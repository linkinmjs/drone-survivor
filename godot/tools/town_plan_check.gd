## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del **plano del pueblo** (`docs/10` §4, reescrito por WP-T3).
##
## No abre un solo asset y no instancia ni un nodo: carga
## `city/designs/town_a.json`, lo resuelve con [TownPlanner] y le hace preguntas
## de geometría. Por eso corre en menos de cinco segundos en `--headless` puro y
## se puede ejecutar mil veces mientras se ajusta el diseño, que es exactamente
## lo que hace falta cuando lo que se está afinando es dónde va cada casa.
##
## ## Qué cambió respecto de WP-B
##
## Hasta P2b el pueblo lo **sorteaba** una semilla, así que el check medía
## *rangos*: entre once y catorce manzanas, entre cuarenta y cuatro y cincuenta y
## dos casas, transversales a 74–106° de la ruta. Un rango es lo único que se le
## puede exigir a un sorteo.
##
## Desde WP-T3 el trazado está escrito a mano, y a un diseño no se le pregunta si
## cae dentro de un rango: se le pregunta si el plano dice **lo que el diseño
## dijo**. Las tres secciones nuevas son:
##
## - **§grafo**: toda calle termina en un nodo o en un cabo con cierre, dos
##   calles que se encuentran lo hacen a 35° o más, ningún par se cruza sin nodo,
##   y el polígono de cada manzana es el anillo de **sus** nodos metido hacia
##   adentro la media franja de la calle de cada lado. Lo miden
##   [method TownPlan.graph_problems] y este archivo, cada uno lo suyo.
## - **§diseño**: cada casa, cada POI, cada caserío y cada roca declarados
##   aparecen en el plano, con su pieza y a menos de cinco centímetros de donde
##   el diseño los puso.
## - **§determinismo posicional**: recolorear una casa o moverla cambia **su**
##   línea de la firma y la del hash del diseño, y ninguna otra. Es la propiedad
##   que hace editable el diseño: sin ella, tocar la manzana 7 movería la 8 y el
##   `diff` del pueblo horneado dejaría de decir qué cambió.
##
## Lo que sigue valiendo se conserva entero: parcelas sin solapes y dentro de su
## manzana, el círculo de juego, el reparto de roles y el HP total, los
## marcadores, las rocas, el racionamiento de ventanas y la escena horneada.
##
## Cierra con **pruebas negativas** sobre las rutinas de verdad
## —[method _parcel_problems], [method TownPlan.graph_problems] y la validación
## de [TownDesign]—, porque un sub-check que nunca vio fallar nada no se sabe si
## mira.
extends CheckRunner

## El diseño comiteado.
const DESIGN_PATH: String = "res://city/designs/town_a.json"

## Parcelas: rangos que el diseño **no** puede violar aunque quiera, porque los
## fija la pieza o el motor.
const HOUSE_WIDTH_MIN: float = 9.0
const HOUSE_WIDTH_MAX: float = 15.0

## Tolerancia del HP total contra lo que dicen los roles.
const HP_TOLERANCE: float = 0.05

## Marcadores.
const SPAWNS: int = 4
const SPAWN_MARGIN: float = 60.0
const POSTS: int = 8
const POSTS_STREET: int = 5
## El mismo rango que [constant TownPlanner.POST_STREET_Y_MIN] y su par: el
## puesto de calle cuelga **de** su toldo, que arranca a 2,40 m y mide 0,80
## (WP-D4a, hallazgo 5).
const POST_Y_MIN: float = 2.8
const POST_Y_MAX: float = 3.2
const DRONE_DISTANCE: float = 120.0
const DRONE_HEIGHT: float = 1.5
const ROCK_CONE_DEG: float = 30.0

## Dónde tienen que caer los caseríos, en metros del centro. Cerca para que se
## vean al anochecer, lejos para que sigan fuera del círculo de 140 m.
const HAMLET_MIN: float = 150.0
const HAMLET_MAX: float = 220.0

## La escuela: hasta dónde puede estar del centro y de la plaza, y cuánto puede
## desviarse su fachada de mirarla (`docs/17` §2 y §3).
const SCHOOL_REACH_MAX: float = 60.0
const SCHOOL_PLAZA_MAX: float = 80.0
const SCHOOL_PLAZA_ANGLE: float = 35.0

## Reglas de las arboledas: cuánto puede desviarse el conteo declarado y a qué
## distancia mínima del eje de la ruta puede caer una instancia.
const GROVE_COUNT_TOLERANCE: float = 0.10
const GROVE_SPACED_TOLERANCE: float = 0.20
const GROVE_ROUTE_MIN: float = 12.0

## Anillos de densidad de `docs/17` §1: radio de corte y banda de POI de cada
## uno. Un POI es un edificio que no es casa, un hito, la plaza, el puente, un
## cartel, una parada, una arboleda, un maizal o un molino.
const RING_EDGES: Array[float] = [60.0, 140.0, 230.0, 600.0]
const RING_MIN: Array[int] = [4, 14, 8, 4]
const RING_MAX: Array[int] = [7, 22, 14, 8]

## Qué props cuentan como POI del mapa de densidad: los que una persona nombra
## al describir el pueblo. Un banco o una farola no; el cartel de bienvenida, la
## parada, el monumento, el mástil y el toldo de una pila, sí.
const RING_POI_PIECES: Array[StringName] = [
	&"welcome_sign", &"road_sign_narrow", &"road_sign_speed", &"bus_stop",
	&"awning_orange", &"monument", &"flag_mast", &"windmill",
]

## Cuántas casas de caserío son **un** caserío (`docs/17` §2).
const HAMLET_GROUP: int = 6

## Tolerancia de las comprobaciones geométricas, en metros.
const EPSILON: float = 0.1

## Con cuánta precisión el plano tiene que respetar lo que el diseño declaró, en
## metros. Es cinco centímetros: menos que el ancho de un marco de puerta.
const DESIGN_TOLERANCE: float = 0.05

## Escena horneada del pueblo. Se lee como **texto**, no se instancia: el check
## tiene que seguir corriendo en `--headless` puro en menos de cinco segundos, y
## lo que hay que verificar acá son nombres de nodo y una línea de grupo.
const TOWN_SCENE: String = "res://city/districts/town_a.tscn"

## Nodos que `RoundManager`, `BatterySpawner` y el jefe buscan **por nombre** o
## **por grupo** dentro del pueblo horneado.
##
## Va sobre el texto del `.tscn` a propósito: el grupo `town_centre` se perdió una
## vez por un `add_to_group()` sin `persistent = true`, que es un fallo que no se
## ve en el plano, no se ve al construir y sólo aparece cuando el jefe carga la
## escena empaquetada y se queda sin centro de pueblo.
##
## La lista **no** nombra los nodos del viario (`Crossings`, `Sidewalks`,
## `BlockPads`): el constructor los reemplaza por dos mallas en WP-T1/T4 y exigir
## los de P2b sería exigir el defecto que se está arreglando.
const BAKED_MARKERS: Array[String] = [
	"[node name=\"TownCentre\"",
	"groups=[\"town_centre\"]",
	"[node name=\"DroneSpawn\"",
	"[node name=\"CameraFixedPose\"",
	"[node name=\"EnemySpawn0\"", "[node name=\"EnemySpawn3\"",
	"[node name=\"Post0\"", "[node name=\"Post7\"",
	"[node name=\"Building_School\"",
	"[node name=\"Building_Landmark\"",
]

var _design: TownDesign = null
var _plan: TownPlan = null

## Relieve horneado con el que se resuelve el diseño, o `null` si todavía no se
## horneó. Ver [method TownPlanner.baked_terrain].
var _terrain: Object = null


func _run() -> void:
	_design = TownDesign.load_json(DESIGN_PATH)
	if _design == null:
		fail("'%s' no carga: %s" % [DESIGN_PATH, _failure_text()])
		_report_failures()
		await wait_frames(1)
		return
	expect(_design.warnings.is_empty(),
			"el diseño comiteado trae %d avisos de pieza: %s"
			% [_design.warnings.size(), ", ".join(_design.warnings)])
	# El relieve horneado entra en la resolución igual que en el horneado del
	# pueblo: es de él que sale la cota de cada manzana, así que sin él las
	# firmas de este check y las de `city_check` hablarían de dos pueblos.
	_terrain = TownPlanner.baked_terrain()
	_plan = TownPlanner.resolve(_design, _terrain)

	_check_determinism()
	_check_signature_covers()
	_check_graph()
	_check_blocks()
	_check_design()
	_check_parcels()
	_check_circle()
	_check_roles()
	_check_windows()
	_check_markers()
	_check_rocks()
	_check_plaza()
	_check_groves()
	_check_fences()
	_check_props()
	_check_awnings()
	_check_ring_density()
	_check_positional()
	_check_grove_determinism()
	_check_baked_scene()
	_check_negative()
	_report()
	await wait_frames(1)


func _failure_text() -> String:
	var failure := TownDesign.last_failure()
	if failure == null:
		return "sin diagnóstico"
	return "; ".join(failure.problems)


func _report_failures() -> void:
	var failure := TownDesign.last_failure()
	if failure == null:
		return
	for problem: String in failure.problems:
		print("  %s" % problem)


# --------------------------------------------------------------------------
# Determinismo
# --------------------------------------------------------------------------

## Dos resoluciones del mismo diseño dan el mismo pueblo; dos diseños distintos,
## pueblos distintos.
##
## `generate()` ya no depende de la semilla —el trazado lo manda el JSON— así que
## el control negativo no es «otra semilla» sino **otro diseño**: se cambia la
## semilla de variación en memoria, que es lo único que le queda al azar.
func _check_determinism() -> void:
	var again := TownPlanner.resolve(_design, _terrain)
	expect(again.signature() == _plan.signature(),
			"dos resoluciones del mismo diseño dieron planos distintos")

	var copy := TownDesign.from_data(_design.raw_data())
	expect(copy != null, "el diseño comiteado no vuelve a validar desde memoria")
	if copy != null:
		expect(copy.design_hash() == _design.design_hash(),
				"el mismo diseño leído de disco y de memoria da dos hashes")
		expect(TownPlanner.resolve(copy, _terrain).signature() == _plan.signature(),
				"el mismo diseño leído de disco y de memoria da dos pueblos")

	var other_data := _design.raw_data()
	other_data["variation_seed"] = int(other_data.get("variation_seed", 0)) + 1
	var other := TownDesign.from_data(other_data)
	expect(other != null, "cambiar la semilla de variación rompió la validación")
	if other != null:
		expect(other.design_hash() != _design.design_hash(),
				"dos semillas de variación distintas dan el mismo hash de diseño")
		expect(TownPlanner.resolve(other, _terrain).signature() != _plan.signature(),
				"dos semillas de variación distintas dan el mismo pueblo")

	# `generate()` tiene que devolver **el** pueblo comiteado aunque le pasen
	# cualquier semilla: los argumentos quedaron por compatibilidad.
	expect(TownPlanner.generate(TownPlanner.TOWN_SEED).signature() == _plan.signature(),
			"generate(TOWN_SEED) no devuelve el pueblo del diseño")
	expect(TownPlanner.generate(987654).signature() == _plan.signature(),
			"generate() todavía mira la semilla, y el trazado lo manda el diseño")


