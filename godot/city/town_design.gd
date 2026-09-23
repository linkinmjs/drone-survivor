## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## El **diseño** del pueblo: lo que una persona escribe a mano y el código
## resuelve (plan P2c §2).
##
## Hasta WP-T2 el trazado lo sorteaba una semilla y [TownPlanner] lo verificaba
## después. Eso da pueblos **plausibles** y nunca un pueblo **bueno**: la semilla
## no sabe que la escuela va enfrente de la plaza, que la estación de servicio es
## el «hola» de la entrada ni que una sola casa tiene que tener la puerta
## abierta. Desde acá el trazado es un archivo de texto —`city/designs/*.json`—
## que se lee, se discute y se versiona con `diff`, y el código pasa a hacer lo
## único que hace mejor que una persona: resolver la geometría exacta.
##
## ## Qué valida y por qué es ruidoso
##
## [method load_json] no es un cargador tolerante. Un diseño con una calle que no
## termina en ningún lado, una manzana cóncava o una casa con `t = 1,4` **no se
## carga**: devuelve `null` y deja en [member problems] un mensaje por
## incumplimiento, cada uno con **el número de línea del JSON**, que es lo que
## convierte un error de diseño en una corrección de treinta segundos en vez de
## en una tarde de bisección. El archivo admite comentarios `//` y `/* */`: se
## reemplazan por espacios **antes** de parsear, así que las líneas que reporta
## el error son las líneas reales del archivo.
##
## Las piezas son la excepción: una pieza que la tabla no conoce —o que conoce
## pero todavía no existe en disco, como el tanque de agua que llega en WP-D1— no
## es un error de diseño sino trabajo pendiente. Queda anotada en
## [member warnings] y el resolvedor **la omite con un aviso**, en vez de sembrar
## otra pieza cualquiera en su lugar: un hueco se ve; una casa donde tenía que ir
## un silo, no.
##
## ## La identidad del diseño
##
## [method design_hash] mezcla el JSON **normalizado** —claves ordenadas,
## flotantes a cuatro decimales— y no el texto crudo: reindentar el archivo o
## mover una clave de sitio no cambia el pueblo, y por lo tanto no puede cambiar
## la firma del plano. Cambiar un número, sí.
@tool
class_name TownDesign extends Resource

## Versión del esquema que entiende este archivo.
const SCHEMA_VERSION: int = 1

## Clase de cada pieza conocida.
##
## `building` se siembra como [Building] (o como pieza cruda si es de caserío),
## `prop` y `rock` como decorado, y `pending` es una pieza que el diseño puede
## nombrar pero que todavía no existe en disco: llega con la ingesta de packs de
## WP-D1. El resolvedor omite las `pending` con un aviso.
const PIECE_CLASS: Dictionary[StringName, StringName] = {
	&"house_a": &"building", &"house_a_b": &"building",
	&"house_b": &"building", &"house_b_b": &"building",
	&"house_c": &"building", &"house_c_b": &"building",
	&"house_d": &"building", &"house_d_b": &"building",
	&"shed": &"building", &"shed_b": &"building",
	&"block_mid": &"building", &"tower_b": &"building", &"block_low_c": &"building",
	&"overgrowth_a": &"prop", &"overgrowth_b": &"prop",
	&"trash_0": &"prop", &"trash_1": &"prop", &"trash_2": &"prop",
	&"trash_3": &"prop", &"trash_4": &"prop",
	&"barrel_a": &"prop", &"barrel_b": &"prop",
	&"rock_a": &"rock", &"rock_b": &"rock", &"rock_c": &"rock",
	&"rock_d": &"rock", &"rock_e": &"rock", &"rock_f": &"rock",
	# Pendientes de WP-D1 (plan P2c §4): procedurales propios y packs nuevos.
	&"gas_station": &"pending", &"water_tower": &"pending", &"silo": &"pending",
	&"chapel": &"pending", &"field_shed": &"pending", &"bus_stop": &"pending",
	&"lamp_post": &"pending", &"school_chair": &"pending", &"bench": &"pending",
	&"lantern": &"pending", &"flag_mast": &"pending", &"monument": &"pending",
	&"awning_orange": &"pending", &"welcome_sign": &"pending",
	&"road_sign_narrow": &"pending", &"road_sign_speed": &"pending",
	&"fence_post": &"pending", &"fence_wire_6m": &"pending",
	&"fence_picket_3m": &"pending", &"bridge_deck": &"pending",
	&"crate": &"pending", &"barrel_c": &"pending",
	&"car_a": &"pending", &"car_b": &"pending", &"pickup": &"pending",
	&"truck": &"pending",
	&"tree_xl": &"pending", &"tree_large": &"pending", &"tree_medium": &"pending",
	&"tree_small": &"pending", &"tree_stump": &"pending",
	&"bush_a": &"pending", &"bush_b": &"pending", &"grass_a": &"pending",
	&"flowers_a": &"pending", &"corn_a": &"pending", &"corn_b": &"pending",
}

## Manifiesto de piezas de WP-D1.
##
## Es la tabla que el encargo de arte escribe cuando hornea las piezas nuevas:
## `{nombre: {class, scene, footprint, height, origin, front, placeholder,
## tris}}`. Mientras el archivo no exista, [method piece_class] contesta con
## [constant PIECE_CLASS] y las diecinueve piezas nuevas siguen siendo
## `pending`; en cuanto aparece, la **misma** llamada empieza a decir `prop`,
## `building` o `foliage` sin tocar una línea de este archivo.
##
## La fusión se hace acá y no copiando el manifiesto a [constant PIECE_CLASS]
## porque una constante no se puede fusionar en ejecución y un diccionario
## estático mutable se desincroniza: lo único que hay es **una** pregunta.
const MANIFEST_PATH: String = "res://assets/town/pieces_manifest.json"

## Clases que el manifiesto puede declarar y que el resolvedor sabe sembrar.
##
## `foliage` es la clase nueva de WP-D1: malla sin colisión que se siembra por
## [MultiMesh] y nunca como [Building]. Se acepta también en el sitio de un
## `prop`, porque un árbol de patio es un prop que resulta ser follaje.
const PIECE_CLASSES: Array[StringName] = [
	&"building", &"prop", &"rock", &"foliage", &"pending",
]

static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false


## El manifiesto de WP-D1, o un diccionario vacío si todavía no está en disco.
static func manifest() -> Dictionary:
	if _manifest_loaded:
		return _manifest
	_manifest_loaded = true
	_manifest = {}
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _manifest
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("TownDesign: '%s' existe y no se puede abrir." % MANIFEST_PATH)
		return _manifest
	var json := JSON.new()
	var err := json.parse(_strip_comments(file.get_as_text()))
	file.close()
	if err != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("TownDesign: '%s' no parsea como objeto JSON." % MANIFEST_PATH)
		return _manifest
	# El manifiesto de WP-D1 envuelve la tabla en `pieces` y le pone al lado un
	# `comment` y una `version`. Se aceptan las dos formas —envuelta y plana—
	# porque la que importa es la tabla y no dónde está: preguntar por `pieces` y
	# caer a la raíz cuesta tres líneas y ahorra un acoplamiento de formato.
	var data: Dictionary = json.data
	var pieces: Variant = data.get("pieces", null)
	_manifest = pieces if typeof(pieces) == TYPE_DICTIONARY else data
	return _manifest


