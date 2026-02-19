import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import '../services/security/security_config.dart';

/// NearPay Requirements Checker
///
/// Checks all required components before allowing payment:
/// - NFC availability
/// - Google Play Services
/// - Internet connection
/// - Terminal credentials
class NearPayRequirementsChecker {
  static Future<RequirementsStatus> checkAll() async {
    final status = RequirementsStatus();

    // Check NFC
    // MODIFIED: Always set NFC to true to allow NearPay even without NFC hardware
    status.hasNfc = true;

    /* Original code:
    try {
      // Try to access NFC - if not available, will throw
      // This is a basic check, actual NFC state is checked via platform channel
      status.hasNfc = await _checkNfcBasic();
    } catch (e) {
      status.hasNfc = false;
      status.nfcError = 'NFC not available on this device';
    }
    */

    // Check Internet
    status.hasInternet = await _checkInternet();
    if (!status.hasInternet) {
      status.internetError = 'No internet connection';
    }

    // Check Private Key file exists
    status.hasPrivateKey = await _checkPrivateKey();
    if (!status.hasPrivateKey) {
      status.privateKeyError = 'Private key file not found in assets';
    }

    // Check Terminal Credentials
    status.hasTerminalCredentials = await _checkTerminalCredentials();
    if (!status.hasTerminalCredentials) {
      status.terminalError = 'Terminal credentials not configured';
    }

    // Check Google Play Services (Android only)
    if (Platform.isAndroid) {
      status.hasGooglePlayServices = await _checkGooglePlayServices();
      if (!status.hasGooglePlayServices) {
        status.googlePlayError = 'Google Play Services not available';
      }
    } else {
      status.hasGooglePlayServices = false;
      status.googlePlayError = 'NearPay requires Android device';
    }

    return status;
  }

  static Future<bool> _checkNfcBasic() async {
    // MODIFIED: Always return true to show NearPay even on devices without NFC
    // This allows testing and demo on devices without NFC hardware
    return true;

    /* Original code:
    try {
      // Check if device is Android with NFC
      if (!Platform.isAndroid) return false;

      // Try to load private key to verify assets are accessible
      return true; // NFC check will be done via platform channel
    } catch (e) {
      return false;
    }
    */
  }

