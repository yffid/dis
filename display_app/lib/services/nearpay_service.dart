import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'security/security_config.dart';

/// NearPay Service for JWT generation and authentication
///
/// Credentials from NearPay Dashboard:
/// - Client UUID: 55df27ff-0b1c-430f-a137-3d8dd96d4af0
/// - Terminal ID (TID): 0211868700118687
/// - Google Cloud Project Number: 764962961378
class NearPayService {
  // NearPay Configuration
  static const String _clientUuid = SecurityConfig.nearPayClientUuid;
  static const String _terminalId = SecurityConfig.nearPayTerminalId;
  static const String _googleCloudProjectNumber =
      SecurityConfig.nearPayGoogleCloudProjectNumber;

  // JWT Key file asset path
  static const String _privateKeyAsset = SecurityConfig.nearPayPrivateKeyAsset;

  String? _cachedJwt;
  DateTime? _jwtExpiry;
  String? _cachedPrivateKey;

  /// Generate JWT token for NearPay authentication
  ///
  /// The JWT contains:
  /// - client_uuid: The client UUID from NearPay dashboard
  /// - terminal_id: The terminal ID (TID) from NearPay dashboard
  /// - ops: The operation type ("auth")
  Future<String> generateJwt() async {
    try {
      // Check if we have a valid cached token
      if (_cachedJwt != null && _jwtExpiry != null) {
        if (DateTime.now().isBefore(_jwtExpiry!)) {
          return _cachedJwt!;
        }
      }

      // Load private key
      final privateKeyPem = await _loadPrivateKey();
      if (privateKeyPem == null) {
        throw Exception('Failed to load private key');
      }

      // Create JWT payload according to NearPay requirements
      final payload = {
        'data': {
          'ops': 'auth',
          'client_uuid': _clientUuid,
          'terminal_id': _terminalId,
        },
      };

      // Create and sign JWT
      final jwt = JWT(payload, header: {'alg': 'RS256', 'typ': 'JWT'});

      final token = jwt.sign(
        RSAPrivateKey(privateKeyPem),
        algorithm: JWTAlgorithm.RS256,
      );

      // Cache the token (expires in 1 hour)
      _cachedJwt = token;
      _jwtExpiry = DateTime.now().add(const Duration(hours: 1));

      debugPrint('NearPay JWT generated successfully');
      return token;
    } catch (e) {
      debugPrint('Error generating NearPay JWT: $e');
      rethrow;
    }
  }

  /// Load private key from Flutter assets
  Future<String?> _loadPrivateKey() async {
    try {
      // Return cached key if available
      if (_cachedPrivateKey != null) {
        return _cachedPrivateKey;
      }

      // Load from Flutter assets bundle
      final key = await rootBundle.loadString(_privateKeyAsset);
      _cachedPrivateKey = key;
      debugPrint('Private key loaded from assets successfully');
      return key;
    } catch (e) {
      debugPrint('Error loading private key from assets: $e');
      return null;
    }
  }

  /// Get Client UUID
  String get clientUuid => _clientUuid;

  /// Get Terminal ID
  String get terminalId => _terminalId;

  /// Get Google Cloud Project Number
  String get googleCloudProjectNumber => _googleCloudProjectNumber;

  /// Get the terminal credentials for NearPay initialization
  Map<String, dynamic> getTerminalCredentials() {
    return {
      'clientUuid': _clientUuid,
      'terminalId': _terminalId,
      'googleCloudProjectNumber': _googleCloudProjectNumber,
    };
  }

  /// Clear cached JWT (useful for logout or token refresh)
  void clearCache() {
    _cachedJwt = null;
    _jwtExpiry = null;
    debugPrint('NearPay JWT cache cleared');
  }
}
