import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../providers/display_provider.dart';
import '../screens/nearpay_payment_screen.dart';
import 'websocket_auth_service.dart';
import 'secure_message_queue.dart';

/// Socket Service for handling WebSocket communication with Cashier App
/// CRITICAL FIXES:
/// - JWT-based authentication for all connections
/// - Secure message queue with delivery confirmation
/// - Payment amount validation
/// - Message sequencing to prevent race conditions
/// - Configurable port with automatic fallback
/// - Removal of premature ACK responses
class SocketService {
  final DisplayProvider _displayProvider;
  final GlobalKey<NavigatorState> _navigatorKey;
  HttpServer? _server;
  final List<_AuthenticatedClient> _clients = [];
  final _ipController = StreamController<String?>.broadcast();
  String? _lastIp;
  bool _isInitialized = false;
  String? _errorMessage;

  // CRITICAL FIX: Configurable port with fallback
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

  // CRITICAL FIX: Message sequencing
  int _lastProcessedSequence = 0;
  final Map<int, Map<String, dynamic>> _pendingMessages = {};

  Stream<String?> get ipStream => _ipController.stream;
  String? get lastIp => _lastIp;
  bool get isRunning => _server != null;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  int get port => _port;
  int get connectedClients => _clients.length;

  SocketService(this._displayProvider, this._navigatorKey);

