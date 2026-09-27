# `assets/city/` — pack VoxelCity FreeSample (WP-13)

> Origen: `assets/_raw/FreeSample.zip` · Importado el 2026-09-19 con Godot 4.7 (ufbx) · Gobierna: `docs/10-ciudad-destructible.md` §2

El ZIP **no se extrae dentro del repositorio**: se descomprime en un directorio temporal fuera del árbol y aquí sólo quedan los derivados que el juego usa. La licencia del pack sigue abierta (`docs/16`, riesgo 11 de `docs/10`).

## Escala: por pieza, medida por la puerta (P2f)

> **P2f (2026-09-27, hechos medidos)**: la sección que sigue es la historia de WP-13, que eligió 5.0 para caer en la ventana de 12–16 m de `docs/10` §11.1 **sin medir nada del pack**; con ese factor la puerta de `BuildingBlock_1` medía 10 m. Medido en la fachada, en unidades nativas (`root_scale = 1`, vóxel 0,1), con la fachada reproyectada desde el atlas (UV → texel) y con una captura ortográfica, que coinciden:
>
> | FBX | Puerta nativa | Planta nativa | `root_scale` | Puerta | Planta | Ancho × Alto × Fondo |
> |---|---|---|---|---|---|---|
> | `BuildingBlock_1` | **2,0** (hoja 1,2 de ancho, teclado a 0,9–1,1) | 2,5 (una planta) | 5.0 → **1.05** | 2,10 m | 2,63 m | 6,30 × 2,63 × 2,52 m |
> | `BuildingBlock_2` | — | 2,5 | 5.0 → **1.05** (mismo kit) | — | 2,63 m | 6,30 × 2,63 × 2,10 m |
> | `Building_3` | — | **1,3** (período de las ventanas) | 5.0 → **2.45** | — | 3,19 m | 9,80 × 39,69 × 4,90 m |
> | `BuildingBlock_19` | **2,1** | 2,5 | **5.0** (sin cambio) | 10,5 m | 12,5 m | 20,00 × 12,50 × 11,00 m |
> | `BuildingBlock_18` | — | 2,5 | **5.0** (sin cambio) | — | 12,5 m | 20,00 × 12,50 × 11,00 m |
> | `BuildingBlock_24` | — | 1,6 | **5.0** (sin cambio) | — | 8 m | 20,00 × 8,00 × 10,50 m |
>
> Factor = 2,1 m / puerta nativa (redondeado a 0,05); sin puerta, 3,2 m / planta nativa. El kit no es homogéneo: los bloques de una planta están a ~×1 y `Building_3` a ~×2,5. `BuildingBlock_19`, `_18` y `_24` son la escuela, el hito y los medianos de `town_a`: llevarlos a 1.05 tira cinco filas de `city_check` y deja el hito en 3,6 m, así que siguen en 5.0 y la galería los marca `ESCALA?` hasta que se rediseñe el pueblo. Props y viario no cambian (tamaño real ya medido en WP-24b; módulo de 10 m del viario). Las medidas nativas viven en `pieces_manifest.json` (`features`) y la galería las multiplica por el `root_scale` vigente de cada `.fbx.import`. `docs/10` §2.2 y su Nota de P2f.

### Historia de WP-13: `nodes/root_scale = 5.0`

**El factor es de aumento, no de reducción.** `docs/10` §2.2 suponía que los FBX venían en centímetros y que `BuildingBlock_1` mediría ~1 200 unidades, con lo que el factor sería `0.01`. Lo medido contradice las dos cosas:

| Paso | Medición |
|---|---|
| Vértices crudos del FBX (`BuildingBlock_1`) | 600 × 240 × **250** unidades, con `UnitScaleFactor = 1.0` |
| Ejes | `UpAxis = 1` (Y) y `OriginalUpAxis = 2` (Z), con `PreRotation = (-90, 0, 0)`: la **Z cruda es la altura** |
| Importado con `root_scale = 1.0` | **2.50 m** de alto |
| Ventana exigida por `docs/10` §11.1 sub-check 4 | 12 – 16 m |
| Factor fijado | **5.0** → **12.50 m** |

El importador ufbx ya aplica por su cuenta la conversión de unidades del FBX, así que las 250 unidades llegan a Godot como 2.50 m. El rango de factores que cae en la ventana es `[4.8, 6.4]`; se elige **5.0** por ser redondo y quedar en mitad de la ventana. Los 13 `.fbx.import` llevan el mismo valor con `nodes/apply_root_scale = true`, para que la escala se hornee en los vértices y **nunca** haya que escalar un `StaticBody3D` (prohibido por `docs/03` y verificado por `city_check`).

## Las 13 piezas

Dimensiones reales del AABB agregado, en metros, tal como las imprime `city_import_check` (P2f: `block_low_a`, `block_low_b` y `tower_a` con su escala medida).

