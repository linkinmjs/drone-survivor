## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Post-import de las piezas del pueblo de ruta (`assets/town/`, WP-A).
##
## Calcado de `import_city_piece.gd`: deja la pieza con el mismo contrato que las
## trece del pack VoxelCity, para que `CityGrid._spawn_building()` y `Building`
## no distingan una casa del pueblo de un bloque de la ciudad. Raíz
## `StaticBody3D` en la capa `city` con la misma máscara, un `MeshInstance3D`
## **hijo directo**, un `CollisionShape3D` llamado `IntactShape` también hijo
## directo, y los metadatos `piece_id` y `base_size`.
##
## Tres diferencias con el importador de ciudad, todas por el origen del modelo:
##
## 1. El GLB lo escribe `voxsplit` y trae su propio nodo raíz (`HouseARoot`), así
##    que hay que **fundirlo**: Godot añade otro por encima y, sin fundir, la
##    malla quedaría dos niveles por debajo de la raíz y `CityGrid` no la vería.
## 2. La familia de material no sale de una tabla de nombres sino del **sidecar**
##    del pack (`<pack>.pieces.json`, que emite `voxsplit town`): las casas
##    llevan el material con la máscara de ventanas y los props el opaco.
## 3. La paleta es de 256×1 y **no admite filtrado**, así que se fuerza
##    `TEXTURE_FILTER_NEAREST` igual que en `import_drone.gd` (`docs/02` §7.3).
##
## ## Cuatro packs, un importador (WP-D1)
##
## Desde WP-D1 `assets/town/` no es un pack sino cuatro, cada uno con su paleta
## de 256×1 y su material: `nuke_town` (casas y props), `foliage`, `village` y
## `city_sample`. El importador **no conoce ninguno**: busca la pieza en todos
## los `*.pieces.json` del directorio y saca de ahí su clase y la ruta de su
## material (bloque `materials` del sidecar). Agregar un pack es escribir una
## receta y un `.tres`, y no tocar este archivo.
##
## La clase `foliage` es la única que rompe el contrato de `CityGrid`: se siembra
## con `MultiMeshInstance3D`, no tiene colisión y por lo tanto **no tiene cuerpo**
## —su raíz es un `Node3D` pelado. Un `StaticBody3D` sin formas sería un cuerpo
## de física por árbol para nada.
##
## Como en los otros dos importadores, **no añade ningún script** a ningún nodo y
## el fallo es ruidoso.
@tool
extends EditorScenePostImport

## Nombre del nodo de colisión, el mismo que espera `Building.intact_shape`.
const SHAPE_NAME: StringName = &"IntactShape"

## Directorio donde viven los sidecars de todos los packs del pueblo.
const TOWN_DIR: String = "res://assets/town"

## Sufijo de los sidecars que escribe `python -m voxsplit town`: clase, medidas,
## presupuesto y material de cada pieza. Son la fuente de verdad de qué es casa,
## qué es prop y qué es follaje.
const INVENTORY_SUFFIX: String = ".pieces.json"

## Material por clase cuando el sidecar no declara su bloque `materials`. Es el
## caso de `nuke_town.pieces.json`, que se escribió antes de que el bloque
## existiera y cuyos materiales son los originales de WP-A.
const DEFAULT_MATERIALS: Dictionary[String, String] = {
	"house": "res://assets/town/materials/town_houses_windows.tres",
	"prop": "res://assets/town/materials/town_houses_opaque.tres",
}

## Distancia a la que los props se desvanecen, igual que en `import_city_piece.gd`.
const PROP_VISIBILITY_RANGE_END: float = 180.0


## Punto de entrada del importador. Devuelve la misma escena, modificada.
func _post_import(scene: Node) -> Object:
	var piece_id := StringName(get_source_file().get_file().get_basename())
	var entry := _inventory_entry(piece_id)
	var kind := String(entry.get("kind", "house"))
	if kind == "foliage":
		return _import_foliage(scene, piece_id, entry)

	var body := _ensure_static_body(scene)
	body.collision_layer = PhysicsLayers.CITY
	body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.DRONE \
			| PhysicsLayers.ENEMY_BODY | PhysicsLayers.PROJECTILE_PLAYER \
			| PhysicsLayers.PROJECTILE_ENEMY | PhysicsLayers.DEBRIS

	_flatten(body)

	var meshes := _collect_meshes(body)
	if meshes.is_empty():
		push_error("import_town_piece: '%s' no tiene ningún MeshInstance3D." % piece_id)
		return body

	var is_prop := kind == "prop"
	var material := _resolve_material(_material_path(entry, kind), piece_id)
	for mesh_instance: MeshInstance3D in meshes:
		_configure_mesh(mesh_instance, material, is_prop, piece_id)

	var bounds := _aggregate_aabb(meshes, body)
	_add_collision_shape(body, meshes, bounds, is_prop, piece_id)

	_stamp_meta(body, piece_id, kind, bounds, entry)
	return body


