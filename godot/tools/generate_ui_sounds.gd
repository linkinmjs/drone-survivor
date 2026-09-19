## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
extends SceneTree
## Synthesizes the short interface sounds into assets/audio/ui/*.wav.
## Usage: godot --headless --path godot -s res://tools/generate_ui_sounds.gd
## Soft sine "clicks" with a fast attack and an exponential decay, to fit the minimal look.


const MIX_RATE := 44100
const OUTPUT_DIR := "res://assets/audio/ui"

## name: [start Hz, end Hz, duration s, volume, second harmonic amount]
const SOUNDS := {
	"hover": [1760.0, 1760.0, 0.035, 0.16, 0.0],
	"click": [1180.0, 880.0, 0.07, 0.32, 0.15],
	"back": [740.0, 520.0, 0.09, 0.28, 0.1],
	"tick": [2400.0, 2400.0, 0.018, 0.12, 0.0],
	"error": [330.0, 250.0, 0.16, 0.3, 0.3],
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


func _synth(start_hz: float, end_hz: float, duration: float, volume: float,
		harmonic: float) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		var progress := float(i) / count
		var frequency := lerpf(start_hz, end_hz, progress)
		phase += TAU * frequency / MIX_RATE
		var attack := clampf(t / 0.003, 0.0, 1.0)
		var decay := exp(-progress * 5.0)
		var tail := clampf((1.0 - progress) / 0.1, 0.0, 1.0)
		var sample := sin(phase) + harmonic * sin(phase * 2.0)
		sample *= volume * attack * decay * tail / (1.0 + harmonic)
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
