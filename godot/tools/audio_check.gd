## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de audio (`docs/15` §3, `docs/13` §10.3).
##
## Cubre lo que WP-07 puso sobre la mesa —los **siete buses**, el autoload [Audio]
## como único dueño de los volúmenes, los **ocho loops de motor** sintetizados y el
## [MotorAudio] del `drone_rig.tscn` con su crossfade por bandas de régimen— y lo
## que WP-27 agregó: los **efectos** de `Master`, `City` y `Music`, el [AudioPool]
## con su presupuesto de 24 voces y el [MusicDirector] con sus tres stems.
##
## Los criterios siguen el orden de `docs/13` §10.3, con dos aclaraciones sobre
## cómo se miden, que valen tanto como el número:
##
## - **Criterio 4, «monótona»**: se mide *por tramo*. Dentro de `INTRO → BATTLE →
##   fase 3` hay stems que primero suben y después bajan —`tension` va de −18 a 0 y
##   de 0 a −4—, así que exigir monotonía sobre la secuencia entera no querría
##   decir nada. Lo que no puede pasar es que un cruce se pase de largo o se dé
##   vuelta: eso es lo que se verifica, tramo por tramo, junto con el techo de
##   6 dB por cada 20 ms.
## - **Criterio 5, «misma posición»**: en Godot 4.7 `AudioStreamPlaybackSynchronized`
##   no expone **nada** —ni posición ni volumen por stem—, así que no hay forma de
##   leer tres posiciones y restarlas. La garantía real es estructural: los tres
##   stems entran al mismo [AudioStreamSynchronized] y **miden exactamente lo
##   mismo al sample**, que es lo que el riesgo 8 de `docs/13` §11 pide de verdad.
##   El check compara los tres largos al sample, mide la deriva del reloj de la
##   mezcla contra el reloj de pared a los 30 s de posición, y además corre una
##   **prueba negativa**: con stems de distinta duración, el comparador falla.
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

## Comando con el que se deja a los motores en régimen de vuelo antes de congelar
## el cuerpo. Tiene que dejarlos **muy por encima** del ralentí: lo que se prueba es
## que el audio calla aunque las rpm se queden altas.
const FREEZE_COMMAND: float = 0.7

## Segundos que se le dan al audio para caer al silencio con el cuerpo congelado.
##
## El limitador de pendiente de [constant MotorAudio.SLEW_DB_PER_SECOND] tarda
## 80 / 300 = 0.27 s en ir de 0 dB a −80; medio segundo deja margen y sigue siendo
## imperceptible sobre la tarjeta de reconstrucción.
const FREEZE_FADE_BUDGET: float = 0.5

## Tope de ticks del bucle de medición del desvanecido (2 s a 100 Hz).
const FREEZE_MAX_TICKS: int = 200

## Archivo del layout, que el check lee como **texto** para comparar la mezcla
## base contra [constant Audio.BASE_VOLUMES_DB]. Leerlo del `AudioServer` no
## serviría: para cuando el check corre, cualquiera pudo haber aplicado los
## volúmenes del jugador encima.
const LAYOUT_PATH: String = "res://default_bus_layout.tres"

## Efectos que tiene que tener cada bus, en orden (`docs/13` §5.1).
const BUS_EFFECTS: Dictionary[StringName, Array] = {
	&"Master": ["AudioEffectCompressor", "AudioEffectLimiter"],
	&"City": ["AudioEffectReverb"],
	&"Music": ["AudioEffectLowPassFilter"],
}

## Buses que no llevan ningún efecto.
const BUSES_WITHOUT_EFFECTS: Array[StringName] = [&"Motors", &"Weapons", &"Enemies", &"UI"]

## Fuentes 3D que se disparan de golpe contra el `AudioPool` (`docs/13` §10.3.3).
const STRESS_SOURCES: int = 30

## Cuánto puede alejarse la voz de un haz de su punto de contacto, en metros
## (WP-27b). Es holgura de redondeo: el pool escribe la posición exacta.
const BEAM_FOLLOW_TOLERANCE: float = 0.1

## Segundos que se le dan al piloto automático de la intensidad para asentarse
## antes de medir el reposo.
const INTENSITY_SETTLE_SECONDS: float = 0.8

## Ventana de medición del golpe, en segundos: la memoria de daño más margen para
## ver la rampa de bajada terminada.
const INTENSITY_WINDOW_SECONDS: float = 6.2

## Calor que puede quedar al final de esa ventana.
const INTENSITY_RESIDUAL: float = 0.02

## Duración exacta de cada stem, en segundos (`docs/13` §5.3).
const STEM_SECONDS: float = 64.0

## Tolerancia de la duración de los stems, en segundos. Es media muestra a
## 32 kHz: el criterio es «exactamente 64 s», no «64 s más o menos».
const STEM_TOLERANCE: float = 0.000016

## Salto máximo admitido en el volumen de un stem por cada 20 ms (`docs/13`
## §10.3.4).
const STEM_MAX_STEP_DB: float = 6.0

## Ventana con la que se mide ese salto, en segundos.
const STEM_STEP_WINDOW: float = 0.020

## Separación mínima entre dos muestras del volumen de un stem, en segundos. Sin
## este piso, en headless los frames salen cada décimas de milisegundo y la tasa
## medida se vuelve ruido de coma flotante.
const STEM_SAMPLE_GAP: float = 0.005

## Margen de tolerancia de la monotonía, en dB.
const STEM_MONOTONIC_EPSILON: float = 0.01

## Posición a la que se salta para medir la deriva del reloj de la mezcla.
const SYNC_PROBE_SECONDS: float = 30.0

## Ventana sobre la que se mide esa deriva, en segundos.
const SYNC_WINDOW: float = 4.0

## Deriva admitida entre el reloj de la mezcla y el de pared, como fracción de la
## ventana.
##
## No son los ±5 ms del criterio 5, y la diferencia **no** es un relajo del
## criterio sino un cambio de lo que se está midiendo. Los ±5 ms de `docs/13`
## §10.3.5 son entre stems, y entre stems no hay nada que medir: los tres viven en
## el mismo [AudioStreamSynchronized], con la misma cantidad de muestras, y el
## check lo comprueba al sample (más la prueba negativa del criterio 9). Lo que
## esta cifra vigila es otra cosa —que la mezcla siga corriendo y a la velocidad
## correcta— y la referencia con la que se compara es mala: en `--headless` el
## controlador es el Dummy, que mezcla desde el propio bucle principal, así que
## `get_playback_position()` acompaña los altibajos del frame. Medido en corridas
## seguidas, la desviación va de 0.2 % a 2.5 % sin que nada suene distinto. Con el
## 25 % se cazan los fallos reales —la mezcla parada, el doble de rápido, el reloj
## pegado— sin rojos de mentira; el número exacto queda impreso para el que quiera
## mirarlo.
const SYNC_TOLERANCE: float = 0.25

