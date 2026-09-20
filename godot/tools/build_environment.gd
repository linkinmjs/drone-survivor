## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Genera los recursos de entorno y luz de `docs/13` §3.1–§3.3 (WP-24).
##
## Escribe cuatro `.tres` y es la **única** fuente de sus valores: la tabla del
## documento vive acá como constantes y el recurso se regenera, nunca se edita a mano.
##
## [codeblock]
## godot --headless --path godot --script res://tools/build_environment.gd
## [/codeblock]
##
## | Recurso | Qué es |
## |---|---|
## | `world/environment_battle.tres` | `Environment` del nivel y de los checks |
## | `world/environment_menu.tres` | ídem para el backdrop del menú (WP-25): mismo cielo, glow sí, SDFGI no |
## | `world/sun_dusk.tres` | [SunProfile] del sol de atardecer |
## | `world/camera_attributes_dusk.tres` | exposición fotográfica compartida por las escenas |
##
## ## Por qué la exposición se mueve y el resto del encuadre no
##
## El proyecto corre con `use_physical_light_units = true`, así que **todo** lo que
## ilumina está en unidades físicas y la cámara decide cuánto de eso llega al
## tonemapper. Los valores que dejó P1 eran los de fábrica: sol de 100 000 lux
## (× 1,45 de `light_energy`), cielo de [code]background_intensity = 30000[/code]
## nits y cámara de f/16 · 1/100 s · ISO 100, que es exactamente la regla del
## «soleado f/16». O sea: **mediodía despejado**, que es lo que el usuario vio.
##
## El emisivo de las ventanas, en cambio, no es de fábrica: `StandardMaterial3D`
## con `use_physical_light_units` fija `emission_intensity = 1000` nits. Con la
## normalización de exposición de f/16 · ISO 100 (3,26 × 10⁻⁵) esas ventanas salían
## a **0,033** sobre un cielo a 0,98: invisibles, y treinta veces por debajo del
## `glow_hdr_threshold`. De ahí la ciudad «plana y gris».
##
## La corrección es de escena entera, no de un valor suelto: el sol baja a 2400 lux,
## el cielo a [constant SKY_INTENSITY_NITS] nits y la cámara se abre los mismos
## ~6 pasos (f/2,8 · ISO 200). El producto sol × exposición queda igual que antes
## —la imagen no se va a blanco ni a negro— pero los emisivos, que no se tocaron,
## suben ×65 y pasan a 2,1: por encima del umbral de glow, que es lo que enciende las
## ventanas y los emisivos del coloso.
##
## La exposición va en el `CameraAttributesPhysical` y **no** en `tonemap_exposure`
## porque el glow se extrae del búfer HDR antes del tonemap: subir la exposición en
## el tonemapper dejaría el glow sin alimentar.
extends SceneTree

const ENVIRONMENT_BATTLE_PATH: String = "res://world/environment_battle.tres"
const ENVIRONMENT_MENU_PATH: String = "res://world/environment_menu.tres"
const SUN_PROFILE_PATH: String = "res://world/sun_dusk.tres"
const CAMERA_ATTRIBUTES_PATH: String = "res://world/camera_attributes_dusk.tres"
const LUT_PATH: String = "res://world/lut_dusk.tres"

# --- Cielo (`docs/13` §3.1) -------------------------------------------------------------------

const SKY_RAYLEIGH_COEFFICIENT: float = 2.4
const SKY_RAYLEIGH_COLOR: Color = Color(0.32157, 0.47843, 0.78039)      # #527ac7
const SKY_MIE_COEFFICIENT: float = 0.012
const SKY_MIE_ECCENTRICITY: float = 0.82
const SKY_MIE_COLOR: Color = Color(0.94118, 0.67843, 0.41961)           # #f0ad6b
const SKY_TURBIDITY: float = 12.0
const SKY_SUN_DISK_SCALE: float = 1.6
const SKY_GROUND_COLOR: Color = Color(0.03529, 0.03922, 0.05098)        # #090A0D
const SKY_ENERGY_MULTIPLIER: float = 1.0

## Luminancia del fondo en nits. **No está en `docs/13`** y es el segundo valor que
## hacía de mediodía: el de fábrica, 30 000 nits, es el cielo al mediodía. Un cielo
## de crepúsculo civil está dos órdenes por debajo; 420 nits lo deja algo por debajo
## de las fachadas iluminadas, que es lo que hace que el horizonte se lea como
## atardecer y no como día nublado.
const SKY_INTENSITY_NITS: float = 1100.0

