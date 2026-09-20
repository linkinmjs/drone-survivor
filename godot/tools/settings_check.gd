## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de los autoloads de configuración y de las curvas de rates
## (`docs/04` §9, `docs/03` §3.6).
##
## Verifica, para los cinco archivos de `user://config`: que un archivo corrupto
## devuelve su clave `ERR_CONFIG_*`, deja los valores por defecto y se acumula en
## `Global.startup_errors`; que un archivo ausente **no** es error; que guardar
## valores no por defecto y volver a cargarlos devuelve exactamente lo mismo; que
## `Controls.load_input_map()` reconstruye las ocho acciones de vuelo y las trece
## asignables sin perder los atajos de teclado; y que `get_flight_input()` aplica
## calibración, inversión y zona muerta sobre ejes inyectados. Cierra con las cinco
## curvas de [ControlProfile].
##
## **No toca la configuración del jugador**: antes de la primera prueba apunta
## `Global.config_dir` a [constant TEMP_DIR] y `Global.log_path` a un log dentro de
## ese mismo directorio —porque corromper archivos a propósito deja líneas en el
## log—, y al terminar devuelve ambos a su valor original y borra el directorio. El
## snapshot de `CheckRunner` sobre `user://config` queda como segunda red de seguridad.
extends CheckRunner

## Directorio de trabajo de la prueba. Se borra entero en [method finish].
const TEMP_DIR: String = "user://config_check_tmp"

## Directorio real del jugador, que esta prueba no puede tocar.
const PLAYER_DIR: String = "user://config"

## Contenido que `ConfigFile.load()` no puede parsear.
const GARBAGE: String = "esto no es un archivo de configuración válido\n[[[\nclave = @@@\n"

## Archivos y clave de error de cada autoload, en el orden de `docs/04` §3.1.
const CONFIG_FILES: Array[Array] = [
	["GameSettings.cfg", "ERR_CONFIG_GAME"],
	["Graphics.cfg", "ERR_CONFIG_GRAPHICS"],
	["Audio.cfg", "ERR_CONFIG_AUDIO"],
	["Quad.cfg", "ERR_CONFIG_QUAD"],
	["InputMap.cfg", "ERR_CONFIG_INPUT"],
]

## Tolerancia de los valores de las curvas de rates, en deg/s.
const RATE_TOLERANCE: float = 0.5

## Parámetros con los que se prueba cada curva distinta de ACTUAL: `rc_rate`,
## `rate` y `expo` en las unidades propias de esa curva.
const CURVE_SAMPLES: Array[Array] = [
	[ControlProfile.RateCurve.BETAFLIGHT, 100.0, 70.0, 0.0],
	[ControlProfile.RateCurve.RACEFLIGHT, 67.0, 80.0, 30.0],
	[ControlProfile.RateCurve.KISS, 100.0, 70.0, 30.0],
	[ControlProfile.RateCurve.QUICKRATES, 100.0, 67.0, 54.0],
]

var _saved_player_config_dir: String = ""
var _saved_player_log_path: String = ""
var _original_locale: String = ""
var _player_files_before: PackedStringArray = PackedStringArray()
var _restored: bool = false


func _run() -> void:
	_saved_player_config_dir = Global.config_dir
	_saved_player_log_path = Global.log_path
	_original_locale = TranslationServer.get_locale()
	_player_files_before = _player_files()
	_purge_temp()
	Global.config_dir = TEMP_DIR
	expect(DirAccess.dir_exists_absolute(TEMP_DIR),
			"asignar Global.config_dir crea el directorio nuevo")
	Global.log_path = TEMP_DIR.path_join("output.log")

	_check_corrupt_startup()
	_check_missing_files()
	_check_audio_round_trip()
	_check_game_settings_round_trip()
	_check_graphics_round_trip()
	_check_quality_presets()
	await _check_occlusion_off()
	_check_quad_round_trip()
	_check_controls_round_trip()
	_check_input_map_rebuild()
	await _check_flight_input()
	_check_control_profile()
	_check_player_dir_untouched()


## Devuelve `Global.config_dir` a su valor original y borra el directorio temporal
## antes de que `CheckRunner` cierre el proceso. Se ejecuta también si el check
## falló o si expiró el timeout.
func finish() -> void:
	_restore_environment()
	super()


# --- 1. Archivo corrupto y `Global.startup_errors` --------------------------------------------

## Los cinco archivos rotos a la vez: `load_startup_settings()` acumula las cinco
## claves en orden, cada autoload queda con sus valores por defecto y los archivos
## se reescriben limpios, de modo que el arranque siguiente ya no reporta nada.
func _check_corrupt_startup() -> void:
	for entry: Array in CONFIG_FILES:
		_write_garbage(String(entry[0]))
	Global.startup_errors.clear()
	Global.load_startup_settings()

	var expected: Array[String] = []
	for entry: Array in CONFIG_FILES:
		expected.append(String(entry[1]))
	# Evidencia visible de la prueba negativa: los cinco `.cfg` del directorio
	# temporal se escribieron corruptos a propósito.
	print("  prueba negativa (cinco .cfg corruptos): %s" % ", ".join(Global.startup_errors))
	expect(Global.startup_errors == expected,
			"startup_errors acumula las cinco claves en el orden de docs/04 §3.1 (obtuvo %s)"
					% str(Global.startup_errors))

	expect(is_equal_approx(Audio.get_volume(&"Master"), 1.0)
			and is_equal_approx(Audio.get_volume(&"Music"), 0.8) and not Audio.muted,
			"un Audio.cfg corrupto deja los volúmenes por defecto")
	expect(Graphics.quality == Graphics.Quality.HIGH and Graphics.max_fps == 0,
			"un Graphics.cfg corrupto deja el preset HIGH y sin tope de fps")
	expect(GameSettings.aim_assist == GameSettings.AimAssist.SUBTLE
			and is_equal_approx(GameSettings.shake_intensity, 1.0),
			"un GameSettings.cfg corrupto deja la asistencia sutil y la sacudida al máximo")
	expect(is_equal_approx(QuadSettings.angle, 25.0)
			and is_equal_approx(QuadSettings.fov, 150.0),
			"un Quad.cfg corrupto deja el ángulo y el FOV por defecto")
	expect(Controls.action_list.size() == Controls.BINDABLE_ACTIONS.size(),
			"un InputMap.cfg corrupto deja las 13 acciones de fábrica")

	# Segunda pasada: los archivos quedaron reescritos, así que nadie devuelve error.
	expect(Audio.load_audio_settings().is_empty()
			and Graphics.load_graphics_settings().is_empty()
			and GameSettings.load_game_settings().is_empty()
			and QuadSettings.load_quad_settings().is_empty()
			and Controls.load_input_map().is_empty(),
			"tras el diagnóstico los archivos quedan sanos y la recarga no vuelve a fallar")
	Engine.max_fps = 0

	# Una segunda llamada no vuelve a cargar: es una sola vez por proceso.
	Global.startup_errors.clear()
	_write_garbage("Audio.cfg")
	Global.load_startup_settings()
	expect(Global.startup_errors.is_empty(),
			"load_startup_settings() solo actúa la primera vez del proceso")
	var _discard := Audio.load_audio_settings()


# --- 2. Archivo ausente -----------------------------------------------------------------------

