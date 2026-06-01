import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../models/academician_model.dart';
import '../services/academician_service.dart';

class AkademisyenYonetimSayfasi extends StatefulWidget {
  const AkademisyenYonetimSayfasi({super.key});

  @override
  State<AkademisyenYonetimSayfasi> createState() =>
      _AkademisyenYonetimSayfasiState();
}

class _AkademisyenYonetimSayfasiState
    extends State<AkademisyenYonetimSayfasi> {
  final AcademicianService _service = AcademicianService();
  static const Color neuColor = Color(0xFF005A71);
  final List<String> gunler = [
    "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma"
  ];

  List<Map<String, dynamic>> _aktifler   = [];
  List<Map<String, dynamic>> _onKayitlar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _veriCek();
  }

  Future<void> _veriCek() async {
    setState(() => _yukleniyor = true);
    try {
      final aktifSnap =
          await FirebaseDatabase.instance.ref().child('academic_users').get();
      final onSnap =
          await FirebaseDatabase.instance.ref().child('on_kayit_academic').get();

      final aktifler = <Map<String, dynamic>>[];
      if (aktifSnap.exists && aktifSnap.value is Map) {
        (aktifSnap.value as Map).forEach((uid, val) {
          if (val is Map) {
            final data = Map<String, dynamic>.from(val);
            if (data['roller']?['akademisyen'] == true) {
              aktifler.add({...data, '_uid': uid.toString()});
            }
          }
        });
      }

      final onKayitlar = <Map<String, dynamic>>[];
      if (onSnap.exists && onSnap.value is Map) {
        (onSnap.value as Map).forEach((key, val) {
          if (val is Map) {
            onKayitlar.add({
              ...Map<String, dynamic>.from(val),
              '_key': key.toString(),
            });
          }
        });
      }

      if (mounted) {
        setState(() {
          _aktifler   = aktifler;
          _onKayitlar = onKayitlar;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // -------------------------------------------------- Excel yükleme
  void _exceldenYukle() async {
    final statusNotifier = ValueNotifier<String>("Hazırlanıyor...");
    final isFinished = ValueNotifier<bool>(false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ValueListenableBuilder<bool>(
            valueListenable: isFinished,
            builder: (ctx, done, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                done
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 60)
                    : const CircularProgressIndicator(strokeWidth: 5, color: neuColor),
                const SizedBox(height: 20),
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (_, s, __) => Text(s,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (done)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: neuColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _veriCek();
                      },
                      child: const Text("Kapat", style: TextStyle(color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      statusNotifier.value = "Excel okunuyor...";
      final hocalar = await _service.fetchAcademiciansFromExcel();
      if (hocalar.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }
      statusNotifier.value = "Hesaplar oluşturuluyor... (0/${hocalar.length})";
      await _service.syncAcademiciansToFirebase(
        hocalar,
        onProgress: (done, total) =>
            statusNotifier.value = "Hesaplar oluşturuluyor... ($done/$total)",
      );
      statusNotifier.value = "${hocalar.length} akademisyen hesabı oluşturuldu!\nVarsayılan şifre: Akademisyen2026";
      isFinished.value = true;
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
    }
  }

  // -------------------------------------------------- Hesap oluştur (ön kayıt → aktif)
  void _hesapOlustur(Map<String, dynamic> onKayit) {
    final passwordCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text("Hesap Oluştur"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${onKayit['unvan'] ?? ''} ${onKayit['ad_soyad'] ?? ''}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(onKayit['email'] ?? '',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Geçici Şifre (en az 6 karakter)",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text("İptal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: neuColor),
              onPressed: saving
                  ? null
                  : () async {
                      if (passwordCtrl.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text("Şifre en az 6 karakter olmalı")));
                        return;
                      }
                      setS(() => saving = true);
                      final result = await _service.createAcademicianWithAuth(
                        email:    onKayit['email'] ?? '',
                        password: passwordCtrl.text,
                        adSoyad:  onKayit['ad_soyad'] ?? '',
                        unvan:    onKayit['unvan'] ?? '',
                        verilenDersler: List.from(onKayit['verilen_dersler'] ?? []),
                      );
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      if (result.success) {
                        await FirebaseDatabase.instance
                            .ref()
                            .child('on_kayit_academic/${onKayit['_key']}')
                            .remove();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text("Hesap oluşturuldu!"),
                            backgroundColor: Colors.green));
                        _veriCek();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(result.message),
                            backgroundColor: Colors.red));
                      }
                    },
              child: const Text("Oluştur", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------- Manuel form
  void _akademisyenFormu({Academician? mevcutHoca}) {
    final isYeni       = mevcutHoca == null;
    final nameCtrl     = TextEditingController(text: mevcutHoca?.adSoyad);
    final unvanCtrl    = TextEditingController(text: mevcutHoca?.unvan);
    final emailCtrl    = TextEditingController(text: mevcutHoca?.email);
    final passwordCtrl = TextEditingController();
    bool isIdari  = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isYeni ? "Yeni Akademisyen" : "Bilgileri Düzenle"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isYeni)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 18),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Akademisyen email + şifresiyle giriş yapabilir.",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(controller: unvanCtrl,
                    decoration: const InputDecoration(labelText: "Ünvan")),
                const SizedBox(height: 8),
                TextField(controller: nameCtrl,
                    decoration: const InputDecoration(labelText: "Ad Soyad")),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  enabled: isYeni,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "E-posta"),
                ),
                if (isYeni) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: "Geçici Şifre (en az 6 karakter)"),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("İdari yetkisi de versin",
                        style: TextStyle(fontSize: 13)),
                    value: isIdari,
                    onChanged: (v) => setS(() => isIdari = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text("İptal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: neuColor),
              onPressed: isSaving
                  ? null
                  : () async {
                      setS(() => isSaving = true);
                      if (isYeni) {
                        final result = await _service.createAcademicianWithAuth(
                          email: emailCtrl.text, password: passwordCtrl.text,
                          adSoyad: nameCtrl.text, unvan: unvanCtrl.text,
                          isIdari: isIdari,
                        );
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(result.success
                              ? "Akademisyen oluşturuldu!"
                              : result.message),
                          backgroundColor: result.success ? Colors.green : Colors.red,
                        ));
                        if (result.success) _veriCek();
                      } else {
                        await _service.saveOrUpdateAcademician(Academician(
                          id: mevcutHoca!.id,
                          adSoyad: nameCtrl.text,
                          unvan: unvanCtrl.text,
                          email: emailCtrl.text,
                          verilenDersler: mevcutHoca.verilenDersler,
                        ));
                        if (mounted) { Navigator.pop(ctx); _veriCek(); }
                      }
                    },
              child: Text(isYeni ? "Oluştur" : "Kaydet",
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------- Ders atama (3 yol)
  void _hocaDersAtaPenceresi(String uid, String name) {
    List<Map<String, String>> liste = [];  // ders_programi kayıtları
    bool yuklendi = false;
    int sekme = 0; // 0=Mevcut dersler, 1=Ders programından, 2=Manuel

    // Sekme 0 & 2 ortak state
    String? seciliDersAdi;          // sekme 0: seçili ders
    List<String> mevcutDersAdlari = [];  // sekme 0: verilen_dersler isimleri
    bool mevcutYuklendi = false;

    // Sekme 1: ders programı (schedules) state
    List<Map<String, String>> programDersler = [];
    bool programYuklendi = false;
    Set<int> programSecili = {};

    // Ortak gün/saat
    final dersAdiCtrl = TextEditingController();
    TimeOfDay bas = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay bit = const TimeOfDay(hour: 11, minute: 0);
    String gun = "Pazartesi";
    int? duzIdx;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        // Mevcut ders_programi'ni yükle (bir kez)
        if (!yuklendi) {
          yuklendi = true;
          FirebaseDatabase.instance.ref('academic_users/$uid/ders_programi').get().then((s) {
            if (!s.exists) return;
            final raw = s.value;
            final items = <Map<String, String>>[];
            void parse(dynamic r) {
              if (r is List) { for (final e in r) { if (e is Map) items.add(Map<String, String>.from(e.map((k,v)=>MapEntry(k.toString(),v.toString())))); } }
              else if (r is Map) { for (final e in r.values) { if (e is Map) items.add(Map<String, String>.from(e.map((k,v)=>MapEntry(k.toString(),v.toString())))); } }
            }
            parse(raw);
            setS(() => liste = items);
          });
        }

        // Sekme 0: verilen_dersler isimlerini yükle
        if (sekme == 0 && !mevcutYuklendi) {
          mevcutYuklendi = true;
          FirebaseDatabase.instance.ref('academic_users/$uid/verilen_dersler').get().then((s) {
            if (!s.exists) return;
            final raw = s.value;
            final adlar = <String>[];
            void parse(dynamic r) {
              void addItem(dynamic e) {
                if (e is String && e.isNotEmpty) { adlar.add(e); }
                else if (e is Map) { final ad = e['ad']?.toString() ?? e['ders_adi']?.toString() ?? ''; if (ad.isNotEmpty) adlar.add(ad); }
              }
              if (r is List) { for (final e in r) addItem(e); }
              else if (r is Map) { for (final e in r.values) addItem(e); }
            }
            parse(raw);
            setS(() => mevcutDersAdlari = adlar);
          });
        }

        // Sekme 1: ders programından bu hocaya ait dersleri çek
        if (sekme == 1 && !programYuklendi) {
          programYuklendi = true;
          FirebaseDatabase.instance.ref('schedules/2025_2026_bahar/program').get().then((s) {
            if (!s.exists || s.value is! Map) return;
            final program = s.value as Map;
            final hocaninKelimeler = name.toLowerCase().replaceAll('.', ' ').split(' ').where((k) => k.length > 2).toSet();
            final sonuclar = <Map<String, String>>[];
            program.forEach((sinif, gunMap) {
              if (gunMap is! Map) return;
              gunMap.forEach((g, dersListesi) {
                List items = [];
                if (dersListesi is List) items = dersListesi;
                else if (dersListesi is Map) items = dersListesi.values.toList();
                for (final d in items) {
                  if (d is! Map) continue;
                  final hoca = (d['hoca']?.toString() ?? '').toLowerCase().replaceAll('.', ' ');
                  final hocaKelimeler = hoca.split(' ').where((k) => k.length > 2).toSet();
                  if (hocaninKelimeler.intersection(hocaKelimeler).isNotEmpty) {
                    final key = '${d['ders_adi']}_$g';
                    if (!sonuclar.any((x) => '${x['ad']}_${x['gun']}' == key)) {
                      sonuclar.add({
                        'ad': d['ders_adi']?.toString() ?? '',
                        'gun': g.toString(),
                        'saat': d['saat']?.toString() ?? '',
                        'derslik': d['derslik']?.toString() ?? '',
                      });
                    }
                  }
                }
              });
            });
            setS(() => programDersler = sonuclar);
          });
        }

        // gun her zaman geçerli bir değer olmalı
        if (!gunler.contains(gun)) gun = gunler.first;

        return Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          height: MediaQuery.of(ctx).size.height * 0.90,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 12),
            Text("$name — Ders Programı", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: neuColor)),
            const SizedBox(height: 10),

            // ── 3 sekme ──
            Row(children: [
              _SekmeBtn(label: "Derslerimden", aktif: sekme == 0, onTap: () => setS(() => sekme = 0)),
              const SizedBox(width: 6),
              _SekmeBtn(label: "Programdan", aktif: sekme == 1, onTap: () => setS(() => sekme = 1)),
              const SizedBox(width: 6),
              _SekmeBtn(label: "Manuel", aktif: sekme == 2, onTap: () => setS(() => sekme = 2)),
            ]),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),

            Expanded(child: ListView(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
              children: [

                // ── Sekme 0: mevcut derslerden seç ──
                if (sekme == 0) ...[
                  const Text("Excelden yüklenen dersleriniz:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  if (mevcutDersAdlari.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text("Yüklü ders bulunamadı.", style: TextStyle(color: Colors.grey)))
                  else
                    ...mevcutDersAdlari.map((ad) => Card(
                      color: seciliDersAdi == ad ? neuColor.withOpacity(0.1) : null,
                      child: ListTile(
                        dense: true,
                        title: Text(ad, style: const TextStyle(fontSize: 13)),
                        trailing: seciliDersAdi == ad ? const Icon(Icons.check_circle, color: neuColor) : null,
                        onTap: () => setS(() { seciliDersAdi = ad; dersAdiCtrl.text = ad; }),
                      ),
                    )),
                  if (seciliDersAdi != null) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const Text("Gün ve saat seçin:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _GunSaatForm(gunler: gunler, gun: gun, bas: bas, bit: bit, ctx: ctx,
                      onGun: (v) => setS(() => gun = v),
                      onBas: (t) => setS(() => bas = t),
                      onBit: (t) => setS(() => bit = t)),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: neuColor, minimumSize: const Size(double.infinity, 44)),
                      onPressed: () => setS(() {
                        liste.add({"ad": seciliDersAdi!, "gun": gun, "saat": "${bas.format(ctx)} - ${bit.format(ctx)}"});
                        seciliDersAdi = null;
                      }),
                      child: const Text("LİSTEYE EKLE", style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ],

                // ── Sekme 1: ders programından toplu seç ──
                if (sekme == 1) ...[
                  const Text("Ders programınızdaki dersler:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  if (programDersler.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text("Ders programında bu hocaya ait ders bulunamadı.", style: TextStyle(color: Colors.grey)))
                  else ...[
                    ...programDersler.asMap().entries.map((e) {
                      final i = e.key; final d = e.value;
                      final secili = programSecili.contains(i);
                      return CheckboxListTile(
                        dense: true,
                        value: secili,
                        activeColor: neuColor,
                        title: Text(d['ad'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text("${d['gun']} • ${d['saat']} ${d['derslik']?.isNotEmpty == true ? '• ${d['derslik']}' : ''}",
                            style: const TextStyle(fontSize: 11)),
                        onChanged: (v) => setS(() { if (v == true) programSecili.add(i); else programSecili.remove(i); }),
                      );
                    }),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: neuColor, minimumSize: const Size(double.infinity, 44)),
                      onPressed: programSecili.isEmpty ? null : () => setS(() {
                        for (final i in programSecili) {
                          final d = programDersler[i];
                          if (!liste.any((x) => x['ad'] == d['ad'] && x['gun'] == d['gun'])) {
                            liste.add({"ad": d['ad']!, "gun": d['gun']!, "saat": d['saat']!, "derslik": d['derslik'] ?? ''});
                          }
                        }
                        programSecili.clear();
                      }),
                      child: Text("${programSecili.length} DERSİ EKLE", style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ],

                // ── Sekme 2: manuel ──
                if (sekme == 2) ...[
                  Card(
                    color: duzIdx != null ? Colors.orange.shade50 : Colors.grey.shade50,
                    child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                      TextField(controller: dersAdiCtrl,
                          decoration: const InputDecoration(labelText: "Ders Adı", border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      _GunSaatForm(gunler: gunler, gun: gun, bas: bas, bit: bit, ctx: ctx,
                        onGun: (v) => setS(() => gun = v),
                        onBas: (t) => setS(() => bas = t),
                        onBit: (t) => setS(() => bit = t)),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: neuColor, minimumSize: const Size(double.infinity, 44)),
                        onPressed: () {
                          if (dersAdiCtrl.text.isNotEmpty) {
                            setS(() {
                              final y = {"ad": dersAdiCtrl.text.trim(), "gun": gun, "saat": "${bas.format(ctx)} - ${bit.format(ctx)}"};
                              if (duzIdx != null) { liste[duzIdx!] = y; duzIdx = null; } else { liste.add(y); }
                              dersAdiCtrl.clear(); FocusScope.of(ctx).unfocus();
                            });
                          }
                        },
                        child: Text(duzIdx != null ? "GÜNCELLE" : "LİSTEYE EKLE", style: const TextStyle(color: Colors.white)),
                      ),
                    ])),
                  ),
                ],

                // ── Atanan dersler (ortak) ──
                const SizedBox(height: 20),
                Row(children: [
                  const Text("Atanan Dersler", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: neuColor, borderRadius: BorderRadius.circular(10)),
                    child: Text('${liste.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ]),
                const Divider(),
                if (liste.isEmpty)
                  const Padding(padding: EdgeInsets.all(12), child: Text("Henüz ders eklenmedi.", style: TextStyle(color: Colors.grey)))
                else
                  ...liste.asMap().entries.map((e) {
                    final i = e.key; final d = e.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(d['ad'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text("${d['gun']} | ${d['saat']}", style: const TextStyle(fontSize: 11)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                            onPressed: () => setS(() {
                              duzIdx = i; dersAdiCtrl.text = d['ad'] ?? '';
                              gun = gunler.contains(d['gun']) ? d['gun']! : "Pazartesi";
                              sekme = 2;
                            })),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () => setS(() => liste.removeAt(i))),
                      ]),
                    );
                  }),
              ],
            )),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 50)),
                onPressed: () async {
                  await FirebaseDatabase.instance.ref('academic_users/$uid/ders_programi').set(liste);
                  if (mounted) Navigator.pop(ctx);
                },
                child: const Text("TÜM DEĞİŞİKLİKLERİ KAYDET",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        );
      }),
    );
  }

  // -------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Akademisyen Yönetimi"),
        backgroundColor: neuColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _veriCek, tooltip: "Yenile"),
          IconButton(icon: const Icon(Icons.file_upload), onPressed: _exceldenYukle, tooltip: "Excel'den Yükle"),
          IconButton(icon: const Icon(Icons.add), onPressed: () => _akademisyenFormu(), tooltip: "Manuel Ekle"),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator(color: neuColor))
          : RefreshIndicator(
              onRefresh: _veriCek,
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  // --- Ön kayıtlar ---
                  if (_onKayitlar.isNotEmpty) ...[
                    _baslik("Ön Kayıtlı — Hesap Bekleniyor",
                        "${_onKayitlar.length} kişi", Colors.orange),
                    ..._onKayitlar.map(_onKayitKarti),
                    const SizedBox(height: 20),
                  ],

                  // --- Aktif akademisyenler ---
                  _baslik("Aktif Akademisyenler",
                      "${_aktifler.length} kişi", Colors.green),
                  if (_aktifler.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                          child: Text("Henüz aktif akademisyen yok.",
                              style: TextStyle(color: Colors.grey))),
                    ),
                  ..._aktifler.map((a) {
                    final hoca = Academician.fromJson(a, a['_uid'] ?? '');
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      child: ListTile(
                        title: Text("${hoca.unvan} ${hoca.adSoyad}",
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hoca.email),
                            const Divider(height: 10),
                            _derslerText(hoca.verilenDersler),
                          ],
                        ),
                        leading: IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            onPressed: () => _akademisyenFormu(mevcutHoca: hoca)),
                        trailing: IconButton(
                            icon: const Icon(Icons.calendar_month, color: Colors.blue),
                            onPressed: () =>
                                _hocaDersAtaPenceresi(hoca.id!, hoca.adSoyad)),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Widget _baslik(String baslik, String alt, Color renk) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(width: 4, height: 20, color: renk,
              margin: const EdgeInsets.only(right: 8)),
          Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 8),
          Text(alt, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      );

  Widget _onKayitKarti(Map<String, dynamic> ok) => Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade200)),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8)),
            child: const Text("Beklemede",
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold)),
          ),
          title: Text("${ok['unvan'] ?? ''} ${ok['ad_soyad'] ?? ''}".trim(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(ok['email'] ?? '',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          trailing: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: neuColor,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            icon: const Icon(Icons.person_add, size: 16, color: Colors.white),
            label: const Text("Hesap Oluştur",
                style: TextStyle(color: Colors.white, fontSize: 12)),
            onPressed: () => _hesapOlustur(ok),
          ),
        ),
      );

  Widget _derslerText(dynamic dersler) {
    if (dersler == null || dersler is! List || dersler.isEmpty) {
      return const Text("Henüz ders atanmadı.",
          style: TextStyle(color: Colors.red, fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: dersler.map<Widget>((d) {
        final ad  = (d is Map) ? d['ad']  : d.toString();
        final gun = (d is Map && d['gun'] != "-") ? " (${d['gun']})" : "";
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text("• $ad$gun", style: const TextStyle(fontSize: 12)),
        );
      }).toList(),
    );
  }
}

