## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de energía, casco y respawn (`docs/09` §5, `energy_check`).
##
## Corre los 23 sub-checks de `docs/09` §5 sobre el `drone_rig.tscn` **real** —con
## su `EnergySystem`, su `Hull`, su `RespawnController` y su `WeaponMount`— más un
## `BatterySpawner` de ocho marcadores con uno tapado por un cuerpo de capa 8.
##
## Corre así:
##
##     godot --headless --path godot res://tools/energy_check.tscn
##
## Con `-- --negative` se le quita la histéresis al perfil de energía
## (`critical_exit_ratio = critical_ratio`) y el sub-check 8 tiene que detectar el
## parpadeo: la corrida sale en **rojo**. Es la prueba de que el check mide algo.
##
## ## Cómo se avanza el tiempo
##
## `docs/09` §5 lo fija: los sistemas bajo prueba quedan con `set_physics_process`
## en `false` y el check llama a su `_physics_process(1 / 100)` en bucle. Los 12 s
## del respawn son 1 200 iteraciones y tardan milisegundos; los 200 s del
## sub-check 21 son 20 000 y tardan poco más.
##
## Un detalle que no es opcional: **todo bloque de avance manual arranca después de
## `await get_tree().physics_frame`**. Esa señal se emite dentro del paso de física
## del árbol, así que la corrutina sigue corriendo en la misma ventana en la que un
## `_physics_process` normal correría, y el `intersect_shape` del spawner tiene un
## `PhysicsDirectSpaceState3D` válido. Fuera de esa ventana la consulta es ilegal.
##
## ## Por qué el rig real y no el `DroneStub` de `docs/09` §5
##
## Los contadores que el documento le pedía al doble se observan igual desde
## fuera y, de paso, prueban el cableado: `force_disarm()` por
## [signal Drone.disarmed], `set_thrust_scale()` por [method Drone.get_thrust_scale]
## y el armado rechazado por [signal FlightController.arm_failed]. Con un doble no
## habría nada que probar en los sub-checks 4, 9, 14, 16 y 23, que son justamente
## los de integración.
##
## ## Discrepancias con `docs/09` que este check resuelve
##
## - **Sub-check 5 contra §2.1**: el documento describe una recarga en reposo de
##   1 %/s con techo de 10 %, y además se contradice en §5 (pide que un dron
##   desarmado al 50 % suba a 60 % en 10 s **y** que el tope sea 10 %). WP-24e cierra
##   las dos puntas apagando el mecanismo: `idle_recharge = 0`. La salida del bloqueo
##   a 0 % —lo único que la recarga venía a resolver— es ahora la reconstrucción del
##   sub-check 9. Acá se verifica que un dron desarmado **no se mueve**, venga de
##   donde venga.
## - **Sub-checks 9 y 10 contra §2.2**: el documento deja al dron agotado bloqueado
##   hasta encontrar una pila. Desde WP-24e la batería a 0 % reconstruye el dron como
##   si hubiera muerto —doce segundos, `Events.drone_destroyed`, −300 y ×0.6— y lo
##   devuelve con `respawn_energy_depleted` (30 %), no con los 60 % del casco.
## - **Sub-check 6 contra §5 y §4**: la tabla de §5 pide «energía a 50 → **80.0**»
##   (la pila de +30 del Anexo A/C) y la nota del checkpoint 4 lo corrigió a 95.0
##   (la pila de +45). Las dos quedaron viejas el mismo día: por pedido del usuario
##   **una pila renueva toda la energía**, `battery_amount` vale 100 y recoger una
##   desde 50 % deja **100.0**. La cuenta de §5 ya no es una suma sino un tope, y
##   [constant DOC_BATTERY_AMOUNT] pasa a ser igual a [constant DOC_MAX_ENERGY].
## - **Sub-check 20 contra §2.5**: §2.5 dice que el acumulador reactiva «otra» pila
##   y §5 pide cinco de vuelta tras recoger dos y esperar 25 s. Gana el sub-check:
##   el acumulador es uno solo y rellena hasta el objetivo de una vez.
## - **Sub-check 23**: pide contar los `Area3D` del dron «y del jefe de prueba». No
##   hay jefe: los enemigos son WP-16/WP-17. Se recorre el árbol **entero** del
##   banco, que es una comprobación más fuerte.
extends CheckRunner

## Paso de física nominal, en segundos (100 Hz, `docs/02` §2).
const PHYSICS_STEP: float = 0.01

## Bandera que corrompe el perfil para la prueba negativa.
const NEGATIVE_ARG: String = "negative"

# --- Valores del Anexo A/C (`docs/09` §4), escritos a mano ------------------------------------
#
# Están duplicados a propósito: si el check midiera contra `profile.base_drain`
# sería tautológico y un perfil con el número cambiado pasaría igual. Acá el perfil
# es lo que se verifica, no la vara de medir.

const DOC_MAX_ENERGY: float = 100.0
const DOC_BASE_DRAIN: float = 0.40
const DOC_THROTTLE_DRAIN: float = 0.60
const DOC_IDLE_RECHARGE: float = 0.0
const DOC_IDLE_CAP: float = 0.0
const DOC_CRITICAL_RATIO: float = 0.15
const DOC_CRITICAL_EXIT_RATIO: float = 0.18
const DOC_CRITICAL_THRUST: float = 0.82
## Lo que devuelve una pila. **Una pila renueva toda la energía**, así que es igual
## a [constant DOC_MAX_ENERGY] y no un monto parcial: el sub-check 6 lo comprueba
## recogiendo una pila desde 50 % y exigiendo 100 %, no 50 + algo.
const DOC_BATTERY_AMOUNT: float = 100.0
const DOC_EMP_DRAIN: float = 25.0
const DOC_EMP_GLITCH: float = 3.0
const DOC_RESPAWN_ENERGY: float = 60.0
const DOC_RESPAWN_ENERGY_DEPLETED: float = 30.0
const DOC_ENERGY_PER_SHOT: float = 0.30

const DOC_MAX_HP: float = 100.0
const DOC_IMPACT_THRESHOLD: float = 8.0
const DOC_IMPACT_PER_MS: float = 4.0
const DOC_IMPACT_COOLDOWN: float = 0.35
const DOC_DEBRIS_MASS_MIN: float = 150.0
const DOC_DEBRIS_MASS_MAX: float = 3000.0
const DOC_DEBRIS_DAMAGE_MIN: float = 15.0
const DOC_DEBRIS_DAMAGE_MAX: float = 35.0
const DOC_RESPAWN_SECONDS: float = 12.0
const DOC_MULTIPLIER_FLOOR: float = 0.3

const DOC_PICKUP_RADIUS: float = 3.5
const DOC_SPAWNER_MARKERS: int = 8
const DOC_SPAWNER_ACTIVE: int = 5
const DOC_SPAWNER_DELAY: float = 25.0
const DOC_CLEARANCE_MASK: int = 384

# --- Parámetros de las pruebas ----------------------------------------------------------------

## Duración de cada medición de drenaje, en segundos.
const DRAIN_SECONDS: float = 10.0

## Tolerancia relativa del drenaje que pide `docs/09` §5 (±2 %).
const DRAIN_TOLERANCE: float = 0.02

## Tolerancia de las cuentas exactas (consumo, pila, EMP).
const EXACT_TOLERANCE: float = 0.01

## Tolerancia del respawn, en segundos.
const RESPAWN_TOLERANCE: float = 0.05

## Ticks máximos que se le dan al respawn antes de declararlo colgado.
const RESPAWN_MAX_TICKS: int = 2000

## Cambios de escala de empuje que admite el barrido del sub-check 8.
const THRUST_CHANGE_BUDGET: int = 2

## Segundos de simulación del sub-check 21.
const CLEARANCE_SECONDS: float = 200.0

## Índice del marcador tapado por el cuerpo de capa 8.
const BLOCKED_MARKER: int = 7

## Monto de la sonda de inyección del sub-check 6, en la escala 0–100.
##
## Tiene que ser un número que **no aparezca en ningún perfil ni escena del
## proyecto**: es lo único que distingue «el spawner copió el perfil» de «el
## spawner dejó el default de `battery_pickup.tscn`, que por suerte coincide».
const PROBE_BATTERY_AMOUNT: float = 12.5

## Daño por segundo que recibe el edificio de prueba durante el respawn.
const CITY_DAMAGE_PER_SECOND: float = 500.0

## Integridad inicial del edificio de prueba.
const CITY_HP: float = 20000.0

## Pérdida mínima del edificio durante los 12 s del respawn (`docs/09` §5 #18).
const CITY_LOSS_MIN: float = 5000.0

## Semilla con la que se prueba el determinismo del spawner.
const SEED_A: int = 987654321

var _rig: DroneRig = null
var _drone: Drone = null
var _controller: FlightController = null
var _energy: EnergySystem = null
var _hull: Hull = null
var _respawn: RespawnController = null
var _weapon: WeaponMount = null
var _spawner: BatterySpawner = null
var _pickup: BatteryPickup = null
var _command: FlightCommand = FlightCommand.new()

