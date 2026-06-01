"""
Yüz tanıtma HTTP sunucusu.

Endpoint'ler:
  GET  /status               → sunucu canlı mı?
  GET  /enroll?uid=TC        → Mac kamerasını açar, yüzü kaydeder
  POST /recognize            → Telefon fotoğrafını alır, yüzü tanır, face_ok yazar

Kullanım:
    cd /Users/iremutusmac/face_attendance
    source venv/bin/activate
    python enroll_server.py
"""

from __future__ import annotations

import io
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

BASE_DIR  = Path(__file__).resolve().parent
PYTHON    = str(BASE_DIR / "venv" / "bin" / "python")
SCRIPT    = str(BASE_DIR / "main.py")
PORT      = 5050

_lock = threading.Lock()

# /recognize için lazım — ilk istekte yükle
_recognize_ready = False
_face_recognition = None
_np = None
_firebase_client = None


def _ensure_recognize_imports():
    """face_recognition ve firebase_client'ı lazy yükle."""
    global _recognize_ready, _face_recognition, _np, _firebase_client
    if _recognize_ready:
        return True
    try:
        import importlib, sys as _sys
        # venv'in site-packages'ını path'e ekle
        import site
        venv_site = BASE_DIR / "venv" / "lib"
        for p in venv_site.glob("python*/site-packages"):
            if str(p) not in _sys.path:
                _sys.path.insert(0, str(p))
        if str(BASE_DIR) not in _sys.path:
            _sys.path.insert(0, str(BASE_DIR))

        import face_recognition as _fr
        import numpy as _np_mod
        import firebase_client as _fc

        _face_recognition  = _fr
        _np                = _np_mod
        _firebase_client   = _fc
        _recognize_ready   = True
        return True
    except Exception as e:
        print(f"[server] recognize import hatasi: {e}")
        return False


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"[server] {self.address_string()} - {fmt % args}")

    def _json(self, code: int, body: dict):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    # ── GET ──────────────────────────────────────────────────────────────────

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if parsed.path == "/status":
            self._json(200, {"ok": True, "message": "Enroll sunucusu calisiyor"})
            return

        if parsed.path == "/enroll":
            uid = (params.get("uid") or [""])[0].strip()
            if not uid:
                self._json(400, {"ok": False, "message": "uid parametresi eksik"})
                return
            if not _lock.acquire(blocking=False):
                self._json(409, {"ok": False, "message": "Baska bir enrollment devam ediyor, bekleyin"})
                return
            try:
                print(f"[server] Enrollment basladi: uid={uid}")
                result = subprocess.run(
                    [PYTHON, SCRIPT, "enroll", "--uid", uid],
                    timeout=120,
                    capture_output=False,
                )
                exit_code = result.returncode
                messages = {
                    0:  "Yuz basariyla kaydedildi",
                    10: "Kullanici iptal etti",
                    11: "Kadrajda yuz bulunamadi",
                    12: "Kadrajda birden fazla yuz var",
                    13: "Kamera acilamadi",
                    14: "Firebase yazma hatasi",
                }
                msg = messages.get(exit_code, f"Bilinmeyen hata (kod {exit_code})")
                ok  = exit_code == 0
                self._json(200 if ok else 422, {"ok": ok, "message": msg, "exit_code": exit_code})
            except subprocess.TimeoutExpired:
                self._json(408, {"ok": False, "message": "Zaman asimi (120 sn)"})
            except Exception as e:
                self._json(500, {"ok": False, "message": str(e)})
            finally:
                _lock.release()
            return

        # GET /attend_face?tc=TC&session_id=SID  → Mac webcam açar, yüzü tanır, face_ok yazar
        if parsed.path == "/attend_face":
            tc = (params.get("tc") or [""])[0].strip()
            session_id = (params.get("session_id") or [""])[0].strip()
            if not tc:
                self._json(400, {"ok": False, "message": "tc parametresi eksik"})
                return
            if not _lock.acquire(blocking=False):
                self._json(409, {"ok": False, "message": "Baska bir islem devam ediyor"})
                return
            try:
                cmd = [PYTHON, str(BASE_DIR / "attend_face.py"), "--tc", tc]
                if session_id:
                    cmd += [f"--session-id={session_id}"]
                result = subprocess.run(
                    cmd,
                    timeout=60,
                    capture_output=True,
                    text=True,
                )
                import json as _json
                try:
                    body = _json.loads(result.stdout.strip().splitlines()[-1])
                except Exception:
                    ok = result.returncode == 0
                    body = {"ok": ok, "message": result.stdout.strip() or result.stderr.strip() or "Bilinmeyen sonuc"}
                self._json(200 if body.get("ok") else 422, body)
            except subprocess.TimeoutExpired:
                self._json(408, {"ok": False, "message": "Zaman asimi (60 sn)"})
            except Exception as e:
                self._json(500, {"ok": False, "message": str(e)})
            finally:
                _lock.release()
            return

        self._json(404, {"ok": False, "message": "Bilinmeyen endpoint"})

    # ── POST /recognize ───────────────────────────────────────────────────────

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path != "/recognize":
            self._json(404, {"ok": False, "message": "Bilinmeyen endpoint"})
            return

        # Body: raw JPEG/PNG bytes
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            self._json(400, {"ok": False, "message": "Goruntu verisi bos"})
            return

        img_bytes = self.rfile.read(length)

        if not _ensure_recognize_imports():
            self._json(503, {"ok": False, "message": "face_recognition modulu yuklenemedi"})
            return

        try:
            result = _recognize_and_mark(img_bytes)
            self._json(200 if result["ok"] else 422, result)
        except Exception as e:
            print(f"[server] recognize hatasi: {e}")
            self._json(500, {"ok": False, "message": str(e)})

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Content-Length")
        self.end_headers()


