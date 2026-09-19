## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de la pausa y de las cámaras del nivel (`docs/04` §4.9, `docs/11` §3.2).
##
## Entra al nivel de vuelo libre por la vía real —`SceneTransition.change_scene()` con
## pantalla de carga— y comprueba las cuatro promesas del contrato de pausa:
##
## 1. La acción `change_camera` cicla las cámaras del nivel y vuelve a la primera.
## 2. La acción `pause_menu` abre el menú y **detiene la física**: un dron en caída libre
##    deja de caer. Es la prueba de que `process_mode` está bien puesto.
## 3. `resumed` no despausa mientras la entrada que abrió la pausa siga apretada, y sí lo
##    hace en cuanto se suelta.
## 4. La acción `pause_menu` **estando en pausa** cierra el menú y reanuda: el nivel es
##    `PAUSABLE` y no recibe entrada con el árbol detenido, así que la tiene que escuchar
##    el propio menú (`docs/12` §5.1).
## 5. `MENU_MAIN` pide confirmación y, al confirmar, vuelve al menú principal sin dejar
##    el árbol en pausa.
##
## Comando:
## `"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/pause_check.tscn -- --timeout=120`
extends CheckRunner

const LEVEL_SCENE: String = "res://rounds/free_flight_level.tscn"
const MAIN_MENU_SCENE: String = "res://gui/main_menu.tscn"

## Plazo de cada espera intermedia; el timeout global lo pone `CheckRunner`.
const STEP_TIMEOUT_SECONDS: float = 25.0

## Altura a la que se sube el dron para que esté cayendo cuando llega la pausa.
const DROP_HEIGHT: float = 60.0

## Pasos de física de cada medición de caída.
const DROP_TICKS: int = 12

## Margen por debajo del respaldo de `LevelBase.RESUME_RELEASE_TIMEOUT`: si la máquina
## tarda más que esto en dar tres cuadros, la comprobación de «no despausa mientras se
## mantiene» no es concluyente y se informa en vez de fallar.
const HOLD_BUDGET_MSEC: int = 300

var _level: LevelBase = null


func _run() -> void:
	UI.set_input_kind(UI.InputKind.KEYBOARD)
	# El nodo del check deja de ser la escena actual para sobrevivir a los cambios.
	get_tree().current_scene = null
	if not await _enter_level():
		return
	await _check_cameras()
	await _check_pause_stops_physics()
	await _check_resume_waits_for_release()
	await _check_pause_action_resumes()
	await _check_menu_returns()
	await _close()


# --- Entrada al nivel ------------------------------------------------------------------------

func _enter_level() -> bool:
	if not ResourceLoader.exists(LEVEL_SCENE):
		fail("falta el nivel de vuelo libre (%s)" % LEVEL_SCENE)
		return false
	SceneTransition.change_scene(LEVEL_SCENE, true)
	var done := await _wait_until(func() -> bool: return not SceneTransition.is_busy())
	if not done:
		fail("la transición al nivel nunca terminó")
		return false
	_level = get_tree().current_scene as LevelBase
	if _level == null:
		fail("%s no instancia un LevelBase" % LEVEL_SCENE)
		return false
	expect(_level.is_warmed_up(), "el nivel precalentó la vista antes de revelarse")
	expect(not get_tree().paused, "el nivel arranca sin pausa")
	expect(StickNavigation.suspended,
			"mientras se vuela, los sticks pilotan y no navegan menús")
	return true


# --- 1. Cámaras ------------------------------------------------------------------------------

func _check_cameras() -> void:
	var total := _level.cameras.size()
	expect(total >= 2, "el nivel ofrece al menos dos cámaras (tiene %d)" % total)
	if total < 2:
		return
	var first := _level.active_camera()
	expect(first != null and first.current, "la cámara inicial está activa")
	await _send_action(&"change_camera")
	expect(_level.active_camera() != first,
			"change_camera pasa a otra cámara (siguió en %s)" % _name_of(first))
	expect(_level.active_camera().current, "la cámara nueva queda como la actual")
	for _step: int in total - 1:
		await _send_action(&"change_camera")
	expect(_level.active_camera() == first,
			"ciclar %d veces vuelve a la primera cámara (quedó en %s)"
					% [total, _name_of(_level.active_camera())])


