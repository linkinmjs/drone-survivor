## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Controlador de vuelo del cuadricóptero: modos, armado, lazo de tasa y
## mezclador con air mode (`docs/03` §3).
##
## Vive como hijo del [Drone] y se engancha en su [member Drone.controller]. El
## dron lo llama una vez por sub-paso —1 000 Hz con el paso nominal de 100 Hz—
## con [method integrate], que devuelve los cuatro comandos de motor en el orden
## del mezclador de §3.5.
##
## Cadena de una pasada:
## 1. Transiciones de modo (§3.2): entrada y salida de RECOVER, salida de TURTLE.
## 2. Velocidad angular objetivo por eje, en la convención de piloto de
##    [method FlightState.rates]: en ACRO la da el [ControlProfile] directamente;
##    en HORIZON sale de un lazo externo de ángulo; en RECOVER, de nivelar.
## 3. Tres [PIDController] de tasa (§3.4).
## 4. Mezclador X con air mode (§3.5).
##
## TURTLE se salta los pasos 2 a 4: es lazo abierto, dos motores en reversa.
##
## Convención de signos, la misma de §3.5 y de [FlightCommand]: alabeo positivo =
## ala derecha abajo, cabeceo positivo = morro arriba, guiñada positiva = morro a
## la izquierda. Ojo con [method FlightState.rates] y con [member FlightState.euler]:
## los dos vienen ya convertidos a esa convención por WP-04 (el alabeo de piloto es
## el **opuesto** de la rotación sobre `+Z`), así que aquí se comparan tal cual, sin
## volver a cambiarles el signo.
##
## Discrepancia registrada con `docs/03` §3.5 — **signo del cabeceo en el
## mezclador**. §3.5 dice dos cosas que no pueden ser ciertas a la vez: en el
## texto, que «cabeceo positivo = morro arriba»; en las fórmulas, que
## `m3 = T − r + p + y` y `m4 = T + r + p − y`, o sea que un `p` positivo sube los
## dos motores **traseros** (M3 y M4, en `z = +0.085`). Levantar la cola es bajar
## el morro: la fórmula describe morro **abajo**. Manda la fórmula, porque es la
## que fija los signos del mezclador y la que comprueba `flight_bench` §11.12, y
## porque las otras dos filas sí son coherentes con su texto (`r` positivo sube los
## motores de la izquierda, que es ala derecha abajo; `y` positivo sube los dos CW,
## que es morro a la izquierda). El lazo de cabeceo trabaja en la convención de
## piloto de [FlightState] —morro arriba positivo, la misma de [FlightCommand]— y
## su salida entra al mezclador **negada**, en [method integrate]. Medido: con el
## signo sin negar el dron se va en tumbo a 2 800 deg/s en menos de medio segundo,
## porque el lazo de cabeceo queda realimentado en positivo.
##
## Discrepancia registrada con `docs/03` §3.3 — **acelerador de armado con mando de
## pulgares**. §4 fija `throttle = (eje + 1)/2`, o sea 0.5 con el stick centrado, y
## §3.3 exige `throttle < 0.02` para armar. Con un gamepad de retorno al centro las
## dos cosas juntas significan que **hay que bajar el stick a fondo para armar**,
## que es lo que hace el check. No es un error de la especificación, pero conviene
## dejarlo escrito porque parece uno la primera vez que se prueba.
class_name FlightController extends Node

## Se emite al armar con éxito, con la clave del modo activo.
signal armed(mode_key: String)

## Se emite al desarmar, por cualquier vía.
signal disarmed()

## Se emite cuando un intento de armado es rechazado (`docs/03` §3.3).
signal arm_failed(reason_key: String)

## Se emite en cada cambio de modo, incluido el automático a RECOVER.
signal flight_mode_changed(mode_key: String)

## Modo acrobático: los sticks mandan velocidad angular. Es el modo por defecto.
const MODE_ACRO: String = "acro"

## Modo asistido: los sticks mandan ángulo de alabeo y cabeceo.
const MODE_HORIZON: String = "horizon"

## Modo tortuga: dos motores en reversa para dar vuelta el dron en el suelo.
const MODE_TURTLE: String = "turtle"

