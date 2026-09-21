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
## **Edificio protegido** (WP-25b, `docs/11` §1): la ronda puede señalar un
## edificio con nombre propio —la escuela del barrio— con [method set_protected].
## Su HP pasa a pesar [member protected_weight] veces en el numerador **y** en el
## denominador, de modo que la ciudad intacta sigue valiendo 1.0 pero perderlo
## cuesta el triple que perder al vecino. Al entrar en `RUBBLE` se publica
## [signal protected_fallen], que es local: el bus ya cuenta que cayó un edificio
## y no tiene por qué saber cuál era el importante de esta ronda.
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

## Cayó el edificio protegido de la ronda. Se emite **una sola vez**, en cuanto
## entra en `RUBBLE` (`docs/11` §1).
##
## Es una señal **local** y no del bus: `Events.building_destroyed` ya publica el
## hecho «cayó un edificio» y el bus no tiene por qué saber qué edificio era
## especial en esta ronda (`docs/02` §5.1: el bus publica hechos, no contexto de
## partida). Quien la escucha es [RoundManager], que sí conoce la ronda.
signal protected_fallen(building: Building)

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

## Cuántas veces pesa el edificio protegido frente a uno cualquiera, en el
## **numerador y en el denominador** de la integridad (`docs/11` §1).
##
## Pesarlo sólo en el numerador lo arrancaría por debajo del 100 %; pesarlo en los
## dos deja la ciudad intacta en 1.0 y hace que perder la escuela cueste el triple
## que perder el bloque de al lado. Es la traducción literal de `docs/narrativa`
## §8: «perderlos pesa más que perder el dron».
@export_range(1.0, 10.0, 0.5) var protected_weight: float = 3.0

var _buildings: Array[Building] = []
var _initial_hp: float = 0.0
var _total_hp: float = 0.0
var _last_emitted: float = 1.0
var _pending_delay: float = 0.0
var _has_pending: bool = false
var _defeat_emitted: bool = false
var _under_siege: Building = null
var _siege_accumulator: float = 0.0
var _protected: Building = null
var _protected_fallen_emitted: bool = false


func _ready() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	if _buildings.is_empty():
		rebuild()


## Acumuladores de publicación y de asedio. Nunca un [Timer].
func _physics_process(delta: float) -> void:
	PerfProbe.begin(&"city_integrity")
	_tick_accumulators(delta)
	PerfProbe.end(&"city_integrity")


## El cuerpo de [method _physics_process], en una función aparte para que el
## `return` temprano del asedio no se saltee el cierre de la sonda.
func _tick_accumulators(delta: float) -> void:
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
		if not is_instance_valid(building):
			continue
		if building.damage_taken.is_connected(_on_damage_taken):
			building.damage_taken.disconnect(_on_damage_taken)
		if building.damage_taken.is_connected(_on_protected_damage):
			building.damage_taken.disconnect(_on_protected_damage)
		if building.stage_changed.is_connected(_on_protected_stage):
			building.stage_changed.disconnect(_on_protected_stage)
	_protected = null
	_protected_fallen_emitted = false
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
	var weight := _weight_for(building)
	_initial_hp += weight * building.get_max_hp()
	_total_hp += weight * building.hp


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
		var weight := _weight_for(building)
		_initial_hp += weight * building.get_max_hp()
		_total_hp += weight * building.hp
	_under_siege = null
	_siege_accumulator = 0.0
	_defeat_emitted = false
	_protected_fallen_emitted = false
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


## Registra el edificio que la ronda pide proteger, o lo quita con `null`
## (`docs/11` §1).
##
## A partir de acá su HP pesa [member protected_weight] veces en el numerador y en
## el denominador de la integridad, y su caída publica [signal protected_fallen].
## Lo llama `RoundManager._resolve_protected()` justo después de `rebuild()`, con
## la ciudad todavía intacta, así que la integridad no se mueve: cambian los dos
## términos del cociente en la misma proporción.
##
## Los totales se rehacen edificio por edificio en vez de corregirse con una
## resta: es una pasada de 60 sumas, una sola vez por ronda, y evita que un
## `set_protected()` a mitad de partida deje el acumulador desviado.
func set_protected(building: Building) -> void:
	if _protected == building:
		return
	if is_instance_valid(_protected):
		if _protected.stage_changed.is_connected(_on_protected_stage):
			_protected.stage_changed.disconnect(_on_protected_stage)
		_bind_damage(_protected, false)
	_protected = building
	_protected_fallen_emitted = false
	if building != null:
		if not building.stage_changed.is_connected(_on_protected_stage):
			var _discard := building.stage_changed.connect(_on_protected_stage)
		_bind_damage(building, true)
	_recompute_totals()
	var current := get_ratio()
	if not is_equal_approx(current, _last_emitted):
		_publish(current)


