// sinav_atama_service.dart
//
// Derslik atama + oturma planı algoritması:
//
// 1. Firebase'den tüm sınavları ve derslikleri çek
// 2. Sınavları (tarih, saat_saat_kısmı) ile grupla  ← :00/:01 farkını normalize et
// 3. Her zaman diliminde aynı derslik iki farklı sınava atanamaz (çakışma engeli)
// 4. Büyük sınav → birden fazla dersliğe sığdır
// 5. Öğrencileri rastgele karıştır, sıra/koltuk sıralı ata
//
// Firebase çıktısı:
//   sinav_takvimi/{ders_kodu}/derslik_atamalari: [
//     {
//       derslik_id, derslik_ad, sira_sayisi, kisi_per_sira, kapasite,
//       oturma_plani: { okul_no: {ad_soyad, sira, koltuk, yer} }
//     }
//   ]

import 'dart:math';
import 'package:firebase_database/firebase_database.dart';

class Derslik {
  final String id;
  final String ad;
  final int siraSayisi;
  final int kisiPerSira;

  int get kapasite => siraSayisi * kisiPerSira;

  const Derslik({
    required this.id,
    required this.ad,
    required this.siraSayisi,
    required this.kisiPerSira,
  });

  factory Derslik.fromMap(String id, Map data) => Derslik(
        id: id,
        ad: data['ad']?.toString() ?? id,
        siraSayisi: int.tryParse(data['sira_sayisi']?.toString() ?? '0') ?? 0,
        kisiPerSira: int.tryParse(data['kisi_per_sira']?.toString() ?? '0') ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'derslik_id': id,
        'derslik_ad': ad,
        'sira_sayisi': siraSayisi,
        'kisi_per_sira': kisiPerSira,
        'kapasite': kapasite,
      };
}

class SinavAtamaService {
  final _db = FirebaseDatabase.instance.ref();

  // ----------------------------------------------------------------
  // Tek sınav için manuel derslik + oturma planı ata
  // ----------------------------------------------------------------
  /// Hata varsa hata mesajı döner, başarıda null döner.
  Future<String?> tekSinavIcinAta({
    required String sinavKod,
    required List<SinifSecimi> secimler,
  }) async {
    try {
      final snap = await _db.child('sinav_takvimi/$sinavKod').get();
      if (!snap.exists || snap.value is! Map) return 'Sınav bulunamadı.';
      final data = Map<String, dynamic>.from(snap.value as Map);

      final ogrencilerRaw = data['ogrenciler'];
      if (ogrencilerRaw == null || ogrencilerRaw is! Map) return 'Bu sınava kayıtlı öğrenci yok.';

      final ogrenciler = Map<String, Map>.from(
        (ogrencilerRaw as Map).map((k, v) => MapEntry(k.toString(), Map.from(v as Map))),
      );

      final ogrNoListe = ogrenciler.keys.toList()..shuffle(Random());

      int ogrIdx = 0;
      final List<Map<String, dynamic>> atamalar = [];

      for (final secim in secimler) {
        if (ogrIdx >= ogrNoListe.length) break;
        final derslik = secim.derslik;
        final kisiPerSira = secim.kisiPerSira;
        final siraSayisi = derslik.siraSayisi;
        final kapasite = siraSayisi * kisiPerSira;

        final Map<String, dynamic> oturmalar = {};
        for (int i = 0; i < kapasite && ogrIdx < ogrNoListe.length; i++) {
          final ogrNo  = ogrNoListe[ogrIdx++];
          final siraNo = (i ~/ kisiPerSira) + 1;
          final koltuk = (i %  kisiPerSira) + 1;
          oturmalar[ogrNo] = {
            'ad_soyad': ogrenciler[ogrNo]?['ad_soyad'] ?? '',
            'tc_no':    ogrenciler[ogrNo]?['tc_no'] ?? '',
            'sira':     siraNo,
            'koltuk':   koltuk,
            'yer':      'Sıra $siraNo / Koltuk $koltuk',
          };
        }

        atamalar.add({
          'derslik_id': derslik.id,
          'derslik_ad': derslik.ad,
          'sira_sayisi': siraSayisi,
          'kisi_per_sira': kisiPerSira,
          'kapasite': kapasite,
          'oturma_plani': oturmalar,
        });
      }

      await _db.child('sinav_takvimi/$sinavKod/derslik_atamalari').set(atamalar);
      return null; // başarı
    } catch (e) {
      return 'Hata: $e';
    }
  }

  // ----------------------------------------------------------------
  // Tüm derslikleri çek
  // ----------------------------------------------------------------
  Future<List<Derslik>> fetchDerslikler() async {
    final snap = await _db.child('derslikler').get();
    if (!snap.exists || snap.value is! Map) return [];
    final map = snap.value as Map;
    return map.entries
        .map((e) => Derslik.fromMap(e.key.toString(), Map.from(e.value as Map)))
        .where((d) => d.kapasite > 0)
        .toList();
  }

