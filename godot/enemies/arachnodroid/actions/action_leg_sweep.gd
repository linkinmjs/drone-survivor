## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `leg_sweep` — limpiar la media distancia (`docs/07` §5.5).
##
## [b]Telegrafía 0.9 s[/b]: la pata del lado del dron se retrae
## [constant RETRACT_DEGREES]° (canal de postura) con el gruñido grave de servo y
## la luz de carga. [b]Activo 0.5 s[/b]: la tibia barre un arco de
## [constant SWEEP_DEGREES]° y el volumen —un [BoxShape3D] de 14 × 4 × 3 m— se
## reposiciona sobre ese arco [b]cada `query_interval`[/b] (0.05 s), que es lo
## que convierte un barrido continuo en diez consultas discretas sin agujeros.
##
## [b]Daño[/b]: 60 al casco más 40 N·s [b]tangenciales[/b]: el dron sale
## despedido en el sentido del barrido, no hacia afuera como en el pisotón. Es la
## diferencia que hace legible el golpe —te lleva por delante— y la que obliga a
## sobrescribir [method SweepAction._impulse_direction].
##
## [b]Contramedida[/b] (`docs/07` §5.5): subir por encima de 18 m, o meterse
## dentro del radio de barrido (< 8 m del cuerpo), donde el arco ya pasó. Las dos
## salen solas de la geometría: la caja tiene 4 m de alto y nace a
## [constant INNER_REACH] m del cuerpo.
class_name ActionLegSweep extends SweepAction

## Arco que barre la tibia, en grados (`docs/07` §5.5).
const SWEEP_DEGREES: float = 160.0

## Retracción de la pata durante el aviso, en grados.
const RETRACT_DEGREES: float = 60.0

## Distancia del cuerpo a la que arranca la caja, en metros: por dentro de eso
## el arco ya pasó.
const INNER_REACH: float = 1.0

## Altura del centro de la caja sobre el suelo, en metros.
const SWEEP_HEIGHT: float = 2.0

## Distancia a la que el barrido vale 1, en metros.
const SWEET_SPOT: float = 14.0

## Altura del dron por encima de la cual el barrido ya no llega, en metros.
const HEIGHT_LIMIT: float = 18.0

## Patas que tienen que quedar apoyadas además de la que actúa.
##
## **2 → 1 (WP-23).** `require_planted()` compara contra `planted_count()`, que
## es el total de patas que **sostienen** el cuerpo, y el trote sostiene con dos:
## al levantar una para el golpe queda una sola, así que el gate no se podía
## cumplir **ni con las cuatro patas sanas**. Medido en una pelea completa: 5 de 6
## pisotones, 6 de 7 barridos y todos los saltos abortados, y **cero** daño al
## casco en trece minutos de combate — el jugador era invulnerable y los pasos 8 y
## 12 del smoke test de `docs/15` §6 no se podían ejecutar. Con 1 el golpe exige
## apoyo real —dos patas en el suelo contando la que actúa— y deja de dispararse
## sólo cuando el jefe está caído, que es lo que `docs/06` §10.2 quiere decir.
## **Y 1 → 0 (segunda medición).** Con una rodilla rota el rig queda en trípode
## y con dos en arrastre: `planted_count()` vale 1 —o 0 durante el tranco— y
## levantar la pata que golpea lo deja en cero, así que el gate seguía abortando
## 5 de cada 6 desde P2. El filtro que de verdad importa es `locomotion_ready()`,
## que ya rechaza `LEAP`, `STAGGER` y `DOWNED` al puntuar (`docs/06` §10.2): con
## el modelo de «rodilla rota = pata entera» de `docs/07` §15 #11, exigir apoyo
## además de eso es exigir un trípode que el jefe no vuelve a tener nunca.
const MIN_SUPPORT: int = 0

## Medidas de la caja si el perfil no trae forma, en metros.
const FALLBACK_SIZE: Vector3 = Vector3(14.0, 4.0, 3.0)

var _base_direction: Vector3 = Vector3.FORWARD
var _angle: float = 0.0
var _elapsed_active: float = 0.0
var _leg_index: int = -1
var _ground_y: float = 0.0


## Media distancia, dron bajo y creencia firme.
func score(ctx: Dictionary) -> float:
	if profile == null or not locomotion_ready():
		return 0.0
	var distance := target_distance(ctx)
	var base := ActionScore.bell(distance, SWEET_SPOT, maxf(profile.max_range, 1.0))
	var height := float(ctx.get(&"drone_height", 0.0))
	var low := 1.0 - clampf(height / HEIGHT_LIMIT, 0.0, 1.0)
	var confidence := clampf(float(ctx.get(&"confidence", 0.0)), 0.0, 1.0)
	return ActionScore.clamp01(base * low * confidence)


# --------------------------------------------------------------------------
# Coreografía
# --------------------------------------------------------------------------

## La pata se retrae y el aviso marca el alcance del arco.
func _on_telegraph() -> void:
	_base_direction = _direction_to_target()
	_ground_y = aim_point().y
	_leg_index = _pick_leg()
	_retract_leg()
	var node := telegraph_node()
	if node != null:
		node.set_radius(_reach())
		node.set_ground_point(_ground_point())


