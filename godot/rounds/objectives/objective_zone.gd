## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Columna translúcida que marca un lugar —y una banda de altura— al que hay que
## llegar en un objetivo (`docs/11` §5).
##
## La geometría se construye en código; sólo se exportan el radio y la banda.
@tool
class_name ObjectiveZone
extends Node3D


enum State {HIDDEN, IDLE, ACTIVE, INSIDE, DONE}

const COLOR_IDLE := Color(1.0, 1.0, 1.0)
const COLOR_ACTIVE := Color("#4F9BFF")
const COLOR_DONE := Color("#3DDC97")

@export var radius := 2.0:
	set(value):
		radius = maxf(value, 0.1)
		_rebuild()
@export var bottom := 0.0:
	set(value):
		bottom = value
		_rebuild()
@export var top := 3.0:
	set(value):
		top = value
		_rebuild()

var state := State.HIDDEN

var _column: MeshInstance3D = null
var _rings: Array[MeshInstance3D] = []
var _column_material: StandardMaterial3D = null
var _ring_material: StandardMaterial3D = null
var _time := 0.0


func _ready() -> void:
	_column_material = _make_material()
	_ring_material = _make_material()
	_rebuild()
	set_state(State.IDLE if Engine.is_editor_hint() else State.HIDDEN)


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	return material


func _rebuild() -> void:
	if not is_node_ready() or _column_material == null:
		return
	if _column:
		_column.queue_free()
	for ring in _rings:
		ring.queue_free()
	_rings.clear()

	var height := maxf(top - bottom, 0.05)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	cylinder.radial_segments = 32
	cylinder.rings = 1
	cylinder.material = _column_material
	_column = MeshInstance3D.new()
	_column.mesh = cylinder
	_column.position.y = bottom + height / 2.0
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)

	# A ring at each end of the band makes the height easy to read from the FPV camera
	for y: float in [bottom, top]:
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.06
		torus.outer_radius = radius + 0.06
		torus.rings = 48
		torus.ring_segments = 6
		torus.material = _ring_material
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.position.y = maxf(y, 0.03)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_rings.append(ring)
	_apply_colors()


func set_state(new_state: State) -> void:
	state = new_state
	visible = state != State.HIDDEN
	_time = 0.0
	_apply_colors()


func contains_horizontal(point: Vector3) -> bool:
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z)
	return flat.length() <= radius


func horizontal_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _process(delta: float) -> void:
	if state == State.ACTIVE and visible:
		_time += delta
		_apply_colors()


func _apply_colors() -> void:
	if _column_material == null:
		return
	var color := COLOR_IDLE
	var column_alpha := 0.06
	var ring_alpha := 0.35
	match state:
		State.ACTIVE:
			color = COLOR_ACTIVE
			column_alpha = 0.16 + 0.08 * sin(_time * 4.0)
			ring_alpha = 0.9
		State.INSIDE:
			color = COLOR_DONE
			column_alpha = 0.22
			ring_alpha = 1.0
		State.DONE:
			color = COLOR_DONE
			column_alpha = 0.05
			ring_alpha = 0.5
	_column_material.albedo_color = Color(color, column_alpha)
	_ring_material.albedo_color = Color(color, ring_alpha)
