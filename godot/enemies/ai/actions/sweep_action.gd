## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Base de toda acción que resuelve su daño por barrido (`docs/06` §11.3).
##
## Es el tronco común de las ocho acciones ofensivas del Arachnodroid
## (`docs/07` §5) y de las que traigan los enemigos de P3: acá vive el
## `intersect_shape` con sus reglas, y cada acción concreta sólo dice
## [b]dónde[/b] poner el volumen en cada instante sobrescribiendo
## [method _sweep_transform].
##
## [b]Reglas de la resolución[/b] (`docs/06` §11.3):
##
## - Un `PhysicsShapeQueryParameters3D` con la forma del [AttackProfile], la
##   máscara `query_layers` (capas 2 `drone` y 8 `city`) y el enemigo excluido.
##   [b]Ningún `Area3D`[/b].
## - Un mismo collider se daña **una sola vez por ventana activa**, salvo que
##   `damage_per_second` esté puesto, en cuyo caso cada consulta cobra
##   `damage · query_interval`.
## - Contra el dron va `Hull.apply_damage(amount, origen)` —nunca el alias
##   `take_damage` (`docs/09` §2.10)—, que es quien publica
##   `Events.drone_damaged`, más `apply_impulse` recortado a
##   [constant EnemyAction.MAX_IMPULSE].
## - Contra la ciudad, `Building.take_damage(amount, punto)` más
##   [method EnemyAction.notify_city_attack].
##
## [b]Gate de apoyo[/b] (`docs/06` §10.2, `docs/07` §5.4): al decidir sólo se
## exige que la locomoción no esté en `LEAP`/`STAGGER`/`DOWNED`
## ([method locomotion_ready]); las patas se cuentan al entrar en `ACTIVE`
## ([method require_planted]), cuando el `lock_locomotion` del aviso ya las
## plantó. El trote deja exactamente dos patas apoyadas mientras camina, así que
## pedir tres en el `score()` dejaría el pisotón en cero para siempre.
class_name SweepAction extends EnemyAction

## Media longitud del rayo que baja un punto al suelo, en metros.
const GROUND_PROBE: float = 300.0

## Tope de colisiones que devuelve una consulta. Con 16 sobran: el barrido más
## grande del jefe es la esfera de 45 m del EMP y sólo mira la capa 2.
const MAX_RESULTS: int = 16

## Estados de locomoción en los que ninguna acción ofensiva puede empezar.
const BLOCKING_STATES: Array[StringName] = [&"LEAP", &"STAGGER", &"DOWNED"]

var _query_accumulator: float = 0.0
var _hits: Dictionary[int, bool] = {}
var _drone_hits: int = 0
var _building_hits: int = 0
var _damage_dealt: float = 0.0
var _fallback_shape: Shape3D = null
var _beam: MeshInstance3D = null
var _beam_mesh: CylinderMesh = null


# --------------------------------------------------------------------------
# Ciclo de la ventana activa
# --------------------------------------------------------------------------

## Arranca la ventana: nadie recibió daño todavía y se resuelve el primer barrido.
func _on_active_begin() -> void:
	open_window()
	resolve_now()


## Repite la consulta cada `query_interval` mientras dura la ventana.
func _on_active(delta: float) -> void:
	if profile == null or is_aborted():
		return
	_query_accumulator += delta
	var step := query_step()
	while _query_accumulator >= step:
		_query_accumulator -= step
		resolve_now()


## Apaga el aviso si la acción se corta a mitad del windup.
func _on_interrupt() -> void:
	var node := telegraph_node()
	if node != null:
		node.cancel()


# --------------------------------------------------------------------------
# Resolución (`docs/06` §11.3)
# --------------------------------------------------------------------------

## Deja la ventana limpia: ningún collider dañado y el acumulador a cero.
func open_window() -> void:
	_hits.clear()
	_drone_hits = 0
	_building_hits = 0
	_damage_dealt = 0.0
	_query_accumulator = 0.0


## Un barrido con el volumen que devuelve [method _sweep_transform]. Devuelve
## cuántos colliders nuevos se dañaron.
func resolve_now() -> int:
	return resolve_at(_sweep_transform(), _sweep_shape())


