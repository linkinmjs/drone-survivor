## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Vista rápida del Arachnodroid a escala real. **No es un check**: no afirma
## nada ni devuelve códigos de salida; existe para mirar al coloso y comprobar a
## ojo lo que ningún umbral captura — que el haz de asedio se lee desde lejos,
## que el decal del pisotón cae donde el pie, que la carcasa se abre de verdad,
## que el emisivo blanco de P5 pulsa cada vez más rápido y —desde WP-24d— que la
## marcha se ve creíble.
##
## [b]Dos guiones[/b], por el argumento de usuario `--scene`:
##
## - `--scene=combat` (por defecto): el guion de WP-19, con los cuatro ataques,
##   las cinco roturas y la detonación.
## - `--scene=gait` (WP-24d): siete actos de locomoción pura —reposo, marcha
##   recta, giro de 180°, rampa de 20°, escalones de 4 m, trepado a un edificio
##   de capa 8 y salto— sin un solo ataque. Es el material con el que se juzga
##   la marcha fotograma a fotograma.
##
## [b]Tres encuadres[/b], por `--cam`: `side` (lateral a nivel de calle, 60 m),
## `aerial` (3/4 aéreo a 40 m de alto) y `chase` (detrás y arriba, siguiendo el
## rumbo real del jefe). Los dos primeros se orientan con el rumbo **nominal del
## acto**, no con el instantáneo, para que durante el giro la cámara se quede
## quieta y el giro se vea; el tercero persigue de verdad.
##
## Guion de `combat` (acumuladores, nunca un [Timer]):
##
## | Segundo | Qué pasa |
## |---|---|
## | 0 – 2 | el jefe arranca quieto: se ve la pose de marcha con la cadera a 14 m |
## | 2 – 11 | camina hacia la torre; polvo y grietas por pisada |
## | 11 – 18.3 | `siege_beam`: columna de luz sobre la torre y 4 s de haz |
## | 16 | aparece el dron de prueba, bajo y cerca |
## | 19 – 21.2 | `stomp`: decal rojo, pata a 1.6 × `hip_height` y cráter |
## | 22 | se rompe la primera rodilla → **P2** y cae la pata |
## | 23 – 27.6 | `head_laser`: línea guía, **haz blanco-cian** y el visor expuesto |
## | 27.5 | se rompe la segunda rodilla → **P3**, emisivos rojos, marcha `DRAG` |
## | 29 – 33.5 | `pounce`: parábola guía, vuelo balístico y onda de aterrizaje |
## | 35 | se rompe la tercera → **P4**: la carcasa se abre 70° y el jefe queda postrado |
## | 38 | se rompen dos núcleos → **P5**: emisivo blanco pulsante y cuenta atrás |
## | 42 | `detonate()`: los edificios a ≤ 120 m se llevan los 25 000 |
##
## Guion de `gait` (`GAIT_ACTS`): cada acto teletransporta al jefe al terreno que
## le toca y le pide [method ProceduralLegRig.snap_to_ground], así cada tramo
## empieza limpio y los fotogramas de un acto no arrastran el anterior.
##
## | Segundo | Acto |
## |---|---|
## | 0 – 6 | `idle`: quieto en llano (respiración de servos) |
## | 6 – 20 | `walk`: marcha recta a `walk_speed` |
## | 20 – 30 | `turn`: giro de 180° en el lugar |
## | 30 – 42 | `ramp`: rampa de 20° |
## | 42 – 52 | `steps`: tres escalones de 4 m |
## | 52 – 62 | `climb`: trepado a un edificio de capa 8 |
## | 62 – 72 | `leap`: salto sobre una roca |
##
## [b]El modelo de patas del MVP[/b] (decisión del orquestador al cerrar WP-19):
## cada rodilla rota se lleva la pata entera (`docs/07` §4), así que la toma
## atraviesa `TROT` → `TRIPOD` (P2) → `DRAG` (P3) → postrado (P4). `pounce` sale
## en P3 desde el arrastre, con dos patas apoyadas, que es el mínimo que pide al
## entrar en `ACTIVE`; y en P4 el jefe ya no camina, sólo abre la carcasa y
## espera el reloj.
##
## [b]Por qué los ataques se conducen a mano[/b]: el selector es ponderado y
## sembrado (`docs/06` §10), así que dejarlo suelto daría una toma distinta por
## semilla y el guion no podría prometer que en el segundo 25 se ve el láser. La
## IA sí decide sola la caminata de los primeros 11 s —con el resto del move set
## apartado, para que no meta un asedio antes de tiempo—, que es donde se la
## quiere ver elegir objetivo. En `gait` la IA está apagada del todo: el guion
## conduce el cuerpo con `face_toward()` y `move_body()`, como hace `gait_check`.
##
## Captura con Movie Maker, desde la raíz del repositorio:
## [codeblock]
## godot --path godot --windowed --resolution 1280x720 \
##     --write-movie <dir>/a.png --fixed-fps 10 --quit-after 720 \
##     res://tools/enemy_showcase.tscn -- --scene=gait --cam=side
## [/codeblock]
##
## En `combat` son 440 fotogramas a 10 fps — 44 s. Los que hay que mirar son el
## **125** (columna del asedio), el **150** (haz ámbar del asedio), el **198**
## (decal del pisotón), el **258** (haz blanco-cian del láser), el **305** (salto
## en el aire), el **375** (carcasa abierta) y el **425** (detonación). En `gait`
## son 720 y los fotogramas son los bordes de acto: **60** (reposo), **120**
## (marcha en régimen), **240** (giro), **340** (rampa), **460** (escalones),
## **570** (trepado) y **660** (salto).
extends Node3D

