## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Verificación de render y presupuesto de cuadro (`docs/13` §10.1).
##
## Monta la batalla de verdad —`battle_level` con el distrito de 60 edificios, el
## Arachnodroid suelto y un [BotPilot] jugando— y mide una ventana de
## [constant WINDOW_FRAMES] cuadros en tres configuraciones:
##
## | Variante | Qué prueba | Presupuesto |
## |---|---|---|
## | `high` | preset HIGH con SDFGI, ojo de pez FAST_WIDE | fps ≥ 60, p1 ≥ 45, draw calls < 900 |
## | `sdfgi_off` | variante **B** de `docs/13` §3.5: SDFGI apagado, ambiente de color, SSIL y 6 probes | informativa |
## | `low` | preset LOW | fps ≥ 120 |
##
## **Necesita GPU.** Con `--headless` no hay rasterizado: los tiempos de render
## valen cero y los fps no significan nada, así que el check imprime un SKIP
## explícito y **sale con 0** (`docs/13` §11.11 y `docs/15` §3.1). No está en la
## lista de `run_checks`: es un check local.
##
## Comando, desde la raíz del repositorio:
## [codeblock]
## godot --windowed --resolution 1920x1080 --disable-vsync --path godot \
##     res://tools/render_check.tscn -- --shots=tools/out/shots
## [/codeblock]
##
## ## Por qué el veredicto no sale de `Engine.get_frames_per_second()`
##
## Ese contador es la cuenta de cuadros del **último segundo**, refrescada una vez
## por segundo: sobre una ventana de tres segundos que arranca justo después de
## cargar un nivel, la mitad de las muestras todavía arrastran el tirón de la
## carga. Medido en WP-24a, daba 106 fps donde el reloj de pared daba 194. Por eso
## el check se asienta [constant SETTLE_SECONDS] segundos **reales** antes de
## abrir la ventana, y el veredicto lo toma [PerfSampler] con el tiempo de cuadro
## medido con `Time.get_ticks_usec()`, que es lo que siente el jugador. El número
## del motor se imprime igual, al lado, para poder compararlos.
extends CheckRunner

## Nivel que se mide. Es el mismo que juega el jugador, sin recortes.
const LEVEL_SCENE: String = "res://rounds/battle_level.tscn"

## Ronda y semilla con las que se arma la batalla, iguales que en `perf_report`.
const ROUND_ID: String = "first-contact"
const ROUND_SEED: int = 1

## Cuadros de calentamiento antes de medir (`docs/13` §10.1 punto 2).
const WARMUP_FRAMES: int = 120

## Cuadros de la ventana de medición (`docs/13` §10.1 punto 2).
const WINDOW_FRAMES: int = 600

## Segundos **reales** de reposo extra tras el calentamiento, para que el contador
## de fps del motor deje de arrastrar la carga del nivel.
const SETTLE_SECONDS: float = 1.5

## Variantes que se miden, en orden. `fps_min` y `p1_min` en `0.0` significan
## «informativa»: se mide y se tabula, pero no hace fallar el check.
const VARIANTS: Array[Dictionary] = [
	{
		"id": "high", "shot": "render_high", "label": "HIGH",
		"preset": 2, "sdfgi": true, "ssil": false,
		"fps_min": 60.0, "p1_min": 45.0, "draw_calls_max": 900.0,
	},
	# `sdfgi` en `true` **y** `ssil` en `true` no es contradictorio: `sdfgi` es el
	# ajuste del jugador («quiero iluminación global») y `ssil` marca la variante B,
	# que es **cómo** se le da. Quien apaga SDFGI de verdad es
	# [member Graphics.gi_variant], y de paso sube los probes a seis.
	{
		"id": "sdfgi_off", "shot": "render_sdfgi_off", "label": "HIGH, variante B",
		"preset": 2, "sdfgi": true, "ssil": true,
		"fps_min": 0.0, "p1_min": 0.0, "draw_calls_max": 900.0,
	},
	{
		"id": "low", "shot": "render_low", "label": "LOW",
		"preset": 0, "sdfgi": false, "ssil": false,
		"fps_min": 120.0, "p1_min": 0.0, "draw_calls_max": 900.0,
	},
]

