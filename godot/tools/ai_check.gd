## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-18: percepción, selector de utilidad y máquina de dos capas
## (`docs/06` §16.3).
##
## Levanta un mundo sintético —suelo llano, seis [Building] de valor distinto en
## la capa 8 y un dron de prueba en la capa 2 con su casco— e instancia al
## Arachnodroid. Después mide, en este orden:
##
## | # | Criterio | Umbral |
## |---|---|---|
## | a1 | σ del ruido con el dron quieto, 200 muestras | `noise_base` ± 20 % |
## | a2 | σ con el dron a 8 m/s, 200 muestras | `noise_base + 0.25·v` ± 20 % |
## | a3 | LOS se pierde al interponer un bloque de capa 1 | ≤ 0.15 s |
## | a4 | La creencia deja de seguir al dron sin visión | > 20 m de error |
## | a5 | `confidence` cae a 0 | `memory_seconds` ± 10 % |
## | a6 | `search_point()` cambia mientras busca | cada ~2 s |
## | a7 | LOS se recupera al quitar el bloque | ≤ 0.15 s |
## | a8 | Cegado: σ ×5 y memoria 1.5 s | ± 20 % y ± 10 % |
## | b1 | 3 semillas × 600 decisiones → 3 histogramas | L1 ≥ 0.15 entre pares |
## | b2 | Misma semilla, misma secuencia | igualdad exacta |
## | b3 | Nada elegido con `score <= 0`, en cooldown o fuera de rango | 0 casos |
## | b4 | Ninguna acción monopoliza ni queda muerta | `p_max ≤ 0.60`, todas > 0 |
## | c1 | Toda acción dañina pasa por `TELEGRAPH` antes de `ACTIVE` | ≥ 0.80 s |
## | c2 | `lock_locomotion` detiene `move_body` | < 0.5 m de deriva |
## | c3 | `stagger()` interrumpe y vuelve a `NONE` | estado `NONE` |
## | c4 | `DOWNED` bloquea las decisiones | 0 consultas nuevas |
## | d1 | `approach` llega al edificio más valioso | < 30 m en < 60 s |
## | d2 | `stomp` daña al edificio y al dron | HP y casco bajan |
## | d3 | El impulso al dron sale recortado | ≤ 120 N·s pese a pedir 500 |
## | e | Cadencias de decisión y de percepción | 4 Hz y 10 Hz ± 1 tick |
## | f | Sin nodos huérfanos tras liberar al jefe | 0 |
## | g | `Global.debug_freeze_ai` congela cerebro, rig y movedor | 0 cambios en 2 s |
##
## Y cierra con una [b]prueba negativa[/b]: se fuerza el `windup` de la
## plantilla a 0.30 s —por debajo del mínimo absoluto de `docs/06` §6.1— y se
## comprueba que el marco lo levanta igualmente a 0.80 s, tanto en la API como
## en el tiempo real que la FSM pasa en `TELEGRAPH`.
##
## El mundo lo arma este script, no la escena: los tamaños salen de las
## constantes de acá y no hay que editar un `.tscn` para mover un edificio.
extends CheckRunner

## Escena del jefe.
const ENEMY_SCENE: String = "res://enemies/arachnodroid/arachnodroid.tscn"

## Perfil de edificio del que salen los seis de prueba (`docs/10` §4.2).
const BUILDING_PROFILE: String = "res://city/profiles/low_block.tres"

## Aceleración de la simulación. El tope que fija WP-18 es 4×.
const TIME_SCALE: float = 4.0

## Muestras de ruido por medición (`docs/06` §16.3 #8).
const NOISE_SAMPLES: int = 200

## Tolerancia de la desviación medida, como fracción.
const SIGMA_TOLERANCE: float = 0.20

## Tolerancia de la memoria medida, como fracción.
const MEMORY_TOLERANCE: float = 0.10

## Tiempo máximo que puede tardar la línea de visión en conmutar, en segundos.
const LOS_SWITCH_LIMIT: float = 0.15

## Velocidad del dron en la medición de σ con movimiento, en m/s.
const ORBIT_SPEED: float = 8.0

## Radio y altura de la órbita del dron de prueba, en metros.
const ORBIT_RADIUS: float = 60.0
const ORBIT_HEIGHT: float = 30.0

## Semillas de `Global.round_seed` de `docs/06` §16.3 #1.
const SEEDS: Array[int] = [1, 7, 99]

## Decisiones por semilla en la prueba del selector.
const DECISIONS_PER_SEED: int = 600

## Paso simulado entre dos decisiones sintéticas, en segundos (4 Hz).
const DECISION_STEP: float = 0.25

## Distancia L1 mínima entre los histogramas de dos semillas.
const MIN_HISTOGRAM_L1: float = 0.15

## Probabilidad máxima admisible para una sola acción.
const MAX_ACTION_SHARE: float = 0.60

## Segundos simulados que se le dan a `approach` para llegar al objetivo.
const APPROACH_BUDGET: float = 60.0

## Distancia a la que se da por alcanzado el edificio, en metros.
const APPROACH_GOAL: float = 30.0

## Segundos simulados que se le dan al pisotón para dispararse.
const STOMP_BUDGET: float = 20.0

## Distancia a la que se planta el coloso para el pisotón, en metros.
##
## No puede ser menos: con la huella de 21 × 27 m y patas de 15 m (`docs/07` §2),
## más cerca del edificio los pies delanteros se apoyan en el techo, el rig entra
## en modo trepada y `planted_legs` no vuelve a 4 —con lo que el modulador
## `planted_legs ≥ 3` de `docs/06` §10.2 deja el pisotón en cero para siempre.
const STOMP_STANDOFF: float = 30.0

## Distancia del dron al centro del edificio, en metros. Con el cilindro de
## r 9 m centrado en él, el barrido alcanza a los dos: al dron y a la fachada.
const STOMP_DRONE_OFFSET: float = 16.0

## Altura a la que se aparca el dron para el pisotón, en metros. Por debajo de
## los 12 m que `docs/06` §10.2 fija como techo del modulador de altura.
const STOMP_DRONE_HEIGHT: float = 4.0

## Deriva máxima del cuerpo con la locomoción bloqueada, en metros.
const LOCK_DRIFT: float = 0.5

## Extrapolación máxima admisible de la creencia sobre un objetivo quieto
## durante toda la memoria, en metros. No es cero: la velocidad creída es la
## derivada de una señal con ruido, así que pasea un poco.
const BELIEF_DRIFT_LIMIT: float = 25.0

## Ventana en la que se miden las cadencias, en segundos simulados.
const RATE_WINDOW: float = 8.0

## `windup` de la prueba negativa, en segundos.
const NEGATIVE_WINDUP: float = 0.30

## Segundos simulados que dura la prueba de `Global.debug_freeze_ai`.
const FREEZE_SECONDS: float = 2.0

## Movimiento máximo admisible con la IA congelada, en metros. No es cero
## exacto porque el cuerpo puede estar a mitad de un suavizado de altura cuando
## se levanta la bandera; es el orden del error de punto flotante.
const FREEZE_DRIFT: float = 0.01

## Impulso absurdo con el que se comprueba el recorte de `docs/06` §11.3.
const EXCESSIVE_IMPULSE: float = 500.0

## Tolerancia de las medidas de tiempo, en segundos: un tick de física a
## `TIME_SCALE`. El reloj del check es un acumulador de `delta` en coma flotante,
## así que una ventana de 0.80 s exactos sale medida como 0.79999995 y una
## comparación cruda contra el piso fallaría por un bit.
const TIME_EPSILON: float = 0.05

