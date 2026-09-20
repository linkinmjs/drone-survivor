## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Banco de sonido de un enemigo (`docs/06` §12, `docs/07` §10). Reemplaza al
## placeholder de WP-16.
##
## Es un pool de [constant POOL_SIZE] `AudioStreamPlayer3D` reciclados por
## prioridad más un canal de loop para los servos, todos sobre el bus `Enemies`,
## con `ATTENUATION_INVERSE_SQUARE_DISTANCE` y `unit_size` de 45 a 70 m según el
## evento: el jefe se tiene que oír desde 150 m.
##
## [b]Presupuesto de voces[/b]: [constant MAX_VOICES] (8) para el jefe entero.
## De esas, este nodo usa como mucho [constant POOL_SIZE] + 1; la octava es el
## reproductor de carga del [Telegraph], que es el segundo canal de loop de
## `docs/06` §12 y vive allí porque el aviso lo enciende y lo apaga con sus otros
## dos canales.
##
## [b]Cableado automático[/b]: el rig no espera que nadie lo llame para lo que ya
## viaja por señales (`docs/07` §10). Se engancha solo a
## [signal ProceduralLegRig.foot_planted] para las pisadas, a
## `Events.enemy_part_broken` y a `WeakPoint.destroyed` de las rodillas para las
## roturas, y a `Events.enemy_phase_changed` para el acorde de fase —siempre
## filtrando por su propio enemigo, porque el bus es global—. Las cargas de
## ataque las dispara el [Telegraph] y los eventos sueltos, la acción.
##
## [b]Sonidos[/b]: los sintetiza `tools/generate_enemy_sounds.gd` en
## `assets/audio/enemies/*.wav`, PCM sin comprimir y deterministas. Un evento sin
## archivo no rompe nada: [method play] no hace ruido y devuelve `null`.
class_name AudioRig extends Node3D

## Bus de audio de los enemigos (`docs/07` §10).
const BUS: StringName = &"Enemies"

## Carpeta del banco.
const BANK_DIR: String = "res://assets/audio/enemies"

## Voces simultáneas de todo el jefe (`docs/07` §10).
const MAX_VOICES: int = 8

## Reproductores de un disparo del pool.
const POOL_SIZE: int = 6

## Variantes de pisada que se alternan (`docs/07` §10).
const FOOTSTEP_VARIANTS: int = 4

## Velocidad de impacto a la que la pisada suena a pleno volumen, en m/s.
const FOOTSTEP_REFERENCE_SPEED: float = 14.0

## Atenuación mínima de una pisada suave, en dB.
const FOOTSTEP_MIN_DB: float = -14.0

## Velocidad angular del cuerpo por encima de la cual suena el loop de servos,
## en grados por segundo (`docs/07` §10, `servo_loop`).
const SERVO_THRESHOLD: float = 2.0

## Velocidad angular a la que el loop de servos llega a su máximo, en °/s.
const SERVO_REFERENCE: float = 25.0

## Rango de volumen del loop de servos, en dB.
const SERVO_DB_RANGE: Vector2 = Vector2(-24.0, -6.0)

## Rango de tono del loop de servos.
const SERVO_PITCH_RANGE: Vector2 = Vector2(0.80, 1.35)

## Ritmo con el que el loop de servos sigue a la carga, en s⁻¹.
const SERVO_SMOOTH: float = 6.0

## `unit_size` por evento, en metros. Lo que se tiene que oír de lejos —las
## cargas y las fases— lleva 70; lo doméstico, 45 (`docs/07` §10).
const UNIT_SIZES: Dictionary[StringName, float] = {
	&"footstep": 65.0,
	&"servo_loop": 45.0,
	&"part_break": 55.0,
	&"leg_tear": 70.0,
	&"phase_shift": 70.0,
	&"selfdestruct_tick": 70.0,
	&"emp_burst": 70.0,
}

