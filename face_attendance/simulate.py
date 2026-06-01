"""
Sahte kart okuması simülasyonu.

Donanım gelene kadar (veya demo/sunum için) tek atımlık "kart okundu"
olayı tetikler. Aktif session'a doğrudan Firebase'e yazar.

Kullanım:
    # Aktif session'a verilen UID'yi 'okutulmus' olarak isaretle
    python main.py simulate-card --rfid A4B72F19

    # Belirli session'a yaz
    python main.py simulate-card --rfid A4B72F19 --session <sid>

    # rfid yerine ogrenci UID'si veya okul_no de verilebilir
    python main.py simulate-card --student <ogrenci_uid>
    python main.py simulate-card --student 22370031804     # okul no
"""

from __future__ import annotations

import argparse
import sys

import firebase_client


def _resolve_target(rfid: str | None, student: str | None) -> str | None:
    """Bize verilen tanımlayıcıdan ogrenci_uid bul."""
    if rfid:
        found = firebase_client.get_user_by_rfid(rfid)
        if not found:
            print(f"[sim] RFID UID '{rfid}' rfid_index'te yok.", file=sys.stderr)
            print(f"[sim] Once 'python main.py enroll --uid <ogr> --rfid-only' ile kart bagla.", file=sys.stderr)
            return None
        return found[0]
    if student:
        # Once UID dene
        user = firebase_client.get_user(student)
        if user:
            return student
        # Sonra okul_no
        found = firebase_client.get_user_by_okul_no(student)
        if found:
            return found[0]
        # Son olarak TC
        found = firebase_client.get_user_by_tc(student)
        if found:
            return found[0]
        print(f"[sim] '{student}' UID/okul_no/TC olarak bulunamadi.", file=sys.stderr)
        return None
    return None


def main(args: argparse.Namespace) -> int:
    target_uid = _resolve_target(args.rfid, args.student)
    if not target_uid:
        return 1

    # Session'u bul
    if args.session:
        from firebase_admin import db
        firebase_client.init()
        data = db.reference(f"attendance_sessions/{args.session}").get()
        if not data:
            print(f"[sim] session bulunamadi: {args.session}", file=sys.stderr)
            return 1
        session_id = args.session
    else:
        found = firebase_client.get_active_session()
        if not found:
            print("[sim] Aktif yoklama oturumu yok.", file=sys.stderr)
            print("[sim] Once Flutter'dan 'Yoklama Baslat' veya --session <sid> verin.", file=sys.stderr)
            return 1
        session_id = found[0]

    # Hangi onayı simüle ediyoruz? --rfid varsa rfid, --student-face varsa face
    if args.face_too:
        firebase_client.mark_face_seen(session_id, target_uid)
        print(f"[sim] face_ok yazildi: ogrenci={target_uid} session={session_id}")
    firebase_client.mark_rfid_seen(session_id, target_uid)
    print(f"[sim] rfid_ok yazildi: ogrenci={target_uid} session={session_id}")
    return 0


def add_subparser(subparsers: argparse._SubParsersAction) -> None:
    p = subparsers.add_parser(
        "simulate-card",
        help="Donanim yokken: kart okundu olayini Firebase'e yaz (test/demo)",
    )
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--rfid", help="Kart UID'si (rfid_index'te kayitli olmali)")
    group.add_argument("--student", help="Ogrenci UID / okul_no / TC")
    p.add_argument("--session", help="Hedef session ID (yoksa aktif olan)")
    p.add_argument(
        "--face-too",
        action="store_true",
        help="Ayni anda face_ok'u da set et (tam present icin)",
    )
    p.set_defaults(func=main)
