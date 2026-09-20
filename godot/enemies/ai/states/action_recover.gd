## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Estado `RECOVER` de la capa de acción (`docs/06` §11.1).
##
## La cola del ataque: el enemigo ya no hace daño pero sigue comprometido con la
## pose. Es **la ventana de daño del jugador** (`docs/07` §5.9), así que su
## duración sale tal cual del [AttackProfile] y no se recorta por fase. Al
## terminar, la acción arranca su enfriamiento.
class_name ActionRecover extends EnemyActionState


func state_id() -> StringName:
	return &"RECOVER"


func _enter(ctx: Dictionary) -> void:
	super._enter(ctx)
	finite = true
	duration = action.recover_seconds() if action != null else 0.0
	if action != null:
		action.begin_recover()
