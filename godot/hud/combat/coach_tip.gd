## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Consejos contextuales de una línea (WP-24d, `docs/12` §4.1).
##
## Cuatro frases, cada una **una sola vez por ronda**, disparadas por el hecho que
## las vuelve útiles:
##
## | Disparo | Clave |
## |---|---|
## | primer `head_laser` telegrafiado | `HUD_COACH_VISOR` |
## | primer `emp_pulse` telegrafiado | `HUD_COACH_EMP` |
## | primer `stomp` telegrafiado | `HUD_COACH_STOMP` |
## | [constant WeakPointTracker.IDLE_SECONDS] s sin acertarle a un débil expuesto | `HUD_COACH_WEAK` |
##
## Son la respuesta al feedback que gobierna WP-24d: el jugador de la primera partida
## no sabe que el visor se abre mientras el jefe carga el láser, ni que el anillo del
## EMP y el círculo del pisotón se esquivan saliendo. Nada de esto se puede deducir
## mirando, y el aviso de telegrafía sólo dice **qué** ataque viene, no qué hacer.
##
## ## No bloquea y no se repite
##
## Una línea de texto a [constant TOP_RATIO] del alto, en el hueco que queda entre el
## aviso de telegrafía y el retículo. No pausa, no roba foco, no espera confirmación
## y se va sola a los [constant TIP_SECONDS] segundos. Y no vuelve: un consejo que se
## repite deja de ser un consejo y pasa a ser ruido. [method has_fired] es lo que
## `combat_hud_check` verifica.
##
## Un consejo nuevo **reemplaza** al anterior en vez de encolarse: si el jefe
## telegrafía un pisotón mientras se lee el del visor, lo que importa ahora es el
## pisotón.
class_name HUDCoachTip
extends CombatHUDComponent

## Ataque telegrafiado → clave del consejo (`docs/07` §5 para los ids).
const TIP_KEYS: Dictionary[StringName, String] = {
	&"head_laser": "HUD_COACH_VISOR",
	&"emp_pulse": "HUD_COACH_EMP",
	&"stomp": "HUD_COACH_STOMP",
}

## Consejo de los puntos débiles, el único que no lo dispara un ataque.
const WEAK_KEY: String = "HUD_COACH_WEAK"

## Segundos que dura un consejo en pantalla.
const TIP_SECONDS: float = 5.0

## Segundos de aparición y de desaparición.
const FADE_SECONDS: float = 0.3

## Altura de la línea como fracción del alto del lienzo.
##
## No es un número libre: el aviso de telegrafía ocupa de 0.30 a 0.38 del alto
## ([constant HUDTelegraphWarning.TOP_RATIO] más sus 58 px) y el retículo empieza
## cerca del 0.45. El 0.42 es el único renglón libre entre los dos, y es donde el ojo
## ya está mirando.
const TOP_RATIO: float = 0.42

## Ancho del bloque de texto, en píxeles. Entra entre las cintas laterales del
## `FlightHUD`, que están a ±320 px del centro.
const BLOCK_WIDTH: float = 600.0

## Tamaño de la fuente del consejo, en píxeles.
const FONT_SIZE: int = 20

## Tamaño mínimo al que se deja encoger el consejo para que entre en el bloque.
const MIN_FONT_SIZE: int = 14

## Margen interno del bloque, en píxeles.
const PADDING: float = 14.0

## Estado compartido con [HUDWeakPointHint]: quién está expuesto y hace cuánto.
var tracker: WeakPointTracker = WeakPointTracker.new()

## Claves ya disparadas en esta ronda: `{clave: true}`.
var _fired: Dictionary[String, bool] = {}

## Clave del consejo en pantalla, o `""`.
var _key: String = ""

## Segundos que le quedan al consejo en pantalla.
var _left: float = 0.0

## Opacidad actual, de 0 a 1.
var _alpha: float = 0.0


## Da de alta un enemigo para el reloj de los puntos débiles. Idempotente.
func bind_enemy(enemy: Node3D) -> void:
	tracker.bind_enemy(enemy)


## Da de baja un enemigo.
func unbind_enemy(enemy: Node3D) -> void:
	tracker.unbind_enemy(enemy)


## Olvida enemigos y consejo en pantalla, pero **no** las claves ya disparadas: el
## jefe que cae no devuelve al jugador al principio de la ronda.
func clear_enemies() -> void:
	tracker.clear()
	clear_tip()


## `Events.enemy_attack_telegraphed`.
func on_telegraph(_enemy: Node3D, attack_id: StringName, duration: float) -> void:
	if not is_finite(duration) or duration <= 0.0:
		return
	var key := String(TIP_KEYS.get(attack_id, ""))
	if key.is_empty():
		return
	show_tip(key)


## `Events.enemy_weak_point_state`.
func on_weak_point_state(enemy: Node3D, weak_point_id: StringName, exposed: bool) -> void:
	tracker.on_state(enemy, weak_point_id, exposed)


