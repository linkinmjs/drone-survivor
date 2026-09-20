## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Constructor de los dos temas del juego a partir de [UIPalette] (`docs/13` §2.4).
##
## `tools/build_theme.gd` lo corre en headless y escribe `gui/theme/main_theme.tres` y
## `hud/hud_theme.tres`. Ninguno de los dos se edita a mano.
##
## ## Qué cambió en WP-25 respecto del tema claro heredado
##
## - **Esquinas rectas**: radio [constant UIPalette.RADIUS] (2 px) en todo, contra los
##   10–16 px de antes. Los botones ya no son pastillas.
## - **Líneas de 1 px** ([constant UIPalette.BORDER_WIDTH]) y **sin sombras difusas**:
##   un panel se separa del fondo por su borde, no por un halo.
## - **Foco ámbar de 2 px** pegado al control, sin expansión blanda.
## - **Íconos rehechos**: el interruptor es un rectángulo con ranura, la casilla es un
##   cuadrado de 1 px, los chevrones son dos trazos finos y el tirador del deslizador es
##   un anillo delgado. Se fue toda la geometría redondeada tipo iOS.
## - **Tres voces tipográficas** (`docs/13` §2.3): Chakra Petch en títulos y códigos,
##   Barlow Semi Condensed en la voz propia, JetBrains Mono en los números.
## - **Una sola decoración**: la subraya «de rotulador» de [MarkerUnderlineStyle] bajo
##   los encabezados de sección. Nada más.
class_name ThemeBuilder
extends RefCounted

const P := preload("res://gui/theme/ui_palette.gd")
const MarkerStyle := preload("res://gui/theme/marker_underline_style.gd")

## Pares texto/fondo que [method verify_contrast] obliga a pasar 4,5:1. El nombre es
## solo para el informe; lo que manda es el par de colores.
const CONTRAST_PAIRS: Array = [
	["TEXT", P.TEXT, "BG", P.BG],
	["TEXT", P.TEXT, "SURFACE", P.SURFACE],
	["TEXT", P.TEXT, "SURFACE_ALT", P.SURFACE_ALT],
	["TEXT", P.TEXT, "SURFACE_HOVER", P.SURFACE_HOVER],
	["TEXT", P.TEXT, "SURFACE_DISABLED", P.SURFACE_DISABLED],
	["TEXT", P.TEXT, "ACCENT_SOFT", P.ACCENT_SOFT],
	["TEXT_DIM", P.TEXT_DIM, "BG", P.BG],
	["TEXT_DIM", P.TEXT_DIM, "SURFACE", P.SURFACE],
	["TEXT_DIM", P.TEXT_DIM, "SURFACE_ALT", P.SURFACE_ALT],
	["TEXT_DIM", P.TEXT_DIM, "SURFACE_HOVER", P.SURFACE_HOVER],
	["TEXT_MUTED", P.TEXT_MUTED, "BG", P.BG],
	["TEXT_MUTED", P.TEXT_MUTED, "SURFACE", P.SURFACE],
	["TEXT_MUTED", P.TEXT_MUTED, "SURFACE_DISABLED", P.SURFACE_DISABLED],
	["ACCENT", P.ACCENT, "BG", P.BG],
	["ACCENT", P.ACCENT, "SURFACE", P.SURFACE],
	["ACCENT_HOVER", P.ACCENT_HOVER, "BG", P.BG],
	["ACCENT_DIM", P.ACCENT_DIM, "BG", P.BG],
	["ACCENT_DIM", P.ACCENT_DIM, "SURFACE", P.SURFACE],
	["DANGER", P.DANGER, "BG", P.BG],
	["DANGER", P.DANGER, "SURFACE", P.SURFACE],
	["DANGER", P.DANGER, "DANGER_SOFT", P.DANGER_SOFT],
	["SUCCESS", P.SUCCESS, "BG", P.BG],
	["SUCCESS", P.SUCCESS, "SURFACE", P.SURFACE],
	["TARGET", P.TARGET, "BG", P.BG],
	["TARGET", P.TARGET, "SURFACE", P.SURFACE],
	["TEXT_ON_ACCENT", P.TEXT_ON_ACCENT, "ACCENT", P.ACCENT],
	["TEXT_ON_ACCENT", P.TEXT_ON_ACCENT, "ACCENT_HOVER", P.ACCENT_HOVER],
	["TEXT_ON_ACCENT", P.TEXT_ON_ACCENT, "ACCENT_DIM", P.ACCENT_DIM],
	["HUD_TEXT", P.HUD_TEXT, "HUD_SHADOW", Color.BLACK],
	["GRAPH_AXIS", P.GRAPH_AXIS, "GRAPH_BG", P.GRAPH_BG],
]

## Contraste mínimo exigido a cada par de [constant CONTRAST_PAIRS] (WCAG 2.1 AA).
const MIN_CONTRAST: float = 4.5


# --- Tipografías -----------------------------------------------------------------------------

