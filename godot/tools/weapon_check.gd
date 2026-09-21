## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del arma primaria del dron (`docs/08` §5, `weapon_check`).
##
## Dispara el `drone_rig.tscn` completo contra cuatro cuerpos de prueba —capas 3,
## 4, 8 y 1— y verifica los 19 sub-checks de `docs/08` §5: cadencia, dispersión en
## frío y en ráfaga, calor y bloqueo, las cuatro filas de la tabla de resolución de
## impacto, el diccionario `hit`, el retroceso, las compuertas de energía y de
## armado, proyectiles huérfanos, trazadores, asistencia de puntería y lock.
##
## Corre así:
##
##     godot --headless --path godot res://tools/weapon_check.tscn -- --timeout=240
##
## Con `-- --negative` corrompe a propósito `weak_point_multiplier` para demostrar
## que el check detecta la regresión: tiene que salir en rojo.
##
## Tres decisiones de método que valen para cualquier check que dispare este rig:
##
## - **El tiempo se avanza en ticks de física reales**, no llamando a
##   `_physics_process()` a mano. `docs/08` §5 propone lo segundo, pero la
##   resolución de impactos necesita un `PhysicsDirectSpaceState3D` válido, y
##   consultarlo fuera del paso de física de Jolt da «Can't change this state while
##   flushing queries». A 100 Hz cada tick vale exactamente 0.01 s, así que el
##   avance sigue siendo determinista y contado, que es lo que la regla pide.
## - **El dron se reinicia antes de cada disparo medido** con
##   [method Drone.reset_to]. Está armado, así que cae: sin el reinicio, entre
##   colocar el blanco y que la bala llegue el cañón ya se habría movido metros y
##   el disparo erraría por geometría, no por un fallo del arma.
## - **Los blancos se colocan a lo largo de la puntería real**
##   (`−FPVCamera.global_basis.z`), no en una posición fija. La cámara va inclinada
##   por el ángulo del hangar (`docs/03` §5), que es configuración del jugador: una
##   posición fija ataría el check a un valor de `QuadSettings`.
extends CheckRunner

## Paso de física nominal, en segundos.
const PHYSICS_STEP: float = 0.01

## Distancia a la que se ponen los blancos, en metros.
const TARGET_DISTANCE: float = 50.0

## Lado de los blancos, en metros. A 50 m un cubo de 4 m cubre ±2.3°, muy por
## encima de la dispersión en frío (0.35°).
const TARGET_SIZE: float = 4.0

## Aparcadero de los blancos: lejos de cualquier trayectoria.
const PARKED: Vector3 = Vector3(0.0, -5000.0, 0.0)

## Disparos de la prueba de cadencia y de dispersión.
const CADENCE_SHOTS: int = 100

## Cadencia nominal, en disparos por segundo.
const NOMINAL_RATE: float = 8.0

## Tolerancia de la cadencia, en fracción.
const RATE_TOLERANCE: float = 0.05

## Ticks nominales entre disparos a 8/s y 100 Hz.
const NOMINAL_INTERVAL_TICKS: float = 12.5

## Disparos de la prueba de retroceso.
const RECOIL_SHOTS: int = 20

## Disparos por tick durante la prueba de retroceso: repartirlos evita cruzar el
## umbral de choque del dron (6 m/s de `Δv` por tick) y disparar `crashed`.
const RECOIL_SHOTS_PER_TICK: int = 2

## Tolerancia del retroceso, en fracción.
const RECOIL_TOLERANCE: float = 0.10

## Ticks que se le dan a una bala para recorrer [constant TARGET_DISTANCE] y
## resolver: 50 m a 420 m/s son 12 ticks; 20 dan margen.
const FLIGHT_TICKS: int = 20

## Ticks de asentamiento tras reiniciar el dron.
const SETTLE_TICKS: int = 3

## Trazadores vivos que pide el sub-check 14.
const TRACER_SAMPLE: int = 6

## Disparos con los que se mide la proporción de trazadores.
const TRACER_RATIO_SHOTS: int = 30

## Ángulo de prueba de la asistencia, en grados (`docs/08` §5, sub-check 15).
const ASSIST_ANGLE_DEG: float = 3.0

## Distancia del blanco de la asistencia, en metros.
const ASSIST_DISTANCE: float = 60.0

## Ángulo fuera del cono de 3.5° con el que se comprueba el descarte.
const ASSIST_OUTSIDE_DEG: float = 5.0

## Emisiones máximas de `Events.weapon_heat_changed` en la prueba de calor.
const HEAT_EVENT_BUDGET: int = 120

## Valores del **Anexo C** (`docs/08` §4 y §5) escritos a mano.
##
## Están duplicados a propósito: si el check midiera contra `profile.damage *
## profile.weak_point_multiplier` sería tautológico —un perfil con el multiplicador
## roto pasaría igual—. Acá el perfil es lo que se verifica, no la vara de medir.
const DOC_DAMAGE: float = 16.0
const DOC_WEAK_MULTIPLIER: float = 3.0
const DOC_ARMOR: float = 0.90
const DOC_EFFECTIVE_ARMOR_DAMAGE: float = 1.6
const DOC_WEAK_DAMAGE: float = 48.0
const DOC_CITY_SCALE: float = 0.375
const DOC_CITY_DAMAGE: float = 6.0
const DOC_HEAT_PER_SHOT: float = 0.045
const DOC_OVERHEAT_LOCK: float = 1.8
const DOC_OVERHEAT_RELEASE: float = 0.35
const DOC_RECOIL_IMPULSE: float = 0.9
const DOC_SPREAD_BASE_DEG: float = 0.35
const DOC_SPREAD_MAX_DEG: float = 2.2
const DOC_ASSIST_STRENGTH: float = 0.35
const DOC_POOL_SIZE: int = 256

var _rig: DroneRig = null
var _drone: Drone = null
var _radio: RadioController = null
var _camera_rig: CameraRig = null
var _weapon: WeaponMount = null
var _pool: ProjectilePool = null
var _fx: ImpactFXPool = null
var _tracers: TracerRenderer = null
var _profile: WeaponProfile = null

var _part: WeaponCheckStubs.PartStub = null
var _weak: WeaponCheckStubs.PartStub = null
var _building: WeaponCheckStubs.BuildingStub = null
var _world: StaticBody3D = null
var _energy: WeaponCheckStubs.EnergyStub = null
var _markers: Array[Node3D] = []
var _targets_root: Node3D = null

var _tick: int = 0
var _shot_ticks: PackedInt32Array = PackedInt32Array()
var _shot_angles: PackedFloat32Array = PackedFloat32Array()
var _shot_count: int = 0
var _hits: Array[Dictionary] = []
var _heat_events: Array[Vector2] = []
var _overheat_tick: int = -1
var _cool_tick: int = -1
var _overheat_shots: int = -1
var _cool_heat: float = -1.0
var _saved_aim_assist: int = 0
var _saved_camera_offset: Vector3 = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	_tick += 1


