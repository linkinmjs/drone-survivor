## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sintetiza el banco de sonido del jefe en `assets/audio/enemies/*.wav`
## (`docs/06` §11.2 canal 2, `docs/07` §10).
##
## Cómo regenerarlo (desde la raíz del repositorio):
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot -s res://tools/generate_enemy_sounds.gd
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot --editor --quit
##
## La segunda línea es el paso de importación. Es el mismo patrón de
## `tools/generate_motor_sounds.gd`: la herramienta escribe los `.wav` y deja los
## `.import` con PCM sin comprimir —el defecto de Godot 4.7 es QOA, con pérdida—,
## y no toca el `uid` ni el `path` de un `.import` que ya exista, así que
## regenerar no rompe las referencias del proyecto.
##
## [b]Qué se sintetiza[/b] (`docs/07` §10). Una carga distinguible por ataque,
## cuatro variantes de pisada, el loop de servos, el desgarro de pata, la
## fractura, el acorde de fase, el pulso de la autodestrucción y el estallido del
## EMP. Cada uno es una fila de [constant BANK] con su familia de síntesis:
##
## - `SWEEP`: barrido de frecuencia con armónicos, sub-grave y aire filtrado. Es
##   la carga de servo, y cambiando el par de frecuencias y el número de
##   armónicos salen ocho avisos que no se confunden entre sí.
## - `BUZZ`: portadora modulada en amplitud a frecuencia creciente. El EMP.
## - `RATTLE`: ruido metálico modulado a 12 Hz. El traqueteo del sacudón.
## - `IMPACT`: golpe sub-grave con cola de crujido. Pisadas y fracturas.
## - `BURST`: impulso más cola de ruido filtrado que se cierra. El EMP al soltar.
## - `TEAR`: ruido de desgarro con chillido agudo encima. La pata que se arranca.
## - `CHORD`: acorde descendente con respiración de servos. El cambio de fase.
## - `PING`: pulso corto. El tic de la cuenta atrás.
## - `LOOP`: motor filtrado, con las fases cuadradas al periodo para que empalme
##   sin chasquido. Los servos.
##
## [b]Determinismo[/b]: cada fila lleva su semilla, así que dos corridas producen
## byte a byte los mismos archivos. Sala limpia: no hay ninguna grabación de por
## medio (`docs/13` §5.4).
extends SceneTree

## Frecuencia de muestreo, en Hz.
const MIX_RATE: int = 44100

## Carpeta de salida dentro del proyecto.
const OUTPUT_DIR: String = "res://assets/audio/enemies"

## Familias de síntesis.
enum Kind { SWEEP, BUZZ, RATTLE, IMPACT, BURST, TEAR, CHORD, PING, LOOP }

## Fracción de Nyquist por encima de la cual no se sintetiza ningún parcial.
const NYQUIST_GUARD: float = 0.45

## Pico al que se normaliza cada sonido, en dBFS. Es el mismo que usan los loops
## de motor, para que el banco entero tenga el mismo nivel de partida.
const PEAK_DBFS: float = -6.0

## Semilla base; cada fila le suma la suya.
const BASE_SEED: int = 0x45_4E_4D_59

