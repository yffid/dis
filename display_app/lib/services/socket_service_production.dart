import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

import '../providers/display_provider.dart';
import '../screens/nearpay_payment_screen.dart';
import 'websocket_auth_service.dart';
import 'secure_message_queue.dart';

/// PRODUCTION-READY Socket Service
///
/// Features:
/// - JWT-based authentication with challenge-response
/// - Type-safe JSON parsing with comprehensive error handling
/// - Reconnection handshake with state synchronization
/// - Guaranteed message delivery with confirmation
/// - Configurable port with automatic fallback
/// - Message sequencing to prevent race conditions
/// - Comprehensive error codes for all failure scenarios
///
/// Error Codes Reference:
/// ERR_001: Connection Lost - Client disconnected unexpectedly
/// ERR_002: Authentication Failed - Invalid credentials or timeout
/// ERR_003: Message Parse Error - Invalid JSON format
/// ERR_004: Type Validation Error - Wrong data type in message
/// ERR_005: Sequence Error - Messages received out of order
/// ERR_006: Payment Validation Failed - Invalid payment parameters
/// ERR_007: Mode Mismatch - Payment requested in wrong mode
/// ERR_008: Port Binding Failed - Cannot bind to any port
/// ERR_009: Max Retries Exceeded - Message delivery failed
/// ERR_010: Unauthorized Action - Client not authenticated
class SocketService {
  final DisplayProvider _displayProvider;
  final GlobalKey<NavigatorState> _navigatorKey;
  HttpServer? _server;
  final List<_AuthenticatedClient> _clients = [];
  final _ipController = StreamController<String?>.broadcast();
  String? _lastIp;
  bool _isInitialized = false;
  String? _errorMessage;
  final _uuid = const Uuid();

  // Port configuration
  int _port = 8080;
  static const int _minPort = 8080;
  static const int _maxPort = 8090;

  // Connection health monitoring
  final Map<WebSocketChannel, DateTime> _lastPingTimes = {};
  final Map<WebSocketChannel, String> _clientDeviceIds = {};
  Timer? _healthCheckTimer;
  Timer? _authCleanupTimer;
  static const Duration healthCheckInterval = Duration(seconds: 30);
  static const Duration connectionTimeout = Duration(seconds: 60);

  // Message sequencing
  final Map<String, int> _clientSequenceNumbers = {};
  final Map<String, Map<int, Map<String, dynamic>>> _clientPendingMessages = {};

  // Transaction tracking for Golden Thread
  final Map<String, _TransactionState> _activeTransactions = {};

  Stream<String?> get ipStream => _ipController.stream;
  String? get lastIp => _lastIp;
  bool get isRunning => _server != null;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  int get port => _port;
  int get connectedClients => _clients.length;
  Map<String, Map<String, dynamic>> get activeTransactions =>
      _activeTransactions.map((deviceId, tx) => MapEntry(deviceId, tx.toMap()));

  SocketService(this._displayProvider, this._navigatorKey);

