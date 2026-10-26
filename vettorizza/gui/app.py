"""Avvio dell'interfaccia grafica."""

from __future__ import annotations

import sys
from pathlib import Path


def _icon_path() -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[2]))
    return base / "assets" / "icon.png"


def main() -> int:
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication

    from .main_window import MainWindow

    if sys.platform == "win32":
        # Icona corretta nella barra delle applicazioni di Windows.
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("Vettorizza.App")

    app = QApplication(sys.argv)
    app.setApplicationName("Vettorizza")
    app.setOrganizationName("Vettorizza")
    app.setStyle("Fusion")
    if _icon_path().is_file():
        app.setWindowIcon(QIcon(str(_icon_path())))
    win = MainWindow()
    win.show()
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if args:
        win.open_image(args[0])
    return app.exec()
