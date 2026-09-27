## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Inventario de la galería de assets (planes P2e y P2f): **qué** entra en
## `tools/asset_gallery.tscn`, en qué fila, con qué etiqueta, qué huella ocupa,
## de dónde viene y si su escala es verosímil.
##
## Lo usan los dos lados del contrato —`tools/build_asset_gallery.gd`, que
## hornea la escena y escribe `assets/INVENTARIO.md`, y
## `tools/asset_gallery_check.gd`, que verifica las dos cosas— para que lo que
## *debería* haber salga siempre del mismo cálculo.
##
## ## Un catálogo de objetos
##
## Desde P2f la galería muestra sólo **objetos**: lo que se puede poner en un
## nivel. No entran los escombros, la pila, los VFX, los decals ni las mallas
## horneadas del nivel (son efectos o resultados de un horneado, no piezas), ni
## las piezas marcadas `placeholder` en su manifiesto (los cuatro vehículos
## procedurales del pueblo son cajas grises, no assets).
##
## ## Sin listas a mano
##
## Cada familia sale de su propia fuente de verdad, nunca de una tabla de piezas
## escrita acá:
##
## | Filas | Fuente |
## |---|---|
## | `Pueblo/*` | `assets/town/pieces_manifest.json` (54 piezas, 50 sin `placeholder`) |
## | `Ciudad/*` | `assets/city/pieces_manifest.json` (13 piezas) |
## | `Rocas` | `ROCK_IDS` y `ROCK_DIR` de `tools/build_city_meshes.gd` |
## | `Enemigos` | [constant EnemyCatalog.ENTRIES] (GLB **estático**, `JUGABLE`) más `assets/preview/enemies/` (`VISTA PREVIA`), por altura |
## | `Packs/*` | cada `assets/preview/*/pieces_manifest.json` (WP-G2) |
## | `Dron` | `assets/drone/drone_quad.glb` |
##
## Si mañana entra una pieza nueva en cualquiera de esas fuentes, la galería la
## muestra al volver a hornearla y el check la exige: no hay que tocar este
## archivo. Lo que sí hay que declarar acá es su **procedencia** si trae un
## `source`/`pack` nuevo ([constant PROVENANCE]) y, si su clase o su id no caen
## en ninguna, una regla de escala ([constant SCALE_RULES]).
##
## ## Procedencia y tintas
##
## La segunda línea de cada etiqueta empieza con `PROPIO` o
## `DESCARGADO (<pack>)`, y el `Label3D` va teñido según eso, con dos tintas
## legibles sobre el cielo gris de estudio y el suelo oscuro de la galería (las
## dos con contorno negro de 14):
##
## - **propio** `#66D9FF` (0,4 · 0,85 · 1,0): cian;
## - **descargado** `#FFA333` (1,0 · 0,64 · 0,2): ámbar;
## - procedencia **desconocida** (`?`) `#FF73CC`: magenta, para que salte a la
##   vista; el check la pone en rojo.
##
## Los primeros tonos, más pálidos (`#8CEBFF` y `#FFCC80`, con contorno de 10),
## se perdían contra el horizonte blanquecino del atardecer.
##
## ## Escala
##
## El juego usa **metros reales** y la unidad de comparación es el dron
## (0,24 m de diagonal motor a motor, `docs/05` §10), que va posado sobre el
## poste de 2 m de cada fila. Cada entrada lleva dos marcas posibles, en una
## tercera línea de la etiqueta que sólo aparece si hay marca:
##
## - `MEDIDA≠ A×F×H m`: la caja real de la escena difiere de la que declara su
##   manifiesto en más de [constant MEASURE_TOLERANCE_RATIO] o
##   [constant MEASURE_TOLERANCE_MIN] m en algún eje;
## - `ESCALA? motivo`: la caja real cae fuera de su regla de [constant SCALE_RULES],
##   o un rasgo humano medido (la puerta, la planta) no tiene el tamaño de uno
##   real (ver «Rasgos humanos»).
##
## ## Rasgos humanos
##
## La caja sola no alcanza: el `block_low_a` del FreeSample medía 30 × 12,5 m, que
## es un edificio verosímil, y era una casa de una planta con una puerta de
## 10 m. Desde P2f el manifiesto de ciudad trae, por edificio, `features` con el
## alto de la **puerta** (`door_native`) y de una **planta** (`floor_native`) en
## unidades nativas del FBX, medidos en la fachada; esta fuente lee el
## `nodes/root_scale` **vigente** de cada `.fbx.import` ([method root_scale_of])
## y los lleva a metros ([method human_features]). La regla de `building` los
## exige en [constant DOOR_RANGE] y [constant FLOOR_RANGE]: si alguien vuelve a
## poner 5.0, la etiqueta dice `ESCALA? puerta 10,5 m` sola.
##
## ## Por qué ahora sí tiene `class_name`
##
## Hasta P2e nombraba a `VFXPool`, que arrastra a los autoload, y el horneador
## corre con `-s`, que compila su script antes de darlos de alta: una clase
## global que lo nombrara moría con «Identifier not found». Sin las filas de
## efectos, este archivo sólo pide con `load()` —en el momento de usarlos— el
## catálogo de enemigos y la herramienta de rocas, y no nombra ningún autoload
## ni ninguna clase que los nombre: puede ser [AssetGallerySources] y el
## horneador y el check lo llaman por su nombre, como a [SceneBake].
class_name AssetGallerySources
extends RefCounted

## Orden y nombre de las filas. `node` es el nombre del nodo en la escena (el
## árbol del editor no admite `/`). Dos claves opcionales: `gap`, el aire mínimo
## entre piezas en metros, para las filas cuyas etiquetas necesitan un paso
## propio (los mechas de veinte metros y las filas de packs donde una pieza de
## 0,9 m queda al lado de una de 4–6 m, que aleja la cámara y junta las
## etiquetas de las chicas), y `sort: height`, que ordena la fila de menor a
## mayor altura real aunque sus piezas vengan de fuentes distintas.
const ROWS: Array[Dictionary] = [
	{"name": "Pueblo/Edificios", "node": "Pueblo_Edificios"},
	{"name": "Pueblo/Props", "node": "Pueblo_Props"},
	{"name": "Pueblo/Follaje", "node": "Pueblo_Follaje"},
	{"name": "Ciudad/Edificios", "node": "Ciudad_Edificios"},
	{"name": "Ciudad/Props", "node": "Ciudad_Props"},
	{"name": "Ciudad/Viario", "node": "Ciudad_Viario"},
	{"name": "Rocas", "node": "Rocas"},
	{"name": "Enemigos", "node": "Enemigos", "gap": 16.0, "sort": "height"},
	{"name": "Packs/Autos y calle", "node": "Packs_Autos", "gap": 3.0},
	{"name": "Packs/Ciudad voxel", "node": "Packs_CiudadVoxel"},
	{"name": "Packs/Aldea", "node": "Packs_Aldea", "gap": 4.5},
	{"name": "Packs/Follaje extra", "node": "Packs_Follaje", "gap": 3.0},
	{"name": "Packs/Nuke extra", "node": "Packs_Nuke"},
	{"name": "Packs/Barrancas", "node": "Packs_Barrancas"},
	{"name": "Dron", "node": "Dron"},
]

