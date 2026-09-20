## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Contrato común de todos los enemigos (`docs/06` §2, §6 y §7).
##
## Arma el grafo de partes en `_ready()` a partir de los metadatos que dejó el
## importador voxel (`docs/05` §12), da de alta los puntos débiles, agrupa las
## patas para el rig y lleva la salud escalonada, las fases y el movedor
## cinemático. **Ningún número vive acá**: todo sale de [EnemyProfile].
##
## Árbol esperado (`docs/06` §2), por nombre fijo de hijo:
## [codeblock]
## <Enemy> (EnemyBase, Node3D)
## ├── Model (Node3D)          ← instancia del GLB importado
## ├── Parts (Node)            ← se llena en _ready()
## ├── WeakPoints (Node)       ← se llena en _ready()
## ├── Locomotion (Node3D)     ← WP-17
## ├── Perception (Node)       ← WP-18
## ├── Brain (Node)            ← WP-18
## ├── AttackLibrary (Node)    ← WP-19
## ├── AudioRig (Node3D)       ← WP-19
## └── Telegraph (Node3D)      ← WP-19
## [/codeblock]
##
## **Alcance de WP-16**: el grafo, el daño, el desprendimiento, los puntos
## débiles, las fases y `move_body`. La locomoción procedural (WP-17), la
## percepción y el selector (WP-18) y los ataques (WP-19) llegan después; sus
## nodos existen como placeholder con la interfaz mínima que declara `docs/06`.
class_name EnemyBase extends Node3D

## Se rompió una parte.
signal part_broken(part_id: StringName)

## Cambió la exposición de un punto débil.
signal weak_point_state_changed(weak_point_id: StringName, exposed: bool)

## El enemigo entró en una fase nueva. Las fases son monótonas.
signal phase_changed(phase_id: StringName)

## El enemigo cayó. Se emite **exactamente una vez**.
signal defeated()

## Grupo que recorre `OffscreenMarkers` (`docs/12`).
const GROUP: StringName = &"enemies"

## Nombres fijos de los hijos del árbol de `docs/06` §2.
const MODEL_NODE: StringName = &"Model"
const PARTS_NODE: StringName = &"Parts"
const WEAK_POINTS_NODE: StringName = &"WeakPoints"
const LOCOMOTION_NODE: StringName = &"Locomotion"
const PERCEPTION_NODE: StringName = &"Perception"
const BRAIN_NODE: StringName = &"Brain"

## Estado de acción cuando no hay ninguna en curso (`docs/06` §11.1).
const ACTION_NONE: StringName = &"NONE"

## Frecuencia de evaluación de la exposición de puntos débiles, en Hz (`docs/06` §5).
const WEAK_POINT_HZ: float = 10.0

## Frecuencia de evaluación de fases, en Hz (`docs/06` §6.1).
const PHASE_HZ: float = 4.0

## Mallas de escombro que un enemigo puede registrar en el `RubbleField`
## (`docs/06` §4.1 punto 8).
const MAX_RUBBLE_MESHES: int = 2

## Tiempo de convergencia de la velocidad hacia la deseada, en segundos
## (`docs/06` §7 punto 2: la aceleración es `walk_speed / 0.8`).
const ACCELERATION_TIME: float = 0.8

## Ficha del enemigo: la única fuente de balance.
@export var profile: EnemyProfile = null

## Pool de escombros del nivel. Si queda vacío se resuelve con
## [method DebrisPool.resolve] (grupo `debris_pool` o uno nuevo).
@export var debris_pool: DebrisPool = null

## Campo de ruina donde se hornean los escombros. Si queda vacío se usa el del
## pool.
@export var rubble_field: RubbleField = null

## Raíz del GLB importado.
var model: Node3D = null

## Contenedor de las [EnemyPart].
var parts_root: Node = null

## Contenedor de los [WeakPoint].
var weak_points_root: Node = null

## Rig de patas (WP-17). Placeholder mientras tanto.
var locomotion: Node = null

## Percepción (WP-18). Placeholder mientras tanto.
var perception: Node = null

## Cerebro: selector y máquina de estados (WP-18). Placeholder mientras tanto.
var brain: Node = null

var _parts: Dictionary[StringName, EnemyPart] = {}
var _weak_points: Dictionary[StringName, WeakPoint] = {}
var _legs: Array[Dictionary] = []
var _phase_index: int = -1
var _phase_id: StringName = &""
var _unlocked_attacks: Dictionary[StringName, bool] = {}
var _phase_locked: Dictionary[StringName, bool] = {}
var _timed_locks: Dictionary[StringName, float] = {}
var _multipliers: Dictionary = {}
var _utility_weights: Dictionary = {}
var _music_stem: StringName = &""
var _structure_denominator: float = 0.0
var _defeated: bool = false
var _built: bool = false
var _action_state: StringName = ACTION_NONE
var _locomotion_state: StringName = &"IDLE"
var _stagger_left: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _elapsed: float = 0.0
var _weak_point_accumulator: float = 0.0
var _phase_accumulator: float = 0.0


