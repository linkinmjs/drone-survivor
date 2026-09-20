## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ficha de la telegrafía de un ataque (`docs/06` §3 y §11.2).
##
## `docs/06` §11.2 exige **al menos dos de tres canales** en toda acción dañina, y
## los tres en las letales. Este recurso los declara de forma que el [Telegraph]
## —que es uno solo por enemigo— sepa qué encender sin saber nada del ataque:
##
## 1. [b]Luz emisiva[/b]: [member light_color_from] → [member light_color_to] con
##    la energía interpolada durante el windup.
## 2. [b]Audio[/b]: [member audio_event], que el [Telegraph] resuelve contra
##    `assets/audio/enemies/<audio_event>.wav` (los sintetiza
##    `tools/generate_enemy_sounds.gd`). Vacío = el barrido genérico `charge`.
## 3. [b]Señal espacial[/b]: [member spatial_kind], que elige entre el anillo de
##    suelo del pisotón, la línea guía del láser, la columna del asedio, la
##    parábola del salto o la postura del cuerpo (que no dibuja nada: la pone la
##    propia acción).
##
## [b]El aviso no miente[/b]: [member decal_radius] es el radio real del volumen
## de resolución del ataque, no un adorno. Si los dos no coinciden, el jugador no
## puede esquivar y `docs/07` §14 mide exactamente eso.
class_name TelegraphProfile extends Resource

## Tipo de señal espacial (`docs/06` §11.2 canal 3).
enum SpatialKind {
	NONE,       ## Sin señal espacial: el ataque se conforma con luz y audio.
	DECAL_ZONE, ## Anillo/decal proyectado en el suelo (pisotón, onda del EMP).
	GUIDE_LINE, ## Línea guía fina desde la cabeza al objetivo (láser).
	COLUMN,     ## Columna vertical de luz sobre el objetivo (asedio).
	PARABOLA,   ## Arco balístico hasta el punto de caída (salto).
	POSTURE,    ## Sólo postura del cuerpo; la coreografía la hace la acción.
}

## Color del emisivo al empezar la carga. Es el cian de reposo del Arachnodroid
## (`docs/07` §2).
@export var light_color_from: Color = Color(0.216, 0.667, 0.973)

## Color al que vira el emisivo al final del windup.
@export var light_color_to: Color = Color(1.0, 0.25, 0.1)

## Energía relativa de la luz al empezar, de 0 a 1.
@export_range(0.0, 1.0, 0.01) var light_energy_from: float = 0.2

## Energía relativa de la luz al terminar, de 0 a 1.
@export_range(0.0, 1.0, 0.01) var light_energy_to: float = 1.0

## Evento del banco de `AudioRig` (`docs/07` §10). El [Telegraph] lo resuelve
## contra `assets/audio/enemies/<audio_event>.wav`.
@export var audio_event: StringName = &""

## Señal espacial que enciende el [Telegraph], como valor de [enum SpatialKind].
@export var spatial_kind: int = SpatialKind.DECAL_ZONE

## Textura del decal de zona. Sin ella el [Telegraph] dibuja su anillo de malla,
## que es lo que hace WP-19: el decal con textura es pulido de WP-27.
@export var decal_texture: Texture2D = null

## Radio de la zona marcada, en metros. **Tiene que ser el del volumen de
## resolución del ataque.**
@export_range(0.0, 200.0, 0.5) var decal_radius: float = 9.0

## Fracción del radio a la que arranca la zona al empezar el aviso. `0.0` la hace
## crecer desde el centro —el anillo del EMP de `docs/07` §5.8—; `0.25` la deja
## legible desde el primer instante, que es lo que quiere el pisotón.
@export_range(0.0, 1.0, 0.01) var decal_grow_from: float = 0.25

## Grosor de la línea guía y de la parábola, en metros (`docs/07` §5.6: 0.25 m).
@export_range(0.01, 5.0, 0.01) var guide_width: float = 0.25

## Curva de la postura durante el windup, de 0 a 1. La consume la acción, no el
## [Telegraph]: es el `tuck` del salto o la retracción de la pata del barrido.
@export var posture_curve: Curve = null

## Clave de traducción del aviso del `CombatHUD` (`docs/12`). El HUD usa además
## `HUD_TELEGRAPH_<attack_id>`; esta clave es el texto largo opcional.
@export var hud_warning_key: String = ""


## Canales que este perfil declara encender (`docs/06` §11.2). Siempre cuenta la
## luz y el audio; la señal espacial sólo si no es [constant SpatialKind.NONE].
func declared_channels() -> int:
	var channels := 2
	if spatial_kind != SpatialKind.NONE:
		channels += 1
	return channels


## Ruta del sonido de carga, o `""` si el perfil no declara ninguno.
func audio_path() -> String:
	if audio_event == &"":
		return ""
	return "res://assets/audio/enemies/%s.wav" % audio_event
