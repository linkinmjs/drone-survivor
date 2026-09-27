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
## parcela lo ocupa su `base_size.x`, que es 5,00–5,10 m en las diez piezas.
##
## Era 5,4 y la casa entraba entera con 15–20 cm de retiro contra la línea
## municipal: menos que los 30 cm a los que va el cerco del frente
## ([constant FRONT_FENCE_OFFSET]) más su medio canto, así que 45 tramos de cerco
## tocaban la fachada de su casa y 16 le atravesaban la pared (WP-L, fila E de
## `city_check`, fila A bis de `town_plan_check`). La casa se centra en el lote,
## así que agrandar el fondo la corre medio agrandamiento hacia adentro: con
## 6,16 m el tramo de cerco más justo del pueblo queda a 0,103 m de su fachada,
## y es el mínimo que deja los 0,10 que exige la fila. Con el fondo nuevo, cuatro
## lotes de esquina se tocaban con el vecino de la calle perpendicular por la
## espalda y se angostaron en `town_a.json`; ninguna casa real cambió de ancho.
const HOUSE_DEPTH: float = 6.16

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

## A cuántos metros del frente, hacia adentro del lote, va el árbol del patio
## **como mucho**.
##
## El lote mide [constant HOUSE_DEPTH] de fondo y la casa lo ocupa entero, así
## que el árbol va **detrás** de la casa: es el patio, que es donde está el
## árbol frutal y el tendedero de `docs/17` §3.
##
## Hasta P2c era una constante y se aplicaba tal cual, y eso plantó el árbol de
## `Building_House_01_03` con el tronco 0,65 m **dentro** de la pared de
## `Building_Mid_3` (WP-L, hallazgos S2/S7): con lotes de 5,4 m de fondo, diez
## metros dejan el árbol 4,6 m más allá del lote, en el corazón de manzana, que
## es justamente donde se sientan los medianos. Desde WP-L es un **tope**: la
## profundidad de verdad la decide [method _garden_tree_depth], que retrocede
## hasta que la copa despeje [constant GARDEN_TREE_CLEAR] metros de todo sólido,
## y si no hay dónde, la casa se queda sin árbol.
const GARDEN_TREE_DEPTH: float = 10.0

## Cuánto despeja la **copa** del árbol de patio de cualquier sólido y de
## cualquier otra copa, en metros.
##
## Es el mismo medio metro que exige la fila B de `tools/town_plan_check.gd`: el
## resolvedor siembra con la regla que el check mide, y no con una parecida.
const GARDEN_TREE_CLEAR: float = 0.5

## Con qué paso se prueba la profundidad del árbol de patio, en metros.
##
## Se busca de afuera hacia adentro —del tope hacia la línea municipal— y se
## toma la primera que despeja: el árbol queda lo más al fondo del patio que se
## pueda, que es donde está el árbol de una casa. Diez centímetros es más fino
## que la holgura que se exige, así que el resultado no depende del paso.
const GARDEN_TREE_STEP: float = 0.1

## Radio del casco de cada roca, en metros, medido sobre los puntos del
## `ConvexPolygonShape3D` de `world/rocks/rock_*.tscn`.
##
## Es un **radio** y no una huella orientada porque [CityGrid] le da a cada roca
## un giro sorteado (`_build_rocks`, canal `CHANNEL_YAW`): lo único que el plano
## puede afirmar de una roca girada al azar es su círculo circunscrito. Medidos:
## `rock_a` 6,07 × 7,42 m de caja y 3,87 de radio; `rock_b` 10,22 × 8,62 / 5,67;
## `rock_c` 8,74 × 11,29 / 5,78; `rock_d` 13,22 × 12,51 / 7,33; `rock_e`
## 16,12 × 14,80 / 9,69; `rock_f` 12,78 × 17,33 / 8,76.
const ROCK_RADIUS: Dictionary[StringName, float] = {
	&"rock_a": 3.87,
	&"rock_b": 5.67,
	&"rock_c": 5.78,
	&"rock_d": 7.33,
	&"rock_e": 9.69,
	&"rock_f": 8.76,
}

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
	#
	# WP-L reordenó las cinco últimas. El arroyo, el puente y los cercos se
	# copian ahora **antes** que las arboledas porque desde P2d una arboleda los
	# esquiva, y no se puede esquivar lo que todavía no está en el plano: con el
	# orden viejo `plan.creek_width` valía cero y `plan.fence_points` estaba
	# vacío cuando se sembraban los mil cuatrocientos árboles. Ninguna de las
	# tres depende de las arboledas, así que el orden nuevo no tiene vuelta.
	#
	# «Los cercos» son **todos**: los de línea del diseño y los de frente de cada
	# casa. Los de frente se sembraban en `_place_house_props`, después de las
	# arboledas, así que la siembra esquivaba unos cercos y la fila C medía
	# contra todos (revisión de WP-L, hallazgo 9). Desde la revisión los dos los
	# pone [method _place_fences], en el mismo orden que antes —primero los del
	# diseño, después los de frente por orden de parcela—, y la lista es la misma
	# para la siembra y para el check.
	_place_creek(plan, design)
	_place_bridge(plan, design, terrain)
	_place_fences(plan, design)
	_place_groves(plan, design)
	_place_props(plan, design)
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
	plan.rock_pieces = PackedStringArray()
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
		plan.rock_pieces.append(String(piece))


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

	# Las listas que se comparten entre arboledas —lotes, rocas, cercos y
	# tablero— se arman **una vez** para todo el pueblo: son las mismas para las
	# cuatro arboledas y recalcularlas por celda costaría medio millón de cuentas.
	var shared := _grove_shared(plan)
	for index: int in groves.size():
		var context := _grove_context(plan, design, index, shared)
		if context.is_empty():
			continue
		var cell := float(context["cell"])
		var low: Vector2 = context["low"]
		var high: Vector2 = context["high"]
		var species: Array[Dictionary] = context["species"]
		for iz: int in range(floori(low.y / cell), ceili(high.y / cell) + 1):
			for ix: int in range(floori(low.x / cell), ceili(high.x / cell) + 1):
				if not _grove_planted(context, ix, iz):
					continue
				var spot := _grove_point(design, index, ix, iz, cell)
				var piece := StringName(species[_grove_pick(context, ix, iz)]["piece"])
				var bucket := _grove_bucket(plan, piece)
				plan.grove_points[bucket].append(Vector3(spot.x, 0.0, spot.y))
				plan.grove_yaws[bucket].append(
						_unit(design, [SALT_GROVE, index, ix, iz, 3]) * TAU)
				plan.grove_scales[bucket].append(_grove_scale(context, ix, iz))
				plan.grove_source[bucket].append(index)


