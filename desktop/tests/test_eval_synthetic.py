"""Tests synthétiques de validation de l'évaluation (Étape 1 - L6).

Tous les cas sont générés en code (aucun fichier média physique).
Vérifie rigoureusement les 10 scénarios spécifiés au plan :
1. Masques = boîtes GT -> rappel 100%, exposition 0
2. Aucun masque -> rappel 0%, exposition = durée totale
3. Ellipse inscrite dans la boîte -> couverture ~78.5% -> NON couverte
4. Ellipse inscrite dans la boîte agrandie de 1.3 -> couverture ~98.6% -> couverte
5. Ellipse inscrite dans la boîte agrandie de 1.6 (règle deface) -> couverture 100% -> couverte
6. Rectangle décalé de la moitié de sa largeur -> couverture 50% -> non couverte
7. Sortie et retour (outside) avec exposition avant et après -> 2 expositions distinctes
8. Cadence variable (VFR) -> exposition en ms = somme exacte des durées réelles
9. Horodatage à 0.5 ms (500 µs) -> apparié avec succès
10. Horodatage à 2 ms (2000 µs) ou masque manquant -> erreur explicite (TimestampMatchError)
"""

import math
import pytest

from blurr_ref.eval.coverage import compute_box_coverage, is_box_covered
from blurr_ref.eval.metrics import (
    TimestampMatchError,
    evaluate_clip,
    match_frames,
)
from blurr_ref.gt import GTBox, GTDoc, GTFrameInfo, GTPerson
from blurr_ref.masks import EllipseShape, MaskFrame, MasksDoc, RectShape


def test_coverage_inscribed_ellipse():
    """Ellipse inscrite dans la boîte : couverture pi/4 ~= 78.5% -> non couverte (seuil 90%)."""
    box = GTBox(i=0, x=100.0, y=100.0, w=100.0, h=100.0)
    # Ellipse inscrite : cx=150, cy=150, rx=50, ry=50
    ellipse = EllipseShape(cx=150.0, cy=150.0, rx=50.0, ry=50.0)
    cov = compute_box_coverage(box, [ellipse], grid_resolution=200)

    expected = math.pi / 4.0  # ~0.785398
    assert abs(cov - expected) < 0.01
    assert not is_box_covered(box, [ellipse])


def test_coverage_ellipse_scaled_1_3():
    """Ellipse agrandie de 1.3 (cas synthétique) : couverture ~98.6% -> couverte."""
    box = GTBox(i=0, x=100.0, y=100.0, w=100.0, h=100.0)
    # Demi-axes agrandis de 1.3 : rx = 50 * 1.3 = 65, ry = 65
    ellipse = EllipseShape(cx=150.0, cy=150.0, rx=65.0, ry=65.0)
    cov = compute_box_coverage(box, [ellipse], grid_resolution=200)

    # Doit être > 90% (théoriquement ~98.6%)
    assert cov > 0.95
    assert abs(cov - 0.986) < 0.02
    assert is_box_covered(box, [ellipse])


def test_coverage_ellipse_scaled_1_6_deface_rule():
    """Ellipse agrandie de 1.6 (règle effective de deface scale_bb avec mask_scale 1.3) : couverture 100%."""
    box = GTBox(i=0, x=100.0, y=100.0, w=100.0, h=100.0)
    # Demi-axes agrandis de 1.6 : rx = 50 * 1.6 = 80, ry = 80
    # Coins de la boîte à (50/80)^2 * 2 = 0.78125 < 1.0 (strictement à l'intérieur de l'ellipse)
    ellipse = EllipseShape(cx=150.0, cy=150.0, rx=80.0, ry=80.0)
    cov = compute_box_coverage(box, [ellipse], grid_resolution=200)

    assert cov == 1.0
    assert is_box_covered(box, [ellipse])


def test_coverage_rect_half_shifted():
    """Rectangle décalé de la moitié de sa largeur : couverture 50% -> non couverte."""
    box = GTBox(i=0, x=100.0, y=100.0, w=100.0, h=100.0)
    # Décalé de 50 px vers la droite
    rect = RectShape(x=150.0, y=100.0, w=100.0, h=100.0)
    cov = compute_box_coverage(box, [rect], grid_resolution=100)

    assert abs(cov - 0.50) < 0.01
    assert not is_box_covered(box, [rect])


def test_eval_masks_identical_to_gt():
    """Masques = boîtes de vérité terrain (rectangles) : rappel 100%, exposition 0."""
    frames_gt = [GTFrameInfo(i=i, pts_us=i * 33333, dur_us=33333) for i in range(10)]
    person = GTPerson(
        id=1,
        type="réel",
        boxes=[GTBox(i=i, x=100.0, y=100.0, w=80.0, h=80.0) for i in range(10)],
    )
    gt_doc = GTDoc(clip="TEST01", frames=frames_gt, persons=[person])

    mask_frames = [
        MaskFrame(
            pts_us=i * 33333,
            shapes=[RectShape(x=100.0, y=100.0, w=80.0, h=80.0)],
        )
        for i in range(10)
    ]
    masks_doc = MasksDoc(clip="TEST01", frames=mask_frames)

    res = evaluate_clip(gt_doc, masks_doc)
    assert res.recall == 1.0
    assert res.covered_gt_boxes == 10
    assert len(res.exposures) == 0
    assert res.worst_exposure_frames == 0
    assert res.worst_exposure_ms == 0.0
    assert res.persons_never_exposed_ratio == 1.0


