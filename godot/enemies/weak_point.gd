## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Punto débil de un enemigo (`docs/06` §5).
##
## Vive bajo `WeakPoints/` y apunta a la [EnemyPart] que recibe el daño y a la
## parte que lo hospeda. No tiene lógica por enemigo: todo sale de su
## [WeakPointProfile].
##
## Al quedar **expuesto** su colisionador baja a la capa 4 (`enemy_weak`, máscara
## 1·2), el emisivo se enciende y el cuerpo entra en el grupo `weak_points`, que
## es de donde salen los candidatos de la asistencia de puntería (`docs/08` §2.8).
## Al cubrirse vuelve a la capa 3 (`enemy_body`, máscara 1·2·8·9), el emisivo se
## apaga y sale del grupo: el disparo sigue impactando, pero como carcasa.
##
## **Qué entra en el grupo**: entra el `AnimatableBody3D` del punto débil, no
## este nodo. `docs/06` §2.1 punto 5 pide dar de alta «el punto débil» y
## `docs/08` §2.8 le pide al candidato su `global_position`, que un [Node] pelado
## no tiene; el colisionador es además el nodo que el rayo del arma devuelve y el
## que lleva los metadatos `weak_point_id` y `enemy_part`.
class_name WeakPoint extends Node

## Cambió la exposición del punto débil.
signal exposure_changed(weak_point_id: StringName, exposed: bool)

## El punto débil se rompió. [EnemyBase] ejecuta acá su `on_destroy`.
signal destroyed(weak_point_id: StringName)

## Condiciones de exposición combinables (`docs/06` §5).
enum Exposure {
	ALWAYS,       ## Siempre expuesto.
	WHILE_ATTACK, ## Mientras la capa de acción está en `TELEGRAPH` o `ACTIVE`.
	AFTER_PARTS,  ## Tras romper las partes declaradas, o una cantidad de ellas.
	ANGLE_CONE,   ## Sólo dentro de un cono anclado al hospedador.
	TIMED,        ## Parpadeo periódico.
}

## Grupo del que sale la asistencia de puntería (`docs/08` §2.8).
const GROUP: StringName = &"weak_points"

## Estados de la capa de acción que cuentan como «atacando».
const ATTACK_STATES: Array[StringName] = [&"TELEGRAPH", &"ACTIVE"]

## Máscara de un punto débil expuesto: `world | drone` (`docs/02` §3.1).
## Metadato del cuerpo del hospedador que cuenta cuántos de sus puntos débiles
## están expuestos ahora mismo (`WeakPointProfile.pierces_host`).
const PIERCE_META: StringName = &"weak_points_open"

const EXPOSED_MASK: int = PhysicsLayers.WORLD | PhysicsLayers.DRONE

## Máscara de un punto débil cubierto: la de una parte blindada.
const COVERED_MASK: int = PhysicsLayers.WORLD | PhysicsLayers.DRONE \
		| PhysicsLayers.CITY | PhysicsLayers.DEBRIS

## Configuración declarativa del punto débil.
var profile: WeakPointProfile = null

## Parte que recibe el daño (la malla `wp_*` del GLB).
var part: EnemyPart = null

## Parte que lo hospeda; define el origen y los ejes del cono.
var host: EnemyPart = null

## Enemigo dueño ([EnemyBase], tipado flojo para no cerrar un ciclo de clases).
var enemy: Node3D = null

var _exposed: bool = false
var _applied: bool = false
var _material: BaseMaterial3D = null


## Deja el punto débil listo. Se llama **antes** de colgarlo del árbol, porque
## `_ready()` ya aplica el estado inicial de capas, emisivo y grupo.
func setup(weak_point_profile: WeakPointProfile, weak_part: EnemyPart,
		host_part: EnemyPart, owner_enemy: Node3D) -> void:
	profile = weak_point_profile
	part = weak_part
	host = host_part if host_part != null else weak_part.parent_part
	enemy = owner_enemy
	name = String(profile.weak_point_id)
	# El HP de un punto débil es asunto de su perfil: si la parte traía otro por
	# metadato o por override, gana éste (`docs/06` §3).
	part.max_hp = maxf(profile.hp, 1.0)
	part.hp = part.max_hp
	var _discard := part.broken.connect(_on_part_broken)
	var _discard_detached := part.detached.connect(_on_part_detached)