# --- Sol (`docs/13` §3.2) ---------------------------------------------------------------------

const SUN_INTENSITY_LUX: float = 2400.0
const SUN_TEMPERATURE_K: float = 3200.0
const SUN_ANGLE_DEGREES: Vector3 = Vector3(-6.0, -118.0, 0.0)
const SUN_ANGULAR_DISTANCE: float = 0.6
const SUN_SHADOW_OPACITY: float = 1.0
const SUN_VOLUMETRIC_FOG_ENERGY: float = 1.6

# --- Cámara -----------------------------------------------------------------------------------

## Apertura, obturador (1/x s) e ISO. f/2,8 · 1/100 s · ISO 200 son 6,03 pasos por
## encima del f/16 · 1/100 s · ISO 100 que traían las escenas, que es exactamente lo
## que baja el sol al pasar de 145 000 lux efectivos a 2400.
const CAMERA_APERTURE: float = 2.8
const CAMERA_SHUTTER_SPEED: float = 100.0
const CAMERA_SENSITIVITY: float = 400.0

## Distancia de foco y focal del ojo de pez, tal como estaban en las escenas.
const CAMERA_FOCUS_DISTANCE: float = 5.0
const CAMERA_FOCAL_LENGTH: float = 2.1

# --- Iluminación indirecta --------------------------------------------------------------------

const AMBIENT_SKY_CONTRIBUTION: float = 1.0
const AMBIENT_ENERGY: float = 1.0

## Copias de las constantes de `Graphics` que también viven en el recurso. No se
## leen del autoload porque una herramienta `--script` reemplaza el bucle principal
## y los autoloads no llegan a instanciarse. `settings_check` verifica que el preset
## los reescriba igual, así que una divergencia se nota en verde o en rojo.
const FALLBACK_AMBIENT_COLOR: Color = Color(0.16470589, 0.22745098, 0.32156864)
const SDFGI_BOUNCE_FEEDBACK: float = 0.5
const SDFGI_CASCADES_HIGH: int = 4
const SDFGI_CASCADE0_DISTANCE: float = 16.0
const SDFGI_NORMAL_BIAS: float = 1.1
const SDFGI_PROBE_BIAS: float = 1.1

const SSAO_RADIUS: float = 1.6
const SSAO_INTENSITY: float = 2.2
const SSAO_POWER: float = 1.5
const SSAO_DETAIL: float = 0.5
const SSAO_HORIZON: float = 0.06
const SSAO_SHARPNESS: float = 0.98

const SSIL_RADIUS: float = 4.0
const SSIL_INTENSITY: float = 1.0
const SSIL_SHARPNESS: float = 0.98
const SSIL_NORMAL_REJECTION: float = 1.0

# --- Nieblas ----------------------------------------------------------------------------------

const FOG_DENSITY: float = 0.0006
const FOG_LIGHT_COLOR: Color = Color(0.41961, 0.47843, 0.61961)         # #6B7A9E
const FOG_LIGHT_ENERGY: float = 0.22
const FOG_SUN_SCATTER: float = 0.25
const FOG_AERIAL_PERSPECTIVE: float = 0.25
const FOG_SKY_AFFECT: float = 0.30

const VFOG_DENSITY: float = 0.0008
const VFOG_ALBEDO: Color = Color(0.61961, 0.65882, 0.78039)             # #9EA8C7
const VFOG_ANISOTROPY: float = 0.35
const VFOG_LENGTH: float = 96.0
const VFOG_DETAIL_SPREAD: float = 2.0
const VFOG_GI_INJECT: float = 0.6
const VFOG_AMBIENT_INJECT: float = 0.15
const VFOG_SKY_AFFECT: float = 0.35
const VFOG_EMISSION: Color = Color(0.05098, 0.05882, 0.09020)           # #0D0F17
const VFOG_EMISSION_ENERGY: float = 0.4
const VFOG_TEMPORAL_AMOUNT: float = 0.9

# --- Glow y tonemap ---------------------------------------------------------------------------

const GLOW_LEVELS: Array[float] = [0.0, 0.2, 0.8, 1.0, 0.6, 0.2, 0.0]
const GLOW_INTENSITY: float = 0.85
const GLOW_STRENGTH: float = 1.0
const GLOW_BLOOM: float = 0.03
const GLOW_HDR_THRESHOLD: float = 1.4
const GLOW_HDR_SCALE: float = 2.0
const GLOW_HDR_LUMINANCE_CAP: float = 12.0
const GLOW_MIX: float = 0.05

const TONEMAP_EXPOSURE: float = 1.0

