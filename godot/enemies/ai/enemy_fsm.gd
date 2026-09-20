## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Máquina de estados de dos capas del enemigo (`docs/06` §11). Es el nodo
## `Brain` del árbol de `docs/06` §2 y reemplaza al placeholder de WP-16.
##
## [b]Capa de locomoción[/b] (`IDLE`, `WALK`, `TURN`, `CLIMB`, `LEAP`, `STAGGER`,
## `DOWNED`): la [b]reporta el rig[/b] de WP-17, que es quien sabe si está
## trepando o saltando; el FSM la consume y sólo decide si está bloqueada.
##
## [b]Capa de acción[/b] (`NONE`, `TELEGRAPH`, `ACTIVE`, `RECOVER`): cada estado
## es un nodo hijo con `_enter/_exit/_tick/can_exit` (`docs/06` §11.1). El FSM
## enruta y nada más: no hay lógica de gameplay acá dentro.
##
## Ciclo de un tick de física:
##
## 1. Si el enemigo está tambaleando o caído, se [b]interrumpe[/b] la acción en
##    curso ([method EnemyAction.cancel], que respeta el enfriamiento) y la capa
##    de acción vuelve a `NONE`. `STAGGER` y `DOWNED` tienen prioridad absoluta.
## 2. Se avanza el estado actual y, si agotó su ventana, se pasa al siguiente:
##    `TELEGRAPH → ACTIVE → RECOVER → NONE`.
## 3. A [member EnemyProfile.decision_hz] (4 Hz) y [b]sólo en `NONE`[/b] se arma
##    el `ctx` de `docs/06` §10.1 una sola vez y se consulta al
##    [UtilitySelector]. Una acción sin telegrafía ni daño —`approach`, que es
##    locomoción— entra directo en `ACTIVE`; el resto pasa obligatoriamente por
##    `TELEGRAPH` al menos [constant EnemyAction.MIN_WINDUP] segundos.
## 4. Mientras dura `TELEGRAPH` + `ACTIVE` de una acción con `lock_locomotion`,
##    [method is_locomotion_locked] devuelve `true` y `EnemyBase.move_body()`
##    anula el avance.
##
## [b]Sin objetivo no hay decisión[/b]: si no hay ni creencia sobre el dron ni
## un edificio vivo al alcance, el FSM se queda en `NONE` sin consultar al
## selector. Es lo correcto para el juego —un enemigo sin nada que atacar
## espera— y además deja inertes las escenas de `enemy_parts_check` y de
## `gait_check`, que instancian al jefe para medir otras cosas.
class_name EnemyFSM extends Node

## Cambió la capa de locomoción.
signal locomotion_changed(from: StringName, to: StringName)

## Cambió la capa de acción.
signal action_changed(from: StringName, to: StringName)

## Se eligió una acción (`docs/06` §10 punto 5).
signal action_selected(attack_id: StringName, score: float)

## Estados de la capa de acción (`docs/06` §11.1).
const ACTION_NONE: StringName = &"NONE"
const ACTION_TELEGRAPH: StringName = &"TELEGRAPH"
const ACTION_ACTIVE: StringName = &"ACTIVE"
const ACTION_RECOVER: StringName = &"RECOVER"

## Radio en el que se busca objetivo de ciudad, en metros.
const CITY_SEARCH_RADIUS: float = 400.0

## Cono frontal en el que se cuentan edificios para `ctx.buildings_in_cone`:
## 60° de apertura a 90 m (`docs/06` §10.1).
const CONE_HALF_ANGLE: float = 30.0
const CONE_RANGE: float = 90.0

## Distancia por debajo de la cual el dron cuenta como «cerca» para
## `ctx.time_near` (`docs/06` §10.1 y `docs/07` §5.10).
const NEAR_DISTANCE: float = 12.0

## Largo del rayo con el que se mide la altura del dron sobre el suelo.
const HEIGHT_PROBE: float = 300.0

