## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-17, ampliado en WP-24d: mide la marcha procedural del
## Arachnodroid (`docs/06` §16.2).
##
## Levanta un mundo sintético —llano, rampa de 20° de 130 m, tres escalones de
## 4 m, una roca, tres edificios en capa 8 y, desde WP-T2, un **parche de
## relieve** de 128 m de lado sobre un [HeightMapShape3D]— y hace caminar al
## jefe 120 s simulados por una ronda de puntos de paso que cruza los cinco
## terrenos, más un giro de 180° en el lugar, un salto y una travesía del
## relieve. Mientras camina mide, tick a tick:
##
## | # | Métrica | Umbral | Origen |
## |---|---|---|---|
## | 1 | Deslizamiento de un pie apoyado | < 0.10 m | WP-24d (era 0.25) |
## | 2 | Pie flotando > 0.30 m sobre su apoyo | nunca > 0.20 s seguidos | §16.2 |
## | 3 | Pares diagonales en el aire a la vez | 0 ocurrencias | §16.2 |
## | 4 | Inclinación del cuerpo en la rampa de 20° | entre 8° y 16° | §16.2 |
## | 5 | Altura de la cadera en llano | `hip_height` ± 1 m | §16.2 |
## | 6 | Estabilidad numérica | 0 `NaN` / `INF` en 120 s | §16.2 |
## | 7 | Paso de `move_body` | ≤ `max_step_per_tick` | §16.2 |
## | 8 | Coste de `rig_tick` | < 0.25 ms de media | §16.2 |
## | 9 | Retraso entre «pie plantado» y contacto visual | < 0.05 s | WP-24d |
## | 10 | Rodilla mínima en marcha en llano | ≥ 8.5 m | WP-24d |
## | 11 | Cabeceo máximo en llano | ≤ 6° | WP-24d |
## | 12 | Deslizamiento por pie en un giro de 180° | < 0.25 m | WP-24d |
## | 13 | Tibia o pie dentro de un edificio intacto | nunca > 0.20 s | WP-24d |
## | 14 | Salto: las 4 patas apoyadas tras tocar el suelo | < 0.60 s | WP-24d |
##
## La **cuarta superficie** (WP-T2) se mide aparte, en [method _check_relief]:
## el jefe cruza de ida y vuelta un heightfield de ruido de ±1,5 m y 30 m de
## longitud de onda —generado con [method TownTerrain.from_noise], la misma
## técnica que hornea el terreno del pueblo— y se le exigen los **mismos
## umbrales que al tramo de rampa** para lo que mide el apoyo: ningún pie
## flotando más de 0,20 s, ninguna cadena estirada, nunca menos de dos patas
## apoyadas. El **balanceo de la planta** se mide aparte y con su propio tope
## ([constant RELIEF_SOLE_SWING]), porque sobre terreno irregular no mide un
## resbalón sino que el pie pivota alrededor de un tobillo quieto: ahí está la
## explicación entera. Va en su propio tramo y no dentro de la ronda de 120 s
## para no correr los kilómetros que las métricas 4 y 10 necesitan sobre la
## rampa y el llano: las catorce métricas de antes miden exactamente lo mismo
## que antes.
##
## Y además, con guion: rompe una rodilla en marcha (trípode, ≥ 60 % de la
## velocidad), rompe otra (arrastre ×0.55), salta sobre la roca, comprueba que
## pisar un edificio le cobra `crush_damage` y cierra con una **prueba negativa**
## —`step_trigger` a 30 m y `reach_trigger` desarmado— que debe hacer saltar por
## los aires las métricas 1 y 2.
##
## Las métricas 1 y 2 se exigen con **cuatro patas y con tres**; con dos se
## miden y se imprimen, pero no se exigen: en `DRAG` el cuerpo se arrastra con
## una sola pata en el aire por vez y el pie apoyado no puede seguirle el paso
## por definición. Es el modo que `docs/06` §8.3 llama, justamente, arrastre.
##
## El desglose por terreno —llano, rampa, escalones, edificios— se imprime
## siempre aunque no se exija: un máximo global sin terreno no dice dónde
## mirar, y en WP-24d hizo falta exactamente eso.
##
## El mundo lo arma este script, no la escena: así los tamaños salen de las
## constantes de acá y no hay que editar un `.tscn` para mover un escalón.
extends CheckRunner

## Escena del jefe.
const ENEMY_SCENE: String = "res://enemies/arachnodroid/arachnodroid.tscn"

## Segundos simulados de marcha continua (`docs/06` §16.2: 120 s totales).
const WALK_SECONDS: float = 120.0

## Aceleración de la simulación. El tope lo fija WP-17 en 4×.
const TIME_SCALE: float = 4.0

## Deslizamiento máximo de un pie apoyado, en metros (WP-24d: era 0.25).
const MAX_SLIDE: float = 0.10

## Deslizamiento máximo con una pata perdida, en metros.
##
## Es el 0.25 m original de `docs/06` §16.2. En trípode se levanta **una** pata
## por vez, así que la que sufre espera un tranco entero de otra antes de que le
## toque; el trote, que mueve el par entero, no paga esa espera. WP-24d aprieta
## la marcha sana a 0.10 m y le deja al modo degradado el umbral del documento.
const MAX_SLIDE_TRIPOD: float = 0.25

## Altura a partir de la cual un pie apoyado se considera flotando, en metros.
const FLOAT_HEIGHT: float = 0.30

## Tiempo máximo que se tolera un pie flotando, en segundos.
const MAX_FLOAT_TIME: float = 0.20

## Distancia a la que la planta se considera **en contacto visual** con su
## apoyo, en metros. Son el 6 % de la altura del pie del Arachnodroid (3.4 m).
const CONTACT_EPS: float = 0.20

## Retraso máximo entre el contacto visual y el apoyo declarado, en segundos.
const MAX_CONTACT_DELAY: float = 0.05

## Altura mínima de la rodilla en marcha en llano, en metros.
const MIN_KNEE: float = 8.5

## Cabeceo máximo del cuerpo en llano, en grados.
const MAX_FLAT_TILT: float = 6.0

## Deslizamiento máximo por pie durante el giro de 180°, en metros.
const MAX_TURN_SLIDE: float = 0.25

## Tiempo máximo que una tibia o un pie puede pasar dentro de un edificio
## intacto, en segundos.
const MAX_PENETRATION: float = 0.20

## Segundos que se le dan al aterrizaje para dejar las 4 patas apoyadas.
const LAND_PLANT_BUDGET: float = 0.60

## Banda de inclinación válida del cuerpo sobre la rampa de 20°, en grados.
const RAMP_TILT_MIN: float = 8.0
const RAMP_TILT_MAX: float = 16.0

## Tolerancia de la altura de cadera en llano, en metros.
const HEIGHT_TOLERANCE: float = 1.0

## Presupuesto de `rig_tick`, en microsegundos (`docs/06` §15).
const MAX_RIG_USEC: float = 250.0

## Velocidad mínima con tres patas, como fracción de `walk_speed`.
const TRIPOD_SPEED_RATIO: float = 0.60

## Segundos que se le dan al salto para dejar los cuatro pies en el suelo.
const LEAP_BUDGET: float = 4.0

## Pendiente de la rampa, en grados, y su largo en metros.
const RAMP_ANGLE: float = 20.0
const RAMP_LENGTH: float = 120.0
const RAMP_START_X: float = 60.0
const RAMP_WIDTH: float = 80.0
const RAMP_THICKNESS: float = 8.0

## Escalones: tres de 4 m, hacia −X.
const STEP_RISE: float = 4.0
const STEP_DEPTH: float = 30.0
const STEP_FIRST_X: float = -40.0

## Roca del salto: caja de 12 × 10 × 12 m en capa 1.
const ROCK_SIZE: Vector3 = Vector3(12.0, 10.0, 12.0)
const ROCK_CENTER: Vector3 = Vector3(0.0, 5.0, -70.0)

