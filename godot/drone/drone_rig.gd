## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Conjunto jugable del dron: cuerpo, controlador de vuelo, radio y cámara FPV,
## cableados entre sí y con la configuración del jugador (`docs/03` §8).
##
## El rig es solo cableado. No hay lógica de vuelo acá: el [Drone] pone la física,
## el [FlightController] el lazo de control, el [RadioController] la entrada y la
## [FPVCamera] la vista. Lo que aporta este nodo es lo que ninguno de ellos puede
## saber solo:
## - dónde reaparece el dron (lo cablea el nivel en [member respawn_point]);
## - cuándo cambió la configuración del hangar (`QuadSettings.settings_updated`),
##   para refrescar el perfil de rates del controlador, la inclinación de la cámara
##   y su FOV. La masa la toma el propio dron de la misma señal.
##
## Estado de WP-15 respecto del árbol de §8: el rig está completo. `Drone`,
## `FlightController`, `RadioController`, `CameraRig`, `FPVCamera`, `ModeLED`,
## `MotorAudio`, `WeaponMount`, `EnergySystem` y `Hull` viven dentro de
## `drone_quad.tscn`; `FlightHUD` y `RespawnController` son hermanos del `Drone`.
##
## **Energía, casco y respawn (WP-15, `docs/09`)**: la batería y el casco se cablean
## solos —son hijos del `Drone` y encuentran a su dueño por ancestro—, así que lo
## único que aporta el rig es reexponer [signal respawned]. Es la señal que
## `docs/11` consume para aplicar el castigo de puntaje, y tiene que salir del rig
## y no del bus porque el `RoundManager` necesita saber **de qué dron** habla.
##
## **El arma (WP-14, `docs/08`)**: vive en `drone_quad.tscn` como hija del `Drone`, por
## la misma razón que el `ModeLED` y el `MotorAudio`. Lo único que aporta el rig es el
## puente **radio → arma**: `fire_changed`, `fire_alt_changed`, `lock_pressed` y
## `cycle_target_pressed`. El `WeaponMount` nunca lee el `InputMap`, así que sin este
## cableado el arma existe pero no dispara, que es exactamente lo que se quiere en un
## dron de adorno ([member radio_enabled] en `false`).
##
## **Dónde viven `ModeLED` y `MotorAudio` (WP-07)**: en `drone_quad.tscn`, no acá. El
## §8 los dibuja colgando del `Drone`, y el `Drone` de este rig **es** una instancia de
## `drone_quad.tscn`: ponerlos allá deja las rutas de §8 (`Drone/ModeLED`,
## `Drone/MotorAudio`) exactamente como el documento las pide y, además, cualquier
## escena que use el dron suelto —`flight_bench.tscn`— hereda el LED y el audio sin
## duplicar cableado. El `ModeLED` ya estaba allá como `Node3D` vacío desde WP-12b:
## WP-07 solo le puso el script.
##
## **El `FlightHUD` (WP-08, `docs/12` §2)**: hermano del `Drone`, instancia de
## `hud/hud.tscn`. El HUD **no observa al dron**: este rig lo alimenta una vez por
## frame de física con [method FlightHUD.update_data] y le reemite las cuatro señales
## de vuelo. Esa es la razón de que el HUD pueda existir sin dron —la vista previa del
## menú de opciones y los checks— y de que las unidades de `docs/12` §2.2 tengan un
## único punto de conversión, que es [method _feed_hud].
class_name DroneRig extends Node3D

## El dron volvió a volar tras morir. [param score_multiplier] es el castigo
## acumulado, con piso 0.30 (`docs/09` §2.8). La reexpone el rig desde
## [signal RespawnController.respawned]; es la que consume `docs/11`.
signal respawned(score_multiplier: float)

## Punto de reaparición. Lo cablea el nivel; el rig se lo pasa al dron y lo usa
## para atender `reset_requested` de la radio.
@export var respawn_point: Node3D

## Deja el rig con la radio apagada, para las escenas donde el dron es decorado
## (menú principal, cinemáticas) o donde el vuelo lo maneja un check.
@export var radio_enabled: bool = true

## Deja el rig sin HUD, por la misma razón que [member radio_enabled]: un dron de
## adorno no tiene piloto al que informarle de nada. Con `false` el nodo se libera en
## [method _ready] y [method get_flight_hud] devuelve `null`.
@export var hud_enabled: bool = true

var _drone: Drone = null
var _controller: FlightController = null
var _radio: RadioController = null
var _camera_rig: CameraRig = null
var _fpv_camera: FPVCamera = null
var _mode_led: ModeLED = null
var _motor_audio: MotorAudio = null
var _hud: FlightHUD = null
var _weapon: WeaponMount = null
var _energy: EnergySystem = null
var _hull: Hull = null
var _respawn_controller: RespawnController = null
var _overlay: FPVOverlay = null


