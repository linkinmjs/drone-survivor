## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Caja de stick del HUD de vuelo (`docs/12` §2.1 y §7).
##
## Dibuja el marco cuadrado de un stick de radio y el punto donde está la deflexión
## actual. El HUD monta dos: el izquierdo lleva `(guiñada, acelerador)` y el derecho
## `(alabeo, cabeceo)`, los cuatro en `[−1, 1]` y ya con curvas y zona muerta aplicadas
## (`docs/03` §4). El acelerador llega como **deflexión** (`2·t − 1`) y no como
## `[0, 1]`, que es justamente lo que permite dibujar los dos sticks con el mismo
## dibujo (`docs/03` §9, [method Drone.get_stick_input]).
##
## Es un componente **continuo** (`docs/12` §2.3): se redibuja con el valor instantáneo
## cada frame, no con el promedio de los numéricos. Un stick que se mueve a 10 Hz no
## transmite nada.
##
## Convención de pantalla: `+y` del stick es hacia arriba (acelerador arriba, morro
## arriba), así que el punto se dibuja en `centro + (x, −y) · medio_lado`.
class_name HUDStickInput
extends Control

## Lado del marco, en píxeles. El control puede ser mayor: el marco se centra.
const BOX_SIDE: float = 104.0

## Radio del punto de deflexión, en píxeles.
const DOT_RADIUS: float = 5.0

## Largo de las marcas de centro que salen de cada lado del marco, en píxeles.
const TICK_LENGTH: float = 9.0

## Grosor del marco, en píxeles.
const FRAME_WIDTH: float = 2.0

## Deflexión actual del stick, en `[−1, 1]` por eje.
var value: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BOX_SIDE + 6.0, BOX_SIDE + 6.0)


## Fija la deflexión del stick y pide redibujo (`docs/12` §7).
func update_stick_input(stick: Vector2) -> void:
	var wanted := Vector2(clampf(stick.x, -1.0, 1.0), clampf(stick.y, -1.0, 1.0))
	if wanted.is_equal_approx(value):
		return
	value = wanted
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var half := BOX_SIDE * 0.5
	var top_left := centre - Vector2(half, half)
	var top_right := centre + Vector2(half, -half)
	var bottom_right := centre + Vector2(half, half)
	var bottom_left := centre + Vector2(-half, half)

	HUDDraw.line(self, top_left, top_right, FRAME_WIDTH)
	HUDDraw.line(self, top_right, bottom_right, FRAME_WIDTH)
	HUDDraw.line(self, bottom_right, bottom_left, FRAME_WIDTH)
	HUDDraw.line(self, bottom_left, top_left, FRAME_WIDTH)

	# Marcas de centro: dicen dónde está el reposo sin tapar el punto.
	var faint := Color(HUDDraw.WHITE, 0.55)
	HUDDraw.line(self, Vector2(centre.x, centre.y - half),
			Vector2(centre.x, centre.y - half + TICK_LENGTH), FRAME_WIDTH, faint)
	HUDDraw.line(self, Vector2(centre.x, centre.y + half),
			Vector2(centre.x, centre.y + half - TICK_LENGTH), FRAME_WIDTH, faint)
	HUDDraw.line(self, Vector2(centre.x - half, centre.y),
			Vector2(centre.x - half + TICK_LENGTH, centre.y), FRAME_WIDTH, faint)
	HUDDraw.line(self, Vector2(centre.x + half, centre.y),
			Vector2(centre.x + half - TICK_LENGTH, centre.y), FRAME_WIDTH, faint)

	# `+y` del stick es arriba; `+y` de pantalla es abajo.
	var dot := centre + Vector2(value.x, -value.y) * half
	draw_circle(dot, DOT_RADIUS + 1.5, HUDDraw.SHADOW, true, -1.0, true)
	draw_circle(dot, DOT_RADIUS, HUDDraw.WHITE, true, -1.0, true)
