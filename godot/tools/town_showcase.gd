## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Vista rápida de las piezas del pueblo de ruta (WP-A). **No es un check**: no
## afirma nada, sólo arma la escena y saca las capturas con las que se juzga a
## ojo lo que ningún umbral captura — si una casa se lee como casa, si la puerta
## y las ventanas se distinguen, y si la escala contra un `block_mid` de la
## ciudad es creíble.
##
## Tres encuadres, uno por captura:
##
## | Captura | Qué muestra |
## |---|---|
## | `row` | los 5 tipos en fila (`house_a`, `house_b`, `house_c`, `house_d`, `shed`) con un `block_mid` de 20 × 12,5 m al lado, para la escala |
## | `facade` | la fachada −X de `house_a` de cerca: puerta, ventanas encendidas y grano del vóxel de 5 cm |
## | `props` | los 9 props en fila sobre la calle, a distancia de peatón |
##
## Se corre **con ventana** (en `--headless` no hay rasterizado y `shot()` no
## escribe nada), desde la raíz del repositorio:
##
## [codeblock]
## godot --path godot --windowed --resolution 1600x900 \
##     res://tools/town_showcase.tscn -- --shots=<dir> --timeout=40
## [/codeblock]
extends CheckRunner

## Sidecar del pueblo: de ahí salen los nombres y las medidas de cada pieza.
const INVENTORY_PATH: String = "res://assets/town/nuke_town.pieces.json"

## Los cinco tipos, en el orden en que se alinean de izquierda a derecha.
const HOUSE_TYPES: PackedStringArray = ["house_a", "house_b", "house_c", "house_d", "shed"]

## Los nueve props, en el mismo orden que la tabla del informe.
const PROP_TYPES: PackedStringArray = [
	"barrel_a", "barrel_b", "trash_0", "trash_1", "trash_2",
	"trash_3", "trash_4", "overgrowth_a", "overgrowth_b",
]

## Pieza de ciudad con la que se compara la escala (`assets/city/README.md`:
## 20,00 × 12,50 × 11,00 m).
const REFERENCE_PIECE: String = "res://city/pieces/block_mid.tscn"

## Separación entre piezas en la fila de casas y en la de props, en metros.
const HOUSE_SPACING: float = 7.5
const PROP_SPACING: float = 2.4

var _camera: Camera3D = null


func _run() -> void:
	# Dos recorridos en la misma escena: sin argumentos, las piezas sueltas de
	# WP-A; con `-- --town`, los cuatro encuadres del nivel que el checkpoint
	# mira (`docs/17` §5). Comparten entorno, sol y cámara, que es justamente lo
	# que hace comparables las dos tandas de capturas.
	if user_args().has("town"):
		await _run_town()
		return
	_camera = $Camera3D as Camera3D
	var inventory := _read_inventory()

	var houses := Node3D.new()
	houses.name = "Houses"
	add_child(houses)
	var offset := -HOUSE_SPACING * (HOUSE_TYPES.size() - 1) * 0.5
	for index: int in HOUSE_TYPES.size():
		var piece := _instance("res://city/pieces/town/%s.tscn" % HOUSE_TYPES[index])
		if piece == null:
			continue
		# Las piezas se componen con la fachada —puerta y ventanas— en la cara −X.
		# Un giro de +90° sobre Y lleva el −X local al +Z del mundo, que es donde
		# está la cámara: sin él la toma muestra la medianera ciega.
		piece.rotation.y = PI * 0.5
		piece.position = Vector3(offset + index * HOUSE_SPACING, 0.0, 0.0)
		houses.add_child(piece)
		var pieces := inventory.get("pieces", {}) as Dictionary
		var entry := pieces.get(HOUSE_TYPES[index], {}) as Dictionary
		print("  %s: %s m · %d triángulos" % [HOUSE_TYPES[index],
				str(entry.get("size", [])), int(entry.get("triangles", 0))])

	var reference := _instance(REFERENCE_PIECE)
	if reference != null:
		reference.position = Vector3(offset + HOUSE_TYPES.size() * HOUSE_SPACING + 8.0,
				0.0, -4.0)
		houses.add_child(reference)

	var props := Node3D.new()
	props.name = "Props"
	props.position = Vector3(0.0, 0.0, 9.0)
	add_child(props)
	var prop_offset := -PROP_SPACING * (PROP_TYPES.size() - 1) * 0.5
	for index: int in PROP_TYPES.size():
		var piece := _instance("res://city/pieces/town/props/%s.tscn" % PROP_TYPES[index])
		if piece == null:
			continue
		piece.position = Vector3(prop_offset + index * PROP_SPACING, 0.0, 0.0)
		props.add_child(piece)

	await wait_frames(6)

	_frame(Vector3(8.0, 13.0, 52.0), Vector3(6.0, 4.0, -2.0), 44.0)
	await wait_frames(3)
	await shot("row")

	_frame(Vector3(-14.0, 2.2, 12.5), Vector3(-15.0, 1.5, 0.0), 32.0)
	await wait_frames(3)
	await shot("facade")

	_frame(Vector3(0.0, 2.2, 24.0), Vector3(0.0, 0.4, 9.0), 46.0)
	await wait_frames(3)
	await shot("props")

	await wait_frames(2)


