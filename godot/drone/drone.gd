## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cuerpo rígido del cuadricóptero con integrador propio (`docs/03` §2).
##
## Godot integra los cuerpos rígidos una vez por tick de física; a 100 Hz eso
## deja un paso de 10 ms, demasiado grueso para un lazo de tasa que necesita
## reaccionar en milisegundos. Por eso el dron desactiva la integración del motor
## (`custom_integrator = true`) y hace la suya: [constant SUBSTEPS_ARMED]
## sub-pasos de 1 ms cuando está armado y uno solo cuando no lo está, con Euler
## semi-implícito. Los contactos los sigue resolviendo Jolt entre tick y tick.
##
## Lo que se suma en cada sub-paso:
## 1. El controlador de vuelo, si hay ([member controller]), que devuelve los
##    cuatro comandos de motor; si no, [member test_motor_commands].
## 2. El régimen de cada [DroneMotor] (`docs/03` §2.2).
## 3. Empuje, arrastre en plano y par de cada [DronePropeller] (`docs/03` §2.3),
##    aplicados en la posición de su hélice.
## 4. Arrastre del cuerpo por eje y amortiguación angular (`docs/03` §2.4).
## 5. Gravedad manual: el cuerpo lleva `gravity_scale = 0`.
##
## Discrepancia registrada con `docs/03` §2.2 — **signo del par de reacción**.
## §2.2 escribe `τ_reacción = −s · Q` con `s = +1` para giro CW, pero eso deja la
## guiñada al revés que el mezclador de §3.5, donde un comando de guiñada positivo
## (morro a la izquierda, o sea rotación positiva sobre `+Y` en ejes de Godot)
## acelera justamente los motores CW (M1 y M3). La tercera ley da la razón a
## §3.5: una hélice que arrastra el aire en sentido horario empuja el cuerpo en
## sentido antihorario. Se implementa **`τ = +s · Q`**, que es lo coherente con
## §3.5, con la física y con el criterio 9 del banco.
##
## Discrepancia registrada con `docs/03` §2.1 — **brazo de los motores**. §2.1
## propone `(∓0.08, 0, ∓0.08)`; el modelo voxel real (`assets/drone/drone_quad.glb`,
## WP-12b) los tiene en `(∓0.085, 0.015, ∓0.085)`. Manda el modelo, para que las
## esferas de colisión, el empuje y las hélices que se ven coincidan en el mismo
## punto. El brazo queda un 6 % más largo, lo que sube la autoridad de alabeo y
## cabeceo en esa misma proporción.
##
## Ajuste de WP-05 — **velocidad máxima (`docs/03` §11.6)**. Con los valores de
## §10 tal cual, el banco medía **51.3 m/s** a 45° de inclinación y acelerador a
## fondo, por encima del techo de 40 m/s de §11.6. Se ajustaron, dentro de los
## rangos que el propio §11.6 autoriza, los dos parámetros que gobiernan ese
## régimen: [member DronePropeller.k_j] de 0.6 a **1.0** (pérdida de empuje por
## relación de avance) y el arrastre del cuerpo, [constant DRAG_AREA] y
## [constant DRAG_CD]. Los dos cambios van hacia lo físicamente más realista: un
## cuadro de 5" con cuatro motores, cámara y antena es un cuerpo romo, no un perfil
## aerodinámico, y una hélice de paso 4.8" pierde empuje rápido en vuelo axial.
##
## Corrección de la revisión de WP-05 — **arrastre simétrico en X/Z**. El primer
## ajuste había dejado `A_z = 0.020 m²` contra `A_x = 0.013 m²` y `Cd_z = 1.0`
## contra `Cd_x = 0.4`, o sea un cuadro que frena cuatro veces más yendo de morro
## que yendo de costado. El cuadro es simétrico en X y Z —los cuatro brazos son
## iguales y los cuatro motores están a la misma distancia—, así que los dos ejes
## horizontales comparten área y coeficiente. Valores finales:
## **`A = (0.016, 0.020, 0.016) m²`** y **`Cd = (1.0, 1.2, 1.0)`**, con
## **`k_J = 1.0`** sin tocar (ya estaba en el tope que §11.6 autoriza). El eje
## vertical queda con la mayor área, que es lo que corresponde a la silueta vista
## desde arriba, y con el `Cd` de placa plana de §2.4. Medido con estos valores:
## **`v_max = 34.2 m/s`** (antes del ajuste, 37.0), dentro del `[25, 40]` de §11.6.
## Los criterios
## §11.1–§11.3 (empuje estático, relación empuje/peso y respuesta de motor) no se
## mueven, porque ninguno de los tres depende de la velocidad.
class_name Drone extends RigidBody3D

