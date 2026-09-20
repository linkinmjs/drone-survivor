## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de la ronda (`docs/11` §11, `docs/15` §2).
##
## Corre la ronda 1 **sin jugarla**: nadie dispara, el jefe no ataca y los hechos se
## inyectan por el bus. Es la prueba de que la máquina de estados, el puntaje y la
## persistencia funcionan sin depender de que la IA del coloso (WP-18/19) ni el arma
## hagan nada.
##
## Comando:
## `"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/round_check.tscn`
##
## Las catorce filas de `docs/11` §11, en orden, con una línea `OK`/`FAIL` por fila.
## El check nunca deja [member Engine.time_scale] ni el `.cfg` modificados: la fila 13
## restaura el progreso y lo verifica **releyendo el archivo**, y [CheckRunner] trabaja
## además sobre una carpeta de configuración propia del proceso.
extends CheckRunner

const LEVEL_SCENE: String = "res://rounds/battle_level.tscn"

## Ronda que se ejercita. Es el id estable del catálogo, no un índice.
const ROUND_ID: String = "first-contact"

## Id de catálogo del jefe de la ronda 1.
const ENEMY_ID: StringName = &"arachnodroid"

## Semilla fija de las filas 3 y 7.
const SEED_A: int = 12345

## Segunda semilla de la fila 7.
const SEED_B: int = 54321

## Plazo de cada espera intermedia; el timeout global lo pone [CheckRunner].
const STEP_TIMEOUT_SECONDS: float = 20.0

## Par de tiempo con el que se verifica la fórmula (fila 9).
const TIME_PAR: float = 540.0

## Tolerancia de huérfanos tras liberar el nivel (fila 14).
const ORPHAN_TOLERANCE: int = 0

## Filas de la tabla de `docs/11` §11, en orden. La 15 la agrega WP-24d y la 16
## WP-25b.
const ROW_TITLES: Array[String] = [
	"catálogo consistente", "respaldo de configuración", "instanciado", "estado inicial",
	"salteo de la cinemática", "objetivos", "determinismo de semilla", "victoria",
	"puntaje", "persistencia", "derrota", "prioridad", "restauración", "sin huérfanos",
	"secuencia completa", "edificio protegido",
]

## Nombre de nodo y clave del edificio protegido de la ronda 1 (`docs/11` §1).
const PROTECTED_NODE: String = "Building_8_4"
const PROTECTED_KEY: String = "BLD_SCHOOL_12"

## Tolerancia del cociente entre lo que cuesta la escuela y lo que cuesta un bloque
## igual. Es una división de dos restas de coma flotante sobre 127 300 HP.
const PROTECTED_WEIGHT_TOLERANCE: float = 0.02

## Las cuatro rodillas del Arachnodroid, en el orden del perfil (`docs/07` §4).
const KNEE_IDS: Array[StringName] = [
	&"wp_leg_fl_knee", &"wp_leg_fr_knee", &"wp_leg_bl_knee", &"wp_leg_br_knee",
]

## Los tres núcleos ventrales (`docs/07` §4).
const CORE_IDS: Array[StringName] = [&"wp_core_a", &"wp_core_b", &"wp_core_c"]

## Comando con el que se dejan los cuatro motores en régimen de vuelo antes de la
## tarjeta de resultado. El lazo de control se desengancha para poder fijarlo.
const MOTOR_COMMAND: float = 0.7

## Ticks que se le dan al audio de motores para llegar a régimen.
const MOTOR_SETTLE_TICKS: int = 90

## Ticks de física que se le dan para callarse al congelar el dron, y el plazo en
## segundos de **tiempo de juego** que no puede pasar. Los ticks son muchos porque
## el desenlace corre a `OUTRO_TIME_SCALE` (×0.35) y cada uno vale 3.5 ms de juego.
const MOTOR_SILENCE_TICKS: int = 150
const MOTOR_SILENCE_BUDGET: float = 1.0

## Cuántos objetivos tiene la cadena de la ronda 1 tras WP-24d (`docs/11` §5).
const CHAIN_LENGTH: int = 5

## Meta de los contadores «RODILLAS n/3» y «NÚCLEOS n/3».
const COUNT_TARGET: int = 3

## Estados publicados por `Events.round_state_changed` desde que arrancó el check.
var _states: Array[int] = []

## Índices publicados por `ObjectiveSequencer.objective_started`.
var _objective_starts: Array[int] = []

## Veces que la ronda en curso emitió `RoundManager.alert_finished`.
var _alert_finished_count: int = 0

## Respaldo de la fila 2: `{clave: valor}` de `GameSettings.rounds` al empezar.
var _rounds_backup: Dictionary = {}

## Resultado de cada fila: `{número: todas sus comprobaciones pasaron}`.
var _rows: Dictionary[int, bool] = {}


func _run() -> void:
	# El nodo del check deja de ser la escena actual para sobrevivir a los niveles.
	get_tree().current_scene = null
	# `docs/11` §11: el jefe no piensa ni se mueve; los hechos se inyectan por el bus.
	Global.debug_freeze_ai = true
	var _discard := Events.round_state_changed.connect(_on_round_state_changed)

	_check_catalog()
	_backup_config()
	if not ResourceLoader.exists(LEVEL_SCENE):
		fail("falta el nivel de batalla (%s)" % LEVEL_SCENE)
	else:
		await _check_victory_run()
		_check_score_formula()
		await _check_defeat_run()
		await _check_priority_run()
		await _check_sequence_run()
		await _check_protected_run()
	_restore_config()
	Global.debug_freeze_ai = false
	Events.round_state_changed.disconnect(_on_round_state_changed)
	_print_rows()


# --- Fila 1: catálogo consistente -------------------------------------------------------------

