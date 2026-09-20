## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Audio de los cuatro motores del dron (`docs/03` §6).
##
## Cuelga del [Drone] y no sabe nada de vuelo: cada frame de física lee el régimen
## de cada [DroneMotor] y lo traduce a volumen y tono. Los ocho loops de
## `assets/audio/motors/` los sintetiza `tools/generate_motor_sounds.gd`.
##
## **Ocho reproductores, dos por motor.** Cada motor suena con las **dos bandas de
## régimen adyacentes** a su rpm, mezcladas con un crossfade de potencia constante.
## Los reproductores son [AudioStreamPlayer] —no posicionales— porque el oyente va
## montado en el propio dron: espacializar los motores propios solo agregaría paneo
## y atenuación sobre algo que está siempre a 5 cm del micrófono. Los ocho van al
## bus [constant BUS], que es donde el menú de audio aplica el deslizador «Motores»
## (`docs/04` §3.2).
##
## **Cómo se reparte el volumen.** Hay dos factores y se aplican en sitios
## distintos, que es lo que hace que esto no chasquee:
##
## - La **envolvente del motor**, `lerp(−24 dB, 0 dB, régimen)` con desvanecido a
##   [constant SILENT_DB] por debajo del ralentí, es la única magnitud que puede
##   pegar un salto —el régimen sí los pega— y por eso es la única que pasa por un
##   limitador de pendiente ([constant SLEW_DB_PER_SECOND]): ningún frame la mueve
##   más de 3 dB a los 100 Hz de física del proyecto.
## - El **reparto entre las dos bandas** se aplica en crudo, sin limitar, porque ya
##   es continuo por construcción: `cos`/`sin` de la posición dentro de la banda,
##   suavizada con `smoothstep`. Limitarlo sería contraproducente —haría que la voz
##   entrante llegara tarde a su volumen— y no hace falta.
##
## Como el crossfade es de potencia constante (`cos² + sin² = 1`) y las dos bandas
## son loops distintos —no correlacionados—, la **potencia combinada** de las dos
## voces de un motor es exactamente su envolvente: el cruce de bandas no se oye ni
## como un bache ni como un pico. Es lo que miden `flight_check` §11.7 y
## `audio_check` con [method get_motor_volume_db].
##
## **Cómo se evita el otro clic.** El de cortar un `play()` por la mitad. Un cambio
## de banda **nunca** reinicia un reproductor que se esté oyendo: la banda nueva se
## le da al que ya está en [constant SILENT_DB], que siempre aparece un frame
## después de cruzar el borde, porque el crossfade deja al saliente en silencio
## antes. Si ninguno está callado —un salto brusco de régimen— el cambio espera al
## frame siguiente y ese motor suena 10 ms con una sola banda.
##
## **Cuerpo congelado: el régimen deja de ser un dato.** `RigidBody3D.freeze`
## apaga [method Drone._integrate_forces], que es el único sitio donde corre
## [method DroneMotor.step]: con el dron congelado —la reconstrucción de
## `docs/09` §2.8 y la tarjeta de VICTORY/DEFEAT de `docs/11` §6.3 lo congelan— las
## rpm quedan clavadas en las del último cuadro vivo y la envolvente se quedaría
## sonando para siempre. Por eso [method _is_cut] trata el cuerpo congelado como
## **régimen cero**: la envolvente baja a [constant SILENT_DB] por el limitador de
## pendiente de siempre —0,27 s desde el máximo, sin clic— y [method _stop] corta
## los ocho loops. No se toca [member enabled]: el audio vuelve solo en cuanto el
## cuerpo se descongela y el dron se arma, sin que ningún camino de salida tenga
## que acordarse de rehabilitarlo.
##
## **Headless**: con el controlador Dummy el `AudioServer` sigue mezclando, así que
## `playing`, `volume_db`, `pitch_scale` y la posición de reproducción valen lo
## mismo que con tarjeta de sonido. Los checks se apoyan en eso.
class_name MotorAudio extends Node

