# 05 — Pipeline voxel

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-12 · Depende de: `docs/02-configuracion-del-proyecto.md`, `docs/00-plan-maestro.md`

## 1. Objetivo y alcance

> **Nota de WP-25 (2026-09-20)**: el dron pasa a paleta de «pieza suelta» en `tools/voxsplit/models/drone_quad.py` (chasis gris de tres tonos con rayones, brazo rojo y brazo negro en diagonal, cinta en el motor 2, batería con parche verde, LED ámbar, hélices de dos tonos, 11 vóxeles de detalle); mismas 16 partes, ids, pivotes, `collision`, bbox y masa; build reproducible byte a byte; `enemy_import_check` en verde.

> **Nota de WP-12a/12b (2026-09-19)**: el sidecar ES el mismo `<enemy>.parts.json` (superconjunto idempotente con `metadata`); `source` admite `archivo.zip!miembro`; los criterios numéricos del jefe viven en el bloque `expect` del JSON, no en la herramienta. El Arachnodroid tiene 4 274 triángulos (no 4 282) y los 3 voxels cian que §2.3 atribuye a `neck` pertenecen a `carapace`. Import: preset con `meshes/ensure_tangents=false` (modelo sin normal maps), `nodes/root_type=Node3D` y `nodes/root_name` (`ArachnodroidRoot`/`DroneQuad`; Godot añade una raíz propia y el script funde la interior); `flags` se escribe como `PackedStringArray`; los scripts de import no declaran `class_name`; los metadatos van en la malla **y** en el `AnimatableBody3D`; en la pose de reposo las rodillas quedan a 8,625 m y los pies a 3,75 m (el 11,0/3,0 de §14.2 es la pose de marcha, WP-17) y el check compara contra `pivot_world` del sidecar; `get_lod_count()` no existe: se usa `RenderingServer.mesh_get_surface()["lods"]`. El dron tiene 16 partes (`led` incluido) y raíz `DroneQuad`.


Especifica la herramienta **`voxsplit`** (Python 3.12, `godot/tools/voxsplit/`) que convierte un modelo `.vox` de MagicaVoxel en un **GLB jerárquico con una parte por nodo**, y el script de importación de Godot que lo convierte en una escena con colisionadores, capas y metadatos. Define también el **dron voxel original** del jugador, generado con el mismo pipeline.

**Incluye**: lectura del `.vox`, sistema de coordenadas, esquema de `parts.json`, segmentación, meshing greedy, escritura de GLB, CLI, `EditorScenePostImport`, escala, el modelo del dron y el fallback en Blender.

**NO incluye**: el comportamiento de las partes en juego (HP, desprendimiento, puntos débiles: `docs/06-framework-de-enemigos.md`), la ficha del Arachnodroid (`docs/07-arachnodroid.md`), ni la ciudad (`docs/10-ciudad-destructible.md`).

Todas las cifras de este documento se verificaron contra el archivo real `Arachnoid.vox` (versión 150, 40×40×40, 4 007 voxels).

**Restricciones**: solo biblioteca estándar de Python 3.12 más **Pillow** (para PNG de paleta y previsualizaciones). `numpy` queda prohibido como dependencia obligatoria; si se usa, debe ser detectado con `try: import numpy` y tener camino alternativo en stdlib. Los archivos de `assets/_raw/` **no se extraen dentro del repositorio**.

---

## 2. Formato `.vox` de MagicaVoxel (versión 150)

### 2.1 Cabecera y chunks

| Offset | Bytes | Contenido |
|---|---|---|
| 0 | 4 | Magic `VOX ` (con espacio final) |
| 4 | 4 | Versión, entero little-endian. El archivo del Arachnodroid es **150** |
| 8 | 12 | Cabecera del chunk `MAIN` |
| **20** | — | **Primer chunk hijo de `MAIN`** |

Cabecera de chunk: `id` (4 bytes ASCII), `contentBytes` (int32 LE), `childrenBytes` (int32 LE). `MAIN` tiene `contentBytes = 0`, por lo que su primer hijo empieza en el offset 20.

Trampa clásica: al recorrer los hijos de `MAIN` hay que **entrar** en la región de hijos (avanzar `12 + contentBytes`), no saltarla. Para cualquier otro chunk se avanza `12 + contentBytes + childrenBytes`.

### 2.2 Chunks que `voxreader` debe entender

| Chunk | Contenido | Notas |
|---|---|---|
| `SIZE` | `x`, `y`, `z` (int32) | Dimensiones del modelo. Arachnodroid: 40, 40, 40 |
| `XYZI` | `n` (int32), luego `n` tuplas `(x, y, z, i)` de 1 byte | `i` es el índice de paleta **1-based**. Arachnodroid: `n = 4007` |
| `RGBA` | 256 entradas de 4 bytes | **El color del índice `i` está en `RGBA[i - 1]`** |
| `MATL` | `id` (int32) + diccionario | `id` es el índice de paleta. Ver 2.3 |
| `nTRN` / `nGRP` / `nSHP` | Grafo de escena | Ver 2.4 |
| `LAYR` | Capas del editor | Se ignoran |
| `PACK` | Número de modelos (formato antiguo) | Se ignora si hay grafo |

Diccionario VOX (`DICT`): `int32 numPairs`, y por cada par dos cadenas `int32 len + bytes UTF-8`.

### 2.3 `MATL` y emisivos

En el archivo real, los materiales emisivos tienen esta forma exacta (material 8, el cian de rodillas y visor):

