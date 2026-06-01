"""
Yoklama sistemi CLI giriş noktası.

Alt komutlar:
    enroll    Ogrenci yuzunu/kartini tanit
    attend    Aktif yoklama oturumu icin webcam+RFID izle
    list      face_encoding'i olan ogrencileri listele (debug)
    seed      Test ogrencisi ekle (test icin, deneme amacli)

Örnek:
    python main.py enroll --uid abc123
    python main.py enroll --uid 12345678901 --photo /tmp/iremcan.jpg --rfid
    python main.py attend
"""

from __future__ import annotations

import argparse
import sys

import attend
import enroll
import firebase_client
import simulate


def cmd_list(args: argparse.Namespace) -> int:
    users = firebase_client.list_users_with_face_encoding()
    if not users:
        print("face_encoding'i olan ogrenci yok.")
        return 0
    print(f"{len(users)} ogrenci:")
    for uid, data in users.items():
        rfid = data.get("rfid_uid", "-")
        print(f"  {uid}  {data.get('ad_soyad', '?'):30s}  rfid={rfid}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="yoklama",
        description="Yuz tanima + RFID yoklama sistemi",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    enroll.add_subparser(sub)
    attend.add_subparser(sub)
    simulate.add_subparser(sub)

    p_list = sub.add_parser("list", help="face_encoding'i olan ogrencileri listele")
    p_list.set_defaults(func=cmd_list)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
