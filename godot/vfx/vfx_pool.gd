## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Pool de efectos visuales del nivel (`docs/13` §4 y §8).
##
## Es el **único** dueño de las partículas del juego: ningún sistema de gameplay
## instancia un [GPUParticles3D] por su cuenta. El pool traduce hechos del bus en
## efectos, recicla por LRU y, cuando el presupuesto está lleno, **devuelve
## `null`** en vez de crear nodos nuevos.
##
## ## Presupuesto
##
## `docs/13` §4 fija un tope duro de **12 `GPUParticles3D` emitiendo a la vez**,
## que baja a 8 en MEDIUM y a 6 en LOW; el número lo manda `Graphics.max_emitters()`
## y acá se lee en cada consulta, así que cambiar de preset en el menú lo mueve en
## caliente. El tope es **conjunto con la ciudad**: [Building] pide sus plazas de
## polvo y humo con [method reserve_emitters], de modo que sesenta derrumbes no
## pueden dejar sin partículas al combate ni al revés.
##
## Las telegrafías **no gastan presupuesto**: el decal del pisotón, el anillo del
## EMP, la línea guía, la columna del asedio y la parábola del salto tienen pool
## dedicado y cero emisores (`docs/13` §11 #12). Un aviso que el presupuesto
## pueda descartar deja un ataque sin señal, y eso no es un adorno perdido: es
## una muerte injusta.
##
## ## Preasignación
##
## Las instancias se crean **todas en `_ready()`** y no se crean ni se liberan
## nunca más. Por eso `vfx_check` puede aseverar que el conteo de hijos y el de
## nodos del proceso son idénticos al principio y al final: si alguna ruta
## instanciara en caliente, el check lo vería.
##
## ## Reciclado
##
## [method request] busca primero una ranura libre del id pedido; si no hay,
## recicla la **más vieja** de ese id (LRU), que es la que menos se nota perder.
## Sólo después mira el presupuesto: reciclar libera emisores, así que mirar el
## presupuesto antes daría `null` con ranuras disponibles.
##
## ## Vidas
##
## Un efecto con `life_seconds > 0` lo suelta el pool solo cuando se apaga. Uno
## con `life_seconds = 0` —los haces y las telegrafías, cuya duración la manda el
## ataque— es de quien lo pidió hasta que llame a [method release]; el pool sólo
## lo reclama pasados [constant MAX_HOLD_SECONDS], como red contra una acción que
## muera sin soltarlo.
##
## Esa red **no se le aplica** a los efectos que declaran `hold` en su fila de
## [constant SPECS]: los dos haces y las chispas de parte dañada se retienen por
## diseño mientras dure el ataque o la avería, y una pelea larga pasa de sobra los
## dos minutos. Reclamarlos era un error visible: el haz parpadeaba, dejaba de
## contar en [method active_emitters] y, si el jefe moría con el haz encendido, el
## `release()` de la acción caía sobre una ranura ya libre y no apagaba nada. Esos
## efectos sólo avisan por consola y siguen siendo de quien los pidió.
class_name VFXPool extends Node

## Grupo por el que lo encuentra todo el que lo necesite sin cablear rutas.
const GROUP: StringName = &"vfx_pool"

## Segundos tras los que se reclama un efecto de vida manual que nadie soltó.
const MAX_HOLD_SECONDS: float = 120.0

## Efecto que le toca a cada superficie de `Events.hit_confirmed` (`docs/02`
## §5.1, WP-26). `world` no está: el suelo y el escombro no dibujan nada del pool.
##
## Hasta que la señal llevó la superficie, esto se deducía por **cercanía al
## enemigo** (30 m), y esa heurística fallaba justo cuando el jefe estaba encima
## del edificio al que le estabas tirando. Ahora lo dice el emisor, que es el
## único que tiene el collider.
const SURFACE_EFFECT: Dictionary[StringName, StringName] = {
	&"weak": &"impact_weak",
	&"armor": &"impact_armor",
	&"city": &"impact_city",
}

