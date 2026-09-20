## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Percepción del enemigo (`docs/06` §9). Reemplaza al placeholder de WP-16.
##
## Corre a [member PerceptionProfile.hz] (10 Hz) acumulando tiempo dentro de
## `_physics_process`, nunca en `_process` ni con un [Timer], y produce una
## **creencia** sobre el dron, no la verdad:
##
## 1. [b]Línea de visión[/b]: un `intersect_ray` desde la cabeza —la parte
##    `wp_head_visor`, o `hull` si falta— hasta la posición real del dron, con
##    máscara `world | city` y los cuerpos propios excluidos. Si golpea algo
##    antes de llegar, no hay visión.
## 2. [b]Ruido[/b]: la medida es la posición real más un gaussiano por eje de
##    desviación `noise_base + noise_speed_factor · velocidad_del_dron`
##    (2.0 + 0.25·v), generado por Box-Muller con un [RandomNumberGenerator]
##    sembrado en `Global.round_seed ^ hash(enemy_id)`: la misma semilla
##    reproduce la misma pelea.
## 3. [b]Filtro paso bajo[/b]: `believed_position` persigue la medida con
##    `1 - exp(-delta / filter_tau)` (τ = 0.35 s) y `believed_velocity` es la
##    derivada de la creencia, suavizada con el mismo τ.
## 4. [b]Memoria[/b]: al perder la visión se sigue extrapolando con la velocidad
##    creída durante `memory_seconds` (4.5 s) mientras [member confidence] cae
##    linealmente de 1 a 0. Al expirar, [method search_point] entrega puntos
##    sobre una espiral de radio creciente que se regenera cada 2 s.
## 5. [b]Ceguera[/b]: [method blind] multiplica la desviación por 5 y recorta la
##    memoria a 1.5 s mientras dura.
##
## [b]Campo contra método[/b]: `docs/06` §9 y §14 declaran `has_los` como
## [b]campo público[/b] y el placeholder de WP-16 ya lo expone así, de modo que
## acá sigue siendo una variable. GDScript no admite un miembro y un método con
## el mismo nombre, así que la consulta en forma de función es
## [method has_line_of_sight].
class_name Perception extends Node

## Cambió la línea de visión. [param value] es el estado nuevo.
signal los_changed(value: bool)

## Se recuperó la línea de visión (`docs/06` §14).
signal los_gained()

## Se perdió la línea de visión (`docs/06` §14).
signal los_lost()

## Ajustes. Los inyecta [EnemyBase] desde `EnemyProfile.perception`.
@export var profile: PerceptionProfile = null

## Objetivo a seguir. Lo fija [method set_target]; también se acepta por
## `@export` para las escenas de prueba.
@export var target: Node3D = null

## Hay línea de visión directa con el objetivo.
var has_los: bool = false

## Posición creída del objetivo.
var believed_position: Vector3 = Vector3.ZERO

## Velocidad creída del objetivo.
var believed_velocity: Vector3 = Vector3.ZERO

## Confianza en la creencia, de 0 a 1. Vale 1 con visión y decae a 0 en
## `memory_seconds`.
var confidence: float = 0.0

var _enemy: Node3D = null
var _head: Node3D = null
var _exclude: Array[RID] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _query: PhysicsRayQueryParameters3D = null
var _accumulator: float = 0.0
var _since_sample: float = 0.0
var _blind_left: float = 0.0
var _since_los: float = 1.0e6
var _ticks: int = 0
var _ready_to_sense: bool = false
var _has_previous: bool = false
var _previous_target: Vector3 = Vector3.ZERO
var _target_speed: float = 0.0
var _last_noise: Vector3 = Vector3.ZERO
var _last_measurement: Vector3 = Vector3.ZERO
var _search_point: Vector3 = Vector3.ZERO
var _search_age: float = 0.0
var _search_elapsed: float = 0.0
var _search_index: int = 0
var _spare_gauss: float = 0.0
var _has_spare: bool = false


## Lleva el acumulador del muestreo y el de la ceguera. Nunca usa un [Timer].
##
## Con [member Global.debug_freeze_ai] no muestrea nada (`docs/11` §11): el
## enemigo deja de percibir y, al soltar la bandera, la primera muestra vuelve a
## medir la velocidad del objetivo desde cero en vez de inventarse un salto con
## la posición de hace dos minutos.
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	if Global.debug_freeze_ai:
		_has_previous = false
		return
	_since_los += delta
	if _blind_left > 0.0:
		_blind_left = maxf(0.0, _blind_left - delta)
	if not _ready_to_sense:
		_setup()
		if not _ready_to_sense:
			return

	var step := 1.0 / maxf(_profile().hz, 0.5)
	_accumulator += delta
	_since_sample += delta
	# Tope de rezago: con `Engine.time_scale` alto, un frame largo no puede
	# disparar cien muestras de golpe.
	if _accumulator > step * 8.0:
		_accumulator = step * 8.0
	while _accumulator >= step:
		_accumulator -= step
		# El paso que ve la muestra es el **tiempo real transcurrido**, no el
		# nominal: con `delta` de 0.04 s el acumulador dispara cada 0.08 o 0.12 s
		# alternando, y dividir por 0.1 s daría una velocidad del objetivo que
		# oscila un 20 % sin que el objetivo cambie de velocidad.
		var real_step := _since_sample
		_since_sample = 0.0
		_sample(maxf(real_step, 0.0001))


