// yoklama_sayfasi.dart
//
// Akademisyen bir derse tıkladığında açılır.
// - on_kayitlar'dan dersi alan öğrencileri listeler
// - "Yoklama Başlat" → attendance_sessions'a yeni session yazar
// - Python (attend.py) bu session'ı görüp yüz/RFID taramasını başlatır
// - records/{tc} → face_ok / rfid_ok / final_status → gerçek zamanlı güncelleme
// - "Yoklama Bitir" → session'ı kapatır

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../services/rest_auth_service.dart';

class YoklamaSayfasi extends StatefulWidget {
  final String dersAdi;
  final String derslik;
  final String saat;
  final String gun;
  final String hocaAdSoyad;

  const YoklamaSayfasi({
    super.key,
    required this.dersAdi,
    required this.derslik,
    required this.saat,
    required this.gun,
    required this.hocaAdSoyad,
  });

  @override
  State<YoklamaSayfasi> createState() => _YoklamaSayfasiState();
}

class _YoklamaSayfasiState extends State<YoklamaSayfasi> {
  static const Color _neu = Color(0xFF005A71);

  String? _sessionId;
  bool _aktif = false;
  bool _yukleniyor = true;
  StreamSubscription? _recordsSub;
  Timer? _countdownTimer;
  int _dakikaKaldi = 9999; // ders saatine kaç dakika kaldı

  // TC → _OgrenciDurum
  final Map<String, _OgrenciDurum> _ogrenciler = {};

