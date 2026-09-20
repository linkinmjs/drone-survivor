## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Gráficos (`docs/04` §4.3).
##
## Tres secciones: **Pantalla** (modo de ventana, escala de resolución, sincronización
## vertical y tope de fps), **Calidad** (preset, MSAA, sombras, iluminación global,
## niebla volumétrica y oclusión ambiental) y **FPV** (ojo de pez, su resolución y su
## MSAA, con la opción «igual que el juego»).
##
## Todo se aplica y se guarda en el acto: cada control escribe su valor en `Graphics`
## y llama a `save_graphics_settings()`, que reaplica y avisa. En `--headless` los
## `update_*` del autoload no tocan ni la ventana ni el vsync, así que esta pantalla
## también se puede recorrer sin framebuffer.
##
## **Preset personalizado**: los siete valores que fija `QUALITY_PRESETS` —MSAA,
## sombras, iluminación global, niebla, oclusión, modo y resolución del ojo de pez—
## llaman a `Graphics.mark_custom_quality()` cuando el jugador los toca a mano, y el
## preset pasa a mostrar «Personalizado». Los de la sección Pantalla y el MSAA del ojo
## de pez no forman parte de ningún preset, así que no lo ensucian.
class_name GraphicsMenu
extends MenuScreen

## Clave de traducción de cada [enum Graphics.WindowMode].
const WINDOW_MODE_KEYS: Array[String] = ["GFX_FULLSCREEN", "GFX_WINDOW", "GFX_BORDERLESS"]

## Clave de traducción de cada [enum Graphics.VSync].
const VSYNC_KEYS: Array[String] = ["UI_OFF", "UI_ON", "GFX_VSYNC_ADAPTIVE"]

## Clave de traducción de cada [enum Graphics.Quality]; la última es «Personalizado».
const QUALITY_KEYS: Array[String] = ["GFX_QUALITY_LOW", "GFX_QUALITY_MEDIUM",
		"GFX_QUALITY_HIGH", "GFX_QUALITY_ULTRA", "GFX_QUALITY_CUSTOM"]

## Clave de traducción de cada [enum Graphics.Msaa].
const MSAA_KEYS: Array[String] = ["UI_OFF", "GFX_MSAA_2X", "GFX_MSAA_4X", "GFX_MSAA_8X"]

## Clave de traducción de cada [enum Graphics.Shadows].
const SHADOW_KEYS: Array[String] = ["GFX_QUALITY_VERY_LOW", "GFX_QUALITY_LOW",
		"GFX_QUALITY_MEDIUM", "GFX_QUALITY_HIGH", "GFX_QUALITY_ULTRA"]

## Clave de traducción de cada [enum Graphics.Gi].
const GI_KEYS: Array[String] = ["UI_OFF", "GFX_GI_SDFGI"]

## Clave de traducción de cada [enum Graphics.FisheyeMode]. El orden es el del enum,
## no el del costo: `FAST_WIDE` se anexó al final en WP-24c para no reinterpretar los
## `Graphics.cfg` ya escritos.
const FISHEYE_KEYS: Array[String] = ["UI_OFF", "GFX_FISHEYE_FULL", "GFX_FISHEYE_FAST",
		"GFX_FISHEYE_FAST_WIDE"]

## Clave de traducción de cada [enum Graphics.FisheyeMsaa]; la última copia el MSAA
## del juego.
const FISHEYE_MSAA_KEYS: Array[String] = ["UI_OFF", "GFX_MSAA_2X", "GFX_MSAA_4X",
		"GFX_MSAA_8X", "GFX_SAME_AS_GAME"]

## Índice de «Personalizado» dentro de [constant QUALITY_KEYS].
const CUSTOM_QUALITY_INDEX: int = 4

## Controles expuestos a los checks por [method control_for].
var _controls: Dictionary[StringName, Control] = {}

var _syncing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_items()
	_connect_controls()
	_apply_renderer_limits()
	_sync()
	bind_back_button(%ButtonBack)
	initial_focus = %WindowModeOption
	var _discard := Graphics.graphics_settings_updated.connect(_on_graphics_updated)
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build_items()
		_sync()


## Control asociado a una clave de ajuste, o `null` si no existe. Lo usan los checks.
func control_for(key: StringName) -> Control:
	return _controls.get(key, null)


# --- Construcción ----------------------------------------------------------------------------

