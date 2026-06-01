"""
Excel sınav listesindeki hoca-ders eşleşmelerini Firebase'deki
academic_users/{uid}/verilen_dersler ile senkronize eder.

Sadece EKSİK dersleri ekler — mevcut veriye dokunmaz.

Kullanım:
    cd /Users/iremutusmac/face_attendance
    source venv/bin/activate
    python sync_akademisyen_dersler.py
"""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

import openpyxl
import firebase_admin
from firebase_admin import credentials, db

import config

# Excel dosyasının yolu — bu scriptle aynı klasörde olmalı ya da tam yol ver
EXCEL_PATH = Path(__file__).parent / "sinav_listesi.xlsx"


def tr_norm(s: str) -> str:
    return (s
        .replace('İ', 'i').replace('I', 'i').replace('ı', 'i')
        .replace('Ğ', 'g').replace('ğ', 'g')
        .replace('Ş', 's').replace('ş', 's')
        .replace('Ö', 'o').replace('ö', 'o')
        .replace('Ü', 'u').replace('ü', 'u')
        .replace('Ç', 'c').replace('ç', 'c')
        .lower().strip()
    )


def hoca_eslesiyor(fb_ad: str, excel_ad: str) -> bool:
    """Firebase ad_soyad ile Excel hoca adını karşılaştırır."""
    # Unvan öneklerini temizle
    unvanlar = {'prof.dr.', 'doc.dr.', 'doç.dr.', 'yrd.doc.dr.', 'yrd.doç.dr.',
                'dr.ogr.uyesi', 'dr.öğr.üyesi', 'dr.', 'ogr.gor.dr.', 'öğr.gör.dr.',
                'ogr.gor.', 'öğr.gör.', 'prof.', 'doç.', 'doc.'}

    def temizle(s: str) -> str:
        n = tr_norm(s).replace('.', ' ').replace('  ', ' ').strip()
        for u in sorted(unvanlar, key=len, reverse=True):
            n = n.replace(u.replace('.', ' ').strip(), '').strip()
        return n.strip()

    return temizle(fb_ad) == temizle(excel_ad)


def main() -> int:
    if not config.SERVICE_ACCOUNT_KEY.exists():
        print(f"HATA: serviceAccountKey.json bulunamadı", file=sys.stderr)
        return 1

    if not EXCEL_PATH.exists():
        # Uploads klasöründe ara
        alt = Path(__file__).parent / "venv" / ".." / ".."
        candidates = list(Path("/Users/iremutusmac").rglob("*Sınav*Tarihsiz*.xlsx"))
        if not candidates:
            candidates = list(Path("/Users/iremutusmac").rglob("*sinav*listesi*.xlsx"))
        if candidates:
            excel = candidates[0]
            print(f"Excel bulundu: {excel}")
        else:
            print(f"HATA: Excel bulunamadı. '{EXCEL_PATH}' yoluna koyun veya aşağıyı düzenleyin.")
            return 1
    else:
        excel = EXCEL_PATH

    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(
            credentials.Certificate(str(config.SERVICE_ACCOUNT_KEY)),
            {"databaseURL": config.FIREBASE_DB_URL},
        )

    # ── 1. Excel'den hoca → dersler map'i oluştur ──
    wb = openpyxl.load_workbook(str(excel))
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    header = [str(c).strip() if c else '' for c in rows[0]]

    # Sütun indekslerini bul
    def col(name_part: str) -> int:
        for i, h in enumerate(header):
            if name_part.lower() in h.lower():
                return i
        return -1

    idx_ders  = col('DH_Adı')
    idx_hoca  = col('Öğretim_Üyesi')
    idx_okul  = col('Öğrenci_No')

    if idx_ders < 0 or idx_hoca < 0:
        # Kolon adı farklıysa pozisyona göre tahmin et
        idx_ders  = 8
        idx_hoca  = 10

    hoca_dersler: dict[str, set[str]] = defaultdict(set)
    for row in rows[1:]:
        if not row[idx_ders] or not row[idx_hoca]:
            continue
        ders = str(row[idx_ders]).strip()
        hoca = str(row[idx_hoca]).strip()
        if ders and hoca:
            hoca_dersler[hoca].add(ders)

    print(f"Excel'de {len(hoca_dersler)} benzersiz hoca bulundu.\n")

    # ── 2. Firebase'den tüm akademisyenleri çek ──
    akademisyenler = db.reference("academic_users").get()
    if not akademisyenler:
        print("HATA: academic_users boş veya bulunamadı.")
        return 1

    guncellenen = 0
    eslesmedi   = []

    for uid, data in akademisyenler.items():
        if not isinstance(data, dict):
            continue
        fb_ad = data.get("ad_soyad", "").strip()
        if not fb_ad:
            continue

        # Excel'de eşleşen hoca bul
        esleyen_excel_ad = None
        for excel_hoca in hoca_dersler:
            if hoca_eslesiyor(fb_ad, excel_hoca):
                esleyen_excel_ad = excel_hoca
                break

        if not esleyen_excel_ad:
            eslesmedi.append(fb_ad)
            continue

        excel_dersler = hoca_dersler[esleyen_excel_ad]
        mevcut = data.get("verilen_dersler", [])
        if not isinstance(mevcut, list):
            mevcut = []

        # verilen_dersler string veya dict olabilir
        mevcut_str  = [d if isinstance(d, str) else d.get('ders_adi', str(d)) for d in mevcut]
        mevcut_norm = {tr_norm(d) for d in mevcut_str}
        eklenecek   = [d for d in excel_dersler if tr_norm(d) not in mevcut_norm]

        if not eklenecek:
            print(f"[=] {fb_ad} — zaten güncel ({len(mevcut)} ders)")
            continue

        yeni_liste = mevcut + eklenecek
        db.reference(f"academic_users/{uid}").update({"verilen_dersler": yeni_liste})
        print(f"[+] {fb_ad}")
        for d in eklenecek:
            print(f"    + {d}")
        guncellenen += 1

    print(f"\n{'='*44}")
    print(f"Güncellenen akademisyen : {guncellenen}")
    if eslesmedi:
        print(f"\nEşleşemeyen akademisyenler (Excel'de yok):")
        for ad in eslesmedi:
            print(f"  - {ad}")
    print("Tamamlandı.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
