"""Lector de archivos `.vox` de MagicaVoxel (versión 150).

Sigue al pie de la letra `docs/05-pipeline-voxel.md` §2:

* La cabecera es `VOX ` + versión (int32 LE). El chunk `MAIN` empieza en el offset 8
  y, como su `contentBytes` es 0, su **primer hijo** empieza en el offset **20**.
* Al recorrer los hijos de `MAIN` hay que *entrar* en la región de hijos
  (avanzar `12 + contentBytes`), no saltarla.
* El índice de paleta de un voxel es **1-based**: el color del índice `i` está en
  `RGBA[i - 1]`.
* `MATL` marca emisivos con `_type == "_emit"`; la fuerza es `_weight` y el
  multiplicador de potencia es `_flux`, con `energy = _weight * 2 ** (_flux - 1)`.
* Si hay grafo (`nTRN` / `nGRP` / `nSHP`) se recorre desde el nodo 0 y se toma el
  primer `modelId`; la traslación `_t` se ignora deliberadamente (§2.4).

Además acepta rutas con la forma ``<archivo.zip>!<miembro>`` para leer el `.vox`
directamente desde un ZIP de ``assets/_raw/`` sin extraerlo al repositorio (§1).
"""

from __future__ import annotations

import struct
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

__all__ = [
    "VoxError",
    "VoxModel",
    "DEFAULT_PALETTE",
    "read",
    "read_bytes",
    "resolve_source",
]

#: Separador de rutas «dentro de un ZIP»: ``Arachnodroid.zip!Package/Arachnoid.vox``.
ZIP_SEPARATOR = "!"


class VoxError(Exception):
    """Error de lectura o de formato de un archivo `.vox`."""


def _build_default_palette() -> tuple[tuple[int, int, int, int], ...]:
    """Reconstruye la paleta por defecto de MagicaVoxel (256 colores, §2.5).

    Estructura canónica del formato: los índices 1..216 forman un cubo RGB de
    6×6×6 con los niveles ``255, 204, 153, 102, 51, 0`` y el **azul** como
    componente que varía más rápido; después vienen cuatro rampas de 10 pasos
    (rojo, verde, azul y gris) con los niveles ``238 … 17``.

    Solo se usa como respaldo: el `.vox` del Arachnodroid trae su chunk `RGBA`.
    """
    levels = (255, 204, 153, 102, 51, 0)
    ramp = (238, 221, 187, 170, 136, 119, 85, 68, 34, 17)
    colors: list[tuple[int, int, int, int]] = []
    for r in levels:
        for g in levels:
            for b in levels:
                colors.append((r, g, b, 255))
    for v in ramp:
        colors.append((v, 0, 0, 255))
    for v in ramp:
        colors.append((0, v, 0, 255))
    for v in ramp:
        colors.append((0, 0, v, 255))
    for v in ramp:
        colors.append((v, v, v, 255))
    assert len(colors) == 256
    return tuple(colors)


#: Paleta por defecto de MagicaVoxel: 256 colores RGBA, el índice `i` en `[i - 1]`.
DEFAULT_PALETTE: tuple[tuple[int, int, int, int], ...] = _build_default_palette()