var _results: Dictionary[String, Dictionary] = {}
var _freeze_before: bool = false
var _seed_before: int = 0
var _round_before: String = ""
var _quality_before: int = 0


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  SKIP: render_check necesita GPU y no corre con --headless"
				+ " (docs/13 §11.11, docs/15 §3.1).")
		print("  Corralo con: --windowed --resolution 1920x1080 --disable-vsync")
		return

	get_tree().current_scene = null
	_freeze_before = Global.debug_freeze_ai
	_seed_before = Global.round_seed
	_round_before = Global.selected_round
	_quality_before = int(Graphics.quality)
	Global.debug_freeze_ai = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_print_window()

	for variant: Dictionary in VARIANTS:
		var sample := await _measure(variant)
		if sample.is_empty():
			continue
		_results[String(variant["id"])] = sample
		_print_variant(sample)

	_print_table()
	_check_budgets()

	Graphics.gi_variant = Graphics.GiVariant.A_SDFGI
	Graphics.apply_quality_preset(_quality_before as Graphics.Quality, false)
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	Global.debug_freeze_ai = _freeze_before
	Global.round_seed = _seed_before
	Global.selected_round = _round_before


# --- Medición ---------------------------------------------------------------------------------

## Aplica el preset de [param variant], monta la batalla, la deja arrancar y mide
## la ventana. Devuelve el diccionario de [PerfSampler], o vacío si algo falló.
func _measure(variant: Dictionary) -> Dictionary:
	var id := String(variant["id"])
	print("")
	print("  === variante %s (%s) ===" % [id, String(variant["label"])])
	_apply_variant(variant)

	Global.selected_round = ROUND_ID
	Global.round_seed = ROUND_SEED
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % LEVEL_SCENE)
		return {}
	var level := packed.instantiate() as BattleLevel
	if level == null:
		fail("%s no instancia un BattleLevel" % LEVEL_SCENE)
		return {}
	add_child(level)
	await wait_frames(4)
	_force_variant_environment(level, variant)
	var bot := _start_round(level)

	await wait_frames(WARMUP_FRAMES)
	await _settle(SETTLE_SECONDS)

	var sampler := PerfSampler.new()
	sampler.attach(get_viewport(), _fisheye_viewports(level))
	sampler.begin()
	for _frame: int in WINDOW_FRAMES:
		await get_tree().process_frame
		sampler.sample()
	var sample := sampler.finish()
	sampler.detach()
	sample["fisheye_viewports"] = _fisheye_viewports(level).size()

	await _capture(String(variant["shot"]))

	if bot != null and is_instance_valid(bot):
		bot.stop()
		bot.queue_free()
	level.queue_free()
	await wait_frames(3)
	return sample


## Vuelca el preset de la variante sobre `Graphics` **antes** de montar el nivel,
## para que el `WorldEnvironment`, el sol y el ojo de pez nazcan ya con él.
func _apply_variant(variant: Dictionary) -> void:
	Graphics.apply_quality_preset(int(variant["preset"]) as Graphics.Quality, false)
	Graphics.gi = Graphics.Gi.SDFGI if bool(variant["sdfgi"]) else Graphics.Gi.OFF
	# Desde WP-24 la variante B de `docs/13` §3.5 es una bandera de `Graphics`, no un
	# parche sobre el `Environment` ya montado: así se lleva consigo el SSIL **y** los
	# seis `ReflectionProbe`, que es lo que la variante pide de verdad.
	if bool(variant["ssil"]):
		Graphics.gi_variant = Graphics.GiVariant.B_AMBIENT_SSIL
	else:
		Graphics.gi_variant = Graphics.GiVariant.A_SDFGI
	# `apply_all()` reaplica el vsync y el tope de fps de la configuración —que en
	# el aislamiento del runner son los de fábrica, o sea vsync ON—, así que hay que
	# apagarlos **acá dentro** y no una sola vez al principio: medir contra el
	# refresco del monitor daba exactamente 60,0 fps en las tres variantes.
	Graphics.vsync = Graphics.VSync.OFF
	Graphics.max_fps = 0
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


