// services/enrollment_service.dart
//
// Yüz tanıtma + RFID bağlama servisi.
//
// Yüz tanıtma iki yolla çalışır:
//   1. HTTP (telefon): Mac'te çalışan enroll_server.py'ye istek atar.
//      Mac kamerayı açar, encoding'i Firebase'e yazar.
//   2. Subprocess (Mac'te çalışırken): Doğrudan Python çalıştırır.
//
// RFID bağlama: Firebase'e direkt yazar.

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

class EnrollmentResult {
  final bool success;
  final String message;
  final int? exitCode;
  final String? stdout;
  final String? stderr;

  EnrollmentResult.ok(this.message)
      : success = true,
        exitCode = 0,
        stdout = null,
        stderr = null;

  EnrollmentResult.fail(this.message, {this.exitCode, this.stdout, this.stderr})
      : success = false;
}

class EnrollmentService {
  // ── Mac'teki enroll_server.py adresi ──────────────────────────────────────
  // Mac terminalde `python enroll_server.py` çalıştırınca gösterilen IP'yi yaz.
  // Telefon ve Mac aynı WiFi'da olmalı.
  static const String enrollServerIp   = '10.0.2.2'; // Android emülatör → Mac host
  static const int    enrollServerPort  = 5050;

  // ── Subprocess (Mac'te uygulama doğrudan çalışırken) ──────────────────────
  static const String pythonPath = '/Users/iremutusmac/face_attendance/venv/bin/python';
  static const String scriptDir  = '/Users/iremutusmac/face_attendance';
  static const String scriptName = 'main.py';

  static const Duration enrollTimeout = Duration(seconds: 120);

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // ── Yüz tanıtma ───────────────────────────────────────────────────────────

  Future<EnrollmentResult> enrollFace(String uid) async {
    if (uid.trim().isEmpty) return EnrollmentResult.fail("UID boş olamaz");

    // Önce HTTP sunucusunu dene (telefon / farklı cihaz)
    final httpResult = await _enrollViaHttp(uid);
    if (httpResult != null) return httpResult;

    // Fallback: subprocess (Mac'te çalışırken)
    return _enrollViaSubprocess(uid);
  }

