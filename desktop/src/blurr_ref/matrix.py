"""Contrôle de la matrice clips × conditions et de la répartition D/R.

Règles de validation (Étape 1 - L3) :
- Liste fermée de 16 étiquettes de condition.
- Au moins 24 clips ingérés/définis (cible 27).
- Chaque étiquette présente dans au moins 2 clips au total.
- Chaque étiquette présente au moins une fois dans le lot réservé (R).
- Splits valides : 'D' (développement) ou 'R' (réservé).
"""

from __future__ import annotations

import csv
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Set

CLOSED_CONDITIONS: frozenset[str] = frozenset({
    "profil",
    "petit",
    "foule",
    "contre-jour",
    "nuit",
    "flou",
    "rapide",
    "occultation",
    "sortie-retour",
    "image",
    "rotation-90",
    "rotation-270",
    "hdr",
    "vfr",
    "zoom",
    "contraste",
})


@dataclass
class ClipEntry:
    clip_id: str
    split: str  # 'D' ou 'R'
    conditions: Set[str] = field(default_factory=set)
    extra_fields: Dict[str, str] = field(default_factory=dict)


@dataclass
class MatrixReport:
    total_clips: int
    n_dev: int
    n_reserved: int
    condition_counts_total: Dict[str, int]
    condition_counts_dev: Dict[str, int]
    condition_counts_reserved: Dict[str, int]
    unknown_conditions: Set[str]
    deficit_conditions_total: Set[str]  # < 2 au total
    deficit_conditions_reserved: Set[str]  # < 1 en R
    is_valid: bool
    errors: List[str]


def parse_conditions_str(raw: str) -> Set[str]:
    """Parse une chaîne de conditions séparées par des virgules, points-virgules ou espaces."""
    if not raw or not raw.strip():
        return set()
    cleaned = raw.replace(";", ",").replace(" ", ",")
    parts = [p.strip() for p in cleaned.split(",") if p.strip()]
    return set(parts)


def load_conditions_csv(path: Path | str) -> List[ClipEntry]:
    """Charge le fichier conditions.csv et retourne la liste des ClipEntry."""
    csv_path = Path(path)
    if not csv_path.exists():
        raise FileNotFoundError(f"Fichier introuvable: {csv_path}")

    entries: List[ClipEntry] = []
    with open(csv_path, mode="r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError(f"Le fichier CSV {csv_path} est vide ou invalide.")

        # Harmonisation des noms de colonnes insensibles à la casse
        field_map = {fn.strip().lower(): fn for fn in reader.fieldnames}
        clip_col = field_map.get("clip") or field_map.get("clip_id") or field_map.get("id")
        split_col = field_map.get("split") or field_map.get("lot")
        cond_col = field_map.get("conditions") or field_map.get("condition") or field_map.get("etiquettes")

        if not clip_col or not split_col or not cond_col:
            raise ValueError(
                f"Colonnes requises ('clip', 'split', 'conditions') manquantes dans {csv_path}. "
                f"Colonnes trouvées: {reader.fieldnames}"
            )

        for row in reader:
            clip_id = (row.get(clip_col) or "").strip()
            if not clip_id:
                continue
            split = (row.get(split_col) or "").strip().upper()
            conds_raw = row.get(cond_col) or ""
            conditions = parse_conditions_str(conds_raw)

            extra = {k: v for k, v in row.items() if k not in (clip_col, split_col, cond_col)}
            entries.append(ClipEntry(clip_id=clip_id, split=split, conditions=conditions, extra_fields=extra))

    return entries


def check_matrix(
    entries: List[ClipEntry],
    min_clips: int = 24,
    required_conditions: frozenset[str] = CLOSED_CONDITIONS,
) -> MatrixReport:
    """Contrôle la conformité de la matrice selon les exigences de l'étape 1."""
    errors: List[str] = []
    total_clips = len(entries)
    n_dev = sum(1 for e in entries if e.split == "D")
    n_reserved = sum(1 for e in entries if e.split == "R")

    # Vérification des splits valides
    invalid_splits = [e.clip_id for e in entries if e.split not in ("D", "R")]
    if invalid_splits:
        errors.append(f"Clips avec split invalide (doit être 'D' ou 'R'): {invalid_splits}")

    # Vérification du nombre minimal de clips
    if total_clips < min_clips:
        errors.append(
            f"Nombre insuffisant de clips: {total_clips} (minimum requis: {min_clips}, cible: 27)"
        )

    # Décompte par condition
    counts_total: Dict[str, int] = {c: 0 for c in required_conditions}
    counts_dev: Dict[str, int] = {c: 0 for c in required_conditions}
    counts_reserved: Dict[str, int] = {c: 0 for c in required_conditions}
    unknown_conditions: Set[str] = set()

    for e in entries:
        for c in e.conditions:
            if c not in required_conditions:
                unknown_conditions.add(c)
            else:
                counts_total[c] += 1
                if e.split == "D":
                    counts_dev[c] += 1
                elif e.split == "R":
                    counts_reserved[c] += 1

    if unknown_conditions:
        errors.append(
            f"Étiquettes non autorisées (hors liste fermée): {sorted(unknown_conditions)}"
        )

    deficit_total = {c for c, count in counts_total.items() if count < 2}
    if deficit_total:
        errors.append(
            f"Étiquettes apparaissant moins de 2 fois au total: {sorted(deficit_total)}"
        )

    deficit_reserved = {c for c, count in counts_reserved.items() if count < 1}
    if deficit_reserved:
        errors.append(
            f"Étiquettes absentes du lot réservé (R) (minimum 1 requis): {sorted(deficit_reserved)}"
        )

    is_valid = len(errors) == 0

    return MatrixReport(
        total_clips=total_clips,
        n_dev=n_dev,
        n_reserved=n_reserved,
        condition_counts_total=counts_total,
        condition_counts_dev=counts_dev,
        condition_counts_reserved=counts_reserved,
        unknown_conditions=unknown_conditions,
        deficit_conditions_total=deficit_total,
        deficit_conditions_reserved=deficit_reserved,
        is_valid=is_valid,
        errors=errors,
    )


def format_matrix_summary(report: MatrixReport) -> str:
    """Génère un affichage formaté de la matrice."""
    lines = [
        "=== Contrôle de la matrice clips × conditions ===",
        f"Total clips : {report.total_clips} (Développement: {report.n_dev}, Réservés: {report.n_reserved})",
        "",
        f"{'Condition':<16} | {'Total':<6} | {'D (dév)':<8} | {'R (réservé)':<12} | {'Statut'}",
        "-" * 60,
    ]

    for c in sorted(CLOSED_CONDITIONS):
        tot = report.condition_counts_total[c]
        d = report.condition_counts_dev[c]
        r = report.condition_counts_reserved[c]
        ok = (tot >= 2) and (r >= 1)
        statut = "OK" if ok else "DÉFICITAIRE"
        lines.append(f"{c:<16} | {tot:<6} | {d:<8} | {r:<12} | {statut}")

    lines.append("-" * 60)
    if report.is_valid:
        lines.append("Résultat : [SUCCÈS] La matrice est conforme aux exigences de l'étape 1.")
    else:
        lines.append("Résultat : [ÉCHEC] Erreurs détectées :")
        for err in report.errors:
            lines.append(f"  - {err}")

    return "\n".join(lines)