# --- 2. La pausa detiene la física -----------------------------------------------------------

func _check_pause_stops_physics() -> void:
	var drone := _drone()
	if drone == null:
		fail("el nivel no expone el dron del rig: no se puede medir la física")
		return
	if drone.has_method(&"reset_to"):
		drone.call(&"reset_to", Transform3D(Basis(), Vector3(0.0, DROP_HEIGHT, 0.0)))
	await wait_physics(DROP_TICKS)
	var from := drone.global_position
	await wait_physics(DROP_TICKS)
	var to := drone.global_position
	expect(to.y < from.y - 0.01,
			"con el juego corriendo el dron cae (bajó %.3f m en %d pasos)"
					% [from.y - to.y, DROP_TICKS])

	await _send_action(&"pause_menu")
	var opened := await _wait_until(func() -> bool: return _level.pause_menu() != null)
	expect(opened, "la acción pause_menu abre el menú de pausa")
	if not opened:
		return
	expect(get_tree().paused, "abrir la pausa pone el árbol en pausa")
	expect(not StickNavigation.suspended,
			"en pausa los sticks vuelven a navegar el menú (docs/04 §4.9)")
	var menu := _level.pause_menu()
	expect(menu.layer == PauseMenu.CANVAS_LAYER,
			"el menú de pausa vive en la capa %d (docs/12 §1.1)" % PauseMenu.CANVAS_LAYER)
	expect(menu.process_mode == Node.PROCESS_MODE_WHEN_PAUSED,
			"el menú de pausa se declara PROCESS_MODE_WHEN_PAUSED")
	var paused_at := drone.global_position
	await wait_physics(DROP_TICKS * 2)
	expect(drone.global_position.distance_to(paused_at) < 0.001,
			"en pausa la física se detiene y el dron no avanza (se movió %.4f m)"
					% drone.global_position.distance_to(paused_at))


# --- 3. Reanudar espera a que se suelte la entrada -------------------------------------------

func _check_resume_waits_for_release() -> void:
	var menu := _level.pause_menu()
	if menu == null:
		fail("no hay menú de pausa para reanudar")
		return
	Input.action_press(&"pause_menu")
	await wait_frames(1)
	menu.request_resume()
	var started := Time.get_ticks_msec()
	await wait_frames(3)
	var elapsed := Time.get_ticks_msec() - started
	if elapsed < HOLD_BUDGET_MSEC:
		expect(get_tree().paused,
				"mantener apretada la entrada de pausa no reanuda (pasaron %d ms)" % elapsed)
	else:
		print("  NOTA: tres cuadros tardaron %d ms, por encima del respaldo de %.2f s; "
				% [elapsed, LevelBase.RESUME_RELEASE_TIMEOUT]
				+ "no se puede afirmar nada sobre el bloqueo de reanudación.")
	Input.action_release(&"pause_menu")
	var resumed := await _wait_until(func() -> bool: return not get_tree().paused)
	expect(resumed, "al soltar la entrada, el juego se reanuda")
	var closed := await _wait_until(func() -> bool: return _level.pause_menu() == null)
	expect(closed, "el menú de pausa se cierra al reanudar")
	expect(StickNavigation.suspended,
			"al volver al vuelo los sticks vuelven a pilotar")


# --- 4. La acción de pausa, en pausa, reanuda ------------------------------------------------