## Verdadero si el manifiesto de WP-D1 ya está en disco. Lo preguntan los checks
## para saber si una pieza que falta es trabajo pendiente o una regresión.
static func manifest_ready() -> bool:
	return not manifest().is_empty()


## Olvida el manifiesto cargado. Sólo para las pruebas que lo escriben a mano.
static func forget_manifest() -> void:
	_manifest = {}
	_manifest_loaded = false


## Clase de [param piece]: la que dice el manifiesto si existe, la de
## [constant PIECE_CLASS] si no, y `&""` si la pieza no la conoce nadie.
static func piece_class(piece: StringName) -> StringName:
	var entry: Variant = manifest().get(String(piece), null)
	if typeof(entry) == TYPE_DICTIONARY:
		var declared := StringName(String((entry as Dictionary).get("class", "")))
		if PIECE_CLASSES.has(declared):
			return declared
	return StringName(PIECE_CLASS.get(piece, &""))


## La escena de [param piece] según el manifiesto, o `""`.
static func piece_scene(piece: StringName) -> String:
	var entry: Variant = manifest().get(String(piece), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return String((entry as Dictionary).get("scene", ""))


## Hacia dónde mira la pieza [param piece] en su espacio local: `-X` para las
## piezas del pueblo y `-Z` para las de ciudad.
##
## El giro que el diseño declara es el del **mundo**: «esta parada mira a la
## ruta». Cuál de los ejes locales de la pieza es su frente es dato de la pieza,
## y por eso vive en el manifiesto y no en el diseño. Sin esto, la mitad de los
## props le mostrarían el costado a la calle, que es exactamente lo que
## [constant CityGrid.TOWN_PIECE_META] resuelve para los edificios.
static func piece_front(piece: StringName) -> StringName:
	var entry: Variant = manifest().get(String(piece), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return &"-Z"
	return StringName(String((entry as Dictionary).get("front", "-Z")))


## Alto nominal de [param piece] según el manifiesto, o `0`.
static func piece_height(piece: StringName) -> float:
	var entry: Variant = manifest().get(String(piece), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return 0.0
	return float((entry as Dictionary).get("height", 0.0))


## Verdadero si [param piece] se puede sembrar como decorado: prop, follaje o
## roca. Es la pregunta que hacen las arboledas, los cercos y los props.
static func piece_is_decor(piece: StringName) -> bool:
	var kind := piece_class(piece)
	return kind == &"prop" or kind == &"foliage" or kind == &"rock"

## Qué puede ser un [code]kind[/code] de calle. El orden fija el entero que va a
## `TownPlan.street_kind`.
const STREET_KINDS: Array[StringName] = [&"route", &"street", &"lane", &"access"]

## Qué puede cerrar el cabo de una calle. `none` quiere decir que ese extremo no
## es un cabo: se muere en un nodo o se va del campo.
const CLOSURE_KINDS: Array[StringName] = [&"none", &"gate", &"culvert", &"fence"]

## Roles de POI del plan P2c §4. Los tres primeros tienen pieza hoy; los demás
## se validan pero se siembran cuando WP-D1 traiga la pieza.
const POI_ROLES: Array[StringName] = [
	&"school", &"medium", &"landmark",
	&"gas_station", &"water_tower", &"silo", &"chapel", &"shed",
]

## Estados en los que puede nacer una casa (`docs/10` §3).
const HOUSE_STATES: Array[StringName] = [&"intact", &"damaged", &"ruined"]

## Cómo se puede cercar un frente.
const FENCE_KINDS: Array[StringName] = [&"", &"picket", &"wire", &"hedge", &"wall"]

## Qué clases de cerco de **línea** sabe sembrar el resolvedor (WP-D2).
##
## Son menos que [constant FENCE_KINDS] a propósito: el cerco del frente de una
## casa es un adorno que la pieza puede o no traer, pero un cerco de línea es
## geometría repetida a lo largo de una polilínea y hace falta saber de cuántos
## metros es cada tramo. Hoy hay dos piezas y por lo tanto dos clases.
const FENCE_LINE_KINDS: Array[StringName] = [&"wire", &"picket"]

## Largo de un tramo de cada clase de cerco de línea, en metros.
##
## Son los largos **reales** de las piezas de WP-D1: el alambrado mide 6,00 m y
## el cerco de tabla **3,60** —tres módulos de 1,2— y no 3,00, que es lo que el
## encargo suponía. El número vive acá y no en el resolvedor porque es un dato de
## la pieza: si mañana el cerco de tabla pasa a cuatro módulos, cambia esta línea
## y los tramos se recalculan solos.
const FENCE_SPAN: Dictionary[StringName, float] = {&"wire": 6.0, &"picket": 3.6}

## Pieza de cada clase de cerco de línea.
const FENCE_PIECE: Dictionary[StringName, StringName] = {
	&"wire": &"fence_wire_6m", &"picket": &"fence_picket_3m",
}

## Qué puede declarar un marcador del diseño.
##
## Un marcador **reemplaza** al que el resolvedor sortearía de ese `kind`: es la
## puerta por la que el diseño se mete en una decisión que hasta P2b era
## automática, sin tener que declarar las cuatro. Las pilas son el caso que lo
## justifica: la gramática de `docs/17` §4 dice «toldo naranja = pila», y eso no
## lo puede cumplir un sorteo sobre los cruces del grafo.
const MARKER_KINDS: Array[StringName] = [&"battery", &"enemy", &"drone", &"camera"]

## A cuántos metros de un toldo naranja o de una estación de servicio tiene que
## caer un marcador `battery` declarado (`docs/17` §4, fila «toldo = pila»).
const AWNING_REACH: float = 4.0

## Las piezas que cumplen la gramática «acá hay una pila».
const AWNING_PIECES: Array[StringName] = [&"awning_orange", &"gas_station", &"bus_stop"]

## Holguras por omisión de una arboleda, en metros: a la franja de calle, al
## borde de manzana, a la huella de un edificio y al eje de la ruta.
const GROVE_CLEAR: Dictionary[StringName, float] = {
	&"streets": 6.0, &"blocks": 4.0, &"houses": 3.0, &"route": 12.0,
}

## Tolerancia con la que un nodo declarado tiene que caer sobre el eje que dice
## tocar, en metros.
const ON_AXIS_TOLERANCE: float = 0.25

# --------------------------------------------------------------------------
# Datos
# --------------------------------------------------------------------------

## De dónde salió este diseño. Encabeza cada mensaje de [member problems].
@export var source_path: String = ""

## Incumplimientos encontrados al cargar, con archivo y línea. Vacío quiere decir
## diseño válido.
@export var problems: PackedStringArray = PackedStringArray()

## Avisos: piezas que la tabla **no conoce**. No impiden cargar, pero son una
## regresión: alguien escribió un nombre que no existe.
@export var warnings: PackedStringArray = PackedStringArray()

## Piezas nombradas por el diseño que todavía no existen en disco (`pending`).
##
## Van aparte de [member warnings] porque no son lo mismo: un nombre
## desconocido es un error de tipeo y una pieza `pending` es **trabajo de
## WP-D1**. El check exige que [member warnings] esté vacío y se limita a
## **contar** éstas, que es lo que permite tener el diseño bueno escrito y
## verificado mientras el arte llega.
@export var pending: PackedStringArray = PackedStringArray()

## El JSON ya parseado y normalizado a los tipos del esquema.
var _data: Dictionary = {}

## Índice de identificador de nodo a posición en [member _nodes].
var _node_index: Dictionary[StringName, int] = {}

## Nodos, en orden de declaración: `{id: StringName, pos: Vector2}`.
var _nodes: Array[Dictionary] = []

## Calles **sin la ruta**, en orden de declaración. La ruta es la calle 0 y vive
## aparte porque es una polilínea y no un segmento entre dos nodos.
var _streets: Array[Dictionary] = []

## Índice de identificador de calle a índice de plano (`0` es la ruta).
var _street_index: Dictionary[StringName, int] = {}

## Manzanas, con los nodos ya resueltos a índices.
var _blocks: Array[Dictionary] = []

## Por qué nodos pasa cada calle, en orden a lo largo de su eje. El índice es el
## de plano: `0` es la ruta. Ver [method _build_chains].
var _chains: Array[PackedInt32Array] = []

## Por qué calles pasa cada nodo. Es la traspuesta de [member _chains] y lo que
## permite saber si una punta de calle es un cabo o una T.
var _node_streets: Array[PackedInt32Array] = []

## Las líneas del archivo tal cual, para poder decir en cuál está cada problema.
var _lines: PackedStringArray = PackedStringArray()

var _hash_cache: int = 0
var _hash_done: bool = false


# --------------------------------------------------------------------------
# Carga
# --------------------------------------------------------------------------

## Carga y valida el diseño de [param path].
##
## Devuelve `null` si el archivo no existe, no parsea o no pasa la validación; en
## los dos últimos casos el diseño a medio cargar queda accesible por
## [method last_failure] para que el check pueda leer [member problems]. Los
## mensajes se emiten además por `push_error`, así que una corrida de
## `build_town` que cargue un diseño roto lo dice en el log.
static func load_json(path: String) -> TownDesign:
	_last_failure = null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var design := TownDesign.new()
		design.source_path = path
		design._fail(0, "no se puede abrir el diseño: %s"
				% error_string(FileAccess.get_open_error()))
		_last_failure = design
		design._report()
		return null
	var text := file.get_as_text()
	file.close()
	return load_text(text, path)


## Igual que [method load_json] pero sobre un texto ya leído. Sirve para validar
## un diseño que todavía no está en disco.
static func load_text(text: String, source: String = "<texto>") -> TownDesign:
	var json := JSON.new()
	var err := json.parse(_strip_comments(text))
	if err != OK:
		var design := TownDesign.new()
		design.source_path = source
		design._lines = text.split("\n")
		design._fail(json.get_error_line(), "JSON inválido: %s" % json.get_error_message())
		_last_failure = design
		design._report()
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		var design := TownDesign.new()
		design.source_path = source
		design._lines = text.split("\n")
		design._fail(1, "el diseño tiene que ser un objeto JSON")
		_last_failure = design
		design._report()
		return null
	return from_data(json.data, source, text.split("\n"))


## Valida un diseño que ya está **en memoria**, sin pasar por disco.
##
## Es lo que permite a `tools/town_plan_check.gd` recolorear una casa, mover otra
## y volver a resolver para comprobar que un cambio local toca una sola línea de
## la firma: escribir un archivo temporal por cada variación sería lento y
## dejaría basura en `user://`.
static func from_data(data: Dictionary, source: String = "<memoria>",
		lines: PackedStringArray = PackedStringArray()) -> TownDesign:
	_last_failure = null
	var design := TownDesign.new()
	design.source_path = source
	design.resource_name = source.get_file().get_basename()
	design._lines = lines
	design._data = data
	design._validate()
	design._report()
	if not design.problems.is_empty():
		_last_failure = design
		return null
	return design


## Copia profunda del JSON parseado, para poder variarlo y volver a validarlo con
## [method from_data].
func raw_data() -> Dictionary:
	return _data.duplicate(true)


## El último diseño que la carga rechazó, con sus [member problems] intactos. Lo
## usan las pruebas negativas de `tools/town_plan_check.gd`.
static func last_failure() -> TownDesign:
	return _last_failure


static var _last_failure: TownDesign = null

## Si los mensajes de carga salen por el log del motor. Ver [method _report].
static var report_to_log: bool = true


## Reemplaza los comentarios `//` y `/* */` por espacios **conservando los saltos
## de línea**, para que `JSON.get_error_line()` siga apuntando a la línea real.
static func _strip_comments(text: String) -> String:
	var out := PackedStringArray()
	var length := text.length()
	var index := 0
	var in_string := false
	while index < length:
		var c := text[index]
		if in_string:
			out.append(c)
			if c == "\\" and index + 1 < length:
				out.append(text[index + 1])
				index += 2
				continue
			if c == "\"":
				in_string = false
			index += 1
			continue
		if c == "\"":
			in_string = true
			out.append(c)
			index += 1
			continue
		if c == "/" and index + 1 < length and text[index + 1] == "/":
			while index < length and text[index] != "\n":
				out.append(" ")
				index += 1
			continue
		if c == "/" and index + 1 < length and text[index + 1] == "*":
			while index < length:
				if text[index] == "*" and index + 1 < length and text[index + 1] == "/":
					out.append("  ")
					index += 2
					break
				out.append("\n" if text[index] == "\n" else " ")
				index += 1
			continue
		out.append(c)
		index += 1
	return "".join(out)


# --------------------------------------------------------------------------
# Validación
# --------------------------------------------------------------------------

## Recorre el esquema entero. No corta en el primer fallo: un diseño con cuatro
## errores tiene que enseñar los cuatro de una sola corrida.
func _validate() -> void:
	var version := int(_number("version", 0.0))
	if version != SCHEMA_VERSION:
		_fail(_line_of("\"version\""),
				"el diseño dice versión %d y este cargador entiende la %d"
				% [version, SCHEMA_VERSION])

	for key: String in ["play_radius", "block_radius", "field_size"]:
		if _number(key, -1.0) <= 0.0:
			_fail(_line_of("\"%s\"" % key), "'%s' tiene que ser un número positivo" % key)

	_validate_nodes()
	_validate_route()
	_validate_streets()
	_validate_blocks()
	_validate_poi()
	_validate_scatter()
	_validate_markers()
	_validate_terrain()


func _validate_nodes() -> void:
	_nodes = []
	_node_index = {}
	var raw: Array = _array("nodes")
	if raw.is_empty():
		_fail(_line_of("\"nodes\""), "el diseño no declara ni un nodo")
		return
	for index: int in raw.size():
		if typeof(raw[index]) != TYPE_DICTIONARY:
			_fail(_line_of("\"nodes\""), "el nodo %d no es un objeto" % index)
			continue
		var entry: Dictionary = raw[index]
		var id := StringName(String(entry.get("id", "")))
		var line := _line_of("\"%s\"" % id) if id != &"" else _line_of("\"nodes\"")
		if id == &"":
			_fail(_line_of("\"nodes\""), "el nodo %d no tiene 'id'" % index)
			continue
		if _node_index.has(id):
			_fail(line, "el nodo '%s' está declarado dos veces" % id)
			continue
		var position: Variant = to_vector2(entry.get("pos", null))
		if position == null:
			_fail(line, "el nodo '%s' no tiene una 'pos' de dos números" % id)
			continue
		_node_index[id] = _nodes.size()
		_nodes.append({"id": id, "pos": position})


func _validate_route() -> void:
	var route := _dictionary("route")
	var line := _line_of("\"route\"")
	if route.is_empty():
		_fail(line, "el diseño no declara la ruta")
		return
	var vertices := to_vector2_list(route.get("vertices", null))
	if vertices.size() < 2:
		_fail(line, "la ruta tiene %d vértices y necesita al menos dos" % vertices.size())
		return
	if float(route.get("width", 0.0)) <= 0.0:
		_fail(line, "la ruta no declara un 'width' positivo")
	if float(route.get("shoulder", -1.0)) < 0.0:
		_fail(line, "la ruta no declara un 'shoulder' de cero o más")

	# Los nodos de la ruta, en el orden en que la ruta los toca. Que estén **en
	# orden** no es cosmético: el resolvedor y `RoadMesh` recorren la cinta de
	# principio a fin y un nodo fuera de orden partiría la calzada al revés.
	var travelled := -INF
	for id_raw: Variant in route.get("nodes", []):
		var id := StringName(String(id_raw))
		var node_line := _line_of("\"%s\"" % id)
		if not _node_index.has(id):
			_fail(node_line, "la ruta dice pasar por el nodo '%s', que no existe" % id)
			continue
		var point: Vector2 = _nodes[_node_index[id]]["pos"]
		var hit := _closest_on_polyline(vertices, point)
		if float(hit["distance"]) > ON_AXIS_TOLERANCE:
			_fail(node_line, "el nodo '%s' de la ruta está a %.3f m de su eje (tope %.2f)"
					% [id, float(hit["distance"]), ON_AXIS_TOLERANCE])
		var along := float(hit["along"])
		if along <= travelled:
			_fail(node_line, "el nodo '%s' de la ruta va fuera de orden (%.1f m después de %.1f m)"
					% [id, along, travelled])
		travelled = along


func _validate_streets() -> void:
	_streets = []
	_street_index = {&"route": 0}
	var raw: Array = _array("streets")
	for index: int in raw.size():
		if typeof(raw[index]) != TYPE_DICTIONARY:
			_fail(_line_of("\"streets\""), "la calle %d no es un objeto" % index)
			continue
		var entry: Dictionary = raw[index]
		var id := StringName(String(entry.get("id", "")))
		var line := _line_of("\"id\": \"%s\"" % id) if id != &"" else _line_of("\"streets\"")
		if id == &"":
			_fail(_line_of("\"streets\""), "la calle %d no tiene 'id'" % index)
			continue
		if _street_index.has(id):
			_fail(line, "la calle '%s' está declarada dos veces ('route' está reservado)" % id)
			continue

		var a := StringName(String(entry.get("a", "")))
		var b := StringName(String(entry.get("b", "")))
		var ok := true
		for end_id: StringName in [a, b]:
			if not _node_index.has(end_id):
				_fail(line, "la calle '%s' termina en el nodo '%s', que no existe" % [id, end_id])
				ok = false
		if not ok:
			continue
		if a == b:
			_fail(line, "la calle '%s' empieza y termina en el mismo nodo '%s'" % [id, a])
			continue

		var width := float(entry.get("width", 0.0))
		var sidewalk := float(entry.get("sidewalk", -1.0))
		if width <= 0.0:
			_fail(line, "la calle '%s' no declara un 'width' positivo" % id)
		if sidewalk < 0.0:
			_fail(line, "la calle '%s' no declara una 'sidewalk' de cero o más" % id)
		var kind := StringName(String(entry.get("kind", "street")))
		if not STREET_KINDS.has(kind):
			_fail(line, "la calle '%s' es de tipo '%s', que no existe (%s)"
					% [id, kind, ", ".join(_names(STREET_KINDS))])
		for suffix: String in ["a", "b"]:
			var stub := float(entry.get("stub_%s" % suffix, 0.0))
			if stub < 0.0:
				_fail(line, "la calle '%s' declara un cabo '%s' negativo (%.2f m)"
						% [id, suffix, stub])
			var closure := StringName(String(entry.get("closure_%s" % suffix, "none")))
			if not CLOSURE_KINDS.has(closure):
				_fail(line, "la calle '%s' cierra el lado '%s' con '%s', que no existe (%s)"
						% [id, suffix, closure, ", ".join(_names(CLOSURE_KINDS))])

		var index_a: int = _node_index[a]
		var index_b: int = _node_index[b]
		_street_index[id] = _streets.size() + 1
		_streets.append({
			"id": id,
			"a": index_a,
			"b": index_b,
			"width": width,
			"sidewalk": maxf(sidewalk, 0.0),
			"kind": kind,
			"stub_a": maxf(float(entry.get("stub_a", 0.0)), 0.0),
			"stub_b": maxf(float(entry.get("stub_b", 0.0)), 0.0),
			"closure_a": StringName(String(entry.get("closure_a", "none"))),
			"closure_b": StringName(String(entry.get("closure_b", "none"))),
			"line": line,
		})

	_build_chains()
	_validate_street_ends()


## La **cadena de nodos** de cada calle: por qué nodos pasa, en orden a lo largo
## de su eje. La calle `0` es la ruta y su cadena es la que declara.
##
## Una calle **no** se parte en el nodo por el que pasa: la transversal `c3` es
## una sola calle de punta a punta y toca tres nodos. Es lo que hace que el
## viario horneado no tenga una costura en cada cruce, y por eso «qué calle une
## estos dos nodos» se responde por **adyacencia en la cadena** y no por los dos
## extremos declarados.
func _build_chains() -> void:
	_chains = []
	_node_streets = []
	for _node: int in _nodes.size():
		_node_streets.append(PackedInt32Array())
	_chains.append(route_nodes())
	for street: Dictionary in _streets:
		var a: Vector2 = _nodes[int(street["a"])]["pos"]
		var b: Vector2 = _nodes[int(street["b"])]["pos"]
		var direction := (b - a).normalized()
		var from := a - direction * float(street["stub_a"])
		var span := from.distance_to(b + direction * float(street["stub_b"]))
		var found: Array[Dictionary] = []
		for node: int in _nodes.size():
			var point: Vector2 = _nodes[node]["pos"]
			var along := (point - from).dot(direction)
			if along < -ON_AXIS_TOLERANCE or along > span + ON_AXIS_TOLERANCE:
				continue
			if point.distance_to(from + direction * along) > ON_AXIS_TOLERANCE:
				continue
			found.append({"node": node, "along": along})
		found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return float(x["along"]) < float(y["along"]))
		var chain := PackedInt32Array()
		for entry: Dictionary in found:
			chain.append(int(entry["node"]))
		_chains.append(chain)
	for index: int in _chains.size():
		for node: int in _chains[index]:
			if node >= 0 and node < _node_streets.size():
				_node_streets[node].append(index)


## Un extremo libre —cabo con largo, o nodo al que no llega ninguna otra
## calle— necesita cierre.
##
## Es la regla que arregla los catorce cabos sueltos de P2b: una calle que se
## corta en el campo sin tranquera, alcantarilla ni cerco se lee como una calle
## inacabada, que es exactamente lo que era.
func _validate_street_ends() -> void:
	for index: int in _streets.size():
		var street := _streets[index]
		for suffix: String in ["a", "b"]:
			var node: int = street[suffix]
			var stub := float(street["stub_%s" % suffix])
			var closure: StringName = street["closure_%s" % suffix]
			var alone := node < 0 or node >= _node_streets.size() \
					or _node_streets[node].size() < 2
			var free_end := stub > 0.0 or alone
			if free_end and closure == &"none":
				_fail(int(street["line"]),
						"la calle '%s' muere en el lado '%s' sin nodo ni cierre"
						% [street["id"], suffix])
			if not free_end and closure != &"none":
				_fail(int(street["line"]),
						"la calle '%s' cierra el lado '%s' con '%s' y ahí no hay cabo: hay un cruce"
						% [street["id"], suffix, closure])


func _validate_blocks() -> void:
	_blocks = []
	var raw: Array = _array("blocks")
	for index: int in raw.size():
		if typeof(raw[index]) != TYPE_DICTIONARY:
			_fail(_line_of("\"blocks\""), "la manzana %d no es un objeto" % index)
			continue
		var entry: Dictionary = raw[index]
		var id := StringName(String(entry.get("id", "")))
		var line := _line_of("\"id\": \"%s\"" % id) if id != &"" else _line_of("\"blocks\"")
		if id == &"":
			_fail(_line_of("\"blocks\""), "la manzana %d no tiene 'id'" % index)
			continue

		var ids: Array = entry.get("nodes", [])
		var slots := PackedInt32Array()
		var ring := PackedVector2Array()
		var ok := true
		for node_raw: Variant in ids:
			var node_id := StringName(String(node_raw))
			if not _node_index.has(node_id):
				_fail(line, "la manzana '%s' nombra el nodo '%s', que no existe" % [id, node_id])
				ok = false
				continue
			var slot: int = _node_index[node_id]
			if slots.has(slot):
				_fail(line, "la manzana '%s' repite el nodo '%s'" % [id, node_id])
				ok = false
				continue
			slots.append(slot)
			ring.append(_nodes[slot]["pos"])
		if not ok:
			continue
		if slots.size() < 3:
			_fail(line, "la manzana '%s' tiene %d nodos y necesita al menos tres"
					% [id, slots.size()])
			continue
		if not TownPlan.polygon_is_convex(ring):
			_fail(line, "la manzana '%s' no es convexa" % id)
			continue

		var datum: Variant = entry.get("datum", "auto")
		if typeof(datum) == TYPE_STRING and String(datum) != "auto":
			_fail(line, "la manzana '%s' declara 'datum' = '%s': sólo vale \"auto\" o un número"
					% [id, datum])
		_blocks.append({
			"id": id,
			"nodes": slots,
			"ring": ring,
			"datum": datum,
			"pad": StringName(String(entry.get("pad", "garden"))),
			"houses": _validate_houses(id, slots, entry.get("houses", []), line),
			"line": line,
		})


## Las casas de una manzana, ya con la calle resuelta a índice de plano.
func _validate_houses(block_id: StringName, slots: PackedInt32Array, raw: Variant,
		block_line: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		_fail(block_line, "las casas de la manzana '%s' no son una lista" % block_id)
		return found
	var houses: Array = raw
	var line := block_line
	for index: int in houses.size():
		line = _line_of("\"front\"", line + 1)
		if typeof(houses[index]) != TYPE_DICTIONARY:
			_fail(block_line, "la casa %d de la manzana '%s' no es un objeto" % [index, block_id])
			continue
		var entry: Dictionary = houses[index]
		var front := StringName(String(entry.get("front", "")))
		if not _street_index.has(front):
			_fail(line, "la casa %d de '%s' da a la calle '%s', que no existe"
					% [index, block_id, front])
			continue
		var street: int = _street_index[front]
		if _block_edge_of(slots, street) < 0:
			_fail(line, "la casa %d de '%s' da a la calle '%s', que no toca esa manzana"
					% [index, block_id, front])
			continue
		var t := float(entry.get("t", -1.0))
		if t < 0.0 or t > 1.0:
			_fail(line, "la casa %d de '%s' cae en t = %.3f, fuera de [0, 1]"
					% [index, block_id, t])
			continue
		var state := StringName(String(entry.get("state", "intact")))
		if not HOUSE_STATES.has(state):
			_fail(line, "la casa %d de '%s' nace en estado '%s', que no existe (%s)"
					% [index, block_id, state, ", ".join(_names(HOUSE_STATES))])
		var fence := StringName(String(entry.get("fence", "")))
		if not FENCE_KINDS.has(fence):
			_fail(line, "la casa %d de '%s' lleva un cerco '%s', que no existe"
					% [index, block_id, fence])
		var piece := StringName(String(entry.get("piece", "")))
		_check_piece(piece, line, "la casa %d de '%s'" % [index, block_id])
		var tree := StringName(String(entry.get("tree", "")))
		if tree != &"":
			_check_piece(tree, line, "el árbol de la casa %d de '%s'" % [index, block_id])
		found.append({
			"front": street,
			"t": t,
			"piece": piece,
			"variant": int(entry.get("variant", 0)),
			"color": int(entry.get("color", 0)),
			"state": state,
			"garden": bool(entry.get("garden", false)),
			"tree": tree,
			"door_open": bool(entry.get("door_open", false)),
			"fence": fence,
			"width": float(entry.get("width", 0.0)),
			"height_scale": float(entry.get("height_scale", 0.0)),
			"line": line,
		})
	return found


func _validate_poi() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for index: int in _array("poi").size():
		var entry: Variant = _array("poi")[index]
		if typeof(entry) != TYPE_DICTIONARY:
			_fail(_line_of("\"poi\""), "el POI %d no es un objeto" % index)
			continue
		var data: Dictionary = entry
		var id := StringName(String(data.get("id", "")))
		var line := _line_of("\"id\": \"%s\"" % id) if id != &"" else _line_of("\"poi\"")
		if id == &"":
			_fail(_line_of("\"poi\""), "el POI %d no tiene 'id'" % index)
			continue
		if seen.has(id):
			_fail(line, "el POI '%s' está declarado dos veces" % id)
			continue
		seen[id] = true
		var role := StringName(String(data.get("role", "")))
		if not POI_ROLES.has(role):
			_fail(line, "el POI '%s' tiene el rol '%s', que no existe (%s)"
					% [id, role, ", ".join(_names(POI_ROLES))])
		if to_vector2(data.get("pos", null)) == null:
			_fail(line, "el POI '%s' no tiene una 'pos' de dos números" % id)
		var footprint: Variant = to_vector2(data.get("footprint", null))
		if footprint == null:
			_fail(line, "el POI '%s' no declara 'footprint'" % id)
		else:
			var size: Vector2 = footprint
			if size.x <= 0.0 or size.y <= 0.0:
				_fail(line, "el POI '%s' tiene una huella de %.1f × %.1f m" % [id, size.x, size.y])
		_check_piece(StringName(String(data.get("piece", ""))), line, "el POI '%s'" % id)
		# `block` dice **en qué manzana** va el POI. Un POI sin la clave se sienta
		# donde caiga (compatibilidad con el andamio); con `null` declara que es
		# un lote rural fuera de todas las manzanas —el silo— y toma su cota del
		# terreno; con un identificador se exige que esa manzana exista.
		if data.has("block") and data["block"] != null:
			var block_id := StringName(String(data["block"]))
			if block_index(block_id) < 0:
				_fail(line, "el POI '%s' dice estar en la manzana '%s', que no existe"
						% [id, block_id])


## Los marcadores declarados, que reemplazan a los sorteados de su `kind`.
func _validate_markers() -> void:
	for index: int in _array("markers").size():
		var entry: Variant = _array("markers")[index]
		var line := _line_of("\"markers\"")
		if typeof(entry) != TYPE_DICTIONARY:
			_fail(line, "el marcador %d no es un objeto" % index)
			continue
		var data: Dictionary = entry
		var kind := StringName(String(data.get("kind", "")))
		if not MARKER_KINDS.has(kind):
			_fail(line, "el marcador %d es de clase '%s', que no existe (%s)"
					% [index, kind, ", ".join(_names(MARKER_KINDS))])
		if to_vector2(data.get("pos", null)) == null:
			_fail(line, "el marcador %d no tiene una 'pos' de dos números" % index)


## Rocas, caseríos, props, arboledas, cercos, arroyo, puente y plaza.
func _validate_scatter() -> void:
	for key: String in ["rocks", "props", "decor_houses"]:
		for index: int in _array(key).size():
			var entry: Variant = _array(key)[index]
			var line := _line_of("\"%s\"" % key)
			if typeof(entry) != TYPE_DICTIONARY:
				_fail(line, "la entrada %d de '%s' no es un objeto" % [index, key])
				continue
			var data: Dictionary = entry
			if to_vector2(data.get("pos", null)) == null:
				_fail(line, "la entrada %d de '%s' no tiene una 'pos' de dos números" % [index, key])
			_check_piece(StringName(String(data.get("piece", ""))), line,
					"la entrada %d de '%s'" % [index, key])

	for index: int in _array("groves").size():
		var entry: Variant = _array("groves")[index]
		var line := _line_of("\"groves\"")
		if typeof(entry) != TYPE_DICTIONARY:
			_fail(line, "la arboleda %d no es un objeto" % index)
			continue
		var grove: Dictionary = entry
		if to_vector2_list(grove.get("polygon", null)).size() < 3:
			_fail(line, "la arboleda %d tiene menos de tres vértices" % index)
		if float(grove.get("density", 0.0)) <= 0.0:
			_fail(line, "la arboleda %d no declara una densidad positiva" % index)
		if float(grove.get("min_spacing", 0.0)) < 0.0:
			_fail(line, "la arboleda %d declara una separación mínima negativa" % index)
		var species := grove_species(index)
		if species.is_empty():
			_fail(line, "la arboleda %d no declara ninguna especie" % index)
		for choice: Dictionary in species:
			if float(choice["weight"]) <= 0.0:
				_fail(line, "la especie '%s' de la arboleda %d pesa %.3f"
						% [choice["piece"], index, float(choice["weight"])])
			_check_piece(StringName(choice["piece"]), line, "la arboleda %d" % index)
		var clear: Variant = grove.get("clear", {})
		if typeof(clear) == TYPE_DICTIONARY:
			for key: Variant in (clear as Dictionary):
				if not GROVE_CLEAR.has(StringName(String(key))):
					_fail(line, "la arboleda %d declara la holgura '%s', que no existe"
							% [index, key] + " ('streets', 'blocks', 'houses', 'route')")
		elif clear != null:
			_fail(line, "la holgura de la arboleda %d no es un objeto" % index)

	for index: int in _array("fences").size():
		var entry: Variant = _array("fences")[index]
		var line := _line_of("\"fences\"")
		if typeof(entry) != TYPE_DICTIONARY:
			_fail(line, "el cerco %d no es un objeto" % index)
			continue
		var fence: Dictionary = entry
		if to_vector2_list(fence.get("polyline", null)).size() < 2:
			_fail(line, "el cerco %d tiene menos de dos vértices" % index)
		var kind := StringName(String(fence.get("kind", "")))
		if not FENCE_LINE_KINDS.has(kind):
			_fail(line, "el cerco %d es de tipo '%s', que no existe (%s)"
					% [index, kind, ", ".join(_names(FENCE_LINE_KINDS))])
		else:
			_check_piece(FENCE_PIECE[kind], line, "el cerco %d" % index)

	if _data.has("creek"):
		var creek := _dictionary("creek")
		var line := _line_of("\"creek\"")
		if to_vector2_list(creek.get("polyline", null)).size() < 2:
			_fail(line, "el arroyo tiene menos de dos vértices")
		for key: String in ["width", "depth", "bank"]:
			if float(creek.get(key, 0.0)) <= 0.0:
				_fail(line, "el arroyo no declara un '%s' positivo" % key)
	if _data.has("bridge"):
		var bridge := _dictionary("bridge")
		var line := _line_of("\"bridge\"")
		if to_vector2(bridge.get("at", null)) == null:
			_fail(line, "el puente no declara dónde está")
		for key: String in ["span", "deck_width"]:
			if float(bridge.get(key, 0.0)) <= 0.0:
				_fail(line, "el puente no declara un '%s' positivo" % key)
	if _data.has("plaza"):
		var plaza := _dictionary("plaza")
		var line := _line_of("\"plaza\"")
		if to_vector2_list(plaza.get("polygon", null)).size() < 3:
			_fail(line, "la plaza tiene menos de tres vértices")
		elif not TownPlan.polygon_is_convex(to_vector2_list(plaza.get("polygon", null))):
			_fail(line, "el polígono de la plaza no es convexo")
		var datum: Variant = plaza.get("datum", "auto")
		if typeof(datum) == TYPE_STRING and String(datum) != "auto":
			_fail(line, "la plaza declara 'datum' = '%s': sólo vale \"auto\" o un número"
					% datum)
		# Los props de la plaza se validan como cualquier otro prop: son props que
		# resulta que están en la plaza, y tenerlos declarados ahí adentro es lo
		# que permite mover la plaza entera sin perseguir seis bancos por el JSON.
		var props: Variant = plaza.get("props", [])
		if typeof(props) != TYPE_ARRAY:
			_fail(line, "los props de la plaza no son una lista")
		else:
			for index: int in (props as Array).size():
				var prop: Variant = (props as Array)[index]
				if typeof(prop) != TYPE_DICTIONARY:
					_fail(line, "el prop %d de la plaza no es un objeto" % index)
					continue
				if to_vector2((prop as Dictionary).get("pos", null)) == null:
					_fail(line, "el prop %d de la plaza no tiene una 'pos' de dos números"
							% index)
				_check_piece(StringName(String((prop as Dictionary).get("piece", ""))),
						line, "el prop %d de la plaza" % index)


func _validate_terrain() -> void:
	if not _data.has("terrain"):
		return
	var terrain := _dictionary("terrain")
	var line := _line_of("\"terrain\"")
	for key: String in ["hills", "grain"]:
		var band: Dictionary = terrain.get(key, {})
		if float(band.get("wavelength", 0.0)) <= 0.0:
			_fail(line, "el terreno declara '%s' sin longitud de onda positiva" % key)
		if float(band.get("amplitude", -1.0)) < 0.0:
			_fail(line, "el terreno declara '%s' con amplitud negativa" % key)
	var fade := _to_float_list(terrain.get("fade", null))
	if fade.size() != 2 or fade[0] <= 0.0 or fade[1] <= fade[0]:
		_fail(line, "el terreno necesita un 'fade' de dos radios crecientes")
	if float(terrain.get("route_grade_max", 0.0)) <= 0.0:
		_fail(line, "el terreno no declara una pendiente máxima de ruta positiva")
	if float(terrain.get("mask_feather", 0.0)) <= 0.0:
		_fail(line, "el terreno no declara un 'mask_feather' positivo")


## Anota un aviso si la pieza no se puede sembrar todavía. No es un fallo de
## diseño: es trabajo que llega en WP-D1.
func _check_piece(piece: StringName, line: int, who: String) -> void:
	if piece == &"":
		_warn(line, "%s no nombra ninguna pieza" % who)
		return
	var kind := piece_class(piece)
	if kind == &"":
		_warn(line, "%s usa la pieza '%s', que la tabla no conoce: se omite" % [who, piece])
	elif kind == &"pending":
		pending.append(_where(line,
				"%s usa la pieza '%s', que todavía no existe (WP-D1)" % [who, piece]))


# --------------------------------------------------------------------------
# Accesores
# --------------------------------------------------------------------------

func variation_seed() -> int:
	return int(_number("variation_seed", 0.0))


func play_centre() -> Vector3:
	var flat: Variant = to_vector2(_data.get("play_centre", null))
	if flat == null:
		return Vector3.ZERO
	var point: Vector2 = flat
	return Vector3(point.x, 0.0, point.y)


func play_radius() -> float:
	return _number("play_radius", 140.0)


func block_radius() -> float:
	return _number("block_radius", 150.0)


func field_size() -> float:
	return _number("field_size", 1200.0)


func node_count() -> int:
	return _nodes.size()


func node_id(index: int) -> StringName:
	if index < 0 or index >= _nodes.size():
		return &""
	return _nodes[index]["id"]


func node_position(index: int) -> Vector2:
	if index < 0 or index >= _nodes.size():
		return Vector2.ZERO
	return _nodes[index]["pos"]


func node_index(id: StringName) -> int:
	return int(_node_index.get(id, -1))


## Los vértices de la ruta, en XZ con `y = 0`.
func route_vertices() -> PackedVector3Array:
	var out := PackedVector3Array()
	for point: Vector2 in to_vector2_list(_dictionary("route").get("vertices", null)):
		out.append(Vector3(point.x, 0.0, point.y))
	return out


func route_width() -> float:
	return float(_dictionary("route").get("width", 10.0))


func route_shoulder() -> float:
	return float(_dictionary("route").get("shoulder", 3.0))


## Los nodos que toca la ruta, ya resueltos a índices y en orden.
func route_nodes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id_raw: Variant in _dictionary("route").get("nodes", []):
		var slot := node_index(StringName(String(id_raw)))
		if slot >= 0:
			out.append(slot)
	return out


## Cuántas calles hay **sin contar la ruta**.
func street_count() -> int:
	return _streets.size()


## La calle [param index] del diseño (`0` es la ruta y `1 + k` es la calle `k`),
## con sus nodos ya resueltos a índices.
func street(index: int) -> Dictionary:
	if index == 0:
		return {
			"id": &"route", "a": -1, "b": -1,
			"width": route_width(), "sidewalk": route_shoulder(),
			"kind": &"route", "stub_a": 0.0, "stub_b": 0.0,
			"closure_a": &"none", "closure_b": &"none",
		}
	var slot := index - 1
	if slot < 0 or slot >= _streets.size():
		return {}
	return _streets[slot]


## Índice de plano de la calle [param id], o `-1`.
func street_index(id: StringName) -> int:
	return int(_street_index.get(id, -1))


func block_count() -> int:
	return _blocks.size()


## La manzana [param index]: `{id, nodes: PackedInt32Array, ring, datum, pad,
## houses}`.
func block(index: int) -> Dictionary:
	if index < 0 or index >= _blocks.size():
		return {}
	return _blocks[index]


func poi() -> Array:
	return _array("poi")


func decor_houses() -> Array:
	return _array("decor_houses")


func rocks() -> Array:
	return _array("rocks")


func props() -> Array:
	return _array("props")


func groves() -> Array:
	return _array("groves")


func fences() -> Array:
	return _array("fences")


func creek() -> Dictionary:
	return _dictionary("creek")


func bridge() -> Dictionary:
	return _dictionary("bridge")


func plaza() -> Dictionary:
	return _dictionary("plaza")


## Los props de la plaza, ya como lista de diccionarios.
func plaza_props() -> Array:
	var props: Variant = plaza().get("props", [])
	return props if typeof(props) == TYPE_ARRAY else []


## Los marcadores declarados.
func markers() -> Array:
	return _array("markers")


## Índice de la manzana [param id], o `-1`.
func block_index(id: StringName) -> int:
	for index: int in _blocks.size():
		if StringName(_blocks[index]["id"]) == id:
			return index
	return -1


## Las especies de la arboleda [param index], normalizadas a
## `[{piece: StringName, weight: float}]` y **en el orden declarado**.
##
## El JSON admite las dos formas: una lista de nombres —todas las especies
## pesan lo mismo— y una lista de `{piece, weight}`. El orden importa porque de
## él sale el reparto por peso acumulado, y un reparto que dependiera del orden
## de las claves de un diccionario no sería reproducible.
func grove_species(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Array = groves()
	if index < 0 or index >= list.size():
		return out
	var raw: Variant = (list[index] as Dictionary).get("species", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in (raw as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			var data: Dictionary = entry
			out.append({
				"piece": StringName(String(data.get("piece", ""))),
				"weight": float(data.get("weight", 1.0)),
			})
			continue
		out.append({"piece": StringName(String(entry)), "weight": 1.0})
	return out


## Holguras de la arboleda [param index], con los valores por omisión de
## [constant GROVE_CLEAR] rellenando lo que no declare.
func grove_clear(index: int) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = GROVE_CLEAR.duplicate()
	var list: Array = groves()
	if index < 0 or index >= list.size():
		return out
	var raw: Variant = (list[index] as Dictionary).get("clear", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: Variant in (raw as Dictionary):
		var name := StringName(String(key))
		if out.has(name):
			out[name] = float((raw as Dictionary)[key])
	return out


func terrain() -> Dictionary:
	return _dictionary("terrain")


## Qué lado de la manzana [param block_index] da a la calle [param street], o
## `-1`. El lado `e` va del nodo `e - 1` al nodo `e`, que es el convenio de
## [member TownPlan.block_streets].
func block_edge(block_index: int, street: int) -> int:
	var entry := block(block_index)
	if entry.is_empty():
		return -1
	return _block_edge_of(entry["nodes"] as PackedInt32Array, street)


## Qué calle une los nodos [param a] y [param b], o `-1` si no los une ninguna.
##
## «Unir» quiere decir **ser contiguos en su cadena**: dos nodos de la misma
## calle con un tercero en el medio no están unidos por un lado de manzana, están
## a dos cuadras. Es lo que hace que el lado de una manzana sea siempre una
## cuadra y no media calle.
func street_between(a: int, b: int) -> int:
	for index: int in _chains.size():
		var chain := _chains[index]
		for slot: int in maxi(chain.size() - 1, 0):
			if (chain[slot] == a and chain[slot + 1] == b) \
					or (chain[slot] == b and chain[slot + 1] == a):
				return index
	return -1


## Por qué calles pasa el nodo [param index], en índices de plano.
func node_streets(index: int) -> PackedInt32Array:
	if index < 0 or index >= _node_streets.size():
		return PackedInt32Array()
	return _node_streets[index]


## Los nodos por los que pasa la calle [param index], en orden a lo largo de su
## eje.
func street_chain(index: int) -> PackedInt32Array:
	if index < 0 or index >= _chains.size():
		return PackedInt32Array()
	return _chains[index]


func _block_edge_of(slots: PackedInt32Array, street: int) -> int:
	for edge: int in slots.size():
		var from := slots[(edge - 1 + slots.size()) % slots.size()]
		var to := slots[edge]
		if street_between(from, to) == street:
			return edge
	return -1


# --------------------------------------------------------------------------
# Identidad
# --------------------------------------------------------------------------

## Entero estable que identifica **este** diseño.
##
## Va a `TownPlan.design_hash` y de ahí a la firma del plano, así que dos diseños
## distintos no pueden dar el mismo pueblo aunque casualmente resuelvan a las
## mismas parcelas.
##
## Se llama `design_hash` y no `hash` porque `Object.hash()` ya existe en el
## motor y tapar un método nativo es pedir una sorpresa.
func design_hash() -> int:
	if _hash_done:
		return _hash_cache
	var bytes := _canonical(_data).to_utf8_buffer()
	# Se rellena a múltiplo de ocho para poder mezclar de a un entero de 64 bits
	# en vez de byte a byte: son veinte mil bytes y mezclarlos de a uno cuesta
	# cuarenta mil llamadas en cada `generate()`.
	while bytes.size() % 8 != 0:
		bytes.append(0)
	var acc := TownPlan.mix(bytes.size())
	var offset := 0
	while offset < bytes.size():
		acc = TownPlan.mix(acc ^ TownPlan.mix(bytes.decode_s64(offset)))
		offset += 8
	_hash_cache = acc
	_hash_done = true
	return _hash_cache


## El diseño como texto canónico: claves ordenadas y flotantes a cuatro
## decimales. Reindentar el JSON no cambia esto; cambiar un número, sí.
static func _canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var data: Dictionary = value
			var keys: PackedStringArray = PackedStringArray()
			for key: Variant in data.keys():
				keys.append(String(key))
			keys.sort()
			var parts: PackedStringArray = PackedStringArray()
			for key: String in keys:
				parts.append("%s:%s" % [key, _canonical(data[key])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var list: Array = value
			var items: PackedStringArray = PackedStringArray()
			for item: Variant in list:
				items.append(_canonical(item))
			return "[%s]" % ",".join(items)
		TYPE_FLOAT, TYPE_INT:
			return "%.4f" % float(value)
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_NIL:
			return "null"
		_:
			return "\"%s\"" % String(value)


# --------------------------------------------------------------------------
# Lectura del JSON
# --------------------------------------------------------------------------

func _number(key: String, fallback: float) -> float:
	var value: Variant = _data.get(key, null)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	return float(value)


func _array(key: String) -> Array:
	var value: Variant = _data.get(key, null)
	if typeof(value) != TYPE_ARRAY:
		return []
	return value


func _dictionary(key: String) -> Dictionary:
	var value: Variant = _data.get(key, null)
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


## Un par `[x, z]` del JSON como [Vector2], o `null` si no lo es.
static func to_vector2(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return null
	var pair: Array = value
	if pair.size() != 2:
		return null
	for item: Variant in pair:
		if typeof(item) != TYPE_FLOAT and typeof(item) != TYPE_INT:
			return null
	return Vector2(float(pair[0]), float(pair[1]))


## Una lista de pares `[x, z]` como polilínea o polígono en XZ.
static func to_vector2_list(value: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if typeof(value) != TYPE_ARRAY:
		return out
	for item: Variant in value:
		var point: Variant = to_vector2(item)
		if point == null:
			continue
		out.append(point)
	return out


static func _to_float_list(value: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if typeof(value) != TYPE_ARRAY:
		return out
	for item: Variant in value:
		if typeof(item) == TYPE_FLOAT or typeof(item) == TYPE_INT:
			out.append(float(item))
	return out


static func _names(list: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()
	for item: StringName in list:
		out.append("'%s'" % item)
	return out


## El punto de [param line] más cercano a [param point], como
## `{distance, along}`.
static func _closest_on_polyline(line: PackedVector2Array, point: Vector2) -> Dictionary:
	var best := INF
	var best_along := 0.0
	var travelled := 0.0
	for index: int in maxi(line.size() - 1, 0):
		var a := line[index]
		var delta := line[index + 1] - a
		var span := delta.length()
		if span <= 0.0001:
			continue
		var t := clampf((point - a).dot(delta) / (span * span), 0.0, 1.0)
		var distance := point.distance_to(a + delta * t)
		if distance < best:
			best = distance
			best_along = travelled + span * t
		travelled += span
	return {"distance": best, "along": best_along}


# --------------------------------------------------------------------------
# Mensajes
# --------------------------------------------------------------------------

## La primera línea (base 1) que contiene [param needle], buscando desde
## [param from]; `0` si no aparece.
func _line_of(needle: String, from: int = 1) -> int:
	for index: int in range(maxi(from - 1, 0), _lines.size()):
		if _lines[index].contains(needle):
			return index + 1
	return 0


func _fail(line: int, message: String) -> void:
	problems.append(_where(line, message))


func _warn(line: int, message: String) -> void:
	warnings.append(_where(line, message))


func _where(line: int, message: String) -> String:
	var file := source_path.get_file()
	return "%s:%d: %s" % [file, line, message] if line > 0 else "%s: %s" % [file, message]


## Saca los mensajes por el log del motor. Los fallos van por `push_error` —así
## una corrida de `build_town` con un diseño roto muere ruidosa— y los avisos por
## `push_warning`.
##
## Se puede callar con [member report_to_log], y hay un solo motivo legítimo para
## hacerlo: las **pruebas negativas** del check, que rompen un diseño a propósito
## y cuyos errores esperados ensuciarían el log de una corrida en verde.
func _report() -> void:
	if not report_to_log:
		return
	for problem: String in problems:
		push_error(problem)
	for warning: String in warnings:
		push_warning(warning)