## **La firma ve un solo giro** (WP-D4a, hallazgo 2).
##
## La firma es lo único que ata la escena comiteada al resolvedor de hoy
## (`city_check` compara las dos), así que todo lo que decide una transformada
## tiene que entrar en ella. Hasta WP-D4a entraban los **puntos** de las
## arboledas y de los cercos y no su giro ni su escala, y de un prop no entraba
## `on_terrain`: girar los mil cuatrocientos árboles del pueblo, achatarlos a la
## mitad o despegar un toldo del suelo dejaba la firma idéntica y la escena vieja
## pasaba en verde.
##
## La fila toca **un** número de un plano resuelto de más y exige que la firma
## cambie. No se hace desde el diseño porque ninguno de estos cuatro valores se
## declara: salen del resolvedor.
func _check_signature_covers() -> void:
	var cases: Array[Dictionary] = [
		{"what": "el giro de un árbol", "field": "grove_yaws"},
		{"what": "la escala de un árbol", "field": "grove_scales"},
		{"what": "el rumbo de un tramo de cerco", "field": "fence_yaws"},
		{"what": "el `on_terrain` de un prop", "field": "prop_on_terrain"},
		{"what": "el `align` de un prop", "field": "prop_align"},
	]
	var touched := 0
	for case: Dictionary in cases:
		var mutated := TownPlanner.resolve(_design, _terrain)
		if not _nudge(mutated, String(case["field"])):
			fail("la firma: no hay dónde cambiar %s" % String(case["what"]))
			continue
		touched += 1
		expect(mutated.signature() != _plan.signature(),
				"la firma no cambia al cambiar %s" % String(case["what"]))
	print("  la firma ve: %d cambios de un solo valor, %d líneas de firma"
			% [touched, _plan.signature().split("\n").size()])


## Cambia **un** valor de [param plan] y devuelve `true` si había alguno.
func _nudge(plan: TownPlan, field: String) -> bool:
	match field:
		"grove_yaws":
			for index: int in plan.grove_yaws.size():
				if plan.grove_yaws[index].is_empty():
					continue
				var list := plan.grove_yaws[index]
				list[0] = list[0] + 0.5
				plan.grove_yaws[index] = list
				return true
		"grove_scales":
			for index: int in plan.grove_scales.size():
				if plan.grove_scales[index].is_empty():
					continue
				var list := plan.grove_scales[index]
				list[0] = list[0] * 0.5
				plan.grove_scales[index] = list
				return true
		"fence_yaws":
			if plan.fence_yaws.is_empty():
				return false
			plan.fence_yaws[0] = plan.fence_yaws[0] + 0.5
			return true
		"prop_on_terrain":
			if plan.prop_placements.is_empty():
				return false
			var prop: Dictionary = plan.prop_placements[0]
			prop["on_terrain"] = not bool(prop.get("on_terrain", true))
			return true
		"prop_align":
			if plan.prop_placements.is_empty():
				return false
			var prop: Dictionary = plan.prop_placements[0]
			prop["align"] = not bool(prop.get("align", false))
			return true
	return false


# --------------------------------------------------------------------------
# Grafo
# --------------------------------------------------------------------------

## El grafo del viario: calles que terminan donde tienen que terminar, ángulos
## legibles, ningún cruce sin nodo y bocas completas.
func _check_graph() -> void:
	expect(_plan.has_graph(), "el plano no trae grafo")
	if not _plan.has_graph():
		return
	for problem: String in _plan.graph_problems():
		fail("grafo: %s" % problem)

	expect(_plan.graph_street_count() == _design.street_count() + 1,
			"el grafo cubre %d calles y el diseño declara %d"
			% [_plan.graph_street_count(), _design.street_count() + 1])
	expect(_plan.nodes.size() == _design.node_count(),
			"el plano trae %d nodos y el diseño declara %d"
			% [_plan.nodes.size(), _design.node_count()])
	expect(_plan.street_kind_of(0) == TownPlan.StreetKind.ROUTE,
			"la calle 0 no está declarada como ruta")

	# Cada punta: nodo o cabo con cierre. Es la fila que arregla los catorce
	# cabos sueltos de P2b, y se mide acá **además** de en `graph_problems()`
	# porque acá se puede decir de qué calle del diseño se trata.
	var stubs := 0
	var declared_stubs := 0
	for index: int in _design.street_count():
		var street := _design.street(index + 1)
		for suffix: String in ["a", "b"]:
			if float(street["stub_%s" % suffix]) > 0.0:
				declared_stubs += 1
	for street: int in _plan.graph_street_count():
		var id := _street_id(street)
		for end: int in 2:
			var node := _plan.node_of(street, end)
			if node >= 0:
				expect(_plan.street_closure_of(street, end) == &"none"
						or _plan.street_closure_of(street, end) == &"",
						"la calle '%s' llega a un nodo y además declara cierre" % id)
				continue
			stubs += 1
			var closure := _plan.street_closure_of(street, end)
			expect(closure != &"none" and closure != &"",
					"la punta %s de la calle '%s' es un cabo sin cierre"
					% ["a" if end == 0 else "b", id])
			expect(_plan.street_stub_of(street, end) > 0.0,
					"la punta %s de la calle '%s' es un cabo de largo cero"
					% ["a" if end == 0 else "b", id])
	expect(stubs == declared_stubs,
			"el plano tiene %d cabos y el diseño declara %d" % [stubs, declared_stubs])

	# Las bocas: un nodo por el que una calle pasa de largo aporta **dos**, una
	# para cada lado. Si alguien llamara a `TownPlan.refresh_nodes()` sobre este
	# plano —que deduce las bocas sólo de las puntas— los cruces de la ruta se
	# quedarían con la mitad, y esta fila es la que lo ve.
	for index: int in _plan.nodes.size():
		var node := _plan.nodes[index]
		var streets: PackedInt32Array = node.get("streets", PackedInt32Array())
		var expected := 0
		for street: int in _design.node_streets(index):
			var chain := _design.street_chain(street)
			var slot := _chain_slot(chain, index)
			if slot < 0:
				continue
			# Dos bocas salvo en la punta del **eje**: un nodo al principio de la
			# cadena con cabo sigue teniendo calle de los dos lados, porque el
			# cabo es calzada de verdad que muere en el campo.
			expected += 2
			if slot == 0 and _plan.street_stub_of(street, 0) <= 0.0:
				expected -= 1
			if slot == chain.size() - 1 and _plan.street_stub_of(street, 1) <= 0.0:
				expected -= 1
		expect(streets.size() == expected,
				"el nodo '%s' declara %d bocas y su geometría da %d"
				% [_design.node_id(index), streets.size(), expected])
		expect(streets.size() >= 1, "el nodo '%s' no toca ninguna calle" % _design.node_id(index))
		for slot: int in streets.size():
			var half: float = node["half_widths"][slot]
			expect(is_equal_approx(half, _plan.street_half_of(streets[slot])),
					"la boca %d del nodo '%s' dice media franja %.3f y su calle mide %.3f"
					% [slot, _design.node_id(index), half,
					_plan.street_half_of(streets[slot])])


## En qué posición de [param chain] está el nodo [param node], o `-1`.
func _chain_slot(chain: PackedInt32Array, node: int) -> int:
	for slot: int in chain.size():
		if chain[slot] == node:
			return slot
	return -1


## El identificador de diseño de la calle [param street] del plano.
func _street_id(street: int) -> String:
	if street == 0:
		return "route"
	return String(_design.street(street).get("id", "?"))


# --------------------------------------------------------------------------
# Manzanas
# --------------------------------------------------------------------------

## Cada manzana es el anillo de **sus** nodos metido hacia adentro la media
## franja de la calle de cada lado, convexo y sin pisar a ninguna vecina.
##
## Se recalcula el polígono aquí a partir del diseño en vez de creerle al plano:
## es la única forma de comprobar que el resolvedor resolvió y no copió.
func _check_blocks() -> void:
	expect(_plan.block_count() == _design.block_count(),
			"el plano trae %d manzanas y el diseño declara %d"
			% [_plan.block_count(), _design.block_count()])
	for index: int in mini(_plan.block_count(), _design.block_count()):
		var block := _design.block(index)
		var id: StringName = block["id"]
		var ring: PackedVector2Array = block["ring"]
		var slots: PackedInt32Array = block["nodes"]
		var poly := _plan.block_polygon(index)
		expect(poly.size() == ring.size(),
				"la manzana '%s' declara %d nodos y su polígono tiene %d vértices"
				% [id, ring.size(), poly.size()])
		expect(TownPlan.polygon_is_convex(ring), "el anillo de nodos de '%s' no es convexo" % id)
		expect(TownPlan.polygon_is_convex(poly), "la manzana '%s' no es convexa" % id)
		if poly.size() != ring.size():
			continue
		for edge: int in slots.size():
			var from := slots[(edge - 1 + slots.size()) % slots.size()]
			var expected := _design.street_between(from, slots[edge])
			expect(_plan.block_edge_street(index, edge) == expected,
					"el lado %d de '%s' dice dar a la calle %d y sus nodos dicen %d"
					% [edge, id, _plan.block_edge_street(index, edge), expected])
			# El lado corrido tiene que quedar a **exactamente** la media franja
			# del lado de nodos: ni encima de la calzada ni metido en el jardín.
			var half := _plan.street_half_of(expected) if expected >= 0 else 0.0
			var a := ring[(edge - 1 + ring.size()) % ring.size()]
			var b := ring[edge]
			var direction := (b - a).normalized()
			var outward := Vector2(direction.y, -direction.x)
			if TownPlan.polygon_signed_area(ring) < 0.0:
				outward = -outward
			var mid := (poly[(edge - 1 + poly.size()) % poly.size()] + poly[edge]) * 0.5
			expect_near((mid - a).dot(outward), -half, 0.01,
					"el lado %d de '%s' quedó a %.3f m de la línea de nodos y la calle pide %.3f"
					% [edge, id, -(mid - a).dot(outward), half])
		for other: int in index:
			expect(not TownPlan.polygons_overlap(poly, _plan.block_polygon(other), 0.5),
					"las manzanas '%s' y '%s' se solapan" % [_design.block(other)["id"], id])


# --------------------------------------------------------------------------
# Diseño
# --------------------------------------------------------------------------