## Se emite al armar con éxito. [param mode_key] es la clave del modo activo.
signal armed(mode_key: String)

## Se emite al desarmar, por cualquier vía.
signal disarmed()

## Se emite cuando el controlador rechaza un intento de armado (`docs/03` §3.3).
## [param reason_key] es `ERR_ARM_THROTTLE_HIGH`, `ERR_ARM_RECOVERING` o
## `ERR_ARM_NO_ENERGY`.
signal arm_failed(reason_key: String)

## Se emite en cada cambio de modo de vuelo (`docs/03` §3.2).
signal flight_mode_changed(mode_key: String)

## Se emite al reaparecer, desde [method reset_to].
signal respawned()

## Se emite cuando el dron choca. [param impact_speed] es la variación de
## velocidad detectada, en m/s.
signal crashed(impact_speed: float)

## Gravedad manual: el cuerpo tiene `gravity_scale = 0` y la aplica el integrador.
const GRAVITY: Vector3 = Vector3(0.0, -9.81, 0.0)

## Sub-pasos por tick de física con el dron armado al paso nominal de 100 Hz
## (`docs/03` §2.5): 1 000 Hz de lazo de control.
const SUBSTEPS_ARMED: int = 10

## Sub-pasos con el dron desarmado. Sin lazo de control no hace falta más.
const SUBSTEPS_IDLE: int = 1

## Duración objetivo de cada sub-paso, en segundos. Es [constant SUBSTEPS_ARMED]
## sub-pasos dentro del paso nominal de 10 ms.
const TARGET_SUBSTEP_SECONDS: float = 0.001

## Tope de sub-pasos por tick, para que un paso de física anormalmente largo no
## convierta un hipo en una congelación.
const MAX_SUBSTEPS: int = 40

## Inercia diagonal en ejes del cuerpo, en kg·m² (`docs/03` §2.1).
const INERTIA: Vector3 = Vector3(0.0025, 0.0045, 0.0025)

## Áreas proyectadas por eje del cuerpo, en m² (`docs/03` §2.4). Los dos ejes
## horizontales son iguales porque el cuadro lo es; la vertical es la mayor, que es
## la silueta vista desde arriba. Ver el ajuste de §11.6 de la cabecera.
const DRAG_AREA: Vector3 = Vector3(0.016, 0.020, 0.016)

## Coeficientes de arrastre por eje del cuerpo (`docs/03` §2.4). Cuerpo romo en los
## tres ejes; `y` conserva el 1.2 de placa plana de §2.4. Ver la cabecera.
const DRAG_CD: Vector3 = Vector3(1.0, 1.2, 1.0)

## Densidad del aire a nivel del mar, en kg/m³.
const AIR_DENSITY: float = 1.225

## Amortiguación angular cuadrática, en N·m·s² (`docs/03` §2.4).
const ANGULAR_DAMPING: float = 0.0004

## Variación de velocidad entre pasos a partir de la cual se considera choque,
## en m/s (`docs/03` §2.5).
const CRASH_DELTA_V: float = 6.0

## Tiempo simulado, en segundos, durante el que no se vuelve a emitir
## [signal crashed]. Un rebote reparte el impulso en varios ticks y sin esto
## saldrían tres o cuatro señales por golpe.
const CRASH_COOLDOWN: float = 0.25

## Clave del modo de vuelo cuando no hay [member controller] enganchado, que es
## como vuela `flight_bench` en sus criterios puramente físicos.
const DEFAULT_MODE_KEY: String = "acro"

## Tope de giro visible de las hélices, en rev/s (`docs/03` §7). Más allá el ojo
## solo ve el disco y el estroboscopio del render juega en contra.
const VISUAL_MAX_REV: float = 20.0

## Fracción de [member DroneMotor.max_rpm] a la que el disco de desenfoque queda
## completamente opaco y la pala llega a su desvanecimiento máximo.
const VISUAL_BLUR_FULL: float = 0.5

## Transparencia máxima de la pala cuando el disco de desenfoque la reemplaza.
const VISUAL_BLADE_FADE: float = 0.85

## Punto de reaparición. Lo cablea el nivel; lo leen `DroneRig` y el
## `RespawnController` de `docs/09`.
@export var respawn_point: Node3D

