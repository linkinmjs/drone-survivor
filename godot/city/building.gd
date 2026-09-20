## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Un edificio destructible de la ciudad (`docs/10` §3 y §9.1).
##
## El script va sobre la **raíz de una pieza importada** (`city/pieces/*.tscn`),
## que ya es un `StaticBody3D` en la capa 8 con su `IntactShape`; lo asigna
## [CityGrid] al sembrar el distrito, junto con los nodos de etapa. Nadie más lo
## instancia a mano.
##
## Máquina de etapas de `docs/10` §3.1, absorbente en `RUBBLE`:
## [codeblock]
## INTACT ──ratio ≤ 0.60──▶ DAMAGED ──ratio ≤ 0.15──▶ RUBBLE
## [/codeblock]
##
## Al entrar en `RUBBLE` el HP se pone en **cero** y el resto se cuenta como daño
## aplicado: así `Σ hp` llega exactamente a 0 y `Events.city_integrity_changed`
## es monótona no creciente por construcción. El coste efectivo de derribar un
## edificio es, por lo tanto, el 85 % de su HP nominal.
##
## **Duck typing con el arma**: `ProjectilePool` llama `take_damage(amount, point)`
## sobre el colisionador de capa 8 sin conocer esta clase (`docs/08` §2.7); la
## firma es estable y el escalado de fuego amigo lo aplica el llamador.
##
## Presentación por etapa:
##
## - `INTACT` — malla del pack tal cual, con sus ventanas emisivas.
## - `DAMAGED` — la **misma** malla con `city/damage_overlay.gdshader` como
##   `material_override`: recorta boquetes con `ALPHA_SCISSOR` sobre un ruido
##   triplanar y, al no escribir `EMISSION`, apaga los emisivos. La colisión no
##   cambia y la malla original no se toca.
## - `RUBBLE` — la malla se oculta, el colisionador baja a una caja de ~2 m y
##   aparece un montículo `rubble_pile_*` con columna de humo.
##
## Todos los temporizadores son acumuladores en `_physics_process`, nunca
## [Timer] (convención de `docs/00` §6), lo que hace reproducible el derrumbe en
## `city_check`.
class_name Building extends StaticBody3D

## Etapas de destrucción. `RUBBLE` es absorbente.
enum Stage {
	INTACT,  ## Malla completa, ventanas encendidas.
	DAMAGED, ## Boquetes por shader, emisivos apagados.
	RUBBLE,  ## Montículo de cascotes; `hp = 0` e inmune.
}

## Grupo con todos los edificios del distrito (`docs/10` §5, `docs/11` §4.2).
const GROUP: StringName = &"buildings"

## Grupo del edificio que está bajo asedio. Tiene **como mucho un miembro**:
## quien arbitra es [CityIntegrity] (`docs/12` §4.1).
const GROUP_UNDER_SIEGE: StringName = &"buildings_under_siege"

## Ruta del shader de la etapa `DAMAGED`.
const DAMAGE_SHADER_PATH: String = "res://city/damage_overlay.gdshader"

## Tope duro de `GPUParticles3D` emitiendo a la vez en toda la ciudad
## (`docs/13` §7). Un edificio que no consigue plaza se derrumba sin polvo.
const MAX_EMITTERS: int = 12

## Distancia a la que se desvanece la columna de humo (`docs/10` §7).
const SMOKE_VISIBILITY_RANGE_END: float = 400.0

## Fracción de la altura que conserva la malla al terminar el derrumbe.
const COLLAPSE_SHRINK: float = 0.86

## Altura máxima, en metros, a la que nace un trozo de escombro.
const DEBRIS_MAX_ORIGIN_HEIGHT: float = 26.0

## Emisores de partículas ocupados ahora mismo por la ciudad.
static var _active_emitters: int = 0

## Materiales de daño ya construidos, indexados por el material original de la
## pieza. Hay **uno por familia** (`buildings_001` y `buildings_002`), no uno por
## edificio: 60 duplicados romperían el agrupado de lotes.
static var _damage_materials: Dictionary = {}

## Se emite en cada transición de etapa, nunca al repetir la misma.
signal stage_changed(stage: Stage)

## Se emite **una sola vez**, al terminar el derrumbe.
signal destroyed(value: int)