@export var rig_path: NodePath = ^"DroneRig"

var _rig: DroneRig = null
var _drone: Drone = null
var _audio: MotorAudio = null
var _pool: AudioPool = null
var _music: MusicDirector = null
var _restore_volumes: Dictionary[StringName, float] = {}
var _restore_muted: bool = false
var _restore_lowpass: bool = false

## Voces que el check finge estar usando como fuente externa del [AudioPool].
var stub_voices_count: int = 0


func _run() -> void:
	Engine.physics_ticks_per_second = 100
	for bus: StringName in Audio.BUSES:
		_restore_volumes[bus] = Audio.get_volume(bus)
	_restore_muted = Audio.muted
	_restore_lowpass = Audio.is_music_lowpass_enabled()

	_check_buses()
	_check_effects()
	_check_volume_api()
	_check_loops()
	await _check_motor_audio()
	await _check_audio_pool()
	await _check_music()
	_check_stem_comparator()

	# El autoload es global al proceso: se deja como estaba aunque el check falle.
	for bus: StringName in _restore_volumes:
		Audio.set_volume(bus, _restore_volumes[bus])
	Audio.set_muted(_restore_muted)
	var _restored := Audio.set_music_lowpass(_restore_lowpass)


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
	_check_base_volumes()


## 1b — La mezcla base del layout coincide con [constant Audio.BASE_VOLUMES_DB].
##
## Son dos copias de la misma tabla —`docs/13` §5.1— y viven en archivos
## distintos: el `.tres` que carga el `AudioServer` y la constante con la que el
## autoload compone el volumen del jugador. Si se separan, el jugador mueve un
## deslizador y la mezcla salta a otra cosa; esto es lo que lo impide.
func _check_base_volumes() -> void:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	if text.is_empty():
		fail("no se pudo leer %s" % LAYOUT_PATH)
		return
	var names: Dictionary[int, String] = {0: "Master"}
	var volumes: Dictionary[int, float] = {0: 0.0}
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("bus/"):
			continue
		var parts := trimmed.split("=", true, 1)
		if parts.size() != 2:
			continue
		var key := parts[0].strip_edges()
		var value := parts[1].strip_edges()
		var fields := key.split("/")
		if fields.size() != 3:
			continue
		var index := int(fields[1])
		if fields[2] == "name":
			names[index] = value.trim_prefix("&").trim_prefix("\"").trim_suffix("\"")
		elif fields[2] == "volume_db":
			volumes[index] = float(value)
	var line_out: Array[String] = []
	for index: int in BUSES.size():
		var bus: StringName = BUSES[index]
		# Lo que el `.tres` no escribe es el valor por defecto de Godot, 0 dB.
		var written := float(volumes.get(index, 0.0))
		var wanted := Audio.base_volume_db(bus)
		line_out.append("%s %+.1f" % [String(bus), written])
		expect(String(names.get(index, "Master")) == String(bus),
				"el bus %d del layout se llama '%s' y tiene que llamarse '%s'"
				% [index, String(names.get(index, "Master")), String(bus)])
		expect_near(written, wanted, 0.01,
				"la mezcla base de '%s' en el layout" % String(bus))
	print("  [1b] mezcla base del layout: %s dB" % ", ".join(line_out))


## 2 — Los efectos de `docs/13` §5.1: compresor y limitador en `Master`, reverb en
## `City`, pasa-bajos **apagado** en `Music` que se puede encender y apagar.
func _check_effects() -> void:
	for bus: StringName in BUS_EFFECTS:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			fail("falta el bus '%s'" % String(bus))
			continue
		var wanted := BUS_EFFECTS[bus]
		var found: Array[String] = []
		for slot: int in AudioServer.get_bus_effect_count(index):
			found.append(AudioServer.get_bus_effect(index, slot).get_class())
		print("  [2] %-7s %s" % [String(bus), ", ".join(found) if not found.is_empty() else "-"])
		expect(found.size() == wanted.size(),
				"'%s' tiene %d efectos y `docs/13` §5.1 pide %d (%s)"
				% [String(bus), found.size(), wanted.size(), ", ".join(wanted)])
		for slot: int in mini(found.size(), wanted.size()):
			expect(found[slot] == wanted[slot],
					"el efecto %d de '%s' es %s y tiene que ser %s"
					% [slot, String(bus), found[slot], wanted[slot]])
	for bus: StringName in BUSES_WITHOUT_EFFECTS:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		expect(AudioServer.get_bus_effect_count(index) == 0,
				"'%s' tiene %d efectos y `docs/13` §5.1 no le pone ninguno"
				% [String(bus), AudioServer.get_bus_effect_count(index)])

	# Los parámetros del compresor y del limitador son la mitad del punto: un
	# limitador con el techo de fábrica no protege de nada.
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0 and AudioServer.get_bus_effect_count(master) >= 2:
		var compressor := AudioServer.get_bus_effect(master, 0) as AudioEffectCompressor
		var limiter := AudioServer.get_bus_effect(master, 1) as AudioEffectLimiter
		if compressor != null:
			print("  [2] compresor: umbral %.1f dB, ratio %.1f:1, ataque %.0f µs, release %.0f ms"
					% [compressor.threshold, compressor.ratio, compressor.attack_us,
					compressor.release_ms])
			expect_near(compressor.threshold, -12.0, 0.01, "el umbral del compresor")
			expect_near(compressor.ratio, 4.0, 0.01, "la ratio del compresor")
			expect_near(compressor.attack_us, 20000.0, 1.0, "el ataque del compresor")
			expect_near(compressor.release_ms, 180.0, 1.0, "el release del compresor")
		if limiter != null:
			print("  [2] limitador: techo %.2f dB" % limiter.ceiling_db)
			expect_near(limiter.ceiling_db, -0.5, 0.01, "el techo del limitador")

	var city := AudioServer.get_bus_index(&"City")
	if city >= 0 and AudioServer.get_bus_effect_count(city) >= 1:
		var reverb := AudioServer.get_bus_effect(city, 0) as AudioEffectReverb
		if reverb != null:
			print("  [2] reverb de City: sala %.2f, damping %.2f, húmedo %.2f"
					% [reverb.room_size, reverb.damping, reverb.wet])
			expect_near(reverb.room_size, 0.6, 0.01, "el tamaño de sala del reverb de City")
			expect_near(reverb.damping, 0.4, 0.01, "el damping del reverb de City")
			expect_near(reverb.wet, 0.12, 0.01, "la parte húmeda del reverb de City")

	var music := AudioServer.get_bus_index(&"Music")
	if music < 0 or AudioServer.get_bus_effect_count(music) < 1:
		fail("el bus 'Music' no tiene el pasa-bajos de `docs/13` §5.1")
		return
	var lowpass := AudioServer.get_bus_effect(music, 0) as AudioEffectLowPassFilter
	if lowpass != null:
		print("  [2] pasa-bajos de Music: corte %.0f Hz, resonancia %.2f"
				% [lowpass.cutoff_hz, lowpass.resonance])
		expect_near(lowpass.cutoff_hz, 600.0, 1.0, "el corte del pasa-bajos de Music")
		expect_near(lowpass.resonance, 0.5, 0.01, "la resonancia del pasa-bajos de Music")
	# Nace apagado, se enciende al pausar y se apaga al reanudar. Los tres estados
	# se prueban acá porque es lo que hace `PauseMenu` y no hay otro sitio donde
	# verificarlo sin abrir un nivel.
	expect(not AudioServer.is_bus_effect_enabled(music, 0),
			"el pasa-bajos de 'Music' arranca encendido y `docs/13` §5.1 lo pide apagado")
	var turned_on := Audio.set_music_lowpass(true)
	var on := Audio.is_music_lowpass_enabled()
	var turned_off := Audio.set_music_lowpass(false)
	var off := Audio.is_music_lowpass_enabled()
	print("  [2] pasa-bajos: apagado -> %s -> %s" % [str(on), str(off)])
	expect(turned_on and on, "Audio.set_music_lowpass(true) no encendió el pasa-bajos")
	expect(turned_off and not off, "Audio.set_music_lowpass(false) no lo apagó")