## Chakra Petch SemiBold: títulos, marca y códigos enemigos.
static func font_display() -> Font:
	return load(P.FONT_DISPLAY) as Font


## Barlow Semi Condensed Regular: párrafos de la voz propia.
static func font_regular() -> Font:
	return load(P.FONT_REGULAR) as Font


## Barlow Semi Condensed Medium: rótulos, botones y filas de la voz propia.
static func font_medium() -> Font:
	return load(P.FONT_MEDIUM) as Font


## JetBrains Mono al peso [constant UIPalette.FONT_MONO_WEIGHT]: readouts y números.
##
## La fuente es variable, así que se envuelve en un [FontVariation] en vez de cargar un
## archivo estático por peso.
static func font_mono() -> Font:
	var base := load(P.FONT_MONO) as Font
	var variation := FontVariation.new()
	variation.base_font = base
	var server := TextServerManager.get_primary_interface()
	if server != null:
		variation.variation_opentype = {server.name_to_tag("wght"): P.FONT_MONO_WEIGHT}
	return variation


# --- Verificación de contraste ---------------------------------------------------------------

## Informe de contraste de [constant CONTRAST_PAIRS].
##
## Devuelve un [Dictionary] con `rows` (una fila por par: nombre del texto, nombre del
## fondo y relación) y `failures` (las filas que no llegan a [constant MIN_CONTRAST]).
## `tools/build_theme.gd` aborta si `failures` no está vacío: un tema que no se lee no
## se guarda.
static func verify_contrast() -> Dictionary:
	var rows: Array = []
	var failures: Array = []
	for pair: Array in CONTRAST_PAIRS:
		var ratio := P.contrast_ratio(pair[1] as Color, pair[3] as Color)
		var row := {"text": pair[0], "background": pair[2], "ratio": ratio}
		rows.append(row)
		if ratio < MIN_CONTRAST:
			failures.append(row)
	return {"rows": rows, "failures": failures}


# --- Construcción ----------------------------------------------------------------------------

## Tema de menús completo.
static func build() -> Theme:
	var t := Theme.new()
	var display := font_display()
	var regular := font_regular()
	var medium := font_medium()
	var mono := font_mono()
	t.default_font = medium
	t.default_font_size = 18

	_containers(t)
	_labels(t, display, regular, medium, mono)
	_buttons(t, medium)
	_panels(t)
	_popups(t, medium)
	_ranges(t)
	_toggles(t)
	_tabs(t)
	_scroll(t)
	_text_inputs(t)
	_rich_text(t, regular, medium)
	return t


