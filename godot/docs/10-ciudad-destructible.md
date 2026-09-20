# 10 — Ciudad destructible

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-13 y WP-20 · Depende de: `docs/02-configuracion-del-proyecto.md`, `docs/06-framework-de-enemigos.md`, `docs/08-combate-y-armas.md`, `docs/09-energia-y-danio.md`

## 1. Objetivo y alcance

> **Nota de WP-24e (2026-09-20)**: los 15 `OccluderInstance3D` por manzana (§7) nunca se retiraban al derrumbe y, con la oclusión encendida en las `SubViewport` del ojo de pez, dejaban losas fantasma de hasta 75 m que culeaban el cuadro entero cuando el dron entraba en la huella de un edificio caído o tapaban al coloso (el «mapa y enemigo que aparecen y desaparecen» del usuario). Ahora `CityGrid.occluder_for(building)` (solo para el edificio más alto de la manzana, resuelto por nombre y metadato `cell`, sin regenerar `district_a.tscn`) y `Building._finish_collapse()` lo oculta (`reset()` lo devuelve); `city_check` 8b lo verifica. Además la oclusión queda **apagada** en el proyecto y en todos los presets (`docs/13` §3.4).

> **Nota de WP-24 (2026-09-20)**: los materiales de ciudad `assets/city/materials/{buildings_001,buildings_002,props,roads}.tres` pasan a **`emission_operator = MULTIPLY`**: con el ADD de fábrica y `emission = blanco`, toda la fachada emitía 1 000 nits y el bake de ventanas no se veía (era la «planitud» de la ciudad). Regla para cualquier material nuevo que use `emission_texture` como **máscara**: `emission_operator = MULTIPLY`. `gi_mode` verificado por `city_check._check_gi_modes()` (STATIC en lo estático, DISABLED en ruinas, humo, polvo y partículas).

> **Nota de WP-24b (2026-09-20)**: el distrito A se regeneró con una **rejilla no uniforme por carriles** (`CityGrid.lane_count/lane_kind/lane_width/lane_start/lane_centre`, `street_width_at`, `get_core_extent`, `avenue_crossing`): carriles de edificio de 32 m, **calles de 16 m** (vereda 3 + calzada 10 + vereda 3) y **una avenida por eje de 32 m** (vereda 5 + calzada 10 + cantero 2 + calzada 10 + vereda 5), con anillo perimetral de 16 m → **432 × 272 m** (núcleo 400 × 240; antes 480 × 288 con cada calle ocupando una celda entera de asfalto). Calzada a 0,03 m y vereda/cantero/patio a 0,18 m (cordón de 15 cm = cara lateral de `Sidewalk_Chunk_2`, que es una losa plana sin cordón modelado); base de edificio a 0,18 m (antes hundidos 18 cm). Cinco `MultiMeshInstance3D` (`RoadEW` 150, `RoadNS` 126 girada 90° para que las bandas pintadas corran a lo largo, `Crossings` 140 con una malla propia de asfalto liso que apunta a un parche del atlas `roads.tres`, `Sidewalks` 768, `BlockPads` 240 de `Sidewalk_Tile_1` a escala uniforme 0,8), 1 424 instancias, 0 colisionadores de calle; sin senda peatonal (el atlas no la trae). **Fachadas a la línea municipal**: cada manzana sortea molinete o peine, el lado largo del edificio da a la calle y el resto es patio (`city_check._check_facade`: ≤ 0,05 m de la línea, base 0,18 ± 0,011). **Silueta**: 6 hitos `Building_3` a `height_scale` 0,90–1,00 (74–80 m, pisos reales) elegidos entre las celdas de perfil torre por cercanía al cruce de avenidas con separación ≥ 72 m; 15 torres medias `tower_b`/`block_mid` a 1,20–1,35 (15–17 m); 39 bloques bajos a 0,85–1,20 (7–15 m). Se descartó la opción «`Building_3` a 0,4–0,6» de la Nota de WP-13: dejaba pisos de 1,2–1,7 m, que es lo que el usuario vio como «estructuras muy escaladas». **Props a escala** (`nodes/root_scale` por pieza, tabla en `city_import_check.ROOT_SCALE_BY_PIECE` ± 0,01): `SateliteDish` 2,0 (1,8 m), `Advertising_6` 2,8 (3,4 × 5,0 m, vertical), `Advertising_7` 3,3 (5,9 × 3,0 m, horizontal), `Advertising_5` 3,0 (2,1 × 4,8 m, importado y fuera de `prop_pieces`: colgarlo de fachada pide otro anclaje); giro en pasos de 90°, huella entera sobre la azotea, altura horneada. **Rocas** 8–18 m, fuera de la extensión y a ≥ 30° de la línea aparición→centro (`rock_spots()`). `EnemySpawn0..3` a (0, ±176) y (±256, 0); marcadores de pila repartidos por todo el distrito (seis en calle, dos en azoteas a techo + 3,2 m porque `BatterySpawner._is_clear()` usa una esfera de 2,5 m) — concentrarlos cerca del centro bajaba la duración media de `balance_check` de 428 a 296 s. `city_check` ganó `grid_layout` por carriles, `_check_facade`, `_check_skyline`, `street_batching` con orientación de bandas y material del cruce, `rocks_ground` 8–18 m y ángulo, `_check_prop_scale`; `MultiMesh.buffer` se decodifica a mano porque `get_instance_transform()` es nula en headless. Efecto en el balance: el jefe hace un 22 % más de `approach` entre blancos (fachadas alineadas) y la partida de control tarda 444–470 s en tirar la ciudad (antes 430–442): el techo de 450 s de `RANGE_CONTROL` queda sin margen (WP-24d lo resuelve con la marcha o ensanchando a 480). §4.1/§4.3/§4.4/§9.3/§10/§11.2 de este documento quedan desactualizados: manda esta nota.

