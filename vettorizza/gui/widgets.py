"""Widget riutilizzabili dell'interfaccia."""

from __future__ import annotations

import numpy as np
from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QImage, QPainter, QPixmap
from PySide6.QtWidgets import (QColorDialog, QGraphicsPixmapItem, QGraphicsScene,
                               QGraphicsView, QHBoxLayout, QLabel, QPushButton,
                               QSizePolicy, QToolButton, QVBoxLayout, QWidget)

from ..imaging import hex_color


def to_pixmap(img: np.ndarray) -> QPixmap:
    img = np.ascontiguousarray(img)
    h, w = img.shape[:2]
    if img.ndim == 2:
        qimg = QImage(img.data, w, h, w, QImage.Format.Format_Grayscale8)
    elif img.shape[2] == 4:
        qimg = QImage(img.data, w, h, 4 * w, QImage.Format.Format_RGBA8888)
    else:
        qimg = QImage(img.data, w, h, 3 * w, QImage.Format.Format_RGB888)
    return QPixmap.fromImage(qimg.copy())


class ImageView(QGraphicsView):
    """Vista immagine con zoom (rotella), trascinamento e adattamento automatico."""

    clicked = Signal(int, int)  # coordinate pixel nell'immagine

    def __init__(self, placeholder: str = "", parent=None):
        super().__init__(parent)
        self.setScene(QGraphicsScene(self))
        self._item = QGraphicsPixmapItem()
        self._item.setTransformationMode(Qt.TransformationMode.SmoothTransformation)
        self.scene().addItem(self._item)
        self._fit = True
        self._placeholder = placeholder
        self.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)
        self.setDragMode(QGraphicsView.DragMode.ScrollHandDrag)
        self.setTransformationAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)
        self.setBackgroundBrush(QColor("#2b2d31"))
        self.setFrameShape(QGraphicsView.Shape.NoFrame)

    def set_image(self, img: np.ndarray | None, keep_view: bool = False):
        if img is None:
            self._item.setPixmap(QPixmap())
        else:
            self._item.setPixmap(to_pixmap(img))
        self.scene().setSceneRect(QRectF(self._item.pixmap().rect()))
        if not keep_view:
            self._fit = True
        if self._fit:
            self.fit()
        self.viewport().update()

    def has_image(self) -> bool:
        return not self._item.pixmap().isNull()

    def fit(self):
        if self.has_image():
            self.fitInView(self._item, Qt.AspectRatioMode.KeepAspectRatio)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self._fit:
            self.fit()

    def wheelEvent(self, event):
        if not self.has_image():
            return
        factor = 1.25 if event.angleDelta().y() > 0 else 0.8
        self._fit = False
        self.scale(factor, factor)

    def mouseDoubleClickEvent(self, event):
        self._fit = True
        self.fit()

    def mousePressEvent(self, event):
        super().mousePressEvent(event)
        if event.button() == Qt.MouseButton.LeftButton and self.has_image():
            p: QPointF = self.mapToScene(event.position().toPoint())
            self.clicked.emit(int(p.x()), int(p.y()))

    def drawForeground(self, painter, rect):
        if not self.has_image() and self._placeholder:
            painter.save()
            painter.resetTransform()
            painter.setPen(QColor("#9aa0a6"))
            f = painter.font()
            f.setPointSize(13)
            painter.setFont(f)
            painter.drawText(self.viewport().rect(), Qt.AlignmentFlag.AlignCenter, self._placeholder)
            painter.restore()


class ColorButton(QToolButton):
    """Pulsante che mostra un colore; cliccandolo si apre il selettore."""

    colorChanged = Signal(tuple)

    def __init__(self, rgb=(255, 255, 255), size: int = 26, editable: bool = True, parent=None):
        super().__init__(parent)
        self._rgb = tuple(rgb)
        self._editable = editable
        self.setFixedSize(size, size)
        self.setCursor(Qt.CursorShape.PointingHandCursor if editable else Qt.CursorShape.ArrowCursor)
        self.clicked.connect(self._pick)
        self._apply()

    @property
    def rgb(self):
        return self._rgb

    def set_rgb(self, rgb):
        self._rgb = tuple(int(c) for c in rgb)
        self._apply()

    def _apply(self):
        self.setStyleSheet(f"QToolButton {{ background: {hex_color(self._rgb)}; "
                           "border: 1px solid #555; border-radius: 4px; }")
        self.setToolTip(hex_color(self._rgb))

    def _pick(self):
        if not self._editable:
            return
        c = QColorDialog.getColor(QColor(*self._rgb), self, "Scegli il colore")
        if c.isValid():
            self.set_rgb((c.red(), c.green(), c.blue()))
            self.colorChanged.emit(self._rgb)


FILAMENT_PRESETS: dict[str, list[str]] = {
    "Bambu PLA Basic (colori indicativi)": [
        "#FFFFFF", "#000000", "#C12E1F", "#F4EE2A", "#FF6A13", "#0A2989",
        "#0086D6", "#00AE42", "#F55A74", "#5E43B7", "#9D432C", "#8E9089", "#F7E6DE",
    ],
    "AMS base: bianco, nero, rosso, giallo": ["#FFFFFF", "#000000", "#C12E1F", "#F4EE2A"],
}


class PaletteEditor(QWidget):
    """Elenco dei filamenti disponibili: l'ordine corrisponde agli slot dell'AMS."""

    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._buttons: list[ColorButton] = []
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        self._row = QHBoxLayout()
        self._row.setSpacing(3)
        self._row.addStretch(1)
        lay.addLayout(self._row)
        tools = QHBoxLayout()
        add = QPushButton("+ Aggiungi")
        rem = QPushButton("− Rimuovi ultimo")
        add.clicked.connect(self._add_clicked)
        rem.clicked.connect(self._remove_last)
        tools.addWidget(add)
        tools.addWidget(rem)
        lay.addLayout(tools)
        self._hint = QLabel()
        self._hint.setWordWrap(True)
        self._hint.setStyleSheet("color: #888; font-size: 11px;")
        self._hint.setText("Clic su un colore per cambiarlo. Ordine = slot AMS 1, 2, 3…")
        lay.addWidget(self._hint)
        self.setSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)

    def palette(self) -> list[tuple[int, int, int]]:
        return [b.rgb for b in self._buttons]

    def set_palette(self, colors):
        for b in self._buttons:
            b.deleteLater()
        self._buttons.clear()
        for c in colors:
            self._append(c)
        self.changed.emit()

    def _append(self, rgb):
        b = ColorButton(rgb, 24)
        b.colorChanged.connect(lambda _: self.changed.emit())
        self._row.insertWidget(self._row.count() - 1, b)
        self._buttons.append(b)
        self._renumber()

    def _renumber(self):
        for i, b in enumerate(self._buttons, 1):
            b.setToolTip(f"Slot {i}: {hex_color(b.rgb)}")

    def _add_clicked(self):
        if len(self._buttons) >= 16:
            return
        c = QColorDialog.getColor(QColor(128, 128, 128), self, "Colore del filamento")
        if c.isValid():
            self._append((c.red(), c.green(), c.blue()))
            self.changed.emit()

    def _remove_last(self):
        if self._buttons:
            self._buttons.pop().deleteLater()
            self.changed.emit()
