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

## Segundos **reales** de reposo extra tras descartar, para que el contador de fps
## del motor deje de arrastrar la carga del nivel.
const SETTLE_SECONDS: float = 1.2

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
	# El veredicto de fps sale del reloj de pared, no de `TIME_PROCESS` ni de
	# `Engine.get_frames_per_second()`: el primero incluye la espera por la GPU
	# (`docs/15` §5.1, corrección de WP-23) y el segundo es la cuenta del último
	# segundo, que sobre una ventana de dos segundos recién cargada da cualquier
	# cosa —medido en WP-24a: 5 fps donde el reloj daba 420—. Los tres se reportan.
	{"key": "fps_wall", "limit": 60.0, "label": "FPS de reloj", "unit": "fps",
			"scenarios": ["flight_only", "boss", "boss_and_city"], "minimum": true},

]

## Radio de la órbita del señuelo del escenario `boss`, en metros.
const PREY_RADIUS: float = 40.0

## Altura del señuelo sobre el plano, en metros.
const PREY_HEIGHT: float = 8.0

## Velocidad tangencial del señuelo, en metros por segundo.
const PREY_SPEED: float = 12.0

## Escena del escenario que se ablaciona.
const ABLATE_SCENE: String = "res://rounds/battle_level.tscn"

## Fotogramas que se miden en cada ventana de ablación. Son menos que los 300 de
## la medición principal porque hay veinte ventanas y el escenario es el mismo: lo
## que se busca acá es el **delta** entre rasgos, no el número absoluto.
const ABLATE_FRAMES: int = 240

## Fotogramas de reposo entre apagar un rasgo y empezar a medir. SDFGI necesita
## rehacer sus cascadas y la niebla volumétrica su reproyección temporal.
const ABLATE_WARMUP: int = 60

## Fotogramas de pelea antes de la primera ventana de ablación: lo que tarda el
## bot en estar disparando, el jefe en caminar y la ciudad en empezar a romperse.
const ABLATE_SETTLE: int = 900

## Rasgos que sabe apagar [method _set_feature], en el orden en que se tabulan.
const ABLATE_FEATURES: Array[Dictionary] = [
	{"id": "root3d", "label": "3D de la viewport raíz"},
	{"id": "shadows", "label": "sombras direccionales"},
	{"id": "sdfgi", "label": "SDFGI"},
	{"id": "fog", "label": "niebla volumétrica"},
	{"id": "ssao", "label": "SSAO"},
	{"id": "msaa", "label": "MSAA 3D"},
	{"id": "fisheye", "label": "ojo de pez"},
	{"id": "occlusion", "label": "oclusión"},
	{"id": "phys_scripts", "label": "_physics_process del nivel"},
	{"id": "phys_enemies", "label": "_physics_process del jefe"},
]

## Referencia contra la que se imprime el Δ % informativo (`docs/15` §8.3).
const DEFAULT_REFERENCE: String = "res://docs/perf/2026-09-19.json"

## Métricas que se comparan contra la referencia, con el signo que las mejora.
const COMPARED: Array[Dictionary] = [
	{"key": "physics_ms_avg", "label": "física media", "lower_is_better": true},
	{"key": "draw_calls_avg", "label": "draw calls", "lower_is_better": true},
	{"key": "primitives_avg", "label": "primitivas", "lower_is_better": true},
	{"key": "fps_engine", "label": "fps de motor", "lower_is_better": false},
	{"key": "fps_wall", "label": "fps de reloj", "lower_is_better": false},
]

