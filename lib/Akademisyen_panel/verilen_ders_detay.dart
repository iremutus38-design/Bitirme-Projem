// verilen_ders_detay.dart
//
// Bir derse tıklandığında açılır.
// on_kayitlar/ altında alinan_dersler[*].ders_adi == dersAdi olan öğrencileri listeler.
// Hem ders adı eşleşmesi hem de hoca adı eşleşmesi kontrol edilir.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class DersDetaySayfasi extends StatefulWidget {
  final String dersAdi;
  final String hocaAdSoyad; // eşleşme doğruluğu için

  const DersDetaySayfasi({
    super.key,
    required this.dersAdi,
    required this.hocaAdSoyad,
  });

  @override
  State<DersDetaySayfasi> createState() => _DersDetaySayfasiState();
}

class _DersDetaySayfasiState extends State<DersDetaySayfasi> {
  static const Color _neu = Color(0xFF005A71);

  List<_OgrenciItem> _ogrenciler = [];
  bool _yukleniyor = true;
  String _aramaMetni = '';

  @override
  void initState() {
    super.initState();
    _veriCek();
  }

  Future<void> _veriCek() async {
    setState(() => _yukleniyor = true);

    final snap = await FirebaseDatabase.instance.ref().child('on_kayitlar').get();
    final liste = <_OgrenciItem>[];

    if (snap.exists && snap.value is Map) {
      (snap.value as Map).forEach((tc, val) {
        if (val is! Map) return;
        final data = Map<String, dynamic>.from(val);

        // alinan_dersler: [{ders_adi: "...", hoca_adi: "..."}, ...]
        final derslerRaw = data['alinan_dersler'];
        if (derslerRaw is! List) return;

        for (final d in derslerRaw) {
          if (d is! Map) continue;
          final dersAdi  = d['ders_adi']?.toString().trim() ?? '';
          final hocaAdi  = d['hoca_adi']?.toString().trim() ?? '';

          if (_dersEslesiyor(dersAdi) && _hocaEslesiyor(hocaAdi)) {
            liste.add(_OgrenciItem(
              adSoyad: data['ad_soyad']?.toString() ?? 'İsimsiz',
              okulNo:  data['okul_no']?.toString() ?? '-',
              bolum:   data['bolum']?.toString() ?? '-',
              sinif:   data['sinif']?.toString() ?? '-',
              email:   data['email']?.toString() ?? '-',
            ));
            break; // aynı öğrenciyi iki kez ekleme
          }
        }
      });
    }

    liste.sort((a, b) => a.adSoyad.compareTo(b.adSoyad));
    if (mounted) setState(() { _ogrenciler = liste; _yukleniyor = false; });
  }

  /// Ders adı tam eşleşme (büyük/küçük harf duyarsız)
  bool _dersEslesiyor(String firebaseAd) =>
      firebaseAd.toLowerCase() == widget.dersAdi.toLowerCase();

  /// Hoca adı: Firebase'deki "Dr. Öğr. Üyesi HASAN SERDAR" ile
  /// academic_users'taki "HASAN SERDAR" gibi kısa versiyonu eşleştir.
  /// Hoca adındaki 3+ karakterli kelimelerin en az biri örtüşüyorsa eşleşti say.
  bool _hocaEslesiyor(String firebaseHoca) {
    if (widget.hocaAdSoyad.isEmpty) return true; // kontrol yapma
    final hedef = widget.hocaAdSoyad.toLowerCase().split(' ')
        .where((k) => k.length > 2).toSet();
    final kaynak = firebaseHoca.toLowerCase().split(' ')
        .where((k) => k.length > 2).toSet();
    return hedef.intersection(kaynak).isNotEmpty;
  }

  List<_OgrenciItem> get _filtreliListe {
    if (_aramaMetni.isEmpty) return _ogrenciler;
    final q = _aramaMetni.toLowerCase();
    return _ogrenciler
        .where((o) =>
            o.adSoyad.toLowerCase().contains(q) ||
            o.okulNo.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final liste = _filtreliListe;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.dersAdi,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: _neu,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        // ---- Özet ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          color: _neu.withOpacity(0.07),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _OzetKutu(
                ikon: Icons.people,
                deger: _yukleniyor ? '...' : '${_ogrenciler.length}',
                etiket: 'Toplam Öğrenci',
              ),
              _OzetKutu(
                ikon: Icons.school,
                deger: _yukleniyor ? '...' : '${liste.length}',
                etiket: 'Gösterilen',
              ),
            ],
          ),
        ),

        // ---- Arama ----
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _aramaMetni = v),
            decoration: InputDecoration(
              hintText: 'Ad veya öğrenci no ile ara...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),

        // ---- Liste ----
        Expanded(
          child: _yukleniyor
              ? const Center(child: CircularProgressIndicator(color: _neu))
              : liste.isEmpty
                  ? const Center(
                      child: Text('Bu dersi alan öğrenci bulunamadı.',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: liste.length,
                      itemBuilder: (_, i) {
                        final o = liste[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _neu.withOpacity(0.1),
                              child: Text(
                                o.adSoyad.isNotEmpty
                                    ? o.adSoyad[0]
                                    : '?',
                                style: const TextStyle(
                                    color: _neu, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(o.adSoyad,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(
                              '${o.okulNo}  •  ${o.bolum}  •  ${o.sinif}. Sınıf',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              '${i + 1}',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────
class _OzetKutu extends StatelessWidget {
  final IconData ikon;
  final String deger;
  final String etiket;
  const _OzetKutu({required this.ikon, required this.deger, required this.etiket});

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(ikon, color: const Color(0xFF005A71), size: 22),
        const SizedBox(height: 4),
        Text(deger,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF005A71))),
        Text(etiket, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]);
}

// ───────────────────────────────────────────────
class _OgrenciItem {
  final String adSoyad;
  final String okulNo;
  final String bolum;
  final String sinif;
  final String email;

  const _OgrenciItem({
    required this.adSoyad,
    required this.okulNo,
    required this.bolum,
    required this.sinif,
    required this.email,
  });
}
