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

**Armado a mano, no de fábrica** (WP-25, `docs/narrativa/narrativa.md` §2 «El taller»
y §4 «El dron»). En el taller, cuando un dron cae sale otro, y el que sale es un poco
peor que el anterior. La paleta lo dice sin una línea de texto:

* el chasis es gris claro con **tres grises**: el de la pieza, el de las zonas
  gastadas y el de los rayones y las quemaduras;
* el brazo del motor 1 es **rojo** y el del motor 3 es **negro** —repuestos que no
  combinan—; los otros dos siguen en el gris del chasis;
* el motor 2 va sujeto con una vuelta de **cinta gris**;
* la batería lleva un **parche verde** (una celda de otra tanda) y su propia cinta;
* el LED trasero es **ámbar** `#FFB020`, la voz propia de `docs/13`: nada nuestro es
  cian;
* las hélices son de **dos tonos**: dos palas claras (1 y 3) y dos oscuras (2 y 4),
  con sus discos de desenfoque al mismo tono.

La silueta suma once voxels de detalle —antena de vídeo, cuatro tornillos salientes y
una férula atornillada sobre el brazo negro—, todos **dentro** del bbox anterior: la
altura total sigue siendo 0.08 m y la huella 0.30 × 0.30 m.

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

# Índices de paleta (1-based). Los nueve primeros conservan su número de WP-12a para
# que el diff del sidecar se lea de un vistazo, aunque tres de ellos cambiaron de
# color (chasis, LED y el 7, que pasó de naranja de catálogo a brazo rojo suelto).
C_FRAME = 1        # gris claro del chasis: placa y brazos de serie
C_MOTOR = 2        # negro de las campanas de motor y de la antena
C_PROP = 3         # pala clara (hélices 1 y 3)
C_CAMERA = 4       # cuerpo de la cámara
C_BATTERY = 5      # batería
C_LED = 6          # LED trasero ámbar (emisivo)
C_ARM_RED = 7      # brazo de repuesto rojo (motor 1)
C_BLUR = 8         # disco de hélice claro (motores 1 y 3)
C_LENS = 9         # lente de la cámara
C_FRAME_WORN = 10  # gris medio: zonas gastadas del chasis y la férula del brazo negro
C_SCUFF = 11       # gris oscuro: rayones y quemaduras
C_ARM_BLACK = 12   # brazo de repuesto negro (motor 3)
C_TAPE = 13        # cinta gris: vuelta del motor 2 y correa de la batería
C_PATCH = 14       # parche de la batería: una celda de otra tanda
C_PROP_DARK = 15   # pala oscura (hélices 2 y 4)
C_BLUR_DARK = 16   # disco de hélice oscuro (motores 2 y 4)
C_SCREW = 17       # tornillos y remaches de latón

_COLORS = {
    C_FRAME: (152, 156, 160, 255),
    C_MOTOR: (26, 26, 30, 255),
    C_PROP: (208, 212, 216, 255),
    C_CAMERA: (58, 60, 66, 255),
    C_BATTERY: (30, 64, 112, 255),
    C_LED: (255, 176, 32, 255),
    C_ARM_RED: (170, 48, 40, 255),
    C_BLUR: (168, 172, 178, 255),
    C_LENS: (18, 22, 34, 255),
    C_FRAME_WORN: (112, 116, 120, 255),
    C_SCUFF: (74, 76, 80, 255),
    C_ARM_BLACK: (34, 34, 38, 255),
    C_TAPE: (134, 132, 126, 255),
    C_PATCH: (62, 104, 72, 255),
    C_PROP_DARK: (62, 64, 70, 255),
    C_BLUR_DARK: (96, 100, 106, 255),
    C_SCREW: (198, 172, 104, 255),
}

#: Brazos de repuesto que no combinan: ``{motor_index: índice de paleta}``. Los motores
#: que no figuran acá llevan el gris del chasis. Están en diagonal a propósito: no es
#: una decoración simétrica, es lo que había en la caja.
ARM_COLOURS = {1: C_ARM_RED, 3: C_ARM_BLACK}

#: Al motor 2 le falta un tornillo y va sujeto con una vuelta de cinta.
TAPED_MOTOR = 2

