import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';

class ScheduleService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref().child('schedules');

  Future<void> uploadScheduleFromExcel(String donemId) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.single.path == null) return;

      final bytes = File(result.files.single.path!).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);

      Map<String, dynamic> allProgram = {};

      final Map<String, String> gunMap = {
        "pazartesi": "Pazartesi",
        "sali":      "Salı",
        "salı":      "Salı",
        "çarşamba":  "Çarşamba",
        "carsamba":  "Çarşamba",
        "persembe":  "Perşembe",
        "perşembe":  "Perşembe",
        "cuma":      "Cuma",
      };

      for (var table in excel.tables.keys) {
        String gradeKey = _getGradeKey(table);
        Map<String, List<Map<String, String>>> sheetData = {};
        String currentDay = "";

        // Dinamik sütun indexleri
        int? dersIdx, derslikIdx, hocaIdx, saatIdx;

for (var row in excel.tables[table]!.rows) {
  String getVal(int index) {
    if (index >= row.length || row[index] == null) return "";
    return row[index]!.value?.toString().trim() ?? "";
  }

  // ✅ ÖNCE gün adını kontrol et (başlık satırında da olabilir)
  String firstCell = getVal(0).toLowerCase().trim();
  if (gunMap.containsKey(firstCell) && firstCell.length >= 4) {
    currentDay = gunMap[firstCell]!;
    // Gün satırı aynı zamanda başlık satırı — indexleri de güncelle
    for (int i = 0; i < row.length; i++) {
      String val = (row[i]?.value?.toString().trim() ?? "").toLowerCase();
      if (val == "ders")                            dersIdx    = i;
      if (val == "sınıf" || val == "sinif")         derslikIdx = i;
      if (val.contains("eleman") || val == "hoca")  hocaIdx    = i;
      if (val == "saat")                            saatIdx    = i;
    }
    continue; // Bu satırda ders yok, geç
  }

  // Başlık satırı ama gün adı yok (ilk PAZARTESİ satırı gibi)
  bool isHeaderRow = false;
  for (int i = 0; i < row.length; i++) {
    String val = (row[i]?.value?.toString().trim() ?? "").toLowerCase();
    if (val == "ders")                            { dersIdx    = i; isHeaderRow = true; }
    if (val == "sınıf" || val == "sinif")         { derslikIdx = i; isHeaderRow = true; }
    if (val.contains("eleman") || val == "hoca")  { hocaIdx    = i; isHeaderRow = true; }
    if (val == "saat")                            { saatIdx    = i; isHeaderRow = true; }
  }
  if (isHeaderRow) continue;

  // Saat + ders okuma (değişmedi)
  int sIdx = saatIdx ?? 1;
  String timeCell = getVal(sIdx);
  bool isSaatSatiri = timeCell.contains(" - ") &&
                      (timeCell.contains(".") || timeCell.contains(":"));

  if (isSaatSatiri && currentDay.isNotEmpty) {
    String dersAdi = getVal(dersIdx    ?? 2);
    String derslik = getVal(derslikIdx ?? 3);
    String hoca    = getVal(hocaIdx    ?? 4);

    if (dersAdi.isEmpty || dersAdi.toLowerCase() == "ders" || dersAdi.length <= 2) continue;

    if (!sheetData.containsKey(currentDay)) sheetData[currentDay] = [];
    sheetData[currentDay]!.add({
      "ders_adi": dersAdi,
      "saat":     timeCell,
      "derslik":  derslik.isEmpty ? "Belirtilmemiş" : derslik,
      "hoca":     hoca.isEmpty    ? "Bilinmiyor"    : hoca,
    });
  }
}
        if (sheetData.isNotEmpty) {
          allProgram[gradeKey] = sheetData;
        }
      }

      if (allProgram.isNotEmpty) {
        await _dbRef.child(donemId).set({
          "guncelleme_tarihi": DateTime.now().toIso8601String(),
          "program": allProgram,
        });
      }
    } catch (e) {
      print("Excel Yükleme Hatası: $e");
      rethrow;
    }
  }

  String _getGradeKey(String name) {
    String n = name.toLowerCase().trim();
    if (n.contains("table 1") || n.contains("1. sinif") || n.contains("i. sinif")) return "1_sinif";
    if (n.contains("table 2") || n.contains("2. sinif") || n.contains("ii. sinif")) return "2_sinif";
    if (n.contains("table 3") || n.contains("3. sinif") || n.contains("iii. sinif")) return "3_sinif";
    if (n.contains("table 4") || n.contains("4. sinif") || n.contains("iv. sinif")) return "4_sinif";
    return name.replaceAll(" ", "_").toLowerCase();
  }
}