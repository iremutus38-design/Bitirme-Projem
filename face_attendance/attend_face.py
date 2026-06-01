"""
attend_face.py  —  Manuel seçimli yüz yoklaması (Mac webcam)
=============================================================

Akış:
  1. Firebase'den TC'nin face_encoding'ini yükle
  2. Aktif attendance_session bul
  3. Webcam aç — tespit edilen yüzleri kutucukla göster
  4. Kullanıcı ok tuşlarıyla yüz seçer, Enter ile onaylar
  5. Seçilen yüz kayıtlı yüzle eşleşiyorsa face_ok yaz

Tuşlar:
  Sol/Sağ ok  → yüzler arasında geç
  Enter       → seçili yüzü onayla ve karşılaştır
  ESC         → iptal et
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import face_recognition
import numpy as np

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))
import firebase_client

THRESHOLD  = 0.50   # uzaklık eşiği
FRAME_SKIP = 2      # her N frame'de bir yüz tara


def _json_out(ok: bool, message: str, **extra):
    d = {"ok": ok, "message": message, **extra}
    print(json.dumps(d, ensure_ascii=False))


def tr_ascii(s: str) -> str:
    return s.translate(str.maketrans(
        {"ç":"c","Ç":"C","ğ":"g","Ğ":"G","ı":"i","İ":"I",
         "ö":"o","Ö":"O","ş":"s","Ş":"S","ü":"u","Ü":"U"}
    ))


def draw_faces(frame, locs, selected_idx):
    """Yüz kutularını çiz. Seçili = yeşil, diğerleri = gri."""
    for i, (top, right, bottom, left) in enumerate(locs):
        if i == selected_idx:
            color = (0, 220, 0)   # yeşil — seçili
            thickness = 3
            label = f"[{i+1}/{len(locs)}] ENTER=onayla"
        else:
            color = (160, 160, 160)  # gri — seçilmedi
            thickness = 1
            label = f"{i+1}"

        cv2.rectangle(frame, (left, top), (right, bottom), color, thickness)
        cv2.rectangle(frame, (left, bottom), (right, bottom + 22), color, cv2.FILLED)
        cv2.putText(frame, label, (left + 4, bottom + 16),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)


def draw_hint(frame, text, color=(200, 200, 0)):
    h, w = frame.shape[:2]
    cv2.rectangle(frame, (0, h - 36), (w, h), (30, 30, 30), cv2.FILLED)
    cv2.putText(frame, text, (10, h - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 1)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--tc", required=True)
    p.add_argument("--session-id", default=None, help="Kullanılacak session ID (opsiyonel)")
    args = p.parse_args()
    tc = args.tc.strip()
    forced_session_id = args.session_id

    firebase_client.init()

    # 1. Kayıtlı yüzü al
    user_data = (
        firebase_client.db.reference(f"on_kayitlar/{tc}").get()
        or firebase_client.db.reference(f"users/{tc}").get()
    )
    if not user_data or not isinstance(user_data, dict):
        all_users = firebase_client.db.reference("users").get() or {}
        user_data = next(
            (v for v in all_users.values()
             if isinstance(v, dict) and str(v.get("tc", "")) == tc),
            None,
        )

    if not user_data:
        _json_out(False, f"TC bulunamadi: {tc}")
        return 1

    enc_raw = user_data.get("face_encoding")
    if not enc_raw or not isinstance(enc_raw, list) or len(enc_raw) != 128:
        _json_out(False, "Yuz kayitli degil (once enroll yapin)")
        return 1

    known_enc = np.array(enc_raw, dtype=np.float64)
    ad_soyad  = user_data.get("ad_soyad", tc)

    # 2. Aktif session — Flutter'dan gelen session_id varsa onu kullan
    if forced_session_id:
        from firebase_admin import db as _db
        session_data = _db.reference(f"attendance_sessions/{forced_session_id}").get()
        if not session_data or not isinstance(session_data, dict):
            _json_out(False, f"Session bulunamadi: {forced_session_id}")
            return 1
        session_id = forced_session_id
    else:
        session = firebase_client.get_active_session()
        if session is None:
            _json_out(False, "Aktif yoklama session'i yok")
            return 1
        session_id, session_data = session
    ders_adi = session_data.get("ders_adi", "?")

    # 3. Kamera
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        _json_out(False, "Kamera acilamadi")
        return 1

    print(f"[attend_face] Kamera acik — {ad_soyad} | {ders_adi}", file=sys.stderr)
    print("[attend_face] Sol/Sag ok: yuz sec  |  Enter: onayla  |  ESC: iptal", file=sys.stderr)

    # Durum değişkenleri
    locs: list       = []
    encs: list       = []
    selected_idx     = 0
    frame_no         = 0
    last_scan        = 0.0
    result           = None  # None | True | False

    cv2.namedWindow("Yuz Tanima", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("Yuz Tanima", 640, 500)

    while result is None:
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.03)
            continue

        frame_no += 1

        # Her FRAME_SKIP karede bir yüz tara
        if frame_no % FRAME_SKIP == 0:
            rgb  = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            locs = face_recognition.face_locations(rgb, model="hog")
            encs = face_recognition.face_encodings(rgb, locs)
            # Seçili indeks sınırda kalmasın
            if locs:
                selected_idx = selected_idx % len(locs)

        # Kutucukları çiz
        display = frame.copy()
        if locs:
            draw_faces(display, locs, selected_idx)
            n = len(locs)
            hint = (f"Yuz {selected_idx+1}/{n}  |  "
                    f"<- -> : gec  |  ENTER: onayla  |  ESC: iptal")
        else:
            hint = "Yuz algilanamadi — kameraya bakin"

        draw_hint(display, hint)
        cv2.imshow("Yuz Tanima", display)

        key = cv2.waitKey(1) & 0xFF

        if key == 27:          # ESC — iptal
            result = False
            break

        if not locs:
            continue

        if key == 81 or key == 2:   # Sol ok (Linux/Mac)
            selected_idx = (selected_idx - 1) % len(locs)
        elif key == 83 or key == 3: # Sag ok
            selected_idx = (selected_idx + 1) % len(locs)
        elif key == 13 or key == 10:  # Enter
            # Seçili yüzü karşılaştır
            if selected_idx < len(encs):
                enc  = encs[selected_idx]
                dist = face_recognition.face_distance([known_enc], enc)[0]
                print(f"[attend_face] dist={dist:.3f}", file=sys.stderr)

                if dist <= THRESHOLD:
                    # Onay ekranı
                    ok_frame = display.copy()
                    top, right, bottom, left = locs[selected_idx]
                    cv2.rectangle(ok_frame, (left, top), (right, bottom), (0, 255, 0), 3)
                    cv2.putText(ok_frame,
                                f"Tanindi: {tr_ascii(ad_soyad)}",
                                (30, 50), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 0), 2)
                    draw_hint(ok_frame, "Yuz eslesti! Yoklamaya kaydedildi.", (0, 220, 0))
                    cv2.imshow("Yuz Tanima", ok_frame)
                    cv2.waitKey(2000)
                    result = True
                else:
                    # Eşleşmedi — kırmızı uyarı
                    no_frame = display.copy()
                    top, right, bottom, left = locs[selected_idx]
                    cv2.rectangle(no_frame, (left, top), (right, bottom), (0, 0, 255), 3)
                    draw_hint(no_frame,
                              f"Eslesme yok (dist={dist:.2f} > {THRESHOLD}). Tekrar deneyin.",
                              (0, 60, 255))
                    cv2.imshow("Yuz Tanima", no_frame)
                    cv2.waitKey(2000)
                    # Döngüye devam et (result = None kalmaya devam)

    cap.release()
    cv2.destroyAllWindows()

    if result is not True:
        _json_out(False, "Yuz taninamadi veya iptal edildi")
        return 1

    # 4. Firebase'e yaz
    firebase_client.mark_face_seen(session_id, tc)
    print(f"[attend_face] face_ok yazildi: session={session_id} tc={tc}", file=sys.stderr)

    _json_out(True,
              f"Yuz tanindi — {ad_soyad} — {ders_adi}",
              ad_soyad=ad_soyad,
              ders_adi=ders_adi,
              session_id=session_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
