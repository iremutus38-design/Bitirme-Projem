"""
yoklama_rfid.py  —  RFID Yoklama Scripti
==========================================

Ders zamanı çalıştırılır. Anten kartı okuyunca:
  1. rfid_index/{uid} → owner_key (TC veya uid) bulur
  2. on_kayitlar veya users'dan TC'yi alır
  3. Firebase'deki aktif attendance_sessions bulur
  4. attendance_sessions/{sid}/records/{tc} günceller:
       rfid_ok: true
       final_status: "present"   (face_ok zaten true ise)
       final_status: "rfid_only" (face_ok yoksa)

Kullanım:
    python yoklama_rfid.py
    python yoklama_rfid.py --antenna-host 192.168.x.x --antenna-port 80
    python yoklama_rfid.py --test-uid e28068940000501760066cdb   # gerçek anten olmadan test

Gereksinimler:
    pip install firebase-admin
    serviceAccountKey.json bu klasörde olmalı.
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

# ── Ayarlar ───────────────────────────────────────────────────────────────────

BASE_DIR            = Path(__file__).resolve().parent
SERVICE_ACCOUNT_KEY = BASE_DIR / "serviceAccountKey.json"
FIREBASE_DB_URL     = os.environ.get("FIREBASE_DB_URL",
                        "https://finalproject-eb873-default-rtdb.firebaseio.com")

ANTENNA_HOST     = os.environ.get("ANTENNA_HOST", "192.168.137.188")
ANTENNA_PORT     = int(os.environ.get("ANTENNA_PORT", "80"))
ANTENNA_PATH     = os.environ.get("ANTENNA_PATH", "/")
POLL_INTERVAL    = float(os.environ.get("POLL_INTERVAL_SEC", "0.25"))
HTTP_TIMEOUT     = float(os.environ.get("HTTP_TIMEOUT_SEC", "3.0"))
DEDUPE_SEC       = 3.0   # aynı UID art arda gelirse bu kadar saniye yoksay
SESSION_CHECK_SEC = 3.0  # kaç saniyede bir aktif session kontrolü

UID_FIELD_REGEX = re.compile(r"^[0-9a-fA-F]{8,}$")
DATA_LINE_REGEX = re.compile(
    r"\d{2}:\d{2}:\d{2}\s*;\s*\d{2}/\d{2}/\d{4}\s*;\s*[\d.]+\s*V\s*;\s*"
    r"[0-9a-fA-F]+\s*;\s*(\d+)\s*;\s*(.*?);;", re.DOTALL)

# ── Firebase ──────────────────────────────────────────────────────────────────

_fb_init = False

def init_firebase() -> None:
    global _fb_init
    if _fb_init:
        return
    if not SERVICE_ACCOUNT_KEY.exists():
        sys.exit(f"HATA: serviceAccountKey.json bulunamadi: {SERVICE_ACCOUNT_KEY}")
    cred = credentials.Certificate(str(SERVICE_ACCOUNT_KEY))
    firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})
    _fb_init = True

# ── Anten istemcisi ───────────────────────────────────────────────────────────

class AntennaClient:
    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = port
        self.queue: Queue[str] = Queue()
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _loop(self) -> None:
        first_ok = False
        errors = 0
        while not self._stop.is_set():
            try:
                body = self._get()
                if not first_ok:
                    print(f"[anten] Baglanti OK  ({self.host}:{self.port})")
                    first_ok = True
                errors = 0
                self._parse(body)
            except Exception as e:
                errors += 1
                if errors <= 3 or errors % 20 == 0:
                    print(f"[anten] hata #{errors}: {e}")
                if self._stop.wait(min(2.0, POLL_INTERVAL * 4)):
                    break
                continue
            if self._stop.wait(POLL_INTERVAL):
                break

    def _get(self) -> str:
        conn = http.client.HTTPConnection(self.host, self.port, timeout=HTTP_TIMEOUT)
        try:
            conn.request("GET", ANTENNA_PATH)
            raw = conn.getresponse().read()
            return raw.decode("utf-8", errors="ignore")
        finally:
            conn.close()

    def _parse(self, body: str) -> None:
        seen: set[str] = set()
        s = body.strip()
        if UID_FIELD_REGEX.match(s):
            uid = s.lower()
            if uid not in seen:
                seen.add(uid)
                self.queue.put(uid)
            return
        matched = False
        for m in DATA_LINE_REGEX.finditer(body):
            matched = True
            for part in m.group(2).split(";"):
                uid = part.strip().lower()
                if uid and UID_FIELD_REGEX.match(uid) and uid not in seen:
                    seen.add(uid)
                    self.queue.put(uid)
        if not matched:
            for line in body.splitlines():
                uid = line.strip().lower()
                if uid and UID_FIELD_REGEX.match(uid) and uid not in seen:
                    seen.add(uid)
                    self.queue.put(uid)

    def flush(self) -> None:
        try: self._get()
        except Exception: pass
        while not self.queue.empty():
            try: self.queue.get_nowait()
            except Empty: break

    def next_uid(self, timeout: float = 1.0) -> Optional[str]:
        try: return self.queue.get(timeout=timeout)
        except Empty: return None

# ── Firebase yardımcıları ─────────────────────────────────────────────────────

def aktif_sessionlar() -> dict[str, dict]:
    """Tüm aktif attendance_sessions'ı döner."""
    raw = db.reference("attendance_sessions").get() or {}
    return {sid: d for sid, d in raw.items()
            if isinstance(d, dict) and d.get("aktif") is True}

