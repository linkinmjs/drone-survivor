## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Dispositivo activo por GUID, lista de acciones asignables, reconstrucción del
## `InputMap` desde `InputMap.cfg` y calibración persistida de los cuatro ejes de
## vuelo (`docs/04` §3.3).
##
## Reparto de responsabilidades: el `InputMap` conserva siempre las ocho acciones de
## vuelo mapeadas al dispositivo activo, porque son las que lee `StickNavigation`
## para mover los menús; la calibración fina (mín/centro/máx, inversión y zona
## muerta) la aplica [method get_flight_input], que es lo que consume
## `RadioController` (`docs/03` §4). Godot no sabe reescalar ejes, así que el
## `InputMap` se queda con los umbrales y nada más.
extends Node

## Se emite cuando cambia el mando activo; lleva su GUID (vacío si no hay ninguno).
signal active_device_changed(guid: String)

## Se emite cada vez que se reconstruye el `InputMap` o cambia un binding.
signal bindings_updated

## Nombre del archivo dentro de `Global.config_dir`.
const CONFIG_FILE: String = "InputMap.cfg"

## Sección con el mando activo y el preferido.
const MAIN_SECTION: String = "controls"

## Clave de traducción que `Global.startup_errors` acumula si el archivo está roto.
const ERROR_KEY: String = "ERR_CONFIG_INPUT"

## Zona muerta de [method get_flight_input], con reescalado (`docs/04` §3.3).
const DEADZONE: float = 0.02

## Zona muerta de las acciones de eje del `InputMap` (`docs/02` §4.2). Es baja a
## propósito: la curva y la calibración las aplica [method get_flight_input].
const FLIGHT_ACTION_DEADZONE: float = 0.01

## Los cuatro ejes de vuelo, en el orden del asistente de calibración (`docs/04` §4.6).
const FLIGHT_AXES: Array[StringName] = [&"throttle", &"yaw", &"pitch", &"roll"]

## Índice físico por defecto de cada eje de vuelo, mapeo Mode 2 (`docs/02` §4.2).
const DEFAULT_AXIS_INDEX: Dictionary[StringName, int] = {
	&"throttle": 1,
	&"yaw": 0,
	&"roll": 2,
	&"pitch": 3,
}

## Par de acciones del `InputMap` de cada eje de vuelo: primero la que se dispara
## con el eje en −1.0 y después la de +1.0 (`docs/02` §4.2).
const FLIGHT_AXIS_ACTIONS: Dictionary = {
	&"throttle": [&"throttle_up", &"throttle_down"],
	&"yaw": [&"yaw_left", &"yaw_right"],
	&"pitch": [&"pitch_up", &"pitch_down"],
	&"roll": [&"roll_left", &"roll_right"],
}

## Las 13 acciones asignables, en el orden en que las lista el menú de controles
## (`docs/04` §3.3). `pause_menu` no está: queda fija en Start / Esc.
const BINDABLE_ACTIONS: Array[StringName] = [&"arm", &"toggle_arm", &"respawn",
		&"cycle_flight_modes", &"mode_horizon", &"mode_turtle", &"fire", &"fire_alt",
		&"lock_target", &"cycle_target", &"objective_next", &"objective_skip",
		&"change_camera"]

## Clave de traducción de la etiqueta de cada acción asignable.
const ACTION_LABELS: Dictionary[StringName, String] = {
	&"arm": "CTRL_ACTION_ARM_HOLD",
	&"toggle_arm": "CTRL_ACTION_ARM_TOGGLE",
	&"respawn": "CTRL_ACTION_RESPAWN",
	&"cycle_flight_modes": "CTRL_ACTION_CYCLE_MODES",
	&"mode_horizon": "CTRL_ACTION_MODE_HORIZON",
	&"mode_turtle": "CTRL_ACTION_MODE_TURTLE",
	&"fire": "CTRL_ACTION_FIRE",
	&"fire_alt": "CTRL_ACTION_FIRE_ALT",
	&"lock_target": "CTRL_ACTION_LOCK",
	&"cycle_target": "CTRL_ACTION_CYCLE_TARGET",
	&"objective_next": "CTRL_ACTION_OBJECTIVE_NEXT",
	&"objective_skip": "CTRL_ACTION_OBJECTIVE_SKIP",
	&"change_camera": "CTRL_ACTION_CHANGE_CAMERA",
}

