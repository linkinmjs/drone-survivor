"""CLI de `voxsplit`: `inspect`, `build` y `preview` (§8 y §14.1 de `docs/05`).

    python -m voxsplit inspect <archivo.vox>
    python -m voxsplit objinspect <archivo.obj | archivo.zip!miembro.obj> [--step <u>]
    python -m voxsplit town [<nuke_town.json>] --out <dir>
    python -m voxsplit build <parts.json | models.modulo> --out <dir> [--preview] [--report]
                             [--allow-unassigned] [--preview-out <dir>]
    python -m voxsplit preview <parts.json | models.modulo> [--out <dir>]

Códigos de salida (§8):

===========  ==========================================================
 0           todo bien
 1           hay voxels en `_unassigned` sin `--allow-unassigned`, o falla
             alguno de los criterios declarados en `expect`
 2           el `parts.json` (o el `.vox`) es inválido
===========  ==========================================================

Se puede ejecutar de dos formas equivalentes:

* desde ``godot/tools``:   ``python -m voxsplit build ../enemies/...``
* desde cualquier sitio:   ``python <repo>/godot/tools/voxsplit/__main__.py build ...``
  (el propio archivo añade su carpeta padre a ``sys.path``).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import importlib
import os
import sys
from collections import Counter, deque
from pathlib import Path

_PACKAGE_PARENT = str(Path(__file__).resolve().parent.parent)
if _PACKAGE_PARENT not in sys.path:
    sys.path.insert(0, _PACKAGE_PARENT)

from voxsplit import VERSION                                      # noqa: E402
from voxsplit import compose, glbvalidate, glbwriter, mesher, preview  # noqa: E402
from voxsplit import parts as parts_module                        # noqa: E402
from voxsplit import objvox                                       # noqa: E402
from voxsplit import voxreader                                    # noqa: E402
from voxsplit.jsonio import dumps                                 # noqa: E402
from voxsplit.parts import UNASSIGNED, PartsError, PartsSpec      # noqa: E402
from voxsplit.voxreader import VoxError, VoxModel                 # noqa: E402

EXIT_OK = 0
EXIT_FAILED_CRITERIA = 1
EXIT_INVALID = 2

#: Prefijo que identifica un modelo procedural en lugar de una ruta a `parts.json`.
MODEL_PREFIX = "models."


# --------------------------------------------------------------------------- #
# Carga unificada: `parts.json` de disco o modelo procedural                    #
# --------------------------------------------------------------------------- #


def _load_target(target: str) -> tuple[PartsSpec, VoxModel, str]:
    """Devuelve ``(spec, modelo, nombre)`` a partir de una ruta o de `models.<modulo>`."""
    if target.startswith(MODEL_PREFIX) and not Path(target).exists():
        module = importlib.import_module(f"voxsplit.{target}")
        data = module.build()
        header = dict(data.get("header", {}))
        header["parts"] = data["parts"]
        name = str(header.get("name") or target.split(".")[-1])
        spec = parts_module.load_dict(header, path=None, text=None, name=name)
        model = VoxModel(
            size=tuple(data["size"]),                      # type: ignore[arg-type]
            voxels=dict(data["voxels"]),
            palette=[tuple(c) for c in data["palette"]],   # type: ignore[misc]
            materials={},
        )
        return spec, model, name

    spec = parts_module.load(target)
    if not spec.source:
        raise PartsError("el parts.json no declara 'source'", "source")
    base = spec.path.parent if spec.path else Path.cwd()
    model = voxreader.read(voxreader.resolve_source(spec.source, base))
    return spec, model, spec.name


def _timestamp() -> str:
    """Marca de tiempo UTC ISO-8601; respeta `SOURCE_DATE_EPOCH` para builds reproducibles."""
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch and epoch.isdigit():
        moment = _dt.datetime.fromtimestamp(int(epoch), _dt.timezone.utc)
    else:
        moment = _dt.datetime.now(_dt.timezone.utc)
    return moment.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _write_text(path: Path, text: str) -> None:
    """Escribe texto UTF-8 con saltos `\\n`, sin BOM y sin traducción de fin de línea."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


# --------------------------------------------------------------------------- #
# inspect                                                                       #
# --------------------------------------------------------------------------- #


