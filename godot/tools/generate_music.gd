## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sintetiza los tres stems de la música por capas y los dos stings en
## `assets/audio/music/*.wav` (`docs/13` §5.3 y §5.4, WP-27).
##
## Cómo regenerarlo (desde la raíz del repositorio):
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot -s res://tools/generate_music.gd
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot --editor --quit
##
## [b]Formato: WAV PCM y no OGG[/b]. Godot no expone un codificador Vorbis a
## GDScript —`AudioStreamOggVorbis` solo *lee*—, así que una herramienta headless
## sin dependencias externas no puede escribir `.ogg`. Los tres stems quedan en
## PCM de 16 bits **mono a 32 kHz**: 4.0 MiB cada uno en vez de los 11 que
## costarían en estéreo a 44.1 kHz, con el Nyquist en 16 kHz, que para pads,
## percusión seca y una radio filtrada sobra. Si algún día entra un codificador,
## se cambia el formato sin tocar la síntesis. Anotado para `docs/16`.
##
## [b]Los tres miden exactamente lo mismo[/b]: 120 BPM, 32 compases de 4/4, 64.000 s
## al sample ([constant FRAMES] muestras). Es el requisito del riesgo 8 de
## `docs/13` §11: [AudioStreamSynchronized] desfasa si los archivos no miden igual,
## y `audio_check` lo verifica al sample, no al milisegundo.
##
## [b]Armonía[/b] (la misma en los tres, `docs/13` §5.3): la menor, cuatro acordes
## de dos compases —Am · F · Dm · E5— repetidos cuatro veces. El cuarto va sin
## tercera a propósito: con sol sostenido el giro suena a cadencia clásica, y la
## nota de identidad de §1 pide «metales secos, sin épica orquestal».
##
## - `ambient` — pads oscuros con el filtro abriéndose y cerrándose lento, la radio
##   lejana de la ciudad dormida (`docs/narrativa` §2) y un pulso de sub cada dos
##   compases. Sin percusión.
## - `tension` — pulso grave a negras, arpegio apagado de cuatro notas y hi-hat de
##   ruido filtrado a contratiempo. El pad sigue debajo, a −14 dB, para que las
##   tres capas compartan de verdad la armonía y no solo el tempo.
## - `combat` — percusión seca (bombo, caja de ruido, metales cortos) y bajo con
##   distorsión leve. Ni cuerdas ni pads: cuando entra, lo que cambia es el pulso.
##
## [b]Cómo se sintetiza[/b]: osciladores por **tabla de onda** con interpolación
## lineal (una tabla «pad» de ocho armónicos con caída 1/n^1.4, una «bajo» de
## impares y una senoidal). Sumar senos por muestra costaría decenas de millones
## de llamadas a `sin()` por stem; con tabla, los tres salen en segundos y el
## resultado es idéntico salvo el rizado de la interpolación, que está 60 dB por
## debajo. Todo determinista: cada stem lleva su semilla.
##
## [b]Bucle[/b]: cada evento que cruza el final del archivo se **pliega** sobre el
## principio (ver [method _add]), así que el empalme es continuo; el log imprime la
## derivada máxima incluyendo el salto del final al principio.
extends SceneTree

## Frecuencia de muestreo de la música, en Hz. Ver la nota de formato de arriba.
const MIX_RATE: int = 32000

## Carpeta de salida.
const OUTPUT_DIR: String = "res://assets/audio/music"

## Tempo y métrica de `docs/13` §5.3.
const BPM: float = 120.0
const BEAT_SECONDS: float = 60.0 / BPM
const BAR_SECONDS: float = 4.0 * BEAT_SECONDS
const BARS: int = 32

## Duración exacta de los tres stems, en segundos y en muestras.
const DURATION: float = BAR_SECONDS * float(BARS)
const FRAMES: int = int(DURATION * float(MIX_RATE))

## Compases que dura cada acorde.
const CHORD_BARS: int = 2
const CHORD_SECONDS: float = BAR_SECONDS * float(CHORD_BARS)

