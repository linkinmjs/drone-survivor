"""Carga, validación, espejo y asignación de voxels de `parts.json` (§4 y §5 de `docs/05`).

Reglas implementadas:

* El **orden** de `parts[]` importa: cada voxel se asigna a la **primera** parte cuya
  unión de `boxes` lo contiene y cuya unión de `exclude` no lo contiene (§5.1).
* Lo que no cae en ninguna parte va a la clave especial ``"_unassigned"`` (§5.2).
* Las cajas son **inclusivas** y están en índices de voxel.
* `origin_voxel` nombra una **esquina** de la retícula; los centros de voxel viven en
  los enteros. La fórmula única de §3.1 es
  ``p_vox = (p_index - origin_voxel + 0.5) * voxel_size`` y luego ``axis_map``.
* `axis_map` debe ser una permutación con signo; se calcula su determinante para saber
  si hay que invertir el bobinado de los triángulos (§3.3).
* Espejo (§4.4): ``x' = n - 1 - x``, aplicado a `boxes`, `exclude` y `pivot`. Se expone
  con el campo opcional ``mirror_of`` + ``mirror_axes`` de una entrada de `parts[]`.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Sequence

__all__ = [
    "PartsError",
    "AxisMap",
    "Part",
    "PartsSpec",
    "load",
    "load_dict",
    "assign",
    "mirror_box",
    "mirror_point",
    "UNASSIGNED",
]

#: Clave de la parte virtual que recoge los voxels sin asignar (§5.2).
UNASSIGNED = "_unassigned"

#: Flags reconocidos por `docs/05` §4.2. Otros valores se aceptan con advertencia.
KNOWN_FLAGS = frozenset({
    "root", "weak_point", "detachable", "cosmetic",
    "leg_root", "leg_segment", "foot", "staged",
})

#: Valores admitidos para `collision`.
COLLISION_KINDS = frozenset({"box", "convex", "none"})

_AXIS_INDEX = {"x": 0, "y": 1, "z": 2}


class PartsError(Exception):
    """Error de esquema en un `parts.json`, con campo y (si se puede) línea.

    Atributos:
        field_path: ruta al campo culpable, p. ej. ``parts[7].boxes[0]``.
        line: número de línea 1-based dentro del archivo, o ``None``.
    """

    def __init__(self, message: str, field_path: str = "", line: int | None = None) -> None:
        self.field_path = field_path
        self.line = line
        where = []
        if field_path:
            where.append(f"campo '{field_path}'")
        if line is not None:
            where.append(f"línea {line}")
        suffix = f" ({', '.join(where)})" if where else ""
        super().__init__(f"{message}{suffix}")


# --------------------------------------------------------------------------- #
# Mapa de ejes                                                                 #
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class AxisMap:
    """Permutación con signo de ejes: de MagicaVoxel (Z-up) a Godot (Y-up).

    ``{"x": "+x", "y": "+z", "z": "-y"}`` significa *godot.x = vox.x*, *godot.y = vox.z*,
    *godot.z = −vox.y*.
    """

    source: tuple[int, int, int]
    signs: tuple[float, float, float]
    raw: dict[str, str]

    @property
    def determinant(self) -> float:
        """Determinante de la matriz de permutación con signo: ``+1`` o ``−1``."""
        rows = [[0.0, 0.0, 0.0] for _ in range(3)]
        for axis in range(3):
            rows[axis][self.source[axis]] = self.signs[axis]
        a, b, c = rows
        return (a[0] * (b[1] * c[2] - b[2] * c[1])
                - a[1] * (b[0] * c[2] - b[2] * c[0])
                + a[2] * (b[0] * c[1] - b[1] * c[0]))

    def apply(self, v: Sequence[float]) -> tuple[float, float, float]:
        """Convierte un vector en ejes de MagicaVoxel a ejes de Godot."""
        return (
            self.signs[0] * v[self.source[0]],
            self.signs[1] * v[self.source[1]],
            self.signs[2] * v[self.source[2]],
        )

    @staticmethod
    def parse(raw: Any, field_path: str = "axis_map") -> "AxisMap":
        """Valida y construye un `AxisMap`; lanza `PartsError` si no es una permutación."""
        if not isinstance(raw, dict):
            raise PartsError("axis_map debe ser un objeto", field_path)
        source: list[int] = [0, 0, 0]
        signs: list[float] = [1.0, 1.0, 1.0]
        seen: set[int] = set()
        for axis_name in ("x", "y", "z"):
            if axis_name not in raw:
                raise PartsError(f"axis_map no declara el eje '{axis_name}'", field_path)
            token = str(raw[axis_name]).strip().lower()
            sign = 1.0
            if token and token[0] in "+-":
                sign = -1.0 if token[0] == "-" else 1.0
                token = token[1:]
            if token not in _AXIS_INDEX:
                raise PartsError(f"eje de origen inválido '{raw[axis_name]}'",
                                 f"{field_path}.{axis_name}")
            index = _AXIS_INDEX[token]
            if index in seen:
                raise PartsError(f"el eje de origen '{token}' se usa dos veces",
                                 f"{field_path}.{axis_name}")
            seen.add(index)
            source[_AXIS_INDEX[axis_name]] = index
            signs[_AXIS_INDEX[axis_name]] = sign
        result = AxisMap(tuple(source), tuple(signs), dict(raw))  # type: ignore[arg-type]
        det = result.determinant
        if abs(abs(det) - 1.0) > 1e-9:
            raise PartsError(f"axis_map no es una permutación con signo (det = {det})",
                             field_path)
        return result


# --------------------------------------------------------------------------- #
# Partes                                                                       #
# --------------------------------------------------------------------------- #


@dataclass
class Part:
    """Una entrada de `parts[]` ya validada."""

    id: str
    parent: str | None
    boxes: list[tuple[int, int, int, int, int, int]]
    pivot: tuple[float, float, float]
    exclude: list[tuple[int, int, int, int, int, int]] = field(default_factory=list)
    flags: list[str] = field(default_factory=list)
    collision: str = "box"
    hp: int | None = None
    armor: float | None = None
    debris_mass: float | None = None
    function: str | None = None
    weak_point_id: str | None = None
    meta: dict[str, Any] = field(default_factory=dict)
    raw: dict[str, Any] = field(default_factory=dict)

    @property
    def is_root(self) -> bool:
        """`True` si la parte lleva el flag `root`."""
        return "root" in self.flags

    @property
    def is_weak_point(self) -> bool:
        """`True` si la parte lleva el flag `weak_point`."""
        return "weak_point" in self.flags

    def contains(self, x: int, y: int, z: int) -> bool:
        """`True` si el voxel cae dentro de `boxes` y fuera de `exclude`."""
        inside = False
        for x0, y0, z0, x1, y1, z1 in self.boxes:
            if x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1:
                inside = True
                break
        if not inside:
            return False
        for x0, y0, z0, x1, y1, z1 in self.exclude:
            if x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1:
                return False
        return True


@dataclass
class PartsSpec:
    """Un `parts.json` completo, validado y con el espejo ya expandido."""

    source: str
    voxel_size: float
    origin_voxel: tuple[float, float, float]
    axis_map: AxisMap
    palette_texture: str
    emissive_palette_indices: list[int]
    collision_default: str
    parts: list[Part]
    root_node: str
    name: str = "model"
    grid_size: tuple[int, int, int] | None = None
    density: float = 220.0
    emissive_strength: float | None = None
    path: Path | None = None
    raw: dict[str, Any] = field(default_factory=dict)

    # -- utilidades geométricas ------------------------------------------- #

    def to_meters(self, p_index: Sequence[float]) -> tuple[float, float, float]:
        """Aplica la fórmula única de §3.1: índices de voxel → metros en ejes de Godot."""
        vx = (p_index[0] - self.origin_voxel[0] + 0.5) * self.voxel_size
        vy = (p_index[1] - self.origin_voxel[1] + 0.5) * self.voxel_size
        vz = (p_index[2] - self.origin_voxel[2] + 0.5) * self.voxel_size
        return self.axis_map.apply((vx, vy, vz))

    def pivot_world(self, part: Part) -> tuple[float, float, float]:
        """Posición del pivote de `part` en metros, en el espacio del modelo."""
        return self.to_meters(part.pivot)

    def by_id(self) -> dict[str, Part]:
        """Índice ``{id: Part}``."""
        return {p.id: p for p in self.parts}

    def root_part(self) -> Part:
        """La única parte con `parent == None`."""
        for part in self.parts:
            if part.parent is None:
                return part
        raise PartsError("no hay ninguna parte con parent = null", "parts")

    def children_of(self, part_id: str | None) -> list[Part]:
        """Hijos directos de `part_id`, en el orden de `parts[]`."""
        return [p for p in self.parts if p.parent == part_id]


# --------------------------------------------------------------------------- #
# Espejo                                                                       #
# --------------------------------------------------------------------------- #


def mirror_point(point: Sequence[float], axes: Iterable[str],
                 extent: Sequence[int]) -> tuple[float, ...]:
    """Espeja un punto en índices de voxel con la regla ``c' = n - 1 - c`` (§4.4)."""
    out = list(float(c) for c in point)
    for axis in axes:
        i = _AXIS_INDEX[axis]
        out[i] = (extent[i] - 1) - out[i]
    return tuple(out)


