## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Aviso de ataque telegrafiado (`docs/12` §4.1 y §8).
##
## `Events.enemy_attack_telegraphed(enemy, attack_id, duration)` enciende una franja
## con el icono del ataque, la clave `HUD_TELEGRAPH_<ATTACK_ID>` y una barra de
## windup que se vacía exactamente en `duration`; en el último
## [constant BLINK_TAIL] del tiempo parpadea a [constant BLINK_HZ] Hz. Es la promesa
## de `docs/07` §5 hecha interfaz: **todo ataque avisa antes de golpear**.
##
## El punto de impacto no viaja en la señal, así que el marcador lo toma del `enemy`
## recibido y lo proyecta con [HUDProjection] (`docs/12` §4.1).
##
## ## Dos discrepancias registradas con `docs/12`
##
## 1. **Altura de la franja.** §4.1 la pone «a 24 % del alto». A esa altura cae
##    encima de la franja de ciudad, que el mismo documento ubica bajo la barra del
##    jefe (`TOP_MARGIN` 184 px de 720 = 25.5 %). Se baja a [constant TOP_RATIO], el
##    primer renglón libre por debajo del bloque jefe + ciudad, y se conserva todo lo
##    demás.
## 2. **Icono.** §4.1 pide «icono del ataque». El juego de iconos es de `docs/13` y lo
##    entrega WP-25; hasta entonces se dibuja un triángulo de aviso procedural, igual
##    para los nueve ataques, y el ataque se distingue por el texto, que es el dato
##    que el jugador lee.
class_name HUDTelegraphWarning
extends CombatHUDComponent

## Prefijo de la clave de traducción de cada ataque (`docs/12` §6).
const KEY_PREFIX: String = "HUD_TELEGRAPH_"

## Clave de respaldo cuando el ataque no tiene fila en el CSV.
const GENERIC_KEY: String = "HUD_TELEGRAPH_GENERIC"

## Altura de la franja como fracción del alto del lienzo. Ver la discrepancia 1.
const TOP_RATIO: float = 0.30

## Ancho de la franja, en píxeles. Entra entre las dos cintas laterales del
## `FlightHUD`, que están a ±320 px del centro (`hud/hud_side_tapes.gd`).
const WIDTH: float = 480.0

## Alto de la franja, en píxeles.
const HEIGHT: float = 58.0

## Alto de la barra de windup, en píxeles.
const BAR_HEIGHT: float = 6.0

## Fracción final del windup en la que el aviso parpadea (`docs/12` §8).
const BLINK_TAIL: float = 0.25

## Parpadeo final, en Hz (`docs/12` §8).
const BLINK_HZ: float = 4.0

## Cámara impuesta por [CombatHUD]; si es `null` se usa la que dibuja la escena.
var camera: Camera3D = null

var _attack_id: StringName = &""
var _duration: float = 0.0
var _left: float = 0.0
var _time: float = 0.0
var _enemy: Node3D = null


## `Events.enemy_attack_telegraphed`. Un aviso nuevo reemplaza al anterior: dos
## avisos a la vez serían ilegibles y el jefe telegrafía de a uno (`docs/07` §5).
func on_telegraph(enemy: Node3D, attack_id: StringName, duration: float) -> void:
	if not is_finite(duration) or duration <= 0.0:
		return
	_enemy = enemy
	_attack_id = attack_id
	_duration = duration
	_left = duration
	_time = 0.0
	queue_redraw()


## Apaga el aviso. La usan el respawn, el modo cinemático y el fin de ronda.
func clear_warning() -> void:
	if _left <= 0.0 and _attack_id == &"":
		return
	_attack_id = &""
	_enemy = null
	_duration = 0.0
	_left = 0.0
	queue_redraw()


## `true` mientras el aviso esté en pantalla.
func is_active() -> bool:
	return _left > 0.0


## Clave de traducción del aviso vigente, o `""`.
##
## `docs/12` §9.2 fila 8 exige exactamente `HUD_TELEGRAPH_STOMP` para el ataque
## `stomp`: la clave es el id en mayúsculas con el prefijo, sin tabla intermedia, así
## que un ataque nuevo de `docs/07` sólo necesita su fila en el CSV.
func current_key() -> String:
	if _attack_id == &"":
		return ""
	return KEY_PREFIX + String(_attack_id).to_upper()