## Los tres edificios de prueba en capa 8, con el techo a 8 m. El primero es el
## que la ronda pisa; los otros dos flanquean el pasillo por el que camina, que
## es donde se mide que ninguna tibia los atraviese.
const BUILDING_SIZE: Vector3 = Vector3(26.0, 8.0, 26.0)
## El primero es el que la ronda pisa; los otros dos flanquean el pasillo por el
## que camina, a 44 m del eje: con una huella de 22 m y la zancada del trote, el
## coloso pasa entre ellos **sin tocarlos**, que es justo lo que la métrica 13
## tiene que poder afirmar.
const BUILDINGS: Array[Vector3] = [
	Vector3(0.0, 4.0, 70.0),
	Vector3(-44.0, 4.0, 40.0),
	Vector3(44.0, 4.0, 40.0),
]

## Ventana de la rampa en la que se mide la inclinación: con el cuerpo acá, las
## cuatro patas pisan la pendiente.
const RAMP_SAMPLE_MIN: float = 80.0
const RAMP_SAMPLE_MAX: float = 150.0

## Radio en torno al origen que se considera llano para medir la altura.
const FLAT_RADIUS: float = 35.0

## Desnivel máximo entre pies apoyados para considerar el apoyo «en llano».
const LEVEL_TOLERANCE: float = 0.5

## Puntos de paso de la ronda, en XZ. Cruzan rampa, escalones y edificios.
const WAYPOINTS: Array[Vector2] = [
	Vector2(40.0, 0.0),
	Vector2(150.0, 0.0),
	Vector2(40.0, 0.0),
	Vector2(-30.0, 0.0),
	Vector2(-120.0, 0.0),
	Vector2(-30.0, 0.0),
	Vector2(0.0, 62.0),
	Vector2(0.0, 0.0),
]

## Distancia a la que se da por alcanzado un punto de paso.
const WAYPOINT_RADIUS: float = 8.0

## Segundo simulado en el que se rompe cada rodilla.
const FIRST_BREAK: float = 86.0
const SECOND_BREAK: float = 104.0

## Rodillas que se rompen, en orden.
const BREAK_KNEES: Array[StringName] = [&"wp_leg_fl_knee", &"wp_leg_bl_knee"]

## `step_trigger` absurdo de la prueba negativa, en metros.
const NEGATIVE_TRIGGER: float = 30.0

## Segundos simulados de la prueba negativa.
const NEGATIVE_SECONDS: float = 14.0

## Segundos simulados que dura el giro de 180° en el lugar.
const TURN_SECONDS: float = 12.0

## Cuarta superficie (WP-T2): un [HeightMapShape3D] de ruido, generado con la
## misma técnica que el terreno del pueblo.
##
## Va al sur del llano, lejos de la rampa, de los escalones, de la roca y de los
## edificios: el parche tiene que ser el **único** accidente bajo los pies
## mientras se lo mide, o el deslizamiento que se anote sería el de otro
## terreno. Se apoya sobre el llano y se desvanece a cero en sus últimos doce
## metros, así que el jefe entra y sale sin escalón.
const RELIEF_CENTRE: Vector3 = Vector3(0.0, 0.0, -150.0)
const RELIEF_SAMPLES: int = 129
const RELIEF_CELL: float = 1.0
const RELIEF_WAVELENGTH: float = 30.0
const RELIEF_AMPLITUDE: float = 1.5
const RELIEF_FADE: float = 12.0

## Cuánto se levanta el parche sobre el llano, en metros.
##
## Con el valle más hondo en `y = 0` el heightfield queda **coplanar** con la
## tapa de la caja del llano, y dos superficies coplanares son un empate de
## raycast esperando a pasar. Se midió si ese empate explicaba el arrastre de la
## planta —no lo explica: con y sin separación la medida sale idéntica al
## milímetro— pero la separación se deja igual, porque un banco de pruebas no
## debe tener dos suelos en el mismo plano.
const RELIEF_CLEARANCE: float = 2.0

## Tope del balanceo de la planta sobre el relieve, en metros.
##
## **No es la tolerancia de la métrica 1 con otro nombre.** Mide otra cosa, y
## hace falta decir cuál, porque el número asusta.
##
## Sobre cajas —llano, rampa de 20°, escalones de 4 m— la planta de un pie
## apoyado no se mueve ni un milímetro en 120 s. Sobre el heightfield se
## desplaza hasta 0,43 m. Midiéndolo con detalle: ocurre **en recta** (0,00
## rad/s de giro), sobre apoyos de **2° de pendiente**, y con la cadena al 78 %,
## o sea sin estirar. El objetivo del IK es el tobillo, `plant_position +
## ankle_lift`, y es fijo mientras la pata está apoyada; lo que se mueve es la
## **geometría del pie**, que cuelga de la tibia con un desfase lateral. Sobre
## terreno irregular las cuatro patas apoyan a alturas distintas, el cuerpo
## cabecea y se hunde para acomodarlas (`tilt_blend`, `height_smooth_rate`,
## `_reach_crouch`), la tibia se reorienta y la planta —que es un punto rígido
## de esa tibia— barre un arco alrededor de un tobillo que no se movió.
##
## O sea: **el apoyo no resbala, el pie pivota**. Es visible igual, y arreglarlo
## es hacer que el IK apunte a la planta y no al tobillo, en
## `enemies/locomotion/leg.gd`, que no es un archivo de este WP y que tocaría
## las catorce métricas anteriores. Queda anotado para el checkpoint. Mientras
## tanto este umbral es una **guarda de regresión** sobre un límite conocido del
## rig: si el balanceo crece, algo empeoró.
const RELIEF_SOLE_SWING: float = 0.50
const RELIEF_SEED: int = 4711

## Los dos puntos de paso que cruzan el parche, en XZ absolutas.
const RELIEF_WAYPOINTS: Array[Vector2] = [
	Vector2(-42.0, -150.0),
	Vector2(42.0, -150.0),
]

## Segundos simulados de la travesía del relieve.
const RELIEF_SECONDS: float = 30.0

## Inclinación máxima del cuerpo tolerada sobre el relieve, en grados. El parche
## tiene pendientes de hasta unos 17° (`2π · 1,5 / 30`), así que el cuerpo no
## tiene por qué pasar de la banda alta de la rampa.
const RELIEF_TILT_MAX: float = 20.0

## Metros que el jefe tiene que recorrer sobre el parche para que la medida
## valga: sin esto, un jefe que se queda clavado pasaría en verde.
const RELIEF_MIN_TRAVEL: float = 60.0

## Giro por encima del cual un tick del relieve cuenta como «girando», en rad/s.
## El coloso vira a unos 0,44 rad/s (25°/s), así que 0,10 separa limpiamente la
## recta del viraje.
const RELIEF_TURN_RATE: float = 0.10


## Edificio de prueba: un `StaticBody3D` de capa `city` que apunta cada
## aplastamiento. No hereda de `Building` (`docs/10`) a propósito: el rig lo
## resuelve por *duck typing*, y el check tiene que demostrar justamente eso.
class TestBuilding extends StaticBody3D:
	var hits: int = 0
	var total: float = 0.0
	var last_point: Vector3 = Vector3.ZERO
	var box: AABB = AABB()

	func take_damage(amount: float, point: Vector3) -> void:
		hits += 1
		total += amount
		last_point = point

	## `true` si [param point] cae dentro del volumen, con [param margin] metros
	## de holgura en cada cara para no contar un roce de la piel del collider.
	func contains(point: Vector3, margin: float) -> bool:
		return box.grow(-margin).has_point(point)


## Acumulador de métricas de una corrida de marcha.
class Metrics extends RefCounted:
	var max_slide: float = 0.0
	var max_float: float = 0.0
	var max_float_time: float = 0.0
	var min_planted: int = 99
	var pair_violations: int = 0
	var nan_ticks: int = 0
	var max_body_step: float = 0.0
	var ramp_tilt_sum: float = 0.0
	var ramp_tilt_count: int = 0
	var flat_height_sum: float = 0.0
	var flat_height_count: int = 0
	var slide_offender: StringName = &""
	var float_offender: StringName = &""
	var slide_trace: String = ""
	var float_trace: String = ""
	var max_contact_delay: float = 0.0
	var contact_events: int = 0
	var min_knee: float = 1.0e9
	var max_flat_tilt: float = 0.0
	var max_penetration: float = 0.0
	var knee_trace: String = ""
	var penetration_trace: String = ""

	func ramp_tilt() -> float:
		return ramp_tilt_sum / float(maxi(ramp_tilt_count, 1))

	func flat_height() -> float:
		return flat_height_sum / float(maxi(flat_height_count, 1))


