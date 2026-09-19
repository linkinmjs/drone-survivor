## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Fila de una acción asignable en el menú de controles (`docs/04` §4.5).
##
## A la izquierda la etiqueta de la acción, a la derecha su binding actual
## escrito con `CTRL_BOUND_BUTTON`, `CTRL_BOUND_AXIS` o `CTRL_UNBOUND`. La fila
## entera es un `Button` con la variación `RowPanel` del tema: se enfoca con el
## teclado, el mando y los sticks, y al activarla el menú abre el [BindingPopup].
##
## La fila nunca escribe en `Controls`: solo avisa con [signal clicked] y vuelve
## a leer la acción cuando le piden [method refresh]. Quien decide qué se guarda
## es el menú, después de que el jugador confirme en el popup.
class_name GUIControllerBinding
extends Button

## Se emite al activar la fila, con el nombre de la acción del `InputMap`.
signal clicked(action_name: StringName)

## Se emite cada vez que la fila vuelve a dibujar el binding que muestra.
signal binding_updated(action_name: StringName)

## Alto mínimo de la fila, para que el foco se vea sin apretar el texto.
const ROW_HEIGHT: int = 44

## Separación entre la etiqueta y el valor, en píxeles.
const ROW_PADDING: int = 14

## Nombre de la acción del `InputMap` que representa la fila.
var action_name: StringName = &""

## Clave de traducción de la etiqueta de la acción.
var label_key: String = ""

var _label: Label = null
var _value: Label = null


func _ready() -> void:
	theme_type_variation = &"RowPanel"
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# El texto propio del botón queda vacío: las dos etiquetas de adentro son las
	# que se alinean a los bordes de la fila.
	text = ""
	_build_rows()
	var _discard := pressed.connect(_on_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh(Controls.get_action(action_name))


## Ata la fila a una acción y dibuja su binding. Se puede llamar antes o después
## de agregar la fila al árbol: el contenido se construye una sola vez.
func setup(action: ControllerAction) -> void:
	if action == null:
		return
	action_name = action.action_name
	label_key = action.label_key
	_build_rows()
	_label.text = label_key
	refresh(action)


## Vuelve a escribir el binding que muestra la fila.
func refresh(action: ControllerAction) -> void:
	if _value == null:
		return
	_value.text = describe(action)
	binding_updated.emit(action_name)


## Texto que muestra la fila para [param action], ya traducido.
##
## `CTRL_BOUND_BUTTON` lleva el índice del botón, `CTRL_BOUND_AXIS` el del eje
## más los dos extremos de la banda, y una acción sin atar dice `CTRL_UNBOUND`
## (`docs/04` §6). Es estática porque también la usan el popup y los checks.
static func describe(action: ControllerAction) -> String:
	if action == null or not action.bound:
		return String(TranslationServer.translate("CTRL_UNBOUND"))
	if action.type == ControllerAction.Type.AXIS:
		return String(TranslationServer.translate("CTRL_BOUND_AXIS")) \
				% [action.axis, action.axis_min, action.axis_max]
	return String(TranslationServer.translate("CTRL_BOUND_BUTTON")) % action.button


## El contenido va dentro de un `MarginContainer` que cubre toda la fila y deja
## pasar el ratón, de modo que el botón siga recibiendo los clics y el orden de
## las dos etiquetas lo resuelva un contenedor y no coordenadas a mano.
func _build_rows() -> void:
	if _label != null:
		return
	var margins := MarginContainer.new()
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margins.add_theme_constant_override(StringName("margin_" + side), ROW_PADDING)
	add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", ROW_PADDING)
	margins.add_child(row)

	_label = Label.new()
	_label.text = label_key
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)

	_value = Label.new()
	_value.theme_type_variation = &"ValueLabel"
	_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# El texto ya viene traducido y formateado por `describe()`.
	_value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(_value)


func _on_pressed() -> void:
	clicked.emit(action_name)
