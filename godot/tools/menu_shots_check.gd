## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Capturas de menús para revisión visual (`docs/13` §10.5, WP-25).
##
## [codeblock]
## godot --windowed --resolution 960x540 --path godot res://tools/menu_shots_check.tscn \
##     -- --shots=tools/out/shots
## [/codeblock]
##
## Instancia **cada pantalla por separado** —no navega el menú, de eso ya se ocupa
## `ui_smoke_test`— y guarda una captura de cada una. Diez en total: las ocho
## obligatorias de `docs/13` §10.5 (menú principal, rondas, hub de opciones, juego +
## HUD con vista previa, gráficos, audio, controles y hangar) más la pausa y la tarjeta
## de resultado.
##
## ## Qué falla
##
## - Una pantalla que **no se instancia** (escena ausente, raíz del tipo equivocado).
## - Un [Label] o un [Button] que muestra su **clave de traducción cruda**, que es el
##   síntoma de una clave faltante en `localization/translations.csv`. La detección
##   mira los nodos con texto de forma de clave (`MAYÚSCULAS_CON_GUIONES`) cuyo `tr()`
##   devuelve la clave tal cual; los nodos con `auto_translate_mode` desactivado se
##   saltean porque su texto es un dato, no una clave (el número de paso de la
##   calibración, por ejemplo).
##
## En `--headless` no hay rasterizado: el check **no captura** —[method shot] ya lo
## sabe— pero igual instancia las diez pantallas y verifica las claves, y sale en
## verde. Eso es el SKIP limpio que pide `docs/15` §7.1: sirve en CI como prueba de
## que ninguna pantalla se rompió, aunque nadie pueda mirarla.
extends CheckRunner

## Pantallas obligatorias: nombre de la captura, escena y clase esperada de la raíz.
const SCREENS: Array[Array] = [
	["main_menu", "res://gui/main_menu.tscn", "MainMenu"],
	["rounds", "res://gui/rounds_menu.tscn", "RoundsMenu"],
	["options_hub", "res://gui/options_menu/options_menu.tscn", "OptionsMenu"],
	["options_game_hud", "res://gui/options_menu/game_settings_menu.tscn", "GameSettingsMenu"],
	["options_graphics", "res://gui/options_menu/graphics_menu.tscn", "GraphicsMenu"],
	["options_audio", "res://gui/options_menu/audio_menu.tscn", "AudioMenu"],
	["options_controls", "res://gui/options_menu/controls_menu/controls_menu.tscn", "ControlsMenu"],
	["hangar", "res://gui/quad_settings_menu.tscn", "QuadSettingsMenu"],
]

## Menú de pausa, que no es un [MenuScreen] suelto sino un [CanvasLayer].
const PAUSE_SCENE: String = "res://gui/pause_menu.tscn"

## Tarjeta de resultado.
const RESULT_SCENE: String = "res://rounds/results/result_card.tscn"

## Segundos que se dejan pasar para que terminen los fundidos de apertura antes de
## capturar.
const SETTLE_SECONDS: float = 0.35

## Índice de la pestaña de HUD dentro del menú de juego (`docs/04` §4.2).
const HUD_TAB: int = 1

## Nombre de la pantalla en la que hay que abrir la pestaña de HUD.
const HUD_TAB_SCREEN: String = "options_game_hud"

## Una cadena es «clave cruda» si tiene esta forma y [method Object.tr] la devuelve
## igual: mayúsculas, dígitos y al menos un guion bajo.
const KEY_PATTERN: String = "^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$"

var _key_regex: RegEx = null
var _saved_suspended: bool = false
var _saved_input_kind: int = 0


func _run() -> void:
	_key_regex = RegEx.new()
	var err := _key_regex.compile(KEY_PATTERN)
	if err != OK:
		fail("no se pudo compilar la expresión de claves crudas")
		return
	_saved_suspended = StickNavigation.suspended
	# Con el teclado fijado, cada pantalla toma su foco inicial y la captura muestra el
	# anillo ámbar: con «ratón» las pantallas no lo toman y el foco no se ve.
	_saved_input_kind = int(UI.input_kind)
	var _discard := UI.input_kind_changed.connect(_on_input_kind_changed)
	UI.set_input_kind(UI.InputKind.KEYBOARD)
	Global.startup_errors.clear()
	Global.load_startup_settings()
	Global.startup_errors.clear()

	for entry: Array in SCREENS:
		await _capture_screen(String(entry[0]), String(entry[1]), String(entry[2]))
	await _capture_pause()
	await _capture_result_card()


func finish() -> void:
	if UI.input_kind_changed.is_connected(_on_input_kind_changed):
		UI.input_kind_changed.disconnect(_on_input_kind_changed)
	UI.set_input_kind(_saved_input_kind as UI.InputKind)
	StickNavigation.suspended = _saved_suspended
	get_tree().paused = false
	super()


## Vuelve a fijar el teclado si algo —un movimiento de ratón de la ventana— lo cambia.
func _on_input_kind_changed(kind: UI.InputKind) -> void:
	if int(kind) != int(UI.InputKind.KEYBOARD):
		UI.set_input_kind(UI.InputKind.KEYBOARD)


# --- Pantallas -------------------------------------------------------------------------------

