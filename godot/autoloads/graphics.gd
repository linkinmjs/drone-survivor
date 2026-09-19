## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Modo de ventana, escala de resolución, vsync, fps máximo, preset de calidad,
## MSAA, sombras y ojo de pez, persistidos en `Graphics.cfg` (`docs/04` §3.5).
##
## Es seguro en `--headless`: con el `DisplayServer` sin ventana se guarda el estado
## pero no se tocan ni el modo de ventana ni el vsync, de modo que los checks de CI
## pueden ejercitar la carga y el guardado sin reventar.
extends Node

## Se emite después de guardar; el menú de gráficos rehace sus controles.
signal graphics_settings_updated

## Se emite cuando cambia algo del ojo de pez. Lo escucha `FPVCamera` (`docs/03` §5).
signal fisheye_changed

## Se emite cuando cambia algo que afecta al `Environment` del nivel. Lo escucha el
## `WorldEnvironment`, que vuelve a llamar a [method apply_environment_quality].
signal environment_quality_changed

## Nombre del archivo dentro de `Global.config_dir`.
const CONFIG_FILE: String = "Graphics.cfg"

## Única sección del archivo.
const SECTION: String = "graphics"

## Clave de traducción que `Global.startup_errors` acumula si el archivo está roto.
const ERROR_KEY: String = "ERR_CONFIG_GRAPHICS"

## Modo de la ventana principal.
enum WindowMode {FULLSCREEN, WINDOW, BORDERLESS}

## Muestras de antialiasing 3D.
enum Msaa {OFF, X2, X4, X8}

## Calidad de las sombras direccionales.
enum Shadows {VERY_LOW, LOW, MEDIUM, HIGH, ULTRA}

## Modo del ojo de pez de la cámara FPV (`docs/03` §5).
enum FisheyeMode {OFF, FULL, FAST}

## Resolución de las sub-viewports del ojo de pez.
enum FisheyeResolution {P2160, P1440, P1080, P720, P480, P240}

## MSAA de las sub-viewports del ojo de pez; [constant FisheyeMsaa.SAME_AS_GAME]
## copia el valor de [member msaa].
enum FisheyeMsaa {OFF, X2, X4, X8, SAME_AS_GAME}

## Sincronización vertical.
enum VSync {OFF, ON, ADAPTIVE}

## Preset de calidad. [constant Quality.CUSTOM] es lo que queda cuando el jugador
## toca un control suelto del menú.
enum Quality {LOW, MEDIUM, HIGH, ULTRA, CUSTOM}

## Iluminación global.
enum Gi {OFF, SDFGI}

## Valores que fija cada preset de calidad (`docs/04` §3.5).
const QUALITY_PRESETS: Dictionary[int, Dictionary] = {
	Quality.LOW: {
		"msaa": Msaa.OFF, "shadows": Shadows.LOW, "gi": Gi.OFF,
		"volumetric_fog": false, "ssao": false,
		"fisheye_mode": FisheyeMode.FAST, "fisheye_resolution": FisheyeResolution.P480,
	},
	Quality.MEDIUM: {
		"msaa": Msaa.X2, "shadows": Shadows.MEDIUM, "gi": Gi.OFF,
		"volumetric_fog": true, "ssao": false,
		"fisheye_mode": FisheyeMode.FAST, "fisheye_resolution": FisheyeResolution.P720,
	},
	Quality.HIGH: {
		"msaa": Msaa.X4, "shadows": Shadows.HIGH, "gi": Gi.SDFGI,
		"volumetric_fog": true, "ssao": true,
		"fisheye_mode": FisheyeMode.FAST, "fisheye_resolution": FisheyeResolution.P1080,
	},
	Quality.ULTRA: {
		"msaa": Msaa.X8, "shadows": Shadows.ULTRA, "gi": Gi.SDFGI,
		"volumetric_fog": true, "ssao": true,
		"fisheye_mode": FisheyeMode.FULL, "fisheye_resolution": FisheyeResolution.P1080,
	},
}