## 2b — `Audio.set_volume()` mueve el `AudioServer` **componiendo** sobre la mezcla
## base, y el 0 lineal no produce `-inf`.
##
## La composición es de WP-27: el deslizador del jugador se suma en dB a la mezcla
## de `docs/13` §5.1, así que `Motors` al 0.8 lineal no queda en −1.94 dB sino en
## −5.94. Antes de que el layout tuviera mezcla, las dos cuentas daban lo mismo.
func _check_volume_api() -> void:
	var index := AudioServer.get_bus_index(&"Motors")
	if index < 0:
		fail("no se puede probar Audio.set_volume(): falta el bus 'Motors'")
		return
	var line: Array[String] = []
	for linear: float in VOLUME_PROBES:
		Audio.set_volume(&"Motors", linear)
		var applied := AudioServer.get_bus_volume_db(index)
		var wanted := Audio.bus_volume_db(&"Motors")
		line.append("%.2f->%.2f dB" % [linear, applied])
		expect_near(applied, wanted, 0.01,
				"Audio.set_volume(&\"Motors\", %.2f) dejó el bus en %.2f dB" % [linear, applied])
		if linear > 0.0:
			expect_near(applied, Audio.base_volume_db(&"Motors") + linear_to_db(linear), 0.01,
					"la composición base + deslizador con %.2f lineal" % linear)
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
	await _check_frozen_body(players)
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


## 6b — Con el **cuerpo congelado** el audio calla igual, aunque las rpm se queden
## clavadas en régimen de vuelo, y vuelve solo al descongelar y armar.
##
## Es el bug que reportó el piloto en el checkpoint 3b: «a veces queda sonando lo
## último». `RespawnController._begin()` y `RoundManager._freeze_drone(true)` ponen
## `freeze = true`, y con el cuerpo congelado no corre `Drone._integrate_forces()`,
## que es el único sitio donde se llama a `DroneMotor.step()`. Las rpm se quedan
## donde estaban, `envelope_for()` las lee, y los ocho loops —que son
## `LOOP_FORWARD`— siguen sonando con el volumen y el tono del último cuadro vivo
## hasta el final de la ronda.
##
## Los tres criterios: las ocho voces caen a `SILENT_DB` en menos de medio segundo,
## `_stop()` ocurre de verdad (cero voces sonando), y el retorno es **automático**:
## descongelar y armar vuelve a dar sonido sin que nadie rehabilite nada. Lo
## último importa tanto como lo primero: arreglar esto con `set_enabled(false)`
## dejaría el audio mudo en cualquier camino de salida que se olvide de encenderlo.
func _check_frozen_body(players: Array[AudioStreamPlayer]) -> void:
	var armed := _drone.arm()
	if not armed:
		fail("6 no se pudo rearmar el dron para la prueba de cuerpo congelado")
		return
	_set_commands(FREEZE_COMMAND)
	await wait_physics(SETTLE_TICKS)
	var flying := _audible_count(players)
	var rpm_before := _max_rpm()

	# Exactamente lo que hace `RespawnController._begin()`, en el mismo orden.
	_drone.force_disarm()
	_drone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_drone.freeze = true

	var ticks := 0
	var silent_at := -1.0
	while ticks < FREEZE_MAX_TICKS:
		await wait_physics(1)
		ticks += 1
		if silent_at < 0.0 and _audible_count(players) == 0:
			silent_at = float(ticks) * PHYSICS_STEP
		if silent_at >= 0.0 and _audio.get_active_voice_count() == 0:
			break
	var stopped := _audio.get_active_voice_count() == 0
	var rpm_frozen := _max_rpm()

	# Y el regreso: descongelar y armar, sin tocar `enabled`.
	_drone.freeze = false
	var rearmed := _drone.arm()
	_set_commands(FREEZE_COMMAND)
	await wait_physics(SETTLE_TICKS)
	var back := _audible_count(players)

	# Se deja el banco como estaba antes de 6b: desarmado y en silencio, que es lo
	# que el cierre del check espera.
	_set_commands(0.0)
	_drone.force_disarm()
	await wait_physics(SETTLE_TICKS)

	print("  [6b] con freeze: %d voces audibles antes → silencio a los %.3f s (rpm %.0f → %.0f, o sea clavadas), _stop() %s tras %.2f s; al descongelar y armar vuelven %d voces"
			% [flying, silent_at, rpm_before, rpm_frozen, str(stopped),
			float(ticks) * PHYSICS_STEP, back])
	expect(flying > 0,
			"6 la prueba no vale: el dron no llegó a sonar antes de congelarse")
	expect(rpm_frozen >= _idle_rpm(),
			"6 la prueba no vale: las rpm cayeron a %.0f con el cuerpo congelado (ralentí %.0f),"
			% [rpm_frozen, _idle_rpm()]
			+ " así que el silencio pudo venir del motor y no de la regla de congelado")
	expect(silent_at >= 0.0 and silent_at <= FREEZE_FADE_BUDGET,
			"6 con el cuerpo congelado las ocho voces tardaron %.3f s en caer a %.0f dB (tope %.2f s)"
			% [silent_at, MotorAudio.SILENT_DB, FREEZE_FADE_BUDGET])
	expect(stopped,
			"6 con el cuerpo congelado quedaron %d voces sonando: `_stop()` no llegó"
			% _audio.get_active_voice_count())
	expect(rearmed and back > 0,
			"6 al descongelar y armar el audio no volvió (%d voces audibles): el arreglo no puede"
			% back + " dejar el nodo apagado")


