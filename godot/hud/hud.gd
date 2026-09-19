## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## HUD de vuelo del dron (`docs/12` §2).
##
## Es un [Control] a pantalla completa que vive en la **capa 0** del canvas, colgado
## del `DroneRig` como hermano del `Drone` (`docs/03` §8, `docs/12` §1.1). Un `Control`
## bajo un [Node3D] se dibuja igual en el canvas por defecto de la viewport, que es
## exactamente lo que se quiere: queda por encima del compuesto del ojo de pez (capa
## −2) y **fuera** de sus `SubViewport`, así que no se deforma con la imagen (riesgo 1
## de `docs/12` §10).
##
## ## El HUD no observa al dron
##
## No hay señales del bus acá ni búsquedas por grupo: el rig lo alimenta una vez por
## frame de física con [method update_data] (`docs/12` §2.2). Eso deja el componente
## probable sin dron —`preview_mode` y los checks— y hace que la única fuente de
## verdad de las unidades sea la tabla de §2.2: ángulos en radianes, rpm absolutas,
## sticks ya con curvas y zona muerta.
##
## ## Dos ritmos en el mismo nodo (`docs/12` §2.3)
##
## - **Continuos** (horizonte, escalera, retículo, cintas, sticks, RPM): valor
##   instantáneo, cada frame. Son los que transmiten sensación de vuelo.
## - **Numéricos** ([HUDReadouts] y el rumbo en grados): promedio **ponderado por
##   tiempo** que se publica a `1/fps`, con `fps` de `GameSettings.hud_config`. Ponderar
##   por `dt` y no promediar muestras mantiene la lectura correcta aunque el paso de
##   física varíe (`Engine.time_scale` de los bancos, hipos del motor).
##
## El rumbo se promedia como **vector** (`cos`/`sin` acumulados y `atan2` al publicar)
## y no como número: promediar 359° y 1° daría 180°, o sea el sur.
##
## Los numéricos además solo piden redibujo **cuando publican**, no cada frame: es la
## mitigación del riesgo 5 de `docs/12` §10 (presupuesto de `_draw()`).
##
## ## Escala del marco
##
## Los componentes procedurales están dibujados en píxeles contra un lienzo de
## [constant MIN_LAYOUT_SIZE]. Todos cuelgan de un [Control] intermedio, `Frame`, que
## se escala para entrar en el espacio disponible **sin agrandar nunca**: a 960×540 o
## más, factor 1 y el HUD es un `PRESET_FULL_RECT` literal como pide §2; en el panel de
## vista previa del menú de HUD (`docs/04` §4.2), que mide bastante menos, el mismo
## árbol se reduce y sigue siendo legible. Que la escala dependa del tamaño y no de
## [member preview_mode] es lo que permite capturar el HUD del juego con
## `preview_mode` encendido (`docs/12` §9.1 fila 5) sin que encoja.
##
## ## Qué se puede apagar
##
## [enum Component] tiene **12** entradas y `hud_config` **11 bools**: `STATUS` no es
## configurable porque los mensajes de armado se ven siempre (`docs/12` §2.4). Está en
## el enum para que [method show_component] pueda esconderlo en el modo cinemático y en
## las capturas, y eso es todo.
class_name FlightHUD
extends Control

## Los 12 componentes que [method show_component] sabe encender y apagar
## (`docs/12` §2.4). `STATUS` es el único sin bool en `hud_config`.
enum Component {CROSSHAIR, STATUS, HEADING, SPEED, ALTITUDE, LADDER,
		HORIZON, STICKS, RPM, FLIGHT_MODE, REC, SIDE_TAPES}

## Lienzo de referencia de los componentes procedurales, en píxeles. Por debajo de
## esto el marco se reduce; por encima no se agranda.
##
## No es un número redondo cualquiera: las cintas laterales se dibujan a 320 px del
## centro y 270 px de alto ([HUDSideTapes]), así que con 960×540 rozaban el borde y se
## comían el sitio de los números. 1280×720 deja margen a los dos lados y sigue
## entrando entero en una captura de 960×540 con factor 0.75.
const MIN_LAYOUT_SIZE: Vector2 = Vector2(1280.0, 720.0)