## Bus al que van los ocho reproductores (`docs/04` §3.2, `docs/13` §5.1).
const BUS: StringName = &"Motors"

## Carpeta de los loops sintetizados.
const STREAM_DIR: String = "res://assets/audio/motors"

## Fracción de `max_rpm` de cada banda (`docs/03` §6). Tiene que coincidir con la
## de `tools/generate_motor_sounds.gd`.
const BAND_RATIOS: Array[float] = [0.05, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 1.0]

## Nombre del archivo de cada banda, en el mismo orden que [constant BAND_RATIOS].
const BAND_NAMES: Array[String] = ["idle", "band_1", "band_2", "band_3",
		"band_4", "band_5", "band_6", "band_7"]

## Reproductores por motor: las dos bandas adyacentes al régimen.
const VOICES_PER_MOTOR: int = 2

## Volumen del motor en ralentí y a fondo, en dB (`docs/03` §6). Interpolar en
## **decibeles** es justamente la «curva exponencial» de §6: en amplitud lineal el
## recorrido de −24 a 0 dB es una exponencial, que es como el oído mide el volumen.
const MIN_VOLUME_DB: float = -24.0
const MAX_VOLUME_DB: float = 0.0

## Silencio efectivo, en dB. Es el suelo de todos los volúmenes: `-inf` no es un
## valor válido para `AudioServer` y complicaría el limitador de pendiente.
const SILENT_DB: float = -80.0

## Límites del `pitch_scale` (`docs/03` §6). Fuera de ellos el resampleo empieza a
## notarse como un efecto y no como un motor.
const PITCH_LIMITS: Vector2 = Vector2(0.8, 1.25)

## Pendiente máxima de la envolvente de un motor, en dB por segundo. A los 100 Hz
## de física del proyecto son 3 dB por frame, y a 60 Hz siguen siendo 5: por debajo
## del escalón de 6 dB que `docs/03` §11.7 considera un clic.
const SLEW_DB_PER_SECOND: float = 300.0

## Margen sobre [constant SILENT_DB] por debajo del cual un reproductor se
## considera apagado y se le puede cambiar la banda sin que se oiga.
const SILENCE_MARGIN_DB: float = 0.5

## Si el rig cablea el dron a mano. Vacío, se usa el nodo padre, que es donde
## `docs/03` §8 pone este nodo.
@export var drone: Drone

## Apaga el audio de motores sin sacar el nodo del árbol. Equivale a
## [method set_enabled].
@export var enabled: bool = true:
	set = set_enabled

var _drone: Drone = null
var _motors: Array[DroneMotor] = []
var _players: Array[AudioStreamPlayer] = []
var _streams: Array[AudioStreamWAV] = []

## Banda que lleva cargada cada reproductor, en el mismo orden que [member _players].
var _bands: PackedInt32Array = PackedInt32Array()

## Envolvente vigente de cada motor, en dB. Es el estado del limitador de pendiente.
var _envelopes: PackedFloat32Array = PackedFloat32Array()

## `true` mientras los ocho reproductores están sonando (aunque sea en silencio).
var _playing: bool = false

var _built: bool = false
var _warned: bool = false


func _ready() -> void:
	_load_streams()
	_resolve_drone()
	if _drone != null:
		if not _drone.armed.is_connected(_on_armed):
			var _discard := _drone.armed.connect(_on_armed)
		if not _drone.disarmed.is_connected(_on_disarmed):
			var _discard := _drone.disarmed.connect(_on_disarmed)
	# Los motores los arma `Drone._ready()`, que corre **después** que el de sus
	# hijos: la construcción real se hace en el primer frame de física.
	var _ready_now := _build()


func _physics_process(delta: float) -> void:
	if not _build():
		return
	if not enabled:
		return
	var cut := _is_cut()
	if _drone.is_armed() and not _playing and not cut:
		_start()
	for index: int in _motors.size():
		_update_motor(index, delta, cut)
	if _playing and (cut or not _drone.is_armed()) and _is_silent():
		_stop()


