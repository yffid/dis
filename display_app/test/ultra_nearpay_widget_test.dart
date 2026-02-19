import 'package:display_app/providers/nearpay_provider.dart';
import 'package:display_app/screens/nearpay_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakeNearPayProvider extends NearPayProvider {
  PaymentStatus _status = PaymentStatus.idle;
  String? _errorMessage;
  String? _statusMessage;
  bool _isInitialized = true;
  bool _isReady = false;
  Map<String, dynamic>? _lastTransaction;
  String? _currentIntentUuid = 'ULTRA-INTENT-001';

  int initializeCalls = 0;
  int processPurchaseCalls = 0;
  int resetCalls = 0;

  int? lastPurchaseAmount;
  String? lastCustomerReference;

  @override
  PaymentStatus get status => _status;

  @override
  String? get errorMessage => _errorMessage;

  @override
  String? get statusMessage => _statusMessage;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isReady => _isReady;

  @override
  bool get isProcessing =>
      _status == PaymentStatus.processing ||
      _status == PaymentStatus.waitingCard ||
      _status == PaymentStatus.readingCard ||
      _status == PaymentStatus.enteringPin;

  @override
  Map<String, dynamic>? get lastTransaction => _lastTransaction;

  @override
  String? get currentIntentUuid => _currentIntentUuid;

  void setStateSnapshot({
    required PaymentStatus status,
    String? errorMessage,
    String? statusMessage,
    bool? isInitialized,
    bool? isReady,
    Map<String, dynamic>? lastTransaction,
    String? currentIntentUuid,
  }) {
    _status = status;
    _errorMessage = errorMessage;
    _statusMessage = statusMessage;
    _isInitialized = isInitialized ?? _isInitialized;
    _isReady = isReady ?? (status == PaymentStatus.ready);
    _lastTransaction = lastTransaction ?? _lastTransaction;
    _currentIntentUuid = currentIntentUuid ?? _currentIntentUuid;
    notifyListeners();
  }

  @override
  Future<void> initializeAndAuthenticate() async {
    initializeCalls++;
    setStateSnapshot(
      status: PaymentStatus.ready,
      statusMessage: 'Mock auth ready',
      isInitialized: true,
      isReady: true,
    );
  }

  @override
  Future<void> processPurchase({
    required int amount,
    String? customerReferenceNumber,
  }) async {
    processPurchaseCalls++;
    lastPurchaseAmount = amount;
    lastCustomerReference = customerReferenceNumber;

    setStateSnapshot(
      status: PaymentStatus.waitingCard,
      statusMessage: 'اقرب البطاقة أو الجوال',
      isReady: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    setStateSnapshot(
      status: PaymentStatus.readingCard,
      statusMessage: 'جاري قراءة البطاقة...',
      isReady: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    _lastTransaction = {
      'status': 'approved',
      'isApproved': true,
      'transactionId': 'ULTRA-TXN-999',
      'amount': amount / 100.0,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setStateSnapshot(
      status: PaymentStatus.success,
      statusMessage: 'تمت العملية بنجاح!',
      isReady: false,
      lastTransaction: _lastTransaction,
    );
  }

  @override
  bool reset() {
    resetCalls++;
    setStateSnapshot(
      status: PaymentStatus.idle,
      errorMessage: null,
      statusMessage: null,
      isReady: false,
    );
    return true;
  }
}

Widget _buildHarness({
  required FakeNearPayProvider provider,
  required double amount,
  required String? customerReference,
  required void Function(Map<String, dynamic>) onPaymentComplete,
  required VoidCallback onPaymentCancelled,
  required void Function(String status, String? message) onStatusChanged,
}) {
  return ChangeNotifierProvider<NearPayProvider>.value(
    value: provider,
    child: MaterialApp(
      home: NearPayPaymentScreen(
        amount: amount,
        customerReference: customerReference,
        onPaymentComplete: onPaymentComplete,
        onPaymentCancelled: onPaymentCancelled,
        onStatusChanged: onStatusChanged,
      ),
    ),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.views.first.physicalSize = const Size(1440, 2560);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  group('ULTRA NearPay Widget Test', () {
    testWidgets(
      'end-to-end widget flow: init, start, waiting, reading, success, complete callback',
      (tester) async {
        final provider = FakeNearPayProvider();
        final statusEvents = <String>[];
        Map<String, dynamic>? completedTransaction;
        var cancelCalls = 0;

        await tester.pumpWidget(
          _buildHarness(
            provider: provider,
            amount: 15.75,
            customerReference: 'TABLE-12',
            onPaymentComplete: (tx) => completedTransaction = tx,
            onPaymentCancelled: () => cancelCalls++,
            onStatusChanged: (status, message) {
              statusEvents.add('$status|${message ?? ''}');
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));

        expect(provider.initializeCalls, 1);
        expect(find.text('بدء الدفع - 15.75 ر.س'), findsOneWidget);

        await tester.tap(find.text('بدء الدفع - 15.75 ر.س'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(provider.processPurchaseCalls, 1);
        expect(provider.lastPurchaseAmount, 1575);
        expect(provider.lastCustomerReference, 'TABLE-12');
        expect(
          statusEvents.any((e) => e.startsWith('waitingCard|')),
          true,
        );

        await tester.pump(const Duration(milliseconds: 40));
        expect(
          statusEvents.any((e) => e.startsWith('readingCard|')),
          true,
        );

        await tester.pump(const Duration(milliseconds: 40));
        expect(find.text('تم الدفع بنجاح!'), findsOneWidget);
        expect(find.text('إنهاء'), findsOneWidget);

        await tester.tap(find.text('إنهاء'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));

        expect(completedTransaction, isNotNull);
        expect(completedTransaction!['status'], 'approved');
        expect(completedTransaction!['transactionId'], 'ULTRA-TXN-999');
        expect(cancelCalls, 0);
        expect(statusEvents.isNotEmpty, true);
      },
    );

    testWidgets(
      'error mode: shows error UI, retry resets state and re-initializes',
      (tester) async {
        final provider = FakeNearPayProvider()
          ..setStateSnapshot(
            status: PaymentStatus.error,
            errorMessage: 'ERR_007: Payment can only be processed in CDS mode',
            isInitialized: false,
            isReady: true,
          );

        await tester.pumpWidget(
          _buildHarness(
            provider: provider,
            amount: 10,
            customerReference: null,
            onPaymentComplete: (_) {},
            onPaymentCancelled: () {},
            onStatusChanged: (_, __) {},
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));

        expect(find.text('حدث خطأ'), findsOneWidget);
        expect(find.textContaining('ERR_007'), findsWidgets);
        expect(find.text('إعادة المحاولة'), findsOneWidget);

        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pump(const Duration(milliseconds: 50));

        expect(provider.resetCalls, 1);
        expect(provider.initializeCalls, 1);
        expect(provider.status, PaymentStatus.ready);
      },
    );

    testWidgets(
      'processing mode: cancel action is available and calls callback',
      (tester) async {
        final provider = FakeNearPayProvider()
          ..setStateSnapshot(
            status: PaymentStatus.waitingCard,
            statusMessage: 'اقرب البطاقة',
            isReady: true,
          );

        var cancelCalls = 0;

        await tester.pumpWidget(
          _buildHarness(
            provider: provider,
            amount: 25,
            customerReference: 'CANCEL-CASE',
            onPaymentComplete: (_) {},
            onPaymentCancelled: () => cancelCalls++,
            onStatusChanged: (_, __) {},
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));

        expect(find.text('إلغاء العملية'), findsOneWidget);

        await tester.tap(find.text('إلغاء العملية'));
        await tester.pump();

        expect(cancelCalls, 1);
      },
    );
  });
}
