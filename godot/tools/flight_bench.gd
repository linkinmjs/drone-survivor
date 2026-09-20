## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Banco de pruebas del núcleo de vuelo (`docs/03` §11).
##
## Mide primero los criterios que **no** dependen del controlador de vuelo, que
## es lo que cerró WP-04: hover, relación empuje/peso, respuesta de motor,
## estabilidad numérica, coste por tick, efecto suelo, arrastre, reaparición y par
## de reacción. Después engancha un [FlightController] al dron y mide los tres que
## sí dependen de él (§11.4 escalón de tasa, §11.5 escalón de ángulo, §11.6
## velocidad máxima) más el armado, los signos del mezclador y el air mode.
##
## El controlador se agrega **a mitad de la corrida**, no en la escena: los diez
## primeros criterios necesitan mandar comandos crudos a los motores con
## `test_motor_commands`, y un controlador enganchado se los pisaría en cada
## sub-paso.
##
## Discrepancia registrada con `docs/03` §11.8 — **cómo se mide el coste**.
## §11.8 pide «media de `Performance.TIME_PHYSICS_PROCESS` < 1.6 ms». Ese monitor
## no es una media por tick: Godot lo refresca **una vez por segundo** y lo que
## guarda es el **máximo** del bloque de física de ese segundo, con todos los
## pasos que la iteración haya tenido que recuperar de golpe. Medido acá, una
## escena vacía sin un solo cuerpo ya marca picos de 0.34 ms, y tres corridas
## idénticas del dron dieron 1.70, 3.90 y 4.70 ms: es ruido del planificador de
## Windows, no coste del dron. Se mantiene el monitor y su ventana (300 ticks
## descartando los 60 primeros) como dato **informativo**, y lo que decide el
## check es la medida directa del integrador —`Time.get_ticks_usec()` dentro de
## `_integrate_forces`—, que es literalmente lo que presupuesta §2.5: «el tick de
## física **del dron** debe costar < 1.6 ms».
##
## Corre así:
##   godot --headless --path godot res://tools/flight_bench.tscn
extends CheckRunner

## Aceleración de la gravedad en m/s², la misma de `docs/02` §2.
const GRAVITY: float = 9.81

## Rango admitido del comando de equilibrio (`docs/03` §11.1).
const HOVER_RANGE: Vector2 = Vector2(0.35, 0.55)

## Tolerancia del empuje de equilibrio contra el peso (`docs/03` §11.1).
const HOVER_TOLERANCE: float = 0.03

## Rango admitido de la relación empuje/peso a comando máximo (`docs/03` §11.2).
const TWR_RANGE: Vector2 = Vector2(4.0, 6.0)

## Tiempo máximo de ralentí al 90 % del régimen máximo, en s (`docs/03` §11.3).
const RESPONSE_LIMIT: float = 0.12

## Presupuesto de física por tick, en ms (`docs/03` §11.8 y `docs/15` §5.2).
const COST_LIMIT_MS: float = 1.6

## Ventana de medida de coste y frames de calentamiento descartados (`docs/15` §5.1).
const COST_WINDOW: int = 300
const COST_WARMUP: int = 60

## Duración de la prueba de estabilidad numérica, en segundos simulados.
const STABILITY_SECONDS: float = 60.0

## Velocidad por encima de la cual la simulación se considera divergida, en m/s.
const STABILITY_SPEED_LIMIT: float = 80.0

## Velocidad terminal máxima admitida en caída libre desarmado, en m/s.
const TERMINAL_SPEED_LIMIT: float = 60.0

## Alturas a las que se compara el empuje para el efecto suelo, en m.
const GROUND_EFFECT_LOW: float = 0.06
const GROUND_EFFECT_HIGH: float = 2.0

## Rango admitido del factor de efecto suelo entre esas dos alturas.
const GROUND_EFFECT_RANGE: Vector2 = Vector2(1.05, 1.33)

## Factor de aceleración del tiempo simulado. `CheckRunner` lo devuelve a 1 al
## terminar y su timeout mide segundos reales, así que no se puede colgar.
const FAST_FORWARD: float = 4.0

## Semilla fija de la prueba de estabilidad: un fallo tiene que poder repetirse.
const STABILITY_SEED: int = 20260919

## Paso de física nominal, en segundos. `Engine.time_scale` lo multiplica: a 4×
## cada tick avanza 40 ms de tiempo simulado, y el dron reparte sus sub-pasos
## para que cada uno siga midiendo 1 ms.
const PHYSICS_STEP: float = 0.01

## Escalón de tasa de `docs/03` §11.4: consigna, tiempo máximo al 90 % y
## sobrepaso máximo.
const RATE_STEP_DEGREES: float = 360.0
const RATE_STEP_RISE_LIMIT: float = 0.150
const RATE_STEP_OVERSHOOT_LIMIT: float = 0.15