## Procedencia por origen. La clave es el `source` de la pieza (pueblo,
## ciudad), el `pack` (vistas previas) o el origen que esta misma fuente le da
## a las demás familias (`procedural` para las rocas, `drone` para el dron, el
## id del enemigo para los del catálogo). El valor:
##
## - `made`: `propio` (geometría escrita en este repositorio: `SurfaceTool` de
##   `build_town_props.gd`/`build_city_meshes.gd` o el modelo `drone_quad.py`)
##   o `descargado` (derivado de un archivo de `assets/_raw/`);
## - `pack`: el archivo de `assets/_raw/` del que deriva, o `pipeline propio`.
##   Vacío en `mech`: cada mecha viene de su propio `.zip`/`.rar`, y el
##   manifiesto de vistas previas lo trae en `source`;
## - `tag`: el nombre corto que va entre paréntesis en la etiqueta.
##
## Contrastado con `assets/town/LICENSE-PENDING.md` §1–§2,
## `assets/preview/LICENSE-PENDING.md` §1 y `docs/16` §4.
const PROVENANCE: Dictionary[String, Dictionary] = {
	"procedural": {"made": "propio", "pack": "pipeline propio", "tag": ""},
	"drone": {"made": "propio", "pack": "pipeline propio", "tag": ""},
	"nuke_town": {"made": "descargado", "pack": "nuke Free Sample.zip", "tag": "nuke"},
	"nuke": {"made": "descargado", "pack": "nuke Free Sample.zip", "tag": "nuke"},
	"foliage": {"made": "descargado", "pack": "Foliage.rar", "tag": "foliage"},
	"village": {"made": "descargado", "pack": "VoxelVillagePack.zip", "tag": "village"},
	"city_sample": {"made": "descargado", "pack": "city-Free Sample.zip", "tag": "vcity"},
	"vcity": {"made": "descargado", "pack": "city-Free Sample.zip", "tag": "vcity"},
	"freesample": {"made": "descargado", "pack": "FreeSample.zip", "tag": "freesample"},
	"cars": {"made": "descargado", "pack": "cars.zip", "tag": "cars"},
	"cliffs": {"made": "descargado", "pack": "Package.zip", "tag": "cliffs"},
	"mech": {"made": "descargado", "pack": "", "tag": "mech"},
	"arachnodroid": {"made": "descargado", "pack": "Arachnodroid.zip", "tag": "arachnodroid"},
}

## Tinta del `Label3D` por procedencia (ver la cabecera).
const TINTS: Dictionary[String, Color] = {
	"propio": Color(0.4, 0.85, 1.0, 1.0),
	"descargado": Color(1.0, 0.64, 0.2, 1.0),
	"?": Color(1.0, 0.45, 0.8, 1.0),
}

## Licencia que declara el inventario según la procedencia.
const LICENSES: Dictionary[String, String] = {
	"propio": "propio",
	"descargado": "pendiente (docs/16 §4)",
	"?": "?",
}

## Tolerancia de «declarado = medido», por eje: el mayor entre este tanto por
## uno de la medida declarada y [constant MEASURE_TOLERANCE_MIN] metros (un
## vóxel de más en una pieza chica no es un error de manifiesto).
const MEASURE_TOLERANCE_RATIO: float = 0.10
const MEASURE_TOLERANCE_MIN: float = 0.30

## Holgura de redondeo al comparar contra los límites de [constant SCALE_RULES]:
## medio centímetro, para que una maleza de 0,05 m medida en 0,0499 no salte.
const SCALE_EPSILON: float = 0.005

## Módulos admitidos para la huella de las baldosas y los pisos, en metros, y su
## tolerancia: la calle del pack de autos va en 4 m, la de Nuke y la ciudad
## voxel en 5 m, el hormigón y los trozos del FreeSample en 10 y 20 m.
const TILE_MODULES: Array[float] = [4.0, 5.0, 10.0, 20.0]
const TILE_MODULE_TOLERANCE: float = 0.3

## Nombre de cada eje de las reglas en el motivo de `ESCALA?`. `height` y
## `thickness` son el alto; `side` y `length`, el lado mayor de la huella (se
## llaman distinto para que el motivo se lea: el lado de una casa, el largo de
## un auto); `width`, el lado menor; `size`, la mayor de las tres medidas.
const AXIS_NAMES: Dictionary[String, String] = {
	"height": "alto", "thickness": "espesor", "side": "lado", "length": "largo",
	"width": "ancho", "size": "tamaño",
}

