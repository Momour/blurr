"""Génération des rapports d'évaluation (JSON, Markdown et worst.csv).

Produit :
- report.json
- report.md
- worst.csv (les 20 plus longues expositions)
"""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Dict, List, Optional

from blurr_ref.eval.metrics import ClipEvalResult, ExposureInterval


def export_worst_exposures_csv(
    exposures_by_clip: List[tuple[str, ExposureInterval]],
    out_path: Path | str,
    top_n: int = 20,
) -> None:
    """Exporte les top N pires expositions dans worst.csv."""
    sorted_exp = sorted(
        exposures_by_clip,
        key=lambda item: (item[1].duration_ms, item[1].n_frames),
        reverse=True,
    )[:top_n]

    p = Path(out_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "clip",
            "person_id",
            "n_frames",
            "duration_ms",
            "start_frame",
            "end_frame",
            "start_pts_us",
            "end_pts_us",
        ])
        for clip_id, exp in sorted_exp:
            writer.writerow([
                clip_id,
                exp.person_id,
                exp.n_frames,
                exp.duration_ms,
                exp.start_frame,
                exp.end_frame,
                exp.start_pts_us,
                exp.end_pts_us,
            ])


def generate_markdown_report(results: List[ClipEvalResult]) -> str:
    """Génère un rapport synthétique au format Markdown."""
    lines = [
        "# Rapport d'évaluation blurr",
        "",
        "## Résumé global",
        "",
        "| Clip | Rappel | Boîtes couvertes | Pire exposition (images) | Pire exposition (ms) | Jamais exposées |",
        "|---|---|---|---|---|---|",
    ]

    tot_boxes = sum(r.total_gt_boxes for r in results)
    tot_covered = sum(r.covered_gt_boxes for r in results)
    overall_recall = (tot_covered / tot_boxes) if tot_boxes > 0 else 1.0

    for r in results:
        pct_recall = f"{r.recall * 100:.1f} %"
        cov_str = f"{r.covered_gt_boxes} / {r.total_gt_boxes}"
        pct_never = f"{r.persons_never_exposed_ratio * 100:.1f} %"
        lines.append(
            f"| {r.clip_id} | {pct_recall} | {cov_str} | {r.worst_exposure_frames} | {r.worst_exposure_ms:.1f} ms | {pct_never} |"
        )

    lines.append("")
    lines.append(f"**Rappel global pondéré** : {overall_recall * 100:.2f} % ({tot_covered} / {tot_boxes} boîtes)")
    lines.append("")

    lines.append("## Ventilation par catégorie de taille (hauteur en px)")
    lines.append("")
    lines.append("| Clip | < 20 px | 20–40 px | 40–80 px | ≥ 80 px |")
    lines.append("|---|---|---|---|---|")
    for r in results:
        u20 = f"{r.recall_under_20 * 100:.1f} %" if r.recall_under_20 is not None else "-"
        b20_40 = f"{r.recall_20_to_40 * 100:.1f} %" if r.recall_20_to_40 is not None else "-"
        b40_80 = f"{r.recall_40_to_80 * 100:.1f} %" if r.recall_40_to_80 is not None else "-"
        o80 = f"{r.recall_over_80 * 100:.1f} %" if r.recall_over_80 is not None else "-"
        lines.append(f"| {r.clip_id} | {u20} | {b20_40} | {b40_80} | {o80} |")

    return "\n".join(lines)


def export_full_report(
    results: List[ClipEvalResult],
    out_dir: Path | str,
) -> None:
    """Exporte report.json, report.md et worst.csv dans out_dir."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    # 1. report.md
    md_content = generate_markdown_report(results)
    (out / "report.md").write_text(md_content, encoding="utf-8")

    # 2. report.json
    json_data = {
        "clips": [
            {
                "clip_id": r.clip_id,
                "total_gt_boxes": r.total_gt_boxes,
                "covered_gt_boxes": r.covered_gt_boxes,
                "recall": r.recall,
                "worst_exposure_frames": r.worst_exposure_frames,
                "worst_exposure_ms": r.worst_exposure_ms,
                "persons_never_exposed_ratio": r.persons_never_exposed_ratio,
                "persons_over_20_never_exposed_ratio": r.persons_over_20_never_exposed_ratio,
                "recall_under_20": r.recall_under_20,
                "recall_20_to_40": r.recall_20_to_40,
                "recall_40_to_80": r.recall_40_to_80,
                "recall_over_80": r.recall_over_80,
                "recall_by_pose": r.recall_by_pose,
                "recall_by_occlusion": r.recall_by_occlusion,
                "image_type_boxes": r.image_type_boxes,
                "image_type_covered": r.image_type_covered,
            }
            for r in results
        ]
    }
    with open(out / "report.json", "w", encoding="utf-8") as f:
        json.dump(json_data, f, indent=2, ensure_ascii=False)

    # 3. worst.csv
    all_exposures: List[tuple[str, ExposureInterval]] = []
    for r in results:
        for exp in r.exposures:
            all_exposures.append((r.clip_id, exp))
    export_worst_exposures_csv(all_exposures, out / "worst.csv", top_n=20)
