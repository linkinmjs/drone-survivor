## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Música por capas: tres stems sincronizados y dos stings (`docs/13` §5.3).
##
## Cuelga de `Pools/MusicDirector` en el nivel, suena en el bus `Music` y **no se
## reinicia nunca**. Los tres stems —`ambient`, `tension`, `combat`— viven dentro
## de un [AudioStreamSynchronized], o sea que comparten reloj: lo único que cambia
## es el volumen de cada capa. Por eso no hay saltos de fase, ni cortes, ni
## compases perdidos al pasar de la calma al combate; lo que se oye es una capa
## que se enciende encima de la que ya estaba.
##
## [b]La tabla[/b] (`docs/13` §5.3), con cruces de [constant CROSSFADE_SECONDS]:
##
## | Situación | `ambient` | `tension` | `combat` |
## |---|---|---|---|
## | `INTRO` y `ALERT` | 0 dB | −18 dB | −80 dB |
## | `BATTLE`, fases `p1_siege` y `p2_alert` | −4 dB | 0 dB | −80 dB |
## | `BATTLE`, fases `p3_fury`, `p4_belly`, `p5_selfdestruct` | −10 dB | −4 dB | 0 dB |
## | Dron destruido / reconstruyéndose | −6 dB | −10 dB | −24 dB |
## | `VICTORY` / `DEFEAT` | −80 dB + sting | −80 dB | −80 dB |
##
## [b]Intensidad[/b]: dentro de `BATTLE`, la música respira ±[constant INTENSITY_RANGE_DB]
## dB sobre `tension` sin cambiar de capa. `docs/13` §5.3 define la intensidad como
## `v = f(distancia al jefe, daño recibido en los últimos 5 s)`, y este nodo la
## calcula solo:
##
## [codeblock]
## cercanía = clamp((LEJOS − distancia) / (LEJOS − CERCA), 0, 1)   # 1 encima del jefe
## calor    = clamp(daño acumulado / DAMAGE_FULL_HP, 0, 1)         # decae a 0 en 5 s
## v        = 0.5 · cercanía + 0.5 · calor
## [/codeblock]
##
## Mitad y mitad a propósito: con solo la distancia, quedarse lejos apagaría la
## música aunque el jefe estuviera desarmando la ciudad; con solo el daño, un
## piloto que no cobra nunca jugaría en silencio. Sumadas, la música sube cuando el
## jugador **se mete** o cuando **le pegan**, que son las dos formas de que la
## pelea apriete. La distancia se muestrea a [constant DISTANCE_SAMPLE_HZ] Hz —no
## hace falta más para algo que tarda medio segundo en moverse— y tolera que no
## haya jefe o no haya dron: sin ninguno de los dos, la cercanía es 0 y la música
## se queda abajo.
##
## Fuera de `BATTLE` la intensidad vuelve a 0.5, que es desvío 0: ni la intro ni la
## tarjeta de resultado heredan el color del último combate.
##
## El desvío **no se aplica con un [Tween] por llamada** —serían dos por segundo,
## creados y tirados— sino con una rampa por acumulador en [method _process],
## limitada a [constant INTENSITY_SLEW_DB_PER_SECOND]. Eso además garantiza lo que
## mide `audio_check`: ningún paso de 20 ms mueve el stem más de 0.48 dB.
##
## El desvío se **atenúa cuando la capa se está apagando** (ver
## [method stem_volume_db]): si no, cruzar a −80 dB con la intensidad al máximo
## daría un escalón de 6 dB en mitad del fundido.
##
## [b]Nota de API de Godot 4.7[/b]: `docs/13` §5.3 dice que los volúmenes se mueven
## con `AudioStreamPlaybackSynchronized.set_stream_volume(i, db)`. Ese método no
## existe: el playback no expone nada y quien lleva los volúmenes es el **recurso**
## [AudioStreamSynchronized], con `set_sync_stream_volume(i, db)`, que el mezclador
## lee en cada bloque. Es la única diferencia con el documento y el efecto es el
## mismo. Como los volúmenes viven en el recurso y no en la reproducción, este
## nodo **arma el suyo** en `_ready()` en vez de cargar un `.tres` compartido: dos
## niveles a la vez —o un nivel y un check— se pisarían la mezcla.
class_name MusicDirector
extends AudioStreamPlayer

## Los tres stems, en el orden en que entran al [AudioStreamSynchronized]. El
## índice es el que devuelve [method stem_volume_db].
const STEMS: Array[StringName] = [&"ambient", &"tension", &"combat"]