## Clave de `hud_config` de cada componente configurable (`docs/12` §2.4). `STATUS` no
## está: no tiene interruptor.
const CONFIG_KEYS: Dictionary[int, String] = {
	Component.CROSSHAIR: "crosshair",
	Component.HEADING: "heading",
	Component.SPEED: "speed",
	Component.ALTITUDE: "altitude",
	Component.LADDER: "ladder",
	Component.HORIZON: "horizon",
	Component.STICKS: "sticks",
	Component.RPM: "rpm",
	Component.FLIGHT_MODE: "flight_mode",
	Component.REC: "rec",
	Component.SIDE_TAPES: "side_tapes",
}

## Clave de traducción del badge para cada modo de vuelo de `docs/03` §3.2.
const MODE_KEYS: Dictionary[String, String] = {
	"acro": "HUD_MODE_ACRO",
	"horizon": "HUD_MODE_HORIZON",
	"turtle": "HUD_MODE_TURTLE",
	"recover": "HUD_MODE_RECOVER",
}

## Modo de vuelo que el sistema **impone** y que por eso parpadea en el badge
## (`docs/12` §2.6).
const BLINKING_MODE: String = "recover"

## Clave de traducción de cada motivo de `Drone.arm_failed` (`docs/03` §3.3).
const ARM_FAILED_KEYS: Dictionary[String, String] = {
	"ERR_ARM_THROTTLE_HIGH": "HUD_ARM_FAILED_THROTTLE",
	"ERR_ARM_RECOVERING": "HUD_ARM_FAILED_RECOVER",
	"ERR_ARM_NO_ENERGY": "HUD_ARM_FAILED_ENERGY",
}

## Mensaje de armado con éxito.
const ARMED_KEY: String = "HUD_STATUS_ARMED"

## Texto persistente mientras el dron esté desarmado.
const DISARMED_KEY: String = "HUD_STATUS_DISARMED"

## Color del mensaje de armado (`SUCCESS` de la paleta, aclarado para que se lea sobre
## el video de la cámara).
const COLOR_ARMED: Color = Color(0.36, 0.86, 0.60, 1.0)

## Color del texto persistente de desarmado (`TEXT_DIM` sobre video).
const COLOR_DISARMED: Color = Color(1.0, 1.0, 1.0, 0.75)

## Color de un fallo de armado (`DANGER` de la paleta, aclarado igual que el verde).
const COLOR_ARM_FAILED: Color = Color(0.98, 0.42, 0.36, 1.0)

## Frecuencia de publicación de los numéricos cuando `hud_config` no trae `fps`
## (`docs/12` §2.3 y §8).
const DEFAULT_FPS: int = 10

## Modos del horizonte artificial (`docs/12` §2.4). El primero es el de respaldo.
const HORIZON_MODES: Array[String] = ["camera", "attitude"]

# --- Generador de `preview_mode` (`docs/12` §2.5) ---------------------------------------------

## Amplitud del barrido de cabeceo de la vista previa, en grados.
const PREVIEW_PITCH_DEG: float = 25.0

## Amplitud del barrido de alabeo de la vista previa, en grados.
const PREVIEW_ROLL_DEG: float = 35.0

## Velocidad de guiñada de la vista previa, en grados por segundo.
const PREVIEW_HEADING_RATE: float = 12.0

## Altura media de la vista previa, en metros.
const PREVIEW_ALTITUDE: float = 40.0

## Amplitud de la oscilación de altura de la vista previa, en metros.
const PREVIEW_ALTITUDE_SWING: float = 15.0

## Frecuencia angular de la oscilación de altura, en rad/s. La velocidad vertical de
## la vista previa es su derivada exacta, para que los dos números sean coherentes.
const PREVIEW_ALTITUDE_OMEGA: float = 0.31

## Velocidad máxima de la vista previa, en km/h.
const PREVIEW_SPEED_MAX: float = 90.0

