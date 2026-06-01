//student_api_service.dart

import 'dart:async';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart'; // compute için gerekli
import '../models/student_model.dart';

class StudentApiService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  /// EXCEL'DEN VERİ SEÇER VE LİSTE OLARAK DÖNDÜRÜR
  Future<List<Student>> fetchStudentsFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: false, 
      );

      if (result == null || result.files.single.path == null) return [];

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes(); 

      return await compute(_parseExcelInBackground, bytes);
      
    } catch (e) {
      print("Excel Okuma Hatası: $e");
      return [];
    }
  }

// Tarihsiz Excel formatı (Dosya 2) kolon sırası:
//   0:SIRANO  1:Fakülte  2:Program  3:OgrNo  4:TC
//   5:Adı     6:Soyadı   7:DH_Kodu  8:DH_Adı 9:Sınıf  10:Hoca
static List<Student> _parseExcelInBackground(Uint8List bytes) {
  var excel = Excel.decodeBytes(bytes);
  Map<String, Student> studentMap = {};

  for (var table in excel.tables.keys) {
    var sheet = excel.tables[table]!;

    for (var i = 1; i < sheet.maxRows; i++) {
      var row = sheet.rows[i];
      if (row == null || row.isEmpty || row.length < 9) continue;

      String temizle(dynamic value) {
        if (value == null) return "";
        String s = value.toString().trim();
        return s.endsWith(".0") ? s.substring(0, s.length - 2) : s;
      }

      final ogrenciNo = temizle(row[3]?.value);
      final tcNo      = temizle(row[4]?.value);
      if (ogrenciNo.isEmpty || tcNo.isEmpty) continue;

      final dersKod = temizle(row[7]?.value);
      final dersAdi = row[8]?.value?.toString().trim() ?? "Bilinmeyen Ders";
      final hoca    = row.length > 10 ? row[10]?.value?.toString().trim() ?? "Belirtilmedi" : "Belirtilmedi";

      final Course yeniDers = Course(
        dersAdi: dersAdi,
        hoca: hoca,
        kredi: 2,
      );

      if (studentMap.containsKey(tcNo)) {
        final bool dersVar = studentMap[tcNo]!.alinanDersler.any((d) => d.dersAdi == dersAdi);
        if (!dersVar) studentMap[tcNo]!.alinanDersler.add(yeniDers);
      } else {
        final ad    = row[5]?.value?.toString().trim() ?? "";
        final soyad = row[6]?.value?.toString().trim() ?? "";
        final sinif = int.tryParse(row[9]?.value?.toString() ?? "1") ?? 1;

        studentMap[tcNo] = Student(
          id: ogrenciNo,
          adSoyad: "$ad $soyad".toUpperCase(),
          email: "$ogrenciNo@ogr.erbakan.edu.tr",
          bolum: row[2]?.value?.toString().trim() ?? "Bölüm Yok",
          tcNo: tcNo,
          sinif: sinif,
          alinanDersler: [yeniDers],
        );
      }
    }
  }

  return studentMap.values.toList();
}
Future<void> syncStudentsToFirebase(List<Student> students, {Function(int)? onProgress}) async {
  if (students.isEmpty) return;
  try {
    int count = 0;
    for (var i = 0; i < students.length; i += 100) {
      int end = (i + 100 < students.length) ? i + 100 : students.length;
      Map<String, dynamic> updates = {};
      
      for (var j = i; j < end; j++) {
        var student = students[j];
        // TC No'yu anahtar yapıyoruz ki kayıt anında kolayca bulalım
        updates['on_kayitlar/${student.tcNo}'] = {
          'ad_soyad': student.adSoyad,
          'okul_no': student.id, // Excel'deki öğrenci no
          'tc_no': student.tcNo,
          'bolum': student.bolum,
          'sinif': student.sinif,
          'email': student.email,
          // Dersleri liste olarak ekliyoruz
          'alinan_dersler': student.alinanDersler.map((d) => {
            'ders_adi': d.dersAdi,
            'hoca_adi': d.hoca,
          }).toList(),
          'kayit_durumu': 'beklemede',
        };
      }
      await _dbRef.update(updates);
      count = end;
      if (onProgress != null) onProgress(count); 
    }
  } catch (e) {
    print("Firebase Güncelleme Hatası: $e");
    rethrow;
  }
}

Future<List<Student>> fetchAllStudentsFromFirebase() async {
    try {
      final snapshot = await _dbRef.child('on_kayitlar').get();
      if (!snapshot.exists) return [];

      List<Student> students = [];
      Map<dynamic, dynamic> data = snapshot.value as Map;
      data.forEach((key, value) {
        students.add(Student.fromJson(Map<String, dynamic>.from(value)));
      });
      return students;
    } catch (e) {
      print("Firebase Veri Çekme Hatası: $e");
      return [];
    }
  }
}