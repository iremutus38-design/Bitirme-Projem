import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/academician_model.dart';
import 'rest_auth_service.dart';

/// Yeni akademisyen oluşturma işleminin sonucu.
class AcademicianCreateResult {
  final bool success;
  final String message;
  final String? uid;
  AcademicianCreateResult.ok(this.uid, [this.message = "Akademisyen oluşturuldu"])
      : success = true;
  AcademicianCreateResult.fail(this.message)
      : success = false,
        uid = null;
}

class AcademicianService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  /// Firebase için güvenli bir ID oluşturur (Nokta, $, #, [, ], / gibi karakterleri temizler)
  String _generateSafeId(String name) {
    return name
        .replaceAll(" ", "_")
        .replaceAll(RegExp(r'[.#$\[\]]'), "") // Firebase'in yasakladığı karakterleri siler
        .toLowerCase();
  }

  /// EXCEL'DEN AKADEMİSYENLERİ ÇEKER, HER BİRİ İÇİN DOĞRUDAN AUTH HESABI AÇAR.
  /// Varsayılan şifre: Akademisyen2026
  /// Mevcut email varsa şifre güncellenir, yeni kayıt oluşturulmaz.
  /// [onProgress] → (tamamlanan, toplam)
  Future<int> syncAcademiciansToFirebase(
    List<Academician> academicians, {
    void Function(int done, int total)? onProgress,
  }) async {
    const defaultPassword = 'Akademisyen2026';
    int done = 0;

    for (final hoca in academicians) {
      final result = await createAcademicianWithAuth(
        email: hoca.email,
        password: defaultPassword,
        adSoyad: hoca.adSoyad,
        unvan: hoca.unvan,
        verilenDersler: hoca.verilenDersler,
      );

      if (!result.success) {
        // EMAIL_EXISTS → hesap zaten var, DB'yi güncelle
        if (result.message.contains('kayıtlı') || result.message.contains('EXISTS')) {
          // mevcut kullanıcıyı bul ve DB'sini güncelle (şifre değiştirilmez)
          // sessizce devam et
        }
        // diğer hatalar → yoksay, devam et
      }

      done++;
      onProgress?.call(done, academicians.length);
    }

    return done;
  }

  /// MANUEL GÜNCELLEME (sadece DB - mevcut UID/safeId üzerinden).
  /// Yeni eklemeler için createAcademicianWithAuth() kullanın.
  Future<void> saveOrUpdateAcademician(Academician academician) async {
    final id = academician.id ?? _generateSafeId(academician.adSoyad);
    await _dbRef.child('academic_users/$id').update({
      'ad_soyad': academician.adSoyad,
      'unvan': academician.unvan,
      'email': academician.email,
      'verilen_dersler': academician.verilenDersler,
    });
  }

  /// İdari panelden yeni akademisyen ekleme. REST API üzerinden Auth
  /// hesabı oluşturur VE academic_users/{uid} altına kaydeder.
  /// İdari kullanıcının mevcut oturumu KORUNUR (REST'te otomatik
  /// switch yok), bu yüzden tekrar giriş yapmaya gerek kalmaz.
  Future<AcademicianCreateResult> createAcademicianWithAuth({
    required String email,
    required String password,
    required String adSoyad,
    required String unvan,
    List<dynamic> verilenDersler = const [],
    bool isIdari = false,
  }) async {
    if (email.trim().isEmpty || !email.contains('@')) {
      return AcademicianCreateResult.fail("Geçerli bir email girin");
    }
    if (password.length < 6) {
      return AcademicianCreateResult.fail("Şifre en az 6 karakter olmalı");
    }
    if (adSoyad.trim().isEmpty) {
      return AcademicianCreateResult.fail("Ad Soyad boş olamaz");
    }

    final cleanEmail = email.trim().toLowerCase();
    final cleanAd = adSoyad.trim();
    final mevcutIdari = RestAuthService.instance.currentUid;

    try {
      // Sessiz signUp - mevcut oturum (idari) değişmez
      final result = await RestAuthService.instance
          .createUserSilently(cleanEmail, password);
      if (!result.success || result.uid == null) {
        return AcademicianCreateResult.fail(result.message);
      }
      final uid = result.uid!;

      final roller = <String, bool>{'akademisyen': true};
      if (isIdari) roller['idare'] = true;

      await _dbRef.child('academic_users/$uid').set({
        'ad_soyad': cleanAd,
        'unvan': unvan.trim(),
        'email': cleanEmail,
        'verilen_dersler': verilenDersler,
        'roller': roller,
        'kayit_tarihi': ServerValue.timestamp,
        'olusturan_uid': mevcutIdari,
      });

      return AcademicianCreateResult.ok(uid);
    } catch (e) {
      return AcademicianCreateResult.fail("Hata: $e");
    }
  }

  /// Akademisyeni siler (hem Auth hem DB). NOT: Auth silme idari oturum
  /// üzerinden yapılamaz, sadece DB kaydı silinir. Auth hesabını manuel
  /// olarak Firebase Console'dan silmek gerekir (veya Admin SDK ile).
  Future<void> deleteAcademician(String uid) async {
    await _dbRef.child('academic_users/$uid').remove();
  }

  /// EXCEL DOSYASINI SEÇER VE PARSE EDER
  Future<List<Academician>> fetchAcademiciansFromExcel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result == null || result.files.single.path == null) return [];

    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();
    return await compute(_parseAcademicianExcel, bytes);
  }

  /// Türkçe karakterleri ASCII karşılıklarıyla değiştirir (email için)
  static String _turkceTemizle(String s) {
    const tr = ['ç','ğ','ı','İ','ö','ş','ü','Ç','Ğ','I','Ö','Ş','Ü'];
    const en = ['c','g','i','i','o','s','u','c','g','i','o','s','u'];
    var result = s;
    for (var i = 0; i < tr.length; i++) {
      result = result.replaceAll(tr[i], en[i]);
    }
    return result;
  }

  static List<Academician> _parseAcademicianExcel(Uint8List bytes) {
    var excel = Excel.decodeBytes(bytes);
    Map<String, Academician> hocaMap = {};

    for (var table in excel.tables.keys) {
      var sheet = excel.tables[table]!;
      for (var i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        if (row == null || row.length < 14) continue;

        // Ders programındaki "Prof.Dr. H. Gökmeşe" formatıyla eşleşmesi için unvanı ayırmıyoruz
        String unvan = row[12]?.value?.toString() ?? "";
        String tamAd = row[13]?.value?.toString()?.trim() ?? "";

        if (tamAd.isEmpty) continue;

        // E-posta için unvanları temizle + Türkçe karakterleri normalize et
        String temizEmailIsim = tamAd
            .replaceAll(RegExp(r'Prof\.?|Dr\.?|Doç\.?|öğr\.?|gör\.?', caseSensitive: false), "")
            .trim();
        String emailKismi = _turkceTemizle(temizEmailIsim)
            .replaceAll(" ", "")
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), ""); // sadece harf ve rakam
        String dersAdi = row[9]?.value?.toString() ?? "";

        if (hocaMap.containsKey(tamAd)) {
          var mevcutHoca = hocaMap[tamAd]!;
          bool dersVarMi = mevcutHoca.verilenDersler.any((d) => (d is Map ? d['ad'] : d) == dersAdi);
          if (!dersVarMi) {
            mevcutHoca.verilenDersler.add({"ad": dersAdi, "gun": "-", "saat": "-"});
          }
        } else {
          hocaMap[tamAd] = Academician(
            adSoyad: tamAd,
            unvan: unvan,
            email: "$emailKismi@erbakan.edu.tr",
            verilenDersler: [{"ad": dersAdi, "gun": "-", "saat": "-"}],
          );
        }
      }
    }
    return hocaMap.values.toList();
  }
}