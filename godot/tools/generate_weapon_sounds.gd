## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sintetiza los dos sonidos del arma de `docs/08` §2.10 en
## `assets/audio/weapons/*.wav`.
##
## Cómo regenerarlos (desde la raíz del repositorio):
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot -s res://tools/generate_weapon_sounds.gd
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot --editor --quit
##
## Mismo patrón que `tools/generate_motor_sounds.gd`: la herramienta escribe el
## `.wav` y deja el `.import` con los parámetros que hacen falta; la segunda línea
## es el paso de importación. No se toca el `uid` de un `.import` que ya exista, de
## modo que regenerar no rompe las referencias del proyecto.
##
## **Qué se sintetiza** (sala limpia, `docs/13` §5.4: nada sale de una grabación).
##
## - `shot.wav`, 0.22 s. Un disparo es un **transitorio**: un golpe de ruido de
##   banda ancha con ataque de una muestra y caída exponencial rápida, más un
##   cuerpo tonal grave que le da el «chunk» mecánico —dos senos barridos hacia
##   abajo, que es lo que hace el gas al expandirse— y una cola de ruido filtrado
##   más largo que simula la reflexión en la estructura del dron.
## - `impact.wav`, 0.18 s. Un impacto metálico: el mismo transitorio de ruido pero
##   más corto y más agudo, y encima tres parciales **inarmónicos** (relaciones
##   1 : 2.76 : 5.40, las de una placa rectangular) con caídas distintas. Los
##   parciales inarmónicos son lo que distingue «metal» de «tambor».
##
## Ninguno de los dos hace bucle: son one-shot, así que `edit/loop_mode` va en 0.
##
## **Determinismo**: cada sonido usa su propia semilla fija, así que dos corridas
## producen byte a byte el mismo archivo.
extends SceneTree

## Frecuencia de muestreo de los dos sonidos, en Hz.
const MIX_RATE: int = 44100

## Carpeta de salida dentro del proyecto.
const OUTPUT_DIR: String = "res://assets/audio/weapons"

## Pico al que se normaliza cada sonido, en dBFS. El mismo que los loops de motor,
## para que el bus `Weapons` y el bus `Motors` arranquen equilibrados.
const PEAK_DBFS: float = -6.0

## Duración del disparo, en segundos.
const SHOT_SECONDS: float = 0.22

## Duración del impacto, en segundos.
const IMPACT_SECONDS: float = 0.18

## Semillas fijas de cada sonido.
const SHOT_SEED: int = 0x57_50_4E_31
const IMPACT_SEED: int = 0x57_50_4E_32

## Relaciones de los parciales inarmónicos de una placa metálica. La primera es la
## fundamental; las otras dos son las que hacen que suene a metal y no a parche.
const PLATE_RATIOS: Array[float] = [1.0, 2.76, 5.40]

## Caída de cada parcial de la placa, en segundos (constante de tiempo).
const PLATE_DECAY: Array[float] = [0.045, 0.030, 0.018]

## Amplitud de cada parcial de la placa.
const PLATE_GAIN: Array[float] = [0.55, 0.32, 0.18]

## Parámetros del importador de WAV. Dos diferencias con los loops de motor:
## `edit/loop_mode = 0` (son one-shot) y `compress/mode = 0` (PCM sin comprimir,
## para que el transitorio no se lave con un códec con pérdida).
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


func _init() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var err := DirAccess.make_dir_recursive_absolute(absolute)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("No se pudo crear %s: %s" % [absolute, error_string(err)])
		quit(1)
		return
	print("Sonidos del arma: 2 one-shot a %d Hz" % MIX_RATE)
	if not _write("shot", _synth_shot()):
		quit(1)
		return
	if not _write("impact", _synth_impact()):
		quit(1)
		return
	print("Listo. Importá con: godot --headless --path godot --editor --quit")
	quit(0)


## Escribe el WAV y su `.import`. Devuelve `false` si algo falló.
func _write(base_name: String, samples: PackedFloat32Array) -> bool:
	var stream := _to_stream(samples)
	var file_name := "%s.wav" % base_name
	var path := "%s/%s" % [ProjectSettings.globalize_path(OUTPUT_DIR), file_name]
	var err := stream.save_to_wav(path)
	if err != OK:
		push_error("No se pudo escribir %s: %s" % [path, error_string(err)])
		return false
	_write_import(OUTPUT_DIR.path_join(file_name))
	print("  %-8s %5d muestras · %.3f s · pico %.2f dBFS · %d bytes"
			% [base_name, samples.size(), float(samples.size()) / float(MIX_RATE),
			PEAK_DBFS, FileAccess.get_file_as_bytes(path).size()])
	return true


