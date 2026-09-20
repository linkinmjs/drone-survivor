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

## Se emite cuando cambian las sombras direccionales. Los soles dados de alta con
## [method register_sun] ya se reajustaron cuando suena; la escuchan los checks y
## cualquiera que tenga una luz propia que no haya registrado.
signal shadows_changed

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
##
## [constant FisheyeMode.FAST_WIDE] va **al final** a propósito: los tres primeros
## valores son los que ya escribió `Graphics.cfg` en las máquinas de los jugadores, y
## [method _read_enum] sólo acota al rango, así que un archivo viejo sigue leyéndose
## igual. Cambiar el orden para dejarlos "ordenados por costo" reinterpretaría cada
## `.cfg` existente.
enum FisheyeMode {OFF, FULL, FAST, FAST_WIDE}

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

## Variante de iluminación indirecta del plan A/B de `docs/13` §3.5.
##
## [constant GiVariant.A_SDFGI] es la de fábrica: SDFGI con realimentación de rebote.
## [constant GiVariant.B_AMBIENT_SSIL] es el respaldo por si el popping al colapsar
## edificios molesta (riesgo 1 de `docs/13` §11): SDFGI apagado, ambiente de color,
## SSIL encendido y el máximo de [ReflectionProbe].
##
## **No se persiste**: es una palanca de comparación, y la elección definitiva la
## toma el usuario en el checkpoint 4 mirando las capturas. El día que se decida, el
## ganador se hornea en [constant QUALITY_PRESETS] y esta bandera desaparece.
enum GiVariant {A_SDFGI, B_AMBIENT_SSIL}

## Operador de tonemap del A/B de `docs/13` §11 #3. AgX conserva el hue de los
## emisivos saturados; ACES los desplaza al blanco-rosado pero da una imagen más
## contrastada, y se compensa con algo más de saturación en los ajustes. Tampoco se
## persiste, por lo mismo que [enum GiVariant].
enum Tonemap {AGX, ACES}

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
		"fisheye_mode": FisheyeMode.FAST_WIDE, "fisheye_resolution": FisheyeResolution.P1080,
	},
	Quality.ULTRA: {
		"msaa": Msaa.X8, "shadows": Shadows.ULTRA, "gi": Gi.SDFGI,
		"volumetric_fog": true, "ssao": true,
		"fisheye_mode": FisheyeMode.FAST_WIDE, "fisheye_resolution": FisheyeResolution.P1080,
	},
}

## Escalas de resolución 3D admitidas.
const RESOLUTION_SCALES: Array[float] = [1.0, 0.75, 0.5]

## Topes de fps admitidos; 0 es «sin límite».
const MAX_FPS_VALUES: Array[int] = [0, 30, 60, 120, 144, 240]

## Tamaño del atlas de sombras direccionales por nivel de [enum Shadows]
## (`docs/13` §3.4). **No** es la tabla de `docs/04` §3.5, que pedía
## `2048/4096/8192/8192/16384`: un atlas de 16 k cuesta 1 GB de VRAM y no se ve, y
## el documento de identidad visual es el que manda sobre los presets (WP-24a).
const SHADOW_ATLAS_SIZES: Array[int] = [2048, 2048, 4096, 8192, 8192]

## Cantidad de cascadas paralelas por nivel de [enum Shadows] (`docs/13` §3.4).
const SHADOW_SPLIT_COUNTS: Array[int] = [2, 2, 4, 4, 4]

## Alcance de la sombra direccional en metros, por nivel de [enum Shadows].
## El valor cableado en las escenas era 700 m: con 4 cascadas eso deja la cascada
## más fina cubriendo 42 m y la ciudad entera con sombra de un texel por metro.
const SHADOW_DISTANCES: Array[float] = [120.0, 120.0, 200.0, 320.0, 420.0]

## Primer corte de cascada por nivel de [enum Shadows]: más lejos con dos splits,
## porque ahí la primera cascada tiene que cubrir sola casi todo lo cercano.
const SHADOW_SPLIT_1: Array[float] = [0.20, 0.20, 0.06, 0.06, 0.06]

