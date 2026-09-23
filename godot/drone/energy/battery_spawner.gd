## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Reparte y repone las pilas del distrito (`docs/09` §2.5).
##
## Es un [Node3D] con una lista de puestos —[Marker3D]— de los que mantiene
## [member active_target] activos. No busca nodos por ruta ni por nombre: recorre
## hijos en orden de árbol, que es lo que hace que el orden sea estable entre
## ejecuciones y, con la misma semilla, la secuencia de puestos sea reproducible.
##
## ## De dónde salen los puestos, y por qué arrancar vacío es normal
##
## Los pone **el barrio**: el distrito trae un `BatteryPosts` y
## `RoundManager._adopt_district_markers()` se lo pasa a [method adopt_markers].
## Los hijos propios de la escena son sólo el respaldo de un nivel que no instancie
## distrito, y en `battle_level.tscn` ya no hay ninguno.
##
## Por eso [method _ready] **no** se queja de quedarse sin puestos: en el nivel de
## batalla eso es el estado normal durante el resto de ese mismo cuadro, hasta que
## `RoundManager.begin()` —que corre en el `_ready()` del nivel, o sea después que
## el de este nodo— llame a la adopción. Quejarse ahí llenaba de un `ERROR` por
## carga a `balance_check`, `render_check`, Movie Maker y CI, avisando de algo que
## se arreglaba solo un instante después.
##
## La comprobación está **diferida al primer uso**: el aviso sale de
## [method _physics_process], que es el primer momento en que este nodo tiene que
## repartir pilas de verdad, y para entonces la adopción ya pasó. Sale una sola vez
## por ronda —lo cuenta [method empty_warnings]— y es un `push_warning`, no un
## `push_error`: una ronda sin pilas se juega peor, pero se juega.
##
## **Una pila por marcador, encendida o apagada**. Se instancian tantas
## [BatteryPickup] como marcadores y cada una queda anclada al suyo; activar es
## encender la que corresponde. Es más barato que crear y liberar nodos —una pila
## apagada no monitorea, no se dibuja y no procesa— y deja `get_active_count()`
## como una simple cuenta.
##
## **Semilla**: el [RandomNumberGenerator] se siembra con `Global.round_seed`. Dos
## rondas con la misma semilla activan la misma secuencia de marcadores, que es lo
## que pide `energy_check` §5 sub-check 22 y lo que hace rejugable una semilla.
##
## **Espacio libre** (`docs/09` §2.5): antes de activar se lanza un
## `intersect_shape` con una esfera de [member clearance_radius] sobre la máscara
## `8|9` = 384 (`city` y `debris`). Nunca se fuerza una aparición dentro de
## geometría: si todos los marcadores libres están tapados se reintenta cada
## [member retry_interval]. Un marcador sepultado bajo una ruina deja de usarse
## solo, sin lógica adicional.
##
## **Discrepancia registrada con `docs/09`**: §2.5 dice que al recogerse una pila
## «un acumulador de 25 s reactiva **otra**», en singular, pero §5 sub-check 20
## pide que tras recoger dos y avanzar 25 s vuelva a haber **cinco**. Gana el
## sub-check, que es el criterio verificable: el acumulador es **uno solo** y, al
## vencer, rellena hasta [member active_target] de una vez.
class_name BatterySpawner extends Node3D

## Escena de la pila. Si queda vacía se carga [constant DEFAULT_PICKUP_SCENE].
@export var pickup_scene: PackedScene

## Batería del dron que reciben las pilas de este spawner. Si queda vacía se busca
## en el grupo `drone_rig` del nivel, y si no, por duck typing en el árbol.
@export var energy_system: EnergySystem

## Cuántas pilas se mantienen activas a la vez.
@export_range(1, 16) var active_target: int = 5

## Segundos que tarda el relleno después de que se recoja una pila.
@export_range(0.0, 120.0) var respawn_delay: float = 25.0

