## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ráfaga de estática a pantalla completa (`docs/13` §1, nota «Decisión de identidad»
## del checkpoint 3b; `docs/narrativa` §4 y §8).
##
## La dirección **A · Última luz** eligió que **no haya pantalla de muerte**: el enlace
## de video se corta, se ven unos segundos de estática y alguien del taller le alcanza
## otro dron. Este componente es ese corte, y son dos ráfagas y no una:
##
## - `Events.drone_destroyed` → [constant DEATH_SECONDS], la señal que se pierde;
## - `Events.drone_respawned` → [constant REBUILT_SECONDS], la del dron nuevo
##   enganchando.
##
## ## Por qué cuelga del [HUDGlitchLayer]
##
## Dibuja un solo rectángulo con `static.gdshader` encima de todo el `Frame`, así que
## tiene que ser el último hijo del HUD; y el que ya está último es el
## [HUDGlitchLayer]. Colgarlo de ahí —en vez de darle su propia entrada en
## [enum CombatHUD.Component]— tiene además dos consecuencias que se quieren: la
## estática se apaga con el modo cinemático por el mismo camino que el EMP, y el
## recuento de componentes del HUD no cambia. Es la capa la que le pasa el delta, así
## que el reloj sigue siendo **uno solo** para todo el `CombatHUD`.
##
## ## Acumulador, no [Timer]
##
## Igual que el resto del HUD (`docs/00` §6): [method play] carga los segundos y
## [method _tick] los descuenta. Eso es lo que le permite a `combat_hud_check`
## congelar el tiempo real y medir los 0,8 s con tolerancia, y es también lo que
## alimenta el uniform `clock` del shader: con `TIME` la estática correría a la
## velocidad del bucle principal y ninguna captura sería reproducible.
class_name HUDStaticBurst
extends CombatHUDComponent

## Shader de la estática. El material se arma en código: no hace falta un `.tres`
## para un shader con un solo consumidor.
const SHADER_PATH: String = "res://hud/combat/static.gdshader"

## Segundos de estática cuando el dron cae.
##
## Ocho décimas es lo que tarda en leerse como «se cortó» sin llegar a ser un castigo:
## por debajo de media se confunde con un golpe de daño y por encima de un segundo el
## jugador empieza a buscar el botón de reintentar, que es justamente la pantalla que
## esta dirección decidió no tener.
const DEATH_SECONDS: float = 0.8

## Segundos de estática cuando el taller entrega el dron nuevo. La mitad: el enganche
## es una buena noticia y no tiene por qué durar lo mismo que la pérdida.
const REBUILT_SECONDS: float = 0.4

var _material: ShaderMaterial = null
var _left: float = 0.0
var _duration: float = 0.0
var _clock: float = 0.0


func _setup() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_error("HUDStaticBurst: no se pudo cargar %s (docs/13 §1)." % SHADER_PATH)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	# El ámbar del HUD: la señal que se rompe es la nuestra, y `docs/13` §2.2 dice que
	# nada propio es cian. Godot convierte el [Color] al `vec3 : source_color` solo.
	_material.set_shader_parameter(&"tint", CombatHUDPalette.TEXT)
	material = _material
	_apply(0.0, 0.0)
	visible = false


# --- Interfaz pública -------------------------------------------------------------------------

## Arranca una ráfaga de [param seconds] segundos.
##
## Una ráfaga nueva **reinicia** la anterior en vez de sumarse, por el mismo motivo que
## el EMP (`docs/12` §4.3): morir dos veces seguidas no puede dejar la pantalla en
## blanco el doble de tiempo, porque los segundos de estática son los que el jugador
## no ve nada y no hay forma de entender por qué.
func play(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	_duration = seconds
	_left = seconds
	_clock = 0.0
	visible = true
	_apply(1.0, 0.0)
	queue_redraw()


## `true` mientras la estática esté en pantalla. Es `false` a los segundos exactos.
func is_playing() -> bool:
	return _left > 0.0


## Segundos que le quedan a la ráfaga.
func remaining() -> float:
	return maxf(_left, 0.0)


## Valor vigente del uniform `intensity`, de 1 a 0. Es lo que mira `combat_hud_check`
## para exigir que la ráfaga **termine apagada** y no sólo invisible: un componente
## escondido con el material encendido vuelve a pintar en cuanto alguien lo muestre.
func intensity() -> float:
	if _material == null:
		return 0.0
	return float(_material.get_shader_parameter(&"intensity"))


## Corta la ráfaga y deja el componente apagado.
func stop() -> void:
	_left = 0.0
	_duration = 0.0
	_clock = 0.0
	_apply(0.0, 0.0)
	visible = false
	queue_redraw()


# --- Reloj ------------------------------------------------------------------------------------

func _tick(delta: float) -> void:
	if _left <= 0.0:
		return
	_clock += delta
	_left = maxf(_left - delta, 0.0)
	if _left <= 0.0:
		stop()
		return
	_apply(1.0, clampf(1.0 - _left / maxf(_duration, 0.001), 0.0, 1.0))
	queue_redraw()


# --- Internos ---------------------------------------------------------------------------------

## Escribe los tres uniforms que cambian cuadro a cuadro. El resto —grano, barras,
## tinte— se fija una vez en [method _setup].
func _apply(burst_intensity: float, progress: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"intensity", burst_intensity)
	_material.set_shader_parameter(&"progress", progress)
	_material.set_shader_parameter(&"clock", _clock)


func _draw() -> void:
	# No pasa por `begin_draw()`: el EMP no tiene por qué desplazar un rectángulo que
	# cubre la pantalla entera —se vería el borde del lienzo— ni saltearle un cuadro,
	# que es exactamente el agujero por el que se colaría la imagen que la estática
	# está tapando.
	if _left <= 0.0:
		return
	draw_count += 1
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