## Reglas de verosimilitud por clase, en metros reales. Gana la **primera** que
## coincide: una regla coincide si la clase de la pieza está en `klass` o si su
## id encaja en alguno de los patrones de `ids` (`String.match`, con `*`). Por
## eso las de id van antes que las de clase. `limits` es eje → `[mín, máx]` (ver
## [constant AXIS_NAMES]); `module` exige que cada lado de la huella esté a
## [constant TILE_MODULE_TOLERANCE] de uno de [constant TILE_MODULES]. Una pieza
## sin regla lleva `ESCALA? sin regla`.
##
## Por qué cada rango, con el tamaño de la cosa real:
##
## - **dron** 0,20–0,35 m de lado: un quad FPV de 5" mide 220–250 mm motor a
##   motor, y las hélices de 5" sobresalen hasta ~0,35 m de caja;
## - **enemigo** 20–45 m de alto: la guía de `docs/05` §3.4 y `docs/14`;
## - **roca** 0,5–20 m de tamaño: de una piedra que se nota desde el dron a un
##   peñón que cierra el horizonte (las rocas de borde de `build_city_meshes.gd`
##   miden 10–18 m, como un afloramiento serrano; el tope de 10 m del pedido
##   original las marcaba a todas por ser lo que son); por id, porque hay rocas
##   con clase `foliage` y `prop`;
## - **vehículo** (clase o `car_*`, `pickup`, `truck`, `*taxi*`) 3,5–9 m de
##   largo, 1,6–2,6 m de ancho, 1,3–3,5 m de alto: de un auto chico (3,6 m) a un
##   camión rígido (8–9 m); el ancho legal ronda 2,6 m y un furgón 3,5 m de alto;
## - **galpón** (`shed*`) lado ≥ 3 m, alto 2–6 m: un galpón de herramientas
##   empieza en 3 × 2 m de planta y 2–2,5 m de alto;
## - **edificio** lado ≥ 6 m, alto 2,6–90 m: una casa de una planta tiene 6–12 m
##   de lado y 2,6–3,5 m por planta (un local de una planta del FreeSample mide
##   2,63 m a escala medida, P2f); una torre de 25 pisos, ~80 m. Con rasgos
##   medidos (`features`), además, **puerta** 1,9–2,5 m (una puerta real mide
##   2,0–2,3 m; el margen es el vóxel de 0,1 nativo) y **planta** 2,6–4,0 m (de
##   una planta baja de vivienda a una de local comercial);
## - **piso de edificio** (`*floor*`) alto 2,3–4 m y huella modular: una planta
##   con su losa mide 2,5–3,5 m;
## - **baldosa** (clase `street`/`block` o `*_tile*`, `*_chunk*`, `*crossing*`,
##   `*street*`, `*curb*`, `*road*`) espesor ≤ 0,3 m y huella modular: una
##   calzada o una vereda son una capa de 10–20 cm sobre el terreno;
## - **árboles**: `tree_small` 3–6 m (un árbol joven), `tree_medium` 6–12 m,
##   `tree_large`/`tree_xl` 10–20 m (un eucalipto o un álamo de campo);
##   `tree_stump` 0,3–1,5 m; el resto de los árboles (`*tree*`) 3–20 m;
## - **arbusto** 0,5–2,5 m; **pasto, flores, plantas, maíz, rosal, hongo**
##   0,2–2,5 m (el maíz maduro llega a 2,5 m);
## - **farol, farola y mástil** 3–12 m de alto: un farol de plaza tiene 3–4 m,
##   una columna de avenida 8–12 m, un mástil de plaza 8–12 m;
## - **carteles** (`*sign*` o clase `sign`) 2–6 m de alto: una señal vial se
##   planta a 2–3,5 m; un cartel de ruta, hasta 6 m;
## - **banco** 1,5–2,2 m de largo;
## - **cajón y barril** 0,4–1,3 m: un tambor de 200 l mide 0,9 × 0,6 m;
## - **parada y puesto de mercado** 2–3,5 m de alto: se pasa por debajo;
## - **toldo** 1,5–6 m de ancho y 0,3–1,5 m de alto: el toldo de una puerta se
##   cuelga a 2–3 m, pero la pieza es sólo su faldón (la regla del pedido original
##   —2–3,5 m de alto— medía la altura a la que se cuelga, no la pieza);
## - **basura y maleza** 0,05–1,5 m de alto: de una mancha en el piso a una bolsa
##   apilada;
## - **puente** 2–6 m de alto: tablero, barandas y estribos;
## - **monumento** 2–8 m;
## - **el resto de los props** 0,2–12 m de tamaño;
## - **el resto del follaje** 0,2–20 m de alto.
const SCALE_RULES: Array[Dictionary] = [
	{"klass": ["drone"], "ids": [], "limits": {"side": [0.20, 0.35]}},
	{"klass": ["enemy"], "ids": [], "limits": {"height": [20.0, 45.0]}},
	{"klass": ["rock"], "ids": ["*rock*"], "limits": {"size": [0.5, 20.0]}},
	{"klass": ["vehicle"], "ids": ["car_*", "pickup", "truck", "*taxi*"],
			"limits": {"length": [3.5, 9.0], "width": [1.6, 2.6], "height": [1.3, 3.5]}},
	{"klass": [], "ids": ["shed*"], "limits": {"side": [3.0, INF], "height": [2.0, 6.0]}},
	{"klass": ["building"], "ids": [], "limits": {"side": [6.0, INF], "height": [2.6, 90.0]},
			"features": {"door": DOOR_RANGE, "floor": FLOOR_RANGE}},
	{"klass": [], "ids": ["*floor*"], "limits": {"height": [2.3, 4.0]}, "module": true},
	{"klass": ["sign"], "ids": ["*sign*"], "limits": {"height": [2.0, 6.0]}},
	{"klass": ["street", "block"],
			"ids": ["*_tile*", "*_chunk*", "*crossing*", "*street*", "*curb*", "*road*"],
			"limits": {"thickness": [0.0, 0.3]}, "module": true},
	{"klass": [], "ids": ["tree_small"], "limits": {"height": [3.0, 6.0]}},
	{"klass": [], "ids": ["tree_medium"], "limits": {"height": [6.0, 12.0]}},
	{"klass": [], "ids": ["tree_large", "tree_xl"], "limits": {"height": [10.0, 20.0]}},
	{"klass": [], "ids": ["*tree_stump*"], "limits": {"height": [0.3, 1.5]}},
	{"klass": [], "ids": ["*tree*"], "limits": {"height": [3.0, 20.0]}},
	{"klass": [], "ids": ["*bush*"], "limits": {"height": [0.5, 2.5]}},
	{"klass": [], "ids": ["*grass*", "*flowers*", "*plant*", "*corn*", "*rose*", "*mushroom*"],
			"limits": {"height": [0.2, 2.5]}},
	{"klass": [], "ids": ["*lamp_post*", "*lantern*", "*flag_mast*"],
			"limits": {"height": [3.0, 12.0]}},
	{"klass": [], "ids": ["*bench*"], "limits": {"length": [1.5, 2.2]}},
	{"klass": [], "ids": ["*crate*", "*barrel*"], "limits": {"size": [0.4, 1.3]}},
	{"klass": [], "ids": ["*bus_stop*", "*market_stall*"], "limits": {"height": [2.0, 3.5]}},
	{"klass": [], "ids": ["*awning*"], "limits": {"length": [1.5, 6.0], "height": [0.3, 1.5]}},
	{"klass": [], "ids": ["*trash*", "*overgrowth*", "*weeds*"],
			"limits": {"height": [0.05, 1.5]}},
	{"klass": [], "ids": ["*bridge*"], "limits": {"height": [2.0, 6.0]}},
	{"klass": [], "ids": ["*monument*"], "limits": {"height": [2.0, 8.0]}},
	{"klass": ["prop"], "ids": [], "limits": {"size": [0.2, 12.0]}},
	{"klass": ["foliage"], "ids": [], "limits": {"height": [0.2, 20.0]}},
]

## Rangos de los rasgos humanos de la regla de `building`, en metros (ver la
## lista de [constant SCALE_RULES]).
const DOOR_RANGE: Array[float] = [1.9, 2.5]
const FLOOR_RANGE: Array[float] = [2.6, 4.0]

## Nombre de cada rasgo en el motivo de `ESCALA?` y su clave nativa en el
## manifiesto de ciudad.
const FEATURE_NAMES: Dictionary[String, String] = {"door": "puerta", "floor": "planta"}
const FEATURE_KEYS: Dictionary[String, String] = {"door": "door_native", "floor": "floor_native"}

## Carpeta de los FBX de ciudad y de sus `.fbx.import`.
const CITY_MODELS_DIR: String = "res://assets/city/models"

