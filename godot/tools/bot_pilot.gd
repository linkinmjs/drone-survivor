## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Piloto sintético que juega la ronda 1 de verdad, sin jugador humano (`docs/15` §4,
## `docs/07` §14).
##
## No es un doble ni un maniquí: vuela el `DroneRig` real sobre `battle_level.tscn`,
## dispara con el [WeaponMount] real —cadencia, calor, energía y asistencia
## incluidas—, muere con el [Hull] real y reaparece con el [RespawnController] real.
## Lo único sintético es **cómo se mueve el cuerpo** y **cómo apunta**.
##
## ## Por qué el dron es cinemático
##
## El [Drone] es un [RigidBody3D] con un integrador propio de diez subpasos y un
## lazo PID detrás (`docs/03`). Pilotarlo «de verdad» exigiría escribir un
## controlador de vuelo autónomo —otro WP entero— y, peor, el resultado del balance
## dependería de lo bien que volara ese controlador y no del balance del jefe. Por
## eso el bot pone `freeze_mode = FREEZE_MODE_KINEMATIC` y `freeze = true` y escribe
## `global_position` y `global_basis` una vez por tick de física.
##
## Lo que esa elección **conserva**, que es lo que importa para medir:
##
## - el cuerpo sigue en la **capa 2** (`drone`), así que los `intersect_shape` de
##   `stomp`, `leg_sweep`, `pounce`, `emp_pulse` y `shake_off` lo siguen encontrando
##   y el casco sigue cobrando (`SweepAction._hit_drone`);
## - la [Perception] del jefe lo sigue viendo y midiendo su velocidad, porque el
##   rayo de línea de visión no pregunta si el cuerpo es dinámico;
## - el [WeaponMount] dispara con su propio acumulador, su calor y su asistencia;
## - el [EnergySystem] cobra por disparo y drena por acelerador, porque el bot le
##   escribe un [FlightCommand] con acelerador emulado (`docs/09` §2.1);
## - el [Hull], el [RespawnController] y las pilas funcionan sin cambios.
##
## Lo que **pierde**: el impulso de los barridos (`apply_impulse` sobre un cuerpo
## congelado no hace nada) y el daño por choque, que se neutraliza a propósito
## dejando `linear_velocity` en cero cada tick para que [Hull] no cobre colisiones
## imaginarias al teletransportar. El impulso se compensa en la medición: el bot
## **no** se aleja gratis del golpe, porque el retroceso empujaba hacia afuera y
## eso sólo lo ayudaría.
##
## ## Comportamiento
##
## | Situación | Qué hace |
## |---|---|
## | Rodillas sin romper | orbita el jefe entre [member orbit_min] y [member orbit_max] m, a [member knee_orbit_height] sobre el suelo (la banda de rodilla de `docs/07` §15 #1) |
## | Visor expuesto | se queda en la órbita y le dispara al visor mientras dure la ventana |
## | 3 rodillas rotas | deja de disparar a las rodillas y se mete **debajo** del jefe, barriendo el cono de los núcleos |
## | Telegrafía esquivable | con probabilidad [member dodge_skill] sale del radio del ataque durante el windup |
## | Energía < [member energy_hunt_ratio] | va a la pila activa más cercana |
## | Reconstruyéndose | no hace nada; el [RespawnController] manda |
## | [constant Mode.IDLE] | se queda posado sobre el punto de reaparición y no dispara nunca |
##
## ## Puntería
##
## La dirección de disparo es la del punto débil elegido más un error angular
## gaussiano de σ [member aim_sigma_deg] grados, remuestreado a
## [constant AIM_HZ]. El error se aplica **al cuerpo del dron**, no al arma: el bot
## orienta el dron de modo que la `FPVCamera` —que es la fuente de puntería del
## [WeaponMount] (`docs/08` §2.2)— mire ahí, descontando la inclinación de cámara
## del hangar. Así la asistencia de puntería, la dispersión y el retroceso operan
## sobre la misma geometría que tendría un humano.
##
## ## Determinismo
##
## Todo el azar del bot sale de un [RandomNumberGenerator] sembrado con
## [method RoundCatalog.derive_seed] sobre la etiqueta `"bot"`, es decir de
## [member Global.round_seed]: dos corridas con la misma semilla dan la misma
## partida. Nada de [Timer]: todo son acumuladores sobre `delta` (`docs/00` §6).
class_name BotPilot extends Node

