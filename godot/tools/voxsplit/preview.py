"""Previsualizaciones ortográficas del volumen segmentado, con Pillow (§7.3 de `docs/05`).

Dibuja tres proyecciones —frontal, lateral y superior— del modelo ya asignado a partes,
**coloreando cada parte con un color determinista** derivado de un hash SHA-1 de su `id`
(nunca `hash()`, que está aleatorizado por proceso) y `_unassigned` en **magenta puro
(255, 0, 255)**. Una leyenda lateral lista `id`, color y número de voxels.

Es la herramienta de trabajo para ajustar las cajas de `parts.json`.
"""

from __future__ import annotations

import colorsys
import hashlib
from pathlib import Path

from .parts import UNASSIGNED, PartsSpec

__all__ = ["render", "part_color", "VIEWS"]

#: Las tres vistas: nombre de archivo, ejes de pantalla y eje de profundidad (en Godot).
#: ``(nombre, eje_u, signo_u, eje_v, signo_v, eje_profundidad, signo_profundidad)``.
#: `v` crece hacia abajo en la imagen, por eso los signos negativos en la altura.
VIEWS = (
    ("front", 0, 1.0, 1, -1.0, 2, 1.0),
    ("side", 2, 1.0, 1, -1.0, 0, 1.0),
    ("top", 0, 1.0, 2, 1.0, 1, -1.0),
)

#: Magenta puro reservado para `_unassigned` (§5.2).
UNASSIGNED_COLOR = (255, 0, 255)

_BACKGROUND = (22, 24, 28)
_GRID = (38, 42, 48)
_TEXT = (214, 218, 224)
_MUTED = (140, 146, 154)


def part_color(part_id: str) -> tuple[int, int, int]:
    """Color determinista de una parte, derivado de SHA-1 de su `id`."""
    if part_id == UNASSIGNED:
        return UNASSIGNED_COLOR
    digest = hashlib.sha1(part_id.encode("utf-8")).digest()
    hue = int.from_bytes(digest[0:4], "big") / 2 ** 32
    saturation = 0.45 + (digest[4] / 255.0) * 0.40
    value = 0.62 + (digest[5] / 255.0) * 0.33
    r, g, b = colorsys.hsv_to_rgb(hue, saturation, value)
    return (int(r * 255), int(g * 255), int(b * 255))


def _shade(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(c * factor))) for c in color)  # type: ignore[return-value]


def render(model, assignment: dict[str, dict[tuple[int, int, int], int]],
           spec: PartsSpec, out_dir: str | Path, *, scale: int = 10) -> list[Path]:
    """Escribe `preview_front.png`, `preview_side.png` y `preview_top.png` en `out_dir` (§12).

    Args:
        model: el `VoxModel` de origen (solo se usa para el tamaño de la retícula).
        assignment: ``{part_id: {voxel: índice}}`` de `parts.assign`.
        spec: el `parts.json` validado, para convertir a metros con el `axis_map`.
        out_dir: carpeta de salida; se crea si hace falta.
        scale: píxeles por voxel.

    Returns:
        Las rutas de los tres PNG escritos.
    """
    from PIL import Image, ImageDraw, ImageFont

    directory = Path(out_dir)
    directory.mkdir(parents=True, exist_ok=True)
    # Los PNG de trabajo no deben importarse en Godot: `.gdignore` en la carpeta de salida
    # (y en `previews/` si es su padre) hace que el editor se salte todo el subárbol.
    for folder in (directory, directory.parent):
        if folder is directory or folder.name == "previews":
            marker = folder / ".gdignore"
            if not marker.exists():
                marker.write_bytes(b"")
    font = ImageFont.load_default()

    ordered_ids = [p.id for p in spec.parts]
    if assignment.get(UNASSIGNED):
        ordered_ids.append(UNASSIGNED)
    colors = {pid: part_color(pid) for pid in ordered_ids}

    # Centro de cada voxel en metros (espacio de Godot), una sola vez.
    points: list[tuple[tuple[float, float, float], str]] = []
    for part_id in ordered_ids:
        for coord in sorted(assignment.get(part_id, {})):
            points.append((spec.to_meters(coord), part_id))
    if not points:
        raise ValueError("no hay voxels asignados que dibujar")

    step = spec.voxel_size
    written: list[Path] = []
    for name, u_axis, u_sign, v_axis, v_sign, d_axis, d_sign in VIEWS:
        us = [p[0][u_axis] * u_sign for p in points]
        vs = [p[0][v_axis] * v_sign for p in points]
        u_min, u_max = min(us) - step / 2, max(us) + step / 2
        v_min, v_max = min(vs) - step / 2, max(vs) + step / 2
        pixels_per_meter = scale / step
        margin = 18
        view_w = int(round((u_max - u_min) * pixels_per_meter)) + margin * 2
        view_h = int(round((v_max - v_min) * pixels_per_meter)) + margin * 2

        legend_w = 250
        legend_h = 34 + len(ordered_ids) * 13 + 14
        width = view_w + legend_w
        height = max(view_h, legend_h)

        image = Image.new("RGB", (width, height), _BACKGROUND)
        draw = ImageDraw.Draw(image)

        # Retícula cada 10 voxels y línea del suelo.
        for i in range(0, int((u_max - u_min) / step) + 1, 10):
            x = margin + int(round(i * scale))
            draw.line([(x, margin), (x, view_h - margin)], fill=_GRID)
        for i in range(0, int((v_max - v_min) / step) + 1, 10):
            y = margin + int(round(i * scale))
            draw.line([(margin, y), (view_w - margin, y)], fill=_GRID)

        depths = [p[0][d_axis] * d_sign for p in points]
        d_min, d_max = min(depths), max(depths)
        span = (d_max - d_min) or 1.0
        order = sorted(range(len(points)), key=lambda i: -depths[i])
        for i in order:
            centre, part_id = points[i]
            u = centre[u_axis] * u_sign
            v = centre[v_axis] * v_sign
            x0 = margin + (u - step / 2 - u_min) * pixels_per_meter
            y0 = margin + (v - step / 2 - v_min) * pixels_per_meter
            factor = 0.62 + 0.38 * (1.0 - (depths[i] - d_min) / span)
            draw.rectangle(
                [round(x0), round(y0), round(x0 + scale) - 1, round(y0 + scale) - 1],
                fill=_shade(colors[part_id], factor))

        title = {"front": "FRONTAL (-Z)", "side": "LATERAL (+X)", "top": "SUPERIOR (+Y)"}[name]
        draw.text((6, 4), f"{spec.name} · {title}", fill=_TEXT, font=font)

        x = view_w + 12
        draw.text((x, 8), f"{len(points)} voxels · {len(ordered_ids)} partes",
                  fill=_TEXT, font=font)
        draw.text((x, 21), f"1 voxel = {spec.voxel_size} m", fill=_MUTED, font=font)
        y = 40
        for part_id in ordered_ids:
            count = len(assignment.get(part_id, {}))
            draw.rectangle([x, y + 1, x + 9, y + 10], fill=colors[part_id])
            label = f"{part_id}  {count}"
            draw.text((x + 14, y), label, fill=_TEXT if count else _MUTED, font=font)
            y += 13

        path = directory / f"preview_{name}.png"
        image.save(path, format="PNG", optimize=True)
        written.append(path)
    return written
