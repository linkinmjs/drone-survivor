## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Hangar: ajustes del cuadro y curvas de rates (`docs/04` §4.7).
##
## Dos tarjetas a la izquierda y el gráfico a la derecha. Arriba, el **cuadro**: ángulo
## de la cámara FPV, peso en seco, peso de batería y campo de visión, cada uno con un
## `HSlider` y un `SpinBox` que comparten el mismo [Range] (`slider.share(spin)`), así
## que mover uno mueve el otro sin una sola línea de sincronización. Abajo, los
## **rates**: la curva y, por cada eje, `rc_rate`, `rate` y `expo`, con los rangos y las
## etiquetas que correspondan a la curva elegida. A la derecha, el [RateGraph] dibuja
## las tres curvas y su tasa máxima, y se rehace con cada cambio.
##
## La escritura en disco es una sola, al salir ([method _before_back]), que es lo que
## emite `QuadSettings.settings_updated` y llega al dron en caliente. Los dos botones de
## restablecer sí guardan en el acto, porque piden confirmación primero.
class_name QuadSettingsMenu
extends MenuScreen

## Campos del cuadro, en el orden de las filas de la escena. `property` es el miembro de
## `QuadSettings`; `key` la etiqueta, `help` el tooltip y `suffix` la unidad
## (`docs/04` §6). El sufijo es una clave de traducción como cualquier otro texto de la
## interfaz (`docs/00` §6): `SpinBox.suffix` no se traduce solo, así que lo resuelve
## [method _collect_frame_rows] con `tr()` y lo rehace `NOTIFICATION_TRANSLATION_CHANGED`.
const FRAME_FIELDS: Array[Dictionary] = [
	{"property": &"angle", "key": "QUAD_CAMERA_ANGLE", "help": "QUAD_HELP_CAMERA_ANGLE",
		"step": 1.0, "suffix": "QUAD_UNIT_DEG"},
	{"property": &"dry_weight", "key": "QUAD_DRY_WEIGHT", "help": "QUAD_HELP_DRY_WEIGHT",
		"step": 0.01, "suffix": "QUAD_UNIT_KG"},
	{"property": &"battery_weight", "key": "QUAD_BATTERY_WEIGHT",
		"help": "QUAD_HELP_BATTERY_WEIGHT", "step": 0.01, "suffix": "QUAD_UNIT_KG"},
	{"property": &"fov", "key": "QUAD_FOV", "help": "QUAD_HELP_FOV",
		"step": 1.0, "suffix": "QUAD_UNIT_DEG"},
]

## Nombre de cada eje dentro de las claves de control, en el orden de los `Vector3`
## de `QuadSettings` (`x` roll, `y` pitch, `z` yaw).
const AXIS_NAMES: Array[String] = ["ROLL", "PITCH", "YAW"]

## Clave de traducción del nombre de cada eje, en el mismo orden.
const AXIS_KEYS: Array[String] = ["QUAD_ROLL", "QUAD_PITCH", "QUAD_YAW"]

## Tooltip del encabezado de cada eje.
const AXIS_HELP: Array[String] = ["QUAD_HELP_ROLL", "QUAD_HELP_PITCH", "QUAD_HELP_YAW"]

## Orden en que se muestran los ejes: pitch primero, como en un configurador real.
const AXIS_ORDER: Array[int] = [ControlProfile.Axis.PITCH, ControlProfile.Axis.ROLL,
		ControlProfile.Axis.YAW]

## Sufijo de cada parámetro dentro de las claves de control y de ayuda.
const PARAM_NAMES: Array[String] = ["RC", "RATE", "EXPO"]