func _ready() -> void:
	_drone = get_node_or_null(^"Drone") as Drone
	if _drone == null:
		push_error("DroneRig: falta el nodo 'Drone' en %s." % name)
		return
	_controller = _drone.get_node_or_null(^"FlightController") as FlightController
	_radio = get_node_or_null(^"RadioController") as RadioController
	_camera_rig = _drone.get_node_or_null(^"CameraRig") as CameraRig
	_fpv_camera = _drone.get_node_or_null(^"CameraRig/FPVCamera") as FPVCamera
	_mode_led = _drone.get_node_or_null(^"ModeLED") as ModeLED
	_motor_audio = _drone.get_node_or_null(^"MotorAudio") as MotorAudio
	_weapon = _drone.get_node_or_null(^"WeaponMount") as WeaponMount
	_energy = _drone.get_node_or_null(^"EnergySystem") as EnergySystem
	_hull = _drone.get_node_or_null(^"Hull") as Hull
	_respawn_controller = get_node_or_null(^"RespawnController") as RespawnController
	_overlay = get_node_or_null(^"Overlay") as FPVOverlay
	_hud = get_node_or_null(^"FlightHUD") as FlightHUD
	if _controller == null:
		push_error("DroneRig: falta 'Drone/FlightController' en %s." % name)
	if _radio == null:
		push_error("DroneRig: falta el nodo 'RadioController' en %s." % name)
	if _camera_rig == null or _fpv_camera == null:
		push_error("DroneRig: falta 'Drone/CameraRig/FPVCamera' en %s." % name)
	if _mode_led == null:
		push_error("DroneRig: falta 'Drone/ModeLED' en %s (docs/03 §7)." % name)
	if _weapon == null:
		push_error("DroneRig: falta 'Drone/WeaponMount' en %s (docs/08 §3.1)." % name)
	if _energy == null:
		push_error("DroneRig: falta 'Drone/EnergySystem' en %s (docs/09 §3.1)." % name)
	if _hull == null:
		push_error("DroneRig: falta 'Drone/Hull' en %s (docs/09 §3.1)." % name)
	if _respawn_controller == null:
		push_error("DroneRig: falta 'RespawnController' en %s (docs/09 §3.1)." % name)
	if _overlay == null:
		push_error("DroneRig: falta 'Overlay' en %s (docs/13 §7)." % name)
	_check_motor_audio()

	if respawn_point != null:
		_drone.respawn_point = respawn_point
	if _radio != null:
		_radio.target = _drone
		_radio.enabled = radio_enabled
		if not _radio.reset_requested.is_connected(_on_reset_requested):
			var _discard := _radio.reset_requested.connect(_on_reset_requested)

	_wire_weapon()
	_wire_respawn()
	_wire_hud()

	var _discard := QuadSettings.settings_updated.connect(_on_quad_settings_updated)
	_on_quad_settings_updated()


## Alimenta el HUD con el estado del último paso de física (`docs/12` §2.2).
##
## Va en `_physics_process` y no en `_process` porque lo que se publica es una muestra
## del paso que la produjo: el [param delta] que viaja con ella es el peso del promedio
## ponderado de `docs/12` §2.3, y con `Engine.time_scale` acelerado —los bancos— ese
## peso cambia. Los componentes continuos del HUD se redibujan igual en cada frame de
## render, desde su propio `_process`.
func _physics_process(delta: float) -> void:
	PerfProbe.begin(&"drone_rig")
	_feed_hud(delta)
	PerfProbe.end(&"drone_rig")


## El dron del rig.
func get_drone() -> Drone:
	return _drone


## El controlador de vuelo del rig.
func get_flight_controller() -> FlightController:
	return _controller


## La radio del rig.
func get_radio() -> RadioController:
	return _radio


## El soporte de la cámara: el único nodo que escribe su transformada (`docs/03` §5).
func get_camera_rig() -> CameraRig:
	return _camera_rig


## La cámara FPV. Es lo que busca `LevelBase.collect_cameras()` para ponerla primera
## en el ciclo de cámaras del nivel (`docs/03` §5).
func get_fpv_camera() -> FPVCamera:
	return _fpv_camera


## El LED de modo del dron (`docs/03` §7).
func get_mode_led() -> ModeLED:
	return _mode_led


## El audio de motores del dron (`docs/03` §6).
func get_motor_audio() -> MotorAudio:
	return _motor_audio


