"""Tests unitaires pour la validation de la matrice de tournage (matrix.py)."""

from pathlib import Path
import pytest

from blurr_ref.matrix import (
    CLOSED_CONDITIONS,
    ClipEntry,
    check_matrix,
    load_conditions_csv,
    parse_conditions_str,
)


def test_parse_conditions_str():
    assert parse_conditions_str("") == set()
    assert parse_conditions_str("profil, rotation-90") == {"profil", "rotation-90"}
    assert parse_conditions_str("profil;nuit") == {"profil", "nuit"}
    assert parse_conditions_str("foule  petit") == {"foule", "petit"}


def test_dataset_conditions_file_validity():
    """Vérifie que le fichier réel dataset/conditions.csv du dépôt est 100% conforme."""
    # Localise conditions.csv
    repo_root = Path(__file__).resolve().parent.parent.parent
    csv_path = repo_root / "dataset" / "conditions.csv"
    assert csv_path.exists(), f"Le fichier {csv_path} est introuvable."

    entries = load_conditions_csv(csv_path)
    assert len(entries) == 27, f"Attendu 27 clips, trouvé {len(entries)}"

    report = check_matrix(entries, min_clips=24)
    assert report.is_valid, f"Erreurs dans la matrice: {report.errors}"
    assert report.total_clips == 27
    assert report.n_dev == 18
    assert report.n_reserved == 9
    assert len(report.unknown_conditions) == 0
    assert len(report.deficit_conditions_total) == 0
    assert len(report.deficit_conditions_reserved) == 0


def test_matrix_catches_unknown_condition():
    entries = [
        ClipEntry(clip_id=f"C{i:02d}", split="D", conditions={"profil"}) for i in range(1, 20)
    ]
    entries.append(ClipEntry(clip_id="C20", split="D", conditions={"condition_inconnue"}))
    entries.extend(
        [ClipEntry(clip_id=f"C{i:02d}", split="R", conditions=set(CLOSED_CONDITIONS)) for i in range(21, 26)]
    )

    report = check_matrix(entries, min_clips=24)
    assert not report.is_valid
    assert "condition_inconnue" in report.unknown_conditions


def test_matrix_catches_deficit_reserved():
    # Toutes les conditions sont présentes en D mais 'nuit' n'est jamais en R
    entries = []
    for i in range(1, 19):
        entries.append(ClipEntry(clip_id=f"C{i:02d}", split="D", conditions=set(CLOSED_CONDITIONS)))
    for i in range(19, 28):
        # En R, toutes les conditions sauf 'nuit'
        conds_r = set(CLOSED_CONDITIONS) - {"nuit"}
        entries.append(ClipEntry(clip_id=f"C{i:02d}", split="R", conditions=conds_r))

    report = check_matrix(entries, min_clips=24)
    assert not report.is_valid
    assert "nuit" in report.deficit_conditions_reserved


def test_matrix_catches_invalid_split():
    entries = [
        ClipEntry(clip_id="C01", split="X", conditions={"profil"}),
    ]
    report = check_matrix(entries, min_clips=1)
    assert not report.is_valid
    assert any("split invalide" in e for e in report.errors)