var _static_body: StaticBody3D = null
var _debris_body: RigidBody3D = null

# --- Grabadoras de señales --------------------------------------------------------------------

var _energy_events: int = 0
var _energy_last_ratio: float = -1.0
var _energy_last_critical: bool = false
var _hull_events: int = 0
var _hull_last_ratio: float = -1.0
var _damage_events: int = 0
var _damage_last_amount: float = -1.0
var _damage_last_source: Vector3 = Vector3.ZERO
var _destroyed_events: int = 0
var _destroyed_last: Vector3 = Vector3.ZERO
var _bus_respawns: Array[float] = []
var _local_respawns: Array[float] = []
var _rig_respawns: Array[float] = []
var _battery_events: int = 0
var _battery_last_amount: float = -1.0
var _battery_last_position: Vector3 = Vector3.ZERO
var _trauma_events: int = 0
var _disarms: int = 0
var _arm_failures: Array[String] = []
var _critical_enters: int = 0
var _critical_exits: int = 0
var _depleted_events: int = 0
var _emp_events: int = 0
var _emp_last_seconds: float = -1.0

## Energía con la que volvió el dron de la reconstrucción por batería agotada. La
## mide el sub-check 9 y la vuelve a aseverar el 16.
var _measured_depleted_energy: float = -1.0

var _city_hp: float = CITY_HP
var _drive_spawner: bool = false
var _negative: bool = false
var _original_seed: int = 0
var _original_ticks: int = 0
var _original_exit_ratio: float = 0.0

## Números medidos, para el resumen final.
var _measured: Array[String] = []


func _run() -> void:
	await get_tree().physics_frame
	if not _prepare():
		return
	await _check_drain_base()
	await _check_drain_throttle()
	await _check_drain_shot()
	await _check_drain_disarmed()
	await _check_battery_pickup()
	await _check_critical_enter()
	await _check_critical_hysteresis()
	await _check_depleted()
	await _check_emp()
	await _check_hull_impact()
	await _check_hull_debris()
	await _check_hull_attack()
	await _check_destroy_and_respawn()
	await _check_spawner()
	_check_no_area_hitbox()
	_check_restore()
	_print_measurements()


## Gancho de `docs/09` §2.8: [RespawnController] lo busca hacia arriba con
## `has_method`. Devolver la cámara fija del banco prueba que el cambio de vista
## del respawn está cableado de verdad.
func get_respawn_camera() -> Camera3D:
	return get_node_or_null(^"CameraFixed") as Camera3D


# --- Preparación ------------------------------------------------------------------------------

func _prepare() -> bool:
	_negative = user_args().has(NEGATIVE_ARG)
	_original_seed = Global.round_seed
	_original_ticks = Engine.physics_ticks_per_second

	_rig = get_node_or_null(^"DroneRig") as DroneRig
	_spawner = get_node_or_null(^"BatterySpawner") as BatterySpawner
	if _rig == null or _spawner == null:
		fail("el banco no tiene DroneRig o BatterySpawner")
		return false
	_drone = _rig.get_drone()
	_controller = _rig.get_flight_controller()
	_energy = _rig.get_energy_system()
	_hull = _rig.get_hull()
	_respawn = _rig.get_respawn_controller()
	_weapon = _rig.get_weapon_mount()
	if _drone == null or _energy == null or _hull == null or _respawn == null:
		fail("el rig no expone Drone/EnergySystem/Hull/RespawnController")
		return false
	if _energy.profile == null or _hull.profile == null:
		fail("faltan los perfiles de energía o de casco")
		return false

	_check_profiles()
	_original_exit_ratio = _energy.profile.critical_exit_ratio
	if _negative:
		print("  (modo negativo: se le quita la histéresis al EnergyProfile)")
		_energy.profile.critical_exit_ratio = _energy.profile.critical_ratio

	# `docs/09` §5: los sistemas bajo prueba no corren solos; los mueve el check.
	_energy.set_physics_process(false)
	_hull.set_physics_process(false)
	_respawn.set_physics_process(false)
	_spawner.set_physics_process(false)

	_connect_recorders()
	_build_test_bodies()

	_weapon.reset()
	_hull.restore()
	_respawn.reset()
	_energy.reset(DOC_MAX_ENERGY)
	return true


## Sub-check implícito: el perfil que se cargó es el del Anexo A/C. Sin esto,
## todas las mediciones siguientes podrían pasar con un perfil desbalanceado.
func _check_profiles() -> void:
	var energy_profile := _energy.profile
	expect_near(energy_profile.max_energy, DOC_MAX_ENERGY, 0.001, "EnergyProfile.max_energy")
	expect_near(energy_profile.base_drain, DOC_BASE_DRAIN, 0.001, "EnergyProfile.base_drain")
	expect_near(energy_profile.throttle_drain, DOC_THROTTLE_DRAIN, 0.001,
			"EnergyProfile.throttle_drain")
	expect_near(energy_profile.idle_recharge, DOC_IDLE_RECHARGE, 0.001,
			"EnergyProfile.idle_recharge")
	expect_near(energy_profile.idle_recharge_cap, DOC_IDLE_CAP, 0.001,
			"EnergyProfile.idle_recharge_cap")
	expect_near(energy_profile.critical_ratio, DOC_CRITICAL_RATIO, 0.001,
			"EnergyProfile.critical_ratio")
	expect_near(energy_profile.critical_exit_ratio, DOC_CRITICAL_EXIT_RATIO, 0.001,
			"EnergyProfile.critical_exit_ratio")
	expect_near(energy_profile.critical_thrust_scale, DOC_CRITICAL_THRUST, 0.001,
			"EnergyProfile.critical_thrust_scale")
	expect_near(energy_profile.battery_amount, DOC_BATTERY_AMOUNT, 0.001,
			"EnergyProfile.battery_amount")
	expect_near(energy_profile.emp_drain, DOC_EMP_DRAIN, 0.001, "EnergyProfile.emp_drain")
	expect_near(energy_profile.emp_glitch_seconds, DOC_EMP_GLITCH, 0.001,
			"EnergyProfile.emp_glitch_seconds")
	expect_near(energy_profile.respawn_energy, DOC_RESPAWN_ENERGY, 0.001,
			"EnergyProfile.respawn_energy")
	expect_near(energy_profile.respawn_energy_depleted, DOC_RESPAWN_ENERGY_DEPLETED, 0.001,
			"EnergyProfile.respawn_energy_depleted")

	var hull_profile := _hull.profile
	expect_near(hull_profile.max_hp, DOC_MAX_HP, 0.001, "HullProfile.max_hp")
	expect_near(hull_profile.impact_speed_threshold, DOC_IMPACT_THRESHOLD, 0.001,
			"HullProfile.impact_speed_threshold")
	expect_near(hull_profile.impact_damage_per_ms, DOC_IMPACT_PER_MS, 0.001,
			"HullProfile.impact_damage_per_ms")
	expect_near(hull_profile.impact_cooldown, DOC_IMPACT_COOLDOWN, 0.001,
			"HullProfile.impact_cooldown")
	expect_near(hull_profile.debris_mass_min, DOC_DEBRIS_MASS_MIN, 0.001,
			"HullProfile.debris_mass_min")
	expect_near(hull_profile.debris_mass_max, DOC_DEBRIS_MASS_MAX, 0.001,
			"HullProfile.debris_mass_max")
	expect_near(hull_profile.debris_damage_min, DOC_DEBRIS_DAMAGE_MIN, 0.001,
			"HullProfile.debris_damage_min")
	expect_near(hull_profile.debris_damage_max, DOC_DEBRIS_DAMAGE_MAX, 0.001,
			"HullProfile.debris_damage_max")
	expect_near(hull_profile.respawn_seconds, DOC_RESPAWN_SECONDS, 0.001,
			"HullProfile.respawn_seconds")
	expect_near(hull_profile.respawn_multiplier_floor, DOC_MULTIPLIER_FLOOR, 0.001,
			"HullProfile.respawn_multiplier_floor")


func _connect_recorders() -> void:
	var _discard := Events.energy_changed.connect(_on_energy_changed)
	_discard = Events.hull_changed.connect(_on_hull_changed)
	_discard = Events.drone_damaged.connect(_on_drone_damaged)
	_discard = Events.drone_destroyed.connect(_on_drone_destroyed)
	_discard = Events.drone_respawned.connect(_on_drone_respawned)
	_discard = Events.battery_collected.connect(_on_battery_collected)
	_discard = Events.camera_trauma.connect(_on_camera_trauma)
	_discard = _drone.disarmed.connect(_on_disarmed)
	_discard = _energy.critical_entered.connect(_on_critical_entered)
	_discard = _energy.critical_exited.connect(_on_critical_exited)
	_discard = _energy.depleted.connect(_on_energy_depleted)
	_discard = _energy.emp_hit.connect(_on_emp_hit)
	_discard = _respawn.respawned.connect(_on_local_respawned)
	_discard = _rig.respawned.connect(_on_rig_respawned)
	if _controller != null:
		_discard = _controller.arm_failed.connect(_on_arm_failed)


