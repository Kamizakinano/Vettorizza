"""Esportazione 3D: 3MF multicolore (Bambu Studio), OBJ+MTL con colori, STL per colore."""

from __future__ import annotations

import re
import zipfile
from pathlib import Path
from xml.sax.saxutils import quoteattr

import numpy as np

from .imaging import hex_color
from .mesh import Mesh
from .model3d import Part


def _safe(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_") or "parte"


def _centered(parts: list[Part]) -> list[Part]:
    """Sposta il modello con il fondo a z=0 e centrato sull'origine in XY."""
    meshes = [p.mesh for p in parts if not p.mesh.is_empty]
    if not meshes:
        return parts
    allv = np.concatenate([m.vertices for m in meshes])
    lo, hi = allv.min(axis=0), allv.max(axis=0)
    off = np.array([-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]])
    return [Part(p.name, p.rgb, p.extruder, Mesh(p.mesh.vertices + off, p.mesh.faces))
            for p in parts]


# ---------------------------------------------------------------- STL

def write_stl(mesh: Mesh, path: str | Path, name: str = "Vettorizza") -> Path:
    v = mesh.vertices[mesh.faces].astype(np.float32)
    n = np.cross(v[:, 1] - v[:, 0], v[:, 2] - v[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    rec = np.zeros(len(v), dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    rec["n"], rec["v"] = n, v
    header = name.encode("ascii", "replace")[:80].ljust(80, b" ")
    path = Path(path)
    with open(path, "wb") as f:
        f.write(header)
        f.write(np.uint32(len(v)).tobytes())
        f.write(rec.tobytes())
    return path


def export_stl_parts(parts: list[Part], folder: str | Path, stem: str) -> list[Path]:
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    out = []
    for k, p in enumerate(_centered(parts), 1):
        fname = f"{stem}_{k:02d}_{_safe(p.name)}_AMS{p.extruder}.stl"
        out.append(write_stl(p.mesh, folder / fname, p.name))
    return out


# ---------------------------------------------------------------- OBJ

def export_obj(parts: list[Part], path: str | Path) -> list[Path]:
    """OBJ con materiali: Bambu Studio lo importa proponendo i colori dei filamenti."""
    path = Path(path)
    mtl = path.with_suffix(".mtl")
    lines = ["# Vettorizza", f"mtllib {mtl.name}"]
    mtl_lines = ["# Vettorizza"]
    offset = 1
    for k, p in enumerate(_centered(parts), 1):
        mat = f"colore_{k}_{hex_color(p.rgb)[1:]}"
        r, g, b = (c / 255 for c in p.rgb)
        mtl_lines += [f"newmtl {mat}", f"Kd {r:.4f} {g:.4f} {b:.4f}",
                      "Ka 0 0 0", "Ks 0 0 0", "d 1", "illum 1", ""]
        lines.append(f"o {_safe(p.name)}")
        lines.append(f"usemtl {mat}")
        lines.extend(f"v {x:.4f} {y:.4f} {z:.4f}" for x, y, z in p.mesh.vertices)
        f = p.mesh.faces + offset
        lines.extend(f"f {a} {b} {c}" for a, b, c in f)
        offset += len(p.mesh.vertices)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    mtl.write_text("\n".join(mtl_lines), encoding="utf-8")
    return [path, mtl]


# ---------------------------------------------------------------- 3MF

_CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
 <Default Extension="config" ContentType="text/xml"/>
</Types>"""

_RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>"""


def _mesh_xml(mesh: Mesh) -> str:
    verts = "".join(f'<vertex x="{x:.4f}" y="{y:.4f}" z="{z:.4f}"/>\n' for x, y, z in mesh.vertices)
    tris = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>\n' for a, b, c in mesh.faces)
    return f"<mesh>\n<vertices>\n{verts}</vertices>\n<triangles>\n{tris}</triangles>\n</mesh>"


def export_3mf(parts: list[Part], path: str | Path, name: str = "Vettorizza") -> Path:
    """3MF con un unico oggetto composto da una parte per colore.

    - ogni parte ha il suo colore (basematerials), visibile in qualsiasi programma;
    - ``Metadata/model_settings.config`` assegna a ogni parte lo slot del filamento
      (AMS) in Bambu Studio / Orca Slicer.
    """
    parts = [p for p in _centered(parts) if not p.mesh.is_empty]
    path = Path(path)
    mats = "".join(f'  <base name={quoteattr(p.name)} displaycolor="{hex_color(p.rgb)}FF"/>\n'
                   for p in parts)
    objects, comps, cfg_parts = [], [], []
    for k, p in enumerate(parts):
        oid = k + 2
        objects.append(f'<object id="{oid}" type="model" name={quoteattr(p.name)} '
                       f'pid="1" pindex="{k}">\n{_mesh_xml(p.mesh)}\n</object>')
        comps.append(f'<component objectid="{oid}"/>')
        cfg_parts.append(
            f'  <part id="{oid}" subtype="normal_part">\n'
            f'   <metadata key="name" value={quoteattr(p.name)}/>\n'
            f'   <metadata key="extruder" value="{p.extruder}"/>\n'
            f'  </part>')
    asm_id = len(parts) + 2
    model = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<model unit="millimeter" xml:lang="it-IT" '
        'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n'
        f' <metadata name="Title">{name}</metadata>\n'
        ' <metadata name="Application">Vettorizza</metadata>\n'
        ' <resources>\n'
        f' <basematerials id="1">\n{mats} </basematerials>\n'
        + "\n".join(objects) + "\n"
        f'<object id="{asm_id}" type="model" name={quoteattr(name)}>\n'
        f'<components>\n' + "\n".join(comps) + "\n</components>\n</object>\n"
        ' </resources>\n'
        f' <build>\n  <item objectid="{asm_id}" printable="1"/>\n </build>\n'
        '</model>\n'
    )
    first_extruder = parts[0].extruder if parts else 1
    config = (
        '<?xml version="1.0" encoding="UTF-8"?>\n<config>\n'
        f' <object id="{asm_id}">\n'
        f'  <metadata key="name" value={quoteattr(name)}/>\n'
        f'  <metadata key="extruder" value="{first_extruder}"/>\n'
        + "\n".join(cfg_parts) + "\n </object>\n</config>\n"
    )
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", _CONTENT_TYPES)
        z.writestr("_rels/.rels", _RELS)
        z.writestr("3D/3dmodel.model", model)
        z.writestr("Metadata/model_settings.config", config)
    return path
