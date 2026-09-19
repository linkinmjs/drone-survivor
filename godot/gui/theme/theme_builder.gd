## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
class_name ThemeBuilder
extends RefCounted
## Builds the light "minimal" menu theme from UIPalette.
## Run `tools/build_theme.gd` to regenerate `gui/theme/main_theme.tres`.


const P := preload("res://gui/theme/ui_palette.gd")


static func build() -> Theme:
	var t := Theme.new()
	var regular := load(P.FONT_REGULAR) as Font
	var bold := load(P.FONT_BOLD) as Font
	t.default_font = regular
	t.default_font_size = 22

	_containers(t)
	_labels(t, bold)
	_buttons(t, bold)
	_panels(t)
	_popups(t)
	_ranges(t)
	_toggles(t)
	_tabs(t)
	_scroll(t)
	_text_inputs(t)
	_rich_text(t, regular, bold)
	return t


# --- Style helpers -------------------------------------------------------------------------

static func flat(bg: Color, radius := 10, margins := Vector4(20, 12, 20, 12),
		border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.anti_aliasing = true
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	return sb


static func focus_ring(radius := 10, expand := 3.0) -> StyleBoxFlat:
	var sb := flat(Color.TRANSPARENT, radius + 2, Vector4.ZERO, P.ACCENT, 2)
	sb.draw_center = false
	sb.set_expand_margin_all(expand)
	return sb


static func empty(margins := Vector4.ZERO) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	return sb


static func with_shadow(sb: StyleBoxFlat, size := 18, offset := Vector2(0, 6)) -> StyleBoxFlat:
	sb.shadow_color = P.SHADOW
	sb.shadow_size = size
	sb.shadow_offset = offset
	return sb


# --- Sections ------------------------------------------------------------------------------

static func _containers(t: Theme) -> void:
	t.set_constant("separation", "BoxContainer", 12)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("h_separation", "GridContainer", 24)
	t.set_constant("v_separation", "GridContainer", 14)
	t.set_constant("separation", "HFlowContainer", 12)
	for side: String in ["left", "top", "right", "bottom"]:
		t.set_constant("margin_" + side, "MarginContainer", 0)


static func _labels(t: Theme, bold: Font) -> void:
	t.set_color("font_color", "Label", P.TEXT)
	t.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	t.set_color("font_outline_color", "Label", Color.TRANSPARENT)
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 4)

	var variations := {
		"DisplayLabel": [bold, 72, P.TEXT],
		"TitleLabel": [bold, 44, P.TEXT],
		"HeadingLabel": [bold, 26, P.TEXT],
		"SubtitleLabel": [null, 24, P.TEXT_2],
		"CaptionLabel": [null, 18, P.TEXT_2],
		"SectionLabel": [bold, 16, P.TEXT_2],
		"HintLabel": [null, 17, P.TEXT_2],
		"ValueLabel": [null, 20, P.TEXT_2],
	}
	for variation: String in variations:
		var data: Array = variations[variation]
		t.set_type_variation(variation, "Label")
		if data[0]:
			t.set_font("font", variation, data[0])
		t.set_font_size("font_size", variation, data[1])
		t.set_color("font_color", variation, data[2])

	t.set_type_variation("KeyCap", "Label")
	t.set_font("font", "KeyCap", bold)
	t.set_font_size("font_size", "KeyCap", 15)
	t.set_color("font_color", "KeyCap", P.TEXT_ON_ACCENT)
	t.set_stylebox("normal", "KeyCap", flat(P.TEXT, 6, Vector4(8, 2, 8, 3)))

	t.set_color("font_color", "TooltipLabel", P.TEXT_ON_ACCENT)
	t.set_font_size("font_size", "TooltipLabel", 18)
	t.set_stylebox("panel", "TooltipPanel", with_shadow(flat(P.TEXT, 8, Vector4(14, 10, 14, 10)), 12))


