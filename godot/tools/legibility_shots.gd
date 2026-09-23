## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Capturas y métricas de **legibilidad** para el checkpoint 4.
##
## El usuario jugó la tanda 4 y dijo que «los disparos y las luces de fondo
## dificultan un poco la visión». Esta herramienta convierte esa frase en números
## comparables: fotografía la batalla de verdad en encuadres fijos, con y sin
## fogonazo, cerca de una fachada encendida y con un haz en pantalla, e imprime
## por cada captura la luminancia de la **región central** (30 % del cuadro, que es
## donde vive el retículo y donde el jugador busca al jefe) además de la del cuadro
## entero.
##
## Reutiliza el método de `tools/environment_shots.gd` —dron congelado en una pose
## calculada, IA detenida, misma semilla— porque una comparación A/B sólo sirve si
## las dos imágenes son la misma imagen. Lo que agrega es el **fogonazo**: cada
## encuadre se captura dos veces, una con el destello apagado y otra en el pico del
## pulso, y la diferencia entre las dos es exactamente lo que el jugador llama «no
## veo cuando disparo».
##
## [codeblock]
## godot --windowed --resolution 1920x1080 --disable-vsync --path godot \
##     res://tools/legibility_shots.tscn -- --shots=<dir> --tag=antes
## [/codeblock]
##
## Argumentos propios:
## [codeblock]
## --tag=antes                 prefijo de los nombres de archivo (por defecto, "")
## --frames=<n>                cuadros de asentamiento por captura (60)
## --shots-only=boss|win|street|beam   un solo grupo de encuadres
## --distances=40,60,80        distancias al jefe, en metros
## --tweak=glow_intensity=0.55;glow_hdr_threshold=2.0
##                             sobreescribe el `Environment` del nivel en caliente
## --flash=lumens=0.4;range=2.0;bloom_size=0.6;bloom_albedo=0.4
##                             escala el fogonazo en caliente (factores, salvo `range`
##                             que son metros) para barrer valores sin tocar la escena
## --emission=0.65             escala `emission_energy_multiplier` de las fachadas
## [/codeblock]
##
## Nada de esto persiste: los `.tres` sólo cambian por `tools/build_environment.gd`
## y por una edición explícita de la escena del fogonazo.
extends CheckRunner

const LEVEL_SCENE: String = "res://rounds/battle_level.tscn"
const ROUND_ID: String = "first-contact"
const ROUND_SEED: int = 1
const SIEGE_BEAM_SCENE: String = "res://vfx/siege_beam.tscn"

## Familias de fachada cuyo emisivo son las ventanas (`docs/10` §1, WP-25b).
const FACADE_MATERIALS: Array[String] = [
	"res://assets/city/materials/buildings_001.tres",
	"res://assets/city/materials/buildings_002.tres",
	"res://assets/city/materials/props.tres",
	"res://assets/city/materials/roads.tres",
]

## Fracción del **área** del cuadro que ocupa la región central medida. 0.30 deja
## un rectángulo centrado de 0.5477 de lado, o sea 1052 × 591 px a 1080p.
const CENTRAL_AREA: float = 0.30

## Altura del punto del jefe al que mira el dron, sobre su base. El casco del
## Arachnodroid está entre 22 y 29 m (`docs/07` §2).
const BOSS_LOOK_HEIGHT: float = 20.0

## Altura del dron sobre la base del jefe en los encuadres de combate.
const BOSS_SHOT_HEIGHT: float = 22.0

## Distancia a la fachada del encuadre de ventanas, en metros. Es la distancia del
## criterio de halo (`≤ 6 px a 1080p alrededor de una ventana a 30 m`).
const WINDOW_DISTANCE: float = 30.0

## Altura y retroceso del encuadre de vuelo bajo entre manzanas.
const STREET_HEIGHT: float = 12.0
const STREET_BACK: float = 70.0

