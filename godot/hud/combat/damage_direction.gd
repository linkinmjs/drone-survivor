## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Arcos de dirección del daño (`docs/12` §4.1 y §8).
##
## `Events.drone_damaged(amount, source_position)` deja un arco de
## [constant SPAN_DEG]° pegado al borde, en la dirección de la fuente, con opacidad
## `clampf(amount / 45.0, 0.25, 1.0)` y [constant FADE_SECONDS] s de desvanecido. Se
## suman hasta [constant MAX_ARCS].
##
## ## El ángulo es un **rumbo**, no una proyección
##
## Un golpe que viene exactamente de atrás no se puede proyectar: su dirección en el
## plano de pantalla es el punto (0, 0) y cualquier `atan2` devolvería basura. Por eso
## el arco no usa [HUDProjection] sino el rumbo en espacio de cámara,
## `atan2(local.x, −local.z)`, que mapea el frente arriba, la derecha a la derecha y
## la espalda abajo, y está definido para las tres. Es la convención de cualquier
## indicador de daño y la que hace que el gesto sea «mirá para allá» y no «el píxel
## está acá».
##
## Vive fuera del marco escalado porque el borde de la pantalla es una magnitud de
## pantalla; el radio sale de [constant RADIUS_RATIO] del alto de la viewport.
class_name HUDDamageDirection
extends CombatHUDComponent

## Apertura de cada arco, en grados (`docs/12` §8).
const SPAN_DEG: float = 60.0

## Desvanecido de un arco, en segundos (`docs/12` §8).
const FADE_SECONDS: float = 0.8

## Arcos simultáneos (`docs/12` §8).
const MAX_ARCS: int = 3

## Radio del arco como fracción del alto de la viewport (`docs/12` §4.1).
const RADIUS_RATIO: float = 0.44

## Grosor del trazo, en píxeles.
const THICKNESS: float = 12.0

## Daño que satura la opacidad (`docs/12` §4.1).
const FULL_DAMAGE: float = 45.0

## Opacidad mínima de un arco.
const MIN_ALPHA: float = 0.25

## Segmentos con los que se tesela un arco de 60°.
const ARC_STEPS: int = 24

## Cámara impuesta por [CombatHUD]; si es `null` se usa la que dibuja la escena.
var camera: Camera3D = null

## Arcos vivos: `{angle: float, alpha: float, left: float}`.
var _arcs: Array[Dictionary] = []


func _tick(delta: float) -> void:
	if _arcs.is_empty():
		return
	var index := _arcs.size() - 1
	while index >= 0:
		var arc := _arcs[index]
		arc["left"] = float(arc["left"]) - delta
		if float(arc["left"]) <= 0.0:
			_arcs.remove_at(index)
		else:
			_arcs[index] = arc
		index -= 1
	queue_redraw()


## `Events.drone_damaged`. Un daño sin posición finita —o sin cámara— se ignora: un
## arco apuntando a ninguna parte es peor que ningún arco.
func add_damage(amount: float, source_position: Vector3) -> void:
	var angle := angle_for(source_position)
	if is_nan(angle):
		return
	if _arcs.size() >= MAX_ARCS:
		_arcs.remove_at(0)
	var alpha := clampf(absf(amount) / FULL_DAMAGE, MIN_ALPHA, 1.0)
	if not is_finite(alpha):
		alpha = MIN_ALPHA
	_arcs.append({"angle": angle, "alpha": alpha, "left": FADE_SECONDS})
	queue_redraw()


## Ángulo de pantalla al que apuntaría un golpe desde [param source_position], en
## radianes y en la convención de [method CanvasItem.draw_arc]: `0` a la derecha,
## `−PI/2` arriba (el frente), `PI/2` abajo (la espalda). `NAN` si no hay cámara.
func angle_for(source_position: Vector3) -> float:
	var active := _camera()
	if active == null or not source_position.is_finite():
		return NAN
	var to_source := source_position - active.global_position
	if not to_source.is_finite() or to_source.length_squared() <= 1e-8:
		return NAN
	var local := active.global_basis.orthonormalized().inverse() * to_source
	var bearing := atan2(local.x, -local.z)
	if is_nan(bearing):
		return NAN
	return wrapf(bearing - PI * 0.5, -PI, PI)


## Arcos vivos. La fila 7 de `docs/12` §9.2 exige 4 ángulos distintos y ninguno `NAN`.
func arc_angles() -> Array[float]:
	var angles: Array[float] = []
	for arc: Dictionary in _arcs:
		angles.append(float(arc["angle"]))
	return angles


## Cantidad de arcos vivos. A los 0.9 s del último golpe tiene que ser 0.
func active_count() -> int:
	return _arcs.size()


## Borra los arcos. La usan el respawn y el modo cinemático.
func clear_arcs() -> void:
	if _arcs.is_empty():
		return
	_arcs.clear()
	queue_redraw()


func _draw() -> void:
	if not begin_draw():
		return
	if _arcs.is_empty():
		return
	var viewport := get_viewport()
	var view_size := viewport.get_visible_rect().size if viewport != null else size
	var origin := get_global_transform_with_canvas().affine_inverse() * (view_size * 0.5)
	if not origin.is_finite():
		origin = centre()
	var radius := maxf(view_size.y * RADIUS_RATIO, 16.0)
	var half := deg_to_rad(SPAN_DEG) * 0.5
	for arc: Dictionary in _arcs:
		var life := clampf(float(arc["left"]) / FADE_SECONDS, 0.0, 1.0)
		var alpha := float(arc["alpha"]) * life
		var angle := float(arc["angle"])
		draw_arc(origin, radius, angle - half, angle + half, ARC_STEPS,
				CombatHUDPalette.with_alpha(CombatHUDPalette.SHADOW, alpha * 0.8),
				THICKNESS + 4.0, true)
		draw_arc(origin, radius, angle - half, angle + half, ARC_STEPS,
				CombatHUDPalette.with_alpha(CombatHUDPalette.DANGER, alpha),
				THICKNESS, true)


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		return camera
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
