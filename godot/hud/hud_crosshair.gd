## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Retículo de vuelo del HUD (`docs/12` §2.1 y §2.4): marca a dónde apunta la cámara FPV.
##
## ## Estilo de WP-25
##
## Más liviano: cuatro marcas cortas y un punto, sin el anillo grueso de antes. El
## retículo del `FlightHUD` **no** es una mira de arma —esa es la de `hud/combat/`— y
## tiene que estorbar lo menos posible en el centro de la imagen.
class_name HUDCrosshair
extends Control

## Distancia del centro al arranque de cada marca, en píxeles.
const INNER_RADIUS := 7.0

## Distancia del centro al final de cada marca, en píxeles.
const OUTER_RADIUS := 16.0

## Radio del punto central, en píxeles.
const DOT_RADIUS := 1.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(48, 48)


func _draw() -> void:
	var c := size / 2.0
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		HUDDraw.line(self, c + direction * INNER_RADIUS, c + direction * OUTER_RADIUS,
				HUDDraw.STROKE)
	draw_circle(c, DOT_RADIUS + 1.0, HUDDraw.SHADOW, true, -1.0, true)
	draw_circle(c, DOT_RADIUS, HUDDraw.TEXT, true, -1.0, true)
