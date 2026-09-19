## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Pestaña HUD del menú de juego (`docs/04` §4.2, `docs/12` §2.4).
##
## A la izquierda, el preset, el modo de horizonte, la frecuencia de refresco de los
## números y los **once** interruptores de `GameSettings.hud_config` —uno por cada
## entrada del `enum Component` de `docs/12` §2.4 salvo `STATUS`, que siempre se ve—.
## A la derecha, el panel de vista previa.
##
## **Vista previa**: el nodo `%HudPreview` es, desde WP-08, una instancia de
## `hud/hud.tscn` —el `FlightHUD` real— con `preview_mode` encendido: se alimenta sola
## con el generador de `docs/12` §2.5 y refleja los once interruptores en vivo. Esta
## pantalla no sabe nada de eso: llama a `set_preview()` al abrirse y a
## `apply_hud_config()` cada vez que cambia la configuración, y con eso alcanza.
##
## Cada cambio se guarda en el acto y emite `hud_config_updated` a través de
## [method GameSettings.save_hud_config]; la única excepción es el arrastre del
## deslizador, que aplica en vivo y escribe el archivo al soltarlo.
class_name HudConfigPanel
extends HBoxContainer

## Presets en el orden en que los lista el `OptionButton`. `custom` es el último y no
## se puede elegir a mano: es lo que queda cuando la configuración no coincide con
## ningún preset (`docs/04` §3.4).
const PRESETS: Array[String] = ["minimal", "standard", "full", "custom"]

## Clave de traducción de cada preset, en el mismo orden que [constant PRESETS].
const PRESET_KEYS: Array[String] = ["HUD_PRESET_MINIMAL", "HUD_PRESET_STANDARD",
		"HUD_PRESET_FULL", "HUD_PRESET_CUSTOM"]

## Clave de traducción de cada modo de horizonte, en el orden de
## `GameSettings.HUD_HORIZON_MODES`.
const HORIZON_KEYS: Array[String] = ["HUD_HORIZON_CAMERA", "HUD_HORIZON_ATTITUDE"]

## Índice de `custom` dentro de [constant PRESETS].
const CUSTOM_INDEX: int = 3

## Interruptor de cada bool de `hud_config`, indexado por el nombre de la clave.
var _toggles: Dictionary[String, CheckButton] = {}

## Controles expuestos a los checks por [method control_for].
var _controls: Dictionary[StringName, Control] = {}

## Verdadero mientras [method _sync] vuelca los valores sobre los controles, para que
## las señales que eso dispara no se confundan con un cambio del jugador.
var _syncing: bool = false

## Verdadero mientras el jugador arrastra el deslizador de frecuencia.
var _dragging_fps: bool = false


func _ready() -> void:
	_collect_toggles()
	_build_items()
	_connect_controls()
	_sync()
	_setup_preview()
	var _discard := GameSettings.hud_config_updated.connect(_on_hud_config_updated)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build_items()
		_sync()


## Control asociado a una clave de ajuste, o `null` si no existe. Lo usan los checks
## para mover un valor sin depender de la ruta de los nodos.
func control_for(key: StringName) -> Control:
	return _controls.get(key, null)


## Primer control de la pestaña; el menú de juego lo usa como foco inicial.
func first_control() -> Control:
	return %PresetOption


## Nodo de la vista previa.
func preview_node() -> Control:
	return %HudPreview


## La vista previa tipada como lo que es desde WP-08: el `FlightHUD` real en
## `preview_mode`. Lo usa `ui_smoke_test` para comprobar que un interruptor mueve de
## verdad un componente del HUD y no solo un bool de `GameSettings`.
func preview_hud() -> FlightHUD:
	return %HudPreview as FlightHUD


# --- Construcción ----------------------------------------------------------------------------

## Indexa los interruptores por la meta `hud_toggle` de cada uno, así el orden de los
## hijos de la escena no es un contrato.
func _collect_toggles() -> void:
	_toggles.clear()
	var grid := %Toggles as GridContainer
	for child: Node in grid.get_children():
		if not child is CheckButton or not child.has_meta(&"hud_toggle"):
			continue
		var toggle := child as CheckButton
		_toggles[String(toggle.get_meta(&"hud_toggle"))] = toggle
		_controls[StringName(toggle.text)] = toggle
	for expected: String in GameSettings.HUD_TOGGLES:
		if not _toggles.has(expected):
			push_error("Falta el interruptor de HUD '%s' en hud_config.tscn" % expected)


