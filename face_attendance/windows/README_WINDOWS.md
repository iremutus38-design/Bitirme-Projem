# Windows tarafı — RFID köprüsü

Bu klasördeki tek dosya `rfid_to_firebase.py`. Görevi:
**Anteni HTTP GET ile yokla → body'den UID'leri çıkar → Firebase'e yaz.**

Mimari:
```
[Bu script] ──HTTP GET / (her ~250ms)──> [Anten 192.168.137.87:80]
     │                                          │
     │                              body'de UID(ler) text olarak
     v
[Firebase: rfid_events/]
     │
     v
[Mac yoklama: attend.py]
```

Mac tarafındaki `attend.py` Firebase'i zaten dinliyor, orada kod değişikliği yok.

## Kurulum (tek seferlik)

1. Bu `rfid_windows/` klasörünü Windows makinesine kopyala.
2. Mac'teki `serviceAccountKey.json` dosyasını da bu klasöre koy.
3. cmd / PowerShell aç:
   ```
   cd C:\path\to\rfid_windows
   pip install -r requirements.txt
   ```

## Anten IP'sini değiştirme

Default: `192.168.137.87`. Değiştirmek istersen iki yol:

**a) Kodda:** `rfid_to_firebase.py` dosyasının başında:
```python
ANTENNA_HOST = os.environ.get("ANTENNA_HOST", "192.168.137.87")
```
buradaki IP'yi değiştir.

**b) Çalıştırırken:**
```
python rfid_to_firebase.py --antenna-host 192.168.137.87 test
```

## Üç mod, sırayla kullan

### 1) `test` — Anteni doğru okuyor muyuz?

```
python rfid_to_firebase.py test
```

Firebase'e **hiçbir şey yazmaz**. Çıktı:
```
[poller] BAGLANTI OK - polling basladi (0.25sn)
[test] UID: e2806894000050176005b4db
```

UID düşmüyorsa:
- IP yanlış olabilir (`--antenna-host 192.168.137.XX`)
- Anten farklı bir path'te yayın yapıyor olabilir (`--antenna-path /data` gibi)
- Body içindeki format 24-hex değil olabilir — bana ham body örneğini ver, regex'i ayarlayalım

### 2) `enroll` — Kartları öğrencilere ata (yılın başında bir kere)

```
python rfid_to_firebase.py enroll
```

Akış:
1. Firebase'den RFID kartı olmayan öğrencileri listeler.
2. Listeden bir numara seç.
3. O öğrencinin kartını antene yaklaştır.
4. İlk okunan UID o öğrenciye atanır.

### 3) `listen` — Ders zamanı çalışacak mod

```
python rfid_to_firebase.py listen
```

Sürekli açık tut. Her UID için `rfid_events/` altına push atar. Mac tarafı
otomatik tüketir.

## Firebase yapısı (referans)

```
rfid_events/{push_id}/
  uid:      "e2806894000050176005b4db"
  ts:       1716552120000
  device:   "main_door_antenna"
  consumed: false

rfid_index/
  e2806894000050176005b4db: "<ogrenci_uid>"

users/{uid}/
  rfid_uid: "e2806894000050176005b4db"
```

## Yapılandırma — environment variable

```
set ANTENNA_HOST=192.168.137.87
set ANTENNA_PORT=80
set ANTENNA_PATH=/
set POLL_INTERVAL_SEC=0.25
set RFID_DEVICE_ID=kapi_anten
set FIREBASE_DB_URL=https://<senin-projen>.firebaseio.com
```

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| `serviceAccountKey.json bulunamadi` | Mac'tekini bu klasöre kopyala |
| `[poller] hata: timeout` | IP yanlış ya da anten erişilemez |
| Test modu UID görüyor, listen Firebase'e atmıyor | DB URL'yi kontrol et |
| Mac yoklama ekranında RFID OK gelmiyor | Mac'in `config.py`'da `FIREBASE_RFID_DEVICE_FILTER` boş olsun |