## Tema del HUD de vuelo (`docs/12` §2.7): mono a 24 px, ámbar y contorno oscuro de
## 3 px. Es independiente del de menús porque sobre el video no hay fondo en el que
## apoyarse.
static func build_hud() -> Theme:
	var t := Theme.new()
	var mono := font_mono()
	t.default_font = mono
	t.default_font_size = 24
	t.set_font("font", "Label", mono)
	t.set_font_size("font_size", "Label", 24)
	t.set_color("font_color", "Label", P.HUD_TEXT)
	t.set_color("font_outline_color", "Label", P.HUD_SHADOW)
	t.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	t.set_constant("outline_size", "Label", P.HUD_OUTLINE)
	t.set_constant("shadow_outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 2)
	return t


# --- Ayudas de estilo ------------------------------------------------------------------------

## [StyleBoxFlat] recto de la identidad nueva. El radio por defecto es
## [constant UIPalette.RADIUS] y el borde, cuando lo hay, es de 1 px.
static func flat(bg: Color, radius := P.RADIUS, margins := Vector4(20, 11, 20, 11),
		border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 2
	sb.anti_aliasing = false
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	return sb


## Anillo de foco: ámbar, [constant UIPalette.FOCUS_WIDTH] px, pegado al control.
static func focus_ring(radius := P.RADIUS, expand := 1.0) -> StyleBoxFlat:
	var sb := flat(Color.TRANSPARENT, radius, Vector4.ZERO, P.BORDER_FOCUS, P.FOCUS_WIDTH)
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


## Subraya «de rotulador» de los encabezados (`docs/13` §2, WP-25).
static func marker_underline(color: Color, thickness: float, seed_value: int,
		bottom := 4.0, max_length := 180.0) -> MarkerUnderlineStyle:
	var sb := MarkerStyle.new()
	sb.color = color
	sb.thickness = thickness
	sb.noise_seed = seed_value
	sb.bottom_inset = bottom
	sb.max_length = max_length
	sb.content_margin_left = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_bottom = bottom + thickness + 2.0
	return sb


# --- Secciones -------------------------------------------------------------------------------

static func _containers(t: Theme) -> void:
	t.set_constant("separation", "BoxContainer", P.MARGIN_SM + 2)
	t.set_constant("separation", "VBoxContainer", P.MARGIN_SM + 2)
	t.set_constant("separation", "HBoxContainer", P.MARGIN_SM + 2)
	t.set_constant("h_separation", "GridContainer", P.MARGIN_LG)
	t.set_constant("v_separation", "GridContainer", P.MARGIN_MD - 2)
	t.set_constant("separation", "HFlowContainer", P.MARGIN_SM + 2)
	for side: String in ["left", "top", "right", "bottom"]:
		t.set_constant("margin_" + side, "MarginContainer", 0)


static func _labels(t: Theme, display: Font, regular: Font, medium: Font, mono: Font) -> void:
	t.set_font("font", "Label", medium)
	t.set_color("font_color", "Label", P.TEXT)
	t.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	t.set_color("font_outline_color", "Label", Color.TRANSPARENT)
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 4)

	# fuente, tamaño, color. Chakra Petch es la voz de máquina y de marca; Barlow, la
	# propia; JetBrains Mono, la de los números.
	var variations := {
		"DisplayLabel": [display, 60, P.TEXT],
		"TitleLabel": [display, 44, P.TEXT],
		"HeadingLabel": [display, 32, P.TEXT],
		"SectionLabel": [display, 20, P.ACCENT],
		"SubtitleLabel": [regular, 20, P.TEXT_DIM],
		"ValueLabel": [medium, 18, P.TEXT_DIM],
		"CaptionLabel": [regular, 16, P.TEXT_DIM],
		"HintLabel": [regular, 16, P.TEXT_MUTED],
		"MonoLabel": [mono, 24, P.TEXT],
		"LoadingLabel": [medium, 26, P.ACCENT],
		"LoadingTipLabel": [regular, 18, P.ACCENT_DIM],
		"MonoSmallLabel": [mono, 18, P.TEXT_DIM],
		"CodeLabel": [display, 20, P.TARGET],
	}
	for variation: String in variations:
		var data: Array = variations[variation]
		t.set_type_variation(variation, "Label")
		t.set_font("font", variation, data[0] as Font)
		t.set_font_size("font_size", variation, data[1])
		t.set_color("font_color", variation, data[2] as Color)

	# La única decoración de la identidad: dos semillas distintas para que los dos
	# encabezados no repitan el mismo temblor.
	t.set_stylebox("normal", "HeadingLabel",
			marker_underline(P.ACCENT, 2.0, 20260920, 5.0, 190.0))
	t.set_stylebox("normal", "SectionLabel",
			marker_underline(P.ACCENT_DIM, 2.0, 71104, 4.0, 120.0))

	t.set_type_variation("KeyCap", "Label")
	t.set_font("font", "KeyCap", mono)
	t.set_font_size("font_size", "KeyCap", 15)
	t.set_color("font_color", "KeyCap", P.TEXT)
	t.set_stylebox("normal", "KeyCap",
			flat(P.SURFACE_HOVER, P.RADIUS, Vector4(8, 2, 8, 3), P.BORDER_STRONG, P.BORDER_WIDTH))

	t.set_color("font_color", "TooltipLabel", P.TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_stylebox("panel", "TooltipPanel",
			flat(P.SURFACE, P.RADIUS, Vector4(12, 8, 12, 8), P.BORDER_STRONG, P.BORDER_WIDTH))


static func _button_colors(t: Theme, type: String, normal: Color, hover: Color, focus: Color,
		disabled := P.TEXT_MUTED) -> void:
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


static func _buttons(t: Theme, medium: Font) -> void:
	for type: String in ["Button", "MenuButton", "OptionButton", "LinkButton"]:
		_button_colors(t, type, P.TEXT, P.TEXT, P.ACCENT)
		t.set_font("font", type, medium)
	for type: String in ["Button", "MenuButton", "OptionButton"]:
		var margins := Vector4(20, 11, 20, 11) if type != "OptionButton" \
				else Vector4(14, 9, 14, 9)
		t.set_stylebox("normal", type, flat(P.SURFACE, P.RADIUS, margins, P.BORDER, P.BORDER_WIDTH))
		t.set_stylebox("hover", type,
				flat(P.SURFACE_HOVER, P.RADIUS, margins, P.BORDER_STRONG, P.BORDER_WIDTH))
		t.set_stylebox("pressed", type,
				flat(P.SURFACE_ALT, P.RADIUS, margins, P.ACCENT_DIM, P.BORDER_WIDTH))
		t.set_stylebox("hover_pressed", type,
				flat(P.SURFACE_ALT, P.RADIUS, margins, P.ACCENT_DIM, P.BORDER_WIDTH))
		t.set_stylebox("disabled", type,
				flat(P.SURFACE_DISABLED, P.RADIUS, margins, P.BORDER, P.BORDER_WIDTH))
		t.set_stylebox("focus", type, focus_ring())
		t.set_constant("h_separation", type, P.MARGIN_SM)
	t.set_icon("arrow", "OptionButton", _chevron_icon(14, 8, P.TEXT_DIM, false))
	t.set_constant("arrow_margin", "OptionButton", 12)
	t.set_constant("modulate_arrow", "OptionButton", 0)
	t.set_color("font_color", "LinkButton", P.ACCENT)
	t.set_color("font_hover_color", "LinkButton", P.ACCENT_HOVER)
	t.set_stylebox("focus", "LinkButton", focus_ring(P.RADIUS, 2.0))

	# Entradas grandes y transparentes del menú principal y de la pausa.
	var mib := "MenuItemButton"
	t.set_type_variation(mib, "Button")
	var m := Vector4(22, 12, 22, 12)
	t.set_stylebox("normal", mib, empty(m))
	t.set_stylebox("hover", mib, flat(P.SURFACE, P.RADIUS, m, P.BORDER, P.BORDER_WIDTH))
	t.set_stylebox("pressed", mib, flat(P.SURFACE_ALT, P.RADIUS, m, P.ACCENT_DIM, P.BORDER_WIDTH))
	t.set_stylebox("hover_pressed", mib,
			flat(P.SURFACE_ALT, P.RADIUS, m, P.ACCENT_DIM, P.BORDER_WIDTH))
	t.set_stylebox("disabled", mib, empty(m))
	# El foco de una entrada grande es una barra ámbar a la izquierda: se ve de lejos y
	# no encierra la palabra en una caja.
	var mib_focus := flat(P.ACCENT_SOFT, P.RADIUS, Vector4.ZERO)
	mib_focus.border_color = P.ACCENT
	mib_focus.border_width_left = 4
	t.set_stylebox("focus", mib, mib_focus)
	t.set_font("font", mib, medium)
	t.set_font_size("font_size", mib, 28)
	_button_colors(t, mib, P.TEXT, P.ACCENT_HOVER, P.ACCENT)

	var primary := "PrimaryButton"
	t.set_type_variation(primary, "Button")
	var pm := Vector4(24, 12, 24, 12)
	t.set_stylebox("normal", primary, flat(P.ACCENT, P.RADIUS, pm))
	t.set_stylebox("hover", primary, flat(P.ACCENT_HOVER, P.RADIUS, pm))
	t.set_stylebox("pressed", primary, flat(P.ACCENT_DIM, P.RADIUS, pm))
	t.set_stylebox("hover_pressed", primary, flat(P.ACCENT_DIM, P.RADIUS, pm))
	t.set_stylebox("disabled", primary,
			flat(P.SURFACE_DISABLED, P.RADIUS, pm, P.BORDER, P.BORDER_WIDTH))
	t.set_stylebox("focus", primary, focus_ring(P.RADIUS, 3.0))
	t.set_font("font", primary, medium)
	_button_colors(t, primary, P.TEXT_ON_ACCENT, P.TEXT_ON_ACCENT, P.TEXT_ON_ACCENT, P.TEXT_MUTED)

	var danger := "DangerButton"
	t.set_type_variation(danger, "Button")
	var dm := Vector4(20, 11, 20, 11)
	t.set_stylebox("normal", danger, flat(P.DANGER_SOFT, P.RADIUS, dm, P.DANGER_BORDER, P.BORDER_WIDTH))
	t.set_stylebox("hover", danger, flat(P.DANGER_HOVER, P.RADIUS, dm, P.DANGER, P.BORDER_WIDTH))
	t.set_stylebox("pressed", danger, flat(P.DANGER_HOVER, P.RADIUS, dm, P.DANGER, P.BORDER_WIDTH))
	t.set_stylebox("hover_pressed", danger,
			flat(P.DANGER_HOVER, P.RADIUS, dm, P.DANGER, P.BORDER_WIDTH))
	t.set_stylebox("focus", danger, focus_ring())
	_button_colors(t, danger, P.DANGER, P.DANGER, P.DANGER)

	var ghost := "GhostButton"
	t.set_type_variation(ghost, "Button")
	var gm := Vector4(16, 9, 16, 9)
	t.set_stylebox("normal", ghost, empty(gm))
	t.set_stylebox("hover", ghost, flat(P.SURFACE_HOVER, P.RADIUS, gm))
	t.set_stylebox("pressed", ghost, flat(P.SURFACE_ALT, P.RADIUS, gm))
	t.set_stylebox("hover_pressed", ghost, flat(P.SURFACE_ALT, P.RADIUS, gm))
	t.set_stylebox("focus", ghost, focus_ring())
	_button_colors(t, ghost, P.TEXT_DIM, P.TEXT, P.ACCENT)


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer",
			flat(P.SURFACE, P.RADIUS, Vector4(22, 20, 22, 20), P.BORDER, P.BORDER_WIDTH))
	t.set_stylebox("panel", "Panel", flat(P.SURFACE, P.RADIUS, Vector4.ZERO, P.BORDER, P.BORDER_WIDTH))

	var card := flat(P.SURFACE, P.RADIUS, Vector4(30, 26, 30, 26), P.BORDER, P.BORDER_WIDTH)
	for name: String in ["Card", "CardPanel"]:
		t.set_type_variation(name, "PanelContainer")
		t.set_stylebox("panel", name, card)
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel",
			flat(P.SURFACE_ALT, P.RADIUS, Vector4(18, 16, 18, 16), P.BORDER, P.BORDER_WIDTH))
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip",
			flat(P.SURFACE_ALT, P.RADIUS, Vector4(10, 4, 12, 4), P.BORDER, P.BORDER_WIDTH))
	t.set_type_variation("ClearPanel", "PanelContainer")
	t.set_stylebox("panel", "ClearPanel", empty())
	t.set_type_variation("HudPreviewPanel", "PanelContainer")
	# La vista previa del HUD imita la señal del dron: un slate oscuro sobre el que el
	# ámbar del HUD se lee igual que en vuelo.
	t.set_stylebox("panel", "HudPreviewPanel",
			flat(Color("#232E38"), P.RADIUS, Vector4.ZERO, P.BORDER, P.BORDER_WIDTH))
	t.set_type_variation("OverlayScrim", "Panel")
	t.set_stylebox("panel", "OverlayScrim", flat(P.SCRIM, 0, Vector4.ZERO))

	# Filas que se comportan como botones (asignación de controles)
	var rm := Vector4(14, 8, 14, 8)
	t.set_stylebox("normal", "RowPanel", empty(rm))
	t.set_stylebox("hover", "RowPanel", flat(P.SURFACE_HOVER, P.RADIUS, rm))
	t.set_stylebox("focus", "RowPanel",
			flat(P.ACCENT_SOFT, P.RADIUS, rm, P.ACCENT, P.FOCUS_WIDTH))

	var line := StyleBoxLine.new()
	line.color = P.BORDER
	line.thickness = P.BORDER_WIDTH
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", P.MARGIN_MD)
	var vline := StyleBoxLine.new()
	vline.color = P.BORDER
	vline.thickness = P.BORDER_WIDTH
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)
	t.set_constant("separation", "VSeparator", P.MARGIN_MD)

	t.set_stylebox("background", "ProgressBar",
			flat(P.SURFACE_ALT, P.RADIUS, Vector4.ZERO, P.BORDER, P.BORDER_WIDTH))
	t.set_stylebox("fill", "ProgressBar", flat(P.ACCENT, P.RADIUS, Vector4.ZERO))
	t.set_color("font_color", "ProgressBar", P.TEXT)


