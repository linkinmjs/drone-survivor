## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Menú de rondas (`docs/11` §8).
##
## Lista las entradas de [RoundCatalog] con su nombre, su medalla ya conseguida y su
## estado de bloqueo; la línea inferior muestra el objetivo y los récords de la ronda
## que tiene el foco. Mientras el catálogo no llegue a las ocho rondas se agrega una
## tarjeta inerte de «próximamente», que no es una entrada del catálogo.
##
## Elegir una ronda fija [member Global.selected_round] y una semilla nueva y entra al
## nivel con la pantalla de carga. El nivel al que se entra lo decide
## [method RoundCatalog.level_scene_for]: `battle_level.tscn` cuando WP-21 lo entregue
## y, hasta entonces, el nivel de vuelo libre de WP-11.
class_name RoundsMenu
extends MenuScreen

## Menú principal, destino de la vuelta cuando esta pantalla es la escena raíz.
const MAIN_MENU_SCENE: String = "res://gui/main_menu.tscn"

## Radio del hexágono de medalla, en píxeles.
const MEDAL_RADIUS: float = 9.0

## Color de cada medalla, indexado por [enum RoundCatalog.Medal].
const MEDAL_COLORS: Array[Color] = [
	UIPalette.BORDER_STRONG, # NONE: el borde fuerte de la paleta oscura.
	Color("#C08048"), # BRONZE
	Color("#AEBAC6"), # SILVER
	Color("#FFC94D"), # GOLD
]

@onready var _subtitle: Label = %Subtitle
@onready var _list: VBoxContainer = %List
@onready var _detail: Label = %Detail
@onready var _button_back: Button = %ButtonBack

## Botón de cada ronda, por id. Lo usan los checks.
var _buttons: Dictionary[String, Button] = {}

## Tarjeta inerte de «próximamente», o `null` si el catálogo ya está completo.
var _coming_soon: Button = null

var _busy: bool = false


func _ready() -> void:
	super()
	bind_back_button(_button_back)
	# A esta pantalla se llega normalmente con `open_submenu()` desde el menú
	# principal, que es quien escucha `back`. La tarjeta de resultado (`docs/11` §6.3)
	# también puede entrar **directo** con `change_scene()`, y ahí no hay nadie
	# debajo: entonces la vuelta la resuelve la pantalla misma.
	if get_tree().current_scene == self:
		var _discard := back.connect(_on_back_to_main)
	_build_list()