func _run() -> void:
	_collect_nodes()
	if not failures.is_empty():
		return
	await _prepare()
	await _check_cadence_and_spread()
	await _check_heat()
	await _check_damage_layer_3()
	await _check_damage_layer_4()
	await _check_damage_layer_8()
	await _check_damage_layer_1()
	await _check_recoil()
	await _check_energy_gate()
	await _check_disarmed_gate()
	await _check_orphans()
	await _check_tracers()
	await _check_aim_assist()
	await _check_lock()
	await _check_no_self_hit()
	await _check_restore()


# --- Preparación -----------------------------------------------------------------------------


func _collect_nodes() -> void:
	_rig = get_node_or_null(^"DroneRig") as DroneRig
	if _rig == null:
		fail("falta el nodo 'DroneRig' en la escena del check")
		return
	_drone = _rig.get_drone()
	_radio = _rig.get_radio()
	_camera_rig = _rig.get_camera_rig()
	_weapon = _rig.get_weapon_mount()
	_pool = get_node_or_null(^"ProjectilePool") as ProjectilePool
	_fx = get_node_or_null(^"ImpactFXPool") as ImpactFXPool
	_targets_root = get_node_or_null(^"Targets") as Node3D
	if _drone == null:
		fail("el rig no tiene dron")
	if _weapon == null:
		fail("el dron no tiene 'WeaponMount' (docs/08 §3.1)")
	if _pool == null:
		fail("falta el nodo 'ProjectilePool' en la escena del check")
	if _fx == null:
		fail("falta el nodo 'ImpactFXPool' en la escena del check")
	if _targets_root == null:
		fail("falta el nodo 'Targets' en la escena del check")


## Deja el banco listo: radio apagada, dron armado, perfil de trabajo duplicado,
## blancos creados y aparcados, y telemetría conectada al bus.
func _prepare() -> void:
	_saved_aim_assist = int(GameSettings.aim_assist)
	_saved_camera_offset = _camera_rig.position if _camera_rig != null else Vector3.ZERO
	GameSettings.aim_assist = GameSettings.AimAssist.OFF

	_radio.enabled = false
	_weapon.set_projectile_pool(_pool)
	# Perfil de trabajo: el `.tres` del juego es un recurso compartido y el check
	# necesita tocar `heat_per_shot`, `recoil_impulse` y `tracer_every`. Duplicarlo
	# deja el archivo del proyecto intacto.
	_profile = _weapon.get_profile().duplicate() as WeaponProfile
	_check_profile_values()
	_weapon.set_profile(_profile)
	_pool.set_profile(_profile)
	_tracers = _pool.tracer_renderer

	_build_targets()
	_stand_down_wp15_systems()
	_energy = WeaponCheckStubs.EnergyStub.new()
	_energy.name = "EnergySystem"
	_drone.add_child(_energy)
	_weapon.refresh_energy_system()

	var _discard := Events.shot_fired.connect(_on_shot_fired)
	_discard = Events.hit_confirmed.connect(_on_hit_confirmed)
	_discard = Events.weapon_heat_changed.connect(_on_heat_changed)
	_discard = _weapon.overheated.connect(_on_overheated)
	_discard = _weapon.cooled.connect(_on_cooled)

	if user_args().has("negative"):
		# Prueba negativa: con el multiplicador en 1.0 el punto débil recibe 16 en
		# vez de 48 y el sub-check 7 tiene que ponerse rojo.
		print("  (modo negativo: weak_point_multiplier forzado a 1.0)")
		_profile.weak_point_multiplier = 1.0

	await _reset_drone()
	var armed := _drone.arm()
	expect(armed, "el dron no se pudo armar para el check")
	expect(_weapon.energy_system == _energy,
			"WeaponMount no encontró el 'EnergySystem' por duck typing (docs/09 §2)")
	await _step(SETTLE_TICKS)


## Saca del banco el `EnergySystem` y el `Hull` reales que WP-15 agregó a
## `drone_quad.tscn` (`docs/09` §3.1).
##
## Nota de WP-15 (2026-09-19). Ninguno de los dos es lo que este check prueba, y
## los dos lo rompían:
##
## - El `EnergySystem` real se queda con el nombre `EnergySystem`, así que el doble
##   de [WeaponCheckStubs] pasaba a llamarse `EnergySystem2` y
##   `WeaponMount._find_energy_system()` devolvía el real. El sub-check 11 dejaba
##   de poder rechazar un cobro y el arma disparaba igual.
## - El `Hull` real escucha `body_entered` del dron. El banco deja caer el dron
##   desde 400 m, así que el primer impacto contra el suelo lo destruía: el
##   `RespawnController` lo congelaba 12 s y todos los disparos posteriores
##   quedaban bloqueados por la compuerta de «dron armado».
##
## Se liberan en vez de desactivarse porque lo que hace falta es que el nombre
## quede libre y que la conexión a `body_entered` desaparezca; un
## `set_physics_process(false)` no consigue ninguna de las dos cosas. `docs/09`
## tiene su propio banco, `energy_check`, que sí los prueba enteros.
func _stand_down_wp15_systems() -> void:
	for child_name: StringName in [&"EnergySystem", &"Hull"]:
		var node := _drone.get_node_or_null(NodePath(child_name))
		if node == null:
			continue
		_drone.remove_child(node)
		node.queue_free()


## Sub-check 0: el `.tres` del MVP lleva los valores cerrados del Anexo C
## (`docs/08` §4). Corre **antes** de que el modo negativo toque nada.
func _check_profile_values() -> void:
	print("-- 0 profile (Anexo C)")
	expect_near(_profile.fire_rate, NOMINAL_RATE, 0.0001, "fire_rate del perfil")
	expect_near(_profile.damage, DOC_DAMAGE, 0.0001, "damage del perfil")
	expect_near(_profile.weak_point_multiplier, DOC_WEAK_MULTIPLIER, 0.0001,
			"weak_point_multiplier del perfil")
	expect_near(_profile.spread_base_deg, DOC_SPREAD_BASE_DEG, 0.0001,
			"spread_base_deg del perfil")
	expect_near(_profile.spread_max_deg, DOC_SPREAD_MAX_DEG, 0.0001,
			"spread_max_deg del perfil")
	expect_near(_profile.heat_per_shot, DOC_HEAT_PER_SHOT, 0.0001, "heat_per_shot del perfil")
	expect_near(_profile.overheat_lock, DOC_OVERHEAT_LOCK, 0.0001, "overheat_lock del perfil")
	expect_near(_profile.overheat_release, DOC_OVERHEAT_RELEASE, 0.0001,
			"overheat_release del perfil")
	expect_near(_profile.recoil_impulse, DOC_RECOIL_IMPULSE, 0.0001, "recoil_impulse del perfil")
	expect_near(_profile.city_friendly_fire_scale, DOC_CITY_SCALE, 0.0001,
			"city_friendly_fire_scale del perfil")
	expect_near(_profile.aim_assist_strength, DOC_ASSIST_STRENGTH, 0.0001,
			"aim_assist_strength del perfil")
	expect(_profile.pool_size == DOC_POOL_SIZE, "pool_size del perfil")
	expect(_profile.hit_mask == PhysicsLayers.QUERY_SHOT,
			"hit_mask = %d, se esperaba QUERY_SHOT = %d"
			% [_profile.hit_mask, PhysicsLayers.QUERY_SHOT])
	expect(_profile.los_mask == PhysicsLayers.QUERY_LOS,
			"los_mask = %d, se esperaba QUERY_LOS = %d"
			% [_profile.los_mask, PhysicsLayers.QUERY_LOS])
	print("   profile = 8/s · 16 daño · ×3.0 · calor 0.045 · bloqueo 1.8 s · retroceso 0.9 N·s"
			+ " · máscaras %d/%d" % [_profile.hit_mask, _profile.los_mask])