## Daño realmente aplicado. Lo escucha [CityIntegrity] para llevar el acumulador
## sin volver a sumar los 60 edificios cada frame.
signal damage_taken(amount: float, point: Vector3)

## Números del tipo de edificio. Sin perfil el edificio no recibe daño.
@export var profile: BuildingProfile = null

## AABB de la pieza sin variación de altura, en metros y en el espacio local de
## la raíz. Lo copia [CityGrid] del metadato `base_size` del import.
@export var base_size: Vector3 = Vector3(20.0, 12.5, 11.0)

## Factor de altura aplicado por [method apply_variation]. Multiplica la malla y
## el `BoxShape3D`, **nunca** la escala del `StaticBody3D`.
@export_range(0.05, 4.0, 0.001) var height_scale: float = 1.0

## Malla de la pieza importada (o el contenedor que la agrupa). Es un [Node3D],
## **no** el cuerpo: escalarlo y hundirlo no toca las formas de colisión.
@export var stage_intact: Node3D = null

## Transformada de [member stage_intact] **sin** variación de altura, ya
## recentrada sobre la huella. Es el punto de partida de la escala y del
## hundimiento; se guarda explícitamente porque la transformada que queda en
## `district_a.tscn` ya lleva la variación aplicada y leerla en `_ready()`
## volvería a multiplicar la altura en cada carga.
@export var intact_rest_transform: Transform3D = Transform3D.IDENTITY

## Contenedor de la ruina: montículo y humo.
@export var stage_rubble: Node3D = null

## Caja de colisión del edificio en pie.
@export var intact_shape: CollisionShape3D = null

## Caja baja de la ruina; empieza deshabilitada.
@export var rubble_shape: CollisionShape3D = null

## Estallido de polvo de cada transición (`one_shot`).
@export var dust_burst: GPUParticles3D = null

## Columna de humo de la ruina (continua, con vida acotada).
@export var smoke: GPUParticles3D = null

## Carteles y antenas de azotea. Se desprenden al entrar en `DAMAGED`.
@export var props: Node3D = null

## Montículo de cascotes de la etapa `RUBBLE`.
@export var rubble_pile: MeshInstance3D = null

## Pool de escombros. Si queda vacío se resuelve con [method DebrisPool.resolve].
@export var debris_pool: DebrisPool = null

## Metadato con la posición **sin variación** de cada prop de azotea; lo escribe
## [method _place_props] la primera vez que ve al prop y sobrevive al empaquetado,
## así una recarga (o un nuevo `apply_variation`) no vuelve a escalar lo ya escalado.
const PROP_REST_META: StringName = &"rest_position"

## Estructura restante.
var hp: float = 0.0

## Etapa actual.
var stage: Stage = Stage.INTACT

## Peso en el puntaje; sale del perfil.
var value: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _collapsing: bool = false
var _collapse_elapsed: float = 0.0
var _dust_left: float = 0.0
var _smoke_left: float = 0.0
var _dust_holds_slot: bool = false
var _smoke_holds_slot: bool = false
var _siege_damage: float = 0.0
var _siege_age: float = 0.0
var _under_siege: bool = false
var _destroyed_emitted: bool = false
var _pile_rest_scale: Vector3 = Vector3.ONE

## [CityGrid] al que pertenece este edificio. Se resuelve tarde y se cachea; el
## tipo es [Node3D] y el despacho por `has_method` para no cerrar el ciclo
## `city_grid.gd` → `building.gd` → `city_grid.gd`.
var _grid: Node3D = null


func _ready() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	# Semilla estable por edificio: dos corridas con la misma `round_seed` tiran
	# los mismos escombros aunque cambie el orden de los derrumbes.
	_rng.seed = hash(Vector3i(roundi(position.x), roundi(position.y), roundi(position.z))) \
			^ Global.round_seed
	if rubble_pile != null:
		_pile_rest_scale = rubble_pile.scale
	# Las formas se **desclonan y se recalculan en cada carga**, no se guardan en
	# `district_a.tscn`: los nodos internos de una escena instanciada no
	# conservan sus anulaciones al empaquetar, así que las diez instancias de una
	# misma pieza compartirían el `BoxShape3D` del `PackedScene` y la variación
	# de altura de un edificio reescribiría la de sus hermanos. El estado que se
	# guarda es el lógico —[member base_size] y [member height_scale]— y la
	# geometría se deriva de él.
	_unshare_shape(intact_shape)
	_unshare_shape(rubble_shape)
	refresh_shapes()
	reset()
	set_physics_process(false)