  // ----------------------------------------------------------------
  // Ana metod: derslik + oturma planı ata
  // ----------------------------------------------------------------
  Future<AtamaOzeti> ataVeOturmaPlaniOlustur({
    void Function(String mesaj)? onDurum,
  }) async {
    onDurum?.call('Sınavlar yükleniyor...');

    // 1. Sınavları çek
    final sinavSnap = await _db.child('sinav_takvimi').get();
    if (!sinavSnap.exists || sinavSnap.value is! Map) {
      return AtamaOzeti(basarili: false, mesaj: 'Sınav takvimi boş.');
    }
    final sinavMap = Map<String, Map>.from(
      (sinavSnap.value as Map).map(
        (k, v) => MapEntry(k.toString(), Map.from(v as Map)),
      ),
    );

    // 2. Derslikleri çek
    onDurum?.call('Derslikler yükleniyor...');
    final derslikler = await fetchDerslikler();
    if (derslikler.isEmpty) {
      return AtamaOzeti(basarili: false, mesaj: 'Önce en az bir derslik ekleyin.');
    }

    // Toplam kapasite
    derslikler.sort((a, b) => b.kapasite.compareTo(a.kapasite)); // büyükten küçüğe

    // 3. Sınavları (tarih, saat_normalize) ile grupla
    //    :01 gibi mükerrer dakikaları :00'a normalize et
    final Map<String, List<String>> zamanGruplari = {};
    for (final entry in sinavMap.entries) {
      final kod  = entry.key;
      final data = entry.value;
      final tarih = data['tarih']?.toString() ?? '';
      final saat  = _saatNormalize(data['saat']?.toString() ?? '');
      if (tarih.isEmpty) continue;
      final slot = '$tarih|$saat';
      zamanGruplari.putIfAbsent(slot, () => []).add(kod);
    }

    // 4. Her zaman dilimi için derslik ata
    onDurum?.call('Derslik ataması yapılıyor...');
    // slot → kullanılmış derslik id listesi
    final Map<String, Set<String>> slotKullanilanDerslik = {};

    // Tüm güncellemeleri toplu yaz
    final Map<String, dynamic> updates = {};
    int atananSinav = 0;
    int atanamayanSinav = 0;

    for (final slot in zamanGruplari.keys) {
      final kodlar = zamanGruplari[slot]!;
      slotKullanilanDerslik.putIfAbsent(slot, () => {});

      for (final kod in kodlar) {
        final data = sinavMap[kod]!;
        final ogrencilerRaw = data['ogrenciler'];
        if (ogrencilerRaw == null || ogrencilerRaw is! Map) continue;

        final ogrenciler = Map<String, Map>.from(
          (ogrencilerRaw as Map).map(
            (k, v) => MapEntry(k.toString(), Map.from(v as Map)),
          ),
        );

        final List<String> ogrNoListe = ogrenciler.keys.toList();
        ogrNoListe.shuffle(Random());

        // Kullanılmamış derslikleri bul
        final musaitDerslikler = derslikler
            .where((d) => !slotKullanilanDerslik[slot]!.contains(d.id))
            .toList();

        if (musaitDerslikler.isEmpty) {
          atanamayanSinav++;
          continue;
        }

        // Öğrencileri dersliklere böl
        final List<Map<String, dynamic>> atamalar = [];
        int ogrIdx = 0;

        for (final derslik in musaitDerslikler) {
          if (ogrIdx >= ogrNoListe.length) break;

          slotKullanilanDerslik[slot]!.add(derslik.id);

          final Map<String, dynamic> oturmalar = {};
          for (int i = 0; i < derslik.kapasite && ogrIdx < ogrNoListe.length; i++) {
            final ogrNo  = ogrNoListe[ogrIdx++];
            final siraNo = (i ~/ derslik.kisiPerSira) + 1;
            final koltuk = (i %  derslik.kisiPerSira) + 1;
            oturmalar[ogrNo] = {
              'ad_soyad': ogrenciler[ogrNo]?['ad_soyad'] ?? '',
              'tc_no':    ogrenciler[ogrNo]?['tc_no'] ?? '',
              'sira':     siraNo,
              'koltuk':   koltuk,
              'yer':      'Sıra $siraNo / Koltuk $koltuk',
            };
          }

          atamalar.add({
            ...derslik.toMap(),
            'oturma_plani': oturmalar,
          });
        }

        if (ogrIdx < ogrNoListe.length) {
          // Tüm öğrenciler sığmadı → uyarı ama devam et
          atanamayanSinav++;
        }

        updates['sinav_takvimi/$kod/derslik_atamalari'] = atamalar;
        atananSinav++;
      }
    }

    onDurum?.call('Firebase\'e yazılıyor...');
    await _db.update(updates);

    return AtamaOzeti(
      basarili: true,
      mesaj: '$atananSinav sınav için derslik ve oturma planı oluşturuldu.'
          '${atanamayanSinav > 0 ? '\n⚠️ $atanamayanSinav sınav için derslik yetmedi.' : ''}',
      atananSinav: atananSinav,
      atanamayanSinav: atanamayanSinav,
    );
  }

  // ----------------------------------------------------------------
  // Yardımcılar
  // ----------------------------------------------------------------

  /// "10:01" → "10:00",  "14:00" → "14:00"
  String _saatNormalize(String saat) {
    final parts = saat.split(':');
    if (parts.length < 2) return saat;
    final dakika = int.tryParse(parts[1]) ?? 0;
    // 5 dakikadan az farkı sıfıra normalize et
    final normDakika = (dakika < 5) ? 0 : dakika;
    return '${parts[0]}:${normDakika.toString().padLeft(2, '0')}';
  }
}

class SinifSecimi {
  final Derslik derslik;
  final int kisiPerSira;
  const SinifSecimi({required this.derslik, required this.kisiPerSira});
}

class AtamaOzeti {
  final bool basarili;
  final String mesaj;
  final int atananSinav;
  final int atanamayanSinav;

  const AtamaOzeti({
    required this.basarili,
    required this.mesaj,
    this.atananSinav = 0,
    this.atanamayanSinav = 0,
  });
}
