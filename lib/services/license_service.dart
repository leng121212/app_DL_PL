import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LicenseState {
  const LicenseState({
    required this.isLoggedIn,
    this.email,
    this.status = 'none',
    this.expiresAt,
    this.denialCode,
    this.denialMessage,
    this.isOffline = false,
  });

  factory LicenseState.unauthenticated([String? code, String? message]) {
    return LicenseState(
      isLoggedIn: false,
      status: 'unauthenticated',
      denialCode: code,
      denialMessage: message,
    );
  }

  factory LicenseState.active({
    required String email,
    required DateTime expiresAt,
    bool isOffline = false,
  }) {
    return LicenseState(
      isLoggedIn: true,
      email: email,
      status: 'active',
      expiresAt: expiresAt,
      isOffline: isOffline,
    );
  }

  final bool isLoggedIn;
  final String? email;
  final String status;
  final DateTime? expiresAt;
  final String? denialCode;
  final String? denialMessage;
  final bool isOffline;

  int get remainingDays {
    if (expiresAt == null) return 0;
    final diff = expiresAt!.difference(DateTime.now());
    return diff.inDays.clamp(0, 999999);
  }
}

class AuthSessionInfo {
  AuthSessionInfo({
    required this.sessionId,
    required this.pollToken,
    required this.loginUrl,
    required this.verifier,
  });

  final String sessionId;
  final String pollToken;
  final String loginUrl;
  final String verifier;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'poll_token': pollToken,
    'login_url': loginUrl,
    'verifier': verifier,
  };

  factory AuthSessionInfo.fromJson(Map<String, dynamic> json) => AuthSessionInfo(
    sessionId: json['session_id'] ?? '',
    pollToken: json['poll_token'] ?? '',
    loginUrl: json['login_url'] ?? '',
    verifier: json['verifier'] ?? '',
  );
}

class LicenseService with ChangeNotifier {
  static final LicenseService instance = LicenseService._internal();
  LicenseService._internal();

  static const String serverUrl = 'https://license-dub-pro.onrender.com';
  static const String productId = 'trabekprey-dl-phone';
  static const String contactUrl = 'https://t.me/Chhunleng1122';

  LicenseState _state = LicenseState.unauthenticated();
  LicenseState get state => _state;
  bool _isChecking = true;
  bool get isChecking => _isChecking;

  String? _cachedDeviceHash;

  Future<void> init() async {
    await checkLicense();
  }