## Modos de juego del bot.
enum Mode {
	COMBAT, ## Juega la ronda: orbita, apunta, dispara, esquiva y recoge pilas.
	IDLE,   ## Partida de control: se queda posado y no dispara nunca.
}

## Refresco del error de puntería, en Hz. Un error nuevo por disparo sería ruido
## blanco y la tasa de acierto saldría del promedio del cono; a 5 Hz el error dura
## lo que dura una microcorrección humana.
const AIM_HZ: float = 5.0

## Refresco de la decisión de objetivo, en Hz.
const TARGET_HZ: float = 4.0

## Altura mínima sobre el suelo a la que el bot se deja estar, en metros.
const MIN_CLEARANCE: float = 3.0

## Alcance del rayo que busca el suelo bajo el bot, en metros.
const GROUND_PROBE: float = 400.0

## Margen que el bot deja al salir del radio de un ataque, en metros.
const DODGE_MARGIN: float = 6.0

## Velocidad de escape durante una esquiva, en metros por segundo.
const DODGE_SPEED: float = 34.0

## Altura del punto débil de rodilla sobre el suelo, en metros (`docs/07` §15, #1).
const KNEE_HEIGHT: Vector2 = Vector2(6.0, 12.0)

## Velocidad angular con la que el bot barre el cono del vientre, en rad/s.
const BELLY_SWEEP_RATE: float = 0.55

## Amplitud del barrido radial bajo el vientre, en metros.
const BELLY_SWEEP_SPAN: float = 2.5

## Amplitud del barrido vertical bajo el vientre, en metros.
const BELLY_LIFT_SPAN: float = 3.0

## Ataques que el bot sabe esquivar saliendo de un radio. `head_laser` y
## `siege_beam` no están: el primero se esquiva orbitando y el segundo ni siquiera
## apunta al dron.
const DODGEABLE: Array[StringName] = [&"stomp", &"pounce", &"emp_pulse",
		&"leg_sweep", &"shake_off"]

## Ids de los puntos débiles de rodilla, en el orden de `docs/07` §4.
const KNEE_IDS: Array[StringName] = [&"wp_leg_fl_knee", &"wp_leg_fr_knee",
		&"wp_leg_bl_knee", &"wp_leg_br_knee"]

## Id del visor.
const VISOR_ID: StringName = &"wp_head_visor"

## Modo de juego.
@export var mode: int = Mode.COMBAT

## Desviación angular de la puntería, en grados. Es la palanca con la que se
## calibra la tasa de acierto sobre puntos débiles al rango de `docs/07` §14.
##
## Calibrada en WP-23 contra la tasa medida: el error total que ve el blanco es
## esta σ compuesta con la dispersión de ráfaga del arma (0.35° que crece a 2.2°,
## `docs/08` §2.3), y la fracción de disparos que caen dentro de un punto débil de
## unos tres metros a 25–45 m sigue `1 − exp(−R²/2σ²)`. Con σ 1.9° la tasa salía
## 0.22, con 1.0° salía 0.34, con 0.70° 0.35–0.40 y con 0.60° queda holgada dentro
## de la banda 0.35–0.45 sin llegar a la puntería perfecta. Valor final: **0.55**.
@export var aim_sigma_deg: float = 0.55

## Probabilidad de intentar la esquiva de una telegrafía esquivable.
@export var dodge_skill: float = 0.70

## Radio mínimo de la órbita alrededor del jefe, en metros.
@export var orbit_min: float = 25.0

## Radio máximo de la órbita alrededor del jefe, en metros.
@export var orbit_max: float = 45.0

## Velocidad de crucero del bot, en metros por segundo.
@export var cruise_speed: float = 22.0

## Velocidad tangencial de la órbita, en metros por segundo.
@export var orbit_speed: float = 14.0

## Fracción de batería por debajo de la cual el bot va a buscar una pila.
@export var energy_hunt_ratio: float = 0.35

## Acelerador emulado que el bot le declara al [EnergySystem] mientras vuela.
@export var throttle: float = 0.45

## Segundos de reacción a una telegrafía: el bot no empieza a esquivar en el mismo
## tick en que el aviso aparece.
@export var reaction_seconds: float = 0.25

