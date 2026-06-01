import 'package:bitirme_projesi/Akademisyen_panel/verilen_ders_detay.dart';
import 'package:bitirme_projesi/services/rest_auth_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const Color _neu = Color(0xFF005A71);

class AkademisyenProfil extends StatelessWidget {
  const AkademisyenProfil({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = RestAuthService.instance.currentUid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Profilim',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _neu,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder(
        stream: FirebaseDatabase.instance.ref('academic_users/$uid').onValue,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _neu));
          }
          if (!snap.hasData || snap.data!.snapshot.value == null) {
            return const Center(child: Text('Kullanıcı verisi bulunamadı.'));
          }

          final data = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
          final adSoyad = data['ad_soyad']?.toString() ?? '—';
          final unvan   = data['unvan']?.toString() ?? '';
          final email   = data['email']?.toString() ?? '';

          // verilen_dersler — string veya Map olabilir
          final List<String> verilenDersler = [];
          final raw = data['verilen_dersler'];
          void parseV(dynamic r) {
            if (r is List) {
              for (final d in r) {
                if (d is String && d.isNotEmpty) verilenDersler.add(d);
                else if (d is Map) {
                  final ad = d['ad']?.toString() ?? d['ders_adi']?.toString() ?? '';
                  if (ad.isNotEmpty) verilenDersler.add(ad);
                }
              }
            } else if (r is Map) {
              for (final d in r.values) {
                if (d is String && d.isNotEmpty) verilenDersler.add(d);
                else if (d is Map) {
                  final ad = d['ad']?.toString() ?? d['ders_adi']?.toString() ?? '';
                  if (ad.isNotEmpty) verilenDersler.add(ad);
                }
              }
            }
          }
          parseV(raw);

          // ders_programi — admin tarafından atanan çizelge
          final List<Map<String, dynamic>> desProgrami = [];
          void parseP(dynamic r) {
            if (r is List) {
              for (final d in r) { if (d is Map) desProgrami.add(Map<String, dynamic>.from(d)); }
            } else if (r is Map) {
              for (final d in r.values) { if (d is Map) desProgrami.add(Map<String, dynamic>.from(d)); }
            }
          }
          parseP(data['ders_programi']);

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // ── Profil başlığı ──
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF005A71), Color(0xFF00A99D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(36),
                      bottomRight: Radius.circular(36),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 36, 24, 30),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: Text(
                        adSoyad.isNotEmpty ? adSoyad.split(' ').last[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 38, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(adSoyad,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    if (unvan.isNotEmpty)
                      Text(unvan,
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                  ]),
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
                        if (email.isNotEmpty)
                          _InfoSatir(Icons.email_outlined, 'E-posta', email),
                      ]),

                      // ── Ders programı ──
                      if (desProgrami.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _SectionHeader('Ders Programım (${desProgrami.length})'),
                        const SizedBox(height: 10),
                        ...desProgrami.map((d) => _DersKarti(
                          ad: d['ad']?.toString() ?? '—',
                          gun: d['gun']?.toString() ?? '',
                          saat: d['saat']?.toString() ?? '',
                          derslik: d['derslik']?.toString() ?? '',
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => DersDetaySayfasi(
                              dersAdi: d['ad']?.toString() ?? '',
                              hocaAdSoyad: adSoyad,
                            ),
                          )),
                        )),
                      ],

                      // ── Şifre değiştir ──
                      const SizedBox(height: 22),
                      _SectionHeader('Güvenlik'),
                      const SizedBox(height: 10),
                      _SifreDegistirKarti(),

                      // ── Tüm dersler (verilen_dersler) ──
                      const SizedBox(height: 22),
                      _SectionHeader('Verdiğim Dersler (${verilenDersler.length})'),
                      const SizedBox(height: 10),
                      if (verilenDersler.isEmpty)
                        _InfoKarti(children: const [
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Henüz ders kaydı bulunamadı.',
                                style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ),
                        ])
                      else
                        ...verilenDersler.toSet().map((dersAdi) => _DersKarti(
                          ad: dersAdi,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => DersDetaySayfasi(
                              dersAdi: dersAdi,
                              hocaAdSoyad: adSoyad,
                            ),
                          )),
                        )),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Yardımcı ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: _neu));
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
          Text('$etiket: ', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Expanded(
              child: Text(deger,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
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
  final _eskiCtrl  = TextEditingController();
  final _yeniCtrl  = TextEditingController();
  final _tekrarCtrl = TextEditingController();
  bool _eskiGizli  = true;
  bool _yeniGizli  = true;
  bool _yukleniyor = false;
  bool _acik       = false; // form görünür mü?

  static const String _apiKey = 'AIzaSyDDnN0Km9HMc2D2jl9IWuKGztaT8LW5-V0';

  @override
  void dispose() {
    _eskiCtrl.dispose();
    _yeniCtrl.dispose();
    _tekrarCtrl.dispose();
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

      // 1. Eski şifreyle giriş yaparak doğrula
      final dogrulaResp = await http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': eski, 'returnSecureToken': true}),
      );

      if (dogrulaResp.statusCode != 200) {
        _snack('Mevcut şifre yanlış.', Colors.red); return;
      }

      final idToken = jsonDecode(dogrulaResp.body)['idToken'];

      // 2. Şifreyi güncelle
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
      SnackBar(content: Text(msg), backgroundColor: renk, behavior: SnackBarBehavior.floating),
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
      child: Column(
        children: [
          // ── Buton satırı ──
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.lock_outline, color: _neu),
            title: const Text('Şifre Değiştir',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: Icon(_acik ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
            onTap: () => setState(() => _acik = !_acik),
          ),

          // ── Form (açılır/kapanır) ──
          if (_acik) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                children: [
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
                ],
              ),
            ),
          ],
        ],
      ),
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
              onPressed: onToggle,
            )
          : null,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _DersKarti extends StatelessWidget {
  final String ad;
  final String gun;
  final String saat;
  final String derslik;
  final VoidCallback onTap;

  const _DersKarti({
    required this.ad,
    this.gun = '',
    this.saat = '',
    this.derslik = '',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final altBaslik = [gun, saat, derslik]
        .where((s) => s.isNotEmpty && s != '-')
        .join('  •  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5)],
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: _neu.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.menu_book, color: _neu, size: 20),
        ),
        title: Text(ad,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: altBaslik.isNotEmpty
            ? Text(altBaslik, style: const TextStyle(fontSize: 11, color: Colors.grey))
            : null,
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
