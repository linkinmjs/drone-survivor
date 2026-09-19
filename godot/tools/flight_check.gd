## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del controlador de vuelo y de la radio (`docs/03` §11, `flight_check`).
##
## Vuela el `drone_rig.tscn` completo —dron, `FlightController` y
## `RadioController` cableados como en el juego— y comprueba lo que el banco de
## pruebas no puede: armado, vuelo estacionario con el lazo de tasa cerrado,
## cambio de modo por acción, vuelco con TURTLE, reaparición, recuperación
## automática con RECOVER y lectura de radio con joypad simulado (`docs/15` §4.1).
##
## Desde WP-07 están los ocho criterios: el 6 (cámara FPV) lo colgó WP-06 y el 7
## (audio de motores y LED de modo) mide el `MotorAudio` y el `ModeLED` que WP-07
## agregó al dron.
##
## Dos detalles de método que valen para cualquier check que toque este rig:
## - La radio se **apaga** ([member RadioController.enabled]) en los criterios
##   donde el check escribe el `FlightCommand` a mano. Si no, cada frame de física
##   la radio lo pisaría con los sticks en reposo, que con un mando de pulgares
##   son acelerador 0.5.
## - Los eventos sintéticos van con `device = 0`, no con `−1`. `docs/15` §4.1 usa
##   −1 porque las entradas del `InputMap` se serializan así y −1 casa con todas;
##   pero `Input.get_joy_axis()` —que es lo que lee `Controls.get_flight_input()`—
##   indexa por dispositivo exacto, y con −1 nunca vería el eje. Un evento con
##   device 0 resuelve las dos cosas: el `InputMap` lo acepta igual, porque la
##   entrada guardada con −1 significa «cualquier dispositivo».
##
## Corre así:
##   godot --headless --path godot res://tools/flight_check.tscn
extends CheckRunner

## Altura a la que se mide el vuelo estacionario, en metros. Bien por encima del
## alcance de 2 m del rayo de efecto suelo.
const HOVER_ALTITUDE: float = 20.0

## Duración de la medida de vuelo estacionario, en segundos (`docs/03` §11.2).
const HOVER_SECONDS: float = 5.0

## Desvío máximo admitido durante ese tiempo, en metros.
const HOVER_TOLERANCE: float = 0.3

## Tiempo que se le da al lazo de altitud para estabilizarse antes de empezar a
## medir, en segundos.
const HOVER_SETTLE: float = 1.5

## Ganancias del controlador de altitud **del check** (`docs/03` §11.2): es un
## lazo PID sobre el acelerador del `FlightCommand`, no parte del juego.
const HOVER_BASE: float = 0.395
const HOVER_KP: float = 0.12
const HOVER_KD: float = 0.12
const HOVER_KI: float = 0.04
const HOVER_INTEGRAL_LIMIT: float = 0.2

## Tiempo máximo que puede tardar TURTLE en dar vuelta el dron, en s (`docs/03` §11.4).
const TURTLE_LIMIT: float = 3.0

## Altura desde la que se prueba RECOVER, en metros. Lo bastante alta para que el
## vuelco y la nivelación entren, y lo bastante baja para que el descenso a 3 m/s
## llegue al suelo dentro de la ventana.
const RECOVER_ALTITUDE: float = 14.0

## Inclinación a la que se lleva HORIZON para disparar RECOVER, en grados: por
## encima de los 60° de `docs/03` §3.2.
const RECOVER_TILT_DEGREES: float = 78.0

## Ventana total de la prueba de RECOVER, en segundos.
const RECOVER_LIMIT: float = 12.0

## Paso de física nominal, en segundos.
const PHYSICS_STEP: float = 0.01

## Eje analógico libre con el que se prueba el switch en banda de eje. Los ejes 0
## a 3 son los de vuelo y el 4 y el 5 son los gatillos de `fire` y `lock_target`.
const SWITCH_AXIS: int = 6

## Banda del switch de prueba, la misma forma que usa un interruptor de radio.
const SWITCH_BAND: Vector2 = Vector2(0.5, 1.0)

## Reproductores que `docs/03` §6 pide: dos por motor.
const AUDIO_PLAYERS: int = 8

## Altura a la que se hace el banco de régimen del criterio de audio, en metros.
## Alto para que el dron no toque el suelo mientras el barrido lo empuja hacia arriba.
const AUDIO_ALTITUDE: float = 60.0

## Ticks de física que se dejan para que el régimen y el volumen se asienten.
const AUDIO_SETTLE_TICKS: int = 90

## Régimen, como fracción de `max_rpm`, con el que se mide el volumen «alto» (§11.7).
const AUDIO_LOUD_RATIO: float = 0.60

## Subida mínima de volumen del ralentí a [constant AUDIO_LOUD_RATIO], en dB.
const AUDIO_RISE_DB: float = 6.0

## Duración del barrido de régimen del criterio de crossfade, en segundos.
const AUDIO_SWEEP_SECONDS: float = 3.0

## Variación máxima de amplitud admitida en el crossfade, en dB (§11.7).
const AUDIO_VARIANCE_DB: float = 6.0

## Por encima de este volumen se considera que un reproductor **se oye**, y por lo
## tanto que cambiarle el loop sería un clic.
const AUDIO_AUDIBLE_DB: float = -40.0

## Ticks que se dan tras desarmar para que los motores se frenen y el audio calle.
const AUDIO_SILENCE_TICKS: int = 200

## Ventana en la que se observa el parpadeo lento del LED, en segundos: algo más de
## un período de [constant ModeLED.IDLE_BLINK_PERIOD].
const LED_BLINK_SECONDS: float = 1.4

