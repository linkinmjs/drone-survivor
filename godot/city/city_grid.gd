## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Rejilla del distrito (`docs/10` §4).
##
## Siembra manzanas de `block_span × block_span` celdas de edificio separadas por
## **calles de verdad** —vereda, cordón y calzada— coloca **exactamente**
## [method building_count] edificios con la fachada sobre la línea municipal,
## dibuja calzada, cruces y veredas con cinco [MultiMeshInstance3D], apoya todo
## sobre una única caja de suelo y remata con oclusores, rocas y puntos de
## aparición.
##
## Es `@tool` para poder regenerar el distrito desde el editor, pero **nunca**
## construye sola: [method build] se llama a mano o desde
## `tools/build_district.gd`. El resultado se guarda como escena concreta
## `city/districts/district_a.tscn` y es lo que instancia `RoundManager`
## (`docs/10` §12, decisión 10): así los oclusores, la iluminación y `city_check`
## son reproducibles.
##
## ## Celda de 32 m, y no de 24 m
##
## `docs/10` §4.1 fija la celda en 24 m, pero la Nota de WP-13 de §1 midió que
## `BuildingBlock_1` y `BuildingBlock_2` tienen **30 m de ancho**: en una celda
## de 24 m desbordarían 3 m por lado sobre la calle. De las tres palancas que
## enumera `assets/city/README.md` (agrandar la celda, reservar esas piezas para
## el borde, o escalarlas también en planta) se elige **agrandar la celda a
## 32 m**, porque es la única que no escala en XZ —lo que obligaría a reescribir
## `BoxShape3D.size` en los tres ejes— ni desperdicia dos de las seis piezas de
## edificio.
##
## ## Rejilla NO uniforme: carriles de tres anchos (WP-24b)
##
## Hasta WP-21 la rejilla era uniforme y **una calle ocupaba una celda entera de
## 32 m de asfalto**: una autopista de doce carriles entre dos bloques de
## oficinas. WP-24b la parte en *carriles* de tres clases, cada uno con su ancho:
##
## [codeblock]
## celda de edificio  32 m   fachada a fachada de la manzana
## calle              16 m   vereda 3 + calzada 10 + vereda 3
## avenida            32 m   vereda 5 + calzada 10 + cantero 2 + calzada 10 + vereda 5
## [/codeblock]
##
## Hay **una avenida por eje**, junto a la manzana central, y un anillo de calle
## en el perímetro para que los edificios del borde también tengan vereda
## enfrente. Con 5 × 3 manzanas de 2 × 2 celdas la extensión baja de
## 480 × 288 m a **432 × 272 m** (400 × 240 m de manzanas y calles interiores más
## el anillo perimetral), y la cuenta de edificios (60), el reparto de HP y todo
## lo demás quedan igual.
##
## [method cell_position] ya no multiplica índice por lado: **acumula anchos**
## carril a carril, y [method get_extent] es la suma de esos anchos. Es lo que
## verifica `city_check`.
@tool
class_name CityGrid extends Node3D

## Clase de carril. Un carril `BLOCK` es una fila o columna de celdas de
## edificio; `STREET` y `AVENUE` son calzada con sus veredas.
enum Lane {
	BLOCK,   ## Celdas de edificio, de [member cell_size] metros.
	STREET,  ## Calle de [member street_width] metros.
	AVENUE,  ## Avenida de [member avenue_width] metros, con cantero central.
}

## Nombres de los contenedores generados. `build()` los recrea de cero.
const BUILDINGS_NODE: StringName = &"Buildings"
const STREETS_NODE: StringName = &"Streets"
const OCCLUDERS_NODE: StringName = &"Occluders"
const ROCKS_NODE: StringName = &"Rocks"
const SPAWNS_NODE: StringName = &"Spawns"
const GROUND_NODE: StringName = &"Ground"

## Nombres de los cinco [MultiMeshInstance3D] de la red viaria. Los dos primeros
## están separados **a propósito**: llevan la misma malla con la basis girada un
## cuarto de vuelta entre sí, y tenerlos en nodos distintos es lo que permite a
## `city_check` comprobar que las marcas de la calzada van a lo largo de cada
## calle y no cruzadas.
const ROAD_NS_NODE: StringName = &"RoadNS"
const ROAD_EW_NODE: StringName = &"RoadEW"
const CROSSINGS_NODE: StringName = &"Crossings"
const SIDEWALKS_NODE: StringName = &"Sidewalks"
const PADS_NODE: StringName = &"BlockPads"

## Script que se pone sobre la raíz de cada pieza al sembrarla (`docs/10` §2.5).
const BUILDING_SCRIPT: String = "res://city/building.gd"

## Nodo de colisión que dejó el post-import en cada pieza.
const PIECE_SHAPE: StringName = &"IntactShape"

## Capas de `docs/10` §9.4.
const GROUND_LAYER: int = 1
const GROUND_MASK: int = 294

## Variación de altura por rol (`docs/10` §4.3 adaptada a las piezas reales).
##
## Los **hitos** (`Building_3`, 81 m nativos) ya no se aplastan a 0.40–0.55: con
## pisos de 1,2 m la torre se leía como una maqueta y era lo que el jugador veía
## como «estructuras muy escaladas». Van casi a escala 1, que es lo que da la
## silueta que `docs/07` §2 necesita para `climb` y `siege_beam`. Las otras
## torres son bloques medios estirados a 15–17 m.
const LANDMARK_SCALE_MIN: float = 0.90
const LANDMARK_SCALE_MAX: float = 1.00
const MID_TOWER_SCALE_MIN: float = 1.20
const MID_TOWER_SCALE_MAX: float = 1.35
const LOW_SCALE_MIN: float = 0.85
const LOW_SCALE_MAX: float = 1.20

## Separación mínima entre hitos, en metros. Se relaja si con ella no entran los
## [member tall_primary_count] pedidos.
const LANDMARK_SPACING: float = 72.0

## Alturas a las que se apoyan calzada y veredas, en metros sobre `y = 0`. La
## diferencia (15 cm) es el cordón visible.
const ROAD_TOP: float = 0.03
const SIDEWALK_TOP: float = 0.18

## Ancho de una hilera de calzada, en metros. Es exactamente el lado de
## `Road_Chunk_5`, así que una sola instancia cubre la calzada a lo ancho.
const ROADWAY_WIDTH: float = 10.0

## Lado nativo de las piezas de calle, en metros.
const ROAD_PIECE_SIDE: float = 10.0
const WALK_PIECE_SIDE: float = 10.0
const TILE_PIECE_SIDE: float = 20.0

## Alto nativo de las piezas de calle, en metros (su AABB arranca en `y = 0`).
const ROAD_PIECE_HEIGHT: float = 0.5
const WALK_PIECE_HEIGHT: float = 1.0
const TILE_PIECE_HEIGHT: float = 1.0

## Relación largo/ancho de las baldosas de vereda. La textura de
## `Sidewalk_Chunk_2` sólo tiene estructura **a lo ancho** (las dos bandas
## oscuras del cordón), así que estirarla a lo largo no se ve y ahorra dos
## tercios de las instancias.
const WALK_TILE_ASPECT: float = 2.5

## Lado del parche de asfalto liso del cruce, en metros, y cuántos entran en una
## baldosa. Ver [method _build_crossing_mesh].
const CROSSING_PATCH: float = 2.0
const CROSSING_CELLS: int = 4