func _ready() -> void:
	_resolve_nodes()
	if profile == null:
		push_error("EnemyBase '%s': falta el EnemyProfile." % name)
		Global.startup_errors.append("ERR_ENEMY_NO_PROFILE")
		return
	_resolve_debris_pool()
	_build_parts()
	_link_hierarchy()
	_build_weak_points()
	_build_legs()
	_register_rubble_meshes()
	_built = true

	if not is_in_group(GROUP):
		add_to_group(GROUP)
	Events.enemy_spawned.emit(self, profile.enemy_id)
	_refresh_weak_points()
	_evaluate_phases()


## Lleva los acumuladores del tambaleo, de los bloqueos de ataque, de la
## exposición (10 Hz) y de las fases (4 Hz). Nunca usa un [Timer].
func _physics_process(delta: float) -> void:
	if not _built:
		return
	_elapsed += delta
	if _stagger_left > 0.0:
		_stagger_left = maxf(0.0, _stagger_left - delta)
		if _stagger_left <= 0.0 and _locomotion_state == &"STAGGER":
			_locomotion_state = &"DOWNED" if is_downed() else &"IDLE"
	_tick_locks(delta)

	_weak_point_accumulator += delta
	var weak_step := 1.0 / WEAK_POINT_HZ
	while _weak_point_accumulator >= weak_step:
		_weak_point_accumulator -= weak_step
		_refresh_weak_points()

	_phase_accumulator += delta
	var phase_step := 1.0 / PHASE_HZ
	while _phase_accumulator >= phase_step:
		_phase_accumulator -= phase_step
		_evaluate_phases()


# --------------------------------------------------------------------------
# Interfaz pública (`docs/06` §14)
# --------------------------------------------------------------------------

## Parte [param part_id], o `null` si no existe.
func get_part(part_id: StringName) -> EnemyPart:
	return _parts.get(part_id, null) as EnemyPart


## Punto débil [param weak_point_id], o `null` si no existe.
func get_weak_point(weak_point_id: StringName) -> WeakPoint:
	return _weak_points.get(weak_point_id, null) as WeakPoint


## Todas las partes del grafo, en orden de construcción.
func get_parts() -> Array[EnemyPart]:
	var found: Array[EnemyPart] = []
	for part_id: StringName in _parts:
		found.append(_parts[part_id])
	return found


## Todos los puntos débiles.
func get_weak_points() -> Array[WeakPoint]:
	var found: Array[WeakPoint] = []
	for weak_point_id: StringName in _weak_points:
		found.append(_weak_points[weak_point_id])
	return found


## Partes cuya función canónica es [param function] (`leg`, `sensor`, `weapon`,
## `cosmetic` o `core`).
func get_parts_by_function(function: StringName) -> Array[EnemyPart]:
	var found: Array[EnemyPart] = []
	for part: EnemyPart in get_parts():
		if part.function == function:
			found.append(part)
	return found


## Partes que llevan el flag [param flag] del `parts.json`.
func get_parts_by_flag(flag: StringName) -> Array[EnemyPart]:
	var found: Array[EnemyPart] = []
	for part: EnemyPart in get_parts():
		if part.flags.has(String(flag)):
			found.append(part)
	return found


## Patas agrupadas para el rig (`docs/06` §2.1 punto 6). Cada entrada trae
## `index`, `side`, `root`, `segments`, `foot` y `parts`.
func get_legs() -> Array[Dictionary]:
	return _legs


## Patas perdidas: las que tienen algún segmento roto o desprendido.
func legs_lost() -> int:
	var lost := 0
	for leg: Dictionary in _legs:
		if _is_leg_lost(leg):
			lost += 1
	return lost


## `true` cuando se perdieron [member EnemyProfile.downed_legs_lost] patas. Es
## irreversible (`docs/06` §8.7).
func is_downed() -> bool:
	return profile != null and legs_lost() >= profile.downed_legs_lost


## Integridad estructural de 0 a 1 (`docs/06` §6).
##
## `Σ(hp_actual · structure_weight) / Σ(hp_max · structure_weight)`. El
## denominador se fija al construir el grafo, no al vuelo: si también se
## recalculara sobre las partes vivas, desprender una parte rota **subiría** la
## razón y los umbrales `structure_below` de las fases dejarían de tener sentido.
## Las partes desprendidas dejan de aportar al numerador.
func total_structure_ratio() -> float:
	if _structure_denominator <= 0.0:
		return 1.0
	var total := 0.0
	for part: EnemyPart in get_parts():
		if part.structure_weight <= 0.0 or part.is_detached():
			continue
		total += part.hp * part.structure_weight
	return clampf(total / _structure_denominator, 0.0, 1.0)