  @override
  void initState() {
    super.initState();
    _ogrencileriYukle();
    _hesaplaDakikaKaldi();
    // Her dakika güncelle
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _hesaplaDakikaKaldi());
    });
  }

  @override
  void dispose() {
    _recordsSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _hesaplaDakikaKaldi() {
    // widget.saat "09:00" veya "09:00 - 11:00" formatında olabilir
    final saatStr = widget.saat.split('-').first.trim();
    final parts = saatStr.split(':');
    if (parts.length < 2) { _dakikaKaldi = 9999; return; }
    final dersMin = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    _dakikaKaldi = dersMin - nowMin;
  }

  Future<void> _ogrencileriYukle() async {
    final snap =
        await FirebaseDatabase.instance.ref('on_kayitlar').get();

    if (snap.exists && snap.value is Map) {
      (snap.value as Map).forEach((tc, val) {
        if (val is! Map) return;
        final data = Map<String, dynamic>.from(val as Map);
        final derslerRaw = data['alinan_dersler'];
        if (derslerRaw is! List) return;

        for (final d in derslerRaw) {
          if (d is! Map) continue;
          final ad = d['ders_adi']?.toString().trim() ?? '';
          if (_dersEslesiyor(ad)) {
            _ogrenciler[tc.toString()] = _OgrenciDurum(
              tc: tc.toString(),
              adSoyad: data['ad_soyad']?.toString() ?? 'İsimsiz',
              okulNo: data['okul_no']?.toString() ?? '-',
              durum: 'bekliyor',
            );
            break;
          }
        }
      });
    }

    if (mounted) setState(() => _yukleniyor = false);
    await _aktifSessionBul();
  }

  Future<void> _aktifSessionBul() async {
    try {
      final uid = RestAuthService.instance.currentUid ?? '';
      // orderByChild için index gerekebilir; hata alırsak tüm listeyi çekip filtrele
      DataSnapshot snap;
      try {
        snap = await FirebaseDatabase.instance
            .ref('attendance_sessions')
            .orderByChild('aktif')
            .equalTo(true)
            .get();
      } catch (_) {
        snap = await FirebaseDatabase.instance
            .ref('attendance_sessions')
            .get();
      }

      if (snap.exists && snap.value is Map) {
        (snap.value as Map).forEach((sid, data) {
          if (data is! Map) return;
          if (data['aktif'] != true) return;
          final dersAdi = data['ders_adi']?.toString() ?? '';
          final hocaUid = data['hoca_uid']?.toString() ?? '';
          if (dersAdi.toLowerCase() == widget.dersAdi.toLowerCase() &&
              (hocaUid == uid || hocaUid.isEmpty)) {
            _sessionId = sid.toString();
            _aktif = true;
          }
        });
      }

      if (_sessionId != null && mounted) {
        setState(() {});
        _sessionDinle(_sessionId!);
      }
    } catch (e) {
      debugPrint('_aktifSessionBul hata: $e');
    }
  }

  /// Türkçe karakterleri ASCII'ye dönüştürür.
  /// Dart'ta 'İ'.toLowerCase() = 'i̇' (noktalı i) — Firebase ile eşleşmez.
  static String _trNormalize(String s) => s
      .replaceAll('İ', 'i').replaceAll('I', 'i').replaceAll('ı', 'i')
      .replaceAll('Ğ', 'g').replaceAll('ğ', 'g')
      .replaceAll('Ş', 's').replaceAll('ş', 's')
      .replaceAll('Ö', 'o').replaceAll('ö', 'o')
      .replaceAll('Ü', 'u').replaceAll('ü', 'u')
      .replaceAll('Ç', 'c').replaceAll('ç', 'c')
      .toLowerCase()
      .trim();

  /// Ders adı eşleşme
  bool _dersEslesiyor(String firebaseAd) {
    // 1. Direkt toLowerCase karşılaştırması (verilen_ders_detay ile aynı mantık)
    if (firebaseAd.trim().toLowerCase() == widget.dersAdi.trim().toLowerCase()) return true;

    // 2. Türkçe normalize (ı→i, İ→i vb.) sonra karşılaştır
    final hedef  = _trNormalize(widget.dersAdi);
    final kaynak = _trNormalize(firebaseAd);
    if (hedef == kaynak) return true;

    // 3. Parantez içini sil, tekrar karşılaştır
    final hedefTemiz  = hedef.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    final kaynakTemiz = kaynak.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    if (hedefTemiz == kaynakTemiz) return true;

    // 4. Kelime kesişimi — 2+ karakterli kelimeleri dahil et (is, ve gibi kısalar da sayılsın)
    final hedefKelime  = hedefTemiz.split(RegExp(r'\s+')).where((k) => k.length >= 2).toSet();
    final kaynakKelime = kaynakTemiz.split(RegExp(r'\s+')).where((k) => k.length >= 2).toSet();
    if (hedefKelime.isNotEmpty && kaynakKelime.isNotEmpty) {
      final ortak = hedefKelime.intersection(kaynakKelime).length;
      final minLen = hedefKelime.length < kaynakKelime.length
          ? hedefKelime.length : kaynakKelime.length;
      if (ortak >= minLen) return true;
    }

    // 5. Biri diğerini içeriyor mu (substring kontrolü)
    if (hedefTemiz.contains(kaynakTemiz) || kaynakTemiz.contains(hedefTemiz)) return true;

    return false;
  }

  void _sessionDinle(String sid) {
    _recordsSub?.cancel();
    _recordsSub = FirebaseDatabase.instance
        .ref('attendance_sessions/$sid/records')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final records = event.snapshot.value;
      if (records is Map) {
        setState(() {
          records.forEach((tc, rec) {
            if (rec is! Map) return;
            final o = _ogrenciler[tc.toString()];
            if (o == null) return;
            final fs = rec['final_status']?.toString();
            if (fs != null && fs.isNotEmpty) {
              o.durum = fs;
            } else if (rec['face_ok'] == true || rec['rfid_ok'] == true) {
              o.durum = 'kısmi';
            }
          });
        });
      }
    });
  }

  Future<void> _yoklamaBaslat() async {
    final uid = RestAuthService.instance.currentUid ?? '';
    final now = DateTime.now();
    final tarih =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final ref =
        FirebaseDatabase.instance.ref('attendance_sessions').push();
    await ref.set({
      'aktif': true,
      'ders_adi': widget.dersAdi,
      'derslik': widget.derslik,
      'gun': widget.gun,
      'saat': widget.saat,
      'hoca_uid': uid,
      'hoca_ad_soyad': widget.hocaAdSoyad,
      'tarih': tarih,
      'baslangic_ts': ServerValue.timestamp,
    });

    setState(() {
      _sessionId = ref.key;
      _aktif = true;
    });
    _sessionDinle(ref.key!);
  }

  Future<void> _yoklamaBitir() async {
    if (_sessionId == null) return;
    await FirebaseDatabase.instance
        .ref('attendance_sessions/$_sessionId')
        .update({'aktif': false, 'bitis_ts': ServerValue.timestamp});
    _recordsSub?.cancel();
    setState(() => _aktif = false);
  }

  List<_OgrenciDurum> get _sortedList {
    final list = _ogrenciler.values.toList();
    list.sort((a, b) {
      // Mevcut → Kısmi → Bekliyor
      int rank(String d) =>
          d == 'present' ? 0 : (d == 'kısmi' || d.contains('only') ? 1 : 2);
      final r = rank(a.durum).compareTo(rank(b.durum));
      return r != 0 ? r : a.adSoyad.compareTo(b.adSoyad);
    });
    return list;
  }

  // Ders başlamadan önce (session açılmamışsa) öğrenciler "bekliyor" sayılır
  bool get _dersBaslamadi => _sessionId == null && !_aktif;
  // Ders sona erdi (session kapandı)
  bool get _dersBitti => _sessionId != null && !_aktif;

  @override
  Widget build(BuildContext context) {
    final list = _sortedList;
    final present = list.where((o) => o.durum == 'present').length;
    final partial = list.where((o) =>
        o.durum == 'kısmi' || o.durum == 'face_only' || o.durum == 'rfid_only').length;
    // "Gelmedi" sadece ders bittikten sonra anlamlı
    final absent = _dersBitti ? list.length - present - partial : 0;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.dersAdi,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: _neu,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        // ── Özet ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          color: _neu.withOpacity(0.07),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _OzetKutu(deger: '${list.length}', etiket: 'Toplam', renk: Colors.blueGrey),
              _OzetKutu(deger: '$present', etiket: 'Mevcut', renk: Colors.green),
              _OzetKutu(deger: '$partial', etiket: 'Kısmi', renk: Colors.orange),
              _OzetKutu(deger: '$absent', etiket: 'Gelmedi', renk: Colors.red.shade400),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.room, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                widget.derslik.isNotEmpty ? widget.derslik : 'Derslik belirtilmemiş',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.access_time, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${widget.gun}  •  ${widget.saat}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ]),
        ),

        // ── Başlat / Bitir ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SizedBox(
            width: double.infinity,
            child: _aktif
                ? ElevatedButton.icon(
                    onPressed: _yoklamaBitir,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Yoklamayı Bitir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _yoklamaBaslat,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Yoklama Başlat'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _neu,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
          ),
        ),

        // ── Ders saatine yaklaşıyor uyarısı (30 dk önceden) ──
        if (!_aktif && _dakikaKaldi > 0 && _dakikaKaldi <= 30)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(children: [
              const Icon(Icons.alarm, color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Derse $_dakikaKaldi dakika kaldı — yoklamayı başlatmayı unutmayın.',
                  style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),

        // ── Canlı durum bandı ──
        if (_aktif)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(children: [
              Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Yoklama aktif — RFID / yüz tanıma sistemi öğrencileri kaydediyor',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ),
            ]),
          ),

        // ── Ders bitti bandı ──
        if (_dersBitti)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.grey, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text('Yoklama tamamlandı.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ]),
          ),

        const SizedBox(height: 6),

        // ── Öğrenci listesi ──
        Expanded(
          child: _yukleniyor
              ? const Center(child: CircularProgressIndicator(color: _neu))
              : list.isEmpty
                  ? const Center(
                      child: Text('Bu dersi alan öğrenci bulunamadı.',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final o = list[i];
                        final isPresent = o.durum == 'present';
                        final isPartial = o.durum == 'kısmi' ||
                            o.durum == 'face_only' ||
                            o.durum == 'rfid_only';
                        // Ders başlamadıysa kırmızı gösterme
                        final showAbsent = !_dersBaslamadi;
                        final renk = isPresent
                            ? Colors.green
                            : isPartial
                                ? Colors.orange
                                : showAbsent
                                    ? Colors.red.shade300
                                    : Colors.grey.shade400;

                        // Chip için gerçek durum: başlamadıysa bekliyor
                        final chipDurum = (!isPresent && !isPartial && _dersBaslamadi)
                            ? 'bekliyor'
                            : o.durum;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: renk.withOpacity(0.15),
                              child: Text(
                                o.adSoyad.isNotEmpty ? o.adSoyad[0] : '?',
                                style: TextStyle(
                                    color: renk,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                            title: Text(o.adSoyad,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(o.okulNo,
                                style: const TextStyle(fontSize: 11)),
                            trailing: _DurumChip(durum: chipDurum),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ────────────────────────────────────────────────────
class _OzetKutu extends StatelessWidget {
  final String deger;
  final String etiket;
  final Color renk;
  const _OzetKutu(
      {required this.deger, required this.etiket, required this.renk});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(deger,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: renk)),
        Text(etiket,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]);
}

// ────────────────────────────────────────────────────
class _DurumChip extends StatelessWidget {
  final String durum;
  const _DurumChip({required this.durum});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (durum) {
      case 'present':
        color = Colors.green;
        label = 'Mevcut';
        break;
      case 'face_only':
        color = Colors.orange;
        label = 'Yüz ✓';
        break;
      case 'rfid_only':
        color = Colors.orange;
        label = 'RFID ✓';
        break;
      case 'kısmi':
        color = Colors.orange;
        label = 'Kısmi';
        break;
      case 'bekliyor':
        color = Colors.grey;
        label = 'Bekliyor';
        break;
      default:
        color = Colors.red.shade300;
        label = 'Gelmedi';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

// ────────────────────────────────────────────────────
class _OgrenciDurum {
  final String tc;
  final String adSoyad;
  final String okulNo;
  String durum;

  _OgrenciDurum({
    required this.tc,
    required this.adSoyad,
    required this.okulNo,
    required this.durum,
  });
}