## Rectángulo UV de un parche de asfalto **sin marcas** del atlas
## `t_roads_diffuse.png`, medido sobre la cara superior de `Road_Chunk_5`: la
## pieza mapea sus 10 m a 0.1353 de UV, así que 0.02706 son 2 m de calzada. El
## parche está entre las dos bandas anaranjadas del borde y esquiva las dos
## tapas de alcantarilla; en `bake_roads_emissive.png` es negro, o sea que el
## cruce no emite. Así el cruce reutiliza el material `roads.tres` sin estirar
## la textura ni añadir un PNG al presupuesto de VRAM de `docs/10` §2.3.
const ASPHALT_UV: Rect2 = Rect2(0.8905, 0.1565, 0.02606, 0.02606)

## Punto de aparición del dron en el nivel de batalla, en el espacio local del
## distrito (que está en el origen), y semiángulo del cono de visión inicial que
## ninguna roca puede invadir.
const DRONE_SPAWN: Vector3 = Vector3(120.0, 0.0, 200.0)
const SPAWN_CONE_DEG: float = 30.0

## Rumbo real del dron al aparecer (el `-Z` de la base de `Respawn` en
## `rounds/battle_level.tscn`) y semiángulo que se le respeta.
##
## No coincide con la línea al centro: el nivel hace aparecer al dron mirando
## por encima del lado este de la ciudad, 48° a la izquierda del centro. El cono
## que pide el encargo se mide contra el centro, pero una roca justo enfrente del
## rumbo **real** se vería igual de mal, así que las posiciones respetan los dos.
const DRONE_FACING: Vector3 = Vector3(0.2979, 0.0, -0.9546)
const SPAWN_VIEW_CONE_DEG: float = 20.0

## Lado de la celda de edificio, en metros. Ver la nota de cabecera: 32 y no 24.
@export_range(8.0, 100.0, 0.5) var cell_size: float = 32.0

## Manzanas en X y en Z.
@export_range(1, 20) var block_cols: int = 5
@export_range(1, 20) var block_rows: int = 3

## Celdas de edificio por lado de manzana.
@export_range(1, 8) var block_span: int = 2

## Ancho de una calle común: vereda + calzada + vereda.
@export_range(8.0, 60.0, 0.5) var street_width: float = 16.0

## Ancho de una avenida: vereda + calzada + cantero + calzada + vereda.
@export_range(8.0, 80.0, 0.5) var avenue_width: float = 32.0

## Ancho del anillo de calle que rodea el distrito.
@export_range(8.0, 60.0, 0.5) var perimeter_width: float = 16.0

## Vereda de una calle y de una avenida, en metros.
@export_range(1.0, 12.0, 0.25) var street_sidewalk: float = 3.0
@export_range(1.0, 12.0, 0.25) var avenue_sidewalk: float = 5.0

## Cantero central de la avenida, en metros.
@export_range(0.0, 8.0, 0.25) var avenue_median: float = 2.0

## Qué hueco entre manzanas es la avenida, contando desde el borde negativo. Con
## 5 manzanas hay 4 huecos (0–3) y ninguno cae justo en el centro: el 2 deja la
## avenida pegada a la manzana central.
@export_range(0, 18) var avenue_gap_col: int = 2
@export_range(0, 18) var avenue_gap_row: int = 1

## Semilla del sembrado. `district_a` se generó con **0**.
@export var seed: int = 0

## Edificios con perfil de torre (3 500 HP). El resto son bloques bajos.
@export_range(0, 400) var tall_count: int = 21

## De las torres, cuántas son **hitos** con la pieza alta de verdad
## (`Building_3`, 81 m) casi a escala 1. Las demás son bloques medios estirados.
@export_range(0, 400) var tall_primary_count: int = 6

## Piezas de bloque bajo o medio.
@export var low_pieces: Array[PackedScene] = []

## Pieza alta real. `docs/10` §2.1 esperaba dos; el pack sólo trae una.
@export var tall_pieces: Array[PackedScene] = []

## Piezas de «torre baja»: bloques de 12,5 m estirados a 15–17 m.
@export var mid_tower_pieces: Array[PackedScene] = []

## Carteles y antenas de azotea.
@export var prop_pieces: Array[PackedScene] = []

## Proporción de azoteas con prop (`docs/10` §4.3 y WP-20: 30 %).
@export_range(0.0, 1.0, 0.01) var prop_chance: float = 0.30

## Rocas del borde, en el grupo `city_rocks`.
@export var rock_scenes: Array[PackedScene] = []

## Perfil de los bloques bajos y medios.
@export var low_profile: BuildingProfile = null

## Perfil de las torres.
@export var tall_profile: BuildingProfile = null

## Piezas de calle, de las que se hornean las mallas de [MultiMesh].
@export var road_piece: PackedScene = null
@export var sidewalk_piece: PackedScene = null
@export var sidewalk_tile_piece: PackedScene = null

## Material del suelo del descampado.
@export var ground_material: Material = null

## Lado de la caja de suelo, en metros (`docs/10` §4.4).
@export_range(100.0, 4000.0, 10.0) var ground_size: float = 1200.0

## Pool de escombros del nivel. `district_a` lo deja vacío: cada [Building] lo
## resuelve con [method DebrisPool.resolve] (grupo `debris_pool`).
@export var debris_pool: DebrisPool = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _prop_debt: float = 0.0

## Plano de carriles por eje, recalculado cuando cambia algún parámetro.
var _kinds: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _widths: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _starts: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _extent: Vector2 = Vector2.ZERO
var _lane_signature: String = ""


# --------------------------------------------------------------------------
# Plano de carriles
# --------------------------------------------------------------------------

## Reconstruye el plano de carriles si cambió algún parámetro de la rejilla.
##
## La firma es explícita y no un `dirty` puesto a mano: la rejilla es `@tool` y
## sus propiedades se editan desde el inspector, donde nadie va a llamar a una
## invalidación.
func _ensure_lanes() -> void:
	var signature := "%d|%d|%d|%.3f|%.3f|%.3f|%.3f|%d|%d" % [block_cols, block_rows,
			block_span, cell_size, street_width, avenue_width, perimeter_width,
			avenue_gap_col, avenue_gap_row]
	if signature == _lane_signature:
		return
	_lane_signature = signature
	for axis: int in 2:
		var blocks := block_cols if axis == 0 else block_rows
		var avenue_gap := avenue_gap_col if axis == 0 else avenue_gap_row
		var kinds := PackedInt32Array()
		var widths := PackedFloat32Array()
		kinds.append(Lane.STREET)
		widths.append(perimeter_width)
		for block: int in blocks:
			for _d: int in block_span:
				kinds.append(Lane.BLOCK)
				widths.append(cell_size)
			if block >= blocks - 1:
				continue
			var avenue := block == avenue_gap
			kinds.append(Lane.AVENUE if avenue else Lane.STREET)
			widths.append(avenue_width if avenue else street_width)
		kinds.append(Lane.STREET)
		widths.append(perimeter_width)

		var total := 0.0
		for width: float in widths:
			total += width
		var starts := PackedFloat32Array()
		var cursor := -total * 0.5
		for width: float in widths:
			starts.append(cursor)
			cursor += width
		_kinds[axis] = kinds
		_widths[axis] = widths
		_starts[axis] = starts
		if axis == 0:
			_extent.x = total
		else:
			_extent.y = total


## Carriles del eje [param axis] (0 = X, 1 = Z).
func lane_count(axis: int) -> int:
	_ensure_lanes()
	return _kinds[axis].size()


## Clase del carril [param lane] del eje [param axis], como valor de [enum Lane].
## Devuelve `int` y no `Lane` porque el plano vive en un [PackedInt32Array] y
## GDScript no convierte de entero a enumerado.
func lane_kind(axis: int, lane: int) -> int:
	_ensure_lanes()
	var kinds := _kinds[axis]
	if lane < 0 or lane >= kinds.size():
		return Lane.STREET
	return kinds[lane]


## Ancho en metros del carril [param lane] del eje [param axis].
func lane_width(axis: int, lane: int) -> float:
	_ensure_lanes()
	var widths := _widths[axis]
	if lane < 0 or lane >= widths.size():
		return 0.0
	return widths[lane]


