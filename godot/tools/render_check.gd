## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Verificación de render y presupuesto de cuadro (`docs/13` §10.1).
##
## Monta la batalla de verdad —`battle_level` con el distrito de 60 edificios, el
## Arachnodroid suelto y un [BotPilot] jugando— y mide dos ventanas de
## [constant WINDOW_FRAMES] cuadros en cada una de tres configuraciones:
##
## | Variante | Qué prueba | Presupuesto |
## |---|---|---|
## | `high` | preset HIGH con SDFGI, ojo de pez FAST_WIDE | fps ≥ 60, p1 ≥ 45, draw calls < 900 |
## | `sdfgi_off` | variante **B** de `docs/13` §3.5: SDFGI apagado, ambiente de color, SSIL y 6 probes | informativa |
## | `low` | preset LOW | fps ≥ 120 |
##
## Y dos escenarios por variante (P2d):
##
## | Escenario | Qué hay en pantalla | Presupuesto de lotes |
## |---|---|---|
## | `intacto` | el pueblo en pie, el jefe caminando y el bot disparando | < 900 de máximo |
## | `con derrumbe` | ocho edificios caídos alrededor del jefe: polvo, escombro suelto, campos de ruina horneados y montículos | < 1100 de máximo y < 1000 de media |
##
## Los fps y el percentil 1 de la variante se aseveran en **los dos**: en el cuadro con
## derrumbe son el criterio vinculante, y el tope de lotes sólo está para cazar
## regresiones grandes (ver [method _check_budgets]).
##
## El derrumbe lo guiona el propio check con [method Building.take_damage], sin tocar
## el juego, en dos tandas separadas por [constant COLLAPSE_BAKE_SECONDS] para que la
## ventana vea a la vez el [RubbleField] ya horneado y escombro todavía volando.
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

## Edificios que el check derrumba para el escenario «con derrumbe», repartidos en
## dos tandas de [constant COLLAPSE_WAVE].
const COLLAPSE_TARGETS: int = 8

## Edificios por tanda. La primera tanda existe para que su escombro se duerma y se
## **hornee** en el [RubbleField] antes de medir: así la ventana ve los campos de
## ruina abiertos *y* escombro suelto al mismo tiempo, que es el cuadro caro de
## verdad (`docs/10` §6).
const COLLAPSE_WAVE: int = 4

## Segundos entre la primera tanda y la segunda. Tienen que alcanzar para el
## derrumbe (`BuildingProfile.collapse_seconds`, 1,8 s) más los
## [constant DebrisPool.SLEEP_RETIRE_SECONDS] que tarda un trozo dormido en
## hornearse.
const COLLAPSE_BAKE_SECONDS: float = 4.5

## Segundos entre la segunda tanda y la ventana de medición: lo justo para que el
## polvo esté emitiendo y el escombro volando, sin que ninguno se haya apagado.
const COLLAPSE_DUST_SECONDS: float = 0.6

## Cuadros de cada ventana corta de [method _shadow_share].
const PROBE_FRAMES: int = 90

## Cuadros de reposo entre apagar la sombra y volver a medir.
const PROBE_WARMUP: int = 10

## Tope de lotes de dibujo del pueblo **intacto** (`docs/15` §5.2). Es el presupuesto
## histórico del proyecto y el que sigue mandando: el cuadro que el jugador ve la mayor
## parte de la ronda.
const BATCH_BUDGET_INTACT: float = 900.0

## Tope de lotes del **pico** del escenario con derrumbe.
##
## El cuadro con derrumbe no se mide contra los 900: es un pico transitorio —cuatro
## edificios cayéndose en el mismo cuadro— y su criterio vinculante son los fps, que ya
## se aseveran. Este tope y [constant BATCH_MEAN_COLLAPSE] están para **cazar
## regresiones grandes**, no para dimensionar el cuadro.
##
## Medido en P2d sobre el pueblo de `town_a`, preset HIGH, con las sombras del escombro,
## de los campos de ruina y del montículo ya apagadas: **1019 lotes de máximo y 905 de
## media**, a 116 fps de reloj y 73 de percentil 1, con 23–24 escombros vivos, 27–28
## horneados en 4 campos y 9 montículos en pie. Apagar esas tres sombras valió −21 lotes
## en el pico; el pase de sombra direccional que **queda** son 254–374 lotes, el 33–43 %
## del cuadro, y es el de los seis hitos que `docs/13` §1 hace proyectar a propósito.
## Los topes se ponen por encima de la medida con margen para la deriva del escenario.
const BATCH_BUDGET_COLLAPSE: float = 1100.0

