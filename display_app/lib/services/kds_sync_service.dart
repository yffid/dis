import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// KDS Sync Service
/// Syncs kitchen order state to backend API to prevent data loss on restart
/// HIGH RISK FIX: Addresses KDS state loss vulnerability
class KdsSyncService {
  static const String _apiBaseUrl = 'https://api.hermosaapp.com';
  static const Duration _syncInterval = Duration(seconds: 5);
  static const Duration _retryInterval = Duration(seconds: 10);

  String? _authToken;
  String? _branchId;
  Timer? _syncTimer;
  Timer? _retryTimer;
  final Map<String, Map<String, dynamic>> _pendingSync = {};
  final Set<String> _syncingNow = {};
  bool _isInitialized = false;

  /// Initialize the sync service
  Future<void> initialize({
    required String authToken,
    required String branchId,
  }) async {
    if (_isInitialized) return;

    _authToken = authToken;
    _branchId = branchId;

    // Start periodic sync
    _syncTimer = Timer.periodic(_syncInterval, (_) => _processSyncQueue());

    _isInitialized = true;
    debugPrint('KdsSyncService initialized for branch $branchId');
  }

  /// Queue an order for sync
  void queueOrderSync(dynamic order) {
    // Convert order to map
    final orderMap = _orderToMap(order);
    _pendingSync[orderMap['id']] = orderMap;
    debugPrint('Order ${orderMap['id']} queued for sync');

    // Immediate sync attempt
    _syncOrder(orderMap);
  }

  /// Queue item bump for sync
  void queueBumpSync(String orderId, String cartId, bool bumped) {
    final order = _pendingSync[orderId];
    if (order != null) {
      final items = order['items'] as List<dynamic>?;
      if (items != null) {
        for (final item in items) {
          if (item is Map && item['cartId'] == cartId) {
            item['bumped'] = bumped;
            break;
          }
        }
      }
      _syncOrder(order);
    }
  }

  /// Queue status change for sync
  void queueStatusSync(String orderId, String status) {
    final order = _pendingSync[orderId];
    if (order != null) {
      order['status'] = status;
      _syncOrder(order);
    }
  }

  Map<String, dynamic> _orderToMap(dynamic order) {
    // Handle both Map and KitchenOrder object
    if (order is Map<String, dynamic>) {
      return order;
    }

    // Convert KitchenOrder object to map using reflection-like access
    return {
      'id': order.id,
      'orderNumber': order.orderNumber,
      'type': order.type,
      'status': order.status.toString().split('.').last,
      'items': order.items,
      'note': order.note,
      'total': order.total,
      'startTime': order.startTime?.toIso8601String(),
    };
  }

  /// Process sync queue
  void _processSyncQueue() {
    if (_pendingSync.isEmpty) return;

    for (final order in _pendingSync.values) {
      if (!_syncingNow.contains(order['id'])) {
        _syncOrder(order);
      }
    }
  }

  /// Sync a single order to backend
  Future<void> _syncOrder(Map<String, dynamic> order) async {
    if (_authToken == null || _branchId == null) return;
    if (_syncingNow.contains(order['id'])) return;

    _syncingNow.add(order['id']);

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/seller/branches/$_branchId/kds/sync'),
            headers: {
              'Authorization': 'Bearer $_authToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'orderId': order['id'],
              'orderNumber': order['orderNumber'],
              'type': order['type'],
              'status': order['status'],
              'items': order['items'],
              'note': order['note'],
              'total': order['total'],
              'startTime': order['startTime'],
              'syncedAt': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Remove from pending if successfully synced
        _pendingSync.remove(order['id']);
        debugPrint('Order ${order['id']} synced successfully');
      } else {
        debugPrint(
          'Failed to sync order ${order['id']}: ${response.statusCode}',
        );
        _scheduleRetry();
      }
    } catch (e) {
      debugPrint('Error syncing order ${order['id']}: $e');
      _scheduleRetry();
    } finally {
      _syncingNow.remove(order['id']);
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryInterval, _processSyncQueue);
  }

  /// Fetch orders from backend (for recovery after restart)
  Future<List<Map<String, dynamic>>> fetchActiveOrders() async {
    if (_authToken == null || _branchId == null) return [];

    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/seller/branches/$_branchId/kds/active'),
            headers: {
              'Authorization': 'Bearer $_authToken',
              'Accept': 'application/json',
            },
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final orders = (data['orders'] as List).cast<Map<String, dynamic>>();
        debugPrint('Fetched ${orders.length} active orders from backend');
        return orders;
      }
    } catch (e) {
      debugPrint('Error fetching active orders: $e');
    }

    return [];
  }

  /// Dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _isInitialized = false;
    debugPrint('KdsSyncService disposed');
  }
}

/// Singleton instance
final kdsSyncService = KdsSyncService();
