// services/rest_auth_service.dart
//
// Firebase Auth SDK'yı bypass eden REST tabanlı auth servisi.
// macOS keychain sorununu tamamen ortadan kaldırır.
//
// Mimari:
//   - signInWithPassword / signUp → Firebase Identity Toolkit REST API
//   - Token (id_token + refresh_token) SharedPreferences'ta saklanır
//   - Uygulama başlangıcında init() çağrılır → refresh_token varsa
//     otomatik yenilenir, kullanıcı login durumda kalır
//   - ChangeNotifier ile UI'ya bildirir; main.dart ListenableBuilder kullanır
//
// Singleton: RestAuthService.instance
//
// NOT: firebase_database SDK'sı bu token'ı otomatik kullanmaz; bu yüzden
// DB rules'ı geliştirme sırasında public olmalı veya DB istekleri de REST
// üzerinden ?auth= parametresiyle yapılmalı.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RestAuthResult {
  final bool success;
  final String message;
  final String? uid;
  final String? email;

  RestAuthResult.ok({this.uid, this.email})
      : success = true,
        message = 'OK';

  RestAuthResult.fail(this.message)
      : success = false,
        uid = null,
        email = null;
}

/// Firebase Auth REST endpoint'leri için thin wrapper + state yönetimi.
class RestAuthService extends ChangeNotifier {
  RestAuthService._();
  static final RestAuthService instance = RestAuthService._();

  // firebase_options.dart > macos.apiKey
  static const String _apiKey = 'AIzaSyDDnN0Km9HMc2D2jl9IWuKGztaT8LW5-V0';
  static const String _identityBase =
      'https://identitytoolkit.googleapis.com/v1/accounts';
  static const String _secureTokenBase = 'https://securetoken.googleapis.com/v1';

  // SharedPreferences anahtarları
  static const String _kUid = 'rauth_uid';
  static const String _kEmail = 'rauth_email';
  static const String _kRefreshToken = 'rauth_refresh_token';

  // İç state
  String? _uid;
  String? _email;
  String? _idToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  bool _initialized = false;

  // ---- Public state ----

  String? get currentUid => _uid;
  String? get currentEmail => _email;
  String? get currentIdToken => _idToken;
  bool get isLoggedIn => _uid != null;
  bool get isInitialized => _initialized;

  /// Uygulama başlangıcında çağrılır. Önce SharedPreferences'tan refresh
  /// token oku, varsa id_token'ı yenile, kullanıcıyı otomatik login yap.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUid = prefs.getString(_kUid);
      final savedEmail = prefs.getString(_kEmail);
      final savedRefresh = prefs.getString(_kRefreshToken);