> **Nota de WP-13 (2026-09-19, hechos medidos al importar el pack)**: (1) los FBX NO están en centímetros: ufbx ya convierte unidades y `BuildingBlock_1` importa con 2,50 m de alto a escala 1, así que el `nodes/root_scale` correcto es **5.0** (queda en 12,50 m), no 0.01; todas las menciones a 0.01 en este doc quedan superadas. (2) Los FBX viven en `assets/city/models/` (no `pieces_src/`), las texturas redimensionadas en `assets/city/textures/` y los materiales propios en `assets/city/materials/` (`materials/extract` no sirve: el pack trae rutas absolutas rotas y tres emisivas apuntan a archivos que no existen). (3) El importador no genera LODs para estas mallas voxel (normales duras y atlas por cara: meshoptimizer no encuentra aristas colapsables); el check verifica la opción del preset y el `shadow_mesh`, no niveles de LOD reales. (4) Alturas reales: `Building_3` = **81 m** (única pieza alta; a escala 1 es un rascacielos que empequeñece al coloso de 29 m: WP-20 debe usarla con `height_scale` ≈ 0.4–0.6 o reservarla como hito único), `BuildingBlock_19/18/1/2` = 12,5 m, `BuildingBlock_24` = 8 m; anchos de `BuildingBlock_1/2` = **30 m** (desbordan la celda de 24 m: WP-20 usa el metadato `base_size` de cada pieza y ajusta la celda o escala en XZ). Ver `assets/city/README.md` y `tools/city_import_check.gd`.


Especifica la ciudad que el jugador debe defender: cómo se importa el pack **FreeSample**, cómo se arma el distrito, cómo se destruyen los edificios por etapas, cómo se mide la integridad y cómo se gestionan los escombros. Gobierna dos paquetes de trabajo:

- **WP-13** (§2): import de las 13 piezas FBX, escala, texturas, colisión y LODs. Puede ejecutarse en paralelo con WP-02…11.
- **WP-20** (§3–§8): `Building`, `BuildingProfile`, `CityGrid`, `district_a`, `CityIntegrity`, `DebrisPool`, `RubbleField`, rocas y terreno.

**NO incluye**: cómo el jefe elige objetivo ni los valores de sus ataques (`docs/06`, `docs/07`); el daño de un escombro al dron (`docs/09`); barra de integridad y marcadores (`docs/12`); `Environment`, SDFGI y presets gráficos (`docs/13`); la derrota dentro de la máquina de ronda (`docs/11`).

---

## 2. Import del pack FreeSample (WP-13)

Origen: `godot/assets/_raw/FreeSample.zip` (57 MB, 13 FBX + 12 PNG). El ZIP **no se extrae dentro del repo**: se copia a `godot/assets/city/` sólo lo que se usa, y `godot/assets/_raw/` lleva `.gdignore`.

### 2.1 Inventario de las 13 piezas y uso propuesto

| FBX | Escena de pieza | Rol | Perfil | HP |
|---|---|---|---|---|
| `Building_3` | `city/pieces/tower_a.tscn` | Torre alta, silueta principal del centro | `tower_a` | 3 500 |
| `BuildingBlock_19` | `city/pieces/tower_b.tscn` | Torre alta, variante | `tower_b` | 3 500 |
| `BuildingBlock_18` | `city/pieces/block_mid.tscn` | Bloque medio | `block_mid` | 1 200 |
| `BuildingBlock_1` | `city/pieces/block_low_a.tscn` | Bloque bajo — **pieza de calibración de escala** | `block_low` | 1 200 |
| `BuildingBlock_2` | `city/pieces/block_low_b.tscn` | Bloque bajo, variante | `block_low` | 1 200 |
| `BuildingBlock_24` | `city/pieces/block_low_c.tscn` | Bloque bajo, variante | `block_low` | 1 200 |
| `Advertising_5` | `city/pieces/props/sign_a.tscn` | Cartel de fachada (emisivo) | — | — |
| `Advertising_6` | `city/pieces/props/sign_b.tscn` | Cartel **vertical** de azotea (6 × 9 × 1,5 m con el import a ×5; medido en el diagnóstico de P2, 2026-09-20: los roles de `_6`/`_7` estaban invertidos en esta tabla) | — | — |
| `Advertising_7` | `city/pieces/props/sign_c.tscn` | Cartel **horizontal** de azotea (9 × 4,5 × 2,5 m con el import a ×5) | — | — |
| `SateliteDish` | `city/pieces/props/dish.tscn` | Prop de azotea, se desprende como escombro cosmético | — | — |
| `Road_Chunk_5` | `city/pieces/road_chunk.tscn` | Calzada (instanciada en `MultiMesh`) | — | — |
| `Sidewalk_Chunk_2` | `city/pieces/sidewalk_chunk.tscn` | Vereda de tramo (`MultiMesh`) | — | — |
| `Sidewalk_Tile_1` | `city/pieces/sidewalk_tile.tscn` | Baldosa de vereda (`MultiMesh`) | — | — |

Los props (`Advertising_*`, `SateliteDish`) **no tienen HP propio**: son hijos decorativos de un `Building` y, cuando éste pasa a `DAMAGED`, se desprenden como `DebrisChunk` cosméticos (masa baja, sin daño estructural). Sólo hay **dos** piezas altas para 21 torres: la variedad se consigue con escala vertical y rotación en pasos de 90° (§4.3), no con mallas nuevas.

### 2.2 Escala y verificación

Los FBX declaran `UnitScaleFactor = 1.0` y `UpAxis = Y`; por el origen del pack es casi seguro que están en **centímetros**. Procedimiento obligatorio: (1) copiar los 13 FBX a `assets/city/pieces_src/` e importarlos con los valores por defecto (`nodes/root_scale = 1.0`); (2) ejecutar `city_import_check`, que imprime el AABB agregado de cada pieza; (3) si `BuildingBlock_1` mide ~1 200 unidades de alto, fijar **`nodes/root_scale = 0.01`** en los 13 `.fbx.import` y reimportar (si midiera ~12, dejarlo en 1.0); (4) volver a ejecutar el check, donde **`BuildingBlock_1` debe medir entre 12 y 16 m**.

Los `.fbx.import` se **comiten**. Nunca se corrige la escala poniendo `scale` en el nodo de la escena: eso rompe las formas de colisión y `docs/03` prohíbe escalar cuerpos físicos.

Opciones de import comunes a las 13 piezas: `nodes/root_scale` `0.01` (a confirmar en el paso 3) con `nodes/apply_root_scale = true` para que la escala se hornee en los vértices · `nodes/root_type = "StaticBody3D"` y `nodes/root_name` con el nombre de la pieza, para que la raíz ya sea el cuerpo de colisión y los nodos sean estables en las escenas heredadas · `meshes/generate_lods = true` (60 edificios en pantalla; los enemigos usan `false`, `docs/05`) · `meshes/create_shadow_meshes = true` · `meshes/ensure_tangents = true` · `materials/extract = true` con `materials/extract_path = res://assets/city/materials/`, para que los materiales salgan a `.tres` y compartan las texturas 2K/1K · `animation/import = false` · `import_script/path = res://asset_import/import_city_piece.gd` (§2.4).

