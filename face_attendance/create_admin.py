"""
Admin / test hesabı oluşturur.

Üç mod var:
  1) Sadece idari (default)
  2) 3 rol birden (idari + akademisyen + öğrenci) — tek hesapla tüm panelleri test et
  3) Sadece istediğin rol(ler)

Sadece bir kere çalıştır.

Kullanım:
    python create_admin.py
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

    firebase_admin.initialize_app(
        credentials.Certificate(str(config.SERVICE_ACCOUNT_KEY)),
        {"databaseURL": config.FIREBASE_DB_URL},
    )

    print("=== Idari Admin Hesabi Olustur ===\n")
    email = input("E-posta (orn: admin@neu.edu.tr): ").strip().lower()
    if "@" not in email:
        print("Gecersiz e-posta.")
        return 1

    password = input("Sifre (en az 6 karakter): ").strip()
    if len(password) < 6:
        print("Sifre cok kisa.")
        return 1

    ad_soyad = input("Ad Soyad (orn: Test Admin): ").strip() or "Admin"

    print("\nHangi roller olsun? (giris sonrasi panel secim ekrani cikar)")
    print("  1) Sadece idari (default)")
    print("  2) 3'u birden: idare + akademisyen + ogrenci  -- tum panelleri test")
    print("  3) Ozel: virgulle yaz (orn: idare,akademisyen)")
    sec = input("Secim [1/2/3]: ").strip() or "1"

    if sec == "2":
        roller = {"idare": True, "akademisyen": True, "öğrenci": True}
    elif sec == "3":
        ozel = input("Roller (virgulle): ").strip().lower()
        roller = {r.strip(): True for r in ozel.split(",") if r.strip()}
        if not roller:
            print("Hicbir rol verilmedi, default'a donuyorum.")
            roller = {"idare": True}
    else:
        roller = {"idare": True}

    # 1) Auth user olustur (varsa onu kullan)
    try:
        user = auth.create_user(email=email, password=password, display_name=ad_soyad)
        print(f"\n[OK] Auth kullanicisi olusturuldu: {user.uid}")
    except auth.EmailAlreadyExistsError:
        user = auth.get_user_by_email(email)
        auth.update_user(user.uid, password=password)
        print(f"\n[OK] Var olan kullanici bulundu, sifre guncellendi: {user.uid}")

    # 2) academic_users altına yaz — main.dart once buraya bakiyor
    db.reference(f"academic_users/{user.uid}").update({
        "email": email,
        "ad_soyad": ad_soyad,
        "okul_no": "ADMIN001",  # giris formundan okul_no ile de girebilesin
        "roller": roller,
        "olusturma_tarihi": int(time.time() * 1000),
    })
    print(f"[OK] academic_users/{user.uid}: {list(roller.keys())}")

    # 3) Eger ogrenci rolu de varsa, users/{uid} altina minimal kayit yaz
    # (ogrenci paneli alinan_dersler vb okumaya calisirken patlamasin)
    if "öğrenci" in roller:
        db.reference(f"users/{user.uid}").update({
            "email": email,
            "ad_soyad": ad_soyad,
            "okul_no": "ADMIN001",
            "bolum": "Test",
            "sinif": 1,
            "alinan_dersler": [],
            "roller": {"öğrenci": True},
            "olusturma_tarihi": int(time.time() * 1000),
        })
        print(f"[OK] users/{user.uid} altina ogrenci kaydi yazildi")

    print("\n=== Hazir ===")
    print(f"Giris bilgilerin:")
    print(f"  E-posta veya okul_no : {email}  /  ADMIN001")
    print(f"  Sifre                : {password}")
    print(f"  Roller               : {list(roller.keys())}")
    print(f"\nUygulamayi telefonda ac, bu bilgilerle giris yap.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
