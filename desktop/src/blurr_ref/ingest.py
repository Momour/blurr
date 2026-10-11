"""Ingestion vidéo, extraction des images et calcul des métadonnées (Étape 1 - L4).

Conformité avec les règles du plan :
- SHA-256 du fichier brut
- Lecture ffprobe (dimensions, rotation, cadence, HDR, audio)
- Horodatages précis (pts_us brut du conteneur en µs sans renormalisation)
- Détection de cadence variable (VFR) :
  durée max > 1.5 * médiane OU > 1% des images à > 10% de la médiane
- Extraction ffmpeg sans altération temporelle (-fps_mode passthrough)
- Génération de frames.csv (index, pts_us, duration_us)
"""

from __future__ import annotations

import csv
import hashlib
import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import numpy as np


def compute_file_sha256(file_path: Path | str) -> str:
    """Calcule l'empreinte SHA-256 d'un fichier par blocs."""
    sha = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(1024 * 1024):
            sha.update(chunk)
    return sha.hexdigest()


def is_vfr(durations_us: List[int]) -> bool:
    """Détecte si un flux est à cadence variable (VFR) selon la règle :

    durée maximale d'image > 1.5 * médiane
    OU plus de 1% des images à plus de 10% de la médiane.
    """
    if len(durations_us) < 5:
        return False

    arr = np.array(durations_us, dtype=np.float64)
    med = float(np.median(arr))
    if med <= 0:
        return False

    max_dur = float(np.max(arr))
    if max_dur > 1.5 * med:
        return True

    # Déviation > 10% de la médiane
    deviations = np.abs(arr - med) / med
    fraction_deviant = float(np.count_nonzero(deviations > 0.10)) / float(len(arr))

    return fraction_deviant > 0.01


@dataclass
class VideoProbeMetadata:
    width: int
    height: int
    rotation: int
    avg_fps: float
    time_base: str
    hdr_transfer: str
    has_audio: bool
    duration_ms: float
    first_pts_us: int
    n_frames: int


def probe_video(video_path: Path | str) -> VideoProbeMetadata:
    """Interroge ffprobe pour extraire les métadonnées techniques du flux vidéo."""
    vpath = str(video_path)
    cmd = [
        "ffprobe",
        "-v", "error",
        "-print_format", "json",
        "-show_streams",
        "-show_format",
        vpath,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    info = json.loads(res.stdout)

    video_stream = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), None)
    if not video_stream:
        raise ValueError(f"Aucun flux vidéo trouvé dans {video_path}")

    w = int(video_stream.get("width", 0))
    h = int(video_stream.get("height", 0))

    # Détection de la rotation
    rotation = 0
    # 1. Dans side_data_list
    for sd in video_stream.get("side_data_list", []):
        if "rotation" in sd:
            rotation = int(sd["rotation"])
            break
    # 2. Dans tags
    if rotation == 0:
        rot_tag = video_stream.get("tags", {}).get("rotate")
        if rot_tag:
            rotation = int(rot_tag)

    # Cadence
    avg_fps_str = video_stream.get("avg_frame_rate", "0/1")
    if "/" in avg_fps_str:
        num, den = avg_fps_str.split("/")
        avg_fps = float(num) / float(den) if float(den) != 0 else 0.0
    else:
        avg_fps = float(avg_fps_str)

    time_base = video_stream.get("time_base", "1/90000")
    color_transfer = video_stream.get("color_transfer", "")

    has_audio = any(s.get("codec_type") == "audio" for s in info.get("streams", []))

    format_info = info.get("format", {})
    dur_sec = float(format_info.get("duration", 0.0))
    duration_ms = dur_sec * 1000.0

    return VideoProbeMetadata(
        width=w,
        height=h,
        rotation=rotation,
        avg_fps=avg_fps,
        time_base=time_base,
        hdr_transfer=color_transfer,
        has_audio=has_audio,
        duration_ms=duration_ms,
        first_pts_us=0,
        n_frames=int(video_stream.get("nb_frames") or 0),
    )