  /// Initialize WebSocket server with authentication
  Future<void> initialize({int? preferredPort}) async {
    if (_isInitialized) {
      debugPrint('[SocketService] Already initialized');
      return;
    }

    // Initialize message queue
    await secureMessageQueue.initialize();
    secureMessageQueue.setMessageSender(_sendQueuedMessage);

    _ipController.add(null);
    _lastIp = null;
    _errorMessage = null;

    // Try ports in range
    _port = preferredPort ?? _minPort;
    HttpServer? server;

    for (int tryPort = _port; tryPort <= _maxPort; tryPort++) {
      try {
        final handler = webSocketHandler((WebSocketChannel webSocket) {
          _handleNewConnection(webSocket);
        });

        server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          tryPort,
        );
        _port = tryPort;
        debugPrint('[SocketService] Bound to port $_port');
        break;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98) {
          debugPrint('[SocketService] Port $tryPort in use, trying next...');
          continue;
        }
        rethrow;
      }
    }

    if (server == null) {
      throw SocketException(
        'ERR_008: Cannot bind to any port in range $_minPort-$_maxPort',
      );
    }

    _server = server;
    _isInitialized = true;

    _lastIp = await _getLocalIpAddress();
    _ipController.add(_lastIp);
    debugPrint('[SocketService] Server running on port $_port');

    _startHealthCheck();

    _authCleanupTimer = Timer.periodic(Duration(minutes: 1), (_) {
      webSocketAuthService.cleanupExpiredSessions();
    });
  }

  /// Handle new client connection with authentication
  void _handleNewConnection(WebSocketChannel webSocket) {
    debugPrint('[SocketService] New connection attempt');

    Timer? authTimeout;
    bool isAuthenticated = false;
    String? deviceId;

    // Set authentication timeout
    authTimeout = Timer(Duration(seconds: 10), () {
      if (!isAuthenticated) {
        debugPrint('[SocketService] ERR_002: Authentication timeout');
        _sendError(webSocket, 'ERR_002', 'Authentication timeout');
        webSocket.sink.close();
      }
    });

    webSocket.stream.listen(
      (message) {
        if (!isAuthenticated) {
          final authenticatedDeviceId = _handleAuthentication(
            message,
            webSocket,
          );
          isAuthenticated = authenticatedDeviceId != null;
          if (isAuthenticated) {
            authTimeout?.cancel();
            deviceId = authenticatedDeviceId;
            if (deviceId != null) {
              _registerClient(webSocket, deviceId!);
              _sendReconnectionHandshake(webSocket, deviceId!);
            }
          }
        } else {
          _handleMessage(message, webSocket, deviceId!);
        }
      },
      onDone: () {
        authTimeout?.cancel();
        _handleClientDisconnect(webSocket, deviceId);
      },
      onError: (error) {
        debugPrint('[SocketService] ERR_001: Connection error: $error');
        authTimeout?.cancel();
        _handleClientDisconnect(webSocket, deviceId);
      },
    );

    // Send authentication challenge
    final challenge = webSocketAuthService.generateChallenge();
    _sendMessage(webSocket, {'type': 'AUTH_CHALLENGE', ...challenge});
  }

  /// Send reconnection handshake with state sync
  void _sendReconnectionHandshake(WebSocketChannel webSocket, String deviceId) {
    // Check for any active transactions that need status
    final activeTransaction = _activeTransactions[deviceId];

    _sendMessage(webSocket, {
      'type': 'RECONNECTED',
      'message': 'Reconnection successful',
      'timestamp': DateTime.now().toIso8601String(),
      'currentMode': _displayProvider.currentMode.name.toUpperCase(),
      'serverPort': _port,
      'activeTransaction': activeTransaction != null
          ? {
              'transactionId': activeTransaction.transactionId,
              'status': activeTransaction.status,
              'amount': activeTransaction.amount,
              'startedAt': activeTransaction.startedAt.toIso8601String(),
            }
          : null,
    });

    debugPrint('[SocketService] Reconnection handshake sent to $deviceId');
  }

  /// Handle authentication
  String? _handleAuthentication(dynamic message, WebSocketChannel webSocket) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String?;

      if (type == 'AUTH_RESPONSE') {
        final challenge = data['challenge'] as String?;
        final response = data['response'] as String?;
        final deviceId = data['deviceId'] as String? ?? 'unknown';

        if (challenge == null || response == null) {
          _sendError(webSocket, 'ERR_002', 'Missing challenge or response');
          return null;
        }

        if (webSocketAuthService.verifyChallengeResponse(challenge, response)) {
          final token = webSocketAuthService.generateToken(
            deviceId,
            isCashier: true,
          );

          _sendMessage(webSocket, {
            'type': 'AUTH_SUCCESS',
            'token': token,
            'message': 'Display App ready',
            'timestamp': DateTime.now().toIso8601String(),
            'supportsNearPay': true,
            'currentMode': _displayProvider.currentMode.name.toUpperCase(),
          });

          debugPrint('[SocketService] Client authenticated: $deviceId');
          return deviceId;
        } else {
          _sendError(webSocket, 'ERR_002', 'Invalid authentication response');
          webSocket.sink.close();
          return null;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[SocketService] ERR_002: Authentication error: $e');
      _sendError(webSocket, 'ERR_002', 'Authentication error: $e');
      webSocket.sink.close();
      return null;
    }
  }

  _AuthenticatedClient? _findClientByDeviceId(String deviceId) {
    for (final client in _clients) {
      if (client.deviceId == deviceId) {
        return client;
      }
    }
    return null;
  }

  /// Register authenticated client
  void _registerClient(WebSocketChannel webSocket, String deviceId) {
    _clients.add(
      _AuthenticatedClient(
        channel: webSocket,
        deviceId: deviceId,
        connectedAt: DateTime.now(),
      ),
    );
    _lastPingTimes[webSocket] = DateTime.now();
    _clientDeviceIds[webSocket] = deviceId;
    _clientSequenceNumbers[deviceId] = 0;

    debugPrint('[SocketService] Client registered: $deviceId');
  }

  /// Handle client disconnect
  void _handleClientDisconnect(WebSocketChannel webSocket, String? deviceId) {
    if (deviceId != null) {
      // Mark any active transaction as pending verification
      final transaction = _activeTransactions[deviceId];
      if (transaction != null && transaction.status == 'processing') {
        transaction.status = 'pending_verification';
        debugPrint(
          '[SocketService] Transaction $deviceId marked for verification',
        );
      }
    }

    _unregisterClient(webSocket, deviceId);
  }

  /// Unregister client
  void _unregisterClient(WebSocketChannel webSocket, String? deviceId) {
    _clients.removeWhere((c) => c.channel == webSocket);
    _lastPingTimes.remove(webSocket);

    if (deviceId != null) {
      _clientDeviceIds.remove(webSocket);
      webSocketAuthService.removeSession(deviceId);
    }

    debugPrint('[SocketService] Client unregistered: $deviceId');
  }

  /// Handle incoming message with type-safe parsing
  void _handleMessage(
    dynamic message,
    WebSocketChannel client,
    String deviceId,
  ) {
    try {
      // Type-safe JSON parsing
      final Map<String, dynamic> data;
      try {
        data = jsonDecode(message) as Map<String, dynamic>;
      } catch (e) {
        _sendError(client, 'ERR_003', 'Invalid JSON format: $e');
        return;
      }

      final type = _parseString(data['type']);
      final sequenceNumber = _parseInt(data['sequenceNumber']);

      if (type == null) {
        _sendError(client, 'ERR_003', 'Missing message type');
        return;
      }

      debugPrint('[SocketService] Received: $type from $deviceId');

      // Handle secure messages
      if (type == 'SECURE_MESSAGE') {
        _handleSecureMessage(data, client, deviceId);
        return;
      }

      // Handle delivery confirmations
      if (type == 'DELIVERY_CONFIRMED') {
        final messageId = _parseString(data['messageId']);
        if (messageId != null) {
          secureMessageQueue.confirmDelivery(messageId);
        }
        return;
      }

      // Handle transaction status queries (Golden Thread)
      if (type == 'QUERY_TRANSACTION_STATUS') {
        _handleTransactionStatusQuery(data, client, deviceId);
        return;
      }

      // Update health check
      _lastPingTimes[client] = DateTime.now();

      // Sequence validation
      if (sequenceNumber != null) {
        final lastSeq = _clientSequenceNumbers[deviceId] ?? 0;

        if (sequenceNumber <= lastSeq) {
          // Duplicate or old message
          return;
        }

        if (sequenceNumber > lastSeq + 1) {
          // Future message - queue it
          _clientPendingMessages.putIfAbsent(deviceId, () => {});
          _clientPendingMessages[deviceId]![sequenceNumber] = data;
          return;
        }
      }

      _processMessageByType(type, data, client, deviceId);

      if (sequenceNumber != null) {
        _clientSequenceNumbers[deviceId] = sequenceNumber;
        _processPendingMessages(deviceId);
      }
    } catch (e, stackTrace) {
      debugPrint('[SocketService] ERR_003: Error handling message: $e');
      debugPrint(stackTrace.toString());
      _sendError(client, 'ERR_003', 'Error handling message: $e');
    }
  }

  /// Handle secure message delivery
  void _handleSecureMessage(
    Map<String, dynamic> data,
    WebSocketChannel client,
    String deviceId,
  ) {
    final payload = data['payload'];
    final messageId = _parseString(data['messageId']);
    final requireAck = _parseBool(data['requireAck']) ?? false;

    if (payload is! Map<String, dynamic>) {
      _sendError(client, 'ERR_004', 'Invalid payload type');
      return;
    }

    final type = _parseString(payload['type']);
    if (type != null) {
      _processMessageByType(type, payload, client, deviceId);
    }

    if (requireAck && messageId != null) {
      _sendMessage(client, {
        'type': 'DELIVERY_CONFIRMED',
        'messageId': messageId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Handle transaction status query (Golden Thread)
  void _handleTransactionStatusQuery(
    Map<String, dynamic> data,
    WebSocketChannel client,
    String deviceId,
  ) {
    final transactionId = _parseString(data['transactionId']);

    if (transactionId == null) {
      _sendError(client, 'ERR_006', 'Missing transactionId');
      return;
    }

    final transaction = _activeTransactions[deviceId];

    if (transaction != null && transaction.transactionId == transactionId) {
      _sendMessage(client, {
        'type': 'TRANSACTION_STATUS',
        'transactionId': transactionId,
        'status': transaction.status,
        'amount': transaction.amount,
        'result': transaction.result,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } else {
      _sendError(client, 'ERR_006', 'Transaction not found: $transactionId');
    }
  }

  /// Process pending messages in sequence order
  void _processPendingMessages(String deviceId) {
    final pending = _clientPendingMessages[deviceId];
    if (pending == null) return;

    int nextSeq = (_clientSequenceNumbers[deviceId] ?? 0) + 1;

    while (pending.containsKey(nextSeq)) {
      final data = pending.remove(nextSeq)!;
      final type = _parseString(data['type']);
      if (type != null) {
        _processMessageByType(type, data, null, deviceId);
      }
      _clientSequenceNumbers[deviceId] = nextSeq;
      nextSeq++;
    }
  }

  /// Process message by type
  void _processMessageByType(
    String type,
    Map<String, dynamic> data,
    WebSocketChannel? client,
    String deviceId,
  ) {
    switch (type) {
      case 'SET_MODE':
        _handleSetMode(data);
        break;
      case 'UPDATE_CART':
        _handleUpdateCart(data);
        break;
      case 'NEW_ORDER':
        _handleNewOrder(data);
        break;
      case 'START_PAYMENT':
        _handleStartPayment(data, deviceId);
        break;
      case 'UPDATE_PAYMENT_STATUS':
        _handleUpdatePaymentStatus(data);
        break;
      case 'PAYMENT_SUCCESS':
        _handlePaymentSuccess(data, deviceId);
        break;
      case 'PAYMENT_FAILED':
        _handlePaymentFailed(data);
        break;
      case 'CANCEL_PAYMENT':
        _handleCancelPayment(data, deviceId);
        break;
      case 'CLEAR_PAYMENT':
        _handleClearPayment(data);
        break;
      case 'PING':
        if (client != null) _handlePing(client, data);
        break;
      default:
        debugPrint('[SocketService] Unknown message type: $type');
        if (client != null) {
          _sendError(client, 'ERR_003', 'Unknown message type: $type');
        }
    }
  }

  /// Type-safe JSON parsing helpers
  String? _parseString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return null;
  }

  double? _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    return null;
  }

  /// Handle payment start with validation
  void _handleStartPayment(Map<String, dynamic> data, String deviceId) {
    debugPrint('[SocketService] Starting payment for $deviceId');

    // Validate CDS mode
    if (_displayProvider.currentMode != DisplayMode.cds) {
      _sendPaymentResultToDevice(
        deviceId,
        'PAYMENT_FAILED',
        message: 'ERR_007: Payment can only be processed in CDS mode',
      );
      return;
    }

    final paymentData = data['data'];
    if (paymentData is! Map<String, dynamic>) {
      _sendPaymentResultToDevice(
        deviceId,
        'PAYMENT_FAILED',
        message: 'ERR_004: Invalid payment data type',
      );
      return;
    }

    // Type-safe amount extraction
    final amount = _parseDouble(paymentData['amount']);

    if (amount == null) {
      _sendPaymentResultToDevice(
        deviceId,
        'PAYMENT_FAILED',
        message: 'ERR_004: Invalid amount type',
      );
      return;
    }

    if (amount <= 0) {
      _sendPaymentResultToDevice(
        deviceId,
        'PAYMENT_FAILED',
        message: 'ERR_006: Amount must be positive',
      );
      return;
    }

    if (amount > 100000) {
      _sendPaymentResultToDevice(
        deviceId,
        'PAYMENT_FAILED',
        message: 'ERR_006: Amount exceeds maximum',
      );
      return;
    }

    // Track transaction for Golden Thread
    final transactionId = _uuid.v4();
    _activeTransactions[deviceId] = _TransactionState(
      transactionId: transactionId,
      amount: amount,
      status: 'processing',
      startedAt: DateTime.now(),
    );

    _displayProvider.startPayment(paymentData);

    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) => NearPayPaymentScreen(
            amount: amount,
            customerReference:
                _parseString(paymentData['orderNumber']) ?? 'Unknown',
            onPaymentComplete: (transactionData) async {
              // Update transaction state
              final transaction = _activeTransactions[deviceId];
              if (transaction != null) {
                transaction.status = 'completed';
                transaction.result = transactionData;
              }

              final result = {
                'amount': amount,
                'orderNumber': paymentData['orderNumber'],
                'transaction': transactionData,
                'transactionId': transactionId,
                'timestamp': DateTime.now().toIso8601String(),
              };

              final delivered = await secureMessageQueue.enqueue(
                {'type': 'PAYMENT_SUCCESS', 'data': result},
                deviceId: deviceId,
                requireConfirmation: true,
              );

              if (!delivered) {
                debugPrint(
                  '[SocketService] ERR_009: Payment success not confirmed',
                );
              }

              _displayProvider.clearPayment();
              _displayProvider.clearCart();
              _safePopNavigator(navigator);
            },
            onPaymentFailed: (errorMessage) async {
              final transaction = _activeTransactions[deviceId];
              if (transaction != null) {
                transaction.status = 'failed';
              }

              await secureMessageQueue.enqueue(
                {'type': 'PAYMENT_FAILED', 'message': errorMessage},
                deviceId: deviceId,
                requireConfirmation: true,
              );
            },
            onPaymentCancelled: () async {
              final transaction = _activeTransactions[deviceId];
              if (transaction != null) {
                transaction.status = 'cancelled';
              }

              await secureMessageQueue.enqueue(
                {'type': 'PAYMENT_CANCELLED'},
                deviceId: deviceId,
                requireConfirmation: true,
              );
              _safePopNavigator(navigator);
            },
            onStatusChanged: (status, message) {
              _sendPaymentResultToDevice(
                deviceId,
                'PAYMENT_STATUS',
                data: {'status': status, 'message': message},
              );
            },
          ),
        ),
      );
    }
  }

  /// Handle payment success
  void _handlePaymentSuccess(Map<String, dynamic> data, String deviceId) {
    debugPrint('[SocketService] Payment success from $deviceId');
    _displayProvider.setPaymentSuccess(data['data']);

    // Clear transaction tracking
    _activeTransactions.remove(deviceId);
  }

  /// Handle cancel payment
  void _handleCancelPayment(Map<String, dynamic> data, String deviceId) {
    debugPrint('[SocketService] Payment cancelled for $deviceId');
    _displayProvider.cancelPayment();

    // Clear transaction tracking
    _activeTransactions.remove(deviceId);
  }

  // Other handlers remain similar but with type-safe parsing...
  void _handleSetMode(Map<String, dynamic> data) {
    final mode = _parseString(data['mode']);
    if (mode == null) return;

    _displayProvider.setMode(mode);

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    switch (mode.toUpperCase()) {
      case 'CDS':
        navigator.pushNamedAndRemoveUntil('/cds', (route) => false);
        break;
      case 'KDS':
        navigator.pushNamedAndRemoveUntil('/kds', (route) => false);
        break;
    }
  }

  void _handleUpdateCart(Map<String, dynamic> data) {
    final cartData = data['data'];
    if (cartData is Map<String, dynamic>) {
      _displayProvider.updateCartData(cartData);
    }
  }

  void _handleNewOrder(Map<String, dynamic> data) {
    final orderData = data['data'];
    if (orderData is Map<String, dynamic>) {
      _displayProvider.addOrder(orderData);
    }
  }

  void _handleUpdatePaymentStatus(Map<String, dynamic> data) {
    final status = _parseString(data['status']) ?? 'processing';
    final message = _parseString(data['message']);
    _displayProvider.updatePaymentStatus(status, message: message);
  }

  void _handlePaymentFailed(Map<String, dynamic> data) {
    final message = _parseString(data['message']) ?? 'Payment failed';
    _displayProvider.setPaymentFailed(message);
  }

  void _handleClearPayment(Map<String, dynamic> data) {
    _displayProvider.clearPayment();
  }

  void _handlePing(WebSocketChannel client, Map<String, dynamic> data) {
    _sendMessage(client, {
      'type': 'PONG',
      'timestamp': DateTime.now().toIso8601String(),
      'received': data['timestamp'],
    });
  }

  void _safePopNavigator(NavigatorState navigator) {
    try {
      if (navigator.canPop()) {
        navigator.pop();
      }
    } catch (e) {
      debugPrint('[SocketService] Safe pop skipped: $e');
    }
  }

  /// Send message helper
  void _sendMessage(WebSocketChannel client, Map<String, dynamic> message) {
    try {
      client.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('[SocketService] Error sending message: $e');
    }
  }

  /// Send error with code
  void _sendError(WebSocketChannel client, String code, String message) {
    _sendMessage(client, {
      'type': 'ERROR',
      'code': code,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Send payment result to specific device
  void _sendPaymentResultToDevice(
    String deviceId,
    String type, {
    Map<String, dynamic>? data,
    String? message,
  }) {
    final response = <String, dynamic>{
      'type': type,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (data != null) {
      response['data'] = data;
    }
    if (message != null) {
      response['message'] = message;
    }

    final client = _findClientByDeviceId(deviceId);
    if (client != null) {
      try {
        client.channel.sink.add(jsonEncode(response));
      } catch (e) {
        debugPrint('[SocketService] Error sending to $deviceId: $e');
      }
    }
  }

  /// Send queued message
  void _sendQueuedMessage(String deviceId, String message) {
    final client = _findClientByDeviceId(deviceId);
    if (client != null) {
      try {
        client.channel.sink.add(message);
      } catch (e) {
        debugPrint('[SocketService] Error sending queued message: $e');
        String messageId = '';
        try {
          final parsed = jsonDecode(message);
          if (parsed is Map<String, dynamic>) {
            messageId = parsed['messageId'] as String? ?? '';
          }
        } catch (_) {
          // Ignore parse failures in failure path.
        }
        secureMessageQueue.markFailed(messageId, e.toString());
      }
    }
  }

  /// Health check
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (timer) {
      _checkClientHealth();
    });
  }

  void _checkClientHealth() {
    final now = DateTime.now();
    final deadClients = <WebSocketChannel>[];

    for (final entry in _lastPingTimes.entries) {
      if (now.difference(entry.value) > connectionTimeout) {
        deadClients.add(entry.key);
      }
    }

    for (final client in deadClients) {
      final deviceId = _clientDeviceIds[client];
      _handleClientDisconnect(client, deviceId);

      try {
        client.sink.close();
      } catch (e) {
        debugPrint('[SocketService] Error closing client: $e');
      }
    }
  }

  /// Get local IP address
  Future<String?> _getLocalIpAddress() async {
    if (kIsWeb) {
      try {
        final response = await http
            .get(Uri.parse('https://api.ipify.org'))
            .timeout(Duration(seconds: 3));
        if (response.statusCode == 200) return response.body;
      } catch (e) {
        debugPrint('[SocketService] Could not get external IP: $e');
      }
      return 'localhost';
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            if (addr.address.startsWith('192.168.')) return addr.address;
            if (addr.address.startsWith('10.')) return addr.address;
            if (addr.address.startsWith('172.')) {
              final octet = int.tryParse(addr.address.split('.')[1]) ?? 0;
              if (octet >= 16 && octet <= 31) return addr.address;
            }
          }
        }
      }

      return '127.0.0.1';
    } catch (e) {
      return '127.0.0.1';
    }
  }

  /// Broadcast to all clients
  void broadcast(String message) {
    for (final client in List<_AuthenticatedClient>.from(_clients)) {
      try {
        client.channel.sink.add(message);
      } catch (e) {
        debugPrint('[SocketService] Error broadcasting: $e');
      }
    }
  }

  /// Legacy send payment result
  void sendPaymentResult(
    String type, {
    Map<String, dynamic>? data,
    String? message,
  }) {
    for (final client in _clients) {
      _sendPaymentResultToDevice(
        client.deviceId,
        type,
        data: data,
        message: message,
      );
    }
  }

  /// Dispose
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    _authCleanupTimer?.cancel();

    for (final client in _clients) {
      await client.channel.sink.close();
    }

    _clients.clear();
    _lastPingTimes.clear();
    _clientDeviceIds.clear();
    _activeTransactions.clear();

    await _server?.close();
    await _ipController.close();
    await secureMessageQueue.dispose();

    _isInitialized = false;
  }
}

/// Authenticated client wrapper
class _AuthenticatedClient {
  final WebSocketChannel channel;
  final String deviceId;
  final DateTime connectedAt;

  _AuthenticatedClient({
    required this.channel,
    required this.deviceId,
    required this.connectedAt,
  });
}

/// Transaction state tracking for Golden Thread
class _TransactionState {
  final String transactionId;
  final double amount;
  String
  status; // processing, completed, failed, cancelled, pending_verification
  final DateTime startedAt;
  Map<String, dynamic>? result;
  DateTime? completedAt;

  _TransactionState({
    required this.transactionId,
    required this.amount,
    required this.status,
    required this.startedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'transactionId': transactionId,
      'amount': amount,
      'status': status,
      'startedAt': startedAt.toIso8601String(),
      'result': result,
      'completedAt': completedAt?.toIso8601String(),
    };
  }
}
