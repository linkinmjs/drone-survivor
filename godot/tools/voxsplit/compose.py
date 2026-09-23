"""Compositor de casas y props del pueblo de ruta, a partir del pack `nuke Free Sample`.

El pack no trae casas: trae **piezas sueltas** de una escena de MagicaVoxel (un bloque
cuadrado, un bloque angosto, dos tapas de techo, una puerta, un portón de garaje y
decoración). Este módulo las vuelve a voxelizar con `objvox`, las **apila según una
receta** (`models/nuke_town.json`) y emite un GLB por tipo y variante con el mismo
mesher greedy y el mismo escritor de GLB que el dron y el Arachnodroid.

## Las tres decisiones que hacen que esto quepa en presupuesto

1. **Familias de paleta.** Las caras del pack están *dithered*: la fachada del bloque
   cuadrado alterna los índices 69 y 70, que difieren en 4/255 — invisible — vóxel a
   vóxel. Ese ruido es lo único que impedía fusionar: el bloque entero son **70
   triángulos** si se pinta de un solo color y **34 390** con la paleta cruda. Agrupando
   los 48 índices visibles en 11 familias perceptuales (`palette_families` del JSON) el
   mismo bloque baja a **346** sin que cambie un solo píxel visible. Las familias se
   aplican **globalmente**, para que dos piezas apiladas fusionen también a través de la
   junta.

2. **Índices emisivos protegidos.** Las tres familias que enciende la máscara (`7` el
   papel, `50` el impreso y el marco, `13` el fondo de la hoja oscura) nunca se funden con
   la pared aunque estén cerca en RGB. Ojo con el nombre: el pack **no tiene ventanas de
   vidrio**; lo único claro de la fachada son los **carteles pegados** y los paneles
   enmarcados del bloque angosto. Se llaman «ventanas» porque es lo que
   `Building._apply_window_ration()` raciona. Una pieza puede desactivarlas con
   `palette_override`: el portón de garaje tiene manchas de moho del mismo verde pálido
   que el papel, y sin el override el garaje brillaría.

3. **Diezmado opcional.** Cinco piezas lo usan, por dos motivos distintos. Dos tienen una
   cota **geométrica** por encima del presupuesto —el ático `Rooftop-0` (2 166 triángulos
   a un solo color) y el montón de basura grande (1 238)— y tres son props chicos que no
   entraban en los 300 (`barrel_a`, `barrel_b`, `weeds_clump`). Se vota el color por
   bloques de *n*³ y se vuelve a expandir **sobre la misma retícula de 5 cm**, con la
   rejilla de bloques centrada sobre la pieza, de modo que sigue encajando vóxel a vóxel
   con el bloque de abajo pero con la mitad (o un tercio) de detalle. Es una decisión por
   pieza y queda escrita en el reporte.

## Receta de una casa

Una variante declara `stack` (pisos apilados en Y, centrados en XZ sobre el primero),
`roof` (tapa apoyada en el techo del último piso), `attach` (piezas **embutidas** en una
cara: la puerta ocupa el hueco de la pared en vez de sobresalir, así la huella no cambia)
y los modificadores `trim` (recorta celdas del último piso, para variar la altura) y
`mirror` (espejo en X). El conjunto se recentra en XZ y se apoya en `y = 0` al final, que
es lo que exigen `CityGrid` y `town_import_check`.

Escala: el pack está a 0,02 unidades por vóxel y se multiplica por 2,5, así que
**1 vóxel = 5 cm** y la puerta mide 2,20 m. Todo lo demás sale de ahí.
"""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Sequence

from . import VERSION
from . import glbvalidate, glbwriter, mesher, objvox
from . import parts as parts_module
from .jsonio import dumps

__all__ = ["ComposeError", "TownSpec", "PieceResult", "build_town", "load_spec"]


#: Cuánto puede sobresalir un techo de la planta, en celdas (6 × 5 cm = 0,30 m).
#: El techo plano del pack mide 3 celdas más que el bloque y el ático 5: es el alero, y
#: es intencional. Más que eso ya no es alero, es una pieza mal elegida —el techo plano
#: de 100 celdas sobre el bloque angosto de 50 sobresaldría 50 y se atrapa acá.
ROOF_EAVES = 6


class ComposeError(Exception):
    """Error en `nuke_town.json` o en la composición de una pieza."""