func _check_catalog() -> void:
	_row(1, RoundCatalog.count() == 1,
			"1 · el catálogo tiene una ronda (tiene %d)" % RoundCatalog.count())
	var ids: Dictionary[String, bool] = {}
	for index: int in RoundCatalog.count():
		var id := String(RoundCatalog.get_round(index)["id"])
		_row(1, not ids.has(id), "1 · el id '%s' está repetido en el catálogo" % id)
		ids[id] = true
	var first := String(RoundCatalog.get_round(0).get("id", ""))
	_row(1, first == ROUND_ID, "1 · la ronda 0 es '%s' (es '%s')" % [ROUND_ID, first])
	_row(1, RoundCatalog.get_index(first) == 0,
			"1 · get_index('%s') devuelve 0 (devuelve %d)" % [first, RoundCatalog.get_index(first)])
	_row(1, RoundCatalog.get_round(-1).is_empty(), "1 · un índice inválido devuelve {}")
	_row(1, RoundCatalog.get_by_id("no-existe").is_empty(), "1 · un id inexistente devuelve {}")
	_row(1, is_equal_approx(float(RoundCatalog.get_round(0)["time_par"]), TIME_PAR),
			"1 · el par de tiempo de la ronda 1 es %.0f s" % TIME_PAR)
	# Umbrales recalibrados en WP-23 con los puntajes medidos por `balance_check`:
	# bronce 350, plata 800, oro 2000 (`docs/11` §12, fila 3).
	_row(1, RoundCatalog.medal_for(0, 1999) == RoundCatalog.Medal.SILVER,
			"1 · 1999 puntos son plata (son %d)" % RoundCatalog.medal_for(0, 1999))
	_row(1, RoundCatalog.medal_for(0, 2000) == RoundCatalog.Medal.GOLD,
			"1 · 2000 puntos son oro (son %d)" % RoundCatalog.medal_for(0, 2000))
	_row(1, RoundCatalog.medal_for(0, 349) == RoundCatalog.Medal.NONE,
			"1 · 349 puntos no dan medalla (dan %d)" % RoundCatalog.medal_for(0, 349))
	_row(1, RoundCatalog.medal_for(0, 350) == RoundCatalog.Medal.BRONZE,
			"1 · 350 puntos son bronce (son %d)" % RoundCatalog.medal_for(0, 350))
	_row(1, RoundCatalog.medal_for(0, 800) == RoundCatalog.Medal.SILVER,
			"1 · 800 puntos son plata (son %d)" % RoundCatalog.medal_for(0, 800))
	_row(1, RoundCatalog.is_unlocked(0), "1 · la ronda 0 está siempre desbloqueada")
	_row(1, RoundCatalog.level_scene_for(RoundCatalog.get_round(0)) == LEVEL_SCENE,
			"1 · la ronda 1 manda al nivel de batalla")


# --- Fila 2: respaldo de configuración --------------------------------------------------------

func _backup_config() -> void:
	_rounds_backup = GameSettings.rounds.duplicate(true)
	print("  2 · respaldo en memoria: best_score=%d best_time=%.2f"
			% [GameSettings.get_best_score(ROUND_ID), GameSettings.get_best_time(ROUND_ID)])
	# Se arranca con la ronda sin jugar para que la fila 10 mida un récord de verdad.
	var _dropped := GameSettings.rounds.erase("best_score_%s" % ROUND_ID)
	_dropped = GameSettings.rounds.erase("best_time_%s" % ROUND_ID)
	_row(2, GameSettings.get_best_score(ROUND_ID) == 0,
			"2 · el respaldo deja la ronda sin récord para la pasada del check")


# --- Filas 3 a 10 y 14: pasada de victoria ----------------------------------------------------

func _check_victory_run() -> void:
	var before_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var level := await _enter_level(SEED_A)
	if level == null:
		return
	var manager := level.get_round_manager()

	_check_spawning(manager)
	_check_initial_state(manager)
	var enemy := _first_enemy(manager)
	await _check_skip_and_objectives(manager, enemy)
	_check_seed_determinism()
	await _check_victory(manager, enemy)

	await _discard_level(level)
	var after_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_row(14, after_orphans - before_orphans <= ORPHAN_TOLERANCE,
			"14 · la pasada de victoria no deja huérfanos (antes %d, después %d)"
					% [before_orphans, after_orphans])


## Fila 3: el distrito y el jefe entran desde el catálogo.
func _check_spawning(manager: RoundManager) -> void:
	_row(3, manager.district_root.get_child_count() == 1,
			"3 · District tiene un hijo (tiene %d)" % manager.district_root.get_child_count())
	var enemies := manager.get_enemies()
	_row(3, enemies.size() == 1, "3 · Enemies tiene un enemigo (tiene %d)" % enemies.size())
	_row(3, not enemies.is_empty() and enemies[0] is EnemyBase,
			"3 · el enemigo instanciado es un EnemyBase")
	_row(3, manager.get_round_id() == ROUND_ID,
			"3 · la ronda en curso es '%s' (es '%s')" % [ROUND_ID, manager.get_round_id()])


## Fila 4: la ronda abre en la **alerta del taller** y lo publica (WP-25b).
func _check_initial_state(manager: RoundManager) -> void:
	_row(4, manager.get_state() == Global.RoundState.ALERT,
			"4 · la ronda arranca en ALERT (arranca en %d)" % manager.get_state())
	_row(4, _states.has(Global.RoundState.ALERT),
			"4 · se publicó round_state_changed(ALERT)")
	_row(4, not _states.has(Global.RoundState.INTRO),
			"4 · la INTRO todavía no empezó: la alerta va primero")
	_row(4, manager.get_alert_remaining() > 0.0
					and manager.get_alert_remaining() <= RoundManager.ALERT_SECONDS,
			"4 · quedan %.2f s de alerta (de %.1f)"
					% [manager.get_alert_remaining(), RoundManager.ALERT_SECONDS])


