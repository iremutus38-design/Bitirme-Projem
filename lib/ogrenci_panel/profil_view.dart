// ogrenci_panel/profil_view.dart
//
// Öğrencinin profil sayfası.
//   - Ad soyad, öğrenci no, bölüm, e-posta
//   - Alınan dersler listesi
//   - OBS ve e-devlet öğrenci belgesi bağlantıları

import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/rest_auth_service.dart';

const Color _neu = Color(0xFF005A71);

class ProfilView extends StatelessWidget {
  const ProfilView({super.key});

  Future<void> _linkAc(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Açılamadı: $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = RestAuthService.instance.currentUid ?? '';
    final email = RestAuthService.instance.currentEmail ?? '';

    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref('on_kayitlar').orderByChild('uid').equalTo(uid).onValue,
      builder: (context, onKayitSnap) {
        // on_kayitlar'dan alinan_dersler'i bul
        List<Map> onKayitDersler = [];
        if (onKayitSnap.hasData && onKayitSnap.data!.snapshot.value is Map) {
          (onKayitSnap.data!.snapshot.value as Map).forEach((_, val) {
            if (val is Map) {
              final raw = val['alinan_dersler'];
              if (raw is List) onKayitDersler = raw.whereType<Map>().toList();
            }
          });
        }
        return StreamBuilder(
      stream: FirebaseDatabase.instance.ref('users/$uid').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Veri alınamadı'));
        }
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: CircularProgressIndicator(color: _neu));
        }

        final data = Map<String, dynamic>.from(
            snapshot.data!.snapshot.value as Map);
        final adSoyad = data['ad_soyad']?.toString() ?? '—';
        final okulNo = data['okul_no']?.toString() ?? '—';
        final bolum = data['bolum']?.toString() ?? '';
        final tc = data['tc']?.toString() ?? '';

        // on_kayitlar verisi varsa onu kullan, yoksa users verisine düş
        final derslerRaw = data['alinan_dersler'];
        final dersler = onKayitDersler.isNotEmpty
            ? onKayitDersler
            : (derslerRaw is List ? derslerRaw.whereType<Map>().toList() : <Map>[]);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              // ── Profil başlığı ──
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF005A71), Color(0xFF007A98)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 30),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: Text(
                        adSoyad.isNotEmpty ? adSoyad[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 38,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      adSoyad,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    if (bolum.isNotEmpty)
                      Text(bolum,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13)),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Kişisel bilgiler ──
                    _SectionHeader('Kişisel Bilgiler'),
                    const SizedBox(height: 10),
                    _InfoKarti(children: [
                      _InfoSatir(Icons.badge_outlined, 'Öğrenci No', okulNo),
                      if (email.isNotEmpty)
                        _InfoSatir(Icons.email_outlined, 'E-posta', email),
                      if (tc.isNotEmpty)
                        _InfoSatir(Icons.fingerprint, 'TC', tc),
                    ]),

                    const SizedBox(height: 20),

                    // ── Şifre değiştir ──
                    const SizedBox(height: 20),
                    const _SifreDegistirKarti(),

                    // ── Hızlı bağlantılar ──
                    _SectionHeader('Bağlantılar'),
                    const SizedBox(height: 10),
                    _LinkButon(
                      baslik: 'NEÜ ÖBS Sistemi',
                      ikon: Icons.account_balance_outlined,
                      url: 'https://obs.erbakan.edu.tr',
                      onTap: _linkAc,
                    ),
                    const SizedBox(height: 8),
                    _LinkButon(
                      baslik: 'E-Devlet Öğrenci Belgesi',
                      ikon: Icons.assignment_turned_in_outlined,
                      url: 'https://www.turkiye.gov.tr/yok-ogrenci-belgesi-sorgulama',
                      onTap: _linkAc,
                    ),

                    const SizedBox(height: 20),

                    // ── Alınan dersler ──
                    _SectionHeader('Alınan Dersler (${dersler.length})'),
                    const SizedBox(height: 10),
                    if (dersler.isEmpty)
                      const _InfoKarti(children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Kayıtlı ders bulunamadı.',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      ])
                    else
                      ...dersler.map((ders) {
                        final dersAdi = ders['ders_adi']?.toString() ?? '—';
                        final hoca = ders['hoca_adi']?.toString() ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 5)
                            ],
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: _neu.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.menu_book,
                                  color: _neu, size: 20),
                            ),
                            title: Text(dersAdi,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: hoca.isNotEmpty
                                ? Text(hoca,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey))
                                : null,
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
      }, // outer StreamBuilder builder end
    );   // outer StreamBuilder end
  }
}

// ── Yardımcı ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String baslik;
  const _SectionHeader(this.baslik);

  @override
  Widget build(BuildContext context) => Text(
        baslik,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: _neu),
      );
}

