## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Los 256 proyectiles del jugador, su avance y la resolución de impactos
## (`docs/08` §2.6 y §2.7).
##
## **Por qué vive en el nivel y no en el dron.** Los proyectiles tienen que
## sobrevivir al respawn del dron —una bala en vuelo no desaparece porque el
## piloto reaparezca— y se comparten entre todas las fuentes de fuego del jugador.
## Por eso el nodo se instala en el nivel y el [WeaponMount] lo **busca por el
## grupo [constant GROUP] dentro de `get_tree().current_scene`**. Si no encuentra
## ninguno —`flight_sandbox`, `weapon_check`, cualquier escena de prueba— crea uno
## y lo agrega al `current_scene`, de modo que el arma funciona sola y el nivel
## sigue siendo el dueño natural cuando existe.
##
## **Lista libre O(1)**: los 256 [Projectile] se crean en `_ready()` y los índices
## libres viven en un [PackedInt32Array] usado como pila. Alta y baja son un
## `append` y un `resize`; en caliente no se instancia nada. Si se agotan se
## recicla el más viejo con un aviso: la ocupación esperada es ~11.
##
## **Resolución**: un `intersect_ray` por proyectil y por tick sobre el tramo
## `prev → next`, con máscara [constant PhysicsLayers.QUERY_SHOT] (397) y el RID
## del dron excluido. La capa 2 no está en la máscara, así que el dron es inmune a
## su propio fuego por construcción; la exclusión del RID es defensa en profundidad.
## `collide_with_areas = false` es obligatorio: evita que las `BatteryPickup`
## intercepten balas.
##
## Ningún [Area3D] como hitbox, en ninguna parte (`docs/02` §3.2).
class_name ProjectilePool extends Node

## Grupo por el que lo encuentra el [WeaponMount].
const GROUP: StringName = &"projectile_pool"

## Nombre del nodo cuando el arma tiene que crear el pool por su cuenta.
const FALLBACK_NAME: String = "ProjectilePool"

## Claves del diccionario `hit` del contrato de `docs/06` §14.1. El resolvedor no
## mete ninguna más: `weapon_check` comprueba el conjunto exacto.
const HIT_KEYS: Array[StringName] = [&"position", &"normal", &"direction", &"source",
		&"is_weak_point", &"weak_point_id", &"damage_type"]

## Tipo de daño del arma primaria.
const DAMAGE_TYPE: StringName = &"kinetic"

## Metadato que `docs/06` §3 propaga al colisionador con la parte dueña.
const META_ENEMY_PART: StringName = &"enemy_part"

## Metadato con el id de la parte blindada (capa 3).
const META_PART_ID: StringName = &"part_id"

## Metadato con el id del punto débil (capa 4).
const META_WEAK_POINT_ID: StringName = &"weak_point_id"

## Trazadores del pool; si queda en `null` se crea uno como hijo.
@export var tracer_renderer: TracerRenderer

## Pool de efectos de impacto; si queda en `null` se busca por grupo y, si no hay,
## se crea uno como hijo.
@export var impact_fx_pool: ImpactFXPool

## Perfil del arma. Lo escribe el [WeaponMount] al cablearse.
@export var profile: WeaponProfile

var _projectiles: Array[Projectile] = []
var _free: PackedInt32Array = PackedInt32Array()
var _active: PackedInt32Array = PackedInt32Array()
var _friendly_fire_damage: float = 0.0
var _recycled: int = 0
var _pool_size: int = 0
var _last_effective_damage: float = 0.0

## Parámetros del rayo de avance, **reutilizados** en vez de recreados.
##
## `PhysicsRayQueryParameters3D.create()` construye un objeto nuevo y un `Array`
## de exclusión nuevo por cada rayo. Con once proyectiles vivos eso son once
## objetos y once arreglos por tick de física, mil cien por segundo a 100 Hz, que
## el recolector de GDScript tiene que barrer (WP-24a). Acá se crean una sola vez
## y se reescriben campo a campo.
var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()

## Arreglo de exclusión del rayo: el cuerpo que disparó, y nada más.
var _exclude: Array[RID] = []


func _ready() -> void:
	add_to_group(GROUP)
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.hit_from_inside = false
	_build(profile.pool_size if profile != null else 256)
	_ensure_tracer_renderer()
	_ensure_impact_pool()


## Avanza todos los proyectiles activos y resuelve sus impactos.
##
## Recorre el arreglo de activos **hacia atrás** para poder dar de baja sin
## reindexar: borrar el elemento `i` mueve el último a su lugar, que ya se visitó.
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	PerfProbe.begin(&"projectile_pool")
	var space := _space_state()
	var index := _active.size() - 1
	while index >= 0:
		var slot := _active[index]
		var projectile := _projectiles[slot]
		if not projectile.active:
			_retire_at(index)
			index -= 1
			continue
		var previous := projectile.position
		var next := previous + projectile.velocity * delta
		var blocked := false
		if space != null and not previous.is_equal_approx(next):
			var hit := _cast(space, previous, next, projectile)
			if not hit.is_empty():
				_resolve(hit, projectile)
				blocked = true
		if blocked:
			_retire_at(index)
			index -= 1
			continue
		projectile.position = next
		projectile.age += delta
		projectile.ttl -= delta
		if projectile.ttl <= 0.0:
			_retire_at(index)
			index -= 1
			continue
		if projectile.tracer_slot >= 0 and tracer_renderer != null:
			tracer_renderer.write(projectile.tracer_slot, projectile.position,
					projectile.direction(), projectile.life_ratio())
		index -= 1
	if tracer_renderer != null:
		tracer_renderer.commit()
	PerfProbe.end(&"projectile_pool")


## Da de alta un proyectil. Devuelve `false` sólo si el pool está sin construir.
##
## [param with_tracer] pide una ranura de trazador; si las 96 están ocupadas el
## proyectil vuela igual, sin estela.
func spawn(origin: Vector3, direction: Vector3, damage: float, weak_multiplier: float,
		shooter_rid: RID, source: Node3D, with_tracer: bool) -> bool:
	if _projectiles.is_empty():
		return false
	var slot := _take_slot()
	if slot < 0:
		return false
	var speed := profile.projectile_speed if profile != null else 420.0
	var ttl := profile.projectile_ttl() if profile != null else 1.43
	var unit := direction.normalized() if direction.length_squared() > 0.0 else Vector3.FORWARD
	var projectile := _projectiles[slot]
	var _spawned := projectile.spawn(origin, unit, speed, ttl, damage, weak_multiplier,
			source, shooter_rid)
	if with_tracer and tracer_renderer != null:
		projectile.tracer_slot = tracer_renderer.acquire()
		if projectile.tracer_slot >= 0:
			tracer_renderer.write(projectile.tracer_slot, origin, unit, 1.0)
	_active.append(slot)
	return true


## Proyectiles en vuelo.
func get_active_count() -> int:
	return _active.size()


## Alias de [method get_active_count] con el nombre que usa el brief de WP-14.
func get_live_count() -> int:
	return _active.size()


## Ranuras libres del pool.
func get_free_count() -> int:
	return _free.size()


## Tamaño total del pool.
func get_pool_size() -> int:
	return _pool_size


## Daño estructural que el jugador le hizo a la ciudad, acumulado
## (`docs/08` §2.7 y `docs/10` §8). Lo lee `RoundManager` al cerrar la ronda.
func get_friendly_fire_damage() -> float:
	return _friendly_fire_damage


## Veces que hubo que reciclar el proyectil más viejo por falta de ranuras. Con la
## ocupación esperada (~11 de 256) tiene que quedarse en cero.
func get_recycled_count() -> int:
	return _recycled


## Daño **efectivo** que devolvió el último `take_damage()` de una parte enemiga
## (`docs/06` §14.1: el arma pasa el daño bruto y la parte aplica su blindaje).
## Lo consume `weapon_check`; el HUD usa `Events.hit_confirmed`.
func get_last_effective_damage() -> float:
	return _last_effective_damage


## Apaga todos los proyectiles y libera sus trazadores.
func clear() -> void:
	while not _active.is_empty():
		_retire_at(_active.size() - 1)
	if tracer_renderer != null:
		tracer_renderer.clear()


## Reinicia el acumulador de fuego amigo. Lo llama `RoundManager` al abrir ronda.
func reset_friendly_fire() -> void:
	_friendly_fire_damage = 0.0


## Copia el perfil y propaga lo que de él dependen los pools hijos.
func set_profile(new_profile: WeaponProfile) -> void:
	profile = new_profile
	if profile == null:
		return
	if impact_fx_pool != null and impact_fx_pool.impact_sound == null:
		impact_fx_pool.impact_sound = profile.impact_sound
	if _pool_size != profile.pool_size and _active.is_empty():
		_build(profile.pool_size)


# --- Construcción ----------------------------------------------------------------------------


func _build(size: int) -> void:
	var count := maxi(size, 16)
	_projectiles.clear()
	_projectiles.resize(count)
	_free.resize(count)
	_active.clear()
	for index: int in count:
		_projectiles[index] = Projectile.new()
		# Pila servida por el final: el orden inverso entrega la 0 primero.
		_free[index] = count - 1 - index
	_pool_size = count


func _ensure_tracer_renderer() -> void:
	if tracer_renderer != null:
		return
	for child: Node in get_children():
		var found := child as TracerRenderer
		if found != null:
			tracer_renderer = found
			return
	var renderer := TracerRenderer.new()
	renderer.name = "TracerRenderer"
	add_child(renderer)
	tracer_renderer = renderer


func _ensure_impact_pool() -> void:
	if impact_fx_pool != null:
		return
	var tree := get_tree()
	if tree != null:
		for node: Node in tree.get_nodes_in_group(ImpactFXPool.GROUP):
			var found := node as ImpactFXPool
			if found != null:
				impact_fx_pool = found
				break
	if impact_fx_pool == null:
		var pool := ImpactFXPool.new()
		pool.name = "ImpactFXPool"
		add_child(pool)
		impact_fx_pool = pool
	if profile != null and impact_fx_pool.impact_sound == null:
		impact_fx_pool.impact_sound = profile.impact_sound


# --- Lista libre -----------------------------------------------------------------------------


## Índice libre, o el del proyectil más viejo si no queda ninguno.
func _take_slot() -> int:
	var free_count := _free.size()
	if free_count > 0:
		var slot := _free[free_count - 1]
		_free.resize(free_count - 1)
		return slot
	if _active.is_empty():
		return -1
	# Reciclar el más viejo: el de mayor `age` entre los activos.
	var oldest_index := 0
	var oldest_age := -1.0
	for index: int in _active.size():
		var candidate := _projectiles[_active[index]]
		if candidate.age > oldest_age:
			oldest_age = candidate.age
			oldest_index = index
	_recycled += 1
	push_warning("ProjectilePool: pool agotado (%d), se recicla el proyectil más viejo." % _pool_size)
	# `_retire_at` devuelve la ranura al final de la pila libre; se la vuelve a
	# sacar de inmediato para entregarla.
	_retire_at(oldest_index)
	var free_now := _free.size()
	if free_now <= 0:
		return -1
	var slot := _free[free_now - 1]
	_free.resize(free_now - 1)
	return slot


## Da de baja el activo en la posición [param index] del arreglo de activos.
func _retire_at(index: int) -> void:
	if index < 0 or index >= _active.size():
		return
	var slot := _active[index]
	var projectile := _projectiles[slot]
	if projectile.tracer_slot >= 0 and tracer_renderer != null:
		tracer_renderer.release(projectile.tracer_slot)
	projectile.deactivate()
	var last := _active.size() - 1
	_active[index] = _active[last]
	_active.resize(last)
	_free.append(slot)


# --- Consulta y resolución -------------------------------------------------------------------


## Estado del espacio de física del mundo 3D del árbol, o `null` si no hay.
func _space_state() -> PhysicsDirectSpaceState3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var world := viewport.find_world_3d()
	if world == null:
		return null
	return world.direct_space_state


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		projectile: Projectile) -> Dictionary:
	_query.from = from
	_query.to = to
	_query.collision_mask = profile.hit_mask if profile != null else PhysicsLayers.QUERY_SHOT
	_exclude.clear()
	if projectile.shooter_rid.is_valid():
		_exclude.append(projectile.shooter_rid)
	_query.exclude = _exclude
	return space.intersect_ray(_query)


## Aplica la tabla de resolución por capa de `docs/08` §2.7 y publica
## `Events.hit_confirmed`, con la superficie que devuelve [method surface_for].
func _resolve(raycast: Dictionary, projectile: Projectile) -> void:
	var collider := raycast.get("collider") as Object
	var point := raycast.get("position", projectile.position) as Vector3
	var normal := raycast.get("normal", Vector3.UP) as Vector3
	var direction := projectile.direction()
	var layer := _collider_layer(collider)

	var weak := false
	var lethal := false
	var weak_point_id := StringName()
	var part_id := StringName()
	if collider != null:
		if collider.has_meta(META_WEAK_POINT_ID):
			weak_point_id = StringName(collider.get_meta(META_WEAK_POINT_ID))
			weak = weak_point_id != StringName()
		if collider.has_meta(META_PART_ID):
			part_id = StringName(collider.get_meta(META_PART_ID))

	var amount := projectile.damage
	if weak:
		amount *= projectile.weak_multiplier

	# `confirmed` decide si el impacto llega al bus. Sólo lo hacen los que tienen
	# `HitKind` en la tabla de `docs/08` §2.7: partes, puntos débiles y ciudad. Un
	# tiro al suelo o a un escombro deja chispas pero **no** marca hitmarker.
	var confirmed := false
	if weak or part_id != StringName():
		lethal = _damage_part(collider, amount, _build_hit(point, normal, direction,
				projectile.source, weak, weak_point_id))
		confirmed = true
	elif (layer & PhysicsLayers.CITY) != 0:
		_damage_building(collider, point)
		confirmed = true
	elif (layer & PhysicsLayers.DEBRIS) != 0:
		_push_debris(collider, point, direction)
	elif (layer & PhysicsLayers.ENEMY_BODY) != 0:
		# Capa 3 sin `part_id`: error de importación. Se trata como `world`.
		push_warning("ProjectilePool: colisionador de capa 3 sin '%s'; se trata como mundo."
				% String(META_PART_ID))

	_play_fx(point, normal, layer)
	if confirmed:
		Events.hit_confirmed.emit(point, weak, lethal,
				surface_for(layer, weak, part_id != StringName()))


## Superficie contra la que pegó un disparo, para el [param surface] de
## `Events.hit_confirmed` (`docs/02` §5.1, WP-26).
##
## Es la **misma** tabla de resolución de `docs/08` §2.7 mirada desde el otro
## lado: el emisor es el único que tiene el collider, así que es el único que
## puede decir si esos tres flotantes son una rodilla, una coraza o una fachada.
## Se expone como `static` para que `weapon_check` pueda aseverar el mapeo
## completo —incluido `world`, que hoy no llega a viajar— sin fabricar un
## colisionador de cada capa.
static func surface_for(layer: int, weak: bool, has_part: bool) -> StringName:
	if weak:
		return &"weak"
	if has_part:
		return &"armor"
	if (layer & PhysicsLayers.CITY) != 0:
		return &"city"
	# Todo lo demás es `world`, y eso incluye el caso raro de un colisionador de
	# capa 3 **sin** `part_id`: [method _resolve] ya lo trata como mundo y avisa
	# del error de importación, así que la superficie tiene que decir lo mismo.
	return &"world"


## Construye el diccionario `hit` con **exactamente** las claves del contrato de
## `docs/06` §14.1. Nada de datos internos acá: el resolvedor ya tiene el
## `Dictionary` crudo del `intersect_ray` para lo suyo.
func _build_hit(point: Vector3, normal: Vector3, direction: Vector3, source: Node3D,
		weak: bool, weak_point_id: StringName) -> Dictionary:
	var hit: Dictionary = {
		&"position": point,
		&"normal": normal,
		&"direction": direction,
		&"source": source,
		&"is_weak_point": weak,
		&"damage_type": DAMAGE_TYPE,
	}
	if weak:
		hit[&"weak_point_id"] = weak_point_id
	return hit


## Aplica daño a la parte dueña del colisionador y devuelve la letalidad.
##
## El dueño se busca en tres saltos, en este orden: el metadato `enemy_part` que
## `docs/06` §3 propaga al cuerpo, el propio colisionador y su padre. El primero
## que tenga `take_damage` gana; así el arma resuelve en O(1) sin cadenas de
## `get_parent()`.
func _damage_part(collider: Object, amount: float, hit: Dictionary) -> bool:
	var target := _damage_target(collider)
	if target == null:
		push_warning("ProjectilePool: colisionador con metadatos de parte pero sin take_damage().")
		return false
	# `EnemyPart.take_damage` devuelve el daño efectivo (`docs/06` §14.1), pero un
	# duck type de prueba puede no devolver nada: `float(null)` sería un error de
	# runtime, así que se comprueba el tipo antes de convertir.
	var returned: Variant = target.call(&"take_damage", amount, hit)
	_last_effective_damage = float(returned) if returned is float or returned is int else 0.0
	if target.has_method(&"is_broken"):
		return bool(target.call(&"is_broken"))
	return false


## Nodo que recibe `take_damage(amount, hit)`.
func _damage_target(collider: Object) -> Object:
	if collider == null:
		return null
	if collider.has_meta(META_ENEMY_PART):
		var owner_part := collider.get_meta(META_ENEMY_PART) as Object
		if owner_part != null and is_instance_valid(owner_part) \
				and owner_part.has_method(&"take_damage"):
			return owner_part
	if collider.has_method(&"take_damage"):
		return collider
	var node := collider as Node
	if node != null:
		var parent := node.get_parent()
		if parent != null and parent.has_method(&"take_damage"):
			return parent
	return null


## Capa 8: daño estructural escalado por `city_friendly_fire_scale`, por duck
## typing. `Building` todavía no existe (WP-20): lo único que se le pide al nodo
## es un `take_damage(amount, point)`.
func _damage_building(collider: Object, point: Vector3) -> void:
	if collider == null:
		return
	# Los dos respaldos son los del perfil del MVP tras el rebalance del checkpoint 4
	# (`damage` 16 × `city_friendly_fire_scale` 0.375 = 6 por impacto, igual que los
	# 12 × 0.5 de antes). Sin perfil el pool no debería llegar acá nunca; si llega,
	# que al menos no invente un número de otra época.
	var scale := profile.city_friendly_fire_scale if profile != null else 0.375
	var amount := (profile.damage if profile != null else 16.0) * scale
	_friendly_fire_damage += amount
	if collider.has_method(&"take_damage"):
		collider.call(&"take_damage", amount, point)


## Capa 9: sólo un empujón. Un escombro no tiene HP.
func _push_debris(collider: Object, point: Vector3, direction: Vector3) -> void:
	var body := collider as RigidBody3D
	if body == null:
		return
	var impulse := profile.debris_impulse if profile != null else 0.6
	body.apply_impulse(direction * impulse, point - body.global_position)


func _play_fx(point: Vector3, normal: Vector3, layer: int) -> void:
	if impact_fx_pool == null:
		return
	var _fx := impact_fx_pool.spawn(point, normal, ImpactFXPool.variant_for_layer(layer))
	if ImpactFXPool.layer_takes_decal(layer):
		var _placed := impact_fx_pool.spawn_decal(point, normal)


## Capas del colisionador, o 0 si el objeto no es un cuerpo de física.
func _collider_layer(collider: Object) -> int:
	var body := collider as CollisionObject3D
	if body == null:
		return 0
	return body.collision_layer
