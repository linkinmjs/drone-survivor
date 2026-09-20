## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Rótulo de la cinemática de apertura (`docs/12` §4.2).
##
## Durante `INTRO` el `CombatHUD` muestra **sólo** la [HUDCityBar] y este rótulo con
## el `name_key` y el `goal_key` de la ronda, más `ROUND_INTRO_SKIP`. Nada más: el
## piloto todavía no tiene el mando, así que una mira, un arco de energía o un
## cronómetro en cero serían información de un juego que aún no empezó.
##
## Es el único componente que [method CombatHUD.set_cinematic] deja encendido junto
## con la franja de ciudad, y el único que se apaga al pasar a `BATTLE`.
class_name HUDIntroBanner
extends CombatHUDComponent

## Clave del pie que recuerda que la cinemática se puede saltear.
const SKIP_KEY: String = "ROUND_INTRO_SKIP"

## Altura del rótulo como fracción del alto del lienzo.
const TOP_RATIO: float = 0.34

## Ancho del bloque de texto, en píxeles.
const BLOCK_WIDTH: float = 900.0

## Parpadeo del pie de salteo, en Hz.
const HINT_BLINK_HZ: float = 0.8

var _name_key: String = ""
var _goal_key: String = ""
var _time: float = 0.0


## Nombre y objetivo de la ronda, tal como los trae [RoundCatalog] (`docs/11` §2).
func set_round(name_key: String, goal_key: String) -> void:
	if name_key == _name_key and goal_key == _goal_key:
		return
	_name_key = name_key
	_goal_key = goal_key
	queue_redraw()


## Claves vigentes, `[name_key, goal_key]`.
func round_keys() -> PackedStringArray:
	return PackedStringArray([_name_key, _goal_key])


func _tick(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not begin_draw():
		return
	if _name_key.is_empty() and _goal_key.is_empty():
		return
	var left := centre().x - BLOCK_WIDTH * 0.5
	var y := size.y * TOP_RATIO
	if not _name_key.is_empty():
		HUDDraw.text(self, HUDDraw.font_bold(), Vector2(left, y), tr(_name_key).to_upper(),
				48, HORIZONTAL_ALIGNMENT_CENTER, BLOCK_WIDTH, CombatHUDPalette.TEXT)
		y += 46.0
	if not _goal_key.is_empty():
		HUDDraw.text(self, HUDDraw.font_mono(), Vector2(left, y), tr(_goal_key), 22,
				HORIZONTAL_ALIGNMENT_CENTER, BLOCK_WIDTH, CombatHUDPalette.TEXT_DIM)
		y += 44.0
	var lit := fposmod(_time * HINT_BLINK_HZ, 1.0) < 0.6
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(left, y), tr(SKIP_KEY).to_upper(), 18,
			HORIZONTAL_ALIGNMENT_CENTER, BLOCK_WIDTH,
			CombatHUDPalette.with_alpha(CombatHUDPalette.ACCENT, 1.0 if lit else 0.35))
