## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## `stomp` — castigo al dron bajo y cerca (`docs/07` §5.4).
##
## [b]Telegrafía 1.1 s, tres canales[/b]: la pata delantera del lado del dron se
## levanta a [constant LIFT_FACTOR] × `hip_height` (postura), un decal rojo del
## radio real del cilindro se proyecta en el punto previsto siguiendo a
## `believed_position` y [b]congelándose los últimos[/b]
## [constant FREEZE_SECONDS], y el anillo de la rodilla vira cian → rojo con el
## chirrido de servo ascendente. Ese congelado es lo que hace esquivable el
## ataque: el jugador ve dónde va a caer el pie y tiene un cuarto de segundo para
## salir.
##
## [b]Activo 0.25 s[/b]: el pie baja y se resuelve un `intersect_shape` con el
## [CylinderShape3D] de r 9 × h 6 del perfil sobre las capas 2 y 8. Daño: 45 al
## casco más 55 N·s radiales y 2 500 a cada edificio tocado.
##
## [b]Gate de apoyo[/b] (`docs/06` §10.2, `docs/07` §5.4): al decidir sólo se
## exige que la locomoción no esté en `LEAP`/`STAGGER`/`DOWNED` —el trote deja
## exactamente dos patas apoyadas, así que pedir tres en el `score()` dejaría el
## pisotón muerto para siempre—; las patas se cuentan al [b]entrar en `ACTIVE`[/b],
## cuando el `lock_locomotion` del aviso ya las plantó. Si no quedan
## [constant MIN_SUPPORT] apoyadas además de la que pisa, la acción pasa directo
## a `RECOVER` sin daño y paga igual su enfriamiento.
class_name ActionStomp extends SweepAction

## Segundos finales del aviso en los que el punto de impacto ya no se mueve.
const FREEZE_SECONDS: float = 0.25

## Distancia a la que el pisotón vale 1, en metros (`docs/06` §10.2).
const SWEET_SPOT: float = 12.0

## Altura del dron sobre el suelo a partir de la cual el pisotón deja de valer.
const HEIGHT_LIMIT: float = 12.0

## Altura a la que sube la pata durante el aviso, en múltiplos de `hip_height`.
const LIFT_FACTOR: float = 1.6

## Fracción del camino al impacto a la que se adelanta la pata levantada.
const LEG_LEAD: float = 0.6

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

## Sacudida de cámara del impacto (`docs/07` §5.4).
const TRAUMA: float = 0.6

## Radio del cilindro si el perfil no trae forma, en metros.
const FALLBACK_RADIUS: float = 9.0

## Altura del cilindro si el perfil no trae forma, en metros.
const FALLBACK_HEIGHT: float = 6.0

var _impact: Vector3 = Vector3.ZERO
var _frozen: bool = false
var _telegraph_elapsed: float = 0.0
var _leg_index: int = -1
var _landed: bool = false


## Castigo al objetivo bajo y cerca (`docs/06` §10.2, fila `stomp`).
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

## Entra el aviso: decal del radio real y pata delantera levantada.
func _on_telegraph() -> void:
	_frozen = false
	_landed = false
	_telegraph_elapsed = 0.0
	_impact = aim_point()
	_leg_index = _pick_leg()
	_publish_aim()
	_lift_leg()
	var rig_audio := audio_rig()
	if rig_audio != null:
		rig_audio.set_servo_load(1.0)


## El punto sigue al objetivo hasta los últimos [constant FREEZE_SECONDS].
func _on_telegraph_tick(delta: float) -> void:
	_telegraph_elapsed += delta
	if _frozen:
		return
	if telegraph_seconds() - _telegraph_elapsed <= FREEZE_SECONDS:
		_frozen = true
		# El decal deja de seguir a la creencia: de acá en más el jugador sabe
		# exactamente dónde cae el pie (`docs/07` §5.4).
		var node := telegraph_node()
		if node != null:
			node.freeze_zone()
		return
	_impact = aim_point()
	_publish_aim()
	_lift_leg()


## Baja el pie y resuelve, si hay apoyo suficiente.
func _on_active_begin() -> void:
	if not require_planted(MIN_SUPPORT):
		_drop_leg()
		return
	var leg_rig := rig()
	if leg_rig != null and _leg_index >= 0:
		leg_rig.move_raised_leg(_leg_index, _impact)
	super._on_active_begin()
	_landed = true
	# La zona se apaga y deja la marca de cráter durante 4 s (`docs/13` §4). El
	# aviso ya cumplió: lo que queda es la cicatriz en la calle.
	var node := telegraph_node()
	if node != null:
		node.freeze_zone(true)
	Events.camera_trauma.emit(TRAUMA, _impact)


## La pata vuelve al suelo estirada y la rodilla queda quieta: es la ventana de
## daño que `docs/07` §5.4 le promete al jugador.
func _on_recover() -> void:
	_drop_leg()


func _on_finish() -> void:
	_drop_leg()
	var rig_audio := audio_rig()
	if rig_audio != null:
		rig_audio.set_servo_load(0.0)


func _on_interrupt() -> void:
	super._on_interrupt()
	_drop_leg()
	_frozen = false


## Punto en el que cayó el pie en la última ejecución.
func impact_point() -> Vector3:
	return _impact


## `true` si el último pisotón llegó a resolverse (no lo abortó el gate).
func landed() -> bool:
	return _landed


## Índice de la pata que pisa, o `-1`.
func stomping_leg() -> int:
	return _leg_index


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## El volumen nace en el suelo, no a la altura a la que vuela el dron.
func _sweep_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _impact + Vector3.UP * shape_height() * 0.5)


func _build_fallback_shape() -> Shape3D:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = FALLBACK_RADIUS
	cylinder.height = FALLBACK_HEIGHT
	return cylinder


## Le dice al aviso dónde y de qué tamaño va la zona. El radio es el del volumen
## de resolución: un decal más grande que el cilindro sería mentirle al jugador.
func _publish_aim() -> void:
	var node := telegraph_node()
	if node == null:
		return
	node.set_radius(shape_radius())
	node.set_ground_point(_impact)


## Pata delantera del lado del dron (`docs/07` §5.4).
func _pick_leg() -> int:
	var leg_rig := rig()
	if leg_rig == null:
		return -1
	return leg_rig.front_leg_toward(_impact)


## Levanta la pata a [constant LIFT_FACTOR] × `hip_height` sobre el impacto,
## adelantada [constant LEG_LEAD] del camino: desde abajo se lee de dónde viene
## el golpe.
func _lift_leg() -> void:
	var leg_rig := rig()
	var host := owner_enemy()
	if leg_rig == null or host == null or host.profile == null or _leg_index < 0:
		return
	var body := host.global_position
	var lifted := Vector3(lerpf(body.x, _impact.x, LEG_LEAD), 0.0,
			lerpf(body.z, _impact.z, LEG_LEAD))
	lifted.y = _impact.y + host.profile.hip_height * LIFT_FACTOR
	if leg_rig.is_leg_raised(_leg_index):
		leg_rig.move_raised_leg(_leg_index, lifted)
	else:
		leg_rig.raise_leg(_leg_index, lifted)


## Devuelve la pata al ciclo de paso.
func _drop_leg() -> void:
	var leg_rig := rig()
	if leg_rig != null and _leg_index >= 0:
		leg_rig.release_leg(_leg_index)
