## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cintas laterales del HUD de vuelo (`docs/12` §2.1 y §2.4).
##
## Dos columnas que enmarcan el centro: la izquierda corre con la **velocidad** y la
## derecha con la **altura**.
##
## ## Estilo de WP-25
##
## Antes eran dos peines mudos: el movimiento decía «estás acelerando» pero no cuánto.
## Ahora cada [constant MAJOR_STEP] unidades hay una marca larga **con su número** en
## JetBrains Mono, y un **cursor** fijo en el centro señala el valor actual. El número
## grande sigue estando en `HUDReadouts`; esto es la referencia de escala que hace que
## el movimiento de la cinta signifique algo.
class_name HUDSideTapes
extends Control

## Distancia del centro de la pantalla a cada cinta, en píxeles.
const DISTANCE_FROM_CENTER := 320.0

## Media altura útil de una cinta, en píxeles.
const HALF_HEIGHT := 250.0

## Píxeles por unidad. Con [constant MINOR_STEP] de 1, cada marca chica es una unidad.
const PX_PER_UNIT := 13.0

## Cada cuántas unidades va una marca chica.
const MINOR_STEP := 1

## Cada cuántas unidades va una marca larga con número.
const MAJOR_STEP := 5

## Medio ancho de una marca chica, en píxeles.
const MINOR_HALF := 4.0

## Medio ancho de una marca larga, en píxeles.
const MAJOR_HALF := 9.0

## Valor mínimo que puede mostrar una cinta. Ni la velocidad ni la altura del dron son
## negativas, así que dibujar marcas bajo el cero solo aportaba ruido.
const MIN_UNIT := 0

## Velocidad en m/s.
var speed := 0.0

## Altura en m.
var altitude := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size / 2.0
	_draw_tape(center.x - DISTANCE_FROM_CENTER, center.y, speed, -1.0)
	_draw_tape(center.x + DISTANCE_FROM_CENTER, center.y, altitude, 1.0)


## Dibuja una cinta en la columna [param x] centrada en [param value].
##
## [param side] vale −1 para la cinta izquierda y +1 para la derecha: los números y el
## cursor van siempre del lado de **afuera**, para dejar limpio el centro de la imagen.
func _draw_tape(x: float, center_y: float, value: float, side: float) -> void:
	var first := int(floor((value - HALF_HEIGHT / PX_PER_UNIT) / MINOR_STEP)) * MINOR_STEP
	var last := int(ceil((value + HALF_HEIGHT / PX_PER_UNIT) / MINOR_STEP)) * MINOR_STEP
	var unit := maxi(first, MIN_UNIT)
	while unit <= last:
		var y := center_y - (float(unit) - value) * PX_PER_UNIT
		var alpha := HUDDraw.fade(y - center_y, HALF_HEIGHT, 80.0)
		if alpha > 0.0:
			var major := unit % MAJOR_STEP == 0
			var half := MAJOR_HALF if major else MINOR_HALF
			var color := Color(HUDDraw.TEXT, HUDDraw.TEXT.a * alpha * (1.0 if major else 0.6))
			HUDDraw.line(self, Vector2(x - half, y), Vector2(x + half, y), HUDDraw.STROKE, color)
			if major:
				var label_x := x + side * (MAJOR_HALF + 6.0)
				if side < 0.0:
					label_x -= 56.0
				var alignment := HORIZONTAL_ALIGNMENT_RIGHT if side < 0.0 \
						else HORIZONTAL_ALIGNMENT_LEFT
				HUDDraw.text(self, HUDDraw.font_mono(), Vector2(label_x, y + 6.0),
						"%d" % [unit], 16, alignment, 56.0,
						Color(HUDDraw.DIM, HUDDraw.DIM.a * alpha))
		unit += MINOR_STEP
	# Carril: dice dónde empieza y dónde termina la ventana de la cinta.
	HUDDraw.line(self, Vector2(x, center_y - HALF_HEIGHT), Vector2(x, center_y + HALF_HEIGHT),
			1.0, HUDDraw.TRACK)
	# Cursor fijo: la punta señala el valor de ahora.
	var tip := Vector2(x + side * (MAJOR_HALF + 2.0), center_y)
	var back := tip + Vector2(side * 11.0, 0.0)
	var cursor := PackedVector2Array([tip, back + Vector2(0.0, -6.0), back + Vector2(0.0, 6.0)])
	draw_colored_polygon(cursor, HUDDraw.TEXT)