static func _button_colors(t: Theme, type: String, normal: Color, hover: Color, focus: Color,
		disabled := P.TEXT_DISABLED) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_pressed_color", type, hover)
	t.set_color("font_hover_pressed_color", type, hover)
	t.set_color("font_focus_color", type, focus)
	t.set_color("font_disabled_color", type, disabled)
	t.set_color("icon_normal_color", type, normal)
	t.set_color("icon_hover_color", type, hover)
	t.set_color("icon_pressed_color", type, hover)
	t.set_color("icon_focus_color", type, focus)
	t.set_color("icon_disabled_color", type, disabled)
	t.set_color("font_outline_color", type, Color.TRANSPARENT)
	t.set_constant("outline_size", type, 0)


static func _buttons(t: Theme, bold: Font) -> void:
	for type: String in ["Button", "MenuButton", "OptionButton", "LinkButton"]:
		_button_colors(t, type, P.TEXT, P.TEXT, P.TEXT)
	for type: String in ["Button", "MenuButton", "OptionButton"]:
		var margins := Vector4(20, 12, 20, 12) if type != "OptionButton" else Vector4(16, 10, 16, 10)
		t.set_stylebox("normal", type, flat(P.SURFACE, 10, margins, P.BORDER, 1))
		t.set_stylebox("hover", type, flat(P.SURFACE_ALT, 10, margins, P.BORDER_STRONG, 1))
		t.set_stylebox("pressed", type, flat(P.SURFACE_PRESSED, 10, margins, P.BORDER_STRONG, 1))
		t.set_stylebox("hover_pressed", type, flat(P.SURFACE_PRESSED, 10, margins, P.BORDER_STRONG, 1))
		t.set_stylebox("disabled", type, flat(P.SURFACE_DISABLED, 10, margins, P.BORDER, 1))
		t.set_stylebox("focus", type, focus_ring())
		t.set_constant("h_separation", type, 8)
	t.set_icon("arrow", "OptionButton", _chevron_icon(14, 9, P.TEXT_2, false))
	t.set_constant("arrow_margin", "OptionButton", 14)
	t.set_constant("modulate_arrow", "OptionButton", 0)
	t.set_color("font_color", "LinkButton", P.ACCENT)
	t.set_color("font_hover_color", "LinkButton", P.ACCENT_HOVER)
	t.set_stylebox("focus", "LinkButton", focus_ring(4, 2))

	# Big transparent entries of the main and pause menus
	var mib := "MenuItemButton"
	t.set_type_variation(mib, "Button")
	var m := Vector4(28, 14, 28, 14)
	t.set_stylebox("normal", mib, empty(m))
	t.set_stylebox("hover", mib, flat(P.SURFACE, 12, m, P.BORDER, 1))
	t.set_stylebox("pressed", mib, flat(P.SURFACE_PRESSED, 12, m))
	t.set_stylebox("hover_pressed", mib, flat(P.SURFACE_PRESSED, 12, m))
	t.set_stylebox("disabled", mib, empty(m))
	var mib_focus := flat(Color(P.ACCENT, 0.1), 12, Vector4.ZERO)
	mib_focus.border_color = P.ACCENT
	mib_focus.border_width_left = 5
	t.set_stylebox("focus", mib, mib_focus)
	t.set_font_size("font_size", mib, 30)
	_button_colors(t, mib, P.TEXT, P.TEXT, P.ACCENT)

	var primary := "PrimaryButton"
	t.set_type_variation(primary, "Button")
	var pm := Vector4(24, 12, 24, 12)
	t.set_stylebox("normal", primary, flat(P.ACCENT, 10, pm))
	t.set_stylebox("hover", primary, flat(P.ACCENT_HOVER, 10, pm))
	t.set_stylebox("pressed", primary, flat(P.ACCENT_PRESSED, 10, pm))
	t.set_stylebox("hover_pressed", primary, flat(P.ACCENT_PRESSED, 10, pm))
	t.set_stylebox("disabled", primary, flat(P.BORDER_STRONG, 10, pm))
	t.set_font("font", primary, bold)
	_button_colors(t, primary, P.TEXT_ON_ACCENT, P.TEXT_ON_ACCENT, P.TEXT_ON_ACCENT, P.SURFACE)

	var danger := "DangerButton"
	t.set_type_variation(danger, "Button")
	t.set_stylebox("normal", danger, flat(P.DANGER_SOFT, 10, Vector4(20, 12, 20, 12), P.DANGER_BORDER, 1))
	t.set_stylebox("hover", danger, flat(P.DANGER_HOVER, 10, Vector4(20, 12, 20, 12), P.DANGER, 1))
	t.set_stylebox("pressed", danger, flat(P.DANGER_HOVER, 10, Vector4(20, 12, 20, 12), P.DANGER, 1))
	t.set_stylebox("hover_pressed", danger, flat(P.DANGER_HOVER, 10, Vector4(20, 12, 20, 12), P.DANGER, 1))
	_button_colors(t, danger, P.DANGER, P.DANGER, P.DANGER)

	var ghost := "GhostButton"
	t.set_type_variation(ghost, "Button")
	t.set_stylebox("normal", ghost, empty(Vector4(16, 10, 16, 10)))
	t.set_stylebox("hover", ghost, flat(P.SURFACE_ALT, 10, Vector4(16, 10, 16, 10)))
	t.set_stylebox("pressed", ghost, flat(P.SURFACE_PRESSED, 10, Vector4(16, 10, 16, 10)))
	t.set_stylebox("hover_pressed", ghost, flat(P.SURFACE_PRESSED, 10, Vector4(16, 10, 16, 10)))
	_button_colors(t, ghost, P.TEXT_2, P.TEXT, P.TEXT)


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", flat(P.SURFACE, 12, Vector4(24, 24, 24, 24), P.BORDER, 1))
	t.set_stylebox("panel", "Panel", flat(P.SURFACE, 12, Vector4.ZERO, P.BORDER, 1))

	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card",
			with_shadow(flat(P.SURFACE, 16, Vector4(36, 32, 36, 32), P.BORDER, 1)))
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", flat(P.SURFACE_ALT, 12, Vector4(20, 18, 20, 18)))
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", flat(P.SURFACE, 8, Vector4(10, 5, 12, 5), P.BORDER, 1))
	t.set_type_variation("ClearPanel", "PanelContainer")
	t.set_stylebox("panel", "ClearPanel", empty())
	t.set_type_variation("HudPreviewPanel", "PanelContainer")
	var preview := flat(Color("#5B7A99"), 12, Vector4.ZERO)
	t.set_stylebox("panel", "HudPreviewPanel", preview)
	t.set_type_variation("OverlayScrim", "Panel")
	t.set_stylebox("panel", "OverlayScrim", flat(Color(P.BG, 0.72), 0, Vector4.ZERO))

	# Rows that behave like buttons (control bindings)
	var rm := Vector4(14, 8, 14, 8)
	t.set_stylebox("normal", "RowPanel", empty(rm))
	t.set_stylebox("hover", "RowPanel", flat(P.SURFACE_ALT, 8, rm))
	t.set_stylebox("focus", "RowPanel", flat(P.ACCENT_SOFT, 8, rm, P.ACCENT, 2))

	var line := StyleBoxLine.new()
	line.color = P.BORDER
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 16)
	var vline := StyleBoxLine.new()
	vline.color = P.BORDER
	vline.thickness = 1
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)
	t.set_constant("separation", "VSeparator", 16)

	t.set_stylebox("background", "ProgressBar", flat(P.SURFACE_ALT, 4, Vector4.ZERO))
	t.set_stylebox("fill", "ProgressBar", flat(P.ACCENT, 4, Vector4.ZERO))
	t.set_color("font_color", "ProgressBar", P.TEXT)


