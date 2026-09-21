## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sintetiza el banco de la ciudad en `assets/audio/city/*.wav` (`docs/13` §5.4,
## WP-27): derrumbes, crujido de daño, ambiente nocturno y sirena lejana.
##
## Cómo regenerarlo (desde la raíz del repositorio):
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot -s res://tools/generate_city_sounds.gd
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot --editor --quit
##
## La segunda línea importa. Mismo patrón que `generate_motor_sounds.gd` y
## `generate_enemy_sounds.gd`: PCM de 16 bits sin comprimir escrito desde un
## [PackedByteArray], `.import` con `compress/mode = 0`, semilla por sonido y cero
## grabaciones de por medio. Sala limpia y sin licencias de terceros.
##
## [b]Qué es cada cosa[/b] (`docs/13` §5, notas de identidad de §1):
##
## - `collapse_low` — el sub-grave del derrumbe: 60 → 35 Hz cayendo durante 2.5 s
##   con retumbe filtrado encima. Es el peso, no el ruido.
## - `collapse_debris` — la cascada: 90 golpes granulares de hormigón repartidos
##   con densidad decreciente en 1.8 s. Se dispara junto con el anterior; los dos
##   juntos son «un edificio que se cae», uno solo no.
## - `damage_crack` — el crujido corto de pasar a `DAMAGED`. Estructura que cede,
##   no explosión.
## - `ambience_night` — 20 s en bucle: viento, ciudad dormida y **una radio
##   lejana**. La ciudad se comunica por radio (`docs/narrativa` §2), así que el
##   fondo del combate tiene una voz filtrada que se entiende como murmullo y no
##   dice palabras: es sintética, no hay locución grabada.
## - `siren_far` — sirena de dos tonos muy lejos, para cuando la ciudad se queja.
## - `battery_click` — el «clic de conector» de la pila (`docs/13` §8: la pila
##   suena en el bus `City`). Hojalata: armónicos impares y un parcial desafinado,
##   igual que los sonidos de interfaz de WP-25.
##
## [b]Bucles[/b]: `ambience_night` se importa con `edit/loop_mode = 2`, que es el
## `LOOP_FORWARD` del importador (el 1 es «deshabilitado»). Además se sintetiza
## **cerrado sobre sí mismo**: las frecuencias de los osciladores lentos se
## cuadran al periodo del archivo y la radio entra y sale dentro del bucle, así
## que el empalme no chasquea. El log imprime la derivada máxima incluyendo el
## salto del final al principio, que es donde se oiría.
extends SceneTree

## Frecuencia de muestreo, en Hz.
const MIX_RATE: int = 44100

## Carpeta de salida.
const OUTPUT_DIR: String = "res://assets/audio/city"

## Pico al que se normaliza cada sonido, en dBFS. El mismo que el resto de los
## bancos del proyecto.
const PEAK_DBFS: float = -6.0

## El ambiente va mucho más abajo: es fondo y encima el `AudioPool` lo reproduce a
## −18 dB (`docs/13` §5).
const AMBIENCE_PEAK_DBFS: float = -8.0

## Semilla base; cada sonido le suma la suya.
const BASE_SEED: int = 0x43_49_54_59

## Duración del bucle de ambiente, en segundos.
const AMBIENCE_SECONDS: float = 20.0

## Formantes de las cinco vocales sintéticas de la radio, en Hz. No se pronuncia
## ninguna palabra: la radio encadena vocales con una envolvente silábica, que es
## exactamente lo que se oye de una conversación a través de una pared.
const VOWELS: Array[Vector3] = [
	Vector3(730.0, 1090.0, 2440.0),  # a
	Vector3(530.0, 1840.0, 2480.0),  # e
	Vector3(390.0, 1990.0, 2550.0),  # i
	Vector3(570.0, 840.0, 2410.0),   # o
	Vector3(440.0, 1020.0, 2240.0),  # u
]