## Prioridad por evento: cuando el pool está lleno, un evento sólo desaloja a
## otro de prioridad estrictamente menor. Las pisadas son lo primero que se cae.
const PRIORITIES: Dictionary[StringName, int] = {
	&"footstep": 0,
	&"part_break": 2,
	&"emp_burst": 3,
	&"leg_tear": 3,
	&"selfdestruct_tick": 3,
	&"phase_shift": 4,
}

## `unit_size` de un evento que no aparezca en [constant UNIT_SIZES].
const DEFAULT_UNIT_SIZE: float = 60.0

## El banco completo de `docs/07` §10, que [method _ready] **precarga**.
##
## Cargar un WAV la primera vez que suena es un tirón: la primera pisada del
## combate costaba más que todo el tick de física. Son 19 archivos PCM cortos,
## así que entran de una vez al instanciar al jefe y no vuelven a tocar disco.
const BANK: PackedStringArray = [
	"charge", "charge_climb", "charge_stomp", "charge_leg_sweep",
	"charge_head_laser", "charge_siege_beam", "charge_emp_pulse", "charge_pounce",
	"charge_shake_off", "emp_burst", "footstep_1", "footstep_2", "footstep_3",
	"footstep_4", "servo_loop", "leg_tear", "part_break", "phase_shift",
	"selfdestruct_tick",
]

## Enemigo dueño. Si queda vacío se toma el padre.
@export var enemy: Node3D = null

## Si el rig emite sonido. Un check headless puede apagarlo sin tocar el bus.
@export var audio_enabled: bool = true

var _pool: Array[AudioStreamPlayer3D] = []
var _priorities: Array[int] = []
var _servo: AudioStreamPlayer3D = null
var _streams: Dictionary[StringName, AudioStream] = {}
var _events: Dictionary[StringName, int] = {}
var _footstep_cursor: int = 0
var _servo_load: float = 0.0
var _servo_target: float = 0.0
var _last_yaw: float = 0.0
var _has_yaw: bool = false
var _wired: bool = false
var _played: int = 0


func _ready() -> void:
	if enemy == null:
		enemy = get_parent() as Node3D
	for event: String in BANK:
		var _stream := _stream_for(StringName(event))
	_build_pool()


## Mide la carga de servos y suaviza el loop. Acumulador y derivada del rumbo del
## cuerpo; nunca un [Timer].
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	if not _wired:
		_wire()
	_measure_servo(delta)
	_servo_load = lerpf(_servo_load, _servo_target, 1.0 - exp(-SERVO_SMOOTH * delta))
	_apply_servo()


func _exit_tree() -> void:
	_unwire()


# --------------------------------------------------------------------------
# Interfaz pública (`docs/06` §12)
# --------------------------------------------------------------------------

## Dispara el evento [param event] del banco en la posición del enemigo (o en
## [param at] si se pasa). Devuelve el reproductor que se llevó la voz, o `null`
## si el evento no tiene sonido o el pool estaba ocupado con algo más urgente.
func play(event: StringName, at: Vector3 = Vector3.INF, volume_db: float = 0.0,
		pitch: float = 1.0) -> AudioStreamPlayer3D:
	if not audio_enabled:
		return null
	var stream := _stream_for(event)
	if stream == null:
		return null
	var player := _acquire(_priority_of(event))
	if player == null:
		return null
	player.stream = stream
	player.unit_size = UNIT_SIZES.get(_family(event), DEFAULT_UNIT_SIZE)
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch, 0.01)
	player.global_position = at if at != Vector3.INF else _origin()
	player.play()
	_played += 1
	_events[event] = int(_events.get(event, 0)) + 1
	return player


## Dispara la pisada que toca, alternando las cuatro variantes y escalando el
## volumen con [param impact_speed] (`docs/07` §10).
func play_footstep(at: Vector3, impact_speed: float) -> void:
	var variant := _footstep_cursor % FOOTSTEP_VARIANTS + 1
	_footstep_cursor += 1
	var ratio := clampf(impact_speed / FOOTSTEP_REFERENCE_SPEED, 0.0, 1.0)
	var _player := play(StringName("footstep_%d" % variant), at,
			lerpf(FOOTSTEP_MIN_DB, 0.0, ratio))


