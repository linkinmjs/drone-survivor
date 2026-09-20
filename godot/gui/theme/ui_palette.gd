## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Paleta única de la interfaz (`docs/13` §2.2, dirección **A · Última luz**).
##
## ## Ámbar = gente, cian = máquina
##
## La regla de coherencia que eligió el checkpoint 3b vale para **todo** lo que se
## dibuja: nada enemigo es cálido y nada propio es cian.
##
## - [constant ACCENT] (ámbar `#FFB020`) es la voz propia: foco, valores activos,
##   energía, casco, la pantalla del taller. Es el hue de mayor contraste sobre un
##   fondo casi negro (10,7:1) y arrastra la connotación de radio de barrio.
## - [constant TARGET] (cian `#38E1FF`) es **diegético**: marca lo que pertenece al
##   enemigo y lo que se puede romper —puntos débiles, cajas de objetivo, barra del
##   jefe—. Nunca se usa como acento de interfaz: si la UI también fuera cian, el
##   jugador no distinguiría «información mía» de «objetivo».
##
## ## Quién la consume
##
## Es la **única** fuente de verdad de color y métrica. `gui/theme/theme_builder.gd`
## arma con ella `gui/theme/main_theme.tres` y `hud/hud_theme.tres` desde
## `tools/build_theme.gd`, que además verifica que todo par texto/fondo pase 4,5:1.
## Los `.tres` no se editan a mano. [CombatHUDPalette] es un alias de esta clase.
##
## ## Tres voces tipográficas (`docs/13` §2.3)
##
## - [constant FONT_DISPLAY] **Chakra Petch SemiBold**: títulos, marca y códigos
##   enemigos. Angosta, terminaciones cortadas, mayúsculas de máquina.
## - [constant FONT_REGULAR] / [constant FONT_MEDIUM] **Barlow Semi Condensed**: la
##   voz propia, o sea menús, descripciones, consejos y rótulos.
## - [constant FONT_MONO] **JetBrains Mono**: readouts, HUD numérico y gráficos, donde
##   lo único que importa es que 0/O y 1/l no se confundan.
##
## Las tres son SIL OFL 1.1 y guardan su licencia en `gui/theme/fonts/<familia>/LICENSE.txt`.
class_name UIPalette
extends RefCounted

# --- Fondos ----------------------------------------------------------------------------------

## Fondo base de pantallas. Casi negro con una gota de azul: es «de noche», no «apagado».
const BG := Color("#0A0D10")

## Extremo superior del degradado de fondo de [MenuScreen].
const BG_TOP := Color("#0E1318")

## Extremo inferior del degradado de fondo.
const BG_BOTTOM := Color("#05070A")

## Velo sobre el nivel o el backdrop 3D (80 %). Lo usan la pausa y los menús abiertos
## sobre el vuelo.
const SCRIM := Color(0.02, 0.027, 0.039, 0.8)

## Paneles y tarjetas.
const SURFACE := Color("#131A20")

## Filas alternas y campos.
const SURFACE_ALT := Color("#1A232B")

## Hover y presionado.
const SURFACE_HOVER := Color("#22303A")

## Alias histórico de [constant SURFACE_HOVER] (carriles de deslizador, fondo de barra).
const SURFACE_PRESSED := SURFACE_HOVER

## Fondo de un control deshabilitado: por debajo de [constant SURFACE], nunca por encima.
const SURFACE_DISABLED := Color("#10161C")

# --- Bordes ----------------------------------------------------------------------------------

## Borde de 1 px de paneles y botones.
const BORDER := Color("#2A3742")

## Separadores, encabezados y bordes de estado hover.
const BORDER_STRONG := Color("#3E5261")

## Anillo de foco, 2 px. Es ámbar a propósito: el foco es del jugador.
const BORDER_FOCUS := Color("#FFB020")

# --- Texto -----------------------------------------------------------------------------------

