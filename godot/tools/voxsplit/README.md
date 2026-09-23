# `voxsplit` — pipeline voxel → GLB jerárquico

Herramienta de línea de comandos que implementa `godot/docs/05-pipeline-voxel.md`: convierte
un `.vox` de MagicaVoxel (o un modelo procedural propio) en un **GLB con una parte por nodo**,
con jerarquía padre-hijo, pivotes en metros, materiales opaco y emisivo separados y UV sobre
una paleta de 256×1 píxeles.

- **Python 3.12**, solo biblioteca estándar más **Pillow**. `numpy` no se usa ni se necesita.
- **Determinista**: la misma entrada produce el mismo GLB **byte a byte**.
- Los `.vox` de `assets/_raw/` **se leen desde el ZIP**, nunca se extraen dentro del repo.

---

## 1. Uso

La CLI se invoca como módulo. Hay dos formas equivalentes:

### Desde `godot/tools/` (la más corta)

```powershell
cd godot\tools
python -m voxsplit --help
```

### Desde cualquier carpeta

`__main__.py` añade su carpeta padre a `sys.path`, así que también funciona por ruta directa:

```powershell
python C:\...\drone-survivor\godot\tools\voxsplit\__main__.py build ... --out ...
```

o, si preferís `-m`, fijando `PYTHONPATH`:

```powershell
$env:PYTHONPATH = "godot\tools"; python -m voxsplit build godot\enemies\... --out godot\enemies\...
```

```bash
PYTHONPATH=godot/tools python -m voxsplit build godot/enemies/... --out godot/enemies/...
```

### Subcomandos

```
python -m voxsplit inspect    <archivo.vox>
python -m voxsplit build      <parts.json | models.modulo> --out <dir>
                              [--preview] [--preview-out <dir>] [--report] [--allow-unassigned]
python -m voxsplit preview    <parts.json | models.modulo> [--out <dir>]
python -m voxsplit objinspect <archivo.obj | archivo.zip!miembro.obj>
                              [--step <u>] [--scale <f>] [--no-fill]
python -m voxsplit town       [<nuke_town.json>] --out <dir> [--quiet]
```

| Subcomando | Qué hace | Salidas |
|---|---|---|
| `inspect` | Tamaño, voxels, bbox ocupado, histograma de índices, emisivos según `MATL` y **componentes conexas** (globales y por índice de paleta, 6 vecinos). Es el punto de partida para escribir las cajas de un `parts.json` nuevo. | stdout |
| `build` | Segmenta, hace meshing greedy, escribe el GLB, lo **vuelve a leer y lo valida**, y emite el sidecar, la paleta y (opcionalmente) previews y reporte. | `<modelo>.glb`, `<modelo>.parts.json`, `<modelo>_palette.png`, `preview_*.png`, `report.txt` |
| `preview` | Solo las tres vistas ortográficas, sin tocar el GLB. Es el bucle de trabajo para ajustar cajas. | `preview_front/side/top.png` |
| `objinspect` | Lo mismo que `inspect` pero para un **OBJ** de MagicaVoxel: paso, bbox, dimensiones en celdas y en metros, triángulos del OBJ crudo, voxels recuperados (cáscara + relleno), conflictos y colores usados. Es el punto de partida para escribir un JSON de `compose`. | stdout |
| `town` | Compone las casas y los props del **pueblo de ruta** desde `models/nuke_town.json`: voxeliza cada OBJ del pack, agrupa la paleta, apila las piezas y emite un GLB por variante, más la paleta, la máscara emisiva, el sidecar y el reporte. | `<pieza>.glb` ×19, `nuke_town_palette.png`, `nuke_town_emissive.png`, `nuke_town.pieces.json`, `nuke_town_report.txt` |

### Códigos de salida

| Código | Significado |
|---|---|
| `0` | Todo bien |
| `1` | Hay voxels en `_unassigned` sin `--allow-unassigned`, o falla algún criterio del bloque `expect`. En `town`: alguna pieza se pasó del presupuesto de triángulos, no quedó centrada en XZ o apoyada en `y = 0`, o una pieza de casa resultó no estanca |
| `2` | El `parts.json`, el `.vox`, el `.obj` o el JSON de recetas son inválidos, o el GLB escrito no pasa la validación interna |