## Un `.cfg` que no existe no es un error: se cargan los valores por defecto y se
## escribe el archivo (`docs/04` §2).
func _check_missing_files() -> void:
	_clear_temp_files()
	expect(Audio.load_audio_settings().is_empty(), "Audio.cfg ausente no es error")
	expect(Graphics.load_graphics_settings().is_empty(), "Graphics.cfg ausente no es error")
	expect(GameSettings.load_game_settings().is_empty(), "GameSettings.cfg ausente no es error")
	expect(QuadSettings.load_quad_settings().is_empty(), "Quad.cfg ausente no es error")
	expect(Controls.load_input_map().is_empty(), "InputMap.cfg ausente no es error")
	Engine.max_fps = 0
	for entry: Array in CONFIG_FILES:
		var path := Global.config_path(String(entry[0]))
		expect(FileAccess.file_exists(path),
				"la carga con el archivo ausente deja escrito %s" % entry[0])


# --- 3. Guardar y recargar --------------------------------------------------------------------

func _check_audio_round_trip() -> void:
	var wanted: Dictionary[StringName, float] = {
		&"Master": 0.62, &"Motors": 0.31, &"Weapons": 0.44, &"Enemies": 0.55,
		&"City": 0.17, &"UI": 0.93, &"Music": 0.08,
	}
	for bus: StringName in wanted:
		Audio.set_volume(bus, wanted[bus])
	Audio.set_muted(true)
	Audio.save_audio_settings()
	Audio.reset_to_defaults()
	expect(Audio.load_audio_settings().is_empty(), "Audio.cfg recién escrito se relee sin error")
	for bus: StringName in wanted:
		expect_near(Audio.get_volume(bus), wanted[bus], 0.0001,
				"el volumen de %s sobrevive al guardado" % bus)
	expect(Audio.muted, "el silencio general sobrevive al guardado")
	# El valor aplicado sobre el servidor coincide con el guardado.
	var index := AudioServer.get_bus_index(&"Music")
	expect_near(AudioServer.get_bus_volume_db(index), Audio.linear_to_volume_db(0.08), 0.01,
			"update_volumes() vuelca el volumen de Music sobre el AudioServer")


func _check_game_settings_round_trip() -> void:
	GameSettings.language = "en"
	GameSettings.nav_scheme = GameSettings.NavScheme.YAW_SELECT
	GameSettings.aim_assist = GameSettings.AimAssist.ASSISTED
	GameSettings.shake_intensity = 0.35
	GameSettings.telegraph_hints = false
	GameSettings.apply_hud_preset("full")
	GameSettings.hud_config["fps"] = 42
	GameSettings.hud_config["horizon_mode"] = "attitude"
	GameSettings.hud_config["rpm"] = false
	GameSettings.mark_objective_completed(3)
	GameSettings.mark_objective_completed(7)
	expect(GameSettings.record_score("r01", 1200), "un puntaje nuevo es récord")
	expect(not GameSettings.record_score("r01", 900), "un puntaje peor no es récord")
	expect(GameSettings.record_time("r01", 88.5), "un tiempo nuevo es récord")
	expect(not GameSettings.record_time("r01", 120.0), "un tiempo peor no es récord")
	expect(GameSettings.record_time("r01", 71.25), "un tiempo mejor sí es récord")
	GameSettings.save_game_settings()

	GameSettings.reset_to_defaults()
	expect(GameSettings.load_game_settings().is_empty(),
			"GameSettings.cfg recién escrito se relee sin error")
	expect(GameSettings.language == "en", "el idioma sobrevive al guardado")
	expect(TranslationServer.get_locale().begins_with("en"),
			"cargar el idioma lo aplica en el TranslationServer")
	expect(GameSettings.get_nav_scheme() == int(GameSettings.NavScheme.YAW_SELECT),
			"el esquema de navegación sobrevive al guardado")
	expect(GameSettings.aim_assist == GameSettings.AimAssist.ASSISTED,
			"la asistencia de puntería sobrevive al guardado")
	expect_near(GameSettings.shake_intensity, 0.35, 0.0001,
			"la intensidad de sacudida sobrevive al guardado")
	expect(not GameSettings.telegraph_hints, "los avisos de ataque sobreviven al guardado")
	expect(GameSettings.hud_config.size() == 13,
			"hud_config tiene 13 claves (obtuvo %d)" % GameSettings.hud_config.size())
	expect(int(GameSettings.hud_config["fps"]) == 42, "la frecuencia del HUD sobrevive")
	expect(String(GameSettings.hud_config["horizon_mode"]) == "attitude",
			"el modo de horizonte sobrevive")
	expect(not bool(GameSettings.hud_config["rpm"]) and bool(GameSettings.hud_config["ladder"]),
			"los 11 interruptores del HUD sobreviven uno a uno")
	expect(GameSettings.get_hud_preset_name() == GameSettings.CUSTOM_HUD_PRESET,
			"apagar un interruptor de Full deja el preset en Custom")
	expect(GameSettings.is_objective_completed(3) and GameSettings.is_objective_completed(7)
			and not GameSettings.is_objective_completed(4),
			"la máscara de objetivos sobrevive al guardado")
	expect(GameSettings.get_best_score("r01") == 1200, "el mejor puntaje sobrevive al guardado")
	expect_near(GameSettings.get_best_time("r01"), 71.25, 0.0001,
			"el mejor tiempo sobrevive al guardado")
	expect(GameSettings.has_completed("r01") and not GameSettings.has_completed("r02"),
			"has_completed() mira el tiempo registrado de esa ronda")

	GameSettings.apply_hud_preset("standard")
	expect(GameSettings.get_hud_preset_name() == "standard",
			"aplicar el preset Standard se reconoce al releerlo")
	_check_signal_toggle_migration()
	GameSettings.reset_round_progress()
	expect(GameSettings.get_best_score("r01") == 0 and not GameSettings.has_completed("r01"),
			"reset_round_progress() borra los récords")
	GameSettings.set_language("es")
	expect(TranslationServer.get_locale().begins_with("es"),
			"set_language() aplica el locale en el acto")