## Tolerancia del centro de pantalla en el criterio de cámara, en píxeles (§11.6).
const CAMERA_CENTRE_TOLERANCE: float = 2.0

## Pasos de cabeceo del barrido de direcciones de la cámara.
const CAMERA_PITCH_STEPS: int = 9

## Pasos de guiñada del barrido: 360° en pasos de 10°.
const CAMERA_YAW_STEPS: int = 36

## Cabeceo máximo del barrido, en grados (§11.6).
const CAMERA_PITCH_LIMIT: float = 80.0

## Franja alrededor del borde del campo donde no se exige nada: ahí «se ve» y «no se
## ve» se deciden por un flotante, y no es lo que mide el criterio.
const CAMERA_FIELD_GUARD: float = 0.01

@export var rig_path: NodePath = ^"DroneRig"
@export var respawn_path: NodePath = ^"Respawn"

var _rig: DroneRig = null
var _drone: Drone = null
var _controller: FlightController = null
var _radio: RadioController = null
var _respawn: Node3D = null

var _command: FlightCommand = FlightCommand.new()
var _arm_failures: Array[String] = []
var _arm_modes: Array[String] = []
var _mode_changes: Array[String] = []
var _respawn_count: int = 0
var _hover_integral: float = 0.0

## Color de emisión del LED muestreado en cada modo de vuelo (`docs/03` §7).
var _led_samples: Dictionary[String, Color] = {}


func _run() -> void:
	Engine.physics_ticks_per_second = 100
	_rig = get_node_or_null(rig_path) as DroneRig
	_respawn = get_node_or_null(respawn_path) as Node3D
	if _rig == null or _respawn == null:
		fail("faltan el rig '%s' o el punto de reaparición '%s'"
				% [str(rig_path), str(respawn_path)])
		return
	await wait_physics(2)
	_drone = _rig.get_drone()
	_controller = _rig.get_flight_controller()
	_radio = _rig.get_radio()
	if _drone == null or _controller == null or _radio == null:
		fail("el rig no quedó cableado: dron %s, controlador %s, radio %s"
				% [str(_drone), str(_controller), str(_radio)])
		return
	var _discard := _drone.arm_failed.connect(_on_arm_failed)
	_discard = _drone.armed.connect(_on_armed)
	_discard = _drone.flight_mode_changed.connect(_on_mode_changed)
	_discard = _drone.respawned.connect(_on_respawned)
	print("  rig: %s + %s + %s, modo inicial '%s'"
			% [_drone.name, _controller.name, _radio.name, _drone.get_mode_key()])

	await _check_arming()
	await _check_hover()
	await _check_mode_cycle()
	await _check_turtle()
	await _check_respawn()
	await _check_recover()
	await _check_camera()
	await _check_audio()
	await _check_led_blink()
	await _check_simulated_radio()


## §11.1 — Armar con acelerador alto falla con `ERR_ARM_THROTTLE_HIGH`; con
## acelerador bajo emite `armed("acro")`.
func _check_arming() -> void:
	_radio.enabled = false
	_drone.force_disarm()
	_controller.select_mode(FlightController.MODE_ACRO)
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, HOVER_ALTITUDE, 0.0)))
	await wait_physics(3)
	_arm_failures.clear()
	_arm_modes.clear()

	_send(0.6, 0.0, 0.0, 0.0)
	var high := _drone.arm()
	var reason := _arm_failures[0] if not _arm_failures.is_empty() else "(ninguna)"
	print("  [1] armado con acelerador 0.60 -> %s, arm_failed('%s')" % [str(high), reason])
	expect(not high and not _drone.is_armed(),
			"el dron armó con el acelerador en 0.60 y no debía")
	expect(reason == FlightController.REASON_THROTTLE_HIGH,
			"el motivo fue '%s' y debía ser '%s'"
			% [reason, FlightController.REASON_THROTTLE_HIGH])

	_send(0.0, 0.0, 0.0, 0.0)
	var low := _drone.arm()
	var mode := _arm_modes[0] if not _arm_modes.is_empty() else "(ninguno)"
	print("      armado con acelerador 0.00 -> %s, armed('%s')" % [str(low), mode])
	expect(low and _drone.is_armed(), "el dron no armó con el acelerador al mínimo")
	expect(mode == FlightController.MODE_ACRO,
			"la señal armed llegó con '%s' y debía ser '%s'"
			% [mode, FlightController.MODE_ACRO])


## §11.2 — Con el controlador de altitud del check, el dron flota 5 s dentro de
## ±0.3 m de la altura objetivo.
##
## El check solo escribe el **acelerador**; la actitud la sostiene el lazo de tasa
## en ACRO con los tres sticks centrados, que es justamente lo que se quiere medir.
func _check_hover() -> void:
	_radio.enabled = false
	_drone.force_disarm()
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, HOVER_ALTITUDE, 0.0)))
	_send(0.0, 0.0, 0.0, 0.0)
	await wait_physics(3)
	var ok := _drone.arm()
	expect(ok, "no se pudo armar para la prueba de vuelo estacionario")
	if not ok:
		return
	_hover_integral = 0.0

	for _tick: int in int(HOVER_SETTLE / PHYSICS_STEP):
		_hover_tick()
		await wait_physics(1)

	var drift := 0.0
	var tilt := 0.0
	for _tick: int in int(HOVER_SECONDS / PHYSICS_STEP):
		_hover_tick()
		await wait_physics(1)
		drift = maxf(drift, absf(_drone.global_transform.origin.y - HOVER_ALTITUDE))
		var euler := _drone.get_flight_state().euler
		tilt = maxf(tilt, maxf(absf(euler.x), absf(euler.y)))
	var throttle := _drone.get_throttle()
	_drone.force_disarm()
	print("  [2] vuelo estacionario: %.1f s, desvío máximo %.4f m (límite %.2f m), acelerador final %.4f, inclinación máxima %.3f°"
			% [HOVER_SECONDS, drift, HOVER_TOLERANCE, throttle, rad_to_deg(tilt)])
	expect(drift <= HOVER_TOLERANCE,
			"el dron se apartó %.4f m de la altura objetivo y el límite es %.2f m"
			% [drift, HOVER_TOLERANCE])
	expect(rad_to_deg(tilt) < 5.0,
			"el dron se inclinó %.2f° flotando con los sticks centrados" % rad_to_deg(tilt))