## Clave de traducción de cada parámetro por curva: `[curva][parámetro]`. El significado
## de los tres números cambia con la curva, así que también cambia su etiqueta.
const PARAM_KEYS: Array[Array] = [
	["QUAD_CENTER_RATE", "QUAD_MAX_RATE", "QUAD_EXPO"],  # ACTUAL
	["QUAD_RC_RATE", "QUAD_RATE", "QUAD_EXPO"],          # BETAFLIGHT
	["QUAD_RATE", "QUAD_ACRO_PLUS", "QUAD_EXPO"],        # RACEFLIGHT
	["QUAD_RC_RATE", "QUAD_RATE", "QUAD_RC_CURVE"],      # KISS
	["QUAD_RC_RATE", "QUAD_MAX_RATE", "QUAD_EXPO"],      # QUICKRATES
]

## Sufijo de la clave de ayuda de cada curva: `QUAD_HELP_<curva>_<parámetro>`.
const CURVE_HELP_NAMES: Array[String] = ["ACTUAL", "BETAFLIGHT", "RACEFLIGHT", "KISS",
		"QUICKRATES"]

## Nombre visible de cada curva en el `OptionButton`.
const CURVE_KEYS: Array[String] = ["QUAD_CURVE_ACTUAL", "QUAD_CURVE_BETAFLIGHT",
		"QUAD_CURVE_RACEFLIGHT", "QUAD_CURVE_KISS", "QUAD_CURVE_QUICKRATES"]

## Rango de cada parámetro por curva (`docs/04` §4.7). ACTUAL trabaja en decenas de
## grados por segundo; las otras cuatro usan las unidades enteras de su configurador.
const RATE_RANGES: Array[Array] = [
	[Vector2(1.0, 100.0), Vector2(0.0, 180.0), Vector2(0.0, 100.0)],  # ACTUAL
	[Vector2(1.0, 255.0), Vector2(0.0, 100.0), Vector2(0.0, 100.0)],  # BETAFLIGHT
	[Vector2(1.0, 255.0), Vector2(0.0, 100.0), Vector2(0.0, 100.0)],  # RACEFLIGHT
	[Vector2(1.0, 255.0), Vector2(0.0, 100.0), Vector2(0.0, 100.0)],  # KISS
	[Vector2(1.0, 255.0), Vector2(0.0, 100.0), Vector2(0.0, 100.0)],  # QUICKRATES
]

## Paso de los controles de rates.
const RATE_STEP: float = 1.0

var _frame_sliders: Dictionary[StringName, HSlider] = {}
var _frame_captions: Dictionary[StringName, Label] = {}

## `SpinBox` de cada fila del cuadro: su `suffix` no se traduce solo y hay que
## rehacerlo al cambiar de idioma ([method _refresh_frame_suffixes]).
var _frame_spins: Dictionary[StringName, SpinBox] = {}

## `[eje][parámetro]` → deslizador, con los tres ejes en el orden de los `Vector3`.
var _rate_sliders: Array[Array] = []

## `[eje][parámetro]` → etiqueta, para renombrarlas al cambiar de curva.
var _rate_captions: Array[Array] = []

## Controles expuestos a los checks por [method control_for].
var _controls: Dictionary[StringName, Control] = {}

var _syncing: bool = false
var _busy: bool = false

@onready var _graph: RateGraph = %Graph
@onready var _curve_option: OptionButton = %CurveOption


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_collect_frame_rows()
	_build_rate_rows()
	_fill_curve_option()
	_connect_controls()
	_apply_curve_layout()
	_sync()
	_graph.set_profile(QuadSettings.control_profile)
	bind_back_button(%ButtonBack as Button)
	initial_focus = _frame_sliders.get(&"angle", null) as Control
	var _discard := QuadSettings.settings_updated.connect(_on_settings_updated)
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_curve_option()
		_apply_curve_layout()
		_refresh_frame_suffixes()
		_sync()


## Guarda una sola vez al salir y avisa al dron (`docs/04` §4.7).
func _before_back() -> void:
	QuadSettings.save_quad_settings()


## Control asociado a una clave (`QUAD_CAMERA_ANGLE`, `QUAD_RATES_CURVE`,
## `QUAD_RATE_PITCH_RC`…), o `null` si no existe. Lo usan los checks.
func control_for(key: StringName) -> Control:
	return _controls.get(key, null)


