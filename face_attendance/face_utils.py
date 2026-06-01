"""
Yüz tanıma yardımcıları: kamera açma, encoding hesabı, karşılaştırma.

face_recognition kütüphanesi 128 boyutlu bir vektör (dlib face encoding) döner.
Bu vektörü Firebase'de saklayıp karşılaştırırız.
"""

from __future__ import annotations

from typing import Iterator, Optional

import cv2
import face_recognition
import numpy as np

import config


# ---- Kamera ----

class Camera:
    """OpenCV VideoCapture etrafında ince bir sarmalayıcı."""

    def __init__(self, device_index: int = 0) -> None:
        self.device_index = device_index
        self._cap: Optional[cv2.VideoCapture] = None

    def __enter__(self):
        self._cap = cv2.VideoCapture(self.device_index)
        if not self._cap.isOpened():
            raise RuntimeError(
                f"Kamera acilamadi (index={self.device_index}). "
                "macOS'ta Terminal'e kamera izni vermeyi unutmayin: "
                "System Settings > Privacy & Security > Camera"
            )
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self._cap is not None:
            self._cap.release()
            self._cap = None
        cv2.destroyAllWindows()

    def read(self) -> Optional[np.ndarray]:
        if self._cap is None:
            return None
        ok, frame = self._cap.read()
        return frame if ok else None

    def frames(self) -> Iterator[np.ndarray]:
        while True:
            frame = self.read()
            if frame is None:
                break
            yield frame


# ---- Encoding hesabı ----

def bgr_to_rgb(frame: np.ndarray) -> np.ndarray:
    """OpenCV BGR -> face_recognition'in beklediği RGB."""
    return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)


def encode_face_from_frame(frame: np.ndarray) -> Optional[np.ndarray]:
    """
    Tek bir frame'den, kadrajda tek bir yüz varsa 128-d encoding döner.
    Birden fazla yüz veya hiç yüz yoksa None döner (enroll için bu şart).
    """
    rgb = bgr_to_rgb(frame)
    locations = face_recognition.face_locations(rgb, model=config.FACE_DETECTION_MODEL)
    if len(locations) != 1:
        return None
    encodings = face_recognition.face_encodings(rgb, locations)
    return encodings[0] if encodings else None


def encode_face_from_file(path: str) -> Optional[np.ndarray]:
    """Bir fotoğraf dosyasından encoding üretir."""
    image = face_recognition.load_image_file(path)
    locations = face_recognition.face_locations(image, model=config.FACE_DETECTION_MODEL)
    if not locations:
        return None
    encodings = face_recognition.face_encodings(image, locations)
    return encodings[0] if encodings else None


# ---- Karşılaştırma ----

def match_face(
    unknown: np.ndarray,
    known_db: dict[str, np.ndarray],
    tolerance: float = config.FACE_MATCH_TOLERANCE,
) -> Optional[tuple[str, float]]:
    """
    unknown encoding'i bilinen encoding sözlüğüyle karşılaştırır.
    En yakın eşleşmeyi (uid, distance) olarak döner; tolerance içinde değilse None.
    """
    if not known_db:
        return None

    uids = list(known_db.keys())
    matrix = np.array([known_db[u] for u in uids])
    distances = face_recognition.face_distance(matrix, unknown)
    best_idx = int(np.argmin(distances))
    best_dist = float(distances[best_idx])
    if best_dist <= tolerance:
        return uids[best_idx], best_dist
    return None


# ---- Görselleştirme (debug için kutucuk çiz) ----

def draw_box(
    frame: np.ndarray,
    location: tuple[int, int, int, int],
    label: str,
    color: tuple[int, int, int] = (0, 200, 0),
) -> None:
    """frame üstüne yüz kutusu + label çizer (in-place)."""
    top, right, bottom, left = location
    cv2.rectangle(frame, (left, top), (right, bottom), color, 2)
    cv2.rectangle(frame, (left, bottom - 22), (right, bottom), color, cv2.FILLED)
    cv2.putText(
        frame, label, (left + 6, bottom - 6),
        cv2.FONT_HERSHEY_DUPLEX, 0.5, (255, 255, 255), 1,
    )
