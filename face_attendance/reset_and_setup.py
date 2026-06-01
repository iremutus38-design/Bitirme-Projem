"""
TEMIZ BASLANGIC scripti.

DIKKAT: Bu script Firebase'deki tum auth kullanicilarini, users,
academic_users, on_kayitlar, rfid_index, attendance_sessions
dugumlerini SILECEK. schedules ve courses dokunulmaz.

Sonra size yeni bir idari hesap olusturur. Email ve sifreyi
interaktif olarak siz girersiniz.

Calistirma:
    cd ~/face_attendance && source venv/bin/activate
    python reset_and_setup.py
"""

from __future__ import annotations

import getpass
import shutil
import sys
import time
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, db, auth


def main() -> int:
    print("=" * 60)
    print("  TEMIZ BASLANGIC")
    print("=" * 60)
    print()
    print("Bu script su islemleri yapacak:")
    print("  1. Firebase Auth'taki TUM kullanicilari SILECEK")
    print("  2. Realtime DB'den users/, academic_users/, on_kayitlar/,")
    print("     on_kayit_academic/, rfid_index/, attendance_sessions/")
    print("     rfid_events/ dugumlerini SILECEK (schedules dokunmaz)")
    print("  3. faces/ klasorundeki tum referans fotograflari silecek")
    print("  4. Size YENI bir idari hesap olusturacak")
    print()
    confirm = input("Devam etmek icin 'EVET' yazin (baska bir sey iptal eder): ").strip()
    if confirm != "EVET":
        print("Iptal edildi, hicbir sey degismedi.")
        return 0

    # --- Firebase init ---
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(
        cred,
        {"databaseURL": "https://finalproject-eb873-default-rtdb.firebaseio.com"},
    )

    # --- 1. Auth kullanicilarini sil ---
    print("\n[1/4] Firebase Auth kullanicilari siliniyor...")
    page = auth.list_users()
    deleted = 0
    while page:
        for user in page.users:
            try:
                auth.delete_user(user.uid)
                deleted += 1
                print(f"   sildim: {user.email or user.uid}")
            except Exception as exc:
                print(f"   HATA ({user.uid}): {exc}")
        page = page.get_next_page() if hasattr(page, "get_next_page") else None
    print(f"   Toplam {deleted} auth hesabi silindi.")

    # --- 2. RTDB dugumlerini sil ---
    print("\n[2/4] Realtime DB dugumleri siliniyor...")
    for node in [
        "users",
        "academic_users",
        "on_kayitlar",
        "on_kayit_academic",
        "rfid_index",
        "attendance_sessions",
        "rfid_events",
    ]:
        try:
            db.reference(node).delete()
            print(f"   silindi: /{node}")
        except Exception as exc:
            print(f"   HATA (/{node}): {exc}")

    # --- 3. faces/ klasorunu temizle ---
    print("\n[3/4] Yerel referans fotograflari siliniyor...")
    faces_dir = Path(__file__).parent / "faces"
    if faces_dir.exists():
        n = 0
        for p in faces_dir.iterdir():
            if p.is_file():
                p.unlink()
                n += 1
        print(f"   {n} fotograf silindi.")
    else:
        print("   faces/ klasoru yok, atlandi.")

    # --- 4. Yeni idari hesap olustur ---
    print("\n[4/4] Yeni IDARI hesap olusturuluyor.")
    print("Asagidaki bilgileri girin:\n")
    email = input("  Email (orn: iremutus38@gmail.com): ").strip()
    if not email or "@" not in email:
        print("Gecersiz email, iptal.")
        return 1

    ad_soyad = input("  Ad Soyad (orn: Irem Utus): ").strip()
    if not ad_soyad:
        ad_soyad = "Idari Kullanici"

    sifre = getpass.getpass("  Sifre (en az 6 karakter, ekranda gozukmez): ").strip()
    sifre2 = getpass.getpass("  Sifre tekrar: ").strip()
    if sifre != sifre2:
        print("Sifreler uyusmuyor, iptal.")
        return 1
    if len(sifre) < 6:
        print("Sifre cok kisa (en az 6 karakter), iptal.")
        return 1

    try:
        user = auth.create_user(
            email=email,
            password=sifre,
            display_name=ad_soyad,
        )
        print(f"   Auth hesabi olusturuldu: uid={user.uid}")
    except Exception as exc:
        print(f"   HATA: Auth hesabi olusturulamadi: {exc}")
        return 1

    # academic_users altina kaydet
    try:
        db.reference(f"academic_users/{user.uid}").set({
            "ad_soyad": ad_soyad,
            "email": email,
            "unvan": "Idari",
            "verilen_dersler": [],
            "roller": {"idare": True},
            "kayit_tarihi": int(time.time() * 1000),
        })
        print(f"   academic_users/{user.uid} olusturuldu.")
    except Exception as exc:
        print(f"   HATA: DB yazma: {exc}")
        return 1

    print("\n" + "=" * 60)
    print("  TAMAMLANDI")
    print("=" * 60)
    print(f"Yeni idari hesap:")
    print(f"  Email: {email}")
    print(f"  UID:   {user.uid}")
    print(f"  Rol:   idare")
    print()
    print("Flutter app'te bu email ve sifreyle giris yapabilirsiniz.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