## Un `GameSettings.cfg` anterior a WP-25b guarda el indicador de señal como `rec`
## (`docs/12` §2.4). Al leerlo, el valor tiene que aparecer bajo `signal`.
##
## Sin esta migración el jugador que lo tenía encendido lo vería apagado y sin aviso:
## su valor seguiría en el archivo, bajo un nombre que ya no lee nadie. Se escribe el
## `.cfg` a mano —no hay forma de que `save_game_settings()` produzca la clave vieja,
## que es justamente lo que se quiere— y se comprueba además que el guardado
## siguiente se la lleve.
func _check_signal_toggle_migration() -> void:
	var path := Global.config_path(GameSettings.CONFIG_FILE)
	var legacy := ConfigFile.new()
	expect(legacy.load(path) == OK, "el GameSettings.cfg de la prueba se relee para migrarlo")
	legacy.erase_section_key(GameSettings.HUD_SECTION, GameSettings.HUD_SIGNAL_KEY)
	legacy.set_value(GameSettings.HUD_SECTION, GameSettings.HUD_SIGNAL_LEGACY_KEY, true)
	expect(legacy.save(path) == OK, "se pudo escribir un .cfg con la clave vieja 'rec'")

	GameSettings.reset_to_defaults()
	expect(GameSettings.load_game_settings().is_empty(),
			"un .cfg con la clave vieja se lee sin error")
	expect(bool(GameSettings.hud_config.get(GameSettings.HUD_SIGNAL_KEY, false)),
			"hud_config['rec'] de un .cfg viejo se migra a hud_config['signal']")
	expect(not GameSettings.hud_config.has(GameSettings.HUD_SIGNAL_LEGACY_KEY),
			"la clave vieja no sobrevive en memoria")

	# Y un `.cfg` nuevo tiene que seguir mandando sobre el viejo si estuvieran los dos.
	legacy.set_value(GameSettings.HUD_SECTION, GameSettings.HUD_SIGNAL_KEY, false)
	expect(legacy.save(path) == OK, "se pudo escribir un .cfg con las dos claves")
	expect(GameSettings.load_game_settings().is_empty(),
			"un .cfg con las dos claves se lee sin error")
	expect(not bool(GameSettings.hud_config.get(GameSettings.HUD_SIGNAL_KEY, true)),
			"con las dos claves manda la nueva")

	GameSettings.save_hud_config()
	var rewritten := ConfigFile.new()
	expect(rewritten.load(path) == OK, "el .cfg reescrito se relee")
	expect(not rewritten.has_section_key(GameSettings.HUD_SECTION,
			GameSettings.HUD_SIGNAL_LEGACY_KEY),
			"guardar se lleva la clave vieja del archivo")


func _check_graphics_round_trip() -> void:
	Graphics.window_mode = Graphics.WindowMode.BORDERLESS
	Graphics.resolution_scale = 0.75
	Graphics.vsync = Graphics.VSync.ADAPTIVE
	Graphics.max_fps = 240
	Graphics.apply_quality_preset(Graphics.Quality.ULTRA, false)
	Graphics.mark_custom_quality()
	Graphics.fisheye_msaa = Graphics.FisheyeMsaa.X2
	Graphics.save_graphics_settings()

	Graphics.reset_to_defaults()
	expect(Graphics.load_graphics_settings().is_empty(),
			"Graphics.cfg recién escrito se relee sin error")
	Engine.max_fps = 0
	expect(Graphics.window_mode == Graphics.WindowMode.BORDERLESS,
			"el modo de ventana sobrevive al guardado")
	expect_near(Graphics.resolution_scale, 0.75, 0.0001,
			"la escala de resolución sobrevive al guardado")
	expect(Graphics.vsync == Graphics.VSync.ADAPTIVE, "el vsync sobrevive al guardado")
	expect(Graphics.max_fps == 240, "el tope de fps sobrevive al guardado")
	expect(Graphics.quality == Graphics.Quality.CUSTOM, "el preset Custom sobrevive al guardado")
	expect(Graphics.msaa == Graphics.Msaa.X8 and Graphics.shadows == Graphics.Shadows.ULTRA
			and Graphics.gi == Graphics.Gi.SDFGI and Graphics.volumetric_fog and Graphics.ssao,
			"los valores que dejó el preset ULTRA sobreviven al guardado")
	# El modo es el que dejó el preset ULTRA, que desde WP-24c es FAST_WIDE y no FULL.
	expect(Graphics.fisheye_mode == Graphics.FisheyeMode.FAST_WIDE
			and Graphics.fisheye_resolution == Graphics.FisheyeResolution.P1080
			and Graphics.fisheye_msaa == Graphics.FisheyeMsaa.X2,
			"la configuración del ojo de pez sobrevive al guardado (obtenido modo %d, resolución %d, msaa %d)"
					% [int(Graphics.fisheye_mode), int(Graphics.fisheye_resolution),
					int(Graphics.fisheye_msaa)])
	expect(Graphics.is_headless(), "el check corre en headless y Graphics lo detecta")

	# Los cuatro presets existen y son coherentes con la tabla de `docs/04` §3.5.
	expect(Graphics.QUALITY_PRESETS.size() == 4, "QUALITY_PRESETS tiene los cuatro presets")
	Graphics.apply_quality_preset(Graphics.Quality.LOW, false)
	expect(Graphics.msaa == Graphics.Msaa.OFF and Graphics.shadows == Graphics.Shadows.LOW
			and Graphics.gi == Graphics.Gi.OFF and not Graphics.volumetric_fog
			and not Graphics.ssao
			and Graphics.fisheye_resolution == Graphics.FisheyeResolution.P480,
			"el preset LOW vuelca los valores de la tabla")

	# `apply_environment_quality()` escribe sobre el Environment del nivel.
	var env := Environment.new()
	Graphics.apply_quality_preset(Graphics.Quality.ULTRA, false)
	Graphics.apply_environment_quality(env)
	expect(env.sdfgi_enabled and env.volumetric_fog_enabled and env.ssao_enabled,
			"apply_environment_quality() enciende SDFGI, niebla y SSAO en ULTRA")
	Graphics.apply_quality_preset(Graphics.Quality.LOW, false)
	Graphics.apply_environment_quality(env)
	expect(not env.sdfgi_enabled and not env.volumetric_fog_enabled and not env.ssao_enabled,
			"apply_environment_quality() los apaga en LOW")
	Engine.max_fps = 0


func _check_quad_round_trip() -> void:
	QuadSettings.angle = 42.0
	QuadSettings.dry_weight = 0.61
	QuadSettings.battery_weight = 0.24
	QuadSettings.fov = 132.0
	QuadSettings.curve = ControlProfile.RateCurve.KISS
	QuadSettings.rc_rate = Vector3(110.0, 108.0, 90.0)
	QuadSettings.rate = Vector3(70.0, 70.0, 62.0)
	QuadSettings.expo = Vector3(25.0, 25.0, 30.0)
	QuadSettings.save_quad_settings()
	expect(QuadSettings.control_profile.curve == ControlProfile.RateCurve.KISS
			and QuadSettings.control_profile.rc_rate.is_equal_approx(Vector3(110.0, 108.0, 90.0)),
			"guardar reconstruye control_profile")

	QuadSettings.reset_to_defaults()
	expect(QuadSettings.load_quad_settings().is_empty(),
			"Quad.cfg recién escrito se relee sin error")
	expect_near(QuadSettings.angle, 42.0, 0.0001, "el ángulo de cámara sobrevive al guardado")
	expect_near(QuadSettings.dry_weight, 0.61, 0.0001, "el peso seco sobrevive al guardado")
	expect_near(QuadSettings.battery_weight, 0.24, 0.0001,
			"el peso de batería sobrevive al guardado")
	expect_near(QuadSettings.fov, 132.0, 0.0001, "el FOV sobrevive al guardado")
	expect_near(QuadSettings.total_mass(), 0.85, 0.0001, "la masa total es seca más batería")
	expect(QuadSettings.curve == ControlProfile.RateCurve.KISS,
			"la curva de rates sobrevive al guardado")
	expect(QuadSettings.rate.is_equal_approx(Vector3(70.0, 70.0, 62.0))
			and QuadSettings.expo.is_equal_approx(Vector3(25.0, 25.0, 30.0)),
			"los nueve parámetros de rates sobreviven al guardado")
	expect(QuadSettings.control_profile.curve == ControlProfile.RateCurve.KISS
			and QuadSettings.control_profile.expo.is_equal_approx(Vector3(25.0, 25.0, 30.0)),
			"cargar reconstruye control_profile")

	# Los rangos de `docs/04` §3.6 acotan lo que venga del archivo.
	QuadSettings.angle = 999.0
	QuadSettings.fov = 10.0
	QuadSettings.save_quad_settings()
	var _discard := QuadSettings.load_quad_settings()
	expect_near(QuadSettings.angle, 80.0, 0.0001, "el ángulo se acota a 80 grados")
	expect_near(QuadSettings.fov, 90.0, 0.0001, "el FOV se acota a 90 grados")

	QuadSettings.reset_quad()
	QuadSettings.reset_rates()
	expect(QuadSettings.curve == ControlProfile.RateCurve.ACTUAL
			and QuadSettings.rc_rate.is_equal_approx(Vector3(QuadSettings.DEFAULT_RC_RATE,
					QuadSettings.DEFAULT_RC_RATE, QuadSettings.DEFAULT_RC_RATE))
			and QuadSettings.rate.is_equal_approx(Vector3(QuadSettings.DEFAULT_RATE,
					QuadSettings.DEFAULT_RATE, QuadSettings.DEFAULT_RATE))
			and is_equal_approx(QuadSettings.angle, 25.0),
			"reset_quad() y reset_rates() vuelven a los valores de fábrica")


