## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Reparto de voces de audio y traductor de hechos a sonidos (`docs/13` §5.2 y §8).
##
## Es el hermano del [VFXPool]: cuelga de `Pools/AudioPool` en el nivel, escucha el
## bus de `Events` y reproduce lo que corresponde. **Ningún sistema de gameplay
## reproduce sonido por su cuenta**, salvo los tres que ya tenían su reproductor
## propio antes de WP-27 y que siguen siendo los dueños de ese sonido: el
## `FireSound` del [WeaponMount], el `Sound` del [ImpactFX] y el [AudioRig] del
## enemigo. Ver «Quién suena qué» más abajo.
##
## [b]El presupuesto[/b] (`docs/13` §5.2): [constant VOICE_BUDGET] voces en total,
## con tope por categoría —motores 4, armas 6, enemigos 6, ciudad 6, interfaz 2—.
## La suma de los topes es exactamente 24, así que respetar los topes es respetar
## el presupuesto, y por eso [method active_voices] se mide sumando categorías.
##
## Con el tope lleno **se recicla la voz más lejana al oyente**, y si empatan, la
## más vieja. Es la regla de `docs/13` §5.2 y tiene una razón concreta: en una
## ciudad de 432 m el sonido que se pierde tiene que ser el que menos se oía, no
## el que llegó primero. Si no hay nada que reciclar —porque el tope lo están
## ocupando fuentes externas, como los ocho reproductores del jefe—,
## [method play_3d] devuelve `null` y no suena nada. Nunca se crea una voz de más.
##
## [b]Fuentes externas[/b]. Dos sistemas tienen su propio pool y **no** se
## desarman para meterlos acá: el [AudioRig] del jefe (`docs/07` §10) y el
## [MotorAudio] del dron (`docs/03` §6). Los dos se anotan en sus grupos
## ([constant SOURCE_GROUPS]) y este nodo los descubre, les cuenta las voces contra
## el tope de su categoría y, en el caso del jefe, le pasa la referencia para que
## respete el tope de 6 reciclando en vez de sumar. Así los servos y las
## telegrafías no se pierden nunca —son las voces que el rig no desaloja— y el
## presupuesto global sigue cerrando.
##
## [b]Quién suena qué[/b] (`docs/13` §8):
##
## | Señal | Sonido | Categoría · bus | `unit_size` |
## |---|---|---|---|
## | `shot_fired` | lo toca el `FireSound` del arma | `weapons` · `Weapons` | 12 (del `WeaponMount`) |
## | `hit_confirmed(surface = &"armor")` | `impact_armor` (metal sordo) | `weapons` · `Weapons` | 8 |
## | `hit_confirmed(surface = &"weak")` | `impact_weak` (cristal eléctrico) | `weapons` · `Weapons` | 8 |
## | `enemy_part_broken` | `part_fall` (fractura + caída) | `enemies` · `Enemies` | 24 |
## | `building_destroyed` | `collapse_low` + `collapse_debris` | `city` · `City` | 48 |
## | `Building.stage_changed` → `DAMAGED` | `damage_crack` | `city` · `City` | 48 |
## | `battery_collected` | `battery_click` | `city` · `City` | 8 |
## | `drone_damaged` | `hull_hit` (hojalata) | `weapons` · `Weapons` | 8 |
## | `drone_destroyed` | `signal_cut` | `motors` · `Motors` | 24 |
## | `drone_respawned` | `power_up` | `motors` · `Motors` | 24 |
## | `enemy_attack_telegraphed` | lo toca el [Telegraph] | `enemies` · `Enemies` | 60 (del `Telegraph`) |
## | `round_state_changed` → `BATTLE` | `ambience_night` en bucle, −18 dB | `city` · `City` | no posicional |
## | `SweepAction.update_beam()` del láser | `laser_loop` **sostenido** | `enemies` · `Enemies` | 24 |
## | `SweepAction.update_beam()` del asedio | `siege_loop` **sostenido** | `enemies` · `Enemies` | 24 |
## | `ActionEmpPulse` al soltar el pulso | `emp_ring` (estela que se aleja) | `enemies` · `Enemies` | 48 |
## | `EnemyPart` bajo el 35 % y sin romper | `sparks_loop` **sostenido**, ≤ 2 | `enemies` · `Enemies` | 16 |
##
## [b]Bucles sostenidos[/b] (WP-27b). Los cuatro efectos de WP-26 que quedaron
## mudos necesitan algo que el pool no tenía: una voz que dure lo que dure el
## hecho, que **siga a un punto que se mueve** y que no se pueda desalojar.
## [method play_loop] la entrega, [method move_loop] la mueve y [method stop_loop]
## la suelta; mientras vive, la voz queda **retenida** y el reciclaje por lejanía
## no la toca, igual que los servos del jefe. Cuenta en el tope de su categoría
## como cualquier otra, que es lo que impide que dos haces y las chispas dejen al
## jefe sin telegrafías.
##
## Cada bucle puede llevar un **ancla** ([method play_loop], parámetro `anchor`).
## El ancla no es un padre —la voz sigue colgando del pool— sino dos cosas: de
## dónde sale la posición cuando nadie llama a [method move_loop], y sobre todo
## **hasta cuándo vive el bucle**. Si el ancla se libera o sale del árbol, el
## bucle se corta en el mismo tick. Sin eso, matar al jefe con el haz encendido
## dejaría el zumbido sonando para siempre en una posición que ya no existe.
##
## [b]Por qué el impacto en blindaje es opcional[/b]. El [ImpactFX] del arma ya
## reproduce el `impact.wav` del perfil en la misma posición y en el mismo bus, y
## dos golpes idénticos separados por un frame suenan a fallo, no a capas. Por eso
## el timbre de blindaje va en [enum ArmorPolicy] `AUTO`: si el nivel tiene un
## [ImpactFXPool] con sonido cargado, el pool deja el golpe sordo en sus manos y
## agrega solo el timbre del punto débil, que es el que nadie distingue hoy. Sin
## `ImpactFXPool` —un banco de pruebas, un check— toca los dos.
class_name AudioPool
extends Node

