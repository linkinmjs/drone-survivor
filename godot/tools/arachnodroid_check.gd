## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-19: el Arachnodroid completo (`docs/07` §13).
##
## Levanta un mundo sintético —suelo llano, seis [Building] reales en la capa 8 y
## un dron de prueba en la capa 2 con casco y batería— e instancia al jefe desde
## `EnemyCatalog`. [b]Nunca[/b] abre una escena de juego real.
##
## | # | Criterio de `docs/07` §13 | Umbral |
## |---|---|---|
## | 1 | Construcción: tantas partes como declara `metadata.part_count` | igualdad de ids |
## | 2 | Daño: 12 al `hull` y 36 a una rodilla | 0.96 y 36.0 ± 0.01 |
## | 3 | Las 5 fases se alcanzan en orden, sin retrocesos | 5 `enemy_phase_changed` |
## | 4 | Desbloqueos por fase | `head_laser`/`emp_pulse` ≥ P2, `pounce` ≥ P3, `climb` fuera en P4 |
## | 5 | Exposición del núcleo | no con 2 rodillas; sí con 3 y el dron en el cono |
## | 6 | Exposición del visor | capa 4 sólo en `TELEGRAPH`/`ACTIVE` |
## | 7 | Telegrafía de los 8 ataques, en las 5 fases | ≥ 0.80 s y ≥ 2 canales (3 en `pounce`) |
## | 8 | Cooldowns en 600 decisiones simuladas | 0 repeticiones antes del enfriamiento |
## | 9 | `defeated` una sola vez, en dos corridas | exactamente 1 por corrida |
## | 10 | Las 4 patas perdidas dejan al jefe en `DOWNED` | `is_downed()`, velocidad 0, el cuerpo apoya, 3 núcleos expuestos |
## | 10b | Desplome antes de P5 | P5 automática con 90.0 s ± 0.1 y un solo `enemy_defeated` |
## | 11 | `on_destroy` de rodilla y de visor | fémur desprendido, ceguera 20 s, respaldo 45 s |
## | 12 | P5: temporizador y detonación | 45.0 ± 0.1 s, daño a ≤ 120 m, `enemy_defeated` |
## | 13 | Escombros con 4 patas, carcasa y 2 antenas | `get_live_count() <= 24` |
## | 14 | Rendimiento con el jefe caminando y 6 edificios | física < 2.0 ms/tick |
## | 15 | Haz visible de `head_laser` y `siege_beam` | encendido en `ACTIVE`, apagado fuera |
##
## La 15 no está en `docs/07` §13: la agrega el orquestador en el cierre de
## WP-19, porque los dos haces continuos hacían su daño sin nada en pantalla
## durante toda la ventana activa.
##
## Y además, porque son de WP-19 y no estaban en la tabla: que los ocho ataques
## hagan el daño que declara `docs/07` §5.1, que la carcasa se abra 70° en P4 y
## abra el cono del vientre a 55°, y que el `AudioRig` tenga el banco entero sin
## pasarse de ocho voces.
##
## [b]Pruebas negativas[/b] (tres): un `windup` de 0.30 s tiene que telegrafiar
## 0.80 s igual —en la API [b]y[/b] en el reloj de la máquina—; `defeated` no
## puede emitirse dos veces aunque se pida dos veces; y `detonate()` llamado dos
## veces no puede cobrar el daño dos veces.
##
## [b]El dron[/b] es un [RigidBody3D] sintético con un `Hull` y un `EnergySystem`
## por *duck typing*, no `drone_rig.tscn`: ese árbol arrastra el HUD, la radio y
## el respawn, y lo que se mide acá es el jefe. El contrato que el marco de
## ataques usa son `Hull.apply_damage` y `EnergySystem.apply_emp` (`docs/09`
## §2.7 y §2.9), y los dos están, así que el daño al casco y el drenaje del EMP
## quedan igual de verificables.
##
## Sale [b]0[/b] al pasar todo, [b]1[/b] con `FAIL: <criterio> esperado=<x>
## medido=<y>` y [b]2[/b] si falta un recurso. Restaura `Global.round_seed` y
## `Global.debug_freeze_ai` al salir.
extends CheckRunner

## Id del jefe en el catálogo.
const ENEMY_ID: StringName = &"arachnodroid"

## Sidecar del pipeline voxel, de donde sale `metadata.part_count` (`docs/05`).
const PARTS_JSON: String = "res://enemies/arachnodroid/arachnodroid.parts.json"

## Perfil de edificio del que salen los seis de prueba (`docs/10` §4.2).
const BUILDING_PROFILE: String = "res://city/profiles/low_block.tres"

## Carpeta del banco de sonido del jefe (`docs/07` §10).
const AUDIO_DIR: String = "res://assets/audio/enemies"

## Código de salida cuando falta un recurso (`docs/07` §13).
const EXIT_MISSING_RESOURCE: int = 2

## Aceleración de la simulación para las esperas largas: los 45 s de la ceguera
## y los 45 s de la cuenta atrás.
const TIME_SCALE: float = 8.0

## Aceleración durante la batería de ataques. Más fina a propósito: con
## `time_scale` 8 el tick de física dura 0.08 s simulados y una ventana activa de
## 0.25 s —la del pisotón— cabría en tres consultas. A 2× el tick vale 0.02 s y
## las coreografías se resuelven con el grano con el que se van a jugar.
const ATTACK_TIME_SCALE: float = 2.0

## Semilla con la que corre el check.
const SEED: int = 19

## Suelo del mundo sintético.
const GROUND_SIZE: Vector3 = Vector3(1600.0, 8.0, 1600.0)

## Huella y altura de los edificios de prueba, en metros.
const BUILDING_SIZE: Vector3 = Vector3(18.0, 26.0, 18.0)

## HP de los edificios de prueba. Alto a propósito: el rig les cobra
## `crush_damage` 900 por apoyo al trepar y el asedio 2 800 por ráfaga; con
## 1 200 HP se derrumbarían a mitad de la medición y el objetivo cambiaría solo.
const BUILDING_HP: float = 400000.0

## Los seis edificios: nombre, posición en XZ y `value` (`docs/10` §4.2).
const BUILDINGS: Array[Dictionary] = [
	{"name": "Block_A", "at": Vector2(70.0, 60.0), "value": 100},
	{"name": "Block_B", "at": Vector2(-95.0, 45.0), "value": 120},
	{"name": "Block_C", "at": Vector2(100.0, -55.0), "value": 150},
	{"name": "Block_D", "at": Vector2(-55.0, 105.0), "value": 200},
	{"name": "Block_E", "at": Vector2(60.0, 110.0), "value": 250},
	{"name": "Tower_F", "at": Vector2(-40.0, -95.0), "value": 300},
]

## Ids de los cuatro puntos débiles de rodilla, en el orden en que se rompen.
const KNEES: Array[StringName] = [
	&"wp_leg_fl_knee", &"wp_leg_fr_knee", &"wp_leg_bl_knee", &"wp_leg_br_knee",
]

## Ids de los tres núcleos ventrales.
const CORES: Array[StringName] = [&"wp_core_a", &"wp_core_b", &"wp_core_c"]

## Los ocho ataques de `docs/07` §5, en el orden del documento.
const ATTACK_IDS: Array[StringName] = [
	&"climb", &"stomp", &"leg_sweep", &"head_laser", &"siege_beam", &"emp_pulse",
	&"pounce", &"shake_off",
]

## Ataques con haz continuo visible durante la ventana activa.
const BEAM_ATTACKS: PackedStringArray = ["head_laser", "siege_beam"]

## Ids de fase esperados, en orden (`docs/07` §6).
const PHASE_IDS: Array[StringName] = [
	&"p1_siege", &"p2_alert", &"p3_fury", &"p4_belly", &"p5_selfdestruct",
]

## Daño del arma en un disparo y multiplicador de punto débil (`docs/08`).
const SHOT_DAMAGE: float = 12.0
const WEAK_MULTIPLIER: float = 3.0

## Decisiones simuladas de la prueba de enfriamientos (`docs/07` §13 #8).
const DECISIONS: int = 600

## Paso simulado entre dos decisiones, en segundos (4 Hz).
const DECISION_STEP: float = 0.25

## Ventana de medición del coste de física, en ticks.
const PERF_TICKS: int = 160

## Ticks de calentamiento antes de medir el coste.
const PERF_WARMUP: int = 60

## Presupuesto de física con el jefe caminando, en ms/tick (`docs/07` §13 #14).
const PERF_BUDGET_MS: float = 2.0

## Tope de escombros vivos del pool (`docs/10` §6).
const DEBRIS_LIMIT: int = 24

## Voces simultáneas del jefe (`docs/07` §10).
const VOICE_BUDGET: int = 8

## Duración nominal de la cuenta atrás y su tolerancia, en segundos.
const SELFDESTRUCT_SECONDS: float = 45.0
const SELFDESTRUCT_TOLERANCE: float = 0.1

## Radio de la detonación, en metros.
const DETONATION_RADIUS: float = 120.0

## `windup` de la primera prueba negativa, en segundos.
const NEGATIVE_WINDUP: float = 0.30

## Segundos que se le dan a una acción conducida a mano antes de darla por
## colgada.
const ACTION_BUDGET: float = 14.0

## Cara superior del suelo sintético, en metros. La caja mide `GROUND_SIZE.y` y
## está centrada en `-GROUND_SIZE.y / 2`, así que su techo queda en 0.
const GROUND_TOP: float = 0.0