## Controlador de vuelo (WP-05). Si no es `null` y expone
## `integrate(dt: float, state: FlightState) -> Array[float]`, se le pide los
## cuatro comandos de motor en cada sub-paso. Si es `null` se usan
## [member test_motor_commands], que es como vuela el banco de pruebas.
@export var controller: Node

## Comandos fijos de los cuatro motores, en el orden del mezclador de
## `docs/03` §3.5. Solo se usan cuando no hay [member controller]; existen para
## `flight_bench` y para probar a mano en el sandbox.
@export var test_motor_commands: Array[float] = [0.0, 0.0, 0.0, 0.0]

var _motors: Array[DroneMotor] = []
var _propellers: Array[DronePropeller] = []
var _prop_offsets: PackedVector3Array = PackedVector3Array()
var _prop_heights: PackedFloat32Array = PackedFloat32Array()
var _commands: PackedFloat32Array = PackedFloat32Array()
var _blade_meshes: Array[MeshInstance3D] = []
var _disk_meshes: Array[MeshInstance3D] = []
var _blade_spins: PackedInt32Array = PackedInt32Array()

var _flight_state: FlightState = FlightState.new()
var _command: FlightCommand = FlightCommand.new()
var _armed: bool = false
var _thrust_scale: float = 1.0
var _mass_inverse: float = 1.0
var _inertia_inverse: Vector3 = Vector3.ONE
var _drag_factor: Vector3 = Vector3.ZERO

## Enciende la medida del coste del integrador. Apagado cuesta un `if` por tick;
## encendido, dos lecturas de reloj. Lo usa `flight_bench` (`docs/03` §2.5).
var profiling: bool = false

var _profile_total_usec: int = 0
var _profile_peak_usec: int = 0
var _profile_ticks: int = 0

var _expected_velocity: Vector3 = Vector3.ZERO
var _has_expected_velocity: bool = false
var _crash_cooldown: float = 0.0
var _last_substeps: int = 0
var _visuals_settled: bool = false
var _pending_transform: Transform3D = Transform3D.IDENTITY
var _has_pending_transform: bool = false


func _ready() -> void:
	_configure_body()
	_collect_motors()
	_collect_model_meshes()
	_cache_constants()
	_apply_mass()
	_connect_controller()
	var _discard := QuadSettings.settings_updated.connect(_on_quad_settings_updated)
	_discard = body_entered.connect(_on_body_entered)


## Integrador propio (`docs/03` §2.5). Todo el modelo físico del dron pasa por
## acá: Godot no toca ni la velocidad ni la transformada del cuerpo.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _motors.is_empty():
		return
	var profile_begin := Time.get_ticks_usec() if profiling else 0
	if _has_pending_transform:
		state.transform = _pending_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_has_pending_transform = false
		_has_expected_velocity = false
	var step := state.step
	if step <= 0.0:
		return

	_detect_impact(state)
	_read_ground_heights()

	var substeps := _substep_count(step)
	_last_substeps = substeps
	var dt := step / float(substeps)
	var body_transform := state.transform
	var velocity := state.linear_velocity
	var angular := state.angular_velocity

	for _substep: int in substeps:
		var body_basis := body_transform.basis
		var inverse_basis := body_basis.transposed()
		_flight_state.update(body_transform, velocity, angular, _lowest_height())
		var commands := _resolve_commands(dt)

		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		var thrust_axis := body_basis.y

		for index: int in _motors.size():
			var motor := _motors[index]
			motor.set_command(commands[index])
			motor.step(dt)
			var propeller := _propellers[index]
			if propeller == null:
				continue
			var offset := body_basis * _prop_offsets[index]
			var prop_velocity := velocity + angular.cross(offset)
			var forces := propeller.compute_forces(motor.rpm, prop_velocity, thrust_axis,
					_prop_heights[index])
			var applied: Vector3 = thrust_axis * float(forces["thrust"])
			applied += forces["in_plane_force"] as Vector3
			force += applied
			torque += offset.cross(applied)
			# Par de reacción: `+spin`, no `−spin`. Ver la nota de discrepancia
			# de la cabecera.
			torque += thrust_axis * (float(motor.spin) * signf(motor.rpm)
					* float(forces["torque"]))

		# Arrastre del cuerpo, cuadrático y por eje (`docs/03` §2.4).
		var local_velocity := inverse_basis * velocity
		force += body_basis * Vector3(
				-_drag_factor.x * absf(local_velocity.x) * local_velocity.x,
				-_drag_factor.y * absf(local_velocity.y) * local_velocity.y,
				-_drag_factor.z * absf(local_velocity.z) * local_velocity.z)

		# Amortiguación angular, también cuadrática.
		var local_angular := inverse_basis * angular
		var local_torque := inverse_basis * torque
		local_torque += Vector3(
				-ANGULAR_DAMPING * absf(local_angular.x) * local_angular.x,
				-ANGULAR_DAMPING * absf(local_angular.y) * local_angular.y,
				-ANGULAR_DAMPING * absf(local_angular.z) * local_angular.z)

		# Euler semi-implícito: primero la velocidad, después la posición.
		velocity += (force * _mass_inverse + GRAVITY) * dt
		body_transform.origin += velocity * dt

		# Euler de la rotación con el término giroscópico `ω × (I·ω)`.
		var spin_momentum := Vector3(INERTIA.x * local_angular.x, INERTIA.y * local_angular.y,
				INERTIA.z * local_angular.z)
		local_angular += (local_torque - local_angular.cross(spin_momentum)) \
				* _inertia_inverse * dt
		angular = body_basis * local_angular
		var angular_speed := angular.length()
		if angular_speed > 0.0:
			body_transform.basis = body_basis.rotated(angular / angular_speed,
					angular_speed * dt).orthonormalized()
		else:
			body_transform.basis = body_basis.orthonormalized()

	state.linear_velocity = velocity
	state.angular_velocity = angular
	state.transform = body_transform
	_expected_velocity = velocity
	_has_expected_velocity = true
	if _crash_cooldown > 0.0:
		_crash_cooldown = maxf(_crash_cooldown - step, 0.0)
	if profiling:
		var spent := Time.get_ticks_usec() - profile_begin
		_profile_total_usec += spent
		_profile_peak_usec = maxi(_profile_peak_usec, spent)
		_profile_ticks += 1


