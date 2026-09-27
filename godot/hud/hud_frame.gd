## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## El lienzo común de los dos HUD y la escala que lo mete en pantalla
## (`docs/12` §1.1).
##
## [FlightHUD] y [CombatHUD] dibujan sus componentes en píxeles contra un lienzo
## fijo de [constant LAYOUT_SIZE] y reducen —nunca agrandan— un [Control]
## intermedio, `Frame`, para que ese lienzo entre en el espacio disponible. Los
## dos tenían el número, la fórmula y el piso de escala escritos por separado
## (P2d WP-C, mejoras), y el comentario de `CombatHUD` decía «el mismo que el del
## `FlightHUD`, a propósito» sin que nada lo garantizara: eran dos constantes que
## se podían mover una sin la otra y los dos lienzos dejarían de coincidir.
##
## [b]No es una clase base[/b]: [FlightHUD] es un [Control] y [CombatHUD] un
## [CanvasLayer], así que no pueden compartir ancestro. Lo que se comparte es el
## número y la cuenta, que es lo que tiene que ser el mismo.
class_name HUDFrame extends RefCounted

## Lienzo de referencia de los componentes, en píxeles.
const LAYOUT_SIZE: Vector2 = Vector2(1280.0, 720.0)

## Piso de la escala del marco. Sin él, una ventana de un píxel dejaría el marco
## en escala 0 y los componentes con tamaño infinito.
const MIN_SCALE: float = 0.05


## Escala que le toca al marco con [param available] píxeles disponibles: la que
## mete [constant LAYOUT_SIZE] entero, nunca por encima de 1.0 ni por debajo de
## [constant MIN_SCALE].
static func scale_for(available: Vector2) -> float:
	var usable := available
	if usable.x < 1.0 or usable.y < 1.0:
		usable = LAYOUT_SIZE
	var factor := minf(1.0, minf(usable.x / LAYOUT_SIZE.x, usable.y / LAYOUT_SIZE.y))
	return maxf(factor, MIN_SCALE)


## Deja [param frame] escalado y dimensionado para [param available] píxeles.
static func apply(frame: Control, available: Vector2) -> void:
	if frame == null:
		return
	var usable := available
	if usable.x < 1.0 or usable.y < 1.0:
		usable = LAYOUT_SIZE
	var factor := scale_for(usable)
	frame.position = Vector2.ZERO
	frame.scale = Vector2(factor, factor)
	frame.size = usable / factor