## Modula el loop de servos: [param load] de 0 a 1 mueve volumen y tono
## (`docs/07` §10). Con 0 el loop se apaga.
func set_servo_load(load: float) -> void:
	_servo_target = clampf(load, 0.0, 1.0)


## Carga de servos vigente, ya suavizada.
func servo_load() -> float:
	return _servo_load


## Voces de este rig sonando ahora mismo. El presupuesto de `docs/07` §10 es
## [constant MAX_VOICES] contando además la carga del [Telegraph].
func active_voices() -> int:
	var count := 0
	for player: AudioStreamPlayer3D in _pool:
		if player.playing:
			count += 1
	if _servo != null and _servo.playing:
		count += 1
	return count


## Eventos disparados desde el arranque, por id. Lo usa `arachnodroid_check`.
func event_counts() -> Dictionary[StringName, int]:
	return _events


## Total de eventos disparados.
func played_count() -> int:
	return _played


## `true` si [param event] tiene sonido en el banco.
func has_event(event: StringName) -> bool:
	return _stream_for(event) != null


## Corta todas las voces, loop incluido.
func stop_all() -> void:
	for player: AudioStreamPlayer3D in _pool:
		player.stop()
	if _servo != null:
		_servo.stop()
	_servo_load = 0.0
	_servo_target = 0.0


# --------------------------------------------------------------------------
# Pool
# --------------------------------------------------------------------------

## Crea el pool de un disparo y el canal de loop de servos.
func _build_pool() -> void:
	for index: int in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "Voice%d" % index
		_configure(player)
		add_child(player)
		_pool.append(player)
		_priorities.append(-1)

	_servo = AudioStreamPlayer3D.new()
	_servo.name = "ServoLoop"
	_configure(_servo)
	_servo.unit_size = UNIT_SIZES.get(&"servo_loop", DEFAULT_UNIT_SIZE)
	_servo.volume_db = SERVO_DB_RANGE.x
	add_child(_servo)
	_servo.stream = _stream_for(&"servo_loop")


## Deja un reproductor con los ajustes espaciales de `docs/07` §10.
func _configure(player: AudioStreamPlayer3D) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.unit_size = DEFAULT_UNIT_SIZE
	player.max_distance = 0.0
	player.top_level = true
	if AudioServer.get_bus_index(String(BUS)) >= 0:
		player.bus = String(BUS)


## Toma una voz libre, o desaloja la de menor prioridad si [param priority] la
## supera. Devuelve `null` si nada es desalojable.
func _acquire(priority: int) -> AudioStreamPlayer3D:
	for index: int in _pool.size():
		if not _pool[index].playing:
			_priorities[index] = priority
			return _pool[index]
	var worst := -1
	var worst_priority := priority
	for index: int in _pool.size():
		if _priorities[index] < worst_priority:
			worst_priority = _priorities[index]
			worst = index
	if worst < 0:
		return null
	_pool[worst].stop()
	_priorities[worst] = priority
	return _pool[worst]


## Prioridad del evento, deducida de su familia.
func _priority_of(event: StringName) -> int:
	return int(PRIORITIES.get(_family(event), 1))


## Familia de un evento: `footstep_3` es `footstep`, `charge_stomp` es `charge`.
func _family(event: StringName) -> StringName:
	var text := String(event)
	if text.begins_with("footstep"):
		return &"footstep"
	if text.begins_with("charge"):
		return &"charge"
	return event


## Carga (y cachea) el sonido de [param event].
func _stream_for(event: StringName) -> AudioStream:
	if _streams.has(event):
		return _streams[event]
	var path := "%s/%s.wav" % [BANK_DIR, event]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = ResourceLoader.load(path, "AudioStream") as AudioStream
	_streams[event] = stream
	return stream


## Posición desde la que suena el rig: la del enemigo.
func _origin() -> Vector3:
	if enemy != null and is_instance_valid(enemy):
		return enemy.global_position
	return global_position


# --------------------------------------------------------------------------
# Servos
# --------------------------------------------------------------------------

