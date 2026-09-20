## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Línea de horizonte y escalera de cabeceo del HUD de vuelo (`docs/12` §2.1 y §2.4).
##
## Dos modos: `camera` dibuja el horizonte **real** visto por la lente FPV —con la
## inclinación de la cámara y la deformación del ojo de pez incluidas—, y `attitude`
## sigue la actitud del dron con una línea geométrica, más barata y siempre definida.
##
## ## Estilo de WP-25
##
## Peldaños **cortos** (la mitad que antes) y numerados solo cada
## [constant LABEL_EVERY_DEG] grados: entre medio hay peldaños de 5° sin número, que
## dan resolución sin llenar la pantalla de dígitos. Trazo fino de
## [constant HUDDraw.STROKE] y el mismo ámbar que el resto del instrumental.
class_name HUDHorizon
extends Control

## Píxeles por grado de cabeceo en el modo `attitude`.
const ATTITUDE_PX_PER_DEG := 12.0

## Radio libre alrededor del retículo, en píxeles.
const HOLE_RADIUS := 66.0

## Elevaciones con peldaño, en grados. Cada 5°, sin el cero (ese es el horizonte).
const LADDER_STEPS: Array[int] = [-30, -25, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30]

## Solo los múltiplos de este valor llevan número.
const LABEL_EVERY_DEG := 10

## Los peldaños más lejos de esto respecto del centro no se dibujan: taparían la
## brújula y las cajas de sticks.
const LADDER_MAX_OFFSET := 250.0

## Media apertura de un peldaño numerado, en grados de azimut (modo `camera`).
const RUNG_HALF_DEG := 3.6

## Media apertura de un peldaño sin número, en grados de azimut.
const MINOR_RUNG_HALF_DEG := 2.0

## Medio ancho de un peldaño numerado en el modo `attitude`, en píxeles.
const RUNG_HALF_PX := 46.0

## Medio ancho de un peldaño sin número en el modo `attitude`, en píxeles.
const MINOR_RUNG_HALF_PX := 24.0

var show_horizon := true
var show_ladder := false
var mode := "camera"
var camera: FPVCamera = null
## Actitud en radianes (la usan el modo `attitude` y el caso sin cámara)
var pitch := 0.0
var roll := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if not show_horizon and not show_ladder:
		return
	if mode == "camera" and is_instance_valid(camera) and camera.is_inside_tree():
		_draw_camera_horizon()
	else:
		_draw_attitude_horizon()


func _to_local(viewport_point: Vector2) -> Vector2:
	if not viewport_point.is_finite():
		return viewport_point
	return get_global_transform_with_canvas().affine_inverse() * viewport_point


func _draw_camera_horizon() -> void:
	var basis := camera.global_transform.basis
	var forward := -basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() < 0.08:
		# Mirando recto arriba o abajo: el horizonte no está delante de la cámara
		return
	flat = flat.normalized()
	var center := _to_local(get_viewport().get_visible_rect().size / 2.0)
	if show_horizon:
		var points := PackedVector2Array()
		for azimuth in range(-88, 89, 4):
			var direction := flat.rotated(Vector3.UP, deg_to_rad(azimuth))
			points.append(_to_local(camera.project_direction(direction)))
		HUDDraw.dashed_polyline(self, points, 6.0, 10.0, HUDDraw.STROKE, HUDDraw.TEXT,
				center, HOLE_RADIUS)
	if show_ladder:
		for elevation in LADDER_STEPS:
			var labelled := elevation % LABEL_EVERY_DEG == 0
			var half := RUNG_HALF_DEG if labelled else MINOR_RUNG_HALF_DEG
			var e := deg_to_rad(elevation)
			var mid := flat * cos(e) + Vector3.UP * sin(e)
			var left := flat.rotated(Vector3.UP, deg_to_rad(half)) * cos(e) + Vector3.UP * sin(e)
			var right := flat.rotated(Vector3.UP, deg_to_rad(-half)) * cos(e) + Vector3.UP * sin(e)
			var p_mid := _to_local(camera.project_direction(mid))
			var p_left := _to_local(camera.project_direction(left))
			var p_right := _to_local(camera.project_direction(right))
			if not (p_mid.is_finite() and p_left.is_finite() and p_right.is_finite()):
				continue
			if absf(p_mid.y - center.y) > LADDER_MAX_OFFSET \
					or absf(p_mid.x - center.x) > LADDER_MAX_OFFSET:
				continue
			_draw_rung(p_left, p_right, elevation, labelled)


func _draw_attitude_horizon() -> void:
	var center := size / 2.0
	var normal := Vector2(-sin(roll), cos(roll))
	var along := Vector2(cos(roll), sin(roll))
	var origin := center + rad_to_deg(pitch) * ATTITUDE_PX_PER_DEG * normal
	if show_horizon:
		var points := PackedVector2Array([origin - along * 420.0, origin + along * 420.0])
		HUDDraw.dashed_polyline(self, points, 6.0, 10.0, HUDDraw.STROKE, HUDDraw.TEXT,
				center, HOLE_RADIUS)
	if show_ladder:
		for elevation in LADDER_STEPS:
			var labelled := elevation % LABEL_EVERY_DEG == 0
			var half := RUNG_HALF_PX if labelled else MINOR_RUNG_HALF_PX
			var rung_center := origin - normal * elevation * ATTITUDE_PX_PER_DEG
			if rung_center.distance_to(center) > LADDER_MAX_OFFSET:
				continue
			_draw_rung(rung_center - along * half, rung_center + along * half, elevation, labelled)


## Un peldaño: dos trazos con un hueco al medio, dos marcas que apuntan al horizonte y,
## si [param labelled], el número de grados del lado de afuera.
func _draw_rung(a: Vector2, b: Vector2, elevation: int, labelled: bool) -> void:
	var along := (b - a).normalized()
	var normal := Vector2(-along.y, along.x)
	# Las marcas apuntan hacia el horizonte, como en una escalera de avión
	var tick := normal * (6.0 if elevation > 0 else -6.0)
	var mid := (a + b) * 0.5
	var gap := along * (14.0 if labelled else 8.0)
	var color := Color(HUDDraw.TEXT, 0.85 if labelled else 0.6)
	HUDDraw.line(self, a, mid - gap, HUDDraw.STROKE, color)
	HUDDraw.line(self, mid + gap, b, HUDDraw.STROKE, color)
	HUDDraw.line(self, a, a + tick, HUDDraw.STROKE, color)
	HUDDraw.line(self, b, b + tick, HUDDraw.STROKE, color)
	if not labelled:
		return
	HUDDraw.text(self, HUDDraw.font_mono(), b + along * 8.0 + Vector2(0, 6),
			"%d" % [absi(elevation)], 16, HORIZONTAL_ALIGNMENT_LEFT, -1.0, color)