## Enciende o apaga el audio de motores. Apagarlo detiene los ocho reproductores;
## encenderlo los devuelve a sonar en cuanto el dron esté armado.
func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and _playing:
		_stop()


## Reproductores que están sonando ahora mismo. Es el consumo de voces de este
## nodo frente al presupuesto de 24 de `docs/13` §5.2, y nunca pasa de
## `motores × VOICES_PER_MOTOR`.
func get_active_voice_count() -> int:
	var _ready_now := _build()
	var count := 0
	for player: AudioStreamPlayer in _players:
		if player.playing:
			count += 1
	return count


## Los ocho reproductores, en el orden `motor 1 voz A, motor 1 voz B, motor 2 voz A…`.
## Pensado para los checks; el gameplay no los toca.
func get_players() -> Array[AudioStreamPlayer]:
	var _ready_now := _build()
	return _players


## Banda que lleva cargada el reproductor [param player_index], o `−1` si el índice
## no existe.
func get_player_band(player_index: int) -> int:
	if player_index < 0 or player_index >= _bands.size():
		return -1
	return _bands[player_index]


## Volumen combinado de las dos voces de un motor, en dB.
##
## Se suman **potencias**, no amplitudes, porque las dos bandas son loops
## sintetizados por separado y no están correlacionadas: dos señales
## independientes de igual nivel suenan 3 dB más fuerte, no 6. Con el crossfade de
## potencia constante de [method _update_motor] esta cifra es exactamente la
## envolvente del motor, y cualquier apartamiento —un bache en el cruce, un salto
## de banda sin crossfade— aparece acá. Es lo que vigilan `flight_check` §11.7 y
## `audio_check`.
func get_motor_volume_db(motor_index: int) -> float:
	var _ready_now := _build()
	var first := motor_index * VOICES_PER_MOTOR
	if first < 0 or first + VOICES_PER_MOTOR > _players.size():
		return SILENT_DB
	var power := 0.0
	for offset: int in VOICES_PER_MOTOR:
		var player := _players[first + offset]
		if player.playing:
			var amplitude := db_to_linear(player.volume_db)
			power += amplitude * amplitude
	if power <= 0.0:
		return SILENT_DB
	return maxf(SILENT_DB, linear_to_db(sqrt(power)))


## Envolvente vigente de un motor, en dB: el volumen al que apunta antes de
## repartirlo entre las dos bandas. Es el valor con el que `flight_check` compara
## [method get_motor_volume_db] para medir el rizado del crossfade.
func get_motor_envelope_db(motor_index: int) -> float:
	if motor_index < 0 or motor_index >= _envelopes.size():
		return SILENT_DB
	return _envelopes[motor_index]


## Envolvente que le corresponde a un régimen dado, en dB, sin limitador de
## pendiente: `lerp(−24, 0, régimen)` y desvanecido a [constant SILENT_DB] por
## debajo del ralentí (`docs/03` §6).
func envelope_for(motor: DroneMotor) -> float:
	var max_rpm := maxf(motor.max_rpm, 1.0)
	var rpm := absf(motor.rpm)
	var envelope := lerpf(MIN_VOLUME_DB, MAX_VOLUME_DB, clampf(rpm / max_rpm, 0.0, 1.0))
	var idle_rpm := maxf(motor.idle_rpm, 1.0)
	if rpm < idle_rpm:
		envelope = lerpf(SILENT_DB, envelope, rpm / idle_rpm)
	return envelope


## Régimen en rpm al que corresponde una banda para un motor dado.
func band_rpm(motor: DroneMotor, band: int) -> float:
	return motor.max_rpm * BAND_RATIOS[clampi(band, 0, BAND_RATIOS.size() - 1)]


# --- Construcción -----------------------------------------------------------------------------


## Carga los ocho loops. Un loop que falte se reporta una sola vez: el nodo sigue
## funcionando con los que haya, y `audio_check` es quien falla por el que falta.
func _load_streams() -> void:
	_streams.clear()
	for name_key: String in BAND_NAMES:
		var path := "%s/%s.wav" % [STREAM_DIR, name_key]
		var stream: AudioStreamWAV = null
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStreamWAV
		if stream == null:
			push_error("MotorAudio: falta el loop de motor '%s'. Regeneralo con tools/generate_motor_sounds.gd."
					% path)
		_streams.append(stream)