## Cuánto puede hundirse el origen del cuerpo caído por debajo del suelo, en
## metros (`downed_body_height` es -6.0, con medio metro de margen).
const DOWNED_MIN_ORIGIN: float = 6.5

## Semiapertura del cono del vientre antes y después de abrir la carcasa.
const CONE_CLOSED: float = 35.0
const CONE_OPEN: float = 55.0


## Dron de prueba: un [RigidBody3D] de la capa 2 con casco y batería por *duck
## typing*, que es todo el contrato que el marco de ataques usa (`docs/09` §2).
class DroneStub extends RigidBody3D:
	## Casco: el contrato mínimo de `Hull` de `docs/09` §2.7.
	class HullStub extends Node:
		var hp: float = 100.0
		var hits: int = 0
		var last_amount: float = 0.0
		var last_source: Vector3 = Vector3.ZERO

		## Nombre canónico de `docs/09` §2: todo daño que no sea un choque entra
		## por acá, y es quien publica `Events.drone_damaged`.
		func apply_damage(amount: float, source_position: Vector3) -> void:
			hits += 1
			last_amount = amount
			last_source = source_position
			hp = maxf(hp - amount, 0.0)
			Events.drone_damaged.emit(amount, source_position)

	## Batería: el contrato mínimo de `EnergySystem` de `docs/09` §2.9.
	class EnergyStub extends Node:
		signal emp_hit(glitch_seconds: float)

		var energy: float = 100.0
		var maximum: float = 100.0
		var emp_count: int = 0
		var last_glitch: float = 0.0

		func get_max_energy() -> float:
			return maximum

		func drain(amount: float) -> void:
			energy = maxf(energy - amount, 0.0)

		func apply_emp(amount: float, glitch_seconds: float) -> void:
			drain(amount)
			emp_count += 1
			last_glitch = glitch_seconds
			emp_hit.emit(glitch_seconds)

	var anchor: Vector3 = Vector3.ZERO
	var parked: bool = true
	var hull: HullStub = null
	var energy: EnergyStub = null

	func _ready() -> void:
		collision_layer = PhysicsLayers.DRONE
		# Máscara 0: nada empuja al dron de prueba. Las consultas de ataque lo
		# encuentran por su **capa**, que es lo que importa acá.
		collision_mask = 0
		gravity_scale = 0.0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 0.4, 1.2)
		shape.shape = box
		add_child(shape)
		hull = HullStub.new()
		hull.name = "Hull"
		add_child(hull)
		energy = EnergyStub.new()
		energy.name = "EnergySystem"
		add_child(energy)

	func _physics_process(_delta: float) -> void:
		if not parked:
			return
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		global_position = anchor

	## Deja el dron quieto en [param point].
	func park(point: Vector3) -> void:
		parked = true
		anchor = point
		global_position = point

	## Lo suelta para que un impulso se note en su velocidad.
	func release() -> void:
		parked = false

	## Devuelve casco y batería a pleno.
	func restore() -> void:
		hull.hp = 100.0
		hull.hits = 0
		energy.energy = energy.maximum
		energy.emp_count = 0


var _enemy: Arachnodroid = null
var _perception: Perception = null
var _brain: EnemyFSM = null
var _library: AttackLibrary = null
var _telegraph: Telegraph = null
var _audio: AudioRig = null
var _rig: ProceduralLegRig = null
var _drone: DroneStub = null
var _world: Node3D = null
var _pool: DebrisPool = null
var _buildings: Array[Building] = []
var _tower: Building = null

var _seed_before: int = 0
var _freeze_before: bool = false
var _phase_log: Array[StringName] = []
var _defeats: int = 0
var _telegraph_events: Array[Dictionary] = []
var _summary: PackedStringArray = PackedStringArray()
var _sim_time: float = 0.0
var _started_usec: int = 0
var _selfdestruct_announced: float = -1.0


func _run() -> void:
	_started_usec = Time.get_ticks_usec()
	_seed_before = Global.round_seed
	_freeze_before = Global.debug_freeze_ai
	Global.debug_freeze_ai = false
	Global.round_seed = SEED

	if not _verify_resources():
		_restore()
		get_tree().quit(EXIT_MISSING_RESOURCE)
		return

	_build_world()
	await wait_physics(2)
	if not await _spawn_enemy():
		_restore()
		return
	if not _check_wiring():
		_restore()
		return

	await _check_construction()          # 1
	_check_damage_model()                # 2
	await _check_performance()           # 14
	await _check_visor_exposure()        # 6
	await _check_attacks()               # 7 + daño de los ocho ataques
	_check_windup_matrix()               # 7 (las 5 fases, analítico)
	_check_cooldowns()                   # 8
	await _check_phases()                # 3, 4, 5, 11, carcasa y cono
	await _check_downed()                # 10
	# La derrota por núcleos va **antes** que los escombros: romper la carcasa
	# desprende el vientre y con él los tres núcleos, que dejan de contar.
	await _check_defeat_by_cores()       # 9 (primera corrida)
	await _check_debris()                # 13
	await _check_audio()                 # `docs/07` §10
	await _check_downed_selfdestruct()   # 10b (corrida propia)
	await _check_selfdestruct()          # 12 + 9 (tercera corrida)
	await _check_negatives()             # pruebas negativas

	Engine.time_scale = 1.0
	_print_summary()
	_restore()


# --------------------------------------------------------------------------
# Recursos y mundo
# --------------------------------------------------------------------------

## Comprueba que está todo lo que el check necesita. Sin alguno, sale con 2.
func _verify_resources() -> bool:
	var missing := PackedStringArray()
	if not EnemyCatalog.has_id(ENEMY_ID):
		missing.append("EnemyCatalog['%s']" % ENEMY_ID)
	for path: String in [PARTS_JSON, BUILDING_PROFILE,
			String(EnemyCatalog.entry(ENEMY_ID).get("scene", "")),
			String(EnemyCatalog.entry(ENEMY_ID).get("profile", ""))]:
		if path.is_empty() or not ResourceLoader.exists(path):
			if not FileAccess.file_exists(path):
				missing.append(path)
	for attack_id: StringName in ATTACK_IDS:
		var path := "res://enemies/arachnodroid/attacks/%s.tres" % attack_id
		if not ResourceLoader.exists(path):
			missing.append(path)
	if missing.is_empty():
		return true
	for path: String in missing:
		print("  FALTA: %s" % path)
	print("CHECK %s: RECURSO AUSENTE (%d)" % [check_name, missing.size()])
	return false


## Suelo llano, seis edificios de distinto valor y el dron de prueba.
func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_pool = get_node_or_null(^"DebrisPool") as DebrisPool
	var _ground := _add_box("Ground", GROUND_SIZE, Vector3(0.0, -GROUND_SIZE.y * 0.5, 0.0),
			PhysicsLayers.WORLD)

	var source := ResourceLoader.load(BUILDING_PROFILE, "Resource") as BuildingProfile
	for entry: Dictionary in BUILDINGS:
		var spot := entry["at"] as Vector2
		var building := _make_building(String(entry["name"]), source,
				Vector3(spot.x, 0.0, spot.y), int(entry["value"]))
		_buildings.append(building)
		if _tower == null or building.value > _tower.value:
			_tower = building

	_drone = DroneStub.new()
	_drone.name = "DroneStub"
	_world.add_child(_drone)
	_drone.park(Vector3(40.0, 6.0, 0.0))


## Un [Building] mínimo pero completo: perfil propio, malla de etapa intacta y
## caja de colisión en la capa 8. No se instancia una pieza de `city/pieces/`
## porque el pack sólo trae la malla importada: el `Building` lo arma [CityGrid]
## en runtime (`docs/10` §4), y acá se hace lo mismo con una caja.
func _make_building(node_name: String, source: BuildingProfile, at: Vector3,
		value: int) -> Building:
	var profile := source.duplicate() as BuildingProfile
	profile.value = value
	profile.max_hp = BUILDING_HP
	# Sin escombros de ciudad: el tope del pool que mide el criterio 13 es el de
	# las piezas del jefe, y `city_check` ya cubre los derrumbes.
	profile.debris_count_min = 0
	profile.debris_count_max = 0

	var building := Building.new()
	building.name = node_name
	building.collision_layer = PhysicsLayers.CITY
	building.collision_mask = 0
	building.profile = profile
	building.base_size = BUILDING_SIZE
	building.position = at

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = BUILDING_SIZE
	mesh.mesh = box_mesh
	mesh.position = Vector3(0.0, BUILDING_SIZE.y * 0.5, 0.0)
	building.add_child(mesh)
	building.stage_intact = mesh
	building.intact_rest_transform = mesh.transform

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = BUILDING_SIZE
	shape.shape = box
	building.add_child(shape)
	building.intact_shape = shape

	_world.add_child(building)
	return building