## El banco de `docs/07` §10. Cada fila: `kind`, `dur` en segundos, `seed` y los
## parámetros de su familia.
const BANK: Dictionary = {
	# --- Cargas de telegrafía, una por ataque (`docs/06` §11.2 canal 2) -------
	# `charge` es la genérica: la usa cualquier acción sin `audio_event`.
	"charge": {"kind": Kind.SWEEP, "dur": 2.4, "seed": 1,
		"from": 200.0, "to": 1800.0, "harmonics": 3, "sub": 48.0, "sub_gain": 0.55,
		"noise": Vector2(0.06, 0.26), "cutoff": Vector2(600.0, 5200.0)},
	# Trepar: gruñido grave y corto de servos bajo carga.
	"charge_climb": {"kind": Kind.SWEEP, "dur": 0.9, "seed": 2,
		"from": 90.0, "to": 260.0, "harmonics": 5, "sub": 38.0, "sub_gain": 0.80,
		"noise": Vector2(0.10, 0.18), "cutoff": Vector2(300.0, 1400.0)},
	# Pisotón: el chirrido ascendente de `docs/07` §5.4.
	"charge_stomp": {"kind": Kind.SWEEP, "dur": 1.1, "seed": 3,
		"from": 200.0, "to": 1400.0, "harmonics": 3, "sub": 46.0, "sub_gain": 0.60,
		"noise": Vector2(0.06, 0.28), "cutoff": Vector2(700.0, 4800.0)},
	# Barrido de pata: gruñido **descendente**, al revés que el pisotón. Es la
	# forma más barata de que dos ataques que cargan a la vez no se confundan.
	"charge_leg_sweep": {"kind": Kind.SWEEP, "dur": 0.9, "seed": 4,
		"from": 360.0, "to": 110.0, "harmonics": 4, "sub": 52.0, "sub_gain": 0.45,
		"noise": Vector2(0.14, 0.06), "cutoff": Vector2(3000.0, 900.0)},
	# Láser: silbido casi puro, un solo armónico.
	"charge_head_laser": {"kind": Kind.SWEEP, "dur": 1.6, "seed": 5,
		"from": 220.0, "to": 1900.0, "harmonics": 1, "sub": 0.0, "sub_gain": 0.0,
		"noise": Vector2(0.03, 0.12), "cutoff": Vector2(1800.0, 7000.0)},
	# Asedio: sub-grave de 35 Hz con armónico creciente (`docs/07` §10).
	"charge_siege_beam": {"kind": Kind.SWEEP, "dur": 1.8, "seed": 6,
		"from": 34.0, "to": 78.0, "harmonics": 6, "sub": 35.0, "sub_gain": 0.95,
		"noise": Vector2(0.04, 0.14), "cutoff": Vector2(200.0, 1100.0)},
	# EMP: zumbido de condensadores con el temblor acelerando.
	"charge_emp_pulse": {"kind": Kind.BUZZ, "dur": 2.2, "seed": 7,
		"carrier": 900.0, "am": Vector2(6.0, 44.0), "detune": 1.012, "noise": 0.10},
	# Salto: chillido de servo agudo.
	"charge_pounce": {"kind": Kind.SWEEP, "dur": 1.3, "seed": 8,
		"from": 600.0, "to": 2400.0, "harmonics": 2, "sub": 60.0, "sub_gain": 0.35,
		"noise": Vector2(0.05, 0.20), "cutoff": Vector2(2000.0, 8000.0)},
	# Sacudón: traqueteo metálico a la misma frecuencia a la que tiembla el
	# cuerpo (12 Hz, `docs/07` §5.10), para que lo que se ve y lo que se oye sean
	# el mismo gesto.
	"charge_shake_off": {"kind": Kind.RATTLE, "dur": 0.8, "seed": 9,
		"rate": 12.0, "partials": [430.0, 770.0, 1310.0], "noise": 0.55,
		"cutoff": Vector2(1200.0, 6000.0)},

	# --- Eventos (`docs/07` §10) ---------------------------------------------
	"emp_burst": {"kind": Kind.BURST, "dur": 1.4, "seed": 10,
		"cutoff": Vector2(7000.0, 300.0), "sub": 42.0, "sub_gain": 0.7},
	"footstep_1": {"kind": Kind.IMPACT, "dur": 0.85, "seed": 11,
		"sub": 42.0, "crack": 0.55, "cutoff": Vector2(3800.0, 500.0), "decay": 7.0},
	"footstep_2": {"kind": Kind.IMPACT, "dur": 0.85, "seed": 12,
		"sub": 52.0, "crack": 0.48, "cutoff": Vector2(3200.0, 460.0), "decay": 7.8},
	"footstep_3": {"kind": Kind.IMPACT, "dur": 0.85, "seed": 13,
		"sub": 61.0, "crack": 0.62, "cutoff": Vector2(4400.0, 620.0), "decay": 6.4},
	"footstep_4": {"kind": Kind.IMPACT, "dur": 0.85, "seed": 14,
		"sub": 70.0, "crack": 0.42, "cutoff": Vector2(2900.0, 420.0), "decay": 8.6},
	"servo_loop": {"kind": Kind.LOOP, "dur": 1.5, "seed": 15,
		"base": 78.0, "harmonics": 6, "wobble": 5.0, "noise": 0.12,
		"cutoff": Vector2(900.0, 900.0)},
	"leg_tear": {"kind": Kind.TEAR, "dur": 0.9, "seed": 16,
		"squeal": Vector2(1500.0, 2600.0), "sub": 40.0, "noise": 0.75,
		"cutoff": Vector2(6500.0, 1200.0)},
	"part_break": {"kind": Kind.IMPACT, "dur": 0.35, "seed": 17,
		"sub": 95.0, "crack": 0.85, "cutoff": Vector2(6000.0, 1400.0), "decay": 16.0},
	"phase_shift": {"kind": Kind.CHORD, "dur": 1.6, "seed": 18,
		"root": Vector2(220.0, 110.0), "ratios": [1.0, 1.5, 2.0, 3.0], "noise": 0.10,
		"cutoff": Vector2(2400.0, 600.0)},
	"selfdestruct_tick": {"kind": Kind.PING, "dur": 0.18, "seed": 19,
		"freq": 1180.0, "decay": 26.0, "click": 0.35},
}

