## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Volúmenes de los siete buses de audio, silencio global y persistencia en
## `Audio.cfg` (`docs/04` §3.2).
##
## El silencio se aplica sobre `Master`, de modo que apagar y volver a encender no
## pierde los volúmenes individuales que el jugador dejó puestos.
extends Node

## Se emite después de guardar. El menú de audio redibuja sus deslizadores y el
## `tick` de la interfaz vuelve a sonar con el volumen nuevo.
signal audio_settings_updated

## Nombre del archivo dentro de `Global.config_dir`.
const CONFIG_FILE: String = "Audio.cfg"

## Única sección del archivo.
const SECTION: String = "audio"

## Clave de traducción que `Global.startup_errors` acumula si el archivo está roto.
const ERROR_KEY: String = "ERR_CONFIG_AUDIO"

## Buses de `default_bus_layout.tres`, en el orden en que los lista el menú
## (`docs/04` §3.2 y §4.4). `Master` primero; el resto envía a él.
const BUSES: Array[StringName] = [&"Master", &"Motors", &"Weapons", &"Enemies",
		&"City", &"UI", &"Music"]

## Volumen lineal por defecto de cada bus: 1.0 el general, 0.8 los demás.
const DEFAULT_VOLUMES: Dictionary[StringName, float] = {
	&"Master": 1.0,
	&"Motors": 0.8,
	&"Weapons": 0.8,
	&"Enemies": 0.8,
	&"City": 0.8,
	&"UI": 0.8,
	&"Music": 0.8,
}

## dB que recibe un bus con volumen 0. Se usa en vez del `-inf` que devolvería
## `linear_to_db(0.0)`, que el `AudioServer` no acepta como volumen válido.
const SILENT_DB: float = -80.0

## Volumen lineal `0–1` por bus. Se lee con [method get_volume], que rellena los
## huecos con [constant DEFAULT_VOLUMES].
var volumes: Dictionary[StringName, float] = {}

## Silencio global. Apaga el bus `Master` sin tocar los volúmenes individuales.
var muted: bool = false


func _ready() -> void:
	reset_to_defaults()


## Lee `Audio.cfg` y aplica los volúmenes.
##
## Devuelve `""` si todo fue bien —incluido el caso de que el archivo no exista,
## que no es un error y solo escribe los valores por defecto— o
## [constant ERROR_KEY] si el archivo está corrupto, en cuyo caso se vuelve a los
## valores por defecto y se reescribe para no arrastrar el mismo error en cada
## arranque (`docs/04` §2).
func load_audio_settings() -> String:
	Global.initialize()
	reset_to_defaults()
	var path := Global.config_path(CONFIG_FILE)
	var config := ConfigFile.new()
	var err := config.load(path)
	if err == ERR_FILE_NOT_FOUND:
		save_audio_settings()
		return ""
	if err != OK:
		Global.log_error(err, "no se pudo leer %s: %s" % [path, error_string(err)])
		save_audio_settings()
		return ERROR_KEY
	for bus: StringName in BUSES:
		var stored := float(config.get_value(SECTION, volume_key(bus), DEFAULT_VOLUMES[bus]))
		volumes[bus] = clampf(stored, 0.0, 1.0)
	muted = bool(config.get_value(SECTION, "muted", false))
	update_volumes()
	return ""


## Escribe `Audio.cfg`, aplica los volúmenes y emite [signal audio_settings_updated].
func save_audio_settings() -> void:
	Global.initialize()
	var config := ConfigFile.new()
	for bus: StringName in BUSES:
		config.set_value(SECTION, volume_key(bus), get_volume(bus))
	config.set_value(SECTION, "muted", muted)
	var path := Global.config_path(CONFIG_FILE)
	var err := config.save(path)
	if err != OK:
		Global.log_error(err, "no se pudo guardar %s: %s" % [path, error_string(err)])
	update_volumes()
	audio_settings_updated.emit()


## Vuelca [member volumes] y [member muted] sobre el `AudioServer`.
func update_volumes() -> void:
	for bus: StringName in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		AudioServer.set_bus_volume_db(index, linear_to_volume_db(get_volume(bus)))
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, muted)


## Fija el volumen lineal de un bus y lo aplica. **No** guarda: el menú de audio
## llama a [method save_audio_settings] cuando el jugador suelta el deslizador.
func set_volume(bus: StringName, linear: float) -> void:
	if not DEFAULT_VOLUMES.has(bus):
		push_error("Bus de audio desconocido: %s" % bus)
		return
	volumes[bus] = clampf(linear, 0.0, 1.0)
	update_volumes()


## Volumen lineal `0–1` de un bus; su valor por defecto si nunca se fijó.
func get_volume(bus: StringName) -> float:
	return float(volumes.get(bus, DEFAULT_VOLUMES.get(bus, 0.8)))


## Silencia o restablece el audio general y lo aplica.
func set_muted(value: bool) -> void:
	muted = value
	update_volumes()


## Deja [member volumes] y [member muted] en sus valores por defecto, sin aplicar
## ni guardar. Lo usa [method load_audio_settings] antes de leer el archivo.
func reset_to_defaults() -> void:
	volumes.clear()
	for bus: StringName in BUSES:
		volumes[bus] = DEFAULT_VOLUMES[bus]
	muted = false


## Clave de `Audio.cfg` correspondiente a un bus: `Master` → `master_volume`.
func volume_key(bus: StringName) -> String:
	return "%s_volume" % String(bus).to_lower()


## `linear_to_db()` acotado: el volumen 0 se traduce a [constant SILENT_DB] en vez
## de a `-inf`, que el `AudioServer` rechaza.
func linear_to_volume_db(linear: float) -> float:
	if linear <= 0.0:
		return SILENT_DB
	return maxf(linear_to_db(linear), SILENT_DB)