## Separación mínima **efectiva** de la arboleda [param index], en metros.
##
## Es la declarada o la suma de los dos radios de copa más grandes que la
## arboleda puede sembrar, lo que sea mayor. Los cinco metros que declaran las
## dos bandas del arroyo eran menos que **una** copa de `tree_xl`
## —6,5 m de huella por hasta [constant GROVE_SCALE_MAX] de escala, o sea 8,06 m
## de diámetro— así que dos sauces a cinco metros no eran dos sauces sino un
## borrón (WP-L, hallazgo S11). Con el piso, dos vecinas nunca se tocan.
static func grove_spacing(design: TownDesign, index: int) -> float:
	var list: Array = design.groves()
	if index < 0 or index >= list.size():
		return 0.0
	var declared := float((list[index] as Dictionary).get("min_spacing", 0.0))
	var widest := 0.0
	for choice: Dictionary in design.grove_species(index):
		widest = maxf(widest, piece_radius(StringName(choice["piece"])) * GROVE_SCALE_MAX)
	return maxf(declared, widest * 2.0)


## Cuántos metros cuadrados de la arboleda [param index] son **plantables**: los
## de las celdas que caen dentro del polígono y cuya copa despeja todo.
##
## Es la medida con la que `tools/town_plan_check.gd` pregunta por la densidad,
## y hace falta porque la banda del arroyo es un polígono centrado **en el
## cauce**: más de la mitad de su superficie es agua y orilla, y pedirle que
## siembre 0,018 árboles por metro cuadrado de polígono sería pedirle que plante
## en el agua. Lo que el diseño declara es la densidad **donde hay sitio**.
##
## Cuesta una pasada más sobre la rejilla y sólo la paga el check.
static func grove_free_area(plan: TownPlan, design: TownDesign, index: int) -> float:
	var context := _grove_context(plan, design, index, _grove_shared(plan))
	if context.is_empty():
		return 0.0
	var cell := float(context["cell"])
	var low: Vector2 = context["low"]
	var high: Vector2 = context["high"]
	var free := 0
	for iz: int in range(floori(low.y / cell), ceili(high.y / cell) + 1):
		for ix: int in range(floori(low.x / cell), ceili(high.x / cell) + 1):
			if _grove_free(context, ix, iz):
				free += 1
	return float(free) * cell * cell


## Lo que las cuatro arboledas miran igual: los lotes, las rocas, los tramos de
## cerco y el tablero del puente. Se arma una vez por plano.
static func _grove_shared(plan: TownPlan) -> Dictionary:
	return {
		"footprints": _lot_footprints(plan), "discs": rock_discs(plan),
		"segments": fence_segments(plan), "deck": bridge_rect(plan),
	}


## El contexto de siembra de la arboleda [param index]: todo lo que las
## funciones de celda necesitan saber, o un diccionario vacío si la arboleda no
## siembra nada (polígono de menos de tres vértices, densidad nula, sin especies
## o con todas las especies a peso cero).
##
## Existe para que [method _place_groves] y [method grove_free_area] —que es la
## medida con la que el check pregunta por la densidad— no puedan sembrar con
## reglas distintas: hasta la revisión de WP-L los dos armaban el contexto a mano,
## campo por campo. [param shared] es lo de [method _grove_shared].
##
## Trae dos memorias por celda: `memo` ([method _grove_free]) y `planted`
## ([method _grove_planted]).
static func _grove_context(plan: TownPlan, design: TownDesign, index: int,
		shared: Dictionary) -> Dictionary:
	var groves: Array = design.groves()
	if index < 0 or index >= groves.size():
		return {}
	var grove: Dictionary = groves[index]
	var polygon := TownDesign.to_vector2_list(grove.get("polygon", null))
	var density := float(grove.get("density", 0.0))
	var species := design.grove_species(index)
	if polygon.size() < 3 or density <= 0.0 or species.is_empty():
		return {}
	var weight_total := 0.0
	for choice: Dictionary in species:
		weight_total += maxf(float(choice["weight"]), 0.0)
	if weight_total <= 0.0:
		return {}
	# Una instancia por celda: el lado de la celda es el inverso de la raíz de la
	# densidad, que es lo que hace que «0,018 por metro cuadrado» dé 0,018 por
	# metro cuadrado.
	var cell := 1.0 / sqrt(density)
	var low := polygon[0]
	var high := polygon[0]
	for point: Vector2 in polygon:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	var spacing := grove_spacing(design, index)
	# Hasta cuántas celdas de distancia puede estar una vecina que aprieta: dos
	# celdas a `d` de distancia sobre un eje quedan, como mucho, a
	# `(d − 2 · GROVE_JITTER) · cell` metros. Con la separación de las bandas del
	# arroyo (8,1 m) y celdas de 7,45 m da una, que son las ocho vecinas.
	var reach := maxi(ceili(spacing / cell + 2.0 * GROVE_JITTER) - 1, 0)
	return {
		"plan": plan, "design": design, "grove": index, "cell": cell,
		"polygon": polygon, "low": low, "high": high,
		"clear": design.grove_clear(index),
		"species": species, "weight": weight_total,
		"footprints": shared["footprints"], "discs": shared["discs"],
		"segments": shared["segments"], "deck": shared["deck"],
		"spacing": spacing, "reach": reach, "memo": {}, "planted": {},
	}


