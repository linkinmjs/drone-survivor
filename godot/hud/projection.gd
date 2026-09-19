## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Proyección compartida entre el HUD de vuelo y el HUD de combate (`docs/12` §3).
##
## Todo lo que el jugador ve marcado sobre el mundo —la línea de horizonte, los
## marcadores de enemigos, las pilas, el edificio bajo asedio— necesita la misma
## cuenta: dónde cae en pantalla una dirección del mundo 3D. La cámara FPV ya sabe
## hacerlo con su ojo de pez ([method FPVCamera.project_direction]); esta clase es la
## versión sin dependencias, con funciones estáticas y sin estado, que además sirve
## para cualquier [Camera3D] y para los checks.
##
## Dos contratos que conviene no confundir:
## - [method project_direction] y [method project_point] devuelven `Vector2(NAN, NAN)`
##   cuando la dirección queda fuera del campo visual. Quien las llame **debe**
##   verificar con `is_finite()`.
## - [method marker_for] nunca devuelve `NAN`: si el punto está detrás de la cámara o
##   fuera del círculo de ojo de pez, construye una dirección de respaldo y empuja el
##   marcador al borde del rectángulo. Quien la llame no necesita verificar nada.
class_name HUDProjection
extends RefCounted

## Lo que devuelven las proyecciones para algo que no se ve.
const OUT_OF_FIELD: Vector2 = Vector2(NAN, NAN)

## Por debajo de esto, dos puntos de pantalla son el mismo punto.
const EPSILON: float = 1e-6


## Dirección del mundo → píxel de la viewport de [param camera], o
## `Vector2(NAN, NAN)` si queda fuera del campo.
##
## Tres caminos, en este orden:
## 1. Con [param fisheye_hfov] positivo manda la proyección **equidistante** de
##    `docs/12` §3.1, sea cual sea la cámara. Es el camino que usan los checks para
##    exigir un campo concreto.
## 2. Si la cámara es una [FPVCamera] y no se forzó un campo, se delega en ella: sabe
##    su modo de ojo de pez y su `hfov` reales, así que el marcador cae exactamente
##    donde está la imagen.
## 3. Si no, proyección **rectilínea** con `unproject_position` y la guarda de
##    `is_position_behind`.
static func project_direction(camera: Camera3D, dir: Vector3,
		fisheye_hfov: float = -1.0) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return OUT_OF_FIELD
	if not dir.is_finite() or dir.length_squared() <= 0.0:
		return OUT_OF_FIELD
	var unit := dir.normalized()
	if fisheye_hfov > 0.0:
		return _project_equidistant(camera, unit, fisheye_hfov)
	var fpv := camera as FPVCamera
	if fpv != null:
		return fpv.project_direction(unit)
	return _project_rectilinear(camera, unit)


## Punto del mundo → píxel, con la misma semántica que [method project_direction].
static func project_point(camera: Camera3D, world_point: Vector3,
		fisheye_hfov: float = -1.0) -> Vector2:
	if camera == null or not camera.is_inside_tree() or not world_point.is_finite():
		return OUT_OF_FIELD
	return project_direction(camera, world_point - camera.global_position, fisheye_hfov)


## Recorta [param point] al rectángulo [param rect] encogido [param margin] píxeles.
##
## Devuelve `{pos: Vector2, angle: float, offscreen: bool}`. Un punto interior vuelve
## intacto con `offscreen = false`; uno exterior se recorta sobre el segmento
## centro → punto, que es lo que hace que la flecha apunte a donde está la cosa.
## Es idempotente: recortar dos veces da el mismo punto.
static func edge_clamp(point: Vector2, rect: Rect2, margin: float) -> Dictionary:
	var inner := inner_rect(rect, margin)
	var centre := inner.position + inner.size * 0.5
	var half := inner.size * 0.5
	var target := point
	if not target.is_finite():
		target = centre + Vector2.DOWN * maxf(half.y, 1.0)
	var delta := target - centre
	if delta.length() <= EPSILON:
		return {"pos": centre, "angle": Vector2.DOWN.angle(), "offscreen": false}
	var scale := 1.0
	if half.x > 0.0 and absf(delta.x) > half.x:
		scale = minf(scale, half.x / absf(delta.x))
	if half.y > 0.0 and absf(delta.y) > half.y:
		scale = minf(scale, half.y / absf(delta.y))
	return {
		"pos": centre + delta * scale,
		"angle": delta.angle(),
		"offscreen": scale < 1.0,
	}