def mirror_box(box: Sequence[int], axes: Iterable[str],
               extent: Sequence[int]) -> tuple[int, int, int, int, int, int]:
    """Espeja una caja inclusiva y vuelve a ordenar sus extremos."""
    lo = [int(box[0]), int(box[1]), int(box[2])]
    hi = [int(box[3]), int(box[4]), int(box[5])]
    for axis in axes:
        i = _AXIS_INDEX[axis]
        a = (extent[i] - 1) - lo[i]
        b = (extent[i] - 1) - hi[i]
        lo[i], hi[i] = min(a, b), max(a, b)
    return (lo[0], lo[1], lo[2], hi[0], hi[1], hi[2])


# --------------------------------------------------------------------------- #
# Carga y validación                                                           #
# --------------------------------------------------------------------------- #


def _line_of(text: str | None, needle: str) -> int | None:
    """Busca la línea 1-based donde aparece `needle` en `text` (mejor esfuerzo)."""
    if not text:
        return None
    position = text.find(needle)
    if position < 0:
        return None
    return text.count("\n", 0, position) + 1


def _require(data: dict[str, Any], key: str, kind: type | tuple[type, ...],
             field_path: str, text: str | None) -> Any:
    if key not in data:
        raise PartsError(f"falta el campo obligatorio '{key}'", f"{field_path}{key}",
                         _line_of(text, f'"{key}"'))
    value = data[key]
    if not isinstance(value, kind):
        raise PartsError(f"'{key}' tiene el tipo equivocado", f"{field_path}{key}",
                         _line_of(text, f'"{key}"'))
    return value


