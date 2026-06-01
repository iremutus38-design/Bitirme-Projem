// sinav_service.dart
//
// Tarihli sınav Excel dosyasını okur ve Firebase'e şu yapıyla yazar:
//
// sinav_takvimi/
//   {ders_kodu}/
//     ders_adi: "FİZİK II"
//     hoca_adi: "Dr. Öğr. Üyesi HÜSNÜ KARA"
//     tarih: "02.04.2026"
//     saat: "10:00"
//     program: "MAKİNE MÜHENDİSLİĞİ"
//     ogrenciler/
//       {okul_no}/
//         ad_soyad: "ALİ VELİ"
//         sinif: 1
//
// Excel kolon sırası (tarihli format):
//   0:SIRANO  1:Fakülte  2:Program  3:Sınıf  4:TC  5:OgrNo
//   6:Adı     7:Soyadı   8:DH_Kodu  9:DH_Adı 10:Geçme 11:Dönem
//   12:Unvan  13:Hoca    14:SNV_Tarihi  15:SNV_Saati

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class SinavService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  /// Dosya seçtirir, parse eder, Firebase'e yazar.
  /// [onProgress] → kaç ders işlendi bildirir.
  Future<int> yukleVeKaydet({Function(int done, int total)? onProgress}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: false,
    );
    if (result == null || result.files.single.path == null) return 0;

    final bytes = await File(result.files.single.path!).readAsBytes();
    final sinav = await compute(_parseExcel, bytes);
    if (sinav.isEmpty) return 0;

    final keys = sinav.keys.toList();
    int done = 0;

    for (int i = 0; i < keys.length; i += 10) {
      final end = (i + 10 < keys.length) ? i + 10 : keys.length;
      final Map<String, dynamic> updates = {};

      for (int j = i; j < end; j++) {
        final kod = keys[j];
        final data = sinav[kod]!;

        // Üst düzey ders bilgisi
        updates['sinav_takvimi/$kod/ders_adi'] = data['ders_adi'];
        updates['sinav_takvimi/$kod/hoca_adi'] = data['hoca_adi'];
        updates['sinav_takvimi/$kod/tarih']    = data['tarih'];
        updates['sinav_takvimi/$kod/saat']     = data['saat'];
        updates['sinav_takvimi/$kod/program']  = data['program'];

        // Öğrenciler alt düğümü
        final ogrenciler = data['ogrenciler'] as Map<String, dynamic>;
        ogrenciler.forEach((ogrNo, ogrData) {
          updates['sinav_takvimi/$kod/ogrenciler/$ogrNo'] = ogrData;
        });

        done++;
        onProgress?.call(done, keys.length);
      }

      await _dbRef.update(updates);
    }
    return done;
  }
}

// --- Background parser (compute ile ayrı isolate'ta çalışır) ---

Map<String, Map<String, dynamic>> _parseExcel(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  // ders_kodu → {ders_adi, hoca_adi, tarih, saat, program, ogrenciler: {}}
  final Map<String, Map<String, dynamic>> sinav = {};

  for (final table in excel.tables.keys) {
    final sheet = excel.tables[table]!;
    for (int i = 1; i < sheet.maxRows; i++) {
      final row = sheet.rows[i];
      if (row == null || row.length < 16) continue;

      String temizle(dynamic v) {
        if (v == null) return '';
        final s = v.toString().trim();
        return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
      }

      final ogrNo   = temizle(row[5]?.value);
      final tc      = temizle(row[4]?.value);
      final dersKod = temizle(row[8]?.value);
      if (ogrNo.isEmpty || dersKod.isEmpty) continue;

      final dersAdi = row[9]?.value?.toString().trim() ?? '';
      final hocat   = row[13]?.value?.toString().trim() ?? '';
      final tarih   = row[14]?.value?.toString().trim() ?? '';
      final saat    = row[15]?.value?.toString().trim() ?? '';
      final program = row[2]?.value?.toString().trim() ?? '';
      final ad      = row[6]?.value?.toString().trim() ?? '';
      final soyad   = row[7]?.value?.toString().trim() ?? '';
      final sinif   = int.tryParse(row[3]?.value?.toString() ?? '1') ?? 1;

      // Firebase anahtarlarında . / [ ] # $ kullanılamaz → kodu temizle
      final kodKey = dersKod.replaceAll(RegExp(r'[.#$\[\]/]'), '_');

      sinav.putIfAbsent(kodKey, () => {
        'ders_adi': dersAdi,
        'hoca_adi': hocat,
        'tarih': tarih,
        'saat': saat,
        'program': program,
        'ogrenciler': <String, dynamic>{},
      });

      (sinav[kodKey]!['ogrenciler'] as Map<String, dynamic>)[ogrNo] = {
        'ad_soyad': '$ad $soyad'.trim().toUpperCase(),
        'tc_no': tc,
        'sinif': sinif,
      };

      // Hoca / tarih / saat → son okunan satırdan üzerine yaz (tutarlı olmalı)
      sinav[kodKey]!['hoca_adi'] = hocat;
      sinav[kodKey]!['tarih']    = tarih;
      sinav[kodKey]!['saat']     = saat;
    }
  }
  return sinav;
}
