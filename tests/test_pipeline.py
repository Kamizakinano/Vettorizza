import zipfile
import xml.etree.ElementTree as ET

import numpy as np
import pytest

from vettorizza.export_3d import export_3mf, export_obj, write_stl
from vettorizza.mesh import Mesh, extrude_polygon, heightfield_mesh
from vettorizza.model3d import build_model, inflate, remove_pinches
from vettorizza.pipeline import analyze, delete_color, export_all, merge_colors
from vettorizza.settings import ModelSettings, ProcessSettings


@pytest.fixture
def analysis(toy_rgba):
    return analyze(toy_rgba, ProcessSettings(background="classico", n_colors=4))


def _close(rgb, ref, tol=40):
    return all(abs(a - b) <= tol for a, b in zip(rgb, ref))


def test_background_and_colors(analysis):
    an = analysis
    assert an.method == "classico"
    # Il soggetto è stato ritagliato: lo sfondo chiaro non è tra i colori.
    assert len(an.colors) == 4
    for ref in [(200, 30, 40), (245, 200, 30), (250, 250, 250), (20, 20, 20)]:
        assert any(_close(c, ref) for c in an.colors), ref
    # Larghezza impostata = larghezza del soggetto.
    assert an.size_mm[0] == pytest.approx(80.0)
    cov = an.coverage()
    assert sum(cov) == pytest.approx(1.0)
    assert cov == sorted(cov, reverse=True)


def test_transparent_png_uses_alpha(toy_rgba):
    rgba = toy_rgba.copy()
    bg = (np.abs(rgba[..., :3].astype(int) - (235, 238, 240)).sum(axis=2) < 40)
    rgba[bg, 3] = 0
    an = analyze(rgba, ProcessSettings(background="auto", n_colors=4))
    assert an.method == "trasparenza"
    assert len(an.colors) == 4


def test_palette_mapping(toy_rgba):
    palette = [(255, 255, 255), (0, 0, 0), (193, 46, 31), (244, 238, 42), (10, 41, 137)]
    an = analyze(toy_rgba, ProcessSettings(background="classico", n_colors=4,
                                           use_palette=True, palette=palette))
    assert set(an.colors) <= set(palette)
    assert (10, 41, 137) not in an.colors  # il blu non c'è nell'immagine
    # Lo slot AMS suggerito è la posizione del filamento nella palette.
    for rgb, slot in zip(an.colors, an.slots):
        assert palette[slot - 1] == rgb


def test_vector_layers(analysis):
    vec = analysis.vector
    assert len(vec.layers) == 4
    total = sum(l.area_mm2 for l in vec.layers)
    sil = sum(abs(np.dot(o[:, 0], np.roll(o[:, 1], -1)) - np.dot(o[:, 1], np.roll(o[:, 0], -1))) / 2
              for o, _ in vec.silhouette)
    assert total == pytest.approx(sil, rel=0.03)  # i colori tassellano la sagoma
    red = next(l for l in vec.layers if _close(l.rgb, (200, 30, 40)))
    assert any(len(holes) == 1 for _, holes in red.polygons)  # la pancia è un buco


@pytest.mark.parametrize("mode", ["rilievo", "gonfiato"])
def test_model_parts_are_watertight(analysis, mode):
    ms = ModelSettings(mode=mode, resolution_mm=0.5)
    parts = build_model(analysis.labels, analysis.colors, analysis.px_mm, ProcessSettings(), ms)
    assert len(parts) >= 4
    for p in parts:
        assert p.mesh.is_watertight(), p.name
        assert p.mesh.volume() > 0, p.name
    top = max(p.mesh.bounds()[1][2] for p in parts)
    expected = ms.base_mm + ms.layer_mm if mode == "rilievo" else ms.max_height_mm
    assert top == pytest.approx(expected, abs=0.3)


def test_extra_height_raises_one_color(analysis):
    ms = ModelSettings(mode="rilievo", extra_mm=[0, 0, 0, 2.0])
    parts = build_model(analysis.labels, analysis.colors, analysis.px_mm, ProcessSettings(), ms)
    eyes = parts[-1]
    assert eyes.mesh.bounds()[1][2] == pytest.approx(ms.base_mm + ms.layer_mm + 2.0)


