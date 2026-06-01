import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:flutter/material.dart';

class OgrenciYonetimSayfasi extends StatefulWidget {
  const OgrenciYonetimSayfasi({super.key});

  @override
  State<OgrenciYonetimSayfasi> createState() => _OgrenciYonetimSayfasiState();
}

class _OgrenciYonetimSayfasiState extends State<OgrenciYonetimSayfasi> {
  // Veritabanı referansı: 'users' düğümünü dinliyoruz
  final Query dbRef = FirebaseDatabase.instance.ref().child('users');

  // Görselde belirttiğin derslerin listesi
  final List<Map<String, String>> tumDersler = [
    {"kod": "0370060064", "ad": "Mühendislik Projesi I"},
    {"kod": "0370060065", "ad": "Staj II"},
    {"kod": "0370060068", "ad": "Kablosuz Ağ Teknolojileri"},
    {"kod": "0370060072", "ad": "Görüntü İşleme"},
    {"kod": "0370060076", "ad": "Gömülü ve Gerçek Zamanlı Sistemler"},
    {"kod": "0370060081", "ad": "İşlemsel Zeka"},
  ];

  // Ders atama penceresini açan fonksiyon
  void _dersAtaPenceresi(String studentUid, String studentName) {
    // Seçilen derslerin durumunu tutan geçici map
    Map<String, bool> secilenDersler = {};
    for (var ders in tumDersler) {
      secilenDersler[ders['ad']!] = false;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("$studentName - Ders Atama"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: tumDersler.map((ders) {
                    return CheckboxListTile(
                      activeColor: const Color(0xFF005A71),
                      title: Text(ders['ad']!),
                      subtitle: Text("Kod: ${ders['kod']}"),
                      value: secilenDersler[ders['ad']],
                      onChanged: (val) {
                        // Diyalog içindeki checkbox'ı güncellemek için
                        setDialogState(() {
                          secilenDersler[ders['ad']!] = val!;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("İptal"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005A71),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    // Sadece 'true' (işaretli) olan dersleri bir listeye al
                    List<String> atanacaklar = [];
                    secilenDersler.forEach((key, value) {
                      if (value) atanacaklar.add(key);
                    });

                    // Firebase'de o öğrencinin altına 'alinan_dersler' düğümü aç ve kaydet
                    await FirebaseDatabase.instance
                        .ref()
                        .child('users/$studentUid/alinan_dersler')
                        .set(atanacaklar);

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Dersler başarıyla atandı!"),
                        ),
                      );
                    }
                  },
                  child: const Text("Kaydet"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kayıtlı Öğrenciler"),
        backgroundColor: const Color(0xFF005A71),
        foregroundColor: Colors.white,
      ),
      body: FirebaseAnimatedList(
        query: dbRef,
        itemBuilder: (context, snapshot, animation, index) {
          Map user = snapshot.value as Map;
          user['key'] = snapshot.key;

          // Sadece 'öğrenci' rolüne sahip olanları listele
          if (user['roller'] != null && user['roller']['öğrenci'] == true) {
            return _buildOgrenciKarti(user);
          } else {
            return const SizedBox.shrink(); // Öğrenci değilse gösterme
          }
        },
      ),
    );
  }

  // Her bir öğrenci satırı (Kutu tasarımı)
  Widget _buildOgrenciKarti(Map ogrenci) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
      child: ListTile(
        onTap: () => _dersAtaPenceresi(ogrenci['key'], ogrenci['ad_soyad']),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF005A71),
          child: Text(
            ogrenci['ad_soyad'] != null
                ? ogrenci['ad_soyad'][0].toUpperCase()
                : "?",
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          ogrenci['ad_soyad'] ?? "İsimsiz Öğrenci",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(ogrenci['email'] ?? "E-posta bilgisi yok"),
        trailing: const Icon(Icons.add_task, color: Colors.green),
      ),
    );
  }
}
