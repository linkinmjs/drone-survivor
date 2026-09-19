## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del menú de controles y del asistente de calibración
## (`docs/04` §4.5, §4.6 y §9; `docs/15` §3 y §4).
##
## Recorre lo que haría un jugador con un mando en la mano, pero con el mando
## sintetizado: abre la pantalla de controles, asigna un botón a `fire` y una
## banda de eje a `mode_horizon` desde el [BindingPopup], borra el binding de
## `respawn`, corre los catorce pasos de la calibración con valores sintéticos
## —incluida una inversión—, comprueba que todo se relee del archivo, restablece
## el mando con confirmación y verifica que `StickNavigation` quedó libre.
##
## **Los dos dispositivos del joypad sintético.** `Input` guarda el estado de los
## ejes con una clave que combina eje y dispositivo, así que hay que inyectar en
## los dos sentidos según lo que se esté probando:
##
## - [constant CAPTURE_DEVICE] (−1, «cualquier dispositivo», `docs/02` §4.1) para
##   los eventos que captura el popup y que tienen que casar con el `InputMap`.
## - [constant READ_DEVICE] (0) para los valores que se leen después con
##   `Input.get_joy_axis()`: la calibración y `Controls.get_flight_input()`. Es
##   el mismo criterio que usa `tools/settings_check.gd`.
##
## **No toca la configuración del jugador**: apunta `Global.config_dir` a un
## directorio temporal propio de este proceso —`run_checks` y una corrida a mano
## pueden solaparse— y lo borra al terminar. El snapshot de `CheckRunner` sobre
## `user://config` queda como segunda red de seguridad.
extends CheckRunner

const CONTROLS_SCENE: String = "res://gui/options_menu/controls_menu/controls_menu.tscn"

## Prefijo del directorio de trabajo; el nombre real lleva el id del proceso.
const TEMP_DIR_PREFIX: String = "user://config_controls_tmp"

## Directorio real del jugador, que esta prueba no puede tocar.
const PLAYER_DIR: String = "user://config"

## Dispositivo de los eventos que captura el popup: «cualquiera» (`docs/02` §4.1).
const CAPTURE_DEVICE: int = -1

## Dispositivo cuyos ejes crudos lee `Input.get_joy_axis()`.
const READ_DEVICE: int = 0

## Botón que se asigna a `fire`; no lo usa ningún binding de fábrica.
const FIRE_BUTTON: int = 5

## Eje que se asigna a `mode_horizon`.
const HORIZON_AXIS: int = 4

## Banda esperada tras mover las manijas del [GUIControllerAxisRange].
const HORIZON_BAND: Vector2 = Vector2(0.55, 0.90)

## Plazo de cada espera intermedia, medido contra el reloj y no contra frames.
const STEP_TIMEOUT_SECONDS: float = 15.0

## Margen para que terminen los fundidos de apertura de los modales.
const SETTLE_SECONDS: float = 0.25

## Los cuatro ejes físicos que el primer paso de la calibración debe detectar,
## en el orden de `Controls.FLIGHT_AXES` (`docs/02` §4.2).
const SWEEP_AXES: Array[int] = [1, 0, 3, 2]

## Valores sintéticos de los doce pasos por eje: `[eje, valor]` en el orden de
## `CalibrationMenu.STEPS`, a partir del tercero. El acelerador y el pitch se
## mueven al revés a propósito, para que el asistente detecte la inversión.
const CAL_SAMPLES: Array[Array] = [
	[1, -1.0],  # 3. acelerador arriba  (eje invertido: arriba da −1)
	[1, 0.8],   # 4. acelerador abajo
	[1, -0.25], # 5. acelerador al centro (reposo descentrado a propósito)
	[0, 1.0],   # 6. yaw derecha
	[0, -1.0],  # 7. yaw izquierda
	[0, 0.0],   # 8. yaw al centro
	[3, -1.0],  # 9. pitch adelante (también invertido)
	[3, 1.0],   # 10. pitch atrás
	[3, 0.0],   # 11. pitch al centro
	[2, 1.0],   # 12. roll derecha
	[2, -1.0],  # 13. roll izquierda
	[2, 0.0],   # 14. roll al centro
]

