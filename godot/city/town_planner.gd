## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Resuelve un [TownDesign] en un [TownPlan] (`docs/10` §4, reescrito por WP-T3).
##
## No toca un solo asset: es aritmética y geometría de polígonos, y por eso
## `tools/town_plan_check.gd` lo puede correr entero en `--headless` puro en
## menos de cinco segundos.
##
## ## El diseño manda; el código resuelve
##
## Hasta P2b esta clase **sorteaba** el pueblo: la semilla elegía el rumbo de la
## ruta, la separación de las transversales, el ángulo de cada cruce y qué lado
## de manzana se llenaba de casas. Salían pueblos plausibles y ninguno bueno,
## porque una semilla no sabe que la escuela va enfrente de la plaza ni que las
## calles tienen que llegar a algún lado: dos transversales las amputaba el
## recorte al círculo, las dos paralelas de fondo colgaban doce metros en el
## campo y las manzanas se tallaban con **rectas infinitas**, así que había casas
## de frente a calles que no pasaban por ahí.
##
## Ahora el trazado se escribe a mano en `city/designs/town_a.json` y acá se
## resuelve, en este orden:
##
## 1. el **grafo**: los nodos declarados y las calles que los unen, cada una con
##    su cabo y su cierre; la ruta es la calle `0` y va de nodo a nodo;
## 2. las **manzanas**, que son el anillo de sus propios nodos metido hacia
##    adentro la media franja de la calle de cada lado —ya no se tallan con
##    semiplanos— y por lo tanto cierran exactamente sobre el viario;
## 3. los **frentes**: los lados de manzana que de verdad dan a una calle
##    ([method _frontage_edges], que sobrevive de WP-B);
## 4. las **parcelas declaradas**: los POI por su posición y su giro, y después
##    casa por casa con su pieza, su variante, su color y su sitio sobre el
##    frente (`t`);
## 5. los **marcadores** —apariciones, puestos de pila, dron y cámara— y lo de
##    afuera: caseríos, rocas y maleza.
##
## ## Qué queda de aleatorio
##
## Sólo lo que el diseño **no** declara: el giro fino de una casa dentro de su
## lote —hasta diez centímetros medidos en su fachada—, su altura, y las noventa
## y seis matas de maleza. Y no sale de una semilla global sino de
## [method TownPlan.mix_all] sembrado con `variation_seed`, la manzana y el sitio
## dentro de la manzana: es **posicional**, así que mover la casa 3 de la manzana
## 7 —o recolorearla— no mueve ni una de las otras cuarenta y cinco. Eso es lo
## que permite editar el diseño con `diff` y saber qué cambió.
##
## ## Nota para quien consuma el grafo
##
## Los nodos que este resolvedor escribe llevan **también las calles que pasan de
## largo**: el cruce de la ruta con una transversal tiene cuatro bocas, no dos.
## [method TownPlan.refresh_nodes] deduce las bocas sólo de las **puntas** de
## cada calle, así que llamarlo sobre un plano resuelto acá borraría la mitad de
## las bocas de todos los cruces. No hace falta llamarlo: los nodos ya vienen
## completos. `tools/town_plan_check.gd` tiene una fila que lo vigila.
@tool
class_name TownPlanner extends RefCounted

# --- Entrada ---------------------------------------------------------------

## Diseño con el que se hornea `city/districts/town_a.tscn`.
const DESIGN_PATH: String = "res://city/designs/town_a.json"

## Relieve horneado de `town_a` (WP-T2).
##
## [method generate] lo carga **si está en disco** y se lo pasa a
## [method resolve]. Es lo que hace que el plano que viaja dentro de
## `town_a.tscn` y el que `tools/city_check.gd` rehace por su cuenta salgan con
## las mismas cotas de manzana: los dos pasan por el mismo camino y leen el
## mismo `.res`. Sin el archivo el mundo es plano, que es como corrió el
## resolvedor hasta que WP-T2 entregó el terreno.
const TERRAIN_PATH: String = "res://assets/city/terrain/town_a_terrain.res"

## Semilla histórica de `town_a`.
##
## Ya no elige nada —el trazado lo elige el diseño y la variación fina sale de su
## `variation_seed`—, pero sigue viva porque `tools/build_town.gd`,
## `tools/build_terrain.gd` y `tools/city_check.gd` la usan como **la** fuente de
## verdad con la que rehacer el plano y comprobar que la escena comiteada está al
## día.
const TOWN_SEED: int = 0

## Valores por omisión del pueblo. El diseño manda: éstos sólo rellenan los
## argumentos de [method generate], que se conservan por compatibilidad.
const PLAY_RADIUS: float = 140.0
const FIELD_SIZE: float = 1200.0

# --- Parcelas --------------------------------------------------------------

## Ancho de parcela de casa cuando el diseño no declara `width`, en metros.
const HOUSE_WIDTH_TARGET: float = 12.0

## Fondo de una parcela de casa, en metros.
##
## La fachada de las casas de WP-A mira a **−X local**, así que el fondo de la
## parcela lo ocupa su `base_size.x`, que es 5,00–5,10 m en las diez piezas. Con
## 5,4 la casa entra entera y sobran 15 cm de retiro contra la línea municipal.
const HOUSE_DEPTH: float = 5.4

## Huella de un edificio grande cuando el diseño no declara `footprint`, en
## metros: `BuildingBlock_18/19` miden 20 × 11 m y la parcela les deja medio
## metro por lado.
const BIG_WIDTH: float = 21.0
const BIG_DEPTH: float = 11.5

## Variación de altura de una casa cuando el diseño no la declara.
const HOUSE_SCALE_MIN: float = 0.92
const HOUSE_SCALE_MAX: float = 1.18

## Cuánto se puede girar **el edificio dentro de su lote** cuando el diseño no
## lo gira, medido en su fachada: diez centímetros de corrimiento en la punta del
## frente.
##
## No es un capricho: una cuadra de casas perfectamente alineadas se lee como una
## rejilla y un grado de desorden la convierte en una cuadra. Se mide en metros y
## no en grados para que una casa ancha y una angosta se desordenen lo mismo a la
## vista.
##
## Gira **el edificio, no el lote**. El lote se mide derecho —`frontage_normal`
## queda perpendicular al frente— y el giro viaja en la clave `yaw_jitter` de la
## parcela, que aplica el constructor. Girar el lote parecía más simple y no lo
## es: los lotes de una cuadra se tocan de borde a borde, así que medio grado de
## giro hace que dos lotes vecinos se pisen y `_parcel_problems` —con razón— los
## rechace. Lo que está torcido en un pueblo es la casa, no la manzana.
const HOUSE_YAW_JITTER: float = 0.10

## Sales de las mezclas posicionales. Son enteros y no textos porque la llave la
## produce [method TownPlan.mix_all], no `String.hash()`, que es un detalle de
## implementación del motor.
const SALT_HOUSE: int = 0x686F7573  # "hous"
const SALT_DECOR: int = 0x6465636F  # "deco"
const SALT_POST: int = 0x706F7374   # "post"
const SALT_GROVE: int = 0x67726F76  # "grov"
const SALT_FENCE: int = 0x66656E63  # "fenc"
const SALT_PROP: int = 0x70726F70   # "prop"

# --- Arboledas -------------------------------------------------------------

## Cuánto se corre una instancia de arboleda dentro de su celda, como fracción
## del lado de la celda.
##
## La siembra es una **rejilla con temblor** y no un Poisson por rechazo a
## propósito: la rejilla da una llave por celda —`(arboleda, ix, iz)`— y por lo
## tanto determinismo **posicional**, que es lo que permite agrandar el polígono
## de una arboleda sin que se muevan los árboles que ya estaban. Un Poisson por
## rechazo recorre las candidatas en orden y una candidata nueva le cambia el
## estado a todas las de atrás: el mismo problema del contador global que WP-T3
## sacó de las casas.
##
## El temblor se mide en **fracción de celda** y vale 0,28: la instancia se
## mueve hasta poco más de un cuarto de celda desde su centro, así que dos
## vecinas nunca se cruzan —haría falta 0,5— y la rejilla deja de leerse como
## rejilla. El docstring decía 0,42 y la constante 0,28 desde WP-D2 (WP-D4a,
## hallazgo 16): manda la constante, que es la que sembró los mil cuatrocientos
## árboles que el orquestador aprobó en las capturas.
const GROVE_JITTER: float = 0.28

## Escala mínima y máxima de una instancia de arboleda.
const GROVE_SCALE_MIN: float = 0.82
const GROVE_SCALE_MAX: float = 1.24

## Cuánto se separa un tramo de cerco de la franja de calle que cruza, además
## de la media franja, en metros. Es el hueco de la tranquera.
const FENCE_STREET_GAP: float = 1.5

# --- Props -----------------------------------------------------------------

## A cuántos metros del frente, hacia adentro del lote, va el árbol del patio.
##
## El lote mide [constant HOUSE_DEPTH] de fondo y la casa lo ocupa entero, así
## que el árbol va **detrás** de la casa: es el patio, que es donde está el
## árbol frutal y el tendedero de `docs/17` §3.
const GARDEN_TREE_DEPTH: float = 10.0

## Cuánto se corre el cerco del frente **hacia adentro del lote**, en metros.
##
## El signo estaba al revés (WP-D4a, hallazgo 17): el código sumaba la normal de
## frente —que apunta a la calle— así que el cerco se plantaba treinta
## centímetros **sobre la vereda**, encima del cordón. Va sobre la línea
## municipal y apenas adentro, que es donde está el cerco de una casa.
const FRONT_FENCE_OFFSET: float = 0.30