var _results: Dictionary[String, Dictionary] = {}
var _ablation: Array[Dictionary] = []
var _physics_suspended: Array[Node] = []
## Fotogramas por ventana de ablación en esta corrida; `--ablate_frames=<n>` lo
## sube para los rasgos de física, donde el monitor del motor necesita varios
## segundos por ventana para dar un pico representativo.
var _ablate_frames: int = ABLATE_FRAMES
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

	var only := String(_args.get("only", ""))
	for scenario: Dictionary in SCENARIOS:
		var id := String(scenario["id"])
		var path := String(scenario["scene"])
		if not only.is_empty() and only != id:
			continue
		if not ResourceLoader.exists(path):
			fail("falta la escena del escenario '%s' (%s)" % [id, path])
			continue
		var sample := await _measure(id, path, bool(scenario["bot"]),
				bool(scenario.get("strip", false)))
		_results[id] = sample
		_print_scenario(id, sample)

	var ablate := String(_args.get("ablate", ""))
	if not ablate.is_empty():
		await _run_ablation(ablate)

	_print_budgets()
	_compare_reference()
	# `Performance.RENDER_VIDEO_MEM_USED` cuenta **toda** la memoria de vídeo
	# —objetivos de render, buffers, sombras, SDFGI— y no es comparable con el
	# presupuesto de `docs/15` §5.2, que habla de la VRAM de **texturas de ciudad**
	# y la mide `city_import_check` leyendo los `.import` (`docs/10` §11.1). Se
	# reporta como dato, no contra un techo.
	print("  (VRAM: dato informativo; el techo de 90 MB de §5.2 es el de las texturas"
			+ " de ciudad y lo mide city_import_check, no este monitor)")
	_write_report(String(_args.get("suffix", "")))
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
	# `Engine.get_frames_per_second()` se refresca una vez por segundo: sin este
	# reposo real, la ventana entera arrastra el tirón de la carga del nivel.
	await _settle(SETTLE_SECONDS)

	var sampler := PerfSampler.new()
	sampler.attach(get_viewport(), _fisheye_viewports(root))
	sampler.begin()
	for _frame: int in WINDOW_FRAMES:
		await get_tree().process_frame
		if prey != null:
			_orbit_prey(prey)
		sampler.sample()
	var sample := sampler.finish()
	sampler.detach()

	await shot(id)

	if bot != null and is_instance_valid(bot):
		bot.stop()
		bot.queue_free()
	root.queue_free()
	await wait_frames(3)
	return sample


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


## Cede fotogramas hasta que pasen [param seconds] segundos reales.
func _settle(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


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


# --- Ablación ----------------------------------------------------------------------------------

## Las `SubViewport` del ojo de pez de la cámara FPV que cuelgue de [param root],
## o un arreglo vacío si el escenario no tiene dron o el ojo de pez está en OFF.
func _fisheye_viewports(root: Node) -> Array[SubViewport]:
	for node: Node in get_tree().get_nodes_in_group(&"fpv_camera"):
		var camera := node as FPVCamera
		if camera != null and root != null and root.is_ancestor_of(camera):
			return camera.get_fisheye_viewports()
	return []


## Si el compuesto del ojo de pez está visible, que es cuando la viewport raíz no
## debe dibujar 3D.
func _composite_visible(root: Node) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"fpv_camera"):
		var camera := node as FPVCamera
		if camera == null or root == null or not root.is_ancestor_of(camera):
			continue
		var composite := camera.get_composite()
		return composite != null and composite.visible
	return false


## El `Environment` del nivel [param root], o `null` si no tiene `WorldEnvironment`.
func _environment(root: Node) -> Environment:
	var world := root.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	return world.environment if world != null else null


