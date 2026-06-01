// akademisyen_panel.dart

import 'package:bitirme_projesi/Akademisyen_panel/AkademisyenProfil.dart';
import 'package:bitirme_projesi/Akademisyen_panel/sinav_bildirim_sayfasi.dart';
import 'package:bitirme_projesi/Akademisyen_panel/verilen_ders_detay.dart';
import 'package:bitirme_projesi/Akademisyen_panel/yoklama_sayfasi.dart';
import 'package:bitirme_projesi/services/rest_auth_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class AkademisyenPanel extends StatelessWidget {
  const AkademisyenPanel({super.key});

  static const Color _neu = Color(0xFF005A71);

  @override
  Widget build(BuildContext context) {
    final uid = RestAuthService.instance.currentUid ?? '';

    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref().child('academic_users/$uid').onValue,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData || snap.data!.snapshot.value == null) {
          return const Scaffold(
              body: Center(child: Text('Kullanıcı verisi bulunamadı.')));
        }

        final userData = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        // adSoyad already contains unvan prefix in Firebase (e.g. "Doç.Dr. FİKRİ KÖKEN")
        final adSoyad = userData['ad_soyad']?.toString() ?? 'Akademisyen';
        final email   = userData['email']?.toString() ?? '';
        final unvan   = userData['unvan']?.toString() ?? '';

        // Parse helper: handles List/Map from Firebase; items can be Map OR plain String
        void ekle(dynamic raw, List<Map<String, dynamic>> hedef) {
          void add(dynamic d) {
            if (d is Map) {
              hedef.add(Map<String, dynamic>.from(d));
            } else if (d is String && d.trim().isNotEmpty) {
              hedef.add({'ad': d.trim()});
            }
          }
          if (raw is List) {
            for (final d in raw) add(d);
          } else if (raw is Map) {
            for (final d in raw.values) add(d);
          }
        }

        // verilen_dersler: Excel courses (gun="-", no schedule)
        final List<Map<String, dynamic>> dersler = [];
        ekle(userData['verilen_dersler'], dersler);

        // ders_programi: admin-assigned schedule with day/time
        final List<Map<String, dynamic>> desProgrami = [];
        ekle(userData['ders_programi'], desProgrami);

        return Scaffold(
          backgroundColor: const Color(0xFFF4F6F9),
          appBar: AppBar(
            title: const Text('Akademisyen Paneli',
                style: TextStyle(color: Colors.white, fontSize: 17)),
            backgroundColor: _neu,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          drawer: _Drawer(adSoyad: adSoyad, email: email, unvan: unvan),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              // ── Welcome card ──
              _HosgeldinKarti(adSoyad: adSoyad),
              const SizedBox(height: 16),

              // ── Upcoming exam alerts ──
              _SinavUyari(hocaAdSoyad: adSoyad),

              // ── Ders Programım (unified, with today highlights) ──
              _DersProgramiSection(
                hocaAdSoyad: adSoyad,
                desProgrami: desProgrami,
              ),
              const SizedBox(height: 20),

            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────────────────────────────
/// Section header with accent bar
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color color;
  const _SectionHeader({required this.title, this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(width: 4, height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          )),
      const SizedBox(width: 10),
      Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2A3A))),
      if (subtitle != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(subtitle!,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    ],
  );
}

// ───────────────────────────────────────────────
/// Unified Ders Programım — shows admin-assigned courses.
/// Today's courses get a highlighted "Bugün" badge and are placed first.
class _DersProgramiSection extends StatelessWidget {
  final String hocaAdSoyad;
  final List<Map<String, dynamic>> desProgrami;

  const _DersProgramiSection({
    required this.hocaAdSoyad,
    required this.desProgrami,
  });

  static const List<String> _gunSirasi = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];

  static const List<String> _gunlerMap = [
    '', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];

  String get _bugunAdi => _gunlerMap[DateTime.now().weekday];

  @override
  Widget build(BuildContext context) {
    if (desProgrami.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionHeader(
          title: 'Ders Programım',
          color: Colors.teal,
        ),
        const SizedBox(height: 10),
        _EmptyCard(
          icon: Icons.calendar_today_outlined,
          message: 'Henüz ders programı atanmadı.\nİdari panel üzerinden atama yapılabilir.',
        ),
        const SizedBox(height: 8),
      ]);
    }

    // Separate today vs other days
    final bugun = desProgrami.where((d) => d['gun']?.toString() == _bugunAdi).toList();
    final diger = desProgrami.where((d) => d['gun']?.toString() != _bugunAdi).toList();

    // Sort other days by weekday order then time
    diger.sort((a, b) {
      final ai = _gunSirasi.indexOf(a['gun']?.toString() ?? '');
      final bi = _gunSirasi.indexOf(b['gun']?.toString() ?? '');
      if (ai != bi) return ai.compareTo(bi);
      return _dakika(a['saat']).compareTo(_dakika(b['saat']));
    });
    bugun.sort((a, b) => _dakika(a['saat']).compareTo(_dakika(b['saat'])));

    final allSorted = [...bugun, ...diger];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Ders Programım',
          subtitle: '${desProgrami.length} ders',
          color: Colors.teal,
        ),
        const SizedBox(height: 10),
        ...allSorted.map((ders) => _ProgramDersKarti(
              ders: ders,
              isToday: ders['gun']?.toString() == _bugunAdi,
              hocaAdSoyad: hocaAdSoyad,
            )),
        const SizedBox(height: 4),
      ],
    );
  }

  int _dakika(String? saat) {
    if (saat == null) return 0;
    final parts = saat.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}

