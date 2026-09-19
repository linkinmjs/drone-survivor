## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Asistente de calibración de los cuatro ejes de vuelo (`docs/04` §4.6).
##
## Catorce pasos: primero las cuatro esquinas —para saber **cuáles** de los ocho
## ejes físicos son los dos sticks—, después el reposo, y a continuación los tres
## pasos de cada eje de vuelo (extremo, extremo contrario y centro) en el orden
## acelerador, yaw, pitch, roll.
##
## Cada paso se confirma solo: cuando la condición del paso se cumple y el valor
## se queda quieto durante [constant HOLD_SECONDS], el asistente lo da por bueno
## y avanza. «Siguiente» hace lo mismo a mano, «Omitir» pasa sin registrar y
## «Cancelar» sale sin guardar nada.
##
## **Ejes invertidos**: el asistente no supone que «arriba» sea positivo. Un
## acelerador de mando estándar da −1.0 empujado hacia arriba; el paso registra
## ese valor tal cual y la inversión sale de comparar los dos extremos, de modo
## que [method Controls.get_flight_input] devuelva +1.0 con el stick arriba
## venga como venga cableado el mando.
##
## Mientras el asistente corre, `StickNavigation.suspended` queda en `true`: los
## mismos sticks que se están midiendo no pueden estar navegando el menú.
class_name CalibrationMenu
extends MenuScreen

## Qué mide cada paso.
enum StepKind {
	CORNERS, ## Detecta los cuatro ejes con mayor recorrido.
	CENTERS, ## Registra el reposo de los cuatro ejes detectados.
	MAX,     ## Primer extremo de un eje de vuelo (arriba / derecha).
	MIN,     ## Extremo contrario (abajo / izquierda).
	CENTER,  ## Reposo de ese eje.
}

## Los catorce pasos: clave de traducción, qué mide y sobre qué eje de vuelo
## (`docs/04` §4.6).
const STEPS: Array[Array] = [
	["CAL_STEP_CORNERS", StepKind.CORNERS, &""],
	["CAL_STEP_CENTER", StepKind.CENTERS, &""],
	["CAL_STEP_THROTTLE_UP", StepKind.MAX, &"throttle"],
	["CAL_STEP_THROTTLE_DOWN", StepKind.MIN, &"throttle"],
	["CAL_STEP_THROTTLE_CENTER", StepKind.CENTER, &"throttle"],
	["CAL_STEP_YAW_RIGHT", StepKind.MAX, &"yaw"],
	["CAL_STEP_YAW_LEFT", StepKind.MIN, &"yaw"],
	["CAL_STEP_YAW_CENTER", StepKind.CENTER, &"yaw"],
	["CAL_STEP_PITCH_UP", StepKind.MAX, &"pitch"],
	["CAL_STEP_PITCH_DOWN", StepKind.MIN, &"pitch"],
	["CAL_STEP_PITCH_CENTER", StepKind.CENTER, &"pitch"],
	["CAL_STEP_ROLL_RIGHT", StepKind.MAX, &"roll"],
	["CAL_STEP_ROLL_LEFT", StepKind.MIN, &"roll"],
	["CAL_STEP_ROLL_CENTER", StepKind.CENTER, &"roll"],
]

## Ejes físicos que el asistente vigila.
const AXIS_COUNT: int = 8

## Cuántos ejes busca el primer paso: los cuatro de los dos sticks.
const FLIGHT_AXIS_COUNT: int = 4

## Cuánto hay que sostener la condición de un paso para que se confirme sola.
const HOLD_SECONDS: float = 0.4

## Deflexión mínima, medida desde el reposo, para dar por buena una punta.
const TRIGGER: float = 0.5

## Variación por debajo de la cual un eje cuenta como quieto.
const STABLE_EPSILON: float = 0.05

## Recorrido mínimo —de punta a punta— para que el primer paso considere que un
## eje es uno de los cuatro de los sticks.
const CORNER_TRAVEL: float = 1.0

## Cuánto se muestra `CAL_DONE` antes de volver al menú de controles.
const DONE_SECONDS: float = 0.5

var _step: int = 0
var _hold: float = 0.0
var _running: bool = false
var _saved: bool = false
var _device: int = 0
var _sticks_suspended: bool = false
var _restored: bool = true