## Escalón de ángulo de `docs/03` §11.5: consigna en grados, banda de asentamiento
## en grados, tiempo máximo de asentamiento y sobrepaso máximo.
const ANGLE_STEP_DEGREES: float = 30.0
const ANGLE_STEP_BAND: float = 2.0
const ANGLE_STEP_SETTLE_LIMIT: float = 1.0
const ANGLE_STEP_OVERSHOOT_LIMIT: float = 0.15

## Velocidad máxima de `docs/03` §11.6: inclinación mantenida, ventana de medida y
## rango admitido de `v_max`.
const TOP_SPEED_PITCH_DEGREES: float = -45.0
const TOP_SPEED_SECONDS: float = 6.0
const TOP_SPEED_RANGE: Vector2 = Vector2(25.0, 40.0)

## Velocidad a la que el banco lleva la consigna de inclinación hasta los 45°,
## en deg/s.
const TOP_SPEED_RAMP: float = 60.0

## Acelerador con el que se intenta armar en el criterio de armado: bien por
## encima del 0.02 de `docs/03` §3.3.
const ARM_HIGH_THROTTLE: float = 0.5

## Deflexión de stick con la que se comprueban los signos del mezclador. Pequeña
## a propósito: con el mezclador sin saturar se ve el signo puro de cada eje.
const MIXER_PROBE: float = 0.2

@export var drone_path: NodePath = ^"Drone"

var _drone: Drone = null
var _motors: Array[DroneMotor] = []
var _propellers: Array[DronePropeller] = []
var _hover_command: float = 0.0
var _respawn_count: int = 0
var _controller: FlightController = null
var _command: FlightCommand = FlightCommand.new()
var _arm_failures: Array[String] = []
var _arm_modes: Array[String] = []


func _run() -> void:
	Engine.physics_ticks_per_second = 100
	_drone = get_node_or_null(drone_path) as Drone
	if _drone == null:
		fail("no se encontró el nodo Drone en '%s'" % str(drone_path))
		return
	_stand_down_gameplay_systems()
	await wait_physics(2)
	_motors = _drone.get_motors()
	_propellers = _drone.get_propellers()
	if _motors.size() != 4 or _propellers.size() != 4:
		fail("se esperaban 4 motores con hélice y hay %d/%d"
				% [_motors.size(), _propellers.size()])
		return
	var _discard := _drone.respawned.connect(_on_respawned)

	print("  masa %.3f kg, peso %.3f N, max_rpm %.0f, C_T %.4f, C_Q %.4f, D %.4f m"
			% [_drone.mass, _drone.mass * GRAVITY, _motors[0].max_rpm,
			_propellers[0].c_t, _propellers[0].c_q, _propellers[0].diameter])

	_check_hover_command()
	_check_thrust_to_weight()
	_check_motor_response()
	await _check_ground_effect()
	await _check_reaction_torque()
	await _check_reset_to()
	await _check_terminal_velocity()
	await _check_numerical_stability()
	await _check_physics_cost()
	await _check_model_wiring()
	_attach_controller()
	await _check_arming()
	_check_mixer_signs()
	_check_air_mode()
	await _check_rate_step()
	await _check_angle_step()
	await _check_top_speed()


## §11.1 — Comando de equilibrio por bisección sobre el empuje estático.
func _check_hover_command() -> void:
	var weight := _drone.mass * GRAVITY
	var low := 0.0
	var high := 1.0
	for _iteration: int in 64:
		var middle := (low + high) * 0.5
		if _static_thrust(middle) < weight:
			low = middle
		else:
			high = middle
	_hover_command = (low + high) * 0.5
	var thrust := _static_thrust(_hover_command)
	var error := absf(thrust - weight) / weight
	print("  [1] hover: comando %.4f, empuje %.4f N, peso %.4f N, error %.3f %%"
			% [_hover_command, thrust, weight, error * 100.0])
	expect(error <= HOVER_TOLERANCE,
			"el empuje de equilibrio se aparta del peso un %.2f %% (máximo %.0f %%)"
			% [error * 100.0, HOVER_TOLERANCE * 100.0])
	expect(_hover_command >= HOVER_RANGE.x and _hover_command <= HOVER_RANGE.y,
			"el comando de equilibrio %.4f queda fuera de [%.2f, %.2f]"
			% [_hover_command, HOVER_RANGE.x, HOVER_RANGE.y])


## §11.2 — Relación empuje/peso con los cuatro motores a fondo.
func _check_thrust_to_weight() -> void:
	var weight := _drone.mass * GRAVITY
	var thrust := _static_thrust(1.0)
	var ratio := thrust / weight
	print("  [2] empuje/peso: %.4f N totales, relación %.3f" % [thrust, ratio])
	expect(ratio >= TWR_RANGE.x and ratio <= TWR_RANGE.y,
			"la relación empuje/peso %.3f queda fuera de [%.1f, %.1f]"
			% [ratio, TWR_RANGE.x, TWR_RANGE.y])


