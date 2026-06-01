"""
Yoklama sistemi konfigürasyonu.

Tüm sabit ayarlar burada tutulur. Geliştirme/sunum ortamına göre değiştirilir.
"""

import os
from pathlib import Path

# --- Genel yollar ---
BASE_DIR = Path(__file__).resolve().parent
SERVICE_ACCOUNT_KEY = BASE_DIR / "serviceAccountKey.json"
FACES_DIR = BASE_DIR / "faces"  # Referans yüz fotoğrafları (yerel yedek)
FACES_DIR.mkdir(exist_ok=True)

# --- Firebase ---
# Firebase Console > Realtime Database üst başlıkta URL gözükür.
# Genelde şu iki formdan biri olur:
#   https://<project-id>-default-rtdb.firebaseio.com
#   https://<project-id>-default-rtdb.europe-west1.firebasedatabase.app
# Yanlış URL verirseniz "Reference.set failed: permission_denied" değil,
# "no such database" hatası alırsınız - o zaman europe-west1 olanı deneyin.
FIREBASE_DB_URL = os.environ.get(
    "FIREBASE_DB_URL",
    "https://finalproject-eb873-default-rtdb.firebaseio.com",
)

# --- Yüz tanıma parametreleri ---
# face_recognition.compare_faces eşiği. 0.6 default, daha düşük = daha sıkı.
FACE_MATCH_TOLERANCE = 0.5

# Kameradan kaç frame'i atlayarak işlem yapalım (CPU yükü için).
FRAME_PROCESS_EVERY_N = 3

# face_recognition modeli: "hog" (CPU, hızlı) veya "cnn" (GPU, doğru).
FACE_DETECTION_MODEL = "hog"

# Aynı öğrenci için iki tanıma arasındaki minimum süre (saniye).
# Bu süreden önce tekrar yazma yapılmaz - aşırı yazmayı engeller.
FACE_REWRITE_COOLDOWN_SEC = 5

# --- Cihaz kimliği ---
# Her cihaz farklı olur. Şimdilik MacBook için sabit; sınıf cihazları için
# environment variable ile override edilir.
DEVICE_ID = os.environ.get("ATTENDANCE_DEVICE_ID", "macbook_dev")
DERSLIK_ID = os.environ.get("ATTENDANCE_DERSLIK_ID", "dev_room")

# --- RFID ---
# Seçenekler:
#   "stdin"    - klavyeden UID yazıp Enter (geliştirme / manuel test)
#   "mock"     - MOCK_RFID_UIDS'tan otomatik UID basar (donanım yokken demo)
#   "serial"   - Arduino+RC522 USB seri portundan okur
#   "firebase" - Windows server / ESP32-WiFi anten senaryosu için.
#                Anten ESP32'den TCP:3000'e gönderir, Windows app Firebase'e
#                yazar, biz rfid_events/ düğümünü dinleriz.
# Mevcut donanım kurulumunuz "firebase" tipini kullanır.
RFID_READER_TYPE = os.environ.get("RFID_READER_TYPE", "stdin")

# Birden fazla anten/cihaz olursa sadece belirli birinin event'lerini dinle.
# Boş ise tüm event'ler dinlenir.
FIREBASE_RFID_DEVICE_FILTER = os.environ.get("FIREBASE_RFID_DEVICE_FILTER", "") or None
RFID_SERIAL_PORT = os.environ.get("RFID_SERIAL_PORT", "/dev/tty.usbmodem")
RFID_SERIAL_BAUD = int(os.environ.get("RFID_SERIAL_BAUD", "9600"))

# Mock reader için sahte UID havuzu. Donanım yokken demo/sunum için.
# Her interval saniyede listeden sıradaki UID'yi "okumuş" gibi davranır.
MOCK_RFID_UIDS = [
    "TEST001",
    "TEST002",
    "TEST003",
    "TEST004",
]
MOCK_RFID_INTERVAL_SEC = float(os.environ.get("MOCK_RFID_INTERVAL_SEC", "8.0"))