def _components(voxels: dict[tuple[int, int, int], int],
                keys: set[tuple[int, int, int]]) -> list[list[tuple[int, int, int]]]:
    """Componentes conexas por 6 vecinos dentro de `keys`."""
    remaining = set(keys)
    out: list[list[tuple[int, int, int]]] = []
    while remaining:
        seed = min(remaining)
        remaining.discard(seed)
        group = [seed]
        queue = deque([seed])
        while queue:
            x, y, z = queue.popleft()
            for neighbour in ((x + 1, y, z), (x - 1, y, z), (x, y + 1, z),
                              (x, y - 1, z), (x, y, z + 1), (x, y, z - 1)):
                if neighbour in remaining:
                    remaining.discard(neighbour)
                    group.append(neighbour)
                    queue.append(neighbour)
        out.append(group)
    out.sort(key=lambda g: (-len(g), min(g)))
    return out


def _bbox(group) -> str:
    xs = [c[0] for c in group]
    ys = [c[1] for c in group]
    zs = [c[2] for c in group]
    return f"x[{min(xs)},{max(xs)}] y[{min(ys)},{max(ys)}] z[{min(zs)},{max(zs)}]"


def cmd_inspect(args: argparse.Namespace) -> int:
    """Imprime tamaño, bbox, histograma, emisivos y componentes conexas de un `.vox` (§5.3)."""
    try:
        model = voxreader.read(args.file)
    except VoxError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_INVALID

    lo, hi = model.occupied_bbox()
    print(f"archivo          : {args.file}")
    print(f"versión .vox     : {model.version}")
    print(f"tamaño           : {model.size[0]} x {model.size[1]} x {model.size[2]}")
    print(f"voxels ocupados  : {len(model.voxels)}")
    print(f"bbox ocupado     : x[{lo[0]},{hi[0]}] y[{lo[1]},{hi[1]}] z[{lo[2]},{hi[2]}]")

    histogram = Counter(model.voxels.values())
    emissive = set(model.emissive_indices())
    print()
    print("histograma de índices de paleta (1-based):")
    print(f"  {'idx':>4}  {'voxels':>7}  {'color RGB':<16} emisivo")
    for index, count in sorted(histogram.items()):
        r, g, b, _a = model.color(index)
        mark = f"sí  (energy {model.emissive_energy(index):.4g})" if index in emissive else "no"
        print(f"  {index:>4}  {count:>7}  ({r:>3}, {g:>3}, {b:>3})     {mark}")
    print()
    print(f"emissive_palette_indices sugerido: {sorted(emissive)}")

    print()
    print("componentes conexas (6 vecinos) sobre todo el volumen:")
    for i, group in enumerate(_components(model.voxels, set(model.voxels))[:args.max_components]):
        print(f"  #{i:<3} {len(group):>6} voxels   {_bbox(group)}")

    print()
    print("componentes conexas por índice de paleta:")
    for index, _count in sorted(histogram.items()):
        keys = {c for c, i in model.voxels.items() if i == index}
        groups = _components(model.voxels, keys)
        print(f"  índice {index:>3}: {len(groups)} componente(s)")
        for i, group in enumerate(groups[:args.max_components]):
            print(f"      #{i:<3} {len(group):>6} voxels   {_bbox(group)}")
        if len(groups) > args.max_components:
            print(f"      … y {len(groups) - args.max_components} más")
    return EXIT_OK


# --------------------------------------------------------------------------- #
# build                                                                         #
# --------------------------------------------------------------------------- #


