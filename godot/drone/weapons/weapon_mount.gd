## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## El arma primaria del dron: ciclo de disparo, dispersión, calor, retroceso y
## asistencia de puntería (`docs/08` §2.2 a §2.5 y §3.2).
##
## Es un [Node3D] **hijo directo del `Drone`** y vive en `drone_quad.tscn`, igual
## que el `ModeLED` y el `MotorAudio`: así cualquier escena que use el dron suelto
## hereda el arma sin cablear nada, y las rutas de `docs/03` §8 (`Drone/WeaponMount`)
## quedan exactas.
##
## **Quién le dice que dispare.** [member fire_pressed] es un `bool` público que
## escribe `RadioController` a través de `drone_rig.gd`. El arma **nunca** lee el
## `InputMap`: eso la deja usable desde un check, desde una cinemática y desde un
## bot sin tocar una línea.
##
## **Dirección y origen.** La dirección de puntería es `−FPVCamera.global_basis.z`,
## que ya viene inclinada por el `CameraRig` con el ángulo de cámara del hangar
## (`docs/03` §5): el jugador apunta con lo que ve, no con el morro del dron. El
## `Muzzle` va [constant WeaponProfile.muzzle_offset] 0.35 m por delante de la
## cámara en esa misma dirección, para que el rayo no arranque dentro del casco.
## El nodo se reorienta cada tick de física con la cámara, de modo que
## `−muzzle.global_basis.z` sigue siendo la dirección de disparo tal como la
## escribe `docs/08` §2.2.
##
## **Nada de `Timer` de nodo.** Cadencia, calor, bloqueo, ráfaga y refresco de la
## asistencia son acumuladores en `_physics_process`, porque `weapon_check` avanza
## el tiempo en ticks contados y un `SceneTreeTimer` no se enteraría.
##
## **Orden de compuertas de [method fire]** (`docs/08` §2.2), que `weapon_check`
## verifica una por una: perfil y pool, no sobrecalentado, dron armado, energía.
## Si la energía dice que no, no se consume nada y no sale el disparo.
class_name WeaponMount extends Node3D

## Se emite con cada disparo efectivo. [param direction] llega normalizada y ya
## corregida por la asistencia y desviada por la dispersión.
signal fired(origin: Vector3, direction: Vector3)

## Se emite al entrar en bloqueo por sobrecalentamiento.
signal overheated()

## Se emite al salir del bloqueo.
signal cooled()

## Clasificación del impacto que `docs/12` §4.1 deriva de `weak` y `lethal`. **No
## viaja por el bus**: `Events.hit_confirmed(position, weak, lethal)` lleva los dos
## booleanos y el HUD arma el enum con [method hit_kind].
enum HitKind {
	ARMOR = 0,       ## Impacto en blindaje: ✕ blanco.
	WEAK = 1,        ## Impacto en punto débil: ✕ ámbar.
	PART_BROKEN = 2, ## El impacto rompió la parte: ✕ rojo.
}

## Estados del arma (`docs/08` §2.2).
enum State {
	READY,      ## Dispara si hay gatillo y el acumulador venció.
	OVERHEATED, ## Bloqueada: ni dispara ni acumula cadencia.
}

## Máximo de disparos por tick de física. Un *hitch* no puede producir una ráfaga
## instantánea (`docs/08` §2.2).
const MAX_SHOTS_PER_TICK: int = 2

## Refresco de la asistencia de puntería, en Hz (`docs/08` §4).
const AIM_ASSIST_HZ: float = 20.0

## Variación mínima de `ratio` que publica `Events.weapon_heat_changed`. Sin este
## umbral serían cien emisiones por segundo (`docs/08` §2.4).
const HEAT_EVENT_EPSILON: float = 0.01

## Ruta del perfil por defecto del MVP.
const DEFAULT_PROFILE: String = "res://drone/weapons/profiles/default_gun.tres"

