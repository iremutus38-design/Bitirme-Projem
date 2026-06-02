// idari_panel/yuz_kart_yonetimi.dart
//
// İdari panelden açılan "Yüz & Kart Yönetimi" sayfası.
//
// Her öğrenci satırında:
//   - Yüz durumu rozeti (var/yok)
//   - RFID durumu rozeti (UID veya yok)
//   - "Yüz Tanıt" butonu → Python subprocess'i tetikler
//   - "Kart Bağla" butonu → manuel UID input + Firebase yazma
//
// Hem `users` (kayıt olmuş öğrenciler) hem `on_kayitlar` (henüz kayıt
// olmamış ön kayıt öğrencileri) listelenir. on_kayitlar için anahtar TC,
// users için Firebase UID.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../services/enrollment_service.dart';

// ── RFID Okuyucu IP ayarı ──────────────────────────────────────────────────
// Windows bilgisayarındaki anten sunucusunun IP adresi:
const String _rfidAntenIp = '192.168.137.188';
const int    _rfidAntenPort = 80;

class YuzKartYonetimiSayfasi extends StatefulWidget {
  const YuzKartYonetimiSayfasi({super.key});

  @override
  State<YuzKartYonetimiSayfasi> createState() => _YuzKartYonetimiSayfasiState();
}