## Cuerpos sintéticos contra los que se prueba el casco, y la pila suelta del
## sub-check 6. Se crean en código porque hay que moverlos y reconfigurarlos entre
## pruebas.
func _build_test_bodies() -> void:
	_static_body = StaticBody3D.new()
	_static_body.name = "ImpactStub"
	_static_body.collision_layer = PhysicsLayers.WORLD
	_static_body.collision_mask = 0
	add_child(_static_body)
	_static_body.global_position = Vector3(0.0, 380.0, 0.0)

	_debris_body = RigidBody3D.new()
	_debris_body.name = "DebrisStub"
	_debris_body.collision_layer = PhysicsLayers.DEBRIS
	_debris_body.collision_mask = 0
	_debris_body.freeze = true
	_debris_body.mass = 450.0
	add_child(_debris_body)
	_debris_body.global_position = Vector3(4.0, 380.0, 0.0)

	var packed := load("res://drone/energy/battery_pickup.tscn") as PackedScene
	if packed == null:
		fail("no se pudo cargar battery_pickup.tscn")
		return
	_pickup = packed.instantiate() as BatteryPickup
	_pickup.name = "LoosePickup"
	_pickup.energy_system = _energy
	add_child(_pickup)


# --- Avance del tiempo ------------------------------------------------------------------------

## Avanza [param seconds] de simulación llamando a mano al `_physics_process` de
## los sistemas bajo prueba. Devuelve los ticks que ejecutó.
func _advance(seconds: float) -> int:
	var ticks := int(round(seconds / PHYSICS_STEP))
	for _i: int in ticks:
		_tick()
	return ticks


## Corre la cuenta de la reconstrucción a 100 Hz hasta que el dron vuelve a volar y
## devuelve los ticks que tardó. Los sistemas bajo prueba no se mueven solos
## (`docs/09` §5): los bombea [method _tick], `_respawn._physics_process` incluido.
func _finish_respawn() -> int:
	var ticks := 0
	while _respawn.is_respawning() and ticks < RESPAWN_MAX_TICKS:
		_tick()
		ticks += 1
	return ticks


func _tick() -> void:
	_energy._physics_process(PHYSICS_STEP)
	_hull._physics_process(PHYSICS_STEP)
	_respawn._physics_process(PHYSICS_STEP)
	if _drive_spawner:
		_spawner._physics_process(PHYSICS_STEP)
	_city_hp = maxf(_city_hp - CITY_DAMAGE_PER_SECOND * PHYSICS_STEP, 0.0)


## Deja el dron quieto en el sitio. Hace falta antes de cada contacto sintético:
## `Drone._on_body_entered` traduce el contacto a [signal Drone.crashed] con la
## velocidad que lleve el cuerpo, y por encima de 12 m/s el `FlightController`
## entra en RECOVER, que cambiaría el motivo de los armados rechazados.
func _park_drone() -> void:
	_drone.reset_to(_drone.global_transform)


func _set_throttle(value: float) -> void:
	_command.set_axes(value, 0.0, 0.0, 0.0)
	_drone.update_command(_command)


func _arm_at_zero_throttle() -> bool:
	_set_throttle(0.0)
	return _drone.arm()


func _record(line: String) -> void:
	_measured.append(line)


# --- 1. drain_base ----------------------------------------------------------------------------

func _check_drain_base() -> void:
	await get_tree().physics_frame
	_energy.reset(DOC_MAX_ENERGY)
	var armed := _arm_at_zero_throttle()
	expect(armed, "1 drain_base: el dron no pudo armar con la batería llena")
	expect(_drone.is_armed(), "1 drain_base: el dron quedó desarmado")
	var _ticks := _advance(DRAIN_SECONDS)
	var expected := DOC_MAX_ENERGY - DOC_BASE_DRAIN * DRAIN_SECONDS
	expect_near(_energy.energy, expected, expected * DRAIN_TOLERANCE,
			"1 drain_base: 10 s armado con throttle 0")
	_record("1  drain_base ............. %.3f %% (esperado %.2f, ±2 %%)"
			% [_energy.energy, expected])


# --- 2. drain_throttle ------------------------------------------------------------------------

func _check_drain_throttle() -> void:
	await get_tree().physics_frame
	_energy.reset(DOC_MAX_ENERGY)
	_set_throttle(1.0)
	expect_near(_drone.get_throttle(), 1.0, 0.001, "2 drain_throttle: el acelerador no llegó a 1")
	var _ticks := _advance(DRAIN_SECONDS)
	var full := DOC_MAX_ENERGY - (DOC_BASE_DRAIN + DOC_THROTTLE_DRAIN) * DRAIN_SECONDS
	expect_near(_energy.energy, full, full * DRAIN_TOLERANCE,
			"2 drain_throttle: 10 s armado con throttle 1.0")
	var measured_full := _energy.energy

	_energy.reset(DOC_MAX_ENERGY)
	_set_throttle(0.5)
	_ticks = _advance(DRAIN_SECONDS)
	var half := DOC_MAX_ENERGY - (DOC_BASE_DRAIN + DOC_THROTTLE_DRAIN * 0.5) * DRAIN_SECONDS
	expect_near(_energy.energy, half, half * DRAIN_TOLERANCE,
			"2 drain_throttle: 10 s armado con throttle 0.5")
	_record("2  drain_throttle ......... %.3f %% a 1.0 (esperado %.2f) · %.3f %% a 0.5 (esperado %.2f)"
			% [measured_full, full, _energy.energy, half])
	_set_throttle(0.0)


# --- 4. drain_shot ----------------------------------------------------------------------------

func _check_drain_shot() -> void:
	await get_tree().physics_frame
	# (a) 20 cobros directos de 0.30 bajan exactamente 6.0.
	_energy.reset(50.0)
	for _i: int in 20:
		expect(_energy.consume(DOC_ENERGY_PER_SHOT),
				"4 drain_shot: consume(0.30) rechazado con energía de sobra")
	expect_near(_energy.energy, 44.0, EXACT_TOLERANCE,
			"4 drain_shot: 20 cobros de 0.30 desde 50 %")
	var measured_drop := 50.0 - _energy.energy

	# (b) todo o nada: sin saldo no resta nada.
	_energy.reset(0.2)
	expect(not _energy.consume(DOC_ENERGY_PER_SHOT),
			"4 drain_shot: consume(0.30) aceptado con 0.2 de saldo")
	expect_near(_energy.energy, 0.2, EXACT_TOLERANCE,
			"4 drain_shot: un cobro rechazado no puede restar nada")

	# (c) el arma real cobra por `WeaponMount.fire()`, no por una llamada de prueba.
	expect(_weapon != null, "4 drain_shot: el rig no expone WeaponMount")
	if _weapon == null:
		return
	expect(_weapon.energy_system == _energy,
			"4 drain_shot: el arma no resolvió Drone/EnergySystem por duck typing")
	expect(_weapon.profile != null, "4 drain_shot: el arma no tiene perfil")
	expect_near(_weapon.profile.energy_per_shot, DOC_ENERGY_PER_SHOT, 0.001,
			"4 drain_shot: WeaponProfile.energy_per_shot")
	_weapon.reset()
	_energy.reset(DOC_MAX_ENERGY)
	if not _drone.is_armed():
		var _armed := _arm_at_zero_throttle()
	var before := _energy.energy
	var fired := _weapon.fire()
	expect(fired, "4 drain_shot: WeaponMount.fire() no salió con la batería llena")
	var shot_cost := before - _energy.energy
	expect_near(shot_cost, DOC_ENERGY_PER_SHOT, EXACT_TOLERANCE,
			"4 drain_shot: el disparo real no cobró energy_per_shot")

	# (d) sin saldo el arma no dispara y no cobra.
	_energy.reset(0.2)
	_weapon.reset()
	var blocked := _weapon.fire()
	expect(not blocked, "4 drain_shot: el arma disparó sin energía")
	expect_near(_energy.energy, 0.2, EXACT_TOLERANCE,
			"4 drain_shot: un disparo bloqueado no puede restar energía")
	_record("4  drain_shot ............. 20×0.30 = %.3f · fire() = %.3f · bloqueado = %s"
			% [measured_drop, shot_cost, str(not blocked)])


# --- 5. drain_disarmed ------------------------------------------------------------------------