## El gráfico de curvas, para que el check pueda comprobar que se redibuja.
func graph() -> RateGraph:
	return _graph


## Clave de control de un parámetro de rates.
static func rate_key(axis: int, param: int) -> StringName:
	return StringName("QUAD_RATE_%s_%s" % [AXIS_NAMES[axis], PARAM_NAMES[param]])


# --- Construcción ----------------------------------------------------------------------------

## Las filas del cuadro salen de la escena y se asocian a su miembro de `QuadSettings`
## por la meta `quad_key`, así el orden de los hijos no es un contrato.
func _collect_frame_rows() -> void:
	# Fijar `min_value` acota el valor por defecto del control y dispara `value_changed`:
	# sin la guarda, montar la pantalla pisaría la configuración del jugador.
	_syncing = true
	var rows: VBoxContainer = %FrameRows
	for field: Dictionary in FRAME_FIELDS:
		var property := StringName(field["property"])
		var row: HBoxContainer = null
		for child: Node in rows.get_children():
			if child.has_meta(&"quad_key") and StringName(child.get_meta(&"quad_key")) == property:
				row = child as HBoxContainer
				break
		if row == null:
			push_error("QuadSettingsMenu: falta la fila '%s' en quad_settings_menu.tscn" % property)
			continue
		var slider := row.get_node(^"Slider") as HSlider
		var spin := row.get_node(^"Spin") as SpinBox
		var limits := _frame_range(property)
		slider.min_value = limits.x
		slider.max_value = limits.y
		slider.step = float(field["step"])
		spin.suffix = tr(String(field["suffix"]))
		# Un solo `Range` para los dos controles: mover uno mueve el otro (`docs/04` §4.7).
		slider.share(spin)
		slider.set_meta(&"stick_value_control", true)
		spin.set_meta(&"stick_value_control", true)
		slider.tooltip_text = String(field["help"])
		spin.tooltip_text = String(field["help"])
		_frame_sliders[property] = slider
		_frame_spins[property] = spin
		_frame_captions[property] = row.get_node(^"Caption") as Label
		_controls[StringName(field["key"])] = slider
	_syncing = false


## Vuelve a traducir la unidad de cada `SpinBox` del cuadro. `SpinBox.suffix` es texto
## plano, no una clave que el control resuelva solo, así que hay que rehacerlo en cada
## `NOTIFICATION_TRANSLATION_CHANGED`.
func _refresh_frame_suffixes() -> void:
	for field: Dictionary in FRAME_FIELDS:
		var spin := _frame_spins.get(StringName(field["property"]), null) as SpinBox
		if spin != null:
			spin.suffix = tr(String(field["suffix"]))


## Arma los nueve controles de rates: tres ejes por `rc_rate`, `rate` y `expo`.
func _build_rate_rows() -> void:
	var rows: VBoxContainer = %RateRows
	_rate_sliders.clear()
	_rate_captions.clear()
	for _axis: int in 3:
		_rate_sliders.append([null, null, null])
		_rate_captions.append([null, null, null])
	for axis: int in AXIS_ORDER:
		var heading := Label.new()
		heading.name = "Heading%s" % AXIS_NAMES[axis].capitalize()
		heading.text = AXIS_KEYS[axis]
		heading.tooltip_text = AXIS_HELP[axis]
		heading.mouse_filter = Control.MOUSE_FILTER_PASS
		heading.theme_type_variation = &"ValueLabel"
		rows.add_child(heading)
		for param: int in PARAM_NAMES.size():
			_build_rate_row(rows, axis, param)