## Filas 5 y 6: el salteo va de a un estado, es irreversible y los objetivos avanzan
## por el bus.
func _check_skip_and_objectives(manager: RoundManager, enemy: EnemyBase) -> void:
	var sequencer := manager.sequencer
	var _discard := sequencer.objective_started.connect(_on_objective_started)
	_discard = manager.alert_finished.connect(_on_alert_finished)

	manager.skip_intro()
	_row(5, manager.get_state() == Global.RoundState.INTRO,
			"5 · el primer skip_intro() saltea la alerta y pasa a INTRO (quedó en %d)"
					% manager.get_state())
	_row(5, _alert_finished_count == 1,
			"5 · saltear la alerta emite alert_finished una sola vez (emitió %d)"
					% _alert_finished_count)
	_row(5, is_equal_approx(manager.get_alert_remaining(), 0.0),
			"5 · fuera de ALERT no queda alerta pendiente (queda %.2f s)"
					% manager.get_alert_remaining())
	manager.skip_intro()
	_row(5, manager.get_state() == Global.RoundState.BATTLE,
			"5 · el segundo skip_intro() pasa a BATTLE en el mismo frame (quedó en %d)"
					% manager.get_state())
	var states_after_skip := _states.size()
	manager.skip_intro()
	_row(5, manager.get_state() == Global.RoundState.BATTLE
					and _states.size() == states_after_skip,
			"5 · un tercer skip_intro() no cambia nada")
	_row(5, _alert_finished_count == 1,
			"5 · alert_finished no se repite en el resto de la ronda (emitió %d)"
					% _alert_finished_count)

	_row(6, _objective_starts.has(0), "6 · se publicó objective_started(0)")
	_row(6, sequencer.count() == CHAIN_LENGTH,
			"6 · la cadena de la ronda 1 tiene %d objetivos (tiene %d)"
					% [CHAIN_LENGTH, sequencer.count()])
	var objective := sequencer.get_current()
	_row(6, objective != null, "6 · hay un objetivo en curso tras el salteo")
	if objective == null:
		return
	_row(6, objective is ObjectiveDefendCity,
			"6 · el primer objetivo de la cadena es ObjectiveDefendCity")
	_row(6, not objective.get_task_text().is_empty(), "6 · el objetivo tiene texto de tarea")
	var progress := objective.get_progress()
	_row(6, progress >= 0.0 and progress <= 1.0,
			"6 · el progreso del objetivo está en [0, 1] (es %.3f)" % progress)

	# Los objetivos avanzan por hechos del bus, no por su cuenta (`docs/11` §5).
	Events.enemy_part_broken.emit(enemy, KNEE_IDS[0], Vector3.ZERO)
	Events.enemy_part_broken.emit(enemy, KNEE_IDS[1], Vector3.ZERO)
	# El contador de rodillas de WP-24d vive ya en el **primer** objetivo, y es el
	# mismo número con el que arranca el segundo: por eso encadenan.
	var defend := objective as ObjectiveDefendCity
	_row(6, defend != null and defend.get_broken_count() == 2,
			"6 · ObjectiveDefendCity cuenta las 2 rodillas rotas (cuenta %d)"
					% (defend.get_broken_count() if defend != null else -1))
	sequencer.skip_current()
	await wait_frames(1)
	var second := sequencer.get_current()
	_row(6, second is ObjectiveBreakParts and not (second is ObjectiveBreakCores),
			"6 · el segundo objetivo de la cadena es ObjectiveBreakParts")
	if not (second is ObjectiveBreakParts):
		return
	var parts := second as ObjectiveBreakParts
	_row(6, parts.get_broken_count() == 2,
			"6 · ObjectiveBreakParts recupera las 2 rodillas ya rotas (cuenta %d)"
					% parts.get_broken_count())
	var expected := tr(parts.count_key).format([2, COUNT_TARGET])
	_row(6, parts.get_progress_text() == expected and expected != parts.count_key,
			"6 · el texto de progreso es '%s' (es '%s')"
					% [expected, parts.get_progress_text()])
	Events.enemy_part_broken.emit(enemy, KNEE_IDS[2], Vector3.ZERO)
	_row(6, not parts.active, "6 · la tercera rodilla cierra ObjectiveBreakParts")
	await _check_survive_time(manager)


## `ObjectiveSurviveTime` se implementa y se verifica en WP-21 pero **no** está en la
## cadena de la ronda 1 (`docs/11` §5), así que se ejercita suelto: fuera del
## secuenciador, con un plazo corto, y se comprueba que cuenta, informa y cierra.
func _check_survive_time(manager: RoundManager) -> void:
	var survive := ObjectiveSurviveTime.new()
	survive.name = "SurviveProbe"
	survive.seconds = 0.2
	survive.title_key = "OBJ_SURVIVE_TIME_TITLE"
	survive.objective_key = "OBJ_SURVIVE_TIME_DESC"
	add_child(survive)
	survive.setup(manager.get_context())
	var completed: Array[bool] = [false]
	var _discard := survive.completed.connect(func() -> void: completed[0] = true)
	survive.start()
	_row(6, is_equal_approx(survive.get_progress(), 0.0),
			"6 · ObjectiveSurviveTime arranca en 0 (arranca en %.3f)" % survive.get_progress())
	_row(6, survive.get_progress_text() == "0:01",
			"6 · la cuenta regresiva se formatea como m:ss (dice '%s')"
					% survive.get_progress_text())
	await wait_physics(30)
	_row(6, completed[0], "6 · ObjectiveSurviveTime cierra al cumplirse el plazo")
	_row(6, not survive.active, "6 · ObjectiveSurviveTime queda inactivo al cerrar")
	survive.stop()
	survive.queue_free()


## Fila 7: la semilla derivada es estable por etiqueta y cambia con la semilla maestra.
func _check_seed_determinism() -> void:
	Global.round_seed = SEED_A
	var batteries := RoundManager.derive_seed("batteries")
	Global.round_seed = SEED_A
	_row(7, RoundManager.derive_seed("batteries") == batteries,
			"7 · derive_seed('batteries') es estable con la misma semilla")
	_row(7, RoundManager.derive_seed("intro") != batteries,
			"7 · dos etiquetas distintas dan semillas distintas")
	_row(7, RoundCatalog.derive_seed("batteries") == batteries,
			"7 · RoundManager.derive_seed delega en RoundCatalog")
	Global.round_seed = SEED_B
	_row(7, RoundManager.derive_seed("batteries") != batteries,
			"7 · con otra semilla, derive_seed('batteries') cambia")
	Global.round_seed = SEED_A


