## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Retículo del arma (`docs/12` §4.1 y §8).
##
## Cuatro corchetes que se separan [constant SPREAD_PIXELS_PER_DEG] px por grado de
## dispersión, un punto central de 2 px, la caja cian del punto débil que el rayo de
## asistencia está tocando y, con objetivo fijado, los corchetes girados 45° más la
## clave `HUD_LOCK`.
##
## ## Por qué hace polling y no escucha el bus
##
## Riesgo 4 de `docs/12` §10, ya resuelto: la dispersión cambia **todos los cuadros**
## mientras el gatillo está apretado (`docs/08` §2.3). Un evento por cuadro con dos
## flotantes sería ruido puro en el bus y llegaría siempre un cuadro tarde. El precio
## es que el retículo necesita [method bind_weapon] otra vez después de cada respawn,
## que es exactamente lo que hace [CombatHUD] con `Events.drone_respawned`.
##
## ## Espacios de coordenadas
##
## El componente vive dentro del `Frame` escalado del `CombatHUD`, así que lo que
## devuelve [HUDProjection] —píxeles de viewport— hay que pasarlo por la inversa de
## [method CanvasItem.get_global_transform_with_canvas]. Sin eso, a 960 × 540 la caja
## del punto débil caería a 4/3 de distancia del centro.
class_name HUDReticle
extends CombatHUDComponent

## Apertura del retículo por grado de dispersión, en píxeles (`docs/12` §8).
const SPREAD_PIXELS_PER_DEG: float = 34.0

## Separación de los corchetes con dispersión cero, en píxeles.
const BASE_GAP: float = 9.0

## Largo del brazo de cada corchete, en píxeles.
const ARM: float = 11.0

## Radio del punto central, en píxeles (`docs/12` §4.1: «punto central de 2 px»).
const DOT_RADIUS: float = 2.0

## Giro que toman los corchetes con objetivo fijado, en grados (`docs/12` §4.1).
const LOCK_ROTATION_DEG: float = 45.0

## Radio en metros con el que se estima el tamaño en pantalla de un punto débil.
## Las rodillas del Arachnodroid miden alrededor de eso (`docs/07` §3).
const TARGET_WORLD_RADIUS: float = 1.6

## Lado mínimo y máximo de la caja del punto débil, en píxeles.
const TARGET_BOX_MIN: float = 16.0
const TARGET_BOX_MAX: float = 190.0

## Parpadeo del rótulo de fijado, en Hz.
const LOCK_BLINK_HZ: float = 2.0

## Clave del rótulo de objetivo fijado.
const LOCK_KEY: String = "HUD_LOCK"

## Arma que se consulta cada cuadro. La escribe [method bind_weapon].
var weapon: WeaponMount = null

## Cámara con la que se proyecta la caja del punto débil.
var camera: Camera3D = null

var _spread_deg: float = 0.0
var _locked: Node3D = null
var _assisted: Node3D = null
var _time: float = 0.0


## Ata el retículo al arma del dron vivo. Llamarla con `null` lo deja en reposo, que
## es lo que corresponde mientras el dron se reconstruye.
func bind_weapon(mount: WeaponMount) -> void:
	weapon = mount
	_spread_deg = 0.0
	_locked = null
	_assisted = null
	queue_redraw()


func _tick(delta: float) -> void:
	_time += delta
	var spread := 0.0
	var locked: Node3D = null
	var assisted: Node3D = null
	if weapon != null and is_instance_valid(weapon) and weapon.is_inside_tree():
		spread = weapon.get_spread_deg()
		locked = weapon.get_locked_weak_point()
		var assist := weapon.get_aim_assist()
		if assist != null:
			assisted = assist.get_target()
	if not is_finite(spread):
		spread = 0.0
	# Sólo se pide redibujo cuando algo cambió de verdad, salvo con lock —ahí el
	# rótulo parpadea— y con un objetivo asistido, que se mueve con el jefe.
	var changed := not is_equal_approx(spread, _spread_deg) or locked != _locked \
			or assisted != _assisted
	_spread_deg = spread
	_locked = locked
	_assisted = assisted
	if changed or locked != null or assisted != null:
		queue_redraw()