## Borde de menor coordenada del carril [param lane], en el espacio local.
func lane_start(axis: int, lane: int) -> float:
	_ensure_lanes()
	var starts := _starts[axis]
	if lane < 0 or lane >= starts.size():
		return 0.0
	return starts[lane]


## Centro del carril [param lane], en el espacio local.
func lane_centre(axis: int, lane: int) -> float:
	return lane_start(axis, lane) + lane_width(axis, lane) * 0.5


## Ancho de calzada + veredas del carril [param lane], o **0** si es un carril de
## edificio. Es la consulta que usa `city_check` para rehacer la cuenta de la
## extensión sin copiar la tabla de anchos.
func street_width_at(axis: int, lane: int) -> float:
	var kind := lane_kind(axis, lane)
	return 0.0 if kind == Lane.BLOCK else lane_width(axis, lane)


## Vereda del carril [param lane], en metros. Cero si no es calle.
func sidewalk_width_at(axis: int, lane: int) -> float:
	match lane_kind(axis, lane):
		Lane.AVENUE:
			return avenue_sidewalk
		Lane.STREET:
			return street_sidewalk
		_:
			return 0.0


# --------------------------------------------------------------------------
# Consultas de rejilla
# --------------------------------------------------------------------------

## Celdas en X (de edificio y de calle).
func get_cols() -> int:
	return lane_count(0)


## Celdas en Z.
func get_rows() -> int:
	return lane_count(1)


## Extensión del distrito, en metros: la **suma de los anchos** de los carriles
## de cada eje, anillo perimetral incluido.
func get_extent() -> Vector2:
	_ensure_lanes()
	return _extent


## Extensión de manzanas y calles interiores, sin el anillo perimetral.
func get_core_extent() -> Vector2:
	_ensure_lanes()
	return get_extent() - Vector2(perimeter_width, perimeter_width) * 2.0


## Verdadero si [param cell] cae sobre calzada en alguno de los dos ejes.
func is_street_cell(cell: Vector2i) -> bool:
	return lane_kind(0, cell.x) != Lane.BLOCK or lane_kind(1, cell.y) != Lane.BLOCK


## Verdadero si [param cell] es un cruce: calle en los dos ejes.
func is_crossing_cell(cell: Vector2i) -> bool:
	return lane_kind(0, cell.x) != Lane.BLOCK and lane_kind(1, cell.y) != Lane.BLOCK


## Centro de [param cell] en el espacio local del distrito, con `y = 0`.
func cell_position(cell: Vector2i) -> Vector3:
	return Vector3(lane_centre(0, cell.x), 0.0, lane_centre(1, cell.y))


## Celda de edificio [param dx], [param dz] de la manzana [param block_x],
## [param block_z].
func block_cell(block_x: int, block_z: int, dx: int, dz: int) -> Vector2i:
	var period := block_span + 1
	return Vector2i(1 + block_x * period + dx, 1 + block_z * period + dz)


## Manzana a la que pertenece [param cell].
func cell_block(cell: Vector2i) -> Vector2i:
	var period := block_span + 1
	return Vector2i((cell.x - 1) / period, (cell.y - 1) / period)


## Posición de [param cell] dentro de su manzana.
func cell_in_block(cell: Vector2i) -> Vector2i:
	var period := block_span + 1
	return Vector2i((cell.x - 1) % period, (cell.y - 1) % period)


## Cruce de las dos avenidas, en el espacio local. Es el punto al que mira el
## centro financiero y donde se concentran los hitos.
func avenue_crossing() -> Vector3:
	var lane_x := 1 + avenue_gap_col * (block_span + 1) + block_span
	var lane_z := 1 + avenue_gap_row * (block_span + 1) + block_span
	return Vector3(lane_centre(0, lane_x), 0.0, lane_centre(1, lane_z))


## Celdas de edificio, en orden fijo (Z externo, X interno). El orden es parte
## del contrato: es lo que hace reproducible el sembrado con la misma semilla.
func building_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for z: int in get_rows():
		if lane_kind(1, z) != Lane.BLOCK:
			continue
		for x: int in get_cols():
			if lane_kind(0, x) != Lane.BLOCK:
				continue
			cells.append(Vector2i(x, z))
	return cells


## Cuántos edificios produce esta rejilla. Con 5 × 3 manzanas de 2 × 2 son
## exactamente **60**.
func building_count() -> int:
	return block_cols * block_rows * block_span * block_span


## Edificios ya sembrados, en el orden en que se crearon.
func get_buildings() -> Array[Building]:
	var found: Array[Building] = []
	var container := get_node_or_null(NodePath(BUILDINGS_NODE))
	if container == null:
		return found
	for child: Node in container.get_children():
		var building := child as Building
		if building != null:
			found.append(building)
	return found


## Edificio de [param cell], o `null` si esa celda es calle.
func get_building_at(cell: Vector2i) -> Building:
	for building: Building in get_buildings():
		if building.get_meta(&"cell", Vector2i(-1, -1)) == cell:
			return building
	return null


## Oclusor de la manzana de [param building], o `null` si ese edificio no es el
## que lo define.
##
## Hay **un oclusor por manzana** y su caja está ceñida al edificio **más alto** de
## esa manzana (ver [method _build_occluders]): mientras ese edificio siga en pie el
## volumen está dentro de geometría opaca y los otros tres pueden caerse sin que el
## oclusor mienta. Por eso esto devuelve el nodo **solo** para el más alto: es el
## único que tiene derecho a apagarlo cuando se derrumba.
##
## Se resuelve por nombre y por metadato, no por un vínculo horneado en
## `district_a.tscn`, para que la escena empaquetada no cambie: los nombres
## `Occluder_<x>_<z>` y el metadato `cell` los escribe esta misma clase al sembrar.
func occluder_for(building: Building) -> OccluderInstance3D:
	if building == null:
		return null
	var cell: Vector2i = building.get_meta(&"cell", Vector2i(-1, -1))
	if cell.x < 0 or cell.y < 0:
		return null
	var container := get_node_or_null(NodePath(OCCLUDERS_NODE))
	if container == null:
		return null
	var block := cell_block(cell)
	var node := container.get_node_or_null(
			NodePath("Occluder_%d_%d" % [block.x, block.y])) as OccluderInstance3D
	if node == null:
		return null
	return node if tallest_in_block(block) == building else null


## Edificio más alto de la manzana [param block], o `null` si no queda ninguno.
## Es el que define el oclusor de esa manzana.
func tallest_in_block(block: Vector2i) -> Building:
	var tallest: Building = null
	for dz: int in block_span:
		for dx: int in block_span:
			var building := get_building_at(block_cell(block.x, block.y, dx, dz))
			if building == null:
				continue
			if tallest == null or building.get_height() > tallest.get_height():
				tallest = building
	return tallest


## Rocas del borde (grupo `city_rocks`).
func get_rocks() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var container := get_node_or_null(NodePath(ROCKS_NODE))
	if container == null:
		return found
	for child: Node in container.get_children():
		var rock := child as Node3D
		if rock != null:
			found.append(rock)
	return found


# --------------------------------------------------------------------------
# Construcción
# --------------------------------------------------------------------------

## Genera el distrito completo de cero. Es idempotente: vuelve a empezar
## borrando lo que hubiera. Con la misma [member seed] produce siempre lo mismo.
func build() -> void:
	_clear_generated()
	_ensure_lanes()
	_rng.seed = seed
	_prop_debt = 0.0

	_build_ground()
	_build_streets()
	_build_buildings()
	_build_occluders()
	_build_rocks()
	_build_spawns()