## Desplazamiento horizontal con el que el bot se pone bajo el vientre, en metros.
## Tiene que dejar el ángulo contra la vertical por dentro del cono de los núcleos
## (`docs/07` §4), que es de 35° y de 55° en P4.
@export var belly_offset: float = 4.0

## Altura de la órbita sobre el suelo cuando el blanco es una rodilla, en metros.
## Es la palanca de exposición del bot: volar a la altura de la rodilla lo deja
## dentro del cilindro del pisotón, que es donde `docs/07` §5.4 quiere al dron.
@export var knee_orbit_height: float = 7.0

## Distancia máxima a la que el bot se molesta en disparar, en metros. Más allá,
## un blanco de tres metros no es un blanco: es gastar batería y calor.
@export var fire_max_range: float = 80.0

## Rodillas que el bot se permite romper. La cuarta deja al jefe sin patas y la
## ronda sin final: ver [method _pick_target].
@export var knee_target_limit: int = 3

var _rig: DroneRig = null
var _drone: Drone = null
var _weapon: WeaponMount = null
var _energy: EnergySystem = null
var _hull: Hull = null
var _respawn: RespawnController = null
var _camera_rig: CameraRig = null
var _enemy: EnemyBase = null
var _library: AttackLibrary = null
var _spawner: BatterySpawner = null
var _home: Vector3 = Vector3.ZERO

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _command: FlightCommand = FlightCommand.new()
var _active: bool = false

var _orbit_angle: float = 0.0
var _orbit_radius: float = 35.0
var _orbit_sign: float = 1.0
var _aim_error: Vector2 = Vector2.ZERO
var _aim_accumulator: float = 0.0
var _target_accumulator: float = 0.0
var _target: WeakPoint = null
var _spare_gauss: float = 0.0
var _has_spare: bool = false

var _dodge_left: float = 0.0
var _dodge_delay: float = 0.0
var _dodge_centre: Vector3 = Vector3.ZERO
var _dodge_radius: float = 0.0
var _dodge_id: StringName = &""
var _hold_left: float = 0.0

## Métricas acumuladas de la partida. Las lee `balance_check`.
var _fire_seconds: float = 0.0
var _armed_seconds: float = 0.0
var _shots: int = 0
var _weak_hits: int = 0
var _armor_hits: int = 0
var _dodges_tried: int = 0
var _dodges_made: int = 0
var _batteries: int = 0
var _min_energy: float = 1.0
var _elapsed: float = 0.0
var _damage_taken: float = 0.0
var _hits_taken: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(false)


# --- Interfaz pública -------------------------------------------------------------------------

## Cablea el bot con el nivel y lo deja listo para [method start].
##
## [param bot_seed] siembra todo el azar del bot; `balance_check` le pasa
## `RoundCatalog.derive_seed("bot")` para que la partida sea reproducible con la
## semilla de la ronda (`docs/11` §4.4).
func setup(rig: DroneRig, enemy: EnemyBase, spawner: BatterySpawner, bot_seed: int) -> void:
	_rig = rig
	_enemy = enemy
	_spawner = spawner
	_rng.seed = bot_seed
	if _rig != null:
		_drone = _rig.get_drone()
		_weapon = _rig.get_weapon_mount()
		_energy = _rig.get_energy_system()
		_hull = _rig.get_hull()
		_respawn = _rig.get_respawn_controller()
		_camera_rig = _rig.get_camera_rig()
		_home = _rig.global_position
	if _enemy != null:
		var brain := _enemy.brain as EnemyFSM
		if brain != null:
			_library = brain.library
	_orbit_radius = _rng.randf_range(orbit_min, orbit_max)
	_orbit_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_orbit_angle = _rng.randf() * TAU
	_connect_bus()


## Empieza a jugar. Antes de esto el bot no toca nada: `RoundManager` todavía está
## en `INTRO` y el dron tiene que quedarse congelado y desarmado.
func start() -> void:
	if _drone == null:
		return
	_active = true
	_apply_kinematic()
	# La radio del jugador se apaga: `RoundManager._enter_battle` la enciende al
	# pasar a `BATTLE` y su `fire_changed` pelearía con el gatillo del bot
	# (`docs/03` §8).
	var radio := _rig.get_radio() if _rig != null else null
	if radio != null:
		radio.enabled = false
	if mode == Mode.IDLE:
		_drone.force_disarm()
	set_physics_process(true)


