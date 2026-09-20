## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `shake_off` — antiacampe (`docs/07` §5.10).
##
## [b]Sólo puntúa[/b] con `time_near > `[constant NEAR_SECONDS]` s` y el dron a
## menos de [constant NEAR_DISTANCE] m. No es un ataque que el jefe elija: es la
## respuesta a un jugador que se instaló pegado a una rodilla y dejó de esquivar.
##
## [b]Telegrafía 0.8 s[/b]: todo el cuerpo tiembla a [constant SHAKE_HZ] Hz con
## ±[constant SHAKE_AMPLITUDE] m de amplitud (canal de postura), el anillo de
## hombros destella blanco y suena el traqueteo metálico. El temblor se escribe
## sobre el nodo `Model`, que es el único transform del jefe que no se disputan
## `move_body` (XZ) y el rig (Y y base): tocar cualquiera de los otros dos haría
## que el coloso se «nadara» a sí mismo.
##
## [b]Activo 1.0 s[/b]: [SphereShape3D] de r 16 centrada en el casco, evaluada
## cada `query_interval`. 25 de daño una sola vez y 80 N·s radiales hacia afuera.
##
## [b]Contramedida[/b]: no acampar; o encajar el golpe y aprovechar los 0.6 s de
## recuperación.
class_name ActionShakeOff extends SweepAction

## Segundos que el dron tiene que llevar cerca para que el ataque puntúe.
const NEAR_SECONDS: float = 6.0

## Distancia por debajo de la cual el dron cuenta como «encima», en metros.
const NEAR_DISTANCE: float = 12.0

## Frecuencia del temblor, en Hz.
const SHAKE_HZ: float = 12.0

## Amplitud del temblor, en metros.
const SHAKE_AMPLITUDE: float = 0.4

## Radio de la esfera si el perfil no trae forma, en metros.
const FALLBACK_RADIUS: float = 16.0

var _shake_phase: float = 0.0
var _model_rest: Vector3 = Vector3.ZERO
var _shaking: bool = false


## Antiacampe puro: sin las dos condiciones de `docs/07` §5.10, vale cero.
func score(ctx: Dictionary) -> float:
	if profile == null or not locomotion_ready():
		return 0.0
	if float(ctx.get(&"time_near", 0.0)) <= NEAR_SECONDS:
		return 0.0
	var distance := target_distance(ctx)
	if distance >= NEAR_DISTANCE:
		return 0.0
	# Cuanto más pegado, más urgente: 1.0 encima del cuerpo y 0 en el borde.
	return ActionScore.clamp01(1.0 - distance / NEAR_DISTANCE)


# --------------------------------------------------------------------------
# Coreografía
# --------------------------------------------------------------------------

func _on_telegraph() -> void:
	_shake_phase = 0.0
	_begin_shake()
	var node := telegraph_node()
	if node != null:
		node.set_radius(shape_radius())
		node.set_ground_point(_body_ground())


## Temblor de [constant SHAKE_HZ] Hz sobre el nodo `Model`.
func _on_telegraph_tick(delta: float) -> void:
	_shake_phase += delta * SHAKE_HZ * TAU
	var model := _model()
	if model == null or not _shaking:
		return
	model.position = _model_rest + Vector3(
			sin(_shake_phase) * SHAKE_AMPLITUDE,
			sin(_shake_phase * 1.7) * SHAKE_AMPLITUDE * 0.5,
			cos(_shake_phase * 1.3) * SHAKE_AMPLITUDE)
	var node := telegraph_node()
	if node != null:
		node.set_ground_point(_body_ground())


func _on_active_begin() -> void:
	_end_shake()
	super._on_active_begin()


func _on_finish() -> void:
	_end_shake()


func _on_interrupt() -> void:
	super._on_interrupt()
	_end_shake()


func _exit_tree() -> void:
	_end_shake()


## `true` mientras el cuerpo está temblando.
func is_shaking() -> bool:
	return _shaking


# --------------------------------------------------------------------------
# Volumen
# --------------------------------------------------------------------------

## La esfera se centra en el cuerpo, a la altura de cadera: el sacudón sale del
## coloso, no del suelo.
##
## [b]Desviación de `docs/07` §5.10[/b], que dice «centrada en el casco». El
## casco vive entre 22 y 29 m de altura (`docs/07` §2) y las rodillas —donde
## acampa exactamente el jugador al que este ataque castiga— entre 6 y 12 m: una
## esfera de 16 m colgada del casco no llega ni a sus propias rodillas, así que
## el ataque antiacampe no alcanzaría nunca a nadie. Centrada en la cadera
## (14 m) cubre las cuatro rodillas y los 12 m de `time_near` que el `score()`
## exige, que es lo que el documento quiere decir.
func _sweep_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _body_centre())


func _build_fallback_shape() -> Shape3D:
	var sphere := SphereShape3D.new()
	sphere.radius = FALLBACK_RADIUS
	return sphere


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## Guarda la pose de reposo del modelo y arranca el temblor.
func _begin_shake() -> void:
	var model := _model()
	if model == null or _shaking:
		return
	_model_rest = model.position
	_shaking = true


## Devuelve el modelo a su sitio. Es idempotente: lo llaman el fin, la
## interrupción y la salida del árbol.
func _end_shake() -> void:
	if not _shaking:
		return
	_shaking = false
	var model := _model()
	if model != null:
		model.position = _model_rest


## Raíz del GLB, el único transform que nadie más escribe.
func _model() -> Node3D:
	var host := owner_enemy()
	if host == null:
		return null
	return host.model


## Centro del cuerpo, a la altura de cadera sobre el suelo: el centro de la onda.
func _body_centre() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.ZERO
	var height := host.profile.hip_height if host.profile != null else 14.0
	var ground := _body_ground()
	return Vector3(host.global_position.x, ground.y + height, host.global_position.z)


## Proyección del cuerpo sobre el suelo, para el anillo del aviso.
func _body_ground() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.ZERO
	return ground_snap(host.global_position)