## Separación actual de los corchetes respecto del centro, en píxeles.
func gap() -> float:
	return BASE_GAP + maxf(_spread_deg, 0.0) * SPREAD_PIXELS_PER_DEG


## Dispersión que se está dibujando, en grados.
func spread_deg() -> float:
	return _spread_deg


## `true` cuando el arma tiene un objetivo fijado.
func has_lock() -> bool:
	return _locked != null and is_instance_valid(_locked)


## Punto débil que el rayo de asistencia está tocando, o `null`.
func assisted_target() -> Node3D:
	return _assisted if _assisted != null and is_instance_valid(_assisted) else null


func _draw() -> void:
	if not begin_draw():
		return
	var origin := centre()
	var separation := gap()
	var rotation := deg_to_rad(LOCK_ROTATION_DEG) if has_lock() else 0.0
	var colour := CombatHUDPalette.TARGET if has_lock() else CombatHUDPalette.TEXT

	# Cuatro corchetes en cruz. Con lock giran 45° enteros, así que el gesto de
	# «enganchado» se lee incluso de reojo y sin color (`docs/12` §4.1).
	for index: int in 4:
		var angle := rotation + deg_to_rad(90.0 * float(index))
		var direction := Vector2.from_angle(angle)
		var side := Vector2(-direction.y, direction.x)
		var base := origin + direction * separation
		HUDDraw.line(self, base, base + direction * ARM, 2.0, colour)
		HUDDraw.line(self, base + direction * ARM,
				base + direction * ARM - side * (ARM * 0.45), 2.0, colour)

	draw_circle(origin, DOT_RADIUS + 1.2, CombatHUDPalette.SHADOW)
	draw_circle(origin, DOT_RADIUS, colour)

	_draw_target_box(_locked, CombatHUDPalette.TARGET, 2.0)
	if _assisted != _locked:
		_draw_target_box(_assisted, CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET,
				0.55), 1.5)

	if has_lock():
		var lit := fposmod(_time * LOCK_BLINK_HZ, 1.0) < 0.65
		HUDDraw.text(self, HUDDraw.font_mono(), origin + Vector2(-90.0, -separation - 22.0),
				tr(LOCK_KEY), 18, HORIZONTAL_ALIGNMENT_CENTER, 180.0,
				CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, 1.0 if lit else 0.45))


# --- Internos ---------------------------------------------------------------------------------

## Caja cian de un punto débil, dibujada donde la cámara lo pone.
##
## El tamaño sale de proyectar un punto desplazado [constant TARGET_WORLD_RADIUS]
## metros hacia el lado en espacio de cámara y medir cuántos píxeles se movió: así la
## caja crece al acercarse sin tener que leer la forma de colisión del enemigo, que
## es de `docs/06` y no del HUD.
func _draw_target_box(target: Node3D, colour: Color, width: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var active := _camera()
	if active == null:
		return
	var world := target.global_position
	var point := HUDProjection.project_point(active, world)
	if not point.is_finite():
		return
	var side := active.global_basis.orthonormalized().x * TARGET_WORLD_RADIUS
	var edge := HUDProjection.project_point(active, world + side)
	var half := TARGET_BOX_MIN
	if edge.is_finite():
		half = clampf(absf(edge.x - point.x), TARGET_BOX_MIN, TARGET_BOX_MAX)
	var local := get_global_transform_with_canvas().affine_inverse()
	var screen_scale := maxf(local.get_scale().x, 0.01)
	var centre_local := local * point
	half *= screen_scale
	if not centre_local.is_finite():
		return

	# Cuatro esquinas y no un rectángulo cerrado: deja ver el punto débil que
	# encierra, que es lo que el jugador tiene que estar mirando.
	var corner := half * 0.45
	for index: int in 4:
		var sx := 1.0 if index == 0 or index == 3 else -1.0
		var sy := 1.0 if index < 2 else -1.0
		var anchor := centre_local + Vector2(half * sx, half * sy)
		HUDDraw.line(self, anchor, anchor - Vector2(corner * sx, 0.0), width, colour)
		HUDDraw.line(self, anchor, anchor - Vector2(0.0, corner * sy), width, colour)


## Cámara efectiva: la que impuso [CombatHUD] o, si no hay ninguna, la que está
## dibujando la escena.
func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		return camera
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
