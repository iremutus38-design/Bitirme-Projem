"""
Ön kayıttaki tüm öğrencilere Firebase Auth hesabı açar.

  - on_kayitlar/{tc} → her öğrenci için hesap oluşturur
  - Email   : {okul_no}@ogr.neu.edu.tr
  - Şifre   : Ogrenci2026  (öğrenci sonradan değiştirebilir)
  - users/{uid} altına öğrenci verisini yazar (tc dahil)
  - on_kayitlar/{tc}/uid alanını günceller

Kullanım:
    cd /Users/iremutusmac/face_attendance
    source venv/bin/activate
    python create_accounts_from_on_kayitlar.py
"""

from __future__ import annotations

import sys
import time

import firebase_admin
from firebase_admin import credentials, auth, db

import config

DEFAULT_PASSWORD = "Ogrenci2026"


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

    print("=== Ön Kayıt → Firebase Auth Hesap Açma ===\n")
    print(f"Varsayılan şifre: {DEFAULT_PASSWORD}\n")

    on_kayitlar = db.reference("on_kayitlar").get()
    if not on_kayitlar:
        print("on_kayitlar boş veya bulunamadı.")
        return 1

    toplam = len(on_kayitlar)
    basarili = 0
    atlandı = 0
    hatali = 0

    for tc, data in on_kayitlar.items():
        if not isinstance(data, dict):
            continue

        ad_soyad = data.get("ad_soyad", "").strip() or "Öğrenci"
        okul_no  = str(data.get("okul_no", "")).strip()
        bolum    = data.get("bolum", "").strip() or "Belirtilmedi"
        alinan_dersler = data.get("alinan_dersler", [])
        rfid_uid = data.get("rfid_uid", "")
        face_encoding = data.get("face_encoding", "")

        if not okul_no:
            print(f"[ATLA] TC={tc} → okul_no yok")
            atlandı += 1
            continue

        email = f"{okul_no}@ogr.neu.edu.tr"

        try:
            # Auth hesabı oluştur (varsa şifreyi güncelle)
            try:
                user = auth.create_user(
                    email=email,
                    password=DEFAULT_PASSWORD,
                    display_name=ad_soyad,
                )
                print(f"[YENİ] {ad_soyad} ({okul_no}) → uid={user.uid}")
            except auth.EmailAlreadyExistsError:
                user = auth.get_user_by_email(email)
                auth.update_user(user.uid, password=DEFAULT_PASSWORD)
                print(f"[VAR ] {ad_soyad} ({okul_no}) → uid={user.uid} (şifre güncellendi)")

            uid = user.uid

            # users/{uid} altına yaz
            user_data: dict = {
                "email":          email,
                "ad_soyad":       ad_soyad,
                "okul_no":        okul_no,
                "bolum":          bolum,
                "tc":             tc,
                "alinan_dersler": alinan_dersler if isinstance(alinan_dersler, list) else [],
                "roller":         {"öğrenci": True},
                "olusturma_tarihi": int(time.time() * 1000),
            }
            if rfid_uid:
                user_data["rfid_uid"] = rfid_uid
            if face_encoding:
                user_data["face_encoding"] = face_encoding

            db.reference(f"users/{uid}").update(user_data)

            # on_kayitlar/{tc}/uid alanını güncelle (geri referans)
            db.reference(f"on_kayitlar/{tc}").update({"uid": uid})

            basarili += 1

        except Exception as e:
            print(f"[HATA] TC={tc} ({ad_soyad}): {e}")
            hatali += 1

    print(f"\n{'='*44}")
    print(f"Toplam   : {toplam}")
    print(f"Başarılı : {basarili}")
    print(f"Atlandı  : {atlandı}")
    print(f"Hatalı   : {hatali}")
    print(f"{'='*44}")
    print(f"\nÖğrenciler artık şu bilgilerle giriş yapabilir:")
    print(f"  E-posta : {{okul_no}}@ogr.neu.edu.tr")
    print(f"  Şifre   : {DEFAULT_PASSWORD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