## Disparo: transitorio de ruido + cuerpo tonal barrido + cola filtrada.
func _synth_shot() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SHOT_SEED
	var frames := int(round(SHOT_SECONDS * float(MIX_RATE)))
	var samples := PackedFloat32Array()
	samples.resize(frames)

	# 1) Transitorio: ruido blanco con envolvente de ataque instantáneo y caída de
	#    8 ms. Es el 80 % de lo que el oído identifica como «disparo».
	var crack := _filtered_noise(rng, frames, 5200.0)
	# 2) Cola: el mismo ruido con otro corte y otra caída, mucho más larga.
	var tail := _filtered_noise(rng, frames, 900.0)

	for i: int in frames:
		var t := float(i) / float(MIX_RATE)
		var crack_env := exp(-t / 0.008)
		var tail_env := exp(-t / 0.055) * (1.0 - exp(-t / 0.002))
		# 3) Cuerpo tonal: dos senos que barren de 220 a 90 Hz y de 460 a 180 Hz con
		#    constante de tiempo 30 ms. La fase se integra en forma cerrada
		#    ([method _sweep_phase]) porque la frecuencia cambia con el tiempo.
		var phase_low := TAU * _sweep_phase(t, 220.0, 90.0, 0.030)
		var phase_high := TAU * _sweep_phase(t, 460.0, 180.0, 0.030)
		var body := (0.55 * sin(phase_low) + 0.28 * sin(phase_high)) * exp(-t / 0.022)
		samples[i] = 1.00 * crack[i] * crack_env + 0.42 * tail[i] * tail_env + body

	return _normalize(_fade_out(samples))


## Impacto metálico: transitorio corto + tres parciales inarmónicos.
func _synth_impact() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = IMPACT_SEED
	var frames := int(round(IMPACT_SECONDS * float(MIX_RATE)))
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var crack := _filtered_noise(rng, frames, 9000.0)
	var fundamental := 1250.0

	for i: int in frames:
		var t := float(i) / float(MIX_RATE)
		var value := 0.85 * crack[i] * exp(-t / 0.004)
		for partial: int in PLATE_RATIOS.size():
			var frequency := fundamental * PLATE_RATIOS[partial]
			if frequency > 0.45 * float(MIX_RATE):
				continue
			value += PLATE_GAIN[partial] * sin(TAU * frequency * t) \
					* exp(-t / PLATE_DECAY[partial])
		samples[i] = value

	return _normalize(_fade_out(samples))


## Fase acumulada de un barrido exponencial de [param start] a [param stop] hercios
## con constante de tiempo [param tau], en ciclos.
##
## Integrar `f(t) = stop + (start − stop)·e^(−t/τ)` da
## `stop·t + (start − stop)·τ·(1 − e^(−t/τ))`. Hacerlo en forma cerrada y no
## acumulando incrementos evita el arrastre de error de punto flotante que
## produciría un clic al final.
func _sweep_phase(t: float, start: float, stop: float, tau: float) -> float:
	return stop * t + (start - stop) * tau * (1.0 - exp(-t / tau))


## Ruido blanco pasado por un polo simple. No hace falta que sea periódico: estos
## sonidos son one-shot.
func _filtered_noise(rng: RandomNumberGenerator, frames: int,
		cutoff: float) -> PackedFloat32Array:
	var alpha := clampf(1.0 - exp(-TAU * cutoff / float(MIX_RATE)), 0.0, 1.0)
	var filtered := PackedFloat32Array()
	filtered.resize(frames)
	var state := 0.0
	var peak := 0.0
	for i: int in frames:
		state += alpha * (rng.randf_range(-1.0, 1.0) - state)
		filtered[i] = state
		peak = maxf(peak, absf(state))
	if peak > 0.0:
		for i: int in frames:
			filtered[i] /= peak
	return filtered


## Rampa de bajada en las últimas 3 ms: un one-shot que termina en un valor no nulo
## produce un clic al soltarlo.
func _fade_out(samples: PackedFloat32Array) -> PackedFloat32Array:
	var fade := mini(int(0.003 * float(MIX_RATE)), samples.size())
	for i: int in fade:
		var index := samples.size() - fade + i
		samples[index] *= 1.0 - float(i) / float(fade)
	return samples


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


## Empaqueta las muestras como `AudioStreamWAV` PCM de 16 bits, mono, sin bucle.
func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var frames := samples.size()
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i: int in frames:
		data.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


## Escribe (o actualiza) el `.import` del WAV con [constant IMPORT_PARAMS],
## conservando `[remap]` y `[deps]` si ya existían.
func _write_import(resource_path: String) -> void:
	var import_path := "%s.import" % resource_path
	var config := ConfigFile.new()
	var _existing := config.load(import_path)
	config.set_value("remap", "importer", "wav")
	config.set_value("remap", "type", "AudioStreamWAV")
	config.set_value("deps", "source_file", resource_path)
	for key: String in IMPORT_PARAMS:
		config.set_value("params", key, IMPORT_PARAMS[key])
	var err := config.save(import_path)
	if err != OK:
		push_error("No se pudo escribir %s: %s" % [import_path, error_string(err)])