## Referencia del diagnóstico de escala del inventario: lado mayor de una casa
## de pueblo y alto de una planta, en metros.
const BUILDING_SIDE_REFERENCE: Vector2 = Vector2(8.0, 12.0)
const FLOOR_HEIGHT_REFERENCE: Vector2 = Vector2(3.0, 3.5)

const TOWN_MANIFEST: String = "res://assets/town/pieces_manifest.json"
## Carpeta de las vistas previas de packs (WP-G2): una subcarpeta por pack, cada
## una con su `pieces_manifest.json` escrito por `voxsplit`.
const PREVIEW_DIR: String = "res://assets/preview"
const CITY_MANIFEST: String = "res://assets/city/pieces_manifest.json"
const CITY_MESHES_TOOL: String = "res://tools/build_city_meshes.gd"
const DRONE_GLB: String = "res://assets/drone/drone_quad.glb"
const ENEMY_CATALOG: String = "res://enemies/enemy_catalog.gd"
const INVENTORY_PATH: String = "res://assets/INVENTARIO.md"

## Giro del dron para mirarlo de frente desde +Z: su cámara está en los vóxeles
## `y` 19–21 de la retícula de 30 (`docs/05` §10), que el `axis_map`
## (`z = −y`) lleva a −Z. Media vuelta la trae hacia la cámara de la fila.
const DRONE_YAW: float = PI


# --------------------------------------------------------------------------
# La lista
# --------------------------------------------------------------------------

## Todas las entradas de la galería, en el orden de [constant ROWS] (y, dentro
## de las filas con `sort: height`, de menor a mayor altura real).
##
## Cada entrada es un diccionario con:
## `id`, `row` (nombre de fila), `path` (escena o GLB), `origin` (clave de
## [constant PROVENANCE]), `klass`, `dims` (A×F×H de la etiqueta: lo declarado
## en el manifiesto o, si no declara, lo medido), `declared` (`true` si `dims`
## viene de un manifiesto), `real` (A×F×H medido en la escena), `tris`,
## `preview_only`, `playable`, `yaw` (giro en Y), `aabb` (caja local medida,
## **sin girar**, para repartir la fila), `note` (aclaración del informe),
## `made`, `archive` y `tag` (procedencia) y `marks` (`MEDIDA≠` y `ESCALA?`). Los
## edificios de ciudad con rasgos medidos suman `features_native` y `root_scale`.
static func entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	found.append_array(_town_entries())
	found.append_array(_city_entries())
	found.append_array(_rock_entries())
	found.append_array(_enemy_entries())
	found.append_array(_preview_entries())
	found.append_array(_drone_entries())
	for entry: Dictionary in found:
		entry.merge(provenance(String(entry["origin"]), String(entry.get("own_archive", ""))),
				true)
		var marks := measure_marks(entry)
		marks.append_array(scale_marks(entry))
		entry["marks"] = marks
	return _in_row_order(found)


## Texto de la etiqueta de [param entry]: `id`; debajo,
## `PROPIO|DESCARGADO (pack) · clase · A×F×H m · N tris` (+ `VISTA PREVIA`,
## + `JUGABLE`); y, sólo si hay marcas, una tercera línea con ellas.
static func label_text(entry: Dictionary) -> String:
	var line := "%s · %s · %s m · %d tris" % [provenance_token(entry), String(entry["klass"]),
			size_text(entry["dims"]), int(entry["tris"])]
	if bool(entry.get("preview_only", false)):
		line += " · VISTA PREVIA"
	if bool(entry.get("playable", false)):
		line += " · JUGABLE"
	var text := "%s\n%s" % [String(entry["id"]), line]
	var marks := marks_line(entry)
	if not marks.is_empty():
		text += "\n" + marks
	return text


## `PROPIO`, `DESCARGADO (<tag>)` o `?`.
static func provenance_token(entry: Dictionary) -> String:
	match String(entry.get("made", "?")):
		"propio":
			return "PROPIO"
		"descargado":
			return "DESCARGADO (%s)" % String(entry.get("tag", ""))
	return "?"


## Tinta de la etiqueta de [param entry] según su procedencia.
static func tint(entry: Dictionary) -> Color:
	return TINTS.get(String(entry.get("made", "?")), TINTS["?"])


## La tercera línea de la etiqueta: las marcas separadas por ` · `, o `""`.
static func marks_line(entry: Dictionary) -> String:
	return " · ".join(entry.get("marks", PackedStringArray()) as PackedStringArray)


## `A×F×H` con [method num].
static func size_text(dims: Vector3) -> String:
	return "%s×%s×%s" % [num(dims.x), num(dims.y), num(dims.z)]


## Número corto para la etiqueta: sin ceros de más, con la precisión que el
## tamaño merece y coma decimal.
static func num(value: float) -> String:
	var text := ""
	if absf(value) >= 100.0:
		text = "%.0f" % value
	elif absf(value) >= 10.0:
		text = "%.1f" % value
	else:
		text = "%.2f" % value
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text.replace(".", ",")


## Cámara que encuadra el tramo de fila entre [param min_x] y [param max_x]
## (coordenadas de mundo), de [param height] metros de alto, con la fila en
## [param z]; [param front] es cuánto sobresale el tramo hacia la cámara desde
## [param z] (un camión de ocho metros visto de frente), y la distancia se mide
## desde ahí. Es la regla de `town_showcase.gd::_shoot_row()`: la distancia sale
## del ancho y del campo de visión, no de un número a ojo.
##
## Lo chato —una baldosa de calle— se mira más desde arriba: a ras del suelo una
## losa de 20 m es una raya.
static func frame(min_x: float, max_x: float, height: float, z: float, fov: float,
		front: float = 0.0) -> Transform3D:
	var width := max_x - min_x
	var distance := frame_distance(width, height, fov)
	var centre := (min_x + max_x) * 0.5
	var flat := clampf(1.0 - height / maxf(width, 0.01) * 4.0, 0.0, 1.0)
	var lift := maxf(height * 0.55, 1.6) + distance * (0.18 + 0.8 * flat)
	var eye := Vector3(centre, lift, z + maxf(front, 0.0) + distance)
	var target := Vector3(centre, height * 0.45, z)
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


## Distancia de cámara con la que un tramo de [param width] metros de ancho y
## [param height] de alto entra en cuadro con un campo de visión vertical de
## [param fov] grados. El horizontal, con 16:9, es 1,6 veces el vertical (con
## aire).
static func frame_distance(width: float, height: float, fov: float) -> float:
	var half_fov := tan(deg_to_rad(fov) * 0.5)
	var margin := width * 0.5 + 2.0
	return maxf(maxf(margin / (half_fov * 1.6), height * 0.75 / half_fov), 3.0)


## Nombre de nodo de la fila [param row_name].
static func row_node(row_name: String) -> String:
	return String(row_info(row_name).get("node", ""))


## La entrada de [constant ROWS] de la fila [param row_name], o `{}`.
static func row_info(row_name: String) -> Dictionary:
	for row: Dictionary in ROWS:
		if String(row["name"]) == row_name:
			return row
	return {}


