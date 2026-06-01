"""
fix_oturma_tc.py
================
Mevcut sinav_takvimi/*/derslik_atamalari/*/oturma_plani kayıtlarına
tc_no alanı ekler.

Kaynak: sinav_takvimi/{kod}/ogrenciler/{ogrNo}/tc_no
Hedef : sinav_takvimi/{kod}/derslik_atamalari/[i]/oturma_plani/{ogrNo}/tc_no

Kullanım:
    cd /Users/iremutusmac/face_attendance
    source venv/bin/activate
    python fix_oturma_tc.py
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import firebase_client
firebase_client.init()
from firebase_admin import db

def main():
    print("sinav_takvimi okunuyor...")
    sinav_data = db.reference("sinav_takvimi").get() or {}
    updates = {}
    guncellenen = 0

    for kod, sinav in sinav_data.items():
        if not isinstance(sinav, dict):
            continue

        # ogrenciler: {ogrNo: {ad_soyad, tc_no, sinif}}
        ogrenciler = sinav.get("ogrenciler", {}) or {}
        # ogrNo → tc eşlemesi
        ogr_tc = {
            str(ogr_no): str(ogr_data.get("tc_no", ""))
            for ogr_no, ogr_data in ogrenciler.items()
            if isinstance(ogr_data, dict) and ogr_data.get("tc_no")
        }

        atamalar = sinav.get("derslik_atamalari", []) or []
        if not isinstance(atamalar, list):
            continue

        for i, atama in enumerate(atamalar):
            if not isinstance(atama, dict):
                continue
            oturmalar = atama.get("oturma_plani", {}) or {}
            if not isinstance(oturmalar, dict):
                continue

            for ogr_no, kayit in oturmalar.items():
                if not isinstance(kayit, dict):
                    continue
                if kayit.get("tc_no"):
                    continue  # zaten var

                tc = ogr_tc.get(str(ogr_no), "")
                if tc:
                    path = f"sinav_takvimi/{kod}/derslik_atamalari/{i}/oturma_plani/{ogr_no}/tc_no"
                    updates[path] = tc
                    guncellenen += 1

    if not updates:
        print("Güncellenecek kayıt yok (zaten tc_no mevcut ya da eşleşme bulunamadı).")
        return

    print(f"{guncellenen} kayıt güncellenecek, Firebase'e yazılıyor...")
    # 500'lük gruplarda yaz
    items = list(updates.items())
    for start in range(0, len(items), 500):
        batch = dict(items[start:start+500])
        db.reference().update(batch)
        print(f"  {min(start+500, len(items))}/{len(items)} yazıldı")

    print(f"\nTamamlandı. {guncellenen} oturma kaydına tc_no eklendi.")

if __name__ == "__main__":
    main()
