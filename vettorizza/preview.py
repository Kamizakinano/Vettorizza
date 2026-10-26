"""Immagini di anteprima: soggetto ritagliato, colori, vettoriale e vista 3D."""

from __future__ import annotations

import cv2
import numpy as np

from .imaging import checkerboard
from .model3d import HeightPreview
from .vectorize import VectorResult


def cutout(rgb: np.ndarray, mask: np.ndarray) -> np.ndarray:
    board = checkerboard(*mask.shape)
    return np.where(mask[..., None], rgb, board)


def labels_image(labels: np.ndarray, colors, highlight: int | None = None) -> np.ndarray:
    board = checkerboard(*labels.shape)
    if not colors:
        return board
    pal = np.array(colors, np.uint8)
    img = np.where((labels >= 0)[..., None], pal[np.maximum(labels, 0)], board)
    if highlight is not None and 0 <= highlight < len(colors):
        dim = (img * 0.25 + board * 0.35).astype(np.uint8)
        img = np.where((labels == highlight)[..., None], img, dim)
    return img


def vector_image(vec: VectorResult, max_side: int = 1400, outlines: bool = True) -> np.ndarray:
    s = max_side / max(vec.width_mm, vec.height_mm, 1e-6)
    w, h = max(1, round(vec.width_mm * s)), max(1, round(vec.height_mm * s))
    img = checkerboard(h, w)
    shift = 4
    k = s * (1 << shift)

    def rings(poly):
        outer, holes = poly
        return [np.round(r * k).astype(np.int32) for r in [outer, *holes]]

    for layer in vec.layers:
        for poly in layer.polygons:
            cv2.fillPoly(img, rings(poly), tuple(int(c) for c in layer.rgb),
                         lineType=cv2.LINE_AA, shift=shift)
    if outlines:
        for layer in vec.layers:
            for poly in layer.polygons:
                cv2.polylines(img, rings(poly), True, (30, 30, 30), 1,
                              lineType=cv2.LINE_AA, shift=shift)
    return img


def render_3d(hp: HeightPreview, azimuth: float = 0.0, elevation: float = 40.0,
              out_side: int = 900) -> np.ndarray:
    """Vista obliqua ombreggiata della mappa di altezze (senza OpenGL)."""
    height = hp.height
    fg = ~np.isnan(height)
    rgb = hp.rgb
    if not fg.any():
        return np.full((out_side, out_side, 3), 235, np.uint8)

    # Ruota la scena attorno al suo centro, su una tela abbastanza grande.
    h, w = height.shape
    diag = int(np.ceil(np.hypot(h, w))) + 4
    m = cv2.getRotationMatrix2D((w / 2, h / 2), azimuth, 1.0)
    m[0, 2] += (diag - w) / 2
    m[1, 2] += (diag - h) / 2
    hz = np.nan_to_num(height, nan=-1.0).astype(np.float32)
    hz = cv2.warpAffine(hz, m, (diag, diag), flags=cv2.INTER_NEAREST, borderValue=-1.0)
    col = cv2.warpAffine(rgb, m, (diag, diag), flags=cv2.INTER_NEAREST, borderValue=0)
    fg = hz >= 0
    ys, xs = np.nonzero(fg)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    hz, col, fg = hz[y0:y1, x0:x1], col[y0:y1, x0:x1], fg[y0:y1, x0:x1]
    hz = np.where(fg, hz, 0.0) / hp.cell_mm  # altezze in celle
    h, w = hz.shape

    # Normali e luce.
    gy, gx = np.gradient(hz)
    n = np.dstack([-gx, -gy, np.ones_like(hz)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    light = np.array([-0.45, 0.35, 0.82])
    light /= np.linalg.norm(light)
    shade = np.clip(0.38 + 0.62 * (n @ light), 0.25, 1.0)
    top_col = np.clip(col * shade[..., None] + 12, 0, 255)

    e = np.radians(np.clip(elevation, 10, 89))
    se, ce = np.sin(e), np.cos(e)

    # Pareti: solo dove il vicino è più basso.
    pad = np.pad(np.where(fg, hz, 0.0), 1)
    low = np.minimum.reduce([pad[:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, :-2], pad[1:-1, 2:]])
    dz = 0.7 / max(ce, 1e-3)
    pts_r, pts_c, pts_z, pts_rgb = [], [], [], []
    rr, cc = np.nonzero(fg)
    pts_r.append(rr); pts_c.append(cc); pts_z.append(hz[rr, cc]); pts_rgb.append(top_col[rr, cc])
    wall = fg & (hz - low > dz)
    if wall.any():
        wr, wc = np.nonzero(wall)
        top, bot = hz[wr, wc], low[wr, wc]
        steps = np.ceil((top - bot) / dz).astype(int)
        rep = np.repeat(np.arange(len(wr)), steps)
        k = np.arange(len(rep)) - np.repeat(np.cumsum(steps) - steps, steps)
        z = bot[rep] + k * dz
        side = col[wr, wc].astype(np.float32)[rep]
        fade = (0.42 + 0.25 * (z / max(hz.max(), 1e-6)))[:, None]
        pts_r.append(wr[rep]); pts_c.append(wc[rep]); pts_z.append(z); pts_rgb.append(side * fade)

    r = np.concatenate(pts_r).astype(np.float64)
    c = np.concatenate(pts_c)
    z = np.concatenate(pts_z)
    colors = np.concatenate(pts_rgb)
    sy = r * se - z * ce
    depth = r * ce + z * se
    sy -= sy.min()
    out_h = int(np.ceil(sy.max())) + 2
    iy = np.round(sy).astype(np.int64)
    flat = iy * w + c
    order = np.argsort(depth, kind="stable")[::-1]  # dal più vicino
    uniq, first = np.unique(flat[order], return_index=True)
    canvas = np.zeros((out_h * w, 3), np.float32)
    filled = np.zeros(out_h * w, bool)
    canvas[uniq] = colors[order[first]]
    filled[uniq] = True
    canvas = canvas.reshape(out_h, w, 3)
    filled = filled.reshape(out_h, w)

    # Chiude i piccoli buchi lasciati dalla proiezione.
    closed = cv2.dilate(canvas, np.ones((2, 2), np.uint8))
    canvas = np.where(filled[..., None], canvas, np.where(
        cv2.dilate(filled.astype(np.uint8), np.ones((2, 2), np.uint8))[..., None] > 0, closed, 0))
    filled = cv2.morphologyEx(filled.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((2, 2), np.uint8)) > 0

    # Sfondo sfumato + ombra morbida.
    margin = 0.08
    side = int(max(out_h, w) * (1 + 2 * margin))
    yy = np.linspace(0, 1, side)[:, None, None]
    bg = (238 - 30 * yy) * np.ones((side, side, 3))
    oy, ox = (side - out_h) // 2, (side - w) // 2
    shadow = np.zeros((side, side), np.float32)
    shadow[oy:oy + out_h, ox:ox + w] = filled
    shadow = cv2.GaussianBlur(np.roll(shadow, (int(side * 0.012), int(side * 0.01)), (0, 1)),
                              (0, 0), side * 0.012)
    bg *= (1 - 0.28 * shadow)[..., None]
    region = bg[oy:oy + out_h, ox:ox + w]
    bg[oy:oy + out_h, ox:ox + w] = np.where(filled[..., None], canvas, region)
    img = np.clip(bg, 0, 255).astype(np.uint8)
    return cv2.resize(img, (out_side, out_side), interpolation=cv2.INTER_AREA
                      if side > out_side else cv2.INTER_LINEAR)
