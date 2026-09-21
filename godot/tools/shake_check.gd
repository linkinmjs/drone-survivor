## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Verificación headless de la sacudida de cámara (`docs/13` §6 y §10.4).
##
## ```
## "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless \
##     --path godot res://tools/shake_check.tscn
## ```
##
## Diez filas sobre el [CameraRig] de un `drone_rig.tscn` real —el mismo montaje que
## usan `audio_check` y `overlay_check`— y no sobre un `Node3D` suelto: lo que hay que
## demostrar no es que un modelo de trauma decaiga, es que **ese** nodo, con la
## `FPVCamera` colgada y el `FlightHUD` al lado, sacude la imagen y el instrumental
## juntos y devuelve la cámara exactamente a donde estaba.
##
## | # | Verifica |
## |---|---|
## | 1 | `add_trauma(1.0)` → `get_trauma()` llega a 0.0 antes de 1.5 s (teórico 0.72 s) |
## | 2 | Durante la sacudida el desplazamiento nunca supera 0.08 m ni 2.5°, muestreado a 240 Hz |
## | 3 | Al terminar, la cámara vuelve exactamente a su base (error < 1e-4), también con inclinación del hangar |
## | 4 | `Events.camera_trauma(0.5, p)` a 160 m aporta ≤ 0.5 × 0.15, y a 0 m aporta 0.5 |
## | 5 | Con sacudida activa el horizonte del `FlightHUD` sigue a la cámara con < 1 px en OFF, FAST, FAST_WIDE y FULL |
## | 6 | Sumar trauma 30 veces en un frame no supera 1.0 |
## | 7 | La calidad de señal publicada: 0.55 / 0.30 / 0.165 / 1.0 con 3 / 2 / 1 / 4 barras |
## | 8 | Dos rigs con la misma semilla producen la misma trayectoria (±1e-6) |
## | 9 | Sin fugas de nodos tras 30 ciclos de sacudida |
## | 10 | Prueba negativa: con `--negative` el decaimiento se apaga y las filas 1 y 3 fallan |
##
## ## El reloj se avanza a mano
##
## [method CameraRig.tick] es la única fuente de tiempo de la sacudida, así que el
## check apaga su `_process` y la llama con el paso que quiere medir, igual que
## `overlay_check` hace con [method FPVOverlay.tick]. Los plazos se miden en pasos y no
## en segundos de pared: no hay tolerancia por carga de la máquina y el resultado es
## idéntico en CI y en escritorio.
##
## ## Por qué la fila 5 no necesita imagen
##
## [method FPVCamera.project_direction] es **analítica** en los cuatro modos (`docs/03`
## §5): el compuesto es equidistante por construcción y la fórmula no consulta ningún
## píxel. Por eso esta fila corre en `--headless` y no duplica la fila 4 de `docs/12`
## §9.1, que sí captura imagen y vive en `hud_projection_check`. Lo que se mide acá es
## que el horizonte que dibuja el HUD en modo `camera` esté donde la cámara **sacudida**
## dice que está esa dirección del mundo: si alguien atara el horizonte a la actitud del
## dron en vez de a la cámara, la sacudida dejaría de arrastrarlo y esta fila lo vería.
##
## ## La prueba negativa
##
## Con `-- --negative` el decaimiento del rig se pone en 0: el trauma nunca baja, la
## sacudida no termina y la cámara no vuelve a la base. Las filas 1 y 3 fallan. Sirve
## para demostrar que esas dos filas miden algo y no que cualquier número pasa.
extends CheckRunner

## Paso de muestreo de la envolvente (fila 2): 240 Hz, cuatro veces el paso de física.
const STEP: float = 1.0 / 240.0

## Tope de la fila 1, en segundos simulados.
const MAX_DECAY_SECONDS: float = 1.5

## Extinción teórica con trauma 1.0 y 1.4/s de caída (`docs/13` §6).
const THEORETICAL_SECONDS: float = 1.0 / 1.4

## Tope duro del bucle de la fila 1. Con el decaimiento apagado —la prueba negativa—
## el trauma no baja nunca y el bucle tiene que cortar igual.
const GUARD_SECONDS: float = 2.5

## Error admitido al volver a la base (`docs/13` §10.4, fila 3).
const BASE_TOLERANCE: float = 1e-4