## Los lotes del plano, que es contra lo que se mide la holgura `houses` de una
## arboleda. Es el **lote** y no la pieza a propósito: un árbol pegado a la
## medianera de un lote vacío tampoco corresponde.
static func _lot_footprints(plan: TownPlan) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for index: int in plan.parcels.size():
		out.append(plan.parcel_footprint(index))
	return out


## Qué especie le toca a la celda `(ix, iz)`, por peso acumulado.
static func _grove_pick(context: Dictionary, ix: int, iz: int) -> int:
	var species: Array[Dictionary] = context["species"]
	var roll := _unit(context["design"], [SALT_GROVE, context["grove"], ix, iz, 2]) \
			* float(context["weight"])
	for choice: int in species.size():
		roll -= maxf(float(species[choice]["weight"]), 0.0)
		if roll <= 0.0:
			return choice
	return species.size() - 1


## Escala de la instancia de la celda `(ix, iz)`.
static func _grove_scale(context: Dictionary, ix: int, iz: int) -> float:
	return lerpf(GROVE_SCALE_MIN, GROVE_SCALE_MAX,
			_unit(context["design"], [SALT_GROVE, context["grove"], ix, iz, 4]))


## Radio de la **copa** de la instancia de la celda `(ix, iz)`, en metros.
##
## Es lo que convierte una holgura medida al tronco en una holgura medida al
## borde del árbol, que es la única que se ve desde el aire.
static func _grove_crown(context: Dictionary, ix: int, iz: int) -> float:
	var species: Array[Dictionary] = context["species"]
	var piece := StringName(species[_grove_pick(context, ix, iz)]["piece"])
	return piece_radius(piece) * _grove_scale(context, ix, iz)


## Verdadero si en la celda `(ix, iz)` **entra** una instancia: cae dentro del
## polígono y su copa despeja todo. No mira a las vecinas; de eso se ocupa
## [method _grove_planted].
##
## Memoizado por celda porque [method _grove_planted] pregunta por las vecinas
## de cada celda: sin memoria, el filtro se evaluaría una vez por vecina.
static func _grove_free(context: Dictionary, ix: int, iz: int) -> bool:
	var memo: Dictionary = context["memo"]
	var key := Vector2i(ix, iz)
	if memo.has(key):
		return bool(memo[key])
	var spot := _grove_point(context["design"], context["grove"], ix, iz,
			float(context["cell"]))
	var free := Geometry2D.is_point_in_polygon(spot, context["polygon"]) \
			and _grove_spot_free(context, spot, _grove_crown(context, ix, iz))
	memo[key] = free
	return free


