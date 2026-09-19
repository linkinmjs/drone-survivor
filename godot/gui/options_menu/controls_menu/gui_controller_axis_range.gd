## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Control de dos manijas para la banda `[axis_min, axis_max]` de un binding de
## eje (`docs/04` §4.5).
##
## Un interruptor de tres posiciones de una radio, o un gatillo analógico, no
## dispara una acción en un punto sino dentro de un tramo del recorrido del eje.
## Este control es el que deja elegir ese tramo: dibuja el eje de −1 a 1, la
## banda elegida, las dos manijas y un marcador con la deflexión real del eje,
## para que el jugador vea si su interruptor cae dentro o fuera.
##
## Navegación: lleva la meta `stick_value_control`, así que `StickNavigation`
## convierte el roll en `ui_left`/`ui_right` en vez de aceptar o cancelar
## (`docs/04` §5). `ui_left` y `ui_right` mueven la manija activa y `ui_accept`
## cambia de manija; con el ratón se arrastra la más cercana.
class_name GUIControllerAxisRange
extends Control

## Se emite en cada cambio de la banda, mientras el jugador la mueve.
signal range_updated(lo: float, hi: float)

## Se emite al soltar: el momento en que conviene persistir el valor.
signal range_released

## Manija del extremo bajo de la banda.
const HANDLE_LOW: int = 0

## Manija del extremo alto de la banda.
const HANDLE_HIGH: int = 1

## Cuánto mueve la manija activa cada pulsación de `ui_left` / `ui_right`.
const STEP: float = 0.05

## Separación mínima entre las dos manijas: una banda vacía no dispararía nunca.
const MIN_WIDTH: float = 0.05

## Tamaño mínimo del control; el alto deja sitio al marcador del eje en vivo.
const MIN_SIZE: Vector2 = Vector2(280, 52)

## Radio de las manijas, también el margen lateral del carril.
const HANDLE_RADIUS: float = 9.0

## Extremo bajo de la banda, en `[−1, 1]`.
var axis_min: float = 0.5

## Extremo alto de la banda, en `[−1, 1]`.
var axis_max: float = 1.0

## Deflexión real del eje, solo para dibujar el marcador.
var live_value: float = 0.0

## Manija que mueven `ui_left` y `ui_right`.
var active_handle: int = HANDLE_HIGH

var _dragging: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = MIN_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# `StickNavigation` lee esta meta para navegar valores con el roll en vez de
	# aceptar o cancelar (`docs/04` §5).
	set_meta(&"stick_value_control", true)
	var _discard := focus_entered.connect(queue_redraw)
	_discard = focus_exited.connect(queue_redraw)


## Fija la banda sin emitir señales; lo usa el popup al abrirse.
func setup(lo: float, hi: float) -> void:
	axis_min = clampf(minf(lo, hi), -1.0, 1.0)
	axis_max = clampf(maxf(lo, hi), -1.0, 1.0)
	if axis_max - axis_min < MIN_WIDTH:
		axis_max = minf(axis_min + MIN_WIDTH, 1.0)
		axis_min = maxf(axis_max - MIN_WIDTH, -1.0)
	queue_redraw()


## Vuelca la deflexión real del eje para el marcador.
func set_live_value(raw: float) -> void:
	var clamped := clampf(raw, -1.0, 1.0)
	if is_equal_approx(live_value, clamped):
		return
	live_value = clamped
	queue_redraw()


## La banda elegida, como `Vector2(mínimo, máximo)`.
func band() -> Vector2:
	return Vector2(axis_min, axis_max)


## Verdadero si la deflexión cae dentro de la banda.
func contains(raw: float) -> bool:
	return raw >= axis_min and raw <= axis_max


