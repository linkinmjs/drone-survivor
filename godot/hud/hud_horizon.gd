## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDHorizon
extends Control
## Dotted horizon line with a gap around the crosshair, plus an optional pitch ladder.
## Two modes: "camera" draws the real horizon through the FPV lens (camera tilt and fisheye
## included), "attitude" follows the drone attitude like the classic HUD.


const ATTITUDE_PX_PER_DEG := 12.0
const HOLE_RADIUS := 70.0
const LADDER_STEPS: Array[int] = [-30, -20, -10, 10, 20, 30]
## Rungs further than this from the center are not drawn (they would cover the compass
## and the stick display)
const LADDER_MAX_OFFSET := 270.0

var show_horizon := true
var show_ladder := false
var mode := "camera"
var camera: FPVCamera = null
## Attitude in radians (used by the attitude mode and when there is no camera)
var pitch := 0.0
var roll := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if not show_horizon and not show_ladder:
		return
	if mode == "camera" and is_instance_valid(camera) and camera.is_inside_tree():
		_draw_camera_horizon()
	else:
		_draw_attitude_horizon()


func _to_local(viewport_point: Vector2) -> Vector2:
	if not viewport_point.is_finite():
		return viewport_point
	return get_global_transform_with_canvas().affine_inverse() * viewport_point


func _draw_camera_horizon() -> void:
	var basis := camera.global_transform.basis
	var forward := -basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() < 0.08:
		# Looking straight up or down: the horizon is not in front of the camera
		return
	flat = flat.normalized()
	var center := _to_local(get_viewport().get_visible_rect().size / 2.0)
	if show_horizon:
		var points := PackedVector2Array()
		for azimuth in range(-88, 89, 4):
			var direction := flat.rotated(Vector3.UP, deg_to_rad(azimuth))
			points.append(_to_local(camera.project_direction(direction)))
		HUDDraw.dashed_polyline(self, points, 7.0, 11.0, 3.5, HUDDraw.WHITE, center, HOLE_RADIUS)
	if show_ladder:
		for elevation in LADDER_STEPS:
			var e := deg_to_rad(elevation)
			var mid := flat * cos(e) + Vector3.UP * sin(e)
			var left := flat.rotated(Vector3.UP, deg_to_rad(6.0)) * cos(e) + Vector3.UP * sin(e)
			var right := flat.rotated(Vector3.UP, deg_to_rad(-6.0)) * cos(e) + Vector3.UP * sin(e)
			var p_mid := _to_local(camera.project_direction(mid))
			var p_left := _to_local(camera.project_direction(left))
			var p_right := _to_local(camera.project_direction(right))
			if not (p_mid.is_finite() and p_left.is_finite() and p_right.is_finite()):
				continue
			if absf(p_mid.y - center.y) > LADDER_MAX_OFFSET or absf(p_mid.x - center.x) > LADDER_MAX_OFFSET:
				continue
			_draw_rung(p_left, p_right, elevation)


func _draw_attitude_horizon() -> void:
	var center := size / 2.0
	var normal := Vector2(-sin(roll), cos(roll))
	var along := Vector2(cos(roll), sin(roll))
	var origin := center + rad_to_deg(pitch) * ATTITUDE_PX_PER_DEG * normal
	if show_horizon:
		var points := PackedVector2Array([origin - along * 420.0, origin + along * 420.0])
		HUDDraw.dashed_polyline(self, points, 7.0, 11.0, 3.5, HUDDraw.WHITE, center, HOLE_RADIUS)
	if show_ladder:
		for elevation in LADDER_STEPS:
			var rung_center := origin - normal * elevation * ATTITUDE_PX_PER_DEG
			if rung_center.distance_to(center) > LADDER_MAX_OFFSET:
				continue
			_draw_rung(rung_center - along * 70.0, rung_center + along * 70.0, elevation)


func _draw_rung(a: Vector2, b: Vector2, elevation: int) -> void:
	var along := (b - a).normalized()
	var normal := Vector2(-along.y, along.x)
	# Ticks point toward the horizon, like an aircraft ladder
	var tick := normal * (8.0 if elevation > 0 else -8.0)
	var mid := (a + b) * 0.5
	var gap := along * 18.0
	HUDDraw.line(self, a, mid - gap, 2.0, Color(HUDDraw.WHITE, 0.8))
	HUDDraw.line(self, mid + gap, b, 2.0, Color(HUDDraw.WHITE, 0.8))
	HUDDraw.line(self, a, a + tick, 2.0, Color(HUDDraw.WHITE, 0.8))
	HUDDraw.line(self, b, b + tick, 2.0, Color(HUDDraw.WHITE, 0.8))
	var label := "%d" % [absi(elevation)]
	HUDDraw.text(self, HUDDraw.font_mono(), b + along * 10.0 + Vector2(0, 7), label, 18,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, Color(HUDDraw.WHITE, 0.8))
