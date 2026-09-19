## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Helper común de todos los checks headless (`docs/15` §2).
##
## Cada check concreto es una escena `tools/<x>_check.tscn` cuyo nodo raíz lleva
## un script `extends CheckRunner` que sobrescribe [method _run]. El runner se
## ocupa del timeout, de las capturas, del resumen final, del código de salida y
## de dejar la configuración del jugador exactamente como la encontró.
##
## Contrato con CI: el proceso sale con 0 si no hubo fallos y con 1 si los hubo.
##
## **Aislamiento (WP-11)**: por defecto cada check trabaja sobre su propia carpeta de
## configuración, `user://config_check_<pid>`, y escribe su log dentro de ella; al
## terminar la borra y devuelve `Global.config_dir` y `Global.log_path` a lo que eran.
## Así dos suites concurrentes —o una suite y una corrida a mano— no se pisan los `.cfg`
## ni el log, que era el problema anotado al cerrar WP-09. Las capturas van por la misma
## razón a `<shots>/<check_name>/`. Un check que no deba escribir nada en `user://`
## apaga el aislamiento con [member isolate_config].

class_name CheckRunner
extends Node

## Se emite justo antes de ceder el control a [method _run].
signal check_started

## Se emite al terminar, antes de cerrar el proceso.
signal check_finished(ok: bool, failures: int)

## Nombre corto del check; encabeza la línea de resumen. Si queda vacío se
## deduce del nombre del archivo del script.
@export var check_name: String = ""

## Timeout en segundos cuando no se pasa `--timeout=<s>` en los argumentos de usuario.
@export var default_timeout: float = 60.0

## Si es `true` —lo normal—, el check corre con `Global.config_dir` apuntando a
## [member isolated_dir] y no ve ni toca la configuración del jugador. `project_check`
## lo apaga porque no debe escribir nada en `user://`.
@export var isolate_config: bool = true

## Mensajes de los fallos acumulados. Vacío significa check en verde.
var failures: Array[String] = []

## Directorio donde [method shot] guarda las capturas; vacío si no se pasó `--shots=<dir>`.
var shots_dir: String = ""

const _CONFIG_DIR: String = "user://config"

## Prefijo de la carpeta de configuración propia del proceso. El nombre real lleva el
## id del proceso, que es lo que hace que dos checks a la vez no se pisen.
const _ISOLATED_PREFIX: String = "user://config_check"

## Carpeta de configuración propia de este proceso, o `""` si el aislamiento está
## apagado. La borra [method finish].
var isolated_dir: String = ""

var _args: Dictionary = {}
var _timeout: float = 0.0
var _timeout_timer: SceneTreeTimer = null
var _config_snapshot: Dictionary[String, PackedByteArray] = {}
var _finished: bool = false
var _original_config_dir: String = ""
var _original_log_path: String = ""


func _ready() -> void:
	_args = user_args()
	if check_name.is_empty():
		check_name = _script_base_name()
	# Cada check guarda en su propia subcarpeta: dos suites concurrentes escribiendo el
	# mismo directorio se pisaban las capturas.
	shots_dir = _resolve_dir(String(_args.get("shots", "")))
	if not shots_dir.is_empty():
		shots_dir = shots_dir.path_join(check_name)
		var err := DirAccess.make_dir_recursive_absolute(shots_dir)
		if err != OK and err != ERR_ALREADY_EXISTS:
			fail("no se pudo crear el directorio de capturas '%s': %s" % [shots_dir, error_string(err)])
	_timeout = float(_args.get("timeout", default_timeout))
	_snapshot_config()
	if isolate_config:
		_isolate()
	# `ignore_time_scale` en true: el timeout mide segundos reales aunque el check
	# acelere la simulación con `Engine.time_scale`.
	_timeout_timer = get_tree().create_timer(_timeout, true, false, true)
	var _discard := _timeout_timer.timeout.connect(_on_timeout)
	check_started.emit()
	await _run()
	finish()


## Cuerpo del check. Cada check concreto lo sobrescribe; es una corutina, así que
## puede usar `await` libremente. Al volver, el runner llama a [method finish].
func _run() -> void:
	await wait_frames(1)


## Registra un fallo si [param cond] es falsa. No corta la ejecución: un check
## debe reportar todos sus fallos de una sola pasada.
func expect(cond: bool, msg: String) -> void:
	if cond:
		return
	fail(msg)


## Compara dos flotantes con tolerancia. Falla también si [param a] no es finito.
func expect_near(a: float, b: float, tol: float, msg: String) -> void:
	if is_nan(a) or is_inf(a):
		fail("%s (valor no finito: %s)" % [msg, str(a)])
		return
	expect(absf(a - b) <= tol, "%s (esperado %.4f, obtenido %.4f, tol %.4f)" % [msg, b, a, tol])


## Añade un fallo incondicional y lo imprime en el momento.
func fail(msg: String) -> void:
	failures.append(msg)
	print("  FAIL: %s" % msg)


## Restaura el entorno, imprime la línea de resumen y cierra el proceso con 0 o 1.
## Es idempotente: solo la primera llamada tiene efecto.
func finish() -> void:
	if _finished:
		return
	_finished = true
	if _timeout_timer != null:
		if _timeout_timer.timeout.is_connected(_on_timeout):
			_timeout_timer.timeout.disconnect(_on_timeout)
		_timeout_timer = null
	Engine.time_scale = 1.0
	_release_isolation()
	_restore_config()
	var ok := failures.is_empty()
	if ok:
		print("CHECK %s: OK" % check_name)
	else:
		print("CHECK %s: FAIL (%d fallos)" % [check_name, failures.size()])
	check_finished.emit(ok, failures.size())
	get_tree().quit(0 if ok else 1)


