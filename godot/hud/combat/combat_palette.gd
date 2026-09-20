## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Alias del `CombatHUD` sobre [UIPalette] (`docs/13` §2.2, WP-25).
##
## Hasta WP-25 esta clase **duplicaba** los valores de la paleta oscura porque
## [UIPalette] todavía era la paleta clara del framework copiado (`docs/01` §2.3). Ya
## no: la paleta oscura vive en [UIPalette] y acá no queda un solo color propio, solo
## los nombres con los que el HUD de combate los llama.
##
## Se conserva la clase —en vez de reemplazar las referencias— porque los nombres de
## combate dicen **para qué** sirve cada color sobre el video: `TRACK` es el carril
## vacío de una barra, `BOX` el relleno de un marco, `TEXT_DIM` el rótulo de una
## distancia. La regla de `docs/13` sigue intacta: ámbar es lo propio, cian es de ellos.
class_name CombatHUDPalette
extends RefCounted

## Color **diegético**: puntos débiles, cajas de objetivo, barra del jefe y todo lo que
## pertenece al enemigo.
const TARGET: Color = UIPalette.TARGET

## Acento del jugador: energía, casco, calor, línea de objetivo. Ámbar.
const ACCENT: Color = UIPalette.ACCENT

## Peligro sobre video: energía crítica, casco roto, sobrecalentamiento, aviso de
## telegrafía y marcadores de enemigo.
const DANGER: Color = UIPalette.DANGER

## Algo bueno para el piloto: pilas y progreso cumplido.
const SUCCESS: Color = UIPalette.SUCCESS

## Texto del HUD sobre el video, en el mismo ámbar cálido que el HUD de vuelo.
const TEXT: Color = UIPalette.HUD_TEXT

## Texto secundario: rótulos, unidades, distancias.
const TEXT_DIM: Color = UIPalette.HUD_DIM

## Carcasa de una barra vacía o de un segmento todavía no gastado.
const TRACK: Color = UIPalette.HUD_TRACK

## Relleno de las cajas y marcos semitransparentes del HUD.
const BOX: Color = UIPalette.HUD_BOX

## Sombra de contorno, compartida con el HUD de vuelo.
const SHADOW: Color = UIPalette.HUD_SHADOW


## [param color] con la opacidad [param alpha], sin tocar el original.
static func with_alpha(color: Color, alpha: float) -> Color:
	return UIPalette.with_alpha(color, alpha)


## Interpola de [constant ACCENT] a [constant DANGER] según [param ratio], que es el
## degradado que piden la barra de calor y la de casco (`docs/12` §4.1).
static func heat_gradient(ratio: float) -> Color:
	return ACCENT.lerp(DANGER, clampf(ratio, 0.0, 1.0))
