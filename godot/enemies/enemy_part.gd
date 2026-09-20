## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Una parte dañable de un enemigo (`docs/06` §4).
##
## **No es un cuerpo físico**: envuelve el par `MeshInstance3D` + `AnimatableBody3D`
## que vino del GLB y le pone vida, blindaje y desprendimiento. Vive bajo `Parts/`
## y la construye [EnemyBase] en `_ready()` leyendo los metadatos del import.
##
## El daño efectivo es `amount · (1 − armor)`. Si el impacto llegó por un punto
## débil expuesto, **el arma ya aplicó el multiplicador** (`docs/08` §2.7): acá no
## se vuelve a aplicar nunca.
##
## La referencia al enemigo se tipa como [Node3D] y no como `EnemyBase` a
## propósito: [EnemyBase] ya depende de esta clase y la referencia cruzada sería
## cíclica. La comunicación de vuelta va por señales, no por llamadas.
class_name EnemyPart extends Node

## La parte cruzó 0 de vida. [EnemyBase] escucha para encadenar tambaleo, fases y
## deshabilitación de función.
signal broken(part_id: StringName)

## La parte recibió daño. [param amount] es el daño **efectivo**, ya descontado
## el blindaje, y [param remaining] la vida que queda.
signal damaged(part_id: StringName, amount: float, remaining: float)

## La parte se fue como escombro, sola o arrastrada por su padre.
signal detached(part_id: StringName)

## Conjunto canónico de funciones (`docs/06` §3).
const FUNCTIONS: PackedStringArray = ["leg", "sensor", "weapon", "cosmetic", "core"]

## Sinónimos descriptivos que el `parts.json` puede traer, con su equivalente.
const FUNCTION_ALIASES: Dictionary[StringName, StringName] = {
	&"vision": &"sensor",
	&"optics": &"sensor",
	&"sensor_head": &"sensor",
	&"gun": &"weapon",
	&"turret": &"weapon",
	&"body": &"core",
}

## Id de la parte; coincide con el nombre del nodo y con el metadato `part_id`.
var part_id: StringName = &""

## Malla de la parte, tal como la importó `docs/05`.
var mesh: MeshInstance3D = null

## Colisionador `<id>_body` de la parte. `null` en una parte sin colisión.
var body: PhysicsBody3D = null

## Enemigo dueño de la parte ([EnemyBase], tipado flojo para evitar el ciclo).
var enemy: Node3D = null

## Pool que recibe el escombro al desprenderse.
var debris_pool: DebrisPool = null

## Primer ancestro que también es una parte, o `null` si es la raíz del grafo.
var parent_part: EnemyPart = null

## Partes que cuelgan directamente de ésta.
var child_parts: Array[EnemyPart] = []

## Vida actual.
var hp: float = 0.0

## Vida inicial; es el denominador de [method structure_ratio].
var max_hp: float = 1.0

## Fracción de daño absorbida, recortada a `[0.0, 0.99]`.
var armor: float = 0.90

## Si la parte se convierte en escombro al romperse.
var detachable: bool = false

## Masa del escombro en kilogramos.
var debris_mass: float = 0.0

## Vida del escombro en segundos.
var debris_lifetime: float = 20.0

## Velocidad inicial del escombro en m/s; el impulso es `masa · detach_speed`.
var detach_speed: float = 3.0

## Función canónica de la parte: `leg`, `sensor`, `weapon`, `cosmetic` o `core`.
var function: StringName = &"cosmetic"

## Peso en [method EnemyBase.total_structure_ratio]; 0 la deja fuera.
var structure_weight: float = 1.0

## Sacudida de cámara al romperse.
var break_trauma: float = 0.35

## Escala del polvo de rotura.
var dust_scale: float = 1.0

## Id del punto débil que hospeda o que representa; `&""` si no tiene.
var weak_point_id: StringName = &""

## Flags del `parts.json` (`root`, `detachable`, `weak_point`, `leg_root`,
## `leg_segment`, `foot`, `cosmetic`, `staged`…).
var flags: PackedStringArray = PackedStringArray()

## La malla trae al menos una superficie emisiva (`docs/05` §9.2).
var has_emissive_surface: bool = false

## La parte llegó sin colisionador: no recibe daño ni se desprende
## (`ERR_ENEMY_PART_NO_BODY`, `docs/06` §2.1 punto 3).
var invalid: bool = false

var _broken: bool = false
var _detached: bool = false


## Lee los metadatos que escribió el importador (`docs/05` §12) y deja la parte
## configurada. [param override] pisa lo que trajo el GLB y puede ser `null`.
func configure(mesh_instance: MeshInstance3D, override: EnemyPartProfile,
		armor_default: float) -> void:
	mesh = mesh_instance
	part_id = StringName(mesh_instance.get_meta(&"part_id", mesh_instance.name))
	name = String(part_id)
	max_hp = float(mesh_instance.get_meta(&"hp", 600))
	armor = float(mesh_instance.get_meta(&"armor", armor_default))
	detachable = bool(mesh_instance.get_meta(&"detachable", false))
	debris_mass = float(mesh_instance.get_meta(&"debris_mass", 0.0))
	weak_point_id = StringName(mesh_instance.get_meta(&"weak_point_id", ""))
	function = StringName(mesh_instance.get_meta(&"function", "cosmetic"))
	flags = mesh_instance.get_meta(&"flags", PackedStringArray()) as PackedStringArray
	has_emissive_surface = bool(mesh_instance.get_meta(&"has_emissive_surface", false))

	if override != null:
		max_hp = override.hp
		armor = override.armor
		detachable = override.detachable
		if override.debris_mass > 0.0:
			debris_mass = override.debris_mass
		function = override.function
		structure_weight = override.structure_weight
		break_trauma = override.break_trauma
		dust_scale = override.dust_scale

	armor = clampf(armor, 0.0, 0.99)
	max_hp = maxf(max_hp, 1.0)
	hp = max_hp
	function = normalize_function(function)