## Fase en la que arranca el barrido, en segundos.
##
## No es cero a propósito: en `t = 0` el generador da velocidad 0, cabeceo 0, alabeo 0
## y los dos sticks centrados, o sea un HUD que parece roto justo en el primer instante,
## que es cuando el jugador abre el menú de opciones y cuando el check saca la captura.
## Arrancar con el barrido ya empezado es además **determinista**, que es lo que pide
## `docs/15` §1.1 (regla 5): la captura no depende de cuántos cuadros se esperaron.
const PREVIEW_START_TIME: float = 7.0

## Se alimenta sola con el generador de `docs/12` §2.5 e ignora [method update_data].
## Lo usan el panel de vista previa del menú de HUD y las capturas de los checks.
@export var preview_mode: bool = false:
	set = set_preview

var _frame: Control = null
var _horizon: HUDHorizon = null
var _tapes: HUDSideTapes = null
var _compass: HUDCompassTape = null
var _readouts: HUDReadouts = null
var _crosshair: HUDCrosshair = null
var _badge: HUDModeBadge = null
var _status: HUDStatus = null
var _rec: HUDRecIndicator = null
var _sticks: Control = null
var _stick_left: HUDStickInput = null
var _stick_right: HUDStickInput = null
var _rpm: HUDRPM = null
var _gate: HUDGateMarker = null

var _camera: FPVCamera = null

## Frecuencia de publicación de los numéricos, en Hz.
var _fps: float = float(DEFAULT_FPS)

## Modo pedido por `hud_config`; el efectivo depende además de que haya cámara.
var _horizon_mode: String = HORIZON_MODES[0]

var _mode_key: String = "acro"

# Estado continuo del último `update_data`.
var _pitch: float = 0.0
var _roll: float = 0.0

# Acumuladores del promedio ponderado por tiempo (`docs/12` §2.3).
var _acc_time: float = 0.0
var _acc_altitude: float = 0.0
var _acc_speed: float = 0.0
var _acc_vertical: float = 0.0
var _acc_heading_cos: float = 0.0
var _acc_heading_sin: float = 0.0

var _preview_time: float = 0.0
var _preview_rpm: Array[float] = [0.0, 0.0, 0.0, 0.0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collect_nodes()
	_layout()
	apply_hud_config()
	_apply_preview_state()
	update_flight_mode(_mode_key, false)
	if not GameSettings.hud_config_updated.is_connected(_on_hud_config_updated):
		var _discard := GameSettings.hud_config_updated.connect(_on_hud_config_updated)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_layout):
		var _discard := viewport.size_changed.connect(_layout)


func _exit_tree() -> void:
	if GameSettings.hud_config_updated.is_connected(_on_hud_config_updated):
		GameSettings.hud_config_updated.disconnect(_on_hud_config_updated)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_layout):
		viewport.size_changed.disconnect(_layout)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _frame != null:
		_layout()


func _process(delta: float) -> void:
	# Escondido no hay nada que redibujar ni barrido que avanzar: el nivel esconde el
	# HUD entero cuando la cámara activa no es la FPV (`docs/12` §1.1), y ahí seguir
	# pidiendo `queue_redraw()` a doce `Control` es trabajo tirado (riesgo 5 de §10).
	# `update_data()` sigue llegando del rig, así que al volver a verse el HUD está al
	# día en el primer cuadro.
	if not is_visible_in_tree():
		return
	if preview_mode:
		_advance_preview(delta)
	_update_orientation()


# --- Contrato de datos (`docs/12` §2.2) -------------------------------------------------------

## Muestra de vuelo del paso de física que la produjo (`docs/12` §2.2).
##
## Unidades, fijas para siempre: [param dt] en segundos; [param pos] en metros de
## mundo (`pos.y` es la altitud); [param angles] en **radianes**, con `x` cabeceo
## (positivo arriba), `y` guiñada y `z` alabeo (positivo a la derecha);
## [param velocity] en m/s de mundo (`velocity.y` es la velocidad vertical);
## los dos sticks en `[−1, 1]` ya con curvas y zona muerta; [param rpm] en rpm
## **absolutas**, cuatro elementos, que [HUDRPM] normaliza con su propio
## [constant HUDRPM.MAX_RPM].
##
## En [member preview_mode] la llamada se ignora: ahí manda el generador interno.
func update_data(dt: float, pos: Vector3, angles: Vector3, velocity: Vector3,
		left_stick: Vector2, right_stick: Vector2, rpm: Array[float]) -> void:
	if preview_mode:
		return
	_ingest(dt, pos, angles, velocity, left_stick, right_stick, rpm)