## Nombres fijos de los hijos que este nodo necesita del árbol de `docs/06` §2.
const ACTION_ROOT: StringName = &"Action"
const ATTACK_LIBRARY_NODE: StringName = &"AttackLibrary"
const TELEGRAPH_NODE: StringName = &"Telegraph"

## Si el FSM decide por su cuenta. Los checks lo apagan para conducirlo a mano.
@export var autonomous: bool = true

## Enemigo dueño. Si queda vacío se toma el padre.
var enemy: EnemyBase = null

## Percepción del enemigo.
var perception: Perception = null

## Biblioteca de acciones.
var library: AttackLibrary = null

## Telegrafía compartida.
var telegraph: Telegraph = null

## Personalidad sorteada en el arranque (`docs/06` §10).
var personality: Personality = null

## Selector de utilidad.
var selector: UtilitySelector = UtilitySelector.new()

var _states: Dictionary[StringName, EnemyActionState] = {}
var _state: EnemyActionState = null
var _action_state: StringName = ACTION_NONE
var _locomotion_state: StringName = &"IDLE"
var _current_action: EnemyAction = null
var _locomotion_locked: bool = false
var _decision_accumulator: float = 0.0
var _decision_ticks: int = 0
var _decisions: int = 0
var _elapsed: float = 0.0
var _time_near: float = 0.0
var _time_since_city_attack: float = 1.0e6
var _last_ctx: Dictionary = {}
var _ready_to_think: bool = false


func _ready() -> void:
	_build_states()
	var _discard := Events.building_destroyed.connect(_on_building_destroyed)


## Conduce las dos capas. Acumuladores, nunca un [Timer].
##
## Con [member Global.debug_freeze_ai] el cerebro no piensa (`docs/11` §11): ni
## avanza el estado en curso ni consulta al selector, así que no hay telegrafías
## ni ataques. Al soltar la bandera retoma donde estaba: los acumuladores no se
## tocan, sólo dejan de avanzar.
func _physics_process(delta: float) -> void:
	if delta <= 0.0 or Global.debug_freeze_ai:
		return
	_elapsed += delta
	_time_since_city_attack += delta
	if not _ready_to_think:
		_setup()
		if not _ready_to_think:
			return

	_sync_locomotion()
	if _should_interrupt():
		_interrupt()

	if _state != null:
		_state._tick(delta)
		if _state.is_finished():
			_advance()

	if not autonomous:
		return
	var step := 1.0 / maxf(_decision_hz(), 0.5)
	_decision_accumulator += delta
	if _decision_accumulator > step * 8.0:
		_decision_accumulator = step * 8.0
	while _decision_accumulator >= step:
		_decision_accumulator -= step
		_decide(step)


# --------------------------------------------------------------------------
# Interfaz pública (`docs/06` §14) y contrato del placeholder de WP-16
# --------------------------------------------------------------------------

## Estado de la capa de acción.
func action_state() -> StringName:
	return _action_state


## Fuerza el estado de la capa de acción sin acción asociada. Lo usan
## `EnemyBase.set_action_state()` y los checks; un estado sin acción no avanza
## solo, así que se queda donde lo dejen.
func set_action_state(state: StringName) -> void:
	if state == _action_state:
		return
	_transition(state, {})


## Pide el estado de acción [param state] (`docs/06` §14).
func request_action(state: StringName, ctx: Dictionary = {}) -> bool:
	if state == _action_state:
		return false
	if not _states.has(state):
		return false
	_transition(state, ctx)
	return true


## Estado de la capa de locomoción, tal como lo reporta el rig de WP-17.
func locomotion_state() -> StringName:
	if enemy != null:
		return enemy.locomotion_state()
	return _locomotion_state


## Fuerza el estado de locomoción. La capa la manda el rig: esto sólo existe
## para las escenas de prueba que no lo tienen.
func set_locomotion_state(state: StringName) -> void:
	if state == _locomotion_state:
		return
	var previous := _locomotion_state
	_locomotion_state = state
	locomotion_changed.emit(previous, state)


