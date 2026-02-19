import 'package:flutter/foundation.dart';
import 'package:flutter_terminal_sdk/flutter_terminal_sdk.dart';
import 'package:flutter_terminal_sdk/models/card_reader_callbacks.dart';
import 'package:flutter_terminal_sdk/models/purchase_callbacks.dart';
import 'package:flutter_terminal_sdk/models/terminal_response.dart';
import 'package:flutter_terminal_sdk/models/terminal_sdk_initialization_listener.dart';
import 'package:flutter_terminal_sdk/models/data/purchase_response.dart';
import 'package:uuid/uuid.dart';
import '../services/nearpay_service.dart';

/// Payment status enumeration
enum PaymentStatus {
  idle,
  initializing,
  authenticating,
  connecting,
  ready,
  waitingCard,
  readingCard,
  enteringPin,
  processing,
  success,
  error,
}

/// NearPay Provider for managing payment state using the real SDK
class NearPayProvider extends ChangeNotifier {
  final NearPayService _nearPayService = NearPayService();
  final FlutterTerminalSdk _sdk = FlutterTerminalSdk();
  final Uuid _uuid = const Uuid();

  PaymentStatus _status = PaymentStatus.idle;
  String? _errorMessage;
  String? _statusMessage;
  TerminalModel? _connectedTerminal;
  PurchaseResponse? _lastPurchaseResponse;
  Map<String, dynamic>? _lastTransaction;
  String? _currentIntentUuid;
  String? _lastSdkErrorRaw;

  // CRITICAL FIX: Payment lock to prevent concurrent payments
  bool _paymentLock = false;
  DateTime? _paymentLockTimestamp;
  static const Duration _paymentLockTimeout = Duration(minutes: 5);

  // Getters
  PaymentStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  TerminalModel? get connectedTerminal => _connectedTerminal;
  PurchaseResponse? get lastPurchaseResponse => _lastPurchaseResponse;
  Map<String, dynamic>? get lastTransaction => _lastTransaction;
  String? get currentIntentUuid => _currentIntentUuid;
  String? get lastSdkErrorRaw => _lastSdkErrorRaw;
  bool get isReady => _status == PaymentStatus.ready;
  bool get isProcessing =>
      _status == PaymentStatus.processing ||
      _status == PaymentStatus.waitingCard ||
      _status == PaymentStatus.readingCard ||
      _status == PaymentStatus.enteringPin;
  bool get isInitialized => _sdk.isInitialized;

  NearPayService get nearPayService => _nearPayService;

  /// Initialize NearPay SDK with the real flutter_terminal_sdk
  Future<void> initialize() async {
    // NearPay terminal plugin works on Android only.
    if (!defaultTargetPlatform.name.toLowerCase().contains('android')) {
      _setError('NearPay SDK يعمل فقط على Android.');
      _setStatus(PaymentStatus.error);
      return;
    }

    if (_sdk.isInitialized) {
      debugPrint('NearPay SDK already initialized');
      _setStatus(PaymentStatus.idle);
      return;
    }

    try {
      _setStatus(PaymentStatus.initializing);
      _clearError();
      _statusMessage = 'جاري تهيئة نظام الدفع...';
      notifyListeners();

      await _sdk.initialize(
        environment: Environment.production,
        googleCloudProjectNumber: 764962961378,
        huaweiSafetyDetectApiKey: '',
        country: Country.sa,
        initializationListener: TerminalSDKInitializationListener(
          onInitializationSuccess: () {
            debugPrint('NearPay SDK initialized successfully via listener');
          },
          onInitializationFailure: (String error) {
            debugPrint(
              'NearPay SDK initialization failed via listener: $error',
            );
            _lastSdkErrorRaw = error;
            final parsed = _friendlySdkError(error);
            _statusMessage = 'فشل تهيئة SDK: ${parsed.message}';
            _setError(_statusMessage!);
            _setStatus(PaymentStatus.error);
            notifyListeners();
          },
        ),
      );

      debugPrint('NearPay SDK initialized successfully');
      _statusMessage = 'تم تهيئة نظام الدفع';
      _setStatus(PaymentStatus.idle);
    } catch (e) {
      debugPrint('Failed to initialize NearPay SDK: $e');
      _lastSdkErrorRaw = e.toString();
      final parsed = _friendlySdkError(e.toString());
      _statusMessage = 'فشل التهيئة: ${parsed.message}';
      _setError(_statusMessage!);
      _setStatus(PaymentStatus.error);
    }
  }

