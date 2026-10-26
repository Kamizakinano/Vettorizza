"""Caricamento immagini e conversioni di colore."""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

IMAGE_FILTER = "Immagini (*.png *.jpg *.jpeg *.bmp *.webp *.tif *.tiff *.gif)"


def load_rgba(path: str | Path) -> np.ndarray:
    """Carica un'immagine come array RGBA uint8, rispettando l'orientamento EXIF."""
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im)
        im = im.convert("RGBA")
        return np.array(im)


def resize_max(img: np.ndarray, max_side: int) -> np.ndarray:
    h, w = img.shape[:2]
    scale = max_side / max(h, w)
    if scale >= 1:
        return img
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    return cv2.resize(img, size, interpolation=cv2.INTER_AREA)


def rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """RGB uint8 (..., 3) -> CIELab float32 (L 0..100)."""
    shape = rgb.shape
    flat = rgb.reshape(-1, 1, 3).astype(np.float32) / 255.0
    return cv2.cvtColor(flat, cv2.COLOR_RGB2LAB).reshape(shape)


def lab_to_rgb(lab: np.ndarray) -> np.ndarray:
    shape = lab.shape
    flat = lab.reshape(-1, 1, 3).astype(np.float32)
    rgb = cv2.cvtColor(flat, cv2.COLOR_LAB2RGB).reshape(shape)
    return np.clip(np.round(rgb * 255), 0, 255).astype(np.uint8)


def hex_color(rgb) -> str:
    return "#{:02X}{:02X}{:02X}".format(*(int(c) for c in rgb[:3]))


def parse_hex(text: str) -> tuple[int, int, int]:
    t = text.strip().lstrip("#")
    if len(t) == 3:
        t = "".join(c * 2 for c in t)
    if len(t) != 6:
        raise ValueError(f"Colore non valido: {text}")
    return int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16)


def luminance(rgb) -> float:
    r, g, b = (int(c) for c in rgb[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def checkerboard(h: int, w: int, cell: int = 12) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w]
    board = ((yy // cell + xx // cell) % 2).astype(np.uint8)
    out = np.where(board[..., None] == 1, 205, 245).astype(np.uint8)
    return np.repeat(out, 3, axis=2)
