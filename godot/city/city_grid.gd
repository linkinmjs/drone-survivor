## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Rejilla del distrito (`docs/10` §4).
##
## Siembra manzanas de `block_span × block_span` celdas de edificio separadas por
## una celda de calle, coloca **exactamente** [method building_count] edificios,
## dibuja calzada y veredas con tres [MultiMeshInstance3D], apoya todo sobre una
## única caja de suelo y remata con oclusores, rocas y puntos de aparición.
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
## edificio. La rejilla pasa de 360 × 216 m a **480 × 288 m**; la cuenta de
## edificios (60), el reparto de HP y todo lo demás quedan igual.
@tool
class_name CityGrid extends Node3D

## Nombres de los contenedores generados. `build()` los recrea de cero.
const BUILDINGS_NODE: StringName = &"Buildings"
const STREETS_NODE: StringName = &"Streets"
const OCCLUDERS_NODE: StringName = &"Occluders"
const ROCKS_NODE: StringName = &"Rocks"
const SPAWNS_NODE: StringName = &"Spawns"
const GROUND_NODE: StringName = &"Ground"

## Script que se pone sobre la raíz de cada pieza al sembrarla (`docs/10` §2.5).
const BUILDING_SCRIPT: String = "res://city/building.gd"

## Nodo de colisión que dejó el post-import en cada pieza.
const PIECE_SHAPE: StringName = &"IntactShape"

## Capas de `docs/10` §9.4.
const GROUND_LAYER: int = 1
const GROUND_MASK: int = 294

## Variación de altura por rol (`docs/10` §4.3 adaptada a las piezas reales).
const TALL_SCALE_MIN: float = 0.40
const TALL_SCALE_MAX: float = 0.55
const MID_TOWER_SCALE_MIN: float = 1.20
const MID_TOWER_SCALE_MAX: float = 1.35
const LOW_SCALE_MIN: float = 0.85
const LOW_SCALE_MAX: float = 1.35

## Alturas a las que se apoyan calzada y veredas, en metros sobre `y = 0`.
const ROAD_TOP: float = 0.03
const SIDEWALK_TOP: float = 0.18

## Lado de la celda, en metros. Ver la nota de cabecera: 32 y no 24.
@export_range(8.0, 100.0, 0.5) var cell_size: float = 32.0

## Manzanas en X y en Z.
@export_range(1, 20) var block_cols: int = 5
@export_range(1, 20) var block_rows: int = 3

## Celdas de edificio por lado de manzana y celdas de calle entre manzanas.
@export_range(1, 8) var block_span: int = 2
@export_range(1, 8) var street_span: int = 1

## Semilla del sembrado. `district_a` se generó con **0**.
@export var seed: int = 0

## Torres del centro financiero. El resto de las celdas son bloques bajos.
@export_range(0, 400) var tall_count: int = 21

## De las torres, cuántas usan la pieza alta de verdad (`Building_3`, 81 m). Las
## demás son «torres bajas» con las piezas de 12,5 m estiradas.
@export_range(0, 400) var tall_primary_count: int = 14

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

## Piezas de calle, de las que se hornean las tres mallas de [MultiMesh].
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


# --------------------------------------------------------------------------
# Consultas de rejilla
# --------------------------------------------------------------------------

## Celdas en X (edificio y calle).
func get_cols() -> int:
	return block_cols * (block_span + street_span)


## Celdas en Z.
func get_rows() -> int:
	return block_rows * (block_span + street_span)


## Extensión del distrito, en metros.
func get_extent() -> Vector2:
	return Vector2(float(get_cols()) * cell_size, float(get_rows()) * cell_size)


## Verdadero si [param cell] es calle. El patrón tiene período
## `block_span + street_span`: las últimas `street_span` filas o columnas de cada
## período son calzada.
func is_street_cell(cell: Vector2i) -> bool:
	var period := block_span + street_span
	return posmod(cell.x, period) >= block_span or posmod(cell.y, period) >= block_span


## Verdadero si [param cell] es un cruce: calle en los dos ejes.
func is_crossing_cell(cell: Vector2i) -> bool:
	var period := block_span + street_span
	return posmod(cell.x, period) >= block_span and posmod(cell.y, period) >= block_span


## Centro de [param cell] en el espacio local del distrito, con `y = 0`.
func cell_position(cell: Vector2i) -> Vector3:
	return Vector3(
			(float(cell.x) + 0.5 - float(get_cols()) * 0.5) * cell_size,
			0.0,
			(float(cell.y) + 0.5 - float(get_rows()) * 0.5) * cell_size)


## Celdas de edificio, en orden fijo (Z externo, X interno). El orden es parte
## del contrato: es lo que hace reproducible el sembrado con la misma semilla.
func building_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for z: int in get_rows():
		for x: int in get_cols():
			var cell := Vector2i(x, z)
			if not is_street_cell(cell):
				cells.append(cell)
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