## §11.3 — La acción `cycle_flight_modes` lleva a HORIZON y vuelve a ACRO.
func _check_mode_cycle() -> void:
	_radio.enabled = true
	_drone.force_disarm()
	_controller.select_mode(FlightController.MODE_ACRO)
	await wait_frames(2)
	_mode_changes.clear()

	await _press_action(&"cycle_flight_modes")
	var first := _drone.get_mode_key()
	await _press_action(&"cycle_flight_modes")
	var second := _drone.get_mode_key()
	print("  [3] cycle_flight_modes: '%s' -> '%s', señales %s"
			% [first, second, str(_mode_changes)])
	expect(first == FlightController.MODE_HORIZON,
			"el primer cycle_flight_modes dejó el modo en '%s' y debía ser '%s'"
			% [first, FlightController.MODE_HORIZON])
	expect(second == FlightController.MODE_ACRO,
			"el segundo cycle_flight_modes dejó el modo en '%s' y debía ser '%s'"
			% [second, FlightController.MODE_ACRO])
	expect(_mode_changes.size() == 2 and _mode_changes[0] == FlightController.MODE_HORIZON
			and _mode_changes[1] == FlightController.MODE_ACRO,
			"flight_mode_changed emitió %s y se esperaba ['horizon', 'acro']"
			% str(_mode_changes))


## §11.4 — Volcado boca abajo en el suelo, TURTLE lo endereza en menos de 3 s.
func _check_turtle() -> void:
	_radio.enabled = false
	_drone.force_disarm()
	_controller.select_mode(FlightController.MODE_ACRO)
	# Boca abajo: 180° de alabeo, apoyado sobre las esferas de los motores.
	var upside_down := Basis.IDENTITY.rotated(Vector3(0.0, 0.0, 1.0), PI)
	_drone.reset_to(Transform3D(upside_down, Vector3(0.0, 0.05, 0.0)))
	_send(0.0, 0.0, 0.0, 0.0)
	await wait_physics(30)
	var settled := _drone.get_flight_state().basis.y.dot(Vector3.UP)
	expect(settled < -0.7, "el dron no quedó boca abajo antes de TURTLE (y·UP = %.3f)"
			% settled)

	# `mode_turtle` mantenido al armar, que es lo que hace `RadioController`.
	_controller.select_mode(FlightController.MODE_TURTLE)
	var entered := _drone.get_mode_key() == FlightController.MODE_TURTLE
	expect(entered, "TURTLE no se pudo elegir estando desarmado y boca abajo (modo '%s')"
			% _drone.get_mode_key())
	await wait_frames(2)
	# El LED de §7 se muestrea acá: TURTLE no se puede elegir desde `_check_audio`.
	_sample_led()
	_send(0.0, 1.0, 0.0, 0.0)
	var ok := _drone.arm()
	expect(ok, "no se pudo armar en TURTLE")
	if not entered or not ok:
		return

	var elapsed := 0.0
	var upright := -1.0
	var best := settled
	var reverse := 0.0
	for _tick: int in int((TURTLE_LIMIT + 0.5) / PHYSICS_STEP):
		_send(0.0, 1.0, 0.0, 0.0)
		await wait_physics(1)
		elapsed += PHYSICS_STEP
		for rpm: float in _drone.get_motor_rpm():
			reverse = minf(reverse, rpm)
		var dot := _drone.get_flight_state().basis.y.dot(Vector3.UP)
		best = maxf(best, dot)
		if upright < 0.0 and dot > FlightController.TURTLE_UPRIGHT_DOT:
			upright = elapsed
			break
	var mode := _drone.get_mode_key()
	var armed := _drone.is_armed()
	_drone.force_disarm()
	print("  [4] TURTLE: enderezó en %.2f s (límite %.1f s), y·UP máximo %.3f, régimen mínimo %.0f rpm, al salir modo '%s' y armado %s"
			% [upright, TURTLE_LIMIT, best, reverse, mode, str(armed)])
	expect(upright >= 0.0 and upright < TURTLE_LIMIT,
			"TURTLE no dio vuelta el dron en %.1f s (y·UP máximo %.3f)" % [TURTLE_LIMIT, best])
	expect(mode == FlightController.MODE_ACRO and not armed,
			"tras enderezarse el dron quedó en '%s' y armado %s, y debía quedar en ACRO desarmado"
			% [mode, str(armed)])