## Botón de joypad por defecto de cada acción asignable (`docs/02` §4.3).
const DEFAULT_BUTTONS: Dictionary[StringName, int] = {
	# `arm` (mantener) no tiene botón por defecto: es para un switch de radio, que el
	# jugador asigna desde Opciones → Controles. En gamepad L1 alterna el armado.
	&"toggle_arm": 9,
	&"respawn": 4,
	&"cycle_flight_modes": 13,
	&"mode_horizon": 11,
	&"mode_turtle": 12,
	&"fire_alt": 10,
	&"cycle_target": 14,
	&"objective_next": 3,
	&"objective_skip": 2,
	&"change_camera": 8,
}

## Banda de eje por defecto de las dos acciones de gatillo (`docs/02` §4.3):
## `[índice, mínimo, máximo]`. Un gatillo estándar reposa en −1.0 y llega a +1.0.
const DEFAULT_AXIS_BINDINGS: Dictionary = {
	&"fire": [5, 0.35, 1.0],
	&"lock_target": [4, 0.35, 1.0],
}

## Atajos de teclado de depuración (`docs/02` §4.3). `docs/04` §3.3 propone además
## Retroceso, Tab y el clic derecho; están en [constant EXTRA_KEYBOARD_SHORTCUTS].
const KEYBOARD_SHORTCUTS: Dictionary[StringName, int] = {
	&"respawn": KEY_R,
	&"cycle_flight_modes": KEY_M,
	&"toggle_arm": KEY_SPACE,
	&"arm": KEY_SHIFT,
	&"mode_horizon": KEY_H,
	&"mode_turtle": KEY_T,
	&"pause_menu": KEY_ESCAPE,
	&"change_camera": KEY_C,
	&"fire_alt": KEY_F,
	&"lock_target": KEY_Q,
	&"cycle_target": KEY_E,
	&"objective_next": KEY_N,
	&"objective_skip": KEY_K,
}

## Atajos extra de `docs/04` §3.3 que no chocan con los de `docs/02` §4.3. El que
## ese documento propone para `lock_target` (Shift) **no** está: `docs/02` ya le da
## Shift a `arm` y dos acciones con la misma tecla dejarían el mapa ambiguo.
const EXTRA_KEYBOARD_SHORTCUTS: Dictionary[StringName, int] = {
	&"respawn": KEY_BACKSPACE,
	&"cycle_target": KEY_TAB,
}

## Botones de ratón de depuración: disparo principal y secundario (`docs/04` §3.3).
const MOUSE_SHORTCUTS: Dictionary[StringName, int] = {
	&"fire": MOUSE_BUTTON_LEFT,
	&"fire_alt": MOUSE_BUTTON_RIGHT,
}

## GUID del mando elegido por el jugador. Vacío mientras no haya ninguno conectado:
## `ControlHints` lo usa para marcar cuál de los joypads manda.
var active_controller_guid: String = ""

## Nombre legible del mando activo, para la etiqueta del pie de página.
var active_controller_name: String = ""

## Índice de dispositivo del mando activo; −1 cuando no hay ninguno, que es el
## valor que `InputEventJoypad*` interpreta como «cualquier dispositivo».
var active_device: int = -1

## GUID del mando que el jugador marcó como preferido; se elige aunque esté
## enchufado después de otro.
var default_controller_guid: String = ""

## Las 13 acciones asignables con su binding vivo (`docs/04` §3.3).
var action_list: Array[ControllerAction] = []

## Solo para pruebas: se comporta como si hubiera un joypad conectado, de modo que
## un check headless pueda inyectar ejes con `Input.parse_input_event()`.
var assume_joypad: bool = false

## Calibración por eje de vuelo: `{axis, inverted, min, center, max}`.
var _calibration: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	action_list = create_action_list()
	_reset_calibration()
	var _discard := Input.joy_connection_changed.connect(_on_joy_connection_changed)


# --- Carga y guardado ------------------------------------------------------------------------