## Pieza de follaje: sin cuerpo, sin colisión, material opaco del pack y la malla
## como hija directa de un `Node3D`.
##
## No lleva cuerpo porque no lo usa nadie: el follaje se dibuja con
## `MultiMeshInstance3D`, que sólo mira la malla, y un árbol con el que el dron
## choca sería además un accidente de juego (un sauce no para un dron de dos
## kilos). Los metadatos son los mismos que en las otras clases, así que el
## sembrador y el check no tienen que distinguirlas para leerlos.
func _import_foliage(scene: Node, piece_id: StringName, entry: Dictionary) -> Object:
	var root := scene as Node3D
	if root == null:
		push_error("import_town_piece: la raíz de '%s' no es un Node3D." % piece_id)
		return scene
	_flatten(root)
	var meshes := _collect_meshes(root)
	if meshes.is_empty():
		push_error("import_town_piece: '%s' no tiene ningún MeshInstance3D." % piece_id)
		return root
	var material := _resolve_material(_material_path(entry, "foliage"), piece_id)
	for mesh_instance: MeshInstance3D in meshes:
		_configure_mesh(mesh_instance, material, true, piece_id)
	_stamp_meta(root, piece_id, "foliage", _aggregate_aabb(meshes, root), entry)
	return root


## Metadatos comunes a las tres clases.
func _stamp_meta(root: Node3D, piece_id: StringName, kind: String, bounds: AABB,
		entry: Dictionary) -> void:
	root.set_meta(&"piece_id", piece_id)
	root.set_meta(&"base_size", bounds.size)
	root.set_meta(&"town_kind", kind)
	root.set_meta(&"triangle_count", int(entry.get("triangles", 0)))
	root.set_meta(&"window_voxels", int(entry.get("window_voxels", 0)))


## Ruta del material de [param kind] según el sidecar, o el de la tabla por
## defecto. Un pack que declare `materials` manda; uno que no —`nuke_town`—
## cae en los dos materiales de WP-A.
func _material_path(entry: Dictionary, kind: String) -> String:
	var declared := entry.get("_materials", {}) as Dictionary
	var path := String(declared.get(kind, ""))
	if not path.is_empty():
		return path
	return String(DEFAULT_MATERIALS.get(kind, DEFAULT_MATERIALS["prop"]))


## Garantiza que la raíz sea un `StaticBody3D`. Con `nodes/root_type` ya lo es.
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


## Sube todos los `MeshInstance3D` a hijos directos de [param body], componiendo
## las transformadas de los nodos intermedios, y libera lo que quede vacío.
##
## Hace falta porque el GLB de `voxsplit` cuelga la malla de un nodo raíz propio
## (`<Pieza>Root`) y Godot añade otro por encima: sin aplanar, la jerarquía sería
## `StaticBody3D → Node3D → MeshInstance3D` y `CityGrid._spawn_building()`, que
## sólo mira los hijos directos, no encontraría la malla.
func _flatten(body: Node3D) -> void:
	for node: Node in _descendants(body):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.get_parent() == body:
			continue
		var offset := _relative_transform(mesh_instance, body)
		var parent := mesh_instance.get_parent()
		parent.remove_child(mesh_instance)
		# El `owner` viejo apunta a un nodo que puede morir en esta misma pasada:
		# se limpia antes de reparentar y se vuelve a asignar con `_claim`.
		_claim(mesh_instance, null)
		body.add_child(mesh_instance)
		mesh_instance.transform = offset
		_claim(mesh_instance, body)

	for node: Node in _descendants(body):
		if node == body or node is MeshInstance3D or node.get_child_count() > 0:
			continue
		if node.get_parent() == null:
			continue
		node.get_parent().remove_child(node)
		node.free()