# --------------------------------------------------------------------------
# Interfaz pública (`docs/06` §14)
# --------------------------------------------------------------------------

## Fija el objetivo a perseguir y reinicia la creencia sobre él.
func set_target(drone: Node3D) -> void:
	target = drone
	_has_previous = false
	_target_speed = 0.0
	if drone != null:
		believed_position = drone.global_position
	_last_measurement = believed_position
	believed_velocity = Vector3.ZERO


## Objetivo actual, o `null`.
func get_target() -> Node3D:
	return target


## `true` si hay línea de visión directa. Es la forma funcional del campo
## [member has_los], que `docs/06` §14 declara como variable pública.
func has_line_of_sight() -> bool:
	return has_los


## Ciega la percepción por [param seconds]: la desviación del ruido se
## multiplica por `blind_noise_multiplier` y la memoria se recorta a
## `blind_memory_seconds` (`docs/06` §9 punto 5).
func blind(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_blind_left = maxf(_blind_left, seconds)


## Alias de [method blind] con el nombre que usa `ai_check`.
func set_blinded(seconds: float) -> void:
	blind(seconds)


## Devuelve la percepción a su estado nominal cancelando la ceguera.
##
## Es el gancho del [b]sensor de respaldo[/b] del Arachnodroid, que a los 45 s de
## romperle el visor restituye la percepción completa (`docs/07` §9). WP-19 lo
## llama desde el temporizador del `on_destroy`; `ai_check` lo usa para volver a
## medir el ruido nominal después de la prueba de ceguera.
func restore_sight() -> void:
	_blind_left = 0.0


## `true` mientras dura la ceguera.
func is_blinded() -> bool:
	return _blind_left > 0.0


## Segundos de ceguera que quedan.
func blind_remaining() -> float:
	return _blind_left


## Segundos desde la última muestra con línea de visión.
func time_since_los() -> float:
	return _since_los


## Desviación típica del ruido que se está aplicando ahora mismo, en metros.
func noise_sigma() -> float:
	var sigma := _profile().noise_base + _profile().noise_speed_factor * _target_speed
	if is_blinded():
		sigma *= _profile().blind_noise_multiplier
	return sigma


## Segundos de memoria efectivos: los nominales, o los de ceguera si está ciego.
func memory_window() -> float:
	return _profile().blind_memory_seconds if is_blinded() else _profile().memory_seconds


## Desplazamiento gaussiano de la última medida. Lo usa `ai_check` para medir la
## desviación real sobre 200 muestras.
func last_noise() -> Vector3:
	return _last_noise


## Última medida cruda (posición real + ruido), antes del filtro paso bajo.
func last_measurement() -> Vector3:
	return _last_measurement


## Velocidad real del objetivo que alimenta la desviación del ruido, en m/s.
func target_speed() -> float:
	return _target_speed


## Muestras tomadas desde que arrancó el nodo. `ai_check` lo usa para verificar
## los 10 Hz.
func tick_count() -> int:
	return _ticks


## Punto de la espiral de búsqueda (`docs/06` §9 punto 4).
##
## Mientras hay creencia viva devuelve la posición creída; sin ella entrega
## puntos sobre una espiral centrada en la última posición conocida, de radio
## creciente y regenerada cada `search_refresh` segundos.
func search_point() -> Vector3:
	if confidence > 0.0:
		return believed_position
	return _search_point


## Nodo desde el que sale el rayo de línea de visión.
func head_node() -> Node3D:
	return _head


## Rehace el cableado (cabeza, exclusiones y semilla). Lo llaman las escenas de
## prueba que cambian de enemigo o de semilla sin recrear el nodo.
func rebuild() -> void:
	_ready_to_sense = false
	_setup()


# --------------------------------------------------------------------------
# Muestreo
# --------------------------------------------------------------------------

## Resuelve enemigo, cabeza, exclusiones y semilla. Se hace perezosamente porque
## el `_ready()` de este nodo corre [b]antes[/b] que el de [EnemyBase], que es
## quien construye las partes e inyecta el [PerceptionProfile].
func _setup() -> void:
	_enemy = get_parent() as Node3D
	if _enemy == null:
		return
	var enemy_profile := _enemy.get(&"profile") as EnemyProfile
	if profile == null and enemy_profile != null:
		profile = enemy_profile.perception as PerceptionProfile
	_head = _resolve_head()
	if _head == null:
		return
	_collect_exclusions()
	_query = PhysicsRayQueryParameters3D.new()
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.collision_mask = _profile().los_mask
	_query.exclude = _exclude
	var enemy_id: StringName = &""
	if enemy_profile != null:
		enemy_id = enemy_profile.enemy_id
	_rng.seed = Global.round_seed ^ hash(enemy_id)
	_search_point = believed_position
	_ready_to_sense = true


## Cabeza del enemigo: la parte declarada en el perfil, la de reserva, o el
## propio nodo del enemigo si no hay grafo de partes.
func _resolve_head() -> Node3D:
	var names: Array[StringName] = [_profile().head_node_name, _profile().head_fallback_name]
	if _enemy.has_method(&"get_part"):
		for part_name: StringName in names:
			if part_name == &"":
				continue
			var part := _enemy.call(&"get_part", part_name) as EnemyPart
			if part != null and part.mesh != null:
				return part.mesh
	return _enemy


## RID de todos los cuerpos propios, para que el rayo no choque con el enemigo.
func _collect_exclusions() -> void:
	_exclude.clear()
	for node: Node in _descendants(_enemy):
		var body := node as CollisionObject3D
		if body != null:
			_exclude.append(body.get_rid())


## Una muestra completa: visión, ruido, filtro, memoria y búsqueda.
func _sample(step: float) -> void:
	_ticks += 1
	_search_age += step
	if target == null or not is_instance_valid(target):
		_lose_los()
		_decay(step)
		return

	var truth := target.global_position
	if _has_previous:
		_target_speed = truth.distance_to(_previous_target) / maxf(step, 0.0001)
	_previous_target = truth
	_has_previous = true

	var visible := _raycast(truth)
	if visible != has_los:
		has_los = visible
		los_changed.emit(visible)
		if visible:
			los_gained.emit()
		else:
			los_lost.emit()

	if not visible:
		_decay(step)
		return

	_since_los = 0.0
	confidence = 1.0
	_search_elapsed = 0.0
	_search_index = 0

	var sigma := noise_sigma()
	_last_noise = Vector3(_gauss() * sigma, _gauss() * sigma, _gauss() * sigma)
	_last_measurement = truth + _last_noise

	var alpha := 1.0 - exp(-step / maxf(_profile().filter_tau, 0.001))
	var previous := believed_position
	believed_position = believed_position.lerp(_last_measurement, alpha)
	var raw_velocity := (believed_position - previous) / maxf(step, 0.0001)
	believed_velocity = believed_velocity.lerp(raw_velocity, alpha)


## Sin visión: se extrapola con la velocidad creída y la confianza cae.
func _decay(step: float) -> void:
	var window := memory_window()
	if _since_los < window:
		believed_position += believed_velocity * step
		confidence = clampf(1.0 - _since_los / maxf(window, 0.0001), 0.0, 1.0)
		return
	confidence = 0.0
	believed_velocity = Vector3.ZERO
	_advance_search(step)


## Espiral de búsqueda: radio creciente de `search_radius_start` a
## `search_radius_end` en `search_seconds`, con punto nuevo cada
## `search_refresh` segundos (`docs/06` §9 punto 4).
func _advance_search(step: float) -> void:
	_search_elapsed += step
	if _search_age < _profile().search_refresh and _search_index > 0:
		return
	_search_age = 0.0
	var span := maxf(_profile().search_seconds, 0.001)
	var t := clampf(_search_elapsed / span, 0.0, 1.0)
	var radius := lerpf(_profile().search_radius_start, _profile().search_radius_end, t)
	# Ángulo áureo: puntos repartidos sin repetir dirección al crecer el radio.
	var angle := float(_search_index) * 2.3999632
	_search_index += 1
	_search_point = believed_position + Vector3(cos(angle), 0.0, sin(angle)) * radius


## Marca la pérdida de visión cuando el objetivo desapareció del árbol.
func _lose_los() -> void:
	if not has_los:
		return
	has_los = false
	los_changed.emit(false)
	los_lost.emit()


## `true` si el rayo cabeza → [param point] llega sin tocar nada.
func _raycast(point: Vector3) -> bool:
	var space := _enemy.get_world_3d().direct_space_state
	if space == null:
		return false
	_query.from = _head.global_position
	_query.to = point
	_query.collision_mask = _profile().los_mask
	_query.exclude = _exclude
	return space.intersect_ray(_query).is_empty()


## Gaussiano de media 0 y desviación 1 por Box-Muller polar. Guarda el segundo
## valor del par para la llamada siguiente: cuesta la mitad y no sesga nada.
func _gauss() -> float:
	if _has_spare:
		_has_spare = false
		return _spare_gauss
	var u := 0.0
	var v := 0.0
	var s := 0.0
	while s <= 0.0001 or s >= 1.0:
		u = _rng.randf_range(-1.0, 1.0)
		v = _rng.randf_range(-1.0, 1.0)
		s = u * u + v * v
	var factor := sqrt(-2.0 * log(s) / s)
	_spare_gauss = v * factor
	_has_spare = true
	return u * factor


## Perfil vigente, o uno por defecto si nadie lo inyectó.
func _profile() -> PerceptionProfile:
	if profile == null:
		profile = PerceptionProfile.new()
	return profile


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
