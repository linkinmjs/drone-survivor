## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Marcador del punto débil expuesto más cercano (WP-24d, `docs/12` §4.1).
##
## Sale a ayudar cuando el jugador lleva [constant WeakPointTracker.IDLE_SECONDS]
## segundos **sin acertarle a un punto débil** y hay alguno expuesto: corchetes cian
## sobre el más cercano si está en cuadro, flecha al borde si no, y siempre el rótulo
## del grupo (`WP_KNEE`, `WP_VISOR`, `WP_CORE`) con la distancia en metros. Se apaga
## en cuanto el jugador acierta uno.
##
## Es la respuesta al feedback que gobierna WP-24d —«no entendí cómo matarlo»— y al
## riesgo 1 de `docs/07` §15, que ya pedía que «el `CombatHUD` marque la rodilla más
## cercana». No es una ayuda permanente: ocho segundos de silencio son suficientes
## para que un jugador que entendió nunca la vea.
##
## ## Por qué es un componente propio y no una clase más de [HUDOffscreenMarkers]
##
## Los marcadores de borde recorren **grupos del árbol** (`enemies`, `pickups`,
## `buildings_under_siege`), muestran hasta seis a la vez y no tienen estado temporal.
## Éste sigue a **un** nodo elegido por una regla con reloj, cambia de blanco cuando
## el jefe expone otra cosa y dibuja corchetes dentro de la pantalla, que es
## justamente lo que aquel componente no hace. Mezclarlos habría metido el reloj de
## ocho segundos y la elección del más cercano dentro del `_compute()` de los seis
## marcadores, que corre todos los cuadros.
##
## ## Por qué vive fuera del marco escalado
##
## Por lo mismo que [HUDOffscreenMarkers]: el margen y el borde de la pantalla son
## magnitudes **de pantalla**, no del lienzo de diseño de 1280 × 720. Cuelga del
## `Root` del [CombatHUD].
class_name HUDWeakPointHint
extends CombatHUDComponent

## Margen del rectángulo útil, en píxeles. El mismo que el de los marcadores de borde
## para que las dos flechas caigan sobre la misma línea.
const MARGIN: float = 56.0

## Medio lado de la caja de corchetes, en píxeles.
const BRACKET_HALF: float = 26.0

## Largo del trazo de cada corchete, en píxeles.
const BRACKET_ARM: float = 9.0

## Grosor del trazo de los corchetes.
const BRACKET_WIDTH: float = 2.0

## Lado de la flecha de borde, en píxeles.
const ARROW_SIZE: float = 18.0

## Frecuencia del latido del marcador, en Hz. Lento a propósito: es una ayuda, no una
## alarma; el aviso de telegrafía parpadea a 4 Hz y no tienen que confundirse.
const PULSE_HZ: float = 1.2

## Opacidad mínima del latido.
const PULSE_FLOOR: float = 0.55

## Segundos de aparición y de desaparición del marcador.
const FADE_SECONDS: float = 0.35

## Cámara impuesta por [CombatHUD]; si es `null` se usa la que dibuja la escena.
var camera: Camera3D = null

## Estado compartido con [HUDCoachTip]: quién está expuesto y hace cuánto.
var tracker: WeakPointTracker = WeakPointTracker.new()

## Opacidad actual, de 0 a 1. Nunca salta: un corchete que aparece de golpe sobre el
## video se lee como un impacto.
var _alpha: float = 0.0

## Reloj del latido, en segundos.
var _time: float = 0.0

## Punto débil que se está marcando, o `null`.
var _target: WeakPoint = null


## Da de alta un enemigo para el marcador. Idempotente.
func bind_enemy(enemy: Node3D) -> void:
	tracker.bind_enemy(enemy)


## Da de baja un enemigo.
func unbind_enemy(enemy: Node3D) -> void:
	tracker.unbind_enemy(enemy)
	if _target != null and not is_instance_valid(_target):
		_target = null
	queue_redraw()


## Olvida todos los enemigos y apaga el marcador.
func clear_enemies() -> void:
	tracker.clear()
	_target = null
	_alpha = 0.0
	queue_redraw()


## `Events.enemy_weak_point_state`.
func on_weak_point_state(enemy: Node3D, weak_point_id: StringName, exposed: bool) -> void:
	tracker.on_state(enemy, weak_point_id, exposed)


## `Events.enemy_part_broken`.
func on_part_broken(enemy: Node3D, part_id: StringName) -> void:
	tracker.on_broken(enemy, part_id)


## `Events.hit_confirmed` con `weak = true`: el marcador se apaga.
func on_weak_hit() -> void:
	tracker.on_weak_hit()


## `true` mientras el marcador esté pedido por la regla de los ocho segundos.
func is_active() -> bool:
	return tracker.is_idle()


## `true` mientras se vea algo en pantalla, incluida la desaparición.
func is_showing() -> bool:
	return _alpha > 0.01 and _target != null


## Punto débil marcado, o `null`.
func target() -> WeakPoint:
	return _target if _target != null and is_instance_valid(_target) else null


## Id del punto débil marcado, o `&""`.
func target_id() -> StringName:
	var weak_point := target()
	return weak_point.weak_point_id() if weak_point != null else &""


## Clave `WP_*` del grupo del punto débil marcado, o `""`.
func label_key() -> String:
	return WeakPointTracker.group_key_of(target())


