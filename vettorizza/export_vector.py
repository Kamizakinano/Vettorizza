"""Esportazione vettoriale: SVG (Fusion 360, Inkscape, Bambu Studio) e DXF (Fusion 360, CAD)."""

from __future__ import annotations

from pathlib import Path
from xml.sax.saxutils import escape

import numpy as np

from .imaging import hex_color
from .vectorize import Polygon, VectorLayer, VectorResult


def _ring_path(pts: np.ndarray) -> str:
    coords = " ".join(f"{x:.3f},{y:.3f}" for x, y in pts)
    return f"M{coords}Z"


def _poly_path(poly: Polygon) -> str:
    outer, holes = poly
    return " ".join([_ring_path(outer)] + [_ring_path(h) for h in holes])


def svg_document(vec: VectorResult, layers: list[tuple[str, VectorLayer]] | None = None,
                 outline: bool = False) -> str:
    """SVG in millimetri; ogni colore è un gruppo (livello) separato."""
    if layers is None:
        layers = [(f"Colore {i + 1} {hex_color(l.rgb)}", l) for i, l in enumerate(vec.layers)]
    w, h = vec.width_mm, vec.height_mm
    out = [
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" '
        f'width="{w:.3f}mm" height="{h:.3f}mm" viewBox="0 0 {w:.3f} {h:.3f}" version="1.1">',
        "<title>Vettorizza</title>",
    ]
    for i, (name, layer) in enumerate(layers):
        color = hex_color(layer.rgb)
        style = (f'fill="none" stroke="{color}" stroke-width="0.1"' if outline
                 else f'fill="{color}" fill-rule="evenodd" stroke="none"')
        out.append(f'<g id="colore_{i + 1}" inkscape:groupmode="layer" '
                   f'inkscape:label="{escape(name)}" {style}>')
        for poly in layer.polygons:
            out.append(f'<path d="{_poly_path(poly)}"/>')
        out.append("</g>")
    out.append("</svg>")
    return "\n".join(out)


def export_svg(vec: VectorResult, path: str | Path, per_color: bool = False) -> list[Path]:
    """Salva l'SVG completo; con ``per_color`` anche un file per ogni colore."""
    path = Path(path)
    path.write_text(svg_document(vec), encoding="utf-8")
    written = [path]
    if per_color:
        for i, layer in enumerate(vec.layers):
            p = path.with_name(f"{path.stem}_colore{i + 1}_{hex_color(layer.rgb)[1:]}.svg")
            p.write_text(svg_document(vec, [(f"Colore {i + 1}", layer)]), encoding="utf-8")
            written.append(p)
    return written


def export_dxf(vec: VectorResult, path: str | Path, include_silhouette: bool = True) -> Path:
    """DXF in millimetri con un layer per colore (asse y verso l'alto, come nei CAD)."""
    import ezdxf
    from ezdxf import colors as dxf_colors

    doc = ezdxf.new("R2010", setup=False)
    doc.units = ezdxf.units.MM
    doc.header["$MEASUREMENT"] = 1
    msp = doc.modelspace()
    h = vec.height_mm

    def add(layer_name: str, polys: list[Polygon]):
        for outer, holes in polys:
            for ring in [outer, *holes]:
                pts = [(float(x), float(h - y)) for x, y in ring]
                msp.add_lwpolyline(pts, close=True, dxfattribs={"layer": layer_name})

    if include_silhouette and vec.silhouette:
        layer = doc.layers.add("CONTORNO")
        layer.color = 7
        add("CONTORNO", vec.silhouette)
    for i, l in enumerate(vec.layers):
        name = f"COLORE_{i + 1}_{hex_color(l.rgb)[1:]}"
        layer = doc.layers.add(name)
        layer.true_color = dxf_colors.rgb2int(l.rgb)
        add(name, l.polygons)
    path = Path(path)
    doc.saveas(path)
    return path