// ── Yardımcı widget'lar ──────────────────────────────────────────────────────

class _SekmeBtn extends StatelessWidget {
  final String label;
  final bool aktif;
  final VoidCallback onTap;
  const _SekmeBtn({required this.label, required this.aktif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: aktif ? const Color(0xFF005A71) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: aktif ? Colors.white : Colors.grey.shade600,
              )),
        ),
      ),
    );
  }
}

class _GunSaatForm extends StatelessWidget {
  final List<String> gunler;
  final String gun;
  final TimeOfDay bas;
  final TimeOfDay bit;
  final BuildContext ctx;
  final void Function(String) onGun;
  final void Function(TimeOfDay) onBas;
  final void Function(TimeOfDay) onBit;

  const _GunSaatForm({
    required this.gunler, required this.gun, required this.bas,
    required this.bit, required this.ctx,
    required this.onGun, required this.onBas, required this.onBit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      DropdownButtonFormField<String>(
        value: gunler.contains(gun) ? gun : gunler.first,
        decoration: const InputDecoration(labelText: "Gün", border: OutlineInputBorder(), isDense: true),
        items: gunler.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
        onChanged: (v) { if (v != null) onGun(v); },
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: bas); if (t != null) onBas(t); },
          child: Text(bas.format(ctx)))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(
          onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: bit); if (t != null) onBit(t); },
          child: Text(bit.format(ctx)))),
      ]),
    ]);
  }
}
