## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Idioma, esquema de navegación, `hud_config` y progreso de objetivos y de rondas,
## persistidos en `GameSettings.cfg` (`docs/04` §3.4).
##
## Solo se guarda la métrica cruda (`best_score_<id>`, `best_time_<id>`, máscara de
## objetivos): medallas y desbloqueos se **derivan** (`docs/00` §6). Por eso acá no
## existe `is_round_unlocked()`: esa derivación necesita el orden del catálogo y vive
## en `RoundCatalog` (WP-21), que además es quien conoce los ids. Lo que sí vive acá
## es [method has_completed], que solo mira si hay un registro para ese id.
extends Node

## Esquemas de navegación por sticks; el valor viaja a `StickNavigation.Scheme`
## (0 BETAFLIGHT, 1 YAW_SELECT). `docs/04` §3.4.
enum NavScheme {
	BETAFLIGHT, ## Pitch mueve el foco, roll acepta y vuelve.
	YAW_SELECT, ## Pitch mueve el foco, roll ajusta valores, yaw acepta y vuelve.
}

## Asistencia de puntería (`docs/08`).
enum AimAssist {
	OFF,      ## Sin asistencia.
	SUBTLE,   ## Corrección suave del retículo.
	ASSISTED, ## Corrección marcada.
}

## Se emite después de guardar los ajustes de juego. `ControlHints` la escucha para
## rehacer el pie de página cuando cambia el idioma o el esquema de sticks.
signal game_settings_updated

## Se emite después de guardar la configuración del HUD. La escucha `FlightHUD`,
## tanto el del juego como el preview del menú de opciones.
signal hud_config_updated

## Se emite cuando cambia un récord o se borra el progreso de rondas.
signal round_progress_updated

## Nombre del archivo dentro de `Global.config_dir`.
const CONFIG_FILE: String = "GameSettings.cfg"

## Secciones del archivo (`docs/04` §3.4).
const GAME_SECTION: String = "game"
const HUD_SECTION: String = "hud_config"
const OBJECTIVES_SECTION: String = "objectives"
const ROUNDS_SECTION: String = "rounds"

## Clave de traducción que `Global.startup_errors` acumula si el archivo está roto.
const ERROR_KEY: String = "ERR_CONFIG_GAME"

## Idiomas del juego. El primero es el que se usa si el del sistema no está.
const LANGUAGES: Array[String] = ["es", "en"]

## Clave del indicador de señal (`docs/12` §2.4).
##
## Se nombra aparte porque tiene historia: hasta WP-25 el componente era el punto
## «REC» y se persistía como [constant HUD_SIGNAL_LEGACY_KEY]. WP-25 cambió el
## componente y el rótulo pero dejó la clave vieja en el `.cfg`, y WP-25b la termina
## de renombrar con la migración de [method _read_hud_config].
const HUD_SIGNAL_KEY: String = "signal"

## Nombre con el que los `.cfg` anteriores a WP-25b guardaban
## [constant HUD_SIGNAL_KEY]. Sólo se lee; nunca se vuelve a escribir.
const HUD_SIGNAL_LEGACY_KEY: String = "rec"

## Los 11 interruptores de `[hud_config]`: uno por cada entrada del `enum Component`
## de `docs/12` §2.4 salvo `STATUS`, que siempre se ve.
const HUD_TOGGLES: Array[String] = [
	"crosshair", "horizon", "ladder", "heading", "speed", "altitude",
	"side_tapes", "flight_mode", HUD_SIGNAL_KEY, "sticks", "rpm",
]

## Frecuencia de refresco de los números del HUD, en Hz.
const HUD_FPS_RANGE: Vector2i = Vector2i(5, 60)

## Modos del horizonte artificial (`docs/12` §2.4).
const HUD_HORIZON_MODES: Array[String] = ["camera", "attitude"]

## Presets de HUD (`docs/04` §3.4). `custom` no está acá: es lo que queda cuando la
## configuración no coincide con ninguno.
##
## **`standard` incluye [constant HUD_SIGNAL_KEY] desde WP-28** (`docs/04` §3.4 queda
## corregido). La degradación de la señal es parte de la identidad que eligió el
## usuario —«Última luz» con el préstamo de B: la señal se degrada con el daño—, y un
## indicador que hay que ir a buscar a Opciones no cuenta nada: el piloto tiene que
## enterarse de que la imagen se le está yendo **antes** de que se ponga fea.
##
## Esto gobierna el **primer arranque** y el botón de preset, no a quien ya jugó: un
## `.cfg` existente trae las once claves escritas una a una ([method _write_hud_config])
## y [method _read_hud_config] las respeta. Quien ya tenía el indicador apagado lo sigue
## teniendo apagado hasta que elija un preset, que es el mismo trato que recibe
## cualquier otro interruptor y el único que no le pisa la configuración.
const HUD_PRESETS: Dictionary = {
	"minimal": ["crosshair", "horizon", "flight_mode"],
	"standard": ["crosshair", "horizon", "flight_mode",
			"heading", "speed", "altitude", "side_tapes", "sticks", HUD_SIGNAL_KEY],
	"full": HUD_TOGGLES,
}

