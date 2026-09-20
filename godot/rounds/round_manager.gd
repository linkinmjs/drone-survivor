## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Máquina de estados de la ronda y contabilidad de la partida (`docs/11` §4).
##
## Instancia el distrito y los enemigos de la entrada de [RoundCatalog], lleva
## `ALERT` → `INTRO` → `BATTLE` → `VICTORY` / `DEFEAT`, arma el [ObjectiveContext]
## del secuenciador, acumula el [RoundResult] con hechos del bus y termina mostrando
## la [ResultCard].
##
## `ALERT` es la alerta del monitor del taller de `docs/narrativa` §5 (WP-25b): seis
## segundos de pantalla, un corte de estática de [constant STATIC_SECONDS] y recién
## entonces la cinemática. Este nodo pone el **estado y los datos** —edificio
## protegido, punto de entrada del jefe, rejilla del barrio— y no dibuja nada: la
## pantalla es un componente del `CombatHUD`.
##
## **Reglas que no se negocian**
##
## - La victoria y la derrota se deciden **sólo** por el bus (`docs/11` §12, fila 4):
##   todos los ids de la ronda vistos en `Events.enemy_defeated`, o
##   `Events.city_integrity_changed` por debajo de [constant DEFEAT_INTEGRITY]. Este
##   nodo no mira la vida del jefe ni la de los edificios.
## - Si los dos hechos caen en el **mismo frame** gana la derrota (`docs/11` §4.1). Por
##   eso ninguno de los dos se resuelve dentro del manejador de la señal: se anotan como
##   pendientes y [method _process] los resuelve con la derrota primero.
## - `VICTORY` y `DEFEAT` son **terminales**: un `enemy_defeated` tardío no reabre nada.
## - Este nodo emite `Events.round_state_changed` y **ningún otro evento del bus**
##   (`docs/11` §9.2); todo lo demás son hechos de otros sistemas.
## - Nadie busca nodos en la raíz: todas las referencias entran por `@export` desde
##   `battle_level.tscn` (`docs/11` §3).
##
## Todos los plazos son **acumuladores**, nunca [Timer] (`docs/00` §6).
class_name RoundManager extends Node

## Texto de la tarea actual, su progreso de 0 a 1 —negativo si no hay barra— y su
## línea de progreso. Lo consume el `CombatHUD` de WP-22 (`docs/12` §4.1).
signal objective_text_changed(task_text: String, progress: float, progress_text: String)

## Se acabó la alerta del taller: la pantalla se corta y entra la estática
## (`docs/11` §1, `docs/narrativa` §5).
##
## Es **local** y no del bus: `Events.round_state_changed` ya publica el estado, y
## esto es el detalle de presentación de un estado —el instante exacto en que la
## pantalla deja de dibujarse— que sólo le interesa a quien la dibuja. Se emite una
## sola vez por ronda, tanto si la alerta se agotó como si el jugador la salteó.
signal alert_finished

## Duración de la alerta del taller, en segundos (`docs/11` §1).
const ALERT_SECONDS: float = 6.0

## Hueco de estática entre la alerta y la cinemática, en segundos.
##
## No lo dibuja este nodo: es el tiempo que la ronda le deja al `StaticBurst` del
## HUD entre [signal alert_finished] y [method _enter_intro]. Si nadie lo dibuja,
## el único efecto es que la `INTRO` empieza 0,4 s más tarde.
const STATIC_SECONDS: float = 0.4

## Segundos de la alerta durante los que **no** se acepta el «cualquier botón».
##
## Sin esta guarda la alerta se saltea sola en el primer cuadro: la ventana recién
## creada entrega el evento de la tecla o del clic con el que se llegó hasta acá
## —medido con una sonda, `ALERT` duraba 0,000 s con ventana y 6,000 s en
## `--headless`—, y el jugador veía un parpadeo en vez de un aviso. Trescientos
## cincuenta milisegundos es menos de lo que tarda nadie en decidir saltear algo que
## todavía no leyó.
const ALERT_INPUT_GRACE: float = 0.35

## Paso máximo que se le admite a los relojes de la apertura, en segundos.
##
## **No es cosmético.** El cuadro siguiente a instanciar el distrito y al coloso
## llega con un `delta` de varios segundos —el motor entrega el tiempo de pared que
## costó construir la escena—, y sin recorte ese único cuadro se comía la alerta
## entera: medido con Movie Maker, `ALERT` duraba 0,1 s en vez de 6 y la ronda
## abría directamente en la cinemática. La misma guarda protege a la `INTRO` de un
## tirón largo en medio del travelling.
const MAX_STEP: float = 0.25

## Duración de la cinemática de apertura, en segundos (`docs/11` §10).
const INTRO_SECONDS: float = 12.0

## Travelling de apertura, medido **desde el jefe** (WP-19b). `FORWARD` va hacia
## la ciudad, `SIDE` es lateral y `HEIGHT` es la altura sobre el suelo; `LOOK_*`
## es la altura del punto al que mira la cámara.
##
## El final queda a `sqrt(86² + 50²) ≈ 100 m` en horizontal y 26 m de alto —unos
## 103 m del jefe, por debajo del tope de 150— y el punto de mira está 4 m por
## encima de la cámara, así que el encuadre cierra apuntando ligeramente hacia
## arriba con el coloso recortado contra el cielo y la ciudad por detrás.
const INTRO_START_FORWARD: float = 210.0
const INTRO_START_SIDE: float = 130.0
const INTRO_START_HEIGHT: float = 52.0
const INTRO_END_FORWARD: float = 86.0
const INTRO_END_SIDE: float = 50.0
const INTRO_END_HEIGHT: float = 26.0
const INTRO_LOOK_START_HEIGHT: float = 24.0
const INTRO_LOOK_END_HEIGHT: float = 30.0

## Integridad de la ciudad por debajo de la cual la ronda se pierde.
const DEFEAT_INTEGRITY: float = 0.35

