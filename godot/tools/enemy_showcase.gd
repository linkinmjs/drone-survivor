## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Vista rápida del Arachnodroid a escala real. **No es un check**: no afirma
## nada ni devuelve códigos de salida; existe para mirar al coloso y comprobar a
## ojo lo que ningún umbral captura — que el haz de asedio se lee desde lejos,
## que el decal del pisotón cae donde el pie, que la carcasa se abre de verdad y
## que el emisivo blanco de P5 pulsa cada vez más rápido.
##
## Guion de la toma (acumuladores, nunca un [Timer]):
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
## quiere ver elegir objetivo.
##
## Captura con Movie Maker, desde la raíz del repositorio:
## [codeblock]
## godot --path godot --windowed --resolution 960x540 \
##     --write-movie <dir>/a.png --fixed-fps 10 --quit-after 440 \
##     res://tools/enemy_showcase.tscn
## [/codeblock]
##
## Son 440 fotogramas a 10 fps — 44 s. Los que hay que mirar son el **125**
## (columna del asedio), el **150** (haz ámbar del asedio), el **198** (decal del
## pisotón), el **258** (haz blanco-cian del láser), el **305** (salto en el
## aire), el **375** (carcasa abierta) y el **425** (detonación).
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

## Edificios de la toma: nombre, posición en XZ y `value` (`docs/10` §4.2). El de
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

## Desplazamiento de la cámara respecto del jefe. Es una vista **de perfil**
## desde su izquierda: la que deja ver los pares de patas alternando, la columna
## del asedio entera y la parábola del salto.
const CAMERA_OFFSET: Vector3 = Vector3(-72.0, 26.0, 10.0)

## Punto al que mira la cámara, relativo al jefe.
const CAMERA_LOOK: Vector3 = Vector3(0.0, 12.0, -8.0)

## Ritmo con el que la cámara persigue al jefe, en s⁻¹.
const CAMERA_RATE: float = 2.5

## Campo de visión vertical.
const CAMERA_FOV: float = 48.0

## Posición desde la que apunta el sol, del lado de la cámara para que la cara
## delantera del coloso quede iluminada y no en contraluz.
const SUN_POSITION: Vector3 = Vector3(-120.0, 100.0, -40.0)

## Perfil del que salen los edificios de la toma.
const BUILDING_PROFILE: String = "res://city/profiles/low_block.tres"

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


func _ready() -> void:
	_camera = get_node_or_null(^"Camera3D") as Camera3D
	if _camera != null:
		_camera.fov = CAMERA_FOV

	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	if sun != null:
		sun.look_at_from_position(SUN_POSITION, Vector3(0.0, 12.0, -40.0), Vector3.UP)

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
	_park_attacks(true)
	_build_buildings()
	_camera_anchor = _enemy.global_position
	_aim_camera()


## Lleva el guion de la toma. Acumulador, nunca un [Timer] (`docs/00` §6).
func _physics_process(delta: float) -> void:
	if _enemy == null:
		return
	_elapsed += delta
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
# Guion
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

## Persigue al jefe con un acumulador exponencial y lo encuadra de perfil.
func _aim_camera(delta: float = -1.0) -> void:
	if _camera == null or _enemy == null:
		return
	var target := _enemy.global_position
	if delta > 0.0:
		_camera_anchor = _camera_anchor.lerp(target, 1.0 - exp(-CAMERA_RATE * delta))
	else:
		_camera_anchor = target
	_camera.look_at_from_position(_camera_anchor + CAMERA_OFFSET,
			_camera_anchor + CAMERA_LOOK, Vector3.UP)


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
