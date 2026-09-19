## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cuatro barras de régimen de motor, en la disposición en X del cuadro
## (`docs/12` §2.1, §7 y §8).
##
## Los cuatro motores se dibujan **donde están**, vistos desde arriba y con el morro
## hacia arriba de la pantalla (`docs/03` §2.1): M1 delantero-izquierdo, M2
## delantero-derecho, M3 trasero-derecho y M4 trasero-izquierdo. Así, un alabeo a la
## derecha se lee como «las dos barras de la izquierda suben» sin tener que acordarse
## de qué índice es cada motor.
##
## [method update_rpm] recibe **rpm absolutas** y normaliza acá con
## [constant MAX_RPM] (`docs/12` §2.2): el HUD no consume fracciones porque el
## `max_rpm` del motor es del dron, no suyo. Un régimen negativo —reversa de TURTLE,
## `docs/03` §3.2— se dibuja hacia abajo desde la línea de reposo y en
## [constant UIPalette.HUD_REC], que es el único color de alarma que la paleta del
## HUD trae.
##
## Es un componente **continuo** (`docs/12` §2.3): valor instantáneo, cada frame.
class_name HUDRPM
extends Control

## Régimen con el que se normaliza la barra, en rpm (`docs/12` §8 y `docs/03` §10).
const MAX_RPM: float = 30000.0

## Alto útil de una barra, en píxeles.
const BAR_HEIGHT: float = 58.0

## Ancho de una barra, en píxeles.
const BAR_WIDTH: float = 14.0

## Separación horizontal entre los dos motores de un mismo lado, en píxeles.
const SPREAD_X: float = 74.0

## Separación vertical entre la fila delantera y la trasera, en píxeles.
const SPREAD_Y: float = 24.0

## Tamaño de la etiqueta con el número de motor, en píxeles.
const LABEL_SIZE: int = 14

## Ancho reservado para la etiqueta de cada motor, en píxeles. Va por **fuera** de su
## barra: entre las dos filas no hay sitio, y encima del tope la etiqueta se saldría
## del control.
const LABEL_WIDTH: float = 22.0

## Separación entre el borde de una barra y su etiqueta, en píxeles.
const LABEL_GAP: float = 4.0

## Posición de cada motor en la X, en el orden del mezclador de `docs/03` §3.5:
## M1 delantero-izquierdo, M2 delantero-derecho, M3 trasero-derecho, M4
## trasero-izquierdo. Son múltiplos de [constant SPREAD_X] y [constant SPREAD_Y].
const MOTOR_CELLS: Array[Vector2] = [
	Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5),
]

var _ratios: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
			SPREAD_X + BAR_WIDTH + (LABEL_GAP + LABEL_WIDTH) * 2.0 + 8.0,
			SPREAD_Y + BAR_HEIGHT * 2.0 + 8.0)


## Fija el régimen de los cuatro motores en rpm absolutas, en el orden del mezclador
## (`docs/12` §7). La normalización con [constant MAX_RPM] se hace acá.
func update_rpm(r1: float, r2: float, r3: float, r4: float) -> void:
	var changed := false
	var values: Array[float] = [r1, r2, r3, r4]
	for index: int in _ratios.size():
		var ratio := clampf(values[index] / MAX_RPM, -1.0, 1.0)
		if not is_equal_approx(ratio, _ratios[index]):
			_ratios[index] = ratio
			changed = true
	if changed:
		queue_redraw()


## Fracción de [constant MAX_RPM] que muestra el motor [param index] (0 a 3). Lo miran
## los checks.
func ratio_for(index: int) -> float:
	if index < 0 or index >= _ratios.size():
		return 0.0
	return _ratios[index]


func _draw() -> void:
	var centre := size * 0.5
	var faint := Color(HUDDraw.WHITE, 0.45)
	# Los dos brazos del cuadro, para que las cuatro barras se lean como un dron y no
	# como un ecualizador.
	var arm := Vector2(SPREAD_X, SPREAD_Y) * 0.5
	HUDDraw.line(self, centre - arm, centre + arm, 1.5, faint)
	HUDDraw.line(self, centre + Vector2(-arm.x, arm.y), centre + Vector2(arm.x, -arm.y),
			1.5, faint)

	for index: int in _ratios.size():
		_draw_bar(centre, index)


## Dibuja la barra del motor [param index] en su celda de la X.
func _draw_bar(centre: Vector2, index: int) -> void:
	var cell: Vector2 = MOTOR_CELLS[index]
	var ratio := _ratios[index]
	# La línea de reposo de la fila delantera está arriba y la barra crece hacia
	# arriba; la de la trasera está abajo y crece hacia abajo. Alejarse del centro es
	# siempre «más régimen».
	var direction := signf(cell.y)
	var base := Vector2(centre.x + cell.x * SPREAD_X, centre.y + cell.y * SPREAD_Y)
	var tip := base + Vector2(0.0, direction * BAR_HEIGHT * absf(ratio))
	var half_width := BAR_WIDTH * 0.5

	# Carril: dice cuánto queda hasta el tope aunque el motor esté al ralentí.
	var rail_tip := base + Vector2(0.0, direction * BAR_HEIGHT)
	HUDDraw.line(self, base, rail_tip, 1.5, Color(HUDDraw.WHITE, 0.3))

	var colour := HUDDraw.WHITE if ratio >= 0.0 else UIPalette.HUD_REC
	if absf(ratio) > 0.001:
		var top := minf(base.y, tip.y)
		var bottom := maxf(base.y, tip.y)
		var rect := Rect2(Vector2(base.x - half_width, top),
				Vector2(BAR_WIDTH, maxf(bottom - top, 1.0)))
		draw_rect(rect.grow(1.5), Color(HUDDraw.SHADOW, HUDDraw.SHADOW.a), true)
		draw_rect(rect, colour, true)

	# Tope de la barra y marca de reposo.
	HUDDraw.line(self, Vector2(base.x - half_width, base.y),
			Vector2(base.x + half_width, base.y), 2.0, Color(HUDDraw.WHITE, 0.8))

	# La etiqueta va del lado de afuera de su columna, a la altura de la línea de
	# reposo: es el único hueco que no pisa ni la barra ni el brazo del cuadro.
	var outward := signf(cell.x)
	var label_x := base.x + outward * (half_width + LABEL_GAP)
	if outward < 0.0:
		label_x -= LABEL_WIDTH
	var alignment := HORIZONTAL_ALIGNMENT_RIGHT if outward < 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	HUDDraw.text(self, HUDDraw.font_mono(), Vector2(label_x, base.y + 5.0),
			"%d" % [index + 1], LABEL_SIZE, alignment, LABEL_WIDTH,
			Color(HUDDraw.WHITE, 0.75))
