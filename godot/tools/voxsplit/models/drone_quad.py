"""Dron voxel original del jugador, definido de forma procedural (§10 de `docs/05`).

Modelo propio: **no** se importa de ningún pack. Retícula 30×30×10 con
``voxel_size = 0.01`` (1 voxel = 1 cm) y ``origin_voxel = [15, 15, 5]``, que es la
esquina de retícula del centro geométrico (los centros de voxel caen en 14.5, que es
el 0 de metros). Los cuatro motores están en los índices ``(6, 6)``, ``(6, 23)``,
``(23, 6)`` y ``(23, 23)``: separación de 17 voxels ⇒ diagonal ``17 · √2 = 24.04 cm``.

**Numeración de motores.** Se usa la de `docs/03` §2.1, que es la que consume el
mezclador: M1 delantero-izquierdo (−x, −z) **CW**, M2 delantero-derecho **CCW**,
M3 trasero-derecho **CW**, M4 trasero-izquierdo **CCW**, con **−Z adelante**.
`docs/05` §10 enumeraba los mismos cuatro puntos en otro orden; ver el README.

Partes (16): `frame`, `motor_1..4`, `prop_1..4`, `prop_disk_1..4`, `camera`, `battery`
y `led` (la luz trasera emisiva que pide WP-12a; `docs/05` §10 contaba 15 sin ella).

Toda la geometría se expresa con **cajas inclusivas** en índices de voxel, igual que un
`parts.json` escrito a mano: el disco de hélice y los brazos en X se describen como una
unión de cajas por fila, así el sidecar sigue siendo legible y no hace falta ampliar el
esquema de §4.2.
"""

from __future__ import annotations

from typing import Iterable, Sequence

__all__ = ["build", "SIZE", "MOTORS"]

#: Dimensiones de la retícula.
SIZE = (30, 30, 10)

#: Centro geométrico en índices de voxel (mapea exactamente a 0 m con `origin_voxel`).
CENTRE = 14.5

#: Semidiagonal del brazo, en voxels: 14.5 ± 8.5 ⇒ centros en 6 y 23.
ARM = 8.5

#: ``{motor_index: (x, y, spin)}`` según `docs/03` §2.1. `spin` es +1 para CW, −1 para CCW.
#: godot.x = vox.x y godot.z = −vox.y, así que vox.y alto = adelante (−z).
MOTORS = {
    1: (6, 23, +1),    # delantero-izquierdo, CW
    2: (23, 23, -1),   # delantero-derecho, CCW
    3: (23, 6, +1),    # trasero-derecho, CW
    4: (6, 6, -1),     # trasero-izquierdo, CCW
}

# Índices de paleta (1-based).
C_FRAME = 1        # carbono gris oscuro
C_MOTOR = 2        # negro
C_PROP = 3         # gris claro
C_CAMERA = 4       # cuerpo de cámara
C_BATTERY = 5      # batería
C_LED = 6          # LED trasero (emisivo)
C_ACCENT = 7       # naranja de los brazos delanteros
C_BLUR = 8         # gris del disco de hélice
C_LENS = 9         # lente de la cámara

_COLORS = {
    C_FRAME: (48, 50, 54, 255),
    C_MOTOR: (20, 20, 22, 255),
    C_PROP: (190, 195, 200, 255),
    C_CAMERA: (58, 60, 66, 255),
    C_BATTERY: (30, 64, 112, 255),
    C_LED: (255, 48, 48, 255),
    C_ACCENT: (232, 112, 32, 255),
    C_BLUR: (150, 155, 162, 255),
    C_LENS: (18, 22, 34, 255),
}

#: Radio del disco de hélice, en voxels (13 voxels de diámetro ≈ una hélice de 5.1").
DISK_RADIUS = 6

Box = tuple[int, int, int, int, int, int]


def _cells(boxes: Iterable[Sequence[int]]) -> set[tuple[int, int, int]]:
    """Expande una lista de cajas inclusivas a su conjunto de voxels."""
    out: set[tuple[int, int, int]] = set()
    for x0, y0, z0, x1, y1, z1 in boxes:
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    out.add((x, y, z))
    return out


