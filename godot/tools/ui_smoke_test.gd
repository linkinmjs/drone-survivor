## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Smoke test de la interfaz (`docs/15` §3, `docs/04` §9).
##
## Alcance de WP-09: el menú principal y todo el árbol de opciones. Abre
## `gui/main_menu.tscn`, comprueba el foco inicial, activa las entradas todavía sin
## destino y verifica que su aviso se abre y se cierra, que la confirmación de salir
## se cancela con `ui_cancel` sin cerrar el juego, y después recorre el hub de opciones
## y sus cuatro pantallas: en cada una comprueba el foco inicial, mueve un valor con
## la misma entrada que usaría el jugador (`ui_right` sobre el control enfocado),
## comprueba que el autoload lo refleja, que sobrevive a `save_*` + recarga y que la
## pantalla vuelve tanto con `ui_cancel` como con el botón de atrás dejando el foco
## donde estaba. Cierra comprobando que ninguna clave de traducción usada falta en
## español o en inglés y que ninguna etiqueta muestra su clave cruda.
##
## **No toca la configuración del jugador**: antes de instanciar nada apunta
## `Global.config_dir` a [member _temp_dir] y `Global.log_path` a un log dentro de ese
## mismo directorio, como hace `tools/settings_check.gd`, y al terminar devuelve ambos
## a su valor original y borra el directorio. El snapshot de `CheckRunner` sobre
## `user://config` queda como segunda red de seguridad.
##
## WP-10 agrega la pantalla de controles y su asistente de calibración: acá se
## comprueba que las dos abren desde el hub, enfocan, no muestran claves crudas y
## vuelven —y que cancelar la calibración no guarda nada—. Las asignaciones, la
## captura de bindings y los catorce pasos del asistente los prueba
## `tools/controls_check.gd`, que es el dueño de esa parte (`docs/15` §3).
##
## WP-11 cierra el recorrido: rondas, hangar —con el gráfico de rates—, ayuda y pausa.
## De cada una se comprueba lo mismo que de las de opciones (foco, textos, vuelta) más lo
## propio: que la ronda del MVP aparece desbloqueada, que mover un rate llega al autoload,
## sobrevive a guardar y recargar y rehace el gráfico, que la ayuda muestra el texto de
## licencias del motor, y que la pausa se declara en la capa y el `process_mode` que le
## tocan. La pausa **sobre un nivel** la prueba `tools/pause_check.gd`, que es su dueño.
##
## WP-08 agrega dos cosas. La primera, en la pestaña de HUD: la vista previa ya no es un
## marcador de posición sino el `FlightHUD` real en `preview_mode`, así que acá se
## comprueba que un interruptor mueve **el componente** y no solo un bool de
## `GameSettings`, que los tres presets se reflejan enteros y que `STATUS` sigue visible
## en todos ellos porque no tiene interruptor (`docs/12` §2.4).
##
## La segunda es el **tipo de entrada**. Esta prueba navega con acciones `ui_*`
## sintéticas y depende del foco, pero `UI` suelta el foco en cuanto cree que el jugador
## está usando el ratón (`autoloads/ui.gd`), y eso pasaba con solo dejar el puntero
## encima de la ventana: la prueba salía verde o roja según dónde estuviera el mouse
## (pendiente registrado en `docs/00` §7). Desde WP-08 el check fija
## `UI.InputKind.KEYBOARD` **antes de instanciar nada** y lo vuelve a fijar si algo lo
## cambia, con [method _on_input_kind_changed]; [method _restore_environment] devuelve
## el valor original.
extends CheckRunner

const MAIN_MENU_SCENE := "res://gui/main_menu.tscn"

## Pantallas de WP-11 que cuelgan del menú principal.
const ROUNDS_SCENE := "res://gui/rounds_menu.tscn"
const HANGAR_SCENE := "res://gui/quad_settings_menu.tscn"
const HELP_SCENE := "res://gui/help_page.tscn"
const PAUSE_SCENE := "res://gui/pause_menu.tscn"

## Pantalla de controles y asistente de calibración de WP-10.
const CONTROLS_SCENE := "res://gui/options_menu/controls_menu/controls_menu.tscn"
const CALIBRATION_SCENE := "res://gui/options_menu/controls_menu/calibration_menu.tscn"

## Prefijo del directorio de trabajo de la prueba. El nombre real lleva además el id
## del proceso ([member _temp_dir]): `run_checks.ps1` y una corrida a mano pueden
## solaparse, y dos procesos que compartieran el mismo directorio se borrarían la
## configuración temporal el uno al otro a mitad de la prueba.
const TEMP_DIR_PREFIX: String = "user://config_ui_smoke_tmp"

## Directorio real del jugador, que esta prueba no puede tocar.
const PLAYER_DIR: String = "user://config"

## Locales que el juego declara en `project.godot`; toda clave visible existe en ambos.
const LOCALES: Array[String] = ["es", "en"]

## Claves de traducción fijas que estas pantallas y sus modales ponen en pantalla. Las
## listas de opciones no se repiten acá: [method _collect_used_keys] las lee de las
## constantes de cada menú, así el check no se desfasa si cambia una lista.
const USED_KEYS: Array[String] = [
	"GAME_TITLE", "MENU_TAGLINE",
	"MENU_PLAY", "MENU_HANGAR", "MENU_OPTIONS", "MENU_HELP", "MENU_QUIT",
	"MENU_QUIT_CONFIRM", "UI_NOT_YET",
	"UI_OK", "UI_CONFIRM", "UI_CANCEL", "UI_LOADING", "UI_BACK",
	"UI_HINT_NAVIGATE", "UI_HINT_ACCEPT", "UI_HINT_BACK", "UI_HINT_ADJUST",
	"UI_KEY_DPAD", "UI_NO_CONTROLLER",
	"UI_OFF", "UI_ON", "UI_PERCENT",
	"OPT_TITLE", "OPT_SUBTITLE", "OPT_GAME", "OPT_GRAPHICS", "OPT_AUDIO", "OPT_CONTROLS",
	"GAME_SUBTITLE", "GAME_LANGUAGE", "GAME_STICK_NAVIGATION", "GAME_AIM_ASSIST",
	"GAME_SHAKE", "GAME_TELEGRAPH_HINTS",
	"HUD_PRESET", "HUD_HORIZON_MODE", "HUD_NUMBERS_RATE", "HUD_HZ", "HUD_COMPONENTS",
	"HUD_PREVIEW",
	"GFX_TITLE", "GFX_SUBTITLE", "GFX_SECTION_DISPLAY", "GFX_SECTION_QUALITY",
	"GFX_SECTION_FPV", "GFX_WINDOW_MODE", "GFX_RESOLUTION_SCALE", "GFX_VSYNC",
	"GFX_MAX_FPS", "GFX_UNLIMITED", "GFX_PRESET", "GFX_MSAA", "GFX_SHADOWS", "GFX_GI",
	"GFX_FOG", "GFX_SSAO", "GFX_FISHEYE", "GFX_FISHEYE_RESOLUTION", "GFX_FISHEYE_MSAA",
	"GFX_RESTART_NOTE",
	"AUD_TITLE", "AUD_SUBTITLE", "AUD_MUTE",
	"CTRL_TITLE", "CTRL_SUBTITLE", "CTRL_SECTION_DEVICE", "CTRL_SECTION_LIVE",
	"CTRL_SECTION_FLIGHT", "CTRL_SECTION_ACTIONS", "CTRL_ACTIVE_CONTROLLER",
	"CTRL_DEFAULT_CONTROLLER", "CTRL_NO_CONTROLLER", "CTRL_AXES", "CTRL_BUTTONS",
	"CTRL_AXIS_N", "CTRL_CALIBRATED", "CTRL_UNCALIBRATED", "CTRL_INVERT",
	"CTRL_CALIBRATE", "CTRL_CALIBRATE_HINT", "CTRL_RESET", "CTRL_RESET_CONFIRM",
	"CTRL_DEVICE_SWITCH", "CTRL_BINDINGS", "CTRL_BOUND_BUTTON", "CTRL_BOUND_AXIS",
	"CTRL_UNBOUND", "CTRL_LISTEN", "CTRL_CLEAR", "CTRL_RANGE_HINT",
	"CTRL_BINDING_HINT", "CTRL_BINDING_LISTENING", "CTRL_BINDING_CAPTURED",
	"CTRL_BINDING_CLEARED",
	"CAL_TITLE", "CAL_SUBTITLE", "CAL_HINT", "CAL_NEXT", "CAL_SKIP", "CAL_DONE",
	"CAL_SUCCESS", "CAL_SKIPPED",
	"ROUND_MENU_TITLE", "ROUND_MENU_SUBTITLE", "ROUND_LOCKED_HINT", "ROUND_BEST_SCORE",
	"ROUND_BEST_TIME", "ROUND_NOT_PLAYED", "ROUND_COMING_SOON",
	"QUAD_TITLE", "QUAD_SUBTITLE", "QUAD_SECTION_FRAME", "QUAD_SECTION_RATES",
	"QUAD_GRAPH", "QUAD_HELP_GRAPH", "QUAD_RATES_CURVE", "QUAD_HELP_RATES_CURVE",
	"QUAD_RESET_QUAD", "QUAD_RESET_RATES", "QUAD_RESET_QUAD_CONFIRM",
	"QUAD_RESET_RATES_CONFIRM", "QUAD_HELP_RESET_QUAD", "QUAD_HELP_RESET_RATES",
	"HELP_TITLE", "HELP_SUBTITLE",
	"MENU_MAIN", "MENU_RESUME", "MENU_PAUSED", "MENU_PAUSED_HINT",
	"MENU_QUIT_ROUND_CONFIRM",
]

