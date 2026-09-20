## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `pounce` — el salto letal (`docs/07` §5.9).
##
## [b]Telegrafía 1.3 s, tres canales[/b] —los tres son obligatorios porque el
## golpe mata de casco lleno (`docs/06` §11.2)—: el cuerpo se agacha al
## [constant TUCK_RATIO] de `hip_height` con `ProceduralLegRig.set_crouch`, una
## parábola guía marca el punto de caída y el chillido de servo carga la luz.
##
## [b]Activo 1.2 s[/b]: `begin_leap(landing, 1.2, true)`. El tercer argumento se
## salta la recogida propia del rig: ya la hizo el aviso, y con ella encima el
## vuelo terminaría medio segundo después de cerrarse la ventana. Al aterrizar
## —por [signal ProceduralLegRig.leap_landed], no por el reloj de la ventana— se
## resuelve una [SphereShape3D] de r 12: [b]100 al dron[/b], 2 500 a los
## edificios del radio y `Events.camera_trauma(0.9, landing)`.
##
## [b]Recuperación 2.0 s[/b] con el cuerpo bajo y las cuatro rodillas al alcance:
## es la mejor ventana de daño del combate.
##
## [b]En P4[/b] el salto [b]reapunta hasta el instante del lanzamiento[/b] y cae
## sobre el dron, en vez de congelar el punto al terminar el aviso. La
## contramedida deja de ser esperar al congelado y pasa a ser moverse de verdad.
class_name ActionPounce extends SweepAction

## Fracción de `hip_height` a la que se agacha el cuerpo durante el aviso.
const TUCK_RATIO: float = 0.4

## Agachada que conserva durante la recuperación.
const RECOVER_CROUCH: float = 0.22

## Segundos finales del aviso en los que el punto de caída ya no se mueve, fuera
## de P4.
const FREEZE_SECONDS: float = 0.3

## Sacudida de cámara del aterrizaje (`docs/07` §5.9).
const TRAUMA: float = 0.9

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
const MIN_SUPPORT: int = 1

## Patas perdidas por encima de las cuales el salto deja de puntuar. Dos es el
## `DRAG` de `docs/06` §8.3: con tres el jefe queda postrado y no despega.
const MAX_LEGS_LOST: int = 2

## Distancia a la que el salto vale 1, en metros (`docs/06` §10.2).
const SWEET_SPOT: float = 30.0

## Velocidad del dron a la que el salto deja de valer, en m/s.
const SPEED_LIMIT: float = 14.0

## Radio de la esfera de aterrizaje si el perfil no trae forma, en metros.
const FALLBACK_RADIUS: float = 12.0

## Fase en la que el salto persigue al dron hasta el último instante.
const TRACKING_PHASE: StringName = &"p4_belly"

var _landing: Vector3 = Vector3.ZERO
var _frozen: bool = false
var _telegraph_elapsed: float = 0.0
var _launched: bool = false
var _impacted: bool = false


## Castiga al que se queda quieto a media-larga distancia (`docs/06` §10.2).
func score(ctx: Dictionary) -> float:
	if profile == null or not locomotion_ready():
		return 0.0
	if not bool(ctx.get(&"has_los", false)):
		return 0.0
	if int(ctx.get(&"legs_lost", 0)) > MAX_LEGS_LOST:
		return 0.0
	var distance := target_distance(ctx)
	var base := ActionScore.bell(distance, SWEET_SPOT, maxf(profile.max_range, 1.0))
	var still := 1.0 - clampf(float(ctx.get(&"drone_speed", 0.0)) / SPEED_LIMIT, 0.0, 1.0)
	var confidence := clampf(float(ctx.get(&"confidence", 0.0)), 0.0, 1.0)
	return ActionScore.clamp01(base * still * confidence)


# --------------------------------------------------------------------------
# Coreografía
# --------------------------------------------------------------------------

## El cuerpo se recoge y la parábola marca dónde va a caer.
func _on_telegraph() -> void:
	_frozen = false
	_launched = false
	_impacted = false
	_telegraph_elapsed = 0.0
	_landing = aim_point()
	var leg_rig := rig()
	if leg_rig != null:
		leg_rig.release_all_legs()
		leg_rig.set_crouch(TUCK_RATIO)
	_publish_aim()