## Ruta de la escena del destello de boca.
const MUZZLE_FLASH_SCENE: String = "res://drone/weapons/muzzle_flash.tscn"

## Bus de audio del arma (`docs/04` §3.2).
const BUS: StringName = &"Weapons"

## Claves de [method set_aim_assist_mode] (`docs/08` §3.2).
const MODE_OFF: StringName = &"off"
const MODE_SUBTLE: StringName = &"subtle"
const MODE_ASSISTED: StringName = &"assisted"

## Perfil del arma. Si queda vacío se carga [constant DEFAULT_PROFILE].
@export var profile: WeaponProfile

## Dron que recibe el retroceso y que decide si está armado. Si queda vacío se
## busca el primer ancestro [Drone].
@export var drone: Drone

## Nodo que define la dirección de puntería. Si queda vacío se busca
## `Drone/CameraRig/FPVCamera` y, si no está, el propio dron.
@export var aim_source: Node3D

## Nodo de energía (`docs/09`). Si queda vacío se busca por **duck typing** un
## hijo del dron con `consume(amount) -> bool`. Sin él el arma dispara sin costo:
## WP-15 todavía no existe.
@export var energy_system: Node

## `true` mientras el gatillo está apretado. Lo escribe `RadioController` vía
## `drone_rig.gd`; el arma no lee el `InputMap`.
var fire_pressed: bool = false

## `true` mientras el gatillo secundario está apretado. En el MVP no hay arma
## secundaria (`docs/08` §1): sólo se registra para que WP-23 lo encuentre cableado.
var fire_alt_pressed: bool = false

## Calor normalizado de 0.0 a 1.0.
var heat: float = 0.0

var _state: int = State.READY
var _muzzle: Marker3D = null
var _muzzle_flash: MuzzleFlash = null
var _fire_sound: AudioStreamPlayer3D = null
var _pool: ProjectilePool = null
var _assist: WeaponAimAssist = WeaponAimAssist.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _shot_accumulator: float = 0.0
var _burst_time: float = 0.0
var _lock_timer: float = 0.0
var _assist_accumulator: float = 0.0
var _shot_index: int = 0
var _shots_fired: int = 0
var _last_heat_event: float = -1.0
var _last_overheated_event: bool = false
var _assist_mode_override: int = -1
var _last_aim_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	if profile == null:
		profile = load(DEFAULT_PROFILE) as WeaponProfile
	if profile == null:
		push_error("WeaponMount: no hay perfil y no se pudo cargar %s." % DEFAULT_PROFILE)
	_resolve_nodes()
	# Semilla propia: `weapon_check` necesita que la dispersión sea reproducible.
	_rng.seed = Global.round_seed
	_shot_accumulator = _interval()
	_configure_assist()
	_publish_heat(true)


## Todo el ciclo del arma en un acumulador por tick (`docs/08` §2.2 a §2.4).
##
## Orden deliberado: primero el arma se pone donde mira la cámara, después se
## refresca la asistencia, después corre el calor y sólo al final se resuelve la
## cadencia. Si el calor corriera después del disparo, el bloqueo llegaría un tick
## tarde y el sub-check de los 22–23 disparos daría 24.
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	# Acá sólo se **busca** el pool del nivel; el que falta se crea en [method fire].
	# Dos razones: crear uno y colgarlo del `current_scene` desde el `_ready()` de un
	# descendiente falla con «Parent node is busy setting up children» —los ancestros
	# siguen propagando el `NOTIFICATION_READY`—, y un dron de adorno o un banco de
	# vuelo no tienen por qué pagar 256 proyectiles y 48 nodos de VFX por existir.
	if _pool == null:
		_pool = _find_pool()
	_track_aim()
	_update_burst(delta)
	_update_assist(delta)
	_update_heat(delta)
	_update_cadence(delta)
	_publish_heat(false)