## Segundo y tercer corte de cascada, sólo con cuatro splits (`docs/13` §3.2).
const SHADOW_SPLIT_2: float = 0.16
const SHADOW_SPLIT_3: float = 0.40

## Dónde empieza el desvanecido de la sombra, en fracción del alcance (`docs/13` §3.2).
const SHADOW_FADE_START: float = 0.85

## Sesgos de la sombra direccional (`docs/13` §3.2). El normal es alto porque los
## voxels de la ciudad son grandes y planos.
const SHADOW_NORMAL_BIAS: float = 1.6
const SHADOW_BIAS: float = 0.06

## Filtro de sombra suave por nivel de [enum Shadows]: `HARD`, `SOFT_LOW`,
## `SOFT_LOW`, `SOFT_MEDIUM`, `SOFT_HIGH` (`docs/13` §3.4). No es la identidad:
## `RenderingServer` intercala `SOFT_VERY_LOW` en el índice 1, y el índice 3
## (HIGH) es `SOFT_MEDIUM`, no `SOFT_HIGH` como decía `docs/04` §3.5.
const SHADOW_FILTERS: Array[int] = [
	RenderingServer.SHADOW_QUALITY_HARD,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
]

## Escala de render 3D por preset de calidad (`docs/13` §3.4). Va sobre las
## `SubViewport` del ojo de pez, que es donde se dibuja la escena: la raíz no
## dibuja nada mientras el compuesto está al mando.
const PRESET_RENDER_SCALES: Array[float] = [0.70, 0.85, 1.0, 1.0]

## Emisores de partículas simultáneos por preset (`docs/13` §3.4 y §4).
const PRESET_MAX_EMITTERS: Array[int] = [6, 8, 12, 12]

## `mesh_lod_threshold` en píxeles por preset: cuánto tiene que medir en pantalla
## un LOD para que se dibuje. 1.0 es el valor por defecto del motor.
const PRESET_MESH_LOD: Array[float] = [4.0, 2.0, 1.0, 1.0]

## Largo de la niebla volumétrica en metros por preset (`docs/13` §3.1 y §3.4).
## El `.tres` traía 256 m, que es más del doble de lo que pide el documento.
const PRESET_FOG_LENGTHS: Array[float] = [96.0, 96.0, 96.0, 128.0]

## Lado y profundidad del froxel de niebla volumétrica por preset
## ([method RenderingServer.environment_set_volumetric_fog_volume_size]).
const PRESET_FOG_VOLUME: Array[int] = [32, 32, 64, 96]
const PRESET_FOG_DEPTH: Array[int] = [32, 32, 64, 96]

## Cascadas de SDFGI por preset (`docs/13` §3.4). En Godot 4.7
## `Environment.sdfgi_cascades` es un entero de 1 a 8 —no la enumeración de
## 4/6/8 de versiones anteriores—, así que las cinco cascadas de ULTRA se pueden
## pedir tal cual. Con `cascade0` de 16 m, cuatro cascadas cubren 128 m y cinco
## cubren 256 m, que es la cifra que da el documento.
const SDFGI_CASCADES_HIGH: int = 4
const SDFGI_CASCADES_ULTRA: int = 5

## Alcance de la cascada 0 de SDFGI, en metros (`docs/13` §3.1).
const SDFGI_CASCADE0_DISTANCE: float = 16.0

## Realimentación de rebote y sesgos de SDFGI (`docs/13` §3.1).
const SDFGI_BOUNCE_FEEDBACK: float = 0.5
const SDFGI_NORMAL_BIAS: float = 1.1
const SDFGI_PROBE_BIAS: float = 1.1

## Ambiente de respaldo cuando SDFGI queda apagado (`docs/13` §3.4 y §3.5 B).
const FALLBACK_AMBIENT_COLOR: Color = Color(0.16470589, 0.22745098, 0.32156864)
const FALLBACK_AMBIENT_ENERGY: float = 0.55

## Radio de SSAO en MEDIUM y en el resto de los presets (`docs/13` §3.1 y §3.4).
const SSAO_RADIUS_MEDIUM: float = 1.2
const SSAO_RADIUS: float = 1.6

## SSIL, sólo en ULTRA (`docs/13` §3.1).
const SSIL_RADIUS: float = 4.0
const SSIL_INTENSITY: float = 1.0

