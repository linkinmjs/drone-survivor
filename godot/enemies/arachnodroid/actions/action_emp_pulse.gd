## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `emp_pulse` — castigo de proximidad media (`docs/07` §5.8).
##
## [b]Telegrafía 2.2 s[/b]: un anillo cian crece [b]de 0 a 45 m[/b] en el suelo
## durante todo el windup —el `decal_grow_from 0.0` del [TelegraphProfile]—, de
## modo que el radio se lee exactamente desde el primer medio segundo; la luz
## ventral pulsa y el zumbido de condensadores sube. [b]Activo 0.3 s[/b]: un
## [b]único[/b] `intersect_shape` con una [SphereShape3D] de r 45 sobre la
## [b]capa 2 solamente[/b].
##
## [b]No hace daño al casco[/b] (`docs/07` §5.8 y `docs/09` §2.9): descuenta
## [constant DRAIN_RATIO] de la batería y avisa del glitch con
## `EnergySystem.apply_emp(amount, 3.0)`, que es quien emite `emp_hit` para el
## overlay FPV. Por eso sobrescribe [method SweepAction._apply_drone_effect] en
## vez de declarar `damage_drone`: un EMP que quitara casco sería otro ataque.
##
## [b]Contramedida[/b]: salir del círculo, que es visible y medible desde el
## segundo 0.5. Con 2.2 s de aviso y 45 m de radio, un dron a 20 m/s se salva
## desde cualquier punto de dentro.
class_name ActionEmpPulse extends SweepAction

## Fracción de la batería que se lleva el pulso (`docs/07` §5.8).
const DRAIN_RATIO: float = 0.25

## Segundos de glitch del overlay FPV (`docs/13`).
const GLITCH_SECONDS: float = 3.0

## Radio de la esfera si el perfil no trae forma, en metros.
const FALLBACK_RADIUS: float = 45.0

## Distancia a la que el pulso vale 1, en metros: la mitad del radio, que es
## donde el jugador ya no tiene tiempo de salir.
const SWEET_SPOT: float = 22.0

var _drained: float = 0.0
var _centre: Vector3 = Vector3.ZERO


## Proximidad media: el dron dentro del radio y con creencia suficiente.
func score(ctx: Dictionary) -> float:
	if profile == null or not locomotion_ready():
		return 0.0
	var distance := target_distance(ctx)
	var base := ActionScore.bell(distance, SWEET_SPOT, maxf(profile.max_range, 1.0))
	var confidence := clampf(float(ctx.get(&"confidence", 0.0)), 0.0, 1.0)
	return ActionScore.clamp01(base * confidence)


# --------------------------------------------------------------------------
# Coreografía
# --------------------------------------------------------------------------

## El anillo nace en el cuerpo, no en el dron: el pulso sale del jefe.
func _on_telegraph() -> void:
	_centre = _body_ground()
	var node := telegraph_node()
	if node != null:
		node.set_radius(shape_radius())
		node.set_ground_point(_centre)


func _on_telegraph_tick(_delta: float) -> void:
	_centre = _body_ground()
	var node := telegraph_node()
	if node != null:
		node.set_ground_point(_centre)


## Un solo barrido, y se acabó (`docs/07` §5.8: «un único `intersect_shape`»).
func _on_active_begin() -> void:
	_drained = 0.0
	_centre = _body_ground()
	open_window()
	var _touched := resolve_at(_sweep_transform(), _sweep_shape())
	var rig_audio := audio_rig()
	if rig_audio != null:
		var _player := rig_audio.play(&"emp_burst", _centre)


## La ventana activa no vuelve a consultar: el pulso ya pasó.
func _on_active(_delta: float) -> void:
	pass


## Energía que se llevó el último pulso, en la escala 0–100.
func drained() -> float:
	return _drained


## Centro del pulso.
func centre() -> Vector3:
	return _centre


# --------------------------------------------------------------------------
# Volumen y efecto
# --------------------------------------------------------------------------

## La esfera se centra en el cuerpo, a la altura del casco: el pulso es radial.
func _sweep_transform() -> Transform3D:
	var host := owner_enemy()
	var height := host.profile.hip_height if host != null and host.profile != null else 14.0
	return Transform3D(Basis.IDENTITY, _centre + Vector3.UP * height * 0.5)


func _build_fallback_shape() -> Shape3D:
	var sphere := SphereShape3D.new()
	sphere.radius = FALLBACK_RADIUS
	return sphere


## Drena la batería en vez de dañar el casco (`docs/09` §2.9).
func _apply_drone_effect(collider: Node3D, _origin: Vector3) -> void:
	var energy := find_energy(collider)
	if energy == null:
		return
	var maximum := 100.0
	if energy.has_method(&"get_max_energy"):
		maximum = float(energy.call(&"get_max_energy"))
	var amount := maximum * DRAIN_RATIO
	energy.call(&"apply_emp", amount, GLITCH_SECONDS)
	_drained += amount


## Proyección del cuerpo sobre el suelo, que es donde se dibuja el anillo.
func _body_ground() -> Vector3:
	var host := owner_enemy()
	if host == null:
		return Vector3.ZERO
	return ground_snap(host.global_position)
