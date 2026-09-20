## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Integridad de la ciudad (`docs/10` §5 y §9.3).
##
## [codeblock]
## ratio = Σ hp_actual / Σ hp_inicial
## [/codeblock]
##
## El cálculo es **incremental**: no se vuelven a sumar los 60 edificios cada
## frame. Cada [Building] publica el daño realmente aplicado con su señal
## `damage_taken` y acá se descuenta de un acumulador, con `Σ hp_inicial`
## calculado una sola vez en [method reset]. `city_check` verifica en cinco
## puntos que el acumulador no deriva frente a la suma recalculada a mano.
##
## La sucesión es **monótona no creciente por construcción**: no hay reparación
## en el MVP y la etapa `RUBBLE` es absorbente con `hp = 0`.
##
## No conoce la máquina de ronda: al cruzar [member defeat_threshold] publica
## [signal defeat_threshold_reached] **una sola vez** y quien decide la derrota
## es `RoundManager` (`docs/11` §4.1), escuchando `Events.city_integrity_changed`.
##
## **Edificio bajo asedio**: a [member siege_hz] hercios se revisa qué edificio
## acumuló más daño en su ventana deslizante; si supera
## [member siege_min_damage] se lo marca y se desmarca al anterior. El grupo
## `buildings_under_siege` tiene, por lo tanto, **como mucho un miembro**, que es
## lo que espera `OffscreenMarkers` (`docs/12` §4.1).
class_name CityIntegrity extends Node

## Grupo por el que lo encuentran el HUD y los checks.
const GROUP: StringName = &"city_integrity"

## Se emite con el mismo valor que `Events.city_integrity_changed`.
signal integrity_changed(ratio: float)

## Se emite una única vez, al cruzar [member defeat_threshold] hacia abajo.
signal defeat_threshold_reached()

## Distrito del que salen los edificios en [method rebuild]. Puede quedar vacío:
## entonces se toma el grupo `buildings` entero.
@export var grid: CityGrid = null

## Integridad por debajo de la cual la ronda se pierde (`docs/11` §4.1).
## `docs/10` §9.3 lo llama `defeat_ratio`; es el mismo número.
@export_range(0.0, 1.0, 0.01) var defeat_threshold: float = 0.35

## Daño mínimo acumulado en la ventana para marcar «bajo asedio» (`docs/10` §10).
@export_range(0.0, 5000.0, 1.0) var siege_min_damage: float = 150.0

## Frecuencia de revisión del asedio, en hercios.
@export_range(0.5, 30.0, 0.5) var siege_hz: float = 4.0

## Cambio mínimo de integridad que se publica al bus. WP-20 lo fija en 0.001;
## `docs/10` §5 proponía 0.002.
@export_range(0.0, 0.5, 0.0001) var emit_epsilon: float = 0.001

## Segundos tras los que un cambio pendiente se publica igual, aunque no llegue
## a [member emit_epsilon]. Garantiza que el último valor siempre sale.
@export_range(0.0, 5.0, 0.01) var emit_max_delay: float = 0.25

var _buildings: Array[Building] = []
var _initial_hp: float = 0.0
var _total_hp: float = 0.0
var _last_emitted: float = 1.0
var _pending_delay: float = 0.0
var _has_pending: bool = false
var _defeat_emitted: bool = false
var _under_siege: Building = null
var _siege_accumulator: float = 0.0


func _ready() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	if _buildings.is_empty():
		rebuild()


## Acumuladores de publicación y de asedio. Nunca un [Timer].
func _physics_process(delta: float) -> void:
	if _has_pending:
		_pending_delay += delta
		if _pending_delay >= emit_max_delay:
			_publish(get_ratio())

	_siege_accumulator += delta
	var period := 1.0 / maxf(siege_hz, 0.001)
	if _siege_accumulator < period:
		return
	_siege_accumulator = 0.0
	_update_siege()


# --------------------------------------------------------------------------
# Alta y reinicio
# --------------------------------------------------------------------------

## Da de alta todos los edificios del distrito y reinicia la cuenta. Es el alias
## documentado de `reset()` + alta del grupo `buildings` (`docs/10` §9.3).
func rebuild() -> void:
	for building: Building in _buildings:
		if is_instance_valid(building) and building.damage_taken.is_connected(_on_damage_taken):
			building.damage_taken.disconnect(_on_damage_taken)
	_buildings.clear()

	var source: Array[Building] = []
	if grid != null:
		source = grid.get_buildings()
	if source.is_empty():
		var tree := get_tree()
		if tree != null:
			for node: Node in tree.get_nodes_in_group(Building.GROUP):
				var building := node as Building
				if building != null:
					source.append(building)
	for building: Building in source:
		register(building)
	reset()


