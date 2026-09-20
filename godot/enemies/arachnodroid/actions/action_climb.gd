## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `climb` — ganar altura y aplastar (`docs/07` §5.3).
##
## [b]Telegrafía 0.6 s[/b] —que el piso absoluto de `docs/06` §6.1 sube a 0.80 s,
## como cualquier acción dañina—: los anillos de hombro en ámbar y la tensión de
## servos, más el canal de postura del cuerpo cabeceando hacia arriba.
##
## [b]Activo 2–4 s[/b]: el jefe camina [b]contra[/b] el edificio elegido. No hay
## una máquina de trepado aparte y no hace falta: el rayo de apoyo del
## [ProceduralLegRig] ya lleva la máscara `world | city` (`docs/06` §8.4), así
## que en cuanto un pie encuentra el techo por encima del `step_trigger`, se
## apoya arriba y el rig reporta `CLIMB` solo. Esta acción es [b]la decisión[/b]
## de subir, no la mecánica.
##
## [b]Daño[/b]: 1 500 por apoyo sobre el edificio, resueltos con el
## `intersect_ray` del pie que pide `docs/07` §5.1 —no con un `intersect_shape`:
## acá el volumen es el pie y el rayo ya sabe dónde cayó—. El
## `crush_damage` 900 de la marcha (`docs/06` §8.4) lo cobra el rig aparte y por
## su cuenta: son dos cosas distintas, pisar y treparse encima.
##
## [b]Contramedida[/b]: romper la rodilla de una pata trepadora, que hace caer al
## jefe. Eso lo resuelve el `on_destroy` del punto débil (`docs/07` §4) con su
## `stagger`, que además cancela esta acción por la vía normal del [EnemyFSM].
class_name ActionClimb extends SweepAction

## Media longitud del rayo que confirma sobre qué se apoyó el pie, en metros.
const FOOT_PROBE: float = 4.0

## Distancia a la que se deja de empujar contra el edificio, en metros. Es corta
## a propósito: pararse a 12 m de una torre de 18 m de lado deja los reposos de
## las patas fuera de la huella y el rayo de apoyo no encuentra nunca el techo.
const ARRIVE_DISTANCE: float = 4.0

## Tiempo sin dañar la ciudad a partir del cual trepar vale 1, en segundos.
const PRESSURE_WINDOW: float = 20.0

## Altura mínima del edificio para que valga la pena subirse, en metros.
const MIN_HEIGHT: float = 10.0

## Altura a la que trepar vale 1, en metros.
const HEIGHT_REFERENCE: float = 26.0

var _target: Node3D = null
var _supports: int = 0
var _damage: float = 0.0
var _connected: bool = false


## Presión sobre la ciudad, sesgada por la altura del edificio elegido: subirse a
## una torre vale más que a un bloque bajo (`docs/07` §5.3 y §9).
func score(ctx: Dictionary) -> float:
	if profile == null or not locomotion_ready():
		return 0.0
	if not bool(ctx.get(&"has_city_target", false)):
		return 0.0
	var building := ctx.get(&"city_target", null) as Node3D
	var height := _height_of(building)
	if height < MIN_HEIGHT:
		return 0.0
	var tall := clampf(height / HEIGHT_REFERENCE, 0.0, 1.0)
	var idle := clampf(float(ctx.get(&"time_since_city_attack", 0.0)) / PRESSURE_WINDOW,
			0.0, 1.0)
	var bias := clampf(float(ctx.get(&"city_bias", 1.0)), 0.0, 1.0)
	return ActionScore.clamp01(lerpf(0.25, 1.0, idle) * tall * bias)


# --------------------------------------------------------------------------
# Coreografía
# --------------------------------------------------------------------------

## Elige el edificio y encara. El aviso es sólo luz, audio y postura: no hay zona
## de suelo que marcar, porque el daño lo recibe el edificio, no el jugador.
func _on_telegraph() -> void:
	_target = context().get(&"city_target", null) as Node3D
	_supports = 0
	_damage = 0.0


func _on_telegraph_tick(delta: float) -> void:
	var host := owner_enemy()
	if host == null or _target == null or not is_instance_valid(_target):
		return
	host.face_toward(_target.global_position, delta)