def _sidecar(spec: PartsSpec, meshes: dict, info: glbwriter.GlbInfo, model: VoxModel,
             unassigned: int, energies: dict[int, dict]) -> dict:
    """Construye el sidecar: copia del `parts.json` de entrada más el bloque `metadata` (§7.2).

    La parte sintética `_unassigned` de `--allow-unassigned` aparece en `metadata.parts`
    (para poder verla en el diff) pero **no** en `parts[]` ni en `metadata.part_count`.
    """
    data = dict(spec.raw)
    data["parts"] = [part.raw for part in spec.parts if not part.meta.get("synthetic")]

    per_part: dict[str, dict] = {}
    voxel_volume = spec.voxel_size ** 3
    for part in spec.parts:
        mesh = meshes[part.id]
        world = info.node_world[part.id]
        parent_world = (info.node_world[part.parent] if part.parent else (0.0, 0.0, 0.0))
        per_part[part.id] = {
            "parent": part.parent,
            "aabb_min": list(mesh.aabb_min),
            "aabb_max": list(mesh.aabb_max),
            "center_of_mass": list(mesh.center_of_mass),
            "voxel_count": mesh.voxel_count,
            "triangle_count": mesh.triangle_count,
            "estimated_mass": mesh.voxel_count * voxel_volume * spec.density,
            "has_emissive_surface": mesh.has_emissive,
            "pivot_world": list(world),
            "translation": [world[i] - parent_world[i] for i in range(3)],
        }

    data["metadata"] = {
        "voxsplit_version": VERSION,
        "generated_at": _timestamp(),
        "source": spec.source,
        "part_count": sum(1 for p in spec.parts if not p.meta.get("synthetic")),
        "voxel_count": sum(m.voxel_count for m in meshes.values()),
        "triangle_count": info.triangle_count,
        "quad_count": sum(m.quad_count for m in meshes.values()),
        "unassigned_count": unassigned,
        "total_height": info.total_height,
        "aabb_min": list(info.aabb_min),
        "aabb_max": list(info.aabb_max),
        "footprint": [info.aabb_max[0] - info.aabb_min[0],
                      info.aabb_max[2] - info.aabb_min[2]],
        "density": spec.density,
        "emissive_strength": info.emissive_strength,
        "emissive_indices": {str(k): v for k, v in sorted(energies.items())},
        "root_node": spec.root_node,
        "parts": per_part,
    }
    return data


def _report(spec: PartsSpec, meshes: dict, info: glbwriter.GlbInfo, model: VoxModel,
            assignment: dict, failures: list[str], energies: dict[int, dict]) -> str:
    """Genera `report.txt` con la tabla de §4.4 recalculada, para que el diff sea legible."""
    lines: list[str] = []
    add = lines.append
    add(f"voxsplit {VERSION} — reporte de «{spec.name}»")
    add(f"generado            : {_timestamp()}")
    add(f"origen              : {spec.source}")
    add(f"voxel_size          : {spec.voxel_size} m")
    add(f"origin_voxel        : {list(spec.origin_voxel)}")
    add(f"axis_map            : {spec.axis_map.raw} (det {spec.axis_map.determinant:+.0f})")
    add("")
    add(f"{'parte':<18} {'padre':<16} {'vox':>5} {'tris':>6} {'quads':>6} "
        f"{'emis':>5}  bbox local (m)")
    add("-" * 118)
    for part in spec.parts:
        mesh = meshes[part.id]
        bbox = (f"[{mesh.aabb_min[0]:7.3f},{mesh.aabb_min[1]:7.3f},{mesh.aabb_min[2]:7.3f}] "
                f"[{mesh.aabb_max[0]:7.3f},{mesh.aabb_max[1]:7.3f},{mesh.aabb_max[2]:7.3f}]")
        add(f"{part.id:<18} {str(part.parent or '-'):<16} {mesh.voxel_count:>5} "
            f"{mesh.triangle_count:>6} {mesh.quad_count:>6} "
            f"{('sí' if mesh.has_emissive else 'no'):>5}  {bbox}")
    add("-" * 118)
    total_vox = sum(m.voxel_count for m in meshes.values())
    total_quads = sum(m.quad_count for m in meshes.values())
    add(f"{'TOTAL':<18} {'':<16} {total_vox:>5} {info.triangle_count:>6} {total_quads:>6}")
    add("")
    declared = [p for p in spec.parts if not p.meta.get("synthetic")]
    weak = sum(1 for p in declared if p.is_weak_point)
    add(f"partes              : {len(declared)} "
        f"({len(declared) - weak} estructurales + {weak} puntos débiles)")
    add(f"voxels del .vox     : {len(model.voxels)}")
    add(f"voxels asignados    : {total_vox}")
    unassigned = assignment.get(UNASSIGNED, {})
    add(f"voxels sin asignar  : {len(unassigned)}")
    if unassigned:
        xs = [c[0] for c in unassigned]
        ys = [c[1] for c in unassigned]
        zs = [c[2] for c in unassigned]
        add(f"  bbox de _unassigned: x[{min(xs)},{max(xs)}] "
            f"y[{min(ys)},{max(ys)}] z[{min(zs)},{max(zs)}]")
        for coord in sorted(unassigned)[:40]:
            add(f"    {coord}  índice {unassigned[coord]}")
        if len(unassigned) > 40:
            add(f"    … y {len(unassigned) - 40} más")
    add(f"triángulos          : {info.triangle_count}")
    add(f"quads (greedy)      : {total_quads}")
    add(f"primitivas / mallas : {info.primitive_count} / {info.mesh_count}")
    add(f"nodos del GLB       : {info.node_count} (1 raíz '{spec.root_node}' "
        f"+ {len(spec.parts)} nodos de parte)")
    add(f"bbox del modelo (m) : min {[round(c, 4) for c in info.aabb_min]}  "
        f"max {[round(c, 4) for c in info.aabb_max]}")
    add(f"altura total (m)    : {info.total_height:.4f}")
    add(f"huella X × Z (m)    : {info.aabb_max[0] - info.aabb_min[0]:.4f} × "
        f"{info.aabb_max[2] - info.aabb_min[2]:.4f}")
    add(f"GLB                 : {info.byte_length} bytes")
    add("")
    add("índices emisivos:")
    for index, data in sorted(energies.items()):
        add(f"  {index:>3}  RGB {tuple(data['color'][:3])}  voxels {data['voxels']:>4}  "
            f"weight {data['weight']}  flux {data['flux']}  energy {data['energy']:.4g}")
    add(f"  emissiveStrength del material voxel_emissive: {info.emissive_strength:.4g}")
    add("")
    add("jerarquía:")
    for line in _tree_lines(spec):
        add("  " + line)
    add("")
    if failures:
        add(f"CHECK voxsplit: FAIL ({len(failures)} fallos)")
        for failure in failures:
            add(f"  - {failure}")
    else:
        add("CHECK voxsplit: OK")
    return "\n".join(lines) + "\n"


