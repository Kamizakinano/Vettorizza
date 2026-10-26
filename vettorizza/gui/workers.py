"""Esecuzione dei calcoli lunghi fuori dal thread dell'interfaccia."""

from __future__ import annotations

import traceback
from typing import Callable

from PySide6.QtCore import QThread, Signal


class Worker(QThread):
    """Esegue ``fn(progress)`` in un thread; ``progress(testo, frazione)``."""

    progress = Signal(str, float)
    done = Signal(object)
    failed = Signal(str)

    def __init__(self, fn: Callable, parent=None):
        super().__init__(parent)
        self._fn = fn

    def run(self):
        try:
            result = self._fn(lambda msg, frac: self.progress.emit(msg, float(frac)))
        except Exception as exc:  # mostrato all'utente in una finestra di errore
            traceback.print_exc()
            self.failed.emit(str(exc) or exc.__class__.__name__)
        else:
            self.done.emit(result)
