## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Modal de asignación de una acción a un mando (`docs/04` §4.5).
##
## Flujo: **Escuchar** deja el popup a la espera del siguiente evento de joypad.
## Si llega un botón, la acción queda atada a ese botón; si llega un eje con una
## deflexión mayor que [constant AXIS_THRESHOLD], queda atada a una banda de ese
## eje que el jugador puede afinar con el [GUIControllerAxisRange] de abajo.
## **Borrar** deja la acción sin asignar, **Cancelar** se va sin tocar nada y
## **Confirmar** devuelve el resultado al menú, que es quien escribe en `Controls`.
##
## Dos detalles que el documento pide explícitamente:
##
## - Los eventos de joypad se leen en [method _input], no en `_gui_input`: si se
##   leyeran desde el control con foco, el botón «Escuchar» consumiría como
##   `ui_accept` el mismo botón que el jugador quiere asignar.
## - Mientras escucha, `StickNavigation.suspended` queda en `true` para que mover
##   el stick que se está asignando no navegue el menú de atrás. Al dejar de
##   escuchar —y al cerrar, pase lo que pase— se restaura el valor anterior.
class_name BindingPopup
extends Control

## Se emite al cerrar. [param confirmed] es `true` solo si el jugador confirmó.
signal closed(confirmed: bool)

## Deflexión a partir de la cual un eje cuenta como «movido a propósito».
const AXIS_THRESHOLD: float = 0.5

## Banda que se propone al capturar un eje, desde la mitad del recorrido hasta
## el extremo por el que se lo movió.
const CAPTURED_BAND: float = 0.5

## Ancho de la tarjeta del modal.
const CARD_WIDTH: float = 620.0

## Copia de trabajo de la acción: el popup nunca toca la lista viva de `Controls`
## hasta que el menú aplica el resultado.
var action: ControllerAction = null

## Verdadero si el jugador pidió borrar el binding.
var cleared: bool = false

var _listening: bool = false
var _captured: bool = false
var _suspended_before: bool = false
var _done: bool = false
var _card: PanelContainer = null
var _state: Label = null
var _value: Label = null
var _range: GUIControllerAxisRange = null
var _range_box: VBoxContainer = null
var _buttons: Dictionary[StringName, Button] = {}


## Prepara el popup con una copia de la acción. Se llama antes de agregarlo al árbol.
func setup(source: ControllerAction) -> void:
	action = source.duplicate_action() if source != null else ControllerAction.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if action == null:
		action = ControllerAction.new()
	_build()
	_sync()
	UI.register_context(self)
	_play_open()
	grab_initial_focus.call_deferred()


func _exit_tree() -> void:
	_set_listening(false)
	UI.unregister_context(self)


func _process(_delta: float) -> void:
	if _range == null or _range_box == null or not _range_box.visible or action.axis < 0:
		return
	var device := maxi(Controls.active_device, 0)
	_range.set_live_value(Input.get_joy_axis(device, action.axis as JoyAxis))


# --- Interfaz pública ------------------------------------------------------------------------

## Empieza a escuchar el mando, igual que pulsar «Escuchar».
func listen() -> void:
	if _done:
		return
	_set_listening(true)
	_sync()


## Verdadero mientras el popup espera un evento de joypad.
func is_listening() -> bool:
	return _listening


## Control de la banda de eje, o `null` si el binding actual no es de eje.
func range_control() -> GUIControllerAxisRange:
	return _range


## Botón del popup por su clave de traducción, o `null`. Lo usan los checks.
func button_for(key: StringName) -> Button:
	return _buttons.get(key, null)


## Cierra el popup como si el jugador hubiera pulsado «Cancelar» o «Confirmar».
func close(confirmed: bool) -> void:
	_close(confirmed)


func grab_initial_focus(force: bool = false) -> void:
	if not force and UI.is_using_mouse():
		return
	var listen_button := _buttons.get(&"CTRL_LISTEN", null) as Button
	if listen_button == null:
		return
	UI.mute_for(0.1)
	listen_button.grab_focus()


# --- Entrada ---------------------------------------------------------------------------------

## Los eventos de joypad se capturan acá, antes de que la GUI los reparta: así el
## foco del botón «Escuchar» no se come el botón que se quiere asignar.
func _input(event: InputEvent) -> void:
	if _done:
		return
	if _listening:
		if event is InputEventJoypadButton and event.is_pressed():
			get_viewport().set_input_as_handled()
			_capture_button(event as InputEventJoypadButton)
			return
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if absf(motion.axis_value) > AXIS_THRESHOLD:
				get_viewport().set_input_as_handled()
				_capture_axis(motion)
			return
		# Cualquier otra cosa (teclado, ratón) sigue su curso: el jugador tiene
		# que poder cancelar con Esc aunque el mando no responda.
	if event.is_action_pressed(&"ui_cancel", false, true):
		get_viewport().set_input_as_handled()
		UI.play("back")
		_close(false)


func _capture_button(event: InputEventJoypadButton) -> void:
	action.bind_button(int(event.button_index))
	_captured = true
	cleared = false
	_set_listening(false)
	UI.play("click")
	_sync()