static func _popups(t: Theme) -> void:
	var panel := with_shadow(flat(P.SURFACE, 12, Vector4(8, 8, 8, 8), P.BORDER, 1), 16)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	t.set_stylebox("hover", "PopupMenu", flat(P.ACCENT_SOFT, 8, Vector4(12, 8, 12, 8)))
	t.set_stylebox("focus", "PopupMenu", flat(P.ACCENT_SOFT, 8, Vector4(12, 8, 12, 8)))
	var sep := StyleBoxLine.new()
	sep.color = P.BORDER
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_color("font_color", "PopupMenu", P.TEXT)
	t.set_color("font_hover_color", "PopupMenu", P.ACCENT_PRESSED)
	t.set_color("font_disabled_color", "PopupMenu", P.TEXT_DISABLED)
	t.set_color("font_accelerator_color", "PopupMenu", P.TEXT_2)
	t.set_color("font_separator_color", "PopupMenu", P.TEXT_2)
	t.set_color("font_outline_color", "PopupMenu", Color.TRANSPARENT)
	t.set_constant("outline_size", "PopupMenu", 0)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_constant("h_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 14)
	t.set_font_size("font_size", "PopupMenu", 20)
	var dot := _dot_icon(18, 7, P.ACCENT)
	var blank := _blank_icon(18)
	for icon: String in ["radio_checked", "checked"]:
		t.set_icon(icon, "PopupMenu", dot)
		t.set_icon(icon + "_disabled", "PopupMenu", dot)
	for icon: String in ["radio_unchecked", "unchecked"]:
		t.set_icon(icon, "PopupMenu", blank)
		t.set_icon(icon + "_disabled", "PopupMenu", blank)
	t.set_icon("submenu", "PopupMenu", _chevron_icon(9, 14, P.TEXT_2, true))

	t.set_stylebox("embedded_border", "Window", empty())
	t.set_stylebox("embedded_unfocused_border", "Window", empty())


static func _ranges(t: Theme) -> void:
	for type: String in ["HSlider", "VSlider"]:
		var track := flat(P.SURFACE_PRESSED, 4, Vector4(0, 3, 0, 3))
		var fill := flat(P.ACCENT, 4, Vector4(0, 3, 0, 3))
		if type == "VSlider":
			track = flat(P.SURFACE_PRESSED, 4, Vector4(3, 0, 3, 0))
			fill = flat(P.ACCENT, 4, Vector4(3, 0, 3, 0))
		t.set_stylebox("slider", type, track)
		t.set_stylebox("grabber_area", type, fill)
		t.set_stylebox("grabber_area_highlight", type, fill)
		t.set_icon("grabber", type, _ring_icon(24, P.SURFACE, P.ACCENT, 2.5))
		t.set_icon("grabber_highlight", type, _ring_icon(26, P.ACCENT, P.SURFACE, 3.0))
		t.set_icon("grabber_disabled", type, _ring_icon(24, P.SURFACE, P.BORDER_STRONG, 2.5))
		t.set_icon("tick", type, _tick_icon(type == "HSlider"))
		t.set_stylebox("focus", type, focus_ring(8, 6))
		t.set_constant("center_grabber", type, 0)
		t.set_constant("grabber_offset", type, 0)


static func _toggles(t: Theme) -> void:
	var m := Vector4(4, 6, 4, 6)
	for type: String in ["CheckButton", "CheckBox"]:
		_button_colors(t, type, P.TEXT, P.TEXT, P.TEXT)
		t.set_stylebox("normal", type, empty(m))
		t.set_stylebox("pressed", type, empty(m))
		t.set_stylebox("hover", type, empty(m))
		t.set_stylebox("hover_pressed", type, empty(m))
		t.set_stylebox("disabled", type, empty(m))
		t.set_stylebox("focus", type, focus_ring(8, 4))
		t.set_constant("h_separation", type, 14)
		t.set_constant("check_v_offset", type, 0)
	var on := _switch_icon(true, P.ACCENT)
	var off := _switch_icon(false, P.BORDER_STRONG)
	var on_disabled := _switch_icon(true, Color(P.ACCENT, 0.4))
	var off_disabled := _switch_icon(false, P.BORDER)
	for suffix: String in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", on)
		t.set_icon("unchecked" + suffix, "CheckButton", off)
		t.set_icon("checked_disabled" + suffix, "CheckButton", on_disabled)
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", off_disabled)
	t.set_icon("checked", "CheckBox", _checkbox_icon(true, P.ACCENT))
	t.set_icon("unchecked", "CheckBox", _checkbox_icon(false, P.BORDER_STRONG))
	t.set_icon("checked_disabled", "CheckBox", _checkbox_icon(true, P.BORDER_STRONG))
	t.set_icon("unchecked_disabled", "CheckBox", _checkbox_icon(false, P.BORDER))
	t.set_icon("radio_checked", "CheckBox", _ring_icon(24, P.SURFACE, P.ACCENT, 7.0))
	t.set_icon("radio_unchecked", "CheckBox", _ring_icon(24, P.SURFACE, P.BORDER_STRONG, 2.0))
	t.set_icon("radio_checked_disabled", "CheckBox", _ring_icon(24, P.SURFACE, P.BORDER_STRONG, 7.0))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _ring_icon(24, P.SURFACE, P.BORDER, 2.0))


