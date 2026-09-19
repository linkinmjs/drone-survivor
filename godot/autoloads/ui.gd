## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
extends Node
## Global interface services: input device tracking, focus handling shared by every menu,
## interface sounds and micro animations, and modal overlays (confirm / alert).


signal input_kind_changed(kind: InputKind)
signal context_changed

enum InputKind {MOUSE, KEYBOARD, GAMEPAD, STICKS}

const SOUNDS := {
	"hover": "res://assets/audio/ui/hover.wav",
	"click": "res://assets/audio/ui/click.wav",
	"back": "res://assets/audio/ui/back.wav",
	"tick": "res://assets/audio/ui/tick.wav",
	"error": "res://assets/audio/ui/error.wav",
}
const NAV_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right",
		&"ui_accept", &"ui_focus_next", &"ui_focus_prev"]

var input_kind := InputKind.MOUSE
var _players := {}
var _mute_until_msec := 0
var _last_sound_msec := {}
var _overlay_layer: CanvasLayer = null
## Focus contexts: menus and overlays that can receive keyboard/gamepad focus.
## The last visible one is the active context.
var _contexts: Array[Control] = []


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 90
	add_child(_overlay_layer)

	var bus := &"UI" if AudioServer.get_bus_index(&"UI") >= 0 else &"Master"
	for key: String in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.bus = bus
		if ResourceLoader.exists(SOUNDS[key]):
			player.stream = load(SOUNDS[key])
		add_child(player)
		_players[key] = player

	var _discard := get_tree().node_added.connect(_on_node_added)


# --- Sounds --------------------------------------------------------------------------------

func play(sound: String) -> void:
	if Time.get_ticks_msec() < _mute_until_msec:
		return
	var player := _players.get(sound) as AudioStreamPlayer
	if player == null or player.stream == null:
		return
	# Avoid machine-gun repeats (slider + shared spin box emit twice, fast navigation)
	var now := Time.get_ticks_msec()
	var min_gap := 40 if sound == "tick" else 25
	if now - int(_last_sound_msec.get(sound, -1000)) < min_gap:
		return
	_last_sound_msec[sound] = now
	player.play()


## Silences interface sounds for a short time, e.g. while a screen grabs its initial focus.
func mute_for(seconds: float) -> void:
	_mute_until_msec = maxi(_mute_until_msec, Time.get_ticks_msec() + int(seconds * 1000.0))


func _on_node_added(node: Node) -> void:
	if not node is Control:
		return
	if node is BaseButton:
		var button := node as BaseButton
		_connect_once(button.mouse_entered, _on_button_hovered.bind(button))
		_connect_once(button.focus_entered, _on_button_focused.bind(button))
		_connect_once(button.pressed, _on_button_pressed.bind(button))
		if node is OptionButton:
			_connect_once((node as OptionButton).item_selected, _on_option_selected)
	elif node is Range and not node is ScrollBar:
		_connect_once((node as Range).value_changed, _on_range_changed.bind(node))
	elif node is TabBar:
		_connect_once((node as TabBar).tab_changed, _on_tab_changed)


func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		var _discard := sig.connect(callable)


func _on_button_hovered(button: BaseButton) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return
	play("hover")
	_pulse(button)


func _on_button_focused(button: BaseButton) -> void:
	if input_kind == InputKind.MOUSE:
		return
	play("hover")
	_pulse(button)


func _on_button_pressed(button: BaseButton) -> void:
	if button.has_meta(&"ui_silent"):
		return
	play("back" if button.has_meta(&"ui_back") else "click")


func _on_option_selected(_idx: int) -> void:
	play("click")


func _on_range_changed(_value: float, range_control: Range) -> void:
	if not range_control.is_visible_in_tree():
		return
	var hovered := range_control.get_global_rect().has_point(range_control.get_global_mouse_position())
	if range_control.has_focus() or hovered or _focus_inside(range_control):
		play("tick")


func _on_tab_changed(_tab: int) -> void:
	play("click")


func _focus_inside(control: Control) -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and control.is_ancestor_of(focus)


## Small scale pulse on the big menu entries.
func _pulse(button: BaseButton) -> void:
	if button.theme_type_variation != &"MenuItemButton":
		return
	button.pivot_offset = button.size / 2.0
	var tween := button.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var _step1 := tween.tween_property(button, "scale", Vector2(1.025, 1.025), 0.08)
	var _step2 := tween.tween_property(button, "scale", Vector2.ONE, 0.14)