## Modo de recuperación automática: nivela y desciende.
const MODE_RECOVER: String = "recover"

## Claves de fallo de armado (`docs/03` §3.3).
const REASON_THROTTLE_HIGH: String = "ERR_ARM_THROTTLE_HIGH"
const REASON_RECOVERING: String = "ERR_ARM_RECOVERING"
const REASON_NO_ENERGY: String = "ERR_ARM_NO_ENERGY"

## Acelerador por debajo del cual se admite armar (`docs/03` §3.3).
const ARM_THROTTLE_LIMIT: float = 0.02

## Comando mínimo de motor con el dron armado: la reserva de autoridad del air
## mode (`docs/03` §3.5).
const MIXER_IDLE: float = 0.05

## Inclinación a partir de la cual, en HORIZON, empieza a contar el reloj de
## RECOVER, en grados (`docs/03` §3.2).
const RECOVER_ANGLE_DEGREES: float = 60.0

## Tiempo que hay que pasar volcado para que RECOVER se dispare, en segundos.
const RECOVER_DELAY: float = 0.3

## Velocidad de impacto a partir de la cual un choque dispara RECOVER, en m/s.
const RECOVER_CRASH_SPEED: float = 12.0

## Velocidad vertical objetivo durante la recuperación, en m/s.
const RECOVER_DESCENT_SPEED: float = -3.0

## Ganancia del lazo P de velocidad vertical, en unidades de acelerador por m/s.
const RECOVER_VERTICAL_GAIN: float = 0.08

## Inclinación por debajo de la cual RECOVER se considera cumplido, en grados.
const RECOVER_EXIT_DEGREES: float = 10.0

## Velocidad vertical por debajo de la cual RECOVER se considera cumplido, en m/s.
const RECOVER_EXIT_VERTICAL: float = 1.0

## Tiempo que hay que cumplir las dos condiciones para salir de RECOVER, en s.
const RECOVER_EXIT_TIME: float = 0.5

## Altura sobre el terreno por debajo de la cual RECOVER desarma, en metros.
const RECOVER_DISARM_AGL: float = 0.5

## Deflexión mínima del stick para que TURTLE encienda un par de motores.
const TURTLE_STICK_THRESHOLD: float = 0.2

## `basis.y · UP` a partir del cual TURTLE da el vuelco por terminado.
const TURTLE_UPRIGHT_DOT: float = 0.7

## Dron al que pertenece este controlador. Si queda vacío se resuelve al padre,
## que es como lo arma `drone_rig.tscn`.
@export var drone: Drone

## Ganancias del lazo de tasa de alabeo como `(Kp, Ki, Kd)` (`docs/03` §3.4).
@export var rate_gains_roll: Vector3 = Vector3(0.045, 0.06, 0.0009)

## Ganancias del lazo de tasa de cabeceo como `(Kp, Ki, Kd)`.
@export var rate_gains_pitch: Vector3 = Vector3(0.045, 0.06, 0.0009)

## Ganancias del lazo de tasa de guiñada como `(Kp, Ki, Kd)`.
@export var rate_gains_yaw: Vector3 = Vector3(0.08, 0.10, 0.0)

## Ganancia del lazo externo de ángulo de HORIZON, en s⁻¹ (`docs/03` §3.2).
@export var angle_gain: float = 6.0

## Inclinación máxima que pide el stick a fondo en HORIZON, en grados.
@export var angle_limit_degrees: float = 35.0

## Acelerador de equilibrio, base del lazo vertical de RECOVER. Es el comando de
## equilibrio que mide `flight_bench` §11.1 (0.395 con los valores de fábrica).
@export var hover_throttle: float = 0.40

## Lo pone en `false` `EnergySystem` (`docs/09`, WP-15) cuando no queda energía;
## entonces [method arm] falla con [constant REASON_NO_ENERGY].
@export var can_arm_energy: bool = true

var _mode_key: String = MODE_ACRO
var _armed: bool = false
var _previous_mode: String = MODE_ACRO

var _command: FlightCommand = FlightCommand.new()
var _profile: ControlProfile = null

var _pid_roll: PIDController = PIDController.new()
var _pid_pitch: PIDController = PIDController.new()
var _pid_yaw: PIDController = PIDController.new()