func _on_telegraph_tick(_delta: float) -> void:
	# La pata sigue apuntando mientras el cuerpo gira: el barrido arranca donde
	# el jugador ve la tibia cargada, no donde estaba al empezar el aviso.
	_base_direction = _direction_to_target()
	_retract_leg()
	var node := telegraph_node()
	if node != null:
		node.set_ground_point(_ground_point())


## Arranca el arco desde el extremo, si hay apoyo suficiente.
func _on_active_begin() -> void:
	_elapsed_active = 0.0
	_angle = -deg_to_rad(SWEEP_DEGREES) * 0.5
	if not require_planted(MIN_SUPPORT):
		_release_leg()
		return
	super._on_active_begin()


## Reposiciona la caja sobre el arco en cada consulta.
func _on_active(delta: float) -> void:
	if profile == null or is_aborted():
		return
	var span := maxf(active_seconds(), 0.01)
	_elapsed_active += delta
	var ratio := clampf(_elapsed_active / span, 0.0, 1.0)
	_angle = deg_to_rad(SWEEP_DEGREES) * (ratio - 0.5)
	var leg_rig := rig()
	if leg_rig != null and _leg_index >= 0 and leg_rig.is_leg_raised(_leg_index):
		leg_rig.move_raised_leg(_leg_index, _box_origin())
	super._on_active(delta)


func _on_recover() -> void:
	_release_leg()


func _on_finish() -> void:
	_release_leg()


func _on_interrupt() -> void:
	super._on_interrupt()
	_release_leg()


## Ángulo actual del arco, en grados desde el centro. Lo lee el check.
func sweep_angle() -> float:
	return rad_to_deg(_angle)


# --------------------------------------------------------------------------
# Volumen
# --------------------------------------------------------------------------

## La caja va tumbada sobre el arco: su eje largo (X, 14 m) apunta hacia afuera
## y el centro queda a media caja del cuerpo.
func _sweep_transform() -> Transform3D:
	var direction := _swept_direction()
	var basis := Basis(direction, Vector3.UP, direction.cross(Vector3.UP).normalized())
	return Transform3D(basis.orthonormalized(), _box_origin())


func _build_fallback_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = FALLBACK_SIZE
	return box


## El impulso es [b]tangencial[/b] al arco: `v = ω × r` con ω sobre el eje
## vertical, o sea `UP × radial` (`docs/07` §5.5).
func _impulse_direction(_body: Node3D, _origin: Vector3) -> Vector3:
	var tangent := Vector3.UP.cross(_swept_direction())
	if tangent.is_zero_approx():
		return Vector3.UP
	return tangent.normalized()


## Dirección del arco en este instante.
func _swept_direction() -> Vector3:
	return _base_direction.rotated(Vector3.UP, _angle).normalized()


## Centro de la caja: a media longitud del cuerpo, a la altura del barrido.
func _box_origin() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.ZERO
	var body := host.global_position
	var offset := _swept_direction() * (INNER_REACH + _length() * 0.5)
	return Vector3(body.x + offset.x, _ground_y + SWEEP_HEIGHT, body.z + offset.z)


## Alcance del barrido desde el cuerpo, para el anillo del aviso.
func _reach() -> float:
	return INNER_REACH + _length()


## Longitud de la caja (su eje X).
func _length() -> float:
	var box := _sweep_shape() as BoxShape3D
	return box.size.x if box != null else FALLBACK_SIZE.x


## Centro del anillo del aviso: el cuerpo, que es el eje del arco.
func _ground_point() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.ZERO
	return Vector3(host.global_position.x, _ground_y, host.global_position.z)


## Dirección horizontal del cuerpo al objetivo creído.
func _direction_to_target() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.FORWARD
	var point := target_point(context())
	var flat := Vector3(point.x - host.global_position.x, 0.0,
			point.z - host.global_position.z)
	if flat.is_zero_approx():
		var facing := -host.global_basis.z
		facing.y = 0.0
		return facing.normalized() if not facing.is_zero_approx() else Vector3.FORWARD
	return flat.normalized()


## Pata que barre: la delantera del lado del dron.
func _pick_leg() -> int:
	var leg_rig := rig()
	if leg_rig == null:
		return -1
	var host := owner_enemy()
	var toward := host.global_position + _base_direction * 20.0 if host != null else Vector3.ZERO
	return leg_rig.front_leg_toward(toward)


## Retrae la pata [constant RETRACT_DEGREES]° hacia atrás y la sube media altura
## de barrido: es el canal de postura del aviso.
func _retract_leg() -> void:
	var leg_rig := rig()
	var host := owner_enemy()
	if leg_rig == null or host == null or _leg_index < 0:
		return
	var back := _base_direction.rotated(Vector3.UP, deg_to_rad(180.0 - RETRACT_DEGREES))
	var body := host.global_position
	var point := body + back * (INNER_REACH + _length() * 0.4)
	point.y = _ground_y + SWEEP_HEIGHT * 1.5
	if leg_rig.is_leg_raised(_leg_index):
		leg_rig.move_raised_leg(_leg_index, point)
	else:
		leg_rig.raise_leg(_leg_index, point)


## Devuelve la pata al ciclo de paso.
func _release_leg() -> void:
	var leg_rig := rig()
	if leg_rig != null and _leg_index >= 0:
		leg_rig.release_leg(_leg_index)
