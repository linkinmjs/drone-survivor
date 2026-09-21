## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Capturas y coste del overlay de la señal FPV (`docs/13` §7).
##
## ```
## "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --windowed \
##     --resolution 1920x1080 --disable-vsync --path godot \
##     res://tools/overlay_shots.tscn -- --shots=tools/out/shots
## ```
##
## **No forma parte de la suite**: necesita GPU y su salida es para mirar, no para
## aprobar. Hace dos cosas que `overlay_check` no puede hacer en `--headless`:
##
## 1. **Mide.** Con `RenderingServer.viewport_set_measure_render_time` sobre la viewport
##    **raíz**, que con el ojo de pez activo no dibuja 3D (`disable_3d = true`, WP-24a) y
##    por lo tanto solo compone canvas: el compuesto, este overlay y el `FlightHUD`. Eso
##    convierte la diferencia entre «overlay apagado» y «overlay encendido» en el coste
##    del overlay **y de su copia de backbuffer**, sin la escena de por medio. El
##    presupuesto de `docs/13` §7 es ≤ 0,25 ms a 1080p.
## 2. **Captura** los seis estados que hay que mirar: limpio, daño 0,5, daño 1,0,
##    EMP 1,0, EMP 0,4 y preset LOW.
##
## ## La misma imagen seis veces
##
## Una comparación solo sirve si lo único que cambia es lo que se quiere comparar. Por
## eso el dron se congela en la pose de `environment_shots` —calculada desde el jefe y
## el centro de la ciudad, con la misma semilla—, la IA se detiene con
## `Global.debug_freeze_ai` y el reloj del overlay se fija a mano con
## [method FPVOverlay.set_clock]: el grano, el latido de la viñeta y la barra del EMP
## caen siempre en la misma fase.
extends CheckRunner

const LEVEL_SCENE: String = "res://rounds/battle_level.tscn"
const ROUND_ID: String = "first-contact"
const ROUND_SEED: int = 1

## Pose de la vista FPV, medida desde el jefe. Los mismos números que
## `tools/environment_shots.gd`, para poder comparar con aquellas capturas.
const FPV_BACK: float = 74.0
const FPV_SIDE: float = 40.0
const FPV_HEIGHT: float = 26.0
const FPV_LOOK_HEIGHT: float = 20.0

## Cuadros de asentamiento: SDFGI llena cascadas y la niebla volumétrica reproyecta.
const SETTLE_FRAMES: int = 90

## Cuadros de calentamiento y de ventana de cada medición.
const WARMUP_FRAMES: int = 45
const WINDOW_FRAMES: int = 240

## Fase fija del reloj del overlay, en segundos. 0,40 s cae con la barra del EMP a un
## tercio de la pantalla y con el latido de la viñeta cerca del máximo: es el cuadro que
## más cuenta de los dos efectos a la vez.
const FIXED_CLOCK: float = 0.40

## Presupuesto de `docs/13` §7, en milisegundos de GPU a 1080p.
const BUDGET_MS: float = 0.25

## Estados a medir y a capturar. `off` esconde el rectángulo: es la línea de base.
const STATES: Array[Dictionary] = [
	{"id": "off", "label": "overlay apagado", "on": false, "damage": 0.0, "emp": 0.0},
	{"id": "clean", "label": "base (daño 0, EMP 0)", "on": true, "damage": 0.0, "emp": 0.0},
	{"id": "damage_050", "label": "daño 0,5", "on": true, "damage": 0.5, "emp": 0.0},
	{"id": "damage_100", "label": "daño 1,0", "on": true, "damage": 1.0, "emp": 0.0},
	{"id": "emp_100", "label": "EMP 1,0", "on": true, "damage": 0.0, "emp": 1.0},
	{"id": "emp_040", "label": "EMP 0,4", "on": true, "damage": 0.0, "emp": 0.4},
]

var _level: Node = null
var _overlay: FPVOverlay = null
var _samples: Dictionary[String, Dictionary] = {}
var _freeze_before: bool = false
var _quality_before: int = 0
var _quality_captured: bool = false


func _run() -> void:
	if Graphics.is_headless():
		print("  SKIP: sin rasterizado no hay ni tiempos de GPU ni capturas (--headless).")
		return
	_quality_before = int(Graphics.quality)
	_quality_captured = true
	_freeze_before = Global.debug_freeze_ai

	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	Graphics.vsync = Graphics.VSync.OFF
	Graphics.max_fps = 0
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	if not await _build_scene():
		return
	_print_window()

	for state: Dictionary in STATES:
		await _measure_state(state)
	_print_table()

	await _capture_low()

	Global.debug_freeze_ai = _freeze_before


func finish() -> void:
	if _quality_captured and int(Graphics.quality) != _quality_before:
		Graphics.apply_quality_preset(_quality_before as Graphics.Quality, false)
	super.finish()