## Cuadros que se capturan tras encender el fogonazo. El pulso dura 0.06 s y la
## ventana corre sin vsync, así que el pico cae en un cuadro distinto según los fps:
## se capturan varios y se guarda el más brillante.
const FLASH_FRAMES: int = 6

const DEFAULT_SETTLE_FRAMES: int = 60

var _settle_frames: int = DEFAULT_SETTLE_FRAMES
var _tag: String = ""
var _level: BattleLevel = null
var _quality_before: int = 0
var _variant_before: int = 0
var _tonemap_before: int = 0
var _freeze_before: bool = false
var _seed_before: int = 0
var _round_before: String = ""
var _emission_before: Dictionary[String, float] = {}

## Referencias vivas a los materiales de fachada mientras dura la corrida.
##
## Sin esto el barrido de emisivo **no hacía nada**: `ResourceLoader.load()` dentro
## de una función devuelve una referencia que muere al volver, el recurso se
## descarga y la ciudad lo vuelve a leer del disco con el valor original. Guardarlo
## acá mantiene viva la misma instancia que después cargan las mallas.
var _facade_materials: Array[StandardMaterial3D] = []


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  SKIP: legibility_shots necesita GPU y no corre con --headless.")
		print("  Corralo con: --windowed --resolution 1920x1080 --disable-vsync")
		return
	get_tree().current_scene = null
	_settle_frames = int(user_args().get("frames", DEFAULT_SETTLE_FRAMES))
	_tag = String(user_args().get("tag", ""))
	_quality_before = int(Graphics.quality)
	_variant_before = int(Graphics.gi_variant)
	_tonemap_before = int(Graphics.tonemap)
	_freeze_before = Global.debug_freeze_ai
	_seed_before = Global.round_seed
	_round_before = Global.selected_round

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var size := DisplayServer.window_get_size()
	print("  ventana %dx%d · región central %.0f %% del área · %d cuadros de asentamiento"
			% [size.x, size.y, CENTRAL_AREA * 100.0, _settle_frames])
	if size.x < 1920 or size.y < 1080:
		print("  AVISO: los criterios de halo son a 1920x1080; esta ventana es menor.")

	# HIGH · A (SDFGI) · AgX: la variante recomendada por WP-24 y la que juega el usuario.
	Graphics.gi_variant = Graphics.GiVariant.A_SDFGI
	Graphics.tonemap = Graphics.Tonemap.AGX
	Graphics.apply_quality_preset(Graphics.Quality.HIGH, false)
	Graphics.vsync = Graphics.VSync.OFF
	Graphics.max_fps = 0
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_apply_emission_scale()
	await _mount_level()
	if _level == null:
		_restore_emission_scale()
		return

	# `--shots-only` admite una lista: `--shots-only=win,street`.
	var only := String(user_args().get("shots-only", "")).split(",", false)
	if only.is_empty() or only.has("boss"):
		await _shoot_boss()
	if only.is_empty() or only.has("win"):
		await _shoot_windows()
	if only.is_empty() or only.has("street"):
		await _shoot_street()
	if only.is_empty() or only.has("beam"):
		await _shoot_beam()

	_level.queue_free()
	await wait_frames(3)
	_restore_emission_scale()
	Graphics.gi_variant = _variant_before as Graphics.GiVariant
	Graphics.tonemap = _tonemap_before as Graphics.Tonemap
	Graphics.apply_quality_preset(_quality_before as Graphics.Quality, false)
	Graphics.apply_all()
	Graphics.environment_quality_changed.emit()
	Global.debug_freeze_ai = _freeze_before
	Global.round_seed = _seed_before
	Global.selected_round = _round_before


# --- Montaje ------------------------------------------------------------------------------------

