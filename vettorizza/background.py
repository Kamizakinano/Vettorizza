"""Separazione del soggetto dallo sfondo."""

from __future__ import annotations

import cv2
import numpy as np

from . import ai_models
from .imaging import rgb_to_lab
from .settings import ProcessSettings


def _has_transparency(rgba: np.ndarray) -> bool:
    alpha = rgba[..., 3]
    return bool((alpha < 128).mean() > 0.01)


def _border_pixels(arr: np.ndarray, strip: int) -> np.ndarray:
    return np.concatenate([
        arr[:strip].reshape(-1, arr.shape[-1]),
        arr[-strip:].reshape(-1, arr.shape[-1]),
        arr[:, :strip].reshape(-1, arr.shape[-1]),
        arr[:, -strip:].reshape(-1, arr.shape[-1]),
    ])


def _classic_mask(rgb: np.ndarray, tolerance: float) -> np.ndarray:
    """Sfondo = regioni collegate al bordo con colore simile a quello del bordo."""
    h, w = rgb.shape[:2]
    smooth = cv2.bilateralFilter(rgb, 7, 40, 7)
    lab = rgb_to_lab(smooth)
    strip = max(2, min(h, w) // 50)
    border = _border_pixels(lab, strip).astype(np.float32)

    # Lo sfondo può avere più tonalità (ombre, gradienti): fino a 3 colori.
    k = 3 if len(border) >= 30 else 1
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
    cv2.setRNGSeed(1)
    _, lbl, centers = cv2.kmeans(border, k, None, criteria, 3, cv2.KMEANS_PP_CENTERS)
    counts = np.bincount(lbl.ravel(), minlength=k)
    bg_colors = centers[counts >= 0.12 * len(border)]

    dist = np.full((h, w), np.inf, np.float32)
    for c in bg_colors:
        dist = np.minimum(dist, np.linalg.norm(lab - c, axis=2))
    similar = (dist < tolerance).astype(np.uint8)

    # Solo le zone simili che toccano il bordo sono sfondo (i buchi chiusi
    # vengono gestiti dopo da GrabCut).
    n, comp = cv2.connectedComponents(similar, connectivity=4)
    edge_ids = np.unique(np.concatenate([comp[0], comp[-1], comp[:, 0], comp[:, -1]]))
    edge_ids = edge_ids[edge_ids > 0]
    bg = np.isin(comp, edge_ids)
    fg = ~bg
    if fg.sum() < 0.002 * h * w:
        return fg

    # Rifinitura con GrabCut su un'immagine ridotta.
    scale = min(1.0, 640 / max(h, w))
    small = cv2.resize(rgb, (max(1, int(w * scale)), max(1, int(h * scale))),
                       interpolation=cv2.INTER_AREA)
    sh, sw = small.shape[:2]
    gc = np.full((sh, sw), cv2.GC_PR_BGD, np.uint8)
    fg_s = cv2.resize(fg.astype(np.uint8), (sw, sh), interpolation=cv2.INTER_NEAREST) > 0
    sure_bg = cv2.resize((bg & (dist < tolerance * 0.6)).astype(np.uint8), (sw, sh),
                         interpolation=cv2.INTER_NEAREST) > 0
    gc[fg_s] = cv2.GC_PR_FGD
    core = cv2.erode(fg_s.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    gc[core & (cv2.resize(dist, (sw, sh)) > tolerance * 2)] = cv2.GC_FGD
    gc[sure_bg] = cv2.GC_BGD
    try:
        bgd = np.zeros((1, 65), np.float64)
        fgd = np.zeros((1, 65), np.float64)
        cv2.grabCut(small, gc, None, bgd, fgd, 4, cv2.GC_INIT_WITH_MASK)
        refined = (gc == cv2.GC_FGD) | (gc == cv2.GC_PR_FGD)
        refined = cv2.resize(refined.astype(np.uint8), (w, h),
                             interpolation=cv2.INTER_NEAREST) > 0
        # Se GrabCut stravolge il risultato, meglio tenere la stima iniziale.
        ratio = refined.sum() / max(fg.sum(), 1)
        if 0.6 < ratio < 1.4:
            fg = refined
    except cv2.error:
        pass
    return fg


def clean_mask(mask: np.ndarray) -> np.ndarray:
    """Elimina briciole, piccoli buchi e frammenti staccati dal soggetto."""
    h, w = mask.shape
    m = mask.astype(np.uint8)
    k = max(1, round(min(h, w) / 300))
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1, 2 * k + 1))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, kernel)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, kernel)

    n, comp, stats, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    if n <= 1:
        return m > 0
    areas = stats[1:, cv2.CC_STAT_AREA]
    keep = np.flatnonzero(areas >= 0.03 * areas.max()) + 1
    m = np.isin(comp, keep)

    # Riempie i buchi minuscoli (riflessi, rumore) ma non quelli veri.
    inv = (~m).astype(np.uint8)
    n, comp, stats, _ = cv2.connectedComponentsWithStats(inv, connectivity=4)
    total = m.sum()
    for i in range(1, n):
        x, y, bw, bh, area = stats[i]
        touches = x == 0 or y == 0 or x + bw == w or y + bh == h
        if not touches and area < 0.004 * total:
            m[comp == i] = True
    return m


def foreground_mask(rgba: np.ndarray, settings: ProcessSettings) -> tuple[np.ndarray, str]:
    """Restituisce (maschera del soggetto, metodo usato)."""
    rgb = np.ascontiguousarray(rgba[..., :3])
    mode = settings.background
    h, w = rgb.shape[:2]

    if mode == "nessuno":
        if _has_transparency(rgba):
            return rgba[..., 3] >= 128, "trasparenza"
        return np.ones((h, w), bool), "nessuno"

    if mode == "auto":
        if _has_transparency(rgba):
            return clean_mask(rgba[..., 3] >= 128), "trasparenza"
        mode = "ai" if ai_models.is_available(settings.ai_model) else "classico"

    if mode == "ai":
        alpha = ai_models.predict_alpha(rgb, settings.ai_model)
        if _has_transparency(rgba):
            alpha = alpha * (rgba[..., 3] / 255.0)
        return clean_mask(alpha >= 0.5), "ai"

    mask = _classic_mask(rgb, settings.bg_tolerance)
    if _has_transparency(rgba):
        mask &= rgba[..., 3] >= 128
    mask = clean_mask(mask)
    return mask, "classico" if _looks_reliable(mask) else "classico-incerto"


def _looks_reliable(mask: np.ndarray) -> bool:
    """Un soggetto ben ritagliato è in pochi pezzi e non tocca i bordi della foto."""
    strip = max(2, min(mask.shape) // 50)
    on_border = float(_border_pixels(mask[..., None], strip).mean())
    pieces = cv2.connectedComponents(mask.astype(np.uint8))[0] - 1
    return on_border < 0.01 and pieces <= 3
