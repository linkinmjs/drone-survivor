## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Marcha procedural cuadrúpeda con IK de dos huesos (`docs/06` §8).
##
## Es el nodo `Locomotion` del árbol de `docs/06` §2 y reemplaza al placeholder
## de WP-16. Cada tick de física:
##
## 1. Mide cuánto se alejó cada pie de su reposo y cuánto le queda de cadena, y
##    con eso decide cuál pide paso.
## 2. Deja que el [GaitController] arbitre: pares diagonales en `TROT`, una
##    pata por vez en `TRIPOD` y en `DRAG`, todas libres en `LEAP`. Sólo la que
##    gana el turno tira el `intersect_ray` de colocación (máscara
##    `world | city`), así el rig cuesta un rayo por paso y no cuatro por tick.
## 3. Fija la **altura** del cuerpo sobre la media de los pies apoyados y su
##    **inclinación** con el plano de mínimos cuadrados del apoyo.
## 4. Resuelve el IK de cada pata con [TwoBoneIK] y escribe las bases locales.
##
## [b]Reparto de responsabilidades[/b]: la posición **XZ** del cuerpo la manda
## `EnemyBase.move_body()` (y en WP-18 el cerebro que la llama). El rig sólo
## escribe **Y** y la **base**, y mueve las patas. La única excepción es el
## vuelo balístico del salto, donde el rig integra la parábola completa porque
## el cuerpo ya no toca nada (`docs/06` §8.6).
##
## [b]Altura del cuerpo[/b]: `hip_height` (14 m) es la altura de la **cadera**
## sobre la media de los pies, no la del origen del nodo. El origen del modelo
## está a ras del suelo en la pose de reposo, con la cadera a 17.25 m, así que
## [method body_height_target] devuelve `media_de_pies + hip_height − 17.25`.
## Esos 3.25 m de agachada son los que doblan la rodilla: la pose de reposo del
## GLB trae la cadena al 99.7 % de extensión y caminar así sería imposible.
##
## [b]Marcha creíble (WP-24d)[/b]. El rig de WP-17 cumplía los umbrales de
## `docs/06` §16.2 y aun así se veía mal: el jefe «se movía raro». Siete cambios,
## todos medibles en `gait_check`:
##
## 1. [b]Huella lateral[/b] (`stance_spread`, ahora en ±X): el pie nace 5 m más
##    afuera, el fémur se inclina y la rodilla sube de 7.9 m a 9.4 m.
## 2. [b]Zancada centrada[/b] ([method _step_target]): el objetivo lleva el
##    avance del vuelo **más** media zancada, así la pata posa por delante tanto
##    como despega por detrás en vez de vivir arrastrada.
## 3. [b]Arco con peso[/b] ([method _advance_step]): `smootherstep` horizontal y
##    un arco sesgado que llega al contacto con velocidad cero.
## 4. [b]Apoyo alcanzable[/b] ([method _project]): el rayo elige entre cinco
##    objetivos el primero que la cadena alcance, en vez de plantar el pie en el
##    primer punto sólido aunque esté 30 m más abajo.
## 5. [b]Cuerpo vivo[/b]: rebote en fase con el ciclo, balanceo de ≤ 3°,
##    respiración de servos en reposo, flexión de rodillas al aterrizar y los
##    25° de cabeceo que `docs/07` §5.3 le pide al trepado.
## 6. [b]Terreno difícil[/b]: la cadera se hunde cuando el apoyo pide más cadena
##    de la que hay ([method _reach_crouch]) y el vuelo en curso se apura cuando
##    la pata que aguanta se queda corta ([method _hurry_factor]).
## 7. [b]Giro[/b]: umbral de paso propio (`turn_step_trigger`) y paso más corto,
##    de modo que girar son pasos en el lugar y no un pie arrastrado.
class_name ProceduralLegRig extends Node3D

## Se apoyó un pie. [param impact_speed] alimenta el volumen de la pisada.
signal foot_planted(leg_index: int, position: Vector3, impact_speed: float)

## Se perdió una pata.
signal leg_broken(leg_index: int)

## Terminó un salto: los cuatro pies volvieron al suelo.
signal leap_landed(position: Vector3)

## Estados de la capa de locomoción (`docs/06` §11.1).
const STATE_IDLE: StringName = &"IDLE"
const STATE_WALK: StringName = &"WALK"
const STATE_TURN: StringName = &"TURN"
const STATE_CLIMB: StringName = &"CLIMB"
const STATE_LEAP: StringName = &"LEAP"
const STATE_STAGGER: StringName = &"STAGGER"
const STATE_DOWNED: StringName = &"DOWNED"

## Fases del salto (`docs/06` §8.6).
enum LeapPhase { NONE, TUCK, FLIGHT, LAND }

## Penalización de velocidad por pata perdida cuando no hay [EnemyProfile].
const DEFAULT_LEG_PENALTY: float = 0.15

## Altura de cadera por defecto cuando no hay [EnemyProfile], en metros.
const DEFAULT_HIP_HEIGHT: float = 14.0

## Sesgo hacia atrás del vector de polo: con él las rodillas se arquean hacia
## afuera **y atrás**, como las de una araña.
const KNEE_POLE_BACK: float = 0.30

## Piso de elevación de la rodilla que el rig le pide al IK (`TwoBoneIK.solve`).
const KNEE_MIN_LIFT: float = 0.30

## Sesgo hacia arriba del vector de polo (WP-24d).
##
## El polo define en qué dirección sale la rodilla del segmento cadera→tobillo.
## Con el polo puramente horizontal, esa dirección se inclina con la pata: en
## cuanto el pie queda del lado de dentro de su cadera —un tranco que cruzó, un
## giro a medias— la rodilla se va hacia **abajo y hacia adentro**, que es
## exactamente la pose que rompe la silueta de araña. Con una componente
## vertical el polo garantiza un piso: la rodilla sale siempre hacia arriba,
## salga hacia donde salga en horizontal.
const KNEE_POLE_UP: float = 0.30

## Velocidad por debajo de la cual el cuerpo se considera quieto, en m/s.
const IDLE_SPEED: float = 0.25

## Giro por encima del cual el estado es `TURN`, en grados por segundo.
const TURN_RATE_EPS: float = 2.0

## Fracción del alcance a la que se recorta el re-balance de reposos.
const REBALANCE_LIMIT: float = 0.35

## Tope del adelanto del objetivo del paso, como fracción de la cadena.
##
## El adelanto de [method _step_target] vale `v · step_time + step_trigger`, que
## a velocidad de crucero son 8.3 m y no crece: por encima de `speed_ref` la
## duración del paso se acorta en la misma proporción. El tope es contra una
## velocidad disparatada (un empujón, un `time_scale` alto), no contra la marcha.
const MAX_STRIDE_REACH: float = 0.70

## Velocidad a la que el adelanto por `step_trigger` ya entra entero, en m/s.
const LEAD_RAMP_SPEED: float = 1.0

## Giro a partir del cual el adelanto angular por `step_trigger` entra entero,
## en rad/s.
const TURN_LEAD_RATE: float = 0.20

## Sesgo del vértice del arco del paso: el pie sube pronto y baja tarde.
const STEP_LIFT_SKEW: float = 0.80

## Agudeza del arco. Por encima de 1 la velocidad vertical del pie llega a cero
## en el contacto, que es lo que hace que el apoyo se lea firme.
const STEP_LIFT_SHARPNESS: float = 1.35

## Ritmo con el que entra y sale la respiración de reposo, en s⁻¹.
const IDLE_BLEND_RATE: float = 3.0

## Ritmo con el que entra y sale el cabeceo del trepado, en s⁻¹.
const CLIMB_BLEND_RATE: float = 1.6

## Fracción de la cadena por encima de la cual el cuerpo empieza a agacharse.
const COMFORT_REACH: float = 0.86

## Cuánto puede hundirse la cadera para que el apoyo llegue, en metros.
const MAX_REACH_CROUCH: float = 5.0

## Fracción de la cadena a partir de la cual el vuelo en curso se acelera.
const HURRY_REACH: float = 0.88

## Cuánto llega a acelerarse el vuelo cuando la pata apoyada se queda sin cadena.
const MAX_HURRY: float = 2.2

## Ritmo con el que la cadera **baja** para que el apoyo llegue, en s⁻¹. Bajar
## es urgente —el pie ya no llega— y subir no, así que la recuperación usa el
## suavizado normal del cuerpo.
const REACH_SINK_RATE: float = 12.0

## Apoyo mínimo antes de que una pata pueda volver a pedir paso, como fracción
## de la duración del paso.
##
## El desvío que dispara el paso se mide **sin signo**, y con la zancada centrada
## de WP-24d el pie aterriza justo a `step_trigger` de su reposo: sin esta
## histéresis la pata pediría turno en el mismo tick en que apoya. Un apoyo
## mínimo es además lo que impide el castañeteo en terreno irregular, y se mide
## en fracciones del paso para que valga igual a 6 m/s que arrastrándose.
const MIN_STANCE_RATIO: float = 0.35

## Cuánto más urgente es un paso de giro que uno de avance a la misma velocidad
## de pie.
##
## Girando en el sitio el pie viaja de costado, justo en la dirección en la que
## la pata ya nace separada del cuerpo, así que el mismo desplazamiento le cuesta
## mucha más cadena que avanzando. Con el paso un 60 % más corto y más frecuente
## el giro son **pasos cortos en el lugar** —lo que hace un cuadrúpedo pesado— y
## ningún pie se queda arrastrado media vuelta por detrás.
const TURN_STEP_URGENCY: float = 1.6