## Escalas de resolución 3D admitidas.
const RESOLUTION_SCALES: Array[float] = [1.0, 0.75, 0.5]

## Topes de fps admitidos; 0 es «sin límite».
const MAX_FPS_VALUES: Array[int] = [0, 30, 60, 120, 144, 240]

## Tamaño del atlas de sombras direccionales por nivel de [enum Shadows].
const SHADOW_ATLAS_SIZES: Array[int] = [2048, 4096, 8192, 8192, 16384]

## Filtro de sombra suave por nivel de [enum Shadows]: `HARD`, `SOFT_LOW`,
## `SOFT_MEDIUM`, `SOFT_HIGH`, `SOFT_ULTRA` (`docs/04` §3.5). No es la identidad:
## `RenderingServer` intercala `SOFT_VERY_LOW` en el índice 1.
const SHADOW_FILTERS: Array[int] = [
	RenderingServer.SHADOW_QUALITY_HARD,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
	RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
]

## Alto en píxeles de cada [enum FisheyeResolution].
const FISHEYE_HEIGHTS: Array[int] = [2160, 1440, 1080, 720, 480, 240]

## Modo de ventana persistido.
var window_mode: WindowMode = WindowMode.FULLSCREEN

## Escala de render 3D: 1.0, 0.75 o 0.5.
var resolution_scale: float = 1.0

## Sincronización vertical persistida.
var vsync: VSync = VSync.ON

## Tope de fps; 0 es sin límite.
var max_fps: int = 0

## Preset de calidad activo.
var quality: Quality = Quality.HIGH

## Muestras de MSAA 3D.
var msaa: Msaa = Msaa.X4

## Calidad de las sombras direccionales.
var shadows: Shadows = Shadows.HIGH

## Iluminación global del nivel.
var gi: Gi = Gi.SDFGI

## Niebla volumétrica del nivel.
var volumetric_fog: bool = true

## Oclusión ambiental del nivel.
var ssao: bool = true

## Modo del ojo de pez.
var fisheye_mode: FisheyeMode = FisheyeMode.FAST

## Resolución de las sub-viewports del ojo de pez.
var fisheye_resolution: FisheyeResolution = FisheyeResolution.P1080

## MSAA de las sub-viewports del ojo de pez.
var fisheye_msaa: FisheyeMsaa = FisheyeMsaa.SAME_AS_GAME


## Lee `Graphics.cfg` y aplica todo.
##
## Devuelve `""` si todo fue bien —el archivo ausente no es error y solo escribe los
## valores por defecto— o [constant ERROR_KEY] si está corrupto, en cuyo caso se
## vuelve a los valores por defecto y se reescribe (`docs/04` §2).
func load_graphics_settings() -> String:
	Global.initialize()
	reset_to_defaults()
	var path := Global.config_path(CONFIG_FILE)
	var config := ConfigFile.new()
	var err := config.load(path)
	if err == ERR_FILE_NOT_FOUND:
		save_graphics_settings()
		return ""
	if err != OK:
		Global.log_error(err, "no se pudo leer %s: %s" % [path, error_string(err)])
		save_graphics_settings()
		return ERROR_KEY
	window_mode = _read_enum(config, "window_mode", WindowMode.size(), int(window_mode)) as WindowMode
	resolution_scale = _read_choice(config, "resolution_scale", RESOLUTION_SCALES, resolution_scale)
	vsync = _read_enum(config, "vsync", VSync.size(), int(vsync)) as VSync
	max_fps = _read_int_choice(config, "max_fps", MAX_FPS_VALUES, max_fps)
	quality = _read_enum(config, "quality", Quality.size(), int(quality)) as Quality
	msaa = _read_enum(config, "msaa", Msaa.size(), int(msaa)) as Msaa
	shadows = _read_enum(config, "shadows", Shadows.size(), int(shadows)) as Shadows
	gi = _read_enum(config, "gi", Gi.size(), int(gi)) as Gi
	volumetric_fog = bool(config.get_value(SECTION, "volumetric_fog", volumetric_fog))
	ssao = bool(config.get_value(SECTION, "ssao", ssao))
	fisheye_mode = _read_enum(config, "fisheye_mode", FisheyeMode.size(),
			int(fisheye_mode)) as FisheyeMode
	fisheye_resolution = _read_enum(config, "fisheye_resolution", FisheyeResolution.size(),
			int(fisheye_resolution)) as FisheyeResolution
	fisheye_msaa = _read_enum(config, "fisheye_msaa", FisheyeMsaa.size(),
			int(fisheye_msaa)) as FisheyeMsaa
	apply_all()
	return ""