## Diagonal motor a motor del dron, medida en su GLB: la mayor distancia entre
## los pivotes de sus nodos `motor_*`. Es el número que lleva la etiqueta del
## poste de escala (`docs/05` §10 lo declara en 24 cm).
static func drone_span() -> float:
	var root := instance(DRONE_GLB)
	if root == null:
		return 0.0
	var motors: Array[Vector3] = []
	for node: Node in walk(root):
		if node is Node3D and String(node.name).begins_with("motor_"):
			motors.append(relative_transform(node as Node3D, root).origin)
	root.free()
	var span := 0.0
	for index: int in motors.size():
		for other: int in range(index + 1, motors.size()):
			span = maxf(span, motors[index].distance_to(motors[other]))
	return span


# --------------------------------------------------------------------------
# Procedencia y escala
# --------------------------------------------------------------------------

## Procedencia del origen [param origin]: `{made, archive, tag}`.
## [param own_archive] es el archivo que la pieza misma dice que la originó (el
## `source` de las vistas previas): llena el `pack` vacío de `mech` y, si
## contradice a [constant PROVENANCE], es un error. Un origen que no esté en la
## tabla sale con `made = "?"` y un `push_error`.
static func provenance(origin: String, own_archive: String = "") -> Dictionary:
	if not PROVENANCE.has(origin):
		push_error("asset_gallery: procedencia desconocida para el origen '%s'" % origin)
		return {"made": "?", "archive": own_archive if not own_archive.is_empty() else "?",
				"tag": "?"}
	var info := PROVENANCE[origin]
	var archive := String(info["pack"])
	if archive.is_empty():
		archive = own_archive
	elif not own_archive.is_empty() and own_archive != archive:
		push_error("asset_gallery: '%s' dice venir de '%s' y PROVENANCE dice '%s'"
				% [origin, own_archive, archive])
	return {"made": String(info["made"]), "archive": archive, "tag": String(info["tag"])}


## `MEDIDA≠ A×F×H m` si la caja real de [param entry] difiere de la declarada
## en más de la tolerancia en algún eje; nada si no declara medidas.
static func measure_marks(entry: Dictionary) -> PackedStringArray:
	if not bool(entry.get("declared", false)):
		return PackedStringArray()
	var declared: Vector3 = entry["dims"]
	var real: Vector3 = entry["real"]
	for axis: int in 3:
		var allowed := maxf(declared[axis] * MEASURE_TOLERANCE_RATIO, MEASURE_TOLERANCE_MIN)
		if absf(real[axis] - declared[axis]) > allowed:
			return PackedStringArray(["MEDIDA≠ %s m" % size_text(real)])
	return PackedStringArray()


## `ESCALA? motivo, motivo` si la caja real de [param entry] cae fuera de su
## regla de [constant SCALE_RULES]; nada si cumple.
static func scale_marks(entry: Dictionary) -> PackedStringArray:
	var rule := scale_rule(entry)
	if rule.is_empty():
		return PackedStringArray(["ESCALA? sin regla para '%s'" % String(entry["klass"])])
	var real: Vector3 = entry["real"]
	var reasons := PackedStringArray()
	var measured := human_features(entry)
	var wanted: Dictionary = rule.get("features", {})
	for feature: String in wanted:
		if not measured.has(feature):
			continue
		var bounds: Array = wanted[feature]
		var size := float(measured[feature])
		if size < float(bounds[0]) - SCALE_EPSILON or size > float(bounds[1]) + SCALE_EPSILON:
			var _added := reasons.append("%s %s m" % [FEATURE_NAMES[feature], num(size)])
	var limits: Dictionary = rule["limits"]
	for axis: String in limits:
		var range_: Array = limits[axis]
		var value := _axis_value(real, axis)
		var low := float(range_[0])
		var high := float(range_[1])
		if value < low - SCALE_EPSILON:
			var _added := reasons.append("%s %s m < %s m" % [AXIS_NAMES[axis], num(value), num(low)])
		elif value > high + SCALE_EPSILON:
			var _added := reasons.append("%s %s m > %s m" % [AXIS_NAMES[axis], num(value), num(high)])
	if bool(rule.get("module", false)):
		for side: float in [real.x, real.y]:
			if tile_module(side) < 0.0:
				var modules := PackedStringArray()
				for module: float in TILE_MODULES:
					var _module := modules.append(num(module))
				var _added := reasons.append("módulo %s m ∉ {%s}" % [num(side), ", ".join(modules)])
				break
	if reasons.is_empty():
		return PackedStringArray()
	return PackedStringArray(["ESCALA? %s" % ", ".join(reasons)])


