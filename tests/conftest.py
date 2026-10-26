import cv2
import numpy as np
import pytest


def make_toy(size: int = 400, noise: bool = True) -> np.ndarray:
    """Un "pupazzetto" sintetico su sfondo chiaro: corpo rosso, testa gialla,
    occhi neri, pancia bianca."""
    img = np.full((size, size, 3), (235, 238, 240), np.uint8)
    s = size / 400
    cv2.ellipse(img, (int(200 * s), int(270 * s)), (int(90 * s), int(100 * s)), 0, 0, 360, (200, 30, 40), -1)
    cv2.ellipse(img, (int(200 * s), int(290 * s)), (int(45 * s), int(55 * s)), 0, 0, 360, (250, 250, 250), -1)
    cv2.circle(img, (int(200 * s), int(130 * s)), int(75 * s), (245, 200, 30), -1)
    cv2.circle(img, (int(172 * s), int(120 * s)), int(12 * s), (20, 20, 20), -1)
    cv2.circle(img, (int(228 * s), int(120 * s)), int(12 * s), (20, 20, 20), -1)
    if noise:
        rng = np.random.default_rng(1)
        img = np.clip(img.astype(int) + rng.normal(0, 6, img.shape), 0, 255).astype(np.uint8)
    alpha = np.full((size, size, 1), 255, np.uint8)
    return np.concatenate([img, alpha], axis=2)


@pytest.fixture
def toy_rgba():
    return make_toy()
