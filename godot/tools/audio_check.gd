## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de audio (`docs/15` §3, `docs/13` §10.3).
##
## Cubre lo que WP-07 pone sobre la mesa: los **siete buses**, el autoload [Audio]
## como único dueño de los volúmenes, los **ocho loops de motor** sintetizados y el
## [MotorAudio] del `drone_rig.tscn` con su crossfade por bandas de régimen.
##
## Lo que `docs/13` §10.3 pide y **todavía no existe** —los efectos de `Master` y
## `Music`, el `AudioPool` y los tres stems de la música por capas— es de WP-27; el
## check lo imprime como `SKIP` para que la diferencia entre «no está» y «no se
## comprueba» quede escrita, y no en silencio.
##
## Corre así:
##   godot --headless --path godot res://tools/audio_check.tscn
##
## El controlador de audio en `--headless` es el Dummy: el `AudioServer` mezcla
## igual, así que `volume_db`, `pitch_scale`, `playing` y los índices de bus valen
## lo mismo que con tarjeta de sonido. Lo único que no vale es *escuchar*, y por eso
## todos los criterios de acá son numéricos.
extends CheckRunner

## Los siete buses de `docs/04` §3.2 y `docs/13` §5.1, en orden. `Master` es el 0.
const BUSES: Array[StringName] = [&"Master", &"Motors", &"Weapons", &"Enemies",
		&"City", &"UI", &"Music"]

## Duración que `docs/03` §6 pide para cada loop, en segundos, y su tolerancia.
const LOOP_SECONDS: float = 1.5
const LOOP_TOLERANCE: float = 0.01

## Ventana admitida para el pico de cada loop, en dBFS: `docs/03` §6 los normaliza
## a −6 dBFS y acá se deja ±1 dB de margen de cuantización.
const PEAK_RANGE: Vector2 = Vector2(-7.0, -5.0)

## Frecuencia de muestreo que tienen que tener los loops, en Hz.
const MIX_RATE: int = 44100

## Presupuesto global de voces de `docs/13` §5.2.
const VOICE_BUDGET: int = 24

## Volúmenes lineales con los que se prueba `Audio.set_volume()`.
const VOLUME_PROBES: Array[float] = [1.0, 0.5, 0.25, 0.0]

## Altura del banco de régimen, en metros: el dron sube durante la rampa y no debe
## llegar al suelo.
const RAMP_ALTITUDE: float = 60.0

## Duración de la rampa de régimen, en segundos.
const RAMP_SECONDS: float = 3.0

## Salto máximo de volumen combinado entre dos frames, en dB (`docs/03` §11.7).
const MAX_JUMP_DB: float = 6.0

## Por encima de este volumen un reproductor **se oye**: cambiarle el loop ahí es un
## clic, y es lo que detecta el criterio 5.
const AUDIBLE_DB: float = -40.0

## Por encima de este volumen un reproductor **lleva el sonido** del motor. Lo que
## le pase a una voz por debajo de −30 dBFS, con la otra a 0 dB, está enmascarado.
const LOUD_DB: float = -30.0

## Salto máximo, en dB y entre dos frames, del volumen de una voz que lleva el
## sonido. Es el criterio que distingue un crossfade de un **cambio de banda a
## pelo**: sin crossfade la voz saliente pasa de la envolvente al silencio de un
## frame al otro, unos 75 dB.
const MAX_VOICE_JUMP_DB: float = 20.0

## Paso de física nominal, en segundos.
const PHYSICS_STEP: float = 0.01

## Ticks que se dejan para que el régimen y el volumen se asienten.
const SETTLE_TICKS: int = 90

@export var rig_path: NodePath = ^"DroneRig"

var _rig: DroneRig = null
var _drone: Drone = null
var _audio: MotorAudio = null
var _restore_volumes: Dictionary[StringName, float] = {}
var _restore_muted: bool = false


func _run() -> void:
	Engine.physics_ticks_per_second = 100
	for bus: StringName in Audio.BUSES:
		_restore_volumes[bus] = Audio.get_volume(bus)
	_restore_muted = Audio.muted

	_check_buses()
	_check_volume_api()
	_check_loops()
	await _check_motor_audio()
	_skip_wp27()

	# El autoload es global al proceso: se deja como estaba aunque el check falle.
	for bus: StringName in _restore_volumes:
		Audio.set_volume(bus, _restore_volumes[bus])
	Audio.set_muted(_restore_muted)


