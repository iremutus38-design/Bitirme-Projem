"""
sync_ogrenciler.py
==================
on_kayitlar içindeki öğrencileri, aldıkları derslerle eşleşen
sinav_takvimi/{kod}/ogrenciler listesine ekler.

Mevcut kayıtlara dokunmaz, sadece eksik olanları ekler.

Kullanım:
    cd /Users/iremutusmac/face_attendance
    source venv/bin/activate
    python sync_ogrenciler.py
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import firebase_client
firebase_client.init()
from firebase_admin import db


def tr_norm(s: str) -> str:
    """Türkçe karakterleri normalize et, küçük harfe çevir."""
    tablo = str.maketrans("İIĞŞÖÜÇığşöüç", "iigsoucigsouc")
    return s.translate(tablo).lower().strip()


def main():
    print("on_kayitlar okunuyor...")
    kayitlar = db.reference("on_kayitlar").get() or {}

    print("sinav_takvimi okunuyor...")
    sinav_data = db.reference("sinav_takvimi").get() or {}

    # sinav_takvimi: ders_adi normalleştirilmiş → {kod, ders_adi}
    sinav_index: dict[str, list[str]] = {}  # norm_ders_adi → [kod, ...]
    for kod, sinav in sinav_data.items():
        if not isinstance(sinav, dict):
            continue
        ders_adi = sinav.get("ders_adi", "").strip()
        if not ders_adi:
            continue
        norm = tr_norm(ders_adi)
        sinav_index.setdefault(norm, []).append(kod)

    updates = {}
    eklenen = 0
    atlanan = 0

    for tc, kayit in kayitlar.items():
        if not isinstance(kayit, dict):
            continue

        ad_soyad = kayit.get("ad_soyad") or kayit.get("isim", "")
        okul_no  = kayit.get("okul_no", "")
        sinif    = kayit.get("sinif", "")
        alinan   = kayit.get("alinan_dersler", []) or []

        if not okul_no:
            print(f"  [ATLA] TC={tc} — okul_no yok")
            atlanan += 1
            continue

        for ders in alinan:
            if not isinstance(ders, dict):
                continue
            ders_adi = ders.get("ders_adi", "").strip()
            if not ders_adi:
                continue
            norm = tr_norm(ders_adi)
            kodlar = sinav_index.get(norm, [])
            if not kodlar:
                continue

            for kod in kodlar:
                # Zaten varsa atlat
                sinav = sinav_data.get(kod, {})
                ogrenciler = sinav.get("ogrenciler", {}) or {}
                if str(okul_no) in ogrenciler:
                    continue

                path = f"sinav_takvimi/{kod}/ogrenciler/{okul_no}"
                updates[path] = {
                    "ad_soyad": ad_soyad,
                    "tc_no":    str(tc),
                    "sinif":    sinif,
                }
                print(f"  + {ad_soyad} ({okul_no}) → {ders_adi} [{kod}]")
                eklenen += 1

    if not updates:
        print("\nEklenecek öğrenci yok. Tüm öğrenciler zaten kayıtlı.")
        return

    print(f"\n{eklenen} kayıt Firebase'e yazılıyor...")
    items = list(updates.items())
    for start in range(0, len(items), 500):
        batch = dict(items[start:start+500])
        db.reference().update(batch)
        print(f"  {min(start+500, len(items))}/{len(items)} yazıldı")

    print(f"\nTamamlandı. {eklenen} öğrenci sınav listelerine eklendi.")
    if atlanan:
        print(f"  ({atlanan} öğrenci okul_no eksik olduğu için atlandı)")


if __name__ == "__main__":
    main()