## Grupo por el que cualquiera encuentra el pool del nivel.
const GROUP: StringName = &"audio_pool"

## Presupuesto global de voces (`docs/13` §5.2 y §9).
const VOICE_BUDGET: int = 24

## Las cinco categorías, en el orden de la tabla de §5.2.
const CATEGORY_MOTORS: StringName = &"motors"
const CATEGORY_WEAPONS: StringName = &"weapons"
const CATEGORY_ENEMIES: StringName = &"enemies"
const CATEGORY_CITY: StringName = &"city"
const CATEGORY_UI: StringName = &"ui"

## Voces como mucho por categoría. Suman [constant VOICE_BUDGET].
const CATEGORY_LIMITS: Dictionary[StringName, int] = {
	CATEGORY_MOTORS: 4,
	CATEGORY_WEAPONS: 6,
	CATEGORY_ENEMIES: 6,
	CATEGORY_CITY: 6,
	CATEGORY_UI: 2,
}

## Bus de cada categoría (`docs/13` §5.1).
const CATEGORY_BUSES: Dictionary[StringName, StringName] = {
	CATEGORY_MOTORS: &"Motors",
	CATEGORY_WEAPONS: &"Weapons",
	CATEGORY_ENEMIES: &"Enemies",
	CATEGORY_CITY: &"City",
	CATEGORY_UI: &"UI",
}

## `unit_size` por categoría, en metros: la distancia a la que el sonido vale
## 0 dB (`docs/13` §5.2). 8 para los impactos, 24 para los servos, 48 para lo que
## se tiene que oír de una punta a la otra del distrito.
const CATEGORY_UNIT_SIZES: Dictionary[StringName, float] = {
	CATEGORY_MOTORS: 24.0,
	CATEGORY_WEAPONS: 8.0,
	CATEGORY_ENEMIES: 24.0,
	CATEGORY_CITY: 48.0,
}

## `max_distance` por categoría, en metros: 600 para pisadas, servos y derrumbes;
## 200 para los impactos, que a esa distancia ya no aportan nada.
const CATEGORY_MAX_DISTANCES: Dictionary[StringName, float] = {
	CATEGORY_MOTORS: 600.0,
	CATEGORY_WEAPONS: 200.0,
	CATEGORY_ENEMIES: 600.0,
	CATEGORY_CITY: 600.0,
}

## Categorías con doppler por paso de física: proyectiles y enemigo (`docs/13`
## §5.2). El resto lo deja apagado, que es un cálculo menos por voz.
const CATEGORY_DOPPLER: Dictionary[StringName, bool] = {
	CATEGORY_MOTORS: false,
	CATEGORY_WEAPONS: true,
	CATEGORY_ENEMIES: true,
	CATEGORY_CITY: false,
}

## Grupos en los que se anotan las fuentes externas, con la categoría que ocupan y
## el método que dice cuántas voces están usando.
const SOURCE_GROUPS: Dictionary[StringName, Dictionary] = {
	&"audio_motors": {"category": CATEGORY_MOTORS, "method": &"logical_voice_count"},
	&"audio_enemies": {"category": CATEGORY_ENEMIES, "method": &"total_voices"},
}

## Carpetas del banco propio del pool.
const CITY_DIR: String = "res://assets/audio/city"
const COMBAT_DIR: String = "res://assets/audio/combat"