# --- Piezas ----------------------------------------------------------------

## Alto nativo de cada pieza, en metros. Es una **tabla de datos**, no una
## lectura de assets: el plano tiene que poder calcular la azotea de la escuela
## sin abrir un `.tscn`. [CityGrid] afina los puestos de azotea con la altura
## real cuando siembra.
const PIECE_HEIGHT: Dictionary[StringName, float] = {
	&"house_a": 3.00,
	&"house_a_b": 2.70,
	&"house_b": 5.55,
	&"house_b_b": 5.30,
	&"house_c": 3.00,
	&"house_c_b": 2.90,
	&"house_d": 5.50,
	&"house_d_b": 5.00,
	&"shed": 2.25,
	&"shed_b": 2.55,
	&"block_mid": 12.5,
	&"tower_b": 12.5,
	&"block_low_c": 8.0,
	# Los cuatro POI procedurales de WP-D1. Faltaban (WP-D4a, hallazgo 20), así
	# que `PIECE_HEIGHT.get(piece, 12.5)` les devolvía 12,5 m: el tanque de agua
	# —que mide 16,5— perdía cuatro metros y el galpón de campo —que mide 6—
	# ganaba seis y medio. Es la tabla con la que el resolvedor calcula la azotea
	# de un puesto de pila sin abrir un `.tscn`, y los números son los del
	# manifiesto de WP-D1.
	&"water_tower": 16.5,
	&"silo": 14.0,
	&"gas_station": 8.0,
	&"field_shed": 6.0,
}

## Qué rol de [TownPlan] es cada rol de POI del diseño.
##
## Los que faltan —`gas_station`, `water_tower`, `silo`, `chapel`, `shed`— están
## en [constant TownDesign.POI_ROLES] y el diseño los puede declarar hoy: se
## validan, se avisa que no se siembran y se omiten hasta que WP-D1 traiga su
## pieza. Sembrar otra cosa en su lugar escondería el hueco debajo de un edificio
## que se ve bien y no es el que el diseño pidió.
## Desde WP-D2 están los cinco: la estación de servicio, el tanque, el silo, el
## galpón y la capilla entran como `MEDIUM` —3 500 HP, perfil de torre— porque
## es lo que son de cara al juego: edificios grandes que el coloso tira y que
## cuentan en la integridad. Lo que decide si se siembran **no** es esta tabla
## sino la clase de su pieza: mientras el manifiesto de WP-D1 no exista siguen
## siendo `pending` y se omiten con aviso, igual que antes.
const POI_ROLE: Dictionary[StringName, int] = {
	&"school": TownPlan.Role.SCHOOL,
	&"landmark": TownPlan.Role.LANDMARK,
	&"medium": TownPlan.Role.MEDIUM,
	&"gas_station": TownPlan.Role.MEDIUM,
	&"water_tower": TownPlan.Role.MEDIUM,
	&"silo": TownPlan.Role.MEDIUM,
	&"chapel": TownPlan.Role.MEDIUM,
	&"shed": TownPlan.Role.MEDIUM,
}

# --- Afuera del círculo ----------------------------------------------------

## Cuántos manojos de maleza, basura y barriles se siembran. No se declaran: son
## ruido de campo, y lo que el diseño declara son los props que **cuentan algo**.
const DECOR_SPOTS: int = 96

# --- Marcadores ------------------------------------------------------------

## A qué distancia del borde del círculo aparece el coloso, en metros.
const SPAWN_MARGIN: float = 60.0

## Distancia al centro a la que aparece el dron, sobre la ruta.
const DRONE_DISTANCE: float = 120.0

## Altura de aparición del dron, en metros.
const DRONE_HEIGHT: float = 1.5

## Puestos de pila en calle y en azotea (`docs/09`).
const POSTS_STREET: int = 5
const POSTS_ROOF: int = 3

## Altura de un puesto de pila de calle, en metros.
##
## **Bajo el toldo, no sobre él** (WP-D4a, hallazgo 5). Cuatro a seis metros
## venía de P2b, cuando un puesto de calle era una caja flotando sobre un cruce
## y no tenía nada debajo. Desde WP-D2 la gramática de `docs/17` §4 dice «toldo
## naranja = pila» y los cuatro primeros puestos cuelgan de un toldo: el toldo
## arranca a 2,40 m y mide 0,80, así que un puesto a cinco metros está un metro y
## medio **por encima** del toldo del que tendría que colgar y la regla deja de
## leerse desde la calle. De 2,80 a 3,20 el puesto queda dentro del volumen del
## toldo.
const POST_STREET_Y_MIN: float = 2.8
const POST_STREET_Y_MAX: float = 3.2

## Altura de un puesto de azotea sobre el techo, en metros. `BatterySpawner`
## comprueba el hueco con una esfera de 2,5 m (`docs/10` §1, nota de WP-24b).
const POST_ROOF_CLEARANCE: float = 3.2

## Pose de la cámara fija: altura y distancia al centro, en metros.
const CAMERA_HEIGHT: float = 120.0
const CAMERA_DISTANCE: float = 240.0


# --------------------------------------------------------------------------
# Entrada
# --------------------------------------------------------------------------

## Traza el pueblo comiteado.
##
## Conserva la firma pública de WP-B para no romper a `tools/build_town.gd`,
## `tools/build_terrain.gd` ni `tools/city_check.gd`, pero **los tres argumentos
## se ignoran**: el radio, el campo y la variación los declara
## `city/designs/town_a.json`, que es la fuente de verdad desde WP-T3. Se dejan
## para que una llamada vieja siga compilando y para que [constant TOWN_SEED]
## siga siendo el identificador con el que los checks rehacen el plano.
##
## Devuelve un plano vacío si el diseño no carga: los incumplimientos ya salieron
## por `push_error` con su número de línea.
static func generate(town_seed: int = TOWN_SEED, radius: float = PLAY_RADIUS,
		field: float = FIELD_SIZE) -> TownPlan:
	var _ignored := [town_seed, radius, field]
	var design := TownDesign.load_json(DESIGN_PATH)
	if design == null:
		push_error("TownPlanner: '%s' no se pudo cargar; el plano sale vacío." % DESIGN_PATH)
		return TownPlan.new()
	return resolve(design, baked_terrain())


## El relieve horneado de `town_a`, o `null` si todavía no está en disco.
##
## Se devuelve como [Object] y se carga con [method ResourceLoader.load] y no
## con `preload` porque `tools/build_terrain.gd` —que es quien lo escribe—
## también llama a [method generate] para saber por dónde pasan la ruta y las
## manzanas: un `preload` ataría el horneado del terreno a que el terreno ya
## exista, que es el orden al revés. El horneado no lee `block_datum`, así que
## la vuelta se cierra sin morderse la cola.
static func baked_terrain() -> Object:
	if not ResourceLoader.exists(TERRAIN_PATH):
		return null
	return ResourceLoader.load(TERRAIN_PATH, "Resource")


## Resuelve [param design] en un plano.
##
## [param terrain] es el `TownTerrain` horneado de WP-T2, o `null`. Se recibe
## como [Object] y se usa por pato —`height_at(x, z)`— a propósito: el plano y su
## check tienen que seguir corriendo aunque el terreno todavía no exista, y
## nombrar la clase obligaría al analizador a compilarla.
static func resolve(design: TownDesign, terrain: Object = null) -> TownPlan:
	var plan := TownPlan.new()
	plan.seed = design.variation_seed()
	plan.play_centre = design.play_centre()
	plan.play_radius = design.play_radius()
	plan.block_radius = design.block_radius()
	plan.field_size = design.field_size()
	plan.route = design.route_vertices()
	plan.route_width = design.route_width()
	plan.route_shoulder = design.route_shoulder()
	plan.resource_name = "town_%s" % design.resource_name

	var graph := build_graph(design)
	_apply_graph(plan, design, graph)
	_carve_blocks(plan, design, terrain)
	_place_plaza(plan, design)
	_place_parcels(plan, design, terrain)
	_place_hamlets(plan, design, terrain)
	_place_markers(plan, design, graph)
	_place_rocks(plan, design)
	_place_decor(plan, design)
	# Lo de WP-D2 va **al final** porque mira todo lo anterior: las arboledas
	# esquivan calles, manzanas y huellas; los cercos, las calzadas; los props,
	# las casas de las que cuelgan.
	_place_groves(plan, design)
	_place_fences(plan, design)
	_place_props(plan, design)
	_place_creek(plan, design)
	_place_bridge(plan, design, terrain)
	return plan


# --------------------------------------------------------------------------
# 1. Grafo
# --------------------------------------------------------------------------