def _motor_boxes(cx: int, cy: int) -> list[Box]:
    """Cilindro aproximado de 5×5×3 (disco de 21 celdas por capa) centrado en `(cx, cy)`."""
    return [
        (cx - 1, cy - 2, 5, cx + 1, cy - 2, 7),
        (cx - 2, cy - 1, 5, cx + 2, cy + 1, 7),
        (cx - 1, cy + 2, 5, cx + 1, cy + 2, 7),
    ]


def _prop_boxes(cx: int, cy: int) -> list[Box]:
    """Hélice de dos palas: 12 voxels de largo en total, 2 de ancho y 1 de alto, en z = 8.

    Las dos palas son simétricas por rotación de 180° y las puntas se estrechan a 1 voxel
    para que queden **dentro** del disco de radio 6, que es el que las sustituye en alta RPM.
    """
    return [
        (cx - 6, cy, 8, cx - 5, cy, 8),
        (cx - 4, cy - 1, 8, cx - 1, cy, 8),
        (cx, cy, 8, cx, cy, 8),
        (cx + 1, cy, 8, cx + 4, cy + 1, 8),
        (cx + 5, cy, 8, cx + 6, cy, 8),
    ]


def _disk_boxes(cx: int, cy: int) -> list[Box]:
    """Disco voxelizado de radio 6 y 1 voxel de alto, en z = 9, como unión de filas."""
    limit = DISK_RADIUS ** 2 + 0.25
    spans: list[tuple[int, int]] = []
    for dy in range(-DISK_RADIUS, DISK_RADIUS + 1):
        reach = 0
        while (reach + 1) ** 2 + dy * dy <= limit:
            reach += 1
        spans.append((dy, reach))
    boxes: list[Box] = []
    start = 0
    while start < len(spans):
        end = start
        while end + 1 < len(spans) and spans[end + 1][1] == spans[start][1]:
            end += 1
        reach = spans[start][1]
        boxes.append((cx - reach, cy + spans[start][0], 9,
                      cx + reach, cy + spans[end][0], 9))
        start = end + 1
    return boxes


def _arm_boxes(cx: int, cy: int) -> list[Box]:
    """Brazo diagonal en X: bloques de 2×2 que van del centro de la placa al motor."""
    step_x = 1 if cx > CENTRE else -1
    step_y = 1 if cy > CENTRE else -1
    boxes: list[Box] = []
    for k in range(9):
        x0 = 14 + step_x * k
        y0 = 14 + step_y * k
        boxes.append((min(x0, x0 + 1), min(y0, y0 + 1), 4,
                      max(x0, x0 + 1), max(y0, y0 + 1), 5))
    return boxes


def _frame_boxes() -> list[Box]:
    """Placa central más los cuatro brazos."""
    boxes: list[Box] = [(11, 11, 4, 18, 18, 5)]
    for index in sorted(MOTORS):
        cx, cy, _spin = MOTORS[index]
        boxes.extend(_arm_boxes(cx, cy))
    return boxes


#: Cajas de la cámara: cuña escalonada que se inclina hacia adelante al subir.
_CAMERA_BOXES: list[Box] = [
    (13, 19, 5, 16, 19, 5),
    (13, 19, 6, 16, 20, 6),
    (13, 19, 7, 16, 21, 7),
    (13, 20, 8, 16, 21, 8),
]

_BATTERY_BOXES: list[Box] = [(12, 12, 2, 17, 18, 3)]
_LED_BOXES: list[Box] = [(14, 10, 4, 15, 10, 5)]


def _part(part_id: str, parent: str | None, boxes: list[Box], pivot: Sequence[float],
          **extra) -> dict:
    entry: dict = {
        "id": part_id,
        "parent": parent,
        "boxes": [list(b) for b in boxes],
        "pivot": [float(c) if c != int(c) else int(c) for c in pivot],
    }
    entry.update(extra)
    return entry


