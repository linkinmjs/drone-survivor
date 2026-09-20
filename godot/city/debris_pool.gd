## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Pool de escombros compartido por la ciudad y por los enemigos (`docs/10` §6 y
## §9.3, `docs/06` §4.1 y §12).
##
## Hay **uno solo por nivel**, cableado por la escena del nivel y dado de alta en
## el grupo `debris_pool`. Mantiene como mucho [constant MAX_LIVE] trozos vivos:
## al pedir el número 25 retira el más viejo, lo congela y hornea su transformada
## en el [RubbleField], que es lo que deja la ruina en pantalla sin coste físico.
##
## Dos formas de nacer un trozo:
##
## - [method request] construye uno **nuevo** desde una malla y una forma. Es el
##   caso de la ciudad, que fabrica pedazos de hormigón al derrumbar un edificio.
## - [method adopt] **reparenta nodos que ya existen** bajo el chunk. Es el caso
##   del desprendimiento de partes de enemigo: así el trozo conserva sus hijos,
##   sus materiales y su colisión sin reconstruir nada (`docs/06` §4.1).
##
## **Cableado**: quien lo necesite lo recibe por `@export`; si no lo recibe, usa
## [method resolve], que lo busca en el grupo `debris_pool` y, si no hay ninguno,
## crea uno bajo la raíz del árbol. Es el mismo patrón con el que `WeaponMount`
## resuelve su `ProjectilePool` (`docs/08` §2.6): permite que los checks y los
## bancos de prueba funcionen sin un nivel completo.
##
## **Reciclado (WP-20)**: `docs/10` §6 pide que el trozo retirado «vuelva a la
## lista libre». Los que fabricó [method request] se aparcan bajo el nodo
## [constant RECYCLED_NODE] —congelados, invisibles y fuera de toda capa— y
## [method request] los vuelve a usar reasignando la malla y la forma de sus
## hijos, en vez de construir nodos nuevos. Los que nacieron de [method adopt]
## **no** se reciclan: llevan dentro nodos ajenos (mallas, colisionadores y
## puntos débiles del enemigo) que mueren con ellos.
##
## Se aparcan bajo un nodo aparte y no como hijos directos del pool a propósito:
## `tools/enemy_parts_check.gd` enumera los `DebrisChunk` hijos del pool y da por
## sentado que todos están vivos.
class_name DebrisPool extends Node3D

## Grupo por el que lo encuentra [method resolve].
const GROUP: StringName = &"debris_pool"

## Tope de trozos vivos a la vez (`docs/10` §10).
const MAX_LIVE: int = 24

## Segundos que un trozo dormido aguanta antes del retiro anticipado (`docs/10` §6).
const SLEEP_RETIRE_SECONDS: float = 2.0

## Velocidad angular máxima por eje que recibe un trozo al nacer, en rad/s
## (`docs/06` §4.1 punto 5).
const SPIN_RANGE: float = 1.2

## Nodo bajo el que se aparcan los trozos reciclables.
const RECYCLED_NODE: StringName = &"Recycled"

## Campo de ruina donde se hornean los trozos retirados. Si falta, el trozo
## simplemente desaparece al expirar.
@export var rubble_field: RubbleField = null

## Vida por defecto de un trozo, en segundos, cuando el llamador no pasa otra.
@export_range(1.0, 120.0, 0.5) var debris_lifetime: float = 20.0

var _live: Array[DebrisChunk] = []
var _free: Array[DebrisChunk] = []
var _created: int = 0
var _recycled_total: int = 0
var _recycled: Node3D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	_recycled = get_node_or_null(NodePath(RECYCLED_NODE)) as Node3D
	if _recycled == null:
		_recycled = Node3D.new()
		_recycled.name = RECYCLED_NODE
		_recycled.visible = false
		add_child(_recycled)
	# Semilla de ronda: dos corridas con la misma semilla tiran los escombros
	# igual, que es lo que hace reproducibles a `enemy_parts_check` y al showcase.
	_rng.seed = Global.round_seed


