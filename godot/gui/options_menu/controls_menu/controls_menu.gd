## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Controles (`docs/04` §4.5).
##
## Cinco bloques, en el orden en que el jugador los necesita:
##
## 1. **Dispositivo**: qué mando manda. Lista los joypads conectados con su
##    nombre y su GUID abreviado, ofrece marcarlo como preferido y, si el
##    jugador mueve un eje de otro mando, propone cambiar con `UI.confirm()`.
## 2. **Vista en vivo**: ocho barras de eje y dieciséis testigos de botón que se
##    refrescan en [method _process]. Es lo primero que se mira cuando «el mando
##    no responde»: si acá tampoco se mueve nada, el problema no es el juego.
## 3. **Ejes de vuelo**: qué eje físico usa cada uno de los cuatro ejes de vuelo,
##    si está invertido y si tiene calibración propia; más el botón que abre el
##    asistente de calibración de `docs/04` §4.6.
## 4. **Acciones**: una fila [GUIControllerBinding] por cada acción asignable de
##    `Controls.action_list`; al activarla se abre el [BindingPopup].
## 5. **Restablecer**: vuelve la calibración y los bindings de este mando a los
##    de fábrica, con confirmación.
##
## Nada se guarda al salir: cada cambio llama en el acto al método de `Controls`
## que corresponde, y ese autoload es el único que escribe `InputMap.cfg`.
class_name ControlsMenu
extends MenuScreen

## Asistente de calibración que abre el botón **Calibrar** (`docs/04` §4.6).
const CALIBRATION_SCENE: String = \
		"res://gui/options_menu/controls_menu/calibration_menu.tscn"

## Ejes físicos que muestra la vista en vivo.
const AXIS_COUNT: int = 8

## Botones físicos que muestra la vista en vivo.
const BUTTON_COUNT: int = 16

## Clave de traducción del nombre de cada eje de vuelo, en el orden de
## `Controls.FLIGHT_AXES`.
const FLIGHT_AXIS_KEYS: Dictionary[StringName, String] = {
	&"throttle": "CTRL_AXIS_THROTTLE",
	&"yaw": "CTRL_AXIS_YAW",
	&"pitch": "CTRL_AXIS_PITCH",
	&"roll": "CTRL_AXIS_ROLL",
}

## Deflexión a partir de la cual se considera que el jugador movió a propósito
## un eje de un mando que no es el activo (`docs/04` §4.5).
const DETECT_THRESHOLD: float = 0.5

## Caracteres del GUID que se muestran junto al nombre del mando.
const GUID_PREFIX: int = 8

## Controles expuestos a los checks por [method control_for].
var _controls: Dictionary[StringName, Control] = {}

var _axis_bars: Array[GUIControllerAxis] = []
var _button_dots: Array[GUIControllerButton] = []
var _invert_checks: Dictionary[StringName, CheckButton] = {}
var _axis_labels: Dictionary[StringName, Label] = {}
var _status_labels: Dictionary[StringName, Label] = {}
var _rows: Dictionary[StringName, GUIControllerBinding] = {}
var _popup: BindingPopup = null
var _content: MarginContainer = null

## Mando que el jugador rechazó como activo; −1 si no hay ninguno pendiente.
var _declined_device: int = -1

var _busy: bool = false
var _syncing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = %Content as MarginContainer
	_build_live_view()
	_build_flight_axes()
	_build_bindings()
	_connect_controls()
	_sync()
	bind_back_button(%ButtonBack)
	initial_focus = %DeviceOption
	var _discard := Controls.bindings_updated.connect(_sync)
	_discard = Controls.active_device_changed.connect(_on_active_device_changed)
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_sync()


## Vista en vivo y autodetección de mando. Se apaga cuando esta pantalla deja de
## ser el contexto activo: con la calibración o un modal encima no tiene sentido
## seguir leyendo ejes ni proponer cambios de mando.
func _process(_delta: float) -> void:
	if not _is_live():
		return
	var device := maxi(Controls.active_device, 0)
	for index: int in _axis_bars.size():
		_axis_bars[index].set_axis_value(Input.get_joy_axis(device, index as JoyAxis))
	for index: int in _button_dots.size():
		_button_dots[index].set_pressed_state(
				Input.is_joy_button_pressed(device, index as JoyButton))
	_detect_other_device()