## Rellena los dos `OptionButton` con el texto traducido de cada entrada. Se rehace en
## `NOTIFICATION_TRANSLATION_CHANGED`: el idioma se cambia en la pestaña de al lado.
func _build_items() -> void:
	var preset := %PresetOption as OptionButton
	preset.clear()
	for index: int in PRESET_KEYS.size():
		preset.add_item(tr(PRESET_KEYS[index]), index)
	# `custom` se muestra, pero no se elige a mano (`docs/04` §4.2).
	preset.set_item_disabled(CUSTOM_INDEX, true)

	var horizon := %HorizonOption as OptionButton
	horizon.clear()
	for index: int in HORIZON_KEYS.size():
		horizon.add_item(tr(HORIZON_KEYS[index]), index)


func _connect_controls() -> void:
	_controls[&"HUD_PRESET"] = %PresetOption
	_controls[&"HUD_HORIZON_MODE"] = %HorizonOption
	_controls[&"HUD_NUMBERS_RATE"] = %FpsSlider
	var value_controls: Array[Control] = [%PresetOption, %HorizonOption, %FpsSlider]
	for control: Control in value_controls:
		control.set_meta(&"stick_value_control", true)
	var _discard := (%PresetOption as OptionButton).item_selected.connect(_on_preset_selected)
	_discard = (%HorizonOption as OptionButton).item_selected.connect(_on_horizon_selected)
	var fps := %FpsSlider as HSlider
	fps.min_value = float(GameSettings.HUD_FPS_RANGE.x)
	fps.max_value = float(GameSettings.HUD_FPS_RANGE.y)
	_discard = fps.value_changed.connect(_on_fps_changed)
	_discard = fps.drag_started.connect(_on_fps_drag_started)
	_discard = fps.drag_ended.connect(_on_fps_drag_ended)
	for name_key: String in _toggles:
		var toggle := _toggles[name_key]
		toggle.set_meta(&"stick_value_control", true)
		_discard = toggle.toggled.connect(_on_toggle.bind(name_key))


func _setup_preview() -> void:
	var preview: Control = %HudPreview
	if preview.has_method(&"set_preview"):
		preview.call(&"set_preview", true)
	_refresh_preview()


func _refresh_preview() -> void:
	var preview: Control = %HudPreview
	if preview.has_method(&"apply_hud_config"):
		preview.call(&"apply_hud_config")


# --- Sincronización --------------------------------------------------------------------------

## Vuelca `GameSettings.hud_config` sobre los controles sin volver a guardarlo.
func _sync() -> void:
	if _syncing:
		return
	_syncing = true
	var preset_index := PRESETS.find(GameSettings.get_hud_preset_name())
	(%PresetOption as OptionButton).select(preset_index if preset_index >= 0 else CUSTOM_INDEX)
	var mode := String(GameSettings.hud_config.get("horizon_mode",
			GameSettings.HUD_HORIZON_MODES[0]))
	(%HorizonOption as OptionButton).select(maxi(GameSettings.HUD_HORIZON_MODES.find(mode), 0))
	var fps := int(GameSettings.hud_config.get("fps", 10))
	(%FpsSlider as HSlider).value = float(fps)
	(%FpsValue as Label).text = tr("HUD_HZ") % fps
	for name_key: String in _toggles:
		_toggles[name_key].button_pressed = bool(GameSettings.hud_config.get(name_key, false))
	_syncing = false


func _on_hud_config_updated() -> void:
	if _syncing:
		return
	_sync()
	_refresh_preview()


# --- Manejadores -----------------------------------------------------------------------------

func _on_preset_selected(index: int) -> void:
	if _syncing or index < 0 or index >= PRESETS.size() or index == CUSTOM_INDEX:
		return
	GameSettings.apply_hud_preset(PRESETS[index])


func _on_horizon_selected(index: int) -> void:
	if _syncing:
		return
	var modes: Array[String] = GameSettings.HUD_HORIZON_MODES
	GameSettings.hud_config["horizon_mode"] = modes[clampi(index, 0, modes.size() - 1)]
	GameSettings.save_hud_config()


func _on_fps_changed(value: float) -> void:
	if _syncing:
		return
	var fps := int(roundf(value))
	GameSettings.hud_config["fps"] = fps
	(%FpsValue as Label).text = tr("HUD_HZ") % fps
	if _dragging_fps:
		_refresh_preview()
	else:
		GameSettings.save_hud_config()


func _on_fps_drag_started() -> void:
	_dragging_fps = true


func _on_fps_drag_ended(value_changed: bool) -> void:
	_dragging_fps = false
	if value_changed:
		GameSettings.save_hud_config()


func _on_toggle(pressed: bool, name_key: String) -> void:
	if _syncing:
		return
	GameSettings.hud_config[name_key] = pressed
	GameSettings.save_hud_config()