## §11.3 — Tiempo de ralentí al 90 % del régimen máximo.
##
## Se mide sobre un motor de laboratorio con los mismos parámetros que el del
## dron, para no perturbar la simulación que viene después.
func _check_motor_response() -> void:
	var reference := _motors[0]
	var motor := DroneMotor.new()
	motor.max_rpm = reference.max_rpm
	motor.idle_rpm = reference.idle_rpm
	motor.tau_up = reference.tau_up
	motor.tau_down = reference.tau_down
	motor.powered = true
	motor.rpm = motor.idle_rpm
	motor.set_command(1.0)
	var goal := 0.9 * motor.max_rpm
	var dt := 0.0005
	var elapsed := 0.0
	while motor.rpm < goal and elapsed < 1.0:
		motor.step(dt)
		elapsed += dt
	var reached := motor.rpm
	motor.free()
	print("  [3] respuesta de motor: %.0f -> %.0f rpm en %.4f s (límite %.2f s)"
			% [reference.idle_rpm, reached, elapsed, RESPONSE_LIMIT])
	expect(elapsed < RESPONSE_LIMIT,
			"el motor tardó %.4f s en llegar al 90 %% del régimen (límite %.2f s)"
			% [elapsed, RESPONSE_LIMIT])


## §11 — Efecto suelo: a 0.06 m el empuje supera al de 2 m con el mismo régimen.
## De paso comprueba que el `RayCast3D` de la hélice mide la altura de verdad.
func _check_ground_effect() -> void:
	var propeller := _propellers[0]
	var rpm := _motors[0].rpm_for_command(_hover_command)
	var near: float = propeller.compute_forces(rpm, Vector3.ZERO, Vector3.UP,
			GROUND_EFFECT_LOW)["thrust"]
	var far: float = propeller.compute_forces(rpm, Vector3.ZERO, Vector3.UP,
			GROUND_EFFECT_HIGH)["thrust"]
	var factor := near / far if far > 0.0 else 0.0
	print("  [6] efecto suelo: %.4f N a %.2f m contra %.4f N a %.2f m, factor %.4f"
			% [near, GROUND_EFFECT_LOW, far, GROUND_EFFECT_HIGH, factor])
	expect(near > far, "el empuje a %.2f m (%.4f N) no supera al de %.2f m (%.4f N)"
			% [GROUND_EFFECT_LOW, near, GROUND_EFFECT_HIGH, far])
	expect(factor >= GROUND_EFFECT_RANGE.x and factor <= GROUND_EFFECT_RANGE.y,
			"el factor de efecto suelo %.4f queda fuera de [%.2f, %.2f]"
			% [factor, GROUND_EFFECT_RANGE.x, GROUND_EFFECT_RANGE.y])

	_drone.force_disarm()
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.30, 0.0)))
	await wait_physics(3)
	var measured := _drone.get_flight_state().altitude_agl
	print("      altura medida por los rayos de hélice: %.4f m" % measured)
	expect(measured > 0.0 and measured < 0.6,
			"el rayo de hélice midió %.4f m sobre un suelo que está a ~0.33 m" % measured)


## §11 — Par de reacción: la pareja CW (M1 y M3) guiña a la izquierda y la pareja
## CCW (M2 y M4) a la derecha, que es el sentido que necesita el mezclador de §3.5.
func _check_reaction_torque() -> void:
	var clockwise := await _measure_yaw([1.0, 0.0, 1.0, 0.0])
	var counter := await _measure_yaw([0.0, 1.0, 0.0, 1.0])
	print("  [9] par de reacción: M1+M3 (CW) %.3f rad/s, M2+M4 (CCW) %.3f rad/s"
			% [clockwise, counter])
	expect(clockwise > 1.0,
			"con M1 y M3 (CW) a régimen la guiñada dio %.3f rad/s y debía ser positiva"
			% clockwise)
	expect(counter < -1.0,
			"con M2 y M4 (CCW) a régimen la guiñada dio %.3f rad/s y debía ser negativa"
			% counter)


## §11 — `reset_to()` teletransporta y emite `respawned`.
func _check_reset_to() -> void:
	_drone.force_disarm()
	_drone.test_motor_commands = [0.0, 0.0, 0.0, 0.0]
	await wait_physics(2)
	var target := Transform3D(Basis.IDENTITY, Vector3(12.0, 33.0, -7.0))
	_respawn_count = 0
	_drone.reset_to(target)
	await wait_physics(3)
	var distance := _drone.global_transform.origin.distance_to(target.origin)
	print("  [8] reset_to: %d señal(es) respawned, desvío %.4f m" % [_respawn_count, distance])
	expect(_respawn_count == 1, "reset_to emitió %d señales respawned en vez de 1"
			% _respawn_count)
	expect(distance < 0.2, "reset_to dejó el dron a %.4f m del destino" % distance)