## Pide el estado de locomoción [param state] (`docs/06` §14).
func request_locomotion(state: StringName, _ctx: Dictionary = {}) -> bool:
	if state == _locomotion_state:
		return false
	set_locomotion_state(state)
	return true


## `true` si la acción en curso bloquea la locomoción.
func is_locomotion_locked() -> bool:
	return _locomotion_locked


## Bloquea o libera la locomoción a mano.
func set_locomotion_locked(locked: bool) -> void:
	_locomotion_locked = locked


## Acción en curso, o `null`.
func current_action() -> EnemyAction:
	return _current_action


## Contexto de la última decisión (`docs/06` §10.1).
func last_context() -> Dictionary:
	return _last_ctx


## Ticks del reloj de decisión desde el arranque. `ai_check` los usa para
## verificar los 4 Hz.
func decision_ticks() -> int:
	return _decision_ticks


## Consultas reales al selector (sólo las que se hicieron estando en `NONE`).
func decision_count() -> int:
	return _decisions


## Avisa de que el enemigo acaba de dañar la ciudad: reinicia
## `ctx.time_since_city_attack` (`docs/06` §10.1).
func notify_city_attack() -> void:
	_time_since_city_attack = 0.0


## Rehace el cableado y vuelve a sortear la personalidad con la semilla actual.
## Lo usan los checks que cambian `Global.round_seed` en caliente.
func rebuild() -> void:
	_ready_to_think = false
	_setup()


## Arma el contexto de decisión ahora mismo, sin decidir. Lo usan los checks y
## las acciones que necesitan el objetivo de ciudad fuera del ciclo.
func build_context() -> Dictionary:
	return _build_context()


## Rehace el contexto **y lo publica** como el de la última decisión.
##
## [method last_context] es una caché que sólo se refresca al decidir, que es lo
## correcto mientras el cerebro conduce: la acción arranca en el mismo tick en
## que se la eligió. Quien lance una acción desde fuera —un check, el guion del
## showcase— tiene que llamar a esto antes, o la acción apuntará a donde estaba
## el dron la última vez que el cerebro pensó.
func refresh_context() -> Dictionary:
	if enemy == null:
		return _last_ctx
	_last_ctx = _build_context()
	return _last_ctx


# --------------------------------------------------------------------------
# Arranque
# --------------------------------------------------------------------------

## Crea los cuatro estados de la capa de acción bajo un hijo `Action`, si la
## escena no los trae ya (`docs/06` §2).
func _build_states() -> void:
	var root := get_node_or_null(NodePath(String(ACTION_ROOT)))
	if root == null:
		root = Node.new()
		root.name = String(ACTION_ROOT)
		add_child(root)
	_register(root, "None", ActionNone.new())
	_register(root, "Telegraph", ActionTelegraph.new())
	_register(root, "Active", ActionActive.new())
	_register(root, "Recover", ActionRecover.new())
	_state = _states[ACTION_NONE]
	_state._enter({})


## Da de alta un estado, respetando el que la escena hubiera puesto con ese
## nombre.
func _register(root: Node, node_name: String, fallback: EnemyActionState) -> void:
	var existing := root.get_node_or_null(NodePath(node_name)) as EnemyActionState
	if existing == null:
		existing = fallback
		existing.name = node_name
		root.add_child(existing)
	else:
		fallback.free()
	_states[existing.state_id()] = existing