## Segundo en el que arranca la marcha autónoma.
const WALK_DELAY: float = 2.0

## Segundo en el que aparece el dron de prueba.
const DRONE_DELAY: float = 16.0

## Guion de ataques: segundo de disparo → id de la acción.
const ATTACKS: Array[Dictionary] = [
	{"at": 11.0, "id": &"siege_beam"},
	{"at": 19.0, "id": &"stomp"},
	{"at": 23.0, "id": &"head_laser"},
	{"at": 29.0, "id": &"pounce"},
]

## Guion de roturas: segundo → punto débil. Las tres rodillas llevan a P4 y los
## dos núcleos a P5 (`docs/07` §6).
const BREAKS: Array[Dictionary] = [
	{"at": 22.0, "id": &"wp_leg_fr_knee"},
	{"at": 27.5, "id": &"wp_leg_fl_knee"},
	{"at": 35.0, "id": &"wp_leg_br_knee"},
	{"at": 38.0, "id": &"wp_core_a"},
	{"at": 38.4, "id": &"wp_core_b"},
]

## Segundo en el que se fuerza la detonación. La cuenta atrás real son 45 s
## (`docs/07` §6) y la toma dura 44: se la adelanta para que el clímax entre.
const DETONATE_DELAY: float = 42.0

## Edificios de la toma, nombre, posición en XZ y `value` (`docs/10` §4.2). El de
## 300 es el que el cerebro tiene que elegir, y está del lado de la cámara.
const BUILDINGS: Array[Dictionary] = [
	{"name": "Block_Left", "at": Vector2(-64.0, 26.0), "value": 100},
	{"name": "Block_Far", "at": Vector2(84.0, -28.0), "value": 150},
	{"name": "Tower_Main", "at": Vector2(0.0, -92.0), "value": 300},
]

## Huella y altura de los edificios de la toma, en metros.
##
## Son torres **angostas** a propósito: con una huella de más de 12 m de radio los
## pies delanteros terminarían sobre el techo en cuanto el jefe se acerque, el
## rig pasaría a trepar y la toma se quedaría sin la caminata.
const BUILDING_SIZE: Vector3 = Vector3(10.0, 30.0, 10.0)

## HP del edificio principal. El asedio le quita 2 800 por ráfaga y cada apoyo de
## pie 900: con 9 000 HP la torre cruza el umbral de `DAMAGED` con el primer haz
## y suelta polvo y escombros sin derrumbarse del todo.
const BUILDING_HP: float = 9000.0