## Radio, en metros, dentro del cual un impacto se **ancla** al enemigo para que
## el efecto camine con él. Ya no decide la superficie —eso lo dice la señal—,
## sólo a qué nodo seguir. La huella del Arachnodroid es de 21 × 27 m y sus patas
## llegan a ±11 m (`docs/07` §2).
const ENEMY_HIT_RADIUS: float = 30.0

## Velocidad de apoyo, en m/s, a la que el polvo de pisada sale al 100 %.
const FOOT_FULL_SPEED: float = 14.0

## Umbral de vida por debajo del cual una parte echa chispas (`docs/13` §4).
const DAMAGED_RATIO: float = 0.35

## Metadato que marca una [EnemyPart] ya enganchada al pool.
const META_HOOKED: StringName = &"vfx_hooked"

## Metadato con las chispas que una [EnemyPart] tiene encendidas ahora mismo.
const META_SPARKS: StringName = &"vfx_sparks"

## Catálogo de efectos (`docs/13` §4). `size` es el tamaño del pool, `emitters`
## lo que cada instancia cuesta del presupuesto.
##
## `muzzle_flash` vale **0** porque §4 lo declara «1 emisor permanente» fijo en el
## [WeaponMount]: no compite con nada. Las cinco telegrafías valen 0 por §11 #12.
##
## `hold` marca la **retención larga**: quien lo pide lo conserva mientras dure una
## condición de juego, no una animación, así que la red de
## [constant MAX_HOLD_SECONDS] no lo toca. Lo declaran los dos haces —[SweepAction]
## los retiene desde el primer `configure_beam()` hasta salir del árbol— y las
## chispas de parte dañada, que viven hasta que la parte sane o se rompa.
const SPECS: Dictionary[StringName, Dictionary] = {
	&"muzzle_flash": {"scene": "res://drone/weapons/muzzle_flash.tscn",
			"size": 1, "emitters": 0},
	&"impact_armor": {"scene": "res://vfx/impact_armor.tscn", "size": 12, "emitters": 1},
	&"impact_weak": {"scene": "res://vfx/impact_weak.tscn", "size": 8, "emitters": 1},
	&"impact_city": {"scene": "res://vfx/impact_city.tscn", "size": 8, "emitters": 1},
	&"foot_dust": {"scene": "res://vfx/foot_dust.tscn", "size": 4, "emitters": 1},
	&"collapse": {"scene": "res://vfx/collapse.tscn", "size": 2, "emitters": 2},
	&"part_detach": {"scene": "res://vfx/part_detach.tscn", "size": 4, "emitters": 2},
	&"laser_beam": {"scene": "res://vfx/laser_beam.tscn", "size": 1, "emitters": 1, "hold": true},
	&"siege_beam": {"scene": "res://vfx/siege_beam.tscn", "size": 1, "emitters": 1, "hold": true},
	&"emp_ring": {"scene": "res://vfx/emp_ring.tscn", "size": 1, "emitters": 0},
	&"stomp_decal": {"scene": "res://vfx/stomp_decal.tscn", "size": 2, "emitters": 0},
	&"guide_line": {"scene": "res://vfx/guide_line.tscn", "size": 1, "emitters": 0},
	&"siege_column": {"scene": "res://vfx/siege_column.tscn", "size": 1, "emitters": 0},
	&"parabola": {"scene": "res://vfx/parabola.tscn", "size": 1, "emitters": 0},
	&"damaged_sparks": {"scene": "res://vfx/damaged_sparks.tscn", "size": 4, "emitters": 1,
			"hold": true},
	&"drone_sparks": {"scene": "res://vfx/drone_sparks.tscn", "size": 2, "emitters": 1},
	&"drone_burst": {"scene": "res://vfx/drone_burst.tscn", "size": 1, "emitters": 2},
	&"pickup_flash": {"scene": "res://vfx/pickup_flash.tscn", "size": 2, "emitters": 1},
}

## Efectos continuos, que ocupan su emisor mientras dure la condición que los
## encendió. Se les recorta el reparto para que no se coman el presupuesto.
const CONTINUOUS_IDS: Array[StringName] = [&"damaged_sparks"]