func _build_targets() -> void:
	_part = WeaponCheckStubs.PartStub.new()
	_part.name = "PartBody"
	_part.armor = DOC_ARMOR
	_part.sync_to_physics = false
	_part.collision_layer = PhysicsLayers.ENEMY_BODY
	_part.collision_mask = 0
	_part.set_meta(&"part_id", &"wc_armor")
	_add_body(_part)

	_weak = WeaponCheckStubs.PartStub.new()
	_weak.name = "WeakBody"
	# La parte que hospeda un punto débil expuesto tiene `armor = 0.0`
	# (`docs/08` §2.7, requisito sobre `docs/06`): el arma aplica el ×3.0 y la
	# parte no absorbe nada, así que el impacto vale 48 y no 4.8.
	_weak.armor = 0.0
	_weak.sync_to_physics = false
	_weak.collision_layer = PhysicsLayers.ENEMY_WEAK
	_weak.collision_mask = 0
	_weak.set_meta(&"part_id", &"wc_head")
	_weak.set_meta(&"weak_point_id", &"wc_visor")
	_weak.add_to_group(WeaponAimAssist.GROUP)
	_add_body(_weak)

	_building = WeaponCheckStubs.BuildingStub.new()
	_building.name = "CityBody"
	_building.collision_layer = PhysicsLayers.CITY
	_building.collision_mask = 0
	_add_body(_building)

	_world = StaticBody3D.new()
	_world.name = "WorldBody"
	_world.collision_layer = PhysicsLayers.WORLD
	_world.collision_mask = 0
	_add_body(_world)


func _add_body(body: CollisionObject3D) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TARGET_SIZE, TARGET_SIZE, TARGET_SIZE)
	shape.shape = box
	body.add_child(shape)
	_targets_root.add_child(body)
	body.global_position = PARKED


# --- 1, 2 y 3: cadencia y dispersión ---------------------------------------------------------


## Sub-checks 1 (`cadence`), 2 (`spread_cold`) y 3 (`spread_growth`).
##
## Los tres salen de la misma ráfaga sostenida con `heat_per_shot = 0` —que es lo
## que `docs/08` §5 pide para aislar la cadencia del bloqueo— más un disparo suelto
## desde frío antes de empezar.
func _check_cadence_and_spread() -> void:
	print("-- 1/2/3 cadence · spread_cold · spread_growth")
	_profile.heat_per_shot = 0.0
	_profile.recoil_impulse = 0.0
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	await _step(SETTLE_TICKS)

	# Sub-check 2: un disparo desde frío, con el acumulador de ráfaga en cero.
	_begin_capture()
	var cold := _weapon.fire()
	expect(cold, "el disparo en frío no salió")
	await _step(1)
	expect(_shot_count == 1, "el disparo en frío emitió %d shot_fired" % _shot_count)
	if _shot_angles.size() > 0:
		expect(_shot_angles[0] <= DOC_SPREAD_BASE_DEG + 0.001,
				"dispersión en frío %.4f° > %.2f°" % [_shot_angles[0], DOC_SPREAD_BASE_DEG])
		print("   spread_cold = %.4f° (tope %.2f°)" % [_shot_angles[0], DOC_SPREAD_BASE_DEG])

	# Sub-checks 1 y 3: ráfaga sostenida de 100 disparos.
	_weapon.reset()
	await _step(SETTLE_TICKS)
	_begin_capture()
	_weapon.fire_pressed = true
	var guard := 0
	while _shot_count < CADENCE_SHOTS and guard < CADENCE_SHOTS * 40:
		await _step(1)
		guard += 1
	_weapon.fire_pressed = false
	await _step(1)

	expect(_shot_count >= CADENCE_SHOTS,
			"la ráfaga sostenida dio %d disparos de %d" % [_shot_count, CADENCE_SHOTS])
	if _shot_ticks.size() < 2:
		fail("no hay intervalos que medir")
		return

	var span := float(_shot_ticks[_shot_ticks.size() - 1] - _shot_ticks[0])
	var mean_ticks := span / float(_shot_ticks.size() - 1)
	var rate := 1.0 / (mean_ticks * PHYSICS_STEP)
	expect_near(rate, NOMINAL_RATE, NOMINAL_RATE * RATE_TOLERANCE,
			"cadencia sostenida fuera del ±5 %")
	var worst := 0
	for index: int in range(1, _shot_ticks.size()):
		worst = maxi(worst, absi(_shot_ticks[index] - _shot_ticks[index - 1]
				- int(NOMINAL_INTERVAL_TICKS)))
	expect(worst <= 1, "algún intervalo se desvió %d ticks de los 12–13 nominales" % worst)
	print("   cadence = %.3f disp/s (%.2f ticks de intervalo medio, desvío máx %d ticks)"
			% [rate, mean_ticks, worst])

	var first := _mean_angle(0, 10)
	var last := _mean_angle(_shot_angles.size() - 10, 10)
	var peak := 0.0
	for angle: float in _shot_angles:
		peak = maxf(peak, angle)
	expect(last > first, "la dispersión no creció en ráfaga (%.4f° → %.4f°)" % [first, last])
	expect(peak <= DOC_SPREAD_MAX_DEG + 0.01,
			"la dispersión superó el tope: %.4f° > %.2f°" % [peak, DOC_SPREAD_MAX_DEG])
	print("   spread_growth = %.4f° (10 primeros) → %.4f° (10 últimos), pico %.4f° (tope %.2f°)"
			% [first, last, peak, DOC_SPREAD_MAX_DEG])
	_profile.heat_per_shot = 0.045


# --- 4 y 5: calor, bloqueo y evento ----------------------------------------------------------


