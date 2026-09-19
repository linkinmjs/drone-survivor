"""Validador propio de GLB: vuelve a leer el archivo recién escrito y lo comprueba.

No depende de `pygltflib` ni de ninguna otra biblioteca externa: parsea el contenedor
binario y el chunk JSON a mano y verifica, como mínimo:

* magic `glTF`, versión 2 y `byteLength` de la cabecera coherente con el archivo;
* tamaños y alineación de los chunks `JSON` y `BIN`;
* que todo `bufferView` quepa en su buffer y que todo `accessor` quepa en su `bufferView`;
* que cada `mesh` tenga primitivas con `POSITION`, `NORMAL`, `TEXCOORD_0` e índices,
  con el mismo número de vértices en los tres atributos;
* que los índices estén dentro del rango de vértices de su primitiva;
* que `min`/`max` de cada `POSITION` coincidan con los datos reales;
* que todo nodo, malla, material, textura, imagen y sampler referenciado exista;
* que la jerarquía sea un **árbol con una sola raíz** (sin ciclos ni nodos compartidos).
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

__all__ = ["GlbValidationError", "validate", "validate_file"]

_COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
_TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
_REQUIRED_ATTRIBUTES = ("POSITION", "NORMAL", "TEXCOORD_0")


class GlbValidationError(Exception):
    """El GLB escrito no pasa la validación interna."""


def _fail(errors: list[str], message: str) -> None:
    errors.append(message)


def validate(blob: bytes, *, expect_single_root: bool = True) -> dict:
    """Valida un GLB en memoria y devuelve su JSON; lanza `GlbValidationError` si falla."""
    errors: list[str] = []
    if len(blob) < 20:
        raise GlbValidationError("el archivo es demasiado corto para ser un GLB")
    magic, version, declared = struct.unpack_from("<III", blob, 0)
    if magic != 0x46546C67:
        raise GlbValidationError("magic incorrecto: no empieza con 'glTF'")
    if version != 2:
        _fail(errors, f"versión de contenedor {version}, se esperaba 2")
    if declared != len(blob):
        _fail(errors, f"byteLength de la cabecera {declared} != tamaño real {len(blob)}")

    chunks: list[tuple[int, bytes]] = []
    offset = 12
    while offset + 8 <= len(blob):
        length, kind = struct.unpack_from("<II", blob, offset)
        offset += 8
        if length % 4:
            _fail(errors, f"chunk 0x{kind:08x} con longitud {length}, no múltiplo de 4")
        if offset + length > len(blob):
            raise GlbValidationError(f"chunk 0x{kind:08x} se sale del archivo")
        chunks.append((kind, blob[offset:offset + length]))
        offset += length
    if offset != len(blob):
        _fail(errors, "hay bytes sobrantes después del último chunk")
    if not chunks or chunks[0][0] != 0x4E4F534A:
        raise GlbValidationError("el primer chunk no es 'JSON'")

    try:
        gltf = json.loads(chunks[0][1].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GlbValidationError(f"el chunk JSON no es JSON válido: {exc}") from exc

    binary = b""
    for kind, payload in chunks[1:]:
        if kind == 0x004E4942:
            binary = payload
            break

    buffers = gltf.get("buffers", [])
    views = gltf.get("bufferViews", [])
    accessors = gltf.get("accessors", [])
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    materials = gltf.get("materials", [])
    textures = gltf.get("textures", [])
    images = gltf.get("images", [])
    samplers = gltf.get("samplers", [])

    for i, buffer in enumerate(buffers):
        if "uri" not in buffer:
            if buffer.get("byteLength", 0) > len(binary):
                _fail(errors, f"buffers[{i}].byteLength {buffer.get('byteLength')} "
                              f"> chunk BIN ({len(binary)} bytes)")

    for i, view in enumerate(views):
        index = view.get("buffer", -1)
        if not 0 <= index < len(buffers):
            _fail(errors, f"bufferViews[{i}].buffer {index} no existe")
            continue
        end = view.get("byteOffset", 0) + view.get("byteLength", 0)
        if end > buffers[index].get("byteLength", 0):
            _fail(errors, f"bufferViews[{i}] termina en {end}, fuera del buffer "
                          f"({buffers[index].get('byteLength')})")

    for i, accessor in enumerate(accessors):
        view_index = accessor.get("bufferView")
        if view_index is None or not 0 <= view_index < len(views):
            _fail(errors, f"accessors[{i}].bufferView {view_index} no existe")
            continue
        component = _COMPONENT_SIZE.get(accessor.get("componentType", 0))
        elements = _TYPE_COUNT.get(accessor.get("type", ""))
        if component is None or elements is None:
            _fail(errors, f"accessors[{i}] con componentType/type desconocidos")
            continue
        stride = component * elements
        need = accessor.get("byteOffset", 0) + accessor.get("count", 0) * stride
        if need > views[view_index].get("byteLength", 0):
            _fail(errors, f"accessors[{i}] necesita {need} bytes pero su bufferView "
                          f"tiene {views[view_index].get('byteLength')}")

    def read_accessor(index: int) -> list[tuple[float, ...]]:
        accessor = accessors[index]
        view = views[accessor["bufferView"]]
        component = _COMPONENT_SIZE[accessor["componentType"]]
        elements = _TYPE_COUNT[accessor["type"]]
        base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        fmt = {5125: "I", 5123: "H", 5121: "B", 5126: "f"}[accessor["componentType"]]
        out = []
        for n in range(accessor["count"]):
            start = base + n * component * elements
            out.append(struct.unpack_from(f"<{elements}{fmt}", binary, start))
        return out

    for mi, mesh in enumerate(meshes):
        primitives = mesh.get("primitives", [])
        if not primitives:
            _fail(errors, f"meshes[{mi}] ('{mesh.get('name')}') no tiene primitivas")
        for pi, primitive in enumerate(primitives):
            where = f"meshes[{mi}].primitives[{pi}]"
            attributes = primitive.get("attributes", {})
            for name in _REQUIRED_ATTRIBUTES:
                if name not in attributes:
                    _fail(errors, f"{where} no tiene el atributo {name}")
            if "indices" not in primitive:
                _fail(errors, f"{where} no tiene índices")
            counts = {name: accessors[attributes[name]].get("count")
                      for name in attributes if 0 <= attributes[name] < len(accessors)}
            if len(set(counts.values())) > 1:
                _fail(errors, f"{where} tiene atributos con distinto count: {counts}")
            if "material" in primitive and not 0 <= primitive["material"] < len(materials):
                _fail(errors, f"{where}.material {primitive['material']} no existe")
            if errors:
                continue
            vertex_count = counts.get("POSITION", 0)
            indices = [v[0] for v in read_accessor(primitive["indices"])]
            if len(indices) % 3:
                _fail(errors, f"{where} tiene {len(indices)} índices, no múltiplo de 3")
            if indices and (min(indices) < 0 or max(indices) >= vertex_count):
                _fail(errors, f"{where} tiene índices fuera de rango "
                              f"[0, {vertex_count})")
            positions = read_accessor(attributes["POSITION"])
            declared_min = accessors[attributes["POSITION"]].get("min")
            declared_max = accessors[attributes["POSITION"]].get("max")
            if declared_min is None or declared_max is None:
                _fail(errors, f"{where}.POSITION no declara min/max")
            elif positions:
                real_min = [min(p[i] for p in positions) for i in range(3)]
                real_max = [max(p[i] for p in positions) for i in range(3)]
                for i in range(3):
                    if abs(real_min[i] - declared_min[i]) > 1e-6 or \
                       abs(real_max[i] - declared_max[i]) > 1e-6:
                        _fail(errors, f"{where}.POSITION min/max no coinciden con los datos")
                        break

    for i, node in enumerate(nodes):
        if "mesh" in node and not 0 <= node["mesh"] < len(meshes):
            _fail(errors, f"nodes[{i}].mesh {node['mesh']} no existe")
        for child in node.get("children", []):
            if not 0 <= child < len(nodes):
                _fail(errors, f"nodes[{i}].children referencia el nodo {child}, que no existe")

    for i, texture in enumerate(textures):
        if "source" in texture and not 0 <= texture["source"] < len(images):
            _fail(errors, f"textures[{i}].source {texture['source']} no existe")
        if "sampler" in texture and not 0 <= texture["sampler"] < len(samplers):
            _fail(errors, f"textures[{i}].sampler {texture['sampler']} no existe")
    for i, material in enumerate(materials):
        pbr = material.get("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            ref = pbr.get(key)
            if ref and not 0 <= ref.get("index", -1) < len(textures):
                _fail(errors, f"materials[{i}].{key} apunta a una textura inexistente")
        ref = material.get("emissiveTexture")
        if ref and not 0 <= ref.get("index", -1) < len(textures):
            _fail(errors, f"materials[{i}].emissiveTexture apunta a una textura inexistente")

    # -- la jerarquía debe ser un árbol con una sola raíz -------------------- #
    parents: dict[int, int] = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            if not 0 <= child < len(nodes):
                continue
            if child in parents:
                _fail(errors, f"el nodo {child} tiene dos padres: {parents[child]} e {i}")
            elif child == i:
                _fail(errors, f"el nodo {i} es hijo de sí mismo")
            else:
                parents[child] = i
    roots = [i for i in range(len(nodes)) if i not in parents]
    if expect_single_root and len(roots) != 1:
        _fail(errors, f"la jerarquía tiene {len(roots)} raíces, se esperaba 1")
    reachable: set[int] = set()
    stack = list(roots)
    while stack:
        current = stack.pop()
        if current in reachable:
            _fail(errors, f"ciclo o nodo repetido en la jerarquía: {current}")
            break
        reachable.add(current)
        stack.extend(c for c in nodes[current].get("children", []) if 0 <= c < len(nodes))
    if len(reachable) != len(nodes):
        _fail(errors, f"{len(nodes) - len(reachable)} nodos no son alcanzables desde la raíz")

    scenes = gltf.get("scenes", [])
    scene_index = gltf.get("scene", 0)
    if not 0 <= scene_index < len(scenes):
        _fail(errors, f"'scene' apunta a {scene_index}, que no existe")
    else:
        for node_index in scenes[scene_index].get("nodes", []):
            if not 0 <= node_index < len(nodes):
                _fail(errors, f"scenes[{scene_index}].nodes referencia {node_index}, inexistente")

    if errors:
        raise GlbValidationError("GLB inválido:\n  - " + "\n  - ".join(errors))
    return gltf


def validate_file(path: str | Path, *, expect_single_root: bool = True) -> dict:
    """Lee un `.glb` de disco y lo valida."""
    return validate(Path(path).read_bytes(), expect_single_root=expect_single_root)