## Lee `InputMap.cfg`, elige el mando activo y reconstruye el `InputMap`.
##
## Con [param update_controller] en `true` vuelve a detectar joypads y elige el
## activo por GUID (el preferido primero) o, si no encuentra ninguno, el primero
## conectado. Devuelve `""` si todo fue bien —el archivo ausente no es error— o
## [constant ERROR_KEY] si el archivo está corrupto, en cuyo caso se reconstruye el
## mapa con los bindings de fábrica y se reescribe (`docs/04` §2).
func load_input_map(update_controller: bool = false) -> String:
	Global.initialize()
	var path := Global.config_path(CONFIG_FILE)
	var config := ConfigFile.new()
	var err := config.load(path)
	var broken := err != OK and err != ERR_FILE_NOT_FOUND
	if broken:
		Global.log_error(err, "no se pudo leer %s: %s" % [path, error_string(err)])
		config = ConfigFile.new()
	var readable := err == OK
	if readable:
		default_controller_guid = String(config.get_value(MAIN_SECTION,
				"default_controller_guid", ""))
	if update_controller or active_device < 0:
		var wanted := default_controller_guid
		if wanted.is_empty() and readable:
			wanted = String(config.get_value(MAIN_SECTION, "active_controller_guid", ""))
		_select_device(wanted)
	_reset_calibration()
	action_list = create_action_list()
	if readable:
		_read_device_section(config)
	rebuild_input_map()
	if not readable:
		# Archivo ausente o roto: se deja escrito el mapa de fábrica del mando
		# activo, para no repetir el mismo diagnóstico en cada arranque.
		save_input_map()
	bindings_updated.emit()
	return ERROR_KEY if broken else ""


## Escribe `InputMap.cfg` con el mando activo, el preferido, la calibración de los
## cuatro ejes de vuelo y el binding de las 13 acciones asignables.
func save_input_map() -> void:
	Global.initialize()
	var path := Global.config_path(CONFIG_FILE)
	var config := ConfigFile.new()
	# Se conserva lo que haya de otros mandos: cada uno tiene su propia sección.
	var _discard := config.load(path)
	config.set_value(MAIN_SECTION, "active_controller_guid", active_controller_guid)
	config.set_value(MAIN_SECTION, "active_controller_name", active_controller_name)
	config.set_value(MAIN_SECTION, "default_controller_guid", default_controller_guid)
	var section := device_section()
	for axis_name: StringName in FLIGHT_AXES:
		var cal := get_axis_calibration(axis_name)
		config.set_value(section, "%s_axis" % axis_name, int(cal["axis"]))
		config.set_value(section, "%s_inverted" % axis_name, bool(cal["inverted"]))
		config.set_value(section, "%s_min" % axis_name, float(cal["min"]))
		config.set_value(section, "%s_center" % axis_name, float(cal["center"]))
		config.set_value(section, "%s_max" % axis_name, float(cal["max"]))
	for action: ControllerAction in action_list:
		var prefix := String(action.action_name)
		config.set_value(section, "%s_type" % prefix,
				"axis" if action.type == ControllerAction.Type.AXIS else "button")
		config.set_value(section, "%s_button" % prefix, action.button)
		config.set_value(section, "%s_axis" % prefix, action.axis)
		config.set_value(section, "%s_min" % prefix, action.axis_min)
		config.set_value(section, "%s_max" % prefix, action.axis_max)
	var err := config.save(path)
	if err != OK:
		Global.log_error(err, "no se pudo guardar %s: %s" % [path, error_string(err)])


## Nombre de la sección del mando activo: `controls_<GUID>`. Sin mando conectado se
## usa `controls_default`, para que la configuración de un arranque sin joypad no
## se pierda ni se mezcle con la de un mando real.
func device_section() -> String:
	if active_controller_guid.is_empty():
		return "controls_default"
	return "controls_%s" % active_controller_guid


# --- Dispositivo -----------------------------------------------------------------------------

## Fija el mando activo por índice de dispositivo; −1 para «ninguno». Emite
## [signal active_device_changed] cuando efectivamente cambia.
func update_active_device(device: int) -> void:
	# `get_joy_guid()` sobre un dispositivo que no está conectado empuja un error del
	# motor; con un joypad simulado (`assume_joypad`) eso pasa siempre, así que se
	# pregunta antes y se acepta un GUID vacío.
	var connected := device >= 0 and Input.get_connected_joypads().has(device)
	var guid := Input.get_joy_guid(device) if connected else ""
	var joy_name := Input.get_joy_name(device) if connected else ""
	var changed := device != active_device or guid != active_controller_guid
	active_device = device
	active_controller_guid = guid
	active_controller_name = joy_name
	if changed:
		active_device_changed.emit(guid)


## Marca un GUID como mando preferido y lo guarda.
func set_default_device(guid: String) -> void:
	default_controller_guid = guid
	save_input_map()
	bindings_updated.emit()


