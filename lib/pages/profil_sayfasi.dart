import 'package:flutter/material.dart';

class ProfilSayfasi extends StatelessWidget {
  const ProfilSayfasi({super.key});

  final Color neuColor = const Color(0xFF005A71);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      // Üst AppBar'ı kaldırdık çünkü ogrenci_panel'de zaten var
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfilHeader(),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  _buildNotBilgileri(),
                  const SizedBox(height: 20),
                  _buildDanismanKarti(),
                  const SizedBox(height: 25),
                  _buildBelgeIndirmeBolumu(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: neuColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 55,
            backgroundColor: Colors.white,
            child: CircleAvatar(
              radius: 52,
              backgroundColor: neuColor,
              // HATA ALMAMAK İÇİN İKON KOYDUK:
              child: const Icon(Icons.person, size: 60, color: Colors.white),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            "Ahmet Yılmaz",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            "211213001 | Bilgisayar Mühendisliği",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // Diğer kısımlar (NotBilgileri, DanismanKarti vb.) aynı kalabilir...
  Widget _buildNotBilgileri() {
    return Row(
      children: [
        _notKutusu("GANO", "3.42", Colors.orange),
        const SizedBox(width: 15),
        _notKutusu("AGNO", "3.65", Colors.green),
      ],
    );
  }

  Widget _notKutusu(String baslik, String deger, Color renk) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Column(
          children: [
            Text(
              baslik,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              deger,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: renk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDanismanKarti() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Icon(Icons.school_outlined, color: neuColor, size: 35),
        title: const Text(
          "Akademik Danışman",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          "Prof. Dr. Necmettin Erbakan",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: neuColor,
          ),
        ),
      ),
    );
  }

  Widget _buildBelgeIndirmeBolumu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Belgeler ve Linkler",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 10),
        _belgeButonu(
          "Öğrenci Belgesi İndir (E-Devlet)",
          Icons.file_present_rounded,
        ),
        const SizedBox(height: 10),
        _belgeButonu("Transkript İndir", Icons.analytics_outlined),
      ],
    );
  }

  Widget _belgeButonu(String metin, IconData icon) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 20, color: neuColor),
      label: Text(metin, style: const TextStyle(color: Colors.black87)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
