"""Conversione delle regioni di colore in tracciati vettoriali (millimetri).

I contorni sono estratti a precisione sub-pixel: ogni maschera viene sfumata,
ingrandita e tagliata a metà livello. Due colori confinanti condividono così
quasi esattamente lo stesso bordo, senza fessure.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

from .settings import RGB

# Un poligono è (contorno esterno, [buchi]); punti (N, 2) in mm, asse y verso il basso.
Polygon = tuple[np.ndarray, list[np.ndarray]]


@dataclass
class VectorLayer:
    rgb: RGB
    polygons: list[Polygon] = field(default_factory=list)

    @property
    def area_mm2(self) -> float:
        return sum(polygon_area(o) - sum(polygon_area(h) for h in hs) for o, hs in self.polygons)


@dataclass
class VectorResult:
    width_mm: float
    height_mm: float
    layers: list[VectorLayer]
    silhouette: list[Polygon]


def polygon_area(pts: np.ndarray) -> float:
    x, y = pts[:, 0], pts[:, 1]
    return float(abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))) / 2)


def mask_polygons(mask: np.ndarray, px_mm: float, smooth_px: float = 1.0,
                  simplify_mm: float = 0.05, level: float = 0.5,
                  min_area_mm2: float = 0.05) -> list[Polygon]:
    """Contorni di una maschera booleana come poligoni con buchi, in mm."""
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return []
    h, w = mask.shape
    pad = int(np.ceil(3 * max(smooth_px, 0.5))) + 2
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, w)
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, h)
    crop = np.zeros((y1 - y0 + 2 * pad, x1 - x0 + 2 * pad), np.float32)
    crop[pad:pad + y1 - y0, pad:pad + x1 - x0] = mask[y0:y1, x0:x1]
    ox, oy = x0 - pad, y0 - pad  # origine del ritaglio nell'immagine

    if smooth_px > 0:
        crop = cv2.GaussianBlur(crop, (0, 0), smooth_px)
    # Fattore di ingrandimento: circa 4x, limitato per non esaurire la memoria.
    f = int(max(1, min(4, 3000 // max(crop.shape))))
    big = cv2.resize(crop, (crop.shape[1] * f, crop.shape[0] * f),
                     interpolation=cv2.INTER_LINEAR) if f > 1 else crop
    binary = (big >= level).astype(np.uint8)

    contours, hier = cv2.findContours(binary, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    if hier is None:
        return []
    hier = hier[0]
    eps = max(simplify_mm / px_mm * f, 0.3)

    def to_mm(c: np.ndarray) -> np.ndarray | None:
        c = cv2.approxPolyDP(c, eps, True).reshape(-1, 2).astype(np.float64)
        if len(c) < 3:
            return None
        # Centro del pixel ingrandito -> coordinate dell'immagine originale.
        x = (c[:, 0] + 0.5) / f - 0.5 + ox
        y = (c[:, 1] + 0.5) / f - 0.5 + oy
        return np.stack([(x + 0.5) * px_mm, (y + 0.5) * px_mm], axis=1)

    polys: list[Polygon] = []
    for i, c in enumerate(contours):
        if hier[i][3] != -1:  # è un buco: viene raccolto dal suo genitore
            continue
        outer = to_mm(c)
        if outer is None or polygon_area(outer) < min_area_mm2:
            continue
        holes = []
        child = hier[i][2]
        while child != -1:
            hole = to_mm(contours[child])
            if hole is not None and polygon_area(hole) >= min_area_mm2:
                holes.append(hole)
            child = hier[child][0]
        polys.append((outer, holes))
    return polys


def vectorize(labels: np.ndarray, colors: list[RGB], px_mm: float,
              smooth_px: float = 1.0, simplify_mm: float = 0.05,
              level: float = 0.5) -> VectorResult:
    h, w = labels.shape
    layers = [
        VectorLayer(rgb, mask_polygons(labels == i, px_mm, smooth_px, simplify_mm, level))
        for i, rgb in enumerate(colors)
    ]
    silhouette = mask_polygons(labels >= 0, px_mm, smooth_px, simplify_mm, 0.5)
    return VectorResult(w * px_mm, h * px_mm, layers, silhouette)
