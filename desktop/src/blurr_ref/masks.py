"""Modèle et manipulation des masques (masks.json v0).

Prend en charge les formes 'rect' et 'ellipse', l'appariement temporel
et la sérialisation conforme au schéma blurr-masks/0.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Union


@dataclass
class RectShape:
    x: float
    y: float
    w: float
    h: float
    kind: Literal["rect"] = "rect"

    def to_dict(self) -> Dict[str, Any]:
        return {"kind": "rect", "x": self.x, "y": self.y, "w": self.w, "h": self.h}

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> RectShape:
        return cls(x=float(d["x"]), y=float(d["y"]), w=float(d["w"]), h=float(d["h"]))


@dataclass
class EllipseShape:
    cx: float
    cy: float
    rx: float
    ry: float
    kind: Literal["ellipse"] = "ellipse"

    def to_dict(self) -> Dict[str, Any]:
        return {"kind": "ellipse", "cx": self.cx, "cy": self.cy, "rx": self.rx, "ry": self.ry}

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> EllipseShape:
        return cls(cx=float(d["cx"]), cy=float(d["cy"]), rx=float(d["rx"]), ry=float(d["ry"]))


ShapeType = Union[RectShape, EllipseShape]


@dataclass
class MaskFrame:
    pts_us: int
    shapes: List[ShapeType] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "pts_us": self.pts_us,
            "shapes": [s.to_dict() for s in self.shapes],
        }

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> MaskFrame:
        shapes: List[ShapeType] = []
        for s in d.get("shapes", []):
            kind = s.get("kind", "rect")
            if kind == "ellipse":
                shapes.append(EllipseShape.from_dict(s))
            elif kind == "rect":
                shapes.append(RectShape.from_dict(s))
            else:
                raise ValueError(f"Forme de masque inconnue: {kind}")
        return cls(pts_us=int(d["pts_us"]), shapes=shapes)


@dataclass
class MasksDoc:
    schema: str = "blurr-masks/0"
    clip: str = ""
    method: str = ""
    params: Dict[str, Any] = field(default_factory=dict)
    pts_origin: str = "container"
    frames: List[MaskFrame] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema": self.schema,
            "clip": self.clip,
            "method": self.method,
            "params": self.params,
            "pts_origin": self.pts_origin,
            "frames": [f.to_dict() for f in self.frames],
        }

    def save(self, path: Path | str) -> None:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)

    @classmethod
    def load(cls, path: Path | str) -> MasksDoc:
        p = Path(path)
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
        frames = [MaskFrame.from_dict(f) for f in data.get("frames", [])]
        return cls(
            schema=data.get("schema", "blurr-masks/0"),
            clip=data.get("clip", ""),
            method=data.get("method", ""),
            params=data.get("params", {}),
            pts_origin=data.get("pts_origin", "container"),
            frames=frames,
        )