## Distancia de la cámara al punto marcado, en metros; `-1.0` si no hay marcador.
func distance() -> float:
	var weak_point := target()
	var active := _camera()
	if weak_point == null or active == null:
		return -1.0
	var point := weak_point.world_position()
	if not point.is_finite():
		return -1.0
	return active.global_position.distance_to(point)


func _tick(delta: float) -> void:
	tracker.tick(delta)
	_time += delta
	var wanted := is_active()
	if wanted:
		_target = _pick_target()
		wanted = _target != null
	var step := delta / maxf(FADE_SECONDS, 0.001)
	var before := _alpha
	_alpha = clampf(_alpha + (step if wanted else -step), 0.0, 1.0)
	if _alpha <= 0.0:
		if before > 0.0:
			_target = null
			queue_redraw()
		return
	queue_redraw()


func _draw() -> void:
	if not begin_draw():
		return
	var weak_point := target()
	if weak_point == null or _alpha <= 0.01:
		return
	var active := _camera()
	if active == null:
		return
	var point := weak_point.world_position()
	if not point.is_finite():
		return
	var rect := screen_rect()
	var marker := HUDProjection.marker_for(active, point, rect, MARGIN)
	var at: Vector2 = get_global_transform_with_canvas().affine_inverse() \
			* (marker["pos"] as Vector2)
	if not at.is_finite():
		return

	var beat := PULSE_FLOOR + (1.0 - PULSE_FLOOR) \
			* (0.5 + 0.5 * sin(TAU * PULSE_HZ * _time))
	var colour := CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, _alpha * beat)
	var offscreen := bool(marker["offscreen"])
	if offscreen:
		_draw_arrow(at, float(marker["angle"]), colour)
	else:
		_draw_brackets(at, colour)
	_draw_label(at, offscreen, float(marker["distance"]), colour)


## Rectángulo de pantalla sobre el que se recorta el marcador.
func screen_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(Vector2.ZERO, size)
	return viewport.get_visible_rect()


# --- Internos ---------------------------------------------------------------------------------

## El punto débil expuesto más cercano a la cámara. Sin cámara no hay «cerca», así
## que se toma el primero expuesto: un marcador en el punto equivocado es mejor que
## ninguno cuando el nivel está ciclando cámaras.
func _pick_target() -> WeakPoint:
	var active := _camera()
	if active != null:
		var nearest := tracker.nearest(active.global_position)
		if nearest != null:
			return nearest
	var exposed := tracker.exposed_points()
	return exposed[0] if not exposed.is_empty() else null


## Cuatro corchetes en las esquinas de una caja. No es un rectángulo cerrado: el
## retículo ya dibuja una caja cian llena sobre el punto débil fijado (`docs/12`
## §4.1) y dos rectángulos iguales serían el mismo dibujo dos veces.
func _draw_brackets(at: Vector2, colour: Color) -> void:
	for corner: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0),
			Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var origin := at + corner * BRACKET_HALF
		HUDDraw.line(self, origin, origin - Vector2(corner.x * BRACKET_ARM, 0.0),
				BRACKET_WIDTH, colour)
		HUDDraw.line(self, origin, origin - Vector2(0.0, corner.y * BRACKET_ARM),
				BRACKET_WIDTH, colour)


## Flecha hueca hacia donde está el punto débil. Hueca y no rellena para que no se
## confunda con el triángulo macizo de [HUDOffscreenMarkers], que marca al jefe
## entero: éste marca **dónde pegarle**.
func _draw_arrow(at: Vector2, angle: float, colour: Color) -> void:
	var direction := Vector2.from_angle(angle)
	var side := Vector2(-direction.y, direction.x)
	var tip := at + direction * ARROW_SIZE * 0.7
	var base := at - direction * ARROW_SIZE * 0.5
	var points := PackedVector2Array([tip, base + side * ARROW_SIZE * 0.55,
			base - side * ARROW_SIZE * 0.55, tip])
	draw_polyline(points, CombatHUDPalette.SHADOW, BRACKET_WIDTH + 2.5, true)
	draw_polyline(points, colour, BRACKET_WIDTH, true)


## «RODILLA 128 m» **encima** del marcador.
##
## Encima y no debajo porque debajo ya escribe [HUDOffscreenMarkers]: el jefe está en
## el mismo sitio que su rodilla y su rótulo «HOSTIL 383 m» cae a 36 px del punto
## (`ARROW_SIZE + 20`). Los dos rótulos a 12 px de distancia se pisaban letra sobre
## letra, que es exactamente lo que mostró la primera captura de WP-24d. Si el
## marcador está pegado al borde superior, el rótulo baja.
func _draw_label(at: Vector2, offscreen: bool, metres: float, colour: Color) -> void:
	var key := label_key()
	if key.is_empty():
		return
	var reach := (ARROW_SIZE if offscreen else BRACKET_HALF) + 12.0
	var anchor := at - Vector2(0.0, reach)
	if anchor.y < MARGIN * 0.5:
		anchor = at + Vector2(0.0, reach + 14.0)
	var text := "%s %s" % [tr(key).to_upper(), number_text("%d m" % [roundi(metres)])]
	HUDDraw.text(self, HUDDraw.font_mono(), anchor - Vector2(90.0, 0.0), text, 16,
			HORIZONTAL_ALIGNMENT_CENTER, 180.0, colour)


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		return camera
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
