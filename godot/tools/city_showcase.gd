## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Recorrido de revisión visual del **pueblo de ruta** `town_a`. **No es un
## check**: no afirma nada ni devuelve códigos de salida; existe para mirar el
## pueblo y comprobar a ojo lo que ningún check mide —escala de las casas,
## legibilidad de la calzada contra la vereda, silueta y campo— y que las tres
## etapas de destrucción se distinguen.
##
## Guion por **planos fijos**, con acumuladores y nunca un [Timer] (convención de
## `docs/00` §6). Cada plano dura [constant SHOT_SECONDS] y, a 10 fps de Movie
## Maker, ocupa doce fotogramas:
##
## [codeblock]
## 1  aéreo     el pueblo entero desde 380 m: ruta, manzanas y campo alrededor
## 2  ruta      tres cuartos a 60 m sobre la ruta, entrando al pueblo
## 3  calle     nivel de calle en una transversal: cordón, vereda y fachadas
## 4  centro    escuela e hito desde 40 m, que son la silueta alta del pueblo
## 5  campo     horizonte bajo desde fuera del círculo: casas de 5 m y caserío
## 6  daño      cuatro casas en DAMAGED y tres derrumbándose
## [/codeblock]
##
## Los planos salen de la **geometría del plano** ([TownPlan]: centro, radio,
## ruta) y no de números a mano, así que siguen apuntando a donde tienen que
## apuntar si se regenera el pueblo con otra semilla. Hasta WP-D estaban escritos
## contra el distrito rectangular de P2 —medio kilómetro de lado, hitos de 75 m—
## y encuadraban un pueblo de 280 m de diámetro desde tan lejos que no se veía
## nada.
##
## Captura con Movie Maker, desde la raíz del repositorio:
## [codeblock]
## godot --path godot --windowed --resolution 960x540 \
##     --write-movie <dir>/c.png --fixed-fps 10 --quit-after 95 \
##     res://tools/city_showcase.tscn
## [/codeblock]
extends Node3D

## Ruta del distrito que se muestra.
const DISTRICT_PATH: String = "res://city/districts/town_a.tscn"

## Duración de cada plano fijo, en segundos.
const SHOT_SECONDS: float = 1.2

## Cuántos planos fijos hay antes de la secuencia de destrucción.
const STILL_SHOTS: int = 5

## Segundos —ya dentro del último plano— en los que se daña y se derrumba.
const DAMAGE_DELAY: float = 0.3
const COLLAPSE_DELAY: float = 1.1

## Edificios que se dañan y que se derrumban.
const DAMAGE_COUNT: int = 4
const COLLAPSE_COUNT: int = 3

## Campo de visión vertical.
const CAMERA_FOV: float = 58.0

var _elapsed: float = 0.0
var _damaged: bool = false
var _collapsed: bool = false
var _district: CityGrid = null
var _camera: Camera3D = null
var _shots: Array[Dictionary] = []
var _focus: Vector3 = Vector3.ZERO


func _ready() -> void:
	_apply_render_quality()
	_camera = get_node_or_null(^"Camera3D") as Camera3D
	if _camera != null:
		_camera.fov = CAMERA_FOV
		_camera.far = 3000.0

	var packed := ResourceLoader.load(DISTRICT_PATH, "PackedScene") as PackedScene
	if packed == null:
		push_error("city_showcase: falta '%s'." % DISTRICT_PATH)
		return
	_district = packed.instantiate() as CityGrid
	add_child(_district)

	var integrity := CityIntegrity.new()
	integrity.name = "CityIntegrity"
	integrity.grid = _district
	add_child(integrity)

	_shots = _build_shots()
	_place_camera(0.0)


## Aplica el preset de gráficos a la escena, que es lo que `LevelBase` hace por
## los niveles jugables y este showcase no heredaba (WP-24a): clon propio del
## `Environment` —lo comparte con `battle_level.tscn` y escribirlo dejaría el
## `.tres` mutado para la escena siguiente—, calidad volcada sobre el clon y sol
## dado de alta para que reciba la tabla de sombras de `docs/13` §3.4 en vez de
## los 700 m cableados en la escena.
func _apply_render_quality() -> void:
	var world := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var clone := world.environment.duplicate(false) as Environment
		if clone != null:
			clone.resource_local_to_scene = true
			world.environment = clone
		Graphics.apply_environment_quality(world.environment)
	Graphics.register_sun(get_node_or_null(^"Sun") as DirectionalLight3D)


## Centro del círculo de juego, en coordenadas **globales**.
##
## `CityGrid.play_centre()` devuelve local, así que hay que transformarlo. Hoy el
## distrito se instancia en el origen y las dos coinciden; el `to_global` está
## para el día que el nivel lo mueva, que es cuando un plano encuadrado sobre el
## punto equivocado sale mal sin que nada falle.
func _city_centre() -> Vector3:
	if _district == null or not is_instance_valid(_district):
		return Vector3.ZERO
	return _district.to_global(_district.play_centre())