## Sub-checks 4 (`heat_lock`) y 5 (`heat_event`).
func _check_heat() -> void:
	print("-- 4/5 heat_lock · heat_event")
	_profile.recoil_impulse = 0.0
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	await _step(SETTLE_TICKS)

	_begin_capture()
	_overheat_tick = -1
	_cool_tick = -1
	_overheat_shots = -1
	_heat_events.clear()
	_weapon.fire_pressed = true
	var guard := 0
	while _overheat_tick < 0 and guard < 600:
		await _step(1)
		guard += 1
	expect(_overheat_tick >= 0, "el arma no se bloqueó por calor")
	if _overheat_tick < 0:
		_weapon.fire_pressed = false
		return

	expect(_overheat_shots >= 22 and _overheat_shots <= 23,
			"el bloqueo llegó al disparo %d, fuera de [22, 23]" % _overheat_shots)
	expect(_weapon.is_overheated(), "is_overheated() no quedó en true tras el bloqueo")
	expect(not _weapon.fire(), "fire() salió durante el bloqueo")
	var shots_at_lock := _shot_count
	await _step(20)
	expect(_shot_count == shots_at_lock,
			"salieron %d disparos durante el bloqueo" % (_shot_count - shots_at_lock))

	guard = 0
	while _cool_tick < 0 and guard < 600:
		await _step(1)
		guard += 1
	_weapon.fire_pressed = false
	expect(_cool_tick >= 0, "el arma no salió del bloqueo")
	if _cool_tick < 0:
		return

	var lock_seconds := float(_cool_tick - _overheat_tick) * PHYSICS_STEP
	expect_near(lock_seconds, DOC_OVERHEAT_LOCK, 0.05,
			"la duración del bloqueo se fue de los 1.8 s")
	expect(_cool_heat <= DOC_OVERHEAT_RELEASE + 0.001,
			"al desbloquear el calor quedó en %.4f > %.2f"
			% [_cool_heat, DOC_OVERHEAT_RELEASE])
	print("   heat_lock = disparo %d, bloqueo %.3f s, calor al salir %.4f"
			% [_overheat_shots, lock_seconds, _cool_heat])

	var saw_locked := false
	var saw_released := false
	for event: Vector2 in _heat_events:
		if event.y > 0.5:
			saw_locked = true
		elif saw_locked:
			saw_released = true
	expect(saw_locked, "no se emitió weapon_heat_changed con overheated = true")
	expect(saw_released, "no se emitió weapon_heat_changed con overheated = false tras el bloqueo")
	expect(_heat_events.size() <= HEAT_EVENT_BUDGET,
			"weapon_heat_changed se emitió %d veces (presupuesto %d)"
			% [_heat_events.size(), HEAT_EVENT_BUDGET])
	print("   heat_event = %d emisiones, con bloqueo y desbloqueo" % _heat_events.size())


# --- 6, 7 y 7b: daño a las capas 3 y 4 -------------------------------------------------------


## Sub-check 6 (`damage_layer_3`): blindaje 0.90 → 16 brutos, 1.6 efectivos.
func _check_damage_layer_3() -> void:
	print("-- 6 damage_layer_3")
	_part.reset()
	await _shoot_at(_part)
	expect(_part.hits == 1, "la parte blindada recibió %d impactos" % _part.hits)
	if _part.hits == 0:
		return
	expect_near(_part.last_amount, DOC_DAMAGE, 0.01,
			"el arma no pasó los 16 de daño base a la capa 3")
	expect_near(_part.last_effective, DOC_EFFECTIVE_ARMOR_DAMAGE, 0.01,
			"el daño efectivo con blindaje 0.90 no es 1.6")
	expect_near(_pool.get_last_effective_damage(), DOC_EFFECTIVE_ARMOR_DAMAGE, 0.01,
			"el pool no recogió el daño efectivo que devolvió take_damage()")
	expect(not bool(_part.last_hit.get(&"is_weak_point", true)),
			"hit['is_weak_point'] no es false en la capa 3")
	expect(not _hits.is_empty(), "no se emitió hit_confirmed en la capa 3")
	if not _hits.is_empty():
		var last: Dictionary = _hits[_hits.size() - 1]
		expect(WeaponMount.hit_kind(bool(last["weak"]), bool(last["lethal"]))
				== WeaponMount.HitKind.ARMOR, "el HitKind de la capa 3 no es ARMOR")
		expect(StringName(last["surface"]) == &"armor",
				"hit_confirmed.surface en la capa 3: esperado='armor' medido='%s'"
				% String(last["surface"]))
	print("   damage_layer_3 = %.3f brutos → %.3f efectivos"
			% [_part.last_amount, _part.last_effective])
	_check_hit_dict(_part.last_hit, false)


## Sub-check 7 (`damage_layer_4`) y la parte letal: ×3.0 → 48 brutos y 48 efectivos.
func _check_damage_layer_4() -> void:
	print("-- 7 damage_layer_4")
	_weak.reset()
	_weak.hp = 10000.0
	await _shoot_at(_weak)
	expect(_weak.hits == 1, "el punto débil recibió %d impactos" % _weak.hits)
	if _weak.hits == 0:
		return
	expect_near(_weak.last_amount, DOC_WEAK_DAMAGE, 0.01,
			"el arma no pasó los 48 (16 × 3.0) a la capa 4")
	expect_near(_weak.last_effective, DOC_WEAK_DAMAGE, 0.01,
			"el daño efectivo en la capa 4 no es 48 (la parte hospedadora tiene armor 0.0)")
	expect(bool(_weak.last_hit.get(&"is_weak_point", false)),
			"hit['is_weak_point'] no es true en la capa 4")
	expect(_weak.last_hit.has(&"weak_point_id"),
			"falta hit['weak_point_id'] en la capa 4")
	var confirmed: Dictionary = _hits[_hits.size() - 1] if not _hits.is_empty() else {}
	expect(bool(confirmed.get("weak", false)), "hit_confirmed no marcó weak en la capa 4")
	expect(StringName(confirmed.get("surface", &"")) == &"weak",
			"hit_confirmed.surface en la capa 4: esperado='weak' medido='%s'"
			% String(confirmed.get("surface", &"")))
	expect(WeaponMount.hit_kind(true, false) == WeaponMount.HitKind.WEAK,
			"el HitKind de un punto débil sano no es WEAK")
	print("   damage_layer_4 = %.3f brutos → %.3f efectivos"
			% [_weak.last_amount, _weak.last_effective])
	_check_hit_dict(_weak.last_hit, true)

	# Letalidad: con la estructura casi agotada el mismo impacto rompe la parte y
	# `hit_confirmed` tiene que llegar con `lethal = true`.
	_weak.reset()
	_weak.hp = 1.0
	await _shoot_at(_weak)
	expect(_weak.hits == 1, "el impacto letal no llegó")
	var lethal: Dictionary = _hits[_hits.size() - 1] if not _hits.is_empty() else {}
	expect(bool(lethal.get("lethal", false)),
			"hit_confirmed no marcó lethal tras romper la parte")
	expect(WeaponMount.hit_kind(true, true) == WeaponMount.HitKind.PART_BROKEN,
			"el HitKind de una parte rota no es PART_BROKEN")
	_weak.hp = 10000.0
	print("   lethal = %s" % str(bool(lethal.get("lethal", false))))


