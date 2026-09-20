## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Franja de integridad de la ciudad (`docs/12` §4.1 y §8).
##
## 640 × 10 px bajo la [HUDBossBar], con una muesca fija en [constant DEFEAT_RATIO] —el
## umbral de derrota de `docs/10` §5 y `docs/11` §4.1— y un destello de
## [constant FLASH_SECONDS] en `DANGER` cada vez que cae un edificio.
##
## Es el **único** componente que sigue visible en modo cinemático (`docs/12` §4.2):
## durante la cinemática de apertura el jugador todavía no tiene el mando, pero la
## ciudad ya es lo que está en juego y la franja es lo que lo dice sin una línea de
## texto.
##
## `Events.city_integrity_changed` es monótona decreciente (`docs/02` §5.1), así que
## la barra nunca vuelve a subir; el único caso en que lo hace es el reinicio de la
## ronda, que llega como un `1.0` y se acepta sin destello.
class_name HUDCityBar
extends CombatHUDComponent

## Ancho de la franja, en píxeles (`docs/12` §8).
const WIDTH: float = 640.0

## Alto de la franja, en píxeles (`docs/12` §8).
const HEIGHT: float = 10.0

## Distancia del borde superior del lienzo a la franja, en píxeles. Queda justo
## debajo del bloque de barras de la [HUDBossBar].
const TOP_MARGIN: float = 184.0

## Umbral de derrota, donde va la muesca fija (`docs/12` §8).
const DEFEAT_RATIO: float = 0.35

## Duración del destello al caer un edificio, en segundos (`docs/12` §4.1).
const FLASH_SECONDS: float = 0.25

## Clave del rótulo permanente.
const LABEL_KEY: String = "HUD_CITY"

## Integridad publicada por el bus, de 0 a 1.
var ratio: float = 1.0

var _flash: float = 0.0


func _tick(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


## `Events.city_integrity_changed`.
func set_integrity(new_ratio: float) -> void:
	var clamped := clampf(new_ratio, 0.0, 1.0) if is_finite(new_ratio) else 0.0
	if is_equal_approx(clamped, ratio):
		return
	ratio = clamped
	queue_redraw()


## `Events.building_destroyed`. El valor del edificio no cambia el dibujo: lo que se
## anuncia es que **cayó uno**, y la magnitud ya la cuenta la barra.
func flash() -> void:
	_flash = FLASH_SECONDS
	queue_redraw()


## `true` mientras dura el destello. `docs/12` §9.2 fila 5 exige que termine antes de
## los 300 ms.
func is_flashing() -> bool:
	return _flash > 0.0


func _draw() -> void:
	if not begin_draw():
		return
	var rect := Rect2(Vector2(centre().x - WIDTH * 0.5, TOP_MARGIN),
			Vector2(WIDTH, HEIGHT))
	draw_rect(rect.grow(1.5), CombatHUDPalette.SHADOW, true)
	draw_rect(rect, CombatHUDPalette.TRACK, true)

	var flash := clampf(_flash / FLASH_SECONDS, 0.0, 1.0)
	var colour := CombatHUDPalette.ACCENT
	if ratio <= DEFEAT_RATIO * 1.15:
		colour = CombatHUDPalette.DANGER
	if flash > 0.0:
		colour = colour.lerp(CombatHUDPalette.DANGER, flash)
	if ratio > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)),
				colour, true)

	# Muesca del umbral de derrota: la línea a partir de la cual se pierde la ronda.
	var notch_x := rect.position.x + WIDTH * DEFEAT_RATIO
	HUDDraw.line(self, Vector2(notch_x, rect.position.y - 4.0),
			Vector2(notch_x, rect.end.y + 4.0), 2.0, CombatHUDPalette.DANGER)

	var font := HUDDraw.font_mono()
	HUDDraw.text(self, font, Vector2(rect.position.x - 130.0, rect.end.y - 1.0),
			tr(LABEL_KEY), 17, HORIZONTAL_ALIGNMENT_RIGHT, 120.0,
			CombatHUDPalette.TEXT_DIM)
	HUDDraw.text(self, font, Vector2(rect.end.x + 10.0, rect.end.y - 1.0),
			number_text("%d%%" % [roundi(ratio * 100.0)]), 18,
			HORIZONTAL_ALIGNMENT_LEFT, 120.0, colour)