## Deja de jugar y suelta el gatillo. No devuelve el dron a dinámico: el nivel se
## libera entero después.
func stop() -> void:
	_active = false
	set_physics_process(false)
	if _weapon != null and is_instance_valid(_weapon):
		_weapon.fire_pressed = false
	_disconnect_bus()


## Métricas de la partida, para el informe de `balance_check`.
func metrics() -> Dictionary:
	return {
		"fire_seconds": _fire_seconds,
		"armed_seconds": _armed_seconds,
		"shots": _shots,
		"weak_hits": _weak_hits,
		"armor_hits": _armor_hits,
		"weak_hit_rate": float(_weak_hits) / float(maxi(_shots, 1)),
		"duty_cycle": float(_shots) / maxf(_fire_seconds * _fire_rate(), 1.0),
		"dodges_tried": _dodges_tried,
		"dodges_made": _dodges_made,
		"batteries": _batteries,
		"min_energy": _min_energy,
		"damage_taken": _damage_taken,
		"hits_taken": _hits_taken,
		"hull_left": _hull.get_ratio() if _hull != null and is_instance_valid(_hull) else 1.0,
	}


## Segundos con el gatillo apretado.
func fire_seconds() -> float:
	return _fire_seconds


## Punto débil al que el bot le está apuntando, o `null`.
func current_target() -> WeakPoint:
	return _target


# --- Bucle ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _active or delta <= 0.0 or _drone == null or not is_instance_valid(_drone):
		return
	_elapsed += delta
	if _energy != null:
		_min_energy = minf(_min_energy, _energy.get_ratio())
	if _respawn != null and _respawn.is_respawning():
		# El `RespawnController` es el dueño del cuerpo durante los 12 s
		# (`docs/09` §2.8): el bot no lo toca ni dispara.
		if _weapon != null:
			_weapon.fire_pressed = false
		return
	PerfProbe.begin(&"bot_pilot")
	_apply_kinematic()
	if mode == Mode.IDLE:
		_tick_idle(delta)
		PerfProbe.end(&"bot_pilot")
		return
	_tick_dodge(delta)
	_tick_target(delta)
	_tick_aim(delta)
	_move(delta)
	_tick_trigger(delta)
	_feed_energy()
	PerfProbe.end(&"bot_pilot")


## Partida de control: el dron se queda posado donde apareció, armado para que la
## batería drene como en una partida real, y **sin** disparar nunca.
func _tick_idle(delta: float) -> void:
	_armed_seconds += delta
	if _weapon != null:
		_weapon.fire_pressed = false
	_drone.global_position = _home
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO


## Deja el cuerpo cinemático y quieto. Se reaplica cada tick porque
## `RoundManager._freeze_drone` y `RespawnController._finish` lo devuelven a
## dinámico por su cuenta.
func _apply_kinematic() -> void:
	if _drone.freeze_mode != RigidBody3D.FREEZE_MODE_KINEMATIC:
		_drone.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	if not _drone.freeze:
		_drone.freeze = true
	# Con velocidad cero, `Hull._impact_damage` no cobra nada al teletransportar:
	# el daño por choque de un cuerpo que se mueve por escritura sería inventado.
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO


# --- Objetivo ---------------------------------------------------------------------------------

## Reelige el punto débil cada [constant TARGET_HZ] Hz.
func _tick_target(delta: float) -> void:
	_target_accumulator += delta
	var period := 1.0 / TARGET_HZ
	if _target_accumulator < period and _target != null and _target.is_exposed():
		return
	_target_accumulator = 0.0
	_target = _pick_target()


