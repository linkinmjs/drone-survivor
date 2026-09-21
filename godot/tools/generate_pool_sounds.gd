## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sintetiza el banco de realimentación de combate que dispara el [AudioPool], en
## `assets/audio/combat/*.wav` (`docs/13` §5.4 y §8, WP-27).
##
## Cómo regenerarlo (desde la raíz del repositorio):
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot -s res://tools/generate_pool_sounds.gd
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot --editor --quit
##
## Son los seis sonidos que `docs/13` §8 le pide al pool y que no tenían archivo:
## el banco de la ciudad está en `generate_city_sounds.gd`, el del jefe en
## `generate_enemy_sounds.gd` y el del arma en `generate_weapon_sounds.gd`.
##
## [b]Las dos reglas de identidad de `docs/13` §1[/b] mandan acá más que ninguna
## otra cosa:
##
## - **Lo propio suena a hojalata**: armónicos impares con el tercer parcial
##   desafinado un 1.2 %, exactamente como los sonidos de interfaz de WP-25.
##   `hull_hit`, `signal_cut` y `power_up` están hechos así: el dron es chapa
##   soldada en un taller, no una nave.
## - **Nada enemigo es cálido y nada propio es cian**: el punto débil es cian, y
##   `impact_weak` es su sonido —vidrio y electricidad, parciales altos y
##   crepitación—, bien separado del `impact_armor`, que es un golpe sordo sin
##   brillo. Son los dos timbres que hoy no se distinguen: el `ImpactFX` toca el
##   mismo `impact.wav` para los dos.
##
## [b]Los cuatro sonidos de WP-27b[/b] son la voz de los efectos que WP-26 dejó
## mudos: el haz del láser, el del asedio, las chispas de una parte dañada y el
## anillo del EMP. Los tres bucles se sintetizan **cerrados sobre sí mismos** —toda
## frecuencia periódica se cuadra al periodo del archivo y los granos que cruzan el
## final se pliegan sobre el principio—, así que el empalme no chasquea; el log
## imprime la derivada máxima incluyendo ese salto.
##
## Determinista y sin grabaciones, como el resto de los bancos.
extends SceneTree

## Frecuencia de muestreo, en Hz.
const MIX_RATE: int = 44100

## Carpeta de salida.
const OUTPUT_DIR: String = "res://assets/audio/combat"

## Pico al que se normaliza cada sonido, en dBFS.
const PEAK_DBFS: float = -6.0

## Semilla base; cada sonido le suma la suya.
const BASE_SEED: int = 0x50_4F_4F_4C

## Desafinado del tercer parcial de la hojalata.
const TIN_DETUNE: float = 1.012

## Parámetros del importador. `compress/mode = 0` es PCM sin comprimir.
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

## El banco: nombre, duración y semilla.
const BANK: Array[Dictionary] = [
	{"name": "impact_armor", "dur": 0.28, "seed": 1},
	{"name": "impact_weak", "dur": 0.40, "seed": 2},
	{"name": "part_fall", "dur": 1.20, "seed": 3},
	{"name": "hull_hit", "dur": 0.34, "seed": 4},
	{"name": "signal_cut", "dur": 1.00, "seed": 5},
	{"name": "power_up", "dur": 1.30, "seed": 6},
	# WP-27b: los efectos de WP-26 que estaban mudos.
	{"name": "laser_loop", "dur": 2.00, "seed": 7},
	{"name": "siege_loop", "dur": 2.50, "seed": 8},
	{"name": "sparks_loop", "dur": 1.60, "seed": 9},
	{"name": "emp_ring", "dur": 1.20, "seed": 10},
]

## Sonidos que se importan en bucle (`edit/loop_mode = 2`).
const LOOPING: PackedStringArray = ["laser_loop", "siege_loop", "sparks_loop"]


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
		var rng := RandomNumberGenerator.new()
		rng.seed = BASE_SEED + int(row["seed"])
		var looping := LOOPING.has(sound_name)
		var samples := _normalize(_synth(sound_name, frames, duration, rng), PEAK_DBFS)
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
		# El `|Δ|máx` de un sonido con ruido de banda ancha es alto por definición
		# —una muestra de ruido salta medio fondo de escala— así que por sí solo no
		# dice si el bucle empalma. Lo que lo dice es el **salto de empalme** contra
		# el máximo del interior: si el primero no se despega del segundo, el punto
		# de costura es una muestra más y no se oye.
		var seam := " · bucle (empalme %.4f de %.4f)" % [_seam_jump(samples),
				_max_slope(samples, false)] if looping else ""
		print("  %-14s %6.3f s · %6d muestras · RMS %6.2f dBFS · pico %6.2f dBFS · |Δ|máx %.4f%s"
				% [sound_name, duration, frames, _rms_db(samples), _peak_db(samples),
				_max_slope(samples, looping), seam])

	print("Banco de combate: %d sonidos, %d Hz, PCM 16 bits mono, %.1f KiB"
			% [BANK.size(), MIX_RATE, float(total) / 1024.0])
	print("Listo. Importá con: godot --headless --path godot --editor --quit")
	quit(0)