### 2.3 Texturas y presupuesto de VRAM

De los 12 PNG del pack se conservan **8**. Los cuatro `VoxelCity_CompositeBuildings_Optimized-*` se **descartan** si las cuatro `*Diffuse` cubren todas las UV de las 13 piezas, lo que se verifica al extraer los materiales (paso 2.2); si alguna pieza sí referencia un composite, se conserva **sólo ese** a 2K y se anota en `CREDITS.md`. Todas con `compress/mode = 2` (VRAM Compressed) y `mipmaps/generate = true`:

| Texturas | Destino | Cantidad | VRAM BC1 | VRAM BC7 |
|---|---|---|---|---|
| `T_Buildings_001/002Diffuse` | 2048² | 2 | 5.33 MB | 10.67 MB |
| `T_PropsDiffuse`, `T_RoadsDiffuse` | 1024² | 2 | 1.33 MB | 2.67 MB |
| `BAKE_*Emissive` (buildings 001/002, props, roads) | 1024² | 4 | 2.67 MB | 5.33 MB |
| **Total** | | **8** | **9.4 MB** | **18.6 MB** |

El reescalado se hace con `process/size_limit` (2048 o 1024) en el `.import`, no editando los PNG: el original queda intacto y el ajuste es reversible. El presupuesto del plan es **< 90 MB** y sobra margen de 4× a 9×; el check existe para atrapar el caso contrario, porque los cuatro diffuse a 4 096² sin comprimir con mipmaps son **358 MB**, cuatro veces el presupuesto por sí solos.

Ajustes adicionales: `mipmaps/generate = true` es obligatorio en 3D (evita el aliasing de las fachadas a distancia), `detect_3d/compress_to = 0` para que Godot no cambie el modo por su cuenta, y `compress/high_quality = false` por defecto (BC1/BC3), subiendo a BPTC sólo si aparecen artefactos en el grading de `docs/13`.

### 2.4 `import_city_piece.gd`

`asset_import/import_city_piece.gd`, `EditorScenePostImport`:

```gdscript
@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object
```

Responsabilidades, en orden:

1. **Garantizar la raíz `StaticBody3D`**: si `nodes/root_type` ya la creó se usa, si no se crea y se reparenta todo bajo ella. `collision_layer = 128` (capa 8 `city`), `collision_mask = 311` (capas 1,2,3,5,6,9 según `docs/02` §3.1).
2. **Forma de colisión** por tabla de nombres, determinista y revisable: `Building_3`, `BuildingBlock_*`, `Road_Chunk_5` y `Sidewalk_*` → **`BoxShape3D`** del AABB agregado (los edificios son cajas y además deben poder redimensionarse por variación de altura, §4.3); `SateliteDish` y `Advertising_*` → **`ConvexPolygonShape3D`** con `mesh.create_convex_shape(true, true)`.
3. **Mallas**: `gi_mode = GI_MODE_STATIC` y `cast_shadow = SHADOW_CASTING_SETTING_ON` en cada `MeshInstance3D`; en los props, además `visibility_range_end = 180.0` y `visibility_range_fade_mode = VISIBILITY_RANGE_FADE_SELF`.
4. **Metadatos** en la raíz: `piece_id` y `base_size` (el AABB), para que las escenas heredadas y `CityGrid` no recalculen dimensiones en runtime.
5. Asignar `owner` a todo nodo creado y devolver `scene`.

Los LOD **no** se generan aquí: los produce el importador. El runtime no expone el número de niveles, así que `city_import_check` comprueba la **opción** en el `.import`.

### 2.5 `city/pieces/*.tscn`

Cada pieza jugable es una **escena heredada** de la escena importada («Nueva escena heredada»). La raíz heredada ya es el `StaticBody3D` de la capa 8; se le asigna `script = res://city/building.gd` y se añaden los nodos de etapa:

```
tower_a (Building : StaticBody3D, capa 8, máscara 311)
├─ StageIntact (Node3D) → Mesh (malla importada, gi_mode STATIC) + Windows (emisivo)
├─ StageDamaged (Node3D, visible = false) → Mesh (misma malla + damage_overlay.gdshader)
├─ StageRubble (Node3D, visible = false) → Mesh (rubble_pile_*) + Smoke (GPUParticles3D) + Dust (FogVolume BOX)
├─ IntactShape (CollisionShape3D — BoxShape3D)
├─ RubbleShape (CollisionShape3D — BoxShape3D baja, disabled = true)
├─ DustBurst (GPUParticles3D, one_shot) + FireLight (OmniLight3D, visible = false)
└─ CollapseSound (AudioStreamPlayer3D, bus City)
```

Las piezas de calle (`road_chunk`, `sidewalk_chunk`, `sidewalk_tile`) **no** llevan `Building` ni colisión propia: se dibujan con `MultiMeshInstance3D` y el suelo lo aporta una única caja de terreno (§4.4), lo que ahorra ~120 colisionadores.

---

## 3. `Building` y etapas de destrucción (WP-20)

### 3.1 Máquina de etapas

```
INTACT  ──ratio ≤ 0.60──▶  DAMAGED  ──ratio ≤ 0.15──▶  RUBBLE (absorbente)
```

`take_damage(amount, point)`: (1) si `stage == RUBBLE` retorna de inmediato, una ruina no recibe más daño; (2) `hp = max(0.0, hp - amount)` y `CityIntegrity` recibe el delta real aplicado; (3) si `get_ratio() <= rubble_threshold` → `hp = 0.0` y transición a `RUBBLE`; (4) si no, y `get_ratio() <= damaged_threshold` con `stage == INTACT` → transición a `DAMAGED`; (5) `stage_changed(stage)` sólo en la transición.

Poner `hp = 0` al entrar en `RUBBLE` hace que la integridad de una ciudad arrasada valga exactamente **0.0** y que `Events.city_integrity_changed` sea monótona no creciente por construcción. La consecuencia es que **el coste efectivo de derribar un edificio es el 85 % de su HP nominal**:

