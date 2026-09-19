## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDCompassTape
extends Control
## Compass ribbon at the top of the screen: cardinal and intercardinal letters, ticks every
## 15 degrees and a caret with the numeric heading. North is the -Z direction of the world.


const PX_PER_DEG := 2.6
const HALF_RANGE := 90.0
const LETTERS := {0: "HUD_COMPASS_N", 45: "HUD_COMPASS_NE", 90: "HUD_COMPASS_E",
		135: "HUD_COMPASS_SE", 180: "HUD_COMPASS_S", 225: "HUD_COMPASS_SW",
		270: "HUD_COMPASS_W", 315: "HUD_COMPASS_NW"}

## Heading in degrees, 0..360
var heading := 0.0
var show_numeric := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PX_PER_DEG * HALF_RANGE * 2.0, 96)


func _draw() -> void:
	var center_x := size.x / 2.0
	var base_y := 44.0
	var half_width := PX_PER_DEG * HALF_RANGE
	var first := int(floor((heading - HALF_RANGE) / 15.0)) * 15
	var deg := first
	while deg <= heading + HALF_RANGE:
		var offset := (deg - heading) * PX_PER_DEG
		var alpha := HUDDraw.fade(offset, half_width, 70.0)
		if alpha > 0.0:
			var x := center_x + offset
			var value := wrapi(deg, 0, 360)
			var color := Color(HUDDraw.WHITE, HUDDraw.WHITE.a * alpha)
			if LETTERS.has(value):
				var cardinal := value % 90 == 0
				var font_size := 34 if cardinal else 22
				HUDDraw.text(self, HUDDraw.font_bold(), Vector2(x - 40, base_y), tr(LETTERS[value]),
						font_size, HORIZONTAL_ALIGNMENT_CENTER, 80.0, color)
			else:
				HUDDraw.line(self, Vector2(x, base_y - 22), Vector2(x, base_y - 8), 2.0, color)
		deg += 15
	# Caret under the ribbon
	var caret_y := base_y + 10.0
	var caret := PackedVector2Array([Vector2(center_x - 8, caret_y + 10),
			Vector2(center_x + 8, caret_y + 10), Vector2(center_x, caret_y)])
	draw_colored_polygon(caret, HUDDraw.WHITE)
	if show_numeric:
		HUDDraw.text(self, HUDDraw.font_mono(), Vector2(center_x - 40, caret_y + 36),
				"%03d" % [int(round(heading)) % 360], 22, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