## Dispara **ahora**, saltándose la cadencia pero no las otras tres compuertas.
##
## Devuelve `true` si el disparo salió. Es el punto de entrada de los sistemas que
## no son el gatillo: los checks, una ráfaga guionada, un disparo de prueba.
func fire() -> bool:
	# 1) Perfil y pool.
	if profile == null:
		return false
	if _pool == null:
		_pool = _find_or_create_pool()
	if _pool == null:
		return false
	# 2) Sobrecalentamiento.
	if is_overheated():
		return false
	# 3) Dron armado.
	if drone != null and not drone.is_armed():
		return false
	# 4) Energía. Si dice que no, no se consume nada y no sale el disparo.
	if not _consume_energy():
		return false

	var origin := _muzzle_origin()
	var aim := get_aim_direction()
	var direction := _apply_spread(aim)
	var with_tracer := profile.tracer_every <= 1 or _shot_index % profile.tracer_every == 0
	var rid := drone.get_rid() if drone != null else RID()
	var _spawned := _pool.spawn(origin, direction, profile.damage,
			profile.weak_point_multiplier, rid, self, with_tracer)

	_shot_index += 1
	_shots_fired += 1
	_add_heat()
	_apply_recoil(aim)
	_play_shot_fx()
	_last_aim_direction = direction
	fired.emit(origin, direction)
	Events.shot_fired.emit(origin, direction)
	return true


## Cambia de perfil en caliente y reconfigura pool y asistencia.
func set_profile(new_profile: WeaponProfile) -> void:
	if new_profile == null:
		return
	profile = new_profile
	if _pool != null:
		_pool.set_profile(profile)
	_configure_assist()
	_apply_muzzle_offset()
	if _fire_sound != null:
		_fire_sound.stream = profile.fire_sound


## El perfil vigente.
func get_profile() -> WeaponProfile:
	return profile


## Instala el pool del nivel. Lo llama el nivel durante su cableado; si nadie lo
## llama, el arma busca uno por grupo y, si no hay, crea el suyo.
func set_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool
	if _pool != null and profile != null:
		_pool.set_profile(profile)


## El pool que usa esta arma.
func get_projectile_pool() -> ProjectilePool:
	return _pool


## Calor normalizado, de 0.0 a 1.0.
func get_heat_ratio() -> float:
	return heat


## `true` mientras el arma está bloqueada por sobrecalentamiento.
func is_overheated() -> bool:
	return _state == State.OVERHEATED


## Segundos que le quedan al bloqueo.
func get_overheat_remaining() -> float:
	return maxf(_lock_timer, 0.0)


## Dirección de puntería de este instante, **ya corregida** por la asistencia y
## **sin** dispersión. La consume el retículo del HUD (WP-22).
func get_aim_direction() -> Vector3:
	var base := _raw_aim_direction()
	return _assist.apply(_muzzle_origin(), base)


## Dirección de puntería cruda, sin asistencia: `−FPVCamera.global_basis.z`.
func get_raw_aim_direction() -> Vector3:
	return _raw_aim_direction()


## Dirección del último disparo efectivo, con dispersión incluida.
func get_last_shot_direction() -> Vector3:
	return _last_aim_direction


## Origen del disparo: el `Muzzle`, 0.35 m por delante de la cámara.
func get_muzzle_position() -> Vector3:
	return _muzzle_origin()


## Dispersión actual, en grados (`docs/08` §2.3).
func get_spread_deg() -> float:
	if profile == null:
		return 0.0
	return profile.spread_at(_burst_time)


## Segundos de ráfaga sostenida acumulados.
func get_burst_time() -> float:
	return _burst_time


## Disparos efectivos desde el último [method reset].
func get_shot_count() -> int:
	return _shots_fired


## Fija el objetivo del cono ampliado (acción `lock_target`).
func lock_target() -> void:
	refresh_aim_assist()
	_assist.lock()