## La progresión, en la menor. `bass` es la fundamental de la octava 1–2 y `notes`
## las tres voces del pad; `arp` son las cuatro notas del arpegio de `tension`.
const CHORDS: Array[Dictionary] = [
	# Am: la menor, el acorde de casa.
	{"bass": 55.00, "notes": [110.00, 130.81, 164.81], "arp": [220.00, 261.63, 329.63, 261.63]},
	# F: el VI, que baja la luz.
	{"bass": 43.65, "notes": [87.31, 110.00, 130.81], "arp": [174.61, 220.00, 261.63, 220.00]},
	# Dm: el iv, más oscuro todavía.
	{"bass": 36.71, "notes": [73.42, 87.31, 110.00], "arp": [146.83, 174.61, 220.00, 174.61]},
	# E5: el V **sin tercera**; deja la tensión abierta sin sonar a película.
	{"bass": 41.20, "notes": [82.41, 123.47, 164.81], "arp": [164.81, 246.94, 329.63, 246.94]},
]

## Muestras de las tablas de onda.
const TABLE_SIZE: int = 2048

## Objetivo de valor eficaz de cada stem, en dBFS. No se normalizan al mismo pico:
## un pad sostenido y una percusión seca con el mismo pico se oyen a volúmenes
## completamente distintos, y la tabla de dB de §5.3 supone que las tres capas
## están equilibradas entre sí.
const TARGET_RMS_DBFS: Dictionary[String, float] = {
	"ambient": -24.0,
	"tension": -21.0,
	"combat": -18.0,
}

## Techo de pico, en dBFS. `docs/13` §10.3 pide picos por debajo de −0.5; acá se
## deja un decibel entero de margen para la cuantización a 16 bits.
const PEAK_CEILING_DBFS: float = -1.0

## Semilla base; cada pieza le suma la suya.
const BASE_SEED: int = 0x4D_55_53_43

## Los stings de victoria y derrota, que van en un reproductor aparte.
const STINGS: Array[Dictionary] = [
	{"name": "sting_victory", "dur": 2.6, "seed": 21},
	{"name": "sting_defeat", "dur": 3.2, "seed": 22},
]

## Formantes de las vocales de la radio lejana, en Hz. Igual que en
## `tools/generate_city_sounds.gd`: la radio del ambiente musical y la del ambiente
## de ciudad son la misma voz, para que suene a la misma emisora.
const VOWELS: Array[Vector3] = [
	Vector3(730.0, 1090.0, 2440.0),
	Vector3(530.0, 1840.0, 2480.0),
	Vector3(390.0, 1990.0, 2550.0),
	Vector3(570.0, 840.0, 2410.0),
	Vector3(440.0, 1020.0, 2240.0),
]

## Peso relativo de cada formante.
const FORMANT_GAINS: Array[float] = [1.0, 0.55, 0.25]

## Peso de cada voz del pad, de la más grave a la más aguda.
const PAD_VOICE_GAINS: Array[float] = [1.0, 0.8, 0.62]

## Parámetros del importador. `compress/mode = 0` es PCM sin comprimir y
## `edit/loop_mode = 2` es el bucle hacia adelante (el 1 es «deshabilitado»).
const IMPORT_PARAMS: Dictionary[String, Variant] = {
	"force/8_bit": false,
	"force/mono": false,
	"force/max_rate": false,
	"force/max_rate_hz": 44100,
	"edit/trim": false,
	"edit/normalize": false,
	"edit/loop_mode": 0,
	"edit/loop_begin": 0,
	"edit/loop_end": -1,
	"compress/mode": 0,
}

