"""Mesh triangolari chiuse (watertight) per la stampa 3D."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .vectorize import Polygon


@dataclass
class Mesh:
    vertices: np.ndarray  # (N, 3) float64, mm
    faces: np.ndarray  # (M, 3) int64, ordine antiorario visto dall'esterno

    @staticmethod
    def empty() -> "Mesh":
        return Mesh(np.zeros((0, 3)), np.zeros((0, 3), np.int64))

    @property
    def is_empty(self) -> bool:
        return len(self.faces) == 0

    @staticmethod
    def concat(meshes: list["Mesh"]) -> "Mesh":
        meshes = [m for m in meshes if not m.is_empty]
        if not meshes:
            return Mesh.empty()
        verts, faces, off = [], [], 0
        for m in meshes:
            verts.append(m.vertices)
            faces.append(m.faces + off)
            off += len(m.vertices)
        return Mesh(np.concatenate(verts), np.concatenate(faces))

    def volume(self) -> float:
        v = self.vertices[self.faces]
        return float(np.einsum("ij,ij->i", v[:, 0], np.cross(v[:, 1], v[:, 2])).sum() / 6)

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        return self.vertices.min(axis=0), self.vertices.max(axis=0)

    def is_watertight(self) -> bool:
        """Ogni spigolo orientato deve comparire una volta, e il suo opposto una volta."""
        f = self.faces
        e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
        n = len(self.vertices) + 1
        fwd = e[:, 0] * n + e[:, 1]
        rev = e[:, 1] * n + e[:, 0]
        if len(np.unique(fwd)) != len(fwd):
            return False
        return bool(np.isin(rev, fwd).all())


def _signed_area(pts: np.ndarray) -> float:
    x, y = pts[:, 0], pts[:, 1]
    return float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))) / 2


def _dedupe(ring: np.ndarray) -> np.ndarray:
    keep = np.any(np.abs(ring - np.roll(ring, -1, axis=0)) > 1e-9, axis=1)
    return ring[keep]


def extrude_polygon(poly: Polygon, z0: float, z1: float) -> Mesh:
    """Estrude un poligono con buchi (coordinate in mm, asse y verso l'alto)."""
    import mapbox_earcut as earcut

    outer, holes = poly
    rings = []
    for k, r in enumerate([outer, *holes]):
        r = _dedupe(np.asarray(r, np.float64))
        if len(r) < 3 or abs(_signed_area(r)) < 1e-9:
            if k == 0:
                return Mesh.empty()
            continue
        # Esterno antiorario, buchi orari: l'interno resta sempre a sinistra.
        if (_signed_area(r) > 0) != (k == 0):
            r = r[::-1]
        rings.append(r)

    flat = np.concatenate(rings)
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    tris = np.asarray(earcut.triangulate_float64(flat, ends), np.int64).reshape(-1, 3)
    if len(tris) == 0:
        return Mesh.empty()
    n = len(flat)
    bottom = np.column_stack([flat, np.full(n, z0)])
    top = np.column_stack([flat, np.full(n, z1)])
    verts = np.concatenate([bottom, top])

    # earcut non garantisce il verso: si orientano i triangoli verso l'alto.
    a, b, c = flat[tris[:, 0]], flat[tris[:, 1]], flat[tris[:, 2]]
    cross = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
    tris[cross < 0] = tris[cross < 0][:, [0, 2, 1]]

    faces = [tris + n, tris[:, [0, 2, 1]]]
    start = 0
    for r in rings:
        idx = np.arange(start, start + len(r))
        nxt = np.roll(idx, -1)
        faces.append(np.column_stack([idx, nxt, nxt + n]))
        faces.append(np.column_stack([idx, nxt + n, idx + n]))
        start += len(r)
    return Mesh(verts, np.concatenate(faces))


def extrude_polygons(polys: list[Polygon], z0: float, z1: float, height_mm: float) -> Mesh:
    """Estrude poligoni in coordinate immagine (y verso il basso, altezza ``height_mm``)."""
    meshes = []
    for outer, holes in polys:
        flip = lambda r: np.column_stack([r[:, 0], height_mm - r[:, 1]])  # noqa: E731
        meshes.append(extrude_polygon((flip(outer), [flip(h) for h in holes]), z0, z1))
    return Mesh.concat(meshes)


def heightfield_mesh(cells: np.ndarray, vz: np.ndarray, cell_mm: float) -> Mesh:
    """Solido chiuso: le celle ``cells`` (h, w) di una griglia con il fondo
    piatto a z=0 e la superficie superiore alle quote dei vertici ``vz`` (h+1, w+1).

    Le pareti laterali seguono i bordi delle celle, quindi due parti adiacenti
    combaciano perfettamente.
    """
    h, w = cells.shape
    if not cells.any():
        return Mesh.empty()
    W = w + 1
    nv = (h + 1) * W

    def vid(i, j):
        return i * W + j

    ci, cj = np.nonzero(cells)
    v00, v01 = vid(ci, cj), vid(ci, cj + 1)
    v10, v11 = vid(ci + 1, cj), vid(ci + 1, cj + 1)
    top = np.concatenate([np.column_stack([v00, v10, v11]), np.column_stack([v00, v11, v01])])
    faces = [top + nv, top[:, [0, 2, 1]]]  # superiore (+nv), inferiore

    padded = np.pad(cells, 1)
    walls = []
    # Bordi orizzontali: linea di griglia i tra la riga i-1 (sopra) e la riga i (sotto).
    above, below = padded[:-1, 1:-1], padded[1:, 1:-1]
    ii, jj = np.nonzero(above & ~below)
    walls.append((vid(ii, jj), vid(ii, jj + 1)))
    ii, jj = np.nonzero(below & ~above)
    walls.append((vid(ii, jj + 1), vid(ii, jj)))
    # Bordi verticali: linea j tra la colonna j-1 (sinistra) e la colonna j (destra).
    left, right = padded[1:-1, :-1], padded[1:-1, 1:]
    ii, jj = np.nonzero(left & ~right)
    walls.append((vid(ii + 1, jj), vid(ii, jj)))
    ii, jj = np.nonzero(right & ~left)
    walls.append((vid(ii, jj), vid(ii + 1, jj)))
    for a, b in walls:
        faces.append(np.column_stack([a, b, b + nv]))
        faces.append(np.column_stack([a, b + nv, a + nv]))
    faces = np.concatenate(faces)

    gi, gj = np.mgrid[0:h + 1, 0:w + 1]
    x = (gj * cell_mm).ravel().astype(np.float64)
    y = ((h - gi) * cell_mm).ravel().astype(np.float64)
    verts = np.concatenate([np.column_stack([x, y, np.zeros(nv)]),
                            np.column_stack([x, y, vz.ravel().astype(np.float64)])])

    used, inverse = np.unique(faces, return_inverse=True)
    return Mesh(verts[used], inverse.reshape(-1, 3).astype(np.int64))