## Clave del modo de vuelo en el badge y si tiene que parpadear (`docs/12` §2.6).
## [param blink] es `true` para los modos que impone el sistema, no el piloto.
func update_flight_mode(key: String, blink: bool) -> void:
	_mode_key = key
	if _badge != null:
		_badge.set_mode(_mode_text_key(key), blink)


## Enciende o apaga un componente (`docs/12` §2.2).
##
## `SPEED` y `ALTITUDE` gobiernan los números de [HUDReadouts]; `SIDE_TAPES`, las
## cintas laterales: son independientes a propósito. `HORIZON` y `LADDER` comparten
## nodo y el nodo se ve mientras alguno de los dos esté encendido. `STICKS` mueve las
## dos cajas a la vez.
func show_component(component: Component, component_visible: bool) -> void:
	match component:
		Component.CROSSHAIR:
			_set_visible(_crosshair, component_visible)
		Component.STATUS:
			if _status != null:
				_status.enabled = component_visible
		Component.HEADING:
			_set_visible(_compass, component_visible)
		Component.SPEED:
			if _readouts != null:
				_readouts.show_speed = component_visible
				_refresh_readouts()
		Component.ALTITUDE:
			if _readouts != null:
				_readouts.show_altitude = component_visible
				_refresh_readouts()
		Component.LADDER:
			if _horizon != null:
				_horizon.show_ladder = component_visible
				_refresh_horizon()
		Component.HORIZON:
			if _horizon != null:
				_horizon.show_horizon = component_visible
				_refresh_horizon()
		Component.STICKS:
			_set_visible(_sticks, component_visible)
		Component.RPM:
			_set_visible(_rpm, component_visible)
		Component.FLIGHT_MODE:
			_set_visible(_badge, component_visible)
		Component.REC:
			if _rec != null:
				_rec.recording = component_visible
				_set_visible(_rec, component_visible)
		Component.SIDE_TAPES:
			_set_visible(_tapes, component_visible)


## Vuelca `GameSettings.hud_config` sobre el HUD (`docs/12` §2.4).
##
## Cualquier clave ausente o fuera de rango se corrige con el valor por defecto y
## **no** aborta: un `.cfg` viejo nunca rompe el HUD.
func apply_hud_config() -> void:
	var config: Dictionary = GameSettings.hud_config
	_fps = float(clampi(int(config.get("fps", DEFAULT_FPS)),
			GameSettings.HUD_FPS_RANGE.x, GameSettings.HUD_FPS_RANGE.y))
	var mode := String(config.get("horizon_mode", HORIZON_MODES[0]))
	_horizon_mode = mode if HORIZON_MODES.has(mode) else HORIZON_MODES[0]
	for component: int in CONFIG_KEYS:
		var key: String = CONFIG_KEYS[component]
		var wanted := bool(config.get(key, _default_toggle(key)))
		show_component(component as Component, wanted)
	_update_orientation()


## Enciende o apaga el generador interno de `docs/12` §2.5. Es el `set` de
## [member preview_mode]: las dos formas hacen lo mismo.
func set_preview(enabled: bool) -> void:
	if preview_mode == enabled and is_node_ready():
		return
	preview_mode = enabled
	if not is_node_ready():
		return
	_apply_preview_state()


## `Drone.armed`: mensaje de confirmación y modo en el badge (`docs/12` §2.6).
func on_armed(mode_key: String) -> void:
	if _status != null:
		_status.set_persistent("")
		_status.show_message(ARMED_KEY, COLOR_ARMED, HUDStatus.MESSAGE_SECONDS)
	update_flight_mode(mode_key, mode_key.to_lower() == BLINKING_MODE)


