"""
Windows tarafı: UHF Anteni (HTTP) → Python poller → Firebase.

Anten bir HTTP server; root endpoint'e GET atınca body'de UID(ler) dönüyor.
Bu script o endpoint'i periyodik olarak yokluyor.

Mimari:
    [Bu script] ──HTTP GET / (her ~250ms)──> [Anten 192.168.137.87:80]
         │                                          │
         v                                          v
    body'den UID extract                       UID'ler text olarak
         │
         v
    [Firebase rfid_events/]
         │
         v
    [Mac yoklama loop (attend.py)]

Üç mod:
    test    — UID'leri ekrana basar, Firebase'e DOKUNMAZ (önce bunu çalıştır)
    enroll  — Listeden bir öğrenci seç, antenden gelen ilk UID'yi ona ata
    listen  — Her okunan UID için rfid_events/ altına push at (ders zamanı çalışacak mod)

Kullanım:
    python rfid_to_firebase.py test                   # önce bunu çalıştır
    python rfid_to_firebase.py enroll                 # kartları öğrencilere ata
    python rfid_to_firebase.py listen                 # ders zamanı çalıştır

Notlar:
- Anten IP'sini ANTENNA_HOST sabitinde değiştir (veya --antenna-host ile geç).
- Polling aralığı POLL_INTERVAL_SEC (default 0.25 = saniyede 4 GET).
- serviceAccountKey.json bu klasörde olmalı (Mac'teki dosyanın aynısı).
"""

from __future__ import annotations

import argparse
import http.client
import os
import re
import sys
import threading
import time
from pathlib import Path
from queue import Queue, Empty
from typing import Optional

import firebase_admin
from firebase_admin import credentials, db

# --- Ayarlar (gerekirse environment variable ile override edilebilir) ---
BASE_DIR = Path(__file__).resolve().parent
SERVICE_ACCOUNT_KEY = BASE_DIR / "serviceAccountKey.json"

FIREBASE_DB_URL = os.environ.get(
    "FIREBASE_DB_URL",
    "https://finalproject-eb873-default-rtdb.firebaseio.com",
)

# *** ANTEN IP'sini buraya yaz ***
# Anten bir HTTP server, GET / yapınca body'de UID(ler) donüyor.
ANTENNA_HOST = os.environ.get("ANTENNA_HOST", "192.168.137.87")
ANTENNA_PORT = int(os.environ.get("ANTENNA_PORT", "80"))
ANTENNA_PATH = os.environ.get("ANTENNA_PATH", "/")

# Polling araliği — saniyede kaç GET? 0.25 = saniyede 4
POLL_INTERVAL_SEC = float(os.environ.get("POLL_INTERVAL_SEC", "0.25"))
HTTP_TIMEOUT_SEC = float(os.environ.get("HTTP_TIMEOUT_SEC", "3.0"))

# Bu Windows makinesinin / antenin id'si. Mac tarafı bu device_id ile filtreleyebilir.
DEVICE_ID = os.environ.get("RFID_DEVICE_ID", "main_door_antenna")

# Antenin gerçek çıktı formatı:
#   zaman; tarih; voltaj; READER_ID; SAYI; UID1; UID2; ... ; UIDN;;
# Örn (3 tag okunmuş):
#   00:00:00; 01/01/2000; 5.35V; a325fbf; 3; e28068940000501760066cdb; e2806894000040176005bcdb; e280689400005017600678db;;
# Örn (tag yok):
#   00:00:00; 01/01/2000; 5.46V; a325fbf; 0; ;;
#
# 4. alan reader ID (sabit, görmezden gelinir)
# 5. alan o anda görülen tag sayısı
# 6+ alanlar tag UID'leri
DATA_LINE_REGEX = re.compile(
    r"\d{2}:\d{2}:\d{2}\s*;\s*"          # zaman
    r"\d{2}/\d{2}/\d{4}\s*;\s*"          # tarih
    r"[\d.]+\s*V\s*;\s*"                 # voltaj
    r"[0-9a-fA-F]+\s*;\s*"               # reader_id (atla)
    r"(\d+)\s*;\s*"                      # SAYI (capture)
    r"(.*?);;",                          # UID listesi (capture) — ;;'a kadar
    re.DOTALL,
)
# Bir UID hex olmalı, en az 8 karakter (EPC genelde 24 hex)
UID_FIELD_REGEX = re.compile(r"^[0-9a-fA-F]{8,}$")