## Un dron desarmado **no recarga nada** (WP-24e): `idle_recharge` e
## `idle_recharge_cap` valen 0 y este sub-check mide que la batería no se mueve un
## milésimo en diez segundos, venga de donde venga. La salida del bloqueo a 0 % es
## el sub-check 9, no esperar sentado.
func _check_drain_disarmed() -> void:
	await get_tree().physics_frame
	_drone.disarm()
	expect(not _drone.is_armed(), "5 drain_disarmed: el dron no se desarmó")
	expect_near(_energy.profile.idle_recharge, 0.0, 0.001,
			"5 drain_disarmed: la recarga en reposo tiene que estar apagada")
	expect_near(_energy.profile.idle_recharge_cap, 0.0, 0.001,
			"5 drain_disarmed: el techo de la recarga en reposo tiene que estar apagado")

	var measured: Array[float] = []
	# 5 % era el caso que subía al techo, 9.5 % el que lo rozaba y 50 % el que ya
	# estaba por encima: los tres tienen que quedarse clavados.
	for start: float in [5.0, 9.5, 50.0, 95.0]:
		_energy.reset(start)
		var _ticks := _advance(DRAIN_SECONDS)
		measured.append(_energy.energy)
		expect_near(_energy.energy, start, EXACT_TOLERANCE,
				"5 drain_disarmed: desde %.1f %% un dron desarmado no se mueve en %.0f s"
				% [start, DRAIN_SECONDS])
	expect(_energy.energy <= DOC_MAX_ENERGY,
			"5 drain_disarmed: la energía se pasó del máximo")
	_record("5  drain_disarmed ........ 5 %%→%.3f · 9.5 %%→%.3f · 50 %%→%.3f · 95 %%→%.3f (sin recarga en reposo)"
			% [measured[0], measured[1], measured[2], measured[3]])


# --- 6. battery_pickup ------------------------------------------------------------------------

func _check_battery_pickup() -> void:
	await get_tree().physics_frame
	if _pickup == null:
		fail("6 battery_pickup: no hay pila de prueba")
		return
	# Configuración de `docs/09` §2.4 y §3.6.
	expect(_pickup.collision_layer == PhysicsLayers.PICKUP,
			"6 battery_pickup: la pila no está en la capa 7 (layer %d)" % _pickup.collision_layer)
	expect(_pickup.collision_mask == PhysicsLayers.DRONE,
			"6 battery_pickup: la máscara no es 2 (mask %d)" % _pickup.collision_mask)
	expect(not _pickup.monitorable, "6 battery_pickup: monitorable debería ser false")
	expect(_pickup.is_in_group(&"pickups"), "6 battery_pickup: la pila no está en el grupo pickups")
	var shape := _pickup.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var sphere: SphereShape3D = shape.shape as SphereShape3D if shape != null else null
	expect(sphere != null, "6 battery_pickup: la pila no tiene SphereShape3D")
	if sphere != null:
		expect_near(sphere.radius, DOC_PICKUP_RADIUS, 0.001, "6 battery_pickup: radio de la pila")
	expect_near(_pickup.amount, DOC_BATTERY_AMOUNT, 0.001, "6 battery_pickup: energía de la pila")

	var at := Vector3(11.0, 2.0, -7.0)
	_pickup.activate(Transform3D(Basis.IDENTITY, at))
	expect(_pickup.is_active(), "6 battery_pickup: activate() no la dejó activa")
	# `monitoring` se escribe en diferido (está prohibido tocarlo dentro del
	# despacho de `body_entered`), así que hay que dejar vaciar la cola.
	await wait_physics(2)
	expect(_pickup.monitoring, "6 battery_pickup: una pila activa tiene que monitorear")

	_energy.reset(50.0)
	_battery_events = 0
	_pickup.body_entered.emit(_drone)
	# Una pila **renueva toda la energía**: desde 50 % tiene que dejar 100,0, y el
	# recorte de `recharge()` es lo que impide que el monto de 100 se pase del máximo.
	expect_near(_energy.energy, DOC_MAX_ENERGY, EXACT_TOLERANCE,
			"6 battery_pickup: la pila no dejó la energía en 100 % desde 50 %")
	expect(_battery_events == 1,
			"6 battery_pickup: battery_collected se emitió %d veces, no 1" % _battery_events)
	expect_near(_battery_last_amount, DOC_BATTERY_AMOUNT, 0.001,
			"6 battery_pickup: el amount de battery_collected")
	expect(_battery_last_position.distance_to(at) < 0.01,
			"6 battery_pickup: la posición de battery_collected es %v, no %v"
			% [_battery_last_position, at])
	expect(not _pickup.is_active(), "6 battery_pickup: la pila quedó activa tras recogerse")
	expect(not _pickup.visible, "6 battery_pickup: la pila quedó visible tras recogerse")

	# Una pila apagada no vuelve a cobrarse, ni siquiera durante el frame en el que
	# `monitoring` todavía no se apagó.
	_pickup.body_entered.emit(_drone)
	expect(_battery_events == 1, "6 battery_pickup: una pila apagada volvió a cobrarse")
	await wait_physics(2)
	expect(not _pickup.monitoring, "6 battery_pickup: monitoring quedó en true tras recogerse")

	# (e) el monto de una pila **de ronda** lo inyecta el [BatterySpawner] desde
	# `EnergyProfile.battery_amount`, y no sale del default de `battery_pickup.tscn`.
	# La pila del spawner del banco lleva el número del perfil del proyecto...
	var spawned := _spawner.get_pickup(0) if _spawner != null else null
	expect(spawned != null, "6 battery_pickup: el spawner del banco no construyó pilas")
	var spawned_amount := spawned.amount if spawned != null else -1.0
	expect_near(spawned_amount, DOC_BATTERY_AMOUNT, 0.001,
			"6 battery_pickup: la pila del spawner suma %.3f y el perfil dice %.2f"
			% [spawned_amount, DOC_BATTERY_AMOUNT])
	# ...pero eso solo no prueba nada, porque el default de la escena **también** es
	# `DOC_BATTERY_AMOUNT`: si el spawner dejara de inyectar, la aserción de arriba
	# seguiría pasando. La prueba de la inyección es un spawner con un perfil
	# duplicado y un monto que no existe en ninguna otra parte del proyecto.
	var injected := await _probe_injected_amount()
	expect_near(injected, PROBE_BATTERY_AMOUNT, 0.001,
			"6 battery_pickup: con el perfil en %.1f la pila del spawner salió con %.3f:"
			% [PROBE_BATTERY_AMOUNT, injected]
			+ " el monto no se inyecta y quedó el default de la escena")
	_record("6  battery_pickup ........ 50 %%→%.3f %% · battery_collected(%.0f, %v) ×%d · spawner inyecta %.1f (sonda con perfil %.1f → %.1f)"
			% [_energy.energy, _battery_last_amount, _battery_last_position, _battery_events,
			spawned_amount, PROBE_BATTERY_AMOUNT, injected])


## Monto con el que un [BatterySpawner] recién construido arma sus pilas cuando su
## perfil dice [constant PROBE_BATTERY_AMOUNT].
##
## Monta un spawner de un solo marcador con una batería propia —un [EnergySystem]
## suelto con el perfil **duplicado**— en vez de tocar `default_energy.tres`, que es
## el recurso que comparten el rig del banco y cualquier escena que siga cargada en
## el proceso: corromperlo a mitad de la corrida contaminaría los quince sub-checks
## que vienen después.
##
## El spawner se desconecta de la física apenas nace: lo único que interesa de él es
## lo que hizo su `_ready()`, no su acumulador de relleno.
func _probe_injected_amount() -> float:
	var profile := _energy.profile.duplicate() as EnergyProfile
	profile.battery_amount = PROBE_BATTERY_AMOUNT
	var battery := EnergySystem.new()
	battery.name = "ProbeEnergy"
	battery.profile = profile

	var probe := BatterySpawner.new()
	probe.name = "AmountProbe"
	probe.energy_system = battery
	var marker := Marker3D.new()
	marker.name = "Marker"
	probe.add_child(marker)
	add_child(probe)
	probe.set_physics_process(false)
	await wait_physics(1)

	var pickup := probe.get_pickup(0)
	var amount := pickup.amount if pickup != null else -1.0
	probe.queue_free()
	# `battery` nunca entró al árbol, así que no hay `queue_free()` que valga.
	battery.free()
	await wait_frames(2)
	return amount


# --- 7. critical_enter ------------------------------------------------------------------------

func _check_critical_enter() -> void:
	await get_tree().physics_frame
	_energy.reset(DOC_MAX_ENERGY)
	_critical_enters = 0
	_energy_events = 0
	_energy.energy = 14.0
	expect(_energy.is_critical(), "7 critical_enter: al 14 % no se entró en crítico")
	expect(_critical_enters == 1,
			"7 critical_enter: critical_entered se emitió %d veces, no 1" % _critical_enters)
	expect(_energy_last_critical,
			"7 critical_enter: el último energy_changed no llevaba critical = true")
	expect_near(_energy_last_ratio, 0.14, 0.001, "7 critical_enter: el ratio publicado")
	expect_near(_drone.get_thrust_scale(), DOC_CRITICAL_THRUST, 0.001,
			"7 critical_enter: set_thrust_scale(0.82) no llegó al dron")
	_record("7  critical_enter ........ ratio %.4f critical=%s thrust_scale %.3f"
			% [_energy_last_ratio, str(_energy_last_critical), _drone.get_thrust_scale()])


# --- 8. critical_hysteresis -------------------------------------------------------------------

## Barrido que oscila alrededor del 15 % y termina por encima del 18 %.
##
## Con histéresis hay exactamente **dos** cambios de escala: uno al entrar y otro
## al salir. Sin ella (`--negative`) cada cruce del 15 % produce uno, y el barrido
## está diseñado para cruzarlo cinco veces: el check tiene que ponerse en rojo.
const HYSTERESIS_SWEEP: Array[float] = [16.0, 14.5, 15.5, 14.5, 15.5, 14.5, 19.0]