var _output: Array[float] = [0.0, 0.0, 0.0, 0.0]

var _tilt_timer: float = 0.0
var _recover_timer: float = 0.0
var _pending_recover: bool = false


func _ready() -> void:
	if drone == null:
		drone = get_parent() as Drone
	if _profile == null:
		set_control_profile(QuadSettings.control_profile)
	apply_gains()
	if drone != null and not drone.crashed.is_connected(_on_drone_crashed):
		var _discard := drone.crashed.connect(_on_drone_crashed)


# --- Interfaz pública (`docs/03` §9) ---------------------------------------------------------


## Comandos de los cuatro motores para un sub-paso de [param dt] segundos.
##
## Devuelve **siempre el mismo array**, reescrito en cada llamada: a 1 000 Hz,
## crear uno nuevo por sub-paso serían diez asignaciones por tick de física. Quien
## necesite conservarlo lo duplica.
##
## Los valores van en `[0, 1]`, salvo en TURTLE donde pueden ser negativos hasta
## `−1` (reversa, `docs/03` §2.2).
func integrate(dt: float, state: FlightState) -> Array[float]:
	if state == null or dt <= 0.0:
		return _output
	_update_transitions(dt, state)
	if not _armed:
		_fill_output(0.0)
		return _output
	if _mode_key == MODE_TURTLE:
		_mix_turtle()
		return _output

	var throttle := _command.throttle
	var targets := Vector3.ZERO
	match _mode_key:
		MODE_RECOVER:
			targets = _level_targets(state)
			throttle = _recover_throttle(state)
		MODE_HORIZON:
			targets = _horizon_targets(state)
		_:
			targets = _acro_targets()

	var rates := state.rates()
	var roll_output := _pid_roll.update(targets.x, rates.x, dt)
	var pitch_output := _pid_pitch.update(targets.y, rates.y, dt)
	var yaw_output := _pid_yaw.update(targets.z, rates.z, dt)
	# El cabeceo entra al mezclador con el signo cambiado: ver la nota de
	# discrepancia sobre §3.5 en la cabecera.
	_apply_mixer(throttle, roll_output, -pitch_output, yaw_output)
	return _output


## Cambia de modo por su clave (`docs/03` §3.2).
##
## Rechaza en silencio lo que §3.2 no permite: abandonar RECOVER a mano, entrar en
## TURTLE armado o estando derecho, y cambiar de modo mientras TURTLE está activo.
func select_mode(mode_key: String) -> void:
	var key := mode_key.to_lower()
	if key == _mode_key:
		return
	match key:
		MODE_ACRO, MODE_HORIZON:
			if _mode_key == MODE_RECOVER or _mode_key == MODE_TURTLE:
				return
			_set_mode(key)
		MODE_TURTLE:
			if not can_enter_turtle():
				return
			_set_mode(key)
		MODE_RECOVER:
			if not _armed:
				return
			_enter_recover()
		_:
			push_warning("FlightController: modo desconocido '%s'." % mode_key)


## Alterna ACRO ↔ HORIZON (`docs/03` §3.2). No hace nada en TURTLE ni en RECOVER.
func cycle_mode() -> void:
	if _mode_key == MODE_TURTLE or _mode_key == MODE_RECOVER:
		return
	select_mode(MODE_HORIZON if _mode_key == MODE_ACRO else MODE_ACRO)


## Arma el dron si se cumplen las tres reglas de `docs/03` §3.3.
##
## Devuelve `true` si quedó armado. Al fallar emite [signal arm_failed] con
## [constant REASON_RECOVERING], [constant REASON_THROTTLE_HIGH] o
## [constant REASON_NO_ENERGY], en ese orden de prioridad.
func arm() -> bool:
	if _armed:
		return true
	if _mode_key == MODE_RECOVER:
		arm_failed.emit(REASON_RECOVERING)
		return false
	if _command.throttle >= ARM_THROTTLE_LIMIT:
		arm_failed.emit(REASON_THROTTLE_HIGH)
		return false
	if not can_arm_energy:
		arm_failed.emit(REASON_NO_ENERGY)
		return false
	_armed = true
	_reset_loops()
	_apply_reverse_permission(_mode_key == MODE_TURTLE)
	if drone != null:
		drone.apply_arm_state(true)
	armed.emit(_mode_key)
	return true