# Aynı UID art arda gelirse N saniye boyunca tekrar yazma (anten spam'ini engelle).
DEDUPE_WINDOW_SEC = 3.0


# --- Firebase ---

_firebase_initialized = False


def init_firebase() -> None:
    global _firebase_initialized
    if _firebase_initialized:
        return
    if not SERVICE_ACCOUNT_KEY.exists():
        sys.exit(
            f"HATA: serviceAccountKey.json bulunamadi: {SERVICE_ACCOUNT_KEY}\n"
            f"Mac'teki dosyanin aynisini bu klasore kopyala."
        )
    cred = credentials.Certificate(str(SERVICE_ACCOUNT_KEY))
    firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})
    _firebase_initialized = True


# --- HTTP poller (antene GET atıp body'den UID çıkarır) ---

class AntennaClient:
    """
    Antene HTTP GET atar, body'den 24-karakter hex UID'leri regex ile çıkarır
    ve queue'ya koyar.

    POLL_INTERVAL_SEC kadar uyuyup yeniden GET atar. Hata olursa biraz daha
    bekleyip devam eder.
    """

    def __init__(self, host: str, port: int, path: str = ANTENNA_PATH,
                 interval: float = POLL_INTERVAL_SEC) -> None:
        self.host = host
        self.port = port
        self.path = path
        self.interval = interval
        self.queue: "Queue[str]" = Queue()
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._first_ok = False

    def start(self) -> None:
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _loop(self) -> None:
        consecutive_errors = 0
        while not self._stop.is_set():
            try:
                data = self._fetch_once()
                if not self._first_ok:
                    print(f"[poller] BAGLANTI OK - polling basladi ({self.interval}sn)")
                    self._first_ok = True
                consecutive_errors = 0
                if data:
                    self._extract(data)
            except Exception as e:
                consecutive_errors += 1
                # Her hatayı basmayalım, sadece ilk birkaçını ve sonra seyrek
                if consecutive_errors <= 3 or consecutive_errors % 20 == 0:
                    print(f"[poller] hata #{consecutive_errors}: {e}")
                # Hata varsa biraz fazla bekle
                if self._stop.wait(min(2.0, self.interval * 4)):
                    break
                continue
            # Normal bekleme
            if self._stop.wait(self.interval):
                break

    def _fetch_once(self) -> str:
        conn = http.client.HTTPConnection(self.host, self.port, timeout=HTTP_TIMEOUT_SEC)
        try:
            conn.request("GET", self.path)
            resp = conn.getresponse()
            raw = resp.read()
            try:
                return raw.decode("utf-8", errors="ignore")
            except Exception:
                return raw.decode("latin-1", errors="ignore")
        finally:
            conn.close()

    def _extract(self, body: str) -> None:
        # Her data satırından (count, UID_listesi) çıkar
        # Aynı body içinde aynı UID'yi tek sefer kuyruğa atalım
        seen = set()
        for m in DATA_LINE_REGEX.finditer(body):
            uid_block = m.group(2)
            # ";" ile böl, her parçayı strip, hex UID kontrolü yap
            for part in uid_block.split(";"):
                uid = part.strip().lower()
                if uid and UID_FIELD_REGEX.match(uid) and uid not in seen:
                    seen.add(uid)
                    self.queue.put(uid)

    def next_uid(self, timeout: float = 1.0) -> Optional[str]:
        try:
            return self.queue.get(timeout=timeout)
        except Empty:
            return None

    def flush_buffer(self) -> None:
        """Antenin biriktirdiği eski okumaları temizle.

        Açılışta bir kere çağır: ilk poll'u yapıp atar, sonraki poll'larda
        sadece o andan sonraki okumalar gelir.
        """
        try:
            self._fetch_once()
        except Exception:
            pass
        # Bekleyen kuyruktaki UID'leri de boşalt
        while not self.queue.empty():
            try:
                self.queue.get_nowait()
            except Empty:
                break

    def sample_uids(self, duration_sec: float) -> set:
        """duration_sec boyunca okunan tüm farklı UID'leri set olarak döner."""
        uids: set = set()
        deadline = time.time() + duration_sec
        while time.time() < deadline:
            uid = self.next_uid(timeout=0.2)
            if uid:
                uids.add(uid)
        return uids


# --- TEST modu (Firebase'e dokunmaz) ---

