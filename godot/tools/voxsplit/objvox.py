"""Voxelizador de OBJ de MagicaVoxel a la rejilla que consume `mesher.build_part`.

`voxreader` lee `.vox`; este módulo cubre el otro formato del catálogo: los packs que
sólo traen **OBJ ya mallado** por MagicaVoxel (`assets/_raw/nuke Free Sample.zip`). La
salida es la misma estructura que `VoxModel.voxels`, ``{(x, y, z): índice_paleta}`` con
el índice **1-based**, de modo que el resto del pipeline (`parts`, `mesher`, `glbwriter`,
`glbvalidate`) funciona sin cambios.

Por qué hay que re-voxelizar en vez de importar el OBJ tal cual: el exportador de
MagicaVoxel emite **un quad por cara de vóxel visible**, sin fusionar nada.
`BuildingBlock-0` son 48 644 triángulos para una casa de 4,85 × 2,50 m. Volviendo a la
rejilla y pasando por el mesher greedy de `docs/05` §6 la misma pieza baja dos órdenes de
magnitud, conserva exactamente la misma silueta y hereda la UV de paleta de 256×1 que ya
usan el dron y el Arachnodroid.

## Cómo se recupera la rejilla

Cada cara del OBJ es un rectángulo alineado a ejes cuyas coordenadas son múltiplos del
paso (0,02 unidades en este pack). La **normal apunta hacia afuera**, así que:

* la celda que toca la cara por el lado **contrario** a la normal es *interior*;
* la celda que la toca por el lado de la normal es *exterior*.

Una celda se considera ocupada si alguna cara la marca interior y **ninguna** la marca
exterior; las celdas marcadas de las dos formas son conflictos y se reportan
(`VoxelGrid.conflicts`), no se silencian.

Esa regla sola sólo recupera la **cáscara**: MagicaVoxel no emite las caras entre dos
vóxeles adyacentes, así que el volumen macizo de un bloque no deja ninguna cara y
quedaría hueco. Un modelo hueco no es equivalente al macizo — el mesher generaría
también la superficie interior — así que además se hace un **relleno por inundación**:
se parte del exterior de la caja envolvente y se avanza entre celdas vecinas sólo cuando
no hay una cara del OBJ entre ellas. Lo que no se alcanza desde afuera está dentro. Los
huecos sellados (una habitación cerrada) se rellenan, que es justo lo que interesa: no se
ven y su superficie interior costaba triángulos. Los huecos abiertos (un zaguán con
puerta) siguen huecos.

Las dos vías se contrastan entre sí: toda celda marcada interior tiene que quedar
ocupada y toda celda marcada exterior tiene que quedar vacía. Las diferencias se
acumulan en `VoxelGrid.fill_mismatches`.

## Color

El OBJ trae `vt u 0.5` con ``u = (índice0 + 0,5) / 256``, la misma convención que escribe
`mesher._uv_for` para el índice 1-based. El color de una celda es el de la cara que la
marcó interior; si dos caras discrepan gana la mayoría y el caso se anota en
`VoxelGrid.colour_conflicts`. Las celdas de relleno nunca generan caras, así que su color
es irrelevante y se les pone el índice más frecuente de la pieza.

Sólo stdlib más Pillow (para leer el PNG de paleta), como fija `docs/05` §1.
"""

from __future__ import annotations

import zipfile
from collections import Counter, deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

__all__ = [
    "ObjVoxError",
    "ObjMesh",
    "VoxelGrid",
    "DEFAULT_STEP",
    "PALETTE_WIDTH",
    "read_obj",
    "read_palette",
    "read_source_bytes",
    "voxelize",
    "load",
    "normalize",
    "origin_for",
    "pivot_for",
    "translate",
    "mirror_x",
]

#: Tamaño del vóxel del pack, en unidades del OBJ. Todas las coordenadas son múltiplos.
DEFAULT_STEP = 0.02

#: Ancho de la textura de paleta, en píxeles (`docs/05` §6.2).
PALETTE_WIDTH = 256

#: Cuánto puede desviarse una coordenada de un múltiplo exacto del paso, en celdas.
SNAP_TOLERANCE = 1e-3