func _ready() -> void:
	_build_material()
	_apply(false, true)


## Evalúa las condiciones del perfil contra [param ctx] y aplica el cambio de
## exposición si lo hubo. Devuelve el estado resultante.
##
## Claves de [param ctx]: `action_state`, `broken_ids`, `structural_broken`,
## `has_target`, `target_position` y `time`.
func evaluate(ctx: Dictionary) -> bool:
	if profile == null or part == null:
		return false
	# Un punto débil roto o que se fue con su parte no vuelve a exponerse nunca.
	if part.is_broken() or part.is_detached():
		_apply(false, false)
		return false

	var require_all := profile.require_all
	var result := require_all
	for condition: int in profile.conditions:
		var met := _condition_met(condition, ctx)
		if require_all:
			result = result and met
			if not result:
				break
		else:
			result = result or met
			if result:
				break
	if profile.conditions.is_empty():
		result = true
	_apply(result, false)
	return _exposed


## `true` si el punto débil está expuesto ahora mismo.
func is_exposed() -> bool:
	return _exposed


## Multiplicador que el arma aplica al daño (`docs/08` §2.7).
func damage_multiplier() -> float:
	return profile.damage_multiplier if profile != null else 1.0


## `true` si el punto débil ya fue destruido.
func is_broken() -> bool:
	return part != null and part.is_broken()


## Id del punto débil.
func weak_point_id() -> StringName:
	return profile.weak_point_id if profile != null else &""


## Colisionador del punto débil: el nodo que entra en el grupo `weak_points` y el
## que devuelve el rayo del arma.
func collider() -> PhysicsBody3D:
	return part.body if part != null else null


## Posición del punto débil en el mundo.
func world_position() -> Vector3:
	return part.world_position() if part != null else Vector3.ZERO


# --------------------------------------------------------------------------
# Internos
# --------------------------------------------------------------------------

## Resuelve una condición suelta contra el contexto.
func _condition_met(condition: int, ctx: Dictionary) -> bool:
	match condition:
		Exposure.ALWAYS:
			return true
		Exposure.WHILE_ATTACK:
			return ATTACK_STATES.has(ctx.get("action_state", &"NONE") as StringName)
		Exposure.AFTER_PARTS:
			return _after_parts_met(ctx)
		Exposure.ANGLE_CONE:
			return _angle_cone_met(ctx)
		Exposure.TIMED:
			if profile.timed_period <= 0.0:
				return false
			var phase := fposmod(float(ctx.get("time", 0.0)), profile.timed_period)
			return phase < profile.timed_period * profile.timed_duty
	return false


## `AFTER_PARTS`: todas las ids declaradas rotas, [member
## WeakPointProfile.after_parts_count] de ellas, o esa cantidad de partes
## estructurales cualesquiera si la lista está vacía (`docs/06` §5).
func _after_parts_met(ctx: Dictionary) -> bool:
	var broken_ids := ctx.get("broken_ids", {}) as Dictionary
	if profile.after_parts_ids.is_empty():
		return int(ctx.get("structural_broken", 0)) >= maxi(profile.after_parts_count, 1)
	var count := 0
	for raw_id: String in profile.after_parts_ids:
		if broken_ids.has(StringName(raw_id)):
			count += 1
	var needed := profile.after_parts_count
	if needed <= 0:
		needed = profile.after_parts_ids.size()
	return count >= needed


## `ANGLE_CONE`: el objetivo cae dentro del cono anclado al hospedador.
func _angle_cone_met(ctx: Dictionary) -> bool:
	if not bool(ctx.get("has_target", false)):
		return false
	var anchor := host if host != null else part
	if anchor == null or anchor.mesh == null or not is_instance_valid(anchor.mesh):
		return false
	var axis := (anchor.mesh.global_transform.basis * profile.cone_axis)
	if axis.is_zero_approx():
		return false
	var to_target := (ctx.get("target_position", Vector3.ZERO) as Vector3) - anchor.world_position()
	if to_target.is_zero_approx():
		return true
	return rad_to_deg(axis.normalized().angle_to(to_target.normalized())) <= profile.cone_half_angle