## Punto del mundo en el que aparece el dron de prueba: entre el jefe y la torre,
## bajo y cerca, para que el pisotón y el láser lo alcancen.
const DRONE_SPAWN: Vector3 = Vector3(11.0, 5.0, -62.0)

## Ritmo con el que la cámara persigue al jefe, en s⁻¹.
const CAMERA_RATE: float = 2.5

## Ritmo con el que la cámara gira hacia el rumbo del acto, en s⁻¹. Es lento a
## propósito: una cámara que siguiera el rumbo instantáneo escondería el giro.
const CAMERA_TURN_RATE: float = 1.2

## Los tres encuadres de `--cam`, en el marco {derecha, arriba, frente} del acto.
##
## `follow` a `true` hace que el encuadre use el rumbo **real** del jefe en vez
## del nominal del acto: es lo que convierte a `chase` en una cámara de
## persecución y deja a las otras dos quietas mientras el coloso gira.
const CAMERAS: Dictionary = {
	&"side": {
		"right": -60.0, "up": 9.0, "forward": 0.0,
		"look_up": 13.0, "look_forward": 0.0, "fov": 46.0, "follow": false,
	},
	&"aerial": {
		"right": -30.0, "up": 40.0, "forward": -30.0,
		"look_up": 8.0, "look_forward": 0.0, "fov": 46.0, "follow": false,
	},
	&"chase": {
		"right": 0.0, "up": 30.0, "forward": -52.0,
		"look_up": 12.0, "look_forward": 14.0, "fov": 52.0, "follow": true,
	},
}

## Encuadre por defecto cuando no se pasa `--cam`.
const DEFAULT_CAMERA: StringName = &"side"

## Perfil del que salen los edificios de la toma.
const BUILDING_PROFILE: String = "res://city/profiles/low_block.tres"

# --------------------------------------------------------------------------
# Guion de locomoción (`--scene=gait`, WP-24d)
# --------------------------------------------------------------------------

## Los siete actos de `gait`. `from` es el punto al que se teletransporta el jefe
## al empezar el acto, `face` el rumbo nominal (que además orienta las cámaras
## `side` y `aerial`), `goal` el punto de paso al que camina y `spin` marca el
## acto de giro, en el que no se avanza.
const GAIT_ACTS: Array[Dictionary] = [
	{"at": 0.0, "id": &"idle", "from": Vector3(0.0, 0.0, 0.0),
		"face": Vector2(1.0, 0.0), "goal": Vector2(0.0, 0.0)},
	{"at": 6.0, "id": &"walk", "from": Vector3(-36.0, 0.0, 0.0),
		"face": Vector2(1.0, 0.0), "goal": Vector2(52.0, 0.0)},
	{"at": 20.0, "id": &"turn", "from": Vector3(0.0, 0.0, 0.0),
		"face": Vector2(1.0, 0.0), "goal": Vector2(-200.0, 0.0), "spin": true},
	{"at": 30.0, "id": &"ramp", "from": Vector3(48.0, 0.0, 0.0),
		"face": Vector2(1.0, 0.0), "goal": Vector2(170.0, 0.0)},
	{"at": 42.0, "id": &"steps", "from": Vector3(-24.0, 0.0, 0.0),
		"face": Vector2(-1.0, 0.0), "goal": Vector2(-140.0, 0.0)},
	{"at": 52.0, "id": &"climb", "from": Vector3(0.0, 0.0, 52.0),
		"face": Vector2(0.0, 1.0), "goal": Vector2(0.0, 118.0)},
	{"at": 62.0, "id": &"leap", "from": Vector3(0.0, 0.0, -74.0),
		"face": Vector2(0.0, -1.0), "goal": Vector2(0.0, -74.0), "jump": true},
]

## Segundo, dentro del acto `leap`, en el que se dispara el salto.
const GAIT_JUMP_AT: float = 2.0

