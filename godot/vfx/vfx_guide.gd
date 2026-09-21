## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Línea guía y parábola de telegrafía (`docs/13` §4, `docs/07` §5.6 y §5.9).
##
## Dos formas del mismo nodo, porque las dos son «una polilínea de la cabeza a un
## punto» y separarlas duplicaría el [ImmediateMesh] y su material:
##
## - [constant Mode.LINE] — la línea fina **blanca-cian** del `head_laser`. Es
##   delgada a propósito: avisa de a dónde apunta el visor sin tapar la ciudad
##   que hay detrás.
## - [constant Mode.PARABOLA] — el arco **punteado** del `pounce`. Punteado y no
##   continuo porque a 40 m de vuelo una línea llena se lee como una pared; los
##   huecos dejan ver el punto de caída, que es el dato que importa.
##
## No tiene ni una partícula: es señal, no adorno, y el presupuesto de emisores
## no puede descartarla.
class_name VFXGuide extends VFXEffect

## Forma de la guía.
enum Mode {
	LINE,     ## Segmento recto cabeza → objetivo.
	PARABOLA, ## Arco balístico punteado hasta el punto de caída.
}

## Segmentos con los que se dibuja la parábola (`Telegraph.PARABOLA_SEGMENTS`).
const SEGMENTS: int = 18

## Altura del arco como fracción del alcance (la misma que usa el rig al saltar).
const ARC_HEIGHT: float = 0.28

## Grosor de la línea en metros. Un [ImmediateMesh] de `PRIMITIVE_LINE_STRIP` no
## tiene grosor, así que la guía se dibuja como un par de triángulos por tramo
## encarados a la cámara.
const DEFAULT_WIDTH: float = 0.25

## Forma que dibuja esta instancia.
@export var mode: Mode = Mode.LINE

@onready var _line: MeshInstance3D = get_node_or_null(^"Line") as MeshInstance3D

var _mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _width: float = DEFAULT_WIDTH
var _progress: float = 0.0


func _ready() -> void:
	super()
	if _line == null:
		return
	_mesh = ImmediateMesh.new()
	_line.mesh = _mesh
	var source := _line.material_override as StandardMaterial3D
	if source != null:
		_material = source.duplicate() as StandardMaterial3D
		_line.material_override = _material


## Extremos de la guía, en coordenadas de mundo.
func set_endpoints(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	_redraw()


## Grosor de la guía, en metros (`TelegraphProfile.guide_width`).
func set_width(width: float) -> void:
	_width = maxf(width, 0.02)
	_redraw()


## Progreso del windup, de 0 a 1. Sube la opacidad: la guía nace tenue y termina
## sólida justo cuando el ataque sale.
func set_progress(t: float) -> void:
	_progress = clampf(t, 0.0, 1.0)
	if _material != null:
		_material.albedo_color.a = 0.45 + 0.45 * _progress


func _on_play() -> void:
	_progress = 0.0
	set_progress(0.0)


func _on_stop() -> void:
	if _mesh != null:
		_mesh.clear_surfaces()


# --------------------------------------------------------------------------
# Dibujo
# --------------------------------------------------------------------------

## Rehace la polilínea. Se llama en cada tick del aviso: el objetivo se mueve.
func _redraw() -> void:
	if _mesh == null or _line == null:
		return
	_mesh.clear_surfaces()
	var points := _points()
	if points.size() < 2:
		return
	# Los vértices se arman **antes** de abrir la superficie: un `surface_end()`
	# sin un solo vértice es un error del motor, y eso pasa cada vez que la guía
	# se configura antes de recibir sus extremos (los dos puntos en el origen).
	var vertices := PackedVector3Array()
	var dotted := mode == Mode.PARABOLA
	for index: int in points.size() - 1:
		# Punteado: un tramo sí y otro no. Con 18 segmentos quedan 9 rayas.
		if dotted and index % 2 == 1:
			continue
		_append_quad(vertices, points[index], points[index + 1])
	if vertices.is_empty():
		return
	# `global_transform` en identidad: los vértices ya están en mundo. Es lo mismo
	# que hace el aviso de malla de WP-19 y evita arrastrar la pose del coloso.
	_line.global_transform = Transform3D.IDENTITY
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for vertex: Vector3 in vertices:
		_mesh.surface_add_vertex(vertex)
	_mesh.surface_end()


## Vértices de la guía, en mundo.
func _points() -> PackedVector3Array:
	var points := PackedVector3Array()
	if mode == Mode.LINE:
		points.append(_from)
		points.append(_to)
		return points
	var span := _from.distance_to(_to)
	for index: int in SEGMENTS + 1:
		var ratio := float(index) / float(SEGMENTS)
		var point := _from.lerp(_to, ratio)
		point.y += sin(PI * ratio) * span * ARC_HEIGHT
		points.append(point)
	return points


## Tramo de la polilínea como una cinta de dos triángulos, ancha [member _width]
## y encarada a la cámara del que mira. Sin cámara —checks headless— la cinta se
## levanta sobre el eje vertical, que es suficiente para que la malla exista.
func _append_quad(into: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var axis := b - a
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	var eye := _eye()
	var view := (a - eye)
	var side := axis.cross(view)
	if side.length_squared() < 0.000001:
		side = axis.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized() * (_width * 0.5)
	var v0 := a - side
	var v1 := a + side
	var v2 := b + side
	var v3 := b - side
	for vertex: Vector3 in [v0, v1, v2, v0, v2, v3]:
		var _added := into.append(vertex)


## Posición del ojo, para encarar la cinta. Sin cámara devuelve un punto alto.
func _eye() -> Vector3:
	var viewport := get_viewport()
	if viewport == null:
		return _from + Vector3.UP * 100.0
	var camera := viewport.get_camera_3d()
	if camera == null:
		return _from + Vector3.UP * 100.0
	return camera.global_position