## Asigna `owner` a todo lo generado para que [method PackedScene.pack] lo
## guarde. Se llama una vez, al final, desde `tools/build_district.gd`.
##
## La regla vale también dentro de las piezas instanciadas: un nodo **sin
## dueño** lo creó [method build] y hay que reclamarlo; uno que ya tiene dueño
## vino dentro de un `PackedScene` y se deja en paz, porque lo que se guarda es
## su instancia con las anulaciones de sus internos.
func claim_ownership(scene_root: Node) -> void:
	for node: Node in _descendants(self):
		if node == scene_root:
			continue
		if node.owner == null:
			node.owner = scene_root


func _clear_generated() -> void:
	for name: StringName in [BUILDINGS_NODE, STREETS_NODE, OCCLUDERS_NODE,
			ROCKS_NODE, SPAWNS_NODE, GROUND_NODE]:
		var existing := get_node_or_null(NodePath(name))
		if existing != null:
			remove_child(existing)
			existing.free()


## Contenedor vacío colgado de la rejilla.
func _container(name: StringName) -> Node3D:
	var node := Node3D.new()
	node.name = name
	add_child(node)
	return node


# --- Suelo -----------------------------------------------------------------

## Un único `StaticBody3D` de capa 1 con una caja de `ground_size × 4 × ground_size`
## centrada en `y = −2`, más un `PlaneMesh` del mismo lado. Cubre el distrito y
## el descampado con **un solo colisionador** (`docs/10` §4.4).
func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = GROUND_NODE
	body.collision_layer = GROUND_LAYER
	body.collision_mask = GROUND_MASK
	add_child(body)

	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	plane.material = ground_material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = plane
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	var box := BoxShape3D.new()
	box.size = Vector3(ground_size, 4.0, ground_size)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "Shape"
	shape_node.shape = box
	shape_node.position = Vector3(0.0, -2.0, 0.0)
	body.add_child(shape_node)


# --- Calles ----------------------------------------------------------------

## Calzada, cruces, veredas y patios en cinco [MultiMeshInstance3D] **sin
## colisión propia**: el suelo lo aporta la caja única de [method _build_ground]
## y la red viaria no suma ni un colisionador (`docs/10` §4.4 y §7).
##
## Reparto, y por qué cada pieza va donde va:
##
## - **Calzada** — un `Road_Chunk_5` cubre los 10 m de ancho de una hilera de una
##   sola vez y se repite **sólo a lo largo**. Las bandas pintadas de la pieza
##   corren sobre su eje X local, así que las calles este–oeste van sin girar y
##   las norte–sur con un cuarto de vuelta ([method _turns]): las marcas quedan
##   siempre a lo largo de la calle y nunca cruzadas.
## - **Cruces** — asfalto liso horneado ([method _build_crossing_mesh]) con el
##   mismo `roads.tres`. Un cruce no lleva las marcas de ninguna de las dos
##   calles.
## - **Veredas** — `Sidewalk_Chunk_2` a escala casi uniforme. La pieza **no trae
##   un cordón modelado**: es una losa plana de 1 m de espesor cuya cara lateral
##   es el cordón, y las dos bandas oscuras de su textura caen sobre los bordes
##   largos. Por eso se la escala poco a lo ancho (0.3 para 3 m) y bastante a lo
##   largo: las bandas quedan justo en el borde de la vereda y el cordón sale de
##   los 15 cm que separan [constant SIDEWALK_TOP] de [constant ROAD_TOP].
## - **Patios** — el interior de la manzana con `Sidewalk_Tile_1` a escala
##   **uniforme** 0.8 (16 m), 2 × 2 por celda: los 20 m nativos no dividen los
##   32 m de la celda, y estirar la baldosa era justo lo que se veía mal.
func _build_streets() -> void:
	var streets := _container(STREETS_NODE)
	var roads_ns: Array[Transform3D] = []
	var roads_ew: Array[Transform3D] = []
	var crossings: Array[Transform3D] = []
	var walks: Array[Transform3D] = []
	var pads: Array[Transform3D] = []

	for lane_x: int in get_cols():
		for lane_z: int in get_rows():
			var cell := Vector2i(lane_x, lane_z)
			var kind_x := lane_kind(0, lane_x)
			var kind_z := lane_kind(1, lane_z)
			if kind_x == Lane.BLOCK and kind_z == Lane.BLOCK:
				_emit_block_pad(pads, cell)
			elif kind_x != Lane.BLOCK and kind_z != Lane.BLOCK:
				_emit_crossing(crossings, walks, cell)
			elif kind_x != Lane.BLOCK:
				_emit_street_segment(roads_ns, walks, cell, false)
			else:
				_emit_street_segment(roads_ew, walks, cell, true)

	var road_mesh := _bake_piece_mesh(road_piece)
	var walk_mesh := _bake_piece_mesh(sidewalk_piece)
	var tile_mesh := _bake_piece_mesh(sidewalk_tile_piece)
	var asphalt_material: Material = null
	if road_mesh != null and road_mesh.get_surface_count() > 0:
		asphalt_material = road_mesh.surface_get_material(0)

	_add_multimesh(streets, ROAD_EW_NODE, road_mesh, roads_ew)
	_add_multimesh(streets, ROAD_NS_NODE, road_mesh, roads_ns)
	_add_multimesh(streets, CROSSINGS_NODE, _build_crossing_mesh(asphalt_material), crossings)
	_add_multimesh(streets, SIDEWALKS_NODE, walk_mesh, walks)
	_add_multimesh(streets, PADS_NODE, tile_mesh, pads)


## Patio de una celda de edificio: 2 × 2 baldosas de 16 m a escala uniforme.
func _emit_block_pad(out: Array[Transform3D], cell: Vector2i) -> void:
	var tiles := 2
	var side := cell_size / float(tiles)
	var scale := side / TILE_PIECE_SIDE
	var basis := Basis.from_scale(Vector3(scale, scale, scale))
	var origin_x := lane_start(0, cell.x)
	var origin_z := lane_start(1, cell.y)
	var top := SIDEWALK_TOP - TILE_PIECE_HEIGHT * scale
	for j: int in tiles:
		for i: int in tiles:
			out.append(Transform3D(basis, Vector3(
					origin_x + side * (float(i) + 0.5), top,
					origin_z + side * (float(j) + 0.5))))


## Tramo de calle entre dos manzanas: calzada (una hilera, o dos con cantero si
## es avenida) más las dos veredas.
##
## [param along_x] indica si la calle corre este–oeste. La calzada de una calle
## norte–sur va girada un cuarto de vuelta para que sus marcas sigan el eje de
## la calle.
func _emit_street_segment(roads: Array[Transform3D], walks: Array[Transform3D],
		cell: Vector2i, along_x: bool) -> void:
	var across_axis := 1 if along_x else 0
	var along_axis := 0 if along_x else 1
	var lane := cell.y if along_x else cell.x
	var span := cell.x if along_x else cell.y
	var from_along := lane_start(along_axis, span)
	var to_along := from_along + lane_width(along_axis, span)
	var start := lane_start(across_axis, lane)
	var width := lane_width(across_axis, lane)
	var walk := sidewalk_width_at(across_axis, lane)

	# Veredas: una en cada borde del carril, con el cordón mirando a la calzada.
	_walk_strip(walks, start + walk * 0.5, walk, from_along, to_along, along_x)
	_walk_strip(walks, start + width - walk * 0.5, walk, from_along, to_along, along_x)

	if lane_kind(across_axis, lane) == Lane.AVENUE:
		# La banda pintada de `Road_Chunk_5` cae siempre sobre el borde de menor
		# coordenada de la pieza. La hilera de vuelta va espejada media vuelta
		# para que las dos bandas queden contra las veredas y no una contra la
		# vereda y la otra contra el cantero.
		_road_strip(roads, start + walk + ROADWAY_WIDTH * 0.5, from_along, to_along,
				along_x, false)
		_road_strip(roads, start + width - walk - ROADWAY_WIDTH * 0.5,
				from_along, to_along, along_x, true)
		_median_strip(walks, start + width * 0.5, from_along, to_along, along_x)
		return
	_road_strip(roads, start + width * 0.5, from_along, to_along, along_x, false)