func _check_critical_hysteresis() -> void:
	await get_tree().physics_frame
	_energy.reset(DOC_MAX_ENERGY)
	_critical_enters = 0
	_critical_exits = 0
	var changes := 0
	var previous := _drone.get_thrust_scale()
	var still_critical_at_16 := false
	for value: float in HYSTERESIS_SWEEP:
		_energy.energy = value
		var scale := _drone.get_thrust_scale()
		if not is_equal_approx(scale, previous):
			changes += 1
			previous = scale
		if is_equal_approx(value, 15.5) and _energy.is_critical():
			still_critical_at_16 = true
	expect(still_critical_at_16,
			"8 critical_hysteresis: al volver al 15.5 % se salió de crítico (sin histéresis)")
	expect(not _energy.is_critical(), "8 critical_hysteresis: al 19 % sigue en crítico")
	expect(_critical_exits >= 1, "8 critical_hysteresis: nunca se emitió critical_exited")
	expect_near(_drone.get_thrust_scale(), 1.0, 0.001,
			"8 critical_hysteresis: al salir no se restauró thrust_scale a 1.0")
	expect(changes <= THRUST_CHANGE_BUDGET,
			"8 critical_hysteresis: %d cambios de escala en el barrido, máximo %d (parpadeo)"
			% [changes, THRUST_CHANGE_BUDGET])
	_record("8  critical_hysteresis ... %d cambios de escala (máx %d) · enters %d · exits %d"
			% [changes, THRUST_CHANGE_BUDGET, _critical_enters, _critical_exits])


# --- 9. depleted ------------------------------------------------------------------------------

## Batería a 0 %: desarme, bloqueo del armado **y reconstrucción**.
##
## Desde WP-24e el agotamiento no deja al dron esperando una pila que quizá no
## llegue: dispara la misma secuencia de doce segundos que una muerte por casco
## —`Events.drone_destroyed` una sola vez, congelado e invisible— y lo devuelve con
## `respawn_energy_depleted`. Sin esto el 0 % era un ciclo: recargaba 1 %, armaba,
## caía, recargaba 1 %.
func _check_depleted() -> void:
	await get_tree().physics_frame
	_respawn.reset()
	_hull.restore()
	_park_drone()
	_energy.reset(DOC_MAX_ENERGY)
	_set_throttle(0.0)
	if not _drone.is_armed():
		var _armed := _arm_at_zero_throttle()
	expect(_drone.is_armed(), "9 depleted: el dron tenía que estar armado antes de agotarse")

	_disarms = 0
	_depleted_events = 0
	_destroyed_events = 0
	_energy.energy = 0.0
	expect(_energy.is_depleted(), "9 depleted: is_depleted() no es true con 0 %")
	expect(_depleted_events == 1,
			"9 depleted: la señal depleted se emitió %d veces, no 1" % _depleted_events)
	expect(_disarms == 1,
			"9 depleted: force_disarm() disparó %d desarmes, no 1" % _disarms)
	expect(not _drone.is_armed(), "9 depleted: el dron siguió armado con la batería a 0")
	expect(not _energy.consume(1.0), "9 depleted: consume() aceptó un cobro con la batería a 0")
	expect(_controller != null and not _controller.can_arm_energy,
			"9 depleted: can_arm_energy siguió en true")

	# La reconstrucción arrancó en el mismo tick, con su motivo y su hecho global.
	expect(_respawn.is_respawning(),
			"9 depleted: la batería a 0 no arrancó la reconstrucción (docs/09 §2.8)")
	expect(_respawn.get_reason() == RespawnController.Reason.ENERGY,
			"9 depleted: el motivo de la reconstrucción es %d y tenía que ser ENERGY"
			% int(_respawn.get_reason()))
	expect(_destroyed_events == 1,
			"9 depleted: Events.drone_destroyed se emitió %d veces, no 1" % _destroyed_events)
	expect(_drone.freeze, "9 depleted: el dron no quedó congelado")
	expect(not _drone.visible, "9 depleted: el dron quedó visible durante la reconstrucción")

	_arm_failures.clear()
	var armed_again := _arm_at_zero_throttle()
	expect(not armed_again, "9 depleted: el dron armó con la batería a 0")
	expect(_arm_failures.size() == 1 and _arm_failures[0] == FlightController.REASON_NO_ENERGY,
			"9 depleted: arm_failed no llegó con ERR_ARM_NO_ENERGY (llegó %s)"
			% str(_arm_failures))

	# Los doce segundos, tick a tick, con el mundo corriendo.
	var ticks := _finish_respawn()
	expect(ticks < RESPAWN_MAX_TICKS, "9 depleted: la reconstrucción por batería nunca llegó")
	expect_near(float(ticks) * PHYSICS_STEP, DOC_RESPAWN_SECONDS, RESPAWN_TOLERANCE,
			"9 depleted: la reconstrucción por batería también dura 12 s")
	_measured_depleted_energy = _energy.energy
	expect_near(_energy.energy, DOC_RESPAWN_ENERGY_DEPLETED, 0.001,
			"9 depleted: el dron tenía que volver con 30 %% y volvió con %.2f %%"
			% _energy.energy)
	expect(_destroyed_events == 1,
			"9 depleted: Events.drone_destroyed se emitió %d veces en toda la secuencia, no 1"
			% _destroyed_events)
	expect(not _energy.is_depleted(), "9 depleted: siguió agotado tras reconstruirse")
	expect(not _energy.is_critical(), "9 depleted: 30 %% está por encima del 18 %% de salida")
	expect(_controller.can_arm_energy, "9 depleted: can_arm_energy no volvió a true")
	expect(not _drone.freeze, "9 depleted: el dron quedó congelado tras reconstruirse")
	expect(_drone.visible, "9 depleted: el dron quedó invisible tras reconstruirse")
	expect_near(_hull.hp, DOC_MAX_HP, 0.001,
			"9 depleted: la reconstrucción tiene que devolver el casco entero")
	expect(_respawn.get_death_count() == 1,
			"9 depleted: la reconstrucción por batería cuenta como muerte (contador %d)"
			% _respawn.get_death_count())
	var armed_ok := _arm_at_zero_throttle()
	expect(armed_ok, "9 depleted: el dron no pudo armar tras reconstruirse")
	_record("9  depleted .............. desarmes %d · arm_failed %s · reconstrucción %.2f s por ENERGY · vuelve con %.1f %% · rearme %s"
			% [_disarms, str(_arm_failures), float(ticks) * PHYSICS_STEP,
			_measured_depleted_energy, str(armed_ok)])
	_respawn.reset()


# --- 10. emp ----------------------------------------------------------------------------------

func _check_emp() -> void:
	await get_tree().physics_frame
	_energy.reset(80.0)
	_emp_events = 0
	_energy.apply_emp(_energy.profile.emp_drain, _energy.profile.emp_glitch_seconds)
	expect_near(_energy.energy, 55.0, EXACT_TOLERANCE, "10 emp: 80 % − 25 % debería dar 55 %")
	expect(_emp_events == 1, "10 emp: emp_hit se emitió %d veces, no 1" % _emp_events)
	expect_near(_emp_last_seconds, DOC_EMP_GLITCH, 0.001, "10 emp: los segundos de glitch")
	var after_first := _energy.energy

	# Desde 20 %: cae a 0, entra en crítico y desarma en el mismo tick.
	_energy.reset(DOC_MAX_ENERGY)
	_set_throttle(0.0)
	if not _drone.is_armed():
		var _armed := _arm_at_zero_throttle()
	_energy.reset(20.0)
	_disarms = 0
	_critical_enters = 0
	_emp_events = 0
	_destroyed_events = 0
	_energy.apply_emp(_energy.profile.emp_drain, _energy.profile.emp_glitch_seconds)
	expect_near(_energy.energy, 0.0, EXACT_TOLERANCE, "10 emp: 20 % − 25 % debería recortar en 0")
	expect(_energy.is_critical(), "10 emp: no se entró en crítico tras el EMP")
	expect(_critical_enters == 1, "10 emp: critical_entered no se emitió una sola vez")
	expect(_energy.is_depleted(), "10 emp: no se llegó a agotado tras el EMP")
	expect(_disarms == 1, "10 emp: el EMP no desarmó el dron en el mismo tick")
	expect(_emp_events == 1, "10 emp: emp_hit no se emitió en el segundo pulso")
	# Un EMP que deja la batería en cero dispara la reconstrucción igual que agotarla
	# volando: es el mismo estado, llegado por otro camino (`docs/09` §2.9).
	expect(_respawn.is_respawning(),
			"10 emp: el EMP que deja la batería en 0 tiene que arrancar la reconstrucción")
	expect(_respawn.get_reason() == RespawnController.Reason.ENERGY,
			"10 emp: el motivo de la reconstrucción tras el EMP tiene que ser ENERGY")
	expect(_destroyed_events == 1,
			"10 emp: Events.drone_destroyed se emitió %d veces tras el EMP, no 1"
			% _destroyed_events)
	var emp_ticks := _finish_respawn()
	expect(emp_ticks < RESPAWN_MAX_TICKS, "10 emp: la reconstrucción tras el EMP nunca llegó")
	expect_near(_energy.energy, DOC_RESPAWN_ENERGY_DEPLETED, 0.001,
			"10 emp: tras el EMP el dron vuelve con 30 %%, no con %.2f %%" % _energy.energy)
	_record("10 emp .................. 80 %%→%.3f · 20 %%→0.000 (crítico %s, agotado %s) · reconstrucción por ENERGY → %.1f %%"
			% [after_first, str(_critical_enters == 1), str(true), _energy.energy])
	_respawn.reset()
	_energy.reset(DOC_MAX_ENERGY)


