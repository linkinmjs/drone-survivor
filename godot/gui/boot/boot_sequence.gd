## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name BootSequence
extends Control
## Studio card shown when the game starts: "OMINOSO" typed on a black terminal with a
## blinking cursor, then a short cut to black and the main menu.
##
## It is the project's main scene. It loads the saved settings first, so the window mode and
## the volumes are already right while the card plays. Any key, gamepad button, click or
## stick gesture skips it. Going back to the menu from a level does not pass through here.


signal finished

const MAIN_MENU_SCENE := "res://gui/main_menu.tscn"

const FONT := preload("res://gui/boot/Withheld Data.otf")
## Same share of the screen height as in the original game (64 px on a 648 px viewport)
const FONT_SIZE := 107
const STUDIO_NAME := "OMINOSO"
const PROMPT := "C:\\>"
const CURSOR := "_"
const CURSOR_BLINK := 0.5
## Wait with the bare prompt before the first letter, time between letters (plus some
## randomness, like someone typing) and hold with the full name before the cut.
const PAUSE := 0.4
const TYPE_SECONDS := 0.075
const TYPE_JITTER := 0.035
const HOLD := 1.1
## Black between the terminal and the menu: the screen turns off before the menu shows up.
const CUT_SECONDS := 0.25

const KEY_SOUND := preload("res://assets/audio/ui/boot_key.ogg")
const KEY_VOLUME_DB := -6.0
const ENTER_SOUND := preload("res://assets/audio/ui/boot_enter.ogg")

## Checks turn it off to drive the card by hand.
@export var autoplay := true

var _terminal: Label = null
var _key_player: AudioStreamPlayer = null
var _enter_player: AudioStreamPlayer = null
var _typed := ""
var _cursor_visible := true
var _tween: Tween = null
var _cursor_tween: Tween = null
var _cutting := false
var _finished := false


func _ready() -> void:
	Global.load_startup_settings()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_build()
	if autoplay:
		play()


## Starts typing from the bare prompt.
func play() -> void:
	_stop()
	_typed = ""
	_cursor_visible = true
	_refresh_terminal()
	_start_cursor_blink()
	_tween = create_tween()
	var _step := _tween.tween_interval(PAUSE)
	for _letter in STUDIO_NAME.length():
		var _type := _tween.tween_callback(_type_next)
		_step = _tween.tween_interval(TYPE_SECONDS + randf_range(-TYPE_JITTER, TYPE_JITTER))
	var _enter := _tween.tween_callback(_enter_player.play)
	_step = _tween.tween_interval(HOLD)
	var _cut := _tween.tween_callback(skip)


## Cuts to black and opens the main menu.
func skip() -> void:
	if _cutting:
		return
	_cutting = true
	_stop()
	_terminal.visible = false
	_tween = create_tween()
	var _step := _tween.tween_interval(CUT_SECONDS)
	var _done := _tween.tween_callback(_finish)


## The full name on the terminal at once, for screenshots.
func type_all() -> void:
	_stop()
	_typed = STUDIO_NAME
	_cursor_visible = true
	_refresh_terminal()


func is_typing_done() -> bool:
	return _typed == STUDIO_NAME


func terminal_text() -> String:
	return _terminal.text


## Any key, gamepad button, click or stick gesture. The event is consumed, so the key that
## skips the card does not also reach the menu.
func _unhandled_input(event: InputEvent) -> void:
	var is_press := event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton or event is InputEventAction
	if not is_press or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	skip()


func _type_next() -> void:
	if _typed.length() >= STUDIO_NAME.length():
		return
	_typed = STUDIO_NAME.substr(0, _typed.length() + 1)
	# Every letter turns the cursor back on, like a real terminal
	_cursor_visible = true
	_start_cursor_blink()
	_refresh_terminal()
	_key_player.pitch_scale = randf_range(0.92, 1.08)
	_key_player.play()


func _start_cursor_blink() -> void:
	if _cursor_tween != null and _cursor_tween.is_valid():
		_cursor_tween.kill()
	_cursor_tween = create_tween().set_loops()
	var _step := _cursor_tween.tween_interval(CURSOR_BLINK)
	var _toggle := _cursor_tween.tween_callback(_toggle_cursor)


func _toggle_cursor() -> void:
	_cursor_visible = not _cursor_visible
	_refresh_terminal()


## A space instead of the hidden cursor keeps the width: the line does not shift while blinking.
func _refresh_terminal() -> void:
	_terminal.text = PROMPT + _typed + (CURSOR if _cursor_visible else " ")


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	SceneTransition.change_scene(MAIN_MENU_SCENE)


func _stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _cursor_tween != null and _cursor_tween.is_valid():
		_cursor_tween.kill()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var black := ColorRect.new()
	black.name = "Black"
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_terminal = Label.new()
	_terminal.name = "Terminal"
	_terminal.add_theme_font_override(&"font", FONT)
	_terminal.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_terminal.add_theme_color_override(&"font_color", Color.WHITE)
	_terminal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_terminal)
	_refresh_terminal()

	var bus := &"UI" if AudioServer.get_bus_index(&"UI") >= 0 else &"Master"
	_key_player = AudioStreamPlayer.new()
	_key_player.stream = KEY_SOUND
	_key_player.volume_db = KEY_VOLUME_DB
	_key_player.max_polyphony = 4
	_key_player.bus = bus
	add_child(_key_player)
	_enter_player = AudioStreamPlayer.new()
	_enter_player.stream = ENTER_SOUND
	_enter_player.bus = bus
	add_child(_enter_player)
