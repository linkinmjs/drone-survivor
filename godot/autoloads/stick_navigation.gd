## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
extends Node
## Lets a radio transmitter without buttons (or the sticks of a gamepad) drive the menus,
## like the Betaflight OSD menu. It reads the already calibrated pitch / roll / yaw actions
## and injects the matching ui_* actions. Throttle never navigates, since on a radio it
## rests at the bottom.


enum Scheme {BETAFLIGHT, YAW_SELECT}

const THRESHOLD := 0.6
const RELEASE := 0.4
const INITIAL_DELAY := 0.35
const REPEAT := 0.12

var scheme := Scheme.BETAFLIGHT
## Set while an action binding or the calibration is listening to the sticks.
var suspended := false:
	set(value):
		suspended = value
		_reset_axes()

## Tests only: behave as if a joypad were connected.
var assume_joypad := false

var _dir := {"pitch": 0, "roll": 0, "yaw": 0}
var _timer := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
var _was_active := false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	scheme = GameSettings.get_nav_scheme() as Scheme


func _process(delta: float) -> void:
	var active := not suspended and UI.sticks_allowed() \
			and (assume_joypad or not Input.get_connected_joypads().is_empty())
	if not active:
		_was_active = false
		return
	if not _was_active:
		# A menu just opened: ignore sticks that are already deflected (e.g. the gesture
		# that opened it) until they come back to the center.
		_was_active = true
		_prime_axes()
		return
	# Pushing the stick up is "pitch down" (nose down, fly forward): it moves the focus up
	_update("pitch", Input.get_axis(&"pitch_up", &"pitch_down"), delta)
	_update("roll", Input.get_axis(&"roll_left", &"roll_right"), delta)
	_update("yaw", Input.get_axis(&"yaw_left", &"yaw_right"), delta)


func _update(axis: String, value: float, delta: float) -> void:
	var prev: int = _dir[axis]
	var dir := prev
	if prev == 0 and absf(value) > THRESHOLD:
		dir = signi(value) if value != 0.0 else 0
	elif prev != 0 and (absf(value) < RELEASE or signf(value) != float(prev)):
		dir = 0
	if dir != prev:
		_dir[axis] = dir
		if dir != 0:
			_fire(axis, dir)
			_timer[axis] = INITIAL_DELAY
	elif dir != 0 and _repeats(axis):
		_timer[axis] -= delta
		if _timer[axis] <= 0.0:
			_fire(axis, dir)
			_timer[axis] = REPEAT


## Only movement repeats while the stick is held; accept / back fire once per gesture.
func _repeats(axis: String) -> bool:
	return action_for(axis, 1) in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]


func _fire(axis: String, dir: int) -> void:
	var action := action_for(axis, dir)
	if action == &"":
		return
	UI.set_input_kind(UI.InputKind.STICKS)
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func action_for(axis: String, dir: int) -> StringName:
	match axis:
		"pitch":
			return &"ui_up" if dir > 0 else &"ui_down"
		"roll":
			if scheme == Scheme.YAW_SELECT or _focus_is_value_control():
				return &"ui_right" if dir > 0 else &"ui_left"
			return &"ui_accept" if dir > 0 else &"ui_cancel"
		"yaw":
			if scheme == Scheme.YAW_SELECT:
				return &"ui_accept" if dir > 0 else &"ui_cancel"
	return &""


func _focus_is_value_control() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		return false
	return focus is Range or focus is OptionButton or focus is TabBar \
			or focus is CheckButton or focus is CheckBox or focus.has_meta(&"stick_value_control")


func any_axis_deflected() -> bool:
	return absf(Input.get_axis(&"pitch_up", &"pitch_down")) > RELEASE \
			or absf(Input.get_axis(&"roll_left", &"roll_right")) > RELEASE \
			or absf(Input.get_axis(&"yaw_left", &"yaw_right")) > RELEASE


func _prime_axes() -> void:
	for axis: String in ["pitch", "roll", "yaw"]:
		var value := 0.0
		match axis:
			"pitch":
				value = Input.get_axis(&"pitch_up", &"pitch_down")
			"roll":
				value = Input.get_axis(&"roll_left", &"roll_right")
			"yaw":
				value = Input.get_axis(&"yaw_left", &"yaw_right")
		_dir[axis] = signi(value) if absf(value) > RELEASE else 0
		_timer[axis] = 1000.0


func _reset_axes() -> void:
	_was_active = false