  /// Authenticate with JWT and connect terminal
  Future<void> authenticateWithJwt() async {
    try {
      _setStatus(PaymentStatus.authenticating);
      _clearError();
      _statusMessage = 'جاري المصادقة...';
      notifyListeners();

      // Make sure SDK is initialized first
      if (!_sdk.isInitialized) {
        await initialize();
      }

      if (!_sdk.isInitialized) {
        _setError('NearPay SDK غير مهيأ.');
        _setStatus(PaymentStatus.error);
        return;
      }

      // Generate JWT token
      final jwt = await _nearPayService.generateJwt();
      debugPrint('Generated JWT for NearPay authentication');

      // Login with JWT - this returns a TerminalModel directly
      _statusMessage = 'جاري الاتصال بالتيرمنال...';
      notifyListeners();

      final terminalModel = await _sdk.jwtLogin(jwt: jwt);
      _connectedTerminal = terminalModel;

      debugPrint(
        'Authenticated and connected to terminal: ${terminalModel.tid} (UUID: ${terminalModel.terminalUUID})',
      );
      _statusMessage = 'تم الاتصال بنجاح - TID: ${terminalModel.tid}';
      _setStatus(PaymentStatus.ready);
    } catch (e) {
      debugPrint('Authentication failed: $e');
      _lastSdkErrorRaw = e.toString();
      final parsed = _friendlySdkError(e.toString());
      _setError('فشل المصادقة: ${parsed.message}');
      _setStatus(PaymentStatus.error);
    }
  }

  /// Full initialization + authentication flow
  Future<void> initializeAndAuthenticate() async {
    await initialize();
    await authenticateWithJwt();
  }

  /// CRITICAL FIX: Acquire payment lock with timeout handling
  bool _acquirePaymentLock() {
    // Check if already locked
    if (_paymentLock) {
      // Check if lock has expired (timeout protection)
      if (_paymentLockTimestamp != null) {
        final lockDuration = DateTime.now().difference(_paymentLockTimestamp!);
        if (lockDuration > _paymentLockTimeout) {
          // Lock expired, force release
          debugPrint('Payment lock expired, force releasing');
          _releasePaymentLock();
          _paymentLock = true;
          _paymentLockTimestamp = DateTime.now();
          return true;
        }
      }
      debugPrint('Payment already in progress, cannot start new payment');
      return false;
    }

    _paymentLock = true;
    _paymentLockTimestamp = DateTime.now();
    return true;
  }

  /// Release payment lock
  void _releasePaymentLock() {
    _paymentLock = false;
    _paymentLockTimestamp = null;
  }

  /// Check if payment is locked
  bool get isPaymentLocked => _paymentLock;