| FBX | Escena de pieza | Rol propuesto | Ancho × Alto × Fondo | Tris | Colisión |
|---|---|---|---|---|---|
| `Building_3` | `city/pieces/tower_a.tscn` | **Edificio alto** — única torre real del pack | 9.80 × **39.69** × 4.90 | 1 772 | `BoxShape3D` |
| `BuildingBlock_19` | `city/pieces/tower_b.tscn` | Edificio alto, variante (ver aviso) | 20.00 × 12.50 × 11.00 | 468 | `BoxShape3D` |
| `BuildingBlock_18` | `city/pieces/block_mid.tscn` | Bloque medio | 20.00 × 12.50 × 11.00 | 236 | `BoxShape3D` |
| `BuildingBlock_1` | `city/pieces/block_low_a.tscn` | Local de una planta con puerta — **pieza de calibración** | 6.30 × 2.63 × 2.52 | 210 | `BoxShape3D` |
| `BuildingBlock_2` | `city/pieces/block_low_b.tscn` | Local de una planta, variante | 6.30 × 2.63 × 2.10 | 160 | `BoxShape3D` |
| `BuildingBlock_24` | `city/pieces/block_low_c.tscn` | Bloque bajo, variante | 20.00 × 8.00 × 10.50 | 140 | `BoxShape3D` |
| `Advertising_5` | `city/pieces/props/sign_a.tscn` | **Cartel** de fachada | 2.10 × 4.80 × 0.30 | 12 | `ConvexPolygonShape3D` |
| `Advertising_6` | `city/pieces/props/sign_b.tscn` | **Cartel** vertical de azotea | 3.36 × 5.04 × 0.84 | 164 | `ConvexPolygonShape3D` |
| `Advertising_7` | `city/pieces/props/sign_c.tscn` | **Cartel** horizontal de azotea | 5.94 × 2.97 × 1.65 | 288 | `ConvexPolygonShape3D` |
| `SateliteDish` | `city/pieces/props/dish.tscn` | **Prop** de azotea, escombro cosmético | 1.80 × 1.80 × 0.60 | 266 | `ConvexPolygonShape3D` |
| `Road_Chunk_5` | `city/pieces/road_chunk.tscn` | **Calle** — calzada (`MultiMesh`) | 10.00 × 0.50 × 10.00 | 12 | `BoxShape3D` |
| `Sidewalk_Chunk_2` | `city/pieces/sidewalk_chunk.tscn` | **Vereda** de tramo (`MultiMesh`) | 10.00 × 1.00 × 10.00 | 28 | `BoxShape3D` |
| `Sidewalk_Tile_1` | `city/pieces/sidewalk_tile.tscn` | **Vereda** — baldosa (`MultiMesh`) | 20.00 × 1.00 × 20.00 | 12 | `BoxShape3D` |

Las 13 escenas de `city/pieces/` son **heredadas** de la escena importada: la raíz ya es el `StaticBody3D` de la capa 8 con su `IntactShape`, y WP-20 sólo tiene que ponerle el script `Building` y los nodos de etapa de `docs/10` §2.5.

### Dos avisos para WP-20 (historia: medidas a ×5, antes de P2f)

1. **Sólo hay una torre, no dos.** `BuildingBlock_19` mide 12.50 m, exactamente lo mismo que los bloques bajos; la única pieza con silueta de torre es `Building_3`, con 81 m. La tabla de `docs/10` §2.1 le asigna el rol `tower_b` suponiendo que era alta. Con la variación de altura prevista (`height_scale ∈ [0.85, 1.35]`, §4.3) `tower_b` llegaría a 16.9 m como mucho, lejos de leerse como torre. Las palancas son ampliar el rango de `height_scale` para las torres, repetir `Building_3` con rotación, o aceptar que el centro financiero es una torre rodeada de bloques medios.
2. **`BuildingBlock_1` y `BuildingBlock_2` miden 30 m de ancho y la celda de `docs/10` §4.1 es de 24 m.** Se desbordan 3 m por lado sobre la calle. El metadato `base_size` de la raíz está justamente para que `CityGrid` lo resuelva sin volver a medir: o crece la celda, o esas dos variantes se reservan para celdas de borde, o se las escala también en planta (lo que obliga a reescribir `BoxShape3D.size` en los tres ejes, no sólo en `y`).

## Texturas: 8 conservadas de 12

**Los cuatro `VoxelCity_CompositeBuildings_Optimized-*` se descartan.** La decisión no es una estimación: se leyeron las referencias de textura de los 13 FBX del pack y **ninguno** nombra un composite. Las cuatro difusas cubren todas las UV, así que se cumple la condición de `docs/10` §2.3 para descartarlos y no hay que anotar nada en `CREDITS.md`. Ahorro: 30 MB de PNG en disco y ~11 MB de VRAM.

Las ocho conservadas llegan a 4096² y se **redimensionan con Pillow (filtro LANCZOS)** a su tamaño de destino, además de fijar `process/size_limit` en el `.import`. Redimensionar el PNG saca 84 MB del repositorio; el `size_limit` conserva la intención declarada que `docs/10` §2.3 pide guardar y que el sub-check `texture_settings` verifica.

