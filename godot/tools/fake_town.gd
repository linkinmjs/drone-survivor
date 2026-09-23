## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Doble mínimo del plano del pueblo, para los bancos (`docs/15` §2).
##
## El contrato de `TownPlan` está congelado pero el `city/town_plan.gd` que lo
## implementa —y el pueblo horneado— los entrega otro encargo. Esto nació para poder
## verificar lo que se dibuja y se calcula sobre el plano —el mapa de la alerta, los
## `ReflectionProbe`— sin esperar a que el pueblo existiera.
##
## Y se queda aunque el pueblo ya exista, porque prueba otra cosa: trae **nueve
## manzanas y cuatro tramos de ruta escritos a mano**, números que **no** coinciden
## con los del pueblo real, así que un error de conteo en el dibujo no se puede
## esconder detrás de un barrio que casualmente dé lo mismo. Es además lo único que
## sigue midiendo algo si una ronda futura corre sobre un barrio sin plano.
##
## Así que acá hay un pueblo **armado a mano**: un `Resource` con los campos del
## contrato que WP-C consume y un [Node3D] que lo publica con `get_plan()`, que es
## todo lo que le hace falta a quien lo dibuja. No es una implementación de
## `TownPlan` ni pretende serlo: no tiene parcelas, ni roles, ni HP, ni semilla, y
## `class_name` es otro a propósito para no pisarle el nombre a la clase de verdad.
##
## **Es determinista**: la geometría sale de un [RandomNumberGenerator] con semilla
## fija, así que dos corridas dibujan el mismo pueblo y una captura se puede comparar
## con la anterior.
##
## `combat_hud_check` mide la fila 20 **dos veces**: contra el barrio de la ronda y
## contra este doble. Las dos hacen falta y dicen cosas distintas.
##
## ## El grafo de P2c
##
## Desde WP-T1 el doble trae además un **grafo de viario escrito a mano**: cuatro
## nodos sobre la ruta, cinco calles —la ruta y cuatro transversales, la última
## muerta en un cabo con tranquera— y dos manzanas con su anillo de vereda.
##
## Existe por la misma razón que el resto del archivo: [RoadMesh] y las filas de
## viario de `city_check` se pueden desarrollar y verificar contra un grafo
## conocido sin esperar a que WP-T3 entregue el resolvedor del diseño. Y está
## escrito con **ángulos que no son rectos** a propósito (72°, 105°, 68° y 95°
## respecto de la ruta): un cruce recto no distingue una cinta bien recortada de
## un parche cuadrado alineado al mundo, que es justo el defecto de P2b.
class_name FakeTown
extends RefCounted

## Radio del círculo de juego, en metros. Es el del contrato.
const PLAY_RADIUS: float = 140.0

## Cuánto más grande que el círculo es el campo dibujado (`get_extent()` del
## contrato: 2·r·1,35).
const EXTENT_FACTOR: float = 1.35

## Ancho de la calzada de la ruta, en metros.
const ROUTE_WIDTH: float = 10.0

## Banquina de la ruta, en metros.
const ROUTE_SHOULDER: float = 3.0

## Semilla de la geometría. Fija: el pueblo de prueba es siempre el mismo.
const SEED: int = 20260921

## Cuántas manzanas trae el pueblo de prueba.
##
## **Nueve, y no las doce del pueblo real, a propósito.** Un doble cuyos números
## coinciden con los del barrio de verdad no distingue «el mapa dibujó el plano que
## le dieron» de «el mapa dibujó el otro plano»: las dos mitades de la fila 20 de
## `combat_hud_check` darían lo mismo y una de las dos sobraría sin que nadie se
## enterara. Con nueve manzanas y cuatro tramos de ruta —contra doce y tres— las
## dos mitades miden cosas que no se pueden confundir.
const BLOCK_COUNT: int = 9

## Fondo de las dos manzanas atadas al grafo, en metros.
const BLOCK_DEPTH: float = 46.0

## Pose de aparición del dron, 42 m sobre el sureste del pueblo.
const DRONE_SPAWN: Transform3D = Transform3D(Basis.IDENTITY, Vector3(118.0, 42.0, 126.0))


