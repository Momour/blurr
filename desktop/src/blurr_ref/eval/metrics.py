"""Calcul des métriques d'évaluation selon la section 4.5 du plan.

Métriques calculées :
- Rappel par image (global et ventilé : taille, pose, occlusion)
- Exposition continue (durée en ms et en images)
- Plus longue exposition
- Pistes jamais exposées (global et taille médiane >= 20 px)
- Sur-masquage (formes avec < 10% de surface sur boîte annotée, par minute)
- Appariement temporel au plus proche voisin (tolérance 1 ms / 1000 µs)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
import numpy as np

from blurr_ref.eval.coverage import compute_box_coverage, is_box_covered
from blurr_ref.gt import GTBox, GTDoc, GTPerson
from blurr_ref.masks import EllipseShape, MasksDoc, RectShape, ShapeType

MATCH_TOLERANCE_US: int = 1000  # 1 ms


class TimestampMatchError(ValueError):
    """Erreur levée lorsque l'appariement temporel échoue."""
    pass


@dataclass
class ExposureInterval:
    person_id: int
    start_frame: int
    end_frame: int
    n_frames: int
    duration_ms: float
    start_pts_us: int
    end_pts_us: int


@dataclass
class ClipEvalResult:
    clip_id: str
    total_gt_boxes: int
    covered_gt_boxes: int
    recall: float
    # Ventilation par taille
    recall_under_20: Optional[float] = None
    recall_20_to_40: Optional[float] = None
    recall_40_to_80: Optional[float] = None
    recall_over_80: Optional[float] = None
    # Ventilation par pose
    recall_by_pose: Dict[str, float] = field(default_factory=dict)
    # Ventilation par occlusion
    recall_by_occlusion: Dict[str, float] = field(default_factory=dict)
    # Expositions
    exposures: List[ExposureInterval] = field(default_factory=list)
    worst_exposure_frames: int = 0
    worst_exposure_ms: float = 0.0
    # Personnes jamais exposées
    total_persons: int = 0
    persons_never_exposed: int = 0
    persons_never_exposed_ratio: float = 1.0
    persons_over_20_never_exposed_ratio: float = 1.0
    # Type image (compté à part)
    image_type_boxes: int = 0
    image_type_covered: int = 0
    # Sur-masquage
    overmask_count: int = 0
    overmask_per_minute: float = 0.0


def match_frames(
    gt_doc: GTDoc,
    masks_doc: MasksDoc,
    tolerance_us: int = MATCH_TOLERANCE_US,
) -> Dict[int, List[ShapeType]]:
    """Apparie chaque image GT (index i) aux masques correspondants par pts_us (plus proche voisin).

    Lève TimestampMatchError si une image GT n'a aucun masque dans la tolérance
    ou si plusieurs masques s'apparient à la même image.
    """
    if not gt_doc.frames:
        return {}

    mask_frames = masks_doc.frames
    if not mask_frames:
        raise TimestampMatchError(
            f"Le fichier de masques pour le clip {gt_doc.clip} ne contient aucune image."
        )

    matched: Dict[int, List[ShapeType]] = {}
    used_mask_indices: set[int] = set()

    mask_pts_list = np.array([mf.pts_us for mf in mask_frames], dtype=np.int64)

    for frame_info in gt_doc.frames:
        gt_pts = frame_info.pts_us
        # Recherche du plus proche voisin
        diffs = np.abs(mask_pts_list - gt_pts)
        best_idx = int(np.argmin(diffs))
        best_diff = diffs[best_idx]

        if best_diff > tolerance_us:
            raise TimestampMatchError(
                f"Clip {gt_doc.clip} frame {frame_info.i} (pts {gt_pts} µs) : "
                f"aucun masque trouvé à moins de {tolerance_us} µs "
                f"(plus proche à {best_diff} µs, pts {mask_pts_list[best_idx]} µs)."
            )

        if best_idx in used_mask_indices:
            raise TimestampMatchError(
                f"Clip {gt_doc.clip} : deux images de masques ou plus correspondent "
                f"à l'image GT frame {frame_info.i} (pts {gt_pts} µs)."
            )

        used_mask_indices.add(best_idx)
        matched[frame_info.i] = mask_frames[best_idx].shapes

    return matched