## Holgura de la envolvente de la fila 2. No es 0 exacto porque el ángulo se mide
## recomponiendo la base desde los tres ángulos de Euler.
const ENVELOPE_TOLERANCE: float = 1e-5

## Distancia y trauma de la fila 4 (`docs/13` §10.4).
const FAR_DISTANCE: float = 160.0
const FAR_AMOUNT: float = 0.5

## Sumas de trauma en un frame de la fila 6.
const BURST_ADDS: int = 30
const BURST_AMOUNT: float = 0.5

## Inclinación del hangar con la que se repite la fila 3.
const TILT_DEGREES: float = 30.0

## Tolerancia de la fila 5, en píxeles (`docs/13` §10.4).
const HORIZON_TOLERANCE: float = 1.0

## Pasos de sacudida que se avanzan antes de medir el horizonte. Con ocho pasos de
## 240 Hz el ruido ya se movió lo suficiente como para que el desplazamiento sea
## legible y el trauma sigue casi entero.
const HORIZON_STEPS: int = 8

## Desplazamiento mínimo del horizonte en la fila 5. Sin este piso la fila pasaría
## también con una sacudida que no mueve nada.
const HORIZON_MIN_SHIFT: float = 0.5

## Tolerancia y largo de la fila 8.
const DETERMINISM_TOLERANCE: float = 1e-6
const DETERMINISM_STEPS: int = 120

## Semilla con la que se demuestra que la semilla manda (fila 8).
const OTHER_SEED: int = 987654321

## Ciclos de sacudida de la fila 9.
const LEAK_CYCLES: int = 30

## Diferencia de nodos admitida en la fila 9: ninguna.
const LEAK_TOLERANCE: int = 0

## Segundos del pulso EMP de la fila 7 (`docs/13` §9).
const GLITCH_SECONDS: float = 3.0

## Tolerancia de las calidades publicadas en la fila 7.
const QUALITY_TOLERANCE: float = 1e-4

## Bandera de la prueba negativa.
const NEGATIVE_ARG: String = "negative"

var _rig: DroneRig = null
var _drone: Drone = null
var _camera_rig: CameraRig = null
var _camera: FPVCamera = null
var _hud: FlightHUD = null
var _overlay: FPVOverlay = null
var _hull: Hull = null
var _signal: HUDSignalIndicator = null
var _negative: bool = false
var _saved_horizon_mode: String = ""
var _saved_fisheye: int = 0


func _run() -> void:
	_negative = user_args().has(NEGATIVE_ARG)
	if _negative:
		print("  MODO NEGATIVO: el decaimiento del trauma se apaga; las filas 1 y 3 deben fallar.")
	await wait_frames(2)
	if not _resolve():
		return

	# El rig es un cuerpo rígido desarmado: sin congelarlo se cae 60 m durante el
	# check y la fila 4, que mide distancias contra `global_position`, mediría contra
	# una posición distinta en cada medición.
	_drone.freeze = true
	# La sacudida no vuelve a tener otro reloj que el nuestro. Va por `auto_tick` y no
	# por `set_process(false)`: el rig enciende su propio `_process` al empezar una
	# sacudida, así que apagarlo desde afuera duraría hasta el primer `add_trauma`.
	_camera_rig.auto_tick = false
	# El overlay tampoco: la fila 7 necesita el EMP clavado en 1.0.
	_overlay.set_process(false)
	if _negative:
		_camera_rig.decay_per_second = 0.0

	await wait_physics(2)
	_check_decay_and_envelope()
	_check_return_to_base()
	_check_distance_attenuation()
	await _check_horizon_follows()
	_check_burst_ceiling()
	await _check_published_signal()
	_check_determinism()
	await _check_leaks()
	await wait_frames(1)


func finish() -> void:
	# El modo de horizonte y el de ojo de pez se tocan en la fila 5: devolverlos es
	# obligación del check aunque falle.
	if not _saved_horizon_mode.is_empty():
		GameSettings.hud_config["horizon_mode"] = _saved_horizon_mode
		if _hud != null:
			_hud.apply_hud_config()
	if _camera != null and is_instance_valid(_camera):
		_camera.set_fisheye_mode(_saved_fisheye)
	super.finish()


