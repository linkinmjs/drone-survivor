## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Indicador de carga de la pantalla «del taller» (WP-25).
##
## Antes era un arco girando, que es el spinner de cualquier aplicación. Ahora es una
## **barra de puntos ámbar** que se encienden de izquierda a derecha: se lee como un
## aparato del taller cargando, no como una web esperando. Es la misma idea que el
## indicador de señal del HUD —barras discretas, nada continuo— y por eso comparte el
## ámbar de [constant UIPalette.ACCENT].
##
## No mide progreso real (para eso está la [ProgressBar] de `SceneTransition`): dice
## «esto sigue vivo».
class_name LoadingSpinner
extends Control

## Cantidad de puntos.
const DOT_COUNT: int = 7

## Radio de un punto, en píxeles.
const DOT_RADIUS: float = 4.0

## Separación entre centros de puntos, en píxeles.
const DOT_SPACING: float = 18.0

## Puntos por segundo del barrido.
const SPEED: float = 6.0

## Cuántos puntos se quedan encendidos detrás del que va adelante.
const TAIL: float = 2.5

## Opacidad de un punto apagado.
const OFF_ALPHA: float = 0.18

var _phase: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(DOT_COUNT * DOT_SPACING, DOT_RADIUS * 4.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_phase = fmod(_phase + delta * SPEED, float(DOT_COUNT) + TAIL)
	queue_redraw()


func _draw() -> void:
	var total := (DOT_COUNT - 1) * DOT_SPACING
	var origin := Vector2((size.x - total) * 0.5, size.y * 0.5)
	for index: int in DOT_COUNT:
		var distance := _phase - float(index)
		var lit := 0.0
		if distance >= 0.0 and distance <= TAIL:
			lit = 1.0 - distance / TAIL
		var color := UIPalette.ACCENT if lit > 0.0 else UIPalette.ACCENT_DIM
		var alpha := lerpf(OFF_ALPHA, 1.0, lit)
		draw_circle(origin + Vector2(index * DOT_SPACING, 0.0), DOT_RADIUS,
				UIPalette.with_alpha(color, alpha), true, -1.0, true)