## Rota entre los objetivos del cono ampliado (acción `cycle_target`).
func cycle_target() -> void:
	refresh_aim_assist()
	_assist.cycle_lock()


## Rehace **ahora** los candidatos de la asistencia, sin esperar al refresco de
## 20 Hz. Lo usan el lock, el ciclo de objetivos y los checks, que necesitan medir
## sobre el estado del instante y no sobre uno de hasta 50 ms de antigüedad.
func refresh_aim_assist() -> void:
	_refresh_assist()


## Objetivo fijado, o `null`. Lo dibuja el retículo (WP-22).
func get_locked_weak_point() -> Node3D:
	return _assist.get_locked_target()


## Alias de [method get_locked_weak_point] con el nombre del brief de WP-14.
func get_locked_target() -> Node3D:
	return _assist.get_locked_target()


## La asistencia de puntería de esta arma, para el HUD y los checks.
func get_aim_assist() -> WeaponAimAssist:
	return _assist


## Fuerza el modo de asistencia por encima de `GameSettings.aim_assist`
## (`docs/08` §3.2). Con una clave desconocida se vuelve a seguir el menú.
func set_aim_assist_mode(mode: StringName) -> void:
	match mode:
		MODE_OFF:
			_assist_mode_override = GameSettings.AimAssist.OFF
		MODE_SUBTLE:
			_assist_mode_override = GameSettings.AimAssist.SUBTLE
		MODE_ASSISTED:
			_assist_mode_override = GameSettings.AimAssist.ASSISTED
		_:
			_assist_mode_override = -1
	_configure_assist()


## Vuelve a leer `GameSettings.aim_assist`. Lo llama el menú de opciones al
## cerrarse.
func refresh_settings() -> void:
	_configure_assist()


## Vuelve a buscar el nodo de energía entre los hijos del dron.
##
## Hace falta porque `EnergySystem` es de WP-15 y puede aparecer **después** del
## `_ready()` del arma —un nivel que lo agrega al cablear, un check que lo
## instala—. Sin esto el arma dispararía gratis para siempre.
func refresh_energy_system() -> void:
	energy_system = _find_energy_system()


## Deja el arma como recién aparecida: calor 0, ráfaga 0, sin lock y sin bloqueo.
func reset() -> void:
	var was_overheated := _state == State.OVERHEATED
	heat = 0.0
	_state = State.READY
	_lock_timer = 0.0
	_burst_time = 0.0
	_shot_accumulator = _interval()
	_shots_fired = 0
	_assist.reset()
	if _muzzle_flash != null:
		_muzzle_flash.stop()
	if was_overheated:
		cooled.emit()
	_publish_heat(true)


## `HitKind` que le corresponde a un `Events.hit_confirmed` (`docs/08` §2.11).
static func hit_kind(weak: bool, lethal: bool) -> int:
	if lethal:
		return HitKind.PART_BROKEN
	return HitKind.WEAK if weak else HitKind.ARMOR


# --- Gatillo ---------------------------------------------------------------------------------


## Escribe [member fire_pressed]. Es lo que `drone_rig.gd` conecta a
## `RadioController.fire_changed`.
func set_fire_pressed(pressed: bool) -> void:
	fire_pressed = pressed


## Gatillo secundario. En el MVP no hay arma secundaria (`docs/08` §1), así que
## sólo se registra el estado para que WP-23 lo encuentre cableado.
func set_fire_alt_pressed(pressed: bool) -> void:
	fire_alt_pressed = pressed


## `true` mientras el gatillo secundario está apretado.
func is_fire_alt_pressed() -> bool:
	return fire_alt_pressed


# --- Ciclo interno ---------------------------------------------------------------------------


## Pone el nodo donde mira la cámara, para que `−muzzle.global_basis.z` sea la
## dirección de disparo y el `Muzzle` quede 0.35 m por delante.
func _track_aim() -> void:
	if aim_source == null or not aim_source.is_inside_tree():
		return
	global_basis = aim_source.global_basis.orthonormalized()
	global_position = aim_source.global_position


