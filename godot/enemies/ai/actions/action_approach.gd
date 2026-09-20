## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `approach` — desplazamiento hacia el objetivo elegido (`docs/06` §10 y §11).
##
## [b]No es un ataque[/b]: es locomoción, así que no telegrafía nada y entra
## directo en `ACTIVE` (`windup 0`, `lock_locomotion false`). Cada ventana activa
## es un tramo corto de marcha; al terminar, el selector vuelve a decidir, de
## modo que el coloso puede abandonar la caminata en cuanto aparezca algo mejor
## que hacer.
##
## [b]Elección del objetivo[/b] (`docs/07` §6 y §7): cada fase declara un sesgo
## ciudad/dron —70/30 en P1, 30/70 en P4, 100/0 en P5— que el perfil guarda como
## el multiplicador de fase `city_bias`. La comparación es determinista, no un
## sorteo: se enfrentan `city_bias` contra `(1 − city_bias) · confianza` y gana
## el mayor. Así el coloso no oscila entre la torre y el dron cuatro veces por
## segundo, y con el dron perdido de vista la ciudad gana siempre.
##
## [b]Puntuación[/b]: rampa lineal con la distancia al objetivo elegido, 0 a
## [constant ARRIVE_DISTANCE] y 1 a partir de [constant ENGAGE_DISTANCE]. Al
## llegar, el score cae a 0, el selector lo descarta y el coloso se planta.
class_name ActionApproach extends EnemyAction

## Distancia a la que se da por llegado, en metros. Con la huella de 21 × 27 m
## del Arachnodroid (`docs/07` §2), pararse a 20 m del centro de un edificio es
## tenerlo debajo de las patas delanteras.
const ARRIVE_DISTANCE: float = 20.0

## Distancia a partir de la cual acercarse vale 1.
const ENGAGE_DISTANCE: float = 90.0

## Confianza por debajo de la cual el dron no cuenta como objetivo perseguible.
const MIN_CONFIDENCE: float = 0.15

var _goal: Vector3 = Vector3.ZERO
var _chasing_drone: bool = false


## Alto si el objetivo está lejos, cero al llegar.
func score(ctx: Dictionary) -> float:
	var distance := _goal_distance(ctx)
	if distance >= 1.0e5:
		return 0.0
	return ActionScore.linear(distance, ARRIVE_DISTANCE, ENGAGE_DISTANCE)


## Caminar siempre es elegible mientras haya a dónde ir y el coloso pueda andar.
func can_run(ctx: Dictionary) -> bool:
	if not super.can_run(ctx):
		return false
	var host := owner_enemy()
	if host != null and (host.is_downed() or host.is_staggered()):
		return false
	return _goal_distance(ctx) < 1.0e5


## Fija el objetivo del tramo y lo publica si es el dron.
func _on_active_begin() -> void:
	var host := owner_enemy()
	if host == null:
		return
	var ctx := _context()
	_chasing_drone = _prefers_drone(ctx)
	_goal = _goal_point(ctx)
	if _chasing_drone:
		# `set_target_position` es lo que alimenta el cono de exposición del
		# núcleo ventral (`docs/06` §5): sólo tiene sentido con el dron, nunca
		# con un edificio.
		host.set_target_position(_goal)


## Un tramo de marcha: girar hacia el objetivo y avanzar lo que permita el rig.
func _on_active(delta: float) -> void:
	var host := owner_enemy()
	if host == null or delta <= 0.0:
		return
	var rig := host.locomotion as ProceduralLegRig
	if rig != null and rig.is_leaping():
		return

	var origin := host.global_position
	var to_goal := Vector3(_goal.x - origin.x, 0.0, _goal.z - origin.z)
	var distance := to_goal.length()
	if distance <= ARRIVE_DISTANCE or distance < 0.01:
		host.move_body(delta, Vector3.ZERO)
		return

	var direction := to_goal / distance
	host.face_toward(origin + direction * 100.0, delta)
	# Sólo se avanza en la medida en que el cuerpo ya encara el objetivo: si no,
	# el coloso patinaría de costado mientras gira a 25 °/s (`docs/06` §7).
	var facing := -host.global_basis.z
	facing.y = 0.0
	var alignment := 0.0
	if not facing.is_zero_approx():
		alignment = clampf(facing.normalized().dot(direction), 0.0, 1.0)
	var speed := host.profile.walk_speed * host.phase_multiplier(&"walk_speed") * alignment
	if rig != null:
		speed *= rig.speed_multiplier()
	host.move_body(delta, direction * speed)