func _resolve() -> bool:
	_rig = get_node_or_null(^"DroneRig") as DroneRig
	if _rig == null:
		fail("la escena del check no trae 'DroneRig'")
		return false
	_drone = _rig.get_drone()
	_camera_rig = _rig.get_camera_rig()
	_camera = _rig.get_fpv_camera()
	_hud = _rig.get_flight_hud()
	_overlay = _rig.get_overlay()
	_hull = _rig.get_hull()
	if _camera_rig == null:
		fail("el DroneRig no expone CameraRig (docs/03 §5)")
		return false
	if _drone == null or _camera == null or _hud == null or _overlay == null or _hull == null:
		fail("el DroneRig no está completo: drone %s, cámara %s, HUD %s, overlay %s, casco %s"
				% [_drone != null, _camera != null, _hud != null, _overlay != null,
				_hull != null])
		return false
	_signal = _hud.find_child("HUDSignal", true, false) as HUDSignalIndicator
	if _signal == null:
		fail("el FlightHUD no trae el HUDSignalIndicator 'HUDSignal' (docs/12 §2)")
		return false
	_saved_fisheye = _camera.get_fisheye_mode()
	return true


# --- [1] y [2] Decaimiento y envolvente --------------------------------------------------------

## `add_trauma(1.0)` decae a 0 antes de 1.5 s y, mientras tanto, la cámara nunca se
## aparta más de `max_translation` ni de `max_rotation_degrees` de su base.
##
## Las dos filas comparten el mismo barrido porque miden la misma sacudida: separarlas
## obligaría a sacudir dos veces y la segunda arrancaría con el ruido en otra fase, que
## es justo la variable que no hay que mover al comparar envolventes.
func _check_decay_and_envelope() -> void:
	_reset_shake()
	_camera_rig.set_tilt_degrees(0.0)
	var base_position := _camera_rig.position
	var base_rotation := _camera_rig.rotation
	_camera_rig.add_trauma(1.0)
	var elapsed := 0.0
	var steps := 0
	var worst_translation := 0.0
	var worst_degrees := 0.0
	while _camera_rig.get_trauma() > 0.0 and elapsed < GUARD_SECONDS:
		_camera_rig.tick(STEP)
		elapsed += STEP
		steps += 1
		worst_translation = maxf(worst_translation,
				_camera_rig.position.distance_to(base_position))
		worst_degrees = maxf(worst_degrees, _angle_degrees(base_rotation,
				_camera_rig.rotation))
	print("  [1] add_trauma(1.0) → trauma 0.0 en %.4f s (%d pasos de 1/240 s; teórico %.4f s, límite %.1f s)"
			% [elapsed, steps, THEORETICAL_SECONDS, MAX_DECAY_SECONDS])
	expect(_camera_rig.get_trauma() <= 0.0,
			"el trauma no llegó a 0.0: quedó en %.6f tras %.2f s simulados"
					% [_camera_rig.get_trauma(), elapsed])
	expect(elapsed < MAX_DECAY_SECONDS,
			"la sacudida tardó %.4f s en extinguirse y el límite es %.1f s"
					% [elapsed, MAX_DECAY_SECONDS])

	var limit_translation := _camera_rig.max_translation
	var limit_degrees := _camera_rig.max_rotation_degrees
	print("  [2] envolvente en %d muestras a 240 Hz: desplazamiento máximo %.5f m (límite %.5f), rotación máxima %.4f° (límite %.4f°)"
			% [steps, worst_translation, limit_translation, worst_degrees, limit_degrees])
	expect(worst_translation <= limit_translation + ENVELOPE_TOLERANCE,
			"la cámara se apartó %.5f m de su base y el máximo es %.5f m"
					% [worst_translation, limit_translation])
	expect(worst_degrees <= limit_degrees + ENVELOPE_TOLERANCE,
			"la cámara giró %.4f° sobre su base y el máximo es %.4f°"
					% [worst_degrees, limit_degrees])
	# Una envolvente de cero pasaría los dos topes sin sacudir nada.
	expect(worst_translation > 0.0 and worst_degrees > 0.0,
			"la sacudida no movió la cámara: %.6f m y %.6f°"
					% [worst_translation, worst_degrees])


# --- [3] Vuelta exacta a la base ---------------------------------------------------------------