## GUID de todos los joypads conectados, en orden de dispositivo.
func get_joypad_guid_list() -> Array[String]:
	var guids: Array[String] = []
	for device: int in Input.get_connected_joypads():
		guids.append(Input.get_joy_guid(device))
	return guids


## Verdadero si hay un mando utilizable (o si un check pidió simular uno).
func has_joypad() -> bool:
	return assume_joypad or not Input.get_connected_joypads().is_empty()


# --- Calibración de los ejes de vuelo --------------------------------------------------------

## Guarda la calibración de un eje de vuelo, reconstruye el `InputMap` y persiste.
func save_axis_calibration(axis_name: StringName, index: int, lo: float, center: float,
		hi: float, inverted: bool) -> void:
	if not DEFAULT_AXIS_INDEX.has(axis_name):
		push_error("Eje de vuelo desconocido: %s" % axis_name)
		return
	_calibration[axis_name] = {
		"axis": maxi(index, 0),
		"inverted": inverted,
		"min": clampf(minf(lo, hi), -1.0, 1.0),
		"center": clampf(center, -1.0, 1.0),
		"max": clampf(maxf(lo, hi), -1.0, 1.0),
	}
	rebuild_input_map()
	save_input_map()
	bindings_updated.emit()


## Copia de la calibración de un eje de vuelo: `{axis, inverted, min, center, max}`.
## Quien la modifique no toca el original.
func get_axis_calibration(axis_name: StringName) -> Dictionary:
	if not _calibration.has(axis_name):
		return _default_calibration(axis_name)
	return _calibration[axis_name].duplicate()


# --- Bindings de acciones --------------------------------------------------------------------

## Lista de fábrica de las 13 acciones asignables (`docs/04` §3.3), con el binding
## por defecto de `docs/02` §4.3.
func create_action_list() -> Array[ControllerAction]:
	var list: Array[ControllerAction] = []
	for action_name: StringName in BINDABLE_ACTIONS:
		var action := ControllerAction.new(action_name,
				String(ACTION_LABELS.get(action_name, "")))
		if DEFAULT_AXIS_BINDINGS.has(action_name):
			var band: Array = DEFAULT_AXIS_BINDINGS[action_name]
			action.bind_axis(int(band[0]), float(band[1]), float(band[2]))
		else:
			action.bind_button(int(DEFAULT_BUTTONS.get(action_name, -1)))
		list.append(action)
	return list


## Devuelve la acción asignable de ese nombre, o `null` si no es asignable.
func get_action(action_name: StringName) -> ControllerAction:
	for action: ControllerAction in action_list:
		if action.action_name == action_name:
			return action
	return null


## Ata una acción al botón o al eje que trae [param event] y persiste.
func save_binding(action_name: StringName, event: InputEvent) -> void:
	var action := get_action(action_name)
	if action == null:
		return
	if event is InputEventJoypadButton:
		action.bind_button(int((event as InputEventJoypadButton).button_index))
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var value := motion.axis_value
		if value >= 0.0:
			action.bind_axis(int(motion.axis), 0.5, 1.0)
		else:
			action.bind_axis(int(motion.axis), -1.0, -0.5)
	else:
		return
	rebuild_input_map()
	save_input_map()
	bindings_updated.emit()


## Ata una acción a la banda `[lo, hi]` de un eje analógico y persiste.
func save_axis_binding(action_name: StringName, axis: int, lo: float, hi: float) -> void:
	var action := get_action(action_name)
	if action == null:
		return
	action.bind_axis(axis, lo, hi)
	rebuild_input_map()
	save_input_map()
	bindings_updated.emit()


## Quita el binding de mando de una acción y persiste. Los atajos de teclado y de
## ratón de esa acción se conservan.
func clear_binding(action_name: StringName) -> void:
	var action := get_action(action_name)
	if action == null:
		return
	action.clear()
	rebuild_input_map()
	save_input_map()
	bindings_updated.emit()


## Devuelve la calibración y los bindings del mando activo a los de fábrica
## (`CTRL_RESET_CONFIRM`).
func reset_controller_bindings() -> void:
	_reset_calibration()
	action_list = create_action_list()
	rebuild_input_map()
	save_input_map()
	bindings_updated.emit()


# --- `InputMap` ------------------------------------------------------------------------------