## Arma el grafo del diseño: los nodos con sus bocas y las calles con su eje, su
## cabo y su cierre.
##
## Se devuelve como diccionario —y no sólo escrito en el plano— para que
## `tools/town_plan_check.gd` pueda verificar el grafo del **diseño** aunque el
## plano venga de otra parte.
##
## El eje de una calle va del nodo `a` al nodo `b` y se prolonga `stub_a` metros
## antes del primero y `stub_b` después del segundo. Una punta con cabo no llega
## a ningún nodo —[member TownPlan.street_nodes] guarda `-1`— y por eso tiene que
## traer cierre; una punta sin cabo termina **exactamente** sobre su nodo, que es
## lo que [method TownPlan.graph_problems] mide con 5 cm de tolerancia.
##
## Las bocas de un nodo salen de la **geometría** y no de las puntas: una calle
## que pasa de largo por un nodo aporta dos bocas, una para cada lado. Es lo que
## hace que el cruce de la ruta con una transversal sea un polígono de cuatro
## bocas y no de dos.
static func build_graph(design: TownDesign) -> Dictionary:
	var axes: Array[PackedVector3Array] = [design.route_vertices()]
	for index: int in design.street_count():
		var street := design.street(index + 1)
		var a := design.node_position(int(street["a"]))
		var b := design.node_position(int(street["b"]))
		var direction := (b - a).normalized()
		var from := a - direction * float(street["stub_a"])
		var to := b + direction * float(street["stub_b"])
		axes.append(PackedVector3Array([
			Vector3(from.x, 0.0, from.y), Vector3(to.x, 0.0, to.y)]))

	# --- Bocas de cada nodo ----------------------------------------------
	var arms: Array[Array] = []
	for _node: int in design.node_count():
		arms.append([])
	for street: int in axes.size():
		var axis := axes[street]
		var half := _street_half(design, street)
		var length := TownPlan.polyline_length(axis)
		for node: int in design.node_count():
			var flat := design.node_position(node)
			var point := Vector3(flat.x, 0.0, flat.y)
			var along := TownPlan.polyline_closest(axis, point)
			if TownPlan.polyline_point(axis, along).distance_to(point) \
					> TownDesign.ON_AXIS_TOLERANCE:
				continue
			var tangent := TownPlan.polyline_tangent(axis, along)
			if along > TownDesign.ON_AXIS_TOLERANCE:
				arms[node].append({"street": street, "half": half, "dir": -tangent})
			if along < length - TownDesign.ON_AXIS_TOLERANCE:
				arms[node].append({"street": street, "half": half, "dir": tangent})

	# --- Nodos -------------------------------------------------------------
	var nodes: Array[Dictionary] = []
	for node: int in design.node_count():
		var list: Array = arms[node]
		# Ordenadas por rumbo: `RoadMesh` recorre el cruce en círculo y toma cada
		# boca con la siguiente para calcular el chaflán de la esquina.
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var angle_a := _arm_angle(a["dir"])
			var angle_b := _arm_angle(b["dir"])
			if not is_equal_approx(angle_a, angle_b):
				return angle_a < angle_b
			return int(a["street"]) < int(b["street"]))
		var streets := PackedInt32Array()
		var angles := PackedFloat32Array()
		var half_widths := PackedFloat32Array()
		for arm: Dictionary in list:
			streets.append(int(arm["street"]))
			angles.append(_arm_angle(arm["dir"]))
			half_widths.append(float(arm["half"]))
		var flat := design.node_position(node)
		var entry: Dictionary = {
			"pos": Vector3(flat.x, 0.0, flat.y),
			"streets": streets,
			"angles": angles,
			"half_widths": half_widths,
			# `poly` sale vacío a propósito: el polígono del cruce con su chaflán
			# es geometría de la cinta y lo calcula [RoadMesh] cuando alguien lo
			# pide ([method TownPlan.node_at]). El radio sí se guarda, porque
			# entra en la firma y porque recortar las cintas lo necesita.
			"poly": PackedVector2Array(),
			"radius": 0.0,
		}
		entry["radius"] = RoadMesh.node_radius(entry)
		nodes.append(entry)

	# --- Calles ------------------------------------------------------------
	var route_nodes := design.route_nodes()
	var head := route_nodes[0] if route_nodes.size() > 0 else -1
	var tail := route_nodes[route_nodes.size() - 1] if route_nodes.size() > 0 else -1
	var street_nodes := PackedInt32Array([head, tail])
	var street_stubs := PackedFloat32Array([0.0, 0.0])
	var street_kind := PackedInt32Array([TownPlan.StreetKind.ROUTE])
	var street_closures := PackedStringArray([""])
	for index: int in design.street_count():
		var street := design.street(index + 1)
		for suffix: String in ["a", "b"]:
			var stub := float(street["stub_%s" % suffix])
			# Con cabo la calle **no** termina en su nodo: sigue de largo y muere
			# en el campo, así que la punta es un cabo declarado y el nodo queda
			# como un cruce por el que la calle pasa.
			street_nodes.append(-1 if stub > 0.0 else int(street[suffix]))
			street_stubs.append(stub)
		street_kind.append(maxi(TownDesign.STREET_KINDS.find(street["kind"]), 0))
		var closure_a := StringName(street["closure_a"])
		var closure_b := StringName(street["closure_b"])
		if closure_a == &"none" and closure_b == &"none":
			street_closures.append("")
		else:
			street_closures.append("a:%s;b:%s" % [closure_a, closure_b])

	return {
		"nodes": nodes,
		"axes": axes,
		"street_nodes": street_nodes,
		"street_stubs": street_stubs,
		"street_kind": street_kind,
		"street_closures": street_closures,
		"design_hash": design.design_hash(),
	}


## Copia el grafo y los ejes al plano.
static func _apply_graph(plan: TownPlan, design: TownDesign, graph: Dictionary) -> void:
	var axes: Array[PackedVector3Array] = graph["axes"]
	plan.streets = []
	plan.street_widths = PackedFloat32Array()
	plan.street_sidewalks = PackedFloat32Array()
	for index: int in design.street_count():
		var street := design.street(index + 1)
		plan.streets.append(axes[index + 1])
		plan.street_widths.append(float(street["width"]))
		plan.street_sidewalks.append(float(street["sidewalk"]))

	plan.nodes = graph["nodes"]
	plan.street_nodes = graph["street_nodes"]
	plan.street_stubs = graph["street_stubs"]
	plan.street_kind = graph["street_kind"]
	plan.street_closures = graph["street_closures"]
	plan.design_hash = graph["design_hash"]
	# `block_rings` los llena el constructor desde [method RoadMesh.ring]: el
	# anillo de vereda es geometría de la cinta y no del plano. Vacío quiere
	# decir «usá el polígono de la manzana», que es lo que hace
	# [method TownPlan.block_ring].
	plan.block_rings = []


## Media franja —calzada más vereda— de la calle [param index] del diseño.
static func _street_half(design: TownDesign, index: int) -> float:
	var street := design.street(index)
	if street.is_empty():
		return 0.0
	return float(street["width"]) * 0.5 + float(street["sidewalk"])


## Rumbo de una boca en XZ, en radianes: el mismo `atan2(dz, dx)` del contrato
## del grafo.
static func _arm_angle(direction: Vector3) -> float:
	return atan2(direction.z, direction.x)


# --------------------------------------------------------------------------
# 2. Manzanas
# --------------------------------------------------------------------------

## Resuelve cada manzana declarada: el anillo de sus nodos metido hacia adentro
## la media franja de la calle de cada lado.
##
## Un lado entre dos nodos que **no** une ninguna calle no se mete nada: es el
## fondo de la manzana contra el campo, y ahí no hay vereda que respetar. Con
## esto la manzana cierra exactamente sobre el viario: ya no hay casas de frente
## a una calle que pasaba de largo, porque el lado existe **porque** la calle lo
## limita.
static func _carve_blocks(plan: TownPlan, design: TownDesign, terrain: Object) -> void:
	plan.blocks = []
	plan.block_streets = []
	plan.block_datum = PackedFloat32Array()
	for index: int in design.block_count():
		var block := design.block(index)
		var ring: PackedVector2Array = block["ring"]
		var slots: PackedInt32Array = block["nodes"]
		var tags := PackedInt32Array()
		for edge: int in slots.size():
			var from := slots[(edge - 1 + slots.size()) % slots.size()]
			tags.append(design.street_between(from, slots[edge]))
		plan.blocks.append(_inset(design, ring, tags))
		plan.block_streets.append(tags)
		plan.block_datum.append(_block_datum(block, ring, terrain))


## Cota de apoyo de una manzana. `"auto"` la toma del terreno horneado en el
## baricentro; sin terreno conectado es cero, y la cota real la pone WP-T4 al
## rehornear el pueblo con el terreno en la mano.
static func _block_datum(block: Dictionary, ring: PackedVector2Array,
		terrain: Object) -> float:
	var datum: Variant = block.get("datum", "auto")
	if typeof(datum) == TYPE_FLOAT or typeof(datum) == TYPE_INT:
		return float(datum)
	if terrain == null or not terrain.has_method("height_at"):
		return 0.0
	var centre := TownPlan.polygon_centroid(ring)
	return float(terrain.call("height_at", centre.x, centre.y))


## Mete el polígono [param ring] hacia adentro la media franja de la calle de
## cada lado y devuelve el polígono resultante, vértice a vértice.
##
## El vértice `i` del resultado es el corte de los dos lados corridos que lo
## tocan: el que entra (`i`) y el que sale (`i + 1`). Si salieran paralelos —no
## puede pasar en un polígono convexo de verdad, pero un diseño a medio escribir
## sí— se deja el nodo sin correr, que es un error visible y no un `NaN`.
static func _inset(design: TownDesign, ring: PackedVector2Array,
		tags: PackedInt32Array) -> PackedVector2Array:
	var count := ring.size()
	var winding := 1.0 if TownPlan.polygon_signed_area(ring) >= 0.0 else -1.0
	var lines: Array[Dictionary] = []
	for edge: int in count:
		var a := ring[(edge - 1 + count) % count]
		var b := ring[edge]
		var direction := (b - a).normalized()
		var outward := Vector2(direction.y, -direction.x) * winding
		var half := _street_half(design, tags[edge]) if tags[edge] >= 0 else 0.0
		lines.append({"point": a - outward * half, "dir": direction})
	var out := PackedVector2Array()
	for corner: int in count:
		var first: Dictionary = lines[corner]
		var second: Dictionary = lines[(corner + 1) % count]
		var hit: Variant = _line_cross(first["point"], first["dir"],
				second["point"], second["dir"])
		out.append(hit if hit != null else ring[corner])
	return out