## Cada elemento declarado aparece en el plano, con su pieza y donde el diseño lo
## puso.
func _check_design() -> void:
	var houses := 0
	for block: int in _design.block_count():
		var entry := _design.block(block)
		var id: StringName = entry["id"]
		var declared: Array[Dictionary] = entry["houses"]
		houses += declared.size()
		for slot: int in declared.size():
			var house := declared[slot]
			var wanted := StringName("%s%02d_%02d" % [TownPlan.HOUSE_PREFIX, block, slot])
			var parcel := _parcel_named(wanted)
			if parcel < 0:
				fail("la casa %d de '%s' no aparece en el plano ('%s')" % [slot, id, wanted])
				continue
			var data := _plan.parcels[parcel]
			expect(StringName(data.get("piece", &"")) == StringName(house["piece"]),
					"la casa '%s' se sembró con la pieza '%s' y el diseño pide '%s'"
					% [wanted, data.get("piece", "?"), house["piece"]])
			expect(int(data.get("block", -1)) == block,
					"la casa '%s' dice estar en la manzana %d y el diseño la puso en la %d"
					% [wanted, data.get("block", -1), block])
			expect(int(data.get("street", -1)) == int(house["front"]),
					"la casa '%s' da a la calle %d y el diseño la puso sobre la %d"
					% [wanted, data.get("street", -1), house["front"]])
			expect(int(data.get("color", -1)) == int(house["color"]),
					"la casa '%s' no conservó su color" % wanted)
			expect(int(data.get("variant", -1)) == int(house["variant"]),
					"la casa '%s' no conservó su variante" % wanted)
			# Dónde: el `t` declarado sobre el lado de manzana que da a su calle.
			var edge := _design.block_edge(block, int(house["front"]))
			var poly := _plan.block_polygon(block)
			if edge < 0 or poly.size() < 3:
				fail("la casa '%s' da a una calle que no toca su manzana" % wanted)
				continue
			var a := poly[(edge - 1 + poly.size()) % poly.size()]
			var b := poly[edge]
			var wanted_point := a.lerp(b, float(house["t"]))
			var point: Vector3 = data.get("frontage_point", Vector3.ZERO)
			expect_near(Vector2(point.x, point.z).distance_to(wanted_point), 0.0,
					DESIGN_TOLERANCE,
					"la casa '%s' quedó lejos del t = %.3f que declara"
					% [wanted, float(house["t"])])
			var width := float(data.get("width", 0.0))
			expect(width >= HOUSE_WIDTH_MIN - 0.01 and width <= HOUSE_WIDTH_MAX + 0.01,
					"la parcela de '%s' mide %.2f m de frente, fuera de [%.0f, %.0f]"
					% [wanted, width, HOUSE_WIDTH_MIN, HOUSE_WIDTH_MAX])
	expect(_plan.parcels_of_role(TownPlan.Role.HOUSE).size() == houses,
			"el diseño declara %d casas y el plano sembró %d"
			% [houses, _plan.parcels_of_role(TownPlan.Role.HOUSE).size()])

	# --- POI ---------------------------------------------------------------
	var seeded := 0
	for entry: Variant in _design.poi():
		var data: Dictionary = entry
		var role := StringName(String(data.get("role", "")))
		if not TownPlanner.POI_ROLE.has(role):
			continue
		# Un POI cuyo rol el resolvedor conoce pero cuya **pieza** todavía no
		# existe no se siembra, y no puede contar como sembrado: es trabajo de
		# WP-D1, no un fallo del diseño. Lo que sí se cuenta —y se informa— es
		# cuántos son.
		if TownDesign.piece_class(StringName(String(data.get("piece", "")))) != &"building":
			continue
		seeded += 1
		var parcel := _parcel_with(&"design_id", StringName(String(data.get("id", ""))))
		if parcel < 0:
			fail("el POI '%s' no aparece en el plano" % data.get("id", "?"))
			continue
		var plan_role: int = TownPlanner.POI_ROLE[role]
		expect(int(_plan.parcels[parcel].get("role", -1)) == plan_role,
				"el POI '%s' se sembró con otro rol" % data.get("id", "?"))
		expect(StringName(_plan.parcels[parcel].get("piece", &"")) == StringName(String(data.get("piece", ""))),
				"el POI '%s' se sembró con otra pieza" % data.get("id", "?"))
		var wanted_pos: Variant = TownDesign.to_vector2(data.get("pos", null))
		var position := _plan.parcel_position(parcel)
		expect_near(Vector2(position.x, position.z).distance_to(wanted_pos as Vector2), 0.0,
				DESIGN_TOLERANCE, "el POI '%s' no quedó donde el diseño lo puso"
				% data.get("id", "?"))
		expect_near(absf(angle_difference(_plan.parcel_yaw(parcel),
				deg_to_rad(float(data.get("yaw_deg", 0.0))))), 0.0, 0.001,
				"el POI '%s' no quedó con el giro que declara" % data.get("id", "?"))
	var big := _plan.parcels_of_role(TownPlan.Role.MEDIUM).size() \
			+ _plan.parcels_of_role(TownPlan.Role.LANDMARK).size() \
			+ _plan.parcels_of_role(TownPlan.Role.SCHOOL).size()
	expect(big == seeded, "el diseño declara %d POI sembrables y el plano puso %d" % [seeded, big])

	# --- Caseríos y rocas --------------------------------------------------
	var decor := _design.decor_houses()
	expect(_plan.parcels_of_role(TownPlan.Role.DECOR).size() == decor.size(),
			"el diseño declara %d casas de caserío y el plano sembró %d"
			% [decor.size(), _plan.parcels_of_role(TownPlan.Role.DECOR).size()])
	for index: int in decor.size():
		var data: Dictionary = decor[index]
		var parcel := _parcel_named(StringName("%s%02d" % [TownPlan.DECOR_PREFIX, index]))
		if parcel < 0:
			fail("la casa de caserío %d no aparece en el plano" % index)
			continue
		expect(StringName(_plan.parcels[parcel].get("piece", &"")) == StringName(String(data.get("piece", ""))),
				"la casa de caserío %d se sembró con otra pieza" % index)
		var wanted_pos: Variant = TownDesign.to_vector2(data.get("pos", null))
		var position := _plan.parcel_position(parcel)
		expect_near(Vector2(position.x, position.z).distance_to(wanted_pos as Vector2), 0.0,
				DESIGN_TOLERANCE, "la casa de caserío %d no quedó donde el diseño la puso" % index)

	var rocks := _design.rocks()
	expect(_plan.rocks.size() == rocks.size(),
			"el diseño declara %d rocas y el plano sembró %d" % [rocks.size(), _plan.rocks.size()])
	for index: int in mini(rocks.size(), _plan.rocks.size()):
		var data: Dictionary = rocks[index]
		var wanted_pos: Variant = TownDesign.to_vector2(data.get("pos", null))
		var spot: Vector3 = _plan.rocks[index]
		expect_near(Vector2(spot.x, spot.z).distance_to(wanted_pos as Vector2), 0.0,
				DESIGN_TOLERANCE, "la roca %d no quedó donde el diseño la puso" % index)


## La parcela que se llama [param wanted], o `-1`.
func _parcel_named(wanted: StringName) -> int:
	return _parcel_with(&"name", wanted)


## La parcela cuya clave [param key] vale [param wanted], o `-1`.
func _parcel_with(key: StringName, wanted: StringName) -> int:
	for index: int in _plan.parcels.size():
		if StringName(_plan.parcels[index].get(key, &"")) == wanted:
			return index
	return -1


# --------------------------------------------------------------------------
# Parcelas
# --------------------------------------------------------------------------

## Cada parcela entera dentro de su manzana, sin pisar a ninguna vecina, con el
## frente sobre una calle y el edificio apoyado donde manda el plano.
func _check_parcels() -> void:
	for problem: String in _parcel_problems(_plan):
		fail(problem)


## Los incumplimientos de las parcelas de [param plan], como lista de mensajes.
##
## Va aparte del sub-check —mismo patrón que [method TownPlan.graph_problems]—
## para que las **pruebas negativas** corran esta misma rutina sobre planos rotos
## a mano. Antes las negativas llamaban a los ayudantes de [TownPlan]
## (`polygon_contains`, `polygons_overlap`) en vez de al check, así que
## comprobaban que la geometría funciona, no que el check mire.
func _parcel_problems(plan: TownPlan) -> Array[String]:
	var found: Array[String] = []
	var footprints: Array[PackedVector2Array] = []
	for index: int in plan.parcels.size():
		footprints.append(plan.parcel_footprint(index))

	for index: int in plan.parcels.size():
		var parcel := plan.parcels[index]
		var role := int(parcel.get("role", -1))
		var label := String(parcel.get("name", "?"))
		var normal: Vector3 = parcel.get("frontage_normal", Vector3.ZERO)
		if absf(Vector2(normal.x, normal.z).length() - 1.0) > 0.001:
			found.append("la normal de frente de '%s' no es unitaria" % label)
		if absf(normal.y) > 0.001:
			found.append("la normal de frente de '%s' no es horizontal" % label)

		# El edificio apoya a media profundidad hacia adentro de la manzana y
		# mira a la calle: el `-Z` de la pieza tiene que dar sobre la normal.
		var facing := Basis.from_euler(Vector3(0.0, plan.parcel_yaw(index), 0.0)) * Vector3.FORWARD
		if TownPlan.flat_angle(facing, normal) > 0.05:
			found.append("'%s' no mira a la calle" % label)

		var block := int(parcel.get("block", -1))
		# Un POI **rural** —el silo y su galpón— no pertenece a ninguna manzana a
		# propósito (`block: null` en el diseño, `docs/17` §3): está en un lote de
		# campo dentro del círculo. Lo que se le exige es lo contrario que a una
		# casa: que **no** caiga dentro de ninguna manzana.
		if bool(parcel.get("rural", false)):
			for other_block: int in plan.block_count():
				var other_poly := plan.block_polygon(other_block)
				for corner: Vector2 in footprints[index]:
					if TownPlan.polygon_contains(other_poly, corner, -EPSILON):
						found.append("'%s' se declara rural y pisa la manzana %d"
								% [label, other_block])
						break
		elif role != TownPlan.Role.DECOR:
			var street := int(parcel.get("street", -1))
			if street < 0:
				found.append("'%s' no declara sobre qué calle da" % label)
			var poly := plan.block_polygon(block)
			if poly.size() < 3:
				found.append("'%s' dice pertenecer a la manzana %d, que no existe" % [label, block])
			else:
				for corner: Vector2 in footprints[index]:
					if not TownPlan.polygon_contains(poly, corner, -EPSILON):
						found.append("'%s' no entra entera en su manzana (%d)" % [label, block])
						break
				# El frente tiene que estar **sobre un lado** de la manzana, que
				# es lo que quiere decir «con frente a la calle»: si estuviera en
				# el medio, la casa daría al patio.
				#
				# La regla es de **casas**. Un tanque de agua no tiene frente: va
				# en el medio de su lote, que es donde está un tanque de agua
				# (`docs/17` §3, «un lote vacío con pasto alto y el alambrado»).
				# Exigirle línea municipal lo habría empujado contra la vereda y
				# lo habría convertido en un edificio más de la cuadra.
				if role == TownPlan.Role.HOUSE:
					var point: Vector3 = parcel.get("frontage_point", Vector3.ZERO)
					var inset := TownPlan.polygon_inset(poly, Vector2(point.x, point.z))
					if absf(inset) > EPSILON:
						found.append("el frente de '%s' no cae sobre un lado de su manzana (%.3f m)"
								% [label, inset])
				found.append_array(_frontage_matches_street(plan, index, block, street, label))

		# Los solapes se miran **también entre casas de caserío**: las de caserío
		# no tienen manzana (`block = -1`), así que se comparan entre ellas.
		for other: int in index:
			if int(plan.parcels[other].get("block", -2)) != block:
				continue
			if TownPlan.polygons_overlap(footprints[index], footprints[other], 0.02):
				found.append("'%s' se solapa con '%s'"
						% [label, plan.parcels[other].get("name", "?")])
	return found