## Tiempo de ráfaga: sube mientras el gatillo está apretado y se descuenta
## `spread_decay_factor` veces más rápido al soltarlo (`docs/08` §2.3).
func _update_burst(delta: float) -> void:
	if profile == null:
		return
	if fire_pressed:
		_burst_time += delta
		return
	_burst_time = maxf(0.0, _burst_time - delta * profile.spread_decay_factor)


## Calor y bloqueo (`docs/08` §2.4).
##
## El enfriado corre **sólo con el gatillo suelto o durante el bloqueo**. Si
## corriera en paralelo con el fuego sostenido, a 8 disparos/s el calor ganaría
## 0.36/s contra 0.40/s de enfriado y el arma no se bloquearía jamás.
func _update_heat(delta: float) -> void:
	if profile == null:
		return
	if _state == State.OVERHEATED:
		_lock_timer = maxf(_lock_timer - delta, 0.0)
		heat = maxf(heat - profile.cooldown_at(heat) * delta, 0.0)
		if _lock_timer <= 0.0 and heat <= profile.overheat_release:
			_state = State.READY
			_shot_accumulator = _interval()
			cooled.emit()
		return
	if fire_pressed:
		return
	heat = maxf(heat - profile.cooldown_at(heat) * delta, 0.0)


## Cadencia por acumulador, con tope de [constant MAX_SHOTS_PER_TICK] por tick.
func _update_cadence(delta: float) -> void:
	if profile == null:
		return
	var interval := _interval()
	if not fire_pressed or _state == State.OVERHEATED:
		# Sin gatillo el acumulador se tapa en un intervalo: el primer disparo de
		# la próxima ráfaga sale al instante, pero soltar diez segundos no compra
		# ochenta disparos de golpe.
		_shot_accumulator = minf(_shot_accumulator + delta, interval)
		return
	_shot_accumulator += delta
	var shots := 0
	while _shot_accumulator >= interval and shots < MAX_SHOTS_PER_TICK:
		if not fire():
			# Compuerta cerrada (energía, desarmado, bloqueo): el acumulador se
			# tapa para no acumular deuda mientras no se puede disparar.
			_shot_accumulator = minf(_shot_accumulator, interval)
			return
		_shot_accumulator -= interval
		shots += 1


## Refresco de la asistencia a 20 Hz (`docs/08` §2.8).
func _update_assist(delta: float) -> void:
	_assist_accumulator += delta
	var period := 1.0 / AIM_ASSIST_HZ
	if _assist_accumulator < period:
		return
	_assist_accumulator = fmod(_assist_accumulator, period)
	_refresh_assist()


func _refresh_assist() -> void:
	var exclude: Array[RID] = []
	if drone != null:
		exclude.append(drone.get_rid())
	_assist.refresh(_muzzle_origin(), _raw_aim_direction(), _space_state(), exclude)


## Suma el calor del disparo y entra en bloqueo si cruza 1.0. El disparo que cruza
## el umbral **sí sale**: esta función corre después de `spawn()`.
func _add_heat() -> void:
	if profile == null:
		return
	heat += profile.heat_per_shot
	if heat < 1.0 or _state == State.OVERHEATED:
		return
	_state = State.OVERHEATED
	_lock_timer = profile.overheat_lock
	overheated.emit()
	_publish_heat(true)


## Publica `Events.weapon_heat_changed` al cambiar de estado o cuando `ratio` varía
## al menos [constant HEAT_EVENT_EPSILON].
func _publish_heat(force: bool) -> void:
	var ratio := clampf(heat, 0.0, 1.0)
	var locked := is_overheated()
	if not force and locked == _last_overheated_event \
			and absf(ratio - _last_heat_event) < HEAT_EVENT_EPSILON:
		return
	_last_heat_event = ratio
	_last_overheated_event = locked
	Events.weapon_heat_changed.emit(ratio, locked)