## Corte de dos rectas infinitas, o `null` si son paralelas.
static func _line_cross(p: Vector2, d: Vector2, q: Vector2, e: Vector2) -> Variant:
	var denominator := d.cross(e)
	if absf(denominator) < 0.000001:
		return null
	return p + d * ((q - p).cross(e) / denominator)


# --------------------------------------------------------------------------
# 3. Frentes
# --------------------------------------------------------------------------

## Todos los lados de manzana que dan a una calle.
##
## Sobrevive de WP-B con un cambio: ya no descarta los lados cortos. El corte por
## largo mínimo existía porque el sembrado automático tenía que decidir solo si un
## lado aguantaba una casa; ahora lo decide el diseño, y un lado de doce metros
## con una sola casa declarada es una decisión, no un accidente.
static func _frontage_edges(plan: TownPlan) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for block: int in plan.block_count():
		var poly := plan.block_polygon(block)
		for edge: int in poly.size():
			var street := plan.block_edge_street(block, edge)
			if street < 0:
				continue
			# `block_streets[i]` es la calle del lado que **entra** al vértice
			# `i`, o sea el que va de `i - 1` a `i`.
			var a := poly[(edge - 1 + poly.size()) % poly.size()]
			var b := poly[edge]
			var length := a.distance_to(b)
			if length <= 0.01:
				continue
			var outward := TownPlan.polygon_edge_normal(poly,
					(edge - 1 + poly.size()) % poly.size())
			if outward == Vector2.ZERO:
				continue
			var mid := (a + b) * 0.5
			found.append({
				"block": block,
				"edge": edge,
				"street": street,
				"a": a,
				"b": b,
				"length": length,
				"normal": outward,
				"mid": mid,
				"centre_distance": Vector2(plan.play_centre.x, plan.play_centre.z).distance_to(mid),
			})
	return found


# --------------------------------------------------------------------------
# 4. Parcelas declaradas
# --------------------------------------------------------------------------

## Siembra los POI y después las casas, en ese orden.
##
## El orden importa y es el mismo de WP-B: escuela, hito, medianos y recién
## después las casas. [member TownPlan.battery_roof_parcels] y `city_check`
## cuentan con que las tres azoteas con puesto de pila sean las tres primeras
## parcelas del plano.
static func _place_parcels(plan: TownPlan, design: TownDesign,
		terrain: Object = null) -> void:
	plan.parcels = []
	var edges := _frontage_edges(plan)
	_place_poi(plan, design, edges, terrain)
	_place_houses(plan, design, edges)


## Escuela, hito y medianos: posición y giro declarados, manzana y calle
## deducidas de la geometría.
##
## El POI declara **dónde está el edificio**, no sobre qué lado se apoya, que es
## lo que dice un plano de nivel. La manzana y la calle salen de buscar el frente
## más cercano; si no hubiera ninguno el POI se siembra igual con `block = -1`, y
## `town_plan_check` lo ve en la fila de parcelas.
static func _place_poi(plan: TownPlan, design: TownDesign,
		edges: Array[Dictionary], terrain: Object = null) -> void:
	var mediums := 0
	for entry: Variant in design.poi():
		var data: Dictionary = entry
		var role_key := StringName(String(data.get("role", "")))
		if not POI_ROLE.has(role_key):
			push_warning("TownPlanner: el POI '%s' es de rol '%s' y todavía no se siembra (WP-D1)."
					% [data.get("id", "?"), role_key])
			continue
		var piece := StringName(String(data.get("piece", "")))
		if TownDesign.piece_class(piece) != &"building":
			push_warning("TownPlanner: el POI '%s' pide la pieza '%s', que no se puede sembrar: se omite."
					% [data.get("id", "?"), piece])
			continue

		var role: int = POI_ROLE[role_key]
		var flat: Variant = TownDesign.to_vector2(data.get("pos", null))
		var footprint: Variant = TownDesign.to_vector2(data.get("footprint", null))
		var size := Vector2(BIG_WIDTH, BIG_DEPTH) if footprint == null else footprint as Vector2
		var position: Vector2 = Vector2.ZERO if flat == null else flat as Vector2
		var yaw := deg_to_rad(float(data.get("yaw_deg", 0.0)))
		# El `-Z` local de la pieza mira a la calle, así que la normal de frente
		# es esa misma dirección: es la inversa exacta de
		# [method TownPlan.parcel_yaw].
		var normal := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var frontage := Vector3(position.x, 0.0, position.y) + normal * size.y * 0.5
		# Dónde se sienta el POI. Con `block` declarado manda el diseño: el lado
		# se busca **dentro de esa manzana**, que es lo que evita que la estación
		# de servicio de la manzana 6 se declare vecina de la 0 porque el lado de
		# enfrente le quedó dos centímetros más cerca. Con `block: null` el POI es
		# un lote rural —el silo— y no pertenece a ninguna manzana: toma su cota
		# del terreno y el check lo mide contra el campo, no contra una vereda.
		var rural := data.has("block") and data["block"] == null
		var wanted_block := -1
		if data.has("block") and data["block"] != null:
			wanted_block = design.block_index(StringName(String(data["block"])))
		var seat := {"block": -1, "street": -1}
		if not rural:
			seat = _seat_of(edges, frontage, wanted_block)
		var node_name := TownPlan.SCHOOL_NODE
		if role == TownPlan.Role.LANDMARK:
			node_name = TownPlan.LANDMARK_NODE
		elif role == TownPlan.Role.MEDIUM:
			node_name = StringName("%s%d" % [TownPlan.MEDIUM_PREFIX, mediums])
			mediums += 1
		plan.parcels.append({
			"block": int(seat["block"]),
			"role": role,
			"piece": piece,
			"frontage_point": frontage,
			"frontage_normal": normal,
			"depth": size.y,
			"width": size.x,
			"height_scale": float(data.get("height_scale", 1.0)),
			"variant": int(data.get("variant", 0)),
			"destructible": true,
			"name": node_name,
			"hp": float(TownPlan.ROLE_HP.get(role, 0.0)),
			"street": int(seat["street"]),
			# En un lote rural **no hay vereda**: el silo y el galpón se apoyan
			# sobre el pasto. Sumarles [constant TownPlan.SIDEWALK_TOP] —los
			# 18 cm de losa con los que apoya una casa del pueblo— los dejaba
			# flotando esos mismos 18 cm sobre el campo, que desde el aire se lee
			# como una sombra despegada (WP-D4a, hallazgo 6).
			"base_y": _ground_y(terrain, position) if rural \
					else _base_y(plan, int(seat["block"])),
			"rural": rural,
			"color": int(data.get("color", 0)),
			"design_id": StringName(String(data.get("id", ""))),
			"name_key": StringName(String(data.get("name_key", ""))),
			"silhouette": StringName(String(data.get("silhouette", ""))),
		})


## Sobre qué frente se apoya el punto [param frontage]: la manzana y la calle del
## lado de manzana más cercano.
##
## Con [param only_block] mayor o igual que cero la búsqueda se limita a los
## lados de esa manzana: el diseño ya dijo en cuál va, y lo único que queda por
## averiguar es a qué calle da.
static func _seat_of(edges: Array[Dictionary], frontage: Vector3,
		only_block: int = -1) -> Dictionary:
	var flat := Vector2(frontage.x, frontage.z)
	var best := INF
	var found := {"block": only_block, "street": -1}
	for edge: Dictionary in edges:
		if only_block >= 0 and int(edge["block"]) != only_block:
			continue
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		var delta := b - a
		var span := delta.length_squared()
		if span <= 0.0001:
			continue
		var t := clampf((flat - a).dot(delta) / span, 0.0, 1.0)
		var distance := flat.distance_to(a + delta * t)
		if distance < best:
			best = distance
			found = {"block": int(edge["block"]), "street": int(edge["street"])}
	return found