## El HUD de vuelo del rig (`docs/12` §2). Lo consulta `LevelBase` para esconderlo
## cuando la cámara activa no es la FPV.
func get_flight_hud() -> FlightHUD:
	return _hud


## El arma primaria del dron (`docs/08` §3.2).
func get_weapon_mount() -> WeaponMount:
	return _weapon


## La batería del dron (`docs/09` §3.2). Es a quien se conecta el `CombatHUD` para
## el glitch de EMP, que viaja por señal local y no por el bus.
func get_energy_system() -> EnergySystem:
	return _energy


## El casco del dron (`docs/09` §3.5).
func get_hull() -> Hull:
	return _hull


## El controlador de muerte y reaparición del rig (`docs/09` §3.5).
func get_respawn_controller() -> RespawnController:
	return _respawn_controller


## El overlay de la señal FPV (`docs/13` §7): la capa −1 con la viñeta, el grano, las
## scanlines, la aberración y los dos estados de degradación.
##
## El rig **no lo cablea**: el overlay se engancha solo a `Events.hull_changed` y a la
## señal local `EnergySystem.emp_hit`, igual que la batería y el casco se cablean solos.
## Lo único que aporta el rig es este accessor, que es por donde la sacudida de WP-28
## parte B lee [method FPVOverlay.signal_quality] para publicarla en el `FlightHUD`.
func get_overlay() -> FPVOverlay:
	return _overlay


## Multiplicador de puntaje vigente, 1.0 si el dron todavía no murió.
func get_score_multiplier() -> float:
	return _respawn_controller.get_score_multiplier() if _respawn_controller != null else 1.0


# --- Arma (`docs/08` §2.2) ---------------------------------------------------------------------

## Puente radio → arma. Son las cuatro señales de `docs/03` §4 que WP-14 estrena.
##
## `fire_changed` se traduce a [member WeaponMount.fire_pressed] y no a una llamada a
## `fire()`: el gatillo es un **estado** y la cadencia la lleva el acumulador del arma,
## que es lo único que le da los 8 disparos/s exactos de `docs/08` §2.12. Si la radio
## disparara por evento, la cadencia sería la del `InputMap`.
##
## Con [member radio_enabled] en `false` no se conecta nada: un dron de adorno no
## dispara, y además el `WeaponMount` queda libre para que un check le escriba
## `fire_pressed` a mano sin pelearse con la radio.
func _wire_weapon() -> void:
	if _weapon == null or _radio == null or not radio_enabled:
		return
	var _discard := _radio.fire_changed.connect(_weapon.set_fire_pressed)
	_discard = _radio.fire_alt_changed.connect(_weapon.set_fire_alt_pressed)
	_discard = _radio.lock_pressed.connect(_weapon.lock_target)
	_discard = _radio.cycle_target_pressed.connect(_weapon.cycle_target)
	_discard = GameSettings.game_settings_updated.connect(_weapon.refresh_settings)


# --- Energía, casco y respawn (`docs/09` §2.8) ------------------------------------------------

## Reexpone [signal RespawnController.respawned] como [signal respawned].
##
## No es redundante con `Events.drone_respawned`: el bus publica **el hecho** para
## quien no conoce al dron (el `CombatHUD`), y esta señal lo publica **desde este
## rig** para quien sí necesita saber de cuál habla. `docs/11` consume ésta.
func _wire_respawn() -> void:
	if _respawn_controller == null:
		return
	if not _respawn_controller.respawned.is_connected(_on_respawned):
		var _discard := _respawn_controller.respawned.connect(_on_respawned)


func _on_respawned(score_multiplier: float) -> void:
	respawned.emit(score_multiplier)


# --- HUD de vuelo (`docs/12` §2) --------------------------------------------------------------

## Conecta el HUD con el dron: la cámara para el horizonte en modo `camera`, las cuatro
## señales de vuelo y el estado inicial.
##
## El estado inicial se fija a mano porque **ninguna señal se emite al arrancar**: el
## dron nace desarmado y en ACRO sin avisarle a nadie, así que sin esto el HUD
## arrancaría en blanco hasta el primer intento de armado.
func _wire_hud() -> void:
	if _hud == null:
		push_error("DroneRig: falta el nodo 'FlightHUD' en %s (docs/03 §8)." % name)
		return
	if not hud_enabled:
		# Se libera en vez de esconderse: `LevelBase` vuelve a mostrar el HUD del rig
		# cada vez que la cámara activa es la FPV, así que un `visible = false` acá
		# duraría hasta el primer cambio de cámara. Sin nodo no hay ambigüedad, y
		# [method get_flight_hud] devuelve `null`, que es la respuesta correcta.
		var orphan := _hud
		_hud = null
		orphan.visible = false
		remove_child(orphan)
		orphan.queue_free()
		return
	_hud.set_camera(_fpv_camera)
	if _drone == null:
		return
	var _discard := _drone.armed.connect(_hud.on_armed)
	_discard = _drone.disarmed.connect(_hud.on_disarmed)
	_discard = _drone.arm_failed.connect(_hud.on_arm_failed)
	_discard = _drone.flight_mode_changed.connect(_on_flight_mode_changed)
	_on_flight_mode_changed(_drone.get_mode_key())
	if _drone.is_armed():
		_hud.on_armed(_drone.get_mode_key())
	else:
		_hud.on_disarmed()