## Giro y desenfoque de las hélices del modelo (`docs/03` §7). Es puro adorno, así
## que vive en `_process` y no en el tick de física.
func _process(delta: float) -> void:
	if _blade_meshes.is_empty():
		return
	var spinning := false
	for index: int in _motors.size():
		var motor := _motors[index]
		var revolutions := absf(motor.rpm) / 60.0
		if revolutions > 0.0:
			spinning = true
		elif _visuals_settled:
			continue
		var blur := clampf(absf(motor.rpm_ratio()) / VISUAL_BLUR_FULL, 0.0, 1.0)
		var blade := _blade_meshes[index]
		if blade != null:
			# `spin = +1` es giro horario visto desde arriba, que en ejes de Godot es
			# rotación negativa sobre `+Y`.
			var direction := -float(_blade_spins[index]) * signf(motor.rpm)
			blade.rotate_y(direction * minf(revolutions, VISUAL_MAX_REV) * TAU * delta)
			blade.transparency = blur * VISUAL_BLADE_FADE
		var disk := _disk_meshes[index]
		if disk != null:
			disk.visible = blur > 0.0
			disk.transparency = 1.0 - blur
	# Con las cuatro hélices paradas ya no hay nada que animar: se deja el modelo
	# en reposo una vez y el resto de los frames sale por arriba.
	_visuals_settled = not spinning


## Detiene el dron, lo teletransporta a [param xform], reinicia motores y
## controlador y emite [signal respawned] (`docs/03` §9).
##
## La transformada se aplica también dentro del siguiente [method _integrate_forces],
## porque con `custom_integrator` el servidor de física es el dueño del estado; el
## nodo se actualiza igual en el acto para quien lea [member global_transform]
## enseguida.
func reset_to(xform: Transform3D) -> void:
	_pending_transform = xform
	_has_pending_transform = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = xform
	_expected_velocity = Vector3.ZERO
	_has_expected_velocity = false
	_crash_cooldown = 0.0
	# El armado no cambia: reaparecer es asunto del nivel, armar y desarmar es
	# asunto del piloto y de `FlightController` (WP-05). Lo que sí se reinicia es
	# el régimen, para que el dron no llegue girando al punto de reaparición.
	for motor: DroneMotor in _motors:
		motor.reset()
		if _armed:
			motor.spin_up_to_idle()
	_fill_commands(0.0)
	if controller != null and controller.has_method(&"reset"):
		controller.call(&"reset")
	_flight_state.update(xform, Vector3.ZERO, Vector3.ZERO, DronePropeller.NO_GROUND)
	respawned.emit()


