"""Paquete `voxsplit`: convierte modelos voxel en un GLB jerárquico con una parte por nodo.

Implementa el pipeline descrito en `godot/docs/05-pipeline-voxel.md`:

* `voxreader`  — lectura de archivos `.vox` de MagicaVoxel (versión 150).
* `parts`      — carga y validación de `parts.json`, espejo y asignación de voxels.
* `mesher`     — meshing greedy por parte y por material, con UV de paleta.
* `glbwriter`  — serialización glTF 2.0 binaria escrita a mano.
* `glbvalidate`— validador propio del GLB recién escrito.
* `preview`    — vistas ortográficas con Pillow.
* `models`     — modelos procedurales propios (el dron del jugador).

Dependencias: biblioteca estándar de Python 3.12 más Pillow. `numpy` NO se usa.
"""

from __future__ import annotations

__all__ = ["VERSION"]

#: Versión de la herramienta; se escribe en `metadata.voxsplit_version` del sidecar.
VERSION = "1.0.0"