## Calzada, cruces y veredas en tres [MultiMeshInstance3D] **sin colisión
## propia**: 3 lotes de dibujo para toda la red viaria y ~120 colisionadores
## menos que si cada tramo fuera un cuerpo (`docs/10` §4.4 y §7).
func _build_streets() -> void:
	var streets := _container(STREETS_NODE)
	var sub := cell_size / 3.0
	var chunk_scale := sub / 10.0
	var tile_scale := cell_size / 20.0

	var roads: Array[Transform3D] = []
	var crossings: Array[Transform3D] = []
	var pads: Array[Transform3D] = []

	for z: int in get_rows():
		for x: int in get_cols():
			var cell := Vector2i(x, z)
			var centre := cell_position(cell)
			if not is_street_cell(cell):
				pads.append(Transform3D(
						Basis.from_scale(Vector3(tile_scale, tile_scale, tile_scale)),
						centre + Vector3(0.0, SIDEWALK_TOP - tile_scale, 0.0)))
				continue
			var target := crossings if is_crossing_cell(cell) else roads
			# Tres por tres tramos de 10 m por celda: mantiene la densidad de
			# textura del pack en vez de estirar un único tramo a 32 m.
			var top := ROAD_TOP - (chunk_scale if is_crossing_cell(cell) else chunk_scale * 0.5)
			for j: int in 3:
				for i: int in 3:
					target.append(Transform3D(
							Basis.from_scale(Vector3(chunk_scale, chunk_scale, chunk_scale)),
							centre + Vector3((float(i) - 1.0) * sub, top, (float(j) - 1.0) * sub)))

	_add_multimesh(streets, "Road", road_piece, roads)
	_add_multimesh(streets, "Crossings", sidewalk_piece, crossings)
	_add_multimesh(streets, "Sidewalks", sidewalk_tile_piece, pads)


## Crea un [MultiMeshInstance3D] con la malla horneada de [param piece] y las
## [param transforms] dadas.
func _add_multimesh(parent: Node3D, name: String, piece: PackedScene,
		transforms: Array[Transform3D]) -> void:
	var mesh := _bake_piece_mesh(piece)
	if mesh == null or transforms.is_empty():
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
## guardaría con las 735 instancias en el origen. Asignar `buffer` escribe la
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

## Siembra los 60 edificios: elige rol por cercanía al centro, pieza por rol y
## variante al azar, y posiciona en el centro de la celda con giro en pasos de
## 90° y variación de altura.
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

	var role_by_cell: Dictionary[Vector2i, int] = {}
	for index: int in ranked.size():
		# 0 = torre alta, 1 = torre baja, 2 = bloque bajo.
		var role := 2
		if index < tall_count:
			role = 0 if index < tall_primary_count else 1
		role_by_cell[ranked[index]] = role

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
				height_scale = _rng.randf_range(TALL_SCALE_MIN, TALL_SCALE_MAX)
			1:
				# Alternancia fija entre las dos piezas de torre baja: con RNG
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
		var building := _spawn_building(piece, profile, cell, height_scale)
		if building == null:
			continue
		container.add_child(building)


## Instancia una pieza, le pone el script [Building] y le monta los nodos de
## etapa. Devuelve el edificio **fuera del árbol**; quien llama lo cuelga.
func _spawn_building(piece: PackedScene, profile: BuildingProfile, cell: Vector2i,
		height_scale: float) -> Building:
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

	building.position = cell_position(cell)
	building.apply_variation(height_scale, _rng.randi_range(0, 3))
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
	# Altura **sin** variación: `Building.apply_variation()` (que corre después, en
	# `_make_building`) y `Building.reset()` la escalan con `height_scale` y guardan
	# la posición de reposo en `Building.PROP_REST_META`.
	prop.position = Vector3(
			_rng.randf_range(-0.22, 0.22) * base_size.x,
			base_size.y,
			_rng.randf_range(-0.22, 0.22) * base_size.z)
	prop.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
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
	var period := block_span + street_span
	for block_z: int in block_rows:
		for block_x: int in block_cols:
			var tallest: Building = null
			for dz: int in block_span:
				for dx: int in block_span:
					var cell := Vector2i(block_x * period + dx, block_z * period + dz)
					var building := get_building_at(cell)
					if building == null:
						continue
					if tallest == null or building.get_height() > tallest.get_height():
						tallest = building
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


## Seis rocas a 45–80 m del perímetro, en el grupo `city_rocks` (`docs/10` §4.4).
func _build_rocks() -> void:
	var container := _container(ROCKS_NODE)
	if rock_scenes.is_empty():
		return
	var extent := get_extent()
	var half := Vector3(extent.x * 0.5, 0.0, extent.y * 0.5)
	var spots: Array[Vector3] = [
		Vector3(-half.x - 72.0, 0.0, -half.z - 58.0),
		Vector3(half.x + 78.0, 0.0, -half.z - 46.0),
		Vector3(half.x + 63.0, 0.0, half.z + 70.0),
		Vector3(-half.x - 54.0, 0.0, half.z + 52.0),
		Vector3(-18.0, 0.0, -half.z - 76.0),
		Vector3(26.0, 0.0, half.z + 74.0),
	]
	for index: int in spots.size():
		var scene := rock_scenes[index % rock_scenes.size()]
		var rock := scene.instantiate() as Node3D
		if rock == null:
			continue
		rock.name = "Rock_%d" % index
		rock.position = spots[index]
		rock.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
		container.add_child(rock)


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
