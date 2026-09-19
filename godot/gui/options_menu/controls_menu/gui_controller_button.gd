## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Testigo de un botón del mando (`docs/04` §4.5).
##
## La vista en vivo del menú de controles crea dieciséis, uno por botón físico,
## y los enciende con `Input.is_joy_button_pressed()` del dispositivo activo. El
## número del botón va dentro del testigo, que es justo el dato que el jugador
## necesita para entender qué dice `CTRL_BOUND_BUTTON`.
##
## Igual que [GUIControllerAxis], se dibuja con la textura procedural de
## [method ThemeBuilder.bar_texture] teñida, sin archivos de imagen.
class_name GUIControllerButton
extends TextureProgressBar

## Tamaño del testigo, elegido para que entren dos filas de ocho en la tarjeta.
const DOT_SIZE: Vector2 = Vector2(40, 28)

## Margen del nine patch de la textura de 12 × 12 de [ThemeBuilder].
const PATCH_MARGIN: int = 5

## Índice del botón físico que muestra este testigo.
var button_index: int = 0

var _label: Label = null


func _ready() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 1.0
	value = 0.0
	fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	nine_patch_stretch = true
	stretch_margin_left = PATCH_MARGIN
	stretch_margin_right = PATCH_MARGIN
	stretch_margin_top = PATCH_MARGIN
	stretch_margin_bottom = PATCH_MARGIN
	texture_under = ThemeBuilder.bar_texture()
	texture_progress = ThemeBuilder.bar_texture()
	tint_under = UIPalette.SURFACE_PRESSED
	tint_progress = UIPalette.ACCENT
	custom_minimum_size = DOT_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GUIControllerAxis.silence_ui_tick(self)
	_build_label()


## Índice del botón; también es el número que se dibuja dentro.
func setup(index: int) -> void:
	button_index = index
	if _label != null:
		_label.text = str(index)


## Enciende o apaga el testigo.
func set_pressed_state(pressed: bool) -> void:
	var wanted := 1.0 if pressed else 0.0
	if is_equal_approx(float(value), wanted):
		return
	value = wanted
	if _label != null:
		_label.add_theme_color_override(&"font_color",
				UIPalette.TEXT_ON_ACCENT if pressed else UIPalette.TEXT_2)


## El número vive dentro del testigo, anclado a todo el rectángulo: así el
## contenedor que ordena la rejilla solo tiene que colocar un nodo por botón.
func _build_label() -> void:
	_label = Label.new()
	_label.text = str(button_index)
	_label.theme_type_variation = &"CaptionLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# El número no es texto traducible: es el índice físico del botón.
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.add_theme_color_override(&"font_color", UIPalette.TEXT_2)
	add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
