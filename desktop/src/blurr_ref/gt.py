"""Structure, sérialisation et conversion de la vérité terrain (gt.json v0).

Prend en charge :
- Le schéma blurr-gt/0
- L'import depuis l'export CVAT for video 1.1 (XML) enrichi avec frames.csv
- L'export vers CVAT XML pour la pré-annotation (L5)
"""

from __future__ import annotations

import csv
import json
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional


@dataclass
class GTFrameInfo:
    i: int
    pts_us: int
    dur_us: int

    def to_dict(self) -> Dict[str, Any]:
        return {"i": self.i, "pts_us": self.pts_us, "dur_us": self.dur_us}

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> GTFrameInfo:
        return cls(i=int(d["i"]), pts_us=int(d["pts_us"]), dur_us=int(d["dur_us"]))


@dataclass
class GTBox:
    i: int
    x: float
    y: float
    w: float
    h: float
    pose: str = "face"  # face | trois-quarts | profil
    occlusion: str = "aucune"  # aucune | partielle | forte
    keyframe: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "i": self.i,
            "x": self.x,
            "y": self.y,
            "w": self.w,
            "h": self.h,
            "pose": self.pose,
            "occlusion": self.occlusion,
            "keyframe": self.keyframe,
        }

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> GTBox:
        return cls(
            i=int(d["i"]),
            x=float(d["x"]),
            y=float(d["y"]),
            w=float(d["w"]),
            h=float(d["h"]),
            pose=str(d.get("pose", "face")),
            occlusion=str(d.get("occlusion", "aucune")),
            keyframe=bool(d.get("keyframe", False)),
        )


@dataclass
class GTPerson:
    id: int
    type: str = "réel"  # réel | image
    boxes: List[GTBox] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "type": self.type,
            "boxes": [b.to_dict() for b in self.boxes],
        }

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> GTPerson:
        return cls(
            id=int(d["id"]),
            type=str(d.get("type", "réel")),
            boxes=[GTBox.from_dict(b) for b in d.get("boxes", [])],
        )


@dataclass
class GTDoc:
    schema: str = "blurr-gt/0"
    clip: str = ""
    source_sha256: str = ""
    width: int = 1920
    height: 1080 = 1080
    pts_origin: str = "container"
    frames: List[GTFrameInfo] = field(default_factory=list)
    persons: List[GTPerson] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema": self.schema,
            "clip": self.clip,
            "source_sha256": self.source_sha256,
            "width": self.width,
            "height": self.height,
            "pts_origin": self.pts_origin,
            "frames": [f.to_dict() for f in self.frames],
            "persons": [p.to_dict() for p in self.persons],
        }

    def save(self, path: Path | str) -> None:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)

    @classmethod
    def load(cls, path: Path | str) -> GTDoc:
        p = Path(path)
        with open(p, "r", encoding="utf-8") as f:
            d = json.load(f)
        frames = [GTFrameInfo.from_dict(f) for f in d.get("frames", [])]
        persons = [GTPerson.from_dict(p) for p in d.get("persons", [])]
        return cls(
            schema=d.get("schema", "blurr-gt/0"),
            clip=d.get("clip", ""),
            source_sha256=d.get("source_sha256", ""),
            width=int(d.get("width", 1920)),
            height=int(d.get("height", 1080)),
            pts_origin=d.get("pts_origin", "container"),
            frames=frames,
            persons=persons,
        )


def load_frames_csv(path: Path | str) -> List[GTFrameInfo]:
    """Charge un fichier frames.csv (index,pts_us,duration_us)."""
    p = Path(path)
    frames: List[GTFrameInfo] = []
    with open(p, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            # support des variantes de noms de colonnes
            idx = int(row.get("index") or row.get("i") or 0)
            pts = int(row.get("pts_us") or row.get("pts") or 0)
            dur = int(row.get("duration_us") or row.get("dur_us") or row.get("dur") or 0)
            frames.append(GTFrameInfo(i=idx, pts_us=pts, dur_us=dur))
    frames.sort(key=lambda x: x.i)
    return frames


def parse_cvat_video_xml(
    xml_path: Path | str,
    frames_info: List[GTFrameInfo],
    clip_id: str = "",
    source_sha256: str = "",
    width: int = 1920,
    height: int = 1080,
) -> GTDoc:
    """Parse un export CVAT for video 1.1 XML et génère un GTDoc."""
    tree = ET.parse(str(xml_path))
    root = tree.getroot()

    # Lecture des dimensions si présentes dans les métadonnées CVAT
    size_elem = root.find(".//original_size")
    if size_elem is not None:
        w_el = size_elem.find("width")
        h_el = size_elem.find("height")
        if w_el is not None and w_el.text:
            width = int(w_el.text)
        if h_el is not None and h_el.text:
            height = int(h_el.text)

    persons: List[GTPerson] = []

    for track in root.findall("track"):
        label = track.attrib.get("label", "face")
        if label != "face":
            continue

        track_id = int(track.attrib.get("id", len(persons) + 1))
        # Attribut global / immuable type
        person_type = "réel"

        boxes: List[GTBox] = []

        for box_el in track.findall("box"):
            outside = box_el.attrib.get("outside", "0")
            if outside == "1":
                # Personne hors-champ sur cette image
                continue

            frame_idx = int(box_el.attrib.get("frame", 0))
            xtl = float(box_el.attrib.get("xtl", 0.0))
            ytl = float(box_el.attrib.get("ytl", 0.0))
            xbr = float(box_el.attrib.get("xbr", 0.0))
            ybr = float(box_el.attrib.get("ybr", 0.0))
            keyframe = box_el.attrib.get("keyframe", "0") == "1"

            w = max(0.0, xbr - xtl)
            h = max(0.0, ybr - ytl)

            pose = "face"
            occlusion = "aucune"

            for attr in box_el.findall("attribute"):
                name = attr.attrib.get("name")
                val = (attr.text or "").strip()
                if name == "pose":
                    pose = val
                elif name == "occlusion":
                    occlusion = val
                elif name == "type":
                    person_type = val

            boxes.append(
                GTBox(
                    i=frame_idx,
                    x=round(xtl, 1),
                    y=round(ytl, 1),
                    w=round(w, 1),
                    h=round(h, 1),
                    pose=pose,
                    occlusion=occlusion,
                    keyframe=keyframe,
                )
            )

        boxes.sort(key=lambda b: b.i)
        persons.append(GTPerson(id=track_id, type=person_type, boxes=boxes))

    return GTDoc(
        schema="blurr-gt/0",
        clip=clip_id,
        source_sha256=source_sha256,
        width=width,
        height=height,
        pts_origin="container",
        frames=frames_info,
        persons=persons,
    )