## Niveles de glow que sobreviven en LOW (`docs/13` §3.4): sólo los tres del medio.
const GLOW_LEVELS_LOW: Array[int] = [3, 4, 5]

## [ReflectionProbe] locales por preset (`docs/13` §3.3 y §3.4). Los crea el nivel
## en tiempo de ejecución sobre puntos que le pide a [CityGrid], para no hornearlos
## en `district_a.tscn`.
const PRESET_REFLECTION_PROBES: Array[int] = [0, 2, 4, 6]

## Saturación de los ajustes de color por operador de tonemap (`docs/13` §3.1 y
## §11 #3). ACES desatura menos que AgX en las sombras pero comprime más el color
## de los emisivos, así que se le sube la saturación un punto más.
const TONEMAP_SATURATION_AGX: float = 1.06
const TONEMAP_SATURATION_ACES: float = 1.12

## Punto blanco de cada operador. AgX tiene el suyo propio (`tonemap_agx_white`);
## `tonemap_white` sólo lo leen Reinhardt, Filmic y ACES.
const TONEMAP_ACES_WHITE: float = 2.0

## Perfil de sol de la identidad visual (`docs/13` §3.2). [method register_sun] se
## lo aplica a las luces que no traen el suyo, de modo que un showcase que registre
## su sol quede iluminado como el juego sin tener que cambiar su escena.
const SUN_PROFILE_PATH: String = "res://world/sun_dusk.tres"

## Alto en píxeles de cada [enum FisheyeResolution].
const FISHEYE_HEIGHTS: Array[int] = [2160, 1440, 1080, 720, 480, 240]

## Proporción del alto frontal que reciben las caras laterales de
## [constant FisheyeMode.FAST_WIDE], por preset (`docs/03` §5).
##
## Las laterales viven en la periferia del círculo, donde la proyección equidistante
## **magnifica**: una cara cuadrada de 100° a 720 px da como mucho 1,0 texels por
## píxel de salida sobre una pantalla de 1920, así que dos tercios del alto frontal
## alcanzan y sobran hasta HIGH. ULTRA las lleva a 1 —1080² con la frontal a 1080p—,
## que es nitidez que el borde del cuadro ya no puede mostrar pero que ULTRA puede
## pagar: es el preset que hasta WP-24c gastaba cinco viewports en FULL.
const PRESET_FISHEYE_SIDE_RATIO: Array[float] = [2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1.0]

## Lado mínimo y máximo de una cara lateral, en píxeles.
const FISHEYE_SIDE_RANGE: Vector2i = Vector2i(360, 1080)

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

## Variante de iluminación indirecta activa (`docs/13` §3.5). No se persiste.
var gi_variant: GiVariant = GiVariant.A_SDFGI

## Operador de tonemap activo (`docs/13` §11 #3). No se persiste.
var tonemap: Tonemap = Tonemap.AGX

## Soles de los niveles y showcases vivos, dados de alta con [method register_sun].
var _suns: Array[DirectionalLight3D] = []

## Perfil de sol cargado a demanda por [method default_sun_profile].
var _sun_profile: SunProfile = null


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
	update_mesh_lod()
	update_volumetric_fog_volume()
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


## Aplica la escala de render 3D sobre el viewport raíz y avisa al ojo de pez.
##
## La raíz casi no dibuja nada mientras el compuesto del ojo de pez está al mando
## (`docs/03` §5), así que la escala que de verdad importa es la de las
## `SubViewport`: la aplica [FPVCamera] leyendo [method fisheye_render_scale] en
## cuanto suena [signal fisheye_changed].
func update_resolution_scale() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.scaling_3d_scale = resolution_scale
	fisheye_changed.emit()


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


## Aplica tamaño de atlas y filtro de las sombras direccionales, y vuelca la tabla
## de `docs/13` §3.4 sobre cada sol dado de alta con [method register_sun].
func update_shadows() -> void:
	var level := clampi(int(shadows), 0, SHADOW_ATLAS_SIZES.size() - 1)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZES[level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
			SHADOW_FILTERS[level] as RenderingServer.ShadowQuality)
	_prune_suns()
	for light: DirectionalLight3D in _suns:
		apply_sun_quality(light)
	shadows_changed.emit()


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