## Un barrido con [param xform] y [param shape] explícitos. Es lo que usan las
## acciones que mueven el volumen a mano (el barrido de pata y el haz).
func resolve_at(xform: Transform3D, shape: Shape3D) -> int:
	var space := space_state()
	if space == null or profile == null or shape == null:
		return 0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = xform
	params.collision_mask = profile.query_layers
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = self_exclusions()

	var origin := _damage_origin(xform)
	var touched := 0
	for hit: Dictionary in space.intersect_shape(params, MAX_RESULTS):
		var collider := hit.get("collider", null) as Node3D
		if collider == null:
			continue
		var key := collider.get_instance_id()
		if _hits.has(key) and not profile.damage_per_second:
			continue
		_hits[key] = true
		if _hit_drone(collider, origin):
			_drone_hits += 1
			touched += 1
		elif _hit_building(collider, origin):
			_building_hits += 1
			touched += 1
	return touched


## Colisiones dañadas en la última ventana activa: dron y edificios.
func last_hits() -> Vector2i:
	return Vector2i(_drone_hits, _building_hits)


## Daño total repartido en la última ventana activa.
func damage_dealt() -> float:
	return _damage_dealt


## Intervalo entre consultas, en segundos.
func query_step() -> float:
	return maxf(profile.query_interval, 0.01) if profile != null else 0.05


# --------------------------------------------------------------------------
# Ganchos de la coreografía
# --------------------------------------------------------------------------

## Dónde está el volumen de resolución ahora mismo. Por defecto, centrado en el
## punto apuntado y levantado media altura del volumen, que es lo que hace el
## pisotón: el pie cae al suelo, no a la altura a la que vuela el dron.
func _sweep_transform() -> Transform3D:
	var point := aim_point()
	return Transform3D(Basis.IDENTITY, point + Vector3.UP * shape_height() * 0.5)


## Forma del barrido: la del perfil, o la de reserva de la acción concreta.
func _sweep_shape() -> Shape3D:
	if profile != null and profile.query_shape != null:
		return profile.query_shape
	if _fallback_shape == null:
		_fallback_shape = _build_fallback_shape()
	return _fallback_shape


## Forma de reserva si el `.tres` no trae ninguna. Las acciones concretas la
## sobrescriben; la base da una esfera de 6 m.
func _build_fallback_shape() -> Shape3D:
	var sphere := SphereShape3D.new()
	sphere.radius = 6.0
	return sphere


## Punto de origen del daño: el que viaja en `Events.drone_damaged` y el que
## decide la dirección del impulso. Por defecto, el centro del volumen.
func _damage_origin(xform: Transform3D) -> Vector3:
	return xform.origin


# --------------------------------------------------------------------------
# Daño
# --------------------------------------------------------------------------

## Daña al dron por *duck typing*: el casco es el hijo `Hull` del cuerpo rígido
## de la capa 2 (`docs/09` §2). Devuelve `true` si el collider era el dron.
func _hit_drone(collider: Node3D, origin: Vector3) -> bool:
	var object := collider as CollisionObject3D
	if object == null or object.collision_layer & PhysicsLayers.DRONE == 0:
		return false
	_apply_drone_effect(collider, origin)
	return true


## Efecto sobre el dron. La base descuenta casco e impulsa; el EMP lo sobrescribe
## para drenar la batería en vez de dañar (`docs/07` §5.8).
func _apply_drone_effect(collider: Node3D, origin: Vector3) -> void:
	if profile.damage_drone > 0.0:
		var hull := find_hull(collider)
		if hull != null:
			var amount := damage_amount(profile.damage_drone)
			hull.call(&"apply_damage", amount, origin)
			_damage_dealt += amount
	if profile.impulse_drone > 0.0:
		var body := collider as RigidBody3D
		if body != null:
			# El recorte a 120 N·s es obligatorio: sin él Jolt manda el dron
			# fuera del mundo (`docs/06` §11.3).
			body.apply_impulse(_impulse_direction(body, origin)
					* minf(profile.impulse_drone, MAX_IMPULSE))


## Dirección del impulso al dron. Por defecto radial hacia afuera desde el punto
## de impacto; `leg_sweep` la sobrescribe por la tangencial del arco.
func _impulse_direction(body: Node3D, origin: Vector3) -> Vector3:
	var direction := body.global_position - origin
	if direction.is_zero_approx():
		return Vector3.UP
	return direction.normalized()