static func _popups(t: Theme, medium: Font) -> void:
	var panel := flat(P.SURFACE, P.RADIUS, Vector4(6, 6, 6, 6), P.BORDER_STRONG, P.BORDER_WIDTH)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("panel", "PopupPanel", panel)
	t.set_stylebox("hover", "PopupMenu", flat(P.ACCENT_SOFT, P.RADIUS, Vector4(12, 7, 12, 7)))
	t.set_stylebox("focus", "PopupMenu", flat(P.ACCENT_SOFT, P.RADIUS, Vector4(12, 7, 12, 7)))
	var sep := StyleBoxLine.new()
	sep.color = P.BORDER
	sep.thickness = P.BORDER_WIDTH
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_font("font", "PopupMenu", medium)
	t.set_color("font_color", "PopupMenu", P.TEXT)
	t.set_color("font_hover_color", "PopupMenu", P.ACCENT)
	t.set_color("font_disabled_color", "PopupMenu", P.TEXT_MUTED)
	t.set_color("font_accelerator_color", "PopupMenu", P.TEXT_MUTED)
	t.set_color("font_separator_color", "PopupMenu", P.TEXT_MUTED)
	t.set_color("font_outline_color", "PopupMenu", Color.TRANSPARENT)
	t.set_constant("outline_size", "PopupMenu", 0)
	t.set_constant("v_separation", "PopupMenu", P.MARGIN_SM)
	t.set_constant("h_separation", "PopupMenu", P.MARGIN_SM)
	t.set_constant("item_start_padding", "PopupMenu", P.MARGIN_SM)
	t.set_constant("item_end_padding", "PopupMenu", P.MARGIN_MD - 4)
	t.set_font_size("font_size", "PopupMenu", 18)
	var dot := _dot_icon(16, 6, P.ACCENT)
	var blank := _blank_icon(16)
	for icon: String in ["radio_checked", "checked"]:
		t.set_icon(icon, "PopupMenu", dot)
		t.set_icon(icon + "_disabled", "PopupMenu", dot)
	for icon: String in ["radio_unchecked", "unchecked"]:
		t.set_icon(icon, "PopupMenu", blank)
		t.set_icon(icon + "_disabled", "PopupMenu", blank)
	t.set_icon("submenu", "PopupMenu", _chevron_icon(8, 14, P.TEXT_DIM, true))

	t.set_stylebox("embedded_border", "Window", empty())
	t.set_stylebox("embedded_unfocused_border", "Window", empty())