func _check_controls_round_trip() -> void:
	Controls.assume_joypad = true
	Controls.update_active_device(0)
	Controls.save_axis_calibration(&"throttle", 1, -1.0, -0.5, 1.0, false)
	Controls.save_axis_calibration(&"yaw", 0, -1.0, 0.0, 1.0, true)
	Controls.save_axis_calibration(&"roll", 2, -1.0, 0.0, 1.0, false)
	Controls.save_axis_calibration(&"pitch", 3, -0.9, 0.05, 0.95, true)
	Controls.save_axis_binding(&"fire", 5, 0.4, 0.9)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_X
	Controls.save_binding(&"respawn", button)
	Controls.clear_binding(&"change_camera")
	Controls.set_default_device("GUID-DE-PRUEBA")

	expect(Controls.load_input_map().is_empty(), "InputMap.cfg recién escrito se relee sin error")
	var throttle := Controls.get_axis_calibration(&"throttle")
	expect(int(throttle["axis"]) == 1 and is_equal_approx(float(throttle["center"]), -0.5)
			and not bool(throttle["inverted"]),
			"la calibración del acelerador sobrevive al guardado")
	var pitch := Controls.get_axis_calibration(&"pitch")
	expect(bool(pitch["inverted"]) and is_equal_approx(float(pitch["min"]), -0.9)
			and is_equal_approx(float(pitch["max"]), 0.95),
			"la inversión y los extremos de pitch sobreviven al guardado")
	var fire := Controls.get_action(&"fire")
	expect(fire != null and fire.bound and fire.type == ControllerAction.Type.AXIS
			and fire.axis == 5 and is_equal_approx(fire.axis_min, 0.4)
			and is_equal_approx(fire.axis_max, 0.9),
			"la banda de eje de fire sobrevive al guardado")
	var respawn := Controls.get_action(&"respawn")
	expect(respawn != null and respawn.bound and respawn.type == ControllerAction.Type.BUTTON
			and respawn.button == int(JOY_BUTTON_X),
			"el botón de respawn sobrevive al guardado")
	var camera := Controls.get_action(&"change_camera")
	expect(camera != null and not camera.bound,
			"una acción sin asignar sigue sin asignar tras recargar")
	expect(Controls.default_controller_guid == "GUID-DE-PRUEBA",
			"el mando preferido sobrevive al guardado")

	# La copia que devuelve get_axis_calibration() no es la interna.
	throttle["center"] = 0.9
	expect(is_equal_approx(float(Controls.get_axis_calibration(&"throttle")["center"]), -0.5),
			"get_axis_calibration() devuelve una copia")

	Controls.reset_controller_bindings()
	var reset_fire := Controls.get_action(&"fire")
	expect(reset_fire != null and reset_fire.axis == 5 and is_equal_approx(reset_fire.axis_min, 0.35),
			"reset_controller_bindings() vuelve a la banda de fábrica de fire")


# --- 3.bis. Tabla de presets de `docs/13` §3.4 (WP-24a) ---------------------------------------

## La tabla de calidad de `docs/13` §3.4 aplicada de verdad: sombras, SDFGI, SSAO,
## SSIL, niebla, escala de render y emisores.
##
## Hasta WP-24a el preset sólo movía cinco booleanos: el alcance y las cascadas de
## la sombra estaban cableados en cada escena (700 m en `battle_level.tscn`), SDFGI
## corría con los valores por defecto del motor y apagarlo dejaba la ciudad a
## oscuras porque nadie ponía el ambiente de respaldo. Esto verifica que cada
## número de la tabla llega a donde tiene que llegar.
##
## **Discrepancia anotada**: `docs/04` §3.5 pedía atlas `2048/4096/8192/8192/16384`
## y filtros `HARD/SOFT_LOW/SOFT_MEDIUM/SOFT_HIGH/SOFT_ULTRA`. Manda `docs/13` §3.4,
## que es el documento de los presets: atlas `2048/2048/4096/8192/8192` y el índice
## HIGH con `SOFT_MEDIUM`, no con `SOFT_HIGH`.
func _check_quality_presets() -> void:
	_check_shadow_table()
	_check_sun_registration()
	_check_environment_presets()
	_check_preset_scalars()


## Las cuatro tablas de sombra tienen un valor por nivel de `Shadows` y son las de
## `docs/13` §3.4.
func _check_shadow_table() -> void:
	var levels := Graphics.Shadows.size()
	expect(Graphics.SHADOW_ATLAS_SIZES.size() == levels
			and Graphics.SHADOW_FILTERS.size() == levels
			and Graphics.SHADOW_SPLIT_COUNTS.size() == levels
			and Graphics.SHADOW_DISTANCES.size() == levels
			and Graphics.SHADOW_SPLIT_1.size() == levels,
			"las tablas de sombra tienen un valor por nivel de Shadows (%d)" % levels)
	expect(Graphics.SHADOW_ATLAS_SIZES == [2048, 2048, 4096, 8192, 8192],
			"atlas de sombra de docs/13 §3.4, obtenido %s" % str(Graphics.SHADOW_ATLAS_SIZES))
	expect(Graphics.SHADOW_SPLIT_COUNTS == [2, 2, 4, 4, 4],
			"splits de docs/13 §3.4, obtenido %s" % str(Graphics.SHADOW_SPLIT_COUNTS))
	expect(Graphics.SHADOW_DISTANCES == [120.0, 120.0, 200.0, 320.0, 420.0],
			"alcance de sombra de docs/13 §3.4, obtenido %s" % str(Graphics.SHADOW_DISTANCES))
	expect(Graphics.SHADOW_FILTERS[Graphics.Shadows.HIGH]
			== RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
			"el filtro de HIGH es SOFT_MEDIUM (docs/13 §3.4 fila «filtro 2»)")
	expect(Graphics.SHADOW_FILTERS[Graphics.Shadows.VERY_LOW]
			== RenderingServer.SHADOW_QUALITY_HARD,
			"el filtro de VERY_LOW es de sombras duras")
	expect(Graphics.SHADOW_FILTERS[Graphics.Shadows.ULTRA]
			== RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
			"el filtro de ULTRA es SOFT_HIGH")
	print("  presets: atlas %s, splits %s, alcance %s"
			% [str(Graphics.SHADOW_ATLAS_SIZES), str(Graphics.SHADOW_SPLIT_COUNTS),
			str(Graphics.SHADOW_DISTANCES)])


