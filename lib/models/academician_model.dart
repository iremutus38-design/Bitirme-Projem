class Academician {
  String? id;
  String adSoyad;
  String unvan;
  String email;
  List<dynamic> verilenDersler; 

  Academician({
    this.id,
    required this.adSoyad,
    required this.unvan,
    required this.email,
    required this.verilenDersler,
  });

  factory Academician.fromJson(Map<String, dynamic> json, String id) {
    return Academician(
      id: id,
      adSoyad: json['ad_soyad'] ?? '',
      unvan: json['unvan'] ?? '',
      email: json['email'] ?? '',
      verilenDersler: json['verilen_dersler'] ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ad_soyad': adSoyad,
      'unvan': unvan,
      'email': email,
      'verilen_dersler': verilenDersler,
      'roller': {'akademisyen': true},
    };
  }
}