## Radio de la esfera con la que se comprueba que el marcador esté despejado.
@export_range(0.5, 10.0) var clearance_radius: float = 2.5

## Segundos hasta el siguiente intento cuando todos los marcadores libres están
## bloqueados.
@export_range(0.1, 10.0) var retry_interval: float = 1.0

## Capas que bloquean una aparición: 8 (`city`) y 9 (`debris`).
@export_flags_3d_physics var clearance_mask: int = 384

## Escena por defecto de la pila.
const DEFAULT_PICKUP_SCENE: String = "res://drone/energy/battery_pickup.tscn"

var _markers: Array[Marker3D] = []
var _pickups: Array[BatteryPickup] = []
var _active: PackedInt32Array = PackedInt32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _clearance_shape: SphereShape3D = SphereShape3D.new()
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _accumulator: float = 0.0
var _next_delay: float = 0.0
var _active_count: int = 0
var _used_markers: PackedInt32Array = PackedInt32Array()

## Veces que avisó que llegó al juego sin puestos, en esta ronda. Es un contador y
## no un `bool` para que `energy_check` pueda distinguir «no avisó» de «avisó una
## vez» sin tener que leer la consola.
var _empty_warnings: int = 0


func _ready() -> void:
	_collect_markers()
	if energy_system == null:
		energy_system = _find_energy_system()
	_build_pickups()
	_configure_query()
	reset()


## Relleno por acumulador (`docs/09` §1: nunca un [Timer]).
##
## El primer relleno sale en el primer tick porque [member _next_delay] arranca en
## cero; los siguientes esperan [member respawn_delay], y un intento bloqueado por
## geometría vuelve a intentarlo en [member retry_interval].
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	if _markers.is_empty():
		# Primer uso real sin puestos: acá sí es un problema, porque la adopción ya
		# tuvo su oportunidad. Ver la cabecera.
		_warn_empty()
		return
	PerfProbe.begin(&"drone_energy")
	if _active_count >= active_target:
		_accumulator = 0.0
	else:
		_accumulator += delta
		if _accumulator >= _next_delay:
			_accumulator = 0.0
			_fill()
			_next_delay = respawn_delay if _active_count >= active_target else retry_interval
	PerfProbe.end(&"drone_energy")


# --- Interfaz pública (`docs/09` §3.4) --------------------------------------------------------

## Pilas encendidas en este momento.
func get_active_count() -> int:
	return _active_count


## Marcadores candidatos que encontró en [method _ready].
func get_marker_count() -> int:
	return _markers.size()


## Veces que este spawner avisó que se quedó sin puestos, en la ronda en curso.
##
## Lo mira `energy_check`: con la adopción pendiente —el caso normal del nivel de
## batalla— tiene que quedar en **cero**, y ese cero es lo que prueba que arrancar
## vacío dejó de ensuciar la consola.
func empty_warnings() -> int:
	return _empty_warnings


## Cambia los puestos de pila por los [Marker3D] hijos de [param source].
##
## La llama `RoundManager._adopt_district_markers()` con el `BatteryPosts` del
## distrito recién instanciado. **Los marcadores del nivel quedan como respaldo**:
## siguen colgando de este nodo en `battle_level.tscn` y son los que se usan
## mientras el distrito no traiga los suyos, que es lo que hace que un distrito
## viejo —o un banco que abra el nivel suelto— siga funcionando sin tocar nada.
## Esa es también la razón por la que el nivel puede tener los dos juegos a la vez:
## los del distrito **ganan**, no se suman.
##
## Rehace las pilas, porque cada [BatteryPickup] está anclada a su marcador y
## sobran o faltan según cuántos traiga el distrito, y termina en [method reset],
## así que la secuencia vuelve a salir de la semilla de la ronda. [member
## active_target] **no se toca**: cuántas pilas hay a la vez es una decisión de
## balance del nivel (`docs/09` §2.5), no del barrio.
##
## Con [param source] nulo o sin hijos [Marker3D] no hace nada y avisa: es mejor
## seguir con los puestos del nivel que quedarse sin ninguno.
func adopt_markers(source: Node3D) -> void:
	if source == null or not is_instance_valid(source):
		return
	var adopted := _markers_of(source)
	if adopted.is_empty():
		push_warning("BatterySpawner: '%s' no trae hijos Marker3D; se conservan los %d del nivel."
				% [source.name, _markers.size()])
		return
	for pickup: BatteryPickup in _pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	_pickups.clear()
	_markers = adopted
	_active.resize(_markers.size())
	_build_pickups()
	reset()