## Texto principal (16,5:1 sobre [constant BG]).
const TEXT := Color("#E6EDF3")

## Texto secundario (8,8:1).
const TEXT_DIM := Color("#9FB0BE")

## Alias histórico de [constant TEXT_DIM].
const TEXT_2 := TEXT_DIM

## Ayudas, unidades y deshabilitado (5,4:1 sobre [constant BG], 4,9:1 sobre
## [constant SURFACE]).
const TEXT_MUTED := Color("#78899A")

## Alias histórico de [constant TEXT_MUTED].
const TEXT_DISABLED := TEXT_MUTED

## Texto sobre un relleno de [constant ACCENT]: el ámbar es claro, así que encima va el
## negro del fondo y no blanco.
const TEXT_ON_ACCENT := BG

# --- Acento y estados ------------------------------------------------------------------------

## Ámbar de la voz propia: acento, foco, valores activos (10,7:1).
const ACCENT := Color("#FFB020")

## Ámbar encendido para hover.
const ACCENT_HOVER := Color("#FFC44D")

## Ámbar apagado: presionado y rellenos (5,4:1).
const ACCENT_DIM := Color("#B87A14")

## Alias histórico de [constant ACCENT_DIM].
const ACCENT_PRESSED := ACCENT_DIM

## Relleno tenue de ámbar sobre fondo oscuro (selección, rango activo).
const ACCENT_SOFT := Color("#3A2B10")

## Peligro, daño y derrota (6,0:1).
const DANGER := Color("#FF4D4D")

## Relleno de barras críticas.
const DANGER_DIM := Color("#B03030")

## Fondo de un botón de peligro.
const DANGER_SOFT := Color("#2A1214")

## Fondo de un botón de peligro con el puntero encima.
const DANGER_HOVER := Color("#3A181A")

## Borde de un botón de peligro.
const DANGER_BORDER := Color("#6E2B2B")

## Confirmaciones, pilas y victoria (11,2:1).
const SUCCESS := Color("#4ADE80")

## Color **diegético**: puntos débiles, cajas de objetivo y todo lo que pertenece al
## enemigo (12,4:1). Nunca es acento de interfaz.
const TARGET := Color("#38E1FF")

## Sombra de paneles. La identidad nueva no usa sombras difusas: queda para los
## contornos duros que todavía la piden.
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)

# --- Gráfico de rates ------------------------------------------------------------------------

## Fondo del gráfico de rates del hangar.
const GRAPH_BG := Color("#0C1116")

## Rejilla del gráfico.
const GRAPH_GRID := Color("#22303A")

## Ejes del gráfico. `docs/13` §2.2 proponía `#5A6B78`, que sobre [constant GRAPH_BG]
## da 3,44:1 y no pasa la verificación de `tools/build_theme.gd`; se aclara a 4,64:1.
const GRAPH_AXIS := Color("#6E808D")

## Curva de cabeceo.
const GRAPH_PITCH := Color("#FFB020")

## Curva de alabeo.
##
## **No es [constant TARGET].** El cian es diegético y sólo marca lo que
## pertenece al enemigo (`docs/13` §2.2, nota de WP-25): una curva de rates del
## hangar es información del piloto, así que va en un azul apagado que se
## distingue del ámbar del cabeceo sin robarle el significado al cian.
const GRAPH_ROLL := Color("#7FA4C0")

## Curva de guiñada.
const GRAPH_YAW := Color("#A78BFA")

# --- HUD sobre la señal ----------------------------------------------------------------------

## Texto e instrumental del HUD de vuelo: **ámbar cálido** sobre el video del dron
## (`docs/13` §1, nota del checkpoint 3b). Lo propio nunca es blanco de consola ni cian.
const HUD_TEXT := Color("#FFD08A")

## Contorno del HUD: negro al 70 % y **3 px**, no 5. El trazo es más fino que antes, así
## que el contorno también.
const HUD_SHADOW := Color(0.0, 0.0, 0.0, 0.7)