# --- Input device and focus ----------------------------------------------------------------

func set_input_kind(kind: InputKind) -> void:
	if kind == input_kind:
		return
	input_kind = kind
	if kind == InputKind.MOUSE:
		var focus := get_viewport().gui_get_focus_owner()
		if focus and not (focus is LineEdit or focus is TextEdit):
			focus.release_focus()
	input_kind_changed.emit(kind)


func is_using_mouse() -> bool:
	return input_kind == InputKind.MOUSE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 9.0 \
				and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			set_input_kind(InputKind.MOUSE)
		return
	elif event is InputEventMouseButton:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			set_input_kind(InputKind.MOUSE)
		return
	elif event is InputEventKey and event.is_pressed():
		set_input_kind(InputKind.KEYBOARD)
	elif event is InputEventJoypadButton and event.is_pressed():
		set_input_kind(InputKind.GAMEPAD)

	if not event.is_pressed() or _contexts.is_empty():
		return
	var is_nav := false
	for action in NAV_ACTIONS:
		if event.is_action(action, true):
			is_nav = true
			break
	if not is_nav:
		return

	var context := get_active_context()
	if context == null:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not context.is_ancestor_of(focus) and focus != context:
		# First key/button press after using the mouse: show where the focus is
		# instead of acting on an invisible target.
		if context.has_method(&"grab_initial_focus"):
			context.call(&"grab_initial_focus", true)
		get_viewport().set_input_as_handled()
		return

	var left := event.is_action(&"ui_left", true)
	var right := event.is_action(&"ui_right", true)
	if not (left or right):
		return
	if focus is OptionButton:
		var option := focus as OptionButton
		if option.get_popup().visible or option.item_count == 0:
			return
		var idx := option.selected
		var step := -1 if left else 1
		for _i in option.item_count:
			idx = wrapi(idx + step, 0, option.item_count)
			if not option.is_item_disabled(idx) and not option.is_item_separator(idx):
				break
		if idx != option.selected:
			option.select(idx)
			option.item_selected.emit(idx)
		get_viewport().set_input_as_handled()
	elif focus is CheckButton or focus is CheckBox:
		var toggle := focus as BaseButton
		if not toggle.disabled and toggle.button_pressed != right:
			toggle.button_pressed = right
			play("click")
		get_viewport().set_input_as_handled()


func register_context(control: Control) -> void:
	if not _contexts.has(control):
		_contexts.append(control)
	context_changed.emit()


func unregister_context(control: Control) -> void:
	_contexts.erase(control)
	context_changed.emit()


func get_active_context() -> Control:
	for i in range(_contexts.size() - 1, -1, -1):
		var context := _contexts[i]
		if not is_instance_valid(context):
			continue
		if context.is_visible_in_tree():
			return context
	return null


## True when the active context wants the radio sticks to drive the interface.
func sticks_allowed() -> bool:
	var context := get_active_context()
	if context == null:
		return false
	return not context.has_meta(&"no_sticks")


func find_first_focusable(root: Node) -> Control:
	for child in root.get_children():
		if child is Control:
			var control := child as Control
			if not control.is_visible_in_tree():
				continue
			if control.focus_mode == Control.FOCUS_ALL and not (control is BaseButton and control.disabled):
				return control
			var found := find_first_focusable(control)
			if found:
				return found
	return null


# --- Modal overlays ------------------------------------------------------------------------

func has_modal() -> bool:
	for child in _overlay_layer.get_children():
		if child is ConfirmOverlay and not child.is_queued_for_deletion():
			return true
	return false


## Shows a modal question. Returns true when the user confirms.
func confirm(text: String, ok_text := "UI_CONFIRM", cancel_text := "UI_CANCEL",
		danger := false) -> bool:
	var overlay := ConfirmOverlay.new()
	overlay.setup(text, ok_text, cancel_text, danger)
	_overlay_layer.add_child(overlay)
	var result: bool = await overlay.closed
	return result


func alert(text: String, ok_text := "UI_OK") -> void:
	var overlay := ConfirmOverlay.new()
	overlay.setup(text, ok_text, "", false)
	_overlay_layer.add_child(overlay)
	var _result: bool = await overlay.closed