## Suelo del mundo sintético.
const GROUND_SIZE: Vector3 = Vector3(1600.0, 8.0, 1600.0)

## Huella y altura de los edificios de prueba, en metros.
const BUILDING_SIZE: Vector3 = Vector3(24.0, 14.0, 24.0)

## HP de los edificios de prueba. Alto a propósito: el rig les cobra
## `crush_damage` 900 por apoyo al trepar (`docs/06` §8.4) y un bloque normal de
## 1 200 HP se derrumbaría antes de que termine la caminata, cambiando el
## objetivo más valioso a mitad de la medición.
const BUILDING_HP: float = 400000.0

## Los seis edificios: nombre, posición en XZ y `value` (`docs/10` §4.2). El de
## 300 es el que `approach` tiene que elegir.
const BUILDINGS: Array[Dictionary] = [
	{"name": "Block_A", "at": Vector2(120.0, 90.0), "value": 100},
	{"name": "Block_B", "at": Vector2(-150.0, 60.0), "value": 120},
	{"name": "Block_C", "at": Vector2(150.0, -70.0), "value": 150},
	{"name": "Block_D", "at": Vector2(-60.0, 150.0), "value": 200},
	{"name": "Block_E", "at": Vector2(90.0, 150.0), "value": 250},
	{"name": "Tower_F", "at": Vector2(-40.0, -130.0), "value": 300},
]

## Centros de las campanas de las acciones sintéticas del selector, en metros.
##
## Son [b]nueve[/b], como las nueve acciones del Arachnodroid (`docs/07` §5). El
## tamaño del banco importa: con cinco acciones la curva decide sola y los tres
## histogramas salen iguales, porque la personalidad —±30 %— no alcanza a
## reordenar un `top_n` de 3 sobre cinco candidatos. Con nueve curvas que se
## solapan, quién entra en el `top_n` depende de verdad de la semilla, que es lo
## que `docs/06` §16.3 #1 quiere medir.
const SYNTHETIC_CENTERS: Array[float] = [
	14.0, 24.0, 34.0, 44.0, 54.0, 64.0, 74.0, 84.0, 94.0,
]

## Medio ancho de esas campanas, en metros. Es el ajuste fino de la prueba, y
## tiene dos paredes: por encima de 90 m la personalidad manda tanto que hay
## acciones que no entran nunca en el `top_n`, y `docs/06` §16.3 #2 exige conteo
## > 0 para todas; por debajo de 45 m manda la curva y la distancia L1 entre
## semillas cae de 0.15 (§16.3 #1). Medido con las semillas 1, 7 y 99: a 75 m
## quedan L1 ≥ 0.33 y ninguna acción muerta.
const SYNTHETIC_WIDTH: float = 75.0


## Dron de prueba: un [RigidBody3D] de la capa 2 con un casco por *duck typing*,
## que es todo lo que el marco de ataques necesita (`docs/09` §2).
##
## No se instancia `drone_rig.tscn` a propósito: ese árbol arrastra el HUD, la
## radio y el respawn, y lo que se prueba acá es la IA del enemigo, no el vuelo.
## Se mueve solo, con acumulador, para que la medición de σ con el dron en
## movimiento no dependa del ritmo del check.
class DroneStub extends RigidBody3D:
	## Modos de movimiento del dron de prueba.
	enum Mode { PARKED, ORBIT, FREE }

	## Casco: publica el contrato mínimo de `Hull` de `docs/09` §2.
	class HullStub extends Node:
		## Integridad restante.
		var hp: float = 100.0

		## Impactos recibidos.
		var hits: int = 0

		## Daño del último impacto y su origen.
		var last_amount: float = 0.0
		var last_source: Vector3 = Vector3.ZERO

		## Nombre canónico de `docs/09` §2: todo daño que no sea un choque
		## entra por acá. El alias `take_damage` existe allí pero no se usa.
		func apply_damage(amount: float, source_position: Vector3) -> void:
			hits += 1
			last_amount = amount
			last_source = source_position
			hp = maxf(hp - amount, 0.0)

	var mode: int = Mode.PARKED
	var anchor: Vector3 = Vector3.ZERO
	var orbit_centre: Vector3 = Vector3.ZERO
	var orbit_radius: float = 60.0
	var orbit_speed: float = 8.0
	var hull: HullStub = null

	var _angle: float = 0.0

	func _ready() -> void:
		collision_layer = PhysicsLayers.DRONE
		# Máscara 0: nada empuja al dron de prueba. Las consultas de ataque lo
		# encuentran por su **capa**, que es lo que importa acá.
		collision_mask = 0
		gravity_scale = 0.0
		freeze = false
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 0.4, 1.2)
		shape.shape = box
		add_child(shape)
		hull = HullStub.new()
		hull.name = "Hull"
		add_child(hull)

	func _physics_process(delta: float) -> void:
		match mode:
			Mode.PARKED:
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				global_position = anchor
			Mode.ORBIT:
				_angle += orbit_speed / maxf(orbit_radius, 0.01) * delta
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				global_position = orbit_centre + Vector3(
						cos(_angle) * orbit_radius, 0.0, sin(_angle) * orbit_radius)
			_:
				pass

	## Deja el dron quieto en [param point].
	func park(point: Vector3) -> void:
		mode = Mode.PARKED
		anchor = point
		global_position = point

	## Lo pone a orbitar [param centre] a [param speed] m/s.
	func orbit(centre: Vector3, radius: float, speed: float) -> void:
		mode = Mode.ORBIT
		orbit_centre = centre
		orbit_radius = radius
		orbit_speed = speed
		_angle = 0.0

	## Lo suelta para que un impulso se note en su velocidad.
	func release() -> void:
		mode = Mode.FREE


## Acción sintética del banco del selector (`docs/06` §10.2).
##
## Sólo existe para que la prueba del [UtilitySelector] no dependa de las dos
## acciones que WP-18 entrega: se necesitan cinco curvas distintas para que el
## histograma tenga algo que decir. La curva es una campana centrada en su
## distancia preferida, igual que la de `stomp` y `head_laser`.
class ScriptedAction extends EnemyAction:
	## Distancia preferida, en metros.
	var centre: float = 20.0

	## Medio ancho de la campana, en metros.
	var width: float = 40.0

	func score(ctx: Dictionary) -> float:
		return ActionScore.bell(float(ctx.get(&"distance", 1.0e6)), centre, width)


var _enemy: EnemyBase = null
var _perception: Perception = null
var _brain: EnemyFSM = null
var _library: AttackLibrary = null
var _telegraph: Telegraph = null
var _approach: EnemyAction = null
var _stomp: EnemyAction = null
var _parked: Dictionary[StringName, AttackProfile] = {}
var _drone: DroneStub = null
var _world: Node3D = null
var _blocker: StaticBody3D = null
var _buildings: Array[Building] = []
var _target_building: Building = null
var _synthetic: Array[EnemyAction] = []
var _synthetic_root: Node = null

var _seed_before: int = 0
var _freeze_before: bool = false
var _telegraph_events: Array[Dictionary] = []
var _action_log: Array[Dictionary] = []
var _sim_time: float = 0.0
var _histograms: Array[Dictionary] = []
var _summary: PackedStringArray = PackedStringArray()


