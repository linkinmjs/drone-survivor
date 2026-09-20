## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Objetivo de aguante: sobrevivir [member seconds] segundos (`docs/11` §5).
##
## **No está en la cadena de la ronda 1**: se implementa y se verifica en WP-21 y
## queda disponible para las rondas de intercepción (WP-35) y para el tutorial de
## combate. El cronómetro es un acumulador de [method _tick], así que no corre en
## pausa ni durante la cinemática: el secuenciador es `PROCESS_MODE_PAUSABLE` y
## sólo arranca en `BATTLE`.
##
## A diferencia de los otros tres, este objetivo **sí** pierde su progreso al
## reaparecer el dron: lo que mide es cuánto aguantó el piloto vivo.
class_name ObjectiveSurviveTime extends Objective

## Segundos que hay que aguantar.
@export_range(1.0, 1200.0, 0.5) var seconds: float = 60.0

var _elapsed: float = 0.0


func _on_restart() -> void:
	_elapsed = 0.0


func _tick(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= seconds:
		finish()


func get_task_text() -> String:
	return objective_key if not objective_key.is_empty() else "OBJ_SURVIVE_TIME_TITLE"


func get_progress() -> float:
	return clampf(_elapsed / maxf(seconds, 0.001), 0.0, 1.0)


## Cuenta regresiva en `m:ss`.
func get_progress_text() -> String:
	var left := int(ceilf(maxf(seconds - _elapsed, 0.0)))
	return "%d:%02d" % [left / 60, left % 60]


func get_success_text() -> String:
	return tr("OBJ_SURVIVE_TIME_DONE")


## Segundos aguantados desde la última reaparición.
func get_elapsed() -> float:
	return _elapsed