#: Tono de cada hélice: dos palas claras y dos oscuras, porque el juego no repone de a
#: cuatro. `prop_disk_N` copia el tono de su `prop_N` para que el desenfoque no mienta.
PROP_COLOURS = {1: C_PROP, 2: C_PROP_DARK, 3: C_PROP, 4: C_PROP_DARK}
DISK_COLOURS = {1: C_BLUR, 2: C_BLUR_DARK, 3: C_BLUR, 4: C_BLUR_DARK}

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


def _arm_block(cx: int, cy: int, k: int) -> Box:
    """Bloque `k` del brazo diagonal hacia `(cx, cy)`: 2×2 en planta, 2 de alto."""
    x0 = 14 + (1 if cx > CENTRE else -1) * k
    y0 = 14 + (1 if cy > CENTRE else -1) * k
    return (min(x0, x0 + 1), min(y0, y0 + 1), 4,
            max(x0, x0 + 1), max(y0, y0 + 1), 5)


def _arm_boxes(cx: int, cy: int) -> list[Box]:
    """Brazo diagonal en X: bloques de 2×2 que van del centro de la placa al motor."""
    return [_arm_block(cx, cy, k) for k in range(9)]


#: Placa central del chasis.
_PLATE_BOX: Box = (11, 11, 4, 18, 18, 5)

#: Antena de vídeo: mástil de 3 voxels apoyado en el borde trasero de la placa. Es el
#: primero de los detalles de silueta de WP-25 y no toca el techo del modelo (z = 9).
_ANTENNA_BOXES: list[Box] = [(16, 11, 6, 16, 11, 8)]

#: Tornillos que sobresalen: las cuatro esquinas de la placa más los dos remaches que
#: sujetan la férula del brazo negro.
_SCREW_BOXES: list[Box] = [
    (11, 11, 6, 11, 11, 6),
    (11, 18, 6, 11, 18, 6),
    (18, 11, 6, 18, 11, 6),
    (18, 18, 6, 18, 18, 6),
    (20, 8, 6, 20, 8, 6),
    (21, 9, 6, 21, 9, 6),
]

#: Férula: chapa de 2×2 atornillada sobre el brazo negro, donde se partió.
_SPLINT_BOXES: list[Box] = [(20, 8, 6, 21, 9, 6)]


def _frame_boxes() -> list[Box]:
    """Placa central, los cuatro brazos y el detalle atornillado a mano."""
    boxes: list[Box] = [_PLATE_BOX]
    for index in sorted(MOTORS):
        cx, cy, _spin = MOTORS[index]
        boxes.extend(_arm_boxes(cx, cy))
    boxes.extend(_ANTENNA_BOXES)
    boxes.extend(_SPLINT_BOXES)
    boxes.extend(_SCREW_BOXES)
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

#: Parche de la batería: una celda de otra tanda, verde en vez de azul.
_BATTERY_PATCH_BOXES: list[Box] = [(12, 12, 2, 13, 14, 3)]

#: Correa de cinta que la sostiene contra la placa.
_BATTERY_TAPE_BOXES: list[Box] = [(12, 16, 2, 17, 16, 3)]

#: Zonas gastadas del chasis (gris medio). Se recortan contra las celdas reales del
#: `frame`, así que escribirlas de más no ensucia otras partes.
_FRAME_WORN_BOXES: list[Box] = [
    (11, 15, 5, 13, 18, 5),    # esquina delantera-izquierda de la placa, lijada
    (9, 9, 4, 11, 11, 5),      # arranque del brazo trasero-izquierdo, rozado
    (16, 12, 4, 18, 13, 4),    # panza de la placa, apoyada mil veces en la mesa
]

#: Rayones y quemaduras del chasis (gris oscuro).
_FRAME_SCUFF_BOXES: list[Box] = [
    (12, 13, 5, 16, 13, 5),    # rayón recto sobre la placa
    (14, 11, 5, 15, 12, 5),    # quemadura junto al LED
    (17, 16, 5, 18, 18, 5),    # esquina trasera-derecha, raspada
    (12, 12, 4, 12, 16, 4),    # rozadura larga en la panza
    (8, 20, 5, 9, 21, 5),      # el brazo rojo tampoco vino nuevo
]


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