## Tope de la **media** de lotes de la ventana con derrumbe. Va aparte del pico porque
## un máximo se lo lleva un solo cuadro y una media que sube es contenido nuevo.
const BATCH_MEAN_COLLAPSE: float = 1000.0

## Los dos escenarios que se miden por variante, en orden.
##
## `batch_mean` en `0.0` significa que ese escenario no tiene presupuesto de media.
const SCENARIOS: Array[Dictionary] = [
	{"id": "intact", "label": "intacto",
			"batch_max": BATCH_BUDGET_INTACT, "batch_mean": 0.0},
	{"id": "collapse", "label": "con derrumbe",
			"batch_max": BATCH_BUDGET_COLLAPSE, "batch_mean": BATCH_MEAN_COLLAPSE},
]

## Variantes que se miden, en orden. `fps_min` y `p1_min` en `0.0` significan
## «informativa»: se mide y se tabula, pero no hace fallar el check.
##
## El presupuesto de lotes ya **no** vive acá: es del escenario, no de la variante
## ([constant SCENARIOS]). Los fps y el percentil 1 sí son de la variante, y desde P2d
## se aseveran en los **dos** escenarios: son el criterio vinculante del cuadro con
## derrumbe.
const VARIANTS: Array[Dictionary] = [
	{
		"id": "high", "shot": "render_high", "label": "HIGH",
		"preset": 2, "sdfgi": true, "ssil": false,
		"fps_min": 60.0, "p1_min": 45.0,
	},
	# `sdfgi` en `true` **y** `ssil` en `true` no es contradictorio: `sdfgi` es el
	# ajuste del jugador («quiero iluminación global») y `ssil` marca la variante B,
	# que es **cómo** se le da. Quien apaga SDFGI de verdad es
	# [member Graphics.gi_variant], y de paso sube los probes a seis.
	{
		"id": "sdfgi_off", "shot": "render_sdfgi_off", "label": "HIGH, variante B",
		"preset": 2, "sdfgi": true, "ssil": true,
		"fps_min": 0.0, "p1_min": 0.0,
	},
	{
		"id": "low", "shot": "render_low", "label": "LOW",
		"preset": 0, "sdfgi": false, "ssil": false,
		"fps_min": 120.0, "p1_min": 0.0,
	},
]

## Nombres que admite `--fisheye_msaa`, en el orden de [enum Graphics.FisheyeMsaa].
const FISHEYE_MSAA_NAMES: Array[String] = ["OFF", "X2", "X4", "X8", "SAME"]

var _results: Dictionary[String, Dictionary] = {}
## Palanca [member Graphics.fisheye_msaa] que pide `--fisheye_msaa`, o `-1` si no se
## pasó la bandera. Existe para poder sacar `render_high.png` con la cara frontal a 4×
## y a 2× y mirar las dos: la decisión del MSAA frontal se toma con la captura al lado
## del número, no sólo con el número (P2d).
var _fisheye_msaa_arg: int = -1
var _freeze_before: bool = false
var _seed_before: int = 0
var _round_before: String = ""
var _quality_before: int = 0
var _fisheye_msaa_before: int = 0
var _gi_variant_before: int = 0


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
	_fisheye_msaa_before = int(Graphics.fisheye_msaa)
	_gi_variant_before = int(Graphics.gi_variant)
	Global.debug_freeze_ai = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_read_fisheye_msaa_arg()
	_print_window()

	for variant: Dictionary in VARIANTS:
		var measured := await _measure(variant)
		if measured.is_empty():
			continue
		for scenario: Dictionary in SCENARIOS:
			var key := String(scenario["id"])
			if not measured.has(key):
				continue
			_results["%s/%s" % [String(variant["id"]), key]] = measured[key]
			_print_variant(String(scenario["label"]), measured[key])

	_print_table()
	_check_budgets()

	Graphics.gi_variant = _gi_variant_before as Graphics.GiVariant
	Graphics.fisheye_msaa = _fisheye_msaa_before as Graphics.FisheyeMsaa
	Graphics.apply_quality_preset(_quality_before as Graphics.Quality, false)
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	Global.debug_freeze_ai = _freeze_before
	Global.round_seed = _seed_before
	Global.selected_round = _round_before


