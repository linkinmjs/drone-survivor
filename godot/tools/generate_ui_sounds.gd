## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sintetiza los cinco sonidos cortos de interfaz en `assets/audio/ui/*.wav`.
##
## Uso:
## [codeblock]
## godot --headless --path godot --script res://tools/generate_ui_sounds.gd
## [/codeblock]
##
## ## Timbre «de hojalata» (WP-25)
##
## Antes eran senos limpios, que es el sonido de una aplicación bien terminada. La
## identidad «Última luz» dice lo contrario: **lo propio tiene imperfección** y lo
## enemigo es exacto (`docs/narrativa/identidad-visual-opciones.md` §6; «los servos
## enemigos suenan limpios, el dron suena a hojalata»).
##
## Así que cada sonido es ahora una onda de **armónicos impares** —1, 3, 5, 7, como una
## cuadrada a medio filtrar—, con el tercer parcial ligeramente desafinado
## ([constant DETUNE]) para que bata un poco, ataque de [constant ATTACK_SECONDS] y
## caída corta. Los **niveles no cambian**: el pico de cada onda se normaliza al mismo
## `volume` que tenía el seno, de modo que `UI.play()` y las mezclas de `docs/13` §5.1
## siguen valiendo tal cual.
extends SceneTree

## Frecuencia de muestreo.
const MIX_RATE := 44100

## Carpeta de salida.
const OUTPUT_DIR := "res://assets/audio/ui"

## Ataque, en segundos. Corto pero no instantáneo: un ataque de cero muestras hace clic
## de codificación, no de interfaz.
const ATTACK_SECONDS := 0.0015

## Amplitud relativa de cada armónico impar (1, 3, 5, 7). Es una cuadrada recortada:
## suficiente metal para que suene a chapa, sin el zumbido de una cuadrada entera.
const HARMONICS: Array[float] = [1.0, 0.45, 0.22, 0.1]

## Desafinación del tercer parcial, en fracción de su frecuencia. Lo que hace que la
## nota «bata» como una pieza suelta.
const DETUNE := 0.012

## Cada sonido: `[Hz inicial, Hz final, duración s, volumen pico, caída]`.
##
## Los tres primeros campos y el volumen son los mismos que tenía la versión de senos;
## lo único nuevo es la caída, que separa un toque seco (`tick`) de un rechazo que
## resuena un poco más (`error`).
const SOUNDS := {
	"hover": [1760.0, 1760.0, 0.035, 0.16, 6.0],
	"click": [1180.0, 880.0, 0.07, 0.32, 7.0],
	"back": [740.0, 520.0, 0.09, 0.28, 6.0],
	"tick": [2400.0, 2400.0, 0.018, 0.12, 9.0],
	"error": [330.0, 250.0, 0.16, 0.3, 4.0],
}


func _init() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var _err := DirAccess.make_dir_recursive_absolute(absolute)
	for sound_name: String in SOUNDS:
		var params: Array = SOUNDS[sound_name]
		var stream := _synth(params[0], params[1], params[2], params[3], params[4])
		var path := "%s/%s.wav" % [absolute, sound_name]
		var err := stream.save_to_wav(path)
		print("%s -> %s (%s)" % [sound_name, path, error_string(err)])
	quit(0)


## Una onda de armónicos impares de [param start_hz] a [param end_hz] que dura
## [param duration] segundos y llega como mucho a [param volume].
func _synth(start_hz: float, end_hz: float, duration: float, volume: float,
		decay: float) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	# Normalizar por la suma de amplitudes deja el pico en `volume` exacto, que es lo
	# que mantiene los niveles de la versión anterior.
	var norm := 0.0
	for amplitude: float in HARMONICS:
		norm += amplitude
	var phase := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		var progress := float(i) / count
		var frequency := lerpf(start_hz, end_hz, progress)
		phase += TAU * frequency / MIX_RATE
		var attack := clampf(t / ATTACK_SECONDS, 0.0, 1.0)
		var envelope := exp(-progress * decay)
		var tail := clampf((1.0 - progress) / 0.12, 0.0, 1.0)
		var sample := 0.0
		for index: int in HARMONICS.size():
			var partial := float(index * 2 + 1)
			if index == 1:
				partial *= 1.0 + DETUNE
			sample += HARMONICS[index] * sin(phase * partial)
		sample *= volume * attack * envelope * tail / norm
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