## Reproductores por encima del suelo de volumen.
func _audible_count(players: Array[AudioStreamPlayer]) -> int:
	var count := 0
	for player: AudioStreamPlayer in players:
		if player.volume_db > MotorAudio.SILENT_DB + MotorAudio.SILENCE_MARGIN_DB:
			count += 1
	return count


## Régimen más alto de los cuatro motores, en rpm.
func _max_rpm() -> float:
	var top := 0.0
	for motor: DroneMotor in _drone.get_motors():
		top = maxf(top, absf(motor.rpm))
	return top


## Ralentí del primer motor, que es el umbral bajo el cual la envolvente se
## desvanece sola.
func _idle_rpm() -> float:
	var motors := _drone.get_motors()
	return motors[0].idle_rpm if not motors.is_empty() else 0.0


## 7 — El [AudioPool]: 30 fuentes 3D de golpe, presupuesto de 24 y topes por
## categoría (`docs/13` §10.3.3).
##
## El pool se crea acá y no en la escena a propósito: así el check prueba también
## que el nodo se arma solo, encuentra sus fuentes externas —el [MotorAudio] del
## rig, que se anota en su grupo— y carga su banco sin que nadie lo cablee.
func _check_audio_pool() -> void:
	_pool = AudioPool.new()
	_pool.name = "AudioPool"
	# El golpe de blindaje se fuerza: en esta escena no hay `ImpactFXPool`, pero
	# el criterio no es «cuál suena» sino «cuántas voces hay».
	_pool.armor_policy = AudioPool.ArmorPolicy.ALWAYS
	add_child(_pool)
	await wait_frames(2)

	var missing := PackedStringArray()
	for event: StringName in AudioPool.BANK:
		if not _pool.has_event(event):
			missing.append(String(event))
	expect(missing.is_empty(),
			"al banco del AudioPool le faltan %s (regeneralos con tools/generate_city_sounds.gd y tools/generate_pool_sounds.gd)"
			% ", ".join(missing))
	var sum_limits := 0
	for category: StringName in AudioPool.CATEGORY_LIMITS:
		sum_limits += _pool.category_limit(category)
	expect(sum_limits == AudioPool.VOICE_BUDGET,
			"los topes por categoría suman %d y el presupuesto de `docs/13` §5.2 es %d"
			% [sum_limits, AudioPool.VOICE_BUDGET])

	# 30 fuentes repartidas entre las cuatro categorías posicionales, a distancias
	# distintas: es lo que obliga al reciclaje por lejanía.
	var categories: Array[StringName] = [AudioPool.CATEGORY_WEAPONS, AudioPool.CATEGORY_ENEMIES,
			AudioPool.CATEGORY_CITY, AudioPool.CATEGORY_MOTORS]
	var events: Array[StringName] = [&"impact_armor", &"part_fall", &"collapse_low", &"signal_cut"]
	var served := 0
	var worst_voices := 0
	var worst_by_category: Dictionary[StringName, int] = {}
	for shot: int in STRESS_SOURCES:
		var slot := shot % categories.size()
		var position := Vector3(float(shot) * 3.0, 0.0, float(shot % 7) * 4.0)
		var player := _pool.play_event(events[slot], position)
		if player != null:
			served += 1
		worst_voices = maxi(worst_voices, _pool.active_voices())
		for category: StringName in AudioPool.CATEGORY_LIMITS:
			worst_by_category[category] = maxi(int(worst_by_category.get(category, 0)),
					_pool.category_voices(category))
	var detail: Array[String] = []
	for category: StringName in AudioPool.CATEGORY_LIMITS:
		detail.append("%s %d/%d" % [String(category), int(worst_by_category.get(category, 0)),
				_pool.category_limit(category)])
	print("  [7] AudioPool: %d pedidos, %d servidos, %d voces como mucho (presupuesto %d) · %s"
			% [STRESS_SOURCES, served, worst_voices, AudioPool.VOICE_BUDGET, ", ".join(detail)])
	expect(worst_voices <= AudioPool.VOICE_BUDGET,
			"el AudioPool llegó a %d voces y el presupuesto es %d"
			% [worst_voices, AudioPool.VOICE_BUDGET])
	for category: StringName in AudioPool.CATEGORY_LIMITS:
		var peak := int(worst_by_category.get(category, 0))
		expect(peak <= _pool.category_limit(category),
				"la categoría '%s' llegó a %d voces y su tope es %d"
				% [String(category), peak, _pool.category_limit(category)])
	expect(served > 0, "el AudioPool no sirvió ni una voz: revisá el banco")

	# El pool se anotó a sí mismo y encontró al `MotorAudio` del rig por grupo.
	expect(_pool.is_in_group(AudioPool.GROUP),
			"el AudioPool no se anotó en el grupo '%s'" % String(AudioPool.GROUP))
	var motors_source := get_tree().get_nodes_in_group(&"audio_motors").size()
	print("  [7] fuentes externas: %d en 'audio_motors', %d voces lógicas de motores"
			% [motors_source, _pool.external_voices(AudioPool.CATEGORY_MOTORS)])
	expect(motors_source > 0,
			"el MotorAudio del rig no se anotó en 'audio_motors': el pool no puede contarle las voces")

	# Y las señales del bus llegan: un derrumbe son dos capas, una pila es un clic.
	_pool.stop_all()
	await wait_frames(1)
	var before := _pool.event_counts().size()
	Events.building_destroyed.emit(Vector3(12.0, 0.0, 8.0), 100)
	Events.battery_collected.emit(0.4, Vector3(4.0, 1.0, 0.0))
	Events.hit_confirmed.emit(Vector3(6.0, 2.0, 1.0), true, false, &"weak")
	await wait_frames(2)
	var counts := _pool.event_counts()
	print("  [7] por el bus: %s" % str(counts))
	for event: StringName in [&"collapse_low", &"collapse_debris", &"battery_click",
			&"impact_weak"]:
		expect(int(counts.get(event, 0)) > 0,
				"el AudioPool no tocó '%s' cuando el bus lo pidió" % String(event))
	expect(counts.size() >= before, "el AudioPool perdió eventos del banco")
	_pool.stop_all()
	await _check_external_cap()