# --- 11. hull_impact --------------------------------------------------------------------------

func _check_hull_impact() -> void:
	await get_tree().physics_frame
	_hull.restore()
	_park_drone()
	_damage_events = 0
	_emit_contact(_static_body, 20.0)
	var expected := (20.0 - DOC_IMPACT_THRESHOLD) * DOC_IMPACT_PER_MS
	expect_near(DOC_MAX_HP - _hull.hp, expected, 0.1,
			"11 hull_impact: un choque a 20 m/s debería costar 48 de casco")
	var at_twenty := DOC_MAX_HP - _hull.hp

	# Cooldown: el mismo cuerpo a los 0.1 s no vuelve a cobrar.
	var hp_before := _hull.hp
	var _ticks := _advance(0.1)
	_emit_contact(_static_body, 20.0)
	expect_near(_hull.hp, hp_before, 0.001,
			"11 hull_impact: el cooldown de 0.35 s por cuerpo no frenó el segundo contacto")

	# Pasado el cooldown, el mismo cuerpo vuelve a cobrar.
	_ticks = _advance(DOC_IMPACT_COOLDOWN + 0.02)
	_emit_contact(_static_body, 20.0)
	expect_near(hp_before - _hull.hp, expected, 0.1,
			"11 hull_impact: pasado el cooldown el mismo cuerpo tiene que volver a dañar")

	# Roce: por debajo del umbral no hay daño.
	_hull.restore()
	_ticks = _advance(DOC_IMPACT_COOLDOWN + 0.02)
	_emit_contact(_static_body, 6.0)
	expect_near(_hull.hp, DOC_MAX_HP, 0.001,
			"11 hull_impact: un contacto a 6 m/s no puede hacer daño")
	_record("11 hull_impact .......... 20 m/s → %.2f de casco · 6 m/s → %.2f · cooldown %.2f s"
			% [at_twenty, DOC_MAX_HP - _hull.hp, DOC_IMPACT_COOLDOWN])


## Contacto sintético: fija la velocidad del tick anterior y emite `body_entered`
## del dron, que es exactamente lo que hace Jolt al principio del tick siguiente.
func _emit_contact(body: Node3D, previous_speed: float) -> void:
	_park_drone()
	_hull.set_previous_velocity(Vector3(0.0, 0.0, -previous_speed))
	_drone.body_entered.emit(body)


# --- 12. hull_debris --------------------------------------------------------------------------

func _check_hull_debris() -> void:
	await get_tree().physics_frame
	_hull.restore()
	var _ticks := _advance(DOC_IMPACT_COOLDOWN + 0.02)
	_debris_body.mass = 450.0
	_emit_contact(_debris_body, 20.0)
	var damage := DOC_MAX_HP - _hull.hp
	var expected := DOC_DEBRIS_DAMAGE_MIN + (450.0 - DOC_DEBRIS_MASS_MIN) \
			/ (DOC_DEBRIS_MASS_MAX - DOC_DEBRIS_MASS_MIN) \
			* (DOC_DEBRIS_DAMAGE_MAX - DOC_DEBRIS_DAMAGE_MIN)
	expect_near(damage, expected, 0.5,
			"12 hull_debris: un escombro de 450 kg debería costar ≈17.1 de casco")
	expect(absf(damage - 48.0) > 1.0,
			"12 hull_debris: el escombro se cobró con la fórmula de velocidad, no por masa")

	# Una torre de 2 000 kg cuesta ≈28.
	_hull.restore()
	_ticks = _advance(DOC_IMPACT_COOLDOWN + 0.02)
	_debris_body.mass = 2000.0
	_emit_contact(_debris_body, 20.0)
	var heavy := DOC_MAX_HP - _hull.hp
	expect_near(heavy, 28.0, 0.5, "12 hull_debris: un escombro de 2 000 kg debería costar ≈28")
	_record("12 hull_debris .......... 450 kg → %.2f (esperado %.2f) · 2 000 kg → %.2f"
			% [damage, expected, heavy])


# --- 13. hull_attack --------------------------------------------------------------------------

func _check_hull_attack() -> void:
	await get_tree().physics_frame
	_hull.restore()
	_damage_events = 0
	_hull_events = 0
	var source := Vector3(12.0, 3.0, -4.0)
	_hull.apply_damage(45.0, source)
	expect_near(_hull.hp, 55.0, 0.001, "13 hull_attack: apply_damage(45) debería dejar hp en 55")
	expect(_damage_events == 1,
			"13 hull_attack: drone_damaged se emitió %d veces, no 1" % _damage_events)
	expect_near(_damage_last_amount, 45.0, 0.001, "13 hull_attack: el amount de drone_damaged")
	expect(_damage_last_source.distance_to(source) < 0.001,
			"13 hull_attack: la source_position de drone_damaged")
	expect_near(_hull_last_ratio, 0.55, 0.001, "13 hull_attack: el ratio de hull_changed")
	expect(_hull_events >= 1, "13 hull_attack: hull_changed no se emitió")
	var attack_line := "13 hull_attack .......... hp %.1f · drone_damaged(%.1f, %v) · hull_changed %.4f" \
			% [_hull.hp, _damage_last_amount, _damage_last_source, _hull_last_ratio]

	# El alias de `docs/09` §2.10 tiene que ir al mismo sitio.
	_hull.take_damage(5.0, source)
	expect_near(_hull.hp, 50.0, 0.001, "13 hull_attack: take_damage() no es alias de apply_damage()")

	# Aridad del contrato de `docs/02` §5.1: las tres señales se conectaron con
	# `Callable` de 2, 1 y 1 argumentos y ninguna falló en tiempo de ejecución.
	var signals := Events.get_signal_list()
	var arity: Dictionary[String, int] = {}
	for entry: Dictionary in signals:
		arity[String(entry["name"])] = (entry["args"] as Array).size()
	expect(arity.get("drone_damaged", -1) == 2, "13 hull_attack: drone_damaged no tiene 2 argumentos")
	expect(arity.get("hull_changed", -1) == 1, "13 hull_attack: hull_changed no tiene 1 argumento")
	expect(arity.get("drone_destroyed", -1) == 1,
			"13 hull_attack: drone_destroyed no tiene 1 argumento")
	expect(arity.get("drone_respawned", -1) == 1,
			"13 hull_attack: drone_respawned no tiene 1 argumento")
	expect(arity.get("battery_collected", -1) == 2,
			"13 hull_attack: battery_collected no tiene 2 argumentos")
	expect(arity.get("energy_changed", -1) == 2,
			"13 hull_attack: energy_changed no tiene 2 argumentos")
	_record(attack_line)
	_record("   alias take_damage(5) ... hp %.1f" % _hull.hp)


# --- 14 a 18. destroy, respawn y la ciudad que sufre ------------------------------------------

func _check_destroy_and_respawn() -> void:
	await get_tree().physics_frame
	_hull.restore()
	_respawn.reset()
	# Los sub-checks 9 y 10 reconstruyeron el dron por batería; el 17 cuenta
	# reapariciones y quiere exactamente las tres de acá.
	_bus_respawns.clear()
	_local_respawns.clear()
	_rig_respawns.clear()
	_energy.reset(DOC_MAX_ENERGY)
	_set_throttle(0.0)
	if not _drone.is_armed():
		var _armed := _arm_at_zero_throttle()

	var expected_multipliers: Array[float] = [0.6, 0.36, DOC_MULTIPLIER_FLOOR]
	var measured_times: Array[float] = []
	var measured_multipliers: Array[float] = []
	for death: int in 3:
		var timing := await _one_death_and_respawn(death, expected_multipliers[death])
		measured_times.append(timing)
		measured_multipliers.append(_respawn.get_score_multiplier())

	expect(_bus_respawns.size() == 3,
			"17 respawn_penalty: Events.drone_respawned se emitió %d veces, no 3"
			% _bus_respawns.size())
	expect(_local_respawns.size() == 3,
			"17 respawn_penalty: RespawnController.respawned se emitió %d veces, no 3"
			% _local_respawns.size())
	expect(_rig_respawns.size() == 3,
			"17 respawn_penalty: DroneRig.respawned se emitió %d veces, no 3"
			% _rig_respawns.size())
	for index: int in mini(3, _bus_respawns.size()):
		expect_near(_bus_respawns[index], expected_multipliers[index], 0.001,
				"17 respawn_penalty: multiplicador %d en el bus" % (index + 1))
		expect_near(_local_respawns[index], expected_multipliers[index], 0.001,
				"17 respawn_penalty: multiplicador %d en la señal local" % (index + 1))
		expect_near(_rig_respawns[index], expected_multipliers[index], 0.001,
				"17 respawn_penalty: multiplicador %d reexpuesto por DroneRig" % (index + 1))
	_record("15 respawn_timing ....... %.3f / %.3f / %.3f s (esperado 12.00 ±%.2f)"
			% [measured_times[0], measured_times[1], measured_times[2], RESPAWN_TOLERANCE])
	_record("17 respawn_penalty ...... ×%.3f → ×%.3f → ×%.3f (piso %.2f)"
			% [measured_multipliers[0], measured_multipliers[1], measured_multipliers[2],
			DOC_MULTIPLIER_FLOOR])


