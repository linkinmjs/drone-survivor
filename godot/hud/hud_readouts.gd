## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDReadouts
extends Control
## Exact values away from the center, top right: altitude, speed and vertical speed.
## Small label with the unit stacked below it, big value on the right.


var altitude := 0.0
var speed_kmh := 0.0
var vertical_speed := 0.0
var show_altitude := true
var show_speed := true
var show_vertical_speed := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(260, 200)


func _draw() -> void:
	var y := 0.0
	if show_altitude:
		var value := "%.1f" % altitude if absf(altitude) < 10.0 else "%d" % [roundi(altitude)]
		_row(y, "HUD_ALT", "HUD_UNIT_M", value)
		y += 66.0
	if show_speed:
		_row(y, "HUD_SPD", "HUD_UNIT_KMH", "%d" % [roundi(speed_kmh)])
		y += 66.0
	if show_vertical_speed and show_altitude:
		var arrow := "▲" if vertical_speed > 0.05 else ("▼" if vertical_speed < -0.05 else " ")
		_row(y, "HUD_VS", "HUD_UNIT_MPS", "%s %.1f" % [arrow, absf(vertical_speed)], 28)


func _row(y: float, label_key: String, unit_key: String, value: String, value_size := 44) -> void:
	var font := HUDDraw.font_bold()
	var label_x := 0.0
	HUDDraw.text(self, font, Vector2(label_x, y + 24), tr(label_key), 26, HORIZONTAL_ALIGNMENT_RIGHT, 92.0)
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(label_x, y + 44), tr(unit_key), 16,
			HORIZONTAL_ALIGNMENT_RIGHT, 92.0, Color(HUDDraw.WHITE, 0.85))
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(110, y + 44), value, value_size,
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 110.0)