## Las casas declaradas de cada manzana, sobre el lado al que dan y en el `t` que
## dicen.
static func _place_houses(plan: TownPlan, design: TownDesign,
		edges: Array[Dictionary]) -> void:
	var by_block: Dictionary[int, Dictionary] = {}
	for edge: Dictionary in edges:
		var block := int(edge["block"])
		if not by_block.has(block):
			by_block[block] = {}
		var lookup: Dictionary = by_block[block]
		if not lookup.has(int(edge["street"])):
			lookup[int(edge["street"])] = edge

	for block: int in design.block_count():
		var entry := design.block(block)
		var houses: Array[Dictionary] = entry["houses"]
		var lookup: Dictionary = by_block.get(block, {})
		for slot: int in houses.size():
			var house := houses[slot]
			var street := int(house["front"])
			if not lookup.has(street):
				push_error("TownPlanner: la manzana '%s' no tiene lado sobre la calle %d"
						% [entry["id"], street])
				continue
			var piece := StringName(house["piece"])
			if TownDesign.piece_class(piece) != &"building":
				push_warning("TownPlanner: la casa %d de '%s' pide la pieza '%s': se omite."
						% [slot, entry["id"], piece])
				continue
			var edge: Dictionary = lookup[street]
			var a: Vector2 = edge["a"]
			var b: Vector2 = edge["b"]
			var point := a.lerp(b, float(house["t"]))
			var normal: Vector2 = edge["normal"]
			var width := float(house["width"])
			if width <= 0.0:
				width = HOUSE_WIDTH_TARGET
			var height_scale := float(house["height_scale"])
			if height_scale <= 0.0:
				height_scale = lerpf(HOUSE_SCALE_MIN, HOUSE_SCALE_MAX,
						_unit(design, [SALT_HOUSE, block, slot, 1]))
			var swing := _unit(design, [SALT_HOUSE, block, slot, 2]) * 2.0 - 1.0
			var jitter := atan2(HOUSE_YAW_JITTER * swing, maxf(width, 1.0) * 0.5)
			plan.parcels.append({
				"block": block,
				"role": TownPlan.Role.HOUSE,
				"piece": piece,
				"frontage_point": Vector3(point.x, 0.0, point.y),
				"frontage_normal": Vector3(normal.x, 0.0, normal.y),
				"depth": HOUSE_DEPTH,
				"width": width,
				"height_scale": height_scale,
				"variant": int(house["variant"]),
				"destructible": true,
				# El nombre es **posicional**: `Building_House_07_02` es la casa 2
				# de la manzana 7 y lo sigue siendo aunque se agregue una casa en
				# la manzana 3. Con un contador corrido, insertar una casa
				# renombraba a todas las de atrás y el `diff` del pueblo horneado
				# dejaba de decir nada.
				"name": StringName("%s%02d_%02d" % [TownPlan.HOUSE_PREFIX, block, slot]),
				"hp": float(TownPlan.ROLE_HP.get(TownPlan.Role.HOUSE, 0.0)),
				"street": street,
				"base_y": _base_y(plan, block),
				"color": int(house["color"]),
				"state": StringName(house["state"]),
				"garden": bool(house["garden"]),
				"tree": StringName(house["tree"]),
				"door_open": bool(house["door_open"]),
				"fence": StringName(house["fence"]),
				"yaw_jitter": jitter,
			})


## A qué altura apoya un edificio de la manzana [param block]: la cota civil de
## la manzana más el espesor de la vereda.
static func _base_y(plan: TownPlan, block: int) -> float:
	return plan.block_datum_of(block) + TownPlan.SIDEWALK_TOP


# --------------------------------------------------------------------------
# 5. Caseríos
# --------------------------------------------------------------------------

## Las casas de caserío declaradas: fuera del círculo, sobre la ruta y sin
## [Building].
##
## No son destructibles: no tienen perfil, ni etapas, ni HP, y `CityIntegrity` no
## las cuenta. Están para que el pueblo tenga de dónde venir y adónde ir, que es
## lo que un pueblo de ruta necesita para no parecer una maqueta flotando en un
## descampado.
## [param terrain] es el relieve horneado, o `null`. Una casa de caserío no
## tiene manzana de la que tomar la cota —está en pleno campo—, así que su
## `base_y` **es** la altura del terreno bajo ella. `tools/build_terrain.gd` le
## aplana un pad debajo justamente para que las cuatro esquinas apoyen ahí.
static func _place_hamlets(plan: TownPlan, design: TownDesign, terrain: Object = null) -> void:
	var index := 0
	for entry: Variant in design.decor_houses():
		var data: Dictionary = entry
		var piece := StringName(String(data.get("piece", "")))
		if TownDesign.piece_class(piece) != &"building":
			push_warning("TownPlanner: la casa de caserío %d pide la pieza '%s': se omite."
					% [index, piece])
			continue
		var flat: Variant = TownDesign.to_vector2(data.get("pos", null))
		var position: Vector2 = Vector2.ZERO if flat == null else flat as Vector2
		var yaw := deg_to_rad(float(data.get("yaw_deg", 0.0)))
		var normal := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var width := float(data.get("width", 0.0))
		if width <= 0.0:
			width = HOUSE_WIDTH_TARGET
		var height_scale := float(data.get("height_scale", 0.0))
		if height_scale <= 0.0:
			height_scale = lerpf(HOUSE_SCALE_MIN, HOUSE_SCALE_MAX,
					_unit(design, [SALT_DECOR, index, 0, 0]))
		plan.parcels.append({
			"block": -1,
			"role": TownPlan.Role.DECOR,
			"piece": piece,
			# La huella **es la casa**: se adelanta media profundidad desde donde
			# va a quedar el centro para que `parcel_position()` la deje justo
			# donde el diseño la puso.
			"frontage_point": Vector3(position.x, 0.0, position.y) + normal * HOUSE_DEPTH * 0.5,
			"frontage_normal": normal,
			"depth": HOUSE_DEPTH,
			"width": width,
			"height_scale": height_scale,
			"variant": int(data.get("variant", 0)),
			"destructible": false,
			"name": StringName("%s%02d" % [TownPlan.DECOR_PREFIX, index]),
			"hp": 0.0,
			"street": 0,
			"base_y": _ground_y(terrain, position),
			"color": int(data.get("color", 0)),
		})
		index += 1


## Altura del terreno en [param flat], o `0` sin terreno conectado.
static func _ground_y(terrain: Object, flat: Vector2) -> float:
	if terrain == null or not terrain.has_method("height_at"):
		return 0.0
	return float(terrain.call("height_at", flat.x, flat.y))


# --------------------------------------------------------------------------
# 6. Marcadores
# --------------------------------------------------------------------------

## Apariciones del coloso, puestos de pila, aparición del dron y cámara fija.
##
## Las reglas son las de WP-B; lo que cambió es de dónde salen los cinco puestos
## de calle: ya no se recalculan cruzando ejes —que era la misma cuenta hecha dos
## veces— sino que **son nodos del grafo**.
static func _place_markers(plan: TownPlan, design: TownDesign, graph: Dictionary) -> void:
	var centre := plan.play_centre
	var route_centre := plan.route_centre_distance()
	var along := plan.route_tangent(route_centre)
	var left := TownPlan.left_of(along)
	var radius := plan.play_radius + SPAWN_MARGIN

	# --- Apariciones: dos sobre la ruta y dos perpendiculares -------------
	var spots: Array[Vector3] = [
		plan.route_point(_route_distance_at(plan, route_centre, radius, -1.0)),
		plan.route_point(_route_distance_at(plan, route_centre, radius, 1.0)),
		centre + left * radius,
		centre - left * radius,
	]
	var declared_enemy := _declared_markers(design, &"enemy")
	for index: int in mini(declared_enemy.size(), spots.size()):
		var flat: Vector2 = declared_enemy[index]["pos"]
		spots[index] = Vector3(flat.x, 0.0, flat.y)
	plan.spawns = []
	for spot: Vector3 in spots:
		var facing := (centre - spot).normalized()
		var basis := Basis.from_euler(Vector3(0.0, atan2(-facing.x, -facing.z), 0.0))
		plan.spawns.append(Transform3D(basis, Vector3(spot.x, 0.0, spot.z)))

	# --- Dron: sobre la ruta, del lado de adelante -----------------------
	#
	# Es el **mismo** lado que la aparición 1 del coloso, no el opuesto: los dos
	# salen de recorrer la ruta hacia adelante. El jugador entra por donde va a
	# entrar el jefe, que es lo que hace que la primera ronda empiece con los dos
	# mirándose.
	var drone_at := _route_distance_at(plan, route_centre, DRONE_DISTANCE, 1.0)
	var drone_point := plan.route_point(drone_at)
	var declared_drone := _declared_markers(design, &"drone")
	if not declared_drone.is_empty():
		var flat: Vector2 = declared_drone[0]["pos"]
		drone_point = Vector3(flat.x, 0.0, flat.y)
	var to_town := (centre - drone_point).normalized()
	plan.drone = Transform3D(
			Basis.from_euler(Vector3(0.0, atan2(-to_town.x, -to_town.z), 0.0)),
			Vector3(drone_point.x, DRONE_HEIGHT, drone_point.z))

	# --- Cámara fija ------------------------------------------------------
	var camera_dir := (along * 0.55 + left * 0.84).normalized()
	var camera_at := centre + camera_dir * CAMERA_DISTANCE + Vector3.UP * CAMERA_HEIGHT
	var declared_camera := _declared_markers(design, &"camera")
	if not declared_camera.is_empty():
		var flat: Vector2 = declared_camera[0]["pos"]
		camera_at = Vector3(flat.x, CAMERA_HEIGHT, flat.y)
	var look := (centre - camera_at).normalized()
	plan.camera = Transform3D(Basis.looking_at(look, Vector3.UP), camera_at)

	# --- Puestos de pila --------------------------------------------------
	#
	# Los puestos declarados van **primero** y los sorteados rellenan lo que
	# falte hasta [constant POSTS_STREET]. Que reemplacen y no se sumen es lo que
	# mantiene los ocho puestos de `docs/09` —cinco de calle y tres de azotea—
	# mientras la gramática «toldo naranja = pila» de `docs/17` §4 decide dónde
	# están los primeros: un sorteo sobre los cruces del grafo no sabe dónde hay
	# un toldo, y sumarlos daría doce pilas y una ronda regalada.
	plan.battery = PackedVector3Array()
	plan.battery_roof_parcels = PackedInt32Array()
	var street_posts: Array[Vector3] = []
	for marker: Dictionary in _declared_markers(design, &"battery"):
		if street_posts.size() >= POSTS_STREET:
			break
		var flat: Vector2 = marker["pos"]
		street_posts.append(Vector3(flat.x, 0.0, flat.y))
	for point: Vector3 in _street_posts(plan, graph):
		if street_posts.size() >= POSTS_STREET:
			break
		street_posts.append(point)
	for slot: int in mini(POSTS_STREET, street_posts.size()):
		var point: Vector3 = street_posts[slot]
		plan.battery.append(Vector3(point.x,
				lerpf(POST_STREET_Y_MIN, POST_STREET_Y_MAX,
				_unit(design, [SALT_POST, slot, 0, 0])), point.z))
		plan.battery_roof_parcels.append(-1)
	for parcel: int in _roof_parcels(plan):
		if plan.battery.size() >= POSTS_STREET + POSTS_ROOF:
			break
		var position := plan.parcel_position(parcel)
		var piece: StringName = plan.parcels[parcel].get("piece", &"")
		var height := float(PIECE_HEIGHT.get(piece, 12.5)) \
				* float(plan.parcels[parcel].get("height_scale", 1.0))
		plan.battery.append(Vector3(position.x, position.y + height + POST_ROOF_CLEARANCE,
				position.z))
		plan.battery_roof_parcels.append(parcel)