## Lleva el dron a [member respawn_point], si el nivel lo cableó. Devuelve `false`
## si no hay punto de reaparición.
func respawn() -> bool:
	if respawn_point == null:
		return false
	reset_to(respawn_point.global_transform)
	return true


## Arma el dron (`docs/03` §3.3 y §9).
##
## Con [member controller] enganchado la decisión es suya: acelerador bajo, no
## estar en RECOVER y energía disponible. El dron solo aplica el resultado y
## reemite las señales del controlador. Sin controlador —el banco de pruebas—
## siempre tiene éxito.
##
## Devuelve `true` si quedó armado.
func arm() -> bool:
	if _armed:
		return true
	if controller != null and controller.has_method(&"arm"):
		return bool(controller.call(&"arm"))
	apply_arm_state(true)
	armed.emit(get_mode_key())
	return true


## Desarma el dron: `rpm_target` a cero y [signal disarmed].
##
## Igual que [method arm], delega en [member controller] cuando lo hay para que
## los integradores del PID y el modo activo queden coherentes.
func disarm() -> void:
	if controller != null and controller.has_method(&"disarm"):
		controller.call(&"disarm")
		return
	if not _armed:
		return
	apply_arm_state(false)
	disarmed.emit()


## Aplica el estado de armado sin emitir señales ni consultar reglas: enciende o
## apaga los cuatro motores y vacía los comandos.
##
## Es el punto por el que el controlador de vuelo materializa su decisión, una
## vez tomada. El gameplay usa [method arm] y [method disarm].
func apply_arm_state(active: bool) -> void:
	if _armed == active:
		return
	_armed = active
	_fill_commands(0.0)
	for motor: DroneMotor in _motors:
		if active:
			motor.spin_up_to_idle()
		else:
			motor.shut_down()


## `true` si el dron está armado.
func is_armed() -> bool:
	return _armed


## Guarda el comando del piloto y se lo pasa al controlador (`docs/03` §3.1).
##
## Lo llama `RadioController` una vez por frame de física. El dron conserva su
## propia copia porque [method get_throttle] y [method get_stick_input] son parte
## de su interfaz pública y tienen que funcionar aunque el controlador sea otro.
func update_command(cmd: FlightCommand) -> void:
	if cmd == null:
		return
	_command.copy_from(cmd)
	if controller != null and controller.has_method(&"update_command"):
		controller.call(&"update_command", _command)


## Copia viva del último comando recibido. No se duplica: quien la guarde usa
## [method FlightCommand.copy].
func get_command() -> FlightCommand:
	return _command


## Acelerador del último `FlightCommand`, en `[0, 1]` (`docs/03` §9).
func get_throttle() -> float:
	return _command.throttle


## Desarma sin preguntar. Lo usa `EnergySystem` (`docs/09`) cuando se acaba la
## batería.
func force_disarm() -> void:
	disarm()


## Escala el régimen máximo efectivo de los cuatro motores (`docs/03` §9):
## `1.0` es lo normal y `0.82` lo que deja la energía crítica.
func set_thrust_scale(scale: float) -> void:
	_thrust_scale = clampf(scale, 0.0, 2.0)
	for motor: DroneMotor in _motors:
		motor.thrust_scale = _thrust_scale


## Factor de empuje vigente.
func get_thrust_scale() -> float:
	return _thrust_scale


## Estado de vuelo del último sub-paso (`docs/03` §3.1).
##
## La instancia se reutiliza y se reescribe mil veces por segundo: quien necesite
## conservar una lectura usa [method FlightState.copy].
func get_flight_state() -> FlightState:
	return _flight_state


## Régimen de los cuatro motores en rpm, en el orden del mezclador.
func get_motor_rpm() -> Array[float]:
	var values: Array[float] = []
	for motor: DroneMotor in _motors:
		values.append(motor.rpm)
	return values


## Deflexión de los sticks como `[izquierdo, derecho]` para el HUD (`docs/03` §9).
##
## El izquierdo lleva `(guiñada, acelerador)` y el derecho `(alabeo, cabeceo)`,
## los cuatro en `[−1, 1]`. El acelerador, que en [FlightCommand] vive en `[0, 1]`,
## se devuelve como **deflexión de stick** (`2·t − 1`) para que el indicador del
## HUD pueda dibujar los dos sticks con el mismo dibujo.
func get_stick_input() -> Array[Vector2]:
	return [
		Vector2(_command.yaw, _command.throttle * 2.0 - 1.0),
		Vector2(_command.roll, _command.pitch),
	]


