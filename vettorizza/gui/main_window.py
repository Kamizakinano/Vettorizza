"""Finestra principale di Vettorizza."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import numpy as np
from PySide6.QtCore import QSettings, Qt, QTimer, QUrl
from PySide6.QtGui import QAction, QDesktopServices, QKeySequence
from PySide6.QtWidgets import (QAbstractItemView, QCheckBox, QComboBox, QDialog,
                               QDialogButtonBox, QDoubleSpinBox, QFileDialog,
                               QFormLayout, QGroupBox, QHBoxLayout, QHeaderView,
                               QLabel, QLineEdit, QMainWindow, QMessageBox,
                               QProgressBar, QProgressDialog, QPushButton,
                               QScrollArea, QSlider, QSpinBox, QSplitter,
                               QStackedWidget, QTableWidget, QTabWidget,
                               QVBoxLayout, QWidget)

from .. import __version__, ai_models, preview
from ..imaging import IMAGE_FILTER, hex_color, load_rgba, parse_hex
from ..model3d import default_base_color, height_preview
from ..pipeline import (Analysis, analyze, delete_color, export_all, merge_colors,
                        set_color)
from ..settings import BACKGROUND_MODES, MODEL_MODES, ModelSettings, ProcessSettings
from .widgets import FILAMENT_PRESETS, ColorButton, ImageView, PaletteEditor
from .workers import Worker

STYLE = """
QMainWindow, QWidget { font-size: 13px; }
QGroupBox { font-weight: 600; border: 1px solid #3c4043; border-radius: 6px;
            margin-top: 14px; padding: 10px 8px 8px 8px; }
QGroupBox::title { subcontrol-origin: margin; left: 10px; padding: 0 4px; }
QPushButton#primary { background: #1a73e8; color: white; font-weight: 600;
                      padding: 8px; border-radius: 6px; border: none; }