def _tree_lines(spec: PartsSpec) -> list[str]:
    """Dibuja la jerarquía padre-hijo como árbol de texto, desde el nodo raíz del GLB."""
    out = [spec.root_node]
    _tree_branch(spec, spec.root_part().id, "", True, out)
    return out


def _tree_branch(spec: PartsSpec, part_id: str, prefix: str, last: bool,
                 out: list[str]) -> None:
    """Añade a `out` la rama de `part_id` con los conectores del árbol."""
    out.append(f"{prefix}{'`-- ' if last else '|-- '}{part_id}")
    children = spec.children_of(part_id)
    child_prefix = prefix + ("    " if last else "|   ")
    for i, child in enumerate(children):
        _tree_branch(spec, child.id, child_prefix, i == len(children) - 1, out)


def _check_expectations(spec: PartsSpec, info: glbwriter.GlbInfo,
                        unassigned: int) -> list[str]:
    """Comprueba el bloque opcional `expect` del `parts.json` (§14.1 sin constantes)."""
    expect = spec.raw.get("expect") or {}
    failures: list[str] = []
    declared = sum(1 for p in spec.parts if not p.meta.get("synthetic"))
    if "part_count" in expect and declared != int(expect["part_count"]):
        failures.append(f"part_count = {declared}, se esperaba {expect['part_count']}")
    budget = expect.get("triangle_budget")
    if budget is not None and info.triangle_count >= int(budget):
        failures.append(f"triangle_count = {info.triangle_count} >= presupuesto {budget}")
    height = expect.get("total_height")
    if height is not None:
        tolerance = float(expect.get("height_tolerance", 0.01))
        if abs(info.total_height - float(height)) > tolerance:
            failures.append(f"altura total = {info.total_height:.4f} m, se esperaba "
                            f"{height} ± {tolerance}")
    footprint = expect.get("footprint")
    if footprint:
        tolerance = float(expect.get("footprint_tolerance", 0.01))
        real = (info.aabb_max[0] - info.aabb_min[0], info.aabb_max[2] - info.aabb_min[2])
        for i, axis in enumerate("XZ"):
            if abs(real[i] - float(footprint[i])) > tolerance:
                failures.append(f"huella {axis} = {real[i]:.4f} m, se esperaba "
                                f"{footprint[i]} ± {tolerance}")
    if unassigned:
        failures.append(f"{unassigned} voxels sin asignar")
    return failures