`objinspect` devuelve `0` o `2`. `town` devuelve los tres.

---

## 2. Regenerar los dos modelos del MVP

Ambos comandos se ejecutan **con `cwd = godot/tools`** (las rutas son relativas a esa carpeta):

```powershell
# Arachnodroid (jefe 1) — 31 partes, 4 007 voxels, 4 274 triángulos, 29.25 m
python -m voxsplit build ..\enemies\arachnodroid\arachnodroid.parts.json `
    --out ..\enemies\arachnodroid --report --preview `
    --preview-out .\voxsplit\previews\arachnodroid

# Dron del jugador — 16 partes, 1 132 voxels, 1 066 triángulos, diagonal 24.04 cm
python -m voxsplit build models.drone_quad `
    --out ..\assets\drone --report --preview `
    --preview-out .\voxsplit\previews\drone_quad
```

En bash es lo mismo, cambiando las barras y el carácter de continuación de línea:

```bash
cd godot/tools
python -m voxsplit build ../enemies/arachnodroid/arachnodroid.parts.json \
    --out ../enemies/arachnodroid --report --preview \
    --preview-out ./voxsplit/previews/arachnodroid
python -m voxsplit build models.drone_quad \
    --out ../assets/drone --report --preview \
    --preview-out ./voxsplit/previews/drone_quad
```

Y para mirar el `.vox` de origen sin extraerlo:

```bash
python -m voxsplit inspect '../assets/_raw/Arachnodroid.zip!Package/Arachnoid.vox'
```

> En PowerShell y cmd el `!` no necesita comillas; en bash sí (o usá comillas simples), porque
> `!` dispara la expansión del historial.

---

## 3. Módulos

| Archivo | Responsabilidad |
|---|---|
| `objvox.py` | Voxelizador **OBJ → rejilla**, para los packs que sólo traen malla y no `.vox`. Recupera la celda interior de cada cara por su normal, rellena el volumen por inundación y lee el color de la UV de paleta. Acepta `archivo.zip!miembro`. |
| `compose.py` | Compositor del pueblo de ruta: familias de paleta, recorte, diezmado, apilado de pisos, embutido de puertas, espejo y máscara emisiva. |
| `models/nuke_town.json` | Las recetas: qué OBJ es cada pieza, cómo se agrupa la paleta, qué índices se encienden y cómo se arma cada tipo y variante de casa. |
| `voxreader.py` | Parseo de `.vox` (chunks, `SIZE`, `XYZI`, `RGBA`, `MATL`, grafo `nTRN`/`nGRP`/`nSHP`, paleta por defecto). Acepta `archivo.zip!miembro`. |
| `parts.py` | Carga y validación de `parts.json`, `axis_map`, espejo, asignación de voxels y `_unassigned`. |
| `mesher.py` | Meshing greedy por parte y por material, UV de paleta, normales de eje, bobinado. |
| `glbwriter.py` | Serialización glTF 2.0 binaria, jerarquía, materiales, PNG de paleta. |
| `glbvalidate.py` | Validador propio: relee el GLB escrito y comprueba tamaños, referencias y que la jerarquía sea un árbol con una sola raíz. |
| `jsonio.py` | Serializador JSON determinista y legible (cajas y pivotes en una línea). |
| `preview.py` | Vistas ortográficas con Pillow, leyenda y magenta para `_unassigned`. |
| `__main__.py` | CLI, `report.txt` y códigos de salida. |
| `models/drone_quad.py` | Definición procedural del dron del jugador. |

---

## 4. Esquema de `parts.json`

Es el de `docs/05` §4, con unas pocas claves **opcionales** añadidas (todas con valor por
defecto, así que un `parts.json` escrito según el documento sigue siendo válido):