## Plazo de cada espera intermedia. Se espera por condición y no por frames: en
## `--headless` un frame dura una fracción de milisegundo y los fundidos de los
## modales duran décimas de segundo reales.
const STEP_TIMEOUT_SECONDS := 10.0

## Margen real para que terminen los fundidos de apertura antes de capturar.
const SETTLE_SECONDS := 0.4

## Directorio de trabajo propio de este proceso; lo borra [method finish].
var _temp_dir: String = ""

var _menu: MainMenu = null
var _saved_locale: String = ""
var _smoke_saved_config_dir: String = ""
var _smoke_saved_log_path: String = ""
var _original_suspended: bool = false
var _original_window_mode: int = 0
var _original_vsync: int = 0
var _original_input_kind: int = 0

## Tipo de entrada que el check impone mientras dura. Ver la cabecera.
var _forced_input_kind: int = UI.InputKind.KEYBOARD
var _player_files_before: PackedStringArray = PackedStringArray()
var _restored: bool = false

## Pantalla cuya desaparición espera [method _expect_closed].
var _watched_screen: MenuScreen = null

## Control cuyo foco espera [method _watched_control_has_focus].
var _watched_control: Control = null

## Verdadero en cuanto el menú de pausa emite `resumed`.
var _pause_resumed: bool = false


func _run() -> void:
	_pin_input_kind()
	_temp_dir = "%s_%d" % [TEMP_DIR_PREFIX, OS.get_process_id()]
	_saved_locale = TranslationServer.get_locale()
	_smoke_saved_config_dir = Global.config_dir
	_smoke_saved_log_path = Global.log_path
	_original_suspended = StickNavigation.suspended
	_original_window_mode = int(Graphics.window_mode)
	_original_vsync = int(Graphics.vsync)
	_player_files_before = _player_files()
	_purge_temp()
	Global.config_dir = _temp_dir
	Global.log_path = _temp_dir.path_join("output.log")
	# El menú principal también la llama, pero conviene adelantarla para que lea el
	# directorio temporal y no el del jugador, y para dejar la ventana en un estado
	# previsible antes de la primera captura.
	Global.startup_errors.clear()
	Global.load_startup_settings()
	Global.startup_errors.clear()
	_prepare_window()

	_check_translations()
	await _open_menu()
	if _menu == null:
		return
	_check_menu_targets()
	await _check_rounds()
	await _check_hangar()
	await _check_help()
	await _check_options()
	await _check_quit_is_cancellable()
	await _check_pause()
	_check_no_raw_keys(_menu, "el menú principal")
	await _close()
	_check_player_dir_untouched()


## Devuelve el entorno a su estado original antes de que `CheckRunner` cierre el
## proceso. Se ejecuta también si el check falló o si expiró el timeout.
func finish() -> void:
	_restore_environment()
	super()


# --- Entorno ---------------------------------------------------------------------------------

## Fija `UI.InputKind.KEYBOARD` y lo mantiene fijo mientras dure el check.
##
## Se llama **antes** de instanciar el menú principal: `MenuScreen.grab_initial_focus()`
## no toma el foco si `UI` cree que el jugador está con el ratón, y `UI` arranca
## justamente en `MOUSE`. Quedarse con el primer `set_input_kind` no alcanzaba: cualquier
## movimiento real del puntero sobre la ventana lo devuelve a `MOUSE` y suelta el foco,
## que es la flojera registrada en `docs/00` §7.
func _pin_input_kind() -> void:
	_original_input_kind = int(UI.input_kind)
	if not UI.input_kind_changed.is_connected(_on_input_kind_changed):
		var _discard := UI.input_kind_changed.connect(_on_input_kind_changed)
	UI.set_input_kind(_forced_input_kind as UI.InputKind)


func _on_input_kind_changed(kind: UI.InputKind) -> void:
	if int(kind) != _forced_input_kind:
		UI.set_input_kind(_forced_input_kind as UI.InputKind)

## Deja la ventana como la pide el comando del check: en modo ventana, sin vsync y sin
## tope de fps. El valor por defecto de `Graphics` es pantalla completa, y aplicarlo
## rompería la resolución de las capturas.
func _prepare_window() -> void:
	Graphics.window_mode = Graphics.WindowMode.WINDOW
	Graphics.vsync = Graphics.VSync.OFF
	Graphics.max_fps = 0
	Graphics.save_graphics_settings()
	Engine.max_fps = 0


## Idempotente: la llama [method finish], que a su vez puede llegar por el timeout.
func _restore_environment() -> void:
	if _restored:
		return
	_restored = true
	if get_tree() != null:
		get_tree().paused = false
	if UI.input_kind_changed.is_connected(_on_input_kind_changed):
		UI.input_kind_changed.disconnect(_on_input_kind_changed)
	UI.set_input_kind(_original_input_kind as UI.InputKind)
	StickNavigation.suspended = _original_suspended
	Engine.max_fps = 0
	Graphics.window_mode = _original_window_mode
	Graphics.vsync = _original_vsync
	_purge_temp()
	if not _smoke_saved_log_path.is_empty():
		Global.log_path = _smoke_saved_log_path
	if not _smoke_saved_config_dir.is_empty():
		Global.config_dir = _smoke_saved_config_dir
	if not _saved_locale.is_empty():
		TranslationServer.set_locale(_saved_locale)
	Global.startup_errors.clear()


## Borra solo el directorio de este proceso: otro `ui_smoke_test` puede estar
## corriendo a la vez con el suyo.
func _purge_temp() -> void:
	if _temp_dir.is_empty() or not DirAccess.dir_exists_absolute(_temp_dir):
		return
	for file_name: String in DirAccess.get_files_at(_temp_dir):
		var _discard := DirAccess.remove_absolute(_temp_dir.path_join(file_name))
	var _removed := DirAccess.remove_absolute(_temp_dir)