## Índices, por legibilidad.
const STEM_AMBIENT: int = 0
const STEM_TENSION: int = 1
const STEM_COMBAT: int = 2

## Carpeta de la música.
const MUSIC_DIR: String = "res://assets/audio/music"

## Bus de la música (`docs/13` §5.1).
const BUS: StringName = &"Music"

## Duración de los cruces, en segundos (`docs/13` §5.3 y §9).
const CROSSFADE_SECONDS: float = 2.5

## Duración del cruce de la intensidad. Es más corto que el de capa porque no
## cambia la música, solo la empuja.
const INTENSITY_SECONDS: float = 0.5

## Cuánto mueve la intensidad al stem `tension`, en dB hacia cada lado.
const INTENSITY_RANGE_DB: float = 6.0

## Ritmo de la rampa de intensidad, en dB por segundo: el recorrido entero
## (±6 dB) en [constant INTENSITY_SECONDS]. Son 0.48 dB por cada 20 ms, muy por
## debajo del tope de 6 que vigila `audio_check`.
const INTENSITY_SLEW_DB_PER_SECOND: float = 2.0 * INTENSITY_RANGE_DB / INTENSITY_SECONDS

## Segundos que el daño recibido sigue contando (`docs/13` §5.3).
const DAMAGE_MEMORY_SECONDS: float = 5.0

## Daño acumulado dentro de esa ventana que satura la mitad «calor» de la
## intensidad. El casco del dron son 100 puntos (`docs/09`), así que 60 es «te
## están pegando en serio» sin pedir que estés muerto.
const DAMAGE_FULL_HP: float = 60.0

## Distancias al jefe, en metros, entre las que se mueve la mitad «cercanía».
## Encima del jefe es 1; a 160 m —casi la diagonal del distrito— es 0.
const DISTANCE_NEAR: float = 30.0
const DISTANCE_FAR: float = 160.0

## Cada cuánto se mide la distancia al jefe, en hercios.
const DISTANCE_SAMPLE_HZ: float = 4.0

## Grupo del jefe (`EnemyBase.GROUP`) y de la cámara del dron
## (`FPVCamera`), por nombre para no atar la música a esas clases.
const ENEMY_GROUP: StringName = &"enemies"
const DRONE_EYE_GROUP: StringName = &"fpv_camera"

## dB con el que un stem se considera apagado.
const SILENT_DB: float = -80.0

## Por encima de esta suma sobre [constant SILENT_DB] el desvío de intensidad se
## aplica entero; por debajo se desvanece con la propia capa.
const INTENSITY_FADE_DB: float = 20.0

## Fases que piden el stem `combat` (`docs/13` §5.3, `docs/07` §6). El resto de las
## fases de `BATTLE` se quedan en `tension`.
const COMBAT_PHASES: Array[StringName] = [&"p3_fury", &"p4_belly", &"p5_selfdestruct"]

## Las filas de la tabla de §5.3.
const MIX_INTRO: Array[float] = [0.0, -18.0, SILENT_DB]
const MIX_BATTLE_EARLY: Array[float] = [-4.0, 0.0, SILENT_DB]
const MIX_BATTLE_LATE: Array[float] = [-10.0, -4.0, 0.0]
const MIX_RESPAWN: Array[float] = [-6.0, -10.0, -24.0]
const MIX_TERMINAL: Array[float] = [SILENT_DB, SILENT_DB, SILENT_DB]

## Los stings, por id.
const STINGS: Dictionary[StringName, String] = {
	&"victory": "%s/sting_victory.wav" % MUSIC_DIR,
	&"defeat": "%s/sting_defeat.wav" % MUSIC_DIR,
}

## Si el director escucha el bus. Un check puede apagarlo para manejarlo a mano.
@export var listen_to_events: bool = true

## Si arranca sonando al entrar al árbol.
@export var autostart: bool = true

## Si la intensidad se calcula sola a partir de la distancia y el daño. Apagarlo
## deja mandando a [method set_intensity], que es lo que hace `audio_check` para
## medir el recorrido completo sin depender de dónde esté el jefe.
@export var auto_intensity: bool = true