## Monta la batalla congelada y salta directo al estado BATTLE.
func _mount_level() -> void:
	Global.debug_freeze_ai = true
	Global.selected_round = ROUND_ID
	Global.round_seed = ROUND_SEED
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % LEVEL_SCENE)
		return
	_level = packed.instantiate() as BattleLevel
	if _level == null:
		fail("%s no instancia un BattleLevel" % LEVEL_SCENE)
		return
	add_child(_level)
	await wait_frames(4)
	_apply_tweaks()
	_apply_flash_tweaks()
	var manager := _level.get_round_manager()
	if manager != null:
		manager.skip_to_battle()
		# El salto a BATTLE dispara el corte de estática del `GlitchLayer`
		# ([constant RoundManager.STATIC_SECONDS] = 0.4 s). Sin vsync la ventana
		# corre a cientos de fps, así que esperar «unos cuadros» no alcanza: las
		# primeras capturas salían con la pantalla de ruido encima. Se espera por
		# **reloj**, no por cuadros.
		await _wait_seconds(RoundManager.STATIC_SECONDS * 3.0)
	_report_setup()


## Cede el control durante [param seconds] de tiempo real.
func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## Vuelca los `--tweak=` sobre el `Environment` del nivel (mismo contrato que
## `tools/environment_shots.gd`).
func _apply_tweaks() -> void:
	var raw := String(user_args().get("tweak", ""))
	if raw.is_empty():
		return
	var env := _environment()
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


## Escala el fogonazo en caliente para barrer valores sin tocar la escena.
##
## `lumens` y `bloom_albedo` son **factores** sobre lo que trae la escena; `range`
## son metros y `bloom_size` es un factor sobre el lado del quad.
func _apply_flash_tweaks() -> void:
	var raw := String(user_args().get("flash", ""))
	if raw.is_empty():
		return
	var flash := _muzzle_flash()
	if flash == null:
		fail("--flash: el dron no trae MuzzleFlash")
		return
	var light := flash.get_node_or_null(^"FlashLight") as OmniLight3D
	var bloom := flash.get_node_or_null(^"Bloom") as MeshInstance3D
	var particles := flash.get_node_or_null(^"Particles") as GPUParticles3D
	var process: ParticleProcessMaterial = null
	if particles != null:
		process = (particles.process_material as ParticleProcessMaterial).duplicate() \
				as ParticleProcessMaterial
		particles.process_material = process
	for pair: String in raw.split(";", false):
		var parts := pair.split("=", false, 1)
		if parts.size() != 2:
			fail("--flash mal formado: '%s'" % pair)
			continue
		var key := parts[0].strip_edges()
		var value := parts[1].strip_edges().to_float()
		match key:
			"lumens":
				if light != null:
					light.light_intensity_lumens *= value
					print("  flash     : lúmenes = %.0f" % light.light_intensity_lumens)
			"range":
				if light != null:
					light.omni_range = value
					print("  flash     : alcance = %.2f m" % light.omni_range)
			"bloom_size":
				if bloom != null:
					var mesh := (bloom.mesh as QuadMesh).duplicate() as QuadMesh
					mesh.size *= value
					bloom.mesh = mesh
					print("  flash     : quad = %.3f m" % mesh.size.x)
			"bloom_albedo":
				if bloom != null:
					var material := bloom.get_active_material(0)
					var standard := (material as StandardMaterial3D)
					if standard != null:
						var copy := standard.duplicate() as StandardMaterial3D
						copy.albedo_color = Color(
								copy.albedo_color.r * value,
								copy.albedo_color.g * value,
								copy.albedo_color.b * value, 1.0)
						bloom.material_override = copy
						print("  flash     : albedo del quad = (%.2f, %.2f, %.2f)"
								% [copy.albedo_color.r, copy.albedo_color.g, copy.albedo_color.b])
			"spark_amount":
				if particles != null:
					particles.amount = maxi(int(value), 1)
					print("  flash     : chispas = %d" % particles.amount)
			"spark_spread":
				if process != null:
					process.spread = value
					print("  flash     : dispersión = %.0f°" % process.spread)
			"spark_scale":
				if process != null:
					process.scale_min *= value
					process.scale_max *= value
					print("  flash     : escala de chispa = %.3f–%.3f"
							% [process.scale_min, process.scale_max])
			"spark_albedo":
				if particles != null:
					var mesh := particles.draw_pass_1 as QuadMesh
					var standard := (mesh.material if mesh != null else null) as StandardMaterial3D
					if standard != null:
						var copy := standard.duplicate() as StandardMaterial3D
						copy.albedo_color = Color(
								copy.albedo_color.r * value,
								copy.albedo_color.g * value,
								copy.albedo_color.b * value, 1.0)
						var quad := mesh.duplicate() as QuadMesh
						quad.material = copy
						particles.draw_pass_1 = quad
						print("  flash     : albedo de chispa = (%.2f, %.2f, %.2f)"
								% [copy.albedo_color.r, copy.albedo_color.g, copy.albedo_color.b])
			"spark_size":
				if particles != null:
					var mesh := (particles.draw_pass_1 as QuadMesh).duplicate() as QuadMesh
					mesh.size *= value
					particles.draw_pass_1 = mesh
					print("  flash     : quad de chispa = %.4f m" % mesh.size.x)
			_:
				fail("--flash: clave desconocida '%s'" % key)