| Clave (cabecera) | Tipo | Para qué |
|---|---|---|
| `name` | string | Nombre base de las salidas; por defecto, el del archivo sin `.parts.json`. |
| `root_node` | string | Nombre del nodo raíz extra del GLB; por defecto `PascalCase(name) + "Root"`. |
| `grid_size` | `[x,y,z]` | Dimensiones de la retícula; necesarias para `mirror_of`. |
| `density` | float | kg/m³ para `estimated_mass`; por defecto 220 (`docs/05` §7.2). |
| `emissive_strength` | float | Fuerza de emisión fija; si falta se deriva del `MATL` (ver §5.4). |
| `expect` | objeto | Criterios que `build` verifica: `part_count`, `triangle_budget`, `total_height`, `height_tolerance`, `footprint`, `footprint_tolerance`. **Los números viven aquí, no en el código** (D-1 de `docs/05` §15). |

| Clave (parte) | Tipo | Para qué |
|---|---|---|
| `meta` | objeto | Metadatos libres que se copian al sidecar (el dron usa `motor_index` y `spin`). |
| `mirror_of` + `mirror_axes` | string + `[eje]` | Deriva una parte espejando otra ya definida con `c' = n − 1 − c`. Requiere `grid_size` o `mirror_extent`. |

> **Cuidado con `mirror_of`**: el sidecar se escribe **ya expandido**, así que si generás la
> salida sobre la misma carpeta del `parts.json` de entrada (que es lo normal, ver §5.1), el
> archivo de autoría con `mirror_of` se pierde. Por eso `arachnodroid.parts.json` trae las 31
> partes escritas de forma explícita; el espejo se aplicó una vez al generarlo.

---

## 5. Ambigüedades de `docs/05` resueltas aquí

`docs/05` es el documento que gobierna y **no se modificó**. Estos puntos quedaron abiertos o
contradictorios y se resolvieron de la forma más simple posible.

### 5.1 El sidecar tiene el mismo nombre que el `parts.json` de entrada

§7.2 dice que el sidecar es `<enemy>.parts.json` y §9.1 dice que el importador de Godot lo
localiza **sustituyendo la extensión del `source_file` por `.parts.json`**. Con `--out` igual a
la carpeta de entrada, sidecar y entrada son el mismo archivo.

**Resolución**: se escribe **en el mismo archivo**. El sidecar es un superconjunto del
`parts.json` (copia literal + bloque `metadata`), así que la operación es idempotente: volver a
construir sobre el sidecar da el mismo resultado. El archivo de entrada se lee entero en
memoria antes de escribir, y el sidecar solo se escribe **después** de que el GLB pase la
validación interna. Consecuencia práctica: el único campo que cambia en el diff entre dos
builds es `metadata.generated_at` (fijable con la variable de entorno `SOURCE_DATE_EPOCH`).

### 5.2 `source` no puede apuntar a un `.vox` dentro del repo

§4.1 pide una ruta al `.vox` relativa al `parts.json`, pero §1 prohíbe extraer `assets/_raw/`
dentro del repositorio.

**Resolución**: `voxreader.read()` acepta la forma `<ruta.zip>!<miembro>` y lee el miembro
directamente del ZIP con `zipfile`. `arachnodroid.parts.json` declara
`"source": "../../assets/_raw/Arachnodroid.zip!Package/Arachnoid.vox"`.

### 5.3 §14.1 codifica `part_count != 31` como constante, pero D-1 exige lo contrario

**Resolución**: los criterios viven en el bloque `expect` de la cabecera del `parts.json` (y se
copian al sidecar). La herramienta no conoce ningún número del Arachnodroid.

### 5.4 Un solo material emisivo, pero cuatro energías distintas

§7.1 declara un único material `voxel_emissive` con un `emissiveStrength`, mientras que §2.3
deriva una energía **por índice de paleta** (`_weight · 2^(_flux − 1)`). En el `.vox` real dan
cuatro valores distintos: índice 6 → 3.28, 7 → 0.72, 8 → 0.65, 14 → 0.72.

**Resolución**: se usa el **máximo** de las energías de los índices emisivos realmente usados
(3.28 para el Arachnodroid), para no recortar la intención del artista. Las cuatro energías, con
su color y su conteo de voxels, quedan registradas en `metadata.emissive_indices` del sidecar y
en `report.txt`, por si `docs/13` quiere afinar el glow por índice. Un `emissive_strength`
explícito en la cabecera tiene prioridad (el dron lo usa: 2.0).