## `Drone.disarmed`: texto persistente parpadeando a 1 Hz (`docs/12` §2.6).
func on_disarmed() -> void:
	if _status != null:
		_status.set_persistent(DISARMED_KEY, COLOR_DISARMED)


## `Drone.arm_failed`: el motivo traducido, en rojo y parpadeando (`docs/12` §2.6).
## [param reason_key] es una de las claves `ERR_ARM_*` de `docs/03` §3.3.
func on_arm_failed(reason_key: String) -> void:
	if _status == null:
		return
	var key := String(ARM_FAILED_KEYS.get(reason_key, reason_key))
	_status.show_message(key, COLOR_ARM_FAILED, HUDStatus.MESSAGE_SECONDS, true)


## Cámara que usa el horizonte en modo `camera` y el marcador de objetivo
## (`docs/12` §2.4). Solo una [FPVCamera] sirve para el modo `camera`, porque es la
## única que sabe deformar la línea como el ojo de pez; con cualquier otra cosa —o con
## `null`— el horizonte cae al modo `attitude`, que siempre está definido.
func set_camera(camera: Camera3D) -> void:
	_camera = camera as FPVCamera
	if _horizon != null:
		_horizon.camera = _camera
	if _gate != null:
		_gate.camera = _camera
	_update_orientation()


# --- Consultas (las usan los checks y el menú de HUD) -----------------------------------------

## Nodo que dibuja [param component]. Nunca es `null` en un HUD bien construido.
func component_node(component: Component) -> Control:
	match component:
		Component.CROSSHAIR:
			return _crosshair
		Component.STATUS:
			return _status
		Component.HEADING:
			return _compass
		Component.SPEED, Component.ALTITUDE:
			return _readouts
		Component.LADDER, Component.HORIZON:
			return _horizon
		Component.STICKS:
			return _sticks
		Component.RPM:
			return _rpm
		Component.FLIGHT_MODE:
			return _badge
		Component.REC:
			return _rec
		Component.SIDE_TAPES:
			return _tapes
		_:
			return null


## Estado **configurado** de [param component]. No sigue el parpadeo ni el desvanecido
## de [HUDStatus]: informa de lo que se pidió, que es lo que comparan los checks y el
## menú de HUD.
func is_component_visible(component: Component) -> bool:
	match component:
		Component.STATUS:
			return _status != null and _status.enabled
		Component.SPEED:
			return _readouts != null and _readouts.show_speed
		Component.ALTITUDE:
			return _readouts != null and _readouts.show_altitude
		Component.LADDER:
			return _horizon != null and _horizon.show_ladder
		Component.HORIZON:
			return _horizon != null and _horizon.show_horizon
		_:
			var node := component_node(component)
			return node != null and node.visible


## Las dos cajas de stick, en el orden `[izquierda, derecha]`.
func stick_inputs() -> Array[HUDStickInput]:
	return [_stick_left, _stick_right]


## El marcador de objetivo. Arranca oculto: en combate lo reemplaza `OffscreenMarkers`
## del `CombatHUD` (`docs/12` §2.1 y §4.1).
func gate_marker() -> HUDGateMarker:
	return _gate


## Frecuencia de publicación de los numéricos vigente, en Hz.
func numeric_fps() -> float:
	return _fps


## Modo efectivo del horizonte: `camera` solo si además hay una [FPVCamera] viva.
func horizon_mode() -> String:
	if _horizon == null:
		return HORIZON_MODES[1]
	return String(_horizon.mode)


