## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Menú principal (`docs/04` §4.10, `docs/12` §5).
##
## Es el destino del boot y la raíz de la pila de menús. Las cuatro primeras entradas
## abren su pantalla con `open_submenu()`, que conserva la pila y devuelve el foco al
## volver: rondas (`docs/11` §8), hangar (§4.7), opciones (§4.1) y ayuda (§4.8).
## `MENU_QUIT` pide confirmación y cierra el juego.
##
## Si alguna escena todavía no existe, la entrada avisa con `UI.alert("UI_NOT_YET")` en
## vez de romperse: así el menú no depende del orden en que se cierren los paquetes.
class_name MainMenu
extends MenuScreen

## Clave del título del juego; se muestra con la variación `DisplayLabel`.
const TITLE_KEY: String = "GAME_TITLE"

## Pantalla que abre cada entrada, en el orden de [constant ENTRIES].
const SUBMENU_SCENES: Dictionary[StringName, String] = {
	&"MENU_PLAY": "res://gui/rounds_menu.tscn",
	&"MENU_HANGAR": "res://gui/quad_settings_menu.tscn",
	&"MENU_OPTIONS": "res://gui/options_menu/options_menu.tscn",
	&"MENU_HELP": "res://gui/help_page.tscn",
}

## Entradas del menú, en orden de aparición. El `text` de cada botón **es** la
## clave de traducción (`docs/00` §6), así que el cambio de idioma las rehace solo.
const ENTRIES: Array[StringName] = [&"MENU_PLAY", &"MENU_HANGAR", &"MENU_OPTIONS",
		&"MENU_HELP", &"MENU_QUIT"]

## Nombre de nodo de cada botón, para que los checks los encuentren sin depender
## del texto traducido.
const BUTTON_NAMES: Dictionary[StringName, StringName] = {
	&"MENU_PLAY": &"ButtonPlay",
	&"MENU_HANGAR": &"ButtonHangar",
	&"MENU_OPTIONS": &"ButtonOptions",
	&"MENU_HELP": &"ButtonHelp",
	&"MENU_QUIT": &"ButtonQuit",
}

var _buttons: Dictionary[StringName, Button] = {}
var _busy: bool = false

## Contenido de la pantalla: se oculta mientras hay un submenú encima.
var _margin: MarginContainer = null

## Número de versión de la esquina; es `top_level`, así que se oculta aparte.
var _version: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = Backdrop.OPAQUE
	# La raíz de la pila no tiene a dónde volver: `ui_cancel` no cierra el menú.
	allow_back = false
	# Idempotente: si se llega desde el boot ya está hecho, pero el menú también
	# tiene que funcionar abierto directamente (`docs/04` §4.10).
	Global.load_startup_settings()
	_build()
	super()
	_report_startup_errors.call_deferred()


## Devuelve el botón de una entrada, o `null` si la clave no existe. Lo usan los
## checks para activar entradas sin depender del orden de los hijos.
func button_for(key: StringName) -> Button:
	return _buttons.get(key, null)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", UIPalette.SCREEN_MARGIN_H)
	margin.add_theme_constant_override(&"margin_right", UIPalette.SCREEN_MARGIN_H)
	margin.add_theme_constant_override(&"margin_top", UIPalette.SCREEN_MARGIN_TOP)
	margin.add_theme_constant_override(&"margin_bottom", UIPalette.SCREEN_MARGIN_BOTTOM)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_margin = margin

	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(620, 0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"DisplayLabel"
	title.text = TITLE_KEY
	column.add_child(title)

	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.theme_type_variation = &"SubtitleLabel"
	tagline.text = "MENU_TAGLINE"
	column.add_child(tagline)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size = Vector2(0, 32)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	for key: StringName in ENTRIES:
		var button := Button.new()
		button.name = BUTTON_NAMES[key]
		button.text = String(key)
		button.theme_type_variation = &"MenuItemButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = false
		column.add_child(button)
		_buttons[key] = button
		var _discard := button.pressed.connect(_on_entry_pressed.bind(key))

	initial_focus = _buttons[&"MENU_PLAY"]

	# Arriba a la derecha: abajo está el pie de página de `ControlHints`.
	var version := Label.new()
	version.name = "Version"
	version.theme_type_variation = &"CaptionLabel"
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	version.top_level = true
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
			Control.PRESET_MODE_MINSIZE)
	version.offset_left -= UIPalette.SCREEN_MARGIN_H
	version.offset_right -= UIPalette.SCREEN_MARGIN_H
	version.offset_top += UIPalette.SCREEN_MARGIN_TOP
	version.offset_bottom += UIPalette.SCREEN_MARGIN_TOP
	_version = version


func _on_entry_pressed(key: StringName) -> void:
	if _busy or UI.has_modal() or SceneTransition.is_busy():
		return
	_busy = true
	if key == &"MENU_QUIT":
		if await UI.confirm("MENU_QUIT_CONFIRM"):
			get_tree().quit()
			return
	else:
		await _open_screen(key)
	_busy = false
	_refocus(key)


## Abre la pantalla de una entrada sobre el menú, ocultando mientras tanto el contenido
## y el número de versión (`top_level`, así que no lo tapa el submenú).
func _open_screen(key: StringName) -> void:
	var path: String = SUBMENU_SCENES.get(key, "")
	var packed: PackedScene = null
	if not path.is_empty() and ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed == null:
		await UI.alert("UI_NOT_YET")
		return
	_version.visible = false
	await open_submenu(packed, _margin)
	_version.visible = true


## Muestra y vacía las claves `ERR_*` que dejó el arranque (`docs/04` §2 y §3.1).
func _report_startup_errors() -> void:
	if Global.startup_errors.is_empty():
		return
	var pending := Global.startup_errors.duplicate()
	Global.startup_errors.clear()
	for error_key: String in pending:
		UI.play("error")
		await UI.alert(error_key)
	grab_initial_focus()


func _refocus(key: StringName) -> void:
	var button := _buttons.get(key, null) as Button
	if button == null or UI.is_using_mouse() or not button.is_visible_in_tree():
		return
	UI.mute_for(0.12)
	button.grab_focus()