## Mide `boss_and_city` apagando un rasgo por vez y tabula el Δ contra la línea de
## base (`--ablate=root3d,shadows,sdfgi,...`).
##
## Es la tabla que decide el orden de la optimización: sin ella, «bajar el MSAA» o
## «apagar SDFGI» son corazonadas. Todo pasa sobre **una sola** instancia del
## nivel —cargarlo nueve veces costaría minutos y metería la varianza de la carga
## dentro de la medición— y cada rasgo se devuelve a su sitio antes del siguiente.
func _run_ablation(list: String) -> void:
	print("")
	print("  === ablación de boss_and_city ===")
	var wanted := _ablation_list(list)
	if wanted.is_empty():
		fail("--ablate no nombró ningún rasgo conocido (%s)" % list)
		return
	var packed := load(ABLATE_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % ABLATE_SCENE)
		return
	var root := packed.instantiate() as Node
	if root == null:
		fail("%s no instancia una escena" % ABLATE_SCENE)
		return
	Global.selected_round = "first-contact"
	Global.round_seed = ROUND_SEED
	add_child(root)
	await wait_frames(4)
	var bot := _start_round(root)
	# La pelea tiene que estar **empezada**: con sesenta frames el bot no disparó
	# todavía, no hay escombros y la ciudad está intacta, así que se mediría una
	# postal y no el escenario del presupuesto.
	await wait_frames(ABLATE_SETTLE)

	var fisheye_before := int(Graphics.fisheye_mode)
	# Emparejado: antes de cada rasgo se vuelve a medir la línea de base, porque el
	# escenario **se mueve** —el bot juega, el jefe camina y los edificios caen— y
	# una sola base al principio haría pasar esa deriva por ahorro del rasgo. El Δ
	# se toma siempre contra la base inmediatamente anterior.
	_ablate_frames = int(_args.get("ablate_frames", ABLATE_FRAMES))
	var base := await _ablate_window(root)
	base["feature"] = "base"
	base["label"] = "línea de base"
	_ablation.append(base)
	for id: String in wanted:
		# Los rasgos de render se miden con el árbol en **pausa**: la pelea avanza
		# —caen edificios, vuelan escombros, el jefe camina— y en diez ventanas
		# seguidas esa deriva es más grande que el rasgo que se quiere medir. En
		# pausa el render sigue dibujando exactamente el mismo cuadro y el Δ es el
		# del rasgo. Los rasgos de física, en cambio, necesitan el árbol corriendo.
		var needs_physics := id.begins_with("phys_")
		if get_tree().paused == needs_physics:
			get_tree().paused = not needs_physics
			await wait_frames(ABLATE_WARMUP)
			base = await _ablate_window(root)
			base["feature"] = "base"
			base["label"] = "línea de base (%s)" % ("corriendo" if needs_physics else "en pausa")
			_ablation.append(base)
		_set_feature(root, id, true)
		await wait_frames(ABLATE_WARMUP)
		var sample := await _ablate_window(root)
		_set_feature(root, id, false)
		await wait_frames(ABLATE_WARMUP)
		var after := await _ablate_window(root)
		var base_gpu := (float(base["gpu_ms_total"]) + float(after["gpu_ms_total"])) * 0.5
		var base_frame := (float(base["frame_ms_avg"]) + float(after["frame_ms_avg"])) * 0.5
		var base_physics := (float(base["physics_ms_avg"])
				+ float(after["physics_ms_avg"])) * 0.5
		sample["feature"] = id
		sample["label"] = _ablation_label(id)
		sample["base_gpu_ms"] = base_gpu
		sample["base_frame_ms"] = base_frame
		sample["delta_gpu_ms"] = base_gpu - float(sample["gpu_ms_total"])
		sample["delta_frame_ms"] = base_frame - float(sample["frame_ms_avg"])
		sample["delta_physics_ms"] = base_physics - float(sample["physics_ms_avg"])
		var feature_fps := 1000.0 / maxf(float(sample["frame_ms_avg"]), 0.0001)
		sample["delta_fps"] = feature_fps - 1000.0 / maxf(base_frame, 0.0001)
		_ablation.append(sample)
		after["feature"] = "base"
		after["label"] = "línea de base"
		_ablation.append(after)
		base = after
	get_tree().paused = false
	Graphics.fisheye_mode = fisheye_before as Graphics.FisheyeMode
	Graphics.update_fisheye()

	if bot != null and is_instance_valid(bot):
		bot.stop()
		bot.queue_free()
	root.queue_free()
	await wait_frames(3)
	_print_ablation()


## Los identificadores de [param list] que [method _set_feature] sabe apagar, en
## el orden de [constant ABLATE_FEATURES]. `--ablate=all` los pide todos.
func _ablation_list(list: String) -> PackedStringArray:
	var raw := list.strip_edges().to_lower()
	var wanted := PackedStringArray()
	for feature: Dictionary in ABLATE_FEATURES:
		var id := String(feature["id"])
		if raw == "all" or raw == "true" or ("," + raw + ",").contains("," + id + ","):
			wanted.append(id)
	return wanted


## Rótulo legible de un rasgo.
func _ablation_label(id: String) -> String:
	for feature: Dictionary in ABLATE_FEATURES:
		if String(feature["id"]) == id:
			return String(feature["label"])
	return id


## Una ventana corta de medición sobre el nivel ya montado.
func _ablate_window(root: Node) -> Dictionary:
	var sampler := PerfSampler.new()
	sampler.attach(get_viewport(), _fisheye_viewports(root))
	sampler.begin()
	for _frame: int in _ablate_frames:
		await get_tree().process_frame
		sampler.sample()
	var sample := sampler.finish()
	sampler.detach()
	return sample