## Ejes físicos detectados en el primer paso; vacío quiere decir «todavía todos».
var _candidates: Array[int] = []

## Eje físico que resultó ser cada eje de vuelo.
var _assigned: Dictionary[StringName, int] = {}

## Muestras crudas de cada eje de vuelo: `{hi, lo, center, has_*}`.
var _samples: Dictionary[StringName, Dictionary] = {}

## Reposo de cada eje físico medido en el segundo paso.
var _step_centers: Dictionary[int, float] = {}

var _travel_min: PackedFloat32Array = PackedFloat32Array()
var _travel_max: PackedFloat32Array = PackedFloat32Array()
var _stable_ref: PackedFloat32Array = PackedFloat32Array()
var _bars: Array[GUIControllerAxis] = []
var _captions: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_device = maxi(Controls.active_device, 0)
	_reset_state()
	_build_axis_grid()
	var _discard := (%ButtonNext as Button).pressed.connect(_on_next_pressed)
	_discard = (%ButtonSkip as Button).pressed.connect(_on_skip_pressed)
	# La barra de progreso es un indicador: no debe sonar como un deslizador.
	GUIControllerAxis.silence_ui_tick(%Progress as ProgressBar)
	bind_back_button(%ButtonCancel)
	initial_focus = %ButtonNext
	_suspend_sticks()
	_refresh_step()
	super()
	_running = true


func _exit_tree() -> void:
	_restore_sticks()
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_step()


func _process(delta: float) -> void:
	if not _running:
		return
	_read_axes()
	if _step_ready():
		_hold += delta
		if _hold >= HOLD_SECONDS:
			_commit_step()
			_advance()
	else:
		_hold = 0.0


# --- Interfaz pública ------------------------------------------------------------------------

## Índice del paso en curso, de 0 a 13. Lo usan los checks para avanzar en orden.
func current_step() -> int:
	return _step


## Verdadero mientras el asistente está midiendo.
func is_running() -> bool:
	return _running


## Verdadero si el asistente llegó a guardar la calibración.
func has_saved() -> bool:
	return _saved


## Eje físico asignado a un eje de vuelo, o −1 si ese paso se omitió.
func assigned_axis(axis_name: StringName) -> int:
	return int(_assigned.get(axis_name, -1))


# --- Estado ----------------------------------------------------------------------------------

func _reset_state() -> void:
	_step = 0
	_hold = 0.0
	_saved = false
	_candidates.clear()
	_assigned.clear()
	_samples.clear()
	_step_centers.clear()
	_travel_min = PackedFloat32Array()
	_travel_max = PackedFloat32Array()
	_stable_ref = PackedFloat32Array()
	for _axis: int in AXIS_COUNT:
		# Centinelas al revés: la primera lectura fija los dos extremos.
		var _discard := _travel_min.append(1.0)
		_discard = _travel_max.append(-1.0)
		_discard = _stable_ref.append(0.0)
	for axis_name: StringName in Controls.FLIGHT_AXES:
		_samples[axis_name] = {
			"hi": 0.0, "lo": 0.0, "center": 0.0,
			"has_hi": false, "has_lo": false, "has_center": false,
		}


## Deflexión cruda de un eje físico del mando activo.
func _raw(axis: int) -> float:
	return Input.get_joy_axis(_device, axis as JoyAxis)


## Ejes que el asistente vigila en este momento: los cuatro detectados, o los
## ocho mientras el primer paso no haya terminado.
func _monitored() -> Array[int]:
	if not _candidates.is_empty():
		return _candidates
	var all: Array[int] = []
	for axis: int in AXIS_COUNT:
		all.append(axis)
	return all


## Reposo conocido de un eje físico; 0.0 mientras no se haya medido.
func _center_of(axis: int) -> float:
	return float(_step_centers.get(axis, 0.0))


func _read_axes() -> void:
	for axis: int in AXIS_COUNT:
		var value := _raw(axis)
		_travel_min[axis] = minf(_travel_min[axis], value)
		_travel_max[axis] = maxf(_travel_max[axis], value)
		if axis < _bars.size():
			_bars[axis].set_axis_value(value)