func _run() -> void:
	_seed_before = Global.round_seed
	_freeze_before = Global.debug_freeze_ai
	Global.debug_freeze_ai = false
	Global.round_seed = SEEDS[0]
	_build_world()
	await wait_physics(2)
	if not _spawn_enemy():
		_restore()
		return
	await wait_physics(6)
	if not _check_wiring():
		_restore()
		return

	Engine.time_scale = TIME_SCALE
	print("  simulación: time_scale %.1f, delta de física %.4f s"
			% [Engine.time_scale, get_physics_process_delta_time()])

	await _check_perception()
	_check_utility()
	await _check_rates()
	await _check_approach()
	await _check_stomp()
	await _check_lock_and_interrupt()
	await _check_freeze()
	_check_windup_invariant()
	await _check_negative()
	await _check_downed()
	Engine.time_scale = 1.0
	await _check_cleanup()

	_print_summary()
	_restore()


# --------------------------------------------------------------------------
# Mundo sintético
# --------------------------------------------------------------------------

## Suelo llano, seis edificios de distinto valor y el dron de prueba.
func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	var _ground := _add_box("Ground", GROUND_SIZE, Vector3(0.0, -GROUND_SIZE.y * 0.5, 0.0),
			PhysicsLayers.WORLD)

	var source := ResourceLoader.load(BUILDING_PROFILE, "Resource") as BuildingProfile
	if source == null:
		fail("no se pudo cargar %s" % BUILDING_PROFILE)
		return
	for entry: Dictionary in BUILDINGS:
		var spot := entry["at"] as Vector2
		var building := _make_building(String(entry["name"]), source,
				Vector3(spot.x, 0.0, spot.y), int(entry["value"]))
		_buildings.append(building)
		if _target_building == null or building.value > _target_building.value:
			_target_building = building

	_drone = DroneStub.new()
	_drone.name = "DroneStub"
	_world.add_child(_drone)
	_drone.park(Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0.0))


## Un [Building] mínimo pero completo: perfil propio, malla de etapa intacta y
## caja de colisión en la capa 8. No se instancia una pieza de `city/pieces/`
## porque el pack sólo trae la malla importada: el `Building` lo arma [CityGrid]
## en runtime (`docs/10` §4), y acá se hace lo mismo con una caja.
func _make_building(node_name: String, source: BuildingProfile, at: Vector3,
		value: int) -> Building:
	var profile := source.duplicate() as BuildingProfile
	profile.value = value
	profile.max_hp = BUILDING_HP
	# Sin escombros: el check mide decisiones, no derrumbes, y `city_check` ya
	# cubre el pool.
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
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.32, 0.36)
	material.roughness = 0.9
	box_mesh.material = material
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


## Instancia el jefe en el origen, con el cerebro todavía apagado.
func _spawn_enemy() -> bool:
	var scene := ResourceLoader.load(ENEMY_SCENE, "PackedScene") as PackedScene
	if scene == null:
		fail("no se pudo cargar %s" % ENEMY_SCENE)
		return false
	_enemy = scene.instantiate() as EnemyBase
	if _enemy == null:
		fail("la escena del jefe no es un EnemyBase")
		return false
	add_child(_enemy)
	_enemy.global_position = Vector3.ZERO
	var _telegraphed := Events.enemy_attack_telegraphed.connect(_on_telegraphed)
	return true


## Comprueba que los cuatro nodos de WP-18 son los de verdad, no los placeholder.
func _check_wiring() -> bool:
	_perception = _enemy.perception as Perception
	_brain = _enemy.brain as EnemyFSM
	_library = _enemy.get_node_or_null(^"AttackLibrary") as AttackLibrary
	_telegraph = _enemy.get_node_or_null(^"Telegraph") as Telegraph
	if _perception == null:
		fail("el nodo Perception no es un Perception")
	if _brain == null:
		fail("el nodo Brain no es un EnemyFSM")
	if _library == null:
		fail("el nodo AttackLibrary no es un AttackLibrary")
	if _telegraph == null:
		fail("el nodo Telegraph no es un Telegraph")
	if _perception == null or _brain == null or _library == null or _telegraph == null:
		return false

	expect(_perception.profile != null,
			"Perception no recibió el PerceptionProfile del EnemyProfile")
	_approach = _library.find(&"approach")
	_stomp = _library.find(&"stomp")
	expect(_approach != null, "falta la acción 'approach' en AttackLibrary")
	expect(_stomp != null, "falta la acción 'stomp' en AttackLibrary")
	if _approach == null or _stomp == null:
		return false

	_brain.autonomous = false
	var _changed := _brain.action_changed.connect(_on_action_changed)
	expect(_brain.personality != null, "el cerebro no sorteó personalidad")
	if _brain.personality != null:
		print("  personalidad: %s" % _brain.personality.describe())
	expect(_telegraph.has_audio(),
			"el Telegraph no cargó assets/audio/enemies/charge.wav")
	return true


# --------------------------------------------------------------------------
# (a) Percepción (`docs/06` §9)
# --------------------------------------------------------------------------

