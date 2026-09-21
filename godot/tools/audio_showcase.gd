## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Escaparate de audio (WP-27): reproduce 20 s de la mezcla completa y vuelca los
## **picos por bus** a la consola.
##
## Corre así:
##
##     "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" \
##         --headless --path godot res://tools/audio_showcase.tscn
##
## No es un check y nunca falla: es el equivalente auditivo de las capturas de
## `render_check`. En `--headless` no hay forma de *escuchar* nada, así que lo que
## se entrega para revisar es la tabla de niveles: si el derrumbe tapa la música,
## si la interfaz se pierde bajo los motores o si el `Master` está pegado al techo
## del limitador, se ve en estos números sin necesidad de tarjeta de sonido.
##
## La línea de tiempo recorre una ronda comprimida —alerta, intro, combate,
## derrumbes, fase 3, muerte y vuelta, victoria— y cada dos segundos imprime una
## fila con el pico de los siete buses en dBFS.
extends CheckRunner

## Duración del recorrido, en segundos.
const SHOWCASE_SECONDS: float = 20.0

## Cada cuánto se imprime una fila de niveles, en segundos.
const REPORT_PERIOD: float = 2.0

## Cada cuánto se mide el pico, en segundos. Se mide mucho más seguido de lo que
## se imprime y se guarda el máximo: un pico de 60 ms no aparece si solo se mira
## dos veces por segundo.
const SAMPLE_PERIOD: float = 0.05

## Los siete buses, en el orden de la tabla.
const BUSES: Array[StringName] = [&"Master", &"Motors", &"Weapons", &"Enemies",
		&"City", &"UI", &"Music"]

## La ronda comprimida: segundo, qué pasa y una etiqueta para el log.
const TIMELINE: Array[Dictionary] = [
	{"at": 0.5, "event": "state_intro", "label": "INTRO: la ciudad dormida"},
	{"at": 3.0, "event": "state_battle", "label": "BATTLE p1: entra la tensión"},
	{"at": 5.0, "event": "shots", "label": "ráfaga sobre el blindaje"},
	{"at": 6.5, "event": "weak", "label": "impacto en punto débil"},
	{"at": 8.0, "event": "collapse", "label": "derrumbe de edificio"},
	{"at": 9.5, "event": "part", "label": "rotura y caída de una pata"},
	{"at": 11.0, "event": "phase3", "label": "fase p3_fury: entra el combate"},
	{"at": 13.0, "event": "battery", "label": "pila recogida"},
	{"at": 14.0, "event": "damage", "label": "golpe en el casco"},
	{"at": 15.0, "event": "down", "label": "dron destruido"},
	{"at": 17.0, "event": "respawn", "label": "dron reconstruido"},
	{"at": 18.5, "event": "victory", "label": "VICTORY: sting"},
]

var _pool: AudioPool = null
var _music: MusicDirector = null
var _peaks: PackedFloat32Array = PackedFloat32Array()


func _run() -> void:
	_pool = AudioPool.new()
	_pool.name = "AudioPool"
	_pool.armor_policy = AudioPool.ArmorPolicy.ALWAYS
	add_child(_pool)
	_music = MusicDirector.new()
	_music.name = "MusicDirector"
	add_child(_music)
	await wait_frames(2)

	_peaks.resize(BUSES.size())
	_reset_peaks()
	print("  Escaparate de audio: %.0f s, picos en dBFS por bus" % SHOWCASE_SECONDS)
	print("  %-6s %s" % ["t", _header()])

	var start := Time.get_ticks_usec()
	var next_report := REPORT_PERIOD
	var next_sample := 0.0
	var fired := 0
	var elapsed := 0.0
	while elapsed < SHOWCASE_SECONDS:
		await get_tree().process_frame
		elapsed = float(Time.get_ticks_usec() - start) / 1000000.0
		while fired < TIMELINE.size() and elapsed >= float(TIMELINE[fired]["at"]):
			_fire(String(TIMELINE[fired]["event"]))
			print("  %-6.1f · %s" % [elapsed, String(TIMELINE[fired]["label"])])
			fired += 1
		if elapsed >= next_sample:
			next_sample = elapsed + SAMPLE_PERIOD
			_sample_peaks()
		if elapsed >= next_report:
			next_report += REPORT_PERIOD
			print("  %-6.1f %s" % [elapsed, _row()])
			_reset_peaks()

	print("  voces al cerrar: %d de %d · ambiente %s"
			% [_pool.active_voices(), _pool.budget(), str(_pool.is_ambience_playing())])
	_music.stop()
	_pool.stop_all()
	# `AudioStreamPlayer.stop()` no libera la reproducción en el acto: el
	# `AudioServer` la deja apagándose un par de bloques de mezcla. Liberar el nodo
	# antes de eso deja el `AudioStreamPlaybackSynchronized` —y con él los tres
	# stems— vivos en el servidor, que es lo que Godot reporta al cerrar como
	# instancias filtradas. Un cuarto de segundo alcanza y sobra.
	await _wait_seconds(0.25)
	_music.queue_free()
	_music = null
	_pool.queue_free()
	_pool = null
	await wait_frames(3)


## Cede el control durante [param seconds] de reloj de pared.
func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame


## Dispara un hito de la línea de tiempo por el bus de eventos, que es como
## llegaría en una partida de verdad.
func _fire(event: String) -> void:
	match event:
		"state_intro":
			Events.round_state_changed.emit(Global.RoundState.INTRO)
		"state_battle":
			Events.round_state_changed.emit(Global.RoundState.BATTLE)
		"shots":
			for shot: int in 5:
				Events.hit_confirmed.emit(Vector3(float(shot) * 2.0, 3.0, 20.0), false, false,
						&"armor")
		"weak":
			Events.hit_confirmed.emit(Vector3(4.0, 6.0, 18.0), true, false, &"weak")
		"collapse":
			Events.building_destroyed.emit(Vector3(40.0, 0.0, 30.0), 120)
		"part":
			Events.enemy_part_broken.emit(null, &"wp_leg_fl_knee", Vector3(12.0, 8.0, 24.0))
		"phase3":
			Events.enemy_phase_changed.emit(null, &"p3_fury")
		"battery":
			Events.battery_collected.emit(0.4, Vector3(3.0, 1.0, 4.0))
		"damage":
			Events.drone_damaged.emit(18.0, Vector3(8.0, 4.0, 10.0))
		"down":
			Events.drone_destroyed.emit(Vector3(0.0, 2.0, 0.0))
		"respawn":
			Events.drone_respawned.emit(1.0)
		"victory":
			Events.round_state_changed.emit(Global.RoundState.VICTORY)


## Guarda el pico más alto visto desde la última fila.
func _sample_peaks() -> void:
	for index: int in BUSES.size():
		var bus := AudioServer.get_bus_index(BUSES[index])
		if bus < 0:
			continue
		var peak := maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0),
				AudioServer.get_bus_peak_volume_right_db(bus, 0))
		if is_finite(peak):
			_peaks[index] = maxf(_peaks[index], peak)


func _reset_peaks() -> void:
	for index: int in _peaks.size():
		_peaks[index] = -200.0


func _header() -> String:
	var parts: Array[String] = []
	for bus: StringName in BUSES:
		parts.append("%7s" % String(bus))
	return " ".join(parts)


func _row() -> String:
	var parts: Array[String] = []
	for index: int in BUSES.size():
		parts.append("%7s" % ("  -inf" if _peaks[index] <= -199.0 else "%6.1f" % _peaks[index]))
	return " ".join(parts)