## Resuelve enemigo, percepción, biblioteca y telegrafía, y sortea la
## personalidad. Perezoso: el `_ready()` de este nodo corre **antes** que el de
## [EnemyBase], que es quien construye las partes.
func _setup() -> void:
	enemy = get_parent() as EnemyBase
	if enemy == null:
		return
	perception = enemy.perception as Perception
	library = enemy.get_node_or_null(NodePath(String(ATTACK_LIBRARY_NODE))) as AttackLibrary
	telegraph = enemy.get_node_or_null(NodePath(String(TELEGRAPH_NODE))) as Telegraph
	if library == null:
		return

	var ids := library.attack_ids()
	var spread := enemy.profile.personality_spread if enemy.profile != null else \
			Personality.DEFAULT_SPREAD
	personality = Personality.from_seed(Global.round_seed, ids, spread)
	var enemy_id: StringName = enemy.profile.enemy_id if enemy.profile != null else &""
	selector.configure(Global.round_seed ^ hash(enemy_id))
	if not selector.action_selected.is_connected(_on_action_selected):
		var _discard := selector.action_selected.connect(_on_action_selected)
	_ready_to_think = true


# --------------------------------------------------------------------------
# Enrutado
# --------------------------------------------------------------------------

## Pasa al estado [param state] con [param ctx], cerrando el anterior.
##
## Si [param ctx] trae una acción, [b]se adopta como la acción en curso[/b]. Sin
## esto, un [method request_action] desde fuera —un check, el guion del
## showcase— telegrafiaría bien y llegaría a `ACTIVE` con la acción en `null`:
## la ventana activa correría su tiempo sin resolver un solo barrido, que es
## exactamente el fallo que no se ve en ninguna traza.
func _transition(state: StringName, ctx: Dictionary) -> void:
	var target := _states.get(state, null) as EnemyActionState
	if target == null:
		return
	var incoming := ctx.get(&"action", null) as EnemyAction
	if incoming != null:
		_current_action = incoming
	if _state != null:
		_state._exit()
	var previous := _action_state
	_action_state = state
	_state = target
	_state._enter(ctx)
	_refresh_lock()
	action_changed.emit(previous, state)
	if enemy != null:
		# La exposición de los puntos débiles depende de la capa de acción
		# (`WHILE_ATTACK`, `docs/06` §5): hay que reevaluarla en el acto.
		enemy.set_action_state(state)


## Encadena `TELEGRAPH → ACTIVE → RECOVER → NONE`.
func _advance() -> void:
	match _action_state:
		ACTION_TELEGRAPH:
			_transition(ACTION_ACTIVE, {&"action": _current_action})
		ACTION_ACTIVE:
			_transition(ACTION_RECOVER, {&"action": _current_action})
		ACTION_RECOVER:
			_finish_action()
		_:
			pass


## Cierra el ciclo de la acción: enfriamiento y vuelta a `NONE`.
func _finish_action() -> void:
	if _current_action != null:
		_current_action.finish()
	_current_action = null
	_transition(ACTION_NONE, {})


## Corta la acción en curso por tambaleo, caída o pedido externo.
func _interrupt() -> void:
	if _current_action != null:
		_current_action.cancel()
		_current_action = null
	if telegraph != null:
		telegraph.cancel()
	_transition(ACTION_NONE, {})


## `true` si hay que cortar: tambaleo o caída con una acción en curso.
func _should_interrupt() -> bool:
	if _action_state == ACTION_NONE:
		return false
	if enemy == null:
		return false
	return enemy.is_staggered() or enemy.is_downed()


## Recalcula el bloqueo de locomoción: sólo durante `TELEGRAPH` + `ACTIVE` de
## una acción que lo pida (`docs/06` §11.1).
func _refresh_lock() -> void:
	var in_window := _action_state == ACTION_TELEGRAPH or _action_state == ACTION_ACTIVE
	_locomotion_locked = in_window and _current_action != null \
			and _current_action.locks_locomotion()


## Copia el estado de locomoción que reporta el rig, para publicar el cambio.
func _sync_locomotion() -> void:
	if enemy == null:
		return
	var reported := enemy.locomotion_state()
	if reported == _locomotion_state:
		return
	var previous := _locomotion_state
	_locomotion_state = reported
	locomotion_changed.emit(previous, reported)


# --------------------------------------------------------------------------
# Decisión (`docs/06` §10)
# --------------------------------------------------------------------------