## Si el pool escucha el bus. Un showcase o un check pueden apagarlo para pedir
## efectos a mano sin que los hechos del juego se los muevan.
@export var listen_to_events: bool = true

## Si el pool sigue a los enemigos que aparecen para enganchar sus pisadas y sus
## partes dañadas.
@export var track_enemies: bool = true

## Una ranura del pool: la instancia, su id y el turno en que se usó por última
## vez, que es lo que ordena el LRU.
class Slot:
	var id: StringName = &""
	var node: Node3D = null
	var effect: VFXEffect = null
	var emitters: int = 0
	var busy: bool = false
	var manual: bool = false
	var long_hold: bool = false
	var warned: bool = false
	var ticket: int = 0
	var held: float = 0.0

var _slots: Dictionary[StringName, Array] = {}
var _by_node: Dictionary[int, Slot] = {}
var _reserved: int = 0
var _ticket: int = 0
var _requests: int = 0
var _denied: int = 0
var _shots: int = 0
var _part_fx_frame: int = -1
var _drone: Node3D = null
var _enemies: Array[Node3D] = []


func _ready() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	_build()
	if listen_to_events:
		_connect_bus()
	if track_enemies:
		# Los enemigos que ya estaban en la escena —los bancos de los checks y los
		# showcases— nunca emitieron `enemy_spawned` para este pool.
		call_deferred(&"_scan_enemies")
	set_process(true)


## Suelta lo que se haya apagado y reclama lo que nadie soltó. Presentación pura:
## `_process`, no tick de física.
func _process(delta: float) -> void:
	PerfProbe.begin(&"vfx_pool")
	var busy := 0
	for id: StringName in _slots:
		for slot: Slot in _slots[id]:
			if not slot.busy:
				continue
			busy += 1
			slot.held += delta
			if slot.manual:
				if slot.held >= MAX_HOLD_SECONDS and not slot.warned:
					slot.warned = true
					push_warning("VFXPool: '%s' lleva %.0f s retenido%s."
							% [String(slot.id), slot.held,
							"" if slot.long_hold else "; se reclama la ranura"])
				# La retención larga es de quien la pidió hasta que llame a
				# `release()`: reclamarla apagaba haces en pleno ataque.
				if slot.held >= MAX_HOLD_SECONDS and not slot.long_hold:
					_free_slot(slot)
					busy -= 1
				continue
			if not _node_playing(slot):
				_free_slot(slot)
				busy -= 1
	PerfProbe.end(&"vfx_pool")
	# Sin ranuras ocupadas no hay nada que envejecer. Lo vuelve a encender
	# [method acquire]; es higiene, no rendimiento (WP-29 midió 0.029 ms/cuadro).
	if busy == 0 and _reserved == 0:
		set_process(false)


# --------------------------------------------------------------------------
# Interfaz pública (`docs/13` §8)
# --------------------------------------------------------------------------

## Pide el efecto [param id] colocado en [param xform].
##
## Devuelve `null` si el id no existe o si el presupuesto de emisores está lleno;
## **nunca** instancia nada nuevo. [param parent] no reparenta: el efecto se queda
## bajo el pool —reparentar rompería el reciclado— y lo **sigue** en cada frame,
## que es lo que quiere quien lo pasa (una parte desprendida, una pieza que cae).
func request(id: StringName, xform: Transform3D, parent: Node3D = null) -> Node3D:
	return acquire(id, xform, parent, 1.0)