def test_eval_no_masks():
    """Aucun masque : rappel 0%, exposition = durée totale."""
    frames_gt = [GTFrameInfo(i=i, pts_us=i * 40000, dur_us=40000) for i in range(5)]
    person = GTPerson(
        id=1,
        type="réel",
        boxes=[GTBox(i=i, x=100.0, y=100.0, w=80.0, h=80.0) for i in range(5)],
    )
    gt_doc = GTDoc(clip="TEST02", frames=frames_gt, persons=[person])

    # Masques vides pour chaque image
    mask_frames = [MaskFrame(pts_us=i * 40000, shapes=[]) for i in range(5)]
    masks_doc = MasksDoc(clip="TEST02", frames=mask_frames)

    res = evaluate_clip(gt_doc, masks_doc)
    assert res.recall == 0.0
    assert res.covered_gt_boxes == 0
    assert len(res.exposures) == 1
    assert res.worst_exposure_frames == 5
    assert res.worst_exposure_ms == 200.0  # 5 * 40 ms = 200 ms
    assert res.persons_never_exposed_ratio == 0.0


def test_eval_outside_interruption_two_distinct_exposures():
    """Personne qui sort (outside) et revient : deux expositions distinctes non additionnées."""
    # Personne présente à frames 0, 1, puis absente (frame 2, 3), puis présente à 4, 5
    frames_gt = [GTFrameInfo(i=i, pts_us=i * 33333, dur_us=33333) for i in range(6)]
    boxes = [
        GTBox(i=0, x=100.0, y=100.0, w=50.0, h=50.0),
        GTBox(i=1, x=100.0, y=100.0, w=50.0, h=50.0),
        # Frame 2 et 3 : absente (pas de boîte)
        GTBox(i=4, x=100.0, y=100.0, w=50.0, h=50.0),
        GTBox(i=5, x=100.0, y=100.0, w=50.0, h=50.0),
    ]
    person = GTPerson(id=1, type="réel", boxes=boxes)
    gt_doc = GTDoc(clip="TEST03", frames=frames_gt, persons=[person])

    mask_frames = [MaskFrame(pts_us=i * 33333, shapes=[]) for i in range(6)]
    masks_doc = MasksDoc(clip="TEST03", frames=mask_frames)

    res = evaluate_clip(gt_doc, masks_doc)
    assert len(res.exposures) == 2
    assert res.exposures[0].n_frames == 2
    assert res.exposures[1].n_frames == 2
    assert res.worst_exposure_frames == 2  # Non additionnées


def test_eval_variable_frame_rate_duration():
    """Cadence variable (durées d'image inégales) : exposition en ms = somme des durées réelles."""
    durations = [20000, 50000, 30000]  # 20ms, 50ms, 30ms -> total 100ms
    pts = [0, 20000, 70000]
    frames_gt = [GTFrameInfo(i=i, pts_us=pts[i], dur_us=durations[i]) for i in range(3)]
    person = GTPerson(
        id=1,
        type="réel",
        boxes=[GTBox(i=i, x=50.0, y=50.0, w=50.0, h=50.0) for i in range(3)],
    )
    gt_doc = GTDoc(clip="TEST04", frames=frames_gt, persons=[person])

    mask_frames = [MaskFrame(pts_us=pts[i], shapes=[]) for i in range(3)]
    masks_doc = MasksDoc(clip="TEST04", frames=mask_frames)

    res = evaluate_clip(gt_doc, masks_doc)
    assert res.worst_exposure_ms == 100.0


def test_eval_timestamp_matching_tolerance():
    """Horodatage à 0.5 ms (500 µs) apparié, à 2.0 ms (2000 µs) déclenche TimestampMatchError."""
    # 1. Cas 0.5 ms -> apparié
    frames_gt = [GTFrameInfo(i=0, pts_us=10000, dur_us=33333)]
    gt_doc = GTDoc(clip="TEST_MATCH", frames=frames_gt, persons=[])

    # Masque décalé de 500 µs (0.5 ms)
    mask_frames_ok = [MaskFrame(pts_us=10500, shapes=[])]
    matched = match_frames(gt_doc, MasksDoc(clip="TEST_MATCH", frames=mask_frames_ok), tolerance_us=1000)
    assert 0 in matched

    # 2. Cas 2.0 ms -> Erreur explicite
    mask_frames_err = [MaskFrame(pts_us=12000, shapes=[])]
    with pytest.raises(TimestampMatchError):
        match_frames(gt_doc, MasksDoc(clip="TEST_MATCH", frames=mask_frames_err), tolerance_us=1000)