## Marcadores que llegaron a usarse al menos una vez, en índices de
## [method get_marker_count]. Lo consume `energy_check` para comprobar que el
## marcador tapado nunca se elige.
func get_used_markers() -> PackedInt32Array:
	return _used_markers


## `true` si el marcador [param index] tiene su pila encendida.
func is_marker_active(index: int) -> bool:
	if index < 0 or index >= _active.size():
		return false
	return _active[index] == 1


## La pila anclada al marcador [param index], encendida o no.
func get_pickup(index: int) -> BatteryPickup:
	if index < 0 or index >= _pickups.size():
		return null
	return _pickups[index]


## Apaga todo, vuelve a sembrar el RNG con `Global.round_seed` y deja el relleno
## listo para el primer tick.
func reset() -> void:
	for pickup: BatteryPickup in _pickups:
		if pickup != null:
			pickup.deactivate()
	for index: int in _active.size():
		_active[index] = 0
	_active_count = 0
	_used_markers = PackedInt32Array()
	_accumulator = 0.0
	_next_delay = 0.0
	# El aviso de «sin puestos» es **por ronda**: si la que viene tampoco los trae,
	# se avisa de nuevo, y una sola vez.
	_empty_warnings = 0
	_rng.seed = Global.round_seed


# --- Relleno ----------------------------------------------------------------------------------

## Enciende pilas hasta llegar a [member active_target], saltando los marcadores
## ocupados y los que no estén despejados.
func _fill() -> void:
	var candidates := _free_markers()
	_shuffle(candidates)
	for index: int in candidates:
		if _active_count >= active_target:
			return
		if not _is_clear(index):
			continue
		_activate(index)


func _activate(index: int) -> void:
	var pickup := _pickups[index]
	var marker := _markers[index]
	if pickup == null or marker == null:
		return
	pickup.activate(marker.global_transform)
	_active[index] = 1
	_active_count += 1
	if not _used_markers.has(index):
		var _appended := _used_markers.append(index)


func _on_collected(pickup: BatteryPickup) -> void:
	var index := _pickups.find(pickup)
	if index < 0 or _active[index] == 0:
		return
	_active[index] = 0
	_active_count = maxi(_active_count - 1, 0)


## Índices de los marcadores cuya pila está apagada.
##
## Devuelve un [Array] tipado y no un [PackedInt32Array] a propósito: los arrays
## empaquetados son valores con copia al escribir, así que [method _shuffle] no
## podría reordenarlos en su sitio.
func _free_markers() -> Array[int]:
	var free: Array[int] = []
	for index: int in _markers.size():
		if _active[index] == 0 and _markers[index] != null:
			free.append(index)
	return free


## Fisher–Yates con el RNG sembrado. `Array.shuffle()` usa el generador global y
## rompería el determinismo que pide `docs/09` §5 sub-check 22.
func _shuffle(values: Array[int]) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var pick := _rng.randi_range(0, index)
		var swap := values[index]
		values[index] = values[pick]
		values[pick] = swap


## `intersect_shape` sobre `city | debris` (`docs/09` §2.5). Sin espacio de física
## —fuera del árbol o antes del primer paso— se da por despejado: es mejor una
## pila de más que un spawner mudo.
func _is_clear(index: int) -> bool:
	var marker := _markers[index]
	if marker == null:
		return false
	var world := get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	_clearance_shape.radius = clearance_radius
	_query.transform = Transform3D(Basis.IDENTITY, marker.global_position)
	_query.collision_mask = clearance_mask
	return space.intersect_shape(_query, 1).is_empty()