## Sub-check 7b (`hit_dict`): exactamente las claves del contrato de `docs/06` §14.1.
func _check_hit_dict(hit: Dictionary, weak: bool) -> void:
	var required: Array[StringName] = [&"position", &"normal", &"direction", &"source",
			&"is_weak_point", &"damage_type"]
	for key: StringName in required:
		expect(hit.has(key), "el diccionario hit no trae la clave '%s'" % String(key))
	for key: Variant in hit.keys():
		expect(ProjectilePool.HIT_KEYS.has(key),
				"el diccionario hit trae la clave extra '%s' (docs/06 §14.1)" % str(key))
	if weak:
		expect(hit.has(&"weak_point_id"),
				"falta 'weak_point_id' en un impacto de punto débil")
	else:
		expect(not hit.has(&"weak_point_id"),
				"'weak_point_id' aparece en un impacto que no es de punto débil")
	expect(hit.get(&"source") == _weapon, "hit['source'] no es el WeaponMount emisor")
	expect(hit.get(&"damage_type") == &"kinetic", "hit['damage_type'] no es &\"kinetic\"")
	var direction := hit.get(&"direction", Vector3.ZERO) as Vector3
	expect_near(direction.length(), 1.0, 0.001, "hit['direction'] no llega normalizada")
	print("   hit_dict = %d claves, todas del contrato" % hit.size())


# --- 8: ciudad --------------------------------------------------------------------------------


## Sub-check 8 (`damage_layer_8`): `damage × city_friendly_fire_scale` y acumulador
## de fuego amigo.
func _check_damage_layer_8() -> void:
	print("-- 8 damage_layer_8")
	_building.reset()
	_pool.reset_friendly_fire()
	var expected := DOC_CITY_DAMAGE
	var shots := 3
	for _i: int in shots:
		await _shoot_at(_building)
	expect(_building.hits == shots, "el edificio recibió %d de %d impactos"
			% [_building.hits, shots])
	expect_near(_building.last_amount, expected, 0.01,
			"el daño estructural no es damage × city_friendly_fire_scale")
	expect_near(_pool.get_friendly_fire_damage(), expected * float(shots), 0.01,
			"get_friendly_fire_damage() no acumula el daño aplicado")
	var city_hit: Dictionary = _hits[_hits.size() - 1] if not _hits.is_empty() else {}
	expect(StringName(city_hit.get("surface", &"")) == &"city",
			"hit_confirmed.surface en la capa 8: esperado='city' medido='%s'"
			% String(city_hit.get("surface", &"")))
	print("   damage_layer_8 = %.3f por impacto, %.3f acumulados en %d impactos"
			% [_building.last_amount, _pool.get_friendly_fire_damage(), _building.hits])


# --- 9: mundo ---------------------------------------------------------------------------------


## Sub-check 9 (`damage_layer_1`): cero daño y exactamente un decal.
func _check_damage_layer_1() -> void:
	print("-- 9 damage_layer_1")
	_part.reset()
	_building.reset()
	_fx.clear()
	var decals_before := _fx.get_decal_requests()
	await _shoot_at(_world)
	var requested := _fx.get_decal_requests() - decals_before
	expect(requested == 1, "la capa 1 pidió %d decals en vez de 1" % requested)
	expect(_part.hits == 0 and _building.hits == 0,
			"un impacto en la capa 1 aplicó daño a alguien")
	# `_shoot_at` reinicia la captura, así que `_hits` sólo puede traer el impacto
	# de este disparo. La capa 1 no tiene `HitKind` (`docs/08` §2.7): no publica.
	expect(_hits.is_empty(),
			"la capa 1 emitió hit_confirmed (no tiene HitKind, docs/08 §2.7)")
	# La cuarta superficie de `Events.hit_confirmed` **no puede** llegar por el
	# bus, justamente porque la capa 1 no confirma. Lo que sí se puede aseverar es
	# la tabla completa de `ProjectilePool.surface_for`, que es de donde sale el
	# valor que viaja en las otras tres.
	var mapping: Array[Array] = [
		[PhysicsLayers.ENEMY_WEAK, true, true, &"weak"],
		[PhysicsLayers.ENEMY_BODY, false, true, &"armor"],
		[PhysicsLayers.CITY, false, false, &"city"],
		[PhysicsLayers.WORLD, false, false, &"world"],
		[PhysicsLayers.DEBRIS, false, false, &"world"],
		[PhysicsLayers.ENEMY_BODY, false, false, &"world"],
	]
	for row: Array in mapping:
		var got := ProjectilePool.surface_for(int(row[0]), bool(row[1]), bool(row[2]))
		expect(got == row[3],
				"surface_for(capa %d, weak=%s, parte=%s): esperado='%s' medido='%s'"
				% [int(row[0]), row[1], row[2], String(row[3]), String(got)])
	print("   damage_layer_1 = 0 daño, %d decal; surface_for cubre las 4 superficies"
			% requested)


# --- 10: retroceso ----------------------------------------------------------------------------


## Sub-check 10 (`recoil`): `Δv = −aim · recoil_impulse · n / masa`.
##
## Se mide **contra una línea base**: la misma ventana de ticks sin disparar. Así
## la gravedad, el arrastre y el empuje de ralentí se cancelan y lo que queda es
## sólo el retroceso, que es lo que el sub-check afirma.
func _check_recoil() -> void:
	print("-- 10 recoil")
	_profile.recoil_impulse = DOC_RECOIL_IMPULSE
	_park_targets()
	var ticks := RECOIL_SHOTS / RECOIL_SHOTS_PER_TICK

	await _reset_drone()
	_weapon.reset()
	await _step(SETTLE_TICKS)
	var aim := _weapon.get_raw_aim_direction()
	var baseline_start := _drone.linear_velocity
	await _step(ticks)
	var baseline := _drone.linear_velocity - baseline_start

	await _reset_drone()
	_weapon.reset()
	await _step(SETTLE_TICKS)
	aim = _weapon.get_raw_aim_direction()
	var start := _drone.linear_velocity
	var fired := 0
	for _i: int in ticks:
		for _shot: int in RECOIL_SHOTS_PER_TICK:
			if _weapon.fire():
				fired += 1
		await _step(1)
	var measured := _drone.linear_velocity - start - baseline

	expect(fired == RECOIL_SHOTS, "salieron %d de %d disparos de retroceso"
			% [fired, RECOIL_SHOTS])
	var expected := float(fired) * DOC_RECOIL_IMPULSE / _drone.mass
	var along := measured.dot(-aim)
	expect(_drone.linear_velocity.dot(aim) < 0.0,
			"el retroceso no empuja al dron hacia atrás (docs/08 §2.5)")
	expect_near(along, expected, expected * RECOIL_TOLERANCE,
			"el retroceso acumulado se fue del ±10 %")
	print("   recoil = %.3f m/s medidos contra %.3f m/s esperados (%d disparos, %.2f kg)"
			% [along, expected, fired, _drone.mass])
	_profile.recoil_impulse = 0.0