## Verdadero si la celda `(ix, iz)` **se planta**: entra ([method _grove_free]) y
## ninguna vecina **anterior que se haya plantado** queda a menos de la separación
## efectiva ([method grove_spacing]).
##
## «Anterior» quiere decir con orden lexicográfico `(iz, ix)` menor: la celda que
## cede es siempre la segunda, y cuál es la segunda no depende de en qué orden se
## recorra la rejilla sino de los dos índices. La respuesta es una función pura de
## los índices y del contorno, así que el determinismo sigue siendo **posicional**.
##
## Es recursiva hacia atrás y está memoizada en `context["planted"]`. Hasta la
## revisión de WP-L la memoria era de dos niveles —«¿la vecina estaba apretada
## por **su** vecina?», y ahí se cortaba— y eso no garantizaba la separación: en
## una fila L → M → N → C con 8,1 m de separación y celdas de 7,45 m, M cedía
## ante L, N se plantaba porque M no estaba, y C no veía a N —el segundo nivel
## le decía que N estaba apretada por M— y se plantaba a menos de 8,1 m de ella.
## Con la memoria de verdad cada celda sabe si su vecina **se plantó**, que es
## lo único que importa.
##
## La recursión está acotada: sólo mira vecinas anteriores, hasta `reach` celdas
## ([method _grove_context]), y una celda fuera de la caja del polígono no entra
## y corta ahí. [method _place_groves] recorre la rejilla en el mismo orden
## lexicográfico, así que cuando pregunta por una celda sus vecinas anteriores ya
## están en la memoria y la pila no pasa de un nivel.
##
## Existe porque las copas importan: los sauces de WP-D1 miden 6,5 m de huella y
## 8,5 m de alto, y dos a metro y medio no son dos árboles sino un borrón. La
## rejilla con temblor sola no lo garantiza —dos celdas vecinas pueden acercarse
## el doble del temblor— y bajar el temblor hasta que lo garantizara habría
## devuelto la rejilla a la vista.
static func _grove_planted(context: Dictionary, ix: int, iz: int) -> bool:
	var planted: Dictionary = context["planted"]
	var key := Vector2i(ix, iz)
	if planted.has(key):
		return bool(planted[key])
	var result := _grove_free(context, ix, iz)
	var spacing := float(context["spacing"])
	if result and spacing > 0.0:
		var design: TownDesign = context["design"]
		var grove := int(context["grove"])
		var cell := float(context["cell"])
		var reach := int(context["reach"])
		var mine := _grove_point(design, grove, ix, iz, cell)
		for dz: int in range(-reach, 1):
			for dx: int in range(-reach, reach + 1):
				if dz == 0 and dx >= 0:
					break
				if mine.distance_to(_grove_point(design, grove, ix + dx, iz + dz, cell)) \
						>= spacing:
					continue
				if _grove_planted(context, ix + dx, iz + dz):
					result = false
					break
			if not result:
				break
	planted[key] = result
	return result


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
static func _grove_spot_free(context: Dictionary, spot: Vector2, crown: float) -> bool:
	var plan: TownPlan = context["plan"]
	var clear: Dictionary = context["clear"]
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		if axis.size() < 2:
			continue
		var margin := plan.street_half_of(street) + crown + (
				float(clear.get(&"route", 0.0)) if street == 0
				else float(clear.get(&"streets", 0.0)))
		if TownPlan.polyline_distance(axis, spot) < margin:
			return false
	var block_clear := float(clear.get(&"blocks", 0.0)) + crown
	for block: int in plan.block_count():
		if TownPlan.polygon_inset(plan.block_polygon(block), spot) > -block_clear:
			return false
	var house_clear := float(clear.get(&"houses", 0.0)) + crown
	var footprints: Array[PackedVector2Array] = context["footprints"]
	for footprint: PackedVector2Array in footprints:
		if footprint.size() < 3:
			continue
		if TownPlan.polygon_inset(footprint, spot) > -house_clear:
			return false
	# --- lo que WP-L agregó ------------------------------------------------
	# Las rocas. Ocho instancias vivían dentro de `rock_e` y de `rock_a` —hasta
	# 6,70 m adentro del casco— porque `plan.rocks` no se consultaba (hallazgos
	# S1/S4). Son discos: [CityGrid] les sortea el rumbo, así que lo único que el
	# plano puede afirmar de una roca es su círculo.
	var rock_clear := float(clear.get(&"rocks", 0.0)) + crown
	var discs: Array[Dictionary] = context["discs"]
	for disc: Dictionary in discs:
		if spot.distance_to(disc["centre"] as Vector2) < float(disc["radius"]) + rock_clear:
			return false
	# El canal del arroyo. La banda de la arboleda está centrada **en el cauce**,
	# así que sin restar el agua caían 52 instancias adentro (hallazgo S3).
	var water := plan.creek_width * 0.5 + float(clear.get(&"water", 0.0)) + crown
	if plan.creek_width > 0.0 and creek_distance(plan, spot) < water:
		return false
	# El tablero del puente, con la holgura de manzana: es obra, no campo.
	var deck: PackedVector2Array = context["deck"]
	if deck.size() >= 3 and point_polygon_distance(deck, spot) < block_clear:
		return false
	# El alambrado. Tres instancias quedaban a 1,0–1,4 m del cierre del disco
	# (hallazgo S12): los cercos se siembran **antes** que las arboledas desde
	# WP-L, así que acá ya están todos.
	var fence_clear := float(clear.get(&"fences", 0.0)) + crown
	var segments: Array[PackedVector2Array] = context["segments"]
	if fence_distance(segments, spot) < fence_clear:
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
	_place_front_fences(plan)


## El cerco del frente de cada casa que lo declara.
##
## Corre sobre el frente del lote, corrido [constant FRONT_FENCE_OFFSET] metros
## hacia adentro para no pisar el cordón, y se cuentan piezas enteras: un cerco
## de 11,9 m con piezas de 3,6 m lleva tres y deja el hueco del portón.
##
## Va en [method _place_fences] y no con el árbol del patio porque las arboledas
## lo esquivan, y las arboledas se siembran antes que los props (ver
## [method resolve]). El orden de los tramos es el de siempre —después de los
## cercos de línea y por orden de parcela—, así que la firma no cambia por
## haberlo movido.
static func _place_front_fences(plan: TownPlan) -> void:
	for index: int in plan.parcels.size():
		var parcel := plan.parcels[index]
		if int(parcel.get("role", -1)) != TownPlan.Role.HOUSE:
			continue
		var fence := StringName(parcel.get("fence", &""))
		var slot := TownDesign.FENCE_LINE_KINDS.find(fence)
		var width := float(parcel.get("width", 0.0))
		if slot < 0 or width <= 0.0:
			continue
		var span := float(TownDesign.FENCE_SPAN.get(fence, 0.0))
		if span <= 0.0:
			continue
		var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
		var front: Vector3 = parcel.get("frontage_point", Vector3.ZERO)
		var along := Vector3(-normal.z, 0.0, normal.x)
		var yaw := atan2(-along.z, along.x)
		# `- normal`: la normal de frente apunta **a la calle**, así que restarla
		# es meterse en el lote (WP-D4a, hallazgo 17).
		var start := front - normal * FRONT_FENCE_OFFSET - along * (width * 0.5)
		for piece: int in floori(width / span):
			var at := start + along * (float(piece) * span)
			plan.fence_points.append(Vector3(at.x, 0.0, at.z))
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
		# Las dos listas blancas de WP-L. No entran en la firma del plano porque
		# no deciden dónde va el prop ni cómo se ve: son lo que el diseño le
		# **declara al check** sobre qué puede pisar este prop y ningún otro.
		"allow_overlap": TownDesign.allow_overlap_of(data),
		"on_road": TownDesign.on_road_of(data),
		"source": source,
	})