def cmd_test(args: argparse.Namespace) -> int:
    print(f"[test] anten={args.antenna_host}:{args.antenna_port} - Firebase'e YAZMIYOR, sadece basacak")
    server = AntennaClient(args.antenna_host, args.antenna_port)
    server.start()
    # Açılışta antenin biriktirdiği eski okumaları at — sadece şu andan
    # sonraki okumaları görmek istiyoruz.
    time.sleep(1.0)  # bağlantı kurulsun
    server.flush_buffer()
    print("[test] eski buffer temizlendi, simdi okuyacak...")
    seen: dict[str, float] = {}
    try:
        while True:
            uid = server.next_uid(timeout=1.0)
            if not uid:
                continue
            now = time.time()
            if now - seen.get(uid, 0.0) < DEDUPE_WINDOW_SEC:
                continue
            seen[uid] = now
            print(f"[test] UID: {uid}")
    except KeyboardInterrupt:
        print("\n[test] cikiliyor...")
    finally:
        server.stop()
    return 0


# --- ENROLL modu (öğrenciye kart ata) ---

def _list_uncarded_students() -> list[tuple[str, dict, str]]:
    """RFID kartı olmayan öğrencileri döner. (uid_or_tc, data, source) listesi."""
    init_firebase()
    out: list[tuple[str, dict, str]] = []

    users = db.reference("users").get() or {}
    for uid, data in users.items():
        if isinstance(data, dict) and not data.get("rfid_uid"):
            # öğrenci rolü var mı diye basit kontrol
            roller = data.get("roller", {})
            if isinstance(roller, dict) and not roller.get("ogrenci", True):
                continue
            out.append((uid, data, "users"))

    on_kayitlar = db.reference("on_kayitlar").get() or {}
    for tc, data in on_kayitlar.items():
        if isinstance(data, dict) and not data.get("rfid_uid"):
            out.append((tc, data, "on_kayitlar"))

    return out


def _display_name(data: dict) -> str:
    ad_soyad = data.get("ad_soyad")
    if ad_soyad:
        return str(ad_soyad)
    ad = data.get("ad") or data.get("isim") or "?"
    soyad = data.get("soyad") or ""
    return f"{ad} {soyad}".strip()


def cmd_enroll(args: argparse.Namespace) -> int:
    candidates = _list_uncarded_students()
    if not candidates:
        print("[enroll] RFID karti olmayan ogrenci bulunamadi.")
        print("         (Tum ogrencilere zaten kart atanmis olabilir veya")
        print("         Firebase'de hic ogrenci yoktur.)")
        return 0

    print(f"\nKart bekleyen {len(candidates)} ogrenci:\n")
    for i, (uid, data, src) in enumerate(candidates):
        ad = _display_name(data)
        okul_no = data.get("okul_no") or data.get("ogrenci_no") or "-"
        tc = data.get("tc_no") or "-"
        print(f"  [{i:2d}] {ad:35s}  okul_no={okul_no!s:12s}  tc={tc!s:12s}  ({src})")

    print()
    try:
        sel = input("Numara sec (veya 'q' cik): ").strip()
    except EOFError:
        return 0
    if sel.lower() in ("q", "quit", "exit", ""):
        return 0
    try:
        idx = int(sel)
        target_uid, target_data, source = candidates[idx]
    except (ValueError, IndexError):
        print("[enroll] gecersiz secim")
        return 1

    ad = _display_name(target_data)
    server = AntennaClient(args.antenna_host, args.antenna_port)
    server.start()
    try:
        # 1) Anten bağlansın, buffer temizlensin
        time.sleep(1.0)
        server.flush_buffer()

        # 2) Arka plan tag'lerini ölç (etrafta başka UHF tag varsa onları öğrenelim)
        print("\n[enroll] Anteni BOS birak (kart yaklastirma).")
        try:
            input("         Hazirsan Enter'a bas: ")
        except EOFError:
            return 0
        server.flush_buffer()
        print("[enroll] Arka plan taraniyor (3 sn)...")
        background = server.sample_uids(3.0)
        if background:
            print(f"[enroll] Arka planda {len(background)} tag goruldu:")
            for u in sorted(background):
                print(f"           {u}")
        else:
            print("[enroll] Arka plan temiz.")

        # 3) Kartı koy
        print(f"\n[enroll] Simdi '{ad}' icin karti antene KOY.")
        try:
            input("         Yaklastirdigin sabit tut, Enter'a bas: ")
        except EOFError:
            return 0
        server.flush_buffer()
        print("[enroll] Kart taraniyor (4 sn)...")
        with_card = server.sample_uids(4.0)

        # 4) Yeni UID'leri bul
        new_uids = with_card - background
        if not new_uids:
            print(
                "[enroll] HATA: Yeni hicbir UID okunmadi.\n"
                "         - Kart anten menzilinde mi?\n"
                "         - Kart UHF mi? (LF/HF kartlar bu antende calismaz)\n"
                "         - Tekrar dene"
            )
            return 1

        if len(new_uids) == 1:
            uid = next(iter(new_uids))
        else:
            print(f"\n[enroll] {len(new_uids)} yeni UID bulundu (etrafta hareket var?):")
            uid_list = sorted(new_uids)
            for i, u in enumerate(uid_list):
                print(f"  [{i}] {u}")
            try:
                sel = input("Bu ogrencinin karti hangisi? (numara): ").strip()
                uid = uid_list[int(sel)]
            except (ValueError, IndexError, EOFError):
                print("[enroll] gecersiz secim, iptal.")
                return 1

        # 5) Bu UID baska birine bagli mi?
        existing = db.reference(f"rfid_index/{uid}").get()
        if existing and existing != target_uid:
            try:
                eski = db.reference(f"users/{existing}").get() or \
                       db.reference(f"on_kayitlar/{existing}").get() or {}
                eski_ad = _display_name(eski) if isinstance(eski, dict) else "?"
            except Exception:
                eski_ad = "?"
            ans = input(
                f"\n[!] UYARI: {uid} zaten '{eski_ad}' kisisine bagli. "
                f"Uzerine yazayim mi? [e/H]: "
            ).strip().lower()
            if ans not in ("e", "y", "evet", "yes"):
                print("[enroll] iptal edildi.")
                return 0

        # 6) Yaz
        db.reference(f"{source}/{target_uid}").update({"rfid_uid": uid})
        db.reference(f"rfid_index/{uid}").set(target_uid)
        print(f"\n[enroll] OK -> {ad}  =>  {uid}")
        return 0
    finally:
        server.stop()


