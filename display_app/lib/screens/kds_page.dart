import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/display_provider.dart';
import '../services/sound_service.dart';
import '../services/kds_sync_service.dart';
import '../models.dart';

// نموذج بيانات خاص بطلبات المطبخ
class KitchenOrder {
  final String id;
  final String orderNumber;
  final String type; // dine_in, take_away, delivery, car, table
  final DateTime startTime;
  OrderStatus status;
  final List<Map<String, dynamic>> items;
  final String? note;
  final double? total;
  bool _urgencyAlertPlayed = false;

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

  factory KitchenOrder.fromJson(Map<String, dynamic> json) {
    return KitchenOrder(
      id: json['id'] ?? 'ORD-${DateTime.now().millisecondsSinceEpoch}',
      orderNumber: json['orderNumber'] ?? json['id'] ?? 'Unknown',
      type: json['type'] ?? 'dine_in',
      startTime: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      status: OrderStatus.pending,
      items: List<Map<String, dynamic>>.from(json['items'] ?? []),
      note: json['note'],
      total: json['total'] != null
          ? (json['total'] is int
                ? json['total'].toDouble()
                : json['total'] as double)
          : null,
    );
  }

  bool get urgencyAlertPlayed => _urgencyAlertPlayed;
  void setUrgencyAlertPlayed() => _urgencyAlertPlayed = true;

  int get bumpedItemsCount =>
      items.where((item) => item['bumped'] == true).length;

  double get progress => items.isEmpty ? 0 : bumpedItemsCount / items.length;

  bool get allItemsBumped => items.every((item) => item['bumped'] == true);
}