## El árbol del patio de cada casa que lo declara.
##
## El árbol va **detrás** de la casa: el lote mide [constant HOUSE_DEPTH] de
## fondo y la casa lo ocupa casi entero, así que el patio es lo que queda entre
## la casa y el corazón de la manzana. A qué profundidad lo decide
## [method _garden_tree_depth]: la más honda que despeje, con
## [constant GARDEN_TREE_DEPTH] metros de la línea municipal como **tope** y no
## como valor; si no despeja a ninguna, la casa se queda sin árbol. El lado del
## lote y el giro son posicionales: la casa 2 de la manzana 7 tiene siempre su
## árbol en el mismo costado y torcido igual.
##
## El cerco del frente ya no se siembra acá: lo pone [method _place_front_fences]
## antes que las arboledas (revisión de WP-L, hallazgo 9).
static func _place_house_props(plan: TownPlan, design: TownDesign) -> void:
	var solids := parcel_solid_list(plan)
	# Las copas ya plantadas, como discos: el árbol de la casa 3 no se puede
	# cruzar con el de la 2 (hallazgo S10, dos copas cruzadas 0,70 m). Se resuelve
	# **por orden de parcela** —la segunda es la que cede— porque el orden de
	# parcelas es posicional y no un contador: agregar una casa en la manzana 3
	# no cambia quién cede en la 11.
	var crowns: Array[Dictionary] = []
	# Y lo que ya estaba plantado antes que los props: las rocas y las copas de
	# arboleda. Es la misma regla que la fila B de `town_plan_check` mide desde la
	# revisión de WP-L (hallazgo 18); hoy ninguna arboleda llega a un patio, pero
	# el resolvedor siembra con la regla que el check mide y no con una parecida.
	var planted: Array[Dictionary] = []
	for disc: Dictionary in rock_discs(plan):
		planted.append({"centre": disc["centre"], "radius": disc["radius"]})
	for slot: int in plan.grove_species.size():
		var grove_radius := piece_radius(StringName(plan.grove_species[slot]))
		for at_index: int in plan.grove_points[slot].size():
			var at: Vector3 = plan.grove_points[slot][at_index]
			planted.append({"centre": Vector2(at.x, at.z),
					"radius": grove_radius * plan.grove_scales[slot][at_index]})
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
			var line := Vector2(front.x, front.z) \
					+ Vector2(along.x, along.z) * (side * width * 0.5)
			var crown := piece_radius(tree)
			# Sólo las copas que el árbol podría alcanzar: las mil y pico de la
			# arboleda por cada paso de profundidad serían medio millón de cuentas.
			var near: Array[Dictionary] = crowns.duplicate()
			for other: Dictionary in planted:
				if line.distance_to(other["centre"] as Vector2) < GARDEN_TREE_DEPTH \
						+ crown + float(other["radius"]) + GARDEN_TREE_CLEAR:
					near.append(other)
			var depth := _garden_tree_depth(solids, near, line,
					Vector2(normal.x, normal.z), crown)
			# Sin sitio: la casa se queda sin árbol. Es determinista —la decisión
			# sale de la geometría, no de un sorteo— y `town_plan_check` lo cuenta.
			parcel["garden_tree"] = depth > 0.0
			if depth > 0.0:
				var spot := line - Vector2(normal.x, normal.z) * depth
				crowns.append({"centre": spot, "radius": crown})
				plan.prop_placements.append({
					"piece": tree,
					"pos": Vector3(spot.x, 0.0, spot.y),
					"yaw": _unit(design, [SALT_PROP, block, index, 1]) * TAU,
					"on_terrain": true,
					"align": false,
					"allow_overlap": [] as Array[StringName],
					"on_road": false,
					"source": StringName(parcel.get("name", &"")),
				})


## A cuántos metros de la línea municipal, hacia adentro de la manzana, entra el
## árbol de patio de una casa; `0` si no entra a ninguna profundidad.
##
## [param line] es el punto del frente ya corrido a un lado del lote y
## [param normal] la normal de frente, que apunta **a la calle**: el árbol se
## busca en `line - normal · profundidad`.
##
## Se prueba de afuera hacia adentro —desde [constant GARDEN_TREE_DEPTH] hacia la
## línea municipal, de a [constant GARDEN_TREE_STEP]— y se toma la primera
## profundidad en que la copa despeja [constant GARDEN_TREE_CLEAR] metros de
## **todos** los sólidos del pueblo y de las copas ya plantadas —otros árboles
## de patio, copas de arboleda y rocas—. Buscar desde
## afuera es lo que deja el árbol lo más al fondo del patio que se pueda, que es
## donde está el árbol de una casa; buscar desde adentro lo habría pegado a la
## pared del comedor.
##
## La propia casa cuenta como sólido: es lo que impide que el árbol retroceda
## hasta meterse en la cocina cuando el corazón de manzana está ocupado. Cuando
## las dos condiciones no se pueden cumplir a la vez —el mediano de la manzana 1
## se sienta a 6,6 m del frente y no hay hueco entre él y la casa— la respuesta
## honesta es que ahí no hay patio, y la casa se queda sin árbol.
static func _garden_tree_depth(solids: Array[Dictionary], crowns: Array[Dictionary],
		line: Vector2, normal: Vector2, crown: float) -> float:
	var steps := int(GARDEN_TREE_DEPTH / GARDEN_TREE_STEP)
	for step: int in steps + 1:
		var depth := GARDEN_TREE_DEPTH - float(step) * GARDEN_TREE_STEP
		if depth <= 0.0:
			break
		var spot := line - normal * depth
		var free := true
		for solid: Dictionary in solids:
			if point_polygon_distance(solid["poly"] as PackedVector2Array, spot) \
					< crown + GARDEN_TREE_CLEAR:
				free = false
				break
		if free:
			for other: Dictionary in crowns:
				if spot.distance_to(other["centre"] as Vector2) \
						< crown + float(other["radius"]) + GARDEN_TREE_CLEAR:
					free = false
					break
		if free:
			return depth
	return 0.0


