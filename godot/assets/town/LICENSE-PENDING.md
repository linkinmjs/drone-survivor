# `assets/town/` — licencias **pendientes**

> Gobierna: `docs/16-licencias-y-atribucion.md` (riesgo D-6 de `docs/05`) · Actualizado en WP-D1 (2026-09-23)

Este archivo **registra**, no resuelve. Ninguno de los cuatro packs que alimentan el pueblo
de ruta trae licencia, y eso no bloquea el trabajo —igual que en la ciudad de WP-13— pero
tiene que estar escrito antes de publicar. El checklist de qué hacer con cada uno está en
`docs/16`.

## 1. Una fila por pack

| Archivo en `assets/_raw/` | Autor que figura | Qué se tomó | Piezas derivadas | Licencia |
|---|---|---|---|---|
| `nuke Free Sample.zip` | ninguno (los OBJ llevan `# MagicaVoxel @ Ephtracy`, que identifica al **exportador**) | 2 bloques de edificio, 2 tapas de techo, puerta, portón de garaje, 2 barriles, 5 montones de basura, 2 matas de maleza | 10 casas (`house_a…d`, `shed`, y sus variantes `_b`) y 9 props (`barrel_a/b`, `trash_0…4`, `overgrowth_a/b`) | **DESCONOCIDA** |
| `Foliage.rar` | ninguno (los OBJ llevan el mismo encabezado de MagicaVoxel) | 11 de los 32 modelos de `obj/`: árbol XL, grande, medio, chico, tocón, 2 arbustos, pasto alto, flor roja, maíz medio y maíz completo | `tree_xl`, `tree_large`, `tree_medium`, `tree_small`, `tree_stump`, `bush_a`, `bush_b`, `grass_a`, `flowers_a`, `corn_a`, `corn_b` | **DESCONOCIDA** |
| `VoxelVillagePack.zip` | ninguno | 4 de `objects/`: farol, módulo de cerco, barril y cajón vacío | `lantern`, `fence_picket_3m`, `barrel_c`, `crate` | **DESCONOCIDA** |
| `city-Free Sample.zip` | ninguno (mismo encabezado; el prefijo de archivo es `Voxel City-<n>-<Pieza>`) | 2 de las 11 piezas: la parada de colectivo y el toldo de puerta rojo | `bus_stop`, `awning_orange` (el toldo, **repintado** a naranja en la paleta) | **DESCONOCIDA** |
| `Package.zip` | ninguno | **nada** | — | **DESCONOCIDA** (no se usa: ver §4) |

## 2. Una fila por procedural (propio)

Las dieciocho piezas que hornea `tools/build_town_props.gd` son **obra propia** de este
proyecto: geometría escrita en GDScript con `SurfaceTool`, sin ninguna malla, textura ni
paleta de terceros. El atlas de carteles `signs.png` también: el texto lo pinta una fuente
de mapa de bits de 5 × 7 incluida en el mismo archivo.

| Piezas | Licencia |
|---|---|
| `gas_station`, `water_tower`, `silo`, `field_shed` | propia, © 2026 Drone Survivor |
| `lamp_post`, `bench`, `flag_mast`, `monument`, `welcome_sign`, `road_sign_narrow`, `road_sign_speed`, `fence_post`, `fence_wire_6m`, `bridge_deck` | propia, © 2026 Drone Survivor |
| `car_a`, `car_b`, `pickup`, `truck` (placeholder) | propia, © 2026 Drone Survivor |
| `signs.png`, `town_{concrete,sheet,metal,wood,signs}.tres` | propia, © 2026 Drone Survivor |

## 3. Qué se redistribuye y qué no

| | En el repositorio |
|---|---|
| Los cinco archivos originales | **Sí**, en `assets/_raw/`, que lleva `.gdignore` y queda fuera del export (igual que los `.vox` de los enemigos) |
| Los OBJ de los packs | **No.** Nunca se extraen: `tools/voxsplit/objvox.py` los lee desde el archivo con `archivo.zip!miembro`, y desde WP-D1 también `archivo.rar!miembro` por tubería de UnRAR |
| Los PNG de paleta de los packs | **No** tal cual. Cada `<pack>_palette.png` se **regenera** con `glbwriter.write_palette_png()` a partir de los colores leídos |
| Los GLB de `assets/town/` | **Sí**, y son **derivados**: geometría re-voxelizada y vuelta a mallar con el mesher greedy propio, recentrada, recortada y recompuesta según las recetas de `tools/voxsplit/models/*.json` |
| Los `.res` de `assets/city/props/` | **Sí**, y son **propios**: no derivan de ningún pack |

