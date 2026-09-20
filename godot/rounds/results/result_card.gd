## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Tarjeta de resultado de la ronda (`docs/11` §6.3).
##
## `CanvasLayer` en la capa 45 —por encima del `CombatHUD` (20) y del menú de pausa
## (40), `docs/12` §4— con `process_mode = ALWAYS`, porque tiene que responder aunque
## el árbol esté en pausa.
##
## Dos mitades: a la derecha el detalle de la partida, que se construye con
## [method RoundResult.summary_rows]; a la izquierda un [ChoiceMenu], que aporta el
## título, el fundido de fondo, la navegación con teclado, mando y sticks, y la señal
## `chosen(id)` (`docs/01` §2.3). La tarjeta no decide nada: reemite esa elección en
## [signal chosen] y [RoundManager] hace el cambio de escena.
##
## El texto se reconstruye entero en `NOTIFICATION_TRANSLATION_CHANGED`, salvo el del
## [ChoiceMenu], que traduce sus botones solo porque su `text` es la clave cruda.
class_name ResultCard extends CanvasLayer

## El jugador eligió [param id]: `retry`, `next`, `rounds` o `menu`.
signal chosen(id: String)

## Capa del canvas (`docs/11` §10).
const LAYER: int = 45

## Ancho de la columna de estadísticas, en píxeles.
const PANEL_WIDTH: float = 420.0

## Radio del hexágono de medalla, en píxeles.
const MEDAL_RADIUS: float = 26.0

## Color con el que se resaltan los valores que baten un récord.
const HIGHLIGHT: Color = Color("#D8A21A")

## Resultado que se dibuja. Lo fija [method setup] antes de entrar al árbol.
var result: RoundResult = null

## Entradas del menú, ya resueltas por [RoundManager].
var _entries: Array[Dictionary] = []

var _root: Control = null
var _panel: VBoxContainer = null
var _choice: ChoiceMenu = null
var _chosen: bool = false


## Inyecta el resultado y las entradas del menú. [param entries] usa el formato de
## `ChoiceMenu.setup()`: `{id, text, primary}`.
func setup(round_result: RoundResult, entries: Array[Dictionary]) -> void:
	result = round_result
	_entries = entries


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_choice()
	_build_panel()
	_fill_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_panel()


## El menú de elección, para que los checks puedan elegir sin mover el foco.
func choice_menu() -> ChoiceMenu:
	return _choice


## Elige [param id] como si lo hubiera pulsado el jugador. Lo usa `round_check`.
func choose(id: String) -> void:
	_on_chosen(id)


# --- Construcción ----------------------------------------------------------------------------

## El [ChoiceMenu] va primero para que su fondo quede **debajo** del panel.
func _build_choice() -> void:
	_choice = ChoiceMenu.new()
	_choice.name = "Choice"
	var title := "ROUND_VICTORY" if result != null and result.victory else "ROUND_DEFEAT"
	_choice.setup(tr(title), _subtitle_text(), _entries, "rounds")
	add_child(_choice)
	var _discard := _choice.chosen.connect(_on_chosen)


func _build_panel() -> void:
	_root = Control.new()
	_root.name = "Stats"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	margin.offset_left = -(PANEL_WIDTH + float(UIPalette.SCREEN_MARGIN_H))
	margin.add_theme_constant_override(&"margin_right", UIPalette.SCREEN_MARGIN_H)
	margin.add_theme_constant_override(&"margin_top", UIPalette.SCREEN_MARGIN_TOP)
	margin.add_theme_constant_override(&"margin_bottom", UIPalette.SCREEN_MARGIN_BOTTOM)
	_root.add_child(margin)

	_panel = VBoxContainer.new()
	_panel.name = "Rows"
	_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_constant_override(&"separation", 8)
	margin.add_child(_panel)


func _fill_panel() -> void:
	if _panel == null:
		return
	for child: Node in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	if result == null:
		return

	for row: Dictionary in result.summary_rows():
		_add_row(tr(String(row["label_key"])), String(row["value_text"]), bool(row["highlight"]))

	_panel.add_child(_separator())
	_add_row(tr("RESULT_SCORE"), str(result.score), result.is_record, 32)
	if result.is_record:
		var record := _make_label(tr("RESULT_NEW_RECORD"), 20, HIGHLIGHT)
		record.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_panel.add_child(record)

	var medal_row := HBoxContainer.new()
	medal_row.alignment = BoxContainer.ALIGNMENT_END
	medal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_row.add_theme_constant_override(&"separation", 12)
	_panel.add_child(medal_row)
	var name_label := _make_label(tr(RoundCatalog.medal_key(result.medal)), 22, UIPalette.TEXT_2)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal_row.add_child(name_label)
	var badge := MedalBadge.new()
	badge.medal = result.medal
	badge.custom_minimum_size = Vector2(MEDAL_RADIUS * 2.4, MEDAL_RADIUS * 2.4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_row.add_child(badge)


## Fila `etiqueta … valor`, con el valor alineado a la derecha.
func _add_row(label_text: String, value_text: String, highlight: bool, size: int = 22) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 16)
	_panel.add_child(row)

	var label := _make_label(label_text, size, UIPalette.TEXT_2)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value := _make_label(value_text, size, HIGHLIGHT if highlight else UIPalette.TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font = load(UIPalette.FONT_BOLD) as Font
	settings.font_size = size
	settings.font_color = color
	label.label_settings = settings
	return label


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = UIPalette.BORDER_STRONG
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Subtítulo del menú: nombre de la ronda y tiempo de la partida.
func _subtitle_text() -> String:
	if result == null:
		return ""
	var round_data := RoundCatalog.get_by_id(result.round_id)
	var name_text := tr(String(round_data.get("name_key", ""))) if not round_data.is_empty() else ""
	return "%s · %s %s" % [name_text, tr("RESULT_TIME"), RoundResult.format_time(result.time_seconds)]


func _on_chosen(id: String) -> void:
	if _chosen:
		return
	_chosen = true
	chosen.emit(id)


## Hexágono relleno con el color de la medalla (`docs/11` §6.3). Sin medalla se
## dibuja sólo el contorno, igual que en el menú de rondas.
class MedalBadge extends Control:
	var medal: int = RoundCatalog.Medal.NONE

	func _draw() -> void:
		var center := size * 0.5
		var points := PackedVector2Array()
		for corner: int in 6:
			var angle := TAU * float(corner) / 6.0 - PI * 0.5
			points.append(center + Vector2(cos(angle), sin(angle)) * ResultCard.MEDAL_RADIUS)
		var palette: Array[Color] = RoundsMenu.MEDAL_COLORS
		var color: Color = palette[clampi(medal, 0, palette.size() - 1)]
		if medal == RoundCatalog.Medal.NONE:
			points.append(points[0])
			draw_polyline(points, color, 2.0, true)
			return
		draw_colored_polygon(points, color)