## Al extinguirse el trauma la cámara vuelve a su transformada base, con inclinación
## del hangar en 0 y en [constant TILT_DEGREES].
##
## Las dos inclinaciones no son un lujo: el error que esta fila busca es el del modelo
## que **resta** el último desplazamiento en vez de reescribir la base, y ése solo se
## ve cuando la base no es la identidad.
func _check_return_to_base() -> void:
	for tilt: float in [0.0, TILT_DEGREES]:
		_reset_shake()
		_camera_rig.set_tilt_degrees(tilt)
		var base_position := _camera_rig.position
		var base_rotation := _camera_rig.rotation
		_camera_rig.add_trauma(1.0)
		var elapsed := 0.0
		while _camera_rig.get_trauma() > 0.0 and elapsed < GUARD_SECONDS:
			_camera_rig.tick(STEP)
			elapsed += STEP
		var position_error := _camera_rig.position.distance_to(base_position)
		var rotation_error := _angle_degrees(base_rotation, _camera_rig.rotation)
		print("  [3] inclinación %.0f°: error de posición %.9f m, error de rotación %.9f° (tolerancia %.9f)"
				% [tilt, position_error, rotation_error, BASE_TOLERANCE])
		expect(position_error < BASE_TOLERANCE,
				"con inclinación %.0f° la cámara quedó a %.6f m de su base" % [tilt, position_error])
		expect(rotation_error < BASE_TOLERANCE,
				"con inclinación %.0f° la cámara quedó a %.6f° de su base" % [tilt, rotation_error])
		expect(is_equal_approx(_camera_rig.get_tilt_degrees(), tilt),
				"la inclinación del hangar cambió durante la sacudida: %.3f° en vez de %.3f°"
						% [_camera_rig.get_tilt_degrees(), tilt])
	_camera_rig.set_tilt_degrees(QuadSettings.angle)


# --- [4] Atenuación por distancia --------------------------------------------------------------

## `Events.camera_trauma(0.5, p)` entra entero a 0 m y recortado al piso de 0.15 a
## 160 m (`docs/13` §6). Se mide por el **bus**, que es el camino real: el listener del
## rig es lo que esta fila tiene que demostrar que existe.
func _check_distance_attenuation() -> void:
	_reset_shake()
	var origin := _camera_rig.global_position
	Events.camera_trauma.emit(FAR_AMOUNT, origin)
	var near_trauma := _camera_rig.get_trauma()
	_reset_shake()
	Events.camera_trauma.emit(FAR_AMOUNT, origin + Vector3(FAR_DISTANCE, 0.0, 0.0))
	var far_trauma := _camera_rig.get_trauma()
	_reset_shake()
	Events.camera_trauma.emit(FAR_AMOUNT, Vector3.INF)
	var infinite_trauma := _camera_rig.get_trauma()
	_reset_shake()
	var ceiling := FAR_AMOUNT * CameraRig.MIN_ATTENUATION
	print("  [4] camera_trauma(%.2f): a 0 m aporta %.4f; a %.0f m aporta %.4f (techo %.4f); con posición no finita aporta %.4f"
			% [FAR_AMOUNT, near_trauma, FAR_DISTANCE, far_trauma, ceiling, infinite_trauma])
	expect_near(near_trauma, FAR_AMOUNT, QUALITY_TOLERANCE,
			"a 0 m el trauma tendría que entrar entero")
	expect(far_trauma <= ceiling + QUALITY_TOLERANCE,
			"a %.0f m el trauma aportó %.4f y el techo es %.4f"
					% [FAR_DISTANCE, far_trauma, ceiling])
	expect(far_trauma > 0.0, "a %.0f m el trauma se perdió del todo" % FAR_DISTANCE)
	expect_near(infinite_trauma, FAR_AMOUNT, QUALITY_TOLERANCE,
			"una posición no finita no se atenúa (docs/11 §5.2)")


# --- [5] El horizonte del HUD sigue a la cámara ------------------------------------------------