func _check_perception() -> void:
	var profile := _perception.profile
	_drone.park(Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0.0))
	_perception.set_target(_drone)
	await _advance(1.0)
	expect(_perception.has_los, "no hay línea de visión con el dron a la vista")

	# a1: ruido con el dron quieto.
	var still := await _measure_sigma(NOISE_SAMPLES)
	var expected_still := profile.noise_base
	_expect_ratio(still, expected_still, SIGMA_TOLERANCE,
			"σ con el dron quieto")
	_summary.append("σ quieto %.3f m (esperado %.3f)" % [still, expected_still])

	# a2: ruido con el dron a ORBIT_SPEED m/s.
	_drone.orbit(Vector3(0.0, ORBIT_HEIGHT, 0.0), ORBIT_RADIUS, ORBIT_SPEED)
	await _advance(1.5)
	var moving := await _measure_sigma(NOISE_SAMPLES)
	var measured_speed := _perception.target_speed()
	var expected_moving := profile.noise_base + profile.noise_speed_factor * measured_speed
	_expect_ratio(moving, expected_moving, SIGMA_TOLERANCE,
			"σ con el dron a %.2f m/s" % measured_speed)
	_summary.append("σ a %.1f m/s %.3f m (esperado %.3f)"
			% [measured_speed, moving, expected_moving])

	# a3: se interpone un bloque de capa 1 entre la cabeza y el dron.
	# Aparcar al dron lo teletransporta desde donde lo dejó la órbita, así que se
	# vuelve a fijar el objetivo: `set_target` resincroniza la creencia y pone la
	# velocidad creída a cero, que es lo que hace medible la extrapolación.
	_drone.park(Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0.0))
	_perception.set_target(_drone)
	await _advance(2.0)
	expect(_perception.has_los, "la línea de visión no volvió tras aparcar el dron")
	var lost := await _occlude()
	expect(lost <= LOS_SWITCH_LIMIT,
			"la LOS tardó %.3f s en perderse (tope %.2f s)" % [lost, LOS_SWITCH_LIMIT])
	_summary.append("LOS perdida en %.3f s" % lost)

	# a4 y a5: la creencia extrapola y la confianza cae en `memory_seconds`.
	var belief_at_loss := _perception.believed_position
	_drone.park(Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 140.0))
	var decay := await _measure_decay(profile.memory_seconds * 2.5)
	var drift := _perception.believed_position.distance_to(_drone.global_position)
	expect(drift > 20.0,
			"la creencia siguió al dron sin verlo: error %.1f m" % drift)
	var extrapolated := belief_at_loss.distance_to(_perception.believed_position)
	expect(extrapolated < BELIEF_DRIFT_LIMIT,
			"la creencia extrapoló %.1f m con el objetivo quieto (tope %.0f m)"
			% [extrapolated, BELIEF_DRIFT_LIMIT])
	_expect_ratio(decay, profile.memory_seconds, MEMORY_TOLERANCE,
			"memoria antes de perder la confianza")
	_summary.append("memoria %.2f s (esperado %.2f) · error de creencia %.1f m"
			% [decay, profile.memory_seconds, drift])

	# a6: el patrón de búsqueda se regenera.
	var first_point := _perception.search_point()
	await _advance(profile.search_refresh + 0.4)
	var second_point := _perception.search_point()
	expect(first_point.distance_to(second_point) > 0.5,
			"search_point() no cambió tras %.1f s de búsqueda" % profile.search_refresh)

	# a7: se quita el bloque y la visión vuelve.
	_drone.park(Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0.0))
	await _advance(0.2)
	var regained := await _reveal()
	expect(regained <= LOS_SWITCH_LIMIT,
			"la LOS tardó %.3f s en recuperarse (tope %.2f s)" % [regained, LOS_SWITCH_LIMIT])
	_summary.append("LOS recuperada en %.3f s" % regained)

	# a8: cegado. σ ×5 y memoria recortada a `blind_memory_seconds`.
	_perception.blind(60.0)
	await _advance(0.5)
	var blind_sigma := await _measure_sigma(NOISE_SAMPLES)
	var expected_blind := profile.noise_base * profile.blind_noise_multiplier
	_expect_ratio(blind_sigma, expected_blind, SIGMA_TOLERANCE, "σ con el visor roto")
	expect_near(_perception.memory_window(), profile.blind_memory_seconds, 0.001,
			"memoria efectiva mientras dura la ceguera")
	var blind_lost := await _occlude()
	expect(blind_lost <= LOS_SWITCH_LIMIT,
			"con el visor roto la LOS tardó %.3f s en perderse" % blind_lost)
	var blind_decay := await _measure_decay(profile.blind_memory_seconds * 3.0)
	_expect_ratio(blind_decay, profile.blind_memory_seconds, MEMORY_TOLERANCE,
			"memoria con el visor roto")
	_summary.append("cegado: σ %.3f m (esperado %.3f) · memoria %.2f s (esperado %.2f)"
			% [blind_sigma, expected_blind, blind_decay, profile.blind_memory_seconds])

	_perception.restore_sight()
	var _back := await _reveal()
	_drone.park(Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0.0))
	await _advance(1.0)
	expect(_perception.has_los, "la percepción no volvió a la nominal tras la ceguera")
	expect_near(_perception.noise_sigma(), profile.noise_base, 0.001,
			"σ nominal restituida por el sensor de respaldo")


## Desviación típica del ruido sobre [param count] muestras de percepción, con
## los tres ejes agrupados.
func _measure_sigma(count: int) -> float:
	var values: PackedFloat32Array = PackedFloat32Array()
	var seen := _perception.tick_count()
	var guard := 0.0
	while values.size() < count * 3 and guard < float(count) * 0.5:
		await get_tree().physics_frame
		guard += get_physics_process_delta_time()
		var now := _perception.tick_count()
		if now == seen:
			continue
		seen = now
		var noise := _perception.last_noise()
		values.append(noise.x)
		values.append(noise.y)
		values.append(noise.z)
	if values.size() < 3:
		fail("no se pudieron medir muestras de ruido")
		return 0.0
	var mean := 0.0
	for value: float in values:
		mean += value
	mean /= float(values.size())
	var variance := 0.0
	for value: float in values:
		variance += (value - mean) * (value - mean)
	return sqrt(variance / float(values.size()))


## Interpone un bloque de capa 1 en mitad del rayo cabeza → dron y devuelve los
## segundos simulados que tarda la línea de visión en caerse.
func _occlude() -> float:
	if _blocker != null:
		_blocker.queue_free()
		_blocker = null
	var head := _perception.head_node()
	var from := head.global_position if head != null else _enemy.global_position
	var midpoint := from.lerp(_drone.global_position, 0.5)
	_blocker = _add_box("Blocker", Vector3(40.0, 40.0, 40.0), midpoint, PhysicsLayers.WORLD)
	return await _wait_for_los(false)


## Quita el bloque y devuelve los segundos que tarda la visión en volver.
func _reveal() -> float:
	if _blocker != null:
		_blocker.queue_free()
		_blocker = null
	return await _wait_for_los(true)


## Segundos simulados hasta que `has_los` valga [param wanted].
func _wait_for_los(wanted: bool) -> float:
	var elapsed := 0.0
	while _perception.has_los != wanted and elapsed < 2.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return elapsed


## Segundos simulados hasta que la confianza llegue a 0, contados desde la
## última muestra con visión.
func _measure_decay(limit: float) -> float:
	var elapsed := 0.0
	while _perception.confidence > 0.0 and elapsed < limit:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	# `time_since_los` es el reloj real de la memoria: se reinicia en la muestra
	# con visión, no en el frame en el que el check se puso a mirar.
	return _perception.time_since_los()


# --------------------------------------------------------------------------
# (b) Selector de utilidad (`docs/06` §10 y §16.3 #1, #2)
# --------------------------------------------------------------------------

func _check_utility() -> void:
	_build_synthetic_actions()
	_histograms.clear()
	var sequences: Array[PackedStringArray] = []
	for seed_value: int in SEEDS:
		var run := _run_selector(seed_value)
		sequences.append(run["sequence"] as PackedStringArray)
		_histograms.append(run["histogram"] as Dictionary)

	# b2: la misma semilla reproduce exactamente la misma secuencia.
	var repeat := _run_selector(SEEDS[0])
	expect((repeat["sequence"] as PackedStringArray) == sequences[0],
			"la semilla %d no reprodujo la misma secuencia de acciones" % SEEDS[0])

	# b1: las tres semillas dan histogramas distintos.
	for a: int in SEEDS.size():
		for b: int in range(a + 1, SEEDS.size()):
			var l1 := _histogram_l1(_histograms[a], _histograms[b])
			expect(l1 >= MIN_HISTOGRAM_L1,
					"semillas %d y %d: distancia L1 %.3f, mínimo %.2f"
					% [SEEDS[a], SEEDS[b], l1, MIN_HISTOGRAM_L1])
			_summary.append("L1(%d, %d) = %.3f" % [SEEDS[a], SEEDS[b], l1])

	# b4: ninguna acción monopoliza ni queda muerta.
	for index: int in _histograms.size():
		var histogram := _histograms[index]
		for action: EnemyAction in _synthetic:
			var share := float(histogram.get(action.id(), 0.0))
			expect(share > 0.0,
					"semilla %d: la acción '%s' nunca se eligió" % [SEEDS[index], action.id()])
			expect(share <= MAX_ACTION_SHARE,
					"semilla %d: la acción '%s' se llevó el %.1f %% (tope %.0f %%)"
					% [SEEDS[index], action.id(), share * 100.0, MAX_ACTION_SHARE * 100.0])
		print("  histograma semilla %d: %s" % [SEEDS[index], _format_histogram(histogram)])