## Instancia [param path], espera a que se asiente, captura y libera.
func _capture_screen(shot_name: String, path: String, type_name: String) -> void:
	if not ResourceLoader.exists(path):
		fail("falta la escena de '%s' (%s)" % [shot_name, path])
		return
	var packed := load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		fail("'%s' no se puede instanciar (%s)" % [shot_name, path])
		return
	var screen := packed.instantiate()
	if not screen.is_class("Control") and not (screen is Control):
		fail("la raíz de '%s' no es un Control" % shot_name)
		screen.queue_free()
		return
	if not _is_type(screen, type_name):
		fail("la raíz de '%s' no es un %s (quedó %s)"
				% [shot_name, type_name, screen.get_class()])
	add_child(screen)
	if screen.has_method(&"grab_initial_focus"):
		screen.call(&"grab_initial_focus", true)
	await _settle()
	if shot_name == HUD_TAB_SCREEN:
		await _open_hud_tab(screen)
	_check_raw_keys(screen, shot_name)
	await shot(shot_name)
	screen.queue_free()
	await wait_frames(2)


## Abre la pestaña de HUD del menú de juego, que es la que lleva la vista previa viva
## del `FlightHUD` y la que `docs/13` §10.5 pide capturar.
func _open_hud_tab(screen: Node) -> void:
	if not screen.has_method(&"show_tab"):
		fail("el menú de juego no expone show_tab(): no se puede capturar la pestaña de HUD")
		return
	screen.call(&"show_tab", HUD_TAB)
	await _settle()


## La pausa vive en un [CanvasLayer] con `process_mode = WHEN_PAUSED`: sin pausar el
## árbol no procesa ni su fundido ni su foco.
func _capture_pause() -> void:
	if not ResourceLoader.exists(PAUSE_SCENE):
		fail("falta el menú de pausa (%s)" % PAUSE_SCENE)
		return
	var menu := (load(PAUSE_SCENE) as PackedScene).instantiate() as PauseMenu
	if menu == null:
		fail("%s no instancia un PauseMenu" % PAUSE_SCENE)
		return
	get_tree().paused = true
	add_child(menu)
	await _settle()
	_check_raw_keys(menu, "pause")
	await shot("pause")
	menu.queue_free()
	await wait_frames(2)
	get_tree().paused = false


## Tarjeta de resultado con un resultado de mentira: victoria con récord, para que se
## vean el resaltado, la medalla y el bloque de «qué quedó en pie».
func _capture_result_card() -> void:
	if not ResourceLoader.exists(RESULT_SCENE):
		fail("falta la tarjeta de resultado (%s)" % RESULT_SCENE)
		return
	var card := (load(RESULT_SCENE) as PackedScene).instantiate() as ResultCard
	if card == null:
		fail("%s no instancia un ResultCard" % RESULT_SCENE)
		return
	card.setup(_sample_result(), [
		{"id": "retry", "text": "RESULT_RETRY", "primary": false},
		{"id": "next", "text": "RESULT_NEXT", "primary": true},
		{"id": "rounds", "text": "RESULT_ROUNDS", "primary": false},
		{"id": "menu", "text": "RESULT_MENU", "primary": false},
	])
	add_child(card)
	await _settle()
	_check_raw_keys(card, "result_card")
	await shot("result_card")
	card.queue_free()
	await wait_frames(2)


## Resultado de muestra para la captura. No sale de ninguna partida: los números están
## elegidos para que todas las filas de la tarjeta tengan contenido.
func _sample_result() -> RoundResult:
	var result := RoundResult.new()
	result.round_id = RoundCatalog.get_round(0)["id"] if RoundCatalog.count() > 0 else "r1"
	result.victory = true
	result.time_seconds = 214.5
	result.city_integrity = 0.78
	result.buildings_standing = 47
	result.buildings_total = 60
	result.parts_broken = 9
	result.shots_fired = 640
	result.shots_hit = 318
	result.deaths = 2
	result.respawn_multiplier = 0.8
	result.base_score = 12400
	result.score = 9920
	result.medal = RoundCatalog.Medal.SILVER
	result.is_record = true
	return result


# --- Claves crudas ---------------------------------------------------------------------------

## Recorre [param root] y falla por cada nodo que muestre su clave sin traducir.
func _check_raw_keys(root: Node, screen_name: String) -> void:
	for node: Node in _walk(root):
		if not (node is Label or node is Button):
			continue
		var control := node as Control
		if control.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED:
			continue
		var value := String(node.get(&"text"))
		if value.is_empty() or _key_regex.search(value) == null:
			continue
		if tr(value) != value:
			continue
		fail("'%s': el nodo %s muestra la clave cruda '%s'"
				% [screen_name, control.name, value])


## Todos los descendientes de [param root], incluido él mismo.
func _walk(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	var index := 0
	while index < nodes.size():
		for child: Node in nodes[index].get_children():
			nodes.append(child)
		index += 1
	return nodes


# --- Utilidades ------------------------------------------------------------------------------

## Verdadero si [param node] es de la clase con nombre global [param type_name].
func _is_type(node: Node, type_name: String) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if script.get_global_name() == StringName(type_name):
			return true
		script = script.get_base_script()
	return false


func _settle() -> void:
	await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