## §11 — Arrastre: la caída libre desarmado llega a una velocidad terminal finita.
func _check_terminal_velocity() -> void:
	_drone.force_disarm()
	_drone.test_motor_commands = [0.0, 0.0, 0.0, 0.0]
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 1500.0, 0.0)))
	await wait_physics(2)
	Engine.time_scale = FAST_FORWARD
	var previous := 0.0
	var speed := 0.0
	var ticks := 0
	while ticks < 2500:
		await wait_physics(50)
		ticks += 50
		speed = _drone.linear_velocity.length()
		if not is_finite(speed):
			break
		if absf(speed - previous) < 0.02:
			break
		previous = speed
	Engine.time_scale = 1.0
	print("  [7] velocidad terminal: %.3f m/s tras %.2f s simulados"
			% [speed, float(ticks) * PHYSICS_STEP * FAST_FORWARD])
	expect(is_finite(speed), "la velocidad de caída no es finita: %s" % str(speed))
	expect(speed < TERMINAL_SPEED_LIMIT,
			"la velocidad terminal %.3f m/s supera el límite de %.0f m/s"
			% [speed, TERMINAL_SPEED_LIMIT])
	expect(speed > 5.0, "el dron no llegó a caer: %.3f m/s" % speed)


## §11.7 — 60 s simulados con comandos aleatorios sin NaN ni velocidades absurdas.
func _check_numerical_stability() -> void:
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 80.0, 0.0)))
	await wait_physics(2)
	var _armed_ok := _drone.arm()
	var rng := RandomNumberGenerator.new()
	rng.seed = STABILITY_SEED
	Engine.time_scale = FAST_FORWARD
	var max_speed := 0.0
	var finite := true
	# Cada tick avanza `PHYSICS_STEP · FAST_FORWARD` de tiempo simulado, y el dron
	# reparte sus sub-pasos para que cada uno siga durando 1 ms.
	var tick_seconds := PHYSICS_STEP * FAST_FORWARD
	var total_ticks := int(STABILITY_SECONDS / tick_seconds)
	var burst := 25
	var elapsed := 0
	while elapsed < total_ticks:
		var commands: Array[float] = []
		for _index: int in 4:
			commands.append(rng.randf_range(0.10, 0.60))
		_drone.test_motor_commands = commands
		await wait_physics(burst)
		elapsed += burst
		var state := _drone.get_flight_state()
		if not state.is_finite_state():
			finite = false
			break
		max_speed = maxf(max_speed, _drone.linear_velocity.length())
	Engine.time_scale = 1.0
	_drone.force_disarm()
	var simulated := float(elapsed) * tick_seconds
	print("  [4] estabilidad numérica: %.1f s simulados en %d ticks a %.0fx, velocidad máxima %.3f m/s"
			% [simulated, elapsed, FAST_FORWARD, max_speed])
	expect(finite, "el estado de vuelo dejó de ser finito a los %.1f s" % simulated)
	expect(max_speed <= STABILITY_SPEED_LIMIT,
			"la velocidad llegó a %.3f m/s y el límite es %.0f m/s"
			% [max_speed, STABILITY_SPEED_LIMIT])


## §11.8 y §2.5 — Coste del tick de física con el dron armado en equilibrio.
##
## Decide la medida directa del integrador; el monitor de `Performance` se
## imprime al lado como dato informativo. El porqué está en la cabecera.
func _check_physics_cost() -> void:
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 40.0, 0.0)))
	await wait_physics(2)
	var _armed_ok := _drone.arm()
	_drone.test_motor_commands = [_hover_command, _hover_command, _hover_command,
			_hover_command]
	await wait_physics(COST_WARMUP)
	_drone.start_profiling()
	var total := 0.0
	var peak := 0.0
	for _sample: int in COST_WINDOW:
		await wait_physics(1)
		var value := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		total += value
		peak = maxf(peak, value)
	var average := _drone.get_profile_average_ms()
	var worst := _drone.get_profile_peak_ms()
	var ticks := _drone.get_profile_ticks()
	_drone.stop_profiling()
	_drone.force_disarm()
	var substeps := _drone.get_last_substep_count()
	print("  [5] coste del integrador: media %.4f ms, peor tick %.4f ms en %d ticks de %d sub-pasos (límite %.2f ms)"
			% [average, worst, ticks, substeps, COST_LIMIT_MS])
	print("      informativo, Performance.TIME_PHYSICS_PROCESS (pico por segundo): media %.3f ms, máximo %.3f ms en %d muestras"
			% [total / float(COST_WINDOW), peak, COST_WINDOW])
	expect(substeps == Drone.SUBSTEPS_ARMED,
			"el coste se midió con %d sub-pasos y el presupuesto de §2.5 es para %d"
			% [substeps, Drone.SUBSTEPS_ARMED])
	expect(ticks >= COST_WINDOW / 2,
			"solo se midieron %d ticks de integrador y se esperaban al menos %d"
			% [ticks, COST_WINDOW / 2])
	expect(average < COST_LIMIT_MS,
			"el integrador costó %.4f ms de media y el presupuesto es %.2f ms"
			% [average, COST_LIMIT_MS])