## Escribe `Graphics.cfg`, aplica todo y emite las tres señales.
func save_graphics_settings() -> void:
	Global.initialize()
	var config := ConfigFile.new()
	config.set_value(SECTION, "window_mode", int(window_mode))
	config.set_value(SECTION, "resolution_scale", resolution_scale)
	config.set_value(SECTION, "vsync", int(vsync))
	config.set_value(SECTION, "max_fps", max_fps)
	config.set_value(SECTION, "quality", int(quality))
	config.set_value(SECTION, "msaa", int(msaa))
	config.set_value(SECTION, "shadows", int(shadows))
	config.set_value(SECTION, "gi", int(gi))
	config.set_value(SECTION, "volumetric_fog", volumetric_fog)
	config.set_value(SECTION, "ssao", ssao)
	config.set_value(SECTION, "fisheye_mode", int(fisheye_mode))
	config.set_value(SECTION, "fisheye_resolution", int(fisheye_resolution))
	config.set_value(SECTION, "fisheye_msaa", int(fisheye_msaa))
	var path := Global.config_path(CONFIG_FILE)
	var err := config.save(path)
	if err != OK:
		Global.log_error(err, "no se pudo guardar %s: %s" % [path, error_string(err)])
	# `apply_all()` ya emite `fisheye_changed` a través de `update_fisheye()`.
	apply_all()
	graphics_settings_updated.emit()
	environment_quality_changed.emit()


## Deja todos los valores en los de primer arranque: preset HIGH, pantalla completa,
## vsync encendido y sin tope de fps (`docs/04` §3.5).
func reset_to_defaults() -> void:
	window_mode = WindowMode.FULLSCREEN
	resolution_scale = 1.0
	vsync = VSync.ON
	max_fps = 0
	fisheye_msaa = FisheyeMsaa.SAME_AS_GAME
	apply_quality_preset(Quality.HIGH, false)


## Aplica de una sola vez todo lo que depende de la configuración.
func apply_all() -> void:
	update_window_mode()
	update_resolution_scale()
	update_vsync()
	update_max_fps()
	update_msaa()
	update_shadows()
	update_fisheye()


## Pone la ventana principal en el modo elegido. No hace nada en `--headless`.
func update_window_mode() -> void:
	if is_headless():
		return
	match window_mode:
		WindowMode.WINDOW:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Aplica la escala de render 3D sobre el viewport raíz.
func update_resolution_scale() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.scaling_3d_scale = resolution_scale


## Aplica la sincronización vertical. No hace nada en `--headless`.
func update_vsync() -> void:
	if is_headless():
		return
	match vsync:
		VSync.OFF:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSync.ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


## Aplica el tope de fps. `Engine.max_fps = 0` significa sin límite.
func update_max_fps() -> void:
	Engine.max_fps = maxi(max_fps, 0)


## Aplica el MSAA 3D sobre el viewport raíz.
func update_msaa() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.msaa_3d = msaa_to_viewport(int(msaa))


## Aplica tamaño de atlas y filtro de las sombras direccionales (`docs/04` §3.5).
func update_shadows() -> void:
	var level := clampi(int(shadows), 0, SHADOW_ATLAS_SIZES.size() - 1)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZES[level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
			SHADOW_FILTERS[level] as RenderingServer.ShadowQuality)


