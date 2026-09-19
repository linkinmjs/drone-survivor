## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name ChoiceMenu
extends MenuScreen
## Menu of a list of options built in code, shown over a level: the tutorial start, lesson
## picker and end screens, and the challenge picker and results. It is a regular MenuScreen,
## so it works with mouse, keyboard, gamepad and radio sticks: `setup()` it, add it to the
## tree and await `chosen`.


signal chosen(id: String)

var _title_text := ""
var _subtitle_text := ""
## Each entry: {"id": String, "text": String, "primary": bool (optional)}
var _entries: Array[Dictionary] = []
## Entry chosen by the back action (Esc / B / stick gesture). Empty: back is disabled.
var _back_id := ""
var _chosen := false


func setup(title: String, subtitle: String, entries: Array[Dictionary], back_id := "") -> void:
	_title_text = title
	_subtitle_text = subtitle
	_entries = entries
	_back_id = back_id


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = Backdrop.SCRIM
	allow_back = not _back_id.is_empty()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", UIPalette.SCREEN_MARGIN_H)
	margin.add_theme_constant_override(&"margin_right", UIPalette.SCREEN_MARGIN_H)
	margin.add_theme_constant_override(&"margin_top", UIPalette.SCREEN_MARGIN_TOP)
	margin.add_theme_constant_override(&"margin_bottom", UIPalette.SCREEN_MARGIN_BOTTOM)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(620, 0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.theme_type_variation = &"DisplayLabel"
	title.text = _title_text
	column.add_child(title)

	if not _subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.theme_type_variation = &"SubtitleLabel"
		subtitle.text = _subtitle_text
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle.custom_minimum_size = Vector2(620, 0)
		column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 32)
	column.add_child(spacer)

	for entry: Dictionary in _entries:
		var button := Button.new()
		button.text = str(entry.get("text", ""))
		button.theme_type_variation = &"MenuItemButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = false
		column.add_child(button)
		var id := str(entry.get("id", ""))
		if id == _back_id:
			button.set_meta(&"ui_back", true)
		var _connected := button.pressed.connect(_choose.bind(id))
		if initial_focus == null or bool(entry.get("primary", false)):
			initial_focus = button

	var _discard := back.connect(_on_back)
	super()


func _choose(id: String) -> void:
	if _chosen:
		return
	_chosen = true
	var tween := create_tween()
	var _step := tween.tween_property(self, "modulate:a", 0.0, 0.12)
	await tween.finished
	chosen.emit(id)


func _on_back() -> void:
	if not _chosen:
		_chosen = true
		chosen.emit(_back_id)
