"""Genera la decorazione natalizia in SVG (solo tracciati, pronta per la stampa 3D)."""
import math, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

FONT = sys.argv[1] if len(sys.argv) > 1 else "Lobster-Regular.woff2"
NOME = sys.argv[2] if len(sys.argv) > 2 else "Valentina"
f = TTFont(FONT); gs = f.getGlyphSet(); cmap = f.getBestCmap(); upm = f["head"].unitsPerEm

def testo(s, cx, base, size, maxw=None):
    w = sum(gs[cmap[ord(c)]].width for c in s) * size / upm
    if maxw and w > maxw: size *= maxw / w; w = maxw
    k = size / upm; x = cx - w / 2; pen = SVGPathPen(gs); d = []
    for c in s:
        g = cmap[ord(c)]; p = SVGPathPen(gs)
        gs[g].draw(TransformPen(p, (k, 0, 0, -k, x, base))); d.append(p.getCommands())
        x += gs[g].width * k
    return " ".join(d)

def stella(cx, cy, r, n=5, ri=0.45, rot=-90):
    pts = []
    for i in range(2 * n):
        a = math.radians(rot + i * 180 / n); rr = r if i % 2 == 0 else r * ri
        pts.append(f"{cx + rr*math.cos(a):.2f},{cy + rr*math.sin(a):.2f}")
    return "M" + " L".join(pts) + "Z"

def scintilla(cx, cy, r):  # stellina a 4 punte
    return stella(cx, cy, r, 4, 0.3, -90)

def foglia(cx, cy, L, ang):
    """Foglia di agrifoglio: punte nette unite da rientranze curve verso la nervatura."""
    tips = [(0.22, 0.17), (0.42, 0.22), (0.62, 0.21), (0.81, 0.14)]
    pts = [(0, 0)] + [(x*L, y*L) for x, y in tips] + [(L, 0)] + [(x*L, -y*L) for x, y in reversed(tips)] + [(0, 0)]
    a = math.radians(ang); c, s = math.cos(a), math.sin(a)
    T = lambda x, y: f"{cx + x*c - y*s:.2f},{cy + x*s + y*c:.2f}"
    d = "M" + T(*pts[0])
    for p0, p1 in zip(pts, pts[1:]):
        estremo = p0[1] == 0 or p1[1] == 0  # tratto verso picciolo o punta: leggermente convesso
        k = 0.95 if estremo else 0.45
        d += " Q" + T((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 * k) + " " + T(*p1)
    return d + "Z"

def agrifoglio(cx, cy, s=1, flip=1):
    d = [foglia(cx, cy, 16*s, 150), foglia(cx, cy, 16*s, 30)]
    berries = [(cx - 2.6*s, cy - 0.6*s, 2.6*s), (cx + 2.6*s, cy - 0.6*s, 2.6*s), (cx, cy - 4.4*s, 2.6*s)]
    return d, berries

C = 100; out = []
ROSSO, BIANCO = "#c8323c", "#f2f2f2"
out.append(f'<circle cx="{C}" cy="{C}" r="98" fill="{BIANCO}"/>')
out.append(f'<circle cx="{C}" cy="{C}" r="93" fill="{ROSSO}"/>')
out.append(f'<circle cx="{C}" cy="{C}" r="88" fill="none" stroke="{BIANCO}" stroke-width="2"/>')
W = []  # forme bianche
W.append(f'<path d="{testo(NOME, C, 102, 40, 104)}"/>')
W.append(f'<path d="{testo("Merry Christmas", C, 128, 19, 120)}"/>')
for i, a in enumerate((-122, -106, -90, -74, -58)):
    r = 66; s = 8 if i == 2 else (6.5 if i in (1, 3) else 5.5)
    W.append(f'<path d="{stella(C + r*math.cos(math.radians(a)), C + r*math.sin(math.radians(a)), s)}"/>')
W.append(f'<rect x="{C-30}" y="138.5" width="60" height="2.6" rx="1.3"/><circle cx="{C}" cy="139.8" r="3.2"/>')
for a in range(40, 141, 14):  # puntini in basso
    W.append(f'<circle cx="{C + 76*math.cos(math.radians(a)):.2f}" cy="{C + 76*math.sin(math.radians(a)):.2f}" r="2.2"/>')
W.append(f'<circle cx="{C}" cy="21" r="2.4"/>')
# agrifogli: ai lati del nome e in basso
for (x, y, s, fl) in ((29, 88, 1.0, 1), (171, 88, 1.0, -1), (55, 150, 1.0, 1), (145, 150, 1.0, -1)):
    leaves, berries = agrifoglio(x, y, s, fl)
    for d in leaves: W.append(f'<path d="{d}"/>')
    for bx, by, br in berries: W.append(f'<circle cx="{bx:.2f}" cy="{by:.2f}" r="{br:.2f}" stroke="{ROSSO}" stroke-width="0.9"/>')
# riempitivi: stelline e puntini negli spazi vuoti
for (x, y, r) in ((40, 52, 5), (160, 52, 5), (28, 118, 4), (172, 118, 4), (100, 160, 4.5), (64, 172, 3.5), (136, 172, 3.5)):
    W.append(f'<path d="{scintilla(x, y, r)}"/>')
for (x, y) in ((54, 40), (146, 40), (36, 66), (164, 66), (24, 104), (176, 104), (76, 158), (124, 158)):
    W.append(f'<circle cx="{x}" cy="{y}" r="1.8"/>')
out.append(f'<g fill="{BIANCO}">' + "".join(W) + "</g>")
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="100mm" height="100mm">{"".join(out)}</svg>'
open(sys.argv[3] if len(sys.argv) > 3 else "decorazione.svg", "w").write(svg)