## Pausa dramática al terminar, en segundos **reales** (`docs/11` §10).
const OUTRO_SECONDS: float = 1.2

## Escala de tiempo durante la pausa dramática.
const OUTRO_TIME_SCALE: float = 0.35

## Id de ronda al que se cae si [member Global.selected_round] viene vacío o no existe.
const FALLBACK_ROUND_ID: String = "first-contact"

## Nombre de los marcadores de aparición del distrito (`docs/10`, `docs/11` §4.2).
const SPAWN_MARKER_PREFIX: String = "EnemySpawn"

## Prioridad que recibe el edificio protegido (`docs/11` §1). Lo pone por encima
## del jefe en los marcadores fuera de cuadro (`docs/12` §4.1).
const PROTECTED_PRIORITY: float = 3.0

## Argumento de usuario que fuerza la victoria a los pocos segundos de empezar la
## batalla. Existe sólo para la captura de Movie Maker de WP-21; no hay forma de
## llegar a él desde el juego.
const FORCE_VICTORY_ARG: String = "force-victory"

## Segundos de batalla tras los que [constant FORCE_VICTORY_ARG] fuerza la victoria.
const FORCE_VICTORY_SECONDS: float = 3.0

## Contenedor del distrito. Lo puebla [method _spawn_district].
@export var district_root: Node3D

## Contenedor de los enemigos. Lo puebla [method _spawn_enemies].
@export var enemies_root: Node3D

## Conjunto jugable del dron.
@export var drone_rig: DroneRig

## Integridad de la ciudad del nivel (`docs/10` §5).
@export var city_integrity: CityIntegrity

## Cadena de objetivos de la ronda.
@export var sequencer: ObjectiveSequencer

## Cámara de la cinemática de apertura.
@export var intro_camera: Camera3D

## Cámara fija desde la que se mira la ciudad mientras el dron se reconstruye.
@export var respawn_camera: Camera3D

## Puestos de pila del nivel (`docs/09` §2.5).
@export var battery_spawner: BatterySpawner

## Escena de la tarjeta de resultado.
@export var result_card_scene: PackedScene

## Capa (45) donde se cuelga la tarjeta de resultado.
@export var result_layer: CanvasLayer

## Capa (20) reservada al `CombatHUD` de WP-22. Si sigue vacía se enciende
## [member objective_hud] para que la ronda se pueda leer igual.
@export var combat_hud_slot: CanvasLayer

## Tarjeta de objetivo provisional, hasta que WP-22 entregue el `CombatHUD`.
@export var objective_hud: ObjectiveHUD

var _level: LevelBase = null
var _round_data: Dictionary = {}
var _round_id: String = ""
var _state: int = Global.RoundState.ALERT
var _ctx: ObjectiveContext = null
var _enemies: Array[EnemyBase] = []
var _result_card: ResultCard = null
var _result: RoundResult = null

## Distrito instanciado por [method _spawn_district], o `null` si la ronda abortó.
var _district: CityGrid = null

## Edificio que la ronda pide proteger, o `null` si no declara ninguno.
var _protected: Building = null

## Marcador por el que entra el jefe. Lo usa la pantalla de la alerta para dibujar
## el chevrón del enemigo.
var _enemy_entry: Vector3 = Vector3.ZERO

var _alert_elapsed: float = 0.0
var _static_left: float = 0.0
var _alert_finished_emitted: bool = false

var _intro_elapsed: float = 0.0
var _battle_elapsed: float = 0.0
var _outro_left: float = 0.0
var _started: bool = false
var _aborted: bool = false
var _force_victory: bool = false

var _victory_pending: bool = false
var _defeat_pending: bool = false
var _defeat_reason: String = ""

var _defeated_ids: Dictionary[StringName, bool] = {}
var _broken_parts: Dictionary[StringName, bool] = {}
var _shots_fired: int = 0
var _shots_hit: int = 0
var _deaths: int = 0
var _respawn_multiplier: float = 1.0

## Última línea de tarea publicada, para no repetir el `emit` cuadro a cuadro.
var _last_task: String = ""
var _last_progress: float = -2.0
var _last_progress_text: String = ""

## Poses del travelling de apertura: `[desde, hasta]` y el punto al que mira en
## cada extremo.
var _intro_from: Vector3 = Vector3.ZERO
var _intro_to: Vector3 = Vector3.ZERO
var _intro_look_from: Vector3 = Vector3.ZERO
var _intro_look_to: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_force_victory = OS.get_cmdline_user_args().has("--%s" % FORCE_VICTORY_ARG)


## Devuelve [member Engine.time_scale] a 1.0 si la ronda muere en plena pausa
## dramática. Sin esto, salir al menú durante el remate dejaría el juego entero al
## 35 % de velocidad.
func _exit_tree() -> void:
	if _outro_left > 0.0:
		_outro_left = 0.0
		Engine.time_scale = 1.0
	_disconnect_bus()


## Arranca la ronda. Lo llama [BattleLevel] desde su `_ready()`, cuando el nivel ya
## está entero en el árbol: así el orden de construcción no depende de en qué rama
## del árbol esté este nodo.
func begin(level: LevelBase) -> void:
	if _started:
		return
	_started = true
	_level = level
	_round_id = _resolve_round_id()
	_round_data = RoundCatalog.get_by_id(_round_id)
	if _round_data.is_empty():
		_abort("ERR_ROUND_MISSING")
		return
	_spawn_district()
	if _aborted:
		return
	_resolve_protected()
	_spawn_enemies()
	if _aborted:
		return
	_build_context()
	_connect_bus()
	_reset_batteries()
	_enter_alert()


# --- Interfaz pública (`docs/11` §9.2) --------------------------------------------------------

## Estado actual, un valor de [enum Global.RoundState].
func get_state() -> int:
	return _state


## Segundos acumulados en `BATTLE`, sin pausa y sin cinemática.
func get_elapsed_seconds() -> float:
	return _battle_elapsed