## Sonidos que se importan con bucle (`edit/loop_mode = 1`).
const LOOPING: PackedStringArray = ["servo_loop"]

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


func _init() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var err := DirAccess.make_dir_recursive_absolute(absolute)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("No se pudo crear %s: %s" % [absolute, error_string(err)])
		quit(1)
		return

	var total := 0
	var names := PackedStringArray()
	for key: String in BANK:
		names.append(key)
	names.sort()
	for sound_name: String in names:
		var row := BANK[sound_name] as Dictionary
		var duration := float(row["dur"])
		var frames := int(round(duration * MIX_RATE))
		var rng := RandomNumberGenerator.new()
		rng.seed = BASE_SEED + int(row["seed"])
		var samples := _synth(row, frames, duration, rng)
		var looping := LOOPING.has(sound_name)
		var stream := _to_stream(_normalize(samples), frames, looping)
		var file_name := "%s.wav" % sound_name
		var path := "%s/%s" % [absolute, file_name]
		var write := stream.save_to_wav(path)
		if write != OK:
			push_error("No se pudo escribir %s: %s" % [path, error_string(write)])
			quit(1)
			return
		_write_import(OUTPUT_DIR.path_join(file_name), looping)
		total += FileAccess.get_file_as_bytes(path).size()
		print("  %-20s %5.2f s · %s%s" % [sound_name, duration,
				_kind_name(int(row["kind"])), " · bucle" if looping else ""])

	print("Banco de enemigos: %d sonidos, %d Hz, PCM 16 bits, %.1f KiB"
			% [names.size(), MIX_RATE, float(total) / 1024.0])
	print("Listo. Importá con: godot --headless --path godot --editor --quit")
	quit(0)


## Nombre legible de una familia, para el log.
func _kind_name(kind: int) -> String:
	match kind:
		Kind.SWEEP: return "sweep"
		Kind.BUZZ: return "buzz"
		Kind.RATTLE: return "rattle"
		Kind.IMPACT: return "impact"
		Kind.BURST: return "burst"
		Kind.TEAR: return "tear"
		Kind.CHORD: return "chord"
		Kind.PING: return "ping"
		Kind.LOOP: return "loop"
	return "?"