## 1 — Los siete buses existen con el nombre exacto y todos envían a `Master`.
func _check_buses() -> void:
	var count := AudioServer.get_bus_count()
	var names: Array[String] = []
	for index: int in count:
		names.append(String(AudioServer.get_bus_name(index)))
	print("  [1] buses (%d): %s" % [count, ", ".join(names)])
	expect(count == BUSES.size(),
			"el layout tiene %d buses y `docs/13` §5.1 pide %d" % [count, BUSES.size()])
	for position: int in BUSES.size():
		var wanted: StringName = BUSES[position]
		var index := AudioServer.get_bus_index(wanted)
		expect(index >= 0, "falta el bus '%s' en default_bus_layout.tres" % String(wanted))
		if index < 0:
			continue
		if wanted == &"Master":
			expect(index == 0, "'Master' está en el índice %d y tiene que ser el 0" % index)
			continue
		var send := AudioServer.get_bus_send(index)
		expect(send == &"Master",
				"el bus '%s' envía a '%s' y tiene que enviar a 'Master'"
				% [String(wanted), String(send)])
	expect(Audio.BUSES == BUSES,
			"el autoload Audio lista %s y `docs/04` §3.2 pide %s"
			% [str(Audio.BUSES), str(BUSES)])


## 2 — `Audio.set_volume()` mueve el `AudioServer`, y el 0 lineal no produce `-inf`.
func _check_volume_api() -> void:
	var index := AudioServer.get_bus_index(&"Motors")
	if index < 0:
		fail("no se puede probar Audio.set_volume(): falta el bus 'Motors'")
		return
	var line: Array[String] = []
	for linear: float in VOLUME_PROBES:
		Audio.set_volume(&"Motors", linear)
		var applied := AudioServer.get_bus_volume_db(index)
		var wanted := Audio.linear_to_volume_db(linear)
		line.append("%.2f->%.2f dB" % [linear, applied])
		expect_near(applied, wanted, 0.01,
				"Audio.set_volume(&\"Motors\", %.2f) dejó el bus en %.2f dB" % [linear, applied])
		expect(Audio.get_volume(&"Motors") == linear,
				"Audio.get_volume() devolvió %.4f tras fijar %.4f"
				% [Audio.get_volume(&"Motors"), linear])
		expect(is_finite(applied),
				"el volumen del bus quedó en %s: `linear_to_db(0)` es `-inf` y hay que acotarlo"
				% str(applied))
	print("  [2] Audio.set_volume(&\"Motors\"): %s" % ", ".join(line))
	Audio.set_volume(&"Motors", _restore_volumes.get(&"Motors", 0.8))


## 3 — Los ocho loops existen, duran 1.5 s, están en bucle hacia adelante y tienen
## el pico donde `docs/03` §6 lo deja.
func _check_loops() -> void:
	for band: int in MotorAudio.BAND_NAMES.size():
		var path := "%s/%s.wav" % [MotorAudio.STREAM_DIR, MotorAudio.BAND_NAMES[band]]
		if not ResourceLoader.exists(path):
			fail("falta el loop de motor '%s' (regeneralo con tools/generate_motor_sounds.gd)"
					% path)
			continue
		var stream := load(path) as AudioStreamWAV
		if stream == null:
			fail("'%s' no cargó como AudioStreamWAV" % path)
			continue
		var frames := _frame_count(stream)
		var peak := _peak_dbfs(stream)
		print("  [3] %-8s %.4f s · %d Hz · formato %d · bucle %d [%d, %d] · pico %.2f dBFS"
				% [MotorAudio.BAND_NAMES[band], stream.get_length(), stream.mix_rate,
				stream.format, stream.loop_mode, stream.loop_begin, stream.loop_end, peak])
		expect_near(stream.get_length(), LOOP_SECONDS, LOOP_TOLERANCE,
				"la duración de '%s'" % MotorAudio.BAND_NAMES[band])
		expect(stream.mix_rate == MIX_RATE,
				"'%s' va a %d Hz y §6 pide %d" % [MotorAudio.BAND_NAMES[band],
				stream.mix_rate, MIX_RATE])
		expect(stream.format == AudioStreamWAV.FORMAT_16_BITS,
				"'%s' no quedó en PCM de 16 bits (formato %d): revisá compress/mode en el .import"
				% [MotorAudio.BAND_NAMES[band], stream.format])
		expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
				"'%s' importó con loop_mode %d y §6 pide LOOP_FORWARD (edit/loop_mode=2)"
				% [MotorAudio.BAND_NAMES[band], stream.loop_mode])
		expect(stream.loop_begin == 0 and stream.loop_end == frames,
				"'%s' tiene el bucle en [%d, %d] y tiene que cubrir las %d muestras"
				% [MotorAudio.BAND_NAMES[band], stream.loop_begin, stream.loop_end, frames])
		expect(peak >= PEAK_RANGE.x and peak <= PEAK_RANGE.y,
				"el pico de '%s' es %.2f dBFS y §6 lo normaliza a −6 (ventana [%.0f, %.0f])"
				% [MotorAudio.BAND_NAMES[band], peak, PEAK_RANGE.x, PEAK_RANGE.y])