## Filas 8 y 10: el bus decide la victoria, la tarjeta aparece y el récord se guarda.
func _check_victory(manager: RoundManager, enemy: EnemyBase) -> void:
	var audio := await _spin_up_motors(manager)
	Events.enemy_defeated.emit(enemy, ENEMY_ID)
	var won := await _wait_until(func() -> bool:
			return manager.get_state() == Global.RoundState.VICTORY)
	_row(8, won, "8 · el bus decide la victoria en menos de %.0f s" % STEP_TIMEOUT_SECONDS)
	await _check_motor_audio_stops(manager, audio)
	var card_up := await _wait_until(func() -> bool: return manager.get_result_card() != null)
	_row(8, card_up, "8 · la victoria termina mostrando la tarjeta de resultado")
	_row(8, is_equal_approx(Engine.time_scale, 1.0),
			"8 · Engine.time_scale vuelve a 1.0 (quedó en %.3f)" % Engine.time_scale)
	# Un hecho tardío no reabre una ronda terminada.
	Events.city_integrity_changed.emit(0.10)
	await wait_frames(2)
	_row(8, manager.get_state() == Global.RoundState.VICTORY,
			"8 · VICTORY es terminal: un hecho tardío no la reabre")

	var result := manager.get_result()
	_row(8, result != null, "8 · la ronda dejó un RoundResult")
	if result == null:
		return
	_row(10, GameSettings.get_best_score(ROUND_ID) == result.score,
			"10 · el récord guardado es el puntaje de la partida (%d vs %d)"
					% [GameSettings.get_best_score(ROUND_ID), result.score])
	_row(10, result.is_record, "10 · la primera victoria es récord")
	_row(10, not GameSettings.record_score(ROUND_ID, result.score - 1),
			"10 · un puntaje peor devuelve false")
	_row(10, GameSettings.get_best_score(ROUND_ID) == result.score,
			"10 · un puntaje peor no pisa el récord")
	_row(10, GameSettings.has_completed(ROUND_ID),
			"10 · la ronda queda marcada como completada")


## Deja los cuatro motores en régimen de vuelo y devuelve el [MotorAudio] del rig.
##
## Sin esto el dron de `round_check` nunca arma —no hay piloto— y el audio ya está
## en silencio cuando llega la tarjeta, así que comprobar el corte no probaría nada.
## El lazo de control se desengancha igual que en `audio_check`: lo que se mide es
## régimen → volumen, no vuelo.
func _spin_up_motors(manager: RoundManager) -> MotorAudio:
	var rig := manager.drone_rig
	if rig == null or not is_instance_valid(rig):
		return null
	var audio := rig.get_motor_audio()
	var drone := rig.get_drone()
	if audio == null or drone == null:
		return null
	var radio := rig.get_radio()
	if radio != null:
		radio.enabled = false
	drone.set_controller(null)
	var commands: Array[float] = [MOTOR_COMMAND, MOTOR_COMMAND, MOTOR_COMMAND, MOTOR_COMMAND]
	drone.test_motor_commands = commands
	if not drone.arm():
		_row(8, false, "8 · no se pudo armar el dron para medir el corte del audio de motores")
		return null
	await wait_physics(MOTOR_SETTLE_TICKS)
	return audio


## Fila 8 (WP-24e): congelar el dron para la tarjeta apaga el audio de motores.
##
## `RoundManager._freeze_drone(true)` usa el mismo `freeze` que la reconstrucción, y
## con el cuerpo congelado no corre `Drone._integrate_forces()`: las rpm se quedan
## clavadas. Hasta WP-24e los ocho loops de [MotorAudio] seguían con el volumen y el
## tono del último cuadro vivo, así que el dron zumbaba **indefinidamente** sobre la
## tarjeta de VICTORY o de DEFEAT. El plazo se mide en tiempo de juego porque el
## desenlace corre en cámara lenta.
func _check_motor_audio_stops(manager: RoundManager, audio: MotorAudio) -> void:
	if audio == null:
		return
	var drone := manager.drone_rig.get_drone() if manager.drone_rig != null else null
	_row(8, drone != null and drone.freeze,
			"8 · el estado terminal deja el dron congelado (freeze %s)"
					% str(drone != null and drone.freeze))
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	var seconds := 0.0
	var ticks := 0
	while ticks < MOTOR_SILENCE_TICKS and audio.get_active_voice_count() > 0:
		seconds += step * Engine.time_scale
		await wait_physics(1)
		ticks += 1
	var left := audio.get_active_voice_count()
	print("  MotorAudio: %d voces %.3f s de juego (%d ticks) después de congelar el dron para la tarjeta"
			% [left, seconds, ticks])
	_row(8, left == 0 and seconds <= MOTOR_SILENCE_BUDGET,
			"8 · con el dron congelado por la tarjeta el audio de motores se detiene:"
					+ " quedaron %d voces tras %.3f s de juego (tope %.1f s)"
					% [left, seconds, MOTOR_SILENCE_BUDGET])


# --- Fila 9: la fórmula de puntaje ------------------------------------------------------------