| Perfil | `max_hp` nominal | Coste efectivo (85 %) | Con `siege_beam` (700 HP/s) |
|---|---|---|---|
| `block_low` / `block_mid` | 1 200 | 1 020 | 1.46 s |
| `tower_a` / `tower_b` | 3 500 | 2 975 | 4.25 s |

### 3.2 Presentación por etapa

**INTACT** — malla completa, ventanas emisivas encendidas (`emission_energy = 1.0`), `IntactShape` activa.

**DAMAGED** — se conmuta a `StageDamaged`. El look se consigue **sin autorar 13 mallas dañadas**: el mismo mesh con un material `damage_overlay.gdshader` que recorta huecos con ruido (`ALPHA_SCISSOR_THRESHOLD` sobre un `NoiseTexture2D` triplanar, con `damage_amount` como uniform 0–1), apaga los emisivos de ventana y oscurece el albedo con hollín en las zonas recortadas. Se encienden dos o tres `GPUParticles3D` de fuego (`amount = 24`, continuos) y la `FireLight` (naranja, parpadeo por `Tween` en bucle sobre `light_energy` 1.4 ± 0.6, período 0.35 s). La colisión **no cambia**. Los props se desprenden aquí como escombros cosméticos.

**RUBBLE** — animación de derrumbe de `collapse_seconds` (1.8 s) con `Tween`:

1. `t = 0` — `DustBurst.restart()`, `CollapseSound.play()`, `Events.camera_trauma(profile.trauma, global_position)`, y se piden `debris_count` trozos al `DebrisPool` con impulso radial hacia afuera y hacia arriba.
2. `0 → 1.8 s` — `StageIntact`/`StageDamaged` descienden `height * 0.35` y se desvanecen; `StageRubble` aparece y crece de 0.6 a 1.0.
3. `t = 1.8 s` — `IntactShape.disabled = true`, `RubbleShape.disabled = false` (caja baja de `height * 0.18`), `Smoke` y `FogVolume` activos, `destroyed(value)` y `Events.building_destroyed(global_position, value)`.

La columna de humo es un `GPUParticles3D` continuo (`amount = 48`, `lifetime = 6.0`, `draw_order = DRAW_ORDER_VIEW_DEPTH`) más un `FogVolume` local (`FOG_VOLUME_SHAPE_BOX`, `size ≈ (30, 40, 30)`, `density 0.03`) para el polvo volumétrico, ambos con `visibility_range_end = 400 m`. Las mallas de ruina (`rubble_pile_low/mid/high.mesh`) son **propias** (pipeline voxel de `docs/05` o CSG horneado): FreeSample no trae variantes dañadas. `StageRubble` y los escombros van con **`GI_MODE_DISABLED`** por el riesgo 9 del plan (popping de SDFGI con geometría que cambia).

---

## 4. `CityGrid` y `district_a`

### 4.1 Geometría de la rejilla

Celda de **24 m**. Patrón de manzana: bloques de **2×2 celdas de edificio** separados por **1 celda de calle**, con período 3; **5 bloques en X × 3 en Z** → rejilla de 15 × 9 celdas = **360 × 216 m**, con (5×2) × (3×2) = **10 × 6 = 60 edificios exactos** y 75 celdas de calle. Una celda es de calle si `x % 3 == 2` o `z % 3 == 2`. El resultado es determinista: el check no cuenta «aproximadamente 60», cuenta 60.

### 4.2 Reparto de HP

| Perfil | Cantidad | `max_hp` | Subtotal |
|---|---|---|---|
| Bajos y medios (`block_low_a/b/c`, `block_mid`) | **39** | 1 200 | 46 800 |
| Torres (`tower_a`, `tower_b`) | **21** | 3 500 | 73 500 |
| **Total** | **60** | | **120 300** |

120 300 está a **+0.25 %** de los 120 000 del plan, dentro del ±5 % exigido.

Las 21 torres se concentran en los **3 bloques centrales** (centro financiero) y los bajos ocupan la periferia: da una silueta legible desde el aire, orienta al jugador y justifica que el jefe camine hacia el centro.

Coste efectivo de arrasar la ciudad: `0.85 × 120 300 = 102 255` HP. Para que caiga en 5 min sin oposición el jefe necesita **341 HP/s** sostenidos; `docs/07` debe verificar que su mezcla de `siege_beam` (700 HP/s), `stomp` (2 500) y `walk` (900 por edificio pisado) lo alcanza. Es un punto de balance de WP-23.

### 4.3 Siembra y variación

`CityGrid.build()` con un `RandomNumberGenerator` sembrado con `seed` (que el nivel toma de `Global.round_seed`): recorre las 60 celdas de edificio en orden fijo; elige perfil según la zona (centro → torre, periferia → bajo/medio) y variante de pieza al azar entre las de ese perfil; instancia y posiciona en el centro de la celda con `yaw = randi_range(0, 3) * 90°`; y aplica una variación de altura `height_scale ∈ [0.85, 1.35]`.

**La variación de altura NO escala el cuerpo físico.** `Building.apply_variation(height_scale, yaw_steps)` escala únicamente los `MeshInstance3D` de las etapas y **reescribe** `BoxShape3D.size.y` y la posición de la forma:

```
shape.size = Vector3(base.x, base.y * height_scale, base.z)
shape_node.position.y = shape.size.y * 0.5
```

Escalar un `StaticBody3D` produce formas de colisión inconsistentes en Jolt; está prohibido por `docs/03` y verificado por revisión.

El distrito resultante se guarda como **escena concreta** `city/districts/district_a.tscn` (generada una vez con `seed = 0` y comiteada), no se genera en cada arranque: así el horneado de oclusores, la iluminación y el check son reproducibles.

### 4.4 Terreno, calles y rocas

- **Suelo**: un único `StaticBody3D` de capa **1** (`world`, máscara 2,3,6,9) con un `BoxShape3D` de `1200 × 4 × 1200 m` centrado en `y = −2` (superficie en `y = 0`). Cubre el distrito y el descampado con **un solo colisionador**; el raycast de pie del jefe (máscara `1|8` = 129) y el de LOS lo encuentran sin problema. El relieve exterior es un `PlaneMesh` de 1 200 m con material triplanar; el `HeightMapShape3D` queda para después del MVP.
- **Calles y veredas**: puramente visuales, en tres `MultiMeshInstance3D` (`road_chunk`, `sidewalk_chunk`, `sidewalk_tile`) con `gi_mode = STATIC`: **3 draw calls** para toda la red viaria.
- **Rocas y colinas**: **6** piezas (rango admitido 5–8) en el borde, a 40–90 m del perímetro, de 18–40 m de alto. Malla voxel propia o CSG horneado con `StandardMaterial3D` y `uv1_triplanar = true` (sin UV autoradas), `StaticBody3D` de capa **1** con `ConvexPolygonShape3D`, en el grupo **`city_rocks`**. Sirven de percha para el dron, de cobertura contra el `head_laser` y de punto de escalada para el jefe.

