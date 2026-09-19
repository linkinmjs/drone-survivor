## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Mensajes de armado del HUD de vuelo (`docs/12` §2.6 y §7).
##
## Es el único componente del HUD que **no** se puede apagar: `STATUS` está en el
## `enum Component` para que `show_component()` pueda esconderlo en capturas y en el
## modo cinemático, pero no tiene interruptor en `hud_config` (`docs/12` §2.4). Si el
## dron no arma, el piloto tiene que enterarse aunque haya vaciado el HUD entero.
##
## Dos canales que se pisan en un orden fijo:
## - **Mensaje momentáneo** ([method show_message]): armado, fallo de armado. Se
##   mantiene [constant MESSAGE_SECONDS] a plena opacidad y después se desvanece en
##   [constant FADE_SECONDS]. Tapa al persistente mientras dure.
## - **Persistente** ([method set_persistent]): el «DESARMADO» que parpadea a
##   [constant BLINK_HZ] mientras el dron no esté armado. Se limpia con `""`.
##
## El color llega por argumento y se aplica con [member CanvasItem.modulate], que es
## exacto porque `hud_theme.tres` pinta la fuente de blanco puro
## ([constant UIPalette.HUD_TEXT]): modular blanco por un color **es** ese color, y
## además el contorno se desvanece junto con el texto en vez de quedarse marcado.
##
## Discrepancia registrada con `docs/12` §7: la tabla de interfaz pública declara
## `HUDStatus extends Control`. Acá extiende [Label], que es lo que pide el brief de
## WP-08 y lo que corresponde: el componente es una sola línea de texto centrada con
## contorno, justo lo que `hud_theme.tres` ya define para `Label`. Los dos métodos
## públicos de §7 ([method show_message] y [method set_persistent]) se respetan tal cual.
class_name HUDStatus
extends Label

## Segundos que un mensaje momentáneo se mantiene a plena opacidad (`docs/12` §8).
const MESSAGE_SECONDS: float = 1.6

## Segundos de desvanecido que siguen a [constant MESSAGE_SECONDS]. Un mensaje de
## armado queda del todo apagado a los 2.0 s de aparecer.
const FADE_SECONDS: float = 0.4

## Parpadeo del texto persistente de desarmado, en Hz (`docs/12` §8).
const BLINK_HZ: float = 1.0

## Parpadeo de un fallo de armado, en Hz. Más rápido que el de desarmado a propósito:
## es un rechazo, no un estado.
const ALERT_BLINK_HZ: float = 4.0

## Opacidad del semiciclo apagado de un parpadeo. No baja a cero para que el texto no
## desaparezca del todo entre destellos.
const BLINK_DIM_ALPHA: float = 0.18

## Apaga el componente entero sin perder su estado. Es lo que mueve
## `FlightHUD.show_component(Component.STATUS, …)` para el modo cinemático y las
## capturas (`docs/12` §2.4); el canal de mensajes sigue funcionando por debajo y
## vuelve a verse en cuanto esto sea `true`.
##
## No se usa [member CanvasItem.visible] directamente porque [method _refresh] lo
## reescribe en cada frame según haya o no texto que mostrar: un `visible = false`
## de afuera duraría un cuadro.
var enabled: bool = true:
	set = set_enabled

var _key: String = ""
var _color: Color = UIPalette.HUD_TEXT
var _alert: bool = false
var _hold: float = 0.0
var _fade: float = 0.0

var _persistent_key: String = ""
var _persistent_color: Color = UIPalette.HUD_TEXT
var _persistent_blink: bool = true

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	if _hold > 0.0:
		_hold = maxf(_hold - delta, 0.0)
	elif _fade > 0.0:
		_fade = maxf(_fade - delta, 0.0)
		if _fade <= 0.0:
			_key = ""
			_alert = false
	_refresh()


## Muestra [param text_key] durante [param seconds] y lo desvanece después
## (`docs/12` §7). [param seconds] menor o igual a cero lo deja fijo hasta el
## siguiente mensaje o hasta [method clear].
##
## [param blink] hace que el mensaje parpadee a [constant ALERT_BLINK_HZ] mientras
## dure: es lo que distingue un rechazo de armado de una confirmación.
func show_message(text_key: String, color: Color, seconds: float, blink: bool = false) -> void:
	_key = text_key
	_color = color
	_alert = blink
	_hold = maxf(seconds, 0.0)
	_fade = FADE_SECONDS if seconds > 0.0 else 0.0
	_time = 0.0
	_refresh()


## Texto que se mantiene mientras no haya mensaje momentáneo encima (`docs/12` §7).
## Una cadena vacía lo limpia.
##
## [param blink] hace que lata a [constant BLINK_HZ], que es lo que `docs/12` §2.6 le
## pide al «DESARMADO». La vista previa del menú de HUD lo apaga: ahí el texto es un
## rótulo de estado, no una alarma.
func set_persistent(text_key: String, color: Color = UIPalette.HUD_TEXT,
		blink: bool = true) -> void:
	_persistent_key = text_key
	_persistent_color = color
	_persistent_blink = blink
	_refresh()


## `set` de [member enabled].
func set_enabled(value: bool) -> void:
	enabled = value
	_refresh()


## Apaga los dos canales de una vez.
func clear() -> void:
	_key = ""
	_alert = false
	_hold = 0.0
	_fade = 0.0
	_persistent_key = ""
	_persistent_blink = true
	_refresh()


## Clave que se está mostrando ahora mismo, o `""` si el componente está apagado.
## Lo miran `hud_projection_check` y `ui_smoke_test`.
func current_key() -> String:
	return _key if not _key.is_empty() else _persistent_key


## Verdadero mientras haya un mensaje momentáneo vivo (todavía visible, aunque se
## esté desvaneciendo).
func has_message() -> bool:
	return not _key.is_empty()


## Vuelca el estado de los dos canales sobre el [Label].
func _refresh() -> void:
	var shown_key := _key
	var shown_color := _color
	var alpha := 1.0
	if shown_key.is_empty():
		shown_key = _persistent_key
		shown_color = _persistent_color
		if shown_key.is_empty():
			alpha = 0.0
		elif _persistent_blink:
			alpha = _blink_alpha(BLINK_HZ)
	else:
		if _hold <= 0.0 and FADE_SECONDS > 0.0:
			alpha = clampf(_fade / FADE_SECONDS, 0.0, 1.0)
		if _alert:
			alpha *= _blink_alpha(ALERT_BLINK_HZ)
	if text != shown_key:
		text = shown_key
	var wanted := Color(shown_color.r, shown_color.g, shown_color.b, shown_color.a * alpha)
	if not modulate.is_equal_approx(wanted):
		modulate = wanted
	var wanted_visible := enabled and not shown_key.is_empty()
	if visible != wanted_visible:
		visible = wanted_visible


## Onda cuadrada de [param hz] ciclos por segundo entre `1.0` y
## [constant BLINK_DIM_ALPHA].
func _blink_alpha(hz: float) -> float:
	if hz <= 0.0:
		return 1.0
	return 1.0 if fmod(_time * hz, 1.0) < 0.5 else BLINK_DIM_ALPHA