## Fracción de la cadena (sin estirar) hasta la que se acepta un apoyo nuevo.
##
## Un rayo puede devolver un punto perfectamente sólido y perfectamente
## inalcanzable: el borde de una escalera de 12 m, el pie de una torre, el filo
## de la rampa. Plantar ahí deja el pie colgando en el aire —2.6 m medidos en
## WP-24d— porque el IK no llega. Con este tope el objetivo se retrae como manda
## `docs/06` §8.4 para el abismo, y la zancada se acorta sola en rampa y en
## escalón, que es además lo que haría cualquier cuadrúpedo.
const PLANT_REACH: float = 0.97

## Media longitud del rayo corto que confirma el apoyo, en metros.
const SUPPORT_SPAN: float = 3.0

## Tope del giro medido, en rad/s. Un pico numérico no puede mandar el objetivo
## de un paso al otro lado del mapa.
const MAX_YAW_RATE: float = 2.0

## Tope del giro que se anticipa al colocar un pie, en radianes.
const MAX_TURN_LEAD: float = 0.7854

## Sacudida de cámara al aterrizar un salto (`docs/06` §8.6 punto 4).
const LAND_TRAUMA: float = 0.5

## Ajustes del rig. Los inyecta [EnemyBase] desde `EnemyProfile.leg_rig`.
@export var profile: LegRigProfile = null

## Si el rig se mueve solo en `_physics_process`. WP-18 puede apagarlo para
## llamar [method rig_tick] desde la máquina de estados.
@export var auto_tick: bool = true

## Dibujo de depuración con [DebugGeometry]; sólo hace algo con `--debug`.
@export var debug_draw: bool = true

## Patas del rig, en el orden en que las agrupó [EnemyBase].
var legs: Array[Leg] = []

## Datos crudos que pasó [EnemyBase] (`docs/06` §2.1 punto 6).
var leg_data: Array[Dictionary] = []

## Índices de las patas perdidas.
var broken_legs: Dictionary[int, bool] = {}

var _gait: GaitController = GaitController.new()
var _enemy: Node3D = null
var _body: Node3D = null
var _ready_to_walk: bool = false
var _needs_snap: bool = true
var _state: StringName = STATE_IDLE
var _ground_height: float = 0.0
var _plane_normal: Vector3 = Vector3.UP
var _basis_target: Basis = Basis.IDENTITY
var _hip_local_height: float = 0.0
var _foot_radius: float = 1.0
var _speed: float = 0.0
var _heading: Vector3 = Vector3.FORWARD
var _last_yaw: float = 0.0
var _yaw_rate: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _climbing: bool = false
var _stagger_left: float = 0.0
var _stagger_phase: float = 0.0
var _crouch: float = 0.0
var _rebalance_from: Vector3 = Vector3.ZERO
var _rebalance_to: Vector3 = Vector3.ZERO
var _rebalance_t: float = 1.0
var _leap_phase: int = LeapPhase.NONE
var _leap_time: float = 0.0
var _leap_flight: float = 1.0
var _leap_landing: Vector3 = Vector3.ZERO
var _leap_velocity: Vector3 = Vector3.ZERO
var _leap_predicted: bool = false
var _support_cursor: int = 0
var _pose_override: Dictionary[int, Vector3] = {}
var _crouch_hold: float = 0.0
var _query: PhysicsRayQueryParameters3D = null
var _exclude: Array[RID] = []
var _tick_usec: int = 0
var _tick_count: int = 0
var _last_tick_usec: int = 0
var _cycle_phase: float = 0.0
var _gait_activity: float = 0.0
var _climb_blend: float = 0.0
var _idle_time: float = 0.0
var _reach_sink: float = 0.0
var _climb_intent: bool = false


func _ready() -> void:
	_body = get_parent() as Node3D
	_enemy = _body
	_query = PhysicsRayQueryParameters3D.new()
	_query.collide_with_areas = false
	_query.collide_with_bodies = true


## Mueve el rig un tick por su cuenta. La velocidad sale del desplazamiento
## real del cuerpo, así da igual quién lo haya movido (`move_body`, un check o
## el cerebro de WP-18).
func _physics_process(delta: float) -> void:
	if not auto_tick or not _ready_to_walk or delta <= 0.0:
		return
	# Congelado por `Global.debug_freeze_ai` (`docs/11` §11): el rig no tiquea y
	# se le refresca la referencia de posición, para que al soltar la bandera no
	# lea como velocidad todo lo que el cuerpo se movió mientras tanto.
	if Global.debug_freeze_ai:
		_last_position = _body.global_position
		return
	var moved := _body.global_position - _last_position
	moved.y = 0.0
	rig_tick(delta, moved / delta)


# --------------------------------------------------------------------------
# Interfaz pública (`docs/06` §14)
# --------------------------------------------------------------------------

## Recibe las patas agrupadas por [EnemyBase] y mide la pose de reposo.
func setup(data: Array[Dictionary]) -> void:
	leg_data = data
	legs.clear()
	if _body == null:
		_body = get_parent() as Node3D
		_enemy = _body
	if _body == null:
		push_error("ProceduralLegRig: el nodo no cuelga de un Node3D.")
		return

	var hip_sum := 0.0
	var radius_sum := 0.0
	for entry: Dictionary in data:
		var leg := Leg.new()
		var pole := _pole_for(entry)
		# La huella de marcha se abre **hacia los lados** sobre la del modelo
		# (`LegRigProfile.stance_spread`): es lo que separa el tobillo de la
		# cadera en horizontal, dobla la rodilla y la saca del cuerpo. Va dentro
		# de `bind()` para que la coxa mida su reposo contra la huella ya abierta.
		if not leg.bind(entry, _body, pole, _spread()):
			Global.startup_errors.append("ERR_ENEMY_LEG_INCOMPLETE")
			push_error("ProceduralLegRig: la pata %d no se pudo medir." % legs.size())
			continue
		hip_sum += leg.hip_offset.y
		radius_sum += Vector2(leg.rest_offset.x, leg.rest_offset.z).length()
		legs.append(leg)

	if legs.is_empty():
		return
	_hip_local_height = hip_sum / float(legs.size())
	_foot_radius = maxf(radius_sum / float(legs.size()), 0.1)
	_gait.setup(legs, profile)
	_collect_exclusions()
	_last_position = _body.global_position
	_last_yaw = _heading_yaw()
	_needs_snap = true
	_ready_to_walk = true


## Avanza el rig un tick de física (`docs/06` §14).
##
## [param body_velocity] es la velocidad horizontal real del cuerpo; se usa para
## la duración del paso, para el adelanto del objetivo y para el estado.
func rig_tick(delta: float, body_velocity: Vector3) -> void:
	if not _ready_to_walk or delta <= 0.0:
		return
	var started := Time.get_ticks_usec()

	var flat := Vector3(body_velocity.x, 0.0, body_velocity.z)
	_speed = flat.length()
	_heading = flat.normalized() if _speed > 0.0001 else _heading
	_track_yaw(delta)
	_tick_stagger(delta)
	_tick_rebalance(delta)
	if _needs_snap:
		snap_to_ground()
		_needs_snap = false

	if _leap_phase != LeapPhase.NONE:
		_tick_leap(delta)
	elif _is_downed():
		_tick_downed(delta)
	else:
		_tick_walk(delta)

	_apply_legs()
	_update_state()
	_last_position = _body.global_position

	_last_tick_usec = Time.get_ticks_usec() - started
	_tick_usec += _last_tick_usec
	_tick_count += 1
	# El dibujo de depuración queda **fuera** del cronómetro a propósito: el
	# presupuesto de 0.25 ms de `docs/06` §15 mide el rig, y con `Global.debug`
	# apagado —o sea, en todo lo que no sea una corrida de desarrollo— estas
	# llamadas no hacen nada. Medirlas daría un número que el juego nunca paga.
	_draw_debug()


## Altura de mundo a la que el rig quiere el **origen** del cuerpo, para que la
## cadera quede a `hip_height` sobre la media de los pies apoyados.
##
## Caído (`DOWNED`) manda [member LegRigProfile.downed_body_height] y el coloso
## **descansa sobre el suelo** en vez de hundirse. El cálculo va acá y no sólo en
## [method _tick_downed] a propósito: [method snap_to_ground] y el suavizado de
## [method _apply_body_pose] pasan por esta función, y si no lo respetaran
## devolverían el cuerpo a la pose de marcha en el primer tick.
func body_height_target() -> float:
	if _is_downed():
		return _ground_height + _profile().downed_body_height
	return _ground_height + _hip_height() - _hip_local_height


## Base objetivo del cuerpo, del plano de mínimos cuadrados del apoyo.
func body_basis_target() -> Basis:
	return _basis_target


## Patas que sostienen el cuerpo ahora mismo.
func planted_count() -> int:
	return _gait.planted_count()


## Multiplicador de velocidad por patas perdidas (`docs/06` §8.7).
func speed_multiplier() -> float:
	if _is_downed():
		return 0.0
	return _gait.speed_multiplier(broken_legs.size(), _leg_penalty())


## Da de baja la pata [param leg_index]: deja de recibir IK, el
## [GaitController] recalcula el modo y los reposos se re-balancean hacia el
## centroide del apoyo que queda (`docs/06` §8.7).
func notify_leg_broken(leg_index: int) -> void:
	if broken_legs.has(leg_index):
		return
	broken_legs[leg_index] = true
	for leg: Leg in legs:
		if leg.index == leg_index:
			leg.broken = true
			leg.planted = false
			leg.step_t = Leg.PLANTED
	_gait.refresh()
	_start_rebalance()
	leg_broken.emit(leg_index)


## Estado de la capa de locomoción que reporta [EnemyBase] (`docs/06` §11.1).
func locomotion_state() -> StringName:
	return _state


# --------------------------------------------------------------------------
# Poses forzadas por las acciones (WP-19)
# --------------------------------------------------------------------------

