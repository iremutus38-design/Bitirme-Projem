//idare_panel.dart

import 'package:bitirme_projesi/idari_panel/akademisyen_yonetim.dart';
import 'package:bitirme_projesi/idari_panel/sinav_yonetim_sayfasi.dart';
import 'package:bitirme_projesi/idari_panel/tum_ogrenciler_listesi.dart';
import 'package:bitirme_projesi/idari_panel/yuz_kart_yonetimi.dart';
import 'package:bitirme_projesi/services/rest_auth_service.dart';
import 'package:bitirme_projesi/services/sinav_service.dart';
import 'package:bitirme_projesi/services/student_api_service.dart';
import 'package:flutter/material.dart';
import '../auth_page.dart';
import 'idari_ayarlar_sayfasi.dart';

class IdarePanel extends StatefulWidget {
  const IdarePanel({super.key});

  @override
  State<IdarePanel> createState() => _IdarePanelState();
}

class _IdarePanelState extends State<IdarePanel> {
  final Color neuColor = const Color(0xFF005A71);

  // ------------------------------------------------------------------ Çıkış
  void _cikisYap() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Çıkış Yap"),
        content: const Text("Sistemden çıkış yapmak istediğinize emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await RestAuthService.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthPage()),
                  (_) => false,
                );
              }
            },
            child: const Text("Çıkış Yap", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("İdari Yönetim Paneli",
            style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: neuColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _ayarlaraGit, tooltip: "Ayarlar"),
          IconButton(icon: const Icon(Icons.logout), onPressed: _cikisYap, tooltip: "Çıkış"),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Veri Yönetimi ----
            const Text("Veri Yönetimi",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            _buildYonetimKarti(
              "Öğrenci Veritabanını Senkronize Et",
              "Öğrenci listesi Excel'ini (.xlsx) yükle — öğrenciler ve aldıkları dersler sisteme aktarılır.",
              Icons.sync_alt,
              Colors.orangeAccent,
              _senkronizasyonBaslat,
            ),

            const SizedBox(height: 15),

            _buildYonetimKarti(
              "Sınav Tarihlerini Ekle",
              "Sınav tarihli Excel'i (.xlsx) yükle — her ders için hoca ve öğrenci listesiyle sınav takvimi oluşturulur.",
              Icons.event_available,
              Colors.blue,
              _sinavTarihiYukle,
            ),

            const SizedBox(height: 25),

            // ---- Yönetim İşlemleri ----
            const Text("Yönetim İşlemleri",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            _buildYonetimKarti(
              "Öğrenci Veritabanı (1-4. Sınıf)",
              "Senkronize edilmiş öğrencileri görüntüle.",
              Icons.people_alt,
              Colors.green,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TumOgrencilerSayfasi())),
            ),

            const SizedBox(height: 15),

            _buildYonetimKarti(
              "Akademisyen Bilgilerini Yönet",
              "Kayıtlı akademisyenleri görüntüle ve ders ata.",
              Icons.school,
              Colors.purple,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AkademisyenYonetimSayfasi())),
            ),

            const SizedBox(height: 15),

            _buildYonetimKarti(
              "Yüz & Kart Yönetimi",
              "Öğrencilerin yüz verisini ve RFID kartını tanıt.",
              Icons.face_retouching_natural,
              Colors.teal,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const YuzKartYonetimiSayfasi())),
            ),

            const SizedBox(height: 15),

            _buildYonetimKarti(
              "Sınav Sistemini Yönet",
              "Sınav takvimini görüntüle, derslik ekle, oturma planı oluştur.",
              Icons.assignment_turned_in,
              Colors.blue,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SinavYonetimSayfasi())),
            ),

            const SizedBox(height: 15),

            _buildYonetimKarti(
              "Duyuruları Yönet",
              "Sistem geneline veya bölüme özel duyuru ekle.",
              Icons.campaign,
              Colors.orange,
              () {},
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ Öğrenci senkronizasyonu
  void _senkronizasyonBaslat() async {
    final progressNotifier = ValueNotifier<int>(0);
    final statusNotifier   = ValueNotifier<String>("Hazırlanıyor...");
    final isFinished       = ValueNotifier<bool>(false);
    int totalToUpload = 0;

    _ilerlemeDialogu(progressNotifier, statusNotifier, isFinished, () => totalToUpload);

    try {
      statusNotifier.value = "Excel dosyası okunuyor...";
      final students = await StudentApiService().fetchStudentsFromExcel();
      if (students.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }
      totalToUpload = students.length;
      statusNotifier.value = "Firebase'e aktarılıyor...";
      await StudentApiService().syncStudentsToFirebase(
        students,
        onProgress: (c) => progressNotifier.value = c,
      );
      statusNotifier.value = "Senkronizasyon Tamamlandı!";
      isFinished.value = true;
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
    }
  }

  // ------------------------------------------------------------------ Sınav takvimi yükleme
  void _sinavTarihiYukle() async {
    final progressNotifier = ValueNotifier<int>(0);
    final statusNotifier   = ValueNotifier<String>("Hazırlanıyor...");
    final isFinished       = ValueNotifier<bool>(false);
    int totalDers = 0;

    _ilerlemeDialogu(progressNotifier, statusNotifier, isFinished, () => totalDers);

    try {
      statusNotifier.value = "Excel dosyası seçiliyor...";
      final done = await SinavService().yukleVeKaydet(
        onProgress: (d, t) {
          totalDers = t;
          progressNotifier.value = d;
          statusNotifier.value = "Firebase'e yazılıyor...";
        },
      );
      if (done == 0) {
        if (mounted) Navigator.pop(context);
        return;
      }
      statusNotifier.value = "$done ders için sınav takvimi oluşturuldu!";
      isFinished.value = true;
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
    }
  }

  // ------------------------------------------------------------------ Ortak ilerleme dialogu
  void _ilerlemeDialogu(
    ValueNotifier<int> progress,
    ValueNotifier<String> status,
    ValueNotifier<bool> finished,
    int Function() getTotal,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ValueListenableBuilder<bool>(
            valueListenable: finished,
            builder: (ctx, done, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                done
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 60)
                    : const CircularProgressIndicator(strokeWidth: 5),
                const SizedBox(height: 20),
                ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (_, s, __) => Text(s,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const SizedBox(height: 8),
                if (!done)
                  ValueListenableBuilder<int>(
                    valueListenable: progress,
                    builder: (_, val, __) {
                      final total = getTotal();
                      return Text(
                        total > 0 ? "$val / $total" : "İşleniyor...",
                        style: TextStyle(color: neuColor, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                if (done)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neuColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Kapat", style: TextStyle(color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ Yardımcılar
  Widget _buildYonetimKarti(
      String baslik, String altBaslik, IconData ikon, Color renk, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5)),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: renk.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
              child: Icon(ikon, color: renk, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(baslik, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(altBaslik, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _ayarlaraGit() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const IdariAyarlar()));
}