func _resolve_drone() -> void:
	_drone = drone
	if _drone == null:
		_drone = get_parent() as Drone


## Crea los reproductores en cuanto el dron publica sus motores. Devuelve `true`
## cuando el nodo está listo para trabajar.
func _build() -> bool:
	if _built:
		return true
	_resolve_drone()
	if _drone == null:
		_warn_once("MotorAudio: no hay un Drone del que colgar (%s)." % get_path())
		return false
	var motors := _drone.get_motors()
	if motors.is_empty():
		return false
	_motors = motors
	for index: int in _motors.size():
		_envelopes.append(SILENT_DB)
		for voice: int in VOICES_PER_MOTOR:
			var player := AudioStreamPlayer.new()
			player.name = "Motor%dVoice%d" % [index + 1, voice + 1]
			player.bus = BUS
			player.volume_db = SILENT_DB
			var band := clampi(voice, 0, _streams.size() - 1)
			player.stream = _streams[band]
			add_child(player)
			_players.append(player)
			_bands.append(band)
	_built = true
	return true


func _warn_once(message: String) -> void:
	if _warned:
		return
	_warned = true
	push_warning(message)


# --- Bucle ------------------------------------------------------------------------------------


## Actualiza las dos voces de un motor: reparte las bandas, y fija volumen y tono.
##
## Con [param cut] la envolvente apunta a [constant SILENT_DB] en vez de al régimen:
## el reparto entre bandas y el `pitch_scale` se siguen calculando con las rpm
## clavadas, pero a −80 dB no se oyen y el estado queda coherente para cuando el
## dron vuelva a volar.
func _update_motor(index: int, delta: float, cut: bool) -> void:
	var motor := _motors[index]
	var max_rpm := maxf(motor.max_rpm, 1.0)
	var rpm := absf(motor.rpm)
	var ratio := clampf(rpm / max_rpm, 0.0, 1.0)
	var low := _band_index(ratio)
	var high := low + 1
	# `smoothstep` aplana el cruce en los dos extremos: la voz saliente llega a cero
	# **antes** del borde de la banda, así que al frame siguiente ya se le puede
	# cambiar el loop sin que nadie lo oiga.
	var blend := smoothstep(0.0, 1.0, _band_blend(ratio, low))

	var target := SILENT_DB if cut else envelope_for(motor)
	_envelopes[index] = move_toward(_envelopes[index], target, SLEW_DB_PER_SECOND * delta)
	var envelope := _envelopes[index]

	var first := index * VOICES_PER_MOTOR
	_claim_bands(first, low, high)
	for offset: int in VOICES_PER_MOTOR:
		var slot := first + offset
		var band := _bands[slot]
		# Crossfade de potencia constante: `cos² + sin² = 1`, así que la potencia de
		# la suma de dos loops no correlacionados no se hunde en mitad del cruce.
		var gain := 0.0
		if band == low:
			gain = cos(blend * PI * 0.5)
		elif band == high:
			gain = sin(blend * PI * 0.5)
		var player := _players[slot]
		player.volume_db = SILENT_DB if gain <= 0.0 \
				else maxf(SILENT_DB, envelope + linear_to_db(gain))
		var reference := band_rpm(motor, band)
		if reference > 0.0:
			player.pitch_scale = clampf(rpm / reference, PITCH_LIMITS.x, PITCH_LIMITS.y)


## Da las bandas [param low] y [param high] a las dos voces del motor que empieza en
## [param first], moviendo solo las que ya están calladas.
func _claim_bands(first: int, low: int, high: int) -> void:
	for wanted: int in [low, high]:
		if wanted < 0 or wanted >= _streams.size():
			continue
		if _bands[first] == wanted or _bands[first + 1] == wanted:
			continue
		for offset: int in VOICES_PER_MOTOR:
			var slot := first + offset
			# No se le quita la banda a una voz que está en el crossfade…
			if _bands[slot] == low or _bands[slot] == high:
				continue
			# …ni a una que todavía se oye: se espera al frame siguiente.
			if _players[slot].volume_db > SILENT_DB + SILENCE_MARGIN_DB:
				continue
			_bands[slot] = wanted
			_load_band(slot)
			break