```
{'_type': '_emit', '_weight': '0.65', '_rough': '0.1', '_spec': '0.5', '_spec_p': '0.5',
 '_ior': '0.3', '_att': '0', '_g0': '-0.5', '_g1': '0.8', '_gw': '0.7', '_flux': '1', '_ldr': '0'}
```

Reglas de lectura:

- Un índice de paleta es **emisivo** si su `MATL` tiene `_type == "_emit"`.
- `_emit` es el **valor de `_type`**, no un campo de intensidad. La **fuerza** de emisión es `_weight` (0–1) y el multiplicador de potencia es `_flux`: son las dos claves canónicas, verificadas en el archivo real. Si una versión antigua de MagicaVoxel trajera `_emit` como número suelto, el lector lo acepta como sinónimo de `_weight`, pero **`_weight` tiene prioridad**.
- `_flux` (entero, 1–5) es un multiplicador de potencia. Se traduce a energía con `energy = float(_weight) * (2 ** (int(_flux) - 1))`.
- Los materiales `MATL` existen para índices **no usados por ningún voxel** (en el Arachnodroid, los índices 1 y 2). Se ignoran.
- `emissive_palette_indices` de `parts.json` es la **lista autoritativa**; los `MATL` sirven para derivarla y para que `inspect` la sugiera, pero el artista puede recortarla o ampliarla a mano.

Índices emisivos reales del Arachnodroid, verificados:

| Índice | Color RGB | Voxels | Ubicación |
|---|---|---|---|
| 6 | 254, 120, 231 (magenta) | 2 | Respiradero superior |
| 7 | 249, 140, 90 (naranja) | 13 | Respiraderos laterales y frontales |
| 8 | 55, 170, 248 (cian) | 11 | **4 anillos de rodilla** (1 cada una) + **visor** (4) + cuello (3) |
| 14 | 254, 120, 231 (magenta) | 2 | **Luz del núcleo ventral** |

### 2.4 Multi-modelo y grafo

Si existen `nTRN` / `nGRP` / `nSHP`, se recorre el grafo desde el nodo raíz (`nTRN` con id 0) hasta el primer `nSHP` y se toma el **primer `modelId`** que declare. Si **no** hay grafo, se toma el primer par `SIZE` + `XYZI` del archivo.

La traslación `_t` de los `nTRN` se **ignora deliberadamente**: el origen del modelo lo define `origin_voxel` en `parts.json`, que es explícito y verificable. Aplicar además `_t` duplicaría el desplazamiento.

### 2.5 Paleta por defecto

Si falta el chunk `RGBA`, se usa la paleta por defecto de MagicaVoxel (256 colores) embebida como constante en `voxreader.py`. El Arachnodroid **sí** trae `RGBA`, pero otros packs del catálogo pueden no traerlo.

---

## 3. Sistema de coordenadas y escala

### 3.1 Dos espacios, una fórmula

MagicaVoxel es **Z-up** con Y como profundidad. Godot es **Y-up**. La conversión se declara en `axis_map`.

- **Espacio de índice**: el voxel de índice `i` tiene su **centro** en `i` y ocupa `[i − 0.5, i + 0.5]`. Los campos `boxes` y `pivot` de `parts.json` están en este espacio (por eso los pivotes usan medios voxels).
- **`origin_voxel`** nombra en cambio una **esquina de la retícula**, no un centro. Eso permite escribir `[20, 20, 0]` y obtener exactamente el centro de la huella al ras del suelo.

Fórmula única, para pivotes y para vértices:

```
p_vox   = (p_index - origin_voxel + 0.5) * voxel_size      # metros, ejes de MagicaVoxel
p_godot = axis_map(p_vox)                                   # por defecto (x, z, -y)
```

Los vértices se generan a partir de las **esquinas** de los voxels, que en espacio de índice caen en `i ± 0.5`.

### 3.2 Verificación con el Arachnodroid

`voxel_size = 0.75`, `origin_voxel = [20, 20, 0]`, bbox ocupado `x[6,33] y[2,37] z[0,38]`.

| Magnitud | Cálculo | Resultado | Ficha (Anexo A) |
|---|---|---|---|
| Altura total | `(38.5 + 0.5) × 0.75` | **29.25 m** | 29.25 m |
| Ancho (X) | `(33.5 − 5.5) × 0.75` | **21.0 m** | 21 m |
| Profundidad (Y) | `(37.5 − 1.5) × 0.75` | **27.0 m** | 27 m |
| Base del casco | voxel z=29, cara inferior | **21.75 m** | «22–29 m» |
| Pivote del casco | `(29 + 0.5) × 0.75` | **22.125 m** | — |
| Suelo | voxel z=0, cara inferior | **0.00 m** | a ras |

Que las cuatro cifras coincidan con la ficha confirma que la interpretación de `origin_voxel` como esquina de retícula es la correcta. Cualquier otra desplaza el modelo 0.375 m.

### 3.3 `axis_map`

Se declara como diccionario de ejes con signo: `{"x": "+x", "y": "+z", "z": "-y"}` significa *godot.x = vox.x, godot.y = vox.z, godot.z = −vox.y*. El lector valida que sea una permutación con signo (determinante ±1) y **rechaza** mapeos que inviertan la orientación sin corregir el bobinado de los triángulos.

### 3.4 Guía de escala por enemigo

Altura objetivo del catálogo: **20–45 m**. `voxel_size = altura_objetivo / altura_en_voxels`.