## `apply_sun_quality()` vuelca la fila del nivel sobre la luz, y `register_sun()`
## la vuelve a volcar cuando el jugador cambia de preset.
func _check_sun_registration() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "SunCheck"
	add_child(sun)
	var fired: Array[bool] = [false]
	var on_changed := func() -> void:
		fired[0] = true
	var _discard := Graphics.shadows_changed.connect(on_changed)

	Graphics.shadows = Graphics.Shadows.HIGH
	Graphics.register_sun(sun)
	expect(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			and is_equal_approx(sun.directional_shadow_max_distance, 320.0)
			and sun.directional_shadow_blend_splits
			and is_equal_approx(sun.directional_shadow_fade_start, Graphics.SHADOW_FADE_START)
			and is_equal_approx(sun.shadow_normal_bias, Graphics.SHADOW_NORMAL_BIAS),
			"register_sun() deja el sol en HIGH: 4 splits, 320 m, mezcla y sesgo 1.6"
			+ " (obtenido %d splits, %.1f m)"
			% [4 if sun.directional_shadow_mode
			== DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS else 2,
			sun.directional_shadow_max_distance])
	expect(Graphics.get_registered_suns().has(sun), "el sol queda dado de alta")

	fired[0] = false
	Graphics.shadows = Graphics.Shadows.VERY_LOW
	Graphics.update_shadows()
	expect(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			and is_equal_approx(sun.directional_shadow_max_distance, 120.0)
			and not sun.directional_shadow_blend_splits,
			"cambiar de preset reaplica la tabla sobre el sol ya registrado"
			+ " (obtenido %.1f m)" % sun.directional_shadow_max_distance)
	expect(fired[0], "update_shadows() emite shadows_changed")

	Graphics.shadows_changed.disconnect(on_changed)
	Graphics.unregister_sun(sun)
	expect(not Graphics.get_registered_suns().has(sun), "unregister_sun() lo da de baja")
	sun.queue_free()


## `apply_environment_quality()` escribe la fila del preset sobre el `Environment`.
func _check_environment_presets() -> void:
	var env := Environment.new()

	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	Graphics.apply_environment_quality(env)
	expect(env.sdfgi_enabled and env.sdfgi_cascades == Graphics.SDFGI_CASCADES_HIGH
			and is_equal_approx(env.sdfgi_cascade0_distance, Graphics.SDFGI_CASCADE0_DISTANCE)
			and env.sdfgi_y_scale == Environment.SDFGI_Y_SCALE_100_PERCENT
			and env.sdfgi_use_occlusion
			and is_equal_approx(env.sdfgi_bounce_feedback, Graphics.SDFGI_BOUNCE_FEEDBACK),
			"HIGH: SDFGI con %d cascadas, cascada0 de %.0f m, y_scale 100 %% y oclusión"
			% [env.sdfgi_cascades, env.sdfgi_cascade0_distance])
	expect(not env.ssil_enabled, "HIGH no enciende SSIL (docs/13 §3.4: sólo ULTRA)")
	expect(env.ssao_enabled and is_equal_approx(env.ssao_radius, Graphics.SSAO_RADIUS),
			"HIGH: SSAO con radio %.1f" % env.ssao_radius)
	expect(env.volumetric_fog_enabled
			and is_equal_approx(env.volumetric_fog_length, 96.0),
			"HIGH: niebla volumétrica de 96 m (obtenido %.0f)" % env.volumetric_fog_length)

	Graphics.apply_quality_preset(Graphics.Quality.ULTRA, false)
	Graphics.apply_environment_quality(env)
	expect(env.sdfgi_cascades == Graphics.SDFGI_CASCADES_ULTRA and env.ssil_enabled
			and is_equal_approx(env.volumetric_fog_length, 128.0),
			"ULTRA: %d cascadas, SSIL encendido y niebla de %.0f m"
			% [env.sdfgi_cascades, env.volumetric_fog_length])

	Graphics.apply_quality_preset(Graphics.Quality.MEDIUM, false)
	Graphics.ssao = true
	Graphics.apply_environment_quality(env)
	expect(is_equal_approx(env.ssao_radius, Graphics.SSAO_RADIUS_MEDIUM),
			"MEDIUM: SSAO con radio 1.2 (obtenido %.2f)" % env.ssao_radius)

	Graphics.apply_quality_preset(Graphics.Quality.LOW, false)
	Graphics.apply_environment_quality(env)
	expect(not env.sdfgi_enabled and not env.volumetric_fog_enabled and not env.ssao_enabled
			and not env.ssil_enabled,
			"LOW: SDFGI, niebla, SSAO y SSIL apagados")
	expect(env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
			and env.ambient_light_color.is_equal_approx(Graphics.FALLBACK_AMBIENT_COLOR)
			and is_equal_approx(env.ambient_light_energy, Graphics.FALLBACK_AMBIENT_ENERGY),
			"LOW: ambiente de respaldo #2A3A52 a 0.55 (docs/13 §3.4), obtenido %s a %.2f"
			% [env.ambient_light_color.to_html(false), env.ambient_light_energy])

	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	Graphics.apply_environment_quality(env)
	expect(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY,
			"volver a HIGH devuelve el ambiente al cielo")