## Calibración que tiene que quedar guardada: eje, mínimo, centro, máximo e
## inversión, deducidos de [constant CAL_SAMPLES].
const CAL_EXPECTED: Dictionary[StringName, Array] = {
	&"throttle": [1, -1.0, -0.25, 0.8, true],
	&"yaw": [0, -1.0, 0.0, 1.0, false],
	&"pitch": [3, -1.0, 0.0, 1.0, true],
	&"roll": [2, -1.0, 0.0, 1.0, false],
}

## Zona muerta con reescalado de `Controls`, para predecir `get_flight_input()`.
const DEADZONE: float = 0.02

var _temp_dir: String = ""
var _menu: ControlsMenu = null
var _controls_saved_config_dir: String = ""
var _controls_saved_log_path: String = ""
var _original_assume_joypad: bool = false
var _original_suspended: bool = false
var _player_files_before: PackedStringArray = PackedStringArray()
var _restored: bool = false


func _run() -> void:
	_temp_dir = "%s_%d" % [TEMP_DIR_PREFIX, OS.get_process_id()]
	_controls_saved_config_dir = Global.config_dir
	_controls_saved_log_path = Global.log_path
	_original_assume_joypad = Controls.assume_joypad
	_original_suspended = StickNavigation.suspended
	_player_files_before = _player_files()
	_purge_temp()
	Global.config_dir = _temp_dir
	Global.log_path = _temp_dir.path_join("output.log")
	# El check simula un mando: sin esto `Controls` se comportaría como si no
	# hubiera ninguno y `get_flight_input()` devolvería un diccionario vacío.
	Controls.assume_joypad = true
	StickNavigation.suspended = false
	UI.set_input_kind(UI.InputKind.KEYBOARD)
	var _discard := Controls.load_input_map(true)

	await _open_menu()
	if _menu == null:
		return
	await _check_button_binding()
	await _check_axis_binding()
	await _check_cleared_binding()
	await _check_calibration()
	await _check_flight_input()
	_check_persistence()
	await _check_reset()
	_check_sticks_free()
	await _close()
	_check_player_dir_untouched()


## Devuelve el entorno a su estado original antes de que `CheckRunner` cierre el
## proceso. Se ejecuta también si el check falló o si expiró el timeout.
func finish() -> void:
	_restore_environment()
	super()


func _restore_environment() -> void:
	if _restored:
		return
	_restored = true
	StickNavigation.suspended = _original_suspended
	Controls.assume_joypad = _original_assume_joypad
	_purge_temp()
	if not _controls_saved_log_path.is_empty():
		Global.log_path = _controls_saved_log_path
	if not _controls_saved_config_dir.is_empty():
		Global.config_dir = _controls_saved_config_dir
	Global.startup_errors.clear()


# --- (a) La pantalla abre, enfoca y no muestra claves crudas ----------------------------------

func _open_menu() -> void:
	var packed := load(CONTROLS_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % CONTROLS_SCENE)
		return
	_menu = packed.instantiate() as ControlsMenu
	if _menu == null:
		fail("%s no instancia un ControlsMenu" % CONTROLS_SCENE)
		return
	add_child(_menu)
	var focused := await _wait_until(func() -> bool: return _focus_name() == "DeviceOption")
	expect(UI.get_active_context() == _menu, "el menú de controles es el contexto activo")
	expect(focused, "el foco inicial cae en el selector de mando (quedó en %s)" % _focus_name())
	expect(_menu.binding_row(&"fire") != null and Controls.action_list.size() == 13,
			"hay una fila por cada una de las 13 acciones asignables")
	expect(_menu.axis_bar(7) != null and _menu.button_dot(15) != null,
			"la vista en vivo tiene 8 barras de eje y 16 testigos de botón")
	await _settle()
	_check_no_raw_keys(_menu, "el menú de controles")


# --- (b) Asignar un botón ---------------------------------------------------------------------

