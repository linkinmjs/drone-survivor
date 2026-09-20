## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cronómetro de la ronda (`docs/12` §4.1 y §8).
##
## `mm:ss` en mono, arriba a la derecha, con polling de
## [method RoundManager.get_elapsed_seconds]. Pasa a `ACCENT` al superar
## [method RoundManager.get_time_par], que es el par de tiempo con el que
## `docs/11` §6.2 calcula la medalla: el color es el único aviso de que la medalla de
## oro ya se fue.
##
## Es uno de los dos componentes que el EMP puede dejar en `--` (`docs/12` §4.3); el
## otro es `HUDReadouts`, que es del HUD de vuelo.
##
## La posición evita los números del `FlightHUD`, que ocupan de la `y` 112 a la 312
## pegados al borde derecho del mismo lienzo (`hud/hud.tscn`).
class_name HUDRoundTimer
extends CombatHUDComponent

## Margen al borde derecho del lienzo, en píxeles.
const RIGHT_MARGIN: float = 40.0

## Distancia del borde superior del lienzo a la línea base del número.
const TOP_MARGIN: float = 58.0

## Ancho del bloque de texto, en píxeles.
const BLOCK_WIDTH: float = 200.0

## Ronda de la que se lee el tiempo. La escribe [method bind_round].
var manager: RoundManager = null

var _elapsed: float = 0.0
var _over_par: bool = false


## Ata el cronómetro a la ronda. Con `null` se queda en `00:00`.
func bind_round(round_manager: RoundManager) -> void:
	manager = round_manager
	_elapsed = 0.0
	_over_par = false
	queue_redraw()


func _tick(_delta: float) -> void:
	# El tiempo no lo lleva el HUD: lo lleva `RoundManager`, que ya descuenta la
	# pausa y la cinemática (`docs/11` §4). Acá sólo se lo mira.
	var elapsed := 0.0
	if manager != null and is_instance_valid(manager):
		elapsed = manager.get_elapsed_seconds()
	if not is_finite(elapsed):
		elapsed = 0.0
	var par := 0.0
	if manager != null and is_instance_valid(manager):
		par = manager.get_time_par()
	var over := par > 0.0 and elapsed > par
	# Redibujo por **segundo mostrado**, no por cuadro: el número sólo cambia una
	# vez por segundo y son 60 `_draw()` ahorrados (riesgo 5 de `docs/12` §10).
	if int(elapsed) == int(_elapsed) and over == _over_par and not glitch_scramble:
		_elapsed = elapsed
		return
	_elapsed = elapsed
	_over_par = over
	queue_redraw()


## Segundos de batalla que se están mostrando.
func elapsed_seconds() -> float:
	return _elapsed


## El texto tal cual se dibuja, `mm:ss` o `--:--` bajo EMP.
func text() -> String:
	if glitch_scramble:
		return "--:--"
	var total := maxi(int(_elapsed), 0)
	return "%02d:%02d" % [total / 60, total % 60]


## `true` cuando el tiempo ya superó el par de la ronda.
func is_over_par() -> bool:
	return _over_par


func _draw() -> void:
	if not begin_draw():
		return
	var colour := CombatHUDPalette.ACCENT if _over_par else CombatHUDPalette.TEXT
	var right := size.x - RIGHT_MARGIN
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(right - BLOCK_WIDTH, TOP_MARGIN),
			text(), 30, HORIZONTAL_ALIGNMENT_RIGHT, BLOCK_WIDTH, colour)