# --- Montaje ----------------------------------------------------------------------------------

## Carga el nivel, salta la cinemática, congela el dron en la pose fija y deja el
## overlay con el reloj parado. Devuelve `false` si algo faltó.
func _build_scene() -> bool:
	Global.debug_freeze_ai = true
	Global.selected_round = ROUND_ID
	Global.round_seed = ROUND_SEED
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % LEVEL_SCENE)
		return false
	_level = packed.instantiate()
	if _level == null:
		fail("%s no instanció nada" % LEVEL_SCENE)
		return false
	add_child(_level)
	await wait_frames(4)

	var level := _level as BattleLevel
	if level == null:
		fail("%s no instancia un BattleLevel" % LEVEL_SCENE)
		return false
	var manager := level.get_round_manager()
	if manager != null and manager.get_state() == Global.RoundState.ALERT:
		manager.skip_intro()
	await wait_frames(2)
	if manager != null:
		while manager.get_intro_remaining() > 0.0:
			await get_tree().process_frame
	_park_drone(level, manager)

	var rig := level.drone_rig as DroneRig
	_overlay = rig.get_overlay() if rig != null else null
	if _overlay == null:
		fail("el DroneRig del nivel no expone overlay (docs/13 §7)")
		return false
	# Reloj parado: las seis capturas comparten fase de grano, de latido y de barra.
	_overlay.set_process(false)
	_overlay.set_clock(FIXED_CLOCK)
	await _settle(SETTLE_FRAMES)
	return true


## Congela el dron mirando al jefe con la ciudad detrás. Misma pose que
## `environment_shots`, para poder poner las capturas una al lado de la otra.
func _park_drone(level: BattleLevel, manager: RoundManager) -> void:
	var rig := level.drone_rig as DroneRig
	if rig == null:
		fail("el nivel no trae DroneRig: no hay vista FPV que capturar")
		return
	var drone := rig.get_drone()
	if drone == null:
		fail("el DroneRig no trae Drone")
		return
	var boss := Vector3.ZERO
	var enemies: Array = manager.get_enemies() if manager != null else []
	if not enemies.is_empty():
		var enemy := enemies[0] as Node3D
		if enemy != null:
			boss = enemy.global_position
	var city := Vector3.ZERO
	var grid := level.get_city_grid()
	if grid != null:
		city = grid.to_global(grid.avenue_crossing())
	var away := city - boss
	away.y = 0.0
	away = Vector3.BACK * 100.0 if away.length() < 1.0 else away.normalized()
	var side := Vector3(-away.z, 0.0, away.x)
	var position := boss - away * FPV_BACK + side * FPV_SIDE + Vector3.UP * FPV_HEIGHT
	var target := boss + Vector3.UP * FPV_LOOK_HEIGHT

	drone.force_disarm()
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	drone.freeze = true
	drone.global_position = position
	drone.look_at(target, Vector3.UP)
	var fpv := rig.get_fpv_camera()
	if fpv != null:
		var _focused := level.focus_camera(fpv)
	print("  pose FPV: %s mirando a %s (jefe %s)"
			% [_v(position), _v(target), _v(boss)])


# --- Medición ---------------------------------------------------------------------------------

## Deja el overlay en [param state], mide una ventana y captura.
func _measure_state(state: Dictionary) -> void:
	var id := String(state["id"])
	_apply_state(state)
	await wait_frames(WARMUP_FRAMES)

	var sampler := PerfSampler.new()
	# Solo la raíz: con ojo de pez activo no dibuja 3D, así que lo que mide es el canvas
	# —compuesto, overlay y HUD— y nada más. Las `SubViewport` del ojo de pez no cambian
	# entre estados y meterlas solo agregaría ruido de la escena.
	sampler.attach(get_viewport(), [])
	sampler.begin()
	for _frame: int in WINDOW_FRAMES:
		await get_tree().process_frame
		sampler.sample()
	var sample := sampler.finish()
	sampler.detach()
	_samples[id] = sample

	print("  %-24s GPU raíz %.4f ms (p95 %.4f, máx %.4f) · draw calls máx %d · %.0f fps"
			% [String(state["label"]), float(sample["gpu_ms_root_avg"]),
			float(sample["gpu_ms_root_p95"]), float(sample["gpu_ms_root_max"]),
			int(sample["draw_calls_max"]), float(sample["fps_wall"])])
	await _capture(id)


## Escribe el estado en el overlay. `off` esconde el rectángulo entero, que es lo que
## también quita la copia de backbuffer: apagar por uniforms no mediría nada.
func _apply_state(state: Dictionary) -> void:
	if _overlay == null:
		return
	var rect := _overlay.rect()
	if rect != null:
		rect.visible = bool(state["on"])
	_overlay.set_damage(float(state["damage"]))
	_overlay.set_emp(float(state["emp"]))
	_overlay.set_clock(FIXED_CLOCK)


