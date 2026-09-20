## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Recorrido de revisión visual del distrito `district_a`. **No es un check**: no
## afirma nada ni devuelve códigos de salida; existe para mirar la ciudad y
## comprobar a ojo lo que ningún check mide —escala de las piezas, red viaria y
## silueta— y que las tres etapas de destrucción se distinguen.
##
## Guion por **planos fijos**, con acumuladores y nunca un [Timer] (convención de
## `docs/00` §6). Cada plano dura [constant SHOT_SECONDS] y, a 10 fps de Movie
## Maker, ocupa doce fotogramas:
##
## [codeblock]
## 1  aéreo      el distrito entero: rejilla, calles de 16 m y avenidas de 32
## 2  avenida    tres cuartos a 60 m sobre la avenida norte-sur
## 3  calle      nivel de calle desde una esquina: cordón, vereda y fachadas
## 4  azotea     una azotea con prop, para medir el cartel contra el edificio
## 5  silueta    horizonte bajo: hitos de 75-80 m contra bloques de 7-17 m
## 6  daño       cuatro edificios en DAMAGED y tres derrumbándose
## [/codeblock]
##
## Hasta WP-21 era una órbita continua; los planos fijos la reemplazan porque lo
## que hay que revisar son detalles concretos (que las marcas de la calzada vayan
## a lo largo, que el cordón se vea, que el cartel no sea más grande que la
## azotea) y una órbita no garantiza que ninguno caiga en un fotograma.
##
## Captura con Movie Maker, desde la raíz del repositorio:
## [codeblock]
## godot --path godot --windowed --resolution 960x540 \
##     --write-movie <dir>/c.png --fixed-fps 10 --quit-after 95 \
##     res://tools/city_showcase.tscn
## [/codeblock]
extends Node3D

## Ruta del distrito que se muestra.
const DISTRICT_PATH: String = "res://city/districts/district_a.tscn"

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


## Los seis planos. Salen de la geometría de la rejilla —cruce de avenidas,
## esquinas y azoteas reales— y no de números a mano, así que siguen apuntando a
## donde tienen que apuntar si cambia el tamaño del distrito.
func _build_shots() -> Array[Dictionary]:
	var extent := _district.get_extent()
	var half := Vector3(extent.x * 0.5, 0.0, extent.y * 0.5)
	var avenue := _district.avenue_crossing()
	var roof := _pick_roof()
	_focus = Vector3(avenue.x, 0.0, avenue.z - 48.0)

	return [
		{
			"name": "aéreo",
			"eye": Vector3(half.x * 0.35, half.x * 1.25, half.z + 250.0),
			"target": Vector3(0.0, 0.0, 0.0),
		},
		{
			"name": "avenida",
			"eye": Vector3(avenue.x + 78.0, 60.0, half.z + 84.0),
			"target": Vector3(avenue.x, 14.0, -40.0),
		},
		{
			"name": "calle",
			"eye": Vector3(avenue.x - 6.0, 2.8, avenue.z + 92.0),
			"target": Vector3(avenue.x + 1.0, 11.0, avenue.z - 120.0),
		},
		{
			"name": "azotea",
			"eye": roof + Vector3(21.0, 13.0, 21.0),
			"target": roof + Vector3(0.0, -2.5, 0.0),
		},
		{
			"name": "silueta",
			"eye": Vector3(-half.x - 150.0, 30.0, half.z + 150.0),
			"target": Vector3(0.0, 40.0, 0.0),
		},
		{
			"name": "daño",
			"eye": _focus + Vector3(62.0, 32.0, 74.0),
			"target": _focus + Vector3(0.0, 10.0, 0.0),
		},
	]


## Techo de un edificio con prop.
##
## Se prefiere uno **bajo** y cercano al centro: sobre un hito de 80 m el cartel
## queda a tanta distancia de la cámara que no se puede juzgar su tamaño, que es
## justo lo que este plano tiene que dejar revisar.
func _pick_roof() -> Vector3:
	var best: Building = null
	var fallback: Building = null
	for building: Building in _district.get_buildings():
		if building.props == null:
			continue
		if fallback == null or building.get_height() > fallback.get_height():
			fallback = building
		if building.get_height() > 20.0:
			continue
		if best == null or building.position.length() < best.position.length():
			best = building
	if best == null:
		best = fallback
	if best == null:
		return Vector3(0.0, 20.0, 0.0)
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
