## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## LED de modo de vuelo del dron (`docs/03` §7).
##
## El piloto vuela mirando el video de la cámara FPV, así que el único sitio donde
## puede ver en qué modo está sin apartar la vista es… el propio dron, cuando lo
## mira desde fuera, y la cámara de seguimiento del nivel. Este nodo pinta esa
## información en la parte `led` del modelo voxel: **cian** en ACRO, **verde** en
## HORIZON, **magenta** en TURTLE y **rojo** en RECOVER; desarmado parpadea lento y
## un armado rechazado dispara tres parpadeos rápidos.
##
## **De dónde sale el material.** La malla `led` del GLB comparte el material
## `voxel_emissive` con cualquier otra parte emisiva del pipeline voxel (`docs/05`),
## y ese material es un recurso **compartido** entre todas las instancias del
## modelo: escribirlo directamente pintaría de magenta los LEDs de todos los drones
## de la escena. Por eso [method _bind] lo **duplica** y lo cuelga como
## `surface_override_material` de esta instancia. Al duplicado se le quitan las
## texturas de albedo y emisión: la del pipeline es la paleta de voxeles, y como
## `emission_operator` es `MULTIPLY`, dejarla puesta teñiría el color de modo con el
## color del voxel y el cian dejaría de ser cian.
##
## **Sin `Timer`.** Los parpadeos se llevan con acumuladores en [method _process]:
## un `Timer` por nodo para un cuadrado de 0.5 s es un nodo, una señal y una
## reconexión en cada respawn, a cambio de nada.
class_name ModeLED extends Node3D

## Color del LED por clave de modo (`docs/03` §3.2 y §7).
const MODE_COLORS: Dictionary[String, Color] = {
	"acro": Color(0.0, 0.88, 1.0),
	"horizon": Color(0.15, 1.0, 0.3),
	"turtle": Color(1.0, 0.1, 0.85),
	"recover": Color(1.0, 0.13, 0.08),
}

## Color de reserva para una clave de modo que no esté en [constant MODE_COLORS].
const FALLBACK_COLOR: Color = Color(1.0, 1.0, 1.0)

## Período del parpadeo lento de desarmado, en segundos. `docs/03` §7 pide «0.5 s»:
## se lee como medio período —0.5 s encendido y 0.5 s apagado—, que es lo que se ve
## como un latido lento y no como un destello.
const IDLE_BLINK_PERIOD: float = 1.0

## Período del parpadeo rápido de armado rechazado, en segundos.
const ALERT_BLINK_PERIOD: float = 0.16

## Parpadeos rápidos que dispara un `arm_failed` (`docs/03` §7).
const ALERT_BLINKS: int = 3

## Factor de emisión con el LED apagado. Cero: un parpadeo se tiene que ver como
## un parpadeo, y así el check lo distingue sin umbrales.
const OFF_LEVEL: float = 0.0

## Cuánto se oscurece el albedo respecto del color de modo, para que el LED se lea
## coloreado incluso en la mitad apagada del parpadeo.
const ALBEDO_DARKEN: float = 0.55

## Dron del que se leen modo y armado. Vacío, se usa el nodo padre, que es donde
## `docs/03` §8 pone este nodo.
@export var drone: Drone

## Nodo bajo el que se busca la malla del LED. Relativo a este nodo.
@export var model_path: NodePath = ^"../Model"

## Nombre —y `part_id`— de la malla emisiva del modelo voxel (`docs/05`).
@export var mesh_name: StringName = &"led"

var _drone: Drone = null
var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null

## Energía de emisión del material original, la que fija `emissive_strength` del
## sidecar del modelo. El parpadeo la modula, no la reemplaza.
var _base_energy: float = 1.0

var _mode_key: String = "acro"
var _armed: bool = false
var _blink_time: float = 0.0
var _alert_remaining: float = 0.0
var _applied_color: Color = Color(0, 0, 0, 0)
var _applied_level: float = -1.0


func _ready() -> void:
	_resolve_drone()
	_bind()
	if _drone != null:
		if not _drone.armed.is_connected(_on_armed):
			var _discard := _drone.armed.connect(_on_armed)
		if not _drone.disarmed.is_connected(_on_disarmed):
			var _discard := _drone.disarmed.connect(_on_disarmed)
		if not _drone.arm_failed.is_connected(_on_arm_failed):
			var _discard := _drone.arm_failed.connect(_on_arm_failed)
		if not _drone.flight_mode_changed.is_connected(_on_mode_changed):
			var _discard := _drone.flight_mode_changed.connect(_on_mode_changed)
	_apply(1.0)


## Las señales del dron dan la reacción inmediata; el sondeo de acá es la red de
## seguridad para los cambios que no pasan por ellas —un modo elegido a mano en un
## check, o un dron que ya estaba armado cuando este nodo entró al árbol—.
func _process(delta: float) -> void:
	if _material == null:
		return
	if _drone != null:
		_mode_key = _drone.get_mode_key()
		_armed = _drone.is_armed()
	_apply(_advance(delta))


