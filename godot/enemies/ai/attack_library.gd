## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Contenedor de las acciones de un enemigo (`docs/06` §2). Reemplaza al
## placeholder de WP-16.
##
## Cuelga un [EnemyAction] por ataque como hijo directo, en el mismo orden que
## `EnemyProfile.attacks`, y le inyecta el enemigo dueño: ninguna acción busca en
## la raíz del árbol. No decide nada —eso es del [UtilitySelector]— ni ejecuta
## nada —eso es del [EnemyFSM]—: sólo enumera y busca por id.
class_name AttackLibrary extends Node

var _actions: Array[EnemyAction] = []
var _by_id: Dictionary[StringName, EnemyAction] = {}
var _built: bool = false


func _ready() -> void:
	rebuild()


## Relee los hijos y reinyecta el enemigo. Es idempotente; lo llaman `_ready()`
## y las escenas que agregan acciones en caliente.
func rebuild() -> void:
	_actions.clear()
	_by_id.clear()
	var host := _resolve_enemy()
	for child: Node in get_children():
		var action := child as EnemyAction
		if action == null:
			continue
		action.enemy = host
		var attack_id := action.id()
		if _by_id.has(attack_id):
			push_error("AttackLibrary: la acción '%s' está repetida." % attack_id)
			continue
		_actions.append(action)
		_by_id[attack_id] = action
	_built = true


## Todas las acciones, en el orden en el que cuelgan del nodo.
func get_actions() -> Array[EnemyAction]:
	if not _built:
		rebuild()
	return _actions


## Acción de id [param attack_id], o `null` si no existe.
func find(attack_id: StringName) -> EnemyAction:
	if not _built:
		rebuild()
	return _by_id.get(attack_id, null) as EnemyAction


## Ids de las acciones disponibles. Mantiene el contrato del placeholder de WP-16.
func attack_ids() -> PackedStringArray:
	var found := PackedStringArray()
	for action: EnemyAction in get_actions():
		found.append(String(action.id()))
	return found


## Deja todos los enfriamientos y contadores a cero.
func reset_actions() -> void:
	for action: EnemyAction in get_actions():
		action.reset_action()


## Enemigo dueño: el primer ancestro [EnemyBase].
func _resolve_enemy() -> EnemyBase:
	var node := get_parent()
	while node != null:
		var found := node as EnemyBase
		if found != null:
			return found
		node = node.get_parent()
	return null