## Nombre del preset que se usa en el primer arranque.
const DEFAULT_HUD_PRESET: String = "standard"

## Nombre que devuelve [method get_hud_preset_name] cuando no coincide ninguno.
const CUSTOM_HUD_PRESET: String = "custom"

## Idioma de la interfaz: `"es"` o `"en"`.
var language: String = "es"

## Esquema de navegación por sticks elegido por el jugador.
var nav_scheme: NavScheme = NavScheme.BETAFLIGHT

## Asistencia de puntería.
var aim_assist: AimAssist = AimAssist.SUBTLE

## Intensidad de la sacudida de cámara, `0–1`.
var shake_intensity: float = 1.0

## Avisos de ataque enemigo en el HUD.
var telegraph_hints: bool = true

## Las 13 claves de `[hud_config]`: `fps`, `horizon_mode` y los 11 bools.
var hud_config: Dictionary = {}

## Máscara de bits de los objetivos ya completados.
var objectives_completed: int = 0

## Índice del último objetivo mostrado.
var objectives_last: int = 0

## Récords crudos por ronda: `best_score_<id>` (int) y `best_time_<id>` (float).
var rounds: Dictionary = {}


func _ready() -> void:
	reset_to_defaults()


# --- Carga y guardado ------------------------------------------------------------------------

## Lee `GameSettings.cfg` entero: juego, HUD, objetivos y récords.
##
## Devuelve `""` si todo fue bien —el archivo ausente no es error y solo escribe los
## valores por defecto— o [constant ERROR_KEY] si está corrupto, en cuyo caso se
## vuelve a los valores por defecto y se reescribe (`docs/04` §2).
func load_game_settings() -> String:
	Global.initialize()
	reset_to_defaults()
	var path := Global.config_path(CONFIG_FILE)
	var config := ConfigFile.new()
	var err := config.load(path)
	if err == ERR_FILE_NOT_FOUND:
		_apply_language()
		_apply_nav_scheme()
		save_game_settings()
		return ""
	if err != OK:
		Global.log_error(err, "no se pudo leer %s: %s" % [path, error_string(err)])
		_apply_language()
		_apply_nav_scheme()
		save_game_settings()
		return ERROR_KEY
	language = _read_language(String(config.get_value(GAME_SECTION, "language", language)))
	nav_scheme = clampi(int(config.get_value(GAME_SECTION, "nav_scheme", int(nav_scheme))),
			0, NavScheme.size() - 1) as NavScheme
	aim_assist = clampi(int(config.get_value(GAME_SECTION, "aim_assist", int(aim_assist))),
			0, AimAssist.size() - 1) as AimAssist
	shake_intensity = clampf(float(config.get_value(GAME_SECTION, "shake_intensity",
			shake_intensity)), 0.0, 1.0)
	telegraph_hints = bool(config.get_value(GAME_SECTION, "telegraph_hints", telegraph_hints))
	_read_hud_config(config)
	objectives_completed = maxi(int(config.get_value(OBJECTIVES_SECTION, "completed", 0)), 0)
	objectives_last = maxi(int(config.get_value(OBJECTIVES_SECTION, "last", 0)), 0)
	_read_rounds(config)
	_apply_language()
	_apply_nav_scheme()
	return ""


## Escribe `GameSettings.cfg` entero y emite [signal game_settings_updated].
func save_game_settings() -> void:
	Global.initialize()
	var config := ConfigFile.new()
	config.set_value(GAME_SECTION, "language", language)
	config.set_value(GAME_SECTION, "nav_scheme", int(nav_scheme))
	config.set_value(GAME_SECTION, "aim_assist", int(aim_assist))
	config.set_value(GAME_SECTION, "shake_intensity", shake_intensity)
	config.set_value(GAME_SECTION, "telegraph_hints", telegraph_hints)
	_write_hud_config(config)
	config.set_value(OBJECTIVES_SECTION, "completed", objectives_completed)
	config.set_value(OBJECTIVES_SECTION, "last", objectives_last)
	for key: String in rounds:
		config.set_value(ROUNDS_SECTION, key, rounds[key])
	var path := Global.config_path(CONFIG_FILE)
	var err := config.save(path)
	if err != OK:
		Global.log_error(err, "no se pudo guardar %s: %s" % [path, error_string(err)])
	game_settings_updated.emit()