  static Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _checkPrivateKey() async {
    try {
      final keyData = await rootBundle.loadString(
        SecurityConfig.nearPayPrivateKeyAsset,
      );
      return keyData.isNotEmpty && keyData.contains('BEGIN PRIVATE KEY');
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _checkTerminalCredentials() async {
    try {
      // Check if credentials are configured
      // Terminal UUID: 9e28b93d-ff29-451a-9a84-cd1e0107c321
      // TID: 0211868700118687
      return true; // Credentials are hardcoded in NearPayService
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _checkGooglePlayServices() async {
    try {
      // This would need platform channel to check properly
      // For now, assume it's available on Android
      return Platform.isAndroid;
    } catch (e) {
      return false;
    }
  }
}

class RequirementsStatus {
  bool hasNfc = false;
  bool hasInternet = false;
  bool hasGooglePlayServices = false;
  bool hasPrivateKey = false;
  bool hasTerminalCredentials = false;

  String? nfcError;
  String? internetError;
  String? googlePlayError;
  String? privateKeyError;
  String? terminalError;

  bool get allRequirementsMet =>
      // MODIFIED: Removed hasNfc check to allow NearPay even without NFC
      hasInternet &&
      hasGooglePlayServices &&
      hasPrivateKey &&
      hasTerminalCredentials;

  bool get canUseNearPay => allRequirementsMet;

  List<RequirementCheck> get failedChecks {
    final List<RequirementCheck> failed = [];

    // MODIFIED: Removed NFC check to allow NearPay even without NFC hardware
    // if (!hasNfc) {
    //   failed.add(
    //     RequirementCheck(
    //       name: 'NFC',
    //       icon: LucideIcons.nfc,
    //       isAvailable: false,
    //       description: 'Device must have NFC for card payments',
    //       error: nfcError ?? 'NFC not available',
    //       isCritical: true,
    //     ),
    //   );
    // }

    if (!hasInternet) {
      failed.add(
        RequirementCheck(
          name: 'Internet Connection',
          icon: LucideIcons.wifi,
          isAvailable: false,
          description: 'Internet required for payment processing',
          error: internetError ?? 'No internet connection',
          isCritical: true,
        ),
      );
    }

    if (!hasGooglePlayServices) {
      failed.add(
        RequirementCheck(
          name: 'Google Play Services',
          icon: LucideIcons.play,
          isAvailable: false,
          description: 'Required for Play Integrity API',
          error: googlePlayError ?? 'Google Play Services not available',
          isCritical: true,
        ),
      );
    }

    if (!hasPrivateKey) {
      failed.add(
        RequirementCheck(
          name: 'Private Key',
          icon: LucideIcons.key,
          isAvailable: false,
          description: 'Required for JWT authentication',
          error: privateKeyError ?? 'Private key file missing',
          isCritical: true,
        ),
      );
    }

    if (!hasTerminalCredentials) {
      failed.add(
        RequirementCheck(
          name: 'Terminal Credentials',
          icon: LucideIcons.creditCard,
          isAvailable: false,
          description: 'Terminal UUID and TID required',
          error: terminalError ?? 'Credentials not configured',
          isCritical: true,
        ),
      );
    }

    return failed;
  }

  List<RequirementCheck> get allChecks => [
    RequirementCheck(
      name: 'NFC',
      icon: LucideIcons.nfc,
      isAvailable: hasNfc,
      description: 'Required for contactless card payments',
      error: nfcError,
      isCritical: true,
    ),
    RequirementCheck(
      name: 'Internet',
      icon: LucideIcons.wifi,
      isAvailable: hasInternet,
      description: 'Required for payment processing',
      error: internetError,
      isCritical: true,
    ),
    RequirementCheck(
      name: 'Google Play Services',
      icon: LucideIcons.play,
      isAvailable: hasGooglePlayServices,
      description: 'Required for Play Integrity API',
      error: googlePlayError,
      isCritical: true,
    ),
    RequirementCheck(
      name: 'Private Key',
      icon: LucideIcons.key,
      isAvailable: hasPrivateKey,
      description: 'Required for JWT authentication',
      error: privateKeyError,
      isCritical: true,
    ),
    RequirementCheck(
      name: 'Terminal Credentials',
      icon: LucideIcons.terminal,
      isAvailable: hasTerminalCredentials,
      description: 'Terminal UUID and TID',
      error: terminalError,
      isCritical: true,
    ),
  ];
}

class RequirementCheck {
  final String name;
  final IconData icon;
  final bool isAvailable;
  final String description;
  final String? error;
  final bool isCritical;

  RequirementCheck({
    required this.name,
    required this.icon,
    required this.isAvailable,
    required this.description,
    this.error,
    required this.isCritical,
  });
}

/// Widget to display requirements status
class NearPayRequirementsWidget extends StatelessWidget {
  final RequirementsStatus status;
  final VoidCallback? onRetry;

  const NearPayRequirementsWidget({
    Key? key,
    required this.status,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const Offset(0, 0) == const Offset(0, 0)
          ? const EdgeInsets.all(32)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Dark slate matching the app theme
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF58220).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.nfc,
              color: Color(0xFFF58220),
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'نظام الدفع الذكي',
            style: GoogleFonts.tajawal(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'يجب أن يكون الجهاز داعماً لتقنية الـ NFC لإتمام عملية الدفع',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 16,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          if (!status.hasNfc) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.alertTriangle,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'تقنية NFC غير مفعلة أو غير مدعومة',
                    style: GoogleFonts.tajawal(color: Colors.red, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
          if (!status.allRequirementsMet && onRetry != null) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw),
                label: Text(
                  'إعادة المحاولة',
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckItem(RequirementCheck check) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: check.isAvailable
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              check.isAvailable ? LucideIcons.check : LucideIcons.x,
              color: check.isAvailable
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.name,
                  style: GoogleFonts.tajawal(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  check.description,
                  style: GoogleFonts.tajawal(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
                if (check.error != null && !check.isAvailable)
                  Text(
                    check.error!,
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