---

## 5. `CityIntegrity`

```
ratio = Σ hp_actual / Σ hp_inicial
```

Implementación **incremental**: `CityIntegrity` no vuelve a sumar los 60 edificios cada frame; `Building.take_damage()` notifica el delta aplicado y se resta de un acumulador, con `Σ hp_inicial` calculado una sola vez. `Events.city_integrity_changed(ratio)` se emite cuando `ratio` baja ≥ 0.002 o han pasado 0.25 s con un cambio pendiente. Es monótona no creciente por construcción: no hay reparación en el MVP y `RUBBLE` es absorbente. Al cruzar `defeat_ratio = 0.35` se emite `defeat_threshold_reached()` **una sola vez**; `RoundManager` (`docs/11`) escucha la señal del bus y decide la derrota — `CityIntegrity` no conoce la máquina de ronda.

**Edificio «bajo asedio»**: `CityIntegrity` mantiene, a 4 Hz, una ventana deslizante de 3 s del daño recibido por edificio. El que más acumule en la ventana, si supera `siege_min_damage` (150 HP), se marca con `mark_under_siege(true)` y el anterior se desmarca. El `Building` marcado enciende un emisivo de baliza y entra en el grupo **`buildings_under_siege`**, que `OffscreenMarkers` (`docs/12` §4.1) recorre. El coste es un `Dictionary` de 60 entradas revisado 4 veces por segundo.

Todo `Building` pertenece además al grupo **`buildings`**, que es como `RoundManager` (`docs/11` §4.2) los registra tras instanciar el distrito con `CityIntegrity.rebuild()`.

---

## 6. `DebrisPool` y `RubbleField`

`DebrisPool` es **compartido con los enemigos** (`docs/06`): un único pool por nivel, cableado por `battle_level.tscn`, con **máximo 24 `DebrisChunk` vivos**.

`DebrisChunk` es un `RigidBody3D` de capa **9** (256) con máscara **387** (capas 1,2,8,9), `gi_mode = DISABLED`, `cast_shadow = ON` y `contact_monitor = false` — quien detecta el golpe al dron es el propio dron (`docs/09`). `continuous_cd = true` sólo si `mass > 800` kg, para que un trozo de torre no atraviese el suelo. Vida de **20 s** (Anexo A), o retiro anticipado si lleva `sleeping == true` más de 2 s.

**Retiro y fusión**: al pedir el chunk número 25 se retira el más viejo con `freeze_mode = FREEZE_MODE_STATIC` y `freeze = true`, su transformada se hornea en el `RubbleField` de su malla, y el `RigidBody3D` se oculta, se limpia y vuelve a la lista libre.

`RubbleField` es un conjunto de `MultiMeshInstance3D`, **uno por malla distinta registrada**, con tope de **4 mallas** (≤ 4 draw calls): la ciudad registra dos (`debris_concrete_small/large`) y los enemigos hasta dos más. `instance_count = 512` por campo, `use_custom_data = true` (tinte por instancia), `gi_mode = DISABLED`.

`Events.camera_trauma(amount, position)` se emite una vez por derrumbe con `amount = profile.trauma`. **El emisor no atenúa por distancia**: publica el hecho («hubo un derrumbe de intensidad A en P») y el `CameraRig` aplica `trauma += amount * clamp(1 − distancia / trauma_radius, 0, 1)` con `trauma_radius` ≈ 120 m (`docs/13`). Así el bus sigue publicando hechos, como exige el Contrato de Events (`docs/02` §5.1). El sonido es un `AudioStreamPlayer3D` del propio `Building` (bus `City`, `unit_size` 60 m, `max_distance` 400 m).

---

## 7. Rendimiento

Medidas: LOD de malla por `meshes/generate_lods = true` con `rendering/mesh_lod/lod_change/threshold_pixels = 1.0` · props lejanos con `visibility_range_end = 180 m` y `FADE_SELF` · humo y niebla de ruinas a 400 m · `rendering/occlusion_culling/use_occlusion_culling = true` con **15 `OccluderInstance3D`** horneados (uno por bloque de 2×2) sobre `district_a` · calles en 3 `MultiMeshInstance3D` en vez de ~120 nodos · 1 caja de suelo en vez de ~120 colisionadores de calle · `GI_MODE_STATIC` en edificios y `DISABLED` en ruinas y escombros (riesgo 9) · `create_shadow_meshes = true`. **Presupuesto de draw calls** (el tope de WP-24 es < 900 a 1080p): 60–120 por los edificios (1–2 superficies cada uno), 3 por calles y veredas, 3 por props, ≤ 4 por `RubbleField`, ≤ 24 por escombros vivos, 8 por rocas y terreno, ~24 por el jefe, ~9 por dron y trazadores y ≤ 12 de VFX (tope de `vfx_check`) → **≈ 150–210 en total**. Queda margen de 4× para el `Environment`, las sombras en cascada y el fisheye. La medición real es de `render_check` (WP-24, `docs/15`).

---

## 8. Fuego amigo del arma

Un proyectil del jugador que impacta en la capa 8 llama a `Building.take_damage(amount, point)` con `amount = damage × city_friendly_fire_scale` = `12 × 0.5` = **6** (`docs/08` §2.7). `ProjectilePool` acumula el daño estructural causado por el jugador y lo expone con `get_friendly_fire_damage()`. Consecuencias que el diseño acepta: el jugador **puede** derribar edificios (1 020 HP efectivos / 6 = **170 impactos** para un bloque bajo, ~39 s de fuego sostenido) — caro pero posible, que es lo que hace que el castigo de puntaje importe; la integridad baja igual venga el daño de quien venga, porque `CityIntegrity` no distingue la fuente, así que la derrota por integridad < 0.35 puede provocarla el propio jugador; y el `Building` **no** recibe la identidad del atacante (el escalado lo aplica el llamador), con lo que `take_damage(amount, point)` queda estable para enemigos y jugador. Penalización de puntaje **propuesta**: `−0.02 × friendly_fire_damage`, a fijar en `docs/11`.

