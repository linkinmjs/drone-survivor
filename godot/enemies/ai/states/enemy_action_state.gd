## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Base de los estados de la capa de acción (`docs/06` §11.1).
##
## Cada estado es un [b]nodo hijo[/b] del [EnemyFSM], no un valor de `enum`, con
## el contrato de `docs/06` §11.1: `_enter(ctx)`, `_exit()`, `_tick(delta)` y
## `can_exit()`. El estado sólo lleva su propio reloj y hace su parte de la
## coreografía; [b]no enruta[/b]: quién sigue a quién lo decide el FSM leyendo
## [method is_finished]. Esa asimetría es deliberada: sin ella, estados y máquina
## se referenciarían en círculo.
##
## El reloj es un acumulador de `_physics_process` del FSM, nunca un [Timer], así
## que respeta `Engine.time_scale` y los checks pueden acelerar la simulación.
class_name EnemyActionState extends Node

## Acción en curso. Llega por `ctx[&"action"]` en cada [method _enter].
var action: EnemyAction = null

## Duración del estado en segundos. La fija cada estado en [method _enter].
var duration: float = 0.0

## Si el estado termina solo al agotar [member duration]. `NONE` no.
var finite: bool = false

var _elapsed: float = 0.0
var _finished: bool = false


## Id del estado: `NONE`, `TELEGRAPH`, `ACTIVE` o `RECOVER`.
func state_id() -> StringName:
	return &"NONE"


## Entrada en el estado. Las subclases llaman primero a `super._enter(ctx)`.
func _enter(ctx: Dictionary) -> void:
	action = ctx.get(&"action", null) as EnemyAction
	_elapsed = 0.0
	_finished = false


## Salida del estado.
func _exit() -> void:
	action = null


## Un tick de física. Las subclases llaman primero a `super._tick(delta)`.
func _tick(delta: float) -> void:
	_elapsed += delta
	if finite and _elapsed >= duration:
		_finished = true


## `true` cuando el estado puede ceder el turno.
func can_exit() -> bool:
	return _finished


## Segundos dentro del estado.
func elapsed() -> float:
	return _elapsed


## `true` cuando el estado agotó su duración.
func is_finished() -> bool:
	return _finished


## Fuerza el fin del estado (interrupciones y cancelaciones).
func force_finish() -> void:
	_finished = true