## El modo de ojo de pez de cada preset y los recortes de las caras laterales
## (`docs/03` §5, WP-24c).
##
## La fila que importa es **HIGH → FAST_WIDE**: es el preset por defecto y el que
## juega el usuario, y es el que deja de tener el churretón de los costados. LOW y
## MEDIUM siguen en FAST —donde ahora hay viñeta negra en vez de texel repetido— y
## ULTRA en FULL.
func _check_fisheye_presets() -> void:
	var modes: Array[int] = []
	for preset: Graphics.Quality in [Graphics.Quality.LOW, Graphics.Quality.MEDIUM,
			Graphics.Quality.HIGH, Graphics.Quality.ULTRA]:
		Graphics.apply_quality_preset(preset, false)
		modes.append(int(Graphics.fisheye_mode))
	var wanted: Array[int] = [
		int(Graphics.FisheyeMode.FAST), int(Graphics.FisheyeMode.FAST),
		int(Graphics.FisheyeMode.FAST_WIDE), int(Graphics.FisheyeMode.FAST_WIDE),
	]
	expect(modes == wanted,
			"el ojo de pez por preset es FAST/FAST/FAST_WIDE/FAST_WIDE, obtenido %s"
			% str(modes))
	# FULL ya no lo pide ningún preset, pero sigue existiendo como opción del menú
	# para quien quiera 170° sin viñeta: el modo y su clave tienen que seguir ahí.
	expect(not modes.has(int(Graphics.FisheyeMode.FULL)),
			"ningún preset usa FULL: cuesta 14,1 ms de GPU y se pasa del presupuesto de"
			+ " draw calls (obtenido %s)" % str(modes))
	expect(int(Graphics.FisheyeMode.FULL) < Graphics.FisheyeMode.size()
			and GraphicsMenu.FISHEYE_KEYS[int(Graphics.FisheyeMode.FULL)]
					== "GFX_FISHEYE_FULL",
			"FULL sigue siendo elegible a mano desde el menú de gráficos")
	expect(int(Graphics.FisheyeMode.FAST_WIDE) == 3,
			"FisheyeMode.FAST_WIDE tiene que valer 3: anexarlo al final es lo que deja"
			+ " válidos los Graphics.cfg ya escritos (obtuvo %d)"
			% int(Graphics.FisheyeMode.FAST_WIDE))
	expect(GraphicsMenu.FISHEYE_KEYS.size() == Graphics.FisheyeMode.size(),
			"el menú de gráficos tiene una clave por modo de ojo de pez (%d claves, %d modos)"
			% [GraphicsMenu.FISHEYE_KEYS.size(), Graphics.FisheyeMode.size()])

	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	var side := Graphics.fisheye_side_height()
	expect(side == 720,
			"en HIGH, con la frontal a 1080, las laterales miden 720 px de lado (2/3),"
			+ " obtenido %d" % side)
	Graphics.apply_quality_preset(Graphics.Quality.ULTRA, false)
	var ultra_side := Graphics.fisheye_side_height()
	expect(ultra_side == 1080,
			"en ULTRA las laterales igualan a la frontal: 1080 px de lado, obtenido %d"
			% ultra_side)
	# WP-24e: las laterales ya **no** llevan un suelo de LOD propio. Un prop de
	# azotea que cambiaba de LOD al cruzar la costura entre la cara frontal y la
	# lateral parpadeaba sobre sí mismo dentro del fundido, porque ahí las dos caras
	# se mezclan y el salto no se esconde.
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	expect(is_equal_approx(Graphics.fisheye_side_mesh_lod(), Graphics.mesh_lod_threshold()),
			"las laterales usan el mismo LOD que el preset (%.1f px), obtenido %.1f"
			% [Graphics.mesh_lod_threshold(), Graphics.fisheye_side_mesh_lod()])
	var lod_by_preset: Array[float] = []
	for preset: Graphics.Quality in [Graphics.Quality.LOW, Graphics.Quality.MEDIUM,
			Graphics.Quality.HIGH, Graphics.Quality.ULTRA]:
		Graphics.apply_quality_preset(preset, false)
		lod_by_preset.append(Graphics.fisheye_side_mesh_lod()
				- Graphics.mesh_lod_threshold())
	for delta: float in lod_by_preset:
		expect(is_zero_approx(delta),
				"en algún preset el LOD lateral se aparta del frontal (deltas %s)"
				% str(lod_by_preset))
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	expect(int(Graphics.fisheye_side_msaa_level()) <= int(Viewport.MSAA_2X)
			and int(Graphics.fisheye_side_msaa_level())
					<= int(Graphics.fisheye_msaa_level()),
			"el MSAA lateral está acotado a 2× y nunca supera el frontal (%d contra %d)"
			% [int(Graphics.fisheye_side_msaa_level()), int(Graphics.fisheye_msaa_level())])

	# El lado lateral está acotado por arriba y por abajo, para que 2160p no dispare
	# dos caras de 1440 ni 240p las deje en 160.
	Graphics.fisheye_resolution = Graphics.FisheyeResolution.P2160
	var big := Graphics.fisheye_side_height()
	Graphics.fisheye_resolution = Graphics.FisheyeResolution.P240
	var small := Graphics.fisheye_side_height()
	expect(big == Graphics.FISHEYE_SIDE_RANGE.y and small == Graphics.FISHEYE_SIDE_RANGE.x,
			"el lado lateral se acota a [%d, %d], obtenido %d y %d"
			% [Graphics.FISHEYE_SIDE_RANGE.x, Graphics.FISHEYE_SIDE_RANGE.y, small, big])
	print("  ojo de pez por preset: %s; laterales %d² en HIGH y %d² en ULTRA, con LOD %.1f px (el del preset) y MSAA %d"
			% [str(modes), side, ultra_side, Graphics.fisheye_side_mesh_lod(),
			int(Graphics.fisheye_side_msaa_level())])


## Ninguna viewport pide oclusión por oclusores, en ningún preset (WP-24e).
##
## Se prueba sobre una [FPVCamera] de verdad y no sobre `Graphics` a secas porque el
## bug vivía justamente en el eslabón de abajo: una `SubViewport` **no** hereda
## `use_occlusion_culling` del proyecto, así que el ojo de pez lo escribe a mano en
## `_add_face()` y en `_apply_viewport_quality()`, y ahí es donde se dibuja la
## escena. Con la oclusión encendida, los 15 oclusores horneados del distrito
## —ceñidos al edificio más alto de cada manzana y nunca retirados al derrumbarlo—
## tapaban al coloso y se tragaban cuadros enteros cuando la cámara entraba en una
## losa fantasma. Apagarla cuesta −0,011 ms según `docs/perf/2026-09-20.json`: nada.
##
## De paso se comprueba lo otro que viaja por el mismo camino: el LOD de malla de
## las tres caras, que desde WP-24e es el mismo del preset a los dos lados de la
## costura.
func _check_occlusion_off() -> void:
	expect(not bool(ProjectSettings.get_setting(
			"rendering/occlusion_culling/use_occlusion_culling", false)),
			"el proyecto no puede pedir rendering/occlusion_culling/use_occlusion_culling")
	var camera := FPVCamera.new()
	camera.name = "OcclusionProbe"
	add_child(camera)
	await wait_physics(2)

	var offenders: Array[String] = []
	var counted := 0
	var names: Array[String] = ["LOW", "MEDIUM", "HIGH", "ULTRA"]
	for index: int in names.size():
		var preset := index as Graphics.Quality
		Graphics.apply_quality_preset(preset, false)
		expect(not Graphics.use_occlusion_culling(),
				"Graphics.use_occlusion_culling() devolvió true en el preset %s" % names[index])
		camera.set_fisheye_mode(int(Graphics.fisheye_mode))
		await wait_physics(2)
		var lod := Graphics.mesh_lod_threshold()
		for viewport: SubViewport in camera.get_fisheye_viewports():
			counted += 1
			if viewport.use_occlusion_culling:
				offenders.append("%s/%s: oclusión" % [names[index], viewport.name])
			if not is_equal_approx(viewport.mesh_lod_threshold, lod):
				offenders.append("%s/%s: LOD %.2f ≠ %.2f"
						% [names[index], viewport.name, viewport.mesh_lod_threshold, lod])
	camera.queue_free()
	await wait_physics(2)
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)

	print("  oclusión: %d sub-viewports del ojo de pez revisadas en 4 presets, %d con oclusión o LOD fuera de sitio"
			% [counted, offenders.size()])
	# LOW y MEDIUM van en FAST (una cara) y HIGH y ULTRA en FAST_WIDE (tres): ocho.
	expect(counted >= 8,
			"se revisaron %d sub-viewports y los cuatro presets tienen que dar al menos 8"
			% counted + " (FAST 1 + FAST 1 + FAST_WIDE 3 + FAST_WIDE 3)")
	expect(offenders.is_empty(),
			"hay viewports con oclusión activa o con el LOD desparejo: %s"
			% ", ".join(offenders))