// ───────────────────────────────────────────────
class _ProgramDersKarti extends StatelessWidget {
  final Map<String, dynamic> ders;
  final bool isToday;
  final String hocaAdSoyad;
  const _ProgramDersKarti({
    required this.ders,
    required this.isToday,
    required this.hocaAdSoyad,
  });

  static const Color _neu = Color(0xFF005A71);

  bool get _aktifMi {
    if (!isToday) return false;
    final saat = ders['saat']?.toString() ?? '';
    final parts = saat.split(':');
    if (parts.length < 2) return false;
    final dersMin = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    return (nowMin - dersMin).abs() <= 90;
  }

  @override
  Widget build(BuildContext context) {
    final ad      = ders['ad']?.toString() ?? '';
    final gun     = ders['gun']?.toString() ?? '-';
    final saat    = ders['saat']?.toString() ?? '-';
    final derslik = ders['derslik']?.toString() ?? '';
    final aktif   = _aktifMi;

    final cardColor = aktif
        ? Colors.teal.shade50
        : isToday
            ? Colors.blue.shade50
            : Colors.white;
    final borderColor = aktif
        ? Colors.teal.shade300
        : isToday
            ? Colors.blue.shade200
            : Colors.transparent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => YoklamaSayfasi(
              dersAdi: ad,
              derslik: derslik,
              saat: saat,
              gun: gun,
              hocaAdSoyad: hocaAdSoyad,
            ),
          )),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Icon container
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: aktif
                      ? Colors.teal.withOpacity(0.15)
                      : isToday
                          ? Colors.blue.withOpacity(0.12)
                          : _neu.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  aktif ? Icons.how_to_reg : Icons.menu_book,
                  color: aktif ? Colors.teal : isToday ? Colors.blue : _neu,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Ders bilgisi
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ad,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14,
                          color: Color(0xFF1A2A3A))),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 11,
                        color: isToday ? Colors.blue.shade600 : Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(gun,
                        style: TextStyle(
                            fontSize: 12,
                            color: isToday ? Colors.blue.shade700 : Colors.grey.shade600,
                            fontWeight: isToday ? FontWeight.w600 : FontWeight.normal)),
                    const SizedBox(width: 8),
                    Icon(Icons.access_time,
                        size: 11, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(saat,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                    if (derslik.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.room, size: 11, color: Colors.grey.shade400),
                      const SizedBox(width: 2),
                      Flexible(child: Text(derslik,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis)),
                    ],
                  ]),
                ],
              )),

              // Badge
              if (aktif)
                _Badge(label: 'Şu an', color: Colors.teal)
              else if (isToday)
                _Badge(label: 'Bugün', color: Colors.blue)
              else
                const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

// ───────────────────────────────────────────────
/// Excel course card — no day/time info, just name + detail link
class _ExcelDersKarti extends StatelessWidget {
  final Map<String, dynamic> ders;
  final VoidCallback onTap;
  const _ExcelDersKarti({required this.ders, required this.onTap});

  static const Color _neu = Color(0xFF005A71);

  @override
  Widget build(BuildContext context) {
    final ad = ders['ad']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _neu.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.book_outlined, color: _neu, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(ad,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13,
                      color: Color(0xFF1A2A3A)))),
              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────
class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
      ],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 40, color: Colors.grey.shade300),
      const SizedBox(height: 10),
      Text(message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ]),
  );
}

// ───────────────────────────────────────────────
class _HosgeldinKarti extends StatelessWidget {
  // adSoyad already has unvan prefix stored in Firebase (e.g. "Doç.Dr. FİKRİ KÖKEN")
  final String adSoyad;
  const _HosgeldinKarti({required this.adSoyad});

  @override
  Widget build(BuildContext context) {
    final now  = DateTime.now();
    final saat = now.hour;
    final selam = saat >= 6 && saat < 12
        ? 'Günaydın'
        : saat < 18
            ? 'İyi günler'
            : saat < 22
                ? 'İyi akşamlar'
                : 'İyi geceler';
    const aylar = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];

