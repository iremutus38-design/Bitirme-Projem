//models/student_model.dart

class Student {
  final String id;
  final String adSoyad;
  final String email;
  final String bolum;
  final String tcNo;
  final int sinif; // 1, 2, 3 veya 4
  final List<Course> alinanDersler; // Yeni eklenen alan

  Student({
    required this.id,
    required this.adSoyad,
    required this.email,
    required this.bolum,
    required this.tcNo,
    required this.sinif,
    required this.alinanDersler, // Constructor'a eklendi
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    // API'den gelen 'alinan_dersler' listesini güvenli bir şekilde Course nesnelerine çeviriyoruz
    var derslerListesi = json['alinan_dersler'] as List? ?? [];
    List<Course> dersNesneleri = derslerListesi
        .map((dersJson) => Course.fromJson(dersJson))
        .toList();

    return Student(
      id: json['id'].toString(),
      adSoyad: json['ad_soyad'] ?? '',
      email: json['email'] ?? '',
      bolum: json['bolum'] ?? '',
      tcNo: json['tc_no'] ?? '',
      sinif: json['sinif'] ?? 1,
      alinanDersler: dersNesneleri, // Factory'ye eklendi
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ad_soyad': adSoyad,
      'email': email,
      'bolum': bolum,
      'tc_no': tcNo,
      'sinif': sinif,
      // Firebase veya API'ye gönderirken listeyi tekrar JSON formatına çeviriyoruz
      'alinan_dersler': alinanDersler.map((d) => d.toJson()).toList(),
    };
  }
}

// Ders verilerini yönetmek için yardımcı alt sınıf
class Course {
  final String dersAdi;
  final String hoca;
  final int kredi;

  Course({
    required this.dersAdi,
    required this.hoca,
    required this.kredi,
  });

  factory Course.fromJson(Map<dynamic, dynamic> json) {
    return Course(
      dersAdi: json['ders_adi'] ?? '',
      hoca: json['hoca'] ?? '',
      kredi: json['kredi'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'ders_adi': dersAdi,
    'hoca': hoca,
    'kredi': kredi,
  };
}