@dataclass
class VoxModel:
    """Un modelo voxel ya leído.

    Atributos:
        size: dimensiones ``(x, y, z)`` de la retícula de MagicaVoxel.
        voxels: ``{(x, y, z): palette_index}`` con el índice de paleta 1-based.
        palette: 256 tuplas ``(r, g, b, a)``; el color del índice `i` está en ``[i - 1]``.
        materials: ``{palette_index: {clave: valor}}`` con los diccionarios `MATL` crudos.
        version: versión del archivo `.vox` (150 en el Arachnodroid).
    """

    size: tuple[int, int, int]
    voxels: dict[tuple[int, int, int], int]
    palette: list[tuple[int, int, int, int]]
    materials: dict[int, dict[str, str]] = field(default_factory=dict)
    version: int = 150

    def occupied_bbox(self) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
        """Devuelve ``(min, max)`` inclusivos de los voxels ocupados, en índices."""
        if not self.voxels:
            return (0, 0, 0), (-1, -1, -1)
        xs = [v[0] for v in self.voxels]
        ys = [v[1] for v in self.voxels]
        zs = [v[2] for v in self.voxels]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def color(self, index: int) -> tuple[int, int, int, int]:
        """Color RGBA del índice de paleta 1-based `index`."""
        return self.palette[index - 1]

    def emissive_indices(self) -> list[int]:
        """Índices 1-based cuyo `MATL` declara ``_type == "_emit"`` y que se usan.

        Los `MATL` de índices que ningún voxel utiliza se descartan (§2.3).
        """
        used = set(self.voxels.values())
        out = [i for i, mat in sorted(self.materials.items())
               if i in used and mat.get("_type") == "_emit"]
        return out

    def emissive_energy(self, index: int) -> float:
        """Energía de emisión del índice `index`: ``_weight * 2 ** (_flux - 1)`` (§2.3).

        `_weight` tiene prioridad sobre un `_emit` numérico suelto de versiones antiguas.
        """
        mat = self.materials.get(index, {})
        weight_raw = mat.get("_weight")
        if weight_raw is None:
            weight_raw = mat.get("_emit")
        try:
            weight = float(weight_raw) if weight_raw is not None else 1.0
        except (TypeError, ValueError):
            weight = 1.0
        try:
            flux = int(float(mat.get("_flux", 1)))
        except (TypeError, ValueError):
            flux = 1
        flux = max(1, min(5, flux))
        return weight * (2.0 ** (flux - 1))


# --------------------------------------------------------------------------- #
# Lectura de chunks                                                            #
# --------------------------------------------------------------------------- #


def _read_dict(data: bytes, off: int) -> tuple[dict[str, str], int]:
    """Lee un `DICT` de VOX y devuelve ``(diccionario, offset_siguiente)``."""
    (num_pairs,) = struct.unpack_from("<i", data, off)
    off += 4
    out: dict[str, str] = {}
    for _ in range(num_pairs):
        (klen,) = struct.unpack_from("<i", data, off)
        off += 4
        key = data[off:off + klen].decode("utf-8", "replace")
        off += klen
        (vlen,) = struct.unpack_from("<i", data, off)
        off += 4
        value = data[off:off + vlen].decode("utf-8", "replace")
        off += vlen
        out[key] = value
    return out, off


def _iter_chunks(data: bytes, start: int, end: int):
    """Itera los chunks entre `start` y `end`, devolviendo ``(id, off, content, children)``."""
    off = start
    while off + 12 <= end:
        chunk_id = data[off:off + 4].decode("ascii", "replace")
        content, children = struct.unpack_from("<ii", data, off + 4)
        if content < 0 or children < 0:
            raise VoxError(f"chunk '{chunk_id}' con tamaños negativos en el offset {off}")
        yield chunk_id, off + 12, content, children
        off += 12 + content + children


def _pick_model_from_graph(
    transforms: dict[int, tuple[int]],
    groups: dict[int, list[int]],
    shapes: dict[int, list[int]],
) -> int | None:
    """Recorre el grafo desde el nodo 0 y devuelve el primer `modelId` (§2.4)."""
    seen: set[int] = set()
    stack = [0]
    while stack:
        node = stack.pop(0)
        if node in seen:
            continue
        seen.add(node)
        if node in shapes and shapes[node]:
            return shapes[node][0]
        if node in transforms:
            stack.insert(0, transforms[node][0])
        elif node in groups:
            for child in reversed(groups[node]):
                stack.insert(0, child)
    return None


