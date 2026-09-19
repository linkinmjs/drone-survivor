"""Serialización glTF 2.0 binaria (`.glb`) escrita a mano, sin dependencias (§7.1 de `docs/05`).

Decisiones fijadas por el documento:

* **Un único buffer** (chunk `BIN`) con todos los vértices e índices, alineado a 4 bytes.
* Un `accessor` por atributo y por primitiva: `POSITION` (VEC3 float, con `min`/`max`),
  `NORMAL` (VEC3 float), `TEXCOORD_0` (VEC2 float) e índices (`UNSIGNED_INT`).
* Un `mesh` por parte, con una `primitive` por material presente (1 o 2).
* Un `node` por parte, con `name = id` y ``translation = pivot_world(parte) − pivot_world(padre)``.
  Sin `rotation` ni `scale`.
* Un nodo raíz extra `<Enemy>Root` cuelga de la escena y tiene como hijo la parte `root`.
* Materiales `voxel_opaque` y `voxel_emissive`; este último con `KHR_materials_emissive_strength`.
* La paleta se referencia **por URI externa**, no embebida, para que Godot la importe con
  su propio preset (filtro nearest, sin mipmaps).

La salida es determinista: misma entrada ⇒ mismo GLB byte a byte.
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

from . import VERSION
from .mesher import EMISSIVE, OPAQUE, PartMesh
from .parts import PartsSpec

__all__ = ["GlbInfo", "write", "MATERIAL_NAMES"]

#: Nombres de los dos materiales del GLB, en el orden en que se escriben.
MATERIAL_NAMES = (OPAQUE, EMISSIVE)

_GLB_MAGIC = 0x46546C67       # 'glTF'
_CHUNK_JSON = 0x4E4F534A      # 'JSON'
_CHUNK_BIN = 0x004E4942       # 'BIN\0'

_FLOAT = 5126
_UNSIGNED_INT = 5125
_ARRAY_BUFFER = 34962
_ELEMENT_ARRAY_BUFFER = 34963
_NEAREST = 9728
_CLAMP_TO_EDGE = 33071


@dataclass
class GlbInfo:
    """Resumen de lo escrito, para el reporte y las comprobaciones."""

    path: Path
    byte_length: int
    node_count: int
    mesh_count: int
    primitive_count: int
    triangle_count: int
    aabb_min: tuple[float, float, float] = (0.0, 0.0, 0.0)
    aabb_max: tuple[float, float, float] = (0.0, 0.0, 0.0)
    emissive_strength: float = 1.0
    node_world: dict[str, tuple[float, float, float]] = field(default_factory=dict)

    @property
    def total_height(self) -> float:
        """Altura total del modelo en metros (eje Y de Godot)."""
        return self.aabb_max[1] - self.aabb_min[1]


def _f32(value: float) -> float:
    """Redondea a la precisión real de float32 para que `min`/`max` casen con el binario."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


class _BufferBuilder:
    """Acumula bytes del chunk `BIN` y crea `bufferViews` alineados a 4."""

    def __init__(self) -> None:
        self.data = bytearray()
        self.views: list[dict] = []

    def add(self, payload: bytes, target: int | None) -> int:
        while len(self.data) % 4:
            self.data.append(0)
        offset = len(self.data)
        self.data.extend(payload)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(payload)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        return len(self.views) - 1