## Da a [param node] una copia propia de su forma, para que dos edificios de la
## misma pieza no compartan el mismo `BoxShape3D`.
func _unshare_shape(node: CollisionShape3D) -> void:
	if node != null and node.shape != null:
		node.shape = node.shape.duplicate()


func _exit_tree() -> void:
	# Un distrito liberado a mitad de un derrumbe no puede dejarse plazas de
	# emisor ocupadas: el presupuesto es estático y sobrevive a la escena.
	if _dust_holds_slot:
		_dust_holds_slot = false
		_release_emitter()
	if _smoke_holds_slot:
		_smoke_holds_slot = false
		_release_emitter()


func _physics_process(delta: float) -> void:
	var busy := false

	if _collapsing:
		_collapse_elapsed += delta
		var span := maxf(profile.collapse_seconds if profile != null else 1.8, 0.01)
		var t := clampf(_collapse_elapsed / span, 0.0, 1.0)
		_apply_collapse(t)
		if t >= 1.0:
			_finish_collapse()
		else:
			busy = true

	if _dust_left > 0.0:
		_dust_left -= delta
		if _dust_left <= 0.0:
			_stop_dust()
		else:
			busy = true

	if _smoke_left > 0.0:
		_smoke_left -= delta
		if _smoke_left <= 0.0:
			_stop_smoke()
		else:
			busy = true

	if _siege_damage > 0.0:
		_siege_age += delta
		if _siege_age >= (profile.siege_window if profile != null else 3.0):
			_siege_damage = 0.0
			_siege_age = 0.0
		else:
			busy = true

	if not busy:
		set_physics_process(false)


# --------------------------------------------------------------------------
# Daño
# --------------------------------------------------------------------------

## Aplica [param amount] puntos de daño estructural con origen en [param point]
## y devuelve el daño **realmente aplicado**, que es lo que descuenta
## [CityIntegrity]. Una ruina devuelve siempre 0: `RUBBLE` es absorbente.
##
## Al cruzar el umbral de ruina el HP restante se suma al daño devuelto y el
## edificio queda en cero, para que la integridad de una ciudad arrasada valga
## exactamente 0.0 (`docs/10` §3.1).
func take_damage(amount: float, point: Vector3) -> float:
	if stage == Stage.RUBBLE or profile == null or amount <= 0.0 or hp <= 0.0:
		return 0.0

	var applied := minf(amount, hp)
	hp -= applied
	var ratio := get_ratio()
	var to_rubble := ratio <= profile.rubble_threshold
	if to_rubble:
		applied += hp
		hp = 0.0

	_siege_damage += applied
	_siege_age = 0.0
	set_physics_process(true)
	damage_taken.emit(applied, point)

	if to_rubble:
		_enter_rubble(point)
	elif stage == Stage.INTACT and ratio <= profile.damaged_threshold:
		_enter_damaged(point)
	return applied


## Estructura restante, de 0.0 a 1.0.
func get_ratio() -> float:
	var maximum := get_max_hp()
	return hp / maximum if maximum > 0.0 else 0.0


## HP del edificio intacto.
func get_max_hp() -> float:
	return profile.max_hp if profile != null else 0.0


## Altura real en metros, ya con la variación aplicada.
func get_height() -> float:
	return base_size.y * height_scale


## Verdadero desde que se cruza el umbral de ruina, aunque el derrumbe siga en
## curso.
func is_destroyed() -> bool:
	return stage == Stage.RUBBLE


## Verdadero cuando el derrumbe terminó: la malla está oculta, el colisionador
## es el de la ruina y ya se publicó `building_destroyed`.
func is_collapsed() -> bool:
	return stage == Stage.RUBBLE and not _collapsing


## Daño acumulado en la ventana deslizante de asedio. Vuelve a 0 tras
## `profile.siege_window` segundos sin recibir daño.
func get_siege_damage() -> float:
	return _siege_damage


## Verdadero si este es el edificio marcado como «bajo asedio».
func is_under_siege() -> bool:
	return _under_siege