#: Cuánto puede desviarse una normal de su eje antes de rechazar la cara.
NORMAL_TOLERANCE = 1e-4

#: Separador de rutas «dentro de un ZIP», igual que en `voxreader`.
ZIP_SEPARATOR = "!"

#: Las seis normales de eje, en el orden en que MagicaVoxel las escribe.
_AXIS_OF_NORMAL = {
    (-1.0, 0.0, 0.0): (0, -1), (1.0, 0.0, 0.0): (0, 1),
    (0.0, -1.0, 0.0): (1, -1), (0.0, 1.0, 0.0): (1, 1),
    (0.0, 0.0, -1.0): (2, -1), (0.0, 0.0, 1.0): (2, 1),
}


class ObjVoxError(Exception):
    """Error de lectura, de formato o de voxelización de un OBJ."""


# --------------------------------------------------------------------------- #
# Lectura                                                                      #
# --------------------------------------------------------------------------- #


def read_source_bytes(path: str | Path) -> bytes:
    """Lee un archivo de disco o un miembro de un ZIP (``archivo.zip!miembro``)."""
    text = str(path)
    zip_path, sep, member = text.partition(ZIP_SEPARATOR)
    if not sep:
        try:
            return Path(text).read_bytes()
        except OSError as exc:
            raise ObjVoxError(f"no se pudo leer '{text}': {exc}") from exc
    if not member:
        raise ObjVoxError(f"{text}: falta el miembro después de '{ZIP_SEPARATOR}'")
    normalized = _normalize_member(member)
    try:
        with zipfile.ZipFile(zip_path) as archive:
            return archive.read(normalized)
    except (OSError, KeyError, zipfile.BadZipFile) as exc:
        raise ObjVoxError(f"no se pudo leer '{normalized}' de '{zip_path}': {exc}") from exc


def _normalize_member(member: str) -> str:
    """Normaliza el nombre de un miembro de ZIP.

    Un ZIP guarda siempre las rutas con `/`; una escrita a mano en Windows puede traer
    `\\`, y entonces `ZipFile.read` falla con un `KeyError` incomprensible. Se limpian
    además el `./` inicial y las barras dobles.
    """
    parts = [chunk for chunk in member.replace("\\", "/").split("/")
             if chunk not in ("", ".")]
    return "/".join(parts)


def _sibling(path: str, suffix: str) -> str:
    """Ruta hermana con otra extensión, respetando la forma ``archivo.zip!miembro``."""
    zip_path, sep, member = str(path).partition(ZIP_SEPARATOR)
    target = member if sep else zip_path
    dot = target.rfind(".")
    if dot > target.replace("\\", "/").rfind("/"):
        target = target[:dot]
    target += suffix
    return f"{zip_path}{sep}{target}" if sep else target


@dataclass
class ObjMesh:
    """Un OBJ de MagicaVoxel ya parseado, sin tocar las coordenadas."""

    name: str
    positions: list[tuple[float, float, float]] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)
    normals: list[tuple[float, float, float]] = field(default_factory=list)
    #: Cada cara es una lista de ``(v, vt, vn)`` con índices **0-based**; `vt`/`vn` o −1.
    faces: list[list[tuple[int, int, int]]] = field(default_factory=list)
    source: str = ""

    @property
    def triangle_count(self) -> int:
        """Triángulos del OBJ tal cual viene, contando cada polígono como abanico."""
        return sum(max(0, len(face) - 2) for face in self.faces)

    def bounds(self) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
        """``(min, max)`` de los vértices, en unidades del OBJ."""
        if not self.positions:
            return (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)
        lo = tuple(min(p[i] for p in self.positions) for i in range(3))
        hi = tuple(max(p[i] for p in self.positions) for i in range(3))
        return lo, hi  # type: ignore[return-value]