## Escala el emisivo de las fachadas en caliente. Devuelve los recursos a su valor
## original en [method _restore_emission_scale]: nunca se guarda nada.
func _apply_emission_scale() -> void:
	var raw := String(user_args().get("emission", ""))
	if raw.is_empty():
		return
	var factor := raw.to_float()
	for path: String in FACADE_MATERIALS:
		var material := ResourceLoader.load(path, "StandardMaterial3D") as StandardMaterial3D
		if material == null:
			continue
		_facade_materials.append(material)
		_emission_before[path] = material.emission_energy_multiplier
		material.emission_energy_multiplier *= factor
		print("  emisivo   : %s = %.3f" % [path.get_file(), material.emission_energy_multiplier])


func _restore_emission_scale() -> void:
	for material: StandardMaterial3D in _facade_materials:
		var path := material.resource_path
		if _emission_before.has(path):
			material.emission_energy_multiplier = _emission_before[path]
	_facade_materials.clear()


func _report_setup() -> void:
	var env := _environment()
	if env == null:
		fail("el nivel no trae WorldEnvironment con Environment")
		return
	print("  glow      : %s · intensidad %.2f · umbral %.2f · bloom %.2f · fuerza %.2f"
			% [_b(env.glow_enabled), env.glow_intensity, env.glow_hdr_threshold,
			env.glow_bloom, env.glow_strength])
	var flash := _muzzle_flash()
	if flash != null:
		var light := flash.get_node_or_null(^"FlashLight") as OmniLight3D
		var bloom := flash.get_node_or_null(^"Bloom") as MeshInstance3D
		if light != null:
			print("  fogonazo  : %.0f lm · alcance %.2f m · pico %.2f"
					% [light.light_intensity_lumens, light.omni_range, MuzzleFlash.PULSE_ENERGY])
		if bloom != null:
			var mesh := bloom.mesh as QuadMesh
			var standard := (bloom.material_override if bloom.material_override != null
					else bloom.get_active_material(0)) as StandardMaterial3D
			if mesh != null and standard != null:
				print("  quad      : %.3f m · albedo (%.2f, %.2f, %.2f)"
						% [mesh.size.x, standard.albedo_color.r,
						standard.albedo_color.g, standard.albedo_color.b])
	var material := ResourceLoader.load(FACADE_MATERIALS[0], "StandardMaterial3D") as StandardMaterial3D
	if material != null:
		print("  ventanas  : emission_energy_multiplier = %.3f"
				% material.emission_energy_multiplier)


# --- Encuadres ----------------------------------------------------------------------------------

## Jefe centrado a 40, 60 y 80 m, con y sin fogonazo.
func _shoot_boss() -> void:
	var boss := _boss_position()
	var away := _away_from_city(boss)
	for text: String in String(user_args().get("distances", "40,60,80")).split(",", false):
		var distance := text.to_float()
		var position := boss - away * distance + Vector3.UP * BOSS_SHOT_HEIGHT
		var target := boss + Vector3.UP * BOSS_LOOK_HEIGHT
		_park(position, target)
		await wait_frames(_settle_frames)
		_report_projection(target, "jefe")
		await _capture("boss%02d_off" % int(distance))
		await _capture_flash("boss%02d_on" % int(distance))