## 7b — El tope que el pool le impone a una **fuente externa**.
##
## Es el mecanismo del que depende el [AudioRig] del jefe: el rig tiene seis
## reproductores propios más el loop de servos más la carga del [Telegraph], o sea
## hasta ocho voces, y la categoría `enemies` sólo admite seis (`docs/13` §5.2).
## El acuerdo es que el rig pregunta `can_claim()` antes de tomar una voz libre y,
## si la categoría está llena, recicla en vez de sumar.
##
## Acá se prueba el lado del pool con el propio check haciendo de fuente: se le
## dice cuántas voces está usando y se verifica que el pool las cuente, que
## `can_claim()` se cierre al llegar al tope y que `play_3d()` devuelva `null` en
## vez de pasarse. Sin un jefe en la escena no hay otra forma de cubrir este
## camino, y es el que decide si las telegrafías se oyen o no.
func _check_external_cap() -> void:
	var limit := _pool.category_limit(AudioPool.CATEGORY_ENEMIES)
	_pool.register_source(AudioPool.CATEGORY_ENEMIES, self, &"stub_voices")
	stub_voices_count = 0
	expect(_pool.external_voices(AudioPool.CATEGORY_ENEMIES) == 0,
			"el pool contó voces de una fuente externa que no está usando ninguna")
	stub_voices_count = limit - 1
	var can_before := _pool.can_claim(AudioPool.CATEGORY_ENEMIES)
	var player := _pool.play_3d(load(String(AudioPool.BANK[&"part_fall"]["path"])),
			Vector3.ZERO, AudioPool.CATEGORY_ENEMIES)
	# La voz servida se corta antes de subir el conteo: si no, el total quedaría en
	# 7 —seis declaradas más la propia— y la línea del log parecería una violación
	# del tope cuando en realidad es la fuente falsa cambiando de opinión a mitad
	# de camino. El rig de verdad no hace eso: declara lo que está sonando.
	if player != null:
		player.stop()
	stub_voices_count = limit
	var can_after := _pool.can_claim(AudioPool.CATEGORY_ENEMIES)
	var refused := _pool.play_3d(load(String(AudioPool.BANK[&"part_fall"]["path"])),
			Vector3(0.0, 0.0, 400.0), AudioPool.CATEGORY_ENEMIES)
	var counted := _pool.category_voices(AudioPool.CATEGORY_ENEMIES)
	print("  [7b] fuente externa con %d/%d voces: can_claim %s -> %s, voces contadas %d, pedido con el tope lleno %s"
			% [limit, limit, str(can_before), str(can_after), counted,
			"rechazado" if refused == null else "servido"])
	expect(can_before, "el pool cerró la categoría con una voz externa libre")
	expect(player != null, "el pool no sirvió la voz que todavía entraba en el tope")
	expect(not can_after, "el pool sigue abierto con la categoría llena de voces externas")
	expect(counted >= limit,
			"el pool contó %d voces de enemigos y la fuente externa declara %d"
			% [counted, limit])
	expect(refused == null,
			"el pool sirvió una voz con la categoría llena: el tope de 6 no se respeta")
	stub_voices_count = 0
	_pool.unregister_source(self)
	_pool.stop_all()
	await wait_frames(1)
	await _check_sustained_loops()
	await _check_loop_budget()
	await _check_loop_leak()


## 7c — Los bucles sostenidos del haz (WP-27b): arrancan con la ventana activa,
## siguen al punto de contacto y se cortan con `hide_beam()`.
##
## Se prueba con un [SweepAction] **de verdad** —la clase base que usan el láser de
## cabeza y el asedio—, no con un doble: lo que se quiere verificar es el gancho
## real, y los tres métodos que lo llevan (`configure_beam`, `update_beam`,
## `hide_beam`) están todos ahí. Sin enemigo alrededor la acción no arma ningún
## haz visual, que es justo lo que hace falta para medir solo el audio.
func _check_sustained_loops() -> void:
	var action := SweepAction.new()
	action.name = "BeamProbe"
	add_child(action)
	await wait_frames(1)

	var before := _pool.active_loops()
	# El nombre del nodo del haz es lo que elige el timbre: cian o asedio.
	action.configure_beam(&"HeadLaserBeam", 0.2, Color.AQUA)
	var origin := Vector3(0.0, 8.0, 0.0)
	var contact := Vector3(30.0, 0.0, 12.0)
	action.update_beam(origin, contact)
	await wait_physics(1)
	var started := _pool.loop_count(&"laser_loop")
	var voice := _beam_voice_at(AudioPool.CATEGORY_ENEMIES)
	var placed := voice.global_position.distance_to(contact) if voice != null else INF

	# El punto de contacto se mueve: el zumbido tiene que irse con él.
	var moved_to := Vector3(-18.0, 3.0, 44.0)
	action.update_beam(origin, moved_to)
	await wait_physics(1)
	var followed := voice.global_position.distance_to(moved_to) if voice != null else INF
	var still := _pool.loop_count(&"laser_loop")

	action.hide_beam()
	await wait_physics(1)
	var after := _pool.loop_count(&"laser_loop")
	var silent := voice == null or not voice.playing

	print("  [7c] haz: bucles %d -> %d al abrir la ventana · en el contacto %.3f m · tras mover el punto %.3f m (%d bucle) · tras hide_beam() %d bucles, voz parada %s"
			% [before, started, placed, followed, still, after, str(silent)])
	expect(started == 1, "el haz no encendió su bucle al llamar a update_beam()")
	expect(placed <= BEAM_FOLLOW_TOLERANCE,
			"la voz del haz quedó a %.3f m del punto de contacto (tope %.2f)"
			% [placed, BEAM_FOLLOW_TOLERANCE])
	expect(followed <= BEAM_FOLLOW_TOLERANCE,
			"la voz del haz no siguió al punto de contacto: quedó a %.3f m" % followed)
	expect(still == 1, "mover el punto de contacto creó un segundo bucle")
	expect(after == 0, "hide_beam() dejó el bucle del haz sonando")
	expect(silent, "la voz del haz sigue reproduciendo después de hide_beam()")

	# El asedio elige el otro timbre por el nombre del nodo, y su bucle es el suyo.
	action.configure_beam(&"SiegeBeam", 0.6, Color.ORANGE)
	action.update_beam(origin, contact)
	await wait_physics(1)
	var siege := _pool.loop_count(&"siege_loop")
	action.hide_beam()
	await wait_physics(1)
	print("  [7c] asedio: %d bucle de `siege_loop` mientras dura, %d después"
			% [siege, _pool.loop_count(&"siege_loop")])
	expect(siege == 1, "el haz de asedio no usó `siege_loop`")
	expect(_pool.loop_count(&"siege_loop") == 0, "el bucle del asedio no se cortó")

	action.queue_free()
	await wait_frames(2)