var _sync: AudioStreamSynchronized = null
var _sting_player: AudioStreamPlayer = null
var _base_db: PackedFloat32Array = PackedFloat32Array()
var _intensity: float = 0.5
var _intensity_db: float = 0.0
var _state: int = Global.RoundState.INTRO
var _phase: StringName = &""
var _down: bool = false
var _mix_tween: Tween = null
var _damage_heat: float = 0.0
var _proximity: float = 0.0
var _distance_countdown: float = 0.0
var _boss: Node3D = null
var _drone_eye: Node3D = null


func _ready() -> void:
	bus = String(BUS)
	_build()
	if listen_to_events:
		_connect_events()
	if autostart and _sync != null:
		play()


## Igual que el [AudioPool]: al salir del árbol se cortan los cruces y la música.
func _exit_tree() -> void:
	_disconnect_events()
	if _mix_tween != null and _mix_tween.is_valid():
		_mix_tween.kill()
	if _sting_player != null and is_instance_valid(_sting_player):
		_sting_player.stop()
	stop()


# --------------------------------------------------------------------------
# Interfaz pública (`docs/13` §8)
# --------------------------------------------------------------------------

## Cambia el estado de ronda y cruza a la fila que corresponda.
func set_round_state(state: int) -> void:
	_state = state
	if state == Global.RoundState.BATTLE:
		# Volver a `BATTLE` es volver a jugar: el dron ya no está caído.
		_down = false
	_refresh()
	if state == Global.RoundState.VICTORY:
		play_sting(&"victory")
	elif state == Global.RoundState.DEFEAT:
		play_sting(&"defeat")


## Fija la fase del jefe. Recibe el `phase_id` de `Events.enemy_phase_changed`,
## que es una cadena estable de `docs/07`, no un entero.
func set_phase(phase_id: StringName) -> void:
	_phase = phase_id
	_refresh()


## Intensidad continua de 0 a 1 dentro de `BATTLE`: mueve `tension`
## ±[constant INTENSITY_RANGE_DB] dB sin cambiar de capa.
##
## Fija el **objetivo**; la rampa de [method _process] lo alcanza a
## [constant INTENSITY_SLEW_DB_PER_SECOND]. Con [member auto_intensity] encendido,
## el cálculo automático lo vuelve a escribir en el muestreo siguiente.
func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)


## Objetivo de desvío en dB al que apunta la rampa.
func intensity_target_db() -> float:
	return (_intensity * 2.0 - 1.0) * INTENSITY_RANGE_DB


## Desvío de intensidad aplicado ahora mismo, en dB. Lo mira `audio_check`.
func intensity_db() -> float:
	return _intensity_db


## Las dos mitades de la fórmula, para el check y para depurar: cercanía al jefe y
## calor del daño reciente, las dos de 0 a 1.
func intensity_terms() -> Vector2:
	return Vector2(_proximity, _damage_heat)


## Calcula la intensidad y la aplica con una rampa acotada.
##
## Todo lo que respira va acá y no en un [Tween]: un tween por muestreo serían dos
## objetos por segundo durante toda la ronda, y la rampa por acumulador da además
## el límite de pendiente que el check exige.
func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	# El calor del daño decae linealmente hasta apagarse a los 5 s del último golpe.
	if _damage_heat > 0.0:
		_damage_heat = maxf(_damage_heat - delta / DAMAGE_MEMORY_SECONDS, 0.0)
	if auto_intensity:
		_distance_countdown -= delta
		if _distance_countdown <= 0.0:
			_distance_countdown = 1.0 / DISTANCE_SAMPLE_HZ
			_sample_proximity()
		# Fuera del combate la música no respira: vuelve a desvío 0.
		set_intensity(0.5 * _proximity + 0.5 * _damage_heat \
				if _state == Global.RoundState.BATTLE else 0.5)
	var previous := _intensity_db
	_intensity_db = move_toward(_intensity_db, intensity_target_db(),
			INTENSITY_SLEW_DB_PER_SECOND * delta)
	if not is_equal_approx(previous, _intensity_db):
		_write(STEM_TENSION)