## Rehace los eventos de joypad del `InputMap`: las ocho acciones de los cuatro ejes
## de vuelo y las 13 acciones asignables. Los eventos de teclado y de ratón no se
## tocan, así que los atajos de `project.godot` sobreviven a cada recarga.
func rebuild_input_map() -> void:
	for axis_name: StringName in FLIGHT_AXES:
		var cal := get_axis_calibration(axis_name)
		var index := int(cal["axis"])
		var inverted := bool(cal["inverted"])
		var actions: Array = FLIGHT_AXIS_ACTIONS[axis_name]
		for slot: int in actions.size():
			var action := StringName(actions[slot])
			_ensure_action(action, FLIGHT_ACTION_DEADZONE)
			_erase_joypad_events(action)
			var motion := InputEventJoypadMotion.new()
			motion.device = active_device
			motion.axis = index as JoyAxis
			var direction := -1.0 if slot == 0 else 1.0
			motion.axis_value = -direction if inverted else direction
			InputMap.action_add_event(action, motion)
	for action: ControllerAction in action_list:
		_ensure_action(action.action_name, FLIGHT_ACTION_DEADZONE)
		_erase_joypad_events(action.action_name)
		if not action.bound:
			continue
		if action.type == ControllerAction.Type.AXIS:
			var motion := InputEventJoypadMotion.new()
			motion.device = active_device
			motion.axis = action.axis as JoyAxis
			motion.axis_value = 1.0 if action.axis_max > 0.0 else -1.0
			# Godot solo sabe de umbral, no de banda: el extremo más cercano al
			# centro hace de zona muerta y `RadioController` afina con histéresis.
			InputMap.action_set_deadzone(action.action_name,
					clampf(minf(absf(action.axis_min), absf(action.axis_max)), 0.01, 0.95))
			InputMap.action_add_event(action.action_name, motion)
		else:
			InputMap.action_set_deadzone(action.action_name, 0.5)
			var button := InputEventJoypadButton.new()
			button.device = active_device
			button.button_index = action.button as JoyButton
			InputMap.action_add_event(action.action_name, button)


## Vuelve a poner los atajos de teclado y de ratón de depuración que falten. Es
## idempotente y **no** borra nada: solo sirve para recuperar el mapa después de
## haberlo toqueteado a mano (`docs/04` §3.3).
func restore_keyboard_shortcuts() -> void:
	for source: Dictionary in [KEYBOARD_SHORTCUTS, EXTRA_KEYBOARD_SHORTCUTS]:
		for action_name: StringName in source:
			_ensure_action(action_name, 0.5)
			var key := InputEventKey.new()
			key.physical_keycode = int(source[action_name]) as Key
			if not InputMap.action_has_event(action_name, key):
				InputMap.action_add_event(action_name, key)
	for action_name: StringName in MOUSE_SHORTCUTS:
		_ensure_action(action_name, 0.5)
		var click := InputEventMouseButton.new()
		click.button_index = int(MOUSE_SHORTCUTS[action_name]) as MouseButton
		if not InputMap.action_has_event(action_name, click):
			InputMap.action_add_event(action_name, click)
	bindings_updated.emit()


# --- Lectura de los sticks -------------------------------------------------------------------

## Deflexión de los cuatro ejes de vuelo en `[−1, 1]`, con las claves `throttle`,
## `roll`, `pitch` y `yaw`.
##
## Lee los ejes crudos con `Input.get_joy_axis()` sobre el dispositivo activo y les
## aplica, en este orden, la calibración mín/centro/máx, la inversión y una zona
## muerta de [constant DEADZONE] con reescalado, de modo que el primer grado de
## stick fuera de la zona muerta valga 0 y no un salto.
##
## Devuelve un diccionario **vacío** si no hay mando: `RadioController` lo toma
## como «usá las acciones del `InputMap`» (`docs/03` §4).
func get_flight_input() -> Dictionary:
	if not has_joypad():
		return {}
	var device := maxi(active_device, 0)
	var values: Dictionary = {}
	for axis_name: StringName in FLIGHT_AXES:
		values[String(axis_name)] = _read_flight_axis(device, axis_name)
	return values


# --- Internos --------------------------------------------------------------------------------

## Elige el mando activo: el del GUID pedido si está conectado, si no el primero.
func _select_device(wanted_guid: String) -> void:
	var joypads := Input.get_connected_joypads()
	var chosen := -1
	if not wanted_guid.is_empty():
		for device: int in joypads:
			if Input.get_joy_guid(device) == wanted_guid:
				chosen = device
				break
	if chosen < 0 and not joypads.is_empty():
		chosen = joypads[0]
	update_active_device(chosen)