## Los marcadores de clase [param kind] que declara el diseño, en orden y ya con
## la posición normalizada a [Vector2].
static func _declared_markers(design: TownDesign, kind: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Variant in design.markers():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = entry
		if StringName(String(data.get("kind", ""))) != kind:
			continue
		var flat: Variant = TownDesign.to_vector2(data.get("pos", null))
		if flat == null:
			continue
		found.append({"pos": flat as Vector2,
				"yaw": deg_to_rad(float(data.get("yaw_deg", 0.0)))})
	return found


## Distancia sobre la ruta a la que ésta corta el círculo de [param radius],
## buscando desde [param from] hacia [param direction].
##
## Se resuelve por bisección y no en cerrado a propósito: la ruta es una
## polilínea con quiebres y el corte puede caer en cualquiera de los tramos.
## Cuarenta pasos dejan el error por debajo del milímetro.
static func _route_distance_at(plan: TownPlan, from: float, radius: float,
		direction: float) -> float:
	var low := from
	var high := from + direction * (radius * 2.5 + 200.0)
	for _step: int in 40:
		var mid := (low + high) * 0.5
		if plan.distance_to_centre(plan.route_point(mid)) < radius:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5


## Los cruces de calle que llevan puesto de pila: nodos del grafo de grado dos o
## más dentro del círculo, de los más céntricos a los más periféricos.
##
## Se toman de a uno salteado para que los cinco puestos no queden todos pegados
## al centro: concentrarlos ahí bajaba la duración media de `balance_check`
## (`docs/10` §1, nota de WP-24b).
static func _street_posts(plan: TownPlan, graph: Dictionary) -> Array[Vector3]:
	var nodes: Array[Dictionary] = graph["nodes"]
	var found: Array[Dictionary] = []
	for node: Dictionary in nodes:
		var streets: PackedInt32Array = node["streets"]
		if streets.size() < 2:
			continue
		var point: Vector3 = node["pos"]
		if not plan.is_inside(point):
			continue
		found.append({"point": point, "key": plan.distance_to_centre(point)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["key"]), float(b["key"])):
			return float(a["key"]) < float(b["key"])
		var pa: Vector3 = a["point"]
		var pb: Vector3 = b["point"]
		return pa.x * 1000.0 + pa.z < pb.x * 1000.0 + pb.z)
	var spread: Array[Vector3] = []
	var step := maxi(found.size() / maxi(POSTS_STREET, 1), 1)
	var cursor := 0
	while spread.size() < POSTS_STREET and cursor < found.size():
		spread.append(found[cursor]["point"])
		cursor += step
	for entry: Dictionary in found:
		if spread.size() >= POSTS_STREET:
			break
		var point: Vector3 = entry["point"]
		if not spread.has(point):
			spread.append(point)
	return spread


## Las tres parcelas cuya azotea lleva puesto de pila: escuela, hito y el mediano
## más alto. Son los únicos techos a los que el dron llega.
static func _roof_parcels(plan: TownPlan) -> Array[int]:
	var found: Array[int] = []
	var school := plan.school_parcel()
	if school >= 0:
		found.append(school)
	for index: int in plan.parcels_of_role(TownPlan.Role.LANDMARK):
		found.append(index)
	for index: int in plan.parcels_of_role(TownPlan.Role.MEDIUM):
		if found.size() >= POSTS_ROOF:
			break
		found.append(index)
	return found


# --------------------------------------------------------------------------
# 7. Rocas y maleza
# --------------------------------------------------------------------------

## Las rocas declaradas.
##
## Dónde va cada una es una decisión de diseño —no pueden tapar el cono de visión
## inicial del dron ni caerse sobre la calzada— y por eso están en el JSON: en
## WP-21 una roca sorteada de cuarenta metros tapaba media pantalla en el primer
## fotograma de la ronda.
static func _place_rocks(plan: TownPlan, design: TownDesign) -> void:
	plan.rocks = PackedVector3Array()
	var list := design.rocks()
	for index: int in list.size():
		var data: Dictionary = list[index]
		var piece := StringName(String(data.get("piece", "")))
		if TownDesign.piece_class(piece) != &"rock":
			push_warning("TownPlanner: la roca %d pide la pieza '%s': se omite." % [index, piece])
			continue
		var flat: Variant = TownDesign.to_vector2(data.get("pos", null))
		if flat == null:
			continue
		var point: Vector2 = flat
		plan.rocks.append(Vector3(point.x, 0.0, point.y))


## Maleza, basura y barriles: dentro del pueblo sobre las manzanas y afuera sobre
## el campo, siempre lejos de la calzada.
##
## Es lo único que se siembra sin declarar, y aun así **no** con una semilla: la
## mata número 41 sale de mezclar el hash del diseño con el 41, así que agregar
## una casa al diseño no vuelve a barajar las noventa y seis matas.
static func _place_decor(plan: TownPlan, design: TownDesign) -> void:
	plan.decor = []
	var reach := plan.play_radius + 220.0
	var clearance := plan.route_width * 0.5 + plan.route_shoulder + 1.5
	var attempts := 0
	while plan.decor.size() < DECOR_SPOTS and attempts < DECOR_SPOTS * 12:
		var slot := plan.decor.size()
		attempts += 1
		var angle := _unit(design, [SALT_DECOR, slot, 1, attempts]) * TAU
		var radius := sqrt(_unit(design, [SALT_DECOR, slot, 2, attempts])) * reach
		var spot := plan.play_centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
		if plan.route_offset(spot) < clearance:
			continue
		var scale := lerpf(0.6, 1.5, _unit(design, [SALT_DECOR, slot, 3, attempts]))
		var basis := Basis.from_euler(Vector3(0.0,
				_unit(design, [SALT_DECOR, slot, 4, attempts]) * TAU, 0.0)) \
				* Basis.from_scale(Vector3(scale,
				lerpf(0.7, 1.6, _unit(design, [SALT_DECOR, slot, 5, attempts])), scale))
		plan.decor.append(Transform3D(basis, Vector3(spot.x, 0.0, spot.z)))


# --------------------------------------------------------------------------
# Variación posicional
# --------------------------------------------------------------------------

## Flotante en `[0, 1)` determinista a partir de la semilla de variación del
## diseño y de **dónde** está lo que se está variando.
##
## Dos decisiones, y las dos importan:
##
## - la semilla es `variation_seed` y **no** el hash del diseño. Con el hash,
##   cambiarle el color a una casa —que cambia el hash— habría vuelto a barajar
##   el giro y la altura de las otras cuarenta y cinco, que es justo lo que la
##   variación posicional existe para evitar. `variation_seed` es el único número
##   del JSON cuyo trabajo es barajar, y se toca a propósito;
## - las llaves son siempre un índice —manzana, sitio, canal— y nunca un
##   contador: un contador global vuelve a barajar el pueblo entero cada vez que
##   se agrega una casa, y entonces el `diff` del pueblo horneado deja de decir
##   qué cambió.
static func _unit(design: TownDesign, keys: Array[int]) -> float:
	var mixed: Array[int] = [design.variation_seed()]
	mixed.append_array(keys)
	return TownPlan.mix_unit(TownPlan.mix_all(mixed))


# --------------------------------------------------------------------------
# 8. Plaza (P2c, WP-D2)
# --------------------------------------------------------------------------

## La plaza: una manzana sin casas con su propio piso.
##
## No es una parcela ni un edificio: es un **polígono** y una lista de props. El
## plano la guarda aparte de [member TownPlan.blocks] porque la manzana sigue
## existiendo —tiene vereda, cordón y cota civil como cualquier otra— y lo que
## cambia es que adentro no hay lotes sino piso, canteros y bancos.
##
## `plaza_block` sale de buscar qué manzana contiene su baricentro y no de
## creerle al diseño: es lo que permite a `town_plan_check` afirmar «la plaza no
## tiene casas» sin que el diseño pueda mentir sobre en qué manzana está.
static func _place_plaza(plan: TownPlan, design: TownDesign) -> void:
	plan.plaza_polygon = PackedVector2Array()
	plan.plaza_block = -1
	plan.plaza_datum = 0.0
	var plaza := design.plaza()
	if plaza.is_empty():
		return
	var polygon := TownDesign.to_vector2_list(plaza.get("polygon", null))
	if polygon.size() < 3:
		return
	plan.plaza_polygon = polygon
	var centre := TownPlan.polygon_centroid(polygon)
	for index: int in plan.block_count():
		if TownPlan.polygon_contains(plan.block_polygon(index), centre):
			plan.plaza_block = index
			break
	var datum: Variant = plaza.get("datum", "auto")
	if typeof(datum) == TYPE_FLOAT or typeof(datum) == TYPE_INT:
		plan.plaza_datum = float(datum)
	else:
		plan.plaza_datum = plan.block_datum_of(plan.plaza_block)


