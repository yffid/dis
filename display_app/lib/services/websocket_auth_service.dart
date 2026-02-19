import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'security/security_config.dart';

/// Secure WebSocket Authentication Service
/// Implements JWT-based authentication with challenge-response
class WebSocketAuthService {
  static const String _secretKey = SecurityConfig.wsSharedSecret;
  static const Duration _tokenExpiry = Duration(hours: 1);
  static const Duration _challengeTimeout = Duration(seconds: 30);

  final Map<String, _AuthSession> _activeSessions = {};
  final Map<String, DateTime> _challengeTimes = {};

  /// Generate a challenge for the client to solve
  Map<String, dynamic> generateChallenge() {
    final challenge = _generateSecureRandomString(32);
    final timestamp = DateTime.now().toIso8601String();

    _challengeTimes[challenge] = DateTime.now();

    return {'challenge': challenge, 'timestamp': timestamp};
  }

  /// Verify client's response to the challenge
  bool verifyChallengeResponse(String challenge, String response) {
    // Check challenge timeout
    final challengeTime = _challengeTimes[challenge];
    if (challengeTime == null) return false;

    if (DateTime.now().difference(challengeTime) > _challengeTimeout) {
      _challengeTimes.remove(challenge);
      return false;
    }

    // Verify response (HMAC-SHA256 of challenge + secret)
    final expectedResponse = _calculateHmac(challenge, _secretKey);
    final isValid = _secureCompare(response, expectedResponse);

    if (isValid) {
      _challengeTimes.remove(challenge);
    }

    return isValid;
  }

  /// Generate JWT token for authenticated session
  String generateToken(String deviceId, {required bool isCashier}) {
    final issuedAt = DateTime.now();
    final expiry = issuedAt.add(_tokenExpiry);

    final payload = {
      'iss': 'hermosa_pos',
      'sub': deviceId,
      'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
      'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      'role': isCashier ? 'cashier' : 'display',
      'jti': _generateSecureRandomString(16),
    };

    final header = base64Url.encode(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})),
    );

    final payloadEncoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
    final signature = _calculateHmac('$header.$payloadEncoded', _secretKey);

    final token = '$header.$payloadEncoded.$signature';

    // Store session
    _activeSessions[deviceId] = _AuthSession(
      token: token,
      deviceId: deviceId,
      role: payload['role'] as String,
      expiry: expiry,
    );

    return token;
  }

  /// Validate JWT token
  bool validateToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;

      final payload = jsonDecode(utf8.decode(base64Url.decode(parts[1])));
      final exp = payload['exp'] as int?;

      if (exp == null) return false;
      if (DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp) return false;

      // Verify signature
      final expectedSignature = _calculateHmac(
        '${parts[0]}.${parts[1]}',
        _secretKey,
      );
      if (!_secureCompare(parts[2], expectedSignature)) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Extract device ID from token
  String? getDeviceIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = jsonDecode(utf8.decode(base64Url.decode(parts[1])));
      return payload['sub'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Check if device is authenticated
  bool isAuthenticated(String deviceId) {
    final session = _activeSessions[deviceId];
    if (session == null) return false;
    if (DateTime.now().isAfter(session.expiry)) {
      _activeSessions.remove(deviceId);
      return false;
    }
    return true;
  }

  /// Remove session on disconnect
  void removeSession(String deviceId) {
    _activeSessions.remove(deviceId);
  }

  /// Clean up expired sessions
  void cleanupExpiredSessions() {
    final now = DateTime.now();
    _activeSessions.removeWhere((_, session) => now.isAfter(session.expiry));
    _challengeTimes.removeWhere(
      (_, time) => now.difference(time) > _challengeTimeout,
    );
  }

  String _generateSecureRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(values);
  }

  String _calculateHmac(String data, String key) {
    final hmac = Hmac(sha256, utf8.encode(key));
    return base64Url.encode(hmac.convert(utf8.encode(data)).bytes);
  }

  bool _secureCompare(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

class _AuthSession {
  final String token;
  final String deviceId;
  final String role;
  final DateTime expiry;

  _AuthSession({
    required this.token,
    required this.deviceId,
    required this.role,
    required this.expiry,
  });
}

/// Singleton instance
final webSocketAuthService = WebSocketAuthService();