## Que el lado de manzana sobre el que apoya la parcela sea **el que da a la
## calle que la parcela declara**.
##
## Es la correspondencia que nadie verificaba: una parcela podía declarar
## `street = 3` y estar apoyada sobre el lado que cortó la calle 5, o sobre el
## lado que no cortó ninguna. Se resuelve por [member TownPlan.block_streets],
## que es exacto porque sale de los dos nodos de ese lado.
func _frontage_matches_street(plan: TownPlan, index: int, block: int, street: int,
		label: String) -> Array[String]:
	var found: Array[String] = []
	var poly := plan.block_polygon(block)
	var point: Vector3 = plan.parcels[index].get("frontage_point", Vector3.ZERO)
	var flat := Vector2(point.x, point.z)
	var best := INF
	var best_street := -2
	for edge: int in poly.size():
		var a := poly[(edge - 1 + poly.size()) % poly.size()]
		var b := poly[edge]
		var delta := b - a
		var span := delta.length()
		if span <= 0.0001:
			continue
		var t := clampf((flat - a).dot(delta) / (span * span), 0.0, 1.0)
		var distance := flat.distance_to(a + delta * t)
		if distance < best:
			best = distance
			best_street = plan.block_edge_street(block, edge)
	if best_street != street:
		found.append("'%s' declara dar a la calle %d y apoya sobre el lado de la calle %d"
				% [label, street, best_street])
	if street >= 0 and plan.street_axis(street).is_empty():
		found.append("'%s' declara dar a la calle %d, que no tiene eje" % [label, street])
	return found


# --------------------------------------------------------------------------
# Círculo de juego
# --------------------------------------------------------------------------

## Todo lo destructible adentro, todo lo decorativo afuera.
func _check_circle() -> void:
	var inside := 0
	var outside := 0
	for index: int in _plan.parcels.size():
		var parcel := _plan.parcels[index]
		var position := _plan.parcel_position(index)
		var destructible := bool(parcel.get("destructible", false))
		if destructible:
			if _plan.is_inside(position):
				inside += 1
			else:
				outside += 1
				fail("'%s' es destructible y cae a %.1f m del centro (radio %.0f)"
						% [parcel.get("name", "?"), _plan.distance_to_centre(position),
						_plan.play_radius])
			continue
		expect(not _plan.is_inside(position),
				"'%s' es decorativa y cae dentro del círculo (%.1f m)"
				% [parcel.get("name", "?"), _plan.distance_to_centre(position)])
	expect(outside == 0, "hay %d destructibles fuera del círculo" % outside)
	expect(inside == _plan.destructible_count(),
			"destructible_count() dice %d y adentro hay %d" % [_plan.destructible_count(), inside])


# --------------------------------------------------------------------------
# Roles y HP
# --------------------------------------------------------------------------

## El reparto de roles —el que declara el diseño— y el HP total que recalibra el
## balance.
func _check_roles() -> void:
	var houses := _plan.parcels_of_role(TownPlan.Role.HOUSE).size()
	var mediums := _plan.parcels_of_role(TownPlan.Role.MEDIUM).size()
	var landmarks := _plan.parcels_of_role(TownPlan.Role.LANDMARK).size()
	var schools := _plan.parcels_of_role(TownPlan.Role.SCHOOL).size()

	expect(schools == 1, "hay %d escuelas, esperada 1" % schools)
	expect(landmarks >= 1, "el pueblo no tiene hito")
	for index: int in _plan.parcels_of_role(TownPlan.Role.DECOR):
		var reach := _plan.distance_to_centre(_plan.parcel_position(index))
		expect(reach >= HAMLET_MIN and reach <= HAMLET_MAX,
				"'%s' está a %.1f m del centro, fuera de [%.0f, %.0f]: a más de eso"
				% [_plan.parcels[index].get("name", "?"), reach, HAMLET_MIN, HAMLET_MAX]
				+ " no se ve al anochecer y a menos se mete en el círculo")

	var school := _plan.school_parcel()
	expect(school >= 0, "el plano no tiene escuela")
	if school >= 0:
		expect(String(_plan.parcels[school].get("name", "")) == String(TownPlan.SCHOOL_NODE),
				"la escuela se llama '%s' y `round_catalog` busca '%s'"
				% [_plan.parcels[school].get("name", "?"), TownPlan.SCHOOL_NODE])
		# **Dónde** va la escuela cambió en WP-D2. Hasta la tanda 1 era «la
		# parcela grande de ruta más cercana al centro», que es lo que un sorteo
		# puede garantizar; desde `docs/17` §2 es una decisión de diseño: manzana
		# 8, fachada al este sobre la calle 4 y **enfrente de la plaza**, que es
		# lo que hace que quien llega a la plaza vea la escuela entera y entienda
		# qué está defendiendo. Así que lo que se mide es eso: que dé a una calle
		# de verdad, que esté en el corazón y que la plaza esté enfrente.
		expect(int(_plan.parcels[school].get("street", -1)) >= 0,
				"la escuela no da a ninguna calle")
		var school_reach := _plan.distance_to_centre(_plan.parcel_position(school))
		expect(school_reach <= SCHOOL_REACH_MAX,
				"la escuela está a %.1f m del centro (tope %.0f): tiene que estar en el anillo 0"
				% [school_reach, SCHOOL_REACH_MAX])
		if _plan.has_plaza():
			var plaza_centre := TownPlan.polygon_centroid(_plan.plaza_polygon)
			var school_at := _plan.parcel_position(school)
			var gap := Vector2(school_at.x, school_at.z).distance_to(plaza_centre)
			expect(gap <= SCHOOL_PLAZA_MAX,
					"la escuela está a %.1f m de la plaza (tope %.0f): tiene que mirarla"
					% [gap, SCHOOL_PLAZA_MAX])
			# Y **mirarla**: la normal de su fachada tiene que apuntar a la plaza.
			var normal: Vector3 = _plan.parcels[school].get("frontage_normal", Vector3.FORWARD)
			expect(TownPlan.flat_angle(normal,
					Vector3(plaza_centre.x - school_at.x, 0.0, plaza_centre.y - school_at.z))
					<= SCHOOL_PLAZA_ANGLE,
					"la escuela no mira a la plaza (%.1f°, tope %.0f)"
					% [TownPlan.flat_angle(normal, Vector3(plaza_centre.x - school_at.x, 0.0,
					plaza_centre.y - school_at.z)), SCHOOL_PLAZA_ANGLE])

	var expected := float(houses) * float(TownPlan.ROLE_HP[TownPlan.Role.HOUSE]) \
			+ float(mediums + landmarks + schools) * float(TownPlan.ROLE_HP[TownPlan.Role.MEDIUM])
	var total := _plan.total_hp()
	expect_near(total, expected, expected * HP_TOLERANCE,
			"total_hp() da %.0f y los roles dicen %.0f" % [total, expected])


# --------------------------------------------------------------------------
# Ventanas
# --------------------------------------------------------------------------

## El racionamiento apaga exactamente `round(manzanas · 0,30)` manzanas.
func _check_windows() -> void:
	var wanted := roundi(float(_plan.block_count()) * TownPlan.DARK_BLOCK_RATIO)
	var dark := _plan.dark_blocks()
	expect(dark.size() == wanted,
			"dark_blocks() apagó %d manzanas de %d, esperadas %d"
			% [dark.size(), _plan.block_count(), wanted])
	for block: int in dark.keys():
		expect(block >= 0 and block < _plan.block_count(),
				"dark_blocks() apagó la manzana %d, que no existe" % block)
		expect(_plan.is_block_dark(block), "is_block_dark(%d) no coincide con dark_blocks()" % block)


# --------------------------------------------------------------------------
# Marcadores
# --------------------------------------------------------------------------

## Apariciones, puestos de pila, dron y cámara.
func _check_markers() -> void:
	var spawns := _plan.spawn_points()
	expect(spawns.size() == SPAWNS, "hay %d apariciones, esperadas %d" % [spawns.size(), SPAWNS])
	var radius := _plan.play_radius + SPAWN_MARGIN
	var on_route := 0
	for index: int in spawns.size():
		var origin := spawns[index].origin
		expect_near(_plan.distance_to_centre(origin), radius, 1.0,
				"la aparición %d no está a %.0f m del centro" % [index, radius])
		var facing := -spawns[index].basis.z
		expect_near(TownPlan.flat_angle(facing, _plan.play_centre - origin), 0.0, 0.5,
				"la aparición %d no mira al centro" % index)
		if _plan.route_offset(origin) < _plan.route_width:
			on_route += 1
	expect(on_route == 2,
			"hay %d apariciones sobre la ruta, esperadas 2 (entrada y salida)" % on_route)

	var posts := _plan.battery_posts()
	expect(posts.size() == POSTS, "hay %d puestos de pila, esperados %d" % [posts.size(), POSTS])
	for index: int in mini(POSTS_STREET, posts.size()):
		expect(posts[index].y >= POST_Y_MIN - 0.01 and posts[index].y <= POST_Y_MAX + 0.01,
				"el puesto de calle %d está a %.2f m, fuera de [%.0f, %.0f]"
				% [index, posts[index].y, POST_Y_MIN, POST_Y_MAX])
		expect(_plan.is_inside(posts[index]), "el puesto de calle %d cae fuera del círculo" % index)
		# Un puesto de calle cae **o sobre un cruce del grafo o sobre un toldo**.
		#
		# Hasta la tanda 1 los cinco salían de sortear nodos, y la regla era «cae
		# sobre un nodo». Desde WP-D2 el diseño declara los cuatro primeros para
		# cumplir la gramática de `docs/17` §4 —toldo naranja = pila—, así que la
		# regla se parte en dos mitades que dicen lo mismo con más precisión: un
		# puesto sorteado sigue sobre un cruce, y uno declarado tiene que tener su
		# toldo, su parada o su estación de servicio a menos de cuatro metros. Un
		# puesto que no cumpliera ninguna de las dos sería una pila en el aire.
		var on_node := _nearest_node_distance(posts[index]) <= EPSILON
		expect(on_node or _awning_distance(posts[index]) <= TownDesign.AWNING_REACH,
				"el puesto de calle %d no cae ni sobre un nodo del grafo ni bajo un toldo"
				% index + " (toldo más cercano a %.2f m)" % _awning_distance(posts[index]))
	for index: int in range(POSTS_STREET, posts.size()):
		expect(posts[index].y > POST_Y_MAX,
				"el puesto de azotea %d está a %.2f m, que no es una azotea"
				% [index, posts[index].y])

	var drone := _plan.drone_spawn()
	expect_near(_plan.distance_to_centre(drone.origin), DRONE_DISTANCE, 2.0,
			"el dron aparece a %.1f m del centro, esperados %.0f"
			% [_plan.distance_to_centre(drone.origin), DRONE_DISTANCE])
	expect_near(drone.origin.y, DRONE_HEIGHT, 0.01, "el dron no aparece a 1,5 m")
	expect(_plan.route_offset(drone.origin) < _plan.route_width,
			"el dron no aparece sobre la ruta")
	expect_near(TownPlan.flat_angle(-drone.basis.z, _plan.play_centre - drone.origin), 0.0, 0.5,
			"el dron no aparece mirando al pueblo")

	var camera := _plan.camera_fixed()
	expect(camera.origin.y > 60.0, "la cámara fija está a %.1f m de altura" % camera.origin.y)
	expect_near(TownPlan.flat_angle(-camera.basis.z, _plan.play_centre - camera.origin), 0.0, 0.5,
			"la cámara fija no mira al centro")

	expect(_plan.get_extent().x > _plan.get_core_extent().x,
			"get_extent() no deja margen sobre get_core_extent()")
	expect_near(_plan.get_core_extent().x, _plan.play_radius * 2.0, 0.01,
			"get_core_extent() no es el diámetro del círculo")