## Aplica [param amount] de daño a la parte [param part_id] y devuelve el daño
## efectivo. El multiplicador de punto débil ya viene aplicado por el arma
## (`docs/08` §2.7); acá sólo se descuenta el blindaje.
func apply_damage(part_id: StringName, amount: float, hit: Dictionary) -> float:
	var part := get_part(part_id)
	if part == null:
		return 0.0
	return part.take_damage(amount, hit)


## Mueve el cuerpo a mano (`docs/06` §7). El enemigo nunca lo empuja la física.
##
## Acelera hacia [param desired_velocity] a `walk_speed / 0.8` m/s², recorta el
## paso a [member EnemyProfile.max_step_per_tick] —la defensa contra el
## *tunneling* de Jolt— y anula el avance mientras está tambaleando o caído.
##
## Con [member Global.debug_freeze_ai] no mueve nada (`docs/11` §11): el enemigo
## se queda exactamente donde está y la velocidad interna queda como estaba, de
## modo que al soltar la bandera retoma la marcha sin un salto.
func move_body(delta: float, desired_velocity: Vector3) -> void:
	if profile == null or delta <= 0.0 or Global.debug_freeze_ai:
		return
	var target := desired_velocity
	if is_staggered() or is_downed() or is_locomotion_locked():
		target = Vector3.ZERO
	var acceleration := profile.walk_speed / ACCELERATION_TIME
	_velocity = _velocity.move_toward(target, acceleration * delta)
	var step := _velocity * delta
	var max_step := profile.max_step_per_tick
	if step.length() > max_step:
		step = step.normalized() * max_step
	global_position += step
	if not target.is_zero_approx():
		_locomotion_state = &"WALK"
	elif _locomotion_state == &"WALK":
		_locomotion_state = &"IDLE"


## Gira el cuerpo hacia [param target] a [member EnemyProfile.turn_rate] grados
## por segundo (`docs/06` §7 punto 4).
##
## El giro se compone **sobre la base**, girándola alrededor de la vertical del
## mundo, y el rumbo se lee del eje frontal, no de `rotation.y` (WP-24d). Con el
## cuerpo inclinado por el rig —y en una rampa de 20° lo está siempre— escribir
## `rotation.y` obliga a descomponer la base en ángulos de Euler y a recomponerla
## desde ellos en cada tick de física: la inclinación se repartía entre los tres
## ángulos y volvía alterada, de modo que el coloso cabeceaba en cada corrección
## de rumbo. Es la misma lectura de rumbo que usan
## [method ProceduralLegRig._heading_yaw] y el [AudioRig].
func face_toward(target: Vector3, delta: float) -> void:
	if profile == null or Global.debug_freeze_ai:
		return
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	var current := global_basis.orthonormalized()
	var forward := -current.z
	if absf(forward.x) < 0.000001 and absf(forward.z) < 0.000001:
		return
	var yaw := atan2(-forward.x, -forward.z)
	var desired := atan2(-to_target.x, -to_target.z)
	var difference := wrapf(desired - yaw, -PI, PI)
	var max_turn := deg_to_rad(profile.turn_rate) * delta
	global_basis = Basis(Vector3.UP, clampf(difference, -max_turn, max_turn)) * current


## Fuerza el tambaleo por [param seconds] (`docs/06` §7 punto 6).
func request_stagger(seconds: float, _source_part: StringName) -> void:
	if seconds <= 0.0 or is_downed():
		return
	_stagger_left = maxf(_stagger_left, seconds)
	_locomotion_state = &"STAGGER"
	_velocity = Vector3.ZERO


## Alias corto de [method request_stagger] sin parte de origen.
func stagger(seconds: float) -> void:
	request_stagger(seconds, &"")


## `true` mientras dura el tambaleo.
func is_staggered() -> bool:
	return _stagger_left > 0.0


## Segundos de tambaleo que quedan.
func stagger_remaining() -> float:
	return _stagger_left


## Fase actual (`p1_siege`…`p5_selfdestruct` en el Arachnodroid).
func current_phase() -> StringName:
	return _phase_id


## Índice de la fase actual, o `-1` si todavía no entró en ninguna.
func current_phase_index() -> int:
	return _phase_index


## Ataques desbloqueados y no bloqueados por la fase ni por partes rotas.
func unlocked_attacks() -> PackedStringArray:
	var available := PackedStringArray()
	for attack_id: StringName in _unlocked_attacks:
		if _phase_locked.has(attack_id) or _timed_locks.has(attack_id):
			continue
		if _attack_disabled_by_parts(attack_id):
			continue
		available.append(String(attack_id))
	available.sort()
	return available