| Enemigo | Voxels de alto | `voxel_size` | Altura |
|---|---|---|---|
| Arachnodroid | 39 | **0.75** | 29.25 m |
| QuadrupedTank / MechaTrooper / MobileStorageBot | 56 / 60 / 46 | 0.55 *(propuesta)* | 30.8 / 33.0 / 25.3 m |
| MechGolem / Companion-bot | 54 / 57 | 0.70 *(propuesta)* | 37.8 / 39.9 m |
| FieldFighter / Mecha01 | 59 / 44 | 0.60 / 0.65 *(propuesta)* | 35.4 / 28.6 m |
| ReconBot | 59 | 0.38 *(propuesta)* | 22.4 m |

Solo el 0.75 del Arachnodroid está fijado por el plan; el resto son propuestas que cada WP de P3 confirma.

---

## 4. Esquema de `parts.json`

### 4.1 Cabecera

| Campo | Tipo | Descripción |
|---|---|---|
| `source` | string | Ruta al `.vox`, relativa al `parts.json` |
| `voxel_size` | float | Metros por voxel |
| `origin_voxel` | `[x, y, z]` float | Esquina de retícula que va al origen del modelo (§3.1) |
| `axis_map` | objeto | `{"x": "+x", "y": "+z", "z": "-y"}` |
| `palette_texture` | string | Nombre del PNG 256×1 a generar |
| `emissive_palette_indices` | `[int]` | Índices 1-based emisivos |
| `collision_default` | string | `"box"` \| `"convex"` \| `"none"` |
| `parts` | `[objeto]` | Ver 4.2. El **orden importa** (§5.1) |

### 4.2 Entrada de `parts[]`

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `id` | string | sí | Nombre del nodo en el GLB. Estable, en inglés, `snake_case` |
| `parent` | string \| null | sí | `id` del padre; `null` solo para la raíz |
| `boxes` | `[[x0,y0,z0,x1,y1,z1]]` | sí | Cajas **inclusivas** en índices de voxel |
| `exclude` | `[[…]]` | no | Cajas que se restan de `boxes` |
| `pivot` | `[x, y, z]` float | sí | Origen del nodo, en índices de voxel, con medios voxels |
| `flags` | `[string]` | no | `root`, `weak_point`, `detachable`, `cosmetic`, `leg_root`, `leg_segment`, `foot`, `staged` |
| `collision` | string | no | `box` \| `convex` \| `none`; por defecto `collision_default` |
| `hp` | int | no | Puntos de vida; lo consume `EnemyPart` |
| `armor` | float | no | 0–1; por defecto 0.90 |
| `debris_mass` | float | no | kg del `DebrisChunk` al desprenderse; si falta se estima (§7.2) |
| `function` | string | no | Etiqueta funcional (`vision`, `laser`, `locomotion`, `core`) para deshabilitar capacidades |
| `weak_point_id` | string | no | Id del punto débil asociado |

### 4.3 Ejemplo mínimo

```json
{
  "source": "Arachnoid.vox",
  "voxel_size": 0.75,
  "origin_voxel": [20, 20, 0],
  "axis_map": {"x": "+x", "y": "+z", "z": "-y"},
  "palette_texture": "arachnodroid_palette.png",
  "emissive_palette_indices": [6, 7, 8, 14],
  "collision_default": "box",
  "parts": [
    {"id": "wp_head_visor", "parent": "hull", "boxes": [[17,33,32,22,35,34]],
     "pivot": [19.5, 34, 33], "flags": ["weak_point"], "hp": 1500, "function": "vision"},
    {"id": "hull", "parent": null, "boxes": [[15,13,29,24,35,38]],
     "pivot": [19.5, 19.5, 29], "flags": ["root"]}
  ]
}
```

### 4.4 Tabla canónica del Arachnodroid

**31 partes**, 0 voxels sin asignar, verificado contra el `.vox`. Las patas derechas y traseras se derivan por espejo: **`x' = 39 − x`, `y' = 39 − y`** (regla `n − 1 − c` con `n = 40`), aplicada tanto a `boxes` como a `pivot`.

