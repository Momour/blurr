"""Calcul de la couverture d'une boîte englobante par l'union des masques.

Définitions (Étape 1 - Section 4.5) :
- Couverture d'une boîte : Part des pixels de la boîte situés dans l'union
  des formes de masque (rectangles et ellipses) de l'image appariée.
- Boîte couverte : Couverture >= 0.9 (seuil de 90 %).
"""

from __future__ import annotations

from typing import List, Sequence
import numpy as np

from blurr_ref.gt import GTBox
from blurr_ref.masks import EllipseShape, RectShape, ShapeType

COVERAGE_THRESHOLD: float = 0.90


def compute_box_coverage(
    box: GTBox | dict,
    shapes: Sequence[ShapeType],
    grid_resolution: int = 100,
) -> float:
    """Calcule la part de la boîte [0.0, 1.0] couverte par l'union des formes de masques.

    Pour garantir une précision analytique sur toutes les échelles (y compris visages < 20 px),
    l'évaluation est effectuée sur une grille régulière de points discrétisant la boîte.
    """
    if isinstance(box, dict):
        bx = float(box["x"])
        by = float(box["y"])
        bw = float(box["w"])
        bh = float(box["h"])
    else:
        bx = float(box.x)
        by = float(box.y)
        bw = float(box.w)
        bh = float(box.h)

    if bw <= 0.0 or bh <= 0.0 or not shapes:
        return 0.0

    # Résolution de la grille (au moins grid_resolution points par côté)
    nw = max(int(np.ceil(bw)), grid_resolution)
    nh = max(int(np.ceil(bh)), grid_resolution)

    # Coordonnées des centres de cellules de la grille à l'intérieur de la boîte
    x_lin = np.linspace(bx + (bw / (2.0 * nw)), bx + bw - (bw / (2.0 * nw)), nw)
    y_lin = np.linspace(by + (bh / (2.0 * nh)), by + bh - (bh / (2.0 * nh)), nh)
    grid_x, grid_y = np.meshgrid(x_lin, y_lin)

    covered = np.zeros((nh, nw), dtype=bool)

    for s in shapes:
        if isinstance(s, RectShape):
            in_rect = (
                (grid_x >= s.x)
                & (grid_x <= s.x + s.w)
                & (grid_y >= s.y)
                & (grid_y <= s.y + s.h)
            )
            covered |= in_rect
        elif isinstance(s, EllipseShape):
            if s.rx <= 0.0 or s.ry <= 0.0:
                continue
            dx = (grid_x - s.cx) / s.rx
            dy = (grid_y - s.cy) / s.ry
            in_ellipse = (dx * dx + dy * dy) <= 1.0
            covered |= in_ellipse

        # Optimisation : si tout est déjà couvert, arrêt anticipé
        if np.all(covered):
            return 1.0

    ratio = float(np.count_nonzero(covered)) / float(nw * nh)
    return min(1.0, max(0.0, ratio))


def is_box_covered(
    box: GTBox | dict,
    shapes: Sequence[ShapeType],
    threshold: float = COVERAGE_THRESHOLD,
) -> bool:
    """Détermine si la boîte est considérée comme protégée (couverture >= seuil)."""
    return compute_box_coverage(box, shapes) >= threshold