class _YuzKartYonetimiSayfasiState extends State<YuzKartYonetimiSayfasi>
    with SingleTickerProviderStateMixin {
  final Color neuColor = const Color(0xFF005A71);
  final EnrollmentService _service = EnrollmentService();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  // {uid_veya_tc: data} formatında öğrenci listesi
  Map<String, Map<String, dynamic>> _users = {};
  Map<String, Map<String, dynamic>> _onKayitlar = {};
  String _filter = "";
  bool _isLoading = true;

  StreamSubscription? _usersSub;
  StreamSubscription? _onKayitSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _baglan();
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _onKayitSub?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _baglan() {
    final db = FirebaseDatabase.instance.ref();
    // Streamleri dinleyerek canlı güncelleme yapıyoruz
    _usersSub = db.child('users').onValue.listen((event) {
      final raw = event.snapshot.value;
      final next = <String, Map<String, dynamic>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map &&
              v['roller'] is Map &&
              (v['roller']['öğrenci'] == true)) {
            next[k.toString()] = Map<String, dynamic>.from(v);
          }
        });
      }
      if (mounted) setState(() {
        _users = next;
        _isLoading = false;
      });
    });

    _onKayitSub = db.child('on_kayitlar').onValue.listen((event) {
      final raw = event.snapshot.value;
      final next = <String, Map<String, dynamic>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) next[k.toString()] = Map<String, dynamic>.from(v);
        });
      }
      if (mounted) setState(() {
        _onKayitlar = next;
      });
    });
  }

  // ---- Filtre ----

  List<MapEntry<String, Map<String, dynamic>>> _filtered(
      Map<String, Map<String, dynamic>> src) {
    if (_filter.isEmpty) return src.entries.toList();
    final q = _filter.toLowerCase();
    return src.entries.where((e) {
      final ad = (e.value['ad_soyad'] ?? '').toString().toLowerCase();
      final tc = (e.value['tc_no'] ?? '').toString();
      final no = (e.value['okul_no'] ?? '').toString();
      return ad.contains(q) || tc.contains(_filter) || no.contains(_filter);
    }).toList();
  }

  // ---- Eylemler ----

  Future<void> _yuzTanit(String uid, String adSoyad) async {
    // Bilgilendirme: Python penceresi açılacak
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Yüz Tanıtma"),
        content: Text(
          "$adSoyad için yüz tanıtma başlatılacak.\n\n"
          "Kamera ayrı bir pencerede açılacak:\n"
          "  • Öğrencinin yüzü kadrajda tek başına olmalı\n"
          "  • SPACE = fotoğrafı çek\n"
          "  • Q veya ESC = iptal\n\n"
          "Hazır mısınız?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: neuColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Başlat", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Çalışıyor diyaloğu
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text("Kamera penceresinde işlem bekleniyor...")),
              ],
            ),
          ),
        ),
      ),
    );

    final result = await _service.enrollFace(uid);
    if (mounted) Navigator.pop(context); // bekleme diyaloğu

    _sonucGoster(result);
  }

  Future<void> _kartBagla(String uid, String adSoyad, String mevcutRfid) async {
    final String? rfid = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RfidOkutmaDialog(adSoyad: adSoyad, mevcutRfid: mevcutRfid),
    );

    if (rfid == null || rfid.isEmpty) return;

    final result = await _service.bindRfidManual(uid, rfid);
    _sonucGoster(result);
  }

  Future<void> _yuzSil(String uid, String adSoyad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Yüz Encoding'i Sil"),
        content: Text("$adSoyad için kayıtlı yüz silinecek. Emin misiniz?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await _service.removeFaceEncoding(uid);
    _sonucGoster(result);
  }

  Future<void> _kartSil(String uid, String adSoyad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("RFID Kartı Kaldır"),
        content: Text("$adSoyad için bağlı kart kaldırılacak. Emin misiniz?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Kaldır", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await _service.unbindRfid(uid);
    _sonucGoster(result);
  }

  void _sonucGoster(EnrollmentResult r) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.message),
        backgroundColor: r.success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Yüz & Kart Yönetimi",
            style: TextStyle(color: Colors.white)),
        backgroundColor: neuColor,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "İsim, TC veya öğrenci no...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: "Kayıtlı (${_users.length})"),
                  Tab(text: "Ön Kayıt (${_onKayitlar.length})"),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_users, isPreReg: false),
                _buildList(_onKayitlar, isPreReg: true),
              ],
            ),
    );
  }

  Widget _buildList(Map<String, Map<String, dynamic>> src,
      {required bool isPreReg}) {
    final liste = _filtered(src);
    if (liste.isEmpty) {
      return const Center(child: Text("Sonuç yok"));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: liste.length,
      itemBuilder: (context, i) {
        final uid = liste[i].key;
        final data = liste[i].value;
        return _buildCard(uid, data, isPreReg);
      },
    );
  }

  Widget _buildCard(String uid, Map<String, dynamic> data, bool isPreReg) {
    final adSoyad = (data['ad_soyad'] ?? "İsimsiz").toString();
    final okulNo = (data['okul_no'] ?? "").toString();
    final tcNo = (data['tc_no'] ?? "").toString();

    final hasFace = data['face_encoding'] != null;
    final rfid = (data['rfid_uid'] ?? "").toString();
    final hasRfid = rfid.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      hasFace && hasRfid ? Colors.green : neuColor,
                  child: Text(
                    adSoyad.isNotEmpty ? adSoyad[0].toUpperCase() : "?",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(adSoyad,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        [if (okulNo.isNotEmpty) "No: $okulNo",
                         if (tcNo.isNotEmpty) "TC: $tcNo",
                         if (isPreReg) "(Ön Kayıt)"].join("  "),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                _rozet("Yüz", hasFace),
                const SizedBox(width: 6),
                _rozet("Kart", hasRfid, valueText: hasRfid ? rfid : null),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(hasFace ? Icons.refresh : Icons.face),
                    label: Text(hasFace ? "Yüzü Yenile" : "Yüz Tanıt"),
                    onPressed: () => _yuzTanit(uid, adSoyad),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.nfc),
                    label: Text(hasRfid ? "Kartı Değiştir" : "Kart Bağla"),
                    onPressed: () => _kartBagla(uid, adSoyad, rfid),
                  ),
                ),
                if (hasFace || hasRfid)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (val) {
                      if (val == "del_face") _yuzSil(uid, adSoyad);
                      if (val == "del_rfid") _kartSil(uid, adSoyad);
                    },
                    itemBuilder: (ctx) => [
                      if (hasFace)
                        const PopupMenuItem(
                          value: "del_face",
                          child: Text("Yüzü Sil",
                              style: TextStyle(color: Colors.red)),
                        ),
                      if (hasRfid)
                        const PopupMenuItem(
                          value: "del_rfid",
                          child: Text("Kartı Kaldır",
                              style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rozet(String label, bool ok, {String? valueText}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ok ? Colors.green.shade300 : Colors.red.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check : Icons.close,
              size: 12, color: ok ? Colors.green : Colors.red),
          const SizedBox(width: 3),
          Text(
            valueText ?? label,
            style: TextStyle(
              fontSize: 10,
              color: ok ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// RFID kart okutma dialog'u.
/// rfid_events/ Firebase path'ini dinler — Windows'taki anten scripti oraya yazar.
class _RfidOkutmaDialog extends StatefulWidget {
  final String adSoyad;
  final String mevcutRfid;
  const _RfidOkutmaDialog({required this.adSoyad, this.mevcutRfid = ''});

  @override
  State<_RfidOkutmaDialog> createState() => _RfidOkutmaDialogState();
}

class _RfidOkutmaDialogState extends State<_RfidOkutmaDialog> {
  static const Color _neu = Color(0xFF005A71);

  String _durum   = 'Kartı antene tutun...';
  String _bulunan = '';

  StreamSubscription? _sub;

  // Manuel giriş fallback
  final _manuelCtrl = TextEditingController();
  bool _manuelMod   = false;

  @override
  void initState() {
    super.initState();
    // Zaten kayıtlı kart varsa direkt göster
    if (widget.mevcutRfid.isNotEmpty) {
      _bulunan = widget.mevcutRfid;
      _durum   = 'Mevcut kart';
    } else {
      _baslat();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _manuelCtrl.dispose();
    super.dispose();
  }

  void _baslat() {
    // rfid_events altına yeni eklenen kayıtları dinle
    _sub = FirebaseDatabase.instance
        .ref('rfid_events')
        .orderByChild('consumed')
        .equalTo(false)
        .onChildAdded
        .listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data is! Map) return;
      final uid = data['uid']?.toString().toUpperCase() ?? '';
      if (uid.isEmpty) return;
      // Consumed olarak işaretle
      event.snapshot.ref.update({'consumed': true});
      setState(() {
        _bulunan = uid;
        _durum   = 'Kart okundu!';
      });
      _sub?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.nfc, color: _neu),
        const SizedBox(width: 8),
        Expanded(child: Text('${widget.adSoyad} — Kart Bağla',
            style: const TextStyle(fontSize: 15))),
      ]),
      content: SizedBox(
        width: 320,
        child: _manuelMod ? _manuelWidget() : _taramaWidget(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _taramaWidget() {
    final bulundu = _bulunan.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animasyon / ikon
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: bulundu ? Colors.green.shade50 : _neu.withOpacity(0.07),
            shape: BoxShape.circle,
          ),
          child: bulundu
              ? const Icon(Icons.check_circle, color: Colors.green, size: 48)
              : const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
        ),
        const SizedBox(height: 16),
        Text(_durum,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: bulundu ? Colors.green.shade700 : Colors.grey.shade700)),
        if (bulundu) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.credit_card, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Text(_bulunan,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      letterSpacing: 2, color: Colors.green)),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() { _manuelMod = true; _sub?.cancel(); }),
          child: const Text('Manuel giriş', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _manuelWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('RFID UID\'sini manuel girin:', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 10),
        TextField(
          controller: _manuelCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'Örn: A4B72F19',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.nfc),
          ),
          onChanged: (v) => setState(() => _bulunan = v.trim().toUpperCase()),
        ),
        TextButton(
          onPressed: () => setState(() {
            _manuelMod = false;
            _bulunan = '';
            _baslat();
          }),
          child: const Text('Okutarak bağla', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context, null),
        child: const Text('İptal'),
      ),
      ElevatedButton.icon(
        icon: const Icon(Icons.save, size: 16),
        label: const Text('Kaydet'),
        style: ElevatedButton.styleFrom(
            backgroundColor: _neu, foregroundColor: Colors.white),
        onPressed: _bulunan.isEmpty ? null : () {
          Navigator.pop(context, _bulunan);
        },
      ),
    ];
  }
}