## `y` de viewport donde la línea de horizonte cruza la columna [param column_x], con
## el **mismo** barrido de azimut y la **misma** proyección que usa [HUDHorizon] en
## modo `camera`. Devuelve `NAN` si no hay cámara, si el horizonte no está en el campo
## o si esa columna no lo cruza.
##
## Existe para la fila 4 de `docs/12` §9.1, que compara esta `y` con la transición
## cielo/suelo de la imagen capturada: es el detector de que la proyección del HUD y la
## de la cámara no se hayan separado (riesgo 3 de `docs/12` §10).
func horizon_screen_y(column_x: float) -> float:
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return NAN
	var forward := -_camera.global_transform.basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() < 0.08:
		return NAN
	flat = flat.normalized()
	var previous := Vector2(NAN, NAN)
	for azimuth: int in range(-88, 89, 4):
		var point := _camera.project_direction(flat.rotated(Vector3.UP, deg_to_rad(azimuth)))
		if previous.is_finite() and point.is_finite():
			var low := minf(previous.x, point.x)
			var high := maxf(previous.x, point.x)
			if column_x >= low and column_x <= high:
				var span := point.x - previous.x
				if absf(span) < 1e-5:
					return (previous.y + point.y) * 0.5
				var weight := (column_x - previous.x) / span
				return previous.y + (point.y - previous.y) * weight
		previous = point
	return NAN


# --- Internos ---------------------------------------------------------------------------------

## Enruta una muestra —venga del rig o del generador de vista previa— hacia los dos
## ritmos de `docs/12` §2.3.
func _ingest(dt: float, pos: Vector3, angles: Vector3, velocity: Vector3,
		left_stick: Vector2, right_stick: Vector2, rpm: Array[float]) -> void:
	if not (pos.is_finite() and angles.is_finite() and velocity.is_finite()):
		return
	_pitch = angles.x
	_roll = angles.z
	var speed_kmh := velocity.length() * 3.6
	var altitude := pos.y

	# Continuos: valor instantáneo.
	if _tapes != null and _tapes.visible:
		_tapes.speed = velocity.length()
		_tapes.altitude = altitude
		_tapes.queue_redraw()
	if _stick_left != null:
		_stick_left.update_stick_input(left_stick)
	if _stick_right != null:
		_stick_right.update_stick_input(right_stick)
	if _rpm != null and _rpm.visible and rpm.size() >= 4:
		_rpm.update_rpm(rpm[0], rpm[1], rpm[2], rpm[3])

	# Numéricos: promedio ponderado por tiempo, publicado a `1/fps`.
	var step := maxf(dt, 0.0)
	if step <= 0.0:
		return
	# `heading = fposmod(rad_to_deg(−guiñada), 360)` (`docs/12` §2.2). Se acumula como
	# vector para que el promedio cruce el 0/360 sin inventar un sur.
	var heading := -angles.y
	_acc_time += step
	_acc_altitude += altitude * step
	_acc_speed += speed_kmh * step
	_acc_vertical += velocity.y * step
	_acc_heading_cos += cos(heading) * step
	_acc_heading_sin += sin(heading) * step
	if _acc_time >= 1.0 / maxf(_fps, 1.0):
		_publish_numeric()


## Publica el promedio acumulado y vacía los acumuladores.
func _publish_numeric() -> void:
	if _acc_time <= 0.0:
		return
	var inverse := 1.0 / _acc_time
	if _readouts != null:
		_readouts.altitude = _acc_altitude * inverse
		_readouts.speed_kmh = _acc_speed * inverse
		_readouts.vertical_speed = _acc_vertical * inverse
		if _readouts.visible:
			_readouts.queue_redraw()
	if _compass != null:
		_compass.heading = fposmod(rad_to_deg(atan2(_acc_heading_sin, _acc_heading_cos)), 360.0)
		if _compass.visible:
			_compass.queue_redraw()
	_acc_time = 0.0
	_acc_altitude = 0.0
	_acc_speed = 0.0
	_acc_vertical = 0.0
	_acc_heading_cos = 0.0
	_acc_heading_sin = 0.0


## Deja el horizonte en el modo que corresponde y pide su redibujo.
##
## Corre cada frame y no en [method update_data] a propósito: en modo `camera` la línea
## depende de la transformada de la cámara, que se mueve por su cuenta (el rig la
## inclina, WP-28 la sacudirá), no del último dato de vuelo.
func _update_orientation() -> void:
	if _horizon == null:
		return
	var has_camera := _camera != null and is_instance_valid(_camera) and _camera.is_inside_tree()
	var wanted := _horizon_mode if has_camera else HORIZON_MODES[1]
	if _horizon.mode != wanted:
		_horizon.mode = wanted
	_horizon.pitch = _pitch
	_horizon.roll = _roll
	if _horizon.visible:
		_horizon.queue_redraw()


