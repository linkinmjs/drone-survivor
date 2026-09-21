## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Indicador de **señal** del HUD de vuelo (WP-25; reemplaza al punto «REC»).
##
## ## Por qué ya no dice REC
##
## El punto rojo de grabación venía del simulador de vuelo, donde el dron graba la
## vuelta como repetición (`docs/01` §2.3). Acá no hay repetición: lo que hay es una
## **señal de video** que llega del dron al taller, y lo que el piloto necesita saber
## es si esa señal está sana. La narrativa lo dice en `docs/narrativa/narrativa.md` §4:
## «lo que ve el jugador es exactamente lo que ve el dron». Cuando la señal se degrada
## —daño, EMP— el HUD tiene que decirlo antes de ponerse feo.
##
## Cuatro barras crecientes y el rótulo `HUD_SIGNAL`. La calidad se fija con
## [method set_quality]; desde WP-28 la publica [method DroneRig._feed_hud] con la
## cifra de [method FPVOverlay.signal_quality], así que las barras bajan exactamente
## con el daño del casco y con el EMP que está rompiendo la imagen. Umbrales:
## cuatro barras por encima de 0,75; tres por encima de 0,5; dos por encima de 0,25;
## una por debajo, y ahí además parpadea.
##
## Es un componente **continuo** solo mientras la señal está baja: con señal plena no
## anima nada y no pide redibujo.
class_name HUDSignalIndicator
extends Control

## Clave de traducción del rótulo.
const LABEL_KEY: String = "HUD_SIGNAL"

## Cantidad de barras.
const BAR_COUNT: int = 4

## Ancho de una barra, en píxeles.
const BAR_WIDTH: float = 6.0

## Separación entre barras, en píxeles.
const BAR_GAP: float = 4.0

## Alto de la barra más alta, en píxeles.
const BAR_MAX_HEIGHT: float = 26.0

## Alto de la barra más baja, en píxeles.
const BAR_MIN_HEIGHT: float = 9.0

## Cuerpo del rótulo, en píxeles.
const FONT_SIZE: int = 16

## Por debajo de esta calidad el indicador parpadea y se pone en
## [constant HUDDraw.ALERT]: la señal se está yendo.
##
## Es exactamente el umbral de la **última barra**: [method lit_bars] enciende cuatro
## por encima de 0.75, tres por encima de 0.5, dos por encima de 0.25 y una por debajo.
## Hacer coincidir las dos cosas es lo que deja leer el indicador de un vistazo: una
## barra sola **y** parpadeando quiere decir lo mismo, y no hay una banda intermedia
## donde la señal parpadea con dos barras encendidas (WP-28).
const CRITICAL_QUALITY: float = 0.25

## Parpadeo de la señal crítica, en Hz.
const BLINK_HZ: float = 2.0

## Opacidad del semiciclo apagado del parpadeo.
const BLINK_DIM_ALPHA: float = 0.3

## Calidad de la señal, de 0 (sin imagen) a 1 (señal limpia).
var quality: float = 1.0

## Mientras sea `false` el componente no dibuja nada. Lo escribe
## `FlightHUD.show_component(Component.SIGNAL, …)`.
var active: bool = true:
	set(value):
		if value != active:
			active = value
			_refresh_process()
			queue_redraw()

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
			BAR_COUNT * BAR_WIDTH + (BAR_COUNT - 1) * BAR_GAP + 86.0,
			BAR_MAX_HEIGHT + 8.0)
	_refresh_process()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## El `_process` se enciende **solo mientras la señal está en crítico**, que es lo
## único que necesita reloj: el parpadeo.
##
## Antes el nodo pedía un frame por frame y salía por la primera línea. La llamada
## vacía no cuesta casi nada sola, pero el HUD tiene doce componentes y la vista previa
## del menú monta un `FlightHUD` entero de más: el criterio del proyecto es que un
## componente continuo lo sea **cuando tiene algo que animar** (`docs/12` §2.3).
func _refresh_process() -> void:
	set_process(active and quality <= CRITICAL_QUALITY)


## Fija la calidad de la señal, de 0 a 1 (`docs/12` §2.2, ampliación de WP-25).
func set_quality(value: float) -> void:
	var wanted := clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	if is_equal_approx(wanted, quality):
		return
	quality = wanted
	_time = 0.0
	_refresh_process()
	queue_redraw()


## Cantidad de barras encendidas con la calidad actual. Lo miran los checks.
func lit_bars() -> int:
	return clampi(int(ceilf(quality * BAR_COUNT)), 0, BAR_COUNT)


func _draw() -> void:
	if not active:
		return
	var critical := quality <= CRITICAL_QUALITY
	var color := HUDDraw.ALERT if critical else HUDDraw.TEXT
	var alpha := 1.0
	if critical and fmod(_time * BLINK_HZ, 1.0) >= 0.5:
		alpha = BLINK_DIM_ALPHA
	var lit := lit_bars()
	var base_y := (size.y + BAR_MAX_HEIGHT) * 0.5
	for index: int in BAR_COUNT:
		var height := lerpf(BAR_MIN_HEIGHT, BAR_MAX_HEIGHT, float(index) / float(BAR_COUNT - 1))
		var rect := Rect2(Vector2(index * (BAR_WIDTH + BAR_GAP), base_y - height),
				Vector2(BAR_WIDTH, height))
		if index < lit:
			draw_rect(rect.grow(1.0), Color(HUDDraw.SHADOW, HUDDraw.SHADOW.a * alpha), true)
			draw_rect(rect, Color(color, alpha), true)
		else:
			draw_rect(rect, Color(HUDDraw.TRACK, HUDDraw.TRACK.a * alpha), true)
	var label_x := BAR_COUNT * (BAR_WIDTH + BAR_GAP) + 6.0
	HUDDraw.text(self, HUDDraw.font_text(), Vector2(label_x, base_y), tr(LABEL_KEY), FONT_SIZE,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, Color(color, alpha))
