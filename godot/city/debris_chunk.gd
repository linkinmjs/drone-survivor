## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Un trozo de escombro físico (`docs/10` §6).
##
## Lo crea y lo recicla [DebrisPool]; nadie lo instancia a mano. Nace congelado,
## se configura y recién entonces se suelta, para que Jolt no lo vea aparecer
## dentro de otro cuerpo. No guarda referencia al pool: el pool le lleva la edad
## y decide cuándo retirarlo, lo que evita una dependencia cíclica entre ambos.
##
## Capa **9** (`debris`) con máscara 1·2·8·9 = 387 (`docs/02` §3.1). `contact_monitor`
## queda apagado: quien detecta el golpe al dron es el propio dron (`docs/09`).
class_name DebrisChunk extends RigidBody3D

## Máscara de consulta de un escombro: `world | drone | city | debris`.
const DEBRIS_MASK: int = PhysicsLayers.WORLD | PhysicsLayers.DRONE \
		| PhysicsLayers.CITY | PhysicsLayers.DEBRIS

## Masa a partir de la cual se activa la detección continua de colisión.
##
## `docs/10` §6 y su riesgo 7 lo fijan en **800 kg**, y `docs/06` §4.1 usa la
## diagonal del AABB > 4 m. WP-16 lo había subido a 2 000 kg; WP-20 lo devuelve
## a los 800 kg del documento dueño, que es lo que hace que los escombros de
## torre (2 000 kg, `city/profiles/tower.tres`) lleven detección continua y no
## atraviesen el suelo al caer desde 40 m. El pie de 9 t del Arachnodroid la
## sigue teniendo y la antena de 250 kg sigue sin ella, así que el cambio no
## altera ningún caso de `docs/06`.
@export_range(0.0, 100000.0, 1.0, "or_greater") var continuous_cd_mass: float = 800.0

## Segundos que el escombro vive antes de congelarse y fundirse en el `RubbleField`.
var lifetime: float = 20.0

## Segundos vividos; los acumula [DebrisPool] en su `_physics_process`.
var age: float = 0.0

## Segundos que lleva dormido. A los 2 s el pool lo retira por anticipado.
var sleep_time: float = 0.0

## Malla que representa a este trozo en el `RubbleField` al retirarse.
var rubble_mesh: Mesh = null

## Tinte con el que se hornea la instancia en el `RubbleField`.
var tint: Color = Color(1.0, 1.0, 1.0, 1.0)

## Nodos que [method DebrisPool.adopt] reparentó acá: mallas y colisionadores
## que ya no pertenecen al enemigo y que mueren con el chunk. Un chunk con esta
## lista vacía es un trozo fabricado por [method DebrisPool.request] y, por lo
## tanto, reciclable: es el dato que necesitará la lista libre de WP-20.
var adopted: Array[Node] = []


func _ready() -> void:
	collision_layer = PhysicsLayers.DEBRIS
	collision_mask = DEBRIS_MASK
	contact_monitor = false
	can_sleep = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


## Deja el chunk listo para volar: fija la masa, decide la detección continua y
## lo descongela. [param spin] es la velocidad angular inicial, en rad/s.
func launch(impulse: Vector3, spin: Vector3, chunk_mass: float) -> void:
	mass = maxf(chunk_mass, 0.001)
	continuous_cd = mass > continuous_cd_mass
	freeze = false
	sleeping = false
	angular_velocity = spin
	if not impulse.is_zero_approx():
		apply_central_impulse(impulse)


## Congela el chunk en su sitio. Es lo que hace el pool al retirarlo: la
## transformada queda quieta para poder hornearla en el `RubbleField`.
func freeze_in_place() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Deja el chunk aparcado en la lista libre del pool: congelado, invisible y
## fuera de toda capa, para que no choque con nada mientras espera turno
## (`docs/10` §6).
func park_in_pool() -> void:
	freeze_in_place()
	visible = false
	collision_layer = 0
	collision_mask = 0
	age = 0.0
	sleep_time = 0.0
	rubble_mesh = null


## Deshace [method park_in_pool]. Lo llama el pool al reutilizarlo; el chunk
## queda congelado hasta que [method launch] lo suelta.
func wake_from_pool() -> void:
	visible = true
	collision_layer = PhysicsLayers.DEBRIS
	collision_mask = DEBRIS_MASK
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