## Prioridad de blancos, en el orden en que la juega un humano que conoce la pelea
## (`docs/07` §4 y §15, #1):
##
## 1. un núcleo expuesto, que es lo único que mata al jefe;
## 2. el visor, mientras dure la ventana que abre un ataque y a distancia de tiro
##    —es la recompensa por provocarlo y vale 1 500 HP de estructura;
## 3. la rodilla sana más cercana, que es el blanco válido del principio.
##
## **La cuarta rodilla no se toca.** Con las cuatro rotas el jefe pierde las cuatro
## patas, entra en `DOWNED` y la cadera baja a `downed_hip_factor` (`docs/06` §8.7):
## el vientre queda a ras de suelo y los tres núcleos dejan de poder exponerse
## —piden al dron **debajo**, dentro del cono—, así que la ronda se vuelve
## inganable y no termina nunca. Medido en WP-23; está anotado como discrepancia.
## Un jugador que ya abrió la carcasa tampoco vuelve a las rodillas, así que la
## regla es además la jugada correcta.
func _pick_target() -> WeakPoint:
	if _enemy == null or not is_instance_valid(_enemy):
		return null
	var origin := _drone.global_position
	var knees_left := _knees_broken() < knee_target_limit
	var best: WeakPoint = null
	var best_distance := INF
	var visor: WeakPoint = null
	for point: WeakPoint in _enemy.get_weak_points():
		if point.is_broken() or not point.is_exposed():
			continue
		if _is_core(point):
			return point
		var distance := origin.distance_to(point.world_position())
		if point.weak_point_id() == VISOR_ID:
			if distance <= fire_max_range:
				visor = point
			continue
		if not knees_left or distance >= best_distance:
			continue
		best_distance = distance
		best = point
	# El visor gana a la rodilla mientras dure su ventana: es la razón de ser de
	# provocar un ataque (`docs/07` §5.6).
	return visor if visor != null else best


## `true` si [param point] es uno de los tres núcleos ventrales.
func _is_core(point: WeakPoint) -> bool:
	return String(point.weak_point_id()).begins_with("wp_core")


## Rodillas rotas hasta ahora. Es lo que decide si el bot se mete debajo.
func _knees_broken() -> int:
	if _enemy == null or not is_instance_valid(_enemy):
		return 0
	var broken := 0
	for id: StringName in KNEE_IDS:
		var point := _enemy.get_weak_point(id)
		if point != null and point.is_broken():
			broken += 1
	return broken


# --- Movimiento -------------------------------------------------------------------------------

## Avanza hacia la pose deseada a [member cruise_speed], o a [constant DODGE_SPEED]
## si está esquivando.
func _move(delta: float) -> void:
	var desired := _desired_position(delta)
	var position := _drone.global_position
	var to := desired - position
	var speed := DODGE_SPEED if _dodge_left > 0.0 and _dodge_delay <= 0.0 else cruise_speed
	var step := speed * delta
	if to.length() > step:
		position += to.normalized() * step
	else:
		position = desired
	position.y = maxf(position.y, _ground_height(position) + MIN_CLEARANCE)
	_drone.global_position = position


## Dónde quiere estar el bot ahora mismo.
func _desired_position(delta: float) -> Vector3:
	if _dodge_left > 0.0 and _dodge_delay <= 0.0:
		return _dodge_position()
	# Telegrafía que el bot **no vio**: se queda donde está, que es lo que hace un
	# piloto que no leyó el aviso. Sin esto la órbita lo sacaría igual del radio y
	# `dodge_skill` no querría decir nada.
	if _hold_left > 0.0:
		return _drone.global_position
	var battery := _battery_target()
	if battery != Vector3.INF:
		return battery
	if _enemy == null or not is_instance_valid(_enemy):
		return _home
	if _knees_broken() >= 3:
		return _belly_position(delta)
	return _orbit_position(delta)


## Órbita alrededor del jefe a la altura del punto débil elegido. El ángulo avanza
## con la velocidad tangencial pedida, así que orbitar más lejos gira más despacio
## —igual que volar de verdad— y a 35 m el bot barre unos 23 °/s.
func _orbit_position(delta: float) -> Vector3:
	_orbit_angle += _orbit_sign * (orbit_speed / maxf(_orbit_radius, 1.0)) * delta
	var centre := _enemy.global_position
	var ground := _ground_height(centre)
	var height := ground + knee_orbit_height
	if _target != null and is_instance_valid(_target) \
			and _target.weak_point_id() == VISOR_ID:
		# Con el visor expuesto el bot sube: el casco está entre 22 y 29 m
		# (`docs/07` §2) y desde la altura de la rodilla el tiro pasa raspando.
		height = _target.world_position().y - 4.0
	height = clampf(height, ground + KNEE_HEIGHT.x, ground + 30.0)
	return Vector3(centre.x + cos(_orbit_angle) * _orbit_radius, height,
			centre.z + sin(_orbit_angle) * _orbit_radius)


