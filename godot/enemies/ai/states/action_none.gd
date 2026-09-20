## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Estado `NONE` de la capa de acción (`docs/06` §11.1).
##
## El enemigo no está ejecutando ningún ataque. Es el único estado desde el que
## el [EnemyFSM] consulta al [UtilitySelector], a 4 Hz; mientras tanto la
## locomoción corre libre. No tiene duración: termina cuando hay una acción
## elegida.
class_name ActionNone extends EnemyActionState


func state_id() -> StringName:
	return &"NONE"


func _enter(ctx: Dictionary) -> void:
	super._enter(ctx)
	finite = false
	duration = 0.0