## Ajusta el `Environment` del nivel a la calidad elegida (`docs/13` §3.4). La
## llama el `WorldEnvironment` en su `_ready()` y cada vez que suena
## [signal environment_quality_changed].
##
## El `Environment` que recibe es el **clon por nivel** que hace `LevelBase._ready()`:
## escribir sobre el `world/environment_battle.tres` compartido dejaría el recurso
## mutado en memoria para el nivel siguiente y para el editor, y un check que
## corriera en LOW ensuciaría al que corriera después.
##
## Lo que toca, en el orden del documento: SDFGI y su ambiente de respaldo, SSIL,
## SSAO, niebla volumétrica, glow y el operador de tonemap del A/B. Lo que **no**
## toca —cielo, exposición, niebla de profundidad, LUT— es identidad visual y lo
## fija el `.tres` que escribe `tools/build_environment.gd`.
func apply_environment_quality(env: Environment) -> void:
	if env == null:
		return
	_apply_sdfgi(env)
	_apply_ssil(env)
	_apply_ssao(env)
	_apply_volumetric_fog(env)
	_apply_glow(env)
	_apply_tonemap(env)


## SDFGI y, cuando queda apagado, el ambiente de color de respaldo `#2A3A52` a
## 0.55 (`docs/13` §3.4 y variante B de §3.5). Sin ese respaldo, apagar SDFGI en
## LOW deja la ciudad a oscuras en vez de barata.
func _apply_sdfgi(env: Environment) -> void:
	var wanted := gi == Gi.SDFGI and not is_compatibility_renderer() \
			and gi_variant == GiVariant.A_SDFGI
	env.sdfgi_enabled = wanted
	if wanted:
		if effective_quality() == Quality.ULTRA:
			env.sdfgi_cascades = SDFGI_CASCADES_ULTRA
		else:
			env.sdfgi_cascades = SDFGI_CASCADES_HIGH
		env.sdfgi_cascade0_distance = SDFGI_CASCADE0_DISTANCE
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_100_PERCENT
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = SDFGI_BOUNCE_FEEDBACK
		env.sdfgi_read_sky_light = true
		env.sdfgi_energy = 1.0
		env.sdfgi_normal_bias = SDFGI_NORMAL_BIAS
		env.sdfgi_probe_bias = SDFGI_PROBE_BIAS
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0
		return
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = FALLBACK_AMBIENT_COLOR
	env.ambient_light_energy = FALLBACK_AMBIENT_ENERGY


## SSIL: en ULTRA (`docs/13` §3.4) y en la variante B de §3.5, donde es el rebote
## de respaldo que reemplaza a SDFGI.
func _apply_ssil(env: Environment) -> void:
	env.ssil_enabled = effective_quality() == Quality.ULTRA \
			or (gi_variant == GiVariant.B_AMBIENT_SSIL and gi == Gi.SDFGI)
	if env.ssil_enabled:
		env.ssil_radius = SSIL_RADIUS
		env.ssil_intensity = SSIL_INTENSITY


## SSAO, con el radio corto de MEDIUM (`docs/13` §3.4).
func _apply_ssao(env: Environment) -> void:
	env.ssao_enabled = ssao
	if not ssao:
		return
	if effective_quality() == Quality.MEDIUM:
		env.ssao_radius = SSAO_RADIUS_MEDIUM
	else:
		env.ssao_radius = SSAO_RADIUS


## Niebla volumétrica: encendido y largo por preset (`docs/13` §3.1 y §3.4).
func _apply_volumetric_fog(env: Environment) -> void:
	env.volumetric_fog_enabled = volumetric_fog and not is_compatibility_renderer()
	if env.volumetric_fog_enabled:
		env.volumetric_fog_length = PRESET_FOG_LENGTHS[_preset_index()]


