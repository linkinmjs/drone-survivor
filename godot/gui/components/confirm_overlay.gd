## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name ConfirmOverlay
extends Control
## Modal question drawn inside the interface (no OS window), navigable with
## mouse, keyboard, gamepad and radio sticks. Created through UI.confirm() / UI.alert().


signal closed(confirmed: bool)

var _text := ""
var _ok_text := "UI_OK"
var _cancel_text := ""
var _danger := false
var _done := false
var _card: PanelContainer = null
var _button_ok: Button = null
var _button_cancel: Button = null


func setup(text: String, ok_text: String, cancel_text: String, danger: bool) -> void:
	_text = text
	_ok_text = ok_text
	_cancel_text = cancel_text
	_danger = danger


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := Panel.new()
	scrim.theme_type_variation = &"OverlayScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.theme_type_variation = &"Card"
	_card.custom_minimum_size = Vector2(560, 0)
	center.add_child(_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 28)
	_card.add_child(vbox)

	var label := Label.new()
	label.text = _text
	label.theme_type_variation = &"HeadingLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(480, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override(&"separation", 12)
	vbox.add_child(buttons)

	if not _cancel_text.is_empty():
		_button_cancel = Button.new()
		_button_cancel.text = _cancel_text
		_button_cancel.custom_minimum_size = Vector2(150, 0)
		_button_cancel.set_meta(&"ui_back", true)
		buttons.add_child(_button_cancel)
		var _discard := _button_cancel.pressed.connect(_close.bind(false))

	_button_ok = Button.new()
	_button_ok.text = _ok_text
	_button_ok.custom_minimum_size = Vector2(150, 0)
	_button_ok.theme_type_variation = &"DangerButton" if _danger else &"PrimaryButton"
	buttons.add_child(_button_ok)
	var _discard := _button_ok.pressed.connect(_close.bind(true))

	# Keep keyboard/gamepad focus inside the dialog
	var focusables: Array[Button] = []
	if _button_cancel:
		focusables.append(_button_cancel)
	focusables.append(_button_ok)
	for i in focusables.size():
		var b := focusables[i]
		var prev := focusables[wrapi(i - 1, 0, focusables.size())]
		var next := focusables[wrapi(i + 1, 0, focusables.size())]
		b.focus_neighbor_left = b.get_path_to(prev)
		b.focus_neighbor_right = b.get_path_to(next)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_previous = b.get_path_to(prev)
		b.focus_next = b.get_path_to(next)

	UI.register_context(self)
	modulate.a = 0.0
	_card.pivot_offset = Vector2(280, 80)
	_card.scale = Vector2(0.96, 0.96)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var _step1 := tween.tween_property(self, "modulate:a", 1.0, 0.14)
	var _step2 := tween.tween_property(_card, "scale", Vector2.ONE, 0.18)
	grab_initial_focus.call_deferred(true)


func _exit_tree() -> void:
	UI.unregister_context(self)


## The safe choice gets the focus: Cancel when there is one.
func grab_initial_focus(force := false) -> void:
	if not force and UI.is_using_mouse():
		return
	UI.mute_for(0.1)
	if _button_cancel:
		_button_cancel.grab_focus()
	elif _button_ok:
		_button_ok.grab_focus()


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed(&"ui_cancel", false, true):
		get_viewport().set_input_as_handled()
		UI.play("back")
		_close(false)
	elif event.is_action_pressed(&"pause_menu", false, true):
		# Do not let the pause menu react underneath the dialog
		get_viewport().set_input_as_handled()


func _close(confirmed: bool) -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	var _step3 := tween.tween_property(self, "modulate:a", 0.0, 0.1)
	await tween.finished
	closed.emit(confirmed)
	queue_free()