# --- 11 y 12: compuertas ----------------------------------------------------------------------


## Sub-check 11 (`energy_gate`): con `consume()` en `false` no sale nada.
func _check_energy_gate() -> void:
	print("-- 11 energy_gate")
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	await _step(SETTLE_TICKS)
	_pool.clear()
	_energy.reset()
	_energy.allow = false
	_begin_capture()
	var before := _pool.get_active_count()
	var ok := _weapon.fire()
	await _step(2)
	expect(not ok, "fire() salió con la energía agotada")
	expect(_shot_count == 0, "se emitió shot_fired con la energía agotada")
	expect(_pool.get_active_count() == before,
			"se creó un proyectil con la energía agotada")
	expect(_energy.consumed == 0.0,
			"se consumió energía en un disparo rechazado (docs/08 §2.2)")
	expect(_energy.calls > 0, "el arma no le preguntó al EnergySystem")

	_energy.allow = true
	_energy.reset()
	_begin_capture()
	var ok_now := _weapon.fire()
	await _step(2)
	expect(ok_now, "fire() no salió con energía disponible")
	expect_near(_energy.consumed, _profile.energy_per_shot, 0.0001,
			"el arma no cobró energy_per_shot")
	print("   energy_gate = rechazo sin consumo, cobro de %.3f por disparo"
			% _energy.consumed)


## Sub-check 12 (`disarmed_gate`): desarmado no se dispara.
func _check_disarmed_gate() -> void:
	print("-- 12 disarmed_gate")
	_drone.force_disarm()
	await _step(2)
	_begin_capture()
	var ok := _weapon.fire()
	await _step(2)
	expect(not ok, "fire() salió con el dron desarmado")
	expect(_shot_count == 0, "se emitió shot_fired con el dron desarmado")
	var armed := _drone.arm()
	expect(armed, "el dron no se pudo volver a armar")
	await _step(SETTLE_TICKS)
	print("   disarmed_gate = fire() devolvió false")


# --- 14: trazadores ---------------------------------------------------------------------------


## Sub-check 14 (`tracers`): una sola llamada de dibujo, datos por instancia y
## proporción 1 de cada 3.
func _check_tracers() -> void:
	print("-- 14 tracers")
	var renderers := _count_multimesh(_pool)
	expect(renderers == 1, "hay %d MultiMeshInstance3D en el subárbol del pool, no 1"
			% renderers)
	if _tracers == null:
		fail("el pool no expone su TracerRenderer")
		return
	expect(_tracers.multimesh != null, "el TracerRenderer no tiene MultiMesh")
	if _tracers.multimesh == null:
		return
	expect(_tracers.multimesh.use_custom_data,
			"el MultiMesh no tiene use_custom_data (docs/08 §2.9)")
	expect(_tracers.multimesh.instance_count == TracerRenderer.INSTANCE_COUNT,
			"instance_count = %d, se esperaban %d"
			% [_tracers.multimesh.instance_count, TracerRenderer.INSTANCE_COUNT])
	expect(_tracers.multimesh.transform_format == MultiMesh.TRANSFORM_3D,
			"el MultiMesh no está en TRANSFORM_3D")

	_park_targets()
	await _reset_drone()
	_weapon.reset()
	_pool.clear()
	# 36 disparos seguidos pasarían de 1.0 de calor: acá se mide el trazador, no
	# el bloqueo, que tiene su propio sub-check.
	_profile.heat_per_shot = 0.0
	await _step(SETTLE_TICKS)

	# Seis trazadores vivos: uno por disparo, en ticks consecutivos.
	_profile.tracer_every = 1
	for _i: int in TRACER_SAMPLE:
		var _ok := _weapon.fire()
		await _step(1)
	expect(_tracers.get_live_count() == TRACER_SAMPLE,
			"hay %d trazadores vivos, se esperaban %d"
			% [_tracers.get_live_count(), TRACER_SAMPLE])
	expect(_tracers.multimesh.visible_instance_count == TRACER_SAMPLE,
			"visible_instance_count = %d, se esperaban %d"
			% [_tracers.multimesh.visible_instance_count, TRACER_SAMPLE])

	# `INSTANCE_CUSTOM.r` decreciente con la edad: la ranura 0 es la del disparo
	# más viejo y tiene que estar más apagada que la última.
	var oldest := _tracers.get_slot_life(0)
	var newest := _tracers.get_slot_life(TRACER_SAMPLE - 1)
	expect(oldest >= 0.0 and newest >= 0.0, "las ranuras de trazador no están vivas")
	expect(oldest < newest,
			"INSTANCE_CUSTOM.r no decrece con la edad (%.4f vs %.4f)" % [oldest, newest])
	print("   tracers = %d vivos, visible_instance_count %d, vida %.4f (viejo) < %.4f (nuevo)"
			% [_tracers.get_live_count(), _tracers.multimesh.visible_instance_count,
			oldest, newest])

	# Proporción: con `tracer_every = 3`, 30 disparos dan 10 trazadores ±1.
	_pool.clear()
	await _step(2)
	_profile.tracer_every = 3
	_weapon.reset()
	for _i: int in TRACER_RATIO_SHOTS:
		var _ok := _weapon.fire()
		await _step(1)
	var live := _tracers.get_live_count()
	var expected := TRACER_RATIO_SHOTS / _profile.tracer_every
	expect(absi(live - expected) <= 1,
			"llevaron trazador %d de %d disparos, se esperaban %d ±1"
			% [live, TRACER_RATIO_SHOTS, expected])
	print("   tracer_every = %d → %d trazadores en %d disparos"
			% [_profile.tracer_every, live, TRACER_RATIO_SHOTS])
	_pool.clear()
	_profile.heat_per_shot = 0.045
	await _step(2)


# --- 13: huérfanos ----------------------------------------------------------------------------


## Sub-check 13 (`orphans`): tras 100 disparos al vacío y el `ttl`, no queda nada.
func _check_orphans() -> void:
	print("-- 13 orphans")
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	_pool.clear()
	_profile.heat_per_shot = 0.0
	await _step(SETTLE_TICKS)

	var fired := 0
	for _i: int in CADENCE_SHOTS:
		if _weapon.fire():
			fired += 1
		await _step(1)
	expect(fired == CADENCE_SHOTS, "salieron %d de %d disparos" % [fired, CADENCE_SHOTS])
	var peak := _pool.get_active_count()
	# `ttl` + 3 s de asentamiento, en ticks.
	var settle := int((_profile.projectile_ttl() + 3.0) / PHYSICS_STEP)
	await _step(settle)

	expect(_pool.get_active_count() == 0,
			"quedaron %d proyectiles vivos" % _pool.get_active_count())
	expect(_pool.get_free_count() == DOC_POOL_SIZE,
			"la lista libre quedó en %d de %d" % [_pool.get_free_count(), DOC_POOL_SIZE])
	expect(_pool.get_recycled_count() == 0,
			"hubo %d reciclajes: el pool se quedó corto" % _pool.get_recycled_count())
	expect(_tracers.get_live_count() == 0,
			"quedaron %d trazadores vivos" % _tracers.get_live_count())
	expect(_tracers.multimesh.visible_instance_count == 0,
			"visible_instance_count quedó en %d" % _tracers.multimesh.visible_instance_count)
	print("   orphans = pico %d vivos → 0, lista libre %d/%d, trazadores 0"
			% [peak, _pool.get_free_count(), DOC_POOL_SIZE])
	_profile.heat_per_shot = 0.045


