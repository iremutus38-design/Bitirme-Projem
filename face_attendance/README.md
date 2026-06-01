# Yoklama Sistemi - Python Servisi

Yüz tanıma + RFID ile iki aşamalı yoklama. Bitirme projesinin Flutter
uygulamasıyla aynı Firebase Realtime Database'i paylaşır.

## İlk kurulum (tek seferlik)

```bash
cd ~/face_attendance
source venv/bin/activate

# Yeni paketleri kur (firebase-admin + opencv-python)
pip install -r requirements.txt

# (macOS) Kamera ve erişilebilirlik izinlerini ver:
#   System Settings → Privacy & Security → Camera → Terminal'i ekle
```

## Hızlı doğrulama

Önce her şeyin yerli yerinde olduğunu kontrol edin:

```bash
python verify_setup.py
```

Bu komut:
1. Gerekli paketleri kontrol eder
2. `serviceAccountKey.json` mevcut mu bakar
3. Firebase'e bağlanmayı dener (URL yanlışsa size hata mesajıyla söyler)
4. Kamerayı 1 frame için açar
5. RFID stdin okuyucusu için tek deneme yapar

Hepsi yeşilse devam edin. Firebase URL yanlışsa `config.py` içindeki
`FIREBASE_DB_URL`'i `europe-west1.firebasedatabase.app` formatına çevirin
veya env ile geçici override edin:

```bash
export FIREBASE_DB_URL="https://finalproject-eb873-default-rtdb.europe-west1.firebasedatabase.app"
```

## Kullanım

### Yüz tanıtma

İdari panelden öğrenci eklerken (veya manuel test için):

```bash
# Kamera açar, kullanıcı SPACE'e basana kadar bekler, encoding'i Firebase'e yazar
python main.py enroll --uid <ogrenci_firebase_uid>

# Önceden çekilmiş fotoğraf üzerinden
python main.py enroll --uid <uid> --photo /yol/foto.jpg

# Yüzü tanıttıktan sonra RFID kartı da bağla (stdin'e UID yazıp Enter)
python main.py enroll --uid <uid> --rfid

# Sadece RFID bağla (yüz zaten var)
python main.py enroll --uid <uid> --rfid-only
```

`--uid` 11 haneli sayısalsa **TC No olarak** kabul edilir ve
`on_kayitlar/<tc>/face_encoding` altına yazılır. Öğrenci kayıt olunca
mevcut `auth_page.dart` mantığı bunu `users/<uid>`'ye taşır.

### Yoklama

Akademisyen Flutter panelinden "Yoklama Başlat" deyince
`attendance_sessions/<id>/aktif=true` olur. Script bu durumda otomatik
devreye girer:

```bash
python main.py attend
```

Aktif oturumu kendi `DERSLIK_ID`'sine göre bekler. ESC veya Q ile çıkış.

### Debug

```bash
python main.py list   # face_encoding'i olan öğrencileri yazdırır
```

## Çevre değişkenleri

| Değişken | Varsayılan | Açıklama |
|----------|------------|----------|
| `FIREBASE_DB_URL` | `https://finalproject-eb873-default-rtdb.firebaseio.com` | Realtime DB URL'si |
| `ATTENDANCE_DEVICE_ID` | `macbook_dev` | Cihaz kimliği (loglarda görünür) |
| `ATTENDANCE_DERSLIK_ID` | `dev_room` | Cihazın bulunduğu derslik. Akademisyen yoklama başlatırken bu derslik ID'sini seçer. |
| `RFID_READER_TYPE` | `stdin` | `stdin` veya `serial` |
| `RFID_SERIAL_PORT` | `/dev/tty.usbmodem` | Arduino seri portu |

## Firebase yapısı

Script şu yolları okur/yazar:

```
users/{uid}/face_encoding          ← yazılır (enroll)
users/{uid}/rfid_uid               ← yazılır (enroll --rfid)
users/{uid}/face_photo_path        ← yazılır (enroll)
on_kayitlar/{tc}/face_encoding     ← yazılır (uid TC No formatındaysa)
rfid_index/{rfid_uid}              ← yazılır (ters arama tablosu)

attendance_sessions/{sid}          ← OKUNUR (Flutter yazar)
attendance_sessions/{sid}/records/{uid}/face_ok    ← yazılır
attendance_sessions/{sid}/records/{uid}/rfid_ok    ← yazılır
attendance_sessions/{sid}/records/{uid}/final_status ← yazılır
```

## Mimari notlar

- **Donanım soyutlaması:** RFID okuyucu `rfid_reader.py` içinde abstrakte.
  Şimdi `StdinRfidReader` (klavye) ve `SerialRfidReader` (Arduino+RC522)
  hazır. MFRC522'yi Raspberry Pi'de SPI'dan okumak için ek bir
  `MfrcRfidReader` sınıfı eklenebilir; `make_reader()` fabrikası
  `config.RFID_READER_TYPE`'a göre dağıtır.
- **Cihaz çoklaması:** Her cihaz `DERSLIK_ID` env'ı ile farklı bir
  dersliğe bağlanır. Akademisyen yoklama başlatırken hangi derslik
  seçildiyse o cihaz devreye girer.
- **Yüz encoding'i Firebase'de:** Pi'de yerel dosya saklamak yerine
  Firebase'e koyduk; bir cihazda tanıtılan yüz tüm cihazlardan görünür.
```