### 5.5 Dónde van las previews

§7.2 las pone en `--out`. El paquete de trabajo WP-12a pide que vayan a
`tools/voxsplit/previews/<modelo>/` para no ensuciar las carpetas de assets.

**Resolución**: `--preview` las escribe en `--out` (como dice el documento) y la opción nueva
`--preview-out <dir>` las redirige. `preview.render()` deja un `.gdignore` vacío en la carpeta
de salida (y en `previews/` si es su padre) para que Godot no importe esos PNG.

> `tools/voxsplit/previews/` está en `.gitignore`: las previsualizaciones son material de
> trabajo local, no se versionan. Se regeneran con el mismo comando de §2.

### 5.6 Numeración de los motores del dron

`docs/05` §10 dice «orden Betaflight X: 1 = trasero-derecho, 2 = delantero-derecho,
3 = trasero-izquierdo, 4 = delantero-izquierdo». `docs/03` §2.1 —el documento que **gobierna el
mezclador**— dice: M1 delantero-izquierdo `(−0.08, 0, −0.08)` **CW**, M2 delantero-derecho
**CCW**, M3 trasero-derecho **CW**, M4 trasero-izquierdo **CCW**, con **−Z adelante**.

**Resolución**: manda `docs/03`, que es de quien depende el control. Los **cuatro puntos son
los mismos** que declara `docs/05` (`(6,6)`, `(6,23)`, `(23,6)`, `(23,23)` en índices de voxel);
lo único que cambia es qué número lleva cada uno. `spin` alterna en diagonal en ambas lecturas.

### 5.7 El dron tiene 16 partes, no 15

`docs/05` §10 lista 15. WP-12a pide además una **luz LED trasera emisiva** como parte `led`.
Se añadió como hijo de `frame` (4 voxels rojos, índice de paleta 6, emisivo), así que el modelo
tiene **16 partes**. El número vive en `metadata.part_count`, no en ningún check.

### 5.8 Pequeñas correcciones de geometría del dron

Todas documentadas porque se apartan de la letra de §10:

| Punto | `docs/05` §10 | Aquí | Por qué |
|---|---|---|---|
| Pivote de `frame` | `[15, 15, 4.5]` | `[14.5, 14.5, 4.5]` | Con `origin_voxel = [15,15,5]` el 0 de metros cae en el índice **14.5**, que es también el centro de la placa `[11..18]²` y el punto medio de los motores (6 y 23). Con `[15,15,·]` el modelo quedaba 5 mm descentrado respecto del centro de masa nominal. |
| Motores | «cilindro 4×4×3» | disco de 5×5 sin esquinas (21 celdas) × 3 | Un ancho par no puede centrarse en un índice entero; con 4×4 los centros caen en 22.5 y 6.5 y la diagonal baja a 22.6 cm. Con 5×5 los centros son exactamente 6 y 23 ⇒ **17 · √2 = 24.04 cm**, la cifra que fija §13. |
| `prop_N` / `prop_disk_N` | ambos con pivote en `z = 7` | `prop_N` en `z = 8`, `prop_disk_N` en `z = 9` | La pala y el disco son **el mismo objeto visual** en dos estados (`DroneRig` enciende uno u otro según las RPM), pero el pipeline asigna cada voxel a **una sola** parte. Separarlos 1 cm es lo mínimo que permite que existan las dos mallas. |
| Puntas de la pala | «2 voxels de ancho» | 2 de ancho salvo los 2 últimos voxels, que son 1 | Para que la pala quede **dentro** del disco de radio 6 que la sustituye. |

### 5.9 Etiquetas de `function`

§4.2 propone `vision`, `laser`, `locomotion`, `core`; `docs/06` §5 declara el conjunto
**canónico** `leg | sensor | weapon | cosmetic | core` y normaliza `vision → sensor`.

**Resolución**: se usan los valores canónicos de `docs/06` (`wp_head_visor` es `sensor`, no
`vision`), así `EnemyBase._ready()` no tiene que normalizar nada.