## Distancia en XZ de [param point] al toldo, parada o estación de servicio más
## cercano, o `INF` si el pueblo no tiene ninguno.
##
## Mira el **plano**, no la escena: la estación de servicio es un POI y los
## toldos son props, y los dos viven en el plano aunque su pieza todavía no
## exista en disco. Es lo que permite verificar la gramática de `docs/17` §4
## antes de que WP-D1 entregue el toldo.
func _awning_distance(point: Vector3) -> float:
	var flat := Vector2(point.x, point.z)
	var best := INF
	for prop: Dictionary in _plan.prop_placements:
		if not TownDesign.AWNING_PIECES.has(StringName(prop.get("piece", &""))):
			continue
		var at: Vector3 = prop.get("pos", Vector3.ZERO)
		best = minf(best, flat.distance_to(Vector2(at.x, at.z)))
	for entry: Variant in _design.poi():
		var data: Dictionary = entry
		if not TownDesign.AWNING_PIECES.has(StringName(String(data.get("piece", "")))):
			continue
		var pos: Variant = TownDesign.to_vector2(data.get("pos", null))
		if pos == null:
			continue
		best = minf(best, flat.distance_to(pos as Vector2))
	return best


func _nearest_node_distance(point: Vector3) -> float:
	var best := INF
	for node: Dictionary in _plan.nodes:
		var pos: Vector3 = node.get("pos", Vector3.ZERO)
		best = minf(best, Vector2(point.x - pos.x, point.z - pos.z).length())
	return best


# --------------------------------------------------------------------------
# Rocas
# --------------------------------------------------------------------------

## Las rocas, fuera del círculo y fuera del cono de visión inicial del dron.
func _check_rocks() -> void:
	var spots := _plan.rock_spots()
	expect(not spots.is_empty(), "el pueblo no tiene ni una roca")
	for index: int in spots.size():
		expect(not _plan.is_inside(spots[index]),
				"la roca %d cae dentro del círculo (%.1f m)"
				% [index, _plan.distance_to_centre(spots[index])])
		expect(_plan.spawn_cone_angle(spots[index]) >= ROCK_CONE_DEG,
				"la roca %d está a %.1f° de la línea de visión del dron (mínimo %.0f)"
				% [index, _plan.spawn_cone_angle(spots[index]), ROCK_CONE_DEG])


# --------------------------------------------------------------------------
# Determinismo posicional
# --------------------------------------------------------------------------

## Un cambio local en el diseño tiene un efecto local en el plano.
##
## Es **la** propiedad que hace editable un diseño escrito a mano: recolorear la
## casa 2 de la manzana 7 tiene que cambiar su línea de la firma y la del hash
## del diseño, y ninguna otra. Con una semilla global —que es como funcionaba
## hasta P2b— agregar una casa volvía a barajar el pueblo entero y el `diff` del
## `.tscn` horneado dejaba de decir qué se había tocado.
func _check_positional() -> void:
	var target := _first_house()
	if target.is_empty():
		fail("determinismo posicional: el diseño no trae ninguna casa que variar")
		return
	var block := int(target["block"])
	var slot := int(target["slot"])
	var label := "%s%02d_%02d" % [TownPlan.HOUSE_PREFIX, block, slot]

	# 1. Recolorear: el color llega al plano y la firma cambia en dos líneas.
	var recoloured_data := _design.raw_data()
	var house := _house_data(recoloured_data, block, slot)
	var colour := int(house.get("color", 0))
	house["color"] = colour + 1
	var recoloured := TownDesign.from_data(recoloured_data)
	if recoloured == null:
		fail("determinismo posicional: recolorear una casa rompió la validación")
		return
	var repainted := TownPlanner.resolve(recoloured, _terrain)
	var parcel := _parcel_of(repainted, label)
	expect(parcel >= 0 and int(repainted.parcels[parcel].get("color", -1)) == colour + 1,
			"determinismo posicional: '%s' no conservó el color nuevo" % label)
	var moved_lines := _signature_diff(_plan, repainted)
	expect(not moved_lines.is_empty(),
			"determinismo posicional: recolorear una casa no cambió nada de la firma")
	for line: String in moved_lines:
		expect(_local_to(line, label),
				"determinismo posicional: recolorear '%s' también cambió «%s»"
				% [label, line.substr(0, 40)])

	# 2. Mover: la casa se corre y ninguna otra parcela se entera.
	var moved_data := _design.raw_data()
	var to_move := _house_data(moved_data, block, slot)
	to_move["t"] = clampf(float(to_move.get("t", 0.5)) + 0.03, 0.0, 1.0)
	var moved_design := TownDesign.from_data(moved_data)
	if moved_design == null:
		fail("determinismo posicional: mover una casa rompió la validación")
		return
	var shifted := TownPlanner.resolve(moved_design, _terrain)
	for line: String in _signature_diff(_plan, shifted):
		expect(_local_to(line, label),
				"determinismo posicional: mover '%s' también cambió «%s»"
				% [label, line.substr(0, 40)])
	var before := _parcel_of(_plan, label)
	var after := _parcel_of(shifted, label)
	expect(before >= 0 and after >= 0
			and _plan.parcel_position(before).distance_to(shifted.parcel_position(after)) > 0.1,
			"determinismo posicional: mover el `t` de '%s' no la movió" % label)


## Verdadero si [param line] de la firma es una consecuencia **local** de haber
## tocado la parcela [param label].
##
## Tres cosas pueden cambiar legítimamente: la huella del diseño (`design=`), la
## línea de esa parcela o de un prop suyo —las dos llevan su nombre entre barras,
## que es para lo que el prop guarda de quién es— y el resumen de cercos. Este
## último es el único agregado que queda, y cambia porque el **cerco del frente**
## de una casa viaja con ella: moverla mueve sus cuatro tramos de tabla. Que no
## se mueva nada más lo garantiza la siembra por celda, y lo verifica
## [method _check_grove_determinism].
func _local_to(line: String, label: String) -> bool:
	return line.begins_with("design=") or line.begins_with("fences=") \
			or line.contains("|%s|" % label)


## Las líneas de la firma de [param b] que no están en la de [param a].
func _signature_diff(a: TownPlan, b: TownPlan) -> PackedStringArray:
	var before := a.signature().split("\n")
	var after := b.signature().split("\n")
	var found := PackedStringArray()
	for index: int in maxi(before.size(), after.size()):
		var left := before[index] if index < before.size() else "<falta>"
		var right := after[index] if index < after.size() else "<falta>"
		if left != right:
			found.append(right)
	return found


## La primera casa declarada del diseño, como `{block, slot}`.
func _first_house() -> Dictionary:
	for block: int in _design.block_count():
		var houses: Array[Dictionary] = _design.block(block)["houses"]
		if not houses.is_empty():
			return {"block": block, "slot": 0}
	return {}


## El diccionario crudo de la casa [param slot] de la manzana [param block]
## dentro de [param data].
func _house_data(data: Dictionary, block: int, slot: int) -> Dictionary:
	var blocks: Array = data.get("blocks", [])
	var entry: Dictionary = blocks[block]
	var houses: Array = entry.get("houses", [])
	return houses[slot]


## La parcela de [param plan] que se llama [param label], o `-1`.
func _parcel_of(plan: TownPlan, label: String) -> int:
	for index: int in plan.parcels.size():
		if String(plan.parcels[index].get("name", "")) == label:
			return index
	return -1


# --------------------------------------------------------------------------
# Escena horneada
# --------------------------------------------------------------------------

## Que `town_a.tscn` traiga los nodos y el grupo que el resto del juego busca.
func _check_baked_scene() -> void:
	var file := FileAccess.open(TOWN_SCENE, FileAccess.READ)
	if file == null:
		fail("no se puede leer '%s': hay que correr `tools/build_town.gd`" % TOWN_SCENE)
		return
	var text := file.get_as_text()
	file.close()
	for needle: String in BAKED_MARKERS:
		expect(text.contains(needle), "'%s' no trae `%s`" % [TOWN_SCENE, needle])
	# El pueblo no hornea oclusores: sus casas son cajas de 5 m en manzanas
	# abiertas, donde una caja oclusora tapa más de lo que ahorra, y la oclusión
	# está apagada en todos los presets desde WP-24e.
	expect(not text.contains("[node name=\"Occluders\""),
			"'%s' trae oclusores y el pueblo no hornea ninguno" % TOWN_SCENE)


# --------------------------------------------------------------------------
# Pruebas negativas
# --------------------------------------------------------------------------

## Un plano y un diseño rotos a mano tienen que fallar las mismas comprobaciones
## que los buenos aprueban. Sin esto no habría forma de saber si los sub-checks
## miden algo.
func _check_negative() -> void:
	# Los diseños rotos de abajo emiten sus errores a propósito: se callan para
	# que una corrida en verde no deje `ERROR:` en el log de CI, que es la forma
	# más rápida de enseñarle a un equipo a ignorar los errores del log.
	TownDesign.report_to_log = false
	_negative_parcels()
	_negative_graph()
	_negative_design()
	TownDesign.report_to_log = true


