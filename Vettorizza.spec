# -*- mode: python ; coding: utf-8 -*-
# Build:  pyinstaller --noconfirm Vettorizza.spec
from PyInstaller.utils.hooks import collect_all

datas = [("assets/icon.png", "assets"), ("assets/icon.ico", "assets")]
binaries = []
hiddenimports = []
for pkg in ("ezdxf", "onnxruntime", "mapbox_earcut"):
    d, b, h = collect_all(pkg)
    datas += d
    binaries += b
    hiddenimports += h

a = Analysis(
    ["run_vettorizza.py"],
    pathex=["."],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    excludes=["tkinter", "matplotlib", "scipy", "pandas", "IPython", "pytest",
              "trimesh", "networkx", "lxml", "cryptography"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Vettorizza",
    icon="assets/icon.ico",
    console=False,
    upx=False,
)
coll = COLLECT(exe, a.binaries, a.datas, name="Vettorizza", upx=False)