func _player_files() -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(PLAYER_DIR):
		return PackedStringArray()
	var files := DirAccess.get_files_at(PLAYER_DIR)
	files.sort()
	return files


func _check_player_dir_untouched() -> void:
	expect(_player_files() == _player_files_before,
			"la prueba no agrega ni quita archivos en %s (antes %s, ahora %s)"
					% [PLAYER_DIR, str(_player_files_before), str(_player_files())])


# --- Traducciones ---------------------------------------------------------------------------

## Toda clave usada tiene texto en los dos idiomas y `tr()` no devuelve la clave cruda.
func _check_translations() -> void:
	var keys := _collect_used_keys()
	for locale: String in LOCALES:
		var translation := TranslationServer.get_translation_object(locale)
		if translation == null:
			fail("no hay objeto de traducción para el locale '%s'" % locale)
			continue
		TranslationServer.set_locale(locale)
		for key: String in keys:
			var message := String(translation.get_message(key))
			expect(not message.is_empty(),
					"la clave '%s' no tiene texto en '%s'" % [key, locale])
			expect(tr(key) != key,
					"tr('%s') devuelve la clave sin traducir en '%s'" % [key, locale])
	TranslationServer.set_locale(_saved_locale)
	print("  claves de traducción comprobadas en es y en: %d" % keys.size())


## Junta las claves fijas de [constant USED_KEYS] con las listas que cada menú declara
## como constantes, de modo que agregar una opción nueva la agregue también al check.
func _collect_used_keys() -> Array[String]:
	var keys: Array[String] = USED_KEYS.duplicate()
	for tip: String in SceneTransition.TIPS:
		_append_key(keys, tip)
	var groups: Array = [
		GameSettingsMenu.NAV_KEYS, GameSettingsMenu.AIM_KEYS, GameSettingsMenu.TAB_KEYS,
		HudConfigPanel.PRESET_KEYS, HudConfigPanel.HORIZON_KEYS,
		GraphicsMenu.WINDOW_MODE_KEYS, GraphicsMenu.VSYNC_KEYS, GraphicsMenu.QUALITY_KEYS,
		GraphicsMenu.MSAA_KEYS, GraphicsMenu.SHADOW_KEYS, GraphicsMenu.GI_KEYS,
		GraphicsMenu.FISHEYE_KEYS, GraphicsMenu.FISHEYE_MSAA_KEYS,
	]
	for group: Array in groups:
		for key: String in group:
			_append_key(keys, key)
	for bus: StringName in AudioMenu.BUS_KEYS:
		_append_key(keys, AudioMenu.BUS_KEYS[bus])
	for toggle: String in GameSettings.HUD_TOGGLES:
		_append_key(keys, "HUD_CFG_%s" % toggle.to_upper())
	# Claves del HUD de vuelo (WP-08). No las escribe ningún menú, pero la vista previa
	# de la pestaña de HUD las pone en pantalla y `docs/12` §10 (riesgo 12) pide que
	# toda clave nueva exista en los dos idiomas.
	_append_key(keys, FlightHUD.ARMED_KEY)
	_append_key(keys, FlightHUD.DISARMED_KEY)
	for mode_key: String in FlightHUD.MODE_KEYS:
		_append_key(keys, String(FlightHUD.MODE_KEYS[mode_key]))
	for reason_key: String in FlightHUD.ARM_FAILED_KEYS:
		_append_key(keys, String(FlightHUD.ARM_FAILED_KEYS[reason_key]))
	for bearing: int in HUDCompassTape.LETTERS:
		_append_key(keys, String(HUDCompassTape.LETTERS[bearing]))
	for readout_key: String in ["HUD_ALT", "HUD_SPD", "HUD_VS", "HUD_REC",
			"HUD_UNIT_M", "HUD_UNIT_KMH", "HUD_UNIT_MPS"]:
		_append_key(keys, readout_key)
	for action_name: StringName in Controls.ACTION_LABELS:
		_append_key(keys, String(Controls.ACTION_LABELS[action_name]))
	for axis_name: StringName in ControlsMenu.FLIGHT_AXIS_KEYS:
		_append_key(keys, String(ControlsMenu.FLIGHT_AXIS_KEYS[axis_name]))
	for step: Array in CalibrationMenu.STEPS:
		_append_key(keys, String(step[0]))
	for index: int in RoundCatalog.count():
		var round_data := RoundCatalog.get_round(index)
		_append_key(keys, String(round_data["name_key"]))
		_append_key(keys, String(round_data["goal_key"]))
	for medal_key: String in RoundCatalog.MEDAL_KEYS:
		_append_key(keys, medal_key)
	for field: Dictionary in QuadSettingsMenu.FRAME_FIELDS:
		_append_key(keys, String(field["key"]))
		_append_key(keys, String(field["help"]))
		_append_key(keys, String(field["suffix"]))
	for group: Array in [QuadSettingsMenu.CURVE_KEYS, QuadSettingsMenu.AXIS_KEYS,
			QuadSettingsMenu.AXIS_HELP]:
		for key: String in group:
			_append_key(keys, key)
	for param_group: Array in QuadSettingsMenu.PARAM_KEYS:
		for key: String in param_group:
			_append_key(keys, key)
	# Las 15 claves de ayuda por curva y parámetro (`docs/04` §4.7).
	for curve_name: String in QuadSettingsMenu.CURVE_HELP_NAMES:
		for param_name: String in QuadSettingsMenu.PARAM_NAMES:
			_append_key(keys, "QUAD_HELP_%s_%s" % [curve_name, param_name])
	for section: Array in HelpPage.SECTIONS:
		if not String(section[0]).is_empty():
			_append_key(keys, String(section[0]))
		_append_key(keys, String(section[1]))
	for key: String in HelpPage.BUTTON_KEYS:
		_append_key(keys, key)
	for key: StringName in PauseMenu.ENTRIES:
		_append_key(keys, String(key))
	return keys


func _append_key(keys: Array[String], key: String) -> void:
	if not keys.has(key):
		keys.append(key)


# --- Menú principal -------------------------------------------------------------------------

func _open_menu() -> void:
	# El foco inicial solo se toma si el jugador no está usando el ratón; de eso ya se
	# ocupó `_pin_input_kind()` al arrancar el check.
	var packed := load(MAIN_MENU_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % MAIN_MENU_SCENE)
		return
	_menu = packed.instantiate() as MainMenu
	if _menu == null:
		fail("%s no instancia un MainMenu" % MAIN_MENU_SCENE)
		return
	add_child(_menu)
	var focused := await _wait_until(func() -> bool: return _focus_name() == "ButtonPlay")
	expect(UI.get_active_context() == _menu, "el menú principal es el contexto activo")
	expect(focused, "el foco inicial cae en MENU_PLAY (quedó en %s)" % _focus_name())
	await _settle()
	expect(_hints_visible(), "el pie de página con las ayudas de control está visible")
	await shot("main_menu")


## Las cinco entradas del menú principal llevan a donde dice `docs/04` §4.10: cuatro
## abren una pantalla que existe y la quinta pide confirmación para salir.
func _check_menu_targets() -> void:
	var targets: Dictionary[StringName, String] = {
		&"MENU_PLAY": ROUNDS_SCENE,
		&"MENU_HANGAR": HANGAR_SCENE,
		&"MENU_OPTIONS": "res://gui/options_menu/options_menu.tscn",
		&"MENU_HELP": HELP_SCENE,
	}
	for key: StringName in targets:
		expect(_menu.button_for(key) != null, "el menú principal tiene botón para %s" % key)
		var wanted: String = targets[key]
		expect(String(MainMenu.SUBMENU_SCENES.get(key, "")) == wanted,
				"%s apunta a %s" % [key, wanted])
		expect(ResourceLoader.exists(wanted), "existe la escena %s" % wanted)
	expect(_menu.button_for(&"MENU_QUIT") != null, "el menú principal tiene botón para MENU_QUIT")
	expect(not MainMenu.SUBMENU_SCENES.has(&"MENU_QUIT"),
			"MENU_QUIT no abre una pantalla: cierra el juego")