## Cuelga el colisionador `<id>_body` y le propaga los metadatos que `docs/08`
## lee del `collider` que devuelve `intersect_ray` (`docs/06` §2.1 punto 3).
func bind_body(part_body: PhysicsBody3D) -> void:
	body = part_body
	if body == null:
		invalid = true
		return
	body.set_meta(&"part_id", String(part_id))
	body.set_meta(&"weak_point_id", String(weak_point_id))
	body.set_meta(&"enemy_part", self)
	if mesh != null:
		mesh.set_meta(&"enemy_part", self)


## Normaliza una función descriptiva al conjunto canónico. Devuelve `&""` si no
## la reconoce, para que el llamador registre `ERR_ENEMY_FUNCTION_UNKNOWN`.
static func normalize_function(raw: StringName) -> StringName:
	if FUNCTIONS.has(String(raw)):
		return raw
	if FUNCTION_ALIASES.has(raw):
		return FUNCTION_ALIASES[raw]
	return &""


## Aplica daño y devuelve el **daño efectivo** (`docs/06` §14.1). No escribe nada
## dentro de [param hit]: el llamador consulta la letalidad con [method is_broken].
func take_damage(amount: float, hit: Dictionary) -> float:
	if invalid or _broken or _detached or amount <= 0.0:
		return 0.0
	var effective := amount * (1.0 - armor)
	hp = maxf(0.0, hp - effective)
	damaged.emit(part_id, effective, hp)
	if hp <= 0.0:
		_break(hit)
	return effective


## `true` cuando la vida llegó a 0.
func is_broken() -> bool:
	return _broken


## `true` cuando la parte ya viaja bajo un [DebrisChunk], sola o con su padre.
func is_detached() -> bool:
	return _detached


## Vida restante de 0 a 1.
func structure_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


## Posición de la parte en el mundo; `Vector3.ZERO` si perdió la malla.
func world_position() -> Vector3:
	if mesh == null or not is_instance_valid(mesh):
		return Vector3.ZERO
	return mesh.global_position


## Masa efectiva del escombro: la del balance, o la estimada por el sidecar si
## el balance la dejó en 0 (`docs/05` §4.2).
func effective_debris_mass() -> float:
	return debris_mass if debris_mass > 0.0 else 1000.0


## Desprende la parte: la reparenta bajo un [DebrisChunk] conservando la
## transformada global, cambia su colisión a la capa 9, se lleva a sus hijos y
## publica el hecho (`docs/06` §4.1).
func detach(impulse: Vector3) -> void:
	if _detached or invalid or mesh == null or not is_instance_valid(mesh):
		return
	if debris_pool == null:
		push_error("EnemyPart '%s': no hay DebrisPool para desprenderla." % part_id)
		return

	var world := mesh.global_transform
	_detached = true
	var chunk := debris_pool.adopt(mesh, body, effective_debris_mass(), impulse, debris_lifetime)
	if chunk == null:
		_detached = false
		return
	# `adopt()` ya conserva la transformada; se reafirma porque es la invariante
	# que vigila el riesgo 3 de `docs/06` §17.
	mesh.global_transform = world

	for descendant: EnemyPart in descendants():
		descendant._mark_detached()

	_publish_break(world.origin)
	detached.emit(part_id)


## Todas las partes que cuelgan de ésta, a cualquier profundidad.
func descendants() -> Array[EnemyPart]:
	var found: Array[EnemyPart] = []
	var pending: Array[EnemyPart] = child_parts.duplicate()
	while not pending.is_empty():
		var current: EnemyPart = pending.pop_back()
		found.append(current)
		pending.append_array(current.child_parts)
	return found


# --------------------------------------------------------------------------
# Internos
# --------------------------------------------------------------------------

## Cruce de 0 de vida: publica, avisa y, si corresponde, se desprende.
func _break(hit: Dictionary) -> void:
	_broken = true
	hp = 0.0
	var origin := world_position()
	# Una parte que se desprende publica desde `detach()`, con la transformada ya
	# congelada: así nunca hay dos `enemy_part_broken` con el mismo id.
	if not detachable:
		_publish_break(origin)
	broken.emit(part_id)
	if detachable and not _detached:
		detach(_impulse_from(hit))


## Emite el par de hechos de rotura del bus (`docs/02` §5.1).
func _publish_break(origin: Vector3) -> void:
	Events.enemy_part_broken.emit(enemy, part_id, origin)
	Events.camera_trauma.emit(break_trauma, origin)


## Impulso de desprendimiento: la dirección del disparo mezclada con la vertical,
## escalada por la masa para que una antena de 250 kg y un fémur de 42 t salgan a
## la misma velocidad.
func _impulse_from(hit: Dictionary) -> Vector3:
	var direction := Vector3.UP
	if hit.has("direction"):
		var shot := hit["direction"] as Vector3
		if not shot.is_zero_approx():
			direction = (shot.normalized() + Vector3.UP * 0.5).normalized()
	elif enemy != null and is_instance_valid(enemy):
		var outward := world_position() - enemy.global_position
		outward.y = 0.0
		if not outward.is_zero_approx():
			direction = (outward.normalized() + Vector3.UP * 0.5).normalized()
	return direction * effective_debris_mass() * detach_speed


## Marca la parte como ida con su padre: deja de recibir daño y de contar para la
## integridad, pero sigue existiendo (`docs/06` §4.1 punto 2).
func _mark_detached() -> void:
	if _detached:
		return
	_detached = true
	detached.emit(part_id)