static func _tabs(t: Theme) -> void:
	for type: String in ["TabContainer", "TabBar"]:
		var tm := Vector4(22, 10, 22, 10)
		t.set_stylebox("tab_selected", type, flat(P.ACCENT_SOFT, 10, tm))
		t.set_stylebox("tab_unselected", type, empty(tm))
		t.set_stylebox("tab_hovered", type, flat(P.SURFACE_ALT, 10, tm))
		t.set_stylebox("tab_disabled", type, empty(tm))
		t.set_stylebox("tab_focus", type, focus_ring(10, 2))
		t.set_color("font_selected_color", type, P.ACCENT_PRESSED)
		t.set_color("font_unselected_color", type, P.TEXT_2)
		t.set_color("font_hovered_color", type, P.TEXT)
		t.set_color("font_disabled_color", type, P.TEXT_DISABLED)
		t.set_color("font_outline_color", type, Color.TRANSPARENT)
		t.set_constant("h_separation", type, 8)
		t.set_constant("outline_size", type, 0)
	t.set_stylebox("panel", "TabContainer", empty(Vector4(0, 20, 0, 0)))
	t.set_stylebox("tabbar_background", "TabContainer", empty(Vector4(0, 0, 0, 0)))
	t.set_constant("side_margin", "TabContainer", 0)