## Desarma: motores a cero, integradores a cero y [signal disarmed].
##
## Ninguno de los dos modos automáticos sobrevive al desarme. TURTLE vuelve a
## ACRO, que es lo que pide §3.2 al enderezarse. RECOVER vuelve **al modo
## anterior**, porque §3.2 pone el desarme bajo 0.5 m AGL como una de las dos
## salidas de la recuperación —«sale al modo anterior … **o desarma** bajo 0.5 m
## AGL»—: el dron ya tocó suelo, no queda nada que recuperar, y dejarlo en
## RECOVER lo dejaría sin poder volver a armar (§3.3) ni cambiar de modo (§3.2),
## o sea varado. Por eso [constant REASON_NO_ENERGY] y
## [constant REASON_THROTTLE_HIGH] se ven en el juego y
## [constant REASON_RECOVERING] queda como guarda: solo salta si algo desarma el
## controlador por fuera de este método, dejándolo en RECOVER.
func disarm() -> void:
	if not _armed:
		return
	_armed = false
	_reset_loops()
	_apply_reverse_permission(false)
	if _mode_key == MODE_TURTLE:
		_set_mode(MODE_ACRO)
	elif _mode_key == MODE_RECOVER:
		_set_mode(_previous_mode)
	if drone != null:
		drone.apply_arm_state(false)
	disarmed.emit()


## Cambia el perfil de rates. Lo llama `DroneRig` con
## `QuadSettings.control_profile` en cada `settings_updated` (`docs/04` §3.6).
func set_control_profile(profile: ControlProfile) -> void:
	if profile == null:
		return
	_profile = profile


## Perfil de rates vigente.
func get_control_profile() -> ControlProfile:
	return _profile


## Copia el último comando del piloto. El controlador guarda una copia propia: la
## radio reescribe su instancia cada frame de física y el lazo corre diez veces
## dentro de ese frame.
func update_command(cmd: FlightCommand) -> void:
	if cmd == null:
		return
	_command.copy_from(cmd)


## Copia del comando vigente, para el HUD y los checks.
func get_command() -> FlightCommand:
	return _command


## Clave del modo activo.
func get_mode_key() -> String:
	return _mode_key


## `true` si el controlador está armado.
func is_armed() -> bool:
	return _armed


## Vacía integradores, filtros y relojes de modo. Lo llama `Drone.reset_to()`.
##
## No toca el armado —reaparecer es asunto del nivel, armar es asunto del piloto—
## pero sí cancela una recuperación en curso: el dron ya está en el punto de
## reaparición, no hay nada que recuperar.
func reset() -> void:
	_reset_loops()
	if _mode_key == MODE_RECOVER:
		_set_mode(_previous_mode)


## Vuelca [member rate_gains_roll], [member rate_gains_pitch] y
## [member rate_gains_yaw] sobre los tres PID. Se llama sola en [method _ready];
## hay que llamarla a mano después de cambiar una ganancia en caliente.
func apply_gains() -> void:
	_pid_roll.set_gains_vector(rate_gains_roll)
	_pid_pitch.set_gains_vector(rate_gains_pitch)
	_pid_yaw.set_gains_vector(rate_gains_yaw)


## Mezclador X con air mode (`docs/03` §3.5), expuesto para que `flight_bench` pueda
## comprobar signos y reserva de ralentí sin volar.
##
## Devuelve un array **nuevo** de cuatro comandos en `[idle, 1]`, pero **no es pura**:
## por dentro reutiliza [member _output], así que pisa los comandos que dejó el último
## [method integrate]. Está pensada para el banco, con el dron quieto y fuera del lazo;
## no se la llama desde el tick de física.
func mix(throttle: float, roll: float, pitch: float, yaw: float) -> Array[float]:
	_apply_mixer(throttle, roll, pitch, yaw)
	return _output.duplicate()


## `true` si se puede entrar en TURTLE ahora mismo: desarmado y boca abajo
## (`docs/03` §3.2).
func can_enter_turtle() -> bool:
	if _armed or drone == null:
		return false
	return drone.get_flight_state().is_upside_down()