  /// Process a purchase transaction using the real SDK
  Future<void> processPurchase({
    required int amount,
    String? customerReferenceNumber,
  }) async {
    // CRITICAL FIX: Prevent concurrent payments
    if (!_acquirePaymentLock()) {
      _setError('عملية دفع أخرى قيد التنفيذ. يرجى الانتظار.');
      _setStatus(PaymentStatus.error);
      return;
    }

    if (_connectedTerminal == null) {
      _setError('Terminal غير متصل. فشل بدء عملية الدفع.');
      _setStatus(PaymentStatus.error);
      _releasePaymentLock();
      return;
    }

    try {
      _setStatus(PaymentStatus.processing);
      _clearError();
      _statusMessage = 'جاري بدء عملية الدفع...';
      _lastPurchaseResponse = null;
      _lastTransaction = null;
      notifyListeners();

      // Generate unique intent UUID
      _currentIntentUuid = _uuid.v4();
      debugPrint(
        'Starting purchase: amount=$amount, intentUUID=$_currentIntentUuid',
      );

      // Create callbacks for real-time updates
      final callbacks = PurchaseCallbacks(
        cardReaderCallbacks: CardReaderCallbacks(
          onReadingStarted: () {
            debugPrint('Card reading started');
            _statusMessage = 'جاري القراءة...';
            _setStatus(PaymentStatus.readingCard);
          },
          onReaderWaiting: () {
            debugPrint('Reader waiting for card');
            _statusMessage = 'اقرب البطاقة أو الجوال';
            _setStatus(PaymentStatus.waitingCard);
          },
          onReaderReading: () {
            debugPrint('Reader reading card');
            _statusMessage = 'جاري قراءة البطاقة...';
            _setStatus(PaymentStatus.readingCard);
          },
          onReaderRetry: () {
            debugPrint('Reader retrying');
            _statusMessage = 'أعد المحاولة - اقرب البطاقة مرة أخرى';
            notifyListeners();
          },
          onPinEntering: () {
            debugPrint('PIN entering');
            _statusMessage = 'أدخل الرقم السري';
            _setStatus(PaymentStatus.enteringPin);
          },
          onReaderFinished: () {
            debugPrint('Reader finished');
            _statusMessage = 'تم قراءة البطاقة بنجاح';
            notifyListeners();
          },
          onReaderError: (String message) {
            debugPrint('Reader error: $message');
            _lastSdkErrorRaw = message;
            _setError('خطأ في القارئ: $message');
            _setStatus(PaymentStatus.error);
          },
          onCardReadSuccess: () {
            debugPrint('Card read successfully');
            _statusMessage = 'تم قراءة البطاقة بنجاح';
            _setStatus(PaymentStatus.processing);
          },
          onCardReadFailure: (String message) {
            debugPrint('Card read failure: $message');
            _lastSdkErrorRaw = message;
            _setError('فشل قراءة البطاقة: $message');
            _setStatus(PaymentStatus.error);
          },
          onReaderDisplayed: () {
            debugPrint('Reader UI displayed');
            _statusMessage = 'اقرب البطاقة أو الجوال';
            _setStatus(PaymentStatus.waitingCard);
          },
          onReaderDismissed: () {
            debugPrint('Reader UI dismissed');
          },
          onReaderClosed: () {
            debugPrint('Reader closed');
          },
        ),
        onSendTransactionFailure: (String message) {
          debugPrint('Transaction failed: $message');
          _lastSdkErrorRaw = message;
          _setError('فشلت العملية: $message');
          _setStatus(PaymentStatus.error);
          // CRITICAL FIX: Release payment lock on failure
          _releasePaymentLock();
        },
        onTransactionPurchaseCompleted: (PurchaseResponse response) {
          debugPrint('Purchase completed: ${response.status}');
          _lastPurchaseResponse = response;

          // Build transaction data map for the socket
          _lastTransaction = {
            'status': response.status,
            'intentUuid': _currentIntentUuid,
            'timestamp': DateTime.now().toIso8601String(),
          };

          // Try to extract transaction details
          final lastTx = response.getLastTransaction();
          if (lastTx != null) {
            _lastTransaction!['transactionId'] = lastTx.id;
            _lastTransaction!['isApproved'] =
                response.status == 'approved' || response.status == 'success';
          }

          _statusMessage = 'تمت العملية بنجاح!';
          _setStatus(PaymentStatus.success);
          // CRITICAL FIX: Release payment lock on completion
          _releasePaymentLock();
        },
      );

      // Call purchase on the connected terminal
      await _connectedTerminal!.purchase(
        intentUUID: _currentIntentUuid!,
        amount: amount,
        callbacks: callbacks,
        customerReferenceNumber: customerReferenceNumber,
      );

      debugPrint('Purchase method called successfully');
    } catch (e) {
      debugPrint('Error in purchase: $e');
      _lastSdkErrorRaw = e.toString();
      final parsed = _friendlySdkError(e.toString());
      _setError('خطأ في عملية الدفع: ${parsed.message}');
      _setStatus(PaymentStatus.error);
      // CRITICAL FIX: Release payment lock on error
      _releasePaymentLock();
    }
  }