## [method request] con control de la cantidad de partículas. [param scale] va de
## 0 a 1 y es lo que hace que un tranco suave levante menos polvo que un pisotón.
func acquire(id: StringName, xform: Transform3D, parent: Node3D = null,
		scale: float = 1.0) -> Node3D:
	_requests += 1
	var spec: Dictionary = SPECS.get(id, {})
	if spec.is_empty():
		_denied += 1
		return null
	if CONTINUOUS_IDS.has(id) and _busy_count(id) >= _continuous_cap():
		_denied += 1
		return null
	# El presupuesto se mira con el **coste neto**: reciclar la instancia más vieja
	# de este id libera sus emisores, así que hay que descontarlos antes de
	# comparar. Y se mira **antes** de apagar nada: reciclar primero y denegar
	# después apagaba un efecto vivo para no servir ninguno, que es lo peor de los
	# dos mundos —pasaba cuando el presupuesto estaba lleno por **otros** ids—.
	var slot := _free_slot_of(id)
	var recycled: Slot = null
	if slot == null:
		recycled = _oldest_busy_of(id)
		if recycled == null:
			_denied += 1
			return null
		slot = recycled
	var cost := int(spec["emitters"])
	if cost > 0:
		var freed := 0
		if recycled != null and recycled.emitters > 0 and _node_playing(recycled):
			freed = recycled.emitters
		if active_emitters() - freed + cost > budget():
			_denied += 1
			return null
	if recycled != null:
		_free_slot(recycled)

	_ticket += 1
	slot.ticket = _ticket
	slot.busy = true
	slot.held = 0.0
	slot.warned = false
	slot.node.top_level = true
	set_process(true)
	slot.node.global_transform = xform
	_play_node(slot, scale)
	if parent != null:
		follow(slot.node, parent)
	return slot.node


## Devuelve [param node] al pool. Es idempotente y tolera un nodo ajeno.
##
## Sobre una ranura que el pool **ya reclamó** igual apaga el efecto: si no, un
## haz que la red de [constant MAX_HOLD_SECONDS] hubiera soltado se quedaba
## emitiendo para siempre, porque quien lo tenía creía haberlo devuelto.
## [method _stop_node] es idempotente, así que llamarlo de más no cuesta nada.
func release(node: Node3D) -> void:
	if node == null:
		return
	var slot: Slot = _by_node.get(node.get_instance_id(), null)
	if slot == null:
		return
	if not slot.busy:
		_stop_node(slot)
		return
	_free_slot(slot)


## Emisores de partículas ocupados ahora mismo: los de los efectos encendidos más
## los que la ciudad pidió con [method reserve_emitters].
func active_emitters() -> int:
	var count := _reserved
	for id: StringName in _slots:
		for slot: Slot in _slots[id]:
			if slot.busy and slot.emitters > 0 and _node_playing(slot):
				count += slot.emitters
	return count


## Tope de emisores del preset vigente: 6 / 8 / 12 / 12 (`docs/13` §3.4).
func budget() -> int:
	return Graphics.max_emitters()


# --------------------------------------------------------------------------
# Extensiones sobre §8
# --------------------------------------------------------------------------

## Reserva [param count] plazas de emisor para un sistema que dibuja sus propias
## partículas, hoy sólo [Building] con su polvo y su humo por edificio. Devuelve
## `false` si no hay presupuesto, y entonces el edificio se derrumba sin polvo.
##
## Es lo que hace que el tope de `docs/13` §4 sea **uno solo** para la ciudad y
## para el combate: antes había dos contadores de 12 que sumaban 24.
func reserve_emitters(count: int = 1) -> bool:
	if count <= 0:
		return true
	if active_emitters() + count > budget():
		return false
	_reserved += count
	return true


## Devuelve [param count] plazas reservadas.
func release_emitters(count: int = 1) -> void:
	_reserved = maxi(_reserved - count, 0)


## Emisores contados **midiendo**: recorre las instancias y cuenta los
## [GPUParticles3D] con `emitting = true`. Es el número que `vfx_check` compara
## contra [method active_emitters] para detectar un contador que miente.
func measured_emitters() -> int:
	var count := _reserved
	for id: StringName in _slots:
		for slot: Slot in _slots[id]:
			if slot.effect != null:
				count += slot.effect.emitting_count()
	return count


## Convierte un efecto de vida manual en uno de vida propia: el pool lo suelta en
## cuanto su `is_playing()` dé `false`, sin esperar un [method release].
##
## Es lo que pasa cuando un aviso se convierte en **secuela**: el decal del
## pisotón deja una marca de cráter de 4 s que ya no es del [Telegraph], y el
## anillo del EMP termina con un destello de 0.3 s que sobrevive al apagado de los
## tres canales. Sin esto, esos dos se quedarían con su ranura hasta que saltara
## la red de [constant MAX_HOLD_SECONDS].
func release_when_done(node: Node3D) -> void:
	if node == null:
		return
	var slot: Slot = _by_node.get(node.get_instance_id(), null)
	if slot == null or not slot.busy:
		return
	slot.manual = false