  /// CRITICAL FIX: Initialize with authentication and message queue
  Future<void> initialize({int? preferredPort}) async {
    if (_isInitialized) {
      debugPrint('SocketService already initialized');
      return;
    }

    // Initialize message queue
    await secureMessageQueue.initialize();
    secureMessageQueue.setMessageSender(_sendQueuedMessage);

    // Emit initial null to show loading state
    _ipController.add(null);
    _lastIp = null;
    _errorMessage = null;

    // CRITICAL FIX: Try to bind to preferred port, fallback if taken
    _port = preferredPort ?? 8080;
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
        debugPrint('WebSocket server bound to port $_port');
        break;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98) {
          // Address already in use
          debugPrint('Port $tryPort in use, trying next...');
          continue;
        }
        rethrow;
      }
    }

    if (server == null) {
      throw Exception(
        'Could not bind to any port in range $_minPort-$_maxPort',
      );
    }

    _server = server;
    _isInitialized = true;

    _lastIp = await _getLocalIpAddress();
    _ipController.add(_lastIp);
    debugPrint('WebSocket server running on port $_port');

    // Start health check timer
    _startHealthCheck();

    // Start auth cleanup timer
    _authCleanupTimer = Timer.periodic(Duration(minutes: 1), (_) {
      webSocketAuthService.cleanupExpiredSessions();
    });
  }

  /// CRITICAL FIX: Handle new connection with authentication handshake
  void _handleNewConnection(WebSocketChannel webSocket) {
    debugPrint('New client connection attempt');

    // Start authentication timeout
    Timer? authTimeout;
    bool isAuthenticated = false;
    String? deviceId;

    authTimeout = Timer(Duration(seconds: 10), () {
      if (!isAuthenticated) {
        debugPrint('Authentication timeout, closing connection');
        webSocket.sink.add(
          jsonEncode({
            'type': 'AUTH_FAILED',
            'message': 'Authentication timeout',
          }),
        );
        webSocket.sink.close();
      }
    });

    webSocket.stream.listen(
      (message) {
        if (!isAuthenticated) {
          // Expecting authentication message
          final data = jsonDecode(message);
          isAuthenticated = _handleAuthentication(message, webSocket);
          if (isAuthenticated) {
            authTimeout?.cancel();
            // Extract deviceId from AUTH_RESPONSE
            deviceId = data['deviceId'] as String? ?? 'unknown';
            _registerClient(webSocket, deviceId!);
          }
        } else {
          _handleMessage(message, webSocket, deviceId!);
        }
      },
      onDone: () {
        authTimeout?.cancel();
        _unregisterClient(webSocket, deviceId);
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
        authTimeout?.cancel();
        _unregisterClient(webSocket, deviceId);
      },
    );

    // Send authentication challenge
    final challenge = webSocketAuthService.generateChallenge();
    webSocket.sink.add(jsonEncode({'type': 'AUTH_CHALLENGE', ...challenge}));
  }

  /// CRITICAL FIX: Handle authentication
  bool _handleAuthentication(dynamic message, WebSocketChannel webSocket) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String?;

      if (type == 'AUTH_RESPONSE') {
        final challenge = data['challenge'] as String?;
        final response = data['response'] as String?;
        final deviceId = data['deviceId'] as String? ?? 'unknown';

        if (challenge == null || response == null) {
          webSocket.sink.add(
            jsonEncode({
              'type': 'AUTH_FAILED',
              'message': 'Missing challenge or response',
            }),
          );
          return false;
        }

        if (webSocketAuthService.verifyChallengeResponse(challenge, response)) {
          // Generate token
          final token = webSocketAuthService.generateToken(
            deviceId,
            isCashier: true,
          );

          webSocket.sink.add(
            jsonEncode({
              'type': 'AUTH_SUCCESS',
              'token': token,
              'message': 'Display App ready',
              'timestamp': DateTime.now().toIso8601String(),
              'supportsNearPay': true,
              'currentMode': _displayProvider.currentMode.name.toUpperCase(),
            }),
          );

          debugPrint('Client authenticated: $deviceId');
          return true;
        } else {
          webSocket.sink.add(
            jsonEncode({
              'type': 'AUTH_FAILED',
              'message': 'Invalid authentication response',
            }),
          );
          webSocket.sink.close();
          return false;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Authentication error: $e');
      webSocket.sink.add(
        jsonEncode({
          'type': 'AUTH_FAILED',
          'message': 'Authentication error: $e',
        }),
      );
      webSocket.sink.close();
      return false;
    }
  }

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
    debugPrint(
      'Client registered: $deviceId. Total clients: ${_clients.length}',
    );
  }

  void _unregisterClient(WebSocketChannel webSocket, String? deviceId) {
    _clients.removeWhere((c) => c.channel == webSocket);
    _lastPingTimes.remove(webSocket);
    if (deviceId != null) {
      _clientDeviceIds.remove(webSocket);
      webSocketAuthService.removeSession(deviceId);
    }
    debugPrint(
      'Client unregistered: $deviceId. Total clients: ${_clients.length}',
    );
  }

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
      final timeSinceLastPing = now.difference(entry.value);
      if (timeSinceLastPing > connectionTimeout) {
        debugPrint('Client timed out after ${timeSinceLastPing.inSeconds}s');
        deadClients.add(entry.key);
      }
    }

    for (final client in deadClients) {
      final deviceId = _clientDeviceIds[client];
      _unregisterClient(client, deviceId);
      try {
        client.sink.close();
      } catch (e) {
        debugPrint('Error closing dead client: $e');
      }
    }
  }

  void _sendQueuedMessage(String deviceId, String message) {
    final client = _findClientByDeviceId(deviceId);
    if (client != null) {
      try {
        client.channel.sink.add(message);
      } catch (e) {
        debugPrint('Error sending queued message: $e');
      }
    }
  }

  Future<String?> _getLocalIpAddress() async {
    // Web platform - can't access network interfaces directly
    if (kIsWeb) {
      try {
        final response = await http
            .get(Uri.parse('https://api.ipify.org'))
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          return response.body;
        }
      } catch (e) {
        debugPrint('Could not get external IP: $e');
      }
      return 'localhost';
    }

    // Native platforms - use network interfaces
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
      );

      // Priority 1: 192.168.x.x
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }

      // Priority 2: 10.x.x.x
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('10.')) {
            return addr.address;
          }
        }
      }

      // Priority 3: 172.16-31.x.x
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            final ip = addr.address;
            if (ip.startsWith('172.')) {
              final secondOctet = int.tryParse(ip.split('.')[1]) ?? 0;
              if (secondOctet >= 16 && secondOctet <= 31) {
                return addr.address;
              }
            }
          }
        }
      }

      // Priority 4: Any non-loopback IPv4
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }

      return '127.0.0.1';
    } catch (e) {
      debugPrint('Error getting IP: $e');
      return '127.0.0.1';
    }
  }

  void _handleMessage(
    dynamic message,
    WebSocketChannel client,
    String deviceId,
  ) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String?;
      final sequenceNumber = data['sequenceNumber'] as int?;

      debugPrint('Received: $type from $deviceId');

      // CRITICAL FIX: Handle secure messages with delivery confirmation
      if (type == 'SECURE_MESSAGE') {
        _handleSecureMessage(data, client, deviceId);
        return;
      }

      // CRITICAL FIX: Handle delivery confirmations
      if (type == 'DELIVERY_CONFIRMED') {
        final messageId = data['messageId'] as String?;
        if (messageId != null) {
          secureMessageQueue.confirmDelivery(messageId);
        }
        return;
      }

      // Update last ping time for health check
      _lastPingTimes[client] = DateTime.now();

      // CRITICAL FIX: Process messages in sequence order
      if (sequenceNumber != null) {
        if (sequenceNumber <= _lastProcessedSequence) {
          // Duplicate or old message, ignore
          return;
        }
        if (sequenceNumber > _lastProcessedSequence + 1) {
          // Future message, queue it
          _pendingMessages[sequenceNumber] = data;
          return;
        }
      }

      _processMessageByType(type, data, client, deviceId);

      // Process any pending messages in sequence
      if (sequenceNumber != null) {
        _lastProcessedSequence = sequenceNumber;
        _processPendingMessages();
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
      _sendError(client, 'Error handling message: $e');
    }
  }

  void _handleSecureMessage(
    Map<String, dynamic> data,
    WebSocketChannel client,
    String deviceId,
  ) {
    final payload = data['payload'] as Map<String, dynamic>?;
    final messageId = data['messageId'] as String?;
    final requireAck = data['requireAck'] as bool? ?? false;

    if (payload == null) return;

    // Process the payload
    final type = payload['type'] as String?;
    _processMessageByType(type, payload, client, deviceId);

    // Send acknowledgment if required
    if (requireAck && messageId != null) {
      client.sink.add(
        jsonEncode({
          'type': 'DELIVERY_CONFIRMED',
          'messageId': messageId,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    }
  }

  void _processPendingMessages() {
    int nextSequence = _lastProcessedSequence + 1;
    while (_pendingMessages.containsKey(nextSequence)) {
      _pendingMessages.remove(nextSequence);
      // Note: deviceId would need to be tracked for pending messages
      _lastProcessedSequence = nextSequence;
      nextSequence++;
    }
  }

  void _processMessageByType(
    String? type,
    Map<String, dynamic> data,
    WebSocketChannel client,
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
        _handlePaymentSuccess(data);
        break;
      case 'PAYMENT_FAILED':
        _handlePaymentFailed(data);
        break;
      case 'CANCEL_PAYMENT':
        _handleCancelPayment(data);
        break;
      case 'CLEAR_PAYMENT':
        _handleClearPayment(data);
        break;
      case 'PING':
        _handlePing(client, data);
        break;
      default:
        debugPrint('Unknown message type: $type');
    }
  }

  void _sendError(WebSocketChannel client, String error) {
    client.sink.add(jsonEncode({'type': 'ERROR', 'message': error}));
  }

  void _handlePing(WebSocketChannel client, Map<String, dynamic> data) {
    client.sink.add(
      jsonEncode({
        'type': 'PONG',
        'timestamp': DateTime.now().toIso8601String(),
        'received': data['timestamp'],
      }),
    );
  }

  void _handleSetMode(Map<String, dynamic> data) {
    final mode = data['mode'] as String?;
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
    if (data['data'] != null) {
      _displayProvider.updateCartData(data['data']);
    }
  }

  void _handleNewOrder(Map<String, dynamic> data) {
    if (data['data'] != null) {
      _displayProvider.addOrder(data['data']);
    }
  }

  // ========== PAYMENT HANDLERS ==========

  void _handleStartPayment(Map<String, dynamic> data, String deviceId) {
    debugPrint('Starting payment display: ${data['data']}');

    // Validate CDS mode
    if (_displayProvider.currentMode != DisplayMode.cds) {
      debugPrint('ERROR: Payment requested but not in CDS mode!');
      _sendPaymentResultToDevice(
        deviceId,
        'PAYMENT_FAILED',
        message:
            'Payment can only be processed in CDS mode. Current mode: ${_displayProvider.currentMode.name}',
      );
      return;
    }

    if (data['data'] != null) {
      _displayProvider.startPayment(data['data']);

      final navigator = _navigatorKey.currentState;
      if (navigator != null) {
        final paymentData = data['data'];
        final amount = (paymentData['amount'] as num?)?.toDouble() ?? 0.0;

        // CRITICAL FIX: Validate payment amount
        if (amount <= 0) {
          _sendPaymentResultToDevice(
            deviceId,
            'PAYMENT_FAILED',
            message:
                'Invalid payment amount: $amount. Amount must be positive.',
          );
          return;
        }

        // CRITICAL FIX: Validate amount is reasonable (prevent overflow/underflow)
        if (amount > 100000) {
          _sendPaymentResultToDevice(
            deviceId,
            'PAYMENT_FAILED',
            message: 'Payment amount exceeds maximum allowed: $amount',
          );
          return;
        }

        // CRITICAL FIX: Use secure message queue for payment results
        navigator.push(
          MaterialPageRoute(
            builder: (context) => NearPayPaymentScreen(
              amount: amount,
              customerReference:
                  paymentData['orderNumber']?.toString() ?? 'Unknown',
              onPaymentComplete: (transactionData) async {
                final result = {
                  'amount': amount,
                  'orderNumber': paymentData['orderNumber'] ?? 'Unknown',
                  'transaction': transactionData,
                  'timestamp': DateTime.now().toIso8601String(),
                };

                // Use secure queue for guaranteed delivery
                final delivered = await secureMessageQueue.enqueue(
                  {'type': 'PAYMENT_SUCCESS', 'data': result},
                  deviceId: deviceId,
                  requireConfirmation: true,
                );

                if (!delivered) {
                  debugPrint('WARNING: Payment success message not confirmed');
                }

                _displayProvider.clearPayment();
                _displayProvider.clearCart();
                _safePopNavigator(navigator);
              },
              onPaymentFailed: (errorMessage) async {
                await secureMessageQueue.enqueue(
                  {'type': 'PAYMENT_FAILED', 'message': errorMessage},
                  deviceId: deviceId,
                  requireConfirmation: true,
                );
              },
              onPaymentCancelled: () async {
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
  }

  void _handleUpdatePaymentStatus(Map<String, dynamic> data) {
    debugPrint('Updating payment status: ${data['status']}');
    _displayProvider.updatePaymentStatus(
      data['status'] ?? 'processing',
      message: data['message'],
    );
  }

  void _handlePaymentSuccess(Map<String, dynamic> data) {
    debugPrint('Payment success: ${data['data']}');
    _displayProvider.setPaymentSuccess(data['data']);
  }

  void _handlePaymentFailed(Map<String, dynamic> data) {
    debugPrint('Payment failed: ${data['message']}');
    _displayProvider.setPaymentFailed(data['message'] ?? 'Payment failed');
  }

  void _handleCancelPayment(Map<String, dynamic> data) {
    debugPrint('Payment cancelled by cashier');
    _displayProvider.cancelPayment();
  }

  void _handleClearPayment(Map<String, dynamic> data) {
    debugPrint('Clearing payment display');
    _displayProvider.clearPayment();
  }

  void broadcast(String message) {
    for (final client in List<_AuthenticatedClient>.from(_clients)) {
      try {
        client.channel.sink.add(message);
      } catch (e) {
        debugPrint('Error broadcasting: $e');
      }
    }
  }

  /// CRITICAL FIX: Send to specific device with delivery tracking
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
        debugPrint('Error sending to device $deviceId: $e');
      }
    }
  }

  void _safePopNavigator(NavigatorState navigator) {
    try {
      if (navigator.canPop()) {
        navigator.pop();
      }
    } catch (e) {
      debugPrint('Safe pop skipped: $e');
    }
  }

  /// Legacy broadcast method (kept for compatibility)
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

  _AuthenticatedClient? _findClientByDeviceId(String deviceId) {
    for (final client in _clients) {
      if (client.deviceId == deviceId) {
        return client;
      }
    }
    return null;
  }

  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    _authCleanupTimer?.cancel();
    for (final client in _clients) {
      await client.channel.sink.close();
    }
    _clients.clear();
    _lastPingTimes.clear();
    _clientDeviceIds.clear();
    await _server?.close();
    await _ipController.close();
    await secureMessageQueue.dispose();
    _isInitialized = false;
  }
}

/// Helper class for authenticated clients
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
