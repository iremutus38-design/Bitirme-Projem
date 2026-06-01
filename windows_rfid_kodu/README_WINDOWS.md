# Windows RFID Köprüsü — Kurulum & Kullanım

## Sistem Mimarisi

```
[RFID Anten]  192.168.137.31:80
      │
      │  HTTP GET /  (her 250ms)
      ▼
[Windows PC]  rfid_to_firebase.py
      │
      │  Firebase Admin SDK (HTTPS)
      ▼
[Firebase Realtime Database]
      │
      ├── on_kayitlar/{tc}/rfid_uid       ← Kart bağlama
      ├── rfid_index/{uid} → tc           ← Hızlı arama
      └── rfid_events/{push}             ← Yoklama olayları
            │
            ▼
      [Mac]  attend.py  (rfid_events'i dinler, yoklamayı günceller)
```

---

## 1. Kurulum (sadece bir kez)

### Gereksinimler
```
pip install firebase-admin
```

### serviceAccountKey.json
Firebase Console → Proje Ayarları → Hizmet Hesapları → Python →
"Yeni özel anahtar oluştur" → İndirilen dosyayı bu klasöre koy:
`windows_rfid_kodu/serviceAccountKey.json`

### IP Ayarı
`rfid_to_firebase.py` dosyasının üstünde:
```python
ANTENNA_HOST = "192.168.137.31"   # anteninin güncel IP'si — değiştir
```

---

## 2. Önce Test Et

Anten gerçekten okunuyor mu kontrol et (Firebase'e YAZMAZ):
```
python rfid_to_firebase.py test
```
Kart okuttukça terminalde UID'ler görünmeli. Görünmüyorsa IP'yi kontrol et.

---

## 3. Kart Bağlama (Enroll)

### Flutter uygulamasından (önerilen — hiç terminal açmana gerek yok)
1. İdari Panel → Yüz & Kart Yönetimi
2. Öğrenciyi bul → **"Kart Bağla"** butonuna bas
3. Dialog açılır: *"Kartı okuyucuya yaklaştırın..."*
4. Kartı antene tut → UID otomatik okunur, ekranda yeşil gösterilir
5. **"Kaydet"** bas → Firebase'e yazılır

Flutter app 192.168.137.31:80'e direkt bağlanır, Windows'ta bir şey çalıştırmana gerek yok.
Sadece anten açık ve aynı ağda olmalı.

### Windows terminalinden (alternatif)
```
python rfid_to_firebase.py enroll
```
Listeden öğrenciyi seçersin, kartı tutarsın, Firebase'e yazar.

---

## 4. Ders Yoklaması (Ders Başlarken)

**Windows PC'de** bir terminal aç:
```
python rfid_to_firebase.py listen
```

**Mac'te** ayrı bir terminal aç (zaten çalışıyor olmalı):
```
python attend.py
```

### Ne olur?
- Öğrenci kartını antene tutar
- Windows script → `rfid_events/{push}` yazar (uid, timestamp)
- Mac attend.py → rfid_events'i okur → `attendance_sessions/{sid}/records/{tc}/rfid_ok = true`
- Flutter yoklama sayfası anlık güncellenir (kırmızı → yeşil)

Ders bitince Windows'ta **Ctrl+C** ile durdur.

---

## 5. Anten Format Desteği

Script iki farklı formatı otomatik tanır:

| Format | Örnek yanıt |
|--------|-------------|
| Basit (HF/NFC/ESP8266) | `A4B72F19` |
| UHF satır formatı | `00:00:00; 01/01/2000; 5.35V; a325fbf; 3; e28068940000501760066cdb; ...;;` |

---

## 6. Özet — Kim Ne Çalıştırır

| Durum | Windows | Mac |
|-------|---------|-----|
| Kart test | `python rfid_to_firebase.py test` | — |
| Kart bağlama | Anten açık olsun (veya `enroll`) | Flutter uygulaması |
| Ders yoklaması | `python rfid_to_firebase.py listen` | `python attend.py` |