# ── Yüz tanıma mantığı ────────────────────────────────────────────────────────

def _recognize_and_mark(img_bytes: bytes) -> dict:
    """
    Verilen JPEG/PNG baytlarındaki yüzü tanır.
    Aktif session varsa face_ok yazar.
    """
    import numpy as np

    # 1. Görüntüyü numpy array'e çevir
    try:
        import cv2
        nparr = np.frombuffer(img_bytes, np.uint8)
        img_bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if img_bgr is None:
            return {"ok": False, "message": "Goruntu okunamadi (gecersiz format)"}
        img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    except Exception as e:
        return {"ok": False, "message": f"Goruntu isleme hatasi: {e}"}

    # 2. Fotoğraftaki yüz(leri) bul
    face_locs     = _face_recognition.face_locations(img_rgb, model="hog")
    face_encs     = _face_recognition.face_encodings(img_rgb, face_locs)

    if not face_encs:
        return {"ok": False, "message": "Fotografta yuz bulunamadi"}
    if len(face_encs) > 1:
        return {"ok": False, "message": "Fotografta birden fazla yuz var, lutfen tek yuz gosterin"}

    unknown_enc = face_encs[0]

    # 3. Kayıtlı yüzleri Firebase'den yükle
    _firebase_client.init()
    users = _firebase_client.list_users_with_face_encoding()
    if not users:
        return {"ok": False, "message": "Firebase'de kayitli yuz bulunamadi"}

    known_uids: list[str]             = []
    known_encs: list[np.ndarray]      = []
    for uid, data in users.items():
        enc = data.get("face_encoding")
        if isinstance(enc, list) and len(enc) == 128:
            try:
                known_uids.append(uid)
                known_encs.append(np.array(enc, dtype=np.float64))
            except Exception:
                continue

    if not known_encs:
        return {"ok": False, "message": "Karsilastirilacak kayitli yuz yok"}

    # 4. Karşılaştır
    THRESHOLD = 0.5
    distances  = _face_recognition.face_distance(known_encs, unknown_enc)
    best_idx   = int(np.argmin(distances))
    best_dist  = float(distances[best_idx])

    if best_dist > THRESHOLD:
        return {
            "ok":      False,
            "message": f"Yuz taninamadi (dist={best_dist:.3f})",
            "dist":    best_dist,
        }

    matched_uid = known_uids[best_idx]
    user_data   = users[matched_uid]
    ad_soyad    = user_data.get("ad_soyad") or matched_uid
    print(f"[recognize] Eslesti: {ad_soyad} ({matched_uid})  dist={best_dist:.3f}")

    # 5. Aktif session bul ve face_ok yaz
    session = _firebase_client.get_active_session()
    if session is None:
        return {
            "ok":       True,
            "tanindi":  True,
            "uid":      matched_uid,
            "ad_soyad": ad_soyad,
            "message":  f"Yuz tanindi ({ad_soyad}) ama aktif yoklama yok",
            "session":  False,
        }

    session_id, session_data = session
    ders_adi = session_data.get("ders_adi", "?")

    _firebase_client.mark_face_seen(session_id, matched_uid)
    print(f"[recognize] face_ok yazildi: session={session_id} uid={matched_uid}")

    return {
        "ok":        True,
        "tanindi":   True,
        "uid":       matched_uid,
        "ad_soyad":  ad_soyad,
        "session_id": session_id,
        "ders_adi":  ders_adi,
        "message":   f"Yuz tanindi — {ad_soyad} — {ders_adi}",
        "dist":      best_dist,
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
    except Exception:
        ip = "?"

    print(f"╔══════════════════════════════════════════╗")
    print(f"  Yuz Tanıtma + Yoklama Sunucusu")
    print(f"  Adres  : http://{ip}:{PORT}")
    print(f"  Enroll : GET  http://{ip}:{PORT}/enroll?uid=TC")
    print(f"  Yoklama: POST http://{ip}:{PORT}/recognize  (body=JPEG)")
    print(f"  Ctrl+C ile durdur")
    print(f"╚══════════════════════════════════════════╝\n")

    server = HTTPServer(("0.0.0.0", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[server] Durduruluyor...")
    finally:
        server.server_close()


if __name__ == "__main__":
    sys.exit(main() or 0)