func _capture_axis(motion: InputEventJoypadMotion) -> void:
	var value := motion.axis_value
	if value >= 0.0:
		action.bind_axis(int(motion.axis), CAPTURED_BAND, 1.0)
	else:
		action.bind_axis(int(motion.axis), -1.0, -CAPTURED_BAND)
	_captured = true
	cleared = false
	_set_listening(false)
	UI.play("click")
	_sync()


## Mientras escucha, los sticks no navegan el menú de atrás (`docs/04` §3.3).
func _set_listening(value: bool) -> void:
	if _listening == value:
		return
	if value:
		_suspended_before = StickNavigation.suspended
		StickNavigation.suspended = true
	else:
		StickNavigation.suspended = _suspended_before
	_listening = value


# --- Construcción ----------------------------------------------------------------------------

func _build() -> void:
	var scrim := Panel.new()
	scrim.theme_type_variation = &"OverlayScrim"
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_card = PanelContainer.new()
	_card.theme_type_variation = &"Card"
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	center.add_child(_card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 18)
	_card.add_child(rows)

	var title := Label.new()
	title.text = action.label_key
	title.theme_type_variation = &"HeadingLabel"
	rows.add_child(title)

	_state = Label.new()
	_state.theme_type_variation = &"CaptionLabel"
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.custom_minimum_size = Vector2(CARD_WIDTH - 80.0, 0)
	rows.add_child(_state)

	var value_row := HBoxContainer.new()
	value_row.add_theme_constant_override(&"separation", 14)
	rows.add_child(value_row)
	var value_caption := Label.new()
	value_caption.text = "CTRL_BINDINGS"
	value_caption.theme_type_variation = &"SectionLabel"
	value_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_row.add_child(value_caption)
	_value = Label.new()
	_value.theme_type_variation = &"ValueLabel"
	_value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_row.add_child(_value)

	_range_box = VBoxContainer.new()
	_range_box.add_theme_constant_override(&"separation", 6)
	rows.add_child(_range_box)
	_range = GUIControllerAxisRange.new()
	_range_box.add_child(_range)
	var range_hint := Label.new()
	range_hint.text = "CTRL_RANGE_HINT"
	range_hint.theme_type_variation = &"CaptionLabel"
	range_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	range_hint.custom_minimum_size = Vector2(CARD_WIDTH - 80.0, 0)
	_range_box.add_child(range_hint)
	var _discard := _range.range_updated.connect(_on_range_updated)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	rows.add_child(buttons)
	_add_button(buttons, &"CTRL_LISTEN", &"PrimaryButton", _on_listen_pressed)
	_add_button(buttons, &"CTRL_CLEAR", &"DangerButton", _on_clear_pressed)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(spacer)
	_add_button(buttons, &"UI_CANCEL", &"GhostButton", _on_cancel_pressed)
	_add_button(buttons, &"UI_CONFIRM", &"PrimaryButton", _on_confirm_pressed)
	(_buttons[&"UI_CANCEL"] as Button).set_meta(&"ui_back", true)


func _add_button(parent: HBoxContainer, key: StringName, variation: StringName,
		handler: Callable) -> void:
	var button := Button.new()
	button.text = String(key)
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(150, 0)
	parent.add_child(button)
	_buttons[key] = button
	var _discard := button.pressed.connect(handler)


func _play_open() -> void:
	modulate.a = 0.0
	_card.pivot_offset = Vector2(CARD_WIDTH * 0.5, 80.0)
	_card.scale = Vector2(0.96, 0.96)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)
	var _step1 := tween.tween_property(self, "modulate:a", 1.0, 0.14)
	var _step2 := tween.tween_property(_card, "scale", Vector2.ONE, 0.18)


# --- Sincronización --------------------------------------------------------------------------

## Vuelca el estado de la copia de trabajo sobre las etiquetas y la banda.
func _sync() -> void:
	var is_axis := action.bound and action.type == ControllerAction.Type.AXIS
	if _state != null:
		if _listening:
			_state.text = "CTRL_BINDING_LISTENING"
		elif cleared:
			_state.text = "CTRL_BINDING_CLEARED"
		elif _captured:
			_state.text = "CTRL_BINDING_CAPTURED"
		else:
			_state.text = "CTRL_BINDING_HINT"
	if _value != null:
		_value.text = GUIControllerBinding.describe(action)
	if _range_box != null:
		_range_box.visible = is_axis
	if is_axis and _range != null:
		_range.setup(action.axis_min, action.axis_max)


func _on_range_updated(lo: float, hi: float) -> void:
	if action.type != ControllerAction.Type.AXIS:
		return
	action.bind_axis(action.axis, lo, hi)
	if _value != null:
		_value.text = GUIControllerBinding.describe(action)


func _on_listen_pressed() -> void:
	cleared = false
	listen()


func _on_clear_pressed() -> void:
	_set_listening(false)
	_captured = false
	cleared = true
	action.clear()
	_sync()


func _on_cancel_pressed() -> void:
	_close(false)


func _on_confirm_pressed() -> void:
	_close(true)


func _close(confirmed: bool) -> void:
	if _done:
		return
	_done = true
	_set_listening(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	var _step := tween.tween_property(self, "modulate:a", 0.0, 0.1)
	await tween.finished
	closed.emit(confirmed)
