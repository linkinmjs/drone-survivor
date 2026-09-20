## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Base de toda acción de enemigo (`docs/06` §10 y §11, `docs/06` §14).
##
## Un nodo por ataque bajo `AttackLibrary`. La clase base resuelve lo que es
## común a las nueve acciones del Arachnodroid —elegibilidad, puntuación,
## enfriamiento, duraciones y el mínimo de telegrafía— y deja cuatro ganchos
## virtuales para la coreografía concreta:
##
## [codeblock]
## _on_telegraph()      # entra en TELEGRAPH: aviso, pose, apuntado
## _on_active(delta)    # cada tick de ACTIVE: barridos y daño
## _on_recover()        # entra en RECOVER: la ventana de daño del jugador
## _on_interrupt()      # stagger, DOWNED o cambio de fase: apagar todo
## [/codeblock]
##
## [b]Telegrafía obligatoria[/b] (`docs/06` §11.2 y §6.1): ninguna acción con
## `damage_drone > 0` o `damage_building > 0` pasa a `ACTIVE` sin haber estado
## al menos [constant MIN_WINDUP] segundos en `TELEGRAPH`, por mucho que la fase
## multiplique el `windup` hacia abajo. [method effective_windup] aplica ese
## piso y es la invariante que verifica `ai_check`.
##
## [b]Duraciones por acumulador[/b]: ningún [Timer]. El enfriamiento lo descuenta
## este nodo en `_physics_process`; las ventanas las llevan los estados del
## [EnemyFSM]. Así todo escala con `Engine.time_scale` y es reproducible.
class_name EnemyAction extends Node

## Mínimo absoluto de telegrafía tras los multiplicadores de fase, en segundos
## (`docs/06` §6.1 y §11.2).
const MIN_WINDUP: float = 0.80

## Tope del impulso que una acción puede aplicar al dron, en N·s
## (`docs/06` §11.3). Sin él Jolt manda el dron fuera del mundo.
const MAX_IMPULSE: float = 120.0

## Ficha del ataque: ventanas, alcances, daño y volumen de consulta.
@export var profile: AttackProfile = null

## Enemigo dueño de la acción. Lo inyecta [AttackLibrary]; si queda vacío se
## resuelve subiendo por los padres.
var enemy: EnemyBase = null

var _cooldown_left: float = 0.0
var _uses: int = 0
var _last_use_time: float = -1.0e6
var _elapsed: float = 0.0
var _aborted: bool = false


## Descuenta el enfriamiento. Acumulador, nunca un [Timer].
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	_elapsed += delta
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


# --------------------------------------------------------------------------
# Identidad y elegibilidad
# --------------------------------------------------------------------------

## Id estable de la acción. Sale del [AttackProfile]; sin perfil, del nombre del
## nodo, que es lo que permite montar acciones sintéticas en los checks.
func id() -> StringName:
	if profile != null and profile.attack_id != &"":
		return profile.attack_id
	return StringName(name)


## Enemigo dueño, resolviendo el cableado perezoso si hace falta.
func owner_enemy() -> EnemyBase:
	if enemy != null and is_instance_valid(enemy):
		return enemy
	var node := get_parent()
	while node != null:
		var found := node as EnemyBase
		if found != null:
			enemy = found
			return enemy
		node = node.get_parent()
	return null


## `true` si la acción hace daño y por lo tanto exige telegrafía (`docs/06` §11.2).
func is_damaging() -> bool:
	if profile == null:
		return false
	return profile.damage_drone > 0.0 or profile.damage_building > 0.0


## Puntuación de utilidad de 0 a 1 (`docs/06` §10). Las acciones concretas la
## sobrescriben; la base evalúa la [Curve] del perfil sobre `score_input`, y sin
## curva prefiere lo cercano.
func score(ctx: Dictionary) -> float:
	if profile == null:
		return 0.0
	var input := float(ctx.get(profile.score_input, 0.0))
	if profile.score_curve != null:
		var span := maxf(profile.max_range, 1.0)
		return ActionScore.from_curve(profile.score_curve, input / span)
	return ActionScore.inverse_distance(target_distance(ctx), maxf(profile.max_range, 1.0))


## `true` si la acción es elegible ahora mismo: sin enfriamiento pendiente,
## dentro de `[min_range, max_range]`, desbloqueada por la fase y con sus partes
## sanas (`docs/06` §10 punto 2).
func can_run(ctx: Dictionary) -> bool:
	if profile == null:
		return false
	if _cooldown_left > 0.0:
		return false
	var distance := target_distance(ctx)
	if distance < profile.min_range or distance > profile.max_range:
		return false
	if not _phase_allows():
		return false
	return not _parts_broken()


## Alias con el nombre de `docs/06` §14.
func is_available(ctx: Dictionary) -> bool:
	return can_run(ctx)


