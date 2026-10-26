"""Costruzione del modello 3D multicolore: una parte (mesh) per ogni colore."""

from __future__ import annotations

from dataclasses import dataclass, replace

import cv2
import numpy as np

from .imaging import hex_color, luminance
from .mesh import Mesh, extrude_polygons, heightfield_mesh
from .settings import RGB, ModelSettings, ProcessSettings
from .vectorize import mask_polygons


@dataclass
class Part:
    name: str
    rgb: RGB
    extruder: int
    mesh: Mesh


@dataclass
class HeightPreview:
    """Mappa di altezze e colori per l'anteprima 3D."""
    height: np.ndarray  # mm, NaN fuori dal soggetto
    rgb: np.ndarray  # colore della superficie
    cell_mm: float


def default_base_color(colors: list[RGB]) -> int:
    return int(np.argmin([luminance(c) for c in colors])) if colors else 0


def _base_index(colors: list[RGB], ms: ModelSettings) -> int:
    if 0 <= ms.base_color < len(colors):
        return ms.base_color
    return default_base_color(colors)


def build_relief(labels: np.ndarray, colors: list[RGB], px_mm: float,
                 ps: ProcessSettings, ms: ModelSettings) -> list[Part]:
    """Rilievo piatto: base sagomata + ogni colore estruso sopra la base."""
    h_mm = labels.shape[0] * px_mm
    parts: list[Part] = []
    base_idx = _base_index(colors, ms)
    z_base = max(ms.base_mm, 0.0)
    if z_base > 0:
        sil = mask_polygons(labels >= 0, px_mm, ps.curve_smooth, ps.simplify_mm, 0.5)
        mesh = extrude_polygons(sil, 0.0, z_base, h_mm)
        parts.append(Part("Base", colors[base_idx], ms.extruder_for(base_idx), mesh))
    for i, rgb in enumerate(colors):
        top = z_base + ms.layer_mm + ms.extra_for(i)
        if top <= z_base + 1e-6:
            continue
        # Livello 0.45: le parti si sovrappongono di un soffio, niente fessure.
        polys = mask_polygons(labels == i, px_mm, ps.curve_smooth, ps.simplify_mm, 0.45)
        mesh = extrude_polygons(polys, z_base, top, h_mm)
        if not mesh.is_empty:
            parts.append(Part(f"Colore {i + 1} {hex_color(rgb)}", rgb, ms.extruder_for(i), mesh))
    return parts