## Una muerte completa: destruir, contar los 12 s tick a tick y verificar el estado
## de la reaparición. Devuelve los segundos medidos.
func _one_death_and_respawn(death: int, expected_multiplier: float) -> float:
	await get_tree().physics_frame
	_park_drone()
	_destroyed_events = 0
	_trauma_events = 0
	_disarms = 0
	_city_hp = CITY_HP
	var respawns_before := _local_respawns.size()

	_hull.apply_damage(200.0, Vector3(1.0, 2.0, 3.0))

	# 14 destroy
	if death == 0:
		expect(_destroyed_events == 1,
				"14 destroy: drone_destroyed se emitió %d veces, no 1" % _destroyed_events)
		expect_near(_hull.hp, 0.0, 0.001, "14 destroy: hp no quedó en 0")
		expect(_hull.is_destroyed(), "14 destroy: is_destroyed() no es true")
		expect(_drone.freeze, "14 destroy: el dron no quedó congelado")
		expect(not _drone.visible, "14 destroy: el dron quedó visible tras morir")
		expect(_disarms == 1, "14 destroy: force_disarm() no desarmó el dron")
		expect(not _drone.is_armed(), "14 destroy: el dron siguió armado tras morir")
		expect(_trauma_events >= 1, "14 destroy: no se pidió camera_trauma al morir")
		expect(_respawn.is_respawning(), "15 respawn_timing: is_respawning() no es true al morir")
		# Un segundo golpe no puede volver a emitir el hecho.
		_hull.apply_damage(50.0, Vector3.ZERO)
		expect(_destroyed_events == 1,
				"14 destroy: drone_destroyed se emitió dos veces por el mismo casco")
		var camera := get_respawn_camera()
		expect(camera != null and camera.current,
				"15 respawn_timing: no se pasó a la cámara de reconstrucción del nivel")
		_record("14 destroy .............. drone_destroyed ×%d · freeze %s · desarmes %d"
				% [_destroyed_events, str(_drone.freeze), _disarms])

	# 15/18: avance a 100 Hz con el mundo corriendo.
	var ticks := 0
	var paused_during := false
	var frames_before := Engine.get_physics_frames()
	while _local_respawns.size() == respawns_before and ticks < RESPAWN_MAX_TICKS:
		_tick()
		ticks += 1
		if get_tree().paused:
			paused_during = true
		if ticks == 600 and death == 0:
			# A mitad de la cuenta, comprobar que el árbol real sigue girando.
			await wait_physics(3)
	var elapsed := float(ticks) * PHYSICS_STEP
	expect(ticks < RESPAWN_MAX_TICKS, "15 respawn_timing: el respawn nunca llegó")
	expect_near(elapsed, DOC_RESPAWN_SECONDS, RESPAWN_TOLERANCE,
			"15 respawn_timing: el respawn tiene que llegar a los 12 s")
	expect(not paused_during, "18 city_suffers: el árbol se pausó durante el respawn")
	if death == 0:
		expect(Engine.get_physics_frames() > frames_before,
				"18 city_suffers: los frames de física reales no avanzaron durante el respawn")
		expect(CITY_HP - _city_hp >= CITY_LOSS_MIN,
				"18 city_suffers: el edificio de prueba solo perdió %.0f HP, mínimo %.0f"
				% [CITY_HP - _city_hp, CITY_LOSS_MIN])
		_record("18 city_suffers ......... edificio −%.0f HP · paused %s · frames +%d"
				% [CITY_HP - _city_hp, str(get_tree().paused),
				Engine.get_physics_frames() - frames_before])

	# 16 respawn_state
	if death == 0:
		expect_near(_hull.hp, DOC_MAX_HP, 0.001, "16 respawn_state: hp no volvió a 100")
		expect(not _hull.is_destroyed(), "16 respawn_state: el casco sigue marcado como destruido")
		expect_near(_energy.energy, DOC_RESPAWN_ENERGY, 0.001,
				"16 respawn_state: la energía no quedó en 60 %")
		expect(_respawn.get_reason() == RespawnController.Reason.HULL,
				"16 respawn_state: una muerte por casco tiene que dejar el motivo en HULL")
		# La otra mitad de la regla, medida en el sub-check 9: por batería son 30 %.
		expect_near(_measured_depleted_energy, DOC_RESPAWN_ENERGY_DEPLETED, 0.001,
				"16 respawn_state: por casco son 60 %% y por batería 30 %%, y el 9 midió %.2f %%"
				% _measured_depleted_energy)
		expect(not _drone.freeze, "16 respawn_state: el dron quedó congelado")
		expect(_drone.visible, "16 respawn_state: el dron quedó invisible")
		expect(_drone.linear_velocity.is_zero_approx(),
				"16 respawn_state: linear_velocity no quedó en cero")
		expect(_drone.angular_velocity.is_zero_approx(),
				"16 respawn_state: angular_velocity no quedó en cero")
		var target := _drone.respawn_point
		expect(target != null, "16 respawn_state: el dron no tiene respawn_point cableado")
		if target != null:
			expect(_drone.global_position.distance_to(target.global_position) < 0.01,
					"16 respawn_state: el dron reapareció en %v y no en %v"
					% [_drone.global_position, target.global_position])
		expect_near(_weapon.heat, 0.0, 0.001, "16 respawn_state: el arma no quedó fría")
		expect(not _weapon.is_overheated(), "16 respawn_state: el arma quedó bloqueada")
		expect(_weapon.get_locked_target() == null, "16 respawn_state: el arma quedó con lock")
		expect(not _drone.is_armed(), "16 respawn_state: el dron reapareció armado")
		var fpv := _rig.get_fpv_camera()
		expect(fpv != null and fpv.current,
				"16 respawn_state: no se volvió a la cámara FPV al reaparecer")
		_record("16 respawn_state ........ hp %.1f · energía %.1f %% por casco y %.1f %% por batería · pos %v · v %v"
				% [_hull.hp, _energy.energy, _measured_depleted_energy,
				_drone.global_position, _drone.linear_velocity])

	expect_near(_respawn.get_score_multiplier(), expected_multiplier, 0.001,
			"17 respawn_penalty: multiplicador tras la muerte %d" % (death + 1))
	expect(_respawn.get_death_count() == death + 1,
			"17 respawn_penalty: el contador de muertes es %d, esperado %d"
			% [_respawn.get_death_count(), death + 1])
	expect(not _respawn.is_respawning(),
			"15 respawn_timing: is_respawning() sigue en true tras reaparecer")
	expect_near(_respawn.get_remaining_seconds(), 0.0, 0.001,
			"15 respawn_timing: get_remaining_seconds() no quedó en 0")
	return elapsed


# --- 19 a 22. spawner -------------------------------------------------------------------------