@dataclass
class PieceResult:
    """Lo que salió de componer y mallar una pieza."""

    piece_id: str
    kind: str                    # "house" | "prop"
    parts: list[str] = field(default_factory=list)
    voxel_count: int = 0
    triangle_count: int = 0
    source_triangles: int = 0
    size_cells: tuple[int, int, int] = (0, 0, 0)
    aabb_min: tuple[float, float, float] = (0.0, 0.0, 0.0)
    aabb_max: tuple[float, float, float] = (0.0, 0.0, 0.0)
    budget: int = 0
    glb_bytes: int = 0
    window_voxels: int = 0

    @property
    def size_metres(self) -> tuple[float, float, float]:
        """Dimensiones del AABB en metros."""
        return tuple(self.aabb_max[i] - self.aabb_min[i] for i in range(3))  # type: ignore[return-value]

    @property
    def over_budget(self) -> bool:
        """`True` si la pieza se pasó del presupuesto de triángulos de su clase."""
        return self.budget > 0 and self.triangle_count > self.budget


@dataclass
class TownSpec:
    """`models/nuke_town.json` ya leído y con las rutas resueltas."""

    raw: dict[str, Any]
    path: Path

    @property
    def name(self) -> str:
        """Nombre del conjunto; encabeza los archivos de salida."""
        return str(self.raw.get("name", "nuke_town"))

    @property
    def step(self) -> float:
        """Tamaño del vóxel en unidades del OBJ."""
        return float(self.raw.get("step", objvox.DEFAULT_STEP))

    @property
    def scale(self) -> float:
        """Factor a metros: `voxel_size = step * scale`."""
        return float(self.raw.get("scale", 2.5))

    @property
    def voxel_size(self) -> float:
        """Metros por vóxel del resultado."""
        return self.step * self.scale

    def source(self) -> str:
        """Ruta al ZIP o carpeta del pack, resuelta contra el JSON."""
        raw = str(self.raw.get("source", ""))
        if not raw:
            raise ComposeError("el spec no declara 'source'")
        candidate = Path(raw)
        if not candidate.is_absolute():
            candidate = (self.path.parent / raw).resolve()
        return str(candidate)

    def member(self, file_name: str) -> str:
        """Ruta completa de un OBJ del pack, con la forma ``archivo.zip!miembro``."""
        prefix = str(self.raw.get("member_prefix", ""))
        base = self.source()
        if base.lower().endswith(".zip"):
            return f"{base}{objvox.ZIP_SEPARATOR}{prefix}{file_name}"
        return str(Path(base) / prefix / file_name)