## Sigue al objetivo. Fuera de P4 congela el punto los últimos
## [constant FREEZE_SECONDS]; en P4 no lo congela nunca (`docs/07` §6).
func _on_telegraph_tick(delta: float) -> void:
	_telegraph_elapsed += delta
	if _frozen:
		return
	if not _tracks_to_the_end() \
			and telegraph_seconds() - _telegraph_elapsed <= FREEZE_SECONDS:
		_frozen = true
		return
	_landing = aim_point()
	_publish_aim()


## Lanza el vuelo balístico, si hay apoyo suficiente.
func _on_active_begin() -> void:
	open_window()
	if not require_planted(MIN_SUPPORT):
		_release_body()
		return
	if _tracks_to_the_end():
		_landing = aim_point()
	var leg_rig := rig()
	if leg_rig == null:
		abort()
		_release_body()
		return
	leg_rig.clear_crouch()
	if not leg_rig.leap_landed.is_connected(_on_leap_landed):
		var _discard := leg_rig.leap_landed.connect(_on_leap_landed)
	# El `true` final se salta la recogida del rig: ya la hizo el aviso.
	leg_rig.begin_leap(_landing, active_seconds(), true)
	_launched = true


## El vuelo lo integra el rig; la ventana activa sólo espera el aterrizaje.
func _on_active(_delta: float) -> void:
	pass


## Cuerpo bajo durante la recuperación: las cuatro rodillas al alcance.
func _on_recover() -> void:
	var leg_rig := rig()
	if leg_rig != null:
		leg_rig.set_crouch(RECOVER_CROUCH)


func _on_finish() -> void:
	_release_body()


func _on_interrupt() -> void:
	super._on_interrupt()
	_release_body()


## Punto al que apunta (o apuntó) el salto.
func landing_point() -> Vector3:
	return _landing


## `true` si el último salto llegó a lanzarse.
func launched() -> bool:
	return _launched


## `true` si el último salto llegó a resolver su onda de aterrizaje.
func impacted() -> bool:
	return _impacted


# --------------------------------------------------------------------------
# Aterrizaje
# --------------------------------------------------------------------------

## El golpe se resuelve al tocar el suelo, que es cuando el rig lo avisa: atarlo
## al reloj de la ventana activa lo desincronizaría del vuelo en cuanto el
## aterrizaje quedara a otra altura que la salida.
func _on_leap_landed(position: Vector3) -> void:
	var leg_rig := rig()
	if leg_rig != null and leg_rig.leap_landed.is_connected(_on_leap_landed):
		leg_rig.leap_landed.disconnect(_on_leap_landed)
	if not _launched or _impacted:
		return
	_impacted = true
	_landing = position
	open_window()
	var _touched := resolve_at(_sweep_transform(), _sweep_shape())
	Events.camera_trauma.emit(TRAUMA, position)


func _sweep_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _landing + Vector3.UP * shape_radius() * 0.5)


func _build_fallback_shape() -> Shape3D:
	var sphere := SphereShape3D.new()
	sphere.radius = FALLBACK_RADIUS
	return sphere


func _damage_origin(_xform: Transform3D) -> Vector3:
	return _landing


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## `true` en la fase en la que el salto cae encima del dron (`docs/07` §6, P4).
func _tracks_to_the_end() -> bool:
	var host := owner_enemy()
	return host != null and host.current_phase() == TRACKING_PHASE


## Le pasa al aviso la parábola y el radio real de la onda.
func _publish_aim() -> void:
	var node := telegraph_node()
	if node == null:
		return
	node.set_radius(shape_radius())
	node.set_guide_target(_landing)


## Devuelve el cuerpo a su altura y suelta la conexión del aterrizaje.
func _release_body() -> void:
	var leg_rig := rig()
	if leg_rig == null:
		return
	leg_rig.clear_crouch()
	if leg_rig.leap_landed.is_connected(_on_leap_landed):
		leg_rig.leap_landed.disconnect(_on_leap_landed)