def _accent_cells() -> set[tuple[int, int, int]]:
    """Celdas de los brazos delanteros que se pintan de naranja (referencia de orientación)."""
    out: set[tuple[int, int, int]] = set()
    for index in (1, 2):
        cx, cy, _spin = MOTORS[index]
        for k in range(6, 9):
            step_x = 1 if cx > CENTRE else -1
            step_y = 1 if cy > CENTRE else -1
            x0 = 14 + step_x * k
            y0 = 14 + step_y * k
            out |= _cells([(min(x0, x0 + 1), min(y0, y0 + 1), 4,
                            max(x0, x0 + 1), max(y0, y0 + 1), 5)])
    return out


def build() -> dict:
    """Devuelve el modelo del dron listo para el pipeline (§10 y §12).

    Returns:
        ``{'size': (30, 30, 10), 'voxels': {(x, y, z): palette_index},
        'parts': [...], 'palette': [(r, g, b, a), ...], 'header': {...}}``.
        `voxels` se deriva de las mismas cajas que declaran las partes, así que el
        build siempre da **0 voxels sin asignar**.
    """
    parts: list[dict] = []

    parts.append(_part("led", "frame", _LED_BOXES, [14.5, 10, 4.5],
                       flags=["cosmetic"], function="cosmetic", collision="none"))
    parts.append(_part("camera", "frame", _CAMERA_BOXES, [14.5, 20, 6],
                       function="sensor", collision="none"))
    parts.append(_part("battery", "frame", _BATTERY_BOXES, [14.5, 15, 2.5],
                       function="core", collision="none"))
    for index in sorted(MOTORS):
        cx, cy, _spin = MOTORS[index]
        parts.append(_part(f"prop_{index}", f"motor_{index}", _prop_boxes(cx, cy),
                           [cx, cy, 8], function="cosmetic", collision="none",
                           meta={"motor_index": index}))
    for index in sorted(MOTORS):
        cx, cy, _spin = MOTORS[index]
        parts.append(_part(f"prop_disk_{index}", f"motor_{index}", _disk_boxes(cx, cy),
                           [cx, cy, 9], flags=["cosmetic"], function="cosmetic",
                           collision="none", meta={"motor_index": index}))
    for index in sorted(MOTORS):
        cx, cy, spin = MOTORS[index]
        parts.append(_part(f"motor_{index}", "frame", _motor_boxes(cx, cy), [cx, cy, 6],
                           function="core", collision="none",
                           meta={"motor_index": index, "spin": spin}))
    parts.append(_part("frame", None, _frame_boxes(), [14.5, 14.5, 4.5],
                       flags=["root"], function="core", collision="none"))

    colour_of = {
        "led": C_LED, "camera": C_CAMERA, "battery": C_BATTERY, "frame": C_FRAME,
    }
    accent = _accent_cells()
    voxels: dict[tuple[int, int, int], int] = {}
    for entry in parts:
        part_id = entry["id"]
        if part_id.startswith("prop_disk_"):
            index = C_BLUR
        elif part_id.startswith("prop_"):
            index = C_PROP
        elif part_id.startswith("motor_"):
            index = C_MOTOR
        else:
            index = colour_of[part_id]
        for cell in sorted(_cells(entry["boxes"])):
            if cell in voxels:
                continue           # la primera parte del orden se queda el voxel (§5.1)
            value = index
            if part_id == "frame" and cell in accent:
                value = C_ACCENT
            elif part_id == "camera" and cell[1] == 21:
                value = C_LENS
            voxels[cell] = value

    palette: list[tuple[int, int, int, int]] = [(0, 0, 0, 0)] * 256
    for index, colour in _COLORS.items():
        palette[index - 1] = colour

    header = {
        "source": "models.drone_quad",
        "name": "drone_quad",
        "root_node": "DroneQuadRoot",
        "voxel_size": 0.01,
        "origin_voxel": [15, 15, 5],
        "grid_size": list(SIZE),
        "axis_map": {"x": "+x", "y": "+z", "z": "-y"},
        "palette_texture": "drone_quad_palette.png",
        "emissive_palette_indices": [C_LED],
        "emissive_strength": 2.0,
        "collision_default": "none",
        "density": 220.0,
    }
    return {
        "size": SIZE,
        "voxels": dict(sorted(voxels.items())),
        "parts": parts,
        "palette": palette,
        "header": header,
    }