  /// Get or create a persistent 64-character SHA-256 device hash for single-device binding
  Future<String> getDeviceHash() async {
    if (_cachedDeviceHash != null && _cachedDeviceHash!.length == 64) {
      return _cachedDeviceHash!;
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, '.trabekprey_device_id'));
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (RegExp(r'^[0-9a-f]{64}$').hasMatch(content)) {
          _cachedDeviceHash = content;
          return content;
        }
      }
      final rand = Random.secure();
      final randomBytes = List<int>.generate(32, (_) => rand.nextInt(256));
      final hash = sha256.convert(randomBytes).toString().toLowerCase();
      await file.writeAsString(hash);
      _cachedDeviceHash = hash;
      return hash;
    } catch (_) {
      final fallback = sha256.convert(utf8.encode('fallback_device_${DateTime.now().millisecondsSinceEpoch}')).toString();
      _cachedDeviceHash = fallback;
      return fallback;
    }
  }

  static String _generateCodeVerifier() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(43, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  static String _generateCodeChallenge(String verifier) {
    final bytes = ascii.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static String getMessageForCode(String code) {
    switch (code) {
      case 'NO_LICENSE':
        return 'គណនី Gmail នេះមិនទាន់មាន License ទេ។ សូមទាក់ទង Admin ដើម្បី Activate។';
      case 'DEVICE_MISMATCH':
        return 'គណនីនេះត្រូវបានភ្ជាប់លើទូរសព្ទផ្សេងរួចហើយ (អនុញ្ញាតតែ ១ Device ប៉ុណ្ណោះ)!';
      case 'LICENSE_SUSPENDED':
        return 'License ត្រូវបានផ្អាកជាបណ្ដោះអាសន្ន។ សូមទាក់ទង Admin។';
      case 'LICENSE_REVOKED':
        return 'License ត្រូវបានដកហូត។ សូមទាក់ទង Admin។';
      case 'LICENSE_EXPIRED':
        return 'License បានផុតកំណត់ហើយ។ សូមទាក់ទង Admin ដើម្បីបន្តសុពលភាព។';
      case 'SESSION_EXPIRED':
        return 'ការចូលគណនីបានផុតកំណត់។ សូមសាកល្បងម្ដងទៀត។';
      default:
        return 'មិនអាចផ្ទៀងផ្ទាត់ License បានទេ ($code)។';
    }
  }

  /// Check license status online and verify device binding
  Future<LicenseState> checkLicense() async {
    _isChecking = true;
    notifyListeners();

    try {
      final creds = await _loadSavedCredentials();
      final refreshToken = creds['refresh_token'];

      if (refreshToken == null || refreshToken.isEmpty) {
        _state = LicenseState.unauthenticated();
        _isChecking = false;
        notifyListeners();
        return _state;
      }

      final devHash = await getDeviceHash();
      final uri = Uri.parse('$serverUrl/api/v1/license/refresh');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refresh_token': refreshToken,
          'device_hash': devHash,
        }),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final newLease = data['lease'] as String?;
        final newRefreshToken = data['refresh_token'] as String? ?? refreshToken;
        if (newLease != null) {
          await _saveCredentials(newRefreshToken, newLease);
          _applyLease(newLease);
          _isChecking = false;
          notifyListeners();
          return _state;
        }
      } else {
        try {
          final data = jsonDecode(res.body);
          final code = data['detail']?['code'] ?? 'LICENSE_DENIED';
          final msg = data['detail']?['message'] ?? getMessageForCode(code);
          await _clearCredentials();
          _state = LicenseState.unauthenticated(code, msg);
        } catch (_) {
          await _clearCredentials();
          _state = LicenseState.unauthenticated('AUTH_FAILED', 'សូមចូលគណនីឡើងវិញ');
        }
        _isChecking = false;
        notifyListeners();
        return _state;
      }
    } catch (_) {
      // In case of momentary offline connection, verify local cached lease if still valid
      final creds = await _loadSavedCredentials();
      final cachedLease = creds['lease'];
      if (cachedLease != null && cachedLease.isNotEmpty) {
        final ok = _applyLeaseIfValid(cachedLease);
        if (ok) {
          _isChecking = false;
          notifyListeners();
          return _state;
        }
      }
      _state = LicenseState.unauthenticated('NETWORK_ERROR', 'មិនអាចភ្ជាប់ទៅកាន់ម៉ាស៊ីនបម្រើ License បានទេ');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
    return _state;
  }

  bool _isExchanging = false;

  Future<void> savePendingSession(AuthSessionInfo info) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, '.trabekprey_pending_session'));
      await file.writeAsString(jsonEncode(info.toJson()));
    } catch (_) {}
  }

  Future<AuthSessionInfo?> loadPendingSession() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, '.trabekprey_pending_session'));
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        final session = AuthSessionInfo.fromJson(data);
        if (session.sessionId.isNotEmpty && session.verifier.isNotEmpty) {
          return session;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> clearPendingSession() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, '.trabekprey_pending_session'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Start authentication session with PKCE and product binding
  Future<AuthSessionInfo?> startLogin() async {
    try {
      final devHash = await getDeviceHash();
      final verifier = _generateCodeVerifier();
      final challenge = _generateCodeChallenge(verifier);

      String devName = 'Android Phone';
      try {
        devName = 'Android (${Platform.operatingSystemVersion})';
      } catch (_) {}

      final uri = Uri.parse('$serverUrl/api/v1/auth/session');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_hash': devHash,
          'device_name': devName,
          'code_challenge': challenge,
          'product_id': productId,
        }),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final info = AuthSessionInfo(
          sessionId: data['session_id'] ?? '',
          pollToken: data['poll_token'] ?? '',
          loginUrl: data['login_url'] ?? '',
          verifier: verifier,
        );
        await savePendingSession(info);
        return info;
      }
    } catch (_) {}
    return null;
  }

  /// Poll server for authorization completion and exchange for tokens
  Future<bool> pollLogin(AuthSessionInfo info) async {
    if (_isExchanging) return false;
    try {
      final uri = Uri.parse('$serverUrl/api/v1/auth/poll');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': info.sessionId,
          'poll_token': info.pollToken,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final status = data['status'];
        if (status == 'authorized') {
          if (data['exchange_code'] != null) {
            return await _exchangeCode(info.sessionId, data['exchange_code'], info.verifier);
          } else if (data['already_used'] == true) {
            final check = await checkLicense();
            if (check.isLoggedIn) {
              await clearPendingSession();
              return true;
            }
          }
        } else if (status == 'denied') {
          final code = data['code'] ?? 'AUTH_DENIED';
          if (code == 'SESSION_USED') {
            final check = await checkLicense();
            if (check.isLoggedIn) {
              await clearPendingSession();
              return true;
            }
          }
          _state = LicenseState.unauthenticated(code, getMessageForCode(code));
          notifyListeners();
          return false;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _exchangeCode(String sessionId, String exchangeCode, String verifier) async {
    if (_isExchanging) return false;
    _isExchanging = true;
    try {
      final uri = Uri.parse('$serverUrl/api/v1/auth/exchange');
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final res = await http.post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'exchange_code': exchangeCode,
              'code_verifier': verifier,
            }),
          ).timeout(const Duration(seconds: 12));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final refreshToken = data['refresh_token'] as String?;
            final lease = data['lease'] as String?;
            if (refreshToken != null && lease != null) {
              final parts = lease.split('.');
              if (parts.isNotEmpty) {
                final norm = base64Url.normalize(parts[0]);
                final pData = jsonDecode(utf8.decode(base64Url.decode(norm))) as Map<String, dynamic>;
                final leaseProduct = pData['product_id'] as String?;
                if (leaseProduct != null && leaseProduct.isNotEmpty && leaseProduct != productId) {
                  await _clearCredentials();
                  _state = LicenseState.unauthenticated('PRODUCT_MISMATCH', 'License នេះសម្រាប់ $leaseProduct មិនមែនសម្រាប់ Trabekprey-DL Pro ទេ។');
                  notifyListeners();
                  return false;
                }
              }
              await _saveCredentials(refreshToken, lease);
              _applyLease(lease);
              await clearPendingSession();
              notifyListeners();
              return true;
            }
          } else {
            final creds = await _loadSavedCredentials();
            if (creds['refresh_token'] != null) {
              final check = await checkLicense();
              if (check.isLoggedIn) {
                await clearPendingSession();
                return true;
              }
            }
            final data = jsonDecode(res.body);
            final code = data['detail']?['code'] ?? 'EXCHANGE_FAILED';
            final msg = data['detail']?['message'] ?? getMessageForCode(code);
            _state = LicenseState.unauthenticated(code, msg);
            notifyListeners();
            return false;
          }
        } catch (_) {
          if (attempt == 2) rethrow;
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }
    } catch (_) {
      final creds = await _loadSavedCredentials();
      if (creds['refresh_token'] != null) {
        final check = await checkLicense();
        if (check.isLoggedIn) {
          await clearPendingSession();
          return true;
        }
      }
    } finally {
      _isExchanging = false;
    }
    return false;
  }

  void _applyLease(String lease) {
    try {
      final parts = lease.split('.');
      if (parts.isEmpty) return;
      final normalized = base64Url.normalize(parts[0]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(payloadJson) as Map<String, dynamic>;

      final leaseProduct = data['product_id'] as String?;
      if (leaseProduct != null && leaseProduct.isNotEmpty && leaseProduct != productId) {
        _clearCredentials();
        _state = LicenseState.unauthenticated('PRODUCT_MISMATCH', 'License នេះសម្រាប់ $leaseProduct មិនមែនសម្រាប់ Trabekprey-DL Pro ទេ។');
        return;
      }

      final email = data['email'] as String? ?? 'User';
      final expSec = data['expires_at'] as int?;
      final DateTime exp = expSec != null
          ? DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true).toLocal()
          : DateTime.now().add(const Duration(days: 30));

      final status = data['status'] as String? ?? 'active';
      if (status == 'active' && exp.isAfter(DateTime.now())) {
        _state = LicenseState.active(email: email, expiresAt: exp);
      } else {
        _state = LicenseState.unauthenticated('EXPIRED', 'License បានផុតកំណត់ហើយ');
      }
    } catch (_) {
      _state = LicenseState.unauthenticated('CORRUPT_LEASE', 'ទិន្នន័យ License មិនត្រឹមត្រូវ');
    }
  }

  bool _applyLeaseIfValid(String lease) {
    try {
      final parts = lease.split('.');
      if (parts.isEmpty) return false;
      final normalized = base64Url.normalize(parts[0]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(payloadJson) as Map<String, dynamic>;

      final leaseProduct = data['product_id'] as String?;
      if (leaseProduct != null && leaseProduct.isNotEmpty && leaseProduct != productId) {
        return false;
      }

      final email = data['email'] as String? ?? 'User';
      final expSec = data['expires_at'] as int?;
      final DateTime exp = expSec != null
          ? DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true).toLocal()
          : DateTime.now().add(const Duration(days: 30));

      final status = data['status'] as String? ?? 'active';
      if (status == 'active' && exp.isAfter(DateTime.now())) {
        _state = LicenseState.active(email: email, expiresAt: exp, isOffline: true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> logout() async {
    try {
      final creds = await _loadSavedCredentials();
      final refreshToken = creds['refresh_token'];
      if (refreshToken != null && refreshToken.isNotEmpty) {
        final uri = Uri.parse('$serverUrl/api/v1/license/logout');
        await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        ).timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    await _clearCredentials();
    _state = LicenseState.unauthenticated();
    notifyListeners();
  }

  Future<Map<String, String?>> _loadSavedCredentials() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, '.trabekprey_license_data'));
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        return {
          'refresh_token': data['refresh_token'] as String?,
          'lease': data['lease'] as String?,
        };
      }
    } catch (_) {}
    return {'refresh_token': null, 'lease': null};
  }

  Future<void> _saveCredentials(String refreshToken, String lease) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, '.trabekprey_license_data'));
      await file.writeAsString(jsonEncode({
        'refresh_token': refreshToken,
        'lease': lease,
        'updated_at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  Future<void> _clearCredentials() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, '.trabekprey_license_data'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
