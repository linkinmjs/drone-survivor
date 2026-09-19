## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Soporte de la cámara FPV dentro del dron (`docs/03` §5 y §8, `docs/13` §6).
##
## Es el **único** nodo que escribe la transformada de la cámara. La `FPVCamera`
## cuelga de acá con transformada identidad y nunca se mueve por su cuenta: todo lo
## que desplace o gire la vista —la inclinación del hangar hoy, la sacudida de
## trauma en WP-28— pasa por este nodo. Así, quien quiera saber hacia dónde mira el
## piloto lee una sola transformada y no tiene que componer dos.
##
## Lo que aplica hoy:
## - **Inclinación**: `rotation.x = deg_to_rad(QuadSettings.angle)`, con el ángulo
##   positivo levantando el morro de la cámara, que es la convención del hangar
##   (`docs/04` §3.6, rango −20..80°). Se refresca sola en `settings_updated`; el
##   [DroneRig] además la empuja al arrancar (`docs/03` §8).
##
## Lo que **no** aplica todavía: la sacudida. [method add_trauma] existe con la firma
## fija de `docs/03` §9 y no hace nada; el modelo de trauma (ruido simplex, caída de
## 1.4/s, desplazamiento proporcional a `trauma²`) es de WP-28 (`docs/13` §6) y se
## implementa acá sin tocar a nadie más.
class_name CameraRig
extends Node3D

## Inclinación aplicada ahora mismo, en grados. Es lo que se leyó de `QuadSettings`.
var _tilt_degrees: float = 0.0


func _ready() -> void:
	set_tilt_degrees(QuadSettings.angle)
	var _discard := QuadSettings.settings_updated.connect(_on_quad_settings_updated)


## Inclina la cámara [param angle] grados sobre el eje X del dron. Positivo levanta
## la vista, que es lo que hace un cuadro de carrera para volar rápido sin cabecear.
func set_tilt_degrees(angle: float) -> void:
	_tilt_degrees = clampf(angle, QuadSettings.ANGLE_RANGE.x, QuadSettings.ANGLE_RANGE.y)
	rotation = Vector3(deg_to_rad(_tilt_degrees), 0.0, 0.0)


## La inclinación aplicada, en grados.
func get_tilt_degrees() -> float:
	return _tilt_degrees


## Sacude la cámara. **No-op documentado**: la firma es la de `docs/03` §9 para que
## las armas y los impactos ya puedan llamarla, pero el modelo de trauma llega en
## WP-28 (`docs/13` §6). Hasta entonces la vista no se mueve.
@warning_ignore("unused_parameter")
func add_trauma(amount: float) -> void:
	pass


## Trauma acumulado. Siempre `0.0` hasta WP-28 (`docs/13` §6).
func get_trauma() -> float:
	return 0.0


func _on_quad_settings_updated() -> void:
	set_tilt_degrees(QuadSettings.angle)