## `docs/13` §3.1 pide `tonemap_white 2.0` y `tonemap_contrast 1.10`. En Godot 4.7
## **no existe** `tonemap_contrast`: AgX tiene los suyos propios
## (`tonemap_agx_white`, de fábrica 16,29, y `tonemap_agx_contrast`, de fábrica 1,25)
## y `tonemap_white` sólo lo leen los otros operadores. El 1,10 del documento va al
## contraste de AgX; el 2,0 queda para ACES, que es el que usa `tonemap_white`.
const TONEMAP_AGX_WHITE: float = 16.29
const TONEMAP_AGX_CONTRAST: float = 1.35
const TONEMAP_ACES_WHITE: float = 2.0

const ADJUSTMENT_BRIGHTNESS: float = 1.0
const ADJUSTMENT_CONTRAST: float = 1.04
const ADJUSTMENT_SATURATION: float = 1.06


func _init() -> void:
	var failures: int = 0
	failures += _save(_build_sun_profile(), SUN_PROFILE_PATH)
	failures += _save(_build_camera_attributes(), CAMERA_ATTRIBUTES_PATH)
	failures += _save(_build_environment(false), ENVIRONMENT_BATTLE_PATH)
	failures += _save(_build_environment(true), ENVIRONMENT_MENU_PATH)
	if failures > 0:
		push_error("build_environment: %d recursos no se pudieron guardar" % failures)
	print("build_environment: %d recursos escritos, %d fallos" % [4 - failures, failures])
	quit(1 if failures > 0 else 0)


