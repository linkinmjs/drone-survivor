## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Objetivo 1 de la ronda 1: contener el asedio (`docs/11` §5).
##
## Cierra cuando el enemigo entra en [member target_phase_id] —es decir, cuando deja
## de ignorar al dron— o cuando pasan [member max_seconds] segundos, lo que ocurra
## primero. No hay forma de fallarlo: si la ciudad cae antes, la ronda ya terminó en
## derrota por su cuenta (`docs/11` §4.1).
##
## **La comparación es por índice, no por id** (`docs/11` §12, fila 5): las fases de
## un [EnemyProfile] están ordenadas y son monótonas, así que un salto de `p1_siege`
## directo a `p3_fury` también cierra el objetivo. Comparar ids sueltos lo dejaría
## abierto para siempre.
class_name ObjectiveDefendCity extends Objective

## Fase del enemigo que cierra el objetivo (`docs/07` §6).
@export var target_phase_id: StringName = &"p2_alert"

## Segundos tras los que el objetivo se cierra igual.
@export_range(1.0, 600.0, 0.5) var max_seconds: float = 90.0

var _elapsed: float = 0.0

## Índice de [member target_phase_id] dentro de las fases del enemigo, o `-1` si no
## se pudo resolver (entonces sólo cuenta el tiempo).
var _target_index: int = -1


func _setup() -> void:
	_target_index = _resolve_target_index()


func _on_start() -> void:
	if not Events.enemy_phase_changed.is_connected(_on_phase_changed):
		var _discard := Events.enemy_phase_changed.connect(_on_phase_changed)


func _on_restart() -> void:
	# El tiempo de asedio **no** se reinicia con el dron: lo que mide es cuánto
	# aguantó la ciudad, no cuánto sobrevivió el piloto.
	pass


func _on_stop() -> void:
	if Events.enemy_phase_changed.is_connected(_on_phase_changed):
		Events.enemy_phase_changed.disconnect(_on_phase_changed)


func _tick(delta: float) -> void:
	_elapsed += delta
	# El enemigo puede haber entrado en la fase antes de que este objetivo arrancara.
	if _reached_target_phase():
		finish()
		return
	if _elapsed >= max_seconds:
		finish()


func get_task_text() -> String:
	return objective_key if not objective_key.is_empty() else "OBJ_DEFEND_CITY_TITLE"


func get_progress() -> float:
	return clampf(_elapsed / maxf(max_seconds, 0.001), 0.0, 1.0)


func get_progress_text() -> String:
	var percent := int(roundf(_integrity() * 100.0))
	return tr("OBJ_DEFEND_CITY_PROGRESS").format([percent])


func get_success_text() -> String:
	return tr("OBJ_DEFEND_CITY_DONE")


## Segundos que lleva el asedio.
func get_elapsed() -> float:
	return _elapsed


func _integrity() -> float:
	return ctx.integrity() if ctx != null else 1.0


## Verdadero si algún enemigo del contexto ya alcanzó la fase objetivo.
func _reached_target_phase() -> bool:
	if ctx == null:
		return false
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy):
			continue
		if _target_index >= 0 and enemy.current_phase_index() >= _target_index:
			return true
		if _target_index < 0 and enemy.current_phase() == target_phase_id:
			return true
	return false


func _on_phase_changed(_enemy: Node3D, _phase_id: StringName) -> void:
	if active and _reached_target_phase():
		finish()


## Posición de [member target_phase_id] en la lista de fases del primer enemigo.
func _resolve_target_index() -> int:
	var enemy := ctx.first_enemy() if ctx != null else null
	if enemy == null or enemy.profile == null:
		return -1
	for index: int in enemy.profile.phases.size():
		var phase: Dictionary = enemy.profile.phases[index]
		if StringName(phase.get("id", &"")) == target_phase_id:
			return index
	return -1