## Cruce: asfalto liso en todo el rectángulo y una vereda de esquina en cada
## ángulo. La vereda va encima del asfalto —15 cm más alta—, así que el solape
## no se ve y no hace falta recortar el cruce.
func _emit_crossing(crossings: Array[Transform3D], walks: Array[Transform3D],
		cell: Vector2i) -> void:
	var x0 := lane_start(0, cell.x)
	var z0 := lane_start(1, cell.y)
	var width := lane_width(0, cell.x)
	var depth := lane_width(1, cell.y)
	var side := CROSSING_PATCH * float(CROSSING_CELLS)
	var cols := maxi(roundi(width / side), 1)
	var rows := maxi(roundi(depth / side), 1)
	var step_x := width / float(cols)
	var step_z := depth / float(rows)
	var basis := Basis.from_scale(Vector3(step_x / side, 1.0, step_z / side))
	for j: int in rows:
		for i: int in cols:
			crossings.append(Transform3D(basis, Vector3(
					x0 + step_x * (float(i) + 0.5), ROAD_TOP,
					z0 + step_z * (float(j) + 0.5))))

	var walk_x := sidewalk_width_at(0, cell.x)
	var walk_z := sidewalk_width_at(1, cell.y)
	var corner := Basis.from_scale(Vector3(walk_x / WALK_PIECE_SIDE, 1.0,
			walk_z / WALK_PIECE_SIDE))
	var top := SIDEWALK_TOP - WALK_PIECE_HEIGHT
	for sx: int in 2:
		for sz: int in 2:
			var cx := x0 + walk_x * 0.5 if sx == 0 else x0 + width - walk_x * 0.5
			var cz := z0 + walk_z * 0.5 if sz == 0 else z0 + depth - walk_z * 0.5
			walks.append(Transform3D(corner, Vector3(cx, top, cz)))


## Hilera de calzada de 10 m de ancho centrada en [param centre], de
## [param from_along] a [param to_along]. Con [param mirror] la pieza va media
## vuelta girada, que es como se espeja la hilera de vuelta de una avenida.
func _road_strip(out: Array[Transform3D], centre: float, from_along: float,
		to_along: float, along_x: bool, mirror: bool) -> void:
	var length := to_along - from_along
	var tiles := maxi(roundi(length / ROAD_PIECE_SIDE), 1)
	_lay_strip(out, centre, ROADWAY_WIDTH, from_along, to_along, tiles,
			_turns(along_x, mirror), ROAD_PIECE_SIDE, ROAD_PIECE_HEIGHT, ROAD_TOP)


## Franja de vereda de [param width] metros de ancho.
func _walk_strip(out: Array[Transform3D], centre: float, width: float,
		from_along: float, to_along: float, along_x: bool) -> void:
	var length := to_along - from_along
	var tiles := maxi(roundi(length / maxf(width * WALK_TILE_ASPECT, 0.5)), 1)
	_lay_strip(out, centre, width, from_along, to_along, tiles,
			_turns(along_x, false), WALK_PIECE_SIDE, WALK_PIECE_HEIGHT, SIDEWALK_TOP)


## Cantero central de una avenida, con la misma pieza de vereda.
func _median_strip(out: Array[Transform3D], centre: float, from_along: float,
		to_along: float, along_x: bool) -> void:
	if avenue_median <= 0.0:
		return
	var length := to_along - from_along
	var tiles := maxi(roundi(length / maxf(avenue_median * WALK_TILE_ASPECT, 0.5)), 1)
	_lay_strip(out, centre, avenue_median, from_along, to_along, tiles,
			_turns(along_x, false), WALK_PIECE_SIDE, WALK_PIECE_HEIGHT, SIDEWALK_TOP)


## Reparte [param tiles] instancias de una pieza cuadrada de [param piece_side]
## metros a lo largo de una franja.
##
## La escala **a lo ancho** es la que manda: es la que decide si el cordón de la
## vereda o el ancho de la calzada salen bien. La escala a lo largo se deduce del
## número de baldosas, y por eso [method _walk_strip] elige ese número con
## [constant WALK_TILE_ASPECT]: la textura de estas piezas no tiene estructura en
## esa dirección.
func _lay_strip(out: Array[Transform3D], centre: float, across: float,
		from_along: float, to_along: float, tiles: int, turns: int,
		piece_side: float, piece_height: float, top: float) -> void:
	var along_x := turns % 2 == 0
	var step := (to_along - from_along) / float(tiles)
	var scale := Vector3(step / piece_side, 1.0, across / piece_side)
	# El giro se aplica **después** de la escala: así `scale.x` sigue queriendo
	# decir «a lo largo de la franja» y `scale.z` «a lo ancho», cualquiera sea la
	# orientación de la calle.
	var basis := Basis.from_euler(Vector3(0.0, float(turns) * (PI * 0.5), 0.0)) 			* Basis.from_scale(scale)
	var y := top - piece_height
	for index: int in tiles:
		var along := from_along + step * (float(index) + 0.5)
		var origin := Vector3(along, y, centre) if along_x else Vector3(centre, y, along)
		out.append(Transform3D(basis, origin))


## Cuartos de vuelta de una franja: 0 este-oeste, 1 norte-sur, y dos más si va
## espejada.
func _turns(along_x: bool, mirror: bool) -> int:
	return (0 if along_x else 1) + (2 if mirror else 0)


## Baldosa de asfalto liso de los cruces: una rejilla de
## [constant CROSSING_CELLS]² parches de [constant CROSSING_PATCH] m, cada uno
## con las UV de [constant ASPHALT_UV].
##
## Se copia la geometría de un [PlaneMesh] en lugar de escribir los triángulos a
## mano para no tener que adivinar el sentido de giro de las caras frontales; lo
## único propio son las UV, que no pueden compartirse entre parches (cada uno
## repite el mismo trozo de atlas) y por eso la malla sale **sin índices**.
func _build_crossing_mesh(material: Material) -> ArrayMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(CROSSING_PATCH, CROSSING_PATCH)
	plane.orientation = PlaneMesh.FACE_Y
	var arrays := plane.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices = PackedInt32Array()
		for index: int in vertices.size():
			indices.append(index)

	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := CROSSING_PATCH * float(CROSSING_CELLS)
	for gz: int in CROSSING_CELLS:
		for gx: int in CROSSING_CELLS:
			var offset := Vector3(
					-side * 0.5 + CROSSING_PATCH * (float(gx) + 0.5), 0.0,
					-side * 0.5 + CROSSING_PATCH * (float(gz) + 0.5))
			for slot: int in indices.size():
				var vertex := vertices[indices[slot]]
				var u := vertex.x / CROSSING_PATCH + 0.5
				var v := vertex.z / CROSSING_PATCH + 0.5
				builder.set_normal(Vector3.UP)
				builder.set_uv(Vector2(
						ASPHALT_UV.position.x + ASPHALT_UV.size.x * u,
						ASPHALT_UV.position.y + ASPHALT_UV.size.y * v))
				builder.add_vertex(vertex + offset)
	builder.generate_tangents()
	var mesh := builder.commit()
	if mesh != null and material != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	return mesh