## Rellena los nueve `OptionButton` con el texto ya traducido. Se rehace en
## `NOTIFICATION_TRANSLATION_CHANGED`.
func _build_items() -> void:
	_fill(%WindowModeOption, WINDOW_MODE_KEYS)
	_fill(%VsyncOption, VSYNC_KEYS)
	_fill(%PresetOption, QUALITY_KEYS)
	# «Personalizado» se muestra, pero no se elige a mano (`docs/04` §4.3).
	(%PresetOption as OptionButton).set_item_disabled(CUSTOM_QUALITY_INDEX, true)
	_fill(%MsaaOption, MSAA_KEYS)
	_fill(%ShadowsOption, SHADOW_KEYS)
	_fill(%GiOption, GI_KEYS)
	_fill(%FisheyeOption, FISHEYE_KEYS)
	_fill(%FisheyeMsaaOption, FISHEYE_MSAA_KEYS)

	var scales := %ResolutionScaleOption as OptionButton
	scales.clear()
	for index: int in Graphics.RESOLUTION_SCALES.size():
		scales.add_item(tr("UI_PERCENT") % int(roundf(Graphics.RESOLUTION_SCALES[index] * 100.0)),
				index)

	var fps := %MaxFpsOption as OptionButton
	fps.clear()
	for index: int in Graphics.MAX_FPS_VALUES.size():
		var value: int = Graphics.MAX_FPS_VALUES[index]
		fps.add_item(tr("GFX_UNLIMITED") if value <= 0 else str(value), index)

	var resolutions := %FisheyeResolutionOption as OptionButton
	resolutions.clear()
	for index: int in Graphics.FISHEYE_HEIGHTS.size():
		resolutions.add_item("%dp" % Graphics.FISHEYE_HEIGHTS[index], index)


func _fill(option: OptionButton, keys: Array[String]) -> void:
	option.clear()
	for index: int in keys.size():
		option.add_item(tr(keys[index]), index)


func _connect_controls() -> void:
	_controls[&"GFX_WINDOW_MODE"] = %WindowModeOption
	_controls[&"GFX_RESOLUTION_SCALE"] = %ResolutionScaleOption
	_controls[&"GFX_VSYNC"] = %VsyncOption
	_controls[&"GFX_MAX_FPS"] = %MaxFpsOption
	_controls[&"GFX_PRESET"] = %PresetOption
	_controls[&"GFX_MSAA"] = %MsaaOption
	_controls[&"GFX_SHADOWS"] = %ShadowsOption
	_controls[&"GFX_GI"] = %GiOption
	_controls[&"GFX_FOG"] = %FogCheck
	_controls[&"GFX_SSAO"] = %SsaoCheck
	_controls[&"GFX_FISHEYE"] = %FisheyeOption
	_controls[&"GFX_FISHEYE_RESOLUTION"] = %FisheyeResolutionOption
	_controls[&"GFX_FISHEYE_MSAA"] = %FisheyeMsaaOption
	for key: StringName in _controls:
		_controls[key].set_meta(&"stick_value_control", true)

	var _discard := (%WindowModeOption as OptionButton).item_selected.connect(_on_window_mode)
	_discard = (%ResolutionScaleOption as OptionButton).item_selected.connect(_on_resolution_scale)
	_discard = (%VsyncOption as OptionButton).item_selected.connect(_on_vsync)
	_discard = (%MaxFpsOption as OptionButton).item_selected.connect(_on_max_fps)
	_discard = (%PresetOption as OptionButton).item_selected.connect(_on_preset)
	_discard = (%MsaaOption as OptionButton).item_selected.connect(_on_msaa)
	_discard = (%ShadowsOption as OptionButton).item_selected.connect(_on_shadows)
	_discard = (%GiOption as OptionButton).item_selected.connect(_on_gi)
	_discard = (%FogCheck as CheckButton).toggled.connect(_on_fog)
	_discard = (%SsaoCheck as CheckButton).toggled.connect(_on_ssao)
	_discard = (%FisheyeOption as OptionButton).item_selected.connect(_on_fisheye)
	_discard = (%FisheyeResolutionOption as OptionButton).item_selected.connect(
			_on_fisheye_resolution)
	_discard = (%FisheyeMsaaOption as OptionButton).item_selected.connect(_on_fisheye_msaa)


## El renderer de compatibilidad no tiene SDFGI, niebla volumétrica ni SSAO, y allí sí
## hay cambios que piden reiniciar; en Forward+ no hay ninguno (`docs/04` §4.3).
func _apply_renderer_limits() -> void:
	var limited := Graphics.is_compatibility_renderer()
	(%GiOption as OptionButton).disabled = limited
	(%FogCheck as CheckButton).disabled = limited
	(%SsaoCheck as CheckButton).disabled = limited
	(%RestartNote as Label).visible = limited


# --- Sincronización --------------------------------------------------------------------------