## Los tres casos tabulados en `docs/11` §11, fila 9, con `time_par` 540 s.
func _check_score_formula() -> void:
	# **Bono de tiempo 25 → 8 pts/s (WP-23, `docs/11` §12 fila 3).** Con 0.9 de
	# integridad, 8 partes, 0 muertes y t = 400 s contra un par de 540:
	# `1000·0.9 + 40·8 − 0 + (540 − 400)·8` = `900 + 320 + 1120` = **2 340**.
	var clean := _result_for(0.9, 8, 0, 400.0)
	_row(9, clean.base_score == 2340, "9 · base sin muertes es 2340 (es %d)" % clean.base_score)
	_row(9, clean.score == 2340, "9 · puntaje sin muertes es 2340 (es %d)" % clean.score)
	_row(9, is_equal_approx(clean.respawn_multiplier, 1.0),
			"9 · sin muertes el multiplicador es 1.0 (es %.3f)" % clean.respawn_multiplier)
	_row(9, clean.medal == RoundCatalog.Medal.GOLD,
			"9 · 4720 puntos dan oro (dan %d)" % clean.medal)

	# El mismo caso con una muerte: `900 + 320 − 300 + 1120` = **2 040**, y
	# `round(2040 · 0.6)` = **1 224**.
	var one_death := _result_for(0.9, 8, 1, 400.0)
	_row(9, one_death.base_score == 2040,
			"9 · base con una muerte es 2040 (es %d)" % one_death.base_score)
	_row(9, is_equal_approx(one_death.respawn_multiplier, 0.6),
			"9 · con una muerte el multiplicador es 0.6 (es %.3f)" % one_death.respawn_multiplier)
	_row(9, one_death.score == 1224,
			"9 · puntaje con una muerte es 1224 (es %d)" % one_death.score)

	var floored := _result_for(0.9, 8, 4, 400.0)
	_row(9, is_equal_approx(floored.respawn_multiplier, 0.30),
			"9 · con cuatro muertes el multiplicador toca el piso 0.30 (es %.3f)"
					% floored.respawn_multiplier)

	# El puntaje nunca baja de cero, por mal que salga la partida.
	var awful := _result_for(0.05, 0, 6, 900.0)
	_row(9, awful.score == 0, "9 · una partida desastrosa da 0 y no un negativo (da %d)"
			% awful.score)
	_row(9, awful.base_score < 0,
			"9 · la base sí puede ser negativa antes del recorte (es %d)" % awful.base_score)


## [RoundResult] ya puntuado con los parámetros de un caso de la tabla.
func _result_for(integrity: float, parts: int, deaths: int, seconds: float) -> RoundResult:
	var result := RoundResult.new()
	result.round_id = ROUND_ID
	# Los tres casos de la tabla son partidas **ganadas**: desde WP-19b el bono de
	# tiempo sólo lo cobra la victoria, así que sin esto los números de `docs/11`
	# §11 fila 9 dejarían de salir.
	result.victory = true
	result.city_integrity = integrity
	result.parts_broken = parts
	result.deaths = deaths
	result.time_seconds = seconds
	var _score := result.compute_score(TIME_PAR)
	var _medal := result.resolve_medal(0)
	return result


# --- Fila 11: derrota por integridad ----------------------------------------------------------

## Segunda pasada: la integridad por debajo del umbral pierde la ronda y **no** escribe
## récord (`docs/11` §7).
func _check_defeat_run() -> void:
	var best_before := GameSettings.get_best_score(ROUND_ID)
	var time_before := GameSettings.get_best_time(ROUND_ID)
	var level := await _enter_level(SEED_A)
	if level == null:
		return
	var manager := level.get_round_manager()
	manager.skip_to_battle()
	Events.city_integrity_changed.emit(0.30)
	var lost := await _wait_until(func() -> bool:
			return manager.get_state() == Global.RoundState.DEFEAT)
	_row(11, lost, "11 · integridad 0.30 pierde la ronda")
	var card_up := await _wait_until(func() -> bool: return manager.get_result_card() != null)
	_row(11, card_up, "11 · la derrota también muestra la tarjeta de resultado")
	var result := manager.get_result()
	_row(11, result != null and not result.victory,
			"11 · el resultado queda marcado como derrota")
	_row(11, result != null and not result.is_record,
			"11 · la derrota no se marca como récord")
	_row(11, GameSettings.get_best_score(ROUND_ID) == best_before,
			"11 · la derrota no escribe best_score (%d vs %d)"
					% [GameSettings.get_best_score(ROUND_ID), best_before])
	_row(11, is_equal_approx(GameSettings.get_best_time(ROUND_ID), time_before),
			"11 · la derrota no escribe best_time")
	# **Sin medalla en derrota y sin bono de tiempo** (WP-19b): perder rápido
	# cobraba el bono y una derrota con la ciudad al 34.9 % salía con PLATA.
	_row(11, result != null and result.medal == RoundCatalog.Medal.NONE,
			"11 · la derrota no da medalla (da %d)"
					% (result.medal if result != null else -1))
	var defeat_bonus := RoundResult.new()
	defeat_bonus.round_id = ROUND_ID
	defeat_bonus.victory = false
	defeat_bonus.city_integrity = 0.349
	defeat_bonus.parts_broken = 8
	defeat_bonus.time_seconds = 200.0
	var _defeat_score := defeat_bonus.compute_score(TIME_PAR)
	var _defeat_medal := defeat_bonus.resolve_medal(0)
	_row(11, defeat_bonus.base_score == 669,
			"11 · una derrota a los 200 s no cobra bono de tiempo (base %d, esperada 669)"
					% defeat_bonus.base_score)
	_row(11, defeat_bonus.medal == RoundCatalog.Medal.NONE,
			"11 · esa derrota no da medalla pese a los %d puntos (da %d)"
					% [defeat_bonus.score, defeat_bonus.medal])
	_row(11, is_equal_approx(Engine.time_scale, 1.0),
			"11 · Engine.time_scale vuelve a 1.0 tras la derrota (quedó en %.3f)" % Engine.time_scale)
	await _discard_level(level)


# --- Filas 12 y 14: prioridad y huérfanos -----------------------------------------------------

## Tercera pasada: victoria y derrota en el **mismo frame**. Gana la derrota
## (`docs/11` §4.1 y §12, fila 11: es la autodestrucción del jefe en P5).
func _check_priority_run() -> void:
	var before_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var before_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var level := await _enter_level(SEED_B)
	if level == null:
		return
	var manager := level.get_round_manager()
	var enemy := _first_enemy(manager)
	manager.skip_to_battle()
	Events.enemy_defeated.emit(enemy, ENEMY_ID)
	Events.city_integrity_changed.emit(0.30)
	var terminal := await _wait_until(_is_terminal.bind(manager))
	_row(12, terminal, "12 · la ronda termina con los dos hechos en el mismo frame")
	_row(12, manager.get_state() == Global.RoundState.DEFEAT,
			"12 · con victoria y derrota en el mismo frame gana la derrota (quedó en %d)"
					% manager.get_state())

	await _discard_level(level)
	var after_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var after_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_row(14, after_orphans - before_orphans <= ORPHAN_TOLERANCE,
			"14 · liberar el nivel no deja huérfanos (antes %d, después %d)"
					% [before_orphans, after_orphans])
	print("  14 · nodos vivos: antes %d, después %d" % [before_nodes, after_nodes])


