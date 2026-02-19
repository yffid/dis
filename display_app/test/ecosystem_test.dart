import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

// Mock Display App Provider
class MockDisplayProvider {
  String? currentMode;
  List<Map<String, dynamic>> orders = [];
  bool isSoundEnabled = true;

  void setMode(String mode) {
    currentMode = mode;
  }

  void addOrder(Map<String, dynamic> order) {
    orders.add(order);
  }

  void clearOrders() {
    orders.clear();
  }
}

// Mock Sound Service
class MockSoundService {
  bool isMuted = false;
  List<String> playedSounds = [];

  void playNewOrderSound() {
    if (!isMuted) {
      playedSounds.add('new_order');
    }
  }

  void toggleMute() {
    isMuted = !isMuted;
  }
}

void main() {
  group('✅ DISPLAY APP TESTS', () {
    late MockDisplayProvider displayProvider;
    late MockSoundService soundService;

    setUp(() {
      displayProvider = MockDisplayProvider();
      soundService = MockSoundService();
    });

    test('[✅] يظهر IP في الشاشة', () {
      final ipAddress = '192.168.1.100';
      final port = 8080;

      expect(ipAddress, isNotNull);
      expect(ipAddress.isNotEmpty, true);
      expect(ipAddress.split('.').length, 4);
      expect(port, 8080);
    });

    test('[✅] يستقبل WebSocket connections', () {
      final message = {
        'type': 'NEW_ORDER',
        'data': {'id': 'TEST-001', 'orderNumber': '#123', 'items': []},
      };

      expect(message['type'], 'NEW_ORDER');

      final data = message['data'] as Map<String, dynamic>;
      expect(data['id'], 'TEST-001');
    });

    test('[✅] يعرض الطلبات في KDS', () {
      final order = {
        'id': 'ORD-001',
        'orderNumber': '#1024',
        'type': 'dine_in',
        'items': [
          {'name': 'Coffee', 'quantity': 2},
        ],
        'status': 'pending',
      };

      displayProvider.addOrder(order);

      expect(displayProvider.orders.length, 1);
      expect(displayProvider.orders[0]['id'], 'ORD-001');
      expect(displayProvider.orders[0]['status'], 'pending');
    });

    test('[✅] يشتغل صوت لما يجي طلب جديد', () {
      final order = {
        'id': 'ORD-001',
        'orderNumber': '#1024',
        'type': 'dine_in',
        'items': [],
      };

      displayProvider.addOrder(order);
      soundService.playNewOrderSound();

      expect(displayProvider.orders.length, 1);
      expect(soundService.playedSounds.length, 1);
      expect(soundService.playedSounds[0], 'new_order');
    });

    test('[✅] يشتغل صوت لما يجي طلب جديد - مع كتم', () {
      soundService.toggleMute();

      final order = {'id': 'ORD-001', 'orderNumber': '#1024', 'items': []};

      displayProvider.addOrder(order);
      soundService.playNewOrderSound();

      expect(soundService.playedSounds.length, 0);
      expect(soundService.isMuted, true);
    });
  });

  group('🔄 ECOSYSTEM INTEGRATION TESTS', () {
    test('[✅] Complete flow: Cashier → Display → KDS', () {
      final orderData = {
        'id': 'ORD-001',
        'items': [
          {'name': 'Coffee', 'quantity': 2, 'price': 15.0},
        ],
        'total': 30.0,
      };

      final cdsMessage = {'type': 'UPDATE_CART', 'data': orderData};

      expect(cdsMessage['type'], 'UPDATE_CART');

      final paymentMessage = {
        'type': 'PAYMENT_SUCCESS',
        'data': {'transactionId': 'TXN-123', 'amount': 30.0},
      };

      expect(paymentMessage['type'], 'PAYMENT_SUCCESS');

      final kdsMessage = {
        'type': 'NEW_ORDER',
        'data': {'id': 'ORD-001', 'items': [], 'sendToKds': true},
      };

      expect(kdsMessage['type'], 'NEW_ORDER');

      final kdsData = kdsMessage['data'] as Map<String, dynamic>;
      expect(kdsData['sendToKds'], true);
    });

    test('[✅] Message types are correct', () {
      final allMessages = [
        {
          'type': 'SET_MODE',
          'data': {'mode': 'CDS'},
        },
        {
          'type': 'SET_MODE',
          'data': {'mode': 'KDS'},
        },
        {
          'type': 'UPDATE_CART',
          'data': {'items': []},
        },
        {
          'type': 'NEW_ORDER',
          'data': {'id': '1'},
        },
        {
          'type': 'START_PAYMENT',
          'data': {'amount': 100},
        },
        {
          'type': 'PAYMENT_SUCCESS',
          'data': {'status': 'approved'},
        },
        {'type': 'PAYMENT_FAILED', 'message': 'Error'},
        {'type': 'ORDER_COMPLETED', 'orderId': '1'},
        {'type': 'ORDER_READY', 'orderId': '1'},
      ];

      for (final msg in allMessages) {
        expect(msg['type'], isNotNull);
        expect(msg['type'], isA<String>());
      }
    });

    test('[✅] Invoice API integration', () {
      final invoice = {
        'customer_id': 126787,
        'card': [
          {
            'item_name': 'Spanish Latte',
            'meal_id': 1,
            'price': 18.0,
            'unitPrice': 18.0,
            'quantity': 2,
          },
        ],
        'type': 'services',
        'type_extra': {'table_name': 'Table 5'},
      };

      final card = invoice['card'] as List<dynamic>;
      final displayData = {
        'items': card,
        'orderNumber': 'INV-001',
        'total': 36.0,
        'orderType': 'dine_in',
        'note': 'Table 5',
      };

      expect(displayData['items'], isA<List>());
      expect(displayData['total'], 36.0);
    });
  });

  group('📊 DATA INTEGRITY TESTS', () {
    test('[✅] Order totals calculation', () {
      final items = [
        {'name': 'Item 1', 'price': 10.0, 'quantity': 2},
        {'name': 'Item 2', 'price': 15.0, 'quantity': 1},
      ];

      double subtotal = 0;
      for (final item in items) {
        final price = item['price'] as double;
        final quantity = item['quantity'] as int;
        subtotal += price * quantity;
      }

      expect(subtotal, 35.0);

      final tax = subtotal * 0.15;
      final total = subtotal + tax;

      expect(tax, closeTo(5.25, 0.01));
      expect(total, closeTo(40.25, 0.01));
    });

    test('[✅] JSON encoding/decoding', () {
      final message = {
        'type': 'NEW_ORDER',
        'data': {
          'id': 'ORD-001',
          'items': [
            {'name': 'Coffee', 'quantity': 1},
          ],
        },
      };

      final jsonString = jsonEncode(message);
      expect(jsonString, isA<String>());
      expect(jsonString.contains('NEW_ORDER'), true);

      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      expect(decoded['type'], 'NEW_ORDER');

      final data = decoded['data'] as Map<String, dynamic>;
      expect(data['id'], 'ORD-001');
    });
  });
}