## Máximos por terreno. No se exigen: se imprimen para saber dónde mirar.
class Region extends RefCounted:
	var label: String = ""
	var max_slide: float = 0.0
	var max_float: float = 0.0
	var ticks: int = 0


var _enemy: EnemyBase = null
var _rig: ProceduralLegRig = null
var _relief: TownTerrain = null
var _buildings: Array[TestBuilding] = []
var _world: Node3D = null
var _metrics: Metrics = Metrics.new()
var _tripod: Metrics = Metrics.new()
var _drag: Metrics = Metrics.new()
var _regions: Dictionary[StringName, Region] = {}
var _anchors: Dictionary[int, Vector3] = {}
var _float_time: Dictionary[int, float] = {}
var _contact_hold: Dictionary[int, float] = {}
var _was_airborne: Dictionary[int, bool] = {}
var _inside_time: Dictionary[int, float] = {}
var _waypoint: int = 0
var _last_body: Vector3 = Vector3.ZERO
var _speed_sum: float = 0.0
var _speed_ticks: int = 0
var _broken: int = 0
var _tripod_speed: float = 0.0
var _slide_logged: bool = false
var _float_logged: bool = false
var _landed_at: float = -1.0
var _land_delay: float = -1.0


func _run() -> void:
	_build_world()
	await wait_physics(2)

	_enemy = _spawn(Vector3.ZERO)
	if _enemy == null:
		return
	await wait_physics(4)
	if not _check_rig():
		return
	_check_rest_pose()

	# El salto va primero, con el jefe entero: después de la marcha le faltan dos
	# patas y `planted_count() == 4` dejaría de tener sentido.
	Engine.time_scale = TIME_SCALE
	var delta := _enemy.get_physics_process_delta_time()
	print("  simulación: time_scale %.1f, delta de física %.4f s" % [Engine.time_scale, delta])
	await _check_leap()
	await _check_turn()

	_enemy.global_position = Vector3.ZERO
	_rig.snap_to_ground()
	await wait_physics(20)
	await _walk(WALK_SECONDS, true)
	Engine.time_scale = 1.0

	_report_walk()
	_check_building()
	await _check_relief()
	await _check_negative()


# --------------------------------------------------------------------------
# Mundo sintético
# --------------------------------------------------------------------------

## Arma llano, rampa, escalones, roca y los tres edificios de prueba.
func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	_add_box("Ground", Vector3(1400.0, 8.0, 1400.0), Vector3(0.0, -4.0, 0.0),
			Basis.IDENTITY, PhysicsLayers.WORLD)

	# Rampa de 20°: el centro se corre media altura por la normal para que la
	# cara superior arranque justo en (RAMP_START_X, 0) y suba hacia +X.
	var angle := deg_to_rad(RAMP_ANGLE)
	var slope := Vector3(cos(angle), sin(angle), 0.0)
	var normal := Vector3(-sin(angle), cos(angle), 0.0)
	var surface_mid := Vector3(RAMP_START_X, 0.0, 0.0) + slope * (RAMP_LENGTH * 0.5)
	_add_box("Ramp", Vector3(RAMP_LENGTH, RAMP_THICKNESS, RAMP_WIDTH),
			surface_mid - normal * (RAMP_THICKNESS * 0.5),
			Basis(Vector3.BACK, angle), PhysicsLayers.WORLD)

	# Tres escalones de 4 m hacia −X, cada uno más alto que el anterior.
	for index: int in 3:
		var top := STEP_RISE * float(index + 1)
		var center_x := STEP_FIRST_X - STEP_DEPTH * (float(index) + 0.5)
		_add_box("Step%d" % index, Vector3(STEP_DEPTH, top * 2.0, RAMP_WIDTH),
				Vector3(center_x, 0.0, 0.0), Basis.IDENTITY, PhysicsLayers.WORLD)

	_add_box("Rock", ROCK_SIZE, ROCK_CENTER, Basis.IDENTITY, PhysicsLayers.WORLD)

	_add_relief()

	for index: int in BUILDINGS.size():
		var building := TestBuilding.new()
		building.name = "TestBuilding%d" % index
		building.collision_layer = PhysicsLayers.CITY
		building.collision_mask = 0
		building.position = BUILDINGS[index]
		building.box = AABB(BUILDINGS[index] - BUILDING_SIZE * 0.5, BUILDING_SIZE)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = BUILDING_SIZE
		shape.shape = box
		building.add_child(shape)
		_world.add_child(building)
		_buildings.append(building)


## La cuarta superficie: un [HeightMapShape3D] de ruido sobre el llano.
##
## La rejilla la genera [method TownTerrain.from_noise], que es la misma técnica
## —dos [FastNoiseLite] sembrados— con la que `tools/build_terrain.gd` hornea el
## relieve del pueblo. Que la comparta importa: lo que este tramo mide no es «el
## rig sobre un heightfield cualquiera» sino el rig sobre **el tipo de suelo que
## el pueblo va a tener**.
##
## Se sube [constant RELIEF_AMPLITUDE] metros antes de desvanecer, para que el
## valle más hondo del parche quede en `y = 0` y nunca por debajo del llano: si
## bajara, el rayo de apoyo encontraría primero la caja del llano y el parche
## dejaría de ser el suelo que se está midiendo.
func _add_relief() -> void:
	var half := float(RELIEF_SAMPLES - 1) * RELIEF_CELL * 0.5
	_relief = TownTerrain.from_noise(RELIEF_SEED, RELIEF_SAMPLES, RELIEF_CELL,
			Vector2(RELIEF_CENTRE.x - half, RELIEF_CENTRE.z - half),
			RELIEF_WAVELENGTH, RELIEF_AMPLITUDE,
			RELIEF_AMPLITUDE + RELIEF_CLEARANCE, RELIEF_FADE)

	var body := StaticBody3D.new()
	body.name = "Relief"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	# El nodo **no se escala**: la forma de altura trabaja en unidades de
	# rejilla y a un metro por celda, y `docs/03` prohíbe escalar un cuerpo
	# estático. Sólo se traslada al centro del parche.
	body.position = Vector3(RELIEF_CENTRE.x, 0.0, RELIEF_CENTRE.z)
	var shape := CollisionShape3D.new()
	shape.shape = _relief.build_shape()
	body.add_child(shape)
	_world.add_child(body)

	var span := _relief.range_of()
	print("  cuarta superficie: heightfield %d² a %.0f m, ruido de %.0f m y ±%.1f m, alturas %.2f–%.2f m"
			% [RELIEF_SAMPLES, RELIEF_CELL, RELIEF_WAVELENGTH, RELIEF_AMPLITUDE,
			span.x, span.y])


