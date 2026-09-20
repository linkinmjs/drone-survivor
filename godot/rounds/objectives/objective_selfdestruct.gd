## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Objetivo de cierre de la ronda 1: derrotarlo antes de que detone (`docs/11` §5).
##
## Es la cuenta regresiva de `docs/07` §6 hecha línea de tarea: cuando el jefe entra
## en la fase de autodestrucción le quedan 45 s (90 s si llegó ahí por `DOWNED`,
## `docs/07` §15 #11) y lo único que importa es rematarlo antes. Cierra con
## `Events.enemy_defeated`, que es el mismo hecho con el que [RoundManager] decide la
## victoria: el objetivo **no** la declara, sólo la acompaña (`docs/11` §9.3).
##
## ## Por qué el reloj se pregunta y no se cuenta acá
##
## El temporizador **no se pausa** cuando el dron muere (`docs/07` §15 #4) y arranca
## en un momento que decide el enemigo, no la ronda. Un acumulador propio en
## [method _tick] se desincronizaría en la primera reaparición y mentiría justo en los
## últimos segundos, que son los que el jugador mira. Así que el objetivo **lee** el
## reloj del enemigo en cada cuadro.
##
## Se lee por **nombre de método** y no por tipo: `Objective` tiene que seguir siendo
## genérico y no puede depender de `Arachnodroid` (`docs/11` §5). Cualquier enemigo
## que publique [member remaining_method] y [member total_method] alimenta esta línea;
## el que no lo haga, simplemente no muestra barra ni reloj.
class_name ObjectiveSelfdestruct
extends Objective

## Ids de catálogo cuyo `enemy_defeated` cierra el objetivo.
@export var enemy_ids: PackedStringArray = PackedStringArray(["arachnodroid"])

## Método sin argumentos del enemigo que devuelve los segundos que faltan para la
## detonación, o un valor negativo si no hay cuenta en marcha.
@export var remaining_method: StringName = &"selfdestruct_remaining"

## Método sin argumentos del enemigo que devuelve la duración total de la cuenta.
@export var total_method: StringName = &"selfdestruct_total"

## Duración que se asume si el enemigo no publica [member total_method], en segundos.
@export_range(1.0, 600.0, 0.5) var fallback_seconds: float = 45.0

## Ids ya derrotados, sin repetidos.
var _down: Dictionary[StringName, bool] = {}


func _on_start() -> void:
	if not Events.enemy_defeated.is_connected(_on_enemy_defeated):
		var _discard := Events.enemy_defeated.connect(_on_enemy_defeated)
	_recount()


func _on_restart() -> void:
	# La cuenta del jefe no se pausa ni se reinicia con el dron (`docs/07` §15 #4).
	pass


func _on_stop() -> void:
	if Events.enemy_defeated.is_connected(_on_enemy_defeated):
		Events.enemy_defeated.disconnect(_on_enemy_defeated)


func get_task_text() -> String:
	return objective_key if not objective_key.is_empty() else "OBJ_SELFDESTRUCT_TITLE"


## La mecha consumida, de 0 a 1. Negativo —barra escondida— mientras no haya cuenta:
## una barra en cero diría «todavía no pasó nada» y lo que pasa es que no hay reloj.
func get_progress() -> float:
	var left := remaining_seconds()
	if left < 0.0:
		return -1.0
	return clampf(1.0 - left / maxf(total_seconds(), 0.001), 0.0, 1.0)


## Cuenta regresiva en `m:ss`, o `""` si todavía no hay ninguna.
func get_progress_text() -> String:
	var left := remaining_seconds()
	if left < 0.0:
		return ""
	var whole := int(ceilf(left))
	return "%d:%02d" % [whole / 60, whole % 60]


func get_success_text() -> String:
	return tr("OBJ_SELFDESTRUCT_DONE")


## Segundos que faltan para la detonación, o `-1.0` si ningún enemigo está contando.
func remaining_seconds() -> float:
	var enemy := _counting_enemy()
	if enemy == null:
		return -1.0
	return float(enemy.call(remaining_method))


## Duración total de la cuenta en marcha, o [member fallback_seconds].
func total_seconds() -> float:
	var enemy := _counting_enemy()
	if enemy == null or not enemy.has_method(total_method):
		return fallback_seconds
	var total := float(enemy.call(total_method))
	return total if total > 0.0 else fallback_seconds


## Cuántos ids de [member enemy_ids] ya cayeron.
func get_defeated_count() -> int:
	return _down.size()


# --- Internos ---------------------------------------------------------------------------------

## Primer enemigo del contexto con una cuenta regresiva en marcha.
func _counting_enemy() -> EnemyBase:
	if ctx == null:
		return null
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy) or not enemy.has_method(remaining_method):
			continue
		if float(enemy.call(remaining_method)) >= 0.0:
			return enemy
	return null


func _on_enemy_defeated(_enemy: Node3D, enemy_id: StringName) -> void:
	if not active or not enemy_ids.has(String(enemy_id)):
		return
	_down[enemy_id] = true
	if _down.size() >= enemy_ids.size():
		finish()


## Recuenta contra el estado real: si el jefe cayó entre dos objetivos —la detonación
## se lleva 0.8 s de `success_delay` por delante—, esta línea se cierra igual.
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