## Parsea `OS.get_cmdline_user_args()` a un diccionario `{clave: valor}`.
## `--shots=dir` da `{"shots": "dir"}`, `--timeout=30` da `{"timeout": "30"}` y
## una bandera suelta como `--debug` da `{"debug": "true"}`.
func user_args() -> Dictionary:
	var parsed: Dictionary = {}
	for raw: String in OS.get_cmdline_user_args():
		var arg := raw
		while arg.begins_with("-"):
			arg = arg.substr(1)
		if arg.is_empty():
			continue
		var separator := arg.find("=")
		if separator >= 0:
			parsed[arg.substr(0, separator)] = arg.substr(separator + 1)
		else:
			parsed[arg] = "true"
	return parsed


## Cede el control durante [param ticks] pasos de física.
func wait_physics(ticks: int) -> void:
	for _i: int in ticks:
		await get_tree().physics_frame


## Cede el control durante [param count] frames de proceso.
func wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


## Guarda una captura del viewport como `<shots_dir>/<check_name>_<name>.png`.
## No hace nada si no se pasó `--shots=<dir>`; en `--headless` no hay rasterizado,
## así que solo la usan los checks con ventana (`docs/15` §3.1).
@warning_ignore("shadowed_variable_base_class")
func shot(name: String) -> void:
	if shots_dir.is_empty():
		return
	# Sin ventana que dibujar no hay `frame_post_draw`: esperarla colgaría el check.
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		fail("no se pudo capturar '%s': el viewport no devolvió imagen" % name)
		return
	var err := image.save_png("%s/%s_%s.png" % [shots_dir, check_name, name])
	if err != OK:
		fail("no se pudo guardar la captura '%s': %s" % [name, error_string(err)])


# --- Aislamiento de la configuración ---------------------------------------------------------

## Apunta `Global.config_dir` y `Global.log_path` a una carpeta propia de este proceso.
## Asignar `config_dir` ya crea el directorio (`docs/04` §3.1).
func _isolate() -> void:
	_original_config_dir = Global.config_dir
	_original_log_path = Global.log_path
	isolated_dir = "%s_%d" % [_ISOLATED_PREFIX, OS.get_process_id()]
	# Restos de una corrida anterior que murió sin limpiar: el check tiene que arrancar
	# con la carpeta vacía o leería configuración ajena.
	_purge_dir(isolated_dir)
	Global.config_dir = isolated_dir
	Global.log_path = isolated_dir.path_join("output.log")


## Devuelve `Global` a su estado original y borra la carpeta del proceso. Es idempotente.
func _release_isolation() -> void:
	if isolated_dir.is_empty():
		return
	var mine := isolated_dir
	isolated_dir = ""
	if not _original_log_path.is_empty():
		Global.log_path = _original_log_path
	if not _original_config_dir.is_empty():
		Global.config_dir = _original_config_dir
	_purge_dir(mine)


## Borra los archivos de [param path] y el propio directorio. Nunca toca la carpeta del
## jugador ni ninguna carpeta que no lleve el prefijo del aislamiento.
func _purge_dir(path: String) -> void:
	if path.is_empty() or not path.begins_with(_ISOLATED_PREFIX):
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		var _removed := DirAccess.remove_absolute(path.path_join(file_name))
	var _gone := DirAccess.remove_absolute(path)


func _on_timeout() -> void:
	if _finished:
		return
	fail("timeout de %.1f s" % _timeout)
	finish()


func _script_base_name() -> String:
	var script := get_script() as Script
	if script == null:
		return "check"
	return script.resource_path.get_file().get_basename()


## Normaliza el directorio de capturas: una ruta relativa se interpreta desde la
## raíz del proyecto, para que `--shots=tools/out/shots` funcione igual desde
## cualquier directorio de trabajo.
func _resolve_dir(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return "res://".path_join(path)


## Bytes de un archivo, o un buffer vacío si no se puede leer.
func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


## Copia a memoria los bytes crudos de cada `user://config/*.cfg` existente.
func _snapshot_config() -> void:
	_config_snapshot.clear()
	if not DirAccess.dir_exists_absolute(_CONFIG_DIR):
		return
	for file_name: String in DirAccess.get_files_at(_CONFIG_DIR):
		if not file_name.ends_with(".cfg"):
			continue
		var path := _CONFIG_DIR.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		_config_snapshot[path] = file.get_buffer(file.get_length())
		file.close()


## Reescribe los `.cfg` con sus bytes originales y borra los que el check haya
## creado. Se ejecuta siempre: en verde, en rojo y al expirar el timeout.
func _restore_config() -> void:
	for path: String in _config_snapshot:
		# Con el aislamiento puesto nadie tocó estos archivos: reescribirlos igual sería
		# una carrera entre dos checks concurrentes por el mismo `.cfg`.
		if _read_bytes(path) == _config_snapshot[path]:
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("No se pudo restaurar %s" % path)
			continue
		var _discard := file.store_buffer(_config_snapshot[path])
		file.close()
	if not DirAccess.dir_exists_absolute(_CONFIG_DIR):
		return
	for file_name: String in DirAccess.get_files_at(_CONFIG_DIR):
		if not file_name.ends_with(".cfg"):
			continue
		var path := _CONFIG_DIR.path_join(file_name)
		if _config_snapshot.has(path):
			continue
		var _discard := DirAccess.remove_absolute(path)
