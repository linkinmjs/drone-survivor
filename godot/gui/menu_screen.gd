## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name MenuScreen
extends Control
## Base class of every menu screen. It keeps the original flow of the project
## (instantiate → add_child → hide the parent → await back → queue_free) and centralizes:
## the back action, keyboard/gamepad/stick focus, the open/close fade, the background
## and the footer with control hints.


signal back

enum Backdrop {AUTO, OPAQUE, SCRIM, NONE}

## Control that receives the focus when the screen opens with keyboard, gamepad or sticks.
@export var initial_focus: Control = null
@export var backdrop := Backdrop.AUTO
@export var show_hints := true
@export var allow_back := true
@export var apply_screen_margins := true

var _closing := false
var _hints: ControlHints = null
static var _gradient: GradientTexture2D = null


func _ready() -> void:
	# Sub screens added inside another screen's container must still cover the whole
	# screen, not the parent's content area.
	if get_parent() is Container:
		top_level = true
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var node: Node = self
	if apply_screen_margins and node is MarginContainer:
		add_theme_constant_override(&"margin_left", UIPalette.SCREEN_MARGIN_H)
		add_theme_constant_override(&"margin_right", UIPalette.SCREEN_MARGIN_H)
		add_theme_constant_override(&"margin_top", UIPalette.SCREEN_MARGIN_TOP)
		add_theme_constant_override(&"margin_bottom", UIPalette.SCREEN_MARGIN_BOTTOM)
	if show_hints:
		_hints = ControlHints.new()
		_hints.owner_screen = self
		add_child(_hints)
	UI.register_context(self)
	var _discard := visibility_changed.connect(_on_visibility_changed)
	_play_open()
	grab_initial_focus.call_deferred()


func _exit_tree() -> void:
	UI.unregister_context(self)


func _draw() -> void:
	match _resolved_backdrop():
		Backdrop.OPAQUE:
			draw_texture_rect(_get_gradient(), Rect2(Vector2.ZERO, size), false)
		Backdrop.SCRIM:
			draw_rect(Rect2(Vector2.ZERO, size), UIPalette.SCRIM)


func _resolved_backdrop() -> Backdrop:
	if backdrop != Backdrop.AUTO:
		return backdrop
	# Over the flying level the menus let the scene show through
	var scene := get_tree().current_scene
	if scene is Node3D:
		return Backdrop.SCRIM
	return Backdrop.OPAQUE


static func _get_gradient() -> GradientTexture2D:
	if _gradient == null:
		var gradient := Gradient.new()
		gradient.set_color(0, UIPalette.BG_TOP)
		gradient.set_color(1, UIPalette.BG_BOTTOM)
		_gradient = GradientTexture2D.new()
		_gradient.gradient = gradient
		_gradient.fill_from = Vector2(0.2, 0.0)
		_gradient.fill_to = Vector2(0.8, 1.0)
		_gradient.width = 64
		_gradient.height = 64
	return _gradient


func _input(event: InputEvent) -> void:
	if not allow_back or _closing or not is_visible_in_tree() or UI.has_modal():
		return
	if UI.get_active_context() != self:
		return
	if event.is_action_pressed(&"ui_cancel", false, true):
		accept_event()
		request_back()


## Plays the close animation and emits `back`. Screens with extra work to do before
## leaving (saving, restoring shortcuts) override `_before_back()`.
func request_back() -> void:
	if _closing:
		return
	_closing = true
	UI.play("back")
	_before_back()
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var _step1 := tween.tween_property(self, "modulate:a", 0.0, 0.12)
	await tween.finished
	back.emit()


func _before_back() -> void:
	pass


## Marks a button as a "back" button: it plays the back sound and closes the screen.
func bind_back_button(button: BaseButton) -> void:
	button.set_meta(&"ui_silent", true)
	var _discard := button.pressed.connect(request_back)


func _play_open() -> void:
	modulate.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var _step2 := tween.tween_property(self, "modulate:a", 1.0, 0.16)


func grab_initial_focus(force := false) -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	if not force and UI.is_using_mouse():
		return
	if UI.get_active_context() != self:
		return
	var target := initial_focus
	if target == null or not target.is_visible_in_tree():
		target = UI.find_first_focusable(self)
	if target:
		UI.mute_for(0.12)
		target.grab_focus()


## Opens a sub screen, hides `hide_node` meanwhile and restores the focus afterwards.
func open_submenu(packed: PackedScene, hide_node: CanvasItem, parent: Node = self) -> void:
	if not packed.can_instantiate():
		return
	var opener := get_viewport().gui_get_focus_owner()
	var sub := packed.instantiate()
	parent.add_child(sub)
	hide_node.visible = false
	await sub.back
	sub.queue_free()
	hide_node.visible = true
	await get_tree().process_frame
	if is_instance_valid(opener) and opener.is_visible_in_tree() and not UI.is_using_mouse():
		UI.mute_for(0.12)
		opener.grab_focus()


func _on_visibility_changed() -> void:
	queue_redraw()
	if is_visible_in_tree():
		grab_initial_focus.call_deferred()