# --- Entrada ---------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		if click.pressed:
			grab_focus()
			active_handle = _nearest_handle(click.position.x)
			_dragging = true
			_move_active(_x_to_value(click.position.x))
		elif _dragging:
			_dragging = false
			range_released.emit()
		return
	if event is InputEventMouseMotion and _dragging:
		accept_event()
		_move_active(_x_to_value((event as InputEventMouseMotion).position.x))
		return
	if event.is_action_pressed(&"ui_left", true, true):
		accept_event()
		_move_active(_active_value() - STEP)
		return
	if event.is_action_pressed(&"ui_right", true, true):
		accept_event()
		_move_active(_active_value() + STEP)
		return
	if event.is_action_released(&"ui_left", true) or event.is_action_released(&"ui_right", true):
		accept_event()
		range_released.emit()
		return
	if event.is_action_pressed(&"ui_accept", false, true):
		# Sin dos botones extra: aceptar alterna cuál de las manijas se mueve.
		accept_event()
		active_handle = HANDLE_LOW if active_handle == HANDLE_HIGH else HANDLE_HIGH
		UI.play("tick")
		queue_redraw()


## Mueve la manija activa a [param target] y mantiene el orden de los extremos.
func _move_active(target: float) -> void:
	var wanted := clampf(target, -1.0, 1.0)
	if active_handle == HANDLE_LOW:
		axis_min = minf(wanted, axis_max - MIN_WIDTH)
	else:
		axis_max = maxf(wanted, axis_min + MIN_WIDTH)
	axis_min = clampf(axis_min, -1.0, 1.0)
	axis_max = clampf(axis_max, -1.0, 1.0)
	queue_redraw()
	range_updated.emit(axis_min, axis_max)


func _active_value() -> float:
	return axis_min if active_handle == HANDLE_LOW else axis_max


func _nearest_handle(x: float) -> int:
	return HANDLE_LOW if absf(x - _value_to_x(axis_min)) <= absf(x - _value_to_x(axis_max)) \
			else HANDLE_HIGH


# --- Dibujo ----------------------------------------------------------------------------------

func _value_to_x(raw: float) -> float:
	var usable := maxf(size.x - HANDLE_RADIUS * 2.0, 1.0)
	return HANDLE_RADIUS + (clampf(raw, -1.0, 1.0) + 1.0) * 0.5 * usable


func _x_to_value(x: float) -> float:
	var usable := maxf(size.x - HANDLE_RADIUS * 2.0, 1.0)
	return clampf((x - HANDLE_RADIUS) / usable * 2.0 - 1.0, -1.0, 1.0)


func _draw() -> void:
	var middle := size.y * 0.5
	var low_x := _value_to_x(axis_min)
	var high_x := _value_to_x(axis_max)

	draw_rect(Rect2(HANDLE_RADIUS, middle - 3.0, size.x - HANDLE_RADIUS * 2.0, 6.0),
			UIPalette.SURFACE_PRESSED)
	draw_rect(Rect2(low_x, middle - 7.0, maxf(high_x - low_x, 1.0), 14.0), UIPalette.ACCENT_SOFT)
	draw_rect(Rect2(low_x, middle - 7.0, maxf(high_x - low_x, 1.0), 14.0), UIPalette.ACCENT,
			false, 2.0)

	# Centro del eje, como referencia del reposo de un stick.
	var center_x := _value_to_x(0.0)
	draw_line(Vector2(center_x, middle - 10.0), Vector2(center_x, middle + 10.0),
			UIPalette.BORDER_STRONG, 1.0)

	# Deflexión real: verde dentro de la banda, gris fuera.
	var live_x := _value_to_x(live_value)
	draw_line(Vector2(live_x, middle - 16.0), Vector2(live_x, middle + 16.0),
			UIPalette.SUCCESS if contains(live_value) else UIPalette.TEXT_2, 2.0)

	_draw_handle(Vector2(low_x, middle), active_handle == HANDLE_LOW)
	_draw_handle(Vector2(high_x, middle), active_handle == HANDLE_HIGH)

	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), UIPalette.ACCENT, false, 2.0)


func _draw_handle(center: Vector2, active: bool) -> void:
	draw_circle(center, HANDLE_RADIUS, UIPalette.SURFACE)
	draw_arc(center, HANDLE_RADIUS - 1.0, 0.0, TAU, 24,
			UIPalette.ACCENT if active else UIPalette.BORDER_STRONG, 2.5)
