## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Estado de partida y servicios básicos de arranque, compartidos por todo el juego.
##
## WP-01 entregó la parte mínima: rutas de usuario, log que anexa, acumulador de
## errores de arranque y estado de ronda. WP-03 completa [method load_startup_settings],
## que encadena los cinco cargadores de configuración en el orden de `docs/04` §3.1.
extends Node

## Estados por los que pasa una ronda, en orden de guion (`docs/11`).
enum RoundState {
	INTRO,   ## Presentación de la ronda; es saltable.
	BATTLE,  ## Combate en curso.
	VICTORY, ## Se cumplió el objetivo de la ronda.
	DEFEAT,  ## La ciudad cayó por debajo del umbral de integridad.
}

## Directorio de los `.cfg` del jugador. [method initialize] lo crea si falta.
##
## Es **reasignable a propósito**: `tools/settings_check.gd` lo apunta a
## `user://config_check_tmp` para poder escribir y corromper archivos sin tocar la
## configuración real, y lo devuelve a su valor original al terminar. Asignarlo
## crea el directorio nuevo en el acto.
var config_dir: String = "user://config":
	set(value):
		if value == config_dir:
			return
		config_dir = value
		_initialized_dir = ""
		initialize()

## Log de errores. [method log_error] anexa al final; nunca trunca el archivo.
var log_path: String = "user://output.log"

## Claves de traducción `ERR_*` acumuladas durante el arranque. El menú principal
## las muestra con `UI.alert()` y luego vacía la lista.
var startup_errors: Array[String] = []

## Id de catálogo de la ronda elegida en el menú de rondas.
var selected_round: String = ""

## Semilla de la partida en curso; fija el azar de personalidad y de aparición.
var round_seed: int = 0

## Verdadero si el proceso arrancó con `--debug` entre los argumentos de usuario.
var debug: bool = false

## Último valor de [member config_dir] para el que ya se creó la carpeta.
var _initialized_dir: String = ""

var _startup_settings_loaded: bool = false


func _ready() -> void:
	debug = OS.get_cmdline_user_args().has("--debug")


## Crea las carpetas de usuario que el juego necesita. Es idempotente por directorio:
## repetir la llamada con el mismo [member config_dir] no vuelve a tocar el disco.
func initialize() -> void:
	if _initialized_dir == config_dir:
		return
	_initialized_dir = config_dir
	if DirAccess.dir_exists_absolute(config_dir):
		return
	var err := DirAccess.make_dir_recursive_absolute(config_dir)
	if err != OK:
		push_error("No se pudo crear %s: %s" % [config_dir, error_string(err)])


## Ruta absoluta de un archivo de configuración dentro de [member config_dir].
func config_path(file_name: String) -> String:
	return config_dir.path_join(file_name)


## Carga la configuración persistida del jugador, una sola vez por proceso.
##
## Orden fijo de `docs/04` §3.1: juego, gráficos, audio, dron y mapa de entrada.
## Cada cargador devuelve `""` si todo fue bien o una clave `ERR_CONFIG_*` que se
## acumula en [member startup_errors] para que el menú principal la muestre.
func load_startup_settings() -> void:
	if _startup_settings_loaded:
		return
	_startup_settings_loaded = true
	initialize()
	var results: Array[String] = [
		GameSettings.load_game_settings(),
		Graphics.load_graphics_settings(),
		Audio.load_audio_settings(),
		QuadSettings.load_quad_settings(),
		Controls.load_input_map(true),
	]
	for error_key: String in results:
		if not error_key.is_empty():
			startup_errors.append(error_key)


## Anexa al log una línea con el formato `[fecha hora] code message`.
func log_error(code: int, message: String) -> void:
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo abrir %s: %s" % [log_path, error_string(FileAccess.get_open_error())])
		return
	file.seek_end()
	var stamp := Time.get_datetime_string_from_system(false, true)
	var _discard := file.store_line("[%s] %d %s" % [stamp, code, message])
	file.close()


## Muestra un error al jugador como aviso modal, con su sonido (`docs/04` §3.1).
func show_error_popup(error_key: String) -> void:
	UI.play("error")
	await UI.alert(error_key)