## Glow: en LOW sobreviven sólo los niveles 3–5 (`docs/13` §3.4). Si el
## `Environment` todavía no trae glow —el `.tres` de WP-24 aún no lo tiene— no se
## enciende nada: el look lo define el recurso, este autoload sólo lo recorta.
func _apply_glow(env: Environment) -> void:
	if not env.glow_enabled or effective_quality() != Quality.LOW:
		return
	for level: int in range(1, 8):
		if not GLOW_LEVELS_LOW.has(level):
			env.set("glow_levels/%d" % level, 0.0)


## Operador de tonemap y la saturación que lo acompaña (`docs/13` §11 #3).
##
## El resto de la cadena de color —exposición, punto blanco de AgX, contraste,
## brillo— lo fija el `.tres`: acá sólo se cambia de operador para el A/B.
func _apply_tonemap(env: Environment) -> void:
	if tonemap == Tonemap.ACES:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = TONEMAP_ACES_WHITE
		env.adjustment_saturation = TONEMAP_SATURATION_ACES
		return
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.adjustment_saturation = TONEMAP_SATURATION_AGX


## Cuántos [ReflectionProbe] locales pide el preset activo (`docs/13` §3.3).
##
## La variante B de §3.5 sube a seis: sin SDFGI, los probes son el único reflejo
## local que queda. **Salvo en LOW**, donde el preset pide cero justamente porque
## ahí no se paga iluminación indirecta de ningún tipo; la variante es una
## alternativa a SDFGI, no una forma de colarla en la máquina más floja.
func reflection_probe_count() -> int:
	var preset_count := PRESET_REFLECTION_PROBES[_preset_index()]
	if gi_variant == GiVariant.B_AMBIENT_SSIL and preset_count > 0:
		return PRESET_REFLECTION_PROBES[PRESET_REFLECTION_PROBES.size() - 1]
	return preset_count


## El [SunProfile] de la identidad visual, cargado una sola vez. Devuelve `null` si
## el recurso todavía no existe, que es lo que pasa en un repositorio a medio
## actualizar: sin perfil, cada escena se queda con la luz que traiga.
func default_sun_profile() -> SunProfile:
	if _sun_profile != null:
		return _sun_profile
	if not ResourceLoader.exists(SUN_PROFILE_PATH):
		return null
	_sun_profile = load(SUN_PROFILE_PATH) as SunProfile
	return _sun_profile


## Preset efectivo para lo que no tiene ajuste suelto propio —escala de render,
## emisores, LOD, largo de niebla—. Con [constant Quality.CUSTOM] se deduce del
## nivel de sombras, que es el ajuste suelto que mejor correlaciona con la
## potencia de la máquina.
func effective_quality() -> Quality:
	if quality != Quality.CUSTOM:
		return quality
	match shadows:
		Shadows.VERY_LOW, Shadows.LOW:
			return Quality.LOW
		Shadows.MEDIUM:
			return Quality.MEDIUM
		Shadows.ULTRA:
			return Quality.ULTRA
		_:
			return Quality.HIGH


## Índice 0–3 de [method effective_quality] para indexar las tablas por preset.
func _preset_index() -> int:
	return clampi(int(effective_quality()), 0, PRESET_RENDER_SCALES.size() - 1)


## Emisores de partículas simultáneos que admite el preset activo (`docs/13` §4).
## Lo consumirá el `VFXPool` de WP-26; hoy nadie lo lee todavía.
func max_emitters() -> int:
	return PRESET_MAX_EMITTERS[_preset_index()]


## Umbral de LOD de malla en píxeles del preset activo.
func mesh_lod_threshold() -> float:
	return PRESET_MESH_LOD[_preset_index()]


## Umbral de LOD de malla de las caras laterales de
## [constant FisheyeMode.FAST_WIDE]: **el mismo del preset**.
##
## Hasta WP-24d las laterales llevaban un suelo de 4 px con el argumento de que lo
## que cae a más de 57° del eje óptico ocupa menos de la mitad de los píxeles. El
## argumento vale para el tamaño; no vale para la **costura**. Un prop de azotea que
## mide 3 px en la lateral y 5 px en la frontal cambia de LOD al cruzar el fundido
## de [constant FPVCamera.EDGE_FADE], y como las dos caras se mezclan ahí, el cambio
## no se esconde: se ve como un parpadeo del objeto sobre sí mismo. Con el umbral
## igualado el LOD es el mismo a los dos lados de la costura y el fundido vuelve a
## ser lo único que pasa ahí. La función se conserva —y los dos brazos de
## `fpv_camera.gd` con ella— porque el eje sigue siendo un punto de ajuste legítimo:
## lo que cambia es el valor, no la estructura.
func fisheye_side_mesh_lod() -> float:
	return mesh_lod_threshold()