# --- Rondas ----------------------------------------------------------------------------------

## `MENU_PLAY` abre el menú de rondas, que lista la ronda del MVP desbloqueada y la
## tarjeta inerte de «próximamente» (`docs/11` §8).
func _check_rounds() -> void:
	var screen := await _open_from_menu(&"MENU_PLAY", "RoundsMenu") as RoundsMenu
	if screen == null:
		return
	expect(RoundCatalog.count() == 1, "el catálogo del MVP congela una sola ronda (tiene %d)"
			% RoundCatalog.count())
	expect(RoundCatalog.get_index("first-contact") == 0,
			"first-contact es la ronda 0 del catálogo")
	expect(RoundCatalog.is_unlocked(0), "la primera ronda está siempre desbloqueada")
	# Umbrales recalibrados en WP-23 con los puntajes medidos por `balance_check`:
	# bronce **350**, plata **800**, oro 2 000 (`docs/11` §12, fila 3). Con el bono
	# de tiempo ya en 8 pts/s, una victoria con una sola reconstrucción rinde entre
	# 918 y 1 329 puntos y con 1 300 se quedaba sin plata.
	expect(RoundCatalog.medal_for(0, 2000) == RoundCatalog.Medal.GOLD
			and RoundCatalog.medal_for(0, 1999) == RoundCatalog.Medal.SILVER
			and RoundCatalog.medal_for(0, 800) == RoundCatalog.Medal.SILVER
			and RoundCatalog.medal_for(0, 350) == RoundCatalog.Medal.BRONZE
			and RoundCatalog.medal_for(0, 349) == RoundCatalog.Medal.NONE,
			"los umbrales de medalla son los de docs/11 §2.2 con la recalibración de WP-23")
	var wanted_level := RoundCatalog.FREE_FLIGHT_LEVEL_SCENE
	if ResourceLoader.exists(RoundCatalog.BATTLE_LEVEL_SCENE):
		wanted_level = RoundCatalog.BATTLE_LEVEL_SCENE
	expect(RoundCatalog.level_scene_for(RoundCatalog.get_round(0)) == wanted_level,
			"la ronda entra a %s" % wanted_level)

	var first := screen.button_for("first-contact")
	expect(first != null and not first.disabled,
			"la ronda first-contact aparece en la lista y se puede elegir")
	var soon := screen.coming_soon_card()
	expect(soon != null and soon.disabled and soon.focus_mode == Control.FOCUS_NONE,
			"mientras falten rondas hay una tarjeta inerte de próximamente")
	_watched_control = first
	var focused := await _wait_until(_watched_control_has_focus)
	expect(focused, "el foco inicial cae en la ronda disponible (quedó en %s)" % _focus_name())
	expect(screen.detail_text().contains(tr("ROUND_FIRST_CONTACT_GOAL")),
			"la línea de detalle muestra el objetivo de la ronda enfocada")
	await _settle()
	_check_no_raw_keys(screen, "el menú de rondas")
	await shot("rounds")
	await _close_to_menu(screen, &"MENU_PLAY")


# --- Hangar ----------------------------------------------------------------------------------

## `MENU_HANGAR` abre el hangar: mover un rate llega a `QuadSettings`, rehace el gráfico
## y sobrevive a salir y recargar el archivo (`docs/04` §4.7).
func _check_hangar() -> void:
	# Abrir el hangar no puede tocar nada: montar nueve deslizadores con su rango acota
	# valores y dispara `value_changed`, y eso pisaría la configuración del jugador.
	var untouched := {
		"angle": QuadSettings.angle,
		"fov": QuadSettings.fov,
		"rc_rate": QuadSettings.rc_rate,
		"rate": QuadSettings.rate,
		"expo": QuadSettings.expo,
	}
	var screen := await _open_from_menu(&"MENU_HANGAR", "QuadSettingsMenu") as QuadSettingsMenu
	if screen == null:
		return
	expect(is_equal_approx(QuadSettings.angle, float(untouched["angle"]))
			and is_equal_approx(QuadSettings.fov, float(untouched["fov"]))
			and QuadSettings.rc_rate.is_equal_approx(untouched["rc_rate"])
			and QuadSettings.rate.is_equal_approx(untouched["rate"])
			and QuadSettings.expo.is_equal_approx(untouched["expo"]),
			"abrir el hangar no cambia ningún valor de QuadSettings (rc_rate %s → %s)"
					% [str(untouched["rc_rate"]), str(QuadSettings.rc_rate)])
	for axis: int in 3:
		var rc := screen.control_for(QuadSettingsMenu.rate_key(axis, 0)) as HSlider
		expect(rc != null and is_equal_approx(rc.value, QuadSettings.rc_rate[axis]),
				"el control de rc_rate del eje %d muestra lo que guarda el autoload"
						% axis)
	var angle := screen.control_for(&"QUAD_CAMERA_ANGLE") as HSlider
	if angle == null:
		fail("el hangar no expone el deslizador de ángulo de cámara")
		return
	_watched_control = angle
	var focused := await _wait_until(_watched_control_has_focus)
	expect(focused, "el foco inicial del hangar cae en el ángulo de cámara (quedó en %s)"
			% _focus_name())
	var curve := screen.control_for(&"QUAD_RATES_CURVE") as OptionButton
	expect(curve != null and curve.item_count == QuadSettingsMenu.CURVE_KEYS.size(),
			"la lista de curvas ofrece las cinco familias de docs/03 §3.6")
	await _settle()
	_check_no_raw_keys(screen, "el hangar")
	await shot("hangar")

	_check_shared_range(screen)
	await _check_rate_change(screen)

	var wanted_rc := QuadSettings.rc_rate
	var wanted_angle := QuadSettings.angle
	await _close_to_menu(screen, &"MENU_HANGAR")
	QuadSettings.load_quad_settings()
	expect(QuadSettings.rc_rate.is_equal_approx(wanted_rc),
			"el rate persiste al salir del hangar (esperado %s, quedó %s)"
					% [str(wanted_rc), str(QuadSettings.rc_rate)])
	expect(is_equal_approx(QuadSettings.angle, wanted_angle),
			"el ángulo de cámara persiste al salir del hangar")


## El deslizador y el `SpinBox` de una fila comparten el mismo `Range` (`docs/04` §4.7).
func _check_shared_range(screen: QuadSettingsMenu) -> void:
	var slider := screen.control_for(&"QUAD_FOV") as HSlider
	if slider == null:
		fail("el hangar no expone el deslizador de FOV")
		return
	var spin := slider.get_parent().get_node_or_null(^"Spin") as SpinBox
	if spin == null:
		fail("la fila de FOV no tiene su SpinBox")
		return
	var before := slider.value
	spin.value = clampf(before + 5.0, QuadSettings.FOV_RANGE.x, QuadSettings.FOV_RANGE.y)
	expect(is_equal_approx(slider.value, spin.value),
			"mover el SpinBox mueve el deslizador: comparten Range")
	expect(is_equal_approx(QuadSettings.fov, spin.value),
			"el FOV del autoload sigue al control (esperado %.1f, quedó %.1f)"
					% [spin.value, QuadSettings.fov])