  /// Mac'teki enroll_server.py'ye HTTP isteği atar.
  /// Sunucu çalışmıyorsa null döner → subprocess'e geçilir.
  Future<EnrollmentResult?> _enrollViaHttp(String uid) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final req = await client.get(enrollServerIp, enrollServerPort,
          '/enroll?uid=${Uri.encodeComponent(uid)}');
      final resp = await req.close().timeout(enrollTimeout);
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final ok  = json['ok'] == true;
      final msg = json['message']?.toString() ?? (ok ? 'Başarılı' : 'Hata');
      return ok ? EnrollmentResult.ok(msg) : EnrollmentResult.fail(msg);
    } on SocketException {
      // Sunucu açık değil → subprocess'e düş
      return null;
    } on TimeoutException {
      return EnrollmentResult.fail(
          'Zaman aşımı (${enrollTimeout.inSeconds}s). Kamera önünde SPACE\'e basıldı mı?');
    } catch (e) {
      return null; // bilinmeyen hata → subprocess dene
    }
  }

  Future<EnrollmentResult> _enrollViaSubprocess(String uid) async {
    if (!await File(pythonPath).exists()) {
      return EnrollmentResult.fail(
        'Yüz tanıtma için Mac\'te enroll_server.py çalıştırın:\n\n'
        'cd /Users/iremutusmac/face_attendance\n'
        'source venv/bin/activate\n'
        'python enroll_server.py\n\n'
        'Ardından enrollment_service.dart\'taki enrollServerIp değerini güncelleyin.',
      );
    }
    try {
      final result = await Process.run(
        pythonPath,
        [scriptName, 'enroll', '--uid', uid],
        workingDirectory: scriptDir,
      ).timeout(enrollTimeout);
      return _parseResult(result);
    } on TimeoutException {
      return EnrollmentResult.fail('Zaman aşımı (${enrollTimeout.inSeconds}s)');
    } catch (e) {
      return EnrollmentResult.fail('Subprocess hatası: $e');
    }
  }

  // ── Yoklama yüz tanıma (Mac webcam — sunucu üzerinden) ───────────────────

  /// Mac'teki enroll_server.py'ye GET /attend_face?tc=TC gönderir.
  /// Sunucu Mac webcam'ini açar, yüzü tanır ve face_ok yazar.
  Future<EnrollmentResult> attendFace(String tc, {String? sessionId}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      var path = '/attend_face?tc=${Uri.encodeComponent(tc)}';
      if (sessionId != null && sessionId.isNotEmpty) {
        path += '&session_id=${Uri.encodeComponent(sessionId)}';
      }
      final req = await client.get(enrollServerIp, enrollServerPort, path);
      final resp = await req.close().timeout(const Duration(seconds: 65));
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final ok  = json['ok'] == true;
      final msg = json['message']?.toString() ?? (ok ? 'Başarılı' : 'Hata');
      return ok ? EnrollmentResult.ok(msg) : EnrollmentResult.fail(msg);
    } on SocketException {
      return EnrollmentResult.fail('Sunucuya bağlanılamadı.\nenroll_server.py Mac\'te çalışıyor mu?');
    } on TimeoutException {
      return EnrollmentResult.fail('Zaman aşımı (65s). Kameraya bakıldı mı?');
    } catch (e) {
      return EnrollmentResult.fail('Hata: $e');
    }
  }

  // ── RFID bağlama (Firebase direkt) ────────────────────────────────────────

  Future<EnrollmentResult> bindRfidManual(String uid, String rfidUid) async {
    final cleanRfid = rfidUid.trim().toUpperCase();
    if (cleanRfid.isEmpty) return EnrollmentResult.fail("RFID UID boş olamaz");
    if (cleanRfid.length < 4) return EnrollmentResult.fail("RFID UID en az 4 karakter olmalı");

    final isTc    = uid.length == 11 && int.tryParse(uid) != null;
    final userPath = isTc ? 'on_kayitlar/$uid' : 'users/$uid';

    try {
      final existing = await _dbRef.child('rfid_index/$cleanRfid').get();
      if (existing.exists && existing.value != uid) {
        return EnrollmentResult.fail(
            'Bu kart zaten başka bir öğrenciye atanmış. Önce eski bağlantıyı kaldırın.');
      }
      final userSnap = await _dbRef.child(userPath).get();
      if (!userSnap.exists) {
        return EnrollmentResult.fail('Öğrenci bulunamadı: $userPath');
      }
      await _dbRef.child(userPath).update({'rfid_uid': cleanRfid});
      await _dbRef.child('rfid_index/$cleanRfid').set(uid);
      return EnrollmentResult.ok('Kart bağlandı: $cleanRfid');
    } catch (e) {
      return EnrollmentResult.fail('Firebase yazma hatası: $e');
    }
  }

  Future<EnrollmentResult> unbindRfid(String uid) async {
    final isTc    = uid.length == 11 && int.tryParse(uid) != null;
    final userPath = isTc ? 'on_kayitlar/$uid' : 'users/$uid';
    try {
      final snap = await _dbRef.child('$userPath/rfid_uid').get();
      if (!snap.exists) return EnrollmentResult.ok('Zaten bağlı kart yok');
      final oldRfid = snap.value.toString();
      await _dbRef.child(userPath).child('rfid_uid').remove();
      await _dbRef.child('rfid_index/$oldRfid').remove();
      return EnrollmentResult.ok('Kart kaldırıldı: $oldRfid');
    } catch (e) {
      return EnrollmentResult.fail('Hata: $e');
    }
  }

  Future<EnrollmentResult> removeFaceEncoding(String uid) async {
    final isTc    = uid.length == 11 && int.tryParse(uid) != null;
    final userPath = isTc ? 'on_kayitlar/$uid' : 'users/$uid';
    try {
      await _dbRef.child(userPath).child('face_encoding').remove();
      await _dbRef.child(userPath).child('face_photo_path').remove();
      return EnrollmentResult.ok('Yüz encoding\'i silindi');
    } catch (e) {
      return EnrollmentResult.fail('Hata: $e');
    }
  }

  // ── yardımcı ──────────────────────────────────────────────────────────────

  EnrollmentResult _parseResult(ProcessResult r) {
    final code = r.exitCode;
    final msgs = {
      0:  'Başarılı',
      10: 'İptal edildi',
      11: 'Kadrajda yüz bulunamadı',
      12: 'Birden fazla yüz var — tek yüz olmalı',
      13: 'Kamera açılamadı (macOS Gizlilik > Kamera izni gerekli)',
      14: 'Firebase yazma hatası',
    };
    final msg = msgs[code] ?? 'Bilinmeyen hata (exit=$code)';
    return code == 0
        ? EnrollmentResult.ok(msg)
        : EnrollmentResult.fail(msg, exitCode: code);
  }
}