## La captura del preset LOW, que es la del overlay en «solo viñeta». Va al final porque
## cambiar de preset rehace las `SubViewport` del ojo de pez y el `Environment`.
func _capture_low() -> void:
	Graphics.apply_quality_preset(Graphics.Quality.LOW, false)
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	if _overlay != null:
		_overlay.set_full_quality(Graphics.fpv_overlay_full())
		_apply_state({"id": "low", "on": true, "damage": 0.0, "emp": 0.0})
	await _settle(SETTLE_FRAMES)

	var sampler := PerfSampler.new()
	sampler.attach(get_viewport(), [])
	sampler.begin()
	for _frame: int in WINDOW_FRAMES:
		await get_tree().process_frame
		sampler.sample()
	var sample := sampler.finish()
	sampler.detach()
	_samples["low"] = sample
	print("  %-24s GPU raíz %.4f ms · draw calls máx %d · overlay completo %s"
			% ["preset LOW", float(sample["gpu_ms_root_avg"]), int(sample["draw_calls_max"]),
			str(_overlay != null and _overlay.is_full_quality())])
	await _capture("low")


func _settle(frames: int) -> void:
	for _frame: int in frames:
		await get_tree().process_frame


# --- Salida -----------------------------------------------------------------------------------

func _print_window() -> void:
	var size := get_viewport().get_visible_rect().size
	print("  ventana   : %d x %d, preset %s, ojo de pez %d"
			% [int(size.x), int(size.y), str(Graphics.effective_quality()),
			int(Graphics.fisheye_mode)])


## La tabla que va al informe: coste por estado y delta contra el overlay apagado.
func _print_table() -> void:
	var base: Dictionary = _samples.get("off", {})
	if base.is_empty():
		return
	var base_ms := float(base["gpu_ms_root_avg"])
	print("")
	print("  | estado | GPU raíz (ms) | delta (ms) | presupuesto 0,25 | draw calls |")
	print("  |---|---|---|---|---|")
	for state: Dictionary in STATES:
		var id := String(state["id"])
		var sample: Dictionary = _samples.get(id, {})
		if sample.is_empty():
			continue
		var value := float(sample["gpu_ms_root_avg"])
		var delta := value - base_ms
		var verdict := "—" if id == "off" else ("OK" if delta <= BUDGET_MS else "EXCEDE")
		print("  | %s | %.4f | %+.4f | %s | %d |"
				% [String(state["label"]), value, delta, verdict,
				int(sample["draw_calls_max"])])
	print("")


## Guarda el PNG e imprime la luminancia en el centro y en las cuatro esquinas: es la
## evidencia numérica de que la viñeta oscurece los bordes y no el centro, y de que el
## tinte de daño no es un filtro rojo a pantalla completa.
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		fail("no se pudo capturar '%s': el viewport no devolvió imagen" % file_name)
		return
	_print_stats(file_name, image)
	if shots_dir.is_empty():
		return
	var path := "%s/overlay_%s.png" % [shots_dir, file_name]
	var err := image.save_png(path)
	if err != OK:
		fail("no se pudo guardar la captura '%s': %s" % [path, error_string(err)])
		return
	print("    captura : %s" % path)


func _print_stats(file_name: String, image: Image) -> void:
	var centre := _patch(image, 0.5, 0.5)
	var corner := _patch(image, 0.04, 0.06)
	var edge := _patch(image, 0.02, 0.5)
	print("    %s: centro L %.4f (rgb %.3f/%.3f/%.3f) · esquina L %.4f (rgb %.3f/%.3f/%.3f) · borde L %.4f"
			% [file_name, _luma(centre), centre.x, centre.y, centre.z,
			_luma(corner), corner.x, corner.y, corner.z, _luma(edge)])


## Media de un parche de 32x32 píxeles centrado en la fracción ([param fx], [param fy])
## del cuadro.
func _patch(image: Image, fx: float, fy: float) -> Vector3:
	var width := image.get_width()
	var height := image.get_height()
	var cx := clampi(int(fx * float(width)), 16, width - 17)
	var cy := clampi(int(fy * float(height)), 16, height - 17)
	var total := Vector3.ZERO
	var count := 0
	for y: int in range(cy - 16, cy + 16, 2):
		for x: int in range(cx - 16, cx + 16, 2):
			var pixel := image.get_pixel(x, y)
			total += Vector3(pixel.r, pixel.g, pixel.b)
			count += 1
	return total / maxf(float(count), 1.0)


func _luma(rgb: Vector3) -> float:
	return rgb.dot(Vector3(0.2126, 0.7152, 0.0722))


func _v(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]