static func _ranges(t: Theme) -> void:
	for type: String in ["HSlider", "VSlider"]:
		var track := flat(P.SURFACE_HOVER, 0, Vector4(0, 2, 0, 2))
		var fill := flat(P.ACCENT, 0, Vector4(0, 2, 0, 2))
		if type == "VSlider":
			track = flat(P.SURFACE_HOVER, 0, Vector4(2, 0, 2, 0))
			fill = flat(P.ACCENT, 0, Vector4(2, 0, 2, 0))
		t.set_stylebox("slider", type, track)
		t.set_stylebox("grabber_area", type, fill)
		t.set_stylebox("grabber_area_highlight", type, fill)
		t.set_icon("grabber", type, _ring_icon(18, P.BG, P.ACCENT, 1.5))
		t.set_icon("grabber_highlight", type, _ring_icon(20, P.BG, P.ACCENT_HOVER, 2.0))
		t.set_icon("grabber_disabled", type, _ring_icon(18, P.BG, P.BORDER_STRONG, 1.5))
		t.set_icon("tick", type, _tick_icon(type == "HSlider"))
		t.set_stylebox("focus", type, focus_ring(P.RADIUS, 5.0))
		t.set_constant("center_grabber", type, 0)
		t.set_constant("grabber_offset", type, 0)


