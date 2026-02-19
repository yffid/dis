import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../utils/nearpay_requirements.dart';

/// NearPay Requirements Screen
///
/// This screen checks all NearPay requirements before allowing the app
/// to be used as a payment terminal.
class NearPayRequirementsScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback? onBack;

  const NearPayRequirementsScreen({
    Key? key,
    required this.onContinue,
    this.onBack,
  }) : super(key: key);

  @override
  State<NearPayRequirementsScreen> createState() =>
      _NearPayRequirementsScreenState();
}

class _NearPayRequirementsScreenState extends State<NearPayRequirementsScreen> {
  RequirementsStatus? _status;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkRequirements();
  }

  Future<void> _checkRequirements() async {
    setState(() => _isChecking = true);

    final status = await NearPayRequirementsChecker.checkAll();

    setState(() {
      _status = status;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                _buildHeader(),
                const SizedBox(height: 32),

                // Requirements Status
                if (_isChecking)
                  _buildLoadingView()
                else if (_status != null)
                  NearPayRequirementsWidget(
                    status: _status!,
                    onRetry: _checkRequirements,
                  ),

                const SizedBox(height: 32),

                // Warning for missing requirements
                if (_status != null && !_status!.allRequirementsMet)
                  _buildWarningCard(),

                const SizedBox(height: 32),

                // Action Buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF58220).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            LucideIcons.creditCard,
            size: 40,
            color: Color(0xFFF58220),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'نظام الدفع الإلكتروني',
          style: GoogleFonts.tajawal(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'NearPay - Tap to Pay on Phone',
          style: GoogleFonts.tajawal(
            fontSize: 16,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Color(0xFFF58220)),
          const SizedBox(height: 24),
          Text(
            'جاري فحص متطلبات النظام...',
            style: GoogleFonts.tajawal(
              fontSize: 16,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.alertTriangle,
            color: Color(0xFFF59E0B),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'تحذير: بعض المتطلبات غير متوفرة. يمكنك المتابعة لكن خاصية الدفع الإلكتروني لن تعمل.',
              style: GoogleFonts.tajawal(
                fontSize: 14,
                color: const Color(0xFF92400E),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool canContinue = _status != null;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: canContinue ? widget.onContinue : null,
            icon: const Icon(LucideIcons.arrowLeft),
            label: Text(
              'متابعة',
              style: GoogleFonts.tajawal(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF58220),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (widget.onBack != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(LucideIcons.arrowRight),
              label: Text(
                'رجوع',
                style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF64748B),
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
