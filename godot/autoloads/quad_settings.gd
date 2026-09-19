## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ángulo de cámara, pesos, FOV y curvas de rates del dron, persistidos en
## `Quad.cfg` (`docs/04` §3.6).
##
## [member control_profile] se reconstruye al cargar y al guardar, de modo que
## `FlightController` siempre recibe un [ControlProfile] coherente con lo que el
## jugador ve en el hangar (`docs/03` §3.6).
extends Node

## Se emite después de guardar. La escuchan `Drone` (masa), `CameraRig` (ángulo),
## `FPVCamera` (FOV) y `FlightController` (perfil de rates).
signal settings_updated

## Nombre del archivo dentro de `Global.config_dir`.
const CONFIG_FILE: String = "Quad.cfg"

## Sección del cuadro.
const QUAD_SECTION: String = "quad"

## Sección de las curvas de rates.
const RATES_SECTION: String = "rates"

## Clave de traducción que `Global.startup_errors` acumula si el archivo está roto.
const ERROR_KEY: String = "ERR_CONFIG_QUAD"

## Inclinación de la cámara FPV, en grados.
const ANGLE_RANGE: Vector2 = Vector2(-20.0, 80.0)

## Peso del dron sin batería, en kg.
const DRY_WEIGHT_RANGE: Vector2 = Vector2(0.1, 1.0)

## Peso de la batería, en kg.
const BATTERY_WEIGHT_RANGE: Vector2 = Vector2(0.1, 0.5)

## Campo de visión horizontal de la cámara FPV, en grados.
const FOV_RANGE: Vector2 = Vector2(90.0, 170.0)

## Valores por defecto del cuadro (`docs/03` §10).
const DEFAULT_ANGLE: float = 25.0
const DEFAULT_DRY_WEIGHT: float = 0.52
const DEFAULT_BATTERY_WEIGHT: float = 0.18
const DEFAULT_FOV: float = 150.0

## Perfil por defecto: ACTUAL 7 / 67 / 54 en los tres ejes, o sea 70 deg/s de
## centro y 670 deg/s de máximo (`docs/03` §3.6).
const DEFAULT_CURVE: int = ControlProfile.RateCurve.ACTUAL
## Defaults de rates suaves para quien arranca (centro 50 deg/s, máximo 300 deg/s,
## expo 0.25): los fijó el usuario en la prueba del checkpoint 2 porque el perfil
## estilo Betaflight (7/67/54 = 70 y 670 deg/s) resultaba demasiado sensible con
## gamepad. `ControlProfile` conserva 7/67/54 como referencia de la spec (`docs/03` §3.6).
const DEFAULT_RC_RATE: float = 5.0
const DEFAULT_RATE: float = 30.0
const DEFAULT_EXPO: float = 25.0

## Prefijo de las claves de `[rates]`, en el orden de los componentes del `Vector3`
## del perfil: `x` roll, `y` pitch, `z` yaw.
const RATE_AXES: Array[String] = ["roll", "pitch", "yaw"]

## Inclinación de la cámara FPV respecto del dron, en grados.
var angle: float = DEFAULT_ANGLE

## Peso del dron sin batería, en kg.
var dry_weight: float = DEFAULT_DRY_WEIGHT

## Peso de la batería, en kg.
var battery_weight: float = DEFAULT_BATTERY_WEIGHT

## Campo de visión horizontal de la cámara FPV, en grados.
var fov: float = DEFAULT_FOV

## Curva de rates elegida.
var curve: ControlProfile.RateCurve = DEFAULT_CURVE as ControlProfile.RateCurve

## `rc_rate` por eje (`x` roll, `y` pitch, `z` yaw).
var rc_rate: Vector3 = Vector3(DEFAULT_RC_RATE, DEFAULT_RC_RATE, DEFAULT_RC_RATE)

## `rate` por eje.
var rate: Vector3 = Vector3(DEFAULT_RATE, DEFAULT_RATE, DEFAULT_RATE)

## `expo` por eje.
var expo: Vector3 = Vector3(DEFAULT_EXPO, DEFAULT_EXPO, DEFAULT_EXPO)

## Perfil de rates vivo. Nadie lo modifica desde fuera: se reconstruye entero en
## [method rebuild_control_profile], que llaman la carga y el guardado.
var control_profile: ControlProfile = ControlProfile.new()


func _ready() -> void:
	rebuild_control_profile()


## Masa total del dron en kg, que es lo que consume `Drone` (`docs/03` §2.1).
func total_mass() -> float:
	return dry_weight + battery_weight