## `docs/03` §7 — Las hélices del modelo giran con el régimen y los discos de
## desenfoque aparecen. No es un criterio de §11, pero es la única forma de saber
## sin ventana que el GLB quedó cableado a los motores por su metadato.
func _check_model_wiring() -> void:
	var blades := _drone.get_blade_meshes()
	var disks := _drone.get_disk_meshes()
	var wired := 0
	for index: int in blades.size():
		if blades[index] != null and disks[index] != null:
			wired += 1
	expect(wired == 4, "solo %d de 4 hélices del modelo quedaron cableadas a su motor" % wired)
	if wired != 4:
		return
	var before := blades[0].rotation.y
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 40.0, 0.0)))
	await wait_physics(2)
	var _armed_ok := _drone.arm()
	_drone.test_motor_commands = [1.0, 1.0, 1.0, 1.0]
	await wait_physics(30)
	await wait_frames(4)
	var turned := absf(blades[0].rotation.y - before) > 0.001
	var disk_visible := disks[0].visible
	var disk_opacity := 1.0 - disks[0].transparency
	_drone.force_disarm()
	_drone.test_motor_commands = [0.0, 0.0, 0.0, 0.0]
	print("  [10] modelo: 4/4 hélices cableadas, pala girando %s, disco visible %s con opacidad %.2f"
			% [str(turned), str(disk_visible), disk_opacity])
	expect(turned, "la malla prop_1 no giró con el motor a fondo")
	expect(disk_visible and disk_opacity > 0.9,
			"el disco de desenfoque no apareció con el motor a fondo (visible %s, opacidad %.2f)"
			% [str(disk_visible), disk_opacity])


## Engancha un `FlightController` al dron para los criterios que lo necesitan.
##
## Va después de los diez primeros a propósito: con el controlador puesto,
## `test_motor_commands` deja de tener efecto y los criterios puramente físicos
## no podrían mandar régimen a mano.
func _attach_controller() -> void:
	_controller = FlightController.new()
	_controller.name = "FlightController"
	_controller.drone = _drone
	_drone.add_child(_controller)
	_drone.set_controller(_controller)
	# Perfil de REFERENCIA de `docs/03` §3.6 (ACTUAL 7/67/54: 70 y 670 deg/s), no el
	# persistido por `QuadSettings` (desde el checkpoint 2 es 5/30/25, con 300 deg/s de
	# máximo, y el escalón de 360 deg/s de §11.4 era inalcanzable). El banco mide el
	# controlador con la spec, no con la sensibilidad que elija el jugador.
	_controller.set_control_profile(ControlProfile.new())
	var _discard := _drone.arm_failed.connect(_on_arm_failed)
	_discard = _drone.armed.connect(_on_armed)
	var profile := _controller.get_control_profile()
	print("  controlador enganchado: PID alabeo %s, cabeceo %s, guiñada %s, K_angle %.2f, perfil %d con máximo %.0f deg/s"
			% [str(_controller.rate_gains_roll), str(_controller.rate_gains_pitch),
			str(_controller.rate_gains_yaw), _controller.angle_gain, int(profile.curve),
			profile.get_max_rate(ControlProfile.Axis.ROLL)])


## §11 — Armado: con acelerador alto falla con `ERR_ARM_THROTTLE_HIGH`; con el
## stick abajo arma y emite `armed("acro")` (`docs/03` §3.3).
func _check_arming() -> void:
	_drone.force_disarm()
	_controller.select_mode(FlightController.MODE_ACRO)
	await wait_physics(2)
	_arm_failures.clear()
	_arm_modes.clear()

	_send_command(ARM_HIGH_THROTTLE, 0.0, 0.0, 0.0)
	var armed_high := _drone.arm()
	var reason := _arm_failures[0] if not _arm_failures.is_empty() else "(ninguna)"
	print("  [11] armado: con acelerador %.2f -> %s, motivo %s"
			% [ARM_HIGH_THROTTLE, str(armed_high), reason])
	expect(not armed_high, "el dron armó con el acelerador en %.2f" % ARM_HIGH_THROTTLE)
	expect(not _drone.is_armed(), "arm() falló pero el dron quedó armado igual")
	expect(reason == FlightController.REASON_THROTTLE_HIGH,
			"el motivo del rechazo fue '%s' y debía ser '%s'"
			% [reason, FlightController.REASON_THROTTLE_HIGH])

	_send_command(0.0, 0.0, 0.0, 0.0)
	var armed_low := _drone.arm()
	var mode := _arm_modes[0] if not _arm_modes.is_empty() else "(ninguno)"
	print("       con acelerador 0.00 -> %s, señal armed('%s')" % [str(armed_low), mode])
	expect(armed_low and _drone.is_armed(), "el dron no armó con el acelerador al mínimo")
	expect(mode == FlightController.MODE_ACRO,
			"armed() llegó con el modo '%s' y debía ser '%s'"
			% [mode, FlightController.MODE_ACRO])
	_drone.force_disarm()
	await wait_physics(2)