## Mover un rate con la misma entrada que usaría el jugador escribe en `QuadSettings` y
## obliga al `RateGraph` a rehacerse.
##
## Se mueven los dos números que importan, porque cada uno cambia algo distinto de la
## curva ACTUAL (`docs/03` §3.6): `rate` fija la tasa **máxima** —el número que el
## gráfico escribe encima de cada eje— y `rc_rate` la sensibilidad **cerca del centro**,
## que no toca el máximo mientras `rate·10` siga por encima.
func _check_rate_change(screen: QuadSettingsMenu) -> void:
	var graph := screen.graph()
	if graph == null:
		fail("el hangar no expone su gráfico de rates")
		return
	var rate_key := QuadSettingsMenu.rate_key(ControlProfile.Axis.PITCH, 1)
	var rate_slider := screen.control_for(rate_key) as HSlider
	var rc_key := QuadSettingsMenu.rate_key(ControlProfile.Axis.PITCH, 0)
	var rc_slider := screen.control_for(rc_key) as HSlider
	if rate_slider == null or rc_slider == null:
		fail("el hangar no expone los deslizadores %s y %s" % [rate_key, rc_key])
		return

	var before_rate := QuadSettings.rate.y
	var before_refresh := graph.refresh_count()
	var before_max := graph.max_rates().y
	rate_slider.grab_focus()
	await wait_frames(2)
	for _step: int in 3:
		await _send_action(&"ui_right")
	expect(not is_equal_approx(QuadSettings.rate.y, before_rate),
			"mover %s cambia QuadSettings.rate.y (siguió en %.1f)" % [rate_key, before_rate])
	expect(is_equal_approx(QuadSettings.rate.y, rate_slider.value),
			"el autoload refleja exactamente el valor del control")
	expect(graph.refresh_count() > before_refresh,
			"el gráfico se vuelve a dibujar con cada cambio (%d → %d)"
					% [before_refresh, graph.refresh_count()])
	expect(not is_equal_approx(graph.max_rates().y, before_max),
			"la tasa máxima de pitch del gráfico sigue al rate (siguió en %.1f)" % before_max)
	expect_near(graph.max_rates().y, QuadSettings.control_profile.get_max_rate(
			ControlProfile.Axis.PITCH), 0.01,
			"la tasa máxima del gráfico sale del perfil de control")

	var before_rc := QuadSettings.rc_rate.y
	var before_center := QuadSettings.control_profile.get_rate(ControlProfile.Axis.PITCH, 0.2)
	rc_slider.grab_focus()
	await wait_frames(2)
	for _step: int in 3:
		await _send_action(&"ui_right")
	expect(not is_equal_approx(QuadSettings.rc_rate.y, before_rc),
			"mover %s cambia QuadSettings.rc_rate.y (siguió en %.1f)" % [rc_key, before_rc])
	expect(not is_equal_approx(QuadSettings.control_profile.get_rate(
			ControlProfile.Axis.PITCH, 0.2), before_center),
			"subir rc_rate cambia la respuesta cerca del centro (siguió en %.1f deg/s)"
					% before_center)
	if DisplayServer.get_name() != "headless":
		expect(graph.draw_count() > 0, "con ventana el gráfico se dibujó de verdad")
	await _settle()
	await shot("hangar_rates")


# --- Ayuda -----------------------------------------------------------------------------------

## `MENU_HELP` abre la ayuda y su botón intercambia el cuerpo por las licencias del motor
## (`docs/04` §4.8).
func _check_help() -> void:
	var screen := await _open_from_menu(&"MENU_HELP", "HelpPage") as HelpPage
	if screen == null:
		return
	var focused := await _wait_until(func() -> bool: return _focus_name() == "ButtonLicenses")
	expect(focused, "el foco inicial de la ayuda cae en el botón de licencias (quedó en %s)"
			% _focus_name())
	var body := screen.help_text()
	for section: Array in HelpPage.SECTIONS:
		var text := tr(String(section[1]))
		expect(body.contains(text),
				"la ayuda incluye el texto de %s" % String(section[1]))
	expect(not screen.showing_licenses(), "la ayuda arranca mostrando su propio texto")
	await _settle()
	_check_no_raw_keys(screen, "la ayuda")
	await shot("help")

	await _send_action(&"ui_accept")
	await wait_frames(2)
	expect(screen.showing_licenses(), "el botón cambia a las licencias del motor")
	expect(screen.license_length() > 1000,
			"el texto de Engine.get_license_text() no está vacío (%d caracteres)"
					% screen.license_length())
	await _settle()
	await shot("help_licenses")
	await _send_action(&"ui_accept")
	await wait_frames(2)
	expect(not screen.showing_licenses(), "el botón vuelve a la ayuda")
	await _close_to_menu(screen, &"MENU_HELP")


# --- Pausa -----------------------------------------------------------------------------------

## El menú de pausa, suelto sobre el menú principal: capa, `process_mode`, entradas,
## foco y textos. La pausa **sobre un nivel** —con el árbol detenido y el bloqueo de
## reanudación— la prueba `tools/pause_check.gd` (`docs/15` §1.1, regla 1).
func _check_pause() -> void:
	if not ResourceLoader.exists(PAUSE_SCENE):
		fail("falta el menú de pausa (%s)" % PAUSE_SCENE)
		return
	var packed := load(PAUSE_SCENE) as PackedScene
	var menu := packed.instantiate() as PauseMenu
	if menu == null:
		fail("%s no instancia un PauseMenu" % PAUSE_SCENE)
		return
	# La pausa solo existe con el árbol detenido: su `process_mode` es `WHEN_PAUSED`, así
	# que sin pausar no procesaría ni sus tweens ni su entrada.
	get_tree().paused = true
	add_child(menu)
	var _discard := menu.resumed.connect(_on_pause_resumed)
	expect(menu.layer == PauseMenu.CANVAS_LAYER,
			"la pausa vive en la capa %d (docs/12 §1.1)" % PauseMenu.CANVAS_LAYER)
	expect(menu.process_mode == Node.PROCESS_MODE_WHEN_PAUSED,
			"la pausa se declara PROCESS_MODE_WHEN_PAUSED (docs/04 §4.9)")
	for key: StringName in PauseMenu.ENTRIES:
		expect(menu.button_for(key) != null, "la pausa tiene entrada para %s" % key)
	var focused := await _wait_until(func() -> bool: return _focus_name() == "ButtonResume")
	expect(focused, "el foco inicial de la pausa cae en MENU_RESUME (quedó en %s)"
			% _focus_name())
	await _settle()
	_check_no_raw_keys(menu, "la pausa")
	await shot("pause")

	await _send_action(&"ui_cancel")
	var resumed := await _wait_until(func() -> bool: return _pause_resumed)
	expect(resumed, "ui_cancel sobre la pausa pide seguir jugando")
	menu.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	expect(not get_tree().paused, "cerrar la pausa deja el árbol corriendo")
	_menu.grab_initial_focus(true)
	var back := await _wait_until(_focus_is_in_main_menu)
	expect(back, "al cerrar la pausa el foco vuelve al menú de abajo (quedó en %s)"
			% _focus_name())


## El control con foco cuelga del menú principal.
func _focus_is_in_main_menu() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and is_instance_valid(_menu) and _menu.is_ancestor_of(focus)


func _on_pause_resumed() -> void:
	_pause_resumed = true


# --- Pantallas del menú principal -------------------------------------------------------------

## Activa una entrada del menú principal y espera a su pantalla.
func _open_from_menu(key: StringName, type_name: String) -> MenuScreen:
	var button := _menu.button_for(key)
	if button == null:
		fail("el menú principal no tiene botón para %s" % key)
		return null
	button.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")
	var screen := await _wait_for_screen(type_name)
	expect(screen != null, "%s abre su pantalla (%s)" % [key, type_name])
	return screen