## Devuelve todos los `MeshInstance3D` de la pieza, en orden de recorrido.
func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in _descendants(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			found.append(mesh_instance)
	return found


## Ajustes de render y material horneado en el `ArrayMesh`.
##
## Se hornea en la malla y no como `material_override` del nodo por la misma
## razón que en la ciudad: los props se dibujan con `MultiMeshInstance3D`, que
## lee el material de la malla y nunca vería un override. Además `Building` usa
## `material_override` para el shader de daño y `set_surface_override_material()`
## para el racionado de ventanas, así que los dos huecos tienen que quedar libres.
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
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null:
		mesh_instance.material_override = material
		return
	if mesh.get_surface_count() == 0:
		push_error("import_town_piece: la malla de '%s' no tiene superficies." % piece_id)
		return
	if mesh.get_surface_count() > 1:
		push_warning("import_town_piece: '%s' tiene %d superficies; se esperaba 1." \
				% [piece_id, mesh.get_surface_count()])
	for surface: int in mesh.get_surface_count():
		mesh.surface_set_material(surface, material)


## AABB agregado de las mallas, en el espacio local de la raíz.
func _aggregate_aabb(meshes: Array[MeshInstance3D], root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in meshes:
		var local := _relative_transform(mesh_instance, root) * mesh_instance.mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	return bounds


## Crea el `CollisionShape3D` de la pieza.
##
## Las casas llevan `BoxShape3D`, como los edificios de la ciudad, porque
## `Building.apply_variation()` reescribe `BoxShape3D.size.y` para la variación
## de altura y porque una casa **es** una caja. Los props llevan
## `ConvexPolygonShape3D`: no son cajas, y aunque WP-B los dibuje con
## `MultiMeshInstance3D` —que ignora la forma— conviene que la escena suelta
## sirva también como cuerpo, y así el check tiene una sola regla («todo nodo del
## pueblo trae un `IntactShape`»).
func _add_collision_shape(body: Node3D, meshes: Array[MeshInstance3D],
		bounds: AABB, is_prop: bool, piece_id: StringName) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = SHAPE_NAME
	if is_prop:
		shape_node.shape = _build_convex_shape(meshes, bounds, piece_id)
	else:
		var box := BoxShape3D.new()
		box.size = bounds.size
		shape_node.shape = box
		shape_node.position = bounds.get_center()
	body.add_child(shape_node)
	_claim(shape_node, body)


## Casco convexo de la primera malla con geometría utilizable; cae a la caja del
## AABB antes que dejar la pieza sin colisión.
func _build_convex_shape(meshes: Array[MeshInstance3D], bounds: AABB,
		piece_id: StringName) -> Shape3D:
	for mesh_instance: MeshInstance3D in meshes:
		var convex := mesh_instance.mesh.create_convex_shape(true, true)
		if convex != null and not convex.points.is_empty():
			return convex
	push_warning("import_town_piece: '%s' no produjo casco convexo; se usa BoxShape3D." % piece_id)
	var box := BoxShape3D.new()
	box.size = bounds.size
	return box


## Entrada de [param piece_id] en el sidecar del pack que la declare, con el
## bloque `materials` de ese pack añadido bajo `_materials`.
##
## Se recorren **todos** los `*.pieces.json` de `assets/town/` porque el pueblo
## son cuatro packs (WP-D1) y una pieza vive en uno solo. Si dos packs
## declarasen el mismo nombre serían además dos GLB con el mismo archivo, así que
## la colisión es imposible por construcción: el primero que la tenga gana y el
## caso queda avisado.
func _inventory_entry(piece_id: StringName) -> Dictionary:
	var found: Dictionary = {}
	var owner_sidecar := ""
	for path: String in _sidecar_paths():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var sidecar := parsed as Dictionary
		if sidecar == null:
			push_error("import_town_piece: '%s' no es un objeto JSON válido." % path)
			continue
		var pieces := sidecar.get("pieces", {}) as Dictionary
		if not pieces.has(String(piece_id)):
			continue
		if not owner_sidecar.is_empty():
			push_error("import_town_piece: '%s' figura en '%s' y en '%s'."
					% [piece_id, owner_sidecar, path])
			continue
		found = (pieces[String(piece_id)] as Dictionary).duplicate()
		found["_materials"] = sidecar.get("materials", {})
		owner_sidecar = path
	if owner_sidecar.is_empty():
		push_error("import_town_piece: '%s' no figura en ningún sidecar de '%s'."
				% [piece_id, TOWN_DIR])
	return found


## Los sidecars de `assets/town/`, en orden alfabético para que el resultado no
## dependa del orden en que el sistema de archivos liste el directorio.
func _sidecar_paths() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(TOWN_DIR)
	if dir == null:
		push_error("import_town_piece: no se pudo abrir '%s'." % TOWN_DIR)
		return found
	for file_name: String in dir.get_files():
		if file_name.ends_with(INVENTORY_SUFFIX):
			found.append("%s/%s" % [TOWN_DIR, file_name])
	found.sort()
	return found


## Carga un material del pueblo.
##
## **No lo modifica.** Los dos `.tres` ya traen `texture_filter = 0` (NEAREST) escrito en
## disco, y `town_import_check` lo verifica. Forzarlo acá mutaba un recurso compartido en
## caliente: cualquier otro sistema que cargara el mismo `.tres` en la misma sesión veía
## el cambio, y si el `.tres` se guardaba desde el editor el valor real del repositorio
## quedaba tapado por el parche del importador. Si el filtro estuviera mal, el sitio donde
## tiene que fallar es el check, no una mutación silenciosa.
func _resolve_material(path: String, piece_id: StringName) -> StandardMaterial3D:
	if not ResourceLoader.exists(path):
		push_error("import_town_piece: falta el material '%s' de '%s'." % [path, piece_id])
		return null
	var material := ResourceLoader.load(path, "StandardMaterial3D") as StandardMaterial3D
	if material == null:
		push_error("import_town_piece: '%s' no es un StandardMaterial3D." % path)
		return null
	if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		push_error("import_town_piece: '%s' no usa TEXTURE_FILTER_NEAREST; la paleta de "
				% path + "256×1 sangraría entre índices vecinos.")
	return material


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