func _check_button_binding() -> void:
	var popup := await _open_popup(&"fire")
	if popup == null:
		return
	expect(get_viewport().gui_get_focus_owner() == popup.button_for(&"CTRL_LISTEN"),
			"el popup enfoca el botón Escuchar")
	await _press(popup.button_for(&"CTRL_LISTEN"))
	expect(popup.is_listening(), "el popup queda escuchando el mando")
	expect(StickNavigation.suspended,
			"mientras escucha, StickNavigation queda suspendido (docs/04 §3.3)")

	# Prueba negativa: solo los eventos de joypad cuentan como binding. Una tecla
	# tiene que dejar el popup escuchando, no atar `fire` a algo que no es mando.
	var band_before := Vector2(popup.action.axis_min, popup.action.axis_max)
	await _tap_key(KEY_J)
	expect(popup.is_listening(),
			"prueba negativa: una tecla no se captura como binding de mando")
	expect(Vector2(popup.action.axis_min, popup.action.axis_max).is_equal_approx(band_before),
			"prueba negativa: la tecla tampoco toca el binding que ya tenia la accion")
	print("  prueba negativa (tecla J mientras escucha): sigue escuchando = %s"
			% str(popup.is_listening()))

	await _tap_joy_button(FIRE_BUTTON)
	expect(not popup.is_listening(), "capturar un botón deja de escuchar")
	expect(not StickNavigation.suspended,
			"al dejar de escuchar, StickNavigation se restaura")
	expect(popup.action.bound and popup.action.type == ControllerAction.Type.BUTTON
			and popup.action.button == FIRE_BUTTON,
			"el popup captura el botón %d (quedó '%s')"
					% [FIRE_BUTTON, GUIControllerBinding.describe(popup.action)])

	await _press(popup.button_for(&"UI_CONFIRM"))
	var closed := await _wait_until(func() -> bool: return _menu.active_popup() == null)
	expect(closed, "confirmar cierra el popup")

	var fire := Controls.get_action(&"fire")
	expect(fire != null and fire.bound and fire.type == ControllerAction.Type.BUTTON
			and fire.button == FIRE_BUTTON,
			"Controls.action_list guarda el botón %d en fire" % FIRE_BUTTON)
	expect(_joy_button_of(&"fire") == FIRE_BUTTON,
			"el InputMap deja fire en el botón %d (quedó %d)"
					% [FIRE_BUTTON, _joy_button_of(&"fire")])
	var row := _menu.binding_row(&"fire")
	var refocused := await _wait_until(func() -> bool: return row != null and row.has_focus())
	expect(refocused, "el foco vuelve a la fila de fire (quedó en %s)" % _focus_name())


# --- (c) Asignar una banda de eje --------------------------------------------------------------

func _check_axis_binding() -> void:
	var popup := await _open_popup(&"mode_horizon")
	if popup == null:
		return
	await _press(popup.button_for(&"CTRL_LISTEN"))
	await _move_captured_axis(HORIZON_AXIS, 0.9)
	expect(not popup.is_listening(), "un eje pasado de 0.5 también corta la escucha")
	expect(popup.action.bound and popup.action.type == ControllerAction.Type.AXIS
			and popup.action.axis == HORIZON_AXIS,
			"el popup captura el eje %d (quedó '%s')"
					% [HORIZON_AXIS, GUIControllerBinding.describe(popup.action)])

	var band := popup.range_control()
	if band == null:
		fail("el popup de un binding de eje no muestra el control de banda")
		return
	expect(band.has_meta(&"stick_value_control"),
			"el control de banda lleva la meta stick_value_control (docs/04 §5)")
	expect(band.band().is_equal_approx(Vector2(0.5, 1.0)),
			"la banda propuesta va de 0.5 al extremo movido (quedó %s)" % str(band.band()))

	band.grab_focus()
	await wait_frames(2)
	# La manija activa arranca en el extremo alto: dos pasos de 0.05 lo bajan a 0.90.
	await _send_action(&"ui_left")
	await _send_action(&"ui_left")
	# Aceptar cambia de manija; un paso a la derecha sube el extremo bajo a 0.55.
	await _send_action(&"ui_accept")
	await _send_action(&"ui_right")
	expect(band.band().is_equal_approx(HORIZON_BAND),
			"las dos manijas se mueven con ui_left / ui_right (banda %s, esperada %s)"
					% [str(band.band()), str(HORIZON_BAND)])

	await _press(popup.button_for(&"UI_CONFIRM"))
	var closed := await _wait_until(func() -> bool: return _menu.active_popup() == null)
	expect(closed, "confirmar cierra el popup del binding de eje")

	var action := Controls.get_action(&"mode_horizon")
	expect(action != null and action.type == ControllerAction.Type.AXIS
			and action.axis == HORIZON_AXIS
			and absf(action.axis_min - HORIZON_BAND.x) < 0.001
			and absf(action.axis_max - HORIZON_BAND.y) < 0.001,
			"Controls guarda la banda [%.2f, %.2f] del eje %d"
					% [HORIZON_BAND.x, HORIZON_BAND.y, HORIZON_AXIS])
	expect(_joy_axis_of(&"mode_horizon") == HORIZON_AXIS,
			"el InputMap deja mode_horizon en el eje %d" % HORIZON_AXIS)
	expect_near(InputMap.action_get_deadzone(&"mode_horizon"), HORIZON_BAND.x, 0.001,
			"el extremo cercano al centro hace de zona muerta de la acción")