## Deja constancia de con qué quedó armada la variante: es lo que se mira al lado de
## los fps para decidir el riesgo 1 de `docs/13` §11 en el checkpoint 4.
##
## Ya no parchea nada —de eso se ocupa [method Graphics.apply_environment_quality] a
## través de [member Graphics.gi_variant]—; sólo informa.
func _force_variant_environment(level: BattleLevel, variant: Dictionary) -> void:
	var world := level.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var env := world.environment
	var probes := level.get_reflection_probes().size()
	print("  GI: sdfgi %s · ssil %s · ambiente %s a %.2f · %d ReflectionProbe"
			% ["on" if env.sdfgi_enabled else "off", "on" if env.ssil_enabled else "off",
			env.ambient_light_color.to_html(false), env.ambient_light_energy, probes])
	if bool(variant["ssil"]):
		expect(not env.sdfgi_enabled and env.ssil_enabled,
				"la variante B tiene que dejar SDFGI apagado y SSIL encendido")
		expect(probes == Graphics.PRESET_REFLECTION_PROBES[
				Graphics.PRESET_REFLECTION_PROBES.size() - 1],
				"la variante B de docs/13 §3.5 pide 6 ReflectionProbe y hay %d" % probes)


## Arranca la batalla y le engancha el bot, igual que `perf_report`.
func _start_round(level: BattleLevel) -> BotPilot:
	var manager := level.get_round_manager()
	var rig := level.drone_rig as DroneRig
	if manager == null or rig == null:
		fail("el nivel de batalla no trae RoundManager o DroneRig")
		return null
	var enemies := manager.get_enemies()
	if enemies.is_empty():
		fail("la ronda no instanció ningún enemigo")
		return null
	var bot := BotPilot.new()
	bot.name = "RenderBot"
	add_child(bot)
	bot.setup(rig, enemies[0] as EnemyBase,
			level.get_node_or_null(^"BatterySpawner") as BatterySpawner,
			RoundCatalog.derive_seed("bot"))
	manager.skip_to_battle()
	bot.start()
	return bot


## Las `SubViewport` del ojo de pez de la cámara FPV del nivel.
func _fisheye_viewports(level: Node) -> Array[SubViewport]:
	for node: Node in get_tree().get_nodes_in_group(&"fpv_camera"):
		var camera := node as FPVCamera
		if camera != null and level.is_ancestor_of(camera):
			return camera.get_fisheye_viewports()
	return []


