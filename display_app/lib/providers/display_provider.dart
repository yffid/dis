import 'package:flutter/foundation.dart';

enum DisplayMode { none, cds, kds }

enum PaymentDisplayStatus { idle, processing, success, failed, cancelled }

class DisplayProvider extends ChangeNotifier {
  DisplayMode _currentMode = DisplayMode.none;
  Map<String, dynamic> _cartData = {};
  final List<Map<String, dynamic>> _orders = [];
  int _nextPendingOrderIndex = 0;
  String? _statusMessage;

  // Payment state
  PaymentDisplayStatus _paymentStatus = PaymentDisplayStatus.idle;
  Map<String, dynamic> _paymentData = {};
  String? _paymentMessage;
  Map<String, dynamic>? _transactionData;

  DisplayMode get currentMode => _currentMode;
  Map<String, dynamic> get cartData => _cartData;
  List<Map<String, dynamic>> get orders => List.unmodifiable(_orders);
  String? get statusMessage => _statusMessage;

  // Payment getters
  PaymentDisplayStatus get paymentStatus => _paymentStatus;
  Map<String, dynamic> get paymentData => _paymentData;
  String? get paymentMessage => _paymentMessage;
  Map<String, dynamic>? get transactionData => _transactionData;
  bool get isShowingPayment => _paymentStatus != PaymentDisplayStatus.idle;
  bool get isPaymentProcessing =>
      _paymentStatus == PaymentDisplayStatus.processing;
  bool get isPaymentSuccess => _paymentStatus == PaymentDisplayStatus.success;
  bool get isPaymentFailed => _paymentStatus == PaymentDisplayStatus.failed;

  void setMode(String mode) {
    switch (mode.toUpperCase()) {
      case 'CDS':
        _currentMode = DisplayMode.cds;
        _statusMessage = 'Customer Display Mode Active';
        break;
      case 'KDS':
        _currentMode = DisplayMode.kds;
        _statusMessage = 'Kitchen Display Mode Active';
        break;
      default:
        _currentMode = DisplayMode.none;
        _statusMessage = 'Unknown mode: $mode';
    }
    notifyListeners();
  }

  void updateCartData(Map<String, dynamic> data) {
    _cartData = Map<String, dynamic>.from(data);
    notifyListeners();
  }

  void addOrder(Map<String, dynamic> orderData) {
    _orders.add(Map<String, dynamic>.from(orderData));
    notifyListeners();
  }

  /// Drain pending orders in FIFO order without dropping burst events.
  List<Map<String, dynamic>> drainPendingOrders() {
    if (_nextPendingOrderIndex >= _orders.length) {
      return const [];
    }
    final pending = _orders
        .sublist(_nextPendingOrderIndex)
        .map((order) => Map<String, dynamic>.from(order))
        .toList(growable: false);
    _nextPendingOrderIndex = _orders.length;
    return pending;
  }

  void removeOrder(String orderId) {
    _orders.removeWhere((order) => order['id'] == orderId);
    if (_nextPendingOrderIndex > _orders.length) {
      _nextPendingOrderIndex = _orders.length;
    }
    notifyListeners();
  }

  void clearOrders() {
    _orders.clear();
    _nextPendingOrderIndex = 0;
    notifyListeners();
  }

  void clearCart() {
    _cartData = {};
    notifyListeners();
  }

  // ========== PAYMENT METHODS ==========

  /// Start showing payment UI
  void startPayment(Map<String, dynamic> data) {
    _paymentStatus = PaymentDisplayStatus.processing;
    _paymentData = Map<String, dynamic>.from(data);
    _paymentMessage = null;
    _transactionData = null;
    debugPrint(
      'Display: Starting payment - ${data['amount']} ${data['orderNumber']}',
    );
    notifyListeners();
  }

  /// Update payment status during processing
  void updatePaymentStatus(String status, {String? message}) {
    switch (status.toLowerCase()) {
      case 'processing':
        _paymentStatus = PaymentDisplayStatus.processing;
        break;
      case 'waiting_card':
      case 'reading':
        _paymentStatus = PaymentDisplayStatus.processing;
        break;
      case 'pin_entry':
        _paymentStatus = PaymentDisplayStatus.processing;
        break;
      case 'success':
        _paymentStatus = PaymentDisplayStatus.success;
        break;
      case 'failed':
      case 'error':
        _paymentStatus = PaymentDisplayStatus.failed;
        break;
      case 'cancelled':
        _paymentStatus = PaymentDisplayStatus.cancelled;
        break;
    }
    _paymentMessage = message;
    debugPrint('Display: Payment status updated to $status');
    notifyListeners();
  }

  /// Mark payment as successful
  void setPaymentSuccess(Map<String, dynamic>? data) {
    _paymentStatus = PaymentDisplayStatus.success;
    _transactionData = data != null ? Map<String, dynamic>.from(data) : null;
    _paymentMessage = null;
    debugPrint('Display: Payment success - $data');
    notifyListeners();
  }

  /// Mark payment as failed
  void setPaymentFailed(String errorMessage) {
    _paymentStatus = PaymentDisplayStatus.failed;
    _paymentMessage = errorMessage;
    debugPrint('Display: Payment failed - $errorMessage');
    notifyListeners();
  }

  /// Cancel payment
  void cancelPayment() {
    _paymentStatus = PaymentDisplayStatus.cancelled;
    _paymentMessage = 'Payment cancelled';
    debugPrint('Display: Payment cancelled');
    notifyListeners();
  }

  /// Clear payment and return to cart view
  void clearPayment() {
    _paymentStatus = PaymentDisplayStatus.idle;
    _paymentData = {};
    _paymentMessage = null;
    _transactionData = null;
    debugPrint('Display: Payment cleared');
    notifyListeners();
  }

  void reset() {
    _currentMode = DisplayMode.none;
    _cartData = {};
    _orders.clear();
    _nextPendingOrderIndex = 0;
    _statusMessage = null;
    _paymentStatus = PaymentDisplayStatus.idle;
    _paymentData = {};
    _paymentMessage = null;
    _transactionData = null;
    notifyListeners();
  }
}