## Rampa del acto `ramp`: 20°, 120 m de largo, arrancando en x = 60.
const RAMP_ANGLE: float = 20.0
const RAMP_LENGTH: float = 130.0
const RAMP_START_X: float = 60.0
const RAMP_WIDTH: float = 90.0
const RAMP_THICKNESS: float = 8.0

## Escalones del acto `steps`: tres de 4 m hacia −X.
const STEP_RISE: float = 4.0
const STEP_DEPTH: float = 34.0
const STEP_FIRST_X: float = -44.0

## Edificio trepable del acto `climb`, en capa 8, con el techo a 10 m.
const CLIMB_SIZE: Vector3 = Vector3(34.0, 10.0, 34.0)
const CLIMB_CENTER: Vector3 = Vector3(0.0, 5.0, 118.0)

## Roca del acto `leap`: caja de 34 × 12 × 34 m en capa 1.
##
## Es **más ancha que la huella de marcha** (22 m desde WP-24d) a propósito: con
## una roca de 16 m los cuatro pies caían a los lados y el coloso aterrizaba a
## horcajadas, con la roca dentro del casco. Con 34 m de lado el salto termina
## como tiene que verse, con las cuatro patas sobre la piedra.
const ROCK_SIZE: Vector3 = Vector3(34.0, 12.0, 34.0)
const ROCK_CENTER: Vector3 = Vector3(0.0, 6.0, -124.0)

## Distancia a la que se da por alcanzado un punto de paso, en metros.
const WAYPOINT_RADIUS: float = 6.0

var _elapsed: float = 0.0
var _attack_cursor: int = 0
var _break_cursor: int = 0
var _drone_on: bool = false
var _detonated: bool = false

var _enemy: Arachnodroid = null
var _rig: ProceduralLegRig = null
var _brain: EnemyFSM = null
var _perception: Perception = null
var _library: AttackLibrary = null
var _telegraph: Telegraph = null
var _drone: RigidBody3D = null
var _last_state: StringName = &""
var _parked: Dictionary[StringName, AttackProfile] = {}
var _camera: Camera3D = null
var _camera_anchor: Vector3 = Vector3.ZERO
var _camera_forward: Vector3 = Vector3.FORWARD
var _framing: Dictionary = {}
var _gait_mode: bool = false
var _act_cursor: int = -1
var _act_started: float = 0.0
var _jumped: bool = false
var _last_locomotion: StringName = &""


func _ready() -> void:
	var args := _user_args()
	_gait_mode = String(args.get("scene", "combat")) == "gait"
	var key := StringName(args.get("cam", String(DEFAULT_CAMERA)))
	if not CAMERAS.has(key):
		key = DEFAULT_CAMERA
	_framing = CAMERAS[key] as Dictionary

	_camera = get_node_or_null(^"Camera3D") as Camera3D
	if _camera != null:
		_camera.fov = float(_framing["fov"])

	# El sol y la exposición son los compartidos (`docs/13` §3.2, WP-24): el nodo
	# `Sun` lleva `world/sun_dusk.tres` y `Graphics` le vuelca encima la tabla de
	# sombras del preset de calidad. El showcase tenía los suyos —2.4 × 100 000
	# lux contra f/16 e ISO 100— y la toma salía siete pasos fuera de la
	# calibración de `world/environment_battle.tres`, que es el entorno que
	# comparte con el nivel de batalla.
	Graphics.register_sun(get_node_or_null(^"Sun") as DirectionalLight3D)

	_enemy = get_node_or_null(^"Arachnodroid") as Arachnodroid
	if _enemy == null:
		push_error("enemy_showcase: falta el nodo 'Arachnodroid'.")
		return
	_rig = _enemy.locomotion as ProceduralLegRig
	_brain = _enemy.brain as EnemyFSM
	_perception = _enemy.perception as Perception
	_library = _enemy.get_node_or_null(^"AttackLibrary") as AttackLibrary
	_telegraph = _enemy.get_node_or_null(^"Telegraph") as Telegraph
	if _brain != null:
		var _changed := _brain.action_changed.connect(_on_action_changed)
	var _phase := _enemy.phase_changed.connect(_on_phase_changed)
	var _tick := _enemy.selfdestruct_tick.connect(_on_selfdestruct_tick)

	if _gait_mode:
		_park_attacks(true)
		if _brain != null:
			_brain.autonomous = false
		_build_gait_world()
		print("enemy_showcase: guion 'gait', encuadre '%s'" % key)
	else:
		_park_attacks(true)
		_build_buildings()
		print("enemy_showcase: guion 'combat', encuadre '%s'" % key)

	_camera_forward = Vector3(0.0, 0.0, -1.0)
	_camera_anchor = _enemy.global_position
	_aim_camera()