## Al cortarse la marcha, el cuerpo frena: no hay inercia que arrastrar.
func _on_interrupt() -> void:
	var host := owner_enemy()
	if host == null:
		return
	host.move_body(host.get_physics_process_delta_time(), Vector3.ZERO)


## Objetivo elegido ahora mismo, en coordenadas de mundo.
func goal() -> Vector3:
	return _goal


## `true` si el tramo en curso persigue al dron en vez de a la ciudad.
func is_chasing_drone() -> bool:
	return _chasing_drone


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## Contexto de la última decisión del cerebro, o uno recién armado.
func _context() -> Dictionary:
	var host := owner_enemy()
	if host == null or host.brain == null:
		return {}
	if host.brain.has_method(&"last_context"):
		var stored := host.brain.call(&"last_context") as Dictionary
		if not stored.is_empty():
			return stored
	if host.brain.has_method(&"build_context"):
		return host.brain.call(&"build_context") as Dictionary
	return {}


## `true` si la fase y la confianza hacen que el dron gane sobre la ciudad.
##
## Un destino forzado por el enemigo —la carrera de la autodestrucción del
## Arachnodroid (`docs/07` §6, P5)— gana sobre los dos: en P5 no hay nada que
## elegir, sólo un reloj y un sitio al que llegar.
func _prefers_drone(ctx: Dictionary) -> bool:
	if bool(ctx.get(&"has_march_goal", false)):
		return false
	var has_drone := bool(ctx.get(&"has_drone_target", false))
	var has_city := bool(ctx.get(&"has_city_target", false))
	if not has_drone:
		return false
	if not has_city:
		return true
	var confidence := float(ctx.get(&"confidence", 0.0))
	if confidence < MIN_CONFIDENCE:
		return false
	var city_bias := clampf(float(ctx.get(&"city_bias", 1.0)), 0.0, 1.0)
	return (1.0 - city_bias) * confidence > city_bias


## Punto al que caminar según la preferencia de la fase.
func _goal_point(ctx: Dictionary) -> Vector3:
	if bool(ctx.get(&"has_march_goal", false)):
		return ctx.get(&"march_goal", Vector3.ZERO) as Vector3
	if _prefers_drone(ctx):
		return ctx.get(&"believed_position", Vector3.ZERO) as Vector3
	if bool(ctx.get(&"has_city_target", false)):
		return ctx.get(&"city_position", Vector3.ZERO) as Vector3
	return ctx.get(&"believed_position", Vector3.ZERO) as Vector3


## Distancia horizontal al objetivo elegido, o un valor enorme si no hay ninguno.
func _goal_distance(ctx: Dictionary) -> float:
	if ctx.is_empty():
		return 1.0e6
	if bool(ctx.get(&"has_march_goal", false)):
		var goal := ctx.get(&"march_goal", Vector3.ZERO) as Vector3
		var origin := ctx.get(&"position", Vector3.ZERO) as Vector3
		return Vector2(goal.x - origin.x, goal.z - origin.z).length()
	if _prefers_drone(ctx):
		return float(ctx.get(&"distance", 1.0e6))
	if bool(ctx.get(&"has_city_target", false)):
		return float(ctx.get(&"city_distance", 1.0e6))
	if bool(ctx.get(&"has_drone_target", false)):
		return float(ctx.get(&"distance", 1.0e6))
	return 1.0e6
