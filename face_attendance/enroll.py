"""
Yüz tanıtma (enroll) modu.

Kullanım:
    python main.py enroll --uid <ogrenci_uid_veya_tc>
    python main.py enroll --uid <uid> --photo /path/to/photo.jpg   (kamera yerine dosya)
    python main.py enroll --uid <uid> --rfid                       (yüzden sonra kart oku)

İdari panelden çağrılır. Akış:
    1. Kamera açılır (veya verilen fotoğraf yüklenir)
    2. Kullanıcı yüzü çerçeveye getirir, SPACE'e basar
    3. Tek bir yüz tespit edilirse encoding hesaplanır
    4. faces/<uid>.jpg olarak yerel yedek alınır
    5. Firebase'e yazılır (users veya on_kayitlar)
    6. --rfid bayrağı varsa RFID kart okuması beklenir, atanır
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import cv2

import config
import face_utils
import firebase_client
import rfid_reader


# Çıkış kodları (Flutter tarafı subprocess'i izlerken kullanır)
EXIT_OK = 0
EXIT_USER_CANCELLED = 10
EXIT_NO_FACE = 11
EXIT_MULTIPLE_FACES = 12
EXIT_CAMERA_ERROR = 13
EXIT_FIREBASE_ERROR = 14


def _save_local_photo(uid: str, frame) -> Path:
    path = config.FACES_DIR / f"{uid}.jpg"
    cv2.imwrite(str(path), frame)
    return path


def enroll_from_camera(uid: str) -> int:
    """Kamerayı açar, kullanıcı SPACE'e basana kadar bekler, encoding hesaplar."""
    print(f"[enroll] uid={uid} - kamera aciliyor...")
    print("[enroll] SPACE = foto cek, Q veya ESC = iptal")

    try:
        with face_utils.Camera(0) as cam:
            for frame in cam.frames():
                # Önizleme: yüz kutularını göster
                rgb = face_utils.bgr_to_rgb(frame)
                import face_recognition
                locs = face_recognition.face_locations(rgb, model=config.FACE_DETECTION_MODEL)
                for loc in locs:
                    face_utils.draw_box(frame, loc, "yuz")
                cv2.putText(
                    frame, f"UID: {uid}  SPACE=cek  Q=iptal",
                    (10, 30), cv2.FONT_HERSHEY_DUPLEX, 0.6, (0, 255, 255), 1,
                )
                cv2.imshow("Yuz Tanitma", frame)

                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), 27):  # Q veya ESC
                    print("[enroll] iptal edildi")
                    return EXIT_USER_CANCELLED
                if key == 32:  # SPACE
                    if len(locs) == 0:
                        print("[enroll] HATA: kadrajda yuz yok, tekrar deneyin")
                        continue
                    if len(locs) > 1:
                        print(f"[enroll] HATA: kadrajda {len(locs)} yuz var, tek yuz olmali")
                        continue
                    encoding = face_utils.encode_face_from_frame(frame)
                    if encoding is None:
                        print("[enroll] HATA: encoding hesaplanamadi")
                        continue
                    photo_path = _save_local_photo(uid, frame)
                    print(f"[enroll] foto kaydedildi: {photo_path}")
                    try:
                        firebase_client.set_user_face_encoding(
                            uid, encoding.tolist(), str(photo_path.name)
                        )
                    except Exception as exc:
                        print(f"[enroll] Firebase yazma hatasi: {exc}", file=sys.stderr)
                        return EXIT_FIREBASE_ERROR
                    print("[enroll] OK - encoding Firebase'e yazildi")
                    return EXIT_OK
    except RuntimeError as exc:
        print(f"[enroll] {exc}", file=sys.stderr)
        return EXIT_CAMERA_ERROR
    return EXIT_USER_CANCELLED


def enroll_from_photo(uid: str, photo_path: str) -> int:
    """Verilen fotoğraftan encoding hesaplar."""
    print(f"[enroll] uid={uid} - foto={photo_path}")
    if not Path(photo_path).exists():
        print(f"[enroll] HATA: foto bulunamadi: {photo_path}", file=sys.stderr)
        return EXIT_NO_FACE
    encoding = face_utils.encode_face_from_file(photo_path)
    if encoding is None:
        print("[enroll] HATA: fotoda yuz bulunamadi", file=sys.stderr)
        return EXIT_NO_FACE
    try:
        firebase_client.set_user_face_encoding(uid, encoding.tolist(), Path(photo_path).name)
    except Exception as exc:
        print(f"[enroll] Firebase yazma hatasi: {exc}", file=sys.stderr)
        return EXIT_FIREBASE_ERROR
    print("[enroll] OK - encoding Firebase'e yazildi")
    return EXIT_OK


def enroll_rfid(uid: str, timeout: float = 30.0) -> int:
    """Tek bir RFID UID okur ve öğrenciye bağlar."""
    print(f"[enroll-rfid] uid={uid} - karti okutun ({timeout}s)...")
    reader = rfid_reader.make_reader()
    reader.start()
    try:
        deadline = time.time() + timeout
        while time.time() < deadline:
            rfid_uid = reader.read_uid(timeout=1.0)
            if rfid_uid:
                print(f"[enroll-rfid] kart okundu: {rfid_uid}")
                try:
                    firebase_client.set_user_rfid(uid, rfid_uid)
                except Exception as exc:
                    print(f"[enroll-rfid] Firebase hatasi: {exc}", file=sys.stderr)
                    return EXIT_FIREBASE_ERROR
                print("[enroll-rfid] OK - kart ogrenciye baglandi")
                return EXIT_OK
        print("[enroll-rfid] zaman asimi", file=sys.stderr)
        return EXIT_USER_CANCELLED
    finally:
        reader.stop()


def main(args: argparse.Namespace) -> int:
    if not args.uid:
        print("--uid zorunlu", file=sys.stderr)
        return 2

    # RFID-only mod (yüz zaten tanıtılmış, sadece kart bağla)
    if args.rfid_only:
        return enroll_rfid(args.uid)

    # Yüz tanıtma
    if args.photo:
        result = enroll_from_photo(args.uid, args.photo)
    else:
        result = enroll_from_camera(args.uid)

    if result != EXIT_OK:
        return result

    # Yüzden sonra RFID
    if args.rfid:
        return enroll_rfid(args.uid)

    return EXIT_OK


def add_subparser(subparsers: argparse._SubParsersAction) -> None:
    p = subparsers.add_parser("enroll", help="Ogrenci yuzunu / RFID kartini tanit")
    p.add_argument("--uid", required=True, help="Ogrenci Firebase UID veya TC No (on kayit)")
    p.add_argument("--photo", help="Kamera yerine fotograf dosyasi kullan")
    p.add_argument("--rfid", action="store_true", help="Yuzden sonra RFID karti da oku")
    p.add_argument("--rfid-only", action="store_true", help="Sadece RFID karti bagla (yuz zaten var)")
    p.set_defaults(func=main)