func _build_rate_row(rows: VBoxContainer, axis: int, param: int) -> void:
	var row := HBoxContainer.new()
	row.name = "Row%s%s" % [AXIS_NAMES[axis].capitalize(), PARAM_NAMES[param].capitalize()]
	row.add_theme_constant_override(&"separation", 18)
	rows.add_child(row)

	var caption := Label.new()
	caption.name = "Caption"
	caption.custom_minimum_size = Vector2(230.0, 0.0)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.custom_minimum_size = Vector2(260.0, 0.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.step = RATE_STEP
	slider.set_meta(&"stick_value_control", true)
	row.add_child(slider)

	var spin := SpinBox.new()
	spin.name = "Spin"
	spin.custom_minimum_size = Vector2(150.0, 0.0)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.set_meta(&"stick_value_control", true)
	row.add_child(spin)
	slider.share(spin)

	_rate_sliders[axis][param] = slider
	_rate_captions[axis][param] = caption
	_controls[rate_key(axis, param)] = slider


func _fill_curve_option() -> void:
	var selected := _curve_option.selected
	_curve_option.clear()
	for index: int in CURVE_KEYS.size():
		_curve_option.add_item(tr(CURVE_KEYS[index]), index)
	if selected >= 0 and selected < _curve_option.item_count:
		_curve_option.selected = selected


func _connect_controls() -> void:
	for field: Dictionary in FRAME_FIELDS:
		var property := StringName(field["property"])
		var slider: HSlider = _frame_sliders.get(property, null)
		if slider == null:
			continue
		var _discard := slider.value_changed.connect(_on_frame_changed.bind(property))
	for axis: int in 3:
		for param: int in PARAM_NAMES.size():
			var slider := _rate_sliders[axis][param] as HSlider
			var _discard := slider.value_changed.connect(_on_rate_changed.bind(axis, param))
	_curve_option.set_meta(&"stick_value_control", true)
	_curve_option.tooltip_text = "QUAD_HELP_RATES_CURVE"
	_controls[&"QUAD_RATES_CURVE"] = _curve_option
	var _discard := _curve_option.item_selected.connect(_on_curve_selected)

	var reset_quad := %ButtonResetQuad as Button
	var reset_rates := %ButtonResetRates as Button
	reset_quad.tooltip_text = "QUAD_HELP_RESET_QUAD"
	reset_rates.tooltip_text = "QUAD_HELP_RESET_RATES"
	_controls[&"QUAD_RESET_QUAD"] = reset_quad
	_controls[&"QUAD_RESET_RATES"] = reset_rates
	_discard = reset_quad.pressed.connect(_on_reset_quad)
	_discard = reset_rates.pressed.connect(_on_reset_rates)


func _frame_range(property: StringName) -> Vector2:
	match property:
		&"angle":
			return QuadSettings.ANGLE_RANGE
		&"dry_weight":
			return QuadSettings.DRY_WEIGHT_RANGE
		&"battery_weight":
			return QuadSettings.BATTERY_WEIGHT_RANGE
	return QuadSettings.FOV_RANGE


# --- Curva activa ----------------------------------------------------------------------------

## Pone en los nueve controles el rango, la etiqueta y el tooltip de la curva elegida.
##
## Corre con [member _syncing] puesto: cambiar `min_value` acota el valor del control y
## eso dispara `value_changed`, que sin la guarda escribiría el valor acotado en
## `QuadSettings` antes de que nadie haya tocado nada. Quien quiera recoger el recorte
## —el cambio de curva— llama después a [method _commit_rates].
func _apply_curve_layout() -> void:
	var was_syncing := _syncing
	_syncing = true
	var curve := clampi(int(QuadSettings.curve), 0, CURVE_KEYS.size() - 1)
	var ranges: Array = RATE_RANGES[curve]
	var keys: Array = PARAM_KEYS[curve]
	for axis: int in 3:
		for param: int in PARAM_NAMES.size():
			var slider := _rate_sliders[axis][param] as HSlider
			var limits: Vector2 = ranges[param]
			slider.min_value = limits.x
			slider.max_value = limits.y
			var help := "QUAD_HELP_%s_%s" % [CURVE_HELP_NAMES[curve], PARAM_NAMES[param]]
			slider.tooltip_text = help
			var spin := _rate_sliders[axis][param].get_parent().get_node(^"Spin") as SpinBox
			spin.tooltip_text = help
			var caption := _rate_captions[axis][param] as Label
			caption.text = String(keys[param])
			caption.tooltip_text = help
	for field: Dictionary in FRAME_FIELDS:
		var caption: Label = _frame_captions.get(StringName(field["property"]), null)
		if caption != null:
			caption.text = String(field["key"])
	_syncing = was_syncing


# --- Sincronización --------------------------------------------------------------------------

## Vuelca los valores de `QuadSettings` sobre los controles sin volver a escribirlos.
func _sync() -> void:
	if _syncing:
		return
	_syncing = true
	for field: Dictionary in FRAME_FIELDS:
		var property := StringName(field["property"])
		var slider: HSlider = _frame_sliders.get(property, null)
		if slider != null:
			slider.value = float(QuadSettings.get(property))
	_curve_option.selected = clampi(int(QuadSettings.curve), 0, CURVE_KEYS.size() - 1)
	for axis: int in 3:
		(_rate_sliders[axis][0] as HSlider).value = QuadSettings.rc_rate[axis]
		(_rate_sliders[axis][1] as HSlider).value = QuadSettings.rate[axis]
		(_rate_sliders[axis][2] as HSlider).value = QuadSettings.expo[axis]
	_syncing = false
	_refresh_graph()


## Escribe en `QuadSettings` lo que muestran los nueve controles. Se usa después de
## cambiar de curva, cuando el rango nuevo pudo acotar algún valor.
func _commit_rates() -> void:
	var rc := QuadSettings.rc_rate
	var rate := QuadSettings.rate
	var expo := QuadSettings.expo
	for axis: int in 3:
		rc[axis] = (_rate_sliders[axis][0] as HSlider).value
		rate[axis] = (_rate_sliders[axis][1] as HSlider).value
		expo[axis] = (_rate_sliders[axis][2] as HSlider).value
	QuadSettings.rc_rate = rc
	QuadSettings.rate = rate
	QuadSettings.expo = expo


func _refresh_graph() -> void:
	QuadSettings.rebuild_control_profile()
	_graph.set_profile(QuadSettings.control_profile)


# --- Manejadores -----------------------------------------------------------------------------

func _on_frame_changed(value: float, property: StringName) -> void:
	if _syncing:
		return
	QuadSettings.set(property, value)


func _on_rate_changed(value: float, axis: int, param: int) -> void:
	if _syncing:
		return
	match param:
		0:
			var rc := QuadSettings.rc_rate
			rc[axis] = value
			QuadSettings.rc_rate = rc
		1:
			var rate := QuadSettings.rate
			rate[axis] = value
			QuadSettings.rate = rate
		_:
			var expo := QuadSettings.expo
			expo[axis] = value
			QuadSettings.expo = expo
	_refresh_graph()


func _on_curve_selected(index: int) -> void:
	if _syncing:
		return
	QuadSettings.curve = clampi(index, 0, CURVE_KEYS.size() - 1) as ControlProfile.RateCurve
	_apply_curve_layout()
	_commit_rates()
	_sync()


func _on_settings_updated() -> void:
	_apply_curve_layout()
	_sync()


func _on_reset_quad() -> void:
	if _busy or UI.has_modal():
		return
	_busy = true
	if await UI.confirm("QUAD_RESET_QUAD_CONFIRM"):
		QuadSettings.reset_quad()
	_busy = false
	_refocus(_controls.get(&"QUAD_RESET_QUAD", null) as Button)


func _on_reset_rates() -> void:
	if _busy or UI.has_modal():
		return
	_busy = true
	if await UI.confirm("QUAD_RESET_RATES_CONFIRM"):
		QuadSettings.reset_rates()
	_busy = false
	_refocus(_controls.get(&"QUAD_RESET_RATES", null) as Button)


func _refocus(button: Button) -> void:
	if button == null or UI.is_using_mouse() or not button.is_visible_in_tree():
		return
	UI.mute_for(0.12)
	button.grab_focus()