## Con la sacudida activa, el horizonte que dibuja el `FlightHUD` en modo `camera` está
## donde la cámara sacudida proyecta esa misma dirección del mundo, en los cuatro modos
## de ojo de pez.
##
## `flat` se fija **antes** de sacudir: es una dirección del mundo, no de la cámara. Si
## se recalculara después, la prueba se volvería una tautología —la cámara siempre está
## donde ella dice que está— y no notaría un horizonte atado a la actitud del dron.
func _check_horizon_follows() -> void:
	_saved_horizon_mode = String(GameSettings.hud_config.get("horizon_mode",
			FlightHUD.HORIZON_MODES[0]))
	GameSettings.hud_config["horizon_mode"] = FlightHUD.HORIZON_MODES[0]
	_hud.apply_hud_config()
	_hud.show_component(FlightHUD.Component.HORIZON, true)
	var saved_tilt := _camera_rig.get_tilt_degrees()
	# Con la cámara mirando al frente el horizonte cae en el centro y entra en el campo
	# de los cuatro modos, incluido el rectilíneo de OFF.
	_camera_rig.set_tilt_degrees(0.0)

	for mode: int in _modes():
		var label := _mode_name(mode)
		_reset_shake()
		_camera.set_fisheye_mode(mode)
		await wait_frames(2)
		_sync_transforms()
		expect(_hud.horizon_mode() == FlightHUD.HORIZON_MODES[0],
				"en %s el horizonte no quedó en modo 'camera' (quedó '%s')"
						% [label, _hud.horizon_mode()])
		var forward := -_camera.global_basis.orthonormalized().z
		var flat := Vector3(forward.x, 0.0, forward.z).normalized()
		var before := _camera.project_direction(flat)
		var y_before := _hud.horizon_screen_y(before.x)

		_camera_rig.add_trauma(1.0)
		for _step: int in HORIZON_STEPS:
			_camera_rig.tick(STEP)
		_sync_transforms()
		var after := _camera.project_direction(flat)
		var y_after := _hud.horizon_screen_y(after.x)
		var shift := (after - before).length() if before.is_finite() and after.is_finite() \
				else INF
		var error := absf(y_after - after.y) if is_finite(y_after) and after.is_finite() \
				else INF
		print("  [5] %s: el horizonte se movió %.3f px con la cámara (HUD %.3f → %.3f px, cámara %.3f → %.3f px); diferencia %.4f px"
				% [label, shift, y_before, y_after, before.y, after.y, error])
		expect(before.is_finite() and after.is_finite(),
				"en %s la dirección del horizonte no se proyecta (%s → %s)"
						% [label, str(before), str(after)])
		expect(is_finite(y_before) and is_finite(y_after),
				"en %s el HUD no dibujó horizonte (%.3f → %.3f)" % [label, y_before, y_after])
		expect(shift >= HORIZON_MIN_SHIFT,
				"en %s la sacudida movió el horizonte solo %.4f px: la fila no mide nada"
						% [label, shift])
		expect(error < HORIZON_TOLERANCE,
				"en %s el horizonte del HUD quedó %.4f px del que dice la cámara (tolerancia %.1f)"
						% [label, error, HORIZON_TOLERANCE])
		await _check_faces_follow(label, mode)
		_reset_shake()

	_camera.set_fisheye_mode(_saved_fisheye)
	_camera_rig.set_tilt_degrees(saved_tilt)
	await wait_frames(2)


## Las caras del ojo de pez siguen a la cámara sacudida.
##
## Es la otra mitad de «la sacudida mueve la cámara de verdad» (`docs/13` §6): el
## horizonte del HUD la sigue porque proyecta con ella, y la **imagen** la sigue porque
## las sub-cámaras de las `SubViewport` copian su transformada global en cada frame
## (`fpv_camera.gd`, `SYNC_PRIORITY`). Se mide después de un frame de proceso, que es
## cuando esa copia ocurre; el [CameraRig] tiene el `_process` apagado, así que la
## sacudida no avanza mientras tanto.
func _check_faces_follow(label: String, mode: int) -> void:
	if mode == Graphics.FisheyeMode.OFF:
		return
	var offset := _camera_rig.translation_offset().length()
	await wait_frames(1)
	var faces := _camera.get_fisheye_viewports()
	var counted := 0
	var worst := 0.0
	for viewport: SubViewport in faces:
		var face := viewport.get_camera_3d()
		if face == null:
			continue
		counted += 1
		worst = maxf(worst, face.global_position.distance_to(_camera.global_position))
	print("  [5] %s: %d cara(s) del ojo de pez siguen a la cámara desplazada %.5f m; desvío máximo %.9f m"
			% [label, counted, offset, worst])
	expect(counted > 0, "en %s no hay sub-cámaras que sincronizar" % label)
	expect(offset > 0.0, "en %s la cámara no estaba desplazada al medir las caras" % label)
	expect(worst <= BASE_TOLERANCE,
			"en %s una cara del ojo de pez quedó a %.6f m de la cámara: no sigue la sacudida"
					% [label, worst])