## Peso relativo de cada formante de la voz de radio.
const FORMANT_GAINS: Array[float] = [1.0, 0.55, 0.25]

## Parámetros del importador de WAV. `compress/mode = 0` es PCM sin comprimir.
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

## El banco: nombre, duración en segundos, semilla, si va en bucle y su pico.
const BANK: Array[Dictionary] = [
	{"name": "collapse_low", "dur": 2.5, "seed": 1, "loop": false, "peak": PEAK_DBFS},
	{"name": "collapse_debris", "dur": 1.8, "seed": 2, "loop": false, "peak": PEAK_DBFS},
	{"name": "damage_crack", "dur": 0.4, "seed": 3, "loop": false, "peak": PEAK_DBFS},
	{"name": "ambience_night", "dur": AMBIENCE_SECONDS, "seed": 4, "loop": true,
		"peak": AMBIENCE_PEAK_DBFS},
	{"name": "siren_far", "dur": 4.0, "seed": 5, "loop": false, "peak": -10.0},
	{"name": "battery_click", "dur": 0.22, "seed": 6, "loop": false, "peak": PEAK_DBFS},
]


func _init() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var err := DirAccess.make_dir_recursive_absolute(absolute)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("No se pudo crear %s: %s" % [absolute, error_string(err)])
		quit(1)
		return

	var total := 0
	for row: Dictionary in BANK:
		var sound_name := String(row["name"])
		var duration := float(row["dur"])
		var frames := int(round(duration * MIX_RATE))
		var looping := bool(row["loop"])
		var rng := RandomNumberGenerator.new()
		rng.seed = BASE_SEED + int(row["seed"])
		var samples := _synth(sound_name, frames, duration, rng)
		samples = _normalize(samples, float(row["peak"]))
		var stream := _to_stream(samples, frames, looping)
		var file_name := "%s.wav" % sound_name
		var path := "%s/%s" % [absolute, file_name]
		var write := stream.save_to_wav(path)
		if write != OK:
			push_error("No se pudo escribir %s: %s" % [path, error_string(write)])
			quit(1)
			return
		_write_import(OUTPUT_DIR.path_join(file_name), looping)
		total += FileAccess.get_file_as_bytes(path).size()
		print("  %-16s %6.3f s · %7d muestras · RMS %6.2f dBFS · pico %6.2f dBFS · |Δ|máx %.4f%s"
				% [sound_name, duration, frames, _rms_db(samples), _peak_db(samples),
				_max_slope(samples, looping), " · bucle" if looping else ""])

	print("Banco de ciudad: %d sonidos, %d Hz, PCM 16 bits mono, %.1f KiB"
			% [BANK.size(), MIX_RATE, float(total) / 1024.0])
	print("Listo. Importá con: godot --headless --path godot --editor --quit")
	quit(0)


