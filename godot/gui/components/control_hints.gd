## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name ControlHints
extends HBoxContainer
## Footer of every menu screen: shows how to navigate with the device in use and
## which controller is active. Only the footer of the active screen is visible.


var owner_screen: Control = null
var show_back := true

var _chips: HBoxContainer = null
var _controller_label: Label = null
var _controller_dot: ColorRect = null


func _ready() -> void:
	top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = UIPalette.SCREEN_MARGIN_H
	offset_right = -UIPalette.SCREEN_MARGIN_H
	offset_top = -72
	offset_bottom = -28
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 24)

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override(&"separation", 22)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.alignment = BoxContainer.ALIGNMENT_BEGIN
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)

	var status := HBoxContainer.new()
	status.add_theme_constant_override(&"separation", 10)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	_controller_dot = ColorRect.new()
	_controller_dot.custom_minimum_size = Vector2(10, 10)
	_controller_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_child(_controller_dot)
	_controller_label = Label.new()
	_controller_label.theme_type_variation = &"HintLabel"
	status.add_child(_controller_label)

	if owner_screen and "allow_back" in owner_screen:
		show_back = owner_screen.allow_back

	var _discard := UI.input_kind_changed.connect(_on_state_changed.unbind(1))
	_discard = UI.context_changed.connect(_update_visibility)
	_discard = Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_discard = GameSettings.game_settings_updated.connect(_rebuild)
	if owner_screen:
		_discard = owner_screen.visibility_changed.connect(_update_visibility)
	_rebuild()
	_update_controller()
	_update_visibility.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_rebuild()
		_update_controller()


func _process(_delta: float) -> void:
	# Keep the footer faded together with its screen
	if owner_screen:
		modulate.a = owner_screen.modulate.a


func _on_state_changed() -> void:
	_rebuild()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_update_controller()


func _update_visibility() -> void:
	if not is_instance_valid(owner_screen):
		return
	visible = owner_screen.is_visible_in_tree() and UI.get_active_context() == owner_screen


func _rebuild() -> void:
	for child in _chips.get_children():
		child.queue_free()
	var hints: Array = []
	match UI.input_kind:
		UI.InputKind.GAMEPAD:
			hints = [["UI_KEY_DPAD", "UI_HINT_NAVIGATE"], ["A", "UI_HINT_ACCEPT"], ["B", "UI_HINT_BACK"]]
		UI.InputKind.STICKS:
			if StickNavigation.scheme == StickNavigation.Scheme.YAW_SELECT:
				hints = [["Pitch ↕", "UI_HINT_NAVIGATE"], ["Roll ↔", "UI_HINT_ADJUST"],
						["Yaw →", "UI_HINT_ACCEPT"], ["Yaw ←", "UI_HINT_BACK"]]
			else:
				hints = [["Pitch ↕", "UI_HINT_NAVIGATE"], ["Roll →", "UI_HINT_ACCEPT"],
						["Roll ←", "UI_HINT_BACK"]]
		_:
			hints = [["↑ ↓", "UI_HINT_NAVIGATE"], ["Enter", "UI_HINT_ACCEPT"], ["Esc", "UI_HINT_BACK"]]
	for hint: Array in hints:
		if hint[1] == "UI_HINT_BACK" and not show_back:
			continue
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override(&"separation", 8)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := Label.new()
		key.theme_type_variation = &"KeyCap"
		key.text = hint[0]
		chip.add_child(key)
		var label := Label.new()
		label.theme_type_variation = &"HintLabel"
		label.text = hint[1]
		chip.add_child(label)
		_chips.add_child(chip)


func _update_controller() -> void:
	var joypads := Input.get_connected_joypads()
	if joypads.is_empty():
		_controller_dot.color = UIPalette.BORDER_STRONG
		if OS.has_feature("web"):
			_controller_label.text = tr("UI_NO_CONTROLLER_WEB")
		else:
			_controller_label.text = tr("UI_NO_CONTROLLER")
	else:
		_controller_dot.color = UIPalette.SUCCESS
		var device := joypads[0]
		for joypad in joypads:
			if Input.get_joy_guid(joypad) == Controls.active_controller_guid:
				device = joypad
				break
		_controller_label.text = Input.get_joy_name(device)
