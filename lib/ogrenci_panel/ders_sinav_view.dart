// ogrenci_panel/ders_sinav_view.dart
//
// Tab 1 — Sınavlarım: sınav tarihi, saati, derslik ve oturma yeri
// Tab 2 — Derslerim: ders listesi + yoklama geçmişi

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../services/rest_auth_service.dart';

const Color _neu = Color(0xFF005A71);

class DersSinavView extends StatefulWidget {
  const DersSinavView({super.key});
  @override
  State<DersSinavView> createState() => _DersSinavViewState();
}

class _DersSinavViewState extends State<DersSinavView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _yukleniyor = true;
  String _tc = '';
  String _okulNo = '';  // oturma_plani lookup için (okul numarası)
  List<Map<String, dynamic>> _alinanDersler = [];
  final Map<String, List<_YoklamaKayit>> _gecmis = {};
  final List<_SinavBilgi> _sinavlar = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _yukle();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final uid = RestAuthService.instance.currentUid ?? '';
    if (uid.isEmpty) { setState(() => _yukleniyor = false); return; }

    // TC ve okul_no bul
    final snap = await FirebaseDatabase.instance.ref('users/$uid').get();
    if (!mounted) return;
    if (snap.exists && snap.value is Map) {
      final data = Map<String, dynamic>.from(snap.value as Map);
      _tc     = data['tc']?.toString() ?? '';
      _okulNo = data['okul_no']?.toString() ?? '';
    }
    if (_tc.isEmpty) {
      final okSnap = await FirebaseDatabase.instance
          .ref('on_kayitlar').orderByChild('uid').equalTo(uid).get();
      if (!mounted) return;
      if (okSnap.exists && okSnap.value is Map) {
        (okSnap.value as Map).forEach((tc, val) {
          if (val is Map) {
            _tc     = tc.toString();
            _okulNo = (val as Map)['okul_no']?.toString() ?? _okulNo;
          }
        });
      }
    }
    // okul_no hala boşsa emailden çıkar (22370031030@ogr.neu.edu.tr → 22370031030)
    if (_okulNo.isEmpty) {
      final emailSnap = await FirebaseDatabase.instance.ref('users/$uid/email').get();
      if (!mounted) return;
      final email = emailSnap.value?.toString() ?? '';
      if (email.contains('@')) _okulNo = email.split('@').first;
    }

    // Ders listesi
    if (_tc.isNotEmpty) {
      final dSnap = await FirebaseDatabase.instance
          .ref('on_kayitlar/$_tc/alinan_dersler').get();
      if (dSnap.exists && dSnap.value is List) {
        _alinanDersler = (dSnap.value as List)
            .whereType<Map>()
            .map((d) => Map<String, dynamic>.from(d))
            .toList();
      }
    }
    if (_alinanDersler.isEmpty) {
      final dSnap = await FirebaseDatabase.instance
          .ref('users/${RestAuthService.instance.currentUid}/alinan_dersler').get();
      if (dSnap.exists && dSnap.value is List) {
        _alinanDersler = (dSnap.value as List)
            .whereType<Map>()
            .map((d) => Map<String, dynamic>.from(d))
            .toList();
      }
    }

    if (_alinanDersler.isNotEmpty) {
      await Future.wait([_gecmisYukle(), _sinavlarYukle()]);
    }

    if (mounted) setState(() => _yukleniyor = false);
  }

  // ── Yoklama geçmişi ──────────────────────────────────────────
  Future<void> _gecmisYukle() async {
    final snap = await FirebaseDatabase.instance.ref('attendance_sessions').get();
    if (!snap.exists || snap.value is! Map) return;

    (snap.value as Map).forEach((sid, data) {
      if (data is! Map || data['aktif'] == true) return;
      final dersAdi = data['ders_adi']?.toString().trim() ?? '';
      final tarih   = data['tarih']?.toString() ?? '';

      final alinanNorm = _alinanDersler
          .map((d) => _trNorm(d['ders_adi']?.toString() ?? ''))
          .toList();
      if (!alinanNorm.contains(_trNorm(dersAdi))) return;

      String durum = 'absent';
      final records = data['records'];
      if (records is Map && records.containsKey(_tc)) {
        final rec = records[_tc];
        if (rec is Map) {
          final fs = rec['final_status']?.toString() ?? '';
          durum = fs.isNotEmpty
              ? fs
              : (rec['face_ok'] == true || rec['rfid_ok'] == true ? 'kısmi' : 'absent');
        }
      }

      final normalKey = _alinanDersler
          .map((d) => d['ders_adi']?.toString().trim() ?? '')
          .firstWhere((ad) => _trNorm(ad) == _trNorm(dersAdi), orElse: () => dersAdi);

      _gecmis.putIfAbsent(normalKey, () => []);
      _gecmis[normalKey]!.add(_YoklamaKayit(tarih: tarih, durum: durum));
    });

    _gecmis.forEach((_, list) => list.sort((a, b) => b.tarih.compareTo(a.tarih)));
  }

  // ── Sınav takvimi + oturma yeri ──────────────────────────────
  Future<void> _sinavlarYukle() async {
    final snap = await FirebaseDatabase.instance.ref('sinav_takvimi').get();
    if (!snap.exists || snap.value is! Map) return;

    final alinanNormlar = _alinanDersler
        .map((d) => _trNorm(d['ders_adi']?.toString() ?? ''))
        .toSet();

    // Duplicate engeli: aynı ders+tarih+saat kombinasyonu bir kez eklensin
    final eklenenler = <String>{};

    (snap.value as Map).forEach((kod, data) {
      if (data is! Map) return;
      final dersAdi = data['ders_adi']?.toString().trim() ?? kod.toString();
      if (!alinanNormlar.contains(_trNorm(dersAdi))) return;

      final tarih   = data['tarih']?.toString() ?? '';
      final saat    = data['saat']?.toString() ?? '';
      final hocaAdi = data['hoca_adi']?.toString() ?? '';

      // Aynı ders+tarih+saat varsa atla
      final uniqueKey = '${_trNorm(dersAdi)}|$tarih|$saat';
      if (eklenenler.contains(uniqueKey)) return;
      eklenenler.add(uniqueKey);

      // Oturma yerini bul
      // Key: okul_no (ogrNo), ama tc_no alanında TC saklı
      // Strateji: önce okul_no ile, sonra TC ile, sonra tc_no alanını tüm kayıtlarda tara
      String? derslikAd;
      String? oturmaYeri;
      final atamalarRaw = data['derslik_atamalari'];
      debugPrint('[SINAV] $dersAdi | okulNo=$_okulNo tc=$_tc | atamalarRaw type=${atamalarRaw?.runtimeType}');
      if (atamalarRaw is List) {
        for (final atama in atamalarRaw) {
          if (atama is! Map) continue;
          final oturmalar = atama['oturma_plani'];
          if (oturmalar is! Map) continue;
          debugPrint('[SINAV] oturma keys: ${(oturmalar as Map).keys.take(3).toList()} (toplam ${oturmalar.length})');

          // 1. Doğrudan key eşleşmesi (okul_no veya TC key olarak)
          Map? bulunan;
          for (final arama in [_okulNo, _tc].where((k) => k.isNotEmpty)) {
            if (oturmalar.containsKey(arama)) {
              bulunan = oturmalar[arama] as Map?;
              debugPrint('[SINAV] Strateji-1 bulundu: key=$arama');
              break;
            }
          }

          // 2. tc_no alanıyla tarama (key okul_no ama tc_no alanı var)
          if (bulunan == null && _tc.isNotEmpty) {
            for (final entry in oturmalar.entries) {
              final val = entry.value;
              if (val is Map && val['tc_no']?.toString() == _tc) {
                bulunan = val;
                debugPrint('[SINAV] Strateji-2 bulundu: key=${entry.key}');
                break;
              }
            }
          }

          if (bulunan != null) {
            derslikAd  = atama['derslik_ad']?.toString();
            final sira   = bulunan['sira']?.toString() ?? '?';
            final koltuk = bulunan['koltuk']?.toString() ?? '?';
            oturmaYeri = 'Sıra $sira / Koltuk $koltuk';
            break;
          }
        }
      }

      _sinavlar.add(_SinavBilgi(
        dersAdi:    dersAdi,
        tarih:      tarih,
        saat:       saat,
        hocaAdi:    hocaAdi,
        derslikAd:  derslikAd,
        oturmaYeri: oturmaYeri,
      ));
    });

    _sinavlar.sort((a, b) {
      final td = _tarihCevir(a.tarih).compareTo(_tarihCevir(b.tarih));
      return td != 0 ? td : a.saat.compareTo(b.saat);
    });
  }

  DateTime _tarihCevir(String t) {
    try {
      final p = t.split('.');
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) { return DateTime(2000); }
  }

  static String _trNorm(String s) => s
      .replaceAll('İ', 'i').replaceAll('I', 'i').replaceAll('ı', 'i')
      .replaceAll('Ğ', 'g').replaceAll('ğ', 'g')
      .replaceAll('Ş', 's').replaceAll('ş', 's')
      .replaceAll('Ö', 'o').replaceAll('ö', 'o')
      .replaceAll('Ü', 'u').replaceAll('ü', 'u')
      .replaceAll('Ç', 'c').replaceAll('ç', 'c')
      .toLowerCase().trim();

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Center(child: CircularProgressIndicator(color: _neu));
    }

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            indicatorColor: _neu,
            labelColor: _neu,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(
                icon: const Icon(Icons.event_note, size: 18),
                text: 'Sınavlarım (${_sinavlar.length})',
              ),
              Tab(
                icon: const Icon(Icons.menu_book, size: 18),
                text: 'Derslerim',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _SinavlarTab(sinavlar: _sinavlar, tc: _tc),
              _DerslerTab(alinanDersler: _alinanDersler, gecmis: _gecmis, tc: _tc),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — SINAVLARIM
// ══════════════════════════════════════════════════════════════════════════════
class _SinavlarTab extends StatelessWidget {
  final List<_SinavBilgi> sinavlar;
  final String tc;
  const _SinavlarTab({required this.sinavlar, required this.tc});

  @override
  Widget build(BuildContext context) {
    if (sinavlar.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('Sınav takvimi bulunamadı.',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            SizedBox(height: 6),
            Text('Sınavlar atandığında burada görünecek.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final bugunBase = DateTime(now.year, now.month, now.day);

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: sinavlar.length,
      itemBuilder: (_, i) {
        final s = sinavlar[i];
        final sinavTarihi = _tarihCevir(s.tarih);
        final gecti = sinavTarihi.isBefore(bugunBase);
        final bugun = sinavTarihi.isAtSameMomentAs(bugunBase);

        final renk = gecti ? Colors.grey : (bugun ? Colors.orange : _neu);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: bugun ? 4 : 1.5,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: bugun
                  ? Border.all(color: Colors.orange.withOpacity(0.6), width: 1.5)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tarih kutusu
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: renk.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(children: [
                          Text(
                            s.tarih.isNotEmpty ? s.tarih.split('.')[0] : '?',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold, color: renk),
                          ),
                          Text(_ayAdi(s.tarih),
                              style: TextStyle(fontSize: 11, color: renk)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      // Ders adı + hoca
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (bugun)
                              Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('BUGÜN',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            Text(s.dersAdi,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: gecti ? Colors.grey : Colors.black87)),
                            if (s.hocaAdi.isNotEmpty)
                              Text(s.hocaAdi,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      // Saat
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: renk.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(s.saat,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: renk)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Oturma yeri
                  if (tc.isEmpty)
                    _uyariSatiri('TC kaydı olmadığı için oturma yeri gösterilemiyor.')
                  else if (s.derslikAd != null && s.oturmaYeri != null)
                    Row(children: [
                      _bilgiBadge(Icons.meeting_room, s.derslikAd!, Colors.green),
                      const SizedBox(width: 10),
                      _bilgiBadge(Icons.chair_alt, s.oturmaYeri!, _neu),
                    ])
                  else
                    _uyariSatiri('Oturma planı henüz oluşturulmadı.'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bilgiBadge(IconData icon, String label, Color renk) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: renk.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: renk.withOpacity(0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: renk),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13, color: renk)),
    ]),
  );

  Widget _uyariSatiri(String mesaj) => Row(children: [
    Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
    const SizedBox(width: 6),
    Expanded(
      child: Text(mesaj,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
    ),
  ]);

  DateTime _tarihCevir(String t) {
    try {
      final p = t.split('.');
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) { return DateTime(2000); }
  }

  String _ayAdi(String tarih) {
    const aylar = ['', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
                        'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    try {
      return aylar[int.parse(tarih.split('.')[1])];
    } catch (_) { return ''; }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — DERSLERİM + YOKLAMA GEÇMİŞİ
// ══════════════════════════════════════════════════════════════════════════════
class _DerslerTab extends StatelessWidget {
  final List<Map<String, dynamic>> alinanDersler;
  final Map<String, List<_YoklamaKayit>> gecmis;
  final String tc;
  const _DerslerTab({
    required this.alinanDersler,
    required this.gecmis,
    required this.tc,
  });

  @override
  Widget build(BuildContext context) {
    if (alinanDersler.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('Kayıtlı ders bulunamadı.',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: alinanDersler.length,
      itemBuilder: (context, i) {
        final ders    = alinanDersler[i];
        final dersAdi = ders['ders_adi']?.toString() ?? '—';
        final hocaAdi = ders['hoca_adi']?.toString() ?? '—';
        final kayitlar = gecmis[dersAdi] ?? [];
        final katildi = kayitlar.where((k) => k.durum == 'present').length;
        final toplam  = kayitlar.length;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 1.5,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              backgroundColor: _neu.withOpacity(0.1),
              child: Text(
                dersAdi.isNotEmpty ? dersAdi[0].toUpperCase() : '?',
                style: const TextStyle(color: _neu, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(dersAdi,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(hocaAdi,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: toplam == 0 ? null
                : _DevamChip(katildi: katildi, toplam: toplam),
            children: [
              if (tc.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'TC kimlik numarası kayıtlı olmadığı için yoklama geçmişi gösterilemiyor.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                )
              else if (kayitlar.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Henüz yoklama kaydı yok.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              else
                ...kayitlar.take(10).map((k) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: _DurumIkon(durum: k.durum),
                  title: Text(k.tarih.isNotEmpty ? k.tarih : '—',
                      style: const TextStyle(fontSize: 13)),
                  trailing: _DurumEtiket(durum: k.durum),
                )),
              if (kayitlar.length > 10)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('  ... ve ${kayitlar.length - 10} kayıt daha',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Yardımcı widget'lar ───────────────────────────────────────────────────────
class _DevamChip extends StatelessWidget {
  final int katildi;
  final int toplam;
  const _DevamChip({required this.katildi, required this.toplam});
  @override
  Widget build(BuildContext context) {
    final oran = toplam > 0 ? katildi / toplam : 0.0;
    final renk = oran >= 0.7 ? Colors.green : (oran >= 0.5 ? Colors.orange : Colors.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: renk.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: renk.withOpacity(0.4)),
      ),
      child: Text('$katildi/$toplam',
          style: TextStyle(fontSize: 12, color: renk, fontWeight: FontWeight.bold)),
    );
  }
}

class _DurumIkon extends StatelessWidget {
  final String durum;
  const _DurumIkon({required this.durum});
  @override
  Widget build(BuildContext context) {
    switch (durum) {
      case 'present':   return const Icon(Icons.check_circle, color: Colors.green, size: 18);
      case 'face_only':
      case 'rfid_only':
      case 'kısmi':     return const Icon(Icons.remove_circle, color: Colors.orange, size: 18);
      default:          return const Icon(Icons.cancel, color: Colors.red, size: 18);
    }
  }
}

class _DurumEtiket extends StatelessWidget {
  final String durum;
  const _DurumEtiket({required this.durum});
  @override
  Widget build(BuildContext context) {
    String label; Color color;
    switch (durum) {
      case 'present':   label = 'Mevcut'; color = Colors.green;  break;
      case 'face_only': label = 'Yüz ✓';  color = Colors.orange; break;
      case 'rfid_only': label = 'RFID ✓'; color = Colors.orange; break;
      case 'kısmi':     label = 'Kısmi';  color = Colors.orange; break;
      default:          label = 'Gelmedi'; color = Colors.red;
    }
    return Text(label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold));
  }
}

// ── Veri modelleri ────────────────────────────────────────────────────────────
class _YoklamaKayit {
  final String tarih;
  final String durum;
  const _YoklamaKayit({required this.tarih, required this.durum});
}

class _SinavBilgi {
  final String dersAdi;
  final String tarih;
  final String saat;
  final String hocaAdi;
  final String? derslikAd;
  final String? oturmaYeri;
  const _SinavBilgi({
    required this.dersAdi,
    required this.tarih,
    required this.saat,
    required this.hocaAdi,
    this.derslikAd,
    this.oturmaYeri,
  });
}