## 4 y 5 — El `MotorAudio` del rig: presupuesto de voces y rampa de régimen sin
## saltos de volumen ni cortes de loop audibles.
func _check_motor_audio() -> void:
	_rig = get_node_or_null(rig_path) as DroneRig
	if _rig == null:
		fail("falta el rig '%s' en la escena del check" % str(rig_path))
		return
	await wait_physics(2)
	_drone = _rig.get_drone()
	_audio = _rig.get_motor_audio()
	if _drone == null or _audio == null:
		fail("el rig no quedó cableado: dron %s, audio %s" % [str(_drone), str(_audio)])
		return

	# El lazo de control se desengancha: lo que se mide es régimen -> volumen.
	var controller := _rig.get_flight_controller()
	var radio := _rig.get_radio()
	if radio != null:
		radio.enabled = false
	_drone.force_disarm()
	_drone.set_controller(null)
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, RAMP_ALTITUDE, 0.0)))
	_set_commands(0.0)
	await wait_physics(3)
	var armed := _drone.arm()
	expect(armed, "no se pudo armar el dron para la rampa de régimen")
	if not armed:
		_drone.set_controller(controller)
		return
	await wait_physics(SETTLE_TICKS)

	var players := _audio.get_players()
	var voices := _audio.get_active_voice_count()
	var scene_voices := _count_scene_voices()
	print("  [4] MotorAudio: %d reproductores, %d voces activas, %d voces en toda la escena (presupuesto %d)"
			% [players.size(), voices, scene_voices, VOICE_BUDGET])
	expect(players.size() == MotorAudio.VOICES_PER_MOTOR * _drone.get_motors().size(),
			"MotorAudio tiene %d reproductores para %d motores"
			% [players.size(), _drone.get_motors().size()])
	expect(voices <= players.size(),
			"MotorAudio reporta %d voces activas y solo tiene %d reproductores"
			% [voices, players.size()])
	expect(scene_voices <= VOICE_BUDGET,
			"la escena tiene %d voces sonando y el presupuesto de `docs/13` §5.2 es %d"
			% [scene_voices, VOICE_BUDGET])

	var ticks := int(RAMP_SECONDS / PHYSICS_STEP)
	var streams: Array[AudioStream] = []
	var volumes: Array[float] = []
	for player: AudioStreamPlayer in players:
		streams.append(player.stream)
		volumes.append(player.volume_db)
	var motors := _drone.get_motors().size()
	var previous: Array[float] = []
	for motor: int in motors:
		previous.append(_audio.get_motor_volume_db(motor))
	var jump := 0.0
	var worst_motor := -1
	var cuts := 0
	var ripple := 0.0
	var voice_jump := 0.0
	var worst_voice := ""
	var bands_seen: Dictionary[int, bool] = {}
	for tick: int in ticks:
		_set_commands(float(tick) / float(maxi(ticks - 1, 1)))
		await wait_physics(1)
		for motor: int in motors:
			var combined := _audio.get_motor_volume_db(motor)
			var step := absf(combined - previous[motor])
			if step > jump:
				jump = step
				worst_motor = motor
			previous[motor] = combined
			ripple = maxf(ripple, absf(combined - _audio.get_motor_envelope_db(motor)))
		for index: int in players.size():
			var player := players[index]
			bands_seen[_audio.get_player_band(index)] = true
			var peak_db := maxf(volumes[index], player.volume_db)
			if player.stream != streams[index] and peak_db > AUDIBLE_DB:
				cuts += 1
				print("      corte: %s pasó de %.2f a %.2f dB cambiando de loop"
						% [player.name, volumes[index], player.volume_db])
			if peak_db > LOUD_DB:
				var voice_step := absf(player.volume_db - volumes[index])
				if voice_step > voice_jump:
					voice_jump = voice_step
					worst_voice = String(player.name)
			streams[index] = player.stream
			volumes[index] = player.volume_db
	print("  [5] rampa de régimen 0->1 en %.1f s: salto combinado máximo %.3f dB (motor %d, límite %.1f), rizado %.3f dB, salto de voz máximo %.3f dB en %s (límite %.1f), %d cortes audibles, %d bandas recorridas"
			% [RAMP_SECONDS, jump, worst_motor + 1, MAX_JUMP_DB, ripple, voice_jump,
			worst_voice if not worst_voice.is_empty() else "(ninguna)", MAX_VOICE_JUMP_DB,
			cuts, bands_seen.size()])
	expect(jump <= MAX_JUMP_DB,
			"el volumen combinado saltó %.2f dB entre dos frames y el límite es %.1f dB"
			% [jump, MAX_JUMP_DB])
	expect(cuts == 0,
			"%d reproductores cambiaron de loop mientras se oían: eso es un clic" % cuts)
	expect(voice_jump <= MAX_VOICE_JUMP_DB,
			"la voz %s saltó %.2f dB en un frame llevando el sonido (límite %.1f): eso es un cambio de banda sin crossfade"
			% [worst_voice, voice_jump, MAX_VOICE_JUMP_DB])
	expect(bands_seen.size() == MotorAudio.BAND_NAMES.size(),
			"la rampa recorrió %d bandas de %d: el barrido no cubre todo el crossfade"
			% [bands_seen.size(), MotorAudio.BAND_NAMES.size()])

	# 6 — Al desarmar, el audio se apaga solo; `set_enabled(false)` lo corta en seco.
	# No es adorno: dejar ocho reproducciones vivas al salir del proceso deja
	# `AudioStreamPlayback` colgando, que es lo que Godot reporta como recursos en
	# uso al cerrar.
	_set_commands(0.0)
	_drone.force_disarm()
	await wait_physics(SETTLE_TICKS)
	var after_disarm := _audio.get_active_voice_count()
	var loud := 0
	for player: AudioStreamPlayer in players:
		if player.playing and player.volume_db > MotorAudio.SILENT_DB + 0.5:
			loud += 1
	_audio.set_enabled(false)
	await wait_physics(2)
	var after_disable := _audio.get_active_voice_count()
	print("  [6] tras desarmar: %d voces, %d por encima de %.0f dB; tras set_enabled(false): %d voces"
			% [after_disarm, loud, MotorAudio.SILENT_DB, after_disable])
	expect(loud == 0,
			"%d reproductores quedaron por encima de %.0f dB con el dron desarmado"
			% [loud, MotorAudio.SILENT_DB])
	expect(after_disable == 0, "set_enabled(false) dejó %d voces sonando" % after_disable)
	_drone.set_controller(controller)