## Cinco acciones sintéticas con campanas a distinta distancia, una con alcance
## corto y otra con enfriamiento, para ejercitar los dos descartes de
## `docs/06` §10 punto 2.
func _build_synthetic_actions() -> void:
	_synthetic_root = Node.new()
	_synthetic_root.name = "SyntheticActions"
	add_child(_synthetic_root)
	for index: int in SYNTHETIC_CENTERS.size():
		var profile := AttackProfile.new()
		profile.attack_id = StringName("synthetic_%d" % index)
		profile.windup = 0.9
		profile.active = 0.3
		profile.recover = 0.4
		# Una con enfriamiento largo y otra con alcance corto: son los dos
		# descartes de `docs/06` §10 punto 2 que la prueba tiene que ejercitar.
		profile.cooldown = 3.0 if index == 1 else 0.5
		profile.min_range = 0.0
		profile.max_range = 70.0 if index == 0 else 200.0
		profile.base_weight = 1.0

		var action := ScriptedAction.new()
		action.name = "Synthetic%d" % index
		action.profile = profile
		action.centre = SYNTHETIC_CENTERS[index]
		action.width = SYNTHETIC_WIDTH
		_synthetic_root.add_child(action)
		_synthetic.append(action)


## Corre [constant DECISIONS_PER_SEED] decisiones con [param seed_value] y
## devuelve la secuencia elegida y el histograma normalizado.
##
## El reloj de las acciones se avanza a mano, un paso de decisión por vuelta: el
## bucle no espera frames, así que la prueba es puramente determinista y no
## depende del ritmo de la física.
func _run_selector(seed_value: int) -> Dictionary:
	Global.round_seed = seed_value
	var ids := PackedStringArray()
	for action: EnemyAction in _synthetic:
		action.reset_action()
		ids.append(String(action.id()))
	var personality := Personality.from_seed(seed_value, ids, Personality.DEFAULT_SPREAD)
	var selector := UtilitySelector.new()
	selector.configure(seed_value)

	var sequence := PackedStringArray()
	var counts: Dictionary[StringName, int] = {}
	for step: int in DECISIONS_PER_SEED:
		for action: EnemyAction in _synthetic:
			action._physics_process(DECISION_STEP)
		# Barrido determinista de la distancia: recorre toda la banda útil, así
		# las cinco campanas llegan a dominar en algún momento.
		var distance := 52.0 + 46.0 * sin(float(step) * 0.11)
		var ctx: Dictionary = {&"distance": distance}
		var chosen := selector.select(_synthetic, ctx, personality, UtilitySelector.DEFAULT_TOP_N)
		if chosen == null:
			continue
		_expect_choice_valid(chosen, selector, distance)
		chosen.finish()
		sequence.append(String(chosen.id()))
		counts[chosen.id()] = int(counts.get(chosen.id(), 0)) + 1

	var histogram: Dictionary[StringName, float] = {}
	var total := maxi(sequence.size(), 1)
	for attack_id: StringName in counts:
		histogram[attack_id] = float(counts[attack_id]) / float(total)
	return {"sequence": sequence, "histogram": histogram}


## b3: la elegida tenía score positivo, estaba dentro de rango y sin enfriar.
func _expect_choice_valid(chosen: EnemyAction, selector: UtilitySelector,
		distance: float) -> void:
	var scores := selector.last_scores()
	var score := float(scores.get(chosen.id(), -1.0))
	if score <= 0.0:
		fail("se eligió '%s' con score %.3f" % [chosen.id(), score])
	if chosen.cooldown_remaining() > 0.0:
		fail("se eligió '%s' con %.2f s de enfriamiento pendiente"
				% [chosen.id(), chosen.cooldown_remaining()])
	if distance > chosen.profile.max_range or distance < chosen.profile.min_range:
		fail("se eligió '%s' a %.1f m, fuera de [%.1f, %.1f]"
				% [chosen.id(), distance, chosen.profile.min_range, chosen.profile.max_range])


## Distancia L1 entre dos histogramas normalizados.
func _histogram_l1(a: Dictionary, b: Dictionary) -> float:
	var keys: Dictionary[StringName, bool] = {}
	for key: StringName in a:
		keys[key] = true
	for key: StringName in b:
		keys[key] = true
	var total := 0.0
	for key: StringName in keys:
		total += absf(float(a.get(key, 0.0)) - float(b.get(key, 0.0)))
	return total


## Histograma en una línea legible.
func _format_histogram(histogram: Dictionary) -> String:
	var parts := PackedStringArray()
	var ids := PackedStringArray()
	for key: StringName in histogram:
		ids.append(String(key))
	ids.sort()
	for key: String in ids:
		parts.append("%s %.1f %%" % [key, float(histogram[StringName(key)]) * 100.0])
	return ", ".join(parts)


# --------------------------------------------------------------------------
# (e) Cadencias (`docs/06` §9 y §10)
# --------------------------------------------------------------------------

func _check_rates() -> void:
	Global.round_seed = SEEDS[0]
	_brain.rebuild()
	_brain.autonomous = true
	_perception.set_target(_drone)
	_drone.park(Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0.0))
	await _advance(0.5)

	var perception_before := _perception.tick_count()
	var decision_before := _brain.decision_ticks()
	var elapsed := await _advance(RATE_WINDOW)
	var perception_rate := float(_perception.tick_count() - perception_before) / elapsed
	var decision_rate := float(_brain.decision_ticks() - decision_before) / elapsed

	var perception_hz := _perception.profile.hz
	var decision_hz := _enemy.profile.decision_hz
	expect(absf(perception_rate - perception_hz) <= 1.0 / elapsed + 0.2,
			"percepción a %.2f Hz, esperada %.1f Hz" % [perception_rate, perception_hz])
	expect(absf(decision_rate - decision_hz) <= 1.0 / elapsed + 0.2,
			"decisión a %.2f Hz, esperada %.1f Hz" % [decision_rate, decision_hz])
	_summary.append("cadencias: percepción %.2f Hz · decisión %.2f Hz en %.1f s simulados"
			% [perception_rate, decision_rate, elapsed])


# --------------------------------------------------------------------------
# (d) `approach` y `stomp`
# --------------------------------------------------------------------------

## El coloso tiene que llegar al edificio más valioso caminando solo.
func _check_approach() -> void:
	# Sin objetivo de dron `approach` apunta a la ciudad; los otros ocho ataques
	# se apartan para que la caminata quede aislada.
	_park_all_but(PackedStringArray(["approach"]))
	_perception.set_target(null)
	_enemy.global_position = Vector3.ZERO
	var rig := _enemy.locomotion as ProceduralLegRig
	if rig != null:
		rig.snap_to_ground()
	await _advance(0.5)

	var goal := _target_building.global_position
	var start := _enemy.global_position.distance_to(goal)
	var elapsed := 0.0
	var best := start
	while elapsed < APPROACH_BUDGET:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var distance := _flat_distance(_enemy.global_position, goal)
		best = minf(best, distance)
		if distance < APPROACH_GOAL:
			break
	expect(best < APPROACH_GOAL,
			"'approach' quedó a %.1f m del edificio de valor %d en %.1f s (tope %.0f m)"
			% [best, _target_building.value, elapsed, APPROACH_GOAL])
	expect(_approach.use_count() > 0, "la acción 'approach' no se ejecutó nunca")
	_summary.append("approach: %.0f m → %.1f m del edificio de valor %d en %.1f s (%d tramos)"
			% [start, best, _target_building.value, elapsed, _approach.use_count()])