## Fachada encendida a 30 m, de frente: es el encuadre del criterio de halo.
func _shoot_windows() -> void:
	var building := _lit_building()
	if building == null:
		fail("no se encontró ningún edificio con ventanas encendidas")
		return
	var centre := building.global_position + Vector3.UP * (building.get_height() * 0.5)
	var grid := _level.get_city_grid()
	var crossing := _city_centre(grid)
	var normal := centre - crossing
	normal.y = 0.0
	normal = Vector3.BACK if normal.length() < 1.0 else normal.normalized()
	# `--win-distance` existe para el caso de contacto: el bot vuela a menos de 10 m
	# de una fachada y ahí la ventana no molesta por su halo sino por su núcleo.
	var distance := float(user_args().get("win-distance", WINDOW_DISTANCE))
	print("  ventanas  : '%s' a %.0f m, alto %.1f m, encendido %s"
			% [building.name, distance, building.get_height(),
			str(building.windows_lit())])
	_park(centre + normal * distance, centre)
	await wait_frames(_settle_frames)
	await _capture("win%02d_off" % int(distance))
	await _capture_flash("win%02d_on" % int(distance))


## Vuelo bajo entre manzanas, mirando al cruce de avenidas.
func _shoot_street() -> void:
	var grid := _level.get_city_grid()
	if grid == null:
		fail("el nivel no trae CityGrid")
		return
	var crossing := _city_centre(grid)
	var boss := _boss_position()
	var away := _away_from_city(boss)
	var position := crossing + away * STREET_BACK
	position.y = crossing.y + STREET_HEIGHT
	_park(position, crossing + Vector3.UP * STREET_HEIGHT)
	await wait_frames(_settle_frames)
	await _capture("street_off")
	await _capture_flash("street_on")


## Un haz de asedio en pantalla, del jefe a una azotea, visto desde 60 m.
func _shoot_beam() -> void:
	var boss := _boss_position()
	var away := _away_from_city(boss)
	var grid := _level.get_city_grid()
	var target := boss + away * -60.0 + Vector3.UP * 20.0
	var building := _lit_building()
	if building != null:
		target = building.global_position + Vector3.UP * building.get_height()
	var packed := load(SIEGE_BEAM_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % SIEGE_BEAM_SCENE)
		return
	var beam := packed.instantiate() as VFXBeam
	_level.add_child(beam)
	await wait_frames(2)
	beam.play()
	beam.set_endpoints(boss + Vector3.UP * 26.0, target)
	# El dron se pone de costado al haz para que el tubo cruce el cuadro entero.
	var side := Vector3(-away.z, 0.0, away.x)
	var position := boss - away * 40.0 + side * 55.0 + Vector3.UP * BOSS_SHOT_HEIGHT
	_park(position, boss + Vector3.UP * BOSS_LOOK_HEIGHT)
	await wait_frames(_settle_frames)
	if grid != null:
		print("  haz       : de %s a %s" % [_v(boss + Vector3.UP * 26.0), _v(target)])
	await _capture("beam_off")
	await _capture_flash("beam_on")
	beam.queue_free()
	await wait_frames(2)


# --- Utilidades de pose ---------------------------------------------------------------------------

