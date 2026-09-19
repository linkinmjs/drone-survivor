## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDModeBadge
extends Control
## Rounded outline badge with the current flight mode, always visible (top left).


var mode_key := "HUD_MODE_ACRO"
var blinking := false
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 56)


func set_mode(key: String, blink := false) -> void:
	mode_key = key
	blinking = blink
	queue_redraw()


func _process(delta: float) -> void:
	if blinking:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var alpha := 1.0
	if blinking and fmod(_time, 0.8) > 0.5:
		alpha = 0.25
	var font := HUDDraw.font_bold()
	var text := tr(mode_key)
	var font_size := 28
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var box := Rect2(Vector2(2, 2), Vector2(text_width + 36.0, 48.0))
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.anti_aliasing = true
	style.border_color = Color(HUDDraw.SHADOW, HUDDraw.SHADOW.a * alpha)
	draw_style_box(style, box.grow(1.5))
	style.border_color = Color(HUDDraw.WHITE, alpha)
	draw_style_box(style, box)
	HUDDraw.text(self, font, Vector2(box.position.x, box.position.y + 35), text, font_size,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, Color(HUDDraw.WHITE, alpha))
