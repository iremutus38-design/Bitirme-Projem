"""
academic_users/{uid}/verilen_dersler içindeki tekrar eden dersleri temizler.
String ve Map formatını birleştirir, normalize ederek tekrarları siler.

Kullanım:
    python temizle_verilen_dersler.py
"""
import sys
import firebase_admin
from firebase_admin import credentials, db
import config

def tr_norm(s):
    return (s
        .replace('İ','i').replace('I','i').replace('ı','i')
        .replace('Ğ','g').replace('ğ','g').replace('Ş','s').replace('ş','s')
        .replace('Ö','o').replace('ö','o').replace('Ü','u').replace('ü','u')
        .replace('Ç','c').replace('ç','c')
        .lower().strip()
    )

def main():
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(
            credentials.Certificate(str(config.SERVICE_ACCOUNT_KEY)),
            {"databaseURL": config.FIREBASE_DB_URL},
        )

    akademisyenler = db.reference("academic_users").get()
    if not akademisyenler:
        print("Veri bulunamadı.")
        return

    for uid, data in akademisyenler.items():
        if not isinstance(data, dict):
            continue
        raw = data.get("verilen_dersler", [])
        if not raw:
            continue

        # Tüm formatları string'e çevir
        dersler = []
        if isinstance(raw, list):
            for d in raw:
                if isinstance(d, str) and d.strip():
                    dersler.append(d.strip())
                elif isinstance(d, dict):
                    ad = d.get('ad') or d.get('ders_adi') or ''
                    if ad.strip():
                        dersler.append(ad.strip())
        elif isinstance(raw, dict):
            for d in raw.values():
                if isinstance(d, str) and d.strip():
                    dersler.append(d.strip())
                elif isinstance(d, dict):
                    ad = d.get('ad') or d.get('ders_adi') or ''
                    if ad.strip():
                        dersler.append(ad.strip())

        # Normalize ederek tekrarları sil, orijinal adı koru
        seen = {}
        temiz = []
        for d in dersler:
            key = tr_norm(d)
            if key not in seen:
                seen[key] = True
                temiz.append(d)

        ad_soyad = data.get('ad_soyad', uid)
        if len(temiz) != len(dersler):
            db.reference(f"academic_users/{uid}").update({"verilen_dersler": temiz})
            print(f"[+] {ad_soyad}: {len(dersler)} → {len(temiz)} ders")
        else:
            print(f"[=] {ad_soyad}: zaten temiz ({len(temiz)} ders)")

    print("\nTamamlandı.")

if __name__ == "__main__":
    main()