## Vuelta al menú principal cuando esta pantalla es la escena raíz.
func _on_back_to_main() -> void:
	SceneTransition.change_scene(MAIN_MENU_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build_list()


## Botón de la ronda [param id], o `null` si no está en la lista. Lo usan los checks
## para elegir una ronda sin depender del orden de los hijos.
func button_for(id: String) -> Button:
	return _buttons.get(id, null)


## Tarjeta inerte de «próximamente», o `null` si el catálogo ya tiene ocho rondas.
func coming_soon_card() -> Button:
	return _coming_soon


## Texto de la línea de detalle (objetivo y récords de la ronda enfocada).
func detail_text() -> String:
	return _detail.text if _detail != null else ""


# --- Construcción ----------------------------------------------------------------------------

func _build_list() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_coming_soon = null

	var entries := RoundCatalog.menu_entries(Global.selected_round)
	_subtitle.text = tr("ROUND_MENU_SUBTITLE") % [_completed_count(), RoundCatalog.count()]

	var focus: Button = null
	for entry: Dictionary in entries:
		var button := _add_entry(entry)
		if bool(entry["locked"]):
			continue
		if focus == null or bool(entry["primary"]):
			focus = button

	if RoundCatalog.shows_coming_soon():
		_coming_soon = _add_coming_soon()

	# `MenuScreen` toma el foco inicial de forma diferida, después de esto: fijarlo acá
	# en vez de pedirlo a mano evita que el scroll salte al construir la lista.
	initial_focus = focus if focus != null else _button_back
	grab_initial_focus.call_deferred(true)
	if focus != null:
		_show_detail(_buttons_index_of(focus))
	else:
		_detail.text = ""


## Fila de una ronda: el botón que la elige y el hexágono de su medalla.
func _add_entry(entry: Dictionary) -> Button:
	var row := HBoxContainer.new()
	row.name = "Row%d" % int(entry["index"])
	row.add_theme_constant_override(&"separation", 12)
	_list.add_child(row)

	var button := Button.new()
	button.name = "Round%d" % int(entry["index"])
	button.theme_type_variation = &"MenuItemButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = false
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# El `text` de un `Control` es la clave cruda: lo traduce él solo (`docs/00` §6),
	# igual que la tarjeta de «próximamente» de [method _add_coming_soon].
	button.text = String(entry["text_key"])
	button.disabled = bool(entry["locked"])
	row.add_child(button)

	var chip := MedalChip.new()
	chip.name = "Medal"
	chip.medal = int(entry["medal"])
	chip.locked = bool(entry["locked"])
	chip.custom_minimum_size = Vector2(MEDAL_RADIUS * 2.4, MEDAL_RADIUS * 2.4)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = tr(RoundCatalog.medal_key(int(entry["medal"])))
	row.add_child(chip)

	var index := int(entry["index"])
	_buttons[String(entry["id"])] = button
	if button.disabled:
		# Una entrada bloqueada no suena ni recibe el anillo de foco (`docs/12` §5).
		button.set_meta(&"no_focus_ring", true)
		button.set_meta(&"ui_silent", true)
		return button
	var _discard := button.pressed.connect(_on_round_pressed.bind(String(entry["id"])))
	_discard = button.focus_entered.connect(_show_detail.bind(index))
	_discard = button.mouse_entered.connect(_show_detail.bind(index))
	return button


## Tarjeta inerte: anuncia que faltan rondas y no se puede elegir ni enfocar.
func _add_coming_soon() -> Button:
	var button := Button.new()
	button.name = "ComingSoon"
	button.theme_type_variation = &"MenuItemButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = false
	button.text = "ROUND_COMING_SOON"
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta(&"no_focus_ring", true)
	button.set_meta(&"ui_silent", true)
	_list.add_child(button)
	return button


## Rondas con récord, que es como se deriva «completada» (`docs/11` §7).
func _completed_count() -> int:
	var total := 0
	for index: int in RoundCatalog.count():
		if GameSettings.has_completed(String(RoundCatalog.get_round(index)["id"])):
			total += 1
	return total


func _buttons_index_of(button: Button) -> int:
	for id: String in _buttons:
		if _buttons[id] == button:
			return RoundCatalog.get_index(id)
	return 0


# --- Detalle ---------------------------------------------------------------------------------

## Objetivo de la ronda y, debajo, sus récords o el motivo del bloqueo.
func _show_detail(index: int) -> void:
	var round_data := RoundCatalog.get_round(index)
	if round_data.is_empty():
		_detail.text = ""
		return
	var id := String(round_data["id"])
	var lines: Array[String] = [tr(String(round_data["goal_key"]))]
	if not RoundCatalog.is_unlocked(index):
		lines.append(tr("ROUND_LOCKED_HINT").format([_required_name(index)]))
	elif GameSettings.has_completed(id):
		lines.append("%s %d · %s %s · %s" % [
			tr("ROUND_BEST_SCORE"), GameSettings.get_best_score(id),
			tr("ROUND_BEST_TIME"), RoundCatalog.format_time(GameSettings.get_best_time(id)),
			tr(RoundCatalog.medal_key(RoundCatalog.earned_medal(index)))])
	else:
		lines.append(tr("ROUND_NOT_PLAYED"))
	_detail.text = "\n".join(lines)


## Nombre traducido de la ronda que hay que completar para abrir [param index].
func _required_name(index: int) -> String:
	var round_data := RoundCatalog.get_round(index)
	var required := String(round_data.get("unlock_after", ""))
	var previous := RoundCatalog.get_by_id(required) if not required.is_empty() \
			else RoundCatalog.get_round(index - 1)
	if previous.is_empty():
		return ""
	return tr(String(previous["name_key"]))


# --- Elección --------------------------------------------------------------------------------

func _on_round_pressed(id: String) -> void:
	if _busy or UI.has_modal() or SceneTransition.is_busy():
		return
	var round_data := RoundCatalog.get_by_id(id)
	if round_data.is_empty():
		return
	_busy = true
	Global.selected_round = id
	Global.round_seed = randi()
	SceneTransition.change_scene(RoundCatalog.level_scene_for(round_data), true)


## Hexágono relleno con el color de la medalla (`docs/11` §8). Una ronda bloqueada
## dibuja solo el contorno, que hace las veces de candado.
class MedalChip extends Control:
	var medal: int = RoundCatalog.Medal.NONE
	var locked: bool = false

	func _draw() -> void:
		var center := size * 0.5
		var points := PackedVector2Array()
		for corner: int in 6:
			var angle := TAU * float(corner) / 6.0 - PI * 0.5
			points.append(center + Vector2(cos(angle), sin(angle)) * RoundsMenu.MEDAL_RADIUS)
		var color: Color = RoundsMenu.MEDAL_COLORS[clampi(medal, 0, RoundsMenu.MEDAL_COLORS.size() - 1)]
		if locked or medal == RoundCatalog.Medal.NONE:
			points.append(points[0])
			draw_polyline(points, color, 1.5, true)
			return
		draw_colored_polygon(points, color)
