"""Flusso completo: immagine -> soggetto -> colori -> vettoriale -> 3D -> file."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np

from . import colors as colormod
from .background import foreground_mask
from .imaging import resize_max
from .model3d import Part, build_model
from .settings import RGB, ModelSettings, ProcessSettings
from .vectorize import VectorResult, vectorize

Progress = Callable[[str, float], None]


@dataclass
class Analysis:
    rgb: np.ndarray  # immagine di lavoro ritagliata sul soggetto
    mask: np.ndarray  # soggetto
    labels: np.ndarray  # indice colore per pixel, -1 = sfondo
    colors: list[RGB]
    slots: list[int]  # slot filamento suggerito per ogni colore (1..)
    px_mm: float  # millimetri per pixel
    method: str  # metodo di rimozione dello sfondo usato
    vector: VectorResult

    @property
    def size_mm(self) -> tuple[float, float]:
        h, w = self.labels.shape
        return w * self.px_mm, h * self.px_mm

    def coverage(self) -> list[float]:
        fg = self.labels >= 0
        total = max(int(fg.sum()), 1)
        counts = np.bincount(self.labels[fg], minlength=len(self.colors))
        return [float(c) / total for c in counts]


def _crop_to_subject(rgba: np.ndarray, mask: np.ndarray, margin: int = 2):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        raise ValueError("Nessun soggetto trovato: prova un altro metodo di rimozione dello sfondo.")
    h, w = mask.shape
    y0, y1 = max(ys.min() - margin, 0), min(ys.max() + margin + 1, h)
    x0, x1 = max(xs.min() - margin, 0), min(xs.max() + margin + 1, w)
    return rgba[y0:y1, x0:x1], mask[y0:y1, x0:x1]


def analyze(rgba: np.ndarray, ps: ProcessSettings, progress: Progress | None = None) -> Analysis:
    report = progress or (lambda msg, frac: None)
    report("Preparazione immagine…", 0.02)
    work = resize_max(rgba, ps.max_work_px)

    report("Rimozione dello sfondo…", 0.10)
    mask, method = foreground_mask(work, ps)
    work, mask = _crop_to_subject(work, mask)
    rgb = np.ascontiguousarray(work[..., :3])
    px_mm = ps.width_mm / mask.shape[1]

    report("Analisi dei colori…", 0.40)
    flat = colormod.flatten_texture(rgb, ps.denoise)
    palette = ps.palette if (ps.use_palette and ps.palette) else None
    labels, colors, source = colormod.quantize(flat, mask, ps.n_colors, palette)

    report("Pulizia delle regioni…", 0.60)
    radius = max(1, round(0.25 / px_mm)) if ps.denoise > 0 else 0
    labels = colormod.majority_filter(labels, len(colors), radius)
    min_area_px = (ps.min_feature_mm / px_mm) ** 2 * np.pi / 4
    labels = colormod.absorb_small_regions(labels, max(min_area_px, 4))
    labels, colors, order = colormod.compact_labels(labels, colors)
    source = [source[i] for i in order]
    slots = [s + 1 for s in source] if palette else list(range(1, len(colors) + 1))

    report("Vettorizzazione…", 0.75)
    vec = vectorize(labels, colors, px_mm, ps.curve_smooth, ps.simplify_mm)
    report("Fatto", 1.0)
    return Analysis(rgb, mask, labels, colors, slots, px_mm, method, vec)


def _recompact(an: Analysis, ps: ProcessSettings) -> None:
    an.labels, an.colors, order = colormod.compact_labels(an.labels, an.colors)
    an.slots = [an.slots[i] for i in order]
    an.mask = an.labels >= 0
    an.vector = vectorize(an.labels, an.colors, an.px_mm, ps.curve_smooth, ps.simplify_mm)


def merge_colors(an: Analysis, ps: ProcessSettings, keep: int, others: list[int]) -> None:
    """Unisce i colori ``others`` nel colore ``keep``."""
    for o in others:
        if o != keep:
            an.labels[an.labels == o] = keep
    _recompact(an, ps)


def delete_color(an: Analysis, ps: ProcessSettings, idx: int) -> None:
    """Toglie un colore dal soggetto (diventa sfondo)."""
    an.labels[an.labels == idx] = -1
    _recompact(an, ps)


def set_color(an: Analysis, idx: int, rgb: RGB) -> None:
    an.colors[idx] = tuple(int(c) for c in rgb)
    an.vector.layers[idx].rgb = an.colors[idx]


def make_model(an: Analysis, ps: ProcessSettings, ms: ModelSettings) -> list[Part]:
    return build_model(an.labels, an.colors, an.px_mm, ps, ms)


def export_all(an: Analysis, parts: list[Part] | None, folder: str | Path, stem: str,
               ps: ProcessSettings, ms: ModelSettings, what: set[str] | None = None) -> list[Path]:
    """Esporta tutti i formati richiesti in ``folder``.

    ``what`` può contenere: svg, svg_colori, dxf, 3mf, obj, stl.
    """
    from .export_3d import export_3mf, export_obj, export_stl_parts
    from .export_vector import export_dxf, export_svg

    what = what or {"svg", "dxf", "3mf", "obj", "stl"}
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    out: list[Path] = []
    if "svg" in what or "svg_colori" in what:
        out += export_svg(an.vector, folder / f"{stem}.svg", per_color="svg_colori" in what)
    if "dxf" in what:
        out.append(export_dxf(an.vector, folder / f"{stem}.dxf"))
    if what & {"3mf", "obj", "stl"}:
        parts = parts if parts is not None else make_model(an, ps, ms)
        if "3mf" in what:
            out.append(export_3mf(parts, folder / f"{stem}.3mf", stem))
        if "obj" in what:
            out += export_obj(parts, folder / f"{stem}.obj")
        if "stl" in what:
            out += export_stl_parts(parts, folder / f"{stem}_stl", stem)
    return out