## Los seis planos. Salen del plano del pueblo —centro, radio y ruta— y no de
## números a mano, así que siguen apuntando a donde tienen que apuntar si se
## regenera el pueblo con otra semilla o con otro radio.
func _build_shots() -> Array[Dictionary]:
	var centre := _city_centre()
	var radius: float = _district.play_radius()
	var plan := _district.get_plan()
	# La ruta atraviesa el pueblo casi recta: su tangente en el punto más cercano
	# al centro es el eje sobre el que se encuadran los planos 1, 2 y 3, y su
	# perpendicular el que los separa de la calzada.
	var along := Vector3.FORWARD
	var mid := centre
	if plan != null and plan.route.size() >= 2:
		var at := plan.route_centre_distance()
		along = plan.route_tangent(at)
		mid = plan.route_point(at)
	var across := TownPlan.left_of(along)
	var roof := _pick_roof()
	_focus = centre + across * (radius * 0.45)

	return [
		{
			"name": "aéreo",
			"eye": centre - along * (radius * 1.2) + Vector3(0.0, radius * 2.7, 0.0),
			"target": centre,
		},
		{
			"name": "ruta",
			"eye": mid - along * (radius * 1.15) + across * 26.0 + Vector3(0.0, 60.0, 0.0),
			"target": centre + Vector3(0.0, 8.0, 0.0),
		},
		{
			"name": "calle",
			"eye": mid - along * (radius * 0.55) + Vector3(0.0, 2.6, 0.0),
			"target": mid + along * (radius * 0.4) + Vector3(0.0, 6.0, 0.0),
		},
		{
			"name": "centro",
			"eye": roof + across * 38.0 - along * 34.0 + Vector3(0.0, 22.0, 0.0),
			"target": roof + Vector3(0.0, -4.0, 0.0),
		},
		{
			"name": "campo",
			"eye": centre - across * (radius + 210.0) + Vector3(0.0, 16.0, 0.0),
			"target": centre + Vector3(0.0, 14.0, 0.0),
		},
		{
			"name": "daño",
			"eye": _focus + across * 46.0 - along * 52.0 + Vector3(0.0, 30.0, 0.0),
			"target": _focus + Vector3(0.0, 4.0, 0.0),
		},
	]


## Techo del edificio protegido, que en el pueblo es la escuela.
##
## Se busca por nombre y se cae al edificio **más alto** —el hito— si no está: son
## los dos únicos volúmenes que sobresalen de un caserío de casas de 5 m, y el
## plano 4 existe para juzgarlos contra ellas.
func _pick_roof() -> Vector3:
	var best: Building = null
	for building: Building in _district.get_buildings():
		if building.name == String(TownPlan.SCHOOL_NODE):
			best = building
			break
		if best == null or building.get_height() > best.get_height():
			best = building
	if best == null:
		return _city_centre() + Vector3(0.0, 15.0, 0.0)
	return best.position + Vector3(0.0, best.get_height(), 0.0)


func _process(delta: float) -> void:
	_elapsed += delta
	_place_camera(_elapsed)

	var last_shot := SHOT_SECONDS * float(STILL_SHOTS)
	if not _damaged and _elapsed >= last_shot + DAMAGE_DELAY:
		_damaged = true
		_hurt(_pick(DAMAGE_COUNT, 0), 0.55)
		print("city_showcase: %d edificios en DAMAGED a los %.1f s" % [DAMAGE_COUNT, _elapsed])
	if not _collapsed and _elapsed >= last_shot + COLLAPSE_DELAY:
		_collapsed = true
		_hurt(_pick(COLLAPSE_COUNT, DAMAGE_COUNT), 1.0)
		print("city_showcase: %d edificios derrumbados a los %.1f s" % [COLLAPSE_COUNT, _elapsed])


## Coloca la cámara en el plano que corresponde al instante [param time]. El
## último plano se queda hasta el final de la captura.
func _place_camera(time: float) -> void:
	if _camera == null or _shots.is_empty():
		return
	var index := clampi(int(time / SHOT_SECONDS), 0, _shots.size() - 1)
	var shot := _shots[index]
	_camera.look_at_from_position(shot["eye"], shot["target"], Vector3.UP)


## Aplica [param fraction] del HP nominal a cada edificio de [param targets].
func _hurt(targets: Array[Building], fraction: float) -> void:
	for building: Building in targets:
		var _applied := building.take_damage(building.get_max_hp() * fraction,
				building.global_position)


## Elige [param count] edificios cercanos al foco del último plano, saltándose
## los [param skip] primeros para que las dos tandas no se pisen.
func _pick(count: int, skip: int) -> Array[Building]:
	if _district == null:
		return []
	var sorted := _district.get_buildings()
	sorted.sort_custom(func(a: Building, b: Building) -> bool:
		return a.global_position.distance_squared_to(_focus) \
				< b.global_position.distance_squared_to(_focus))
	var chosen: Array[Building] = []
	for index: int in sorted.size():
		if index < skip:
			continue
		if chosen.size() >= count:
			break
		if sorted[index].stage == Building.Stage.INTACT:
			chosen.append(sorted[index])
	return chosen