# --------------------------------------------------------------------------
# 9. Arboledas
# --------------------------------------------------------------------------

## Siembra las arboledas declaradas: rejilla con temblor dentro del polígono,
## respetando las holguras a calles, manzanas, huellas y ruta.
##
## El resultado se agrupa **por especie** y no por arboleda porque es lo que
## [CityGrid] necesita: un [MultiMesh] lleva una malla, así que dos arboledas que
## comparten el sauce comparten el lote de dibujo. De qué arboleda salió cada
## instancia se conserva en [member TownPlan.grove_source] para que el check
## pueda contar por arboleda.
##
## ## Determinismo posicional
##
## La llave de una celda es `(variation_seed, SALT_GROVE, arboleda, ix, iz)` y
## los índices de celda son **absolutos sobre el mundo**, no relativos al
## polígono: agrandar la arboleda agrega celdas y no mueve ni una de las que ya
## estaban, y dos arboledas distintas nunca comparten llave aunque se toquen. Es
## la misma propiedad que WP-T3 le dio a las casas, y por el mismo motivo: sin
## ella, agregar un árbol volvería a barajar el bosque y el `diff` del pueblo
## horneado dejaría de decir qué cambió.
static func _place_groves(plan: TownPlan, design: TownDesign) -> void:
	plan.grove_species = PackedStringArray()
	plan.grove_points = []
	plan.grove_yaws = []
	plan.grove_scales = []
	plan.grove_source = []
	var groves := design.groves()
	if groves.is_empty():
		return

	var footprints: Array[PackedVector2Array] = []
	for index: int in plan.parcels.size():
		footprints.append(plan.parcel_footprint(index))

	for index: int in groves.size():
		var grove: Dictionary = groves[index]
		var polygon := TownDesign.to_vector2_list(grove.get("polygon", null))
		var density := float(grove.get("density", 0.0))
		var species := design.grove_species(index)
		if polygon.size() < 3 or density <= 0.0 or species.is_empty():
			continue
		var clear := design.grove_clear(index)
		# Una instancia por celda: el lado de la celda es el inverso de la raíz de
		# la densidad, que es lo que hace que «0,018 por metro cuadrado» dé 0,018
		# por metro cuadrado.
		var cell := 1.0 / sqrt(density)
		var spacing := float(grove.get("min_spacing", 0.0))
		var low := polygon[0]
		var high := polygon[0]
		for point: Vector2 in polygon:
			low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
			high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
		var weight_total := 0.0
		for choice: Dictionary in species:
			weight_total += maxf(float(choice["weight"]), 0.0)
		if weight_total <= 0.0:
			continue

		for iz: int in range(floori(low.y / cell), ceili(high.y / cell) + 1):
			for ix: int in range(floori(low.x / cell), ceili(high.x / cell) + 1):
				var jitter_x := (_unit(design, [SALT_GROVE, index, ix, iz, 0]) - 0.5) \
						* 2.0 * GROVE_JITTER
				var jitter_z := (_unit(design, [SALT_GROVE, index, ix, iz, 1]) - 0.5) \
						* 2.0 * GROVE_JITTER
				var spot := Vector2((float(ix) + 0.5 + jitter_x) * cell,
						(float(iz) + 0.5 + jitter_z) * cell)
				if not Geometry2D.is_point_in_polygon(spot, polygon):
					continue
				if not _grove_spot_free(plan, footprints, spot, clear):
					continue
				var roll := _unit(design, [SALT_GROVE, index, ix, iz, 2]) * weight_total
				var slot := species.size() - 1
				for choice: int in species.size():
					roll -= maxf(float(species[choice]["weight"]), 0.0)
					if roll <= 0.0:
						slot = choice
						break
				var piece := StringName(species[slot]["piece"])
				if spacing > 0.0 and _grove_crowded(design, index, ix, iz, cell, spacing,
						polygon):
					continue
				var bucket := _grove_bucket(plan, piece)
				plan.grove_points[bucket].append(Vector3(spot.x, 0.0, spot.y))
				plan.grove_yaws[bucket].append(
						_unit(design, [SALT_GROVE, index, ix, iz, 3]) * TAU)
				plan.grove_scales[bucket].append(lerpf(GROVE_SCALE_MIN, GROVE_SCALE_MAX,
						_unit(design, [SALT_GROVE, index, ix, iz, 4])))
				plan.grove_source[bucket].append(index)


## Verdadero si la celda `(ix, iz)` tiene un vecino **ya decidido** a menos de
## [param spacing] metros.
##
## «Ya decidido» quiere decir con orden lexicográfico `(iz, ix)` menor: la celda
## que cede es siempre la segunda, y cuál es la segunda no depende de en qué
## orden se recorra la rejilla sino de los dos índices. Eso es lo que conserva el
## determinismo posicional: la decisión de una celda mira sólo a sus ocho
## vecinas, y las ocho se calculan con la misma fórmula pura que ella.
##
## Existe porque las copas importan: los sauces de WP-D1 miden 5,25 × 4,5 m de
## huella y 8,5 m de alto, y dos a metro y medio no son dos árboles sino un
## borrón. La rejilla con temblor sola no lo garantiza —dos celdas vecinas pueden
## acercarse el doble del temblor— y bajar el temblor hasta que lo garantizara
## habría devuelto la rejilla a la vista.
## [param design] es de quien salen las llaves del temblor; [param grove] es el
## índice de la arboleda, `(ix, iz)` la celda que pregunta, [param cell] el lado
## de celda en metros, [param spacing] la separación mínima entre instancias y
## [param polygon] el contorno de la arboleda, que hace falta porque una vecina
## que cayó fuera del polígono no existe y por lo tanto no aprieta.
static func _grove_crowded(design: TownDesign, grove: int, ix: int, iz: int,
		cell: float, spacing: float, polygon: PackedVector2Array) -> bool:
	var mine := _grove_point(design, grove, ix, iz, cell)
	for dz: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if dz > 0 or (dz == 0 and dx >= 0):
				continue
			var other := _grove_point(design, grove, ix + dx, iz + dz, cell)
			if not Geometry2D.is_point_in_polygon(other, polygon):
				continue
			if mine.distance_to(other) < spacing:
				return true
	return false


## Dónde cae la instancia de la celda `(ix, iz)`, sin mirar nada más que sus
## índices. Es la función pura de la que depende todo el determinismo posicional
## de las arboledas.
static func _grove_point(design: TownDesign, grove: int, ix: int, iz: int,
		cell: float) -> Vector2:
	var jitter_x := (_unit(design, [SALT_GROVE, grove, ix, iz, 0]) - 0.5) * 2.0 * GROVE_JITTER
	var jitter_z := (_unit(design, [SALT_GROVE, grove, ix, iz, 1]) - 0.5) * 2.0 * GROVE_JITTER
	return Vector2((float(ix) + 0.5 + jitter_x) * cell, (float(iz) + 0.5 + jitter_z) * cell)


## El cajón de la especie [param piece], creándolo si hace falta.
static func _grove_bucket(plan: TownPlan, piece: StringName) -> int:
	for index: int in plan.grove_species.size():
		if StringName(plan.grove_species[index]) == piece:
			return index
	plan.grove_species.append(String(piece))
	plan.grove_points.append(PackedVector3Array())
	plan.grove_yaws.append(PackedFloat32Array())
	plan.grove_scales.append(PackedFloat32Array())
	plan.grove_source.append(PackedInt32Array())
	return plan.grove_species.size() - 1


## Verdadero si en [param spot] se puede plantar: fuera de toda franja de calle,
## fuera de las manzanas, lejos de las huellas y lejos del eje de la ruta.
##
## Las holguras se miden **desde el borde de la cosa**, no desde su eje: a la
## calle se le suma su media franja, a la manzana su polígono y a la casa su
## huella. Un número que dijera «seis metros del eje» significaría cosas
## distintas en una calle de nueve metros y en la ruta de dieciséis.
static func _grove_spot_free(plan: TownPlan, footprints: Array[PackedVector2Array],
		spot: Vector2, clear: Dictionary[StringName, float]) -> bool:
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		if axis.size() < 2:
			continue
		var margin := plan.street_half_of(street) + (
				float(clear.get(&"route", 0.0)) if street == 0
				else float(clear.get(&"streets", 0.0)))
		if TownPlan.polyline_distance(axis, spot) < margin:
			return false
	var block_clear := float(clear.get(&"blocks", 0.0))
	for block: int in plan.block_count():
		if TownPlan.polygon_inset(plan.block_polygon(block), spot) > -block_clear:
			return false
	var house_clear := float(clear.get(&"houses", 0.0))
	for footprint: PackedVector2Array in footprints:
		if footprint.size() < 3:
			continue
		if TownPlan.polygon_inset(footprint, spot) > -house_clear:
			return false
	return true


# --------------------------------------------------------------------------
# 10. Cercos de línea
# --------------------------------------------------------------------------