## Lleva el guion de la toma. Acumulador, nunca un [Timer] (`docs/00` §6).
func _physics_process(delta: float) -> void:
	if _enemy == null:
		return
	_elapsed += delta
	if _gait_mode:
		_advance_gait(delta)
		_aim_camera(delta)
		return

	if not _drone_on and _elapsed >= DRONE_DELAY:
		_drone_on = true
		_spawn_drone()
	# La caminata la decide la IA; los ataques y las roturas van por guion.
	if _brain != null:
		_brain.autonomous = _elapsed >= WALK_DELAY and _attack_cursor == 0
	_advance_attacks()
	_advance_breaks()
	if not _detonated and _elapsed >= DETONATE_DELAY:
		_detonated = true
		if _enemy.is_selfdestructing():
			print("enemy_showcase: %5.1f s · detonación forzada (quedaban %.1f s)"
					% [_elapsed, _enemy.selfdestruct_remaining()])
			_enemy.detonate()
	_aim_camera(delta)


# --------------------------------------------------------------------------
# Guion de locomoción
# --------------------------------------------------------------------------

## Avanza el acto que toque y conduce el cuerpo a mano.
func _advance_gait(delta: float) -> void:
	var wanted := _act_cursor
	for index: int in GAIT_ACTS.size():
		if _elapsed >= float(GAIT_ACTS[index]["at"]):
			wanted = index
	if wanted != _act_cursor:
		_act_cursor = wanted
		_enter_act(GAIT_ACTS[_act_cursor])
	if _act_cursor < 0:
		return
	_drive_act(GAIT_ACTS[_act_cursor], delta)
	_trace_locomotion()


## Coloca al jefe donde toca y deja el rig en pose de marcha.
func _enter_act(act: Dictionary) -> void:
	_jumped = false
	_act_started = _elapsed
	var face := act["face"] as Vector2
	_enemy.global_position = act["from"] as Vector3
	_enemy.global_basis = Basis(Vector3.UP, atan2(-face.x, -face.y))
	if _rig != null:
		_rig.release_all_legs()
		_rig.clear_crouch()
		_rig.snap_to_ground()
	_camera_forward = Vector3(face.x, 0.0, face.y).normalized()
	_camera_anchor = _enemy.global_position
	print("enemy_showcase: %5.1f s · acto '%s' desde %s"
			% [_elapsed, act["id"], str(_enemy.global_position.round())])


## Un tick del acto en curso: girar, avanzar y, en `leap`, saltar.
func _drive_act(act: Dictionary, delta: float) -> void:
	if _rig != null and _rig.is_leaping():
		return
	if bool(act.get("jump", false)):
		if not _jumped and _elapsed - _act_started >= GAIT_JUMP_AT:
			_jumped = true
			if _rig != null:
				_rig.jump(Vector3(ROCK_CENTER.x,
						ROCK_CENTER.y + ROCK_SIZE.y * 0.5, ROCK_CENTER.z))
			return
		if _jumped:
			return

	var origin := _enemy.global_position
	var goal := act["goal"] as Vector2
	var to_goal := Vector3(goal.x - origin.x, 0.0, goal.y - origin.z)
	if to_goal.length() < WAYPOINT_RADIUS:
		_enemy.move_body(delta, Vector3.ZERO)
		return
	var direction := to_goal.normalized()
	_enemy.face_toward(origin + direction * 100.0, delta)
	if bool(act.get("spin", false)):
		# El acto de giro **no avanza**: se queda girando en el sitio, que es
		# donde se ve si los pies patinan o dan pasos cortos.
		_enemy.move_body(delta, Vector3.ZERO)
		return
	var facing := -_enemy.global_basis.z
	facing.y = 0.0
	var alignment := 0.0
	if not facing.is_zero_approx():
		alignment = clampf(facing.normalized().dot(direction), 0.0, 1.0)
	var speed := _enemy.profile.walk_speed * alignment
	if _rig != null:
		speed *= _rig.speed_multiplier()
	_enemy.move_body(delta, direction * speed)