| id | parent | boxes (fl) | pivot (fl) | vox | tris | flags |
|---|---|---|---|---|---|---|
| `hull` | — | `[15,13,29, 24,35,38]` | `[19.5,19.5,29]` | 1615 | 412 | `root` |
| `wp_head_visor` | `hull` | `[17,33,32, 22,35,34]` | `[19.5,34,33]` | 44 | 72 | `weak_point` |
| `antenna_l` | `hull` | `[15,20,38, 24,22,38]` | `[19.5,21,38]` | 10 | 12 | `detachable`, `cosmetic` |
| `antenna_r` | `hull` | `[15,29,38, 24,31,38]` | `[19.5,30,38]` | 10 | 12 | `detachable`, `cosmetic` |
| `neck` | `hull` | `[16,15,25, 23,`**`24`**`,28]` | `[19.5,19.5,28]` | 188 | 220 | — |
| `shoulder_ring` | `hull` | `[12,12,25, 27,27,27]` | `[19.5,19.5,26]` | 156 | 404 | — |
| `carapace` | `shoulder_ring` | `[6,2,23, 33,37,24]` | `[19.5,19.5,23.5]` | 456 | 556 | — |
| `underbelly` | `carapace` | `[7,12,13, 32,27,22]` | `[19.5,19.5,22.5]` | 844 | 1130 | — |
| `wp_core_a` | `underbelly` | `[18,17,19, 21,18,22]` | `[19.5,17.5,20.5]` | 12 | 22 | `weak_point`, `staged` |
| `wp_core_b` | `underbelly` | `[18,19,19, 21,20,22]` | `[19.5,19.5,20.5]` | 16 | 30 | `weak_point`, `staged` |
| `wp_core_c` | `underbelly` | `[18,21,19, 21,21,22]` | `[19.5,21,20.5]` | 8 | 20 | `weak_point`, `staged` |
| `leg_fl_coxa` | `shoulder_ring` | `[6,28,23, 16,37,24]` | `[13,28,23.5]` | 29 | 60 | `leg_root` |
| `leg_fl_femur` | `leg_fl_coxa` | `[9,31,13, 13,37,22]` | `[11,33.5,22.5]` | 58 | 88 | `detachable`, `leg_segment` |
| `leg_fl_tibia` | `leg_fl_femur` | `[10,33,5, 13,37,12]` | `[11.5,35,12.5]` | 30 | 46 | `leg_segment` |
| `wp_leg_fl_knee` | `leg_fl_tibia` | `[10,35,10, 13,37,12]` | `[11.5,36,11]` | 15 | 50 | `weak_point` |
| `leg_fl_foot` | `leg_fl_tibia` | `[10,33,0, 13,37,4]` | `[11.5,35,4.5]` | 30 | 104 | `leg_segment`, `foot` |

Las 15 filas restantes son `leg_fr_*` (espejo en X), `leg_bl_*` (espejo en Y) y `leg_br_*` (ambos). **Total: 4 007 voxels, 4 282 triángulos, 0 sin asignar.**

Dos correcciones respecto del Anexo B del plan, ambas necesarias y verificadas:

1. **`neck` llega a `y1 = 24`**, no a 23. Con `y1 = 23` quedan 2 voxels huérfanos en `(16..23, 24, 28)` y `--report` falla.
2. **`wp_core_a/b/c` se reparten la caja `[18,17,19, 21,21,22]` a lo largo de Y** (frente → fondo), no a lo largo de Z: así los tres segmentos quedan igualmente accesibles desde abajo, que es la dirección del cono de exposición de 70°.

Los pivotes de las articulaciones coinciden exactamente con las caras de contacto: el pivote de la tibia (`z = 12.5`) es la cara inferior del fémur (`z0 = 13` ⇒ cara en 12.5), y el del pie (`z = 4.5`) es la cara inferior de la tibia (`z0 = 5`). La cadena IK de `docs/06` depende de esa coincidencia.

---

## 5. Segmentación en partes

### 5.1 Asignación

Se recorre cada voxel ocupado y se le asigna la **primera** parte, en el orden de `parts[]`, cuya unión de `boxes` lo contenga y cuya unión de `exclude` no lo contenga. Consecuencia práctica: las partes pequeñas y específicas (puntos débiles, rodillas, antenas) van **primero** en el archivo, y los volúmenes grandes que las envuelven (`hull`, `carapace`, `underbelly`) van al final.

Los voxels que no caen en ninguna parte van a `_unassigned`.

### 5.2 `_unassigned` y `--report`

`_unassigned` se dibuja en **magenta puro (255, 0, 255)** en las previsualizaciones, y se lista en `report.txt` con su bbox y su conteo.

- `--report` **falla con código 1** si hay algún voxel sin asignar.
- `--allow-unassigned` degrada el fallo a advertencia y genera una parte `_unassigned` real en el GLB, útil para iterar cajas.

### 5.3 Ayuda para definir cajas

`voxsplit inspect` imprime, además del tamaño y el bbox, los **componentes conexos por color y por región** (conectividad de 6 vecinos, separada por índice de paleta). Sobre el Arachnodroid, esto aísla de inmediato las cuatro patas (133 voxels cada una, sin contar la coxa) y los cuatro anillos de rodilla, que son el punto de partida natural del `parts.json`.

---

## 6. Meshing greedy

### 6.1 Reglas

1. El meshing se hace **por parte** y **por material**. Cada parte produce una malla con hasta dos superficies: `opaque` y `emissive`, según el índice de paleta de cada voxel.
2. Una cara se genera si el vecino en esa dirección **no existe** o **pertenece a otra parte**. Las caras interiores entre partes distintas **sí se generan**: así el corte queda cerrado cuando la parte se desprende y no se ve el interior hueco.
3. Se recorren los 6 ejes. Por cada eje, cada rebanada y cada material, se construye una máscara 2D y se fusionan rectángulos maximales (greedy: crecer en U mientras el color coincida, luego en V mientras la fila entera coincida).
4. Solo se fusionan celdas del **mismo índice de paleta**, porque la UV depende del índice.
5. Normal = eje de la cara, con signo. Todas las normales son de eje; no hay suavizado.
6. Bobinado antihorario visto desde fuera, coherente con el `axis_map`.

### 6.2 UV y paleta

Cada vértice de una cara de índice `i` (1-based) recibe:

```
u = (i - 0.5) / 256
v = 0.5
```

Los cuatro vértices del rectángulo comparten la misma UV (color plano). La textura es un PNG de **256×1**: el píxel `i − 1` lleva `RGBA[i − 1]`. Debe importarse sin compresión, sin mipmaps y con filtro **nearest** (`docs/02` §7.3).

### 6.3 Vértices

En metros, **relativos al pivote de su propio nodo**:

