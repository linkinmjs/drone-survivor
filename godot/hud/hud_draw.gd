## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name HUDDraw
extends RefCounted
## Drawing helpers shared by the OSD components: white strokes with a soft dark edge so
## they stay readable over bright sky and dark ground alike.


const WHITE := Color(1, 1, 1, 0.96)
const SHADOW := Color(0, 0, 0, 0.35)

static var _font_bold: Font = null
static var _font_mono: Font = null


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = load(UIPalette.FONT_BOLD) as Font
	return _font_bold


static func font_mono() -> Font:
	if _font_mono == null:
		_font_mono = load(UIPalette.FONT_MONO) as Font
	return _font_mono


static func text(ci: CanvasItem, font: Font, pos: Vector2, value: String, font_size: int,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, color := WHITE) -> void:
	ci.draw_string_outline(font, pos, value, align, width, font_size, 5, Color(SHADOW, SHADOW.a * color.a))
	ci.draw_string(font, pos, value, align, width, font_size, color)


static func line(ci: CanvasItem, a: Vector2, b: Vector2, width := 2.0, color := WHITE) -> void:
	ci.draw_line(a, b, Color(SHADOW, SHADOW.a * color.a), width + 2.5, true)
	ci.draw_line(a, b, color, width, true)


static func circle(ci: CanvasItem, center: Vector2, radius: float, width := 2.0, color := WHITE) -> void:
	ci.draw_arc(center, radius, 0.0, TAU, 40, Color(SHADOW, SHADOW.a * color.a), width + 2.5, true)
	ci.draw_arc(center, radius, 0.0, TAU, 40, color, width, true)


## Draws a dashed polyline. Points that are not finite break the line. Dashes whose middle
## falls inside `hole_radius` around `hole_center` are skipped (keeps the crosshair clear).
static func dashed_polyline(ci: CanvasItem, points: PackedVector2Array, dash := 7.0, gap := 11.0,
		width := 3.5, color := WHITE, hole_center := Vector2.ZERO, hole_radius := 0.0) -> void:
	var period := dash + gap
	var phase := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		if not (a.is_finite() and b.is_finite()):
			phase = 0.0
			continue
		var seg_len := a.distance_to(b)
		if seg_len < 0.001 or seg_len > 4000.0:
			continue
		var t := 0.0
		while t < seg_len:
			var local := fmod(phase, period)
			var in_dash := local < dash
			var remaining := (dash - local) if in_dash else (period - local)
			var step := minf(remaining, seg_len - t)
			if in_dash:
				var p0 := a.lerp(b, t / seg_len)
				var p1 := a.lerp(b, (t + step) / seg_len)
				if hole_radius <= 0.0 or ((p0 + p1) * 0.5).distance_to(hole_center) > hole_radius:
					line(ci, p0, p1, width, color)
			t += step
			phase += step


static func fade(distance_from_center: float, half_extent: float, fade_length := 60.0) -> float:
	return clampf((half_extent - absf(distance_from_center)) / fade_length, 0.0, 1.0)
