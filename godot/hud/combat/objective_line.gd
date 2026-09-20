## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Línea de objetivo del `CombatHUD` (`docs/12` §4.1).
##
## Título del objetivo en curso, tarea, barra de progreso —oculta si
## [method Objective.get_progress] devuelve un valor negativo— y línea de progreso.
## **Reemplaza a la [ObjectiveHUD] provisional** de `docs/11` §5.2: desde WP-22 el
## `CombatHUDSlot` del nivel deja de estar vacío, [method RoundManager._show_objective_hud]
## devuelve `false` y la tarjeta vieja no se enciende nunca más.
##
## ## Dos fuentes, cada una para lo suyo
##
## - `RoundManager.objective_text_changed(task, progress, progress_text)` trae lo que
##   cambia en vivo. Llega **sólo cuando cambió algo** (`docs/11` §9.3): un `emit` por
##   cuadro con dos traducciones y un `String` recién formateado sería basura para el
##   recolector a 60 Hz.
## - El [ObjectiveSequencer] trae el título y el «objetivo N de M», que cambian una
##   vez por objetivo y llegan por `objective_started`.
##
## ## Discrepancia registrada con `docs/12` §4.1
##
## La tabla ubica la línea «debajo de la `CityBar`», o sea en el centro superior. Ahí
## chocaría con el aviso de telegrafía, que el mismo documento pone a 24 % del alto, y
## con el bloque jefe + ciudad que ya ocupa hasta el 27 %. Se mueve al **margen
## izquierdo**, a la altura de la cinta de rumbo: es la única franja del lienzo que ni
## el `FlightHUD` ni el resto del `CombatHUD` usan, y es donde estaba la tarjeta
## provisional que este componente reemplaza (`ObjectiveHUD.CARD_POSITION`).
class_name HUDObjectiveLine
extends CombatHUDComponent

## Esquina superior izquierda del bloque, en píxeles del lienzo de diseño.
const ORIGIN: Vector2 = Vector2(48.0, 118.0)

## Ancho del bloque, en píxeles.
const WIDTH: float = 340.0

## Alto de la barra de progreso, en píxeles.
const BAR_HEIGHT: float = 6.0

## Renglones como mucho para la tarea. Más que eso y la línea deja de ser una línea.
const MAX_TASK_LINES: int = 3

## Separación entre renglones de la tarea, en píxeles.
const TASK_LINE_HEIGHT: float = 21.0

## Clave del encabezado «Objetivo %d de %d», compartida con la tarjeta provisional.
const STEP_KEY: String = "OBJ_STEP_OF"

## Secuenciador del que salen el título y el índice.
var sequencer: ObjectiveSequencer = null

var _title_key: String = ""
var _task: String = ""
var _progress: float = -1.0
var _progress_text: String = ""
var _index: int = -1
var _total: int = 0


## Ata la línea a la cadena de objetivos de la ronda.
func bind_sequencer(objective_sequencer: ObjectiveSequencer) -> void:
	sequencer = objective_sequencer
	refresh_objective()


## `RoundManager.objective_text_changed`.
func set_task(task_text: String, progress: float, progress_text: String) -> void:
	_task = task_text
	_progress = progress if is_finite(progress) else -1.0
	_progress_text = progress_text
	queue_redraw()


## Relee el objetivo en curso del secuenciador. La llama `objective_started` y
## también [method bind_sequencer].
func refresh_objective() -> void:
	if sequencer == null or not is_instance_valid(sequencer):
		clear_objective()
		return
	var objective := sequencer.get_current()
	if objective == null:
		clear_objective()
		return
	_index = sequencer.current_index
	_total = sequencer.count()
	_title_key = objective.title_key
	_task = tr(objective.get_task_text())
	_progress = objective.get_progress()
	_progress_text = objective.get_progress_text()
	queue_redraw()