## Retroceso: impulso central opuesto a la dirección de disparo (`docs/08` §2.5).
## El signo lo verifica `weapon_check` con `linear_velocity.dot(aim_dir) < 0`.
func _apply_recoil(aim: Vector3) -> void:
	if drone == null or profile == null or profile.recoil_impulse <= 0.0:
		return
	drone.apply_central_impulse(-aim * profile.recoil_impulse)


## Cobra la energía del disparo por **duck typing**: `EnergySystem` es de WP-15 y
## todavía no existe. Sin nodo de energía el arma dispara sin costo.
func _consume_energy() -> bool:
	if energy_system == null or profile == null:
		return true
	if not energy_system.has_method(&"consume"):
		return true
	return bool(energy_system.call(&"consume", profile.energy_per_shot))


func _play_shot_fx() -> void:
	if _muzzle_flash != null:
		_muzzle_flash.flash()
	if _fire_sound == null or _fire_sound.stream == null:
		return
	_fire_sound.pitch_scale = _rng.randf_range(0.96, 1.04)
	_fire_sound.play()


# --- Geometría y dispersión ------------------------------------------------------------------


## Desvía [param aim] dentro del disco de semiángulo `spread_deg`, muestreado
## **uniforme en área** (`docs/08` §2.3): `r = spread * sqrt(randf())`. Sin la raíz
## los disparos se apelotonarían en el centro del cono.
func _apply_spread(aim: Vector3) -> Vector3:
	if profile == null:
		return aim
	var spread := get_spread_deg()
	if spread <= 0.0:
		return aim
	var angle := deg_to_rad(spread * sqrt(_rng.randf()))
	var roll := _rng.randf() * TAU
	var helper := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var axis := helper.cross(aim).normalized().rotated(aim, roll)
	return aim.rotated(axis, angle).normalized()


## `−aim_source.global_basis.z`, o el frente del dron si no hay fuente de puntería.
func _raw_aim_direction() -> Vector3:
	if aim_source != null and aim_source.is_inside_tree():
		return -aim_source.global_basis.orthonormalized().z
	if drone != null and drone.is_inside_tree():
		return -drone.global_basis.orthonormalized().z
	return -global_basis.orthonormalized().z


func _muzzle_origin() -> Vector3:
	if _muzzle != null and _muzzle.is_inside_tree():
		return _muzzle.global_position
	var offset := profile.muzzle_offset if profile != null else 0.35
	if aim_source != null and aim_source.is_inside_tree():
		return aim_source.global_position + _raw_aim_direction() * offset
	return global_position + _raw_aim_direction() * offset


func _interval() -> float:
	return profile.shot_interval() if profile != null else 0.125


func _space_state() -> PhysicsDirectSpaceState3D:
	var world := get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


# --- Cableado --------------------------------------------------------------------------------


## Encuentra o crea los nodos hijos y los del dron. Todo opcional: el arma tiene
## que poder existir en una escena de prueba con un `Node3D` por padre.
func _resolve_nodes() -> void:
	if drone == null:
		drone = _find_drone()
	if aim_source == null:
		aim_source = _find_aim_source()
	if energy_system == null:
		energy_system = _find_energy_system()
	_muzzle = get_node_or_null(^"Muzzle") as Marker3D
	if _muzzle == null:
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		add_child(_muzzle)
	_apply_muzzle_offset()
	_muzzle_flash = _find_or_create_flash()
	_fire_sound = get_node_or_null(^"FireSound") as AudioStreamPlayer3D
	if _fire_sound == null:
		_fire_sound = AudioStreamPlayer3D.new()
		_fire_sound.name = "FireSound"
		_fire_sound.unit_size = 12.0
		_fire_sound.max_distance = 260.0
		add_child(_fire_sound)
	_fire_sound.bus = BUS
	if profile != null and _fire_sound.stream == null:
		_fire_sound.stream = profile.fire_sound


