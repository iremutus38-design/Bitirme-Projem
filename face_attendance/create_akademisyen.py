"""
Akademisyen hesabı oluşturur.

Kullanım:
    python create_akademisyen.py
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

    print("=== Akademisyen Hesabi Olustur ===\n")

    email = input("E-posta (orn: ahmet.yilmaz@neu.edu.tr): ").strip().lower()
    if "@" not in email:
        print("Gecersiz e-posta.")
        return 1

    password = input("Sifre (en az 6 karakter): ").strip()
    if len(password) < 6:
        print("Sifre cok kisa.")
        return 1

    ad_soyad = input("Ad Soyad (orn: Dr. Ahmet Yilmaz): ").strip() or "Akademisyen"
    okul_no  = input("Sicil No (orn: AKD001): ").strip() or "AKD001"
    bolum    = input("Bolum (orn: Bilgisayar Muhendisligi): ").strip() or "Belirtilmedi"
    unvan    = input("Unvan (orn: Dr. Ogr. Uyesi): ").strip() or ""

    # 1) Auth kullanıcısı oluştur
    try:
        user = auth.create_user(email=email, password=password, display_name=ad_soyad)
        print(f"\n[OK] Auth kullanicisi olusturuldu: {user.uid}")
    except auth.EmailAlreadyExistsError:
        user = auth.get_user_by_email(email)
        auth.update_user(user.uid, password=password)
        print(f"\n[OK] Var olan kullanici bulundu, sifre guncellendi: {user.uid}")

    # 2) academic_users altına yaz (main.dart önce buraya bakıyor)
    db.reference(f"academic_users/{user.uid}").update({
        "email": email,
        "ad_soyad": ad_soyad,
        "okul_no": okul_no,
        "bolum": bolum,
        "unvan": unvan,
        "roller": {"akademisyen": True},
        "olusturma_tarihi": int(time.time() * 1000),
    })
    print(f"[OK] academic_users/{user.uid} altina yazildi (rol: akademisyen)")

    print("\n=== Hazir ===")
    print("Giris bilgilerin:")
    print(f"  E-posta  : {email}")
    print(f"  Sicil No : {okul_no}")
    print(f"  Sifre    : {password}")
    print("\nUygulamayi ac, bu bilgilerle giris yap → Akademisyen Paneli acilir.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