## El pisotón tiene que telegrafiar, dañar el edificio y dañar el dron.
func _check_stomp() -> void:
	var goal := _target_building.global_position
	# Se recoloca al coloso en llano, a `STOMP_STANDOFF` del edificio, y se
	# apartan las otras ocho acciones: si siguiera caminando acabaría con los
	# pies en el techo, y si telegrafiara un asedio de 7.3 s el pisotón no
	# llegaría a elegirse dentro del presupuesto.
	_park_all_but(PackedStringArray(["stomp"]))
	var away := Vector3(1.0, 0.0, 0.0)
	_enemy.global_position = goal + away * STOMP_STANDOFF
	var rig := _enemy.locomotion as ProceduralLegRig
	if rig != null:
		rig.snap_to_ground()
	var anchor := goal + away * STOMP_DRONE_OFFSET
	anchor.y = STOMP_DRONE_HEIGHT
	_drone.park(anchor)
	_perception.set_target(_drone)
	await _advance(1.5)
	# La línea base no se puede tomar con un ciclo a medio camino: el pisotón que
	# ya estuviera telegrafiando descargaría sus 45 dentro de la ventana de
	# medición —y dejaría en el log un `ACTIVE` sin su `TELEGRAPH`—, con lo que el
	# casco bajaría dos veces y el criterio mediría el doble.
	var idle := 0.0
	while _brain.action_state() != EnemyFSM.ACTION_NONE and idle < 8.0:
		await get_tree().physics_frame
		idle += get_physics_process_delta_time()
	_stomp.reset_action()
	_telegraph_events.clear()
	_action_log.clear()
	var hull_before := _drone.hull.hp
	var building_before := _target_building.hp
	var uses_before := _stomp.use_count()

	var elapsed := 0.0
	var reported := 0.0
	while elapsed < STOMP_BUDGET and _stomp.use_count() == uses_before:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if elapsed - reported >= 4.0:
			reported = elapsed
			_report_decision()
	expect(_stomp.use_count() > uses_before,
			"'stomp' no se eligió en %.1f s simulados" % STOMP_BUDGET)
	if _stomp.use_count() == uses_before:
		_report_decision()
		return

	# Se deja terminar el ciclo completo: telegrafía, activo y recuperación.
	await _advance(_stomp.telegraph_seconds() + _stomp.active_seconds()
			+ _stomp.recover_seconds() + 0.5)

	_check_telegraph_precedes_damage()
	expect(_drone.hull.hp < hull_before,
			"el pisotón no dañó al dron (casco %.1f)" % _drone.hull.hp)
	expect_near(hull_before - _drone.hull.hp, _stomp.profile.damage_drone, 0.01,
			"daño al casco del dron")
	expect(_target_building.hp < building_before,
			"el pisotón no dañó al edificio (hp %.0f)" % _target_building.hp)
	_summary.append("stomp: casco %.1f → %.1f · edificio %.0f → %.0f · impactos %s"
			% [hull_before, _drone.hull.hp, building_before, _target_building.hp,
			str((_stomp as SweepAction).last_hits())])
	await _check_impulse_clamp(anchor)


## El impulso al dron sale recortado a [constant EnemyAction.MAX_IMPULSE]
## (`docs/06` §11.3). Se pide un impulso absurdo —500 N·s— y se mide la
## velocidad que gana el cuerpo: sin el recorte sería más de cuatro veces mayor.
##
## La acción se conduce a mano, con el cerebro apagado, para que la medida no
## dependa de que el selector vuelva a elegir el pisotón.
func _check_impulse_clamp(anchor: Vector3) -> void:
	_brain.autonomous = false
	var original := _stomp.profile
	var patched := original.duplicate() as AttackProfile
	patched.impulse_drone = EXCESSIVE_IMPULSE
	patched.damage_drone = 0.0
	patched.damage_building = 0.0
	_stomp.profile = patched

	_drone.release()
	_drone.linear_velocity = Vector3.ZERO
	await wait_physics(1)
	_stomp.begin_telegraph()
	_stomp.begin_active()
	await wait_physics(3)
	var gained := _drone.linear_velocity.length()
	var limit := EnemyAction.MAX_IMPULSE / maxf(_drone.mass, 0.001)
	expect(gained > 0.0, "el impulso del pisotón no llegó al dron")
	expect(gained <= limit * 1.05,
			"el dron ganó %.1f m/s con un impulso de %.0f N·s: el recorte a %.0f N·s no se aplicó"
			% [gained, EXCESSIVE_IMPULSE, EnemyAction.MAX_IMPULSE])
	_summary.append("clamp de impulso: %.0f N·s pedidos → %.1f m/s (tope %.1f m/s)"
			% [EXCESSIVE_IMPULSE, gained, limit])

	_stomp.end_active()
	# `finish()` cierra el ciclo a mano: sin él la pata que el aviso levantó se
	# quedaría en el aire el resto del check y `planted_count()` nunca volvería
	# a 4.
	_stomp.finish()
	_stomp.profile = original
	_stomp.reset_action()
	_drone.park(anchor)
	_brain.autonomous = true
	await wait_physics(2)


## Vuelca el contexto y las puntuaciones de la última decisión. Es el
## diagnóstico que hace legible un fallo de selección.
func _report_decision() -> void:
	var ctx := _brain.last_context()
	print("    ctx: d=%.1f m · d_city=%.1f m · conf=%.2f · los=%s · altura=%.1f m"
			% [float(ctx.get(&"distance", -1.0)), float(ctx.get(&"city_distance", -1.0)),
			float(ctx.get(&"confidence", -1.0)), str(ctx.get(&"has_los", false)),
			float(ctx.get(&"drone_height", -1.0))])
	print("    ctx: patas=%d · fase=%s · estado=%s · sesgo=%.2f"
			% [int(ctx.get(&"planted_legs", -1)), str(ctx.get(&"phase", &"")),
			_brain.action_state(), float(ctx.get(&"city_bias", -1.0))])
	print("    scores: %s · descartes: %s"
			% [str(_brain.selector.last_scores()), str(_brain.selector.last_rejections())])


## c1: toda entrada en `ACTIVE` de una acción dañina estuvo precedida de al menos
## 0.80 s en `TELEGRAPH`, y el aviso se publicó por el bus.
func _check_telegraph_precedes_damage() -> void:
	expect(not _telegraph_events.is_empty(),
			"no se publicó ningún Events.enemy_attack_telegraphed")
	for event: Dictionary in _telegraph_events:
		expect(float(event["duration"]) >= EnemyAction.MIN_WINDUP,
				"telegrafía de '%s' anunciada en %.3f s (mínimo %.2f s)"
				% [event["attack_id"], event["duration"], EnemyAction.MIN_WINDUP])

	var telegraph_start := -1.0
	var checked := 0
	for entry: Dictionary in _action_log:
		var state := entry["to"] as StringName
		if state == EnemyFSM.ACTION_TELEGRAPH:
			telegraph_start = float(entry["time"])
		elif state == EnemyFSM.ACTION_ACTIVE:
			expect(telegraph_start >= 0.0,
					"se entró en ACTIVE sin haber pasado por TELEGRAPH")
			if telegraph_start < 0.0:
				continue
			var window := float(entry["time"]) - telegraph_start
			expect(window >= EnemyAction.MIN_WINDUP,
					"TELEGRAPH duró %.3f s antes de ACTIVE (mínimo %.2f s)"
					% [window, EnemyAction.MIN_WINDUP])
			checked += 1
			_summary.append("telegrafía medida %.3f s antes de ACTIVE" % window)
			telegraph_start = -1.0
	expect(checked > 0, "no se midió ninguna ventana TELEGRAPH → ACTIVE")