## Mide la cercanía al jefe. Tolera que falte cualquiera de los dos extremos: sin
## jefe —todavía no apareció, o ya cayó— o sin dron —reconstruyéndose— la cercanía
## es 0 y la música se apoya solo en el daño reciente.
func _sample_proximity() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	if _boss == null or not is_instance_valid(_boss):
		_boss = tree.get_first_node_in_group(ENEMY_GROUP) as Node3D
	if _drone_eye == null or not is_instance_valid(_drone_eye):
		# La cámara del dron es el único nodo del rig con grupo propio, y además es
		# el oyente: «qué tan cerca está el jefe» y «qué tan cerca suena» son la
		# misma pregunta.
		_drone_eye = tree.get_first_node_in_group(DRONE_EYE_GROUP) as Node3D
		if _drone_eye == null:
			_drone_eye = get_viewport().get_camera_3d() if get_viewport() != null else null
	if _boss == null or _drone_eye == null:
		_proximity = 0.0
		return
	var distance := _boss.global_position.distance_to(_drone_eye.global_position)
	_proximity = clampf((DISTANCE_FAR - distance) / (DISTANCE_FAR - DISTANCE_NEAR), 0.0, 1.0)


## Intensidad vigente.
func intensity() -> float:
	return _intensity


## Dispara un sting en el reproductor aparte: `victory` o `defeat`.
func play_sting(id: StringName) -> void:
	if _sting_player == null:
		return
	var path := String(STINGS.get(id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_sting_player.stream = ResourceLoader.load(path, "AudioStream") as AudioStream
	if _sting_player.stream == null:
		return
	_sting_player.play()


## Volumen efectivo de un stem, en dB: su valor de la tabla más el desvío de
## intensidad, que se desvanece junto con la capa (ver la nota de arriba).
func stem_volume_db(index: int) -> float:
	if index < 0 or index >= _base_db.size():
		return SILENT_DB
	var base := _base_db[index]
	if index != STEM_TENSION or is_zero_approx(_intensity_db):
		return base
	var audible := clampf((base - SILENT_DB) / INTENSITY_FADE_DB, 0.0, 1.0)
	return base + _intensity_db * audible


## Volumen que el recurso tiene escrito ahora mismo. Es la lectura de vuelta que
## usa `audio_check` para comprobar que el camino de escritura funciona de verdad.
func stem_stream_volume_db(index: int) -> float:
	if _sync == null or index < 0 or index >= _sync.stream_count:
		return SILENT_DB
	return _sync.get_sync_stream_volume(index)


## Posición de reproducción de la mezcla, en segundos. Los tres stems comparten
## reloj por construcción, así que es la de los tres.
func stem_position(_index: int) -> float:
	return get_playback_position()


## Largo de cada stem, en segundos, o 0 si falta.
func stem_length(index: int) -> float:
	if _sync == null or index < 0 or index >= _sync.stream_count:
		return 0.0
	var stream := _sync.get_sync_stream(index)
	return stream.get_length() if stream != null else 0.0


## Los tres stems cargados; sirve para verificar que midan lo mismo.
func stem_count() -> int:
	return _sync.stream_count if _sync != null else 0


## `true` si el sting está sonando.
func is_sting_playing() -> bool:
	return _sting_player != null and _sting_player.playing


# --------------------------------------------------------------------------
# Construcción
# --------------------------------------------------------------------------

## Arma el [AudioStreamSynchronized] con los tres stems y el reproductor de
## stings, y deja la mezcla en la fila de `INTRO` **sin cruce**: el primer valor
## no se funde desde nada.
func _build() -> void:
	_base_db.resize(STEMS.size())
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = STEMS.size()
	var missing := PackedStringArray()
	for index: int in STEMS.size():
		var path := "%s/%s.wav" % [MUSIC_DIR, String(STEMS[index])]
		if not ResourceLoader.exists(path):
			missing.append(path)
			continue
		_sync.set_sync_stream(index, ResourceLoader.load(path, "AudioStream") as AudioStream)
	if not missing.is_empty():
		push_warning("MusicDirector: faltan stems (%s); regeneralos con tools/generate_music.gd"
				% ", ".join(missing))
		_sync = null
		return
	stream = _sync

	_sting_player = AudioStreamPlayer.new()
	_sting_player.name = "Sting"
	_sting_player.bus = String(BUS)
	add_child(_sting_player)

	for index: int in STEMS.size():
		_base_db[index] = MIX_INTRO[index]
		_write(index)


func _connect_events() -> void:
	var _state_changed := Events.round_state_changed.connect(_on_round_state_changed)
	var _phase_changed := Events.enemy_phase_changed.connect(_on_phase_changed)
	var _destroyed := Events.drone_destroyed.connect(_on_drone_destroyed)
	var _respawned := Events.drone_respawned.connect(_on_drone_respawned)
	var _damaged := Events.drone_damaged.connect(_on_drone_damaged)


func _disconnect_events() -> void:
	if Events.round_state_changed.is_connected(_on_round_state_changed):
		Events.round_state_changed.disconnect(_on_round_state_changed)
	if Events.enemy_phase_changed.is_connected(_on_phase_changed):
		Events.enemy_phase_changed.disconnect(_on_phase_changed)
	if Events.drone_destroyed.is_connected(_on_drone_destroyed):
		Events.drone_destroyed.disconnect(_on_drone_destroyed)
	if Events.drone_respawned.is_connected(_on_drone_respawned):
		Events.drone_respawned.disconnect(_on_drone_respawned)
	if Events.drone_damaged.is_connected(_on_drone_damaged):
		Events.drone_damaged.disconnect(_on_drone_damaged)


# --------------------------------------------------------------------------
# Mezcla
# --------------------------------------------------------------------------

## Fila de la tabla que corresponde al estado, la fase y si el dron está caído.
func target_mix() -> Array[float]:
	match _state:
		Global.RoundState.VICTORY, Global.RoundState.DEFEAT:
			return MIX_TERMINAL
		Global.RoundState.BATTLE:
			if _down:
				return MIX_RESPAWN
			return MIX_BATTLE_LATE if COMBAT_PHASES.has(_phase) else MIX_BATTLE_EARLY
	return MIX_INTRO


## Cruza a la fila vigente con un [Tween] de [constant CROSSFADE_SECONDS].
##
## Un solo tween en paralelo para los tres stems: al matarlo y rehacerlo, un
## cambio de fase en mitad de un cruce **sale del valor actual**, no del de la
## tabla anterior, así que no hay escalones.
func _refresh() -> void:
	if _sync == null:
		return
	var target := target_mix()
	var moving: Array[int] = []
	for index: int in STEMS.size():
		if not is_equal_approx(_base_db[index], target[index]):
			moving.append(index)
	if _mix_tween != null and _mix_tween.is_valid():
		_mix_tween.kill()
	# Un [Tween] sin tweeners es un error en tiempo de ejecución, y volver a pedir
	# la fila que ya está puesta es lo más común del mundo: `BATTLE` llega una vez
	# por ronda pero `set_phase()` puede llegar en cada cambio de fase del jefe.
	if moving.is_empty():
		return
	_mix_tween = create_tween()
	var _parallel := _mix_tween.set_parallel(true)
	for index: int in moving:
		var _fade := _mix_tween.tween_method(_set_base_db.bind(index), _base_db[index],
				target[index], CROSSFADE_SECONDS)


func _set_base_db(db: float, index: int) -> void:
	_base_db[index] = db
	_write(index)


## Vuelca el volumen efectivo de un stem al recurso.
func _write(index: int) -> void:
	if _sync == null or index < 0 or index >= _sync.stream_count:
		return
	_sync.set_sync_stream_volume(index, stem_volume_db(index))


# --------------------------------------------------------------------------
# Bus de eventos
# --------------------------------------------------------------------------

func _on_round_state_changed(state: int) -> void:
	set_round_state(state)


## La fase manda sobre la música, venga de donde venga: el `phase_id` decide, y si
## no está en la tabla se le pregunta al enemigo por su `music_stem()`, que es lo
## que `EnemyBase` ya calcula desde su perfil.
func _on_phase_changed(enemy: Node3D, phase_id: StringName) -> void:
	if COMBAT_PHASES.has(phase_id):
		set_phase(phase_id)
		return
	if enemy != null and is_instance_valid(enemy) and enemy.has_method(&"music_stem"):
		var stem := enemy.call(&"music_stem") as StringName
		if stem == &"combat":
			# La fase no está en la tabla pero el perfil pide combate: manda el
			# perfil. Es el caso de un enemigo nuevo con otros nombres de fase.
			set_phase(COMBAT_PHASES[0])
			return
	set_phase(phase_id)


## El daño se acumula y decae; dos golpes seguidos pesan más que uno.
func _on_drone_damaged(amount: float, _source_position: Vector3) -> void:
	_damage_heat = clampf(_damage_heat + maxf(amount, 0.0) / DAMAGE_FULL_HP, 0.0, 1.0)


func _on_drone_destroyed(_position: Vector3) -> void:
	_down = true
	# Muerto no hay pelea que acompañar: el calor se va con el dron.
	_damage_heat = 0.0
	_refresh()


func _on_drone_respawned(_score_multiplier: float) -> void:
	_down = false
	_refresh()