## Aplica el estado de exposición: capas, emisivo, grupo y hechos del bus.
## [param force] reaplica aunque el estado no haya cambiado (estado inicial).
func _apply(exposed: bool, force: bool) -> void:
	if _applied and exposed == _exposed and not force:
		return
	_applied = true
	_exposed = exposed

	var collision_body := collider()
	if collision_body != null and is_instance_valid(collision_body):
		collision_body.collision_layer = PhysicsLayers.ENEMY_WEAK if exposed \
				else PhysicsLayers.ENEMY_BODY
		collision_body.collision_mask = EXPOSED_MASK if exposed else COVERED_MASK
		if exposed and not collision_body.is_in_group(GROUP):
			collision_body.add_to_group(GROUP)
		elif not exposed and collision_body.is_in_group(GROUP):
			collision_body.remove_from_group(GROUP)

	_pierce_host(exposed)
	_apply_emissive(exposed)
	if not force:
		exposure_changed.emit(weak_point_id(), exposed)
		Events.enemy_weak_point_state.emit(enemy, weak_point_id(), exposed)


## Apaga la capa `enemy_body` del hospedador mientras este punto débil esté
## expuesto, para que el disparo llegue (`WeakPointProfile.pierces_host`).
##
## Sólo actúa si el perfil lo pide. El contador va en un metadato del cuerpo del
## hospedador porque varios puntos débiles comparten hospedador —los tres núcleos
## del Arachnodroid cuelgan del mismo `underbelly`— y la capa tiene que volver
## cuando se cierra el último, no cuando se cierra el primero.
func _pierce_host(exposed: bool) -> void:
	if profile == null or not profile.pierces_host or host == null:
		return
	var host_body := host.body
	if host_body == null or not is_instance_valid(host_body):
		return
	var open := int(host_body.get_meta(PIERCE_META, 0)) + (1 if exposed else -1)
	open = maxi(open, 0)
	host_body.set_meta(PIERCE_META, open)
	if open > 0:
		host_body.collision_layer &= ~PhysicsLayers.ENEMY_BODY
	else:
		host_body.collision_layer |= PhysicsLayers.ENEMY_BODY


## Duplica el material que hay que encender, para que el resto del atlas de
## paleta no se entere (`docs/06` §5). Si la malla ya trae una superficie
## emisiva, se sobreescribe **esa** superficie; si no, se usa un
## `material_override` propio (`docs/05` §9.2).
func _build_material() -> void:
	if part == null or part.mesh == null or part.mesh.mesh == null:
		return
	var mesh_data := part.mesh.mesh
	if part.has_emissive_surface:
		for surface: int in mesh_data.get_surface_count():
			var source := mesh_data.surface_get_material(surface) as BaseMaterial3D
			if source == null or not source.emission_enabled:
				continue
			var copy := source.duplicate() as BaseMaterial3D
			part.mesh.set_surface_override_material(surface, copy)
			_material = copy
			return
	var base := part.mesh.get_active_material(0) as BaseMaterial3D
	var override: BaseMaterial3D = StandardMaterial3D.new()
	if base != null:
		override = base.duplicate() as BaseMaterial3D
	part.mesh.material_override = override
	_material = override


## Enciende o apaga la emisión del punto débil.
func _apply_emissive(exposed: bool) -> void:
	if _material == null or profile == null:
		return
	_material.emission_enabled = true
	_material.emission = profile.emissive_color
	_material.emission_energy_multiplier = profile.emissive_energy if exposed else 0.0


func _on_part_broken(_part_id: StringName) -> void:
	_apply(false, false)
	destroyed.emit(weak_point_id())


func _on_part_detached(_part_id: StringName) -> void:
	_apply(false, false)