## Cierra con `ui_cancel` y comprueba que el foco vuelve a la entrada del menú principal.
func _close_to_menu(screen: MenuScreen, key: StringName) -> void:
	_watched_screen = screen
	await _send_action(&"ui_cancel")
	var gone := await _wait_until(_watched_screen_is_gone)
	_watched_screen = null
	expect(gone, "ui_cancel cierra la pantalla de %s" % key)
	expect(UI.get_active_context() == _menu,
			"el menú principal vuelve a ser el contexto activo tras cerrar %s" % key)
	var wanted := String(MainMenu.BUTTON_NAMES.get(key, &""))
	var back := await _wait_until(func() -> bool: return _focus_name() == wanted)
	expect(back, "el foco vuelve a %s (quedó en %s)" % [key, _focus_name()])


## `MENU_QUIT` pide confirmación, `ui_cancel` la cancela y el juego sigue vivo.
func _check_quit_is_cancellable() -> void:
	var button := _menu.button_for(&"MENU_QUIT")
	if button == null:
		fail("el menú no tiene botón para MENU_QUIT")
		return
	button.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")
	var opened := await _wait_until(_modal_button_ready)
	expect(opened, "MENU_QUIT abre la confirmación")
	var focus := get_viewport().gui_get_focus_owner() as Button
	expect(focus != null and focus.text == "UI_CANCEL",
			"la confirmación de salir enfoca UI_CANCEL (opción segura, enfocó %s)"
					% _focus_name())
	await _settle()
	await shot("quit_confirm")
	await _send_action(&"ui_cancel")
	var closed := await _wait_until(func() -> bool: return not UI.has_modal())
	expect(closed, "ui_cancel cierra la confirmación de salir")
	expect(is_inside_tree(), "cancelar la confirmación no cierra el juego")
	var back := await _wait_until(func() -> bool: return _focus_name() == "ButtonQuit")
	expect(back, "el foco vuelve a MENU_QUIT (quedó en %s)" % _focus_name())


# --- Opciones --------------------------------------------------------------------------------

## Abre el hub desde el menú principal, recorre sus cuatro entradas y vuelve.
func _check_options() -> void:
	var opener := _menu.button_for(&"MENU_OPTIONS")
	if opener == null:
		fail("el menú no tiene botón para MENU_OPTIONS")
		return
	opener.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")
	var hub := await _wait_for_screen("OptionsMenu") as OptionsMenu
	if hub == null:
		fail("MENU_OPTIONS no abre el hub de opciones")
		return
	expect(UI.get_active_context() == hub, "el hub de opciones es el contexto activo")
	var focused := await _wait_until(func() -> bool: return _focus_name() == "ButtonGame")
	expect(focused, "el foco inicial del hub cae en OPT_GAME (quedó en %s)" % _focus_name())
	await _settle()
	_check_no_raw_keys(hub, "el hub de opciones")
	await shot("options_hub")

	await _check_game_screen(hub)
	await _check_graphics_screen(hub)
	await _check_audio_screen(hub)
	await _check_controls_screen(hub)

	# El hub se cierra con su botón de atrás y devuelve el foco a MENU_OPTIONS.
	await _press_back_button(hub)
	var gone := await _wait_until(func() -> bool: return _find_screen("OptionsMenu") == null)
	expect(gone, "el botón de atrás cierra el hub de opciones")
	var back := await _wait_until(func() -> bool: return _focus_name() == "ButtonOptions")
	expect(back, "el foco vuelve a MENU_OPTIONS (quedó en %s)" % _focus_name())


## Juego y HUD: idioma de ida y vuelta, y un interruptor de la pestaña de HUD.
func _check_game_screen(hub: OptionsMenu) -> void:
	var screen := await _open_from_hub(hub, &"OPT_GAME", "GameSettingsMenu") as GameSettingsMenu
	if screen == null:
		return
	var focused := await _wait_until(func() -> bool: return _focus_name() == "LanguageOption")
	expect(focused, "el foco inicial de Juego y HUD cae en el idioma (quedó en %s)"
			% _focus_name())
	expect(screen.tab_title(0) == tr("GAME_TAB_GAMEPLAY")
			and screen.tab_title(1) == tr("GAME_TAB_HUD"),
			"las pestañas muestran su texto traducido")
	await _settle()
	_check_no_raw_keys(screen, "Juego y HUD")
	await shot("options_game")

	await _check_language(screen)
	await _check_hud_tab(screen)

	await _close_with_cancel(screen, hub, &"OPT_GAME")


## El idioma cambia con el control enfocado, el menú rehace sus textos sin reabrirse y
## el valor sobrevive a una recarga del archivo.
func _check_language(screen: GameSettingsMenu) -> void:
	GameSettings.set_language("es")
	await wait_frames(2)
	var language := screen.control_for(&"GAME_LANGUAGE") as OptionButton
	var aim := screen.control_for(&"GAME_AIM_ASSIST") as OptionButton
	if language == null or aim == null:
		fail("Juego y HUD no expone los controles de idioma y de puntería")
		return
	expect(language.selected == 0, "el idioma arranca en español")
	var spanish := aim.get_item_text(0)

	language.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_right")
	expect(GameSettings.language == "en",
			"elegir English deja GameSettings.language en 'en' (quedó '%s')"
					% GameSettings.language)
	expect(TranslationServer.get_locale().begins_with("en"),
			"el cambio de idioma llega al TranslationServer")
	expect(aim.get_item_text(0) == tr("GAME_AIM_OFF") and aim.get_item_text(0) != spanish,
			"el menú rehace sus textos sin reabrirlo (la lista de puntería dice '%s')"
					% aim.get_item_text(0))
	GameSettings.load_game_settings()
	expect(GameSettings.language == "en", "el idioma persiste tras guardar y recargar")

	await _send_action(&"ui_right")
	expect(GameSettings.language == "es",
			"volver a Español deja GameSettings.language en 'es' (quedó '%s')"
					% GameSettings.language)
	expect(aim.get_item_text(0) == spanish, "los textos vuelven al español")


## Un `CheckButton` de la pestaña de HUD cambia su bool, mueve **el componente** de la
## vista previa real, deja el preset en Custom y sobrevive a una recarga (WP-08).
func _check_hud_tab(screen: GameSettingsMenu) -> void:
	screen.show_tab(1)
	await wait_frames(2)
	var panel := screen.hud_panel()
	var preview := panel.preview_hud()
	expect(preview != null,
			"la pestaña de HUD monta el FlightHUD real en %%HudPreview (quedó %s)"
					% [panel.preview_node()])
	if preview != null:
		expect(preview.preview_mode,
				"la vista previa se alimenta sola con el generador de docs/12 §2.5")
		expect(FlightHUD.Component.size() == 12 and FlightHUD.CONFIG_KEYS.size() == 11,
				"12 componentes y 11 interruptores: STATUS no es configurable (docs/12 §2.4)")
	var toggle := screen.control_for(&"HUD_CFG_REC") as CheckButton
	var preset := screen.control_for(&"HUD_PRESET") as OptionButton
	if toggle == null or preset == null:
		fail("la pestaña de HUD no expone el interruptor de grabación ni el preset")
		return
	expect(not toggle.button_pressed, "el indicador de grabación arranca apagado")
	if preview != null:
		expect(not preview.is_component_visible(FlightHUD.Component.REC),
				"la vista previa arranca con el componente REC apagado")
	toggle.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_right")
	expect(bool(GameSettings.hud_config.get("rec", false)),
			"encender el interruptor escribe hud_config['rec']")
	if preview != null:
		expect(preview.is_component_visible(FlightHUD.Component.REC),
				"encender el interruptor enciende el componente REC de la vista previa real")
	expect(GameSettings.get_hud_preset_name() == GameSettings.CUSTOM_HUD_PRESET,
			"un cambio manual deja el preset de HUD en Custom")
	expect(preset.selected == HudConfigPanel.CUSTOM_INDEX,
			"el selector de preset muestra Custom")
	GameSettings.load_game_settings()
	expect(bool(GameSettings.hud_config.get("rec", false)),
			"el interruptor de grabación persiste tras guardar y recargar")
	await _settle()
	await shot("options_hud")

	await _send_action(&"ui_left")
	expect(not bool(GameSettings.hud_config.get("rec", true)),
			"apagar el interruptor vuelve a escribir hud_config['rec']")
	if preview != null:
		expect(not preview.is_component_visible(FlightHUD.Component.REC),
				"apagar el interruptor apaga el componente REC de la vista previa real")
		await _check_hud_presets(panel, preview)
	screen.show_tab(0)
	await wait_frames(2)


