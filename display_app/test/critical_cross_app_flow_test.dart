import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

abstract class MessageBus {
  Future<void> send(Map<String, dynamic> message);
}

class MockMessageBus extends Mock implements MessageBus {}

class CriticalFlowOrchestrator {
  CriticalFlowOrchestrator({
    required MessageBus bus,
    required ValueNotifier<String> uiState,
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 5),
  }) : _bus = bus,
       _uiState = uiState;

  final MessageBus _bus;
  final ValueNotifier<String> _uiState;
  final int maxRetries;
  final Duration retryDelay;
  final Set<String> _kdsDispatchLedger = <String>{};

  int retryCount = 0;

  Future<void> executeCriticalFlow({
    required String orderId,
    required double amount,
  }) async {
    _uiState.value = 'cart_sent';
    await _bus.send({
      'type': 'UPDATE_CART',
      'data': {'orderId': orderId, 'amount': amount},
    });

    _uiState.value = 'payment_started';
    await _bus.send({
      'type': 'START_PAYMENT',
      'data': {'orderId': orderId, 'amount': amount},
    });

    _uiState.value = 'payment_approved';
    await _sendWithRetry({
      'type': 'PAYMENT_SUCCESS',
      'eventId': 'evt-$orderId',
      'data': {'orderId': orderId, 'amount': amount, 'status': 'approved'},
    });

    if (_kdsDispatchLedger.add(orderId)) {
      await _bus.send({
        'type': 'NEW_ORDER',
        'data': {'id': orderId, 'total': amount, 'status': 'pending'},
      });
    }

    _uiState.value = 'kds_synced';
  }

  Future<void> _sendWithRetry(Map<String, dynamic> message) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _bus.send(message);
        return;
      } catch (error) {
        lastError = error;
        retryCount++;
        if (attempt == maxRetries) break;
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError('Critical message delivery failed: $lastError');
  }
}

class FlowStatusWidget extends StatelessWidget {
  const FlowStatusWidget({super.key, required this.uiState});

  final ValueNotifier<String> uiState;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: uiState,
            builder: (_, value, __) => Text(value, textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpUntilText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (find.text(text).evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for "$text"');
}

void main() {
  group('Critical Cashier -> Display -> KDS Flow', () {
    late MockMessageBus bus;
    late ValueNotifier<String> state;
    late CriticalFlowOrchestrator orchestrator;

    setUpAll(() {
      registerFallbackValue(<String, dynamic>{});
    });

    setUp(() {
      bus = MockMessageBus();
      state = ValueNotifier<String>('idle');
      orchestrator = CriticalFlowOrchestrator(bus: bus, uiState: state);
    });

    tearDown(() {
      state.dispose();
    });

    testWidgets(
      'Given payment success + transient network drop, when retry completes, then KDS receives exactly one order',
      (tester) async {
        var paymentSuccessAttempts = 0;

        when(() => bus.send(any())).thenAnswer((invocation) async {
          final message = invocation.positionalArguments.first as Map<String, dynamic>;
          final type = message['type'] as String?;

          if (type == 'PAYMENT_SUCCESS') {
            paymentSuccessAttempts++;
            if (paymentSuccessAttempts == 1) {
              throw TimeoutException('network drop during PAYMENT_SUCCESS');
            }
          }
        });

        await tester.pumpWidget(FlowStatusWidget(uiState: state));
        await tester.pumpAndSettle();
        expect(find.text('idle'), findsOneWidget);

        await tester.runAsync(() async {
          await orchestrator.executeCriticalFlow(orderId: 'ORD-42', amount: 87.5);
        });

        await _pumpUntilText(tester, 'kds_synced');

        verify(
          () => bus.send(
            any(
              that: predicate<Map<String, dynamic>>(
                (m) => m['type'] == 'UPDATE_CART' && m['data']['orderId'] == 'ORD-42',
              ),
            ),
          ),
        ).called(1);

        verify(
          () => bus.send(
            any(
              that: predicate<Map<String, dynamic>>(
                (m) => m['type'] == 'START_PAYMENT' && m['data']['amount'] == 87.5,
              ),
            ),
          ),
        ).called(1);

        verify(
          () => bus.send(
            any(
              that: predicate<Map<String, dynamic>>(
                (m) =>
                    m['type'] == 'PAYMENT_SUCCESS' &&
                    m['eventId'] == 'evt-ORD-42' &&
                    m['data']['status'] == 'approved',
              ),
            ),
          ),
        ).called(2);

        verify(
          () => bus.send(
            any(
              that: predicate<Map<String, dynamic>>(
                (m) => m['type'] == 'NEW_ORDER' && m['data']['id'] == 'ORD-42',
              ),
            ),
          ),
        ).called(1);

        expect(orchestrator.retryCount, 1);
        expect(paymentSuccessAttempts, 2);
      },
    );
  });
}
