## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Un proyectil del arma primaria: **datos sin nodo** (`docs/08` §2.1 y §3.4).
##
## Es un [RefCounted] a propósito. Un [RigidBody3D] por bala cuesta un cuerpo en
## Jolt, hace *tunneling* a 420 m/s y no se puede preasignar; un hitscan puro no
## permite trazadores creíbles ni tiempo de vuelo a 200 m. Lo que queda es esto:
## una estructura plana que [ProjectilePool] avanza por integración explícita en
## `_physics_process` y resuelve con un `intersect_ray` del tramo recorrido.
##
## Los 256 se crean una sola vez en el `_ready()` del pool y se reciclan con una
## lista libre; en caliente **no se instancia nada**, así que este objeto no tiene
## constructor con argumentos: se rellena con [method spawn] y se apaga con
## [method deactivate].
class_name Projectile extends RefCounted

## Posición actual en coordenadas de mundo.
var position: Vector3 = Vector3.ZERO

## Velocidad en m/s; su módulo es `WeaponProfile.projectile_speed`. Es un vector y
## no una dirección más un escalar para que P3 pueda integrarle gravedad sin
## cambiar el contrato (`docs/08` §6, decisión 5).
var velocity: Vector3 = Vector3.ZERO

## Segundos de vida que le quedan. Arranca en `max_range / projectile_speed`.
var ttl: float = 0.0

## Vida inicial, en segundos. Es el denominador del desvanecido del trazador.
var life: float = 1.0

## Segundos transcurridos desde el disparo.
var age: float = 0.0

## Daño base que este proyectil le pasa a la parte impactada, ya sin el
## multiplicador de punto débil (lo aplica el resolvedor).
var damage: float = 0.0

## Multiplicador que el resolvedor aplica si el impacto cae en la capa 4.
var weak_multiplier: float = 1.0

## El [WeaponMount] que lo disparó. Viaja hasta la clave `source` del diccionario
## `hit` de `docs/06` §14.1.
var source: Node3D = null

## RID del cuerpo del tirador, excluido de la consulta. Defensa en profundidad:
## la capa 2 tampoco está en `hit_mask`.
var shooter_rid: RID = RID()

## Ranura del [TracerRenderer] que dibuja este proyectil, o `−1` si no lleva
## trazador (uno de cada `tracer_every`).
var tracer_slot: int = -1

## `true` mientras ocupa una ranura del pool.
var active: bool = false


## Rellena el proyectil y lo marca activo. Devuelve el propio objeto para que el
## pool pueda encadenar.
func spawn(origin: Vector3, direction: Vector3, speed: float, time_to_live: float,
		base_damage: float, weak_bonus: float, emitter: Node3D,
		exclude_rid: RID) -> Projectile:
	position = origin
	velocity = direction * speed
	ttl = time_to_live
	life = maxf(time_to_live, 0.0001)
	age = 0.0
	damage = base_damage
	weak_multiplier = weak_bonus
	source = emitter
	shooter_rid = exclude_rid
	tracer_slot = -1
	active = true
	return self


## Apaga el proyectil y suelta la referencia al emisor, para que un dron destruido
## no quede vivo a través del pool.
func deactivate() -> void:
	active = false
	source = null
	tracer_slot = -1
	velocity = Vector3.ZERO
	ttl = 0.0


## Fracción de vida restante, de 1.0 recién disparado a 0.0 al expirar. Es lo que
## el trazador escribe en `INSTANCE_CUSTOM.r` para que el desvanecido lo haga el
## shader y no GDScript (`docs/08` §2.9).
func life_ratio() -> float:
	return clampf(ttl / life, 0.0, 1.0)


## Dirección de vuelo normalizada, o [constant Vector3.FORWARD] si está detenido.
func direction() -> Vector3:
	if velocity.length_squared() <= 0.0:
		return Vector3.FORWARD
	return velocity.normalized()
