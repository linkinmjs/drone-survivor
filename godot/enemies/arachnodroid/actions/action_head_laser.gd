## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `head_laser` — la trampa del visor (`docs/07` §5.6).
##
## [b]Telegrafía 1.6 s[/b]: el visor carga de cian a blanco y sale una línea guía
## fina hacia `believed_position` — [b]con el ruido de la percepción[/b], así que
## contra un dron en movimiento apunta mal a propósito— más el silbido
## ascendente. [b]Activo 2.0 s[/b]: el haz barre hacia la posición creída a
## [constant SWEEP_RATE] °/s, con un [CapsuleShape3D] de r 1.2 a lo largo y
## `damage_per_second`: 8/s al dron y 120/s a lo que toque de la ciudad.
##
## [b]La clave[/b] (`docs/07` §4 y §5.6): mientras dura, `wp_head_visor` está
## expuesto. No hay código para eso acá y es correcto que no lo haya: el punto
## débil lleva `Exposure.WHILE_ATTACK`, que es cierto en `TELEGRAPH` y en
## `ACTIVE` (`docs/06` §5), de modo que los 3.6 s de este ataque son la ventana
## más larga que el jugador consigue sobre el visor. Es el ataque que [i]quiere[/i]
## provocar.
##
## [b]Contramedida[/b]: cortar la línea de visión detrás de un edificio, u
## orbitar más rápido que [constant SWEEP_RATE] °/s a esa distancia. Lo segundo
## sale solo del giro limitado del haz; lo primero, de que el barrido nace en la
## cabeza y el [CapsuleShape3D] se corta en el primer edificio que toque.
class_name ActionHeadLaser extends SweepAction

## Velocidad a la que el haz gira hacia la creencia, en grados por segundo.
const SWEEP_RATE: float = 35.0

## Distancia a la que el láser vale 1, en metros (`docs/06` §10.2).
const SWEET_SPOT: float = 45.0

## Alcance del haz si el perfil no declara `max_range`, en metros.
const FALLBACK_RANGE: float = 90.0

## Radio de la cápsula si el perfil no trae forma, en metros.
const FALLBACK_RADIUS: float = 1.2

## Parte que tiene que estar sana para poder disparar.
const VISOR_PART: StringName = &"wp_head_visor"

## Radio del cilindro del haz visible, en metros. Es el doble del radio de la
## cápsula que resuelve el daño (1.2 m) dividido por cinco: el haz se ve fino y
## el volumen que mata es más generoso, que es lo que se quiere.
## Radio **visual** del haz, en metros.
##
## **0.25 → 0.6 (WP-26).** El volumen de daño es una [CapsuleShape3D] de r 1.2 m
## (`docs/07` §5.6) y **no se toca**; lo que se corrige es que el haz se veía casi
## cinco veces más fino que lo que mataba. Con 0.6 m y el fresnel de
## `vfx/beam.gdshader` —que engorda el borde de silueta— el haz lee alrededor de
## 1 m, o sea cerca del volumen real sin prometer más alcance del que tiene. Si en
## el checkpoint 4 el láser se siente injusto, la palanca es ésta y no la cápsula.
const BEAM_RADIUS: float = 0.6

## Color aditivo del haz: blanco-cian, el mismo al que carga el visor.
const BEAM_COLOR: Color = Color(0.70, 0.95, 1.0, 0.85)

var _direction: Vector3 = Vector3.FORWARD
var _length: float = FALLBACK_RANGE
var _contact: Vector3 = Vector3.ZERO


## Distancia media, con visión y el visor entero (`docs/06` §10.2).
func score(ctx: Dictionary) -> float:
	if profile == null or not locomotion_ready():
		return 0.0
	if not bool(ctx.get(&"has_los", false)):
		return 0.0
	if not _visor_intact():
		return 0.0
	var distance := target_distance(ctx)
	var base := ActionScore.bell(distance, SWEET_SPOT, maxf(profile.max_range, 1.0))
	var confidence := clampf(float(ctx.get(&"confidence", 0.0)), 0.0, 1.0)
	return ActionScore.clamp01(base * confidence)


# --------------------------------------------------------------------------
# Coreografía
# --------------------------------------------------------------------------

## El haz arranca apuntando adonde mira la cabeza y la línea guía marca la
## creencia: la diferencia entre las dos es el error que el jugador puede leer.
func _on_telegraph() -> void:
	_direction = _facing()
	_aim_guide()