static func _toggles(t: Theme) -> void:
	var m := Vector4(4, 6, 4, 6)
	for type: String in ["CheckButton", "CheckBox"]:
		_button_colors(t, type, P.TEXT, P.TEXT, P.ACCENT)
		t.set_stylebox("normal", type, empty(m))
		t.set_stylebox("pressed", type, empty(m))
		t.set_stylebox("hover", type, empty(m))
		t.set_stylebox("hover_pressed", type, empty(m))
		t.set_stylebox("disabled", type, empty(m))
		t.set_stylebox("focus", type, focus_ring(P.RADIUS, 3.0))
		t.set_constant("h_separation", type, 12)
		t.set_constant("check_v_offset", type, 0)
	var on := _switch_icon(true, P.ACCENT, P.BG)
	var off := _switch_icon(false, P.BORDER_STRONG, P.SURFACE_ALT)
	var on_disabled := _switch_icon(true, P.ACCENT_DIM, P.BG)
	var off_disabled := _switch_icon(false, P.BORDER, P.SURFACE_DISABLED)
	for suffix: String in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", on)
		t.set_icon("unchecked" + suffix, "CheckButton", off)
		t.set_icon("checked_disabled" + suffix, "CheckButton", on_disabled)
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", off_disabled)
	t.set_icon("checked", "CheckBox", _checkbox_icon(true, P.ACCENT))
	t.set_icon("unchecked", "CheckBox", _checkbox_icon(false, P.BORDER_STRONG))
	t.set_icon("checked_disabled", "CheckBox", _checkbox_icon(true, P.BORDER_STRONG))
	t.set_icon("unchecked_disabled", "CheckBox", _checkbox_icon(false, P.BORDER))
	t.set_icon("radio_checked", "CheckBox", _ring_icon(20, P.ACCENT, P.ACCENT, 1.5, 4.0))
	t.set_icon("radio_unchecked", "CheckBox", _ring_icon(20, Color.TRANSPARENT, P.BORDER_STRONG, 1.5))
	t.set_icon("radio_checked_disabled", "CheckBox",
			_ring_icon(20, P.BORDER_STRONG, P.BORDER_STRONG, 1.5, 4.0))
	t.set_icon("radio_unchecked_disabled", "CheckBox",
			_ring_icon(20, Color.TRANSPARENT, P.BORDER, 1.5))


static func _tabs(t: Theme) -> void:
	for type: String in ["TabContainer", "TabBar"]:
		var tm := Vector4(20, 9, 20, 9)
		var selected := flat(P.SURFACE, P.RADIUS, tm)
		selected.border_color = P.ACCENT
		selected.border_width_bottom = 2
		t.set_stylebox("tab_selected", type, selected)
		t.set_stylebox("tab_unselected", type, empty(tm))
		t.set_stylebox("tab_hovered", type, flat(P.SURFACE_ALT, P.RADIUS, tm))
		t.set_stylebox("tab_disabled", type, empty(tm))
		t.set_stylebox("tab_focus", type, focus_ring(P.RADIUS, 1.0))
		t.set_color("font_selected_color", type, P.ACCENT)
		t.set_color("font_unselected_color", type, P.TEXT_DIM)
		t.set_color("font_hovered_color", type, P.TEXT)
		t.set_color("font_disabled_color", type, P.TEXT_MUTED)
		t.set_color("font_outline_color", type, Color.TRANSPARENT)
		t.set_constant("h_separation", type, P.MARGIN_SM)
		t.set_constant("outline_size", type, 0)
	t.set_stylebox("panel", "TabContainer", empty(Vector4(0, P.MARGIN_LG - 4, 0, 0)))
	t.set_stylebox("tabbar_background", "TabContainer", empty(Vector4.ZERO))
	t.set_constant("side_margin", "TabContainer", 0)