# --- [6] Techo del trauma ----------------------------------------------------------------------

## Sumar trauma 30 veces en un frame no pasa de 1.0. Es lo que evita que una andanada
## de escombros deje la cámara sacudiéndose diez segundos.
func _check_burst_ceiling() -> void:
	_reset_shake()
	for _index: int in BURST_ADDS:
		_camera_rig.add_trauma(BURST_AMOUNT)
	var trauma := _camera_rig.get_trauma()
	print("  [6] %d × add_trauma(%.2f) en un frame → trauma %.6f (techo %.2f)"
			% [BURST_ADDS, BURST_AMOUNT, trauma, CameraRig.MAX_TRAUMA])
	expect(trauma <= CameraRig.MAX_TRAUMA,
			"el trauma llegó a %.6f y el techo es %.2f" % [trauma, CameraRig.MAX_TRAUMA])
	expect_near(trauma, CameraRig.MAX_TRAUMA, QUALITY_TOLERANCE,
			"con 30 sumas de 0.5 el trauma tendría que quedar clavado en el techo")
	_reset_shake()


# --- [7] La señal publicada en el HUD ----------------------------------------------------------

## El `FlightHUD` muestra la calidad de señal que publica [method DroneRig._feed_hud]
## desde el overlay, con las barras que le corresponden.
##
## Los cuatro casos son los de `docs/13` §7: casco al 40 %, EMP entero, los dos a la
## vez, y la vuelta a la señal limpia tras una reaparición.
func _check_published_signal() -> void:
	_reset_shake()
	Events.hull_changed.emit(0.4)
	await _publish()
	_expect_signal(FPVOverlay.quality_for(0.6, 0.0), 3, "casco al 40 %")

	Events.hull_changed.emit(1.0)
	_overlay.trigger_emp(GLITCH_SECONDS)
	await _publish()
	_expect_signal(FPVOverlay.quality_for(0.0, 1.0), 2, "EMP entero con el casco sano")

	Events.hull_changed.emit(0.4)
	await _publish()
	_expect_signal(FPVOverlay.quality_for(0.6, 1.0), 1, "casco al 40 % y EMP entero")

	_hull.restore()
	Events.drone_respawned.emit(1.0)
	await _publish()
	_expect_signal(1.0, 4, "tras reaparecer con el casco entero")
	expect(HUDSignalIndicator.CRITICAL_QUALITY <= 0.25,
			"el indicador parpadea desde %.2f y tendría que hacerlo recién bajo 0.25"
					% HUDSignalIndicator.CRITICAL_QUALITY)


func _publish() -> void:
	await wait_physics(2)


func _expect_signal(expected: float, bars: int, label: String) -> void:
	var published := _hud.signal_quality()
	var lit := _signal.lit_bars()
	print("  [7] %s: señal %.4f (esperada %.4f), %d barra(s) (esperadas %d)"
			% [label, published, expected, lit, bars])
	expect_near(published, expected, QUALITY_TOLERANCE,
			"con %s el FlightHUD publica una señal distinta de la del overlay" % label)
	expect(lit == bars, "con %s el indicador encendió %d barras y no %d" % [label, lit, bars])


# --- [8] Determinismo --------------------------------------------------------------------------