## Lee `Quad.cfg` y reconstruye el perfil de rates.
##
## Devuelve `""` si todo fue bien —el archivo ausente no es error y solo escribe los
## valores por defecto— o [constant ERROR_KEY] si está corrupto, en cuyo caso se
## vuelve a los valores por defecto y se reescribe (`docs/04` §2).
func load_quad_settings() -> String:
	Global.initialize()
	reset_to_defaults()
	var path := Global.config_path(CONFIG_FILE)
	var config := ConfigFile.new()
	var err := config.load(path)
	if err == ERR_FILE_NOT_FOUND:
		save_quad_settings()
		return ""
	if err != OK:
		Global.log_error(err, "no se pudo leer %s: %s" % [path, error_string(err)])
		save_quad_settings()
		return ERROR_KEY
	angle = _read_range(config, QUAD_SECTION, "angle", ANGLE_RANGE, angle)
	dry_weight = _read_range(config, QUAD_SECTION, "dry_weight", DRY_WEIGHT_RANGE, dry_weight)
	battery_weight = _read_range(config, QUAD_SECTION, "battery_weight",
			BATTERY_WEIGHT_RANGE, battery_weight)
	fov = _read_range(config, QUAD_SECTION, "fov", FOV_RANGE, fov)
	var stored_curve := clampi(int(config.get_value(RATES_SECTION, "curve", int(curve))),
			0, ControlProfile.RateCurve.size() - 1)
	curve = stored_curve as ControlProfile.RateCurve
	for index: int in RATE_AXES.size():
		var axis_name := RATE_AXES[index]
		rc_rate[index] = float(config.get_value(RATES_SECTION,
				"%s_rc_rate" % axis_name, rc_rate[index]))
		rate[index] = float(config.get_value(RATES_SECTION,
				"%s_rate" % axis_name, rate[index]))
		expo[index] = float(config.get_value(RATES_SECTION,
				"%s_expo" % axis_name, expo[index]))
	rebuild_control_profile()
	return ""


## Escribe `Quad.cfg`, reconstruye el perfil y emite [signal settings_updated].
func save_quad_settings() -> void:
	Global.initialize()
	var config := ConfigFile.new()
	config.set_value(QUAD_SECTION, "angle", angle)
	config.set_value(QUAD_SECTION, "dry_weight", dry_weight)
	config.set_value(QUAD_SECTION, "battery_weight", battery_weight)
	config.set_value(QUAD_SECTION, "fov", fov)
	config.set_value(RATES_SECTION, "curve", int(curve))
	for index: int in RATE_AXES.size():
		var axis_name := RATE_AXES[index]
		config.set_value(RATES_SECTION, "%s_rc_rate" % axis_name, rc_rate[index])
		config.set_value(RATES_SECTION, "%s_rate" % axis_name, rate[index])
		config.set_value(RATES_SECTION, "%s_expo" % axis_name, expo[index])
	var path := Global.config_path(CONFIG_FILE)
	var err := config.save(path)
	if err != OK:
		Global.log_error(err, "no se pudo guardar %s: %s" % [path, error_string(err)])
	rebuild_control_profile()
	settings_updated.emit()


## Vuelca la curva y los tres `Vector3` sobre [member control_profile].
func rebuild_control_profile() -> void:
	if control_profile == null:
		control_profile = ControlProfile.new()
	control_profile.curve = curve
	control_profile.rc_rate = rc_rate
	control_profile.rate = rate
	control_profile.expo = expo


## Devuelve el cuadro a sus valores de fábrica y guarda (`QUAD_RESET_QUAD`).
func reset_quad() -> void:
	angle = DEFAULT_ANGLE
	dry_weight = DEFAULT_DRY_WEIGHT
	battery_weight = DEFAULT_BATTERY_WEIGHT
	fov = DEFAULT_FOV
	save_quad_settings()


## Devuelve las rates a la curva ACTUAL 7 / 67 / 54 y guarda (`QUAD_RESET_RATES`).
func reset_rates() -> void:
	curve = DEFAULT_CURVE as ControlProfile.RateCurve
	rc_rate = Vector3(DEFAULT_RC_RATE, DEFAULT_RC_RATE, DEFAULT_RC_RATE)
	rate = Vector3(DEFAULT_RATE, DEFAULT_RATE, DEFAULT_RATE)
	expo = Vector3(DEFAULT_EXPO, DEFAULT_EXPO, DEFAULT_EXPO)
	save_quad_settings()


## Deja todo en valores de fábrica sin guardar ni avisar. Lo usa la carga antes de
## leer el archivo, para que un `.cfg` incompleto no arrastre valores de otro perfil.
func reset_to_defaults() -> void:
	angle = DEFAULT_ANGLE
	dry_weight = DEFAULT_DRY_WEIGHT
	battery_weight = DEFAULT_BATTERY_WEIGHT
	fov = DEFAULT_FOV
	curve = DEFAULT_CURVE as ControlProfile.RateCurve
	rc_rate = Vector3(DEFAULT_RC_RATE, DEFAULT_RC_RATE, DEFAULT_RC_RATE)
	rate = Vector3(DEFAULT_RATE, DEFAULT_RATE, DEFAULT_RATE)
	expo = Vector3(DEFAULT_EXPO, DEFAULT_EXPO, DEFAULT_EXPO)
	rebuild_control_profile()


## Lee un float y lo acota al rango `[x, y]` de [param limits].
func _read_range(config: ConfigFile, section: String, key: String, limits: Vector2,
		fallback: float) -> float:
	return clampf(float(config.get_value(section, key, fallback)), limits.x, limits.y)
