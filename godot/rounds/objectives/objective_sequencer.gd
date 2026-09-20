## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ejecuta los objetivos de la ronda en orden, uno por vez (`docs/11` §5).
##
## Los objetivos son sus hijos [Objective]. Cuando uno se completa, el siguiente
## arranca solo después de su `success_delay`, o en el acto con [method confirm].
##
## **Diferencia con el framework del que viene** (`docs/01` §2.1): la espera entre
## objetivos es un **acumulador** en [method _process] y no un [Timer], que es la
## convención del proyecto (`docs/00` §6), y [method setup] recibe un
## [ObjectiveContext] en vez del nivel del tutorial.
class_name ObjectiveSequencer extends Node

## Arrancó el objetivo [param index].
signal objective_started(index: int)

## El objetivo [param index] alcanzó su meta.
signal objective_succeeded(index: int)

## Se salteó el objetivo [param index] sin completarlo.
signal objective_skipped(index: int)

## Se terminó la cadena entera. No implica victoria (`docs/11` §9.3).
signal all_finished

## Estado del secuenciador.
enum State {
	IDLE,     ## Detenido: nadie corre.
	RUNNING,  ## El objetivo actual está en marcha.
	SUCCESS,  ## El objetivo actual se completó y se espera `success_delay`.
	FINISHED, ## Se terminaron todos los objetivos.
}

## Objetivos en orden de árbol.
var objectives: Array[Objective] = []

## Índice del objetivo en curso, o `-1` si todavía no arrancó ninguno.
var current_index: int = -1

var state: State = State.IDLE

## Referencias del nivel; las guarda [method setup] para poder reconfigurar.
var ctx: ObjectiveContext = null

## Acumulador de la espera entre objetivos, en segundos. Nunca un [Timer].
var _success_delay_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Da de alta los objetivos hijos y les pasa el contexto de la ronda.
func setup(context: ObjectiveContext) -> void:
	ctx = context
	objectives.clear()
	for child: Node in get_children():
		var objective := child as Objective
		if objective == null:
			continue
		objectives.append(objective)
		objective.setup(context)
		if not objective.completed.is_connected(_on_objective_completed):
			var _discard := objective.completed.connect(_on_objective_completed.bind(objective))


## Acumulador de la espera entre objetivos (`docs/00` §6: nada de [Timer]).
func _process(delta: float) -> void:
	if state != State.SUCCESS:
		return
	_success_delay_left -= delta
	if _success_delay_left <= 0.0:
		advance()


## El objetivo en curso, o `null` si no hay ninguno.
func get_current() -> Objective:
	if current_index < 0 or current_index >= objectives.size():
		return null
	return objectives[current_index]


## Cantidad de objetivos de la cadena.
func count() -> int:
	return objectives.size()


func is_running() -> bool:
	return state == State.RUNNING


## Verdadero cuando la cadena entera terminó.
func is_finished() -> bool:
	return state == State.FINISHED


## Arranca el objetivo [param index], deteniendo el que estuviera corriendo.
func start_at(index: int) -> void:
	stop_current()
	if objectives.is_empty():
		state = State.FINISHED
		all_finished.emit()
		return
	current_index = clampi(index, 0, objectives.size() - 1)
	state = State.RUNNING
	objective_started.emit(current_index)
	objectives[current_index].start()


func stop_current() -> void:
	_success_delay_left = 0.0
	var objective := get_current()
	if objective != null and state != State.IDLE and state != State.FINISHED:
		objective.stop()
	state = State.IDLE


func restart_current() -> void:
	if current_index >= 0:
		start_at(current_index)


## Saltea el objetivo actual. En el MVP sólo lo usan el tutorial de P4 y
## `round_check` (`docs/11` §5).
func skip_current() -> void:
	if state != State.RUNNING and state != State.SUCCESS:
		return
	if state == State.RUNNING:
		objective_skipped.emit(current_index)
	advance()


## Pasa al siguiente sin esperar, cuando el actual ya está completado.
func confirm() -> void:
	if state == State.SUCCESS:
		advance()


func advance() -> void:
	var next := current_index + 1
	if next >= objectives.size():
		stop_current()
		current_index = objectives.size() - 1
		state = State.FINISHED
		all_finished.emit()
		return
	start_at(next)


## El dron reapareció: el objetivo en curso borra su progreso parcial.
func on_drone_respawned() -> void:
	var objective := get_current()
	if state == State.RUNNING and objective != null:
		objective.restart()


func _on_objective_completed(objective: Objective) -> void:
	if objective != get_current() or state != State.RUNNING:
		return
	state = State.SUCCESS
	_success_delay_left = maxf(objective.success_delay, 0.05)
	objective_succeeded.emit(current_index)