## Apaga ([param disabled] en `true`) o restituye un rasgo de render del nivel.
##
## Restituir no lee un valor guardado sino el que manda `Graphics`: el nivel se
## monta con el preset activo, así que el preset **es** el estado original.
func _set_feature(root: Node, id: String, disabled: bool) -> void:
	var viewport := get_viewport()
	var fisheye := _fisheye_viewports(root)
	match id:
		"root3d":
			# Restituir **no** es «poner false»: con el ojo de pez al mando la raíz
			# tiene que volver a quedarse sin 3D, y quien lo decide es
			# `FPVCamera._update_composite_state()`, que corre en `_process` y por
			# lo tanto no corre con el árbol en pausa. Dejarlo en `false` metía 1,4
			# ms de raíz en todas las líneas de base siguientes y falseaba el resto
			# de la tabla.
			viewport.disable_3d = disabled or _composite_visible(root)
		"shadows":
			var sun := root.get_node_or_null(^"Sun") as DirectionalLight3D
			if sun != null:
				sun.shadow_enabled = not disabled
		"sdfgi":
			var env := _environment(root)
			if env != null:
				env.sdfgi_enabled = not disabled and Graphics.gi == Graphics.Gi.SDFGI
		"fog":
			var env := _environment(root)
			if env != null:
				env.volumetric_fog_enabled = not disabled and Graphics.volumetric_fog
		"ssao":
			var env := _environment(root)
			if env != null:
				env.ssao_enabled = not disabled and Graphics.ssao
		"msaa":
			viewport.msaa_3d = Viewport.MSAA_DISABLED if disabled \
					else Graphics.msaa_to_viewport(int(Graphics.msaa))
			for sub: SubViewport in fisheye:
				sub.msaa_3d = Viewport.MSAA_DISABLED if disabled \
						else Graphics.fisheye_msaa_level()
		"fisheye":
			Graphics.fisheye_mode = Graphics.FisheyeMode.OFF if disabled \
					else Graphics.FisheyeMode.FAST
			Graphics.update_fisheye()
		"occlusion":
			# Restituir no es «poner true»: una `SubViewport` nace con la oclusión
			# apagada y sólo la tiene si `FPVCamera` se la pidió al proyecto.
			var wanted := not disabled and Graphics.use_occlusion_culling()
			viewport.use_occlusion_culling = wanted
			for sub: SubViewport in fisheye:
				sub.use_occlusion_culling = wanted
		"phys_scripts":
			_toggle_physics_process(root, disabled)
		"phys_enemies":
			_toggle_physics_process(root.get_node_or_null(^"Enemies"), disabled)
		_:
			fail("rasgo de ablación desconocido: %s" % id)


## Apaga o restituye el `_physics_process` de todo el subárbol de [param root].
##
## Es la única forma de atribuir el tick de física sin instrumentar archivos que
## este WP no puede tocar (`enemies/ai/enemy_fsm.gd`, `enemies/locomotion/**`,
## `city/**`): lo que se apaga es el **GDScript**, así que lo que quede es el paso
## de Jolt más el motor. Recuerda a quién apagó para no encender de más al volver:
## un nodo que ya estaba sin `_physics_process` debe seguir igual.
func _toggle_physics_process(root: Node, disabled: bool) -> void:
	if root == null:
		return
	if not disabled:
		for node: Node in _physics_suspended:
			if is_instance_valid(node):
				node.set_physics_process(true)
		_physics_suspended.clear()
		return
	_physics_suspended.clear()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_physics_processing():
			node.set_physics_process(false)
			_physics_suspended.append(node)
		for child: Node in node.get_children():
			pending.append(child)


## Tabla de la ablación. El Δ positivo es lo que se **ahorra** apagando el rasgo.
func _print_ablation() -> void:
	if _ablation.is_empty():
		return
	print("")
	print("  --- ablación (boss_and_city, %d fotogramas por ventana) ---" % _ablate_frames)
	print("  %-26s %8s %8s %8s %8s %8s %8s %8s" % ["rasgo apagado", "gpu raíz",
			"gpu ojo", "ms/frame", "ms/tick", "Δ gpu", "Δ tick", "Δ fps"])
	for row: Dictionary in _ablation:
		var is_base := String(row["feature"]) == "base"
		print("  %-26s %8.2f %8.2f %8.2f %8.2f %8s %8s %8s" % [
				String(row["label"]),
				float(row["gpu_ms_root_avg"]), float(row["gpu_ms_fisheye_total"]),
				float(row["frame_ms_avg"]), float(row["physics_ms_avg"]),
				"—" if is_base else "%+.2f" % float(row["delta_gpu_ms"]),
				"—" if is_base else "%+.2f" % float(row["delta_physics_ms"]),
				"—" if is_base else "%+.0f" % float(row["delta_fps"])])


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
	print("  GPU        : raíz %.2f ms (p95 %.2f)  ·  ojo de pez %.2f ms  ·  total %.2f ms"
			% [float(sample["gpu_ms_root_avg"]), float(sample["gpu_ms_root_p95"]),
			float(sample["gpu_ms_fisheye_total"]), float(sample["gpu_ms_total"])])
	print("  CPU render : %.2f ms (p95 %.2f)  ·  ms/frame %.2f  ·  p99 %.2f"
			% [float(sample["cpu_ms_render_avg"]), float(sample["cpu_ms_render_p95"]),
			float(sample["frame_ms_avg"]), float(sample["frame_ms_p99"])])
	print("  FPS reloj  : media %.1f  ·  p1 %.1f  ·  motor %.1f"
			% [float(sample["fps_wall"]), float(sample["fps_engine_p1"]),
			float(sample["fps_engine"])])
	print("  Jolt       : cuerpos activos %.0f  ·  pares %.0f  ·  islas %.0f"
			% [float(sample["physics_active_bodies_avg"]),
			float(sample["physics_collision_pairs_avg"]),
			float(sample["physics_islands_avg"])])
	_print_breakdown(sample)


