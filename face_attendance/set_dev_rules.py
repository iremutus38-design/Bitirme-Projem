"""
Realtime DB rules'ı GELISTIRME modu için açar.

REST API ile token bazlı yetki kontrolü olmadığı için (Firebase Auth SDK
kullanmıyoruz, sadece REST kullanıyoruz, firebase_database SDK auth
state'i otomatik bağlayamıyor), DB rules'ın "public" olması gerek.

DİKKAT: Bu güvensizdir. Sadece geliştirme/demo için. Production'a
çıkarken rules'ı sıkılaştırın.

Çalıştırma:
    python set_dev_rules.py
"""

from __future__ import annotations

import json
import sys

import firebase_admin
from firebase_admin import credentials, db


DEV_RULES = {
    "rules": {
        ".read": "true",
        ".write": "true",
    },
}


def main() -> int:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(
        cred,
        {"databaseURL": "https://finalproject-eb873-default-rtdb.firebaseio.com"},
    )

    try:
        # firebase-admin'in set_rules() metodu var
        db.reference("/").set_rules(json.dumps(DEV_RULES))  # type: ignore
        print("OK rules guncellendi (public read/write).")
        return 0
    except AttributeError:
        print(
            "firebase-admin set_rules desteklemiyor.",
            file=sys.stderr,
        )
    except Exception as exc:
        print(f"HATA: {exc}", file=sys.stderr)

    # Manuel yontem
    print()
    print("=" * 60)
    print("ELLE AYARLAMA ICIN:")
    print("=" * 60)
    print("1. https://console.firebase.google.com'a gidin")
    print("2. finalproject-eb873 projesini secin")
    print("3. Sol menuden 'Realtime Database' acin")
    print("4. Ust kismindan 'Rules' sekmesi")
    print("5. Asagidaki JSON'i yapistirin ve 'Publish' edin:")
    print()
    print(json.dumps(DEV_RULES, indent=2))
    print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
