## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ayudas de dibujo que comparten los componentes del HUD (`docs/12` §2.1).
##
## ## Qué cambió en WP-25
##
## El HUD dejó de ser blanco de consola. Ahora es **ámbar sobre la señal**
## ([constant UIPalette.HUD_TEXT]), con trazo fino de [constant UIPalette.HUD_STROKE]
## píxeles y un contorno oscuro de [constant UIPalette.HUD_OUTLINE] píxeles —tres, no
## cinco—. La regla de identidad del checkpoint 3b es que nada propio es cian y nada
## enemigo es cálido: el instrumental del piloto es lo más propio que hay en pantalla.
##
## El contorno sigue existiendo porque sobre el video no hay fondo en el que apoyarse:
## la misma línea cruza cielo claro y asfalto oscuro en el mismo cuadro.
class_name HUDDraw
extends RefCounted

## Color del instrumental: ámbar cálido sobre la señal.
const TEXT := UIPalette.HUD_TEXT

## Alias histórico de [constant TEXT].
##
## Se conserva el nombre —aunque ya no valga blanco— porque lo consumen componentes
## de `rounds/**`, que no son de este paquete: así heredan el ámbar nuevo sin tocarlos.
const WHITE := UIPalette.HUD_TEXT

## Rótulos, unidades y distancias: el mismo ámbar con menos cuerpo.
const DIM := UIPalette.HUD_DIM

## Carril de una barra o de una cinta todavía no recorrida.
const TRACK := UIPalette.HUD_TRACK

## Relleno oscuro de una caja del HUD: apoya el texto sin taparle la imagen al piloto.
const BOX := UIPalette.HUD_BOX

## Única alarma del HUD: reversa, energía crítica, telegrafía.
const ALERT := UIPalette.HUD_REC

## Contorno oscuro de todo lo que dibuja el HUD.
const SHADOW := UIPalette.HUD_SHADOW

## Grosor del trazo fino.
const STROKE := UIPalette.HUD_STROKE

## Grosor del contorno de texto, en píxeles.
const OUTLINE := UIPalette.HUD_OUTLINE

static var _font_display: Font = null
static var _font_text: Font = null
static var _font_mono: Font = null


## Chakra Petch SemiBold: rótulos de máquina y letras grandes del HUD.
static func font_display() -> Font:
	if _font_display == null:
		_font_display = load(UIPalette.FONT_DISPLAY) as Font
	return _font_display


## Alias histórico de [method font_display], que consumen componentes de `rounds/**`.
static func font_bold() -> Font:
	return font_display()


## Barlow Semi Condensed Medium: los rótulos chicos de la voz propia.
static func font_text() -> Font:
	if _font_text == null:
		_font_text = load(UIPalette.FONT_MEDIUM) as Font
	return _font_text


## JetBrains Mono al peso [constant UIPalette.FONT_MONO_WEIGHT]: todo lo que sea un
## número que el piloto lee de un vistazo.
static func font_mono() -> Font:
	if _font_mono == null:
		var variation := FontVariation.new()
		variation.base_font = load(UIPalette.FONT_MONO) as Font
		var server := TextServerManager.get_primary_interface()
		if server != null:
			variation.variation_opentype = {
				server.name_to_tag("wght"): UIPalette.FONT_MONO_WEIGHT,
			}
		_font_mono = variation
	return _font_mono


static func text(ci: CanvasItem, font: Font, pos: Vector2, value: String, font_size: int,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, color := TEXT) -> void:
	ci.draw_string_outline(font, pos, value, align, width, font_size, OUTLINE,
			Color(SHADOW, SHADOW.a * color.a))
	ci.draw_string(font, pos, value, align, width, font_size, color)


static func line(ci: CanvasItem, a: Vector2, b: Vector2, width := STROKE, color := TEXT) -> void:
	ci.draw_line(a, b, Color(SHADOW, SHADOW.a * color.a), width + 2.0, true)
	ci.draw_line(a, b, color, width, true)


static func circle(ci: CanvasItem, center: Vector2, radius: float, width := STROKE,
		color := TEXT) -> void:
	ci.draw_arc(center, radius, 0.0, TAU, 40, Color(SHADOW, SHADOW.a * color.a), width + 2.0, true)
	ci.draw_arc(center, radius, 0.0, TAU, 40, color, width, true)


## Marco rectangular de radio [constant UIPalette.RADIUS] con su contorno oscuro. Es la
## caja de la identidad nueva: esquinas rectas, una línea fina y nada más.
static func box(ci: CanvasItem, rect: Rect2, width := STROKE, color := TEXT,
		fill := Color.TRANSPARENT) -> void:
	if fill.a > 0.0:
		ci.draw_rect(rect, fill, true)
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.anti_aliasing = false
	style.set_corner_radius_all(UIPalette.RADIUS)
	style.corner_detail = 2
	style.set_border_width_all(int(ceilf(width + 2.0)))
	style.border_color = Color(SHADOW, SHADOW.a * color.a)
	ci.draw_style_box(style, rect.grow(1.0))
	style.set_border_width_all(maxi(int(roundf(width)), 1))
	style.border_color = color
	ci.draw_style_box(style, rect)


## Dibuja una polilínea punteada. Los puntos no finitos cortan la línea. Los guiones
## cuyo centro cae dentro de `hole_radius` alrededor de `hole_center` se saltean (deja
## limpio el retículo).
static func dashed_polyline(ci: CanvasItem, points: PackedVector2Array, dash := 6.0, gap := 10.0,
		width := STROKE, color := TEXT, hole_center := Vector2.ZERO, hole_radius := 0.0) -> void:
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
