## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Una acción asignable a un mando: qué acción del `InputMap` representa, con qué
## etiqueta se muestra y a qué botón o banda de eje está atada (`docs/04` §3.3).
##
## `Controls` mantiene la lista viva (`Controls.action_list`); el menú de controles
## (`docs/04` §4.5) la dibuja fila por fila y `RadioController` (`docs/03` §4) usa
## las entradas de tipo [constant Type.AXIS] para sintetizar pulsaciones cuando el
## eje entra o sale de la banda.
class_name ControllerAction extends RefCounted

## Cómo está atada la acción al mando.
enum Type {
	BUTTON, ## Un botón del joypad ([member button]).
	AXIS,   ## Una banda de un eje analógico ([member axis], [member axis_min], [member axis_max]).
}

## Nombre de la acción en el `InputMap`, por ejemplo `&"fire"`.
var action_name: StringName = &""

## Clave de traducción de la etiqueta que ve el jugador, por ejemplo `"CTRL_ACTION_FIRE"`.
var label_key: String = ""

## Tipo de binding actual.
var type: Type = Type.BUTTON

## Índice de botón del joypad; −1 si el binding no es de botón.
var button: int = -1

## Índice de eje del joypad; −1 si el binding no es de eje.
var axis: int = -1

## Extremo bajo de la banda que activa la acción, en `[−1, 1]`.
var axis_min: float = 0.0

## Extremo alto de la banda que activa la acción, en `[−1, 1]`.
var axis_max: float = 0.0

## Falso mientras la acción no tenga binding de mando (`CTRL_UNBOUND`).
var bound: bool = false


## Construye la acción con su nombre y su etiqueta; el binding se completa después.
func _init(p_action_name: StringName = &"", p_label_key: String = "") -> void:
	action_name = p_action_name
	label_key = p_label_key


## Ata la acción a un botón del joypad.
func bind_button(index: int) -> void:
	type = Type.BUTTON
	button = index
	axis = -1
	axis_min = 0.0
	axis_max = 0.0
	bound = index >= 0


## Ata la acción a la banda `[lo, hi]` de un eje analógico. Los extremos se ordenan
## y se acotan a `[−1, 1]`, así que da igual en qué orden los pase quien llama.
func bind_axis(index: int, lo: float, hi: float) -> void:
	type = Type.AXIS
	axis = index
	button = -1
	axis_min = clampf(minf(lo, hi), -1.0, 1.0)
	axis_max = clampf(maxf(lo, hi), -1.0, 1.0)
	bound = index >= 0


## Quita el binding de mando. La acción sigue existiendo en el `InputMap` con sus
## atajos de teclado, pero el menú la muestra como `CTRL_UNBOUND`.
func clear() -> void:
	type = Type.BUTTON
	button = -1
	axis = -1
	axis_min = 0.0
	axis_max = 0.0
	bound = false


## Verdadero si [param value] cae dentro de la banda de un binding de eje.
## Siempre falso para un binding de botón o sin asignar.
func contains(value: float) -> bool:
	if not bound or type != Type.AXIS:
		return false
	return value >= axis_min and value <= axis_max


## Copia independiente, para que un popup de asignación pueda editar sin tocar
## la lista viva hasta que el jugador confirme.
func duplicate_action() -> ControllerAction:
	var copy := ControllerAction.new(action_name, label_key)
	copy.type = type
	copy.button = button
	copy.axis = axis
	copy.axis_min = axis_min
	copy.axis_max = axis_max
	copy.bound = bound
	return copy
