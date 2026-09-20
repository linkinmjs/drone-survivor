## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Objetivo 2 de la ronda 1: romper 3 de las 4 rodillas (`docs/11` §5).
##
## Cuenta ids **distintos** de [member part_ids] en `Events.enemy_part_broken`: la
## misma rodilla rota dos veces —imposible hoy, pero barato de cubrir— no suma dos.
##
## El conteo arranca en cero cada vez que el objetivo arranca, pero **no** se pierde
## al reaparecer el dron: las rodillas rotas siguen rotas. Por eso [method
## _on_restart] no lo toca.
class_name ObjectiveBreakParts extends Objective

## Ids de parte que cuentan para este objetivo (`docs/07` §4).
@export var part_ids: PackedStringArray = PackedStringArray([
	"wp_leg_fl_knee", "wp_leg_fr_knee", "wp_leg_bl_knee", "wp_leg_br_knee",
])

## Cuántas de [member part_ids] hay que romper para cerrar el objetivo.
@export_range(1, 16) var required_count: int = 3

## Ids ya rotos, sin repetidos.
var _broken: Dictionary[StringName, bool] = {}


func _on_start() -> void:
	if not Events.enemy_part_broken.is_connected(_on_part_broken):
		var _discard := Events.enemy_part_broken.connect(_on_part_broken)
	_recount()


func _on_restart() -> void:
	# Una rodilla rota sigue rota después de reaparecer: no se reinicia nada.
	pass


func _on_stop() -> void:
	if Events.enemy_part_broken.is_connected(_on_part_broken):
		Events.enemy_part_broken.disconnect(_on_part_broken)


func get_task_text() -> String:
	return objective_key if not objective_key.is_empty() else "OBJ_BREAK_PARTS_TITLE"


func get_progress() -> float:
	return clampf(float(_broken.size()) / float(maxi(required_count, 1)), 0.0, 1.0)


func get_progress_text() -> String:
	return "%d / %d" % [mini(_broken.size(), required_count), required_count]


func get_success_text() -> String:
	return tr("OBJ_BREAK_PARTS_DONE")


## Cuántos ids distintos de [member part_ids] están rotos.
func get_broken_count() -> int:
	return _broken.size()


func _on_part_broken(_enemy: Node3D, part_id: StringName, _position: Vector3) -> void:
	if not active or not _counts(part_id):
		return
	_broken[part_id] = true
	if _broken.size() >= required_count:
		finish()


## Recuenta contra lo que ya pasó: si una rodilla cayó antes de que este objetivo
## arrancara, el progreso tiene que reflejarlo igual.
##
## Es **aditivo**, nunca borra: las dos fuentes son la cuenta que [RoundManager] lleva
## del bus desde que empezó la ronda y el estado real de las partes del enemigo. La
## primera es la que manda —el hecho es el evento, no la malla—, y la segunda cubre a
## un enemigo que llegara ya roto.
func _recount() -> void:
	if ctx == null:
		return
	if ctx.round_manager != null and ctx.round_manager.has_method(&"get_broken_part_ids"):
		var ids: Array = ctx.round_manager.call(&"get_broken_part_ids")
		for part_id: StringName in ids:
			if _counts(part_id):
				_broken[part_id] = true
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy):
			continue
		for part: EnemyPart in enemy.get_parts():
			if part.is_broken() and _counts(part.part_id):
				_broken[part.part_id] = true
	if active and _broken.size() >= required_count:
		finish()


func _counts(part_id: StringName) -> bool:
	return part_ids.has(String(part_id))
