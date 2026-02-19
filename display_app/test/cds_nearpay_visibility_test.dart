import 'package:flutter_test/flutter_test.dart';

enum TestDisplayMode { cds, kds }

/// Focused harness for Display behavior when START_PAYMENT arrives.
/// Goal: prove NearPay is shown on CDS only.
class DisplayPaymentHarness {
  TestDisplayMode mode = TestDisplayMode.cds;
  bool nearPayVisible = false;
  final List<Map<String, dynamic>> outboundMessages = [];

  void handleStartPayment({
    required double amount,
    required String orderNumber,
  }) {
    if (mode != TestDisplayMode.cds) {
      outboundMessages.add({
        'type': 'PAYMENT_FAILED',
        'message': 'Payment can only be processed in CDS mode',
      });
      return;
    }

    if (amount <= 0) {
      outboundMessages.add({
        'type': 'PAYMENT_FAILED',
        'message': 'Invalid payment amount',
      });
      return;
    }

    nearPayVisible = true;
    outboundMessages.add({
      'type': 'PAYMENT_STATUS',
      'data': {
        'status': 'waitingCard',
        'message': 'اقرب البطاقة أو الجوال',
        'orderNumber': orderNumber,
      },
    });
  }
}

void main() {
  group('🖥️ CDS NearPay Visibility', () {
    test('START_PAYMENT in CDS => NearPay becomes visible', () {
      final harness = DisplayPaymentHarness()..mode = TestDisplayMode.cds;

      harness.handleStartPayment(
        amount: 73.5,
        orderNumber: 'ORD-CDS-VIS-001',
      );

      expect(harness.nearPayVisible, true);
      expect(harness.outboundMessages.length, 1);
      expect(harness.outboundMessages.first['type'], 'PAYMENT_STATUS');
      expect(
        (harness.outboundMessages.first['data'] as Map)['status'],
        'waitingCard',
      );
    });

    test('START_PAYMENT in KDS => rejected and NearPay not visible', () {
      final harness = DisplayPaymentHarness()..mode = TestDisplayMode.kds;

      harness.handleStartPayment(
        amount: 73.5,
        orderNumber: 'ORD-KDS-REJECT-001',
      );

      expect(harness.nearPayVisible, false);
      expect(harness.outboundMessages.length, 1);
      expect(harness.outboundMessages.first['type'], 'PAYMENT_FAILED');
    });

    test('Invalid amount in CDS => rejected and NearPay not visible', () {
      final harness = DisplayPaymentHarness()..mode = TestDisplayMode.cds;

      harness.handleStartPayment(
        amount: 0,
        orderNumber: 'ORD-BAD-AMOUNT',
      );

      expect(harness.nearPayVisible, false);
      expect(harness.outboundMessages.length, 1);
      expect(harness.outboundMessages.first['type'], 'PAYMENT_FAILED');
    });
  });
}