def _unassigned_part(spec: PartsSpec, voxels: dict[tuple[int, int, int], int]):
    """Parte sintética `_unassigned` que `--allow-unassigned` mete de verdad en el GLB (§5.2).

    Cuelga de la parte raíz y comparte su pivote, así se ve exactamente dónde quedaron los
    voxels huérfanos sin tocar la geometría del resto. No cuenta como parte declarada.
    """
    root = spec.root_part()
    lo = [min(c[i] for c in voxels) for i in range(3)]
    hi = [max(c[i] for c in voxels) for i in range(3)]
    return parts_module.Part(
        id=UNASSIGNED,
        parent=root.id,
        boxes=[(lo[0], lo[1], lo[2], hi[0], hi[1], hi[2])],
        pivot=root.pivot,
        flags=["cosmetic"],
        collision="none",
        meta={"synthetic": True},
        raw={},
    )


def cmd_build(args: argparse.Namespace) -> int:
    """Genera GLB + sidecar + paleta (+ previews, + report) en `--out` (§7.2)."""
    try:
        spec, model, name = _load_target(args.target)
    except (PartsError, VoxError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_INVALID

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    assignment = parts_module.assign(model, spec)
    unassigned = len(assignment.get(UNASSIGNED, {}))
    if unassigned and not args.allow_unassigned:
        print(f"ERROR: {unassigned} voxels sin asignar. Usá --allow-unassigned para "
              f"iterar cajas, o revisá el reporte.", file=sys.stderr)
    if unassigned and args.allow_unassigned:
        spec.parts.append(_unassigned_part(spec, assignment[UNASSIGNED]))

    meshes = mesher.build_all(assignment, spec)

    energies: dict[int, dict] = {}
    used = Counter(model.voxels.values())
    for index in spec.emissive_palette_indices:
        material = model.materials.get(index, {})
        energies[index] = {
            "color": list(model.color(index)),
            "voxels": used.get(index, 0),
            "weight": material.get("_weight", material.get("_emit")),
            "flux": material.get("_flux"),
            "energy": model.emissive_energy(index) if material else 1.0,
        }
    if spec.emissive_strength is not None:
        strength = spec.emissive_strength
    elif energies:
        strength = max((e["energy"] for e in energies.values() if e["voxels"]), default=1.0)
    else:
        strength = 1.0

    palette_path = out_dir / spec.palette_texture
    glbwriter.write_palette_png(palette_path, model.palette)

    glb_path = out_dir / f"{name}.glb"
    info = glbwriter.write(glb_path, meshes, spec, emissive_strength=strength)

    try:
        glbvalidate.validate_file(glb_path)
    except glbvalidate.GlbValidationError as exc:
        print(f"ERROR: la validación interna del GLB falló.\n{exc}", file=sys.stderr)
        return EXIT_INVALID

    sidecar_path = out_dir / f"{name}.parts.json"
    _write_text(sidecar_path, dumps(_sidecar(spec, meshes, info, model, unassigned, energies)))

    failures = _check_expectations(spec, info, 0 if args.allow_unassigned else unassigned)

    written = [glb_path, sidecar_path, palette_path]
    if args.preview:
        preview_dir = Path(args.preview_out) if args.preview_out else out_dir
        written += preview.render(model, assignment, spec, preview_dir)
    if args.report:
        report_path = out_dir / "report.txt"
        _write_text(report_path,
                    _report(spec, meshes, info, model, assignment, failures, energies))
        written.append(report_path)

    for path in written:
        print(f"escrito  {path}")
    declared = sum(1 for p in spec.parts if not p.meta.get("synthetic"))
    print(f"partes {declared} · voxels {sum(m.voxel_count for m in meshes.values())} "
          f"· triángulos {info.triangle_count} · sin asignar {unassigned} "
          f"· altura {info.total_height:.4f} m · GLB {info.byte_length} bytes")

    if unassigned and not args.allow_unassigned:
        return EXIT_FAILED_CRITERIA
    if failures:
        print("CHECK voxsplit: FAIL", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return EXIT_FAILED_CRITERIA
    print("CHECK voxsplit: OK")
    return EXIT_OK


# --------------------------------------------------------------------------- #
# preview                                                                       #
# --------------------------------------------------------------------------- #


def cmd_preview(args: argparse.Namespace) -> int:
    """Escribe las tres vistas ortográficas sin generar el GLB (§7.3)."""
    try:
        spec, model, name = _load_target(args.target)
    except (PartsError, VoxError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_INVALID

    assignment = parts_module.assign(model, spec)
    out_dir = Path(args.out) if args.out else (
        (spec.path.parent if spec.path else Path.cwd()) / "previews" / name)
    for path in preview.render(model, assignment, spec, out_dir):
        print(f"escrito  {path}")
    unassigned = len(assignment.get(UNASSIGNED, {}))
    print(f"voxels sin asignar: {unassigned}")
    return EXIT_FAILED_CRITERIA if unassigned else EXIT_OK



# --------------------------------------------------------------------------- #
# objinspect                                                                    #
# --------------------------------------------------------------------------- #


def cmd_objinspect(args: argparse.Namespace) -> int:
    """Paso, dimensiones, voxels, triangulos del OBJ y colores usados (`objvox`)."""
    try:
        mesh = objvox.read_obj(args.file)
        try:
            palette = objvox.read_palette(args.file)
        except objvox.ObjVoxError as exc:
            print(f"aviso: sin paleta hermana ({exc})", file=sys.stderr)
            palette = None
        grid = objvox.voxelize(mesh, step=args.step, palette=palette, fill=not args.no_fill)
    except objvox.ObjVoxError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_INVALID

    lo, hi = mesh.bounds()
    extent = grid.extent()
    print(f"archivo          : {args.file}")
    print(f"objeto           : {mesh.name}")
    print(f"paso             : {grid.step} u  (x{args.scale} = {grid.step * args.scale} m/voxel)")
    print(f"bbox del OBJ     : "
          f"x[{lo[0]:g},{hi[0]:g}] y[{lo[1]:g},{hi[1]:g}] z[{lo[2]:g},{hi[2]:g}]")
    print(f"dimensiones      : {extent[0]} x {extent[1]} x {extent[2]} celdas  =  "
          f"{extent[0] * grid.step:g} x {extent[1] * grid.step:g} x {extent[2] * grid.step:g} u"
          f"  =  {extent[0] * grid.step * args.scale:.2f} x "
          f"{extent[1] * grid.step * args.scale:.2f} x "
          f"{extent[2] * grid.step * args.scale:.2f} m")
    print(f"triangulos OBJ   : {grid.source_triangles}  ({grid.face_count} caras leidas)")
    print(f"voxels           : {grid.voxel_count}  "
          f"(cascara {grid.shell_count} + relleno {grid.filled_count})")
    print(f"conflictos       : {len(grid.conflicts)} interior/exterior, "
          f"{len(grid.colour_conflicts)} de color, {len(grid.fill_mismatches)} de relleno")
    for line in grid.conflicts[:10]:
        print(f"    celda en conflicto: {line}")
    for line in grid.fill_mismatches[:10]:
        print(f"    {line}")
    print()
    print("colores usados (indice 1-based de la paleta 256x1):")
    print(f"  {'idx':>4}  {'voxels':>8}  color RGB")
    for index, count in sorted(grid.colours().items()):
        if grid.palette:
            r, g, b, _a = grid.palette[index - 1]
            print(f"  {index:>4}  {count:>8}  ({r:>3}, {g:>3}, {b:>3})")
        else:
            print(f"  {index:>4}  {count:>8}  -")
    return EXIT_OK


# --------------------------------------------------------------------------- #
# town                                                                          #
# --------------------------------------------------------------------------- #


def cmd_town(args: argparse.Namespace) -> int:
    """Compone las casas y los props del pueblo de ruta (`compose.build_town`)."""
    default_spec = Path(__file__).resolve().parent / "models" / "nuke_town.json"
    target = Path(args.spec) if args.spec else default_spec
    try:
        results, failures, _inventory = compose.build_town(target, args.out,
                                                           verbose=not args.quiet)
    except (compose.ComposeError, objvox.ObjVoxError, PartsError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_INVALID
    except glbvalidate.GlbValidationError as exc:
        print("ERROR: la validación interna del GLB falló.\n%s" % exc, file=sys.stderr)
        return EXIT_INVALID
    # Un JSON de recetas mal escrito —una clave que falta, un número donde iba una lista—
    # sale por acá. Es un archivo inválido (código 2), no un fallo interno de la
    # herramienta: sin esto el usuario veía un `KeyError: 'file'` sin contexto.
    except (KeyError, TypeError, ValueError) as exc:
        print(f"ERROR: '{target}' no es un JSON de recetas válido: "
              f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return EXIT_INVALID

    houses = sum(1 for r in results if r.kind == "house")
    props = len(results) - houses
    print(f"casas {houses} · props {props} · "
          f"triangulos {sum(r.triangle_count for r in results)} · "
          f"escrito en {args.out}")
    if failures:
        print("CHECK compose: FAIL", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return EXIT_FAILED_CRITERIA
    print("CHECK compose: OK")
    return EXIT_OK


# --------------------------------------------------------------------------- #
# Punto de entrada                                                              #
# --------------------------------------------------------------------------- #


def build_parser() -> argparse.ArgumentParser:
    """Construye el parser de argumentos de la CLI."""
    parser = argparse.ArgumentParser(
        prog="voxsplit",
        description="Convierte modelos voxel en un GLB jerárquico con una parte por nodo "
                    "(docs/05-pipeline-voxel.md).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Ejemplos (con cwd = godot/tools):\n"
               "  python -m voxsplit inspect "
               "../assets/_raw/Arachnodroid.zip!Package/Arachnoid.vox\n"
               "  python -m voxsplit build ../enemies/arachnodroid/arachnodroid.parts.json "
               "--out ../enemies/arachnodroid --report --preview\n"
               "  python -m voxsplit build models.drone_quad --out ../assets/drone --report\n",
    )
    parser.add_argument("--version", action="version", version=f"voxsplit {VERSION}")
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser(
        "inspect", help="tamaño, bbox, histograma, emisivos y componentes conexas de un .vox")
    inspect.add_argument("file", help="ruta al .vox, o 'archivo.zip!miembro.vox'")
    inspect.add_argument("--max-components", type=int, default=12,
                         help="cuántas componentes listar por grupo (por defecto 12)")
    inspect.set_defaults(func=cmd_inspect)

    build = subparsers.add_parser(
        "build", help="genera GLB + sidecar + paleta (+ previews, + report)")
    build.add_argument("target", help="ruta a <modelo>.parts.json, o 'models.drone_quad'")
    build.add_argument("--out", required=True, help="carpeta de salida")
    build.add_argument("--preview", action="store_true",
                       help="además escribe preview_front/side/top.png")
    build.add_argument("--preview-out", default=None,
                       help="carpeta de las previews (por defecto la misma que --out)")
    build.add_argument("--report", action="store_true", help="además escribe report.txt")
    build.add_argument("--allow-unassigned", action="store_true",
                       help="degrada a advertencia los voxels sin asignar")
    build.set_defaults(func=cmd_build)

    objinspect = subparsers.add_parser(
        "objinspect", help="paso, dimensiones, voxels, triangulos y colores de un .obj")
    objinspect.add_argument("file", help="ruta al .obj, o 'archivo.zip!miembro.obj'")
    objinspect.add_argument("--step", type=float, default=objvox.DEFAULT_STEP,
                            help="unidades del OBJ por voxel (por defecto 0.02)")
    objinspect.add_argument("--scale", type=float, default=2.5,
                            help="factor a metros con el que se imprimen las dimensiones")
    objinspect.add_argument("--no-fill", action="store_true",
                            help="no rellenar el interior: deja solo la cascara")
    objinspect.set_defaults(func=cmd_objinspect)

    town = subparsers.add_parser(
        "town", help="compone las casas y los props del pueblo de ruta")
    town.add_argument("spec", nargs="?", default=None,
                      help="ruta al JSON de recetas (por defecto models/nuke_town.json)")
    town.add_argument("--out", required=True, help="carpeta de salida")
    town.add_argument("--quiet", action="store_true", help="solo la linea de resumen")
    town.set_defaults(func=cmd_town)

    preview_cmd = subparsers.add_parser("preview", help="solo las 3 vistas ortográficas")
    preview_cmd.add_argument("target", help="ruta a <modelo>.parts.json, o 'models.drone_quad'")
    preview_cmd.add_argument("--out", default=None, help="carpeta de salida")
    preview_cmd.set_defaults(func=cmd_preview)
    return parser


def main(argv: list[str] | None = None) -> int:
    """Punto de entrada de la CLI."""
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
