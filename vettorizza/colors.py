"""Riduzione dei colori e pulizia delle regioni per la stampa multicolore."""

from __future__ import annotations

import cv2
import numpy as np

from .imaging import lab_to_rgb, rgb_to_lab
from .settings import RGB


def flatten_texture(rgb: np.ndarray, strength: int) -> np.ndarray:
    """Appiattisce texture, riflessi e rumore mantenendo i bordi netti."""
    out = rgb
    if strength <= 0:
        return out
    sp = 4 + 3 * strength
    sr = 10 + 6 * strength
    out = cv2.pyrMeanShiftFiltering(out, sp, sr)
    for _ in range(strength):
        out = cv2.bilateralFilter(out, 7, 30 + 10 * strength, 7)
    return out


def quantize(rgb: np.ndarray, mask: np.ndarray, n_colors: int,
             palette: list[RGB] | None = None) -> tuple[np.ndarray, list[RGB], list[int]]:
    """Assegna ogni pixel del soggetto a uno di ``n_colors`` colori (k-means in Lab).

    Con ``palette`` (i filamenti disponibili) ogni gruppo prende il filamento
    più vicino: gruppi diversi possono finire sullo stesso filamento.
    Restituisce (etichette con -1 per lo sfondo, colori RGB, indice di origine
    di ogni colore: la posizione nella palette dei filamenti o nel k-means).
    """
    labels = np.full(mask.shape, -1, np.int32)
    lab = rgb_to_lab(rgb)
    pix = lab[mask].astype(np.float32)
    if len(pix) == 0:
        return labels, [], []

    k = max(1, min(n_colors, len(pix)))
    rng = np.random.default_rng(0)
    sample = pix if len(pix) <= 60000 else pix[rng.choice(len(pix), 60000, replace=False)]
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.2)
    cv2.setRNGSeed(0)
    _, _, centers = cv2.kmeans(sample, k, None, criteria, 4, cv2.KMEANS_PP_CENTERS)
    assign = _nearest(pix, centers)

    if palette:
        pal_lab = rgb_to_lab(np.array(palette, np.uint8)[None]).reshape(-1, 3)
        assign = _nearest(centers, pal_lab)[assign]
        colors = [tuple(int(v) for v in c) for c in palette]
    else:
        # Colore medio reale di ogni gruppo (più fedele del centro k-means).
        colors = []
        for i in range(len(centers)):
            sel = pix[assign == i]
            c = sel.mean(axis=0) if len(sel) else centers[i]
            colors.append(tuple(int(v) for v in lab_to_rgb(c[None, None])[0, 0]))
    labels[mask] = assign
    return compact_labels(labels, colors)


def _nearest(pix: np.ndarray, centers: np.ndarray) -> np.ndarray:
    out = np.empty(len(pix), np.int32)
    step = 200000
    for s in range(0, len(pix), step):
        d = ((pix[s:s + step, None, :] - centers[None]) ** 2).sum(axis=2)
        out[s:s + step] = d.argmin(axis=1)
    return out


def compact_labels(labels: np.ndarray,
                   colors: list[RGB]) -> tuple[np.ndarray, list[RGB], list[int]]:
    """Elimina i colori non usati e li ordina per area decrescente."""
    valid = labels >= 0
    counts = np.bincount(labels[valid], minlength=len(colors)) if valid.any() else np.zeros(len(colors), int)
    order = [i for i in np.argsort(-counts, kind="stable") if counts[i] > 0]
    remap = np.full(max(len(colors), 1), -1, np.int32)
    for new, old in enumerate(order):
        remap[old] = new
    out = labels.copy()
    out[valid] = remap[labels[valid]]
    return out, [colors[i] for i in order], [int(i) for i in order]


def majority_filter(labels: np.ndarray, n: int, radius: int) -> np.ndarray:
    """Filtro di maggioranza: ammorbidisce i bordi frastagliati tra i colori."""
    if radius <= 0 or n <= 1:
        return labels
    fg = labels >= 0
    size = 2 * radius + 1
    best = np.full(labels.shape, -1.0, np.float32)
    out = labels.copy()
    for i in range(n):
        score = cv2.blur((labels == i).astype(np.float32), (size, size))
        better = score > best
        out[better] = i
        best[better] = score[better]
    out[~fg] = -1
    return out


def absorb_small_regions(labels: np.ndarray, min_area_px: float, passes: int = 3) -> np.ndarray:
    """Le isole di colore troppo piccole per essere stampate prendono il colore
    della regione vicina più prossima."""
    fg = labels >= 0
    out = labels.copy()
    n = int(labels.max()) + 1 if fg.any() else 0
    for _ in range(passes):
        small = np.zeros(labels.shape, bool)
        for i in range(n):
            m = (out == i).astype(np.uint8)
            cnt, comp, stats, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
            if cnt <= 1:
                continue
            tiny = np.flatnonzero(stats[1:, cv2.CC_STAT_AREA] < min_area_px) + 1
            if len(tiny):
                small |= np.isin(comp, tiny)
        if not small.any():
            break
        keep = fg & ~small
        if not keep.any():
            break
        # Per ogni pixel "piccolo" trova il pixel valido più vicino.
        src = (~keep).astype(np.uint8)
        _, idx = cv2.distanceTransformWithLabels(src, cv2.DIST_L2, 5,
                                                 labelType=cv2.DIST_LABEL_PIXEL)
        ys, xs = np.nonzero(keep)
        lut = np.zeros(idx.max() + 1, np.int32)
        lut[idx[ys, xs]] = out[ys, xs]
        out[small] = lut[idx[small]]
    out[~fg] = -1
    return out