## Marcador de [param world_point] sobre el rectángulo de pantalla.
##
## Devuelve `{pos: Vector2, angle: float, offscreen: bool, distance: float}` y **nunca**
## `NAN`: cuando el punto está detrás de la cámara o fuera del círculo de ojo de pez,
## se anula la componente frontal en espacio de cámara, se normaliza el resto y el
## marcador se empuja al borde (si la parte plana es casi nula, hacia abajo).
static func marker_for(camera: Camera3D, world_point: Vector3, rect: Rect2,
		margin: float, fisheye_hfov: float = -1.0) -> Dictionary:
	var inner := inner_rect(rect, margin)
	var centre := inner.position + inner.size * 0.5
	if camera == null or not camera.is_inside_tree() or not world_point.is_finite():
		return {"pos": centre, "angle": Vector2.DOWN.angle(), "offscreen": true,
				"distance": 0.0}
	var origin := camera.global_position
	var direction := world_point - origin
	var distance := direction.length()
	var projected := project_direction(camera, direction, fisheye_hfov)
	var behind := not projected.is_finite()
	var point := projected if not behind else _fallback_point(camera, direction, inner)
	var marker := edge_clamp(point, rect, margin)
	if behind:
		marker["offscreen"] = true
	marker["distance"] = distance if is_finite(distance) else 0.0
	return marker


## El rectángulo útil: [param rect] encogido [param margin] píxeles por lado, sin
## dejarlo nunca del revés.
static func inner_rect(rect: Rect2, margin: float) -> Rect2:
	var base := rect.abs()
	var limit := minf(base.size.x, base.size.y) * 0.5
	return base.grow(-clampf(margin, 0.0, limit))


# --- Internos ---------------------------------------------------------------------------------

## Proyección rectilínea con la matriz de la propia cámara.
static func _project_rectilinear(camera: Camera3D, unit: Vector3) -> Vector2:
	var point := camera.global_position + unit
	if camera.is_position_behind(point):
		return OUT_OF_FIELD
	var projected := camera.unproject_position(point)
	return projected if projected.is_finite() else OUT_OF_FIELD


## Proyección equidistante de `docs/12` §3.1: el medio campo horizontal se mapea a
## media pantalla de ancho, que es la convención del shader de ojo de pez de
## `docs/03` §5.
static func _project_equidistant(camera: Camera3D, unit: Vector3, hfov: float) -> Vector2:
	var half_field := deg_to_rad(hfov) * 0.5
	if half_field <= 0.0:
		return OUT_OF_FIELD
	var local := (camera.global_basis.orthonormalized().inverse() * unit).normalized()
	var theta := acos(clampf(-local.z, -1.0, 1.0))
	if theta > half_field:
		return OUT_OF_FIELD
	var size := camera.get_viewport().get_visible_rect().size
	var centre := size * 0.5
	var phi := atan2(local.y, local.x)
	var radius := theta / half_field * maxf(centre.x, 1.0)
	return centre + Vector2(cos(phi), -sin(phi)) * radius


## Dirección de respaldo para algo que no se ve: la proyección de [param direction]
## sobre el plano de pantalla, sin su componente frontal, empujada más allá del borde
## para que [method edge_clamp] la recorte.
static func _fallback_point(camera: Camera3D, direction: Vector3, inner: Rect2) -> Vector2:
	var centre := inner.position + inner.size * 0.5
	var local := camera.global_basis.orthonormalized().inverse() * direction
	var flat := Vector2(local.x, -local.y)
	if not flat.is_finite() or flat.length() <= EPSILON:
		flat = Vector2.DOWN
	return centre + flat.normalized() * maxf(inner.size.length(), 1.0)