## Da de alta un edificio. Idempotente: registrar dos veces no duplica su HP.
func register(building: Building) -> void:
	if building == null or _buildings.has(building):
		return
	_buildings.append(building)
	if not building.damage_taken.is_connected(_on_damage_taken):
		var _discard := building.damage_taken.connect(_on_damage_taken)
	_initial_hp += building.get_max_hp()
	_total_hp += building.hp


## Devuelve los edificios registrados a su estado intacto y recalcula
## `Σ hp_inicial`. No cambia el registro: para eso está [method rebuild].
func reset() -> void:
	Building.reset_emitters()
	_initial_hp = 0.0
	_total_hp = 0.0
	for building: Building in _buildings:
		if not is_instance_valid(building):
			continue
		building.reset()
		_initial_hp += building.get_max_hp()
		_total_hp += building.hp
	_under_siege = null
	_siege_accumulator = 0.0
	_defeat_emitted = false
	_has_pending = false
	_pending_delay = 0.0
	_last_emitted = get_ratio()
	integrity_changed.emit(_last_emitted)
	Events.city_integrity_changed.emit(_last_emitted)


# --------------------------------------------------------------------------
# Consultas
# --------------------------------------------------------------------------

## Integridad actual, de 0.0 a 1.0. **Canónica**: la usan `docs/11` y `docs/12`.
func get_ratio() -> float:
	if _initial_hp <= 0.0:
		return 1.0
	return clampf(_total_hp / _initial_hp, 0.0, 1.0)


## Alias documentado de [method get_ratio] (`docs/10` §9.3).
func ratio() -> float:
	return get_ratio()


## Suma de HP actual de los edificios registrados, según el acumulador.
func get_total_hp() -> float:
	return _total_hp


## Suma de HP de los edificios intactos.
func get_initial_hp() -> float:
	return _initial_hp


## Edificio marcado como «bajo asedio», o `null` si no hay ninguno.
func get_under_siege() -> Building:
	return _under_siege if is_instance_valid(_under_siege) else null


## Edificios que ya cruzaron el umbral de ruina.
func get_destroyed_count() -> int:
	var count := 0
	for building: Building in _buildings:
		if is_instance_valid(building) and building.is_destroyed():
			count += 1
	return count


## Edificios registrados. La copia evita que un llamador altere el registro.
func get_buildings() -> Array[Building]:
	return _buildings.duplicate()


## Suma de HP recalculada edificio por edificio. Existe para que `city_check`
## pueda contrastarla con [method get_total_hp] y detectar deriva.
func recompute_total_hp() -> float:
	var total := 0.0
	for building: Building in _buildings:
		if is_instance_valid(building):
			total += building.hp
	return total


# --------------------------------------------------------------------------
# Internos
# --------------------------------------------------------------------------

## Descuenta el daño aplicado del acumulador y decide si toca publicar.
func _on_damage_taken(amount: float, _point: Vector3) -> void:
	_total_hp = maxf(_total_hp - amount, 0.0)
	var current := get_ratio()
	if _last_emitted - current >= emit_epsilon:
		_publish(current)
		return
	if not is_equal_approx(current, _last_emitted):
		_has_pending = true


## Publica [param value] en la señal propia y en el bus, y dispara la derrota la
## primera vez que se cruza el umbral.
func _publish(value: float) -> void:
	_has_pending = false
	_pending_delay = 0.0
	# Monotonía dura: el acumulador nunca puede publicar una subida.
	_last_emitted = minf(value, _last_emitted)
	integrity_changed.emit(_last_emitted)
	Events.city_integrity_changed.emit(_last_emitted)
	if not _defeat_emitted and _last_emitted < defeat_threshold:
		_defeat_emitted = true
		defeat_threshold_reached.emit()


## Marca al edificio con más daño reciente y desmarca al anterior.
func _update_siege() -> void:
	var best: Building = null
	var best_damage := siege_min_damage
	for building: Building in _buildings:
		if not is_instance_valid(building) or building.is_destroyed():
			continue
		var damage := building.get_siege_damage()
		if damage >= best_damage:
			best_damage = damage
			best = building

	if best == _under_siege:
		return
	if is_instance_valid(_under_siege):
		_under_siege.mark_under_siege(false)
	_under_siege = best
	if best != null:
		best.mark_under_siege(true)