## 7d — El tope de `enemies` con todo encendido a la vez: haz + servos +
## telegrafía + las dos chispas. Son las seis voces de la categoría y ni una más.
func _check_loop_budget() -> void:
	var limit := _pool.category_limit(AudioPool.CATEGORY_ENEMIES)
	# El jefe declarando lo suyo: servo, carga de telegrafía y una pisada.
	_pool.register_source(AudioPool.CATEGORY_ENEMIES, self, &"stub_voices")
	stub_voices_count = 3
	var beam := _pool.play_loop(&"laser_loop", Vector3(20.0, 0.0, 0.0))
	var anchors: Array[Node3D] = []
	var sparks := 0
	for index: int in 3:
		var anchor := Node3D.new()
		anchor.name = "SparkAnchor%d" % index
		add_child(anchor)
		anchor.global_position = Vector3(float(index) * 4.0, 2.0, 0.0)
		anchors.append(anchor)
		_pool.set_anchored_loop(&"sparks_loop", anchor, true)
		sparks = _pool.loop_count(&"sparks_loop")
	await wait_physics(1)
	var total := _pool.category_voices(AudioPool.CATEGORY_ENEMIES)
	var extra := _pool.play_event(&"part_fall", Vector3(5.0, 0.0, 5.0))
	print("  [7d] tope de enemies: 3 voces del jefe + %s + %d chispas = %d/%d · una fractura más: %s"
			% ["haz" if beam != null else "sin haz", sparks, total, limit,
			"rechazada" if extra == null else "servida"])
	expect(beam != null, "no entró el bucle del haz con el jefe usando 3 voces")
	expect(sparks == 2,
			"encendieron %d bucles de chispas y `max_loops` es 2" % sparks)
	expect(total <= limit,
			"la categoría 'enemies' llegó a %d voces con haz, servos y chispas (tope %d)"
			% [total, limit])
	expect(extra == null,
			"el pool sirvió una fractura con la categoría llena: los bucles no cuentan")
	stub_voices_count = 0
	_pool.unregister_source(self)
	_pool.stop_all()
	for anchor: Node3D in anchors:
		anchor.queue_free()
	await wait_frames(2)


## 7e — Ninguna voz de bucle sobrevive al enemigo. Es la fuga que importa: el haz
## no pasa por `hide_beam()` cuando al jefe lo liberan con la ventana abierta.
func _check_loop_leak() -> void:
	var anchor := Node3D.new()
	anchor.name = "DoomedEnemy"
	add_child(anchor)
	anchor.global_position = Vector3(12.0, 4.0, 3.0)
	await wait_frames(1)
	var voice := _pool.play_loop(&"laser_loop", anchor.global_position, anchor)
	_pool.set_anchored_loop(&"sparks_loop", anchor, true)
	await wait_physics(1)
	var before := _pool.active_loops()
	var playing_before := _pool.category_voices(AudioPool.CATEGORY_ENEMIES)
	anchor.queue_free()
	await wait_frames(2)
	await wait_physics(2)
	var after := _pool.active_loops()
	var playing_after := _pool.category_voices(AudioPool.CATEGORY_ENEMIES)
	var voice_alive := is_instance_valid(voice) and voice.playing
	print("  [7e] enemigo liberado con el haz encendido: %d bucles y %d voces antes, %d y %d después (voz viva %s)"
			% [before, playing_before, after, playing_after, str(voice_alive)])
	expect(before == 2, "la prueba no vale: no se encendieron los dos bucles")
	expect(after == 0, "quedaron %d bucles sonando tras liberar al enemigo" % after)
	expect(playing_after == 0,
			"quedaron %d voces de 'enemies' sonando tras liberar al enemigo" % playing_after)
	expect(not voice_alive, "la voz del haz sigue reproduciendo sin enemigo")


## Primera voz retenida de una categoría, que es la del bucle recién encendido.
func _beam_voice_at(category: StringName) -> AudioStreamPlayer3D:
	for node: Node in _pool.get_children():
		var player := node as AudioStreamPlayer3D
		if player == null or not player.playing:
			continue
		if player.bus == String(AudioPool.CATEGORY_BUSES[category]) and _pool.is_loop(player):
			return player
	return null


## Voces que el check declara como fuente externa; lo lee [method _check_external_cap].
func stub_voices() -> int:
	return stub_voices_count


