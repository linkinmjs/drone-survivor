## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cuenta de reconstrucción del dron (`docs/09` §2.8, `docs/12` §4).
##
## Mientras [method RespawnController.is_respawning] sea `true`, el centro de la
## pantalla muestra `HUD_REBUILDING` y los segundos que faltan —12 s con los valores
## de `docs/09` §3.5—, más el multiplicador de puntaje que la muerte acaba de costar.
##
## El `FlightHUD` no se ve durante la reconstrucción: el nivel pasa a la cámara fija
## y `LevelBase` esconde el HUD del rig cuando la cámara activa no es la FPV
## (`docs/12` §1.1). El `CombatHUD`, en cambio, **sobrevive al respawn** porque
## pertenece al nivel, y por eso la cuenta atrás es suya: es el único HUD que sigue
## en pantalla mientras el dron no existe.
##
## Hace polling y no escucha el bus porque `Events.drone_destroyed` no dice cuánto
## falta: el que lleva la cuenta es el [RespawnController], y duplicar su acumulador
## acá sería tener dos relojes que se separan en la primera pausa.
class_name HUDRespawnOverlay
extends CombatHUDComponent

## Clave del texto principal.
const TITLE_KEY: String = "HUD_REBUILDING"

## Clave de la línea del multiplicador.
const MULTIPLIER_KEY: String = "HUD_RESPAWN_MULTIPLIER"

## Distancia del centro del lienzo a la línea base del título, en píxeles.
##
## El bloque queda **arriba** del centro exacto para no escribir el número encima del
## retículo del `FlightHUD`. En una reaparición real ese HUD está escondido —la cámara
## activa no es la FPV (`docs/12` §1.1)—, pero un check o una cinemática pueden
## mostrar los dos a la vez y el número de dos dígitos es lo bastante grande como para
## tapar la mira entera.
const TITLE_OFFSET_Y: float = -80.0

## Controlador de reaparición del dron vivo. Lo escribe [method bind_respawn].
var controller: RespawnController = null

var _showing: bool = false
var _remaining: float = 0.0
var _multiplier: float = 1.0


## Ata el overlay al dron. Con `null` se apaga.
func bind_respawn(respawn_controller: RespawnController) -> void:
	controller = respawn_controller
	_showing = false
	_remaining = 0.0
	queue_redraw()


func _tick(_delta: float) -> void:
	var showing := false
	var remaining := 0.0
	var multiplier := 1.0
	if controller != null and is_instance_valid(controller):
		showing = controller.is_respawning()
		remaining = controller.get_remaining_seconds()
		multiplier = controller.get_score_multiplier()
	if not is_finite(remaining):
		remaining = 0.0
	# Igual que el cronómetro: un redibujo por segundo mostrado, no por cuadro.
	if showing == _showing and int(ceil(remaining)) == int(ceil(_remaining)) \
			and is_equal_approx(multiplier, _multiplier):
		_remaining = remaining
		return
	_showing = showing
	_remaining = remaining
	_multiplier = multiplier
	queue_redraw()


## `true` mientras el dron se esté reconstruyendo.
func is_showing() -> bool:
	return _showing


## Segundos que faltan para volver a volar.
func remaining() -> float:
	return maxf(_remaining, 0.0)


func _draw() -> void:
	if not begin_draw():
		return
	if not _showing:
		return
	var origin := centre()
	var font := HUDDraw.font_bold()
	var mono := HUDDraw.font_mono()
	HUDDraw.text(self, font, origin + Vector2(-300.0, TITLE_OFFSET_Y), tr(TITLE_KEY), 38,
			HORIZONTAL_ALIGNMENT_CENTER, 600.0, CombatHUDPalette.ACCENT)
	HUDDraw.text(self, mono, origin + Vector2(-300.0, TITLE_OFFSET_Y + 56.0),
			number_text("%d" % [maxi(int(ceil(_remaining)), 0)]), 52,
			HORIZONTAL_ALIGNMENT_CENTER, 600.0, CombatHUDPalette.TEXT)
	if _multiplier < 0.999:
		HUDDraw.text(self, mono, origin + Vector2(-300.0, TITLE_OFFSET_Y + 92.0),
				tr(MULTIPLIER_KEY).format([number_text("%.2f" % [_multiplier])]), 20,
				HORIZONTAL_ALIGNMENT_CENTER, 600.0, CombatHUDPalette.DANGER)