# --- Construcción -----------------------------------------------------------------------------

## Los puestos que trae la propia escena. Quedarse sin ninguno **no es un error**:
## es lo que pasa en `battle_level.tscn`, que espera los del distrito (ver la
## cabecera). El aviso, si hace falta, lo da [method _warn_empty].
func _collect_markers() -> void:
	_markers = _markers_of(self)
	_active.resize(_markers.size())


## Avisa **una sola vez por ronda** que este spawner tiene que repartir pilas y no
## tiene dónde: ni la escena traía puestos ni el distrito se los adoptó.
##
## Es `push_warning` y no `push_error` a propósito: el juego sigue, sin pilas, y el
## único que puede arreglarlo es quien armó el barrio.
func _warn_empty() -> void:
	if _empty_warnings > 0:
		return
	_empty_warnings += 1
	push_warning(("BatterySpawner: %s llegó al juego sin puestos de pila; " % name)
			+ "ni la escena trae hijos Marker3D ni el distrito le adoptó un "
			+ "BatteryPosts (`docs/09` §2.5).")


## Los [Marker3D] hijos directos de [param source], **en orden de árbol**.
##
## El orden importa: es lo que hace que dos rondas con la misma semilla activen la
## misma secuencia de puestos (`docs/09` §5 sub-check 22). Por eso se recorren los
## hijos y no se busca por nombre.
func _markers_of(source: Node) -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	for child: Node in source.get_children():
		var marker := child as Marker3D
		if marker != null:
			found.append(marker)
	return found


func _build_pickups() -> void:
	_pickups.clear()
	var packed := pickup_scene
	if packed == null and ResourceLoader.exists(DEFAULT_PICKUP_SCENE):
		packed = load(DEFAULT_PICKUP_SCENE) as PackedScene
	if packed == null:
		push_error("BatterySpawner: no se pudo cargar %s." % DEFAULT_PICKUP_SCENE)
		return
	for index: int in _markers.size():
		var pickup := packed.instantiate() as BatteryPickup
		if pickup == null:
			push_error("BatterySpawner: la escena de pila no instancia un BatteryPickup.")
			return
		pickup.name = "BatteryPickup%d" % (index + 1)
		pickup.energy_system = energy_system
		# El **monto sale del perfil**, no del default de la escena. Hasta el
		# rebalance del checkpoint 4 el spawner inyectaba la batería pero no la
		# cantidad, así que `EnergyProfile.battery_amount` y `BatteryPickup.amount`
		# eran dos números independientes que sólo coincidían por disciplina: subir
		# uno y olvidarse del otro dejaba el perfil diciendo una cosa y el juego
		# haciendo otra, sin que nada se pusiera rojo salvo `energy_check`, que los
		# comparaba a los dos contra su propia constante. Ahora hay una sola fuente.
		if energy_system != null and energy_system.profile != null:
			pickup.amount = energy_system.profile.battery_amount
		add_child(pickup)
		pickup.global_transform = _markers[index].global_transform
		pickup.deactivate()
		var _discard := pickup.collected.connect(_on_collected)
		_pickups.append(pickup)


func _configure_query() -> void:
	_clearance_shape.radius = clearance_radius
	_query.shape = _clearance_shape
	_query.collision_mask = clearance_mask
	_query.collide_with_areas = false
	_query.collide_with_bodies = true


## Busca la batería del dron sin acoplarse al nivel: primero el `DroneRig` que
## exponga `get_energy_system()`, después cualquier [EnergySystem] del árbol.
func _find_energy_system() -> EnergySystem:
	var root := get_tree().current_scene if get_tree() != null else null
	if root == null:
		root = get_parent()
	if root == null:
		return null
	for node: Node in root.find_children("*", "EnergySystem", true, false):
		var found := node as EnergySystem
		if found != null:
			return found
	return null