## Par de tiempo de la ronda, en segundos.
func get_time_par() -> float:
	return float(_round_data.get("time_par", 0.0))


## Id de catálogo de la ronda en curso.
func get_round_id() -> String:
	return _round_id


## Enemigos instanciados, en orden de aparición.
func get_enemies() -> Array:
	return _enemies.duplicate()


## Contexto que reciben los objetivos, o `null` si la ronda no llegó a arrancar.
func get_context() -> ObjectiveContext:
	return _ctx


## Ids de parte rotos desde que empezó la ronda, sin repetidos.
##
## Es la cuenta de la **ronda**, no la de un objetivo: [ObjectiveBreakParts] se sirve
## de ella al arrancar para no perder las rodillas que cayeron mientras corría el
## objetivo anterior.
func get_broken_part_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for part_id: StringName in _broken_parts:
		ids.append(part_id)
	return ids


## Tarjeta de resultado si ya está en pantalla, o `null`.
func get_result_card() -> ResultCard:
	return _result_card


## Resultado de la partida si la ronda ya terminó, o `null`.
func get_result() -> RoundResult:
	return _result


## Segundos que le quedan a la cinemática de apertura.
func get_intro_remaining() -> float:
	return maxf(INTRO_SECONDS - _intro_elapsed, 0.0)


# --- Datos de la alerta del taller (`docs/11` §1) ---------------------------------------------
#
# Los cinco métodos que siguen son **lo único** que la pantalla de la alerta
# (`hud/combat/alert_screen.gd`) necesita de la ronda. Se devuelven datos ya
# resueltos —el edificio, el punto de entrada, la rejilla— y no el catálogo crudo,
# para que la pantalla no tenga que volver a buscar nada por nombre ni conocer el
# formato de `RoundCatalog`.

## Segundos que le quedan a la alerta del taller. Cero mientras corre el hueco de
## estática y en cualquier estado posterior.
func get_alert_remaining() -> float:
	if _state != Global.RoundState.ALERT:
		return 0.0
	return maxf(ALERT_SECONDS - _alert_elapsed, 0.0)


## Edificio que esta ronda pide proteger, o `null` si no declara ninguno.
func get_protected_building() -> Building:
	return _protected if is_instance_valid(_protected) else null


## Tipo del edificio protegido (`&"school"`, `&"hospital"`…), o `&""` si la ronda
## no declara ninguno. El nombre visible no sale de acá: lo trae el propio
## [Building] en `display_key` (`docs/narrativa` §9, nombre propio antes que tipo).
func get_protected_kind() -> StringName:
	var entry := RoundCatalog.protected_of(_round_data)
	return StringName(entry.get("kind", &""))


## Punto por el que entra el jefe: la posición global del `EnemySpawn` que usó
## [method _spawn_enemies]. Sin marcadores es el origen del contenedor de enemigos.
func get_enemy_entry_position() -> Vector3:
	return _enemy_entry


## Rejilla del distrito en juego, o `null` si la ronda no llegó a instanciarlo. De
## acá salen los carriles con los que la pantalla dibuja el mapa del barrio.
func get_district() -> CityGrid:
	return _district if is_instance_valid(_district) else null


## Salta el estado previo que esté activo: de `ALERT` pasa a `INTRO` y de `INTRO` a
## `BATTLE` (`docs/11` §1). En cualquier otro estado no hace nada: las dos
## transiciones son irreversibles (`docs/11` §4.1).
##
## Saltear la alerta se lleva por delante el hueco de estática: el jugador que
## apretó un botón quiere ver el vuelo, no 0,4 s más de ruido. [signal alert_finished]
## se emite igual —y una sola vez—, así que la pantalla puede disparar su estática
## sobre el arranque de la cinemática si quiere.
func skip_intro() -> void:
	match _state:
		Global.RoundState.ALERT:
			_finish_alert()
			_enter_intro()
		Global.RoundState.INTRO:
			_enter_battle()


## Saltea todo lo previo de un tirón y deja la ronda en `BATTLE`.
##
## Existe para los bancos de pruebas y las capturas, que no quieren ver ni la
## alerta ni la cinemática: `balance_check`, `render_check`, `perf_report` y
## `environment_shots`. El juego no la llama nunca; el jugador saltea de a un
## estado por vez con [method skip_intro].
func skip_to_battle() -> void:
	for _attempt: int in 2:
		if _state == Global.RoundState.BATTLE:
			return
		skip_intro()


## Pide la derrota por un motivo que no es la integridad de la ciudad. Hoy nadie la
## usa desde el juego; existe para el menú de abandono y para los checks.
func request_defeat(reason_key: String) -> void:
	if _is_terminal():
		return
	_defeat_reason = reason_key
	_defeat_pending = true


## Arma el [RoundResult] con lo acumulado hasta ahora. No persiste nada.
func build_result() -> RoundResult:
	var result := RoundResult.new()
	result.round_id = _round_id
	result.victory = _state == Global.RoundState.VICTORY
	result.time_seconds = _battle_elapsed
	result.city_integrity = city_integrity.get_ratio() if city_integrity != null else 1.0
	result.parts_broken = _broken_parts.size()
	result.shots_fired = _shots_fired
	result.shots_hit = _shots_hit
	result.deaths = _deaths
	result.respawn_multiplier = _respawn_multiplier
	# Qué quedó en pie (`docs/narrativa` §8): es lo primero que lee la tarjeta y
	# por eso se llena aunque la ronda no tenga protegido.
	if city_integrity != null and is_instance_valid(city_integrity):
		result.buildings_total = city_integrity.get_buildings().size()
		result.buildings_standing = city_integrity.get_standing_count()
	var protected_building := get_protected_building()
	if protected_building != null:
		result.protected_name_key = protected_building.display_key
		result.protected_state = RoundResult.state_of_building(protected_building)
	var _score := result.compute_score(get_time_par())
	var _medal := result.resolve_medal(RoundCatalog.get_index(_round_id))
	return result