---

## 9. Interfaz pública

### 9.1 `Building`

```gdscript
class_name Building extends StaticBody3D
enum Stage { INTACT, DAMAGED, RUBBLE }
signal stage_changed(stage: Stage)
signal destroyed(value: int)
signal damage_taken(amount: float, point: Vector3)
@export var profile: BuildingProfile
@export var stage_intact: Node3D                   # + stage_damaged, stage_rubble
@export var intact_shape: CollisionShape3D         # + rubble_shape
@export var fire_light: OmniLight3D                # + dust_burst, collapse_sound
@export var debris_pool: DebrisPool
var hp: float
var stage: Stage = Stage.INTACT
var value: int
func take_damage(amount: float, point: Vector3) -> void
func get_ratio() -> float
func get_max_hp() -> float
func is_destroyed() -> bool
func mark_under_siege(active: bool) -> void
func apply_variation(height_scale: float, yaw_steps: int) -> void
func reset() -> void
```

### 9.2 `BuildingProfile`

```gdscript
class_name BuildingProfile extends Resource
@export var id: StringName = &"block_low"
@export_range(1.0, 50000.0) var max_hp: float = 1200.0
@export_range(0.0, 1.0) var damaged_threshold: float = 0.60
@export_range(0.0, 1.0) var rubble_threshold: float = 0.15
@export var mesh_intact: Mesh                      # + mesh_damaged, mesh_rubble
@export_range(0, 32) var debris_count_min: int = 4
@export_range(0, 32) var debris_count_max: int = 8
@export_range(1.0, 10000.0) var debris_mass: float = 450.0
@export_range(0.0, 5.0) var dust_scale: float = 1.0
@export_range(0, 10000) var value: int = 100
@export_range(0.1, 10.0) var collapse_seconds: float = 1.8
@export_range(0.0, 2.0) var trauma: float = 0.65
@export_range(1.0, 200.0) var height: float = 14.0
@export_range(0.0, 1.0) var rubble_height_factor: float = 0.18
```

Perfiles iniciales: `city/profiles/block_low.tres`, `block_mid.tres`, `tower_a.tres`, `tower_b.tres`.

### 9.3 `CityGrid`, `CityIntegrity`, `DebrisPool`, `RubbleField`

```gdscript
class_name CityGrid extends Node3D
@export_range(1.0, 100.0) var cell_size: float = 24.0
@export_range(1, 20) var block_cols: int = 5       # + block_rows 3, block_span 2
@export var seed: int = 0
@export var low_pieces: Array[PackedScene]         # + tall_pieces
@export var low_profiles: Array[BuildingProfile]   # + tall_profiles
@export_range(0, 200) var tall_count: int = 21
@export var debris_pool: DebrisPool
func build() -> void
func get_buildings() -> Array[Building]
func get_building_at(cell: Vector2i) -> Building
func get_extent() -> Vector2                       # (360, 216) m
func is_street_cell(cell: Vector2i) -> bool

class_name CityIntegrity extends Node
signal integrity_changed(ratio: float)
signal defeat_threshold_reached()
@export var grid: CityGrid
@export_range(0.0, 1.0) var defeat_ratio: float = 0.35
@export_range(0.0, 10.0) var siege_window: float = 3.0
@export_range(0.0, 5000.0) var siege_min_damage: float = 150.0
func rebuild() -> void                             # alias documentado: reset() + alta de todo el grupo "buildings"
func register(building: Building) -> void
func get_ratio() -> float                          # CANÓNICO: lo usan docs/11 y docs/12
func ratio() -> float                              # alias documentado de get_ratio()
func get_total_hp() -> float
func get_initial_hp() -> float
func get_under_siege() -> Building                 # null si no hay
func get_destroyed_count() -> int
func reset() -> void

class_name DebrisPool extends Node3D
const MAX_LIVE: int = 24
@export var rubble_field: RubbleField
@export_range(1.0, 120.0) var debris_lifetime: float = 20.0
func request(mesh: Mesh, shape: Shape3D, xform: Transform3D, mass: float, impulse: Vector3, lifetime: float) -> DebrisChunk
# adopt() reparenta nodos YA EXISTENTES bajo el chunk: es la forma que usa el
# desprendimiento de partes de enemigo (docs/06 §4.1). Firma cerrada, no negociable.
func adopt(mesh: MeshInstance3D, body: PhysicsBody3D, mass: float,
        impulse: Vector3, lifetime: float) -> DebrisChunk
func get_live_count() -> int
func retire_oldest() -> void
func clear() -> void

class_name RubbleField extends Node3D
func register_mesh(mesh: Mesh) -> int              # −1 si ya hay 4 campos
func bake(mesh_index: int, xform: Transform3D, tint: Color) -> void
func get_field_count() -> int
func get_instance_count(mesh_index: int) -> int
func clear() -> void
```

### 9.4 Capas de física usadas

| Elemento | Capa | Máscara | Valores |
|---|---|---|---|
| `Building` (intacto y ruina) | 8 `city` | 1,2,3,5,6,9 | layer **128** / mask **311** |
| Suelo y rocas | 1 `world` | 2,3,6,9 | layer **1** / mask **294** (`2+4+32+256`) |
| `DebrisChunk` | 9 `debris` | 1,2,8,9 | layer **256** / mask **387** |
| Consulta de pie y de LOS del jefe | — | 1,8 | mask **129** |
| Consulta de espacio libre de pilas (`docs/09`) | — | 8,9 | mask **384** |

### 9.5 Eventos publicados

| Señal de `Events` | Firma canónica de este doc | Emitida por |
|---|---|---|
| `building_destroyed` | `(position: Vector3, value: int)` | `Building` |
| `city_integrity_changed` | `(ratio: float)` | `CityIntegrity` — coincide con `docs/11` y `docs/12` |
| `camera_trauma` | `(amount: float, position: Vector3)` | `Building` (derrumbe) |

> **Reconciliación cerrada (2026-09-19)**: gana la forma de **dos** argumentos, `camera_trauma(amount: float, position: Vector3)`, ya fijada en el Contrato de Events (`docs/02` §5.1). `docs/06` y `docs/07` pasaron a emitir la posición. El motivo es el de siempre: sin ella el emisor tendría que conocer dónde está la cámara para atenuar, y el bus dejaría de publicar hechos.

