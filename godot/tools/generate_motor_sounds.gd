## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sintetiza los ocho loops de motor de `docs/03` §6 en `assets/audio/motors/*.wav`.
##
## Cómo regenerarlos (desde la raíz del repositorio):
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot -s res://tools/generate_motor_sounds.gd
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot --editor --quit
##
## La segunda línea es el paso de importación: la herramienta escribe el `.wav` y
## deja el `.import` con los parámetros que necesitan los loops (bucle hacia
## adelante, sin normalizar y **sin comprimir**, porque `audio_check` mide el pico
## leyendo el PCM de 16 bits de `AudioStreamWAV.data`); el editor los convierte en
## `.sample`. La herramienta no toca el `uid` ni el `path` de un `.import` que ya
## exista, así que regenerar no rompe las referencias del proyecto.
##
## **Qué se sintetiza** (§6, más la física de hélices de §2.3). Un motor con tres
## palas emite, sobre todo, la **frecuencia de paso de pala** `f_bpf = 3 · rpm/60`
## y sus armónicos, con amplitud decreciente; por debajo está la **fundamental del
## motor** `f_m = rpm/60` —el desbalanceo mecánico del eje, una vez por vuelta— y,
## alrededor de todo, el **ruido de flujo** de la hélice batiendo aire, que crece
## con el régimen y se abre en banda al subir de vueltas. Nada de esto sale de una
## grabación: son tres generadores y un filtro de un polo (sala limpia, `docs/13`
## §5.4).
##
## **Por qué el loop no tiene costura.** Un loop de [constant DURATION] segundos
## solo empalma consigo mismo si cada parcial completa un número **entero** de
## ciclos dentro del buffer, o sea si su frecuencia es múltiplo de
## `1 / DURATION = 0.667 Hz`. Por eso cada frecuencia se redondea a ese retículo
## antes de sintetizar ([method _quantize]) y la fase se calcula sobre el índice de
## muestra, no acumulando incrementos (que arrastraría error de punto flotante).
## El ruido se hace periódico de la misma forma: el buffer de ruido blanco ya lo es
## por construcción, y el filtro pasa-bajos se barre **dos veces** sobre él para que
## su estado en la muestra 0 sea el mismo que en la muestra `N`, que es la condición
## de régimen periódico de un filtro estable ([method _filtered_noise]).
##
## **Determinismo**: cada banda usa [constant BASE_SEED] `+ índice` como semilla, así
## que dos corridas producen byte a byte el mismo archivo.
extends SceneTree

## Frecuencia de muestreo de los ocho loops, en Hz.
const MIX_RATE: int = 44100

## Duración de cada loop, en segundos (`docs/03` §6).
const DURATION: float = 1.5

## Carpeta de salida dentro del proyecto.
const OUTPUT_DIR: String = "res://assets/audio/motors"

## Régimen máximo del motor, en rpm. Es el mismo valor que
## [member DroneMotor.max_rpm] (`docs/03` §10); el audio y la física tienen que
## hablar del mismo motor.
const MAX_RPM: float = 30000.0

## Fracción de [constant MAX_RPM] de cada banda (`docs/03` §6).
const BAND_RATIOS: Array[float] = [0.05, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 1.0]

## Nombre de archivo de cada banda, en el mismo orden que [constant BAND_RATIOS].
const BAND_NAMES: Array[String] = ["idle", "band_1", "band_2", "band_3",
		"band_4", "band_5", "band_6", "band_7"]

## Palas de la hélice (`docs/03` §2.3): la frecuencia de paso de pala es
## `PALAS · rpm/60`.
const BLADES: float = 3.0

## Armónicos de la frecuencia de paso de pala que se sintetizan.
const HARMONICS: int = 12

## Exponente de la caída de amplitud de los armónicos: el armónico `k` vale
## `k^(−HARMONIC_FALLOFF)`. Con 1.35 el timbre queda entre el zumbido puro (2.0) y
## la sierra (1.0), que es como suena una hélice de 5".
const HARMONIC_FALLOFF: float = 1.35

## Amplitud de la fundamental del motor (`rpm/60`) respecto de la del primer
## armónico de paso de pala.
const SHAFT_GAIN: float = 0.45

## Amplitud del segundo armónico de la fundamental del motor.
const SHAFT_SECOND_GAIN: float = 0.18

## Amplitud del ruido de flujo con el motor parado y con el motor a fondo. Crece
## con el régimen porque es aire movido, no electricidad.
const NOISE_GAIN_RANGE: Vector2 = Vector2(0.10, 0.38)

