## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Caja de stick de la tarjeta de objetivos (`docs/11` §5).
##
## Un anillo marca dónde está el stick ahora y una flecha que late marca dónde lo
## quiere el objetivo. Convención de pantalla: arriba es `Vector2(0, -1)`.
class_name ObjectiveStickHint
extends Control


const TRAVEL_RATIO := 0.36
const TARGET_COLOR := Color("#7DB7FF")

var stick := Vector2.ZERO
var target := Vector2.ZERO
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(112, 112)


func set_values(current: Vector2, suggested: Vector2) -> void:
	stick = current.clampf(-1.0, 1.0)
	target = suggested.clampf(-1.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	if target != Vector2.ZERO and is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.3)
	box.set_corner_radius_all(8)
	draw_style_box(box, rect)
	var center := size / 2.0
	var travel := minf(size.x, size.y) * TRAVEL_RATIO
	var dim := Color(HUDDraw.WHITE, 0.45)
	HUDDraw.dashed_polyline(self, PackedVector2Array([Vector2(10, center.y), Vector2(size.x - 10, center.y)]),
			4.0, 5.0, 1.2, dim)
	HUDDraw.dashed_polyline(self, PackedVector2Array([Vector2(center.x, 10), Vector2(center.x, size.y - 10)]),
			4.0, 5.0, 1.2, dim)

	if target != Vector2.ZERO:
		var pulse := fmod(_time, 1.1) / 1.1
		var tip := center + target * travel
		var head := center + target * travel * (0.25 + 0.75 * pulse)
		draw_line(center, tip, Color(TARGET_COLOR, 0.35), 6.0, true)
		draw_circle(head, 9.0, Color(TARGET_COLOR, 0.35 + 0.5 * (1.0 - pulse)), true, -1.0, true)
		var direction := target.normalized()
		var side := Vector2(-direction.y, direction.x) * 9.0
		var arrow := PackedVector2Array([tip + direction * 10.0, tip - direction * 4.0 + side,
				tip - direction * 4.0 - side])
		draw_colored_polygon(arrow, TARGET_COLOR)

	var p := center + stick * travel
	HUDDraw.circle(self, p, 8.0, 2.5)
	draw_circle(p, 3.0, HUDDraw.WHITE, true, -1.0, true)