## Lleva el tobillo de la pata [param leg_index] a [param world_point] y la saca
## del ciclo de paso hasta [method release_leg].
##
## Es lo que necesitan las coreografías de `docs/07`: el pisotón levanta la pata
## delantera a 1.6 × `hip_height` durante el aviso (§5.4) y el barrido retrae la
## suya 60° (§5.5). Mientras dura, la pata [b]no cuenta como apoyada[/b], que es
## justo lo que hace verificable el gate de apoyo: si al entrar en `ACTIVE` no
## quedan dos patas más en el suelo, el golpe se va al aire.
func raise_leg(leg_index: int, world_point: Vector3) -> void:
	var leg := leg_at(leg_index)
	if leg == null or leg.broken:
		return
	_pose_override[leg_index] = world_point
	leg.planted = false
	leg.step_t = Leg.PLANTED
	leg.foot_position = world_point


## Mueve el punto de una pata ya levantada, sin volver a sacarla del ciclo.
func move_raised_leg(leg_index: int, world_point: Vector3) -> void:
	if not _pose_override.has(leg_index):
		return
	_pose_override[leg_index] = world_point
	var leg := leg_at(leg_index)
	if leg != null:
		leg.foot_position = world_point


## Devuelve la pata [param leg_index] al ciclo de paso: vuelve a apoyarla donde
## tenga suelo debajo.
func release_leg(leg_index: int) -> void:
	if not _pose_override.has(leg_index):
		return
	var _erased := _pose_override.erase(leg_index)
	var leg := leg_at(leg_index)
	if leg == null or leg.broken:
		return
	var ground := _ray(leg.rest_world(_body.global_transform))
	leg.plant_position = ground["point"] as Vector3
	leg.plant_normal = ground["normal"] as Vector3
	leg.plant_collider = ground["collider"]
	leg.plant_is_city = bool(ground["city"])
	leg.target = leg.plant_position
	leg.target_normal = leg.plant_normal
	leg.foot_position = leg.plant_position
	leg.planted = true
	leg.supported = true
	leg.step_t = Leg.PLANTED


## Devuelve todas las patas levantadas al ciclo de paso.
func release_all_legs() -> void:
	for leg_index: int in _pose_override.keys():
		release_leg(leg_index)


## `true` si la pata [param leg_index] está fuera del ciclo por una pose forzada.
func is_leg_raised(leg_index: int) -> bool:
	return _pose_override.has(leg_index)


## Pata de índice [param leg_index], o `null`.
func leg_at(leg_index: int) -> Leg:
	for leg: Leg in legs:
		if leg.index == leg_index:
			return leg
	return null


## Índice de la pata **delantera** del lado de [param point], o `-1` si no queda
## ninguna sana (`docs/07` §5.4: «la pata delantera del lado del dron»).
##
## «Delantera» se mide en espacio del cuerpo: `-Z` es el frente. Entre las dos
## delanteras gana la que esté del mismo lado que el objetivo; si la del lado
## correcto se perdió, sirve la otra, y si no quedan delanteras, la trasera más
## cercana al objetivo.
func front_leg_toward(point: Vector3) -> int:
	if legs.is_empty():
		return -1
	var to_local := _body.global_transform.affine_inverse() * point
	var best := -1
	var best_score := -1.0e9
	for leg: Leg in legs:
		if leg.broken or _pose_override.has(leg.index):
			continue
		var offset := leg.base_rest_offset
		# Frente pesa el doble que el lado: primero delantera, después lado.
		var forward := -offset.z
		var lateral := signf(offset.x) * signf(to_local.x) * absf(offset.x)
		var score := forward * 2.0 + lateral
		if score > best_score:
			best_score = score
			best = leg.index
	return best


## Punto de apoyo actual de la pata [param leg_index], en mundo.
func leg_plant_position(leg_index: int) -> Vector3:
	var leg := leg_at(leg_index)
	return leg.plant_position if leg != null else Vector3.ZERO


## Agacha el cuerpo una fracción [param value] de `hip_height`, y lo mantiene
## hasta [method clear_crouch].
##
## `0.4` deja la cadera al 60 %, que es el `tuck` del salto de `docs/07` §5.9.
func set_crouch(value: float) -> void:
	_crouch_hold = clampf(value, 0.0, 0.9)


## Devuelve el cuerpo a su altura nominal.
func clear_crouch() -> void:
	_crouch_hold = 0.0


## Agachada vigente: la mayor entre la del salto y la que pidió una acción.
func crouch() -> float:
	return maxf(_crouch, _crouch_hold)


## Enciende o apaga la **intención de trepar** (`docs/07` §5.3).
##
## Con ella activa, el rayo de colocación prefiere un techo de ciudad por encima
## del apoyo actual entre todos los candidatos que prueba, en vez de quedarse con
## el primero que la cadena alcance. Es lo que convierte a `climb` en una
## decisión de verdad: sin ella, un coloso con 22 m de huella nunca posaría un
## pie sobre una torre de 18 m de lado —sus reposos caen fuera de la huella del
## edificio— y trepar dependería de que el terreno se lo regalara.
##
## La enciende [ActionClimb] al abrir su ventana activa y la apaga al cerrarla.
func set_climb_intent(active: bool) -> void:
	_climb_intent = active


## `true` mientras el rig busca activamente un techo donde apoyar.
func has_climb_intent() -> bool:
	return _climb_intent


## Modo de marcha actual: `TROT`, `TRIPOD`, `DRAG`, `LEAP` o `IDLE`.
func gait_name() -> StringName:
	return _gait.gait_name()


## Índice del par diagonal al que pertenece la pata [param leg_index].
func pair_of(leg_index: int) -> int:
	return _gait.pair_of(leg_index)


## Salta hacia [param target_position] resolviendo la parábola: vértice
## proporcional a la distancia, con tope [member LegRigProfile.jump_max_height],
## y distancia recortada a [member LegRigProfile.jump_max_distance].
func jump(target_position: Vector3) -> void:
	var from := _body.global_position
	var to := target_position
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var max_distance := _profile().jump_max_distance
	if flat.length() > max_distance:
		flat = flat.normalized() * max_distance
		to = Vector3(from.x + flat.x, to.y, from.z + flat.z)
	var gravity := maxf(_profile().leap_gravity, 0.1)
	var apex := clampf(flat.length() * 0.35, _profile().step_height_min,
			_profile().jump_max_height)
	# El vértice se mide sobre el punto de salida; si el destino está más alto,
	# hay que levantarlo también a él o la parábola no llega.
	var rise := maxf(to.y - from.y, 0.0)
	apex = clampf(apex, rise + 1.0, maxf(_profile().jump_max_height, rise + 1.0))
	var vertical := sqrt(2.0 * gravity * apex)
	var fall := maxf(vertical * vertical - 2.0 * gravity * (to.y - from.y), 0.0)
	var flight := (vertical + sqrt(fall)) / gravity
	begin_leap(to, maxf(flight, 0.2))


## Arranca el salto hacia [param landing] con [param flight_time] segundos de
## vuelo (`docs/06` §8.6). Antes del vuelo hay `leap_tuck_time` de recogida.
##
## [param skip_tuck] se salta esa recogida y lanza el cuerpo en el acto. Lo usa
## `pounce` (`docs/07` §5.9), que ya se agachó durante sus 1.3 s de aviso: con la
## recogida encima, los 1.2 s de ventana activa terminarían medio segundo antes
## de que el jefe tocara el suelo.
func begin_leap(landing: Vector3, flight_time: float, skip_tuck: bool = false) -> void:
	if not _ready_to_walk or _is_downed():
		return
	_pose_override.clear()
	_leap_landing = landing
	_leap_flight = maxf(flight_time, 0.1)
	_leap_time = 0.0
	_leap_predicted = false
	_leap_phase = LeapPhase.FLIGHT if skip_tuck or _profile().leap_tuck_time <= 0.0 \
			else LeapPhase.TUCK
	if _leap_phase == LeapPhase.FLIGHT:
		_launch()
	_gait.set_leaping(true)
	for leg: Leg in legs:
		leg.planted = false
		leg.step_t = Leg.PLANTED


## `true` mientras dura el salto, en cualquiera de sus tres fases.
func is_leaping() -> bool:
	return _leap_phase != LeapPhase.NONE