## Daña un edificio de la capa 8. Devuelve `true` si el collider lo aceptó.
func _hit_building(collider: Node3D, origin: Vector3) -> bool:
	if profile.damage_building <= 0.0:
		return false
	var target := find_building(collider)
	if target == null:
		return false
	var amount := damage_amount(profile.damage_building)
	var _applied: Variant = target.call(&"take_damage", amount, origin)
	_damage_dealt += amount
	notify_city_attack()
	return true


## Daño de una consulta: el nominal, o proporcional al intervalo si el ataque es
## continuo (`docs/06` §11.3).
func damage_amount(nominal: float) -> float:
	if profile != null and profile.damage_per_second:
		return nominal * query_step()
	return nominal


## Casco del dron: el hijo `Hull`, o el propio collider si expone el método.
func find_hull(collider: Node3D) -> Node:
	var hull := collider.get_node_or_null(^"Hull")
	if hull != null and hull.has_method(&"apply_damage"):
		return hull
	if collider.has_method(&"apply_damage"):
		return collider
	return null


## Batería del dron: el hijo `EnergySystem`, buscado por nombre y por método.
func find_energy(collider: Node3D) -> Node:
	for candidate_name: StringName in [&"EnergySystem", &"Energy"]:
		var found := collider.get_node_or_null(NodePath(String(candidate_name)))
		if found != null and found.has_method(&"apply_emp"):
			return found
	for child: Node in collider.get_children():
		if child.has_method(&"apply_emp"):
			return child
	return null


## Edificio del collider: él mismo o el primer ancestro con `take_damage`. Los
## colisionadores de `city/pieces` cuelgan del [Building], no son el [Building].
func find_building(collider: Node3D) -> Node:
	var node: Node = collider
	var depth := 0
	while node != null and depth < 3:
		if node.has_method(&"take_damage"):
			return node
		node = node.get_parent()
		depth += 1
	return null


# --------------------------------------------------------------------------
# Contexto, apuntado y apoyo
# --------------------------------------------------------------------------

## Contexto de la última decisión del cerebro, o uno recién armado.
func context() -> Dictionary:
	var host := owner_enemy()
	if host == null or host.brain == null:
		return {}
	if host.brain.has_method(&"last_context"):
		var stored := host.brain.call(&"last_context") as Dictionary
		if not stored.is_empty():
			return stored
	if host.brain.has_method(&"build_context"):
		return host.brain.call(&"build_context") as Dictionary
	return {}


## Punto al que apunta la acción, [b]bajado al suelo[/b].
##
## El golpe cae al piso, no a la altura a la que vuela el dron: con el volumen
## colgado de la posición creída —que trae el ruido de la percepción, σ 2 m
## también en Y— la mitad de los pisotones pasaría por debajo del dron sin
## tocarlo. El aviso queda además donde el jugador lo ve, que es el suelo.
func aim_point() -> Vector3:
	var point := target_point(context())
	var host := owner_enemy()
	if point.is_zero_approx() and host != null:
		point = host.global_position
	return ground_snap(point)


## Baja [param point] al suelo que tiene debajo, con la máscara `world | city`.
func ground_snap(point: Vector3) -> Vector3:
	var space := space_state()
	if space == null:
		return point
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * GROUND_PROBE,
			point + Vector3.DOWN * GROUND_PROBE, PhysicsLayers.QUERY_FOOT)
	query.collide_with_areas = false
	query.exclude = self_exclusions()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return point
	return hit["position"] as Vector3


## Rig de patas del enemigo, o `null`.
func rig() -> ProceduralLegRig:
	var host := owner_enemy()
	if host == null:
		return null
	return host.locomotion as ProceduralLegRig


## Nodo `AudioRig` del enemigo, o `null`.
func audio_rig() -> AudioRig:
	var host := owner_enemy()
	if host == null:
		return null
	return host.get_node_or_null(^"AudioRig") as AudioRig


