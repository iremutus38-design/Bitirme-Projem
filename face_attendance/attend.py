"""
Yoklama (attendance) modu.

Kullanım:
    python main.py attend                      # Aktif session'u bekler
    python main.py attend --session <sid>      # Belirli session'a bagla

Akış:
    1. Aktif attendance_session'u bul (DERSLIK_ID'ye göre veya verilen --session)
    2. users altındaki tüm face_encoding'leri belleğe yükle
    3. Kamerayı aç, her N frame'de bir tarama yap
    4. Yüz tanındıysa mark_face_seen
    5. RFID okuyucudan UID gelirse mark_rfid_seen
    6. Her iki onay birleşince final_status='present' (firebase_client içinde)
    7. ESC veya session.aktif=False → çık
"""

from __future__ import annotations

import argparse
import sys
import time
from typing import Optional

import cv2
import face_recognition
import numpy as np

import config
import face_utils
import firebase_client
import rfid_reader


def _load_known_encodings() -> dict[str, np.ndarray]:
    """users altındaki tüm face_encoding'leri belleğe yükler."""
    users = firebase_client.list_users_with_face_encoding()
    known: dict[str, np.ndarray] = {}
    for uid, data in users.items():
        enc = data.get("face_encoding")
        if isinstance(enc, list) and len(enc) == 128:
            try:
                known[uid] = np.array(enc, dtype=np.float64)
            except Exception:
                continue
    return known


def _wait_for_session(timeout: float = 60.0) -> Optional[tuple[str, dict]]:
    """Aktif session beklemeye başlar (akademisyen 'Yoklama Başlat' basana kadar)."""
    print("[attend] aktif yoklama oturumu bekleniyor...")
    deadline = time.time() + timeout
    last_print = 0.0
    while time.time() < deadline:
        result = firebase_client.get_active_session()
        if result:
            return result
        now = time.time()
        if now - last_print > 5:
            print(f"[attend] hala bekliyor... ({int(deadline - now)}s kaldi)")
            last_print = now
        time.sleep(2)
    return None


def _attendance_loop(session_id: str, session_data: dict, known: dict[str, np.ndarray]) -> int:
    derslik = session_data.get("derslik", "?")
    ders_uuid = session_data.get("ders_uuid", "?")
    print(f"[attend] session={session_id} derslik={derslik} ders={ders_uuid}")
    print(f"[attend] {len(known)} ogrenci yuz encoding'i bellekte")

    reader = rfid_reader.make_reader()
    reader.start()

    last_seen: dict[str, float] = {}  # uid -> son yazma zamanı (cooldown için)
    frame_idx = 0

    try:
        with face_utils.Camera(0) as cam:
            while True:
                frame = cam.read()
                if frame is None:
                    continue
                frame_idx += 1

                # Her N frame'de bir yüz tara (CPU tasarrufu)
                if frame_idx % config.FRAME_PROCESS_EVERY_N == 0:
                    rgb = face_utils.bgr_to_rgb(frame)
                    locations = face_recognition.face_locations(
                        rgb, model=config.FACE_DETECTION_MODEL
                    )
                    encodings = face_recognition.face_encodings(rgb, locations)

                    for loc, enc in zip(locations, encodings):
                        match = face_utils.match_face(enc, known)
                        if match is None:
                            face_utils.draw_box(frame, loc, "?", (0, 0, 255))
                            continue
                        uid, dist = match
                        label = f"{uid[:6]} ({dist:.2f})"
                        face_utils.draw_box(frame, loc, label)

                        # Cooldown kontrolü
                        last = last_seen.get(uid, 0.0)
                        if time.time() - last < config.FACE_REWRITE_COOLDOWN_SEC:
                            continue
                        last_seen[uid] = time.time()
                        try:
                            firebase_client.mark_face_seen(session_id, uid)
                            print(f"[attend] face_ok: {uid} (dist={dist:.3f})")
                        except Exception as exc:
                            print(f"[attend] yazma hatasi: {exc}", file=sys.stderr)

                # RFID kuyruğunu yokla (non-blocking)
                rfid_uid = reader.read_uid(timeout=0.01)
                if rfid_uid:
                    print(f"[attend] kart: {rfid_uid}")
                    found = firebase_client.get_user_by_rfid(rfid_uid)
                    if not found:
                        print(f"[attend] ! bilinmeyen kart: {rfid_uid}")
                    else:
                        ogrenci_uid, _ = found
                        try:
                            firebase_client.mark_rfid_seen(session_id, ogrenci_uid)
                            print(f"[attend] rfid_ok: {ogrenci_uid}")
                        except Exception as exc:
                            print(f"[attend] yazma hatasi: {exc}", file=sys.stderr)

                # Görselleştirme + çıkış kontrolü
                cv2.putText(
                    frame,
                    f"Session: {session_id[:8]}  Q=cik",
                    (10, 30),
                    cv2.FONT_HERSHEY_DUPLEX, 0.5, (0, 255, 255), 1,
                )
                cv2.imshow("Yoklama", frame)
                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), 27):
                    print("[attend] kullanici cikti")
                    return 0

                # Session hala aktif mi? (her 30 frame'de bir kontrol)
                if frame_idx % 30 == 0:
                    current = firebase_client.get_active_session()
                    if current is None or current[0] != session_id:
                        print("[attend] session kapandi, cikiliyor")
                        return 0
    finally:
        reader.stop()


def main(args: argparse.Namespace) -> int:
    if args.session:
        # Belirli session ID verilmişse onu yükle
        from firebase_admin import db
        firebase_client.init()
        data = db.reference(f"attendance_sessions/{args.session}").get()
        if not data:
            print(f"[attend] session bulunamadi: {args.session}", file=sys.stderr)
            return 1
        session = (args.session, data)
    else:
        session = _wait_for_session(timeout=args.timeout)
        if session is None:
            print("[attend] aktif session bulunamadi (timeout)", file=sys.stderr)
            return 1

    known = _load_known_encodings()
    if not known:
        print(
            "[attend] UYARI: hicbir ogrenci face_encoding'i yok. "
            "Once 'python main.py enroll --uid <UID>' ile birkac ogrenci ekleyin.",
            file=sys.stderr,
        )
        # Yine de devam et - RFID çalışabilir

    return _attendance_loop(session[0], session[1], known)


def add_subparser(subparsers: argparse._SubParsersAction) -> None:
    p = subparsers.add_parser("attend", help="Aktif yoklama oturumu icin yuzleri+RFID'leri izle")
    p.add_argument("--session", help="Belirli session ID'ye bagla (yoksa aktif olani bekle)")
    p.add_argument("--timeout", type=float, default=300.0, help="Aktif session bekleme suresi (sn)")
    p.set_defaults(func=main)