## Material vivo del LED, ya duplicado. Lo leen `flight_check` §11.7 y `audio_check`.
func get_material() -> StandardMaterial3D:
	return _material


## Color de emisión que tiene puesto el LED ahora mismo.
func get_emission() -> Color:
	if _material == null:
		return Color(0, 0, 0, 1)
	return _material.emission


## Energía de emisión vigente. Vale cero en la mitad apagada de un parpadeo.
func get_emission_energy() -> float:
	if _material == null:
		return 0.0
	return _material.emission_energy_multiplier


## Clave del modo que el LED está mostrando.
func get_mode_key() -> String:
	return _mode_key


## `true` mientras corren los parpadeos rápidos de un armado rechazado.
func is_alerting() -> bool:
	return _alert_remaining > 0.0


## Color que le corresponde a una clave de modo.
func color_for_mode(mode_key: String) -> Color:
	return MODE_COLORS.get(mode_key, FALLBACK_COLOR)


# --- Interno ----------------------------------------------------------------------------------


func _resolve_drone() -> void:
	_drone = drone
	if _drone == null:
		_drone = get_parent() as Drone
	if _drone != null:
		_mode_key = _drone.get_mode_key()
		_armed = _drone.is_armed()


## Busca la malla del LED y le cuelga una copia propia de su material.
func _bind() -> void:
	_mesh = _find_mesh()
	if _mesh == null:
		push_warning("ModeLED: no se encontró la malla '%s' bajo '%s' (%s). El LED queda apagado."
				% [String(mesh_name), String(model_path), get_path()])
		return
	var source := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if source == null:
		source = _mesh.material_override as StandardMaterial3D
	if source == null and _mesh.mesh != null and _mesh.mesh.get_surface_count() > 0:
		source = _mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if source == null:
		push_warning("ModeLED: la malla '%s' no tiene un StandardMaterial3D que duplicar."
				% String(mesh_name))
		return
	_material = source.duplicate() as StandardMaterial3D
	_base_energy = maxf(_material.emission_energy_multiplier, 0.01)
	_material.emission_enabled = true
	# La paleta de voxeles multiplica la emisión: con ella puesta, el color de modo
	# sería el producto de dos colores y dejaría de ser reconocible.
	_material.emission_texture = null
	_material.albedo_texture = null
	_mesh.set_surface_override_material(0, _material)


## La malla del LED, por nombre o por el metadato `part_id` que escribe
## `asset_import/import_drone.gd` (`docs/05` §10).
func _find_mesh() -> MeshInstance3D:
	var root := get_node_or_null(model_path)
	if root == null:
		return null
	var direct := root.find_child(String(mesh_name), true, false) as MeshInstance3D
	if direct != null:
		return direct
	var pending: Array[Node] = [root]
	var index := 0
	while index < pending.size():
		var node := pending[index]
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.has_meta(&"part_id") \
				and StringName(mesh.get_meta(&"part_id")) == mesh_name:
			return mesh
		for child: Node in node.get_children():
			pending.append(child)
		index += 1
	return null


## Avanza los acumuladores y devuelve el nivel de emisión de este frame, `0` o `1`.
func _advance(delta: float) -> float:
	if _alert_remaining > 0.0:
		_alert_remaining = maxf(_alert_remaining - delta, 0.0)
		var level := _square(_blink_time, ALERT_BLINK_PERIOD)
		_blink_time += delta
		if _alert_remaining <= 0.0:
			_blink_time = 0.0
		return level
	if not _armed:
		var level := _square(_blink_time, IDLE_BLINK_PERIOD)
		_blink_time += delta
		return level
	_blink_time = 0.0
	return 1.0


## Onda cuadrada: encendida la primera mitad de cada período.
func _square(time: float, period: float) -> float:
	if period <= 0.0:
		return 1.0
	return 1.0 if fmod(time, period) < period * 0.5 else OFF_LEVEL


## Escribe el material solo cuando algo cambió: un parpadeo son dos escrituras por
## período, no una por frame.
func _apply(level: float) -> void:
	if _material == null:
		return
	var color := color_for_mode(_mode_key)
	if not color.is_equal_approx(_applied_color):
		_applied_color = color
		_material.emission = color
		_material.albedo_color = color.darkened(ALBEDO_DARKEN)
	if not is_equal_approx(level, _applied_level):
		_applied_level = level
		_material.emission_energy_multiplier = _base_energy * level


func _on_armed(mode_key: String) -> void:
	_mode_key = mode_key
	_armed = true
	_blink_time = 0.0
	_alert_remaining = 0.0
	_apply(1.0)


func _on_disarmed() -> void:
	_armed = false
	_blink_time = 0.0
	_apply(1.0)


func _on_arm_failed(_reason_key: String) -> void:
	_alert_remaining = float(ALERT_BLINKS) * ALERT_BLINK_PERIOD
	_blink_time = 0.0
	_apply(1.0)


func _on_mode_changed(mode_key: String) -> void:
	_mode_key = mode_key
	_apply(_applied_level if _applied_level >= 0.0 else 1.0)