def write(path: str | Path, meshes: dict[str, PartMesh], spec: PartsSpec,
          *, emissive_strength: float | None = None,
          generator: str | None = None) -> GlbInfo:
    """Escribe el GLB jerárquico de `spec` con las mallas de `meshes` (§12).

    Args:
        path: ruta del `.glb` de salida.
        meshes: ``{part_id: PartMesh}`` producido por `mesher.build_all`.
        spec: el `parts.json` validado.
        emissive_strength: valor de `KHR_materials_emissive_strength`; si es `None` se usa
            `spec.emissive_strength` y, si tampoco está, 1.0.
        generator: cadena `asset.generator`; por defecto ``voxsplit <versión>``.

    Returns:
        Un `GlbInfo` con el bbox global, los conteos y la posición mundial de cada nodo.
    """
    out_path = Path(path)
    strength = emissive_strength
    if strength is None:
        strength = spec.emissive_strength if spec.emissive_strength is not None else 1.0

    buffer = _BufferBuilder()
    accessors: list[dict] = []
    gltf_meshes: list[dict] = []
    mesh_index_of: dict[str, int] = {}

    uses_emissive = any(EMISSIVE in meshes[p.id].surfaces
                        for p in spec.parts if p.id in meshes)

    materials: list[dict] = [{
        "name": "voxel_opaque",
        "doubleSided": False,
        "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0},
            "metallicFactor": 0.0,
            "roughnessFactor": 0.85,
        },
    }]
    material_index = {OPAQUE: 0}
    if uses_emissive:
        materials.append({
            "name": "voxel_emissive",
            "doubleSided": False,
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.85,
            },
            "emissiveTexture": {"index": 0},
            "emissiveFactor": [1.0, 1.0, 1.0],
            "extensions": {
                "KHR_materials_emissive_strength": {"emissiveStrength": float(strength)},
            },
        })
        material_index[EMISSIVE] = 1

    primitive_count = 0
    triangle_count = 0
    for part in spec.parts:
        mesh = meshes.get(part.id)
        if mesh is None or mesh.is_empty:
            continue
        primitives: list[dict] = []
        for material in MATERIAL_NAMES:
            surface = mesh.surfaces.get(material)
            if surface is None or not surface.indices:
                continue
            positions = [tuple(_f32(c) for c in v) for v in surface.positions]
            pos_view = buffer.add(
                b"".join(struct.pack("<3f", *v) for v in positions), _ARRAY_BUFFER)
            nrm_view = buffer.add(
                b"".join(struct.pack("<3f", *v) for v in surface.normals), _ARRAY_BUFFER)
            uv_view = buffer.add(
                b"".join(struct.pack("<2f", *v) for v in surface.uvs), _ARRAY_BUFFER)
            idx_view = buffer.add(
                struct.pack(f"<{len(surface.indices)}I", *surface.indices),
                _ELEMENT_ARRAY_BUFFER)

            lo = [min(v[i] for v in positions) for i in range(3)]
            hi = [max(v[i] for v in positions) for i in range(3)]
            pos_accessor = len(accessors)
            accessors.append({
                "bufferView": pos_view, "componentType": _FLOAT,
                "count": len(positions), "type": "VEC3", "min": lo, "max": hi,
            })
            accessors.append({
                "bufferView": nrm_view, "componentType": _FLOAT,
                "count": len(surface.normals), "type": "VEC3",
            })
            accessors.append({
                "bufferView": uv_view, "componentType": _FLOAT,
                "count": len(surface.uvs), "type": "VEC2",
            })
            accessors.append({
                "bufferView": idx_view, "componentType": _UNSIGNED_INT,
                "count": len(surface.indices), "type": "SCALAR",
            })
            primitives.append({
                "attributes": {
                    "POSITION": pos_accessor,
                    "NORMAL": pos_accessor + 1,
                    "TEXCOORD_0": pos_accessor + 2,
                },
                "indices": pos_accessor + 3,
                "material": material_index[material],
                "mode": 4,
            })
            primitive_count += 1
            triangle_count += surface.triangle_count
        if primitives:
            mesh_index_of[part.id] = len(gltf_meshes)
            gltf_meshes.append({"name": part.id, "primitives": primitives})

    # -- nodos ------------------------------------------------------------- #
    nodes: list[dict] = [{"name": spec.root_node}]
    node_index_of: dict[str, int] = {}
    for part in spec.parts:
        node_index_of[part.id] = len(nodes)
        parent_pivot = (0.0, 0.0, 0.0)
        if part.parent is not None:
            parent = spec.by_id()[part.parent]
            parent_pivot = spec.pivot_world(parent)
        pivot = spec.pivot_world(part)
        node: dict = {"name": part.id}
        if part.id in mesh_index_of:
            node["mesh"] = mesh_index_of[part.id]
        node["translation"] = [_f32(pivot[i] - parent_pivot[i]) for i in range(3)]
        nodes.append(node)
    for part in spec.parts:
        children = [node_index_of[child.id] for child in spec.children_of(part.id)]
        if children:
            nodes[node_index_of[part.id]]["children"] = children
    nodes[0]["children"] = [node_index_of[spec.root_part().id]]

    # -- bbox global y posiciones mundiales -------------------------------- #
    node_world: dict[str, tuple[float, float, float]] = {}
    lo_all = [float("inf")] * 3
    hi_all = [float("-inf")] * 3
    for part in spec.parts:
        world = spec.pivot_world(part)
        node_world[part.id] = world
        mesh = meshes.get(part.id)
        if mesh is None or mesh.is_empty:
            continue
        for i in range(3):
            lo_all[i] = min(lo_all[i], world[i] + mesh.aabb_min[i])
            hi_all[i] = max(hi_all[i], world[i] + mesh.aabb_max[i])
    if lo_all[0] == float("inf"):
        lo_all = [0.0, 0.0, 0.0]
        hi_all = [0.0, 0.0, 0.0]

    gltf: dict = {
        "asset": {
            "version": "2.0",
            "generator": generator or f"voxsplit {VERSION}",
        },
    }
    if uses_emissive:
        gltf["extensionsUsed"] = ["KHR_materials_emissive_strength"]
    gltf.update({
        "scene": 0,
        "scenes": [{"name": spec.root_node, "nodes": [0]}],
        "nodes": nodes,
        "meshes": gltf_meshes,
        "materials": materials,
        "textures": [{"sampler": 0, "source": 0}],
        "images": [{"uri": spec.palette_texture, "mimeType": "image/png"}],
        "samplers": [{
            "magFilter": _NEAREST, "minFilter": _NEAREST,
            "wrapS": _CLAMP_TO_EDGE, "wrapT": _CLAMP_TO_EDGE,
        }],
        "accessors": accessors,
        "bufferViews": buffer.views,
        "buffers": [{"byteLength": len(buffer.data)}],
    })

    json_bytes = json.dumps(gltf, separators=(",", ":"),
                            ensure_ascii=False, allow_nan=False).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_bytes = bytes(buffer.data)
    bin_bytes += b"\x00" * ((4 - len(bin_bytes) % 4) % 4)

    total = 12 + 8 + len(json_bytes) + (8 + len(bin_bytes) if bin_bytes else 0)
    blob = bytearray()
    blob += struct.pack("<III", _GLB_MAGIC, 2, total)
    blob += struct.pack("<II", len(json_bytes), _CHUNK_JSON) + json_bytes
    if bin_bytes:
        blob += struct.pack("<II", len(bin_bytes), _CHUNK_BIN) + bin_bytes

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(bytes(blob))

    return GlbInfo(
        path=out_path,
        byte_length=len(blob),
        node_count=len(nodes),
        mesh_count=len(gltf_meshes),
        primitive_count=primitive_count,
        triangle_count=triangle_count,
        aabb_min=tuple(lo_all),  # type: ignore[arg-type]
        aabb_max=tuple(hi_all),  # type: ignore[arg-type]
        emissive_strength=float(strength),
        node_world=node_world,
    )


def write_palette_png(path: str | Path, palette: Sequence[Sequence[int]]) -> None:
    """Escribe el PNG 256×1 RGBA de la paleta: el píxel `i − 1` lleva `RGBA[i − 1]` (§6.2)."""
    from PIL import Image

    image = Image.new("RGBA", (256, 1))
    image.putdata([tuple(int(c) for c in palette[i][:4]) for i in range(256)])
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out, format="PNG", optimize=True)