QPushButton#primary:hover { background: #2b7de9; }
QPushButton#primary:disabled { background: #5f6368; }
QLabel.hint { color: #888; }
"""

TAB_ORIGINAL, TAB_SUBJECT, TAB_COLORS, TAB_VECTOR, TAB_3D = range(5)


def _dspin(lo, hi, val, step=0.1, dec=2, suffix=" mm") -> QDoubleSpinBox:
    s = QDoubleSpinBox()
    s.setRange(lo, hi)
    s.setDecimals(dec)
    s.setSingleStep(step)
    s.setValue(val)
    s.setSuffix(suffix)
    return s


def _hint(text: str) -> QLabel:
    lab = QLabel(text)
    lab.setWordWrap(True)
    lab.setProperty("class", "hint")
    lab.setStyleSheet("color: #888; font-size: 11px;")
    return lab


def open_folder(path: Path):
    if sys.platform == "win32":
        os.startfile(str(path))  # noqa: S606 - apre Esplora risorse
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))


class ExportDialog(QDialog):
    FORMATS = [
        ("3mf", "3MF multicolore (Bambu Studio / Orca Slicer)", True),
        ("obj", "OBJ + MTL con colori (Bambu Studio, Fusion 360)", True),
        ("stl", "STL, un file per colore (qualsiasi slicer)", True),
        ("svg", "SVG vettoriale (Fusion 360: Inserisci > Inserisci SVG)", True),
        ("svg_colori", "SVG separato per ogni colore", False),
        ("dxf", "DXF con un layer per colore (Fusion 360, CAD)", True),
    ]

    def __init__(self, folder: str, stem: str, chosen: list[str] | None, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Esporta")
        self.setMinimumWidth(520)
        lay = QVBoxLayout(self)
        form = QFormLayout()
        row = QHBoxLayout()
        self.folder = QLineEdit(folder)
        browse = QPushButton("Sfoglia…")
        browse.clicked.connect(self._browse)
        row.addWidget(self.folder, 1)
        row.addWidget(browse)
        form.addRow("Cartella:", row)
        self.stem = QLineEdit(stem)
        form.addRow("Nome file:", self.stem)
        lay.addLayout(form)
        box = QGroupBox("Formati")
        bl = QVBoxLayout(box)
        self.checks: dict[str, QCheckBox] = {}
        for key, label, default in self.FORMATS:
            cb = QCheckBox(label)
            cb.setChecked(key in chosen if chosen is not None else default)
            bl.addWidget(cb)
            self.checks[key] = cb
        lay.addWidget(box)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok |
                                   QDialogButtonBox.StandardButton.Cancel)
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("Esporta")
        buttons.button(QDialogButtonBox.StandardButton.Cancel).setText("Annulla")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        lay.addWidget(buttons)

    def _browse(self):
        d = QFileDialog.getExistingDirectory(self, "Cartella di destinazione", self.folder.text())
        if d:
            self.folder.setText(d)

    def selection(self) -> set[str]:
        return {k for k, cb in self.checks.items() if cb.isChecked()}


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"Vettorizza {__version__} – da immagine a vettoriale e 3D")
        self.resize(1400, 900)
        self.setAcceptDrops(True)
        self.setStyleSheet(STYLE)
        self.qs = QSettings("Vettorizza", "Vettorizza")

        self.path: Path | None = None
        self.rgba: np.ndarray | None = None
        self.an: Analysis | None = None
        self.ms = ModelSettings()
        self.worker: Worker | None = None
        self._rerun = False
        self._selected_color: int | None = None

        self._process_timer = QTimer(self, singleShot=True, interval=700)
        self._process_timer.timeout.connect(self.process)
        self._preview_timer = QTimer(self, singleShot=True, interval=120)
        self._preview_timer.timeout.connect(self.update_3d_preview)

        self._build_menu()
        self._build_ui()
        self._load_prefs()
        self._update_ai_status()
        self._sync_mode_widgets()

    # ------------------------------------------------------------ interfaccia
    def _build_menu(self):
        m = self.menuBar().addMenu("&File")
        a = QAction("Apri immagine…", self, shortcut=QKeySequence.StandardKey.Open)
        a.triggered.connect(self.open_dialog)
        m.addAction(a)
        a = QAction("Esporta…", self, shortcut=QKeySequence("Ctrl+E"))
        a.triggered.connect(self.export_dialog)
        m.addAction(a)
        m.addSeparator()
        a = QAction("Esci", self, shortcut=QKeySequence.StandardKey.Quit)
        a.triggered.connect(self.close)
        m.addAction(a)
        t = self.menuBar().addMenu("&Strumenti")
        a = QAction("Scarica modello AI per lo sfondo…", self)
        a.triggered.connect(self.download_model)
        t.addAction(a)
        h = self.menuBar().addMenu("&Aiuto")
        a = QAction("Come stampare in multicolore", self)
        a.triggered.connect(self.show_help)
        h.addAction(a)

    def _build_ui(self):
        split = QSplitter(Qt.Orientation.Horizontal)
        self.setCentralWidget(split)

        panel = QWidget()
        pl = QVBoxLayout(panel)
        pl.setSpacing(6)

        # 1. Immagine
        g = QGroupBox("1 · Immagine")
        gl = QVBoxLayout(g)
        b = QPushButton("📂  Apri immagine…")
        b.clicked.connect(self.open_dialog)
        gl.addWidget(b)
        self.file_label = _hint("Oppure trascina un'immagine nella finestra.")
        gl.addWidget(self.file_label)
        pl.addWidget(g)

        # 2. Sfondo
        g = QGroupBox("2 · Rimozione sfondo")
        f = QFormLayout(g)
        self.bg_mode = QComboBox()
        for k, v in BACKGROUND_MODES.items():
            self.bg_mode.addItem(v, k)
        f.addRow("Metodo:", self.bg_mode)
        self.bg_tol = QSlider(Qt.Orientation.Horizontal)
        self.bg_tol.setRange(4, 60)
        self.bg_tol.setValue(18)
        f.addRow("Tolleranza:", self.bg_tol)
        self.ai_model = QComboBox()
        for k, info in ai_models.MODELS.items():
            self.ai_model.addItem(info.label, k)
        f.addRow("Modello AI:", self.ai_model)
        self.ai_status = _hint("")
        self.ai_download = QPushButton("Scarica modello AI")
        self.ai_download.clicked.connect(self.download_model)
        f.addRow(self.ai_status)
        f.addRow(self.ai_download)
        pl.addWidget(g)

        # 3. Colori
        g = QGroupBox("3 · Colori")
        f = QFormLayout(g)
        self.n_colors = QSpinBox()
        self.n_colors.setRange(1, 16)
        self.n_colors.setValue(4)
        f.addRow("Numero colori:", self.n_colors)
        self.use_palette = QCheckBox("Usa i colori dei miei filamenti")
        f.addRow(self.use_palette)
        self.palette = PaletteEditor()
        f.addRow(self.palette)
        self.preset = QComboBox()
        self.preset.addItem("Carica preset…")
        for name in FILAMENT_PRESETS:
            self.preset.addItem(name)
        self.preset.activated.connect(self._apply_preset)
        f.addRow(self.preset)
        self.denoise = QSlider(Qt.Orientation.Horizontal)
        self.denoise.setRange(0, 5)
        self.denoise.setValue(2)
        f.addRow("Pulizia texture:", self.denoise)
        self.min_feature = _dspin(0.0, 10.0, 1.0, 0.1, 1)
        self.min_feature.setToolTip("I dettagli più piccoli di questa misura vengono assorbiti "
                                    "dal colore vicino (consigliato ≥ 2 × diametro ugello).")
        f.addRow("Dettaglio minimo:", self.min_feature)
        pl.addWidget(g)

        # 4. Dimensioni
        g = QGroupBox("4 · Dimensioni e contorni")
        f = QFormLayout(g)
        self.width_mm = _dspin(5, 1000, 80, 1, 1)
        f.addRow("Larghezza:", self.width_mm)
        self.size_label = _hint("")
        f.addRow(self.size_label)
        self.smooth = QSlider(Qt.Orientation.Horizontal)
        self.smooth.setRange(0, 12)
        self.smooth.setValue(4)
        f.addRow("Morbidezza curve:", self.smooth)
        self.simplify = _dspin(0.0, 1.0, 0.05, 0.01, 2)
        f.addRow("Semplificazione:", self.simplify)
        pl.addWidget(g)

        self.process_btn = QPushButton("⚙  Elabora immagine")
        self.process_btn.setObjectName("primary")
        self.process_btn.clicked.connect(self.process)
        pl.addWidget(self.process_btn)

        # 5. Colori trovati
        g = QGroupBox("5 · Colori trovati")
        gl = QVBoxLayout(g)
        self.table = QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(["Colore", "Area", "Slot AMS", "Extra"])
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        hh = self.table.horizontalHeader()
        hh.setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.setMinimumHeight(150)
        self.table.itemSelectionChanged.connect(self._table_selection)
        gl.addWidget(self.table)
        row = QHBoxLayout()
        b = QPushButton("Unisci selezionati")
        b.setToolTip("Seleziona due o più righe (Ctrl+clic) per unirle nel primo colore.")
        b.clicked.connect(self.merge_selected)
        row.addWidget(b)
        b = QPushButton("Elimina (sfondo)")
        b.setToolTip("Il colore selezionato viene tolto dal soggetto.")
        b.clicked.connect(self.delete_selected)
        row.addWidget(b)
        gl.addLayout(row)
        gl.addWidget(_hint("Clic sul colore per cambiarlo. Clic sull'immagine «Colori» per "
                           "trovare una regione. «Extra» alza quel colore (es. occhi in rilievo)."))
        pl.addWidget(g)

        # 6. Modello 3D
        g = QGroupBox("6 · Modello 3D")
        gl = QVBoxLayout(g)
        f = QFormLayout()
        self.mode = QComboBox()
        for k, v in MODEL_MODES.items():
            self.mode.addItem(v, k)
        f.addRow("Tipo:", self.mode)
        gl.addLayout(f)
        self.mode_stack = QStackedWidget()
        w = QWidget()
        f = QFormLayout(w)
        f.setContentsMargins(0, 0, 0, 0)
        self.base_mm = _dspin(0, 20, self.ms.base_mm, 0.2)
        f.addRow("Spessore base:", self.base_mm)
        self.base_color = QComboBox()
        f.addRow("Colore base:", self.base_color)
        self.layer_mm = _dspin(0.0, 20, self.ms.layer_mm, 0.2)
        f.addRow("Spessore colori:", self.layer_mm)
        self.mode_stack.addWidget(w)
        w = QWidget()
        f = QFormLayout(w)
        f.setContentsMargins(0, 0, 0, 0)
        self.max_h = _dspin(1, 200, self.ms.max_height_mm, 0.5)
        f.addRow("Altezza al centro:", self.max_h)
        self.min_h = _dspin(0.4, 50, self.ms.min_height_mm, 0.2)
        f.addRow("Altezza sul bordo:", self.min_h)
        self.res_mm = _dspin(0.1, 2.0, self.ms.resolution_mm, 0.05)
        self.res_mm.setToolTip("Passo della griglia: più piccolo = più dettagli, file più pesanti.")
        f.addRow("Risoluzione:", self.res_mm)
        self.mode_stack.addWidget(w)
        gl.addWidget(self.mode_stack)
        pl.addWidget(g)

        self.export_btn = QPushButton("💾  Esporta (3MF, OBJ, STL, SVG, DXF)…")
        self.export_btn.setObjectName("primary")
        self.export_btn.clicked.connect(self.export_dialog)
        pl.addWidget(self.export_btn)
        pl.addStretch(1)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(panel)
        scroll.setMinimumWidth(370)
        split.addWidget(scroll)

        # Viste
        self.tabs = QTabWidget()
        self.view_orig = ImageView("Apri o trascina qui un'immagine")
        self.view_subject = ImageView()
        self.view_colors = ImageView()
        self.view_colors.clicked.connect(self._pick_region)
        self.view_vector = ImageView()
        self.view_3d = ImageView()
        self.tabs.addTab(self.view_orig, "Originale")
        self.tabs.addTab(self.view_subject, "Soggetto")
        self.tabs.addTab(self.view_colors, "Colori")
        self.tabs.addTab(self.view_vector, "Vettoriale")
        w3 = QWidget()
        l3 = QVBoxLayout(w3)
        l3.setContentsMargins(0, 0, 0, 0)
        l3.addWidget(self.view_3d, 1)
        ctl = QHBoxLayout()
        ctl.setContentsMargins(8, 4, 8, 4)
        self.azimuth = QSlider(Qt.Orientation.Horizontal)
        self.azimuth.setRange(-180, 180)
        self.azimuth.setValue(-20)
        self.elev = QSlider(Qt.Orientation.Horizontal)
        self.elev.setRange(15, 89)
        self.elev.setValue(50)
        ctl.addWidget(QLabel("Rotazione"))
        ctl.addWidget(self.azimuth, 2)
        ctl.addWidget(QLabel("Inclinazione"))
        ctl.addWidget(self.elev, 1)
        l3.addLayout(ctl)
        self.model_info = _hint("")
        self.model_info.setContentsMargins(8, 0, 8, 6)
        l3.addWidget(self.model_info)
        self.tabs.addTab(w3, "Anteprima 3D")
        self.tabs.currentChanged.connect(lambda i: i == TAB_3D and self.update_3d_preview())
        split.addWidget(self.tabs)
        split.setStretchFactor(1, 1)
        split.setSizes([390, 1000])

        self.status = QLabel("Pronto.")
        self.progress = QProgressBar()
        self.progress.setMaximumWidth(260)
        self.progress.setRange(0, 100)
        self.progress.hide()
        self.statusBar().addWidget(self.status, 1)
        self.statusBar().addPermanentWidget(self.progress)

        # Collegamenti: le impostazioni 2D rielaborano, quelle 3D aggiornano l'anteprima.
        for w in (self.bg_mode, self.ai_model):
            w.currentIndexChanged.connect(self._process_settings_changed)
        for w in (self.bg_tol, self.denoise, self.smooth):
            w.valueChanged.connect(self._process_settings_changed)
        for w in (self.n_colors, self.min_feature, self.width_mm, self.simplify):
            w.valueChanged.connect(self._process_settings_changed)
        self.use_palette.toggled.connect(self._process_settings_changed)
        self.palette.changed.connect(self._palette_changed)
        self.mode.currentIndexChanged.connect(self._model_settings_changed)
        self.base_color.currentIndexChanged.connect(self._model_settings_changed)
        for w in (self.base_mm, self.layer_mm, self.max_h, self.min_h, self.res_mm):
            w.valueChanged.connect(self._model_settings_changed)
        self.azimuth.valueChanged.connect(lambda _: self._preview_timer.start())
        self.elev.valueChanged.connect(lambda _: self._preview_timer.start())
        self.bg_mode.currentIndexChanged.connect(self._update_ai_status)
        self.ai_model.currentIndexChanged.connect(self._update_ai_status)

    # ------------------------------------------------------------ preferenze
    def _load_prefs(self):
        qs = self.qs
        pal = qs.value("palette", None)
        colors = []
        if isinstance(pal, str):
            pal = [p for p in pal.split(",") if p]
        if isinstance(pal, list):
            for p in pal:
                try:
                    colors.append(parse_hex(p))
                except ValueError:
                    pass
        self.palette.set_palette(colors or [parse_hex(h) for h in
                                            FILAMENT_PRESETS["AMS base: bianco, nero, rosso, giallo"]])
        widgets = [self.bg_mode, self.ai_model, self.n_colors, self.use_palette, self.width_mm,
                   self.mode, self.denoise, self.min_feature]
        for w in widgets:
            w.blockSignals(True)
        try:
            self.n_colors.setValue(int(qs.value("n_colors", 4)))
            self.width_mm.setValue(float(qs.value("width_mm", 80)))
            self.use_palette.setChecked(qs.value("use_palette", "false") in (True, "true"))
            idx = self.bg_mode.findData(qs.value("bg_mode", "auto"))
            self.bg_mode.setCurrentIndex(max(idx, 0))
            idx = self.ai_model.findData(qs.value("ai_model", "isnet-general-use"))
            self.ai_model.setCurrentIndex(max(idx, 0))
            idx = self.mode.findData(qs.value("mode", "rilievo"))
            self.mode.setCurrentIndex(max(idx, 0))
        finally:
            for w in widgets:
                w.blockSignals(False)

    def _save_prefs(self):
        qs = self.qs
        qs.setValue("palette", ",".join(hex_color(c) for c in self.palette.palette()))
        qs.setValue("n_colors", self.n_colors.value())
        qs.setValue("width_mm", self.width_mm.value())
        qs.setValue("use_palette", self.use_palette.isChecked())
        qs.setValue("bg_mode", self.bg_mode.currentData())
        qs.setValue("ai_model", self.ai_model.currentData())
        qs.setValue("mode", self.mode.currentData())

    def closeEvent(self, event):
        self._save_prefs()
        if self.worker and self.worker.isRunning():
            self.worker.wait(5000)
        super().closeEvent(event)

    # ------------------------------------------------------------ impostazioni
    def process_settings(self) -> ProcessSettings:
        return ProcessSettings(
            background=self.bg_mode.currentData(),
            bg_tolerance=float(self.bg_tol.value()),
            ai_model=self.ai_model.currentData(),
            n_colors=self.n_colors.value(),
            use_palette=self.use_palette.isChecked(),
            palette=self.palette.palette(),
            denoise=self.denoise.value(),
            min_feature_mm=self.min_feature.value(),
            width_mm=self.width_mm.value(),
            curve_smooth=self.smooth.value() / 4.0,
            simplify_mm=self.simplify.value(),
        )

    def model_settings(self) -> ModelSettings:
        ms = self.ms
        ms.mode = self.mode.currentData()
        ms.base_mm = self.base_mm.value()
        ms.base_color = self.base_color.currentIndex()
        ms.layer_mm = self.layer_mm.value()
        ms.max_height_mm = self.max_h.value()
        ms.min_height_mm = self.min_h.value()
        ms.resolution_mm = self.res_mm.value()
        return ms

    def _process_settings_changed(self, *_):
        if self.rgba is not None:
            self._process_timer.start()

    def _palette_changed(self):
        if self.use_palette.isChecked():
            self._process_settings_changed()

    def _model_settings_changed(self, *_):
        self._sync_mode_widgets()
        self._preview_timer.start()

    def _sync_mode_widgets(self):
        self.mode_stack.setCurrentIndex(0 if self.mode.currentData() == "rilievo" else 1)

    def _apply_preset(self, index: int):
        if index <= 0:
            return
        name = self.preset.itemText(index)
        self.palette.set_palette([parse_hex(h) for h in FILAMENT_PRESETS[name]])
        self.preset.setCurrentIndex(0)

    def _update_ai_status(self, *_):
        name = self.ai_model.currentData()
        if not ai_models.onnx_available():
            self.ai_status.setText("Motore AI non disponibile in questa installazione.")
            self.ai_download.setEnabled(False)
        elif ai_models.is_available(name):
            self.ai_status.setText("✔ Modello AI pronto (funziona offline).")
            self.ai_download.setEnabled(False)
        else:
            size = ai_models.MODELS[name].size_mb
            self.ai_status.setText(f"Modello AI non ancora scaricato ({size} MB). "
                                   "In automatico viene usato il metodo classico.")
            self.ai_download.setEnabled(True)
        self.bg_tol.setEnabled(self.bg_mode.currentData() in ("classico", "auto"))

    # ------------------------------------------------------------ apertura
    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event):
        urls = [u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile()]
        if urls:
            self.open_image(urls[0])

    def open_dialog(self):
        start = self.qs.value("last_open_dir", str(Path.home()))
        path, _ = QFileDialog.getOpenFileName(self, "Apri immagine", start, IMAGE_FILTER)
        if path:
            self.open_image(path)

    def open_image(self, path: str):
        try:
            rgba = load_rgba(path)
        except Exception as exc:
            QMessageBox.critical(self, "Errore", f"Impossibile aprire l'immagine:\n{exc}")
            return
        self.path = Path(path)
        self.qs.setValue("last_open_dir", str(self.path.parent))
        self.rgba = rgba
        self.an = None
        self.file_label.setText(f"{self.path.name} — {rgba.shape[1]}×{rgba.shape[0]} px")
        self.view_orig.set_image(rgba)
        for v in (self.view_subject, self.view_colors, self.view_vector, self.view_3d):
            v.set_image(None)
        self.tabs.setCurrentIndex(TAB_ORIGINAL)
        if self._offer_ai_model():
            return  # l'elaborazione parte a download completato
        self.process()

    def _offer_ai_model(self) -> bool:
        """Al primo utilizzo propone di scaricare il modello AI per lo sfondo."""
        name = self.ai_model.currentData()
        if (self.bg_mode.currentData() not in ("auto", "ai") or not ai_models.onnx_available()
                or ai_models.is_available(name) or self.qs.value("ai_offered", "false") == "true"):
            return False
        self.qs.setValue("ai_offered", "true")
        return self.download_model()

    # ------------------------------------------------------------ elaborazione
    def _busy(self, text: str):
        self.status.setText(text)
        self.progress.setValue(0)
        self.progress.show()

    def _idle(self, text: str):
        self.status.setText(text)
        self.progress.hide()

    def process(self):
        if self.rgba is None:
            return
        if self.worker and self.worker.isRunning():
            self._rerun = True
            return
        ps = self.process_settings()
        rgba = self.rgba
        self._busy("Elaborazione…")
        self.process_btn.setEnabled(False)
        self.worker = Worker(lambda progress: analyze(rgba, ps, progress), self)
        self.worker.progress.connect(self._on_progress)
        self.worker.done.connect(self._on_analysis)
        self.worker.failed.connect(self._on_failed)
        self.worker.finished.connect(self._worker_finished)
        self.worker.start()

    def _on_progress(self, msg: str, frac: float):
        self.status.setText(msg)
        self.progress.setValue(int(frac * 100))

    def _worker_finished(self):
        self.process_btn.setEnabled(True)
        if self._rerun:
            self._rerun = False
            self.process()

    def _on_failed(self, msg: str):
        self._idle("Errore.")
        QMessageBox.critical(self, "Errore", msg)

    def _on_analysis(self, an: Analysis):
        first = self.an is None
        self.an = an
        methods = {"ai": "AI", "classico": "classico", "classico-incerto": "classico",
                   "trasparenza": "trasparenza PNG", "nessuno": "nessuna rimozione"}
        self._idle(f"Fatto: {len(an.colors)} colori · sfondo: {methods.get(an.method, an.method)}")
        if an.method == "classico-incerto":
            tip = ("scegli il metodo «Intelligenza artificiale»"
                   if ai_models.is_available(self.ai_model.currentData())
                   else "scarica il modello AI (menu Strumenti)")
            self.status.setText(self.status.text() + f"  ⚠ Sfondo complesso: per un ritaglio "
                                f"migliore {tip}.")
        self._fill_color_table()
        self.refresh_views()
        if first and self.tabs.currentIndex() == TAB_ORIGINAL:
            self.tabs.setCurrentIndex(TAB_COLORS)

    def refresh_views(self):
        an = self.an
        if an is None:
            return
        w, h = an.size_mm
        self.size_label.setText(f"Dimensione finale: {w:.1f} × {h:.1f} mm")
        self.view_subject.set_image(preview.cutout(an.rgb, an.mask), keep_view=True)
        self.view_colors.set_image(preview.labels_image(an.labels, an.colors, self._selected_color),
                                   keep_view=True)
        self.view_vector.set_image(preview.vector_image(an.vector), keep_view=True)
        self.update_3d_preview()

    def update_3d_preview(self):
        if self.an is None or self.tabs.currentIndex() != TAB_3D:
            return
        an = self.an
        ms = self.model_settings()
        hp = height_preview(an.labels, an.colors, an.px_mm, ms)
        img = preview.render_3d(hp, self.azimuth.value(), self.elev.value())
        self.view_3d.set_image(img, keep_view=True)
        top = np.nanmax(hp.height)
        w, h = an.size_mm
        self.model_info.setText(f"Ingombro: {w:.1f} × {h:.1f} × {top:.1f} mm · "
                                f"{len(an.colors)} colori · {MODEL_MODES[ms.mode]}")

    # ------------------------------------------------------------ tabella colori
    def _fill_color_table(self):
        an = self.an
        cov = an.coverage()
        n = len(an.colors)
        # Mantiene le impostazioni per colore se il numero di colori non cambia.
        if len(self.ms.extruders) != n:
            self.ms.extruders = list(an.slots)
            self.ms.extra_mm = [0.0] * n
        self.table.blockSignals(True)
        self.table.setRowCount(n)
        for i, rgb in enumerate(an.colors):
            btn = ColorButton(rgb, 22)
            btn.colorChanged.connect(lambda c, i=i: self._recolor(i, c))
            holder = QWidget()
            hl = QHBoxLayout(holder)
            hl.setContentsMargins(4, 0, 4, 0)
            hl.addWidget(btn)
            hl.addWidget(QLabel(hex_color(rgb)))
            self.table.setCellWidget(i, 0, holder)
            lab = QLabel(f"{cov[i] * 100:.1f}%")
            lab.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self.table.setCellWidget(i, 1, lab)
            slot = QSpinBox()
            slot.setRange(1, 16)
            slot.setValue(self.ms.extruders[i])
            slot.valueChanged.connect(lambda v, i=i: self._set_slot(i, v))
            self.table.setCellWidget(i, 2, slot)
            extra = _dspin(-10, 50, self.ms.extra_mm[i], 0.2, 1)
            extra.valueChanged.connect(lambda v, i=i: self._set_extra(i, v))
            self.table.setCellWidget(i, 3, extra)
        self.table.blockSignals(False)
        self.table.resizeRowsToContents()

        self.base_color.blockSignals(True)
        prev = self.base_color.currentIndex()
        self.base_color.clear()
        for i, rgb in enumerate(an.colors):
            self.base_color.addItem(f"Colore {i + 1} {hex_color(rgb)}")
        self.base_color.setCurrentIndex(prev if 0 <= prev < n and self.base_color.count() == n
                                        else default_base_color(an.colors))
        self.base_color.blockSignals(False)

    def _set_slot(self, i: int, v: int):
        self.ms.extruders[i] = v

    def _set_extra(self, i: int, v: float):
        self.ms.extra_mm[i] = v
        self._preview_timer.start()

    def _recolor(self, i: int, rgb):
        set_color(self.an, i, rgb)
        self._fill_color_table()
        self.refresh_views()

    def _selected_rows(self) -> list[int]:
        return sorted({ix.row() for ix in self.table.selectionModel().selectedRows()})

    def _table_selection(self):
        rows = self._selected_rows()
        self._selected_color = rows[0] if len(rows) == 1 else None
        if self.an is not None:
            self.view_colors.set_image(
                preview.labels_image(self.an.labels, self.an.colors, self._selected_color),
                keep_view=True)

    def _pick_region(self, x: int, y: int):
        an = self.an
        if an is None or not (0 <= y < an.labels.shape[0] and 0 <= x < an.labels.shape[1]):
            return
        idx = int(an.labels[y, x])
        if idx < 0:
            self.table.clearSelection()
        else:
            self.table.selectRow(idx)

    def _after_edit(self):
        self.ms.extruders = list(self.an.slots)
        self.ms.extra_mm = [0.0] * len(self.an.colors)
        self._selected_color = None
        self._fill_color_table()
        self.refresh_views()

    def merge_selected(self):
        rows = self._selected_rows()
        if self.an is None or len(rows) < 2:
            QMessageBox.information(self, "Unisci colori",
                                    "Seleziona almeno due colori (Ctrl+clic sulle righe).")
            return
        merge_colors(self.an, self.process_settings(), rows[0], rows[1:])
        self._after_edit()

    def delete_selected(self):
        rows = self._selected_rows()
        if self.an is None or len(rows) != 1:
            QMessageBox.information(self, "Elimina colore", "Seleziona un colore.")
            return
        if len(self.an.colors) <= 1:
            return
        delete_color(self.an, self.process_settings(), rows[0])
        self._after_edit()

    # ------------------------------------------------------------ esportazione
    def export_dialog(self):
        if self.an is None:
            QMessageBox.information(self, "Esporta", "Apri ed elabora prima un'immagine.")
            return
        folder = self.qs.value("last_export_dir", str(self.path.parent if self.path else Path.home()))
        chosen = self.qs.value("export_formats", None)
        if isinstance(chosen, str):
            chosen = [c for c in chosen.split(",") if c]
        dlg = ExportDialog(folder, self.path.stem if self.path else "modello", chosen, self)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        what = dlg.selection()
        if not what:
            return
        folder = Path(dlg.folder.text())
        stem = dlg.stem.text().strip() or "modello"
        self.qs.setValue("last_export_dir", str(folder))
        self.qs.setValue("export_formats", ",".join(sorted(what)))
        an, ps, ms = self.an, self.process_settings(), self.model_settings()

        def job(progress):
            progress("Creazione del modello 3D e scrittura dei file…", 0.3)
            return export_all(an, None, folder, stem, ps, ms, what)

        self._busy("Esportazione…")
        self.export_btn.setEnabled(False)
        w = Worker(job, self)
        w.progress.connect(self._on_progress)
        w.done.connect(lambda files: self._exported(folder, files))
        w.failed.connect(self._on_failed)
        w.finished.connect(lambda: self.export_btn.setEnabled(True))
        self._export_worker = w
        w.start()

    def _exported(self, folder: Path, files: list[Path]):
        self._idle(f"Esportati {len(files)} file in {folder}")
        box = QMessageBox(self)
        box.setWindowTitle("Esportazione completata")
        names = "\n".join(f"• {p.relative_to(folder) if p.is_relative_to(folder) else p}"
                          for p in files[:14])
        more = f"\n… e altri {len(files) - 14}" if len(files) > 14 else ""
        box.setText(f"File salvati in:\n{folder}\n\n{names}{more}")
        open_btn = box.addButton("Apri cartella", QMessageBox.ButtonRole.ActionRole)
        box.addButton("OK", QMessageBox.ButtonRole.AcceptRole)
        box.exec()
        if box.clickedButton() is open_btn:
            open_folder(folder)

    # ------------------------------------------------------------ modello AI
    def download_model(self) -> bool:
        """Chiede conferma e scarica il modello; True se il download è partito."""
        name = self.ai_model.currentData()
        info = ai_models.MODELS[name]
        if ai_models.is_available(name):
            QMessageBox.information(self, "Modello AI", "Il modello è già stato scaricato.")
            return False
        if not ai_models.onnx_available():
            QMessageBox.warning(self, "Modello AI", "Il motore AI (onnxruntime) non è installato.")
            return False
        ok = QMessageBox.question(
            self, "Scarica modello AI",
            f"Scaricare «{info.label}» ({info.size_mb} MB)?\n\n"
            "Serve solo una volta: poi la rimozione dello sfondo funziona offline, "
            "sul tuo computer.")
        if ok != QMessageBox.StandardButton.Yes:
            return False
        dlg = QProgressDialog("Download del modello AI…", "Nascondi", 0, 100, self)
        dlg.setWindowTitle("Modello AI")
        dlg.setMinimumDuration(0)
        dlg.setValue(0)
        w = Worker(lambda progress: ai_models.download(name, lambda f: progress("", f)), self)
        w.progress.connect(lambda _m, f: dlg.setValue(int(f * 100)))

        def finished_ok(_):
            dlg.close()
            self._update_ai_status()
            QMessageBox.information(self, "Modello AI", "Modello scaricato: ora lo sfondo "
                                    "viene rimosso con l'intelligenza artificiale.")
            if self.bg_mode.currentData() in ("auto", "ai"):
                self.process()

        def failed(msg):
            dlg.close()
            QMessageBox.critical(self, "Modello AI", f"Download non riuscito:\n{msg}\n\n"
                                 "Verrà usato il metodo classico.")
            self.process()

        w.done.connect(finished_ok)
        w.failed.connect(failed)
        self._download_worker = w
        w.start()
        return True

    # ------------------------------------------------------------ aiuto
    def show_help(self):
        QMessageBox.information(self, "Come stampare in multicolore", HELP_TEXT)


HELP_TEXT = """\
BAMBU STUDIO / ORCA SLICER
• File .3mf: trascinalo in Bambu Studio. Arriva come un unico oggetto con
  una parte per colore («Colore 1 #RRGGBB», …), già allineate.
  Se i filamenti non vengono assegnati da soli (Bambu Studio può dire che
  carica «solo la geometria»), nell'elenco Oggetti seleziona ogni parte e
  scegli il filamento: lo slot AMS è quello della tabella dei colori.
• File .obj: Bambu Studio (1.9 o più recente) apre una finestra per
  abbinare ogni colore dell'immagine a un filamento.
• STL per colore: selezionali tutti, importali e rispondi «Sì» a «caricare
  come singolo oggetto con più parti?». Il nome del file indica lo slot AMS.

FUSION 360
• Vettoriale: Inserisci > Inserisci SVG (oppure Inserisci DXF) su uno
  schizzo, poi Estrudi i profili che vuoi. Le misure sono in millimetri.
• 3D: Inserisci > Inserisci mesh (3MF, OBJ o STL).

CONSIGLI
• Un PNG trasparente o uno sfondo uniforme danno i risultati migliori.
  Per le foto usa il modello AI (menu Strumenti).
• Pochi colori (3–6) = stampa più veloce e meno spreco di filamento.
• «Dettaglio minimo» almeno 0,8–1 mm con ugello da 0,4 mm.
• «Extra» nella tabella dei colori alza un colore (occhi, bottoni…).
"""