## Congela el dron en [param position] mirando a [param target] y enfoca la FPV.
func _park(position: Vector3, target: Vector3) -> void:
	var rig := _level.drone_rig as DroneRig
	if rig == null:
		fail("el nivel no trae DroneRig")
		return
	var drone := rig.get_drone()
	if drone == null:
		fail("el DroneRig no trae Drone")
		return
	drone.force_disarm()
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	drone.freeze = true
	drone.global_position = position
	if position.distance_to(target) > 0.1:
		drone.look_at(target, Vector3.UP)
		# La cámara del dron mira **arriba** del morro (`QuadSettings.angle`, el
		# ángulo de la cámara de un FPV), así que un `look_at` deja el blanco por
		# debajo del retículo. Se compensa inclinando el dron el mismo ángulo: sin
		# esto, el jefe caía a 320 px del centro y la medida del centro del cuadro
		# no decía nada sobre si el fogonazo lo tapa.
		var rig_camera := rig.get_camera_rig() as CameraRig
		if rig_camera != null:
			drone.rotate_object_local(Vector3.RIGHT, -deg_to_rad(rig_camera.get_tilt_degrees()))
	var fpv := rig.get_fpv_camera()
	if fpv != null:
		var _discard := _level.focus_camera(fpv)


## Posición en el suelo del jefe.
func _boss_position() -> Vector3:
	var manager := _level.get_round_manager()
	if manager == null:
		return Vector3.ZERO
	var enemies := manager.get_enemies()
	if enemies.is_empty():
		return Vector3.ZERO
	var enemy := enemies[0] as Node3D
	return enemy.global_position if enemy != null else Vector3.ZERO


## Centro del barrio de [param grid], en coordenadas globales.
##
## `play_centre()` devuelve **local**: se transforma acá. La ronda 1 corre sobre
## el pueblo y lo trae; un barrio sin plano se cae a su propio origen, que para
## encuadrar un plano de legibilidad es de sobra.
func _city_centre(grid: CityGrid) -> Vector3:
	if grid == null or not is_instance_valid(grid):
		return Vector3.ZERO
	if grid.has_method(&"play_centre"):
		return grid.to_global(grid.call(&"play_centre") as Vector3)
	return grid.global_position


## Dirección horizontal **del jefe hacia la ciudad**. El dron se pone del lado
## opuesto para que el distrito entre en cuadro por detrás del jefe.
func _away_from_city(boss: Vector3) -> Vector3:
	var grid := _level.get_city_grid()
	var city := _city_centre(grid)
	var away := city - boss
	away.y = 0.0
	return Vector3.BACK if away.length() < 1.0 else away.normalized()


## Primer edificio con las ventanas encendidas, el más cercano al cruce.
func _lit_building() -> Building:
	var grid := _level.get_city_grid()
	if grid == null:
		return null
	var crossing := _city_centre(grid)
	var best: Building = null
	var best_distance := INF
	for building: Building in grid.get_buildings():
		if not building.windows_lit() or building.is_destroyed():
			continue
		var distance := building.global_position.distance_to(crossing)
		if distance > 20.0 and distance < best_distance:
			best_distance = distance
			best = building
	return best


## Imprime dónde cae [param world_point] en pantalla. Es lo que dice si el
## fogonazo tapa al jefe o solamente al cielo.
func _report_projection(world_point: Vector3, label: String) -> void:
	var rig := _level.drone_rig as DroneRig
	var fpv := rig.get_fpv_camera() if rig != null else null
	if fpv == null:
		return
	var screen := fpv.project_point(world_point)
	var size := Vector2(DisplayServer.window_get_size())
	print("  proyección: %s en (%.0f, %.0f) px · centro (%.0f, %.0f)"
			% [label, screen.x, screen.y, size.x * 0.5, size.y * 0.5])


func _environment() -> Environment:
	var world := _level.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	return world.environment if world != null else null


func _muzzle_flash() -> MuzzleFlash:
	var rig := _level.drone_rig as DroneRig
	var mount := rig.get_weapon_mount() if rig != null else null
	if mount == null:
		return null
	for child: Node in mount.find_children("*", "Node3D", true, false):
		var flash := child as MuzzleFlash
		if flash != null:
			return flash
	return null


# --- Capturas y métricas ---------------------------------------------------------------------

## Captura el cuadro tal como está y tabula sus estadísticas.
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		fail("no se pudo capturar '%s': el viewport no devolvió imagen" % file_name)
		return
	_emit(file_name, image)