```
v_local = axis_map((corner_index - origin_voxel + 0.5) * voxel_size) - pivot_world(part)
```

Sin índices compartidos entre superficies. Cada rectángulo aporta 4 vértices y 6 índices.

### 6.4 Resultado medido

| Métrica | Naive (1 quad por cara) | Greedy |
|---|---|---|
| Quads | 6 506 | 2 141 |
| Triángulos | 13 012 | **4 282** |

El presupuesto de 12 000 triángulos **solo se cumple con greedy**: sin fusión el modelo se pasa. La parte más pesada es `underbelly` (1 130 tris); las 4 patas completas suman 1 392.

---

## 7. Escritura de GLB y artefactos de salida

### 7.1 GLB

glTF 2.0 binario, escrito a mano por `glbwriter.py` (sin dependencias):

- **Un único buffer** (chunk `BIN`) con todos los vértices e índices, alineado a 4 bytes.
- Un `accessor` por atributo y por primitiva: `POSITION` (VEC3 float), `NORMAL` (VEC3 float), `TEXCOORD_0` (VEC2 float), índices (`UNSIGNED_INT`). `min`/`max` obligatorios en `POSITION`.
- Un `mesh` por parte, con una `primitive` por material presente (1 o 2).
- Un `node` por parte, con `name = id` de la parte y `translation` = `pivot_world(part) − pivot_world(parent)`. Sin `rotation` ni `scale`.
- Jerarquía padre-hijo según `parent`. Un nodo raíz extra llamado `<Enemy>Root` cuelga de la escena y tiene como hijo la parte `root`.
- **Materiales**: `voxel_opaque` (`baseColorTexture` = paleta, `metallicFactor` 0.0, `roughnessFactor` 0.85) y `voxel_emissive` (lo mismo más `emissiveTexture` = paleta, `emissiveFactor` `[1,1,1]` y la extensión `KHR_materials_emissive_strength` con `emissiveStrength` = energía derivada del `MATL` según §2.3).
- La textura de paleta se referencia **por URI externa** (`arachnodroid_palette.png` junto al GLB), no embebida, para que Godot la importe con su propio preset.

### 7.2 Sidecar y demás salidas

Por cada modelo se emiten, en `--out <dir>`:

| Archivo | Contenido |
|---|---|
| `<enemy>.glb` | La malla jerárquica |
| `<enemy>.parts.json` | **Sidecar**: copia literal del `parts.json` de entrada más un bloque `metadata` calculado |
| `<enemy>_palette.png` | 256×1 RGBA |
| `preview_front.png`, `preview_side.png`, `preview_top.png` | Solo con `--preview` |
| `report.txt` | Solo con `--report` |

Bloque `metadata` del sidecar, por parte: `aabb_min` / `aabb_max` (metros, locales al pivote), `center_of_mass` (metros, local), `voxel_count`, `estimated_mass` (kg). Y a nivel de modelo: `part_count`, `voxel_count`, `triangle_count`, `total_height`, `unassigned_count`, `generated_at`, `voxsplit_version`.

Masa estimada: `estimated_mass = voxel_count × voxel_size³ × density`, con `density = 220 kg/m³` *(propuesta)*. Para el Arachnodroid eso da ≈ 372 t frente a las 900 t nominales de la ficha; `debris_mass` explícito en `parts.json` tiene prioridad y es el camino recomendado para las partes que se desprenden.

### 7.3 Previsualizaciones

`preview.py` dibuja con Pillow tres proyecciones ortográficas (frontal, lateral, superior) del volumen segmentado, **coloreando cada parte con un color determinista** derivado de un hash de su `id`, y `_unassigned` en magenta puro. Una leyenda lateral lista `id`, color y número de voxels. Es la herramienta de trabajo para ajustar cajas.

---

## 8. CLI

```
python -m voxsplit build <parts.json> --out <dir> [--preview] [--report] [--allow-unassigned]
python -m voxsplit inspect <file.vox>
python -m voxsplit preview <parts.json> [--out <dir>]
```

| Subcomando | Salida | Código de salida |
|---|---|---|
| `build` | GLB + sidecar + paleta (+ previews, + report) | 0 si todo bien; 1 si hay `_unassigned` y no se pasó `--allow-unassigned`; 2 si el `parts.json` es inválido |
| `inspect` | Tamaño, número de voxels, bbox ocupado, histograma de índices, índices emisivos según `MATL`, componentes conexos por color y región | 0 / 2 |
| `preview` | Las 3 vistas ortográficas | 0 / 1 / 2 |

Módulos del paquete `godot/tools/voxsplit/`:

| Archivo | Responsabilidad |
|---|---|
| `voxreader.py` | Parseo de `.vox`: chunks, `SIZE`, `XYZI`, `RGBA`, `MATL`, grafo, paleta por defecto |
| `parts.py` | Carga y validación de `parts.json`, espejo, asignación de voxels a partes, `_unassigned` |
| `mesher.py` | Meshing greedy por parte y material, UV de paleta, normales |
| `glbwriter.py` | Serialización glTF 2.0 binaria, jerarquía, materiales |
| `preview.py` | Vistas ortográficas con Pillow, leyenda, magenta para `_unassigned` |
| `__main__.py` | CLI, `report.txt`, códigos de salida |
| `models/drone_quad.py` | Definición procedural del dron del jugador (§10) |

---

## 9. Import en Godot

### 9.1 `asset_import/import_voxel_enemy.gd`