## Los tres presets de `docs/04` §3.4 se reflejan **enteros** en la vista previa, y
## `STATUS` se ve en los tres porque no tiene interruptor (`docs/12` §2.4).
func _check_hud_presets(panel: HudConfigPanel, preview: FlightHUD) -> void:
	var selector := panel.control_for(&"HUD_PRESET") as OptionButton
	for preset_name: String in ["minimal", "standard", "full"]:
		GameSettings.apply_hud_preset(preset_name)
		await wait_frames(2)
		var enabled: Array = GameSettings.HUD_PRESETS[preset_name]
		var wrong := PackedStringArray()
		for component: int in FlightHUD.CONFIG_KEYS:
			var key: String = FlightHUD.CONFIG_KEYS[component]
			var shown := preview.is_component_visible(component as FlightHUD.Component)
			if shown != enabled.has(key):
				wrong.append("%s=%s" % [key, str(shown)])
		expect(wrong.is_empty(),
				"el preset %s se refleja en la vista previa (difieren: %s)"
						% [preset_name, ", ".join(wrong)])
		expect(GameSettings.get_hud_preset_name() == preset_name,
				"aplicar el preset %s deja get_hud_preset_name() en ese preset" % preset_name)
		expect(preview.is_component_visible(FlightHUD.Component.STATUS),
				"STATUS se ve también con el preset %s: no tiene interruptor" % preset_name)
		if selector != null:
			expect(selector.selected == HudConfigPanel.PRESETS.find(preset_name),
					"el selector muestra el preset %s" % preset_name)
	await _settle()
	await shot("options_hud_preview")
	GameSettings.apply_hud_preset(GameSettings.DEFAULT_HUD_PRESET)
	await wait_frames(2)


## Gráficos: un `OptionButton` cambia, marca la calidad como personalizada y persiste.
func _check_graphics_screen(hub: OptionsMenu) -> void:
	var screen := await _open_from_hub(hub, &"OPT_GRAPHICS", "GraphicsMenu") as GraphicsMenu
	if screen == null:
		return
	var focused := await _wait_until(func() -> bool: return _focus_name() == "WindowModeOption")
	expect(focused, "el foco inicial de Gráficos cae en el modo de ventana (quedó en %s)"
			% _focus_name())
	await _settle()
	_check_no_raw_keys(screen, "Gráficos")
	await shot("options_graphics")

	var msaa := screen.control_for(&"GFX_MSAA") as OptionButton
	var preset := screen.control_for(&"GFX_PRESET") as OptionButton
	if msaa == null or preset == null:
		fail("Gráficos no expone los controles de MSAA ni de preset")
	else:
		var before := int(Graphics.msaa)
		msaa.grab_focus()
		await wait_frames(2)
		await _send_action(&"ui_right")
		expect(int(Graphics.msaa) != before,
				"mover el MSAA cambia Graphics.msaa (siguió en %d)" % int(Graphics.msaa))
		expect(msaa.selected == int(Graphics.msaa), "el control muestra el valor aplicado")
		expect(Graphics.quality == Graphics.Quality.CUSTOM,
				"un cambio manual de calidad marca el preset como personalizado")
		expect(preset.selected == GraphicsMenu.CUSTOM_QUALITY_INDEX,
				"el selector de preset muestra Personalizado")
		var saved := int(Graphics.msaa)
		Graphics.save_graphics_settings()
		Graphics.load_graphics_settings()
		expect(int(Graphics.msaa) == saved,
				"el MSAA persiste tras guardar y recargar (esperado %d, obtenido %d)"
						% [saved, int(Graphics.msaa)])
		expect(Graphics.window_mode == Graphics.WindowMode.WINDOW,
				"recargar gráficos no saca la ventana del modo del check")

	await _close_with_back_button(screen, hub, &"OPT_GRAPHICS")


## Audio: un deslizador cambia el volumen del bus, se aplica y persiste.
func _check_audio_screen(hub: OptionsMenu) -> void:
	var screen := await _open_from_hub(hub, &"OPT_AUDIO", "AudioMenu") as AudioMenu
	if screen == null:
		return
	# Todas las filas llaman `Slider` a su deslizador, así que acá se compara el nodo.
	_watched_control = screen.control_for(&"AUD_MASTER")
	var focused := await _wait_until(_watched_control_has_focus)
	expect(focused, "el foco inicial de Audio cae en el deslizador general (quedó en %s)"
			% _focus_name())
	await _settle()
	_check_no_raw_keys(screen, "Audio")
	await shot("options_audio")

	var music := screen.control_for(&"AUD_MUSIC") as HSlider
	if music == null:
		fail("Audio no expone el deslizador de música")
	else:
		var before := Audio.get_volume(&"Music")
		music.grab_focus()
		await wait_frames(2)
		for _step: int in 3:
			await _send_action(&"ui_right")
		var wanted := music.value / 100.0
		expect(not is_equal_approx(wanted, before),
				"mover el deslizador cambia su valor (siguió en %.2f)" % wanted)
		expect_near(Audio.get_volume(&"Music"), wanted, 0.005,
				"el volumen de música aplicado coincide con el deslizador")
		Audio.save_audio_settings()
		Audio.load_audio_settings()
		expect_near(Audio.get_volume(&"Music"), wanted, 0.005,
				"el volumen de música persiste tras guardar y recargar")
		expect(not Audio.muted, "el silencio general sigue apagado")

	await _close_with_cancel(screen, hub, &"OPT_AUDIO")


## Controles: foco inicial, textos, el asistente de calibración y la vuelta.
##
## Lo que se prueba acá es la pantalla: que abre desde el hub, que enfoca el
## selector de mando, que ninguna etiqueta muestra su clave, que el botón de
## calibrar abre el asistente y que cancelarlo no guarda nada. Las asignaciones,
## la captura de bindings y los catorce pasos del asistente son territorio de
## `tools/controls_check.gd` y no se repiten acá (`docs/15` §1.1, regla 1).
func _check_controls_screen(hub: OptionsMenu) -> void:
	if not ResourceLoader.exists(CONTROLS_SCENE):
		fail("falta la pantalla de controles de WP-10 (%s)" % CONTROLS_SCENE)
		return
	var screen := await _open_from_hub(hub, &"OPT_CONTROLS", "ControlsMenu") as ControlsMenu
	if screen == null:
		return
	var focused := await _wait_until(func() -> bool: return _focus_name() == "DeviceOption")
	expect(focused, "el foco inicial de Controles cae en el selector de mando (quedó en %s)"
			% _focus_name())
	expect(screen.binding_row(&"fire") != null and screen.axis_bar(7) != null,
			"la pantalla arma las filas de acciones y las ocho barras de eje")
	await _settle()
	_check_no_raw_keys(screen, "Controles")
	await shot("options_controls")

	await _check_calibration_screen(screen)

	await _close_with_cancel(screen, hub, &"OPT_CONTROLS")