## §11 — Signos del mezclador (`docs/03` §3.5): cada eje sube la pareja de motores
## que le toca y baja la otra.
func _check_mixer_signs() -> void:
	var base := 0.5
	var roll := _controller.mix(base, MIXER_PROBE, 0.0, 0.0)
	var pitch := _controller.mix(base, 0.0, MIXER_PROBE, 0.0)
	var yaw := _controller.mix(base, 0.0, 0.0, MIXER_PROBE)
	print("  [12] mezclador con base %.2f: r=+%.2f -> %s" % [base, MIXER_PROBE, _format(roll)])
	print("       p=+%.2f -> %s" % [MIXER_PROBE, _format(pitch)])
	print("       y=+%.2f -> %s" % [MIXER_PROBE, _format(yaw)])
	expect(roll[0] > base and roll[3] > base and roll[1] < base and roll[2] < base,
			"con r = +%.2f tienen que subir m1 y m4 y bajar m2 y m3, y quedó %s"
			% [MIXER_PROBE, _format(roll)])
	expect(pitch[2] > base and pitch[3] > base and pitch[0] < base and pitch[1] < base,
			"con p = +%.2f tienen que subir m3 y m4 (traseros: morro abajo) y bajar m1 y m2, y quedó %s"
			% [MIXER_PROBE, _format(pitch)])
	expect(yaw[0] > base and yaw[2] > base and yaw[1] < base and yaw[3] < base,
			"con y = +%.2f tienen que subir m1 y m3 (CW) y bajar m2 y m4, y quedó %s"
			% [MIXER_PROBE, _format(yaw)])


## §11 — Air mode (`docs/03` §3.5): con el acelerador al mínimo y guiñada a fondo,
## ningún motor baja del ralentí del mezclador y la autoridad se conserva.
func _check_air_mode() -> void:
	var mixed := _controller.mix(0.0, 0.0, 0.0, 1.0)
	var lowest := mixed[0]
	var highest := mixed[0]
	for value: float in mixed:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	print("  [13] air mode con T = 0 y y = 1: %s (mínimo %.4f, máximo %.4f, ralentí %.2f)"
			% [_format(mixed), lowest, highest, FlightController.MIXER_IDLE])
	expect(lowest >= FlightController.MIXER_IDLE - 0.0001,
			"un motor quedó en %.4f, por debajo del ralentí %.2f del mezclador"
			% [lowest, FlightController.MIXER_IDLE])
	expect(highest - lowest > 0.5,
			"con el acelerador al mínimo el air mode conservó solo %.4f de autoridad"
			% (highest - lowest))


## §11.4 — Escalón de tasa en ACRO: 360 deg/s de alabeo, 90 % en < 150 ms y
## sobrepaso < 15 %.
func _check_rate_step() -> void:
	var stick := _stick_for_rate(ControlProfile.Axis.ROLL, RATE_STEP_DEGREES)
	var goal := deg_to_rad(RATE_STEP_DEGREES)
	if not await _arm_at(Vector3(0.0, 300.0, 0.0), FlightController.MODE_ACRO):
		return
	_send_command(_hover_command, 0.0, 0.0, 0.0)
	await wait_physics(40)
	_send_command(_hover_command, stick, 0.0, 0.0)

	var rise := -1.0
	var peak := 0.0
	var elapsed := 0.0
	for _tick: int in 80:
		await wait_physics(1)
		elapsed += PHYSICS_STEP
		var rate := _drone.get_flight_state().rates().x
		peak = maxf(peak, rate)
		if rise < 0.0 and rate >= 0.9 * goal:
			rise = elapsed
	_drone.force_disarm()
	var overshoot := (peak - goal) / goal
	print("  [§11.4] escalón de tasa en ACRO: stick %.4f -> %.1f deg/s; 90 %% en %.0f ms (límite %.0f ms), pico %.1f deg/s, sobrepaso %.2f %%"
			% [stick, RATE_STEP_DEGREES, rise * 1000.0, RATE_STEP_RISE_LIMIT * 1000.0,
			rad_to_deg(peak), overshoot * 100.0])
	expect(rise >= 0.0 and rise < RATE_STEP_RISE_LIMIT,
			"la tasa tardó %.0f ms en llegar al 90 %% y el límite es %.0f ms"
			% [rise * 1000.0, RATE_STEP_RISE_LIMIT * 1000.0])
	expect(overshoot < RATE_STEP_OVERSHOOT_LIMIT,
			"el sobrepaso de tasa fue del %.2f %% y el límite es %.0f %%"
			% [overshoot * 100.0, RATE_STEP_OVERSHOOT_LIMIT * 100.0])