def _poisson(mask: np.ndarray, iters: int = 40) -> np.ndarray:
    """Risolve laplaciano(u) = -1 dentro la maschera (u = 0 fuori), dal grossolano al fine."""
    h, w = mask.shape
    if min(h, w) > 24:
        coarse = cv2.resize(mask.astype(np.uint8), ((w + 1) // 2, (h + 1) // 2),
                            interpolation=cv2.INTER_AREA) > 0
        u = cv2.resize(_poisson(coarse, iters) * 4.0, (w, h), interpolation=cv2.INTER_LINEAR)
    else:
        u = np.zeros((h, w), np.float32)
        iters = max(iters, 4 * max(h, w))
    u = np.where(mask, u, 0).astype(np.float32)
    up = np.pad(u, 1)
    inner = up[1:-1, 1:-1]  # vista: aggiornare ``inner`` aggiorna ``up``
    yy, xx = np.mgrid[0:h, 0:w]
    reds = mask & ((yy + xx) % 2 == 0)
    blacks = mask & ((yy + xx) % 2 == 1)
    omega = 1.85
    for _ in range(iters):
        for sel in (reds, blacks):
            nb = up[:-2, 1:-1] + up[2:, 1:-1] + up[1:-1, :-2] + up[1:-1, 2:]
            new = (nb + 1.0) / 4.0
            inner[sel] += omega * (new[sel] - inner[sel])
    return inner.copy()


def inflate(mask: np.ndarray) -> np.ndarray:
    """Profilo "gonfiato" 0..1: un disco diventa una semisfera, le parti sottili
    (braccia, orecchie) restano più basse e arrotondate, senza spigoli."""
    if not mask.any():
        return np.zeros(mask.shape, np.float32)
    u = np.sqrt(np.maximum(_poisson(mask), 0))
    return u / max(float(u.max()), 1e-6)


def remove_pinches(grid: np.ndarray, max_iter: int = 20) -> np.ndarray:
    """Elimina le celle che si toccano solo in diagonale (spigoli non-manifold):
    il blocco 2x2 viene completato con il colore della diagonale."""
    g = grid.copy()
    for _ in range(max_iter):
        a, b = g[:-1, :-1], g[:-1, 1:]
        c, d = g[1:, :-1], g[1:, 1:]
        main = (a == d) & (a >= 0) & (b != a) & (c != a)
        anti = (b == c) & (b >= 0) & (a != b) & (d != b)
        if not (main.any() or anti.any()):
            break
        ii, jj = np.nonzero(main)
        g[ii, jj + 1] = g[ii, jj]
        ii, jj = np.nonzero(anti & ~main)
        g[ii, jj] = g[ii, jj + 1]
    return g


def _inflated_grid(labels: np.ndarray, px_mm: float, ms: ModelSettings):
    """Ricampiona le etichette sulla griglia di stampa e calcola le quote."""
    cell = max(ms.resolution_mm, 0.05)
    h, w = labels.shape
    gw = max(2, round(w * px_mm / cell))
    gh = max(2, round(h * px_mm / cell))
    grid = cv2.resize(labels.astype(np.int16), (gw, gh), interpolation=cv2.INTER_NEAREST)
    grid = remove_pinches(grid)
    cell_x = w * px_mm / gw
    fg = grid >= 0

    dome = inflate(fg)
    lo, hi = ms.min_height_mm, max(ms.max_height_mm, ms.min_height_mm)
    extra = np.array([ms.extra_for(i) for i in range(int(grid.max()) + 1)] or [0.0])
    hc = lo + (hi - lo) * dome + np.where(fg, extra[np.maximum(grid, 0)], 0)
    hc = np.where(fg, np.maximum(hc, 0.2), np.nan)

    # Quota di ogni vertice = media delle celle del soggetto che lo toccano.
    p = np.pad(hc, 1, constant_values=np.nan)
    stack = np.stack([p[:-1, :-1], p[:-1, 1:], p[1:, :-1], p[1:, 1:]])
    valid = ~np.isnan(stack)
    vz = np.where(valid.any(0), np.nansum(stack, 0) / np.maximum(valid.sum(0), 1), 0)
    return grid, hc, vz, cell_x


def build_inflated(labels: np.ndarray, colors: list[RGB], px_mm: float,
                   ms: ModelSettings) -> list[Part]:
    """Pupazzetto 3D: superficie bombata, fondo piatto, una parte per colore."""
    grid, _, vz, cell = _inflated_grid(labels, px_mm, ms)
    parts = []
    for i, rgb in enumerate(colors):
        mesh = heightfield_mesh(grid == i, vz, cell)
        if not mesh.is_empty:
            parts.append(Part(f"Colore {i + 1} {hex_color(rgb)}", rgb, ms.extruder_for(i), mesh))
    return parts


def build_model(labels: np.ndarray, colors: list[RGB], px_mm: float,
                ps: ProcessSettings, ms: ModelSettings) -> list[Part]:
    if ms.mode == "gonfiato":
        return build_inflated(labels, colors, px_mm, ms)
    return build_relief(labels, colors, px_mm, ps, ms)


def height_preview(labels: np.ndarray, colors: list[RGB], px_mm: float,
                   ms: ModelSettings, max_cells: int = 420) -> HeightPreview:
    """Mappa di altezze semplificata per disegnare l'anteprima senza mesh."""
    h, w = labels.shape
    scale = min(1.0, max_cells / max(h, w))
    if scale < 1:
        labels = cv2.resize(labels.astype(np.int16), (max(2, round(w * scale)), max(2, round(h * scale))),
                            interpolation=cv2.INTER_NEAREST).astype(np.int32)
        px_mm = px_mm / scale
    palette = np.array(colors or [(128, 128, 128)], np.uint8)
    fg = labels >= 0
    rgb = palette[np.maximum(labels, 0)]
    if ms.mode == "gonfiato":
        pm = replace(ms, resolution_mm=px_mm)
        _, hc, _, _ = _inflated_grid(labels, px_mm, pm)
        height = hc
    else:
        extra = np.array([ms.extra_for(i) for i in range(len(colors))] or [0.0])
        height = np.where(fg, max(ms.base_mm, 0) + ms.layer_mm + extra[np.maximum(labels, 0)], np.nan)
        height = np.where(fg & (height <= max(ms.base_mm, 0)), max(ms.base_mm, 0.01), height)
        base_rgb = palette[_base_index(colors, ms)] if colors else palette[0]
        rgb = np.where((fg & (height <= max(ms.base_mm, 0) + 1e-6))[..., None], base_rgb, rgb)
    return HeightPreview(height.astype(np.float32), rgb, px_mm)