func _check_spawner() -> void:
	await get_tree().physics_frame
	expect(_spawner.get_marker_count() == DOC_SPAWNER_MARKERS,
			"19 spawner_initial: hay %d marcadores, esperados %d"
			% [_spawner.get_marker_count(), DOC_SPAWNER_MARKERS])
	expect(_spawner.active_target == DOC_SPAWNER_ACTIVE,
			"19 spawner_initial: active_target es %d, esperado %d"
			% [_spawner.active_target, DOC_SPAWNER_ACTIVE])
	expect_near(_spawner.respawn_delay, DOC_SPAWNER_DELAY, 0.001,
			"20 spawner_refill: respawn_delay")
	expect(_spawner.clearance_mask == DOC_CLEARANCE_MASK,
			"21 spawner_clearance: clearance_mask es %d, esperado %d (capas 8|9)"
			% [_spawner.clearance_mask, DOC_CLEARANCE_MASK])

	_drive_spawner = true
	Global.round_seed = SEED_A
	_spawner.reset()
	var _ticks := _advance(1.0)
	expect(_spawner.get_active_count() == DOC_SPAWNER_ACTIVE,
			"19 spawner_initial: tras 1 s hay %d pilas activas, esperadas %d"
			% [_spawner.get_active_count(), DOC_SPAWNER_ACTIVE])
	_record("19 spawner_initial ...... %d activas de %d marcadores tras 1 s"
			% [_spawner.get_active_count(), _spawner.get_marker_count()])

	# 20 spawner_refill
	_energy.reset(DOC_MAX_ENERGY)
	var collected := _collect_active(2)
	expect(collected == 2, "20 spawner_refill: no se pudieron recoger dos pilas")
	expect(_spawner.get_active_count() == DOC_SPAWNER_ACTIVE - 2,
			"20 spawner_refill: tras recoger 2 quedan %d activas, esperadas 3"
			% _spawner.get_active_count())
	var mid_count := _spawner.get_active_count()

	# Antes de los 25 s no hay relleno.
	_ticks = _advance(DOC_SPAWNER_DELAY - 1.0)
	expect(_spawner.get_active_count() == DOC_SPAWNER_ACTIVE - 2,
			"20 spawner_refill: el relleno llegó antes de los 25 s (%d activas)"
			% _spawner.get_active_count())
	var peak := 0
	_ticks = _advance(2.0)
	peak = maxi(peak, _spawner.get_active_count())
	expect(_spawner.get_active_count() == DOC_SPAWNER_ACTIVE,
			"20 spawner_refill: a los 25 s no volvieron a haber 5 activas (%d)"
			% _spawner.get_active_count())

	# Nunca más de 5 por mucho que se espere.
	_ticks = _advance(60.0)
	peak = maxi(peak, _spawner.get_active_count())
	expect(peak <= DOC_SPAWNER_ACTIVE,
			"20 spawner_refill: el spawner llegó a %d activas, máximo %d"
			% [peak, DOC_SPAWNER_ACTIVE])
	_record("20 spawner_refill ....... 5 → %d tras recoger 2 → %d a los 25 s (pico %d)"
			% [mid_count, _spawner.get_active_count(), peak])

	# 21 spawner_clearance: 200 s recogiendo pilas sin parar.
	var cycles := int(CLEARANCE_SECONDS / DOC_SPAWNER_DELAY)
	for _cycle: int in cycles:
		var _got := _collect_active(DOC_SPAWNER_ACTIVE)
		_ticks = _advance(DOC_SPAWNER_DELAY + 1.0)
		_energy.reset(DOC_MAX_ENERGY)
	var used := _spawner.get_used_markers()
	expect(not used.has(BLOCKED_MARKER),
			"21 spawner_clearance: el marcador tapado por el cuerpo de capa 8 se usó igual")
	expect(used.size() == DOC_SPAWNER_MARKERS - 1,
			"21 spawner_clearance: se usaron %d marcadores de los %d libres"
			% [used.size(), DOC_SPAWNER_MARKERS - 1])
	expect(not _spawner.is_marker_active(BLOCKED_MARKER),
			"21 spawner_clearance: el marcador tapado terminó con pila activa")
	_record("21 spawner_clearance .... %d s · marcadores usados %s (tapado: %d)"
			% [CLEARANCE_SECONDS, str(used), BLOCKED_MARKER])

	# 22 spawner_determinism
	var run_a := _record_spawner_sequence()
	var run_b := _record_spawner_sequence()
	expect(run_a == run_b,
			"22 spawner_determinism: dos corridas con la misma semilla dieron secuencias distintas")
	expect(not run_a.is_empty(), "22 spawner_determinism: la secuencia salió vacía")

	# Y con otra semilla la secuencia tiene que poder cambiar: si no, el RNG no se usa.
	Global.round_seed = SEED_A + 7
	var run_c := _record_spawner_sequence_no_reseed()
	_record("22 spawner_determinism .. A=B (%s) · otra semilla → %s"
			% [str(run_a == run_b), str(run_c != run_a)])

	_drive_spawner = false
	Global.round_seed = _original_seed


## Recoge hasta [param count] pilas activas emitiendo `body_entered` con el dron.
func _collect_active(count: int) -> int:
	var taken := 0
	for index: int in _spawner.get_marker_count():
		if taken >= count:
			break
		if not _spawner.is_marker_active(index):
			continue
		var pickup := _spawner.get_pickup(index)
		if pickup == null:
			continue
		pickup.body_entered.emit(_drone)
		taken += 1
	return taken


## Reinicia el spawner con la semilla vigente y devuelve la secuencia de conjuntos
## de marcadores activos a lo largo de tres rellenos.
func _record_spawner_sequence() -> String:
	Global.round_seed = SEED_A
	return _record_spawner_sequence_no_reseed()


func _record_spawner_sequence_no_reseed() -> String:
	_spawner.reset()
	var steps: Array[String] = []
	var _ticks := _advance(1.0)
	steps.append(_active_mask())
	for _cycle: int in 3:
		var _got := _collect_active(2)
		_ticks = _advance(DOC_SPAWNER_DELAY + 1.0)
		steps.append(_active_mask())
	_energy.reset(DOC_MAX_ENERGY)
	return "|".join(steps)


func _active_mask() -> String:
	var mask := ""
	for index: int in _spawner.get_marker_count():
		mask += "1" if _spawner.is_marker_active(index) else "0"
	return mask


# --- 23. no_area_hitbox -----------------------------------------------------------------------

func _check_no_area_hitbox() -> void:
	var offenders: Array[String] = []
	var pickups := 0
	for node: Node in _descendants(self):
		var area := node as Area3D
		if area == null:
			continue
		if area.is_in_group(&"pickups"):
			pickups += 1
			continue
		offenders.append(area.get_path())
	expect(offenders.is_empty(),
			"23 no_area_hitbox: hay Area3D fuera del grupo pickups: %s" % str(offenders))
	var rig_areas := 0
	for node: Node in _descendants(_rig):
		if node is Area3D:
			rig_areas += 1
	expect(rig_areas == 0,
			"23 no_area_hitbox: el subárbol del dron tiene %d Area3D, esperados 0" % rig_areas)
	_record("23 no_area_hitbox ....... %d Area3D en el rig · %d pilas en el grupo pickups"
			% [rig_areas, pickups])


func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found


# --- 24. restore ------------------------------------------------------------------------------

func _check_restore() -> void:
	_energy.profile.critical_exit_ratio = _original_exit_ratio
	Global.round_seed = _original_seed
	# El disparo real del sub-check 4 deja viva la reproducción del
	# `AudioStreamPlayer3D` del arma. En `--headless` el driver falso nunca la
	# termina y Godot la reporta como instancia filtrada al cerrar el proceso.
	var fire_sound := _drone.get_node_or_null(^"WeaponMount/FireSound") as AudioStreamPlayer3D
	if fire_sound != null:
		fire_sound.stop()
	expect(Engine.physics_ticks_per_second == _original_ticks,
			"24 restore: se cambió Engine.physics_ticks_per_second y no se restauró")
	expect(Global.round_seed == _original_seed,
			"24 restore: Global.round_seed quedó en %d" % Global.round_seed)
	expect(not isolated_dir.is_empty(),
			"24 restore: el check tiene que correr con la configuración aislada")
	expect(Global.config_dir == isolated_dir,
			"24 restore: Global.config_dir no apunta a la carpeta aislada")
	expect(not DirAccess.dir_exists_absolute("user://config") \
			or DirAccess.get_files_at("user://config").is_empty() \
			or Global.config_dir != "user://config",
			"24 restore: el check escribió en la configuración del jugador")
	_record("24 restore .............. ticks %d · round_seed %d · config %s"
			% [Engine.physics_ticks_per_second, Global.round_seed, Global.config_dir])


func _print_measurements() -> void:
	print("  --- valores medidos (docs/09 §5) ---")
	for line: String in _measured:
		print("  %s" % line)


# --- Grabadoras -------------------------------------------------------------------------------

func _on_energy_changed(ratio: float, critical: bool) -> void:
	_energy_events += 1
	_energy_last_ratio = ratio
	_energy_last_critical = critical


func _on_hull_changed(ratio: float) -> void:
	_hull_events += 1
	_hull_last_ratio = ratio


func _on_drone_damaged(amount: float, source_position: Vector3) -> void:
	_damage_events += 1
	_damage_last_amount = amount
	_damage_last_source = source_position


func _on_drone_destroyed(at_position: Vector3) -> void:
	_destroyed_events += 1
	_destroyed_last = at_position


func _on_drone_respawned(score_multiplier: float) -> void:
	_bus_respawns.append(score_multiplier)


func _on_local_respawned(score_multiplier: float) -> void:
	_local_respawns.append(score_multiplier)


func _on_rig_respawned(score_multiplier: float) -> void:
	_rig_respawns.append(score_multiplier)


func _on_battery_collected(amount: float, at_position: Vector3) -> void:
	_battery_events += 1
	_battery_last_amount = amount
	_battery_last_position = at_position


func _on_camera_trauma(_amount: float, _at_position: Vector3) -> void:
	_trauma_events += 1


func _on_disarmed() -> void:
	_disarms += 1


func _on_arm_failed(reason_key: String) -> void:
	_arm_failures.append(reason_key)


func _on_critical_entered() -> void:
	_critical_enters += 1


func _on_critical_exited() -> void:
	_critical_exits += 1


func _on_energy_depleted() -> void:
	_depleted_events += 1


func _on_emp_hit(glitch_seconds: float) -> void:
	_emp_events += 1
	_emp_last_seconds = glitch_seconds
