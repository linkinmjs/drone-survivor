## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-17: mide la marcha procedural del Arachnodroid (`docs/06` §16.2).
##
## Levanta un mundo sintético —llano, rampa de 20° de 120 m, tres escalones de
## 4 m, una roca de 12 × 10 × 12 m y un edificio de prueba en capa 8— y hace
## caminar al jefe 120 s simulados por una ronda de puntos de paso que cruza los
## cinco terrenos. Mientras camina mide, tick a tick:
##
## | # | Métrica | Umbral |
## |---|---|---|
## | 1 | Deslizamiento de un pie apoyado | < 0.25 m por paso |
## | 2 | Pie flotando > 0.30 m sobre su apoyo | nunca > 0.20 s seguidos |
## | 3 | Pares diagonales en el aire a la vez | 0 ocurrencias |
## | 4 | Inclinación del cuerpo en la rampa de 20° | entre 8° y 16° |
## | 5 | Altura de la cadera en llano | `hip_height` ± 1 m |
## | 6 | Estabilidad numérica | 0 `NaN` / `INF` en 120 s |
## | 7 | Paso de `move_body` | ≤ `max_step_per_tick` |
## | 8 | Coste de `rig_tick` | < 0.25 ms de media |
##
## Y además, con guion: rompe una rodilla en marcha (trípode, ≥ 60 % de la
## velocidad), rompe otra (arrastre ×0.55), salta sobre la roca (cuatro pies
## apoyados en < 4 s), comprueba que pisar el edificio le cobra `crush_damage`
## y cierra con una **prueba negativa** —`step_trigger` a 30 m y `reach_trigger`
## desarmado— que debe hacer saltar por los aires las métricas 1 y 2.
##
## Las métricas 1 y 2 se exigen con **cuatro patas y con tres**; con dos se
## miden y se imprimen, pero no se exigen: en `DRAG` el cuerpo se arrastra con
## una sola pata en el aire por vez y el pie apoyado no puede seguirle el paso
## por definición. Es el modo que `docs/06` §8.3 llama, justamente, arrastre.
##
## El mundo lo arma este script, no la escena: así los tamaños salen de las
## constantes de acá y no hay que editar un `.tscn` para mover un escalón.
extends CheckRunner

## Escena del jefe.
const ENEMY_SCENE: String = "res://enemies/arachnodroid/arachnodroid.tscn"

## Segundos simulados de marcha continua (`docs/06` §16.2: 120 s totales).
const WALK_SECONDS: float = 120.0

## Aceleración de la simulación. El tope lo fija WP-17 en 4×.
const TIME_SCALE: float = 4.0

## Deslizamiento máximo de un pie apoyado, en metros.
const MAX_SLIDE: float = 0.25

## Altura a partir de la cual un pie apoyado se considera flotando, en metros.
const FLOAT_HEIGHT: float = 0.30

## Tiempo máximo que se tolera un pie flotando, en segundos.
const MAX_FLOAT_TIME: float = 0.20

## Banda de inclinación válida del cuerpo sobre la rampa de 20°, en grados.
const RAMP_TILT_MIN: float = 8.0
const RAMP_TILT_MAX: float = 16.0

## Tolerancia de la altura de cadera en llano, en metros.
const HEIGHT_TOLERANCE: float = 1.0

## Presupuesto de `rig_tick`, en microsegundos (`docs/06` §15).
const MAX_RIG_USEC: float = 250.0

## Velocidad mínima con tres patas, como fracción de `walk_speed`.
const TRIPOD_SPEED_RATIO: float = 0.60

## Segundos que se le dan al salto para dejar los cuatro pies en el suelo.
const LEAP_BUDGET: float = 4.0

## Pendiente de la rampa, en grados, y su largo en metros.
const RAMP_ANGLE: float = 20.0
const RAMP_LENGTH: float = 120.0
const RAMP_START_X: float = 60.0
const RAMP_WIDTH: float = 80.0
const RAMP_THICKNESS: float = 8.0

