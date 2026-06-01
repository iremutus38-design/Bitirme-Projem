"""
İdari hesabı oluşturur veya onarır.
Kullanım: python create_idari.py
"""
from __future__ import annotations
import sys, time
import firebase_admin
from firebase_admin import credentials, auth, db
import config

def main() -> int:
    if not config.SERVICE_ACCOUNT_KEY.exists():
        print(f"HATA: {config.SERVICE_ACCOUNT_KEY} bulunamadi", file=sys.stderr)
        return 1

    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(
            credentials.Certificate(str(config.SERVICE_ACCOUNT_KEY)),
            {"databaseURL": config.FIREBASE_DB_URL},
        )

    print("=== İdari Hesap Olustur / Onar ===\n")

    email    = input("E-posta [idari@neu.edu.tr]: ").strip().lower() or "idari@neu.edu.tr"
    password = input("Sifre (en az 6 karakter): ").strip()
    if len(password) < 6:
        print("Sifre cok kisa.")
        return 1
    ad_soyad = input("Ad Soyad [İdari Kullanici]: ").strip() or "İdari Kullanici"

    # Auth kullanıcısı oluştur veya güncelle
    try:
        user = auth.create_user(email=email, password=password, display_name=ad_soyad)
        print(f"\n[OK] Auth kullanicisi olusturuldu: {user.uid}")
    except auth.EmailAlreadyExistsError:
        user = auth.get_user_by_email(email)
        auth.update_user(user.uid, password=password)
        print(f"\n[OK] Var olan kullanici bulundu, sifre guncellendi: {user.uid}")

    # academic_users'a idare rolüyle yaz
    db.reference(f"academic_users/{user.uid}").set({
        "email": email,
        "ad_soyad": ad_soyad,
        "unvan": "",
        "verilen_dersler": [],
        "roller": {"idare": True},
        "olusturma_tarihi": int(time.time() * 1000),
    })
    print(f"[OK] academic_users/{user.uid} → roller: {{idare: true}}")
    print(f"\nGiris: {email}  /  Sifre: {password}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