def read_obj(path: str | Path) -> ObjMesh:
    """Parsea un OBJ (de disco o de un ZIP). Ignora `mtllib`, `usemtl`, `g`, `s`.

    Cualquier número mal escrito o índice fuera de rango sale como `ObjVoxError` **con
    archivo y línea**: un `ValueError` crudo de `float()` no dice dónde está el problema y
    la CLI lo trataría como un fallo interno en vez de como un archivo inválido.
    """
    text = read_source_bytes(path).decode("utf-8", "replace")
    mesh = ObjMesh(name=Path(_sibling(str(path), "")).name or "mesh", source=str(path))
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line[0] == "#":
            continue
        head, _, rest = line.partition(" ")
        where = f"{path}:{number}"
        try:
            if head == "v":
                parts = rest.split()
                if len(parts) < 3:
                    raise ObjVoxError(f"{where}: 'v' con menos de 3 componentes")
                mesh.positions.append((float(parts[0]), float(parts[1]), float(parts[2])))
            elif head == "vt":
                parts = rest.split()
                if not parts:
                    raise ObjVoxError(f"{where}: 'vt' sin componentes")
                mesh.uvs.append((float(parts[0]), float(parts[1]) if len(parts) > 1 else 0.0))
            elif head == "vn":
                parts = rest.split()
                if len(parts) < 3:
                    raise ObjVoxError(f"{where}: 'vn' con menos de 3 componentes")
                mesh.normals.append((float(parts[0]), float(parts[1]), float(parts[2])))
            elif head == "f":
                mesh.faces.append(_parse_face(mesh, rest, where))
            elif head == "o":
                mesh.name = rest.strip() or mesh.name
        except ObjVoxError:
            raise
        except (ValueError, IndexError, TypeError) as exc:
            raise ObjVoxError(f"{where}: no se pudo leer '{line}': {exc}") from exc
    if not mesh.faces:
        raise ObjVoxError(f"{path}: el OBJ no tiene ninguna cara")
    if not mesh.positions:
        raise ObjVoxError(f"{path}: el OBJ no tiene ningún vértice")
    return mesh


def _parse_face(mesh: ObjMesh, rest: str, where: str) -> list[tuple[int, int, int]]:
    """Parsea una línea `f` a ``[(v, vt, vn)]`` 0-based, validando todos los índices."""
    face: list[tuple[int, int, int]] = []
    for token in rest.split():
        chunks = token.split("/")
        vertex = _relative(chunks[0], len(mesh.positions), "vértice", where, optional=False)
        uv = _relative(chunks[1] if len(chunks) > 1 else "", len(mesh.uvs), "vt", where)
        normal = _relative(chunks[2] if len(chunks) > 2 else "", len(mesh.normals),
                           "vn", where)
        face.append((vertex, uv, normal))
    if len(face) < 3:
        raise ObjVoxError(f"{where}: cara con {len(face)} vértices, hacen falta 3")
    return face


def _relative(token: str, count: int, kind: str, where: str,
              *, optional: bool = True) -> int:
    """Convierte un índice de OBJ (1-based, negativo = relativo al final) a 0-based.

    Valida el rango: el OBJ es 1-based y un `0` significa «ausente». Sin esta
    comprobación, `0` se convertía en `−1` y terminaba indexando el **último** vértice de
    la lista, que es un error silencioso y mucho peor que un fallo.
    """
    text = token.strip()
    if not text:
        if optional:
            return -1
        raise ObjVoxError(f"{where}: falta el índice de {kind}")
    try:
        index = int(text)
    except ValueError as exc:
        raise ObjVoxError(f"{where}: índice de {kind} no entero: '{text}'") from exc
    if index == 0:
        if optional:
            return -1
        raise ObjVoxError(f"{where}: índice de {kind} 0; el OBJ es 1-based")
    resolved = index - 1 if index > 0 else count + index
    if not 0 <= resolved < count:
        raise ObjVoxError(f"{where}: índice de {kind} {index} fuera de rango "
                          f"(hay {count} declarados)")
    return resolved


