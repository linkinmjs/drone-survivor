## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Colores del HUD de combate (`docs/13` § HUD y colores diegéticos).
##
## `docs/13` cierra la regla que gobierna todo lo que dibuja el `CombatHUD`:
##
## - **Cian es diegético**: marca lo que pertenece al enemigo y lo que se puede
##   romper —puntos débiles, cajas de objetivo, barra del jefe—. Nunca se usa para
##   información del jugador.
## - **Ámbar es lo propio**: energía, casco, calor, objetivos del piloto. Es el hue
##   de mayor contraste sobre un fondo casi negro y arrastra la connotación de radio
##   militar.
##
## ## Por qué esta clase existe y no se usa [UIPalette] directamente
##
## La paleta nueva completa —la oscura, militar y holográfica de `docs/13` §3— la
## entrega **WP-25**, que reescribe [UIPalette] y regenera los temas. Hoy [UIPalette]
## sigue siendo la paleta clara de menús que vino con el framework copiado
## (`docs/01` §2.3): su `ACCENT` es un azul de botón (`#2F7CF6`), su `DANGER` es un
## rojo oscuro pensado para fondo blanco (`#B3261E`) y no tiene `TARGET`. Ninguno de
## los tres se lee sobre el video de la cámara, y el azul además competiría con el
## cian diegético, que es justo lo que `docs/13` prohíbe.
##
## Los valores de acá son **los que `docs/13` §3 ya fijó** para esa paleta: cuando
## WP-25 los mueva a [UIPalette], esta clase se reduce a alias y ningún componente
## cambia. Lo que sí sale de [UIPalette] hoy —porque ya está en su valor final— se
## referencia tal cual: [constant UIPalette.HUD_TEXT] y [constant UIPalette.HUD_SHADOW].
class_name CombatHUDPalette
extends RefCounted

## Color **diegético** de `docs/13` §3: puntos débiles, cajas de objetivo, barra del
## jefe y todo lo que pertenece al enemigo.
const TARGET: Color = Color("#38E1FF")

## Acento del jugador: energía, casco, calor, línea de objetivo. Ámbar.
const ACCENT: Color = Color("#FFB020")

## Peligro sobre video: energía crítica, casco roto, sobrecalentamiento, aviso de
## telegrafía y marcadores de enemigo. Es el mismo rojo que [constant UIPalette.HUD_REC].
const DANGER: Color = Color("#FF4D3D")

## Algo bueno para el piloto: pilas y progreso cumplido.
const SUCCESS: Color = Color("#3FD18C")

## Texto del HUD sobre el video.
const TEXT: Color = UIPalette.HUD_TEXT

## Texto secundario: rótulos, unidades, distancias.
const TEXT_DIM: Color = Color(0.91, 0.96, 0.97, 0.66)

## Carcasa de una barra vacía o de un segmento todavía no gastado.
const TRACK: Color = Color(0.91, 0.96, 0.97, 0.22)

## Relleno de las cajas y marcos semitransparentes del HUD.
const BOX: Color = Color(0.02, 0.05, 0.07, 0.42)

## Sombra de contorno, compartida con el HUD de vuelo.
const SHADOW: Color = UIPalette.HUD_SHADOW


## [param color] con la opacidad [param alpha], sin tocar el original.
static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


## Interpola de [constant ACCENT] a [constant DANGER] según [param ratio], que es el
## degradado que piden la barra de calor y la de casco (`docs/12` §4.1).
static func heat_gradient(ratio: float) -> Color:
	return ACCENT.lerp(DANGER, clampf(ratio, 0.0, 1.0))