# --- Interfaz pública ------------------------------------------------------------------------

## Control asociado a una clave de ajuste, o `null` si no existe. Lo usan los checks.
func control_for(key: StringName) -> Control:
	return _controls.get(key, null)


## Fila de una acción asignable, o `null` si esa acción no se lista.
func binding_row(action_name: StringName) -> GUIControllerBinding:
	return _rows.get(action_name, null)


## Interruptor de inversión de un eje de vuelo, o `null`.
func invert_check(axis_name: StringName) -> CheckButton:
	return _invert_checks.get(axis_name, null)


## Barra de la vista en vivo de un eje físico, o `null` si el índice no existe.
func axis_bar(index: int) -> GUIControllerAxis:
	return _axis_bars[index] if index >= 0 and index < _axis_bars.size() else null


## Testigo de la vista en vivo de un botón físico, o `null`.
func button_dot(index: int) -> GUIControllerButton:
	return _button_dots[index] if index >= 0 and index < _button_dots.size() else null


## Popup de asignación abierto, o `null` si no hay ninguno.
func active_popup() -> BindingPopup:
	return _popup


## Verdadero mientras hay un popup, un modal o el asistente abiertos desde acá.
func is_busy() -> bool:
	return _busy


# --- Construcción ----------------------------------------------------------------------------

## Ocho barras de eje en dos columnas y dieciséis testigos de botón en dos filas
## de ocho. Los widgets no tienen escena: se instancian acá y los ordenan las
## rejillas de `controls_menu.tscn`.
func _build_live_view() -> void:
	var axis_grid := %AxisGrid as GridContainer
	for index: int in AXIS_COUNT:
		var caption := Label.new()
		caption.theme_type_variation = &"CaptionLabel"
		caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		axis_grid.add_child(caption)
		var bar := GUIControllerAxis.new()
		bar.setup(index)
		axis_grid.add_child(bar)
		_axis_bars.append(bar)
		_axis_labels[StringName("axis_%d" % index)] = caption

	var button_grid := %ButtonGrid as GridContainer
	for index: int in BUTTON_COUNT:
		var dot := GUIControllerButton.new()
		dot.setup(index)
		button_grid.add_child(dot)
		_button_dots.append(dot)


## Una fila por eje de vuelo: nombre, eje físico asignado, estado de calibración
## e interruptor de inversión.
func _build_flight_axes() -> void:
	var grid := %FlightGrid as GridContainer
	for axis_name: StringName in Controls.FLIGHT_AXES:
		var name_label := Label.new()
		name_label.text = String(FLIGHT_AXIS_KEYS.get(axis_name, ""))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(name_label)

		var axis_label := Label.new()
		axis_label.theme_type_variation = &"ValueLabel"
		axis_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		axis_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(axis_label)
		_axis_labels[axis_name] = axis_label

		var status := Label.new()
		status.theme_type_variation = &"CaptionLabel"
		status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(status)
		_status_labels[axis_name] = status

		var invert := CheckButton.new()
		invert.text = "CTRL_INVERT"
		invert.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(invert)
		_invert_checks[axis_name] = invert
		_controls[StringName("CTRL_INVERT_%s" % String(axis_name).to_upper())] = invert
		var _discard := invert.toggled.connect(_on_invert_toggled.bind(axis_name))


## Una fila por acción asignable, en el orden de `Controls.action_list`.
func _build_bindings() -> void:
	var box := %Bindings as VBoxContainer
	for action: ControllerAction in Controls.action_list:
		var row := GUIControllerBinding.new()
		box.add_child(row)
		row.setup(action)
		_rows[action.action_name] = row
		var _discard := row.clicked.connect(_on_row_clicked)


func _connect_controls() -> void:
	_controls[&"CTRL_ACTIVE_CONTROLLER"] = %DeviceOption
	_controls[&"CTRL_DEFAULT_CONTROLLER"] = %DefaultCheck
	_controls[&"CTRL_CALIBRATE"] = %ButtonCalibrate
	_controls[&"CTRL_RESET"] = %ButtonReset
	(%DeviceOption as OptionButton).set_meta(&"stick_value_control", true)
	var _discard := (%DeviceOption as OptionButton).item_selected.connect(_on_device_selected)
	_discard = (%DefaultCheck as CheckButton).toggled.connect(_on_default_toggled)
	_discard = (%ButtonCalibrate as Button).pressed.connect(_on_calibrate_pressed)
	_discard = (%ButtonReset as Button).pressed.connect(_on_reset_pressed)