## Entra o sale del grupo [constant GROUP_UNDER_SIEGE]. Lo llama **sólo**
## [CityIntegrity], que garantiza un único marcado a la vez.
##
## La baliza emisiva que describe `docs/10` §5 queda para WP-26: el marcador del
## HUD se dibuja desde el grupo, que es lo que `docs/12` §4.1 consume.
func mark_under_siege(active: bool) -> void:
	if active == _under_siege:
		return
	_under_siege = active
	if active:
		add_to_group(GROUP_UNDER_SIEGE)
	else:
		remove_from_group(GROUP_UNDER_SIEGE)


# --------------------------------------------------------------------------
# Variación y reinicio
# --------------------------------------------------------------------------

## Aplica la variación de `docs/10` §4.3: [param new_height_scale] sobre la
## malla y [param yaw_steps] cuartos de vuelta sobre el cuerpo.
##
## **No escala el `StaticBody3D`.** Escala el [Node3D] que contiene la malla y
## **reescribe** `BoxShape3D.size.y` y la posición de las dos formas. Escalar un
## cuerpo físico produce formas inconsistentes en Jolt y `docs/03` lo prohíbe.
func apply_variation(new_height_scale: float, yaw_steps: int) -> void:
	height_scale = maxf(new_height_scale, 0.05)
	rotation = Vector3(0.0, float(yaw_steps) * (PI * 0.5), 0.0)
	_place_intact(height_scale, 0.0)
	_place_props()
	refresh_shapes()


## Reescribe las dos cajas de colisión y el montículo según [member base_size] y
## [member height_scale]. Idempotente; la llama [method apply_variation] y
## [CityGrid] tras duplicar las formas.
func refresh_shapes() -> void:
	var height := get_height()
	var intact_box := intact_shape.shape as BoxShape3D if intact_shape != null else null
	if intact_box != null:
		intact_box.size = Vector3(base_size.x, height, base_size.z)
		intact_shape.position = Vector3(0.0, height * 0.5, 0.0)

	var rubble_box := rubble_shape.shape as BoxShape3D if rubble_shape != null else null
	if rubble_box != null:
		var low := get_rubble_height()
		rubble_box.size = Vector3(base_size.x * 0.96, low, base_size.z * 0.96)
		rubble_shape.position = Vector3(0.0, low * 0.5, 0.0)

	if rubble_pile != null:
		# El montículo viene normalizado a 1 × 1 × 1 m: se estira a la huella
		# real y a una altura algo mayor que la del colisionador, para que la
		# silueta se lea desde el aire sin convertirse en un muro.
		_pile_rest_scale = Vector3(base_size.x * 1.04,
				clampf(height * 0.24, 2.2, 6.0), base_size.z * 1.04)
		rubble_pile.scale = _pile_rest_scale


## Altura del colisionador de la ruina, en metros. `docs/10` §10 fija el factor
## 0.18 sobre la altura; se recorta a `profile.rubble_height_max` (3 m) para que
## una torre de 45 m no deje un muro de 8 m en pie, como pide WP-20.
func get_rubble_height() -> float:
	var factor := profile.rubble_height_factor if profile != null else 0.18
	var maximum := profile.rubble_height_max if profile != null else 3.0
	return clampf(get_height() * factor, 1.2, maximum)


## Devuelve el edificio a `INTACT` con el HP lleno. Lo usa `RoundManager` al
## reiniciar la ronda (`docs/10` §9.1).
func reset() -> void:
	value = profile.value if profile != null else 0
	hp = get_max_hp()
	stage = Stage.INTACT
	_collapsing = false
	_collapse_elapsed = 0.0
	_siege_damage = 0.0
	_siege_age = 0.0
	_destroyed_emitted = false
	mark_under_siege(false)
	_stop_dust()
	_stop_smoke()

	if stage_intact != null:
		stage_intact.visible = true
		_place_intact(height_scale, 0.0)
		_set_damage_material(null)
	if stage_rubble != null:
		stage_rubble.visible = false
	if rubble_pile != null:
		rubble_pile.scale = _pile_rest_scale
	if props != null:
		props.visible = true
		_place_props()
	if intact_shape != null:
		intact_shape.set_deferred(&"disabled", false)
	if rubble_shape != null:
		rubble_shape.set_deferred(&"disabled", true)
	_set_occluder_enabled(true)