# --- Fila 15: la secuencia entera con hechos sintéticos ---------------------------------------

## Recorre la cadena de WP-24d de punta a punta inyectando **sólo** hechos del bus.
##
## Es la fila que responde al feedback que gobierna WP-24d: la cadena vieja se
## verificaba a pedazos —fila 6 salteaba el primer objetivo a mano— y nunca se probó
## que los cinco eslabones se encadenaran solos. Acá no hay un solo `skip_current()`:
## tres rodillas llevan a los núcleos, `p5_selfdestruct` lleva a la detonación y
## `enemy_defeated` termina la ronda.
##
## El jefe está congelado (`docs/11` §11), así que las fases no se reevalúan y los
## objetivos las leen del **evento**, que es para lo que existe
## [method Objective.phase_index_of].
func _check_sequence_run() -> void:
	var level := await _enter_level(SEED_A)
	if level == null:
		return
	var manager := level.get_round_manager()
	var sequencer := manager.sequencer
	var enemy := _first_enemy(manager)
	if sequencer == null or enemy == null:
		_row(15, false, "15 · la ronda no trae secuenciador o enemigo")
		await _discard_level(level)
		return
	manager.skip_to_battle()
	await wait_frames(1)

	# 0 · CONTENÉ EL ASEDIO, con el contador de rodillas.
	var defend := sequencer.get_current() as ObjectiveDefendCity
	_row(15, defend != null, "15 · la cadena abre con ObjectiveDefendCity")
	Events.enemy_part_broken.emit(enemy, KNEE_IDS[0], Vector3.ZERO)
	var knee_text := tr("OBJ_COUNT_KNEES").format([1, COUNT_TARGET])
	_row(15, defend != null and defend.get_progress_text() == knee_text,
			"15 · con una rodilla rota el contador dice '%s' (dice '%s')"
					% [knee_text, defend.get_progress_text() if defend != null else ""])

	# 0 → 1 · la fase `p2_alert` cierra el asedio.
	Events.enemy_phase_changed.emit(enemy, &"p2_alert")
	var at_parts := await _wait_for_index(sequencer, 1)
	_row(15, at_parts and sequencer.get_current() is ObjectiveBreakParts,
			"15 · p2_alert lleva al objetivo de las rodillas (índice %d)"
					% sequencer.current_index)

	# 1 → 2 · las tres rodillas abren la carcasa.
	Events.enemy_part_broken.emit(enemy, KNEE_IDS[1], Vector3.ZERO)
	Events.enemy_part_broken.emit(enemy, KNEE_IDS[2], Vector3.ZERO)
	var at_cores := await _wait_for_index(sequencer, 2)
	var cores := sequencer.get_current() as ObjectiveBreakCores
	_row(15, at_cores and cores != null,
			"15 · 3 rodillas llevan al objetivo de los núcleos (índice %d)"
					% sequencer.current_index)
	var core_text := tr("OBJ_COUNT_CORES").format([0, COUNT_TARGET])
	_row(15, cores != null and cores.get_progress_text() == core_text
					and core_text != "OBJ_COUNT_CORES",
			"15 · el contador de núcleos dice '%s' (dice '%s')"
					% [core_text, cores.get_progress_text() if cores != null else ""])
	_row(15, cores != null and tr(cores.get_task_text()) != cores.get_task_text(),
			"15 · la tarea de los núcleos está traducida ('%s')"
					% (cores.get_task_text() if cores != null else ""))

	# 2 → 3 · dos núcleos rotos arrancan la autodestrucción (`docs/07` §6).
	Events.enemy_part_broken.emit(enemy, CORE_IDS[0], Vector3.ZERO)
	Events.enemy_part_broken.emit(enemy, CORE_IDS[1], Vector3.ZERO)
	Events.enemy_phase_changed.emit(enemy, &"p5_selfdestruct")
	var at_fuse := await _wait_for_index(sequencer, 3)
	var fuse := sequencer.get_current() as ObjectiveSelfdestruct
	_row(15, at_fuse and fuse != null,
			"15 · p5_selfdestruct lleva al objetivo de la detonación (índice %d)"
					% sequencer.current_index)
	# La cuenta atrás del jefe no tiene arranque público y con la IA congelada
	# `_tick_selfdestruct` no corre (`docs/11` §11), así que el check escribe los tres
	# campos que escribiría `_start_selfdestruct` y el valor se queda quieto.
	enemy.set(&"_selfdestruct_left", 45.0)
	enemy.set(&"_selfdestruct_total", 45.0)
	enemy.set(&"_selfdestruct_running", true)
	_row(15, fuse != null and fuse.get_progress_text() == "0:45",
			"15 · la cuenta regresiva se formatea como m:ss (dice '%s')"
					% (fuse.get_progress_text() if fuse != null else ""))
	_row(15, fuse != null and is_equal_approx(fuse.get_progress(), 0.0),
			"15 · la mecha arranca en 0 (arranca en %.3f)"
					% (fuse.get_progress() if fuse != null else -1.0))

	# 3 → 4 · `enemy_defeated` cierra la detonación y la ronda.
	_row(15, sequencer.objectives.size() == CHAIN_LENGTH
					and sequencer.objectives[CHAIN_LENGTH - 1] is ObjectiveDefeatEnemy,
			"15 · el último eslabón de la cadena sigue siendo ObjectiveDefeatEnemy")
	Events.enemy_defeated.emit(enemy, ENEMY_ID)
	await wait_frames(1)
	_row(15, fuse != null and not fuse.active,
			"15 · enemy_defeated cierra el objetivo de la detonación")
	var won := await _wait_until(func() -> bool:
			return manager.get_state() == Global.RoundState.VICTORY)
	_row(15, won, "15 · la secuencia entera termina en VICTORY")
	# Igual que la fila 8: hay que dejar terminar el remate para que
	# [member Engine.time_scale] vuelva a 1.0 antes de tirar el nivel, o la fila 13
	# encontraría el reloj del juego en cámara lenta.
	var card_up := await _wait_until(func() -> bool: return manager.get_result_card() != null)
	_row(15, card_up and is_equal_approx(Engine.time_scale, 1.0),
			"15 · la tarjeta aparece y Engine.time_scale vuelve a 1.0 (quedó en %.3f)"
					% Engine.time_scale)
	await _discard_level(level)


