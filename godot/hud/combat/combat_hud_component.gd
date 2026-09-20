## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Base de los componentes del HUD de combate (`docs/12` §4).
##
## Todos los componentes del `CombatHUD` son [Control] que dibujan con `_draw()` y los
## estáticos de [HUDDraw], sin una sola textura. Esta clase concentra lo que los trece
## comparten para que ninguno lo reinvente:
##
## 1. **Reloj propio.** El HUD no avanza en `_process()` de cada nodo: [CombatHUD] lo
##    hace por todos con [method tick], una vez por cuadro y en un orden fijo. Eso es
##    lo que permite que `combat_hud_check` congele el tiempo real y avance el HUD en
##    pasos exactos (`CombatHUD.set_manual_time()`), que es la única forma de medir
##    «120 ms de hitmarker» o «3.0 s de glitch» sin depender de a qué velocidad corra
##    el bucle principal en `--headless`.
## 2. **Perturbación de EMP** (`docs/12` §4.3). [HUDGlitchLayer] no mueve nodos: le
##    escribe a cada componente un desplazamiento, un pedido de números rotos y, de
##    vez en cuando, un cuadro en blanco. Mover [member Control.position] pelearía con
##    los anclajes y dejaría el HUD corrido si el EMP terminara en medio de un
##    redimensionado; un [method CanvasItem.draw_set_transform] dentro del `_draw()`
##    no puede dejar rastro.
## 3. **Acumuladores, nunca [Timer]** (`docs/00` §6). Todo plazo de un componente es
##    un `float` que baja en [method _tick].
##
## Un componente concreto sobrescribe [method _setup] —no `_ready()`—, [method _tick]
## y `_draw()`, y empieza su `_draw()` con `if not begin_draw(): return`.
class_name CombatHUDComponent
extends Control

## Desplazamiento que el EMP le impone al dibujo, en píxeles (`docs/12` §4.3).
## Vuelve a [constant Vector2.ZERO] en cuanto el glitch termina.
var glitch_offset: Vector2 = Vector2.ZERO

## Con `true` los números de este componente se dibujan como `--` (`docs/12` §4.3).
var glitch_scramble: bool = false

## Con `true` el componente se saltea el cuadro entero. Es el «se oculta un cuadro»
## de `docs/12` §4.3, y por eso no toca [member CanvasItem.visible]: apagar y encender
## la visibilidad a 12 Hz haría trabajar al árbol de `Control` para nada.
var glitch_blank: bool = false

## Cuántas veces se llamó a `_draw()`. `combat_hud_check` lo usa para exigir que cada
## componente haya dibujado **al menos una vez** después de alimentarlo (`docs/12`
## §9.2 fila 1): un componente que existe pero nunca dibujó es un componente roto que
## pasaría cualquier prueba de visibilidad.
var draw_count: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup()


## Avanza el reloj del componente. Lo llama [CombatHUD] una vez por cuadro.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_tick(delta)


## Escribe la perturbación de EMP de este cuadro (`docs/12` §4.3).
func apply_glitch(offset: Vector2, scramble: bool, blank: bool) -> void:
	if offset.is_equal_approx(glitch_offset) and scramble == glitch_scramble \
			and blank == glitch_blank:
		return
	glitch_offset = offset if offset.is_finite() else Vector2.ZERO
	glitch_scramble = scramble
	glitch_blank = blank
	queue_redraw()


## Deja el componente sin rastro del EMP. La llama [HUDGlitchLayer] al terminar.
func clear_glitch() -> void:
	apply_glitch(Vector2.ZERO, false, false)


## Abre el `_draw()`: aplica el desplazamiento del EMP y dice si hay que dibujar.
## Devuelve `false` en el cuadro que el glitch decidió saltear.
func begin_draw() -> bool:
	if glitch_blank:
		return false
	draw_count += 1
	if not glitch_offset.is_zero_approx():
		draw_set_transform(glitch_offset)
	return true


## Centro del lienzo del componente, en coordenadas locales.
func centre() -> Vector2:
	return size * 0.5


## Texto de un número que el EMP puede estar rompiendo (`docs/12` §4.3).
func number_text(value: String) -> String:
	return "--" if glitch_scramble else value


# --- Virtuales --------------------------------------------------------------------------------

## Una sola vez, desde `_ready()`. Las subclases lo sobrescriben en vez de `_ready()`
## para no perder el `mouse_filter` ni el orden de construcción.
func _setup() -> void:
	pass


## Un paso del reloj del componente. [param delta] siempre es positivo.
func _tick(_delta: float) -> void:
	pass
