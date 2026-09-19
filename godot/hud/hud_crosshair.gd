## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDCrosshair
extends Control
## Small ring with four ticks marking where the FPV camera points.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(48, 48)


func _draw() -> void:
	var c := size / 2.0
	HUDDraw.circle(self, c, 10.0, 2.5)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		HUDDraw.line(self, c + direction * 10.0, c + direction * 18.0, 2.5)
	draw_circle(c, 2.0, HUDDraw.WHITE, true, -1.0, true)
