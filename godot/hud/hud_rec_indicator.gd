## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDRecIndicator
extends Control
## Blinking red dot + "REC" while the lap is being recorded as a replay.


var recording := false:
	set(value):
		if value != recording:
			recording = value
			queue_redraw()
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(140, 44)


func _process(delta: float) -> void:
	if recording:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if not recording:
		return
	var on := fmod(_time, 1.0) < 0.65
	var dot_center := Vector2(16, size.y / 2.0)
	draw_circle(dot_center, 12.0, HUDDraw.SHADOW, true, -1.0, true)
	if on:
		draw_circle(dot_center, 10.0, UIPalette.HUD_REC, true, -1.0, true)
	HUDDraw.text(self, HUDDraw.font_bold(), Vector2(36, size.y / 2.0 + 10), tr("HUD_REC"), 28,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, UIPalette.HUD_REC)
