## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Informe de rendimiento del MVP (`docs/15` §5).
##
## **No es un test binario**: mide y compara. Corre tres escenarios, acumula los
## cinco monitores de `docs/15` §5.1 durante [constant WINDOW_FRAMES] fotogramas
## descartando los [constant DISCARD_FRAMES] primeros —compilación de sombreadores
## y calentamiento de SDFGI—, imprime media, p95 y máximo de cada uno contra el
## presupuesto de §5.2 y escribe `docs/perf/<fecha>.json` con el formato de §5.3.
##
## | Escenario | Qué monta |
## |---|---|
## | `flight_only` | `rounds/free_flight_level.tscn`, el sandbox de P0 |
## | `boss` | `tools/enemy_showcase.tscn`: el jefe sobre un plano, con IA suelta |
## | `boss_and_city` | `rounds/battle_level.tscn` en `BATTLE` con [BotPilot] jugando |
##
## Los FPS se **derivan** de `TIME_PROCESS + TIME_PHYSICS_PROCESS` como pide
## `docs/15` §5.1, pero se reporta **también** [method Engine.get_frames_per_second]
## con el vsync apagado: medido en WP-23, `Performance.TIME_PROCESS` incluye la
## espera del hilo principal por la GPU, así que en una escena limitada por render
## el número derivado sale hasta treinta veces por debajo del real (1.7 contra 66).
## La propuesta D-3 de `docs/15` §11 queda contestada: el derivado sirve para
## comparar coste de CPU entre corridas, no para afirmar «≥ 60 fps».
## El check apaga el vsync por [method DisplayServer.window_set_vsync_mode] además
## de aceptar `--disable-vsync` en la línea de órdenes, que es la salida que
## `docs/15` §11 D-2 deja anotada por si el nombre del argumento cambiara.
##
## El check **siempre sale con 0**: un presupuesto excedido se reporta con su
## número y su causa probable, y arreglarlo es trabajo de WP-24 y WP-29
## (`docs/15` §8.5 no lo cubre; lo decide el brief de WP-23).
##
## Comando, desde la raíz del repositorio:
## [codeblock]
## godot --windowed --resolution 1920x1080 --disable-vsync --path godot \
##     res://tools/perf_report.tscn -- --shots=tools/out/shots
## [/codeblock]
extends CheckRunner

## Fotogramas de la ventana de medición (`docs/15` §10).
const WINDOW_FRAMES: int = 300

## Fotogramas descartados al principio de cada escenario.
const DISCARD_FRAMES: int = 60

## Escenarios, en el orden en que se escriben en el JSON.
const SCENARIOS: Array[Dictionary] = [
	{"id": "flight_only", "scene": "res://rounds/free_flight_level.tscn", "bot": false},
	{"id": "boss", "scene": "res://tools/enemy_showcase.tscn", "bot": false, "strip": true},
	{"id": "boss_and_city", "scene": "res://rounds/battle_level.tscn", "bot": true},
]

## Carpeta donde vive el informe (`docs/15` §5.3). Es un archivo de **datos**, no
## documentación: es la única escritura que este check hace fuera de `tools/out`.
const REPORT_DIR: String = "res://docs/perf"

## Semilla de la partida del escenario con ciudad.
const ROUND_SEED: int = 1

## Presupuestos de `docs/15` §5.2: `[clave, límite, comparación, unidad]`.
const BUDGETS: Array[Dictionary] = [
	{"key": "physics_ms_avg", "limit": 2.0, "label": "física media", "unit": "ms/tick",
			"scenarios": ["boss", "boss_and_city"]},
	{"key": "physics_ms_avg", "limit": 1.6, "label": "física media", "unit": "ms/tick",
			"scenarios": ["flight_only"]},
	{"key": "draw_calls_avg", "limit": 900.0, "label": "draw calls", "unit": "",
			"scenarios": ["flight_only", "boss", "boss_and_city"]},
	{"key": "fps_avg", "limit": 60.0, "label": "FPS derivados", "unit": "fps",
			"scenarios": ["flight_only", "boss", "boss_and_city"], "minimum": true},

]

## Radio de la órbita del señuelo del escenario `boss`, en metros.
const PREY_RADIUS: float = 40.0

## Altura del señuelo sobre el plano, en metros.
const PREY_HEIGHT: float = 8.0

## Velocidad tangencial del señuelo, en metros por segundo.
const PREY_SPEED: float = 12.0

var _results: Dictionary[String, Dictionary] = {}
var _prey_angle: float = 0.0
var _prey_centre: Vector3 = Vector3.ZERO
var _freeze_before: bool = false
var _seed_before: int = 0
var _round_before: String = ""