| Textura | Origen en el pack | Destino | VRAM (BC1 + mipmaps) |
|---|---|---|---|
| `t_buildings_001_diffuse.png` | `T_Buildings_001Diffuse- 4K.png` | 2048² | 2.67 MB |
| `t_buildings_002_diffuse.png` | `T_Buildings_002Diffuse- 4K.png` | 2048² | 2.67 MB |
| `t_props_diffuse.png` | `T_PropsDiffuse- 4K.png` | 1024² | 0.67 MB |
| `t_roads_diffuse.png` | `T_RoadsDiffuse- 4K.png` | 1024² | 0.67 MB |
| `bake_buildings_001_emissive.png` | `BAKE_Buildings_001Emissive- 4K.png` | 1024² | 0.67 MB |
| `bake_buildings_002_emissive.png` | `BAKE_Buildings_002Emissive- 4K.png` | 1024² | 0.67 MB |
| `bake_props_emissive.png` | `BAKE_PropsEmissive- 4K.png` | 1024² | 0.67 MB |
| `bake_roads_emissive.png` | `BAKE_RoadsEmissive- 4K.png` | 1024² | 0.67 MB |
| **Total** | | **8** | **9.33 MB** |

Las ocho van con `compress/mode = 2` (VRAM Compressed), `compress/high_quality = false` (BC1: ninguna tiene alfa), `mipmaps/generate = true`, `compress/normal_map = 2` (Disabled, para que la fuente se trate siempre como sRGB, difusas y emisivas por igual) y `detect_3d/compress_to = 0`, de modo que Godot no reimporte por su cuenta y no haya *churn* en el caché de CI.

El presupuesto del plan es **< 90 MB**: sobra un factor 9.6×. El margen existe porque las cuatro difusas a 4 096² sin comprimir serían 358 MB, cuatro veces el presupuesto por sí solas.

## Materiales: por qué los asigna el post-import

Los materiales de `assets/city/materials/` son **propios** y se los asigna `asset_import/import_city_piece.gd`, en lugar de extraer los del FBX con `materials/extract`. El motivo es que **las rutas de textura del pack están rotas**: apuntan al árbol de trabajo del autor (`D:\VoxelAssets\City\...`) y, en las relativas, tres de las cuatro emisivas nombran archivos que el ZIP no trae (`..\..\RawExports\Bakes\Emissive\BAKE_PropsEmissive.png`, sin el sufijo `- 4K` y en un directorio inexistente). Extraerlos habría producido cuatro `.tres` sin textura que igualmente habría que editar a mano.

El material se hornea en el `ArrayMesh` con `surface_set_material()`, no como `material_override` del nodo: las calles y veredas se dibujan con `MultiMeshInstance3D` (`docs/10` §4.4), que lee el material de la malla y nunca vería un override.

Las cuatro familias salen de las referencias declaradas por cada FBX, verificadas una a una:

| Material | Piezas |
|---|---|
| `buildings_001.tres` | `BuildingBlock_18`, `BuildingBlock_19`, `BuildingBlock_24` |
| `buildings_002.tres` | `Building_3`, `BuildingBlock_1`, `BuildingBlock_2` |
| `props.tres` | `Advertising_5/6/7`, `SateliteDish` |
| `roads.tres` | `Road_Chunk_5`, `Sidewalk_Chunk_2`, `Sidewalk_Tile_1` |

## LOD de malla: la opción está activa y el importador genera cero niveles

`meshes/generate_lods = true` en los 13 presets, como manda `docs/10` §2.2, pero **el importador no produce ningún nivel**. No es un fallo de configuración:

- El optimizador **sí corre**: `meshes/create_shadow_meshes = true` deja un `ArrayMesh.shadow_mesh` en las 13 mallas, y se genera en la misma pasada que los LOD.
- Ese `shadow_mesh` sale con **exactamente el mismo número de triángulos** que la malla original (1 772 → 1 772 en `Building_3`), señal de que no se fusionó ni un vértice.
- La causa es la geometría: son mallas vóxel con normales duras y un atlas de UV por cara, con más vértices que triángulos (`Building_3`: 2 664 vértices para 1 772 triángulos). Cada vértice está partido, meshoptimizer ve **todas** las aristas como borde y no puede colapsar ninguna.

`docs/10` §2.4 ya anticipaba que «el runtime no expone el número de niveles, así que `city_import_check` comprueba la **opción** en el `.import`», y eso es lo que hace el sub-check `import_options`. El sub-check `mesh_optimization` verifica además que el optimizador corrió de verdad, comprobando el `shadow_mesh`. Con 12–1 772 triángulos por pieza, el LOD de malla no era la palanca de rendimiento relevante: lo son `visibility_range_end = 180 m` en los props y los 15 oclusores de `docs/10` §7.

## Verificación

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/city_import_check.tscn
```

`tools/city_import_check.gd` imprime el inventario medido y cubre los 13 sub-checks de `docs/10` §11.1: piezas presentes, raíz `StaticBody3D` en capa 8 con máscara 311, forma de colisión del tipo correcto, escala de referencia y cordura, opciones de import, `gi_mode`/sombras/desvanecimiento, materiales con textura, optimización de malla, ajustes y VRAM de texturas, ausencia de composites y no modificación de los `.import`.
