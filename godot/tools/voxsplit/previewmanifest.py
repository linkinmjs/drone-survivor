"""Manifiesto de las vistas previas de `assets/preview/<pack>/` (WP-G2).

La galería de assets (`tools/asset_gallery_sources.gd::_preview_entries()`) no conoce
ningún pack: recorre `assets/preview/*/pieces_manifest.json` y arma sus filas con lo que
dice cada manifiesto. Este módulo escribe ese manifiesto a partir de los sidecars que ya
dejan los dos caminos de `voxsplit` en la carpeta:

* `<receta>.pieces.json` de `town` (`compose.build_town`), con su bloque `preview`;
* `<modelo>.parts.json` de `build`, con `metadata` y su bloque `preview` en la cabecera.

Sólo entran los sidecars que declaran `preview`: un sidecar sin ese bloque no es una
vista previa y se ignora. El manifiesto se regenera **entero** cada vez, desde todos los
sidecars de la carpeta, así que el resultado no depende del orden en que corrieron las
recetas y dos corridas seguidas dan los mismos bytes.

Forma de cada pieza (`pieces[]`, ordenadas por id):

    {"id", "scene", "source", "pack", "class", "row", "footprint": [x, z], "height",
     "tris", "placeholder", "note"?, "yaw"?, "preview_only"?, "order"?}

`scene` es la ruta `res://` del GLB (las vistas previas no llevan `.tscn` heredado: se
importan como escena estática, sin `import_script`). `yaw` es el giro en grados que la
galería aplica para mirar la pieza de frente, cuando su frente no es +Z.
`preview_only` marca lo que **no es jugable** aunque su familia lo sea (los mechas de
`Enemigos/Vista previa`): la etiqueta de la galería le suma `VISTA PREVIA`.
`order` (entero, por pieza) adelanta una pieza dentro de su carpeta: la galería ordena
por `order` (1 si falta) y después por id; el taxi lleva 0 para quedar junto al `car_a`
de referencia.
`sort` (cabecera) dice cómo ordena la galería las piezas de la carpeta: `id` o
`height` (de menor a mayor altura).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .jsonio import dumps

__all__ = ["MANIFEST_NAME", "write", "res_path"]

#: Nombre del manifiesto en cada carpeta de `assets/preview/`.
MANIFEST_NAME = "pieces_manifest.json"


def res_path(path: Path) -> str:
    """Ruta `res://` de `path`, buscando hacia arriba la carpeta con `project.godot`."""
    absolute = path.resolve()
    for parent in absolute.parents:
        if (parent / "project.godot").is_file():
            return "res://" + absolute.relative_to(parent).as_posix()
    raise ValueError(f"'{path}' no está dentro de un proyecto de Godot")


def _round(value: float) -> float:
    """Tres decimales: milímetros, que es más de lo que la etiqueta muestra."""
    return round(float(value), 3)


def _from_inventory(folder: Path, data: dict[str, Any]) -> list[dict[str, Any]]:
    """Piezas de un sidecar de `town` (`<receta>.pieces.json`)."""
    preview = data.get("preview") or {}
    overrides = preview.get("pieces") or {}
    found: list[dict[str, Any]] = []
    for piece_id, piece in sorted((data.get("pieces") or {}).items()):
        size = piece.get("size", [0.0, 0.0, 0.0])
        extra = overrides.get(piece_id) or {}
        entry: dict[str, Any] = {
            "id": piece_id,
            "scene": res_path(folder / f"{piece_id}.glb"),
            "source": str(data.get("source", "")),
            "pack": str(preview.get("pack", data.get("name", ""))),
            "class": str(extra.get("class", piece.get("kind", ""))),
            "row": str(extra.get("row", preview.get("row", ""))),
            "footprint": [_round(size[0]), _round(size[2])],
            "height": _round(size[1]),
            "tris": int(piece.get("triangles", 0)),
            "placeholder": bool(extra.get("placeholder", preview.get("placeholder", False))),
        }
        note = str(extra.get("note", ""))
        if note:
            entry["note"] = note
        if bool(extra.get("preview_only", preview.get("preview_only", False))):
            entry["preview_only"] = True
        if "order" in extra:
            entry["order"] = int(extra["order"])
        if "yaw" in extra or "yaw" in preview:
            entry["yaw"] = float(extra.get("yaw", preview.get("yaw", 0.0)))
        found.append(entry)
    return found


def _from_parts(folder: Path, name: str, data: dict[str, Any]) -> list[dict[str, Any]]:
    """La pieza de un sidecar de `build` (`<modelo>.parts.json`)."""
    preview = data.get("preview") or {}
    meta = data.get("metadata") or {}
    low = meta.get("aabb_min", [0.0, 0.0, 0.0])
    high = meta.get("aabb_max", [0.0, 0.0, 0.0])
    source = str(data.get("source", ""))
    archive = source.split("!")[0].replace("\\", "/").rsplit("/", 1)[-1]
    entry: dict[str, Any] = {
        "id": name,
        "scene": res_path(folder / f"{name}.glb"),
        "source": archive,
        "pack": str(preview.get("pack", name)),
        "class": str(preview.get("class", "")),
        "row": str(preview.get("row", "")),
        "footprint": [_round(high[0] - low[0]), _round(high[2] - low[2])],
        "height": _round(high[1] - low[1]),
        "tris": int(meta.get("triangle_count", 0)),
        "placeholder": bool(preview.get("placeholder", False)),
    }
    if preview.get("note"):
        entry["note"] = str(preview["note"])
    if bool(preview.get("preview_only", False)):
        entry["preview_only"] = True
    if "yaw" in preview:
        entry["yaw"] = float(preview["yaw"])
    return [entry]


def write(folder: str | Path) -> Path:
    """Regenera `<folder>/pieces_manifest.json` desde los sidecars de la carpeta."""
    out = Path(folder)
    pieces: list[dict[str, Any]] = []
    sort = ""
    for path in sorted(out.glob("*.json")):
        if path.name == MANIFEST_NAME:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict) or not data.get("preview"):
            continue
        sort = sort or str((data.get("preview") or {}).get("sort", ""))
        if path.name.endswith(".pieces.json"):
            pieces.extend(_from_inventory(out, data))
        elif path.name.endswith(".parts.json") and data.get("metadata"):
            pieces.extend(_from_parts(out, path.name[: -len(".parts.json")], data))
    pieces.sort(key=lambda p: p["id"])
    manifest: dict[str, Any] = {
        "comment": "Generado por voxsplit (previewmanifest.py, WP-G2). No editar a mano: "
                   "se reescribe en cada corrida de 'town' o 'build' sobre esta carpeta.",
        "sort": sort or "id",
        "pieces": pieces,
    }
    target = out / MANIFEST_NAME
    target.write_bytes(dumps(manifest).encode("utf-8"))
    return target