# --------------------------------------------------------------------------
# Duraciones (`docs/06` §6.1 y §11.2)
# --------------------------------------------------------------------------

## `windup` del perfil tras el multiplicador de fase, [b]sin[/b] el piso. Sólo
## lo usa la prueba negativa de `ai_check`, que necesita ver el valor crudo.
func raw_windup() -> float:
	if profile == null:
		return 0.0
	return maxf(0.0, profile.windup * _multiplier(&"windup"))


## Telegrafía efectiva: nunca por debajo de [constant MIN_WINDUP] segundos.
func effective_windup() -> float:
	return maxf(MIN_WINDUP, raw_windup())


## Segundos que el [EnemyFSM] pasará en `TELEGRAPH`.
##
## Una acción que no hace daño y no declara `windup` —`approach` es locomoción,
## no ataque— entra directo en `ACTIVE`. Todo lo demás paga el piso de
## [constant MIN_WINDUP].
func telegraph_seconds() -> float:
	if not is_damaging() and raw_windup() <= 0.0:
		return 0.0
	return effective_windup()


## Segundos de la ventana activa.
func active_seconds() -> float:
	return maxf(0.0, profile.active) if profile != null else 0.0


## Segundos de recuperación.
func recover_seconds() -> float:
	return maxf(0.0, profile.recover) if profile != null else 0.0


## Enfriamiento tras el multiplicador de fase, en segundos.
func effective_cooldown() -> float:
	if profile == null:
		return 0.0
	return maxf(0.0, profile.cooldown * _multiplier(&"cooldown"))


## Segundos de enfriamiento que quedan.
func cooldown_remaining() -> float:
	return _cooldown_left


## `true` si la locomoción se bloquea mientras dura la acción.
func locks_locomotion() -> bool:
	return profile != null and profile.lock_locomotion


## Veces que se ejecutó la acción.
func use_count() -> int:
	return _uses


## Segundo de simulación del último uso, o un valor muy negativo si nunca corrió.
func last_use_time() -> float:
	return _last_use_time


## Deja el enfriamiento y los contadores como recién creados. Lo usan los checks.
func reset_action() -> void:
	_cooldown_left = 0.0
	_uses = 0
	_last_use_time = -1.0e6
	_aborted = false


## Aborta la ventana activa: el ataque pasa [b]directo a `RECOVER` sin hacer
## daño[/b] y paga igual su enfriamiento.
##
## Es la válvula del gate de apoyo de `docs/06` §10.2 y `docs/07` §5.4: al
## [i]decidir[/i], un pisotón sólo exige no estar saltando, tambaleando ni caído
## —el trote deja exactamente dos patas apoyadas, así que pedir tres en el score
## lo dejaría en cero para siempre—; la comprobación de apoyo va al [i]entrar[/i]
## en `ACTIVE`, cuando `lock_locomotion` ya plantó las patas durante el aviso. Si
## ahí no hay apoyo suficiente, el golpe se va al aire.
func abort() -> void:
	_aborted = true


## `true` si la ventana activa en curso quedó abortada.
func is_aborted() -> bool:
	return _aborted


# --------------------------------------------------------------------------
# Ciclo de vida (`docs/06` §14). Lo conduce el [EnemyFSM].
# --------------------------------------------------------------------------

## Marca el arranque de la acción. Lo llama el [EnemyFSM] antes de entrar en el
## primer estado, que puede ser `TELEGRAPH` o —si la acción no es un ataque—
## directamente `ACTIVE`.
func mark_started() -> void:
	_uses += 1
	_last_use_time = _elapsed
	_aborted = false


## Entra en `TELEGRAPH`.
func begin_telegraph() -> void:
	_on_telegraph()


## Un tick del aviso. Es lo que permite a un ataque seguir a su objetivo durante
## el windup y congelar el punto de impacto al final (`docs/07` §5.4).
func tick_telegraph(delta: float) -> void:
	_on_telegraph_tick(delta)


## Entra en `ACTIVE`.
func begin_active() -> void:
	_on_active_begin()


## Un tick de la ventana activa.
func tick_active(delta: float) -> void:
	_on_active(delta)


## Sale de `ACTIVE`.
func end_active() -> void:
	_on_active_end()


## Entra en `RECOVER`.
func begin_recover() -> void:
	_on_recover()


## La acción terminó su ciclo completo: arranca el enfriamiento.
func finish() -> void:
	_cooldown_left = effective_cooldown()
	_on_finish()


## Cancelación por tambaleo, caída o cambio de fase. Respeta el enfriamiento
## como si la acción hubiera terminado (`docs/06` §7 punto 6).
func cancel() -> void:
	_on_interrupt()
	_cooldown_left = effective_cooldown()


# --------------------------------------------------------------------------
# Ganchos virtuales
# --------------------------------------------------------------------------

## Entrada en `TELEGRAPH`: aviso, pose y apuntado.
func _on_telegraph() -> void:
	pass