# --------------------------------------------------------------------------
# 12. Sólidos: la geometría con la que se mide qué pisa qué (WP-L, P2d)
# --------------------------------------------------------------------------
#
# Hasta P2c el plano medía solapes contra el **lote** —`TownPlan.parcel_footprint`,
# el rectángulo de 12 × 5,4 m que el diseño declara— y no contra el edificio, que
# es una pieza de 5 × 5 m plantada en el medio. Para repartir cuadras el lote es
# la medida correcta; para preguntar «¿este árbol está dentro de una pared?» es
# la equivocada por los dos lados: sobra donde el lote es más ancho que la casa y
# falta donde la pieza es más grande que el lote declarado (la estación de
# servicio, el galpón de campo).
#
# Lo de acá abajo es la otra medida: **la pieza**, con la huella del manifiesto,
# girada como la gira [CityGrid] y con su tramo de alturas. Vive en el resolvedor
# y no en el check porque las dos reglas de siembra de WP-L —la profundidad del
# árbol de patio y la holgura de una arboleda— la necesitan para **decidir**, y
# el check la necesita para **medir**: una sola fórmula para las dos cosas.

## Gira el par XZ [param flat] como lo gira sumarle [param yaw] radianes al giro
## de un nodo.
##
## No es `Vector2.rotated()`: en XZ, con la Y del motor apuntando arriba, un giro
## positivo de nodo va al revés que un giro positivo de `Vector2`. Escrito a mano
## para que el signo esté a la vista y no dependa de recordar la convención.
static func spin(flat: Vector2, yaw: float) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(flat.x * c + flat.y * s, -flat.x * s + flat.y * c)