## Multiplicador de fase de [param key] (`cooldown`, `windup`, `walk_speed`…).
func phase_multiplier(key: StringName) -> float:
	return float(_multipliers.get(key, _multipliers.get(String(key), 1.0)))


## Peso de utilidad que la fase le da a [param attack_id] (WP-18).
func utility_weight(attack_id: StringName) -> float:
	return float(_utility_weights.get(attack_id, _utility_weights.get(String(attack_id), 1.0)))


## Stem de música que pidió la fase actual (`docs/13`).
func music_stem() -> StringName:
	return _music_stem


## Estado de la capa de acción (`docs/06` §11.1). Lo delega en `Brain`.
func action_state() -> StringName:
	if brain != null and brain.has_method(&"action_state"):
		return brain.call(&"action_state") as StringName
	return _action_state


## Fija el estado de la capa de acción y reevalúa la exposición en el acto.
##
## Es el punto de entrada que usará el `EnemyFSM` de WP-18 y el que permite a
## `enemy_parts_check` simular una telegrafía sin que existan los ataques.
func set_action_state(state: StringName) -> void:
	_action_state = state
	if brain != null and brain.has_method(&"set_action_state"):
		brain.call(&"set_action_state", state)
	_refresh_weak_points()


## Estado de la capa de locomoción (`docs/06` §11.1).
##
## Lo delega en el rig de patas, que es quien sabe si está trepando, saltando o
## girando (WP-17). `DOWNED` se resuelve acá porque depende de las partes rotas,
## no de la marcha, y el placeholder de WP-16 no declara el método.
func locomotion_state() -> StringName:
	if is_downed():
		return &"DOWNED"
	if locomotion != null and locomotion.has_method(&"locomotion_state"):
		return locomotion.call(&"locomotion_state") as StringName
	return _locomotion_state


## `true` si la acción en curso bloquea la locomoción (`AttackProfile.lock_locomotion`).
func is_locomotion_locked() -> bool:
	if brain != null and brain.has_method(&"is_locomotion_locked"):
		return bool(brain.call(&"is_locomotion_locked"))
	return false


## Posición creída del objetivo, que alimenta el cono de los puntos débiles.
## La escribirá `Perception` en WP-18; los checks la escriben a mano.
func set_target_position(position: Vector3) -> void:
	_target_position = position
	_has_target = true
	_refresh_weak_points()


## Olvida el objetivo: el cono de exposición deja de cumplirse.
func clear_target() -> void:
	_has_target = false
	_refresh_weak_points()


## Última posición conocida del objetivo.
func target_position() -> Vector3:
	return _target_position


## `true` si hay una posición de objetivo vigente.
func has_target() -> bool:
	return _has_target


## Bloquea [param attack_ids] durante [param seconds]. Lo usa `on_destroy`.
func lock_attacks(attack_ids: PackedStringArray, seconds: float) -> void:
	for attack_id: String in attack_ids:
		_timed_locks[StringName(attack_id)] = maxf(_timed_locks.get(StringName(attack_id), 0.0),
				seconds)


## `true` si [param attack_id] está bloqueado temporalmente.
func is_attack_locked(attack_id: StringName) -> bool:
	return _timed_locks.has(attack_id) or _phase_locked.has(attack_id)


## `true` cuando el enemigo ya fue derrotado.
func is_defeated() -> bool:
	return _defeated


# --------------------------------------------------------------------------
# Construcción del grafo (`docs/06` §2.1)
# --------------------------------------------------------------------------

## Resuelve los hijos de nombre fijo del árbol de `docs/06` §2.
func _resolve_nodes() -> void:
	model = get_node_or_null(NodePath(String(MODEL_NODE))) as Node3D
	parts_root = get_node_or_null(NodePath(String(PARTS_NODE)))
	weak_points_root = get_node_or_null(NodePath(String(WEAK_POINTS_NODE)))
	locomotion = get_node_or_null(NodePath(String(LOCOMOTION_NODE)))
	perception = get_node_or_null(NodePath(String(PERCEPTION_NODE)))
	brain = get_node_or_null(NodePath(String(BRAIN_NODE)))
	if parts_root == null:
		parts_root = Node.new()
		parts_root.name = String(PARTS_NODE)
		add_child(parts_root)
	if weak_points_root == null:
		weak_points_root = Node.new()
		weak_points_root.name = String(WEAK_POINTS_NODE)
		add_child(weak_points_root)


## Deja [member debris_pool] y [member rubble_field] utilizables.
func _resolve_debris_pool() -> void:
	if debris_pool == null:
		debris_pool = DebrisPool.resolve(self)
	if debris_pool != null:
		if rubble_field == null:
			rubble_field = debris_pool.rubble_field
		elif debris_pool.rubble_field == null:
			debris_pool.rubble_field = rubble_field