func _apply_muzzle_offset() -> void:
	if _muzzle == null:
		return
	var offset := profile.muzzle_offset if profile != null else 0.35
	_muzzle.position = Vector3(0.0, 0.0, -offset)


func _find_drone() -> Drone:
	var node := get_parent()
	while node != null:
		var found := node as Drone
		if found != null:
			return found
		node = node.get_parent()
	return null


func _find_aim_source() -> Node3D:
	if drone != null:
		var camera := drone.get_node_or_null(^"CameraRig/FPVCamera") as Node3D
		if camera != null:
			return camera
	return drone


## Busca un hijo del dron con `consume(amount) -> bool`. WP-15 lo llamará
## `EnergySystem`; hasta entonces cualquier nodo que cumpla el contrato sirve, que
## es lo que permite probarlo con un doble en `weapon_check`.
func _find_energy_system() -> Node:
	if drone == null:
		return null
	var named := drone.get_node_or_null(^"EnergySystem")
	if named != null and named.has_method(&"consume"):
		return named
	for child: Node in drone.get_children():
		if child.has_method(&"consume"):
			return child
	return null


func _find_or_create_flash() -> MuzzleFlash:
	var existing := get_node_or_null(^"Muzzle/MuzzleFlash") as MuzzleFlash
	if existing != null:
		return existing
	existing = get_node_or_null(^"MuzzleFlash") as MuzzleFlash
	if existing != null:
		return existing
	var scene := profile.muzzle_flash_scene if profile != null else null
	if scene == null:
		scene = load(MUZZLE_FLASH_SCENE) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate() as MuzzleFlash
	if instance == null:
		return null
	instance.name = "MuzzleFlash"
	if _muzzle != null:
		_muzzle.add_child(instance)
	else:
		add_child(instance)
	return instance


## Busca el pool del nivel por el grupo `projectile_pool` dentro de
## `get_tree().current_scene` y, si no hay ninguno, crea uno y lo **agrega al
## `current_scene`**: así el arma funciona en `flight_sandbox` y en `weapon_check`
## sin nivel, y el nivel sigue siendo el dueño natural cuando existe
## (`docs/08` §2.6).
func _find_or_create_pool() -> ProjectilePool:
	var existing := _find_pool()
	if existing != null:
		return existing
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	var pool := ProjectilePool.new()
	pool.name = ProjectilePool.FALLBACK_NAME
	pool.profile = profile
	var host: Node = scene if scene != null else tree.root
	if host == null:
		return null
	host.add_child(pool)
	return pool


## Pool ya instalado en la escena actual, o `null`. No crea nada.
func _find_pool() -> ProjectilePool:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	for node: Node in tree.get_nodes_in_group(ProjectilePool.GROUP):
		var found := node as ProjectilePool
		if found == null:
			continue
		if scene == null or found == scene or scene.is_ancestor_of(found):
			if profile != null:
				found.set_profile(profile)
			return found
	return null


## Copia al [WeaponAimAssist] el cono y el alcance del perfil y la fuerza que
## manda el menú (`docs/08` §2.8): `OFF` 0.00, `SUBTLE` 0.35, `ASSISTED` 0.60.
func _configure_assist() -> void:
	if profile == null:
		return
	_assist.configure(profile.aim_assist_cone_deg, _assist_strength(),
			profile.aim_assist_max_range, profile.los_mask)
	_assist.configure_lock(profile.lock_cone_deg, profile.lock_break_angle,
			profile.lock_break_range)


func _assist_strength() -> float:
	var mode := _assist_mode_override if _assist_mode_override >= 0 \
			else int(GameSettings.aim_assist)
	match mode:
		GameSettings.AimAssist.OFF:
			return 0.0
		GameSettings.AimAssist.ASSISTED:
			return profile.aim_assist_strength_assisted
		_:
			return profile.aim_assist_strength
