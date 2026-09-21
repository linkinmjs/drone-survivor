## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Pinza de medición del tick de física (`docs/15` §5, WP-29).
##
## [PerfProbe] sabe cuánto cuesta cada sistema instrumentado, pero no cuánto cuesta
## **el tick entero**: para eso hacen falta dos marcas de reloj, una antes del primer
## `_physics_process` del árbol y otra después del último. Este nodo es esa marca.
##
## El orden lo decide [member Node.process_physics_priority], que el motor ordena de
## forma global —antes que el orden de árbol—, así que un nodo con
## [constant OPEN_PRIORITY] corre antes que cualquier autoload y uno con
## [constant CLOSE_PRIORITY] después de cualquier hijo del nivel.
##
## Lo cuelga `tools/perf_report.gd` mientras mide y lo saca al terminar; el juego no
## lo lleva nunca. Con [member PerfProbe.enabled] en `false` las dos llamadas son una
## comparación de un booleano.
class_name PerfBracket
extends Node

## Prioridad del borde que abre: por debajo de cualquier nodo del juego.
const OPEN_PRIORITY: int = -1000000

## Prioridad del borde que cierra: por encima de cualquier nodo del juego.
const CLOSE_PRIORITY: int = 1000000

## Qué borde del tick marca este nodo.
enum Edge {
	## Abre el tick: corre primero.
	OPEN,
	## Cierra el tick: corre último.
	CLOSE,
}

## Borde que marca. Fijarlo también fija la prioridad de física.
@export var edge: Edge = Edge.OPEN:
	set(value):
		edge = value
		process_physics_priority = OPEN_PRIORITY if edge == Edge.OPEN else CLOSE_PRIORITY


## Crea una pinza ya configurada para [param which].
static func make(which: Edge) -> PerfBracket:
	var bracket := PerfBracket.new()
	bracket.name = "PerfBracketOpen" if which == Edge.OPEN else "PerfBracketClose"
	bracket.edge = which
	# La medición tiene que seguir corriendo con el árbol en pausa: la ablación de
	# `perf_report` mide los rasgos de render con `get_tree().paused = true`.
	bracket.process_mode = Node.PROCESS_MODE_ALWAYS
	return bracket


func _physics_process(_delta: float) -> void:
	if edge == Edge.OPEN:
		PerfProbe.tick_open()
	else:
		PerfProbe.tick_close()