## Semilla derivada y estable por subsistema (`docs/11` §4.4).
##
## Con la misma [member Global.round_seed] dos ejecuciones dan el mismo número para
## la misma etiqueta, y el orden de las llamadas no lo altera. Etiquetas del MVP:
## `"personality"`, `"batteries"`, `"debris"`, `"camera"` e `"intro"`.
static func derive_seed(tag: String) -> int:
	return RoundCatalog.derive_seed(tag)


# --- Bucle -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	# La derrota primero: si los dos hechos caen en el mismo frame gana ella
	# (`docs/11` §4.1 y §12, fila 11).
	if _defeat_pending:
		_defeat_pending = false
		_victory_pending = false
		_enter_terminal(Global.RoundState.DEFEAT)
	elif _victory_pending:
		_victory_pending = false
		_enter_terminal(Global.RoundState.VICTORY)

	match _state:
		Global.RoundState.ALERT:
			_tick_alert(delta)
		Global.RoundState.INTRO:
			_tick_intro(delta)
		Global.RoundState.BATTLE:
			_tick_battle(delta)
		_:
			_tick_outro(delta)
	_publish_objective_text()


## «Cualquier botón para continuar» durante la alerta (`docs/narrativa` §5) y el
## `ui_accept` de siempre durante la cinemática (`docs/11` §10).
##
## La alerta acepta **cualquier** tecla, botón de mando o clic —es un aviso, no un
## menú— y la cinemática sólo las dos acciones de confirmar, para que un roce del
## stick no se lleve por delante el vuelo de salida.
func _unhandled_input(event: InputEvent) -> void:
	if UI.has_modal() or SceneTransition.is_busy():
		return
	if _state == Global.RoundState.ALERT:
		if _alert_elapsed < ALERT_INPUT_GRACE or not _is_any_button(event):
			return
		get_viewport().set_input_as_handled()
		skip_intro()
		return
	if _state != Global.RoundState.INTRO:
		return
	if event.is_action_pressed(&"ui_accept", false, true) \
			or event.is_action_pressed(&"objective_next", false, true):
		get_viewport().set_input_as_handled()
		skip_intro()