# --------------------------------------------------------------------------
# Transiciones
# --------------------------------------------------------------------------

## `INTACT` → `DAMAGED`: boquetes por shader, emisivos apagados, polvo, trauma y
## una tanda de escombros. La colisión no cambia (`docs/10` §3.2).
func _enter_damaged(point: Vector3) -> void:
	stage = Stage.DAMAGED
	_set_damage_material(_resolve_damage_material())
	if props != null:
		# `docs/10` §3.2: los props se desprenden acá. Los trozos cosméticos son
		# de WP-26; acá sólo desaparecen, para no gastar plazas del pool de 24.
		props.visible = false
	_burst_dust(0.75)
	_spawn_debris(point)
	Events.camera_trauma.emit(profile.trauma_damaged, global_position)
	stage_changed.emit(stage)


## `DAMAGED` (o `INTACT`, si el golpe fue enorme) → `RUBBLE`: arranca el
## derrumbe acumulado de `collapse_seconds`, publica el trauma y pide escombros.
func _enter_rubble(point: Vector3) -> void:
	stage = Stage.RUBBLE
	hp = 0.0
	_collapsing = true
	_collapse_elapsed = 0.0
	set_physics_process(true)
	if props != null:
		props.visible = false
	if stage_rubble != null:
		stage_rubble.visible = true
	if rubble_pile != null:
		rubble_pile.scale = _pile_rest_scale * 0.6
	_burst_dust(1.0)
	_start_smoke()
	_spawn_debris(point)
	Events.camera_trauma.emit(profile.trauma_rubble, global_position)
	stage_changed.emit(stage)


## Paso del derrumbe, con [param t] de 0 a 1: el edificio se hunde y se aplasta
## mientras el montículo crece de 0.6 a 1.0.
func _apply_collapse(t: float) -> void:
	var sink := profile.collapse_sink if profile != null else 0.35
	_place_intact(height_scale * (1.0 - COLLAPSE_SHRINK * t), get_height() * sink * t)
	if rubble_pile != null:
		rubble_pile.scale = _pile_rest_scale * lerpf(0.6, 1.0, t)


## Cierre del derrumbe: se oculta la malla, se conmutan las formas y se publica
## `destroyed` y `Events.building_destroyed`, **una sola vez**.
func _finish_collapse() -> void:
	_collapsing = false
	if stage_intact != null:
		stage_intact.visible = false
	if rubble_pile != null:
		rubble_pile.scale = _pile_rest_scale
	# Diferido: cambiar `disabled` en pleno paso de física es ilegal en Jolt.
	if intact_shape != null:
		intact_shape.set_deferred(&"disabled", true)
	if rubble_shape != null:
		rubble_shape.set_deferred(&"disabled", false)
	_set_occluder_enabled(false)
	if _destroyed_emitted:
		return
	_destroyed_emitted = true
	destroyed.emit(value)
	Events.building_destroyed.emit(global_position, value)


# --------------------------------------------------------------------------
# Escombros
# --------------------------------------------------------------------------

## Enciende o apaga el [OccluderInstance3D] de la manzana, si este edificio es el
## que lo define (el más alto).
##
## La oclusión por oclusores está apagada en todos los presets desde WP-24e
## (`Graphics.use_occlusion_culling()`), así que hoy esto no cambia un solo píxel.
## Existe igual porque **el bug era éste**: los 15 oclusores se hornean en
## `district_a.tscn` ceñidos al edificio más alto de cada manzana y nadie los
## retiraba al derrumbarlo, así que quedaba una losa opaca invisible de hasta 75 m
## tapando al coloso y tragándose el cuadro cuando la cámara entraba en ella. Con
## esto, volver a encender la oclusión es cambiar una línea del `project.godot`.
##
## Se usa `visible`, que es lo que el `RenderingServer` mira para armar la lista de
## oclusores del escenario, y no borrar el recurso: así [method reset] lo devuelve
## sin tener que reconstruir la caja.
func _set_occluder_enabled(enabled: bool) -> void:
	var grid := _resolve_grid()
	if grid == null:
		return
	var occluder := grid.call(&"occluder_for", self) as OccluderInstance3D
	if occluder == null:
		return
	occluder.visible = enabled