    const gunAdi = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
    final tarih = '${gunAdi[now.weekday - 1]}, ${now.day} ${aylar[now.month - 1]} ${now.year}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF005A71), Color(0xFF00A99D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF005A71).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.school, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$selam,',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 2),
            Text(adSoyad,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.calendar_today, size: 11, color: Colors.white60),
              const SizedBox(width: 5),
              Text(tarih, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ],
        )),
      ]),
    );
  }
}

// ───────────────────────────────────────────────
class _Drawer extends StatelessWidget {
  final String adSoyad;
  final String email;
  final String unvan;
  const _Drawer({required this.adSoyad, required this.email, required this.unvan});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        UserAccountsDrawerHeader(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF005A71), Color(0xFF00A99D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          accountName: Text(adSoyad,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          accountEmail: Text(email),
          currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Color(0xFF005A71), size: 28)),
        ),
        ListTile(
          leading: const Icon(Icons.person_outline, color: Color(0xFF005A71)),
          title: const Text('Profilim'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AkademisyenProfil()));
          },
        ),
        ListTile(
          leading: const Icon(Icons.assignment_outlined, color: Color(0xFF005A71)),
          title: const Text('Sınavlarım'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => SinavBildirimSayfasi(hocaAdSoyad: adSoyad)));
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Çıkış Yap', style: TextStyle(color: Colors.redAccent)),
          onTap: () async {
            Navigator.pop(context);
            await RestAuthService.instance.signOut();
          },
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────
/// Upcoming exam alert strip — shows exams within 14 days
class _SinavUyari extends StatefulWidget {
  final String hocaAdSoyad;
  const _SinavUyari({required this.hocaAdSoyad});
  @override
  State<_SinavUyari> createState() => _SinavUyariState();
}

class _SinavUyariState extends State<_SinavUyari> {
  List<Map<String, String>> _yaklasan = [];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  static const _unvanlar = {'prof', 'doc', 'doç', 'yrd', 'ogr', 'öğr',
      'gor', 'gör', 'uzm', 'uyesi', 'üyesi', 'dr'};

  Set<String> _isimKelimeleri(String s) => s
      .toLowerCase().replaceAll('.', ' ').split(' ')
      .where((k) => k.length > 2 && !_unvanlar.contains(k)).toSet();

  bool _hocaEslesiyor(String s) {
    final hedef = _isimKelimeleri(widget.hocaAdSoyad);
    final kaynak = _isimKelimeleri(s);
    if (hedef.isEmpty || kaynak.isEmpty) return false;
    final ortak = hedef.intersection(kaynak);
    return ortak.length >= 2 || (hedef.length == 1 && ortak.length == 1);
  }

  Future<void> _yukle() async {
    final snap = await FirebaseDatabase.instance.ref('sinav_takvimi').get();
    if (!snap.exists || snap.value is! Map) return;
    final liste = <Map<String, String>>[];
    (snap.value as Map).forEach((kod, val) {
      if (val is! Map) return;
      if (!_hocaEslesiyor(val['hoca_adi']?.toString() ?? '')) return;
      final tarihStr = val['tarih']?.toString() ?? '';
      DateTime? tarih;
      try {
        final p = tarihStr.split(RegExp(r'[-.]'));
        if (p.length == 3) {
          tarih = p[0].length == 4
              ? DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))
              : DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
        }
      } catch (_) {}
      if (tarih == null) return;
      final fark = tarih.difference(DateTime.now()).inDays;
      if (fark >= 0 && fark <= 14) {
        liste.add({
          'ad': val['ders_adi']?.toString() ?? kod.toString(),
          'tarih': tarihStr,
          'saat': val['saat']?.toString() ?? '',
          'fark': '$fark',
        });
      }
    });
    liste.sort((a, b) => a['tarih']!.compareTo(b['tarih']!));
    if (mounted) setState(() => _yaklasan = liste);
  }

  @override
  Widget build(BuildContext context) {
    if (_yaklasan.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(children: [
              const Icon(Icons.event_note, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text('${_yaklasan.length} Yaklaşan Sınav',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.orange)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SinavBildirimSayfasi(hocaAdSoyad: widget.hocaAdSoyad))),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Tümünü gör →',
                    style: TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            ]),
          ),
          // Divider
          Divider(height: 1, color: Colors.orange.shade100),
          // Exam rows
          ..._yaklasan.map((s) {
            final fark = int.tryParse(s['fark'] ?? '99') ?? 99;
            final renk = fark == 0
                ? Colors.red
                : fark <= 3
                    ? Colors.deepOrange
                    : fark <= 7
                        ? Colors.orange
                        : Colors.amber.shade700;
            final label = fark == 0 ? 'Bugün!' : fark == 1 ? 'Yarın' : '$fark gün';
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s['ad']!,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2A3A)))),
                const SizedBox(width: 8),
                Text(s['tarih']!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: renk.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11, color: renk, fontWeight: FontWeight.bold)),
                ),
              ]),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
