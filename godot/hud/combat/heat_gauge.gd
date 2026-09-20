## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Barra de calor del arma (`docs/12` §4.1 y §8).
##
## 180 × 6 px, [constant OFFSET_Y] px por debajo del retículo, con degradado
## `ACCENT` → `DANGER`. Se alimenta de `Events.weapon_heat_changed(ratio, overheated)`,
## que `WeaponMount` publica con umbral (`docs/08` §2.4): no llega un evento por
## cuadro, así que la barra sólo se redibuja cuando el arma tiene algo que decir o
## cuando está parpadeando.
##
## Va **debajo** del retículo y no arriba porque el aviso de sobrecalentamiento tiene
## que caer en el mismo golpe de vista que la mira sin taparle el objetivo.
class_name HUDHeatGauge
extends CombatHUDComponent

## Ancho de la barra, en píxeles (`docs/12` §8).
const WIDTH: float = 180.0

## Alto de la barra, en píxeles (`docs/12` §8).
const HEIGHT: float = 6.0

## Distancia del centro del retículo al borde superior de la barra (`docs/12` §8).
const OFFSET_Y: float = 46.0

## Parpadeo del bloqueo por sobrecalentamiento, en Hz.
const BLINK_HZ: float = 4.0

## Opacidad del semiciclo apagado del parpadeo.
const BLINK_DIM: float = 0.30

## Razón a partir de la cual se dibuja la muesca de aviso.
const WARN_RATIO: float = 0.75

## Clave del rótulo permanente.
const LABEL_KEY: String = "HUD_HEAT"

## Clave del aviso de bloqueo.
const LOCK_KEY: String = "HUD_HEAT_LOCK"

## Calor del arma, de 0 a 1.
var ratio: float = 0.0

## `true` mientras el arma esté bloqueada por sobrecalentamiento.
var overheated: bool = false

var _time: float = 0.0


func _tick(delta: float) -> void:
	if not overheated:
		return
	_time += delta
	queue_redraw()


## `Events.weapon_heat_changed`.
func set_heat(new_ratio: float, new_overheated: bool) -> void:
	var clamped := clampf(new_ratio, 0.0, 1.0) if is_finite(new_ratio) else 0.0
	if is_equal_approx(clamped, ratio) and new_overheated == overheated:
		return
	ratio = clamped
	if new_overheated != overheated:
		overheated = new_overheated
		_time = 0.0
	queue_redraw()


## `true` cuando el arma está bloqueada. Lo consulta `combat_hud_check`
## (`docs/12` §9.2 fila 2).
func is_locked() -> bool:
	return overheated


func _draw() -> void:
	if not begin_draw():
		return
	var origin := centre() + Vector2(0.0, OFFSET_Y)
	var rect := Rect2(origin - Vector2(WIDTH * 0.5, 0.0), Vector2(WIDTH, HEIGHT))
	var alpha := 1.0
	if overheated:
		var lit := fposmod(_time * BLINK_HZ, 1.0) < 0.5
		alpha = 1.0 if lit else BLINK_DIM

	draw_rect(rect.grow(1.5), CombatHUDPalette.SHADOW, true)
	draw_rect(rect, CombatHUDPalette.TRACK, true)

	if ratio > 0.0:
		# El degradado se pinta por franjas: una barra de 180 px con 18 tramos no
		# tiene banding visible y no necesita ni textura ni shader (`docs/12` §4).
		var filled := WIDTH * ratio
		var steps := maxi(1, int(ceil(filled / 10.0)))
		for index: int in steps:
			var from := filled * float(index) / float(steps)
			var to := filled * float(index + 1) / float(steps)
			var colour := CombatHUDPalette.heat_gradient((from + to) * 0.5 / WIDTH)
			if overheated:
				colour = CombatHUDPalette.DANGER
			draw_rect(Rect2(rect.position + Vector2(from, 0.0),
					Vector2(maxf(to - from, 1.0), HEIGHT)),
					CombatHUDPalette.with_alpha(colour, alpha), true)

	# Muesca de aviso: el punto a partir del cual conviene soltar el gatillo.
	var warn_x := rect.position.x + WIDTH * WARN_RATIO
	HUDDraw.line(self, Vector2(warn_x, rect.position.y - 3.0),
			Vector2(warn_x, rect.end.y + 3.0), 1.0,
			CombatHUDPalette.with_alpha(CombatHUDPalette.TEXT, 0.45))

	var font := HUDDraw.font_mono()
	if overheated:
		HUDDraw.text(self, font, origin + Vector2(-WIDTH * 0.5, HEIGHT + 22.0),
				tr(LOCK_KEY), 18, HORIZONTAL_ALIGNMENT_CENTER, WIDTH,
				CombatHUDPalette.with_alpha(CombatHUDPalette.DANGER, alpha))
		return
	if ratio >= WARN_RATIO:
		HUDDraw.text(self, font, origin + Vector2(-WIDTH * 0.5, HEIGHT + 22.0),
				"%s %s" % [tr(LABEL_KEY), number_text("%d%%" % [roundi(ratio * 100.0)])],
				16, HORIZONTAL_ALIGNMENT_CENTER, WIDTH, CombatHUDPalette.TEXT_DIM)