## Pose para atacar los núcleos: **debajo** del jefe y dentro del cono de
## `cone_axis = DOWN` (`docs/07` §4). Un desplazamiento horizontal corto contra una
## caída de una decena de metros deja el ángulo muy por dentro de los 35°, y de los
## 55° que P4 abre.
func _belly_position(delta: float) -> Vector3:
	var centre := _enemy.global_position
	var ground := _ground_height(centre)
	_orbit_angle += _orbit_sign * BELLY_SWEEP_RATE * delta
	# El punto no es fijo: el radio y la altura barren despacio su rango. Con una
	# pose única, una partida entera podía quedarse sin exponer un solo núcleo
	# —bastaba que el coloso quedara encaramado a un edificio o que la creencia de
	# su percepción cayera justo fuera del cono— y la ronda no terminaba nunca.
	var offset := belly_offset + BELLY_SWEEP_SPAN * sin(_elapsed * BELLY_SWEEP_RATE)
	var lift := MIN_CLEARANCE + BELLY_LIFT_SPAN * (0.5 + 0.5 * cos(_elapsed * 0.31))
	return Vector3(centre.x + cos(_orbit_angle) * offset, ground + lift,
			centre.z + sin(_orbit_angle) * offset)


## Punto al que huir de la telegrafía en curso: radialmente hacia afuera del centro
## del ataque hasta pasar su radio con [constant DODGE_MARGIN] de margen.
func _dodge_position() -> Vector3:
	var position := _drone.global_position
	var away := position - _dodge_centre
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle))
	away = away.normalized()
	var target := _dodge_centre + away * (_dodge_radius + DODGE_MARGIN)
	target.y = maxf(position.y, _ground_height(target) + MIN_CLEARANCE)
	return target


