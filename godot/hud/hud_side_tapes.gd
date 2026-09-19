## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDSideTapes
extends Control
## Two vertical columns of ticks framing the center: the left one scrolls with the speed and
## the right one with the altitude. They carry no numbers (the readouts do), the movement
## alone tells the pilot that they are accelerating or climbing.


const DISTANCE_FROM_CENTER := 320.0
const HALF_HEIGHT := 270.0
const TICK_SPACING := 26.0
const SPEED_PX_PER_MPS := 13.0
const ALTITUDE_PX_PER_M := 26.0

var speed := 0.0
var altitude := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size / 2.0
	_draw_tape(center.x - DISTANCE_FROM_CENTER, center.y, speed * SPEED_PX_PER_MPS)
	_draw_tape(center.x + DISTANCE_FROM_CENTER, center.y, altitude * ALTITUDE_PX_PER_M)


func _draw_tape(x: float, center_y: float, scroll_px: float) -> void:
	var offset := fposmod(scroll_px, TICK_SPACING)
	var base_index := int(floor(scroll_px / TICK_SPACING))
	var i := -int(ceil(HALF_HEIGHT / TICK_SPACING)) - 1
	while i <= int(ceil(HALF_HEIGHT / TICK_SPACING)) + 1:
		var y := center_y + i * TICK_SPACING + offset
		var dy := y - center_y
		var alpha := HUDDraw.fade(dy, HALF_HEIGHT, 90.0)
		if alpha > 0.0:
			var color := Color(HUDDraw.WHITE, HUDDraw.WHITE.a * alpha)
			# Every fifth tick is a small square block, the rest are short dashes
			if (base_index - i) % 5 == 0:
				draw_rect(Rect2(Vector2(x - 6, y - 5), Vector2(12, 10)), Color(HUDDraw.SHADOW, alpha * 0.35))
				draw_rect(Rect2(Vector2(x - 5, y - 4), Vector2(10, 8)), color)
			else:
				HUDDraw.line(self, Vector2(x - 6, y), Vector2(x + 6, y), 3.0, color)
		i += 1
	# Fixed end caps
	var cap := Color(HUDDraw.WHITE, 0.9)
	HUDDraw.line(self, Vector2(x - 7, center_y - HALF_HEIGHT), Vector2(x + 7, center_y - HALF_HEIGHT), 3.0, cap)
	HUDDraw.line(self, Vector2(x - 7, center_y + HALF_HEIGHT), Vector2(x + 7, center_y + HALF_HEIGHT), 3.0, cap)