def read_palette(path: str | Path) -> list[tuple[int, int, int, int]]:
    """Lee el PNG 256×1 hermano del OBJ y devuelve 256 tuplas RGBA (índice `i` en `[i-1]`)."""
    from PIL import Image
    import io

    png = _sibling(str(path), ".png")
    data = read_source_bytes(png)
    try:
        with Image.open(io.BytesIO(data)) as image:
            rgba = image.convert("RGBA")
            if rgba.width != PALETTE_WIDTH or rgba.height != 1:
                raise ObjVoxError(f"{png}: la paleta mide {rgba.width}×{rgba.height}, "
                                  f"se esperaba {PALETTE_WIDTH}×1")
            pixels = list(rgba.getdata())
    except ObjVoxError:
        raise
    except Exception as exc:  # Pillow lanza OSError, UnidentifiedImageError, SyntaxError…
        raise ObjVoxError(f"{png}: no se pudo decodificar el PNG de paleta: {exc}") from exc
    if len(pixels) != PALETTE_WIDTH:
        raise ObjVoxError(f"{png}: el PNG trajo {len(pixels)} píxeles, se esperaban "
                          f"{PALETTE_WIDTH}")
    return [tuple(int(c) for c in pixel) for pixel in pixels]  # type: ignore[misc]


# --------------------------------------------------------------------------- #
# Voxelización                                                                 #
# --------------------------------------------------------------------------- #


@dataclass
class VoxelGrid:
    """La rejilla recuperada de un OBJ, lista para `mesher.build_part`."""

    name: str
    #: ``{(x, y, z): índice_paleta}`` con el índice 1-based y el origen en la celda mínima.
    voxels: dict[tuple[int, int, int], int] = field(default_factory=dict)
    size: tuple[int, int, int] = (0, 0, 0)
    step: float = DEFAULT_STEP
    palette: list[tuple[int, int, int, int]] = field(default_factory=list)
    #: Esquina mínima de la caja envolvente, en unidades del OBJ original.
    obj_min: tuple[float, float, float] = (0.0, 0.0, 0.0)
    source_triangles: int = 0
    face_count: int = 0
    shell_count: int = 0
    filled_count: int = 0
    conflicts: list[tuple[int, int, int]] = field(default_factory=list)
    colour_conflicts: list[tuple[tuple[int, int, int], list[int]]] = field(default_factory=list)
    fill_mismatches: list[str] = field(default_factory=list)

    @property
    def voxel_count(self) -> int:
        """Número de celdas ocupadas."""
        return len(self.voxels)

    def colours(self) -> Counter:
        """Histograma ``{índice_paleta: celdas}``."""
        return Counter(self.voxels.values())

    def extent(self) -> tuple[int, int, int]:
        """Dimensiones en celdas del bbox **ocupado** (no de la caja reservada)."""
        if not self.voxels:
            return (0, 0, 0)
        return tuple(max(c[i] for c in self.voxels) - min(c[i] for c in self.voxels) + 1
                     for i in range(3))  # type: ignore[return-value]

    def metres(self, scale: float = 1.0) -> tuple[float, float, float]:
        """Dimensiones del bbox ocupado en metros, con el factor `scale` aplicado."""
        return tuple(c * self.step * scale for c in self.extent())  # type: ignore[return-value]


