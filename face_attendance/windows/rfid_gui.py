# -*- coding: utf-8 -*-
"""
rfid_gui.py  -  Windows RFID Yonetim Arayyuzu
=============================================
Iki sekme:
  1. Kart Tanitma   ogrenciye RFID karti ata
  2. Yoklama        ders sirasinda kartlari Firebase'e gonder

Kullanim:
    python rfid_gui.py
    (serviceAccountKey.json bu klasorde olmali)
"""

from __future__ import annotations

import os
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from queue import Queue, Empty
from tkinter import ttk, messagebox, font as tkfont

# rfid_to_firebase.py ile ayni klasorde
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

#  Renk paleti 
C_BG      = "#F4F6FA"
C_CARD    = "#FFFFFF"
C_NEU     = "#005A71"
C_NEU2    = "#007A96"
C_GREEN   = "#2E7D32"
C_RED     = "#C62828"
C_ORANGE  = "#E65100"
C_GRAY    = "#9E9E9E"
C_TEXT    = "#212121"
C_BORDER  = "#DEE2E6"

#  Firebase lazy init 
_fb_ready = False
_fb_error: str | None = None
_db = None

def _ensure_firebase() -> bool:
    global _fb_ready, _fb_error, _db
    if _fb_ready:
        return True
    if _fb_error:
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials, db as fb_db
        key = BASE_DIR / "serviceAccountKey.json"
        if not key.exists():
            _fb_error = f"serviceAccountKey.json bulunamadi:\n{key}"
            return False
        if not firebase_admin._apps:
            cred = credentials.Certificate(str(key))
            firebase_admin.initialize_app(cred, {
                "databaseURL": "https://finalproject-eb873-default-rtdb.firebaseio.com"
            })
        _db = fb_db
        _fb_ready = True
        return True
    except Exception as e:
        _fb_error = str(e)
        return False

#  AntennaClient (rfid_to_firebase.py'den kopyalandi) 
import http.client, re
from typing import Optional

POLL_INTERVAL_SEC = 0.25
HTTP_TIMEOUT_SEC  = 3.0
DEDUPE_WINDOW_SEC = 3.0

DATA_LINE_REGEX = re.compile(
    r"\d{2}:\d{2}:\d{2}\s*;\s*\d{2}/\d{2}/\d{4}\s*;\s*[\d.]+\s*V\s*;\s*"
    r"[0-9a-fA-F]+\s*;\s*(\d+)\s*;\s*(.*?);;",
    re.DOTALL,
)
UID_FIELD_REGEX = re.compile(r"^[0-9a-fA-F]{8,}$")

class AntennaClient:
    def __init__(self, host: str, port: int = 80) -> None:
        self.host = host; self.port = port
        self.queue: Queue[str] = Queue()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self.connected = False

    def start(self):
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()

    def _loop(self):
        errs = 0
        while not self._stop.is_set():
            try:
                data = self._fetch()
                self.connected = True; errs = 0
                if data: self._extract(data)
            except Exception:
                self.connected = False; errs += 1
                self._stop.wait(min(2.0, POLL_INTERVAL_SEC * 4))
                continue
            self._stop.wait(POLL_INTERVAL_SEC)

    def _fetch(self) -> str:
        conn = http.client.HTTPConnection(self.host, self.port, timeout=HTTP_TIMEOUT_SEC)
        try:
            conn.request("GET", "/")
            return conn.getresponse().read().decode("utf-8", errors="ignore")
        finally:
            conn.close()

    def _extract(self, body: str):
        seen = set()
        for m in DATA_LINE_REGEX.finditer(body):
            for part in m.group(2).split(";"):
                uid = part.strip().lower()
                if uid and UID_FIELD_REGEX.match(uid) and uid not in seen:
                    seen.add(uid); self.queue.put(uid)

    def flush(self):
        try: self._fetch()
        except: pass
        while not self.queue.empty():
            try: self.queue.get_nowait()
            except Empty: break

    def sample(self, secs: float) -> set:
        uids: set = set()
        deadline = time.time() + secs
        while time.time() < deadline:
            try: uids.add(self.queue.get(timeout=0.2))
            except Empty: pass
        return uids

    def next_uid(self, timeout=1.0) -> str | None:
        try: return self.queue.get(timeout=timeout)
        except Empty: return None


