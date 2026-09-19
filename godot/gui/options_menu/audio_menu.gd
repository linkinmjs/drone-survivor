## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Audio (`docs/04` §4.4).
##
## Un deslizador de 0 a 100 % con su valor numérico por cada uno de los siete buses de
## `default_bus_layout.tres` —general, motores, armas, enemigos, ciudad, interfaz y
## música— y un interruptor de silencio general.
##
## Mover un deslizador aplica el volumen en el acto con `Audio.set_volume()`; el
## archivo se escribe al soltarlo (o de inmediato si el cambio vino del teclado, del
## mando o de los sticks, donde no hay arrastre). El `tick` de la interfaz lo agrega
## `UI` solo, porque escucha `value_changed` de todo `Range`.
##
## Las filas salen de la escena y se asocian a su bus por la meta `audio_bus`, de modo
## que el orden de los hijos no es un contrato.
class_name AudioMenu
extends MenuScreen

## Clave de traducción de cada bus, en el orden en que los lista `Audio.BUSES`.
const BUS_KEYS: Dictionary[StringName, String] = {
	&"Master": "AUD_MASTER",
	&"Motors": "AUD_MOTORS",
	&"Weapons": "AUD_WEAPONS",
	&"Enemies": "AUD_ENEMIES",
	&"City": "AUD_CITY",
	&"UI": "AUD_UI",
	&"Music": "AUD_MUSIC",
}

## Deslizador de cada bus.
var _sliders: Dictionary[StringName, HSlider] = {}

## Etiqueta numérica de cada bus.
var _values: Dictionary[StringName, Label] = {}

## Controles expuestos a los checks por [method control_for].
var _controls: Dictionary[StringName, Control] = {}

## Buses cuyo deslizador está siendo arrastrado en este momento.
var _dragging: Dictionary[StringName, bool] = {}

var _syncing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_collect_rows()
	_connect_controls()
	_sync()
	bind_back_button(%ButtonBack)
	initial_focus = _sliders.get(&"Master", null)
	var _discard := Audio.audio_settings_updated.connect(_on_audio_updated)
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_sync()


## Control asociado a una clave de ajuste (`AUD_MASTER` … `AUD_MUSIC`, `AUD_MUTE`),
## o `null` si no existe. Lo usan los checks.
func control_for(key: StringName) -> Control:
	return _controls.get(key, null)


# --- Construcción ----------------------------------------------------------------------------

func _collect_rows() -> void:
	for child: Node in (%Rows as VBoxContainer).get_children():
		if not child.has_meta(&"audio_bus"):
			continue
		var bus := StringName(child.get_meta(&"audio_bus"))
		_sliders[bus] = child.get_node(^"Slider") as HSlider
		_values[bus] = child.get_node(^"Value") as Label
		_dragging[bus] = false
	for bus: StringName in Audio.BUSES:
		if not _sliders.has(bus):
			push_error("Falta la fila del bus de audio '%s' en audio_menu.tscn" % bus)


func _connect_controls() -> void:
	for bus: StringName in _sliders:
		var slider := _sliders[bus]
		slider.set_meta(&"stick_value_control", true)
		_controls[StringName(BUS_KEYS.get(bus, String(bus)))] = slider
		var _discard := slider.value_changed.connect(_on_volume_changed.bind(bus))
		_discard = slider.drag_started.connect(_on_drag_started.bind(bus))
		_discard = slider.drag_ended.connect(_on_drag_ended.bind(bus))
	var mute := %MuteCheck as CheckButton
	mute.set_meta(&"stick_value_control", true)
	_controls[&"AUD_MUTE"] = mute
	var _discard := mute.toggled.connect(_on_mute_toggled)


# --- Sincronización --------------------------------------------------------------------------

## Vuelca los volúmenes de `Audio` sobre los controles sin volver a guardarlos.
func _sync() -> void:
	if _syncing:
		return
	_syncing = true
	for bus: StringName in _sliders:
		var percent := roundf(Audio.get_volume(bus) * 100.0)
		_sliders[bus].value = percent
		_values[bus].text = tr("UI_PERCENT") % int(percent)
	(%MuteCheck as CheckButton).button_pressed = Audio.muted
	_syncing = false


func _on_audio_updated() -> void:
	_sync()


# --- Manejadores -----------------------------------------------------------------------------

func _on_volume_changed(value: float, bus: StringName) -> void:
	if _syncing:
		return
	Audio.set_volume(bus, clampf(value / 100.0, 0.0, 1.0))
	_values[bus].text = tr("UI_PERCENT") % int(roundf(value))
	if not bool(_dragging.get(bus, false)):
		Audio.save_audio_settings()


func _on_drag_started(bus: StringName) -> void:
	_dragging[bus] = true


func _on_drag_ended(value_changed: bool, bus: StringName) -> void:
	_dragging[bus] = false
	if value_changed:
		Audio.save_audio_settings()


func _on_mute_toggled(pressed: bool) -> void:
	if _syncing:
		return
	Audio.set_muted(pressed)
	Audio.save_audio_settings()