def voxelize(mesh: ObjMesh, *, step: float = DEFAULT_STEP,
             palette: Sequence[Sequence[int]] | None = None,
             fill: bool = True) -> VoxelGrid:
    """Recupera la rejilla de `mesh`. Ver el encabezado del módulo para las reglas."""
    if step <= 0.0:
        raise ObjVoxError(f"paso inválido: {step}")

    lo, hi = mesh.bounds()
    base = [_snap(lo[i], step, f"{mesh.name}: mínimo del eje {'xyz'[i]}") for i in range(3)]
    span = [_snap(hi[i], step, f"{mesh.name}: máximo del eje {'xyz'[i]}") - base[i]
            for i in range(3)]
    # Un OBJ sin volumen en algún eje —una sola tapa, un plano— no es voxelizable: con
    # `max(1, 0)` se le inventaba una capa de una celda y salía una caja fantasma.
    for i in range(3):
        if span[i] < 1:
            raise ObjVoxError(f"{mesh.name}: el eje {'xyz'[i]} no tiene volumen "
                              f"({lo[i]}..{hi[i]}, {span[i]} celdas); "
                              f"la malla tiene que ser cerrada, no un plano")
    size = tuple(span)

    interior: dict[tuple[int, int, int], Counter] = {}
    exterior: set[tuple[int, int, int]] = set()
    # `blocked[eje]` guarda los planos de corte: (k, u, v) impide pasar de la celda
    # k − 1 a la k a lo largo de `eje` en la columna (u, v).
    blocked: list[set[tuple[int, int, int]]] = [set(), set(), set()]
    faces = 0

    for face in mesh.faces:
        axis, sign = _face_axis(mesh, face)
        u_axis = (axis + 1) % 3
        v_axis = (axis + 2) % 3
        points = [mesh.positions[v] for v, _t, _n in face]
        plane_raw = points[0][axis]
        for point in points[1:]:
            if abs(point[axis] - plane_raw) > step * SNAP_TOLERANCE:
                raise ObjVoxError(f"{mesh.name}: cara no plana en el eje {'xyz'[axis]} "
                                  f"({point[axis]} != {plane_raw})")
        plane = _snap(plane_raw, step, f"{mesh.name}: plano de una cara") - base[axis]
        u0 = _snap(min(p[u_axis] for p in points), step, mesh.name) - base[u_axis]
        u1 = _snap(max(p[u_axis] for p in points), step, mesh.name) - base[u_axis]
        v0 = _snap(min(p[v_axis] for p in points), step, mesh.name) - base[v_axis]
        v1 = _snap(max(p[v_axis] for p in points), step, mesh.name) - base[v_axis]
        if u1 <= u0 or v1 <= v0:
            continue  # cara degenerada: no cubre ninguna celda
        faces += 1
        index = _face_palette_index(mesh, face)
        inside_k = plane - 1 if sign > 0 else plane
        outside_k = plane if sign > 0 else plane - 1
        for u in range(u0, u1):
            for v in range(v0, v1):
                cell = [0, 0, 0]
                cell[u_axis] = u
                cell[v_axis] = v
                cell[axis] = inside_k
                key = (cell[0], cell[1], cell[2])
                interior.setdefault(key, Counter())[index] += 1
                cell[axis] = outside_k
                exterior.add((cell[0], cell[1], cell[2]))
                blocked[axis].add((plane, u, v))

    grid = VoxelGrid(
        name=mesh.name,
        size=size,  # type: ignore[arg-type]
        step=step,
        palette=[tuple(int(c) for c in palette[i][:4]) for i in range(PALETTE_WIDTH)]
        if palette is not None else [],
        obj_min=(base[0] * step, base[1] * step, base[2] * step),
        source_triangles=mesh.triangle_count,
        face_count=faces,
    )

    shell = {cell: votes for cell, votes in interior.items() if cell not in exterior}
    grid.conflicts = sorted(cell for cell in interior if cell in exterior)
    grid.shell_count = len(shell)

    solid: set[tuple[int, int, int]] = set(shell)
    if fill:
        solid = _flood_fill(size, blocked)  # type: ignore[arg-type]
        for cell in shell:
            if cell not in solid:
                grid.fill_mismatches.append(
                    f"la celda {cell} está marcada interior pero el relleno la deja vacía")
        for cell in exterior:
            if cell in solid and _inside_box(cell, size):  # type: ignore[arg-type]
                grid.fill_mismatches.append(
                    f"la celda {cell} está marcada exterior pero el relleno la llena")
        solid |= set(shell)
    grid.filled_count = len(solid) - len(shell)

    votes_of = interior
    fallback = Counter()
    for cell, votes in shell.items():
        fallback[votes.most_common(1)[0][0]] += 1
    default_index = fallback.most_common(1)[0][0] if fallback else 1
    for cell in sorted(solid):
        votes = votes_of.get(cell)
        if votes is None:
            grid.voxels[cell] = default_index
            continue
        ranked = votes.most_common()
        grid.voxels[cell] = ranked[0][0]
        if len(ranked) > 1:
            grid.colour_conflicts.append((cell, [i for i, _n in ranked]))
    return grid


def _inside_box(cell: Sequence[int], size: Sequence[int]) -> bool:
    """`True` si la celda cae dentro de la caja reservada `size`."""
    return all(0 <= cell[i] < size[i] for i in range(3))