## Huella **real** de [param piece] tal como cae sobre el plano: `x` a lo largo
## del frente y `y` hacia adentro del lote.
##
## El manifiesto la declara en el espacio local de la pieza, y una pieza de
## pueblo tiene el frente en su `-X` ([method TownDesign.piece_front]), así que
## sus dos ejes llegan cambiados. [param fallback] es lo que se devuelve cuando
## el manifiesto no conoce la pieza —los tres bloques de ciudad (`block_mid`,
## `tower_b`, `block_low_c`) no están en el manifiesto del pueblo—: ahí manda lo
## que el diseño declaró, que para esos tres es más grande que la pieza y por lo
## tanto conservador.
static func piece_plan_size(piece: StringName, fallback: Vector2) -> Vector2:
	var entry: Variant = TownDesign.manifest().get(String(piece), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return fallback
	var raw: Variant = (entry as Dictionary).get("footprint", null)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 2:
		return fallback
	var size := Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	if size.x <= 0.0 or size.y <= 0.0:
		return fallback
	return Vector2(size.y, size.x) if TownDesign.piece_front(piece) == &"-X" else size


## Radio de copa de una pieza suelta —follaje, prop o roca— en metros.
##
## Para todo lo que no es roca es **medio lado mayor** de su huella y no el
## círculo circunscrito de la caja (que sería media diagonal): la copa de un
## árbol es redonda y la huella del manifiesto es la caja que la encierra, así
## que medio lado mayor es el radio de la copa, y la media diagonal inflaría
## cada árbol un 41 % en las esquinas que no tiene. Para una caja de verdad
## —un auto, un banco— es una **subestimación**, y por eso los props no se miden
## con esto sino con [method prop_rect].
##
## Para las rocas manda [constant ROCK_RADIUS], que sale del casco de colisión y
## sí es el círculo circunscrito: [CityGrid] les sortea el rumbo y el casco no es
## redondo.
static func piece_radius(piece: StringName) -> float:
	if ROCK_RADIUS.has(piece):
		return float(ROCK_RADIUS[piece])
	var size := piece_plan_size(piece, Vector2.ZERO)
	return maxf(size.x, size.y) * 0.5


## Alto de una pieza según el manifiesto, o el de [constant PIECE_HEIGHT] si el
## manifiesto todavía no la conoce.
static func piece_top(piece: StringName) -> float:
	var height := TownDesign.piece_height(piece)
	if height > 0.0:
		return height
	return float(PIECE_HEIGHT.get(piece, 0.0))


## Las cajas en que se descompone [param piece], en su espacio local, o una
## lista vacía si la pieza es una caja sola.
##
## Sólo la estación de servicio tiene varias (WP-L): cuatro columnas, la tienda,
## la losa de la marquesina y el cartel. Que la lista viva en el manifiesto —y no
## sólo en la escena— es lo que permite al plano saber que **hay aire** bajo la
## marquesina sin abrir un `.tscn`, que es la condición para que el check del
## plano siga corriendo en `--headless` puro.
static func piece_parts(piece: StringName) -> Array:
	var entry: Variant = TownDesign.manifest().get(String(piece), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return []
	var raw: Variant = (entry as Dictionary).get("parts", null)
	return raw as Array if typeof(raw) == TYPE_ARRAY else []


## Los cuatro vértices del rectángulo orientado de centro [param centre], con
## [param along] y [param into] por ejes y [param size] por lados.
static func oriented_rect(centre: Vector2, along: Vector2, into: Vector2,
		size: Vector2) -> PackedVector2Array:
	var u := along * size.x * 0.5
	var v := into * size.y * 0.5
	var out := PackedVector2Array()
	out.append(centre - u - v)
	out.append(centre + u - v)
	out.append(centre + u + v)
	out.append(centre - u + v)
	return out


## En qué sólidos se descompone la parcela [param index]: uno por caja.
##
## Cada uno es `{id, part, parcel, poly, y0, y1}`. `id` es con qué nombre lo
## conoce el diseño —el `design_id` de un POI o el nombre de la parcela—, que es
## lo que un prop nombra en su `allow_overlap`; `part` distingue las cajas de una
## misma pieza para que el mensaje diga «la losa de la marquesina» y no «la
## estación».
##
## El giro es el del **edificio**: la normal de frente más el `yaw_jitter` que
## [CityGrid] le suma a la fachada. El lote no se gira nunca (ver
## [constant HOUSE_YAW_JITTER]); lo que pisa una pared es la pared.
static func parcel_solids(plan: TownPlan, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if index < 0 or index >= plan.parcels.size():
		return out
	var parcel := plan.parcels[index]
	var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
	var into := spin(Vector2(normal.x, normal.z), float(parcel.get("yaw_jitter", 0.0)))
	var along := Vector2(-into.y, into.x)
	var piece := StringName(parcel.get("piece", &""))
	var centre3 := plan.parcel_position(index)
	var centre := Vector2(centre3.x, centre3.z)
	var base_y := centre3.y
	var scale := maxf(float(parcel.get("height_scale", 1.0)), 0.05)
	var id := StringName(parcel.get("design_id", &""))
	if id == &"":
		id = StringName(parcel.get("name", &"?"))

	var parts := piece_parts(piece)
	if parts.is_empty():
		var size := piece_plan_size(piece, Vector2(float(parcel.get("width", 0.0)),
				float(parcel.get("depth", 0.0))))
		out.append({
			"id": id, "part": &"", "parcel": index,
			"poly": oriented_rect(centre, along, into, size),
			"y0": base_y, "y1": base_y + piece_top(piece) * scale,
		})
		return out

	# El reparto de ejes es el de [method piece_plan_size]: una pieza con el
	# frente en `-X` llega girada un cuarto de vuelta, así que su `+X` local
	# apunta hacia **afuera** del lote y su `+Z` corre a lo largo del frente.
	var front_x := TownDesign.piece_front(piece) == &"-X"
	var ex := -into if front_x else along
	var ez := -along if front_x else -into
	for entry: Variant in parts:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = entry
		var at := _triple(part.get("centre", null))
		var size := _triple(part.get("size", null))
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			continue
		var mid := centre + ex * at.x + ez * at.z
		out.append({
			"id": id, "part": StringName(String(part.get("name", ""))), "parcel": index,
			"poly": oriented_rect(mid, ex, ez, Vector2(size.x, size.z)),
			"y0": base_y + (at.y - size.y * 0.5) * scale,
			"y1": base_y + (at.y + size.y * 0.5) * scale,
		})
	return out


## Todos los sólidos del plano: las parcelas —con sus cajas— y nada más. Las
## rocas, el tablero y la losa de la plaza los suma quien pregunte, porque no
## todos los que preguntan los quieren (ver `tools/town_plan_check.gd` filas A y
## B).
static func parcel_solid_list(plan: TownPlan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index: int in plan.parcels.size():
		out.append_array(parcel_solids(plan, index))
	return out


## `[x, y, z]` de un JSON como [Vector3], o el cero.
static func _triple(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return Vector3.ZERO
	var list: Array = value
	return Vector3(float(list[0]), float(list[1]), float(list[2]))


## Cuánto gira [CityGrid] una pieza suelta **además** de lo que el diseño le
## declara, en radianes.
##
## Una pieza de pueblo tiene el frente en su `-X` y el resolvedor declara el giro
## en el marco del **mundo** («esta parada mira a la ruta»), así que el
## constructor le suma un cuarto de vuelta negativo. La regla vive en el
## manifiesto —`front`— y no en una tabla aparte, que es lo que hace que el plano
## y [CityGrid] no se puedan desincronizar.
static func piece_yaw_offset(piece: StringName) -> float:
	return -PI * 0.5 if TownDesign.piece_front(piece) == &"-X" else 0.0


## El rectángulo de la huella de un prop del plano, en XZ, ya girado como lo gira
## [CityGrid].
static func prop_rect(prop: Dictionary) -> PackedVector2Array:
	var piece := StringName(prop.get("piece", &""))
	var size := Vector2.ZERO
	var entry: Variant = TownDesign.manifest().get(String(piece), null)
	if typeof(entry) == TYPE_DICTIONARY:
		var raw: Variant = (entry as Dictionary).get("footprint", null)
		if typeof(raw) == TYPE_ARRAY and (raw as Array).size() == 2:
			size = Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	if size.x <= 0.0 or size.y <= 0.0:
		return PackedVector2Array()
	var yaw := float(prop.get("yaw", 0.0)) + piece_yaw_offset(piece)
	var at: Vector3 = prop.get("pos", Vector3.ZERO)
	return oriented_rect(Vector2(at.x, at.z), Vector2(cos(yaw), -sin(yaw)),
			Vector2(sin(yaw), cos(yaw)), size)


## Cota del relieve en [param flat], o `0` si el terreno todavía no existe. Es la
## forma pública de la cuenta que el resolvedor hace para apoyar un lote rural.
static func ground_height(terrain: Object, flat: Vector2) -> float:
	return _ground_y(terrain, flat)


## Las rocas del plano como discos `{id, centre, radius}`.
##
## La pieza de la roca `i` es [member TownPlan.rock_pieces]`[i]`, que es la
## **misma** lista con la que [CityGrid] elige la escena (`_build_rocks`): una
## sola fuente. Hasta la revisión de WP-L esto reconstruía la pieza desde el
## diseño y [CityGrid] repartía `rock_scenes[i % 6]` de una lista fija, y las dos
## cosas coincidían por casualidad —el diseño declara las seis rocas en el mismo
## orden que la lista— (hallazgo 3). El radio sale de [constant ROCK_RADIUS].
static func rock_discs(plan: TownPlan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: int in mini(plan.rocks.size(), plan.rock_pieces.size()):
		var piece := StringName(plan.rock_pieces[slot])
		var at: Vector3 = plan.rocks[slot]
		out.append({"id": piece, "centre": Vector2(at.x, at.z),
				"radius": piece_radius(piece)})
	return out


## El tablero del puente como rectángulo orientado, o vacío si no hay puente.
##
## Corre a lo largo de su `+X` (`front: "+X-run"` en el manifiesto), que es el
## rumbo de la ruta dentro del vano. La huella es la del manifiesto para
## [member TownPlan.bridge_piece] (20 × 12 para `bridge_deck`: el vano más los
## dos estribos); si el manifiesto no la conoce, el vano y el ancho que declara
## el diseño. Hasta la revisión de WP-L era una constante copiada del manifiesto
## (hallazgo 11).
static func bridge_rect(plan: TownPlan) -> PackedVector2Array:
	if not plan.has_bridge():
		return PackedVector2Array()
	var run := Vector2(cos(plan.bridge_yaw), -sin(plan.bridge_yaw))
	var across := Vector2(-run.y, run.x)
	return oriented_rect(Vector2(plan.bridge_at.x, plan.bridge_at.z), run, across,
			piece_plan_size(plan.bridge_piece,
			Vector2(plan.bridge_span, plan.bridge_deck_width)))


## Los tramos de cerco del plano como segmentos `[a, b]` en XZ.
static func fence_segments(plan: TownPlan) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for index: int in plan.fence_points.size():
		var kind := plan.fence_kinds[index] if index < plan.fence_kinds.size() else 0
		if kind < 0 or kind >= TownDesign.FENCE_LINE_KINDS.size():
			continue
		var span := float(TownDesign.FENCE_SPAN.get(
				TownDesign.FENCE_LINE_KINDS[kind], 0.0))
		var yaw := plan.fence_yaws[index] if index < plan.fence_yaws.size() else 0.0
		var at: Vector3 = plan.fence_points[index]
		var a := Vector2(at.x, at.z)
		out.append(PackedVector2Array([a, a + Vector2(cos(yaw), -sin(yaw)) * span]))
	return out


## Distancia de [param point] al tramo de cerco más cercano, o `INF` si no hay.
static func fence_distance(segments: Array[PackedVector2Array], point: Vector2) -> float:
	var best := INF
	for segment: PackedVector2Array in segments:
		best = minf(best, TownPlan.segment_distance(segment[0], segment[1], point))
	return best


## Distancia de [param point] al eje del arroyo, o `INF` si el plano no trae
## arroyo. Es la medida con la que se resta el canal a la banda de la arboleda.
static func creek_distance(plan: TownPlan, point: Vector2) -> float:
	if plan.creek_points.size() < 2:
		return INF
	var best := INF
	for index: int in plan.creek_points.size() - 1:
		best = minf(best, TownPlan.segment_distance(plan.creek_points[index],
				plan.creek_points[index + 1], point))
	return best


## Distancia mínima entre dos polígonos convexos que **no** se solapan, en
## metros; `0` si se tocan o se pisan.
##
## Es la distancia de verdad —el mínimo sobre los pares vértice/lado de los dos—
## y no el hueco que devuelve el eje separador: para dos rectángulos en diagonal
## el eje separador informa el mayor de los dos catetos y la distancia es la
## hipotenusa. Con el eje separador un par a 0,40 m en diagonal se declararía a
## 0,28 y la fila A lo rechazaría por nada.
static func polygon_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return INF
	if TownPlan.polygons_overlap(a, b, 0.0):
		return 0.0
	var best := INF
	for pair: int in 2:
		var from := a if pair == 0 else b
		var to := b if pair == 0 else a
		for index: int in to.size():
			var p := to[index]
			var q := to[(index + 1) % to.size()]
			for point: Vector2 in from:
				best = minf(best, TownPlan.segment_distance(p, q, point))
	return best


## Cuánto se pisan dos polígonos convexos, en metros, por el eje separador; `0`
## si no se pisan. Es la penetración mínima, que es lo que un informe puede leer
## como «se meten treinta centímetros».
static func polygon_overlap_depth(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return 0.0
	var best := INF
	for pair: int in 2:
		var poly := a if pair == 0 else b
		for index: int in poly.size():
			var p := poly[index]
			var q := poly[(index + 1) % poly.size()]
			var edge := q - p
			if edge.length_squared() <= 0.000001:
				continue
			var axis := Vector2(edge.y, -edge.x).normalized()
			var a_min := INF
			var a_max := -INF
			for point: Vector2 in a:
				var value := point.dot(axis)
				a_min = minf(a_min, value)
				a_max = maxf(a_max, value)
			var b_min := INF
			var b_max := -INF
			for point: Vector2 in b:
				var value := point.dot(axis)
				b_min = minf(b_min, value)
				b_max = maxf(b_max, value)
			var gap := minf(a_max - b_min, b_max - a_min)
			if gap <= 0.0:
				return 0.0
			best = minf(best, gap)
	return 0.0 if is_inf(best) else best


## Distancia de [param point] al polígono convexo [param poly]: positiva hacia
## afuera y `0` adentro.
static func point_polygon_distance(poly: PackedVector2Array, point: Vector2) -> float:
	if poly.size() < 3:
		return INF
	if TownPlan.polygon_inset(poly, point) >= 0.0:
		return 0.0
	var best := INF
	for index: int in poly.size():
		best = minf(best, TownPlan.segment_distance(poly[index],
				poly[(index + 1) % poly.size()], point))
	return best


# --------------------------------------------------------------------------
# 13. Arroyo y puente
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