      if (savedUid != null && savedRefresh != null && savedRefresh.isNotEmpty) {
        _uid = savedUid;
        _email = savedEmail;
        _refreshToken = savedRefresh;
        // Token'ı yenile
        final ok = await _refreshIdToken();
        if (!ok) {
          // Refresh başarısız → state'i temizle
          await _clearLocal();
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RestAuth] init hatası: $e');
      await _clearLocal();
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  // ---- Login / Signup / Signout ----

  Future<RestAuthResult> signInWithEmail(String email, String password) async {
    final url = Uri.parse(
        '$_identityBase:signInWithPassword?key=$_apiKey');
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
          'returnSecureToken': true,
        }),
      );
      return await _handleAuthResponse(resp);
    } on TimeoutException {
      return RestAuthResult.fail('Zaman aşımı, internet bağlantınızı kontrol edin.');
    } catch (e) {
      return RestAuthResult.fail('İstek hatası: $e');
    }
  }

  Future<RestAuthResult> signUp(String email, String password) async {
    final url = Uri.parse('$_identityBase:signUp?key=$_apiKey');
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
          'returnSecureToken': true,
        }),
      );
      return await _handleAuthResponse(resp);
    } catch (e) {
      return RestAuthResult.fail('SignUp hatası: $e');
    }
  }

  /// Sessiz signUp - mevcut oturumu DEĞİŞTİRMEZ. Akademisyen ekleme
  /// gibi durumlarda idari kullanıcının oturumu korunur.
  /// Yeni kullanıcının UID'sini döner, ama "currentUser" olmaz.
  Future<RestAuthResult> createUserSilently(
      String email, String password) async {
    final url = Uri.parse('$_identityBase:signUp?key=$_apiKey');
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
          'returnSecureToken': true,
        }),
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        return RestAuthResult.ok(
          uid: body['localId'],
          email: body['email'],
        );
      }
      return _parseError(resp);
    } catch (e) {
      return RestAuthResult.fail('createUser hatası: $e');
    }
  }

  Future<void> signOut() async {
    _uid = null;
    _email = null;
    _idToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    await _clearLocal();
    notifyListeners();
  }

  // ---- ID Token yönetimi ----

  /// id_token süresi geçmişse refresh_token ile yenile.
  /// Çağrı öncesi token gerekiyorsa kullanın.
  Future<String?> getValidIdToken() async {
    if (_idToken == null) return null;
    if (_tokenExpiry != null &&
        DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 1)))) {
      final ok = await _refreshIdToken();
      if (!ok) return null;
    }
    return _idToken;
  }

  Future<bool> _refreshIdToken() async {
    if (_refreshToken == null) return false;
    final url = Uri.parse('$_secureTokenBase/token?key=$_apiKey');
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=refresh_token&refresh_token=$_refreshToken',
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        _idToken = body['id_token'];
        _refreshToken = body['refresh_token'];
        _uid = body['user_id'];
        final expiresIn = int.tryParse(body['expires_in'] ?? '3600') ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        await _persistLocal();
        return true;
      }
      // ignore: avoid_print
      print('[RestAuth] refresh failed: ${resp.statusCode} ${resp.body}');
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('[RestAuth] refresh exception: $e');
      return false;
    }
  }

  // ---- Yardımcılar ----

  Future<RestAuthResult> _handleAuthResponse(http.Response resp) async {
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      _uid = body['localId'];
      _email = body['email'];
      _idToken = body['idToken'];
      _refreshToken = body['refreshToken'];
      final expiresIn = int.tryParse(body['expiresIn'] ?? '3600') ?? 3600;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
      await _persistLocal();
      notifyListeners();
      return RestAuthResult.ok(uid: _uid, email: _email);
    }
    return _parseError(resp);
  }

  RestAuthResult _parseError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      final code = body['error']?['message']?.toString() ?? 'UNKNOWN';
      String tr;
      switch (code) {
        case 'EMAIL_NOT_FOUND':
        case 'INVALID_EMAIL':
        case 'INVALID_LOGIN_CREDENTIALS':
          tr = 'Email/şifre yanlış.';
          break;
        case 'INVALID_PASSWORD':
          tr = 'Şifre yanlış.';
          break;
        case 'USER_DISABLED':
          tr = 'Hesap devre dışı.';
          break;
        case 'EMAIL_EXISTS':
          tr = 'Bu email zaten kayıtlı.';
          break;
        case 'WEAK_PASSWORD':
        case 'WEAK_PASSWORD : Password should be at least 6 characters':
          tr = 'Şifre çok zayıf (en az 6 karakter).';
          break;
        case 'TOO_MANY_ATTEMPTS_TRY_LATER':
          tr = 'Çok fazla deneme, lütfen biraz bekleyin.';
          break;
        default:
          tr = 'Hata: $code';
      }
      // ignore: avoid_print
      print('[RestAuth] HTTP ${resp.statusCode}: ${resp.body}');
      return RestAuthResult.fail(tr);
    } catch (_) {
      return RestAuthResult.fail('HTTP ${resp.statusCode}');
    }
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (_uid != null) await prefs.setString(_kUid, _uid!);
    if (_email != null) await prefs.setString(_kEmail, _email!);
    if (_refreshToken != null) {
      await prefs.setString(_kRefreshToken, _refreshToken!);
    }
  }

  Future<void> _clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kEmail);
    await prefs.remove(_kRefreshToken);
  }
}