## 8 — El [MusicDirector]: duración exacta de los stems, tabla de §5.3, cruces sin
## saltos y deriva del reloj de la mezcla (`docs/13` §10.3.4, .5 y §11 riesgo 8).
func _check_music() -> void:
	_music = MusicDirector.new()
	_music.name = "MusicDirector"
	# El piloto automático de la intensidad se apaga para todo lo que mide la
	# **tabla** de §5.3: el desvío por distancia y daño se suma a los dB de la
	# tabla, así que con él encendido un cruce a `BATTLE` no termina en 0 dB sino
	# en −6, y la rampa de intensidad se superpone al cruce y lo llena de
	# reversiones. Son dos cosas distintas y se miden por separado: la tabla acá,
	# el piloto automático en 8g, que lo enciende y lo vuelve a apagar.
	_music.auto_intensity = false
	add_child(_music)
	await wait_frames(2)

	# 8a — Los tres stems existen y miden exactamente 64 s, al sample.
	expect(_music.stem_count() == MusicDirector.STEMS.size(),
			"el MusicDirector cargó %d stems y `docs/13` §5.3 pide %d (regeneralos con tools/generate_music.gd)"
			% [_music.stem_count(), MusicDirector.STEMS.size()])
	if _music.stem_count() != MusicDirector.STEMS.size():
		return
	var lengths: Array[float] = []
	var report: Array[String] = []
	for index: int in MusicDirector.STEMS.size():
		var length := _music.stem_length(index)
		lengths.append(length)
		report.append("%s %.6f s" % [String(MusicDirector.STEMS[index]), length])
		expect_near(length, STEM_SECONDS, STEM_TOLERANCE,
				"la duración del stem '%s'" % String(MusicDirector.STEMS[index]))
	print("  [8] stems: %s" % ", ".join(report))
	expect(_stems_match(lengths),
			"los tres stems no miden lo mismo (%s): AudioStreamSynchronized los desfasa"
			% ", ".join(report))
	expect(_music.playing, "el MusicDirector no arrancó a sonar")

	# 8b — La transición INTRO -> BATTLE -> fase 3, tramo por tramo.
	await _probe_transition("INTRO", MusicDirector.MIX_INTRO,
			func() -> void: Events.round_state_changed.emit(Global.RoundState.INTRO))
	await _probe_transition("BATTLE p1", MusicDirector.MIX_BATTLE_EARLY,
			func() -> void: Events.round_state_changed.emit(Global.RoundState.BATTLE))
	await _probe_transition("fase p3_fury", MusicDirector.MIX_BATTLE_LATE,
			func() -> void: Events.enemy_phase_changed.emit(null, &"p3_fury"))

	# 8c — La intensidad mueve `tension` ±6 dB sin cambiar de capa. A mano: lo que
	# se mide es el recorrido completo del desvío.
	var before_intensity := _music.stem_volume_db(MusicDirector.STEM_TENSION)
	_music.set_intensity(1.0)
	await _wait_seconds(MusicDirector.INTENSITY_SECONDS + 0.2)
	var high := _music.stem_volume_db(MusicDirector.STEM_TENSION)
	_music.set_intensity(0.0)
	await _wait_seconds(MusicDirector.INTENSITY_SECONDS + 0.2)
	var low := _music.stem_volume_db(MusicDirector.STEM_TENSION)
	_music.set_intensity(0.5)
	await _wait_seconds(MusicDirector.INTENSITY_SECONDS + 0.2)
	print("  [8] intensidad: 0.5 -> %.2f dB, 1.0 -> %.2f dB, 0.0 -> %.2f dB"
			% [before_intensity, high, low])
	expect_near(high - before_intensity, MusicDirector.INTENSITY_RANGE_DB, 0.2,
			"la intensidad al máximo sobre `tension`")
	expect_near(before_intensity - low, MusicDirector.INTENSITY_RANGE_DB, 0.2,
			"la intensidad al mínimo sobre `tension`")

	await _check_intensity_drive()

	# 8d — El ambiente del `AudioPool` se encendió con `BATTLE`.
	if _pool != null:
		print("  [8] ambiente nocturno en BATTLE: %s" % str(_pool.is_ambience_playing()))
		expect(_pool.is_ambience_playing(),
				"el ambiente de ciudad no arrancó al entrar en BATTLE (`docs/13` §5)")

	# 8e — El reloj de la mezcla no deriva: se salta a los 30 s y se mide contra el
	# reloj de pared. Es lo más cerca que se puede estar de «los tres stems en la
	# misma posición» con la API de 4.7 (ver la nota de cabecera).
	_music.seek(SYNC_PROBE_SECONDS)
	await wait_frames(2)
	var start_position := _music.get_playback_position()
	var start_usec := Time.get_ticks_usec()
	await _wait_seconds(SYNC_WINDOW)
	var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
	var advanced := _music.get_playback_position() - start_position
	var drift := absf(advanced - elapsed)
	print("  [8] tras saltar a %.1f s: la mezcla avanzó %.4f s en %.4f s de reloj (deriva %.4f s = %.2f %%, buffer %.4f s)"
			% [SYNC_PROBE_SECONDS, advanced, elapsed, drift, 100.0 * drift / maxf(elapsed, 0.001),
			AudioServer.get_output_latency()])
	expect(drift <= SYNC_TOLERANCE * elapsed,
			"el reloj de la mezcla derivó %.4f s en %.1f s (tope %.0f %%)"
			% [drift, SYNC_WINDOW, 100.0 * SYNC_TOLERANCE])

	# 8f — Victoria: los tres stems se van y suena el sting.
	Events.round_state_changed.emit(Global.RoundState.VICTORY)
	await wait_frames(2)
	print("  [8] victoria: sting %s" % str(_music.is_sting_playing()))
	expect(_music.is_sting_playing(),
			"`VICTORY` no disparó el sting (`docs/13` §5.3)")
	await _teardown_audio()


## Deja el audio de WP-27 apagado y los nodos fuera del árbol.
##
## No es higiene de más: un [Tween] vivo o una reproducción abierta al salir del
## proceso es exactamente lo que Godot reporta como «instancias filtradas» y
## «recursos en uso» al cerrar, y eso ensucia el log de cualquier suite.
func _teardown_audio() -> void:
	if _music != null and is_instance_valid(_music):
		_music.stop()
		_music.set_intensity(0.5)
		_music.queue_free()
		_music = null
	if _pool != null and is_instance_valid(_pool):
		_pool.stop_all()
		_pool.queue_free()
		_pool = null
	await wait_frames(2)


## 8g — La intensidad **cableada** (`docs/13` §5.3): un golpe la sube y se apaga
## sola en cinco segundos, sin saltos y sin jefe en la escena.
##
## Las tres cosas que se verifican son las tres que pueden romperse solas: que el
## daño llegue a la música (antes `set_intensity()` no lo llamaba nadie), que la
## memoria de cinco segundos se vacíe de verdad —un acumulador que no decae deja
## la música arriba para siempre— y que sin enemigo la cuenta no explote ni se
## quede con una referencia muerta, que es el caso normal entre rondas.
func _check_intensity_drive() -> void:
	_music.auto_intensity = true
	# Sin jefe en la escena, la mitad «cercanía» tiene que ser 0 y quedarse ahí.
	await _wait_seconds(INTENSITY_SETTLE_SECONDS)
	var idle := _music.intensity_terms()
	var idle_db := _music.stem_volume_db(MusicDirector.STEM_TENSION)

	Events.drone_damaged.emit(MusicDirector.DAMAGE_FULL_HP, Vector3(3.0, 1.0, 2.0))
	var samples: Array[float] = []
	var heat: Array[float] = []
	var worst_step := 0.0
	var out_of_range := 0
	var last_usec := Time.get_ticks_usec()
	var previous := _music.stem_volume_db(MusicDirector.STEM_TENSION)
	var deadline := Time.get_ticks_usec() + int(INTENSITY_WINDOW_SECONDS * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last_usec) / 1000000.0
		if dt < STEM_SAMPLE_GAP:
			continue
		last_usec = now
		var value := _music.stem_volume_db(MusicDirector.STEM_TENSION)
		worst_step = maxf(worst_step, absf(value - previous) * STEM_STEP_WINDOW / maxf(dt, 0.000001))
		previous = value
		samples.append(value)
		var terms := _music.intensity_terms()
		heat.append(terms.y)
		if terms.x < 0.0 or terms.x > 1.0 or terms.y < 0.0 or terms.y > 1.0 \
				or not is_finite(value):
			out_of_range += 1

	# La curva sube hasta un pico y vuelve: se mide la monotonía de cada tramo.
	var peak := 0
	for index: int in samples.size():
		if samples[index] > samples[peak]:
			peak = index
	var rises := 0
	var falls := 0
	for index: int in range(1, samples.size()):
		var step := samples[index] - samples[index - 1]
		if index <= peak and step < -STEM_MONOTONIC_EPSILON:
			rises += 1
		elif index > peak and step > STEM_MONOTONIC_EPSILON:
			falls += 1
	var top_heat := 0.0
	for value: float in heat:
		top_heat = maxf(top_heat, value)
	var final_heat := heat[heat.size() - 1] if not heat.is_empty() else 1.0
	var final_db := _music.stem_volume_db(MusicDirector.STEM_TENSION)

	print("  [8g] intensidad cableada: en reposo cercanía %.2f, calor %.2f (%.2f dB) · tras un golpe de %.0f hp el calor llega a %.2f y baja a %.2f en %.1f s · `tension` %.2f -> %.2f -> %.2f dB · salto máximo %.3f dB/20 ms · %d reversiones subiendo, %d bajando"
			% [idle.x, idle.y, idle_db, MusicDirector.DAMAGE_FULL_HP, top_heat, final_heat,
			INTENSITY_WINDOW_SECONDS, idle_db, samples[peak] if not samples.is_empty() else NAN,
			final_db, worst_step, rises, falls])
	expect(is_zero_approx(idle.x),
			"sin jefe en la escena la cercanía dio %.3f y tiene que ser 0" % idle.x)
	expect(is_zero_approx(idle.y), "la intensidad arrancó con calor %.3f" % idle.y)
	expect(out_of_range == 0,
			"%d muestras con la intensidad fuera de [0, 1] o con dB no finitos" % out_of_range)
	expect(top_heat >= 0.9,
			"un golpe de %.0f hp dejó el calor en %.2f y tendría que saturarlo"
			% [MusicDirector.DAMAGE_FULL_HP, top_heat])
	expect(final_heat <= INTENSITY_RESIDUAL,
			"a los %.1f s del golpe queda calor %.3f: la memoria de %.0f s no se vacía"
			% [INTENSITY_WINDOW_SECONDS, final_heat, MusicDirector.DAMAGE_MEMORY_SECONDS])
	expect(samples[peak] > idle_db + 1.0,
			"el golpe no movió `tension`: pico %.2f dB contra %.2f en reposo"
			% [samples[peak], idle_db])
	expect_near(final_db, idle_db, 0.3,
			"`tension` no volvió a su sitio después de que el daño se enfriara")
	expect(worst_step <= STEM_MAX_STEP_DB,
			"la intensidad movió `tension` %.2f dB en 20 ms (tope %.1f)"
			% [worst_step, STEM_MAX_STEP_DB])
	expect(rises == 0 and falls == 0,
			"la curva de intensidad no es monótona por tramos: %d reversiones subiendo y %d bajando"
			% [rises, falls])
	_music.auto_intensity = false