# --- 15: asistencia de puntería ---------------------------------------------------------------


## Sub-check 15 (`aim_assist`).
func _check_aim_assist() -> void:
	print("-- 15 aim_assist")
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	await _step(SETTLE_TICKS)

	var marker := _make_marker("AssistTarget")
	_place_at_angle(marker, ASSIST_ANGLE_DEG, ASSIST_DISTANCE)
	GameSettings.aim_assist = GameSettings.AimAssist.SUBTLE
	_weapon.refresh_settings()
	await _step(4)
	# El dron está armado y cae: el blanco se recoloca contra el cañón de **este**
	# instante y la asistencia se refresca a mano, para que el ángulo medido sea
	# exactamente los 3.0° que pide `docs/08` §5 y no los 3.0° de hace 40 ms.
	_place_at_angle(marker, ASSIST_ANGLE_DEG, ASSIST_DISTANCE)
	_weapon.refresh_aim_assist()

	var raw := _weapon.get_raw_aim_direction()
	var origin := _weapon.get_muzzle_position()
	var to_target := (marker.global_position - origin).normalized()
	var base_angle := _angle_between(raw, to_target)
	var corrected := _weapon.get_aim_direction()
	var residual := _angle_between(corrected, to_target)
	var expected := base_angle * (1.0 - _profile.aim_assist_strength)
	expect(_weapon.get_aim_assist().get_target() == marker,
			"la asistencia no eligió el punto débil del cono")
	expect_near(base_angle, ASSIST_ANGLE_DEG, 0.05,
			"el blanco de la asistencia no quedó a 3.0° del eje")
	expect_near(residual, expected, 0.1,
			"el residual de la asistencia no es (1 − strength) × ángulo")
	expect_near(residual, ASSIST_ANGLE_DEG * (1.0 - _profile.aim_assist_strength), 0.1,
			"el residual no son los 1.95° de docs/08 §5")
	print("   aim_assist = %.3f° → %.3f° residual (esperado %.3f°, strength %.2f)"
			% [base_angle, residual, expected, _profile.aim_assist_strength])

	GameSettings.aim_assist = GameSettings.AimAssist.OFF
	_weapon.refresh_settings()
	_weapon.refresh_aim_assist()
	var untouched := _weapon.get_aim_direction()
	expect_near(_angle_between(untouched, _weapon.get_raw_aim_direction()), 0.0, 0.0001,
			"con aim_assist = OFF la dirección cambió igual")
	print("   aim_assist OFF = sin corrección")

	# Fuera del cono de 3.5°: no se elige.
	GameSettings.aim_assist = GameSettings.AimAssist.SUBTLE
	_weapon.refresh_settings()
	_place_at_angle(marker, ASSIST_OUTSIDE_DEG, ASSIST_DISTANCE)
	_weapon.refresh_aim_assist()
	expect(_weapon.get_aim_assist().get_target() == null,
			"se eligió un objetivo a %.1f°, fuera del cono de %.1f°"
			% [ASSIST_OUTSIDE_DEG, _profile.aim_assist_cone_deg])

	# Tapado por un cuerpo de la capa 8: se descarta por línea de visión.
	_place_at_angle(marker, ASSIST_ANGLE_DEG, ASSIST_DISTANCE)
	var muzzle := _weapon.get_muzzle_position()
	_building.global_position = muzzle + (marker.global_position - muzzle).normalized() * 20.0
	await _step(8)
	expect(_weapon.get_aim_assist().get_target() == null,
			"la asistencia eligió un punto débil tapado por la ciudad")
	print("   aim_assist = descarta fuera de cono y sin línea de visión")
	_building.global_position = PARKED
	marker.queue_free()
	_markers.erase(marker)
	await _step(4)


# --- 16: lock ---------------------------------------------------------------------------------


## Sub-check 16 (`lock`): fijar, rotar y romper el lock.
func _check_lock() -> void:
	print("-- 16 lock")
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	GameSettings.aim_assist = GameSettings.AimAssist.SUBTLE
	_weapon.refresh_settings()
	await _step(SETTLE_TICKS)

	var near_target := _make_marker("LockNear")
	var far_target := _make_marker("LockFar")
	_place_at_angle(near_target, 2.0, 70.0)
	_place_at_angle(far_target, 8.0, 90.0)
	await _step(8)

	_weapon.lock_target()
	expect(_weapon.get_locked_weak_point() == near_target,
			"lock_target() no fijó el candidato más cercano al eje")
	_weapon.cycle_target()
	expect(_weapon.get_locked_weak_point() == far_target,
			"cycle_target() no rotó al siguiente candidato")
	_weapon.cycle_target()
	expect(_weapon.get_locked_weak_point() == near_target,
			"cycle_target() no volvió al primer candidato")
	expect(_weapon.get_locked_target() == _weapon.get_locked_weak_point(),
			"get_locked_target() y get_locked_weak_point() no coinciden")

	# Un punto débil que deja de estar expuesto sale del grupo y, con él, del lock.
	near_target.remove_from_group(WeaponAimAssist.GROUP)
	far_target.remove_from_group(WeaponAimAssist.GROUP)
	await _step(12)
	expect(_weapon.get_locked_weak_point() == null,
			"el lock sobrevivió a la salida del grupo 'weak_points'")
	print("   lock = fija el más cercano al eje, rota y se rompe al salir del grupo")

	near_target.queue_free()
	far_target.queue_free()
	_markers.clear()
	GameSettings.aim_assist = GameSettings.AimAssist.OFF
	_weapon.refresh_settings()
	await _step(4)


# --- 17: fuego propio -------------------------------------------------------------------------


