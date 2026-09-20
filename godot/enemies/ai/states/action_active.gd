## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Estado `ACTIVE` de la capa de acción (`docs/06` §11.3).
##
## Es la ventana en la que el ataque hace daño. Reenvía cada tick a
## [method EnemyAction.tick_active], que es donde vive el `intersect_shape` de la
## acción concreta; el estado no sabe nada de volúmenes ni de capas.
##
## [b]Aborto[/b] (`docs/06` §10.2, `docs/07` §5.4): si al entrar la acción llama
## a [method EnemyAction.abort] —el gate de apoyo del pisotón, del barrido y del
## salto—, la ventana termina en el acto, sin un solo barrido, y el [EnemyFSM]
## pasa a `RECOVER`. El enfriamiento se paga igual: el golpe se dio, aunque al
## aire.
class_name ActionActive extends EnemyActionState


func state_id() -> StringName:
	return &"ACTIVE"


func _enter(ctx: Dictionary) -> void:
	super._enter(ctx)
	finite = true
	duration = action.active_seconds() if action != null else 0.0
	if action == null:
		return
	action.begin_active()
	if action.is_aborted():
		force_finish()


func _tick(delta: float) -> void:
	if action != null and action.is_aborted():
		force_finish()
		return
	super._tick(delta)
	if action != null:
		action.tick_active(delta)


func _exit() -> void:
	if action != null:
		action.end_active()
	super._exit()