## Lleva a los stems a una fila de la tabla y vigila el cruce: monotonía hacia el
## objetivo y ningún salto de más de 6 dB por cada 20 ms.
func _probe_transition(label: String, target: Array[float], trigger: Callable) -> void:
	var start: Array[float] = []
	for index: int in MusicDirector.STEMS.size():
		start.append(_music.stem_volume_db(index))
	trigger.call()
	var previous := start.duplicate()
	var last_usec := Time.get_ticks_usec()
	var worst_step := 0.0
	var worst_stem := -1
	var overshoot := 0.0
	var reversals := 0
	var deadline := Time.get_ticks_usec() + int((MusicDirector.CROSSFADE_SECONDS + 0.4) * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last_usec) / 1000000.0
		if dt < STEM_SAMPLE_GAP:
			continue
		last_usec = now
		for index: int in MusicDirector.STEMS.size():
			var value := _music.stem_volume_db(index)
			var step := absf(value - previous[index]) * STEM_STEP_WINDOW / maxf(dt, 0.000001)
			if step > worst_step:
				worst_step = step
				worst_stem = index
			var direction := signf(target[index] - start[index])
			if not is_zero_approx(direction):
				# Monotonía del tramo: ni se da vuelta ni se pasa del objetivo.
				if (value - previous[index]) * direction < -STEM_MONOTONIC_EPSILON:
					reversals += 1
				overshoot = maxf(overshoot, (value - target[index]) * direction)
			previous[index] = value
	var final: Array[String] = []
	for index: int in MusicDirector.STEMS.size():
		final.append("%s %.2f" % [String(MusicDirector.STEMS[index]),
				_music.stem_volume_db(index)])
		expect_near(_music.stem_volume_db(index), target[index], 0.05,
				"el stem '%s' tras cruzar a %s" % [String(MusicDirector.STEMS[index]), label])
		# El valor tiene que haber llegado al recurso, que es lo que suena.
		expect_near(_music.stem_stream_volume_db(index), _music.stem_volume_db(index), 0.01,
				"el volumen escrito en el AudioStreamSynchronized del stem '%s'"
				% String(MusicDirector.STEMS[index]))
	print("  [8] cruce a %-14s -> %s dB · salto máximo %.3f dB/20 ms%s · sobrepaso %.3f dB · %d reversiones"
			% [label, ", ".join(final), worst_step,
			"" if worst_stem < 0 else " (" + String(MusicDirector.STEMS[worst_stem]) + ")",
			maxf(overshoot, 0.0), reversals])
	expect(worst_step <= STEM_MAX_STEP_DB,
			"el cruce a %s movió un stem %.2f dB en 20 ms (tope %.1f): eso es un clic"
			% [label, worst_step, STEM_MAX_STEP_DB])
	expect(reversals == 0,
			"el cruce a %s se dio vuelta %d veces: no es monótono" % [label, reversals])
	expect(overshoot <= STEM_MONOTONIC_EPSILON,
			"el cruce a %s se pasó %.3f dB del objetivo" % [label, overshoot])


## 9 — Prueba negativa: el comparador de duraciones tiene que **fallar** con stems
## distintos. Sin esto, el criterio 5 podría estar comparando cualquier cosa y
## saliendo en verde igual.
func _check_stem_comparator() -> void:
	var equal: Array[float] = [STEM_SECONDS, STEM_SECONDS, STEM_SECONDS]
	# Una muestra a 32 kHz de diferencia: 31 µs, el desfase más chico que existe.
	var off_by_one: Array[float] = [STEM_SECONDS, STEM_SECONDS + 1.0 / 32000.0, STEM_SECONDS]
	var way_off: Array[float] = [STEM_SECONDS, STEM_SECONDS, 63.5]
	print("  [9] comparador de stems: iguales %s · una muestra %s · medio segundo %s"
			% [str(_stems_match(equal)), str(_stems_match(off_by_one)), str(_stems_match(way_off))])
	expect(_stems_match(equal), "el comparador rechaza tres stems idénticos")
	expect(not _stems_match(off_by_one),
			"el comparador acepta stems que difieren en una muestra: no detectaría el desfase")
	expect(not _stems_match(way_off),
			"el comparador acepta stems que difieren en medio segundo")


## `true` si todos los largos son iguales dentro de [constant STEM_TOLERANCE].
func _stems_match(lengths: Array[float]) -> bool:
	for index: int in range(1, lengths.size()):
		if absf(lengths[index] - lengths[0]) > STEM_TOLERANCE:
			return false
	return true


## Cede el control durante [param seconds] de reloj de pared.
func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame


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