## Clave del modo de vuelo activo (`docs/03` §3.2).
##
## Sin [member controller] enganchado devuelve [constant DEFAULT_MODE_KEY], que
## es lo que corresponde a un dron sin lazo de control.
func get_mode_key() -> String:
	if controller != null and controller.has_method(&"get_mode_key"):
		return String(controller.call(&"get_mode_key"))
	return DEFAULT_MODE_KEY


## Pide al controlador el modo [param mode_key] (`docs/03` §3.2). Sin controlador
## no hace nada.
func select_mode(mode_key: String) -> void:
	if controller != null and controller.has_method(&"select_mode"):
		controller.call(&"select_mode", mode_key)


## Alterna ACRO ↔ HORIZON en el controlador (`docs/03` §3.2).
func cycle_mode() -> void:
	if controller != null and controller.has_method(&"cycle_mode"):
		controller.call(&"cycle_mode")


## Engancha un controlador de vuelo en caliente y recablea sus señales.
##
## En una escena normal el controlador llega por [member controller] desde el
## `.tscn` y se conecta solo en [method _ready]; esto es para las herramientas que
## lo agregan a mano, como `flight_bench`.
func set_controller(node: Node) -> void:
	_disconnect_controller()
	controller = node
	_connect_controller()


## Reemite las cuatro señales de vuelo del controlador como propias, que es lo que
## consume el HUD (`docs/03` §9): el dron es la única fachada del núcleo de vuelo.
func _connect_controller() -> void:
	if controller == null:
		return
	if controller.has_signal(&"armed") and not controller.is_connected(&"armed", _on_controller_armed):
		var _discard := controller.connect(&"armed", _on_controller_armed)
	if controller.has_signal(&"disarmed") and not controller.is_connected(&"disarmed", _on_controller_disarmed):
		var _discard := controller.connect(&"disarmed", _on_controller_disarmed)
	if controller.has_signal(&"arm_failed") and not controller.is_connected(&"arm_failed", _on_controller_arm_failed):
		var _discard := controller.connect(&"arm_failed", _on_controller_arm_failed)
	if controller.has_signal(&"flight_mode_changed") \
			and not controller.is_connected(&"flight_mode_changed", _on_controller_mode_changed):
		var _discard := controller.connect(&"flight_mode_changed", _on_controller_mode_changed)


func _disconnect_controller() -> void:
	if controller == null:
		return
	for pair: Array in [[&"armed", _on_controller_armed], [&"disarmed", _on_controller_disarmed],
			[&"arm_failed", _on_controller_arm_failed],
			[&"flight_mode_changed", _on_controller_mode_changed]]:
		var signal_name: StringName = pair[0]
		var callable: Callable = pair[1]
		if controller.has_signal(signal_name) and controller.is_connected(signal_name, callable):
			controller.disconnect(signal_name, callable)


func _on_controller_armed(mode_key: String) -> void:
	armed.emit(mode_key)


func _on_controller_disarmed() -> void:
	disarmed.emit()


func _on_controller_arm_failed(reason_key: String) -> void:
	arm_failed.emit(reason_key)


func _on_controller_mode_changed(mode_key: String) -> void:
	flight_mode_changed.emit(mode_key)


## Los cuatro motores, en el orden del mezclador. Pensado para el banco de pruebas
## y las herramientas; el gameplay habla con el dron, no con sus motores.
func get_motors() -> Array[DroneMotor]:
	return _motors


## Las cuatro hélices, en el mismo orden que [method get_motors].
func get_propellers() -> Array[DronePropeller]:
	return _propellers


## Posición de cada hélice respecto del centro de masas, en ejes del cuerpo.
func get_propeller_offsets() -> PackedVector3Array:
	return _prop_offsets


## Cantidad de sub-pasos para un paso de física de [param step] segundos.
##
## `docs/03` §2.5 fija 10 sub-pasos armado y 1 desarmado **a 100 Hz**. Acá eso se
## expresa como «sub-pasos de [constant TARGET_SUBSTEP_SECONDS]», que al paso
## nominal de 10 ms da exactamente 10 y además conserva la fidelidad del lazo
## cuando el paso cambia: con `Engine.time_scale` acelerado —que es como
## `flight_bench` simula 60 s de vuelo en pocos segundos— el paso de física crece
## y el sub-paso sigue midiendo 1 ms.
func _substep_count(step: float) -> int:
	if not _armed:
		return SUBSTEPS_IDLE
	return clampi(int(ceil(step / TARGET_SUBSTEP_SECONDS)), 1, MAX_SUBSTEPS)


