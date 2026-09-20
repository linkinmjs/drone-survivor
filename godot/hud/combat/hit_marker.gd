## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Marcas de impacto confirmado (`docs/12` §4.1 y §8).
##
## Una ✕ de [constant SIZE] px sobre el retículo, [constant LIFETIME] s, apilable
## hasta [constant MAX_MARKS]. El color sale de los **dos booleanos** de
## `Events.hit_confirmed(position, weak, lethal)` a través de
## [method WeaponMount.hit_kind], que es la única función que convierte ese par en el
## `HitKind` de `docs/08` §2.11: blanco en blindaje, ámbar en punto débil, rojo y más
## grande cuando ese impacto **rompió** la parte.
##
## `position` llega en la señal pero no se usa para ubicar la marca: el acuse de
## impacto se lee en el centro, donde está la mira, y no donde cayó el tiro. Las
## marcas apiladas se separan un poco entre sí para que tres impactos en el mismo
## cuadro se vean como tres y no como uno.
class_name HUDHitMarker
extends CombatHUDComponent

## Duración de una marca, en segundos (`docs/12` §8).
const LIFETIME: float = 0.12

## Marcas simultáneas (`docs/12` §8).
const MAX_MARKS: int = 3

## Lado de una marca normal, en píxeles.
const SIZE: float = 18.0

## Lado de la marca de parte rota, en píxeles (`docs/12` §4.1).
const LETHAL_SIZE: float = 22.0

## Separación entre dos marcas apiladas, en píxeles.
const STACK_STEP: float = 7.0

## Grosor del trazo.
const WIDTH: float = 2.5

## Marcas vivas: `{kind: int, left: float, slot: int}`.
var _marks: Array[Dictionary] = []

## Cuántas marcas se apilaron desde la última que se apagó del todo.
var _slot: int = 0


func _tick(delta: float) -> void:
	if _marks.is_empty():
		return
	var index := _marks.size() - 1
	while index >= 0:
		var mark := _marks[index]
		mark["left"] = float(mark["left"]) - delta
		if float(mark["left"]) <= 0.0:
			_marks.remove_at(index)
		else:
			_marks[index] = mark
		index -= 1
	if _marks.is_empty():
		_slot = 0
	queue_redraw()


## `Events.hit_confirmed`. La marca más vieja cae si ya hay [constant MAX_MARKS].
func add_hit(weak: bool, lethal: bool) -> void:
	if _marks.size() >= MAX_MARKS:
		_marks.remove_at(0)
	_marks.append({"kind": WeaponMount.hit_kind(weak, lethal), "left": LIFETIME,
			"slot": _slot})
	_slot = (_slot + 1) % MAX_MARKS
	queue_redraw()


## Marcas todavía visibles. `docs/12` §9.2 fila 3 exige 3 tras los tres impactos y 0
## a los 130 ms.
func active_count() -> int:
	return _marks.size()


## Colores de las marcas vivas, en orden de llegada. La fila 3 del check los compara
## entre sí para exigir que las tres combinaciones den tres marcas **distintas**.
func active_colours() -> Array[Color]:
	var colours: Array[Color] = []
	for mark: Dictionary in _marks:
		colours.append(_colour(int(mark["kind"])))
	return colours


## Deja el componente sin marcas. La usan el respawn y el modo cinemático.
func clear_marks() -> void:
	if _marks.is_empty():
		return
	_marks.clear()
	_slot = 0
	queue_redraw()


func _draw() -> void:
	if not begin_draw():
		return
	var origin := centre()
	for mark: Dictionary in _marks:
		var kind := int(mark["kind"])
		var life := clampf(float(mark["left"]) / LIFETIME, 0.0, 1.0)
		var half := (LETHAL_SIZE if kind == WeaponMount.HitKind.PART_BROKEN else SIZE) * 0.5
		# La marca se abre mientras se apaga: el ojo lee el gesto aunque dure 120 ms.
		var spread := half * (1.35 - 0.35 * life)
		var step := STACK_STEP * float(int(mark["slot"]))
		var at := origin + Vector2(step, -step) * 0.5
		var colour := CombatHUDPalette.with_alpha(_colour(kind), life)
		var inner := spread * 0.34
		for index: int in 4:
			var direction := Vector2.from_angle(deg_to_rad(45.0 + 90.0 * float(index)))
			HUDDraw.line(self, at + direction * inner, at + direction * spread, WIDTH, colour)


# --- Internos ---------------------------------------------------------------------------------

func _colour(kind: int) -> Color:
	match kind:
		WeaponMount.HitKind.PART_BROKEN:
			return CombatHUDPalette.DANGER
		WeaponMount.HitKind.WEAK:
			return CombatHUDPalette.ACCENT
		_:
			return CombatHUDPalette.TEXT