## Edificio protegido de la ronda, o `null` si esta ronda no declara ninguno.
func get_protected() -> Building:
	return _protected if is_instance_valid(_protected) else null


## Verdadero si el edificio protegido ya cayó. Sin protegido es siempre `false`.
func is_protected_fallen() -> bool:
	var building := get_protected()
	return building != null and building.is_destroyed()


## Edificio marcado como «bajo asedio», o `null` si no hay ninguno.
func get_under_siege() -> Building:
	return _under_siege if is_instance_valid(_under_siege) else null


## Edificios registrados que siguen en pie, es decir, que no llegaron a `RUBBLE`.
func get_standing_count() -> int:
	return _buildings.size() - get_destroyed_count()


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


## Suma de HP recalculada edificio por edificio, **con los pesos**. Existe para
## que `city_check` pueda contrastarla con [method get_total_hp] y detectar
## deriva.
func recompute_total_hp() -> float:
	var total := 0.0
	for building: Building in _buildings:
		if is_instance_valid(building):
			total += _weight_for(building) * building.hp
	return total


## Peso de [param building] en la integridad: [member protected_weight] para el
## protegido y 1.0 para cualquier otro.
func _weight_for(building: Building) -> float:
	return protected_weight if building != null and building == _protected else 1.0


## Rehace `Σ hp` y `Σ hp_inicial` con los pesos vigentes.
func _recompute_totals() -> void:
	_initial_hp = 0.0
	_total_hp = 0.0
	for building: Building in _buildings:
		if not is_instance_valid(building):
			continue
		var weight := _weight_for(building)
		_initial_hp += weight * building.get_max_hp()
		_total_hp += weight * building.hp


# --------------------------------------------------------------------------
# Internos
# --------------------------------------------------------------------------

## Descuenta el daño aplicado del acumulador y decide si toca publicar.
func _on_damage_taken(amount: float, _point: Vector3) -> void:
	_apply_damage(amount)


## Lo mismo, pero para el edificio protegido: su daño cuenta
## [member protected_weight] veces (`docs/11` §1).
##
## Es un manejador **aparte** y no un segundo oyente sumado al de siempre: el
## protegido se desconecta de [method _on_damage_taken] al registrarse, así que por
## cada golpe corre exactamente una resta. Con dos oyentes encadenados el primero
## publicaría una integridad intermedia —la del peso 1— que nunca existió.
func _on_protected_damage(amount: float, _point: Vector3) -> void:
	_apply_damage(amount * protected_weight)


## Resta [param weighted] del acumulador y decide si toca publicar.
func _apply_damage(weighted: float) -> void:
	_total_hp = maxf(_total_hp - weighted, 0.0)
	var current := get_ratio()
	if _last_emitted - current >= emit_epsilon:
		_publish(current)
		return
	if not is_equal_approx(current, _last_emitted):
		_has_pending = true


## Conmuta a cuál de los dos manejadores de daño está atado [param building].
func _bind_damage(building: Building, weighted: bool) -> void:
	if building == null or not is_instance_valid(building):
		return
	var leaving := _on_protected_damage if not weighted else _on_damage_taken
	var entering := _on_protected_damage if weighted else _on_damage_taken
	if building.damage_taken.is_connected(leaving):
		building.damage_taken.disconnect(leaving)
	if not building.damage_taken.is_connected(entering):
		var _discard := building.damage_taken.connect(entering)


## El protegido cambió de etapa: si llegó a `RUBBLE`, se publica su caída una sola
## vez. Se mira `stage_changed` y no `destroyed` porque `destroyed` llega al final
## del derrumbe de 1,8 s y la línea de objetivo tiene que ponerse en rojo cuando el
## edificio se parte, no cuando termina de asentarse el polvo.
func _on_protected_stage(stage: Building.Stage) -> void:
	if stage != Building.Stage.RUBBLE or _protected_fallen_emitted:
		return
	_protected_fallen_emitted = true
	protected_fallen.emit(_protected)


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