## Los criterios de `docs/13` §10.3 que dependen de piezas de WP-27.
func _skip_wp27() -> void:
	print("  SKIP: [docs/13 §10.3.2] efectos de `Master` (compresor + limitador) y pasa-bajos de `Music` — WP-27")
	print("  SKIP: [docs/13 §10.3.3] `AudioPool.active_voices()` con 30 fuentes 3D — WP-27")
	print("  SKIP: [docs/13 §10.3.4/5] transición de stems y sincronía de `MusicDirector` — WP-27")


# --- Utilidades -------------------------------------------------------------------------------


## Muestras de un loop PCM de 16 bits mono.
func _frame_count(stream: AudioStreamWAV) -> int:
	var bytes := 2 * (2 if stream.stereo else 1)
	return stream.data.size() / maxi(bytes, 1)


## Pico del loop en dBFS, leído del PCM crudo. Es la única forma de medirlo sin
## reproducirlo, y por eso los loops se importan **sin comprimir**: con QOA el
## `data` sería el flujo codificado y esto no diría nada.
func _peak_dbfs(stream: AudioStreamWAV) -> float:
	if stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return NAN
	var peak := 0
	var samples := stream.data.size() / 2
	for index: int in samples:
		peak = maxi(peak, absi(stream.data.decode_s16(index * 2)))
	if peak <= 0:
		return -INF
	return linear_to_db(float(peak) / 32768.0)


## Voces sonando en toda la escena, del tipo que sean (`docs/13` §5.2).
func _count_scene_voices() -> int:
	var count := 0
	var pending: Array[Node] = [get_tree().root]
	var index := 0
	while index < pending.size():
		var node := pending[index]
		if node is AudioStreamPlayer and (node as AudioStreamPlayer).playing:
			count += 1
		elif node is AudioStreamPlayer2D and (node as AudioStreamPlayer2D).playing:
			count += 1
		elif node is AudioStreamPlayer3D and (node as AudioStreamPlayer3D).playing:
			count += 1
		for child: Node in node.get_children():
			pending.append(child)
		index += 1
	return count


## Escribe el mismo comando en los cuatro motores de prueba.
func _set_commands(value: float) -> void:
	var commands: Array[float] = [value, value, value, value]
	_drone.test_motor_commands = commands
