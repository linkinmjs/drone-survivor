## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Post-import de las 13 piezas de ciudad del pack FreeSample (`docs/10` §2.4).
##
## Se ejecuta una vez por FBX al final de la importación, cuando los
## `ImporterMeshInstance3D` ya son `MeshInstance3D` con `ArrayMesh`, los LOD ya
## están generados y `nodes/root_scale` ya está horneado en los vértices. Deja
## la pieza lista para que WP-20 le ponga el script `Building`: raíz
## `StaticBody3D` en la capa `city`, una forma de colisión determinista por tabla
## de nombres, los materiales de ciudad asignados y los metadatos `piece_id` y
## `base_size` para que `CityGrid` no recalcule dimensiones en tiempo de
## ejecución.
##
## Los LOD **no** se generan aquí: los produce el importador con
## `meshes/generate_lods = true`. Este script tampoco añade scripts a los nodos.
@tool
extends EditorScenePostImport

## Nombre del nodo de colisión. `docs/10` §2.5 lo declara como nodo estable de
## las escenas heredadas: `Building.intact_shape` apunta a él.
const SHAPE_NAME: StringName = &"IntactShape"

## Distancia a la que los props se desvanecen (`docs/10` §2.4 punto 3 y §7).
const PROP_VISIBILITY_RANGE_END: float = 180.0

## Piezas decorativas de `docs/10` §2.1. Son las mismas cuatro que llevan
## `ConvexPolygonShape3D` en §2.4 punto 2: la coincidencia es intencional, un
## cartel y una antena no son cajas. El resto usa `BoxShape3D`, porque los
## edificios sí lo son y además `Building.apply_variation()` (§4.3) reescribe
## `BoxShape3D.size.y` para la variación de altura.
const PROP_PIECES: Array[StringName] = [
	&"Advertising_5", &"Advertising_6", &"Advertising_7", &"SateliteDish",
]

## Familia de material de cada pieza. Sale de las referencias de textura que
## declara cada FBX del pack, verificadas una a una al extraer el ZIP.
const FAMILY_BY_PIECE: Dictionary[StringName, StringName] = {
	&"Advertising_5": &"props",
	&"Advertising_6": &"props",
	&"Advertising_7": &"props",
	&"SateliteDish": &"props",
	&"BuildingBlock_18": &"buildings_001",
	&"BuildingBlock_19": &"buildings_001",
	&"BuildingBlock_24": &"buildings_001",
	&"Building_3": &"buildings_002",
	&"BuildingBlock_1": &"buildings_002",
	&"BuildingBlock_2": &"buildings_002",
	&"Road_Chunk_5": &"roads",
	&"Sidewalk_Chunk_2": &"roads",
	&"Sidewalk_Tile_1": &"roads",
}

## Material compartido de cada familia. Los cuatro `.tres` llevan la difusa y la
## emisiva ya redimensionadas de `assets/city/textures/`.
const MATERIAL_BY_FAMILY: Dictionary[StringName, String] = {
	&"buildings_001": "res://assets/city/materials/buildings_001.tres",
	&"buildings_002": "res://assets/city/materials/buildings_002.tres",
	&"props": "res://assets/city/materials/props.tres",
	&"roads": "res://assets/city/materials/roads.tres",
}


## Punto de entrada del importador. Devuelve la misma escena, modificada.
func _post_import(scene: Node) -> Object:
	var piece_id := StringName(get_source_file().get_file().get_basename())
	var body := _ensure_static_body(scene)
	body.collision_layer = PhysicsLayers.CITY
	body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.DRONE \
			| PhysicsLayers.ENEMY_BODY | PhysicsLayers.PROJECTILE_PLAYER \
			| PhysicsLayers.PROJECTILE_ENEMY | PhysicsLayers.DEBRIS

	var meshes := _collect_meshes(body)
	if meshes.is_empty():
		push_error("import_city_piece: '%s' no tiene ningún MeshInstance3D." % piece_id)
		return body

	var material := _resolve_material(piece_id)
	var is_prop := PROP_PIECES.has(piece_id)
	for mesh_instance: MeshInstance3D in meshes:
		_configure_mesh(mesh_instance, material, is_prop, piece_id)

	var bounds := _aggregate_aabb(meshes, body)
	_add_collision_shape(body, meshes, bounds, piece_id)

	body.set_meta(&"piece_id", piece_id)
	body.set_meta(&"base_size", bounds.size)
	return body


