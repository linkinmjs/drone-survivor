## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Anillo de EMP (`docs/13` §4 y §11 #12, `docs/07` §5.8).
##
## Un toro que crece de 0 a 45 m durante los 2.2 s de telegrafía, más un destello
## de 0.3 s cuando el pulso sale de verdad. **Cero emisores de partículas y pool
## dedicado**: `docs/13` §11 #12 lo exige, porque un aviso que el presupuesto
## pueda descartar deja un ataque de 45 m de radio sin señal.
##
## [b]Con [Tween] y no con acumulador[/b]: es la excepción que `docs/13` §4 fija
## a mano para este efecto y para el [Decal] del pisotón. El anillo no depende del
## tick de la telegrafía —que puede saltar si el jefe pierde el objetivo— sino de
## un reloj propio que nace con el aviso y llega a 45 m exactamente cuando el
## pulso sale. Se mata antes de recrearlo, que es la regla que obliga a tener un
## [Tween] recicalable en un pool.
##
## El radio del toro [b]no miente[/b]: se lo fija `ActionEmpPulse` desde
## `shape_radius()`, o sea desde la [SphereShape3D] real de la consulta.
class_name VFXRing extends VFXEffect

## Radio de partida del anillo, en metros. No es 0 porque un toro de radio 0 es
## una malla degenerada que el rasterizador descarta.
const MIN_RADIUS: float = 0.4

## Grosor del anillo como fracción de su radio.
const THICKNESS: float = 0.035

## Grosor mínimo del anillo, en metros: a 2 m de radio el 3.5 % no se vería.
const MIN_THICKNESS: float = 0.25

## Segundos que dura el destello del pulso.
const FLASH_SECONDS: float = 0.3

## Altura del anillo sobre el suelo, en metros.
const LIFT: float = 0.25

@onready var _ring: MeshInstance3D = get_node_or_null(^"Ring") as MeshInstance3D
@onready var _flash: MeshInstance3D = get_node_or_null(^"Flash") as MeshInstance3D

var _mesh: TorusMesh = null
var _material: StandardMaterial3D = null
var _flash_material: StandardMaterial3D = null
var _tween: Tween = null
var _radius: float = 45.0
var _flash_left: float = 0.0
var _flashed: bool = false


func _ready() -> void:
	super()
	if _ring != null:
		_mesh = (_ring.mesh as TorusMesh).duplicate() as TorusMesh
		_ring.mesh = _mesh
		_material = (_mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		_mesh.material = _material
	if _flash != null and _flash.mesh != null:
		var source := _flash.mesh.surface_get_material(0) as StandardMaterial3D
		if source != null:
			_flash_material = source.duplicate() as StandardMaterial3D
			_flash.material_override = _flash_material
		_flash.visible = false


func _process(delta: float) -> void:
	super(delta)
	if _flash_left <= 0.0:
		return
	_flash_left = maxf(0.0, _flash_left - delta)
	var ratio := _flash_left / FLASH_SECONDS
	if _flash_material != null:
		_flash_material.albedo_color.a = ratio
	if _flash != null and _flash_left <= 0.0:
		_flash.visible = false


## Centro del anillo, apoyado sobre el suelo.
func set_ground_point(point: Vector3) -> void:
	global_position = Vector3(point.x, point.y + LIFT, point.z)


## Radio final del anillo, en metros. Es el de la consulta del ataque.
func set_radius(radius: float) -> void:
	_radius = maxf(radius, MIN_RADIUS)


## Arranca el crecimiento de 0 al radio final en [param seconds] segundos.
func grow(seconds: float) -> void:
	_kill_tween()
	_apply_radius(MIN_RADIUS)
	if seconds <= 0.0:
		_apply_radius(_radius)
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_LINEAR)
	# El crecimiento es lineal a propósito: el jugador tiene que poder estimar
	# «cuánto falta» mirando el borde, y cualquier `ease` miente sobre eso.
	var _step := _tween.tween_method(_apply_radius, MIN_RADIUS, _radius, seconds)


## Destello del pulso: el anillo se queda en su radio final y sale el disco.
func flash() -> void:
	# Mismo motivo que [method VFXDecalZone.strike]: el aviso terminó y lo único
	# que queda es el destello, así que el pool tiene que poder recuperar la
	# ranura cuando se apague.
	_flashed = true
	_kill_tween()
	_apply_radius(_radius)
	_flash_left = FLASH_SECONDS
	if _flash != null:
		_flash.scale = Vector3(_radius, 1.0, _radius)
		_flash.visible = true
	if _flash_material != null:
		_flash_material.albedo_color.a = 1.0
	set_process(true)


func _on_play() -> void:
	_flashed = false
	_apply_radius(MIN_RADIUS)
	if _flash != null:
		_flash.visible = false
	_flash_left = 0.0


func _on_stop() -> void:
	_kill_tween()
	_flashed = false
	_flash_left = 0.0
	if _flash != null:
		_flash.visible = false


func is_playing() -> bool:
	if _flashed:
		return _flash_left > 0.0
	return super() or _flash_left > 0.0


func _apply_radius(radius: float) -> void:
	if _mesh == null:
		return
	var thickness := maxf(radius * THICKNESS, MIN_THICKNESS)
	_mesh.outer_radius = maxf(radius, MIN_RADIUS)
	_mesh.inner_radius = maxf(radius - thickness, MIN_RADIUS * 0.5)


func _kill_tween() -> void:
	if _tween != null:
		if _tween.is_valid():
			_tween.kill()
		_tween = null
