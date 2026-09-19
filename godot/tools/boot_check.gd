## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de la secuencia de arranque «Ominoso» (`docs/15` §3, `docs/12` §5).
##
## Verifica que la tarjeta del estudio arranca escribiendo en el terminal, que una
## tecla la saltea en cualquier momento, que siempre termina en el menú principal
## con su foco inicial puesto, y que no deja ningún `AudioStreamPlayer` sonando.
extends CheckRunner

const BOOT_SCENE := "res://gui/boot/boot_sequence.tscn"
const MAIN_MENU_SCENE := "res://gui/main_menu.tscn"

## Margen para que los sonidos cortos de la tarjeta terminen antes de contarlos.
const AUDIO_SETTLE_SECONDS := 1.0

## Plazo máximo de cada espera intermedia; el timeout global lo pone `CheckRunner`.
const STEP_TIMEOUT_SECONDS := 15.0


func _run() -> void:
	# El nodo del check deja de ser la escena actual para sobrevivir al cambio de escena.
	get_tree().current_scene = null

	var err := get_tree().change_scene_to_file(BOOT_SCENE)
	if err != OK:
		fail("no se pudo abrir %s: %s" % [BOOT_SCENE, error_string(err)])
		return
	await wait_frames(3)

	var boot := get_tree().current_scene as BootSequence
	if boot == null:
		fail("la escena actual no es un BootSequence")
		return
	expect(boot.terminal_text().begins_with(BootSequence.PROMPT),
			"la tarjeta arranca con el prompt del terminal (mostró '%s')" % boot.terminal_text())

	# La tarjeta escribe sola: se espera a que aparezca la primera letra del estudio.
	var typed := await _wait_until(func() -> bool: return _has_typed(boot))
	expect(typed, "la tarjeta escribe el nombre del estudio")
	await shot("card")

	# Salto con una tecla en mitad del tipeo: Escape, que además es `ui_cancel`.
	expect(not boot.is_typing_done(),
			"el salto se prueba antes de que termine de escribirse el nombre")
	_press_key(KEY_ESCAPE)
	await wait_frames(2)

	# Desde acá el boot corta a negro y pide el menú a `SceneTransition`.
	var reached := await _wait_until(_menu_is_current)
	if not reached:
		fail("la secuencia nunca llegó a %s" % MAIN_MENU_SCENE)
		return
	var settled := await _wait_until(func() -> bool: return not SceneTransition.is_busy())
	expect(settled, "el fundido de la transición termina y no queda a medias")
	await wait_frames(6)

	var menu := get_tree().current_scene as MainMenu
	expect(menu != null, "la secuencia termina en el menú principal")
	if menu != null:
		expect(UI.get_active_context() == menu, "el menú principal queda como contexto activo")
		await shot("menu")

	expect(not is_instance_valid(boot), "la tarjeta del estudio se libera al salir")

	var playing := await _players_still_playing()
	expect(playing.is_empty(), "no queda audio sonando: %s" % ", ".join(playing))


func _has_typed(boot: BootSequence) -> bool:
	return boot.terminal_text().length() > BootSequence.PROMPT.length() + 1


func _menu_is_current() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == MAIN_MENU_SCENE


## Inyecta una pulsación de tecla completa (press + release) por el bucle de entrada.
func _press_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


## Espera a que [param condition] se cumpla; devuelve `false` si se agota el plazo.
func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false


## Nombres de los `AudioStreamPlayer` que sigan sonando tras dejar asentar el audio.
func _players_still_playing() -> Array[String]:
	await get_tree().create_timer(AUDIO_SETTLE_SECONDS).timeout
	var names: Array[String] = []
	_collect_playing(get_tree().root, names)
	return names


func _collect_playing(node: Node, names: Array[String]) -> void:
	if node is AudioStreamPlayer and (node as AudioStreamPlayer).playing:
		names.append(String(node.get_path()))
	elif node is AudioStreamPlayer2D and (node as AudioStreamPlayer2D).playing:
		names.append(String(node.get_path()))
	elif node is AudioStreamPlayer3D and (node as AudioStreamPlayer3D).playing:
		names.append(String(node.get_path()))
	for child: Node in node.get_children():
		_collect_playing(child, names)