def tc_bul(owner_key: str) -> Optional[str]:
    """
    rfid_index'ten gelen owner_key → TC döner.
    owner_key:
      - on_kayitlar'daki bir key ise doğrudan TC'dir.
      - users'daki uid ise users/{uid}/tc alanını okur;
        yoksa on_kayitlar'da uid eşleşmesi arar.
    """
    ok = db.reference(f"on_kayitlar/{owner_key}").get()
    if isinstance(ok, dict):
        return owner_key  # key zaten TC

    u = db.reference(f"users/{owner_key}").get()
    if isinstance(u, dict):
        tc = u.get("tc")
        if tc:
            return str(tc)
        # on_kayitlar'da uid ile ara
        all_ok = db.reference("on_kayitlar").get() or {}
        for tc_key, val in all_ok.items():
            if isinstance(val, dict) and val.get("uid") == owner_key:
                return str(tc_key)
    return None

def ogrenci_adi(owner_key: str) -> str:
    for path in (f"on_kayitlar/{owner_key}", f"users/{owner_key}"):
        d = db.reference(path).get()
        if isinstance(d, dict):
            ad = d.get("ad_soyad") or f"{d.get('ad','')} {d.get('soyad','')}".strip()
            if ad:
                return ad
    return owner_key

# ── Yoklama işleme ────────────────────────────────────────────────────────────

def uid_isle(uid: str, now: float) -> None:
    """Bir UID okunduğunda aktif session'a rfid_ok yazar."""

    owner_key = db.reference(f"rfid_index/{uid}").get()
    if not owner_key:
        print(f"  UID {uid}  →  KAYITSIZ KART  (enroll yapılmamış)")
        return

    ad = ogrenci_adi(owner_key)
    tc = tc_bul(owner_key)
    if not tc:
        print(f"  {ad}  →  TC bulunamadı, atlanıyor")
        return

    sessions = aktif_sessionlar()
    if not sessions:
        print(f"  {ad}  →  Kart okundu ama aktif yoklama yok")
        return

    for sid, sdata in sessions.items():
        ders = sdata.get("ders_adi", "?")
        ref  = db.reference(f"attendance_sessions/{sid}/records/{tc}")
        mevcut = ref.get() or {}
        if not isinstance(mevcut, dict):
            mevcut = {}

        # Zaten tam onaylıysa tekrar yazma
        if mevcut.get("rfid_ok") and mevcut.get("final_status") == "present":
            print(f"  {ad} ({tc})  →  {ders}  [zaten MEVCUT ✓, atlandı]")
            continue

        face_ok = mevcut.get("face_ok") is True
        guncelleme: dict = {
            "rfid_ok":  True,
            "rfid_ts":  int(now * 1000),
            "rfid_uid": uid,
        }

        if face_ok:
            guncelleme["final_status"] = "present"
            durum = "✓ MEVCUT  (yüz + RFID tamam)"
        else:
            guncelleme["final_status"] = "rfid_only"
            durum = "RFID tamam  —  yüz tanıma bekleniyor"

        ref.update(guncelleme)
        print(f"  {ad} ({tc})  →  {ders}  [{durum}]")

# ── Ana döngü ─────────────────────────────────────────────────────────────────

def calistir(antenna_host: str, antenna_port: int) -> None:
    init_firebase()

    print("=" * 60)
    print("  RFID YOKLAMA SİSTEMİ")
    print(f"  Anten  : {antenna_host}:{antenna_port}")
    print(f"  Firebase: {FIREBASE_DB_URL}")
    print("  Durdurmak için Ctrl+C")
    print("=" * 60)

    server = AntennaClient(antenna_host, antenna_port)
    server.start()
    time.sleep(1.0)
    server.flush()
    print("[sistem] Hazır — kart bekleniyor...\n")

    last_read: dict[str, float] = {}
    last_check = 0.0
    last_session_ids: set[str] = set()

    try:
        while True:
            now = time.time()

            # Aktif session değişti mi? Bildir
            if now - last_check >= SESSION_CHECK_SEC:
                sessions = aktif_sessionlar()
                current_ids = set(sessions.keys())
                if current_ids != last_session_ids:
                    if current_ids:
                        for sid, sd in sessions.items():
                            print(f"[session] AKTİF → {sd.get('ders_adi','?')}  (sid={sid})")
                    else:
                        print("[session] Aktif yoklama yok — bekleniyor...")
                    last_session_ids = current_ids
                last_check = now

            uid = server.next_uid(timeout=1.0)
            if not uid:
                continue

            if now - last_read.get(uid, 0.0) < DEDUPE_SEC:
                continue
            last_read[uid] = now

            print(f"\n[kart okundu] {uid}")
            uid_isle(uid, now)

    except KeyboardInterrupt:
        print("\n[sistem] Kapatılıyor...")
    finally:
        server.stop()

# ── Test modu (gerçek anten olmadan) ─────────────────────────────────────────

def test_uid_isle(uid: str) -> None:
    init_firebase()
    print(f"[test] UID: {uid}")
    uid_isle(uid, time.time())

# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> int:
    p = argparse.ArgumentParser(
        prog="yoklama_rfid",
        description="RFID yoklama scripti — aktif session'a rfid_ok yazar",
    )
    p.add_argument("--antenna-host", default=ANTENNA_HOST,
                   help=f"Anten IP adresi (default: {ANTENNA_HOST})")
    p.add_argument("--antenna-port", type=int, default=ANTENNA_PORT,
                   help=f"Anten portu (default: {ANTENNA_PORT})")
    p.add_argument("--test-uid", metavar="UID",
                   help="Gerçek anten olmadan bu UID'yi test et (Firebase'e yazar)")
    args = p.parse_args()

    if args.test_uid:
        test_uid_isle(args.test_uid.strip().lower())
        return 0

    calistir(args.antenna_host, args.antenna_port)
    return 0

if __name__ == "__main__":
    sys.exit(main())
