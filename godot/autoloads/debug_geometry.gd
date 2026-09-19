## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Dibujo inmediato de líneas y esferas para depurar el IK de patas, la percepción
## del enemigo y las consultas de física (`docs/04` §3.7).
##
## Todo lo que se pide durante un frame se acumula en un buffer y se vuelca sobre un
## `ImmediateMesh` propio al final del `_process` de ese frame, justo antes de que el
## servidor de render dibuje. El buffer se vacía en cada vuelta, así que llamar a
## `draw_line()` una vez dibuja una línea durante un frame: quien la quiera fija la
## llama todos los frames.
##
## Sin `--debug` (`Global.debug` en falso) las llamadas no hacen nada y no se crea
## geometría, de modo que dejar instrumentado el código no cuesta nada en la
## compilación final.
extends Node

## Color de las líneas cuando quien llama no especifica ninguno.
const DEFAULT_COLOR: Color = Color(1.0, 0.85, 0.15)

## Segmentos de cada círculo de [method draw_sphere].
const SPHERE_SEGMENTS: int = 24

## Largo de las alas de la punta de flecha, como fracción del vector dibujado.
const ARROW_HEAD_RATIO: float = 0.18

## Cantidad máxima de `Label3D` en el pool de [method draw_text].
const MAX_LABELS: int = 64

## Alto de las letras de [method draw_text], en metros de mundo.
const LABEL_SIZE: float = 0.06

var _mesh: ImmediateMesh = null
var _instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _labels: Array[Label3D] = []
var _points: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _used_labels: int = 0


func _ready() -> void:
	# Prioridad alta: este `_process` corre después del de todos los demás nodos, así
	# que el buffer ya tiene todo lo que se pidió en este frame (incluido lo que se
	# dibujó desde `_physics_process`, que va antes).
	process_priority = 1000
	process_mode = PROCESS_MODE_ALWAYS
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color.WHITE
	_material.no_depth_test = true
	_material.disable_receive_shadows = true
	_mesh = ImmediateMesh.new()
	_instance = MeshInstance3D.new()
	_instance.name = "DebugLines"
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.visible = false
	add_child(_instance)


func _process(_delta: float) -> void:
	_flush()


## Traza un segmento entre dos puntos en coordenadas de mundo.
func draw_line(a: Vector3, b: Vector3, color: Color = DEFAULT_COLOR) -> void:
	if not is_enabled():
		return
	_points.append(a)
	_points.append(b)
	_colors.append(color)
	_colors.append(color)


## Traza un vector desde [param origin] con una punta de flecha de dos alas.
func draw_arrow(origin: Vector3, dir: Vector3, color: Color = DEFAULT_COLOR) -> void:
	if not is_enabled():
		return
	var tip := origin + dir
	draw_line(origin, tip, color)
	var length := dir.length()
	if length <= 0.0001:
		return
	var forward := dir / length
	# Cualquier perpendicular sirve; se elige el eje del mundo menos alineado para
	# que la punta no degenere cuando la flecha apunta hacia arriba.
	var reference := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := forward.cross(reference).normalized() * length * ARROW_HEAD_RATIO
	var back := tip - forward * length * ARROW_HEAD_RATIO * 2.0
	draw_line(tip, back + side, color)
	draw_line(tip, back - side, color)


## Dibuja las doce aristas de una caja alineada a los ejes del mundo. Para un cubo,
## [param size] es `Vector3.ONE * lado`.
func draw_cube(center: Vector3, size: Vector3, color: Color = DEFAULT_COLOR) -> void:
	if not is_enabled():
		return
	var half := size * 0.5
	var corners: Array[Vector3] = []
	for index: int in 8:
		corners.append(center + Vector3(
				half.x if (index & 1) != 0 else -half.x,
				half.y if (index & 2) != 0 else -half.y,
				half.z if (index & 4) != 0 else -half.z))
	for index: int in 8:
		for bit: int in [1, 2, 4]:
			if (index & bit) == 0:
				draw_line(corners[index], corners[index | bit], color)


## Dibuja una esfera como tres círculos perpendiculares.
func draw_sphere(center: Vector3, radius: float, color: Color = DEFAULT_COLOR) -> void:
	if not is_enabled():
		return
	var step := TAU / float(SPHERE_SEGMENTS)
	for segment: int in SPHERE_SEGMENTS:
		var a := step * float(segment)
		var b := step * float(segment + 1)
		var cos_a := cos(a) * radius
		var sin_a := sin(a) * radius
		var cos_b := cos(b) * radius
		var sin_b := sin(b) * radius
		draw_line(center + Vector3(cos_a, sin_a, 0.0), center + Vector3(cos_b, sin_b, 0.0), color)
		draw_line(center + Vector3(cos_a, 0.0, sin_a), center + Vector3(cos_b, 0.0, sin_b), color)
		draw_line(center + Vector3(0.0, cos_a, sin_a), center + Vector3(0.0, cos_b, sin_b), color)


## Muestra un texto en el mundo con un `Label3D` del pool, siempre de cara a la
## cámara. Como el resto, dura un frame.
func draw_text(pos: Vector3, text: String, color: Color = DEFAULT_COLOR) -> void:
	if not is_enabled():
		return
	if _used_labels >= MAX_LABELS:
		return
	var label := _label_at(_used_labels)
	_used_labels += 1
	label.text = text
	label.modulate = color
	label.global_position = pos
	label.visible = true


## Verdadero cuando el dibujo de depuración está activo: solo con `--debug`
## (`Global.debug`) y con el nodo ya dentro del árbol.
func is_enabled() -> bool:
	return Global.debug and _instance != null


## Vuelca el buffer sobre el `ImmediateMesh` y lo deja vacío para el frame siguiente.
func _flush() -> void:
	if _instance == null:
		return
	if _points.is_empty() and _used_labels == 0 and not _instance.visible:
		return
	_mesh.clear_surfaces()
	var has_lines := _points.size() >= 2
	_instance.visible = has_lines
	if has_lines:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for index: int in _points.size():
			_mesh.surface_set_color(_colors[index])
			_mesh.surface_add_vertex(_points[index])
		_mesh.surface_end()
	_points.clear()
	_colors.clear()
	for index: int in range(_used_labels, _labels.size()):
		_labels[index].visible = false
	_used_labels = 0


## Devuelve el `Label3D` [param index] del pool, creándolo la primera vez.
func _label_at(index: int) -> Label3D:
	while _labels.size() <= index:
		var label := Label3D.new()
		label.name = "DebugLabel%d" % _labels.size()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = LABEL_SIZE / 100.0
		label.visible = false
		add_child(label)
		_labels.append(label)
	return _labels[index]
