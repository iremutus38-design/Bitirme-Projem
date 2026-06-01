// sinav_bildirim_sayfasi.dart
//
// Akademisyenin verdiği dersler için sınav takvimi:
//   - sinav_takvimi/{kod}/hoca_adi  → bu hocaya mı?  (fuzzy match)
//   - tarih / saat / derslik_atamalari / ogrenciler

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class SinavBildirimSayfasi extends StatefulWidget {
  final String hocaAdSoyad;
  const SinavBildirimSayfasi({super.key, required this.hocaAdSoyad});

  @override
  State<SinavBildirimSayfasi> createState() => _SinavBildirimSayfasiState();
}

class _SinavBildirimSayfasiState extends State<SinavBildirimSayfasi> {
  static const Color _neu = Color(0xFF005A71);

  List<_SinavItem> _sinavlar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _veriCek();
  }

  // Unvan kısaltmaları — bunlar eşleşmede KULLANILMAZ
  static const _unvanlar = {'prof', 'doc', 'doç', 'yrd', 'ogr', 'öğr',
      'gor', 'gör', 'uzm', 'uyesi', 'üyesi', 'yardimci', 'yardımcı', 'dr'};

  bool _hocaEslesiyor(String firebaseHoca) {
    if (widget.hocaAdSoyad.isEmpty) return false;

    Set<String> isimKelimeleri(String s) => s
        .toLowerCase()
        .replaceAll('.', ' ')
        .split(' ')
        .where((k) => k.length > 2 && !_unvanlar.contains(k))
        .toSet();

    final hedef = isimKelimeleri(widget.hocaAdSoyad);
    final kaynak = isimKelimeleri(firebaseHoca);
    if (hedef.isEmpty || kaynak.isEmpty) return false;
    // En az 2 kelime eşleşmeli VEYA tek kelime varsa o eşleşmeli
    final ortak = hedef.intersection(kaynak);
    return ortak.length >= 2 || (hedef.length == 1 && ortak.length == 1);
  }

  Future<void> _veriCek() async {
    setState(() => _yukleniyor = true);
    final snap = await FirebaseDatabase.instance.ref('sinav_takvimi').get();
    final liste = <_SinavItem>[];

    if (snap.exists && snap.value is Map) {
      (snap.value as Map).forEach((kod, val) {
        if (val is! Map) return;
        final data = Map<String, dynamic>.from(val);
        final hocaAdi = data['hoca_adi']?.toString() ?? '';
        if (!_hocaEslesiyor(hocaAdi)) return;

        // Öğrenciler
        final ogrencilerRaw = data['ogrenciler'];
        final ogrenciler = <_OgrenciSinav>[];
        if (ogrencilerRaw is Map) {
          ogrencilerRaw.forEach((ogrNo, ogrVal) {
            if (ogrVal is Map) {
              ogrenciler.add(_OgrenciSinav(
                okulNo: ogrNo.toString(),
                adSoyad: ogrVal['ad_soyad']?.toString() ?? '',
                tc: ogrVal['tc']?.toString() ?? '',
              ));
            }
          });
        }
        ogrenciler.sort((a, b) => a.adSoyad.compareTo(b.adSoyad));

        // Derslik atamaları
        final atamalarRaw = data['derslik_atamalari'];
        final derslikler = <String>[];
        if (atamalarRaw is List) {
          for (final a in atamalarRaw) {
            if (a is Map) {
              final d = a['derslik_ad']?.toString() ?? a['derslik_id']?.toString() ?? '';
              if (d.isNotEmpty) derslikler.add(d);
            }
          }
        } else if (atamalarRaw is Map) {
          atamalarRaw.forEach((_, a) {
            if (a is Map) {
              final d = a['derslik_ad']?.toString() ?? a['derslik_id']?.toString() ?? '';
              if (d.isNotEmpty) derslikler.add(d);
            }
          });
        }

        // Oturma planı (ilk derslikten)
        final Map<String, Map<String, dynamic>> oturmaPlan = {};
        if (atamalarRaw is List && atamalarRaw.isNotEmpty) {
          final ilk = atamalarRaw.first;
          if (ilk is Map) {
            final plRaw = ilk['oturma_plani'];
            if (plRaw is Map) {
              plRaw.forEach((ogrNo, yer) {
                if (yer is Map) oturmaPlan[ogrNo.toString()] = Map<String, dynamic>.from(yer);
              });
            }
          }
        }

        liste.add(_SinavItem(
          kod: kod.toString(),
          dersAdi: data['ders_adi']?.toString() ?? kod.toString(),
          hocaAdi: hocaAdi,
          tarih: data['tarih']?.toString() ?? '-',
          saat: data['saat']?.toString() ?? '-',
          derslikler: derslikler,
          ogrenciler: ogrenciler,
          oturmaPlan: oturmaPlan,
        ));
      });
    }

    // Tarihe göre sırala
    liste.sort((a, b) => a.tarih.compareTo(b.tarih));
    if (mounted) setState(() { _sinavlar = liste; _yukleniyor = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Sınavlarım', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: _neu,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _veriCek),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : _sinavlar.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.event_available, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    const Text('Sınav takviminde adınıza kayıtlı sınav bulunamadı.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _sinavlar.length,
                  itemBuilder: (_, i) => _SinavKarti(
                    sinav: _sinavlar[i],
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => _SinavDetay(sinav: _sinavlar[i]))),
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────
class _SinavKarti extends StatelessWidget {
  final _SinavItem sinav;
  final VoidCallback onTap;
  const _SinavKarti({required this.sinav, required this.onTap});

  static const Color _neu = Color(0xFF005A71);

  Color get _renkDurum {
    try {
      final parts = sinav.tarih.split('-'); // yyyy-MM-dd veya dd.MM.yyyy
      DateTime? tarih;
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          tarih = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        } else {
          tarih = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        }
      }
      if (tarih == null) return Colors.blueGrey;
      final fark = tarih.difference(DateTime.now()).inDays;
      if (fark < 0) return Colors.grey;
      if (fark <= 7) return Colors.red;
      if (fark <= 14) return Colors.orange;
      return Colors.green;
    } catch (_) {
      return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final renk = _renkDurum;
    final derslikBilgi = sinav.derslikler.isNotEmpty
        ? sinav.derslikler.join(', ')
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            // Tarih kutusu
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: renk.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(children: [
                Icon(Icons.event, color: renk, size: 22),
                const SizedBox(height: 4),
                Text(sinav.tarih, style: TextStyle(fontSize: 10, color: renk, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sinav.dersAdi, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(sinav.saat, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(width: 12),
                  const Icon(Icons.people, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${sinav.ogrenciler.length} öğrenci',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                if (derslikBilgi != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.room, size: 12, color: Colors.teal),
                    const SizedBox(width: 4),
                    Text(derslikBilgi,
                        style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w500)),
                  ]),
                ],
              ],
            )),
            const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
class _SinavDetay extends StatelessWidget {
  final _SinavItem sinav;
  const _SinavDetay({super.key, required this.sinav});

  static const Color _neu = Color(0xFF005A71);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(sinav.dersAdi,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: _neu,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        // Özet
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: _neu.withOpacity(0.07),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _BilgiSatiri(icon: Icons.event, label: 'Tarih', deger: sinav.tarih),
            _BilgiSatiri(icon: Icons.access_time, label: 'Saat', deger: sinav.saat),
            _BilgiSatiri(icon: Icons.people, label: 'Öğrenci', deger: '${sinav.ogrenciler.length} kişi'),
            if (sinav.derslikler.isNotEmpty)
              _BilgiSatiri(
                  icon: Icons.room,
                  label: 'Derslik',
                  deger: sinav.derslikler.join(' / '),
                  renk: Colors.teal),
            if (sinav.derslikler.isEmpty)
              _BilgiSatiri(
                  icon: Icons.warning_amber,
                  label: 'Derslik',
                  deger: 'Henüz atanmadı',
                  renk: Colors.orange),
          ]),
        ),

        // Öğrenci listesi
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            const Text('Sınava Girecek Öğrenciler',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
        ),

        Expanded(
          child: sinav.ogrenciler.isEmpty
              ? const Center(child: Text('Öğrenci bulunamadı.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: sinav.ogrenciler.length,
                  itemBuilder: (_, i) {
                    final o = sinav.ogrenciler[i];
                    final yer = sinav.oturmaPlan[o.okulNo];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: _neu.withOpacity(0.1),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 11, color: _neu, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(o.adSoyad,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(o.okulNo,
                            style: const TextStyle(fontSize: 11)),
                        trailing: yer != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                                ),
                                child: Text(
                                  yer['yer']?.toString() ?? 'S${yer['sira']} K${yer['koltuk']}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.teal,
                                      fontWeight: FontWeight.bold),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────
class _BilgiSatiri extends StatelessWidget {
  final IconData icon;
  final String label;
  final String deger;
  final Color renk;
  const _BilgiSatiri(
      {required this.icon, required this.label, required this.deger, this.renk = Colors.blueGrey});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(icon, size: 15, color: renk),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(fontSize: 13, color: Colors.grey)),
      Expanded(
          child: Text(deger,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: renk))),
    ]),
  );
}

// ─────────────────────────────────────────────────────
class _SinavItem {
  final String kod;
  final String dersAdi;
  final String hocaAdi;
  final String tarih;
  final String saat;
  final List<String> derslikler;
  final List<_OgrenciSinav> ogrenciler;
  final Map<String, Map<String, dynamic>> oturmaPlan;

  const _SinavItem({
    required this.kod,
    required this.dersAdi,
    required this.hocaAdi,
    required this.tarih,
    required this.saat,
    required this.derslikler,
    required this.ogrenciler,
    required this.oturmaPlan,
  });
}

class _OgrenciSinav {
  final String okulNo;
  final String adSoyad;
  final String tc;
  const _OgrenciSinav(
      {required this.okulNo, required this.adSoyad, required this.tc});
}
