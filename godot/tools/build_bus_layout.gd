## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Escribe `default_bus_layout.tres` con los siete buses de `docs/13` §5.1 y sus
## efectos (WP-27).
##
## Cómo regenerarlo (desde la raíz del repositorio):
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot -s res://tools/build_bus_layout.gd
##
## Es la misma idea que `tools/build_theme.gd` y `tools/build_environment.gd`: el
## `.tres` **no se edita a mano**, se genera desde una tabla de constantes que se
## puede leer al lado del documento que la fija. Un `AudioBusLayout` con efectos
## escrito a mano es un archivo con sub-recursos anónimos, imposible de revisar en
## un diff; generado, la revisión es esta tabla.
##
## [b]Cómo se arma[/b]: la herramienta configura el `AudioServer` vivo —nombres,
## envíos, volúmenes y efectos— y después le pide [method AudioServer.generate_bus_layout],
## que devuelve exactamente el estado del servidor como recurso. Así no hay dos
## fuentes de verdad: lo que se guarda es lo que sonaría.
##
## [b]Los dB de acá son la base[/b]. El autoload [Audio] (`docs/04` §3.3) aplica
## encima el volumen lineal que el jugador dejó en el menú, **sumando** en dB:
## `volumen_del_bus = base + linear_to_db(lineal)`. Con el 0.8 lineal por defecto
## eso son −1.94 dB sobre la base, o sea `Motors` suena a −5.94 dB. Ver
## [constant Audio.BASE_VOLUMES_DB], que tiene que coincidir con la tabla de acá.
extends SceneTree

## Archivo de salida. Es el que `project.godot` carga como layout por defecto.
const OUTPUT_PATH: String = "res://default_bus_layout.tres"

## Los siete buses en orden, con su volumen base en dB (`docs/13` §5.1). `Master`
## es el índice 0 y no envía a ningún lado; el resto envía a `Master`.
const BUSES: Array[Dictionary] = [
	{"name": &"Master", "db": 0.0},
	{"name": &"Motors", "db": -4.0},
	{"name": &"Weapons", "db": -3.0},
	{"name": &"Enemies", "db": -2.0},
	{"name": &"City", "db": -5.0},
	{"name": &"UI", "db": -6.0},
	{"name": &"Music", "db": -8.0},
]

## Compresor del `Master`: umbral −12 dB, 4:1, ataque 20 ms, release 180 ms.
const COMPRESSOR_THRESHOLD_DB: float = -12.0
const COMPRESSOR_RATIO: float = 4.0
const COMPRESSOR_ATTACK_US: float = 20000.0
const COMPRESSOR_RELEASE_MS: float = 180.0

## Techo del limitador del `Master`, en dB.
const LIMITER_CEILING_DB: float = -0.5

## Reverb de `City`: sala mediana, poco húmeda. Es lo que separa un derrumbe —que
## pasa entre edificios— de un impacto en el casco, que pasa en el micrófono.
const REVERB_ROOM_SIZE: float = 0.6
const REVERB_DAMPING: float = 0.4
const REVERB_WET: float = 0.12

## Pasa-bajos de `Music`, **deshabilitado** salvo en pausa (`docs/13` §5.1). Lo
## enciende y lo apaga [method Audio.set_music_lowpass], que llama [PauseMenu].
const LOWPASS_CUTOFF_HZ: float = 600.0
const LOWPASS_RESONANCE: float = 0.5


func _init() -> void:
	_apply_buses()
	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, OUTPUT_PATH)
	if err != OK:
		push_error("No se pudo escribir %s: %s" % [OUTPUT_PATH, error_string(err)])
		quit(1)
		return
	_print_layout()
	print("Layout escrito en %s" % OUTPUT_PATH)
	quit(0)


## Deja el `AudioServer` con los siete buses, sus volúmenes y sus efectos.
func _apply_buses() -> void:
	AudioServer.set_bus_count(BUSES.size())
	for index: int in BUSES.size():
		var row := BUSES[index]
		AudioServer.set_bus_name(index, String(row["name"]))
		AudioServer.set_bus_volume_db(index, float(row["db"]))
		AudioServer.set_bus_solo(index, false)
		AudioServer.set_bus_mute(index, false)
		AudioServer.set_bus_bypass_effects(index, false)
		if index > 0:
			AudioServer.set_bus_send(index, &"Master")
		while AudioServer.get_bus_effect_count(index) > 0:
			AudioServer.remove_bus_effect(index, 0)

	_add_master_chain(0)
	_add_reverb(AudioServer.get_bus_index(&"City"))
	_add_lowpass(AudioServer.get_bus_index(&"Music"))


## Compresor y limitador del `Master`, en ese orden: el compresor junta el rango y
## el limitador impide que la suma de 24 voces pase de −0.5 dBFS.
func _add_master_chain(bus: int) -> void:
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = COMPRESSOR_THRESHOLD_DB
	compressor.ratio = COMPRESSOR_RATIO
	compressor.attack_us = COMPRESSOR_ATTACK_US
	compressor.release_ms = COMPRESSOR_RELEASE_MS
	compressor.gain = 0.0
	compressor.mix = 1.0
	AudioServer.add_bus_effect(bus, compressor)

	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(bus, limiter)


func _add_reverb(bus: int) -> void:
	if bus < 0:
		return
	var reverb := AudioEffectReverb.new()
	reverb.room_size = REVERB_ROOM_SIZE
	reverb.damping = REVERB_DAMPING
	reverb.wet = REVERB_WET
	reverb.dry = 1.0
	AudioServer.add_bus_effect(bus, reverb)


## El pasa-bajos nace **apagado**: la música suena entera mientras se juega y solo
## se enturbia con el árbol en pausa.
func _add_lowpass(bus: int) -> void:
	if bus < 0:
		return
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = LOWPASS_CUTOFF_HZ
	lowpass.resonance = LOWPASS_RESONANCE
	AudioServer.add_bus_effect(bus, lowpass)
	AudioServer.set_bus_effect_enabled(bus, AudioServer.get_bus_effect_count(bus) - 1, false)


## Vuelca la tabla final para que el log del build valga como revisión.
func _print_layout() -> void:
	for index: int in AudioServer.get_bus_count():
		var effects := PackedStringArray()
		for slot: int in AudioServer.get_bus_effect_count(index):
			var effect := AudioServer.get_bus_effect(index, slot)
			var state := "" if AudioServer.is_bus_effect_enabled(index, slot) else " (apagado)"
			effects.append("%s%s" % [effect.get_class(), state])
		print("  %-8s %+6.1f dB -> %-7s %s" % [AudioServer.get_bus_name(index),
				AudioServer.get_bus_volume_db(index),
				String(AudioServer.get_bus_send(index)) if index > 0 else "-",
				", ".join(effects) if not effects.is_empty() else "sin efectos"])