## §11.5 — La acción `respawn` emite `reset_requested`, el rig reaparece el dron y
## la transformada coincide con la del punto de reaparición.
func _check_respawn() -> void:
	_radio.enabled = true
	_drone.force_disarm()
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(40.0, 60.0, -25.0)))
	await wait_physics(3)
	_respawn_count = 0

	await _press_action(&"respawn")
	await wait_physics(3)
	var goal := _respawn.global_transform
	var distance := _drone.global_transform.origin.distance_to(goal.origin)
	var angle := _drone.global_transform.basis.get_rotation_quaternion() \
			.angle_to(goal.basis.get_rotation_quaternion())
	print("  [5] respawn: %d señal(es) respawned, desvío %.4f m y %.3f° del punto de reaparición"
			% [_respawn_count, distance, rad_to_deg(angle)])
	expect(_respawn_count == 1,
			"la acción respawn produjo %d señales respawned en vez de 1" % _respawn_count)
	expect(distance < 0.1, "el dron quedó a %.4f m del punto de reaparición" % distance)
	expect(rad_to_deg(angle) < 2.0,
			"el dron quedó %.3f° girado respecto del punto de reaparición" % rad_to_deg(angle))


## §4 — Radio simulada: con joypad simulado, el `FlightCommand` refleja los cuatro
## ejes y un switch en banda de eje dispara `mode_horizon`.
func _check_simulated_radio() -> void:
	_radio.enabled = true
	_drone.force_disarm()
	_controller.select_mode(FlightController.MODE_ACRO)
	var previous_assume := Controls.assume_joypad
	var previous_device := Controls.active_device
	Controls.assume_joypad = true
	Controls.update_active_device(0)

	# Acelerador arriba, alabeo a la derecha, morro arriba y guiñada a la izquierda.
	await _inject_axes({1: -1.0, 2: 1.0, 3: -1.0, 0: -1.0})
	await wait_physics(3)
	var command := _drone.get_command()
	var left := _radio.get_left_stick()
	var right := _radio.get_right_stick()
	print("  [7] radio simulada: ejes (t %.3f, r %.3f, p %.3f, y %.3f), stick izq %s, der %s"
			% [command.throttle, command.roll, command.pitch, command.yaw,
			str(left), str(right)])
	expect_near(command.throttle, 1.0, 0.01, "el acelerador con el stick arriba")
	expect_near(command.roll, 1.0, 0.01, "el alabeo con el stick a la derecha")
	expect_near(command.pitch, 1.0, 0.01, "el cabeceo con el stick arriba (morro arriba)")
	expect_near(command.yaw, 1.0, 0.01, "la guiñada con el stick a la izquierda")
	expect_near(right.x, 1.0, 0.01, "get_right_stick().x sigue al alabeo")
	expect_near(left.y, 1.0, 0.01, "get_left_stick().y sigue al acelerador")

	await _inject_axes({1: 0.0, 2: 0.0, 3: 0.0, 0: 0.0})
	await wait_physics(3)
	var centred := _drone.get_command()
	print("      con los sticks centrados: acelerador %.3f, alabeo %.3f"
			% [centred.throttle, centred.roll])
	expect_near(centred.throttle, 0.5, 0.01,
			"un stick de pulgares centrado da acelerador 0.5 (docs/03 §4)")
	expect_near(centred.roll, 0.0, 0.01, "el alabeo vuelve a cero con el stick centrado")

	# Switch en banda de eje: `mode_horizon` atado al eje libre SWITCH_AXIS.
	var action := Controls.get_action(&"mode_horizon")
	var backup := action.duplicate_action()
	action.bind_axis(SWITCH_AXIS, SWITCH_BAND.x, SWITCH_BAND.y)
	_mode_changes.clear()
	await _inject_axes({SWITCH_AXIS: -1.0})
	await wait_physics(4)
	await _inject_axes({SWITCH_AXIS: 0.8})
	await wait_physics(6)
	var mode := _drone.get_mode_key()
	print("      switch en banda [%.2f, %.2f] del eje %d -> modo '%s', señales %s"
			% [SWITCH_BAND.x, SWITCH_BAND.y, SWITCH_AXIS, mode, str(_mode_changes)])
	expect(mode == FlightController.MODE_HORIZON,
			"el switch en banda de eje dejó el modo en '%s' y debía ser '%s'"
			% [mode, FlightController.MODE_HORIZON])

	# Restaurar lo que el check tocó de `Controls`, con el tipo que tenía: si el
	# binding original era de eje, `bind_button()` lo convertiría en botón.
	if backup.type == ControllerAction.Type.AXIS:
		action.bind_axis(backup.axis, backup.axis_min, backup.axis_max)
	else:
		action.bind_button(backup.button)
	await _inject_axes({SWITCH_AXIS: -1.0})
	Controls.assume_joypad = previous_assume
	Controls.update_active_device(previous_device)
	_radio.enabled = false
	_controller.select_mode(FlightController.MODE_ACRO)