def _arm_paint() -> dict[tuple[int, int, int], int]:
    """Celdas de los dos brazos de repuesto, desde que salen de la placa hasta el motor.

    Los bloques 0–3 quedan dentro de la placa central, así que se descartan: el color
    del repuesto arranca justo en el borde, que es donde se ve la junta.
    """
    plate = _cells([_PLATE_BOX])
    out: dict[tuple[int, int, int], int] = {}
    for index, colour in ARM_COLOURS.items():
        cx, cy, _spin = MOTORS[index]
        for k in range(4, 9):
            for cell in _cells([_arm_block(cx, cy, k)]):
                if cell not in plate:
                    out[cell] = colour
    return out


def _frame_paint() -> dict[tuple[int, int, int], int]:
    """Pintura del chasis: brazos sueltos, manchas, rayones y detalle atornillado.

    El orden es deliberado: primero los repuestos, después el desgaste (que también cae
    sobre el brazo rojo) y al final la antena, la férula y los tornillos, que son piezas
    puestas encima y no se rayan.
    """
    frame = _cells(_frame_boxes())
    paint: dict[tuple[int, int, int], int] = _arm_paint()
    for boxes, colour in ((_FRAME_WORN_BOXES, C_FRAME_WORN),
                          (_FRAME_SCUFF_BOXES, C_SCUFF)):
        for cell in _cells(boxes):
            if cell in frame:
                paint[cell] = colour
    for cell in _cells(_ANTENNA_BOXES):
        paint[cell] = C_MOTOR
    for cell in _cells(_SPLINT_BOXES):
        paint[cell] = C_FRAME_WORN
    for cell in _cells(_SCREW_BOXES):
        paint[cell] = C_SCREW
    return paint


def _battery_paint() -> dict[tuple[int, int, int], int]:
    """Parche de otra tanda y correa de cinta sobre la batería."""
    paint: dict[tuple[int, int, int], int] = {}
    for cell in _cells(_BATTERY_PATCH_BOXES):
        paint[cell] = C_PATCH
    for cell in _cells(_BATTERY_TAPE_BOXES):
        paint[cell] = C_TAPE
    return paint


def _tape_paint(cx: int, cy: int) -> dict[tuple[int, int, int], int]:
    """Vuelta de cinta alrededor de la campana del motor, con el extremo suelto arriba.

    La vuelta es el perímetro del disco de 5×5 en la capa central (z = 6); el extremo
    suelto son los tres voxels que cruzan la tapa (z = 7).
    """
    paint: dict[tuple[int, int, int], int] = {}
    for x, y, z in _cells(_motor_boxes(cx, cy)):
        if z == 6 and max(abs(x - cx), abs(y - cy)) == 2:
            paint[(x, y, z)] = C_TAPE
    for cell in _cells([(cx - 1, cy, 7, cx + 1, cy, 7)]):
        paint[cell] = C_TAPE
    return paint


def _base_colour(part_id: str) -> int:
    """Índice de paleta que lleva una parte cuando ninguna capa de pintura la tapa."""
    if part_id.startswith("prop_disk_"):
        return DISK_COLOURS[int(part_id.rsplit("_", 1)[1])]
    if part_id.startswith("prop_"):
        return PROP_COLOURS[int(part_id.rsplit("_", 1)[1])]
    if part_id.startswith("motor_"):
        return C_MOTOR
    return {"led": C_LED, "camera": C_CAMERA,
            "battery": C_BATTERY, "frame": C_FRAME}[part_id]


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

    # Una capa de pintura **por parte**: así una celda que el reparto le adjudica al
    # motor (los brazos se meten bajo la campana) nunca se lleva el color del chasis.
    taped_x, taped_y, _taped_spin = MOTORS[TAPED_MOTOR]
    paint: dict[str, dict[tuple[int, int, int], int]] = {
        "frame": _frame_paint(),
        "battery": _battery_paint(),
        "camera": {c: C_LENS for c in _cells(_CAMERA_BOXES) if c[1] == 21},
        f"motor_{TAPED_MOTOR}": _tape_paint(taped_x, taped_y),
    }

    voxels: dict[tuple[int, int, int], int] = {}
    for entry in parts:
        part_id = entry["id"]
        base = _base_colour(part_id)
        overrides = paint.get(part_id, {})
        for cell in sorted(_cells(entry["boxes"])):
            if cell in voxels:
                continue           # la primera parte del orden se queda el voxel (§5.1)
            voxels[cell] = overrides.get(cell, base)

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