## Se engancha a los apoyos del rig: cada pie que caiga sobre capa 8 cobra.
func _on_active_begin() -> void:
	open_window()
	_supports = 0
	_damage = 0.0
	var leg_rig := rig()
	if leg_rig == null:
		return
	# La mecánica la pone el rig, pero la **intención** es de esta acción: con
	# ella encendida el rayo de apoyo prefiere el techo del edificio entre los
	# candidatos que prueba. Sin esto, con la huella de 22 m de WP-24d los
	# reposos de las patas delanteras caen fuera de una torre de 18 m de lado y
	# el jefe la rodearía en vez de subírsele encima.
	leg_rig.set_climb_intent(true)
	if not leg_rig.foot_planted.is_connected(_on_foot_planted):
		var _discard := leg_rig.foot_planted.connect(_on_foot_planted)
		_connected = true


## Camina contra el edificio: el rig hace el resto.
func _on_active(delta: float) -> void:
	var host := owner_enemy()
	if host == null or delta <= 0.0 or _target == null or not is_instance_valid(_target):
		return
	var leg_rig := rig()
	if leg_rig != null and leg_rig.is_leaping():
		return
	var origin := host.global_position
	var goal := _target.global_position
	var to_goal := Vector3(goal.x - origin.x, 0.0, goal.z - origin.z)
	var distance := to_goal.length()
	if distance < 0.01:
		return
	var direction := to_goal / distance
	host.face_toward(origin + direction * 100.0, delta)
	if distance <= ARRIVE_DISTANCE or _supports > 0:
		# Ya está encima —o ya apoyó un pie en el techo—: quedarse quieto deja
		# que el resto de los pies suban en vez de empujar la fachada.
		host.move_body(delta, Vector3.ZERO)
		return
	var facing := -host.global_basis.z
	facing.y = 0.0
	var alignment := 0.0
	if not facing.is_zero_approx():
		alignment = clampf(facing.normalized().dot(direction), 0.0, 1.0)
	var speed := host.profile.walk_speed * host.phase_multiplier(&"walk_speed") * alignment
	if leg_rig != null:
		speed *= leg_rig.speed_multiplier()
	host.move_body(delta, direction * speed)


func _on_active_end() -> void:
	_disconnect()


func _on_interrupt() -> void:
	super._on_interrupt()
	_disconnect()


func _exit_tree() -> void:
	_disconnect()


## Apoyos sobre el edificio en la última trepada.
func supports() -> int:
	return _supports


## Daño repartido en la última trepada.
func climb_damage() -> float:
	return _damage


## Edificio que se está trepando, o `null`.
func target_building() -> Node3D:
	return _target


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## Un pie tocó el suelo: si fue sobre capa 8, cobra `damage_building`.
##
## El rayo va hacia abajo desde un poco más arriba del apoyo, con la máscara
## `world | city` que pide `docs/07` §5.1. Si el collider no está en la capa 8,
## el apoyo fue en la calle y no cuenta.
func _on_foot_planted(_leg_index: int, position: Vector3, _impact_speed: float) -> void:
	if profile == null or profile.damage_building <= 0.0:
		return
	var space := space_state()
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * FOOT_PROBE,
			position - Vector3.UP * FOOT_PROBE, PhysicsLayers.QUERY_FOOT)
	query.collide_with_areas = false
	query.exclude = self_exclusions()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit.get("collider", null) as CollisionObject3D
	if collider == null or collider.collision_layer & PhysicsLayers.CITY == 0:
		return
	var building := find_building(collider)
	if building == null:
		return
	var _applied: Variant = building.call(&"take_damage", profile.damage_building, position)
	_supports += 1
	_damage += profile.damage_building
	notify_city_attack()


## Suelta la conexión con el rig y la intención de trepar. Es idempotente.
func _disconnect() -> void:
	var leg_rig := rig()
	if leg_rig != null:
		leg_rig.set_climb_intent(false)
	if not _connected:
		return
	_connected = false
	if leg_rig != null and leg_rig.foot_planted.is_connected(_on_foot_planted):
		leg_rig.foot_planted.disconnect(_on_foot_planted)


## Altura del edificio, o 0 si el nodo no la declara.
func _height_of(building: Node3D) -> float:
	if building == null or not is_instance_valid(building):
		return 0.0
	if building.has_method(&"get_height"):
		return float(building.call(&"get_height"))
	return 0.0
