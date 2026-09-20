## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Capturas A/B del entorno para el checkpoint 4 (`docs/13` §3.5 y §11 #3).
##
## Monta la batalla de verdad y la fotografía en dos encuadres fijos —el final del
## travelling de `INTRO` y una vista FPV con el jefe y la ciudad— por cada
## combinación de variante de GI (A: SDFGI · B: ambiente + SSIL) y operador de
## tonemap (AgX · ACES), más una captura en preset LOW. Son las imágenes que el
## usuario mira al lado de la tabla de `render_check` para decidir.
##
## **Necesita GPU**: con `--headless` no hay rasterizado y las capturas salen negras,
## así que imprime un SKIP y sale con 0, igual que `render_check`.
##
## [codeblock]
## godot --windowed --resolution 1920x1080 --disable-vsync --path godot \
##     res://tools/environment_shots.tscn -- --shots=tools/out/shots
## [/codeblock]
##
## Argumentos propios:
## [codeblock]
## --variants=high_a_agx,high_b_agx   sólo esas variantes (por defecto, todas)
## --frames=<n>                       cuadros de asentamiento por captura (90)
## --shots-only=intro|fpv             un solo encuadre (por defecto, los dos)
## --tweak=fog_density=0.0008;glow_intensity=0.6
##                                    sobreescribe propiedades del `Environment` del
##                                    nivel después de montarlo, para barrer valores
##                                    sin regenerar el `.tres` (riesgo 6 de §11)
## [/codeblock]
##
## ## Por qué el encuadre no lo elige un bot
##
## Una comparación A/B sólo sirve si las dos imágenes son la **misma** imagen. Un
## [BotPilot] volando no repite trayectoria entre corridas, así que el dron se
## congela en una pose calculada a partir de la posición del jefe y del centro de la
## ciudad, y la IA se detiene con `Global.debug_freeze_ai`. Con la misma semilla,
## las ocho capturas son pixel a pixel el mismo encuadre.
##
## ## Estadísticas
##
## Además del PNG, cada captura imprime luminancia media, percentiles y porcentaje
## de píxeles quemados o aplastados a negro. Los valores de `docs/13` §3.1 son un
## punto de partida (riesgo 6 de §11) y esos números son lo que permite ajustarlos
## sin abrir un editor de imagen.
extends CheckRunner

const LEVEL_SCENE: String = "res://rounds/battle_level.tscn"
const ROUND_ID: String = "first-contact"
const ROUND_SEED: int = 1

## Segundo del travelling de `INTRO` en el que se dispara la captura. La cinemática
## dura [constant RoundManager.INTRO_SECONDS] = 12 s; a los 11 la cámara ya está
## sobre el jefe y la ciudad entra por detrás.
const INTRO_SHOT_SECONDS: float = 11.0

## Pose de la vista FPV, medida **desde el jefe** igual que el travelling. El dron
## se pone del lado **opuesto** a la ciudad para que, mirando al jefe, el distrito
## entre en cuadro detrás de él: la captura tiene que mostrar las dos cosas.
const FPV_BACK: float = 74.0
const FPV_SIDE: float = 40.0
const FPV_HEIGHT: float = 26.0

## Altura del punto al que mira el dron sobre la base del jefe, en metros. El casco
## del Arachnodroid está entre 22 y 29 m (`docs/07` §2).
const FPV_LOOK_HEIGHT: float = 20.0

## Cuadros de asentamiento por defecto antes de capturar: SDFGI necesita varios
## para llenar las cascadas y la niebla volumétrica reproyecta en el tiempo.
const DEFAULT_SETTLE_FRAMES: int = 90

## Variantes, en orden. `preset` es un [enum Graphics.Quality].
const VARIANTS: Array[Dictionary] = [
	{"id": "high_a_agx", "label": "HIGH · A (SDFGI) · AgX", "preset": 2, "variant": 0, "tonemap": 0},
	{"id": "high_a_aces", "label": "HIGH · A (SDFGI) · ACES", "preset": 2, "variant": 0, "tonemap": 1},
	{"id": "high_b_agx", "label": "HIGH · B (ambiente+SSIL) · AgX", "preset": 2, "variant": 1, "tonemap": 0},
	{"id": "high_b_aces", "label": "HIGH · B (ambiente+SSIL) · ACES", "preset": 2, "variant": 1, "tonemap": 1},
	{"id": "low_a_agx", "label": "LOW · A · AgX", "preset": 0, "variant": 0, "tonemap": 0},
]