## Relee solo la sección `[hud_config]` del archivo. Sirve para descartar los
## cambios que el menú de HUD fue aplicando en vivo.
func load_hud_config() -> void:
	var config := ConfigFile.new()
	if config.load(Global.config_path(CONFIG_FILE)) != OK:
		_reset_hud_config()
	else:
		_read_hud_config(config)
	hud_config_updated.emit()


## Guarda el archivo completo y emite [signal hud_config_updated] además de
## [signal game_settings_updated]: el HUD y su preview se rehacen.
func save_hud_config() -> void:
	save_game_settings()
	hud_config_updated.emit()


## Deja todo en valores de fábrica, sin guardar ni aplicar.
func reset_to_defaults() -> void:
	language = _system_language()
	nav_scheme = NavScheme.BETAFLIGHT
	aim_assist = AimAssist.SUBTLE
	shake_intensity = 1.0
	telegraph_hints = true
	objectives_completed = 0
	objectives_last = 0
	rounds.clear()
	_reset_hud_config()


# --- Juego -----------------------------------------------------------------------------------

## Cambia el idioma de la interfaz, lo aplica con `TranslationServer` y lo guarda.
## Un idioma que no esté en [constant LANGUAGES] se ignora.
func set_language(lang: String) -> void:
	var wanted := _read_language(lang)
	if wanted == language:
		return
	language = wanted
	_apply_language()
	save_game_settings()


## Devuelve el esquema de navegación por sticks como entero, tal como lo consume
## `StickNavigation`.
func get_nav_scheme() -> int:
	return int(nav_scheme)


## Fija el esquema de navegación por sticks, lo empuja a `StickNavigation`, lo
## guarda y avisa a quien lo escuche.
func set_nav_scheme(scheme: int) -> void:
	nav_scheme = clampi(scheme, 0, NavScheme.size() - 1) as NavScheme
	_apply_nav_scheme()
	save_game_settings()


# --- HUD -------------------------------------------------------------------------------------

## Vuelca un preset (`minimal`, `standard`, `full`) sobre los 11 interruptores y
## guarda. Un nombre desconocido —incluido `custom`— no hace nada.
func apply_hud_preset(preset_name: String) -> void:
	var key := preset_name.to_lower()
	if not HUD_PRESETS.has(key):
		return
	var enabled: Array = HUD_PRESETS[key]
	for toggle: String in HUD_TOGGLES:
		hud_config[toggle] = enabled.has(toggle)
	save_hud_config()


## Nombre del preset que describe la configuración actual, o
## [constant CUSTOM_HUD_PRESET] si no coincide con ninguno.
func get_hud_preset_name() -> String:
	for key: String in HUD_PRESETS:
		var enabled: Array = HUD_PRESETS[key]
		var matches := true
		for toggle: String in HUD_TOGGLES:
			if bool(hud_config.get(toggle, false)) != enabled.has(toggle):
				matches = false
				break
		if matches:
			return key
	return CUSTOM_HUD_PRESET


# --- Objetivos -------------------------------------------------------------------------------

## Marca el objetivo [param index] como completado y guarda.
func mark_objective_completed(index: int) -> void:
	if index < 0 or index >= 63:
		return
	objectives_completed |= 1 << index
	objectives_last = index
	save_game_settings()


## Verdadero si el objetivo [param index] ya se completó.
func is_objective_completed(index: int) -> bool:
	if index < 0 or index >= 63:
		return false
	return (objectives_completed & (1 << index)) != 0


# --- Récords de ronda ------------------------------------------------------------------------

## Guarda [param score] como récord de [param id] si supera al anterior.
## Devuelve `true` cuando efectivamente era récord.
func record_score(id: String, score: int) -> bool:
	var key := "best_score_%s" % id
	var previous := int(rounds.get(key, -1))
	if score <= previous:
		return false
	rounds[key] = score
	save_game_settings()
	round_progress_updated.emit()
	return true


## Mejor puntaje registrado para [param id]; 0 si la ronda nunca se jugó.
func get_best_score(id: String) -> int:
	return maxi(int(rounds.get("best_score_%s" % id, 0)), 0)