## Escala de render 3D de las `SubViewport` del ojo de pez: la del preset
## (`docs/13` §3.4) multiplicada por la que el jugador eligió a mano.
##
## Va sobre las sub-viewports y no sobre la raíz porque **ahí** se dibuja la
## escena: con ojo de pez la raíz no rasteriza nada (`docs/03` §5).
func fisheye_render_scale() -> float:
	return clampf(PRESET_RENDER_SCALES[_preset_index()] * resolution_scale, 0.25, 2.0)


## Modo de escalado de las `SubViewport` del ojo de pez: FSR 1.0 cuando se está
## escalando de verdad y bilineal cuando la escala es 1, porque FSR a escala 1
## agrega un paso de post sin cambiar un píxel.
func fisheye_scaling_mode() -> Viewport.Scaling3DMode:
	if is_equal_approx(fisheye_render_scale(), 1.0):
		return Viewport.SCALING_3D_MODE_BILINEAR
	return Viewport.SCALING_3D_MODE_FSR


## Aplica la tabla de sombras de `docs/13` §3.4 al sol [param light] del nivel:
## cascadas, alcance, cortes, mezcla, desvanecido y sesgos.
##
## El tamaño del atlas y el filtro **no** van acá: son globales del
## `RenderingServer` y los pone [method update_shadows].
func apply_sun_quality(light: DirectionalLight3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	var level := clampi(int(shadows), 0, SHADOW_ATLAS_SIZES.size() - 1)
	var splits := SHADOW_SPLIT_COUNTS[level]
	light.shadow_enabled = true
	if splits >= 4:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	else:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = SHADOW_DISTANCES[level]
	light.directional_shadow_split_1 = SHADOW_SPLIT_1[level]
	light.directional_shadow_split_2 = SHADOW_SPLIT_2
	light.directional_shadow_split_3 = SHADOW_SPLIT_3
	light.directional_shadow_blend_splits = splits >= 4
	light.directional_shadow_fade_start = SHADOW_FADE_START
	light.shadow_normal_bias = SHADOW_NORMAL_BIAS
	light.shadow_bias = SHADOW_BIAS


## Da de alta el sol de un nivel o de un showcase y le aplica el preset en el acto.
##
## Los niveles no guardan los valores de sombra en la escena: se los pide acá
## `LevelBase._ready()`. Así el mismo `battle_level.tscn` sirve para los cinco
## niveles de sombra y cambiar de preset en caliente no obliga a recargar nada.
## Además de la calidad, a las luces que **no** son [SunLight] se les vuelca el
## [SunProfile] de la identidad visual (`docs/13` §3.2). Un [SunLight] ya trae el
## suyo y se lo aplica solo en su `_ready()`, así que acá se respeta.
##
## Sin esto, un showcase con un sol de 100 000 lux cableado en su escena quedaría
## seis pasos sobreexpuesto contra el `Environment` de atardecer, que está calibrado
## para 2400 lux.
func register_sun(light: DirectionalLight3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	_prune_suns()
	if not _suns.has(light):
		_suns.append(light)
	if not (light is SunLight):
		var profile := default_sun_profile()
		if profile != null:
			profile.apply_to(light)
	apply_sun_quality(light)


## Da de baja un sol. No hace falta llamarla al salir del árbol —[method _prune_suns]
## limpia las referencias muertas—, pero un showcase que cambie de sol puede.
func unregister_sun(light: DirectionalLight3D) -> void:
	var index := _suns.find(light)
	if index >= 0:
		_suns.remove_at(index)


## Los soles vivos dados de alta. Lo miran los checks.
func get_registered_suns() -> Array[DirectionalLight3D]:
	_prune_suns()
	return _suns.duplicate()


## Saca del arreglo los soles que ya no existen.
func _prune_suns() -> void:
	var alive: Array[DirectionalLight3D] = []
	for light: DirectionalLight3D in _suns:
		if is_instance_valid(light):
			alive.append(light)
	_suns = alive


## Aplica el umbral de LOD de malla del preset a la viewport raíz.
func update_mesh_lod() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.mesh_lod_threshold = mesh_lod_threshold()


## Aplica el tamaño del froxel de niebla volumétrica del preset. Es un ajuste
## **global** del `RenderingServer`, no una propiedad del `Environment`.
func update_volumetric_fog_volume() -> void:
	var index := _preset_index()
	RenderingServer.environment_set_volumetric_fog_volume_size(
			PRESET_FOG_VOLUME[index], PRESET_FOG_DEPTH[index])


## Alto en píxeles de las sub-viewports del ojo de pez.
func fisheye_height() -> int:
	var index := clampi(int(fisheye_resolution), 0, FISHEYE_HEIGHTS.size() - 1)
	return FISHEYE_HEIGHTS[index]


## Lado en píxeles de cada cara lateral de [constant FisheyeMode.FAST_WIDE].
##
## El tope de [constant FISHEYE_SIDE_RANGE] es una válvula de seguridad, no parte del
## diseño: con la frontal a 2160p y la proporción de ULTRA, dos caras de 2160² serían
## más píxeles laterales que frontales para una periferia que la proyección comprime.
func fisheye_side_height() -> int:
	var ratio := PRESET_FISHEYE_SIDE_RATIO[_preset_index()]
	var side := int(roundf(float(fisheye_height()) * ratio))
	return clampi(side, FISHEYE_SIDE_RANGE.x, FISHEYE_SIDE_RANGE.y)


## MSAA efectivo del ojo de pez, ya resuelto el caso «igual que el juego».
func fisheye_msaa_level() -> Viewport.MSAA:
	if fisheye_msaa == FisheyeMsaa.SAME_AS_GAME:
		return msaa_to_viewport(int(msaa))
	return msaa_to_viewport(int(fisheye_msaa))


## MSAA de las caras laterales de [constant FisheyeMode.FAST_WIDE], acotado a 2×.
##
## El MSAA se paga por muestra y por píxel de las **tres** viewports, y las laterales
## cubren la periferia, donde el fundido con la frontal y la propia curvatura ya
## suavizan los bordes: 4× o 8× ahí es gasto sin imagen. La frontal conserva el del
## preset entero.
func fisheye_side_msaa_level() -> Viewport.MSAA:
	return mini(int(fisheye_msaa_level()), int(Viewport.MSAA_2X)) as Viewport.MSAA


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


## Si el proyecto pide oclusión por oclusores (`docs/02`). Una `SubViewport` **no**
## la hereda del proyecto —nace con `use_occlusion_culling = false`—, así que las
## del ojo de pez, que son las que dibujan la escena, tienen que pedirla a mano.
##
## **Apagada en todos los presets desde WP-24e**, por dos motivos que se suman:
##
## - **No ahorraba nada.** La fila `occlusion` de `docs/perf/2026-09-20.json` mide
##   −0,011 ms al apagarla: los 15 oclusores de caja del distrito no llegan a pagar
##   el raster de profundidad que hay que hacer por cara del ojo de pez, y con
##   `FAST_WIDE` hay **tres**.
## - **Mentía.** Los oclusores están ceñidos al edificio más alto de cada manzana y
##   se hornean en `district_a.tscn`: cuando ese edificio se derrumba, el volumen
##   sigue ahí. La cámara que entra en la losa fantasma pierde el cuadro entero, y
##   una losa de 75 m de un hito caído tapa al coloso y la ciudad detrás. Con tres
##   rasters el resultado es el parpadeo por caras que reportó el piloto.
##
## `CityGrid.occluder_for()` y `Building._finish_collapse()` arreglan además la
## higiene —un oclusor cuyo edificio cayó queda deshabilitado—, así que volver a
## encender esto es cambiar el `project.godot` y nada más.
func use_occlusion_culling() -> bool:
	return bool(ProjectSettings.get_setting(
			"rendering/occlusion_culling/use_occlusion_culling", false))


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