## Un `StaticBody3D` con una caja, en la capa [param layer].
func _add_box(node_name: String, size: Vector3, origin: Vector3, basis: Basis,
		layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.transform = Transform3D(basis, origin)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	return body


## Instancia el jefe con la cadera ya a `hip_height` sobre [param ground].
func _spawn(ground: Vector3) -> EnemyBase:
	var scene := load(ENEMY_SCENE) as PackedScene
	if scene == null:
		fail("no se pudo cargar %s" % ENEMY_SCENE)
		return null
	var enemy := scene.instantiate() as EnemyBase
	if enemy == null:
		fail("la escena del jefe no es un EnemyBase")
		return null
	add_child(enemy)
	enemy.global_position = ground
	return enemy


## Cablea el rig y comprueba que es el de verdad, no el placeholder.
func _check_rig() -> bool:
	_rig = _enemy.locomotion as ProceduralLegRig
	if _rig == null:
		fail("el nodo Locomotion no es un ProceduralLegRig")
		return false
	if _rig.legs.size() != 4:
		fail("el rig midió %d patas, esperadas 4" % _rig.legs.size())
		return false
	if _rig.profile == null:
		fail("el rig no recibió el LegRigProfile del EnemyProfile")
		return false
	var _connected := _rig.leap_landed.connect(_on_leap_landed)
	return true


# --------------------------------------------------------------------------
# Pose de reposo
# --------------------------------------------------------------------------

## Comprueba la pose de arranque: cuatro pies en el suelo, cadera a
## `hip_height`, rodilla por encima del mínimo, trote y cadena sin estirar.
func _check_rest_pose() -> void:
	var hip := _hip_height()
	expect_near(hip, _enemy.profile.hip_height, HEIGHT_TOLERANCE,
			"altura de cadera en reposo")
	expect(_rig.planted_count() == 4,
			"patas apoyadas en reposo: %d, esperadas 4" % _rig.planted_count())
	expect(_rig.gait_name() == &"TROT",
			"marcha en reposo '%s', esperada 'TROT'" % _rig.gait_name())
	expect_near(_rig.speed_multiplier(), 1.0, 0.001, "speed_multiplier() con 4 patas")

	var stretched := 0
	var knee_sum := 0.0
	var knee_min := 1.0e9
	var span_max := 0.0
	for leg: Leg in _rig.legs:
		if leg.stretched:
			stretched += 1
		knee_sum += leg.tibia.global_position.y
		knee_min = minf(knee_min, leg.tibia.global_position.y)
		span_max = maxf(span_max, _span_ratio(leg))
	expect(stretched == 0, "%d patas nacen estiradas: la pose de marcha no alcanza" % stretched)
	expect(knee_min >= MIN_KNEE, "rodilla en reposo %.2f m, mínimo %.2f m" % [knee_min, MIN_KNEE])
	var rest := _rig.legs[0].rest_offset
	print("  pose de marcha: cadera %.2f m · rodilla %.2f m (mín %.2f) · planta %.2f m · fémur %.3f m · tibia %.3f m"
			% [hip, knee_sum / 4.0, knee_min, _rig.legs[0].sole_position().y,
			_rig.legs[0].femur_length, _rig.legs[0].tibia_length])
	print("  huella: reposo del pie (%.2f, %.2f) · cadena usada %.0f %% · radio %.2f m"
			% [rest.x, rest.z, span_max * 100.0, Vector2(rest.x, rest.z).length()])


## Altura de la cadera (media de los pivotes de fémur) sobre la media de los
## pies apoyados. Es lo que `docs/07` §2 llama `hip_height`.
func _hip_height() -> float:
	var hips := 0.0
	var soles := 0.0
	var count := 0
	var planted := 0
	for leg: Leg in _rig.legs:
		if leg.broken or not is_instance_valid(leg.femur):
			continue
		hips += leg.hip_world().y
		count += 1
		if leg.supports():
			soles += leg.plant_position.y
			planted += 1
	if count == 0 or planted == 0:
		return 0.0
	return hips / float(count) - soles / float(planted)


## Fracción de la cadena que consume el tramo cadera → tobillo de [param leg].
func _span_ratio(leg: Leg) -> float:
	if not is_instance_valid(leg.femur):
		return 0.0
	var span := leg.hip_world().distance_to(leg.plant_position + Vector3.UP * leg.ankle_lift)
	return span / maxf(leg.femur_length + leg.tibia_length, 0.01)


# --------------------------------------------------------------------------
# Marcha
# --------------------------------------------------------------------------

## Camina [param seconds] simulados siguiendo los puntos de paso, muestreando
## todas las métricas. Con [param scripted] rompe las dos rodillas del guion.
func _walk(seconds: float, scripted: bool) -> void:
	var elapsed := 0.0
	_last_body = _enemy.global_position
	_rig.reset_metrics()
	while elapsed < seconds:
		await get_tree().physics_frame
		var delta := _enemy.get_physics_process_delta_time()
		elapsed += delta
		_sample(delta)
		if scripted:
			_script_breaks(elapsed)
		_drive(delta)


## Manda la velocidad deseada hacia el punto de paso y gira el cuerpo. Es lo
## que hará el cerebro de WP-18; acá va escrito a mano para no depender de él.
func _drive(delta: float) -> void:
	if _rig.is_leaping():
		return
	var position := _enemy.global_position
	var goal := WAYPOINTS[_waypoint]
	var to_goal := Vector3(goal.x - position.x, 0.0, goal.y - position.z)
	if to_goal.length() < WAYPOINT_RADIUS:
		_waypoint = (_waypoint + 1) % WAYPOINTS.size()
		goal = WAYPOINTS[_waypoint]
		to_goal = Vector3(goal.x - position.x, 0.0, goal.y - position.z)
	var direction := to_goal.normalized()
	_enemy.face_toward(position + direction * 100.0, delta)
	# Sólo se avanza en la medida en que el cuerpo ya encara el objetivo: así el
	# coloso no patina de costado mientras gira a 25°/s.
	var facing := -_enemy.global_basis.z
	facing.y = 0.0
	var alignment := clampf(facing.normalized().dot(direction), 0.0, 1.0)
	var speed := _enemy.profile.walk_speed * _rig.speed_multiplier() * alignment
	_enemy.move_body(delta, direction * speed)


## Rompe las rodillas del guion en el segundo simulado que toca.
func _script_breaks(elapsed: float) -> void:
	if _broken == 0 and elapsed >= FIRST_BREAK:
		_break_knee(BREAK_KNEES[0])
	elif _broken == 1 and elapsed >= SECOND_BREAK:
		_break_knee(BREAK_KNEES[1])


## Rompe una rodilla como lo haría el arma (`docs/08` §2.7) y anota el estado.
func _break_knee(knee_id: StringName) -> void:
	var knee := _enemy.get_part(knee_id)
	if knee == null:
		fail("no existe la parte '%s'" % knee_id)
		_broken += 1
		return
	var _effective := knee.take_damage(knee.hp / maxf(1.0 - knee.armor, 0.01), {
		"position": knee.world_position(),
		"normal": Vector3.UP,
		"direction": Vector3.FORWARD,
		"source": self,
		"is_weak_point": true,
		"weak_point_id": knee_id,
		"damage_type": &"kinetic",
	})
	_broken += 1
	if _broken == 2:
		# La media acumulada desde la primera rotura es la velocidad con tres
		# patas (`docs/06` §16.2 y §8.7: ≥ 60 % de `walk_speed`).
		_tripod_speed = _speed_sum / float(maxi(_speed_ticks, 1))
		expect_near(_rig.speed_multiplier(), _rig.profile.drag_speed_factor, 0.001,
				"speed_multiplier() al perder la segunda pata")
	elif _broken == 1:
		expect_near(_rig.speed_multiplier(),
				1.0 - _enemy.profile.leg_speed_penalty, 0.001,
				"speed_multiplier() al perder la primera pata")
		expect(_rig.gait_name() == &"TRIPOD",
				"marcha con tres patas '%s', esperada 'TRIPOD'" % _rig.gait_name())
	_speed_sum = 0.0
	_speed_ticks = 0
	print("  rodilla '%s' rota: marcha '%s', speed_multiplier %.2f, patas apoyadas %d"
			% [knee_id, _rig.gait_name(), _rig.speed_multiplier(), _rig.planted_count()])


## Toma todas las medidas de un tick.
func _sample(delta: float) -> void:
	var body := _enemy.global_position
	var step := Vector3(body.x - _last_body.x, 0.0, body.z - _last_body.z).length()
	if not _rig.is_leaping():
		_metrics.max_body_step = maxf(_metrics.max_body_step, step)
		_speed_sum += step / delta
		_speed_ticks += 1
	_last_body = body

	if not _is_finite(body) or not _is_finite(_enemy.global_basis.get_euler()):
		_metrics.nan_ticks += 1

	var region := _region_for(body) if _broken == 0 else null
	# «En llano» es el origen **y** las cuatro patas a la misma altura: con el
	# cuerpo ya en el llano y una pata todavía sobre un escalón de 4 m, el plano
	# de apoyo está inclinado con toda razón y medir ahí el cabeceo de llano
	# sería medir la rampa.
	var flat := Vector2(body.x, body.z).length() < FLAT_RADIUS and _feet_level()
	var airborne_pairs: Dictionary[int, bool] = {}
	var planted := 0
	for leg: Leg in _rig.legs:
		if leg.broken:
			continue
		if not _is_finite(leg.sole_position()) or not _is_finite(leg.hip_world()):
			_metrics.nan_ticks += 1
		_sample_penetration(leg, delta)
		# Con patas rotas las métricas se acumulan aparte: el trípode y el
		# arrastre son modos degradados y `docs/06` §16.2 mide la marcha sana.
		var target := _metrics
		if _broken == 1:
			target = _tripod
		elif _broken >= 2:
			target = _drag
		var sole := leg.sole_position()

		if leg.is_airborne():
			_was_airborne[leg.index] = true
			# Contacto visual: cuánto lleva la planta pegada a su objetivo antes
			# de que el rig declare el apoyo (métrica 9).
			if sole.y - leg.target.y <= CONTACT_EPS:
				_contact_hold[leg.index] = _contact_hold.get(leg.index, 0.0) + delta
			else:
				_contact_hold[leg.index] = 0.0
			airborne_pairs[_pair_of(leg.index)] = true
			var _erased := _anchors.erase(leg.index)
			_float_time[leg.index] = 0.0
			continue

		if bool(_was_airborne.get(leg.index, false)):
			_was_airborne[leg.index] = false
			var delay := float(_contact_hold.get(leg.index, 0.0))
			_contact_hold[leg.index] = 0.0
			target.contact_events += 1
			target.max_contact_delay = maxf(target.max_contact_delay, delay)

		planted += 1
		if not _anchors.has(leg.index):
			_anchors[leg.index] = sole
		var slide := Vector3(sole.x - _anchors[leg.index].x, 0.0,
				sole.z - _anchors[leg.index].z).length()
		if slide > target.max_slide:
			target.max_slide = slide
			target.slide_offender = leg.side
			target.slide_trace = _snapshot(leg)
		if region != null:
			region.max_slide = maxf(region.max_slide, slide)
		if slide > MAX_SLIDE and not _slide_logged and _broken == 0:
			_slide_logged = true
			_trace("deslizamiento", leg)
		var lift := sole.y - leg.plant_position.y
		if lift > target.max_float:
			target.float_trace = _snapshot(leg)
		target.max_float = maxf(target.max_float, lift)
		if region != null:
			region.max_float = maxf(region.max_float, lift)
		if lift > FLOAT_HEIGHT:
			_float_time[leg.index] = _float_time.get(leg.index, 0.0) + delta
			if _float_time[leg.index] > target.max_float_time:
				target.max_float_time = _float_time[leg.index]
				target.float_offender = leg.side
			if _float_time[leg.index] > MAX_FLOAT_TIME and not _float_logged and _broken == 0:
				_float_logged = true
				_trace("flotación", leg)
		else:
			_float_time[leg.index] = 0.0

		# Rodilla y cabeceo se miden **sólo en llano y con las cuatro patas**:
		# en rampa la rodilla baja por geometría y el cabeceo es el de §16.2.
		if flat and _broken == 0 and is_instance_valid(leg.tibia):
			var knee := leg.tibia.global_position.y - leg.plant_position.y
			if knee < _metrics.min_knee:
				_metrics.min_knee = knee
				_metrics.knee_trace = _snapshot(leg)
	if region != null:
		region.ticks += 1

	if not _rig.is_leaping():
		# El criterio 3 de `docs/06` §16.2 se mide **con las cuatro patas sanas**:
		# arrastrándose con dos, tener una sola apoyada es lo correcto.
		if _broken == 0:
			_metrics.min_planted = mini(_metrics.min_planted, planted)
		if airborne_pairs.size() > 1:
			_metrics.pair_violations += 1

	var tilt := rad_to_deg(_enemy.global_basis.y.angle_to(Vector3.UP))
	if body.x > RAMP_SAMPLE_MIN and body.x < RAMP_SAMPLE_MAX and absf(body.z) < 20.0:
		_metrics.ramp_tilt_sum += tilt
		_metrics.ramp_tilt_count += 1
	elif flat and _broken == 0:
		_metrics.flat_height_sum += _hip_height()
		_metrics.flat_height_count += 1
		_metrics.max_flat_tilt = maxf(_metrics.max_flat_tilt, tilt)


## `true` si las patas apoyadas están todas a la misma altura, con
## [constant LEVEL_TOLERANCE] de holgura.
func _feet_level() -> bool:
	var lowest := INF
	var highest := -INF
	for leg: Leg in _rig.legs:
		if leg.broken or leg.is_airborne():
			continue
		lowest = minf(lowest, leg.plant_position.y)
		highest = maxf(highest, leg.plant_position.y)
	if lowest > highest:
		return false
	return highest - lowest <= LEVEL_TOLERANCE


## Acumula cuánto lleva la tibia o el pie de [param leg] dentro de un edificio.
##
## Se muestrea la tibia en tres puntos —rodilla, medio y tobillo— y la planta:
## con un edificio de 26 m de lado y una tibia de 6 m, cuatro muestras no dejan
## pasar una penetración que se vea.
func _sample_penetration(leg: Leg, delta: float) -> void:
	if _buildings.is_empty() or leg.tibia == null or not is_instance_valid(leg.tibia):
		return
	var knee := leg.tibia.global_position
	var ankle := leg.foot.global_position if is_instance_valid(leg.foot) else knee
	var points: Array[Vector3] = [knee, knee.lerp(ankle, 0.5), ankle, leg.sole_position()]
	var inside := false
	for building: TestBuilding in _buildings:
		for point: Vector3 in points:
			if building.contains(point, 0.25):
				inside = true
				break
		if inside:
			break
	if inside:
		_inside_time[leg.index] = _inside_time.get(leg.index, 0.0) + delta
		if _inside_time[leg.index] > _metrics.max_penetration:
			_metrics.max_penetration = _inside_time[leg.index]
			_metrics.penetration_trace = _snapshot(leg)
	else:
		_inside_time[leg.index] = 0.0


## Terreno en el que está el cuerpo, para el desglose informativo.
func _region_for(body: Vector3) -> Region:
	var key := &"llano"
	if body.x > RAMP_START_X:
		key = &"rampa"
	elif body.x < STEP_FIRST_X:
		key = &"escalones"
	elif body.z > 30.0:
		key = &"edificios"
	if not _regions.has(key):
		var region := Region.new()
		region.label = String(key)
		_regions[key] = region
	return _regions[key]


## Índice del par diagonal de una pata, tal como lo armó el [GaitController].
func _pair_of(leg_index: int) -> int:
	return _rig.pair_of(leg_index)


## Vuelca el contexto la **primera** vez que una métrica se sale de umbral. Sin
## esto, un fallo en los 120 s de marcha es un número sin historia.
func _trace(label: String, leg: Leg) -> void:
	print("  primer exceso de %s: %s" % [label, _snapshot(leg)])


## Foto del rig en este tick: quién, dónde, con qué marcha y cuánta cadena gasta
## cada pata. Es lo que convierte un máximo en un diagnóstico.
func _snapshot(leg: Leg) -> String:
	var line := "pata %s, cuerpo %s, cadera %.2f m, marcha %s, estado %s, patas %d" % [
			leg.side, _enemy.global_position.round(), _hip_height(),
			_rig.gait_name(), _rig.locomotion_state(), 4 - _broken]
	for other: Leg in _rig.legs:
		# Una pata rota se va como escombro: sus nodos ya no existen y pedirles
		# la transformada sería un error de script en mitad del volcado.
		var knee := 0.0
		if is_instance_valid(other.tibia):
			knee = other.tibia.global_position.y - other.plant_position.y
		line += " | %s p=%d t=%.2f cad=%.0f%% rod=%.1f plant=%s" % [other.side,
				1 if other.planted else 0, other.step_t, _span_ratio(other) * 100.0,
				knee, other.plant_position.round()]
	return line


## `true` si las tres componentes son finitas.
func _is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


# --------------------------------------------------------------------------
# Veredictos
# --------------------------------------------------------------------------

## Vuelca las métricas de los 120 s y las contrasta con `docs/06` §16.2 y con
## los umbrales de marcha creíble de WP-24d.
func _report_walk() -> void:
	var rig_usec := _rig.average_tick_usec()
	print("  deslizamiento máximo %.3f m (%s) · flotación máxima %.3f m · flotación sostenida %.3f s (%s)"
			% [_metrics.max_slide, _metrics.slide_offender, _metrics.max_float,
			_metrics.max_float_time, _metrics.float_offender])
	print("  inclinación en rampa %.2f° (%d muestras) · cadera en llano %.2f m (%d muestras)"
			% [_metrics.ramp_tilt(), _metrics.ramp_tilt_count, _metrics.flat_height(),
			_metrics.flat_height_count])
	print("  paso máximo de move_body %.3f m · patas apoyadas mínimas %d · rig_tick medio %.1f µs"
			% [_metrics.max_body_step, _metrics.min_planted, rig_usec])
	print("  contacto → apoyo %.3f s (%d apoyos) · rodilla mínima en llano %.2f m · cabeceo en llano %.2f°"
			% [_metrics.max_contact_delay, _metrics.contact_events,
			_metrics.min_knee, _metrics.max_flat_tilt])
	print("  tibia dentro de un edificio intacto %.3f s" % _metrics.max_penetration)
	if not _metrics.slide_trace.is_empty():
		print("  peor deslizamiento: %s" % _metrics.slide_trace)
	if not _metrics.float_trace.is_empty():
		print("  peor flotación: %s" % _metrics.float_trace)
	if not _tripod.slide_trace.is_empty():
		print("  peor deslizamiento en trípode: %s" % _tripod.slide_trace)
	if not _metrics.knee_trace.is_empty():
		print("  rodilla más baja: %s" % _metrics.knee_trace)
	if not _metrics.penetration_trace.is_empty():
		print("  peor penetración: %s" % _metrics.penetration_trace)
	for key: StringName in _regions:
		var region: Region = _regions[key]
		print("  terreno %-10s: deslizamiento %.3f m · flotación %.3f m (%d ticks)"
				% [region.label, region.max_slide, region.max_float, region.ticks])
	print("  trípode (3 patas): deslizamiento %.3f m · flotación sostenida %.3f s"
			% [_tripod.max_slide, _tripod.max_float_time])
	print("  arrastre (2 patas): deslizamiento %.3f m · flotación sostenida %.3f s"
			% [_drag.max_slide, _drag.max_float_time])
	expect(_tripod.max_slide < MAX_SLIDE_TRIPOD,
			"deslizamiento en trípode %.3f m, tope %.2f m"
			% [_tripod.max_slide, MAX_SLIDE_TRIPOD])
	expect(_tripod.max_float_time <= MAX_FLOAT_TIME,
			"pie flotando en trípode %.3f s, tope %.2f s"
			% [_tripod.max_float_time, MAX_FLOAT_TIME])

	expect(_metrics.max_slide < MAX_SLIDE,
			"deslizamiento de pie %.3f m, tope %.2f m" % [_metrics.max_slide, MAX_SLIDE])
	expect(_metrics.max_float_time <= MAX_FLOAT_TIME,
			"pie flotando %.3f s por encima de %.2f m, tope %.2f s"
			% [_metrics.max_float_time, FLOAT_HEIGHT, MAX_FLOAT_TIME])
	expect(_metrics.pair_violations == 0,
			"los dos pares diagonales estuvieron en el aire en %d ticks"
			% _metrics.pair_violations)
	expect(_metrics.min_planted >= 2,
			"en algún tick sólo hubo %d patas apoyadas" % _metrics.min_planted)
	expect(_metrics.nan_ticks == 0,
			"%d ticks con NaN o INF en las transformadas" % _metrics.nan_ticks)
	expect(_metrics.max_body_step <= _enemy.profile.max_step_per_tick + 0.0001,
			"paso de move_body %.4f m, tope %.2f m"
			% [_metrics.max_body_step, _enemy.profile.max_step_per_tick])
	expect(_metrics.ramp_tilt_count > 0, "el jefe nunca llegó a la rampa de 20°")
	expect(_metrics.ramp_tilt() >= RAMP_TILT_MIN and _metrics.ramp_tilt() <= RAMP_TILT_MAX,
			"inclinación en rampa %.2f°, banda [%.0f°, %.0f°]"
			% [_metrics.ramp_tilt(), RAMP_TILT_MIN, RAMP_TILT_MAX])
	expect(_metrics.flat_height_count > 0, "no hubo muestras de altura en llano")
	expect_near(_metrics.flat_height(), _enemy.profile.hip_height, HEIGHT_TOLERANCE,
			"altura de cadera en llano")
	expect(rig_usec < MAX_RIG_USEC,
			"rig_tick medio %.1f µs, tope %.0f µs" % [rig_usec, MAX_RIG_USEC])

	# Marcha creíble (WP-24d).
	expect(_metrics.contact_events > 0, "no se midió ni un apoyo")
	expect(_metrics.max_contact_delay <= MAX_CONTACT_DELAY,
			"el pie tocó el suelo %.3f s antes de declararse apoyado, tope %.2f s"
			% [_metrics.max_contact_delay, MAX_CONTACT_DELAY])
	expect(_metrics.min_knee >= MIN_KNEE,
			"rodilla mínima en llano %.2f m, mínimo %.2f m" % [_metrics.min_knee, MIN_KNEE])
	expect(_metrics.max_flat_tilt <= MAX_FLAT_TILT,
			"cabeceo en llano %.2f°, tope %.1f°" % [_metrics.max_flat_tilt, MAX_FLAT_TILT])
	expect(_metrics.max_penetration <= MAX_PENETRATION,
			"una tibia estuvo %.3f s dentro de un edificio intacto, tope %.2f s"
			% [_metrics.max_penetration, MAX_PENETRATION])

	# Cojera y arrastre (`docs/06` §8.3 y §8.7).
	expect(_broken == 2, "el guion rompió %d rodillas, esperadas 2" % _broken)
	expect_near(_rig.speed_multiplier(), _rig.profile.drag_speed_factor, 0.001,
			"speed_multiplier() con dos patas perdidas")
	expect(_rig.gait_name() == &"DRAG",
			"marcha con dos patas '%s', esperada 'DRAG'" % _rig.gait_name())
	var drag := _speed_sum / float(maxi(_speed_ticks, 1))
	print("  velocidad media arrastrando %.2f m/s (objetivo %.2f m/s)"
			% [drag, _enemy.profile.walk_speed * _rig.profile.drag_speed_factor])
	expect(_tripod_speed >= _enemy.profile.walk_speed * TRIPOD_SPEED_RATIO,
			"velocidad con tres patas %.2f m/s, mínimo %.2f m/s"
			% [_tripod_speed, _enemy.profile.walk_speed * TRIPOD_SPEED_RATIO])


## Los edificios de prueba tienen que haber cobrado `crush_damage` al ser
## pisados.
func _check_building() -> void:
	var damage := _rig.profile.crush_damage
	var hits := 0
	var total := 0.0
	for building: TestBuilding in _buildings:
		hits += building.hits
		total += building.total
	print("  edificios de prueba: %d apoyos, %.0f de daño acumulado" % [hits, total])
	expect(hits > 0, "el jefe nunca apoyó un pie sobre un edificio de capa 8")
	if hits > 0:
		expect_near(total / float(hits), damage, 0.01,
				"daño por apoyo sobre el edificio")


## Giro de 180° en el lugar, en llano: ningún pie apoyado puede deslizar más de
## [constant MAX_TURN_SLIDE] (WP-24d métrica 12).
##
## El cuerpo **no avanza**: sólo gira. Es el caso que más cadena consume, porque
## el pie viaja de costado, justo en la dirección en la que la pata ya nace
## separada del cuerpo.
func _check_turn() -> void:
	_enemy.global_position = Vector3.ZERO
	_enemy.global_basis = Basis.IDENTITY
	_rig.snap_to_ground()
	await wait_physics(30)

	var anchors: Dictionary[int, Vector3] = {}
	var worst := 0.0
	var offender: StringName = &""
	var elapsed := 0.0
	var turned := 0.0
	var last_yaw := _yaw_of(_enemy)
	while elapsed < TURN_SECONDS and turned < PI:
		await get_tree().physics_frame
		var delta := _enemy.get_physics_process_delta_time()
		elapsed += delta
		_enemy.face_toward(Vector3(0.0, 0.0, 200.0), delta)
		_enemy.move_body(delta, Vector3.ZERO)
		var yaw := _yaw_of(_enemy)
		turned += absf(wrapf(yaw - last_yaw, -PI, PI))
		last_yaw = yaw
		for leg: Leg in _rig.legs:
			if leg.broken:
				continue
			if leg.is_airborne():
				var _erased := anchors.erase(leg.index)
				continue
			var sole := leg.sole_position()
			if not anchors.has(leg.index):
				anchors[leg.index] = sole
			var slide := Vector3(sole.x - anchors[leg.index].x, 0.0,
					sole.z - anchors[leg.index].z).length()
			if slide > worst:
				worst = slide
				offender = leg.side
	print("  giro en el lugar: %.0f° en %.2f s simulados · deslizamiento máximo %.3f m (%s)"
			% [rad_to_deg(turned), elapsed, worst, offender])
	expect(turned >= PI * 0.98,
			"el giro sólo cubrió %.0f° en %.1f s" % [rad_to_deg(turned), TURN_SECONDS])
	expect(worst < MAX_TURN_SLIDE,
			"deslizamiento en el giro de 180° %.3f m, tope %.2f m" % [worst, MAX_TURN_SLIDE])


## Cuarta superficie (WP-T2): el jefe cruza el parche de relieve de ida y
## vuelta entre los dos puntos de paso, y se le exigen los **mismos umbrales que
## al tramo de rampa** —deslizamiento de pie apoyado < [constant MAX_SLIDE] y
## ningún pie flotando más de [constant MAX_FLOAT_TIME]— más una inclinación
## acotada y un recorrido mínimo, para que un jefe clavado no pase en verde.
##
## Es el tramo que responde a la pregunta que abre P2c: si el pueblo deja de ser
## plano, ¿la marcha procedural sigue apoyando? El parche tiene el mismo tipo de
## suelo que el terreno horneado (ruido de 30 m y ±1,5 m, o sea pendientes de
## hasta 17°) y, a diferencia de la rampa, **cambia de pendiente bajo cada
## pata**: es el caso que un plano inclinado no cubre.
func _check_relief() -> void:
	if _relief == null:
		fail("no se construyó la cuarta superficie")
		return
	# Con un jefe **nuevo**, y después de la ronda de 120 s, no dentro de ella.
	#
	# El rig es una máquina de fase: meter treinta segundos de marcha en medio
	# de la ronda corre el ciclo de trote de todas las patas, y la ronda de
	# después deja de ser la misma. Se comprobó midiéndolo: con la travesía
	# intercalada antes de `_walk`, la métrica 13 —tibia dentro de un edificio
	# intacto— saltaba de 0,12 s a 0,96 s sin que nada del rig hubiese cambiado.
	# El relieve no puede pagar esa factura, así que se mide al final y sobre una
	# instancia limpia, igual que hace la prueba negativa. Las catorce métricas
	# anteriores vuelven a medir exactamente lo que medían.
	var start := RELIEF_WAYPOINTS[0]
	var ground := Vector3(start.x, _relief.height_at(start.x, start.y), start.y)
	if not await _respawn(ground):
		return
	_enemy.global_basis = Basis.IDENTITY
	_rig.snap_to_ground()
	Engine.time_scale = TIME_SCALE
	await wait_physics(30)

	var anchors: Dictionary[int, Vector3] = {}
	var ankles: Dictionary[int, Vector3] = {}
	var floating: Dictionary[int, float] = {}
	var worst_slide := 0.0
	var worst_level := 0.0
	var worst_sloped := 0.0
	var worst_slope := 0.0
	var worst_stretched := false
	var any_stretched := false
	var worst_straight := 0.0
	var worst_ankle := 0.0
	var turning_ticks := 0
	var last_yaw := _yaw_of(_enemy)
	var slide_offender: StringName = &""
	var worst_float := 0.0
	var float_offender: StringName = &""
	var worst_tilt := 0.0
	var min_planted := 99
	var travelled := 0.0
	var target := 1
	var elapsed := 0.0
	var logged := false
	var last := _enemy.global_position

	while elapsed < RELIEF_SECONDS:
		await get_tree().physics_frame
		var delta := _enemy.get_physics_process_delta_time()
		elapsed += delta

		var body := _enemy.global_position
		travelled += Vector2(body.x - last.x, body.z - last.z).length()
		last = body

		var goal := RELIEF_WAYPOINTS[target]
		var to_goal := Vector3(goal.x - body.x, 0.0, goal.y - body.z)
		if to_goal.length() < WAYPOINT_RADIUS:
			target = (target + 1) % RELIEF_WAYPOINTS.size()
			goal = RELIEF_WAYPOINTS[target]
			to_goal = Vector3(goal.x - body.x, 0.0, goal.y - body.z)
		var direction := to_goal.normalized()
		_enemy.face_toward(body + direction * 100.0, delta)
		var facing := -_enemy.global_basis.z
		facing.y = 0.0
		var alignment := clampf(facing.normalized().dot(direction), 0.0, 1.0)
		_enemy.move_body(delta, direction * _enemy.profile.walk_speed * alignment)

		worst_tilt = maxf(worst_tilt,
				rad_to_deg(_enemy.global_basis.y.angle_to(Vector3.UP)))
		var yaw := _yaw_of(_enemy)
		var yaw_rate := absf(wrapf(yaw - last_yaw, -PI, PI)) / maxf(delta, 0.0001)
		last_yaw = yaw
		var turning := yaw_rate > RELIEF_TURN_RATE
		if turning:
			turning_ticks += 1
		var planted := 0
		for leg: Leg in _rig.legs:
			if leg.broken:
				continue
			if leg.is_airborne():
				var _erased := anchors.erase(leg.index)
				var _dropped := ankles.erase(leg.index)
				floating[leg.index] = 0.0
				continue
			planted += 1
			var sole := leg.sole_position()
			if not anchors.has(leg.index):
				anchors[leg.index] = sole
			var slide := Vector3(sole.x - anchors[leg.index].x, 0.0,
					sole.z - anchors[leg.index].z).length()
			var plant_slope := rad_to_deg(_relief.slope_at(
					leg.plant_position.x, leg.plant_position.z))
			if plant_slope < 3.0:
				worst_level = maxf(worst_level, slide)
			else:
				worst_sloped = maxf(worst_sloped, slide)
			if slide > worst_slide:
				worst_slide = slide
				slide_offender = leg.side
				worst_slope = plant_slope
				worst_stretched = leg.stretched
			any_stretched = any_stretched or leg.stretched
			if not turning:
				worst_straight = maxf(worst_straight, slide)
			# El tobillo es **el apoyo**: si no se mueve, el pie no resbaló,
			# por mucho que la planta gire alrededor de él.
			if is_instance_valid(leg.foot):
				var ankle := leg.foot.global_position
				if not ankles.has(leg.index):
					ankles[leg.index] = ankle
				worst_ankle = maxf(worst_ankle, Vector3(ankle.x - ankles[leg.index].x,
						0.0, ankle.z - ankles[leg.index].z).length())
			if slide > MAX_SLIDE and not logged:
				logged = true
				print("  primer exceso sobre el relieve (girando %s, %.2f rad/s): %s"
						% ["sí" if turning else "no", yaw_rate, _snapshot(leg)])
			if sole.y - leg.plant_position.y > FLOAT_HEIGHT:
				floating[leg.index] = floating.get(leg.index, 0.0) + delta
				if floating[leg.index] > worst_float:
					worst_float = floating[leg.index]
					float_offender = leg.side
			else:
				floating[leg.index] = 0.0
		min_planted = mini(min_planted, planted)

	var span := _relief.range_of()
	print("  relieve: %.0f m recorridos en %.1f s simulados sobre un parche de %.2f m de desnivel"
			% [travelled, elapsed, span.y - span.x])
	print("  relieve: planta %.3f m (%s) · planta en recta %.3f m · tobillo %.3f m · %d ticks girando"
			% [worst_slide, slide_offender, worst_straight, worst_ankle, turning_ticks])
	print("  relieve: apoyos con pendiente < 3° → %.3f m · apoyos en pendiente → %.3f m · peor apoyo a %.1f° (cadena estirada: %s)"
			% [worst_level, worst_sloped, worst_slope,
			"sí" if worst_stretched else "no"])
	print("  relieve: flotación sostenida %.3f s (%s) · inclinación %.2f° · patas apoyadas mínimas %d"
			% [worst_float, float_offender, worst_tilt, min_planted])
	expect(travelled >= RELIEF_MIN_TRAVEL,
			"el jefe sólo recorrió %.0f m sobre el relieve, mínimo %.0f m"
			% [travelled, RELIEF_MIN_TRAVEL])
	expect(not any_stretched,
			"sobre el relieve la cadena de alguna pata llegó estirada al apoyo")
	expect(worst_slide < RELIEF_SOLE_SWING,
			"balanceo de la planta sobre el relieve %.3f m, tope %.2f m"
			% [worst_slide, RELIEF_SOLE_SWING])
	expect(worst_float <= MAX_FLOAT_TIME,
			"pie flotando sobre el relieve %.3f s por encima de %.2f m, tope %.2f s"
			% [worst_float, FLOAT_HEIGHT, MAX_FLOAT_TIME])
	expect(worst_tilt <= RELIEF_TILT_MAX,
			"inclinación sobre el relieve %.2f°, tope %.0f°" % [worst_tilt, RELIEF_TILT_MAX])
	expect(min_planted >= 2,
			"sobre el relieve hubo un tick con sólo %d patas apoyadas" % min_planted)
	Engine.time_scale = 1.0


## Cambia el jefe por una instancia nueva apoyada en [param ground] y vuelve a
## cablear el rig. Lo usan la travesía del relieve y la prueba negativa: las dos
## necesitan un coloso entero después de que la ronda le rompiera dos rodillas.
func _respawn(ground: Vector3) -> bool:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	await wait_frames(2)
	_anchors.clear()
	_float_time.clear()
	_contact_hold.clear()
	_was_airborne.clear()
	_inside_time.clear()
	_enemy = _spawn(ground)
	if _enemy == null:
		return false
	await wait_physics(4)
	_rig = _enemy.locomotion as ProceduralLegRig
	if _rig == null:
		fail("la instancia nueva no trae ProceduralLegRig")
		return false
	return true


## Rumbo del cuerpo, leído del eje frontal de la base.
func _yaw_of(node: Node3D) -> float:
	var forward := -node.global_basis.z
	return atan2(-forward.x, -forward.z)


## Salto sobre la roca: cuatro pies apoyados en menos de [constant LEAP_BUDGET],
## y en menos de [constant LAND_PLANT_BUDGET] desde que el cuerpo toca.
func _check_leap() -> void:
	_enemy.global_position = Vector3(ROCK_CENTER.x, 0.0, ROCK_CENTER.z - 34.0)
	_rig.snap_to_ground()
	await wait_physics(30)

	var landing := Vector3(ROCK_CENTER.x, ROCK_CENTER.y + ROCK_SIZE.y * 0.5, ROCK_CENTER.z)
	var started := Time.get_ticks_usec()
	var elapsed := 0.0
	var tuck := _rig.profile.leap_tuck_time
	_landed_at = -1.0
	_land_delay = -1.0
	_rig.jump(landing)
	expect(_rig.is_leaping(), "jump() no arrancó el salto")
	while elapsed < LEAP_BUDGET and _rig.is_leaping():
		await get_tree().physics_frame
		var delta := _enemy.get_physics_process_delta_time()
		elapsed += delta
		if _landed_at >= 0.0:
			_landed_at += delta
			if _land_delay < 0.0 and _rig.planted_count() == 4:
				_land_delay = _landed_at
	# Se mide justo al salir del salto: pasada la recuperación el rig ya empieza
	# a recolocar los pies con pasos normales y habría patas en el aire de nuevo.
	var planted := _rig.planted_count()
	var states := ""
	for leg: Leg in _rig.legs:
		states += " %s(p=%d t=%.2f)" % [leg.side, 1 if leg.planted else 0, leg.step_t]
	print("  salto: %.2f s simulados (recogida %.2f s), %d pies apoyados%s, cuerpo en %s, %.1f ms reales"
			% [elapsed, tuck, planted, states, _enemy.global_position.round(),
			float(Time.get_ticks_usec() - started) / 1000.0])
	print("  aterrizaje: las 4 patas apoyadas %.3f s después de tocar" % maxf(_land_delay, 0.0))
	expect(elapsed < LEAP_BUDGET, "el salto tardó %.2f s, tope %.1f s" % [elapsed, LEAP_BUDGET])
	expect(planted == 4, "tras el salto quedaron %d pies apoyados, esperados 4" % planted)
	expect(_land_delay >= 0.0 and _land_delay <= LAND_PLANT_BUDGET,
			"tras tocar el suelo las 4 patas tardaron %.3f s en apoyar, tope %.2f s"
			% [_land_delay, LAND_PLANT_BUDGET])
	expect(Vector2(_enemy.global_position.x - landing.x,
			_enemy.global_position.z - landing.z).length() < 12.0,
			"el jefe aterrizó a %.1f m del objetivo"
			% Vector2(_enemy.global_position.x - landing.x,
			_enemy.global_position.z - landing.z).length())


## Arranca el reloj del aterrizaje en cuanto el rig avisa que el cuerpo tocó.
func _on_leap_landed(_position: Vector3) -> void:
	_landed_at = 0.0


## Prueba negativa: con `step_trigger` a 30 m el pie no puede seguir al cuerpo y
## las métricas 1 y 2 tienen que dispararse. Si no lo hacen, el check no estaría
## midiendo nada.
func _check_negative() -> void:
	_metrics = Metrics.new()
	_tripod = Metrics.new()
	_drag = Metrics.new()
	_waypoint = 0
	_broken = 0
	_slide_logged = false
	_float_logged = false
	if not await _respawn(Vector3.ZERO):
		return
	# Se desarman los **dos** disparadores de paso: el de distancia al reposo y
	# el de alcance de la cadena. Con `reach_trigger` en `stretch_max` la pata
	# sólo pide paso cuando ya no llega, que es tarde.
	var broken_profile := _rig.profile.duplicate() as LegRigProfile
	broken_profile.step_trigger = NEGATIVE_TRIGGER
	broken_profile.turn_step_trigger = NEGATIVE_TRIGGER
	broken_profile.reach_trigger = broken_profile.stretch_max
	_rig.profile = broken_profile

	Engine.time_scale = TIME_SCALE
	await _walk(NEGATIVE_SECONDS, false)
	Engine.time_scale = 1.0

	var slid := _metrics.max_slide >= MAX_SLIDE
	var floated := _metrics.max_float_time > MAX_FLOAT_TIME
	print("  prueba negativa (step_trigger %.0f m): deslizamiento %.3f m, flotación sostenida %.3f s"
			% [NEGATIVE_TRIGGER, _metrics.max_slide, _metrics.max_float_time])
	expect(slid or floated,
			"la prueba negativa no rompió ninguna métrica: deslizamiento %.3f m, flotación %.3f s"
			% [_metrics.max_slide, _metrics.max_float_time])
	if slid or floated:
		print("  prueba negativa: FALLA como se esperaba (%s)"
				% ("deslizamiento" if slid else "flotación"))