## §11.5 — Escalón de ángulo en HORIZON: 30° de alabeo, asentado a ±2° en < 1 s y
## sobrepaso < 15 %.
func _check_angle_step() -> void:
	var stick := _stick_for_normalized(ControlProfile.Axis.ROLL,
			ANGLE_STEP_DEGREES / _controller.angle_limit_degrees)
	if not await _arm_at(Vector3(0.0, 300.0, 0.0), FlightController.MODE_HORIZON):
		return
	_send_command(_hover_command, 0.0, 0.0, 0.0)
	await wait_physics(40)
	_send_command(_hover_command, stick, 0.0, 0.0)

	var peak := 0.0
	var settle := -1.0
	var elapsed := 0.0
	var samples := int(2.0 / PHYSICS_STEP)
	for _tick: int in samples:
		await wait_physics(1)
		elapsed += PHYSICS_STEP
		var roll := rad_to_deg(_drone.get_flight_state().euler.x)
		peak = maxf(peak, roll)
		if absf(roll - ANGLE_STEP_DEGREES) > ANGLE_STEP_BAND:
			settle = -1.0
		elif settle < 0.0:
			settle = elapsed
	var final_roll := rad_to_deg(_drone.get_flight_state().euler.x)
	_drone.force_disarm()
	var overshoot := (peak - ANGLE_STEP_DEGREES) / ANGLE_STEP_DEGREES
	print("  [§11.5] escalón de ángulo en HORIZON: stick %.4f -> %.1f°; asentado a ±%.0f° en %.0f ms (límite %.0f ms), pico %.2f°, final %.2f°, sobrepaso %.2f %%"
			% [stick, ANGLE_STEP_DEGREES, ANGLE_STEP_BAND, settle * 1000.0,
			ANGLE_STEP_SETTLE_LIMIT * 1000.0, peak, final_roll, overshoot * 100.0])
	expect(settle >= 0.0 and settle < ANGLE_STEP_SETTLE_LIMIT,
			"el ángulo tardó %.0f ms en asentarse a ±%.0f° y el límite es %.0f ms"
			% [settle * 1000.0, ANGLE_STEP_BAND, ANGLE_STEP_SETTLE_LIMIT * 1000.0])
	expect(overshoot < ANGLE_STEP_OVERSHOOT_LIMIT,
			"el sobrepaso de ángulo fue del %.2f %% y el límite es %.0f %%"
			% [overshoot * 100.0, ANGLE_STEP_OVERSHOOT_LIMIT * 100.0])


## §11.6 — Velocidad máxima: en ACRO, con 45° de inclinación mantenida y el
## acelerador a fondo, `v_max` entra en `[25, 40] m/s` antes de 6 s.
##
## La inclinación la sostiene el propio banco con un lazo P de ángulo sobre el
## stick de cabeceo —el dron sigue en ACRO, o sea en tasa pura—, porque HORIZON
## no pasa de los 35° de `docs/03` §3.2 y el criterio pide 45°.
func _check_top_speed() -> void:
	if not await _arm_at(Vector3(0.0, 400.0, 0.0), FlightController.MODE_ACRO):
		return
	var goal := deg_to_rad(TOP_SPEED_PITCH_DEGREES)
	var best := 0.0
	var best_time := 0.0
	var held := 0.0
	var elapsed := 0.0
	var samples := int(TOP_SPEED_SECONDS / PHYSICS_STEP)
	for _tick: int in samples:
		var state := _drone.get_flight_state()
		# La consigna llega en rampa a TOP_SPEED_RAMP deg/s en vez de como
		# escalón: un escalón de 45° satura el stick, el dron pasa de largo de
		# los 90° de cabeceo y ahí la descomposición de Euler YXZ pierde el eje.
		var ramp := -minf(deg_to_rad(TOP_SPEED_RAMP) * elapsed, absf(goal))
		var stick := clampf(2.0 * (ramp - state.euler.y) - 0.10 * state.rates().y, -1.0, 1.0)
		_send_command(1.0, 0.0, stick, 0.0)
		await wait_physics(1)
		elapsed += PHYSICS_STEP
		held = rad_to_deg(_drone.get_flight_state().euler.y)
		var speed := _drone.linear_velocity.length()
		if speed > best:
			best = speed
			best_time = elapsed
	_drone.force_disarm()
	_send_command(0.0, 0.0, 0.0, 0.0)
	print("  [§11.6] velocidad máxima: %.2f m/s a los %.2f s con %.1f° de cabeceo mantenido (rango [%.0f, %.0f], ventana %.0f s, k_J %.2f, A_z %.3f m2, Cd_z %.2f)"
			% [best, best_time, held, TOP_SPEED_RANGE.x, TOP_SPEED_RANGE.y,
			TOP_SPEED_SECONDS, _propellers[0].k_j, Drone.DRAG_AREA.z, Drone.DRAG_CD.z])
	expect(best >= TOP_SPEED_RANGE.x and best <= TOP_SPEED_RANGE.y,
			"la velocidad máxima %.2f m/s queda fuera de [%.0f, %.0f] m/s"
			% [best, TOP_SPEED_RANGE.x, TOP_SPEED_RANGE.y])
	expect(absf(held - TOP_SPEED_PITCH_DEGREES) < 6.0,
			"el banco no sostuvo los %.0f° de inclinación: terminó en %.1f°"
			% [TOP_SPEED_PITCH_DEGREES, held])