# --- (d) Borrar un binding ---------------------------------------------------------------------

func _check_cleared_binding() -> void:
	var before := Controls.get_action(&"respawn")
	expect(before != null and before.bound, "respawn arranca con su botón de fábrica")
	var popup := await _open_popup(&"respawn")
	if popup == null:
		return
	await _press(popup.button_for(&"CTRL_CLEAR"))
	expect(popup.cleared and not popup.action.bound, "Borrar deja la acción sin asignar")
	await _press(popup.button_for(&"UI_CONFIRM"))
	var closed := await _wait_until(func() -> bool: return _menu.active_popup() == null)
	expect(closed, "confirmar cierra el popup tras borrar")

	var action := Controls.get_action(&"respawn")
	expect(action != null and not action.bound, "Controls deja respawn sin asignar")
	expect(_joy_button_of(&"respawn") < 0,
			"el InputMap se queda sin el evento de joypad de respawn")
	expect(_has_key_event(&"respawn", KEY_R),
			"borrar el binding de mando no toca el atajo de teclado de docs/02 §4.3")
	expect(GUIControllerBinding.describe(action) == tr("CTRL_UNBOUND"),
			"la fila muestra CTRL_UNBOUND")


# --- (e) Los catorce pasos de la calibración ----------------------------------------------------

func _check_calibration() -> void:
	var calibrate := _menu.control_for(&"CTRL_CALIBRATE") as Button
	if calibrate == null:
		fail("el menú no expone el botón de calibrar")
		return
	await _press(calibrate)
	var wizard := await _wait_for_wizard()
	if wizard == null:
		fail("el botón Calibrar no abre el asistente")
		return
	expect(UI.get_active_context() == wizard, "el asistente es el contexto activo")
	expect(StickNavigation.suspended,
			"durante el asistente StickNavigation queda suspendido (docs/04 §4.6)")
	expect(CalibrationMenu.STEPS.size() == 14, "el asistente tiene los 14 pasos de docs/04 §4.6")

	# Paso 1: las cuatro esquinas de los dos sticks.
	await _sweep_corners()
	var detected := await _wait_for_step(wizard, 1)
	expect(detected, "las esquinas detectan los cuatro ejes (quedó en el paso %d)"
			% (wizard.current_step() + 1))

	# Paso 2: reposo de los cuatro ejes detectados.
	for axis: int in SWEEP_AXES:
		_write_axis(axis, 0.0)
	await wait_frames(2)
	var centered := await _wait_for_step(wizard, 2)
	expect(centered, "soltar los sticks registra el centro (quedó en el paso %d)"
			% (wizard.current_step() + 1))

	# Pasos 3 a 14: extremos y centro de cada eje de vuelo.
	for index: int in CAL_SAMPLES.size():
		var sample: Array = CAL_SAMPLES[index]
		_write_axis(int(sample[0]), float(sample[1]))
		await wait_frames(2)
		var advanced := await _wait_for_step(wizard, index + 3)
		if not advanced:
			fail("el paso %d no se confirmó con el eje %d en %.2f"
					% [index + 3, int(sample[0]), float(sample[1])])
			return

	expect(wizard.has_saved(), "el asistente guarda la calibración al terminar")
	var gone := await _wait_until(func() -> bool: return _find_wizard() == null)
	expect(gone, "el asistente vuelve solo al menú de controles")
	expect(not StickNavigation.suspended,
			"al cerrarse el asistente, StickNavigation vuelve a false")

	for axis_name: StringName in CAL_EXPECTED:
		_expect_calibration(axis_name, "tras el asistente")
		var cal := Controls.get_axis_calibration(axis_name)
		print("  calibrado %s: eje %d  min %.2f  centro %.2f  max %.2f  invertido %s"
				% [axis_name, int(cal["axis"]), float(cal["min"]), float(cal["center"]),
				float(cal["max"]), str(cal["inverted"])])
	# La inversión también da vuelta el signo de las acciones del `InputMap`.
	expect(_motion_value(&"throttle_up") > 0.0,
			"un acelerador invertido da vuelta el signo de throttle_up en el InputMap")
	expect(_motion_value(&"yaw_left") < 0.0,
			"un eje sin invertir conserva los signos de docs/02 §4.2")