## Crea un [MultiMeshInstance3D] con [param mesh] y las [param transforms] dadas.
func _add_multimesh(parent: Node3D, name: StringName, mesh: Mesh,
		transforms: Array[Transform3D]) -> void:
	if mesh == null or transforms.is_empty():
		push_error("CityGrid: el MultiMesh '%s' quedaría vacío." % name)
		return
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = transforms.size()
	multi_mesh.buffer = _multimesh_buffer(transforms)

	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multi_mesh
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## Empaqueta [param transforms] en el formato crudo de [member MultiMesh.buffer]:
## tres filas de cuatro flotantes por instancia (la matriz 3 × 4 por filas).
##
## Se escribe el búfer entero y **no** se usa [method MultiMesh.set_instance_transform]
## a propósito: esa vía guarda las transformadas dentro del `RenderingServer`, y
## el servidor de `--headless` —que es donde corre `tools/build_district.gd`— no
## las retiene, así que `get_buffer()` devolvería vacío y `district_a.tscn` se
## guardaría con todas las instancias en el origen. Asignar `buffer` escribe la
## propiedad del recurso, que sí se serializa.
func _multimesh_buffer(transforms: Array[Transform3D]) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(transforms.size() * 12)
	var cursor := 0
	for xform: Transform3D in transforms:
		for row: int in 3:
			data[cursor] = xform.basis.x[row]
			data[cursor + 1] = xform.basis.y[row]
			data[cursor + 2] = xform.basis.z[row]
			data[cursor + 3] = xform.origin[row]
			cursor += 4
	return data


## Copia la malla de una pieza de calle horneando la transformada de su nodo.
##
## Se copia en vez de referenciar `<fbx>::ArrayMesh_xxx` a propósito: el id de
## un subrecurso de escena importada lo genera el importador y cambia si se
## vuelve a importar, con lo que `district_a.tscn` quedaría apuntando a la nada.
## La copia son 12 a 28 triángulos y viaja dentro del `.tscn`.
func _bake_piece_mesh(piece: PackedScene) -> ArrayMesh:
	if piece == null:
		return null
	var root := piece.instantiate()
	var source: MeshInstance3D = null
	for node: Node in _descendants(root):
		var candidate := node as MeshInstance3D
		if candidate != null and candidate.mesh != null:
			source = candidate
			break
	if source == null:
		root.free()
		push_error("CityGrid: la pieza '%s' no tiene malla." % piece.resource_path)
		return null

	var xform := source.transform
	var arrays := source.mesh.surface_get_arrays(0)
	var material := source.mesh.surface_get_material(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(vertices.size())
	for index: int in vertices.size():
		moved[index] = xform * vertices[index]
	arrays[Mesh.ARRAY_VERTEX] = moved
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var turned := PackedVector3Array()
		turned.resize(normals.size())
		for index: int in normals.size():
			turned[index] = (xform.basis * normals[index]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = turned
	root.free()

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


# --- Edificios -------------------------------------------------------------

## Siembra los 60 edificios. Elige rol por cercanía al centro, reparte los hitos
## por el centro y las avenidas, y apoya cada fachada sobre la línea municipal
## del lado de manzana que le toca.
func _build_buildings() -> void:
	var container := _container(BUILDINGS_NODE)
	var cells := building_cells()
	var ranked := cells.duplicate()
	# Centro financiero: las `tall_count` celdas más cercanas al centro. El
	# desempate por índice mantiene el orden determinista.
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := cell_position(a).length_squared()
		var db := cell_position(b).length_squared()
		if is_equal_approx(da, db):
			return cells.find(a) < cells.find(b)
		return da < db)

	var landmarks := _pick_landmarks(ranked)
	var role_by_cell: Dictionary[Vector2i, int] = {}
	for index: int in ranked.size():
		# 0 = hito, 1 = torre media, 2 = bloque bajo.
		var role := 2
		if index < tall_count:
			role = 0 if landmarks.has(ranked[index]) else 1
		role_by_cell[ranked[index]] = role

	var facing_by_cell := _pick_facings()
	var mid_pick := 0
	for cell: Vector2i in cells:
		var role: int = role_by_cell[cell]
		var piece: PackedScene = null
		var profile: BuildingProfile = null
		var height_scale := 1.0
		match role:
			0:
				piece = _pick(tall_pieces)
				profile = tall_profile
				height_scale = _rng.randf_range(LANDMARK_SCALE_MIN, LANDMARK_SCALE_MAX)
			1:
				# Alternancia fija entre las dos piezas de torre media: con RNG
				# podían salir siete iguales y el anillo perdía variedad.
				piece = mid_tower_pieces[mid_pick % maxi(mid_tower_pieces.size(), 1)] \
						if not mid_tower_pieces.is_empty() else null
				mid_pick += 1
				profile = tall_profile
				height_scale = _rng.randf_range(MID_TOWER_SCALE_MIN, MID_TOWER_SCALE_MAX)
			_:
				piece = _pick(low_pieces)
				profile = low_profile
				height_scale = _rng.randf_range(LOW_SCALE_MIN, LOW_SCALE_MAX)
		var building := _spawn_building(piece, profile, cell,
				int(facing_by_cell.get(cell, 0)), height_scale)
		if building == null:
			continue
		container.add_child(building)


## Elige las celdas de los hitos: las más cercanas al centro y a las avenidas,
## pero **separadas entre sí**, para que la silueta alta no se apelotone en una
## sola manzana. Si con la separación pedida no entran todos, se relaja de a
## 8 m hasta que entren.
func _pick_landmarks(ranked: Array[Vector2i]) -> Dictionary[Vector2i, bool]:
	var chosen: Dictionary[Vector2i, bool] = {}
	if tall_primary_count <= 0 or tall_pieces.is_empty():
		return chosen
	var crossing := avenue_crossing()
	var pool := ranked.slice(0, mini(tall_count, ranked.size()))
	pool.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := cell_position(a).distance_to(crossing) + cell_position(a).length() * 0.5
		var db := cell_position(b).distance_to(crossing) + cell_position(b).length() * 0.5
		if is_equal_approx(da, db):
			return ranked.find(a) < ranked.find(b)
		return da < db)

	var spacing := LANDMARK_SPACING
	while spacing > 0.0:
		chosen.clear()
		var picked: Array[Vector3] = []
		for cell: Vector2i in pool:
			if chosen.size() >= tall_primary_count:
				break
			var here := cell_position(cell)
			var far_enough := true
			for other: Vector3 in picked:
				if here.distance_to(other) < spacing:
					far_enough = false
					break
			if far_enough:
				chosen[cell] = true
				picked.append(here)
		if chosen.size() >= tall_primary_count:
			break
		spacing -= 8.0
	return chosen


## Orientación de la fachada de cada celda, en pasos de 90°: 0 = −Z, 1 = −X,
## 2 = +Z, 3 = +X. Coincide con `yaw_steps`, porque un giro de 90° lleva el −Z
## local a −X, el de 180° a +Z y el de 270° a +X.
##
## Cada celda de una manzana de 2 × 2 toca **dos** lados de la manzana, así que
## sólo dos de las cuatro orientaciones son válidas. Los cuatro patrones son los
## que respetan esa restricción: dos molinetes (un edificio por lado) y dos
## «peines» (dos edificios sobre el mismo lado, que es lo que da frente continuo
## de manzana). El patrón se sortea por manzana.
func _pick_facings() -> Dictionary[Vector2i, int]:
	var patterns: Array[PackedInt32Array] = [
		PackedInt32Array([0, 3, 1, 2]),
		PackedInt32Array([1, 0, 2, 3]),
		PackedInt32Array([0, 0, 2, 2]),
		PackedInt32Array([1, 3, 1, 3]),
	]
	var facings: Dictionary[Vector2i, int] = {}
	for block_z: int in block_rows:
		for block_x: int in block_cols:
			var pattern := patterns[_rng.randi_range(0, patterns.size() - 1)]
			for dz: int in block_span:
				for dx: int in block_span:
					var cell := block_cell(block_x, block_z, dx, dz)
					var slot := dz * block_span + dx
					facings[cell] = pattern[slot % pattern.size()]
	return facings