## Coloca la cámara en [param from] mirando a [param at], con [param fov] grados.
func _frame(from: Vector3, at: Vector3, fov: float) -> void:
	if _camera == null:
		return
	_camera.fov = fov
	_camera.position = from
	_camera.look_at(at, Vector3.UP)


## Instancia una escena de pieza, o avisa y devuelve `null` si no está.
func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		fail("falta la escena '%s'" % path)
		return null
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		fail("'%s' no carga como PackedScene" % path)
		return null
	return packed.instantiate() as Node3D


## Lee el sidecar del pueblo; devuelve `{}` si no está (el showcase sigue igual).
func _read_inventory() -> Dictionary:
	if not FileAccess.file_exists(INVENTORY_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY_PATH))
	var sidecar := parsed as Dictionary
	return sidecar if sidecar != null else {}


# --------------------------------------------------------------------------
# Encuadres del nivel (P2c, WP-T4)
# --------------------------------------------------------------------------

## Ruta del pueblo horneado.
const TOWN_PATH: String = "res://city/districts/town_a.tscn"

## Altura del ojo sobre el terreno en los dos encuadres a pie de obra.
const ROUTE_EYE: float = 3.0
const STREET_EYE: float = 4.0

## Los cuatro encuadres del checkpoint (`docs/17` §5).
const BRIDGE_APPROACH: float = 120.0
const PLAZA_HEIGHT: float = 60.0
const PLAZA_PITCH_DEG: float = 60.0
const AERIAL_HEIGHT: float = 220.0
const AERIAL_SPOT: Vector2 = Vector2(-120.0, -120.0)

## Fotogramas que se dejan pasar antes de capturar.
##
## No es cábala: la primera captura de un pueblo recién cargado sale en blanco y
## negro sin sombrear porque Godot todavía está compilando los shaders del
## terreno y de las casas y dibuja con el material de relleno. Con medio segundo
## de fotogramas ya están compilados.
const WARMUP_FRAMES: int = 90
const SETTLE_FRAMES: int = 20

var _town: CityGrid = null


## Recorrido del **nivel**: carga `town_a.tscn` y saca los cuatro encuadres del
## checkpoint. Se pide con `-- --town`.
func _run_town() -> void:
	_camera = $Camera3D as Camera3D
	_apply_render_quality()
	var ground := get_node_or_null(^"Ground")
	if ground != null:
		ground.queue_free()

	if not ResourceLoader.exists(TOWN_PATH):
		fail("falta '%s'; generalo con tools/build_town.gd" % TOWN_PATH)
		return
	_town = (ResourceLoader.load(TOWN_PATH, "PackedScene") as PackedScene).instantiate() as CityGrid
	if _town == null:
		fail("la raíz de '%s' no es un CityGrid" % TOWN_PATH)
		return
	add_child(_town)
	var plan := _town.get_plan()
	if plan == null:
		fail("'%s' no trae TownPlan" % TOWN_PATH)
		return
	if _camera != null:
		_camera.far = 2000.0
	await wait_frames(WARMUP_FRAMES)

	await _shoot_route(plan)
	await _shoot_plaza(plan)
	await _shoot_street(plan)
	await _shoot_aerial(plan)


## (a) `route_120`: sobre la ruta, 120 m al oeste del puente, a tres metros del
## suelo y mirando al este. Tiene que verse el puente, el cauce, la arboleda
## —vacía hasta D2— y la primera transversal con su tranquera.
func _shoot_route(plan: TownPlan) -> void:
	var bridge := _bridge_point(plan)
	var axis := plan.street_axis(0)
	var at := TownPlan.polyline_closest(axis, bridge)
	var centre := plan.route_centre_distance()
	# «Antes del puente» es del lado de afuera: se retrocede alejándose del
	# centro del pueblo.
	var away := -1.0 if at < centre else 1.0
	var from := TownPlan.polyline_point(axis, at + BRIDGE_APPROACH * away)
	var look := TownPlan.polyline_point(axis, at + 20.0 * -away)
	_frame(_eye(from, ROUTE_EYE), _eye(look, ROUTE_EYE * 0.6), 55.0)
	print("  route_120: desde %s mirando a %s (puente en %s)"
			% [str(_camera.position.round()), str(look.round()), str(bridge.round())])
	await _shot_settled("route_120")