## El cuerpo encara mientras carga.
##
## `docs/06` §11.1 lo autoriza explícitamente: `lock_locomotion` fuerza la
## locomoción a `IDLE` «o `TURN` si el ataque necesita apuntar». Sin esto el haz
## arrancaría mirando adonde el jefe venía caminando y, a 35 °/s, gastaría los
## 2.0 s de ventana girando sin llegar nunca al dron.
func _on_telegraph_tick(delta: float) -> void:
	var host := owner_enemy()
	if host != null:
		host.face_toward(target_point(context()), delta)
	_aim_guide()


func _on_active_begin() -> void:
	open_window()
	configure_beam(&"HeadLaserBeam", BEAM_RADIUS, BEAM_COLOR)
	_track(0.0)
	update_beam(_head_position(), _contact)
	var _touched := resolve_at(_sweep_transform(), _sweep_shape())


## Gira el haz hacia la creencia a [constant SWEEP_RATE] °/s y resuelve.
func _on_active(delta: float) -> void:
	_track(delta)
	# El haz se redibuja **cada tick**, no cada `query_interval`: la consulta
	# puede ir a 20 Hz, pero lo que el jugador ve tiene que seguir al punto de
	# contacto sin escalones.
	update_beam(_head_position(), _contact)
	super._on_active(delta)


## Se apaga el haz al cerrarse la ventana activa.
func _on_active_end() -> void:
	hide_beam()


func _on_interrupt() -> void:
	super._on_interrupt()
	hide_beam()


func _exit_tree() -> void:
	hide_beam()


## Punto de contacto visual del haz, del `intersect_ray` por tick (`docs/06` §11.3).
func contact_point() -> Vector3:
	return _contact


## Dirección actual del haz.
func beam_direction() -> Vector3:
	return _direction


# --------------------------------------------------------------------------
# Volumen
# --------------------------------------------------------------------------

## La cápsula se tumba a lo largo del haz: su eje es `Y` en Godot, así que la
## base lleva `Y` sobre la dirección y el centro queda a media longitud.
func _sweep_transform() -> Transform3D:
	var origin := _head_position() + _direction * _length * 0.5
	return Transform3D(_basis_along(_direction), origin)


func _build_fallback_shape() -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = FALLBACK_RADIUS
	capsule.height = FALLBACK_RANGE
	return capsule


## El daño se origina en el punto de contacto, no en el centro de la cápsula:
## es lo que hace que el empujón y la sacudida vengan de donde arde el haz.
func _damage_origin(_xform: Transform3D) -> Vector3:
	return _contact


## Gira el haz y recalcula su largo con el `intersect_ray` del punto de contacto.
func _track(delta: float) -> void:
	var desired := _direction_to_target()
	var limit := deg_to_rad(SWEEP_RATE) * delta
	var angle := _direction.angle_to(desired)
	if angle > limit and limit > 0.0:
		var axis := _direction.cross(desired)
		if not axis.is_zero_approx():
			_direction = _direction.rotated(axis.normalized(), limit).normalized()
	else:
		_direction = desired
	_length = _range()
	_contact = _head_position() + _direction * _length
	var space := space_state()
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(_head_position(), _contact,
			profile.query_layers if profile != null else PhysicsLayers.QUERY_SWEEP)
	query.collide_with_areas = false
	query.exclude = self_exclusions()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	_contact = hit["position"] as Vector3
	# El haz se corta donde toca: sin esto la cápsula seguiría atravesando el
	# edificio y cobraría 120/s a todo lo que hubiera detrás.
	_length = maxf(_head_position().distance_to(_contact), 1.0)


## Longitud nominal del haz.
func _range() -> float:
	if profile != null and profile.max_range > 0.0:
		return profile.max_range
	return FALLBACK_RANGE


## Dirección del haz cuando el ataque empieza: adonde mira el cuerpo.
func _facing() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.FORWARD
	var forward := -host.global_basis.z
	return forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD


## Dirección cabeza → posición creída.
func _direction_to_target() -> Vector3:
	var to_target := target_point(context()) - _head_position()
	if to_target.is_zero_approx():
		return _direction
	return to_target.normalized()


## Origen del haz: el visor, o el casco si ya no está.
func _head_position() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.ZERO
	for part_name: StringName in [VISOR_PART, &"hull"]:
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


## Le pasa al aviso la línea guía hacia la creencia.
func _aim_guide() -> void:
	var node := telegraph_node()
	if node == null:
		return
	node.set_guide_target(target_point(context()))


## `true` si el visor sigue entero: con él roto el láser no puede apuntar
## (`docs/06` §10.2, modulador «visor intacto»).
func _visor_intact() -> bool:
	var host := owner_enemy()
	if host == null:
		return true
	var part := host.get_part(VISOR_PART)
	if part == null:
		return true
	return not (part.is_broken() or part.is_detached())