## §3.2 — RECOVER: volcado más de 60° durante 0.3 s en HORIZON, el controlador
## entra solo en recuperación, nivela, desciende y desarma al llegar al suelo.
##
## El vuelco se consigue subiendo el límite de ángulo de HORIZON a
## [constant RECOVER_TILT_DEGREES] y mandando el stick a fondo, que es la única
## forma limpia de sostener 60° en un modo cuyo trabajo es justamente no pasar de
## 35°. La otra entrada de §3.2 —`crashed` por encima de 12 m/s— desemboca en el
## mismo `_enter_recover()`.
func _check_recover() -> void:
	_radio.enabled = false
	_drone.force_disarm()
	_controller.select_mode(FlightController.MODE_HORIZON)
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, RECOVER_ALTITUDE, 0.0)))
	_send(0.0, 0.0, 0.0, 0.0)
	await wait_physics(3)
	var ok := _drone.arm()
	expect(ok, "no se pudo armar para la prueba de RECOVER")
	if not ok:
		return
	_mode_changes.clear()
	_controller.angle_limit_degrees = RECOVER_TILT_DEGREES
	_send(HOVER_BASE, 1.0, 0.0, 0.0)

	var elapsed := 0.0
	var entered := -1.0
	var levelled := -1.0
	var descent := 0.0
	var disarmed := -1.0
	for _tick: int in int(RECOVER_LIMIT / PHYSICS_STEP):
		await wait_physics(1)
		elapsed += PHYSICS_STEP
		var mode := _drone.get_mode_key()
		if entered < 0.0 and mode == FlightController.MODE_RECOVER:
			entered = elapsed
			# Lo mismo que en TURTLE: RECOVER solo se alcanza desde acá.
			_sample_led()
			# El piloto suelta: RECOVER ignora los sticks de actitud igual.
			_controller.angle_limit_degrees = 35.0
			_send(HOVER_BASE, 0.0, 0.0, 0.0)
			continue
		if entered < 0.0:
			continue
		var euler := _drone.get_flight_state().euler
		var tilt := maxf(absf(euler.x), absf(euler.y))
		if levelled < 0.0 and rad_to_deg(tilt) < FlightController.RECOVER_EXIT_DEGREES:
			levelled = elapsed - entered
		if levelled >= 0.0:
			descent = minf(descent, _drone.linear_velocity.y)
		if not _drone.is_armed():
			disarmed = elapsed - entered
			break
	_controller.angle_limit_degrees = 35.0
	var final_mode := _drone.get_mode_key()
	var agl := _drone.get_flight_state().altitude_agl
	_drone.force_disarm()
	print("  [6] RECOVER: entró a los %.2f s, niveló en %.2f s, descenso máximo %.2f m/s, desarmó en %.2f s a %.2f m AGL, modo final '%s'"
			% [entered, levelled, descent, disarmed, agl, final_mode])
	expect(entered >= 0.0,
			"RECOVER no se activó con más de %.0f° de inclinación en HORIZON"
			% FlightController.RECOVER_ANGLE_DEGREES)
	expect(levelled >= 0.0 and levelled < 1.5,
			"RECOVER tardó %.2f s en bajar de %.0f° de inclinación"
			% [levelled, FlightController.RECOVER_EXIT_DEGREES])
	expect(descent < -1.0 and descent > -6.0,
			"RECOVER descendió a %.2f m/s y la consigna de §3.2 es %.1f m/s"
			% [descent, FlightController.RECOVER_DESCENT_SPEED])
	expect(disarmed >= 0.0 and agl >= 0.0 and agl < 1.5,
			"RECOVER no desarmó cerca del suelo (desarme a los %.2f s, %.2f m AGL)"
			% [disarmed, agl])
	expect(final_mode == FlightController.MODE_HORIZON,
			"al terminar RECOVER el modo quedó en '%s' y debía volver al anterior ('%s')"
			% [final_mode, FlightController.MODE_HORIZON])


## §11.6 — Cámara FPV: `project_direction(−basis.z)` cae en el centro de la pantalla
## ±2 px en los tres modos de ojo de pez y un barrido de 360° de guiñada por ±80° de
## cabeceo no produce ningún `NAN` dentro del campo ni ningún valor finito fuera.
##
## Lo fino de la proyección —marcadores, `edge_clamp`, monotonía del remapeo, fórmula
## equidistante y capturas— lo mide `hud_projection_check` (`docs/12` §9.1); acá se
## verifica el criterio de §11.6 sobre el rig real, que es donde la cámara cuelga del
## dron y hereda su actitud.
func _check_camera() -> void:
	var camera := _rig.get_fpv_camera()
	if camera == null:
		fail("el rig no expone la cámara FPV (docs/03 §5)")
		return
	var original_mode := int(Graphics.fisheye_mode)
	var centre := get_viewport().get_visible_rect().size * 0.5
	for mode: int in [Graphics.FisheyeMode.OFF, Graphics.FisheyeMode.FAST,
			Graphics.FisheyeMode.FULL]:
		Graphics.fisheye_mode = int(mode) as Graphics.FisheyeMode
		Graphics.update_fisheye()
		await wait_frames(2)
		var hfov := camera.get_fisheye_hfov()
		var forward := camera.project_direction(-camera.global_basis.z)
		var error := INF
		if forward.is_finite():
			error = forward.distance_to(centre)
		var limit := deg_to_rad(hfov) * 0.5 if hfov > 0.0 else acos(clampf(camera.near, -1.0, 1.0))
		var inside_nan := 0
		var outside_finite := 0
		var samples := 0
		for pitch_step: int in CAMERA_PITCH_STEPS:
			var pitch := deg_to_rad(lerpf(-CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT,
					float(pitch_step) / float(CAMERA_PITCH_STEPS - 1)))
			for yaw_step: int in CAMERA_YAW_STEPS:
				var yaw := TAU * float(yaw_step) / float(CAMERA_YAW_STEPS)
				var local := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
				var theta := acos(clampf(-local.z, -1.0, 1.0))
				var projected := camera.project_direction(
						camera.global_basis.orthonormalized() * local)
				samples += 1
				if absf(theta - limit) < CAMERA_FIELD_GUARD:
					continue
				if theta < limit and not projected.is_finite():
					inside_nan += 1
				elif theta > limit and projected.is_finite():
					outside_finite += 1
		print("  [§11.6] cámara %s (hfov %.1f°): centro a %.4f px, %d muestras, %d NAN dentro del campo, %d finitos fuera"
				% [_fisheye_name(mode), hfov, error, samples, inside_nan, outside_finite])
		expect(forward.is_finite() and error <= CAMERA_CENTRE_TOLERANCE,
				"en %s la dirección de la cámara cayó a %.3f px del centro (tolerancia %.1f)"
				% [_fisheye_name(mode), error, CAMERA_CENTRE_TOLERANCE])
		expect(inside_nan == 0, "en %s hubo %d direcciones del campo que dieron NAN"
				% [_fisheye_name(mode), inside_nan])
		expect(outside_finite == 0,
				"en %s hubo %d direcciones fuera del campo que no dieron NAN"
				% [_fisheye_name(mode), outside_finite])
	Graphics.fisheye_mode = original_mode as Graphics.FisheyeMode
	Graphics.update_fisheye()