## Los tres PID del lazo de tasa, en el orden `[alabeo, cabeceo, guiñada]`. Para
## depuración y checks; el gameplay no los toca.
func get_rate_pids() -> Array[PIDController]:
	return [_pid_roll, _pid_pitch, _pid_yaw]


# --- Modos (`docs/03` §3.2) -------------------------------------------------------------------


## Entradas y salidas automáticas de modo, una vez por sub-paso.
func _update_transitions(dt: float, state: FlightState) -> void:
	if not _armed:
		return
	match _mode_key:
		MODE_TURTLE:
			if state.basis.y.dot(Vector3.UP) > TURTLE_UPRIGHT_DOT:
				# Ya está derecho: se apaga solo, que es lo que espera el piloto
				# cuando suelta el stick después del vuelco.
				disarm()
		MODE_RECOVER:
			_update_recover_exit(dt, state)
		MODE_HORIZON:
			_update_recover_entry(dt, state)
		_:
			# En ACRO no hay recuperación automática: el piloto conserva el
			# control total, incluso para estrellarse (`docs/03` §3.2).
			_tilt_timer = 0.0
	if _pending_recover:
		_pending_recover = false
		if _armed and _mode_key != MODE_RECOVER:
			_enter_recover()


## Reloj de los 60° de `docs/03` §3.2: volcado el tiempo suficiente, entra RECOVER.
func _update_recover_entry(dt: float, state: FlightState) -> void:
	var limit := deg_to_rad(RECOVER_ANGLE_DEGREES)
	if absf(state.euler.x) > limit or absf(state.euler.y) > limit:
		_tilt_timer += dt
		if _tilt_timer >= RECOVER_DELAY:
			_enter_recover()
	else:
		_tilt_timer = 0.0


## Condiciones de salida de RECOVER: nivelado y sin velocidad vertical durante
## medio segundo, o desarme por llegar al suelo.
func _update_recover_exit(dt: float, state: FlightState) -> void:
	if state.altitude_agl >= 0.0 and state.altitude_agl < RECOVER_DISARM_AGL:
		disarm()
		return
	var limit := deg_to_rad(RECOVER_EXIT_DEGREES)
	var levelled := absf(state.euler.x) < limit and absf(state.euler.y) < limit
	var slow := absf(state.velocity.y) < RECOVER_EXIT_VERTICAL
	if levelled and slow:
		_recover_timer += dt
		if _recover_timer >= RECOVER_EXIT_TIME:
			_set_mode(_previous_mode)
	else:
		_recover_timer = 0.0


func _enter_recover() -> void:
	if _mode_key == MODE_RECOVER:
		return
	_previous_mode = MODE_ACRO if _mode_key == MODE_TURTLE else _mode_key
	_recover_timer = 0.0
	_tilt_timer = 0.0
	_set_mode(MODE_RECOVER)


func _set_mode(mode_key: String) -> void:
	if mode_key == _mode_key:
		return
	var leaving_turtle := _mode_key == MODE_TURTLE
	_mode_key = mode_key
	_tilt_timer = 0.0
	_recover_timer = 0.0
	# `docs/03` §3.4: los integradores se vacían en cada cambio de modo, para que
	# la corrección acumulada en un modo no salga disparada en el siguiente.
	_reset_loops()
	if leaving_turtle or mode_key == MODE_TURTLE:
		_apply_reverse_permission(mode_key == MODE_TURTLE and _armed)
	flight_mode_changed.emit(_mode_key)


## Un choque fuerte en un modo asistido dispara la recuperación (`docs/03` §3.2).
## La entrada se difiere al próximo sub-paso: la señal llega desde el tick de
## física del dron y cambiar de modo en medio del integrador confundiría al lazo.
func _on_drone_crashed(impact_speed: float) -> void:
	if not _armed or impact_speed <= RECOVER_CRASH_SPEED:
		return
	if _mode_key != MODE_HORIZON:
		return
	_pending_recover = true


# --- Consignas por modo ----------------------------------------------------------------------


## ACRO: las tres tasas salen del perfil de rates tal cual (`docs/03` §3.2).
func _acro_targets() -> Vector3:
	return Vector3(
			_rate_for(ControlProfile.Axis.ROLL, _command.roll),
			_rate_for(ControlProfile.Axis.PITCH, _command.pitch),
			_rate_for(ControlProfile.Axis.YAW, _command.yaw))