# --- Sincronización --------------------------------------------------------------------------

## Vuelca el estado de `Controls` sobre todos los controles de la pantalla sin
## volver a escribir nada. La bandera evita que fijar un `CheckButton` a mano se
## confunda con un cambio del jugador y termine guardando en bucle.
func _sync() -> void:
	if _syncing or _content == null:
		return
	_syncing = true
	_sync_device()
	_sync_flight_axes()
	for action: ControllerAction in Controls.action_list:
		var row := _rows.get(action.action_name, null) as GUIControllerBinding
		if row != null:
			row.refresh(action)
	_syncing = false


func _sync_device() -> void:
	var option := %DeviceOption as OptionButton
	option.clear()
	var joypads := Input.get_connected_joypads()
	for device: int in joypads:
		option.add_item(_device_title(device))
		option.set_item_metadata(option.item_count - 1, device)
	if joypads.is_empty():
		option.add_item(tr("CTRL_NO_CONTROLLER"))
		option.set_item_metadata(0, -1)
	var wanted := maxi(joypads.find(Controls.active_device), 0)
	option.select(wanted)

	var default_check := %DefaultCheck as CheckButton
	default_check.disabled = Controls.active_controller_guid.is_empty()
	default_check.button_pressed = not Controls.active_controller_guid.is_empty() \
			and Controls.default_controller_guid == Controls.active_controller_guid

	var status := %DeviceStatus as Label
	if Controls.active_controller_name.is_empty():
		status.text = "CTRL_NO_CONTROLLER"
	else:
		status.text = _device_title(Controls.active_device)


## Nombre legible y GUID abreviado de un joypad conectado (`docs/04` §4.5).
func _device_title(device: int) -> String:
	if device < 0 or not Input.get_connected_joypads().has(device):
		return tr("CTRL_NO_CONTROLLER")
	return "%s  ·  %s" % [Input.get_joy_name(device),
			Input.get_joy_guid(device).substr(0, GUID_PREFIX)]


func _sync_flight_axes() -> void:
	for axis_name: StringName in Controls.FLIGHT_AXES:
		var cal := Controls.get_axis_calibration(axis_name)
		var axis_label := _axis_labels.get(axis_name, null) as Label
		if axis_label != null:
			axis_label.text = tr("CTRL_AXIS_N") % int(cal["axis"])
		var status := _status_labels.get(axis_name, null) as Label
		if status != null:
			status.text = "CTRL_CALIBRATED" if _is_calibrated(cal) else "CTRL_UNCALIBRATED"
		var invert := _invert_checks.get(axis_name, null) as CheckButton
		if invert != null:
			invert.button_pressed = bool(cal["inverted"])
	for index: int in _axis_bars.size():
		var caption := _axis_labels.get(StringName("axis_%d" % index), null) as Label
		if caption != null:
			caption.text = tr("CTRL_AXIS_N") % index


## Un eje está calibrado cuando su recorrido ya no es el de fábrica: la
## calibración de `docs/04` §3.3 nace en `[−1, 0, 1]` y el asistente la reemplaza
## por los extremos medidos del mando real.
func _is_calibrated(cal: Dictionary) -> bool:
	return not (is_equal_approx(float(cal["min"]), -1.0)
			and is_equal_approx(float(cal["center"]), 0.0)
			and is_equal_approx(float(cal["max"]), 1.0))


func _is_live() -> bool:
	return is_node_ready() and _content != null and _content.visible \
			and UI.get_active_context() == self and not UI.has_modal()


# --- Dispositivo -----------------------------------------------------------------------------

## Mover un eje de un mando que no es el activo propone cambiarlo (`docs/04` §4.5).
##
## Un mando ya rechazado no se vuelve a proponer hasta que sus ejes vuelvan al
## centro: si no, el stick que el jugador dejó apoyado reabriría la pregunta en
## cuanto cierra la anterior.
func _detect_other_device() -> void:
	if _busy or (Controls.active_device >= 0 and Input.get_connected_joypads().size() < 2):
		return
	for device: int in Input.get_connected_joypads():
		if device == Controls.active_device:
			continue
		if not _is_deflected(device):
			if device == _declined_device:
				_declined_device = -1
			continue
		if device == _declined_device:
			continue
		_propose_device(device)
		return