## Avisa a la cámara FPV de que el ojo de pez cambió (`docs/03` §5).
func update_fisheye() -> void:
	fisheye_changed.emit()


## Vuelca el preset [param preset] sobre los valores sueltos. Con [param persist]
## en `true` guarda y avisa; el menú de gráficos lo llama así.
func apply_quality_preset(preset: Quality, persist: bool = true) -> void:
	quality = preset
	var values: Dictionary = QUALITY_PRESETS.get(int(preset), {})
	if not values.is_empty():
		msaa = int(values["msaa"]) as Msaa
		shadows = int(values["shadows"]) as Shadows
		gi = int(values["gi"]) as Gi
		volumetric_fog = bool(values["volumetric_fog"])
		ssao = bool(values["ssao"])
		fisheye_mode = int(values["fisheye_mode"]) as FisheyeMode
		fisheye_resolution = int(values["fisheye_resolution"]) as FisheyeResolution
	if persist:
		save_graphics_settings()


## Marca la calidad como personalizada. Lo llama el menú de gráficos en cuanto el
## jugador toca un control suelto (`docs/04` §4.3).
func mark_custom_quality() -> void:
	quality = Quality.CUSTOM


## Ajusta el `Environment` del nivel a la calidad elegida. La llama el
## `WorldEnvironment` en su `_ready()` y cada vez que suena
## [signal environment_quality_changed].
func apply_environment_quality(env: Environment) -> void:
	if env == null:
		return
	env.sdfgi_enabled = gi == Gi.SDFGI
	env.volumetric_fog_enabled = volumetric_fog
	env.ssao_enabled = ssao


## Alto en píxeles de las sub-viewports del ojo de pez.
func fisheye_height() -> int:
	var index := clampi(int(fisheye_resolution), 0, FISHEYE_HEIGHTS.size() - 1)
	return FISHEYE_HEIGHTS[index]


## MSAA efectivo del ojo de pez, ya resuelto el caso «igual que el juego».
func fisheye_msaa_level() -> Viewport.MSAA:
	if fisheye_msaa == FisheyeMsaa.SAME_AS_GAME:
		return msaa_to_viewport(int(msaa))
	return msaa_to_viewport(int(fisheye_msaa))


## Traduce un nivel de [enum Msaa] al valor del viewport.
func msaa_to_viewport(level: int) -> Viewport.MSAA:
	match clampi(level, 0, 3):
		1:
			return Viewport.MSAA_2X
		2:
			return Viewport.MSAA_4X
		3:
			return Viewport.MSAA_8X
		_:
			return Viewport.MSAA_DISABLED


## Verdadero si el proyecto corre con el renderer de compatibilidad, donde no hay
## SDFGI ni niebla volumétrica y el menú de gráficos deshabilita esas opciones.
func is_compatibility_renderer() -> bool:
	var method := String(ProjectSettings.get_setting(
			"rendering/renderer/rendering_method", "forward_plus"))
	return method == "gl_compatibility"


## Verdadero cuando no hay ventana real: `--headless` o un servidor dedicado.
func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


# --- Lectura defensiva del `.cfg` ------------------------------------------------------------

## Lee un entero de enumeración y lo acota al rango válido.
func _read_enum(config: ConfigFile, key: String, count: int, fallback: int) -> int:
	return clampi(int(config.get_value(SECTION, key, fallback)), 0, count - 1)


## Lee un float que solo admite unos pocos valores; si no es ninguno, deja el actual.
func _read_choice(config: ConfigFile, key: String, allowed: Array[float],
		fallback: float) -> float:
	var stored := float(config.get_value(SECTION, key, fallback))
	for value: float in allowed:
		if is_equal_approx(value, stored):
			return value
	return fallback


## Ídem para enteros.
func _read_int_choice(config: ConfigFile, key: String, allowed: Array[int],
		fallback: int) -> int:
	var stored := int(config.get_value(SECTION, key, fallback))
	return stored if allowed.has(stored) else fallback