## Verdadero si [param event] es «cualquier botón»: tecla, botón de mando o clic,
## siempre en el flanco de bajada y sin repetición automática.
func _is_any_button(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null:
		return key.pressed and not key.echo
	var pad := event as InputEventJoypadButton
	if pad != null:
		return pad.pressed
	var click := event as InputEventMouseButton
	return click != null and click.pressed


## Alerta del taller y, después, el hueco de estática.
##
## El reloj no corre mientras `SceneTransition` mantiene el fundido, por el mismo
## motivo que la cinemática: la alerta se mide desde que se ve.
##
## Los dos plazos están en el **mismo** estado a propósito. La estática es el corte
## entre dos imágenes —el monitor del taller y la señal del dron—, no una pantalla
## por derecho propio: darle un `RoundState` obligaría a todo el que hace `match`
## sobre el estado a tratar 0,4 s de ruido como un estado de ronda.
func _tick_alert(delta: float) -> void:
	if SceneTransition.is_busy():
		return
	var step := minf(delta, MAX_STEP)
	if not _alert_finished_emitted:
		_alert_elapsed += step
		if _alert_elapsed < ALERT_SECONDS:
			return
		_finish_alert()
		return
	_static_left -= step
	if _static_left <= 0.0:
		_enter_intro()


## Cierra la parte visible de la alerta y abre el hueco de estática. Idempotente:
## [signal alert_finished] sale una sola vez por ronda.
func _finish_alert() -> void:
	if _alert_finished_emitted:
		return
	_alert_finished_emitted = true
	_alert_elapsed = ALERT_SECONDS
	_static_left = STATIC_SECONDS
	alert_finished.emit()


## Travelling de apertura. El reloj no corre mientras `SceneTransition` mantiene el
## fundido: la cinemática empieza cuando se ve, no cuando se carga.
func _tick_intro(delta: float) -> void:
	if SceneTransition.is_busy():
		return
	# Recortado por [constant MAX_STEP], igual que la alerta: un tirón de varios
	# segundos en medio del travelling daría un salto de cámara en vez de un
	# travelling.
	_intro_elapsed += minf(delta, MAX_STEP)
	_update_intro_camera()
	if _intro_elapsed >= INTRO_SECONDS:
		_enter_battle()


func _tick_battle(delta: float) -> void:
	_battle_elapsed += delta
	if _force_victory and _battle_elapsed >= FORCE_VICTORY_SECONDS:
		_force_victory = false
		_victory_pending = true


## Pausa dramática. Se mide en segundos **reales**: `delta` ya viene multiplicado por
## [member Engine.time_scale], así que se lo divide para volver a tiempo de reloj.
func _tick_outro(delta: float) -> void:
	if _outro_left <= 0.0:
		return
	_outro_left -= delta / maxf(Engine.time_scale, 0.001)
	if _outro_left > 0.0:
		return
	_outro_left = 0.0
	Engine.time_scale = 1.0
	_finish_round()


# --- Estados ---------------------------------------------------------------------------------

## Alerta del taller: el estado con el que abre toda ronda (`docs/11` §1).
##
## El dron queda congelado igual que en `INTRO` —quien mira la pantalla es el
## piloto de turno, todavía en el taller— y la cámara se deja ya en la pose de
## apertura, para que el corte de la estática entregue la cinemática empezada y no
## un cuadro negro.
func _enter_alert() -> void:
	_set_state(Global.RoundState.ALERT)
	_freeze_drone(true)
	_prepare_intro_camera()
	if _level != null:
		var _focused := _level.focus_camera(intro_camera)
	_update_intro_camera()


func _enter_intro() -> void:
	if _state != Global.RoundState.ALERT:
		return
	_set_state(Global.RoundState.INTRO)
	_freeze_drone(true)
	_prepare_intro_camera()
	if _level != null:
		var _focused := _level.focus_camera(intro_camera)
	_update_intro_camera()
	if objective_hud != null and _show_objective_hud():
		objective_hud.visible = true
		objective_hud.flash(tr("INTRO_INCOMING"), tr("INTRO_SKIP_HINT"), INTRO_SECONDS)


func _enter_battle() -> void:
	if _state != Global.RoundState.INTRO:
		return
	_set_state(Global.RoundState.BATTLE)
	_freeze_drone(false)
	if _level != null and drone_rig != null:
		var _focused := _level.focus_camera(drone_rig.get_fpv_camera())
	if objective_hud != null and _show_objective_hud():
		objective_hud.visible = true
	if sequencer != null:
		sequencer.start_at(0)


## Entra en un estado terminal: corta los objetivos, arranca la cámara lenta y deja
## el dron desarmado. El mundo sigue corriendo; la pausa es **lógica** (`docs/11` §6.3).
func _enter_terminal(state: int) -> void:
	if _is_terminal():
		return
	_set_state(state)
	if sequencer != null:
		sequencer.stop_current()
	_freeze_drone(true)
	if state == Global.RoundState.DEFEAT and respawn_camera != null and _level != null:
		var _focused := _level.focus_camera(respawn_camera)
	if objective_hud != null and objective_hud.visible:
		objective_hud.hide_objective()
		objective_hud.flash(tr("ROUND_VICTORY" if state == Global.RoundState.VICTORY
				else "ROUND_DEFEAT"), "", OUTRO_SECONDS)
	_outro_left = OUTRO_SECONDS
	Engine.time_scale = OUTRO_TIME_SCALE


## Cierra la ronda: puntaje, persistencia y tarjeta.
func _finish_round() -> void:
	_result = build_result()
	if _result.victory:
		# Sólo en victoria se persiste, y sólo si mejora (`docs/11` §7).
		_result.is_record = GameSettings.record_score(_round_id, _result.score)
		_result.is_time_record = GameSettings.record_time(_round_id, _result.time_seconds)
	_show_result_card()


func _set_state(state: int) -> void:
	_state = state
	Events.round_state_changed.emit(state)


func _is_terminal() -> bool:
	return _state == Global.RoundState.VICTORY or _state == Global.RoundState.DEFEAT


# --- Instanciado (`docs/11` §4.2) -------------------------------------------------------------

## Id de la ronda elegida. [member Global.selected_round] es el id de catálogo, no un
## índice: si viene vacío o no existe se cae a [constant FALLBACK_ROUND_ID], que es
## lo que hace jugable el nivel abierto a mano o desde un check.
func _resolve_round_id() -> String:
	var wanted := Global.selected_round
	if not wanted.is_empty() and not RoundCatalog.get_by_id(wanted).is_empty():
		return wanted
	return FALLBACK_ROUND_ID


func _spawn_district() -> void:
	if district_root == null:
		_abort("ERR_ROUND_MISSING")
		return
	var path := String(_round_data.get("district", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		_abort("ERR_ROUND_MISSING")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_abort("ERR_ROUND_MISSING")
		return
	var district := packed.instantiate() as Node3D
	district_root.add_child(district)
	_district = district as CityGrid
	# El distrito ya trae su `CityGrid` horneado: acá sólo se le pasa a
	# `CityIntegrity` para que dé de alta sus `Building` y reinicie la cuenta.
	if city_integrity != null:
		city_integrity.grid = _district
		city_integrity.rebuild()


## Resuelve el edificio protegido de la ronda (`docs/11` §1).
##
## Va **después** de [method _spawn_district] y por lo tanto después de
## `CityIntegrity.rebuild()`: el peso ×3 y el nombre propio se aplican sobre una
## ciudad ya dada de alta y todavía intacta, así que la integridad no se mueve.
##
## Un nombre de nodo que no exista —porque alguien regeneró el distrito con otra
## semilla— no aborta la ronda: se avisa con `push_warning` y se juega sin
## protegido, que es exactamente lo que hace hoy cualquier ronda futura que no lo
## declare. Perder la escuela es una historia; perder la ronda por un nombre mal
## escrito, un bug.
func _resolve_protected() -> void:
	_protected = null
	var entry := RoundCatalog.protected_of(_round_data)
	if entry.is_empty() or _district == null:
		return
	var wanted := String(entry.get("building", ""))
	if wanted.is_empty():
		return
	for building: Building in _district.get_buildings():
		if building.name != wanted:
			continue
		_protected = building
		building.mark_protected(String(entry.get("name_key", "")), PROTECTED_PRIORITY)
		if city_integrity != null:
			city_integrity.set_protected(building)
			var _discard := city_integrity.protected_fallen.connect(_on_protected_fallen)
		return
	push_warning("RoundManager: la ronda '%s' pide proteger '%s' y el distrito no lo trae."
			% [_round_id, wanted])


func _spawn_enemies() -> void:
	if enemies_root == null:
		_abort("ERR_ENEMY_UNKNOWN")
		return
	var ids := _round_data.get("enemies", []) as Array
	var markers := _spawn_markers()
	for index: int in ids.size():
		var id := StringName(str(ids[index]))
		if not EnemyCatalog.has_id(id):
			_abort("ERR_ENEMY_UNKNOWN")
			return
		var packed := EnemyCatalog.scene_of(id)
		if packed == null:
			_abort("ERR_ENEMY_UNKNOWN")
			return
		var enemy := packed.instantiate() as EnemyBase
		if enemy == null:
			_abort("ERR_ENEMY_UNKNOWN")
			return
		if index < markers.size() and markers[index] != null:
			enemy.transform = enemies_root.global_transform.affine_inverse() \
					* markers[index].global_transform
			if index == 0:
				# Por dónde entra el jefe: es el chevrón cian del mapa de la alerta
				# (`docs/narrativa` §5). Se anota acá, que es el único punto donde se
				# sabe **qué** marcador se usó de verdad.
				_enemy_entry = markers[index].global_position
		elif index == 0 and enemies_root != null:
			_enemy_entry = enemies_root.global_position
		# Semilla de personalidad del jefe (`docs/11` §4.4). WP-18 la lee al armar
		# su selector de utilidad; hoy queda anotada para que sea reproducible.
		enemy.set_meta(&"personality_seed", derive_seed("personality"))
		enemies_root.add_child(enemy)
		_aim_perception(enemy)
		_enemies.append(enemy)


## Le presenta el dron a la percepción del enemigo recién instanciado.
##
## **Sin esto el jefe no ve al jugador** (medido en WP-23): `Perception.target` es
## un `@export` que nadie puede fijar desde `arachnodroid.tscn` —el dron vive en el
## nivel, no en la escena del enemigo— y `docs/06` §14 no le da otro dueño. Con el
## objetivo en `null`, `EnemyFSM._build_context()` deja `has_drone_target` en
## `false` y **las seis acciones que apuntan al dron** —`stomp`, `leg_sweep`,
## `head_laser`, `emp_pulse`, `pounce` y `shake_off`— puntúan 0 para siempre: el
## coloso se limita a asediar la ciudad y el jugador es invulnerable.
##
## Va acá, y no en [EnemyBase], por la regla de `docs/11` §3: el enemigo no busca
## nodos en la raíz; quien conoce al dron **y** al enemigo es quien los instancia.
## Por *duck typing* porque la percepción es opcional en el marco (`docs/06` §2).
func _aim_perception(enemy: EnemyBase) -> void:
	if drone_rig == null or enemy == null or enemy.perception == null:
		return
	var drone := drone_rig.get_drone()
	if drone == null or not enemy.perception.has_method(&"set_target"):
		return
	enemy.perception.call(&"set_target", drone)


## Los `EnemySpawn0..N` del distrito, en orden. Si el distrito no los trae, la lista
## sale vacía y los enemigos se quedan en el origen del contenedor (`docs/11` §12,
## fila 13).
func _spawn_markers() -> Array[Node3D]:
	var markers: Array[Node3D] = []
	if district_root == null:
		return markers
	var index := 0
	while true:
		var found := district_root.find_child("%s%d" % [SPAWN_MARKER_PREFIX, index], true, false)
		var marker := found as Node3D
		if marker == null:
			break
		markers.append(marker)
		index += 1
	return markers


func _build_context() -> void:
	_ctx = ObjectiveContext.new()
	_ctx.level = _level
	_ctx.drone_rig = drone_rig
	_ctx.drone = drone_rig.get_drone() if drone_rig != null else null
	_ctx.round_manager = self
	_ctx.city_integrity = city_integrity
	_ctx.enemies = _enemies.duplicate()
	if sequencer != null:
		sequencer.setup(_ctx)
		var _discard := sequencer.objective_started.connect(_on_objective_started)
		_discard = sequencer.all_finished.connect(_on_objectives_finished)
	if objective_hud != null:
		objective_hud.setup(_ctx, sequencer)
		objective_hud.visible = false


## Vuelve a sembrar los puestos de pila. El spawner se siembra solo desde
## [member Global.round_seed] (`docs/09` §2.5), que es la misma semilla maestra de la
## que sale [method derive_seed]: con la misma semilla salen los mismos puestos.
func _reset_batteries() -> void:
	if battery_spawner != null:
		battery_spawner.reset()


## Aborta la ronda: anota el error de arranque y vuelve al menú principal.
func _abort(error_key: String) -> void:
	_aborted = true
	Global.startup_errors.append(error_key)
	push_error("RoundManager: %s (ronda '%s')." % [error_key, _round_id])
	SceneTransition.change_scene(LevelBase.MAIN_MENU_SCENE)


# --- Bus (`docs/11` §9.3) ---------------------------------------------------------------------

func _connect_bus() -> void:
	var _discard := Events.enemy_defeated.connect(_on_enemy_defeated)
	_discard = Events.enemy_part_broken.connect(_on_enemy_part_broken)
	_discard = Events.city_integrity_changed.connect(_on_city_integrity_changed)
	_discard = Events.drone_destroyed.connect(_on_drone_destroyed)
	_discard = Events.drone_respawned.connect(_on_drone_respawned)
	_discard = Events.shot_fired.connect(_on_shot_fired)
	_discard = Events.hit_confirmed.connect(_on_hit_confirmed)


func _disconnect_bus() -> void:
	for pair: Array in [
		[Events.enemy_defeated, _on_enemy_defeated],
		[Events.enemy_part_broken, _on_enemy_part_broken],
		[Events.city_integrity_changed, _on_city_integrity_changed],
		[Events.drone_destroyed, _on_drone_destroyed],
		[Events.drone_respawned, _on_drone_respawned],
		[Events.shot_fired, _on_shot_fired],
		[Events.hit_confirmed, _on_hit_confirmed],
	]:
		var signal_ref: Signal = pair[0]
		var callable: Callable = pair[1]
		if signal_ref.is_connected(callable):
			signal_ref.disconnect(callable)


func _on_enemy_defeated(_enemy: Node3D, enemy_id: StringName) -> void:
	if _is_terminal():
		return
	_defeated_ids[enemy_id] = true
	for id: Variant in _round_data.get("enemies", []) as Array:
		if not _defeated_ids.has(StringName(str(id))):
			return
	_victory_pending = true


func _on_enemy_part_broken(_enemy: Node3D, part_id: StringName, _position: Vector3) -> void:
	_broken_parts[part_id] = true


## La derrota vale desde el primer frame, también durante la cinemática: una ronda
## que arrancara con la ciudad ya rota tiene que poder perderse. Hoy no pasa —el
## distrito entra intacto y `CityIntegrity.reset()` publica 1.0—, pero el umbral es
## del hecho, no del estado.
func _on_city_integrity_changed(ratio: float) -> void:
	if _is_terminal():
		return
	if ratio < DEFEAT_INTEGRITY:
		_defeat_reason = "ROUND_DEFEAT"
		_defeat_pending = true


## Cayó el edificio protegido: el objetivo de defensa queda **fallido** y la cadena
## sigue (`docs/11` §1).
##
## No hay derrota directa: la derrota se sigue decidiendo por integridad y sólo por
## integridad (`docs/11` §4.1, §12 fila 4). Lo que cambia es la lectura —la línea
## de objetivo se pone en rojo y el resultado abre con «Caída»—, que es lo que pide
## `docs/narrativa` §6: la ciudad es un personaje y se la ve sufrir.
##
## El reenvío lo hace este nodo y no [CityIntegrity] porque el objetivo es de la
## ronda: la integridad no conoce la cadena de objetivos, igual que no conoce la
## máquina de estados.
func _on_protected_fallen(_building: Building) -> void:
	if sequencer == null:
		return
	for objective: Objective in sequencer.objectives:
		var defend := objective as ObjectiveDefendCity
		if defend != null:
			defend.fail()


func _on_drone_destroyed(_position: Vector3) -> void:
	_deaths += 1
	# El `RespawnController` ya mueve la cámara (`docs/09` §2.8); acá sólo se
	# sincroniza el ciclo del nivel para que el `FlightHUD` se esconda.
	if _level != null and respawn_camera != null:
		var _focused := _level.focus_camera(respawn_camera)


## El multiplicador **no se recalcula**: lo publica `docs/09` y acá sólo se guarda.
func _on_drone_respawned(score_multiplier: float) -> void:
	_respawn_multiplier = score_multiplier
	if _level != null and drone_rig != null:
		var _focused := _level.focus_camera(drone_rig.get_fpv_camera())
	if sequencer != null:
		sequencer.on_drone_respawned()


func _on_shot_fired(_origin: Vector3, _direction: Vector3) -> void:
	_shots_fired += 1


func _on_hit_confirmed(_position: Vector3, _weak: bool, _lethal: bool) -> void:
	_shots_hit += 1


## La cadena de objetivos terminada **no** fuerza la victoria (`docs/11` §9.3): sólo
## limpia la línea de tarea.
func _on_objectives_finished() -> void:
	objective_text_changed.emit("", -1.0, "")
	if objective_hud != null:
		objective_hud.hide_objective()


func _on_objective_started(index: int) -> void:
	if objective_hud == null or sequencer == null:
		return
	var objective := sequencer.get_current()
	if objective != null:
		objective_hud.show_objective(index, sequencer.count(), objective)


## Publica la tarea actual para el `CombatHUD` de WP-22 (`docs/12` §4.1).
##
## Sólo emite cuando algo cambió de verdad. Un `emit` por cuadro con dos traducciones
## y un `String` recién formateado sería basura para el recolector a 60 Hz, y el HUD
## redibujaría lo mismo.
func _publish_objective_text() -> void:
	if sequencer == null:
		return
	var objective := sequencer.get_current()
	if objective == null or not sequencer.is_running():
		return
	var task := tr(objective.get_task_text())
	var progress := objective.get_progress()
	var progress_text := objective.get_progress_text()
	if task == _last_task and progress_text == _last_progress_text \
			and is_equal_approx(progress, _last_progress):
		return
	_last_task = task
	_last_progress = progress
	_last_progress_text = progress_text
	objective_text_changed.emit(task, progress, progress_text)


# --- Dron, cámara y tarjeta -------------------------------------------------------------------

## Congela y desarma el dron, o lo devuelve al vuelo. Se usa en `INTRO` —el piloto
## todavía no tiene el mando— y al terminar la ronda, donde el mundo sigue corriendo
## pero el dron queda quieto (`docs/11` §4.1 y §6.3).
func _freeze_drone(frozen: bool) -> void:
	if drone_rig == null or not is_instance_valid(drone_rig):
		return
	var drone := drone_rig.get_drone()
	if drone != null:
		if frozen:
			drone.force_disarm()
			drone.linear_velocity = Vector3.ZERO
			drone.angular_velocity = Vector3.ZERO
		drone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		drone.freeze = frozen
	var radio := drone_rig.get_radio()
	if radio != null:
		radio.enabled = not frozen
	var weapon := drone_rig.get_weapon_mount()
	if weapon != null and frozen:
		weapon.fire_pressed = false


## Calcula el travelling: entra desde el lado de la ciudad y termina cerca del
## coloso, por debajo de su cabeza y mirando hacia arriba.
##
## [b]Reencuadrado en WP-19b.[/b] Antes todo se medía desde el centro de la
## ciudad y la cámara terminaba a `ciudad + 70 m` en el lado opuesto al jefe, o
## sea a más de 250 m de él y 70 m de alto: el coloso era una mota de 20 px sobre
## una ciudad gris y plana, y desde esa altura entraba en cuadro el borde del
## plano de suelo de 1 200 m. Ahora todas las distancias se miden [b]desde el
## jefe[/b] y son las de [constant INTRO_END_FORWARD] y compañía.
##
## [b]Por qué la cámara termina a 26 m y no más alto[/b]: el casco del
## Arachnodroid está entre 22 y 29 m (`docs/07` §2). En proyección perspectiva,
## todo lo que esté por debajo de la altura de la cámara cae por debajo de la
## línea del horizonte, siempre, a cualquier distancia. Con la cámara a 35 m el
## coloso se recortaría contra el suelo; a 26 m su cabeza queda por encima del
## horizonte y se recorta contra el cielo, que es lo que se busca.
##
## La semilla `"intro"` decide de qué lado entra la cámara, así que dos partidas
## con la misma semilla abren igual (`docs/11` §4.4).
func _prepare_intro_camera() -> void:
	var city := district_root.global_position if district_root != null else Vector3.ZERO
	var enemy := _ctx.first_enemy() if _ctx != null else null
	var boss := enemy.global_position if enemy != null else city + Vector3(0.0, 0.0, -184.0)

	var away := (city - boss)
	away.y = 0.0
	if away.length() < 1.0:
		away = Vector3.BACK * 100.0
	away = away.normalized()
	var side := Vector3(-away.z, 0.0, away.x)
	var lateral := 1.0 if derive_seed("intro") % 2 == 0 else -1.0

	_intro_from = boss + away * INTRO_START_FORWARD 			+ side * (lateral * INTRO_START_SIDE) + Vector3.UP * INTRO_START_HEIGHT
	_intro_to = boss + away * INTRO_END_FORWARD 			+ side * (lateral * INTRO_END_SIDE) + Vector3.UP * INTRO_END_HEIGHT
	_intro_look_from = boss + Vector3.UP * INTRO_LOOK_START_HEIGHT
	_intro_look_to = boss + Vector3.UP * INTRO_LOOK_END_HEIGHT


## Interpola la pose con un `smoothstep` para que el arranque y el final no tengan
## tirón. `look_at` con el dron todavía congelado es seguro: nada se mueve debajo.
func _update_intro_camera() -> void:
	if intro_camera == null or not is_instance_valid(intro_camera):
		return
	var t := smoothstep(0.0, 1.0, clampf(_intro_elapsed / INTRO_SECONDS, 0.0, 1.0))
	intro_camera.global_position = _intro_from.lerp(_intro_to, t)
	var target := _intro_look_from.lerp(_intro_look_to, t)
	if intro_camera.global_position.distance_to(target) > 0.5:
		intro_camera.look_at(target, Vector3.UP)


## Verdadero mientras el `CombatHUDSlot` siga vacío, es decir, mientras WP-22 no haya
## entregado el `CombatHUD` (`docs/12` §4.1).
##
## Desde WP-22 `battle_level.tscn` instancia el `CombatHUD` dentro del slot, así que
## en el juego esto es **siempre `false`** y la tarjeta provisional no se enciende.
## Sigue existiendo para las escenas de prueba que cuelgan un nivel con el slot vacío.
func _show_objective_hud() -> bool:
	return combat_hud_slot == null or combat_hud_slot.get_child_count() == 0


## El `CombatHUD` colgado de [member combat_hud_slot], o `null`.
##
## Se devuelve como [CanvasLayer] y no como `CombatHUD` a propósito: el `CombatHUD`
## ya depende de esta clase —le pide el cronómetro y la línea de objetivo— y nombrar
## su tipo acá cerraría un ciclo entre dos `class_name`. El nivel, que no está en ese
## ciclo, sí lo expone tipado ([method BattleLevel.get_combat_hud]).
func get_combat_hud() -> CanvasLayer:
	if combat_hud_slot == null or not is_instance_valid(combat_hud_slot):
		return null
	for child: Node in combat_hud_slot.get_children():
		var layer := child as CanvasLayer
		if layer != null:
			return layer
	return null


func _show_result_card() -> void:
	if result_card_scene == null or _result == null:
		return
	var card := result_card_scene.instantiate() as ResultCard
	if card == null:
		push_error("RoundManager: result_card_scene no instancia un ResultCard.")
		return
	_result_card = card
	card.setup(_result, _result_entries())
	var _discard := card.chosen.connect(_on_result_chosen)
	# Los menús navegan con los sticks; volar, no (`docs/04` §4.9).
	StickNavigation.suspended = false
	if objective_hud != null:
		objective_hud.hide_objective()
	# El `FlightHUD` es la vista del piloto (`docs/12` §1.1) y la ronda ya terminó:
	# dibujar una mira y un horizonte detrás de la tarjeta sería ruido.
	if drone_rig != null and is_instance_valid(drone_rig):
		var hud := drone_rig.get_flight_hud()
		if hud != null:
			hud.visible = false
	# Lo mismo con el `CombatHUD`: durante la pausa dramática se queda en modo
	# cinemático —sólo la ciudad y el rótulo— y se apaga **cuando aparece la
	# tarjeta**, no antes, para que el remate se vea con la ciudad todavía en cuadro
	# (`docs/12` §4.2, `docs/11` §6.3).
	var combat_hud := get_combat_hud()
	if combat_hud != null:
		combat_hud.visible = false
	var host: Node = result_layer if result_layer != null else _level
	if host == null:
		host = self
	host.add_child(card)


## Entradas de la tarjeta (`docs/11` §6.3). `next` no se dibuja bloqueado: si no hay
## ronda siguiente desbloqueada simplemente no aparece, porque [ChoiceMenu] no tiene
## estado `locked` (`docs/01` §2.3).
func _result_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{"id": "retry", "text": "RESULT_RETRY", "primary": not _result.victory},
	]
	if _next_round_index() >= 0:
		entries.append({"id": "next", "text": "RESULT_NEXT", "primary": _result.victory})
	entries.append({"id": "rounds", "text": "RESULT_ROUNDS", "primary": false})
	entries.append({"id": "menu", "text": "RESULT_MENU", "primary": false})
	return entries


## Índice de la ronda siguiente si existe y está desbloqueada; `-1` si no.
func _next_round_index() -> int:
	var next := RoundCatalog.get_index(_round_id) + 1
	if next <= 0 or next >= RoundCatalog.count() or not RoundCatalog.is_unlocked(next):
		return -1
	return next


func _on_result_chosen(id: String) -> void:
	match id:
		"retry":
			Global.selected_round = _round_id
			Global.round_seed = randi()
			SceneTransition.change_scene(RoundCatalog.level_scene_for(_round_data), true)
		"next":
			var next := _next_round_index()
			if next < 0:
				SceneTransition.change_scene(LevelBase.MAIN_MENU_SCENE, false)
				return
			var data := RoundCatalog.get_round(next)
			Global.selected_round = String(data["id"])
			Global.round_seed = randi()
			SceneTransition.change_scene(RoundCatalog.level_scene_for(data), true)
		"rounds":
			SceneTransition.change_scene(RoundCatalog.ROUNDS_MENU_SCENE, false)
		_:
			SceneTransition.change_scene(LevelBase.MAIN_MENU_SCENE, false)