## Los escalares por preset: emisores, escala de render y umbral de LOD.
func _check_preset_scalars() -> void:
	var emitters: Array[int] = []
	var scales: Array[float] = []
	for preset: Graphics.Quality in [Graphics.Quality.LOW, Graphics.Quality.MEDIUM,
			Graphics.Quality.HIGH, Graphics.Quality.ULTRA]:
		Graphics.apply_quality_preset(preset, false)
		Graphics.resolution_scale = 1.0
		emitters.append(Graphics.max_emitters())
		scales.append(snappedf(Graphics.fisheye_render_scale(), 0.01))
	expect(emitters == [6, 8, 12, 12],
			"max_emitters() es 6/8/12/12 (docs/13 §3.4 y §4), obtenido %s" % str(emitters))
	var wanted_scales: Array[float] = [0.70, 0.85, 1.0, 1.0]
	var scales_ok := scales.size() == wanted_scales.size()
	for index: int in wanted_scales.size():
		if scales_ok and not is_equal_approx(scales[index], wanted_scales[index]):
			scales_ok = false
	expect(scales_ok,
			"la escala de render es 70/85/100/100 %%, obtenido %s" % str(scales))
	_check_fisheye_presets()
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	expect(Graphics.fisheye_scaling_mode() == Viewport.SCALING_3D_MODE_BILINEAR,
			"a escala 1.0 no se paga el paso de FSR")
	Graphics.apply_quality_preset(Graphics.Quality.LOW, false)
	expect(Graphics.fisheye_scaling_mode() == Viewport.SCALING_3D_MODE_FSR,
			"por debajo de 1.0 el escalado es FSR 1.0 (docs/13 §3.4)")

	Graphics.mark_custom_quality()
	Graphics.shadows = Graphics.Shadows.ULTRA
	expect(Graphics.effective_quality() == Graphics.Quality.ULTRA,
			"con preset CUSTOM el efectivo se deduce del nivel de sombras")
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	print("  presets: emisores %s, escala de render %s" % [str(emitters), str(scales)])



# --- 4. Reconstrucción del `InputMap` ---------------------------------------------------------

func _check_input_map_rebuild() -> void:
	var actions := Controls.create_action_list()
	expect(actions.size() == 13, "create_action_list() devuelve las 13 acciones asignables")
	for action: ControllerAction in actions:
		expect(not action.label_key.is_empty(),
				"la acción %s tiene clave de etiqueta" % action.action_name)
		for locale: String in ["es", "en"]:
			var translation := TranslationServer.get_translation_object(locale)
			expect(translation != null
					and not String(translation.get_message(action.label_key)).is_empty(),
					"la clave %s tiene texto en '%s'" % [action.label_key, locale])

	Controls.save_axis_calibration(&"pitch", 3, -1.0, 0.0, 1.0, true)
	Controls.save_axis_calibration(&"throttle", 1, -1.0, 0.0, 1.0, false)
	expect(_motion_value(&"pitch_up") > 0.0 and _motion_value(&"pitch_down") < 0.0,
			"invertir pitch da vuelta el signo de sus dos acciones del InputMap")
	expect(_motion_value(&"throttle_up") < 0.0 and _motion_value(&"throttle_down") > 0.0,
			"sin inversión el acelerador conserva los signos de docs/02 §4.2")
	for axis_name: StringName in Controls.FLIGHT_AXES:
		var pair: Array = Controls.FLIGHT_AXIS_ACTIONS[axis_name]
		var wanted := int(Controls.get_axis_calibration(axis_name)["axis"])
		for entry: StringName in pair:
			expect(InputMap.has_action(entry), "el InputMap conserva la acción %s" % entry)
			expect(_motion_axis(entry) == wanted,
					"%s apunta al eje físico %d" % [entry, wanted])

	expect(_has_key_event(&"respawn", KEY_R),
			"reconstruir el InputMap no borra los atajos de teclado de docs/02 §4.3")
	expect(_joypad_event_count(&"toggle_arm") == 1,
			"cada acción asignable con botón por defecto queda con un único evento de joypad")
	expect(_joypad_event_count(&"arm") == 0,
			"`arm` (mantener) no tiene botón de joypad por defecto: es para un switch de radio")

	var before := _joypad_event_count(&"respawn") + _key_event_count(&"respawn")
	Controls.restore_keyboard_shortcuts()
	Controls.restore_keyboard_shortcuts()
	var after := _joypad_event_count(&"respawn") + _key_event_count(&"respawn")
	expect(after >= before, "restore_keyboard_shortcuts() no pierde eventos")
	expect(_key_event_count(&"respawn") <= 2,
			"restore_keyboard_shortcuts() es idempotente y no duplica teclas (quedaron %d)"
					% _key_event_count(&"respawn"))
	expect(_has_key_event(&"fire_alt", KEY_F) and _has_key_event(&"cycle_target", KEY_E),
			"restore_keyboard_shortcuts() deja los atajos de depuración puestos")


# --- 5. `get_flight_input()` ------------------------------------------------------------------

## Con ejes inyectados por el bucle de entrada, `get_flight_input()` aplica
## mín/centro/máx, inversión y zona muerta con reescalado.
func _check_flight_input() -> void:
	Controls.assume_joypad = true
	Controls.update_active_device(0)
	Controls.save_axis_calibration(&"throttle", 1, -1.0, -0.5, 1.0, false)
	Controls.save_axis_calibration(&"yaw", 0, -1.0, 0.0, 1.0, true)
	Controls.save_axis_calibration(&"roll", 2, -1.0, 0.0, 1.0, false)
	Controls.save_axis_calibration(&"pitch", 3, -1.0, 0.0, 1.0, false)

	await _inject_axes({1: 1.0, 0: 1.0, 2: 0.01, 3: 0.52})
	if not _injection_works(1, 1.0):
		fail("no se pudo inyectar el eje 1 con Input.parse_input_event()")
		return
	var input := Controls.get_flight_input()
	expect(input.size() == 4, "get_flight_input() devuelve los cuatro ejes de vuelo")
	expect_near(float(input["throttle"]), 1.0, 0.0001,
			"el acelerador al máximo da 1.0 con el centro calibrado en −0.5")
	expect_near(float(input["yaw"]), -1.0, 0.0001, "el yaw invertido da vuelta el signo")
	expect_near(float(input["roll"]), 0.0, 0.0001,
			"una deflexión de 0.01 cae dentro de la zona muerta de 0.02")
	expect_near(float(input["pitch"]), 0.5 / 0.98, 0.0001,
			"fuera de la zona muerta el recorrido restante se reescala a [0, 1]")

	await _inject_axes({1: -0.5, 0: 0.0, 2: -1.0, 3: -1.0})
	input = Controls.get_flight_input()
	expect_near(float(input["throttle"]), 0.0, 0.0001,
			"el acelerador en su centro calibrado da 0.0")
	expect_near(float(input["roll"]), -1.0, 0.0001, "el extremo negativo da −1.0")

	await _inject_axes({1: -1.0})
	input = Controls.get_flight_input()
	expect_near(float(input["throttle"]), -1.0, 0.0001,
			"por debajo del centro calibrado el recorrido corto también llega a −1.0")

	Controls.assume_joypad = false
	expect(Controls.get_flight_input().is_empty(),
			"sin mando, get_flight_input() devuelve un diccionario vacío")
	Controls.assume_joypad = true