def _flood_fill(size: tuple[int, int, int],
                blocked: list[set[tuple[int, int, int]]]) -> set[tuple[int, int, int]]:
    """Devuelve las celdas **no alcanzables** desde afuera, es decir el sólido.

    Se inunda una caja con un anillo de una celda de margen: así la semilla siempre existe
    aunque la pieza toque el borde. Se cruza de una celda a la vecina sólo si no hay una
    cara del OBJ entre las dos.
    """
    lo = (-1, -1, -1)
    hi = (size[0], size[1], size[2])
    outside: set[tuple[int, int, int]] = {lo}
    queue = deque([lo])
    while queue:
        current = queue.popleft()
        for axis in range(3):
            u_axis = (axis + 1) % 3
            v_axis = (axis + 2) % 3
            for step_sign in (1, -1):
                neighbour = list(current)
                neighbour[axis] += step_sign
                if not (lo[axis] <= neighbour[axis] <= hi[axis]):
                    continue
                if any(not (lo[i] <= neighbour[i] <= hi[i]) for i in range(3)):
                    continue
                key = (neighbour[0], neighbour[1], neighbour[2])
                if key in outside:
                    continue
                plane = neighbour[axis] if step_sign > 0 else current[axis]
                if (plane, current[u_axis], current[v_axis]) in blocked[axis]:
                    continue
                outside.add(key)
                queue.append(key)
    solid: set[tuple[int, int, int]] = set()
    for x in range(size[0]):
        for y in range(size[1]):
            for z in range(size[2]):
                if (x, y, z) not in outside:
                    solid.add((x, y, z))
    return solid


def _face_axis(mesh: ObjMesh, face: list[tuple[int, int, int]]) -> tuple[int, int]:
    """Eje y signo de la normal de la cara; falla si no es una normal de eje.

    La comprobación se hace contra la normal **original**, no contra la redondeada: con
    `key` —que por construcción ya es ±1 en una componente y 0 en las otras— la condición
    era tautológica y una normal de (0,6, 0,8, 0) pasaba como `+y`.
    """
    normal_index = face[0][2]
    if 0 <= normal_index < len(mesh.normals):
        normal = mesh.normals[normal_index]
    else:
        normal = _geometric_normal(mesh, face)
    key = tuple(float(round(c)) for c in normal)
    if key not in _AXIS_OF_NORMAL:
        raise ObjVoxError(f"{mesh.name}: normal que no es de eje: {normal}")
    drift = max(abs(normal[i] - key[i]) for i in range(3))
    if drift > NORMAL_TOLERANCE:
        raise ObjVoxError(f"{mesh.name}: la normal {normal} se desvía {drift:.6f} del eje "
                          f"{key}; sólo se admiten caras alineadas a ejes")
    return _AXIS_OF_NORMAL[key]


def _geometric_normal(mesh: ObjMesh,
                      face: list[tuple[int, int, int]]) -> tuple[float, float, float]:
    """Normal por producto vectorial, para OBJ sin `vn`.

    Busca el primer trío **no colineal** de la cara: con un abanico degenerado, los tres
    primeros vértices pueden estar alineados y el producto vectorial daría cero.
    """
    if len(face) < 3:
        raise ObjVoxError(f"{mesh.name}: cara con {len(face)} vértices; "
                          f"no se puede calcular la normal")
    a = mesh.positions[face[0][0]]
    for i in range(1, len(face) - 1):
        b = mesh.positions[face[i][0]]
        c = mesh.positions[face[i + 1][0]]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        length = max(abs(n[0]), abs(n[1]), abs(n[2]))
        if length > 0.0:
            return (n[0] / length, n[1] / length, n[2] / length)
    raise ObjVoxError(f"{mesh.name}: cara degenerada (todos sus vértices son colineales)")


