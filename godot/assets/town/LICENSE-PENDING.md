# `assets/town/` — licencia **pendiente**

> Origen: `assets/_raw/nuke Free Sample.zip` · Incorporado el 2026-09-21 (WP-A) · Gobierna: `docs/16-licencias-y-atribucion.md` (riesgo D-6 de `docs/05`)

**El ZIP no trae licencia.** Ni `LICENSE`, ni `README`, ni `EULA`, ni una nota de atribución: son 26 `.obj`, 26 `.mtl` y 26 `.png` de paleta bajo una única carpeta `Free Sample/`, y nada más. Los OBJ llevan el encabezado `# MagicaVoxel @ Ephtracy`, que identifica al **exportador**, no al autor del modelo ni a su licencia.

Esto se **registra, no bloquea**: el WP sigue, igual que la ciudad de WP-13, cuyo pack tiene el mismo problema abierto. Lo que hay que hacer antes de publicar está en `docs/16`.

## Qué se redistribuye y qué no

| | En el repositorio |
|---|---|
| El ZIP original | **Sí**, en `assets/_raw/`, que lleva `.gdignore` y queda fuera del export (igual que los `.vox` de los enemigos) |
| Los OBJ del pack | **No.** Nunca se extraen: `tools/voxsplit/objvox.py` los lee desde el ZIP con `archivo.zip!miembro` |
| Los PNG de paleta del pack | **No** tal cual. `nuke_town_palette.png` se **regenera** con `glbwriter.write_palette_png()` a partir de los colores leídos; los 26 PNG del pack son byte a byte iguales entre sí |
| Los GLB de `assets/town/` | **Sí**, y son **derivados**: geometría re-voxelizada y vuelta a mallar con el mesher greedy propio, con la paleta reagrupada en 11 familias y las piezas recompuestas según `tools/voxsplit/models/nuke_town.json` |

Que sean derivados **no resuelve el problema por sí solo** — es la misma advertencia que `docs/05` §15 D-6 deja para los `.vox` de los enemigos.

## Lo que falta

1. Localizar el origen del pack (el nombre del ZIP sugiere una muestra gratuita de una colección «VoxelNuke»; el prefijo de cada archivo es `VoxelNuke-<n>-<Pieza>`) y su licencia real.
2. Anotarlo en `docs/16` y, si la licencia lo pide, en `CREDITS.md`.
3. Si resultara incompatible: las piezas se sustituyen sin tocar nada más que este directorio y `nuke_town.json`. El pipeline (`objvox` + `compose`) es propio y no depende del pack; `city/pieces/town/*.tscn` son escenas heredadas de una línea.

## Inventario derivado

10 GLB de casa (`house_a`, `house_a_b`, `house_b`, `house_b_b`, `house_c`, `house_c_b`, `house_d`, `house_d_b`, `shed`, `shed_b`) y 9 de prop (`barrel_a/b`, `trash_0..4`, `overgrowth_a/b`), más `nuke_town_palette.png`, `nuke_town_emissive.png`, `nuke_town.pieces.json` y `nuke_town_report.txt`. Las cifras medidas por pieza están en `nuke_town_report.txt`; se regeneran con:

```
python -m voxsplit town --out ../assets/town      # con cwd = godot/tools
```

De los 26 OBJ del pack quedan **sin usar** `RoadTile-0/1` y `ConcreteGroundTile` (26 290 y 85 128 triángulos crudos para baldosas planas: la calle del pueblo la resuelve WP-B con la vereda de la ciudad) y las 7 copias repetidas de `Overgrowth` y las 2 de `TrashPile`.
