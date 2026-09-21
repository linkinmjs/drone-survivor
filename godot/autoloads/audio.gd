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

## dB **base** de cada bus, o sea la mezcla que fija `docs/13` §5.1 y que escribe
## `tools/build_bus_layout.gd` en `default_bus_layout.tres` (WP-27).
##
## [b]Cómo se componen los dos volúmenes[/b]. Hay dos cosas distintas y acá se
## suman, que es lo único que tiene sentido en decibeles:
##
## - La **mezcla** —esta tabla— dice cuánto vale cada familia de sonido respecto de
##   las demás: los motores van 4 dB por debajo del general porque suenan siempre,
##   la música 8 porque es fondo. No la toca el jugador.
## - El **volumen del jugador** —[member volumes], lineal de 0 a 1 y persistido en
##   `Audio.cfg`— es un multiplicador sobre eso.
##
## Multiplicar dos ganancias lineales es sumar sus decibeles, así que el bus
## termina en `base + linear_to_db(lineal)` ([method bus_volume_db]). Con el 0.8
## lineal por defecto son −1.94 dB encima de la base: `Motors` queda en −5.94 dB.
##
## Antes de WP-27 esto no se componía porque la tabla no existía: el layout estaba
## entero a 0 dB y [method update_volumes] escribía directamente la conversión del
## deslizador. Si alguien vuelve a tocar `default_bus_layout.tres`, esta tabla
## tiene que seguirlo; `audio_check` compara las dos.
const BASE_VOLUMES_DB: Dictionary[StringName, float] = {
	&"Master": 0.0,
	&"Motors": -4.0,
	&"Weapons": -3.0,
	&"Enemies": -2.0,
	&"City": -5.0,
	&"UI": -6.0,
	&"Music": -8.0,
}

## Ranura del pasa-bajos dentro del bus `Music` (`docs/13` §5.1). Es el único
## efecto del bus, así que es la 0.
const MUSIC_LOWPASS_SLOT: int = 0

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
		AudioServer.set_bus_volume_db(index, bus_volume_db(bus))
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


## dB que le corresponde a un bus: su mezcla base más el volumen del jugador
## (ver [constant BASE_VOLUMES_DB]). Con el deslizador en 0 el bus se va a
## [constant SILENT_DB] sin sumarle nada, porque «apagado» no tiene grados.
func bus_volume_db(bus: StringName) -> float:
	var linear := get_volume(bus)
	if linear <= 0.0:
		return SILENT_DB
	return maxf(base_volume_db(bus) + linear_to_db(linear), SILENT_DB)


## dB base de un bus (`docs/13` §5.1); 0 si el bus no está en la tabla.
func base_volume_db(bus: StringName) -> float:
	return float(BASE_VOLUMES_DB.get(bus, 0.0))


## Enciende o apaga el pasa-bajos del bus `Music` (`docs/13` §5.1).
##
## Es lo que hace que la música se enturbie al pausar: 600 Hz de corte con
## resonancia 0.5 dejan los graves y se llevan todo el detalle, que es el gesto
## clásico de «el juego se fue a otra habitación». No es un fundido: la música
## sigue en su sitio y al reanudar vuelve entera sin saltar de fase.
##
## No falla si el bus o el efecto no existen —un check puede correr con un layout
## mínimo—: devuelve `false` y no toca nada.
func set_music_lowpass(enabled: bool) -> bool:
	var index := AudioServer.get_bus_index(&"Music")
	if index < 0 or AudioServer.get_bus_effect_count(index) <= MUSIC_LOWPASS_SLOT:
		return false
	AudioServer.set_bus_effect_enabled(index, MUSIC_LOWPASS_SLOT, enabled)
	return true


## `true` si el pasa-bajos de `Music` está encendido ahora mismo.
func is_music_lowpass_enabled() -> bool:
	var index := AudioServer.get_bus_index(&"Music")
	if index < 0 or AudioServer.get_bus_effect_count(index) <= MUSIC_LOWPASS_SLOT:
		return false
	return AudioServer.is_bus_effect_enabled(index, MUSIC_LOWPASS_SLOT)