## HORIZON: alabeo y cabeceo pasan por un lazo externo de ángulo; la guiñada
## sigue siendo tasa (`docs/03` §3.2).
func _horizon_targets(state: FlightState) -> Vector3:
	var limit := deg_to_rad(angle_limit_degrees)
	var roll_goal := _normalized(ControlProfile.Axis.ROLL, _command.roll) * limit
	var pitch_goal := _normalized(ControlProfile.Axis.PITCH, _command.pitch) * limit
	return Vector3(
			_angle_loop(ControlProfile.Axis.ROLL, roll_goal, state.euler.x),
			_angle_loop(ControlProfile.Axis.PITCH, pitch_goal, state.euler.y),
			_rate_for(ControlProfile.Axis.YAW, _command.yaw))


## RECOVER: mismo lazo externo que HORIZON pero con el ángulo objetivo en cero y
## sin guiñada; los sticks quedan fuera (`docs/03` §3.2).
func _level_targets(state: FlightState) -> Vector3:
	return Vector3(
			_angle_loop(ControlProfile.Axis.ROLL, 0.0, state.euler.x),
			_angle_loop(ControlProfile.Axis.PITCH, 0.0, state.euler.y),
			0.0)


## Lazo P de ángulo: `ω = K_angle · (θ_obj − θ)`, acotado a la tasa máxima que el
## perfil da en ese eje.
func _angle_loop(axis: int, goal: float, angle: float) -> float:
	var top := deg_to_rad(_max_rate_degrees(axis))
	return clampf(angle_gain * (goal - angle), -top, top)


## Lazo P de velocidad vertical de RECOVER sobre el acelerador de equilibrio.
func _recover_throttle(state: FlightState) -> float:
	var error := RECOVER_DESCENT_SPEED - state.velocity.y
	return clampf(hover_throttle + RECOVER_VERTICAL_GAIN * error, 0.0, 1.0)


## Velocidad angular pedida por el stick en un eje, en rad/s.
func _rate_for(axis: int, stick: float) -> float:
	if _profile == null:
		return 0.0
	return deg_to_rad(_profile.get_rate(axis, stick))


## Deflexión normalizada a `[−1, 1]` contra la tasa máxima del eje (`docs/03` §3.6).
func _normalized(axis: int, stick: float) -> float:
	if _profile == null:
		return clampf(stick, -1.0, 1.0)
	return _profile.get_normalized(axis, stick)


func _max_rate_degrees(axis: int) -> float:
	if _profile == null:
		return ControlProfile.MAX_RATE
	return maxf(_profile.get_max_rate(axis), 1.0)


# --- Mezclador (`docs/03` §3.5) ----------------------------------------------------------------


## Mezcla X más air mode sobre [member _output].
##
## Numeración de §3.5: M1 delantero-izquierdo (CW), M2 delantero-derecho (CCW),
## M3 trasero-derecho (CW), M4 trasero-izquierdo (CCW).
##
## Air mode: si la excursión pedida no entra en el rango útil `[idle, 1]`, primero
## se **escalan** las desviaciones respecto del acelerador —con lo que se conserva
## la proporción entre ejes— y después se **desplaza** el bloque entero hasta que
## entre. Desplazar sacrifica acelerador, no autoridad de control: por eso el dron
## sigue respondiendo con el stick de gas al mínimo.
func _apply_mixer(throttle: float, roll: float, pitch: float, yaw: float) -> void:
	var base := clampf(throttle, 0.0, 1.0)
	var r := clampf(roll, -1.0, 1.0)
	var p := clampf(pitch, -1.0, 1.0)
	var y := clampf(yaw, -1.0, 1.0)
	_output[0] = base + r - p + y
	_output[1] = base - r - p - y
	_output[2] = base - r + p + y
	_output[3] = base + r + p - y

	var low := _output[0]
	var high := _output[0]
	for index: int in 4:
		low = minf(low, _output[index])
		high = maxf(high, _output[index])

	var span := high - low
	var headroom := 1.0 - MIXER_IDLE
	if span > headroom and span > 0.0:
		var scale := headroom / span
		low = INF
		high = -INF
		for index: int in 4:
			_output[index] = base + (_output[index] - base) * scale
			low = minf(low, _output[index])
			high = maxf(high, _output[index])

	if low < MIXER_IDLE:
		var shift := MIXER_IDLE - low
		for index: int in 4:
			_output[index] += shift
		high += shift
	if high > 1.0:
		var shift := 1.0 - high
		for index: int in 4:
			_output[index] += shift

	for index: int in 4:
		_output[index] = clampf(_output[index], MIXER_IDLE, 1.0)