```gdscript
@tool
class_name ImportVoxelEnemy extends EditorScenePostImport

func _post_import(scene: Node) -> Object
```

Pasos, por cada `MeshInstance3D` del árbol cuyo `name` coincida con un `id` del sidecar (el sidecar se localiza sustituyendo la extensión del `source_file` por `.parts.json`):

1. Crear un hijo `AnimatableBody3D` llamado `<id>_body`, con **`sync_to_physics = false`** (el movedor cinemático propio de `EnemyBase` gobierna las transformadas; `sync_to_physics` introduciría un tick de retardo y peleas con Jolt).
2. Añadirle un `CollisionShape3D`:
   - `collision == "box"` → `BoxShape3D` con `size = mesh.get_aabb().size` y el `CollisionShape3D` desplazado a `mesh.get_aabb().get_center()`.
   - `collision == "convex"` → `mesh.create_convex_shape(true, true)` (limpio y simplificado).
   - `collision == "none"` → no se crea cuerpo.
3. `collision_layer`: **capa 3** (`enemy_body`, valor 4) o **capa 4** (`enemy_weak`, valor 8) si la parte tiene el flag `weak_point`.
4. `collision_mask`: 387 para la capa 3, 3 para la capa 4 (`docs/02` §3.1).
5. Metadatos con `set_meta` **en el `MeshInstance3D`**: `part_id`, `hp`, `armor`, `detachable`, `debris_mass`, `weak_point_id`, `function`, `flags`, y además `has_emissive_surface` (bool, ver 9.2).
6. `gi_mode = GeometryInstance3D.GI_MODE_DISABLED` y `cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON` en cada `MeshInstance3D`.
7. **No se añade ningún script a ningún nodo.** `EnemyBase` construye el grafo de `EnemyPart` y `WeakPoint` en runtime leyendo los metadatos.
8. Si el sidecar no existe o le falta una parte presente en la escena, `push_error` con el `id` faltante y se devuelve la escena sin tocar esa rama: el fallo debe ser ruidoso, no silencioso.

### 9.2 Emisivos que faltan

Dato verificado: de los tres segmentos del núcleo ventral, **solo `wp_core_b` contiene voxels emisivos** en el `.vox` original. Por eso el importador escribe `has_emissive_surface`; `WeakPoint` (`docs/06`) enciende y apaga el punto débil con la energía de emisión de la superficie emisiva cuando existe, y con un `material_override` propio cuando no.

### 9.3 Preset del GLB

El definido en `docs/02` §7.1: `generate_lods = false`, `create_shadow_meshes = true`, `animation/import = false`, `root_scale = 1.0`, `import_script/path` apuntando a este script.

**Sin LOD**, por tres razones: (a) las partes se desprenden y se reparentan bajo un `DebrisChunk`, y un LOD generado rompe la correspondencia malla↔colisionador; (b) el modelo completo son 4 282 triángulos, menos que un solo edificio de la ciudad; (c) el jefe está casi siempre cerca de la cámara, así que el LOD nunca se activaría.

---

## 10. El dron voxel original

Modelo propio, generado por el mismo pipeline, en `tools/voxsplit/models/drone_quad.py`. **No** se importa de ningún pack.

- Escala: **1 voxel = 1 cm** (`voxel_size = 0.01`). Retícula 30×30×10. `origin_voxel = [15, 15, 5]` (centro geométrico, que es también el centro de masa nominal).
- Diagonal motor a motor: centros de motor en los índices `(6,6)`, `(23,6)`, `(6,23)`, `(23,23)` ⇒ `17 × √2 = 24.0 voxels` ≈ **24 cm**.

| Parte | parent | Forma | Pivote | Flags |
|---|---|---|---|---|
| `frame` | — | Placa central `[11,11,4, 18,18,5]` + 4 brazos en X | `[15,15,4.5]` | `root` |
| `motor_1` | `frame` | Cilindro aproximado 4×4×3 en `(23,6)` | `[23,6,6]` | — |
| `motor_2` | `frame` | Ídem en `(23,23)` | `[23,23,6]` | — |
| `motor_3` | `frame` | Ídem en `(6,6)` | `[6,6,6]` | — |
| `motor_4` | `frame` | Ídem en `(6,23)` | `[6,23,6]` | — |
| `prop_N` | `motor_N` | Pala de 2 voxels de ancho, largo 12, 1 de alto | Eje del motor, `z = 7` | — |
| `prop_disk_N` | `motor_N` | **Disco** voxelizado r = 6, 1 voxel de alto | Eje del motor, `z = 7` | `cosmetic` |
| `camera` | `frame` | `[13,19,5, 16,21,8]`, inclinada hacia adelante | `[14.5,20,6]` | — |
| `battery` | `frame` | `[12,12,2, 17,18,3]` | `[14.5,15,2.5]` | — |

**15 partes.** Numeración de motores en orden Betaflight X: 1 = trasero-derecho, 2 = delantero-derecho, 3 = trasero-izquierdo, 4 = delantero-izquierdo. `docs/03` depende de ese orden para el mezclador; cambiarlo invierte el control.

Cada `motor_N` lleva metadatos `motor_index` (1–4) y `spin` (+1 / −1, alternando en diagonal). Los `prop_disk_N` existen para el **efecto de desenfoque en rotación**: `DroneRig` hace visible `prop_N` por debajo de un umbral de RPM y `prop_disk_N` por encima, con un material semitransparente.