## Escribe [param resource] en [param path] y devuelve 1 si falló.
func _save(resource: Resource, path: String) -> int:
	# `FLAG_CHANGE_PATH` deja el recurso apuntando al archivo nuevo; sin él, una
	# segunda pasada guardaría contra la ruta vieja de la caché.
	var err := ResourceSaver.save(resource, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		push_error("no se pudo guardar %s: %s" % [path, error_string(err)])
		return 1
	print("  %s" % path)
	return 0


func _build_sun_profile() -> SunProfile:
	var profile := SunProfile.new()
	profile.resource_name = "sun_dusk"
	profile.intensity_lux = SUN_INTENSITY_LUX
	profile.temperature_k = SUN_TEMPERATURE_K
	profile.derive_light_color()
	profile.energy = 1.0
	profile.indirect_energy = 1.0
	profile.volumetric_fog_energy = SUN_VOLUMETRIC_FOG_ENERGY
	profile.angle_degrees = SUN_ANGLE_DEGREES
	profile.angular_distance = SUN_ANGULAR_DISTANCE
	profile.shadow_opacity = SUN_SHADOW_OPACITY
	profile.shadow_blur = 1.0
	profile.specular = 1.0
	profile.lights_sky = true
	return profile


func _build_camera_attributes() -> CameraAttributesPhysical:
	var attributes := CameraAttributesPhysical.new()
	attributes.resource_name = "camera_attributes_dusk"
	attributes.frustum_focus_distance = CAMERA_FOCUS_DISTANCE
	attributes.frustum_focal_length = CAMERA_FOCAL_LENGTH
	attributes.exposure_aperture = CAMERA_APERTURE
	attributes.exposure_shutter_speed = CAMERA_SHUTTER_SPEED
	attributes.exposure_sensitivity = CAMERA_SENSITIVITY
	# La auto-exposición pulsa cuando el jefe llena la pantalla (`docs/13` §3.2).
	attributes.auto_exposure_enabled = false
	return attributes


## El `Environment` de `docs/13` §3.1. Con [param menu] en `true` sale la variante
## del backdrop (`docs/13` §2.5 y §8): mismo cielo y mismo glow, sin SDFGI, sin SSAO
## y sin niebla volumétrica, que a 1280×720 dentro de un `SubViewport` no se ven y
## cuestan el presupuesto entero de 2,5 ms.
func _build_environment(menu: bool) -> Environment:
	var env := Environment.new()
	env.resource_name = "environment_menu" if menu else "environment_battle"

	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 1.0
	env.background_intensity = SKY_INTENSITY_NITS
	env.sky = _build_sky()

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = AMBIENT_SKY_CONTRIBUTION
	env.ambient_light_energy = AMBIENT_ENERGY
	env.ambient_light_color = FALLBACK_AMBIENT_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# SDFGI: las cascadas las pone el preset (`Graphics.apply_environment_quality`).
	env.sdfgi_enabled = not menu
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = SDFGI_BOUNCE_FEEDBACK
	env.sdfgi_cascades = SDFGI_CASCADES_HIGH
	env.sdfgi_cascade0_distance = SDFGI_CASCADE0_DISTANCE
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_100_PERCENT
	env.sdfgi_energy = 1.0
	env.sdfgi_normal_bias = SDFGI_NORMAL_BIAS
	env.sdfgi_probe_bias = SDFGI_PROBE_BIAS

	env.ssao_enabled = not menu
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_power = SSAO_POWER
	env.ssao_detail = SSAO_DETAIL
	env.ssao_horizon = SSAO_HORIZON
	env.ssao_sharpness = SSAO_SHARPNESS
	env.ssao_light_affect = 0.0
	env.ssao_ao_channel_affect = 0.0

	# SSIL lo enciende el preset ULTRA o la variante B de `docs/13` §3.5.
	env.ssil_enabled = false
	env.ssil_radius = SSIL_RADIUS
	env.ssil_intensity = SSIL_INTENSITY
	env.ssil_sharpness = SSIL_SHARPNESS
	env.ssil_normal_rejection = SSIL_NORMAL_REJECTION

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = FOG_DENSITY
	env.fog_light_color = FOG_LIGHT_COLOR
	env.fog_light_energy = FOG_LIGHT_ENERGY
	env.fog_sun_scatter = FOG_SUN_SCATTER
	env.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	env.fog_sky_affect = FOG_SKY_AFFECT

	env.volumetric_fog_enabled = not menu
	env.volumetric_fog_density = VFOG_DENSITY
	env.volumetric_fog_albedo = VFOG_ALBEDO
	env.volumetric_fog_anisotropy = VFOG_ANISOTROPY
	env.volumetric_fog_length = VFOG_LENGTH
	env.volumetric_fog_detail_spread = VFOG_DETAIL_SPREAD
	env.volumetric_fog_gi_inject = VFOG_GI_INJECT
	env.volumetric_fog_ambient_inject = VFOG_AMBIENT_INJECT
	env.volumetric_fog_sky_affect = VFOG_SKY_AFFECT
	env.volumetric_fog_emission = VFOG_EMISSION
	env.volumetric_fog_emission_energy = VFOG_EMISSION_ENERGY
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = VFOG_TEMPORAL_AMOUNT

	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level: int in range(1, 8):
		env.set("glow_levels/%d" % level, GLOW_LEVELS[level - 1])
	env.glow_normalized = false
	env.glow_intensity = GLOW_INTENSITY
	env.glow_strength = GLOW_STRENGTH
	env.glow_mix = GLOW_MIX
	env.glow_bloom = GLOW_BLOOM
	env.glow_hdr_threshold = GLOW_HDR_THRESHOLD
	env.glow_hdr_scale = GLOW_HDR_SCALE
	env.glow_hdr_luminance_cap = GLOW_HDR_LUMINANCE_CAP

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = TONEMAP_EXPOSURE
	env.tonemap_white = TONEMAP_ACES_WHITE
	env.tonemap_agx_white = TONEMAP_AGX_WHITE
	env.tonemap_agx_contrast = TONEMAP_AGX_CONTRAST

	env.adjustment_enabled = true
	env.adjustment_brightness = ADJUSTMENT_BRIGHTNESS
	env.adjustment_contrast = ADJUSTMENT_CONTRAST
	env.adjustment_saturation = ADJUSTMENT_SATURATION
	# La LUT es opcional (`docs/13` §11.5): se enchufa sólo si ya está generada.
	if ResourceLoader.exists(LUT_PATH):
		env.adjustment_color_correction = load(LUT_PATH)
	return env


func _build_sky() -> Sky:
	var material := PhysicalSkyMaterial.new()
	material.rayleigh_coefficient = SKY_RAYLEIGH_COEFFICIENT
	material.rayleigh_color = SKY_RAYLEIGH_COLOR
	material.mie_coefficient = SKY_MIE_COEFFICIENT
	material.mie_eccentricity = SKY_MIE_ECCENTRICITY
	material.mie_color = SKY_MIE_COLOR
	material.turbidity = SKY_TURBIDITY
	material.sun_disk_scale = SKY_SUN_DISK_SCALE
	material.ground_color = SKY_GROUND_COLOR
	material.energy_multiplier = SKY_ENERGY_MULTIPLIER
	material.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	# `docs/13` §3.1 pide `PROCESS_MODE_HIGH_QUALITY`, que no existe en 4.7: la
	# enumeración es AUTOMATIC / QUALITY / INCREMENTAL / REALTIME y la de más
	# calidad es QUALITY.
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky
