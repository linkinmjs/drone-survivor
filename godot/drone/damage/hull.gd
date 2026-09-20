## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Integridad del casco del dron (`docs/09` §2.6 y §2.7).
##
## Es un [Node] hijo del [Drone] —`Drone/Hull`, la ruta de `docs/09` §3.1— y tiene
## dos entradas: el **choque**, que descubre él mismo escuchando
## [signal RigidBody3D.body_entered] del dron, y el **daño explícito**, que le
## entra por [method apply_damage] desde el jefe (`docs/06`) o el `DebrisPool`
## (`docs/10`).
##
## ## Por qué se conecta a `body_entered` y no a `Drone.crashed(impact_speed)`
##
## `docs/09` §2.6 deja la fuente abierta y el brief pide decidir y documentarlo.
## Se usa `body_entered`, por tres razones que `crashed` no puede cubrir:
##
## 1. `crashed` **no dice contra qué se chocó**. Sin el cuerpo no hay cooldown por
##    `collider_id` (§2.6) ni forma de saber si el golpe vino de la capa 9
##    (`debris`), que se cobra por masa y no por velocidad.
## 2. `crashed` trae sus propios umbrales —6 m/s y 0.25 s globales (`docs/03`
##    §2.5)— distintos de los del casco (8 m/s y 0.35 s **por cuerpo**). Colgarse
##    de él mezclaría dos reglas de balance que viven en documentos distintos.
## 3. La velocidad que reporta `crashed` es la de **después** del contacto, o el
##    `Δv` del tick; ninguna de las dos es «la velocidad del tick anterior» que
##    pide la fórmula.
##
## ## Cómo se obtiene la velocidad previa
##
## Cuando `body_entered` llega, Jolt ya resolvió la colisión y
## `drone.linear_velocity` está frenada. El orden real de un tick de Godot es
## `flush_queries` (donde se emiten `body_entered` y corre `_integrate_forces`) →
## `_physics_process` → `step`. Así que la velocidad que [method _physics_process]
## muestrea en el tick *N* es exactamente con la que el cuerpo entra al paso *N*,
## y el `body_entered` que produce ese paso se emite al principio del tick *N+1*:
## la muestra guardada es, sin buffers ni historia, la velocidad **previa** al
## golpe.
##
## ## Velocidad del otro cuerpo
##
## [RigidBody3D] → `linear_velocity`; [StaticBody3D] → `constant_linear_velocity`;
## cualquier otro ([AnimatableBody3D], las partes del jefe) → [constant Vector3.ZERO].
## Eso **subestima** el golpe de una pata que barre a un dron quieto, y está
## previsto: ese caso lo cubre el daño explícito de `leg_sweep` (`docs/09` §2.7).
class_name Hull extends Node

## El casco recibió [param amount] de daño desde [param source_position].
signal damaged(amount: float, source_position: Vector3)

## El casco llegó a 0. Se emite **una sola vez**; [RespawnController] la escucha.
signal destroyed()

## Números del casco y del respawn (`docs/09` §3.5).
@export var profile: HullProfile

## Dron dueño de este casco. Si queda vacío se busca el primer ancestro [Drone].
@export var drone: Drone

## Integridad actual. Solo lectura desde fuera: se mueve con [method apply_damage],
## [method heal] y [method restore].
var hp: float = 100.0

var _destroyed: bool = false
var _cooldowns: Dictionary[int, float] = {}
var _previous_velocity: Vector3 = Vector3.ZERO
var _live: bool = false


func _ready() -> void:
	if profile == null:
		push_error("Hull: falta el HullProfile en %s (docs/09 §3.5)." % name)
	if drone == null:
		drone = _find_drone()
	if drone == null:
		push_error("Hull: no se encontró el Drone dueño de %s (docs/09 §3.1)." % name)
	else:
		if not drone.body_entered.is_connected(_on_body_entered):
			var _discard := drone.body_entered.connect(_on_body_entered)
		_previous_velocity = drone.linear_velocity
	hp = _max_hp()
	_live = true


## Muestrea la velocidad del tick y purga los cooldowns vencidos.
##
## Todo por acumulador, nunca con [Timer] (`docs/09` §1): el diccionario guarda los
## segundos que le quedan a cada `collider_id` y las entradas se borran al vencer,
## así que no crece con la cantidad de choques de la partida.
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	if drone != null:
		_previous_velocity = drone.linear_velocity
	if _cooldowns.is_empty():
		return
	var expired: Array[int] = []
	for id: int in _cooldowns:
		var left := _cooldowns[id] - delta
		if left <= 0.0:
			expired.append(id)
		else:
			_cooldowns[id] = left
	for id: int in expired:
		var _erased := _cooldowns.erase(id)


# --- Interfaz pública (`docs/09` §3.5) --------------------------------------------------------

## Aplica [param amount] de daño desde [param source_position]. Es el nombre
## canónico: todo daño que no venga de un choque entra por acá.
func apply_damage(amount: float, source_position: Vector3) -> void:
	if _destroyed or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	damaged.emit(amount, source_position)
	Events.drone_damaged.emit(amount, source_position)
	Events.hull_changed.emit(get_ratio())
	if hp > 0.0:
		return
	_destroyed = true
	var at_position := drone.global_position if drone != null else source_position
	destroyed.emit()
	Events.drone_destroyed.emit(at_position)
	if profile != null and profile.destroy_trauma > 0.0:
		Events.camera_trauma.emit(profile.destroy_trauma, at_position)


## Alias histórico de [method apply_damage] (`docs/09` §2.10). Ningún documento lo
## usa ya; queda para el código que se escribió contra el nombre viejo.
func take_damage(amount: float, source_position: Vector3) -> void:
	apply_damage(amount, source_position)


## Repara [param amount] de integridad, sin pasar del máximo. No resucita un casco
## ya destruido: eso es trabajo de [method restore].
func heal(amount: float) -> void:
	if _destroyed or amount <= 0.0:
		return
	var healed := minf(hp + amount, _max_hp())
	if is_equal_approx(healed, hp):
		return
	hp = healed
	Events.hull_changed.emit(get_ratio())


## Integridad normalizada, de 0.0 a 1.0.
func get_ratio() -> float:
	var maximum := _max_hp()
	if maximum <= 0.0:
		return 0.0
	return clampf(hp / maximum, 0.0, 1.0)


## `true` desde que el casco llegó a 0 hasta el siguiente [method restore].
func is_destroyed() -> bool:
	return _destroyed


## Deja el casco como nuevo: integridad al máximo, cooldowns vacíos y
## `Events.hull_changed(1.0)`. Lo llama [RespawnController].
func restore() -> void:
	hp = _max_hp()
	_destroyed = false
	_cooldowns.clear()
	_previous_velocity = drone.linear_velocity if drone != null else Vector3.ZERO
	if _live:
		Events.hull_changed.emit(get_ratio())


## Alias de [method restore] con el nombre de la tabla de `docs/09` §3.5.
func reset() -> void:
	restore()


## Saca el casco de juego **sin publicar nada**: deja de aceptar daño hasta el
## siguiente [method restore], y ni [signal destroyed] ni `Events.drone_destroyed`
## se emiten.
##
## Lo llama [RespawnController] cuando la reconstrucción no la disparó el casco
## —batería agotada, `docs/09` §2.8—: durante los doce segundos el dron sigue
## congelado en el mundo, con su colisionador puesto, y un barrido del jefe que le
## bajara los últimos puntos publicaría un **segundo** `Events.drone_destroyed` por
## la misma reconstrucción. El `RoundManager` lo contaría como una muerte de más.
func deactivate() -> void:
	_destroyed = true
	_cooldowns.clear()


## Velocidad con la que el dron entró al último paso de física. Es la que usa la
## fórmula de choque; `energy_check` la escribe para inyectar impactos sintéticos.
func set_previous_velocity(value: Vector3) -> void:
	_previous_velocity = value


## Segundos de cooldown que le quedan a [param collider_id], o 0.0 si puede volver
## a dañar.
func get_cooldown(collider_id: int) -> float:
	return float(_cooldowns.get(collider_id, 0.0))


# --- Choque -----------------------------------------------------------------------------------

## Traduce un contacto en daño (`docs/09` §2.6 y §2.7).
##
## El cooldown se registra **solo cuando el golpe hace daño**. Un roce por debajo
## del umbral no debe tapar el choque serio que venga 0.1 s después, que es
## justamente la secuencia de rebotar contra una cornisa y estrellarse.
func _on_body_entered(body: Node) -> void:
	if _destroyed or profile == null or body == null:
		return
	var id := body.get_instance_id()
	if _cooldowns.has(id):
		return
	var amount := _debris_damage(body) if _is_debris(body) else _impact_damage(body)
	if amount < profile.min_impact_damage:
		return
	_cooldowns[id] = profile.impact_cooldown
	var spatial := body as Node3D
	var source: Vector3 = spatial.global_position if spatial != null else Vector3.ZERO
	apply_damage(amount, source)


## `max(0, (v_rel − umbral) · daño_por_ms)` con la velocidad del tick anterior.
func _impact_damage(body: Node) -> float:
	var relative := (_previous_velocity - _body_velocity(body)).length()
	return maxf(0.0, (relative - profile.impact_speed_threshold) * profile.impact_damage_per_ms)


## `clamp(remap(mass, 150, 3000, 15, 35), 15, 35)` (`docs/09` §2.7). Un trozo de
## bloque bajo de 450 kg deja ≈ 17.1; uno de torre de 2 000 kg, ≈ 28.0.
func _debris_damage(body: Node) -> float:
	var mass := _body_mass(body)
	var low := profile.debris_mass_min
	var high := maxf(profile.debris_mass_max, low + 0.001)
	var mapped := remap(mass, low, high, profile.debris_damage_min, profile.debris_damage_max)
	return clampf(mapped, profile.debris_damage_min, profile.debris_damage_max)


## `true` si el cuerpo vive en la capa 9 (`debris`). Se cobra por masa y no por
## velocidad para no contar el mismo golpe dos veces.
func _is_debris(body: Node) -> bool:
	var collider := body as CollisionObject3D
	if collider == null:
		return false
	return (collider.collision_layer & PhysicsLayers.DEBRIS) != 0


func _body_mass(body: Node) -> float:
	var rigid := body as RigidBody3D
	if rigid != null:
		return rigid.mass
	var meta: Variant = body.get_meta(&"mass", null)
	if meta != null:
		return float(meta)
	return profile.debris_mass_min


func _body_velocity(body: Node) -> Vector3:
	var rigid := body as RigidBody3D
	if rigid != null:
		return rigid.linear_velocity
	var static_body := body as StaticBody3D
	if static_body != null:
		return static_body.constant_linear_velocity
	return Vector3.ZERO


func _max_hp() -> float:
	return profile.max_hp if profile != null else 100.0


func _find_drone() -> Drone:
	var node := get_parent()
	while node != null:
		var found := node as Drone
		if found != null:
			return found
		node = node.get_parent()
	return null