def read_bytes(data: bytes, origin: str = "<bytes>") -> VoxModel:
    """Parsea el contenido de un `.vox` ya cargado en memoria."""
    if len(data) < 20 or data[0:4] != b"VOX ":
        raise VoxError(f"{origin}: no empieza con el magic 'VOX '")
    (version,) = struct.unpack_from("<i", data, 4)
    main_id = data[8:12].decode("ascii", "replace")
    if main_id != "MAIN":
        raise VoxError(f"{origin}: el chunk en el offset 8 es '{main_id}', no 'MAIN'")
    main_content, main_children = struct.unpack_from("<ii", data, 12)
    first_child = 8 + 12 + main_content  # 20 con contentBytes = 0 (§2.1)
    end = min(len(data), first_child + main_children)

    sizes: list[tuple[int, int, int]] = []
    models: list[dict[tuple[int, int, int], int]] = []
    palette: list[tuple[int, int, int, int]] | None = None
    materials: dict[int, dict[str, str]] = {}
    transforms: dict[int, tuple[int]] = {}
    groups: dict[int, list[int]] = {}
    shapes: dict[int, list[int]] = {}

    for chunk_id, off, content, _children in _iter_chunks(data, first_child, end):
        if chunk_id == "SIZE":
            sizes.append(tuple(struct.unpack_from("<iii", data, off)))  # type: ignore[arg-type]
        elif chunk_id == "XYZI":
            (count,) = struct.unpack_from("<i", data, off)
            voxels: dict[tuple[int, int, int], int] = {}
            base = off + 4
            for i in range(count):
                x, y, z, index = data[base + i * 4: base + i * 4 + 4]
                voxels[(x, y, z)] = index
            models.append(voxels)
        elif chunk_id == "RGBA":
            palette = [tuple(data[off + i * 4: off + i * 4 + 4])  # type: ignore[misc]
                       for i in range(256)]
        elif chunk_id == "MATL":
            (mat_id,) = struct.unpack_from("<i", data, off)
            props, _ = _read_dict(data, off + 4)
            materials[mat_id] = props
        elif chunk_id == "nTRN":
            (node_id,) = struct.unpack_from("<i", data, off)
            _attrs, cur = _read_dict(data, off + 4)
            (child_id,) = struct.unpack_from("<i", data, cur)
            transforms[node_id] = (child_id,)
        elif chunk_id == "nGRP":
            (node_id,) = struct.unpack_from("<i", data, off)
            _attrs, cur = _read_dict(data, off + 4)
            (num_children,) = struct.unpack_from("<i", data, cur)
            cur += 4
            groups[node_id] = list(struct.unpack_from(f"<{num_children}i", data, cur)) \
                if num_children else []
        elif chunk_id == "nSHP":
            (node_id,) = struct.unpack_from("<i", data, off)
            _attrs, cur = _read_dict(data, off + 4)
            (num_models,) = struct.unpack_from("<i", data, cur)
            cur += 4
            model_ids: list[int] = []
            for _ in range(num_models):
                (model_id,) = struct.unpack_from("<i", data, cur)
                cur += 4
                _mattrs, cur = _read_dict(data, cur)
                model_ids.append(model_id)
            shapes[node_id] = model_ids
        # LAYR y PACK se ignoran a propósito (§2.2).

    if not sizes or not models:
        raise VoxError(f"{origin}: no se encontró ningún par SIZE + XYZI")

    model_index = 0
    if shapes:
        picked = _pick_model_from_graph(transforms, groups, shapes)
        if picked is not None and 0 <= picked < len(models):
            model_index = picked

    return VoxModel(
        size=sizes[min(model_index, len(sizes) - 1)],
        voxels=models[model_index],
        palette=palette if palette is not None else list(DEFAULT_PALETTE),
        materials=materials,
        version=version,
    )


def resolve_source(source: str, base_dir: Path | str | None = None) -> str:
    """Normaliza una ruta de `source`, relativa a `base_dir` si es relativa.

    Acepta la forma ``<ruta.zip>!<miembro>`` y deja intacta la parte del miembro.
    """
    zip_path, sep, member = source.partition(ZIP_SEPARATOR)
    path = Path(zip_path)
    if base_dir is not None and not path.is_absolute():
        path = Path(base_dir) / path
    return f"{path}{sep}{member}" if sep else str(path)


def read(path: str | Path) -> VoxModel:
    """Lee un `.vox` desde disco o desde un miembro de un ZIP (``archivo.zip!miembro``)."""
    text = str(path)
    zip_path, sep, member = text.partition(ZIP_SEPARATOR)
    if sep:
        if not member:
            raise VoxError(f"{text}: falta el nombre del miembro después de '{ZIP_SEPARATOR}'")
        try:
            with zipfile.ZipFile(zip_path) as archive:
                data = archive.read(member)
        except (OSError, KeyError, zipfile.BadZipFile) as exc:
            raise VoxError(f"no se pudo leer '{member}' de '{zip_path}': {exc}") from exc
        return read_bytes(data, origin=text)
    try:
        data = Path(text).read_bytes()
    except OSError as exc:
        raise VoxError(f"no se pudo leer '{text}': {exc}") from exc
    return read_bytes(data, origin=text)
