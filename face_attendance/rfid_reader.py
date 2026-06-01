"""
RFID okuyucu donanım soyutlaması.

Şu an üç implementasyon iskeleti var:
- StdinRfidReader: klavyeden UID girip Enter'a basılır (geliştirme/demo).
- SerialRfidReader: Arduino + RC522 sketch'i UID'yi seri porta '\\n' ile basar.
- UsbHidRfidReader: USB klavye-emülasyon kartları için - klavye gibi yazar,
  o yüzden zaten stdin ile çalışır.

İleride MFRC522'yi Pi'de SPI'dan okumak için MfrcRfidReader eklenecek.

Her okuyucu read_uid() metodunda bloke olarak bir UID döner veya None
(timeout) verir. Akış kontrolü main loop'a aittir.
"""

from __future__ import annotations

import sys
import threading
import time
from queue import Queue, Empty
from typing import Optional, Any

import config


class BaseRfidReader:
    """Tüm RFID okuyucuların ortak arayüzü."""

    def start(self) -> None:
        """Arka plan okuma thread'ini başlatır (gerekiyorsa)."""
        raise NotImplementedError

    def stop(self) -> None:
        """Okuyucuyu kapatır."""
        raise NotImplementedError

    def read_uid(self, timeout: float = 1.0) -> Optional[str]:
        """timeout saniye içinde gelen UID'yi döner, yoksa None."""
        raise NotImplementedError


# --- stdin: klavyeden UID girin, Enter ---

