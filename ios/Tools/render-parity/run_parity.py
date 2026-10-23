"""Compare le rendu C++ de l'application iOS (MaskRenderer.cpp) au rendu de la version PC (render.py).

Prérequis : OpenCV C++ (modules core et imgproc), Python avec numpy et opencv, sources de la version PC
(PYTHONPATH=desktop/src). Usage, depuis ce dossier :

    g++ -O2 -std=c++17 -ffp-contract=off -I/usr/include/opencv4 ../../Blurr/Engine/MaskRenderer.cpp render_cli.cpp \
        -lopencv_core -lopencv_imgproc -o render_cli
    PYTHONPATH=../../../desktop/src python3 run_parity.py ./render_cli

Critère : écart d'au plus 1/255 sur chaque canal (ordre des sommes en virgule flottante), pixels hors ellipses
identiques, même nombre d'ellipses dessinées.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

import numpy as np

from blurr.model import MaskStyle
from blurr.render import MaskRenderer


def test_image(w: int, h: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    img = rng.integers(0, 256, size=(h, w, 3), dtype=np.uint8)
    img[::2, ::2] = 255  # motif à haute fréquence
    # Dégradé et zones lisses, plus proches d'une vraie image.
    yy, xx = np.mgrid[0:h, 0:w]
    smooth = ((np.sin(xx / 7.0) + np.cos(yy / 11.0)) * 60 + 128).astype(np.uint8)
    img[h // 2 :, :, 1] = smooth[h // 2 :]
    return img


def run_cli(cli: str, img: np.ndarray, ellipses: np.ndarray, style: MaskStyle, channels: int) -> tuple:
    h, w = img.shape[:2]
    src = img if channels == 3 else np.dstack([img, np.full((h, w), 255, np.uint8)])
    with tempfile.TemporaryDirectory() as d:
        pin = os.path.join(d, "in.raw")
        pel = os.path.join(d, "e.f32")
        pout = os.path.join(d, "out.raw")
        np.ascontiguousarray(src).tofile(pin)
        np.ascontiguousarray(ellipses, dtype=np.float32).tofile(pel)
        res = subprocess.run(
            [cli, str(w), str(h), str(channels), "1" if style is MaskStyle.BLACK else "0", pin, pel, pout],
            check=True, capture_output=True, text=True,
        )
        out = np.fromfile(pout, dtype=np.uint8).reshape(h, w, channels)
    return out, int(res.stdout.strip())


def cases():
    yield "reference-desktop", 96, 72, np.array(
        [[0.30, 0.40, 0.18, 0.25], [0.38, 0.45, 0.06, 0.08], [0.95, 0.05, 0.10, 0.12]], dtype=np.float32)
    yield "centre", 160, 90, np.array([[0.5, 0.5, 0.1, 0.15]], dtype=np.float32)
    yield "damier", 400, 400, np.array([[0.5, 0.5, 0.2, 0.2]], dtype=np.float32)
    rng = np.random.default_rng(7)
    for k, (w, h) in enumerate([(641, 359), (1280, 720), (333, 777), (1920, 1080), (17, 13)]):
        n = int(rng.integers(1, 40))
        e = np.zeros((n, 4), dtype=np.float32)
        e[:, 0] = rng.uniform(-0.05, 1.05, n)
        e[:, 1] = rng.uniform(-0.05, 1.05, n)
        e[:, 2] = rng.uniform(0.002, 0.25, n)
        e[:, 3] = e[:, 2] * rng.uniform(0.8, 2.2, n) * w / h
        yield f"aleatoire-{k}-{w}x{h}-{n}", w, h, e
    yield "geant", 320, 240, np.array([[0.5, 0.5, 2.0, 2.0]], dtype=np.float32)
    yield "minuscule", 320, 240, np.array([[0.5, 0.5, 0.001, 0.001]], dtype=np.float32)
    yield "vide", 64, 48, np.zeros((0, 4), dtype=np.float32)


def main(cli: str) -> int:
    worst = 0
    failures = 0
    for name, w, h, e in cases():
        img = test_image(w, h, seed=w * 31 + h)
        for style in (MaskStyle.BLUR, MaskStyle.BLACK):
            ref_renderer = MaskRenderer(w, h, style)
            ref = ref_renderer.apply(img.copy(), e)
            for channels in (3, 4):
                out, drawn = run_cli(cli, img, e, style, channels)
                diff = np.abs(out[:, :, :3].astype(int) - ref.astype(int))
                worst = max(worst, int(diff.max()) if diff.size else 0)
                alpha_ok = channels == 3 or bool((out[:, :, 3] == 255).all())
                changed_ref = np.any(ref != img, axis=2)
                changed_out = np.any(out[:, :, :3] != img, axis=2)
                # Pixels modifiés par l'un et pas par l'autre : seulement si l'écart est d'arrondi (au plus 1).
                stray = np.logical_xor(changed_ref, changed_out) & (diff.max(axis=2) > 1)
                ok = diff.max(initial=0) <= 1 and alpha_ok and not stray.any() and drawn == ref_renderer.drawn_ellipses
                n_diff = int((diff > 0).any(axis=2).sum())
                print(f"{'OK ' if ok else 'ÉCHEC'} {name:28s} {style.value:5s} {channels} canaux : écart max "
                      f"{int(diff.max(initial=0))}, {n_diff} pixels différents, {drawn} ellipses dessinées "
                      f"(référence {ref_renderer.drawn_ellipses})")
                failures += 0 if ok else 1
    print(f"Écart maximal : {worst} ; échecs : {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "./render_cli"))
