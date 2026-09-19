## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Hub de opciones (`docs/04` §4.1).
##
## Cuatro entradas `MenuItemButton` que abren, con [method MenuScreen.open_submenu],
## las pantallas de juego y HUD, gráficos, audio y controles, más el botón de volver.
##
## La pantalla de controles llega en WP-10: la llamada a `open_submenu()` ya está
## escrita y apunta a su ruta definitiva, pero mientras `ResourceLoader.exists()`
## diga que la escena no está, la entrada avisa con `UI.alert("UI_NOT_YET")`. El día
## que WP-10 agregue el archivo, esta pantalla no se toca.
class_name OptionsMenu
extends MenuScreen

## Escena de cada entrada, en el orden en que se muestran (`docs/04` §4.1).
const ENTRY_SCENES: Dictionary[StringName, String] = {
	&"OPT_GAME": "res://gui/options_menu/game_settings_menu.tscn",
	&"OPT_GRAPHICS": "res://gui/options_menu/graphics_menu.tscn",
	&"OPT_AUDIO": "res://gui/options_menu/audio_menu.tscn",
	&"OPT_CONTROLS": "res://gui/options_menu/controls_menu/controls_menu.tscn",
}

## Nombre de nodo de cada entrada, para que los checks las activen sin depender del
## texto traducido ni del orden de los hijos.
const BUTTON_NAMES: Dictionary[StringName, StringName] = {
	&"OPT_GAME": &"ButtonGame",
	&"OPT_GRAPHICS": &"ButtonGraphics",
	&"OPT_AUDIO": &"ButtonAudio",
	&"OPT_CONTROLS": &"ButtonControls",
}

var _buttons: Dictionary[StringName, Button] = {}
var _busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wire_entries()
	bind_back_button(%ButtonBack)
	initial_focus = _buttons[&"OPT_GAME"]
	super()


## Devuelve el botón de una entrada, o `null` si la clave no existe. Lo usan los
## checks para abrir cada pantalla sin depender del orden de los hijos.
func button_for(key: StringName) -> Button:
	return _buttons.get(key, null)


## Verdadero mientras hay un submenú o un modal abierto desde esta pantalla.
func is_busy() -> bool:
	return _busy


func _wire_entries() -> void:
	var entries: VBoxContainer = %Entries
	for key: StringName in ENTRY_SCENES:
		var button := entries.get_node(NodePath(String(BUTTON_NAMES[key]))) as Button
		_buttons[key] = button
		var _discard := button.pressed.connect(_on_entry_pressed.bind(key))


func _on_entry_pressed(key: StringName) -> void:
	if _busy or UI.has_modal() or SceneTransition.is_busy():
		return
	_busy = true
	var path: String = ENTRY_SCENES[key]
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed == null:
		# WP-10 todavía no entregó la pantalla de controles.
		await UI.alert("UI_NOT_YET")
	else:
		await open_submenu(packed, %Content)
	_busy = false
	_refocus(key)


func _refocus(key: StringName) -> void:
	var button := _buttons.get(key, null) as Button
	if button == null or UI.is_using_mouse() or not button.is_visible_in_tree():
		return
	UI.mute_for(0.12)
	button.grab_focus()
