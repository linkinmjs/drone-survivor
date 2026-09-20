## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Vista aérea del distrito `district_a` a escala real. **No es un check**: no
## afirma nada ni devuelve códigos de salida; existe para mirar la ciudad y
## comprobar que se lee desde el aire —torres de 33 a 44 m contra bloques de
## 12,5 m, calles y veredas, rocas en el borde— y que las tres etapas de
## destrucción se distinguen a simple vista.
##
## Guion, con acumuladores y nunca un [Timer] (convención de `docs/00` §6):
##
## - `t = 0.6 s` — cuatro edificios bajan a `DAMAGED`: aparecen los boquetes del
##   `damage_overlay.gdshader` y se apagan sus ventanas.
## - `t = 2.0 s` — tres edificios se derrumban: polvo, escombros del
##   [DebrisPool] y, al cabo de 1,8 s, montículo de ruina con columna de humo.
##
## La cámara orbita a 12°/s alrededor del centro financiero, alta y lejos, para
## que entren los 480 × 288 m del distrito.
##
## Captura con Movie Maker, desde la raíz del repositorio:
## [codeblock]
## godot --path godot --windowed --resolution 960x540 \
##     --write-movie <dir>/c.png --fixed-fps 10 --quit-after 60 \
##     res://tools/city_showcase.tscn
## [/codeblock]
extends Node3D

## Ruta del distrito que se muestra.
const DISTRICT_PATH: String = "res://city/districts/district_a.tscn"

## Segundos hasta que cuatro edificios entran en `DAMAGED`.
const DAMAGE_DELAY: float = 0.6

## Segundos hasta que tres edificios se derrumban.
const COLLAPSE_DELAY: float = 2.0

## Edificios que se dañan y que se derrumban.
const DAMAGE_COUNT: int = 4
const COLLAPSE_COUNT: int = 3

## Órbita de la cámara. Empieza lejos y alta, para que entren los 480 × 288 m
## del distrito, y se acerca hasta [constant ORBIT_RADIUS_END] mientras gira: la
## niebla volumétrica del  compartido lava el detalle
## más allá de los 200 m, así que el final de la toma es el que muestra los
## boquetes, los escombros y el humo.
const ORBIT_RADIUS_START: float = 360.0
const ORBIT_RADIUS_END: float = 158.0
const ORBIT_HEIGHT_START: float = 150.0
const ORBIT_HEIGHT_END: float = 62.0
const ORBIT_TARGET: Vector3 = Vector3(12.0, 16.0, -68.0)
const ORBIT_SPEED_DEG: float = 11.0
const ORBIT_START_DEG: float = 214.0

## Segundos que dura el acercamiento; coincide con la captura de 60 fotogramas a
## 10 fps del encabezado.
const ORBIT_SECONDS: float = 6.0

## Punto del distrito donde se concentra la destrucción. Está en el primer plano
## del final de la órbita, a unos 60 m de la cámara: es la única distancia a la
## que la niebla volumétrica deja ver los boquetes, los cascotes y el humo.
const FOCUS: Vector3 = Vector3(26.0, 0.0, -94.0)

## Campo de visión vertical.
const CAMERA_FOV: float = 58.0

var _elapsed: float = 0.0
var _damaged: bool = false
var _collapsed: bool = false
var _district: CityGrid = null
var _camera: Camera3D = null


func _ready() -> void:
	_camera = get_node_or_null(^"Camera3D") as Camera3D
	if _camera != null:
		_camera.fov = CAMERA_FOV
		_camera.far = 2000.0

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
	_place_camera(0.0)


func _process(delta: float) -> void:
	_elapsed += delta
	_place_camera(_elapsed)

	if not _damaged and _elapsed >= DAMAGE_DELAY:
		_damaged = true
		_hurt(_pick(DAMAGE_COUNT, 0), 0.55)
		print("city_showcase: %d edificios en DAMAGED a los %.1f s" % [DAMAGE_COUNT, _elapsed])
	if not _collapsed and _elapsed >= COLLAPSE_DELAY:
		_collapsed = true
		_hurt(_pick(COLLAPSE_COUNT, DAMAGE_COUNT), 1.0)
		print("city_showcase: %d edificios derrumbados a los %.1f s" % [COLLAPSE_COUNT, _elapsed])


## Coloca la cámara en la órbita para el instante [param time].
func _place_camera(time: float) -> void:
	if _camera == null:
		return
	var angle := deg_to_rad(ORBIT_START_DEG + ORBIT_SPEED_DEG * time)
	var t := clampf(time / ORBIT_SECONDS, 0.0, 1.0)
	var radius := lerpf(ORBIT_RADIUS_START, ORBIT_RADIUS_END, t)
	var height := lerpf(ORBIT_HEIGHT_START, ORBIT_HEIGHT_END, t)
	var eye := Vector3(cos(angle) * radius, height, sin(angle) * radius)
	_camera.look_at_from_position(eye, ORBIT_TARGET, Vector3.UP)


## Aplica [param fraction] del HP nominal a cada edificio de [param targets].
func _hurt(targets: Array[Building], fraction: float) -> void:
	for building: Building in targets:
		var _applied := building.take_damage(building.get_max_hp() * fraction,
				building.global_position)


## Elige [param count] edificios cercanos a [constant FOCUS], saltándose los
## [param skip] primeros para que las dos tandas no se pisen.
func _pick(count: int, skip: int) -> Array[Building]:
	if _district == null:
		return []
	var sorted := _district.get_buildings()
	sorted.sort_custom(func(a: Building, b: Building) -> bool:
		return a.global_position.distance_squared_to(FOCUS) 				< b.global_position.distance_squared_to(FOCUS))
	var chosen: Array[Building] = []
	for index: int in sorted.size():
		if index < skip:
			continue
		if chosen.size() >= count:
			break
		if sorted[index].stage == Building.Stage.INTACT:
			chosen.append(sorted[index])
	return chosen
