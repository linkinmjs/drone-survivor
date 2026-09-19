## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Página de ayuda (`docs/04` §4.8).
##
## Un único [RichTextLabel] con las siete secciones del juego —cómo se vuela, cómo se
## dispara, cómo funciona la energía, qué pasa con la ciudad, qué muestra el HUD y qué
## hace cada control— más la nota de créditos pendientes, y un botón que cambia el
## cuerpo por el texto de licencias del motor (`Engine.get_license_text()`) dentro de un
## [ScrollContainer].
##
## El texto se arma entero en código a partir de claves de traducción y se vuelve a
## armar con `NOTIFICATION_TRANSLATION_CHANGED`, así que cambiar de idioma desde el menú
## de opciones lo rehace sin reabrir la pantalla.
##
## Nota legal (`docs/00` §8): los créditos y las licencias completas de assets y fuentes
## se resuelven al final del proyecto. Hasta entonces esta página lo dice con la clave
## `HELP_CREDITS_PENDING` en vez de mostrar un `CREDITS.md` que todavía no existe.
class_name HelpPage
extends MenuScreen

## Secciones del cuerpo, en orden: `[clave del encabezado, clave del texto]`. Un
## encabezado vacío escribe el párrafo sin título, que es lo que quiere la introducción.
const SECTIONS: Array[Array] = [
	["", "HELP_INTRO"],
	["HELP_SECTION_FLIGHT", "HELP_FLIGHT"],
	["HELP_SECTION_COMBAT", "HELP_COMBAT"],
	["HELP_SECTION_ENERGY", "HELP_ENERGY"],
	["HELP_SECTION_CITY", "HELP_CITY"],
	["HELP_SECTION_HUD", "HELP_HUD"],
	["HELP_SECTION_CONTROLS", "HELP_CONTROLS"],
	["HELP_SECTION_CREDITS", "HELP_CREDITS_PENDING"],
]

## Texto del botón según lo que se esté mostrando.
const BUTTON_KEYS: Array[String] = ["HELP_LICENSES", "HELP_BACK_TO_HELP"]

var _showing_licenses: bool = false

@onready var _help_card: PanelContainer = %HelpCard
@onready var _help_text: RichTextLabel = %HelpText
@onready var _license_card: PanelContainer = %LicenseCard
@onready var _license_text: Label = %LicenseText
@onready var _button_licenses: Button = %ButtonLicenses


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_text()
	var _discard := _button_licenses.pressed.connect(_on_licenses_pressed)
	bind_back_button(%ButtonBack as Button)
	initial_focus = _button_licenses
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build_text()
		_button_licenses.text = BUTTON_KEYS[1 if _showing_licenses else 0]


## Verdadero mientras se está mostrando el texto de licencias del motor.
func showing_licenses() -> bool:
	return _showing_licenses


## Cantidad de caracteres del texto de licencias ya cargado. Lo mira el check.
func license_length() -> int:
	return _license_text.text.length()


## El cuerpo de la ayuda, ya traducido y sin etiquetas. Lo mira el check.
func help_text() -> String:
	return _help_text.get_parsed_text()


# --- Construcción ----------------------------------------------------------------------------

func _build_text() -> void:
	var blocks: Array[String] = []
	for section: Array in SECTIONS:
		var heading := String(section[0])
		var body := String(section[1])
		if heading.is_empty():
			blocks.append(tr(body))
			continue
		blocks.append("[b]%s[/b]\n%s" % [tr(heading), tr(body)])
	_help_text.text = "\n\n".join(blocks)


# --- Licencias -------------------------------------------------------------------------------

func _on_licenses_pressed() -> void:
	_showing_licenses = not _showing_licenses
	if _showing_licenses and _license_text.text.is_empty():
		# El texto del motor no se traduce ni cambia: se carga una sola vez.
		_license_text.text = Engine.get_license_text()
	_help_card.visible = not _showing_licenses
	_license_card.visible = _showing_licenses
	_button_licenses.text = BUTTON_KEYS[1 if _showing_licenses else 0]