class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  final List<KitchenOrder> _orders = [];
  final ValueNotifier<List<KitchenOrder>> _visibleOrders =
      ValueNotifier<List<KitchenOrder>>(<KitchenOrder>[]);
  Timer? _timer;
  Timer? _urgencyTimer;
  String _filterType = 'all'; // all, dine_in, take_away, delivery, car, table
  final SoundService _soundService = SoundService();
  bool _isSoundInitialized = false;
  DisplayProvider? _displayProvider;
  VoidCallback? _displayListener;

  @override
  void initState() {
    super.initState();
    _initializeSound();

    // Tick visible cards only (without rebuilding full scaffold).
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _refreshVisibleOrdersClockTick();
      }
    });

    // Check for urgent orders every 10 seconds
    _urgencyTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkUrgentOrders();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<DisplayProvider>();
    if (_displayProvider == provider) return;

    if (_displayProvider != null && _displayListener != null) {
      _displayProvider!.removeListener(_displayListener!);
    }

    _displayProvider = provider;
    _displayListener = _consumeIncomingOrders;
    _displayProvider!.addListener(_displayListener!);
    _consumeIncomingOrders();
  }

  Future<void> _initializeSound() async {
    await _soundService.initialize();
    if (mounted) {
      setState(() {
        _isSoundInitialized = true;
      });
    }
  }

  void _checkUrgentOrders() {
    if (_soundService.isMuted) return;

    final now = DateTime.now();
    for (final order in _orders) {
      if (order.status != OrderStatus.ready && !order.urgencyAlertPlayed) {
        final duration = now.difference(order.startTime);
        if (duration.inMinutes >= 15) {
          // Play urgent sound
          _soundService.playUrgentSound();
          order.setUrgencyAlertPlayed();
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _urgencyTimer?.cancel();
    if (_displayProvider != null && _displayListener != null) {
      _displayProvider!.removeListener(_displayListener!);
    }
    _visibleOrders.dispose();
    _soundService.dispose();
    super.dispose();
  }

  void _consumeIncomingOrders() {
    final provider = _displayProvider;
    if (provider == null) return;

    final pendingOrders = provider.drainPendingOrders();
    if (pendingOrders.isEmpty) return;

    var newOrdersCount = 0;
    for (final rawOrder in pendingOrders) {
      final order = KitchenOrder.fromJson(rawOrder);
      final existingIndex = _orders.indexWhere((o) => o.id == order.id);
      if (existingIndex >= 0) {
        _orders[existingIndex] = order;
      } else {
        _orders.insert(0, order);
        newOrdersCount++;
      }
      kdsSyncService.queueOrderSync(order);
    }

    if (newOrdersCount > 0 && _isSoundInitialized) {
      _soundService.playNewOrderSound();
    }
    _recomputeVisibleOrders();
  }

  void _recomputeVisibleOrders() {
    var activeOrders = _orders
        .where((o) => o.status != OrderStatus.completed)
        .toList(growable: false);

    if (_filterType != 'all') {
      activeOrders = activeOrders
          .where((o) => o.type == _filterType)
          .toList(growable: false);
    }

    activeOrders.sort((a, b) {
      if (a.status == OrderStatus.ready && b.status != OrderStatus.ready) {
        return -1;
      }
      if (b.status == OrderStatus.ready && a.status != OrderStatus.ready) {
        return 1;
      }
      return a.startTime.compareTo(b.startTime);
    });

    _visibleOrders.value = activeOrders;
  }

  void _refreshVisibleOrdersClockTick() {
    final current = _visibleOrders.value;
    if (current.isEmpty) return;
    _visibleOrders.value = List<KitchenOrder>.from(current);
  }

  void _bumpItem(KitchenOrder order, int itemIndex) {
    order.items[itemIndex]['bumped'] = true;
    if (_isSoundInitialized) {
      _soundService.playSuccessSound();
    }
    _recomputeVisibleOrders();

    // If all items are bumped, mark order as ready after a delay
    if (order.allItemsBumped) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          order.status = OrderStatus.ready;
          if (_isSoundInitialized) {
            _soundService.playOrderReadySound();
          }
          _recomputeVisibleOrders();
          // Sync status change
          kdsSyncService.queueStatusSync(order.id, 'ready');
        }
      });
    }

    // HIGH RISK FIX: Sync bump status immediately
    final cartId = order.items[itemIndex]['cartId'] as String? ?? '';
    kdsSyncService.queueBumpSync(order.id, cartId, true);
  }

  void _advanceOrderStatus(KitchenOrder order) {
    if (order.status == OrderStatus.pending) {
      order.status = OrderStatus.preparing;
      if (_isSoundInitialized) {
        _soundService.playSuccessSound();
      }
      // HIGH RISK FIX: Sync status change
      kdsSyncService.queueStatusSync(order.id, 'preparing');
      _recomputeVisibleOrders();
    } else if (order.status == OrderStatus.ready) {
      order.status = OrderStatus.completed;
      // HIGH RISK FIX: Sync status change before removing
      kdsSyncService.queueStatusSync(order.id, 'completed');
      _recomputeVisibleOrders();
      // يمكن حذف الطلب من الشاشة أو نقله للأرشيف
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _orders.removeWhere((o) => o.id == order.id);
          _recomputeVisibleOrders();
        }
      });
    }
  }

  void _toggleMute() {
    setState(() {
      _soundService.toggleMute();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF58220),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.chefHat, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'شاشة المطبخ (KDS)',
                    style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: const Color(0xFF1E293B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  ValueListenableBuilder<List<KitchenOrder>>(
                    valueListenable: _visibleOrders,
                    builder: (context, activeOrders, _) {
                      return Text(
                        '${activeOrders.length} طلبات نشطة',
                        style: GoogleFonts.tajawal(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Sound Toggle Button
          IconButton(
            onPressed: _toggleMute,
            icon: Icon(
              _soundService.isMuted ? LucideIcons.volumeX : LucideIcons.volume2,
              color: _soundService.isMuted
                  ? Colors.red
                  : const Color(0xFF64748B),
            ),
            tooltip: _soundService.isMuted ? 'تفعيل الصوت' : 'كتم الصوت',
          ),
          const SizedBox(width: 8),
          _buildFilterChip('الكل', 'all'),
          _buildFilterChip('محلي', 'dine_in'),
          _buildFilterChip('سفري', 'take_away'),
          _buildFilterChip('توصيل', 'delivery'),
          _buildFilterChip('سيارة', 'car'),
          _buildFilterChip('طاولة', 'table'),
          const SizedBox(width: 16),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: ValueListenableBuilder<List<KitchenOrder>>(
        valueListenable: _visibleOrders,
        builder: (context, activeOrders, _) {
          if (activeOrders.isEmpty) {
            return _buildEmptyState();
          }
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.85,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: activeOrders.length,
              itemBuilder: (context, index) {
                return _OrderCard(
                  order: activeOrders[index],
                  onAction: () => _advanceOrderStatus(activeOrders[index]),
                  onBumpItem: (itemIndex) =>
                      _bumpItem(activeOrders[index], itemIndex),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Test sound
          if (_isSoundInitialized) {
            _soundService.playTestSound();
          }
        },
        backgroundColor: const Color(0xFFF58220),
        child: const Icon(LucideIcons.music),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.chefHat, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا توجد طلبات حالياً',
            style: GoogleFonts.tajawal(
              fontSize: 24,
              color: Colors.grey[500],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'بانتظار طلبات جديدة...',
            style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String type) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        onPressed: () {
          setState(() {
            _filterType = type;
          });
          _recomputeVisibleOrders();
        },
        label: Text(label),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF64748B),
          fontWeight: FontWeight.bold,
          fontFamily: 'Tajawal',
        ),
        backgroundColor: isSelected ? const Color(0xFFF58220) : Colors.white,
        side: BorderSide(
          color: isSelected ? const Color(0xFFF58220) : const Color(0xFFE2E8F0),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final KitchenOrder order;
  final VoidCallback onAction;
  final Function(int) onBumpItem;

  const _OrderCard({
    required this.order,
    required this.onAction,
    required this.onBumpItem,
  });

  Color get _statusColor {
    switch (order.status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.preparing:
        return Colors.blue;
      case OrderStatus.ready:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String get _actionText {
    switch (order.status) {
      case OrderStatus.pending:
        return 'بدء التحضير';
      case OrderStatus.preparing:
        return 'جاري التحضير';
      case OrderStatus.ready:
        return 'تسليم الطلب';
      default:
        return '';
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'dine_in':
        return 'محلي';
      case 'take_away':
        return 'سفري';
      case 'delivery':
        return 'توصيل';
      case 'car':
        return 'سيارة';
      case 'table':
        return 'طاولة';
      default:
        return type;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'dine_in':
        return LucideIcons.utensils;
      case 'take_away':
        return LucideIcons.package;
      case 'delivery':
        return LucideIcons.truck;
      case 'car':
        return LucideIcons.car;
      case 'table':
        return LucideIcons.armchair;
      default:
        return LucideIcons.shoppingBag;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'car':
        return Colors.purple;
      case 'table':
        return Colors.teal;
      case 'delivery':
        return Colors.red;
      case 'take_away':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final duration = DateTime.now().difference(order.startTime);
    final isLate = duration.inMinutes > 15 && order.status != OrderStatus.ready;
    final typeColor = _getTypeColor(order.type);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: _statusColor.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: typeColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getTypeIcon(order.type),
                            size: 12,
                            color: typeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getTypeLabel(order.type),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: typeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isLate ? Colors.red : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.clock,
                        size: 14,
                        color: isLate ? Colors.white : Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isLate ? Colors.white : Colors.black87,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Progress Bar
          LinearProgressIndicator(
            value: order.progress,
            backgroundColor: Colors.grey[100],
            color: _statusColor,
            minHeight: 6,
          ),

          // Progress Text
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '${order.bumpedItemsCount} / ${order.items.length} تم التحضير',
              style: GoogleFonts.tajawal(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Items List with Separators
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: order.items.length,
              separatorBuilder: (context, index) => Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              itemBuilder: (context, index) {
                final item = order.items[index];
                final productName =
                    item['name'] ?? item['productName'] ?? 'Product';
                final quantity = item['quantity'] ?? 1;
                final extras = item['extras'] ?? item['selectedExtras'] ?? [];
                final isBumped = item['bumped'] == true;

                return Container(
                  decoration: BoxDecoration(
                    color: isBumped
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isBumped ? Colors.green : Colors.grey[300]!,
                      width: isBumped ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: isBumped ? null : () => onBumpItem(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Bump Button / Status Icon
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isBumped
                                  ? Colors.green
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isBumped
                                  ? LucideIcons.check
                                  : LucideIcons.chefHat,
                              color: isBumped ? Colors.white : Colors.orange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Quantity Box
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isBumped
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isBumped
                                    ? Colors.green
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              '${quantity}x',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: isBumped ? Colors.green : Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  productName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isBumped
                                        ? Colors.green
                                        : const Color(0xFF1E293B),
                                    decoration: isBumped
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (extras.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Wrap(
                                      spacing: 4,
                                      children: extras.map<Widget>((e) {
                                        final extraName = e is Map
                                            ? (e['name'] ?? '')
                                            : e.toString();
                                        return Text(
                                          '+ $extraName',
                                          style: TextStyle(
                                            color: isBumped
                                                ? Colors.green.withValues(
                                                    alpha: 0.7,
                                                  )
                                                : const Color(0xFF64748B),
                                            fontSize: 12,
                                            decoration: isBumped
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Bump Text (if not bumped)
                          if (!isBumped)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'اضغط لـ Bump',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Total (if available)
          if (order.total != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'المجموع: ${order.total!.toStringAsFixed(2)} ر.س',
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFF58220),
                ),
                textAlign: TextAlign.left,
              ),
            ),

          // Notes
          if (order.note != null && order.note!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.stickyNote,
                    size: 16,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.note!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Footer Action
          if (order.status == OrderStatus.ready)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _actionText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
