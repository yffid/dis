import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'connection_screen.dart';

class DeviceSetupWizard extends StatefulWidget {
  final VoidCallback onClose;

  const DeviceSetupWizard({super.key, required this.onClose});

  @override
  State<DeviceSetupWizard> createState() => _DeviceSetupWizardState();
}

class _DeviceSetupWizardState extends State<DeviceSetupWizard> {
  String _step = 'selection'; // 'selection', 'connection'
  String? _selectedDevice; // 'kds', 'cds'

  void _handleSelectDevice(String type) {
    setState(() {
      _selectedDevice = type;
      // Both CDS and KDS go directly to connection.
      _step = 'connection';
    });
  }

  void _handleBack() {
    setState(() {
      _step = 'selection';
      _selectedDevice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // If in connection mode, show the ConnectionScreen
    if (_step == 'connection' && _selectedDevice != null) {
      return ConnectionScreen(
        onClose: widget.onClose,
        onBack: _handleBack,
        mode: _selectedDevice!,
      );
    }

    // Selection Screen
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Background Ambience
          Positioned(
            top: -100,
            left: -50,
            child: _buildBlurCircle(
              400,
              const Color(0xFFF58220).withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -50,
            child: _buildBlurCircle(400, Colors.purple.withValues(alpha: 0.1)),
          ),

          // Close Button
          Positioned(
            top: 32,
            left: 32,
            child: InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(50),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.x,
                  color: Color(0xFF94A3B8),
                  size: 24,
                ),
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Header
                  Container(
                    width: 96,
                    height: 96,
                    margin: const EdgeInsets.only(bottom: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: const Color(0xFFEEF2FF)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE0E7FF).withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Transform.rotate(
                      angle: 0.05, // ~3 degrees
                      child: const Icon(
                        LucideIcons.store,
                        size: 48,
                        color: Color(0xFFF58220),
                      ),
                    ),
                  ),

                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.tajawal(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                        height: 1.2,
                      ),
                      children: const [
                        TextSpan(text: 'إعداد '),
                        TextSpan(
                          text: 'جهاز جديد',
                          style: TextStyle(color: Color(0xFFF58220)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'قم باختيار نمط التشغيل المناسب لهذا الجهاز لربطه مع نقطة البيع الرئيسية',
                    style: GoogleFonts.tajawal(
                      fontSize: 18,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 64),

                  // Cards Grid
                  Wrap(
                    spacing: 32,
                    runSpacing: 32,
                    alignment: WrapAlignment.center,
                    children: [
                      _SelectionCard(
                        title: 'شاشة المطبخ (KDS)',
                        description:
                            'نظام عرض الطلبات للمطبخ لتنظيم عملية التحضير وتتبع حالة الطلبات لحظة بلحظة.',
                        icon: LucideIcons.chefHat,
                        color: Colors.orange,
                        onTap: () => _handleSelectDevice('kds'),
                      ),
                      _SelectionCard(
                        title: 'شاشة العميل (CDS)',
                        description:
                            'شاشة تفاعلية للعميل لعرض تفاصيل الفاتورة والدفع الإلكتروني عبر NearPay (Tap to Pay). تتطلب جهاز Android بدعم NFC.',
                        icon: LucideIcons.monitor,
                        color: Colors.teal,
                        onTap: () => _handleSelectDevice('cds'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 64),

                  // Footer
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.check,
                        size: 16,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'متوافق مع أجهزة iPad و Android Tablets والمتصفحات الحديثة',
                        style: GoogleFonts.tajawal(
                          fontSize: 14,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

class _SelectionCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_SelectionCard> createState() => _SelectionCardState();
}

class _SelectionCardState extends State<_SelectionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 400,
          padding: const EdgeInsets.all(32),
          transform: Matrix4.translationValues(
            0.0,
            _isHovered ? -8.0 : 0.0,
            0.0,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.3)
                  : const Color(0xFFF1F5F9),
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? widget.color.withValues(alpha: 0.15)
                    : const Color(0xFF64748B).withValues(alpha: 0.05),
                blurRadius: _isHovered ? 40 : 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? widget.color.withValues(alpha: 0.1)
                      : widget.color.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Transform.scale(
                  scale: _isHovered ? 1.1 : 1.0,
                  child: Icon(widget.icon, size: 40, color: widget.color),
                ),
              ),

              Text(
                widget.title,
                style: GoogleFonts.tajawal(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.description,
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF64748B),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),

              // Footer Action
              Container(
                padding: const EdgeInsets.only(top: 24),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF8FAFC))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'نمط التشغيل',
                        style: GoogleFonts.tajawal(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: widget.color,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isHovered
                            ? widget.color
                            : const Color(0xFFF8FAFC),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.arrowLeft, // RTL layout
                        size: 20,
                        color: _isHovered
                            ? Colors.white
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