## Un tick del reloj de decisión.
func _decide(step: float) -> void:
	_decision_ticks += 1
	if enemy == null or library == null:
		return
	if enemy.is_downed() or enemy.is_staggered():
		return
	if _action_state != ACTION_NONE:
		return

	var ctx := _build_context()
	_last_ctx = ctx
	_track_near(step, ctx)
	if not bool(ctx.get(&"has_any_target", false)):
		return
	# La creencia alimenta el cono de los puntos débiles (`docs/06` §5).
	if float(ctx.get(&"confidence", 0.0)) > 0.0:
		enemy.set_target_position(ctx.get(&"believed_position", Vector3.ZERO) as Vector3)

	_decisions += 1
	var top_n := enemy.profile.top_n if enemy.profile != null else UtilitySelector.DEFAULT_TOP_N
	var chosen := selector.select(library.get_actions(), ctx, personality, top_n)
	if chosen == null:
		return
	_begin_action(chosen, ctx)


## Arranca [param action]. Sin telegrafía ni daño entra directo en `ACTIVE`; con
## cualquiera de las dos, pasa obligatoriamente por `TELEGRAPH`.
func _begin_action(action: EnemyAction, ctx: Dictionary) -> void:
	_current_action = action
	action.mark_started()
	var payload := ctx.duplicate()
	payload[&"action"] = action
	payload[&"telegraph"] = telegraph
	if action.telegraph_seconds() > 0.0:
		_transition(ACTION_TELEGRAPH, payload)
	else:
		_transition(ACTION_ACTIVE, payload)


## Lleva el acumulador de `ctx.time_near`.
func _track_near(step: float, ctx: Dictionary) -> void:
	if float(ctx.get(&"distance", 1.0e6)) <= NEAR_DISTANCE:
		_time_near += step
	else:
		_time_near = 0.0


## Arma el contexto de `docs/06` §10.1, una sola vez por decisión.
func _build_context() -> Dictionary:
	var origin := enemy.global_position
	var believed := origin
	var believed_velocity := Vector3.ZERO
	var confidence := 0.0
	var has_los := false
	if perception != null:
		believed = perception.believed_position
		believed_velocity = perception.believed_velocity
		confidence = perception.confidence
		has_los = perception.has_los

	var flat := Vector3(believed.x - origin.x, 0.0, believed.z - origin.z)
	var city := _pick_city_target(origin)
	var city_position := city.global_position if city != null else origin
	var city_flat := Vector3(city_position.x - origin.x, 0.0, city_position.z - origin.z)
	var has_drone := perception != null and perception.get_target() != null \
			and (confidence > 0.0 or has_los)

	var legs_lost := enemy.legs_lost()
	var planted := 0
	if enemy.locomotion != null and enemy.locomotion.has_method(&"planted_count"):
		planted = int(enemy.locomotion.call(&"planted_count"))

	# Destino forzado por el enemigo, si lo declara: es la carrera de 45 s del
	# Arachnodroid hacia el centro de la ciudad (`docs/07` §6, P5). Va por *duck
	# typing* porque es una excepción de un enemigo, no una regla del marco.
	var march: Variant = null
	if enemy.has_method(&"march_goal"):
		march = enemy.call(&"march_goal")
	var has_march := typeof(march) == TYPE_VECTOR3

	return {
		&"enemy": enemy,
		&"position": origin,
		&"distance": flat.length(),
		&"distance_3d": origin.distance_to(believed),
		&"drone_height": _height_above_ground(believed),
		&"drone_speed": believed_velocity.length(),
		&"has_los": has_los,
		&"confidence": confidence,
		&"believed_position": believed,
		&"believed_velocity": believed_velocity,
		&"time_near": _time_near,
		&"time_since_city_attack": _time_since_city_attack,
		&"buildings_in_cone": _buildings_in_cone(origin),
		&"structure_ratio": enemy.total_structure_ratio(),
		&"phase": enemy.current_phase(),
		&"planted_legs": planted,
		&"legs_lost": legs_lost,
		&"city_target": city,
		&"city_position": city_position,
		&"city_distance": city_flat.length() if city != null else 1.0e6,
		&"city_value": _value_of(city),
		&"city_bias": enemy.phase_multiplier(&"city_bias"),
		&"march_goal": march if has_march else origin,
		&"has_march_goal": has_march,
		&"has_drone_target": has_drone,
		&"has_city_target": city != null,
		&"has_any_target": has_drone or city != null or has_march,
		&"action_state": _action_state,
		&"is_downed": enemy.is_downed(),
		&"personality": personality,
		&"round_seed": Global.round_seed,
	}