## Pega [param node] a [param target]: se coloca donde esté el nodo en cada frame.
func follow(node: Node3D, target: Node3D) -> void:
	var slot: Slot = _by_node.get(node.get_instance_id(), null)
	if slot == null or slot.effect == null:
		return
	slot.effect.follow(target)


## Ranuras ocupadas de [param id], o de todo el pool si viene vacío.
func busy_count(id: StringName = &"") -> int:
	if id != &"":
		return _busy_count(id)
	var total := 0
	for key: StringName in _slots:
		total += _busy_count(key)
	return total


## Instancias preasignadas de [param id].
func pool_size(id: StringName) -> int:
	var list: Array = _slots.get(id, [])
	return list.size()


## Todos los ids del catálogo, en el orden de [constant SPECS].
func effect_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in SPECS:
		ids.append(id)
	return ids


## Pedidos servidos y rechazados desde el arranque. Los consume `vfx_check`.
func request_count() -> int:
	return _requests


func denied_count() -> int:
	return _denied


## Disparos vistos en el bus. El fogonazo lo pone el [MuzzleFlash] fijo del
## [WeaponMount] (`docs/13` §4: «no cuenta»); acá sólo se cuentan.
func shot_count() -> int:
	return _shots


## Apaga y devuelve todo. Lo usan el respawn, los checks y el cambio de ronda.
func clear() -> void:
	for id: StringName in _slots:
		for slot: Slot in _slots[id]:
			if slot.busy:
				_free_slot(slot)
	_reserved = 0


## El pool del árbol de [param from], o `null`. Es como lo encuentran [Building],
## [Telegraph] y [SweepAction] sin cablear rutas.
static func resolve(from: Node) -> VFXPool:
	if from == null or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as VFXPool


# --------------------------------------------------------------------------
# Construcción
# --------------------------------------------------------------------------

## Preasigna todas las instancias del catálogo.
func _build() -> void:
	for id: StringName in SPECS:
		var spec: Dictionary = SPECS[id]
		var scene := load(String(spec["scene"])) as PackedScene
		var list: Array[Slot] = []
		if scene == null:
			push_error("VFXPool: no se pudo cargar '%s' para '%s'."
					% [spec["scene"], String(id)])
			_slots[id] = list
			continue
		for index: int in int(spec["size"]):
			var node := scene.instantiate() as Node3D
			if node == null:
				push_error("VFXPool: '%s' no instancia un Node3D." % spec["scene"])
				break
			node.name = "%s_%d" % [String(id), index + 1]
			add_child(node)
			node.top_level = true
			var slot := Slot.new()
			slot.id = id
			slot.node = node
			slot.effect = node as VFXEffect
			slot.emitters = int(spec["emitters"])
			slot.manual = slot.effect != null and slot.effect.life_seconds <= 0.0
			slot.long_hold = bool(spec.get("hold", false))
			list.append(slot)
			_by_node[node.get_instance_id()] = slot
			_stop_node(slot)
		_slots[id] = list


## Pares señal → método del bus (`docs/13` §8). Una sola tabla para conectar y
## desconectar: dos listas separadas se desincronizan al agregar un hecho.
func _bus_links() -> Array[Array]:
	var links: Array[Array] = [
		[Events.shot_fired, _on_shot_fired],
		[Events.hit_confirmed, _on_hit_confirmed],
		[Events.enemy_part_broken, _on_enemy_part_broken],
		[Events.building_destroyed, _on_building_destroyed],
		[Events.drone_damaged, _on_drone_damaged],
		[Events.drone_destroyed, _on_drone_destroyed],
		[Events.battery_collected, _on_battery_collected],
	]
	if track_enemies:
		links.append([Events.enemy_spawned, _on_enemy_spawned])
	return links