## Una muestra de vuelo por paso de física, en las unidades de `docs/12` §2.2.
##
## La única conversión que hace falta es la de los ángulos: [FlightState] los guarda en
## convención de **piloto** —`(alabeo, cabeceo, guiñada)`, `docs/03` §3.1— y el HUD los
## pide como `(cabeceo, guiñada, alabeo)`. Los dos usan radianes y el mismo signo, así
## que es una permutación y nada más.
func _feed_hud(delta: float) -> void:
	if _hud == null or not hud_enabled or _drone == null:
		return
	var state := _drone.get_flight_state()
	var angles := Vector3(state.euler.y, state.euler.z, state.euler.x)
	var left := _radio.get_left_stick() if _radio != null else Vector2.ZERO
	var right := _radio.get_right_stick() if _radio != null else Vector2.ZERO
	_hud.update_data(delta, state.position, angles, state.velocity, left, right,
			_drone.get_motor_rpm())
	# La señal del `HUDSignalIndicator` sale del overlay y no de una cuenta propia
	# (`docs/13` §7): el overlay ya sabe cuánto daño y cuánto EMP está dibujando, y
	# publicar su misma cifra es lo que garantiza que las barras y la imagen digan lo
	# mismo. Sin overlay —un rig de adorno— la señal es perfecta.
	_hud.set_signal_quality(_overlay.signal_quality() if _overlay != null else 1.0)


## `RECOVER` lo impone el sistema, no el piloto: por eso el badge parpadea
## (`docs/12` §2.6).
func _on_flight_mode_changed(mode_key: String) -> void:
	if _hud == null:
		return
	_hud.update_flight_mode(mode_key, mode_key.to_lower() == FlightHUD.BLINKING_MODE)


## Comprueba que el audio de motores esté y tenga a dónde sonar.
##
## `Audio.audio_settings_updated` **no** se cablea acá a propósito: el volumen del
## jugador lo aplica el autoload sobre el bus con `AudioServer.set_bus_volume_db()`
## (`docs/04` §3.2), y un bus es justamente lo que evita que cada emisor tenga que
## enterarse. Lo único que el rig tiene que garantizar es que el bus exista; si
## faltara, los ocho reproductores caerían en `Master` y el deslizador «Motores»
## del menú de audio no movería nada.
func _check_motor_audio() -> void:
	if _motor_audio == null:
		push_error("DroneRig: falta 'Drone/MotorAudio' en %s (docs/03 §6)." % name)
		return
	if AudioServer.get_bus_index(MotorAudio.BUS) < 0:
		push_error("DroneRig: el bus de audio '%s' no existe en default_bus_layout.tres (docs/04 §3.2)."
				% String(MotorAudio.BUS))


## Manda el dron al punto de reaparición. Devuelve `false` si el nivel no cableó
## [member respawn_point] ni [member Drone.respawn_point].
func respawn() -> bool:
	if _drone == null:
		return false
	if respawn_point != null:
		_drone.reset_to(respawn_point.global_transform)
		return true
	return _drone.respawn()


func _on_reset_requested() -> void:
	var _done := respawn()


## Refresca lo que el hangar puede cambiar en caliente (`docs/04` §3.6): el perfil de
## rates, la inclinación de la cámara y su FOV. La masa la aplica el propio dron desde
## la misma señal.
##
## El [CameraRig] y la [FPVCamera] también escuchan `settings_updated` por su cuenta
## —son los dueños de su propio estado y tienen que valer fuera de este rig—, así que
## esto es redundante a propósito: lo que garantiza es que al **arrancar** el rig queden
## con la inclinación y el FOV del hangar sin esperar a que el jugador toque nada.
func _on_quad_settings_updated() -> void:
	if _controller != null:
		_controller.set_control_profile(QuadSettings.control_profile)
	if _camera_rig != null:
		_camera_rig.set_tilt_degrees(QuadSettings.angle)
	if _fpv_camera != null:
		_fpv_camera.set_horizontal_fov(QuadSettings.fov)