## Edificio objetivo: el que esté bajo asedio si lo hay, y si no el de mayor
## `value` dentro de [constant CITY_SEARCH_RADIUS], desempatando por cercanía.
## Las ruinas no cuentan (`docs/10` §5).
func _pick_city_target(origin: Vector3) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(&"buildings_under_siege"):
		var besieged := node as Node3D
		if besieged != null and _is_alive(besieged):
			return besieged

	var best: Node3D = null
	var best_value := -1
	var best_distance := 0.0
	for node: Node in tree.get_nodes_in_group(&"buildings"):
		var building := node as Node3D
		if building == null or not _is_alive(building):
			continue
		var distance := origin.distance_to(building.global_position)
		if distance > CITY_SEARCH_RADIUS:
			continue
		var value := _value_of(building)
		if value > best_value or (value == best_value and distance < best_distance):
			best = building
			best_value = value
			best_distance = distance
	return best


## `value` del edificio, o 0 si el nodo no lo declara.
func _value_of(building: Node3D) -> int:
	if building == null:
		return 0
	var declared: Variant = building.get(&"value")
	return int(declared) if typeof(declared) == TYPE_INT else 0


## `true` si el edificio sigue en pie.
func _is_alive(building: Node3D) -> bool:
	if not is_instance_valid(building):
		return false
	if building.has_method(&"is_destroyed"):
		return not bool(building.call(&"is_destroyed"))
	return true


## Edificios vivos en el cono frontal de 60° a ≤ 90 m (`docs/06` §10.1).
func _buildings_in_cone(origin: Vector3) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var facing := -enemy.global_basis.z
	facing.y = 0.0
	if facing.is_zero_approx():
		return 0
	facing = facing.normalized()
	var limit := cos(deg_to_rad(CONE_HALF_ANGLE))
	var count := 0
	for node: Node in tree.get_nodes_in_group(&"buildings"):
		var building := node as Node3D
		if building == null or not _is_alive(building):
			continue
		var to_building := building.global_position - origin
		to_building.y = 0.0
		var distance := to_building.length()
		if distance > CONE_RANGE or distance < 0.01:
			continue
		if facing.dot(to_building / distance) >= limit:
			count += 1
	return count


## Altura de [param point] sobre el suelo que tiene debajo, en metros.
func _height_above_ground(point: Vector3) -> float:
	var space := enemy.get_world_3d().direct_space_state
	if space == null:
		return point.y
	var query := PhysicsRayQueryParameters3D.create(point,
			point + Vector3.DOWN * HEIGHT_PROBE, PhysicsLayers.QUERY_FOOT)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return point.y
	return point.y - (hit["position"] as Vector3).y


## Reemite la elección del selector.
func _on_action_selected(attack_id: StringName, score: float) -> void:
	action_selected.emit(attack_id, score)


## Un edificio caído también cuenta como «la ciudad recibió daño hace poco».
func _on_building_destroyed(_position: Vector3, _value: int) -> void:
	_time_since_city_attack = 0.0


## Frecuencia de decisión del perfil, en Hz.
func _decision_hz() -> float:
	if enemy != null and enemy.profile != null:
		return enemy.profile.decision_hz
	return 4.0