## Paso 1 a 3: una [EnemyPart] por malla con metadato `part_id`, con su
## colisionador cableado y sus metadatos propagados.
func _build_parts() -> void:
	if model == null:
		push_error("EnemyBase '%s': falta el nodo 'Model'." % name)
		Global.startup_errors.append("ERR_ENEMY_NO_MODEL")
		return
	for node: Node in _descendants(model):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.has_meta(&"part_id"):
			continue
		var part_id := StringName(mesh_instance.get_meta(&"part_id"))
		if _parts.has(part_id):
			push_error("EnemyBase '%s': la parte '%s' está repetida." % [name, part_id])
			continue

		var part := EnemyPart.new()
		part.enemy = self
		part.debris_pool = debris_pool
		part.debris_lifetime = profile.debris_lifetime
		part.detach_speed = profile.detach_speed
		part.configure(mesh_instance, profile.override_for(part_id), profile.armor_default)
		if part.function == &"":
			Global.startup_errors.append("ERR_ENEMY_FUNCTION_UNKNOWN")
			push_error("EnemyBase '%s': función desconocida en '%s'." % [name, part_id])
			part.function = &"cosmetic"
		var part_body := _find_body(mesh_instance)
		if part_body == null:
			Global.startup_errors.append("ERR_ENEMY_PART_NO_BODY")
			push_error("EnemyBase '%s': '%s' no tiene AnimatableBody3D." % [name, part_id])
		part.bind_body(part_body)

		parts_root.add_child(part)
		_parts[part.part_id] = part
		_structure_denominator += part.max_hp * part.structure_weight
		var _discard := part.broken.connect(_on_part_broken)


## Paso 4: `parent_part` es el primer ancestro que también es una parte.
func _link_hierarchy() -> void:
	for part: EnemyPart in get_parts():
		var ancestor := part.mesh.get_parent()
		while ancestor != null:
			if ancestor.has_meta(&"part_id"):
				var parent_id := StringName(ancestor.get_meta(&"part_id"))
				part.parent_part = _parts.get(parent_id, null)
				break
			ancestor = ancestor.get_parent()
		if part.parent_part != null:
			part.parent_part.child_parts.append(part)


## Paso 5: un [WeakPoint] por `weak_point_id` declarado.
##
## Varias partes pueden referirse al mismo id (la tibia lo declara porque es la
## hospedadora y la malla `wp_*` porque es el blanco): la parte que recibe el
## daño es la que se llama igual que el punto débil.
func _build_weak_points() -> void:
	var groups: Dictionary[StringName, Array] = {}
	for part: EnemyPart in get_parts():
		if part.weak_point_id == &"":
			continue
		if not groups.has(part.weak_point_id):
			groups[part.weak_point_id] = []
		groups[part.weak_point_id].append(part)

	for weak_point_id: StringName in groups:
		var members := groups[weak_point_id] as Array
		var weak_part := members[0] as EnemyPart
		for candidate: EnemyPart in members:
			if candidate.part_id == weak_point_id:
				weak_part = candidate
				break
		var weak_profile := profile.weak_point_for(weak_point_id)
		if weak_profile == null:
			Global.startup_errors.append("ERR_ENEMY_WP_NO_PROFILE")
			push_error("EnemyBase '%s': '%s' no tiene WeakPointProfile; queda como parte normal." \
					% [name, weak_point_id])
			continue

		var host := _parts.get(weak_profile.host_part_id, null) as EnemyPart
		var weak_point := WeakPoint.new()
		weak_point.setup(weak_profile, weak_part, host, self)
		weak_points_root.add_child(weak_point)
		_weak_points[weak_point_id] = weak_point
		var _exposure := weak_point.exposure_changed.connect(_on_weak_point_exposure)
		var _destroyed := weak_point.destroyed.connect(_on_weak_point_destroyed)
	_recalculate_structure_denominator()


