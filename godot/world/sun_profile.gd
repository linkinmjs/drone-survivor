## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Perfil de sol compartido entre niveles, showcases y el backdrop del menú
## (`docs/13` §3.2).
##
## Un [DirectionalLight3D] no se puede guardar como `.tres` —es un nodo—, así que el
## sol de la identidad visual vive en este recurso y lo vuelca sobre la luz el script
## [SunLight] (o [method Graphics.register_sun], para las luces que no lo llevan).
##
## ## Reparto con `Graphics`
##
## Este recurso es el **look**: intensidad, temperatura, ángulo, penumbra y opacidad
## de sombra. La **calidad** —cascadas, alcance, cortes, sesgos y filtro— la pone
## [method Graphics.apply_sun_quality] desde la tabla de presets de `docs/13` §3.4, y
## acá no se toca ninguno de esos campos: si los dos escribieran `shadow_normal_bias`,
## cambiar de preset dejaría el sesgo del perfil y nadie sabría cuál manda.
##
## ## Temperatura: color derivado y `light_temperature` en neutro
##
## Con `rendering/lights_and_shadows/use_physical_light_units = true` Godot multiplica
## `light_color` por el color de cuerpo negro de `light_temperature`. Aplicar los dos
## —un color ya cálido **y** 3200 K— calentaría la luz dos veces. Por eso
## [member light_color] se **deriva** de [member temperature_k] con
## [method color_from_temperature] y [method apply_to] deja `light_temperature` en
## [constant NEUTRAL_TEMPERATURE_K], donde el factor de cuerpo negro es
## prácticamente blanco.
class_name SunProfile
extends Resource

## Temperatura a la que el factor de cuerpo negro de Godot es ~blanco (1, 1, 1).
## Es el valor de fábrica de [member DirectionalLight3D.light_temperature].
const NEUTRAL_TEMPERATURE_K: float = 6500.0

## Iluminancia del sol sobre una superficie perpendicular, en lux.
##
## 2400 lux es crepúsculo civil (`docs/13` §3.2 y §9). El mediodía despejado son
## 100 000 lux: el `battle_level.tscn` que dejó P1 tenía la luz en los 100 000 de
## fábrica multiplicados por `light_energy = 1.45`, y de ahí venía la ciudad «de
## mediodía» que vio el usuario.
@export_range(0.0, 150000.0, 10.0) var intensity_lux: float = 2400.0

## Temperatura de color de la que se deriva [member light_color], en kelvin.
@export_range(1500.0, 12000.0, 10.0) var temperature_k: float = 3200.0

## Tinte del sol. Lo deriva [method derive_light_color] de [member temperature_k];
## se deja expuesto para poder desviarse a mano del cuerpo negro puro.
@export var light_color: Color = Color(1.0, 0.722, 0.492)

## Multiplicador sobre [member intensity_lux]. Se deja en 1,0 y se mueve el lux:
## así el número del inspector sigue siendo una magnitud física legible.
@export_range(0.0, 16.0, 0.01) var energy: float = 1.0

## Cuánto aporta este sol al rebote indirecto (SDFGI, lightmaps).
@export_range(0.0, 16.0, 0.01) var indirect_energy: float = 1.0

## Cuánto ilumina la niebla volumétrica. Por encima de 1,0 marca los haces rasantes
## entre los edificios, que es la mitad del atardecer.
@export_range(0.0, 16.0, 0.01) var volumetric_fog_energy: float = 1.6

## Rotación de la luz en grados. La `X` negativa es la elevación del sol sobre el
## horizonte: `-6` lo deja 6° arriba, con sombras rasantes largas.
@export var angle_degrees: Vector3 = Vector3(-6.0, -118.0, 0.0)

## Diámetro angular del disco solar, en grados. El sol real mide 0,5°; 0,6 ensancha
## un poco la penumbra sin deshacer el contacto de la sombra.
@export_range(0.0, 90.0, 0.01) var angular_distance: float = 0.6

## Opacidad de la sombra. 1,0 es sombra plena: lo que la levanta es el ambiente del
## cielo, no una sombra aguada.
@export_range(0.0, 1.0, 0.01) var shadow_opacity: float = 1.0

## Desenfoque de la sombra, en múltiplos del valor de fábrica.
@export_range(0.0, 10.0, 0.01) var shadow_blur: float = 1.0

## Intensidad del reflejo especular que produce el sol.
@export_range(0.0, 16.0, 0.01) var specular: float = 1.0

## Si el sol también dibuja el disco y alimenta al [PhysicalSkyMaterial]. Tiene que
## quedar encendido: el cielo físico de `docs/13` §3.1 se construye a partir de él.
@export var lights_sky: bool = true


## Color de cuerpo negro de [param kelvin], en sRGB, normalizado para que 6500 K sea
## blanco (aproximación de Tanner Helland, la misma familia que usa el motor).
static func color_from_temperature(kelvin: float) -> Color:
	var t := clampf(kelvin, 1000.0, 40000.0) / 100.0
	var red := 255.0
	if t > 66.0:
		red = 329.698727446 * pow(t - 60.0, -0.1332047592)
	var green := 0.0
	if t <= 66.0:
		green = 99.4708025861 * log(t) - 161.1195681661
	else:
		green = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	var blue := 255.0
	if t < 19.0:
		blue = 0.0
	elif t < 66.0:
		blue = 138.5177312231 * log(t - 10.0) - 305.0447927307
	return Color(
			clampf(red / 255.0, 0.0, 1.0),
			clampf(green / 255.0, 0.0, 1.0),
			clampf(blue / 255.0, 0.0, 1.0))


## Recalcula [member light_color] a partir de [member temperature_k]. La llama la
## herramienta que escribe `world/sun_dusk.tres`.
func derive_light_color() -> void:
	light_color = color_from_temperature(temperature_k)


## Vuelca el perfil sobre [param light]. **No** toca nada de lo que pone
## [method Graphics.apply_sun_quality]: cascadas, alcance, cortes y sesgos.
func apply_to(light: DirectionalLight3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	light.rotation_degrees = angle_degrees
	light.light_intensity_lux = intensity_lux
	light.light_temperature = NEUTRAL_TEMPERATURE_K
	light.light_color = light_color
	light.light_energy = energy
	light.light_indirect_energy = indirect_energy
	light.light_volumetric_fog_energy = volumetric_fog_energy
	light.light_angular_distance = angular_distance
	light.light_specular = specular
	light.shadow_opacity = shadow_opacity
	light.shadow_blur = shadow_blur
	if lights_sky:
		light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	else:
		light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
