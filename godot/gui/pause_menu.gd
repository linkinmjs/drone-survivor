## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Menú de pausa (`docs/04` §4.9, `docs/12` §5.1).
##
## Es un [CanvasLayer] en la capa 40 con `process_mode = PROCESS_MODE_WHEN_PAUSED`, de
## modo que sigue vivo mientras el árbol está en pausa y todo lo que hay debajo —el
## dron, la física y el HUD— está detenido. El contenido es un [MenuScreen] normal, así
## que hereda el fundido de apertura, el foco automático, el sonido de `UI` y la
## navegación por sticks.
##
## **No es dueño de la pausa**: no llama a `get_tree().paused` ni cambia de escena. Solo
## publica dos hechos, [signal resumed] y [signal menu], y el nivel que lo instanció
## (ver [LevelBase]) decide qué hacer con ellos. Esa es la razón de que el respaldo
## contra «mantener apretado el botón de pausa» viva en `LevelBase._resume_input_held()`
## y no acá: el menú no sabe cuándo es seguro despausar.
##
## Hangar, opciones y ayuda se abren como submenús **encima** de la pausa, con la pila
## de `MenuScreen`, sin salir del nivel.
class_name PauseMenu
extends CanvasLayer

## El jugador pidió seguir jugando. El nivel espera a que se suelte la entrada y
## despausa.
signal resumed

## El jugador confirmó que abandona la ronda. El nivel vuelve al menú principal.
signal menu

## Capa de canvas de la pausa (`docs/12` §1.1): por encima del HUD (20) y por debajo
## de la tarjeta de resultado (45).
const CANVAS_LAYER: int = 40

## Confirmación que pide `MENU_MAIN` antes de abandonar la ronda.
const QUIT_CONFIRM_KEY: String = "MENU_QUIT_ROUND_CONFIRM"

## Entradas del menú, en orden de aparición (`docs/04` §4.9).
const ENTRIES: Array[StringName] = [&"MENU_RESUME", &"MENU_HANGAR", &"MENU_OPTIONS",
		&"MENU_HELP", &"MENU_MAIN"]

## Nombre de nodo de cada entrada, para que los checks las activen sin depender del
## texto traducido ni del orden de los hijos.
const BUTTON_NAMES: Dictionary[StringName, StringName] = {
	&"MENU_RESUME": &"ButtonResume",
	&"MENU_HANGAR": &"ButtonHangar",
	&"MENU_OPTIONS": &"ButtonOptions",
	&"MENU_HELP": &"ButtonHelp",
	&"MENU_MAIN": &"ButtonMain",
}

## Escena que abre cada entrada como submenú sobre la pausa.
const SUBMENU_SCENES: Dictionary[StringName, String] = {
	&"MENU_HANGAR": "res://gui/quad_settings_menu.tscn",
	&"MENU_OPTIONS": "res://gui/options_menu/options_menu.tscn",
	&"MENU_HELP": "res://gui/help_page.tscn",
}

var _buttons: Dictionary[StringName, Button] = {}
var _busy: bool = false
var _closed: bool = false

@onready var _screen: MenuScreen = %Screen
@onready var _content: MarginContainer = %Content


func _ready() -> void:
	layer = CANVAS_LAYER
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_wire_entries()
	_screen.initial_focus = _buttons[&"MENU_RESUME"]
	# `ui_cancel` sobre la pausa es «seguir jugando», no «cerrar la pantalla».
	var _discard := _screen.back.connect(_on_screen_back)
	# La música se va «a la otra habitación» mientras dura la pausa (`docs/13`
	# §5.1): el pasa-bajos de `Music` es lo único que este menú toca del audio.
	var _filtered := Audio.set_music_lowpass(true)


## Devuelve la música a su sitio. Va en `_exit_tree()` y no en [method request_resume]
## porque de la pausa se sale por tres caminos —reanudar, volver al menú y que el
## nivel entero se descargue— y los tres pasan por acá.
func _exit_tree() -> void:
	var _clear := Audio.set_music_lowpass(false)


## El botón que abre la pausa es el mismo que la cierra (`docs/12` §5.1, bloqueo de
## reanudación), y esa segunda pulsación la tiene que escuchar **este** nodo: el nivel
## es `PROCESS_MODE_PAUSABLE`, así que con el árbol detenido no recibe `_unhandled_input`
## y la acción `pause_menu` no llegaría a ningún lado.
##
## Sale por el mismo camino que `MENU_RESUME` —[method request_resume]—, o sea que
## [LevelBase] sigue decidiendo cuándo es seguro despausar con `_resume_input_held()`.
func _input(event: InputEvent) -> void:
	if _closed or _busy or UI.has_modal() or SceneTransition.is_busy():
		return
	if not event.is_action_pressed(&"pause_menu", false, true):
		return
	get_viewport().set_input_as_handled()
	request_resume()


## Devuelve el botón de una entrada, o `null` si la clave no existe.
func button_for(key: StringName) -> Button:
	return _buttons.get(key, null)


## La pantalla que dibuja el menú. La usan los checks y el nivel para mirar el foco.
func screen() -> MenuScreen:
	return _screen


## Pide seguir jugando: emite [signal resumed] una sola vez. Es lo que hacen el botón
## `MENU_RESUME`, la acción `ui_cancel` y la acción de pausa cuando el nivel la repite.
func request_resume() -> void:
	if _closed:
		return
	_closed = true
	resumed.emit()


# --- Construcción ----------------------------------------------------------------------------

func _wire_entries() -> void:
	var entries: VBoxContainer = %Entries
	for key: StringName in ENTRIES:
		var button := entries.get_node(NodePath(String(BUTTON_NAMES[key]))) as Button
		if button == null:
			push_error("PauseMenu: falta el botón %s en pause_menu.tscn" % BUTTON_NAMES[key])
			continue
		_buttons[key] = button
		var _discard := button.pressed.connect(_on_entry_pressed.bind(key))


# --- Manejadores -----------------------------------------------------------------------------

func _on_entry_pressed(key: StringName) -> void:
	if _busy or _closed or UI.has_modal() or SceneTransition.is_busy():
		return
	_busy = true
	if key == &"MENU_RESUME":
		request_resume()
		return
	if key == &"MENU_MAIN":
		if await UI.confirm(QUIT_CONFIRM_KEY):
			_closed = true
			menu.emit()
			return
	else:
		await _open_submenu(key)
	_busy = false
	_refocus(key)


## Abre hangar, opciones o ayuda sobre la pausa, sin salir del nivel.
func _open_submenu(key: StringName) -> void:
	var path: String = SUBMENU_SCENES.get(key, "")
	var packed: PackedScene = null
	if not path.is_empty() and ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed == null:
		await UI.alert("UI_NOT_YET")
		return
	await _screen.open_submenu(packed, _content, _screen)


## `ui_cancel` sobre la pausa equivale a `MENU_RESUME`.
func _on_screen_back() -> void:
	request_resume()


func _refocus(key: StringName) -> void:
	var button := _buttons.get(key, null) as Button
	if button == null or UI.is_using_mouse() or not button.is_visible_in_tree():
		return
	UI.mute_for(0.12)
	button.grab_focus()