## El asistente de calibración abre, suspende los sticks y se cancela sin guardar.
func _check_calibration_screen(screen: ControlsMenu) -> void:
	if not ResourceLoader.exists(CALIBRATION_SCENE):
		fail("falta el asistente de calibración de WP-10 (%s)" % CALIBRATION_SCENE)
		return
	var calibrate := screen.control_for(&"CTRL_CALIBRATE") as Button
	if calibrate == null:
		fail("Controles no expone el botón de calibrar")
		return
	var before := Controls.get_axis_calibration(&"throttle")
	calibrate.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")
	var wizard := await _wait_for_screen("CalibrationMenu") as CalibrationMenu
	expect(wizard != null, "el botón Calibrar abre el asistente de 14 pasos")
	if wizard == null:
		return
	expect(wizard.current_step() == 0 and CalibrationMenu.STEPS.size() == 14,
			"el asistente arranca en el primero de sus 14 pasos")
	expect(StickNavigation.suspended,
			"el asistente suspende la navegación por sticks (docs/04 §4.6)")
	var focused := await _wait_until(func() -> bool: return _focus_name() == "ButtonNext")
	expect(focused, "el foco inicial del asistente cae en Siguiente (quedó en %s)"
			% _focus_name())
	await _settle()
	_check_no_raw_keys(wizard, "la calibración")
	await shot("options_calibration")

	await _send_action(&"ui_cancel")
	var closed := await _wait_until(
			func() -> bool: return _find_screen("CalibrationMenu") == null)
	expect(closed, "ui_cancel cierra el asistente de calibración")
	expect(not StickNavigation.suspended,
			"al cerrar el asistente, StickNavigation.suspended vuelve a false")
	var after := Controls.get_axis_calibration(&"throttle")
	expect(is_equal_approx(float(before["center"]), float(after["center"]))
			and is_equal_approx(float(before["max"]), float(after["max"]))
			and bool(before["inverted"]) == bool(after["inverted"]),
			"cancelar el asistente no guarda ninguna calibración")
	var back := await _wait_until(
			func() -> bool: return _focus_name() == "ButtonCalibrate")
	expect(back, "el foco vuelve al botón de calibrar (quedó en %s)" % _focus_name())


# --- Recorrido de pantallas -------------------------------------------------------------------

## Activa una entrada del hub y espera a que aparezca la pantalla de tipo [param type_name].
func _open_from_hub(hub: OptionsMenu, key: StringName, type_name: String) -> MenuScreen:
	var entry := hub.button_for(key)
	if entry == null:
		fail("el hub no tiene botón para %s" % key)
		return null
	entry.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")
	var screen := await _wait_for_screen(type_name)
	expect(screen != null, "%s abre su pantalla (%s)" % [key, type_name])
	return screen


## Cierra con `ui_cancel` y comprueba que el foco vuelve a la entrada del hub.
func _close_with_cancel(screen: MenuScreen, hub: OptionsMenu, key: StringName) -> void:
	await _send_action(&"ui_cancel")
	await _expect_closed(screen, hub, key, "ui_cancel")


## Cierra con el botón de atrás y comprueba que el foco vuelve a la entrada del hub.
func _close_with_back_button(screen: MenuScreen, hub: OptionsMenu, key: StringName) -> void:
	await _press_back_button(screen)
	await _expect_closed(screen, hub, key, "el botón de atrás")


func _press_back_button(screen: MenuScreen) -> void:
	var back := _find_back_button(screen)
	if back == null:
		fail("%s no tiene botón con la meta ui_back" % screen.name)
		return
	back.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")


func _expect_closed(screen: MenuScreen, hub: OptionsMenu, key: StringName, how: String) -> void:
	_watched_screen = screen
	var gone := await _wait_until(_watched_screen_is_gone)
	_watched_screen = null
	expect(gone, "%s cierra la pantalla de %s" % [how, key])
	expect(UI.get_active_context() == hub, "el hub vuelve a ser el contexto activo tras %s" % how)
	var wanted := String(OptionsMenu.BUTTON_NAMES.get(key, &""))
	var back := await _wait_until(func() -> bool: return _focus_name() == wanted)
	expect(back, "el foco vuelve a %s tras %s (quedó en %s)" % [key, how, _focus_name()])


## Condición por identidad, para los controles cuyo nombre de nodo se repite entre filas.
func _watched_control_has_focus() -> bool:
	return is_instance_valid(_watched_control) and _watched_control.has_focus()


## Condición de [method _expect_closed]: la pantalla observada ya no está en el árbol.
func _watched_screen_is_gone() -> bool:
	if not is_instance_valid(_watched_screen):
		return true
	return _watched_screen.is_queued_for_deletion() or not _watched_screen.is_inside_tree()


func _find_back_button(root: Node) -> Button:
	if root is Button and (root as Button).has_meta(&"ui_back"):
		return root as Button
	for child: Node in root.get_children():
		var found := _find_back_button(child)
		if found != null:
			return found
	return null


## Primera pantalla viva del tipo pedido dentro del árbol del menú principal.
func _find_screen(type_name: String) -> MenuScreen:
	if not is_instance_valid(_menu):
		return null
	for node: Node in _menu.find_children("*", type_name, true, false):
		if node is MenuScreen and node.is_inside_tree() and not node.is_queued_for_deletion():
			return node as MenuScreen
	return null


func _wait_for_screen(type_name: String) -> MenuScreen:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var screen := _find_screen(type_name)
		if screen != null:
			return screen
		await get_tree().process_frame
	return null


# --- Textos en pantalla -----------------------------------------------------------------------

## Ninguna etiqueta muestra su propia clave: eso delataría una clave ausente del CSV
## (mismo criterio que `menu_shots_check`, `docs/15` §3).
func _check_no_raw_keys(root: Node, screen_name: String) -> void:
	var raw: Array[String] = []
	_collect_raw_keys(root, raw)
	expect(raw.is_empty(), "hay textos sin traducir en %s: %s" % [screen_name, ", ".join(raw)])


func _collect_raw_keys(node: Node, raw: Array[String]) -> void:
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is Button:
		text = (node as Button).text
	if _looks_like_key(text) and tr(text) == text and not raw.has(text):
		raw.append(text)
	for child: Node in node.get_children():
		_collect_raw_keys(child, raw)


func _looks_like_key(text: String) -> bool:
	if text.length() < 3 or not text.contains("_") or text.contains(" "):
		return false
	return text == text.to_upper()


# --- Utilidades -----------------------------------------------------------------------------

## Inyecta una acción de interfaz como evento, para que llegue al control con foco.
## `Input.action_press()` no sirve acá: fija el estado pero no recorre la GUI.
func _send_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)
	await wait_frames(1)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await wait_frames(2)


func _focus_name() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	return str(focus.name) if focus != null else "<sin foco>"


## Deja pasar los fundidos de apertura antes de mirar o capturar la pantalla.
func _settle() -> void:
	await get_tree().create_timer(SETTLE_SECONDS).timeout


## El pie de página de `ControlHints` está en pantalla y con contenido.
func _hints_visible() -> bool:
	for child: Node in _menu.get_children():
		if child is ControlHints:
			var hints := child as ControlHints
			return hints.is_visible_in_tree() and hints.modulate.a > 0.9 \
					and hints.get_child_count() > 0
	return false


## El modal está abierto y su botón ya tomó el foco (lo toma diferido).
func _modal_button_ready() -> bool:
	if not UI.has_modal():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return focus is Button and _menu != null and not _menu.is_ancestor_of(focus)


## Espera a que [param condition] se cumpla; devuelve `false` si se agota el plazo.
## Mide contra el reloj y no contra frames, que en `--headless` duran casi nada.
func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false


func _close() -> void:
	TranslationServer.set_locale(_saved_locale)
	if is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	await wait_frames(4)
	expect(not UI.has_modal(), "no queda ningún modal abierto al terminar")