## Despacha por nombre. Cada sonido tiene su propia forma; no hay familias acá
## porque son seis y ninguno se parece al otro.
func _synth(sound_name: String, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	match sound_name:
		"collapse_low":
			return _synth_collapse_low(frames, duration, rng)
		"collapse_debris":
			return _synth_collapse_debris(frames, duration, rng)
		"damage_crack":
			return _synth_damage_crack(frames, duration, rng)
		"ambience_night":
			return _synth_ambience(frames, duration, rng)
		"siren_far":
			return _synth_siren(frames, duration, rng)
		"battery_click":
			return _synth_battery_click(frames, duration)
	return _silence(frames)


# --------------------------------------------------------------------------
# Derrumbe
# --------------------------------------------------------------------------

## Sub-grave del derrumbe: 60 → 35 Hz en 2.5 s, con retumbe filtrado.
##
## La fase se **integra** (`phase += TAU·f(t)/fs`): escribir `TAU·f(t)·t` daría el
## doble de barrido y el final una octava abajo.
func _synth_collapse_low(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var rumble := _lowpass(_noise(rng, frames), 90.0)
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var progress := t / duration
		# Cae de tono mientras suena: es la masa llegando al suelo.
		var frequency := lerpf(60.0, 35.0, progress * progress)
		phase += TAU * frequency * inverse_rate
		# Un poco de segundo armónico para que se oiga en parlantes chicos, donde
		# 35 Hz no existen.
		var body := sin(phase) + 0.25 * sin(2.0 * phase)
		var swell := pow(clampf(t / 0.35, 0.0, 1.0), 1.5) * exp(-1.4 * t)
		samples[index] = (body * swell + 0.7 * rumble[index] * swell) \
				* _envelope(t, duration, 0.02, 0.6)
	return samples


## Cascada de hormigón: golpes granulares con densidad decreciente.
##
## Cada grano es un impulso de ruido con su propio filtro y su propia caída; la
## densidad arranca en 120 golpes por segundo y se apaga. Eso es lo que separa una
## cascada de escombros de un ruido blanco con envolvente.
func _synth_collapse_debris(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var source := _noise(rng, frames)
	var time := 0.0
	while time < duration:
		var progress := time / duration
		var density := lerpf(120.0, 14.0, progress)
		time += rng.randf_range(0.4, 1.6) / density
		if time >= duration:
			break
		var start := int(time * MIX_RATE)
		var decay := rng.randf_range(24.0, 90.0)
		var gain := rng.randf_range(0.25, 1.0) * lerpf(1.0, 0.35, progress)
		var tone := rng.randf_range(260.0, 1700.0)
		var grain_frames := mini(frames - start, int(0.25 * MIX_RATE))
		var phase := 0.0
		for offset: int in grain_frames:
			var local := float(offset) * inverse_rate
			phase += TAU * tone * inverse_rate
			var body := 0.45 * sin(phase)
			# Ataque de 0.4 ms: un grano que arranca en una sola muestra suena a
			# recorte digital, no a hormigón. Sigue siendo instantáneo al oído.
			var attack := clampf(local / 0.0004, 0.0, 1.0)
			samples[start + offset] += gain * attack * (source[start + offset] + body) 					* exp(-decay * local)
	# Un colchón grave debajo de los golpes: la polvareda.
	var dust := _lowpass(_noise(rng, frames), 320.0)
	for index: int in frames:
		var t := float(index) * inverse_rate
		samples[index] += 0.35 * dust[index] * exp(-1.8 * t)
		samples[index] *= _envelope(t, duration, 0.003, 0.25)
	return samples


## Crujido corto de la estructura que cede: ruido con tres parciales que suenan y
## una caída rápida.
func _synth_damage_crack(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var grit := _bandpass(_noise(rng, frames), 1400.0, 1200.0)
	var partials: Array[float] = [190.0, 437.0, 913.0]
	for index: int in frames:
		var t := float(index) * inverse_rate
		var metal := 0.0
		for order: int in partials.size():
			metal += sin(TAU * partials[order] * t) * exp(-float(order + 6) * 4.0 * t) \
					/ float(partials.size())
		# El crujido no es continuo: se parte en escalones, como el hormigón.
		var stutter := 0.55 + 0.45 * signf(sin(TAU * 43.0 * t))
		samples[index] = (grit[index] * exp(-16.0 * t) * stutter + metal) \
				* _envelope(t, duration, 0.001, 0.08)
	return samples


# --------------------------------------------------------------------------
# Ambiente nocturno
# --------------------------------------------------------------------------

## Bucle de 20 s: viento, ciudad dormida y radio lejana.
##
## Todo lo que oscila lento se **cuadra al periodo** del archivo para que el
## empalme no salte, y la radio entra y sale dentro del bucle. El viento es ruido
## pasa-bajos con el corte modulado; la ciudad, un zumbido de 50/100 Hz con
## retumbe de tráfico lejano.
func _synth_ambience(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var wind := _lowpass(_noise(rng, frames), 700.0)
	var traffic := _lowpass(_noise(rng, frames), 140.0)
	var hiss := _highpass(_noise(rng, frames), 3500.0)
	var gust_a := _snap_to_period(0.085, duration)
	var gust_b := _snap_to_period(0.031, duration)
	var swell := _snap_to_period(0.05, duration)
	var hum := _snap_to_period(50.0, duration)
	for index: int in frames:
		var t := float(index) * inverse_rate
		# Dos ráfagas de periodos distintos: el viento no respira a compás.
		var gust := 0.45 + 0.35 * sin(TAU * gust_a * t) + 0.2 * sin(TAU * gust_b * t + 1.7)
		var city := 0.55 + 0.45 * sin(TAU * swell * t + 0.8)
		var mains := 0.05 * sin(TAU * hum * t) + 0.025 * sin(TAU * hum * 2.0 * t + 0.4)
		samples[index] = wind[index] * gust * 0.7 \
				+ traffic[index] * city * 0.9 \
				+ hiss[index] * 0.05 \
				+ mains * city
	# La radio lejana: dos intervenciones dentro del bucle, ninguna pegada al
	# borde, para que el empalme siga siendo continuo.
	var radio := _radio_voice(rng, frames, duration)
	for index: int in frames:
		samples[index] += radio[index]
	return samples


## Voz de radio sintética: tren de pulsos glotales por tres resonadores de
## formante, envolvente silábica y pasa-banda de radio.
##
## No dice nada. Encadena vocales de [constant VOWELS] a ritmo de habla (unas 5
## sílabas por segundo) con pausas entre frases; a través del pasa-banda de
## 380–2400 Hz y con la estática encima, lo que queda es exactamente lo que se oye
## de una radio en otro edificio: hay alguien hablando y no se entiende qué dice.
##
## Las frases se colocan **dentro** del archivo, con silencio en los dos extremos,
## así que sirve tal cual para un bucle.
func _radio_voice(rng: RandomNumberGenerator, frames: int,
		duration: float) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var pitch := rng.randf_range(108.0, 132.0)
	var phase := 0.0
	var formant_state := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var vowel: Vector3 = VOWELS[0]
	var syllable_end := 0.0
	var syllable_start := 0.0
	var syllable_gain := 0.0
	# Dos frases: una al cuarto del bucle y otra pasada la mitad.
	var phrases: Array[Vector2] = [
		Vector2(duration * 0.18, duration * 0.34),
		Vector2(duration * 0.58, duration * 0.79),
	]
	for index: int in frames:
		var t := float(index) * inverse_rate
		var talking := false
		for phrase: Vector2 in phrases:
			if t >= phrase.x and t < phrase.y:
				talking = true
				break
		if not talking:
			syllable_end = t
			syllable_gain = 0.0
			continue
		if t >= syllable_end:
			syllable_start = t
			syllable_end = t + rng.randf_range(0.11, 0.26)
			vowel = VOWELS[rng.randi_range(0, VOWELS.size() - 1)]
			# Una de cada cuatro sílabas es una pausa: sin eso suena a vocal
			# continua y no a alguien hablando.
			syllable_gain = 0.0 if rng.randf() < 0.25 else rng.randf_range(0.6, 1.0)
			pitch = clampf(pitch + rng.randf_range(-9.0, 9.0), 96.0, 148.0)
		phase += TAU * pitch * inverse_rate
		if phase >= TAU:
			phase -= TAU
		# Pulso glotal: un diente de sierra con el borde redondeado. Tiene todos
		# los armónicos que necesitan los formantes.
		var glottal := 2.0 * (phase / TAU) - 1.0
		glottal = glottal - glottal * glottal * glottal * 0.6
		var voiced := 0.0
		for band: int in 3:
			var frequency: float = vowel[band]
			var gain := FORMANT_GAINS[band]
			var state := formant_state[band] as Vector2
			var next := _resonate(glottal, state, frequency, 90.0 + 40.0 * float(band))
			formant_state[band] = Vector2(next, state.x)
			voiced += next * gain
		var local := (t - syllable_start) / maxf(syllable_end - syllable_start, 0.001)
		var envelope := sin(PI * clampf(local, 0.0, 1.0))
		samples[index] = voiced * syllable_gain * envelope
	# Pasa-banda de radio, estática y una portadora muy suave: lo que la hace
	# «lejana» es el recorte de graves y de agudos, no el volumen.
	samples = _bandpass(samples, 1050.0, 1900.0)
	var static_noise := _bandpass(_noise(rng, frames), 1600.0, 2600.0)
	for index: int in frames:
		var t := float(index) * inverse_rate
		var here := 0.0
		for phrase: Vector2 in phrases:
			if t >= phrase.x - 0.4 and t < phrase.y + 0.4:
				here = 1.0
				break
		samples[index] = samples[index] * 0.32 + static_noise[index] * 0.035 * here
	return samples


# --------------------------------------------------------------------------
# Sirena y pila
# --------------------------------------------------------------------------

## Sirena de dos tonos, muy filtrada: suena a diez manzanas de distancia.
func _synth_siren(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var air := _lowpass(_noise(rng, frames), 600.0)
	for index: int in frames:
		var t := float(index) * inverse_rate
		# Dos tonos alternando cada 0.7 s, con el salto suavizado: una sirena real
		# no salta de frecuencia en una muestra.
		var blend := 0.5 + 0.5 * tanh(6.0 * sin(TAU * t / 1.4))
		var frequency := lerpf(558.0, 664.0, blend)
		var tone := sin(TAU * frequency * t) + 0.3 * sin(TAU * frequency * 2.0 * t)
		# Trémolo lento: el aire de la ciudad se lleva parte del sonido.
		var distance := 0.7 + 0.3 * sin(TAU * 0.35 * t + 1.1)
		samples[index] = (tone * 0.5 * distance + air[index] * 0.12) \
				* _envelope(t, duration, 0.35, 0.8)
	return _lowpass(samples, 1800.0)


## «Clic de conector» de la pila: hojalata propia (armónicos impares, tercer
## parcial desafinado 1.2 %) más el chasquido del enganche.
func _synth_battery_click(frames: int, duration: float) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var base := 880.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		# Impares 1, 3, 5 y 7 con el tercero desafinado: es la firma de lo propio
		# (`docs/13` §1, sonidos de interfaz de WP-25).
		var tin := sin(TAU * base * t) * exp(-38.0 * t) \
				+ 0.5 * sin(TAU * base * 3.0 * 1.012 * t) * exp(-52.0 * t) \
				+ 0.28 * sin(TAU * base * 5.0 * t) * exp(-70.0 * t) \
				+ 0.14 * sin(TAU * base * 7.0 * t) * exp(-95.0 * t)
		# El conector que entra: dos chasquidos separados 18 ms.
		var click := exp(-1400.0 * t) + 0.6 * exp(-1400.0 * maxf(t - 0.018, 0.0))
		# Y la confirmación: un tercio ascendente, que es lo que se lee como
		# «entró».
		var confirm := 0.35 * sin(TAU * 1320.0 * maxf(t - 0.04, 0.0)) \
				* exp(-30.0 * maxf(t - 0.04, 0.0))
		samples[index] = (tin * 0.7 + click * 0.5 + confirm) \
				* _envelope(t, duration, 0.0005, 0.03)
	return samples


# --------------------------------------------------------------------------
# Utilidades de señal
# --------------------------------------------------------------------------

## Un paso de resonador de dos polos: `y = x·(1−r²) + 2r·cos(w)·y₁ − r²·y₂`.
## [param state] lleva `(y₁, y₂)` y el valor devuelto es el `y` nuevo.
func _resonate(input: float, state: Vector2, frequency: float, bandwidth: float) -> float:
	var r := exp(-PI * bandwidth / float(MIX_RATE))
	var w := TAU * frequency / float(MIX_RATE)
	return input * (1.0 - r * r) + 2.0 * r * cos(w) * state.x - r * r * state.y


## Ruido blanco en `[-1, 1]`.
func _noise(rng: RandomNumberGenerator, frames: int) -> PackedFloat32Array:
	var samples := _silence(frames)
	for index: int in frames:
		samples[index] = rng.randf_range(-1.0, 1.0)
	return samples


## Pasa-bajos de un polo, normalizado a pico 1.
func _lowpass(samples: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var out := _silence(samples.size())
	var alpha := clampf(1.0 - exp(-TAU * cutoff / float(MIX_RATE)), 0.0, 1.0)
	var state := 0.0
	var peak := 0.0
	for index: int in samples.size():
		state += alpha * (samples[index] - state)
		out[index] = state
		peak = maxf(peak, absf(state))
	if peak > 0.0:
		for index: int in out.size():
			out[index] /= peak
	return out


## Pasa-altos de un polo (la señal menos su pasa-bajos), normalizado a pico 1.
func _highpass(samples: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var out := _silence(samples.size())
	var alpha := clampf(1.0 - exp(-TAU * cutoff / float(MIX_RATE)), 0.0, 1.0)
	var state := 0.0
	var peak := 0.0
	for index: int in samples.size():
		state += alpha * (samples[index] - state)
		out[index] = samples[index] - state
		peak = maxf(peak, absf(out[index]))
	if peak > 0.0:
		for index: int in out.size():
			out[index] /= peak
	return out


## Pasa-banda barato: un resonador de dos polos centrado en [param centre] con
## [param bandwidth] Hz de ancho. Normalizado a pico 1.
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
## ciclos en [param duration] segundos. Es lo que hace empalmable un bucle.
func _snap_to_period(frequency: float, duration: float) -> float:
	var cycles := maxf(1.0, round(frequency * duration))
	return cycles / duration


func _silence(frames: int) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(frames)
	return samples


## Envolvente: rampa de entrada y caída al final, en segundos.
func _envelope(t: float, duration: float, attack: float, release: float) -> float:
	var rise := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var fall := clampf((duration - t) / maxf(release, 0.0001), 0.0, 1.0)
	return rise * fall


## Escala las muestras para que el pico quede en [param peak_dbfs].
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


## Valor eficaz en dBFS.
func _rms_db(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return -INF
	var sum := 0.0
	for value: float in samples:
		sum += value * value
	var rms := sqrt(sum / float(samples.size()))
	return linear_to_db(rms) if rms > 0.0 else -INF


## Pico en dBFS.
func _peak_db(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	return linear_to_db(peak) if peak > 0.0 else -INF


## Mayor diferencia entre dos muestras seguidas. Con [param wrap] incluye el salto
## del final al principio, que es el clic que se oiría en un bucle.
func _max_slope(samples: PackedFloat32Array, wrap: bool) -> float:
	var worst := 0.0
	for index: int in range(1, samples.size()):
		worst = maxf(worst, absf(samples[index] - samples[index - 1]))
	if wrap and samples.size() > 1:
		worst = maxf(worst, absf(samples[0] - samples[samples.size() - 1]))
	return worst


## Empaqueta las muestras como [AudioStreamWAV] PCM de 16 bits mono.
func _to_stream(samples: PackedFloat32Array, frames: int,
		looping: bool) -> AudioStreamWAV:
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
	return stream


## Escribe (o actualiza) el `.import` del WAV con [constant IMPORT_PARAMS].
##
## Conserva `[remap]` y `[deps]` si ya existían: el `uid` de un recurso importado
## es lo que referencian las escenas, y regenerar el sonido no debe cambiarlo.
##
## `edit/loop_mode` del importador: 0 detectar, 1 **deshabilitado**, 2 adelante.
## Un WAV plano no guarda puntos de bucle, así que un sonido en bucle necesita el
## 2 explícito; con el 1 el archivo se reproduce una vez y calla.
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