## Paso 6: agrupa las patas por su `leg_root` y se las pasa al rig.
func _build_legs() -> void:
	_legs.clear()
	var roots := get_parts_by_flag(&"leg_root")
	roots.sort_custom(func(a: EnemyPart, b: EnemyPart) -> bool:
		return String(a.part_id) < String(b.part_id))
	for root: EnemyPart in roots:
		var text := String(root.part_id)
		var cut := text.rfind("_")
		var prefix := text.substr(0, cut + 1) if cut > 0 else text
		var side := prefix.trim_prefix("leg_").trim_suffix("_").to_upper()

		# Todo lo que cuelga de la coxa pertenece a la pata, incluida la rodilla,
		# cuyo id lleva el prefijo `wp_`: sin ella `notify_leg_broken()` nunca se
		# dispararía, porque el punto débil es lo que el jugador rompe.
		var chain: Array[EnemyPart] = []
		var segments: Array[EnemyPart] = []
		var foot: EnemyPart = null
		for part: EnemyPart in root.descendants():
			chain.append(part)
			if part.flags.has("foot"):
				foot = part
			elif part.flags.has("leg_segment"):
				segments.append(part)
		segments.sort_custom(func(a: EnemyPart, b: EnemyPart) -> bool:
			return _depth_of(a) < _depth_of(b))

		if segments.size() < 2 or foot == null:
			Global.startup_errors.append("ERR_ENEMY_LEG_INCOMPLETE")
			push_error("EnemyBase '%s': la pata '%s' está incompleta (%d segmentos, pie %s)." \
					% [name, prefix, segments.size(), "sí" if foot != null else "no"])
			continue
		_legs.append({
			"index": _legs.size(),
			"side": StringName(side),
			"prefix": prefix,
			"root": root,
			"segments": segments,
			"foot": foot,
			"parts": chain,
		})

	if locomotion != null:
		# Inyección por `@export`, como manda `docs/06` §2: ningún nodo busca en
		# la raíz del árbol ni carga su propio recurso.
		if profile.leg_rig != null and &"profile" in locomotion:
			locomotion.set(&"profile", profile.leg_rig)
		if locomotion.has_method(&"setup"):
			locomotion.call(&"setup", _legs)
	if perception != null and profile.perception != null and &"profile" in perception:
		perception.set(&"profile", profile.perception)


## Paso 8 de `docs/06` §4.1: el enemigo registra hasta dos mallas de escombro en
## el [RubbleField], las de sus partes desprendibles más pesadas.
func _register_rubble_meshes() -> void:
	if rubble_field == null:
		return
	var detachables: Array[EnemyPart] = []
	for part: EnemyPart in get_parts():
		if part.detachable and part.mesh != null and part.mesh.mesh != null:
			detachables.append(part)
	detachables.sort_custom(func(a: EnemyPart, b: EnemyPart) -> bool:
		return a.effective_debris_mass() > b.effective_debris_mass())
	var registered := 0
	for part: EnemyPart in detachables:
		if registered >= MAX_RUBBLE_MESHES:
			break
		if rubble_field.index_of(part.mesh.mesh) >= 0:
			continue
		if rubble_field.register_mesh(part.mesh.mesh) < 0:
			break
		registered += 1


## El `WeakPointProfile` puede pisar el HP de su parte, así que el denominador de
## la integridad se recalcula cuando ya están todos los puntos débiles.
func _recalculate_structure_denominator() -> void:
	_structure_denominator = 0.0
	for part: EnemyPart in get_parts():
		_structure_denominator += part.max_hp * part.structure_weight


# --------------------------------------------------------------------------
# Puntos débiles y fases
# --------------------------------------------------------------------------

## Reevalúa la exposición de todos los puntos débiles con el contexto actual.
func _refresh_weak_points() -> void:
	if _weak_points.is_empty():
		return
	var ctx := _exposure_context()
	for weak_point: WeakPoint in get_weak_points():
		var _exposed := weak_point.evaluate(ctx)


## Contexto que consumen las condiciones de [WeakPoint] (`docs/06` §5).
func _exposure_context() -> Dictionary:
	var broken_ids: Dictionary[StringName, bool] = {}
	var structural_broken := 0
	for part: EnemyPart in get_parts():
		if not part.is_broken():
			continue
		broken_ids[part.part_id] = true
		if part.structure_weight > 0.0:
			structural_broken += 1
	return {
		"action_state": action_state(),
		"broken_ids": broken_ids,
		"structural_broken": structural_broken,
		"has_target": _has_target,
		"target_position": _target_position,
		"time": _elapsed,
	}


## Gana la fase de índice más alto que cumpla; nunca se retrocede (`docs/06` §6.1).
func _evaluate_phases() -> void:
	if profile == null or profile.phases.is_empty():
		return
	var best := -1
	for index: int in range(profile.phases.size() - 1, -1, -1):
		var phase := profile.phases[index]
		if _phase_matches(phase.get("when", {}) as Dictionary):
			best = index
			break
	if best <= _phase_index:
		return
	_enter_phase(best)