## Escala el marco para que el lienzo de [constant MIN_LAYOUT_SIZE] entre en el
## espacio disponible, sin agrandarlo nunca.
func _layout() -> void:
	if _frame == null:
		return
	var available := size
	if available.x < 1.0 or available.y < 1.0:
		available = MIN_LAYOUT_SIZE
	var factor := minf(1.0, minf(available.x / MIN_LAYOUT_SIZE.x,
			available.y / MIN_LAYOUT_SIZE.y))
	factor = maxf(factor, 0.05)
	_frame.position = Vector2.ZERO
	_frame.scale = Vector2(factor, factor)
	_frame.size = available / factor


## Toma los nodos por nombre único y avisa de los que falten. Un HUD al que le falta un
## componente no debe fallar en silencio: se dibujaría a medias y nadie sabría por qué.
func _collect_nodes() -> void:
	_frame = get_node_or_null(^"%Frame") as Control
	_horizon = get_node_or_null(^"%HUDHorizon") as HUDHorizon
	_tapes = get_node_or_null(^"%HUDSideTapes") as HUDSideTapes
	_compass = get_node_or_null(^"%HUDCompass") as HUDCompassTape
	_readouts = get_node_or_null(^"%HUDReadouts") as HUDReadouts
	_crosshair = get_node_or_null(^"%Crosshair") as HUDCrosshair
	_badge = get_node_or_null(^"%HUDModeBadge") as HUDModeBadge
	_status = get_node_or_null(^"%HUDStatus") as HUDStatus
	_rec = get_node_or_null(^"%HUDRec") as HUDRecIndicator
	_sticks = get_node_or_null(^"%HUDSticks") as Control
	_rpm = get_node_or_null(^"%HUDRPM") as HUDRPM
	_gate = get_node_or_null(^"%HUDGateMarker") as HUDGateMarker
	if _sticks != null:
		_stick_left = _sticks.get_node_or_null(^"StickLeft") as HUDStickInput
		_stick_right = _sticks.get_node_or_null(^"StickRight") as HUDStickInput
	var missing := PackedStringArray()
	for pair: Array in [["Frame", _frame], ["HUDHorizon", _horizon],
			["HUDSideTapes", _tapes], ["HUDCompass", _compass], ["HUDReadouts", _readouts],
			["Crosshair", _crosshair], ["HUDModeBadge", _badge], ["HUDStatus", _status],
			["HUDRec", _rec], ["HUDSticks", _sticks], ["HUDSticks/StickLeft", _stick_left],
			["HUDSticks/StickRight", _stick_right], ["HUDRPM", _rpm],
			["HUDGateMarker", _gate]]:
		if pair[1] == null:
			missing.append(String(pair[0]))
	if not missing.is_empty():
		push_error("FlightHUD: faltan componentes en %s: %s" % [name, ", ".join(missing)])


## Valor por defecto de un interruptor: el del preset que `GameSettings` usa en el
## primer arranque (`docs/04` §3.4), que es la única fuente de verdad de esa tabla.
func _default_toggle(key: String) -> bool:
	var enabled: Array = GameSettings.HUD_PRESETS[GameSettings.DEFAULT_HUD_PRESET]
	return enabled.has(key)


func _set_visible(node: Control, wanted: bool) -> void:
	if node != null and node.visible != wanted:
		node.visible = wanted


## El nodo del horizonte se ve mientras la línea o la escalera estén encendidas.
func _refresh_horizon() -> void:
	if _horizon == null:
		return
	_set_visible(_horizon, _horizon.show_horizon or _horizon.show_ladder)
	if _horizon.visible:
		_horizon.queue_redraw()


## Ídem para los números: velocidad y altitud comparten nodo.
func _refresh_readouts() -> void:
	if _readouts == null:
		return
	_set_visible(_readouts, _readouts.show_speed or _readouts.show_altitude)
	if _readouts.visible:
		_readouts.queue_redraw()