var _settle_frames: int = DEFAULT_SETTLE_FRAMES
var _quality_before: int = 0
var _variant_before: int = 0
var _tonemap_before: int = 0
var _freeze_before: bool = false
var _seed_before: int = 0
var _round_before: String = ""


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  SKIP: environment_shots necesita GPU y no corre con --headless.")
		print("  Corralo con: --windowed --resolution 1920x1080 --disable-vsync")
		return
	get_tree().current_scene = null
	_settle_frames = int(user_args().get("frames", DEFAULT_SETTLE_FRAMES))
	var wanted := String(user_args().get("variants", ""))
	_quality_before = int(Graphics.quality)
	_variant_before = int(Graphics.gi_variant)
	_tonemap_before = int(Graphics.tonemap)
	_freeze_before = Global.debug_freeze_ai
	_seed_before = Global.round_seed
	_round_before = Global.selected_round

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var size := DisplayServer.window_get_size()
	print("  ventana %dx%d · %d cuadros de asentamiento por captura" % [size.x, size.y, _settle_frames])
	if size.x < 1920 or size.y < 1080:
		print("  AVISO: las capturas de `docs/13` §3.5 son a 1920x1080; esta ventana es menor.")

	for variant: Dictionary in VARIANTS:
		var id := String(variant["id"])
		if not wanted.is_empty() and not wanted.split(",").has(id):
			continue
		await _shoot_variant(variant)

	Graphics.gi_variant = _variant_before as Graphics.GiVariant
	Graphics.tonemap = _tonemap_before as Graphics.Tonemap
	Graphics.apply_quality_preset(_quality_before as Graphics.Quality, false)
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	Global.debug_freeze_ai = _freeze_before
	Global.round_seed = _seed_before
	Global.selected_round = _round_before


## Monta la batalla con la variante puesta y saca las dos capturas.
func _shoot_variant(variant: Dictionary) -> void:
	var id := String(variant["id"])
	print("")
	print("  === %s (%s) ===" % [id, String(variant["label"])])
	Graphics.gi_variant = int(variant["variant"]) as Graphics.GiVariant
	Graphics.tonemap = int(variant["tonemap"]) as Graphics.Tonemap
	Graphics.apply_quality_preset(int(variant["preset"]) as Graphics.Quality, false)
	Graphics.vsync = Graphics.VSync.OFF
	Graphics.max_fps = 0
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	Global.debug_freeze_ai = true
	Global.selected_round = ROUND_ID
	Global.round_seed = ROUND_SEED
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % LEVEL_SCENE)
		return
	var level := packed.instantiate() as BattleLevel
	if level == null:
		fail("%s no instancia un BattleLevel" % LEVEL_SCENE)
		return
	add_child(level)
	await wait_frames(4)
	_apply_tweaks(level)
	_report_setup(level)
	var only := String(user_args().get("shots-only", ""))

	# 1. Final del travelling de INTRO.
	var manager := level.get_round_manager()
	if only != "fpv":
		if manager != null:
			await _advance_intro(manager)
		await wait_frames(_settle_frames)
		await _capture("%s_intro" % id)

	# 2. Vista FPV con el jefe y la ciudad.
	if only != "intro":
		if manager != null:
			manager.skip_intro()
			await wait_frames(4)
			_park_drone(level, manager)
		await wait_frames(_settle_frames)
		await _capture("%s_fpv" % id)

	level.queue_free()
	await wait_frames(3)


## Vuelca los `--tweak=` sobre el `Environment` del nivel.
##
## Existe para el barrido de valores de `docs/13` §11 #6: una corrida con
## `--tweak=volumetric_fog_density=0.004;fog_density=0.0008` dice en veinte
## segundos lo que regenerar el `.tres` y volver a arrancar dice en dos minutos.
## No persiste nada: el `.tres` sólo cambia cuando lo reescribe
## `tools/build_environment.gd`.
func _apply_tweaks(level: BattleLevel) -> void:
	var raw := String(user_args().get("tweak", ""))
	if raw.is_empty():
		return
	var world := level.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	var env := world.environment if world != null else null
	if env == null:
		return
	for pair: String in raw.split(";", false):
		var parts := pair.split("=", false, 1)
		if parts.size() != 2:
			fail("--tweak mal formado: '%s'" % pair)
			continue
		var key := parts[0].strip_edges()
		var text := parts[1].strip_edges()
		var value: Variant = text.to_float() if text.is_valid_float() else str_to_var(text)
		if text == "true" or text == "false":
			value = text == "true"
		env.set(key, value)
		print("  tweak     : %s = %s" % [key, str(env.get(key))])


## Deja correr la cinemática hasta [constant INTRO_SHOT_SECONDS].
func _advance_intro(manager: RoundManager) -> void:
	var deadline := RoundManager.INTRO_SECONDS - INTRO_SHOT_SECONDS
	while manager.get_intro_remaining() > deadline:
		await get_tree().process_frame
		if manager.get_intro_remaining() <= 0.0:
			return


