## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Coordinador de la marcha (`docs/06` §8.3 y §8.4).
##
## Decide **quién puede levantar el pie y cuándo**, y nada más: no toca nodos ni
## resuelve IK. Es la pieza que garantiza la invariante de la marcha diagonal —
## *nunca los dos pares en el aire a la vez*— y la que degrada el modo a medida
## que el jefe pierde patas.
##
## - **TROT** (4 patas): pares diagonales `{FL, BR}` y `{FR, BL}`.
## - **TRIPOD** (3 patas): una pata en vuelo por vez y al menos
##   [member tripod_min_planted] apoyadas.
## - **DRAG** (2 patas): una pata en vuelo por vez y el paso un 30 % más largo;
##   el cuerpo se arrastra a [member drag_speed_factor].
## - **LEAP**: todas libres mientras dura el vuelo balístico.
## - **IDLE**: 1 pata o ninguna; ya no hay marcha que coordinar.
class_name GaitController extends RefCounted

## Modos de marcha de `docs/06` §8.3.
enum Gait { IDLE, TROT, TRIPOD, DRAG, LEAP }

## Pares diagonales por lado. Es la fuente de verdad cuando la pata declara su
## lado; [member fallback_pairs] cubre a los enemigos de P3 que no usen estos
## nombres.
const SIDE_PAIRS: Array = [[&"FL", &"BR"], [&"FR", &"BL"]]

## Cuánto se alarga el paso mientras el cuerpo se arrastra (`docs/06` §8.3).
const DRAG_STEP_FACTOR: float = 1.30

## Cuánto se acorta el paso en trípode.
##
## Con tres patas se levanta una por vez, así que cada pata espera dos trancos
## ajenos entre turno y turno: con el paso nominal el pie se aleja del reposo
## más de lo que la cadena puede estirar. Pasos más cortos y frecuentes son
## justamente la cojera que se busca.
const TRIPOD_STEP_FACTOR: float = 0.70

## Modo actual.
var gait: int = Gait.IDLE

## Pares que se mueven juntos, por índice de pata.
var pairs: Array[PackedInt32Array] = []

## Pares declarados en el [LegRigProfile]; se usan si los lados no se reconocen.
var fallback_pairs: Array[PackedInt32Array] = []

## Patas apoyadas que el modo trípode garantiza como mínimo.
var tripod_min_planted: int = 2

## Multiplicador de velocidad mientras el cuerpo se arrastra con 2 patas.
var drag_speed_factor: float = 0.55

## Duración nominal de un paso a [member speed_ref], en segundos.
var step_duration: float = 0.55

## Velocidad que normaliza la duración del paso, en m/s.
var speed_ref: float = 6.0

## Recorte del factor `velocidad / speed_ref`.
var speed_clamp: Vector2 = Vector2(0.6, 1.8)

## Segundos que tarda el factor de modo en ir de una marcha a la otra.
var blend_time: float = 0.45

## Altura mínima del arco del paso, en metros.
var step_height_min: float = 3.0

## Suma fija a la altura del arco sobre el desnivel salvado, en metros.
var step_height_bias: float = 2.0

var _legs: Array = []
var _pair_of: Dictionary[int, int] = {}
var _mode_factor: float = 1.0


## Cablea las patas y copia los ajustes del perfil.
func setup(legs: Array, profile: LegRigProfile) -> void:
	_legs = legs
	if profile != null:
		fallback_pairs = profile.gait_pairs
		tripod_min_planted = profile.tripod_min_planted
		drag_speed_factor = profile.drag_speed_factor
		step_duration = profile.step_duration
		speed_ref = maxf(profile.speed_ref, 0.1)
		speed_clamp = profile.speed_clamp
		step_height_min = profile.step_height_min
		step_height_bias = profile.step_height_bias
		blend_time = profile.gait_blend_time
	_build_pairs()
	refresh()
	_mode_factor = _mode_target()


## Interpola el factor de modo hacia el de la marcha actual (WP-24d).
##
## El cambio de trote a trípode acorta el paso un 30 % y el de trípode a
## arrastre lo alarga un 86 %: aplicarlos de golpe se ve como un tirón en el
## tranco siguiente, justo en el instante en que el jugador acaba de reventar una
## rodilla y está mirando. Interpolado en [member blend_time] la cojera aparece
## en dos trancos en vez de en uno.
func blend(delta: float) -> void:
	if delta <= 0.0:
		return
	_mode_factor = lerpf(_mode_factor, _mode_target(),
			1.0 - exp(-delta / maxf(blend_time, 0.01)))


## Factor de paso que le corresponde al modo actual.
func _mode_target() -> float:
	match gait:
		Gait.DRAG:
			return DRAG_STEP_FACTOR
		Gait.TRIPOD:
			return TRIPOD_STEP_FACTOR
		_:
			return 1.0


## Recalcula el modo con las patas que quedan (`docs/06` §8.3, `set_available`).
func refresh() -> void:
	if gait == Gait.LEAP:
		return
	match healthy_count():
		4:
			gait = Gait.TROT
		3:
			gait = Gait.TRIPOD
		2:
			gait = Gait.DRAG
		_:
			gait = Gait.IDLE


