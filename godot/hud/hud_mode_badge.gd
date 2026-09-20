## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Insignia del modo de vuelo (`docs/12` §2.1, §2.4 y §2.6), abajo al centro.
##
## Parpadea cuando el modo lo impuso el sistema y no el piloto —`RECOVER`—, que es la
## única forma de avisar «no elegiste esto» sin escribir una frase encima del vuelo.
##
## ## Estilo de WP-25
##
## Caja **rectangular de radio 2** con una línea de 1,6 px, como todas las cajas de la
## identidad nueva. Antes era una pastilla de radio 16 con borde de 3 px, que es
## exactamente la geometría que hacía que el HUD se viera «de otro juego».
class_name HUDModeBadge
extends Control

## Alto de la caja, en píxeles.
const BOX_HEIGHT := 40.0

## Aire a cada lado del texto dentro de la caja, en píxeles.
const PADDING_X := 16.0

## Cuerpo del texto, en píxeles.
const FONT_SIZE := 22

## Opacidad del semiciclo apagado del parpadeo.
const BLINK_DIM_ALPHA := 0.25

var mode_key := "HUD_MODE_ACRO"
var blinking := false
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, BOX_HEIGHT + 4.0)


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
		alpha = BLINK_DIM_ALPHA
	var font := HUDDraw.font_display()
	var label := tr(mode_key)
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var box_width := text_width + PADDING_X * 2.0
	var box := Rect2(Vector2((size.x - box_width) * 0.5, 2.0), Vector2(box_width, BOX_HEIGHT))
	HUDDraw.box(self, box, HUDDraw.STROKE, Color(HUDDraw.TEXT, alpha),
			Color(HUDDraw.BOX, HUDDraw.BOX.a * alpha))
	HUDDraw.text(self, font, Vector2(box.position.x, box.position.y + 28.0), label, FONT_SIZE,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, Color(HUDDraw.TEXT, alpha))