## `docs/12` §5.1: el botón que abre la pausa es el mismo que la cierra. Como el nivel es
## `PROCESS_MODE_PAUSABLE` no recibe `_unhandled_input` con el árbol detenido, la segunda
## pulsación la tiene que resolver `PauseMenu`, que es `WHEN_PAUSED`.
func _check_pause_action_resumes() -> void:
	await _send_action(&"pause_menu")
	var opened := await _wait_until(func() -> bool: return _level.pause_menu() != null)
	expect(opened, "la pausa se puede volver a abrir para probar el cierre por acción")
	if not opened:
		return
	expect(get_tree().paused, "volver a abrir la pausa detiene el árbol otra vez")
	await _send_action(&"pause_menu")
	var resumed := await _wait_until(func() -> bool: return not get_tree().paused)
	expect(resumed, "la acción pause_menu estando en pausa reanuda el juego (docs/12 §5.1)")
	var closed := await _wait_until(func() -> bool: return _level.pause_menu() == null)
	expect(closed, "reanudar con la acción de pausa también cierra el menú")
	expect(StickNavigation.suspended,
			"al volver al vuelo por la acción de pausa los sticks vuelven a pilotar")


# --- 5. MENU_MAIN vuelve al menú principal ---------------------------------------------------

func _check_menu_returns() -> void:
	await _send_action(&"pause_menu")
	var opened := await _wait_until(func() -> bool: return _level.pause_menu() != null)
	expect(opened, "la pausa se puede volver a abrir después de reanudar")
	if not opened:
		return
	var menu := _level.pause_menu()
	var button := menu.button_for(&"MENU_MAIN")
	if button == null:
		fail("el menú de pausa no tiene botón para MENU_MAIN")
		return
	button.grab_focus()
	await wait_frames(2)
	await _send_action(&"ui_accept")
	var asked := await _wait_until(_modal_ready)
	expect(asked, "MENU_MAIN pide confirmación antes de abandonar la ronda")
	if not asked:
		return
	var focus := get_viewport().gui_get_focus_owner() as Button
	expect(focus != null and focus.text == "UI_CANCEL",
			"la confirmación enfoca la opción segura (enfocó %s)" % _focus_name())
	# La opción segura tiene el foco: hay que moverse a la de confirmar.
	await _send_action(&"ui_right")
	await _send_action(&"ui_accept")
	var gone := await _wait_until(func() -> bool:
			var scene := get_tree().current_scene
			return scene != null and scene.scene_file_path == MAIN_MENU_SCENE)
	expect(gone, "confirmar vuelve al menú principal")
	expect(not get_tree().paused, "al salir de la ronda el árbol queda sin pausa")
	expect(not StickNavigation.suspended,
			"en los menús los sticks vuelven a navegar")


func _close() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		get_tree().current_scene = null
		scene.queue_free()
	await wait_frames(4)
	expect(not UI.has_modal(), "no queda ningún modal abierto al terminar")
	expect(not get_tree().paused, "el check no deja el árbol en pausa")


# --- Utilidades ------------------------------------------------------------------------------

## El cuerpo del dron del rig, o `null` si el nivel no tiene uno cableado.
func _drone() -> Node3D:
	if _level == null or _level.drone_rig == null:
		return null
	if not _level.drone_rig.has_method(&"get_drone"):
		return _level.drone_rig
	return _level.drone_rig.call(&"get_drone") as Node3D


## Inyecta una acción como evento, para que llegue al `_unhandled_input` del nivel y a
## los controles con foco. `Input.action_press()` fija el estado pero no recorre el árbol.
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


## El modal está abierto y su botón ya tomó el foco (lo toma diferido).
func _modal_ready() -> bool:
	if not UI.has_modal():
		return false
	return get_viewport().gui_get_focus_owner() is Button


func _focus_name() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	return str(focus.name) if focus != null else "<sin foco>"


func _name_of(node: Node) -> String:
	return str(node.name) if node != null else "<ninguna>"


## Espera a que [param condition] se cumpla; devuelve `false` si se agota el plazo.
func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false