# --- Condición de cada paso ------------------------------------------------------------------

func _step_ready() -> bool:
	var entry: Array = STEPS[_step]
	var kind := int(entry[1])
	var axis_name := StringName(entry[2])
	# La estabilidad se evalúa siempre, para que la referencia no se quede vieja.
	var steady := _stable(_monitored())
	match kind:
		StepKind.CORNERS:
			return _corner_axes().size() >= FLIGHT_AXIS_COUNT
		StepKind.CENTERS:
			return steady
		StepKind.MAX, StepKind.MIN:
			return steady and _extreme_axis(axis_name, kind) >= 0
		StepKind.CENTER:
			return steady and _assigned.has(axis_name)
	return false


## Devuelve `false` en cuanto alguno de los ejes vigilados se movió más de
## [constant STABLE_EPSILON] desde la última lectura, y actualiza la referencia.
func _stable(axes: Array[int]) -> bool:
	var steady := true
	for axis: int in axes:
		var value := _raw(axis)
		if absf(value - _stable_ref[axis]) > STABLE_EPSILON:
			_stable_ref[axis] = value
			steady = false
	return steady


## Los cuatro ejes con mayor recorrido acumulado, de mayor a menor.
func _corner_axes() -> Array[int]:
	var scored: Array[Vector2] = []
	for axis: int in AXIS_COUNT:
		var travel := _travel_max[axis] - _travel_min[axis]
		if travel >= CORNER_TRAVEL:
			scored.append(Vector2(travel, float(axis)))
	scored.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var result: Array[int] = []
	for index: int in mini(scored.size(), FLIGHT_AXIS_COUNT):
		result.append(int(scored[index].y))
	result.sort()
	return result


## Eje físico que está desviado a propósito para este paso, o −1 si ninguno.
##
## En el paso `MAX` es el candidato con mayor deflexión desde el reposo; en el
## `MIN`, ese mismo eje pero movido hacia el lado contrario. No se exige que el
## primer extremo sea el positivo: un eje invertido se calibra igual.
func _extreme_axis(axis_name: StringName, kind: int) -> int:
	var known := int(_assigned.get(axis_name, -1))
	var pool: Array[int] = _monitored()
	if known >= 0:
		pool = [known]
	var best := -1
	var best_delta := 0.0
	for axis: int in pool:
		var delta := _raw(axis) - _center_of(axis)
		if absf(delta) < TRIGGER:
			continue
		if kind == StepKind.MIN and not _is_opposite(axis_name, delta):
			continue
		if absf(delta) > best_delta:
			best_delta = absf(delta)
			best = axis
	return best


## Verdadero si [param delta] apunta al lado contrario del extremo ya registrado.
func _is_opposite(axis_name: StringName, delta: float) -> bool:
	var sample: Dictionary = _samples[axis_name]
	if not bool(sample["has_hi"]):
		return true
	var axis := int(_assigned.get(axis_name, -1))
	var reference := float(sample["hi"]) - _center_of(axis)
	return signf(delta) != signf(reference)


# --- Avance ----------------------------------------------------------------------------------

## Registra lo que mide el paso actual. Si el paso no tiene una lectura válida
## —porque el jugador pulsó «Siguiente» sin mover nada— no escribe nada.
func _commit_step() -> void:
	var entry: Array = STEPS[_step]
	var kind := int(entry[1])
	var axis_name := StringName(entry[2])
	match kind:
		StepKind.CORNERS:
			var detected := _corner_axes()
			if not detected.is_empty():
				_candidates = detected
		StepKind.CENTERS:
			for axis: int in _monitored():
				_step_centers[axis] = _raw(axis)
		StepKind.MAX, StepKind.MIN:
			var axis := _extreme_axis(axis_name, kind)
			if axis < 0:
				return
			_assigned[axis_name] = axis
			var sample: Dictionary = _samples[axis_name]
			if kind == StepKind.MAX:
				sample["hi"] = _raw(axis)
				sample["has_hi"] = true
			else:
				sample["lo"] = _raw(axis)
				sample["has_lo"] = true
		StepKind.CENTER:
			var center_axis := int(_assigned.get(axis_name, -1))
			if center_axis < 0:
				return
			var center_sample: Dictionary = _samples[axis_name]
			center_sample["center"] = _raw(center_axis)
			center_sample["has_center"] = true


