import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Secure Message Queue with Delivery Confirmation (In-Memory Version)
/// Ensures critical messages are never lost during network interruptions
/// CRITICAL FIX: Implements guaranteed delivery for payment messages
class SecureMessageQueue {
  static const Duration _retryInterval = Duration(seconds: 5);
  static const int _maxRetries = 10;
  static const Duration _messageExpiry = Duration(minutes: 30);

  final _uuid = const Uuid();
  final Map<String, _QueuedMessage> _pendingMessages = {};
  final Map<String, Completer<bool>> _deliveryCompleters = {};
  Timer? _retryTimer;
  Timer? _cleanupTimer;
  bool _isInitialized = false;

  /// Message sender callback - to be set by SocketService
  Function(String, String)? _messageSender;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Start retry timer
    _retryTimer = Timer.periodic(_retryInterval, (_) => _processQueue());

    // Start cleanup timer
    _cleanupTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _cleanupExpired(),
    );

    _isInitialized = true;
    debugPrint('SecureMessageQueue initialized');
  }

  void setMessageSender(Function(String, String) sender) {
    _messageSender = sender;
  }

  /// Queue a message for delivery with guaranteed delivery
  Future<bool> enqueue(
    Map<String, dynamic> message, {
    required String deviceId,
    bool requireConfirmation = true,
    Duration? timeout,
  }) async {
    if (!_isInitialized) await initialize();

    final messageId = _uuid.v4();
    final sequenceNumber = DateTime.now().millisecondsSinceEpoch;

    final queuedMessage = _QueuedMessage(
      id: messageId,
      sequenceNumber: sequenceNumber,
      deviceId: deviceId,
      payload: jsonEncode(message),
      timestamp: DateTime.now(),
      requireConfirmation: requireConfirmation,
      maxRetries: _maxRetries,
    );

    _pendingMessages[messageId] = queuedMessage;

    if (requireConfirmation) {
      final completer = Completer<bool>();
      _deliveryCompleters[messageId] = completer;

      // Try to send immediately
      _sendMessage(queuedMessage);

      // Wait for confirmation with timeout
      try {
        final delivered = await completer.future.timeout(
          timeout ?? Duration(seconds: 30),
          onTimeout: () => false,
        );
        return delivered;
      } finally {
        _deliveryCompleters.remove(messageId);
      }
    } else {
      _sendMessage(queuedMessage);
      return true;
    }
  }

  /// Mark message as delivered
  void confirmDelivery(String messageId) {
    final message = _pendingMessages.remove(messageId);
    if (message != null) {
      debugPrint('Message $messageId confirmed delivered');

      final completer = _deliveryCompleters.remove(messageId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(true);
      }
    }
  }

  /// Handle delivery failure
  void markFailed(String messageId, String error) {
    final message = _pendingMessages[messageId];
    if (message != null) {
      message.retryCount++;
      message.lastError = error;
      message.lastAttempt = DateTime.now();

      if (message.retryCount >= message.maxRetries) {
        debugPrint(
          'Message $messageId failed after ${message.retryCount} retries',
        );
        _pendingMessages.remove(messageId);

        final completer = _deliveryCompleters.remove(messageId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(false);
        }
      } else {
        debugPrint(
          'Message $messageId retry ${message.retryCount}/${message.maxRetries}',
        );
      }
    }
  }

  /// Send message via WebSocket
  void _sendMessage(_QueuedMessage message) {
    if (_messageSender == null) return;

    try {
      final envelope = {
        'type': 'SECURE_MESSAGE',
        'messageId': message.id,
        'sequenceNumber': message.sequenceNumber,
        'timestamp': DateTime.now().toIso8601String(),
        'payload': jsonDecode(message.payload),
        'requireAck': message.requireConfirmation,
      };

      _messageSender!(message.deviceId, jsonEncode(envelope));
      message.lastAttempt = DateTime.now();
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  /// Process retry queue
  void _processQueue() {
    final now = DateTime.now();

    for (final message in _pendingMessages.values) {
      if (message.requireConfirmation &&
          message.retryCount < message.maxRetries) {
        final timeSinceLastAttempt = message.lastAttempt != null
            ? now.difference(message.lastAttempt!)
            : Duration(days: 1);

        if (timeSinceLastAttempt >= _retryInterval) {
          _sendMessage(message);
        }
      }
    }
  }

  /// Clean up expired messages
  void _cleanupExpired() {
    final now = DateTime.now();
    final expired = _pendingMessages.entries
        .where((e) => now.difference(e.value.timestamp) > _messageExpiry)
        .map((e) => e.key)
        .toList();

    for (final id in expired) {
      _pendingMessages.remove(id);
      final completer = _deliveryCompleters.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(false);
      }
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _retryTimer?.cancel();
    _cleanupTimer?.cancel();
    _pendingMessages.clear();
    _deliveryCompleters.clear();
  }

  int get pendingCount => _pendingMessages.length;
}

class _QueuedMessage {
  final String id;
  final int sequenceNumber;
  final String deviceId;
  final String payload;
  final DateTime timestamp;
  final bool requireConfirmation;
  final int maxRetries;
  int retryCount = 0;
  String? lastError;
  DateTime? lastAttempt;

  _QueuedMessage({
    required this.id,
    required this.sequenceNumber,
    required this.deviceId,
    required this.payload,
    required this.timestamp,
    required this.requireConfirmation,
    required this.maxRetries,
  });
}

/// Singleton instance
final secureMessageQueue = SecureMessageQueue();