## Ataque que se está avisando.
func current_attack() -> StringName:
	return _attack_id


## Texto ya traducido del aviso.
##
## Si el ataque no tiene fila en el CSV, [method Object.tr] devuelve la clave tal
## cual y el jugador vería `HUD_TELEGRAPH_WALK` en pantalla. Eso no puede pasar: el
## respaldo es [constant GENERIC_KEY], que siempre existe. Es la misma red que usa
## `ui_smoke_test` para detectar claves faltantes, pero del lado del que dibuja.
func display_text() -> String:
	var key := current_key()
	if key.is_empty():
		return ""
	var text := tr(key)
	return text if text != key else tr(GENERIC_KEY)


## Windup restante, de 1 a 0. Llega a 0 a los `duration` segundos exactos.
func progress() -> float:
	if _duration <= 0.0:
		return 0.0
	return clampf(_left / _duration, 0.0, 1.0)


## Segundos que le quedan al aviso.
func remaining() -> float:
	return maxf(_left, 0.0)


func _tick(delta: float) -> void:
	if _left <= 0.0:
		return
	_time += delta
	_left = maxf(_left - delta, 0.0)
	if _left <= 0.0:
		_attack_id = &""
		_enemy = null
	queue_redraw()


func _draw() -> void:
	if not begin_draw():
		return
	if _left <= 0.0:
		return
	var ratio := progress()
	var alpha := 1.0
	if ratio <= BLINK_TAIL:
		alpha = 1.0 if fposmod(_time * BLINK_HZ, 1.0) < 0.5 else 0.35
	var colour := CombatHUDPalette.with_alpha(CombatHUDPalette.DANGER, alpha)

	var top := size.y * TOP_RATIO
	var rect := Rect2(Vector2(centre().x - WIDTH * 0.5, top), Vector2(WIDTH, HEIGHT))
	draw_rect(rect, CombatHUDPalette.BOX, true)
	draw_rect(rect, CombatHUDPalette.with_alpha(colour, alpha * 0.8), false, 1.5)

	_draw_icon(Vector2(rect.position.x + 32.0, rect.position.y + 24.0), colour)

	var font := HUDDraw.font_bold()
	HUDDraw.text(self, font, Vector2(rect.position.x + 62.0, rect.position.y + 30.0),
			display_text(), 24, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 74.0, colour)

	var bar := Rect2(Vector2(rect.position.x + 12.0, rect.end.y - BAR_HEIGHT - 8.0),
			Vector2(WIDTH - 24.0, BAR_HEIGHT))
	draw_rect(bar, CombatHUDPalette.TRACK, true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), colour, true)

	_draw_impact_marker(colour)


# --- Internos ---------------------------------------------------------------------------------

## Triángulo de aviso con su signo de admiración. Placeholder hasta WP-25.
func _draw_icon(at: Vector2, colour: Color) -> void:
	var half := 13.0
	var points := PackedVector2Array([at + Vector2(0.0, -half),
			at + Vector2(half, half * 0.8), at + Vector2(-half, half * 0.8),
			at + Vector2(0.0, -half)])
	draw_polyline(points, CombatHUDPalette.SHADOW, 4.5, true)
	draw_polyline(points, colour, 2.0, true)
	HUDDraw.line(self, at + Vector2(0.0, -half * 0.35), at + Vector2(0.0, half * 0.25),
			2.0, colour)
	draw_circle(at + Vector2(0.0, half * 0.55), 1.6, colour)


## Cursor sobre el enemigo que está telegrafiando, para que el aviso diga **quién**
## además de **qué**. Se salta en silencio si el jefe no está en cuadro.
func _draw_impact_marker(colour: Color) -> void:
	if _enemy == null or not is_instance_valid(_enemy) or not _enemy.is_inside_tree():
		return
	var active := _camera()
	if active == null:
		return
	var point := HUDProjection.project_point(active, _enemy.global_position)
	if not point.is_finite():
		return
	var at := get_global_transform_with_canvas().affine_inverse() * point
	if not at.is_finite():
		return
	HUDDraw.line(self, at + Vector2(-10.0, -16.0), at, 2.0, colour)
	HUDDraw.line(self, at + Vector2(10.0, -16.0), at, 2.0, colour)


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		return camera
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