## Arma rampa, escalones, edificio trepable y roca del guion `gait`.
func _build_gait_world() -> void:
	var angle := deg_to_rad(RAMP_ANGLE)
	var slope := Vector3(cos(angle), sin(angle), 0.0)
	var normal := Vector3(-sin(angle), cos(angle), 0.0)
	var surface_mid := Vector3(RAMP_START_X, 0.0, 0.0) + slope * (RAMP_LENGTH * 0.5)
	_add_box("Ramp", Vector3(RAMP_LENGTH, RAMP_THICKNESS, RAMP_WIDTH),
			surface_mid - normal * (RAMP_THICKNESS * 0.5), Basis(Vector3.BACK, angle),
			PhysicsLayers.WORLD, Color(0.22, 0.24, 0.27))

	for index: int in 3:
		var top := STEP_RISE * float(index + 1)
		var center_x := STEP_FIRST_X - STEP_DEPTH * (float(index) + 0.5)
		_add_box("Step%d" % index, Vector3(STEP_DEPTH, top * 2.0, RAMP_WIDTH),
				Vector3(center_x, 0.0, 0.0), Basis.IDENTITY, PhysicsLayers.WORLD,
				Color(0.24, 0.25, 0.28))

	_add_box("Rock", ROCK_SIZE, ROCK_CENTER, Basis.IDENTITY, PhysicsLayers.WORLD,
			Color(0.30, 0.27, 0.24))
	# El edificio del trepado va en capa `city` para que el rayo de apoyo lo
	# encuentre y el rig reporte `CLIMB` por su cuenta (`docs/06` §8.4).
	_add_box("ClimbBlock", CLIMB_SIZE, CLIMB_CENTER, Basis.IDENTITY,
			PhysicsLayers.CITY, Color(0.30, 0.32, 0.38))


## Un `StaticBody3D` con caja y malla, en la capa [param layer].
func _add_box(node_name: String, size: Vector3, origin: Vector3, basis: Basis,
		layer: int, tint: Color) -> void:
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

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.92
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)


## Traza los cambios de la capa de locomoción, para leer la toma desde consola.
func _trace_locomotion() -> void:
	if _rig == null:
		return
	var state := _rig.locomotion_state()
	if state == _last_locomotion:
		return
	_last_locomotion = state
	print("enemy_showcase: %5.1f s · locomoción %s / %s · apoyadas %d · cuerpo %s"
			% [_elapsed, state, _rig.gait_name(), _rig.planted_count(),
			str(_enemy.global_position.round())])


# --------------------------------------------------------------------------
# Guion de combate
# --------------------------------------------------------------------------

## Lanza el ataque que toque, si la capa de acción está libre.
func _advance_attacks() -> void:
	if _attack_cursor >= ATTACKS.size() or _brain == null:
		return
	var entry := ATTACKS[_attack_cursor]
	if _elapsed < float(entry["at"]):
		return
	if _brain.action_state() != EnemyFSM.ACTION_NONE or _enemy.is_staggered():
		return
	if _attack_cursor == 0:
		# Se acabó la caminata libre: el move set vuelve al selector para que los
		# ataques del guion se resuelvan con sus alcances de verdad.
		_park_attacks(false)
	_attack_cursor += 1
	var action := _library.find(entry["id"] as StringName)
	if action == null:
		push_error("enemy_showcase: no existe la acción '%s'." % entry["id"])
		return
	# El cerebro está apagado, así que su caché de contexto es la de la última
	# vez que pensó: sin refrescarla, el ataque apuntaría adonde estaba el dron
	# hace diez segundos.
	var _ctx := _brain.refresh_context()
	action.mark_started()
	var payload: Dictionary = {&"action": action, &"telegraph": _telegraph}
	var state := EnemyFSM.ACTION_TELEGRAPH if action.telegraph_seconds() > 0.0 \
			else EnemyFSM.ACTION_ACTIVE
	var _started := _brain.request_action(state, payload)
	print("enemy_showcase: %5.1f s · %s (aviso %.2f s)"
			% [_elapsed, action.id(), action.telegraph_seconds()])