## Mide la velocidad angular del cuerpo y la convierte en carga de servos.
##
## El rumbo sale del eje frontal de la base, no de `rotation.y`: con el cuerpo
## inclinado en una rampa la descomposición de Euler pega saltos y el loop
## chirriaría sin que el jefe gire (mismo criterio que
## `ProceduralLegRig._track_yaw`).
func _measure_servo(delta: float) -> void:
	var body := enemy if enemy != null else self
	var forward := -body.global_basis.z
	if absf(forward.x) < 0.000001 and absf(forward.z) < 0.000001:
		return
	var yaw := atan2(-forward.x, -forward.z)
	if not _has_yaw:
		_last_yaw = yaw
		_has_yaw = true
		return
	var rate := absf(rad_to_deg(wrapf(yaw - _last_yaw, -PI, PI)) / delta)
	_last_yaw = yaw
	if rate <= SERVO_THRESHOLD:
		set_servo_load(0.0)
		return
	set_servo_load((rate - SERVO_THRESHOLD) / maxf(SERVO_REFERENCE - SERVO_THRESHOLD, 0.01))


## Traduce la carga a volumen, tono y encendido del loop.
func _apply_servo() -> void:
	if _servo == null or _servo.stream == null:
		return
	if not audio_enabled or _servo_load <= 0.01:
		if _servo.playing:
			_servo.stop()
		return
	_servo.global_position = _origin()
	_servo.volume_db = lerpf(SERVO_DB_RANGE.x, SERVO_DB_RANGE.y, _servo_load)
	_servo.pitch_scale = lerpf(SERVO_PITCH_RANGE.x, SERVO_PITCH_RANGE.y, _servo_load)
	if not _servo.playing:
		_servo.play()


# --------------------------------------------------------------------------
# Cableado por señales (`docs/07` §10)
# --------------------------------------------------------------------------

## Se engancha a las señales del enemigo. Perezoso: el `_ready()` de este nodo
## corre **antes** que el de [EnemyBase], que es quien construye las partes y los
## puntos débiles.
func _wire() -> void:
	if enemy == null or not enemy.has_method(&"get_weak_points"):
		return
	var rig := enemy.get(&"locomotion") as ProceduralLegRig
	if rig != null and not rig.foot_planted.is_connected(_on_foot_planted):
		var _steps := rig.foot_planted.connect(_on_foot_planted)
	for weak_point: WeakPoint in enemy.call(&"get_weak_points") as Array[WeakPoint]:
		if not weak_point.destroyed.is_connected(_on_weak_point_destroyed):
			var _torn := weak_point.destroyed.connect(_on_weak_point_destroyed)
	if not Events.enemy_part_broken.is_connected(_on_part_broken):
		var _broke := Events.enemy_part_broken.connect(_on_part_broken)
	if not Events.enemy_phase_changed.is_connected(_on_phase_changed):
		var _phase := Events.enemy_phase_changed.connect(_on_phase_changed)
	_wired = true


## Suelta las conexiones globales. El bus vive más que el enemigo.
func _unwire() -> void:
	if Events.enemy_part_broken.is_connected(_on_part_broken):
		Events.enemy_part_broken.disconnect(_on_part_broken)
	if Events.enemy_phase_changed.is_connected(_on_phase_changed):
		Events.enemy_phase_changed.disconnect(_on_phase_changed)


func _on_foot_planted(_leg_index: int, position: Vector3, impact_speed: float) -> void:
	play_footstep(position, impact_speed)


## Una rodilla rota es un desgarro; el resto de los puntos débiles se conforma
## con la fractura de `part_break` que ya emite el bus (`docs/07` §10).
func _on_weak_point_destroyed(weak_point_id: StringName) -> void:
	if not String(weak_point_id).ends_with("_knee"):
		return
	var _player := play(&"leg_tear")


func _on_part_broken(source: Node3D, _part_id: StringName, position: Vector3) -> void:
	if source != enemy:
		return
	var _player := play(&"part_break", position)


func _on_phase_changed(source: Node3D, _phase_id: StringName) -> void:
	if source != enemy:
		return
	var _player := play(&"phase_shift")
