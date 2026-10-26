"""Rimozione dello sfondo con reti neurali (modelli ONNX di rembg, eseguiti in locale).

I modelli vengono scaricati una sola volta nella cartella dati dell'utente
(oppure possono essere copiati a mano nella cartella ``models`` accanto
all'eseguibile, per l'uso offline).
"""

from __future__ import annotations

import hashlib
import os
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image

_BASE_URL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/"


@dataclass(frozen=True)
class ModelInfo:
    name: str
    label: str
    md5: str
    size_mb: int
    input_size: int
    mean: tuple[float, float, float]
    std: tuple[float, float, float]

    @property
    def url(self) -> str:
        return _BASE_URL + self.name + ".onnx"


MODELS: dict[str, ModelInfo] = {
    m.name: m
    for m in (
        ModelInfo("isnet-general-use", "ISNet (qualità alta, consigliato)",
                  "fc16ebd8b0c10d971d3513d564d01e29", 171, 1024,
                  (0.5, 0.5, 0.5), (1.0, 1.0, 1.0)),
        ModelInfo("u2net", "U2Net (qualità buona)",
                  "60024c5c889badc19c04ad937298a77b", 168, 320,
                  (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)),
        ModelInfo("u2netp", "U2Net leggero (veloce, 5 MB)",
                  "8e83ca70e441ab06c318d82300c84806", 5, 320,
                  (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)),
    )
}

_sessions: dict[str, object] = {}


def onnx_available() -> bool:
    try:
        import onnxruntime  # noqa: F401
    except Exception:
        return False
    return True


def user_models_dir() -> Path:
    if sys.platform == "win32":
        root = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return root / "Vettorizza" / "models"
    root = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return root / "vettorizza" / "models"


def _candidate_paths(name: str) -> list[Path]:
    fname = name + ".onnx"
    exe_dir = Path(getattr(sys, "_MEIPASS", Path(sys.argv[0]).resolve().parent))
    return [
        user_models_dir() / fname,
        exe_dir / "models" / fname,
        Path(sys.executable).resolve().parent / "models" / fname,
        Path.home() / ".u2net" / fname,
    ]


def find_model(name: str) -> Path | None:
    for p in _candidate_paths(name):
        if p.is_file():
            return p
    return None


def is_available(name: str) -> bool:
    return onnx_available() and find_model(name) is not None


def download(name: str, progress: Callable[[float], None] | None = None) -> Path:
    """Scarica il modello e ne verifica l'integrità (MD5)."""
    info = MODELS[name]
    dest = user_models_dir() / (name + ".onnx")
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part")
    md5 = hashlib.md5()
    with urllib.request.urlopen(info.url, timeout=60) as resp, open(tmp, "wb") as out:
        total = int(resp.headers.get("Content-Length") or 0)
        done = 0
        while chunk := resp.read(1 << 20):
            out.write(chunk)
            md5.update(chunk)
            done += len(chunk)
            if progress and total:
                progress(done / total)
    if md5.hexdigest() != info.md5:
        tmp.unlink(missing_ok=True)
        raise IOError(f"Download del modello {name} corrotto, riprova.")
    tmp.replace(dest)
    return dest


def _session(name: str):
    if name not in _sessions:
        import onnxruntime as ort

        path = find_model(name)
        if path is None:
            raise FileNotFoundError(
                f"Modello AI '{name}' non trovato: scaricalo dal menu Strumenti.")
        opts = ort.SessionOptions()
        opts.log_severity_level = 3
        _sessions[name] = ort.InferenceSession(
            str(path), sess_options=opts, providers=["CPUExecutionProvider"])
    return _sessions[name]


def predict_alpha(rgb: np.ndarray, name: str) -> np.ndarray:
    """Restituisce la probabilità di primo piano (0..1) per ogni pixel."""
    info = MODELS[name]
    sess = _session(name)
    h, w = rgb.shape[:2]
    im = Image.fromarray(rgb).resize((info.input_size, info.input_size),
                                     Image.Resampling.LANCZOS)
    x = np.asarray(im, dtype=np.float32)
    x = x / max(float(x.max()), 1e-6)
    x = (x - np.array(info.mean, np.float32)) / np.array(info.std, np.float32)
    x = x.transpose(2, 0, 1)[None].astype(np.float32)
    out = sess.run(None, {sess.get_inputs()[0].name: x})[0][0, 0]
    lo, hi = float(out.min()), float(out.max())
    out = (out - lo) / max(hi - lo, 1e-6)
    pred = Image.fromarray((out * 255).astype(np.uint8)).resize(
        (w, h), Image.Resampling.LANCZOS)
    return np.asarray(pred, dtype=np.float32) / 255.0