func _run() -> void:
	get_tree().current_scene = null
	_freeze_before = Global.debug_freeze_ai
	_seed_before = Global.round_seed
	_round_before = Global.selected_round
	Global.debug_freeze_ai = false
	_disable_vsync()

	if DisplayServer.get_name() == "headless":
		print("  AVISO: el servidor de pantalla es 'headless'; los monitores de render"
				+ " valen 0 y los FPS derivados no son comparables (docs/15 §3.1).")

	for scenario: Dictionary in SCENARIOS:
		var id := String(scenario["id"])
		var path := String(scenario["scene"])
		if not ResourceLoader.exists(path):
			fail("falta la escena del escenario '%s' (%s)" % [id, path])
			continue
		var sample := await _measure(id, path, bool(scenario["bot"]),
				bool(scenario.get("strip", false)))
		_results[id] = sample
		_print_scenario(id, sample)

	_print_budgets()
	# `Performance.RENDER_VIDEO_MEM_USED` cuenta **toda** la memoria de vídeo
	# —objetivos de render, buffers, sombras, SDFGI— y no es comparable con el
	# presupuesto de `docs/15` §5.2, que habla de la VRAM de **texturas de ciudad**
	# y la mide `city_import_check` leyendo los `.import` (`docs/10` §11.1). Se
	# reporta como dato, no contra un techo.
	print("  (VRAM: dato informativo; el techo de 90 MB de §5.2 es el de las texturas"
			+ " de ciudad y lo mide city_import_check, no este monitor)")
	_write_report()
	Global.debug_freeze_ai = _freeze_before
	Global.round_seed = _seed_before
	Global.selected_round = _round_before


# --- Medición ----------------------------------------------------------------------------------