## Escalones: tres de 4 m, hacia −X.
const STEP_RISE: float = 4.0
const STEP_DEPTH: float = 30.0
const STEP_FIRST_X: float = -40.0

## Roca del salto: caja de 12 × 10 × 12 m en capa 1.
const ROCK_SIZE: Vector3 = Vector3(12.0, 10.0, 12.0)
const ROCK_CENTER: Vector3 = Vector3(0.0, 5.0, -70.0)

## Edificio de prueba en capa 8, con el techo a 8 m.
const BUILDING_SIZE: Vector3 = Vector3(26.0, 8.0, 26.0)
const BUILDING_CENTER: Vector3 = Vector3(0.0, 4.0, 70.0)

## Ventana de la rampa en la que se mide la inclinación: con el cuerpo acá, las
## cuatro patas pisan la pendiente.
const RAMP_SAMPLE_MIN: float = 80.0
const RAMP_SAMPLE_MAX: float = 150.0

## Radio en torno al origen que se considera llano para medir la altura.
const FLAT_RADIUS: float = 35.0

## Puntos de paso de la ronda, en XZ. Cruzan rampa, escalones y edificio.
const WAYPOINTS: Array[Vector2] = [
	Vector2(40.0, 0.0),
	Vector2(150.0, 0.0),
	Vector2(40.0, 0.0),
	Vector2(-30.0, 0.0),
	Vector2(-120.0, 0.0),
	Vector2(-30.0, 0.0),
	Vector2(0.0, 62.0),
	Vector2(0.0, 0.0),
]

## Distancia a la que se da por alcanzado un punto de paso.
const WAYPOINT_RADIUS: float = 8.0

## Segundo simulado en el que se rompe cada rodilla.
const FIRST_BREAK: float = 86.0
const SECOND_BREAK: float = 104.0

## Rodillas que se rompen, en orden.
const BREAK_KNEES: Array[StringName] = [&"wp_leg_fl_knee", &"wp_leg_bl_knee"]

## `step_trigger` absurdo de la prueba negativa, en metros.
const NEGATIVE_TRIGGER: float = 30.0

## Segundos simulados de la prueba negativa.
const NEGATIVE_SECONDS: float = 14.0


## Edificio de prueba: un `StaticBody3D` de capa `city` que apunta cada
## aplastamiento. No hereda de `Building` (`docs/10`) a propósito: el rig lo
## resuelve por *duck typing*, y el check tiene que demostrar justamente eso.
class TestBuilding extends StaticBody3D:
	var hits: int = 0
	var total: float = 0.0
	var last_point: Vector3 = Vector3.ZERO

	func take_damage(amount: float, point: Vector3) -> void:
		hits += 1
		total += amount
		last_point = point


## Acumulador de métricas de una corrida de marcha.
class Metrics extends RefCounted:
	var max_slide: float = 0.0
	var max_float: float = 0.0
	var max_float_time: float = 0.0
	var min_planted: int = 99
	var pair_violations: int = 0
	var nan_ticks: int = 0
	var max_body_step: float = 0.0
	var ramp_tilt_sum: float = 0.0
	var ramp_tilt_count: int = 0
	var flat_height_sum: float = 0.0
	var flat_height_count: int = 0
	var slide_offender: StringName = &""
	var float_offender: StringName = &""

	func ramp_tilt() -> float:
		return ramp_tilt_sum / float(maxi(ramp_tilt_count, 1))

	func flat_height() -> float:
		return flat_height_sum / float(maxi(flat_height_count, 1))


var _enemy: EnemyBase = null
var _rig: ProceduralLegRig = null
var _building: TestBuilding = null
var _world: Node3D = null
var _metrics: Metrics = Metrics.new()
var _tripod: Metrics = Metrics.new()
var _drag: Metrics = Metrics.new()
var _anchors: Dictionary[int, Vector3] = {}
var _float_time: Dictionary[int, float] = {}
var _waypoint: int = 0
var _last_body: Vector3 = Vector3.ZERO
var _speed_sum: float = 0.0
var _speed_ticks: int = 0
var _broken: int = 0
var _tripod_speed: float = 0.0
var _slide_logged: bool = false
var _float_logged: bool = false