## Corte del pasa-bajos del ruido, en Hz, a régimen mínimo y máximo.
const NOISE_CUTOFF_RANGE: Vector2 = Vector2(700.0, 6200.0)

## Fracción de Nyquist por encima de la cual no se sintetiza ningún parcial: evita
## el aliasing de los armónicos altos de la banda de 30 000 rpm.
const NYQUIST_GUARD: float = 0.45

## Pico al que se normaliza cada loop, en dBFS (`docs/03` §6). `audio_check` exige
## que el pico medido quede entre −7 y −5 dBFS.
const PEAK_DBFS: float = -6.0

## Semilla base. La banda `i` usa `BASE_SEED + i`.
const BASE_SEED: int = 0x4D_4F_54_52

## Parámetros del importador de WAV que necesitan estos loops.
##
## - `edit/loop_mode = 2` es `LOOP_FORWARD`: un WAV plano no guarda puntos de bucle
##   (`save_to_wav()` escribe solo `fmt ` y `data`), así que el bucle lo fija el
##   `.import`, no el archivo.
## - `edit/normalize = false` porque el pico ya lo puso la herramienta en
##   [constant PEAK_DBFS] y normalizar lo llevaría a 0 dBFS.
## - `compress/mode = 0` (PCM sin comprimir). El valor por defecto de Godot 4.7 es
##   QOA, que es con pérdida: rompería la medida de pico de `audio_check` y metería
##   artefactos en un sonido que suena todo el tiempo.
const IMPORT_PARAMS: Dictionary[String, Variant] = {
	"force/8_bit": false,
	"force/mono": false,
	"force/max_rate": false,
	"force/max_rate_hz": 44100,
	"edit/trim": false,
	"edit/normalize": false,
	"edit/loop_mode": 2,
	"edit/loop_begin": 0,
	"compress/mode": 0,
}


func _init() -> void:
	var frames := int(round(DURATION * MIX_RATE))
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var err := DirAccess.make_dir_recursive_absolute(absolute)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("No se pudo crear %s: %s" % [absolute, error_string(err)])
		quit(1)
		return
	print("Loops de motor: %d bandas de %.2f s a %d Hz (%d muestras)"
			% [BAND_RATIOS.size(), DURATION, MIX_RATE, frames])
	for index: int in BAND_RATIOS.size():
		var rpm := MAX_RPM * BAND_RATIOS[index]
		var samples := _synth_band(index, rpm, frames)
		var stream := _to_stream(samples, frames)
		var file_name := "%s.wav" % BAND_NAMES[index]
		var path := "%s/%s" % [absolute, file_name]
		var write := stream.save_to_wav(path)
		if write != OK:
			push_error("No se pudo escribir %s: %s" % [path, error_string(write)])
			quit(1)
			return
		_write_import(OUTPUT_DIR.path_join(file_name), frames)
		print("  %-8s %6.0f rpm · paso de pala %7.2f Hz · fundamental %6.2f Hz · pico %.2f dBFS · %d bytes"
				% [BAND_NAMES[index], rpm, BLADES * rpm / 60.0, rpm / 60.0, PEAK_DBFS,
				FileAccess.get_file_as_bytes(path).size()])
	print("Listo. Importá con: godot --headless --path godot --editor --quit")
	quit(0)