## Reparto del tick de física entre sistemas, leído de [PerfProbe].
##
## Son medias **por tick**; `physics_ms_avg` es el pico por segundo del monitor del
## motor y no se puede restar de esto (ver la cabecera de [PerfSampler]). Lo que no
## está instrumentado se atribuye con la ablación, no con una resta.
func _print_breakdown(sample: Dictionary) -> void:
	var breakdown := sample.get("physics_breakdown_ms", {}) as Dictionary
	if breakdown == null or breakdown.is_empty():
		return
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in breakdown:
		var value := float(breakdown[key])
		if value < 0.002:
			continue
		parts.append("%s %.3f" % [String(key), value])
	print("  GDScript por sistema (ms/tick): %s" % ", ".join(parts))


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


## Δ % por métrica contra la referencia commiteada más reciente (`docs/15` §8.3).
## Es **informativo**: este check nunca falla por rendimiento, sólo lo reporta.
func _compare_reference() -> void:
	var path := String(_args.get("reference", DEFAULT_REFERENCE))
	if path.is_empty() or not FileAccess.file_exists(path):
		print("")
		print("  (sin referencia con la que comparar: %s)" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var document := parsed as Dictionary
	if document == null or not document.has("scenarios"):
		print("  (la referencia %s no tiene 'scenarios')" % path)
		return
	var reference := document["scenarios"] as Dictionary
	print("")
	print("  --- Δ %% contra %s (%s) ---" % [path, String(document.get("date", "?"))])
	print("  (informativo; `fps de motor` de la referencia de WP-23 no es comparable:"
			+ " se midió con ventanas más cortas que el refresco del contador)")
	for id: String in _results:
		if not reference.has(id):
			continue
		var before := reference[id] as Dictionary
		var now := _results[id]
		for metric: Dictionary in COMPARED:
			var key := String(metric["key"])
			if not before.has(key) or not now.has(key):
				continue
			var old_value := float(before[key])
			var new_value := float(now[key])
			if is_zero_approx(old_value):
				continue
			var delta := (new_value - old_value) / absf(old_value) * 100.0
			var better := delta < 0.0 if bool(metric["lower_is_better"]) else delta > 0.0
			print("  %-14s %-14s %9.3f -> %9.3f   %+7.1f %%  %s"
					% [id, String(metric["label"]), old_value, new_value, delta,
					"mejor" if better else "peor"])


## Escribe `docs/perf/<fecha><sufijo>.json` con el formato de `docs/15` §5.3 más
## los campos nuevos de WP-24a: tiempos de GPU por viewport, percentil 1 de fps,
## reparto del tick de física y tabla de ablación.
##
## El sufijo existe para poder guardar la medición **antes** de tocar nada
## (`--suffix=-antes`) sin pisar la referencia del día.
func _write_report(suffix: String = "") -> void:
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
			scenarios[id] = PerfSampler.round_values(_results[id])
	var ablation: Array = []
	for row: Dictionary in _ablation:
		ablation.append(PerfSampler.round_values(row))
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
		"ablation": ablation,
	}
	var path := "%s/%s%s.json" % [REPORT_DIR, date, suffix]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("no se pudo escribir %s" % path)
		return
	var _stored := file.store_string(JSON.stringify(payload, "  ", false) + "\n")
	file.close()
	print("")
	print("  informe escrito en %s" % path)


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


## Apaga el vsync desde el propio check, que es la salida que `docs/15` §11 D-2
## deja prevista por si `--disable-vsync` no existiera con ese nombre.
func _disable_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# `--max_fps=<n>` corre la medición con el cuadro **topado**: la GPU deja de ser
	# el limitante y lo que queda en `ms/frame` es trabajo de CPU. Es la contraparte
	# de `--gpu-profile`. Sin el argumento, sin tope.
	Engine.max_fps = maxi(int(_args.get("max_fps", 0)), 0)
	if Engine.max_fps > 0:
		print("  tope de cuadro en %d fps: medición de CPU, los fps no son el veredicto"
				% Engine.max_fps)