## Plano del pueblo de prueba, recién armado.
static func plan() -> Plan:
	return Plan.new()


## Distrito de prueba: un [Node3D] que publica [method plan] con `get_plan()`, que es
## la única cosa que el mapa de la alerta y el rig de probes le piden a un barrio.
##
## Con [param town_plan] nulo se arma uno nuevo.
static func district(town_plan: Plan = null) -> District:
	var node := District.new()
	node.name = "FakeTown"
	node.plan = town_plan if town_plan != null else plan()
	return node


## El plano: los campos del contrato que WP-C consume, y nada más.
class Plan extends Resource:

	## Centro del círculo de juego, en el espacio local del distrito.
	var play_centre: Vector3 = Vector3.ZERO

	## Radio del círculo de juego, en metros.
	var play_radius: float = PLAY_RADIUS

	## Polilínea de la ruta: cinco puntos y **cuatro** tramos.
	##
	## El contrato pide dos quiebres —tres tramos— y el pueblo real los tiene. Este
	## doble lleva tres quiebres justamente para no coincidir, por la misma razón que
	## [constant BLOCK_COUNT]: lo que la fila 20 verifica es que el mapa dibuje
	## **`route.size() - 1`** tramos del plano que le ataron, sea el que sea, y eso
	## sólo se comprueba con un plano que no dé el mismo número que el otro.
	var route: PackedVector3Array = PackedVector3Array([
		Vector3(-184.0, 0.0, -108.0),
		Vector3(-86.0, 0.0, -62.0),
		Vector3(-6.0, 0.0, -18.0),
		Vector3(76.0, 0.0, 44.0),
		Vector3(168.0, 0.0, 104.0),
	])

	## Ancho de la calzada, en metros.
	var route_width: float = ROUTE_WIDTH

	## Banquina, en metros.
	var route_shoulder: float = ROUTE_SHOULDER

	## Calles del pueblo, como polilíneas.
	var streets: Array[PackedVector3Array] = []

	## Anchos de cada calle, en metros.
	var street_widths: PackedFloat32Array = PackedFloat32Array()

	## Manzanas, como polígonos convexos en XZ.
	var blocks: Array[PackedVector2Array] = []

	## Calle de cada lado de cada manzana, en el orden de sus vértices. Vacío en
	## las siete manzanas que el doble no ata al grafo.
	var block_streets: Array[PackedInt32Array] = []

	## Vereda de cada calle, en metros.
	var street_sidewalks: PackedFloat32Array = PackedFloat32Array()

	# --- Grafo de viario (contrato congelado de P2c) -------------------------

	## Los cuatro nodos escritos a mano, con las claves del contrato.
	var nodes: Array[Dictionary] = []

	## Nodos de cada calle, en pares `(a, b)`; `-1` es cabo declarado.
	var street_nodes: PackedInt32Array = PackedInt32Array()

	## Metros de cabo de cada punta de calle.
	var street_stubs: PackedFloat32Array = PackedFloat32Array()

	## Clase de cada calle: `0` ruta, `1` calle, `2` secundaria, `3` acceso.
	var street_kind: PackedInt32Array = PackedInt32Array()

	## Cierre de cada punta, con el formato `"a:kind;b:kind"`.
	var street_closures: PackedStringArray = PackedStringArray()

	## Cota civil de cada manzana. El doble corre sobre el mundo plano.
	var block_datum: PackedFloat32Array = PackedFloat32Array()

	## Anillo de vereda de cada manzana.
	var block_rings: Array[PackedVector2Array] = []

	## Huella del diseño. El doble no sale de ningún JSON: queda en cero.
	var design_hash: int = 0

	## Manzanas a oscuras, `int → bool`.
	var _dark: Dictionary[int, bool] = {}

	## Largo acumulado de la ruta hasta cada vértice. Se calcula una vez.
	var _route_marks: PackedFloat32Array = PackedFloat32Array()

	func _init() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED
		_build_route_marks()
		_build_blocks(rng)
		_build_streets(rng)
		_build_graph()

	# --- Campo -------------------------------------------------------------------

	## Cuánto mide el campo dibujado, en metros: el círculo de juego con aire
	## alrededor.
	func get_extent() -> Vector2:
		var side := play_radius * 2.0 * EXTENT_FACTOR
		return Vector2(side, side)

	## El círculo de juego pelado, sin el aire de [method get_extent].
	func get_core_extent() -> Vector2:
		var side := play_radius * 2.0
		return Vector2(side, side)

	## `true` si [param point] cae dentro del círculo de juego.
	func is_inside(point: Vector3) -> bool:
		var flat := Vector2(point.x - play_centre.x, point.z - play_centre.z)
		return flat.length() <= play_radius

	# --- Ruta --------------------------------------------------------------------

	## Largo total de la ruta, en metros.
	func route_length() -> float:
		return _route_marks[_route_marks.size() - 1] if _route_marks.size() > 0 else 0.0

	## Punto de la ruta a [param distance] metros de su origen.
	func route_point(distance: float) -> Vector3:
		var wanted := clampf(distance, 0.0, route_length())
		for index: int in range(1, route.size()):
			if wanted > _route_marks[index]:
				continue
			var span := _route_marks[index] - _route_marks[index - 1]
			var t := 0.0 if span <= 0.0 else (wanted - _route_marks[index - 1]) / span
			return route[index - 1].lerp(route[index], t)
		return route[route.size() - 1]

	## Tangente unitaria de la ruta a [param distance] metros de su origen.
	func route_tangent(distance: float) -> Vector3:
		var wanted := clampf(distance, 0.0, route_length())
		for index: int in range(1, route.size()):
			if wanted > _route_marks[index] and index < route.size() - 1:
				continue
			var step := route[index] - route[index - 1]
			return Vector3.FORWARD if step.length() < 0.001 else step.normalized()
		return Vector3.FORWARD

	## Distancia sobre la ruta del punto más cercano a [param point].
	func route_closest(point: Vector3) -> float:
		var best := 0.0
		var best_distance := INF
		for index: int in range(1, route.size()):
			var from := route[index - 1]
			var step := route[index] - from
			var span := step.length()
			if span < 0.001:
				continue
			var t := clampf((point - from).dot(step) / (span * span), 0.0, 1.0)
			var on_route := from + step * t
			var distance := on_route.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = _route_marks[index - 1] + span * t
		return best

	# --- Manzanas ----------------------------------------------------------------

	## Cuántas manzanas trae el pueblo.
	func block_count() -> int:
		return blocks.size()

	## Polígono convexo de la manzana [param index], en XZ.
	func block_polygon(index: int) -> PackedVector2Array:
		if index < 0 or index >= blocks.size():
			return PackedVector2Array()
		return blocks[index]

	## Baricentro de la manzana [param index].
	func block_centroid(index: int) -> Vector2:
		var polygon := block_polygon(index)
		if polygon.is_empty():
			return Vector2.ZERO
		var total := Vector2.ZERO
		for corner: Vector2 in polygon:
			total += corner
		return total / float(polygon.size())

	## Manzanas a oscuras, `int → bool`.
	func dark_blocks() -> Dictionary:
		return _dark

	## `true` si la manzana [param index] está a oscuras.
	func is_block_dark(index: int) -> bool:
		return bool(_dark.get(index, false))

	# --- Puntos declarados -------------------------------------------------------

	## Pose de aparición del dron.
	func drone_spawn() -> Transform3D:
		return DRONE_SPAWN

	## Pose de la cámara fija, mirando al centro desde el sureste.
	func camera_fixed() -> Transform3D:
		var eye := play_centre + Vector3(0.0, 120.0, play_radius + 100.0)
		return Transform3D(Basis.IDENTITY, eye).looking_at(play_centre, Vector3.UP)

	## Ocho puestos de pila repartidos por el círculo de juego.
	func battery_posts() -> Array[Vector3]:
		var posts: Array[Vector3] = []
		for index: int in 8:
			var angle := TAU * float(index) / 8.0
			posts.append(play_centre
					+ Vector3(cos(angle), 0.0, sin(angle)) * (play_radius * 0.6)
					+ Vector3.UP * 5.0)
		return posts

	## Cuatro marcadores de aparición, mirando al centro desde fuera del círculo.
	func spawn_points() -> Array[Transform3D]:
		var points: Array[Transform3D] = []
		for index: int in 4:
			var angle := TAU * float(index) / 4.0
			var eye := play_centre + Vector3(cos(angle), 0.0, sin(angle)) * (play_radius + 60.0)
			points.append(Transform3D(Basis.IDENTITY, eye).looking_at(play_centre, Vector3.UP))
		return points

	# --- Grafo -------------------------------------------------------------------

	## Cuántas calles cubre el grafo: la ruta más las de [member streets].
	func graph_street_count() -> int:
		return streets.size() + 1

	## `true` si el doble trae grafo. Siempre lo trae; el método existe porque es
	## lo que el constructor y los checks preguntan antes de exigir nada.
	func has_graph() -> bool:
		return not nodes.is_empty()

	## Eje de la calle [param index] (`0` = ruta), con la convención de
	## `TownPlan.street_axis`.
	func street_axis(index: int) -> PackedVector3Array:
		if index < 0:
			return PackedVector3Array()
		if index == 0:
			return route
		var slot := index - 1
		if slot >= streets.size():
			return PackedVector3Array()
		return streets[slot]

	## Ancho de calzada de la calle [param index].
	func street_width_of(index: int) -> float:
		if index < 0:
			return 0.0
		if index == 0:
			return route_width
		var slot := index - 1
		return street_widths[slot] if slot < street_widths.size() else 0.0

	## Vereda o banquina de la calle [param index].
	func street_sidewalk_of(index: int) -> float:
		if index < 0:
			return 0.0
		if index == 0:
			return route_shoulder
		var slot := index - 1
		return street_sidewalks[slot] if slot < street_sidewalks.size() else 0.0

	## Media franja de la calle [param index]: calzada más vereda.
	func street_half_of(index: int) -> float:
		return street_width_of(index) * 0.5 + street_sidewalk_of(index)

	## Nodo de la punta [param end] de la calle [param street], o `-1`.
	func node_of(street: int, end: int) -> int:
		var slot := street * 2 + clampi(end, 0, 1)
		if street < 0 or slot >= street_nodes.size():
			return -1
		return street_nodes[slot]

	## Metros de cabo de la punta [param end] de la calle [param street].
	func street_stub_of(street: int, end: int) -> float:
		var slot := street * 2 + clampi(end, 0, 1)
		if street < 0 or slot >= street_stubs.size():
			return 0.0
		return street_stubs[slot]

	## Cierre declarado en la punta [param end] de la calle [param street].
	func street_closure_of(street: int, end: int) -> StringName:
		if street < 0 or street >= street_closures.size():
			return &"none"
		var wanted := "a:" if end == 0 else "b:"
		for chunk: String in street_closures[street].split(";", false):
			var text := chunk.strip_edges()
			if text.begins_with(wanted):
				return StringName(text.substr(wanted.length()).strip_edges())
		return &"none"

	## El nodo [param i], con `poly` y `radius` ya resueltos.
	func node_at(i: int) -> Dictionary:
		return nodes[i] if i >= 0 and i < nodes.size() else {}

	## Polígono del cruce del nodo [param i].
	func node_polygon(i: int) -> PackedVector2Array:
		var node := node_at(i)
		if node.is_empty():
			return PackedVector2Array()
		return node.get("poly", PackedVector2Array())

	## Radio de boca del nodo [param i].
	func node_radius(i: int) -> float:
		var node := node_at(i)
		return float(node.get("radius", 0.0)) if not node.is_empty() else 0.0

	## Anillo de vereda de la manzana [param i], o su polígono si no declara uno.
	func block_ring(i: int) -> PackedVector2Array:
		if i >= 0 and i < block_rings.size() and block_rings[i].size() >= 3:
			return block_rings[i]
		return block_polygon(i)

	# --- Construcción ------------------------------------------------------------

	## El grafo escrito a mano: cuatro nodos sobre la ruta, cuatro transversales y
	## un cabo con tranquera.
	##
	## **Reemplaza** las dos calles sorteadas de [method _build_streets]: aquellas
	## cruzaban el pueblo de punta a punta sin tocar la ruta en ningún nodo, que
	## es exactamente el modelo que P2c retira. Las cuatro de acá nacen en su nodo
	## sobre la ruta y mueren en un cabo cerrado, que es el modelo nuevo.
	##
	## Dos de ellas salen hacia un lado de la ruta y dos hacia el otro, para que
	## cada par encierre una manzana con frente a la ruta y a las dos calles.
	func _build_graph() -> void:
		# Las cuatro marcas caen lejos de los tres quiebres de la ruta (108, 200 y
		# 302 m): un nodo pegado a un quiebre deja la boca perpendicular a un
		# tramo y la cinta empalmando con el otro, y ahí sí se solapan dos
		# asfaltos. Es la regla que `TownPlan.graph_problems()` hace cumplir.
		var marks: PackedFloat32Array = PackedFloat32Array([130.0, 182.0, 245.0, 330.0])
		var turns: PackedFloat32Array = PackedFloat32Array([72.0, 105.0, -68.0, -95.0])
		var widths: PackedFloat32Array = PackedFloat32Array([9.0, 8.0, 10.0, 8.5])
		var reaches: PackedFloat32Array = PackedFloat32Array([74.0, 66.0, 81.0, 50.0])

		streets.clear()
		street_widths = PackedFloat32Array()
		street_sidewalks = PackedFloat32Array()
		nodes.clear()

		# La ruta es la calle 0. Sus dos puntas no son cabos: se va del pueblo por
		# los dos lados, y un camino que se va del pueblo no necesita tranquera.
		street_nodes = PackedInt32Array([-1, -1])
		street_stubs = PackedFloat32Array([0.0, 0.0])
		street_kind = PackedInt32Array([0])
		street_closures = PackedStringArray(["a:none;b:none"])

		for index: int in marks.size():
			var origin := route_point(marks[index])
			var tangent := route_tangent(marks[index])
			var angle := atan2(tangent.z, tangent.x) + deg_to_rad(turns[index])
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			streets.append(PackedVector3Array([origin,
					origin + direction * reaches[index]]))
			var _width := street_widths.append(widths[index])
			var _walk := street_sidewalks.append(3.0)
			nodes.append({
				"pos": origin,
				"streets": PackedInt32Array(),
				"angles": PackedFloat32Array(),
				"half_widths": PackedFloat32Array(),
				"poly": PackedVector2Array(),
				"radius": 0.0,
			})
			var last := index == marks.size() - 1
			street_nodes.append_array(PackedInt32Array([index, -1]))
			street_stubs.append_array(PackedFloat32Array([0.0, 20.0 if last else 4.0]))
			var _kind := street_kind.append(3 if last else 1)
			var _closure := street_closures.append("a:none;b:%s"
					% ("gate" if last else "fence"))

		_resolve_nodes()
		_build_rings()

	## Rellena `streets`, `angles`, `half_widths`, `poly` y `radius` de cada nodo.
	##
	## Es la misma regla que `TownPlan.refresh_nodes`, escrita acá para que el
	## doble no dependa de la clase de verdad. La ruta **pasa** por los cuatro
	## nodos sin terminar en ninguno, así que cada nodo le abre dos bocas, una por
	## sentido: sin eso el cruce no tendría por dónde seguir la ruta.
	func _resolve_nodes() -> void:
		for index: int in nodes.size():
			var node := nodes[index]
			var pos: Vector3 = node["pos"]
			var incident := PackedInt32Array()
			var angles := PackedFloat32Array()
			var halves := PackedFloat32Array()
			for street: int in graph_street_count():
				var axis := street_axis(street)
				if axis.size() < 2:
					continue
				for end: int in 2:
					if node_of(street, end) != index:
						continue
					var tip := axis[0] if end == 0 else axis[axis.size() - 1]
					var inward := axis[1] if end == 0 else axis[axis.size() - 2]
					var delta := Vector3(inward.x - tip.x, 0.0, inward.z - tip.z)
					if delta.length() < 0.0001:
						continue
					var _a := incident.append(street)
					var _b := angles.append(atan2(delta.z, delta.x))
					var _c := halves.append(street_half_of(street))
			var along := route_tangent(route_closest(pos))
			for sign: float in [1.0, -1.0]:
				var _d := incident.append(0)
				var _e := angles.append(atan2(along.z * sign, along.x * sign))
				var _f := halves.append(street_half_of(0))
			node["streets"] = incident
			node["angles"] = angles
			node["half_widths"] = halves
			node["radius"] = RoadMesh.node_radius(node)
			node["poly"] = RoadMesh.node_polygon(node)
			nodes[index] = node

	## Dos manzanas atadas al grafo: una entre las calles 1 y 2 y otra entre la 3
	## y la 4, las dos con frente a la ruta y el fondo sin calle.
	func _build_rings() -> void:
		block_streets.clear()
		block_rings.clear()
		block_datum = PackedFloat32Array()
		for _index: int in blocks.size():
			block_streets.append(PackedInt32Array())
			block_rings.append(PackedVector2Array())
			var _datum := block_datum.append(0.0)
		for entry: Array in [[0, 1, 2], [1, 3, 4]]:
			var block := int(entry[0])
			var first := int(entry[1])
			var second := int(entry[2])
			if block >= block_rings.size():
				continue
			var ring := _block_between(first, second)
			if ring.size() < 4:
				continue
			block_rings[block] = ring
			blocks[block] = ring
			# Lados en el orden de los vértices: ruta, calle `second`, fondo sin
			# calle, calle `first`.
			block_streets[block] = PackedInt32Array([0, second, -1, first])

	## El cuadrilátero que queda entre las líneas municipales de dos
	## transversales, con la de la ruta de frente y un fondo a [constant BLOCK_DEPTH].
	##
	## Las dos esquinas del frente salen de **cortar** la línea municipal de cada
	## transversal con la de la ruta, no de correr un largo fijo: con calles
	## oblicuas el largo fijo deja la esquina adentro o afuera de la calzada, y lo
	## que se está probando es justamente que la vereda apoye sobre el cordón.
	func _block_between(first: int, second: int) -> PackedVector2Array:
		var axis_a := street_axis(first)
		var axis_b := street_axis(second)
		if axis_a.size() < 2 or axis_b.size() < 2:
			return PackedVector2Array()
		var dir_a := (axis_a[1] - axis_a[0]).normalized()
		var dir_b := (axis_b[1] - axis_b[0]).normalized()
		var origin := axis_a[0]
		var tangent := route_tangent(route_closest(origin))
		var normal := Vector3(-tangent.z, 0.0, tangent.x)
		var side := signf(dir_a.dot(normal))
		var municipal := street_half_of(0) * side

		var offset_a := Vector3(dir_a.z, 0.0, -dir_a.x) * street_half_of(first)
		var offset_b := Vector3(dir_b.z, 0.0, -dir_b.x) * street_half_of(second)
		if (axis_b[0] - axis_a[0]).dot(offset_a) < 0.0:
			offset_a = -offset_a
		if (axis_a[0] - axis_b[0]).dot(offset_b) < 0.0:
			offset_b = -offset_b

		var front_a := _cross_route(axis_a[0] + offset_a, dir_a, origin, normal, municipal)
		var front_b := _cross_route(axis_b[0] + offset_b, dir_b, origin, normal, municipal)
		var back_a := front_a + dir_a * BLOCK_DEPTH
		var back_b := front_b + dir_b * BLOCK_DEPTH
		return PackedVector2Array([
			Vector2(front_a.x, front_a.z), Vector2(front_b.x, front_b.z),
			Vector2(back_b.x, back_b.z), Vector2(back_a.x, back_a.z)])

	## Corte de la recta `base + dir · t` con la línea municipal de la ruta.
	func _cross_route(base: Vector3, dir: Vector3, origin: Vector3, normal: Vector3,
			municipal: float) -> Vector3:
		var along := dir.dot(normal)
		if absf(along) < 0.0001:
			return base
		return base + dir * ((municipal - (base - origin).dot(normal)) / along)

	## Largo acumulado hasta cada vértice de la ruta.
	func _build_route_marks() -> void:
		_route_marks = PackedFloat32Array()
		var total := 0.0
		var _appended := _route_marks.append(0.0)
		for index: int in range(1, route.size()):
			total += route[index - 1].distance_to(route[index])
			_appended = _route_marks.append(total)

	## Las manzanas, irregulares y repartidas por el círculo, cada una un polígono
	## de cuatro a seis lados.
	##
	## Los vértices salen de ángulos que **avanzan siempre** alrededor del baricentro
	## de la manzana —el ruido de ±0,22 rad es menor que el paso más chico, TAU/6 =
	## 1,05 rad, así que dos vértices no pueden cruzarse—, y eso alcanza para que el
	## polígono sea **simple**, que es lo que `draw_colored_polygon` necesita para no
	## dibujar una estrella.
	##
	## El contrato pide manzanas **convexas** y el planificador de verdad las da; acá
	## los radios varían entre 16 y 30 m, así que alguna puede salir apenas cóncava.
	## Da igual para lo que este doble tiene que probar —que el mapa dibuje un
	## polígono por manzana y los cuente bien— y de paso el dibujo aguanta un
	## polígono peor que el que va a recibir.
	func _build_blocks(rng: RandomNumberGenerator) -> void:
		blocks.clear()
		_dark.clear()
		for index: int in BLOCK_COUNT:
			var angle := TAU * float(index) / float(BLOCK_COUNT) + rng.randf_range(-0.12, 0.12)
			var reach := play_radius * rng.randf_range(0.28, 0.74)
			var centre := Vector2(cos(angle), sin(angle)) * reach
			var sides := rng.randi_range(4, 6)
			var polygon := PackedVector2Array()
			for corner: int in sides:
				var corner_angle := TAU * float(corner) / float(sides) \
						+ rng.randf_range(-0.22, 0.22)
				var radius := rng.randf_range(16.0, 30.0)
				var _appended := polygon.append(
						centre + Vector2(cos(corner_angle), sin(corner_angle)) * radius)
			blocks.append(polygon)
			# Un tercio del pueblo a oscuras, que es lo que hace que el racionamiento
			# de ventanas se vea en el mapa.
			_dark[index] = index % 3 == 0

	## Dos calles que cruzan el pueblo de punta a punta.
	func _build_streets(rng: RandomNumberGenerator) -> void:
		streets.clear()
		street_widths = PackedFloat32Array()
		for index: int in 2:
			var angle := PI * 0.5 * float(index) + rng.randf_range(-0.18, 0.18)
			var step := Vector3(cos(angle), 0.0, sin(angle))
			var street := PackedVector3Array()
			for mark: int in 5:
				var along := lerpf(-play_radius, play_radius, float(mark) / 4.0)
				var _appended := street.append(play_centre + step * along)
			streets.append(street)
			var _appended := street_widths.append(8.0)


## El barrio: lo mínimo que hace falta para que algo dibuje un plano.
class District extends Node3D:

	## Plano que publica este distrito.
	var plan: Plan = null

	## El plano del pueblo. Es el método por el que todo el mundo pregunta.
	func get_plan() -> Plan:
		return plan

	## Cuánto mide el campo, en metros. Lo delega en el plano.
	func get_extent() -> Vector2:
		return plan.get_extent() if plan != null else Vector2.ONE

	## Centro del círculo de juego, **tal cual lo trae el plano**.
	##
	## El contrato dice que `CityGrid.play_centre()` devuelve global, pero la clase
	## real devuelve `plan.play_centre` sin transformar. Este doble copia lo que la
	## clase real **hace**, no lo que el contrato promete: un doble que arreglara la
	## discrepancia por su cuenta taparía justo el bug que hay que poder ver.
	func play_centre() -> Vector3:
		return plan.play_centre if plan != null else Vector3.ZERO

	## Radio del círculo de juego, en metros.
	func play_radius() -> float:
		return plan.play_radius if plan != null else 0.0
