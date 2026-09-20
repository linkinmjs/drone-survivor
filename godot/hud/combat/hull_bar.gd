## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Arco de casco del `CombatHUD` (`docs/12` §4.1 y §8).
##
## Espejo exacto del arco de energía, a la derecha del centro y con el mismo radio y
## grosor, pero partido en **cuatro segmentos de 25 %**: el segmento activo se vacía
## y los que ya cayeron quedan en `DANGER`. Cuatro trozos y no una barra continua
## porque el casco del dron es la única barra cuyo valor el piloto necesita leer de
## reojo, sin mirar: contar tres muescas encendidas es instantáneo, medir el largo de
## una barra no.
##
## Se alimenta de `Events.hull_changed(ratio)` y no consulta al [Hull]. Al bajar,
## destella blanco [constant FLASH_SECONDS] (`docs/12` §4.1).
class_name HUDHullBar
extends CombatHUDComponent

## Radio del arco, igual al de [HUDEnergyBar] (`docs/12` §8).
const RADIUS: float = 190.0

## Grosor del trazo, en píxeles.
const THICKNESS: float = 8.0

## Segmentos del casco (`docs/12` §8).
const SEGMENTS: int = 4

## Apertura total del arco, en grados. La misma que la del arco de energía.
const SPAN_DEG: float = 100.0

## Hueco entre dos segmentos, en grados.
const GAP_DEG: float = 3.0

## Segmentos con los que se tesela cada tramo.
const ARC_STEPS: int = 20

## Duración del destello blanco al recibir daño, en segundos (`docs/12` §4.1).
const FLASH_SECONDS: float = 0.12

## Centro del bloque de texto respecto del centro del lienzo, espejo exacto del de
## [constant HUDEnergyBar.LABEL_OFFSET]: debajo del extremo inferior del arco.
const LABEL_OFFSET: Vector2 = Vector2(122.0, 172.0)

## Ancho del bloque de texto, en píxeles.
const LABEL_WIDTH: float = 150.0

## Clave del rótulo permanente.
const LABEL_KEY: String = "HUD_HULL"

## Razón de casco publicada por el bus, de 0 a 1.
var ratio: float = 1.0

var _flash: float = 0.0


func _tick(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


## `Events.hull_changed`. Un valor que sube —una reparación, un respawn— no destella.
func set_hull(new_ratio: float) -> void:
	var clamped := clampf(new_ratio, 0.0, 1.0) if is_finite(new_ratio) else 0.0
	if is_equal_approx(clamped, ratio):
		return
	if clamped < ratio:
		_flash = FLASH_SECONDS
	ratio = clamped
	queue_redraw()


## Segmentos que ya **no** están enteros, de 0 a [constant SEGMENTS].
##
## Es la cuenta que fija `docs/12` §9.2 fila 2: `hull_changed(0.55)` da **2**, porque
## con 0.55 sólo dos cuartos siguen completos —el tercero está a medias y el cuarto
## vacío—. O sea: `SEGMENTS − ⌊ratio · SEGMENTS⌋`, no la cantidad de segmentos
## totalmente vacíos, que sería 1.
func broken_segments() -> int:
	return clampi(SEGMENTS - int(floor(ratio * float(SEGMENTS) + 1e-4)), 0, SEGMENTS)


## `true` mientras dura el destello blanco del último golpe.
func is_flashing() -> bool:
	return _flash > 0.0


func _draw() -> void:
	if not begin_draw():
		return
	var origin := centre()
	# Espejo del arco de energía: −50°..+50° es el mismo tramo de 100° reflejado.
	var half := deg_to_rad(SPAN_DEG) * 0.5
	var per_segment := deg_to_rad(SPAN_DEG) / float(SEGMENTS)
	var gap := deg_to_rad(GAP_DEG) * 0.5
	var per_ratio := 1.0 / float(SEGMENTS)
	var flash := clampf(_flash / FLASH_SECONDS, 0.0, 1.0)

	for index: int in SEGMENTS:
		# El índice 0 es el segmento de **abajo**, para que el casco se vacíe de
		# arriba hacia abajo igual que la energía.
		var start := half - per_segment * float(index + 1) + gap
		var end := half - per_segment * float(index) - gap
		var low := per_ratio * float(index)
		var fill := clampf((ratio - low) / per_ratio, 0.0, 1.0)
		draw_arc(origin, RADIUS, start, end, ARC_STEPS, CombatHUDPalette.SHADOW,
				THICKNESS + 3.0, true)
		if fill <= 0.0:
			# Segmento perdido: queda encendido en rojo, no vacío. Un casco roto es
			# información permanente, no un hueco.
			draw_arc(origin, RADIUS, start, end, ARC_STEPS,
					CombatHUDPalette.with_alpha(CombatHUDPalette.DANGER, 0.85),
					THICKNESS, true)
			continue
		draw_arc(origin, RADIUS, start, end, ARC_STEPS, CombatHUDPalette.TRACK,
				THICKNESS, true)
		var colour := CombatHUDPalette.ACCENT
		if flash > 0.0:
			colour = colour.lerp(Color.WHITE, flash)
		draw_arc(origin, RADIUS, start, start + (end - start) * fill, ARC_STEPS,
				colour, THICKNESS, true)

	# Mismo criterio que el arco de energía: el texto va abajo y adentro del arco.
	var font := HUDDraw.font_mono()
	var label_pos := origin + LABEL_OFFSET - Vector2(LABEL_WIDTH * 0.5, 0.0)
	HUDDraw.text(self, font, label_pos, tr(LABEL_KEY), 17, HORIZONTAL_ALIGNMENT_CENTER,
			LABEL_WIDTH, CombatHUDPalette.TEXT_DIM)
	var colour := CombatHUDPalette.ACCENT if ratio > 0.25 else CombatHUDPalette.DANGER
	HUDDraw.text(self, font, label_pos + Vector2(0.0, 26.0),
			number_text("%d%%" % [roundi(ratio * 100.0)]), 22, HORIZONTAL_ALIGNMENT_CENTER,
			LABEL_WIDTH, colour)
