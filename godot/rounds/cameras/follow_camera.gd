## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cámara de seguimiento en tercera persona (`docs/03` §5, cámaras alternativas del
## nivel).
##
## Cuelga de una correa: se mantiene a [member distance] metros por detrás del objetivo
## —en la dirección horizontal en la que ya estaba, así que no gira con el dron cuando
## el dron da vueltas— y a [member height] metros por encima, y siempre lo mira. Es lo
## que permite ver el dron desde fuera hasta que WP-06 entregue la cámara FPV.
##
## No pilota ni toca la física: solo escribe su propia transform. Como hereda el
## `process_mode` del nivel (`PROCESS_MODE_PAUSABLE`), en pausa se queda quieta.
##
## Corrección de la revisión de WP-11 — **el seguimiento vive en `_physics_process`**.
## Seguía en `_process`, o sea a la tasa de refresco de la pantalla, a un [Drone] que
## solo mueve su transformada una vez por tick de física (100 Hz, `docs/03` §2.5). Con
## el objetivo congelado entre ticks la cámara seguía avanzando hacia él, así que el
## dron temblaba en el encuadre a cualquier tasa distinta de 100 Hz. La otra salida
## —`physics_interpolation_mode`— no sirve acá: la interpolación de física está apagada
## en `project.godot` (`physics/common/physics_interpolation` no está puesta) y
## encenderla es un cambio de proyecto, no de cámara. Yendo en el tick de física la
## cámara y el cuerpo se mueven en el mismo paso y la imagen queda quieta.
class_name FollowCamera
extends Camera3D

## Debajo de esta distancia horizontal la dirección de la correa no es fiable y se
## reutiliza la anterior.
const MIN_PLANAR: float = 0.05

## Nodo al que sigue. Lo cablea el nivel.
@export var target: Node3D

## Distancia horizontal al objetivo, en metros.
@export_range(1.0, 60.0, 0.1) var distance: float = 8.0

## Altura sobre el objetivo, en metros.
@export_range(0.0, 40.0, 0.1) var height: float = 2.5

## Cuánto se acerca la cámara a su posición deseada por segundo. Más alto es más duro.
@export_range(0.5, 30.0, 0.1) var smoothing: float = 5.0

## Punto que mira dentro del objetivo, en su espacio local.
@export var look_offset: Vector3 = Vector3(0.0, 0.4, 0.0)


func _ready() -> void:
	_place(1.0)


func _physics_process(delta: float) -> void:
	PerfProbe.begin(&"drone_misc")
	_place(clampf(smoothing * delta, 0.0, 1.0))
	PerfProbe.end(&"drone_misc")


## Mueve la cámara [param weight] del camino hacia su posición deseada y mira al
## objetivo. Con `1.0` salta directamente, que es lo que hace falta al entrar al nivel.
func _place(weight: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var focus := target.global_position + look_offset
	var leash := global_position - focus
	leash.y = 0.0
	if leash.length() < MIN_PLANAR:
		leash = Vector3.BACK * distance
	var desired := focus + leash.normalized() * distance + Vector3.UP * height
	global_position = global_position.lerp(desired, weight)
	look_at(focus, Vector3.UP)