---

## 10. Parámetros y valores iniciales

Del **plan (§4.7 y Anexos A–C del borrador; ver `docs/00` §4.1)** (valores cerrados): celda de 24 m · **60 edificios** · HP 1 200 (bajos) y 3 500 (torres) con total ≈ 120 000 · umbrales de etapa 0.60 / 0.15 · `debris_count` 4–8 por transición · `debris_lifetime` 20 s · `defeat_ratio` 0.35 · `MAX_LIVE` del pool 24 · rocas 5–8 · texturas 2 048² (edificios) y 1 024² (props, calles, emissive) VRAM Compressed con mipmaps · presupuesto de VRAM < 90 MB.

**Propuestas de este documento**:

| Parámetro | Valor | Justificación |
|---|---|---|
| Rejilla | 15 × 9 celdas = 360 × 216 m | única disposición que da **60 edificios exactos** con manzanas de 2×2 |
| Reparto | 39 bajos/medios + 21 torres = **120 300 HP** | +0.25 % sobre los 120 000 del plan |
| `debris_mass` (bajo / torre) | 450 / 2 000 kg | mapea a 17.1 y 28.0 de daño al dron (`docs/09`) |
| `collapse_seconds` | 1.8 s | deja margen sobrado frente al criterio de < 6 s |
| `trauma` (bajo / torre) | 0.65 / 0.85 | una torre se siente más que un bloque |
| `value` (bajo / torre) | 100 / 300 | pesa el puntaje y la prioridad de «bajo asedio» |
| `rubble_height_factor` | 0.18 | la ruina sigue siendo obstáculo, no pared |
| `siege_window` / `siege_min_damage` | 3.0 s / 150 HP | evita que la baliza salte entre edificios |
| Campos de `RubbleField` | ≤ 4, 512 instancias | 2 para la ciudad y 2 para los enemigos |
| Rocas / suelo | 6 de 18–40 m / caja 1 200 × 4 × 1 200 m capa 1 | un solo colisionador para todo el terreno |
| `nodes/root_scale` | 0.01 (a confirmar en §2.2) | centímetros → metros |
| `visibility_range_end` props / humo | 180 m / 400 m | recorta el grueso de los draw calls lejanos |
| Oclusores | 15, uno por bloque | horneados sobre `district_a` |
| `city_friendly_fire_scale` | 0.5 | ver §8 y `docs/08` |

---

## 11. Criterios de aceptación y checks headless

