## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Brújula del HUD de vuelo (`docs/12` §2.1 y §2.4).
##
## Tira horizontal arriba al centro con las letras cardinales, marcas cada 15° y el
## rumbo numérico bajo el cursor. El norte es la dirección −Z del mundo.
##
## ## Estilo de WP-25
##
## Es una **tira fina**: una línea de base de 1 px, marcas cortas, letras chicas y el
## rumbo en una **caja rectangular de radio 2** —la caja de la identidad nueva— en vez
## de un número suelto. La caja es lo que hace que el rumbo se lea sobre cualquier
## cielo sin subirle el cuerpo a la fuente.
class_name HUDCompassTape
extends Control

## Píxeles por grado de rumbo.
const PX_PER_DEG := 2.6

## Medio rango visible, en grados.
const HALF_RANGE := 90.0

## Clave de traducción de cada letra cardinal.
const LETTERS := {0: "HUD_COMPASS_N", 45: "HUD_COMPASS_NE", 90: "HUD_COMPASS_E",
		135: "HUD_COMPASS_SE", 180: "HUD_COMPASS_S", 225: "HUD_COMPASS_SW",
		270: "HUD_COMPASS_W", 315: "HUD_COMPASS_NW"}

## Altura de la línea de base de la tira dentro del control, en píxeles.
const BASE_Y := 34.0

## Tamaño de la caja del rumbo, en píxeles.
const BOX_SIZE := Vector2(76.0, 30.0)

## Rumbo en grados, 0..360
var heading := 0.0
var show_numeric := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PX_PER_DEG * HALF_RANGE * 2.0, 90)


func _draw() -> void:
	var center_x := size.x / 2.0
	var half_width := PX_PER_DEG * HALF_RANGE
	# Línea de base de la tira: fina y apagada, es el riel de las marcas.
	HUDDraw.line(self, Vector2(center_x - half_width, BASE_Y),
			Vector2(center_x + half_width, BASE_Y), 1.0, HUDDraw.TRACK)
	var first := int(floor((heading - HALF_RANGE) / 15.0)) * 15
	var deg := first
	while deg <= heading + HALF_RANGE:
		var offset := (deg - heading) * PX_PER_DEG
		var alpha := HUDDraw.fade(offset, half_width, 70.0)
		if alpha > 0.0:
			var x := center_x + offset
			var value := wrapi(deg, 0, 360)
			var color := Color(HUDDraw.TEXT, HUDDraw.TEXT.a * alpha)
			if LETTERS.has(value):
				var cardinal := value % 90 == 0
				var font_size := 24 if cardinal else 17
				HUDDraw.line(self, Vector2(x, BASE_Y), Vector2(x, BASE_Y - 9.0),
						HUDDraw.STROKE, color)
				HUDDraw.text(self, HUDDraw.font_display(), Vector2(x - 40, BASE_Y - 14.0),
						tr(LETTERS[value]), font_size, HORIZONTAL_ALIGNMENT_CENTER, 80.0, color)
			else:
				HUDDraw.line(self, Vector2(x, BASE_Y), Vector2(x, BASE_Y - 6.0), 1.0,
						Color(color, color.a * 0.7))
		deg += 15
	# Cursor bajo la tira.
	var caret_y := BASE_Y + 3.0
	var caret := PackedVector2Array([Vector2(center_x - 7, caret_y + 8),
			Vector2(center_x + 7, caret_y + 8), Vector2(center_x, caret_y)])
	draw_colored_polygon(caret, HUDDraw.TEXT)
	if not show_numeric:
		return
	var box := Rect2(Vector2(center_x - BOX_SIZE.x / 2.0, caret_y + 10.0), BOX_SIZE)
	HUDDraw.box(self, box, 1.0, HUDDraw.TEXT, HUDDraw.BOX)
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(box.position.x, box.position.y + 22.0),
			"%03d" % [int(round(heading)) % 360], 20, HORIZONTAL_ALIGNMENT_CENTER, BOX_SIZE.x)
