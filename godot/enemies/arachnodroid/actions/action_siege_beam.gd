## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `siege_beam` — el reloj de la ciudad (`docs/07` §5.7).
##
## [b]Telegrafía 1.8 s[/b]: el jefe [b]se ancla[/b] —las cuatro patas plantadas,
## `lock_locomotion = true`—, los respiraderos se abren en naranja, una
## [b]columna vertical de luz[/b] marca el edificio elegido y
## [method Building.mark_under_siege] lo mete en el grupo
## `buildings_under_siege`, que es de donde lo saca el marcador del `CombatHUD`
## (`docs/12`) y lo que hace que `EnemyFSM._pick_city_target` no cambie de
## objetivo a mitad del haz.
##
## [b]Activo 4.0 s[/b]: `Building.take_damage(700 · delta, punto)` → 2 800 de
## daño, suficiente para llevar un bloque bajo a ruinas y una torre a `DAMAGED`
## (`docs/10` §5). La resolución es la de `docs/06` §11.3: un `intersect_shape`
## con la cápsula de r 2.5 cada `query_interval` más un `intersect_ray` por tick
## para el punto de contacto visual.
##
## [b]Contramedida[/b]: es la ventana principal de ataque del combate —5.8 s con
## el cuerpo inmóvil y las rodillas quietas— o destruir el edificio marcado antes
## de que termine el haz, que desperdicia el ataque entero: sólo reapunta tras el
## enfriamiento.
class_name ActionSiegeBeam extends SweepAction

## Tiempo sin dañar la ciudad a partir del cual el asedio vale 1, en segundos
## (`docs/06` §10.2, fila `siege_beam`).
const PRESSURE_WINDOW: float = 25.0

## Edificios en el cono frontal con los que el ataque llega a su peso máximo.
const CONE_REFERENCE: float = 4.0

## Radio de la cápsula si el perfil no trae forma, en metros.
const FALLBACK_RADIUS: float = 2.5

## Altura sobre la base del edificio a la que apunta el haz, como fracción de su
## altura: el centroide, que es lo que pide `docs/07` §5.7.
const TARGET_HEIGHT_RATIO: float = 0.5

## Radio del cilindro del haz visible, en metros. Más gordo que el del láser
## —esto derriba edificios, no persigue drones— y algo menor que la cápsula de
## r 2.5 que resuelve el daño.
const BEAM_RADIUS: float = 1.5

## Color aditivo del haz: el ámbar-naranja de los respiraderos de la carcasa.
const BEAM_COLOR: Color = Color(1.0, 0.55, 0.15, 0.85)

var _target: Node3D = null
var _aim: Vector3 = Vector3.ZERO
var _contact: Vector3 = Vector3.ZERO
var _length: float = 1.0


## Presión sobre la ciudad: sube mientras el jugador no molesta (`docs/06` §10.2).
func score(ctx: Dictionary) -> float:
	if profile == null or not locomotion_ready():
		return 0.0
	if not bool(ctx.get(&"has_city_target", false)):
		return 0.0
	var idle := clampf(float(ctx.get(&"time_since_city_attack", 0.0)) / PRESSURE_WINDOW,
			0.0, 1.0)
	# Rampa de `docs/06` §10.2: 0.10 sin tiempo y 1.0 con la ventana entera.
	var pressure := lerpf(0.10, 1.0, idle)
	var cone := clampf(float(ctx.get(&"buildings_in_cone", 0)) / CONE_REFERENCE, 0.0, 1.0)
	# Sin nada en el cono, el edificio elegido igual cuenta: el jefe gira hacia
	# él durante el aviso. Un suelo de 0.35 evita que el asedio muera en un
	# barrio disperso, que es justo donde la ciudad más lo sufre.
	var visibility := maxf(cone, 0.35)
	var bias := clampf(float(ctx.get(&"city_bias", 1.0)), 0.0, 1.0)
	return ActionScore.clamp01(pressure * visibility * bias)


# --------------------------------------------------------------------------
# Coreografía
# --------------------------------------------------------------------------

## Ancla las patas, elige el edificio y levanta la columna de luz.
func _on_telegraph() -> void:
	_release_siege()
	_target = context().get(&"city_target", null) as Node3D
	_aim = _aim_at(_target)
	if _target != null and _target.has_method(&"mark_under_siege"):
		_target.call(&"mark_under_siege", true)
	var node := telegraph_node()
	if node != null:
		node.set_radius(shape_radius())
		node.set_guide_target(_ground(_aim))
	_anchor_legs()