## Rasgos humanos de [param entry] en metros: `{door, floor}` (sólo los que su
## manifiesto mide), cada uno su medida nativa por el `root_scale` de la entrada.
static func human_features(entry: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	var native: Dictionary = entry.get("features_native", {})
	var factor := float(entry.get("root_scale", 1.0))
	for feature: String in FEATURE_KEYS:
		if native.has(FEATURE_KEYS[feature]):
			found[feature] = float(native[FEATURE_KEYS[feature]]) * factor
	return found


## `nodes/root_scale` vigente del FBX de ciudad [param model], leído de su
## `.fbx.import` (el que el importador hornea en los vértices), o 1 si no hay.
static func root_scale_of(model: String) -> float:
	var config := ConfigFile.new()
	var path := "%s/%s.fbx.import" % [CITY_MODELS_DIR, model]
	if config.load(path) != OK:
		push_error("asset_gallery: no se pudo leer '%s'" % path)
		return 1.0
	return float(config.get_value("params", "nodes/root_scale", 1.0))


## La primera regla de [constant SCALE_RULES] que le toca a [param entry], o `{}`.
static func scale_rule(entry: Dictionary) -> Dictionary:
	var id := String(entry["id"])
	var klass := String(entry["klass"])
	for rule: Dictionary in SCALE_RULES:
		if (rule["klass"] as Array).has(klass):
			return rule
		for pattern: String in rule["ids"]:
			if id.match(pattern):
				return rule
	return {}


## El módulo de [constant TILE_MODULES] al que está cerca [param side], o −1.
static func tile_module(side: float) -> float:
	for module: float in TILE_MODULES:
		if absf(side - module) <= TILE_MODULE_TOLERANCE:
			return module
	return -1.0


static func _axis_value(real: Vector3, axis: String) -> float:
	match axis:
		"height", "thickness":
			return real.z
		"side", "length":
			return maxf(real.x, real.y)
		"width":
			return minf(real.x, real.y)
	return maxf(real.x, maxf(real.y, real.z))


# --------------------------------------------------------------------------
# INVENTARIO.md
# --------------------------------------------------------------------------

## El texto de `assets/INVENTARIO.md` para [param all] (las entradas de
## [method entries]). Determinista: sin fecha ni hora, filas y packs en orden
## fijo; dos horneados dan los mismos bytes.
static func inventory_text(all: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	var own := 0
	var downloaded := 0
	var scale_flags := 0
	var measure_flags := 0
	for entry: Dictionary in all:
		own += 1 if String(entry["made"]) == "propio" else 0
		downloaded += 1 if String(entry["made"]) == "descargado" else 0
		scale_flags += 1 if not _mark(entry, "ESCALA?").is_empty() else 0
		measure_flags += 1 if not _mark(entry, "MEDIDA≠").is_empty() else 0
	var _l := lines.append("# Inventario de assets")
	_l = lines.append("")
	_l = lines.append("> Generado por `tools/build_asset_gallery.gd` en cada horneado de la "
			+ "galería, desde las mismas fuentes (`tools/asset_gallery_sources.gd`); "
			+ "`asset_gallery_check` exige que esté al día. **No editar a mano.** Medidas en "
			+ "metros reales, A×F×H = ancho (X) × fondo (Z) × alto (Y); «medida real» sólo "
			+ "si difiere de la declarada (`MEDIDA≠`); «escala» según `SCALE_RULES`; "
			+ "licencias en `docs/16` §4.")
	_l = lines.append("")
	_l = lines.append("%d objetos en %d filas · propio %d · descargado %d · con `ESCALA?` %d · "
			% [all.size(), ROWS.size(), own, downloaded, scale_flags]
			+ "con `MEDIDA≠` %d." % measure_flags)
	for row: Dictionary in ROWS:
		var members := _row_members(all, String(row["name"]))
		_l = lines.append("")
		_l = lines.append("## %s (%d)" % [String(row["name"]), members.size()])
		_l = lines.append("")
		_l = lines.append("| id | procedencia | pack/archivo | clase | A×F×H m | tris | "
				+ "medida real | escala | licencia |")
		_l = lines.append("|---|---|---|---|---|---|---|---|---|")
		for entry: Dictionary in members:
			var measured := _mark(entry, "MEDIDA≠").trim_prefix("MEDIDA≠ ")
			var scale := _mark(entry, "ESCALA?")
			_l = lines.append("| `%s` | %s | %s | %s | %s | %d | %s | %s | %s |" % [
				String(entry["id"]), String(entry["made"]), String(entry["archive"]),
				String(entry["klass"]), size_text(entry["dims"]), int(entry["tris"]),
				measured if not measured.is_empty() else "—",
				scale if not scale.is_empty() else "OK",
				LICENSES.get(String(entry["made"]), "?")])
	lines.append_array(_pack_summary(all))
	lines.append_array(_scale_diagnosis(all))
	lines.append_array(_feature_table(all))
	return "\n".join(lines) + "\n"


## Resumen por archivo de origen: piezas, propio/descargado, módulo de las
## baldosas (las piezas cuya regla pide `module`) y cuántas llevan `ESCALA?`.
static func _pack_summary(all: Array[Dictionary]) -> PackedStringArray:
	var lines := PackedStringArray()
	var _l := lines.append("")
	_l = lines.append("## Resumen por pack")
	_l = lines.append("")
	_l = lines.append("| pack/archivo | piezas | propio | descargado | módulo de baldosas | "
			+ "con `ESCALA?` |")
	_l = lines.append("|---|---|---|---|---|---|")
	var groups := _by_archive(all)
	for archive: String in groups:
		var members: Array = groups[archive]
		var own := 0
		var flagged := 0
		var sides: Array[float] = []
		for entry: Dictionary in members:
			own += 1 if String(entry["made"]) == "propio" else 0
			flagged += 1 if not _mark(entry, "ESCALA?").is_empty() else 0
			if not bool(scale_rule(entry).get("module", false)):
				continue
			var real: Vector3 = entry["real"]
			for side: float in [real.x, real.y]:
				var module := tile_module(side)
				var value := snappedf(module if module > 0.0 else side, 0.01)
				if not sides.has(value):
					sides.append(value)
		sides.sort()
		var modules := PackedStringArray()
		for side: float in sides:
			var _m := modules.append("%s m" % num(side))
		_l = lines.append("| %s | %d | %d | %d | %s | %d |" % [archive, members.size(), own,
				members.size() - own, ", ".join(modules) if not modules.is_empty() else "—",
				flagged])
	return lines


## Diagnóstico de escala: por cada archivo con edificios, la mediana del lado
## mayor y del alto de sus edificios contra la referencia de
## [constant BUILDING_SIDE_REFERENCE] de lado y [constant FLOOR_HEIGHT_REFERENCE]
## por planta, y el factor que llevaría la mediana del lado al centro del rango
## (redondeado a 0,1), con lo que quedaría de alto y de plantas al aplicarlo.
static func _scale_diagnosis(all: Array[Dictionary]) -> PackedStringArray:
	var side_centre := (BUILDING_SIDE_REFERENCE.x + BUILDING_SIDE_REFERENCE.y) * 0.5
	var floor_centre := (FLOOR_HEIGHT_REFERENCE.x + FLOOR_HEIGHT_REFERENCE.y) * 0.5
	var lines := PackedStringArray()
	var _l := lines.append("")
	_l = lines.append("## Diagnóstico de escala")
	_l = lines.append("")
	_l = lines.append(("Edificios (clase `building`) de cada pack contra una casa de pueblo "
			+ "de %s–%s m de lado y %s–%s m por planta. «Factor» lleva la mediana del lado "
			+ "mayor a %s m; «plantas» es el alto dividido %s m. Ninguna pieza se reescala "
			+ "acá: es una recomendación.") % [num(BUILDING_SIDE_REFERENCE.x),
			num(BUILDING_SIDE_REFERENCE.y), num(FLOOR_HEIGHT_REFERENCE.x),
			num(FLOOR_HEIGHT_REFERENCE.y), num(side_centre), num(floor_centre)])
	_l = lines.append("")
	_l = lines.append("| pack/archivo | edificios | mediana lado mayor | mediana alto | plantas | "
			+ "factor | lado × factor | alto × factor | plantas × factor |")
	_l = lines.append("|---|---|---|---|---|---|---|---|---|")
	var groups := _by_archive(all)
	for archive: String in groups:
		var sides: Array[float] = []
		var heights: Array[float] = []
		for entry: Dictionary in groups[archive]:
			if String(entry["klass"]) != "building":
				continue
			var real: Vector3 = entry["real"]
			sides.append(maxf(real.x, real.y))
			heights.append(real.z)
		if sides.is_empty():
			continue
		var side := median(sides)
		var height := median(heights)
		var factor := snappedf(side_centre / maxf(side, 0.01), 0.1)
		_l = lines.append("| %s | %d | %s m | %s m | %s | ×%s | %s m | %s m | %s |" % [archive,
				sides.size(), num(side), num(height), num(snappedf(height / floor_centre, 0.1)),
				num(factor), num(side * factor), num(height * factor),
				num(snappedf(height * factor / floor_centre, 0.1))])
	return lines


## Rasgos humanos: por cada entrada con `features`, el `root_scale` vigente, la
## puerta y la planta nativas y en metros, y su marca de escala.
static func _feature_table(all: Array[Dictionary]) -> PackedStringArray:
	var lines := PackedStringArray()
	var rows := PackedStringArray()
	for entry: Dictionary in all:
		var native: Dictionary = entry.get("features_native", {})
		if native.is_empty():
			continue
		var measured := human_features(entry)
		var cells := PackedStringArray()
		for feature: String in FEATURE_KEYS:
			var key := FEATURE_KEYS[feature]
			var _n := cells.append(num(float(native[key])) if native.has(key) else "—")
			var _m := cells.append("%s m" % num(float(measured[feature])) if measured.has(feature)
					else "—")
		var scale := _mark(entry, "ESCALA?")
		var _r := rows.append("| `%s` | ×%s | %s | %s | %s | %s | %s |" % [String(entry["id"]),
				num(float(entry.get("root_scale", 1.0))), cells[0], cells[1], cells[2], cells[3],
				scale if not scale.is_empty() else "OK"])
	if rows.is_empty():
		return lines
	var _l := lines.append("")
	_l = lines.append("## Rasgos humanos")
	_l = lines.append("")
	_l = lines.append(("Puerta y planta medidas en la fachada, en unidades nativas del FBX "
			+ "(`features` de `assets/city/pieces_manifest.json`), por el `nodes/root_scale` "
			+ "vigente de su `.fbx.import`. Una puerta real mide %s–%s m y una planta %s–%s m "
			+ "(`SCALE_RULES`).") % [num(DOOR_RANGE[0]), num(DOOR_RANGE[1]), num(FLOOR_RANGE[0]),
			num(FLOOR_RANGE[1])])
	_l = lines.append("")
	_l = lines.append("| id | root_scale | puerta nativa | puerta | planta nativa | planta | escala |")
	_l = lines.append("|---|---|---|---|---|---|---|")
	lines.append_array(rows)
	return lines


## Mediana de [param values] (el promedio de las dos centrales si son pares).
static func median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5


## La marca de [param entry] que empieza con [param prefix], o `""`.
static func _mark(entry: Dictionary, prefix: String) -> String:
	for mark: String in entry.get("marks", PackedStringArray()) as PackedStringArray:
		if mark.begins_with(prefix):
			return mark
	return ""


## Las entradas agrupadas por archivo de origen, con las claves ordenadas.
static func _by_archive(all: Array[Dictionary]) -> Dictionary:
	var groups: Dictionary = {}
	for entry: Dictionary in all:
		var archive := String(entry["archive"])
		if not groups.has(archive):
			groups[archive] = []
		(groups[archive] as Array).append(entry)
	var keys: Array = groups.keys()
	keys.sort()
	var ordered: Dictionary = {}
	for key: Variant in keys:
		ordered[key] = groups[key]
	return ordered


static func _row_members(all: Array[Dictionary], row_name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in all:
		if String(entry["row"]) == row_name:
			found.append(entry)
	return found


# --------------------------------------------------------------------------
# Fuentes
# --------------------------------------------------------------------------

## Las piezas del pueblo que no son `placeholder`. Las medidas de la etiqueta y
## la triangulación vienen del manifiesto, que es lo que el diseño del pueblo
## consume; la caja para repartir la fila, de la escena.
static func _town_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var pieces := (_read_json(TOWN_MANIFEST).get("pieces", {}) as Dictionary)
	var ids: Array = pieces.keys()
	ids.sort()
	for raw: Variant in ids:
		var id := String(raw)
		var entry := pieces[id] as Dictionary
		if bool(entry.get("placeholder", false)):
			continue
		var footprint: Array = entry.get("footprint", [1.0, 1.0])
		var klass := String(entry.get("class", ""))
		var row := "Pueblo/Props"
		match klass:
			"building":
				row = "Pueblo/Edificios"
			"foliage":
				row = "Pueblo/Follaje"
		# La regla de `town_showcase.gd::_lay_row()`: el frente real del pueblo
		# es −X y un cuarto de vuelta lo trae hacia la cámara (+Z); un tramo
		# `+X-run` no tiene frente y corre a lo largo de la fila.
		var yaw := PI * 0.5 if String(entry.get("front", "-X")) == "-X" else 0.0
		found.append(_measured_entry(id, row, String(entry.get("scene", "")),
				String(entry.get("source", "")), klass,
				Vector3(float(footprint[0]), float(footprint[1]), float(entry.get("height", 0.0))),
				int(entry.get("tris", 0)), yaw))
	return found


## Las 13 piezas de ciudad del FreeSample, desde su manifiesto (`base_size` es
## X, Y, Z: ancho, alto y fondo). Los edificios con `features` llevan además
## `features_native` y el `root_scale` vigente de su FBX, para
## [method human_features].
static func _city_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var rows := {"building": "Ciudad/Edificios", "prop": "Ciudad/Props",
			"street": "Ciudad/Viario"}
	for raw: Variant in _read_json(CITY_MANIFEST).get("pieces", []) as Array:
		var entry := raw as Dictionary
		if entry == null:
			continue
		var size: Array = entry.get("base_size", [0.0, 0.0, 0.0])
		var family := String(entry.get("family", ""))
		var made := _measured_entry(String(entry.get("id", "")), String(rows.get(family, "")),
				String(entry.get("scene", "")), String(entry.get("source", "")), family,
				Vector3(float(size[0]), float(size[2]), float(size[1])), -1, 0.0)
		var features: Dictionary = entry.get("features", {})
		if not features.is_empty():
			made["features_native"] = features
			made["root_scale"] = root_scale_of(String(entry.get("model", "")))
		found.append(made)
	return found


## Las seis rocas de borde, en el orden de `ROCK_IDS`.
static func _rock_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var tool: Variant = load(CITY_MESHES_TOOL)
	var rock_dir := String(tool.ROCK_DIR)
	for letter: String in tool.ROCK_IDS:
		var id := "rock_%s" % letter
		found.append(_scene_entry(id, "Rocas", "%s/%s.tscn" % [rock_dir, id],
				"procedural", "rock"))
	return found


## Un enemigo por entrada del catálogo, con su GLB **estático** —la escena de
## juego arranca IA y marcha—, que vive junto a la escena con el mismo nombre.
## Son los únicos jugables: su etiqueta lleva `JUGABLE`.
static func _enemy_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var catalog: Variant = load(ENEMY_CATALOG)
	var table: Dictionary = catalog.ENTRIES
	for raw: Variant in table:
		var id := String(raw)
		var scene := String((table[raw] as Dictionary).get("scene", ""))
		var glb := "%s/%s.glb" % [scene.get_base_dir(), id]
		var entry := _scene_entry(id, "Enemigos", glb, id, "enemy")
		entry["playable"] = true
		found.append(entry)
	return found


## Las vistas previas de los packs de `assets/_raw/` (WP-G2): cada
## `assets/preview/<pack>/pieces_manifest.json`, sin conocer ningún pack. La fila
## sale de `row` de cada pieza, así que un pack nuevo entra sin tocar código:
## basta con que su receta de `voxsplit` escriba el manifiesto en una carpeta
## nueva (y, si trae una fila nueva, una línea en [constant ROWS]).
##
## Son GLB **estáticos** importados sin `import_script`: se instancian como
## escena, con el giro `yaw` (grados) del manifiesto si su frente no es +Z. El
## `source` de cada pieza es el archivo de `_raw/` del que sale. Dentro de la
## carpeta se ordenan por `order` (1 si falta) y después por id; `sort: height`
## (los mechas) lo resuelve la fila ([constant ROWS]).
static func _preview_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var folders := DirAccess.get_directories_at(PREVIEW_DIR)
	folders.sort()
	for folder: String in folders:
		var path := "%s/%s/pieces_manifest.json" % [PREVIEW_DIR, folder]
		if not FileAccess.file_exists(path):
			continue
		var listed: Array[Dictionary] = []
		for raw: Variant in _read_json(path).get("pieces", []) as Array:
			var piece := raw as Dictionary
			if piece == null or bool(piece.get("placeholder", false)):
				continue
			var footprint: Array = piece.get("footprint", [1.0, 1.0])
			var entry := _measured_entry(String(piece.get("id", "")),
					String(piece.get("row", "")), String(piece.get("scene", "")),
					String(piece.get("pack", "")), String(piece.get("class", "")),
					Vector3(float(footprint[0]), float(footprint[1]),
					float(piece.get("height", 0.0))), int(piece.get("tris", 0)),
					deg_to_rad(float(piece.get("yaw", 0.0))))
			entry["preview_only"] = bool(piece.get("preview_only", false))
			entry["note"] = String(piece.get("note", ""))
			entry["order"] = int(piece.get("order", 1))
			entry["own_archive"] = String(piece.get("source", ""))
			listed.append(entry)
		listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var oa := int(a["order"])
			var ob := int(b["order"])
			return oa < ob if oa != ob else String(a["id"]) < String(b["id"]))
		found.append_array(listed)
	return found


static func _drone_entries() -> Array[Dictionary]:
	var entry := _scene_entry(DRONE_GLB.get_file().get_basename(), "Dron", DRONE_GLB,
			"drone", "drone")
	entry["yaw"] = DRONE_YAW
	return [entry]


## Las entradas en el orden de [constant ROWS]; las de filas con `sort: height`,
## de menor a mayor altura real (y por id a igual altura). Las de una fila que
## no está en [constant ROWS] van al final: el check las reporta como faltantes.
static func _in_row_order(found: Array[Dictionary]) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	var named: Dictionary[String, bool] = {}
	for row: Dictionary in ROWS:
		var name := String(row["name"])
		named[name] = true
		var members := _row_members(found, name)
		if String(row.get("sort", "")) == "height":
			members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ha := (a["real"] as Vector3).z
				var hb := (b["real"] as Vector3).z
				return ha < hb if ha != hb else String(a["id"]) < String(b["id"]))
		ordered.append_array(members)
	for entry: Dictionary in found:
		if not named.has(String(entry["row"])):
			ordered.append(entry)
	return ordered


# --------------------------------------------------------------------------
# Medición
# --------------------------------------------------------------------------

## Caja y triángulos de las mallas de [param root], en su espacio local.
static func measure(root: Node) -> Dictionary:
	var box := AABB()
	var first := true
	var tris := 0
	for node: Node in walk(root):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		tris += mesh_tris(mesh_node.mesh)
		var world := relative_transform(mesh_node, root) * mesh_node.mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return {"aabb": box, "tris": tris}


## Mide la escena de [param path] instanciándola fuera del árbol.
static func _measure_scene(path: String) -> Dictionary:
	var node := instance(path)
	if node == null:
		return {"aabb": AABB(), "tris": 0}
	var measured := measure(node)
	node.free()
	return measured


## Transformada de [param node] relativa a [param root], sin pasar por el árbol.
static func relative_transform(node: Node3D, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			result = spatial.transform * result
		current = current.get_parent()
	return result


## Triángulos de [param mesh], contando índices o, sin índices, vértices.
static func mesh_tris(mesh: Mesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null and (indices as PackedInt32Array).size() > 0:
			total += (indices as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


## A×F×H: ancho en X, fondo en Z y alto en Y.
static func _dims(box: AABB) -> Vector3:
	return Vector3(box.size.x, box.size.z, box.size.y)


## Entrada de una pieza con medidas declaradas en un manifiesto ([param declared],
## A×F×H): la escena se mide igual, para repartir la fila con su caja real y para
## la marca `MEDIDA≠`. [param tris] negativo toma los triángulos medidos.
static func _measured_entry(id: String, row: String, path: String, origin: String,
		klass: String, declared: Vector3, tris: int, yaw: float) -> Dictionary:
	var entry := _scene_entry(id, row, path, origin, klass)
	entry["dims"] = declared
	entry["declared"] = true
	entry["yaw"] = yaw
	if tris >= 0:
		entry["tris"] = tris
	return entry


## Entrada de una escena sin medidas declaradas: todo sale de medirla.
static func _scene_entry(id: String, row: String, path: String, origin: String,
		klass: String) -> Dictionary:
	var measured := _measure_scene(path)
	var box: AABB = measured["aabb"]
	return {
		"id": id, "row": row, "path": path, "origin": origin, "klass": klass,
		"dims": _dims(box), "declared": false, "real": _dims(box),
		"tris": int(measured["tris"]), "preview_only": false, "playable": false,
		"yaw": 0.0, "aabb": box, "note": "",
	}


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Instancia la escena de [param path], o `null` si no carga. Con
## [param for_bake] la instancia guarda el estado de su escena
## (`GEN_EDIT_STATE_INSTANCE`), que es lo que `PackedScene.pack()` necesita para
## escribir sólo lo que cambió —el nombre y la transformada— y no una copia de
## cada propiedad.
static func instance(path: String, for_bake: bool = false) -> Node3D:
	if not ResourceLoader.exists(path):
		push_error("asset_gallery: falta '%s'" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("asset_gallery: '%s' no es una escena" % path)
		return null
	var state := PackedScene.GEN_EDIT_STATE_INSTANCE if for_bake \
			else PackedScene.GEN_EDIT_STATE_DISABLED
	return packed.instantiate(state) as Node3D


## [param root] y toda su descendencia, en profundidad.
static func walk(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		found.append_array(found[index].get_children())
		index += 1
	return found


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("asset_gallery: falta '%s'" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var document := parsed as Dictionary
	return document if document != null else {}