## Nombre legible de un modo de ojo de pez.
func _fisheye_name(mode: int) -> String:
	match mode:
		Graphics.FisheyeMode.FAST:
			return "FAST"
		Graphics.FisheyeMode.FULL:
			return "FULL"
		_:
			return "OFF"


## §11.7 — Audio de motores y LED de modo (`docs/03` §6 y §7).
##
## Cuatro medidas sobre el rig real:
##
## 1. **Ocho reproductores en el bus `Motors`**, dos por motor.
## 2. **El volumen sube con el régimen**: se compara el volumen medio en ralentí con
##    el del 60 % de `max_rpm`, que es lo que pide §11.7.
## 3. **Sin clics en el crossfade**: barriendo el régimen de 0 a 1 en 3 s, la
##    amplitud combinada de las dos voces de un motor no se aparta de su envolvente
##    más de 6 dB —ese apartamiento *es* la «varianza de amplitud entre bandas» de
##    §11.7: con el crossfade puesto vale cero, y un salto de banda a pelo lo
##    dispararía— y ningún reproductor **que se esté oyendo** cambia de loop, que es
##    la otra forma de meter un clic.
## 4. **Al desarmar** los ocho quedan en −80 dB o parados.
##
## Y el LED: el color de emisión del material cambia con el modo —los cuatro modos
## se muestrean, TURTLE y RECOVER desde los criterios §11.4 y §3.2, que son los que
## saben llegar a esos modos— y parpadea con el dron desarmado.
##
## El barrido se hace con [member Drone.test_motor_commands] y el controlador
## desenganchado: lo que se mide es la traducción de régimen a volumen, no el lazo
## de control, y un barrido de acelerador pilotado no pasaría por todas las bandas.
func _check_audio() -> void:
	var audio := _rig.get_motor_audio()
	var led := _rig.get_mode_led()
	if audio == null or led == null:
		fail("el rig no expone MotorAudio (%s) o ModeLED (%s) (docs/03 §6 y §7)"
				% [str(audio), str(led)])
		return

	# --- 1) Ocho reproductores en el bus `Motors` ---------------------------------------
	var players := audio.get_players()
	var on_bus := 0
	for player: AudioStreamPlayer in players:
		if player.bus == MotorAudio.BUS:
			on_bus += 1
	print("  [§11.7] audio: %d reproductores, %d en el bus '%s', índice de bus %d"
			% [players.size(), on_bus, String(MotorAudio.BUS),
			AudioServer.get_bus_index(MotorAudio.BUS)])
	expect(players.size() == AUDIO_PLAYERS,
			"MotorAudio tiene %d reproductores y §6 pide %d (dos por motor)"
			% [players.size(), AUDIO_PLAYERS])
	expect(on_bus == players.size(),
			"%d de %d reproductores no están en el bus '%s'"
			% [players.size() - on_bus, players.size(), String(MotorAudio.BUS)])

	# --- Preparar un banco de régimen sin lazo de control --------------------------------
	_radio.enabled = false
	_drone.force_disarm()
	_controller.select_mode(FlightController.MODE_ACRO)
	_send(0.0, 0.0, 0.0, 0.0)
	_drone.set_controller(null)
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, AUDIO_ALTITUDE, 0.0)))
	_set_motor_commands(0.0)
	await wait_physics(3)
	var armed := _drone.arm()
	expect(armed, "no se pudo armar para la prueba de audio")
	if not armed:
		_drone.set_controller(_controller)
		return

	# --- 2) El volumen sube con el régimen ------------------------------------------------
	await wait_physics(AUDIO_SETTLE_TICKS)
	var idle_db := _mean_motor_db(audio)
	var idle_players := _mean_player_db(audio)
	var idle_rpm := _mean_rpm()
	_set_motor_commands(_command_for_ratio(AUDIO_LOUD_RATIO))
	await wait_physics(AUDIO_SETTLE_TICKS)
	var loud_db := _mean_motor_db(audio)
	var loud_players := _mean_player_db(audio)
	print("      volumen: ralentí %.2f dB (media por reproductor %.2f dB, %.0f rpm) -> %.0f %% de max_rpm %.2f dB (media %.2f dB, %.0f rpm)"
			% [idle_db, idle_players, idle_rpm, AUDIO_LOUD_RATIO * 100.0, loud_db,
			loud_players, _mean_rpm()])
	expect(loud_db > idle_db + AUDIO_RISE_DB,
			"el volumen solo subió %.2f dB del ralentí al %.0f %% de régimen (mínimo %.1f dB)"
			% [loud_db - idle_db, AUDIO_LOUD_RATIO * 100.0, AUDIO_RISE_DB])
	expect(loud_players > idle_players,
			"el volumen medio por reproductor no subió con el régimen (%.2f -> %.2f dB)"
			% [idle_players, loud_players])

	# --- 3) Barrido 0 -> 1 en 3 s: rizado del crossfade y cortes audibles -----------------
	_set_motor_commands(0.0)
	await wait_physics(AUDIO_SETTLE_TICKS)
	var ticks := int(AUDIO_SWEEP_SECONDS / PHYSICS_STEP)
	var streams: Array[AudioStream] = []
	var volumes: Array[float] = []
	for player: AudioStreamPlayer in players:
		streams.append(player.stream)
		volumes.append(player.volume_db)
	var ripple_low := INF
	var ripple_high := -INF
	var jump := 0.0
	var cuts := 0
	var previous := _mean_motor_db(audio)
	for tick: int in ticks:
		_set_motor_commands(float(tick) / float(maxi(ticks - 1, 1)))
		await wait_physics(1)
		for motor: int in _drone.get_motors().size():
			var residual := audio.get_motor_volume_db(motor) \
					- audio.get_motor_envelope_db(motor)
			ripple_low = minf(ripple_low, residual)
			ripple_high = maxf(ripple_high, residual)
		var combined := _mean_motor_db(audio)
		jump = maxf(jump, absf(combined - previous))
		previous = combined
		for index: int in players.size():
			var player := players[index]
			var audible := maxf(volumes[index], player.volume_db) > AUDIO_AUDIBLE_DB
			if audible and player.stream != streams[index]:
				cuts += 1
			streams[index] = player.stream
			volumes[index] = player.volume_db
	var spread := ripple_high - ripple_low
	print("      crossfade: rizado sobre la envolvente [%.3f, %.3f] dB (varianza %.3f dB, límite %.1f), salto máximo entre frames %.3f dB, %d cortes audibles"
			% [ripple_low, ripple_high, spread, AUDIO_VARIANCE_DB, jump, cuts])
	expect(spread < AUDIO_VARIANCE_DB,
			"la amplitud combinada varía %.2f dB entre bandas y §11.7 admite %.1f dB"
			% [spread, AUDIO_VARIANCE_DB])
	expect(jump <= AUDIO_VARIANCE_DB,
			"el volumen combinado saltó %.2f dB entre dos frames (límite %.1f dB)"
			% [jump, AUDIO_VARIANCE_DB])
	expect(cuts == 0,
			"%d reproductores cambiaron de loop mientras se oían: eso es un clic" % cuts)

	# --- 4) Al desarmar, los ocho en silencio o parados -----------------------------------
	_set_motor_commands(0.0)
	_drone.force_disarm()
	await wait_physics(AUDIO_SILENCE_TICKS)
	var loud_left := 0
	var still_playing := 0
	for player: AudioStreamPlayer in players:
		if player.playing:
			still_playing += 1
			if player.volume_db > MotorAudio.SILENT_DB + 0.5:
				loud_left += 1
	print("      tras desarmar: %d reproductores sonando, %d por encima de %.0f dB, voces activas %d"
			% [still_playing, loud_left, MotorAudio.SILENT_DB, audio.get_active_voice_count()])
	expect(loud_left == 0,
			"%d reproductores quedaron por encima de %.0f dB con el dron desarmado"
			% [loud_left, MotorAudio.SILENT_DB])

	_drone.set_controller(_controller)
	_drone.reset_to(_respawn.global_transform)
	await wait_physics(2)
	await _check_led(led)


