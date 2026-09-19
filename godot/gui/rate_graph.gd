## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Gráfico de las curvas de rates del hangar (`docs/04` §4.7).
##
## Dibuja, para los tres ejes a la vez, qué velocidad de giro pide cada posición del
## stick: el eje horizontal es la deflexión de −1 a 1 y el vertical, grados por segundo.
## Arriba a la izquierda escribe la tasa máxima de cada eje, que es el número con el que
## se comparan dos ajustes.
##
## No conoce el hangar ni la persistencia: recibe un [ControlProfile] con
## [method set_profile] y se redibuja cuando se lo pide [method refresh]. Todo lo que
## dibuja sale de [method ControlProfile.get_rate], así que el gráfico y el vuelo no
## pueden discrepar.
class_name RateGraph
extends Control

## Color de cada curva, en el orden de [enum ControlProfile.Axis] (roll, pitch, yaw).
const AXIS_COLORS: Array[Color] = [UIPalette.GRAPH_ROLL, UIPalette.GRAPH_PITCH,
		UIPalette.GRAPH_YAW]

## Clave de traducción del nombre de cada eje, en el mismo orden.
const AXIS_KEYS: Array[String] = ["QUAD_ROLL", "QUAD_PITCH", "QUAD_YAW"]

## Orden en que se listan las etiquetas: pitch primero, como en el hangar.
const LABEL_ORDER: Array[int] = [ControlProfile.Axis.PITCH, ControlProfile.Axis.ROLL,
		ControlProfile.Axis.YAW]

## Muestras por curva. Impar, para que el centro exacto (x = 0) sea una muestra.
const SAMPLES: int = 81

## Divisiones de la rejilla en cada mitad del gráfico.
const GRID_STEPS: int = 4

## Grosor de las curvas, en píxeles.
const CURVE_WIDTH: float = 2.0

## Margen interior, en píxeles.
const PADDING: float = 10.0

## Tasa mínima con la que se escala el eje vertical, para que un perfil en cero no
## divida por cero ni dibuje una recta infinita.
const MIN_TOP_RATE: float = 1.0

## Tamaño de las etiquetas de tasa máxima, en píxeles.
const LABEL_SIZE: int = 13

var _profile: ControlProfile = null
var _max_rates: Vector3 = Vector3.ZERO
var _draws: int = 0
var _refreshes: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		queue_redraw()


## Fija el perfil que se dibuja y redibuja. Se puede llamar con el mismo objeto cada
## vez: el hangar modifica el perfil vivo de `QuadSettings` en el lugar.
func set_profile(profile: ControlProfile) -> void:
	_profile = profile
	refresh()


## Recalcula las tasas máximas y pide un redibujo. La llama el hangar cada vez que
## cambia un valor.
func refresh() -> void:
	_refreshes += 1
	_max_rates = Vector3.ZERO
	if _profile != null:
		for axis: int in 3:
			_max_rates[axis] = _profile.get_max_rate(axis)
	queue_redraw()


## Tasa máxima de cada eje en deg/s (`x` roll, `y` pitch, `z` yaw).
func max_rates() -> Vector3:
	return _max_rates


## Cuántas veces se pidió un redibujo. Lo mira `tools/ui_smoke_test.gd`.
func refresh_count() -> int:
	return _refreshes


## Cuántas veces se dibujó de verdad. En `--headless` no hay rasterizado y se queda
## en cero: por eso el check solo lo exige con ventana.
func draw_count() -> int:
	return _draws


func _draw() -> void:
	_draws += 1
	var inner := Rect2(Vector2(PADDING, PADDING), size - Vector2(PADDING, PADDING) * 2.0)
	if inner.size.x < 8.0 or inner.size.y < 8.0:
		return
	_draw_grid(inner)
	if _profile == null:
		return
	var top := maxf(MIN_TOP_RATE, maxf(_max_rates.x, maxf(_max_rates.y, _max_rates.z)))
	for axis: int in 3:
		_draw_curve(inner, axis, top)
	_draw_labels(inner)


## Rejilla, ejes y marcas de deflexión.
func _draw_grid(inner: Rect2) -> void:
	var center := inner.position + inner.size * 0.5
	for step: int in range(-GRID_STEPS, GRID_STEPS + 1):
		var fraction := float(step) / float(GRID_STEPS)
		var x := center.x + fraction * inner.size.x * 0.5
		var y := center.y + fraction * inner.size.y * 0.5
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y),
				UIPalette.GRAPH_GRID, 1.0)
		draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y),
				UIPalette.GRAPH_GRID, 1.0)
	draw_line(Vector2(inner.position.x, center.y), Vector2(inner.end.x, center.y),
			UIPalette.BORDER_STRONG, 1.0)
	draw_line(Vector2(center.x, inner.position.y), Vector2(center.x, inner.end.y),
			UIPalette.BORDER_STRONG, 1.0)


## Curva de un eje, escalada contra la tasa máxima de los tres.
func _draw_curve(inner: Rect2, axis: int, top: float) -> void:
	var center_y := inner.position.y + inner.size.y * 0.5
	var points := PackedVector2Array()
	for sample: int in SAMPLES:
		var deflection := -1.0 + 2.0 * float(sample) / float(SAMPLES - 1)
		var omega := _profile.get_rate(axis, deflection)
		var x := inner.position.x + (deflection * 0.5 + 0.5) * inner.size.x
		var y := center_y - clampf(omega / top, -1.0, 1.0) * inner.size.y * 0.5
		points.append(Vector2(x, y))
	draw_polyline(points, AXIS_COLORS[axis], CURVE_WIDTH, true)


## Tasa máxima de cada eje, en el color de su curva.
func _draw_labels(inner: Rect2) -> void:
	var font := _label_font()
	if font == null:
		return
	var line := inner.position + Vector2(6.0, float(LABEL_SIZE) + 2.0)
	for axis: int in LABEL_ORDER:
		var text := "%s  %d" % [tr(AXIS_KEYS[axis]), int(roundf(_max_rates[axis]))]
		draw_string(font, line, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE,
				AXIS_COLORS[axis])
		line.y += float(LABEL_SIZE) + 4.0


func _label_font() -> Font:
	var font := get_theme_font(&"font", &"Label")
	return font if font != null else ThemeDB.fallback_font