## Envejece los trozos vivos y retira los que agotaron su vida o llevan
## demasiado dormidos. Acumulador, nunca un [Timer] (convención de `docs/00` §6).
func _physics_process(delta: float) -> void:
	var index := _live.size() - 1
	while index >= 0:
		var chunk := _live[index]
		if not is_instance_valid(chunk):
			_live.remove_at(index)
			index -= 1
			continue
		chunk.age += delta
		chunk.sleep_time = chunk.sleep_time + delta if chunk.sleeping else 0.0
		if chunk.age >= chunk.lifetime or chunk.sleep_time >= SLEEP_RETIRE_SECONDS:
			_retire_at(index)
		index -= 1


## Construye un trozo nuevo con [param mesh] y [param shape] en [param xform].
## Es la vía de la ciudad (`docs/10` §3.2). Devuelve `null` si faltan datos.
func request(mesh: Mesh, shape: Shape3D, xform: Transform3D, mass: float,
		impulse: Vector3, lifetime: float) -> DebrisChunk:
	if mesh == null and shape == null:
		push_error("DebrisPool.request: hacen falta al menos una malla o una forma.")
		return null
	_make_room()

	var chunk := _acquire_chunk(xform)
	var mesh_instance := chunk.get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh != null:
		if mesh_instance == null:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "Mesh"
			mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			chunk.add_child(mesh_instance)
		mesh_instance.mesh = mesh
		mesh_instance.visible = true
	elif mesh_instance != null:
		mesh_instance.visible = false
	chunk.rubble_mesh = mesh

	var shape_node := chunk.get_node_or_null(^"Shape") as CollisionShape3D
	if shape != null:
		if shape_node == null:
			shape_node = CollisionShape3D.new()
			shape_node.name = "Shape"
			chunk.add_child(shape_node)
		shape_node.shape = shape
		shape_node.disabled = false
	elif shape_node != null:
		shape_node.disabled = true

	_arm(chunk, mass, impulse, lifetime)
	return chunk


## Adopta nodos existentes: reparenta [param mesh] —y [param body] si no cuelga
## ya de la malla— bajo un trozo nuevo, conservando la transformada global
## (`docs/06` §4.1 pasos 1 a 5).
##
## Los `CollisionShape3D` que viajaban dentro de los cuerpos se **mueven** al
## chunk, que es quien necesita forma para ser un cuerpo rígido de verdad; los
## `PhysicsBody3D` adoptados pasan a la capa 9 y quedan inertes, viajando como
## hijos tal como manda `docs/06`. Así no se reconstruye ninguna forma y la malla
## sigue alineada con su colisión.
func adopt(mesh: MeshInstance3D, body: PhysicsBody3D, mass: float,
		impulse: Vector3, lifetime: float) -> DebrisChunk:
	if mesh == null:
		push_error("DebrisPool.adopt: la malla es nula.")
		return null
	_make_room()

	var chunk := _new_chunk(mesh.global_transform)
	mesh.reparent(chunk, true)
	mesh.owner = null
	chunk.adopted.append(mesh)
	chunk.rubble_mesh = mesh.mesh
	if body != null and not chunk.is_ancestor_of(body):
		body.reparent(chunk, true)
		body.owner = null
		chunk.adopted.append(body)

	for node: Node in _descendants(chunk):
		var physics_body := node as PhysicsBody3D
		if physics_body != null:
			physics_body.collision_layer = PhysicsLayers.DEBRIS
			physics_body.collision_mask = DebrisChunk.DEBRIS_MASK
			continue
		var collision_shape := node as CollisionShape3D
		if collision_shape != null and collision_shape.get_parent() != chunk:
			collision_shape.reparent(chunk, true)
			collision_shape.owner = null

	_arm(chunk, mass, impulse, lifetime)
	return chunk


## Trozos vivos en este momento.
func get_live_count() -> int:
	return _live.size()


## Trozos vivos, en orden de antigüedad. La copia evita que un llamador altere
## la lista interna; la usa `city_check` para saber cuándo se durmió el escombro
## de un derrumbe concreto.
func get_live_chunks() -> Array[DebrisChunk]:
	return _live.duplicate()


## Trozos aparcados a la espera de reutilización (`docs/10` §6). En régimen de
## derrumbe seguido suele valer 0: el trozo que se retira lo consume de
## inmediato el pedido que hizo sitio.
func get_free_count() -> int:
	return _free.size()


## `RigidBody3D` construidos desde que existe el pool. Con reciclado nunca pasa
## de [constant MAX_LIVE] por muchos escombros que se pidan, y eso es lo que
## verifica `city_check`.
func get_created_count() -> int:
	return _created


