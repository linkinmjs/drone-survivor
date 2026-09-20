## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Objetivo de la ronda 1: destruir los núcleos con la carcasa abierta (`docs/11` §5).
##
## Es [ObjectiveBreakParts] con dos agregados y ninguna resta: el contador cuenta
## **núcleos** en vez de rodillas y el objetivo también cierra cuando el enemigo entra
## en [member end_phase_id] o cae. Los dos agregados existen por el mismo motivo: en
## el Arachnodroid **dos** núcleos rotos ya disparan `p5_selfdestruct` (`docs/07` §6),
## así que exigir los tres dejaría la línea de tarea diciendo «destruí los 3 núcleos»
## mientras el jefe ya está contando para detonar, que es justo el momento en el que
## el jugador necesita leer otra cosa.
##
## ## Qué enseña
##
## El texto es el que responde a «no entendí cómo vencerlo» (WP-24d): la carcasa se
## abrió, hay tres núcleos y **hay que tirarles desde abajo**. Sin esa última parte el
## jugador orbita al jefe a la altura de los hombros y no encuentra nunca el cono de
## 70° de `docs/07` §4.
##
## Sigue siendo genérico: los ids de núcleo son un `@export` y la fase de cierre otro.
## No hay una sola referencia al Arachnodroid en el código.
class_name ObjectiveBreakCores
extends ObjectiveBreakParts

## Fase del enemigo que también cierra el objetivo, comparada **por índice** igual que
## en [ObjectiveDefendCity] (`docs/11` §12, fila 5). Vacía = sólo cuenta el contador.
@export var end_phase_id: StringName = &"p5_selfdestruct"

## Ids de catálogo cuyo `enemy_defeated` cierra el objetivo. Un jefe que cae antes de
## que se rompa el tercer núcleo —se autodestruyó, por ejemplo— no puede dejar la
## cadena trabada.
@export var enemy_ids: PackedStringArray = PackedStringArray(["arachnodroid"])

## Índice de [member end_phase_id] en las fases del enemigo, o `-1` si no se resolvió.
var _end_phase_index: int = -1


func _setup() -> void:
	_end_phase_index = _resolve_end_phase_index()


func _on_start() -> void:
	super()
	if not Events.enemy_phase_changed.is_connected(_on_phase_changed):
		var _discard := Events.enemy_phase_changed.connect(_on_phase_changed)
	if not Events.enemy_defeated.is_connected(_on_enemy_defeated):
		var _discard := Events.enemy_defeated.connect(_on_enemy_defeated)
	# El jefe puede haber entrado en la fase de detonación antes de que este objetivo
	# arrancara: el que cierra la cadena anterior y el que abre ésta son el mismo
	# cuadro, y `success_delay` mete 0.8 s en el medio.
	_check_end_conditions()


func _on_stop() -> void:
	super()
	if Events.enemy_phase_changed.is_connected(_on_phase_changed):
		Events.enemy_phase_changed.disconnect(_on_phase_changed)
	if Events.enemy_defeated.is_connected(_on_enemy_defeated):
		Events.enemy_defeated.disconnect(_on_enemy_defeated)


func get_task_text() -> String:
	return objective_key if not objective_key.is_empty() else "OBJ_BREAK_CORES_TITLE"


func get_success_text() -> String:
	return tr("OBJ_BREAK_CORES_DONE")


## `true` cuando el enemigo ya llegó a [member end_phase_id] o cayó.
func is_end_reached() -> bool:
	if ctx == null:
		return false
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.is_defeated():
			return true
		if _end_phase_index >= 0 and enemy.current_phase_index() >= _end_phase_index:
			return true
		if _end_phase_index < 0 and end_phase_id != &"" \
				and enemy.current_phase() == end_phase_id:
			return true
	return false


# --- Internos ---------------------------------------------------------------------------------

func _check_end_conditions() -> void:
	if active and is_end_reached():
		finish()


## La fase que trae el evento cuenta tanto como la que se lee del enemigo
## ([method Objective.phase_index_of] explica por qué).
func _on_phase_changed(enemy: Node3D, phase_id: StringName) -> void:
	if not active:
		return
	var announced := phase_index_of(enemy, phase_id)
	if (_end_phase_index >= 0 and announced >= _end_phase_index) \
			or (_end_phase_index < 0 and phase_id == end_phase_id):
		finish()
		return
	_check_end_conditions()


func _on_enemy_defeated(_enemy: Node3D, enemy_id: StringName) -> void:
	if active and enemy_ids.has(String(enemy_id)):
		finish()


## Posición de [member end_phase_id] en la lista de fases del primer enemigo.
func _resolve_end_phase_index() -> int:
	var enemy := ctx.first_enemy() if ctx != null else null
	if enemy == null or enemy.profile == null or end_phase_id == &"":
		return -1
	for index: int in enemy.profile.phases.size():
		var phase: Dictionary = enemy.profile.phases[index]
		if StringName(phase.get("id", &"")) == end_phase_id:
			return index
	return -1