## Cuatro parcelas rotas contra [method _parcel_problems].
func _negative_parcels() -> void:
	var broken := TownPlanner.resolve(_design, _terrain)
	var target := _first_role(broken, TownPlan.Role.HOUSE)
	if target < 0:
		fail("prueba negativa: el plano no trae ninguna casa que romper")
		return

	# Punto de partida: el plano bueno no tiene ningún incumplimiento. Si esto
	# fallara, las cuatro negativas de abajo no querrían decir nada.
	expect(_parcel_problems(broken).is_empty(),
			"prueba negativa: el plano intacto ya trae incumplimientos de parcela")

	# 1. Una parcela corrida hacia la calle deja de entrar en su manzana **y**
	#    deja de apoyar sobre un lado.
	var parcel := broken.parcels[target].duplicate()
	var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
	var label := String(parcel.get("name", "?"))
	parcel["frontage_point"] = (parcel["frontage_point"] as Vector3) + normal * 12.0
	broken.parcels[target] = parcel
	expect(_has_problem(_parcel_problems(broken), label),
			"prueba negativa: _parcel_problems() aprobó una parcela corrida 12 m a la calle")
	broken = TownPlanner.resolve(_design, _terrain)

	# 2. Dos parcelas de la misma manzana encimadas.
	var twin := _first_role(broken, TownPlan.Role.HOUSE)
	var mate := _second_in_block(broken, twin)
	if mate < 0:
		fail("prueba negativa: no hay dos casas en la misma manzana que encimar")
	else:
		var moved := broken.parcels[mate].duplicate()
		moved["frontage_point"] = broken.parcels[twin].get("frontage_point", Vector3.ZERO)
		moved["frontage_normal"] = broken.parcels[twin].get("frontage_normal", Vector3.FORWARD)
		broken.parcels[mate] = moved
		expect(_has_problem(_parcel_problems(broken), String(moved.get("name", "?"))),
				"prueba negativa: _parcel_problems() aprobó dos parcelas encimadas")
	broken = TownPlanner.resolve(_design, _terrain)

	# 3. Una parcela que declara dar a otra calle que la de su lado.
	var liar := _first_role(broken, TownPlan.Role.HOUSE)
	var swapped := broken.parcels[liar].duplicate()
	var wrong := int(swapped.get("street", 0)) + 1
	swapped["street"] = wrong if wrong <= broken.street_count() else 0
	broken.parcels[liar] = swapped
	expect(_has_problem(_parcel_problems(broken), String(swapped.get("name", "?"))),
			"prueba negativa: _parcel_problems() aprobó un frente que declara la calle equivocada")
	broken = TownPlanner.resolve(_design, _terrain)

	# 4. Una casa girada un cuarto de vuelta enseña a la calle su pared lateral.
	var turned := _first_role(broken, TownPlan.Role.HOUSE)
	var sideways := broken.parcels[turned].duplicate()
	var face: Vector3 = sideways.get("frontage_normal", Vector3.FORWARD)
	sideways["frontage_normal"] = Vector3(-face.z, 0.0, face.x)
	broken.parcels[turned] = sideways
	expect(_has_problem(_parcel_problems(broken), String(sideways.get("name", "?"))),
			"prueba negativa: _parcel_problems() aprobó una casa girada 90°")


## Dos grafos rotos contra [method TownPlan.graph_problems].
func _negative_graph() -> void:
	var broken := TownPlanner.resolve(_design, _terrain)
	expect(broken.graph_problems().is_empty(),
			"prueba negativa: el grafo intacto ya trae incumplimientos")

	# 1. Un cabo al que le sacan el cierre.
	var stub := -1
	for street: int in broken.graph_street_count():
		if broken.node_of(street, 0) < 0:
			stub = street
			break
	if stub < 0:
		fail("prueba negativa: el pueblo no trae ningún cabo que destapar")
	else:
		var closures := broken.street_closures
		closures[stub] = ""
		broken.street_closures = closures
		expect(not broken.graph_problems().is_empty(),
				"prueba negativa: graph_problems() aprobó un cabo sin cierre")
	broken = TownPlanner.resolve(_design, _terrain)

	# 2. Un nodo corrido veinte metros deja a su calle colgando.
	var moved := broken.nodes.duplicate(true)
	var anchor := -1
	for street: int in broken.graph_street_count():
		if broken.node_of(street, 0) >= 0:
			anchor = broken.node_of(street, 0)
			break
	if anchor < 0:
		fail("prueba negativa: ninguna calle llega a un nodo")
		return
	var node: Dictionary = moved[anchor]
	node["pos"] = (node["pos"] as Vector3) + Vector3(20.0, 0.0, 0.0)
	moved[anchor] = node
	broken.nodes = moved
	expect(not broken.graph_problems().is_empty(),
			"prueba negativa: graph_problems() aprobó una calle a 20 m de su nodo")


## Tres diseños rotos contra la validación de [TownDesign].
func _negative_design() -> void:
	# 1. Una calle que muere en el campo sin cierre.
	var data := _design.raw_data()
	var streets: Array = data["streets"]
	var street: Dictionary = streets[0]
	street["closure_a"] = "none"
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó un diseño con una calle sin nodo ni cierre")
	expect(_has_problem(_failure_problems(), String(street["id"])),
			"prueba negativa: el diagnóstico no nombra la calle sin cierre")

	# 2. Una manzana cóncava.
	data = _design.raw_data()
	var blocks: Array = data["blocks"]
	var block: Dictionary = blocks[0]
	var nodes: Array = block["nodes"]
	# Se cruzan el segundo y el tercero, no el primero y el tercero: permutar 0
	# con 2 en un cuadrilátero da el **mismo** anillo recorrido al revés, que
	# sigue siendo convexo y no prueba nada. Con 1 y 2 sale un moño.
	var swap: Variant = nodes[1]
	nodes[1] = nodes[2]
	nodes[2] = swap
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó un diseño con una manzana cruzada")

	# 3. Una casa fuera de su frente.
	data = _design.raw_data()
	var target := _first_house()
	if target.is_empty():
		return
	_house_data(data, int(target["block"]), int(target["slot"]))["t"] = 1.4
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó un diseño con una casa en t = 1,4")

	# 4. Un JSON con un comentario **tiene** que cargar: el diseño lo escribe una
	#    persona y anotar por qué una calle muere donde muere es media
	#    documentación del nivel.
	var commented := TownDesign.load_text("{\n// por qué\n\"version\": 1,\n\"nodes\": []\n}",
			"<comentario>")
	expect(commented == null and _has_problem(_failure_problems(), "nodo"),
			"prueba negativa: un diseño vacío con comentario no dio el diagnóstico esperado")
	expect(not _has_problem(_failure_problems(), "JSON inválido"),
			"prueba negativa: el comentario `//` rompió el parseo")

	# 5. Un POI que dice estar en una manzana que no existe.
	data = _design.raw_data()
	var poi: Array = data["poi"]
	(poi[0] as Dictionary)["block"] = "m99"
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó un POI en la manzana 'm99'")
	expect(_has_problem(_failure_problems(), "m99"),
			"prueba negativa: el diagnóstico no nombra la manzana inventada")

	# 6. Un cerco de una clase que no existe. Es la diferencia entre el cerco de
	#    **línea** —que tiene pieza y largo de tramo— y el `fence` decorativo del
	#    frente de una casa: `hedge` vale para el segundo y no para el primero.
	data = _design.raw_data()
	var fences: Array = data["fences"]
	(fences[0] as Dictionary)["kind"] = "hedge"
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó un cerco de línea de clase 'hedge'")

	# 7. Un marcador de una clase que no existe.
	data = _design.raw_data()
	var markers: Array = data["markers"]
	(markers[0] as Dictionary)["kind"] = "linterna"
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó un marcador de clase 'linterna'")

	# 8. Una arboleda con una especie de peso cero: sembraría cero de esa especie
	#    en silencio, que es peor que no declararla.
	data = _design.raw_data()
	var groves: Array = data["groves"]
	var species: Array = (groves[0] as Dictionary)["species"]
	(species[0] as Dictionary)["weight"] = 0.0
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó una arboleda con una especie de peso cero")

	# 9. Una plaza que no es convexa: la losa saldría con el abanico dado vuelta.
	data = _design.raw_data()
	var plaza: Dictionary = data["plaza"]
	var polygon: Array = plaza["polygon"]
	var corner: Variant = polygon[1]
	polygon[1] = polygon[2]
	polygon[2] = corner
	expect(TownDesign.from_data(data) == null,
			"prueba negativa: se cargó una plaza con el polígono cruzado")


## Los incumplimientos del último diseño rechazado.
func _failure_problems() -> Array[String]:
	var failure := TownDesign.last_failure()
	var found: Array[String] = []
	if failure == null:
		return found
	for problem: String in failure.problems:
		found.append(problem)
	return found


## Verdadero si algún incumplimiento nombra a [param label].
func _has_problem(problems: Array[String], label: String) -> bool:
	for problem: String in problems:
		if problem.contains(label):
			return true
	return false


## La primera parcela de rol [param role].
func _first_role(plan: TownPlan, role: int) -> int:
	var found := plan.parcels_of_role(role)
	return found[0] if not found.is_empty() else -1


## Otra parcela de la misma manzana que [param index], o `-1`.
func _second_in_block(plan: TownPlan, index: int) -> int:
	if index < 0:
		return -1
	var block := int(plan.parcels[index].get("block", -2))
	for other: int in plan.parcels.size():
		if other != index and int(plan.parcels[other].get("block", -3)) == block:
			return other
	return -1


# --------------------------------------------------------------------------
# Informe
# --------------------------------------------------------------------------

## Los números del plano, para leerlos en el log del check sin correr la
## herramienta de horneado.
func _report() -> void:
	print("  diseño %s · hash %d · variación %d"
			% [DESIGN_PATH.get_file(), _design.design_hash(), _design.variation_seed()])
	print("  radio %.0f m · disco %.0f m · campo %.0f m"
			% [_plan.play_radius, _plan.block_radius, _plan.field_size])
	print("  ruta: %d vértices · %.0f m de largo · pasa a %.1f m del centro"
			% [_plan.route.size(), _plan.route_length(),
			_plan.distance_to_centre(_plan.route_point(_plan.route_centre_distance()))])
	print("  grafo: %d nodos · %d calles · %d cabos · manzanas %d (%.0f–%.0f m²)"
			% [_plan.nodes.size(), _plan.graph_street_count(), _stub_count(),
			_plan.block_count(), _min_area(), _max_area()])
	print("  parcelas: %d casas · %d medianos · %d hito · %d escuela · %d caserío"
			% [_plan.parcels_of_role(TownPlan.Role.HOUSE).size(),
			_plan.parcels_of_role(TownPlan.Role.MEDIUM).size(),
			_plan.parcels_of_role(TownPlan.Role.LANDMARK).size(),
			_plan.parcels_of_role(TownPlan.Role.SCHOOL).size(),
			_plan.parcels_of_role(TownPlan.Role.DECOR).size()])
	print("  destructibles: %d · HP total: %.0f · rocas %d · maleza %d · apagadas %d"
			% [_plan.destructible_count(), _plan.total_hp(), _plan.rocks.size(),
			_plan.decor.size(), _plan.dark_blocks().size()])