def test_extrude_polygon_with_hole():
    sq = np.array([[0, 0], [10, 0], [10, 10], [0, 10]], float)
    hole = np.array([[3, 3], [3, 7], [7, 7], [7, 3]], float)
    m = extrude_polygon((sq, [hole]), 0, 2)
    assert m.is_watertight()
    assert m.volume() == pytest.approx((100 - 16) * 2)


def test_heightfield_mesh_volume():
    cells = np.zeros((6, 6), bool)
    cells[1:5, 1:5] = True
    cells[0, 0] = True  # tocca il resto solo in un angolo
    grid = remove_pinches(np.where(cells, 0, -1))
    assert grid.sum() > np.where(cells, 0, -1).sum()  # una cella aggiunta
    vz = np.full((7, 7), 3.0)
    m = heightfield_mesh(grid == 0, vz, 0.5)
    assert m.is_watertight()
    assert m.volume() == pytest.approx(18 * 0.25 * 3.0)


def test_remove_pinches_two_labels():
    rng = np.random.default_rng(3)
    grid = rng.integers(-1, 3, (40, 40))
    g = remove_pinches(grid)
    vz = np.ones((41, 41))
    for k in range(3):
        assert heightfield_mesh(g == k, vz, 1.0).is_watertight()


def test_inflate_is_hemisphere():
    import cv2
    m = np.zeros((161, 161), np.uint8)
    cv2.circle(m, (80, 80), 70, 1, -1)
    d = inflate(m > 0)
    r = np.array([0, 35, 60])
    assert d[80, 80 + r] == pytest.approx(np.sqrt(1 - (r / 70) ** 2), abs=0.03)


def test_merge_and_delete(analysis):
    ps = ProcessSettings(background="classico")
    merge_colors(analysis, ps, 0, [1])
    assert len(analysis.colors) == 3
    assert len(analysis.vector.layers) == 3
    delete_color(analysis, ps, 2)
    assert len(analysis.colors) == 2
    assert analysis.mask.sum() == (analysis.labels >= 0).sum()


def test_export_all(analysis, tmp_path):
    ps, ms = ProcessSettings(), ModelSettings(extruders=[3, 1, 2, 4])
    files = export_all(analysis, None, tmp_path, "toy", ps, ms,
                       {"svg", "svg_colori", "dxf", "3mf", "obj", "stl"})
    names = {f.name for f in files}
    assert {"toy.svg", "toy.dxf", "toy.3mf", "toy.obj", "toy.mtl"} <= names
    assert sum(n.endswith(".stl") for n in names) == 5  # base + 4 colori

    svg = ET.parse(tmp_path / "toy.svg").getroot()
    assert svg.get("width") == "80.000mm"
    assert len(svg.findall("{http://www.w3.org/2000/svg}g")) == 4

    import ezdxf
    doc = ezdxf.readfile(tmp_path / "toy.dxf")
    assert sum(l.dxf.name.startswith("COLORE_") for l in doc.layers) == 4

    with zipfile.ZipFile(tmp_path / "toy.3mf") as z:
        model = ET.fromstring(z.read("3D/3dmodel.model"))
        cfg = ET.fromstring(z.read("Metadata/model_settings.config"))
    ns = {"m": "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"}
    assert len(model.findall(".//m:base", ns)) == 5
    assert len(model.findall(".//m:component", ns)) == 5
    extruders = [p.find("metadata[@key='extruder']").get("value") for p in cfg.iter("part")]
    assert extruders[1:] == ["3", "1", "2", "4"]


def test_stl_roundtrip(tmp_path):
    sq = np.array([[0, 0], [4, 0], [4, 4], [0, 4]], float)
    m = extrude_polygon((sq, []), 0, 1)
    p = write_stl(m, tmp_path / "a.stl")
    data = p.read_bytes()
    assert int.from_bytes(data[80:84], "little") == len(m.faces)
    assert len(data) == 84 + 50 * len(m.faces)


def test_empty_mesh_export(tmp_path):
    from vettorizza.model3d import Part
    export_3mf([Part("vuoto", (0, 0, 0), 1, Mesh.empty())], tmp_path / "e.3mf")
    export_obj([], tmp_path / "e.obj")