## Enciende el fogonazo y guarda el **cuadro más brillante** del pulso.
##
## El pulso dura 0.06 s y la ventana corre sin vsync: con 200 fps el pico cae en el
## tercer cuadro y con 60 en el primero. En vez de adivinar el instante se capturan
## [constant FLASH_FRAMES] cuadros seguidos y se guarda el de mayor luminancia
## central, que es el peor caso que el jugador ve.
func _capture_flash(file_name: String) -> void:
	var flash := _muzzle_flash()
	if flash == null:
		fail("no hay MuzzleFlash que encender para '%s'" % file_name)
		return
	flash.flash()
	var best: Image = null
	var best_mean: float = -1.0
	var best_frame: int = -1
	for i: int in FLASH_FRAMES:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null:
			continue
		var mean := _central_mean(image)
		if mean > best_mean:
			best_mean = mean
			best = image
			best_frame = i
	flash.stop()
	if best == null:
		fail("no se pudo capturar '%s'" % file_name)
		return
	print("  pico      : cuadro %d de %d del pulso" % [best_frame + 1, FLASH_FRAMES])
	_emit(file_name, best)
	await wait_frames(4)


## Imprime la tabla y guarda el PNG.
func _emit(file_name: String, image: Image) -> void:
	_print_stats(file_name, image)
	if shots_dir.is_empty():
		return
	var name := file_name if _tag.is_empty() else "%s_%s" % [_tag, file_name]
	var path := "%s/%s.png" % [shots_dir, name]
	var err := image.save_png(path)
	if err != OK:
		fail("no se pudo guardar la captura '%s': %s" % [path, error_string(err)])
		return
	print("  captura   : %s" % path)


## Luminancia media de la región central, sin construir el histograma entero. La
## usa [method _capture_flash] para elegir el cuadro del pico.
func _central_mean(image: Image) -> float:
	var rect := _central_rect(image)
	var sum: float = 0.0
	var count: int = 0
	for y: int in range(rect.position.y, rect.end.y, 4):
		for x: int in range(rect.position.x, rect.end.x, 4):
			var c := image.get_pixel(x, y)
			sum += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			count += 1
	return sum / float(count) if count > 0 else 0.0


## Rectángulo centrado que cubre [constant CENTRAL_AREA] del área del cuadro.
func _central_rect(image: Image) -> Rect2i:
	var side := sqrt(CENTRAL_AREA)
	var width := int(image.get_width() * side)
	var height := int(image.get_height() * side)
	return Rect2i((image.get_width() - width) / 2, (image.get_height() - height) / 2,
			width, height)


## Dos filas por captura: cuadro entero y región central. La región central es la
## que manda: es donde está el retículo y donde el jugador busca al jefe.
func _print_stats(file_name: String, image: Image) -> void:
	var rect := _central_rect(image)
	print("  %s:" % file_name)
	_print_region("    cuadro ", image, Rect2i(0, 0, image.get_width(), image.get_height()))
	_print_region("    central", image, rect)


func _print_region(label: String, image: Image, rect: Rect2i) -> void:
	var step := 4
	var samples: PackedFloat32Array = PackedFloat32Array()
	var clipped: int = 0
	for y: int in range(rect.position.y, rect.end.y, step):
		for x: int in range(rect.position.x, rect.end.x, step):
			var c := image.get_pixel(x, y)
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			samples.append(l)
			if l > 0.98:
				clipped += 1
	if samples.is_empty():
		return
	samples.sort()
	var total := float(samples.size())
	var sum: float = 0.0
	for value: float in samples:
		sum += value
	print("%s: media %.4f · p50 %.4f · p90 %.4f · p99 %.4f · p999 %.4f · quemado %.2f%%"
			% [label, sum / total, samples[int(total * 0.5)], samples[int(total * 0.9)],
			samples[int(total * 0.99)], samples[mini(int(total * 0.999), samples.size() - 1)],
			100.0 * float(clipped) / total])


func _b(value: bool) -> String:
	return "on" if value else "off"


func _v(value: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [value.x, value.y, value.z]
