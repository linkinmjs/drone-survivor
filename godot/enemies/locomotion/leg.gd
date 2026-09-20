## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Una pata del rig procedural (`docs/06` §8.1).
##
## Envuelve los cuatro nodos del GLB que forman la pata —coxa, fémur, tibia y
## pie—, **mide** sobre la pose de reposo del modelo todo lo que el IK necesita
## (longitudes, pivotes, marcos de alabeo) y aplica la solución escribiendo
## **sólo la base local** de cada hueso: las posiciones locales que vinieron del
## import no se tocan nunca, así el esqueleto no se desarma aunque el rig se
## equivoque.
##
## Medidas del Arachnodroid, derivadas de `arachnodroid.parts.json` y no
## escritas a mano: fémur 7.593 m, tibia 6.0 m, tobillo 3.75 m sobre la planta
## del pie, cadera (pivote del fémur) a 17.25 m del origen del cuerpo.
class_name Leg extends RefCounted

## Valor de [member step_t] cuando la pata está apoyada.
const PLANTED: float = -1.0

## Giro máximo de la coxa respecto de su reposo, en grados. Más que esto haría
## que la pata cruzara por debajo de la carcasa.
const COXA_YAW_LIMIT: float = 40.0

## Índice de la pata dentro del rig, en el orden en que las agrupó [EnemyBase].
var index: int = 0

## Lado: `FL`, `FR`, `BL` o `BR`.
var side: StringName = &""

## Coxa (`leg_XX_coxa`): el nodo que gira en yaw para encarar la pata.
var hip: Node3D = null

## Fémur (`leg_XX_femur`): primer hueso del IK.
var femur: Node3D = null

## Tibia (`leg_XX_tibia`): segundo hueso del IK.
var tibia: Node3D = null

## Pie (`leg_XX_foot`): la punta de la cadena; su pivote es el tobillo.
var foot: Node3D = null

## Longitud del fémur, medida entre pivotes.
var femur_length: float = 1.0

## Longitud de la tibia, medida entre pivotes.
var tibia_length: float = 1.0

## Altura del tobillo sobre la planta del pie, medida del `AABB` de la malla.
var ankle_lift: float = 0.0

## Objetivo de apoyo en espacio del cuerpo, con `y = 0` en la planta del pie.
## Es el que se re-balancea al perder patas.
var rest_offset: Vector3 = Vector3.ZERO

## Reposo de marcha: el del modelo más el ensanchamiento `stance_spread` que
## aplica el rig, antes de cualquier re-balance.
var base_rest_offset: Vector3 = Vector3.ZERO

## Vector de polo en espacio del cuerpo: hacia dónde se arquea la rodilla.
var pole: Vector3 = Vector3.RIGHT

## Pivote de la coxa en espacio del cuerpo.
var coxa_offset: Vector3 = Vector3.ZERO

## Pivote del fémur (la cadera propiamente dicha) en espacio del cuerpo.
var hip_offset: Vector3 = Vector3.ZERO

## `true` mientras el pie sostiene el cuerpo.
var planted: bool = true

## Punto de apoyo en el mundo: lo fija el rayo de colocación.
var plant_position: Vector3 = Vector3.ZERO

## Normal del apoyo; orienta la planta del pie.
var plant_normal: Vector3 = Vector3.UP

## Colisionador sobre el que se apoya el pie, para el daño por aplastamiento.
var plant_collider: Object = null

## `true` si el apoyo actual es un edificio (capa `city`).
var plant_is_city: bool = false

## Último veredicto del rayo corto que confirma que sigue habiendo suelo bajo el
## apoyo. Se refresca por turnos, una pata por tick.
var supported: bool = true

## Objetivo de apoyo del paso en curso.
var target: Vector3 = Vector3.ZERO

## Normal prevista del objetivo del paso.
var target_normal: Vector3 = Vector3.UP

## Punto desde el que arrancó el paso en curso.
var step_from: Vector3 = Vector3.ZERO

## Progreso del paso de 0 a 1, o [constant PLANTED] si la pata está apoyada.
var step_t: float = PLANTED

## Duración del paso en curso, en segundos.
var step_time: float = 0.55

## Altura del arco del paso en curso, en metros.
var step_height: float = 3.0

## La pata se perdió: deja de recibir IK y de contar como apoyo.
var broken: bool = false

## La última solución de IK tuvo que estirar la cadena.
var stretched: bool = false

## Posición de mundo que el rig le pidió al tobillo en el último tick.
var ankle_target: Vector3 = Vector3.ZERO

## Posición de mundo del contacto del pie mientras dura el paso.
var foot_position: Vector3 = Vector3.ZERO

var _femur_rest_frame: Basis = Basis.IDENTITY
var _tibia_rest_frame: Basis = Basis.IDENTITY
var _foot_rest_frame: Basis = Basis.IDENTITY
var _coxa_rest_basis: Basis = Basis.IDENTITY
var _coxa_yaw_axis: Vector3 = Vector3.UP
var _coxa_rest_dir: Vector2 = Vector2(0.0, 1.0)
var _measured: bool = false


## Cablea los nodos desde el diccionario que arma [EnemyBase] (`docs/06` §2.1
## punto 6) y mide la pose de reposo. Devuelve `false` si la pata no sirve.
func bind(data: Dictionary, body: Node3D, pole_body: Vector3) -> bool:
	index = int(data.get("index", 0))
	side = StringName(data.get("side", &""))
	pole = pole_body
	var segments := data.get("segments", []) as Array
	if segments.size() < 2 or body == null:
		return false
	hip = _node_of(data.get("root", null))
	femur = _node_of(segments[0])
	tibia = _node_of(segments[1])
	foot = _node_of(data.get("foot", null))
	if femur == null or tibia == null or foot == null:
		return false
	measure(body, pole_body)
	return _measured


## Mide longitudes, pivotes y marcos de alabeo sobre la pose actual, que es la
## de reposo del GLB. Todo lo que el IK usa sale de acá: ni una cifra del
## modelo vive en el código.
func measure(body: Node3D, pole_body: Vector3) -> void:
	var body_inverse := body.global_transform.affine_inverse()
	femur_length = maxf(tibia.position.length(), TwoBoneIK.MIN_GAP)
	tibia_length = maxf(foot.position.length(), TwoBoneIK.MIN_GAP)

	var mesh := foot as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		ankle_lift = maxf(-mesh.mesh.get_aabb().position.y, 0.0)

	hip_offset = body_inverse * femur.global_position
	coxa_offset = body_inverse * (hip.global_position if hip != null else femur.global_position)
	var ankle_rest := body_inverse * foot.global_position
	base_rest_offset = Vector3(ankle_rest.x, ankle_rest.y - ankle_lift, ankle_rest.z)
	rest_offset = base_rest_offset

	# Marcos de reposo: llevan la dirección en la que cuelga cada hueso sobre la
	# primera columna y el polo sobre el plano de flexión. Se calculan en el
	# espacio local de cada hueso, así el rig funciona aunque el cuerpo esté
	# girado o inclinado al construirse.
	_femur_rest_frame = TwoBoneIK.frame(tibia.position,
			_to_local(body_inverse, femur, pole_body))
	_tibia_rest_frame = TwoBoneIK.frame(foot.position,
			_to_local(body_inverse, tibia, pole_body))
	_foot_rest_frame = TwoBoneIK.frame(Vector3.DOWN,
			_to_local(body_inverse, foot, pole_body))

	if hip != null:
		_coxa_rest_basis = hip.transform.basis
		var parent := hip.get_parent_node_3d()
		var parent_basis := parent.global_basis if parent != null else body.global_basis
		_coxa_yaw_axis = (parent_basis.inverse() * (body.global_basis * Vector3.UP)).normalized()
		var rest_dir := base_rest_offset - coxa_offset
		_coxa_rest_dir = Vector2(rest_dir.x, rest_dir.z)
		if _coxa_rest_dir.length_squared() < TwoBoneIK.EPSILON:
			_coxa_rest_dir = Vector2(0.0, 1.0)
		_coxa_rest_dir = _coxa_rest_dir.normalized()

	plant_position = body.global_transform * base_rest_offset
	foot_position = plant_position
	target = plant_position
	ankle_target = foot.global_position
	_measured = true


## `true` mientras el pie está en el aire.
func is_airborne() -> bool:
	return step_t >= 0.0


## `true` si la pata sostiene el cuerpo: sana y apoyada.
func supports() -> bool:
	return not broken and planted and not is_airborne()


## Punto de mundo donde está la planta del pie **de verdad**, con la pose que
## dejó el IK. Es lo que miden el deslizamiento y la flotación de `gait_check`.
func sole_position() -> Vector3:
	if foot == null or not is_instance_valid(foot):
		return plant_position
	return foot.global_transform * Vector3(0.0, -ankle_lift, 0.0)


## Objetivo de apoyo en el mundo para la pose [param body_xform], antes de
## proyectarlo contra el suelo.
func rest_world(body_xform: Transform3D) -> Vector3:
	return body_xform * rest_offset


