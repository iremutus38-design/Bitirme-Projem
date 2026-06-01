//schedule_model.dart

class ScheduleItem {
  final String saat;
  final String ders;
  final String hoca;
  final String derslik; // PDF'deki "Sınıf" sütunu buraya gelecek (Örn: NM Amfi)

  ScheduleItem({
    required this.saat,
    required this.ders,
    required this.hoca,
    required this.derslik, 
  });

  factory ScheduleItem.fromJson(Map<dynamic, dynamic> json) {
    return ScheduleItem(
      saat: json['saat'] ?? '',
      ders: json['ders'] ?? '',
      hoca: json['hoca'] ?? '',
      derslik: json['derslik'] ?? '', // Anahtar adını derslik yaptık
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'saat': saat,
      'ders': ders,
      'hoca': hoca,
      'derslik': derslik,
    };
  }
}