## Verdadero si algún eje de ese mando está fuera de su centro a propósito.
func _is_deflected(device: int) -> bool:
	for axis: int in AXIS_COUNT:
		if absf(Input.get_joy_axis(device, axis as JoyAxis)) > DETECT_THRESHOLD:
			return true
	return false


func _propose_device(device: int) -> void:
	_busy = true
	var accepted: bool = await UI.confirm(tr("CTRL_DEVICE_SWITCH") % _device_title(device))
	if accepted:
		_apply_device(device)
	else:
		_declined_device = device
	_busy = false


func _apply_device(device: int) -> void:
	Controls.update_active_device(device)
	# Cada mando guarda su calibración y sus bindings en su propia sección, así
	# que cambiar de mando es volver a leer el archivo (`docs/04` §3.3).
	var _discard := Controls.load_input_map()
	Controls.save_input_map()
	_sync()


func _on_device_selected(index: int) -> void:
	if _syncing:
		return
	var option := %DeviceOption as OptionButton
	var device := int(option.get_item_metadata(index))
	if device < 0 or device == Controls.active_device:
		return
	_apply_device(device)


func _on_default_toggled(pressed: bool) -> void:
	if _syncing:
		return
	Controls.set_default_device(Controls.active_controller_guid if pressed else "")


func _on_active_device_changed(_guid: String) -> void:
	_sync()


# --- Ejes de vuelo ---------------------------------------------------------------------------

func _on_invert_toggled(pressed: bool, axis_name: StringName) -> void:
	if _syncing:
		return
	var cal := Controls.get_axis_calibration(axis_name)
	Controls.save_axis_calibration(axis_name, int(cal["axis"]), float(cal["min"]),
			float(cal["center"]), float(cal["max"]), pressed)


func _on_calibrate_pressed() -> void:
	if _busy or UI.has_modal() or not ResourceLoader.exists(CALIBRATION_SCENE):
		return
	var packed := load(CALIBRATION_SCENE) as PackedScene
	if packed == null:
		return
	_busy = true
	await open_submenu(packed, _content)
	_busy = false
	_sync()


# --- Acciones --------------------------------------------------------------------------------

## Abre el popup de asignación y aplica su resultado sobre `Controls`.
func _on_row_clicked(action_name: StringName) -> void:
	if _busy or _popup != null or UI.has_modal():
		return
	var action := Controls.get_action(action_name)
	if action == null:
		return
	_busy = true
	_popup = BindingPopup.new()
	_popup.setup(action)
	add_child(_popup)
	var confirmed: bool = await _popup.closed
	if confirmed:
		_apply_binding(action_name, _popup)
	_popup.queue_free()
	_popup = null
	_busy = false
	_sync()
	_refocus(action_name)


func _apply_binding(action_name: StringName, popup: BindingPopup) -> void:
	if popup.cleared or not popup.action.bound:
		Controls.clear_binding(action_name)
		return
	if popup.action.type == ControllerAction.Type.AXIS:
		Controls.save_axis_binding(action_name, popup.action.axis, popup.action.axis_min,
				popup.action.axis_max)
		return
	var event := InputEventJoypadButton.new()
	event.device = Controls.active_device
	event.button_index = popup.action.button as JoyButton
	Controls.save_binding(action_name, event)


func _refocus(action_name: StringName) -> void:
	var row := _rows.get(action_name, null) as GUIControllerBinding
	if row == null or UI.is_using_mouse() or not row.is_visible_in_tree():
		return
	UI.mute_for(0.12)
	row.grab_focus()


# --- Restablecer -----------------------------------------------------------------------------

func _on_reset_pressed() -> void:
	if _busy or UI.has_modal():
		return
	_busy = true
	var accepted: bool = await UI.confirm("CTRL_RESET_CONFIRM", "UI_CONFIRM", "UI_CANCEL", true)
	if accepted:
		Controls.reset_controller_bindings()
	_busy = false
	_sync()