## Entra o sale del modo de salto.
func set_leaping(leaping: bool) -> void:
	if leaping:
		gait = Gait.LEAP
		return
	gait = Gait.IDLE
	refresh()


## Patas sanas.
func healthy_count() -> int:
	var total := 0
	for leg: Leg in _legs:
		if not leg.broken:
			total += 1
	return total


## Patas que sostienen el cuerpo ahora mismo.
func planted_count() -> int:
	var total := 0
	for leg: Leg in _legs:
		if leg.supports():
			total += 1
	return total


## Patas en el aire.
func airborne_count() -> int:
	var total := 0
	for leg: Leg in _legs:
		if not leg.broken and leg.is_airborne():
			total += 1
	return total


## `true` si la pata [param leg] puede empezar un paso sin romper la invariante
## del modo actual.
func can_lift(leg: Leg) -> bool:
	if leg.broken or leg.is_airborne():
		return false
	match gait:
		Gait.LEAP:
			return true
		Gait.TROT:
			# El par diagonal se mueve **entero**: sólo despega si la diagonal
			# contraria está completamente apoyada. Dejar que cada pata pidiera
			# turno por su cuenta desfasaba las dos mitades de un par, y con una
			# de ellas siempre en el aire el otro par no volvía a pisar nunca.
			for other: Leg in _legs:
				if other == leg or other.broken or not other.is_airborne():
					continue
				return false
			return true
		Gait.TRIPOD:
			return airborne_count() == 0 and healthy_count() - 1 >= tripod_min_planted
		Gait.DRAG:
			return airborne_count() == 0
		_:
			return false


## Índice del par diagonal al que pertenece la pata [param leg_index], o `-1`.
func pair_of(leg_index: int) -> int:
	return _pair_of.get(leg_index, -1)


## Compañera diagonal de [param leg] que debe despegar con ella. Sólo existe en
## `TROT`: en trípode y en arrastre las patas se levantan de a una.
func partner_of(leg: Leg) -> Leg:
	if gait != Gait.TROT:
		return null
	var mine := pair_of(leg.index)
	for other: Leg in _legs:
		if other == leg or other.broken:
			continue
		if pair_of(other.index) == mine:
			return other
	return null


## Duración del paso a [param speed] (`docs/06` §8.4, con `step_duration` 0.80 s
## desde WP-24d): 0.80 s a 6 m/s, 0.44 s a 11 m/s y 1.33 s casi detenido. El
## arrastre lo alarga un 30 % y el trípode lo acorta un 30 %, interpolados por
## [method blend].
func step_time_for(speed: float) -> float:
	var factor := clampf(speed / speed_ref, speed_clamp.x, speed_clamp.y)
	return step_duration * _mode_factor / maxf(factor, 0.01)


## Altura del arco de un paso que salva [param height_delta] metros de desnivel.
func step_height_for(height_delta: float) -> float:
	return maxf(step_height_min, absf(height_delta) + step_height_bias)


## Multiplicador de velocidad por patas perdidas (`docs/06` §8.7). Con dos patas
## el arrastre manda: 0.55 pesa más que la cojera acumulada.
func speed_multiplier(lost: int, leg_penalty: float) -> float:
	var multiplier := maxf(0.0, 1.0 - leg_penalty * float(lost))
	if gait == Gait.DRAG:
		multiplier = minf(multiplier, drag_speed_factor)
	elif gait == Gait.IDLE and lost > 0:
		multiplier = 0.0
	return multiplier


## Nombre legible del modo, para el debug y los checks.
func gait_name() -> StringName:
	match gait:
		Gait.TROT:
			return &"TROT"
		Gait.TRIPOD:
			return &"TRIPOD"
		Gait.DRAG:
			return &"DRAG"
		Gait.LEAP:
			return &"LEAP"
		_:
			return &"IDLE"


## Arma los pares diagonales. Prefiere los lados declarados por [EnemyBase]; si
## el enemigo no los usa, cae a los `gait_pairs` del perfil.
func _build_pairs() -> void:
	pairs = []
	_pair_of.clear()
	var by_side: Dictionary[StringName, int] = {}
	for leg: Leg in _legs:
		by_side[leg.side] = leg.index

	var complete := true
	for couple: Array in SIDE_PAIRS:
		for raw_side: StringName in couple:
			complete = complete and by_side.has(raw_side)
	if complete:
		for couple: Array in SIDE_PAIRS:
			pairs.append(PackedInt32Array([by_side[couple[0]], by_side[couple[1]]]))
	else:
		pairs = fallback_pairs.duplicate()

	for pair_index: int in pairs.size():
		for leg_index: int in pairs[pair_index]:
			_pair_of[leg_index] = pair_index
	# Una pata sin par declarado es su propio par: nunca bloquea a nadie.
	for leg: Leg in _legs:
		if not _pair_of.has(leg.index):
			_pair_of[leg.index] = pairs.size() + leg.index