def _as_box(value: Any, field_path: str, text: str | None) -> tuple[int, ...]:
    if not isinstance(value, (list, tuple)) or len(value) != 6:
        raise PartsError("una caja debe ser [x0, y0, z0, x1, y1, z1]", field_path,
                         _line_of(text, field_path))
    try:
        nums = [int(c) for c in value]
    except (TypeError, ValueError) as exc:
        raise PartsError(f"caja con componentes no enteras: {exc}", field_path) from exc
    lo = nums[:3]
    hi = nums[3:]
    for i in range(3):
        if lo[i] > hi[i]:
            raise PartsError(
                f"caja invertida en el eje {'xyz'[i]}: {lo[i]} > {hi[i]}", field_path)
    return tuple(lo + hi)


def load_dict(data: dict[str, Any], *, path: Path | None = None,
              text: str | None = None, name: str | None = None) -> PartsSpec:
    """Valida un `parts.json` ya parseado y devuelve el `PartsSpec` con espejos expandidos."""
    if not isinstance(data, dict):
        raise PartsError("el parts.json debe ser un objeto en la raíz")

    voxel_size = float(_require(data, "voxel_size", (int, float), "", text))
    if voxel_size <= 0.0:
        raise PartsError("voxel_size debe ser > 0", "voxel_size", _line_of(text, '"voxel_size"'))

    origin_raw = _require(data, "origin_voxel", (list, tuple), "", text)
    if len(origin_raw) != 3:
        raise PartsError("origin_voxel debe tener 3 componentes", "origin_voxel",
                         _line_of(text, '"origin_voxel"'))
    origin = tuple(float(c) for c in origin_raw)

    axis_map = AxisMap.parse(_require(data, "axis_map", dict, "", text))

    collision_default = str(data.get("collision_default", "box"))
    if collision_default not in COLLISION_KINDS:
        raise PartsError(f"collision_default inválido: '{collision_default}'",
                         "collision_default", _line_of(text, '"collision_default"'))

    emissive = [int(i) for i in data.get("emissive_palette_indices", [])]
    for index in emissive:
        if not 1 <= index <= 256:
            raise PartsError(f"índice emisivo fuera de 1..256: {index}",
                             "emissive_palette_indices")

    grid_raw = data.get("grid_size")
    grid_size = tuple(int(c) for c in grid_raw) if grid_raw else None

    raw_parts = _require(data, "parts", list, "", text)
    if not raw_parts:
        raise PartsError("parts[] está vacío", "parts", _line_of(text, '"parts"'))

    model_name = name or (path.name.split(".")[0] if path else "model")
    root_node = str(data.get("root_node") or _default_root_node(model_name))

    # -- expansión de espejos (`mirror_of`) -------------------------------- #
    by_id_raw: dict[str, dict[str, Any]] = {}
    expanded: list[dict[str, Any]] = []
    for i, entry in enumerate(raw_parts):
        if not isinstance(entry, dict):
            raise PartsError("cada entrada de parts[] debe ser un objeto", f"parts[{i}]")
        if "mirror_of" in entry:
            base_id = str(entry["mirror_of"])
            base = by_id_raw.get(base_id)
            if base is None:
                raise PartsError(f"mirror_of apunta a '{base_id}', que no está definida antes",
                                 f"parts[{i}].mirror_of")
            axes = [str(a).lower() for a in entry.get("mirror_axes", [])]
            for axis in axes:
                if axis not in _AXIS_INDEX:
                    raise PartsError(f"mirror_axes contiene un eje inválido '{axis}'",
                                     f"parts[{i}].mirror_axes")
            extent = tuple(int(c) for c in entry.get("mirror_extent", grid_size or (0, 0, 0)))
            if any(c <= 0 for c in extent):
                raise PartsError(
                    "para usar mirror_of hace falta 'grid_size' en la cabecera "
                    "o 'mirror_extent' en la parte", f"parts[{i}].mirror_extent")
            merged = dict(base)
            merged.update({k: v for k, v in entry.items()
                           if k not in ("mirror_of", "mirror_axes", "mirror_extent")})
            merged["boxes"] = [list(mirror_box(b, axes, extent)) for b in base.get("boxes", [])]
            if base.get("exclude"):
                merged["exclude"] = [list(mirror_box(b, axes, extent))
                                     for b in base["exclude"]]
            merged["pivot"] = list(mirror_point(base["pivot"], axes, extent))
            entry = merged
        expanded.append(entry)
        by_id_raw[str(entry.get("id", f"#{i}"))] = entry

    parts: list[Part] = []
    for i, entry in enumerate(expanded):
        field_path = f"parts[{i}]."
        part_id = str(_require(entry, "id", str, field_path, text))
        line = _line_of(text, f'"id": "{part_id}"')
        if "parent" not in entry:
            raise PartsError("falta el campo obligatorio 'parent'", f"{field_path}parent", line)
        parent = entry["parent"]
        if parent is not None and not isinstance(parent, str):
            raise PartsError("'parent' debe ser una cadena o null",
                             f"{field_path}parent", line)
        boxes_raw = _require(entry, "boxes", list, field_path, text)
        boxes = [_as_box(b, f"{field_path}boxes[{j}]", text) for j, b in enumerate(boxes_raw)]
        if not boxes:
            raise PartsError("'boxes' no puede estar vacío", f"{field_path}boxes", line)
        exclude = [_as_box(b, f"{field_path}exclude[{j}]", text)
                   for j, b in enumerate(entry.get("exclude", []))]
        pivot_raw = _require(entry, "pivot", (list, tuple), field_path, text)
        if len(pivot_raw) != 3:
            raise PartsError("'pivot' debe tener 3 componentes", f"{field_path}pivot", line)
        flags = [str(f) for f in entry.get("flags", [])]
        collision = str(entry.get("collision", collision_default))
        if collision not in COLLISION_KINDS:
            raise PartsError(f"collision inválido: '{collision}'",
                             f"{field_path}collision", line)
        parts.append(Part(
            id=part_id,
            parent=parent,
            boxes=boxes,  # type: ignore[arg-type]
            pivot=(float(pivot_raw[0]), float(pivot_raw[1]), float(pivot_raw[2])),
            exclude=exclude,  # type: ignore[arg-type]
            flags=flags,
            collision=collision,
            hp=int(entry["hp"]) if entry.get("hp") is not None else None,
            armor=float(entry["armor"]) if entry.get("armor") is not None else None,
            debris_mass=(float(entry["debris_mass"])
                         if entry.get("debris_mass") is not None else None),
            function=str(entry["function"]) if entry.get("function") else None,
            weak_point_id=(str(entry["weak_point_id"])
                           if entry.get("weak_point_id") else None),
            meta=dict(entry.get("meta", {})),
            raw=entry,
        ))

    _validate_graph(parts, text)

    spec = PartsSpec(
        source=str(data.get("source", "")),
        voxel_size=voxel_size,
        origin_voxel=origin,  # type: ignore[arg-type]
        axis_map=axis_map,
        palette_texture=str(data.get("palette_texture") or f"{model_name}_palette.png"),
        emissive_palette_indices=emissive,
        collision_default=collision_default,
        parts=parts,
        root_node=root_node,
        name=model_name,
        grid_size=grid_size,  # type: ignore[arg-type]
        density=float(data.get("density", 220.0)),
        emissive_strength=(float(data["emissive_strength"])
                           if data.get("emissive_strength") is not None else None),
        path=path,
        raw=data,
    )
    return spec