def load_spec(path: str | Path) -> TownSpec:
    """Lee y valida mínimamente el JSON de recetas."""
    file_path = Path(path)
    try:
        data = json.loads(file_path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ComposeError(f"no se pudo leer '{file_path}': {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ComposeError(f"'{file_path}' no es JSON válido: {exc}") from exc
    for key in ("pieces", "houses", "props", "palette_families"):
        if key not in data:
            raise ComposeError(f"'{file_path}' no declara '{key}'")
    return TownSpec(raw=data, path=file_path)


# --------------------------------------------------------------------------- #
# Paleta                                                                       #
# --------------------------------------------------------------------------- #


def build_palette_map(spec: TownSpec) -> dict[int, int]:
    """`{índice_original: índice_representante}` a partir de `palette_families`."""
    mapping: dict[int, int] = {}
    for rep_raw, members in spec.raw["palette_families"].items():
        rep = int(rep_raw)
        for member in list(members) + [rep]:
            index = int(member)
            if index in mapping and mapping[index] != rep:
                raise ComposeError(f"el índice {index} está en dos familias: "
                                   f"{mapping[index]} y {rep}")
            mapping[index] = rep
    return mapping


def write_emissive_png(path: str | Path, windows: dict[int, Sequence[int]]) -> None:
    """Máscara emisiva 256×1: negro salvo en los índices de ventana (`docs/13` §1).

    El material la usa con `emission_operator = MULTIPLY` y `emission = blanco`, así que
    el píxel **es** el color y el brillo de la ventana; todo lo demás queda a cero y no
    emite. Comparte la UV con la difusa, que es la paleta, por eso basta 256×1.
    """
    from PIL import Image

    if not windows:
        raise ComposeError("'window_indices' está vacío: la máscara emisiva saldría negra "
                           "y el pueblo no tendría un solo punto de luz")
    pixels = [(0, 0, 0, 255)] * objvox.PALETTE_WIDTH
    for index, colour in windows.items():
        slot = int(index)
        if not 1 <= slot <= objvox.PALETTE_WIDTH:
            raise ComposeError(f"'window_indices': el índice {slot} está fuera de "
                               f"1..{objvox.PALETTE_WIDTH}")
        values = [int(c) for c in colour[:3]]
        if len(values) != 3 or any(not 0 <= c <= 255 for c in values):
            raise ComposeError(f"'window_indices[{slot}]': {list(colour)} no es un RGB "
                               f"de tres componentes en 0..255")
        pixels[slot - 1] = (values[0], values[1], values[2], 255)
    image = Image.new("RGBA", (objvox.PALETTE_WIDTH, 1))
    image.putdata(pixels)
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out, format="PNG", optimize=True)


# --------------------------------------------------------------------------- #
# Piezas del pack                                                              #
# --------------------------------------------------------------------------- #


@dataclass
class Piece:
    """Una pieza del pack ya voxelizada, remapeada, recortada y normalizada."""

    id: str
    voxels: dict[tuple[int, int, int], int]
    size: tuple[int, int, int]
    source_triangles: int
    file: str
    #: Celdas donde la cáscara por normales y el relleno por inundación no coinciden.
    #: Vacío en una malla estanca; una lista no vacía significa OBJ con agujeros.
    fill_mismatches: list[str] = field(default_factory=list)
    #: Cuántas celdas recibieron dos colores distintos de dos caras diferentes.
    colour_conflicts: int = 0
    #: Cuántos desajustes de relleno admite la pieza antes de ser un fallo (`docs/05`).
    allow_fill_mismatches: int = 0

    def copy(self) -> dict[tuple[int, int, int], int]:
        """Copia de los vóxeles, para poder desplazarla sin tocar la caché."""
        return dict(self.voxels)


def _decimate(voxels: dict[tuple[int, int, int], int],
              factor: int) -> dict[tuple[int, int, int], int]:
    """Vota el color por bloques de `factor`³ y vuelve a expandir sobre la misma retícula.

    Un bloque queda lleno si al menos la mitad de sus celdas lo estaban. Así la pieza
    conserva su tamaño y su alineación con el resto del pueblo pero pierde la mitad (o un
    tercio) del detalle de superficie, que es lo que cuesta triángulos.

    La rejilla de bloques se **centra** sobre la pieza en vez de anclarse en su esquina
    mínima. Anclada, el resto de la división (`extensión % factor`) se comía siempre las
    caras +X, +Y y +Z y nunca las −: el ático perdía su alero de un lado y quedaba
    visiblemente descentrado sobre el bloque. Con el centrado el recorte se reparte entre
    las dos caras de cada eje.
    """
    if factor <= 1 or not voxels:
        return dict(voxels)
    lo = tuple(min(c[i] for c in voxels) for i in range(3))
    hi = tuple(max(c[i] for c in voxels) for i in range(3))
    # Desfase que reparte el resto entre las dos caras del eje.
    shift = tuple(((hi[i] - lo[i] + 1) % factor) // 2 for i in range(3))
    buckets: dict[tuple[int, int, int], Counter] = {}
    for cell, index in voxels.items():
        key = tuple((cell[i] - lo[i] + shift[i]) // factor for i in range(3))
        buckets.setdefault(key, Counter())[index] += 1  # type: ignore[arg-type]
    out: dict[tuple[int, int, int], int] = {}
    threshold = factor ** 3
    for key, votes in buckets.items():
        if sum(votes.values()) * 2 < threshold:
            continue
        index = votes.most_common(1)[0][0]
        for dx in range(factor):
            for dy in range(factor):
                for dz in range(factor):
                    cell = (lo[0] + key[0] * factor + dx - shift[0],
                            lo[1] + key[1] * factor + dy - shift[1],
                            lo[2] + key[2] * factor + dz - shift[2])
                    if all(lo[i] <= cell[i] <= hi[i] for i in range(3)):
                        out[cell] = index
    return out


def load_pieces(spec: TownSpec, palette_map: dict[int, int],
                *, verbose: bool = False
                ) -> tuple[dict[str, Piece], list[tuple[int, int, int, int]]]:
    """Voxeliza todas las piezas del spec. Devuelve ``({id: Piece}, paleta)``."""
    pieces: dict[str, Piece] = {}
    palette: list[tuple[int, int, int, int]] = []
    for piece_id, entry in spec.raw["pieces"].items():
        source = spec.member(str(entry["file"]))
        grid = objvox.load(source, step=spec.step)
        if grid.conflicts:
            raise ComposeError(f"'{piece_id}': {len(grid.conflicts)} celdas marcadas "
                               f"interior y exterior a la vez, p. ej. {grid.conflicts[:3]}")
        # Sin paleta no hay color: `objvox.load` se traga el fallo de lectura del PNG y
        # deja la lista vacía, y el GLB saldría con UV que no apuntan a ningún sitio.
        if len(grid.palette) != objvox.PALETTE_WIDTH:
            raise ComposeError(f"'{piece_id}': no se pudo leer la paleta de 256×1 hermana "
                               f"de '{entry['file']}' (llegaron {len(grid.palette)} colores)")
        if not palette:
            palette = list(grid.palette)
        elif list(grid.palette) != palette:
            raise ComposeError(f"'{piece_id}' trae una paleta distinta del resto del pack")

        override = {int(k): int(v) for k, v in (entry.get("palette_override") or {}).items()}
        drop = {int(i) for i in (entry.get("drop_indices") or [])}
        crop = entry.get("crop") or {}
        voxels: dict[tuple[int, int, int], int] = {}
        for cell, index in grid.voxels.items():
            if not _in_crop(cell, crop):
                continue
            rep = palette_map.get(index, index)
            rep = override.get(rep, override.get(index, rep))
            if rep in drop:
                continue
            voxels[cell] = rep
        if not voxels:
            raise ComposeError(f"'{piece_id}': no queda ningún vóxel después de 'crop' "
                               f"{crop or '{}'} y 'drop_indices' {sorted(drop)}")
        voxels = _decimate(voxels, int(entry.get("decimate", 1)))
        if not voxels:
            raise ComposeError(f"'{piece_id}': el diezmado ×{entry.get('decimate')} se llevó "
                               f"la pieza entera; es demasiado grande para su tamaño")
        voxels, size, _offset = objvox.normalize(voxels)
        pieces[piece_id] = Piece(id=piece_id, voxels=voxels, size=size,
                                 source_triangles=grid.source_triangles,
                                 file=str(entry["file"]),
                                 fill_mismatches=list(grid.fill_mismatches),
                                 colour_conflicts=len(grid.colour_conflicts),
                                 allow_fill_mismatches=int(
                                     entry.get("allow_fill_mismatches", 0)))
        if verbose:
            print(f"  pieza {piece_id:14s} {size}  vox {len(voxels):7d}  "
                  f"OBJ {grid.source_triangles:6d} tris  "
                  f"colores {sorted(set(voxels.values()))}")
    return pieces, palette


def _in_crop(cell: tuple[int, int, int], crop: dict[str, Any]) -> bool:
    """`True` si la celda sobrevive al recorte declarado (`y_min`, `y_max`, …)."""
    for i, axis in enumerate("xyz"):
        low = crop.get(f"{axis}_min")
        high = crop.get(f"{axis}_max")
        if low is not None and cell[i] < int(low):
            return False
        if high is not None and cell[i] > int(high):
            return False
    return True


# --------------------------------------------------------------------------- #
# Composición                                                                  #
# --------------------------------------------------------------------------- #


def _blit(target: dict[tuple[int, int, int], int],
          source: dict[tuple[int, int, int], int], offset: Sequence[int]) -> None:
    """Estampa `source` sobre `target` desplazada `offset` celdas; lo último gana."""
    dx, dy, dz = int(offset[0]), int(offset[1]), int(offset[2])
    for cell, index in source.items():
        target[(cell[0] + dx, cell[1] + dy, cell[2] + dz)] = index


def _centre_offset(outer: Sequence[int], inner: Sequence[int], axis: int) -> int:
    """Desplazamiento que centra `inner` dentro de `outer` en `axis`."""
    return (outer[axis] - inner[axis]) // 2


def compose_variant(spec: TownSpec, pieces: dict[str, Piece],
                    variant: dict[str, Any]) -> tuple[dict[tuple[int, int, int], int], list[str]]:
    """Ensambla una variante de casa según su receta. Devuelve ``(voxels, partes_usadas)``."""
    used: list[str] = []
    stack_ids = [str(p) for p in variant.get("stack", [])]
    if not stack_ids:
        raise ComposeError(f"la variante '{variant.get('id')}' no declara 'stack'")

    variant_id = str(variant.get("id", "?"))
    base = pieces.get(stack_ids[0])
    if base is None:
        raise ComposeError(f"la variante '{variant_id}' usa la pieza desconocida "
                           f"'{stack_ids[0]}'")
    footprint = base.size
    assembled: dict[tuple[int, int, int], int] = {}
    top = 0
    for number, piece_id in enumerate(stack_ids):
        piece = pieces.get(piece_id)
        if piece is None:
            raise ComposeError(f"'{variant_id}': pieza desconocida '{piece_id}'")
        _require_fits(variant_id, "piso", piece, footprint)
        voxels = piece.copy()
        if number == len(stack_ids) - 1:
            trim = int(variant.get("trim", 0))
            if trim > 0:
                limit = piece.size[1] - trim
                if limit < 4:
                    raise ComposeError(f"'{variant_id}': 'trim' = {trim} deja el piso en "
                                       f"{limit} celdas")
                voxels = {c: i for c, i in voxels.items() if c[1] < limit}
                if not voxels:
                    raise ComposeError(f"'{variant_id}': 'trim' = {trim} se llevó el piso "
                                       f"'{piece_id}' entero")
        height = max(c[1] for c in voxels) + 1
        _blit(assembled, voxels, (_centre_offset(footprint, piece.size, 0), top,
                                  _centre_offset(footprint, piece.size, 2)))
        used.append(piece_id)
        top += height

    for entry in variant.get("attach", []):
        _attach(spec, pieces, assembled, entry, footprint, top, used, variant)

    roof_id = variant.get("roof")
    if roof_id:
        roof = pieces.get(str(roof_id))
        if roof is None:
            raise ComposeError(f"'{variant_id}': techo desconocido '{roof_id}'")
        _require_fits(variant_id, "techo", roof, footprint, tolerance=ROOF_EAVES)
        _blit(assembled, roof.copy(), (_centre_offset(footprint, roof.size, 0), top,
                                       _centre_offset(footprint, roof.size, 2)))
        used.append(str(roof_id))

    if bool(variant.get("mirror", False)):
        assembled = objvox.mirror_x(assembled)
    if not assembled:
        raise ComposeError(f"'{variant_id}': la receta no produjo ningún vóxel")
    return assembled, used


def _require_fits(variant_id: str, role: str, piece: Piece, footprint: Sequence[int],
                  *, tolerance: int = 0) -> None:
    """Falla si `piece` no entra a lo ancho sobre `footprint`.

    Sin esta comprobación un piso o un techo más grande que la planta se centraba con un
    desplazamiento **negativo** y sobresalía por los cuatro lados sin decir nada: la
    huella declarada en `base_size` dejaba de ser la real y `CityGrid` habría plantado la
    casa encima de la vereda. `tolerance` admite el alero del techo, que sí sobresale a
    propósito (el techo plano del pack es 3 celdas más ancho que el bloque).
    """
    for axis in (0, 2):
        excess = piece.size[axis] - footprint[axis]
        if excess > tolerance:
            raise ComposeError(
                f"'{variant_id}': el {role} '{piece.id}' mide {piece.size[axis]} celdas en "
                f"{'x_z'[axis]} sobre una planta de {footprint[axis]} "
                f"(sobresale {excess}, tolerancia {tolerance})")


def _attach(spec: TownSpec, pieces: dict[str, Piece],
            assembled: dict[tuple[int, int, int], int], entry: dict[str, Any],
            footprint: Sequence[int], top: int, used: list[str],
            variant: dict[str, Any]) -> None:
    """Embute una pieza (puerta, portón) en una cara del cuerpo ya apilado.

    **Embutida, no pegada**: la pieza ocupa el hueco de la pared en vez de sobresalir, así
    la huella del conjunto sigue siendo la del bloque y `CityGrid` puede seguir usando
    `base_size` como el ancho real de la casa.
    """
    variant_id = str(variant.get("id", "?"))
    piece = pieces.get(str(entry["piece"]))
    if piece is None:
        raise ComposeError(f"'{variant_id}': pieza de fachada desconocida "
                           f"'{entry['piece']}'")
    face = str(entry.get("face", "-x"))
    if face not in ("-x", "+x", "-z", "+z"):
        raise ComposeError(f"'{variant_id}': cara inválida '{face}'")
    axis = 0 if face[1] == "x" else 2
    lateral = 2 if axis == 0 else 0
    fraction = float(entry.get("u", 0.5))
    lift = int(entry.get("v", 0))

    # La pieza se embute: tiene que entrar a lo ancho, a lo hondo y a lo alto.
    if piece.size[lateral] > footprint[lateral]:
        raise ComposeError(f"'{variant_id}': '{piece.id}' mide {piece.size[lateral]} celdas "
                           f"a lo ancho de la cara '{face}', que tiene "
                           f"{footprint[lateral]}")
    if piece.size[axis] > footprint[axis]:
        raise ComposeError(f"'{variant_id}': '{piece.id}' es más profunda "
                           f"({piece.size[axis]}) que la planta en {'x_z'[axis]} "
                           f"({footprint[axis]}); atravesaría la casa")
    offset = [0, 0, 0]
    offset[axis] = 0 if face[0] == "-" else footprint[axis] - piece.size[axis]
    span = footprint[lateral] - piece.size[lateral]
    offset[lateral] = max(0, min(span, int(round(span * fraction))))
    offset[1] = lift
    if offset[1] + piece.size[1] > top:
        raise ComposeError(f"'{variant_id}': '{piece.id}' no entra en la cara "
                           f"(necesita {offset[1] + piece.size[1]} celdas de alto, hay {top})")
    _blit(assembled, piece.copy(), offset)
    used.append(piece.id)


# --------------------------------------------------------------------------- #
# Escritura                                                                    #
# --------------------------------------------------------------------------- #


def _spec_for(voxels: dict[tuple[int, int, int], int], piece_id: str,
              voxel_size: float, palette_texture: str,
              emissive_indices: Iterable[int]) -> parts_module.PartsSpec:
    """`PartsSpec` de una pieza de una sola parte, centrada en XZ y apoyada en `y = 0`."""
    size = tuple(max(c[i] for c in voxels) + 1 for i in range(3))
    origin = objvox.origin_for(size)
    header = {
        "voxel_size": voxel_size,
        "origin_voxel": list(origin),
        "axis_map": {"x": "+x", "y": "+y", "z": "+z"},
        "palette_texture": palette_texture,
        "emissive_palette_indices": sorted(set(int(i) for i in emissive_indices)),
        "collision_default": "box",
        "grid_size": list(size),
        "root_node": f"{_pascal(piece_id)}Root",
        "parts": [{
            "id": piece_id,
            "parent": None,
            "boxes": [[0, 0, 0, size[0] - 1, size[1] - 1, size[2] - 1]],
            "pivot": list(objvox.pivot_for(origin)),
            "flags": ["root"],
        }],
    }
    return parts_module.load_dict(header, name=piece_id)


def _pascal(name: str) -> str:
    """`house_a` → `HouseA`."""
    return "".join(chunk[:1].upper() + chunk[1:] for chunk in name.split("_") if chunk)


def _emit(piece_id: str, kind: str, voxels: dict[tuple[int, int, int], int],
          spec: TownSpec, out_dir: Path, palette_texture: str, budget: int,
          source_triangles: int, used: list[str],
          window_indices: set[int]) -> PieceResult:
    """Malla, escribe y valida el GLB de una pieza compuesta."""
    if not voxels:
        raise ComposeError(f"'{piece_id}': no hay ningún vóxel que mallar")
    voxels, _size, _offset = objvox.normalize(voxels)
    parts_spec = _spec_for(voxels, piece_id, spec.voxel_size, palette_texture, ())
    part = parts_spec.parts[0]
    mesh = mesher.build_part(voxels, parts_spec, part)
    if mesher.EMISSIVE in mesh.surfaces:
        raise ComposeError(f"'{piece_id}': el mallador generó una superficie emisiva; "
                           f"las casas van con **una sola** superficie y máscara")
    info = glbwriter.write(out_dir / f"{piece_id}.glb", {part.id: mesh}, parts_spec,
                           generator=f"voxsplit {VERSION} compose")
    glbvalidate.validate_file(out_dir / f"{piece_id}.glb")
    return PieceResult(
        piece_id=piece_id,
        kind=kind,
        parts=list(used),
        voxel_count=len(voxels),
        triangle_count=info.triangle_count,
        source_triangles=source_triangles,
        size_cells=tuple(max(c[i] for c in voxels) + 1 for i in range(3)),  # type: ignore[arg-type]
        aabb_min=info.aabb_min,
        aabb_max=info.aabb_max,
        budget=budget,
        glb_bytes=info.byte_length,
        window_voxels=sum(1 for i in voxels.values() if i in window_indices),
    )


def build_town(spec_path: str | Path, out_dir: str | Path,
               *, verbose: bool = True) -> tuple[list[PieceResult], list[str], dict[str, Any]]:
    """Construye todo el pueblo. Devuelve ``(resultados, fallos, inventario)``."""
    spec = load_spec(spec_path)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    palette_map = build_palette_map(spec)
    if verbose:
        print(f"voxsplit {VERSION} · compose «{spec.name}» · vóxel {spec.voxel_size * 100:.0f} cm")
    pieces, palette = load_pieces(spec, palette_map, verbose=verbose)

    palette_texture = str(spec.raw.get("palette_texture", f"{spec.name}_palette.png"))
    glbwriter.write_palette_png(out / palette_texture, palette)
    windows = {int(k): v for k, v in (spec.raw.get("window_indices") or {}).items()}
    emissive_texture = str(spec.raw.get("emissive_texture", f"{spec.name}_emissive.png"))
    write_emissive_png(out / emissive_texture, windows)

    budgets = spec.raw.get("budgets", {})
    # Los 2 400 son los de `tools/town_import_check.gd`: `house_b` mide 2 254 con la
    # hiedra del pack intacta y el 1 500 del plan no era alcanzable a 5 cm por vóxel.
    house_budget = int(budgets.get("house", 2400))
    prop_budget = int(budgets.get("prop", 300))

    results: list[PieceResult] = []
    failures: list[str] = []
    window_set = set(windows)
    # Dos recetas con el mismo id escribirían el mismo `.glb` y la segunda pisaría a la
    # primera sin decir nada: el reporte mostraría 19 piezas y en disco habría 18.
    emitted: set[str] = set()

    def claim(piece_id: str, where: str) -> str:
        if piece_id in emitted:
            raise ComposeError(f"el id '{piece_id}' ({where}) ya se emitió: dos piezas "
                               f"escribirían el mismo '{piece_id}.glb'")
        emitted.add(piece_id)
        return piece_id

    for type_id, entry in spec.raw["houses"].items():
        for variant in entry.get("variants", []):
            variant_id = claim(str(variant.get("id") or type_id), f"houses.{type_id}")
            voxels, used = compose_variant(spec, pieces, variant)
            source = sum(pieces[p].source_triangles for p in dict.fromkeys(used))
            result = _emit(variant_id, "house", voxels, spec, out, palette_texture,
                           house_budget, source, used, window_set)
            result.parts = used
            results.append(result)

    for prop_id, entry in spec.raw["props"].items():
        piece = pieces.get(str(entry["piece"]))
        if piece is None:
            raise ComposeError(f"prop '{prop_id}' usa la pieza desconocida '{entry['piece']}'")
        voxels = piece.copy()
        if bool(entry.get("mirror", False)):
            voxels = objvox.mirror_x(voxels)
        result = _emit(claim(str(prop_id), "props"), "prop", voxels, spec, out,
                       palette_texture, prop_budget, piece.source_triangles,
                       [piece.id], window_set)
        results.append(result)

    # Mallas no estancas: la cáscara por normales y el relleno por inundación discrepan.
    # En una casa es un fallo —el volumen sale mal y la silueta con él—; en un montón de
    # basura del pack es un aviso, porque son mallas abiertas a propósito.
    house_pieces: set[str] = set()
    for result in results:
        if result.kind == "house":
            house_pieces.update(result.parts)
    for piece in pieces.values():
        count = len(piece.fill_mismatches)
        if count == 0:
            continue
        message = (f"{piece.id}: {count} celdas donde la cáscara y el relleno no coinciden "
                   f"(malla no estanca); p. ej. {piece.fill_mismatches[0]}")
        if piece.id in house_pieces and count > piece.allow_fill_mismatches:
            failures.append(f"{message} · tolerancia declarada "
                            f"{piece.allow_fill_mismatches}")
        elif verbose:
            print(f"  aviso  {message}")

    for result in results:
        if result.over_budget:
            failures.append(f"{result.piece_id}: {result.triangle_count} triángulos "
                            f"> presupuesto {result.budget}")
        centre = [(result.aabb_min[i] + result.aabb_max[i]) * 0.5 for i in range(3)]
        for i in (0, 2):
            if abs(centre[i]) > 1e-3:
                failures.append(f"{result.piece_id}: centro {'xz'[i // 2]} = {centre[i]:.4f} m")
        if abs(result.aabb_min[1]) > 1e-3:
            failures.append(f"{result.piece_id}: AABB.min.y = {result.aabb_min[1]:.4f} m")

    inventory = _inventory(spec, pieces, results, windows, palette_map,
                           palette_texture, emissive_texture)
    _write_text(out / f"{spec.name}.pieces.json", dumps(inventory))
    # `<nombre>_report.txt` y no `report.txt`: `build` escribe su propio `report.txt` en
    # `--out`, y componer el pueblo en la misma carpeta que un enemigo se lo llevaba por
    # delante sin avisar.
    _write_text(out / f"{spec.name}_report.txt",
                _report(spec, pieces, results, failures, windows, palette_map))
    if verbose:
        for result in results:
            print(f"  {result.kind:5s} {result.piece_id:16s} "
                  f"tris {result.triangle_count:5d}/{result.budget:<5d} "
                  f"vox {result.voxel_count:7d}  "
                  f"{result.size_metres[0]:5.2f} × {result.size_metres[1]:5.2f} × "
                  f"{result.size_metres[2]:5.2f} m  ventanas {result.window_voxels}")
    return results, failures, inventory


def _inventory(spec: TownSpec, pieces: dict[str, Piece], results: list[PieceResult],
               windows: dict[int, Sequence[int]], palette_map: dict[int, int],
               palette_texture: str, emissive_texture: str) -> dict[str, Any]:
    """Sidecar que consumen `town_import_check` y WP-B: medidas de cada pieza y del pack."""
    return {
        "name": spec.name,
        "voxsplit_version": VERSION,
        "source": Path(spec.source()).name,
        "step": spec.step,
        "scale": spec.scale,
        "voxel_size": spec.voxel_size,
        "palette_texture": palette_texture,
        "emissive_texture": emissive_texture,
        "window_indices": {str(k): list(v) for k, v in sorted(windows.items())},
        "palette_families": {str(rep): sorted(i for i, r in palette_map.items() if r == rep)
                             for rep in sorted(set(palette_map.values()))},
        "sources": {
            piece.id: {
                "file": piece.file,
                "cells": list(piece.size),
                "metres": [round(c * spec.voxel_size, 4) for c in piece.size],
                "voxels": len(piece.voxels),
                "obj_triangles": piece.source_triangles,
            } for piece in pieces.values()
        },
        "pieces": {
            result.piece_id: {
                "kind": result.kind,
                "parts": result.parts,
                "triangles": result.triangle_count,
                "obj_triangles": result.source_triangles,
                "budget": result.budget,
                "voxels": result.voxel_count,
                "cells": list(result.size_cells),
                "aabb_min": [round(c, 4) for c in result.aabb_min],
                "aabb_max": [round(c, 4) for c in result.aabb_max],
                "size": [round(c, 4) for c in result.size_metres],
                "window_voxels": result.window_voxels,
                "scene": f"res://city/pieces/town/{result.piece_id}.tscn"
                if result.kind == "house" else
                f"res://city/pieces/town/props/{result.piece_id}.tscn",
            } for result in results
        },
    }


def _report(spec: TownSpec, pieces: dict[str, Piece], results: list[PieceResult],
            failures: list[str], windows: dict[int, Sequence[int]],
            palette_map: dict[int, int]) -> str:
    """`report.txt`: la tabla que hace legible una regresión en el diff."""
    lines: list[str] = []
    add = lines.append
    add(f"voxsplit {VERSION} — pueblo «{spec.name}»")
    add(f"origen              : {Path(spec.source()).name}")
    add(f"paso del OBJ        : {spec.step} u · escala ×{spec.scale} · "
        f"vóxel {spec.voxel_size} m")
    add("")
    add("piezas del pack (tras familias de paleta, recorte y diezmado):")
    add(f"  {'pieza':<14} {'celdas':<16} {'metros':<22} {'vox':>8} {'OBJ tris':>9}")
    add("  " + "-" * 74)
    for piece in pieces.values():
        cells = "×".join(str(c) for c in piece.size)
        metres = " × ".join(f"{c * spec.voxel_size:.2f}" for c in piece.size)
        add(f"  {piece.id:<14} {cells:<16} {metres:<22} {len(piece.voxels):>8} "
            f"{piece.source_triangles:>9}")
    add("")
    add("diagnóstico de la voxelización (cáscara por normales frente a relleno por inundación):")
    add("  una pieza de casa con más desajustes que su 'allow_fill_mismatches' es un fallo;")
    add("  en un prop es sólo un aviso, porque los montones del pack son mallas abiertas.")
    clean = True
    for piece in pieces.values():
        if not piece.fill_mismatches and piece.colour_conflicts == 0:
            continue
        clean = False
        add(f"  {piece.id}: {len(piece.fill_mismatches)} celdas de desajuste de relleno "
            f"(tolerancia {piece.allow_fill_mismatches}), {piece.colour_conflicts} de color")
        for line in piece.fill_mismatches[:8]:
            add(f"      {line}")
        if len(piece.fill_mismatches) > 8:
            add(f"      … y {len(piece.fill_mismatches) - 8} más")
    if clean:
        add("  sin desajustes: las piezas son estancas y ninguna celda recibió dos colores")
    add("")
    add("piezas compuestas:")
    add(f"  {'pieza':<16} {'clase':<6} {'tris':>6} {'presup':>7} {'OBJ tris':>9} "
        f"{'vox':>8}  {'AABB (m)':<24} vent.")
    add("  " + "-" * 96)
    for result in results:
        box = " × ".join(f"{c:.2f}" for c in result.size_metres)
        add(f"  {result.piece_id:<16} {result.kind:<6} {result.triangle_count:>6} "
            f"{result.budget:>7} {result.source_triangles:>9} {result.voxel_count:>8}  "
            f"{box:<24} {result.window_voxels}")
        add(f"      partes: {', '.join(result.parts)}")
        add(f"      AABB   : min {[round(c, 4) for c in result.aabb_min]}  "
            f"max {[round(c, 4) for c in result.aabb_max]}")
    add("")
    add("familias de paleta (representante ← miembros):")
    for rep in sorted(set(palette_map.values())):
        members = sorted(i for i, r in palette_map.items() if r == rep)
        add(f"  {rep:>3} ← {members}")
    add("")
    add("índices de ventana de la máscara emisiva:")
    for index, colour in sorted(windows.items()):
        add(f"  {index:>3} → RGB {tuple(int(c) for c in colour[:3])}")
    add("")
    if failures:
        add(f"CHECK compose: FAIL ({len(failures)} fallos)")
        for failure in failures:
            add(f"  - {failure}")
    else:
        add("CHECK compose: OK")
    return "\n".join(lines) + "\n"


def _write_text(path: Path, text: str) -> None:
    """Escribe UTF-8 con saltos `\\n`, sin BOM."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))