func _stub_count() -> int:
	var total := 0
	for street: int in _plan.graph_street_count():
		for end: int in 2:
			if _plan.node_of(street, end) < 0:
				total += 1
	return total


func _min_area() -> float:
	var best := INF
	for index: int in _plan.block_count():
		best = minf(best, _plan.block_area(index))
	return 0.0 if is_inf(best) else best


func _max_area() -> float:
	var best := 0.0
	for index: int in _plan.block_count():
		best = maxf(best, _plan.block_area(index))
	return best


# --------------------------------------------------------------------------
# Plaza, arboledas, cercos y props (P2c, WP-D2)
# --------------------------------------------------------------------------

## La plaza: polígono resuelto, manzana sin casas y props sembrados.
##
## «Sin casas» no se mide contra el diseño —que podría declarar una plaza donde
## quisiera— sino contra el **plano**: qué manzana contiene el polígono lo
## decide el resolvedor y quién vive en esa manzana lo dicen las parcelas. Es la
## diferencia entre creerle al diseño y comprobar que la plaza está vacía.
func _check_plaza() -> void:
	var declared := _design.plaza()
	if declared.is_empty():
		expect(not _plan.has_plaza(), "el plano trae plaza y el diseño no la declara")
		return
	expect(_plan.has_plaza(), "el diseño declara plaza y el plano no la trae")
	if not _plan.has_plaza():
		return
	var polygon := TownDesign.to_vector2_list(declared.get("polygon", null))
	expect(_plan.plaza_polygon.size() == polygon.size(),
			"la plaza declara %d vértices y el plano resolvió %d"
			% [polygon.size(), _plan.plaza_polygon.size()])
	for index: int in mini(polygon.size(), _plan.plaza_polygon.size()):
		expect_near(polygon[index].distance_to(_plan.plaza_polygon[index]), 0.0,
				DESIGN_TOLERANCE, "el vértice %d de la plaza no quedó donde el diseño lo puso"
				% index)
	expect(_plan.plaza_block >= 0, "la plaza no cae dentro de ninguna manzana")
	var houses := 0
	for index: int in _plan.parcels.size():
		if int(_plan.parcels[index].get("block", -1)) != _plan.plaza_block:
			continue
		if int(_plan.parcels[index].get("role", -1)) == TownPlan.Role.HOUSE:
			houses += 1
	expect(houses == 0,
			"la manzana de la plaza (%d) tiene %d casas y tiene que estar vacía"
			% [_plan.plaza_block, houses])
	# El polígono de la plaza entra entero en su manzana: si se saliera, la losa
	# taparía la vereda y el cordón.
	var block := _plan.block_polygon(_plan.plaza_block)
	for corner: Vector2 in _plan.plaza_polygon:
		expect(TownPlan.polygon_contains(block, corner, -EPSILON),
				"la plaza se sale de su manzana")
		break
	print("  plaza: manzana %d, %.0f m², 0 casas, %d props propios"
			% [_plan.plaza_block, TownPlan.polygon_area(_plan.plaza_polygon),
			_design.plaza_props().size()])


## Las arboledas: cada una siembra lo que su densidad promete (±10 %) y ninguna
## instancia cae donde no puede.
##
## El conteo esperado es `área · densidad`: la siembra es una instancia por
## celda de `1/√densidad` metros de lado, así que un polígono de mil metros
## cuadrados a 0,018 por metro cuadrado da dieciocho árboles. La tolerancia del
## diez por ciento es por los bordes: una celda cuyo centro cae fuera del
## polígono no siembra, y eso se nota en una arboleda angosta.
func _check_groves() -> void:
	var declared := _design.groves()
	expect(_plan.grove_species_count() > 0 or declared.is_empty(),
			"el diseño declara %d arboledas y el plano no sembró ninguna especie"
			% declared.size())
	var total := 0
	for index: int in declared.size():
		var grove: Dictionary = declared[index]
		var polygon := TownDesign.to_vector2_list(grove.get("polygon", null))
		var density := float(grove.get("density", 0.0))
		var wanted := TownPlan.polygon_area(polygon) * density
		var found := _plan.grove_instances_of(index)
		total += found
		# La arboleda que pide separación mínima siembra **menos** de lo que su
		# densidad promete: cada vez que dos celdas vecinas se acercan más de lo
		# permitido, la segunda cede. Es el precio de que dos sauces de cinco
		# metros de copa no se pisen, y se paga en una banda más ancha —medido:
		# 11 y 12 % menos— en vez de en una densidad mentida.
		var tolerance := GROVE_COUNT_TOLERANCE
		if float(grove.get("min_spacing", 0.0)) > 0.0:
			tolerance = GROVE_SPACED_TOLERANCE
		expect(absf(float(found) - wanted) <= maxf(wanted * tolerance, 3.0),
				"la arboleda '%s' sembró %d y su densidad pide %.0f (±%.0f %%)"
				% [grove.get("id", index), found, wanted, tolerance * 100.0])
		# Las especies del plano son las que la arboleda declara y ninguna más.
		var allowed: Array[StringName] = []
		for choice: Dictionary in _design.grove_species(index):
			allowed.append(StringName(choice["piece"]))
		for slot: int in _plan.grove_species.size():
			var used := false
			for source: int in _plan.grove_source[slot]:
				if source == index:
					used = true
					break
			if used:
				expect(allowed.has(StringName(_plan.grove_species[slot])),
						"la arboleda '%s' sembró '%s', que no declara"
						% [grove.get("id", index), _plan.grove_species[slot]])

	# Ninguna instancia dentro de una calle, de una manzana, de una huella ni a
	# menos de doce metros del eje de la ruta.
	var footprints: Array[PackedVector2Array] = []
	for index: int in _plan.parcels.size():
		footprints.append(_plan.parcel_footprint(index))
	var worst_route := INF
	var problems := 0
	for slot: int in _plan.grove_species.size():
		for point: Vector3 in _plan.grove_points[slot]:
			var flat := Vector2(point.x, point.z)
			worst_route = minf(worst_route, TownPlan.polyline_distance(_plan.route, flat))
			if problems >= 6:
				continue
			for street: int in _plan.graph_street_count():
				var axis := _plan.street_axis(street)
				if axis.size() < 2:
					continue
				if TownPlan.polyline_distance(axis, flat) < _plan.street_half_of(street):
					fail("un '%s' cayó dentro de la calle %d" % [_plan.grove_species[slot], street])
					problems += 1
					break
			for block: int in _plan.block_count():
				if TownPlan.polygon_contains(_plan.block_polygon(block), flat):
					fail("un '%s' cayó dentro de la manzana %d"
							% [_plan.grove_species[slot], block])
					problems += 1
					break
			for footprint: PackedVector2Array in footprints:
				if footprint.size() >= 3 and TownPlan.polygon_contains(footprint, flat):
					fail("un '%s' cayó sobre una huella" % _plan.grove_species[slot])
					problems += 1
					break
	expect(worst_route >= GROVE_ROUTE_MIN or _plan.grove_total() == 0,
			"la instancia de arboleda más cercana a la ruta está a %.2f m (mínimo %.0f)"
			% [worst_route, GROVE_ROUTE_MIN])
	var by_species: PackedStringArray = PackedStringArray()
	for slot: int in _plan.grove_species.size():
		by_species.append("%s %d" % [_plan.grove_species[slot], _plan.grove_count(slot)])
	print("  arboledas: %d polígonos · %d instancias (%s) · la más cercana a la ruta a %.1f m"
			% [declared.size(), total, ", ".join(by_species),
			0.0 if is_inf(worst_route) else worst_route])


## Los cercos: el largo que promete cada polilínea y ni un tramo sobre la
## calzada.
func _check_fences() -> void:
	var declared := _design.fences()
	var wanted := 0.0
	for index: int in declared.size():
		var fence: Dictionary = declared[index]
		var line := TownDesign.to_vector2_list(fence.get("polyline", null))
		for segment: int in maxi(line.size() - 1, 0):
			wanted += line[segment].distance_to(line[segment + 1])
	var built := 0.0
	for kind: int in TownDesign.FENCE_LINE_KINDS.size():
		built += _plan.fence_length_of(kind)
	# El cerco construido es **menor** que la polilínea: cada tramo es una pieza
	# entera y los huecos de las calles se descuentan. Que no sea mayor es lo que
	# dice que no se estiró ninguna pieza.
	expect(built <= wanted + 0.01 or declared.is_empty(),
			"los cercos suman %.0f m de pieza sobre %.0f m de polilínea" % [built, wanted])
	var crossing := 0
	for index: int in _plan.fence_points.size():
		var kind := _plan.fence_kinds[index]
		var span := float(TownDesign.FENCE_SPAN.get(
				TownDesign.FENCE_LINE_KINDS[kind], 6.0))
		var yaw := _plan.fence_yaws[index]
		var start: Vector3 = _plan.fence_points[index]
		var finish := Vector2(start.x + cos(yaw) * span, start.z - sin(yaw) * span)
		for sample: int in 5:
			var point := Vector2(start.x, start.z).lerp(finish, float(sample) / 4.0)
			var inside := false
			for street: int in _plan.graph_street_count():
				var axis := _plan.street_axis(street)
				if axis.size() < 2:
					continue
				if TownPlan.polyline_distance(axis, point) < _plan.street_width_of(street) * 0.5:
					inside = true
					break
			if inside:
				crossing += 1
				break
	expect(crossing == 0, "%d tramos de cerco cruzan una calzada" % crossing)
	print("  cercos: %d polilíneas · %d tramos (%.0f m de alambre, %.0f m de tabla)"
			% [declared.size(), _plan.fence_points.size(),
			_plan.fence_length_of(0), _plan.fence_length_of(1)]
			+ " · 0 sobre la calzada")


## Los props: cada uno declarado aparece donde el diseño lo puso.
func _check_props() -> void:
	var declared := 0
	for source: Array in [_design.props(), _design.plaza_props()]:
		for entry: Variant in source:
			var data: Dictionary = entry
			var piece := StringName(String(data.get("piece", "")))
			var flat: Variant = TownDesign.to_vector2(data.get("pos", null))
			if flat == null or TownDesign.piece_class(piece) == &"":
				continue
			declared += 1
			var wanted: Vector2 = flat
			var found := false
			for prop: Dictionary in _plan.prop_placements:
				if StringName(prop.get("piece", &"")) != piece:
					continue
				var at: Vector3 = prop.get("pos", Vector3.ZERO)
				if Vector2(at.x, at.z).distance_to(wanted) <= DESIGN_TOLERANCE:
					found = true
					break
			expect(found, "el prop '%s' de (%.1f, %.1f) no aparece en el plano"
					% [piece, wanted.x, wanted.y])
	# Los props que cuelgan de una casa: uno por casa con jardín y árbol.
	var garden_trees := 0
	for index: int in _plan.parcels.size():
		var parcel := _plan.parcels[index]
		if int(parcel.get("role", -1)) != TownPlan.Role.HOUSE:
			continue
		if StringName(parcel.get("tree", &"")) != &"" and bool(parcel.get("garden", false)):
			garden_trees += 1
	expect(_plan.prop_placements.size() == declared + garden_trees,
			"el plano trae %d props y el diseño declara %d más %d árboles de patio"
			% [_plan.prop_placements.size(), declared, garden_trees])
	print("  props: %d declarados + %d árboles de patio = %d · %d piezas distintas"
			% [declared, garden_trees, _plan.prop_placements.size(),
			_plan.prop_pieces_used().size()])


