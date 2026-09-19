"""Meshing greedy por parte y por material (§6 de `docs/05`).

Reglas:

1. El meshing se hace **por parte**: una cara se genera si el vecino en esa dirección
   no existe *o* pertenece a otra parte, de modo que el corte queda cerrado cuando la
   parte se desprende.
2. Se recorren los 6 ejes; por cada eje, cada rebanada y cada índice de paleta se
   construye una máscara 2D y se fusionan rectángulos maximales (crecer en V mientras
   el color coincida, luego en U mientras la fila entera coincida).
3. Solo se fusionan celdas del **mismo índice de paleta**, porque la UV depende de él.
4. Cada vértice recibe ``u = (i - 0.5) / 256``, ``v = 0.5`` (§6.2).
5. Los vértices salen en metros, **relativos al pivote de su propio nodo** (§6.3), sin
   índices compartidos entre superficies: cada rectángulo aporta 4 vértices y 6 índices.
6. Bobinado antihorario visto desde fuera; si el `axis_map` tiene determinante −1 se
   invierte el orden de los índices para conservarlo.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Sequence

from .parts import Part, PartsSpec

__all__ = ["Surface", "PartMesh", "build_part", "build_all", "OPAQUE", "EMISSIVE"]

#: Nombres de las dos superficies posibles por parte (§6.1).
OPAQUE = "opaque"
EMISSIVE = "emissive"

#: Ancho de la textura de paleta, en píxeles (§6.2).
PALETTE_WIDTH = 256


@dataclass
class Surface:
    """Una superficie (un material) de una parte: atributos e índices ya triangulados."""

    material: str
    positions: list[tuple[float, float, float]] = field(default_factory=list)
    normals: list[tuple[float, float, float]] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)
    indices: list[int] = field(default_factory=list)

    @property
    def triangle_count(self) -> int:
        """Número de triángulos de la superficie."""
        return len(self.indices) // 3

    @property
    def quad_count(self) -> int:
        """Número de rectángulos fusionados que produjeron la superficie."""
        return len(self.positions) // 4


@dataclass
class PartMesh:
    """Malla de una parte: hasta dos superficies, AABB local y conteos."""

    part_id: str
    surfaces: dict[str, Surface] = field(default_factory=dict)
    aabb_min: tuple[float, float, float] = (0.0, 0.0, 0.0)
    aabb_max: tuple[float, float, float] = (0.0, 0.0, 0.0)
    center_of_mass: tuple[float, float, float] = (0.0, 0.0, 0.0)
    voxel_count: int = 0
    quad_count: int = 0

    @property
    def triangle_count(self) -> int:
        """Triángulos sumando todas las superficies."""
        return sum(s.triangle_count for s in self.surfaces.values())

    @property
    def has_emissive(self) -> bool:
        """`True` si la parte tiene superficie emisiva (metadato `has_emissive_surface`)."""
        return EMISSIVE in self.surfaces

    @property
    def is_empty(self) -> bool:
        """`True` si la parte no recibió ningún voxel."""
        return self.voxel_count == 0


def _uv_for(index: int) -> tuple[float, float]:
    """UV al centro del píxel `index - 1` de la paleta 256×1 (§6.2)."""
    return ((index - 0.5) / PALETTE_WIDTH, 0.5)


def _greedy_rectangles(mask: dict[tuple[int, int], int]) -> list[tuple[int, int, int, int, int]]:
    """Fusiona una máscara 2D en rectángulos maximales del mismo índice de paleta.

    Devuelve tuplas ``(u0, v0, du, dv, palette_index)``. El crecimiento es primero en V
    (fila) y luego en U (mientras la fila entera coincida), como fija §6.1.3.
    """
    if not mask:
        return []
    keys = sorted(mask)
    u_min = keys[0][0]
    u_max = keys[-1][0]
    v_min = min(k[1] for k in keys)
    v_max = max(k[1] for k in keys)
    used: set[tuple[int, int]] = set()
    out: list[tuple[int, int, int, int, int]] = []
    for u in range(u_min, u_max + 1):
        for v in range(v_min, v_max + 1):
            cell = (u, v)
            if cell in used:
                continue
            index = mask.get(cell)
            if index is None:
                continue
            width = 1
            while True:
                probe = (u, v + width)
                if mask.get(probe) == index and probe not in used:
                    width += 1
                else:
                    break
            height = 1
            growing = True
            while growing:
                for k in range(width):
                    probe = (u + height, v + k)
                    if mask.get(probe) != index or probe in used:
                        growing = False
                        break
                if growing:
                    height += 1
            for du in range(height):
                for dv in range(width):
                    used.add((u + du, v + dv))
            out.append((u, v, height, width, index))
    return out


def build_part(voxels: dict[tuple[int, int, int], int], spec: PartsSpec,
               part: Part, emissive_indices: Iterable[int] | None = None) -> PartMesh:
    """Construye la malla greedy de una parte a partir de sus voxels asignados (§12)."""
    emissive = set(emissive_indices if emissive_indices is not None
                   else spec.emissive_palette_indices)
    mesh = PartMesh(part_id=part.id, voxel_count=len(voxels))
    if not voxels:
        return mesh

    pivot = spec.pivot_world(part)
    flip = spec.axis_map.determinant < 0.0
    occupied = voxels  # dict[(x,y,z)] -> palette index

    # Centro de masa y AABB a partir del volumen de voxels (en metros, local al pivote).
    sums = [0.0, 0.0, 0.0]
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for coord in voxels:
        center = spec.to_meters(coord)
        for i in range(3):
            sums[i] += center[i]
        corner_lo = spec.to_meters((coord[0] - 0.5, coord[1] - 0.5, coord[2] - 0.5))
        corner_hi = spec.to_meters((coord[0] + 0.5, coord[1] + 0.5, coord[2] + 0.5))
        for i in range(3):
            lo[i] = min(lo[i], corner_lo[i], corner_hi[i])
            hi[i] = max(hi[i], corner_lo[i], corner_hi[i])
    count = float(len(voxels))
    centre = tuple(sums[i] / count - pivot[i] for i in range(3))
    mesh.center_of_mass = centre  # type: ignore[assignment]
    mesh.aabb_min = tuple(lo[i] - pivot[i] for i in range(3))  # type: ignore[assignment]
    mesh.aabb_max = tuple(hi[i] - pivot[i] for i in range(3))  # type: ignore[assignment]

    for axis in range(3):
        u_axis = (axis + 1) % 3
        v_axis = (axis + 2) % 3
        for sign in (1, -1):
            slices: dict[int, dict[tuple[int, int], int]] = {}
            for coord, index in occupied.items():
                neighbour = list(coord)
                neighbour[axis] += sign
                if tuple(neighbour) in occupied:
                    continue
                slices.setdefault(coord[axis], {})[(coord[u_axis], coord[v_axis])] = index
            for slice_w in sorted(slices):
                for u0, v0, du, dv, index in _greedy_rectangles(slices[slice_w]):
                    _emit_quad(mesh, spec, pivot, axis, u_axis, v_axis, sign,
                               slice_w, u0, v0, du, dv, index, emissive, flip)

    mesh.quad_count = sum(s.quad_count for s in mesh.surfaces.values())
    return mesh


def _emit_quad(mesh: PartMesh, spec: PartsSpec, pivot: Sequence[float],
               axis: int, u_axis: int, v_axis: int, sign: int, slice_w: int,
               u0: int, v0: int, du: int, dv: int, index: int,
               emissive: set[int], flip: bool) -> None:
    """Escribe en la superficie adecuada los 4 vértices y 6 índices de un rectángulo."""
    material = EMISSIVE if index in emissive else OPAQUE
    surface = mesh.surfaces.get(material)
    if surface is None:
        surface = Surface(material=material)
        mesh.surfaces[material] = surface

    plane = slice_w + 0.5 * sign

    def corner(offset_u: float, offset_v: float) -> tuple[float, float, float]:
        point = [0.0, 0.0, 0.0]
        point[axis] = plane
        point[u_axis] = u0 - 0.5 + offset_u
        point[v_axis] = v0 - 0.5 + offset_v
        world = spec.to_meters(point)
        return (world[0] - pivot[0], world[1] - pivot[1], world[2] - pivot[2])

    # (p, q) elegidos para que p × q sea la normal saliente: e_u × e_v = e_axis.
    if sign > 0:
        quad = [corner(0.0, 0.0), corner(du, 0.0), corner(du, dv), corner(0.0, dv)]
    else:
        quad = [corner(0.0, 0.0), corner(0.0, dv), corner(du, dv), corner(du, 0.0)]

    normal_vox = [0.0, 0.0, 0.0]
    normal_vox[axis] = float(sign)
    normal = spec.axis_map.apply(normal_vox)

    base = len(surface.positions)
    uv = _uv_for(index)
    for vertex in quad:
        surface.positions.append(vertex)
        surface.normals.append(normal)
        surface.uvs.append(uv)
    triangle = [base, base + 1, base + 2, base, base + 2, base + 3]
    if flip:
        triangle = [base, base + 2, base + 1, base, base + 3, base + 2]
    surface.indices.extend(triangle)


def build_all(assignment: dict[str, dict[tuple[int, int, int], int]],
              spec: PartsSpec) -> dict[str, PartMesh]:
    """Construye la malla de todas las partes de `spec`, en el orden de `parts[]`."""
    return {part.id: build_part(assignment.get(part.id, {}), spec, part)
            for part in spec.parts}