## Posición del edificio de la celda [param cell] con la fachada [param facing]
## apoyada en la línea municipal, para una pieza de [param depth] metros de fondo.
##
## La fachada se apoya en el borde de la celda que da a la calle; el fondo entra
## hacia el interior de la manzana y lo que sobra es patio. El frente —el lado
## largo de la pieza— queda centrado en la celda, y por eso acá sólo hace falta
## el fondo.
func _facade_position(cell: Vector2i, facing: int, depth: float) -> Vector3:
	var x0 := lane_start(0, cell.x)
	var x1 := x0 + lane_width(0, cell.x)
	var z0 := lane_start(1, cell.y)
	var z1 := z0 + lane_width(1, cell.y)
	var centre := cell_position(cell)
	# El frente se centra en la celda; el fondo se apoya contra la línea.
	var half := depth * 0.5
	match facing:
		1:
			return Vector3(x0 + half, SIDEWALK_TOP, centre.z)
		2:
			return Vector3(centre.x, SIDEWALK_TOP, z1 - half)
		3:
			return Vector3(x1 - half, SIDEWALK_TOP, centre.z)
		_:
			return Vector3(centre.x, SIDEWALK_TOP, z0 + half)


## Instancia una pieza, le pone el script [Building] y le monta los nodos de
## etapa. Devuelve el edificio **fuera del árbol**; quien llama lo cuelga.
func _spawn_building(piece: PackedScene, profile: BuildingProfile, cell: Vector2i,
		facing: int, height_scale: float) -> Building:
	if piece == null or profile == null:
		push_error("CityGrid: falta la pieza o el perfil de la celda %s." % str(cell))
		return null
	var root := piece.instantiate() as StaticBody3D
	if root == null:
		push_error("CityGrid: la pieza '%s' no tiene raíz StaticBody3D." % piece.resource_path)
		return null

	var mesh_instance: MeshInstance3D = null
	for node: Node in root.get_children():
		if mesh_instance == null and node is MeshInstance3D:
			mesh_instance = node as MeshInstance3D
		var player := node as AnimationPlayer
		if player != null:
			# El pack trae un `AnimationPlayer` vacío por pieza; sin animaciones
			# no cuesta nada, pero tampoco hace falta que procese.
			player.process_mode = Node.PROCESS_MODE_DISABLED
	var shape_node := root.get_node_or_null(NodePath(PIECE_SHAPE)) as CollisionShape3D
	if mesh_instance == null or shape_node == null:
		push_error("CityGrid: la pieza '%s' no trae malla o '%s'." % [piece.resource_path, PIECE_SHAPE])
		root.free()
		return null

	var base_size: Vector3 = root.get_meta(&"base_size", Vector3(20.0, 12.5, 11.0))
	# El post-import deja la forma en el centro del AABB, y el origen de estas
	# piezas está en una esquina: ese offset es lo que hay que anular para que
	# la huella quede centrada sobre la celda y el giro sea en torno a su eje.
	var centre := shape_node.position
	var rest := Transform3D(Basis.IDENTITY, Vector3(-centre.x, 0.0, -centre.z)) * mesh_instance.transform

	root.set_script(ResourceLoader.load(BUILDING_SCRIPT, "Script"))
	var building := root as Building
	building.name = "Building_%d_%d" % [cell.x, cell.y]
	building.set_meta(&"cell", cell)
	building.set_meta(&"facing", facing)
	building.set_meta(&"piece", StringName(piece.resource_path.get_file().get_basename()))
	building.profile = profile
	building.base_size = base_size
	building.stage_intact = mesh_instance
	building.intact_rest_transform = rest
	building.intact_shape = shape_node
	building.debris_pool = debris_pool
	# La `BoxShape3D` viene del `PackedScene` y la comparten todas las instancias
	# de la misma pieza: sin duplicarla, la variación de altura de un edificio
	# reescribiría la de sus diez hermanos.
	shape_node.shape = shape_node.shape.duplicate()

	building.rubble_shape = _make_rubble_shape(building)
	_make_rubble_stage(building, profile)
	building.dust_burst = _make_dust(building, profile)
	building.props = _make_props(building, base_size)

	# El frente largo de la pieza (`base_size.x`) va sobre la calle y el fondo
	# (`base_size.z`) entra en la manzana: por eso la línea municipal se calcula
	# con el fondo, no con el ancho.
	building.position = _facade_position(cell, facing, base_size.z)
	building.apply_variation(height_scale, facing)
	return building


## Caja baja de la ruina, deshabilitada hasta que termina el derrumbe.
func _make_rubble_shape(building: Building) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var node := CollisionShape3D.new()
	node.name = "RubbleShape"
	node.shape = box
	node.disabled = true
	building.add_child(node)
	return node


## Montículo de cascotes y columna de humo, ocultos hasta el derrumbe.
func _make_rubble_stage(building: Building, profile: BuildingProfile) -> void:
	var stage := Node3D.new()
	stage.name = "StageRubble"
	stage.visible = false
	building.add_child(stage)
	building.stage_rubble = stage

	var pile_mesh := profile.pick_rubble_mesh(building.base_size.y * building.height_scale)
	if pile_mesh != null:
		var pile := MeshInstance3D.new()
		pile.name = "Pile"
		pile.mesh = pile_mesh
		# Riesgo 9 del plan: geometría que aparece a mitad de partida no
		# participa de SDFGI.
		pile.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		stage.add_child(pile)
		building.rubble_pile = pile

	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.emitting = false
	smoke.amount = 40
	smoke.lifetime = 6.0
	smoke.fixed_fps = 30
	smoke.interpolate = true
	smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	smoke.process_material = _SMOKE_PROCESS
	smoke.draw_pass_1 = _SMOKE_QUAD
	smoke.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_range_end = Building.SMOKE_VISIBILITY_RANGE_END
	smoke.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	smoke.position = Vector3(0.0, 4.0, 0.0)
	stage.add_child(smoke)
	building.smoke = smoke


## Estallido de polvo de cada transición de etapa.
func _make_dust(building: Building, profile: BuildingProfile) -> GPUParticles3D:
	var dust := GPUParticles3D.new()
	dust.name = "DustBurst"
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.amount = 30
	dust.lifetime = 2.4
	dust.fixed_fps = 30
	dust.interpolate = true
	dust.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	dust.process_material = _DUST_PROCESS
	dust.draw_pass_1 = _DUST_QUAD
	dust.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.visibility_range_end = Building.SMOKE_VISIBILITY_RANGE_END
	dust.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	dust.position = Vector3(0.0, building.base_size.y * 0.35, 0.0)
	dust.amount_ratio = clampf(profile.dust_scale, 0.15, 1.0)
	building.add_child(dust)
	return dust


