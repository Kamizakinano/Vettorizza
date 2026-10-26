"""Uso da riga di comando: ``Vettorizza.exe cli immagine.png -o cartella``."""

from __future__ import annotations

import argparse
from pathlib import Path

from .imaging import load_rgba, parse_hex
from .pipeline import analyze, export_all
from .settings import BACKGROUND_MODES, MODEL_MODES, ModelSettings, ProcessSettings


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="vettorizza", description=(
        "Converte un'immagine in vettoriale (SVG/DXF) e in un modello 3D multicolore "
        "(3MF/OBJ/STL)."))
    p.add_argument("immagine")
    p.add_argument("-o", "--output", default=None, help="cartella di destinazione")
    p.add_argument("-n", "--colori", type=int, default=4, help="numero di colori")
    p.add_argument("--filamenti", default="",
                   help="colori dei filamenti in ordine di slot AMS, es. FFFFFF,000000,C12E1F")
    p.add_argument("--sfondo", choices=list(BACKGROUND_MODES), default="auto")
    p.add_argument("--larghezza", type=float, default=80.0, help="larghezza in mm")
    p.add_argument("--modo", choices=list(MODEL_MODES), default="rilievo")
    p.add_argument("--base", type=float, default=1.2, help="rilievo: spessore base (mm)")
    p.add_argument("--spessore", type=float, default=0.8, help="rilievo: spessore colori (mm)")
    p.add_argument("--altezza", type=float, default=12.0, help="gonfiato: altezza massima (mm)")
    p.add_argument("--formati", default="svg,dxf,3mf,obj,stl",
                   help="tra: svg, svg_colori, dxf, 3mf, obj, stl")
    a = p.parse_args(argv)

    src = Path(a.immagine)
    palette = [parse_hex(c) for c in a.filamenti.split(",") if c.strip()]
    ps = ProcessSettings(background=a.sfondo, n_colors=a.colori, width_mm=a.larghezza,
                         use_palette=bool(palette), palette=palette)
    ms = ModelSettings(mode=a.modo, base_mm=a.base, layer_mm=a.spessore,
                       max_height_mm=a.altezza)
    an = analyze(load_rgba(src), ps, lambda msg, f: print(f"[{f * 100:3.0f}%] {msg}"))
    ms.extruders = list(an.slots)
    out = Path(a.output) if a.output else src.with_name(src.stem + "_vettorizza")
    files = export_all(an, None, out, src.stem, ps, ms, set(a.formati.split(",")))
    w, h = an.size_mm
    print(f"Sfondo: {an.method} · {len(an.colors)} colori · {w:.1f} × {h:.1f} mm")
    for f in files:
        print("  ", f)
    return 0