## Altura del volumen de resolución, para centrarlo sobre el suelo.
func shape_height() -> float:
	var shape := _sweep_shape()
	var cylinder := shape as CylinderShape3D
	if cylinder != null:
		return cylinder.height
	var capsule := shape as CapsuleShape3D
	if capsule != null:
		return capsule.height
	var box := shape as BoxShape3D
	if box != null:
		return box.size.y
	var sphere := shape as SphereShape3D
	if sphere != null:
		return sphere.radius * 2.0
	return 6.0


## Radio del volumen de resolución, que es el que tiene que marcar el aviso.
func shape_radius() -> float:
	var shape := _sweep_shape()
	var cylinder := shape as CylinderShape3D
	if cylinder != null:
		return cylinder.radius
	var sphere := shape as SphereShape3D
	if sphere != null:
		return sphere.radius
	var capsule := shape as CapsuleShape3D
	if capsule != null:
		return capsule.radius
	var box := shape as BoxShape3D
	if box != null:
		return maxf(box.size.x, box.size.z) * 0.5
	return 6.0


# --------------------------------------------------------------------------
# Haz visible (opcional: sólo lo usan `head_laser` y `siege_beam`)
# --------------------------------------------------------------------------

## Deja listo el cilindro del haz: [param radius] metros de radio y
## [param color] aditivo.
##
## El aviso tiene sus tres canales, pero la [b]ventana activa[/b] de un haz
## continuo no tenía ninguno: el daño ocurría sin nada en pantalla. Esto es el
## mínimo legible —un cilindro sin sombreado y aditivo, sin sombras— hasta que
## WP-26 y WP-27 traigan el haz de verdad con sus partículas.
##
## El nodo cuelga del enemigo con `top_level`, no de la acción: una acción es un
## [Node] pelado y un [MeshInstance3D] necesita un padre 3D con transformada
## propia para no heredar la pose del coloso.
func configure_beam(node_name: StringName, radius: float, color: Color) -> void:
	if _beam != null and is_instance_valid(_beam):
		return
	var host := owner_enemy()
	if host == null:
		return
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = radius
	_beam_mesh.bottom_radius = radius
	_beam_mesh.height = 1.0
	_beam_mesh.radial_segments = 8
	_beam_mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	_beam_mesh.material = material

	_beam = MeshInstance3D.new()
	_beam.name = String(node_name)
	_beam.mesh = _beam_mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_beam.top_level = true
	_beam.visible = false
	host.add_child(_beam)


## Estira el haz de [param from] a [param to] y lo enciende. El eje del
## [CylinderMesh] es `Y`, así que la base lleva `Y` sobre la dirección y el
## centro queda a media longitud.
func update_beam(from: Vector3, to: Vector3) -> void:
	if _beam == null or not is_instance_valid(_beam):
		return
	var delta := to - from
	var length := delta.length()
	if length < 0.01:
		_beam.visible = false
		return
	var up := delta / length
	var reference := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := reference.cross(up).normalized()
	_beam_mesh.height = length
	_beam.global_transform = Transform3D(
			Basis(right, up, right.cross(up)).orthonormalized(), from + up * length * 0.5)
	_beam.visible = true


## Apaga el haz. Es idempotente: lo llaman el fin, la interrupción y la salida
## del árbol.
func hide_beam() -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.visible = false


## Nodo del haz, o `null` si la acción no usa ninguno. Lo lee
## `arachnodroid_check` para comprobar que se enciende en `ACTIVE` y se apaga
## fuera.
func beam_node() -> MeshInstance3D:
	return _beam


## `true` si la locomoción deja empezar un ataque: ni saltando, ni tambaleando,
## ni caído (`docs/06` §10.2, regla del gate de apoyo).
func locomotion_ready() -> bool:
	var host := owner_enemy()
	if host == null:
		return true
	return not BLOCKING_STATES.has(host.locomotion_state())


## Patas apoyadas ahora mismo.
func planted_legs() -> int:
	var leg_rig := rig()
	if leg_rig == null:
		# Sin rig —escenas sintéticas de los checks— el gate no puede opinar.
		return 4
	return leg_rig.planted_count()


## Gate de apoyo al entrar en `ACTIVE`: si no hay [param minimum] patas
## apoyadas, la acción se [method EnemyAction.abort] y el golpe se va al aire.
## Devuelve `true` si el ataque puede seguir.
func require_planted(minimum: int) -> bool:
	if planted_legs() >= minimum:
		return true
	abort()
	return false
