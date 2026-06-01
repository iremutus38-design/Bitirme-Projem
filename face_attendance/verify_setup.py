"""
Kurulumu doğrulayan teşhis aracı.

Sırayla kontrol eder:
    1. Gerekli Python paketleri kurulu mu
    2. serviceAccountKey.json var ve okunabilir mi
    3. Firebase Realtime DB'ye bağlanabiliyor muyuz (URL doğru mu)
    4. macOS kamera erişimi var mı, webcam açılıyor mu
    5. RFID stdin okuyucusu çalışıyor mu

Kullanım:
    python verify_setup.py
    python verify_setup.py --skip-camera     (kameradan kaçın)
    python verify_setup.py --skip-rfid       (RFID testini atla)
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
RESET = "\033[0m"


def ok(msg: str) -> None:
    print(f"  {GREEN}OK{RESET}  {msg}")


def fail(msg: str, hint: str = "") -> None:
    print(f"  {RED}HATA{RESET}  {msg}")
    if hint:
        print(f"        {YELLOW}{hint}{RESET}")


def warn(msg: str) -> None:
    print(f"  {YELLOW}UYARI{RESET}  {msg}")


def step(title: str) -> None:
    print(f"\n[ {title} ]")


def check_packages() -> bool:
    step("1. Python paketleri")
    needed = [
        ("face_recognition", "face-recognition"),
        ("cv2", "opencv-python"),
        ("firebase_admin", "firebase-admin"),
        ("numpy", "numpy"),
    ]
    all_ok = True
    for mod, pip_name in needed:
        try:
            __import__(mod)
            ok(f"{mod} yüklü")
        except ImportError as exc:
            all_ok = False
            fail(f"{mod} eksik: {exc}", f"pip install {pip_name}")
    return all_ok


def check_service_account() -> bool:
    step("2. Service Account Key")
    import config
    if not config.SERVICE_ACCOUNT_KEY.exists():
        fail(
            f"{config.SERVICE_ACCOUNT_KEY} bulunamadi",
            "Firebase Console > Project Settings > Service Accounts > Generate Key",
        )
        return False
    ok(f"Dosya mevcut: {config.SERVICE_ACCOUNT_KEY}")
    return True


def check_firebase_connection() -> bool:
    step("3. Firebase Realtime DB bağlantısı")
    import config
    print(f"  URL: {config.FIREBASE_DB_URL}")
    try:
        import firebase_client
        firebase_client.init()
        from firebase_admin import db
        # Mevcut yapıyı tara - hem bağlantıyı test eder hem özet verir
        users = db.reference("users").get() or {}
        academic = db.reference("academic_users").get() or {}
        on_kayit = db.reference("on_kayitlar").get() or {}
        ok("Firebase'e bağlanıldı")
        print(f"  users:           {len(users) if isinstance(users, dict) else 0} kayıt")
        print(f"  academic_users:  {len(academic) if isinstance(academic, dict) else 0} kayıt")
        print(f"  on_kayitlar:     {len(on_kayit) if isinstance(on_kayit, dict) else 0} ön kayıt")
        return True
    except Exception as exc:
        msg = str(exc)
        fail(f"Firebase bağlantı hatası: {msg}")
        if "no such" in msg.lower() or "not found" in msg.lower() or "404" in msg:
            print(f"  {YELLOW}URL büyük ihtimalle yanlış. config.py'de FIREBASE_DB_URL'yi şununla deneyin:{RESET}")
            print(f"  https://finalproject-eb873-default-rtdb.europe-west1.firebasedatabase.app")
        elif "permission" in msg.lower():
            print(f"  {YELLOW}DB kuralları yazma izni vermiyor. Firebase Console > Rules{RESET}")
        return False


def check_camera() -> bool:
    step("4. Kamera erişimi")
    try:
        import cv2
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            fail(
                "Kamera açılamadı",
                "macOS: System Settings > Privacy & Security > Camera > Terminal/Python'a izin ver",
            )
            return False
        ret, frame = cap.read()
        cap.release()
        if not ret:
            fail("Kamera açıldı ama frame okunamadı")
            return False
        h, w = frame.shape[:2]
        ok(f"Kamera çalışıyor ({w}x{h})")
        return True
    except Exception as exc:
        fail(f"Kamera testi hata verdi: {exc}")
        return False


def check_rfid() -> bool:
    step("5. RFID okuyucu (stdin modu)")
    import config
    print(f"  Tip: {config.RFID_READER_TYPE}")
    if config.RFID_READER_TYPE != "stdin":
        warn(f"Bu test sadece 'stdin' modunda anlamlı; mevcut: {config.RFID_READER_TYPE}")
        return True
    print(f"  {YELLOW}Test: aşağıya bir UID yazıp Enter'a basın (örn: A4B72F19), boş bırakırsanız atlanır:{RESET}")
    try:
        line = input("  UID > ").strip().upper()
    except (EOFError, KeyboardInterrupt):
        warn("RFID testi atlandı")
        return True
    if not line:
        warn("RFID testi atlandı (boş giriş)")
        return True
    ok(f"UID okundu: {line}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-camera", action="store_true")
    parser.add_argument("--skip-rfid", action="store_true")
    args = parser.parse_args()

    print("Yoklama Sistemi - Kurulum Doğrulama")
    print("=" * 50)

    results = {
        "Paketler": check_packages(),
        "Service Account": check_service_account(),
    }
    # Paketler eksikse devam etmenin anlamı yok
    if not results["Paketler"]:
        print(f"\n{RED}Önce eksik paketleri kurun.{RESET}")
        return 1
    if not results["Service Account"]:
        print(f"\n{RED}serviceAccountKey.json eksik.{RESET}")
        return 1

    results["Firebase"] = check_firebase_connection()
    if not args.skip_camera:
        results["Kamera"] = check_camera()
    if not args.skip_rfid:
        results["RFID"] = check_rfid()

    print("\n" + "=" * 50)
    print("Özet:")
    for name, val in results.items():
        marker = f"{GREEN}OK{RESET}" if val else f"{RED}HATA{RESET}"
        print(f"  {marker:6}  {name}")

    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