## Un [StaticBody3D] con una caja, en la capa [param layer].
func _add_box(node_name: String, size: Vector3, origin: Vector3,
		layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = origin
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	return body


## Instancia el jefe desde el catálogo, con el cerebro apagado.
func _spawn_enemy() -> bool:
	var scene := EnemyCatalog.scene_of(ENEMY_ID)
	if scene == null:
		fail("EnemyCatalog no devolvió la escena de '%s'" % ENEMY_ID)
		return false
	_enemy = scene.instantiate() as Arachnodroid
	if _enemy == null:
		fail("la escena del jefe no es un Arachnodroid")
		return false
	_enemy.debris_pool = _pool
	_enemy.rubble_field = _pool.rubble_field if _pool != null else null
	add_child(_enemy)
	_enemy.global_position = Vector3.ZERO
	_connect(Events.enemy_phase_changed, _on_phase_changed)
	_connect(Events.enemy_defeated, _on_defeated)
	_connect(Events.enemy_attack_telegraphed, _on_telegraphed)
	# La cuenta atrás anuncia su duración nominal al arrancar: es el único
	# instante en el que 45.0 s son exactamente 45.0 s, porque
	# `selfdestruct_remaining()` ya descontó los ticks que tarda el check en
	# mirarlo.
	_selfdestruct_announced = -1.0
	var _started := _enemy.selfdestruct_started.connect(_on_selfdestruct_started)
	await wait_physics(6)
	return true


## Conecta [param target] a [param source] una sola vez. El bus vive más que el
## jefe, y esta escena instancia dos.
func _connect(source: Signal, target: Callable) -> void:
	if not source.is_connected(target):
		var _discard := source.connect(target)


## Comprueba que los nodos de WP-19 son los de verdad.
func _check_wiring() -> bool:
	_perception = _enemy.perception as Perception
	_brain = _enemy.brain as EnemyFSM
	_rig = _enemy.locomotion as ProceduralLegRig
	_library = _enemy.get_node_or_null(^"AttackLibrary") as AttackLibrary
	_telegraph = _enemy.get_node_or_null(^"Telegraph") as Telegraph
	_audio = _enemy.get_node_or_null(^"AudioRig") as AudioRig
	for pair: Array in [[_perception, "Perception"], [_brain, "Brain"],
			[_rig, "Locomotion"], [_library, "AttackLibrary"],
			[_telegraph, "Telegraph"], [_audio, "AudioRig"]]:
		if pair[0] == null:
			fail("el nodo %s no es del tipo esperado" % pair[1])
	if _perception == null or _brain == null or _rig == null or _library == null \
			or _telegraph == null or _audio == null:
		return false

	_brain.autonomous = false
	_perception.set_target(_drone)
	for attack_id: StringName in ATTACK_IDS:
		var action := _library.find(attack_id)
		expect(action != null, "falta la acción '%s' en AttackLibrary" % attack_id)
		if action == null:
			continue
		expect(action.profile != null, "la acción '%s' no tiene AttackProfile" % attack_id)
		if action.profile != null:
			expect(action.profile.telegraph != null,
					"'%s' no declara TelegraphProfile" % attack_id)
	expect(_library.find(&"approach") != null,
			"falta la acción de locomoción 'approach' (la fila `walk` de docs/07 §7)")
	expect(_library.find(&"test_stomp") == null,
			"la acción provisional 'test_stomp' sigue en AttackLibrary")
	# Los fallos de arriba son de configuración, no de cableado: el check puede
	# seguir y reportarlos todos de una pasada.
	return true


# --------------------------------------------------------------------------
# 1 · Construcción
# --------------------------------------------------------------------------

func _check_construction() -> void:
	var declared := _declared_part_count()
	var built := _enemy.get_parts().size()
	expect(built == declared,
			"construcción: esperado=%d partes (metadata.part_count) medido=%d"
			% [declared, built])
	expect(_enemy.get_weak_points().size() == 8,
			"puntos débiles: esperado=8 medido=%d" % _enemy.get_weak_points().size())
	for weak_id: StringName in KNEES + CORES + [&"wp_head_visor"]:
		expect(_enemy.get_weak_point(weak_id) != null,
				"falta el punto débil '%s'" % weak_id)
	expect(_enemy.get_legs().size() == 4,
			"patas agrupadas: esperado=4 medido=%d" % _enemy.get_legs().size())
	_summary.append("construcción: %d partes, %d puntos débiles, %d patas"
			% [built, _enemy.get_weak_points().size(), _enemy.get_legs().size()])
	await wait_physics(1)


## `metadata.part_count` del sidecar del pipeline voxel (`docs/05`). **Ningún
## check codifica el 31 a mano.**
func _declared_part_count() -> int:
	var text := FileAccess.get_file_as_string(PARTS_JSON)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		fail("no se pudo leer %s" % PARTS_JSON)
		return -1
	var data := parsed as Dictionary
	var metadata := data.get("metadata", {}) as Dictionary
	if not metadata.has("part_count"):
		fail("%s no declara metadata.part_count" % PARTS_JSON)
		return -1
	return int(metadata["part_count"])


# --------------------------------------------------------------------------
# 2 · Blindaje y multiplicador
# --------------------------------------------------------------------------

func _check_damage_model() -> void:
	var hull := _enemy.get_part(&"hull")
	var knee := _enemy.get_part(KNEES[0])
	if hull == null or knee == null:
		fail("faltan 'hull' o '%s' para medir el daño" % KNEES[0])
		return

	var hull_before := hull.hp
	var _hull_damage := hull.take_damage(SHOT_DAMAGE, _hit(hull.world_position(), false, &""))
	var hull_lost := hull_before - hull.hp
	expect_near(hull_lost, SHOT_DAMAGE * (1.0 - hull.armor), 0.01,
			"daño al hull con armor %.2f" % hull.armor)

	var knee_before := knee.hp
	# El arma ya aplicó el ×3.0 del punto débil (`docs/08` §2.7); `EnemyPart` no
	# lo vuelve a aplicar, sólo descuenta el blindaje, que en la rodilla es 0.
	var _knee_damage := knee.take_damage(SHOT_DAMAGE * WEAK_MULTIPLIER,
			_hit(knee.world_position(), true, KNEES[0]))
	var knee_lost := knee_before - knee.hp
	expect_near(knee_lost, SHOT_DAMAGE * WEAK_MULTIPLIER, 0.01,
			"daño a la rodilla con armor %.2f" % knee.armor)

	hull.hp = hull.max_hp
	knee.hp = knee.max_hp
	_summary.append("daño: hull %.2f (esperado %.2f) · rodilla %.2f (esperado %.2f)"
			% [hull_lost, SHOT_DAMAGE * (1.0 - hull.armor), knee_lost,
			SHOT_DAMAGE * WEAK_MULTIPLIER])


## Un `hit` del contrato de `docs/06` §14.1.
func _hit(position: Vector3, weak: bool, weak_id: StringName) -> Dictionary:
	return {
		"position": position,
		"normal": Vector3.UP,
		"direction": Vector3.FORWARD,
		"source": self,
		"is_weak_point": weak,
		"weak_point_id": weak_id,
		"damage_type": &"kinetic",
	}


# --------------------------------------------------------------------------
# 14 · Rendimiento
# --------------------------------------------------------------------------

## Física < 2.0 ms/tick con el jefe caminando y seis edificios.
##
## Se mide a `time_scale` 1.0 a propósito: `Performance.TIME_PHYSICS_PROCESS`
## reporta lo que costó el paso de física del último frame, y con la simulación
## acelerada ese frame lleva varios pasos dentro. El presupuesto de `docs/07`
## §13 es por tick, no por frame.
func _check_performance() -> void:
	Engine.time_scale = 1.0
	_brain.autonomous = false
	_brain.set_action_state(EnemyFSM.ACTION_NONE)
	# Campo abierto y marcha conducida a mano. Lo segundo es deliberado: con el
	# selector suelto, la ventana de medición se la llevaría un asedio o una
	# trepada y el número dejaría de ser «el jefe caminando». El punto de partida
	# está elegido para que en los 1.6 s de ventana no llegue a ninguna fachada.
	_enemy.global_position = Vector3.ZERO
	_rig.release_all_legs()
	_rig.clear_crouch()
	_rig.snap_to_ground()
	_drone.park(Vector3(300.0, 30.0, 300.0))
	var heading := Vector3(1.0, 0.0, 0.0)
	var speed := _enemy.profile.walk_speed
	# El calentamiento **también camina**: así las pisadas, el polvo y los rayos
	# de apoyo pagan su primera vez fuera de la ventana de medición.
	for _warm: int in PERF_WARMUP:
		await get_tree().physics_frame
		_enemy.move_body(get_physics_process_delta_time(), heading * speed)

	_rig.reset_metrics()
	var samples := PackedFloat32Array()
	for _sample: int in PERF_TICKS:
		await get_tree().physics_frame
		_enemy.move_body(get_physics_process_delta_time(), heading * speed)
		samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var rig_usec := _rig.average_tick_usec()

	# Línea base: el mismo mundo con el jefe quieto.
	var idle_samples := PackedFloat32Array()
	for _sample: int in PERF_TICKS:
		await get_tree().physics_frame
		idle_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	await _settle()

	# Se mide la **mediana**, no la media. El presupuesto de `docs/07` §13 es el
	# coste de un tick de física en régimen, y la media la arruina un solo
	# tirón: en una corrida de 160 ticks basta que el cargador de recursos, el
	# recolector o el sistema operativo se lleven un frame para que 1.5 ms se
	# conviertan en 80. El pico se imprime al lado, que es donde ese tirón se ve.
	var median := _median(samples)
	expect(median < PERF_BUDGET_MS,
			"rendimiento: esperado=<%.2f ms/tick medido=%.3f ms/tick"
			% [PERF_BUDGET_MS, median])
	_summary.append("física: %.3f ms/tick caminando (media %.3f · pico %.3f · quieto %.3f · rig %.0f µs) con 6 edificios"
			% [median, _mean(samples), _peak(samples), _median(idle_samples), rig_usec])


## Mediana de [param values].
func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


## Media de [param values].
func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


## Máximo de [param values].
func _peak(values: PackedFloat32Array) -> float:
	var best := 0.0
	for value: float in values:
		best = maxf(best, value)
	return best


# --------------------------------------------------------------------------
# 6 · Exposición del visor
# --------------------------------------------------------------------------

## Capa 4 sólo mientras la capa de acción está en `TELEGRAPH` o `ACTIVE`.
func _check_visor_exposure() -> void:
	var visor := _enemy.get_weak_point(&"wp_head_visor")
	if visor == null:
		fail("no existe el punto débil 'wp_head_visor'")
		return
	var body := visor.collider()
	if body == null:
		fail("'wp_head_visor' no tiene colisionador")
		return

	# Con la IA congelada la capa de acción se queda donde la dejen: un estado
	# forzado sin acción asociada tiene duración 0 y el [EnemyFSM] lo encadenaría
	# hasta `NONE` en el tick siguiente (`docs/11` §11).
	Global.debug_freeze_ai = true
	_enemy.set_action_state(&"NONE")
	await wait_physics(2)
	expect(body.collision_layer == PhysicsLayers.ENEMY_BODY,
			"visor en NONE: esperado=capa 3 (%d) medido=%d"
			% [PhysicsLayers.ENEMY_BODY, body.collision_layer])

	for state: StringName in [&"TELEGRAPH", &"ACTIVE"]:
		_enemy.set_action_state(state)
		await wait_physics(2)
		expect(body.collision_layer == PhysicsLayers.ENEMY_WEAK,
				"visor en %s: esperado=capa 4 (%d) medido=%d"
				% [state, PhysicsLayers.ENEMY_WEAK, body.collision_layer])
		expect(visor.is_exposed(), "el visor no quedó expuesto en %s" % state)

	_enemy.set_action_state(&"RECOVER")
	await wait_physics(2)
	expect(body.collision_layer == PhysicsLayers.ENEMY_BODY,
			"visor en RECOVER: esperado=capa 3 (%d) medido=%d"
			% [PhysicsLayers.ENEMY_BODY, body.collision_layer])
	_enemy.set_action_state(&"NONE")
	await wait_physics(2)
	Global.debug_freeze_ai = false
	await wait_physics(2)
	_summary.append("visor: capa 4 sólo en TELEGRAPH y ACTIVE")


# --------------------------------------------------------------------------
# 7 · Telegrafía y daño de los ocho ataques
# --------------------------------------------------------------------------

## Conduce cada ataque a mano y mide su aviso y su efecto.
func _check_attacks() -> void:
	# Las acciones se conducen a mano por la capa de acción, así que el guion de
	# fases —que sólo filtra lo que puede *elegir* el selector— no las estorba.
	Engine.time_scale = ATTACK_TIME_SCALE
	for attack_id: StringName in ATTACK_IDS:
		await _check_attack(attack_id)
	await _settle()
	Engine.time_scale = TIME_SCALE


## Un ataque: telegrafía ≥ 0.80 s con sus canales, y el efecto de `docs/07` §5.1.
func _check_attack(attack_id: StringName) -> void:
	var action := _library.find(attack_id)
	if action == null:
		return
	_reset_stage(attack_id)
	await _wait_calm()

	_telegraph_events.clear()
	_drone.restore()
	var hull_before := _drone.hull.hp
	var energy_before := _drone.energy.energy
	var city_before := _city_hp()
	var channels := 0

	if not _fire(action):
		fail("no se pudo lanzar '%s' a mano" % attack_id)
		return
	# Los canales se cuentan dentro del aviso: al salir de `TELEGRAPH` se apagan.
	var sweep := action as SweepAction
	var beam_in_active := false
	var beam_outside := false
	var elapsed := 0.0
	var window := -1.0
	# Un solo bucle, y el estado se relee **después** de cada `await`: con dos
	# bucles encadenados, el último muestreo del de telegrafía cae cuando la
	# máquina ya pasó a `ACTIVE` —la condición del `while` no se reevalúa hasta
	# la vuelta siguiente— y el haz recién encendido se contaba como «visible
	# fuera de ACTIVE».
	while _brain.action_state() != EnemyFSM.ACTION_NONE and elapsed < ACTION_BUDGET:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var state := _brain.action_state()
		if state == EnemyFSM.ACTION_TELEGRAPH:
			channels = maxi(channels, _telegraph.active_channels())
		elif window < 0.0:
			window = elapsed
		if state == EnemyFSM.ACTION_ACTIVE:
			beam_in_active = beam_in_active or _beam_visible(sweep)
		else:
			beam_outside = beam_outside or _beam_visible(sweep)
	if window < 0.0:
		window = elapsed
	# El ciclo lo cerró el propio [EnemyFSM] al volver a `NONE`, y con él el
	# `finish()` de la acción y su enfriamiento.
	await wait_physics(2)

	# Aviso publicado por el bus, con su duración.
	var announced := -1.0
	for event: Dictionary in _telegraph_events:
		if StringName(event["attack_id"]) == attack_id:
			announced = float(event["duration"])
	expect(announced >= EnemyAction.MIN_WINDUP,
			"telegrafía de '%s': esperado=>=%.2f s medido=%.3f s"
			% [attack_id, EnemyAction.MIN_WINDUP, announced])
	expect(window >= EnemyAction.MIN_WINDUP - 0.02,
			"ventana TELEGRAPH de '%s': esperado=>=%.2f s medido=%.3f s"
			% [attack_id, EnemyAction.MIN_WINDUP, window])
	var needed := 3 if action.profile.damage_drone >= 100.0 else 2
	expect(channels >= needed,
			"canales de '%s': esperado=>=%d medido=%d" % [attack_id, needed, channels])

	_check_attack_effect(attack_id, action, hull_before, energy_before, city_before)
	_check_beam(attack_id, sweep, beam_in_active, beam_outside)
	_summary.append("%s: aviso %.2f s anunciado / %.2f s medidos · %d canales%s"
			% [attack_id, announced, window, channels,
			" · haz visible en ACTIVE" if BEAM_ATTACKS.has(String(attack_id)) else ""])


## El efecto concreto de cada ataque (`docs/07` §5.1).
func _check_attack_effect(attack_id: StringName, action: EnemyAction,
		hull_before: float, energy_before: float, city_before: float) -> void:
	var hull_lost := hull_before - _drone.hull.hp
	var city_lost := city_before - _city_hp()
	match attack_id:
		&"stomp", &"leg_sweep", &"shake_off":
			expect(hull_lost > 0.0,
					"'%s': esperado=daño al casco medido=%.1f" % [attack_id, hull_lost])
			expect_near(hull_lost, action.profile.damage_drone, 0.01,
					"daño al casco de '%s'" % attack_id)
		&"pounce":
			expect((action as ActionPounce).impacted(),
					"'pounce' no llegó a resolver su onda de aterrizaje")
			expect(hull_lost > 0.0,
					"'pounce': esperado=daño al casco medido=%.1f" % hull_lost)
		&"head_laser":
			expect(hull_lost > 0.0,
					"'head_laser': esperado=daño continuo al casco medido=%.1f" % hull_lost)
		&"emp_pulse":
			var drained := energy_before - _drone.energy.energy
			expect_near(drained, 25.0, 0.01, "drenaje del EMP sobre 100 de batería")
			expect(_drone.energy.emp_count == 1,
					"emp_hit: esperado=1 medido=%d" % _drone.energy.emp_count)
			expect_near(_drone.energy.last_glitch, 3.0, 0.01, "glitch del EMP")
			expect(is_equal_approx(_drone.hull.hp, 100.0),
					"el EMP dañó el casco: esperado=100.0 medido=%.1f" % _drone.hull.hp)
		&"siege_beam":
			expect(city_lost > 0.0,
					"'siege_beam': esperado=daño a la ciudad medido=%.1f" % city_lost)
		&"climb":
			# El daño propio de la trepada, no el `crush_damage` que el rig cobra
			# por pisar (`docs/06` §8.4): son dos cosas distintas.
			var climb_action := action as ActionClimb
			expect(climb_action != null and climb_action.supports() > 0,
					"'climb': esperado=>=1 apoyo sobre el edificio medido=%d"
					% (climb_action.supports() if climb_action != null else -1))
			expect(climb_action != null and climb_action.climb_damage() > 0.0,
					"'climb': esperado=daño propio a la ciudad medido=%.1f"
					% (climb_action.climb_damage() if climb_action != null else -1.0))


## 15 · El haz de los ataques continuos se enciende en `ACTIVE` y se apaga fuera.
func _check_beam(attack_id: StringName, sweep: SweepAction, in_active: bool,
		outside: bool) -> void:
	if not BEAM_ATTACKS.has(String(attack_id)):
		# El resto de los ataques no tiene haz; si alguno lo encendiera, sería un
		# nodo colgando del jefe para siempre.
		expect(sweep == null or sweep.beam_node() == null,
				"'%s' creó un haz y no debería tener ninguno" % attack_id)
		return
	expect(sweep != null and sweep.beam_node() != null,
			"'%s': esperado=nodo de haz medido=ninguno" % attack_id)
	expect(in_active, "haz de '%s': esperado=visible durante ACTIVE medido=apagado"
			% attack_id)
	expect(not outside,
			"haz de '%s': esperado=apagado fuera de ACTIVE medido=encendido" % attack_id)
	if sweep != null and sweep.beam_node() != null:
		expect(not sweep.beam_node().visible,
				"haz de '%s': esperado=apagado al terminar el ciclo medido=encendido"
				% attack_id)


## `true` si la acción tiene un haz y está encendido ahora mismo.
func _beam_visible(sweep: SweepAction) -> bool:
	if sweep == null:
		return false
	var beam := sweep.beam_node()
	return beam != null and is_instance_valid(beam) and beam.visible


## Coloca al jefe y al dron donde el ataque tiene sentido.
func _reset_stage(attack_id: StringName) -> void:
	_enemy.global_position = Vector3.ZERO
	_enemy.rotation = Vector3.ZERO
	_rig.release_all_legs()
	_rig.clear_crouch()
	_rig.snap_to_ground()
	match attack_id:
		&"climb", &"siege_beam":
			# Los dos apuntan a la ciudad. Trepar exige estar [b]pegado[/b]: con
			# la torre de 18 m de lado, a 11 m del centro los reposos de las
			# patas delanteras ya caen dentro de la huella y su rayo de apoyo
			# encuentra el techo. El asedio dispara de lejos, así que le sobra
			# con plantarse a 34 m.
			var standoff := 18.0 if attack_id == &"climb" else 34.0
			_enemy.global_position = _tower.global_position + Vector3(standoff, 0.0, 0.0)
			_enemy.look_at_from_position(_enemy.global_position,
					_tower.global_position, Vector3.UP)
			_rig.snap_to_ground()
			_drone.park(_enemy.global_position + Vector3(0.0, 40.0, 0.0))
		&"head_laser":
			_drone.park(Vector3(45.0, 18.0, 0.0))
		&"pounce":
			_drone.park(Vector3(30.0, 2.0, 0.0))
		&"emp_pulse":
			_drone.park(Vector3(20.0, 6.0, 0.0))
		&"shake_off":
			# El acampador vive pegado a una rodilla, a media altura del cuerpo:
			# es a quien castiga este ataque (`docs/07` §5.10).
			_drone.park(Vector3(9.0, 10.0, 0.0))
		_:
			_drone.park(Vector3(9.0, 2.0, 0.0))
	if attack_id != &"climb" and attack_id != &"siege_beam":
		# El jefe encara al dron antes de empezar: en juego lo hace caminando o
		# girando, y acá la medición no puede depender de hacia dónde quedó
		# mirando el ataque anterior.
		_enemy.look_at_from_position(_enemy.global_position,
				Vector3(_drone.global_position.x, _enemy.global_position.y,
				_drone.global_position.z), Vector3.UP)
		_rig.snap_to_ground()
	_perception.set_target(_drone)
	_enemy.set_target_position(_drone.global_position)


## Lanza [param action] por la capa de acción, sin pasar por el selector.
func _fire(action: EnemyAction) -> bool:
	# El cerebro está apagado, así que su caché de contexto es la de la última
	# vez que pensó: sin refrescarla, la acción apuntaría adonde estaba el dron
	# hace media prueba.
	var _ctx := _brain.refresh_context()
	action.mark_started()
	var payload: Dictionary = {&"action": action, &"telegraph": _telegraph}
	if action.telegraph_seconds() > 0.0:
		return _brain.request_action(EnemyFSM.ACTION_TELEGRAPH, payload)
	return _brain.request_action(EnemyFSM.ACTION_ACTIVE, payload)


## HP total de los seis edificios.
func _city_hp() -> float:
	var total := 0.0
	for building: Building in _buildings:
		total += building.hp
	return total


## El windup efectivo de cada ataque, en cada una de las cinco fases, se queda
## en 0.80 s o más (`docs/07` §13 #7: «en las 5 fases»).
func _check_windup_matrix() -> void:
	var worst := 1.0e6
	var worst_label := ""
	for attack_id: StringName in ATTACK_IDS:
		var action := _library.find(attack_id)
		if action == null or action.profile == null:
			continue
		for phase: Dictionary in _enemy.profile.phases:
			var effects := phase.get("then", {}) as Dictionary
			var multipliers := effects.get("multipliers", {}) as Dictionary
			var multiplier := float(multipliers.get("windup",
					multipliers.get(&"windup", 1.0)))
			var effective := maxf(EnemyAction.MIN_WINDUP,
					action.profile.windup * multiplier)
			expect(effective >= EnemyAction.MIN_WINDUP,
					"windup de '%s' en '%s': esperado=>=%.2f medido=%.3f"
					% [attack_id, phase.get("id", &""), EnemyAction.MIN_WINDUP, effective])
			if effective < worst:
				worst = effective
				worst_label = "%s/%s" % [attack_id, phase.get("id", &"")]
	_summary.append("windup efectivo mínimo en las 5 fases: %.3f s en %s"
			% [worst, worst_label])


# --------------------------------------------------------------------------
# 8 · Cooldowns
# --------------------------------------------------------------------------

## 600 decisiones simuladas: ninguna acción se repite antes de su enfriamiento.
##
## El reloj de las acciones se avanza a mano, un paso de decisión por vuelta, así
## que la prueba es determinista y no depende del ritmo de la física.
func _check_cooldowns() -> void:
	var actions := _library.get_actions()
	for action: EnemyAction in actions:
		action.reset_action()
	var selector := UtilitySelector.new()
	selector.configure(Global.round_seed)
	var personality := Personality.from_seed(Global.round_seed, _library.attack_ids(),
			_enemy.profile.personality_spread)

	var last_use: Dictionary[StringName, float] = {}
	var counts: Dictionary[StringName, int] = {}
	var violations := 0
	var now := 0.0
	for step: int in DECISIONS:
		for action: EnemyAction in actions:
			action._physics_process(DECISION_STEP)
		now += DECISION_STEP
		var chosen := selector.select(actions, _synthetic_context(step), personality,
				_enemy.profile.top_n)
		if chosen == null:
			continue
		var attack_id := chosen.id()
		var cooldown := chosen.effective_cooldown()
		if last_use.has(attack_id):
			var gap := now - float(last_use[attack_id])
			if gap < cooldown - 0.001:
				violations += 1
				fail("cooldown de '%s': esperado=>=%.2f s medido=%.2f s"
						% [attack_id, cooldown, gap])
		last_use[attack_id] = now
		counts[attack_id] = int(counts.get(attack_id, 0)) + 1
		chosen.mark_started()
		chosen.finish()

	expect(violations == 0,
			"cooldowns: esperado=0 repeticiones tempranas medido=%d" % violations)
	expect(not counts.is_empty(), "ninguna acción se eligió en %d decisiones" % DECISIONS)
	for action: EnemyAction in actions:
		action.reset_action()
	_summary.append("cooldowns: %d decisiones, %d acciones usadas, 0 repeticiones tempranas"
			% [DECISIONS, counts.size()])


## Contexto sintético que barre toda la banda útil del move set.
func _synthetic_context(step: int) -> Dictionary:
	var phase := float(step) * 0.11
	return {
		&"distance": 34.0 + 30.0 * sin(phase),
		&"distance_3d": 36.0 + 30.0 * sin(phase),
		&"drone_height": 6.0 + 5.0 * sin(phase * 0.7),
		&"drone_speed": 5.0 + 4.0 * sin(phase * 0.3),
		&"has_los": true,
		&"confidence": 1.0,
		&"time_near": 8.0 if sin(phase * 0.5) > 0.0 else 0.0,
		&"time_since_city_attack": 10.0 + 10.0 * sin(phase * 0.23),
		&"buildings_in_cone": 3,
		&"structure_ratio": 1.0,
		&"phase": _enemy.current_phase(),
		&"planted_legs": 4,
		&"legs_lost": 0,
		&"city_target": _tower,
		&"city_position": _tower.global_position,
		&"city_distance": 50.0 + 20.0 * sin(phase * 0.41),
		&"city_value": _tower.value,
		&"city_bias": 0.7,
		&"believed_position": _enemy.global_position + Vector3(30.0, 6.0, 0.0),
		&"has_drone_target": true,
		&"has_city_target": true,
		&"has_any_target": true,
		&"has_march_goal": false,
		&"round_seed": Global.round_seed,
	}


# --------------------------------------------------------------------------
# 3, 4, 5 y 11 · Fases, desbloqueos, núcleo y `on_destroy`
# --------------------------------------------------------------------------

func _check_phases() -> void:
	_phase_log.clear()
	expect(_enemy.current_phase() == PHASE_IDS[0],
			"fase inicial: esperado=%s medido=%s" % [PHASE_IDS[0], _enemy.current_phase()])
	_check_unlocks(PHASE_IDS[0])

	# --- P2: una rodilla ---------------------------------------------------
	await _break_weak_point(KNEES[0])
	expect(_enemy.current_phase() == PHASE_IDS[1],
			"tras 1 rodilla: esperado=%s medido=%s" % [PHASE_IDS[1], _enemy.current_phase()])
	_check_unlocks(PHASE_IDS[1])
	# 11 · el fémur de esa pata se desprendió.
	var femur := _enemy.get_part(&"leg_fl_femur")
	expect(femur != null and femur.is_detached(),
			"on_destroy de rodilla: esperado=fémur desprendido medido=%s"
			% ("desprendido" if femur != null and femur.is_detached() else "en su sitio"))
	expect(_enemy.legs_lost() == 1,
			"patas perdidas tras 1 rodilla: esperado=1 medido=%d" % _enemy.legs_lost())

	# --- P3: dos rodillas ---------------------------------------------------
	await _break_weak_point(KNEES[1])
	expect(_enemy.current_phase() == PHASE_IDS[2],
			"tras 2 rodillas: esperado=%s medido=%s" % [PHASE_IDS[2], _enemy.current_phase()])
	_check_unlocks(PHASE_IDS[2])
	# 5 · con dos rodillas rotas el núcleo no se expone ni desde abajo.
	_enemy.set_target_position(_enemy.global_position + Vector3(0.0, -30.0, 0.0))
	await wait_physics(4)
	for core_id: StringName in CORES:
		var core := _enemy.get_weak_point(core_id)
		expect(core != null and not core.is_exposed(),
				"núcleo '%s' con 2 rodillas: esperado=cubierto medido=expuesto" % core_id)

	# --- P4: tres rodillas, carcasa y cono ----------------------------------
	await _break_weak_point(KNEES[2])
	expect(_enemy.current_phase() == PHASE_IDS[3],
			"tras 3 rodillas: esperado=%s medido=%s" % [PHASE_IDS[3], _enemy.current_phase()])
	_check_unlocks(PHASE_IDS[3])
	await _advance(Arachnodroid.CARAPACE_SECONDS + 0.4)
	expect(_enemy.is_carapace_open(),
			"carcasa en P4: esperado=abierta medido=%.2f de apertura"
			% _enemy.carapace_progress())
	expect_near(_enemy.carapace_angle(), Arachnodroid.CARAPACE_ANGLE, 0.01,
			"ángulo de apertura de la carcasa")
	var core_a := _enemy.get_weak_point(CORES[0])
	expect(core_a != null and is_equal_approx(core_a.profile.cone_half_angle, CONE_OPEN),
			"cono del núcleo en P4: esperado=%.1f° medido=%.1f°"
			% [CONE_OPEN, core_a.profile.cone_half_angle if core_a != null else -1.0])

	# 5 · con tres rodillas y el dron debajo, dentro del cono, se expone.
	_enemy.set_target_position(_enemy.global_position + Vector3(0.0, -30.0, 0.0))
	await wait_physics(4)
	for core_id: StringName in CORES:
		var core := _enemy.get_weak_point(core_id)
		expect(core != null and core.is_exposed(),
				"núcleo '%s' con 3 rodillas y el dron debajo: esperado=expuesto medido=cubierto"
				% core_id)
	# Y fuera del cono vuelve a cubrirse.
	_enemy.set_target_position(_enemy.global_position + Vector3(140.0, 30.0, 0.0))
	await wait_physics(4)
	var outside := _enemy.get_weak_point(CORES[0])
	expect(outside != null and not outside.is_exposed(),
			"núcleo fuera del cono: esperado=cubierto medido=expuesto")

	# --- 11 · visor: ceguera 20 s, bloqueo 30 s y respaldo a los 45 s -------
	await _check_visor_on_destroy()

	# --- 3 · las cinco fases, en orden y sin retrocesos ---------------------
	await _break_weak_point(CORES[0])
	await _break_weak_point(CORES[1])
	expect(_enemy.current_phase() == PHASE_IDS[4],
			"tras 2 núcleos: esperado=%s medido=%s" % [PHASE_IDS[4], _enemy.current_phase()])
	expect(_phase_log.size() == 4,
			"cambios de fase publicados: esperado=4 (P2…P5) medido=%d" % _phase_log.size())
	var expected := PHASE_IDS.slice(1)
	expect(_phase_log == expected,
			"secuencia de fases: esperado=%s medido=%s" % [str(expected), str(_phase_log)])
	# 12 · el temporizador arranca en 45.0 s. Se mide el valor **anunciado** por
	# `selfdestruct_started`: `selfdestruct_remaining()` ya descontó los ticks
	# que el check tarda en mirarlo, y con la simulación acelerada eso son
	# décimas.
	expect_near(_selfdestruct_announced, SELFDESTRUCT_SECONDS,
			SELFDESTRUCT_TOLERANCE, "temporizador de P5 anunciado al entrar en la fase")
	expect(_enemy.selfdestruct_remaining() > SELFDESTRUCT_SECONDS - 1.0,
			"temporizador de P5: esperado=~%.1f s medido=%.2f s"
			% [SELFDESTRUCT_SECONDS, _enemy.selfdestruct_remaining()])
	_summary.append("fases: %s · carcasa 70° · cono %.0f° · temporizador %.2f s"
			% [str(_phase_log), CONE_OPEN, _selfdestruct_announced])


## 4 · Los desbloqueos de cada fase (`docs/07` §6).
func _check_unlocks(phase_id: StringName) -> void:
	var available := _enemy.unlocked_attacks()
	var rules: Dictionary[StringName, bool] = {}
	match phase_id:
		&"p1_siege":
			rules = {&"climb": true, &"stomp": true, &"leg_sweep": true,
					&"siege_beam": true, &"shake_off": true,
					&"head_laser": false, &"emp_pulse": false, &"pounce": false}
		&"p2_alert":
			rules = {&"head_laser": true, &"emp_pulse": true, &"pounce": false,
					&"climb": true}
		&"p3_fury":
			rules = {&"head_laser": true, &"emp_pulse": true, &"pounce": true,
					&"climb": true}
		&"p4_belly":
			rules = {&"pounce": true, &"climb": false, &"stomp": true,
					&"head_laser": true}
		&"p5_selfdestruct":
			rules = {&"climb": false, &"stomp": false, &"leg_sweep": false,
					&"head_laser": false, &"siege_beam": false, &"emp_pulse": false,
					&"pounce": false, &"shake_off": true}
	for attack_id: StringName in rules:
		var wanted := rules[attack_id]
		var got := available.has(String(attack_id))
		expect(got == wanted,
				"'%s' en %s: esperado=%s medido=%s"
				% [attack_id, phase_id, "disponible" if wanted else "bloqueado",
				"disponible" if got else "bloqueado"])


## 11 · Romper el visor: ceguera 20 s, `head_laser` bloqueado 30 s y sensor de
## respaldo a los 45 s que devuelve la percepción a la nominal.
func _check_visor_on_destroy() -> void:
	# El visor sólo se expone atacando; el daño se aplica a la parte, que es lo
	# que hace el arma cuando el rayo le pega (`docs/08` §2.7).
	await _break_weak_point(&"wp_head_visor")
	expect(_perception.is_blinded(), "romper el visor no cegó la percepción")
	expect_near(_perception.blind_remaining(), 20.0, 0.5,
			"ceguera del visor al romperse")
	expect(_enemy.is_attack_locked(&"head_laser"),
			"'head_laser' no quedó bloqueado al romper el visor")
	expect_near(_enemy.backup_sensor_remaining(), 45.0, 0.5,
			"reloj del sensor de respaldo al romper el visor")

	await _advance(21.0)
	expect(not _perception.is_blinded(),
			"a los 21 s: esperado=percepción recuperada medido=ciega")
	await _advance(10.5)
	expect(not _enemy.is_attack_locked(&"head_laser"),
			"a los 31.5 s: esperado='head_laser' desbloqueado medido=bloqueado")

	# Prueba de verdad del respaldo: se vuelve a cegar con 30 s —que pasarían de
	# los 45 s del reloj— y el sensor tiene que cortarla al llegar.
	_perception.blind(30.0)
	expect(_perception.is_blinded(), "la ceguera de prueba no se aplicó")
	await _advance(15.0)
	expect(_enemy.backup_sensor_online(),
			"sensor de respaldo a los 46 s: esperado=en línea medido=fuera de línea")
	expect(not _perception.is_blinded(),
			"el sensor de respaldo no restituyó la percepción nominal")
	expect_near(_perception.noise_sigma(), _perception.profile.noise_base, 0.01,
			"σ nominal restituida por el sensor de respaldo")
	_summary.append("visor: ceguera 20 s · bloqueo 30 s · respaldo a los 45 s")


# --------------------------------------------------------------------------
# 10 · `DOWNED`
# --------------------------------------------------------------------------

func _check_downed() -> void:
	var remaining_before := _enemy.selfdestruct_remaining()
	await _break_weak_point(KNEES[3])
	await _advance(3.0)
	expect(_enemy.is_downed(),
			"4 patas perdidas: esperado=is_downed() true medido=false")
	expect(_enemy.locomotion_state() == &"DOWNED",
			"capa de locomoción: esperado=DOWNED medido=%s" % _enemy.locomotion_state())
	expect(is_equal_approx(_rig.speed_multiplier(), 0.0),
			"velocidad con 4 patas perdidas: esperado=0.0 medido=%.3f"
			% _rig.speed_multiplier())
	var before := _enemy.global_position
	_enemy.move_body(0.1, Vector3(6.0, 0.0, 0.0))
	expect(is_equal_approx(before.x, _enemy.global_position.x),
			"caído, el cuerpo se movió %.3f m" % absf(before.x - _enemy.global_position.x))

	# El cuerpo **descansa sobre el suelo**, no se entierra: antes de WP-19b
	# caía a y = −12.3 y los núcleos quedaban bajo tierra, sin exponerse jamás.
	var origin_y := _enemy.global_position.y
	expect(origin_y >= GROUND_TOP - DOWNED_MIN_ORIGIN,
			"origen del cuerpo caído: esperado=>=%.1f medido=%.2f"
			% [GROUND_TOP - DOWNED_MIN_ORIGIN, origin_y])

	# Los núcleos que sigan enteros quedan expuestos de forma permanente, con el
	# objetivo **fuera** del cono: `_check_phases` lo dejó a 140 m y 30 m de
	# altura. Los dos que ya se rompieron para entrar en P5 no vuelven: un punto
	# débil roto no se expone nunca más (`docs/06` §5).
	var standing := 0
	for core_id: StringName in CORES:
		var core := _enemy.get_weak_point(core_id)
		if core == null or core.is_broken():
			continue
		standing += 1
		expect(core.is_exposed(),
				"núcleo entero '%s' con el jefe caído: esperado=expuesto medido=cubierto"
				% core_id)
	expect(standing > 0, "no quedó ningún núcleo entero para medir la exposición")
	expect(_enemy.is_carapace_open(),
			"carcasa con el jefe caído: esperado=abierta medido=%.2f de apertura"
			% _enemy.carapace_progress())

	# P5 ya venía corriendo desde `_check_phases`: el desplome **conserva** el
	# tiempo que quedaba en vez de reiniciar la cuenta a 90 s.
	expect(not _enemy.is_downed_selfdestruct(),
			"el desplome reinició una cuenta atrás que ya estaba corriendo")
	expect(_enemy.selfdestruct_remaining() <= remaining_before + 0.01,
			"temporizador tras el desplome: esperado=<=%.2f s medido=%.2f s"
			% [remaining_before, _enemy.selfdestruct_remaining()])
	_summary.append("DOWNED: 4 patas, velocidad 0, origen y=%.2f, %d núcleo(s) entero(s) expuesto(s), P5 intacta"
			% [origin_y, standing])


## 10b · Si el desplome llega **antes** que P5, el jefe entra en P5 solo con una
## cuenta de 90 s y la ronda termina igual.
func _check_downed_selfdestruct() -> void:
	if not await _respawn_enemy():
		return
	_enemy.global_position = _enemy.city_centre()
	_rig.snap_to_ground()
	_perception.set_target(_drone)
	_drone.park(_enemy.global_position + Vector3(0.0, 40.0, 0.0))
	await wait_physics(4)

	_selfdestruct_announced = -1.0
	for knee_id: StringName in KNEES:
		await _break_weak_point(knee_id)
	await _advance(3.0)

	expect(_enemy.is_downed(), "4 rodillas rotas: esperado=DOWNED medido=en pie")
	expect(_enemy.current_phase() == PHASE_IDS[4],
			"fase tras el desplome: esperado=%s medido=%s"
			% [PHASE_IDS[4], _enemy.current_phase()])
	expect(_enemy.is_downed_selfdestruct(),
			"la cuenta atrás del desplome no se marcó como tal")
	expect_near(_selfdestruct_announced, Arachnodroid.SELFDESTRUCT_SECONDS_DOWNED,
			SELFDESTRUCT_TOLERANCE, "temporizador anunciado por el desplome")
	var available := _enemy.unlocked_attacks()
	expect(available.has("shake_off"),
			"caído: esperado='shake_off' disponible medido=bloqueado")
	for attack_id: StringName in ATTACK_IDS:
		if attack_id == &"shake_off":
			continue
		expect(not available.has(String(attack_id)),
				"caído: '%s' esperado=bloqueado medido=disponible" % attack_id)
	for core_id: StringName in CORES:
		var core := _enemy.get_weak_point(core_id)
		expect(core != null and core.is_exposed(),
				"núcleo '%s' tras el desplome: esperado=expuesto medido=cubierto" % core_id)

	# Y la ronda **termina**: la cuenta expira y el jefe detona una sola vez.
	# La cuenta ya venía corriendo mientras se rompían las rodillas, así que se
	# mide contra lo que quedaba, no contra los 90 s nominales.
	var remaining_at_start := _enemy.selfdestruct_remaining()
	var elapsed := await _wait_for_detonation(
			Arachnodroid.SELFDESTRUCT_SECONDS_DOWNED * 1.4)
	expect(_enemy.is_defeated(), "la cuenta del desplome expiró sin derrotar al jefe")
	expect(_defeats == 1,
			"enemy_defeated por desplome: esperado=1 medido=%d" % _defeats)
	expect_near(elapsed, remaining_at_start, 2.0,
			"duración medida de la cuenta del desplome")
	_summary.append("DOWNED→P5: %.1f s anunciados, %.1f s restantes, %.1f s medidos, 1 enemy_defeated"
			% [_selfdestruct_announced, remaining_at_start, elapsed])


# --------------------------------------------------------------------------
# 13 · Escombros
# --------------------------------------------------------------------------

## Con las 4 patas, la carcasa y las 2 antenas desprendidas el pool no se pasa.
func _check_debris() -> void:
	if _pool == null:
		fail("la escena del check no trae DebrisPool")
		return
	for part_id: StringName in [&"carapace", &"antenna_l", &"antenna_r"]:
		await _break_part(part_id)
	await _advance(0.5)
	var live := _pool.get_live_count()
	expect(live <= DEBRIS_LIMIT,
			"escombros vivos: esperado=<=%d medido=%d" % [DEBRIS_LIMIT, live])
	for part_id: StringName in [&"carapace", &"antenna_l", &"antenna_r"]:
		var part := _enemy.get_part(part_id)
		expect(part != null and part.is_detached(),
				"'%s': esperado=desprendida medido=en su sitio" % part_id)
	_summary.append("escombros: %d vivos (tope %d) con 4 patas, carcasa y 2 antenas"
			% [live, DEBRIS_LIMIT])


# --------------------------------------------------------------------------
# 9 · `defeated` una sola vez, primera corrida (los tres núcleos)
# --------------------------------------------------------------------------

func _check_defeat_by_cores() -> void:
	_defeats = 0
	await _break_weak_point(CORES[2])
	await _advance(1.0)
	expect(_enemy.is_defeated(), "romper los 3 núcleos no derrotó al jefe")
	expect(_defeats == 1,
			"enemy_defeated por 3 núcleos: esperado=1 medido=%d" % _defeats)
	expect(_enemy.selfdestruct_remaining() < 0.0,
			"el tercer núcleo no paró la cuenta atrás: quedan %.2f s"
			% _enemy.selfdestruct_remaining())
	# Prueba negativa 2: pedir la derrota otra vez no vuelve a emitirla.
	_enemy.declare_defeat()
	_enemy.declare_defeat()
	await wait_physics(2)
	expect(_defeats == 1,
			"negativa: declare_defeat() ×3 emitió %d veces enemy_defeated" % _defeats)
	_summary.append("derrota por núcleos: 1 emisión, sin detonar (quedaban %.1f s)"
			% SELFDESTRUCT_SECONDS)


# --------------------------------------------------------------------------
# Audio (`docs/07` §10)
# --------------------------------------------------------------------------

func _check_audio() -> void:
	var events := PackedStringArray(["footstep_1", "footstep_2", "footstep_3",
			"footstep_4", "servo_loop", "leg_tear", "part_break", "phase_shift",
			"selfdestruct_tick", "emp_burst"])
	for attack_id: StringName in ATTACK_IDS:
		events.append("charge_%s" % attack_id)
	for event: String in events:
		expect(_audio.has_event(StringName(event)),
				"banco de audio: falta '%s.wav'" % event)
	expect(_audio.played_count() > 0,
			"el AudioRig no disparó ningún evento en toda la corrida")
	# Ocho disparos seguidos no pueden pasarse del presupuesto de voces.
	for index: int in 12:
		var _player := _audio.play(&"part_break")
	await wait_physics(1)
	var voices := _audio.active_voices()
	expect(voices <= VOICE_BUDGET - 1,
			"voces del AudioRig: esperado=<=%d medido=%d (la octava es la carga del Telegraph)"
			% [VOICE_BUDGET - 1, voices])
	_audio.stop_all()
	_summary.append("audio: %d eventos disparados, %d voces como mucho (tope %d con el Telegraph)"
			% [_audio.played_count(), voices, VOICE_BUDGET])


# --------------------------------------------------------------------------
# 12 y 9 · Autodestrucción, segunda corrida
# --------------------------------------------------------------------------

## Un jefe nuevo, llevado a P5, con el temporizador corriendo hasta el final.
func _check_selfdestruct() -> void:
	if not await _respawn_enemy():
		return
	# El jefe se planta en el baricentro de la ciudad para que la detonación
	# tenga edificios dentro de los 120 m.
	_enemy.global_position = _enemy.city_centre()
	_rig.snap_to_ground()
	await wait_physics(4)

	for knee_id: StringName in KNEES.slice(0, 3):
		await _break_weak_point(knee_id)
	await _break_weak_point(CORES[0])
	await _break_weak_point(CORES[1])
	expect(_enemy.current_phase() == PHASE_IDS[4],
			"segunda corrida: esperado=%s medido=%s" % [PHASE_IDS[4], _enemy.current_phase()])
	expect_near(_selfdestruct_announced, SELFDESTRUCT_SECONDS,
			SELFDESTRUCT_TOLERANCE, "temporizador de P5 anunciado, segunda corrida")
	expect(_enemy.march_goal() != null,
			"en P5 el jefe no publicó destino de marcha hacia el centro de la ciudad")

	var near_before: Dictionary[int, float] = {}
	var far_before: Dictionary[int, float] = {}
	for building: Building in _buildings:
		var distance := building.global_position.distance_to(_enemy.global_position)
		if distance <= DETONATION_RADIUS:
			near_before[building.get_instance_id()] = building.hp
		else:
			far_before[building.get_instance_id()] = building.hp
	expect(not near_before.is_empty(),
			"no hay ningún edificio a <= %.0f m para medir la detonación" % DETONATION_RADIUS)

	# Cuántos emisivos de carcasa quedaron bajo el pulso blanco. Es una
	# observación, no un umbral: `docs/07` §13 no lo pide y depende de cuántas
	# superficies emisivas traiga el GLB (`docs/05` §9.2).
	await wait_physics(4)
	var pulse_materials := _enemy.pulse_material_count()
	var elapsed := await _wait_for_detonation(SELFDESTRUCT_SECONDS * 1.4)
	expect(_enemy.is_defeated(), "el temporizador expiró sin derrotar al jefe")
	expect(_defeats == 1,
			"enemy_defeated por temporizador: esperado=1 medido=%d" % _defeats)
	expect_near(elapsed, SELFDESTRUCT_SECONDS, 1.0,
			"duración medida de la cuenta atrás")
	expect(_enemy.selfdestruct_ticks() > 0,
			"la cuenta atrás no emitió ningún selfdestruct_tick")

	var damaged := 0
	for building: Building in _buildings:
		var key := building.get_instance_id()
		if near_before.has(key):
			if building.hp < float(near_before[key]) - 0.001:
				damaged += 1
		elif far_before.has(key):
			expect(is_equal_approx(building.hp, float(far_before[key])),
					"la detonación dañó un edificio a más de %.0f m" % DETONATION_RADIUS)
	expect(damaged == near_before.size(),
			"detonación: esperado=%d edificios dañados a <= %.0f m medido=%d"
			% [near_before.size(), DETONATION_RADIUS, damaged])

	# Prueba negativa 3: detonar dos veces no cobra el daño dos veces.
	var snapshot: Dictionary[int, float] = {}
	for building: Building in _buildings:
		snapshot[building.get_instance_id()] = building.hp
	_enemy.detonate()
	await wait_physics(2)
	for building: Building in _buildings:
		expect(is_equal_approx(building.hp, float(snapshot[building.get_instance_id()])),
				"negativa: detonate() dos veces volvió a dañar '%s'" % building.name)
	expect(_defeats == 1,
			"negativa: detonate() dos veces emitió %d enemy_defeated" % _defeats)
	_summary.append("P5: %.2f s medidos, %d tics, %d edificios dañados a <= %.0f m · %d emisivos pulsando"
			% [elapsed, _enemy.selfdestruct_ticks(), damaged, DETONATION_RADIUS,
			pulse_materials])


## Tira el jefe de la corrida anterior, repara la ciudad y levanta uno nuevo.
##
## Cada corrida de derrota necesita un jefe entero: `defeated` se emite una sola
## vez por vida (`docs/06` §6) y los edificios ya vienen mordidos de las pruebas
## de daño.
func _respawn_enemy() -> bool:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	_enemy = null
	await wait_frames(2)
	for building: Building in _buildings:
		building.hp = building.get_max_hp()
		building.stage = Building.Stage.INTACT

	if not await _spawn_enemy():
		return false
	if _enemy == null:
		return false
	_perception = _enemy.perception as Perception
	_brain = _enemy.brain as EnemyFSM
	_rig = _enemy.locomotion as ProceduralLegRig
	_library = _enemy.get_node_or_null(^"AttackLibrary") as AttackLibrary
	_telegraph = _enemy.get_node_or_null(^"Telegraph") as Telegraph
	_audio = _enemy.get_node_or_null(^"AudioRig") as AudioRig
	_brain.autonomous = false
	_defeats = 0
	return true


## Segundos simulados hasta que el jefe detona, o [param limit] si no lo hace.
func _wait_for_detonation(limit: float) -> float:
	var elapsed := 0.0
	while elapsed < limit and not _enemy.is_defeated():
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return elapsed


# --------------------------------------------------------------------------
# Prueba negativa 1 · el piso del windup
# --------------------------------------------------------------------------

## Un `AttackProfile` con `windup 0.30` tiene que telegrafiar 0.80 s igual, en la
## API [b]y[/b] en el reloj de la máquina de estados (`docs/06` §6.1).
func _check_negatives() -> void:
	var action := _library.find(&"stomp")
	if action == null:
		fail("no se pudo tomar 'stomp' para la prueba negativa")
		return
	var original := action.profile
	var patched := original.duplicate() as AttackProfile
	patched.windup = NEGATIVE_WINDUP
	action.profile = patched
	action.reset_action()

	expect(action.raw_windup() < EnemyAction.MIN_WINDUP,
			"la prueba negativa no llegó a pedir un windup por debajo del mínimo")
	expect_near(action.effective_windup(), EnemyAction.MIN_WINDUP, 0.001,
			"effective_windup() con windup forzado a %.2f s" % NEGATIVE_WINDUP)
	expect_near(action.telegraph_seconds(), EnemyAction.MIN_WINDUP, 0.001,
			"telegraph_seconds() con windup forzado a %.2f s" % NEGATIVE_WINDUP)

	# Y el reloj real de la FSM. El jefe de esta corrida está derrotado, así que
	# se revive lo justo para conducir la acción: `is_defeated()` no bloquea la
	# capa de acción, sólo el tambaleo y la caída lo hacen.
	_enemy.global_position = Vector3.ZERO
	_rig.release_all_legs()
	_rig.snap_to_ground()
	_drone.park(Vector3(9.0, 2.0, 0.0))
	_perception.set_target(_drone)
	await wait_physics(4)
	_telegraph_events.clear()
	var measured := 0.0
	if _fire(action):
		while _brain.action_state() == EnemyFSM.ACTION_TELEGRAPH and measured < ACTION_BUDGET:
			await get_tree().physics_frame
			measured += get_physics_process_delta_time()
	action.finish()
	expect(measured >= EnemyAction.MIN_WINDUP - 0.02,
			"negativa: con windup %.2f s la FSM pasó %.3f s en TELEGRAPH (mínimo %.2f s)"
			% [NEGATIVE_WINDUP, measured, EnemyAction.MIN_WINDUP])
	for event: Dictionary in _telegraph_events:
		expect(float(event["duration"]) >= EnemyAction.MIN_WINDUP,
				"negativa: el aviso saboteado se anunció en %.3f s" % float(event["duration"]))
	action.profile = original
	_summary.append("negativa: windup %.2f s crudo → %.3f s medidos en TELEGRAPH"
			% [NEGATIVE_WINDUP, measured])


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Rompe el punto débil [param weak_point_id] como lo haría el arma.
func _break_weak_point(weak_point_id: StringName) -> void:
	await _break_part(weak_point_id)


## Rompe la parte [param part_id] de un golpe y deja pasar dos ticks para que se
## propaguen las fases y la exposición.
func _break_part(part_id: StringName) -> void:
	var part := _enemy.get_part(part_id)
	if part == null:
		fail("no existe la parte '%s'" % part_id)
		return
	if not part.is_broken():
		var _effective := part.take_damage(part.hp / maxf(1.0 - part.armor, 0.01),
				_hit(part.world_position(), true, part_id))
	await wait_physics(3)


## Avanza [param seconds] simulados y devuelve lo que avanzó de verdad.
func _advance(seconds: float) -> float:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return elapsed


## Deja la capa de acción en `NONE` y el cuerpo quieto.
func _settle() -> void:
	_brain.autonomous = false
	_brain.set_action_state(EnemyFSM.ACTION_NONE)
	_rig.release_all_legs()
	_rig.clear_crouch()
	await _wait_calm()


## Espera a que se le pase el tambaleo.
##
## El aterrizaje del salto tambalea 0.35 s (`docs/06` §8.6 punto 4) y un jefe
## tambaleando no telegrafía, no puntúa y cancela lo que tenga en curso: medir el
## ataque siguiente sin esperar a que se recupere daría cero sin que nada esté
## roto.
func _wait_calm() -> void:
	var elapsed := 0.0
	while _enemy.is_staggered() and elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	await wait_physics(4)


func _on_phase_changed(source: Node3D, phase_id: StringName) -> void:
	if source != _enemy:
		return
	_phase_log.append(phase_id)


func _on_defeated(source: Node3D, _enemy_id: StringName) -> void:
	if source != _enemy:
		return
	_defeats += 1


func _on_selfdestruct_started(seconds: float) -> void:
	_selfdestruct_announced = seconds


func _on_telegraphed(_source: Node3D, attack_id: StringName, duration: float) -> void:
	_telegraph_events.append({"attack_id": attack_id, "duration": duration,
			"time": _sim_time})


func _physics_process(delta: float) -> void:
	_sim_time += delta


## Imprime el resumen de métricas.
func _print_summary() -> void:
	for line: String in _summary:
		print("  %s" % line)
	print("  duración del check: %.1f s reales"
			% (float(Time.get_ticks_usec() - _started_usec) / 1000000.0))


## Cierra el check restaurando el entorno **siempre**, también cuando el fallo es
## un timeout y [method _run] nunca llega a volver.
func finish() -> void:
	_restore()
	super.finish()


## Devuelve la semilla y la bandera de congelado a como estaban. Es idempotente.
func _restore() -> void:
	Engine.time_scale = 1.0
	Global.round_seed = _seed_before
	Global.debug_freeze_ai = _freeze_before
	for signal_pair: Array in [[Events.enemy_phase_changed, _on_phase_changed],
			[Events.enemy_defeated, _on_defeated],
			[Events.enemy_attack_telegraphed, _on_telegraphed]]:
		var source := signal_pair[0] as Signal
		var target := signal_pair[1] as Callable
		if source.is_connected(target):
			source.disconnect(target)
