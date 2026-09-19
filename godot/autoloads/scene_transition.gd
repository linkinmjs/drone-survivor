## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
extends CanvasLayer
## Fades to the menu background color while changing scenes. When loading a level it also
## shows a loading screen that stays up until the first frames are smooth: the level is
## loaded, the camera looks around once so the shaders get compiled (this is what made the
## web build stutter at the start) and only then the flight is revealed.


const DURATION := 0.25
## Claves de consejo que rota la pantalla de carga (`docs/12` §6). Reemplazan por
## completo a las del simulador de vuelo, que no aplican a este juego (`docs/01` §2.3).
const TIPS: Array[String] = ["UI_TIP_ARM", "UI_TIP_STICKS", "UI_TIP_WEAK_POINTS",
		"UI_TIP_BATTERIES", "UI_TIP_CITY", "UI_TIP_TELEGRAPH"]
const MIN_LOADING_SECONDS := 1.0
const MAX_WARMUP_SECONDS := 6.0
## Frames longer than this count as a hitch (shader compilation, first uploads...)
const HITCH_MS := 70.0
const STABLE_FRAMES := 8

var _root: Control = null
var _loading_panel: Control = null
var _progress: ProgressBar = null
var _tip: Label = null
var _busy := false
## Se pone en `true` cuando el nivel avisa que ya precalentó la vista (`docs/11` §3.1).
var _warmed_up := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = UIPalette.BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_constant_override(&"separation", 18)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	_loading_panel = panel

	var spinner := LoadingSpinner.new()
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_child(spinner)

	var title := Label.new()
	title.text = "UI_LOADING"
	title.theme_type_variation = &"HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(420, 6)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.max_value = 100.0
	panel.add_child(_progress)

	_tip = Label.new()
	_tip.theme_type_variation = &"CaptionLabel"
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(560, 0)
	panel.add_child(_tip)


func is_busy() -> bool:
	return _busy


## Changes the scene with a fade. `show_loading` adds the loading screen and the warm-up.
func change_scene(path: String, show_loading := false) -> void:
	if _busy:
		return
	_busy = true
	var started := Time.get_ticks_msec()
	_root.visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_panel.visible = show_loading
	_progress.value = 0.0
	_tip.text = TIPS.pick_random()
	var tween := create_tween()
	var _step1 := tween.tween_property(_root, "modulate:a", 1.0, DURATION)
	await tween.finished
	# Make sure the loading screen is on screen before the (blocking on the web) load starts
	await _next_draw()

	var packed: PackedScene = null
	if show_loading:
		packed = await _load(path)
	var err := get_tree().change_scene_to_packed(packed) if packed \
			else get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Could not change scene to %s (error %d)" % [path, err])
	await get_tree().process_frame
	await get_tree().process_frame

	if show_loading:
		await _warm_up(started)

	tween = create_tween()
	var _step2 := tween.tween_property(_root, "modulate:a", 0.0, DURATION)
	await tween.finished
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


## Espera a que el cuadro actual llegue a pantalla.
##
## Nota de WP-02: `RenderingServer.frame_post_draw` **no** se emite cuando no hay
## ninguna ventana que dibujar, que es el caso de `--headless`. Esperarla ahí colgaba
## la transición para siempre y dejaba en rojo a `boot_check` y `loading_check`, que
## `docs/15` §7.1 exige correr sin ventana. Sin rasterizado alcanza con ceder un frame.
func _next_draw() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw


func _load(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_request(path) != OK:
		return null
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if not progress.is_empty():
			_progress.value = float(progress[0]) * 70.0
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_progress.value = 70.0
			return ResourceLoader.load_threaded_get(path) as PackedScene
		return null
	return null


## Keeps the fade up until the scene says it has drawn what the player is about to see
## and the frames stop hitching.
##
## Nota de la revisión de WP-11: la espera de `view_warmed_up` lleva tope. Antes era un
## `await` seco de la señal, y si el nivel se liberaba en medio de su `warm_up_view()`
## —cambio de escena encadenado, check que suelta la escena— la señal no llegaba nunca y
## el fundido quedaba colgado para siempre. Ahora se cede el cuadro en un bucle que corta
## a los [constant MAX_WARMUP_SECONDS] aunque la señal no llegue. Es el respaldo:
## `LevelBase._exit_tree()` la emite igual al liberarse, así que el tope solo actúa si la
## escena desaparece sin avisar.
func _warm_up(started_msec: int) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_signal(&"view_warmed_up") and scene.has_method(&"warm_up_view"):
		_warmed_up = false
		var _connected := Signal(scene, &"view_warmed_up").connect(_on_view_warmed_up,
				CONNECT_ONE_SHOT)
		scene.call(&"warm_up_view")
		var warm_deadline := Time.get_ticks_msec() + int(MAX_WARMUP_SECONDS * 1000.0)
		while not _warmed_up and Time.get_ticks_msec() < warm_deadline:
			await get_tree().process_frame
		if not _warmed_up:
			push_warning("Warm-up timed out after %.1f s; revealing the scene anyway."
					% MAX_WARMUP_SECONDS)
	_progress.value = 85.0
	var warm_start := Time.get_ticks_msec()
	var stable := 0
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - warm_start < MAX_WARMUP_SECONDS * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - last) / 1000.0
		last = now
		stable = stable + 1 if frame_ms < HITCH_MS else 0
		_progress.value = 85.0 + 15.0 * float(stable) / STABLE_FRAMES
		if stable >= STABLE_FRAMES and Time.get_ticks_msec() - started_msec >= MIN_LOADING_SECONDS * 1000.0:
			break
	_progress.value = 100.0


func _on_view_warmed_up() -> void:
	_warmed_up = true