## §7 — LED de modo: un color por modo y parpadeo con el dron desarmado.
func _check_led(led: ModeLED) -> void:
	_led_samples["acro"] = await _sample_led_mode(led, FlightController.MODE_ACRO)
	_led_samples["horizon"] = await _sample_led_mode(led, FlightController.MODE_HORIZON)
	_controller.select_mode(FlightController.MODE_ACRO)
	var seen: Array[Color] = []
	for mode_key: String in ["acro", "horizon", "turtle", "recover"]:
		var expected: Color = led.color_for_mode(mode_key)
		var measured: Color = _led_samples.get(mode_key, Color(0, 0, 0, 0))
		print("  [§7] LED en '%s': emisión %s, esperada %s"
				% [mode_key, str(measured), str(expected)])
		expect(measured.a > 0.0, "no se llegó a muestrear el LED en el modo '%s'" % mode_key)
		expect(measured.is_equal_approx(expected),
				"el LED en '%s' emitió %s y el color de §7 es %s"
				% [mode_key, str(measured), str(expected)])
		for other: Color in seen:
			expect(not other.is_equal_approx(measured),
					"dos modos comparten el color de LED %s" % str(measured))
		seen.append(measured)


## Muestrea el color del LED en un modo al que se puede ir con `select_mode()`.
func _sample_led_mode(led: ModeLED, mode_key: String) -> Color:
	_controller.select_mode(mode_key)
	await wait_frames(2)
	return led.get_emission()


## Guarda el color del LED bajo el modo que el dron tiene puesto en este instante.
## Lo llaman §11.4 y §3.2, que son los criterios que saben entrar en TURTLE y en
## RECOVER; el LED no tiene forma de llegar solo a esos modos.
func _sample_led() -> void:
	var led := _rig.get_mode_led()
	if led == null:
		return
	_led_samples[_drone.get_mode_key()] = led.get_emission()


