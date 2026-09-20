## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Estado `TELEGRAPH` de la capa de acción (`docs/06` §11.2).
##
## Es el aviso obligatorio: ninguna acción dañina llega a `ACTIVE` sin haber
## pasado por acá al menos [constant EnemyAction.MIN_WINDUP] segundos. Al entrar
## le pasa al [Telegraph] el [TelegraphProfile] del ataque, enciende sus canales
## —luz emisiva, audio de carga y señal espacial— y publica
## `Events.enemy_attack_telegraphed(enemy, attack_id, duration)`; al salir los
## apaga. La duración sale de [method EnemyAction.telegraph_seconds], que ya
## aplicó el multiplicador de fase y el piso absoluto.
class_name ActionTelegraph extends EnemyActionState

## Color al que vira la carga cuando el [AttackProfile] no declara
## [TelegraphProfile].
##
## Es el rojo de aviso de `docs/06` §11.2: la luz emisiva arranca en el cian de
## reposo del Arachnodroid (`docs/07` §2) y vira a este rojo mientras dura el
## windup, que es lo que el jugador lee para saber que tiene que esquivar.
const DEFAULT_COLOR: Color = Color(1.0, 0.25, 0.1)

var _telegraph: Telegraph = null


func state_id() -> StringName:
	return &"TELEGRAPH"


func _enter(ctx: Dictionary) -> void:
	super._enter(ctx)
	finite = true
	duration = action.telegraph_seconds() if action != null else 0.0
	_telegraph = ctx.get(&"telegraph", null) as Telegraph
	if action == null:
		return
	if _telegraph != null and duration > 0.0:
		# El perfil va **antes** de `begin()`: es lo que decide el color de
		# reposo, el sonido de carga y qué señal espacial se enciende.
		_telegraph.set_profile(_telegraph_profile())
		_telegraph.begin(action.id(), duration, _color())
	action.begin_telegraph()


func _tick(delta: float) -> void:
	super._tick(delta)
	if action != null:
		action.tick_telegraph(delta)
	if _telegraph != null:
		_telegraph.tick(delta)


func _exit() -> void:
	if _telegraph != null:
		_telegraph.end()
		_telegraph = null
	super._exit()


## [TelegraphProfile] del ataque en curso, o `null`.
func _telegraph_profile() -> TelegraphProfile:
	if action == null or action.profile == null:
		return null
	return action.profile.telegraph


## Color de la carga: el del [TelegraphProfile] si lo hay, o el rojo de aviso.
func _color() -> Color:
	var cfg := _telegraph_profile()
	if cfg == null:
		return DEFAULT_COLOR
	return cfg.light_color_to