## Clave de traducción del badge. Acepta tanto la clave de modo de `docs/03` §3.2
## (`acro`, `horizon`, …) como una clave `HUD_MODE_*` ya resuelta.
func _mode_text_key(key: String) -> String:
	return String(MODE_KEYS.get(key.to_lower(), key))


func _on_hud_config_updated() -> void:
	apply_hud_config()


# --- `preview_mode` (`docs/12` §2.5) -----------------------------------------------------------

## Prepara o desmonta el generador interno.
##
## Un HUD en vista previa no tiene dron ni cámara, así que el horizonte cae a modo
## `attitude` solo y el estado se deja en «armado»: lo que el menú de opciones tiene
## que mostrar es un HUD en vuelo, no uno esperando el armado.
func _apply_preview_state() -> void:
	_preview_time = PREVIEW_START_TIME
	_acc_time = 0.0
	_acc_altitude = 0.0
	_acc_speed = 0.0
	_acc_vertical = 0.0
	_acc_heading_cos = 0.0
	_acc_heading_sin = 0.0
	if _status != null:
		if preview_mode:
			_status.set_persistent(ARMED_KEY, COLOR_ARMED, false)
		else:
			_status.clear()
	if preview_mode and _rec != null:
		_rec.recording = _rec.visible
	if preview_mode:
		# Una muestra de un período de numéricos completo, para que los números estén
		# publicados desde el primer cuadro en vez de quedar en cero hasta el primer
		# `1/fps`. El barrido queda igualmente empezado en [constant PREVIEW_START_TIME].
		var period := 1.0 / maxf(_fps, 1.0)
		_preview_time = PREVIEW_START_TIME - period
		_advance_preview(period)
	_update_orientation()


## Barrido suave de `docs/12` §2.5, determinista: nada de `randf()`, para que dos
## capturas del mismo instante salgan iguales (`docs/15` §1.1, regla 5).
func _advance_preview(delta: float) -> void:
	_preview_time += delta
	var t := _preview_time
	var pitch := deg_to_rad(PREVIEW_PITCH_DEG * sin(t * 0.70))
	var roll := deg_to_rad(PREVIEW_ROLL_DEG * sin(t * 0.43 + 1.1))
	var heading := fposmod(t * PREVIEW_HEADING_RATE, 360.0)
	var yaw := -deg_to_rad(heading)
	var altitude := PREVIEW_ALTITUDE \
			+ PREVIEW_ALTITUDE_SWING * sin(t * PREVIEW_ALTITUDE_OMEGA)
	# Velocidad vertical = derivada exacta de la altura, para que los dos números de
	# `HUDReadouts` cuenten la misma historia.
	var climb := PREVIEW_ALTITUDE_SWING * PREVIEW_ALTITUDE_OMEGA \
			* cos(t * PREVIEW_ALTITUDE_OMEGA)
	var speed := PREVIEW_SPEED_MAX * 0.5 * (1.0 - cos(t * 0.23)) / 3.6
	var vertical := clampf(climb, -speed, speed)
	var horizontal := sqrt(maxf(speed * speed - vertical * vertical, 0.0))
	var velocity := Vector3(horizontal * sin(yaw), vertical, -horizontal * cos(yaw))
	var left := Vector2(0.85 * sin(t * 1.30), 0.80 * sin(t * 0.90 + PI * 0.5))
	var right := Vector2(0.80 * sin(t * 1.10 + 0.4), 0.75 * sin(t * 1.70))
	var base := 0.46 + 0.22 * sin(t * 0.37)
	for index: int in _preview_rpm.size():
		var phase := float(index) * PI * 0.5
		var ripple := 0.07 * sin(t * (5.3 + 0.7 * float(index)) + phase * 1.7) \
				+ 0.04 * sin(t * (11.0 + float(index)) + phase)
		_preview_rpm[index] = clampf(base + 0.14 * sin(t * 0.9 + phase) + ripple, 0.05, 1.0) \
				* HUDRPM.MAX_RPM
	_ingest(delta, Vector3(0.0, altitude, 0.0), Vector3(pitch, yaw, roll), velocity,
			left, right, _preview_rpm)