## Empieza a medir el coste del integrador y pone el acumulador a cero.
func start_profiling() -> void:
	profiling = true
	reset_profile()


## Deja de medir. Los valores acumulados siguen disponibles.
func stop_profiling() -> void:
	profiling = false


## Vacía el acumulador de la medida de coste.
func reset_profile() -> void:
	_profile_total_usec = 0
	_profile_peak_usec = 0
	_profile_ticks = 0


## Coste medio del integrador por tick de física, en ms. Es el número que
## presupuesta `docs/03` §2.5: «el tick de física del dron debe costar < 1.6 ms».
func get_profile_average_ms() -> float:
	if _profile_ticks <= 0:
		return 0.0
	return float(_profile_total_usec) / float(_profile_ticks) / 1000.0


## Peor tick medido desde el último [method reset_profile], en ms.
func get_profile_peak_ms() -> float:
	return float(_profile_peak_usec) / 1000.0


## Ticks de física incluidos en la medida de coste.
func get_profile_ticks() -> int:
	return _profile_ticks


## Sub-pasos que usó el último tick de física. A 100 Hz vale
## [constant SUBSTEPS_ARMED] armado y [constant SUBSTEPS_IDLE] desarmado.
func get_last_substep_count() -> int:
	return _last_substeps


## Las mallas `prop_N` del modelo, en el orden del mezclador. Puede haber huecos
## `null` si la escena no lleva modelo. Lo consume `flight_bench`.
func get_blade_meshes() -> Array[MeshInstance3D]:
	return _blade_meshes


## Las mallas `prop_disk_N` del modelo, en el mismo orden.
func get_disk_meshes() -> Array[MeshInstance3D]:
	return _disk_meshes


## Deja el cuerpo exactamente como lo pide `docs/03` §2.1. La escena ya trae estos
## valores, pero fijarlos acá evita que un `.tscn` mal editado rompa la física en
## silencio.
func _configure_body() -> void:
	custom_integrator = true
	gravity_scale = 0.0
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 6)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	inertia = INERTIA
	collision_layer = PhysicsLayers.DRONE
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ENEMY_BODY \
			| PhysicsLayers.ENEMY_WEAK | PhysicsLayers.CITY | PhysicsLayers.DEBRIS


## Recoge los cuatro motores bajo `Motors/`, los ordena por
## [member DroneMotor.motor_index] y memoriza la posición de cada hélice.
func _collect_motors() -> void:
	_motors.clear()
	_propellers.clear()
	var container := get_node_or_null(^"Motors")
	if container == null:
		push_error("Drone: falta el nodo 'Motors' en %s." % name)
		return
	var found: Array[DroneMotor] = []
	for child: Node in container.get_children():
		var motor := child as DroneMotor
		if motor != null:
			found.append(motor)
	found.sort_custom(func(a: DroneMotor, b: DroneMotor) -> bool:
			return a.motor_index < b.motor_index)
	if found.size() != 4:
		push_error("Drone: se esperaban 4 motores bajo 'Motors' y hay %d." % found.size())

	var inverse := global_transform.affine_inverse()
	_prop_offsets.resize(found.size())
	_prop_heights.resize(found.size())
	for index: int in found.size():
		var motor := found[index]
		motor.thrust_scale = _thrust_scale
		var propeller := motor.get_node_or_null(^"Propeller") as DronePropeller
		motor.propeller = propeller
		_motors.append(motor)
		_propellers.append(propeller)
		var origin := propeller.global_transform.origin if propeller != null \
				else motor.global_transform.origin
		_prop_offsets[index] = inverse * origin
		_prop_heights[index] = DronePropeller.NO_GROUND
	_commands.resize(_motors.size())
	_fill_commands(0.0)


## Capa visual (1..20) reservada para las piezas del propio dron que la cámara FPV no
## debe dibujar: la carcasa `camera` del modelo voxel queda justo delante del lente y,
## con 150° de ojo de pez, tapaba el centro de la imagen. Las cámaras externas la ven.
const FPV_HIDDEN_VISUAL_LAYER: int = 20