func _synth(sound_name: String, frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	match sound_name:
		"impact_armor":
			return _synth_impact_armor(frames, duration, rng)
		"impact_weak":
			return _synth_impact_weak(frames, duration, rng)
		"part_fall":
			return _synth_part_fall(frames, duration, rng)
		"hull_hit":
			return _synth_hull_hit(frames, duration, rng)
		"signal_cut":
			return _synth_signal_cut(frames, duration, rng)
		"power_up":
			return _synth_power_up(frames, duration, rng)
		"laser_loop":
			return _synth_laser_loop(frames, duration, rng)
		"siege_loop":
			return _synth_siege_loop(frames, duration, rng)
		"sparks_loop":
			return _synth_sparks_loop(frames, duration, rng)
		"emp_ring":
			return _synth_emp_ring(frames, duration, rng)
	return _silence(frames)


## Golpe sordo contra blindaje: parciales graves que mueren rápido y nada de
## brillo. La bala no perfora, rebota.
func _synth_impact_armor(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var grit := _lowpass(_noise(rng, frames), 1600.0)
	var partials: Array[float] = [178.0, 406.0, 761.0]
	for index: int in frames:
		var t := float(index) * inverse_rate
		var metal := 0.0
		for order: int in partials.size():
			metal += sin(TAU * partials[order] * t) \
					* exp(-(26.0 + 22.0 * float(order)) * t) / float(order + 1)
		var thud := 0.6 * sin(TAU * 96.0 * t) * exp(-34.0 * t)
		var attack := clampf(t / 0.0006, 0.0, 1.0)
		samples[index] = (metal + thud + grit[index] * 0.5 * exp(-90.0 * t)) \
				* attack * _envelope(t, duration, 0.0004, 0.06)
	return _lowpass(samples, 3200.0)


## Punto débil: vidrio y electricidad. Parciales altos, crepitación modulada y un
## zumbido que se apaga. Es el cian del jefe hecho sonido.
func _synth_impact_weak(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var spark := _highpass(_noise(rng, frames), 2600.0)
	var partials: Array[float] = [1420.0, 2870.0, 4310.0, 6180.0]
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var glass := 0.0
		for order: int in partials.size():
			glass += sin(TAU * partials[order] * t) \
					* exp(-(14.0 + 9.0 * float(order)) * t) / float(order + 1)
		# Crepitación: ruido agudo picado a 140 Hz, que es lo que suena a
		# descarga y no a sisear.
		var crackle := spark[index] * (0.5 + 0.5 * sin(TAU * 140.0 * t)) * exp(-11.0 * t)
		# Y un barrido descendente corto: el circuito que se va.
		phase += TAU * lerpf(2400.0, 700.0, clampf(t / 0.18, 0.0, 1.0)) * inverse_rate
		var zap := 0.3 * sin(phase) * exp(-18.0 * t)
		var attack := clampf(t / 0.0004, 0.0, 1.0)
		samples[index] = (glass + crackle * 0.8 + zap) * attack \
				* _envelope(t, duration, 0.0003, 0.09)
	return samples


## Una parte que se desprende y **cae**: el desgarro corto y, 0.35 s después, el
## golpe contra el asfalto con su cola de chatarra. El `part_break` del [AudioRig]
## toca la fractura; esto es lo que pasa a continuación.
func _synth_part_fall(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var tear := _bandpass(_noise(rng, frames), 2100.0, 2400.0)
	var debris := _bandpass(_noise(rng, frames), 900.0, 1800.0)
	var landing := 0.35
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		# Desgarro: aire y metal doblándose.
		var rip := tear[index] * 0.5 * exp(-7.0 * t)
		# Caída: sub que pega en el suelo con cola de chatarra rebotando.
		var since := maxf(t - landing, 0.0)
		var hit := 0.0
		if t >= landing:
			phase += TAU * lerpf(88.0, 46.0, clampf(since * 12.0, 0.0, 1.0)) * inverse_rate
			hit = sin(phase) * exp(-9.0 * since) \
					+ debris[index] * 0.55 * exp(-5.0 * since) \
					* (0.6 + 0.4 * sin(TAU * 23.0 * since))
			hit *= clampf(since / 0.001, 0.0, 1.0)
		samples[index] = (rip + hit) * _envelope(t, duration, 0.002, 0.25)
	return samples


## Golpe recibido en el casco: hojalata pura. Armónicos impares, tercer parcial
## desafinado y un traqueteo que queda temblando.
func _synth_hull_hit(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var rattle := _bandpass(_noise(rng, frames), 1500.0, 2200.0)
	var base := 268.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var tin := sin(TAU * base * t) * exp(-19.0 * t) \
				+ 0.62 * sin(TAU * base * 3.0 * TIN_DETUNE * t) * exp(-25.0 * t) \
				+ 0.34 * sin(TAU * base * 5.0 * t) * exp(-33.0 * t) \
				+ 0.18 * sin(TAU * base * 7.0 * t) * exp(-44.0 * t)
		# La chapa sigue temblando después del golpe: eso es lo que la delata.
		var shiver := rattle[index] * 0.35 * exp(-12.0 * t) * (0.5 + 0.5 * sin(TAU * 62.0 * t))
		var thud := 0.5 * sin(TAU * 74.0 * t) * exp(-28.0 * t)
		var attack := clampf(t / 0.0005, 0.0, 1.0)
		samples[index] = (tin + shiver + thud) * attack * _envelope(t, duration, 0.0004, 0.05)
	return samples


## Corte de señal: el vídeo se va. Un tono que cae, la estática del enlace
## perdido y el silencio de golpe, que es lo que da el susto.
func _synth_signal_cut(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var fuzz := _bandpass(_noise(rng, frames), 1800.0, 3200.0)
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		# El tono de enlace cayendo dos octavas en 0.4 s: «se apagó».
		phase += TAU * lerpf(640.0, 150.0, clampf(t / 0.4, 0.0, 1.0)) * inverse_rate
		var tone := (sin(phase) + 0.45 * sin(phase * 3.0 * TIN_DETUNE)) * exp(-3.6 * t)
		# La estática entra mientras el tono se va y se corta en seco a los 0.72 s.
		var alive := 1.0 if t < 0.72 else 0.0
		var hiss := fuzz[index] * 0.55 * clampf(t / 0.25, 0.0, 1.0) * alive
		# Y un último chasquido de relé al cortar.
		var relay := 0.6 * exp(-900.0 * absf(t - 0.72))
		samples[index] = (tone * alive * 0.8 + hiss * 0.5 + relay) \
				* _envelope(t, duration, 0.003, 0.2)
	return samples


## Arranque de hojalata: el taller devuelve el dron. Relé, condensadores cargando
## y el zumbido de los motores tomando revoluciones, en tres golpes.
func _synth_power_up(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var air := _lowpass(_noise(rng, frames), 900.0)
	var phase := 0.0
	var charge := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		# Zumbido que sube de 60 a 240 Hz: los motores despertando.
		phase += TAU * lerpf(60.0, 240.0, clampf(t / 0.9, 0.0, 1.0)) * inverse_rate
		var motor := (sin(phase) + 0.4 * sin(phase * 3.0 * TIN_DETUNE)) \
				* clampf(t / 0.35, 0.0, 1.0) * 0.55
		# Condensadores: zumbido agudo que se acelera y se apaga.
		charge += TAU * lerpf(900.0, 1750.0, clampf(t / 0.6, 0.0, 1.0)) * inverse_rate
		var caps := 0.3 * sin(charge) * exp(-4.5 * t) * (0.5 + 0.5 * sin(TAU * 26.0 * t))
		# Tres relés: el taller cerrando los contactos, uno por sistema.
		var relays := 0.0
		for click: int in 3:
			var at := 0.05 + float(click) * 0.16
			relays += (0.55 - 0.12 * float(click)) * exp(-700.0 * absf(t - at))
		samples[index] = (motor + caps + relays + air[index] * 0.12 * clampf(t / 0.5, 0.0, 1.0)) \
				* _envelope(t, duration, 0.002, 0.18)
	return samples


# --------------------------------------------------------------------------
# WP-27b: haces, chispas y anillo
# --------------------------------------------------------------------------

## Haz del láser de cabeza: zumbido eléctrico **fino**, sin cuerpo grave.
##
## Es el cian del jefe hecho sonido sostenido (`docs/13` §1: nada enemigo es
## cálido, nada propio es cian). Dos portadoras cerca de 2 kHz separadas unos pocos
## hercios dan el batido lento que impide que suene a tono de prueba; encima, aire
## filtrado agudo. Todo pasa-altos: el haz **no** tiene graves, y eso es lo que lo
## separa del asedio cuando los dos suenan a la vez.
func _synth_laser_loop(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	# Cuadradas al periodo: es lo único que hace empalmable un bucle tonal.
	var carrier := _snap_to_period(1980.0, duration)
	var beat := _snap_to_period(1984.5, duration)
	var shimmer := _snap_to_period(3.5, duration)
	var wobble := _snap_to_period(31.0, duration)
	var air := _highpass(_noise(rng, frames), 4200.0)
	for index: int in frames:
		var t := float(index) * inverse_rate
		# El batido sale solo de la diferencia entre las dos portadoras.
		var tone := sin(TAU * carrier * t) + 0.85 * sin(TAU * beat * t)
		# Un tercer parcial impar muy flaco: filo metálico sin engordar el timbre.
		tone += 0.22 * sin(TAU * carrier * 3.0 * t)
		# Temblor de 31 Hz: electrónica trabajando, no un oscilador limpio.
		var tremor := 0.88 + 0.12 * sin(TAU * wobble * t)
		var breathe := 0.82 + 0.18 * sin(TAU * shimmer * t)
		samples[index] = (tone * 0.45 * tremor + air[index] * 0.18) * breathe
	return _highpass(samples, 900.0)


## Haz de asedio: grave, ancho y con el hormigón derritiéndose.
##
## Lo contrario del anterior: tres parciales sub-graves, ruido pasa-bajos ancho con
## ondulación lenta y un crepitar granular esparcido por todo el bucle, que es el
## material cediendo. Los granos que cruzan el final se pliegan sobre el principio,
## así que el crepitar tampoco delata el punto de empalme.
func _synth_siege_loop(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var body := _lowpass(_noise(rng, frames), 320.0)
	var partials: Array[float] = [
		_snap_to_period(44.0, duration),
		_snap_to_period(67.0, duration),
		_snap_to_period(91.0, duration),
	]
	var surge := _snap_to_period(1.6, duration)
	var grind := _snap_to_period(7.0, duration)
	for index: int in frames:
		var t := float(index) * inverse_rate
		var low := 0.0
		for order: int in partials.size():
			low += sin(TAU * partials[order] * t) / float(order + 2)
		# Dos ondulaciones de periodos distintos: ancho, no pulsante.
		var swell := 0.75 + 0.25 * sin(TAU * surge * t)
		var rasp := 0.85 + 0.15 * sin(TAU * grind * t + 1.3)
		samples[index] = (low * 0.55 + body[index] * 0.6) * swell * rasp
	# Crepitar de hormigón: granos cortos y secos repartidos por todo el bucle.
	var crackle := _highpass(_noise(rng, frames), 1800.0)
	var grain_frames := int(0.06 * MIX_RATE)
	var time := 0.0
	while true:
		time += rng.randf_range(0.012, 0.075)
		if time >= duration:
			break
		var start := int(time * MIX_RATE)
		var decay := rng.randf_range(90.0, 320.0)
		var gain := rng.randf_range(0.10, 0.34)
		for offset: int in grain_frames:
			var local := float(offset) * inverse_rate
			var at := (start + offset) % frames
			samples[at] += crackle[at] * gain * exp(-decay * local)
	return samples


## Chispas de una parte dañada: crepitar eléctrico intermitente, corto y seco.
##
## Ni zumbido continuo ni fuego: son descargas sueltas. Cada una es ruido agudo con
## una caída de milisegundos y, una de cada tres, un chasquido tonal encima. Nada
## cálido y nada grave, por identidad (`docs/13` §1).
func _synth_sparks_loop(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	var hiss := _highpass(_noise(rng, frames), 3000.0)
	var grain_frames := int(0.08 * MIX_RATE)
	var time := 0.0
	while true:
		time += rng.randf_range(0.02, 0.19)
		if time >= duration:
			break
		var start := int(time * MIX_RATE)
		var decay := rng.randf_range(120.0, 460.0)
		var gain := rng.randf_range(0.25, 1.0)
		var zap := rng.randf() < 0.34
		var pitch := rng.randf_range(2600.0, 4900.0)
		for offset: int in grain_frames:
			var local := float(offset) * inverse_rate
			var at := (start + offset) % frames
			var value := hiss[at] * gain * exp(-decay * local)
			if zap:
				value += 0.35 * gain * sin(TAU * pitch * local) * exp(-decay * 1.6 * local)
			samples[at] += value
	# Un siseo de fondo muy bajo une las descargas: sin él, el bucle suena a
	# archivo cortado entre chispa y chispa.
	for index: int in frames:
		samples[index] += hiss[index] * 0.035
	return samples


## Anillo del EMP: barrido que **se aleja**.
##
## Es lo que le falta al destello de `VFXRing`: el frente de onda saliendo. Un
## silbido cuyo filtro se cierra de 6 kHz a 300 Hz mientras el tono baja de 900 a
## 120 Hz, con el cuerpo hinchándose primero y yéndose después. El golpe grave ya
## lo pone el `emp_burst` del rig; esto es la estela.
func _synth_emp_ring(frames: int, duration: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var samples := _silence(frames)
	var inverse_rate := 1.0 / float(MIX_RATE)
	# Pasa-bajos de un polo con el corte cayendo a lo largo del archivo: eso es
	# exactamente «alejarse», porque lo primero que se pierde son los agudos.
	var sweep := _silence(frames)
	var state := 0.0
	var source := _noise(rng, frames)
	for index: int in frames:
		var progress := float(index) / float(maxi(frames - 1, 1))
		var cutoff := lerpf(6000.0, 300.0, progress * progress)
		var alpha := clampf(1.0 - exp(-TAU * cutoff / float(MIX_RATE)), 0.0, 1.0)
		state += alpha * (source[index] - state)
		sweep[index] = state
	var phase := 0.0
	for index: int in frames:
		var t := float(index) * inverse_rate
		var progress := t / duration
		# Tono descendente: la altura cae como cae la energía del frente.
		phase += TAU * lerpf(900.0, 120.0, progress * progress) * inverse_rate
		var tone := sin(phase) * 0.4 + 0.18 * sin(phase * 2.0)
		# Se hincha en los primeros 150 ms y se va durante el resto: eso se lee
		# como «se aleja» y no como «explotó».
		var swell := pow(clampf(t / 0.15, 0.0, 1.0), 0.7) * exp(-2.1 * t)
		samples[index] = (sweep[index] * 1.4 + tone) * swell \
				* _envelope(t, duration, 0.004, 0.25)
	return samples


# --------------------------------------------------------------------------
# Utilidades de señal
# --------------------------------------------------------------------------

## Frecuencia más cercana a [param frequency] que cierra un número entero de ciclos
## en [param duration] segundos. Es lo que hace empalmable un bucle tonal.
func _snap_to_period(frequency: float, duration: float) -> float:
	var cycles := maxf(1.0, round(frequency * duration))
	return cycles / duration

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


## Pasa-altos de un polo, normalizado a pico 1.
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


## Pasa-banda de dos polos, normalizado a pico 1.
func _bandpass(samples: PackedFloat32Array, centre: float,
		bandwidth: float) -> PackedFloat32Array:
	var out := _silence(samples.size())
	var r := exp(-PI * bandwidth / float(MIX_RATE))
	var w := TAU * centre / float(MIX_RATE)
	var y1 := 0.0
	var y2 := 0.0
	var peak := 0.0
	for index: int in samples.size():
		var value := samples[index] * (1.0 - r * r) + 2.0 * r * cos(w) * y1 - r * r * y2
		y2 = y1
		y1 = value
		out[index] = value
		peak = maxf(peak, absf(value))
	if peak > 0.0:
		for index: int in out.size():
			out[index] /= peak
	return out


func _silence(frames: int) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(frames)
	return samples


func _envelope(t: float, duration: float, attack: float, release: float) -> float:
	var rise := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var fall := clampf((duration - t) / maxf(release, 0.0001), 0.0, 1.0)
	return rise * fall


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


## Salto entre la última muestra y la primera: la costura del bucle.
func _seam_jump(samples: PackedFloat32Array) -> float:
	if samples.size() < 2:
		return 0.0
	return absf(samples[0] - samples[samples.size() - 1])


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


## Escribe (o actualiza) el `.import`, conservando `uid` y `path` si ya existían.
##
## `edit/loop_mode` del importador: 0 detectar, 1 **deshabilitado**, 2 adelante. Un
## WAV plano no guarda puntos de bucle, así que un bucle necesita el 2 explícito;
## con el 1 el archivo suena una vez y calla.
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
