## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Base de un objetivo de ronda (`docs/11` §5).
##
## Cada objetivo es un nodo hijo del [ObjectiveSequencer] del nivel, así que sus
## `@export` apuntan a los datos de la ronda y no a nodos sueltos de la escena. Las
## subclases sobrescriben los métodos virtuales del final del archivo.
##
## Ciclo de vida: [method setup] una vez, [method start] cada vez que el objetivo
## empieza, [method restart] después de cada reaparición del dron y [method stop] al
## dejarlo. Un objetivo llama a [method finish] cuando alcanza su meta.
##
## **Diferencia con el framework del que viene** (`docs/01` §2.1): una lección del
## simulador reaparecía al piloto en un marcador propio y le imponía el modo de vuelo;
## un objetivo de ronda no toca ni la posición ni el modo del dron —la ronda es una
## sola partida continua— y recibe un [ObjectiveContext] en vez del nivel entero.
## Lo único que se conserva del comportamiento original es la vigilancia de vuelco:
## un dron dado vuelta en el suelo no puede armar, y sin esto la ronda se quedaría
## trabada sin que nada lo avise.
class_name Objective extends Node

## El objetivo alcanzó su meta. Lo escucha el [ObjectiveSequencer].
signal completed

## Producto escalar con [constant Vector3.UP] por debajo del cual el dron cuenta
## como volcado.
const TIPPED_OVER_DOT: float = 0.5

## Altura por debajo de la cual se considera que el dron está en el suelo, en metros.
const TIPPED_OVER_ALTITUDE: float = 0.6

## Segundos volcado tras los que aparece el aviso.
const TIPPED_OVER_SECONDS: float = 0.6

## Segundos volcado tras los que el objetivo pide la reaparición por su cuenta.
const AUTO_RESPAWN_SECONDS: float = 3.0

## Aviso mientras el dron está volcado en el suelo.
const WARN_TIPPED: String = "OBJ_WARN_TIPPED"

## Aviso mientras el controlador está en modo de recuperación.
const WARN_RECOVER: String = "OBJ_WARN_RECOVER"

## Título del objetivo (clave de traducción).
@export var title_key: String = ""

## Descripción de una línea del objetivo (clave de traducción).
@export var objective_key: String = ""

## Segundos entre alcanzar la meta y arrancar el objetivo siguiente (`docs/11` §10).
@export_range(0.0, 10.0, 0.05) var success_delay: float = 0.8

## Referencias del nivel, inyectadas por [RoundManager].
var ctx: ObjectiveContext = null

## Cuerpo del dron, cacheado de [member ctx].
var drone: Drone = null

## Controlador de vuelo del dron, cacheado de [member ctx].
var fc: FlightController = null

## Verdadero mientras el objetivo es el que corre.
var active: bool = false

## Aviso persistente del objetivo (clave de traducción); vacío si todo va bien.
var warning_key: String = ""

var _tipped_time: float = 0.0


## Una vez por ronda, en cuanto el nivel está en pie.
func setup(context: ObjectiveContext) -> void:
	ctx = context
	if ctx != null:
		drone = ctx.drone
		fc = ctx.flight_controller()
	_setup()


## Arranca el objetivo. No mueve el dron ni le cambia el modo de vuelo: la ronda es
## una partida continua (`docs/11` §5).
func start() -> void:
	_on_start()
	restart()
	active = true


## Borra el progreso del objetivo (el dron acaba de reaparecer).
func restart() -> void:
	warning_key = ""
	_tipped_time = 0.0
	_on_restart()


func stop() -> void:
	active = false
	warning_key = ""
	_on_stop()


func finish() -> void:
	if not active:
		return
	active = false
	warning_key = ""
	completed.emit()


func _physics_process(delta: float) -> void:
	if not active:
		return
	_check_crash(delta)
	_tick(delta)


## Verdadero si el dron está armado y por encima de [param min_altitude] metros.
func is_airborne(min_altitude: float) -> bool:
	if drone == null or not is_instance_valid(drone) or fc == null:
		return false
	return fc.is_armed() and drone.global_position.y >= min_altitude


## Vigila el vuelco contra el [Drone] y el [FlightController] de este proyecto
## (`docs/03` §3.3): el controlador deja un dron inclinado en modo de recuperación y
## ahí se niega a armar, así que sólo una reaparición lo devuelve al aire.
##
## Mientras [RespawnController] está reconstruyendo el dron no hay nada que vigilar:
## el cuerpo está congelado bajo el suelo y cualquier aviso sería ruido.
func _check_crash(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		return
	var controller := ctx.respawn_controller() if ctx != null else null
	if controller != null and controller.is_respawning():
		_tipped_time = 0.0
		return
	var upright := drone.global_transform.basis.y.dot(Vector3.UP)
	if drone.global_position.y < TIPPED_OVER_ALTITUDE and upright < TIPPED_OVER_DOT:
		_tipped_time += delta
		if _tipped_time >= AUTO_RESPAWN_SECONDS:
			_tipped_time = 0.0
			warning_key = ""
			if ctx != null and ctx.drone_rig != null and is_instance_valid(ctx.drone_rig):
				var _done := ctx.drone_rig.respawn()
			return
		if _tipped_time >= TIPPED_OVER_SECONDS:
			warning_key = WARN_TIPPED
		return
	_tipped_time = 0.0
	if fc != null and fc.is_armed() and fc.get_mode_key() == FlightController.MODE_RECOVER:
		warning_key = WARN_RECOVER
	elif warning_key == WARN_TIPPED or warning_key == WARN_RECOVER:
		warning_key = ""


# --- Métodos virtuales ------------------------------------------------------------------------

## Una sola vez, cuando el nivel ya está listo.
func _setup() -> void:
	pass


func _on_start() -> void:
	pass


func _on_restart() -> void:
	pass


## Acá se desconecta cada objetivo de `Events`, para que [method
## ObjectiveSequencer.restart_current] no duplique conexiones (`docs/11` §5.1).
func _on_stop() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


## Instrucción de la fase actual (clave de traducción o texto ya traducido).
func get_task_text() -> String:
	return objective_key


## Línea de progreso en vivo, ya traducida.
func get_progress_text() -> String:
	return ""


## Progreso del objetivo entre 0 y 1, o un valor negativo para esconder la barra.
func get_progress() -> float:
	return -1.0


## Direcciones de stick a sugerir: `[izquierdo, derecho]` en convención de pantalla
## (x a la derecha, y hacia abajo, así que «stick arriba» es `Vector2(0, -1)`).
## [constant Vector2.ZERO] significa que no hay sugerencia para ese stick.
func get_stick_hint() -> Array[Vector2]:
	return [Vector2.ZERO, Vector2.ZERO]


## Línea extra bajo «¡Bien hecho!» al completar el objetivo (ya traducida).
func get_success_text() -> String:
	return ""