## Relleno de las cajas y marcos semitransparentes del HUD.
const HUD_BOX := Color(0.02, 0.05, 0.07, 0.42)

## Carcasa de una barra vacía o de un carril todavía no gastado, sobre el video.
const HUD_TRACK := Color(1.0, 0.816, 0.541, 0.22)

## Rótulos, unidades y distancias del HUD.
const HUD_DIM := Color(1.0, 0.816, 0.541, 0.66)

## Única alarma de la paleta del HUD: reversa de TURTLE, energía crítica, telegrafías.
const HUD_REC := DANGER

## Grosor del trazo fino del HUD, en píxeles.
const HUD_STROKE := 1.6

## Grosor del contorno de texto del HUD, en píxeles.
const HUD_OUTLINE := 3

# --- Tipografías -----------------------------------------------------------------------------

## Chakra Petch SemiBold: títulos, marca y códigos enemigos.
const FONT_DISPLAY := "res://gui/theme/fonts/chakrapetch/ChakraPetch-SemiBold.ttf"

## Chakra Petch Regular, para el cuerpo de un bloque de código enemigo.
const FONT_DISPLAY_REGULAR := "res://gui/theme/fonts/chakrapetch/ChakraPetch-Regular.ttf"

## Alias histórico de [constant FONT_DISPLAY].
const FONT_BOLD := FONT_DISPLAY

## Barlow Semi Condensed Regular: la voz propia en párrafos y descripciones.
const FONT_REGULAR := "res://gui/theme/fonts/barlowsemicondensed/BarlowSemiCondensed-Regular.ttf"

## Barlow Semi Condensed Medium: la voz propia en rótulos, botones y filas.
const FONT_MEDIUM := "res://gui/theme/fonts/barlowsemicondensed/BarlowSemiCondensed-Medium.ttf"

## JetBrains Mono (variable): readouts, HUD numérico y gráficos.
const FONT_MONO := "res://gui/theme/fonts/jetbrainsmono/JetBrainsMono-VariableFont_wght.ttf"

## Peso que se le pide a la fuente variable de [constant FONT_MONO].
const FONT_MONO_WEIGHT := 500

# --- Métricas --------------------------------------------------------------------------------

## Margen mínimo, en píxeles.
const MARGIN_XS := 4

## Margen chico.
const MARGIN_SM := 8

## Margen medio.
const MARGIN_MD := 16

## Margen grande.
const MARGIN_LG := 24

## Margen de bloque.
const MARGIN_XL := 40

## Radio de esquina de **todo**: 2 px. La identidad nueva es de esquinas rectas.
const RADIUS := 2

## Grosor de línea de bordes y separadores, en píxeles.
const BORDER_WIDTH := 1

## Grosor del anillo de foco, en píxeles.
const FOCUS_WIDTH := 2

## Alto mínimo de una fila interactiva, en píxeles.
const ROW_HEIGHT := 44

## Margen horizontal de pantalla.
const SCREEN_MARGIN_H := 72

## Margen superior de pantalla.
const SCREEN_MARGIN_TOP := 56

## Margen inferior de pantalla (deja sitio al pie de `ControlHints`).
const SCREEN_MARGIN_BOTTOM := 104


## [param color] con la opacidad [param alpha], sin tocar el original.
static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


## Luminancia relativa de la WCAG 2.1 de [param color], ignorando su alfa.
static func relative_luminance(color: Color) -> float:
	var channels := [color.r, color.g, color.b]
	var linear: Array[float] = []
	for channel: float in channels:
		linear.append(channel / 12.92 if channel <= 0.04045
				else pow((channel + 0.055) / 1.055, 2.4))
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


## Relación de contraste WCAG entre [param a] y [param b], de 1,0 a 21,0.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var high := maxf(la, lb)
	var low := minf(la, lb)
	return (high + 0.05) / (low + 0.05)