### 5.10 `weak_point_id`

§4.2 lo describe como «id del punto débil asociado», pero `underbelly` hospeda **tres**.

**Resolución**: la parte que lo lleva es el propio punto débil (su valor es su propio `id`) y,
además, el hospedador de un punto débil único (`leg_XX_tibia`) lo declara apuntando a su rodilla.
Las partes sin punto débil asociado omiten el campo.

### 5.11 `axis_map` con determinante −1

§3.3 dice que el lector **rechaza** los mapeos que invierten la orientación «sin corregir el
bobinado de los triángulos».

**Resolución**: se acepta cualquier permutación con signo (determinante ±1) y, cuando el
determinante es −1, el mesher **invierte el orden de los índices** de cada triángulo. Así el
bobinado antihorario visto desde fuera se conserva siempre (verificado: 0 triángulos invertidos
con `{"x":"+x","y":"+z","z":"+y"}`). Lo que sí se rechaza, con código 2, es un `axis_map` que no
sea una permutación (ejes repetidos o nombres inválidos).

### 5.12 Discrepancias menores encontradas al verificar contra el `.vox`

No cambian ningún criterio de aceptación, pero conviene tenerlas anotadas:

- **Triángulos: 4 274, no 4 282.** Todas las cifras por parte de §4.4 coinciden exactamente
  salvo `leg_XX_tibia` (42 en vez de 46, es decir 2 quads menos por pata) y `leg_bl/br_foot`
  (108 en vez de 104, 2 quads más por pata trasera). Es la diferencia esperable entre dos
  implementaciones greedy con distinto orden de crecimiento, y el espejo de las cajas no
  conserva el orden de fusión. El presupuesto es `< 12 000`, así que sobra margen.
- **Los 3 voxels cian «del cuello»** que §2.3 atribuye al `neck` están en realidad en
  `(17,14,24)`, `(17,25,24)` y `(22,25,24)`, es decir en `carapace` (z = 24). Por eso `neck`
  sale con `has_emissive_surface = false` y `carapace` con `true`. Los conteos totales (11
  voxels del índice 8) sí coinciden.
- **§14.2 criterio 11** (rodillas a 11.0 m y pies a 3.0 m sobre el suelo) no se cumple en
  reposo con los pivotes de §4.4: dan 8.625 m y 3.75 m. Es un criterio del check de Godot
  (WP-12b), no de este paquete; probablemente se refiera a la pose de marcha (`hip_height`
  14.0 m), no al modelo importado.
- `carapace` lleva `debris_mass` (52 t, de `docs/07` §3) pero **no** el flag `detachable`,
  porque `docs/05` §4.4 no se lo da y `docs/07` resuelve la apertura de P4 con una rotación.
  Lo mismo con `leg_XX_tibia` y `leg_XX_foot`: llevan `debris_mass` de `docs/07` y los flags
  de `docs/05`.

---

## 5bis. El pueblo de ruta: de OBJ a casa (WP-A)

El pack `assets/_raw/nuke Free Sample.zip` no trae `.vox` ni casas: trae 26 **OBJ ya
mallados** por MagicaVoxel con piezas sueltas de una escena (bloque cuadrado, bloque
angosto, dos tapas de techo, puerta, portón de garaje, barriles, basura y maleza). El
camino `objvox` → `compose` los devuelve a la rejilla, los apila y los vuelve a mallar con
el mismo mesher greedy que el dron y el Arachnodroid.

```
python -m voxsplit town --out ../assets/town        # cwd = godot/tools
```

### Por qué re-voxelizar en vez de importar el OBJ

El exportador de MagicaVoxel emite **un quad por cara de vóxel visible**, sin fusionar
nada: `BuildingBlock-0` son 48 644 triángulos para una casa de 4,85 × 2,50 m. Pasándolo
por la rejilla y por el mesher greedy la misma pieza queda en **346**, con la misma
silueta y con la UV de paleta de 256×1 del resto del pipeline.

### La rejilla: normales para la cáscara, inundación para el volumen

