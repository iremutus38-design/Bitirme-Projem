"""
Öğrenci hesabı oluşturur.

Kullanım:
    python create_ogrenci.py
"""

from __future__ import annotations

import sys
import time

import firebase_admin
from firebase_admin import credentials, auth, db

import config


def main() -> int:
    if not config.SERVICE_ACCOUNT_KEY.exists():
        print(f"HATA: {config.SERVICE_ACCOUNT_KEY} bulunamadi", file=sys.stderr)
        return 1

    # Firebase zaten başlatılmışsa yeniden başlatma
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(
            credentials.Certificate(str(config.SERVICE_ACCOUNT_KEY)),
            {"databaseURL": config.FIREBASE_DB_URL},
        )

    print("=== Ogrenci Hesabi Olustur ===\n")

    email   = input("E-posta (orn: 2021123456@ogr.neu.edu.tr): ").strip().lower()
    if "@" not in email:
        print("Gecersiz e-posta.")
        return 1

    password = input("Sifre (en az 6 karakter): ").strip()
    if len(password) < 6:
        print("Sifre cok kisa.")
        return 1

    ad_soyad = input("Ad Soyad (orn: Ali Veli): ").strip() or "Ogrenci"
    okul_no  = input("Ogrenci No (orn: 2021123456): ").strip() or "0000000"
    bolum    = input("Bolum (orn: Bilgisayar Muhendisligi): ").strip() or "Belirtilmedi"

    sinif_str = input("Sinif (1-4) [1]: ").strip() or "1"
    try:
        sinif = int(sinif_str)
    except ValueError:
        sinif = 1

    # 1) Auth kullanıcısı oluştur
    try:
        user = auth.create_user(email=email, password=password, display_name=ad_soyad)
        print(f"\n[OK] Auth kullanicisi olusturuldu: {user.uid}")
    except auth.EmailAlreadyExistsError:
        user = auth.get_user_by_email(email)
        auth.update_user(user.uid, password=password)
        print(f"\n[OK] Var olan kullanici bulundu, sifre guncellendi: {user.uid}")

    # 2) users altına yaz (öğrenci paneli buradan okur)
    db.reference(f"users/{user.uid}").update({
        "email": email,
        "ad_soyad": ad_soyad,
        "okul_no": okul_no,
        "bolum": bolum,
        "sinif": sinif,
        "alinan_dersler": [],
        "roller": {"öğrenci": True},
        "olusturma_tarihi": int(time.time() * 1000),
    })
    print(f"[OK] users/{user.uid} altina yazildi (rol: ogrenci)")

    print("\n=== Hazir ===")
    print("Giris bilgilerin:")
    print(f"  E-posta    : {email}")
    print(f"  Ogrenci No : {okul_no}")
    print(f"  Sifre      : {password}")
    print("\nUygulamayi ac, bu bilgilerle giris yap → Ogrenci Paneli acilir.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