## Resuelve el bloque `when` de una fase. Sin criterios, la fase siempre cumple.
func _phase_matches(when: Dictionary) -> bool:
	if when.is_empty():
		return true
	var broken_ids := (_exposure_context()["broken_ids"] as Dictionary)
	var results: Array[bool] = []

	if when.has("parts_broken"):
		var all_broken := true
		for raw_id: String in to_string_array(when["parts_broken"]):
			all_broken = all_broken and broken_ids.has(StringName(raw_id))
		results.append(all_broken)

	if when.has("parts_broken_any_count"):
		var structural := 0
		for part: EnemyPart in get_parts():
			if part.is_broken() and part.structure_weight > 0.0:
				structural += 1
		results.append(structural >= int(when["parts_broken_any_count"]))

	if when.has("parts_broken_from"):
		var candidates := to_string_array(when["parts_broken_from"])
		var hits := 0
		for raw_id: String in candidates:
			if broken_ids.has(StringName(raw_id)):
				hits += 1
		var needed := int(when.get("parts_broken_from_count", 0))
		if needed <= 0:
			needed = candidates.size()
		results.append(hits >= needed)

	if when.has("structure_below"):
		results.append(total_structure_ratio() <= float(when["structure_below"]))

	if when.has("weak_points_broken"):
		var all_down := true
		for raw_id: String in to_string_array(when["weak_points_broken"]):
			var weak_point := get_weak_point(StringName(raw_id))
			all_down = all_down and weak_point != null and weak_point.is_broken()
		results.append(all_down)

	if results.is_empty():
		return true
	var require_all := bool(when.get("require_all", true))
	for result: bool in results:
		if require_all and not result:
			return false
		if not require_all and result:
			return true
	return require_all


## Entra en la fase [param index] y aplica su bloque `then`.
func _enter_phase(index: int) -> void:
	_phase_index = index
	var phase := profile.phases[index]
	_phase_id = StringName(phase.get("id", &""))
	var effects := phase.get("then", {}) as Dictionary

	# Los desbloqueos son acumulativos; los bloqueos pertenecen a la fase.
	for attack_id: String in to_string_array(effects.get("unlock_attacks", [])):
		_unlocked_attacks[StringName(attack_id)] = true
	_phase_locked.clear()
	for attack_id: String in to_string_array(effects.get("lock_attacks", [])):
		_phase_locked[StringName(attack_id)] = true
	_multipliers = effects.get("multipliers", {}) as Dictionary
	_utility_weights = effects.get("utility_weights", {}) as Dictionary
	_music_stem = StringName(effects.get("music_stem", &""))
	if effects.has("emissive_color"):
		_apply_phase_emissive(effects["emissive_color"] as Color)

	phase_changed.emit(_phase_id)
	Events.enemy_phase_changed.emit(self, _phase_id)
	if bool(effects.get("defeat", false)):
		declare_defeat()


## Recolorea los emisivos de carcasa: las partes con superficie emisiva que no
## son puntos débiles (`docs/06` §6.1).
func _apply_phase_emissive(color: Color) -> void:
	for part: EnemyPart in get_parts():
		if not part.has_emissive_surface or part.weak_point_id != &"":
			continue
		if part.mesh == null or part.mesh.mesh == null:
			continue
		var mesh_data := part.mesh.mesh
		for surface: int in mesh_data.get_surface_count():
			var source := mesh_data.surface_get_material(surface) as BaseMaterial3D
			if source == null or not source.emission_enabled:
				continue
			var current := part.mesh.get_surface_override_material(surface) as BaseMaterial3D
			if current == null:
				current = source.duplicate() as BaseMaterial3D
				part.mesh.set_surface_override_material(surface, current)
			current.emission = color


## Emite la derrota **una sola vez** (`docs/06` §6).
func declare_defeat() -> void:
	if _defeated:
		return
	_defeated = true
	defeated.emit()
	Events.enemy_defeated.emit(self, profile.enemy_id if profile != null else &"")


## Derrota por núcleos: caen todos los `core` que pesan en la estructura.
func _check_defeat() -> void:
	if _defeated:
		return
	var cores := 0
	var down := 0
	for part: EnemyPart in get_parts():
		if part.function != &"core" or part.structure_weight <= 0.0:
			continue
		cores += 1
		if part.is_broken():
			down += 1
	if cores > 0 and down == cores:
		declare_defeat()


# --------------------------------------------------------------------------
# Reacciones
# --------------------------------------------------------------------------

## Una parte cruzó 0: tambaleo, función deshabilitada, fases y exposición.
func _on_part_broken(part_id: StringName) -> void:
	var part := get_part(part_id)
	part_broken.emit(part_id)
	if part != null:
		request_stagger(profile.stagger_seconds, part_id)
		_disable_function(part)
	_refresh_weak_points()
	_evaluate_phases()
	_check_defeat()


## Efecto de romper una parte según su función (`docs/06` §4).
func _disable_function(part: EnemyPart) -> void:
	match part.function:
		&"leg":
			var index := _leg_index_of(part)
			if index >= 0 and locomotion != null \
					and locomotion.has_method(&"notify_leg_broken"):
				locomotion.call(&"notify_leg_broken", index)
		&"core":
			_check_defeat()
		_:
			pass