# 
#  Ana pencere
# 

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("RFID Yonetim Sistemi")
        self.geometry("820x600")
        self.minsize(700, 500)
        self.configure(bg=C_BG)
        self.resizable(True, True)

        # Anten baglanti ayarlari
        self._antenna_host = tk.StringVar(value="192.168.137.87")
        self._antenna_port = tk.IntVar(value=80)
        self._client: AntennaClient | None = None

        self._build_ui()
        self._init_firebase_async()

    #  UI yapisi 
    def _build_ui(self):
        # pst baslik
        header = tk.Frame(self, bg=C_NEU, height=56)
        header.pack(fill="x")
        header.pack_propagate(False)
        tk.Label(header, text="  RFID Yonetim Sistemi",
                 font=("Segoe UI", 14, "bold"), fg="white", bg=C_NEU).pack(
                     side="left", padx=20, pady=14)

        # Firebase durum etiketi
        self._fb_lbl = tk.Label(header, text=" Firebase baglaniyor...",
                                font=("Segoe UI", 10), fg="#AEDDE8", bg=C_NEU)
        self._fb_lbl.pack(side="right", padx=20)

        # Anten ayar cubugu
        bar = tk.Frame(self, bg=C_BORDER, height=1)
        bar.pack(fill="x")
        cfg = tk.Frame(self, bg=C_BG, pady=8)
        cfg.pack(fill="x", padx=16)
        tk.Label(cfg, text="Anten IP:", bg=C_BG, fg=C_TEXT,
                 font=("Segoe UI", 10)).pack(side="left")
        tk.Entry(cfg, textvariable=self._antenna_host, width=16,
                 font=("Segoe UI", 10)).pack(side="left", padx=(4,12))
        tk.Label(cfg, text="Port:", bg=C_BG, fg=C_TEXT,
                 font=("Segoe UI", 10)).pack(side="left")
        tk.Entry(cfg, textvariable=self._antenna_port, width=6,
                 font=("Segoe UI", 10)).pack(side="left", padx=(4,0))
        self._conn_lbl = tk.Label(cfg, text="", bg=C_BG,
                                  font=("Segoe UI", 10))
        self._conn_lbl.pack(side="left", padx=16)

        # Sekmeler
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("TNotebook", background=C_BG, borderwidth=0)
        style.configure("TNotebook.Tab", font=("Segoe UI", 11),
                        padding=[16, 8], background=C_BG, foreground=C_GRAY)
        style.map("TNotebook.Tab",
                  background=[("selected", C_CARD)],
                  foreground=[("selected", C_NEU)])

        self._nb = ttk.Notebook(self)
        self._nb.pack(fill="both", expand=True, padx=0, pady=0)

        self._enroll_tab = EnrollTab(self._nb, self)
        self._listen_tab = ListenTab(self._nb, self)
        self._nb.add(self._enroll_tab, text="    Kart Tanitma  ")
        self._nb.add(self._listen_tab, text="    Yoklama       ")

    def get_client(self) -> AntennaClient | None:
        host = self._antenna_host.get().strip()
        if not host:
            return None
        if self._client is None or \
           self._client.host != host or self._client.port != self._antenna_port.get():
            if self._client:
                self._client.stop()
            self._client = AntennaClient(host, self._antenna_port.get())
            self._client.start()
            self._poll_connection()
        return self._client

    def _poll_connection(self):
        if self._client and self._client.connected:
            self._conn_lbl.config(text=" Anten bagli", fg=C_GREEN)
        else:
            self._conn_lbl.config(text=" Anten baglanamadi", fg=C_RED)
        self.after(1500, self._poll_connection)

    def _init_firebase_async(self):
        def run():
            ok = _ensure_firebase()
            self.after(0, lambda: self._fb_lbl.config(
                text=" Firebase bagli" if ok else f" Firebase hatasi",
                fg="#AEDDE8" if ok else "#FFCDD2"
            ))
            if ok:
                self.after(500, self._enroll_tab.load_students)
        threading.Thread(target=run, daemon=True).start()


