import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/socket_service.dart';
import '../widgets/qr_code_display_dialog.dart';

class ConnectionScreen extends StatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onBack;
  final String? mode;

  const ConnectionScreen({super.key, this.onClose, this.onBack, this.mode});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pingController;
  int _previousClientCount = 0;
  StreamSubscription? _clientCountSubscription;

  @override
  void initState() {
    super.initState();
    _pingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // مراقبة عدد الأجهزة المتصلة لإظهار الإشعار
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _monitorNewConnections();
    });
  }

  void _monitorNewConnections() {
    final socketService = context.read<SocketService>();
    _previousClientCount = socketService.connectedClients;

    _clientCountSubscription = Stream.periodic(Duration(seconds: 1)).listen((
      _,
    ) {
      final currentCount = socketService.connectedClients;
      // TODO: يمكن إضافة إشعار هنا لما جهاز جديد يتصل
      _previousClientCount = currentCount;
    });
  }

  @override
  void dispose() {
    _pingController.dispose();
    _clientCountSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socketService = context.read<SocketService>();

    // Using blueGrey as a substitute for Slate
    final slate800 = Colors.blueGrey[800];
    final slate500 = Colors.blueGrey[500];
    final slate600 = Colors.blueGrey[600];
    final slate50 = Colors.blueGrey[50]!;
    final slate200 = Colors.blueGrey[200]!;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            // Decorative Background Elements
            Positioned(
              top: -100,
              right: -100,
              child: _buildBlurCircle(400, Colors.grey.withValues(alpha: 0.05)),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: _buildBlurCircle(
                300,
                const Color(0xFFF58220).withValues(alpha: 0.05),
              ),
            ),

            // Close Button (Physical Top-Left as per 'left-8')
            Positioned(
              top: 32,
              left: 32,
              child: InkWell(
                onTap: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (widget.onClose != null) {
                    widget.onClose!();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                borderRadius: BorderRadius.circular(50),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.x,
                    color: Colors.grey,
                    size: 24,
                  ),
                ),
              ),
            ),

            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo & App Name
                    Container(
                      margin: const EdgeInsets.only(bottom: 40),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              LucideIcons.store,
                              color: Color(0xFFF58220),
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.tajawal(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                                height: 1,
                                letterSpacing: -0.5,
                              ),
                              children: const [
                                TextSpan(text: 'HERMOSA'),
                                TextSpan(
                                  text: 'POS',
                                  style: TextStyle(color: Color(0xFFF58220)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Connection Card
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 512),
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Animated Icon
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _pingController,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: 1.0 - _pingController.value,
                                    child: Transform.scale(
                                      scale:
                                          1.0 +
                                          (_pingController.value *
                                              0.5), // reduced scale
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Color(
                                            0xFFF58220,
                                          ).withValues(alpha: 0.2),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Color(
                                    0xFFF58220,
                                  ).withValues(alpha: 0.05),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(
                                        0xFFF58220,
                                      ).withValues(alpha: 0.1),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  LucideIcons.wifi,
                                  size: 56,
                                  color: Color(0xFFF58220),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),
                          Text(
                            'بانتظار الاتصال...',
                            style: GoogleFonts.tajawal(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: slate800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Waiting for Cashier Connection',
                            style: GoogleFonts.tajawal(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: slate500,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Info Container
                          StreamBuilder<String?>(
                            stream: socketService.ipStream,
                            initialData: socketService.lastIp,
                            builder: (context, snapshot) {
                              final ip = snapshot.data;
                              final isLoading =
                                  ip == null && !snapshot.hasError;

                              if (isLoading) {
                                return Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: slate50,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: slate200),
                                  ),
                                  child: const Column(
                                    children: [
                                      CircularProgressIndicator(
                                        color: Color(0xFFF58220),
                                      ),
                                      SizedBox(height: 12),
                                      Text('جاري البحث عن IP...'),
                                    ],
                                  ),
                                );
                              }

                              // If no IP detected or error
                              if (ip == null ||
                                  ip == 'Unknown' ||
                                  ip == '127.0.0.1' ||
                                  ip == 'localhost') {
                                return Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[50],
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.orange[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        LucideIcons.wifiOff,
                                        color: Colors.orange[600],
                                        size: 40,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'تعذر اكتشاف IP',
                                        style: GoogleFonts.tajawal(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange[800],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'يرجى التأكد من اتصال الجهاز بالشبكة',
                                        style: GoogleFonts.tajawal(
                                          fontSize: 14,
                                          color: Colors.orange[700],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            // Force refresh by reinitializing
                                            socketService.dispose().then((_) {
                                              socketService.initialize();
                                            });
                                          },
                                          icon: const Icon(
                                            LucideIcons.refreshCw,
                                            size: 18,
                                          ),
                                          label: Text(
                                            'إعادة المحاولة',
                                            style: GoogleFonts.tajawal(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange[600],
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: slate50,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: slate200),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.02,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(
                                        0,
                                        2,
                                      ), // Inner shadow simulation
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    _buildInfoRow(
                                      LucideIcons.network,
                                      'عنوان IP',
                                      ip,
                                      const Color(0xFFF58220),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Divider(
                                        color: slate200,
                                        height: 1,
                                      ),
                                    ),
                                    _buildInfoRow(
                                      LucideIcons.router,
                                      'المنفذ (Port)',
                                      socketService.port.toString(),
                                      const Color(0xFFF58220),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 32),

                          const SizedBox(height: 24),

                          // QR Code Button
                          StreamBuilder<String?>(
                            stream: socketService.ipStream,
                            initialData: socketService.lastIp,
                            builder: (context, snapshot) {
                              final ip = snapshot.data;
                              if (ip == null ||
                                  ip == 'Unknown' ||
                                  ip == 'localhost') {
                                return const SizedBox.shrink();
                              }

                              return SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => QRCodeDisplayDialog(
                                        ipAddress: ip,
                                        port: socketService.port,
                                        mode: widget.mode ?? 'cds',
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    LucideIcons.qrCode,
                                    size: 20,
                                  ),
                                  label: Text(
                                    'عرض QR Code للربط السريع',
                                    style: GoogleFonts.tajawal(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF58220),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          // Web Platform Warning
                          if (kIsWeb)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        LucideIcons.alertTriangle,
                                        size: 18,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'أنت تستخدم المتصفح. للحصول على أفضل تجربة، استخدم التطبيق على الجهاز مباشرة (Android/iOS/Desktop)',
                                          style: GoogleFonts.tajawal(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange[800],
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'على المتصفح، أدخل IP الجهاز يدوياً في الكاشير:',
                                    style: GoogleFonts.tajawal(
                                      fontSize: 12,
                                      color: slate600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: slate200),
                                    ),
                                    child: SelectableText(
                                      'localhost:8080',
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF58220),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Color(0xFFF58220).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Color(
                                  0xFFF58220,
                                ).withValues(alpha: 0.05),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  LucideIcons.info,
                                  size: 18,
                                  color: Color(0xFFF58220),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'أدخل هذه البيانات في جهاز الكاشير الرئيسي (إعدادات الطابعات والأجهزة) لإتمام عملية الربط وتشغيل الشاشة.',
                                    style: GoogleFonts.tajawal(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: slate600,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Footer Loader
                    const SizedBox(height: 48),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Jari Al-Etisal...',
                          style: GoogleFonts.tajawal(
                            color: Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
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
      ),
    );
  }

  Widget _buildBlurCircle(double size, Color color) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    Color accentColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.blueGrey[300]), // slate-400
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.tajawal(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[500], // slate-500
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              value,
              style: GoogleFonts.robotoMono(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