# --------------------------------------------------------------------------
# (c) Bloqueo de locomoción e interrupciones (`docs/06` §11.1)
# --------------------------------------------------------------------------

func _check_lock_and_interrupt() -> void:
	var entered := await _wait_for_action_state(EnemyFSM.ACTION_TELEGRAPH, STOMP_BUDGET)
	expect(entered, "no se llegó a TELEGRAPH para medir el bloqueo de locomoción")
	if not entered:
		return

	# c2: con `lock_locomotion` el cuerpo no avanza.
	expect(_enemy.is_locomotion_locked(),
			"la locomoción no quedó bloqueada durante TELEGRAPH de '%s'"
			% _brain.current_action().id())
	var origin := _enemy.global_position
	await _advance(_stomp.telegraph_seconds() * 0.7)
	var drift := _flat_distance(_enemy.global_position, origin)
	expect(drift < LOCK_DRIFT,
			"el cuerpo derivó %.2f m con la locomoción bloqueada (tope %.2f m)"
			% [drift, LOCK_DRIFT])
	_summary.append("lock_locomotion: deriva %.3f m durante el aviso" % drift)

	# c3: `stagger()` corta la acción y devuelve la capa a NONE.
	_enemy.stagger(1.0)
	await wait_physics(2)
	expect(_brain.action_state() == EnemyFSM.ACTION_NONE,
			"tras stagger() la capa de acción quedó en '%s'" % _brain.action_state())
	expect(_brain.current_action() == null, "tras stagger() quedó una acción en curso")
	expect(_stomp.cooldown_remaining() > 0.0,
			"la acción cancelada no arrancó su enfriamiento (`docs/06` §7 punto 6)")
	_summary.append("stagger: acción cancelada con %.2f s de enfriamiento"
			% _stomp.cooldown_remaining())
	await _advance(1.2)


## Deja en el selector sólo las acciones de [param keep] y aparta el resto
## recortándoles el alcance a cero.
##
## Es una manipulación explícita del check, no una capacidad del marco: con las
## nueve acciones del jefe compitiendo por cada turno, medir una sola —cuánto
## camina `approach`, qué daño hace `stomp`— dependería de la semilla. El marco
## no tiene —ni debe tener— un interruptor para esto.
func _park_all_but(keep: PackedStringArray) -> void:
	for action: EnemyAction in _library.get_actions():
		if keep.has(String(action.id())):
			_unpark(action)
		else:
			_park(action)


## Aparta una acción guardando su perfil original.
func _park(action: EnemyAction) -> void:
	var attack_id := action.id()
	if _parked.has(attack_id) or action.profile == null:
		return
	_parked[attack_id] = action.profile
	var patched := action.profile.duplicate() as AttackProfile
	patched.min_range = 0.0
	patched.max_range = 0.0
	action.profile = patched


## Devuelve una acción apartada al selector.
func _unpark(action: EnemyAction) -> void:
	var attack_id := action.id()
	if not _parked.has(attack_id):
		return
	action.profile = _parked[attack_id]
	var _erased := _parked.erase(attack_id)


## Devuelve al selector todo lo que se hubiera apartado.
func _unpark_all() -> void:
	for attack_id: StringName in _parked.keys():
		var action := _library.find(attack_id)
		if action != null:
			action.profile = _parked[attack_id]
	_parked.clear()


## Espera hasta [param limit] segundos simulados a que la capa de acción entre en
## [param state].
func _wait_for_action_state(state: StringName, limit: float) -> bool:
	var elapsed := 0.0
	while elapsed < limit:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if _brain.action_state() == state:
			return true
	return false


# --------------------------------------------------------------------------
# (g) `Global.debug_freeze_ai` (`docs/11` §11)
# --------------------------------------------------------------------------

## Con la bandera puesta, el enemigo no piensa, no percibe y no se mueve; al
## soltarla retoma sin estado corrupto.
##
## Es la garantía que `round_check` y `combat_hud_check` necesitan para inyectar
## hechos por el bus con el jefe instanciado y quieto.
func _check_freeze() -> void:
	# Con el dron a la vista y el cerebro suelto, el jefe tiene de sobra qué
	# hacer: si la bandera no funcionara, se movería o telegrafiaría.
	_perception.set_target(_drone)
	_brain.autonomous = true
	await _advance(0.5)

	Global.debug_freeze_ai = true
	await wait_physics(2)
	var origin := _enemy.global_transform
	var action := _brain.action_state()
	var decisions := _brain.decision_ticks()
	var samples := _perception.tick_count()

	await _advance(FREEZE_SECONDS)
	var drift := origin.origin.distance_to(_enemy.global_position)
	expect(drift <= FREEZE_DRIFT,
			"con debug_freeze_ai el jefe se movió %.4f m en %.1f s" % [drift, FREEZE_SECONDS])
	expect(_brain.action_state() == action,
			"con debug_freeze_ai la capa de acción pasó de '%s' a '%s'"
			% [action, _brain.action_state()])
	expect(_brain.decision_ticks() == decisions,
			"con debug_freeze_ai el cerebro dio %d ticks de decisión"
			% (_brain.decision_ticks() - decisions))
	expect(_perception.tick_count() == samples,
			"con debug_freeze_ai la percepción tomó %d muestras"
			% (_perception.tick_count() - samples))

	Global.debug_freeze_ai = false
	await _advance(1.5)
	expect(_perception.tick_count() > samples,
			"al soltar debug_freeze_ai la percepción no volvió a muestrear")
	expect(_brain.decision_ticks() > decisions,
			"al soltar debug_freeze_ai el cerebro no volvió a decidir")
	expect(_perception.target_speed() < 5.0,
			"al descongelar, la percepción se inventó %.1f m/s de velocidad del dron"
			% _perception.target_speed())
	_summary.append("debug_freeze_ai: %.1f s sin muestras, sin decisiones y con %.4f m de deriva"
			% [FREEZE_SECONDS, drift])


# --------------------------------------------------------------------------
# (c4) `DOWNED` bloquea las decisiones (`docs/06` §8.7 y §11.1)
# --------------------------------------------------------------------------

func _check_downed() -> void:
	for side: String in ["fl", "fr", "bl", "br"]:
		_break_part(StringName("wp_leg_%s_knee" % side))
	await _advance(1.5)
	expect(_enemy.is_downed(), "romper las 4 rodillas no dejó al jefe en DOWNED")
	expect(_enemy.locomotion_state() == &"DOWNED",
			"la capa de locomoción reporta '%s', esperada DOWNED" % _enemy.locomotion_state())
	expect(_brain.action_state() == EnemyFSM.ACTION_NONE,
			"caído, la capa de acción quedó en '%s'" % _brain.action_state())

	var decisions_before := _brain.decision_count()
	var ticks_before := _brain.decision_ticks()
	await _advance(3.0)
	expect(_brain.decision_count() == decisions_before,
			"caído, el cerebro consultó al selector %d veces"
			% (_brain.decision_count() - decisions_before))
	expect(_brain.decision_ticks() > ticks_before,
			"el reloj de decisión se detuvo con el jefe caído")
	_summary.append("DOWNED: %d ticks de decisión sin ninguna consulta al selector"
			% (_brain.decision_ticks() - ticks_before))