## Primer ancestro que sepa resolver oclusores, o `null` en un banco de pruebas que
## use edificios sueltos fuera de un distrito.
func _resolve_grid() -> Node3D:
	if _grid != null and is_instance_valid(_grid):
		return _grid
	var node := get_parent()
	while node != null:
		if node.has_method(&"occluder_for"):
			_grid = node as Node3D
			return _grid
		node = node.get_parent()
	return null


## Pide al [DebrisPool] entre `debris_count_min` y `debris_count_max` trozos con
## impulso radial hacia afuera y hacia arriba (`docs/10` §3.2 paso 1).
##
## [param _point] no coloca los trozos: el derrumbe sale del edificio entero, no
## del punto de impacto. Se conserva en la firma porque es el dato que trae
## `take_damage()` y WP-26 lo va a querer para orientar el polvo del boquete.
func _spawn_debris(_point: Vector3) -> void:
	if profile == null or profile.debris_mesh == null:
		return
	var pool := _resolve_pool()
	if pool == null:
		return
	var count := profile.roll_debris_count(_rng)
	var height := get_height()
	var radius := maxf(base_size.x, base_size.z) * 0.5
	for index: int in count:
		var angle := _rng.randf() * TAU
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		# La altura de salida se recorta a 26 m: un trozo soltado desde los 43 m
		# de una torre tarda casi 3 s sólo en caer y otro tanto en asentarse, y
		# el criterio de `docs/10` §11.2 sub-check 8 exige que el derrumbe esté
		# cerrado —escombros incluidos— antes de los 6 s.
		var origin := global_position \
				+ radial * radius * _rng.randf_range(0.25, 0.85) \
				+ Vector3.UP * _rng.randf_range(
						minf(height * 0.25, DEBRIS_MAX_ORIGIN_HEIGHT * 0.3),
						minf(height * 0.95, DEBRIS_MAX_ORIGIN_HEIGHT))
		var basis := Basis.from_euler(Vector3(
				_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		var impulse := (radial * _rng.randf_range(0.35, 1.0) + Vector3.UP * _rng.randf_range(0.4, 1.0)) \
				* profile.debris_mass * profile.debris_impulse
		var _chunk := pool.request(profile.debris_mesh, profile.debris_shape,
				Transform3D(basis, origin), profile.debris_mass, impulse, 0.0)


## Pool cableado por `@export` o, si falta, el del grupo `debris_pool`.
func _resolve_pool() -> DebrisPool:
	if debris_pool != null and is_instance_valid(debris_pool):
		return debris_pool
	debris_pool = DebrisPool.resolve(self)
	return debris_pool


# --------------------------------------------------------------------------
# Presentación
# --------------------------------------------------------------------------

## Pone (o quita, con `null`) el `material_override` de daño en cada malla de la
## etapa intacta. No modifica el `ArrayMesh`, que es compartido por las 60
## instancias de la pieza.
func _set_damage_material(material: Material) -> void:
	if stage_intact == null:
		return
	for node: Node in _mesh_instances():
		(node as MeshInstance3D).material_override = material


## Material de daño de la familia de esta pieza, construido una sola vez y
## compartido por todos los edificios que usan la misma difusa.
func _resolve_damage_material() -> ShaderMaterial:
	var meshes := _mesh_instances()
	if meshes.is_empty():
		return null
	var source := (meshes[0] as MeshInstance3D).get_active_material(0)
	var key: Variant = source if source != null else &"default"
	if _damage_materials.has(key):
		return _damage_materials[key] as ShaderMaterial

	var shader := ResourceLoader.load(DAMAGE_SHADER_PATH, "Shader") as Shader
	if shader == null:
		push_error("Building: no se pudo cargar '%s'." % DAMAGE_SHADER_PATH)
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.resource_name = "damage_overlay"
	var standard := source as StandardMaterial3D
	if standard != null and standard.albedo_texture != null:
		material.set_shader_parameter(&"albedo_texture", standard.albedo_texture)
	material.set_shader_parameter(&"damage_amount", 0.34)
	material.set_shader_parameter(&"noise_scale", 10.0)
	_damage_materials[key] = material
	return material


## Coloca la malla intacta con escala vertical [param vertical] y hundida
## [param sink] metros, siempre a partir de [member intact_rest_transform].
##
## El producto se hace **por la izquierda** a propósito: la malla importada
## llega girada −90° sobre X (la Z cruda del FBX es la altura), así que escalar
## su eje Y local estiraría el edificio en profundidad. Premultiplicar por la
## escala la aplica en el espacio de la raíz, que es donde «alto» quiere decir
## alto, y deja la base ortogonal.
func _place_intact(vertical: float, sink: float) -> void:
	if stage_intact == null:
		return
	var lift := Transform3D(Basis.from_scale(Vector3(1.0, maxf(vertical, 0.0001), 1.0)),
			Vector3(0.0, -sink, 0.0))
	stage_intact.transform = lift * intact_rest_transform


## Baja los props de azotea a la altura real del techo.
##
## [CityGrid] los deja a `base_size.y` (la altura **sin** variación) y la malla se
## escala después con [member height_scale]; sin esta corrección, el cartel de una
## torre al 54 % quedaba flotando 37 m por encima del techo. La posición de reposo
## se guarda en [constant PROP_REST_META] la primera vez y se escala desde ahí, de
## modo que la operación es idempotente y sobrevive al empaquetado del distrito.
func _place_props() -> void:
	if props == null:
		return
	for child: Node in props.get_children():
		var prop := child as Node3D
		if prop == null:
			continue
		if not prop.has_meta(PROP_REST_META):
			prop.set_meta(PROP_REST_META, prop.position)
		var rest: Vector3 = prop.get_meta(PROP_REST_META)
		prop.position = Vector3(rest.x, rest.y * height_scale, rest.z)


## Mallas de la etapa intacta, en orden de recorrido.
func _mesh_instances() -> Array[Node]:
	var found: Array[Node] = []
	if stage_intact == null:
		return found
	if stage_intact is MeshInstance3D:
		found.append(stage_intact)
	var pending: Array[Node] = [stage_intact]
	var index := 0
	while index < pending.size():
		for child: Node in pending[index].get_children():
			pending.append(child)
			if child is MeshInstance3D:
				found.append(child)
		index += 1
	return found


## Estallido de polvo de una transición, escalado por `dust_scale`.
func _burst_dust(intensity: float) -> void:
	if dust_burst == null or _dust_holds_slot or not _take_emitter():
		return
	_dust_holds_slot = true
	var scale := (profile.dust_scale if profile != null else 1.0) * intensity
	dust_burst.amount_ratio = clampf(scale, 0.15, 1.0)
	dust_burst.emitting = true
	dust_burst.restart()
	_dust_left = dust_burst.lifetime + 0.35
	set_physics_process(true)


func _stop_dust() -> void:
	_dust_left = 0.0
	if dust_burst != null:
		dust_burst.emitting = false
	if _dust_holds_slot:
		_dust_holds_slot = false
		_release_emitter()


## Columna de humo de la ruina, con vida acotada por `profile.smoke_seconds`
## para no dejar sesenta emisores encendidos hasta el final de la ronda.
func _start_smoke() -> void:
	if smoke == null or _smoke_holds_slot or not _take_emitter():
		return
	_smoke_holds_slot = true
	smoke.emitting = true
	_smoke_left = profile.smoke_seconds if profile != null else 12.0
	set_physics_process(true)


func _stop_smoke() -> void:
	_smoke_left = 0.0
	if smoke != null:
		smoke.emitting = false
	if _smoke_holds_slot:
		_smoke_holds_slot = false
		_release_emitter()


# --------------------------------------------------------------------------
# Presupuesto de emisores
# --------------------------------------------------------------------------

## Emisores de la ciudad encendidos ahora mismo. Lo lee `city_check`.
static func active_emitters() -> int:
	return _active_emitters


## Devuelve el contador a cero. Lo llama [method CityIntegrity.reset] al
## reconstruir el distrito.
static func reset_emitters() -> void:
	_active_emitters = 0


static func _take_emitter() -> bool:
	if _active_emitters >= MAX_EMITTERS:
		return false
	_active_emitters += 1
	return true


static func _release_emitter() -> void:
	_active_emitters = maxi(_active_emitters - 1, 0)
