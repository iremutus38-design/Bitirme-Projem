"""
Firebase Admin SDK için ince bir sarmalayıcı.

Tüm Realtime Database işlemleri buradan geçer. Diğer modüller doğrudan
firebase_admin'i import etmez - test ve mock için tek nokta.
"""

from __future__ import annotations

import time
from typing import Any, Optional

import firebase_admin
from firebase_admin import credentials, db

import config


_initialized = False


def init() -> None:
    """Firebase Admin uygulamasını başlatır (idempotent)."""
    global _initialized
    if _initialized:
        return

    if not config.SERVICE_ACCOUNT_KEY.exists():
        raise FileNotFoundError(
            f"serviceAccountKey.json bulunamadi: {config.SERVICE_ACCOUNT_KEY}"
        )

    cred = credentials.Certificate(str(config.SERVICE_ACCOUNT_KEY))
    firebase_admin.initialize_app(
        cred,
        {"databaseURL": config.FIREBASE_DB_URL},
    )
    _initialized = True


# --- Öğrenci sorguları ---

def get_user(uid: str) -> Optional[dict]:
    """users/{uid} kaydını döner."""
    init()
    return db.reference(f"users/{uid}").get()


def get_user_by_okul_no(okul_no: str) -> Optional[tuple[str, dict]]:
    """okul_no ile öğrenci ara. (uid, data) veya None döner."""
    init()
    snap = db.reference("users").order_by_child("okul_no").equal_to(okul_no).get()
    if not snap:
        return None
    uid = next(iter(snap))
    return uid, snap[uid]


def get_user_by_tc(tc_no: str) -> Optional[tuple[str, dict]]:
    """TC ile öğrenci ara (users içinde). Ön kayıt için on_kayitlar'a bakar."""
    init()
    snap = db.reference("users").order_by_child("tc_no").equal_to(tc_no).get()
    if snap:
        uid = next(iter(snap))
        return uid, snap[uid]
    # users'ta yoksa on_kayitlar'a bak
    on_kayit = db.reference(f"on_kayitlar/{tc_no}").get()
    if on_kayit:
        return tc_no, on_kayit  # uid yerine TC dönüyor - henüz kayıt olmamış
    return None


def list_users_with_face_encoding() -> dict[str, dict]:
    """face_encoding'i olan tüm öğrencileri döner. {uid: data}."""
    init()
    all_users = db.reference("users").get() or {}
    return {
        uid: data
        for uid, data in all_users.items()
        if isinstance(data, dict) and data.get("face_encoding")
    }


# --- Öğrenci güncellemeleri (yüz/RFID tanıtma) ---

def set_user_face_encoding(uid: str, encoding: list[float], photo_path: str | None = None) -> None:
    """users/{uid}/face_encoding'i günceller. uid TC olabilir (henüz kayıt olmamış)."""
    init()
    # uid 11 haneli sayısalsa TC kabul edip on_kayitlar'a yaz
    path = f"on_kayitlar/{uid}" if (uid.isdigit() and len(uid) == 11) else f"users/{uid}"
    updates: dict[str, Any] = {"face_encoding": encoding}
    if photo_path:
        updates["face_photo_path"] = photo_path
    db.reference(path).update(updates)


def set_user_rfid(uid: str, rfid_uid: str) -> None:
    """Öğrenciye RFID kart UID'si bağlar ve rfid_index'i günceller."""
    init()
    path = f"on_kayitlar/{uid}" if (uid.isdigit() and len(uid) == 11) else f"users/{uid}"
    db.reference(path).update({"rfid_uid": rfid_uid})
    # rfid_index TC için anlamsız (kart kayıt sonrası çalışacak),
    # ama tutarlılık için yine de yazıyoruz.
    db.reference(f"rfid_index/{rfid_uid}").set(uid)


def get_user_by_rfid(rfid_uid: str) -> Optional[tuple[str, dict]]:
    """RFID UID'sinden öğrenci bul."""
    init()
    target_uid = db.reference(f"rfid_index/{rfid_uid}").get()
    if not target_uid:
        return None
    user = get_user(target_uid)
    if not user:
        return None
    return target_uid, user


# --- Yoklama oturumu ---

def get_active_session() -> Optional[tuple[str, dict]]:
    """Aktif (aktif=True) olan ilk attendance_session'ı döner."""
    init()
    # Firebase boolean sorgusunu desteklemediği için tümünü çekip filtrele
    sessions = db.reference("attendance_sessions").get() or {}
    for sid, data in sessions.items():
        if not isinstance(data, dict):
            continue
        if data.get("aktif") is True:
            derslik = data.get("derslik")
            if not derslik or not config.DERSLIK_ID or derslik == config.DERSLIK_ID:
                return sid, data
    return None


def mark_face_seen(session_id: str, ogrenci_uid: str) -> None:
    """attendance_sessions/{sid}/records/{uid}/face_ok = true."""
    init()
    ts = int(time.time() * 1000)
    db.reference(f"attendance_sessions/{session_id}/records/{ogrenci_uid}").update({
        "face_ok": True,
        "face_ts": ts,
    })
    _maybe_finalize(session_id, ogrenci_uid)


def mark_rfid_seen(session_id: str, ogrenci_uid: str) -> None:
    """attendance_sessions/{sid}/records/{uid}/rfid_ok = true."""
    init()
    ts = int(time.time() * 1000)
    db.reference(f"attendance_sessions/{session_id}/records/{ogrenci_uid}").update({
        "rfid_ok": True,
        "rfid_ts": ts,
    })
    _maybe_finalize(session_id, ogrenci_uid)


def _maybe_finalize(session_id: str, ogrenci_uid: str) -> None:
    """İki onay da geldiyse final_status'u günceller."""
    rec = db.reference(f"attendance_sessions/{session_id}/records/{ogrenci_uid}").get() or {}
    face_ok = rec.get("face_ok", False)
    rfid_ok = rec.get("rfid_ok", False)
    if face_ok and rfid_ok:
        status = "present"
    elif face_ok:
        status = "face_only"
    elif rfid_ok:
        status = "rfid_only"
    else:
        return
    db.reference(f"attendance_sessions/{session_id}/records/{ogrenci_uid}").update({
        "final_status": status,
        "method": "auto",
    })