class StdinRfidReader(BaseRfidReader):
    """
    Geliştirme modu. Konsola UID yazıp Enter'a basın → okuma sayılır.
    Boş satır 'kart yok' demek.
    """

    def __init__(self) -> None:
        self._queue: Queue[str] = Queue()
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()

    def start(self) -> None:
        if self._thread is not None:
            return
        self._thread = threading.Thread(target=self._reader_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _reader_loop(self) -> None:
        # stdin'den bloke okuma; thread daemon olduğu için ana program çıkınca biter
        for line in sys.stdin:
            if self._stop.is_set():
                break
            uid = line.strip().upper()
            if uid:
                self._queue.put(uid)

    def read_uid(self, timeout: float = 1.0) -> Optional[str]:
        try:
            return self._queue.get(timeout=timeout)
        except Empty:
            return None


# --- serial: Arduino/RC522 sketch UID'yi seri porta basar ---

class SerialRfidReader(BaseRfidReader):
    """
    Arduino + RC522 senaryosu için. Sketch örnek çıktısı:

        UID: A4 B7 2F 19

    Biz yalnız hex kısmını alır birleştiririz.
    pyserial gerekir, ihtiyaç olunca pip install yapıp aktifleştirin.
    """

    def __init__(self, port: str = config.RFID_SERIAL_PORT, baud: int = config.RFID_SERIAL_BAUD) -> None:
        self.port = port
        self.baud = baud
        self._queue: Queue[str] = Queue()
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._serial = None

    def start(self) -> None:
        try:
            import serial  # type: ignore
        except ImportError as exc:
            raise RuntimeError(
                "SerialRfidReader pyserial gerektirir. "
                "Kurmak icin: pip install pyserial"
            ) from exc

        self._serial = serial.Serial(self.port, self.baud, timeout=1)
        self._thread = threading.Thread(target=self._reader_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._serial is not None:
            self._serial.close()
            self._serial = None

    def _reader_loop(self) -> None:
        while not self._stop.is_set() and self._serial is not None:
            try:
                raw = self._serial.readline().decode("utf-8", errors="ignore").strip()
            except Exception:
                time.sleep(0.1)
                continue
            if not raw:
                continue
            # "UID: A4 B7 2F 19" formatından sadece hex kısmı
            tail = raw.split(":", 1)[-1].strip()
            uid = "".join(tail.split()).upper()
            if uid:
                self._queue.put(uid)

    def read_uid(self, timeout: float = 1.0) -> Optional[str]:
        try:
            return self._queue.get(timeout=timeout)
        except Empty:
            return None


# --- firebase: Windows server / ESP32-WiFi senaryosu ---

class FirebaseRfidReader(BaseRfidReader):
    """
    Anten + ESP32 + Windows-server senaryosu icin.

    Mimari:
        [UHF Anten + ESP32]  --WiFi-->  [Windows app, port 3000]
                                              |
                                              v
                                    [Firebase: rfid_events/{push_id}]
                                              |
                                              v
                                    [Bu reader: dinler ve isler]

    Beklenen Firebase yapisi:
        rfid_events/{auto_push_id}/
          ├─ uid: "A4B72F19"
          ├─ ts: 1716552120000
          ├─ device: "main_door_antenna"   (opsiyonel)
          └─ consumed: false               (islendi mi)

    Bu reader yeni event'leri dinler, UID'yi queue'ya koyar, event'i
    consumed=true olarak isaretler (gerekirse siler).

    Mac ve Windows ayni WiFi'de olmasina gerek yok - sadece internet
    baglantisi yeterli.
    """

    def __init__(self, device_filter: Optional[str] = None, delete_after: bool = True) -> None:
        """
        device_filter: Sadece bu device_id'den gelen event'leri dinle. None ise hepsi.
        delete_after: Event'i isledikten sonra Firebase'den sil (True onerilir).
        """
        self.device_filter = device_filter
        self.delete_after = delete_after
        self._queue: Queue[str] = Queue()
        self._listener = None
        self._stop = threading.Event()

    def start(self) -> None:
        # Firebase Admin SDK'nin Realtime DB listener'i ayri thread'de calisir
        from firebase_admin import db  # local import - firebase_client.init'i once cagirmis olmali
        import firebase_client
        firebase_client.init()

        events_ref = db.reference("rfid_events")

        def on_event(event):
            # event.data: yeni eklenen child'in icerigi
            # event.path: "/{push_id}" formati
            if self._stop.is_set():
                return
            if event.event_type != "put":
                return
            if event.path == "/":
                # Ilk snapshot - tum mevcut verileri donduruyor; her birini sirayla isle
                if isinstance(event.data, dict):
                    for push_id, payload in event.data.items():
                        self._handle_event(push_id, payload)
                return
            push_id = event.path.lstrip("/")
            self._handle_event(push_id, event.data)

        # listen() bloklayan bir cagri - thread icinde acmak gerek
        def listener_thread():
            try:
                self._listener = events_ref.listen(on_event)
            except Exception as exc:
                print(f"[firebase-rfid] listener kapandi: {exc}", file=__import__('sys').stderr)

        t = threading.Thread(target=listener_thread, daemon=True)
        t.start()

    def _handle_event(self, push_id: str, payload) -> None:
        if not isinstance(payload, dict):
            return
        if payload.get("consumed"):
            return  # Zaten islenmis
        uid = payload.get("uid")
        if not uid:
            return
        if self.device_filter and payload.get("device") != self.device_filter:
            return
        self._queue.put(str(uid).strip().upper())

        # Firebase'de isaretle/sil
        from firebase_admin import db
        ref = db.reference(f"rfid_events/{push_id}")
        if self.delete_after:
            ref.delete()
        else:
            ref.update({"consumed": True, "consumed_ts": int(time.time() * 1000)})

    def stop(self) -> None:
        self._stop.set()
        if self._listener is not None:
            try:
                self._listener.close()
            except Exception:
                pass

    def read_uid(self, timeout: float = 1.0) -> Optional[str]:
        try:
            return self._queue.get(timeout=timeout)
        except Empty:
            return None


# --- mock: donanim yokken otomatik UID uretir ---

class MockRfidReader(BaseRfidReader):
    """
    Donanim yokken kullanilan sahte okuyucu. Onceden tanimli bir UID
    listesinden, belirli araliklarla siradaki UID'yi 'okur'.

    Kullanim ornegi (config.py):
        RFID_READER_TYPE = "mock"
        MOCK_RFID_UIDS = ["TEST001", "TEST002", "TEST003"]
        MOCK_RFID_INTERVAL_SEC = 8.0   # her 8 saniyede bir UID basar

    UID'ler bittiginde tekrar bastan baslar (donguler). Demo/sunum icin
    butun ogrencilerin sirayla sinifa girmesini simule etmeye yarar.
    """

    def __init__(
        self,
        uids: list[str] | None = None,
        interval_sec: float | None = None,
    ) -> None:
        self.uids = uids or getattr(config, "MOCK_RFID_UIDS", [])
        self.interval = interval_sec or getattr(config, "MOCK_RFID_INTERVAL_SEC", 8.0)
        self._queue: Queue[str] = Queue()
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()

    def start(self) -> None:
        if not self.uids:
            print("[mock-rfid] UYARI: MOCK_RFID_UIDS bos, hicbir kart okunmayacak")
            return
        if self._thread is not None:
            return
        self._thread = threading.Thread(target=self._reader_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _reader_loop(self) -> None:
        idx = 0
        while not self._stop.is_set():
            if not self._stop.wait(self.interval):
                uid = self.uids[idx % len(self.uids)]
                idx += 1
                self._queue.put(uid)

    def read_uid(self, timeout: float = 1.0) -> Optional[str]:
        try:
            return self._queue.get(timeout=timeout)
        except Empty:
            return None


# --- Factory ---

def make_reader() -> BaseRfidReader:
    """config.RFID_READER_TYPE'a göre uygun reader üretir."""
    rtype = config.RFID_READER_TYPE.lower()
    if rtype == "stdin":
        return StdinRfidReader()
    if rtype == "serial":
        return SerialRfidReader()
    if rtype == "mock":
        return MockRfidReader()
    if rtype == "firebase":
        device_filter = getattr(config, "FIREBASE_RFID_DEVICE_FILTER", None)
        return FirebaseRfidReader(device_filter=device_filter)
    raise ValueError(f"Bilinmeyen RFID okuyucu tipi: {rtype}")