## Empareja las mallas `prop_N` y `prop_disk_N` del GLB con su motor usando el
## metadato `motor_index` que escribe `asset_import/import_drone.gd`. Buscar por
## metadato y no por ruta deja libre el nombre del nodo del modelo. Además manda la
## pieza `camera` a [constant FPV_HIDDEN_VISUAL_LAYER].
func _collect_model_meshes() -> void:
	_blade_meshes.clear()
	_disk_meshes.clear()
	_blade_spins.clear()
	var count := _motors.size()
	_blade_meshes.resize(count)
	_disk_meshes.resize(count)
	_blade_spins.resize(count)
	for index: int in count:
		_blade_spins[index] = _motors[index].spin
	var model := get_node_or_null(^"Model")
	if model == null:
		return
	for node: Node in _descendants(model):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if String(mesh.name) == "camera":
			mesh.layers = 1 << (FPV_HIDDEN_VISUAL_LAYER - 1)
			continue
		if not mesh.has_meta(&"motor_index"):
			continue
		var slot := int(mesh.get_meta(&"motor_index")) - 1
		if slot < 0 or slot >= count:
			continue
		var mesh_name := String(mesh.name)
		if mesh_name.begins_with("prop_disk_"):
			_disk_meshes[slot] = mesh
		elif mesh_name.begins_with("prop_"):
			_blade_meshes[slot] = mesh
			if mesh.has_meta(&"spin"):
				_blade_spins[slot] = int(mesh.get_meta(&"spin"))


## Precalcula los factores que no cambian entre ticks: medio `ρ·Cd·A` por eje y la
## inversa de la inercia.
func _cache_constants() -> void:
	_drag_factor = Vector3(
			0.5 * AIR_DENSITY * DRAG_CD.x * DRAG_AREA.x,
			0.5 * AIR_DENSITY * DRAG_CD.y * DRAG_AREA.y,
			0.5 * AIR_DENSITY * DRAG_CD.z * DRAG_AREA.z)
	_inertia_inverse = Vector3(1.0 / INERTIA.x, 1.0 / INERTIA.y, 1.0 / INERTIA.z)


## Toma la masa de `QuadSettings` (`docs/04` §3.6): peso en seco más batería.
func _apply_mass() -> void:
	var total: float = QuadSettings.total_mass()
	if total > 0.0:
		mass = total
	_mass_inverse = 1.0 / maxf(mass, 0.001)


func _on_quad_settings_updated() -> void:
	_apply_mass()


## Comandos de motor de este sub-paso: los del controlador si lo hay, los de
## prueba si no.
func _resolve_commands(dt: float) -> PackedFloat32Array:
	if controller != null and controller.has_method(&"integrate"):
		var returned: Variant = controller.call(&"integrate", dt, _flight_state)
		var values := returned as Array
		if values != null:
			for index: int in _commands.size():
				_commands[index] = float(values[index]) if index < values.size() else 0.0
			return _commands
	for index: int in _commands.size():
		_commands[index] = test_motor_commands[index] if index < test_motor_commands.size() \
				else 0.0
	return _commands


func _fill_commands(value: float) -> void:
	for index: int in _commands.size():
		_commands[index] = value


## Lee la altura de cada hélice una vez por tick. Los `RayCast3D` ya se
## actualizaron en este paso de física; consultar el espacio desde dentro de
## [method _integrate_forces] no está permitido.
func _read_ground_heights() -> void:
	for index: int in _propellers.size():
		var propeller := _propellers[index]
		_prop_heights[index] = propeller.measure_height_agl() if propeller != null \
				else DronePropeller.NO_GROUND


## Altura sobre el terreno del dron: la menor de las cuatro hélices que vean
## suelo, o `−1` si ninguna lo ve.
func _lowest_height() -> float:
	var lowest := DronePropeller.NO_GROUND
	for height: float in _prop_heights:
		if height < 0.0:
			continue
		if lowest < 0.0 or height < lowest:
			lowest = height
	return lowest


## Detecta el choque comparando la velocidad con la que dejamos el cuerpo al
## final del tick anterior: si Jolt la cambió en más de [constant CRASH_DELTA_V]
## es que hubo un contacto (`docs/03` §2.5).
func _detect_impact(state: PhysicsDirectBodyState3D) -> void:
	if not _has_expected_velocity:
		return
	var delta := (state.linear_velocity - _expected_velocity).length()
	if delta > CRASH_DELTA_V:
		_report_impact(delta)


func _on_body_entered(_body: Node) -> void:
	# El contacto por sí solo no es un choque: aterrizar también lo dispara. La
	# velocidad de llegada es la que decide.
	_report_impact(linear_velocity.length())


func _report_impact(impact_speed: float) -> void:
	if impact_speed <= CRASH_DELTA_V or _crash_cooldown > 0.0:
		return
	_crash_cooldown = CRASH_COOLDOWN
	crashed.emit(impact_speed)


## Recorre una jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
