## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Juego y HUD (`docs/04` §4.2).
##
## `TabContainer` de dos pestañas: **Gameplay** —idioma, esquema de navegación por
## sticks, asistencia de puntería, intensidad de sacudida y avisos de ataque— y
## **HUD**, que es la escena `hud_config.tscn` ([HudConfigPanel]).
##
## Cada cambio se aplica y se guarda en el acto contra `GameSettings`, que emite
## `game_settings_updated`; la única excepción es el arrastre del deslizador, que
## aplica en vivo y escribe el archivo al soltarlo.
##
## Los nombres de los idiomas son endónimos («Español», «English»): se escriben
## siempre en su propio idioma, así que **no** son claves de traducción.
class_name GameSettingsMenu
extends MenuScreen

## Nombre de cada idioma en su propio idioma, en el orden de `GameSettings.LANGUAGES`.
const LANGUAGE_LABELS: Array[String] = ["Español", "English"]

## Clave de traducción de cada esquema de navegación, en el orden de
## `GameSettings.NavScheme`.
const NAV_KEYS: Array[String] = ["GAME_STICK_NAVIGATION_BETAFLIGHT",
		"GAME_STICK_NAVIGATION_YAW"]

## Clave de traducción de cada nivel de asistencia, en el orden de
## `GameSettings.AimAssist`.
const AIM_KEYS: Array[String] = ["GAME_AIM_OFF", "GAME_AIM_SUBTLE", "GAME_AIM_ASSISTED"]

## Clave de traducción del título de cada pestaña, en orden.
const TAB_KEYS: Array[String] = ["GAME_TAB_GAMEPLAY", "GAME_TAB_HUD"]

## Controles expuestos a los checks por [method control_for].
var _controls: Dictionary[StringName, Control] = {}

var _syncing: bool = false
var _dragging_shake: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_items()
	_connect_controls()
	_sync()
	bind_back_button(%ButtonBack)
	initial_focus = %LanguageOption
	var _discard := GameSettings.game_settings_updated.connect(_on_settings_updated)
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build_items()
		_sync()


## Control asociado a una clave de ajuste, o `null` si no existe. Las claves `HUD_*`
## se delegan en la pestaña de HUD. Lo usan los checks.
func control_for(key: StringName) -> Control:
	if _controls.has(key):
		return _controls[key]
	return (%HudConfig as HudConfigPanel).control_for(key)


## Pestaña de configuración del HUD, para que los checks la recorran.
func hud_panel() -> HudConfigPanel:
	return %HudConfig


## Muestra la pestaña [param index] (0 Gameplay, 1 HUD).
func show_tab(index: int) -> void:
	(%Tabs as TabContainer).current_tab = clampi(index, 0, TAB_KEYS.size() - 1)


## Título ya traducido de la pestaña [param index]. Lo usan los checks.
func tab_title(index: int) -> String:
	return (%Tabs as TabContainer).get_tab_title(clampi(index, 0, TAB_KEYS.size() - 1))


# --- Construcción ----------------------------------------------------------------------------

## Rellena los tres `OptionButton` y los títulos de las pestañas con el texto ya
## traducido. Se rehace en `NOTIFICATION_TRANSLATION_CHANGED`, de modo que cambiar el
## idioma desde acá se ve en el acto sin reabrir la pantalla.
func _build_items() -> void:
	var language := %LanguageOption as OptionButton
	language.clear()
	for index: int in GameSettings.LANGUAGES.size():
		language.add_item(LANGUAGE_LABELS[index], index)

	var nav := %NavOption as OptionButton
	nav.clear()
	for index: int in NAV_KEYS.size():
		nav.add_item(tr(NAV_KEYS[index]), index)

	var aim := %AimOption as OptionButton
	aim.clear()
	for index: int in AIM_KEYS.size():
		aim.add_item(tr(AIM_KEYS[index]), index)

	var tabs := %Tabs as TabContainer
	for index: int in mini(TAB_KEYS.size(), tabs.get_tab_count()):
		tabs.set_tab_title(index, tr(TAB_KEYS[index]))


func _connect_controls() -> void:
	_controls[&"GAME_LANGUAGE"] = %LanguageOption
	_controls[&"GAME_STICK_NAVIGATION"] = %NavOption
	_controls[&"GAME_AIM_ASSIST"] = %AimOption
	_controls[&"GAME_SHAKE"] = %ShakeSlider
	_controls[&"GAME_TELEGRAPH_HINTS"] = %TelegraphCheck
	for key: StringName in _controls:
		_controls[key].set_meta(&"stick_value_control", true)
	(%Tabs as TabContainer).get_tab_bar().set_meta(&"stick_value_control", true)

	var _discard := (%LanguageOption as OptionButton).item_selected.connect(_on_language_selected)
	_discard = (%NavOption as OptionButton).item_selected.connect(_on_nav_selected)
	_discard = (%AimOption as OptionButton).item_selected.connect(_on_aim_selected)
	var shake := %ShakeSlider as HSlider
	_discard = shake.value_changed.connect(_on_shake_changed)
	_discard = shake.drag_started.connect(_on_shake_drag_started)
	_discard = shake.drag_ended.connect(_on_shake_drag_ended)
	_discard = (%TelegraphCheck as CheckButton).toggled.connect(_on_telegraph_toggled)


# --- Sincronización --------------------------------------------------------------------------

## Vuelca los valores de `GameSettings` sobre los controles sin volver a guardarlos.
func _sync() -> void:
	if _syncing:
		return
	_syncing = true
	(%LanguageOption as OptionButton).select(
			maxi(GameSettings.LANGUAGES.find(GameSettings.language), 0))
	(%NavOption as OptionButton).select(clampi(int(GameSettings.nav_scheme), 0,
			NAV_KEYS.size() - 1))
	(%AimOption as OptionButton).select(clampi(int(GameSettings.aim_assist), 0,
			AIM_KEYS.size() - 1))
	var shake := roundf(GameSettings.shake_intensity * 100.0)
	(%ShakeSlider as HSlider).value = shake
	(%ShakeValue as Label).text = tr("UI_PERCENT") % int(shake)
	(%TelegraphCheck as CheckButton).button_pressed = GameSettings.telegraph_hints
	_syncing = false


func _on_settings_updated() -> void:
	_sync()


# --- Manejadores -----------------------------------------------------------------------------

func _on_language_selected(index: int) -> void:
	if _syncing:
		return
	var languages: Array[String] = GameSettings.LANGUAGES
	GameSettings.set_language(languages[clampi(index, 0, languages.size() - 1)])


func _on_nav_selected(index: int) -> void:
	if _syncing:
		return
	GameSettings.set_nav_scheme(index)


func _on_aim_selected(index: int) -> void:
	if _syncing:
		return
	GameSettings.aim_assist = clampi(index, 0, AIM_KEYS.size() - 1)
	GameSettings.save_game_settings()


func _on_shake_changed(value: float) -> void:
	if _syncing:
		return
	GameSettings.shake_intensity = clampf(value / 100.0, 0.0, 1.0)
	(%ShakeValue as Label).text = tr("UI_PERCENT") % int(roundf(value))
	if not _dragging_shake:
		GameSettings.save_game_settings()


func _on_shake_drag_started() -> void:
	_dragging_shake = true


func _on_shake_drag_ended(value_changed: bool) -> void:
	_dragging_shake = false
	if value_changed:
		GameSettings.save_game_settings()


func _on_telegraph_toggled(pressed: bool) -> void:
	if _syncing:
		return
	GameSettings.telegraph_hints = pressed
	GameSettings.save_game_settings()