# --- 6. Curvas de rates -----------------------------------------------------------------------

func _check_control_profile() -> void:
	var profile := ControlProfile.new()
	expect(profile.curve == ControlProfile.RateCurve.ACTUAL
			and profile.rc_rate.is_equal_approx(Vector3(7.0, 7.0, 7.0))
			and profile.rate.is_equal_approx(Vector3(67.0, 67.0, 67.0))
			and profile.expo.is_equal_approx(Vector3(54.0, 54.0, 54.0)),
			"el perfil por defecto es ACTUAL 7 / 67 / 54")

	for axis: int in 3:
		expect_near(profile.get_rate(axis, 1.0), 670.0, RATE_TOLERANCE,
				"ACTUAL 7/67/54 da 670 deg/s con el stick a fondo (eje %d)" % axis)
		# |x|·(x⁵·e + x·(1−e)) con x = 0.5 y e = 0.54 vale 0.1234375;
		# ω = 0.5·70 + 600·0.1234375 = 109.0625 deg/s.
		expect_near(profile.get_rate(axis, 0.5), 109.0625, RATE_TOLERANCE,
				"ACTUAL 7/67/54 da 109 deg/s a medio stick (eje %d)" % axis)
		expect_near(profile.get_rate(axis, 0.0), 0.0, 0.0001,
				"con el stick centrado la tasa es 0 (eje %d)" % axis)
		expect_near(profile.get_max_rate(axis), 670.0, RATE_TOLERANCE,
				"get_max_rate() coincide con el stick a fondo (eje %d)" % axis)
		expect_near(profile.get_normalized(axis, 1.0), 1.0, 0.0001,
				"get_normalized() vale 1.0 con el stick a fondo (eje %d)" % axis)

	# El stick a fondo pasado de rosca sigue acotado y la entrada también.
	expect_near(profile.get_rate(0, 4.0), 670.0, RATE_TOLERANCE,
			"la deflexión se acota a 1.0 antes de evaluar la curva")

	_check_curve_shape(profile, ControlProfile.RateCurve.ACTUAL, 7.0, 67.0, 54.0)
	for sample: Array in CURVE_SAMPLES:
		_check_curve_shape(profile, int(sample[0]) as ControlProfile.RateCurve,
				float(sample[1]), float(sample[2]), float(sample[3]))

	# Parámetros extremos: la salida se acota a ±1998 deg/s y sigue siendo finita.
	profile.curve = ControlProfile.RateCurve.BETAFLIGHT
	profile.rc_rate = Vector3(255.0, 255.0, 255.0)
	profile.rate = Vector3(100.0, 100.0, 100.0)
	profile.expo = Vector3(0.0, 0.0, 0.0)
	expect_near(profile.get_rate(0, 1.0), ControlProfile.MAX_RATE, 0.0001,
			"una curva desbocada se acota a 1998 deg/s")
	expect_near(profile.get_rate(0, -1.0), -ControlProfile.MAX_RATE, 0.0001,
			"el acotado también vale para el lado negativo")


## Comprueba que una curva es finita, impar, creciente en `[0, 1]` y acotada.
func _check_curve_shape(profile: ControlProfile, curve: ControlProfile.RateCurve,
		rc: float, rt: float, ex: float) -> void:
	profile.curve = curve
	profile.rc_rate = Vector3(rc, rc, rc)
	profile.rate = Vector3(rt, rt, rt)
	profile.expo = Vector3(ex, ex, ex)
	var label := "curva %d" % int(curve)
	for axis: int in 3:
		var previous := -1.0
		var steps := 50
		for step: int in steps + 1:
			var x := float(step) / float(steps)
			var value := profile.get_rate(axis, x)
			if not is_finite(value):
				fail("%s devuelve un valor no finito en x = %.2f" % [label, x])
				return
			if absf(value) > ControlProfile.MAX_RATE + 0.0001:
				fail("%s se pasa de 1998 deg/s en x = %.2f (%.2f)" % [label, x, value])
				return
			if value < previous - 0.0001:
				fail("%s no es creciente en x = %.2f (%.2f tras %.2f)"
						% [label, x, value, previous])
				return
			previous = value
			expect_near(profile.get_rate(axis, -x), -value, 0.0001,
					"%s es impar en x = %.2f" % [label, x])
	expect(profile.get_max_rate(0) > 0.0, "%s tiene una tasa máxima positiva" % label)


# --- Utilidades -------------------------------------------------------------------------------

## Manda al bucle de entrada un `InputEventJoypadMotion` por cada `{eje: valor}` y
## espera a que `Input` vacíe su buffer de eventos acumulados.
func _inject_axes(values: Dictionary) -> void:
	for axis: int in values:
		var motion := InputEventJoypadMotion.new()
		motion.device = 0
		motion.axis = axis as JoyAxis
		motion.axis_value = float(values[axis])
		Input.parse_input_event(motion)
	await wait_frames(3)


## Verdadero si la inyección llegó a `Input`; si no, el resto de la prueba de ejes
## no tiene sentido y conviene decirlo con claridad en vez de reportar diferencias.
func _injection_works(axis: int, expected: float) -> bool:
	return absf(Input.get_joy_axis(0, axis as JoyAxis) - expected) < 0.001


## `axis_value` del primer evento de joypad de una acción; 0.0 si no tiene ninguno.
func _motion_value(action: StringName) -> float:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return (event as InputEventJoypadMotion).axis_value
	return 0.0


## Índice de eje del primer evento de joypad de una acción; −1 si no tiene ninguno.
func _motion_axis(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return int((event as InputEventJoypadMotion).axis)
	return -1


func _joypad_event_count(action: StringName) -> int:
	var count := 0
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion or event is InputEventJoypadButton:
			count += 1
	return count


func _key_event_count(action: StringName) -> int:
	var count := 0
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			count += 1
	return count


func _has_key_event(action: StringName, code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false


func _write_garbage(file_name: String) -> void:
	var file := FileAccess.open(Global.config_path(file_name), FileAccess.WRITE)
	if file == null:
		fail("no se pudo escribir el archivo corrupto %s" % file_name)
		return
	file.store_string(GARBAGE)
	file.close()


## Borra todo lo que haya en el directorio temporal: los `.cfg` y el log que
## [method _run] desvió hasta ahí.
func _clear_temp_files() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		return
	for file_name: String in DirAccess.get_files_at(TEMP_DIR):
		var _discard := DirAccess.remove_absolute(TEMP_DIR.path_join(file_name))


func _purge_temp() -> void:
	_clear_temp_files()
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		var _discard := DirAccess.remove_absolute(TEMP_DIR)


## Archivos `.cfg` del directorio real del jugador, para comprobar que la prueba
## no los tocó.
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


## Idempotente: la llama [method finish], que a su vez puede llegar por el timeout.
func _restore_environment() -> void:
	if _restored:
		return
	_restored = true
	Controls.assume_joypad = false
	Engine.max_fps = 0
	_purge_temp()
	if not _saved_player_log_path.is_empty():
		Global.log_path = _saved_player_log_path
	if not _saved_player_config_dir.is_empty():
		Global.config_dir = _saved_player_config_dir
	if not _original_locale.is_empty():
		TranslationServer.set_locale(_original_locale)
	Global.startup_errors.clear()