## Rompe la parte [param part_id] como lo haría el arma (`docs/08` §2.7).
func _break_part(part_id: StringName) -> void:
	var part := _enemy.get_part(part_id)
	if part == null or part.is_broken():
		return
	var _effective := part.take_damage(part.hp / maxf(1.0 - part.armor, 0.01), {
		"position": part.world_position(),
		"normal": Vector3.UP,
		"direction": Vector3.FORWARD,
		"source": self,
		"is_weak_point": true,
		"weak_point_id": part_id,
		"damage_type": &"kinetic",
	})


# --------------------------------------------------------------------------
# Invariante del windup y prueba negativa (`docs/06` §6.1 y §16.3 #3)
# --------------------------------------------------------------------------

## El windup efectivo de toda acción, en toda fase, se queda en 0.80 s o más.
func _check_windup_invariant() -> void:
	var worst := 1.0e6
	var worst_label := ""
	for action: EnemyAction in _library.get_actions():
		if action.profile == null or not action.is_damaging():
			continue
		for phase: Dictionary in _enemy.profile.phases:
			var effects := phase.get("then", {}) as Dictionary
			var multipliers := effects.get("multipliers", {}) as Dictionary
			var multiplier := float(multipliers.get("windup",
					multipliers.get(&"windup", 1.0)))
			var effective := maxf(EnemyAction.MIN_WINDUP, action.profile.windup * multiplier)
			expect(effective >= EnemyAction.MIN_WINDUP,
					"'%s' en la fase '%s': windup efectivo %.3f s"
					% [action.id(), phase.get("id", &""), effective])
			if effective < worst:
				worst = effective
				worst_label = "%s/%s" % [action.id(), phase.get("id", &"")]
	if worst < 1.0e6:
		_summary.append("windup efectivo mínimo %.3f s en %s" % [worst, worst_label])


## Prueba negativa: con `windup` forzado a 0.30 s —por debajo del mínimo— el
## marco tiene que levantarlo a 0.80 s, en la API y en el reloj de la FSM.
func _check_negative() -> void:
	var original := _stomp.profile
	var patched := original.duplicate() as AttackProfile
	patched.windup = NEGATIVE_WINDUP
	_stomp.profile = patched

	expect(_stomp.raw_windup() < EnemyAction.MIN_WINDUP,
			"la prueba negativa no llegó a pedir un windup por debajo del mínimo")
	expect_near(_stomp.effective_windup(), EnemyAction.MIN_WINDUP, 0.001,
			"effective_windup() con windup forzado a %.2f s" % NEGATIVE_WINDUP)
	expect_near(_stomp.telegraph_seconds(), EnemyAction.MIN_WINDUP, 0.001,
			"telegraph_seconds() con windup forzado a %.2f s" % NEGATIVE_WINDUP)
	_summary.append("prueba negativa: windup %.2f s crudo → %.2f s efectivos"
			% [NEGATIVE_WINDUP, _stomp.effective_windup()])

	# Y el reloj real: se deja que la FSM elija el pisotón con el `windup`
	# saboteado y se mide la ventana `TELEGRAPH` → `ACTIVE` de verdad. Si el
	# mínimo viviera sólo en la API y no en la máquina, acá saldría 0.30 s.
	_stomp.reset_action()
	_telegraph_events.clear()
	_action_log.clear()
	var uses_before := _stomp.use_count()
	var elapsed := 0.0
	while elapsed < STOMP_BUDGET and _stomp.use_count() == uses_before:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	expect(_stomp.use_count() > uses_before,
			"el pisotón saboteado no se eligió en %.1f s simulados" % STOMP_BUDGET)
	await _advance(EnemyAction.MIN_WINDUP + _stomp.active_seconds() + 0.5)

	var measured := _measure_telegraph_window()
	expect(measured >= EnemyAction.MIN_WINDUP - TIME_EPSILON,
			"con windup %.2f s la FSM pasó %.3f s en TELEGRAPH (mínimo %.2f s)"
			% [NEGATIVE_WINDUP, measured, EnemyAction.MIN_WINDUP])
	for event: Dictionary in _telegraph_events:
		expect(float(event["duration"]) >= EnemyAction.MIN_WINDUP,
				"el aviso saboteado se anunció en %.3f s" % float(event["duration"]))
	_summary.append("prueba negativa: la FSM pasó %.3f s en TELEGRAPH pese al 0.30 s pedido"
			% measured)

	_stomp.profile = original
	_unpark_all()


## Mayor ventana `TELEGRAPH` → `ACTIVE` registrada en el log de la capa de
## acción, o −1.0 si no hubo ninguna.
func _measure_telegraph_window() -> float:
	var start := -1.0
	var best := -1.0
	for entry: Dictionary in _action_log:
		var state := entry["to"] as StringName
		if state == EnemyFSM.ACTION_TELEGRAPH:
			start = float(entry["time"])
		elif state == EnemyFSM.ACTION_ACTIVE and start >= 0.0:
			best = maxf(best, float(entry["time"]) - start)
			start = -1.0
	return best


# --------------------------------------------------------------------------
# (f) Limpieza
# --------------------------------------------------------------------------

func _check_cleanup() -> void:
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_enemy.queue_free()
	_enemy = null
	await wait_frames(4)
	await wait_physics(2)
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	expect(orphans_after <= orphans_before,
			"quedaron %d nodos huérfanos tras liberar al jefe" % (orphans_after - orphans_before))
	expect(get_tree().get_nodes_in_group(EnemyBase.GROUP).is_empty(),
			"el grupo '%s' no quedó vacío" % EnemyBase.GROUP)
	_summary.append("limpieza: %d → %d nodos huérfanos" % [orphans_before, orphans_after])


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Avanza [param seconds] simulados y devuelve lo que avanzó de verdad.
func _advance(seconds: float) -> float:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return elapsed


## Distancia horizontal entre dos puntos.
func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Falla si [param measured] se sale de [param tolerance] relativo a
## [param expected].
func _expect_ratio(measured: float, expected: float, tolerance: float, label: String) -> void:
	if expected <= 0.0:
		return
	var error := absf(measured - expected) / expected
	expect(error <= tolerance,
			"%s: medido %.3f, esperado %.3f (desvío %.1f %%, tope %.0f %%)"
			% [label, measured, expected, error * 100.0, tolerance * 100.0])


func _on_telegraphed(enemy: Node3D, attack_id: StringName, duration: float) -> void:
	_telegraph_events.append({
		"enemy": enemy, "attack_id": attack_id, "duration": duration, "time": _now(),
	})


func _on_action_changed(from: StringName, to: StringName) -> void:
	_action_log.append({"from": from, "to": to, "time": _now()})


## Reloj simulado del check, en segundos.
func _now() -> float:
	return _sim_time


func _physics_process(delta: float) -> void:
	_sim_time += delta


## Imprime el resumen de métricas.
func _print_summary() -> void:
	for line: String in _summary:
		print("  %s" % line)


## Cierra el check restaurando el entorno **siempre**, también cuando el fallo
## es un timeout y [method _run] nunca llega a volver.
##
## `Global.debug_freeze_ai` es global al proceso: dejarla encendida al salir
## convertiría cualquier corrida posterior en una escena de maniquíes.
func finish() -> void:
	_restore()
	super.finish()


## Devuelve la semilla y la bandera de congelado a como estaban. Es idempotente.
func _restore() -> void:
	Global.round_seed = _seed_before
	Global.debug_freeze_ai = _freeze_before
	if Events.enemy_attack_telegraphed.is_connected(_on_telegraphed):
		Events.enemy_attack_telegraphed.disconnect(_on_telegraphed)