## Gira el cuerpo hacia el edificio mientras carga: el haz sale de la cabeza y
## sin encararlo el cuerpo taparía su propio disparo.
func _on_telegraph_tick(delta: float) -> void:
	var host := owner_enemy()
	if host == null or _target == null or not is_instance_valid(_target):
		return
	host.face_toward(_target.global_position, delta)
	_anchor_legs()


func _on_active_begin() -> void:
	_aim = _aim_at(_target)
	open_window()
	configure_beam(&"SiegeBeam", BEAM_RADIUS, BEAM_COLOR)
	_track()
	update_beam(_head_position(), _contact)
	var _touched := resolve_at(_sweep_transform(), _sweep_shape())


func _on_active(delta: float) -> void:
	_track()
	# El haz se redibuja cada tick: el edificio puede derrumbarse a mitad de la
	# ráfaga y el punto de contacto salta.
	update_beam(_head_position(), _contact)
	super._on_active(delta)


## Se apaga el haz al cerrarse la ventana activa; el asedio sigue marcado hasta
## que termine la recuperación.
func _on_active_end() -> void:
	hide_beam()


func _on_finish() -> void:
	hide_beam()
	_release_siege()


func _on_interrupt() -> void:
	super._on_interrupt()
	hide_beam()
	_release_siege()


func _exit_tree() -> void:
	# Un edificio marcado que nadie desmarca se queda de objetivo para siempre.
	hide_beam()
	_release_siege()


## Edificio que está recibiendo el haz, o `null`.
func besieged() -> Node3D:
	return _target


## Punto de contacto visual del haz.
func contact_point() -> Vector3:
	return _contact


# --------------------------------------------------------------------------
# Volumen
# --------------------------------------------------------------------------

func _sweep_transform() -> Transform3D:
	var origin := _head_position()
	var direction := _direction()
	return Transform3D(_basis_along(direction), origin + direction * _length * 0.5)


func _build_fallback_shape() -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = FALLBACK_RADIUS
	capsule.height = 40.0
	return capsule


func _damage_origin(_xform: Transform3D) -> Vector3:
	return _contact


## Recalcula largo y punto de contacto con el `intersect_ray` de `docs/06` §11.3.
func _track() -> void:
	var origin := _head_position()
	_length = maxf(origin.distance_to(_aim), 1.0)
	_contact = _aim
	var space := space_state()
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, _aim,
			profile.query_layers if profile != null else PhysicsLayers.QUERY_SWEEP)
	query.collide_with_areas = false
	query.exclude = self_exclusions()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	_contact = hit["position"] as Vector3
	_length = maxf(origin.distance_to(_contact), 1.0)


## Centroide del edificio elegido (`docs/07` §5.7).
func _aim_at(building: Node3D) -> Vector3:
	if building == null or not is_instance_valid(building):
		var ctx := context()
		return ctx.get(&"city_position", Vector3.ZERO) as Vector3
	var height := 12.0
	if building.has_method(&"get_height"):
		height = float(building.call(&"get_height"))
	return building.global_position + Vector3.UP * height * TARGET_HEIGHT_RATIO


## Base del edificio, donde se planta la columna del aviso.
func _ground(point: Vector3) -> Vector3:
	if _target != null and is_instance_valid(_target):
		return _target.global_position
	return ground_snap(point)


## Dirección cabeza → objetivo.
func _direction() -> Vector3:
	var to_target := _aim - _head_position()
	if to_target.is_zero_approx():
		return -owner_enemy().global_basis.z
	return to_target.normalized()


## Origen del haz.
func _head_position() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.ZERO
	for part_name: StringName in [&"wp_head_visor", &"hull"]:
		var part := host.get_part(part_name)
		if part != null and part.mesh != null and is_instance_valid(part.mesh):
			return part.mesh.global_position
	return host.global_position


## Base con `Y` sobre [param direction], que es la que necesita la cápsula.
func _basis_along(direction: Vector3) -> Basis:
	var up := direction.normalized()
	var reference := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := reference.cross(up).normalized()
	return Basis(right, up, right.cross(up)).orthonormalized()


## Las cuatro patas al suelo: el ancla de `docs/07` §5.7. `lock_locomotion` ya
## impide avanzar; esto devuelve al ciclo cualquier pata que otra acción hubiera
## dejado levantada.
func _anchor_legs() -> void:
	var leg_rig := rig()
	if leg_rig != null:
		leg_rig.release_all_legs()


## Saca el edificio del grupo `buildings_under_siege`.
func _release_siege() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		return
	if _target.has_method(&"mark_under_siege"):
		_target.call(&"mark_under_siege", false)
	_target = null