## Congela el dron en una pose fija mirando al jefe, con la ciudad detrás.
func _park_drone(level: BattleLevel, manager: RoundManager) -> void:
	var rig := level.drone_rig as DroneRig
	if rig == null:
		fail("el nivel no trae DroneRig: no hay vista FPV que capturar")
		return
	var drone := rig.get_drone()
	if drone == null:
		fail("el DroneRig no trae Drone")
		return
	var enemies := manager.get_enemies()
	var boss := Vector3.ZERO
	if not enemies.is_empty():
		var enemy := enemies[0] as Node3D
		if enemy != null:
			boss = enemy.global_position
	var city := Vector3.ZERO
	var grid := level.get_city_grid()
	if grid != null:
		city = grid.to_global(grid.avenue_crossing())
	var away := city - boss
	away.y = 0.0
	away = Vector3.BACK * 100.0 if away.length() < 1.0 else away.normalized()
	var side := Vector3(-away.z, 0.0, away.x)
	var position := boss - away * FPV_BACK + side * FPV_SIDE + Vector3.UP * FPV_HEIGHT
	var target := boss + Vector3.UP * FPV_LOOK_HEIGHT

	drone.force_disarm()
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	drone.freeze = true
	drone.global_position = position
	drone.look_at(target, Vector3.UP)
	var fpv := rig.get_fpv_camera()
	if fpv != null:
		var _focused := level.focus_camera(fpv)
	print("  FPV: dron en %s mirando a %s (jefe %s)"
			% [_v(position), _v(target), _v(boss)])


## Imprime lo que quedó puesto: probes, SDFGI, SSIL y tonemap del clon del nivel.
func _report_setup(level: BattleLevel) -> void:
	var world := level.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	var env := world.environment if world != null else null
	if env == null:
		fail("el nivel no trae WorldEnvironment con Environment")
		return
	print("  entorno   : sdfgi %s · ssil %s · ssao %s · niebla vol. %s (%.0f m) · glow %s"
			% [_b(env.sdfgi_enabled), _b(env.ssil_enabled), _b(env.ssao_enabled),
			_b(env.volumetric_fog_enabled), env.volumetric_fog_length, _b(env.glow_enabled)])
	print("  color     : tonemap %s · exposición %.2f · saturación %.2f · ambiente %s a %.2f"
			% ["ACES" if env.tonemap_mode == Environment.TONE_MAPPER_ACES else "AgX",
			env.tonemap_exposure, env.adjustment_saturation,
			env.ambient_light_color.to_html(false), env.ambient_light_energy])
	var probes := level.get_reflection_probes()
	print("  probes    : %d (preset pide %d)"
			% [probes.size(), Graphics.reflection_probe_count()])
	for probe: ReflectionProbe in probes:
		print("    %s en %s · caja %s · max_distance %.0f m · box_projection %s"
				% [probe.name, _v(probe.global_position), _v(probe.size),
				probe.max_distance, str(probe.box_projection)])
	var suns := Graphics.get_registered_suns()
	if suns.is_empty():
		fail("ningún sol registrado: LevelBase._register_sun() no encontró la luz")
		return
	var sun := suns[0]
	print("  sol       : %.0f lux × %.2f · color %s · %s° · penumbra %.2f° · sombra %.0f m"
			% [sun.light_intensity_lux, sun.light_energy, sun.light_color.to_html(false),
			_v(sun.rotation_degrees), sun.light_angular_distance,
			sun.directional_shadow_max_distance])


## Guarda la captura y tabula sus estadísticas.
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		fail("no se pudo capturar '%s': el viewport no devolvió imagen" % file_name)
		return
	_print_stats(file_name, image)
	if shots_dir.is_empty():
		return
	var path := "%s/%s.png" % [shots_dir, file_name]
	var err := image.save_png(path)
	if err != OK:
		fail("no se pudo guardar la captura '%s': %s" % [path, error_string(err)])
		return
	print("  captura   : %s" % path)


## Histograma de luminancia sobre una malla de muestreo. No recorre los 2 M de
## píxeles: con un paso de 4 en los dos ejes quedan 130 000 muestras, que es de
## sobra para una media y unos percentiles y no cuesta segundos.
func _print_stats(file_name: String, image: Image) -> void:
	var step := 4
	var samples: PackedFloat32Array = PackedFloat32Array()
	var clipped: int = 0
	var crushed: int = 0
	var warm: int = 0
	var cool: int = 0
	for y: int in range(0, image.get_height(), step):
		for x: int in range(0, image.get_width(), step):
			var c := image.get_pixel(x, y)
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			samples.append(l)
			if l > 0.98:
				clipped += 1
			elif l < 0.02:
				crushed += 1
			if c.b > c.r + 0.02:
				cool += 1
			elif c.r > c.b + 0.02:
				warm += 1
	if samples.is_empty():
		return
	samples.sort()
	var total := float(samples.size())
	var sum: float = 0.0
	for value: float in samples:
		sum += value
	print("  %s: luz media %.3f · p01 %.3f · p50 %.3f · p99 %.3f · quemado %.1f%% · negro %.1f%% · frío %.0f%% / cálido %.0f%%"
			% [file_name, sum / total,
			samples[int(total * 0.01)], samples[int(total * 0.5)], samples[int(total * 0.99)],
			100.0 * float(clipped) / total, 100.0 * float(crushed) / total,
			100.0 * float(cool) / total, 100.0 * float(warm) / total])


func _b(value: bool) -> String:
	return "on" if value else "off"


func _v(value: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [value.x, value.y, value.z]