var _pad_table: PackedFloat32Array = PackedFloat32Array()
var _bass_table: PackedFloat32Array = PackedFloat32Array()
var _sine_table: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var err := DirAccess.make_dir_recursive_absolute(absolute)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("No se pudo crear %s: %s" % [absolute, error_string(err)])
		quit(1)
		return
	_build_tables()

	print("Stems: %d BPM, %d compases, %.3f s, %d muestras a %d Hz"
			% [int(BPM), BARS, DURATION, FRAMES, MIX_RATE])
	var total := 0
	var lengths: Array[int] = []
	for stem: String in ["ambient", "tension", "combat"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = BASE_SEED + hash(stem)
		var samples := _synth_stem(stem, rng)
		samples = _master(samples, float(TARGET_RMS_DBFS[stem]))
		var written := _write(stem, samples, true)
		if written < 0:
			quit(1)
			return
		total += written
		lengths.append(samples.size())
		print("  %-8s %.6f s · %d muestras · RMS %6.2f dBFS · pico %6.2f dBFS · |Δ|máx %.4f · bucle"
				% [stem, float(samples.size()) / float(MIX_RATE), samples.size(),
				_rms_db(samples), _peak_db(samples), _max_slope(samples, true)])

	for row: Dictionary in STINGS:
		var sting_name := String(row["name"])
		var frames := int(round(float(row["dur"]) * MIX_RATE))
		var rng := RandomNumberGenerator.new()
		rng.seed = BASE_SEED + int(row["seed"])
		var samples := _synth_sting(sting_name, frames, float(row["dur"]), rng)
		samples = _master(samples, -16.0)
		var written := _write(sting_name, samples, false)
		if written < 0:
			quit(1)
			return
		total += written
		print("  %-8s %.6f s · %d muestras · RMS %6.2f dBFS · pico %6.2f dBFS · |Δ|máx %.4f"
				% [sting_name, float(frames) / float(MIX_RATE), frames, _rms_db(samples),
				_peak_db(samples), _max_slope(samples, false)])

	var same := lengths.count(FRAMES) == lengths.size()
	print("Música: %d archivos, %d Hz, PCM 16 bits mono, %.1f KiB · stems del mismo largo: %s"
			% [3 + STINGS.size(), MIX_RATE, float(total) / 1024.0, str(same)])
	if not same:
		push_error("Los stems no miden lo mismo: %s" % str(lengths))
		quit(1)
		return
	print("Listo. Importá con: godot --headless --path godot --editor --quit")
	quit(0)


# --------------------------------------------------------------------------
# Stems
# --------------------------------------------------------------------------

func _synth_stem(stem: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match stem:
		"ambient":
			return _synth_ambient(rng)
		"tension":
			return _synth_tension(rng)
		"combat":
			return _synth_combat(rng)
	return _silence(FRAMES)


## `ambient`: pads oscuros con filtro lento, radio lejana y sub cada dos compases.
func _synth_ambient(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _pads(0.9, 3)
	# El filtro respira una vez cada ocho compases; el periodo se cuadra al
	# archivo para que el bucle no lo corte a mitad de camino.
	samples = _sweep_lowpass(samples, 260.0, 1150.0, _snap_to_period(1.0 / 16.0, DURATION))
	# Pulso de sub cada dos compases: el latido de la ciudad dormida.
	var slots := int(DURATION / CHORD_SECONDS)
	for slot: int in slots:
		var chord := CHORDS[slot % CHORDS.size()]
		_add_sub_pulse(samples, float(slot) * CHORD_SECONDS, float(chord["bass"]), 0.55, 2.2)
	# Y la radio, dos frases por vuelta de progresión.
	var radio := _radio_voice(rng, FRAMES, DURATION, [
		Vector2(10.0, 15.5), Vector2(34.0, 40.0), Vector2(52.0, 56.5)])
	for index: int in FRAMES:
		samples[index] += radio[index] * 0.5
	return samples


## `tension`: pulso grave a negras, arpegio apagado y hi-hat a contratiempo.
func _synth_tension(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# El pad sigue debajo, apagado: es lo que hace que el cruce con `ambient` no se
	# note como un cambio de tema sino como una capa que se enciende.
	var samples := _pads(0.22, 2)
	samples = _sweep_lowpass(samples, 220.0, 620.0, _snap_to_period(1.0 / 16.0, DURATION))

	var beats := int(DURATION / BEAT_SECONDS)
	for beat: int in beats:
		var time := float(beat) * BEAT_SECONDS
		var chord := CHORDS[int(time / CHORD_SECONDS) % CHORDS.size()]
		# Negra grave: el pulso. En el primer tiempo del compás pega más fuerte.
		var accent := 1.0 if beat % 4 == 0 else 0.72
		_add_bass_pulse(samples, time, float(chord["bass"]), 0.55 * accent, 7.0, 0.0)
		# Arpegio en corcheas: cuatro notas, muy apagadas.
		var arp := chord["arp"] as Array
		for eighth: int in 2:
			var step := (beat * 2 + eighth) % arp.size()
			_add_pluck(samples, time + float(eighth) * BEAT_SECONDS * 0.5,
					float(arp[step]), 0.16, 12.0)
		# Hi-hat a contratiempo, con la semilla decidiendo cuáles se saltan.
		if rng.randf() < 0.85:
			_add_hat(samples, time + BEAT_SECONDS * 0.5, rng.randf_range(0.05, 0.085), rng)
	return samples


## `combat`: percusión seca, metales cortos y bajo con distorsión leve.
func _synth_combat(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(FRAMES)
	var bars := BARS
	for bar: int in bars:
		var bar_time := float(bar) * BAR_SECONDS
		var chord := CHORDS[int(bar_time / CHORD_SECONDS) % CHORDS.size()]
		# Bombo en 1 y 3, más un rebote en el «y» del 3: seco, sin cola.
		_add_kick(samples, bar_time, 1.0)
		_add_kick(samples, bar_time + BEAT_SECONDS * 2.0, 0.9)
		_add_kick(samples, bar_time + BEAT_SECONDS * 2.75, 0.45)
		# Caja de ruido en 2 y 4.
		_add_snare(samples, bar_time + BEAT_SECONDS, 0.85, rng)
		_add_snare(samples, bar_time + BEAT_SECONDS * 3.0, 0.9, rng)
		# Bajo distorsionado en corcheas, con silencios: lo que empuja.
		for eighth: int in 8:
			if eighth == 3 or eighth == 6:
				continue
			var time := bar_time + float(eighth) * BEAT_SECONDS * 0.5
			var octave := 2.0 if eighth % 4 == 2 else 1.0
			_add_bass_pulse(samples, time, float(chord["bass"]) * octave,
					0.5 if eighth % 2 == 0 else 0.34, 9.0, 0.55)
		# Metales cortos en semicorcheas sueltas: chapa golpeada, no platillos.
		for sixteenth: int in 16:
			if rng.randf() > 0.22:
				continue
			_add_metal(samples, bar_time + float(sixteenth) * BEAT_SECONDS * 0.25,
					rng.randf_range(0.10, 0.26), rng)
	return samples


# --------------------------------------------------------------------------
# Bloques de síntesis
# --------------------------------------------------------------------------

## Colchón de pads de toda la progresión.
##
## Se renderiza **por acorde**, con medio segundo de solape a cada lado, en vez de
## dejar doce osciladores corriendo todo el archivo: cuesta la cuarta parte y el
## cruce sale igual de suave. [param voices] es cuántas copias desafinadas lleva
## cada nota.
func _pads(gain: float, voices: int) -> PackedFloat32Array:
	var samples := _silence(FRAMES)
	var slots := int(DURATION / CHORD_SECONDS)
	var overlap := 0.9
	for slot: int in slots:
		var chord := CHORDS[slot % CHORDS.size()]
		var start := float(slot) * CHORD_SECONDS - overlap
		var length := CHORD_SECONDS + overlap * 2.0
		var notes := chord["notes"] as Array
		for note_index: int in notes.size():
			var frequency := float(notes[note_index])
			# La voz de arriba entra un poco más tarde y más suave: da movimiento
			# sin agregar notas.
			var voice_gain := gain * PAD_VOICE_GAINS[note_index]
			for voice: int in voices:
				var detune := 1.0 + (float(voice) - float(voices - 1) * 0.5) * 0.0032
				_add_wave(samples, _pad_table, start, length, frequency * detune,
						voice_gain / float(voices), overlap)
	return samples


## Escribe una nota de tabla de onda con envolvente de coseno alzado en los
## extremos. [param fade] son los segundos de entrada y de salida.
func _add_wave(samples: PackedFloat32Array, table: PackedFloat32Array, start: float,
		length: float, frequency: float, gain: float, fade: float) -> void:
	var frames := int(length * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var step := frequency * float(TABLE_SIZE) / float(MIX_RATE)
	var phase := 0.0
	var fade_frames := maxf(fade * float(MIX_RATE), 1.0)
	for offset: int in frames:
		var envelope := minf(float(offset) / fade_frames,
				float(frames - offset) / fade_frames)
		envelope = clampf(envelope, 0.0, 1.0)
		# Coseno alzado: la derivada es cero en los extremos, así que ni el
		# principio ni el final de la nota chasquean.
		envelope = 0.5 - 0.5 * cos(PI * envelope)
		_add(samples, start_frame + offset, _lookup(table, phase) * gain * envelope)
		phase += step
	return


## Golpe de sub: seno que cae de tono. [param decay] es el ritmo de la caída.
func _add_sub_pulse(samples: PackedFloat32Array, start: float, frequency: float,
		gain: float, decay: float) -> void:
	var frames := int(1.6 * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var phase := 0.0
	for offset: int in frames:
		var t := float(offset) * inverse_rate
		phase += frequency * lerpf(1.3, 0.92, clampf(t * 3.0, 0.0, 1.0)) \
				* float(TABLE_SIZE) * inverse_rate
		var attack := clampf(t / 0.012, 0.0, 1.0)
		_add(samples, start_frame + offset,
				_lookup(_sine_table, phase) * gain * attack * exp(-decay * t))
	return


## Pulso de bajo con tabla de impares y distorsión opcional ([param drive]).
func _add_bass_pulse(samples: PackedFloat32Array, start: float, frequency: float,
		gain: float, decay: float, drive: float) -> void:
	var frames := int(minf(0.6, BEAT_SECONDS * 1.2) * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var step := frequency * float(TABLE_SIZE) * inverse_rate
	var phase := 0.0
	for offset: int in frames:
		var t := float(offset) * inverse_rate
		var value := _lookup(_bass_table, phase)
		if drive > 0.0:
			# `tanh` con ganancia: redondea los picos en vez de recortarlos, que es
			# la diferencia entre «distorsión leve» y «aliasing».
			value = tanh(value * (1.0 + drive * 3.0)) / (1.0 + drive)
		var attack := clampf(t / 0.004, 0.0, 1.0)
		_add(samples, start_frame + offset, value * gain * attack * exp(-decay * t))
		phase += step
	return


## Nota pulsada y apagada del arpegio: tabla de pad con caída rápida y sin brillo.
func _add_pluck(samples: PackedFloat32Array, start: float, frequency: float,
		gain: float, decay: float) -> void:
	var frames := int(0.35 * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var step := frequency * float(TABLE_SIZE) * inverse_rate
	var phase := 0.0
	var state := 0.0
	var alpha := clampf(1.0 - exp(-TAU * 1300.0 / float(MIX_RATE)), 0.0, 1.0)
	for offset: int in frames:
		var t := float(offset) * inverse_rate
		state += alpha * (_lookup(_pad_table, phase) - state)
		var attack := clampf(t / 0.003, 0.0, 1.0)
		_add(samples, start_frame + offset, state * gain * attack * exp(-decay * t))
		phase += step
	return


## Hi-hat: ruido pasa-altos muy corto.
func _add_hat(samples: PackedFloat32Array, start: float, gain: float,
		rng: RandomNumberGenerator) -> void:
	var frames := int(0.07 * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var state := 0.0
	var alpha := clampf(1.0 - exp(-TAU * 5200.0 / float(MIX_RATE)), 0.0, 1.0)
	for offset: int in frames:
		var t := float(offset) * inverse_rate
		var white := rng.randf_range(-1.0, 1.0)
		state += alpha * (white - state)
		var attack := clampf(t / 0.0006, 0.0, 1.0)
		_add(samples, start_frame + offset, (white - state) * gain * attack * exp(-70.0 * t))
	return


## Bombo seco: seno que cae de 110 a 42 Hz en 40 ms, con un clic de ataque.
func _add_kick(samples: PackedFloat32Array, start: float, gain: float) -> void:
	var frames := int(0.34 * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var phase := 0.0
	for offset: int in frames:
		var t := float(offset) * inverse_rate
		var frequency := lerpf(110.0, 42.0, clampf(t / 0.04, 0.0, 1.0))
		phase += frequency * float(TABLE_SIZE) * inverse_rate
		var attack := clampf(t / 0.0015, 0.0, 1.0)
		var click := 0.22 * exp(-420.0 * t)
		_add(samples, start_frame + offset,
				(_lookup(_sine_table, phase) * exp(-14.0 * t) + click) * gain * attack)
	return


## Caja de ruido: banda de ruido con un cuerpo de 190 Hz, cortísima.
func _add_snare(samples: PackedFloat32Array, start: float, gain: float,
		rng: RandomNumberGenerator) -> void:
	var frames := int(0.22 * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var state := 0.0
	var alpha := clampf(1.0 - exp(-TAU * 2400.0 / float(MIX_RATE)), 0.0, 1.0)
	var phase := 0.0
	for offset: int in frames:
		var t := float(offset) * inverse_rate
		state += alpha * (rng.randf_range(-1.0, 1.0) - state)
		phase += 190.0 * float(TABLE_SIZE) * inverse_rate
		var attack := clampf(t / 0.001, 0.0, 1.0)
		var body := 0.45 * _lookup(_sine_table, phase) * exp(-38.0 * t)
		_add(samples, start_frame + offset, (state * exp(-26.0 * t) + body) * gain * attack)
	return


## Metal corto: tres parciales inarmónicos golpeados. Es chapa, no platillo.
func _add_metal(samples: PackedFloat32Array, start: float, gain: float,
		rng: RandomNumberGenerator) -> void:
	var frames := int(0.30 * MIX_RATE)
	var start_frame := int(start * MIX_RATE)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var base := rng.randf_range(620.0, 1450.0)
	# Relaciones inarmónicas: lo que hace que una chapa suene a chapa.
	var ratios: Array[float] = [1.0, 2.41, 3.83]
	var phases := PackedFloat32Array()
	phases.resize(ratios.size())
	for offset: int in frames:
		var t := float(offset) * inverse_rate
		var value := 0.0
		for partial: int in ratios.size():
			phases[partial] += base * ratios[partial] * float(TABLE_SIZE) * inverse_rate
			value += _lookup(_sine_table, phases[partial]) * exp(-(24.0 + 14.0 * float(partial)) * t) \
					/ float(ratios.size())
		var attack := clampf(t / 0.0008, 0.0, 1.0)
		_add(samples, start_frame + offset, value * gain * attack)
	return


# --------------------------------------------------------------------------
# Stings
# --------------------------------------------------------------------------

## Los dos remates de ronda. Cortos, del mismo material que los stems: victoria
## sube, derrota baja y se apaga como una señal que se corta.
func _synth_sting(sting_name: String, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	if sting_name == "sting_victory":
		# Am ascendente con la quinta arriba: no es un fanfarria, es «seguís vivo».
		var notes: Array[float] = [110.0, 164.81, 220.0, 329.63]
		for step: int in notes.size():
			_add_wave(samples, _pad_table, float(step) * 0.16, duration - float(step) * 0.16,
					notes[step], 0.34, 0.5)
		_add_sub_pulse(samples, 0.0, 55.0, 0.6, 1.6)
		for index: int in frames:
			var t := float(index) * inverse_rate
			samples[index] *= _envelope(t, duration, 0.01, 1.1)
	else:
		# Derrota: acorde descendente, un golpe grave y la estática del corte.
		var notes: Array[float] = [164.81, 130.81, 110.0, 82.41]
		for step: int in notes.size():
			_add_wave(samples, _pad_table, float(step) * 0.22, duration - float(step) * 0.22,
					notes[step], 0.32, 0.6)
		_add_sub_pulse(samples, 0.05, 41.2, 0.7, 1.1)
		var state := 0.0
		var alpha := clampf(1.0 - exp(-TAU * 2600.0 / float(MIX_RATE)), 0.0, 1.0)
		for index: int in frames:
			var t := float(index) * inverse_rate
			state += alpha * (rng.randf_range(-1.0, 1.0) - state)
			# La estática entra al final: la señal se va antes que el acorde.
			var cut := clampf((t - duration * 0.55) / 0.5, 0.0, 1.0)
			samples[index] = samples[index] * (1.0 - 0.7 * cut) + (state * 0.22 * cut)
			samples[index] *= _envelope(t, duration, 0.008, 0.45)
	return samples


# --------------------------------------------------------------------------
# Radio lejana
# --------------------------------------------------------------------------

## Voz de radio sintética: tren de pulsos glotales por tres resonadores de
## formante y envolvente silábica, dentro de las [param phrases] indicadas.
##
## No dice nada: encadena vocales a ritmo de habla. Es la misma voz que el
## ambiente de ciudad de `tools/generate_city_sounds.gd`.
func _radio_voice(rng: RandomNumberGenerator, frames: int, duration: float,
		phrases: Array[Vector2]) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var pitch := rng.randf_range(104.0, 128.0)
	var phase := 0.0
	var formant_state: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var vowel: Vector3 = VOWELS[0]
	var syllable_end := 0.0
	var syllable_start := 0.0
	var syllable_gain := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var talking := false
		for phrase: Vector2 in phrases:
			if t >= phrase.x and t < phrase.y:
				talking = true
				break
		if not talking:
			syllable_end = t
			continue
		if t >= syllable_end:
			syllable_start = t
			syllable_end = t + rng.randf_range(0.12, 0.27)
			vowel = VOWELS[rng.randi_range(0, VOWELS.size() - 1)]
			syllable_gain = 0.0 if rng.randf() < 0.25 else rng.randf_range(0.6, 1.0)
			pitch = clampf(pitch + rng.randf_range(-8.0, 8.0), 94.0, 142.0)
		phase += TAU * pitch * inverse_rate
		if phase >= TAU:
			phase -= TAU
		var glottal := 2.0 * (phase / TAU) - 1.0
		glottal = glottal - glottal * glottal * glottal * 0.6
		var voiced := 0.0
		for band: int in 3:
			var state := formant_state[band]
			var next := _resonate(glottal, state, vowel[band], 90.0 + 40.0 * float(band))
			formant_state[band] = Vector2(next, state.x)
			voiced += next * FORMANT_GAINS[band]
		var local := (t - syllable_start) / maxf(syllable_end - syllable_start, 0.001)
		samples[index] = voiced * syllable_gain * sin(PI * clampf(local, 0.0, 1.0))
	samples = _bandpass(samples, 1050.0, 1900.0)
	for index: int in frames:
		samples[index] *= 0.30
	return samples


# --------------------------------------------------------------------------
# Tablas y utilidades
# --------------------------------------------------------------------------

## Precalcula las tres tablas de onda de [constant TABLE_SIZE] muestras.
func _build_tables() -> void:
	_pad_table = _silence(TABLE_SIZE)
	_bass_table = _silence(TABLE_SIZE)
	_sine_table = _silence(TABLE_SIZE)
	for index: int in TABLE_SIZE:
		var phase := TAU * float(index) / float(TABLE_SIZE)
		_sine_table[index] = sin(phase)
		var pad := 0.0
		for harmonic: int in range(1, 9):
			pad += pow(float(harmonic), -1.4) * sin(phase * float(harmonic))
		_pad_table[index] = pad
		var bass := 0.0
		for odd: int in range(1, 8, 2):
			bass += sin(phase * float(odd)) / float(odd)
		_bass_table[index] = bass
	_pad_table = _normalize(_pad_table, 0.0)
	_bass_table = _normalize(_bass_table, 0.0)


## Lee una tabla con interpolación lineal. [param phase] va en muestras de tabla y
## puede crecer sin límite: el módulo lo resuelve acá.
func _lookup(table: PackedFloat32Array, phase: float) -> float:
	var position := fposmod(phase, float(TABLE_SIZE))
	var first := int(position)
	var second := (first + 1) % TABLE_SIZE
	var blend := position - float(first)
	return lerpf(table[first], table[second], blend)


## Suma una muestra **plegando** el índice sobre el archivo.
##
## Es lo que hace empalmable el bucle: la cola de un bombo del último compás
## aparece al principio, que es exactamente lo que oiría el jugador al volver a
## empezar. Sin esto el final del archivo se corta en seco.
func _add(samples: PackedFloat32Array, index: int, value: float) -> void:
	samples[posmod(index, samples.size())] += value


## Pasa-bajos de un polo con el corte moviéndose a [param lfo_hz].
func _sweep_lowpass(samples: PackedFloat32Array, low: float, high: float,
		lfo_hz: float) -> PackedFloat32Array:
	var out := _silence(samples.size())
	var inverse_rate := 1.0 / float(MIX_RATE)
	var state := 0.0
	for index: int in samples.size():
		var t := float(index) * inverse_rate
		var cutoff := lerpf(low, high, 0.5 + 0.5 * sin(TAU * lfo_hz * t))
		var alpha := clampf(1.0 - exp(-TAU * cutoff / float(MIX_RATE)), 0.0, 1.0)
		state += alpha * (samples[index] - state)
		out[index] = state
	return out


## Un paso de resonador de dos polos; [param state] lleva `(y₁, y₂)`.
func _resonate(input: float, state: Vector2, frequency: float, bandwidth: float) -> float:
	var r := exp(-PI * bandwidth / float(MIX_RATE))
	var w := TAU * frequency / float(MIX_RATE)
	return input * (1.0 - r * r) + 2.0 * r * cos(w) * state.x - r * r * state.y


## Pasa-banda de dos polos, normalizado a pico 1.
func _bandpass(samples: PackedFloat32Array, centre: float,
		bandwidth: float) -> PackedFloat32Array:
	var out := _silence(samples.size())
	var state := Vector2.ZERO
	var peak := 0.0
	for index: int in samples.size():
		var value := _resonate(samples[index], state, centre, bandwidth)
		state = Vector2(value, state.x)
		out[index] = value
		peak = maxf(peak, absf(value))
	if peak > 0.0:
		for index: int in out.size():
			out[index] /= peak
	return out


## Frecuencia más cercana a [param frequency] que cierra un número entero de
## ciclos en [param duration] segundos.
func _snap_to_period(frequency: float, duration: float) -> float:
	var cycles := maxf(1.0, round(frequency * duration))
	return cycles / duration


func _silence(frames: int) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(frames)
	return samples


func _envelope(t: float, duration: float, attack: float, release: float) -> float:
	var rise := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var fall := clampf((duration - t) / maxf(release, 0.0001), 0.0, 1.0)
	return rise * fall


## Ajusta el stem a su valor eficaz objetivo y, si con eso el pico se pasa del
## techo, lo baja hasta el techo. El orden importa: primero el equilibrio entre
## capas, después la seguridad.
func _master(samples: PackedFloat32Array, target_rms_dbfs: float) -> PackedFloat32Array:
	var rms := db_to_linear(_rms_db(samples))
	if rms > 0.0:
		var scale := db_to_linear(target_rms_dbfs) / rms
		for index: int in samples.size():
			samples[index] *= scale
	var peak := db_to_linear(_peak_db(samples))
	var ceiling := db_to_linear(PEAK_CEILING_DBFS)
	if peak > ceiling:
		var trim := ceiling / peak
		for index: int in samples.size():
			samples[index] *= trim
	return samples


## Escala al pico pedido, en dBFS.
func _normalize(samples: PackedFloat32Array, peak_dbfs: float) -> PackedFloat32Array:
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	if peak <= 0.0:
		return samples
	var scale := db_to_linear(peak_dbfs) / peak
	for index: int in samples.size():
		samples[index] *= scale
	return samples


func _rms_db(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return -INF
	var sum := 0.0
	for value: float in samples:
		sum += value * value
	var rms := sqrt(sum / float(samples.size()))
	return linear_to_db(rms) if rms > 0.0 else -INF


func _peak_db(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	return linear_to_db(peak) if peak > 0.0 else -INF


## Mayor diferencia entre dos muestras seguidas; con [param wrap], incluye el
## salto del final al principio.
func _max_slope(samples: PackedFloat32Array, wrap: bool) -> float:
	var worst := 0.0
	for index: int in range(1, samples.size()):
		worst = maxf(worst, absf(samples[index] - samples[index - 1]))
	if wrap and samples.size() > 1:
		worst = maxf(worst, absf(samples[0] - samples[samples.size() - 1]))
	return worst


## Escribe el WAV y su `.import`. Devuelve los bytes escritos, o −1 si falló.
func _write(base_name: String, samples: PackedFloat32Array, looping: bool) -> int:
	var frames := samples.size()
	var data := PackedByteArray()
	data.resize(frames * 2)
	for index: int in frames:
		data.encode_s16(index * 2, int(round(clampf(samples[index], -1.0, 1.0) * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = frames if looping else 0
	var file_name := "%s.wav" % base_name
	var path := "%s/%s" % [ProjectSettings.globalize_path(OUTPUT_DIR), file_name]
	var err := stream.save_to_wav(path)
	if err != OK:
		push_error("No se pudo escribir %s: %s" % [path, error_string(err)])
		return -1
	_write_import(OUTPUT_DIR.path_join(file_name), looping)
	return FileAccess.get_file_as_bytes(path).size()


## Escribe (o actualiza) el `.import`, conservando `uid` y `path` si ya existían.
func _write_import(resource_path: String, looping: bool) -> void:
	var import_path := "%s.import" % resource_path
	var config := ConfigFile.new()
	var _existing := config.load(import_path)
	config.set_value("remap", "importer", "wav")
	config.set_value("remap", "type", "AudioStreamWAV")
	config.set_value("deps", "source_file", resource_path)
	for key: String in IMPORT_PARAMS:
		config.set_value("params", key, IMPORT_PARAMS[key])
	if looping:
		config.set_value("params", "edit/loop_mode", 2)
	var err := config.save(import_path)
	if err != OK:
		push_error("No se pudo escribir %s: %s" % [import_path, error_string(err)])