## Un tick de `TELEGRAPH`.
func _on_telegraph_tick(_delta: float) -> void:
	pass


## Entrada en `ACTIVE`.
func _on_active_begin() -> void:
	pass


## Un tick de `ACTIVE`: barridos y daño.
func _on_active(_delta: float) -> void:
	pass


## Salida de `ACTIVE`.
func _on_active_end() -> void:
	pass


## Entrada en `RECOVER`.
func _on_recover() -> void:
	pass


## Fin del ciclo completo.
func _on_finish() -> void:
	pass


## Interrupción: apagar todo lo que la acción hubiera encendido.
func _on_interrupt() -> void:
	pass


# --------------------------------------------------------------------------
# Utilidades para las acciones concretas
# --------------------------------------------------------------------------

## Distancia horizontal al objetivo que le corresponde a esta acción según
## `AttackProfile.target_kind`.
func target_distance(ctx: Dictionary) -> float:
	if profile != null and profile.target_kind == AttackProfile.TargetKind.BUILDING:
		return float(ctx.get(&"city_distance", 1.0e6))
	return float(ctx.get(&"distance", 1.0e6))


## Punto del mundo al que apunta la acción.
func target_point(ctx: Dictionary) -> Vector3:
	if profile != null and profile.target_kind == AttackProfile.TargetKind.BUILDING:
		return ctx.get(&"city_position", Vector3.ZERO) as Vector3
	return ctx.get(&"believed_position", Vector3.ZERO) as Vector3


## Nodo [Telegraph] del enemigo, o `null` si la escena no lo trae.
func telegraph_node() -> Telegraph:
	var host := owner_enemy()
	if host == null:
		return null
	return host.get_node_or_null(^"Telegraph") as Telegraph


## Avisa al cerebro de que la acción acaba de dañar la ciudad, para que
## `ctx.time_since_city_attack` vuelva a cero (`docs/06` §10.1).
##
## La llamada va por *duck typing* a propósito: tipar el `Brain` como [EnemyFSM]
## cerraría un ciclo de referencias entre la máquina y sus acciones.
func notify_city_attack() -> void:
	var host := owner_enemy()
	if host == null or host.brain == null:
		return
	if host.brain.has_method(&"notify_city_attack"):
		host.brain.call(&"notify_city_attack")


## Estado de física del mundo, o `null` fuera del árbol.
func space_state() -> PhysicsDirectSpaceState3D:
	var host := owner_enemy()
	if host == null:
		return null
	return host.get_world_3d().direct_space_state


## RID de todos los cuerpos del enemigo, para excluirlos de los barridos.
func self_exclusions() -> Array[RID]:
	var rids: Array[RID] = []
	var host := owner_enemy()
	if host == null:
		return rids
	var pending: Array[Node] = [host]
	var index := 0
	while index < pending.size():
		for child: Node in pending[index].get_children():
			pending.append(child)
		var body := pending[index] as CollisionObject3D
		if body != null:
			rids.append(body.get_rid())
		index += 1
	return rids


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## Multiplicador de fase de [param key], o 1.0 sin enemigo.
func _multiplier(key: StringName) -> float:
	var host := owner_enemy()
	if host == null:
		return 1.0
	return host.phase_multiplier(key)


## `true` si la fase desbloqueó la acción y no la tiene bloqueada.
##
## Sin enemigo —acciones sintéticas de un check— la fase no opina. Una acción
## que el guion de fases no nombra nunca tampoco: sólo se descarta a las que
## aparecen en algún `unlock_attacks` y todavía no se desbloquearon.
func _phase_allows() -> bool:
	var host := owner_enemy()
	if host == null:
		return true
	var attack_id := id()
	if host.is_attack_locked(attack_id):
		return false
	if not _declared_in_phases(host, attack_id):
		return true
	return host.unlocked_attacks().has(String(attack_id))


## `true` si algún bloque `then.unlock_attacks` del perfil nombra la acción.
func _declared_in_phases(host: EnemyBase, attack_id: StringName) -> bool:
	if host.profile == null:
		return false
	var needle := String(attack_id)
	for phase: Dictionary in host.profile.phases:
		var effects := phase.get("then", {}) as Dictionary
		for declared: String in EnemyBase.to_string_array(effects.get("unlock_attacks", [])):
			if declared == needle:
				return true
	return false


## `true` si falta alguna parte requerida o se rompió alguna que deshabilita la
## acción (`docs/06` §4).
func _parts_broken() -> bool:
	var host := owner_enemy()
	if host == null or profile == null:
		return false
	for raw_id: String in profile.disabled_if_broken:
		var part := host.get_part(StringName(raw_id))
		if part != null and (part.is_broken() or part.is_detached()):
			return true
	for raw_id: String in profile.requires_parts:
		var part := host.get_part(StringName(raw_id))
		if part == null or part.is_broken() or part.is_detached():
			return true
	return false