## Conecta los hechos del bus que §8 mapea a efectos.
func _connect_bus() -> void:
	for link: Array in _bus_links():
		var signal_ref: Signal = link[0]
		var handler: Callable = link[1]
		if not signal_ref.is_connected(handler):
			var _discard := signal_ref.connect(handler)


## Suelta el bus al salir del árbol. `Events` es un autoload y sobrevive al nivel:
## un pool desconectado del árbol pero conectado al bus seguiría sirviendo efectos
## —y contándolos— desde fuera de la escena.
func _exit_tree() -> void:
	for link: Array in _bus_links():
		var signal_ref: Signal = link[0]
		var handler: Callable = link[1]
		if signal_ref.is_connected(handler):
			signal_ref.disconnect(handler)


# --------------------------------------------------------------------------
# Ranuras
# --------------------------------------------------------------------------

## Primera ranura libre de [param id], o `null` si están todas ocupadas.
func _free_slot_of(id: StringName) -> Slot:
	for slot: Slot in _slots.get(id, []):
		if not slot.busy:
			return slot
	return null


## Ranura ocupada más vieja de [param id] (la del LRU), **sin liberarla**: quien
## llama decide si le conviene reciclarla después de mirar el presupuesto.
func _oldest_busy_of(id: StringName) -> Slot:
	var oldest: Slot = null
	for slot: Slot in _slots.get(id, []):
		if not slot.busy:
			continue
		if oldest == null or slot.ticket < oldest.ticket:
			oldest = slot
	return oldest


func _busy_count(id: StringName) -> int:
	var count := 0
	for slot: Slot in _slots.get(id, []):
		if slot.busy:
			count += 1
	return count


## Tope de efectos continuos simultáneos: un cuarto del presupuesto. Con cuatro
## rodillas rotas y 6 emisores en LOW, las chispas se llevarían dos tercios del
## presupuesto y no quedaría con qué dibujar un impacto.
func _continuous_cap() -> int:
	return maxi(1, budget() / 4)


func _free_slot(slot: Slot) -> void:
	slot.busy = false
	slot.held = 0.0
	_stop_node(slot)


## Enciende la instancia, sea un [VFXEffect] o el [MuzzleFlash] del arma.
func _play_node(slot: Slot, scale: float = 1.0) -> void:
	if slot.effect != null:
		slot.effect.play(scale)
		return
	if slot.node.has_method(&"flash"):
		slot.node.call(&"flash")
		slot.node.visible = true


func _stop_node(slot: Slot) -> void:
	if slot.effect != null:
		slot.effect.stop()
		return
	if slot.node.has_method(&"stop"):
		slot.node.call(&"stop")
	slot.node.visible = false


func _node_playing(slot: Slot) -> bool:
	if slot.effect != null:
		return slot.effect.is_playing()
	if slot.node.has_method(&"is_flashing"):
		return bool(slot.node.call(&"is_flashing"))
	return false


## Atajo para pedir un efecto en un punto, sin transformada.
func _spawn(id: StringName, position: Vector3, scale: float = 1.0) -> Node3D:
	return acquire(id, Transform3D(Basis.IDENTITY, position), null, scale)


# --------------------------------------------------------------------------
# Hechos del bus (`docs/13` §8)
# --------------------------------------------------------------------------

## El fogonazo lo pone el [MuzzleFlash] fijo del [WeaponMount], que ya está en la
## boca del arma y no gasta presupuesto. Acá sólo se cuenta el disparo: pedirle
## uno al pool encendería **dos** destellos en el mismo sitio.
func _on_shot_fired(_origin: Vector3, _direction: Vector3) -> void:
	_shots += 1