## Deja el dron desarmado en [param position], nivelado, elige [param mode_key] y
## arma con el acelerador al mínimo. Devuelve `false` si el armado falló.
func _arm_at(position: Vector3, mode_key: String) -> bool:
	_drone.force_disarm()
	_controller.select_mode(mode_key)
	_drone.reset_to(Transform3D(Basis.IDENTITY, position))
	_send_command(0.0, 0.0, 0.0, 0.0)
	await wait_physics(3)
	var ok := _drone.arm()
	expect(ok, "no se pudo armar el dron para el criterio en modo '%s'" % mode_key)
	return ok


## Manda un comando de piloto al dron, que es como lo haría `RadioController`.
func _send_command(throttle: float, roll: float, pitch: float, yaw: float) -> void:
	_command.set_axes(throttle, roll, pitch, yaw)
	_drone.update_command(_command)


## Deflexión de stick que pide [param degrees] deg/s en [param axis], por bisección
## sobre la curva del perfil, que es monótona.
func _stick_for_rate(axis: int, degrees: float) -> float:
	var profile := _controller.get_control_profile()
	var low := 0.0
	var high := 1.0
	for _iteration: int in 48:
		var middle := (low + high) * 0.5
		if profile.get_rate(axis, middle) < degrees:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## Deflexión de stick cuya salida normalizada vale [param ratio] (`docs/03` §3.6).
func _stick_for_normalized(axis: int, ratio: float) -> float:
	var profile := _controller.get_control_profile()
	var low := 0.0
	var high := 1.0
	for _iteration: int in 48:
		var middle := (low + high) * 0.5
		if profile.get_normalized(axis, middle) < ratio:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## Los cuatro comandos de motor en una línea legible.
func _format(commands: Array[float]) -> String:
	return "[%.4f, %.4f, %.4f, %.4f]" % [commands[0], commands[1], commands[2], commands[3]]


func _on_arm_failed(reason_key: String) -> void:
	_arm_failures.append(reason_key)


func _on_armed(mode_key: String) -> void:
	_arm_modes.append(mode_key)


## Suma del empuje estático de las cuatro hélices para un comando común.
func _static_thrust(command: float) -> float:
	var total := 0.0
	for index: int in _motors.size():
		total += _propellers[index].static_thrust(_motors[index].rpm_for_command(command))
	return total


## Arma el dron lejos del suelo con [param commands] y devuelve la velocidad de
## guiñada en rad/s tras 0.4 s simulados. Positiva es morro a la izquierda.
func _measure_yaw(commands: Array[float]) -> float:
	_drone.force_disarm()
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 120.0, 0.0)))
	await wait_physics(2)
	_drone.test_motor_commands = commands
	var _armed_ok := _drone.arm()
	await wait_physics(40)
	var yaw_rate := _drone.get_flight_state().angular_velocity.y
	_drone.force_disarm()
	_drone.test_motor_commands = [0.0, 0.0, 0.0, 0.0]
	return yaw_rate


func _on_respawned() -> void:
	_respawn_count += 1


## El banco mide el dron puro (`docs/03` §11): retira los sistemas de gameplay que
## WP-15 cuelga del `Drone` en `drone_quad.tscn`. Sin esto, tras el minuto de vuelo
## simulado la energía se agota, `set_thrust_scale(0.82)` recorta la autoridad y el
## escalón de tasa de §11.4 no llega al 90 % (pico medido 318 deg/s de 360); y el casco
## podría destruir el dron en las caídas del banco. Mismo criterio que `weapon_check`.
func _stand_down_gameplay_systems() -> void:
	for child_name: StringName in [&"EnergySystem", &"Hull"]:
		var node := _drone.get_node_or_null(NodePath(child_name))
		if node == null:
			continue
		_drone.remove_child(node)
		node.queue_free()
