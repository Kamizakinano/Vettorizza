"""Impostazioni dell'elaborazione 2D e della generazione 3D."""

from __future__ import annotations

from dataclasses import dataclass, field

RGB = tuple[int, int, int]

BACKGROUND_MODES = {
    "auto": "Automatico",
    "ai": "Intelligenza artificiale",
    "classico": "Classico (colore del bordo)",
    "nessuno": "Nessuna rimozione",
}

MODEL_MODES = {
    "rilievo": "Rilievo a strati (piatto)",
    "gonfiato": "Pupazzetto 3D (gonfiato)",
}


@dataclass
class ProcessSettings:
    """Parametri che determinano sfondo, colori e contorni vettoriali."""

    background: str = "auto"
    bg_tolerance: float = 18.0  # distanza colore (Delta E) dal colore del bordo
    ai_model: str = "isnet-general-use"
    n_colors: int = 4
    use_palette: bool = False
    palette: list[RGB] = field(default_factory=list)  # colori dei filamenti
    denoise: int = 2  # 0..5: appiattisce texture e rumore prima dei colori
    min_feature_mm: float = 1.0  # dettagli più piccoli vengono assorbiti
    width_mm: float = 80.0  # larghezza finale dell'oggetto
    curve_smooth: float = 1.0  # morbidezza dei contorni (pixel)
    simplify_mm: float = 0.05  # tolleranza di semplificazione dei tracciati
    max_work_px: int = 1200  # lato massimo dell'immagine di lavoro


@dataclass
class ModelSettings:
    """Parametri della generazione 3D (non richiedono di rielaborare l'immagine)."""

    mode: str = "rilievo"
    base_mm: float = 1.2  # rilievo: spessore della base
    base_color: int = -1  # indice colore della base, -1 = più scuro
    layer_mm: float = 0.8  # rilievo: spessore dei colori sopra la base
    max_height_mm: float = 12.0  # gonfiato: altezza massima al centro
    min_height_mm: float = 1.2  # gonfiato: altezza sul bordo
    resolution_mm: float = 0.25  # gonfiato: passo della griglia
    extra_mm: list[float] = field(default_factory=list)  # altezza extra per colore
    extruders: list[int] = field(default_factory=list)  # slot AMS per colore (1..16)

    def extra_for(self, idx: int) -> float:
        return self.extra_mm[idx] if idx < len(self.extra_mm) else 0.0

    def extruder_for(self, idx: int) -> int:
        return self.extruders[idx] if idx < len(self.extruders) else idx + 1