# --- Medición ---------------------------------------------------------------------------------

## Aplica el preset de [param variant], monta la batalla, la deja arrancar y mide
## **dos** ventanas sobre el mismo nivel: el pueblo intacto y el pueblo con ocho
## edificios cayéndose. Devuelve `{"intact": …, "collapse": …}` con el diccionario
## de [PerfSampler] de cada una, o vacío si algo falló.
##
## ## Por qué hacen falta dos ventanas
##
## Hasta P2d el check medía [constant WARMUP_FRAMES] + [constant SETTLE_SECONDS] +
## [constant WINDOW_FRAMES]: seis o siete segundos de partida a 130 fps, en los que
## el [BotPilot] todavía no derribó nada. Los lotes que tabulaba eran los del pueblo
## **intacto**, así que el presupuesto de 900 nunca se contrastaba contra el cuadro
## caro de verdad —polvo, escombro suelto, campos de ruina horneados, montículos y el
## jefe—, que es justo donde se disparan las sombras de la ruina.
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
	# El ancla del derrumbe se toma **acá**, con el jefe recién puesto: es su punto de
	# aparición, que depende sólo de la ronda y de la semilla. Tomarla después del
	# calentamiento la ataría a cuántos ticks de física entraron en esos cuadros, que
	# depende de los fps de la máquina, y el escenario dejaría de ser comparable.
	var anchor := _boss_position(level)

	await wait_frames(WARMUP_FRAMES)
	await _settle(SETTLE_SECONDS)

	var measured: Dictionary = {}
	measured["intact"] = await _window(level)
	# Un solo cuadro capturado con los dos nombres: `render_<variante>.png` es el que
	# pide `docs/13` §10.1 punto 6 y `_intact` el que se pone al lado del `_collapse`.
	await _capture(String(variant["shot"]), ["%s_intact" % String(variant["shot"])])

	await _collapse(level, anchor)
	measured["collapse"] = await _window(level)
	await _capture("%s_collapse" % String(variant["shot"]))
	await _shadow_share(level)

	if bot != null and is_instance_valid(bot):
		bot.stop()
		bot.queue_free()
	level.queue_free()
	await wait_frames(3)
	return measured


## Una ventana de [constant WINDOW_FRAMES] cuadros sobre el nivel ya montado.
func _window(level: BattleLevel) -> Dictionary:
	var sampler := PerfSampler.new()
	sampler.attach(get_viewport(), _fisheye_viewports(level))
	sampler.begin()
	for _frame: int in WINDOW_FRAMES:
		await get_tree().process_frame
		sampler.sample()
	var sample := sampler.finish()
	sampler.detach()
	sample["fisheye_viewports"] = _fisheye_viewports(level).size()
	return sample


## Cuánto del cuadro con derrumbe es el **pase de sombra direccional**.
##
## Es una ablación emparejada, con la misma receta que `tools/perf_report.gd`: se mide
## con sombra, sin sombra y otra vez con sombra, y el Δ se toma contra la media de las
## dos con sombra. Hace falta emparejar porque la ruina **se mueve** mientras se mide
## —el escombro se duerme y se hornea, el polvo se apaga, el jefe camina—, y una sola
## lectura de referencia haría pasar esa deriva por ahorro.
##
## Sin este número, «bajé lotes» no se puede repartir entre el pase de sombra y el de
## color, que es lo que decide si la siguiente palanca es `cast_shadow` o geometría.
func _shadow_share(level: BattleLevel) -> void:
	var sun := level.get_node_or_null(^"Sun") as DirectionalLight3D
	if sun == null or not sun.shadow_enabled:
		return
	var before := await _probe(PROBE_FRAMES)
	sun.shadow_enabled = false
	await wait_frames(PROBE_WARMUP)
	var without := await _probe(PROBE_FRAMES)
	sun.shadow_enabled = true
	await wait_frames(PROBE_WARMUP)
	var after := await _probe(PROBE_FRAMES)
	var base := (before + after) * 0.5
	print("  reparto del cuadro con derrumbe: %.0f lotes con sombra direccional,"
			% base + " %.0f sin ella → el pase de sombra son %.0f (%.0f %%)"
			% [without, base - without, 100.0 * (base - without) / maxf(base, 1.0)])


