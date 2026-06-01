// sinav_yonetim_sayfasi.dart
//
// İdari panelden açılan sınav yönetim merkezi.
// Tab 1 – Sınav Takvimi : Firebase'deki tüm sınavları listele,
//         derslik/oturma planı ataması başlat, detay görüntüle.
// Tab 2 – Derslikler    : Derslik ekle / sil, kapasite göster.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../services/sinav_atama_service.dart' show SinavAtamaService, Derslik, SinifSecimi, AtamaOzeti;

const Color _neu = Color(0xFF005A71);

// ═══════════════════════════════════════════════════════════════
class SinavYonetimSayfasi extends StatefulWidget {
  const SinavYonetimSayfasi({super.key});
  @override
  State<SinavYonetimSayfasi> createState() => _SinavYonetimSayfasiState();
}

class _SinavYonetimSayfasiState extends State<SinavYonetimSayfasi>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Sınav Yönetimi',
              style: TextStyle(color: Colors.white)),
          backgroundColor: _neu,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.event_note), text: 'Sınav Takvimi'),
              Tab(icon: Icon(Icons.meeting_room), text: 'Derslikler'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: const [
            _SinavTakvimiTab(),
            _DersliklerTab(),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════
// TAB 1 – SINAV TAKVİMİ
// ═══════════════════════════════════════════════════════════════
class _SinavTakvimiTab extends StatefulWidget {
  const _SinavTakvimiTab();
  @override
  State<_SinavTakvimiTab> createState() => _SinavTakvimiTabState();
}

class _SinavTakvimiTabState extends State<_SinavTakvimiTab> {
  final _db     = FirebaseDatabase.instance.ref();
  final _servis = SinavAtamaService();

  List<_SinavItem> _sinavlar = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _veriCek();
  }

  Future<void> _veriCek() async {
    setState(() => _yukleniyor = true);
    final snap = await _db.child('sinav_takvimi').get();
    final liste = <_SinavItem>[];
    if (snap.exists && snap.value is Map) {
      (snap.value as Map).forEach((k, v) {
        if (v is Map) liste.add(_SinavItem.fromMap(k.toString(), Map.from(v)));
      });
    }
    liste.sort((a, b) {
      final td = _tarihCevir(a.tarih).compareTo(_tarihCevir(b.tarih));
      return td != 0 ? td : a.saat.compareTo(b.saat);
    });
    if (mounted) setState(() { _sinavlar = liste; _yukleniyor = false; });
  }

  DateTime _tarihCevir(String t) {
    try {
      final p = t.split('.');
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) { return DateTime(2000); }
  }

  // ---- Per-sınav diyalog ----
  void _sinavAtamaDiyalogu(_SinavItem sinav) async {
    // Derslikleri çek
    final derslikler = await _servis.fetchDerslikler();
    if (!mounted) return;
    if (derslikler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Önce "Derslikler" sekmesinden derslik ekleyin.')));
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => _SinavAtamaDiyalogu(
        sinav: sinav,
        derslikler: derslikler,
        servis: _servis,
        onTamamlandi: _veriCek,
      ),
    );
  }

  // ---- Tümünü otomatik ata ----
  void _atamaBaslat() async {
    final statusN  = ValueNotifier<String>('Başlatılıyor...');
    final finishN  = ValueNotifier<bool>(false);
    final mesajN   = ValueNotifier<String>('');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ValueListenableBuilder<bool>(
            valueListenable: finishN,
            builder: (ctx, done, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                done
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 60)
                    : const CircularProgressIndicator(color: _neu),
                const SizedBox(height: 16),
                ValueListenableBuilder<String>(
                  valueListenable: statusN,
                  builder: (_, s, __) => Text(s,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (done) ...[
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: mesajN,
                    builder: (_, m, __) => Text(m,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _neu,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () { Navigator.pop(ctx); _veriCek(); },
                    child: const Text('Kapat', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final ozet = await _servis.ataVeOturmaPlaniOlustur(
      onDurum: (m) => statusN.value = m,
    );
    mesajN.value  = ozet.mesaj;
    finishN.value = true;
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Center(child: CircularProgressIndicator(color: _neu));
    }

    // Tarih grupları
    final Map<String, List<_SinavItem>> gruplar = {};
    for (final s in _sinavlar) {
      gruplar.putIfAbsent(s.tarih, () => []).add(s);
    }

    return Column(children: [
      // Üst buton
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: Colors.grey.shade50,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _neu,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.auto_awesome, color: Colors.white),
          label: const Text(
            'Derslik Ata & Oturma Planı Oluştur',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          onPressed: _atamaBaslat,
        ),
      ),
      // Sınav listesi
      Expanded(
        child: RefreshIndicator(
          onRefresh: _veriCek,
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: gruplar.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tarih başlığı
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Container(width: 4, height: 18, color: _neu,
                          margin: const EdgeInsets.only(right: 8)),
                      Text(entry.key,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15, color: _neu)),
                      const SizedBox(width: 8),
                      Text('${entry.value.length} sınav',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ]),
                  ),
                  ...entry.value.map((s) => _SinavKarti(
                        sinav: s,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => _SinavDetaySayfasi(sinav: s))),
                        onAtama: () => _sinavAtamaDiyalogu(s),
                      )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    ]);
  }
}

// ---- Sınav listesi kartı ----
class _SinavKarti extends StatelessWidget {
  final _SinavItem sinav;
  final VoidCallback onTap;
  final VoidCallback onAtama;
  const _SinavKarti({required this.sinav, required this.onTap, required this.onAtama});

  @override
  Widget build(BuildContext context) {
    final atandi = sinav.derslikAtamalari.isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            onTap: onTap,
            leading: CircleAvatar(
              backgroundColor: atandi ? Colors.green.shade100 : Colors.grey.shade200,
              child: Icon(
                atandi ? Icons.check : Icons.hourglass_empty,
                color: atandi ? Colors.green : Colors.grey,
                size: 20,
              ),
            ),
            title: Text(sinav.dersAdi,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${sinav.saat}  •  ${sinav.hocaAdi}',
                    style: const TextStyle(fontSize: 11)),
                if (atandi)
                  Text(
                    sinav.derslikAtamalari
                        .map((d) => '${d['derslik_ad']} (${(d['oturma_plani'] as Map?)?.length ?? 0} öğr.)')
                        .join(' + '),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                  )
                else
                  Text('${sinav.ogrenciSayisi} öğrenci — derslik atanmadı',
                      style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 13),
          ),
          // Derslik Ata butonu
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAtama,
                icon: Icon(
                  atandi ? Icons.edit_location_alt : Icons.add_location_alt,
                  size: 16,
                  color: _neu,
                ),
                label: Text(
                  atandi ? 'Derslik Atamasını Düzenle' : 'Derslik Ata & Oturma Planı',
                  style: const TextStyle(fontSize: 12, color: _neu),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _neu),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SINAV ATAMA DİYALOGU
// ═══════════════════════════════════════════════════════════════
class _SinavAtamaDiyalogu extends StatefulWidget {
  final _SinavItem sinav;
  final List<Derslik> derslikler;
  final SinavAtamaService servis;
  final VoidCallback onTamamlandi;

  const _SinavAtamaDiyalogu({
    required this.sinav,
    required this.derslikler,
    required this.servis,
    required this.onTamamlandi,
  });

  @override
  State<_SinavAtamaDiyalogu> createState() => _SinavAtamaDiyaloguState();
}

class _SinavAtamaDiyaloguState extends State<_SinavAtamaDiyalogu> {
  int _sinifSayisi = 1;
  // Her sınıf için seçili derslik ve sıra başına kişi
  late List<Derslik?> _secilenDerslik;
  late List<int> _kisiPerSira;
  bool _yukleniyor = false;

  @override
  void initState() {
    super.initState();
    _secilenDerslik = [widget.derslikler.isNotEmpty ? widget.derslikler.first : null];
    _kisiPerSira = [widget.derslikler.isNotEmpty ? widget.derslikler.first.kisiPerSira : 1];
  }

  void _sinifSayisiDegistir(int yeni) {
    if (yeni < 1 || yeni > widget.derslikler.length) return;
    setState(() {
      _sinifSayisi = yeni;
      while (_secilenDerslik.length < yeni) {
        _secilenDerslik.add(widget.derslikler.isNotEmpty ? widget.derslikler.first : null);
        _kisiPerSira.add(widget.derslikler.isNotEmpty ? widget.derslikler.first.kisiPerSira : 1);
      }
      _secilenDerslik = _secilenDerslik.take(yeni).toList();
      _kisiPerSira = _kisiPerSira.take(yeni).toList();
    });
  }

  int get _toplamKapasite {
    int toplam = 0;
    for (int i = 0; i < _sinifSayisi; i++) {
      final d = _secilenDerslik[i];
      if (d != null) toplam += d.siraSayisi * _kisiPerSira[i];
    }
    return toplam;
  }

  bool get _yeterli => _toplamKapasite >= widget.sinav.ogrenciSayisi;

  void _oturmaPlaniOlustur() async {
    // Validasyon: aynı derslik iki kez seçilmesin
    final secilenIdler = _secilenDerslik.take(_sinifSayisi).map((d) => d?.id).toList();
    if (secilenIdler.toSet().length < secilenIdler.length) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aynı derslik iki kez seçilemez.')));
      return;
    }

    setState(() => _yukleniyor = true);

    final secimler = List.generate(_sinifSayisi, (i) => SinifSecimi(
      derslik: _secilenDerslik[i]!,
      kisiPerSira: _kisiPerSira[i],
    ));

    final hata = await widget.servis.tekSinavIcinAta(
      sinavKod: widget.sinav.kod,
      secimler: secimler,
    );

    if (!mounted) return;
    setState(() => _yukleniyor = false);

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hata ?? 'Oturma planı oluşturuldu ✓'),
      backgroundColor: hata == null ? Colors.green : Colors.red,
      duration: const Duration(seconds: 4),
    ));
    widget.onTamamlandi();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.sinav.dersAdi,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Text('${widget.sinav.tarih}  •  ${widget.sinav.ogrenciSayisi} öğrenci',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sınıf sayısı seçici
              const Text('Kaç sınıf açılacak?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => _sinifSayisiDegistir(_sinifSayisi - 1),
                    icon: const Icon(Icons.remove_circle_outline, color: _neu),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: _neu.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$_sinifSayisi sınıf',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16, color: _neu)),
                  ),
                  IconButton(
                    onPressed: () => _sinifSayisiDegistir(_sinifSayisi + 1),
                    icon: const Icon(Icons.add_circle_outline, color: _neu),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Her sınıf için derslik seçimi
              ...List.generate(_sinifSayisi, (i) {
                final d = _secilenDerslik[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. Sınıf',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12, color: _neu)),
                      const SizedBox(height: 8),
                      // Derslik seçimi
                      DropdownButtonFormField<Derslik>(
                        value: _secilenDerslik[i],
                        decoration: const InputDecoration(
                          labelText: 'Derslik',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        items: widget.derslikler.map((d) => DropdownMenuItem(
                          value: d,
                          child: Text('${d.ad}  (${d.siraSayisi} sıra)',
                              style: const TextStyle(fontSize: 13)),
                        )).toList(),
                        onChanged: (val) => setState(() {
                          _secilenDerslik[i] = val;
                          if (val != null) _kisiPerSira[i] = val.kisiPerSira;
                        }),
                      ),
                      const SizedBox(height: 10),
                      // Sıra başına kişi
                      Row(children: [
                        const Expanded(
                          child: Text('Sıra başına öğrenci:',
                              style: TextStyle(fontSize: 12)),
                        ),
                        IconButton(
                          iconSize: 20,
                          onPressed: _kisiPerSira[i] > 1
                              ? () => setState(() => _kisiPerSira[i]--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          color: _neu,
                        ),
                        Text('${_kisiPerSira[i]}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          iconSize: 20,
                          onPressed: () => setState(() => _kisiPerSira[i]++),
                          icon: const Icon(Icons.add_circle_outline),
                          color: _neu,
                        ),
                      ]),
                      // Kapasite
                      if (d != null)
                        Text(
                          '${d.siraSayisi} sıra × ${_kisiPerSira[i]} kişi = ${d.siraSayisi * _kisiPerSira[i]} kişilik',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                );
              }),

              // Toplam kapasite özeti
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _yeterli ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _yeterli ? Colors.green.shade200 : Colors.red.shade200),
                ),
                child: Row(children: [
                  Icon(
                    _yeterli ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: _yeterli ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Toplam kapasite: $_toplamKapasite  |  Öğrenci: ${widget.sinav.ogrenciSayisi}'
                      '${_yeterli ? '  ✓' : '  ⚠️ Yetersiz!'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _yeterli ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _yukleniyor ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _yeterli ? _neu : Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _yukleniyor ? null : _oturmaPlaniOlustur,
          icon: _yukleniyor
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.shuffle, color: Colors.white, size: 18),
          label: Text(
            _yukleniyor ? 'Oluşturuluyor...' : 'Oturma Planı Oluştur',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SINAV DETAY SAYFASI (oturma planı)
// ═══════════════════════════════════════════════════════════════
class _SinavDetaySayfasi extends StatelessWidget {
  final _SinavItem sinav;
  const _SinavDetaySayfasi({super.key, required this.sinav});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(sinav.dersAdi,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: _neu,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Bilgi kartı
          Card(
            color: _neu.withOpacity(0.06),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bilgiSatiri(Icons.event, 'Tarih / Saat', '${sinav.tarih}  ${sinav.saat}'),
                  _bilgiSatiri(Icons.school, 'Hoca', sinav.hocaAdi),
                  _bilgiSatiri(Icons.people, 'Toplam Öğrenci', '${sinav.ogrenciSayisi} kişi'),
                  if (sinav.derslikAtamalari.isNotEmpty)
                    _bilgiSatiri(Icons.meeting_room, 'Derslik(ler)',
                        sinav.derslikAtamalari.map((d) => d['derslik_ad']).join(', ')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (sinav.derslikAtamalari.isEmpty)
            const Center(
                child: Text('Henüz derslik atanmadı.',
                    style: TextStyle(color: Colors.grey))),

          // Her derslik için oturma planı
          ...sinav.derslikAtamalari.map((atama) {
            final derslikAd  = atama['derslik_ad']?.toString() ?? '';
            final siraSayisi = atama['sira_sayisi'] as int? ?? 0;
            final kisiPerSira = atama['kisi_per_sira'] as int? ?? 0;
            final oturmalar  = atama['oturma_plani'] as Map? ?? {};

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('📍 $derslikAd — $siraSayisi sıra × $kisiPerSira kişi',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                // Sıra bazlı görünüm
                ...List.generate(siraSayisi, (siraIdx) {
                  final siraNo = siraIdx + 1;
                  final buSiradakiler = oturmalar.entries
                      .where((e) => (e.value as Map)['sira'] == siraNo)
                      .toList();

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: buSiradakiler.isEmpty
                          ? Colors.grey.shade100
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: buSiradakiler.isEmpty
                              ? Colors.grey.shade300
                              : Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text('Sıra $siraNo',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        Expanded(
                          child: buSiradakiler.isEmpty
                              ? const Text('Boş',
                                  style: TextStyle(color: Colors.grey, fontSize: 12))
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: buSiradakiler.map((e) {
                                    final d = e.value as Map;
                                    return Chip(
                                      backgroundColor: _neu.withOpacity(0.1),
                                      label: Text(
                                        'K${d['koltuk']}: ${d['ad_soyad']}',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 24),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _bilgiSatiri(IconData icon, String etiket, String deger) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: _neu),
          const SizedBox(width: 8),
          Text('$etiket: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(child: Text(deger, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════
// TAB 2 – DERSLİKLER
// ═══════════════════════════════════════════════════════════════
class _DersliklerTab extends StatefulWidget {
  const _DersliklerTab();
  @override
  State<_DersliklerTab> createState() => _DersliklerTabState();
}

class _DersliklerTabState extends State<_DersliklerTab> {
  final _db = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> _derslikler = [];
  bool _yukleniyor = true;

  @override
  void initState() { super.initState(); _veriCek(); }

  Future<void> _veriCek() async {
    setState(() => _yukleniyor = true);
    final snap = await _db.child('derslikler').get();
    final liste = <Map<String, dynamic>>[];
    if (snap.exists && snap.value is Map) {
      (snap.value as Map).forEach((k, v) {
        if (v is Map) liste.add({...Map<String, dynamic>.from(v), '_id': k.toString()});
      });
    }
    liste.sort((a, b) => (a['ad'] ?? '').compareTo(b['ad'] ?? ''));
    if (mounted) setState(() { _derslikler = liste; _yukleniyor = false; });
  }

  void _derslikFormu({Map<String, dynamic>? mevcut}) {
    final adCtrl    = TextEditingController(text: mevcut?['ad']?.toString() ?? '');
    final siraCtrl  = TextEditingController(
        text: mevcut?['sira_sayisi']?.toString() ?? '');
    final kisiCtrl  = TextEditingController(
        text: mevcut?['kisi_per_sira']?.toString() ?? '');
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(mevcut == null ? 'Derslik Ekle' : 'Derslik Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: adCtrl,
                decoration: const InputDecoration(
                  labelText: 'Derslik Adı (örn: A-101)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: siraCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sıra Sayısı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kisiCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sıra Başına Kişi Sayısı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              // Kapasite önizleme
              ValueListenableBuilder(
                valueListenable: siraCtrl,
                builder: (_, __, ___) {
                  final s = int.tryParse(siraCtrl.text) ?? 0;
                  final k = int.tryParse(kisiCtrl.text) ?? 0;
                  return Text(
                    'Toplam Kapasite: ${s * k} kişi',
                    style: const TextStyle(
                        color: _neu, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('İptal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _neu),
              onPressed: saving
                  ? null
                  : () async {
                      final ad   = adCtrl.text.trim();
                      final sira = int.tryParse(siraCtrl.text) ?? 0;
                      final kisi = int.tryParse(kisiCtrl.text) ?? 0;
                      if (ad.isEmpty || sira <= 0 || kisi <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Tüm alanları doldurun.')));
                        return;
                      }
                      setS(() => saving = true);
                      final data = {
                        'ad': ad,
                        'sira_sayisi': sira,
                        'kisi_per_sira': kisi,
                        'kapasite': sira * kisi,
                      };
                      if (mevcut != null) {
                        await _db.child('derslikler/${mevcut['_id']}').update(data);
                      } else {
                        await _db.child('derslikler').push().set(data);
                      }
                      if (mounted) { Navigator.pop(ctx); _veriCek(); }
                    },
              child: Text(mevcut == null ? 'Ekle' : 'Kaydet',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _sil(String id, String ad) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Derslik Sil'),
        content: Text('"$ad" dersliğini silmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.child('derslikler/$id').remove();
              if (mounted) { Navigator.pop(context); _veriCek(); }
            },
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Center(child: CircularProgressIndicator(color: _neu));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _neu,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Derslik Ekle',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _derslikFormu(),
          ),
        ),
      ),
      if (_derslikler.isEmpty)
        const Expanded(
          child: Center(
              child: Text('Henüz derslik eklenmedi.',
                  style: TextStyle(color: Colors.grey))),
        )
      else
        Expanded(
          child: RefreshIndicator(
            onRefresh: _veriCek,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _derslikler.length,
              itemBuilder: (_, i) {
                final d = _derslikler[i];
                final kapasite = (d['sira_sayisi'] ?? 0) * (d['kisi_per_sira'] ?? 0);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _neu.withOpacity(0.1),
                      child: const Icon(Icons.meeting_room, color: _neu),
                    ),
                    title: Text(d['ad']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${d['sira_sayisi']} sıra  ×  ${d['kisi_per_sira']} kişi  =  $kapasite kişilik',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            onPressed: () => _derslikFormu(mevcut: d)),
                        IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _sil(d['_id'], d['ad']?.toString() ?? '')),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════
// VERİ MODELİ
// ═══════════════════════════════════════════════════════════════
class _SinavItem {
  final String kod;
  final String dersAdi;
  final String hocaAdi;
  final String tarih;
  final String saat;
  final int    ogrenciSayisi;
  final List<Map<String, dynamic>> derslikAtamalari;

  const _SinavItem({
    required this.kod,
    required this.dersAdi,
    required this.hocaAdi,
    required this.tarih,
    required this.saat,
    required this.ogrenciSayisi,
    required this.derslikAtamalari,
  });

  factory _SinavItem.fromMap(String kod, Map data) {
    final ogrenciler = data['ogrenciler'];
    final atamalarRaw = data['derslik_atamalari'];
    final atamalar = <Map<String, dynamic>>[];
    if (atamalarRaw is List) {
      for (final a in atamalarRaw) {
        if (a is Map) atamalar.add(Map<String, dynamic>.from(a));
      }
    }
    return _SinavItem(
      kod: kod,
      dersAdi: data['ders_adi']?.toString() ?? kod,
      hocaAdi: data['hoca_adi']?.toString() ?? '',
      tarih: data['tarih']?.toString() ?? '',
      saat: data['saat']?.toString() ?? '',
      ogrenciSayisi: ogrenciler is Map ? ogrenciler.length : 0,
      derslikAtamalari: atamalar,
    );
  }
}
