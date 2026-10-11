"""Interface en ligne de commande principale pour blurr-ref.

Commandes disponibles :
  blurr-ref check-matrix : contrôle de la conformité de dataset/conditions.csv
  blurr-ref ingest       : ingestion d'un clip vidéo (extraction frames, pts, SHA-256)
  blurr-ref gt           : conversion CVAT XML <-> gt.json
  blurr-ref eval         : calcul des métriques d'évaluation sur masques vs vérité terrain
  blurr-ref baseline     : exécution de référence deface (CenterFace)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from blurr_ref.eval.metrics import evaluate_clip
from blurr_ref.eval.report import export_full_report, generate_markdown_report
from blurr_ref.gt import GTDoc, load_frames_csv, parse_cvat_video_xml
from blurr_ref.masks import MasksDoc
from blurr_ref.matrix import check_matrix, format_matrix_summary, load_conditions_csv


def cmd_check_matrix(args: argparse.Namespace) -> int:
    conditions_path = Path(args.conditions)
    if not conditions_path.exists():
        candidates = [
            conditions_path,
            Path("dataset/conditions.csv"),
            Path("../dataset/conditions.csv"),
        ]
        for c in candidates:
            if c.exists():
                conditions_path = c
                break

    try:
        entries = load_conditions_csv(conditions_path)
        report = check_matrix(entries, min_clips=args.min_clips)
        print(format_matrix_summary(report))
        return 0 if report.is_valid else 1
    except Exception as exc:
        print(f"Erreur lors du contrôle de la matrice : {exc}", file=sys.stderr)
        return 2


def cmd_gt(args: argparse.Namespace) -> int:
    try:
        xml_path = Path(args.xml)
        frames_path = Path(args.frames)
        out_path = Path(args.out)

        frames_info = load_frames_csv(frames_path)
        clip_id = out_path.stem.replace(".gt", "")
        gt_doc = parse_cvat_video_xml(xml_path, frames_info=frames_info, clip_id=clip_id)
        gt_doc.save(out_path)
        print(f"Vérité terrain enregistrée : {out_path} ({len(gt_doc.persons)} pistes, {len(gt_doc.frames)} frames)")
        return 0
    except Exception as exc:
        print(f"Erreur lors de la conversion CVAT XML : {exc}", file=sys.stderr)
        return 2


def cmd_eval(args: argparse.Namespace) -> int:
    try:
        gt_path = Path(args.gt)
        masks_path = Path(args.masks)
        out_dir = Path(args.out_dir)

        gt_doc = GTDoc.load(gt_path)
        masks_doc = MasksDoc.load(masks_path)

        res = evaluate_clip(gt_doc, masks_doc, tolerance_us=args.tolerance_us)
        export_full_report([res], out_dir=out_dir)

        print(generate_markdown_report([res]))
        print(f"\nRapports générés dans {out_dir}/ (report.json, report.md, worst.csv)")
        return 0
    except Exception as exc:
        print(f"Erreur lors de l'évaluation : {exc}", file=sys.stderr)
        return 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="blurr-ref",
        description="Outillage de référence, ingestion, vérité terrain et évaluation de blurr",
    )
    subparsers = parser.add_subparsers(dest="command", help="Sous-commandes disponibles")

    # check-matrix
    parser_matrix = subparsers.add_parser(
        "check-matrix", help="Contrôle la matrice clips x conditions (conditions.csv)"
    )
    parser_matrix.add_argument(
        "--conditions",
        default="dataset/conditions.csv",
        help="Chemin vers le fichier conditions.csv",
    )
    parser_matrix.add_argument(
        "--min-clips",
        type=int,
        default=24,
        help="Nombre minimal de clips requis",
    )
    parser_matrix.set_defaults(func=cmd_check_matrix)

    # gt
    parser_gt = subparsers.add_parser(
        "gt", help="Conversion CVAT XML <-> gt.json"
    )
    parser_gt.add_argument("--xml", required=True, help="Fichier CVAT XML d'entrée")
    parser_gt.add_argument("--frames", required=True, help="Fichier frames.csv associé")
    parser_gt.add_argument("--out", required=True, help="Fichier gt.json de sortie")
    parser_gt.set_defaults(func=cmd_gt)

    # eval
    parser_eval = subparsers.add_parser(
        "eval", help="Calcul des métriques d'évaluation sur les masques"
    )
    parser_eval.add_argument("--gt", required=True, help="Fichier vérité terrain gt.json")
    parser_eval.add_argument("--masks", required=True, help="Fichier masques masks.json")
    parser_eval.add_argument(
        "--tolerance-us",
        type=int,
        default=1000,
        help="Tolérance d'appariement temporel en microsecondes (défaut: 1000 µs = 1 ms)",
    )
    parser_eval.add_argument(
        "--out-dir",
        default="runs/eval",
        help="Dossier de sortie des rapports (défaut: runs/eval)",
    )
    parser_eval.set_defaults(func=cmd_eval)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.print_help()
        return 1
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