## Impacto confirmado. El punto débil es **cian** y el blindaje cálido, que es la
## regla de identidad de `docs/13` §1: lo del enemigo nunca es cálido.
func _on_hit_confirmed(position: Vector3, _weak: bool, _lethal: bool,
		surface: StringName) -> void:
	var id := SURFACE_EFFECT.get(surface, &"") as StringName
	if id == &"":
		# `world` —suelo y escombro— no dibuja nada del pool: la chispa chica de
		# cada bala ya la pone `ImpactFXPool` (`docs/08` §2.10).
		return
	# La orientación sí hay que deducirla: la señal lleva el punto pero no la
	# normal. La superficie tocada mira, aproximadamente, hacia quien disparó, así
	# que se arma una base con `+Y` hacia el dron: las chispas del proceso salen
	# sobre `+Y` y por lo tanto rebotan **hacia la cámara**, que es como se ve un
	# impacto desde el arma que lo produjo.
	var xform := Transform3D(_facing_basis(position), position)
	# Las chispas sobre el enemigo viajan con él. A 0.35 s y con el jefe a paso de
	# trote el arrastre es de centímetros, pero sin esto la chispa se queda
	# colgada en el aire donde la rodilla ya no está.
	var parent: Node3D = _nearest_enemy(position) if id != &"impact_city" else null
	var _fx := acquire(id, xform, parent)


## Parte rota. Si la parte se desprendió, [method EnemyPart.detach] ya pidió el
## efecto con el [DebrisChunk] al que seguir en este mismo fotograma.
func _on_enemy_part_broken(_enemy: Node3D, _part_id: StringName, position: Vector3) -> void:
	if _part_fx_frame == Engine.get_process_frames():
		return
	var _fx := _spawn(&"part_detach", position)


## Derrumbe: la columna de polvo grande de la ciudad (`docs/10` §3).
func _on_building_destroyed(position: Vector3, _value: int) -> void:
	var _fx := _spawn(&"collapse", position)


## Chispas del dron. **Ámbar y blancas**, nunca cian: lo propio no es cian.
func _on_drone_damaged(_amount: float, _source_position: Vector3) -> void:
	var drone := _resolve_drone()
	if drone == null:
		return
	var node := _spawn(&"drone_sparks", drone.global_position)
	if node != null:
		follow(node, drone)


## Estallido corto de la destrucción, antes de la estática de la señal.
func _on_drone_destroyed(position: Vector3) -> void:
	var _fx := _spawn(&"drone_burst", position)


## Destello `SUCCESS` de la pila recogida (`docs/13` §8).
func _on_battery_collected(_amount: float, position: Vector3) -> void:
	var _fx := _spawn(&"pickup_flash", position)


# --------------------------------------------------------------------------
# Enganches al enemigo
# --------------------------------------------------------------------------

## Engancha las pisadas y las partes de un enemigo recién aparecido. Es lo que
## evita tener que tocar [ProceduralLegRig] y [EnemyPart] para el polvo y las
## chispas: el pool se suscribe y ellos no saben que existe.
func _on_enemy_spawned(enemy: Node3D, _enemy_id: StringName) -> void:
	if enemy == null or _enemies.has(enemy):
		return
	_enemies.append(enemy)
	var rig := enemy.get(&"locomotion") as Node
	if rig != null and rig.has_signal(&"foot_planted") \
			and not rig.is_connected(&"foot_planted", _on_foot_planted):
		var _a := rig.connect(&"foot_planted", _on_foot_planted)
	if not enemy.has_method(&"get_parts"):
		return
	for part: EnemyPart in enemy.call(&"get_parts"):
		# Un `Callable` con `bind` no es igual al de origen, así que
		# `is_connected` no sirve de guardia: la marca va en un metadato.
		if part.has_meta(META_HOOKED):
			continue
		part.set_meta(META_HOOKED, true)
		var _b := part.damaged.connect(_on_part_damaged.bind(part))
		var _c := part.broken.connect(_on_part_broken.bind(part))


## Engancha los enemigos que ya estaban en el árbol cuando nació el pool.
func _scan_enemies() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(EnemyBase.GROUP):
		_on_enemy_spawned(node as Node3D, &"")


## Polvo de pisada: **lo más grande que hay en pantalla** (`docs/13` §1). La
## cantidad sale de la velocidad de apoyo, así que un tranco suave levanta una
## nube chica y un pisotón la levanta entera.
func _on_foot_planted(_leg_index: int, position: Vector3, impact_speed: float) -> void:
	var scale := clampf(impact_speed / FOOT_FULL_SPEED, 0.25, 1.0)
	var _fx := _spawn(&"foot_dust", position, scale)