## Sintetiza una banda y devuelve las muestras en `[−1, 1]`, ya normalizadas al
## pico de [constant PEAK_DBFS].
func _synth_band(index: int, rpm: float, frames: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = BASE_SEED + index
	var ratio := clampf(rpm / MAX_RPM, 0.0, 1.0)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	# 1) Armónicos de la frecuencia de paso de pala y fundamental del motor. Cada
	#    parcial entra con su frecuencia llevada al retículo del loop y con una fase
	#    propia, para que la suma no arranque como un impulso.
	var partials: Array[Vector3] = []   # (ciclos por loop, amplitud, fase)
	var blade_pass := BLADES * rpm / 60.0
	for harmonic: int in range(1, HARMONICS + 1):
		var amplitude := pow(float(harmonic), -HARMONIC_FALLOFF)
		_append_partial(partials, blade_pass * float(harmonic), amplitude, rng, frames)
	var shaft := rpm / 60.0
	_append_partial(partials, shaft, SHAFT_GAIN, rng, frames)
	_append_partial(partials, shaft * 2.0, SHAFT_SECOND_GAIN, rng, frames)

	for partial: Vector3 in partials:
		var cycles := partial.x
		var amplitude := partial.y
		var phase := partial.z
		for i: int in frames:
			samples[i] += amplitude * sin(TAU * cycles * float(i) / float(frames) + phase)

	# 2) Ruido de flujo: crece y se abre en banda con el régimen.
	var noise_gain := lerpf(NOISE_GAIN_RANGE.x, NOISE_GAIN_RANGE.y, ratio)
	var cutoff := lerpf(NOISE_CUTOFF_RANGE.x, NOISE_CUTOFF_RANGE.y, ratio)
	var noise := _filtered_noise(rng, frames, cutoff)
	for i: int in frames:
		samples[i] += noise_gain * noise[i]

	return _normalize(samples)


## Agrega un parcial a [param partials] si entra por debajo de la guarda de Nyquist.
##
## Guarda **ciclos por loop** —la frecuencia ya redondeada al retículo `1/DURATION`—
## en vez de hercios: es lo que hace que el empalme del bucle sea exacto.
func _append_partial(partials: Array[Vector3], frequency: float, amplitude: float,
		rng: RandomNumberGenerator, frames: int) -> void:
	if frequency <= 0.0 or frequency > NYQUIST_GUARD * float(MIX_RATE):
		return
	var cycles := _quantize(frequency, frames)
	if cycles <= 0.0:
		return
	partials.append(Vector3(cycles, amplitude, rng.randf() * TAU))


## Ciclos enteros que caben en el loop para una frecuencia dada. Devolver un entero
## es exactamente la condición de «sin costura»: la muestra `frames` vale lo mismo
## que la muestra `0`.
func _quantize(frequency: float, frames: int) -> float:
	return float(maxi(1, int(round(frequency * float(frames) / float(MIX_RATE)))))


## Ruido blanco pasado por un polo simple, periódico en `frames` muestras.
##
## El truco del empalme es el primer barrido: deja el estado del filtro en el que
## le corresponde al **final** del ciclo, de modo que el segundo barrido —el que se
## queda— arranca ya en régimen periódico. El error residual es `(1−a)^frames`, o
## sea cero para cualquier corte audible y 66 150 muestras.
func _filtered_noise(rng: RandomNumberGenerator, frames: int, cutoff: float) -> PackedFloat32Array:
	var white := PackedFloat32Array()
	white.resize(frames)
	for i: int in frames:
		white[i] = rng.randf_range(-1.0, 1.0)
	var alpha := clampf(1.0 - exp(-TAU * cutoff / float(MIX_RATE)), 0.0, 1.0)
	var state := 0.0
	for i: int in frames:
		state += alpha * (white[i] - state)
	var filtered := PackedFloat32Array()
	filtered.resize(frames)
	var peak := 0.0
	for i: int in frames:
		state += alpha * (white[i] - state)
		filtered[i] = state
		peak = maxf(peak, absf(state))
	if peak > 0.0:
		for i: int in frames:
			filtered[i] /= peak
	return filtered


## Escala las muestras para que el pico quede en [constant PEAK_DBFS].
func _normalize(samples: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	if peak <= 0.0:
		return samples
	var scale := db_to_linear(PEAK_DBFS) / peak
	for i: int in samples.size():
		samples[i] *= scale
	return samples


## Empaqueta las muestras como `AudioStreamWAV` PCM de 16 bits, mono, en bucle
## hacia adelante sobre el loop entero (`docs/03` §6).
func _to_stream(samples: PackedFloat32Array, frames: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i: int in frames:
		data.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


## Escribe (o actualiza) el `.import` del WAV con [constant IMPORT_PARAMS].
##
## Conserva `[remap]` y `[deps]` si ya existían: el `uid` de un recurso importado es
## lo que referencian las escenas, y regenerar el sonido no debe cambiarlo. Cuando
## el archivo no existe se escribe lo mínimo y el editor completa `uid` y `path` en
## el paso de importación.
func _write_import(resource_path: String, frames: int) -> void:
	var import_path := "%s.import" % resource_path
	var config := ConfigFile.new()
	var _existing := config.load(import_path)
	config.set_value("remap", "importer", "wav")
	config.set_value("remap", "type", "AudioStreamWAV")
	config.set_value("deps", "source_file", resource_path)
	for key: String in IMPORT_PARAMS:
		config.set_value("params", key, IMPORT_PARAMS[key])
	config.set_value("params", "edit/loop_end", frames)
	var err := config.save(import_path)
	if err != OK:
		push_error("No se pudo escribir %s: %s" % [import_path, error_string(err)])