static func _scroll(t: Theme) -> void:
	t.set_stylebox("panel", "ScrollContainer", empty())
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 12)
	t.set_constant("scrollbar_v_separation", "ScrollContainer", 12)
	t.set_stylebox("focus", "ScrollContainer", empty())
	var blank := _blank_icon(1)
	for type: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, flat(Color.TRANSPARENT, 0, Vector4(3, 3, 3, 3)))
		t.set_stylebox("scroll_focus", type, flat(Color.TRANSPARENT, 0, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber", type, flat(P.BORDER_STRONG, 0, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_highlight", type, flat(P.TEXT_MUTED, 0, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_pressed", type, flat(P.ACCENT_DIM, 0, Vector4(3, 3, 3, 3)))
		for icon: String in ["increment", "increment_highlight", "increment_pressed",
				"decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(icon, type, blank)


static func _text_inputs(t: Theme) -> void:
	var m := Vector4(12, 8, 12, 8)
	t.set_stylebox("normal", "LineEdit",
			flat(P.SURFACE_ALT, P.RADIUS, m, P.BORDER, P.BORDER_WIDTH))
	var focus := flat(Color.TRANSPARENT, P.RADIUS, m, P.ACCENT, P.FOCUS_WIDTH)
	focus.draw_center = false
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit",
			flat(P.SURFACE_DISABLED, P.RADIUS, m, P.BORDER, P.BORDER_WIDTH))
	t.set_color("font_color", "LineEdit", P.TEXT)
	t.set_color("font_uneditable_color", "LineEdit", P.TEXT_DIM)
	t.set_color("font_placeholder_color", "LineEdit", P.TEXT_MUTED)
	t.set_color("font_selected_color", "LineEdit", P.TEXT_ON_ACCENT)
	t.set_color("selection_color", "LineEdit", P.ACCENT_DIM)
	t.set_color("caret_color", "LineEdit", P.ACCENT)
	t.set_color("clear_button_color", "LineEdit", P.TEXT_DIM)
	t.set_color("font_outline_color", "LineEdit", Color.TRANSPARENT)
	t.set_constant("outline_size", "LineEdit", 0)

	var up := _chevron_icon(12, 7, P.TEXT_DIM, false, true)
	var down := _chevron_icon(12, 7, P.TEXT_DIM, false)
	for state: String in ["", "_hover", "_pressed", "_disabled"]:
		t.set_icon("up" + state, "SpinBox", up)
		t.set_icon("down" + state, "SpinBox", down)
	t.set_icon("updown", "SpinBox", _updown_icon())
	t.set_stylebox("up_background", "SpinBox", empty())
	t.set_stylebox("down_background", "SpinBox", empty())
	t.set_stylebox("up_background_hovered", "SpinBox", flat(P.SURFACE_HOVER, P.RADIUS, Vector4.ZERO))
	t.set_stylebox("down_background_hovered", "SpinBox", flat(P.SURFACE_HOVER, P.RADIUS, Vector4.ZERO))
	t.set_stylebox("up_background_pressed", "SpinBox", flat(P.SURFACE_ALT, P.RADIUS, Vector4.ZERO))
	t.set_stylebox("down_background_pressed", "SpinBox", flat(P.SURFACE_ALT, P.RADIUS, Vector4.ZERO))
	t.set_stylebox("up_background_disabled", "SpinBox", empty())
	t.set_stylebox("down_background_disabled", "SpinBox", empty())
	t.set_stylebox("field_and_buttons_separator", "SpinBox", empty())
	t.set_stylebox("up_down_buttons_separator", "SpinBox", empty())
	t.set_constant("buttons_width", "SpinBox", 24)
	t.set_constant("field_and_buttons_separation", "SpinBox", 2)
	t.set_color("up_icon_modulate", "SpinBox", P.TEXT_DIM)
	t.set_color("up_hover_icon_modulate", "SpinBox", P.ACCENT)
	t.set_color("up_pressed_icon_modulate", "SpinBox", P.ACCENT_DIM)
	t.set_color("up_disabled_icon_modulate", "SpinBox", P.TEXT_MUTED)
	t.set_color("down_icon_modulate", "SpinBox", P.TEXT_DIM)
	t.set_color("down_hover_icon_modulate", "SpinBox", P.ACCENT)
	t.set_color("down_pressed_icon_modulate", "SpinBox", P.ACCENT_DIM)
	t.set_color("down_disabled_icon_modulate", "SpinBox", P.TEXT_MUTED)


static func _rich_text(t: Theme, regular: Font, medium: Font) -> void:
	t.set_stylebox("normal", "RichTextLabel", empty())
	t.set_stylebox("focus", "RichTextLabel", empty())
	t.set_color("default_color", "RichTextLabel", P.TEXT)
	t.set_color("font_selected_color", "RichTextLabel", P.TEXT_ON_ACCENT)
	t.set_color("selection_color", "RichTextLabel", P.ACCENT_DIM)
	t.set_color("font_shadow_color", "RichTextLabel", Color.TRANSPARENT)
	t.set_color("font_outline_color", "RichTextLabel", Color.TRANSPARENT)
	t.set_font("normal_font", "RichTextLabel", regular)
	t.set_font("bold_font", "RichTextLabel", medium)
	t.set_font("mono_font", "RichTextLabel", font_mono())
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 19)
	t.set_constant("line_separation", "RichTextLabel", 6)
	t.set_constant("outline_size", "RichTextLabel", 0)
	t.set_type_variation("BodyText", "RichTextLabel")


# --- Íconos procedurales ---------------------------------------------------------------------

static var _bar_texture: ImageTexture = null


## Barra blanca de esquinas casi rectas que los indicadores de eje y de botón del
## menú de controles tiñen con [member CanvasItem.modulate].
static func bar_texture() -> ImageTexture:
	if _bar_texture == null:
		var s := 12
		var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var c := Vector2(s, s) / 2.0
		for y in s:
			for x in s:
				_blend(img, x, y, Color.WHITE,
						0.5 - _rounded_rect_sdf(Vector2(x + 0.5, y + 0.5), c, c, 1.0))
		_bar_texture = _texture(img)
	return _bar_texture


static func _texture(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _blank_icon(size: int) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	return _texture(img)


static func _blend(img: Image, x: int, y: int, color: Color, coverage: float) -> void:
	if coverage <= 0.0 or color.a <= 0.0:
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


## Anillo fino. [param inner_radius] mayor que cero dibuja además un punto centrado del
## color del relleno (radio de selección).
static func _ring_icon(size: int, fill: Color, ring: Color, ring_width: float,
		inner_radius := 0.0) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c := Vector2(size, size) / 2.0
	var r := size / 2.0 - 1.0
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length()
			_blend(img, x, y, ring, minf(r + 0.5 - d, d - (r - ring_width) + 0.5))
			if inner_radius > 0.0:
				_blend(img, x, y, fill, inner_radius + 0.5 - d)
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


## Interruptor **rectangular con ranura**: un marco de 1 px, un carril interno y un
## taco que se corre de lado. Nada de pastilla con bolita.
static func _switch_icon(checked: bool, frame: Color, knob_back: Color) -> ImageTexture:
	var w := 44
	var h := 22
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(w, h) / 2.0
	var half := Vector2(w, h) / 2.0 - Vector2.ONE
	var knob := Rect2(Vector2(3.0 if not checked else w / 2.0, 3.0),
			Vector2(w / 2.0 - 3.0, h - 6.0))
	var knob_center := knob.position + knob.size / 2.0
	var knob_half := knob.size / 2.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# Marco de 1 px.
			var outer := _rounded_rect_sdf(p, center, half, 1.0)
			_blend(img, x, y, frame, minf(0.5 - outer, outer + 1.0 + 0.5))
			# Fondo de la ranura.
			_blend(img, x, y, knob_back, 0.5 - _rounded_rect_sdf(p, center, half - Vector2(2, 2), 0.5))
			# Taco.
			_blend(img, x, y, frame, 0.5 - _rounded_rect_sdf(p, knob_center, knob_half, 0.5))
	return _texture(img)


## Casilla **cuadrada de 1 px**; marcada se rellena con un cuadrado interior, sin
## palomita redondeada.
static func _checkbox_icon(checked: bool, color: Color) -> ImageTexture:
	var s := 20
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c := Vector2(s, s) / 2.0
	var half := Vector2(s, s) / 2.0 - Vector2.ONE
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var outer := _rounded_rect_sdf(p, c, half, 1.0)
			_blend(img, x, y, color, minf(0.5 - outer, outer + 1.0 + 0.5))
			if checked:
				_blend(img, x, y, color,
						0.5 - _rounded_rect_sdf(p, c, half - Vector2(4, 4), 0.5))
	return _texture(img)


## Chevron de **dos trazos finos**, sin relleno.
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
			_blend(img, x, y, color, 0.6 + 0.5 - dist)
	return _texture(img)


static func _updown_icon() -> ImageTexture:
	var w := 12
	var h := 20
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var up := minf(_segment_distance(p, Vector2(2, 7), Vector2(6, 3)),
					_segment_distance(p, Vector2(6, 3), Vector2(10, 7)))
			var down := minf(_segment_distance(p, Vector2(2, 13), Vector2(6, 17)),
					_segment_distance(p, Vector2(6, 17), Vector2(10, 13)))
			_blend(img, x, y, P.TEXT_DIM, 0.6 + 0.5 - minf(up, down))
	return _texture(img)


static func _tick_icon(horizontal: bool) -> ImageTexture:
	var size := Vector2i(1, 6) if horizontal else Vector2i(6, 1)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(P.BORDER_STRONG)
	return _texture(img)
