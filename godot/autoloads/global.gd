## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Estado de partida y servicios básicos de arranque, compartidos por todo el juego.
##
## WP-01 entregó la parte mínima: rutas de usuario, log que anexa, acumulador de
## errores de arranque y estado de ronda. WP-03 completa [method load_startup_settings],
## que encadena los cinco cargadores de configuración en el orden de `docs/04` §3.1.
extends Node

## Estados por los que pasa una ronda (`docs/11`).
##
## [b]El orden del enum no es el orden del guion.[/b] [constant RoundState.ALERT] es
## el estado [b]primero[/b] de la ronda —la pantalla del monitor del taller de
## `docs/narrativa/narrativa.md` §5— pero va anexado al final porque estos valores
## viajan por `Events.round_state_changed(state: int)` y se guardan en trazas y
## capturas: renumerar `INTRO`…`DEFEAT` cambiaría el significado de cada `0`, `1`,
## `2` y `3` ya escritos. El guion real es
## `ALERT → INTRO → BATTLE → VICTORY / DEFEAT`.
enum RoundState {
	INTRO,   ## Presentación de la ronda; es saltable.
	BATTLE,  ## Combate en curso.
	VICTORY, ## Se cumplió el objetivo de la ronda.
	DEFEAT,  ## La ciudad cayó por debajo del umbral de integridad.
	ALERT,   ## Alerta del taller, previa a `INTRO`; es saltable (WP-25b).
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
##
## Se escribe con [method report_startup_error], que **deduplica**: los errores de
## arranque los publica cada instancia del sistema que falla, y el menú mostraba
## treinta y una veces «ERR_ENEMY_PART_NO_BODY» —una por parte— en un solo cuadro
## de diálogo (P2d WP-C, mejoras). Anexar a mano sigue funcionando: lo que
## deduplica es el método.
var startup_errors: Array[String] = []

## Id de catálogo de la ronda elegida en el menú de rondas.
var selected_round: String = ""

## Semilla de la partida en curso; fija el azar de personalidad y de aparición.
var round_seed: int = 0

## Verdadero si el proceso arrancó con `--debug` entre los argumentos de usuario.
var debug: bool = false

## Bandera solo para checks (`docs/11` §11): con `true`, los enemigos que se instancian
## no piensan ni se mueven (la IA y el rig quedan detenidos) para que `round_check` y
## `combat_hud_check` inyecten hechos por el bus sin interferencias. Ningún menú la
## expone y el juego real nunca la enciende.
var debug_freeze_ai: bool = false

## Último valor de [member config_dir] para el que ya se creó la carpeta.
var _initialized_dir: String = ""

var _startup_settings_loaded: bool = false


func _ready() -> void:
	debug = OS.get_cmdline_user_args().has("--debug")


## Anota la clave [param key] en [member startup_errors] si no estaba ya.
func report_startup_error(key: String) -> void:
	if key.is_empty() or startup_errors.has(key):
		return
	startup_errors.append(key)


## Deja el estado de partida listo para la ronda [param id] con la semilla
## [param seed_value] (P2d WP-C, mejoras).
##
## Es el **único** punto que fija las tres cosas a la vez: los tres caminos que
## arrancan una ronda —el menú de rondas y los dos botones de la tarjeta de
## resultado— escribían `selected_round` y `round_seed` cada uno por su lado y
## ninguno apagaba [member debug_freeze_ai], así que un check que la hubiera
## dejado encendida dejaba al jefe congelado en la partida siguiente.
func begin_round(id: String, seed_value: int) -> void:
	selected_round = id
	round_seed = seed_value
	debug_freeze_ai = false


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