## Aparta del selector todo lo que no sea `approach`, o se lo devuelve.
##
## Durante la caminata el cerebro tiene que poder elegir objetivo —eso es lo que
## la toma quiere mostrar— pero no lanzar un asedio siete segundos antes de que
## el guion lo pida: la toma promete fotogramas concretos y con nueve acciones
## compitiendo cada uno caería donde quisiera la semilla.
func _park_attacks(parked: bool) -> void:
	if _library == null:
		return
	for action: EnemyAction in _library.get_actions():
		if action.id() == &"approach" or action.profile == null:
			continue
		if parked:
			if not _parked.has(action.id()):
				_parked[action.id()] = action.profile
				var patched := action.profile.duplicate() as AttackProfile
				patched.min_range = 0.0
				patched.max_range = 0.0
				action.profile = patched
		elif _parked.has(action.id()):
			action.profile = _parked[action.id()]
	if not parked:
		_parked.clear()


## Rompe el punto débil que toque, como lo haría el arma (`docs/08` §2.7).
func _advance_breaks() -> void:
	if _break_cursor >= BREAKS.size():
		return
	var entry := BREAKS[_break_cursor]
	if _elapsed < float(entry["at"]):
		return
	_break_cursor += 1
	var part_id := entry["id"] as StringName
	var part := _enemy.get_part(part_id)
	if part == null or part.is_broken():
		return
	var _effective := part.take_damage(part.hp / maxf(1.0 - part.armor, 0.01), {
		"position": part.world_position(),
		"normal": Vector3.UP,
		"direction": Vector3(0.0, 0.0, 1.0),
		"source": self,
		"is_weak_point": true,
		"weak_point_id": part_id,
		"damage_type": &"kinetic",
	})
	print("enemy_showcase: %5.1f s · '%s' roto" % [_elapsed, part_id])


# --------------------------------------------------------------------------
# Mundo
# --------------------------------------------------------------------------

## Los tres edificios de la toma, en la capa `city` y en el grupo `buildings`:
## son los que el cerebro mira para elegir objetivo (`docs/06` §10.1).
func _build_buildings() -> void:
	var source := ResourceLoader.load(BUILDING_PROFILE, "Resource") as BuildingProfile
	if source == null:
		push_error("enemy_showcase: falta %s." % BUILDING_PROFILE)
		return
	var pool := get_node_or_null(^"DebrisPool") as DebrisPool
	for entry: Dictionary in BUILDINGS:
		var profile := source.duplicate() as BuildingProfile
		profile.value = int(entry["value"])
		profile.max_hp = BUILDING_HP

		var building := Building.new()
		building.name = String(entry["name"])
		building.collision_layer = PhysicsLayers.CITY
		building.collision_mask = 0
		building.profile = profile
		building.base_size = BUILDING_SIZE
		building.debris_pool = pool
		var spot := entry["at"] as Vector2
		building.position = Vector3(spot.x, 0.0, spot.y)

		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box_mesh := BoxMesh.new()
		box_mesh.size = BUILDING_SIZE
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.28, 0.30, 0.35)
		material.roughness = 0.9
		box_mesh.material = material
		mesh.mesh = box_mesh
		mesh.position = Vector3(0.0, BUILDING_SIZE.y * 0.5, 0.0)
		building.add_child(mesh)
		building.stage_intact = mesh
		building.intact_rest_transform = mesh.transform

		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = BUILDING_SIZE
		shape.shape = box
		building.add_child(shape)
		building.intact_shape = shape
		add_child(building)