## Vuelca los valores de `Graphics` sobre los controles sin volver a guardarlos.
func _sync() -> void:
	if _syncing:
		return
	_syncing = true
	(%WindowModeOption as OptionButton).select(int(Graphics.window_mode))
	(%ResolutionScaleOption as OptionButton).select(_scale_index())
	(%VsyncOption as OptionButton).select(int(Graphics.vsync))
	(%MaxFpsOption as OptionButton).select(maxi(Graphics.MAX_FPS_VALUES.find(Graphics.max_fps), 0))
	(%PresetOption as OptionButton).select(clampi(int(Graphics.quality), 0,
			CUSTOM_QUALITY_INDEX))
	(%MsaaOption as OptionButton).select(int(Graphics.msaa))
	(%ShadowsOption as OptionButton).select(int(Graphics.shadows))
	(%GiOption as OptionButton).select(int(Graphics.gi))
	(%FogCheck as CheckButton).button_pressed = Graphics.volumetric_fog
	(%SsaoCheck as CheckButton).button_pressed = Graphics.ssao
	(%FisheyeOption as OptionButton).select(int(Graphics.fisheye_mode))
	(%FisheyeResolutionOption as OptionButton).select(int(Graphics.fisheye_resolution))
	(%FisheyeMsaaOption as OptionButton).select(int(Graphics.fisheye_msaa))
	_syncing = false


func _scale_index() -> int:
	for index: int in Graphics.RESOLUTION_SCALES.size():
		if is_equal_approx(Graphics.RESOLUTION_SCALES[index], Graphics.resolution_scale):
			return index
	return 0


func _on_graphics_updated() -> void:
	_sync()


# --- Manejadores -----------------------------------------------------------------------------

## Guarda y reaplica. [param custom] marca la calidad como personalizada porque el
## valor que cambió forma parte de `QUALITY_PRESETS`.
func _commit(custom: bool) -> void:
	if custom:
		Graphics.mark_custom_quality()
	Graphics.save_graphics_settings()


func _on_window_mode(index: int) -> void:
	if _syncing:
		return
	Graphics.window_mode = clampi(index, 0, WINDOW_MODE_KEYS.size() - 1)
	_commit(false)


func _on_resolution_scale(index: int) -> void:
	if _syncing:
		return
	var scales: Array[float] = Graphics.RESOLUTION_SCALES
	Graphics.resolution_scale = scales[clampi(index, 0, scales.size() - 1)]
	_commit(false)


func _on_vsync(index: int) -> void:
	if _syncing:
		return
	Graphics.vsync = clampi(index, 0, VSYNC_KEYS.size() - 1)
	_commit(false)


func _on_max_fps(index: int) -> void:
	if _syncing:
		return
	var values: Array[int] = Graphics.MAX_FPS_VALUES
	Graphics.max_fps = values[clampi(index, 0, values.size() - 1)]
	_commit(false)


func _on_preset(index: int) -> void:
	if _syncing or index < 0 or index >= CUSTOM_QUALITY_INDEX:
		return
	Graphics.apply_quality_preset(index, true)


func _on_msaa(index: int) -> void:
	if _syncing:
		return
	Graphics.msaa = clampi(index, 0, MSAA_KEYS.size() - 1)
	_commit(true)


func _on_shadows(index: int) -> void:
	if _syncing:
		return
	Graphics.shadows = clampi(index, 0, SHADOW_KEYS.size() - 1)
	_commit(true)


func _on_gi(index: int) -> void:
	if _syncing:
		return
	Graphics.gi = clampi(index, 0, GI_KEYS.size() - 1)
	_commit(true)


func _on_fog(pressed: bool) -> void:
	if _syncing:
		return
	Graphics.volumetric_fog = pressed
	_commit(true)


func _on_ssao(pressed: bool) -> void:
	if _syncing:
		return
	Graphics.ssao = pressed
	_commit(true)


func _on_fisheye(index: int) -> void:
	if _syncing:
		return
	Graphics.fisheye_mode = clampi(index, 0, FISHEYE_KEYS.size() - 1)
	_commit(true)


func _on_fisheye_resolution(index: int) -> void:
	if _syncing:
		return
	Graphics.fisheye_resolution = clampi(index, 0, Graphics.FISHEYE_HEIGHTS.size() - 1)
	_commit(true)


func _on_fisheye_msaa(index: int) -> void:
	if _syncing:
		return
	Graphics.fisheye_msaa = clampi(index, 0, FISHEYE_MSAA_KEYS.size() - 1)
	# El MSAA del ojo de pez no forma parte de ningún preset de calidad.
	_commit(false)