## Chispas de parte dañada: se encienden al cruzar el 35 % de vida y se apagan al
## subir de ahí o al romperse la parte.
func _on_part_damaged(_part_id: StringName, _amount: float, remaining: float,
		part: EnemyPart) -> void:
	var ratio := remaining / maxf(part.max_hp, 0.0001)
	var live := _part_sparks(part)
	if ratio > DAMAGED_RATIO or part.mesh == null:
		_clear_part_sparks(part)
		return
	if live != null:
		return
	var node := _spawn(&"damaged_sparks", part.world_position())
	if node == null:
		return
	follow(node, part.mesh)
	part.set_meta(META_SPARKS, node)


## Una parte rota deja de echar chispas: ya no hay dónde anclarlas.
func _on_part_broken(_part_id: StringName, part: EnemyPart) -> void:
	_clear_part_sparks(part)


## Chispas encendidas de [param part], o `null`.
func _part_sparks(part: EnemyPart) -> Node3D:
	if not part.has_meta(META_SPARKS):
		return null
	var node := part.get_meta(META_SPARKS) as Node3D
	if node == null or not is_instance_valid(node):
		part.remove_meta(META_SPARKS)
		return null
	var slot: Slot = _by_node.get(node.get_instance_id(), null)
	if slot == null or not slot.busy:
		part.remove_meta(META_SPARKS)
		return null
	return node


func _clear_part_sparks(part: EnemyPart) -> void:
	var live := _part_sparks(part)
	if live == null:
		return
	release(live)
	part.remove_meta(META_SPARKS)


# --------------------------------------------------------------------------
# Ayudas
# --------------------------------------------------------------------------

## Marca que el efecto de desprendimiento de este fotograma ya lo pidió
## [method EnemyPart.detach] con su [DebrisChunk]. Sin esto el bus serviría un
## segundo `part_detach` en el mismo punto.
func claim_part_fx() -> void:
	_part_fx_frame = Engine.get_process_frames()


## Enemigo vivo en cuya huella cae [param point], o `null`. Sólo sirve para
## anclar el efecto a un cuerpo que se mueve; la superficie la manda la señal.
func _nearest_enemy(point: Vector3) -> Node3D:
	var radius_squared := ENEMY_HIT_RADIUS * ENEMY_HIT_RADIUS
	var found: Node3D = null
	var index := _enemies.size() - 1
	while index >= 0:
		var enemy := _enemies[index]
		if not is_instance_valid(enemy):
			_enemies.remove_at(index)
		elif found == null and enemy.global_position.distance_squared_to(point) <= radius_squared:
			found = enemy
		index -= 1
	return found


## Base con `+Y` apuntando de [param point] al dron. Es la orientación de un
## impacto visto por quien disparó: el eje de emisión de los
## [ParticleProcessMaterial] es `+Y`, así que las chispas rebotan hacia la cámara
## en vez de hacia arriba. Sin dron devuelve la identidad.
func _facing_basis(point: Vector3) -> Basis:
	var drone := _resolve_drone()
	if drone == null:
		return Basis.IDENTITY
	var up := drone.global_position - point
	if up.length_squared() < 0.0001:
		return Basis.IDENTITY
	up = up.normalized()
	var helper := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := helper.cross(up).normalized()
	return Basis(right, up, right.cross(up)).orthonormalized()


## Dron del nivel, resuelto tarde y cacheado. Se llega por la cámara FPV, que es
## el único nodo del rig que está en un grupo (`docs/03` §5).
func _resolve_drone() -> Node3D:
	if _drone != null and is_instance_valid(_drone):
		return _drone
	_drone = null
	var tree := get_tree()
	if tree == null:
		return null
	var camera := tree.get_first_node_in_group(&"fpv_camera") as Node3D
	var node: Node = camera
	var depth := 0
	while node != null and depth < 6:
		if node is Drone:
			_drone = node as Node3D
			return _drone
		node = node.get_parent()
		depth += 1
	return null