## Sub-check 17 (`no_self_hit`): con el cañón dentro del casco no hay impactos.
func _check_no_self_hit() -> void:
	print("-- 17 no_self_hit")
	expect((_profile.hit_mask & PhysicsLayers.DRONE) == 0,
			"la capa 'drone' está en hit_mask: el dron podría dispararse a sí mismo")
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	_pool.clear()
	await _step(SETTLE_TICKS)

	# El cañón se mete dentro del casco: origen en el centro del `BoxShape3D`.
	var saved_offset := _profile.muzzle_offset
	_profile.muzzle_offset = 0.0
	_weapon.set_profile(_profile)
	if _camera_rig != null:
		_camera_rig.position = Vector3.ZERO
	await _step(2)

	_begin_capture()
	var shots := 10
	var fired := 0
	for _i: int in shots:
		if _weapon.fire():
			fired += 1
	await _step(2)
	expect(fired == shots, "salieron %d de %d disparos desde dentro del casco"
			% [fired, shots])
	expect(_hits.is_empty(), "hubo %d impactos disparando desde dentro del casco"
			% _hits.size())
	expect(_pool.get_active_count() == fired,
			"%d proyectiles murieron al salir del casco" % (fired - _pool.get_active_count()))
	print("   no_self_hit = %d disparos desde el centro del casco, 0 impactos" % fired)

	_profile.muzzle_offset = saved_offset
	_weapon.set_profile(_profile)
	if _camera_rig != null:
		_camera_rig.position = _saved_camera_offset
	_pool.clear()
	await _step(2)


# --- 18: restauración -------------------------------------------------------------------------


## Sub-check 18 (`restore`): el check devuelve lo que tocó en memoria.
##
## Los `.cfg` de `user://` los restaura [CheckRunner], que además aísla este proceso
## en su propia carpeta de configuración: el check no ve ni escribe la del jugador.
##
## El dron se **desarma** antes de salir. No es cosmético: armado, `MotorAudio`
## mantiene ocho `AudioStreamPlayer` sonando (`docs/03` §6), y salir con ellos vivos
## deja diez instancias de `AudioStreamPlaybackWAV` en el `ObjectDB` y dos recursos
## en uso, que el motor reporta como fuga al cerrar.
func _check_restore() -> void:
	print("-- 18 restore")
	_pool.clear()
	_fx.clear()
	_drone.force_disarm()
	await _step(60)
	GameSettings.aim_assist = _saved_aim_assist as GameSettings.AimAssist
	if _camera_rig != null:
		_camera_rig.position = _saved_camera_offset
	expect(int(GameSettings.aim_assist) == _saved_aim_assist,
			"GameSettings.aim_assist no volvió a su valor original")
	expect(_weapon.get_profile() != load(WeaponMount.DEFAULT_PROFILE),
			"el check trabajó sobre el recurso del proyecto en vez de sobre una copia")
	print("   restore = aim_assist %d, perfil del proyecto intacto" % _saved_aim_assist)


# --- Utilidades ------------------------------------------------------------------------------


func _step(ticks: int) -> void:
	await wait_physics(ticks)


## Deja el dron quieto en el punto de reaparición. Está armado y por tanto cae:
## sin esto, entre colocar un blanco y que la bala llegue el cañón se habría movido.
func _reset_drone() -> void:
	_drone.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 400.0, 0.0)))
	await _step(2)


func _park_targets() -> void:
	_part.global_position = PARKED
	_weak.global_position = PARKED
	_building.global_position = PARKED
	_world.global_position = PARKED


## Coloca [param body] delante del cañón, dispara una vez y espera a que la bala
## llegue. Deja los demás blancos aparcados.
func _shoot_at(body: Node3D) -> void:
	_park_targets()
	await _reset_drone()
	_weapon.reset()
	await _step(SETTLE_TICKS)
	body.global_position = _weapon.get_muzzle_position() \
			+ _weapon.get_raw_aim_direction() * TARGET_DISTANCE
	await _step(2)
	_begin_capture()
	var ok := _weapon.fire()
	expect(ok, "fire() no salió al disparar contra %s" % body.name)
	await _step(FLIGHT_TICKS)


func _begin_capture() -> void:
	_shot_ticks.clear()
	_shot_angles.clear()
	_shot_count = 0
	_hits.clear()


func _mean_angle(from: int, count: int) -> float:
	if _shot_angles.is_empty():
		return 0.0
	var start := clampi(from, 0, _shot_angles.size() - 1)
	var stop := mini(start + count, _shot_angles.size())
	var total := 0.0
	for index: int in range(start, stop):
		total += _shot_angles[index]
	return total / float(maxi(stop - start, 1))


func _angle_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


## Crea un nodo del grupo `weak_points`. `EnemyBase` sólo mete ahí los puntos
## débiles **expuestos** (`docs/06` §5), así que un [Node3D] pelado cumple todo lo
## que la asistencia necesita: estar en el grupo y tener `global_position`.
func _make_marker(marker_name: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = marker_name
	marker.add_to_group(WeaponAimAssist.GROUP)
	_targets_root.add_child(marker)
	_markers.append(marker)
	return marker


## Coloca [param node] a [param angle_deg] del eje de puntería, a [param distance].
func _place_at_angle(node: Node3D, angle_deg: float, distance: float) -> void:
	var origin := _weapon.get_muzzle_position()
	var aim := _weapon.get_raw_aim_direction()
	var helper := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var axis := helper.cross(aim).normalized()
	node.global_position = origin + aim.rotated(axis, deg_to_rad(angle_deg)) * distance


func _count_multimesh(root: Node) -> int:
	var found := 0
	if root is MultiMeshInstance3D:
		found += 1
	for child: Node in root.get_children():
		found += _count_multimesh(child)
	return found


# --- Telemetría del bus ----------------------------------------------------------------------


func _on_shot_fired(_origin: Vector3, direction: Vector3) -> void:
	_shot_count += 1
	_shot_ticks.append(_tick)
	# La dirección de puntería no cambió entre el cálculo del disparo y esta
	# llamada: `fire()` emite de forma síncrona dentro del mismo tick.
	_shot_angles.append(_angle_between(direction, _weapon.get_aim_direction()))


func _on_hit_confirmed(position: Vector3, weak: bool, lethal: bool,
		surface: StringName) -> void:
	_hits.append({"position": position, "weak": weak, "lethal": lethal,
			"surface": surface, "tick": _tick})


func _on_heat_changed(ratio: float, overheated: bool) -> void:
	_heat_events.append(Vector2(ratio, 1.0 if overheated else 0.0))


## El bloqueo se cuenta con [method WeaponMount.get_shot_count] y no con las
## emisiones de `Events.shot_fired`: `overheated` se emite **dentro** de `fire()`,
## antes de publicar el disparo, así que el contador del bus todavía no incluye el
## disparo que cruzó el umbral —que sí sale, `docs/08` §2.4—.
func _on_overheated() -> void:
	if _overheat_tick >= 0:
		return
	_overheat_tick = _tick
	_overheat_shots = _weapon.get_shot_count()


## El calor se captura **en el instante del desbloqueo**: un tick más tarde el
## gatillo sostenido ya habría sumado otro disparo.
func _on_cooled() -> void:
	if _overheat_tick < 0 or _cool_tick >= 0:
		return
	_cool_tick = _tick
	_cool_heat = _weapon.get_heat_ratio()