class _InfoKarti extends StatelessWidget {
  final List<Widget> children;
  const _InfoKarti({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _InfoSatir extends StatelessWidget {
  final IconData ikon;
  final String etiket;
  final String deger;
  const _InfoSatir(this.ikon, this.etiket, this.deger);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(ikon, size: 18, color: _neu.withOpacity(0.7)),
          const SizedBox(width: 12),
          Text('$etiket: ',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Expanded(
              child: Text(deger,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );
}

// ── Şifre Değiştir ────────────────────────────────────────────────────────────

class _SifreDegistirKarti extends StatefulWidget {
  const _SifreDegistirKarti();
  @override
  State<_SifreDegistirKarti> createState() => _SifreDegistirKartiState();
}

class _SifreDegistirKartiState extends State<_SifreDegistirKarti> {
  final _eskiCtrl   = TextEditingController();
  final _yeniCtrl   = TextEditingController();
  final _tekrarCtrl = TextEditingController();
  bool _eskiGizli  = true;
  bool _yeniGizli  = true;
  bool _yukleniyor = false;
  bool _acik       = false;

  static const String _apiKey = 'AIzaSyDDnN0Km9HMc2D2jl9IWuKGztaT8LW5-V0';

  @override
  void dispose() {
    _eskiCtrl.dispose(); _yeniCtrl.dispose(); _tekrarCtrl.dispose();
    super.dispose();
  }

  Future<void> _sifreDegistir() async {
    final eski   = _eskiCtrl.text.trim();
    final yeni   = _yeniCtrl.text.trim();
    final tekrar = _tekrarCtrl.text.trim();

    if (eski.isEmpty || yeni.isEmpty || tekrar.isEmpty) {
      _snack('Tüm alanları doldurun.', Colors.orange); return;
    }
    if (yeni.length < 6) {
      _snack('Yeni şifre en az 6 karakter olmalı.', Colors.orange); return;
    }
    if (yeni != tekrar) {
      _snack('Yeni şifreler eşleşmiyor.', Colors.orange); return;
    }

    setState(() => _yukleniyor = true);
    try {
      final email = RestAuthService.instance.currentEmail ?? '';
      final dogrulaResp = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': eski, 'returnSecureToken': true}),
      );
      if (dogrulaResp.statusCode != 200) {
        _snack('Mevcut şifre yanlış.', Colors.red); return;
      }
      final idToken = jsonDecode(dogrulaResp.body)['idToken'];
      final guncelleResp = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:update?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken, 'password': yeni, 'returnSecureToken': true}),
      );
      if (guncelleResp.statusCode == 200) {
        _eskiCtrl.clear(); _yeniCtrl.clear(); _tekrarCtrl.clear();
        setState(() => _acik = false);
        _snack('Şifre başarıyla güncellendi.', Colors.green);
      } else {
        final msg = jsonDecode(guncelleResp.body)['error']?['message'] ?? 'Hata';
        _snack('Güncelleme başarısız: $msg', Colors.red);
      }
    } catch (e) {
      _snack('Bağlantı hatası: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _snack(String msg, Color renk) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: renk, behavior: SnackBarBehavior.fixed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(children: [
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: const Icon(Icons.lock_outline, color: _neu),
          title: const Text('Şifre Değiştir',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          trailing: Icon(_acik ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
          onTap: () => setState(() => _acik = !_acik),
        ),
        if (_acik) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(children: [
              _SifreAlani(ctrl: _eskiCtrl, etiket: 'Mevcut şifre',
                  gizli: _eskiGizli, onToggle: () => setState(() => _eskiGizli = !_eskiGizli)),
              const SizedBox(height: 12),
              _SifreAlani(ctrl: _yeniCtrl, etiket: 'Yeni şifre',
                  gizli: _yeniGizli, onToggle: () => setState(() => _yeniGizli = !_yeniGizli)),
              const SizedBox(height: 12),
              _SifreAlani(ctrl: _tekrarCtrl, etiket: 'Yeni şifre (tekrar)',
                  gizli: _yeniGizli, onToggle: null),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _yukleniyor ? null : _sifreDegistir,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _neu,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _yukleniyor
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Güncelle', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _SifreAlani extends StatelessWidget {
  final TextEditingController ctrl;
  final String etiket;
  final bool gizli;
  final VoidCallback? onToggle;
  const _SifreAlani({required this.ctrl, required this.etiket, required this.gizli, required this.onToggle});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    obscureText: gizli,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      labelText: etiket,
      labelStyle: const TextStyle(fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      suffixIcon: onToggle != null
          ? IconButton(
              icon: Icon(gizli ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: onToggle)
          : null,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _LinkButon extends StatelessWidget {
  final String baslik;
  final IconData ikon;
  final String url;
  final Future<void> Function(String) onTap;
  const _LinkButon(
      {required this.baslik,
      required this.ikon,
      required this.url,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 0.5,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(url),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              Icon(ikon, color: _neu, size: 22),
              const SizedBox(width: 14),
              Expanded(
                  child: Text(baslik,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14))),
              const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
            ]),
          ),
        ),
      );
}