La normal de cada cara apunta hacia afuera, así que la celda del lado contrario es
*interior* y la del lado de la normal, *exterior*. Una celda se ocupa si alguna cara la
marca interior y ninguna la marca exterior; los conflictos se reportan, no se silencian
(en las 26 piezas del pack son **0**).

Esa regla sola recupera sólo la **cáscara**: MagicaVoxel no emite las caras entre dos
vóxeles adyacentes, así que un bloque macizo no deja ninguna cara por dentro y quedaría
hueco — y un modelo hueco no es equivalente al macizo, porque el mesher generaría también
la superficie interior. Por eso `objvox` hace además un **relleno por inundación** desde
fuera de la caja envolvente, cruzando de una celda a la vecina sólo cuando no hay una cara
entre las dos. `BuildingBlock-0` pasa de 37 236 celdas de cáscara a 470 428: es un macizo.

### Familias de paleta: el 98 % del ahorro

Las caras del pack están *dithered*. La fachada del bloque cuadrado alterna los índices
**69** `(174, 171, 136)` y **70** `(178, 174, 139)` vóxel a vóxel: una diferencia de
**4/255**, invisible, que sin embargo impide fusionar dos caras vecinas porque la UV
depende del índice. Medido sobre `BuildingBlock-0`:

| Paleta | Triángulos |
|---|---|
| Cruda (38 índices) | 34 390 |
| Un solo color (cota geométrica) | **70** |
| 11 familias perceptuales | **346** |

`palette_families` del JSON agrupa los 48 índices visibles del pack en 11 representantes.
Los tres índices de ventana (`7` papel, `50` marco, `13` fondo) se declaran aparte y
**nunca** se funden con la pared: son los que lleva la máscara emisiva. Una pieza puede
apagarlos con `palette_override` — el portón de garaje tiene manchas de moho del mismo
verde pálido que el vidrio y sin el override el garaje brillaría.

### `decimate`: la única palanca para la cota geométrica

Dos piezas tienen una cota de triángulos **geométrica**, no cromática: el ático
`Rooftop-0` (2 166 a un solo color) y el montón de basura grande (1 238). Para ésas el
JSON declara `decimate: 2` o `3`: se vota el color por bloques de *n*³ y se vuelve a
expandir **sobre la misma rejilla de 5 cm**, así la pieza sigue encajando vóxel a vóxel
con el bloque de abajo pero con la mitad (o un tercio) del detalle de superficie.

### Receta de una casa

| Campo | Qué hace |
|---|---|
| `stack` | Pisos apilados en Y, centrados en XZ sobre el primero |
| `roof` | Tapa apoyada en el techo del último piso |
| `attach` | Piezas **embutidas** en una cara (`-x`, `+x`, `-z`, `+z`) con `u` como fracción a lo largo de la cara. Embutidas y no pegadas: la puerta ocupa el hueco de la pared, así la huella del conjunto sigue siendo la del bloque |
| `trim` | Celdas que se recortan del último piso, para variar la altura |
| `mirror` | Espejo en X de todo el conjunto |

El resultado se recentra en XZ y se apoya en `y = 0`, que es lo que exigen `CityGrid` y
`tools/town_import_check.gd`.

### Escala

El pack está a 0,02 unidades por vóxel y se multiplica por **2,5**: 1 vóxel = **5 cm**, la
puerta mide **2,20 m** y el bloque **4,85 × 2,50 m**. El `axis_map` es la identidad porque
el OBJ de MagicaVoxel ya sale Y-arriba, a diferencia del `.vox`, que es Z-arriba.

---

## 6. Qué NO hace este paquete

El import en Godot (`asset_import/import_voxel_enemy.gd`, `asset_import/import_drone.gd` y
`tools/enemy_import_check.tscn`, §9 y §14.2 de `docs/05`) es **WP-12b**. Aquí solo se genera el
GLB, el sidecar, la paleta, las previews y el reporte.

El fallback de Blender (`fallback_blender.py`, §11) no se implementó: es explícitamente plan B
y `mesher.py` + `glbwriter.py` funcionan sobre los dos modelos del MVP (0.03 s de meshing para
4 007 voxels).
