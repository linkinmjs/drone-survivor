## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Lectura de la radio: traduce mando y teclado a [FlightCommand] y a las acciones
## de vuelo (`docs/03` §4).
##
## Es hermano del dron en `drone_rig.tscn` y le habla solo por su interfaz pública
## ([method Drone.update_command], [method Drone.arm]…): el dron es la fachada del
## núcleo de vuelo y la radio no conoce al `FlightController`.
##
## Dos caminos para los cuatro ejes, con el mismo resultado:
## - **Con mando**, [method Controls.get_flight_input] devuelve los ejes crudos ya
##   calibrados (mín/centro/máx, inversión y zona muerta con reescalado, `docs/04`
##   §3.3). Son ejes **físicos**: en un stick de pulgar, arriba es −1.
## - **Sin mando**, el par de acciones del `InputMap` de cada eje (`docs/02` §4.2),
##   que ya trae el signo resuelto porque `throttle_up` está atado a `axis_value`
##   −1.0.
##
## De ahí la conversión de signos, que es la misma por los dos caminos:
## `throttle = (1 − eje)/2` (stick arriba = 1), `pitch = −eje` (arriba = morro
## arriba), `roll = +eje` (derecha = ala derecha abajo) y `yaw = −eje` (izquierda =
## morro a la izquierda, que es el positivo de `docs/03` §3.5).
##
## Un stick de pulgar centrado da **acelerador 0.5**, como pide §4. Eso vale para
## volar pero no para armar, porque §3.3 exige `throttle < 0.02`: con un gamepad
## hay que bajar el stick izquierdo a fondo antes de armar. Con una radio de
## verdad, cuyo acelerador no vuelve al centro, el gesto es el de siempre.
##
## Los switches de tres posiciones de una radio llegan como una **banda de eje**,
## no como un botón. Para esos bindings ([constant ControllerAction.Type.AXIS] en
## `Controls.action_list`) la radio sintetiza `InputEventAction` al entrar y al
## salir de la banda, con [constant AXIS_HYSTERESIS] de histéresis para que un
## switch que tiembla en el borde no dispare la acción cincuenta veces por segundo.
class_name RadioController extends Node

## Se emite con la acción `respawn`. Lo escucha `DroneRig`, que es quien sabe
## dónde está el punto de reaparición.
signal reset_requested()

## Se emite al presionar y al soltar `fire` (`docs/08`).
signal fire_changed(pressed: bool)

## Se emite al presionar y al soltar `fire_alt`.
signal fire_alt_changed(pressed: bool)

## Se emite con la acción `lock_target`.
signal lock_pressed()

## Se emite con la acción `cycle_target`.
signal cycle_target_pressed()

## Histéresis de las bandas de eje, en unidades de eje (`docs/03` §4).
const AXIS_HYSTERESIS: float = 0.05

## Dron al que manda esta radio. Lo cablea `drone_rig.tscn`.
@export var target: Drone

## En `false` la radio deja de leer sticks y acciones: el dron se queda con el
## último comando. Lo usan la pausa, las cinemáticas y los checks que necesitan
## escribir el `FlightCommand` a mano.
@export var enabled: bool = true

var _command: FlightCommand = FlightCommand.new()
var _turtle_held: bool = false
var _axis_switches: Dictionary[StringName, bool] = {}


func _ready() -> void:
	var _discard := Controls.bindings_updated.connect(_on_bindings_updated)


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	PerfProbe.begin(&"drone_misc")
	_read_sticks()
	_poll_axis_switches()
	if target != null:
		target.update_command(_command)
	PerfProbe.end(&"drone_misc")


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or event.is_echo():
		return
	# `mode_turtle` es un mantenido: no elige modo por sí solo, habilita que el
	# próximo armado entre en TURTLE (`docs/03` §3.2).
	if event.is_action_pressed(&"mode_turtle"):
		_turtle_held = true
	elif event.is_action_released(&"mode_turtle"):
		_turtle_held = false

	if event.is_action_pressed(&"toggle_arm"):
		_toggle_arm()
	elif event.is_action_pressed(&"arm"):
		_request_arm()
	elif event.is_action_released(&"arm"):
		_request_disarm()

	if event.is_action_pressed(&"respawn"):
		reset_requested.emit()
	if event.is_action_pressed(&"cycle_flight_modes") and target != null:
		target.cycle_mode()
	if event.is_action_pressed(&"mode_horizon") and target != null:
		target.select_mode(FlightController.MODE_HORIZON)

	if event.is_action_pressed(&"fire"):
		fire_changed.emit(true)
	elif event.is_action_released(&"fire"):
		fire_changed.emit(false)
	if event.is_action_pressed(&"fire_alt"):
		fire_alt_changed.emit(true)
	elif event.is_action_released(&"fire_alt"):
		fire_alt_changed.emit(false)
	if event.is_action_pressed(&"lock_target"):
		lock_pressed.emit()
	if event.is_action_pressed(&"cycle_target"):
		cycle_target_pressed.emit()


