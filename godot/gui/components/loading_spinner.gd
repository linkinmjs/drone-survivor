## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name LoadingSpinner
extends Control
## Rotating arc shown while a scene loads.


const SPEED := 5.0

var _angle := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(56, 56)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_angle = fmod(_angle + delta * SPEED, TAU)
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 4.0
	draw_arc(center, radius, 0.0, TAU, 48, UIPalette.SURFACE_PRESSED, 5.0, true)
	draw_arc(center, radius, _angle, _angle + TAU * 0.3, 24, UIPalette.ACCENT, 5.0, true)