## Cede cuadros hasta que pasen [param seconds] segundos reales.
func _settle(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## Guarda la captura con el nombre exacto que pide `docs/13` §10.1 punto 6
## —`render_high.png`, `render_low.png`, `render_sdfgi_off.png`— en vez del
## `<check>_<name>.png` de [method CheckRunner.shot].
func _capture(file_name: String) -> void:
	if shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		fail("no se pudo capturar '%s': el viewport no devolvió imagen" % file_name)
		return
	var path := "%s/%s.png" % [shots_dir, file_name]
	var err := image.save_png(path)
	if err != OK:
		fail("no se pudo guardar la captura '%s': %s" % [path, error_string(err)])
		return
	print("  captura: %s" % path)


# --- Informe ----------------------------------------------------------------------------------

func _print_window() -> void:
	var size := DisplayServer.window_get_size()
	print("  ventana %dx%d, vsync apagado, %d cuadros de calentamiento + %.1f s de reposo"
			% [size.x, size.y, WARMUP_FRAMES, SETTLE_SECONDS]
			+ " + %d medidos" % WINDOW_FRAMES)
	if size.x < 1920 or size.y < 1080:
		print("  AVISO: el presupuesto de `docs/15` §5.2 es a 1080p; esta ventana es menor.")


func _print_variant(sample: Dictionary) -> void:
	print("  fps        : reloj %.1f  ·  p1 %.1f  ·  motor %.1f"
			% [float(sample["fps_wall"]), float(sample["fps_engine_p1"]),
			float(sample["fps_engine"])])
	print("  GPU        : raíz %.2f ms  ·  ojo de pez %.2f ms (%d viewports)  ·  total %.2f ms"
			% [float(sample["gpu_ms_root_avg"]), float(sample["gpu_ms_fisheye_total"]),
			int(sample["fisheye_viewports"]), float(sample["gpu_ms_total"])])
	print("  draw calls : media %.0f  ·  p95 %.0f  ·  máx %.0f  ·  primitivas %.0f"
			% [float(sample["draw_calls_avg"]), float(sample["draw_calls_p95"]),
			float(sample["draw_calls_max"]), float(sample["primitives_avg"])])
	print("  física     : %.3f ms/tick  ·  VRAM %.0f MB  ·  nodos %d"
			% [float(sample["physics_ms_avg"]), float(sample["vram_mb"]),
			int(sample["node_count"])])


## Tabla comparativa de las tres variantes: es lo que el usuario mira al lado de
## las capturas para decidir el riesgo 1 de `docs/13` §11 en el checkpoint 4.
func _print_table() -> void:
	print("")
	print("  --- docs/13 §3.5: A (SDFGI) contra B (ambiente + SSIL) ---")
	print("  %-18s %8s %8s %8s %9s %9s %10s" % ["variante", "fps", "p1", "motor",
			"gpu ms", "draw máx", "ms/tick"])
	for variant: Dictionary in VARIANTS:
		var id := String(variant["id"])
		if not _results.has(id):
			continue
		var sample := _results[id]
		print("  %-18s %8.1f %8.1f %8.1f %9.2f %9.0f %10.3f"
				% [String(variant["label"]), float(sample["fps_wall"]),
				float(sample["fps_engine_p1"]), float(sample["fps_engine"]),
				float(sample["gpu_ms_total"]), float(sample["draw_calls_max"]),
				float(sample["physics_ms_avg"])])


## Contrasta cada variante con su presupuesto. Acá sí falla el check.
func _check_budgets() -> void:
	print("")
	print("  --- presupuestos (docs/13 §10.1, docs/15 §5.2) ---")
	for variant: Dictionary in VARIANTS:
		var id := String(variant["id"])
		if not _results.has(id):
			fail("la variante '%s' no llegó a medirse" % id)
			continue
		var sample := _results[id]
		var fps := float(sample["fps_wall"])
		var p1 := float(sample["fps_engine_p1"])
		var draws := float(sample["draw_calls_max"])
		var fps_min := float(variant["fps_min"])
		var p1_min := float(variant["p1_min"])
		var draws_max := float(variant["draw_calls_max"])
		if fps_min > 0.0:
			_verdict(id, "fps medio", fps, fps_min, true)
		if p1_min > 0.0:
			_verdict(id, "percentil 1", p1, p1_min, true)
		_verdict(id, "draw calls máx", draws, draws_max, false)


## Imprime y registra un presupuesto. [param minimum] en `true` es «al menos».
func _verdict(id: String, label: String, value: float, limit: float, minimum: bool) -> void:
	var ok := value >= limit if minimum else value < limit
	print("  %s %-12s %-16s %9.1f (presupuesto %s %.1f)"
			% ["OK  " if ok else "FALLA", id, label, value, "≥" if minimum else "<", limit])
	if not ok:
		fail("%s: %s %.1f fuera del presupuesto (%s %.1f)"
				% [id, label, value, "≥" if minimum else "<", limit])