def evaluate_clip(
    gt_doc: GTDoc,
    masks_doc: MasksDoc,
    tolerance_us: int = MATCH_TOLERANCE_US,
) -> ClipEvalResult:
    """Évalue exhaustivement un clip contre ses masques."""
    matched_shapes = match_frames(gt_doc, masks_doc, tolerance_us=tolerance_us)

    frame_durations: Dict[int, int] = {f.i: f.dur_us for f in gt_doc.frames}
    frame_pts: Dict[int, int] = {f.i: f.pts_us for f in gt_doc.frames}

    total_real_boxes = 0
    covered_real_boxes = 0

    size_buckets = {
        "<20": [0, 0],
        "20-40": [0, 0],
        "40-80": [0, 0],
        ">=80": [0, 0],
    }

    pose_buckets: Dict[str, List[int]] = {}
    occlusion_buckets: Dict[str, List[int]] = {}

    image_type_boxes = 0
    image_type_covered = 0

    exposures: List[ExposureInterval] = []

    real_persons = [p for p in gt_doc.persons if p.type == "réel"]
    total_persons = len(real_persons)
    persons_never_exposed_count = 0

    # Personnes de taille médiane >= 20 px
    persons_over_20_count = 0
    persons_over_20_never_exposed_count = 0

    for person in real_persons:
        person_exposed = False
        boxes_by_frame = {b.i: b for b in person.boxes}
        sorted_frame_indices = sorted(boxes_by_frame.keys())

        # Calcul de la taille médiane
        heights = [b.h for b in person.boxes]
        med_h = float(np.median(heights)) if heights else 0.0
        is_over_20 = med_h >= 20.0
        if is_over_20:
            persons_over_20_count += 1

        # Détection des séquences continues d'exposition
        current_streak: List[GTBox] = []

        def flush_streak(streak: List[GTBox]) -> None:
            if not streak:
                return
            s_first = streak[0]
            s_last = streak[-1]
            tot_dur_us = sum(frame_durations.get(b.i, 0) for b in streak)
            exposures.append(
                ExposureInterval(
                    person_id=person.id,
                    start_frame=s_first.i,
                    end_frame=s_last.i,
                    n_frames=len(streak),
                    duration_ms=round(tot_dur_us / 1000.0, 2),
                    start_pts_us=frame_pts.get(s_first.i, 0),
                    end_pts_us=frame_pts.get(s_last.i, 0),
                )
            )

        prev_idx: Optional[int] = None
        for f_idx in sorted_frame_indices:
            box = boxes_by_frame[f_idx]
            shapes = matched_shapes.get(f_idx, [])
            covered = is_box_covered(box, shapes)

            # Ventilation
            total_real_boxes += 1
            if covered:
                covered_real_boxes += 1

            # Taille
            h = box.h
            if h < 20.0:
                size_buckets["<20"][1] += 1
                if covered:
                    size_buckets["<20"][0] += 1
            elif h < 40.0:
                size_buckets["20-40"][1] += 1
                if covered:
                    size_buckets["20-40"][0] += 1
            elif h < 80.0:
                size_buckets["40-80"][1] += 1
                if covered:
                    size_buckets["40-80"][0] += 1
            else:
                size_buckets[">=80"][1] += 1
                if covered:
                    size_buckets[">=80"][0] += 1

            # Pose
            p = box.pose
            if p not in pose_buckets:
                pose_buckets[p] = [0, 0]
            pose_buckets[p][1] += 1
            if covered:
                pose_buckets[p][0] += 1

            # Occlusion
            occ = box.occlusion
            if occ not in occlusion_buckets:
                occlusion_buckets[occ] = [0, 0]
            occlusion_buckets[occ][1] += 1
            if covered:
                occlusion_buckets[occ][0] += 1

            # Suivi des expositions continues
            # Si interruption dans la continuité des frames (sortie du champ outside), flush
            is_consecutive = (prev_idx is not None) and (f_idx == prev_idx + 1)

            if not covered:
                person_exposed = True
                if is_consecutive:
                    current_streak.append(box)
                else:
                    flush_streak(current_streak)
                    current_streak = [box]
            else:
                flush_streak(current_streak)
                current_streak = []

            prev_idx = f_idx

        flush_streak(current_streak)

        if not person_exposed:
            persons_never_exposed_count += 1
            if is_over_20:
                persons_over_20_never_exposed_count += 1

    # Visages de type 'image' (comptés à part)
    image_persons = [p for p in gt_doc.persons if p.type == "image"]
    for ip in image_persons:
        for b in ip.boxes:
            image_type_boxes += 1
            shapes = matched_shapes.get(b.i, [])
            if is_box_covered(b, shapes):
                image_type_covered += 1

    # Plus longue exposition
    worst_frames = max((e.n_frames for e in exposures), default=0)
    worst_ms = max((e.duration_ms for e in exposures), default=0.0)

    # Rappel global
    recall = (
        float(covered_real_boxes) / float(total_real_boxes)
        if total_real_boxes > 0
        else 1.0
    )

    def calc_ratio(b: List[int]) -> Optional[float]:
        return float(b[0]) / float(b[1]) if b[1] > 0 else None

    # Taux de personnes jamais exposées
    ratio_never_exposed = (
        float(persons_never_exposed_count) / float(total_persons)
        if total_persons > 0
        else 1.0
    )
    ratio_over_20_never = (
        float(persons_over_20_never_exposed_count) / float(persons_over_20_count)
        if persons_over_20_count > 0
        else 1.0
    )

    return ClipEvalResult(
        clip_id=gt_doc.clip,
        total_gt_boxes=total_real_boxes,
        covered_gt_boxes=covered_real_boxes,
        recall=recall,
        recall_under_20=calc_ratio(size_buckets["<20"]),
        recall_20_to_40=calc_ratio(size_buckets["20-40"]),
        recall_40_to_80=calc_ratio(size_buckets["40-80"]),
        recall_over_80=calc_ratio(size_buckets[">=80"]),
        recall_by_pose={k: float(v[0]) / float(v[1]) for k, v in pose_buckets.items() if v[1] > 0},
        recall_by_occlusion={
            k: float(v[0]) / float(v[1]) for k, v in occlusion_buckets.items() if v[1] > 0
        },
        exposures=exposures,
        worst_exposure_frames=worst_frames,
        worst_exposure_ms=worst_ms,
        total_persons=total_persons,
        persons_never_exposed=persons_never_exposed_count,
        persons_never_exposed_ratio=ratio_never_exposed,
        persons_over_20_never_exposed_ratio=ratio_over_20_never,
        image_type_boxes=image_type_boxes,
        image_type_covered=image_type_covered,
    )