## Parpadeo del LED con el dron desarmado y en un armado rechazado (`docs/03` §7).
func _check_led_blink() -> void:
	var led := _rig.get_mode_led()
	if led == null:
		return
	_radio.enabled = false
	_drone.force_disarm()
	await wait_frames(2)
	var lit := 0
	var dark := 0
	var frames := int(LED_BLINK_SECONDS / PHYSICS_STEP)
	for _tick: int in frames:
		await wait_physics(1)
		if led.get_emission_energy() > 0.0:
			lit += 1
		else:
			dark += 1
	print("  [§7] parpadeo desarmado en %.1f s: %d frames encendido, %d apagado (período %.1f s)"
			% [LED_BLINK_SECONDS, lit, dark, ModeLED.IDLE_BLINK_PERIOD])
	expect(lit > 0 and dark > 0,
			"el LED no parpadeó con el dron desarmado (%d encendido, %d apagado)" % [lit, dark])

	# Armado rechazado: tres parpadeos rápidos.
	_send(0.9, 0.0, 0.0, 0.0)
	var refused := _drone.arm()
	await wait_frames(2)
	var alerting := led.is_alerting()
	var edges := 0
	var previous := led.get_emission_energy() > 0.0
	var alert_frames := int((float(ModeLED.ALERT_BLINKS) * ModeLED.ALERT_BLINK_PERIOD)
			/ PHYSICS_STEP)
	for _tick: int in alert_frames:
		await wait_physics(1)
		var now := led.get_emission_energy() > 0.0
		if now != previous:
			edges += 1
		previous = now
	_send(0.0, 0.0, 0.0, 0.0)
	print("      armado rechazado (%s): alerta %s, %d cambios de estado en %.2f s (mínimo %d)"
			% [str(refused), str(alerting), edges,
			float(ModeLED.ALERT_BLINKS) * ModeLED.ALERT_BLINK_PERIOD, ModeLED.ALERT_BLINKS])
	expect(not refused, "el dron armó con el acelerador a 0.90 y no debía")
	expect(alerting, "arm_failed no disparó el parpadeo rápido del LED")
	expect(edges >= ModeLED.ALERT_BLINKS,
			"el parpadeo rápido dio %d cambios de estado y §7 pide %d parpadeos"
			% [edges, ModeLED.ALERT_BLINKS])


## Media de la amplitud combinada de los cuatro motores, en dB.
func _mean_motor_db(audio: MotorAudio) -> float:
	var motors := _drone.get_motors().size()
	if motors == 0:
		return MotorAudio.SILENT_DB
	var total := 0.0
	for index: int in motors:
		total += audio.get_motor_volume_db(index)
	return total / float(motors)


## Media del `volume_db` de los ocho reproductores, que es la magnitud literal de
## §11.7 («el volumen sube con el régimen»).
func _mean_player_db(audio: MotorAudio) -> float:
	var players := audio.get_players()
	if players.is_empty():
		return MotorAudio.SILENT_DB
	var total := 0.0
	for player: AudioStreamPlayer in players:
		total += player.volume_db
	return total / float(players.size())


## Régimen medio de los cuatro motores, en rpm.
func _mean_rpm() -> float:
	var values := _drone.get_motor_rpm()
	if values.is_empty():
		return 0.0
	var total := 0.0
	for rpm: float in values:
		total += rpm
	return total / float(values.size())


## Escribe el mismo comando en los cuatro motores de prueba.
func _set_motor_commands(value: float) -> void:
	var commands: Array[float] = [value, value, value, value]
	_drone.test_motor_commands = commands


## Comando de motor que deja el régimen en [param ratio] de `max_rpm`
## (`docs/03` §2.2: `rpm = idle + cmd · (max − idle)`).
func _command_for_ratio(ratio: float) -> float:
	var motors := _drone.get_motors()
	if motors.is_empty():
		return ratio
	var motor := motors[0]
	var span := motor.max_rpm - motor.idle_rpm
	if span <= 0.0:
		return ratio
	return clampf((ratio * motor.max_rpm - motor.idle_rpm) / span, 0.0, 1.0)


# --- Utilidades -------------------------------------------------------------------------------


## Un paso del controlador de altitud del check: PID sobre el acelerador.
func _hover_tick() -> void:
	var error := HOVER_ALTITUDE - _drone.global_transform.origin.y
	_hover_integral = clampf(_hover_integral + HOVER_KI * error * PHYSICS_STEP,
			-HOVER_INTEGRAL_LIMIT, HOVER_INTEGRAL_LIMIT)
	var throttle := HOVER_BASE + HOVER_KP * error - HOVER_KD * _drone.linear_velocity.y \
			+ _hover_integral
	_send(clampf(throttle, 0.0, 1.0), 0.0, 0.0, 0.0)


## Escribe el `FlightCommand` a mano, como haría la radio.
func _send(throttle: float, roll: float, pitch: float, yaw: float) -> void:
	_command.set_axes(throttle, roll, pitch, yaw)
	_drone.update_command(_command)


## Presiona y suelta una acción con un `InputEventAction` sintético, que es la
## única forma de que `_unhandled_input` la vea (`Input.action_press` no genera
## evento, solo cambia el estado interno de `Input`).
func _press_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)
	await wait_frames(3)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await wait_frames(3)


## Manda al bucle de entrada un `InputEventJoypadMotion` por cada `{eje: valor}`
## y espera a que `Input` vacíe su buffer (`docs/15` §4.1).
func _inject_axes(values: Dictionary[int, float]) -> void:
	for axis: int in values:
		var motion := InputEventJoypadMotion.new()
		motion.device = 0
		motion.axis = axis as JoyAxis
		motion.axis_value = float(values[axis])
		Input.parse_input_event(motion)
	await wait_frames(3)


func _on_arm_failed(reason_key: String) -> void:
	_arm_failures.append(reason_key)


func _on_armed(mode_key: String) -> void:
	_arm_modes.append(mode_key)


func _on_mode_changed(mode_key: String) -> void:
	_mode_changes.append(mode_key)


func _on_respawned() -> void:
	_respawn_count += 1
