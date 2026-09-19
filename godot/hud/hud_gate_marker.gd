## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDGateMarker
extends Control
## Race mode: marks the next checkpoint. A diamond with the distance when it is in view,
## an arrow on the edge of the screen pointing toward it otherwise.


const EDGE_MARGIN := 0.8

var camera: FPVCamera = null
var target := Vector3.INF
var show_marker := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if not show_marker or not target.is_finite() or not is_instance_valid(camera):
		return
	var to_target := target - camera.global_position
	var distance := to_target.length()
	if distance < 0.5:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var center := inverse * (viewport_size / 2.0)
	var projected := camera.project_direction(to_target)
	var local := camera.global_transform.basis.inverse() * to_target.normalized()
	var in_front := local.z < 0.0
	var screen_rect := Rect2(Vector2.ZERO, viewport_size).grow(-40.0)
	if in_front and projected.is_finite() and screen_rect.has_point(projected):
		var p := inverse * projected
		var diamond := PackedVector2Array([p + Vector2(0, -14), p + Vector2(14, 0),
				p + Vector2(0, 14), p + Vector2(-14, 0), p + Vector2(0, -14)])
		draw_polyline(diamond, HUDDraw.SHADOW, 6.0, true)
		draw_polyline(diamond, UIPalette.ACCENT.lightened(0.35), 3.0, true)
		HUDDraw.text(self, HUDDraw.font_mono(), p + Vector2(-60, 40), "%d m" % [roundi(distance)],
				20, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
		return
	# Off screen: arrow on an ellipse around the center
	var direction := Vector2(local.x, -local.y)
	if direction.length_squared() < 1e-6:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var radii := viewport_size / 2.0 * EDGE_MARGIN
	var edge := center + Vector2(direction.x * radii.x, direction.y * radii.y)
	var tip := edge + direction * 18.0
	var side := Vector2(-direction.y, direction.x) * 12.0
	var arrow := PackedVector2Array([tip, edge - direction * 6.0 + side, edge - direction * 6.0 - side])
	draw_colored_polygon(arrow, UIPalette.ACCENT.lightened(0.35))
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), HUDDraw.SHADOW, 2.0, true)
	HUDDraw.text(self, HUDDraw.font_mono(), edge - direction * 34.0 + Vector2(-60, 7),
			"%d m" % [roundi(distance)], 18, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