## Veces que un trozo volvió a la lista libre.
func get_recycled_count() -> int:
	return _recycled_total


## Retira el trozo más viejo: lo congela, lo hornea en el [RubbleField] y lo
## libera. No hace nada si no hay ninguno.
func retire_oldest() -> void:
	if _live.is_empty():
		return
	_retire_at(0)


## Retira todos los trozos sin hornearlos, incluidos los aparcados. Lo usa el
## `RoundManager` al reiniciar.
func clear() -> void:
	for chunk: DebrisChunk in _live:
		if is_instance_valid(chunk):
			chunk.queue_free()
	_live.clear()
	for chunk: DebrisChunk in _free:
		if is_instance_valid(chunk):
			chunk.queue_free()
	_free.clear()


## Devuelve el pool del nivel: el del grupo [constant GROUP] si hay alguno, o uno
## nuevo colgado de la raíz del árbol. Nunca devuelve `null`.
##
## Se cuelga de `get_tree().root` y no de la escena actual a propósito: los
## escombros no deben moverse con el enemigo ni morir con él.
static func resolve(context: Node) -> DebrisPool:
	var tree := context.get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP) as DebrisPool
	if found != null:
		return found
	var pool := DebrisPool.new()
	pool.name = "DebrisPool"
	var field := RubbleField.new()
	field.name = "RubbleField"
	pool.add_child(field)
	pool.rubble_field = field
	tree.root.add_child(pool)
	return pool


# --------------------------------------------------------------------------
# Internos
# --------------------------------------------------------------------------

## Devuelve un trozo listo para configurar en [param xform]: uno aparcado si hay,
## o uno nuevo. Siempre llega congelado, para que Jolt no lo vea aparecer dentro
## de otro cuerpo.
func _acquire_chunk(xform: Transform3D) -> DebrisChunk:
	while not _free.is_empty():
		var recycled := _free.pop_back() as DebrisChunk
		if not is_instance_valid(recycled):
			continue
		if recycled.get_parent() != self:
			recycled.reparent(self, false)
		recycled.wake_from_pool()
		recycled.global_transform = xform
		return recycled
	return _new_chunk(xform)


## Crea el `RigidBody3D` congelado y lo cuelga del pool en [param xform].
func _new_chunk(xform: Transform3D) -> DebrisChunk:
	_created += 1
	var chunk := DebrisChunk.new()
	chunk.name = "DebrisChunk"
	chunk.freeze = true
	add_child(chunk)
	chunk.global_transform = xform
	return chunk


## Fija masa, vida y tirada angular, suelta el trozo y lo da de alta como vivo.
func _arm(chunk: DebrisChunk, mass: float, impulse: Vector3, lifetime: float) -> void:
	chunk.lifetime = lifetime if lifetime > 0.0 else debris_lifetime
	chunk.age = 0.0
	chunk.sleep_time = 0.0
	var spin := Vector3(
			_rng.randf_range(-SPIN_RANGE, SPIN_RANGE),
			_rng.randf_range(-SPIN_RANGE, SPIN_RANGE),
			_rng.randf_range(-SPIN_RANGE, SPIN_RANGE))
	chunk.launch(impulse, spin, mass)
	_live.append(chunk)


## Deja sitio para un trozo más retirando el más viejo si el pool está lleno.
func _make_room() -> void:
	while _live.size() >= MAX_LIVE:
		_retire_at(0)


## Congela, hornea y libera el trozo [param index] de la lista de vivos.
func _retire_at(index: int) -> void:
	if index < 0 or index >= _live.size():
		return
	var chunk := _live[index]
	_live.remove_at(index)
	if not is_instance_valid(chunk):
		return
	chunk.freeze_in_place()
	if rubble_field != null and chunk.rubble_mesh != null:
		var field_index := rubble_field.register_mesh(chunk.rubble_mesh)
		if field_index >= 0:
			rubble_field.bake(field_index, chunk.global_transform, chunk.tint)
	# Sólo vuelven a la lista libre los que fabricó `request()`. Los de
	# `adopt()` llevan nodos del enemigo adentro y tienen que morir con ellos.
	if not chunk.adopted.is_empty() or _recycled == null:
		chunk.queue_free()
		return
	chunk.park_in_pool()
	chunk.reparent(_recycled, false)
	_free.append(chunk)
	_recycled_total += 1


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