## Pila activa más cercana mientras la batería esté por debajo del umbral, o
## [constant Vector3.INF] si no hace falta ir a buscar ninguna.
func _battery_target() -> Vector3:
	if _energy == null or _spawner == null or not is_instance_valid(_spawner):
		return Vector3.INF
	if _energy.get_ratio() >= energy_hunt_ratio:
		return Vector3.INF
	var origin := _drone.global_position
	var best := Vector3.INF
	var best_distance := INF
	for index: int in _spawner.get_marker_count():
		var pickup := _spawner.get_pickup(index)
		if pickup == null or not pickup.is_active():
			continue
		var distance := origin.distance_to(pickup.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup.global_position
	return best


## Altura del suelo —o del techo del edificio— bajo [param point].
func _ground_height(point: Vector3) -> float:
	var world := _drone.get_world_3d()
	if world == null:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 5.0,
			point + Vector3.DOWN * GROUND_PROBE, PhysicsLayers.QUERY_FOOT)
	query.collide_with_areas = false
	query.exclude = [_drone.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return (hit["position"] as Vector3).y


# --- Puntería ---------------------------------------------------------------------------------

## Remuestrea el error angular a [constant AIM_HZ] y orienta el cuerpo.
func _tick_aim(delta: float) -> void:
	_aim_accumulator += delta
	var period := 1.0 / AIM_HZ
	if _aim_accumulator >= period:
		_aim_accumulator = fmod(_aim_accumulator, period)
		_aim_error = Vector2(_gauss(), _gauss()) * deg_to_rad(aim_sigma_deg)
	_face(_aim_point())


## Punto al que apunta el bot: el punto débil elegido, adelantado por el tiempo de
## vuelo del proyectil, o el casco del jefe si no hay ninguno expuesto.
func _aim_point() -> Vector3:
	if _target != null and is_instance_valid(_target) and not _target.is_broken():
		var point := _target.world_position()
		return point + _lead(point)
	if _enemy != null and is_instance_valid(_enemy):
		return _enemy.global_position + Vector3.UP * _enemy.profile.hip_height
	return _drone.global_position - _drone.global_basis.z * 100.0


## Adelanto por tiempo de vuelo. El jefe camina a 6 m/s y el proyectil vuela a
## 420 m/s: a 40 m son 0.6 m de corrección, poco pero no cero.
func _lead(point: Vector3) -> Vector3:
	if _enemy == null or _weapon == null or _weapon.get_profile() == null:
		return Vector3.ZERO
	var speed := _weapon.get_profile().projectile_speed
	if speed <= 0.0:
		return Vector3.ZERO
	var flight := _drone.global_position.distance_to(point) / speed
	return _enemy_velocity() * flight


## Velocidad horizontal aparente del jefe, estimada de su propio movedor.
func _enemy_velocity() -> Vector3:
	if _enemy == null or _enemy.profile == null:
		return Vector3.ZERO
	var state := _enemy.locomotion_state()
	if state == &"IDLE" or state == &"DOWNED":
		return Vector3.ZERO
	return -_enemy.global_basis.z * _enemy.profile.walk_speed


## Gira el cuerpo para que la `FPVCamera` mire a [param point] con el error angular
## vigente.
##
## La cámara cuelga del [CameraRig], que le aplica la inclinación del hangar sobre
## el eje X del dron (`docs/03` §5). Para que `−FPVCamera.global_basis.z` —la
## dirección que usa el arma— caiga donde el bot quiere, hay que **descontar** esa
## inclinación de la base del cuerpo.
func _face(point: Vector3) -> void:
	var direction := point - _drone.global_position
	if direction.length() < 0.001:
		return
	direction = direction.normalized()
	var helper := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.995 else Vector3.RIGHT
	var right := helper.cross(direction).normalized()
	var up := direction.cross(right).normalized()
	direction = (direction + right * _aim_error.x + up * _aim_error.y).normalized()
	var camera_basis := Basis.looking_at(direction, Vector3.UP)
	var tilt := deg_to_rad(_camera_rig.get_tilt_degrees()) if _camera_rig != null else 0.0
	var body := camera_basis * Basis(Vector3.RIGHT, -tilt)
	_drone.global_basis = body.orthonormalized()


## Normal estándar por el método polar de Marsaglia, con el par en caché.
func _gauss() -> float:
	if _has_spare:
		_has_spare = false
		return _spare_gauss
	var u := 0.0
	var v := 0.0
	var s := 0.0
	while s <= 0.0 or s >= 1.0:
		u = _rng.randf() * 2.0 - 1.0
		v = _rng.randf() * 2.0 - 1.0
		s = u * u + v * v
	var factor := sqrt(-2.0 * log(s) / s)
	_spare_gauss = v * factor
	_has_spare = true
	return u * factor


# --- Gatillo y energía ------------------------------------------------------------------------

## Aprieta el gatillo cuando hay un punto débil expuesto. La cadencia, el calor y
## el cobro de energía los lleva el [WeaponMount]: el bot sólo sostiene el estado
## (`docs/08` §2.2).
##
## **Querer disparar y estar disparando son cosas distintas.** El gatillo se suelta
## durante el bloqueo por calor —un jugador no puede hacer otra cosa, y sostenerlo
## sólo engordaría la dispersión de ráfaga—, pero los segundos de bloqueo **sí**
## cuentan como fuego neto: el «fuego neto» de `docs/07` §8 es el denominador del
## que ya cuelga el ciclo de trabajo ×0.55, no el tiempo con balas saliendo.
func _tick_trigger(delta: float) -> void:
	if _weapon == null or not is_instance_valid(_weapon):
		return
	if not _drone.is_armed():
		_try_arm()
		_weapon.fire_pressed = false
		return
	_armed_seconds += delta
	var wants := _target != null and is_instance_valid(_target) \
			and not _target.is_broken() and _target.is_exposed() \
			and _drone.global_position.distance_to(_target.world_position()) <= fire_max_range
	_weapon.fire_pressed = wants and not _weapon.is_overheated()
	if wants:
		_fire_seconds += delta


## Arma el dron. El controlador exige acelerador bajo (`docs/03` §3.3), así que el
## comando se manda en cero **antes** de pedir el armado.
func _try_arm() -> void:
	if _energy != null and _energy.is_depleted():
		return
	_command.throttle = 0.0
	_drone.update_command(_command)
	var _armed := _drone.arm()


## Declara el acelerador emulado para que el [EnergySystem] drene como en una
## partida real: `base_drain + throttle_drain × throttle` (`docs/09` §2.1). Sin
## esto un dron cinemático volaría con el consumo de un dron posado.
func _feed_energy() -> void:
	_command.throttle = throttle if _drone.is_armed() else 0.0
	_drone.update_command(_command)


# --- Esquiva ----------------------------------------------------------------------------------

## Descuenta la ventana de esquiva y, al terminar, anota si salió bien.
func _tick_dodge(delta: float) -> void:
	_hold_left = maxf(_hold_left - delta, 0.0)
	if _dodge_left <= 0.0:
		return
	if _dodge_delay > 0.0:
		_dodge_delay = maxf(_dodge_delay - delta, 0.0)
	_dodge_left -= delta
	if _dodge_left > 0.0:
		return
	_dodge_left = 0.0
	var flat := _drone.global_position - _dodge_centre
	flat.y = 0.0
	if flat.length() > _dodge_radius:
		_dodges_made += 1
	_dodge_id = &""


## Una telegrafía del jefe. Si el ataque es esquivable por radio, el bot tira el
## dado de [member dodge_skill] y, si gana, sale del círculo durante el windup.
func _on_telegraphed(enemy: Node3D, attack_id: StringName, duration: float) -> void:
	if not _active or mode == Mode.IDLE or enemy != _enemy:
		return
	if not DODGEABLE.has(attack_id) or _library == null:
		return
	var action := _library.find(attack_id) as SweepAction
	if action == null:
		return
	_dodges_tried += 1
	if _rng.randf() >= dodge_skill:
		# Aviso no leído: el bot se queda donde está durante el windup y encaja.
		_hold_left = duration
		return
	_dodge_id = attack_id
	_dodge_centre = _danger_centre(attack_id, action)
	_dodge_radius = _danger_radius(attack_id, action)
	_dodge_delay = reaction_seconds
	_dodge_left = maxf(duration, reaction_seconds + 0.05)


## Centro del volumen que hay que abandonar. Los ataques que caen sobre el dron
## usan el punto al que apunta la acción —el mismo que dibuja el decal—; los que
## salen del cuerpo del jefe, su cadera.
func _danger_centre(attack_id: StringName, action: SweepAction) -> Vector3:
	if attack_id == &"emp_pulse" or attack_id == &"shake_off" or attack_id == &"leg_sweep":
		return _enemy.global_position
	return action.aim_point()


## Radio del que hay que salir. Para casi todos es el del volumen de resolución;
## `leg_sweep` es la excepción porque su caja de 14 × 4 × 3 barre un arco de 160°
## alrededor del cuerpo y lo que define la zona peligrosa es el **alcance** del
## ataque, no el ancho de la caja (`docs/07` §5.5).
func _danger_radius(attack_id: StringName, action: SweepAction) -> float:
	if attack_id == &"leg_sweep" and action.profile != null:
		return action.profile.max_range
	return action.shape_radius()


# --- Bus --------------------------------------------------------------------------------------

func _connect_bus() -> void:
	var _discard := Events.enemy_attack_telegraphed.connect(_on_telegraphed)
	_discard = Events.hit_confirmed.connect(_on_hit_confirmed)
	_discard = Events.shot_fired.connect(_on_shot_fired)
	_discard = Events.battery_collected.connect(_on_battery_collected)
	_discard = Events.drone_damaged.connect(_on_drone_damaged)


func _disconnect_bus() -> void:
	for pair: Array in [
		[Events.enemy_attack_telegraphed, _on_telegraphed],
		[Events.hit_confirmed, _on_hit_confirmed],
		[Events.shot_fired, _on_shot_fired],
		[Events.battery_collected, _on_battery_collected],
		[Events.drone_damaged, _on_drone_damaged],
	]:
		var signal_ref: Signal = pair[0]
		var callable: Callable = pair[1]
		if signal_ref.is_connected(callable):
			signal_ref.disconnect(callable)


func _on_shot_fired(_origin: Vector3, _direction: Vector3) -> void:
	if _active:
		_shots += 1


func _on_hit_confirmed(_position: Vector3, weak: bool, _lethal: bool) -> void:
	if not _active:
		return
	if weak:
		_weak_hits += 1
	else:
		_armor_hits += 1


func _on_battery_collected(_amount: float, _position: Vector3) -> void:
	if _active:
		_batteries += 1


func _on_drone_damaged(amount: float, _source_position: Vector3) -> void:
	if not _active:
		return
	_damage_taken += amount
	_hits_taken += 1


func _fire_rate() -> float:
	if _weapon == null or _weapon.get_profile() == null:
		return 8.0
	return maxf(_weapon.get_profile().fire_rate, 0.001)