## Despacha a la familia de síntesis de la fila.
func _synth(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	match int(row["kind"]):
		Kind.SWEEP:
			return _synth_sweep(row, frames, duration, rng)
		Kind.BUZZ:
			return _synth_buzz(row, frames, duration, rng)
		Kind.RATTLE:
			return _synth_rattle(row, frames, duration, rng)
		Kind.IMPACT:
			return _synth_impact(row, frames, duration, rng)
		Kind.BURST:
			return _synth_burst(row, frames, duration, rng)
		Kind.TEAR:
			return _synth_tear(row, frames, duration, rng)
		Kind.CHORD:
			return _synth_chord(row, frames, duration, rng)
		Kind.PING:
			return _synth_ping(row, frames, duration)
		Kind.LOOP:
			return _synth_loop(row, frames, duration, rng)
	return _silence(frames)


# --------------------------------------------------------------------------
# Familias
# --------------------------------------------------------------------------

## Barrido de servo: la carga de telegrafía.
##
## La fase se **integra**: con un barrido lineal de f0 a f1, la fase en el
## instante t es `TAU · (f0·t + (f1−f0)·t²/(2·T))`. Escribir `TAU·f(t)·t` daría
## el doble de barrido del pretendido y un final una octava alto.
func _synth_sweep(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var cutoff := row["cutoff"] as Vector2
	var noise := _filtered_noise(rng, frames, cutoff.x, cutoff.y)
	var noise_gain := row["noise"] as Vector2
	var harmonics := int(row["harmonics"])
	var sub := float(row["sub"])
	var sub_gain := float(row["sub_gain"])
	var from := float(row["from"])
	var to := float(row["to"])
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var progress := t / duration
		var frequency := lerpf(from, to, progress)
		phase += TAU * frequency * inverse_rate
		var value := 0.0
		for harmonic: int in range(1, harmonics + 1):
			if frequency * float(harmonic) > NYQUIST_GUARD * float(MIX_RATE):
				break
			value += pow(float(harmonic), -1.6) * sin(phase * float(harmonic))
		if sub_gain > 0.0:
			value += sub_gain * sin(TAU * sub * t)
		value += lerpf(noise_gain.x, noise_gain.y, progress) * noise[index]
		# Meseta creciente: un servo que se tensa suena más fuerte cuanto más
		# cargado está.
		samples[index] = value * _envelope(t, duration, 0.12, 0.06) \
				* lerpf(0.55, 1.0, progress)
	return samples


## Zumbido de condensadores: portadora con modulación de amplitud acelerando.
func _synth_buzz(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var carrier := float(row["carrier"])
	var detune := float(row["detune"])
	var am := row["am"] as Vector2
	var noise := _filtered_noise(rng, frames, 1200.0, 4000.0)
	var noise_gain := float(row["noise"])
	var am_phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var progress := t / duration
		am_phase += TAU * lerpf(am.x, am.y, progress) * inverse_rate
		# Dos portadoras desafinadas dan el batido que hace «eléctrico» al
		# zumbido sin tener que modular la frecuencia.
		var tone := sin(TAU * carrier * t) + 0.7 * sin(TAU * carrier * detune * t)
		var depth := 0.5 + 0.5 * sin(am_phase)
		samples[index] = (tone * depth + noise_gain * noise[index]) \
				* _envelope(t, duration, 0.15, 0.05) * lerpf(0.4, 1.0, progress)
	return samples


## Traqueteo metálico modulado a `rate` Hz.
func _synth_rattle(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var cutoff := row["cutoff"] as Vector2
	var noise := _filtered_noise(rng, frames, cutoff.x, cutoff.y)
	var noise_gain := float(row["noise"])
	var partials := row["partials"] as Array
	var rate := float(row["rate"])
	for index: int in frames:
		var t := float(index) * inverse_rate
		# Diente de sierra rectificado: golpes secos, no una senoide suave.
		var gate := pow(absf(sin(PI * rate * t)), 3.0)
		var metal := 0.0
		for partial: float in partials:
			metal += sin(TAU * partial * t) / float(partials.size())
		samples[index] = (metal * 0.6 + noise_gain * noise[index]) * gate \
				* _envelope(t, duration, 0.03, 0.08)
	return samples


## Golpe sub-grave con cola de crujido: pisadas y fracturas.
func _synth_impact(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var cutoff := row["cutoff"] as Vector2
	var noise := _filtered_noise(rng, frames, cutoff.x, cutoff.y)
	var crack := float(row["crack"])
	var sub := float(row["sub"])
	var decay := float(row["decay"])
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		# El sub cae de tono mientras suena: es lo que hace que un golpe de 900
		# toneladas se lea como peso y no como un bombo.
		var frequency := sub * lerpf(1.6, 0.75, clampf(t * 6.0, 0.0, 1.0))
		phase += TAU * frequency * inverse_rate
		var body := sin(phase) * exp(-decay * 0.35 * t)
		var grit := crack * noise[index] * exp(-decay * t)
		samples[index] = (body + grit) * _envelope(t, duration, 0.004, 0.05)
	return samples


## Impulso con cola de ruido que se cierra: el EMP al soltar.
func _synth_burst(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var cutoff := row["cutoff"] as Vector2
	var noise := _filtered_noise(rng, frames, cutoff.x, cutoff.y)
	var sub := float(row["sub"])
	var sub_gain := float(row["sub_gain"])
	for index: int in frames:
		var t := float(index) * inverse_rate
		var tail := exp(-3.2 * t)
		var thump := sub_gain * sin(TAU * sub * t) * exp(-5.0 * t)
		samples[index] = (noise[index] * tail + thump) \
				* _envelope(t, duration, 0.002, 0.12)
	return samples


## Desgarro metálico con chillido agudo: la pata que se arranca.
func _synth_tear(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var cutoff := row["cutoff"] as Vector2
	var noise := _filtered_noise(rng, frames, cutoff.x, cutoff.y)
	var squeal := row["squeal"] as Vector2
	var noise_gain := float(row["noise"])
	var sub := float(row["sub"])
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var progress := t / duration
		phase += TAU * lerpf(squeal.x, squeal.y, progress) * inverse_rate
		# El chillido entra tarde y se va enseguida: primero se rompe el metal,
		# después chirría.
		var cry := sin(phase) * 0.45 * sin(PI * clampf(progress * 1.4, 0.0, 1.0))
		var rip := noise_gain * noise[index] * exp(-1.6 * t)
		var thud := 0.5 * sin(TAU * sub * t) * exp(-4.0 * t)
		samples[index] = (rip + cry + thud) * _envelope(t, duration, 0.004, 0.10)
	return samples


## Acorde descendente con respiración de servos: el cambio de fase.
func _synth_chord(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var cutoff := row["cutoff"] as Vector2
	var noise := _filtered_noise(rng, frames, cutoff.x, cutoff.y)
	var noise_gain := float(row["noise"])
	var root := row["root"] as Vector2
	var ratios := row["ratios"] as Array
	var phases := PackedFloat32Array()
	phases.resize(ratios.size())
	for index: int in frames:
		var t := float(index) * inverse_rate
		var progress := t / duration
		var fundamental := lerpf(root.x, root.y, progress * progress)
		var value := 0.0
		for voice: int in ratios.size():
			phases[voice] += TAU * fundamental * float(ratios[voice]) * inverse_rate
			value += sin(phases[voice]) / float(ratios.size())
		# Respiración: el ruido se abre y se cierra una vez sobre el acorde.
		var breath := noise_gain * noise[index] * sin(PI * progress)
		samples[index] = (value + breath) * _envelope(t, duration, 0.02, 0.25)
	return samples


## Pulso corto de la cuenta atrás.
func _synth_ping(row: Dictionary, frames: int, duration: float) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var frequency := float(row["freq"])
	var decay := float(row["decay"])
	var click := float(row["click"])
	for index: int in frames:
		var t := float(index) * inverse_rate
		var tone := sin(TAU * frequency * t) + 0.35 * sin(TAU * frequency * 2.01 * t)
		var attack := click * exp(-900.0 * t)
		samples[index] = (tone * exp(-decay * t) + attack) \
				* _envelope(t, duration, 0.0015, 0.02)
	return samples


## Loop de motor. Las frecuencias se **cuadran al periodo** —cada parcial lleva un
## número entero de ciclos en el archivo— para que el empalme del bucle no
## chasquee, y la envolvente es plana por la misma razón.
func _synth_loop(row: Dictionary, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var cutoff := row["cutoff"] as Vector2
	var noise := _filtered_noise(rng, frames, cutoff.x, cutoff.y)
	var noise_gain := float(row["noise"])
	var base := _snap_to_period(float(row["base"]), duration)
	var wobble := _snap_to_period(float(row["wobble"]), duration)
	var harmonics := int(row["harmonics"])
	for index: int in frames:
		var t := float(index) * inverse_rate
		var value := 0.0
		for harmonic: int in range(1, harmonics + 1):
			var frequency := base * float(harmonic)
			if frequency > NYQUIST_GUARD * float(MIX_RATE):
				break
			value += pow(float(harmonic), -1.3) * sin(TAU * frequency * t)
		# El bamboleo es lo que impide que el loop suene a tono puro sostenido.
		var swell := 0.85 + 0.15 * sin(TAU * wobble * t)
		samples[index] = (value + noise_gain * noise[index]) * swell
	return samples


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Frecuencia más cercana a [param frequency] que cierra un número entero de
## ciclos en [param duration] segundos.
func _snap_to_period(frequency: float, duration: float) -> float:
	var cycles := maxf(1.0, round(frequency * duration))
	return cycles / duration


## Buffer de ceros de [param frames] muestras.
func _silence(frames: int) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(frames)
	return samples


## Envolvente: rampa de entrada y caída al final, en segundos.
func _envelope(t: float, duration: float, attack: float, release: float) -> float:
	var rise := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var fall := clampf((duration - t) / maxf(release, 0.0001), 0.0, 1.0)
	return rise * fall


## Ruido blanco pasado por un polo simple cuyo corte va de [param from] a
## [param to] Hz a lo largo del archivo. Normalizado a pico 1.
func _filtered_noise(rng: RandomNumberGenerator, frames: int, from: float,
		to: float) -> PackedFloat32Array:
	var filtered := _silence(frames)
	var state := 0.0
	var peak := 0.0
	for index: int in frames:
		var progress := float(index) / float(maxi(frames - 1, 1))
		var cutoff := lerpf(from, to, progress)
		var alpha := clampf(1.0 - exp(-TAU * cutoff / float(MIX_RATE)), 0.0, 1.0)
		state += alpha * (rng.randf_range(-1.0, 1.0) - state)
		filtered[index] = state
		peak = maxf(peak, absf(state))
	if peak > 0.0:
		for index: int in frames:
			filtered[index] /= peak
	return filtered


## Escala las muestras para que el pico quede en [constant PEAK_DBFS].
func _normalize(samples: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	if peak <= 0.0:
		return samples
	var scale := db_to_linear(PEAK_DBFS) / peak
	for index: int in samples.size():
		samples[index] *= scale
	return samples


## Empaqueta las muestras como [AudioStreamWAV] PCM de 16 bits y mono.
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
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping \
			else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = frames if looping else 0
	return stream


## Escribe (o actualiza) el `.import` del WAV con [constant IMPORT_PARAMS].
##
## Conserva `[remap]` y `[deps]` si ya existían: el `uid` de un recurso importado
## es lo que referencian las escenas, y regenerar el sonido no debe cambiarlo.
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
		# **2**, no 1. El `edit/loop_mode` del importador es
		# `0 detectar · 1 deshabilitado · 2 adelante · 3 ping-pong · 4 atrás`, así que
		# el 1 que había acá importaba el `servo_loop` con el bucle **apagado**:
		# `AudioStreamWAV.loop_mode` quedaba en 0 y el loop de servos del jefe sonaba
		# 1.5 s y callaba, aunque el rig lo tratara como continuo (`docs/07` §10).
		# El WAV plano que escribe `save_to_wav()` no guarda puntos de bucle, así que
		# el 2 explícito es la única forma de pedirlo. Lo mismo hace
		# `tools/generate_motor_sounds.gd`, que sí lo tenía bien.
		config.set_value("params", "edit/loop_mode", 2)
	var err := config.save(import_path)
	if err != OK:
		push_error("No se pudo escribir %s: %s" % [import_path, error_string(err)])