## Espera a que el secuenciador esté corriendo el objetivo [param index].
func _wait_for_index(sequencer: ObjectiveSequencer, index: int) -> bool:
	return await _wait_until(func() -> bool:
			return sequencer.current_index == index and sequencer.is_running())


# --- Fila 16: edificio protegido (WP-25b) -----------------------------------------------------

## El edificio con nombre de la ronda: que exista, que pese el triple y que su caída
## se cuente en el objetivo y en el resultado (`docs/11` §1).
##
## La pasada es propia y no se cuelga de la de victoria porque hay que **romper la
## escuela**, y hacerlo en cualquiera de las otras ensuciaría la integridad con la
## que se miden el puntaje y la derrota.
func _check_protected_run() -> void:
	var before_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var level := await _enter_level(SEED_A)
	if level == null:
		return
	var manager := level.get_round_manager()
	var city := manager.city_integrity
	var school := manager.get_protected_building()
	_row(16, school != null, "16 · la ronda 1 resuelve su edificio protegido")
	if school == null or city == null:
		await _discard_level(level)
		return

	_row(16, school.name == PROTECTED_NODE,
			"16 · el protegido es '%s' (es '%s')" % [PROTECTED_NODE, school.name])
	_row(16, school.display_key == PROTECTED_KEY,
			"16 · su display_key es '%s' (es '%s')" % [PROTECTED_KEY, school.display_key])
	var name_text := school.display_name()
	_row(16, not name_text.is_empty() and name_text != PROTECTED_KEY,
			"16 · el nombre está traducido: '%s'" % name_text)
	_row(16, is_equal_approx(school.priority, RoundManager.PROTECTED_PRIORITY),
			"16 · su prioridad es %.1f (es %.1f)"
					% [RoundManager.PROTECTED_PRIORITY, school.priority])
	_row(16, school.is_in_group(Building.GROUP_PROTECTED),
			"16 · está en el grupo '%s'" % Building.GROUP_PROTECTED)
	_row(16, city.get_protected() == school, "16 · CityIntegrity lo tiene registrado")
	_row(16, school.windows_lit(), "16 · el protegido nunca apaga sus ventanas")
	_row(16, is_equal_approx(city.get_ratio(), 1.0),
			"16 · el peso ×3 deja la ciudad intacta en 100 %% (está en %.4f)" % city.get_ratio())

	# El título del objetivo pasa a nombrar el edificio.
	var defend := _first_defend(manager)
	_row(16, defend != null, "16 · la cadena trae un ObjectiveDefendCity")
	if defend != null:
		var title := defend.get_title_text()
		_row(16, title.contains(name_text.to_upper()) and title != defend.title_key,
				"16 · el título nombra al protegido: '%s'" % title)
		_row(16, not defend.is_failed, "16 · el objetivo arranca sin fallar")

	# **Peso ×3**: la escuela y un bloque de su mismo HP, medidos uno tras otro.
	var twin := _twin_of(city, school)
	_row(16, twin != null, "16 · hay otro edificio con el mismo HP para comparar")
	if twin == null:
		await _discard_level(level)
		return
	var before_twin := city.get_ratio()
	var _applied := twin.take_damage(twin.get_max_hp(), twin.global_position)
	var twin_cost := before_twin - city.get_ratio()
	var before_school := city.get_ratio()
	_applied = school.take_damage(school.get_max_hp(), school.global_position)
	var school_cost := before_school - city.get_ratio()
	var factor := school_cost / maxf(twin_cost, 0.000001)
	print("  16 · un bloque de %.0f HP cuesta %.5f de integridad; la escuela, %.5f (×%.3f)"
			% [twin.get_max_hp(), twin_cost, school_cost, factor])
	_row(16, absf(factor - RoundManager.PROTECTED_PRIORITY) <= PROTECTED_WEIGHT_TOLERANCE,
			"16 · la escuela pesa ×%.3f frente a un bloque igual (esperado ×%.1f ±%.2f)"
					% [factor, RoundManager.PROTECTED_PRIORITY, PROTECTED_WEIGHT_TOLERANCE])

	await wait_frames(1)
	_row(16, defend != null and defend.is_failed,
			"16 · la caída del protegido marca el objetivo como fallido")
	if defend != null:
		var failed_text := defend.get_failed_text()
		_row(16, failed_text.contains(name_text.to_upper())
						and failed_text != defend.protected_failed_key,
				"16 · la línea de fallo dice '%s'" % failed_text)

	# La tarjeta abre por el bloque EN PIE, con la escuela caída.
	var result := manager.build_result()
	var rows := result.summary_rows()
	_row(16, result.protected_state == RoundResult.Protected.FALLEN,
			"16 · el resultado marca el protegido como caído (marca %d)" % result.protected_state)
	_row(16, result.buildings_total == 60 and result.buildings_standing == 58,
			"16 · quedan %d de %d edificios en pie"
					% [result.buildings_standing, result.buildings_total])
	_row(16, rows.size() >= 4 and String(rows[0]["label_key"]) == "RESULT_STANDING_HEADER"
					and bool(rows[0].get("header", false)),
			"16 · summary_rows() abre con el encabezado 'Qué quedó en pie'")
	_row(16, rows.size() >= 2 and String(rows[1]["label_key"]) == PROTECTED_KEY
					and String(rows[1]["value_text"])
							== TranslationServer.translate("RESULT_PROTECTED_FALLEN"),
			"16 · la segunda fila es «%s · %s»"
					% [name_text, String(rows[1]["value_text"]) if rows.size() >= 2 else ""])
	_row(16, rows.size() >= 3 and String(rows[2]["label_key"]) == "RESULT_STANDING_COUNT"
					and String(rows[2]["value_text"]) == "58/60",
			"16 · la tercera fila cuenta los edificios en pie")
	var order := PackedStringArray()
	for row: Dictionary in rows:
		order.append(String(row["label_key"]))
	_row(16, order.find("RESULT_TIME") > order.find("RESULT_INTEGRITY"),
			"16 · el tiempo va después de la integridad (orden %s)" % ", ".join(order))

	await _discard_level(level)
	var after_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_row(16, after_orphans - before_orphans <= ORPHAN_TOLERANCE,
			"16 · la pasada del protegido no deja huérfanos (antes %d, después %d)"
					% [before_orphans, after_orphans])