## Lee la sección del mando activo: calibración de los ejes y binding de las acciones.
func _read_device_section(config: ConfigFile) -> void:
	var section := device_section()
	if not config.has_section(section):
		return
	for axis_name: StringName in FLIGHT_AXES:
		var cal := _default_calibration(axis_name)
		cal["axis"] = maxi(int(config.get_value(section, "%s_axis" % axis_name,
				cal["axis"])), 0)
		cal["inverted"] = bool(config.get_value(section, "%s_inverted" % axis_name,
				cal["inverted"]))
		cal["min"] = clampf(float(config.get_value(section, "%s_min" % axis_name,
				cal["min"])), -1.0, 1.0)
		cal["center"] = clampf(float(config.get_value(section, "%s_center" % axis_name,
				cal["center"])), -1.0, 1.0)
		cal["max"] = clampf(float(config.get_value(section, "%s_max" % axis_name,
				cal["max"])), -1.0, 1.0)
		_calibration[axis_name] = cal
	for action: ControllerAction in action_list:
		var prefix := String(action.action_name)
		if not config.has_section_key(section, "%s_type" % prefix):
			continue
		var kind := String(config.get_value(section, "%s_type" % prefix, "button"))
		if kind == "axis":
			action.bind_axis(int(config.get_value(section, "%s_axis" % prefix, -1)),
					float(config.get_value(section, "%s_min" % prefix, 0.0)),
					float(config.get_value(section, "%s_max" % prefix, 0.0)))
		else:
			action.bind_button(int(config.get_value(section, "%s_button" % prefix, -1)))


## Calibración de fábrica de un eje: su índice de `docs/02` §4.2, sin inversión y
## con el recorrido completo del stick.
func _default_calibration(axis_name: StringName) -> Dictionary:
	return {
		"axis": int(DEFAULT_AXIS_INDEX.get(axis_name, 0)),
		"inverted": false,
		"min": -1.0,
		"center": 0.0,
		"max": 1.0,
	}


func _reset_calibration() -> void:
	_calibration.clear()
	for axis_name: StringName in FLIGHT_AXES:
		_calibration[axis_name] = _default_calibration(axis_name)


## Deflexión calibrada de un eje de vuelo, en `[−1, 1]`.
func _read_flight_axis(device: int, axis_name: StringName) -> float:
	var cal := get_axis_calibration(axis_name)
	var raw := Input.get_joy_axis(device, int(cal["axis"]) as JoyAxis)
	var center := float(cal["center"])
	var value := 0.0
	if raw >= center:
		value = (raw - center) / maxf(float(cal["max"]) - center, 0.001)
	else:
		value = (raw - center) / maxf(center - float(cal["min"]), 0.001)
	value = clampf(value, -1.0, 1.0)
	if bool(cal["inverted"]):
		value = -value
	return _apply_deadzone(value)


## Zona muerta con reescalado: fuera de ella el recorrido restante vuelve a cubrir
## todo `[0, 1]`, así que no hay escalón al salir del centro.
func _apply_deadzone(value: float) -> float:
	var magnitude := absf(value)
	if magnitude <= DEADZONE:
		return 0.0
	return signf(value) * (magnitude - DEADZONE) / (1.0 - DEADZONE)


## Crea la acción en el `InputMap` si el proyecto no la trae.
func _ensure_action(action_name: StringName, deadzone: float) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, deadzone)


## Borra de una acción solo sus eventos de joypad; deja teclado y ratón intactos.
func _erase_joypad_events(action_name: StringName) -> void:
	if not InputMap.has_action(action_name):
		return
	for event: InputEvent in InputMap.action_get_events(action_name):
		if event is InputEventJoypadMotion or event is InputEventJoypadButton:
			InputMap.action_erase_event(action_name, event)


## Un mando que se va deja el mapa en «cualquier dispositivo» y avisa con un GUID
## vacío, para que el dron desarme y el HUD muestre `HUD_NO_CONTROLLER`
## (`docs/04` §10). Uno que llega se adopta si no había ninguno.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		if active_device < 0 or Input.get_joy_guid(device) == default_controller_guid:
			var _discard := load_input_map(true)
		return
	if device != active_device:
		return
	update_active_device(-1)
	var _reloaded := load_input_map(true)