## Guarda [param seconds] como mejor tiempo de [param id] si es más rápido que el
## anterior. Devuelve `true` cuando efectivamente era récord.
func record_time(id: String, seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	var key := "best_time_%s" % id
	var previous := float(rounds.get(key, 0.0))
	if previous > 0.0 and seconds >= previous:
		return false
	rounds[key] = seconds
	save_game_settings()
	round_progress_updated.emit()
	return true


## Mejor tiempo registrado para [param id], en segundos; 0 si nunca se completó.
func get_best_time(id: String) -> float:
	return maxf(float(rounds.get("best_time_%s" % id, 0.0)), 0.0)


## Verdadero si la ronda [param id] llegó alguna vez a su final, es decir, si dejó
## un tiempo registrado. El desbloqueo de la ronda siguiente **no** se deriva acá:
## necesita el orden del catálogo y lo resuelve `RoundCatalog` (WP-21).
func has_completed(id: String) -> bool:
	return get_best_time(id) > 0.0


## Borra todos los récords y la máscara de objetivos, y guarda.
func reset_round_progress() -> void:
	rounds.clear()
	objectives_completed = 0
	objectives_last = 0
	save_game_settings()
	round_progress_updated.emit()


# --- Internos --------------------------------------------------------------------------------

## Aplica [member language] al `TranslationServer`.
func _apply_language() -> void:
	TranslationServer.set_locale(language)


## Empuja el esquema de navegación a `StickNavigation`, que lo lee en su `_ready()`
## y no se entera de los cambios posteriores. Se usa `set()` a propósito: la
## propiedad está tipada con un `enum` propio de ese script y `GameSettings` es un
## autoload **anterior** en el orden de registro (`docs/02` §5).
func _apply_nav_scheme() -> void:
	var nav: Node = get_node_or_null(^"/root/StickNavigation")
	if nav == null:
		return
	nav.set(&"scheme", int(nav_scheme))


## Idioma del sistema si es uno de los soportados; si no, español.
func _system_language() -> String:
	return _read_language(OS.get_locale_language())


## Acota un código de idioma a [constant LANGUAGES].
func _read_language(lang: String) -> String:
	var code := lang.to_lower().substr(0, 2)
	return code if LANGUAGES.has(code) else LANGUAGES[0]


## Deja las 13 claves de `[hud_config]` en el preset por defecto.
func _reset_hud_config() -> void:
	hud_config.clear()
	hud_config["fps"] = 10
	hud_config["horizon_mode"] = HUD_HORIZON_MODES[0]
	var enabled: Array = HUD_PRESETS[DEFAULT_HUD_PRESET]
	for toggle: String in HUD_TOGGLES:
		hud_config[toggle] = enabled.has(toggle)


## Lee `[hud_config]` corrigiendo cualquier clave ausente o fuera de rango; un
## `.cfg` viejo nunca rompe el HUD (`docs/12` §2.4).
func _read_hud_config(config: ConfigFile) -> void:
	_reset_hud_config()
	hud_config["fps"] = clampi(int(config.get_value(HUD_SECTION, "fps", 10)),
			HUD_FPS_RANGE.x, HUD_FPS_RANGE.y)
	var mode := String(config.get_value(HUD_SECTION, "horizon_mode", HUD_HORIZON_MODES[0]))
	hud_config["horizon_mode"] = mode if HUD_HORIZON_MODES.has(mode) else HUD_HORIZON_MODES[0]
	for toggle: String in HUD_TOGGLES:
		hud_config[toggle] = bool(config.get_value(HUD_SECTION, toggle, hud_config[toggle]))
	_migrate_signal_toggle(config)


## Recupera el interruptor del indicador de señal de un `.cfg` anterior a WP-25b.
##
## Sin esto, el jugador que ya lo había encendido lo vería apagado la próxima vez que
## abriera el juego, y sin ningún aviso: el valor seguiría en el archivo, bajo un
## nombre que nadie lee más. La clave nueva manda si están las dos, y el guardado
## siguiente reescribe el archivo entero y se lleva la vieja.
func _migrate_signal_toggle(config: ConfigFile) -> void:
	if config.has_section_key(HUD_SECTION, HUD_SIGNAL_KEY):
		return
	if not config.has_section_key(HUD_SECTION, HUD_SIGNAL_LEGACY_KEY):
		return
	hud_config[HUD_SIGNAL_KEY] = bool(config.get_value(HUD_SECTION,
			HUD_SIGNAL_LEGACY_KEY, hud_config[HUD_SIGNAL_KEY]))


## Escribe las 13 claves de `[hud_config]`.
func _write_hud_config(config: ConfigFile) -> void:
	config.set_value(HUD_SECTION, "fps", int(hud_config.get("fps", 10)))
	config.set_value(HUD_SECTION, "horizon_mode",
			String(hud_config.get("horizon_mode", HUD_HORIZON_MODES[0])))
	for toggle: String in HUD_TOGGLES:
		config.set_value(HUD_SECTION, toggle, bool(hud_config.get(toggle, false)))


## Lee `[rounds]` tal cual: las claves las inventa cada ronda, así que no hay lista
## fija que validar. Solo se descartan los valores que no son números.
func _read_rounds(config: ConfigFile) -> void:
	rounds.clear()
	if not config.has_section(ROUNDS_SECTION):
		return
	for key: String in config.get_section_keys(ROUNDS_SECTION):
		var value: Variant = config.get_value(ROUNDS_SECTION, key)
		if key.begins_with("best_score_") and (value is int or value is float):
			rounds[key] = int(value)
		elif key.begins_with("best_time_") and (value is int or value is float):
			rounds[key] = float(value)