  /// Check required permissions using real SDK
  Future<List<Map<String, dynamic>>> checkPermissions() async {
    try {
      if (!_sdk.isInitialized) {
        await initialize();
      }
      final permissions = await _sdk.checkRequiredPermissions();
      return permissions
          .map((p) => {'permission': p.permission, 'isGranted': p.isGranted})
          .toList();
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return [];
    }
  }

  /// Check if NFC is enabled using real SDK
  Future<bool> isNfcEnabled() async {
    try {
      if (!_sdk.isInitialized) {
        return false;
      }
      return await _sdk.isNfcEnabled();
    } catch (e) {
      debugPrint('Error checking NFC: $e');
      return false;
    }
  }

  /// Check if WiFi is enabled using real SDK
  Future<bool> isWifiEnabled() async {
    try {
      if (!_sdk.isInitialized) {
        return false;
      }
      return await _sdk.isWifiEnabled();
    } catch (e) {
      debugPrint('Error checking WiFi: $e');
      return false;
    }
  }

  /// Logout and clear session
  /// HIGH RISK FIX: Check if payment is in progress before logging out
  Future<bool> logout() async {
    try {
      // CRITICAL FIX: Prevent logout during payment
      if (isProcessing) {
        debugPrint('Cannot logout: payment is in progress');
        _setError('لا يمكن تسجيل الخروج أثناء عملية الدفع');
        return false;
      }

      _nearPayService.clearCache();
      _connectedTerminal?.dispose();
      _connectedTerminal = null;
      _lastTransaction = null;
      _lastPurchaseResponse = null;
      _currentIntentUuid = null;
      _statusMessage = null;
      _paymentLock = false;
      _paymentLockTimestamp = null;
      _clearError();
      _setStatus(PaymentStatus.idle);

      debugPrint('Logged out from NearPay');
      return true;
    } catch (e) {
      debugPrint('Logout error: $e');
      return false;
    }
  }

  /// Reset to idle state (ready for next payment)
  /// HIGH RISK FIX: Check if payment is in progress before resetting
  bool reset() {
    // CRITICAL FIX: Prevent reset during payment
    if (isProcessing) {
      debugPrint('Cannot reset: payment is in progress');
      _setError('لا يمكن إعادة التعيين أثناء عملية الدفع');
      return false;
    }

    _clearError();
    _lastTransaction = null;
    _lastPurchaseResponse = null;
    _currentIntentUuid = null;
    _statusMessage = null;
    _paymentLock = false;
    _paymentLockTimestamp = null;

    if (_connectedTerminal != null) {
      _setStatus(PaymentStatus.ready);
    } else {
      _setStatus(PaymentStatus.idle);
    }
    return true;
  }

  /// Helper methods
  void _setStatus(PaymentStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    debugPrint('NearPay Error: $message');
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  _ParsedSdkError _friendlySdkError(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('missingnfcinterfaceerror') ||
        text.contains('nfcnotenabled') ||
        text.contains('nfc')) {
      return const _ParsedSdkError(
        message: 'الجهاز لا يدعم NFC أو NFC مغلق.',
        isNfcIssue: true,
      );
    }
    if (text.contains('missingpluginexception') ||
        text.contains('no implementation found for method initialize') ||
        text.contains('nearpay_plugin')) {
      return const _ParsedSdkError(
        message:
            'NearPay plugin غير مسجل في التطبيق (Plugin registration issue).',
      );
    }
    if (text.contains('permission')) {
      return const _ParsedSdkError(
        message: 'صلاحيات NearPay غير مكتملة على الجهاز.',
      );
    }
    if (text.contains('jwt') || text.contains('auth')) {
      return const _ParsedSdkError(
        message: 'فشل مصادقة NearPay (JWT/Authentication).',
      );
    }
    if (text.contains('network') || text.contains('socket')) {
      return const _ParsedSdkError(
        message: 'مشكلة اتصال شبكة أثناء عملية NearPay.',
      );
    }
    return _ParsedSdkError(message: raw);
  }

  @override
  void dispose() {
    _connectedTerminal?.dispose();
    super.dispose();
  }
}

class _ParsedSdkError {
  final String message;
  final bool isNfcIssue;

  const _ParsedSdkError({required this.message, this.isNfcIssue = false});
}