## (b) `plaza_60`: a sesenta metros sobre el centro, picado a 60°, mirando a la
## escuela. Entran la plaza, la avenida, los cordones y las cuatro manzanas del
## corazón.
func _shoot_plaza(plan: TownPlan) -> void:
	var centre := plan.play_centre
	var school := plan.school_parcel()
	var target := plan.parcel_position(school) if school >= 0 else centre
	var heading := Vector3(target.x - centre.x, 0.0, target.z - centre.z)
	if heading.length() < 1.0:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	# Picado de 60°: por cada metro de altura, `1 / tan(60°)` de alejamiento.
	var reach := PLAZA_HEIGHT / tan(deg_to_rad(PLAZA_PITCH_DEG))
	var from := Vector3(centre.x, 0.0, centre.z) - heading * reach
	_frame(_eye(from, PLAZA_HEIGHT), _eye(centre, 0.0), 75.0)
	print("  plaza_60: desde %s picado %.0f° hacia la escuela %s"
			% [str(_camera.position.round()), PLAZA_PITCH_DEG, str(target.round())])
	await _shot_settled("plaza_60")


## (c) `street_4`: a cuatro metros sobre una calle interior, mirando a lo largo.
## Es el encuadre que juzga el cordón, la vereda, las cintas y el apoyo de las
## casas, con el cabo y su tranquera al fondo.
func _shoot_street(plan: TownPlan) -> void:
	var street := _busiest_street(plan)
	var axis := plan.street_axis(street)
	var span := TownPlan.polyline_length(axis)
	var from := TownPlan.polyline_point(axis, span * 0.12)
	var look := TownPlan.polyline_point(axis, span * 0.95)
	_frame(_eye(from, STREET_EYE), _eye(look, STREET_EYE * 0.5), 60.0)
	print("  street_4: calle %d (%.0f m) desde %s a lo largo"
			% [street, span, str(_camera.position.round())])
	await _shot_settled("street_4")


## (d) `aerial_nw`: a 220 m sobre (−120, −120), mirando al pueblo. Se leen el
## arroyo, el relieve, las manzanas planas y la ruta subiendo las lomas.
func _shoot_aerial(plan: TownPlan) -> void:
	var from := Vector3(plan.play_centre.x + AERIAL_SPOT.x, 0.0,
			plan.play_centre.z + AERIAL_SPOT.y)
	_frame(_eye(from, AERIAL_HEIGHT), plan.play_centre, 62.0)
	print("  aerial_nw: desde %s mirando al centro" % str(_camera.position.round()))
	await _shot_settled("aerial_nw")


## Punto del puente que declara el relieve horneado, o el cruce del arroyo con
## la ruta si no lo declara.
func _bridge_point(plan: TownPlan) -> Vector3:
	var terrain := _town.terrain as TownTerrain
	if terrain != null:
		var bridge: Dictionary = terrain.params.get("bridge", {})
		var at: Array = bridge.get("at", [])
		if at.size() >= 2:
			return Vector3(float(at[0]), 0.0, float(at[1]))
	return plan.route_point(plan.route_centre_distance() - 200.0)


## La calle interior con más casas dando a ella: la que mejor cuenta lo que el
## encuadre a cuatro metros tiene que juzgar.
func _busiest_street(plan: TownPlan) -> int:
	var tally: Dictionary[int, int] = {}
	for parcel: Dictionary in plan.parcels:
		if int(parcel.get("role", -1)) != TownPlan.Role.HOUSE:
			continue
		var street := int(parcel.get("street", -1))
		if street <= 0:
			continue
		tally[street] = int(tally.get(street, 0)) + 1
	var best := 1
	var best_count := -1
	for street: int in tally:
		if int(tally[street]) > best_count:
			best_count = int(tally[street])
			best = street
	return best


## [param point] llevado a [param lift] metros **sobre el terreno**.
func _eye(point: Vector3, lift: float) -> Vector3:
	return _town.on_terrain(Vector3(point.x, lift, point.z))


## Deja asentar la escena y captura. Los shaders del terreno y de las casas se
## compilan al primer dibujo y hasta entonces todo sale con el material de
## relleno: sin esta espera la captura sale en blanco y negro.
func _shot_settled(name: String) -> void:
	await wait_frames(SETTLE_FRAMES)
	await shot(name)


## Aplica el preset de gráficos a la escena, que es lo que `LevelBase` hace por
## los niveles jugables: clon propio del `Environment` —lo comparte con
## `battle_level.tscn` y escribirlo dejaría el `.tres` mutado— y el sol dado de
## alta para que reciba la tabla de sombras de `docs/13` §3.4.
func _apply_render_quality() -> void:
	var world := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var clone := world.environment.duplicate(false) as Environment
		if clone != null:
			clone.resource_local_to_scene = true
			world.environment = clone
		Graphics.apply_environment_quality(world.environment)
	Graphics.register_sun(get_node_or_null(^"Sun") as DirectionalLight3D)