Que sean derivados **no resuelve el problema por sí solo** — es la misma advertencia que
`docs/05` §15 D-6 deja para los `.vox` de los enemigos.

## 4. Decisiones de WP-D1 que conviene tener anotadas

- **`Package.zip` (barrancas de montaña) queda sin usar.** Son diez OBJ de 5 000 a 17 000
  triángulos crudos para accidentes de terreno que el relieve horneado ya resuelve. No
  entra ninguna pieza, así que no hay nada que acreditar.
- **Las 12 personas del `VoxelVillagePack` no se usan**: el pueblo está evacuado
  (`docs/17` §7.3). Tampoco los 3 puestos de mercado ni los 5 árboles del pack, que
  duplican lo que trae `Foliage.rar` con peor relación de triángulos.
- **El candidato a capilla queda fuera de WP-D1.** `buildings/building3` del
  `VoxelVillagePack` mide 4 × 4 × 6 m y sale en 1 604 triángulos a 10 cm por vóxel, dentro
  de lo razonable, pero el pack trae **dos paletas de 256×1 distintas** —una la comparten
  `buildings/`, `trees/` y `rocks/`, y otra `objects/`, que es la que usan las cuatro
  piezas tomadas— y el compositor exige una sola paleta por receta. Fundirlas es trabajo de
  pipeline, no de arte, y la capilla es prioridad B: queda anotada acá y en el informe del
  WP para quien la retome.
- **El toldo se repinta.** El pack `city` trae el toldo de puerta en rojo y el de mercado
  en amarillo, y ninguno en naranja; la gramática de `docs/17` §4 dice que **el toldo
  naranja es la pila**. Los tres índices de paleta del toldo rojo (62, 63, 64), que no usa
  ninguna otra pieza del pack, se repintan a los tres tonos de (0,95 · 0,45 · 0,10) con la
  clave `palette_paint` de la receta. La geometría no se toca.

## 5. Lo que falta

1. Localizar el origen de los cuatro packs y su licencia real. Pistas: `nuke Free Sample` y
   `city-Free Sample` son muestras gratuitas de colecciones («VoxelNuke», «Voxel City»);
   `Foliage.rar` trae además carpetas `ply/`, `mc/` y `point/` que sugieren un pack de
   vegetación vendido con varios formatos; `VoxelVillagePack.zip` trae `.DS_Store` y
   `__MACOSX/`, o sea que se empaquetó en un macOS.
2. Anotarlo en `docs/16` y, si la licencia lo pide, en `CREDITS.md`.
3. Si alguna resultara incompatible: las piezas se sustituyen sin tocar nada más que este
   directorio y la receta del pack en `tools/voxsplit/models/`. El pipeline (`objvox` +
   `compose`) es propio y no depende de ningún pack; `city/pieces/town/**` son escenas
   heredadas de una línea; y las dieciocho procedurales no se tocan.

## 6. Inventario derivado

54 piezas en total, indexadas en `assets/town/pieces_manifest.json`:

| Procedencia | Piezas | Salidas |
|---|---|---|
| `nuke_town` | 10 casas + 9 props | 19 GLB, `nuke_town_palette.png`, `nuke_town_emissive.png`, `nuke_town.pieces.json`, `nuke_town_report.txt` |
| `foliage` | 11 de follaje | 11 GLB, `foliage_palette.png`, `foliage.pieces.json`, `foliage_report.txt` |
| `village` | 4 props | 4 GLB, `village_palette.png`, `village.pieces.json`, `village_report.txt` |
| `city_sample` | 2 props | 2 GLB, `city_sample_palette.png`, `city_sample.pieces.json`, `city_sample_report.txt` |
| procedural | 4 edificios + 14 props | 18 `.res` en `assets/city/props/`, `signs.png`, 5 materiales en `assets/city/materials/` |

Se regeneran con (`cwd = godot/tools` para los cuatro primeros):

```
python -m voxsplit town voxsplit/models/nuke_town.json   --out ../assets/town
python -m voxsplit town voxsplit/models/foliage.json     --out ../assets/town
python -m voxsplit town voxsplit/models/village.json     --out ../assets/town
python -m voxsplit town voxsplit/models/city_sample.json --out ../assets/town
godot --headless --path godot -s res://tools/build_town_props.gd
```