def _default_root_node(name: str) -> str:
    """`arachnodroid` → `ArachnodroidRoot`; `drone_quad` → `DroneQuadRoot`."""
    pascal = "".join(chunk[:1].upper() + chunk[1:] for chunk in name.split("_") if chunk)
    return f"{pascal or 'Model'}Root"


def _validate_graph(parts: list[Part], text: str | None) -> None:
    """Comprueba ids únicos, padres existentes, una sola raíz y ausencia de ciclos (§14.1)."""
    seen: set[str] = set()
    for part in parts:
        if part.id in seen:
            raise PartsError(f"id repetido: '{part.id}'", "parts",
                             _line_of(text, f'"id": "{part.id}"'))
        seen.add(part.id)
    roots = [p for p in parts if p.parent is None]
    if len(roots) != 1:
        raise PartsError(f"debe haber exactamente una parte con parent = null, hay {len(roots)}",
                         "parts")
    flagged = [p for p in parts if p.is_root]
    if len(flagged) > 1:
        raise PartsError(f"hay {len(flagged)} partes con el flag 'root'", "parts")
    if flagged and flagged[0].id != roots[0].id:
        raise PartsError(
            f"el flag 'root' está en '{flagged[0].id}' pero la raíz del árbol es "
            f"'{roots[0].id}'", "parts")
    for part in parts:
        if part.parent is not None and part.parent not in seen:
            raise PartsError(f"'{part.id}' referencia un parent inexistente: '{part.parent}'",
                             "parts", _line_of(text, f'"id": "{part.id}"'))
    index = {p.id: p for p in parts}
    for part in parts:
        walker: str | None = part.id
        depth = 0
        while walker is not None:
            walker = index[walker].parent
            depth += 1
            if depth > len(parts):
                raise PartsError(f"ciclo en la jerarquía que pasa por '{part.id}'", "parts")