## Garantiza que la raíz sea un `StaticBody3D`. Con `nodes/root_type` ya lo es y
## se reutiliza; si no, se crea uno y se reparenta la jerarquía bajo él.
func _ensure_static_body(scene: Node) -> StaticBody3D:
	var existing := scene as StaticBody3D
	if existing != null:
		return existing

	var body := StaticBody3D.new()
	body.name = scene.name
	var source := scene as Node3D
	if source != null:
		body.transform = source.transform
	for child: Node in scene.get_children():
		scene.remove_child(child)
		body.add_child(child)
		_claim(child, body)
	scene.free()
	return body


## Devuelve todos los `MeshInstance3D` de la pieza, en orden de recorrido.
func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in _descendants(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			found.append(mesh_instance)
	return found


## Aplica a una malla los ajustes de render de `docs/10` §2.4 punto 3 y le asigna
## el material de ciudad en todas sus superficies.
func _configure_mesh(mesh_instance: MeshInstance3D, material: StandardMaterial3D,
		is_prop: bool, piece_id: StringName) -> void:
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if is_prop:
		mesh_instance.visibility_range_end = PROP_VISIBILITY_RANGE_END
		mesh_instance.visibility_range_fade_mode = \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	if material == null:
		return
	# El material se hornea en el `ArrayMesh`, no en un override del nodo: las
	# calles y veredas se dibujan con `MultiMeshInstance3D` (`docs/10` §4.4), que
	# lee el material de la malla y nunca vería un override de `MeshInstance3D`.
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null:
		mesh_instance.material_override = material
		return
	for surface: int in mesh.get_surface_count():
		mesh.surface_set_material(surface, material)
	if mesh.get_surface_count() == 0:
		push_error("import_city_piece: la malla de '%s' no tiene superficies." % piece_id)


## AABB agregado de las mallas, en el espacio local de la raíz.
func _aggregate_aabb(meshes: Array[MeshInstance3D], root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in meshes:
		var local := _relative_transform(mesh_instance, root) * mesh_instance.mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	return bounds


## Crea el `CollisionShape3D` de la pieza según la tabla de `docs/10` §2.4.
func _add_collision_shape(body: StaticBody3D, meshes: Array[MeshInstance3D],
		bounds: AABB, piece_id: StringName) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = SHAPE_NAME
	if PROP_PIECES.has(piece_id):
		shape_node.shape = _build_convex_shape(meshes, bounds, piece_id)
	else:
		var box := BoxShape3D.new()
		box.size = bounds.size
		shape_node.shape = box
		shape_node.position = bounds.get_center()
	body.add_child(shape_node)
	_claim(shape_node, body)


## Casco convexo de la primera malla con geometría utilizable. Si `create_convex_shape`
## devuelve `null` —malla degenerada o simplificación agresiva— se cae a la caja
## del AABB antes que dejar la pieza sin colisión.
func _build_convex_shape(meshes: Array[MeshInstance3D], bounds: AABB,
		piece_id: StringName) -> Shape3D:
	for mesh_instance: MeshInstance3D in meshes:
		var convex := mesh_instance.mesh.create_convex_shape(true, true)
		if convex != null and not convex.points.is_empty():
			return convex
	push_warning("import_city_piece: '%s' no produjo casco convexo; se usa BoxShape3D." % piece_id)
	var box := BoxShape3D.new()
	box.size = bounds.size
	return box


## Carga el material de la familia de la pieza. Devuelve `null` y avisa si falta,
## para que `city_import_check` lo reporte como material sin textura.
func _resolve_material(piece_id: StringName) -> StandardMaterial3D:
	var family: StringName = FAMILY_BY_PIECE.get(piece_id, &"")
	if family.is_empty():
		push_error("import_city_piece: pieza desconocida '%s'." % piece_id)
		return null
	var path: String = MATERIAL_BY_FAMILY.get(family, "")
	if not ResourceLoader.exists(path):
		push_error("import_city_piece: falta el material '%s'." % path)
		return null
	return ResourceLoader.load(path, "StandardMaterial3D") as StandardMaterial3D


## Transformada de [param node] relativa a [param root]. No usa `global_transform`
## porque durante la importación la escena no está dentro del árbol.
func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null and current != root:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found


## Asigna `owner` al nodo y a toda su descendencia, requisito para que el
## importador los empaquete en la escena resultante.
func _claim(node: Node, owner_node: Node) -> void:
	for descendant: Node in _descendants(node):
		descendant.owner = owner_node