Comando base:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/<x>_check.tscn
```

### 11.1 `city_import_check` (WP-13)

**Archivo**: `tools/city_import_check.tscn` + `tools/city_import_check.gd`.

| # | Sub-check | Criterio |
|---|---|---|
| 1 | `pieces_present` | Las **13** rutas de `assets/city/pieces_src/*.fbx` existen y `load()` devuelve una `PackedScene` instanciable |
| 2 | `root_is_body` | La raíz de cada pieza es un `StaticBody3D` con `collision_layer == 128` y `collision_mask == 311` |
| 3 | `has_shape` | ≥ 1 `CollisionShape3D` con `shape != null`; `BoxShape3D` en las 6 de edificio y las 3 de calle, `ConvexPolygonShape3D` en `SateliteDish` y `Advertising_*` |
| 4 | `scale_reference` | AABB agregado de los `MeshInstance3D` de `BuildingBlock_1`: `size.y` ∈ **[12, 16] m** |
| 5 | `scale_sanity` | Toda pieza con `0.2 m < size.y < 120 m` (atrapa el factor 100 en cualquier dirección) |
| 6 | `import_options` | En cada `<pieza>.fbx.import` (`ConfigFile`): `nodes/root_scale` igual al valor fijado, `meshes/generate_lods == true`, `meshes/create_shadow_meshes == true`, `animation/import == false`, `import_script/path` → `import_city_piece.gd` |
| 7 | `gi_mode` | Todos los `MeshInstance3D` con `gi_mode == GI_MODE_STATIC`; props con `visibility_range_end == 180` y `FADE_SELF` |
| 8 | `texture_settings` | En cada `<png>.import` bajo `assets/city/`: `compress/mode == 2`, `mipmaps/generate == true`, `process/size_limit` ≤ 2048 en los diffuse de edificio y ≤ 1024 en props, calles y emissive |
| 9 | `texture_vram` | Estimación analítica `w × h × bpp × 4/3` desde `process/size_limit` y el formato implicado: suma **< 90 MB** |
| 10 | `composites_absent` | Ningún `VoxelCity_CompositeBuildings_Optimized-*` en `assets/city/`, o bien cuenta en el presupuesto del sub-check 9 |
| 11 | `restore` | No escribe en `user://` ni modifica ningún `.import` |

> El VRAM se estima leyendo los `.import` con `ConfigFile`, no consultando al `RenderingServer`: con `--headless` el controlador de render es nulo y sus contadores no son fiables. Además así se verifica la **intención** configurada, que es lo que hay que conservar en el repo.

### 11.2 `city_check` (WP-20)

**Archivo**: `tools/city_check.tscn` + `tools/city_check.gd`. Instancia `city/districts/district_a.tscn` y avanza el tiempo sintéticamente llamando a `_physics_process(1.0/100.0)` en bucle (los temporizadores de gameplay son acumuladores, no `Timer`).

| # | Sub-check | Criterio |
|---|---|---|
| 1 | `building_count` | `CityGrid.get_buildings().size() == 60`, todos en el grupo `buildings` |
| 2 | `hp_total` | `Σ profile.max_hp == 120300`, dentro de **120 000 ±5 %** → [114 000, 126 000] |
| 3 | `hp_mix` | **39** edificios con `max_hp == 1200` y **21** con `max_hp == 3500` |
| 4 | `grid_layout` | Extensión `(360, 216) m`; ningún edificio en celda de calle; distancia mínima entre centros ≥ 24 m |
| 5 | `no_body_scale` | Ningún `Building` con `scale != Vector3.ONE`; toda variación de altura reflejada en `BoxShape3D.size.y` |
| 6 | `stages` | Daño progresivo → `stage_changed(DAMAGED)` al cruzar 0.60 y `(RUBBLE)` al cruzar 0.15; `destroyed` **una** vez; `take_damage` posterior no cambia nada |
| 7 | `stage_visuals` | En `RUBBLE`: `intact_shape.disabled == true`, `rubble_shape.disabled == false`, sólo `stage_rubble.visible` |
| 8 | `collapse_time` | Desde el cruce del umbral hasta (`stage == RUBBLE` **y** todos sus `DebrisChunk` dormidos, retirados o congelados): **< 6 s** |
| 9 | `integrity_monotonic` | Destruyendo los 60 con semilla fija y muestreando `Events.city_integrity_changed`: sucesión monótona no creciente, valor final ≤ 0.001 |
| 10 | `integrity_defeat` | `defeat_threshold_reached()` emitido **exactamente una** vez, al cruzar 0.35 |
| 11 | `integrity_incremental` | `ratio()` coincide con `Σ hp / Σ hp_inicial` recalculado a mano en 5 puntos (±1e−4): el acumulador no deriva |
| 12 | `debris_cap` | Con 10 edificios destruidos seguidos, `get_live_count() <= 24` en **todos** los ticks |
| 13 | `debris_fusion` | El chunk retirado aparece en `RubbleField` y vuelve a la lista libre; tras `clear()`, 0 vivos y sin huérfanos; `get_field_count() <= 4` |
| 15 | `trauma` | Un `camera_trauma` por derrumbe, con `amount == profile.trauma` y `position` la del edificio; el emisor **no** atenúa por distancia |
| 16 | `rocks_ground` | 5–8 nodos en el grupo `city_rocks` con `collision_layer == 1`; un `StaticBody3D` de capa 1 cuyo `BoxShape3D` cubre ≥ 360 × 216 m con la cara superior en `y == 0 ±0.01` |
| 18 | `street_batching` | Exactamente **3** `MultiMeshInstance3D` para calzada y veredas; **0** colisionadores propios de calle |
| 19 | `friendly_fire` | `take_damage(6.0, p)` × 170 sobre un bloque bajo → llega a `RUBBLE`; el daño registrado coincide con el aplicado |
| 20 | `restore` | No escribe en `user://`; deja `Global.round_seed` como estaba antes de `quit()` |

Ambos checks imprimen una línea `[PASS]`/`[FAIL]` por sub-check y un resumen; `quit(0)` si todo pasa, `quit(1)` con el recuento de fallos si no.

---

## 12. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| 1 | **Firma de `camera_trauma`** | **Cerrado (2026-09-19)**: dos argumentos `(amount, position)` en `docs/02` §5.1; los cuatro emisores (06, 07, 09, 10) ya usan esa forma |
| 2 | **Escala real de los FBX** (riesgo 8 del plan) | Abierto hasta el paso 3 de §2.2. Se mide primero y se fija después; `city_import_check` bloquea el WP si `BuildingBlock_1` no cae en 12–16 m |
| 3 | **Licencia del pack FreeSample** (riesgo 11) | Abierto; lo cierra `docs/16` antes de publicar. No se redistribuye el ZIP, en el repo sólo quedan los derivados |
| 4 | **Mallas dañadas y de ruina inexistentes en el pack** | **Decidido**: `DAMAGED` por shader (`damage_overlay.gdshader`), no por mallas nuevas; si no convence en el checkpoint 3, la alternativa es autorar 4 mallas en Blender. Las `rubble_pile_*` son propias y dependen de WP-12 o de un horneado CSG: bloquean el acabado visual de `RUBBLE`, no su lógica |
| 5 | Composites de textura y sólo 2 piezas altas para 21 torres | Los composites se descartan si ningún material los referencia (si alguno los usa, +5 MB, muy por debajo de 90). La repetición de torres se mitiga con escala 0.85–1.35 y rotación de 90° |
| 6 | **SDFGI y geometría que cambia** (riesgo 9) | Mitigado: ruinas y escombros con `gi_mode = DISABLED`. La prueba A/B con `ReflectionProbe` locales es de WP-24 |
| 7 | `DebrisChunk` grandes y tunneling contra Jolt (riesgo 6) | Mitigado con `continuous_cd` sobre 800 kg; si aparecen trozos que atraviesan el suelo, se sube el umbral o se baja `debris_mass` |
| 8 | 341 HP/s para que la ciudad caiga en 5 min | Abierto; lo verifica `docs/07` y lo ajusta WP-23. Palancas: `siege_beam`, cooldowns, o bajar el HP total |
| 9 | El jugador puede perder por su propio fuego amigo | **Aceptado como diseño**: 170 impactos por bloque bajo lo hacen improbable por accidente y significativo si se abusa |
| 10 | `district_a` comiteada como escena concreta | **Decidido**: `CityGrid` genera una vez con `seed = 0` y se guarda. Permite hornear oclusores y hace reproducible el check |
| 11 | 24 escombros rígidos + el jefe en el mismo tick | Presupuesto de física < 2 ms/tick (`docs/15`). Si se supera, la palanca es bajar `MAX_LIVE` a 16 antes que tocar el jefe |

---

## 13. Referencias cruzadas

- `docs/02-configuracion-del-proyecto.md` — capas y máscaras, ajustes de render (occlusion culling, LOD), señales de `Events`. · `docs/05-pipeline-voxel.md` — mallas propias de ruina y rocas.
- `docs/06-framework-de-enemigos.md` — `DebrisPool.adopt()` y `RubbleField.register_mesh()`/`bake()` compartidos, `EnemyPart.detach()`, raycast de pie con máscara `1|8`, `Building.take_damage(crush_damage, ...)` al trepar. · `docs/07-arachnodroid.md` — `siege_beam`, `stomp`, `walk` y `climb`: el ritmo real de destrucción.
- `docs/08-combate-y-armas.md` — fuego amigo, `city_friendly_fire_scale`, `friendly_fire_damage`, impactos y decals. · `docs/09-energia-y-danio.md` — daño de los escombros al dron, espacio libre de las pilas en capas 8 y 9.
- `docs/11-rondas-y-objetivos.md` — derrota por `city_integrity_changed < 0.35`, puntaje `1000 · integridad`, grupo `buildings`, `rebuild()`. · `docs/12-interfaz-y-hud.md` — `CityBar`, grupo `buildings_under_siege`, `OffscreenMarkers`.
- `docs/13-identidad-visual-y-audio.md` — `environment_battle.tres`, `FogVolume`, humo, bus `City`, atenuación del trauma. · `docs/15-verificacion-y-ci.md` — checks y draw calls. · `docs/16-licencias-y-atribucion.md` — licencia del pack.