## Monta [param path], espera a que se asiente y acumula la ventana de medición.
func _measure(id: String, path: String, with_bot: bool, strip: bool = false) -> Dictionary:
	print("")
	print("  === escenario %s ===" % id)
	Global.selected_round = "first-contact"
	Global.round_seed = ROUND_SEED
	var packed := load(path) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % path)
		return {}
	var root := packed.instantiate() as Node
	if root == null:
		fail("%s no instancia una escena" % path)
		return {}
	if strip:
		# `enemy_showcase.tscn` trae un guion de 44 s que rompe rodillas, abre la
		# carcasa, detona y **imprime una línea por tick** durante la cuenta atrás
		# de P5: medir sobre él daba 3 fps y no medía el jefe, medía el `print`.
		# Se le quita el script y se deja el escenario pelado —plano, sol,
		# `Environment`, pool de escombros y el coloso— con la IA suelta.
		root.set_script(null)
	add_child(root)
	await wait_frames(4)

	var prey: Node3D = null
	if strip:
		# Sin el script de la vista, nadie enciende la cámara de la escena y el
		# render se queda en cinco draw calls: hay que activarla a mano.
		var boss := root.get_node_or_null(^"Arachnodroid") as Node3D
		for child: Node in root.get_children():
			var camera := child as Camera3D
			if camera == null:
				continue
			camera.current = true
			if boss != null:
				camera.look_at(boss.global_position + Vector3.UP * 14.0, Vector3.UP)
			break
		prey = _add_prey(root)
	var bot := _start_round(root) if with_bot else null
	await wait_frames(DISCARD_FRAMES)

	var physics: PackedFloat32Array = PackedFloat32Array()
	var frame_ms: PackedFloat32Array = PackedFloat32Array()
	var draw_calls: PackedFloat32Array = PackedFloat32Array()
	var primitives: PackedFloat32Array = PackedFloat32Array()
	var vram := 0.0
	var nodes := 0
	var engine_fps := 0.0
	for _frame: int in WINDOW_FRAMES:
		await get_tree().process_frame
		if prey != null:
			_orbit_prey(prey)
		engine_fps += float(Engine.get_frames_per_second())
		var physics_ms := float(Performance.get_monitor(
				Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		physics.append(physics_ms)
		frame_ms.append(maxf(physics_ms + process_ms, 0.0001))
		draw_calls.append(float(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(float(Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		vram = maxf(vram, float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
		nodes = maxi(nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	engine_fps /= float(WINDOW_FRAMES)

	await shot(id)

	if bot != null and is_instance_valid(bot):
		bot.stop()
		bot.queue_free()
	root.queue_free()
	await wait_frames(3)

	var fps := _derive_fps(frame_ms)
	return {
		"physics_ms_avg": _mean(physics),
		"physics_ms_p95": _percentile(physics, 95.0),
		"physics_ms_max": _maximum(physics),
		"draw_calls_avg": _mean(draw_calls),
		"draw_calls_p95": _percentile(draw_calls, 95.0),
		"draw_calls_max": _maximum(draw_calls),
		"primitives_avg": _mean(primitives),
		"primitives_p95": _percentile(primitives, 95.0),
		"primitives_max": _maximum(primitives),
		"vram_bytes": vram,
		"vram_mb": vram / 1048576.0,
		"node_count": nodes,
		"fps_avg": fps.x,
		"fps_p95": fps.y,
		"fps_min": fps.z,
		"fps_median": _median_fps(frame_ms),
		"fps_engine": engine_fps,
		"frames": WINDOW_FRAMES,
	}


## Cuelga del escenario un señuelo para que el jefe tenga a quién perseguir.
##
## Sin objetivo, `EnemyFSM._build_context()` deja `has_any_target` en `false` y el
## coloso se queda quieto: el escenario mediría el rig y nada más. El señuelo es
## un [Node3D] pelado —no hace falta cuerpo, la percepción sólo necesita una
## posición y una línea de visión— que orbita el jefe a 40 m y 8 m de altura.
func _add_prey(root: Node) -> Node3D:
	var enemy := root.get_node_or_null(^"Arachnodroid") as EnemyBase
	if enemy == null or enemy.perception == null:
		return null
	var prey := Node3D.new()
	prey.name = "PerfPrey"
	root.add_child(prey)
	_prey_centre = enemy.global_position
	prey.global_position = _prey_centre + Vector3(PREY_RADIUS, PREY_HEIGHT, 0.0)
	if enemy.perception.has_method(&"set_target"):
		enemy.perception.call(&"set_target", prey)
	return prey


## Un paso de la órbita del señuelo.
func _orbit_prey(prey: Node3D) -> void:
	_prey_angle += PREY_SPEED / maxf(PREY_RADIUS, 1.0) * get_process_delta_time()
	prey.global_position = _prey_centre + Vector3(cos(_prey_angle) * PREY_RADIUS,
			PREY_HEIGHT, sin(_prey_angle) * PREY_RADIUS)


## Arranca la batalla del escenario con ciudad y le engancha el bot.
func _start_round(root: Node) -> BotPilot:
	var level := root as BattleLevel
	if level == null:
		return null
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
	bot.name = "PerfBot"
	add_child(bot)
	bot.setup(rig, enemies[0] as EnemyBase,
			level.get_node_or_null(^"BatterySpawner") as BatterySpawner,
			RoundCatalog.derive_seed("bot"))
	manager.skip_intro()
	bot.start()
	return bot


## Media, p95 y mínimo de los FPS derivados de `TIME_PROCESS + TIME_PHYSICS_PROCESS`
## (`docs/15` §5.1). El p95 de FPS es el percentil 5 del coste por fotograma: lo
## que interesa del lado malo.
func _derive_fps(frame_ms: PackedFloat32Array) -> Vector3:
	if frame_ms.is_empty():
		return Vector3.ZERO
	var average := _mean(frame_ms)
	return Vector3(
		1000.0 / maxf(average, 0.0001),
		1000.0 / maxf(_percentile(frame_ms, 95.0), 0.0001),
		1000.0 / maxf(_maximum(frame_ms), 0.0001))


## FPS derivados de la **mediana** del coste por fotograma. La media de §5.1 la
## arruina un solo tirón —la compilación de un sombreador dentro de la ventana
## deja un fotograma de más de un segundo— y con 300 muestras eso mueve el número
## un orden de magnitud. Se reportan los dos, y además el del motor.
func _median_fps(frame_ms: PackedFloat32Array) -> float:
	return 1000.0 / maxf(_percentile(frame_ms, 50.0), 0.0001)


# --- Informe -----------------------------------------------------------------------------------

func _print_scenario(id: String, sample: Dictionary) -> void:
	if sample.is_empty():
		return
	print("  física     : media %.3f ms  ·  p95 %.3f ms  ·  máx %.3f ms"
			% [float(sample["physics_ms_avg"]), float(sample["physics_ms_p95"]),
			float(sample["physics_ms_max"])])
	print("  draw calls : media %.0f  ·  p95 %.0f  ·  máx %.0f"
			% [float(sample["draw_calls_avg"]), float(sample["draw_calls_p95"]),
			float(sample["draw_calls_max"])])
	print("  primitivas : media %.0f  ·  p95 %.0f  ·  máx %.0f"
			% [float(sample["primitives_avg"]), float(sample["primitives_p95"]),
			float(sample["primitives_max"])])
	print("  VRAM       : %.1f MB   ·  nodos %d" % [float(sample["vram_mb"]),
			int(sample["node_count"])])
	print("  FPS        : media %.1f  ·  mediana %.1f  ·  p95 %.1f  ·  mín %.1f  ·  motor %.1f"
			% [float(sample["fps_avg"]), float(sample["fps_median"]),
			float(sample["fps_p95"]), float(sample["fps_min"]), float(sample["fps_engine"])])


## Contrasta cada escenario con el presupuesto de `docs/15` §5.2. No falla: informa.
func _print_budgets() -> void:
	print("")
	print("  --- docs/15 §5.2: presupuestos ---")
	for budget: Dictionary in BUDGETS:
		var key := String(budget["key"])
		var limit := float(budget["limit"])
		var minimum := bool(budget.get("minimum", false))
		for id: Variant in budget["scenarios"] as Array:
			var scenario := String(id)
			if not _results.has(scenario):
				continue
			var value := float(_results[scenario].get(key, 0.0))
			var ok := value >= limit if minimum else value < limit
			print("  %s %-14s %-14s %9.2f %-7s (presupuesto %s %.1f)"
					% ["OK  " if ok else "EXCEDE", scenario, String(budget["label"]),
					value, String(budget["unit"]), "≥" if minimum else "<", limit])


## Escribe `docs/perf/<fecha>.json` con el formato de `docs/15` §5.3.
func _write_report() -> void:
	var err := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(REPORT_DIR))
	if err != OK and err != ERR_ALREADY_EXISTS:
		fail("no se pudo crear %s: %s" % [REPORT_DIR, error_string(err)])
		return
	var date := Time.get_date_string_from_system()
	var scenarios: Dictionary = {}
	for scenario: Dictionary in SCENARIOS:
		var id := String(scenario["id"])
		if _results.has(id):
			scenarios[id] = _round_values(_results[id])
	var payload: Dictionary = {
		"date": date,
		"godot": "%d.%d.%s" % [int(Engine.get_version_info()["major"]),
				int(Engine.get_version_info()["minor"]),
				String(Engine.get_version_info()["status"])],
		"commit": _commit(),
		"display": DisplayServer.get_name(),
		"resolution": "%dx%d" % [DisplayServer.window_get_size().x,
				DisplayServer.window_get_size().y],
		"window_frames": WINDOW_FRAMES,
		"discarded_frames": DISCARD_FRAMES,
		"scenarios": scenarios,
	}
	var path := "%s/%s.json" % [REPORT_DIR, date]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("no se pudo escribir %s" % path)
		return
	var _stored := file.store_string(JSON.stringify(payload, "  ", false) + "\n")
	file.close()
	print("")
	print("  informe escrito en %s" % path)


## Redondea los flotantes del informe a tres decimales: un JSON de referencia con
## quince cifras sería ruido en el `diff` del próximo WP.
func _round_values(sample: Dictionary) -> Dictionary:
	var rounded: Dictionary = {}
	for key: Variant in sample:
		var value: Variant = sample[key]
		if typeof(value) == TYPE_FLOAT:
			rounded[key] = snappedf(float(value), 0.001)
		else:
			rounded[key] = value
	return rounded


## Commit corto del repositorio, leído de `.git` sin salir del proceso. Devuelve
## `"desconocido"` si el checkout no es un repositorio o la cabeza está separada
## de una forma que no se sabe resolver.
func _commit() -> String:
	var root := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	var head_path := root.path_join(".git/HEAD")
	if not FileAccess.file_exists(head_path):
		return "desconocido"
	var head := FileAccess.get_file_as_string(head_path).strip_edges()
	if not head.begins_with("ref:"):
		return head.substr(0, 7)
	var ref := head.substr(4).strip_edges()
	var ref_path := root.path_join(".git").path_join(ref)
	if FileAccess.file_exists(ref_path):
		return FileAccess.get_file_as_string(ref_path).strip_edges().substr(0, 7)
	var packed_path := root.path_join(".git/packed-refs")
	if FileAccess.file_exists(packed_path):
		for line: String in FileAccess.get_file_as_string(packed_path).split("\n"):
			if line.ends_with(ref):
				return line.substr(0, 7)
	return "desconocido"


# --- Estadística -------------------------------------------------------------------------------

func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _percentile(values: PackedFloat32Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := Array(values)
	sorted.sort()
	var index := clampi(int(roundf(p / 100.0 * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return float(sorted[index])


func _maximum(values: PackedFloat32Array) -> float:
	var best := 0.0
	for value: float in values:
		best = maxf(best, value)
	return best


## Apaga el vsync desde el propio check, que es la salida que `docs/15` §11 D-2
## deja prevista por si `--disable-vsync` no existiera con ese nombre.
func _disable_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