## Props de azotea en el [member prop_chance] de los edificios. No llevan
## colisión: son decorativos y se desprenden al entrar en `DAMAGED`.
func _make_props(building: Building, base_size: Vector3) -> Node3D:
	# Reparto por deuda acumulada y no por tirada de dado: con 60 muestras una
	# Bernoulli de p = 0.30 se va con facilidad al 40 %, y `docs/10` §4.3 pide un
	# 30 % exacto. Así salen 18 props repartidos de forma pareja por la rejilla.
	_prop_debt += prop_chance
	if prop_pieces.is_empty() or _prop_debt < 1.0:
		return null
	_prop_debt -= 1.0
	var container := Node3D.new()
	container.name = "Props"
	building.add_child(container)

	var prop_scene := _pick(prop_pieces)
	var prop := prop_scene.instantiate() as Node3D
	if prop == null:
		container.free()
		return null
	# Los props son decorativos: se los saca de toda capa en vez de desactivar su
	# `CollisionShape3D`, porque la capa y la máscara son propiedades de la raíz
	# de la instancia —y esas sí se guardan al empaquetar—, mientras que tocar un
	# nodo interno se perdería. Un cuerpo con capa y máscara 0 no participa de
	# nada, que es lo que se busca: `docs/10` §7 no quiere 18 colisionadores más.
	#
	# El desvanecimiento a 180 m no se pone acá: ya lo dejó `import_city_piece.gd`
	# en las mallas de los cuatro props (`docs/10` §2.4 punto 3).
	var body := prop as PhysicsBody3D
	if body != null:
		body.collision_layer = 0
		body.collision_mask = 0

	# Giro en pasos de 90° y voladizo acotado: el prop tiene que apoyar **entero**
	# sobre la azotea. Con la antena a 1,8 m y los carteles a 3,4 y 5,9 m (WP-24b
	# reescaló los `.import`), medio metro de margen alcanza para que no asome por
	# el borde ni siquiera en la pieza de 20 × 10 m.
	var steps := _rng.randi_range(0, 3)
	var prop_size: Vector3 = prop.get_meta(&"base_size", Vector3(2.0, 2.0, 2.0))
	var footprint := Vector2(prop_size.x, prop_size.z)
	if steps % 2 == 1:
		footprint = Vector2(prop_size.z, prop_size.x)
	var margin_x := maxf((base_size.x - footprint.x) * 0.5 - 0.5, 0.0)
	var margin_z := maxf((base_size.z - footprint.y) * 0.5 - 0.5, 0.0)
	# Altura **sin** variación: `Building.apply_variation()` (que corre después, en
	# `_spawn_building`) y `Building.reset()` la escalan con `height_scale` y guardan
	# la posición de reposo en `Building.PROP_REST_META`.
	prop.position = Vector3(
			_rng.randf_range(-margin_x, margin_x),
			base_size.y,
			_rng.randf_range(-margin_z, margin_z))
	prop.rotation = Vector3(0.0, float(steps) * (PI * 0.5), 0.0)
	container.add_child(prop)
	return container


# --- Oclusores, rocas y apariciones ----------------------------------------

## Un [OccluderInstance3D] de caja por manzana, ceñido al **edificio más alto**
## de esa manzana.
##
## `docs/10` §7 pide «uno por bloque de 2 × 2»; ceñirlo a una manzana entera
## taparía también los huecos entre edificios y haría desaparecer geometría que
## sí se ve. Ceñirlo al más alto conserva la cuenta de 15 oclusores y es
## conservador: el volumen siempre está dentro de geometría opaca.
func _build_occluders() -> void:
	var container := _container(OCCLUDERS_NODE)
	for block_z: int in block_rows:
		for block_x: int in block_cols:
			var tallest := tallest_in_block(Vector2i(block_x, block_z))
			if tallest == null:
				continue
			var height := tallest.get_height()
			var box := BoxOccluder3D.new()
			box.size = Vector3(tallest.base_size.x * 0.88, height * 0.94,
					tallest.base_size.z * 0.88)
			var node := OccluderInstance3D.new()
			node.name = "Occluder_%d_%d" % [block_x, block_z]
			node.occluder = box
			node.position = tallest.position + Vector3(0.0, height * 0.47, 0.0)
			node.rotation = tallest.rotation
			container.add_child(node)


## Seis rocas de 8 a 18 m en el borde, en el grupo `city_rocks` (`docs/10` §4.4).
##
## Ninguna cae dentro del cono de [constant SPAWN_CONE_DEG] grados que sale del
## punto de aparición del dron hacia el centro de la ciudad: en WP-21 una roca de
## 40 m tapaba media pantalla en el primer fotograma de la ronda. La lista está
## escrita en múltiplos del semieje del distrito para que siga valiendo si cambia
## el tamaño de la rejilla.
func _build_rocks() -> void:
	var container := _container(ROCKS_NODE)
	if rock_scenes.is_empty():
		return
	var spots := rock_spots()
	for index: int in spots.size():
		var scene := rock_scenes[index % rock_scenes.size()]
		var rock := scene.instantiate() as Node3D
		if rock == null:
			continue
		rock.name = "Rock_%d" % index
		rock.position = spots[index]
		rock.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
		container.add_child(rock)


## Las seis posiciones de roca, en el espacio local del distrito.
func rock_spots() -> Array[Vector3]:
	var extent := get_extent()
	var half := Vector3(extent.x * 0.5, 0.0, extent.y * 0.5)
	return [
		Vector3(-half.x - 69.0, 0.0, half.z + 39.0),
		Vector3(-half.x - 84.0, 0.0, half.z - 76.0),
		Vector3(-half.x * 0.7, 0.0, half.z + 79.0),
		Vector3(half.x * 0.83, 0.0, half.z + 129.0),
		Vector3(half.x + 69.0, 0.0, half.z - 76.0),
		Vector3(half.x + 84.0, 0.0, half.z + 14.0),
	]


## Ángulo, en grados, entre la línea que une el punto de aparición del dron con
## el centro de la ciudad y [param spot]. `city_check` la usa para comprobar el
## cono; la rejilla, para informarlo.
func spawn_cone_angle(spot: Vector3) -> float:
	return _flat_angle(Vector3.ZERO - DRONE_SPAWN, spot - DRONE_SPAWN)


## Ángulo, en grados, entre el rumbo real del dron al aparecer y [param spot].
func spawn_view_angle(spot: Vector3) -> float:
	return _flat_angle(DRONE_FACING, spot - DRONE_SPAWN)


func _flat_angle(reference: Vector3, target: Vector3) -> float:
	var a := Vector3(reference.x, 0.0, reference.z)
	var b := Vector3(target.x, 0.0, target.z)
	if a.length_squared() < 0.01 or b.length_squared() < 0.01:
		return 0.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


## Cuatro `Marker3D` en los accesos del distrito, que es por donde `RoundManager`
## hace entrar al coloso (`docs/11` §4.2, punto pendiente 13).
func _build_spawns() -> void:
	var container := _container(SPAWNS_NODE)
	var extent := get_extent()
	var half := Vector3(extent.x * 0.5, 0.0, extent.y * 0.5)
	var spots: Array[Vector3] = [
		Vector3(0.0, 0.0, -half.z - 40.0),
		Vector3(0.0, 0.0, half.z + 40.0),
		Vector3(-half.x - 40.0, 0.0, 0.0),
		Vector3(half.x + 40.0, 0.0, 0.0),
	]
	for index: int in spots.size():
		var marker := Marker3D.new()
		marker.name = "EnemySpawn%d" % index
		marker.position = spots[index]
		# Giro calculado a mano y no con `look_at_from_position`: durante el
		# horneado la rejilla todavía no está en el árbol y `global_transform`
		# no está definida.
		var facing := (-spots[index]).normalized()
		marker.rotation = Vector3(0.0, atan2(-facing.x, -facing.z), 0.0)
		container.add_child(marker)


# --- Utilidades ------------------------------------------------------------

const _DUST_PROCESS: ParticleProcessMaterial = preload("res://assets/city/rubble/dust_process.tres")
const _SMOKE_PROCESS: ParticleProcessMaterial = preload("res://assets/city/rubble/smoke_process.tres")
const _DUST_QUAD: Mesh = preload("res://assets/city/rubble/dust_quad.tres")
const _SMOKE_QUAD: Mesh = preload("res://assets/city/rubble/smoke_quad.tres")


func _pick(options: Array[PackedScene]) -> PackedScene:
	if options.is_empty():
		return null
	return options[_rng.randi_range(0, options.size() - 1)]


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
