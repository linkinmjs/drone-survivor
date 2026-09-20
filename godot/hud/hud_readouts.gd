## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Números exactos del HUD de vuelo (`docs/12` §2.1, §2.3 y §2.4): altura, velocidad en
## km/h y velocidad vertical, arriba a la derecha.
##
## Es un componente **numérico**: se redibuja cuando `FlightHUD` publica el promedio
## ponderado por tiempo, no cada cuadro, para que los dígitos sean legibles.
##
## ## Estilo de WP-25
##
## Una **columna estrecha** ([constant COLUMN_WIDTH] px) en vez del bloque ancho de
## antes: el rótulo y la unidad van arriba a la izquierda en Barlow chico —la voz
## propia—, y el valor abajo a la derecha en JetBrains Mono. Nada de rótulos gritados
## en display: lo que tiene que leerse de un vistazo es el número.
class_name HUDReadouts
extends Control

## Ancho de la columna, en píxeles.
const COLUMN_WIDTH := 200.0

## Alto de una fila, en píxeles.
const ROW_HEIGHT := 60.0

## Cuerpo del rótulo, en píxeles.
const LABEL_SIZE := 15

## Cuerpo de la unidad, en píxeles.
const UNIT_SIZE := 14

## Cuerpo del valor, en píxeles.
const VALUE_SIZE := 34

var altitude := 0.0
var speed_kmh := 0.0
var vertical_speed := 0.0
var show_altitude := true
var show_speed := true
var show_vertical_speed := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(COLUMN_WIDTH, ROW_HEIGHT * 3.0)


func _draw() -> void:
	var y := 0.0
	if show_altitude:
		var value := "%.1f" % altitude if absf(altitude) < 10.0 else "%d" % [roundi(altitude)]
		_row(y, "HUD_ALT", "HUD_UNIT_M", value)
		y += ROW_HEIGHT
	if show_speed:
		_row(y, "HUD_SPD", "HUD_UNIT_KMH", "%d" % [roundi(speed_kmh)])
		y += ROW_HEIGHT
	if show_vertical_speed and show_altitude:
		var arrow := "+" if vertical_speed > 0.05 else ("-" if vertical_speed < -0.05 else " ")
		_row(y, "HUD_VS", "HUD_UNIT_MPS", "%s%.1f" % [arrow, absf(vertical_speed)], 26)


## Una fila: rótulo y unidad arriba a la izquierda, valor abajo a la derecha.
func _row(y: float, label_key: String, unit_key: String, value: String,
		value_size := VALUE_SIZE) -> void:
	var width := maxf(size.x, COLUMN_WIDTH)
	HUDDraw.text(self, HUDDraw.font_text(), Vector2(0.0, y + 14.0), tr(label_key), LABEL_SIZE,
			HORIZONTAL_ALIGNMENT_LEFT, width, HUDDraw.DIM)
	HUDDraw.text(self, HUDDraw.font_text(), Vector2(0.0, y + 14.0), tr(unit_key), UNIT_SIZE,
			HORIZONTAL_ALIGNMENT_RIGHT, width, HUDDraw.DIM)
	HUDDraw.line(self, Vector2(0.0, y + 19.0), Vector2(width, y + 19.0), 1.0, HUDDraw.TRACK)
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(0.0, y + 50.0), value, value_size,
			HORIZONTAL_ALIGNMENT_RIGHT, width)