Salida: `assets/drone/drone_quad.glb` + `drone_quad.parts.json` + `drone_quad_palette.png`. Lo importa `asset_import/import_drone.gd`, que **no** añade colisionadores por parte (el dron es un único `RigidBody3D` con una forma de colisión convexa hecha a mano); solo fija `gi_mode` y los metadatos de motor.

El módulo expone:

```python
def build() -> dict:
    """Devuelve {'size': (30, 30, 10), 'voxels': {(x, y, z): palette_index},
                 'parts': [...], 'palette': [(r, g, b, a), ...]}"""
```

Permite tanto cajas como voxels generados (los discos de hélice, que no son cajas). `__main__.py` acepta `build models.drone_quad` además de una ruta a `parts.json`.

---

## 11. Fallback: Blender headless

Solo si `mesher.py` o `glbwriter.py` fallan sobre algún modelo del catálogo. Script `tools/voxsplit/fallback_blender.py`, ejecutado con **Blender 4.5**:

```
blender --background --python tools/voxsplit/fallback_blender.py -- <parts.json> --out <dir>
```

Debe consumir **el mismo `parts.json`**, producir **la misma jerarquía de nodos con los mismos nombres y pivotes**, y exportar con `bpy.ops.export_scene.gltf(export_format='GLB', export_yup=True, export_apply=True)`. `enemy_import_check` no distingue qué camino generó el GLB: sus criterios son idénticos.

El fallback es explícitamente **plan B**. Blender no es dependencia de CI ni del flujo normal.

---

## 12. Interfaz pública

| Elemento | Firma / definición |
|---|---|
| `voxreader.read(path: str) -> VoxModel` | `VoxModel`: `size`, `voxels: dict[(int,int,int), int]`, `palette: list[tuple]`, `materials: dict[int, dict]` |
| `parts.load(path: str) -> PartsSpec` | Valida el esquema de §4; lanza `PartsError` con línea y campo |
| `parts.assign(model, spec) -> dict[str, set]` | Devuelve `{part_id: {voxel}}`, con la clave `"_unassigned"` |
| `mesher.build_part(voxels, spec, part) -> PartMesh` | `PartMesh`: `surfaces: dict[str, Surface]`, `aabb`, `triangle_count` |
| `glbwriter.write(path, meshes, spec) -> None` | Escribe el GLB |
| `preview.render(model, assignment, spec, out_dir) -> None` | Tres PNG y la leyenda |
| `ImportVoxelEnemy._post_import(scene: Node) -> Object` | `EditorScenePostImport` (§9.1) |
| `models.drone_quad.build() -> dict` | §10 |

Metadatos garantizados en cada `MeshInstance3D` importado: `part_id: String`, `hp: int`, `armor: float`, `detachable: bool`, `debris_mass: float`, `weak_point_id: String`, `function: String`, `flags: Array[String]`, `has_emissive_surface: bool`.

---

## 13. Parámetros y valores iniciales

| Parámetro | Valor | Origen |
|---|---|---|
| Versión de `.vox`, offset del primer hijo | 150, **20** | Verificados en el archivo real |
| Paleta | 256 colores, índice 1-based; textura 256×1 lossless, sin mipmaps, nearest | Formato + `docs/02` §7.3 |
| Arachnodroid: `voxel_size`, `origin_voxel`, `axis_map` | 0.75 m · `[20,20,0]` · `(x, z, −y)` | Plan |
| Arachnodroid: partes / voxels / triángulos / altura | **31** (23 estructurales + 8 puntos débiles) · 4 007 · **4 282** · 29.25 m | §4.4, medido — cerrado en D-1 |
| `emissive_palette_indices` | `[6, 7, 8, 14]` | Verificado con `MATL` |
| Presupuesto de triángulos | < 12 000 | Plan |
| `armor` por defecto | 0.90 | Plan §4.6 |
| Densidad para masa estimada | 220 kg/m³ | **Propuesta** |
| `energy` emisiva | `_weight × 2^(_flux − 1)` | **Propuesta** |
| Dron: `voxel_size` / diagonal / partes | 0.01 m · 24.0 cm · **15** | Plan + **propuesta** |
| Python | 3.12, stdlib + Pillow, sin `numpy` obligatorio | Plan |

---

## 14. Criterios de aceptación y checks

### 14.1 Check del pipeline (Python)

```
python -m voxsplit build enemies/arachnodroid/arachnodroid.parts.json ^
  --out enemies/arachnodroid --preview --report
```

Falla (código ≠ 0) si:

| # | Criterio |
|---|---|
| 1 | Hay **más de 0 voxels** en `_unassigned` |
| 2 | `part_count != 31` |
| 3 | `triangle_count >= 12000` |
| 4 | La altura total del GLB difiere de 29.25 m en más de 0.01 m |
| 5 | Algún `parent` referencia un `id` inexistente, o hay ciclo, o hay más de una parte con `root` |
| 6 | Algún `id` está repetido |

`report.txt` incluye siempre la tabla de §4.4 recalculada (parte, voxels, triángulos, bbox, emisivo sí/no) para que la regresión sea visible en el diff.

### 14.2 `tools/enemy_import_check.tscn`

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/enemy_import_check.tscn
```

Carga `res://enemies/arachnodroid/arachnodroid.glb` como `PackedScene`, la instancia y verifica:

| # | Criterio | Tolerancia |
|---|---|---|
| 1 | Hay exactamente **31** `MeshInstance3D` con metadato `part_id` | exacto |
| 2 | La jerarquía padre-hijo coincide con la tabla de §4.4 para las 31 partes | exacto |
| 3 | Cada pivote (posición global del nodo) está a menos de **0.05 m** del valor declarado, convertido con la fórmula de §3.1 | 0.05 m |
| 4 | Toda parte sin `weak_point` tiene `collision_layer == 4`; toda parte con `weak_point`, `collision_layer == 8` | exacto |
| 5 | `collision_mask` es 387 (capa 3) o 3 (capa 4) | exacto |
| 6 | Los 9 metadatos de §12 existen en las 31 partes | exacto |
| 7 | Altura total del `AABB` combinado = **29.25 m** | ± 0.1 m |
| 8 | Ningún `Mesh` tiene LOD (`mesh.get_surface_count()` estable y `ArrayMesh.get_lod_count()` inexistente o 0) | exacto |
| 9 | Los 5 `weak_point` con emisivo (`wp_head_visor`, 4 rodillas) tienen `has_emissive_surface == true` | exacto |
| 10 | Cada `AnimatableBody3D` tiene `sync_to_physics == false` | exacto |
| 11 | Los 4 pivotes de rodilla y los 4 pies coinciden con `pivot_world` del sidecar en la **pose de reposo** del GLB: rodillas a **8.625 ± 0.1 m** y pies a **3.75 ± 0.1 m** (medido en WP-12; el 11.0/3.0 de la ficha original nunca fue una pose real: la cadena fémur+tibia+pie del modelo mide 13.6 m, y la pose de marcha realizable de WP-17 dejaba las rodillas a **7.9 m** con el origen del cuerpo a −3.25 m cuando los pies tocan el suelo; ver `06`/`07`). **Actualización de WP-24d (2026-09-20)**: la pose de marcha realizable pasó a dejar las rodillas a **9,4 m** (huella lateral de 22 m), no 7,9; el criterio de reposo no cambia. | 0.1 m |

Imprime `CHECK enemy_import_check: OK` o `FAIL (n fallos)` y sale con 0 o 1. No escribe en `user://`.

---

## 15. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| **D-1** | **Número de partes: 31 frente a las «24» del borrador del plan** | **Cerrado (2026-09-19): son 31 nodos de malla = 23 estructurales + 8 puntos débiles.** Es la cifra verificada contra el `.vox` y la que hace falta para que las patas tengan IK de 3 segmentos y los núcleos sean escalonados. **Los checks leen `metadata.part_count` del sidecar**, nunca una constante, así que el número vive en un solo sitio. La variante reducida a 24 (fusionar las 4 `leg_XX_coxa` dentro de `shoulder_ring` y convertir `wp_core_a/b/c` en colisionadores de `underbelly`) queda descartada |
| D-2 | Solo `wp_core_b` tiene voxels emisivos | Resuelto con `has_emissive_surface` y `material_override` (§9.2), pero conviene que el artista pinte 2 voxels magenta más en los segmentos `a` y `c` del `.vox` |
| D-3 | Cajas espejadas no explicitadas en el Anexo B | Resueltas con la regla `x' = 39 − x`, `y' = 39 − y`, **verificada**: cobertura total y 133 voxels por pata sin coxa, la cifra exacta que da el plan |
| D-4 | Densidad de 220 kg/m³ y fórmula de emisión | **Propuesta** sin fuente; se ajustan en WP-16 y WP-24 |
| D-5 | `voxel_size` de los otros 8 enemigos | **Propuesta**; cada WP de P3 lo confirma contra la altura objetivo de 20–45 m |
| D-6 | Licencia de los packs `.vox` | **Abierto**; `docs/16` lleva el checklist. El pipeline no redistribuye los `.vox`, solo GLB derivados, lo que **no** resuelve el problema por sí solo |
| D-7 | Partes del dron y geometría exacta | **Propuesta** completa (§10); la silueta final la valida el usuario en el checkpoint 2 |
| D-8 | `numpy` opcional | El mesher greedy tarda menos de 2 s en stdlib puro sobre 4 007 voxels; con el QuadrupedTank (28 400 voxels) habrá que medir antes de decidir |
| D-9 | Chunks `nTRN` con traslación no nula | Se ignoran por diseño (§2.4). Si algún pack del catálogo depende de ellos, habrá que revisarlo caso por caso |

---

## 16. Referencias cruzadas

- `docs/02-configuracion-del-proyecto.md` — presets de importación del GLB y de la paleta (§7.1, §7.3), capas 3 y 4 y máscaras (§3).
- `docs/06-framework-de-enemigos.md` — consume los metadatos de §12: `EnemyPart`, `WeakPoint`, `detach()`, `ProceduralLegRig` y la cadena de pivotes de §4.4.
- `docs/07-arachnodroid.md` — HP, blindaje y condiciones de exposición por parte; asigna los valores de `hp` y `armor` del `parts.json`.
- `docs/03-especificacion-nucleo-de-vuelo.md` — consume `assets/drone/drone_quad.glb` y el orden de motores de §10.
- `docs/13-identidad-visual-y-audio.md` — el glow del Environment se apoya en las superficies emisivas de §6.1 y §7.1.
- `docs/14-catalogo-de-enemigos.md` — los otros 8 modelos y su orden de producción; la tabla de escalas de §3.4 es su punto de partida.
- `docs/15-verificacion-y-ci.md` — `enemy_import_check` en el catálogo general de checks.
- `docs/16-licencias-y-atribucion.md` — licencias de los packs voxel (D-6).