## Deja la línea vacía. La cadena terminada la llama con `all_finished`.
func clear_objective() -> void:
	if _title_key.is_empty() and _task.is_empty():
		return
	_title_key = ""
	_task = ""
	_progress = -1.0
	_progress_text = ""
	_index = -1
	_total = 0
	queue_redraw()


## Título traducido del objetivo en curso, o `""`.
func title() -> String:
	return tr(_title_key) if not _title_key.is_empty() else ""


## Tarea en curso, ya traducida.
func task() -> String:
	return _task


## Progreso de 0 a 1, o negativo si no hay barra.
func progress() -> float:
	return _progress


## `true` cuando hay un objetivo que mostrar.
func has_objective() -> bool:
	return not _title_key.is_empty() or not _task.is_empty()


func _draw() -> void:
	if not begin_draw():
		return
	if not has_objective():
		return
	var font_bold := HUDDraw.font_bold()
	var font := HUDDraw.font_mono()
	var y := ORIGIN.y

	if _index >= 0 and _total > 0:
		HUDDraw.text(self, font, Vector2(ORIGIN.x, y), tr(STEP_KEY) % [_index + 1, _total],
				15, HORIZONTAL_ALIGNMENT_LEFT, WIDTH, CombatHUDPalette.TEXT_DIM)
		y += 22.0

	if not _title_key.is_empty():
		HUDDraw.text(self, font_bold, Vector2(ORIGIN.x, y), title(), 22,
				HORIZONTAL_ALIGNMENT_LEFT, WIDTH, CombatHUDPalette.ACCENT)
		y += 28.0

	if not _task.is_empty():
		# `HUDDraw.text` recorta al ancho en vez de partir la línea: una tarea de
		# «No dejes que el coloso arrase el distrito» se vería como «…arrase e». El
		# corte por palabras se hace acá, midiendo con la fuente real.
		for line: String in _wrap(_task, font, 18, WIDTH):
			HUDDraw.text(self, font, Vector2(ORIGIN.x, y), line, 18,
					HORIZONTAL_ALIGNMENT_LEFT, WIDTH, CombatHUDPalette.TEXT)
			y += TASK_LINE_HEIGHT
		y += 4.0

	if _progress >= 0.0:
		var bar := Rect2(Vector2(ORIGIN.x, y), Vector2(WIDTH * 0.7, BAR_HEIGHT))
		draw_rect(bar.grow(1.5), CombatHUDPalette.SHADOW, true)
		draw_rect(bar, CombatHUDPalette.TRACK, true)
		draw_rect(Rect2(bar.position,
				Vector2(bar.size.x * clampf(_progress, 0.0, 1.0), bar.size.y)),
				CombatHUDPalette.ACCENT, true)
		y += BAR_HEIGHT + 20.0

	if not _progress_text.is_empty():
		HUDDraw.text(self, font, Vector2(ORIGIN.x, y), number_text(_progress_text), 17,
				HORIZONTAL_ALIGNMENT_LEFT, WIDTH, CombatHUDPalette.TEXT_DIM)


# --- Internos ---------------------------------------------------------------------------------

## Parte [param text] en renglones que entren en [param width], cortando por palabras.
##
## Devuelve como mucho [constant MAX_TASK_LINES] renglones; si sobra texto, el último
## termina en puntos suspensivos. Una palabra más larga que el ancho se deja entera y
## se recorta al dibujar: partirla al medio sería peor que pasarse dos píxeles.
func _wrap(text: String, font: Font, font_size: int, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	for word: String in text.split(" ", false):
		var candidate := word if current.is_empty() else "%s %s" % [current, word]
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				font_size).x <= width or current.is_empty():
			current = candidate
			continue
		lines.append(current)
		current = word
		if lines.size() >= MAX_TASK_LINES:
			break
	if lines.size() < MAX_TASK_LINES and not current.is_empty():
		lines.append(current)
	elif not current.is_empty() and not lines.is_empty():
		lines[lines.size() - 1] = "%s…" % lines[lines.size() - 1]
	return lines