## `Events.enemy_part_broken`.
func on_part_broken(enemy: Node3D, part_id: StringName) -> void:
	tracker.on_broken(enemy, part_id)


## `Events.hit_confirmed` con `weak = true`.
func on_weak_hit() -> void:
	tracker.on_weak_hit()


## Muestra [param key] si todavía no se mostró nunca. Devuelve `true` si salió.
func show_tip(key: String) -> bool:
	if key.is_empty() or _fired.has(key):
		return false
	_fired[key] = true
	_key = key
	_left = TIP_SECONDS
	queue_redraw()
	return true


## Apaga el consejo en pantalla sin olvidar que ya salió.
func clear_tip() -> void:
	if _key.is_empty() and _alpha <= 0.0:
		return
	_key = ""
	_left = 0.0
	_alpha = 0.0
	queue_redraw()


## Olvida qué consejos salieron. La llama [CombatHUD] al empezar una ronda nueva.
func reset() -> void:
	_fired.clear()
	tracker.set_idle_seconds(0.0)
	clear_tip()


## `true` si [param key] ya salió alguna vez en esta ronda.
func has_fired(key: String) -> bool:
	return _fired.has(key)


## Cuántos consejos distintos salieron.
func fired_count() -> int:
	return _fired.size()


## Clave del consejo en pantalla, o `""`.
func current_key() -> String:
	return _key


## Texto del consejo en pantalla, ya traducido.
func display_text() -> String:
	return tr(_key) if not _key.is_empty() else ""


## `true` mientras se vea algo, incluida la desaparición.
func is_showing() -> bool:
	return _alpha > 0.01 and not _key.is_empty()


## Tamaño de fuente con el que [param text] entra entero en el bloque.
##
## [method HUDDraw.text] **recorta** al ancho en vez de partir la línea, y un consejo
## que termina en «EL RESTO ES BLIND» es peor que no dar consejo. Un renglón único es
## innegociable —es lo que lo vuelve leíble de reojo mientras el jefe carga un
## ataque—, así que lo que cede es el cuerpo de la letra. En español el consejo más
## largo entra a 17 px; [constant MIN_FONT_SIZE] es el piso que deja margen a un
## idioma más ancho sin volverse ilegible.
func font_size_for(text: String) -> int:
	if text.is_empty():
		return FONT_SIZE
	var font := HUDDraw.font_mono()
	var limit := BLOCK_WIDTH - PADDING * 2.0
	var points := FONT_SIZE
	while points > MIN_FONT_SIZE:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points).x <= limit:
			break
		points -= 1
	return points


## Ancho en píxeles que ocupa [param text] con el tamaño que le toca. Lo usa
## `combat_hud_check` para exigir que ninguna traducción se salga del bloque.
func text_width(text: String) -> float:
	if text.is_empty():
		return 0.0
	return HUDDraw.font_mono().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			font_size_for(text)).x


func _tick(delta: float) -> void:
	tracker.tick(delta)
	if tracker.is_idle():
		var _shown := show_tip(WEAK_KEY)
	if _left > 0.0:
		_left = maxf(_left - delta, 0.0)
	var step := delta / maxf(FADE_SECONDS, 0.001)
	var wanted := _left > 0.0 and not _key.is_empty()
	var before := _alpha
	_alpha = clampf(_alpha + (step if wanted else -step), 0.0, 1.0)
	if _alpha <= 0.0:
		if before > 0.0:
			_key = ""
			queue_redraw()
		return
	if not is_equal_approx(before, _alpha):
		queue_redraw()


func _draw() -> void:
	if not begin_draw():
		return
	if _key.is_empty() or _alpha <= 0.01:
		return
	var text := display_text()
	var points := font_size_for(text)
	var left := centre().x - BLOCK_WIDTH * 0.5
	var y := size.y * TOP_RATIO
	# Ámbar: es información **del piloto**, no del enemigo. El cian está reservado a
	# lo que se puede romper (`docs/13` §2.1), y un consejo en cian se leería como un
	# punto débil más.
	var colour := CombatHUDPalette.with_alpha(CombatHUDPalette.ACCENT, _alpha)
	var box := Rect2(Vector2(left, y - float(points) - 6.0),
			Vector2(BLOCK_WIDTH, float(points) + 16.0))
	draw_rect(box, CombatHUDPalette.with_alpha(CombatHUDPalette.BOX, _alpha * 0.85), true)
	HUDDraw.line(self, Vector2(box.position.x, box.end.y),
			Vector2(box.end.x, box.end.y), 1.0,
			CombatHUDPalette.with_alpha(CombatHUDPalette.ACCENT, _alpha * 0.45))
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(left, y), text,
			points, HORIZONTAL_ALIGNMENT_CENTER, BLOCK_WIDTH, colour)
