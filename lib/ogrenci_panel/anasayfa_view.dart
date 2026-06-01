// ogrenci_panel/anasayfa_view.dart

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../services/rest_auth_service.dart';
import '../services/enrollment_service.dart';

const Color _neu = Color(0xFF005A71);

class _YaklasanDers {
  final String dersAdi;
  final String gun;
  final String saat;
  final String hoca;
  const _YaklasanDers({required this.dersAdi, required this.gun, required this.saat, required this.hoca});
}

class AnasayfaView extends StatefulWidget {
  const AnasayfaView({super.key});
  @override
  State<AnasayfaView> createState() => _AnasayfaViewState();
}

class _AnasayfaViewState extends State<AnasayfaView> {
  bool _yukleniyor = true;
  String _adSoyad = '';
  String _tc = '';
  List<String> _alinanDersler = [];

  // Ders programı
  List<_YaklasanDers> _bugunDersler = [];
  List<_YaklasanDers> _haftaDersler = [];

  // Aktif session
  String? _sessionId;
  String? _aktifDersAdi;
  String _yoklamaDurum = 'bekliyor';

  StreamSubscription? _sessionSub;
  StreamSubscription? _recordSub;

  bool _yukleniyor_kamera = false;
  final _enrollService = EnrollmentService();

  static const List<String> _gunSirasi = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _recordSub?.cancel();
    super.dispose();
  }

  Future<void> _yukle() async {
    final uid = RestAuthService.instance.currentUid ?? '';
    if (uid.isEmpty) { setState(() => _yukleniyor = false); return; }

    final snap = await FirebaseDatabase.instance.ref('users/$uid').get();
    if (!mounted) return;
    if (snap.exists && snap.value is Map) {
      final data = Map<String, dynamic>.from(snap.value as Map);
      _adSoyad = data['ad_soyad']?.toString() ?? '';
      _tc = data['tc']?.toString() ?? '';
    }

    // TC yoksa on_kayitlar'da uid ile ara
    if (_tc.isEmpty) {
      final okSnap = await FirebaseDatabase.instance
          .ref('on_kayitlar').orderByChild('uid').equalTo(uid).get();
      if (!mounted) return;
      if (okSnap.exists && okSnap.value is Map) {
        (okSnap.value as Map).forEach((tc, val) {
          if (val is Map) _tc = tc.toString();
        });
      }
    }

    // on_kayitlar'dan canlı ders listesi
    List<String> dersler = [];
    if (_tc.isNotEmpty) {
      final derslerSnap = await FirebaseDatabase.instance
          .ref('on_kayitlar/$_tc/alinan_dersler').get();
      if (derslerSnap.exists && derslerSnap.value is List) {
        dersler = (derslerSnap.value as List)
            .map((d) => d is Map ? (d['ders_adi']?.toString().trim() ?? '') : '')
            .where((s) => s.isNotEmpty).toList();
      }
    }
    if (dersler.isEmpty) {
      final derslerSnap = await FirebaseDatabase.instance
          .ref('users/$uid/alinan_dersler').get();
      if (derslerSnap.exists && derslerSnap.value is List) {
        dersler = (derslerSnap.value as List)
            .map((d) => d is Map ? (d['ders_adi']?.toString().trim() ?? '') : '')
            .where((s) => s.isNotEmpty).toList();
      }
    }
    _alinanDersler = dersler;

    // Ders programını yükle
    if (_alinanDersler.isNotEmpty) {
      await _programYukle();
    }

    if (mounted) setState(() => _yukleniyor = false);
    _sessionDinle();
  }

  Future<void> _programYukle() async {
    final snap = await FirebaseDatabase.instance.ref('academic_users').get();
    if (!snap.exists || snap.value is! Map) return;

    final bugun = _gunSirasi[DateTime.now().weekday - 1];
    final List<_YaklasanDers> bugunList = [];
    final List<_YaklasanDers> haftaList = [];

    (snap.value as Map).forEach((_, akademisyen) {
      if (akademisyen is! Map) return;
      final hocaAdi = akademisyen['ad_soyad']?.toString() ?? '';
      final program = akademisyen['ders_programi'];
      if (program == null) return;

      void isleEntry(dynamic entry) {
        if (entry is! Map) return;
        final gun = entry['gun']?.toString() ?? '';
        final saat = entry['saat']?.toString() ?? '';
        final ad = (entry['ad'] ?? entry['ders_adi'] ?? entry['dersAdi'] ?? '').toString().trim();
        if (gun.isEmpty || ad.isEmpty) return;

        // Bu dersi öğrenci alıyor mu?
        final eslesme = _alinanDersler.any((d) => _trNorm(d) == _trNorm(ad));
        if (!eslesme) return;

        final ders = _YaklasanDers(dersAdi: ad, gun: gun, saat: saat, hoca: hocaAdi);
        if (gun == bugun) {
          bugunList.add(ders);
        } else {
          haftaList.add(ders);
        }
      }

      if (program is List) {
        for (final e in program) isleEntry(e);
      } else if (program is Map) {
        for (final e in program.values) isleEntry(e);
      }
    });

    // Bugün: saate göre sırala
    bugunList.sort((a, b) => _dakikaStr(a.saat).compareTo(_dakikaStr(b.saat)));

    // Hafta: gün sırasına, sonra saate göre sırala
    haftaList.sort((a, b) {
      final gi = _gunSirasi.indexOf(a.gun).compareTo(_gunSirasi.indexOf(b.gun));
      if (gi != 0) return gi;
      return _dakikaStr(a.saat).compareTo(_dakikaStr(b.saat));
    });

    _bugunDersler = bugunList;
    _haftaDersler = haftaList;
  }

  int _dakikaStr(String saat) {
    if (saat.isEmpty) return 9999;
    final parts = saat.split(':');
    if (parts.length < 2) return 9999;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  void _sessionDinle() {
    _sessionSub?.cancel();
    _sessionSub = FirebaseDatabase.instance.ref('attendance_sessions').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.value is! Map) return;

      String? bulunduSid;
      String? bulunduDers;

      (event.snapshot.value as Map).forEach((sid, data) {
        if (data is! Map) return;
        if (data['aktif'] != true) return;
        final dersAdi = data['ders_adi']?.toString().trim() ?? '';
        if (_dersEslesiyor(dersAdi)) {
          bulunduSid = sid.toString();
          bulunduDers = dersAdi;
        }
      });

      if (bulunduSid != _sessionId) {
        _recordSub?.cancel();
        setState(() {
          _sessionId = bulunduSid;
          _aktifDersAdi = bulunduDers;
          _yoklamaDurum = bulunduSid != null ? 'bekliyor' : 'yok';
        });
        if (bulunduSid != null) _recordDinle(bulunduSid!);
      }
    });
  }

  void _recordDinle(String sid) {
    if (_tc.isEmpty) return;
    _recordSub?.cancel();
    _recordSub = FirebaseDatabase.instance
        .ref('attendance_sessions/$sid/records/$_tc')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final rec = event.snapshot.value;
      if (rec is Map) {
        final fs = rec['final_status']?.toString() ?? '';
        setState(() {
          if (fs.isNotEmpty) {
            _yoklamaDurum = fs;
          } else if (rec['face_ok'] == true && rec['rfid_ok'] == true) {
            _yoklamaDurum = 'present';
          } else if (rec['face_ok'] == true) {
            _yoklamaDurum = 'face_only';
          } else if (rec['rfid_ok'] == true) {
            _yoklamaDurum = 'rfid_only';
          }
        });
      }
    });
  }

  Future<void> _yuzOkut() async {
    if (_yukleniyor_kamera || _tc.isEmpty) return;
    setState(() => _yukleniyor_kamera = true);
    try {
      // Mac kamerasını sunucu üzerinden kullan (GET /attend_face?tc=TC)
      final result = await _enrollService.attendFace(_tc, sessionId: _sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.fixed,
        ));
      }
    } finally {
      if (mounted) setState(() => _yukleniyor_kamera = false);
    }
  }

  bool _dersEslesiyor(String firebaseAd) {
    final hedef = _trNorm(firebaseAd);
    for (final d in _alinanDersler) {
      if (hedef == _trNorm(d)) return true;
      final ht = hedef.replaceAll(RegExp(r'\(.*?\)'), '').trim();
      final kt = _trNorm(d).replaceAll(RegExp(r'\(.*?\)'), '').trim();
      if (ht == kt) return true;
    }
    return false;
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

    final now = DateTime.now();
    final saatStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final gun = _gunSirasi[(now.weekday - 1).clamp(0, 6)];
    final nowDakika = now.hour * 60 + now.minute;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hoşgeldin ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF005A71), Color(0xFF007A98)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Merhaba,',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  _adSoyad.isNotEmpty ? _adSoyad : 'Öğrenci',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                  const SizedBox(width: 5),
                  Text('$gun  •  $saatStr',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ],
            ),
          ),

          // ── Bugünün Dersleri ──
          if (_bugunDersler.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Text('Bugünün Dersleri',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _neu)),
            const SizedBox(height: 10),
            ..._bugunDersler.map((d) {
              final dkika = _dakikaStr(d.saat);
              final bitti = nowDakika > dkika + 50; // ~50 dk ders
              final aktif = !bitti && nowDakika >= dkika - 15 && nowDakika <= dkika + 50;
              final renk = bitti ? Colors.grey : (aktif ? Colors.green : _neu);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: aktif
                      ? Border.all(color: Colors.green.withOpacity(0.5), width: 1.5)
                      : null,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: renk.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      d.saat.isNotEmpty ? d.saat.split(' ')[0] : '—',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: renk),
                    ),
                  ),
                  title: Text(d.dersAdi,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: bitti ? Colors.grey : Colors.black87)),
                  subtitle: d.hoca.isNotEmpty
                      ? Text(d.hoca, style: const TextStyle(fontSize: 11, color: Colors.grey))
                      : null,
                  trailing: bitti
                      ? const Text('Bitti', style: TextStyle(fontSize: 11, color: Colors.grey))
                      : aktif
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Devam ediyor',
                                  style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                            )
                          : null,
                ),
              );
            }),
          ],

          // ── Haftalık dersler (bugün yoksa) ──
          if (_bugunDersler.isEmpty && _haftaDersler.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Text('Bu Hafta',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _neu)),
            const SizedBox(height: 10),
            ..._haftaDersler.take(5).map((d) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _neu.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.gun.length >= 3 ? d.gun.substring(0, 3) : d.gun,
                          style: const TextStyle(fontSize: 10, color: _neu)),
                      Text(d.saat.isNotEmpty ? d.saat.split(' ')[0] : '—',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _neu)),
                    ],
                  ),
                ),
                title: Text(d.dersAdi,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: d.hoca.isNotEmpty
                    ? Text(d.hoca, style: const TextStyle(fontSize: 11, color: Colors.grey))
                    : null,
              ),
            )),
          ],

          // ── Program bilgisi yoksa bugün ders yok mesajı ──
          if (_bugunDersler.isEmpty && _haftaDersler.isEmpty && _alinanDersler.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Text('Bugünün Dersleri',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _neu)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)],
              ),
              child: Row(children: [
                Icon(Icons.event_available_outlined, color: Colors.grey.withOpacity(0.5), size: 32),
                const SizedBox(width: 14),
                const Expanded(child: Text('Bugün için ders programı bulunamadı.',
                    style: TextStyle(fontSize: 13, color: Colors.grey))),
              ]),
            ),
          ],

          const SizedBox(height: 22),

          // ── Yoklama Durumu ──
          const Text('Yoklama Durumu',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _neu)),
          const SizedBox(height: 10),
          if (_sessionId == null)
            _BilgiKarti(
              icon: Icons.check_circle_outline,
              renk: Colors.grey,
              baslik: 'Aktif yoklama yok',
              icerik: 'Şu an için herhangi bir dersinizde yoklama başlatılmamış.',
            )
          else ...[
            _AktifYoklamaKarti(
              dersAdi: _aktifDersAdi ?? '',
              durum: _yoklamaDurum,
              tcBosMu: _tc.isEmpty,
            ),
            // Yüz okutma butonu — sadece yüz henüz onaylanmamışsa göster
            if (_yoklamaDurum == 'bekliyor' || _yoklamaDurum == 'rfid_only') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _yukleniyor_kamera ? null : _yuzOkut,
                  icon: _yukleniyor_kamera
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.face_retouching_natural),
                  label: Text(_yukleniyor_kamera ? 'Tanınıyor...' : 'Yüzümü Okut'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _neu,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],

          // ── Bu Dönem özet ──
          if (_alinanDersler.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Text('Bu Dönem',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _neu)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
              ),
              child: Row(children: [
                _OzetKutu(deger: '${_alinanDersler.length}', etiket: 'Ders', renk: _neu),
                const VerticalDivider(indent: 10, endIndent: 10),
                const Expanded(
                  child: Text(
                    'Dersler sekmesinden tüm ders listenizi ve yoklama geçmişinizi görebilirsiniz.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Aktif yoklama kartı ───────────────────────────────────────────────────────

class _AktifYoklamaKarti extends StatelessWidget {
  final String dersAdi;
  final String durum;
  final bool tcBosMu;
  const _AktifYoklamaKarti({required this.dersAdi, required this.durum, required this.tcBosMu});

  @override
  Widget build(BuildContext context) {
    final config = _durumConfig(durum);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: config.renk.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: config.renk.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: config.renk, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('Aktif Yoklama', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ]),
          const SizedBox(height: 8),
          Text(dersAdi, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(children: [
            Icon(config.ikon, color: config.renk, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tcBosMu ? 'TC kimlik numaranız kayıtlı değil; durum takip edilemiyor.' : config.mesaj,
                style: TextStyle(fontSize: 14, color: config.renk, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  _DurumConf _durumConfig(String d) {
    switch (d) {
      case 'present':    return _DurumConf(Colors.green,  Icons.check_circle,  'Yoklamaya katıldınız ✓');
      case 'face_only':  return _DurumConf(Colors.orange, Icons.face,          'Yüz tanıma tamam — RFID bekleniyor');
      case 'rfid_only':  return _DurumConf(Colors.orange, Icons.credit_card,   'RFID tamam — Yüz tanıma bekleniyor');
      case 'bekliyor':   return _DurumConf(Colors.blue,   Icons.hourglass_top, 'Yoklama başladı — tarama bekleniyor');
      default:           return _DurumConf(Colors.grey,   Icons.hourglass_empty, 'Bekleniyor...');
    }
  }
}

class _DurumConf {
  final Color renk; final IconData ikon; final String mesaj;
  const _DurumConf(this.renk, this.ikon, this.mesaj);
}

// ── Yardımcılar ───────────────────────────────────────────────────────────────

class _BilgiKarti extends StatelessWidget {
  final IconData icon; final Color renk; final String baslik; final String icerik;
  const _BilgiKarti({required this.icon, required this.renk, required this.baslik, required this.icerik});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
    ),
    child: Row(children: [
      Icon(icon, color: renk.withOpacity(0.5), size: 36),
      const SizedBox(width: 14),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(icerik, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      )),
    ]),
  );
}

class _OzetKutu extends StatelessWidget {
  final String deger; final String etiket; final Color renk;
  const _OzetKutu({required this.deger, required this.etiket, required this.renk});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(children: [
      Text(deger, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: renk)),
      Text(etiket, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]),
  );
}