func _sweep_corners() -> void:
	for value: float in [0.95, -0.95, 0.0]:
		for axis: int in SWEEP_AXES:
			_write_axis(axis, value)
		await wait_frames(3)


## Compara la calibración guardada de un eje contra [constant CAL_EXPECTED].
func _expect_calibration(axis_name: StringName, when: String) -> void:
	var wanted: Array = CAL_EXPECTED[axis_name]
	var cal := Controls.get_axis_calibration(axis_name)
	expect(int(cal["axis"]) == int(wanted[0]),
			"%s: %s queda en el eje físico %d (quedó %d)"
					% [when, axis_name, int(wanted[0]), int(cal["axis"])])
	expect_near(float(cal["min"]), float(wanted[1]), 0.01, "%s: mínimo de %s" % [when, axis_name])
	expect_near(float(cal["center"]), float(wanted[2]), 0.01,
			"%s: centro de %s" % [when, axis_name])
	expect_near(float(cal["max"]), float(wanted[3]), 0.01, "%s: máximo de %s" % [when, axis_name])
	expect(bool(cal["inverted"]) == bool(wanted[4]),
			"%s: la inversión de %s es %s" % [when, axis_name, str(wanted[4])])


# --- (e bis) `get_flight_input()` aplica la calibración -----------------------------------------

## Con la calibración que dejó el asistente, `get_flight_input()` tiene que dar
## +1 con el acelerador arriba aunque el eje devuelva −1, y reescalar el tramo
## corto del recorrido entre el centro descentrado y cada extremo.
func _check_flight_input() -> void:
	await _write_axes({1: -1.0, 0: 0.5, 3: 1.0, 2: 0.01})
	var input := Controls.get_flight_input()
	expect(input.size() == 4, "get_flight_input() devuelve los cuatro ejes de vuelo")
	expect_near(float(input["throttle"]), 1.0, 0.001,
			"el acelerador invertido da +1.0 con el eje crudo en −1.0")
	expect_near(float(input["pitch"]), -1.0, 0.001, "el pitch invertido da vuelta el signo")
	expect_near(float(input["yaw"]), _rescaled(0.5), 0.001,
			"el yaw sin invertir conserva el signo y aplica la zona muerta")
	expect_near(float(input["roll"]), 0.0, 0.001,
			"una deflexión de 0.01 cae dentro de la zona muerta")

	# Medio recorrido del lado corto del acelerador: centro −0.25, máximo 0.8.
	await _write_axes({1: 0.275})
	input = Controls.get_flight_input()
	expect_near(float(input["throttle"]), -_rescaled(0.5), 0.001,
			"a medio camino entre el centro calibrado y el máximo el acelerador da −0.5")
	await _write_axes({1: 0.8})
	input = Controls.get_flight_input()
	expect_near(float(input["throttle"]), -1.0, 0.001,
			"el máximo calibrado del acelerador invertido da −1.0")


## Valor que devuelve `Controls` tras aplicar su zona muerta con reescalado.
func _rescaled(value: float) -> float:
	return signf(value) * (absf(value) - DEADZONE) / (1.0 - DEADZONE)


# --- (g) Todo se relee del archivo --------------------------------------------------------------

func _check_persistence() -> void:
	Controls.save_input_map()
	var error_key := Controls.load_input_map()
	expect(error_key.is_empty(),
			"InputMap.cfg recién escrito se relee sin error (devolvió '%s')" % error_key)
	expect(FileAccess.file_exists(Global.config_path(Controls.CONFIG_FILE)),
			"la prueba escribe InputMap.cfg dentro del directorio temporal")

	var fire := Controls.get_action(&"fire")
	expect(fire != null and fire.type == ControllerAction.Type.BUTTON
			and fire.button == FIRE_BUTTON,
			"el botón de fire sobrevive a guardar y recargar")
	var horizon := Controls.get_action(&"mode_horizon")
	expect(horizon != null and horizon.type == ControllerAction.Type.AXIS
			and horizon.axis == HORIZON_AXIS
			and absf(horizon.axis_min - HORIZON_BAND.x) < 0.001
			and absf(horizon.axis_max - HORIZON_BAND.y) < 0.001,
			"la banda de eje de mode_horizon sobrevive a guardar y recargar")
	var respawn := Controls.get_action(&"respawn")
	expect(respawn != null and not respawn.bound,
			"una acción borrada sigue sin asignar tras recargar")
	for axis_name: StringName in CAL_EXPECTED:
		_expect_calibration(axis_name, "tras recargar")