func _advance() -> void:
	_hold = 0.0
	_step += 1
	if _step >= STEPS.size():
		_step = STEPS.size()
		_finish()
		return
	_reset_stability()
	_refresh_step()


## Al entrar a un paso nuevo la referencia de estabilidad arranca en la lectura
## actual: así un stick que ya estaba quieto no arrastra la medición anterior.
func _reset_stability() -> void:
	for axis: int in AXIS_COUNT:
		_stable_ref[axis] = _raw(axis)


func _on_next_pressed() -> void:
	if not _running:
		return
	_commit_step()
	_advance()


func _on_skip_pressed() -> void:
	if not _running:
		return
	_advance()


# --- Guardado --------------------------------------------------------------------------------

func _finish() -> void:
	_running = false
	_save()
	(%StepLabel as Label).text = "CAL_DONE"
	(%StepCount as Label).text = "%d / %d" % [STEPS.size(), STEPS.size()]
	(%Progress as ProgressBar).value = float(STEPS.size())
	(%Hint as Label).text = "CAL_SUCCESS" if _saved else "CAL_SKIPPED"
	UI.play("click")
	await get_tree().create_timer(DONE_SECONDS).timeout
	if is_inside_tree():
		request_back()


## Escribe la calibración de cada eje que haya quedado completo y reconstruye el
## `InputMap`. Un eje al que le falte alguna punta conserva lo que ya tenía.
func _save() -> void:
	for axis_name: StringName in Controls.FLIGHT_AXES:
		var axis := int(_assigned.get(axis_name, -1))
		if axis < 0:
			continue
		var sample: Dictionary = _samples[axis_name]
		if not bool(sample["has_hi"]) or not bool(sample["has_lo"]):
			continue
		var hi := float(sample["hi"])
		var lo := float(sample["lo"])
		var center := float(sample["center"]) if bool(sample["has_center"]) else _center_of(axis)
		# `hi` es la punta de «arriba / derecha». Si quedó por debajo de la otra,
		# el eje está cableado al revés y hay que invertirlo.
		Controls.save_axis_calibration(axis_name, axis, minf(hi, lo), center, maxf(hi, lo),
				hi < lo)
		_saved = true
	# `save_axis_calibration()` ya reconstruye, pero `docs/04` §4.6 pide dejarlo
	# explícito: al terminar el asistente el mapa refleja los cuatro ejes.
	Controls.rebuild_input_map()


func _before_back() -> void:
	_running = false
	_restore_sticks()


# --- Navegación por sticks -------------------------------------------------------------------

func _suspend_sticks() -> void:
	_sticks_suspended = StickNavigation.suspended
	StickNavigation.suspended = true
	_restored = false


func _restore_sticks() -> void:
	if _restored:
		return
	_restored = true
	StickNavigation.suspended = _sticks_suspended


# --- Interfaz --------------------------------------------------------------------------------

func _refresh_step() -> void:
	var index := clampi(_step, 0, STEPS.size() - 1)
	var entry: Array = STEPS[index]
	(%StepLabel as Label).text = String(entry[0])
	(%StepCount as Label).text = "%d / %d" % [index + 1, STEPS.size()]
	(%Progress as ProgressBar).max_value = float(STEPS.size())
	(%Progress as ProgressBar).value = float(index)
	(%Hint as Label).text = "CAL_HINT" if Controls.has_joypad() else "CTRL_NO_CONTROLLER"
	for axis: int in _captions.size():
		_captions[axis].text = tr("CTRL_AXIS_N") % axis


## Las ocho barras de eje, para que el jugador vea qué se está moviendo mientras
## responde a cada paso. Son los mismos widgets del menú de controles.
func _build_axis_grid() -> void:
	var grid := %AxisGrid as GridContainer
	for axis: int in AXIS_COUNT:
		var caption := Label.new()
		caption.theme_type_variation = &"CaptionLabel"
		caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(caption)
		_captions.append(caption)
		var bar := GUIControllerAxis.new()
		bar.setup(axis)
		grid.add_child(bar)
		_bars.append(bar)
