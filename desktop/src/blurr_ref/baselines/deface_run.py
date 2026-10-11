"""Exécution de CenterFace (deface) sur les images extraites (Étape 1 - L7).

Respecte les spécifications :
- Appel direct de CenterFace à la résolution native
- Conversion BGR -> RGB (car imread retourne BGR et le réseau attend RGB)
- Application de la règle exacte de scale_bb :
  effective_scale = 1 + 2 * (mask_scale - 1) = 1.6 pour mask_scale = 1.3
- Modes supportés : 'blur' (ellipse inscrite) et 'solid' (rectangle plein)
- Génération d'un fichier masks.json (blurr-masks/0)
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List, Literal, Sequence, Tuple
import cv2
import numpy as np

from deface.centerface import CenterFace

from blurr_ref.gt import GTFrameInfo
from blurr_ref.masks import EllipseShape, MaskFrame, MasksDoc, RectShape, ShapeType


def compute_deface_scaled_bb(
    x1: float, y1: float, x2: float, y2: float, mask_scale: float = 1.3
) -> Tuple[float, float, float, float]:
    """Applique la règle exacte scale_bb de deface."""
    w = x2 - x1
    h = y2 - y1
    s = mask_scale - 1.0
    dx = w * s
    dy = h * s
    return x1 - dx, y1 - dy, x2 + dx, y2 + dy


def run_deface_on_image(
    image_bgr: np.ndarray,
    centerface: CenterFace,
    threshold: float = 0.2,
    mask_scale: float = 1.3,
    mode: Literal["blur", "solid"] = "blur",
) -> List[ShapeType]:
    """Exécute la détection CenterFace sur une image BGR et retourne les formes de masque."""
    h_img, w_img = image_bgr.shape[:2]
    # Conversion BGR -> RGB obligatoire
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)

    dets, _ = centerface(image_rgb, threshold=threshold)
    shapes: List[ShapeType] = []

    for det in dets:
        boxes = det[:4]
        score = det[4]
        if score < threshold:
            continue

        x1, y1, x2, y2 = float(boxes[0]), float(boxes[1]), float(boxes[2]), float(boxes[3])
        # Règle scale_bb de deface
        sx1, sy1, sx2, sy2 = compute_deface_scaled_bb(x1, y1, x2, y2, mask_scale=mask_scale)
        sw = sx2 - sx1
        sh = sy2 - sy1

        if mode == "solid":
            # Mode solid : rectangle plein
            shapes.append(RectShape(x=round(sx1, 1), y=round(sy1, 1), w=round(sw, 1), h=round(sh, 1)))
        else:
            # Mode blur (défaut deface) : ellipse inscrite dans la boîte agrandie
            cx = (sx1 + sx2) / 2.0
            cy = (sy1 + sy2) / 2.0
            rx = sw / 2.0
            ry = sh / 2.0
            shapes.append(
                EllipseShape(cx=round(cx, 1), cy=round(cy, 1), rx=round(rx, 1), ry=round(ry, 1))
            )

    return shapes


def run_deface_on_frames(
    frames_dir: Path | str,
    frames_info: Sequence[GTFrameInfo],
    clip_id: str,
    threshold: float = 0.2,
    mask_scale: float = 1.3,
    mode: Literal["blur", "solid"] = "blur",
) -> Tuple[MasksDoc, float]:
    """Exécute CenterFace sur toutes les images d'un clip et retourne le MasksDoc et le temps total."""
    fdir = Path(frames_dir)
    centerface = CenterFace()

    mask_frames: List[MaskFrame] = []
    t_start = time.perf_counter()

    for fi in frames_info:
        img_name = f"{fi.i:06d}.jpg"
        img_path = fdir / img_name
        if not img_path.exists():
            raise FileNotFoundError(f"Image introuvable: {img_path}")

        img_bgr = cv2.imread(str(img_path))
        if img_bgr is None:
            raise ValueError(f"Impossible de charger l'image: {img_path}")

        shapes = run_deface_on_image(
            img_bgr, centerface, threshold=threshold, mask_scale=mask_scale, mode=mode
        )
        mask_frames.append(MaskFrame(pts_us=fi.pts_us, shapes=shapes))

    total_time_sec = time.perf_counter() - t_start

    effective_scale = 1.0 + 2.0 * (mask_scale - 1.0)
    masks_doc = MasksDoc(
        schema="blurr-masks/0",
        clip=clip_id,
        method="deface-centerface",
        params={
            "threshold": threshold,
            "mask_scale": mask_scale,
            "effective_scale": effective_scale,
            "shape": "rect" if mode == "solid" else "ellipse",
            "mode": mode,
        },
        pts_origin="container",
        frames=mask_frames,
    )

    return masks_doc, total_time_sec