## Gramática «toldo naranja = pila» (`docs/17` §4), del lado del plano.
##
## Las dos mitades hacen falta: sin la segunda, se podría cumplir la regla
## poniendo toldos en todo el pueblo, y el toldo dejaría de significar nada.
func _check_awnings() -> void:
	var posts := _plan.battery_posts()
	var declared := 0
	for entry: Variant in _design.markers():
		if StringName(String((entry as Dictionary).get("kind", ""))) == &"battery":
			declared += 1
	var under := 0
	for index: int in mini(POSTS_STREET, posts.size()):
		if _awning_distance(posts[index]) <= TownDesign.AWNING_REACH:
			under += 1
	expect(under >= declared,
			"hay %d pilas declaradas bajo toldo y sólo %d puestos lo cumplen"
			% [declared, under])
	var orphans := 0
	for prop: Dictionary in _plan.prop_placements:
		if StringName(prop.get("piece", &"")) != &"awning_orange":
			continue
		var at: Vector3 = prop.get("pos", Vector3.ZERO)
		var best := INF
		for post: Vector3 in posts:
			best = minf(best, Vector2(at.x - post.x, at.z - post.z).length())
		if best > TownDesign.AWNING_REACH:
			orphans += 1
			fail("hay un toldo naranja en (%.1f, %.1f) sin pila a %.0f m"
					% [at.x, at.z, TownDesign.AWNING_REACH])
	print("  toldo = pila: %d puestos de calle bajo toldo de %d declarados · %d toldos huérfanos"
			% [under, declared, orphans])


## Densidad por anillo (`docs/17` §1).
##
## Cuenta POI **declarados**, no sembrados: un POI es un edificio que no es
## casa, la plaza, el puente, una arboleda, un maizal, un puesto de pila, un
## cartel, una parada, un alambrado de campo o un caserío. Las casas no cuentan
## —son el tejido, no los puntos— y por eso una manzana llena de casas no sube
## la densidad de su anillo.
##
## Se cuenta contra el **diseño** y no contra el plano a propósito: la fila
## habla de la decisión de diseño, y tiene que decir lo mismo antes y después de
## que WP-D1 entregue las piezas del tanque y del silo. Si contara parcelas
## sembradas, el pueblo bien diseñado de hoy daría «anillo 1 flojo» sólo porque
## cuatro edificios todavía no tienen malla.
##
## Dos reglas de agrupación, las dos de `docs/17` §2: un caserío es **un** POI y
## no seis casas sueltas, y el cerco de una quinta es parte de su caserío, no un
## punto de interés aparte. Lo que sí cuenta por separado es el alambrado de
## campo, que es lo que dibuja el límite del área jugable.
##
## Lo que distingue una cosa de la otra es que la quinta es un **anillo cerrado**
## —su polilínea vuelve al primer vértice— y el alambrado de campo es una línea
## abierta. Hasta WP-D4a la regla miraba el `kind`, que era un sustituto: las
## quintas eran de tabla y el campo de alambre. En cuanto las quintas pasaron a
## alambre (hallazgo 10) —que es lo que `docs/17` §3 pide— el sustituto empezó a
## contar seis POI de más en el anillo 2. La forma no es un sustituto: un cerco
## que se cierra sobre sí mismo encierra algo, y eso que encierra ya es el POI.
func _check_ring_density() -> void:
	var tally := PackedInt32Array()
	tally.resize(RING_EDGES.size())
	var centre := Vector2(_plan.play_centre.x, _plan.play_centre.z)
	for entry: Variant in _design.poi():
		var pos: Variant = TownDesign.to_vector2((entry as Dictionary).get("pos", null))
		if pos != null:
			_tally_ring(tally, centre.distance_to(pos as Vector2))
	if _plan.has_plaza():
		_tally_ring(tally, centre.distance_to(TownPlan.polygon_centroid(_plan.plaza_polygon)))
	if _plan.has_bridge():
		_tally_ring(tally, _plan.distance_to_centre(_plan.bridge_at))
	for index: int in _design.groves().size():
		var polygon := TownDesign.to_vector2_list(
				(_design.groves()[index] as Dictionary).get("polygon", null))
		if polygon.size() >= 3:
			_tally_ring(tally, centre.distance_to(TownPlan.polygon_centroid(polygon)))
	for entry: Variant in _design.markers():
		if StringName(String((entry as Dictionary).get("kind", ""))) != &"battery":
			continue
		var pos: Variant = TownDesign.to_vector2((entry as Dictionary).get("pos", null))
		if pos != null:
			_tally_ring(tally, centre.distance_to(pos as Vector2))
	for prop: Dictionary in _plan.prop_placements:
		if not RING_POI_PIECES.has(StringName(prop.get("piece", &""))):
			continue
		_tally_ring(tally, _plan.distance_to_centre(prop.get("pos", Vector3.ZERO)))
	for entry: Variant in _design.fences():
		var fence: Dictionary = entry
		if StringName(String(fence.get("kind", ""))) != &"wire":
			continue
		var line := TownDesign.to_vector2_list(fence.get("polyline", null))
		if line.size() < 2:
			continue
		if line[0].distance_to(line[line.size() - 1]) < 0.01:
			continue
		var travelled := 0.0
		for segment: int in line.size() - 1:
			travelled += line[segment].distance_to(line[segment + 1])
		var walked := 0.0
		var middle := line[0]
		for segment: int in line.size() - 1:
			var span := line[segment].distance_to(line[segment + 1])
			if walked + span >= travelled * 0.5:
				middle = line[segment].lerp(line[segment + 1],
						(travelled * 0.5 - walked) / maxf(span, 0.0001))
				break
			walked += span
		_tally_ring(tally, centre.distance_to(middle))
	var hamlets := _design.decor_houses()
	var slot := 0
	while slot < hamlets.size():
		var pos: Variant = TownDesign.to_vector2((hamlets[slot] as Dictionary).get("pos", null))
		if pos != null:
			_tally_ring(tally, centre.distance_to(pos as Vector2))
		slot += HAMLET_GROUP
	var rows: PackedStringArray = PackedStringArray()
	for ring: int in RING_EDGES.size():
		rows.append("%d: %d" % [ring, tally[ring]])
		expect(tally[ring] >= RING_MIN[ring] and tally[ring] <= RING_MAX[ring],
				"el anillo %d tiene %d POI y la banda de docs/17 §1 es [%d, %d]"
				% [ring, tally[ring], RING_MIN[ring], RING_MAX[ring]])
	print("  densidad por anillo: %s (bandas 4–7 / 14–22 / 8–14 / 4–8)" % ", ".join(rows))


func _tally_ring(tally: PackedInt32Array, reach: float) -> void:
	for ring: int in RING_EDGES.size():
		if reach <= RING_EDGES[ring]:
			tally[ring] += 1
			return


## Determinismo posicional de las arboledas.
##
## Es la propiedad que hace editable una arboleda: agrandar su polígono agrega
## los árboles de las celdas nuevas y **no mueve** ni uno de los que ya estaban,
## ni toca a ninguna otra arboleda. Sin ella, correr un vértice volvería a
## barajar el bosque entero y el `diff` del pueblo horneado dejaría de decir qué
## cambió — exactamente el defecto que WP-T3 le sacó a las casas.
func _check_grove_determinism() -> void:
	if _design.groves().is_empty():
		return
	var data := _design.raw_data()
	var groves: Array = data["groves"]
	var grove: Dictionary = groves[0]
	var polygon: Array = grove["polygon"]
	# Se estira el primer vértice tres metros hacia afuera del baricentro: entran
	# celdas nuevas y no se toca ninguna de las viejas.
	var flat := TownDesign.to_vector2_list(grove.get("polygon", null))
	var centre := TownPlan.polygon_centroid(flat)
	var direction := (flat[0] - centre).normalized()
	# El vértice se corre sobre la recta que lo une con el baricentro.
	polygon[0] = [flat[0].x + direction.x * 3.0, flat[0].y + direction.y * 3.0]
	var grown := TownDesign.from_data(data)
	expect(grown != null, "agrandar una arboleda rompió la validación")
	if grown == null:
		return
	var after := TownPlanner.resolve(grown, _terrain)

	var moved := 0
	var added := 0
	for slot: int in _plan.grove_species.size():
		var before_points := _plan.grove_points[slot]
		var other := -1
		for index: int in after.grove_species.size():
			if after.grove_species[index] == _plan.grove_species[slot]:
				other = index
				break
		if other < 0:
			fail("agrandar una arboleda borró la especie '%s'" % _plan.grove_species[slot])
			continue
		var lookup: Dictionary[String, bool] = {}
		for point: Vector3 in after.grove_points[other]:
			lookup["%.3f|%.3f" % [point.x, point.z]] = true
		for point: Vector3 in before_points:
			if not lookup.has("%.3f|%.3f" % [point.x, point.z]):
				moved += 1
		added += after.grove_points[other].size() - before_points.size()
	expect(moved <= 1,
			"agrandar una arboleda movió %d instancias que ya estaban (tope 1: la celda tocada)"
			% moved)
	expect(added > 0, "agrandar una arboleda no agregó ni un árbol")

	# Y una arboleda **no toca a otra**: las de la segunda quedan intactas.
	if _design.groves().size() >= 2:
		var untouched := true
		for slot: int in _plan.grove_species.size():
			for index: int in _plan.grove_source[slot].size():
				if _plan.grove_source[slot][index] != 1:
					continue
				var point: Vector3 = _plan.grove_points[slot][index]
				var other := -1
				for candidate: int in after.grove_species.size():
					if after.grove_species[candidate] == _plan.grove_species[slot]:
						other = candidate
						break
				if other < 0:
					untouched = false
					break
				var found := false
				for check: Vector3 in after.grove_points[other]:
					if check.distance_to(point) < 0.001:
						found = true
						break
				if not found:
					untouched = false
					break
		expect(untouched, "agrandar la arboleda 0 movió instancias de la arboleda 1")
	print("  determinismo de arboleda: +%d instancias nuevas, %d movidas de las viejas"
			% [added, moved])