## Primer [ObjectiveDefendCity] de la cadena, o `null`.
func _first_defend(manager: RoundManager) -> ObjectiveDefendCity:
	if manager.sequencer == null:
		return null
	for objective: Objective in manager.sequencer.objectives:
		var defend := objective as ObjectiveDefendCity
		if defend != null:
			return defend
	return null


## Otro edificio con el mismo HP nominal que [param school], para comparar cuánto
## cuesta cada uno en la integridad.
func _twin_of(city: CityIntegrity, school: Building) -> Building:
	for building: Building in city.get_buildings():
		if building != school and is_equal_approx(building.get_max_hp(), school.get_max_hp()):
			return building
	return null


# --- Fila 13: restauración --------------------------------------------------------------------

## Devuelve `GameSettings` a lo que había y lo verifica **releyendo el `.cfg`**.
func _restore_config() -> void:
	GameSettings.rounds = _rounds_backup.duplicate(true)
	GameSettings.save_game_settings()
	var config := ConfigFile.new()
	var path := Global.config_path(GameSettings.CONFIG_FILE)
	var err := config.load(path)
	_row(13, err == OK, "13 · el .cfg restaurado se puede releer (%s)" % error_string(err))
	if err != OK:
		return
	for key: String in ["best_score_%s" % ROUND_ID, "best_time_%s" % ROUND_ID]:
		# `get_value()` sin valor por defecto sobre una sección ausente imprime un
		# error del motor: se pregunta antes.
		var present := config.has_section_key(GameSettings.ROUNDS_SECTION, key)
		var on_disk := float(config.get_value(GameSettings.ROUNDS_SECTION, key, 0.0))
		if _rounds_backup.has(key):
			_row(13, present and is_equal_approx(on_disk, float(_rounds_backup[key])),
					"13 · '%s' vuelve a su valor original" % key)
		else:
			_row(13, not present, "13 · '%s' no existía y no queda escrita" % key)
	_row(13, GameSettings.get_best_score(ROUND_ID)
					== int(_rounds_backup.get("best_score_%s" % ROUND_ID, 0)),
			"13 · el récord en memoria vuelve a su valor original")
	_row(13, is_equal_approx(Engine.time_scale, 1.0),
			"13 · el check no deja Engine.time_scale tocado (quedó en %.3f)" % Engine.time_scale)


# --- Utilidades -------------------------------------------------------------------------------

## Una comprobación de la fila [param row]: suma al resultado de la fila y delega en
## [method CheckRunner.expect], que imprime el motivo si falla.
func _row(row: int, cond: bool, msg: String) -> void:
	_rows[row] = bool(_rows.get(row, true)) and cond
	expect(cond, msg)


## Una línea `OK`/`FAIL` por cada fila de la tabla de `docs/11` §11.
func _print_rows() -> void:
	for row: int in range(1, ROW_TITLES.size() + 1):
		if not _rows.has(row):
			fail("%d · %s: la fila no llegó a ejecutarse" % [row, ROW_TITLES[row - 1]])
			print("  %2d %-28s FAIL" % [row, ROW_TITLES[row - 1]])
			continue
		print("  %2d %-28s %s" % [row, ROW_TITLES[row - 1], "OK" if _rows[row] else "FAIL"])


## Instancia el nivel de batalla con la semilla [param round_seed] y espera a que la
## ronda esté en pie. Devuelve `null` si algo falló.
func _enter_level(round_seed: int) -> BattleLevel:
	Global.selected_round = ROUND_ID
	Global.round_seed = round_seed
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % LEVEL_SCENE)
		return null
	var level := packed.instantiate() as BattleLevel
	if level == null:
		fail("%s no instancia un BattleLevel" % LEVEL_SCENE)
		return null
	add_child(level)
	await wait_frames(2)
	if level.get_round_manager() == null:
		fail("el nivel no trae RoundManager")
		level.queue_free()
		return null
	return level


## Verdadero cuando la ronda de [param manager] ya llegó a un estado terminal.
func _is_terminal(manager: RoundManager) -> bool:
	return manager.get_state() == Global.RoundState.VICTORY 			or manager.get_state() == Global.RoundState.DEFEAT


## Primer enemigo de la ronda, o `null` si no hay ninguno.
func _first_enemy(manager: RoundManager) -> EnemyBase:
	var enemies := manager.get_enemies()
	return enemies[0] as EnemyBase if not enemies.is_empty() else null


## Saca el nivel del árbol y espera dos cuadros, que es lo que pide la fila 14.
func _discard_level(level: Node) -> void:
	level.queue_free()
	await wait_frames(2)


func _on_round_state_changed(state: int) -> void:
	_states.append(state)


func _on_objective_started(index: int) -> void:
	_objective_starts.append(index)


func _on_alert_finished() -> void:
	_alert_finished_count += 1


## Espera a que [param condition] se cumpla; devuelve `false` si se agota el plazo. El
## plazo se mide con el reloj del sistema, así que la cámara lenta del remate no lo
## altera.
func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false