# --- (f) Restablecer con confirmación -----------------------------------------------------------

func _check_reset() -> void:
	var reset := _menu.control_for(&"CTRL_RESET") as Button
	if reset == null:
		fail("el menú no expone el botón de restablecer")
		return
	await _press(reset)
	var opened := await _wait_until(func() -> bool: return UI.has_modal())
	expect(opened, "Restablecer pide confirmación (CTRL_RESET_CONFIRM)")
	if not opened:
		return
	await _settle()
	var confirm := _modal_button("UI_CONFIRM")
	if confirm == null:
		fail("la confirmación de restablecer no tiene botón UI_CONFIRM")
		return
	await _press(confirm)
	var closed := await _wait_until(func() -> bool: return not UI.has_modal())
	expect(closed, "la confirmación se cierra al aceptar")

	var fire := Controls.get_action(&"fire")
	expect(fire != null and fire.type == ControllerAction.Type.AXIS and fire.axis == 5
			and absf(fire.axis_min - 0.35) < 0.001,
			"el reset devuelve fire a su gatillo de fábrica (docs/02 §4.3)")
	var respawn := Controls.get_action(&"respawn")
	expect(respawn != null and respawn.bound and respawn.button == 4,
			"el reset devuelve respawn a su botón de fábrica")
	var throttle := Controls.get_axis_calibration(&"throttle")
	expect(int(throttle["axis"]) == 1 and not bool(throttle["inverted"])
			and is_equal_approx(float(throttle["center"]), 0.0),
			"el reset borra la calibración del acelerador")
	var reloaded := Controls.load_input_map()
	var respawn_after := Controls.get_action(&"respawn")
	expect(reloaded.is_empty() and respawn_after != null and respawn_after.bound
			and respawn_after.button == 4,
			"el reset también queda escrito en el archivo")


# --- (h) e (i) Estado final ---------------------------------------------------------------------

func _check_sticks_free() -> void:
	expect(not StickNavigation.suspended,
			"al terminar el recorrido StickNavigation.suspended vuelve a false")


func _close() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	await wait_frames(4)
	expect(not UI.has_modal(), "no queda ningún modal abierto al terminar")


func _check_player_dir_untouched() -> void:
	expect(_player_files() == _player_files_before,
			"la prueba no agrega ni quita archivos en %s (antes %s, ahora %s)"
					% [PLAYER_DIR, str(_player_files_before), str(_player_files())])


# --- Popup ---------------------------------------------------------------------------------------

## Enfoca la fila de una acción, la activa y espera a que aparezca el popup.
func _open_popup(action_name: StringName) -> BindingPopup:
	var row := _menu.binding_row(action_name)
	if row == null:
		fail("el menú no tiene fila para la acción %s" % action_name)
		return null
	row.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")
	var popup := await _wait_until_popup()
	expect(popup != null, "activar la fila de %s abre el popup de asignación" % action_name)
	if popup != null:
		await _settle()
	return popup


func _wait_until_popup() -> BindingPopup:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var popup := _menu.active_popup()
		if popup != null 				and get_viewport().gui_get_focus_owner() == popup.button_for(&"CTRL_LISTEN"):
			return popup
		await get_tree().process_frame
	return null


# --- Asistente -----------------------------------------------------------------------------------

func _find_wizard() -> CalibrationMenu:
	if not is_instance_valid(_menu):
		return null
	for node: Node in _menu.find_children("*", "CalibrationMenu", true, false):
		if node.is_inside_tree() and not node.is_queued_for_deletion():
			return node as CalibrationMenu
	return null


func _wait_for_wizard() -> CalibrationMenu:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var wizard := _find_wizard()
		if wizard != null and wizard.is_running():
			return wizard
		await get_tree().process_frame
	return null


func _wait_for_step(wizard: CalibrationMenu, step: int) -> bool:
	return await _wait_until(func() -> bool: return wizard.current_step() >= step)


# --- Joypad sintético ----------------------------------------------------------------------------