## Ejecuta el `on_destroy` declarativo del punto débil (`docs/06` §3).
func _on_weak_point_destroyed(weak_point_id: StringName) -> void:
	var weak_point := get_weak_point(weak_point_id)
	if weak_point == null or weak_point.profile == null:
		return
	var effects := weak_point.profile.on_destroy

	var detach_id := StringName(effects.get("detach_part", &""))
	if detach_id != &"":
		var target := get_part(detach_id)
		if target != null and not target.is_detached():
			target.detach(_detach_impulse_for(target))

	var blind_seconds := float(effects.get("blind_seconds", 0.0))
	if blind_seconds > 0.0 and perception != null and perception.has_method(&"blind"):
		perception.call(&"blind", blind_seconds)

	var locked := to_string_array(effects.get("lock_attacks", []))
	if not locked.is_empty():
		lock_attacks(locked, float(effects.get("lock_seconds", 0.0)))

	var stagger_seconds := float(effects.get("stagger_seconds", 0.0))
	if stagger_seconds > 0.0:
		request_stagger(stagger_seconds, weak_point_id)

	_refresh_weak_points()
	_evaluate_phases()
	_check_defeat()


## Impulso con el que sale una parte desprendida por `on_destroy`: radial hacia
## afuera y hacia arriba, escalado por la masa (`docs/06` §4.1 punto 5).
func _detach_impulse_for(part: EnemyPart) -> Vector3:
	var outward := part.world_position() - global_position
	outward.y = 0.0
	var direction := Vector3.UP
	if not outward.is_zero_approx():
		direction = (outward.normalized() + Vector3.UP * 0.5).normalized()
	return direction * part.effective_debris_mass() * profile.detach_speed


func _on_weak_point_exposure(weak_point_id: StringName, exposed: bool) -> void:
	weak_point_state_changed.emit(weak_point_id, exposed)


## Descuenta los bloqueos temporales de ataque.
func _tick_locks(delta: float) -> void:
	if _timed_locks.is_empty():
		return
	for attack_id: StringName in _timed_locks.keys():
		var left := _timed_locks[attack_id] - delta
		if left <= 0.0:
			var _erased := _timed_locks.erase(attack_id)
		else:
			_timed_locks[attack_id] = left


## `true` si algún `disabled_if_broken` del ataque está roto (`docs/06` §4).
func _attack_disabled_by_parts(attack_id: StringName) -> bool:
	if profile == null:
		return false
	for attack: AttackProfile in profile.attacks:
		if attack == null or attack.attack_id != attack_id:
			continue
		for raw_id: String in attack.disabled_if_broken:
			var part := get_part(StringName(raw_id))
			if part != null and (part.is_broken() or part.is_detached()):
				return true
		for raw_id: String in attack.requires_parts:
			var part := get_part(StringName(raw_id))
			if part == null or part.is_broken() or part.is_detached():
				return true
	return false


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Índice de la pata a la que pertenece [param part], o `-1`.
func _leg_index_of(part: EnemyPart) -> int:
	for leg: Dictionary in _legs:
		if (leg["parts"] as Array).has(part) or leg["root"] == part:
			return int(leg["index"])
	return -1


## Una pata está perdida si alguno de sus segmentos o su pie se rompió o se fue.
func _is_leg_lost(leg: Dictionary) -> bool:
	for part: EnemyPart in leg["segments"] as Array:
		if part.is_broken() or part.is_detached():
			return true
	var foot := leg["foot"] as EnemyPart
	return foot != null and (foot.is_broken() or foot.is_detached())


## Profundidad de una parte dentro del grafo, contada desde la raíz.
func _depth_of(part: EnemyPart) -> int:
	var depth := 0
	var current := part.parent_part
	while current != null:
		depth += 1
		current = current.parent_part
	return depth


## Normaliza a [PackedStringArray] una lista que el `.tres` pudo guardar como
## `Array` o como `PackedStringArray`. Los bloques `when`/`then` de las fases y
## los `on_destroy` son diccionarios sueltos: el tipo exacto depende de cómo se
## haya escrito el recurso, y acá se acepta cualquiera de los dos.
static func to_string_array(value: Variant) -> PackedStringArray:
	var found := PackedStringArray()
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		return value as PackedStringArray
	if typeof(value) == TYPE_ARRAY:
		for item: Variant in value as Array:
			found.append(String(item))
	return found


## Primer hijo directo `AnimatableBody3D` de una malla, o `null`.
func _find_body(mesh_instance: MeshInstance3D) -> AnimatableBody3D:
	for child: Node in mesh_instance.get_children():
		var body := child as AnimatableBody3D
		if body != null:
			return body
	return null


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
