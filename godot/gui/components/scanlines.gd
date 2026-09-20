## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Rayado de monitor viejo (WP-25).
##
## Líneas horizontales oscuras y muy tenues sobre el fondo, cada [constant PERIOD]
## píxeles. Lo usa la pantalla de carga «del taller»: el jugador nunca deja de mirar
## una pantalla —primero la del taller, después la señal del dron
## (`docs/narrativa/narrativa.md` §5)—, y el rayado es lo que dice «esto es un monitor»
## sin un solo marco dibujado.
##
## Es deliberadamente barato: son [method CanvasItem.draw_rect] de una línea, que se
## rasterizan una vez y quedan en el [CanvasItem] hasta que el control cambie de
## tamaño. Nada de shaders para un fondo que se ve dos segundos.
class_name Scanlines
extends Control

## Separación entre líneas, en píxeles.
const PERIOD: float = 3.0

## Grosor de una línea, en píxeles.
const THICKNESS: float = 1.0

## Opacidad de una línea.
const LINE_ALPHA: float = 0.35


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _discard := resized.connect(queue_redraw)


func _draw() -> void:
	var color := Color(0.0, 0.0, 0.0, LINE_ALPHA)
	var y := 0.0
	while y < size.y:
		draw_rect(Rect2(0.0, y, size.x, THICKNESS), color, true)
		y += PERIOD
