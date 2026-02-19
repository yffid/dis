// نموذج الإكسترا
class ProductExtra {
  final String id;
  final String name;
  final String nameEn;
  final double price;

  const ProductExtra({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.price,
  });
}

// نموذج المنتج
class Product {
  final String id;
  final String name;
  final String nameEn;
  final double basePrice;
  final String category;
  final String imageUrl;
  final List<ProductExtra> availableExtras;
  final bool isAvailable;

  const Product({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.basePrice,
    required this.category,
    required this.imageUrl,
    this.availableExtras = const [],
    this.isAvailable = true,
  });
}

// نموذج عنصر السلة
class CartItem {
  final String cartId;
  final Product product;
  int quantity;
  final List<ProductExtra> selectedExtras;
  bool isBumped;

  CartItem({
    required this.cartId,
    required this.product,
    this.quantity = 1,
    this.selectedExtras = const [],
    this.isBumped = false,
  });

  double get totalPrice {
    double extrasTotal = selectedExtras.fold(
      0,
      (sum, extra) => sum + extra.price,
    );
    return (product.basePrice + extrasTotal) * quantity;
  }

  String get displayName => product.name;
  String get displayNameEn => product.nameEn;
}

// حالات الطلب
enum OrderStatus { pending, preparing, ready, completed, cancelled }

// نموذج الطلب
class Order {
  final String id;
  final String orderNumber;
  final OrderStatus status;
  final List<CartItem> items;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? note;
  final double subtotal;
  final double tax;
  final double total;
  final String orderType; // dine_in, take_away, delivery, car, table

  Order({
    required this.id,
    required this.orderNumber,
    this.status = OrderStatus.pending,
    required this.items,
    required this.createdAt,
    this.completedAt,
    this.note,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.orderType = 'dine_in',
  });
}

// نموذج طلب المطبخ (KDS)
class KitchenOrder {
  final String id;
  final String orderNumber;
  final String type;
  final DateTime startTime;
  OrderStatus status;
  final List<CartItem> items;
  final String? note;
  final double? total;

  KitchenOrder({
    required this.id,
    required this.orderNumber,
    required this.type,
    required this.startTime,
    this.status = OrderStatus.pending,
    required this.items,
    this.note,
    this.total,
  });

  // Check if all items are bumped
  bool get allItemsBumped => items.every((item) => item.isBumped);

  // Get bumped items count
  int get bumpedItemsCount => items.where((item) => item.isBumped).length;

  // Get progress percentage
  double get progress => items.isEmpty ? 0 : bumpedItemsCount / items.length;
}