## TURTLE: lazo abierto, los dos motores del lado hacia donde apunta el stick
## dominante giran en reversa y los otros dos quedan apagados (`docs/03` §3.2).
##
## «Apagados» es literal: se les quita [member DroneMotor.powered], no se les manda
## comando 0.0. Un motor armado con comando 0.0 se queda en [member DroneMotor.idle_rpm]
## —1 500 rpm— empujando hacia el suelo justo del lado contrario al del vuelco, que es
## exactamente lo que §3.2 no quiere. El par lo restaura [method _apply_reverse_permission]
## al salir de TURTLE.
func _mix_turtle() -> void:
	_fill_output(0.0)
	var roll_stick := _command.roll
	var pitch_stick := _command.pitch
	var use_roll := absf(roll_stick) >= absf(pitch_stick)
	var magnitude := absf(roll_stick) if use_roll else absf(pitch_stick)
	if magnitude < TURTLE_STICK_THRESHOLD:
		_power_turtle_pair(-1, -1)
		return
	# El comando negativo llega a `−DroneMotor.REVERSE_LIMIT · max_rpm · |stick|` dentro
	# de `DroneMotor.rpm_for_command()`; acá basta con el signo y la magnitud. El tope no
	# es el `−0.5 · max_rpm` de `docs/03` §2.2 sino 0.75, por la discrepancia medida que
	# está registrada en `drone/parts/motor.gd` (nota de [constant DroneMotor.REVERSE_LIMIT]).
	var reverse := -magnitude
	var first := 0
	var second := 3
	if use_roll:
		if roll_stick > 0.0:
			first = 1   # M2 delantero-derecho
			second = 2  # M3 trasero-derecho
		else:
			first = 0   # M1 delantero-izquierdo
			second = 3  # M4 trasero-izquierdo
	elif pitch_stick > 0.0:
		first = 2   # M3 trasero-derecho
		second = 3  # M4 trasero-izquierdo
	else:
		first = 0   # M1 delantero-izquierdo
		second = 1  # M2 delantero-derecho
	_output[first] = reverse
	_output[second] = reverse
	_power_turtle_pair(first, second)


## Deja encendidos solo los motores [param first] y [param second]; `−1` en los dos
## apaga los cuatro. Con [member DroneMotor.powered] en `false` el régimen objetivo es
## cero y la hélice se frena con `tau_down`, que es el «apagados» de `docs/03` §3.2.
func _power_turtle_pair(first: int, second: int) -> void:
	if drone == null:
		return
	var motors := drone.get_motors()
	for index: int in motors.size():
		motors[index].powered = _armed and (index == first or index == second)


# --- Internos --------------------------------------------------------------------------------


func _fill_output(value: float) -> void:
	for index: int in 4:
		_output[index] = value


func _reset_loops() -> void:
	_pid_roll.reset()
	_pid_pitch.reset()
	_pid_yaw.reset()
	_tilt_timer = 0.0
	_recover_timer = 0.0
	_pending_recover = false


## Abre o cierra la reversa de los cuatro motores. Solo TURTLE la necesita; fuera
## de él un comando negativo tiene que quedarse en cero (`docs/03` §2.2).
##
## Al cerrarla —o sea al salir de TURTLE, por desarme o por enderezarse— devuelve
## [member DroneMotor.powered] al estado de armado, que es lo que deshace el apagado
## selectivo del par inactivo que hace [method _power_turtle_pair].
func _apply_reverse_permission(allowed: bool) -> void:
	if drone == null:
		return
	for motor: DroneMotor in drone.get_motors():
		motor.allow_reverse = allowed
		if not allowed:
			motor.powered = _armed
