"""Modelos voxel procedurales propios, generados con el mismo pipeline que los `.vox`.

Cada módulo expone ``build() -> dict`` con las claves ``size``, ``voxels``, ``parts``,
``palette`` y ``header`` (§10 y §12 de `docs/05`). `__main__.py` acepta el nombre del
módulo en lugar de una ruta a `parts.json`: ``python -m voxsplit build models.drone_quad``.
"""

from __future__ import annotations

__all__: list[str] = []
