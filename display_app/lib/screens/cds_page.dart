import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';

class CustomerFacingScreen extends StatelessWidget {
  final List<CartItem> cart;
  final VoidCallback onClose;

  const CustomerFacingScreen({
    super.key,
    required this.cart,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // إذا كانت السلة فارغة، نعرض شاشة الترحيب
    if (cart.isEmpty) {
      return _buildIdleWelcomeScreen(context);
    }

    // إذا كان هناك طلبات، نعرض الشاشة العادية (الفاتورة)
    return _buildActiveOrderScreen(context);
  }

  // 1. شاشة الترحيب (تظهر عندما لا يكون هناك طلب مضاف)
  Widget _buildIdleWelcomeScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // خلفية هادئة جداً (دوائر بلون خفيف)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                color: Color(0xFFF58220).withValues(alpha: 0.03),
                shape: BoxShape.circle,
              ),
            ),
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // شعار هيرموسا
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(
                    LucideIcons.store,
                    color: Color(0xFFF58220),
                    size: 80,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'HERMOSA POS',
                  style: GoogleFonts.tajawal(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'أهلاً بك في متجرنا',
                  style: GoogleFonts.tajawal(
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'بانتظار تسجيل طلبك الجديد..',
                    style: GoogleFonts.tajawal(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // زر الخروج مخفي بشكل ناعم في الزاوية
          Positioned(
            bottom: 32,
            left: 32,
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFFCBD5E1)),
            ),
          ),
        ],
      ),
    );
  }

  // 2. الشاشة النشطة (تظهر عند إضافة منتجات)
  Widget _buildActiveOrderScreen(BuildContext context) {
    final double subtotal = cart.fold(0, (sum, item) => sum + item.totalPrice);
    final double tax = subtotal * 0.15;
    final double total = subtotal + tax;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Row(
        children: [
          // القسم الأيسر
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.store, color: Color(0xFFF58220), size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'HERMOSA POS',
                        style: GoogleFonts.tajawal(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'تفاصيل\nطلبك الحالي',
                    style: GoogleFonts.tajawal(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'يمكنك مراجعة المنتجات والأسعار من القائمة الجانبية.',
                    style: GoogleFonts.tajawal(
                      fontSize: 18,
                      color: const Color(0xFF64748B),
                      height: 1.6,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF94A3B8)),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // القسم الأيمن
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'قائمة المشتريات',
                          style: GoogleFonts.tajawal(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'رقم #1024',
                            style: GoogleFonts.robotoMono(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      itemCount: cart.length,
                      separatorBuilder: (context, index) => Divider(color: Colors.grey[100]),
                      itemBuilder: (context, index) {
                        final item = cart[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    '${item.quantity}',
                                    style: const TextStyle(
                                      color: Color(0xFFF58220),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: GoogleFonts.tajawal(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),
                                    if (item.selectedExtras.isNotEmpty)
                                      Text(
                                        item.selectedExtras.map((e) => e.name).join('، '),
                                        style: GoogleFonts.tajawal(
                                          fontSize: 12,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                item.totalPrice.toStringAsFixed(2),
                                style: GoogleFonts.robotoMono(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                    ),
                    child: Column(
                      children: [
                        _SummaryRow(label: 'المجموع الفرعي', value: subtotal.toStringAsFixed(2)),
                        const SizedBox(height: 8),
                        _SummaryRow(label: 'الضريبة (15%)', value: tax.toStringAsFixed(2)),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'الإجمالي النهائي',
                              style: GoogleFonts.tajawal(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  total.toStringAsFixed(2),
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFF58220),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'SAR',
                                  style: GoogleFonts.tajawal(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.tajawal(color: const Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500),
        ),
        Text(
          '$value ريال',
          style: GoogleFonts.tajawal(color: const Color(0xFF334155), fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}