## Deflexión del stick izquierdo como `(guiñada, acelerador)` en `[−1, 1]`
## (`docs/03` §4). El acelerador va como deflexión, o sea `2·t − 1`.
func get_left_stick() -> Vector2:
	return Vector2(_command.yaw, _command.throttle * 2.0 - 1.0)


## Deflexión del stick derecho como `(alabeo, cabeceo)` en `[−1, 1]`.
func get_right_stick() -> Vector2:
	return Vector2(_command.roll, _command.pitch)


## Comando vivo que la radio le pasa al dron. No se duplica.
func get_command() -> FlightCommand:
	return _command


## `true` mientras la acción `mode_turtle` esté mantenida.
func is_turtle_held() -> bool:
	return _turtle_held


# --- Internos --------------------------------------------------------------------------------


## Reconstruye los cuatro ejes del [FlightCommand] de este frame de física.
func _read_sticks() -> void:
	var axes: Dictionary = Controls.get_flight_input()
	if axes.is_empty():
		# Sin mando: el par de acciones de cada eje ya trae el signo resuelto.
		_command.set_axes(
				(Input.get_axis(&"throttle_down", &"throttle_up") + 1.0) * 0.5,
				Input.get_axis(&"roll_left", &"roll_right"),
				Input.get_axis(&"pitch_down", &"pitch_up"),
				Input.get_axis(&"yaw_right", &"yaw_left"))
		return
	_command.set_axes(
			(1.0 - float(axes.get("throttle", 1.0))) * 0.5,
			float(axes.get("roll", 0.0)),
			-float(axes.get("pitch", 0.0)),
			-float(axes.get("yaw", 0.0)))


## Convierte las bandas de eje de `Controls.action_list` en pulsaciones, con
## [method _send_synthetic_action].
func _poll_axis_switches() -> void:
	if not Controls.has_joypad():
		return
	var device := maxi(Controls.active_device, 0)
	for action: ControllerAction in Controls.action_list:
		if not action.bound or action.type != ControllerAction.Type.AXIS:
			# Dejó de ser una banda de eje: hay que olvidar su estado. Si quedara
			# marcada como «dentro», un binding de eje posterior arrancaría con la
			# histéresis de salida y la acción podría no soltarse nunca.
			_forget_axis_switch(action.action_name)
			continue
		var value := Input.get_joy_axis(device, action.axis as JoyAxis)
		var was_inside := bool(_axis_switches.get(action.action_name, false))
		var inside := was_inside
		if was_inside:
			# Para salir hay que abandonar la banda ensanchada: entrar cuesta
			# menos que salir, que es lo que hace que no repique.
			inside = value >= action.axis_min - AXIS_HYSTERESIS \
					and value <= action.axis_max + AXIS_HYSTERESIS
		else:
			inside = action.contains(value)
		if inside == was_inside:
			continue
		_axis_switches[action.action_name] = inside
		_send_synthetic_action(action.action_name, inside)


## Un rebinding cambia el tipo y la banda de cualquier acción, así que el estado
## acumulado deja de valer: se descarta entero para que la próxima lectura decida
## desde cero (`docs/04` §3.3).
func _on_bindings_updated() -> void:
	for action_name: StringName in _axis_switches.keys():
		_forget_axis_switch(action_name)
	_axis_switches.clear()


## Olvida la banda de [param action_name] y, si estaba marcada como «dentro», sintetiza
## el `release`: sin él la acción quedaría apretada para siempre en el `InputMap`.
func _forget_axis_switch(action_name: StringName) -> void:
	if not _axis_switches.has(action_name):
		return
	var was_inside := bool(_axis_switches[action_name])
	var _discard := _axis_switches.erase(action_name)
	if was_inside:
		_send_synthetic_action(action_name, false)


## Publica un `InputEventAction` por el bucle de entrada, en vez de llamar directo al
## dron, para que el resto del juego —HUD, menús, arma— vea exactamente el mismo evento
## que vería con la acción atada a un botón.
func _send_synthetic_action(action_name: StringName, pressed: bool) -> void:
	var synthetic := InputEventAction.new()
	synthetic.action = action_name
	synthetic.pressed = pressed
	synthetic.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(synthetic)


func _toggle_arm() -> void:
	if target == null:
		return
	if target.is_armed():
		_request_disarm()
	else:
		_request_arm()


## Armado: si `mode_turtle` está mantenido se intenta entrar en TURTLE primero.
## El controlador rechaza el modo si el dron no está boca abajo, y entonces el
## armado sigue siendo el normal (`docs/03` §3.2).
func _request_arm() -> void:
	if target == null:
		return
	if _turtle_held:
		target.select_mode(FlightController.MODE_TURTLE)
	var _discard := target.arm()


func _request_disarm() -> void:
	if target == null:
		return
	target.disarm()