static func _scroll(t: Theme) -> void:
	t.set_stylebox("panel", "ScrollContainer", empty())
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 14)
	t.set_constant("scrollbar_v_separation", "ScrollContainer", 14)
	t.set_stylebox("focus", "ScrollContainer", empty())
	var blank := _blank_icon(1)
	for type: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, flat(Color.TRANSPARENT, 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("scroll_focus", type, flat(Color.TRANSPARENT, 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber", type, flat(P.BORDER_STRONG, 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_highlight", type, flat(P.TEXT_2, 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_pressed", type, flat(P.TEXT_2, 4, Vector4(3, 3, 3, 3)))
		for icon: String in ["increment", "increment_highlight", "increment_pressed",
				"decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(icon, type, blank)


static func _text_inputs(t: Theme) -> void:
	var m := Vector4(12, 8, 12, 8)
	t.set_stylebox("normal", "LineEdit", flat(P.SURFACE, 8, m, P.BORDER, 1))
	t.set_stylebox("focus", "LineEdit", flat(Color.TRANSPARENT, 8, m, P.ACCENT, 2))
	(t.get_stylebox("focus", "LineEdit") as StyleBoxFlat).draw_center = false
	t.set_stylebox("read_only", "LineEdit", flat(P.SURFACE_DISABLED, 8, m, P.BORDER, 1))
	t.set_color("font_color", "LineEdit", P.TEXT)
	t.set_color("font_uneditable_color", "LineEdit", P.TEXT_2)
	t.set_color("font_placeholder_color", "LineEdit", P.TEXT_DISABLED)
	t.set_color("font_selected_color", "LineEdit", P.TEXT)
	t.set_color("selection_color", "LineEdit", Color(P.ACCENT, 0.25))
	t.set_color("caret_color", "LineEdit", P.ACCENT)
	t.set_color("clear_button_color", "LineEdit", P.TEXT_2)
	t.set_color("font_outline_color", "LineEdit", Color.TRANSPARENT)
	t.set_constant("outline_size", "LineEdit", 0)

	var up := _chevron_icon(12, 8, P.TEXT_2, false, true)
	var down := _chevron_icon(12, 8, P.TEXT_2, false)
	for state: String in ["", "_hover", "_pressed", "_disabled"]:
		t.set_icon("up" + state, "SpinBox", up)
		t.set_icon("down" + state, "SpinBox", down)
	t.set_icon("updown", "SpinBox", _updown_icon())
	t.set_stylebox("up_background", "SpinBox", empty())
	t.set_stylebox("down_background", "SpinBox", empty())
	t.set_stylebox("up_background_hovered", "SpinBox", flat(P.SURFACE_ALT, 6, Vector4.ZERO))
	t.set_stylebox("down_background_hovered", "SpinBox", flat(P.SURFACE_ALT, 6, Vector4.ZERO))
	t.set_stylebox("up_background_pressed", "SpinBox", flat(P.SURFACE_PRESSED, 6, Vector4.ZERO))
	t.set_stylebox("down_background_pressed", "SpinBox", flat(P.SURFACE_PRESSED, 6, Vector4.ZERO))
	t.set_stylebox("up_background_disabled", "SpinBox", empty())
	t.set_stylebox("down_background_disabled", "SpinBox", empty())
	t.set_stylebox("field_and_buttons_separator", "SpinBox", empty())
	t.set_stylebox("up_down_buttons_separator", "SpinBox", empty())
	t.set_constant("buttons_width", "SpinBox", 26)
	t.set_constant("field_and_buttons_separation", "SpinBox", 2)
	t.set_color("up_icon_modulate", "SpinBox", P.TEXT_2)
	t.set_color("up_hover_icon_modulate", "SpinBox", P.ACCENT)
	t.set_color("up_pressed_icon_modulate", "SpinBox", P.ACCENT_PRESSED)
	t.set_color("up_disabled_icon_modulate", "SpinBox", P.TEXT_DISABLED)
	t.set_color("down_icon_modulate", "SpinBox", P.TEXT_2)
	t.set_color("down_hover_icon_modulate", "SpinBox", P.ACCENT)
	t.set_color("down_pressed_icon_modulate", "SpinBox", P.ACCENT_PRESSED)
	t.set_color("down_disabled_icon_modulate", "SpinBox", P.TEXT_DISABLED)


static func _rich_text(t: Theme, regular: Font, bold: Font) -> void:
	t.set_stylebox("normal", "RichTextLabel", empty())
	t.set_stylebox("focus", "RichTextLabel", empty())
	t.set_color("default_color", "RichTextLabel", P.TEXT)
	t.set_color("font_selected_color", "RichTextLabel", P.TEXT)
	t.set_color("selection_color", "RichTextLabel", Color(P.ACCENT, 0.25))
	t.set_color("font_shadow_color", "RichTextLabel", Color.TRANSPARENT)
	t.set_color("font_outline_color", "RichTextLabel", Color.TRANSPARENT)
	t.set_font("normal_font", "RichTextLabel", regular)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_font_size("normal_font_size", "RichTextLabel", 21)
	t.set_font_size("bold_font_size", "RichTextLabel", 21)
	t.set_constant("line_separation", "RichTextLabel", 6)
	t.set_constant("outline_size", "RichTextLabel", 0)
	t.set_type_variation("BodyText", "RichTextLabel")


# --- Procedural icons ----------------------------------------------------------------------

static var _bar_texture: ImageTexture = null


## White rounded bar used (tinted) by the controller axis and button indicators.
static func bar_texture() -> ImageTexture:
	if _bar_texture == null:
		var s := 12
		var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var c := Vector2(s, s) / 2.0
		for y in s:
			for x in s:
				_blend(img, x, y, Color.WHITE,
						0.5 - _rounded_rect_sdf(Vector2(x + 0.5, y + 0.5), c, c, 4.0))
		_bar_texture = _texture(img)
	return _bar_texture


static func _texture(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _blank_icon(size: int) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	return _texture(img)


static func _blend(img: Image, x: int, y: int, color: Color, coverage: float) -> void:
	if coverage <= 0.0:
		return
	var src := Color(color, color.a * clampf(coverage, 0.0, 1.0))
	var dst := img.get_pixel(x, y)
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a <= 0.0:
		return
	var out := Color(
		(src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / out_a,
		(src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / out_a,
		(src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / out_a,
		out_a)
	img.set_pixel(x, y, out)


static func _rounded_rect_sdf(p: Vector2, center: Vector2, half: Vector2, radius: float) -> float:
	var q := (p - center).abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var h := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - a - ab * h).length()


static func _ring_icon(size: int, fill: Color, ring: Color, ring_width: float) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c := Vector2(size, size) / 2.0
	var r := size / 2.0 - 1.0
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length()
			_blend(img, x, y, ring, r + 0.5 - d)
			_blend(img, x, y, fill, (r - ring_width) + 0.5 - d)
	return _texture(img)


static func _dot_icon(size: int, radius: float, color: Color) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length()
			_blend(img, x, y, color, radius / 2.0 + 0.5 - d)
	return _texture(img)


static func _switch_icon(checked: bool, track: Color) -> ImageTexture:
	var w := 50
	var h := 28
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(w, h) / 2.0
	var knob_center := Vector2(h / 2.0 if not checked else w - h / 2.0, h / 2.0)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			_blend(img, x, y, track, 0.5 - _rounded_rect_sdf(p, center, Vector2(w, h) / 2.0 - Vector2.ONE, h / 2.0 - 1.0))
			_blend(img, x, y, P.SURFACE, 0.5 - ((p - knob_center).length() - (h / 2.0 - 4.0)))
	return _texture(img)


static func _checkbox_icon(checked: bool, color: Color) -> ImageTexture:
	var s := 24
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c := Vector2(s, s) / 2.0
	var half := Vector2(s, s) / 2.0 - Vector2.ONE
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _rounded_rect_sdf(p, c, half, 6.0)
			if checked:
				_blend(img, x, y, color, 0.5 - d)
				var dist := minf(_segment_distance(p, Vector2(6.5, 12.5), Vector2(10.5, 16.5)),
						_segment_distance(p, Vector2(10.5, 16.5), Vector2(17.5, 8.0)))
				_blend(img, x, y, P.SURFACE, 1.5 + 0.5 - dist)
			else:
				_blend(img, x, y, color, 0.5 - d)
				_blend(img, x, y, P.SURFACE, 0.5 - _rounded_rect_sdf(p, c, half - Vector2(2, 2), 4.5))
	return _texture(img)


static func _chevron_icon(w: int, h: int, color: Color, pointing_right: bool,
		pointing_up := false) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var a: Vector2
	var b: Vector2
	var c: Vector2
	if pointing_right:
		a = Vector2(2, 2)
		b = Vector2(w - 2.5, h / 2.0)
		c = Vector2(2, h - 2)
	elif pointing_up:
		a = Vector2(2, h - 2)
		b = Vector2(w / 2.0, 2)
		c = Vector2(w - 2, h - 2)
	else:
		a = Vector2(2, 2)
		b = Vector2(w / 2.0, h - 2.5)
		c = Vector2(w - 2, 2)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var dist := minf(_segment_distance(p, a, b), _segment_distance(p, b, c))
			_blend(img, x, y, color, 1.1 + 0.5 - dist)
	return _texture(img)


static func _updown_icon() -> ImageTexture:
	var w := 14
	var h := 22
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var up := minf(_segment_distance(p, Vector2(3, 8), Vector2(7, 4)),
					_segment_distance(p, Vector2(7, 4), Vector2(11, 8)))
			var down := minf(_segment_distance(p, Vector2(3, 14), Vector2(7, 18)),
					_segment_distance(p, Vector2(7, 18), Vector2(11, 14)))
			_blend(img, x, y, P.TEXT_2, 1.1 + 0.5 - minf(up, down))
	return _texture(img)


static func _tick_icon(horizontal: bool) -> ImageTexture:
	var size := Vector2i(2, 8) if horizontal else Vector2i(8, 2)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(P.BORDER_STRONG)
	return _texture(img)