## Media de lotes de dibujo sobre [param frames] cuadros. Es una ventana corta: lo que
## se busca es el **Δ** entre configuraciones, no el número absoluto.
func _probe(frames: int) -> float:
	var total := 0.0
	for _frame: int in frames:
		await get_tree().process_frame
		total += float(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return total / maxf(float(frames), 1.0)


## Posición del primer enemigo del nivel, o el origen si no hay ninguno.
func _boss_position(level: BattleLevel) -> Vector3:
	var manager := level.get_round_manager()
	if manager == null:
		return Vector3.ZERO
	var enemies := manager.get_enemies()
	for index: int in enemies.size():
		var enemy := enemies[index] as EnemyBase
		if enemy != null and is_instance_valid(enemy):
			return enemy.global_position
	return Vector3.ZERO


## Guiona el derrumbe: dos tandas de [constant COLLAPSE_WAVE] edificios, los más
## cercanos a [param anchor], con [constant COLLAPSE_BAKE_SECONDS] entre medias para
## que el escombro de la primera se duerma y se **hornee** en el [RubbleField].
##
## No toca el juego: llama [method Building.take_damage] con el HP máximo, que es
## exactamente lo que hace un proyectil, y deja que la máquina de etapas de
## `docs/10` §3.1 haga el resto.
##
## ## Determinismo
##
## Mientras dura el guion la IA queda congelada con [member Global.debug_freeze_ai]
## (y se restituye el valor previo al salir): sin eso, en los
## [constant COLLAPSE_BAKE_SECONDS] entre tandas el jefe podía derribar alguno de los
## elegidos, y cuántos según los fps de la máquina. Cada tanda vuelve a pedir los
## [constant COLLAPSE_WAVE] edificios en pie más cercanos al ancla, así que un edificio
## que ya cayó por otra causa se reemplaza por el siguiente en vez de saltarse. Si al
## final no cayeron [constant COLLAPSE_TARGETS], o si al abrir la ventana no hay escombro
## vivo **y** campos de ruina horneados, el check falla: medir «con derrumbe» un cuadro
## sin derrumbe haría pasar el presupuesto sin haberlo contrastado.
func _collapse(level: BattleLevel, anchor: Vector3) -> void:
	var freeze_before := Global.debug_freeze_ai
	Global.debug_freeze_ai = true
	print("  derrumbe guionado: %d edificios alrededor de (%.0f, %.0f, %.0f), IA congelada"
			% [COLLAPSE_TARGETS, anchor.x, anchor.y, anchor.z])
	var felled := 0
	var wave := 0
	while felled < COLLAPSE_TARGETS:
		if wave > 0:
			await _settle(COLLAPSE_BAKE_SECONDS)
		wave += 1
		var wanted := mini(COLLAPSE_WAVE, COLLAPSE_TARGETS - felled)
		var targets := _nearest_buildings(level, anchor, wanted)
		if targets.is_empty():
			break
		for building: Building in targets:
			print("    tanda %d · %-26s a %6.1f m"
					% [wave, String(building.get_meta(&"piece", building.name)),
					building.global_position.distance_to(anchor)])
			var _applied := building.take_damage(building.get_max_hp(),
					building.global_position)
			if building.stage == Building.Stage.RUBBLE:
				felled += 1
		if targets.size() < wanted:
			break
	await _settle(COLLAPSE_DUST_SECONDS)
	Global.debug_freeze_ai = freeze_before
	if felled < COLLAPSE_TARGETS:
		fail("el derrumbe guionado tiró %d edificios de %d: el escenario con derrumbe no"
				% [felled, COLLAPSE_TARGETS] + " mide lo que dice")
	var debris := _print_debris(level)
	expect(int(debris["live"]) > 0,
			"al abrir la ventana con derrumbe no hay escombro vivo (%d)" % int(debris["live"]))
	expect(int(debris["fields"]) > 0,
			"al abrir la ventana con derrumbe no hay campos de ruina horneados (%d)"
			% int(debris["fields"]))


## Los [param count] edificios en pie más cercanos a [param anchor], de menor a mayor
## distancia. El desempate por nombre hace reproducible el orden cuando dos caen a la
## misma distancia. El edificio protegido de la ronda queda fuera: derribarlo
## terminaría la partida en mitad de la medición.
func _nearest_buildings(level: BattleLevel, anchor: Vector3, count: int) -> Array[Building]:
	var candidates: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group(Building.GROUP):
		var building := node as Building
		if building == null or not level.is_ancestor_of(building):
			continue
		if building.stage == Building.Stage.RUBBLE or building.is_protected():
			continue
		candidates.append(building)
	candidates.sort_custom(func(a: Building, b: Building) -> bool:
		var da := a.global_position.distance_squared_to(anchor)
		var db := b.global_position.distance_squared_to(anchor)
		if is_equal_approx(da, db):
			return a.name < b.name
		return da < db)
	var picked: Array[Building] = []
	for index: int in mini(count, candidates.size()):
		picked.append(candidates[index])
	return picked


## Deja constancia de lo que hay vivo cuando se abre la ventana con derrumbe: es lo
## que explica el número de lotes. Devuelve los conteos para que [method _collapse]
## asevere que la ventana ve derrumbe de verdad.
func _print_debris(level: BattleLevel) -> Dictionary:
	var pool := get_tree().get_first_node_in_group(DebrisPool.GROUP) as DebrisPool
	var baked := 0
	var live := 0
	var fields := 0
	if pool != null:
		live = pool.get_live_count()
		if pool.rubble_field != null:
			fields = pool.rubble_field.get_field_count()
			baked = pool.rubble_field.get_total_instance_count()
	var piles := 0
	for node: Node in get_tree().get_nodes_in_group(Building.GROUP):
		var building := node as Building
		if building != null and level.is_ancestor_of(building) \
				and building.stage == Building.Stage.RUBBLE:
			piles += 1
	print("  al abrir la ventana: %d escombros vivos · %d horneados en %d campos"
			% [live, baked, fields]
			+ " · %d montículos · %d emisores de ciudad"
			% [piles, Building.active_emitters()])
	return {"live": live, "baked": baked, "fields": fields, "piles": piles}


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
	if _fisheye_msaa_arg >= 0:
		Graphics.fisheye_msaa = _fisheye_msaa_arg as Graphics.FisheyeMsaa
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
##
## [param also_as] guarda **el mismo cuadro** con otros nombres, sin esperar otro
## `frame_post_draw`.
func _capture(file_name: String, also_as: Array[String] = []) -> void:
	if shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		fail("no se pudo capturar '%s': el viewport no devolvió imagen" % file_name)
		return
	var names: Array[String] = [file_name]
	names.append_array(also_as)
	for name_: String in names:
		var path := "%s/%s.png" % [shots_dir, name_]
		var err := image.save_png(path)
		if err != OK:
			fail("no se pudo guardar la captura '%s': %s" % [path, error_string(err)])
			return
		print("  captura: %s" % path)


# --- Informe ----------------------------------------------------------------------------------

## Lee `--fisheye_msaa=OFF/X2/X4/X8/SAME`, que fuerza la palanca de usuario
## [member Graphics.fisheye_msaa] en las tres variantes. Las caras laterales no se
## mueven —[method Graphics.fisheye_side_msaa_level] las tiene acotadas a 2×—, así que
## la bandera cambia sólo la **cara frontal**.
func _read_fisheye_msaa_arg() -> void:
	var raw := String(user_args().get("fisheye_msaa", "")).strip_edges().to_upper()
	if raw.is_empty():
		return
	var wanted := FISHEYE_MSAA_NAMES.find(raw)
	if wanted < 0:
		fail("--fisheye_msaa no conoce '%s' (esperaba %s)"
				% [raw, ", ".join(FISHEYE_MSAA_NAMES)])
		return
	_fisheye_msaa_arg = wanted


func _print_window() -> void:
	var size := DisplayServer.window_get_size()
	print("  ventana %dx%d, vsync apagado, %d cuadros de calentamiento + %.1f s de reposo"
			% [size.x, size.y, WARMUP_FRAMES, SETTLE_SECONDS]
			+ " + %d medidos, en dos escenarios" % WINDOW_FRAMES)
	if _fisheye_msaa_arg >= 0:
		print("  --fisheye_msaa=%s: la cara frontal del ojo de pez se mide con esa palanca"
				% FISHEYE_MSAA_NAMES[_fisheye_msaa_arg])
	if size.x < 1920 or size.y < 1080:
		print("  AVISO: el presupuesto de `docs/15` §5.2 es a 1080p; esta ventana es menor.")


func _print_variant(scenario: String, sample: Dictionary) -> void:
	print("  --- %s ---" % scenario)
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
	print("  %-18s %-13s %8s %8s %8s %9s %9s %10s" % ["variante", "escenario", "fps",
			"p1", "motor", "gpu ms", "draw máx", "ms/tick"])
	for variant: Dictionary in VARIANTS:
		for scenario: Dictionary in SCENARIOS:
			var key := "%s/%s" % [String(variant["id"]), String(scenario["id"])]
			if not _results.has(key):
				continue
			var sample := _results[key]
			print("  %-18s %-13s %8.1f %8.1f %8.1f %9.2f %9.0f %10.3f"
					% [String(variant["label"]), String(scenario["label"]),
					float(sample["fps_wall"]), float(sample["fps_engine_p1"]),
					float(sample["fps_engine"]), float(sample["gpu_ms_total"]),
					float(sample["draw_calls_max"]), float(sample["physics_ms_avg"])])


## Contrasta cada variante con su presupuesto. Acá sí falla el check.
##
## ## Dos presupuestos de lotes, uno por escenario
##
## El pueblo **intacto** se mide contra [constant BATCH_BUDGET_INTACT], que es el tope
## histórico de `docs/15` §5.2 y sigue mandando: es el cuadro que el jugador ve la mayor
## parte de la ronda.
##
## El cuadro **con derrumbe** no. Es un pico transitorio —cuatro edificios cayéndose a la
## vez, polvo, escombro suelto y campos de ruina en el mismo cuadro— y medirlo contra los
## 900 confundía «el pico cuesta más» con «el juego no entra en presupuesto». Su criterio
## vinculante son los **fps**, que el check ya mide y que desde P2d se aseveran también
## acá; los lotes llevan un tope propio ([constant BATCH_BUDGET_COLLAPSE] de pico y
## [constant BATCH_MEAN_COLLAPSE] de media) cuyo trabajo es cazar regresiones grandes, no
## dimensionar el cuadro. La media va aparte del pico a propósito: un máximo se lo lleva
## un solo cuadro, y una media que sube es contenido nuevo.
func _check_budgets() -> void:
	print("")
	print("  --- presupuestos (docs/13 §10.1, docs/15 §5.2) ---")
	print("  lotes: intacto < %.0f máx  ·  con derrumbe < %.0f máx y < %.0f de media"
			% [BATCH_BUDGET_INTACT, BATCH_BUDGET_COLLAPSE, BATCH_MEAN_COLLAPSE]
			+ "  (el criterio vinculante del derrumbe son los fps)")
	for variant: Dictionary in VARIANTS:
		var id := String(variant["id"])
		for scenario: Dictionary in SCENARIOS:
			var key := "%s/%s" % [id, String(scenario["id"])]
			var label := "%s %s" % [id, String(scenario["label"])]
			if not _results.has(key):
				fail("la variante '%s' no llegó a medirse en %s"
						% [id, String(scenario["label"])])
				continue
			var sample := _results[key]
			var fps_min := float(variant["fps_min"])
			var p1_min := float(variant["p1_min"])
			if fps_min > 0.0:
				_verdict(label, "fps medio", float(sample["fps_wall"]), fps_min, true)
			if p1_min > 0.0:
				_verdict(label, "percentil 1", float(sample["fps_engine_p1"]),
						p1_min, true)
			_verdict(label, "draw calls máx", float(sample["draw_calls_max"]),
					float(scenario["batch_max"]), false)
			var mean_max := float(scenario["batch_mean"])
			if mean_max > 0.0:
				_verdict(label, "draw calls media", float(sample["draw_calls_avg"]),
						mean_max, false)


## Imprime y registra un presupuesto. [param minimum] en `true` es «al menos».
func _verdict(id: String, label: String, value: float, limit: float, minimum: bool) -> void:
	var ok := value >= limit if minimum else value < limit
	print("  %s %-24s %-16s %9.1f (presupuesto %s %.1f)"
			% ["OK  " if ok else "FALLA", id, label, value, "≥" if minimum else "<", limit])
	if not ok:
		fail("%s: %s %.1f fuera del presupuesto (%s %.1f)"
				% [id, label, value, "≥" if minimum else "<", limit])