## Dos [CameraRig] con la misma semilla recorren exactamente la misma trayectoria, y uno
## con otra semilla se separa. Lo primero es lo que hace repetible una corrida; lo
## segundo es lo que demuestra que la semilla no es decorativa.
func _check_determinism() -> void:
	var host := Node3D.new()
	host.name = "SeedHost"
	add_child(host)
	var twins: Array[CameraRig] = [_make_rig(host), _make_rig(host), _make_rig(host)]
	twins[2].set_noise_seed(OTHER_SEED)
	for rig: CameraRig in twins:
		rig.set_process(false)
		rig.add_trauma(1.0)
	var same := 0.0
	var different := 0.0
	for _step: int in DETERMINISM_STEPS:
		for rig: CameraRig in twins:
			rig.tick(STEP)
		same = maxf(same, twins[0].position.distance_to(twins[1].position))
		same = maxf(same, (twins[0].rotation - twins[1].rotation).length())
		different = maxf(different, twins[0].position.distance_to(twins[2].position))
	print("  [8] semilla %d: dos rigs iguales divergen %.9f en %d pasos; con la semilla %d la diferencia llega a %.5f m"
			% [twins[0].noise_seed(), same, DETERMINISM_STEPS, OTHER_SEED, different])
	expect(twins[0].noise_seed() == twins[1].noise_seed(),
			"dos rigs nuevos nacieron con semillas distintas: %d y %d"
					% [twins[0].noise_seed(), twins[1].noise_seed()])
	expect(same <= DETERMINISM_TOLERANCE,
			"dos rigs con la misma semilla se separaron %.9f (tolerancia %.9f)"
					% [same, DETERMINISM_TOLERANCE])
	expect(different > DETERMINISM_TOLERANCE,
			"cambiar la semilla no cambió la trayectoria: la semilla no se está usando")
	host.queue_free()


func _make_rig(host: Node3D) -> CameraRig:
	var rig := CameraRig.new()
	host.add_child(rig)
	return rig


# --- [9] Fugas ---------------------------------------------------------------------------------

## Treinta ciclos de sacudida completos no dejan ni un nodo de más. El [CameraRig] no
## instancia nada, así que un crecimiento acá querría decir que el listener del bus se
## reconecta o que alguien está creando un ruido por sacudida.
func _check_leaks() -> void:
	# Los rigs de la fila 8 y las sub-viewports de la fila 5 se liberan con
	# `queue_free()`: sin este respiro entrarían en la cuenta como fuga ajena.
	await wait_frames(5)
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for _cycle: int in LEAK_CYCLES:
		Events.camera_trauma.emit(0.6, _camera_rig.global_position)
		for _step: int in 12:
			_camera_rig.tick(STEP)
		_reset_shake()
	await wait_frames(5)
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  [9] %d ciclos de sacudida: nodos %d → %d, huérfanos %d → %d"
			% [LEAK_CYCLES, nodes_before, nodes_after, orphans_before, orphans_after])
	expect(absi(nodes_after - nodes_before) <= LEAK_TOLERANCE,
			"los nodos pasaron de %d a %d" % [nodes_before, nodes_after])
	expect(absi(orphans_after - orphans_before) <= LEAK_TOLERANCE,
			"los huérfanos pasaron de %d a %d" % [orphans_before, orphans_after])


# --- Utilidades --------------------------------------------------------------------------------

## Deja la cámara quieta y en su base antes de cada fila.
##
## Usa [method CameraRig.clear_trauma] y no el decaimiento: con la prueba negativa
## —decaimiento en 0— esperar a que el trauma baje colgaría el check, y lo que esa
## prueba tiene que hacer es **fallar** en las filas 1 y 3, no quedarse trabada.
func _reset_shake() -> void:
	_camera_rig.clear_trauma()


## Empuja la transformada del rig y de la cámara al servidor. Sin esto,
## `global_basis` sigue siendo la del frame anterior y el horizonte se mediría contra
## una cámara que todavía no se movió.
func _sync_transforms() -> void:
	_camera_rig.force_update_transform()
	_camera.force_update_transform()


## Ángulo entre dos rotaciones expresadas en ángulos de Euler, en grados.
func _angle_degrees(from: Vector3, to: Vector3) -> float:
	var delta := Basis.from_euler(from).inverse() * Basis.from_euler(to)
	return rad_to_deg(delta.orthonormalized().get_rotation_quaternion().get_angle())


func _modes() -> Array[int]:
	return [Graphics.FisheyeMode.OFF, Graphics.FisheyeMode.FAST,
			Graphics.FisheyeMode.FAST_WIDE, Graphics.FisheyeMode.FULL]


func _mode_name(mode: int) -> String:
	match mode:
		Graphics.FisheyeMode.OFF:
			return "OFF"
		Graphics.FisheyeMode.FAST:
			return "FAST"
		Graphics.FisheyeMode.FAST_WIDE:
			return "FAST_WIDE"
		Graphics.FisheyeMode.FULL:
			return "FULL"
	return "modo %d" % mode