def _face_palette_index(mesh: ObjMesh, face: list[tuple[int, int, int]]) -> int:
    """Índice de paleta 1-based de la cara, leído de su `vt` (``u = (i − 0,5) / 256``).

    Una cara sin `vt` **falla**. El respaldo anterior —devolver el índice 1— pintaba
    silenciosamente de marrón (142, 104, 69) media pieza si el OBJ venía sin UV, que es
    justo el tipo de error que hay que ver en el reporte y no en la captura.
    """
    uv_index = face[0][1]
    if not 0 <= uv_index < len(mesh.uvs):
        raise ObjVoxError(f"{mesh.name}: hay caras sin coordenada 'vt'; el color de cada "
                          f"vóxel sale de la UV de paleta, así que no hay de dónde sacarlo")
    u = mesh.uvs[uv_index][0]
    index = int(round(u * PALETTE_WIDTH + 0.5))
    if not 1 <= index <= PALETTE_WIDTH:
        raise ObjVoxError(f"{mesh.name}: la UV u = {u} cae en el índice de paleta {index}, "
                          f"fuera de 1..{PALETTE_WIDTH}")
    return index


def _snap(value: float, step: float, where: str) -> int:
    """Convierte una coordenada a índice de línea de retícula; falla si no es múltiplo."""
    quotient = value / step
    rounded = round(quotient)
    if abs(quotient - rounded) > SNAP_TOLERANCE:
        raise ObjVoxError(f"{where}: {value} no es múltiplo del paso {step} "
                          f"(quedaría en {quotient:.6f} celdas)")
    return int(rounded)


def load(path: str | Path, *, step: float = DEFAULT_STEP, fill: bool = True) -> VoxelGrid:
    """Atajo: lee el OBJ y su paleta hermana y devuelve la rejilla voxelizada."""
    mesh = read_obj(path)
    try:
        palette = read_palette(path)
    except ObjVoxError:
        palette = None
    return voxelize(mesh, step=step, palette=palette, fill=fill)


# --------------------------------------------------------------------------- #
# Utilidades de colocación                                                     #
# --------------------------------------------------------------------------- #


def translate(voxels: dict[tuple[int, int, int], int],
              offset: Sequence[int]) -> dict[tuple[int, int, int], int]:
    """Desplaza una rejilla por `offset` celdas."""
    dx, dy, dz = int(offset[0]), int(offset[1]), int(offset[2])
    return {(c[0] + dx, c[1] + dy, c[2] + dz): i for c, i in voxels.items()}


def mirror_x(voxels: dict[tuple[int, int, int], int]) -> dict[tuple[int, int, int], int]:
    """Espeja en X con la regla ``x' = max + min − x``, que conserva el bbox."""
    if not voxels:
        return {}
    lo = min(c[0] for c in voxels)
    hi = max(c[0] for c in voxels)
    return {(lo + hi - c[0], c[1], c[2]): i for c, i in voxels.items()}


def normalize(voxels: dict[tuple[int, int, int], int]
              ) -> tuple[dict[tuple[int, int, int], int], tuple[int, int, int],
                         tuple[int, int, int]]:
    """Lleva la esquina mínima al origen. Devuelve ``(voxels, size, offset_aplicado)``."""
    if not voxels:
        return {}, (0, 0, 0), (0, 0, 0)
    lo = tuple(min(c[i] for c in voxels) for i in range(3))
    hi = tuple(max(c[i] for c in voxels) for i in range(3))
    shifted = translate(voxels, (-lo[0], -lo[1], -lo[2]))
    size = tuple(hi[i] - lo[i] + 1 for i in range(3))
    return shifted, size, tuple(-c for c in lo)  # type: ignore[return-value]


def origin_for(size: Sequence[int], *, up_axis: int = 1) -> tuple[float, float, float]:
    """`origin_voxel` que centra la pieza en el plano horizontal y apoya la base en `y = 0`.

    `docs/05` §3.1: `origin_voxel` nombra una **esquina** de la retícula. Con `n` celdas en
    un eje, la esquina que cae en el centro es `n / 2`; en el eje vertical es `0`, que deja
    la cara inferior de la celda 0 exactamente en el metro cero.
    """
    return tuple(0.0 if i == up_axis else size[i] / 2.0 for i in range(3))  # type: ignore[return-value]


def pivot_for(origin: Sequence[float]) -> tuple[float, float, float]:
    """Pivote en índices cuyo `pivot_world` es el origen del modelo: ``origin − 0,5``."""
    return (origin[0] - 0.5, origin[1] - 0.5, origin[2] - 0.5)