## Manda un evento de eje con [constant CAPTURE_DEVICE]: es el que captura el
## popup y el que casa con las entradas del `InputMap` (`docs/02` §4.1).
func _move_captured_axis(axis: int, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = CAPTURE_DEVICE
	motion.axis = axis as JoyAxis
	motion.axis_value = value
	Input.parse_input_event(motion)
	await wait_frames(3)


## Pulsa y suelta un botón del joypad sintético.
func _tap_joy_button(index: int) -> void:
	for pressed: bool in [true, false]:
		var button := InputEventJoypadButton.new()
		button.device = CAPTURE_DEVICE
		button.button_index = index as JoyButton
		button.pressed = pressed
		Input.parse_input_event(button)
		await wait_frames(2)


## Pulsa y suelta una tecla. Sirve para la prueba negativa: el popup solo puede
## capturar eventos de mando.
func _tap_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		key.keycode = code
		key.pressed = pressed
		Input.parse_input_event(key)
		await wait_frames(2)
	UI.set_input_kind(UI.InputKind.KEYBOARD)


## Fija el valor crudo de un eje en [constant READ_DEVICE], que es el que leen
## `Input.get_joy_axis()`, la calibración y `Controls.get_flight_input()`.
func _write_axis(axis: int, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = READ_DEVICE
	motion.axis = axis as JoyAxis
	motion.axis_value = value
	Input.parse_input_event(motion)


func _write_axes(values: Dictionary) -> void:
	for axis: int in values:
		_write_axis(axis, float(values[axis]))
	await wait_frames(3)


# --- `InputMap` ----------------------------------------------------------------------------------

func _joy_button_of(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return int((event as InputEventJoypadButton).button_index)
	return -1


func _joy_axis_of(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return int((event as InputEventJoypadMotion).axis)
	return -1


func _motion_value(action: StringName) -> float:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return (event as InputEventJoypadMotion).axis_value
	return 0.0


func _has_key_event(action: StringName, code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false


# --- Utilidades ------------------------------------------------------------------------------------

## Enfoca un botón y lo activa con la misma acción que usaría el jugador.
func _press(button: Button) -> void:
	if button == null:
		fail("se pidió activar un botón que no existe")
		return
	button.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")


## Inyecta una acción de interfaz como evento, para que llegue al control con foco.
func _send_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)
	await wait_frames(1)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await wait_frames(2)


## Botón de la confirmación modal por su clave de traducción, o `null`.
func _modal_button(key: String) -> Button:
	for overlay: Node in get_tree().root.find_children("*", "ConfirmOverlay", true, false):
		for button: Node in overlay.find_children("*", "Button", true, false):
			if (button as Button).text == key:
				return button as Button
	return null


func _focus_name() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	return str(focus.name) if focus != null else "<sin foco>"


func _settle() -> void:
	await get_tree().create_timer(SETTLE_SECONDS).timeout


## Espera a que [param condition] se cumpla; devuelve `false` si se agota el plazo.
func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false


## Ninguna etiqueta muestra su propia clave: eso delataría una clave ausente del
## CSV (mismo criterio que `ui_smoke_test`, `docs/15` §3).
func _check_no_raw_keys(root: Node, screen_name: String) -> void:
	var raw: Array[String] = []
	_collect_raw_keys(root, raw)
	expect(raw.is_empty(), "hay textos sin traducir en %s: %s" % [screen_name, ", ".join(raw)])


func _collect_raw_keys(node: Node, raw: Array[String]) -> void:
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is Button:
		text = (node as Button).text
	if _looks_like_key(text) and tr(text) == text and not raw.has(text):
		raw.append(text)
	for child: Node in node.get_children():
		_collect_raw_keys(child, raw)


func _looks_like_key(text: String) -> bool:
	if text.length() < 3 or not text.contains("_") or text.contains(" "):
		return false
	return text == text.to_upper()


# --- Directorios ------------------------------------------------------------------------------------

func _player_files() -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(PLAYER_DIR):
		return PackedStringArray()
	var files := DirAccess.get_files_at(PLAYER_DIR)
	files.sort()
	return files


## Borra solo el directorio de este proceso: otro check puede estar corriendo.
func _purge_temp() -> void:
	if _temp_dir.is_empty() or not DirAccess.dir_exists_absolute(_temp_dir):
		return
	for file_name: String in DirAccess.get_files_at(_temp_dir):
		var _discard := DirAccess.remove_absolute(_temp_dir.path_join(file_name))
	var _removed := DirAccess.remove_absolute(_temp_dir)