# 
#  SEKME 1  Kart Tanitma
# 

class EnrollTab(tk.Frame):
    def __init__(self, parent, app: App):
        super().__init__(parent, bg=C_BG)
        self._app = app
        self._students: list[tuple[str, dict, str]] = []   # (key, data, source)
        self._selected_idx: int | None = None
        self._enrolling = False
        self._build()

    def _build(self):
        # Sol: ogrenci listesi
        left = tk.Frame(self, bg=C_BG)
        left.pack(side="left", fill="both", expand=True, padx=(16,8), pady=16)

        tk.Label(left, text="RFID Kart Atanmamis Ogrenciler",
                 font=("Segoe UI", 11, "bold"), fg=C_NEU, bg=C_BG).pack(anchor="w")

        # Arama
        sf = tk.Frame(left, bg=C_BG)
        sf.pack(fill="x", pady=(6,4))
        self._search_var = tk.StringVar()
        self._search_var.trace_add("write", lambda *_: self._filter())
        tk.Entry(sf, textvariable=self._search_var, font=("Segoe UI", 10),
                 relief="solid", bd=1).pack(side="left", fill="x", expand=True)
        tk.Button(sf, text=" Yenile", font=("Segoe UI", 9),
                  bg=C_NEU, fg="white", relief="flat", padx=8,
                  command=self.load_students).pack(side="left", padx=(6,0))

        # Liste
        listframe = tk.Frame(left, bg=C_BG)
        listframe.pack(fill="both", expand=True)
        sb = tk.Scrollbar(listframe)
        sb.pack(side="right", fill="y")
        self._listbox = tk.Listbox(listframe, yscrollcommand=sb.set,
                                   font=("Segoe UI", 10), selectbackground=C_NEU,
                                   selectforeground="white", activestyle="none",
                                   relief="solid", bd=1, bg=C_CARD)
        self._listbox.pack(fill="both", expand=True)
        sb.config(command=self._listbox.yview)
        self._listbox.bind("<<ListboxSelect>>", self._on_select)

        # Sag: kart atama paneli
        right = tk.Frame(self, bg=C_CARD, bd=1, relief="solid",
                         width=280)
        right.pack(side="right", fill="y", padx=(0,16), pady=16)
        right.pack_propagate(False)

        inner = tk.Frame(right, bg=C_CARD)
        inner.pack(fill="both", expand=True, padx=20, pady=20)

        tk.Label(inner, text="Secili Ogrenci",
                 font=("Segoe UI", 10, "bold"), fg=C_GRAY, bg=C_CARD).pack(anchor="w")
        self._sel_lbl = tk.Label(inner, text=" secim yok ",
                                 font=("Segoe UI", 12, "bold"), fg=C_TEXT,
                                 bg=C_CARD, wraplength=240, justify="left")
        self._sel_lbl.pack(anchor="w", pady=(4,0))
        self._sel_sub = tk.Label(inner, text="",
                                 font=("Segoe UI", 9), fg=C_GRAY, bg=C_CARD)
        self._sel_sub.pack(anchor="w")

        tk.Frame(inner, bg=C_BORDER, height=1).pack(fill="x", pady=12)

        self._enroll_btn = tk.Button(inner, text="  Karti Tara",
                                     font=("Segoe UI", 11, "bold"),
                                     bg=C_NEU, fg="white", relief="flat",
                                     padx=12, pady=10,
                                     command=self._start_enroll,
                                     state="disabled")
        self._enroll_btn.pack(fill="x")

        self._status_lbl = tk.Label(inner, text="",
                                    font=("Segoe UI", 10), fg=C_TEXT,
                                    bg=C_CARD, wraplength=240, justify="left")
        self._status_lbl.pack(anchor="w", pady=(12,0))

        # Ilerleme cubugu (gizli)
        self._progress = ttk.Progressbar(inner, mode="indeterminate")

    def load_students(self):
        self._listbox.delete(0, "end")
        self._listbox.insert("end", "   Yukleniyor...")
        self._listbox.config(state="disabled")
        def run():
            if not _ensure_firebase():
                self.after(0, lambda: self._set_status(" Firebase baglantisi yok", C_RED))
                return
            try:
                users      = _db.reference("users").get() or {}
                on_kayitlar = _db.reference("on_kayitlar").get() or {}
                result = []
                # on_kayitlar (ogrenciler)
                for tc, data in on_kayitlar.items():
                    if isinstance(data, dict) and not data.get("rfid_uid"):
                        result.append((tc, data, "on_kayitlar"))
                # users icinden ogrenci rolundekiler
                for uid, data in users.items():
                    if not isinstance(data, dict): continue
                    roller = data.get("roller", {})
                    if isinstance(roller, dict) and roller.get("ogrenci") and not data.get("rfid_uid"):
                        result.append((uid, data, "users"))
                self._students = result
                self.after(0, self._fill_list)
            except Exception as e:
                self.after(0, lambda: self._set_status(f" Hata: {e}", C_RED))
        threading.Thread(target=run, daemon=True).start()

    def _fill_list(self):
        self._listbox.config(state="normal")
        self._listbox.delete(0, "end")
        q = self._search_var.get().lower()
        self._filtered: list[int] = []
        for i, (key, data, src) in enumerate(self._students):
            ad = _display_name(data)
            okul = data.get("okul_no") or data.get("ogrenci_no") or ""
            text = f"  {ad}"
            if okul: text += f"  ({okul})"
            if q and q not in ad.lower() and q not in str(okul).lower():
                continue
            self._listbox.insert("end", text)
            self._filtered.append(i)
        if not self._filtered:
            self._listbox.insert("end", "  Kayit bulunamadi")

    def _filter(self):
        self._fill_list()
        self._selected_idx = None
        self._sel_lbl.config(text=" secim yok ")
        self._sel_sub.config(text="")
        self._enroll_btn.config(state="disabled")

    def _on_select(self, _):
        sel = self._listbox.curselection()
        if not sel or not hasattr(self, "_filtered"):
            return
        li = sel[0]
        if li >= len(self._filtered): return
        idx = self._filtered[li]
        key, data, src = self._students[idx]
        self._selected_idx = idx
        ad = _display_name(data)
        okul = data.get("okul_no") or data.get("ogrenci_no") or ""
        tc = data.get("tc_no") or key if src == "on_kayitlar" else ""
        self._sel_lbl.config(text=ad)
        self._sel_sub.config(text=f"Okul No: {okul}  |  TC: {tc}")
        self._enroll_btn.config(state="normal" if not self._enrolling else "disabled")
        self._set_status("", C_TEXT)

    def _start_enroll(self):
        if self._selected_idx is None: return
        key, data, src = self._students[self._selected_idx]
        ad = _display_name(data)
        client = self._app.get_client()
        if client is None:
            self._set_status(" Anten IP girilmemis.", C_RED); return

        self._enrolling = True
        self._enroll_btn.config(state="disabled", text=" Isleniyor...")
        self._progress.pack(fill="x", pady=(8,0))
        self._progress.start(12)
        self._set_status(f" Anten baglaniyor ve buffer temizleniyor...", C_ORANGE)

        def run():
            try:
                time.sleep(1.0)
                client.flush()
                self.after(0, lambda: self._set_status(" Arka plan taraniyor (3 sn)...", C_ORANGE))
                background = client.sample(3.0)
                self.after(0, lambda: self._set_status(
                    f" Lutfen '{ad}' kartini antene tutun...", C_NEU))
                client.flush()
                time.sleep(0.5)
                with_card = client.sample(4.0)
                new_uids = with_card - background
                if not new_uids:
                    self.after(0, lambda: self._set_status(
                        " Kart okunamadi. Kart araliga uygun mu?\nTekrar deneyin.", C_RED))
                    return
                uid = next(iter(new_uids))
                # Birden fazlaysa ilkini al
                if len(new_uids) > 1:
                    uid = sorted(new_uids)[0]
                # Firebase'e yaz
                _db.reference(f"{src}/{key}").update({"rfid_uid": uid})
                _db.reference(f"rfid_index/{uid}").set(key)
                self.after(0, lambda: self._set_status(
                    f" Basarili!\n{ad}\n{uid}", C_GREEN))
                # Listeden cikar
                self._students.pop(self._selected_idx)
                self._selected_idx = None
                self.after(0, self._fill_list)
                self.after(0, lambda: self._sel_lbl.config(text=" secim yok "))
                self.after(0, lambda: self._sel_sub.config(text=""))
            except Exception as e:
                self.after(0, lambda: self._set_status(f" Hata: {e}", C_RED))
            finally:
                self.after(0, self._enroll_done)

        threading.Thread(target=run, daemon=True).start()

    def _enroll_done(self):
        self._enrolling = False
        self._enroll_btn.config(state="disabled" if self._selected_idx is None else "normal",
                                text="  Karti Tara")
        self._progress.stop()
        self._progress.pack_forget()

    def _set_status(self, msg: str, color: str = C_TEXT):
        self._status_lbl.config(text=msg, fg=color)


