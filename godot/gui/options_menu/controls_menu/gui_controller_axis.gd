## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Barra de un eje analógico del mando, de −1 a 1 (`docs/04` §4.5).
##
## Es un indicador de solo lectura: la vista en vivo del menú de controles crea
## ocho, una por eje físico, y les vuelca en cada frame lo que devuelve
## `Input.get_joy_axis()` del dispositivo activo. El reposo del eje queda en la
## mitad de la barra, así se distingue de un vistazo un stick centrado de un
## gatillo en reposo (que descansa en −1.0).
##
## La textura sale de [method ThemeBuilder.bar_texture]: una barra blanca de
## esquinas redondeadas que se tiñe con `tint_under` y `tint_progress`, de modo
## que el widget no arrastra ningún archivo de imagen.
class_name GUIControllerAxis
extends TextureProgressBar

## Alto de la barra; el ancho lo decide el contenedor.
const BAR_HEIGHT: int = 14

## Ancho mínimo, para que la barra siga siendo legible en la columna angosta.
const BAR_MIN_WIDTH: int = 140

## Margen del nine patch de la textura de 12 × 12 de [ThemeBuilder].
const PATCH_MARGIN: int = 5

## Deflexión a partir de la cual la barra se tiñe de acento, para que se note
## cuál de los ocho ejes está moviendo el jugador.
const ACTIVE_THRESHOLD: float = 0.25

## Índice del eje físico que muestra esta barra.
var axis_index: int = 0


func _ready() -> void:
	min_value = -1.0
	max_value = 1.0
	step = 0.0
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
	tint_progress = UIPalette.BORDER_STRONG
	custom_minimum_size = Vector2(BAR_MIN_WIDTH, BAR_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	silence_ui_tick(self)


## Índice del eje que representa la barra.
func setup(index: int) -> void:
	axis_index = index


## Vuelca la deflexión cruda del eje, acotada a `[−1, 1]`.
func set_axis_value(raw: float) -> void:
	var clamped := clampf(raw, -1.0, 1.0)
	if is_equal_approx(float(value), clamped):
		return
	value = clamped
	tint_progress = UIPalette.ACCENT if absf(clamped) >= ACTIVE_THRESHOLD \
			else UIPalette.BORDER_STRONG


## `UI` conecta un sonido de deslizador a todo `Range` que entra al árbol. Estas
## barras son indicadores, no controles: se las desconecta para que la vista en
## vivo no suene como si el jugador estuviera moviendo un valor.
static func silence_ui_tick(range_control: Range) -> void:
	for connection: Dictionary in range_control.value_changed.get_connections():
		var callable: Callable = connection["callable"]
		if callable.get_object() == UI:
			range_control.value_changed.disconnect(callable)