## Sonido de cada evento: archivo, categoría, `unit_size` (0 = el de la categoría)
## y volumen en dB.
const BANK: Dictionary[StringName, Dictionary] = {
	&"impact_armor": {"path": "%s/impact_armor.wav" % COMBAT_DIR,
		"category": CATEGORY_WEAPONS, "unit_size": 0.0, "db": -2.0},
	&"impact_weak": {"path": "%s/impact_weak.wav" % COMBAT_DIR,
		"category": CATEGORY_WEAPONS, "unit_size": 0.0, "db": 0.0},
	&"part_fall": {"path": "%s/part_fall.wav" % COMBAT_DIR,
		"category": CATEGORY_ENEMIES, "unit_size": 0.0, "db": 0.0},
	&"hull_hit": {"path": "%s/hull_hit.wav" % COMBAT_DIR,
		"category": CATEGORY_WEAPONS, "unit_size": 0.0, "db": 0.0},
	&"signal_cut": {"path": "%s/signal_cut.wav" % COMBAT_DIR,
		"category": CATEGORY_MOTORS, "unit_size": 0.0, "db": 0.0},
	&"power_up": {"path": "%s/power_up.wav" % COMBAT_DIR,
		"category": CATEGORY_MOTORS, "unit_size": 0.0, "db": -2.0},
	&"collapse_low": {"path": "%s/collapse_low.wav" % CITY_DIR,
		"category": CATEGORY_CITY, "unit_size": 0.0, "db": 0.0},
	&"collapse_debris": {"path": "%s/collapse_debris.wav" % CITY_DIR,
		"category": CATEGORY_CITY, "unit_size": 0.0, "db": -3.0},
	&"damage_crack": {"path": "%s/damage_crack.wav" % CITY_DIR,
		"category": CATEGORY_CITY, "unit_size": 24.0, "db": -4.0},
	&"battery_click": {"path": "%s/battery_click.wav" % CITY_DIR,
		"category": CATEGORY_CITY, "unit_size": 8.0, "db": -3.0},
	&"siren_far": {"path": "%s/siren_far.wav" % CITY_DIR,
		"category": CATEGORY_CITY, "unit_size": 0.0, "db": -6.0},
	# WP-27b. `loop` los hace sostenidos y `max_loops` es cuántos pueden sonar a la
	# vez: uno por haz —el jefe no dispara dos láseres— y dos de chispas, porque con
	# cuatro rodillas al 30 % el crepitar se vuelve una manta de ruido y encima se
	# come la mitad de la categoría.
	&"laser_loop": {"path": "%s/laser_loop.wav" % COMBAT_DIR,
		"category": CATEGORY_ENEMIES, "unit_size": 0.0, "db": -6.0,
		"loop": true, "max_loops": 1},
	&"siege_loop": {"path": "%s/siege_loop.wav" % COMBAT_DIR,
		"category": CATEGORY_ENEMIES, "unit_size": 0.0, "db": -3.0,
		"loop": true, "max_loops": 1},
	&"sparks_loop": {"path": "%s/sparks_loop.wav" % COMBAT_DIR,
		"category": CATEGORY_ENEMIES, "unit_size": 16.0, "db": -10.0,
		"loop": true, "max_loops": 2},
	&"emp_ring": {"path": "%s/emp_ring.wav" % COMBAT_DIR,
		"category": CATEGORY_ENEMIES, "unit_size": 48.0, "db": -2.0},
}

## Vida por debajo de la cual una parte del enemigo chisporrotea, igual que las
## chispas del [VFXPool] (`docs/13` §4). El umbral vive acá y no en `EnemyPart`
## para que el gancho de allá sea una sola línea y la perilla quede en el audio.
const SPARKS_RATIO: float = 0.35

## Grupo de los edificios del distrito y etapa «dañado» de [Building].
##
## Van como literales y no como `Building.GROUP` / `Building.Stage.DAMAGED` a
## propósito: referenciar la clase por nombre ataría este nodo —y con él,
## cualquier escena que tenga audio— a que compile `city/building.gd`, que a su
## vez arrastra el [VFXPool] y las diecisiete escenas de `vfx/`. El audio no
## necesita nada de eso para reproducir un crujido.
const BUILDING_GROUP: StringName = &"buildings"
const BUILDING_STAGE_DAMAGED: int = 1

## Grupo del [ImpactFXPool] del arma, por la misma razón.
const IMPACT_FX_POOL_GROUP: StringName = &"impact_fx_pool"

## Ambiente nocturno: bucle no posicional en el bus `City`.
const AMBIENCE_PATH: String = "%s/ambience_night.wav" % CITY_DIR

## Volumen del ambiente, en dB (`docs/13` §5).
const AMBIENCE_DB: float = -18.0

## Segundos del fundido de entrada y de salida del ambiente.
const AMBIENCE_FADE: float = 1.5

## Qué hace el pool con el golpe de blindaje.
enum ArmorPolicy {
	AUTO,   ## Lo toca solo si no hay un [ImpactFXPool] con sonido en el nivel.
	ALWAYS, ## Lo toca siempre (banco de pruebas).
	NEVER,  ## No lo toca nunca; el `ImpactFX` es el dueño.
}

## Ver [enum ArmorPolicy].
@export var armor_policy: ArmorPolicy = ArmorPolicy.AUTO

## Si el pool reproduce el ambiente nocturno durante `BATTLE`.
@export var ambience_enabled: bool = true

## Si el pool escucha el bus. Un check puede apagarlo para disparar a mano.
@export var listen_to_events: bool = true

## Un bucle sostenido: su voz, qué suena, a qué sigue y si alguien le está
## dictando la posición a mano.
class Loop:
	var voice: AudioStreamPlayer3D = null
	var event: StringName = &""
	var anchor: Node3D = null
	var manual: bool = false
	var key: String = ""

	## Si el bucle nació con ancla.
	##
	## Es un booleano y no `anchor != null` por una trampa de GDScript que costó
	## una tarde: un objeto **liberado** compara igual a `null`, así que el ancla
	## muerta —justo el caso que hay que detectar— se leía como «este bucle no
	## tenía ancla» y el zumbido sobrevivía al enemigo. Con la bandera aparte, la
	## pregunta que se hace es `is_instance_valid()`, que sí distingue las dos
	## cosas.
	var anchored: bool = false

var _players: Dictionary[StringName, Array] = {}
var _started_msec: Dictionary[StringName, PackedFloat64Array] = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_started_msec: PackedFloat64Array = PackedFloat64Array()
var _streams: Dictionary[StringName, AudioStream] = {}
var _sources: Array[Dictionary] = []
var _ambience: AudioStreamPlayer = null
var _ambience_tween: Tween = null
var _wired_buildings: Dictionary[int, bool] = {}
var _impact_fx_pool: Node = null
var _played: Dictionary[StringName, int] = {}
var _loops: Array[Loop] = []
var _held: Dictionary[int, bool] = {}
var _anchored: Dictionary[String, Loop] = {}


func _ready() -> void:
	add_to_group(GROUP)
	# El seguimiento de bucles sólo corre cuando hay alguno: sin haces ni chispas
	# esto no gasta un tick.
	set_physics_process(false)
	_build_voices()
	_build_ambience()
	if listen_to_events:
		_connect_events()
	_discover_sources.call_deferred()
	_resolve_impact_fx_pool.call_deferred()