## Suelta un dron de prueba delante del jefe para que la percepción lo vea y los
## ataques dirigidos tengan a quién apuntar.
func _spawn_drone() -> void:
	_drone = RigidBody3D.new()
	_drone.name = "TestDrone"
	_drone.collision_layer = PhysicsLayers.DRONE
	_drone.collision_mask = 0
	_drone.gravity_scale = 0.0
	_drone.freeze = true
	_drone.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.4, 1.2)
	shape.shape = box
	_drone.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.2, 0.4, 1.2)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.9, 0.95)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.9, 1.0)
	box_mesh.material = material
	mesh.mesh = box_mesh
	_drone.add_child(mesh)
	add_child(_drone)

	_drone.global_position = DRONE_SPAWN
	if _perception != null:
		_perception.set_target(_drone)
	print("enemy_showcase: %5.1f s · dron de prueba en %s"
			% [_elapsed, str(_drone.global_position)])


# --------------------------------------------------------------------------
# Cámara y log
# --------------------------------------------------------------------------

## Persigue al jefe con un acumulador exponencial y lo encuadra según `--cam`.
##
## El marco es {derecha, arriba, frente}: con el frente del acto —o el real, en
## `chase`— los tres encuadres quedan definidos por tres escalares y valen igual
## para los dos guiones.
func _aim_camera(delta: float = -1.0) -> void:
	if _camera == null or _enemy == null:
		return
	var target := _enemy.global_position
	var wanted := _camera_forward
	if bool(_framing.get("follow", false)):
		var facing := -_enemy.global_basis.z
		facing.y = 0.0
		if not facing.is_zero_approx():
			wanted = facing.normalized()
	if delta > 0.0:
		_camera_anchor = _camera_anchor.lerp(target, 1.0 - exp(-CAMERA_RATE * delta))
		_camera_forward = _camera_forward.slerp(wanted,
				1.0 - exp(-CAMERA_TURN_RATE * delta)).normalized()
	else:
		_camera_anchor = target
		_camera_forward = wanted

	var forward := _camera_forward
	var right := forward.cross(Vector3.UP).normalized()
	var position := _camera_anchor \
			+ right * float(_framing["right"]) \
			+ Vector3.UP * float(_framing["up"]) \
			+ forward * float(_framing["forward"])
	var look := _camera_anchor \
			+ Vector3.UP * float(_framing["look_up"]) \
			+ forward * float(_framing["look_forward"])
	_camera.look_at_from_position(position, look, Vector3.UP)


## Argumentos de usuario `--clave=valor`, con el mismo parseo que `CheckRunner`.
func _user_args() -> Dictionary:
	var parsed: Dictionary = {}
	for raw: String in OS.get_cmdline_user_args():
		var arg := raw
		while arg.begins_with("-"):
			arg = arg.substr(1)
		if arg.is_empty():
			continue
		var separator := arg.find("=")
		if separator >= 0:
			parsed[arg.substr(0, separator)] = arg.substr(separator + 1)
		else:
			parsed[arg] = "true"
	return parsed


## Traza los cambios de la capa de acción, para leer la toma desde la consola.
func _on_action_changed(from: StringName, to: StringName) -> void:
	if to == _last_state:
		return
	_last_state = to
	var action := _brain.current_action()
	print("enemy_showcase: %5.1f s · acción %s → %s (%s)"
			% [_elapsed, from, to, action.id() if action != null else &"—"])


func _on_phase_changed(phase_id: StringName) -> void:
	print("enemy_showcase: %5.1f s · FASE %s" % [_elapsed, phase_id])


func _on_selfdestruct_tick(remaining: float) -> void:
	# Un tic de cada cinco: el ritmo sube de 1 a 6 Hz y el log se llenaría.
	if _enemy.selfdestruct_ticks() % 5 != 0:
		return
	print("enemy_showcase: %5.1f s · autodestrucción %.1f s" % [_elapsed, remaining])