func _run() -> void:
	_build_world()
	await wait_physics(2)

	_enemy = _spawn(Vector3.ZERO)
	if _enemy == null:
		return
	await wait_physics(4)
	if not _check_rig():
		return
	_check_rest_pose()

	# El salto va primero, con el jefe entero: después de la marcha le faltan dos
	# patas y `planted_count() == 4` dejaría de tener sentido.
	Engine.time_scale = TIME_SCALE
	var delta := _enemy.get_physics_process_delta_time()
	print("  simulación: time_scale %.1f, delta de física %.4f s" % [Engine.time_scale, delta])
	await _check_leap()

	_enemy.global_position = Vector3.ZERO
	_rig.snap_to_ground()
	await wait_physics(20)
	await _walk(WALK_SECONDS, true)
	Engine.time_scale = 1.0

	_report_walk()
	_check_building()
	await _check_negative()


# --------------------------------------------------------------------------
# Mundo sintético
# --------------------------------------------------------------------------

## Arma llano, rampa, escalones, roca y edificio de prueba.
func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	_add_box("Ground", Vector3(1400.0, 8.0, 1400.0), Vector3(0.0, -4.0, 0.0),
			Basis.IDENTITY, PhysicsLayers.WORLD)

	# Rampa de 20°: el centro se corre media altura por la normal para que la
	# cara superior arranque justo en (RAMP_START_X, 0) y suba hacia +X.
	var angle := deg_to_rad(RAMP_ANGLE)
	var slope := Vector3(cos(angle), sin(angle), 0.0)
	var normal := Vector3(-sin(angle), cos(angle), 0.0)
	var surface_mid := Vector3(RAMP_START_X, 0.0, 0.0) + slope * (RAMP_LENGTH * 0.5)
	_add_box("Ramp", Vector3(RAMP_LENGTH, RAMP_THICKNESS, RAMP_WIDTH),
			surface_mid - normal * (RAMP_THICKNESS * 0.5),
			Basis(Vector3.BACK, angle), PhysicsLayers.WORLD)

	# Tres escalones de 4 m hacia −X, cada uno más alto que el anterior.
	for index: int in 3:
		var top := STEP_RISE * float(index + 1)
		var center_x := STEP_FIRST_X - STEP_DEPTH * (float(index) + 0.5)
		_add_box("Step%d" % index, Vector3(STEP_DEPTH, top * 2.0, RAMP_WIDTH),
				Vector3(center_x, 0.0, 0.0), Basis.IDENTITY, PhysicsLayers.WORLD)

	_add_box("Rock", ROCK_SIZE, ROCK_CENTER, Basis.IDENTITY, PhysicsLayers.WORLD)

	_building = TestBuilding.new()
	_building.name = "TestBuilding"
	_building.collision_layer = PhysicsLayers.CITY
	_building.collision_mask = 0
	_building.position = BUILDING_CENTER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BUILDING_SIZE
	shape.shape = box
	_building.add_child(shape)
	_world.add_child(_building)