## Cadera (pivote del fémur) en el mundo. Se lee del nodo porque la coxa gira.
func hip_world() -> Vector3:
	if femur == null or not is_instance_valid(femur):
		return Vector3.ZERO
	return femur.global_position


## Alcance máximo de la cadena con el estiramiento [param stretch_max].
func reach(stretch_max: float) -> float:
	return (femur_length + tibia_length) * stretch_max


## Aplica la pose: gira la coxa en yaw hacia [param ankle], resuelve el IK y
## escribe **sólo** las bases locales de fémur, tibia y pie.
##
## [param pole_world] es el vector de polo ya llevado a mundo y
## [param normal] la normal sobre la que apoya (o apoyará) la planta.
func apply(body_xform: Transform3D, ankle: Vector3, pole_world: Vector3,
		stretch_max: float, normal: Vector3) -> void:
	if broken or not _measured:
		return
	if not (is_instance_valid(femur) and is_instance_valid(tibia) and is_instance_valid(foot)):
		return
	ankle_target = ankle
	_aim_coxa(body_xform, ankle)

	var solution := TwoBoneIK.solve(hip_world(), ankle, femur_length, tibia_length,
			pole_world, stretch_max)
	stretched = bool(solution["stretched"])
	_write_basis(femur, _femur_rest_frame, solution["dir_a"] as Vector3,
			solution["normal"] as Vector3)
	_write_basis(tibia, _tibia_rest_frame, solution["dir_b"] as Vector3,
			solution["normal"] as Vector3)
	# La planta sigue la normal del apoyo, no la del cuerpo: en la rampa el pie
	# se apoya plano y no de canto.
	_write_basis(foot, _foot_rest_frame, -normal.normalized(), pole_world)


## Recoge la pata hacia la carcasa, que es la pose del `tuck` del salto
## (`docs/06` §8.6 punto 1). [param amount] va de 0 (extendida) a 1 (recogida).
func tuck_target(body_xform: Transform3D, amount: float) -> Vector3:
	var folded := rest_offset.lerp(Vector3(rest_offset.x * 0.55,
			rest_offset.y + ankle_lift + femur_length * 0.45, rest_offset.z * 0.55), amount)
	return body_xform * folded


## Gira la coxa en yaw para que la pata encare el objetivo. Nunca toca su
## posición local.
func _aim_coxa(body_xform: Transform3D, ankle: Vector3) -> void:
	if hip == null or not is_instance_valid(hip):
		return
	var local := body_xform.affine_inverse() * ankle
	var direction := Vector2(local.x - coxa_offset.x, local.z - coxa_offset.z)
	if direction.length_squared() < TwoBoneIK.EPSILON:
		return
	direction = direction.normalized()
	# Ángulo firmado en el plano XZ del cuerpo. Un giro de +θ alrededor de +Y
	# lleva (x, z) a un ángulo 2D de −θ: de ahí el signo.
	var cross := _coxa_rest_dir.x * direction.y - _coxa_rest_dir.y * direction.x
	var dot := _coxa_rest_dir.dot(direction)
	var yaw := -atan2(cross, dot)
	var limit := deg_to_rad(COXA_YAW_LIMIT)
	hip.transform = Transform3D(_coxa_rest_basis.rotated(_coxa_yaw_axis,
			clampf(yaw, -limit, limit)), hip.transform.origin)


## Escribe la base local de un hueso para que su dirección de reposo apunte a
## [param direction], conservando su posición local exacta.
func _write_basis(bone: Node3D, rest_frame: Basis, direction: Vector3,
		reference: Vector3) -> void:
	var world := TwoBoneIK.frame(direction, reference) * rest_frame.transposed()
	var parent := bone.get_parent_node_3d()
	var local := world if parent == null else parent.global_basis.inverse() * world
	# `frame()` ya devuelve bases ortonormales y el producto de ortonormales lo
	# sigue siendo: reortonormalizar acá sería pagar tres normalizaciones por
	# hueso y por tick para nada.
	bone.transform = Transform3D(local, bone.transform.origin)


## Lleva un vector de espacio del cuerpo al espacio local de [param bone] en su
## pose actual (la de reposo, cuando lo llama [method measure]).
func _to_local(body_inverse: Transform3D, bone: Node3D, vector_body: Vector3) -> Vector3:
	var rest_in_body := body_inverse.basis * bone.global_basis
	return rest_in_body.transposed() * vector_body


## Nodo [Node3D] de una [EnemyPart]: el rig mueve la malla del GLB, no la parte.
func _node_of(part: Variant) -> Node3D:
	var enemy_part := part as EnemyPart
	if enemy_part == null:
		return null
	return enemy_part.mesh