# --- LISTEN modu (ders zamanı çalışacak) ---

def cmd_listen(args: argparse.Namespace) -> int:
    init_firebase()
    print(
        f"[listen] device={DEVICE_ID}  anten={args.antenna_host}:{args.antenna_port}  -> "
        f"rfid_events/  (Ctrl+C cik)"
    )
    server = AntennaClient(args.antenna_host, args.antenna_port)
    server.start()
    time.sleep(1.0)
    server.flush_buffer()
    print("[listen] eski buffer temizlendi, dinleme basladi")
    last_pushed: dict[str, float] = {}
    try:
        while True:
            uid = server.next_uid(timeout=1.0)
            if not uid:
                continue
            now = time.time()
            if now - last_pushed.get(uid, 0.0) < DEDUPE_WINDOW_SEC:
                continue
            last_pushed[uid] = now

            db.reference("rfid_events").push({
                "uid": uid,
                "ts": int(now * 1000),
                "device": DEVICE_ID,
                "consumed": False,
            })

            # Bu UID'ye sahip ogrenci kim?
            owner_uid = db.reference(f"rfid_index/{uid}").get()
            if owner_uid:
                owner = db.reference(f"users/{owner_uid}").get() or \
                        db.reference(f"on_kayitlar/{owner_uid}").get() or {}
                ad = _display_name(owner) if isinstance(owner, dict) else "?"
                print(f"[listen] {uid}  ->  {ad}")
            else:
                print(f"[listen] {uid}  (kayitsiz kart - enroll edilmemis)")
    except KeyboardInterrupt:
        print("\n[listen] cikiliyor...")
    finally:
        server.stop()
    return 0


# --- CLI ---

def main() -> int:
    p = argparse.ArgumentParser(
        prog="rfid_to_firebase",
        description="Windows: Anten -> Python TCP -> Firebase kopru scripti",
    )
    p.add_argument("--antenna-host", default=ANTENNA_HOST, help=f"Anten IP (default {ANTENNA_HOST})")
    p.add_argument("--antenna-port", type=int, default=ANTENNA_PORT, help=f"Anten port (default {ANTENNA_PORT})")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("test", help="Antenden gelen UID'leri ekrana bas (firebase'e dokunma)")
    sub.add_parser("enroll", help="Bir ogrenciye karti ata")
    sub.add_parser("listen", help="Tum okumalari rfid_events/ altina push'la")

    args = p.parse_args()
    if args.cmd == "test":
        return cmd_test(args)
    if args.cmd == "enroll":
        return cmd_enroll(args)
    if args.cmd == "listen":
        return cmd_listen(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
