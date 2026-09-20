## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Objetivo 3 de la ronda 1: destruir el núcleo (`docs/11` §5).
##
## Cierra cuando todos los ids de [member enemy_ids] aparecieron en
## `Events.enemy_defeated`. Es el mismo hecho con el que [RoundManager] decide la
## victoria, y a propósito: el objetivo **no** es quien la declara, sólo la acompaña
## en la línea de tarea (`docs/11` §9.3).
class_name ObjectiveDefeatEnemy extends Objective

## Ids de catálogo que hay que derrotar, en cualquier orden.
@export var enemy_ids: PackedStringArray = PackedStringArray(["arachnodroid"])

## Ids ya derrotados, sin repetidos.
var _down: Dictionary[StringName, bool] = {}


func _on_start() -> void:
	if not Events.enemy_defeated.is_connected(_on_enemy_defeated):
		var _discard := Events.enemy_defeated.connect(_on_enemy_defeated)
	_recount()


func _on_restart() -> void:
	# Un enemigo derrotado no vuelve: el progreso sobrevive a la reaparición del dron.
	pass


func _on_stop() -> void:
	if Events.enemy_defeated.is_connected(_on_enemy_defeated):
		Events.enemy_defeated.disconnect(_on_enemy_defeated)


func get_task_text() -> String:
	return objective_key if not objective_key.is_empty() else "OBJ_DEFEAT_ENEMY_TITLE"


## Cuánto se le comió al jefe, de 0 a 1 (`docs/11` §5).
func get_progress() -> float:
	return clampf(1.0 - _structure_ratio(), 0.0, 1.0)


func get_progress_text() -> String:
	var percent := int(roundf(_structure_ratio() * 100.0))
	return tr("OBJ_DEFEAT_ENEMY_PROGRESS").format([percent])


func get_success_text() -> String:
	return tr("OBJ_DEFEAT_ENEMY_DONE")


## Cuántos ids de [member enemy_ids] ya cayeron.
func get_defeated_count() -> int:
	return _down.size()


## Estructura que le queda al enemigo más entero del contexto.
func _structure_ratio() -> float:
	if ctx == null:
		return 1.0
	var worst := -1.0
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy):
			continue
		worst = maxf(worst, enemy.total_structure_ratio())
	return worst if worst >= 0.0 else 0.0


func _on_enemy_defeated(_enemy: Node3D, enemy_id: StringName) -> void:
	if not active or not enemy_ids.has(String(enemy_id)):
		return
	_down[enemy_id] = true
	if _down.size() >= enemy_ids.size():
		finish()


## Recuenta contra el estado real: si el jefe cayó antes de que este objetivo
## arrancara —por autodestrucción, por ejemplo—, se cierra igual.
func _recount() -> void:
	if ctx == null:
		return
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy) or not enemy.is_defeated() or enemy.profile == null:
			continue
		if enemy_ids.has(String(enemy.profile.enemy_id)):
			_down[enemy.profile.enemy_id] = true
	if active and not enemy_ids.is_empty() and _down.size() >= enemy_ids.size():
		finish()
