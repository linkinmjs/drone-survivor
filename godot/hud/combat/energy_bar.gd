## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Arco de energía del `CombatHUD` (`docs/12` §4.1 y §8).
##
## Se alimenta de `Events.energy_changed(ratio, critical)` y no consulta al
## [EnergySystem]: la histéresis 15 %/18 % la resuelve `docs/09` §2.2 y el HUD
## **obedece**. Si el HUD decidiera por su cuenta cuándo parpadear, dos sistemas
## estarían llevando el mismo umbral y se separarían en la primera corrección de
## balance.
##
## ## Discrepancia registrada con `docs/12` §4.1
##
## La tabla dice «arco a la izquierda del centro, 220°→320°». Las dos mitades de esa
## frase no pueden ser ciertas a la vez: en la convención de [method CanvasItem.draw_arc]
## —`0` a la derecha, ángulos crecientes en el sentido de las agujas porque la `y` de
## pantalla crece hacia abajo— el tramo 220°→320° cae **arriba** del centro, no a la
## izquierda. Manda la **posición**, que es la que el brief de WP-22 repite («arco
## izquierdo») y la que hace que el arco sea el espejo del casco: se conserva la
## apertura de 100° y se la centra en 180°, o sea [constant START_DEG] → [constant END_DEG].
class_name HUDEnergyBar
extends CombatHUDComponent

## Radio del arco, en píxeles (`docs/12` §8).
const RADIUS: float = 190.0

## Grosor del trazo del arco, en píxeles (`docs/12` §8).
const THICKNESS: float = 8.0

## Extremo inicial del arco, en grados. Ver la discrepancia del encabezado.
const START_DEG: float = 130.0

## Extremo final del arco, en grados.
const END_DEG: float = 230.0

## Segmentos con los que se teselan los arcos. Con radio 190 px son ~3 px por cuerda.
const ARC_STEPS: int = 64

## Por debajo de esta razón el arco parpadea (`docs/12` §8). Es sólo un respaldo: el
## que manda es el `critical` que llega por el bus.
const LOW_RATIO: float = 0.15

## Parpadeo del estado crítico, en Hz (`docs/12` §8).
const BLINK_HZ: float = 3.0

## Opacidad del semiciclo apagado del parpadeo.
const BLINK_DIM: float = 0.22

## Centro del bloque de texto respecto del centro del lienzo, en píxeles.
##
## Va **debajo del extremo inferior del arco**, que está en
## `(cos 130°, sin 130°) · 190 = (−122, +146)`: por debajo de esa `y` no hay trazo,
## así que el texto no se monta sobre el arco ni se acerca al retículo. A la altura
## del centro chocaría con la mira; del lado de afuera, con las cintas laterales del
## `FlightHUD`, que están a ±213 px del centro en este mismo lienzo.
const LABEL_OFFSET: Vector2 = Vector2(-122.0, 172.0)

## Ancho del bloque de texto, en píxeles.
const LABEL_WIDTH: float = 150.0

## Clave del rótulo permanente.
const LABEL_KEY: String = "HUD_ENERGY"

## Clave del aviso de energía crítica.
const LOW_KEY: String = "HUD_ENERGY_LOW"

## Razón de energía publicada por el bus, de 0 a 1.
var ratio: float = 1.0

## `true` mientras `docs/09` mantenga el estado crítico.
var critical: bool = false

var _time: float = 0.0


func _tick(delta: float) -> void:
	if not critical:
		return
	_time += delta
	queue_redraw()


## `Events.energy_changed`. El HUD no interpreta: dibuja lo que le dicen.
func set_energy(new_ratio: float, new_critical: bool) -> void:
	var clamped := clampf(new_ratio, 0.0, 1.0) if is_finite(new_ratio) else 0.0
	if is_equal_approx(clamped, ratio) and new_critical == critical:
		return
	ratio = clamped
	if new_critical != critical:
		critical = new_critical
		_time = 0.0
	queue_redraw()


## `true` cuando el arco está en estado de parpadeo. Lo consulta `combat_hud_check`
## (`docs/12` §9.2 fila 2).
func is_blinking() -> bool:
	return critical or ratio < LOW_RATIO


func _draw() -> void:
	if not begin_draw():
		return
	var origin := centre()
	var start := deg_to_rad(START_DEG)
	var end := deg_to_rad(END_DEG)
	var colour := CombatHUDPalette.ACCENT
	var alpha := 1.0
	if is_blinking():
		colour = CombatHUDPalette.DANGER
		# Onda cuadrada y no senoidal: un aviso de batería tiene que leerse como un
		# aviso, no como una respiración.
		var lit := fposmod(_time * BLINK_HZ, 1.0) < 0.5
		alpha = 1.0 if lit else BLINK_DIM

	# Carcasa: el arco entero apagado, para que se vea cuánto falta y no sólo cuánto queda.
	draw_arc(origin, RADIUS, start, end, ARC_STEPS, CombatHUDPalette.SHADOW,
			THICKNESS + 3.0, true)
	draw_arc(origin, RADIUS, start, end, ARC_STEPS, CombatHUDPalette.TRACK, THICKNESS, true)

	# El relleno crece desde el extremo de abajo, que es el que queda más cerca del
	# pulgar izquierdo en la pantalla y el que el piloto mira de reojo.
	if ratio > 0.0:
		var filled := start + (end - start) * ratio
		draw_arc(origin, RADIUS, start, filled, ARC_STEPS,
				CombatHUDPalette.with_alpha(colour, alpha), THICKNESS, true)

	# Muescas de cuarto: sin ellas un arco es un gesto, no una medida.
	for step: int in 3:
		var fraction := 0.25 * float(step + 1)
		var angle := start + (end - start) * fraction
		var direction := Vector2.from_angle(angle)
		HUDDraw.line(self, origin + direction * (RADIUS - THICKNESS * 0.5 - 1.0),
				origin + direction * (RADIUS + THICKNESS * 0.5 + 1.0), 1.0,
				CombatHUDPalette.with_alpha(CombatHUDPalette.TEXT, 0.35))

	# El aviso de energía crítica **reemplaza** al rótulo en vez de sumarse debajo: una
	# tercera línea caería sobre el mensaje de armado del `FlightHUD`, y de paso el
	# cambio de palabra hace el aviso más difícil de ignorar que un texto extra.
	var font := HUDDraw.font_mono()
	var label_pos := origin + LABEL_OFFSET - Vector2(LABEL_WIDTH * 0.5, 0.0)
	if is_blinking():
		HUDDraw.text(self, font, label_pos, tr(LOW_KEY), 16, HORIZONTAL_ALIGNMENT_CENTER,
				LABEL_WIDTH, CombatHUDPalette.with_alpha(CombatHUDPalette.DANGER, alpha))
	else:
		HUDDraw.text(self, font, label_pos, tr(LABEL_KEY), 17, HORIZONTAL_ALIGNMENT_CENTER,
				LABEL_WIDTH, CombatHUDPalette.TEXT_DIM)
	HUDDraw.text(self, font, label_pos + Vector2(0.0, 26.0),
			number_text("%d%%" % [roundi(ratio * 100.0)]), 22, HORIZONTAL_ALIGNMENT_CENTER,
			LABEL_WIDTH, CombatHUDPalette.with_alpha(colour, maxf(alpha, 0.55)))