## Al salir del árbol no queda nada sonando ni ningún [Tween] vivo. Un nivel que
## se descarga con el ambiente a medio fundido deja la reproducción abierta, y eso
## es lo que Godot reporta como «recursos en uso» al cerrar el proceso.
func _exit_tree() -> void:
	_disconnect_events()
	stop_all()


# --------------------------------------------------------------------------
# Interfaz pública (`docs/13` §8)
# --------------------------------------------------------------------------

## Reproduce [param stream] en [param position] dentro de [param category].
##
## Devuelve el reproductor que se llevó la voz, o `null` si la categoría estaba
## llena y no había nada reciclable. Nunca crea una voz por encima del tope.
func play_3d(stream: AudioStream, position: Vector3, category: StringName,
		volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	if stream == null or not CATEGORY_LIMITS.has(category) or category == CATEGORY_UI:
		return null
	var player := _acquire(category, position)
	if player == null:
		return null
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch, 0.01)
	player.unit_size = float(CATEGORY_UNIT_SIZES.get(category, 24.0))
	player.max_distance = float(CATEGORY_MAX_DISTANCES.get(category, 600.0))
	_reset_doppler(player, bool(CATEGORY_DOPPLER.get(category, false)))
	player.play()
	return player


## Reproduce un sonido de interfaz, sin posición, en el bus `UI`.
##
## La interfaz tiene su propio reproductor en el autoload [UI] para los menús;
## esto es para lo que suena **durante el juego** y tiene que contar contra el
## presupuesto: avisos del HUD, confirmaciones de objetivo.
func play_ui(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or _ui_players.is_empty():
		return
	var chosen := -1
	for index: int in _ui_players.size():
		if not _ui_players[index].playing:
			chosen = index
			break
	if chosen < 0:
		# Sin voz libre se recicla la más vieja: en interfaz no hay distancia con
		# la que decidir.
		chosen = 0
		for index: int in _ui_players.size():
			if _ui_started_msec[index] < _ui_started_msec[chosen]:
				chosen = index
		_ui_players[chosen].stop()
	var player := _ui_players[chosen]
	player.stream = stream
	player.volume_db = volume_db
	_ui_started_msec[chosen] = float(Time.get_ticks_msec())
	player.play()


## Voces sonando ahora mismo, propias y de las fuentes externas (`docs/13` §5.2).
func active_voices() -> int:
	var total := 0
	for category: StringName in CATEGORY_LIMITS:
		total += category_voices(category)
	return total


## Voces de una categoría: las propias del pool más las de sus fuentes externas.
func category_voices(category: StringName) -> int:
	return _own_voices(category) + external_voices(category)


## Tope de voces de una categoría.
func category_limit(category: StringName) -> int:
	return int(CATEGORY_LIMITS.get(category, 0))


## Presupuesto global.
func budget() -> int:
	return VOICE_BUDGET


## `true` si la categoría todavía tiene sitio para una voz más. Lo consulta el
## [AudioRig] antes de tomar una voz libre de su propio pool.
func can_claim(category: StringName) -> bool:
	return category_voices(category) < category_limit(category)


## Da de alta una fuente externa: un nodo con su propio pool de voces que ocupa
## presupuesto en [param category]. [param voices_method] es el método sin
## argumentos que devuelve cuántas voces está usando.
func register_source(category: StringName, source: Node,
		voices_method: StringName = &"active_voices") -> void:
	if source == null or not CATEGORY_LIMITS.has(category):
		return
	if not source.has_method(voices_method):
		push_error("AudioPool: %s no tiene %s()" % [source.name, String(voices_method)])
		return
	for row: Dictionary in _sources:
		if row["node"] == source:
			return
	_sources.append({"category": category, "node": source, "method": voices_method})
	# El jefe necesita la referencia de vuelta para respetar el tope de 6 sin
	# perder servos ni telegrafías (`docs/13` §8).
	if source.has_method(&"set_voice_pool"):
		source.call(&"set_voice_pool", self)


## Da de baja una fuente externa.
func unregister_source(source: Node) -> void:
	for index: int in range(_sources.size() - 1, -1, -1):
		if _sources[index]["node"] == source:
			_sources.remove_at(index)


## Voces que están usando las fuentes externas de una categoría.
func external_voices(category: StringName) -> int:
	var total := 0
	for index: int in range(_sources.size() - 1, -1, -1):
		var row := _sources[index]
		var node := row["node"] as Node
		if node == null or not is_instance_valid(node):
			_sources.remove_at(index)
			continue
		if row["category"] != category:
			continue
		total += int(node.call(row["method"]))
	return total


## Dispara un evento del banco en [param position]. Devuelve el reproductor o
## `null`. Es lo que usan los manejadores del bus y `audio_check`.
func play_event(event: StringName, position: Vector3, volume_db: float = 0.0,
		pitch: float = 1.0) -> AudioStreamPlayer3D:
	var row: Dictionary = BANK.get(event, {})
	if row.is_empty():
		return null
	var stream := _stream_for(event)
	if stream == null:
		return null
	var category: StringName = row["category"]
	var player := play_3d(stream, position, category, float(row["db"]) + volume_db, pitch)
	if player == null:
		return null
	var unit_size := float(row["unit_size"])
	if unit_size > 0.0:
		player.unit_size = unit_size
	_played[event] = int(_played.get(event, 0)) + 1
	return player


## Cuántas veces se disparó cada evento del banco. Lo mira `audio_check`.
func event_counts() -> Dictionary[StringName, int]:
	return _played


## `true` si el evento tiene sonido cargado.
func has_event(event: StringName) -> bool:
	return _stream_for(event) != null


## Enciende o apaga el ambiente nocturno con un fundido de
## [constant AMBIENCE_FADE] segundos.
func set_ambience(enabled: bool) -> void:
	if _ambience == null or _ambience.stream == null:
		return
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	if enabled:
		if not _ambience.playing:
			_ambience.volume_db = Audio.SILENT_DB
			_ambience.play()
		_ambience_tween = create_tween()
		var _fade_in := _ambience_tween.tween_property(_ambience, ^"volume_db",
				AMBIENCE_DB, AMBIENCE_FADE)
		return
	if not _ambience.playing:
		return
	_ambience_tween = create_tween()
	var _fade_out := _ambience_tween.tween_property(_ambience, ^"volume_db",
			Audio.SILENT_DB, AMBIENCE_FADE)
	var _stop := _ambience_tween.tween_callback(_ambience.stop)


## `true` si el ambiente está sonando.
func is_ambience_playing() -> bool:
	return _ambience != null and _ambience.playing


## Corta todo: voces, interfaz y ambiente. Lo usan los checks entre pasadas.
func stop_all() -> void:
	for loop: Loop in _loops:
		_release_loop(loop)
	_loops.clear()
	_anchored.clear()
	_held.clear()
	set_physics_process(false)
	for category: StringName in _players:
		for player: AudioStreamPlayer3D in _players[category]:
			player.stop()
	for player: AudioStreamPlayer in _ui_players:
		player.stop()
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	if _ambience != null:
		_ambience.stop()


## El [AudioPool] del nivel, o `null` si [param from] no está en el árbol o no hay
## ninguno. Mismo patrón que [method VFXPool.resolve]: el que pide sonido no
## guarda referencias ni se cablea, pregunta y sigue.
static func resolve(from: Node) -> AudioPool:
	if from == null or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as AudioPool


## Atajo de una línea para los ganchos de gameplay: dispara un evento del banco
## sin tener que resolver el pool. Devuelve `null` si no hay pool o no hay voz.
static func emit_event(from: Node, event: StringName,
		position: Vector3) -> AudioStreamPlayer3D:
	var pool := resolve(from)
	return pool.play_event(event, position) if pool != null else null


## Atajo de una línea para encender o apagar un bucle anclado (chispas de una
## parte, por ejemplo). Sin pool no hace nada.
static func toggle_loop(from: Node, event: StringName, anchor: Node3D,
		active: bool) -> void:
	var pool := resolve(from)
	if pool != null:
		pool.set_anchored_loop(event, anchor, active)


## Arranca un bucle sostenido en [param position] y devuelve su voz, o `null` si
## el evento no es de bucle, ya hay tantos como admite, o la categoría está llena
## de voces que no se pueden desalojar.
##
## La voz queda **retenida**: no la recicla el reparto por lejanía mientras dure.
## A cambio, el que la pide es responsable de soltarla con [method stop_loop], o
## de darle un [param anchor] que lo haga por él cuando desaparezca.
func play_loop(event: StringName, position: Vector3,
		anchor: Node3D = null) -> AudioStreamPlayer3D:
	var row: Dictionary = BANK.get(event, {})
	if row.is_empty() or not bool(row.get("loop", false)):
		return null
	if loop_count(event) >= int(row.get("max_loops", 1)):
		return null
	var stream := _stream_for(event)
	if stream == null:
		return null
	var category: StringName = row["category"]
	# `forced`: un haz sostenido no se descarta por estar lejos. Lo que dura se
	# oye; lo que no, se recicla.
	var player := _acquire(category, position, true)
	if player == null:
		return null
	player.stream = stream
	player.global_position = position
	player.volume_db = float(row["db"])
	player.pitch_scale = 1.0
	player.unit_size = float(row["unit_size"]) if float(row["unit_size"]) > 0.0 \
			else float(CATEGORY_UNIT_SIZES.get(category, 24.0))
	player.max_distance = float(CATEGORY_MAX_DISTANCES.get(category, 600.0))
	_reset_doppler(player, bool(CATEGORY_DOPPLER.get(category, false)))
	player.play()
	var loop := Loop.new()
	loop.voice = player
	loop.event = event
	loop.anchor = anchor
	loop.anchored = anchor != null
	_loops.append(loop)
	_held[player.get_instance_id()] = true
	_played[event] = int(_played.get(event, 0)) + 1
	if not is_physics_processing():
		set_physics_process(true)
	return player


## Mueve un bucle al punto donde está pasando el hecho. Desde la primera llamada,
## el bucle deja de seguir a su ancla: manda quien lo mueve.
func move_loop(voice: AudioStreamPlayer3D, position: Vector3) -> void:
	var loop := _loop_of(voice)
	if loop == null:
		return
	loop.manual = true
	voice.global_position = position


## Corta un bucle y devuelve su voz al reparto. Es idempotente.
func stop_loop(voice: AudioStreamPlayer3D) -> void:
	for index: int in range(_loops.size() - 1, -1, -1):
		if _loops[index].voice != voice:
			continue
		_release_loop(_loops[index])
		_loops.remove_at(index)
	set_physics_process(not _loops.is_empty())


## Enciende o apaga un bucle **por ancla**: como mucho uno de cada evento por cada
## [param anchor], y la posición sale del ancla en cada tick.
##
## Es lo que usan las chispas de una parte dañada, que se encienden al cruzar el
## umbral de vida y se apagan al subir de ahí o al romperse. Llamarlo dos veces
## con el mismo valor no hace nada.
func set_anchored_loop(event: StringName, anchor: Node3D, active: bool) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var key := "%s:%d" % [String(event), anchor.get_instance_id()]
	var live: Loop = _anchored.get(key, null)
	if active:
		if live != null and is_instance_valid(live.voice) and live.voice.playing:
			return
		var voice := play_loop(event, anchor.global_position, anchor)
		if voice == null:
			return
		var loop := _loop_of(voice)
		if loop != null:
			loop.key = key
			_anchored[key] = loop
		return
	if live == null:
		return
	var _discard := _anchored.erase(key)
	if is_instance_valid(live.voice):
		stop_loop(live.voice)


## Bucles de un evento sonando ahora mismo.
func loop_count(event: StringName) -> int:
	var count := 0
	for loop: Loop in _loops:
		if loop.event == event:
			count += 1
	return count


## Bucles sostenidos vivos, del evento que sean. Lo mira `audio_check`.
func active_loops() -> int:
	return _loops.size()


## `true` si [param voice] es un bucle retenido.
func is_loop(voice: AudioStreamPlayer3D) -> bool:
	return _loop_of(voice) != null


## Sigue a las anclas y corta los bucles que se quedaron sin ella.
##
## Lo segundo es lo que importa: un enemigo liberado mientras el haz está
## encendido no llama a `hide_beam()` —el nodo de la acción se va con él— y el
## zumbido quedaría sonando en el aire. Con el ancla, el corte llega el mismo tick.
func _physics_process(_delta: float) -> void:
	PerfProbe.begin(&"audio_pool")
	for index: int in range(_loops.size() - 1, -1, -1):
		var loop := _loops[index]
		var dead := not is_instance_valid(loop.voice)
		if not dead and loop.anchored:
			dead = not is_instance_valid(loop.anchor) or not loop.anchor.is_inside_tree()
		if not dead and not loop.voice.playing:
			# El archivo se acabó: o no importó en bucle, o alguien lo paró.
			dead = true
		if dead:
			_release_loop(loop)
			_loops.remove_at(index)
			continue
		if not loop.manual and loop.anchored:
			loop.voice.global_position = loop.anchor.global_position
	# Solo en la transición: este método corre a 100 Hz mientras haya un haz
	# encendido, y `set_physics_process()` no es gratis —toca la lista de nodos
	# que procesa el `SceneTree`—. Estando acá, el proceso ya está encendido; lo
	# único que puede cambiar es que se haya vaciado.
	if _loops.is_empty():
		set_physics_process(false)
	PerfProbe.end(&"audio_pool")


## Apaga la voz de un bucle y la devuelve al reparto.
func _release_loop(loop: Loop) -> void:
	if not loop.key.is_empty():
		var _gone := _anchored.erase(loop.key)
	if loop.voice == null or not is_instance_valid(loop.voice):
		return
	var _unheld := _held.erase(loop.voice.get_instance_id())
	loop.voice.stop()


## El bucle que lleva esta voz, o `null`.
func _loop_of(voice: AudioStreamPlayer3D) -> Loop:
	for loop: Loop in _loops:
		if loop.voice == voice:
			return loop
	return null


# --------------------------------------------------------------------------
# Voces
# --------------------------------------------------------------------------

## Crea los reproductores de cada categoría. Se crean todos de entrada —son 24 y
## no cuestan nada apagados— porque instanciar un [AudioStreamPlayer3D] en mitad
## de un derrumbe es exactamente el tirón que el pool existe para evitar.
func _build_voices() -> void:
	for category: StringName in CATEGORY_LIMITS:
		if category == CATEGORY_UI:
			continue
		var limit := category_limit(category)
		var list: Array[AudioStreamPlayer3D] = []
		var ages := PackedFloat64Array()
		for index: int in limit:
			var player := AudioStreamPlayer3D.new()
			player.name = "%s_%d" % [String(category).capitalize(), index]
			player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
			player.unit_size = float(CATEGORY_UNIT_SIZES.get(category, 24.0))
			player.max_distance = float(CATEGORY_MAX_DISTANCES.get(category, 600.0))
			player.panning_strength = 1.0
			player.bus = String(CATEGORY_BUSES.get(category, &"Master"))
			player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP \
					if bool(CATEGORY_DOPPLER.get(category, false)) \
					else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			add_child(player)
			list.append(player)
			ages.append(0.0)
		_players[category] = list
		_started_msec[category] = ages

	for index: int in category_limit(CATEGORY_UI):
		var player := AudioStreamPlayer.new()
		player.name = "Ui_%d" % index
		player.bus = String(CATEGORY_BUSES.get(CATEGORY_UI, &"Master"))
		add_child(player)
		_ui_players.append(player)
		_ui_started_msec.append(0.0)


## Toma una voz de [param category] para un sonido que va a sonar en
## [param position].
##
## Primero busca una libre dentro del tope; si el tope está lleno recicla la que
## esté **más lejos del oyente** y, a igual distancia, la más vieja. Devuelve
## `null` si el tope lo ocupan fuentes externas y no hay nada propio que reciclar.
func _acquire(category: StringName, position: Vector3,
		forced: bool = false) -> AudioStreamPlayer3D:
	var list := _players.get(category, []) as Array
	if list.is_empty():
		return null
	var ages := _started_msec[category] as PackedFloat64Array
	var now := float(Time.get_ticks_msec())
	if can_claim(category):
		for index: int in list.size():
			var player := list[index] as AudioStreamPlayer3D
			if not player.playing:
				ages[index] = now
				return player
	var listener := _listener_position()
	var worst := -1
	var worst_distance := -1.0
	var worst_age := INF
	for index: int in list.size():
		var player := list[index] as AudioStreamPlayer3D
		if not player.playing or _held.has(player.get_instance_id()):
			# Un bucle sostenido no se desaloja: es el hecho que está pasando, no
			# su cola. Misma regla que los servos del jefe (`docs/13` §8).
			continue
		var distance := player.global_position.distance_squared_to(listener)
		if distance > worst_distance \
				or (is_equal_approx(distance, worst_distance) and ages[index] < worst_age):
			worst = index
			worst_distance = distance
			worst_age = ages[index]
	if worst < 0:
		return null
	# La voz nueva solo vale la pena si va a oírse más que la que desaloja. Un
	# bucle forzado se salta la regla: lo que dura se oye.
	var incoming := position.distance_squared_to(listener)
	if not forced and incoming > worst_distance:
		return null
	var chosen := list[worst] as AudioStreamPlayer3D
	chosen.stop()
	ages[worst] = now
	return chosen


## Voces propias sonando en una categoría. El ambiente cuenta como voz de ciudad:
## es sonido que sale por el bus y tiene que entrar en el presupuesto.
func _own_voices(category: StringName) -> int:
	var count := 0
	if category == CATEGORY_UI:
		for player: AudioStreamPlayer in _ui_players:
			if player.playing:
				count += 1
		return count
	for player: AudioStreamPlayer3D in _players.get(category, []) as Array:
		if player.playing:
			count += 1
	if category == CATEGORY_CITY and is_ambience_playing():
		count += 1
	return count


## Posición del oyente: la cámara que esté dibujando. Sin cámara —un check
## headless sin viewport 3D— el origen sirve igual, porque lo único que se usa es
## el orden relativo de las distancias.
func _listener_position() -> Vector3:
	var viewport := get_viewport()
	if viewport == null:
		return Vector3.ZERO
	var camera := viewport.get_camera_3d()
	if camera == null or not is_instance_valid(camera):
		return Vector3.ZERO
	return camera.global_position


## Reinicia el seguimiento de doppler de una voz reciclada.
##
## No es adorno: el doppler de Godot sale de la **velocidad** del nodo entre dos
## pasos de física, y teletransportar un reproductor de un impacto a otro a 200 m
## le daría una velocidad de decenas de km/s durante un frame, o sea un salto de
## tono absurdo en el ataque del sonido. Apagar y volver a encender el seguimiento
## pone el rastreador de velocidad a cero.
func _reset_doppler(player: AudioStreamPlayer3D, enabled: bool) -> void:
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	if enabled:
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP


func _build_ambience() -> void:
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.bus = String(CATEGORY_BUSES.get(CATEGORY_CITY, &"Master"))
	_ambience.volume_db = AMBIENCE_DB
	if ResourceLoader.exists(AMBIENCE_PATH):
		_ambience.stream = ResourceLoader.load(AMBIENCE_PATH, "AudioStream") as AudioStream
	add_child(_ambience)


## Carga (y cachea) el sonido de un evento del banco.
func _stream_for(event: StringName) -> AudioStream:
	if _streams.has(event):
		return _streams[event]
	var row: Dictionary = BANK.get(event, {})
	var stream: AudioStream = null
	var path := String(row.get("path", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		stream = ResourceLoader.load(path, "AudioStream") as AudioStream
	_streams[event] = stream
	return stream


# --------------------------------------------------------------------------
# Fuentes externas
# --------------------------------------------------------------------------

## Da de alta lo que haya en los grupos de [constant SOURCE_GROUPS].
##
## Se llama diferido en `_ready()` —el distrito y los enemigos los instancia
## `RoundManager.begin()`, que corre después— y otra vez en cada cambio de estado
## de ronda y en cada `enemy_spawned`.
func _discover_sources() -> void:
	if not is_inside_tree():
		return
	for group: StringName in SOURCE_GROUPS:
		var row: Dictionary = SOURCE_GROUPS[group]
		for node: Node in get_tree().get_nodes_in_group(group):
			register_source(row["category"], node, row["method"])


# --------------------------------------------------------------------------
# Bus de eventos
# --------------------------------------------------------------------------

func _connect_events() -> void:
	var _hit := Events.hit_confirmed.connect(_on_hit_confirmed)
	var _part := Events.enemy_part_broken.connect(_on_part_broken)
	var _building := Events.building_destroyed.connect(_on_building_destroyed)
	var _battery := Events.battery_collected.connect(_on_battery_collected)
	var _damaged := Events.drone_damaged.connect(_on_drone_damaged)
	var _destroyed := Events.drone_destroyed.connect(_on_drone_destroyed)
	var _respawned := Events.drone_respawned.connect(_on_drone_respawned)
	var _state := Events.round_state_changed.connect(_on_round_state_changed)
	var _spawned := Events.enemy_spawned.connect(_on_enemy_spawned)


func _disconnect_events() -> void:
	if Events.hit_confirmed.is_connected(_on_hit_confirmed):
		Events.hit_confirmed.disconnect(_on_hit_confirmed)
	if Events.enemy_part_broken.is_connected(_on_part_broken):
		Events.enemy_part_broken.disconnect(_on_part_broken)
	if Events.building_destroyed.is_connected(_on_building_destroyed):
		Events.building_destroyed.disconnect(_on_building_destroyed)
	if Events.battery_collected.is_connected(_on_battery_collected):
		Events.battery_collected.disconnect(_on_battery_collected)
	if Events.drone_damaged.is_connected(_on_drone_damaged):
		Events.drone_damaged.disconnect(_on_drone_damaged)
	if Events.drone_destroyed.is_connected(_on_drone_destroyed):
		Events.drone_destroyed.disconnect(_on_drone_destroyed)
	if Events.drone_respawned.is_connected(_on_drone_respawned):
		Events.drone_respawned.disconnect(_on_drone_respawned)
	if Events.round_state_changed.is_connected(_on_round_state_changed):
		Events.round_state_changed.disconnect(_on_round_state_changed)
	if Events.enemy_spawned.is_connected(_on_enemy_spawned):
		Events.enemy_spawned.disconnect(_on_enemy_spawned)


## El metal sordo del blindaje suena **sólo** si el disparo pegó en blindaje.
##
## Antes bastaba con `weak = false`, y eso metía el mismo golpe metálico en cada
## tiro a una fachada de hormigón. Con la superficie de WP-26 (`docs/02` §5.1) el
## pool distingue los cuatro casos: `city` y `world` los deja para el
## `ImpactFXPool`, que ya tiene su sonido por variante de superficie.
func _on_hit_confirmed(position: Vector3, _weak: bool, _lethal: bool,
		surface: StringName) -> void:
	if surface == &"weak":
		var _weak_player := play_event(&"impact_weak", position)
		return
	if surface != &"armor" or not _plays_armor_impact():
		return
	var _armor_player := play_event(&"impact_armor", position)


## Una parte que se rompe suena dos veces: la fractura la toca el [AudioRig] del
## jefe (`part_break`, `docs/07` §10) y la **caída** la toca el pool, 0.35 s más
## tarde, que es lo que tarda un pedazo de coloso en llegar al suelo.
func _on_part_broken(_enemy: Node3D, _part_id: StringName, position: Vector3) -> void:
	var _player := play_event(&"part_fall", position)


## El derrumbe son dos capas a la vez: el sub-grave del peso y la cascada de
## hormigón. Una sola no se lee como «se cayó un edificio».
func _on_building_destroyed(position: Vector3, _value: int) -> void:
	var _low := play_event(&"collapse_low", position)
	var _debris := play_event(&"collapse_debris", position)


func _on_battery_collected(_amount: float, position: Vector3) -> void:
	var _player := play_event(&"battery_click", position)


func _on_drone_damaged(_amount: float, source_position: Vector3) -> void:
	var _player := play_event(&"hull_hit", source_position)


func _on_drone_destroyed(position: Vector3) -> void:
	var _player := play_event(&"signal_cut", position)


func _on_drone_respawned(_score_multiplier: float) -> void:
	var _player := play_event(&"power_up", _listener_position())


func _on_round_state_changed(state: int) -> void:
	if ambience_enabled:
		set_ambience(state == Global.RoundState.BATTLE)
	_discover_sources()
	_wire_buildings()
	_resolve_impact_fx_pool()


func _on_enemy_spawned(_enemy: Node3D, _enemy_id: StringName) -> void:
	_discover_sources.call_deferred()


## Se engancha al `stage_changed` de cada edificio del distrito para el crujido de
## daño. La señal no lleva posición, así que el edificio viaja en el `bind`.
##
## El distrito no existe cuando este nodo arranca —lo instancia
## `RoundManager.begin()`—, por eso el barrido se repite en cada cambio de estado
## de ronda y lleva su propio registro de a quién ya enganchó.
func _wire_buildings() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(BUILDING_GROUP):
		var building := node as Node3D
		if building == null or not building.has_signal(&"stage_changed"):
			continue
		var id := building.get_instance_id()
		if _wired_buildings.has(id):
			continue
		_wired_buildings[id] = true
		var _stage := building.connect(&"stage_changed", _on_building_stage.bind(building))


func _on_building_stage(stage: int, building: Node3D) -> void:
	if stage != BUILDING_STAGE_DAMAGED or not is_instance_valid(building):
		return
	var _player := play_event(&"damage_crack", building.global_position)


## `true` si el golpe de blindaje lo tiene que tocar el pool (ver [enum ArmorPolicy]).
func _plays_armor_impact() -> bool:
	match armor_policy:
		ArmorPolicy.ALWAYS:
			return true
		ArmorPolicy.NEVER:
			return false
	# Una comparación, no un barrido: el nodo se resuelve al entrar al árbol y en
	# cada cambio de estado de ronda ([method _resolve_impact_fx_pool]). Esto corre
	# en **cada bala que pega en el blindaje** —ocho por segundo con el arma
	# sostenida— y antes recorría un grupo entero y leía una propiedad por nodo.
	if _impact_fx_pool == null or not is_instance_valid(_impact_fx_pool):
		return true
	# El `impact_sound` se lo cablea `ProjectilePool` desde el perfil del arma, que
	# puede llegar después que este nodo; por eso se lee ahora y no se congela en
	# un booleano al resolver.
	return _impact_fx_pool.get(&"impact_sound") == null


## Busca el [ImpactFXPool] del nivel y lo guarda. Se llama al entrar al árbol
## —diferido, porque los pools del nivel se arman en el mismo `_ready()`— y en
## cada cambio de estado de ronda, junto con el barrido de edificios.
func _resolve_impact_fx_pool() -> void:
	if not is_inside_tree():
		return
	if _impact_fx_pool != null and is_instance_valid(_impact_fx_pool):
		return
	_impact_fx_pool = get_tree().get_first_node_in_group(IMPACT_FX_POOL_GROUP)
