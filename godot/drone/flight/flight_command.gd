## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Orden del piloto para el controlador de vuelo (`docs/03` §3.1).
##
## Es el único canal por el que la radio habla con el núcleo de vuelo: cuatro
## flotantes normalizados, sin unidades físicas. La conversión a velocidad
## angular la hace [ControlProfile] dentro del controlador, no la radio.
##
## `RadioController` (WP-05) reconstruye uno por frame de física; el dron y el
## controlador solo lo leen.
class_name FlightCommand extends RefCounted

## Acelerador en `[0, 1]`. Un stick centrado con retorno al centro da 0.5.
var throttle: float = 0.0

## Alabeo en `[−1, 1]`. Positivo es **ala derecha abajo** (`docs/03` §3.5).
var roll: float = 0.0

## Cabeceo en `[−1, 1]`. Positivo es **morro arriba** (`docs/03` §3.5).
var pitch: float = 0.0

## Guiñada en `[−1, 1]`. Positivo es **morro a la izquierda**, o sea giro CCW
## visto desde arriba, que en ejes de Godot es rotación positiva sobre `+Y`.
var yaw: float = 0.0


## Escribe los cuatro ejes de una vez, ya acotados a su rango.
func set_axes(throttle_value: float, roll_value: float, pitch_value: float,
		yaw_value: float) -> void:
	throttle = clampf(throttle_value, 0.0, 1.0)
	roll = clampf(roll_value, -1.0, 1.0)
	pitch = clampf(pitch_value, -1.0, 1.0)
	yaw = clampf(yaw_value, -1.0, 1.0)


## Copia los cuatro ejes de [param other] sin crear un objeto nuevo.
func copy_from(other: FlightCommand) -> void:
	if other == null:
		return
	throttle = other.throttle
	roll = other.roll
	pitch = other.pitch
	yaw = other.yaw


## Devuelve un duplicado independiente. [RefCounted] no tiene `duplicate()`.
func copy() -> FlightCommand:
	var clone := FlightCommand.new()
	clone.copy_from(self)
	return clone


## Deja el mando en reposo: acelerador a cero y los tres ejes centrados.
func clear() -> void:
	throttle = 0.0
	roll = 0.0
	pitch = 0.0
	yaw = 0.0


## `true` si los tres ejes de actitud están centrados dentro de [param epsilon].
func is_centered(epsilon: float = 0.02) -> bool:
	return absf(roll) <= epsilon and absf(pitch) <= epsilon and absf(yaw) <= epsilon


func _to_string() -> String:
	return "FlightCommand(T %.3f, R %.3f, P %.3f, Y %.3f)" % [throttle, roll, pitch, yaw]
