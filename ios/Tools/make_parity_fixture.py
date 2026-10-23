"""Génère le jeu de parité du plan de masquage iOS (Swift) contre la version PC (Python, elle-même alignée sur
Android v0.2).

Détections synthétiques (aucune image) : visages qui se déplacent, trous de détection, scores variables, faux
positifs de score moyen. Le plan est construit par `blurr.maskplan.build` (version PC) pour les trois sensibilités ;
le test `MaskPlanParityTests` (BlurrCore) reconstruit le même plan en Swift et compare.

Usage (depuis la racine du dépôt, paquet desktop installé ou PYTHONPATH=desktop/src) :
    python ios/Tools/make_parity_fixture.py ios/BlurrCore/Tests/BlurrCoreTests/Fixtures/maskplan-parity.json
"""

from __future__ import annotations

import json
import sys

import numpy as np

from blurr import maskplan
from blurr.model import Detections, FaceBox, Sensitivity

FRAMES = 360
FRAME_US = 16_667  # 60 i/s
ASPECT = 16.0 / 9.0
SEED = 20261023


def f32(v: float) -> float:
    return float(np.float32(v))


def fmt(v: float) -> str:
    return format(np.float32(v), ".9g")


def synthetic_detections(rng: np.random.Generator) -> Detections:
    faces_per_frame = [[] for _ in range(FRAMES)]
    # Visages réels : trajectoire linéaire bruitée, taille et score propres, trous de détection.
    for _ in range(9):
        start = int(rng.integers(0, FRAMES - 40))
        end = int(min(FRAMES - 1, start + rng.integers(30, 300)))
        w = float(rng.uniform(0.012, 0.12))
        h = w * ASPECT * float(rng.uniform(1.05, 1.3))
        x = float(rng.uniform(0.05, 0.9 - w))
        y = float(rng.uniform(0.05, 0.9 - h))
        vx = float(rng.uniform(-0.002, 0.002))
        vy = float(rng.uniform(-0.0015, 0.0015))
        base = float(rng.uniform(0.45, 0.97))
        gap_until = -1
        for f in range(start, end + 1):
            if f <= gap_until:
                continue
            if rng.random() < 0.02:
                gap_until = f + int(rng.integers(3, 30))  # trou de détection (parfois plus long que 0,3 s)
                continue
            if rng.random() < 0.08:
                continue
            k = f - start
            score = min(0.99, max(0.31, base + float(rng.normal(0, 0.08))))
            jitter = float(rng.normal(0, 0.002))
            faces_per_frame[f].append(
                (x + vx * k + jitter, y + vy * k - jitter, w * float(rng.uniform(0.92, 1.08)), h * float(rng.uniform(0.92, 1.08)), score)
            )
    # Faux positifs isolés ou brefs, de score moyen.
    for f in range(FRAMES):
        for _ in range(int(rng.integers(0, 3))):
            w = float(rng.uniform(0.008, 0.05))
            faces_per_frame[f].append(
                (float(rng.uniform(0, 0.95)), float(rng.uniform(0, 0.9)), w, w * ASPECT, float(rng.uniform(0.3, 0.78)))
            )
    d = Detections()
    for f in range(FRAMES):
        boxes = [FaceBox(f32(a), f32(b), f32(c), f32(e), f32(s)) for (a, b, c, e, s) in faces_per_frame[f]]
        d.add(f * FRAME_US, boxes)
    return d


def main(out_path: str) -> None:
    rng = np.random.default_rng(SEED)
    d = synthetic_detections(rng)
    doc = {
        "schema": "blurr-maskplan-parity/1",
        "aspect": ASPECT,
        "mask_scale": 1.6,
        "margin_frames": 5,
        "union_frames": 1,
        "times": [d.pts_us(i) for i in range(d.size)],
        "faces": [[[fmt(b.x), fmt(b.y), fmt(b.w), fmt(b.h), fmt(b.score)] for b in d.faces(i)] for i in range(d.size)],
        "plans": {},
    }
    for s in Sensitivity:
        plan = maskplan.build(d, s.params, 1.6, 5, aspect=ASPECT, union_frames=1)
        doc["plans"][s.value] = {
            "stats": [plan.stats.tracks, plan.stats.confirmed_tracks, plan.stats.masked_frames],
            "ellipses": [[fmt(v) for v in np.asarray(plan.at(i)).ravel()] for i in range(plan.frame_count)],
        }
        print(f"{s.value}: {plan.stats}")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    print(f"{out_path} : {d.size} images, {d.total_faces} détections")


if __name__ == "__main__":
    main(sys.argv[1])