## Tambalea la marcha [param seconds]: se congelan los pasos nuevos y el cuerpo
## bambolea (`docs/06` §7 punto 6).
func stagger(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_stagger_left = maxf(_stagger_left, seconds)
	if _enemy != null and _enemy.has_method(&"request_stagger"):
		_enemy.call(&"request_stagger", seconds, &"")


## Coste del último tick en microsegundos (`docs/06` §15: < 0.25 ms).
func last_tick_usec() -> int:
	return _last_tick_usec


## Coste medio por tick en microsegundos desde el último [method reset_metrics].
func average_tick_usec() -> float:
	return float(_tick_usec) / float(maxi(_tick_count, 1))


## Reinicia los acumuladores de coste.
func reset_metrics() -> void:
	_tick_usec = 0
	_tick_count = 0


# --------------------------------------------------------------------------
# Marcha
# --------------------------------------------------------------------------

## Un tick de marcha normal: colocación, disparo de paso, arco y pose del cuerpo.
func _tick_walk(delta: float) -> void:
	var body_xform := _body.global_transform
	# Con la locomoción bloqueada el rig **no arranca pasos nuevos**: es lo que
	# hace que la telegrafía de un ataque plante las patas (`docs/06` §11.1 y
	# §10.2). Sin esto, el `tuck` del salto bajaría el cuerpo, los reposos se
	# alejarían de los apoyos y el trote levantaría dos patas justo en el
	# instante en que el gate de apoyo las cuenta.
	var frozen := _stagger_left > 0.0 or _is_staggered() or _is_locomotion_locked()
	# El trote serializa los pares: mientras uno vuela, el otro **tiene** que
	# aguantar, y en una rampa de 20° el cuerpo le sube 1.6 m encima en lo que
	# dura el vuelo — más cadena de la que le queda. Cuando eso pasa, el vuelo en
	# curso se apura hasta 2.2×: el turno del par que sufre llega antes, la
	# invariante del trote no se toca y el paso rápido se lee como lo que es, un
	# tranco corto de terreno difícil.
	var hurry := _hurry_factor()
	for leg: Leg in legs:
		if leg.broken:
			continue
		if leg.is_airborne():
			_advance_step(leg, delta * hurry)
		else:
			leg.stance_time += delta
	_refresh_support()
	if not frozen:
		_choose_step(body_xform)
	_tick_cycle(delta)
	_apply_body_pose(delta)


## Avanza la fase del ciclo de marcha y la mezcla marcha/reposo.
##
## La fase corre sola a `1 / (2 · step_time)` —un ciclo son los dos pares— y
## [method _choose_step] la re-sincroniza en cada despegue, así el rebote no se
## va a la deriva cuando la cadencia cambia. `_gait_activity` es la que apaga el
## rebote y enciende la respiración cuando el coloso se planta.
func _tick_cycle(delta: float) -> void:
	_idle_time += delta
	var step_time := _gait.step_time_for(_effective_speed())
	_cycle_phase = fposmod(_cycle_phase + delta / maxf(2.0 * step_time, 0.01), 1.0)
	var moving := _speed > IDLE_SPEED or absf(_yaw_rate) > deg_to_rad(TURN_RATE_EPS)
	_gait_activity = lerpf(_gait_activity, 1.0 if moving else 0.0,
			1.0 - exp(-IDLE_BLEND_RATE * delta))
	_gait.blend(delta)


## Elige **una sola** pata —y en trote su diagonal— para dar el paso: la más
## necesitada de todas las que el [GaitController] deja despegar.
##
## Que cada pata se disparara por su cuenta no bastaba: la pata que acababa de
## apoyar volvía a pedir turno en el mismo tick y el par contrario se quedaba
## sin pisar nunca. Elegir por necesidad reparte los turnos solo.
func _choose_step(body_xform: Transform3D) -> void:
	var best_need := 1.0
	var best: Leg = null
	for leg: Leg in legs:
		if leg.broken or leg.is_airborne() or not _gait.can_lift(leg):
			continue
		if _pose_override.has(leg.index):
			continue
		var need := _step_need(leg, body_xform)
		if need >= best_need:
			best_need = need
			best = leg
	if best == null:
		return
	if not _begin_step(best, body_xform):
		return
	# El rebote del cuerpo se re-sincroniza con el par que sale: media fase por
	# par, de modo que la cadera esté abajo justo en el intercambio de apoyos.
	_cycle_phase = 0.5 * float(maxi(_gait.pair_of(best.index), 0) % 2)
	# En trote la diagonal compañera despega en el mismo instante, la necesite o
	# no: eso es exactamente un trote, y es lo que mantiene el par en fase.
	var partner := _gait.partner_of(best)
	if partner != null and not partner.is_airborne():
		var _stepped := _begin_step(partner, body_xform)


## Urgencia del paso de una pata, normalizada a 1 (`docs/06` §8.4): se alejó de
## su reposo más que `step_trigger`, la cadena llegó a `reach_trigger` de su
## alcance, o el rayo ya no encuentra suelo donde apoyaba.
##
## El desvío se mide **sin signo** contra el reposo de ahora —no contra el
## objetivo del paso, que lleva el adelanto—, y la histéresis la pone
## [constant MIN_STANCE_RATIO]. Con la zancada centrada de WP-24d el desvío
## recorre `step_trigger` → 0 → `step_trigger` a lo largo del apoyo, así que el
## umbral se cumple justo al aterrizar y justo al despegar; el apoyo mínimo es lo
## que separa los dos casos. Medirlo con signo sobre la dirección de fuga del
## reposo, que fue el primer intento, deja pasar la deriva **perpendicular** —la
## de un giro mientras se avanza— y la pata se quedaba media vuelta por detrás.
##
## La cadena, en cambio, no espera: si el tramo cadera→tobillo ya se pasó de
## `reach_trigger`, la pata pide turno aunque acabe de apoyar.
func _step_need(leg: Leg, body_xform: Transform3D) -> float:
	if not leg.supported:
		return 4.0
	var span := leg.hip_world().distance_to(leg.plant_position + Vector3.UP * leg.ankle_lift)
	var limit := (leg.femur_length + leg.tibia_length) * maxf(_profile().reach_trigger, 0.01)
	var reach_need := span / limit
	if leg.stance_time < MIN_STANCE_RATIO * maxf(leg.step_time, 0.01):
		return reach_need
	# Trepando, una pata que todavía pisa la calle siempre tiene algo que hacer:
	# tantear el techo. Sin esto el coloso llega al pie de la torre, se planta
	# —ya no hay deriva que dispare nada— y no vuelve a levantar un pie.
	if _climb_intent and not leg.plant_is_city:
		return maxf(reach_need, 1.0)
	var drift := _rest_now(leg, body_xform) - leg.plant_position
	drift.y = 0.0
	return maxf(drift.length() / _trigger(), reach_need)


## Umbral de paso vigente: [member LegRigProfile.step_trigger] avanzando y
## [member LegRigProfile.turn_step_trigger] girando, mezclados por cuánto manda
## el giro sobre el avance.
##
## Girando en el sitio el pie se desplaza **de costado**, y de costado la pata ya
## nace a `stance_spread` de la cadera: 3 m más de deriva lateral dejan el
## tobillo a 7.6 m en horizontal y la cadena se queda sin alcance (medido en
## WP-24d: 0.78 m de deslizamiento y `stretched` en el giro de la rampa). Con
## pasos cortos en el lugar el giro no arrastra un solo pie: 0.003 m medidos en
## el giro de 180° de `gait_check`.
func _trigger() -> float:
	var base := maxf(_profile().step_trigger, 0.01)
	var tangential := absf(_yaw_rate) * _foot_radius
	if tangential <= _speed:
		return base
	var share := clampf((tangential - _speed) / maxf(tangential, 0.01), 0.0, 1.0)
	return lerpf(base, maxf(_profile().turn_step_trigger, 0.01), share)


## Refresca, **una pata por tick**, si todavía hay suelo bajo el apoyo.
##
## El rayo es corto —±3 m en torno al apoyo— porque sólo busca desmentir el
## apoyo, no colocarlo, y va por turnos porque es la condición más rara de las
## tres: comprobar las cuatro en cada tick costaba más que el resto del rig
## junto y 40 ms de latencia no cambian ninguna marcha.
func _refresh_support() -> void:
	if legs.is_empty():
		return
	_support_cursor = (_support_cursor + 1) % legs.size()
	var leg := legs[_support_cursor]
	if leg.broken or not leg.planted or leg.is_airborne() or _pose_override.has(leg.index):
		return
	var space := _body.get_world_3d().direct_space_state
	_query.from = leg.plant_position + Vector3.UP * SUPPORT_SPAN
	_query.to = leg.plant_position - Vector3.UP * SUPPORT_SPAN
	_query.collision_mask = _profile().foot_ray_mask
	_query.exclude = _exclude
	leg.supported = not space.intersect_ray(_query).is_empty()


## Reposo de la pata **ahora mismo**, en el mundo. Es contra este punto que se
## mide el retraso que dispara el paso.
func _rest_now(leg: Leg, body_xform: Transform3D) -> Vector3:
	return body_xform * leg.rest_offset


## Dónde tiene que aterrizar el pie para que la zancada quede **centrada** en su
## reposo (`docs/06` §8.4, corregido en WP-24d).
##
## El adelanto tiene dos sumandos y los dos son necesarios:
##
## 1. `v · step_time` — lo que el cuerpo avanza [b]durante el vuelo[/b]. Sin
##    esto el pie apunta a donde el reposo está, no a donde estará, y aterriza ya
##    retrasado.
## 2. `max(step_trigger, v · step_time / 2)` — media zancada más, porque durante
##    el apoyo siguiente el pie se queda quieto mientras el reposo se le escapa.
##    Cuánto se le escapa depende de quién mande: si el apoyo lo corta
##    `step_trigger`, son `step_trigger` metros; si lo corta el turno del trote
##    —el caso del giro, donde el reposo barre 6.8 m/s y el umbral de 1.6 m se
##    cumple enseguida—, son `v · step_time`, y la mitad de eso centra la
##    zancada. Con este sumando el pie posa por delante tanto como despega por
##    detrás.
##
## WP-17 adelantaba `min(v · step_time, step_trigger) · 0.5` —1.75 m a velocidad
## de crucero, contra los 8.3 m que pide la geometría—, así que la pata pasaba
## todo el apoyo arrastrada: el tramo cadera→tobillo vivía al 94 % de la cadena,
## la rodilla no se doblaba y `gait_check` medía 0.61 m de pie flotando sobre su
## propio apoyo porque el IK ya no llegaba.
func _step_target(leg: Leg, body_xform: Transform3D) -> Vector3:
	var step_time := _gait.step_time_for(_effective_speed())
	var pivot := body_xform.origin
	var turn := clampf(_turn_lead(step_time), -MAX_TURN_LEAD, MAX_TURN_LEAD)
	var rest := pivot + Basis(Vector3.UP, turn) * (body_xform * leg.rest_offset - pivot)
	if _speed <= 0.0001:
		return rest
	var ramp := minf(1.0, _speed / LEAD_RAMP_SPEED)
	var stance := _speed * step_time
	var lead := stance + maxf(_trigger(), stance * 0.5) * ramp
	return rest + _heading * minf(lead, _stride_cap())


## Adelanto angular del objetivo, con los mismos dos sumandos que el lineal: lo
## que el cuerpo gira durante el vuelo más el arco que corresponde a
## `step_trigger` al radio de la huella.
##
## A 15 m del centro, girar a 25°/s barre más metros por segundo que caminar a
## 6 m/s: sin este adelanto la pata queda detrás del giro y agota el
## estiramiento esperando su turno.
func _turn_lead(step_time: float) -> float:
	if absf(_yaw_rate) < 0.0001:
		return 0.0
	var arc := _trigger() / maxf(_foot_radius, 1.0)
	var stance := absf(_yaw_rate) * step_time
	var ramp := minf(1.0, absf(_yaw_rate) / TURN_LEAD_RATE)
	return _yaw_rate * step_time + signf(_yaw_rate) * maxf(arc, stance * 0.5) * ramp


## Tope duro del adelanto lineal, en metros.
func _stride_cap() -> float:
	if legs.is_empty():
		return 8.0
	return (legs[0].femur_length + legs[0].tibia_length) * MAX_STRIDE_REACH


## Proyecta el objetivo del paso contra el suelo y elige el mejor apoyo
## alcanzable (`docs/06` §8.4, ampliado en WP-24d con el criterio de alcance).
##
## Se prueban, en orden, el objetivo con adelanto entero, con medio adelanto, el
## reposo pelado y tres poses cada vez más plegadas bajo el cuerpo. Gana el
## primero que la cadena alcance; si ninguno lo hace —el jefe está al borde de
## una rampa de 41 m o al final de una escalera de 12— gana el menos malo, que
## es el que deja la pata menos estirada. Sin esto el rig plantaba el pie en el
## primer punto sólido que devolvía el rayo aunque estuviera 30 m más abajo, y
## el IK dejaba el pie colgando en el aire.
##
## Lo que se recorta es el adelanto, no la pata: la zancada se acorta sola en
## rampa y en escalón, que es lo que hace cualquier cuadrúpedo.
##
## Con [method set_climb_intent] encendida se recorre la lista **entera** y gana
## cualquier techo de ciudad que aparezca, aunque haya un apoyo de calle
## perfectamente bueno antes: es la diferencia entre rodear la torre y subirse.
##
## En marcha normal el primer candidato gana y se tira **un solo rayo por paso**,
## que es el presupuesto de `docs/06` §8.4; los otros cinco sólo se pagan en el
## terreno —o la acción— que los necesita.
func _project(leg: Leg, body_xform: Transform3D) -> Dictionary:
	var step_time := _gait.step_time_for(_effective_speed())
	var rest := _rest_now(leg, body_xform)
	var target := _step_target(leg, body_xform)
	var limit := (leg.femur_length + leg.tibia_length) * PLANT_REACH
	var candidates: Array[Vector3] = [
		target,
		rest.lerp(target, 0.55),
		rest,
		body_xform * _folded_rest(leg, 0.45),
		body_xform * _folded_rest(leg, 0.0),
		body_xform * (leg.rest_offset * 0.5),
	]
	var chosen: Dictionary = {}
	var climbable: Dictionary = {}
	var best: Dictionary = {}
	var best_span := INF
	for point: Vector3 in candidates:
		var ground := _ray(point)
		if not bool(ground["hit"]):
			continue
		var span := _landing_span(leg, body_xform, ground, step_time)
		# Trepar es la excepción (`docs/07` §5.3): subir el pie al techo de un
		# edificio se acepta **aunque hoy no llegue**, porque en cuanto el paso
		# arranca el cuerpo ya sube con él —[method _contact_point] interpola el
		# suelo bajo el pie en vuelo— y para cuando aterriza la cadera está a
		# media altura del techo. Es el único caso en que el coloso se
		# compromete con un apoyo que todavía no alcanza, y es justo la silueta
		# que el juego quiere: el jefe subido a una torre.
		var climb := _is_climb_target(leg, ground)
		if climb and climbable.is_empty():
			climbable = ground
		if chosen.is_empty() and (span <= limit or climb):
			chosen = ground
			if not _climb_intent:
				# Marcha normal: **un solo rayo por paso**, que es el
				# presupuesto de `docs/06` §8.4.
				return chosen
		if span < best_span:
			best_span = span
			best = ground
	if not climbable.is_empty():
		return climbable
	if not chosen.is_empty():
		return chosen
	if not best.is_empty():
		return best
	return {"hit": false, "point": target, "normal": Vector3.UP, "collider": null,
			"city": false}


## `true` si el apoyo que devolvió el rayo es un techo de ciudad **por encima**
## del apoyo actual de la pata: el caso de trepar.
func _is_climb_target(leg: Leg, ground: Dictionary) -> bool:
	if not bool(ground["city"]):
		return false
	return (ground["point"] as Vector3).y > leg.plant_position.y + 1.0


## Repliegue del reposo hacia el cuerpo **conservando la apertura lateral**: el
## pie se acerca por delante y por detrás, nunca por dentro.
##
## Escalar el reposo entero —lo que hacía el repliegue del abismo de WP-17—
## mete el pie por debajo de la cadera, y con el pie del lado de dentro el plano
## de flexión se invierte: la rodilla se va hacia abajo y hacia adentro en vez de
## hacia arriba y hacia afuera. Medido en WP-24d: 8.1 m de rodilla contra los
## 9.4 m del resto de las patas en el mismo tick. Por eso este repliegue va
## **antes** que el escalado entero en la lista de candidatos, y el escalado
## queda sólo para el borde del que no se vuelve.
func _folded_rest(leg: Leg, amount: float) -> Vector3:
	return Vector3(leg.rest_offset.x, leg.rest_offset.y, leg.rest_offset.z * amount)


## Distancia de la cadera al tobillo **en el instante del aterrizaje**.
##
## La cadera se mide donde estará, no donde está: el cuerpo avanza
## `v · step_time` y gira `ω · step_time` durante el vuelo, y el objetivo lleva
## justo ese adelanto. Comparar contra la cadera de ahora daba 14.4 m en una
## zancada perfectamente normal —por encima de la cadena de 13.59 m—, así que el
## rig recortaba **todas** las zancadas y las patas se quedaban atrás.
func _landing_span(leg: Leg, body_xform: Transform3D, ground: Dictionary,
		step_time: float) -> float:
	var ankle := (ground["point"] as Vector3) + Vector3.UP * leg.ankle_lift
	var pivot := body_xform.origin
	var turn := clampf(_yaw_rate * step_time, -MAX_TURN_LEAD, MAX_TURN_LEAD)
	var hip := pivot + Basis(Vector3.UP, turn) * (leg.hip_world() - pivot)
	hip += _heading * _speed * step_time
	return hip.distance_to(ankle)


## Rayo de apoyo vertical de ±`foot_ray_span` sobre [param point], con máscara
## `world | city` (`PhysicsLayers.QUERY_FOOT`).
func _ray(point: Vector3) -> Dictionary:
	var space := _body.get_world_3d().direct_space_state
	var span := _profile().foot_ray_span
	_query.from = point + Vector3.UP * span
	_query.to = point - Vector3.UP * span
	_query.collision_mask = _profile().foot_ray_mask
	_query.exclude = _exclude
	var hit := space.intersect_ray(_query)
	if hit.is_empty():
		return {"hit": false, "point": point, "normal": Vector3.UP, "collider": null,
				"city": false}
	var collider := hit["collider"] as Object
	var layer := 0
	if collider != null and collider is CollisionObject3D:
		layer = (collider as CollisionObject3D).collision_layer
	return {
		"hit": true,
		"point": hit["position"] as Vector3,
		"normal": hit["normal"] as Vector3,
		"collider": collider,
		"city": (layer & PhysicsLayers.CITY) != 0,
	}


## Arranca un paso: tira el rayo de colocación y arma el arco. Devuelve `false`
## si no hay dónde pisar, en cuyo caso la pata conserva su apoyo anterior.
func _begin_step(leg: Leg, body_xform: Transform3D) -> bool:
	var ground := _project(leg, body_xform)
	if not bool(ground["hit"]):
		return false
	leg.step_from = leg.sole_position()
	leg.target = ground["point"] as Vector3
	leg.target_normal = ground["normal"] as Vector3
	leg.plant_collider = ground["collider"]
	leg.plant_is_city = bool(ground["city"])
	leg.step_time = _gait.step_time_for(_effective_speed())
	leg.step_height = _gait.step_height_for(leg.target.y - leg.step_from.y)
	leg.step_t = 0.0
	leg.stance_time = 0.0
	leg.planted = false
	return true


## Avanza el arco del paso; al llegar a 1 apoya el pie.
##
## Las dos componentes del arco llegan al contacto con **velocidad cero**
## (WP-24d), que es lo que separa un apoyo de un golpe:
##
## - **Horizontal**: `smootherstep`, con velocidad y aceleración nulas en los dos
##   extremos. Un pie de 9 t ni despega de golpe ni frena contra el suelo.
## - **Vertical**: `sin(π · t^0.80)^1.35`. El exponente de dentro adelanta el
##   vértice a t = 0.42 —el pie levanta pronto y se toma el resto del tranco para
##   bajar—; el de fuera aplana la llegada, de modo que la velocidad vertical
##   tiende a cero en el contacto en vez de los 17 m/s que daba el `sin(π t)` de
##   WP-17. Y como el pie ya está sobre el objetivo al plantar, [method _plant]
##   no tiene nada que corregir: el apoyo es firme desde el primer fotograma.
func _advance_step(leg: Leg, delta: float) -> void:
	leg.step_t += delta / maxf(leg.step_time, 0.01)
	if leg.step_t >= 1.0:
		_plant(leg)
		return
	var t := leg.step_t
	var travel := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var lift := pow(sin(PI * pow(t, STEP_LIFT_SKEW)), STEP_LIFT_SHARPNESS)
	leg.foot_position = leg.step_from.lerp(leg.target, travel)
	leg.foot_position += Vector3.UP * leg.step_height * lift


## Apoya el pie: fija el apoyo, avisa y cobra el aplastamiento si pisó ciudad.
func _plant(leg: Leg) -> void:
	leg.step_t = Leg.PLANTED
	leg.stance_time = 0.0
	leg.planted = true
	# El apoyo nuevo salió de un rayo: hay suelo debajo por construcción, y sin
	# esto un `supported` viejo en falso pediría un paso nada más apoyar.
	leg.supported = true
	leg.plant_position = leg.target
	leg.plant_normal = leg.target_normal
	leg.foot_position = leg.target
	var impact := absf(leg.target.y - leg.step_from.y) / maxf(leg.step_time, 0.01)
	foot_planted.emit(leg.index, leg.plant_position, impact)
	if leg.plant_is_city:
		_crush(leg)


## Descarga `crush_damage` sobre el edificio pisado, **una sola vez por paso**,
## por *duck typing* sobre el colisionador que devolvió el rayo (`docs/06` §8.4).
func _crush(leg: Leg) -> void:
	var damage := _profile().crush_damage
	if damage <= 0.0:
		return
	var node := leg.plant_collider as Node
	var depth := 0
	while node != null and depth < 3:
		if node.has_method(&"take_damage"):
			node.call(&"take_damage", damage, leg.plant_position)
			return
		node = node.get_parent()
		depth += 1


# --------------------------------------------------------------------------
# Pose del cuerpo (`docs/06` §8.5)
# --------------------------------------------------------------------------

## Altura e inclinación del cuerpo. La XZ no se toca: es de `move_body`.
func _apply_body_pose(delta: float) -> void:
	var support := _support_points()
	var rate := _profile().height_smooth_rate
	_ground_height = lerpf(_ground_height, _support_mean(support),
			1.0 - exp(-rate * delta))
	_plane_normal = _fit_plane(support)
	_climb_blend = lerpf(_climb_blend, 1.0 if _on_city() else 0.0,
			1.0 - exp(-CLIMB_BLEND_RATE * delta))

	var up_target := Vector3.UP.slerp(_plane_normal, _profile().tilt_blend).normalized()
	_basis_target = _basis_with_up(up_target)
	var blend := 1.0 - exp(-_profile().tilt_smooth_rate * delta)
	var posed := _body.global_basis.orthonormalized().slerp(
			_climb_pitch(_gait_sway(_basis_target)), blend)
	if _stagger_left > 0.0:
		posed = _wobble(posed)
	_body.global_basis = posed.orthonormalized()

	var wanted := _reach_crouch()
	var sink_rate := REACH_SINK_RATE if wanted > _reach_sink else _profile().body_smoothing
	_reach_sink = lerpf(_reach_sink, wanted, 1.0 - exp(-sink_rate * delta))
	var height := body_height_target() - crouch() * _hip_height() + _bob_offset() - _reach_sink
	if is_finite(height):
		_body.global_position = Vector3(_body.global_position.x, height,
				_body.global_position.z)


## Altura de referencia del apoyo: la media de [param support], que trae el
## apoyo de las patas plantadas y el **objetivo** de las que están en vuelo.
##
## Hasta WP-24d promediaba sólo las plantadas, y como en trote hay dos en el aire
## la media saltaba en cada intercambio de pares: el cuerpo cabeceaba a destiempo
## del ciclo. Con el objetivo de las que vuelan la media es continua y además el
## cuerpo **anticipa** el terreno — sube antes de que el pie pise el escalón, que
## es lo que hace cualquier cuadrúpedo.
func _support_mean(support: Array[Vector3]) -> float:
	if support.is_empty():
		return _ground_height
	var total := 0.0
	for point: Vector3 in support:
		total += point.y
	return total / float(support.size())


## Rebote vertical de la cadera, en metros.
##
## Caminando, la cadera baja en cada intercambio de pares y sube a media
## zancada: `−A · cos(4π · fase)` da los dos mínimos por ciclo que corresponden a
## los dos apoyos. Quieto, la sustituye la respiración de servos.
func _bob_offset() -> float:
	if _leap_phase != LeapPhase.NONE:
		return 0.0
	var amplitude := _profile().body_bob * _hip_height()
	var walking := -amplitude * cos(TAU * 2.0 * _cycle_phase) * _gait_activity
	return walking + _idle_offset() * (1.0 - _gait_activity)


## Cuánto se acelera el vuelo en curso por culpa de la pata apoyada más
## estirada: 1 mientras a todas les sobre cadena, hasta [constant MAX_HURRY]
## cuando una ya no llega.
func _hurry_factor() -> float:
	var worst := 0.0
	for leg: Leg in legs:
		if leg.broken or leg.is_airborne():
			continue
		var chain := leg.femur_length + leg.tibia_length
		var span := leg.hip_world().distance_to(
				leg.plant_position + Vector3.UP * leg.ankle_lift)
		worst = maxf(worst, span / maxf(chain, 0.01))
	if worst <= HURRY_REACH:
		return 1.0
	var stress := clampf((worst - HURRY_REACH) / (1.0 - HURRY_REACH), 0.0, 1.0)
	return lerpf(1.0, MAX_HURRY, stress)


## Cuánto tiene que hundirse la cadera para que el apoyo le quede cómodo a la
## pata más estirada, en metros.
##
## `hip_height` (14 m) y la cadena (13.59 m) no dejan casi holgura vertical: en
## cuanto el terreno obliga a un pie a quedarse unos metros por debajo del resto
## —el borde de un escalón de 12 m, el filo de la rampa, el pie que quedó abajo
## mientras los otros suben a un techo— la pata se queda sin alcance y el pie
## flota. Bajar la cadera lo que haga falta es lo que hace cualquier cuadrúpedo,
## y convierte un pie colgando en una pose agazapada. Sirve para las dos formas
## de quedarse corto: hundiendo el cuerpo se acorta la componente vertical del
## tramo cadera→tobillo **y** se libera alcance para la horizontal.
##
## En llano no hace nada: con las cuatro patas a la misma altura el tramo se
## queda en el 81–87 % de la cadena y el umbral de confort es el 90 %.
func _reach_crouch() -> float:
	var worst := 0.0
	for leg: Leg in legs:
		if leg.broken or leg.is_airborne():
			continue
		var span := leg.hip_world().distance_to(
				leg.plant_position + Vector3.UP * leg.ankle_lift)
		var comfort := (leg.femur_length + leg.tibia_length) * COMFORT_REACH
		worst = maxf(worst, span - comfort)
	return clampf(worst, 0.0, MAX_REACH_CROUCH)


## Respiración de servos del reposo: ±`idle_breath` metros a `idle_breath_hz`.
func _idle_offset() -> float:
	var amplitude := _profile().idle_breath
	if amplitude <= 0.0:
		return 0.0
	return amplitude * sin(TAU * _profile().idle_breath_hz * _idle_time)


## Balanceo del cuerpo en fase con el ciclo: alabeo hacia la diagonal que
## sostiene y un cabeceo desfasado un cuarto de ciclo. Los dos juntos se quedan
## por debajo de los 6° que WP-24d exige en llano.
func _gait_sway(source: Basis) -> Basis:
	if _gait_activity <= 0.001 or _leap_phase != LeapPhase.NONE:
		return source
	var amount := _gait_activity * (1.0 - crouch())
	var roll := deg_to_rad(_profile().gait_roll) * sin(TAU * _cycle_phase) * amount
	var pitch := deg_to_rad(_profile().gait_pitch) * cos(TAU * _cycle_phase) * amount
	var rolled := source.rotated(source.z.normalized(), roll)
	return rolled.rotated(source.x.normalized(), pitch)


## Levanta el morro mientras trepa hasta el **piso** de `climb_pitch`
## (`docs/07` §5.3: «el cuerpo cabecea 25° hacia arriba»).
##
## Se mide lo que el plano de apoyo ya inclina y se agrega sólo lo que falta: así
## el gesto se lee igual subiendo a un bloque de 8 m que a una torre de 30, y no
## se acumula con la inclinación de la rampa.
func _climb_pitch(source: Basis) -> Basis:
	if _climb_blend <= 0.001:
		return source
	var current := asin(clampf(-source.z.y, -1.0, 1.0))
	var missing := maxf(0.0, deg_to_rad(_profile().climb_pitch) - current)
	if missing <= 0.0:
		return source
	return source.rotated(source.x.normalized(), missing * _climb_blend)


## `true` si alguna pata sana se apoya sobre un collider de capa `city`.
func _on_city() -> bool:
	for leg: Leg in legs:
		if not leg.broken and leg.planted and leg.plant_is_city:
			return true
	return false


## Puntos de apoyo para el plano y para la altura: uno por pata sana, siempre
## los cuatro. Con dos puntos el plano degenera, y en trote siempre hay dos
## patas en el aire: sin esto la inclinación parpadearía en cada tranco.
func _support_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for leg: Leg in legs:
		if leg.broken:
			continue
		points.append(_contact_point(leg))
	return points


## Punto de contacto **virtual** de una pata: su apoyo si está plantada y, si
## está en vuelo, el punto del suelo por el que va pasando.
##
## WP-17 usaba el **objetivo** del paso para las patas en vuelo, y eso sesga la
## media y el plano: en una rampa de 20° el objetivo está siempre unos 2.5 m
## cuesta arriba del apoyo que la pata deja, así que con dos patas en vuelo el
## rig creía el suelo 1.3 m más alto de lo que estaba, subía el cuerpo y dejaba
## a las dos patas apoyadas sin cadena — 2.5 m de pie flotando, medidos en
## WP-24d. Interpolar el suelo que el pie va sobrevolando es continuo en los dos
## extremos del paso y no sesga nada.
func _contact_point(leg: Leg) -> Vector3:
	if not leg.is_airborne():
		return leg.plant_position
	var t := clampf(leg.step_t, 0.0, 1.0)
	return leg.step_from.lerp(leg.target, t * t * (3.0 - 2.0 * t))


## Plano de mínimos cuadrados sobre [param points] (`docs/06` §8.5).
##
## Se ajusta `y = a·x + b·z + c`. Centrar en el baricentro elimina la fila y la
## columna de `c` de la matriz normal 3×3 y deja un sistema 2×2 mejor
## condicionado; con el determinante por debajo de 1e-6 (patas alineadas o
## menos de tres apoyos) se cae a [constant Vector3.UP].
func _fit_plane(points: Array[Vector3]) -> Vector3:
	if points.size() < 3:
		return Vector3.UP
	var centroid := Vector3.ZERO
	for point: Vector3 in points:
		centroid += point
	centroid /= float(points.size())
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for point: Vector3 in points:
		var dx := point.x - centroid.x
		var dy := point.y - centroid.y
		var dz := point.z - centroid.z
		sxx += dx * dx
		szz += dz * dz
		sxz += dx * dz
		sxy += dx * dy
		szy += dz * dy
	var determinant := sxx * szz - sxz * sxz
	if absf(determinant) < 0.000001:
		return Vector3.UP
	var slope_x := (sxy * szz - szy * sxz) / determinant
	var slope_z := (szy * sxx - sxy * sxz) / determinant
	var normal := Vector3(-slope_x, 1.0, -slope_z)
	if not _is_finite(normal):
		return Vector3.UP
	return normal.normalized()


## Base ortonormal con [param up] por vertical, conservando el rumbo actual.
func _basis_with_up(up: Vector3) -> Basis:
	var current := _body.global_basis.orthonormalized()
	var forward := -current.z
	var right := forward.cross(up)
	if right.length_squared() < 0.000001:
		right = current.x
	right = right.normalized()
	var aligned := up.cross(right)
	return Basis(right, up, -aligned).orthonormalized()


## Bamboleo del tambaleo: una oscilación de `stagger_wobble` grados sobre los
## ejes laterales, sin tocar el rumbo.
func _wobble(source: Basis) -> Basis:
	var amplitude := deg_to_rad(_profile().stagger_wobble)
	var pitch := sin(_stagger_phase * TAU) * amplitude
	var roll := sin(_stagger_phase * TAU * 0.7) * amplitude * 0.6
	return source.rotated(source.x.normalized(), pitch).rotated(source.z.normalized(), roll)


# --------------------------------------------------------------------------
# Patas: IK y colocación
# --------------------------------------------------------------------------

## Escribe la pose de las cuatro patas con la solución de [TwoBoneIK].
func _apply_legs() -> void:
	var body_xform := _body.global_transform
	var stretch := _profile().stretch_max
	for leg: Leg in legs:
		if leg.broken:
			continue
		var pole := body_xform.basis * leg.pole
		var normal := leg.plant_normal
		var ankle := Vector3.ZERO
		if _pose_override.has(leg.index):
			# Pose forzada por una acción (`docs/07` §5.4 y §5.5): la pata va al
			# punto que pidió la coreografía y no participa del ciclo de paso.
			ankle = _pose_override[leg.index] + Vector3.UP * leg.ankle_lift
			normal = body_xform.basis * Vector3.UP
		elif _leap_phase == LeapPhase.TUCK or (_leap_phase == LeapPhase.FLIGHT
				and not _leap_predicted):
			ankle = leg.tuck_target(body_xform, 1.0)
			normal = body_xform.basis * Vector3.UP
		elif leg.is_airborne():
			ankle = leg.foot_position + Vector3.UP * leg.ankle_lift
			normal = leg.target_normal
		else:
			ankle = leg.plant_position + Vector3.UP * leg.ankle_lift
		leg.apply(body_xform, ankle, pole, stretch, normal, KNEE_MIN_LIFT)


## Coloca los cuatro pies en el suelo de una sola vez, sin paso: es la pose de
## arranque, la de después de aterrizar y la que hay que pedir tras teletransportar
## al enemigo (aparición de ronda, checks).
func snap_to_ground() -> void:
	var body_xform := _body.global_transform
	var total := 0.0
	var count := 0
	for leg: Leg in legs:
		if leg.broken:
			continue
		var ground := _ray(leg.rest_world(body_xform))
		leg.plant_position = ground["point"] as Vector3
		leg.plant_normal = ground["normal"] as Vector3
		leg.plant_collider = ground["collider"]
		leg.plant_is_city = bool(ground["city"])
		leg.target = leg.plant_position
		leg.target_normal = leg.plant_normal
		leg.foot_position = leg.plant_position
		leg.planted = true
		leg.step_t = Leg.PLANTED
		total += leg.plant_position.y
		count += 1
	_ground_height = total / float(count) if count > 0 else _body.global_position.y
	_plane_normal = _fit_plane(_support_points())
	_basis_target = _basis_with_up(Vector3.UP.slerp(_plane_normal,
			_profile().tilt_blend).normalized())
	_body.global_basis = _basis_target.orthonormalized()
	_body.global_position = Vector3(_body.global_position.x, body_height_target(),
			_body.global_position.z)
	_apply_legs()
	# Tras un teletransporte, la referencia de posición tiene que viajar con el
	# cuerpo: si no, el tick siguiente lee como velocidad todo el salto y las
	# cuatro patas salen a dar pasos de cien metros.
	_last_position = _body.global_position
	_last_yaw = _heading_yaw()


# --------------------------------------------------------------------------
# Salto (`docs/06` §8.6)
# --------------------------------------------------------------------------

## Avanza las tres fases del salto: recogida, vuelo balístico y aterrizaje.
func _tick_leap(delta: float) -> void:
	_leap_time += delta
	match _leap_phase:
		LeapPhase.TUCK:
			_crouch = minf(_leap_time / maxf(_profile().leap_tuck_time, 0.01), 1.0) * 0.15
			_apply_body_pose(delta)
			if _leap_time >= _profile().leap_tuck_time:
				_leap_time = 0.0
				_leap_phase = LeapPhase.FLIGHT
				_launch()
		LeapPhase.FLIGHT:
			_crouch = 0.0
			_leap_velocity += Vector3.DOWN * _profile().leap_gravity * delta
			var step := _leap_velocity * delta
			var cap := _profile().leap_max_step
			if step.length() > cap:
				step = step.normalized() * cap
			_body.global_position += step
			if not _leap_predicted and _leap_time >= _leap_flight - _profile().land_predict:
				_predict_landing()
			elif _leap_predicted:
				for leg: Leg in legs:
					if not leg.broken and leg.is_airborne():
						_advance_step(leg, delta)
			if _leap_time >= _leap_flight:
				_land()
		LeapPhase.LAND:
			# El cuerpo se hunde y vuelve en `land_crouch_time`: es el único
			# sitio donde el salto pesa (`docs/06` §8.6 punto 4 y `docs/13` §6).
			# La campana `sin(π·u)` arranca y termina en cero, así que ni el
			# aterrizaje ni la recuperación pegan un salto de altura.
			var hold := maxf(_profile().land_crouch_time, 0.01)
			var progress := clampf(_leap_time / hold, 0.0, 1.0)
			_crouch = _profile().land_crouch * sin(PI * progress)
			_apply_body_pose(delta)
			if _leap_time >= maxf(_profile().land_stagger, hold):
				_crouch = 0.0
				_leap_phase = LeapPhase.NONE
				_gait.set_leaping(false)


## Posición que tendrá el **origen** del cuerpo cuando los pies pisen el punto
## de caída, con la cadera otra vez a `hip_height`.
func _landing_body_position() -> Vector3:
	return Vector3(_leap_landing.x, _leap_landing.y + _hip_height() - _hip_local_height,
			_leap_landing.z)


## Resuelve la velocidad inicial que lleva el cuerpo al punto de caída en
## `flight_time` con la gravedad del perfil.
func _launch() -> void:
	var from := _body.global_position
	var to := _landing_body_position()
	var gravity := _profile().leap_gravity
	var delta_position := to - from
	_leap_velocity = Vector3(delta_position.x / _leap_flight,
			delta_position.y / _leap_flight + 0.5 * gravity * _leap_flight,
			delta_position.z / _leap_flight)
	_state = STATE_LEAP


## Predice los cuatro puntos de impacto y estira los pies hacia ellos
## (`docs/06` §8.6 punto 3).
func _predict_landing() -> void:
	_leap_predicted = true
	var landing_xform := Transform3D(_body.global_basis, _landing_body_position())
	for leg: Leg in legs:
		if leg.broken:
			continue
		var ground := _ray(landing_xform * leg.rest_offset)
		leg.step_from = leg.sole_position()
		leg.target = ground["point"] as Vector3
		leg.target_normal = ground["normal"] as Vector3
		leg.plant_collider = ground["collider"]
		leg.plant_is_city = bool(ground["city"])
		leg.step_time = maxf(_profile().land_predict, 0.05)
		leg.step_height = _gait.step_height_for(leg.target.y - leg.step_from.y) * 0.4
		leg.step_t = 0.0
		leg.planted = false


## Aterriza: los cuatro pies al suelo, tambaleo corto y sacudida de cámara.
func _land() -> void:
	if not _leap_predicted:
		_predict_landing()
	for leg: Leg in legs:
		if leg.broken:
			continue
		leg.step_t = 1.0
		_plant(leg)
	_leap_phase = LeapPhase.LAND
	_leap_time = 0.0
	_needs_snap = false
	_ground_height = _support_mean(_support_points())
	_body.global_position = Vector3(_body.global_position.x, body_height_target(),
			_body.global_position.z)
	# El bamboleo del aterrizaje es **del rig**, no del enemigo: se queda en el
	# acumulador local en vez de pasar por `EnemyBase.request_stagger`. Si se
	# propagara, el propio salto se cancelaría a sí mismo —`EnemyFSM` interrumpe
	# toda acción con el jefe tambaleando (`docs/06` §11.1)— y `pounce` perdería
	# sus 2.0 s de recuperación, que es la ventana de daño que `docs/07` §5.9 le
	# promete al jugador. Los tambaleos que sí tienen que cortar la acción vienen
	# de romper una parte, y ésos llaman a `request_stagger` directamente.
	_stagger_left = maxf(_stagger_left, _profile().land_stagger)
	Events.camera_trauma.emit(LAND_TRAUMA, _leap_landing)
	leap_landed.emit(_leap_landing)


# --------------------------------------------------------------------------
# Estado, tambaleo y re-balance
# --------------------------------------------------------------------------

## Cuerpo caído: el coloso se desploma hasta apoyar la panza en el suelo y se
## queda ahí (`docs/06` §8.7, con la altura corregida en WP-19b).
##
## El suelo se vuelve a medir con un rayo bajo el cuerpo en vez de fiarse de
## [member _ground_height]: sin patas apoyadas, [method _support_mean] devuelve
## el último valor conocido y se queda congelado, así que un jefe que cayera
## sobre un techo o en una rampa se hundiría en él.
func _tick_downed(delta: float) -> void:
	var ground := _ray(_body.global_position)
	if bool(ground["hit"]):
		_ground_height = (ground["point"] as Vector3).y
	var blend := 1.0 - exp(-_profile().body_smoothing * delta)
	_body.global_position = Vector3(_body.global_position.x,
			lerpf(_body.global_position.y, body_height_target(), blend),
			_body.global_position.z)
	_body.global_basis = _body.global_basis.orthonormalized().slerp(
			_basis_with_up(Vector3.UP), blend).orthonormalized()


## Decide el estado de la capa de locomoción de este tick.
func _update_state() -> void:
	if _is_downed():
		_state = STATE_DOWNED
		return
	if _leap_phase == LeapPhase.TUCK or _leap_phase == LeapPhase.FLIGHT:
		_state = STATE_LEAP
		return
	if _stagger_left > 0.0 or _is_staggered():
		_state = STATE_STAGGER
		return
	_climbing = _on_city()
	if _climbing:
		_state = STATE_CLIMB
		return
	if _speed > IDLE_SPEED:
		_state = STATE_WALK
		return
	if absf(_yaw_rate) > deg_to_rad(TURN_RATE_EPS):
		_state = STATE_TURN
		return
	_state = STATE_IDLE


## Descuenta el tambaleo propio del rig y avanza la fase del bamboleo.
func _tick_stagger(delta: float) -> void:
	if _stagger_left <= 0.0:
		return
	_stagger_left = maxf(0.0, _stagger_left - delta)
	_stagger_phase += delta * _profile().stagger_frequency


## Mide la velocidad de giro: alimenta el adelanto del paso, su duración y el
## estado `TURN`.
##
## El rumbo sale del eje **frontal de la base**, no de `rotation.y`: con el
## cuerpo inclinado en una rampa, la descomposición de Euler reparte el giro
## entre los tres ángulos y `rotation.y` pega saltos que dispararían objetivos
## de paso disparatados.
func _track_yaw(delta: float) -> void:
	var yaw := _heading_yaw()
	_yaw_rate = clampf(wrapf(yaw - _last_yaw, -PI, PI) / delta, -MAX_YAW_RATE, MAX_YAW_RATE)
	_last_yaw = yaw


## Rumbo del cuerpo en radianes, con el mismo convenio que
## `EnemyBase.face_toward()`.
func _heading_yaw() -> float:
	var forward := -_body.global_basis.z
	if absf(forward.x) < 0.000001 and absf(forward.z) < 0.000001:
		return _last_yaw
	return atan2(-forward.x, -forward.z)


## Arranca el re-balance de reposos hacia el centroide del apoyo que queda.
func _start_rebalance() -> void:
	var centroid := Vector3.ZERO
	var count := 0
	for leg: Leg in legs:
		if leg.broken:
			continue
		centroid += leg.base_rest_offset
		count += 1
	if count == 0:
		return
	centroid /= float(count)
	var shift := Vector3(-centroid.x, 0.0, -centroid.z)
	var limit := REBALANCE_LIMIT * (legs[0].femur_length + legs[0].tibia_length)
	if shift.length() > limit:
		shift = shift.normalized() * limit
	_rebalance_from = _rebalance_shift_now()
	_rebalance_to = shift
	_rebalance_t = 0.0


## Interpola el re-balance durante `rebalance_time` segundos.
func _tick_rebalance(delta: float) -> void:
	if _rebalance_t >= 1.0:
		return
	_rebalance_t = minf(1.0, _rebalance_t + delta / maxf(_profile().rebalance_time, 0.01))
	var shift := _rebalance_shift_now()
	for leg: Leg in legs:
		leg.rest_offset = leg.base_rest_offset + shift


## Desplazamiento de reposo vigente en este instante.
func _rebalance_shift_now() -> Vector3:
	return _rebalance_from.lerp(_rebalance_to, _rebalance_t)


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Vector de polo de una pata, en espacio del cuerpo: lateral hacia afuera con
## sesgo hacia atrás, para que la rodilla se arquee como la de una araña.
func _pole_for(entry: Dictionary) -> Vector3:
	var root := entry.get("root", null) as EnemyPart
	var lateral := 1.0
	if root != null and root.mesh != null and _body != null:
		var local := _body.global_transform.affine_inverse() * root.mesh.global_position
		lateral = signf(local.x) if absf(local.x) > 0.001 else 1.0
	return (Vector3(lateral, KNEE_POLE_UP, 0.0)
			+ Vector3.BACK * KNEE_POLE_BACK).normalized()


## RID de las partes propias, para que el rayo de apoyo no se enganche con el
## propio coloso. La máscara `world | city` ya deja fuera las capas 3 y 4; el
## `exclude` es el cinturón sobre los tirantes (`docs/06` §8.4).
func _collect_exclusions() -> void:
	_exclude.clear()
	if _enemy == null or not _enemy.has_method(&"get_parts"):
		return
	var parts := _enemy.call(&"get_parts") as Array
	for part: EnemyPart in parts:
		if part.body != null and is_instance_valid(part.body):
			_exclude.append(part.body.get_rid())


## Perfil del rig; si falta, uno por defecto para no romper nada.
func _profile() -> LegRigProfile:
	if profile == null:
		profile = LegRigProfile.new()
	return profile


## Altura de cadera del [EnemyProfile] del enemigo.
func _hip_height() -> float:
	if _enemy != null and &"profile" in _enemy:
		var enemy_profile := _enemy.get(&"profile") as EnemyProfile
		if enemy_profile != null:
			return enemy_profile.hip_height
	return DEFAULT_HIP_HEIGHT


## Penalización de velocidad por pata del [EnemyProfile].
func _leg_penalty() -> float:
	if _enemy != null and &"profile" in _enemy:
		var enemy_profile := _enemy.get(&"profile") as EnemyProfile
		if enemy_profile != null:
			return enemy_profile.leg_speed_penalty
	return DEFAULT_LEG_PENALTY


## Ensanchamiento de la huella de marcha.
func _spread() -> float:
	return _profile().stance_spread


## Velocidad a la que se mueve **el pie**, que es la que manda en la duración
## del paso: la del cuerpo o la tangencial del giro, la que sea mayor. Girando
## en el sitio la velocidad lineal es 0 y el paso saldría lentísimo justo cuando
## más rápido tiene que moverse la pata.
func _effective_speed() -> float:
	return maxf(_speed, absf(_yaw_rate) * _foot_radius * TURN_STEP_URGENCY)


## `true` cuando se perdieron todas las patas que tolera el enemigo.
func _is_downed() -> bool:
	if _enemy != null and _enemy.has_method(&"is_downed"):
		return bool(_enemy.call(&"is_downed"))
	return broken_legs.size() >= legs.size()


## `true` si una acción con `lock_locomotion` está en curso (`docs/06` §11.1).
func _is_locomotion_locked() -> bool:
	if _enemy != null and _enemy.has_method(&"is_locomotion_locked"):
		return bool(_enemy.call(&"is_locomotion_locked"))
	return false


## `true` si el enemigo está tambaleando por daño.
func _is_staggered() -> bool:
	if _enemy != null and _enemy.has_method(&"is_staggered"):
		return bool(_enemy.call(&"is_staggered"))
	return false


## `true` si las tres componentes son finitas.
func _is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


## Dibuja objetivos, apoyos, plano del cuerpo y arcos (`docs/04` §3.7). Sin
## `--debug` no cuesta nada: [DebugGeometry] descarta la llamada.
func _draw_debug() -> void:
	if not debug_draw or not DebugGeometry.is_enabled():
		return
	var body_xform := _body.global_transform
	for leg: Leg in legs:
		if leg.broken:
			continue
		var color := Color(0.2, 1.0, 0.4) if leg.planted else Color(1.0, 0.65, 0.1)
		DebugGeometry.draw_sphere(leg.plant_position, 1.0, color)
		DebugGeometry.draw_line(leg.rest_world(body_xform), leg.plant_position,
				Color(0.4, 0.7, 1.0, 0.6))
		DebugGeometry.draw_line(leg.hip_world(), leg.sole_position(), color)
		if leg.is_airborne():
			DebugGeometry.draw_line(leg.step_from, leg.target, Color(1.0, 0.9, 0.2))
			DebugGeometry.draw_sphere(leg.foot_position, 0.6, Color(1.0, 0.9, 0.2))
	var center := Vector3(_body.global_position.x, _ground_height, _body.global_position.z)
	DebugGeometry.draw_arrow(center, _plane_normal * 8.0, Color(1.0, 0.2, 0.8))
	DebugGeometry.draw_text(_body.global_position + Vector3.UP * 6.0,
			"%s / %s" % [_state, gait_name()], Color(1.0, 1.0, 1.0))