## Convierte cada polilínea de cerco en tramos de pieza entera, con hueco donde
## cruza una calzada.
##
## Un tramo es un punto y un rumbo: las piezas de WP-D1 corren a lo largo de `+X`
## desde su origen, así que un cerco de ciento veinte metros son veinte tramos
## seguidos y no una malla a medida. El resto de la polilínea —lo que sobra
## después del último tramo entero— se deja sin cerco: un poste a medio metro
## del siguiente se lee como un error, y medio tramo estirado rompe la escala
## del alambre.
##
## El hueco en las calles no es cosmético: un alambrado que cruza la calzada es
## lo primero que delata que el pueblo lo dibujó un programa.
static func _place_fences(plan: TownPlan, design: TownDesign) -> void:
	plan.fence_points = PackedVector3Array()
	plan.fence_yaws = PackedFloat32Array()
	plan.fence_kinds = PackedInt32Array()
	for index: int in design.fences().size():
		var fence: Dictionary = design.fences()[index]
		var line := TownDesign.to_vector2_list(fence.get("polyline", null))
		var kind := StringName(String(fence.get("kind", "")))
		var slot := TownDesign.FENCE_LINE_KINDS.find(kind)
		if line.size() < 2 or slot < 0:
			continue
		var span := float(TownDesign.FENCE_SPAN.get(kind, 0.0))
		if span <= 0.0:
			continue
		var gap := bool(fence.get("gap_at_streets", true))
		for segment: int in line.size() - 1:
			var a := line[segment]
			var b := line[segment + 1]
			var length := a.distance_to(b)
			if length < span:
				continue
			var direction := (b - a) / length
			var yaw := atan2(-direction.y, direction.x)
			for piece: int in floori(length / span):
				var start := a + direction * (float(piece) * span)
				var middle := start + direction * (span * 0.5)
				if gap and _crosses_street(plan, middle):
					continue
				plan.fence_points.append(Vector3(start.x, 0.0, start.y))
				plan.fence_yaws.append(yaw)
				plan.fence_kinds.append(slot)


## Verdadero si [param point] cae dentro de la franja de alguna calle, con el
## hueco de [constant FENCE_STREET_GAP] metros de más a cada lado.
static func _crosses_street(plan: TownPlan, point: Vector2) -> bool:
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		if axis.size() < 2:
			continue
		if TownPlan.polyline_distance(axis, point) \
				< plan.street_half_of(street) + FENCE_STREET_GAP:
			return true
	return false


# --------------------------------------------------------------------------
# 11. Props posicionales
# --------------------------------------------------------------------------

## Los props: los que el diseño declara sueltos, los de la plaza y los que
## cuelgan de cada casa (el árbol del patio y el cerco del frente).
##
## Los tres caminos terminan en la misma lista porque son la misma cosa —una
## pieza, un punto y un rumbo— y separarlos habría obligado a [CityGrid] a
## recorrer tres listas para juntar las instancias de la misma pieza en un
## [MultiMesh].
##
## El cerco del frente **no** entra en la lista de props sino en los tramos de
## cerco: un cerco de doce metros son cuatro piezas de tres, y ponerlas acá las
## dejaría fuera del [MultiMesh] del alambrado por el que ya pagamos.
static func _place_props(plan: TownPlan, design: TownDesign) -> void:
	plan.prop_placements = []
	for index: int in design.props().size():
		var data: Dictionary = design.props()[index]
		_append_prop(plan, data, &"design")
	for index: int in design.plaza_props().size():
		var data: Dictionary = design.plaza_props()[index]
		_append_prop(plan, data, &"plaza")
	_place_house_props(plan, design)


## Una entrada de prop del diseño, ya normalizada.
static func _append_prop(plan: TownPlan, data: Dictionary, source: StringName) -> void:
	var piece := StringName(String(data.get("piece", "")))
	if piece == &"" or TownDesign.piece_class(piece) == &"":
		push_warning("TownPlanner: el prop '%s' de '%s' no nombra una pieza conocida: se omite."
				% [piece, source])
		return
	var flat: Variant = TownDesign.to_vector2(data.get("pos", null))
	if flat == null:
		return
	var point: Vector2 = flat
	plan.prop_placements.append({
		"piece": piece,
		"pos": Vector3(point.x, float(data.get("lift", 0.0)), point.y),
		"yaw": deg_to_rad(float(data.get("yaw_deg", 0.0))),
		"on_terrain": bool(data.get("on_terrain", true)),
		"align": bool(data.get("align_to_slope", false)),
		"source": source,
	})


## El árbol del patio de cada casa que lo declara, y el cerco de su frente.
##
## El árbol va **detrás** de la casa, a [constant GARDEN_TREE_DEPTH] metros de la
## línea municipal: el lote mide 5,4 m de fondo y la casa lo ocupa entero, así
## que el patio es lo que queda entre la casa y el corazón de la manzana. El
## giro es posicional: la casa 2 de la manzana 7 tiene siempre su árbol torcido
## igual.
static func _place_house_props(plan: TownPlan, design: TownDesign) -> void:
	for index: int in plan.parcels.size():
		var parcel := plan.parcels[index]
		if int(parcel.get("role", -1)) != TownPlan.Role.HOUSE:
			continue
		var block := int(parcel.get("block", -1))
		var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
		var front: Vector3 = parcel.get("frontage_point", Vector3.ZERO)
		var width := float(parcel.get("width", 0.0))
		var along := Vector3(-normal.z, 0.0, normal.x)

		var tree := StringName(parcel.get("tree", &""))
		if tree != &"" and bool(parcel.get("garden", false)):
			var side := _unit(design, [SALT_PROP, block, index, 0]) - 0.5
			var spot := front - normal * GARDEN_TREE_DEPTH + along * (side * width * 0.5)
			plan.prop_placements.append({
				"piece": tree,
				"pos": Vector3(spot.x, 0.0, spot.z),
				"yaw": _unit(design, [SALT_PROP, block, index, 1]) * TAU,
				"on_terrain": true,
				"align": false,
				"source": StringName(parcel.get("name", &"")),
			})

		var fence := StringName(parcel.get("fence", &""))
		var slot := TownDesign.FENCE_LINE_KINDS.find(fence)
		if slot < 0 or width <= 0.0:
			continue
		var span := float(TownDesign.FENCE_SPAN.get(fence, 0.0))
		if span <= 0.0:
			continue
		# El cerco corre sobre el frente del lote, corrido unos centímetros hacia
		# adentro para no pisar el cordón. Se cuentan piezas enteras: un cerco de
		# 11,9 m con piezas de 3 m lleva tres y deja el hueco del portón.
		var yaw := atan2(-along.z, along.x)
		# `- normal`: la normal de frente apunta **a la calle**, así que restarla
		# es meterse en el lote (WP-D4a, hallazgo 17).
		var start := front - normal * FRONT_FENCE_OFFSET - along * (width * 0.5)
		for piece: int in floori(width / span):
			var at := start + along * (float(piece) * span)
			plan.fence_points.append(Vector3(at.x, 0.0, at.z))
			plan.fence_yaws.append(yaw)
			plan.fence_kinds.append(slot)


# --------------------------------------------------------------------------
# 12. Arroyo y puente
# --------------------------------------------------------------------------

## Copia el eje del arroyo del diseño al plano.
##
## No hay nada que resolver: el cauce ya está tallado en el relieve horneado con
## **estos mismos** puntos (`tools/build_terrain.gd` los anota en
## `TownTerrain.params`), así que resolverlo otra vez acá sería abrir la puerta a
## que el agua corra por un lado y el pozo esté por otro. Lo único que hace falta
## es que [CityGrid] pueda leerlos sin abrir el `.res` del terreno.
static func _place_creek(plan: TownPlan, design: TownDesign) -> void:
	plan.creek_points = PackedVector2Array()
	plan.creek_width = 0.0
	plan.creek_depth = 0.0
	plan.creek_bank = 0.0
	var creek := design.creek()
	if creek.is_empty():
		return
	var line := TownDesign.to_vector2_list(creek.get("polyline", null))
	if line.size() < 2:
		return
	plan.creek_points = line
	plan.creek_width = float(creek.get("width", 0.0))
	plan.creek_depth = float(creek.get("depth", 0.0))
	plan.creek_bank = float(creek.get("bank", 0.0))


## El tablero del puente: dónde va, con qué rumbo y a qué cota.
##
## La cota no es la del terreno —bajo el puente el terreno **baja**, que para eso
## está el vano— sino la de la **recta entre los dos extremos del vano**, que es
## la que la calzada sigue al cruzar. Es el mismo número que [CityGrid] usa para
## levantar la cinta de la ruta dentro del vano, y vive acá para que los dos lo
## saquen del mismo sitio.
static func _place_bridge(plan: TownPlan, design: TownDesign, terrain: Object) -> void:
	plan.bridge_at = Vector3.ZERO
	plan.bridge_span = 0.0
	plan.bridge_deck_width = 0.0
	plan.bridge_yaw = 0.0
	plan.bridge_piece = &""
	var bridge := design.bridge()
	if bridge.is_empty():
		return
	var flat: Variant = TownDesign.to_vector2(bridge.get("at", null))
	var span := float(bridge.get("span", 0.0))
	var deck := float(bridge.get("deck_width", 0.0))
	if flat == null or span <= 0.0 or deck <= 0.0:
		return
	var at: Vector2 = flat
	var axis := plan.street_axis(0)
	var along := TownPlan.polyline_closest(axis, Vector3(at.x, 0.0, at.y))
	var tangent := TownPlan.polyline_tangent(axis, along)
	var half := span * 0.5 + 1.0
	var head := TownPlan.polyline_point(axis, along - half)
	var tail := TownPlan.polyline_point(axis, along + half)
	var y := (_ground_y(terrain, Vector2(head.x, head.z))
			+ _ground_y(terrain, Vector2(tail.x, tail.z))) * 0.5
	plan.bridge_at = Vector3(at.x, y, at.y)
	plan.bridge_span = span
	plan.bridge_deck_width = deck
	plan.bridge_yaw = atan2(-tangent.z, tangent.x)
	plan.bridge_piece = StringName(String(bridge.get("piece", "bridge_deck")))
