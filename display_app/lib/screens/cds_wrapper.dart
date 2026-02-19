import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/display_provider.dart';
import '../models.dart';
import 'cds_page.dart';

class CdsPageWrapper extends StatelessWidget {
  const CdsPageWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DisplayProvider>(
      builder: (context, provider, child) {
        // Convert real cart data from provider
        final cartData = provider.cartData;
        final cart = _convertCartData(cartData);

        return CustomerFacingScreen(
          cart: cart,
          onClose: () {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/', (route) => false);
          },
        );
      },
    );
  }

  List<CartItem> _convertCartData(Map<String, dynamic> cartData) {
    if (cartData.isEmpty) return [];

    final items = cartData['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return [];

    return items.map((item) {
      final itemMap = item as Map<String, dynamic>;

      // Parse extras
      final extrasRaw = itemMap['extras'] as List<dynamic>? ?? [];
      final extras = extrasRaw.map((e) {
        final extraMap = e as Map<String, dynamic>;
        return ProductExtra(
          id: extraMap['id']?.toString() ?? '',
          name: extraMap['name']?.toString() ?? '',
          nameEn: extraMap['nameEn']?.toString() ?? extraMap['name']?.toString() ?? '',
          price: _parseDouble(extraMap['price']),
        );
      }).toList();

      // Parse price - handle both number and string formats (e.g. "6.00 SAR")
      final unitPrice = _parseDouble(itemMap['price'] ?? itemMap['unitPrice']);
      final totalPrice = _parseDouble(itemMap['totalPrice']);

      // Create Product from the data
      final product = Product(
        id: itemMap['productId']?.toString() ?? itemMap['id']?.toString() ?? '',
        name: itemMap['name']?.toString() ?? '',
        nameEn: itemMap['nameEn']?.toString() ?? itemMap['name']?.toString() ?? '',
        basePrice: unitPrice,
        category: itemMap['category']?.toString() ?? '',
        imageUrl: itemMap['imageUrl']?.toString() ?? '',
        availableExtras: extras,
      );

      return CartItem(
        cartId: itemMap['cartId']?.toString() ?? UniqueKey().toString(),
        product: product,
        quantity: (itemMap['quantity'] as num?)?.toInt() ?? 1,
        selectedExtras: extras,
      );
    }).toList();
  }

  /// Parse a value to double, handling strings like "6.00 SAR"
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      // Remove currency suffix (e.g. "6.00 SAR" -> "6.00")
      final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }
}