## Un `StaticBody3D` con una caja, en la capa [param layer].
func _add_box(node_name: String, size: Vector3, origin: Vector3, basis: Basis,
		layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.transform = Transform3D(basis, origin)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	return body


## Instancia el jefe con la cadera ya a `hip_height` sobre [param ground].
func _spawn(ground: Vector3) -> EnemyBase:
	var scene := load(ENEMY_SCENE) as PackedScene
	if scene == null:
		fail("no se pudo cargar %s" % ENEMY_SCENE)
		return null
	var enemy := scene.instantiate() as EnemyBase
	if enemy == null:
		fail("la escena del jefe no es un EnemyBase")
		return null
	add_child(enemy)
	enemy.global_position = ground
	return enemy


## Cablea el rig y comprueba que es el de verdad, no el placeholder.
func _check_rig() -> bool:
	_rig = _enemy.locomotion as ProceduralLegRig
	if _rig == null:
		fail("el nodo Locomotion no es un ProceduralLegRig")
		return false
	if _rig.legs.size() != 4:
		fail("el rig midió %d patas, esperadas 4" % _rig.legs.size())
		return false
	if _rig.profile == null:
		fail("el rig no recibió el LegRigProfile del EnemyProfile")
		return false
	return true


# --------------------------------------------------------------------------
# Pose de reposo
# --------------------------------------------------------------------------

## Comprueba la pose de arranque: cuatro pies en el suelo, cadera a
## `hip_height`, trote y cadena sin estirar.
func _check_rest_pose() -> void:
	var hip := _hip_height()
	expect_near(hip, _enemy.profile.hip_height, HEIGHT_TOLERANCE,
			"altura de cadera en reposo")
	expect(_rig.planted_count() == 4,
			"patas apoyadas en reposo: %d, esperadas 4" % _rig.planted_count())
	expect(_rig.gait_name() == &"TROT",
			"marcha en reposo '%s', esperada 'TROT'" % _rig.gait_name())
	expect_near(_rig.speed_multiplier(), 1.0, 0.001, "speed_multiplier() con 4 patas")

	var stretched := 0
	var knee_sum := 0.0
	for leg: Leg in _rig.legs:
		if leg.stretched:
			stretched += 1
		knee_sum += leg.tibia.global_position.y
	expect(stretched == 0, "%d patas nacen estiradas: la pose de marcha no alcanza" % stretched)
	print("  pose de marcha: cadera %.2f m · rodilla %.2f m · planta %.2f m · fémur %.3f m · tibia %.3f m"
			% [hip, knee_sum / 4.0, _rig.legs[0].sole_position().y,
			_rig.legs[0].femur_length, _rig.legs[0].tibia_length])


## Altura de la cadera (media de los pivotes de fémur) sobre la media de los
## pies apoyados. Es lo que `docs/07` §2 llama `hip_height`.
func _hip_height() -> float:
	var hips := 0.0
	var soles := 0.0
	var count := 0
	var planted := 0
	for leg: Leg in _rig.legs:
		if leg.broken:
			continue
		hips += leg.hip_world().y
		count += 1
		if leg.supports():
			soles += leg.plant_position.y
			planted += 1
	if count == 0 or planted == 0:
		return 0.0
	return hips / float(count) - soles / float(planted)


# --------------------------------------------------------------------------
# Marcha
# --------------------------------------------------------------------------

## Camina [param seconds] simulados siguiendo los puntos de paso, muestreando
## todas las métricas. Con [param scripted] rompe las dos rodillas del guion.
func _walk(seconds: float, scripted: bool) -> void:
	var elapsed := 0.0
	_last_body = _enemy.global_position
	_rig.reset_metrics()
	while elapsed < seconds:
		await get_tree().physics_frame
		var delta := _enemy.get_physics_process_delta_time()
		elapsed += delta
		_sample(delta)
		if scripted:
			_script_breaks(elapsed)
		_drive(delta)


## Manda la velocidad deseada hacia el punto de paso y gira el cuerpo. Es lo
## que hará el cerebro de WP-18; acá va escrito a mano para no depender de él.
func _drive(delta: float) -> void:
	if _rig.is_leaping():
		return
	var position := _enemy.global_position
	var goal := WAYPOINTS[_waypoint]
	var to_goal := Vector3(goal.x - position.x, 0.0, goal.y - position.z)
	if to_goal.length() < WAYPOINT_RADIUS:
		_waypoint = (_waypoint + 1) % WAYPOINTS.size()
		goal = WAYPOINTS[_waypoint]
		to_goal = Vector3(goal.x - position.x, 0.0, goal.y - position.z)
	var direction := to_goal.normalized()
	_enemy.face_toward(position + direction * 100.0, delta)
	# Sólo se avanza en la medida en que el cuerpo ya encara el objetivo: así el
	# coloso no patina de costado mientras gira a 25°/s.
	var facing := -_enemy.global_basis.z
	facing.y = 0.0
	var alignment := clampf(facing.normalized().dot(direction), 0.0, 1.0)
	var speed := _enemy.profile.walk_speed * _rig.speed_multiplier() * alignment
	_enemy.move_body(delta, direction * speed)


## Rompe las rodillas del guion en el segundo simulado que toca.
func _script_breaks(elapsed: float) -> void:
	if _broken == 0 and elapsed >= FIRST_BREAK:
		_break_knee(BREAK_KNEES[0])
	elif _broken == 1 and elapsed >= SECOND_BREAK:
		_break_knee(BREAK_KNEES[1])


## Rompe una rodilla como lo haría el arma (`docs/08` §2.7) y anota el estado.
func _break_knee(knee_id: StringName) -> void:
	var knee := _enemy.get_part(knee_id)
	if knee == null:
		fail("no existe la parte '%s'" % knee_id)
		_broken += 1
		return
	var _effective := knee.take_damage(knee.hp / maxf(1.0 - knee.armor, 0.01), {
		"position": knee.world_position(),
		"normal": Vector3.UP,
		"direction": Vector3.FORWARD,
		"source": self,
		"is_weak_point": true,
		"weak_point_id": knee_id,
		"damage_type": &"kinetic",
	})
	_broken += 1
	if _broken == 2:
		# La media acumulada desde la primera rotura es la velocidad con tres
		# patas (`docs/06` §16.2 y §8.7: ≥ 60 % de `walk_speed`).
		_tripod_speed = _speed_sum / float(maxi(_speed_ticks, 1))
		expect_near(_rig.speed_multiplier(), _rig.profile.drag_speed_factor, 0.001,
				"speed_multiplier() al perder la segunda pata")
	elif _broken == 1:
		expect_near(_rig.speed_multiplier(),
				1.0 - _enemy.profile.leg_speed_penalty, 0.001,
				"speed_multiplier() al perder la primera pata")
		expect(_rig.gait_name() == &"TRIPOD",
				"marcha con tres patas '%s', esperada 'TRIPOD'" % _rig.gait_name())
	_speed_sum = 0.0
	_speed_ticks = 0
	print("  rodilla '%s' rota: marcha '%s', speed_multiplier %.2f, patas apoyadas %d"
			% [knee_id, _rig.gait_name(), _rig.speed_multiplier(), _rig.planted_count()])


## Toma todas las medidas de un tick.
func _sample(delta: float) -> void:
	var body := _enemy.global_position
	var step := Vector3(body.x - _last_body.x, 0.0, body.z - _last_body.z).length()
	if not _rig.is_leaping():
		_metrics.max_body_step = maxf(_metrics.max_body_step, step)
		_speed_sum += step / delta
		_speed_ticks += 1
	_last_body = body

	if not _is_finite(body) or not _is_finite(_enemy.global_basis.get_euler()):
		_metrics.nan_ticks += 1

	var airborne_pairs: Dictionary[int, bool] = {}
	var planted := 0
	for leg: Leg in _rig.legs:
		if leg.broken:
			continue
		if not _is_finite(leg.sole_position()) or not _is_finite(leg.hip_world()):
			_metrics.nan_ticks += 1
		if leg.is_airborne():
			airborne_pairs[_pair_of(leg.index)] = true
			var _erased := _anchors.erase(leg.index)
			_float_time[leg.index] = 0.0
			continue
		planted += 1
		# Con patas rotas las métricas se acumulan aparte: el trípode y el
		# arrastre son modos degradados y `docs/06` §16.2 mide la marcha sana.
		var target := _metrics
		if _broken == 1:
			target = _tripod
		elif _broken >= 2:
			target = _drag
		var sole := leg.sole_position()
		if not _anchors.has(leg.index):
			_anchors[leg.index] = sole
		var slide := Vector3(sole.x - _anchors[leg.index].x, 0.0,
				sole.z - _anchors[leg.index].z).length()
		if slide > target.max_slide:
			target.max_slide = slide
			target.slide_offender = leg.side
		if slide > MAX_SLIDE and not _slide_logged and _broken == 0:
			_slide_logged = true
			_trace("deslizamiento", leg)
		var lift := sole.y - leg.plant_position.y
		target.max_float = maxf(target.max_float, lift)
		if lift > FLOAT_HEIGHT:
			_float_time[leg.index] = _float_time.get(leg.index, 0.0) + delta
			if _float_time[leg.index] > target.max_float_time:
				target.max_float_time = _float_time[leg.index]
				target.float_offender = leg.side
			if _float_time[leg.index] > MAX_FLOAT_TIME and not _float_logged and _broken == 0:
				_float_logged = true
				_trace("flotación", leg)
		else:
			_float_time[leg.index] = 0.0

	if not _rig.is_leaping():
		# El criterio 3 de `docs/06` §16.2 se mide **con las cuatro patas sanas**:
		# arrastrándose con dos, tener una sola apoyada es lo correcto.
		if _broken == 0:
			_metrics.min_planted = mini(_metrics.min_planted, planted)
		if airborne_pairs.size() > 1:
			_metrics.pair_violations += 1

	var tilt := rad_to_deg(_enemy.global_basis.y.angle_to(Vector3.UP))
	if body.x > RAMP_SAMPLE_MIN and body.x < RAMP_SAMPLE_MAX and absf(body.z) < 20.0:
		_metrics.ramp_tilt_sum += tilt
		_metrics.ramp_tilt_count += 1
	elif Vector2(body.x, body.z).length() < FLAT_RADIUS and _broken == 0:
		_metrics.flat_height_sum += _hip_height()
		_metrics.flat_height_count += 1


## Índice del par diagonal de una pata, tal como lo armó el [GaitController].
func _pair_of(leg_index: int) -> int:
	return _rig.pair_of(leg_index)


## Vuelca el contexto la **primera** vez que una métrica se sale de umbral. Sin
## esto, un fallo en los 120 s de marcha es un número sin historia.
func _trace(label: String, leg: Leg) -> void:
	var line := "  primer exceso de %s: pata %s, cuerpo %s, marcha %s, estado %s" % [
			label, leg.side, _enemy.global_position.round(), _rig.gait_name(),
			_rig.locomotion_state()]
	for other: Leg in _rig.legs:
		line += " | %s p=%d t=%.2f str=%s plant=%s sole=%s" % [other.side,
				1 if other.planted else 0, other.step_t, "S" if other.stretched else "-",
				other.plant_position.round(), other.sole_position().round()]
	print(line)


## `true` si las tres componentes son finitas.
func _is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


# --------------------------------------------------------------------------
# Veredictos
# --------------------------------------------------------------------------

## Vuelca las métricas de los 120 s y las contrasta con `docs/06` §16.2.
func _report_walk() -> void:
	var rig_usec := _rig.average_tick_usec()
	print("  deslizamiento máximo %.3f m (%s) · flotación máxima %.3f m · flotación sostenida %.3f s (%s)"
			% [_metrics.max_slide, _metrics.slide_offender, _metrics.max_float,
			_metrics.max_float_time, _metrics.float_offender])
	print("  inclinación en rampa %.2f° (%d muestras) · cadera en llano %.2f m (%d muestras)"
			% [_metrics.ramp_tilt(), _metrics.ramp_tilt_count, _metrics.flat_height(),
			_metrics.flat_height_count])
	print("  paso máximo de move_body %.3f m · patas apoyadas mínimas %d · rig_tick medio %.1f µs"
			% [_metrics.max_body_step, _metrics.min_planted, rig_usec])
	print("  trípode (3 patas): deslizamiento %.3f m · flotación sostenida %.3f s"
			% [_tripod.max_slide, _tripod.max_float_time])
	print("  arrastre (2 patas): deslizamiento %.3f m · flotación sostenida %.3f s"
			% [_drag.max_slide, _drag.max_float_time])
	expect(_tripod.max_slide < MAX_SLIDE,
			"deslizamiento en trípode %.3f m, tope %.2f m" % [_tripod.max_slide, MAX_SLIDE])
	expect(_tripod.max_float_time <= MAX_FLOAT_TIME,
			"pie flotando en trípode %.3f s, tope %.2f s"
			% [_tripod.max_float_time, MAX_FLOAT_TIME])

	expect(_metrics.max_slide < MAX_SLIDE,
			"deslizamiento de pie %.3f m, tope %.2f m" % [_metrics.max_slide, MAX_SLIDE])
	expect(_metrics.max_float_time <= MAX_FLOAT_TIME,
			"pie flotando %.3f s por encima de %.2f m, tope %.2f s"
			% [_metrics.max_float_time, FLOAT_HEIGHT, MAX_FLOAT_TIME])
	expect(_metrics.pair_violations == 0,
			"los dos pares diagonales estuvieron en el aire en %d ticks"
			% _metrics.pair_violations)
	expect(_metrics.min_planted >= 2,
			"en algún tick sólo hubo %d patas apoyadas" % _metrics.min_planted)
	expect(_metrics.nan_ticks == 0,
			"%d ticks con NaN o INF en las transformadas" % _metrics.nan_ticks)
	expect(_metrics.max_body_step <= _enemy.profile.max_step_per_tick + 0.0001,
			"paso de move_body %.4f m, tope %.2f m"
			% [_metrics.max_body_step, _enemy.profile.max_step_per_tick])
	expect(_metrics.ramp_tilt_count > 0, "el jefe nunca llegó a la rampa de 20°")
	expect(_metrics.ramp_tilt() >= RAMP_TILT_MIN and _metrics.ramp_tilt() <= RAMP_TILT_MAX,
			"inclinación en rampa %.2f°, banda [%.0f°, %.0f°]"
			% [_metrics.ramp_tilt(), RAMP_TILT_MIN, RAMP_TILT_MAX])
	expect(_metrics.flat_height_count > 0, "no hubo muestras de altura en llano")
	expect_near(_metrics.flat_height(), _enemy.profile.hip_height, HEIGHT_TOLERANCE,
			"altura de cadera en llano")
	expect(rig_usec < MAX_RIG_USEC,
			"rig_tick medio %.1f µs, tope %.0f µs" % [rig_usec, MAX_RIG_USEC])

	# Cojera y arrastre (`docs/06` §8.3 y §8.7).
	expect(_broken == 2, "el guion rompió %d rodillas, esperadas 2" % _broken)
	expect_near(_rig.speed_multiplier(), _rig.profile.drag_speed_factor, 0.001,
			"speed_multiplier() con dos patas perdidas")
	expect(_rig.gait_name() == &"DRAG",
			"marcha con dos patas '%s', esperada 'DRAG'" % _rig.gait_name())
	var drag := _speed_sum / float(maxi(_speed_ticks, 1))
	print("  velocidad media arrastrando %.2f m/s (objetivo %.2f m/s)"
			% [drag, _enemy.profile.walk_speed * _rig.profile.drag_speed_factor])
	expect(_tripod_speed >= _enemy.profile.walk_speed * TRIPOD_SPEED_RATIO,
			"velocidad con tres patas %.2f m/s, mínimo %.2f m/s"
			% [_tripod_speed, _enemy.profile.walk_speed * TRIPOD_SPEED_RATIO])


## El edificio de prueba tiene que haber cobrado `crush_damage` al ser pisado.
func _check_building() -> void:
	var damage := _rig.profile.crush_damage
	print("  edificio de prueba: %d apoyos, %.0f de daño acumulado"
			% [_building.hits, _building.total])
	expect(_building.hits > 0,
			"el jefe nunca apoyó un pie sobre el edificio de capa 8")
	if _building.hits > 0:
		expect_near(_building.total / float(_building.hits), damage, 0.01,
				"daño por apoyo sobre el edificio")


## Salto sobre la roca: cuatro pies apoyados en menos de [constant LEAP_BUDGET].
func _check_leap() -> void:
	_enemy.global_position = Vector3(ROCK_CENTER.x, 0.0, ROCK_CENTER.z - 34.0)
	_rig.snap_to_ground()
	await wait_physics(30)

	var landing := Vector3(ROCK_CENTER.x, ROCK_CENTER.y + ROCK_SIZE.y * 0.5, ROCK_CENTER.z)
	var started := Time.get_ticks_usec()
	var elapsed := 0.0
	var tuck := _rig.profile.leap_tuck_time
	_rig.jump(landing)
	expect(_rig.is_leaping(), "jump() no arrancó el salto")
	while elapsed < LEAP_BUDGET and _rig.is_leaping():
		await get_tree().physics_frame
		elapsed += _enemy.get_physics_process_delta_time()
	# Se mide justo al salir del salto: pasada la recuperación el rig ya empieza
	# a recolocar los pies con pasos normales y habría patas en el aire de nuevo.
	var planted := _rig.planted_count()
	var states := ""
	for leg: Leg in _rig.legs:
		states += " %s(p=%d t=%.2f)" % [leg.side, 1 if leg.planted else 0, leg.step_t]
	print("  salto: %.2f s simulados (recogida %.2f s), %d pies apoyados%s, cuerpo en %s, %.1f ms reales"
			% [elapsed, tuck, planted, states, _enemy.global_position.round(),
			float(Time.get_ticks_usec() - started) / 1000.0])
	expect(elapsed < LEAP_BUDGET, "el salto tardó %.2f s, tope %.1f s" % [elapsed, LEAP_BUDGET])
	expect(planted == 4, "tras el salto quedaron %d pies apoyados, esperados 4" % planted)
	expect(Vector2(_enemy.global_position.x - landing.x,
			_enemy.global_position.z - landing.z).length() < 12.0,
			"el jefe aterrizó a %.1f m del objetivo"
			% Vector2(_enemy.global_position.x - landing.x,
			_enemy.global_position.z - landing.z).length())


## Prueba negativa: con `step_trigger` a 30 m el pie no puede seguir al cuerpo y
## las métricas 1 y 2 tienen que dispararse. Si no lo hacen, el check no estaría
## midiendo nada.
func _check_negative() -> void:
	_enemy.queue_free()
	await wait_frames(2)
	_metrics = Metrics.new()
	_tripod = Metrics.new()
	_drag = Metrics.new()
	_anchors.clear()
	_float_time.clear()
	_waypoint = 0
	_broken = 0
	_slide_logged = false
	_float_logged = false

	_enemy = _spawn(Vector3.ZERO)
	if _enemy == null:
		return
	await wait_physics(4)
	_rig = _enemy.locomotion as ProceduralLegRig
	if _rig == null:
		fail("la instancia de la prueba negativa no tiene rig")
		return
	# Se desarman los **dos** disparadores de paso: el de distancia al reposo y
	# el de alcance de la cadena. Con `reach_trigger` en `stretch_max` la pata
	# sólo pide paso cuando ya no llega, que es tarde.
	var broken_profile := _rig.profile.duplicate() as LegRigProfile
	broken_profile.step_trigger = NEGATIVE_TRIGGER
	broken_profile.reach_trigger = broken_profile.stretch_max
	_rig.profile = broken_profile

	Engine.time_scale = TIME_SCALE
	await _walk(NEGATIVE_SECONDS, false)
	Engine.time_scale = 1.0

	var slid := _metrics.max_slide >= MAX_SLIDE
	var floated := _metrics.max_float_time > MAX_FLOAT_TIME
	print("  prueba negativa (step_trigger %.0f m): deslizamiento %.3f m, flotación sostenida %.3f s"
			% [NEGATIVE_TRIGGER, _metrics.max_slide, _metrics.max_float_time])
	expect(slid or floated,
			"la prueba negativa no rompió ninguna métrica: deslizamiento %.3f m, flotación %.3f s"
			% [_metrics.max_slide, _metrics.max_float_time])
	if slid or floated:
		print("  prueba negativa: FALLA como se esperaba (%s)"
				% ("deslizamiento" if slid else "flotación"))