# 
#  SEKME 2  Yoklama (Listen)
# 

class ListenTab(tk.Frame):
    def __init__(self, parent, app: App):
        super().__init__(parent, bg=C_BG)
        self._app = app
        self._listening = False
        self._listen_thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._last_pushed: dict[str, float] = {}
        self._build()

    def _build(self):
        # pst kontrol paneli
        top = tk.Frame(self, bg=C_CARD, bd=1, relief="solid")
        top.pack(fill="x", padx=16, pady=(16,8))

        inner = tk.Frame(top, bg=C_CARD)
        inner.pack(fill="x", padx=16, pady=12)

        tk.Label(inner, text="Yoklama Modu",
                 font=("Segoe UI", 12, "bold"), fg=C_NEU, bg=C_CARD).pack(side="left")

        self._listen_btn = tk.Button(inner, text="  Baslat",
                                     font=("Segoe UI", 10, "bold"),
                                     bg=C_GREEN, fg="white", relief="flat",
                                     padx=16, pady=6,
                                     command=self._toggle)
        self._listen_btn.pack(side="right")

        self._dur_lbl = tk.Label(inner, text="",
                                 font=("Segoe UI", 10), fg=C_GRAY, bg=C_CARD)
        self._dur_lbl.pack(side="right", padx=16)

        # Log alani
        log_frame = tk.Frame(self, bg=C_BG)
        log_frame.pack(fill="both", expand=True, padx=16, pady=(0,16))

        tk.Label(log_frame, text="Okunan Kartlar",
                 font=("Segoe UI", 10, "bold"), fg=C_NEU, bg=C_BG).pack(anchor="w")

        sb = tk.Scrollbar(log_frame)
        sb.pack(side="right", fill="y")
        self._log = tk.Text(log_frame, yscrollcommand=sb.set,
                             font=("Consolas", 10), state="disabled",
                             relief="solid", bd=1, bg=C_CARD,
                             spacing3=4)
        self._log.pack(fill="both", expand=True)
        sb.config(command=self._log.yview)

        # Renk etiketleri
        self._log.tag_config("ok",     foreground=C_GREEN)
        self._log.tag_config("warn",   foreground=C_ORANGE)
        self._log.tag_config("error",  foreground=C_RED)
        self._log.tag_config("info",   foreground=C_GRAY)
        self._log.tag_config("ts",     foreground=C_GRAY)
        self._log.tag_config("bold",   font=("Consolas", 10, "bold"))

        # Temizle butonu
        tk.Button(log_frame, text=" Temizle", font=("Segoe UI", 9),
                  bg=C_BG, fg=C_GRAY, relief="flat",
                  command=self._clear_log).pack(anchor="e", pady=(4,0))

    def _toggle(self):
        if not self._listening:
            self._start()
        else:
            self._stop()

    def _start(self):
        if not _ensure_firebase():
            messagebox.showerror("Hata", f"Firebase baglantisi yok:\n{_fb_error}")
            return
        client = self._app.get_client()
        if client is None:
            messagebox.showerror("Hata", "Anten IP girilmemis.")
            return
        self._listening = True
        self._stop_event.clear()
        self._last_pushed.clear()
        self._listen_btn.config(text="  Durdur", bg=C_RED)
        self._log_append(" Dinleme baslatildi ", "info")
        self._listen_thread = threading.Thread(target=self._loop, args=(client,), daemon=True)
        self._listen_thread.start()
        self._update_dur(time.time())

    def _stop(self):
        self._listening = False
        self._stop_event.set()
        self._listen_btn.config(text="  Baslat", bg=C_GREEN)
        self._dur_lbl.config(text="")
        self._log_append(" Dinleme durduruldu ", "info")

    def _loop(self, client: AntennaClient):
        time.sleep(0.5)
        client.flush()
        while not self._stop_event.is_set():
            uid = client.next_uid(timeout=1.0)
            if not uid: continue
            now = time.time()
            if now - self._last_pushed.get(uid, 0.0) < DEDUPE_WINDOW_SEC:
                continue
            self._last_pushed[uid] = now
            self._push_uid(uid, now)

    def _push_uid(self, uid: str, ts: float):
        try:
            _db.reference("rfid_events").push({
                "uid": uid,
                "ts": int(ts * 1000),
                "device": "main_door_antenna",
                "consumed": False,
            })
            # Sahibini bul
            owner_key = _db.reference(f"rfid_index/{uid}").get()
            if owner_key:
                owner = (_db.reference(f"on_kayitlar/{owner_key}").get() or
                         _db.reference(f"users/{owner_key}").get() or {})
                ad = _display_name(owner) if isinstance(owner, dict) else "?"
                self.after(0, lambda u=uid, a=ad: self._log_ok(u, a))
            else:
                self.after(0, lambda u=uid: self._log_warn(u))
        except Exception as e:
            self.after(0, lambda: self._log_append(f" Firebase hatasi: {e}", "error"))

    def _log_ok(self, uid: str, ad: str):
        zaman = time.strftime("%H:%M:%S")
        self._log_append(f"[{zaman}]  ", "ts", newline=False)
        self._log_append(f"  {ad}", "ok bold", newline=False)
        self._log_append(f"   {uid}\n", "info")

    def _log_warn(self, uid: str):
        zaman = time.strftime("%H:%M:%S")
        self._log_append(f"[{zaman}]  ", "ts", newline=False)
        self._log_append(f"  Kayitsiz kart: {uid}\n", "warn")

    def _log_append(self, text: str, tag: str = "", newline: bool = True):
        self._log.config(state="normal")
        self._log.insert("end", (text + "\n") if newline else text, tag)
        self._log.see("end")
        self._log.config(state="disabled")

    def _clear_log(self):
        self._log.config(state="normal")
        self._log.delete("1.0", "end")
        self._log.config(state="disabled")

    def _update_dur(self, start: float):
        if not self._listening: return
        elapsed = int(time.time() - start)
        m, s = divmod(elapsed, 60)
        self._dur_lbl.config(text=f" {m:02d}:{s:02d}")
        self.after(1000, lambda: self._update_dur(start))


#  Yardimcilar 

def _display_name(data: dict) -> str:
    if data.get("ad_soyad"): return str(data["ad_soyad"])
    ad = data.get("ad") or data.get("isim") or "?"
    soyad = data.get("soyad") or ""
    return f"{ad} {soyad}".strip()


#  Giris noktasi 

if __name__ == "__main__":
    app = App()
    app.mainloop()