def load(path: str | Path, *, name: str | None = None) -> PartsSpec:
    """Lee y valida un `parts.json` desde disco (§12)."""
    file_path = Path(path)
    try:
        text = file_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise PartsError(f"no se pudo leer '{file_path}': {exc}") from exc
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise PartsError(f"JSON inválido: {exc.msg}", "", exc.lineno) from exc
    stem = file_path.name
    for suffix in (".parts.json", ".json"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            break
    return load_dict(data, path=file_path, text=text, name=name or stem)


# --------------------------------------------------------------------------- #
# Asignación                                                                   #
# --------------------------------------------------------------------------- #


def assign(model, spec: PartsSpec) -> dict[str, dict[tuple[int, int, int], int]]:
    """Asigna cada voxel ocupado a la primera parte que lo contenga (§5.1).

    Devuelve ``{part_id: {(x, y, z): palette_index}}`` con la clave extra
    ``"_unassigned"`` siempre presente (puede quedar vacía).
    """
    result: dict[str, dict[tuple[int, int, int], int]] = {p.id: {} for p in spec.parts}
    result[UNASSIGNED] = {}
    ordered = list(spec.parts)
    voxels = model.voxels if hasattr(model, "voxels") else model
    for coord in sorted(voxels):
        x, y, z = coord
        for part in ordered:
            if part.contains(x, y, z):
                result[part.id][coord] = voxels[coord]
                break
        else:
            result[UNASSIGNED][coord] = voxels[coord]
    return result