## Pone en un reproductor el loop de su banda. Solo se llama sobre reproductores en
## silencio, así que el corte de `play()` no se oye.
func _load_band(slot: int) -> void:
	var player := _players[slot]
	var stream := _streams[_bands[slot]]
	if stream == null:
		return
	player.volume_db = SILENT_DB
	player.stream = stream
	player.pitch_scale = 1.0
	if _playing:
		player.play(_start_offset(slot))


## Banda inferior del par que rodea a [param ratio].
func _band_index(ratio: float) -> int:
	for index: int in BAND_RATIOS.size() - 1:
		if ratio < BAND_RATIOS[index + 1]:
			return index
	return BAND_RATIOS.size() - 2


## Posición de [param ratio] dentro de la banda [param low], en `[0, 1]`.
func _band_blend(ratio: float, low: int) -> float:
	var lower := BAND_RATIOS[low]
	var upper := BAND_RATIOS[low + 1]
	if upper <= lower:
		return 0.0
	return clampf((ratio - lower) / (upper - lower), 0.0, 1.0)


# --- Reproducción -----------------------------------------------------------------------------


## Arranca los ocho loops en silencio. Cada uno entra con un desfase distinto para
## que los cuatro motores no suenen en fase, que es lo que produciría un batido.
func _start() -> void:
	_playing = true
	for index: int in _envelopes.size():
		_envelopes[index] = SILENT_DB
	for slot: int in _players.size():
		var player := _players[slot]
		player.volume_db = SILENT_DB
		if player.stream != null:
			player.play(_start_offset(slot))


func _stop() -> void:
	_playing = false
	for player: AudioStreamPlayer in _players:
		player.volume_db = SILENT_DB
		player.stop()
	for index: int in _envelopes.size():
		_envelopes[index] = SILENT_DB


## Desfase de entrada de cada reproductor dentro del loop, en segundos. Es
## determinista: los checks tienen que poder repetir la corrida.
func _start_offset(slot: int) -> float:
	var stream := _players[slot].stream
	if stream == null:
		return 0.0
	var length := stream.get_length()
	if length <= 0.0:
		return 0.0
	return length * float(slot) / float(maxi(_players.size(), 1))


## `true` cuando el régimen que llevan los motores ya no describe nada.
##
## Hoy hay un solo caso y es el cuerpo congelado: `freeze` corta
## [method Drone._integrate_forces], que es quien llama a [method DroneMotor.step],
## así que `motor.rpm` se queda en el valor del último cuadro integrado. Lo ponen la
## reconstrucción (`RespawnController._begin()`) y la tarjeta de fin de ronda
## (`RoundManager._freeze_drone()`); los dos desarman antes, así que el
## [method _stop] de [method _physics_process] llega en cuanto la envolvente toca el
## suelo. Desarmar **sin** congelar no entra acá: ahí las rpm sí caen solas con
## `tau_down` y el volumen las sigue, que es el desvanecido de siempre.
func _is_cut() -> bool:
	return _drone != null and _drone.freeze


## `true` si los ocho reproductores ya están en el suelo de volumen.
func _is_silent() -> bool:
	for player: AudioStreamPlayer in _players:
		if player.volume_db > SILENT_DB + SILENCE_MARGIN_DB:
			return false
	return true


func _on_armed(_mode_key: String) -> void:
	if not enabled or _is_cut():
		return
	if _build():
		_start()


## Al desarmar no se corta nada: los motores bajan de vueltas con su propia
## constante de tiempo y el volumen los sigue hasta el silencio; recién ahí
## [method _physics_process] para los reproductores.
func _on_disarmed() -> void:
	pass
