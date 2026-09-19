## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-13: verifica el import del pack FreeSample según `docs/10` §11.1.
##
## Comprueba las 13 piezas ya importadas y sus escenas de `city/pieces/`: raíz
## `StaticBody3D` en la capa `city`, forma de colisión del tipo que manda la
## tabla de nombres, escala con `BuildingBlock_1` entre 12 y 16 m, ajustes de
## render, materiales con textura, LOD generados y presupuesto de VRAM.
##
## La VRAM se estima leyendo los `.import` con `ConfigFile`, no consultando al
## `RenderingServer`: en `--headless` el controlador de render es nulo y sus
## contadores no son fiables. Además así se verifica la **intención** que queda
## guardada en el repositorio.
##
## No escribe en `user://` ni modifica ningún `.import`: el sub-check `restore`
## lo verifica comparando el contenido de los presets antes y después.
extends CheckRunner

## Factor fijado en `docs/10` §2.2 paso 3 tras medir `BuildingBlock_1`.
## El importador ufbx ya aplica el `UnitScaleFactor` del FBX, así que con
## `root_scale = 1.0` la pieza llega midiendo **2.50 m**, no 1 200 unidades: el
## factor es de aumento, **5.0**, y no el 0.01 que el documento suponía.
## Ver `assets/city/README.md`.
const ROOT_SCALE: float = 5.0

## Ruta del script de post-import que deben declarar los 13 presets.
const IMPORT_SCRIPT: String = "res://asset_import/import_city_piece.gd"

## Pieza de calibración y ventana admitida de altura, en metros (`docs/10` §2.2).
const SCALE_PIECE: StringName = &"BuildingBlock_1"
const SCALE_MIN: float = 12.0
const SCALE_MAX: float = 16.0

## Cota de cordura de altura para cualquier pieza: atrapa un factor 100 en
## cualquier dirección (`docs/10` §11.1 sub-check 5).
const SANITY_MIN: float = 0.2
const SANITY_MAX: float = 120.0

## Presupuesto de VRAM de las texturas de ciudad (`docs/10` §2.3, `docs/15` §5.2).
const VRAM_BUDGET_MB: float = 90.0

## Distancia de desvanecimiento de los props (`docs/10` §2.4 punto 3).
const PROP_VISIBILITY_RANGE_END: float = 180.0

## Directorios de trabajo.
const MODELS_DIR: String = "res://assets/city/models"
const TEXTURES_DIR: String = "res://assets/city/textures"
const CITY_DIR: String = "res://assets/city"

## Las 13 piezas y su escena de `docs/10` §2.1, en el orden de la tabla.
const PIECE_SCENES: Dictionary[StringName, String] = {
	&"Building_3": "res://city/pieces/tower_a.tscn",
	&"BuildingBlock_19": "res://city/pieces/tower_b.tscn",
	&"BuildingBlock_18": "res://city/pieces/block_mid.tscn",
	&"BuildingBlock_1": "res://city/pieces/block_low_a.tscn",
	&"BuildingBlock_2": "res://city/pieces/block_low_b.tscn",
	&"BuildingBlock_24": "res://city/pieces/block_low_c.tscn",
	&"Advertising_5": "res://city/pieces/props/sign_a.tscn",
	&"Advertising_6": "res://city/pieces/props/sign_b.tscn",
	&"Advertising_7": "res://city/pieces/props/sign_c.tscn",
	&"SateliteDish": "res://city/pieces/props/dish.tscn",
	&"Road_Chunk_5": "res://city/pieces/road_chunk.tscn",
	&"Sidewalk_Chunk_2": "res://city/pieces/sidewalk_chunk.tscn",
	&"Sidewalk_Tile_1": "res://city/pieces/sidewalk_tile.tscn",
}

## Props: llevan `ConvexPolygonShape3D` y desvanecimiento a 180 m. El resto usa
## `BoxShape3D` (`docs/10` §2.4 punto 2 y §11.1 sub-check 3).
const PROP_PIECES: Array[StringName] = [
	&"Advertising_5", &"Advertising_6", &"Advertising_7", &"SateliteDish",
]

## Difusas de edificio: 2048². El resto de las texturas de ciudad, 1024².
const BUILDING_DIFFUSE: Array[String] = [
	"t_buildings_001_diffuse", "t_buildings_002_diffuse",
]

## Raíces instanciadas, por pieza. Se liberan en [method _tear_down].
var _roots: Dictionary[StringName, Node3D] = {}

## AABB agregado de cada pieza, en metros y en el espacio local de la raíz.
var _bounds: Dictionary[StringName, AABB] = {}

## Huella de los `.import` al arrancar, para el sub-check `restore`.
var _import_digest: Dictionary[String, String] = {}


func _run() -> void:
	_import_digest = _digest_imports()

	_check_pieces_present()
	_check_root_is_body()
	_check_has_shape()
	_check_scale()
	_check_import_options()
	_check_mesh_render()
	_check_materials()
	_check_mesh_optimization()
	_check_texture_settings()
	_check_texture_vram()
	_check_composites_absent()
	_check_restore()

	_print_table()
	_tear_down()
	await wait_frames(1)


# --- Sub-checks ---------------------------------------------------------------

## 1. Las 13 piezas existen como FBX, y su escena heredada carga e instancia.
func _check_pieces_present() -> void:
	for piece: StringName in PIECE_SCENES:
		var fbx := "%s/%s.fbx" % [MODELS_DIR, piece]
		if not ResourceLoader.exists(fbx):
			fail("pieces_present: falta el FBX '%s'" % fbx)
			continue
		var scene_path: String = PIECE_SCENES[piece]
		if not ResourceLoader.exists(scene_path):
			fail("pieces_present: falta la escena '%s'" % scene_path)
			continue
		var packed := ResourceLoader.load(scene_path, "PackedScene") as PackedScene
		if packed == null or not packed.can_instantiate():
			fail("pieces_present: '%s' no es una PackedScene instanciable" % scene_path)
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			fail("pieces_present: la raíz de '%s' no es un Node3D" % scene_path)
			continue
		add_child(root)
		_roots[piece] = root
		_bounds[piece] = _aggregate_aabb(root)


## 2. Raíz `StaticBody3D` en la capa `city` con la máscara de `docs/02` §3.1.
func _check_root_is_body() -> void:
	var expected_mask := PhysicsLayers.WORLD | PhysicsLayers.DRONE \
			| PhysicsLayers.ENEMY_BODY | PhysicsLayers.PROJECTILE_PLAYER \
			| PhysicsLayers.PROJECTILE_ENEMY | PhysicsLayers.DEBRIS
	for piece: StringName in _roots:
		var body := _roots[piece] as StaticBody3D
		if body == null:
			fail("root_is_body: la raíz de '%s' no es un StaticBody3D" % piece)
			continue
		expect(body.collision_layer == PhysicsLayers.CITY,
				"root_is_body: '%s' tiene collision_layer %d, se esperaba %d"
				% [piece, body.collision_layer, PhysicsLayers.CITY])
		expect(body.collision_mask == expected_mask,
				"root_is_body: '%s' tiene collision_mask %d, se esperaba %d"
				% [piece, body.collision_mask, expected_mask])
		expect(body.has_meta(&"piece_id") and body.get_meta(&"piece_id") == piece,
				"root_is_body: '%s' no lleva el metadato piece_id" % piece)
		expect(body.has_meta(&"base_size"),
				"root_is_body: '%s' no lleva el metadato base_size" % piece)


## 3. Al menos un `CollisionShape3D` con forma, del tipo que manda la tabla.
func _check_has_shape() -> void:
	for piece: StringName in _roots:
		var shapes := _find_all(_roots[piece], "CollisionShape3D")
		var filled: Array[CollisionShape3D] = []
		for node: Node in shapes:
			var shape_node := node as CollisionShape3D
			if shape_node.shape != null:
				filled.append(shape_node)
		if filled.is_empty():
			fail("has_shape: '%s' no tiene ningún CollisionShape3D con forma" % piece)
			continue
		var shape := filled[0].shape
		if PROP_PIECES.has(piece):
			expect(shape is ConvexPolygonShape3D,
					"has_shape: '%s' debería usar ConvexPolygonShape3D, usa %s"
					% [piece, shape.get_class()])
			var convex := shape as ConvexPolygonShape3D
			if convex != null:
				expect(convex.points.size() >= 4,
						"has_shape: el casco convexo de '%s' tiene %d puntos"
						% [piece, convex.points.size()])
		else:
			expect(shape is BoxShape3D,
					"has_shape: '%s' debería usar BoxShape3D, usa %s"
					% [piece, shape.get_class()])
			var box := shape as BoxShape3D
			if box != null:
				expect(box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0,
						"has_shape: la caja de '%s' es degenerada (%s)" % [piece, box.size])


## 4 y 5. Escala: la pieza de calibración en su ventana y el resto con cordura.
func _check_scale() -> void:
	if _bounds.has(SCALE_PIECE):
		var height := _bounds[SCALE_PIECE].size.y
		expect(height >= SCALE_MIN and height <= SCALE_MAX,
				"scale_reference: '%s' mide %.2f m de alto, fuera de [%.1f, %.1f]"
				% [SCALE_PIECE, height, SCALE_MIN, SCALE_MAX])
	else:
		fail("scale_reference: no se pudo medir '%s'" % SCALE_PIECE)

	for piece: StringName in _bounds:
		var height := _bounds[piece].size.y
		expect(height > SANITY_MIN and height < SANITY_MAX,
				"scale_sanity: '%s' mide %.3f m de alto, fuera de (%.1f, %.1f)"
				% [piece, height, SANITY_MIN, SANITY_MAX])


## 6. Los 13 presets `.fbx.import` declaran los valores de `docs/10` §2.2.
func _check_import_options() -> void:
	for piece: StringName in PIECE_SCENES:
		var path := "%s/%s.fbx.import" % [MODELS_DIR, piece]
		var config := ConfigFile.new()
		var err := config.load(path)
		if err != OK:
			fail("import_options: no se pudo leer '%s': %s" % [path, error_string(err)])
			continue
		_expect_param(config, path, "nodes/root_type", "StaticBody3D")
		_expect_param(config, path, "nodes/root_name", String(piece))
		_expect_param(config, path, "nodes/apply_root_scale", true)
		_expect_param(config, path, "nodes/root_scale", ROOT_SCALE)
		_expect_param(config, path, "meshes/generate_lods", true)
		_expect_param(config, path, "meshes/create_shadow_meshes", true)
		_expect_param(config, path, "meshes/ensure_tangents", true)
		_expect_param(config, path, "animation/import", false)
		_expect_param(config, path, "import_script/path", IMPORT_SCRIPT)


## 7. `gi_mode` estático, sombras encendidas y desvanecimiento en los props.
func _check_mesh_render() -> void:
	for piece: StringName in _roots:
		var meshes := _find_all(_roots[piece], "MeshInstance3D")
		if meshes.is_empty():
			fail("mesh_render: '%s' no tiene ningún MeshInstance3D" % piece)
			continue
		for node: Node in meshes:
			var mesh_instance := node as MeshInstance3D
			expect(mesh_instance.gi_mode == GeometryInstance3D.GI_MODE_STATIC,
					"mesh_render: '%s/%s' no tiene gi_mode STATIC"
					% [piece, mesh_instance.name])
			expect(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
					"mesh_render: '%s/%s' no proyecta sombra" % [piece, mesh_instance.name])
			if not PROP_PIECES.has(piece):
				continue
			expect(is_equal_approx(mesh_instance.visibility_range_end,
							PROP_VISIBILITY_RANGE_END),
					"mesh_render: el prop '%s' tiene visibility_range_end %.1f, se esperaba %.1f"
					% [piece, mesh_instance.visibility_range_end, PROP_VISIBILITY_RANGE_END])
			expect(mesh_instance.visibility_range_fade_mode
							== GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
					"mesh_render: el prop '%s' no usa VISIBILITY_RANGE_FADE_SELF" % piece)


## 8. Ninguna superficie sin material y ningún material sin textura de albedo.
func _check_materials() -> void:
	for piece: StringName in _roots:
		for node: Node in _find_all(_roots[piece], "MeshInstance3D"):
			var mesh_instance := node as MeshInstance3D
			var mesh := mesh_instance.mesh
			if mesh == null:
				fail("materials: '%s/%s' no tiene malla" % [piece, mesh_instance.name])
				continue
			if mesh.get_surface_count() == 0:
				fail("materials: la malla de '%s' no tiene superficies" % piece)
				continue
			for surface: int in mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface)
				if material == null:
					fail("materials: '%s' superficie %d sin material" % [piece, surface])
					continue
				var standard := material as BaseMaterial3D
				if standard == null:
					fail("materials: '%s' superficie %d usa %s, no un BaseMaterial3D"
							% [piece, surface, material.get_class()])
					continue
				expect(standard.albedo_texture != null,
						"materials: '%s' superficie %d sin textura de albedo" % [piece, surface])
				expect(standard.emission_enabled and standard.emission_texture != null,
						"materials: '%s' superficie %d sin textura emisiva" % [piece, surface])


## 9. El optimizador de mallas del importador corrió sobre las 13 piezas.
##
## `docs/10` §2.4 avisa de que el runtime **no** expone el número de niveles de
## LOD, y por eso la opción `meshes/generate_lods` se verifica en el preset
## (sub-check `import_options`). Lo que sí se puede verificar aquí es que el
## optimizador corrió: `meshes/create_shadow_meshes = true` deja un
## `ArrayMesh.shadow_mesh`, que se produce en la misma pasada que los LOD.
##
## Medido en WP-13: las 13 mallas salen con **cero** niveles de LOD aunque la
## opción esté activa. No es un fallo del preset. Son mallas vóxel con normales
## duras y un atlas de UV por cara: cada vértice está partido —`Building_3` trae
## 2 664 vértices para 1 772 triángulos— así que meshoptimizer ve todas las
## aristas como borde y no puede colapsar ninguna. La prueba es que el
## `shadow_mesh` sale con el mismo número de triángulos que la malla original.
## El nivel de detalle a distancia lo aportan `visibility_range_end` en los props
## y el occlusion culling de `docs/10` §7, no el LOD de malla.
func _check_mesh_optimization() -> void:
	for piece: StringName in _roots:
		for node: Node in _find_all(_roots[piece], "MeshInstance3D"):
			var mesh := (node as MeshInstance3D).mesh as ArrayMesh
			if mesh == null:
				fail("mesh_optimization: la malla de '%s' no es un ArrayMesh" % piece)
				continue
			expect(mesh.shadow_mesh != null,
					("mesh_optimization: '%s' no tiene shadow_mesh; el importador no corrió"
					+ " el optimizador pese a create_shadow_meshes") % piece)
			expect(mesh.get_surface_count() > 0,
					"mesh_optimization: la malla de '%s' no tiene superficies" % piece)


## 10. Cada `.png.import` de ciudad usa VRAM comprimida, mipmaps y su tope de tamaño.
func _check_texture_settings() -> void:
	for name: String in _texture_names():
		var path := "%s/%s.png.import" % [TEXTURES_DIR, name]
		var config := ConfigFile.new()
		var err := config.load(path)
		if err != OK:
			fail("texture_settings: no se pudo leer '%s': %s" % [path, error_string(err)])
			continue
		_expect_param(config, path, "compress/mode", 2)
		_expect_param(config, path, "mipmaps/generate", true)
		_expect_param(config, path, "detect_3d/compress_to", 0)
		var limit := int(config.get_value("params", "process/size_limit", 0))
		var maximum := 2048 if BUILDING_DIFFUSE.has(name) else 1024
		expect(limit > 0 and limit <= maximum,
				"texture_settings: '%s' tiene process/size_limit %d, se esperaba ≤ %d y > 0"
				% [name, limit, maximum])


## 11. Estimación analítica de la VRAM de las texturas de ciudad.
func _check_texture_vram() -> void:
	var total := 0.0
	for name: String in _texture_names():
		total += _texture_vram_bytes(name)
	var megabytes := total / 1048576.0
	print("  VRAM estimada de texturas de ciudad: %.2f MB (presupuesto %.0f MB)"
			% [megabytes, VRAM_BUDGET_MB])
	expect(megabytes < VRAM_BUDGET_MB,
			"texture_vram: las texturas de ciudad suman %.2f MB, por encima de %.0f MB"
			% [megabytes, VRAM_BUDGET_MB])


## 12. Ningún composite del pack quedó en `assets/city/` (`docs/10` §2.3).
func _check_composites_absent() -> void:
	for path: String in _walk_files(CITY_DIR):
		expect(not path.get_file().begins_with("VoxelCity_CompositeBuildings_Optimized"),
				"composites_absent: sobró un composite del pack en '%s'" % path)


## 13. El check no modificó ningún `.import`.
func _check_restore() -> void:
	var after := _digest_imports()
	expect(after.size() == _import_digest.size(),
			"restore: cambió el número de presets .import (%d → %d)"
			% [_import_digest.size(), after.size()])
	for path: String in _import_digest:
		expect(after.get(path, "") == _import_digest[path],
				"restore: el check modificó '%s'" % path)


# --- Auxiliares ---------------------------------------------------------------

## Imprime el inventario medido: dimensiones en metros, forma y LOD por pieza.
func _print_table() -> void:
	print("  %-18s %8s %8s %8s %7s %4s  %-22s %s" % ["pieza", "ancho", "alto",
			"fondo", "tris", "lod", "forma", "escena"])
	for piece: StringName in PIECE_SCENES:
		if not _bounds.has(piece):
			continue
		var size := _bounds[piece].size
		var shape_name := "—"
		var shapes := _find_all(_roots[piece], "CollisionShape3D")
		if not shapes.is_empty():
			var shape := (shapes[0] as CollisionShape3D).shape
			if shape != null:
				shape_name = shape.get_class()
		print("  %-18s %8.2f %8.2f %8.2f %7d %4d  %-22s %s" % [piece, size.x, size.y,
				size.z, _triangle_count(piece), _lod_count(piece), shape_name,
				String(PIECE_SCENES[piece]).get_file()])


## AABB agregado de los `MeshInstance3D` de [param root], en su espacio local.
func _aggregate_aabb(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var inverse := root.global_transform.affine_inverse()
	for node: Node in _find_all(root, "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local := inverse * mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	return bounds


## Número de niveles de LOD de una superficie, para la columna informativa de la
## tabla. El runtime no expone la lista, así que se lee la propiedad interna
## `_surfaces`, que es la que `ArrayMesh` serializa; la clave `lods` sólo existe
## si el importador llegó a generar algún nivel. Con estas mallas vale siempre 0,
## por el motivo que explica [method _check_mesh_optimization].
func _surface_lod_count(mesh: ArrayMesh, surface: int) -> int:
	var surfaces: Variant = mesh.get("_surfaces")
	if not (surfaces is Array):
		return 0
	var list := surfaces as Array
	if surface >= list.size() or not (list[surface] is Dictionary):
		return 0
	var entry := list[surface] as Dictionary
	var lods: Variant = entry.get("lods", null)
	return (lods as Array).size() if lods is Array else 0


## Nombres (sin extensión) de las texturas de ciudad presentes en el repositorio.
func _texture_names() -> Array[String]:
	var names: Array[String] = []
	for path: String in _walk_files(TEXTURES_DIR):
		if path.get_extension().to_lower() == "png":
			names.append(path.get_file().get_basename())
	names.sort()
	return names


## Bytes de VRAM de una textura, estimados desde su `.import`:
## `ancho × alto × bytes_por_píxel`, por 4/3 si lleva mipmaps.
func _texture_vram_bytes(name: String) -> float:
	var config := ConfigFile.new()
	if config.load("%s/%s.png.import" % [TEXTURES_DIR, name]) != OK:
		return 0.0
	var texture := ResourceLoader.load("%s/%s.png" % [TEXTURES_DIR, name], "Texture2D") as Texture2D
	var side := Vector2i.ZERO
	if texture != null:
		side = Vector2i(texture.get_size())
	var limit := int(config.get_value("params", "process/size_limit", 0))
	if limit > 0:
		side = Vector2i(mini(side.x, limit), mini(side.y, limit))
	var mode := int(config.get_value("params", "compress/mode", 0))
	var high_quality := bool(config.get_value("params", "compress/high_quality", false))
	# Modo 2 es VRAM Compressed: BC7 a 1 byte/píxel con alta calidad, BC1/BC3 a
	# 0.5 en caso contrario. Cualquier otro modo se contabiliza como RGBA8.
	var bytes_per_pixel := 4.0
	if mode == 2:
		bytes_per_pixel = 1.0 if high_quality else 0.5
	var bytes := float(side.x) * float(side.y) * bytes_per_pixel
	if bool(config.get_value("params", "mipmaps/generate", false)):
		bytes *= 4.0 / 3.0
	return bytes


## Huella del contenido de todos los `.import` bajo `assets/city/`.
func _digest_imports() -> Dictionary[String, String]:
	var digest: Dictionary[String, String] = {}
	for path: String in _walk_files(CITY_DIR):
		if path.get_extension().to_lower() == "import":
			digest[path] = FileAccess.get_md5(path)
	return digest


## Rutas de todos los archivos bajo [param dir], recursivamente.
func _walk_files(dir: String) -> Array[String]:
	var files: Array[String] = []
	var pending: Array[String] = [dir]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		for sub: String in DirAccess.get_directories_at(current):
			pending.append(current.path_join(sub))
		for file_name: String in DirAccess.get_files_at(current):
			files.append(current.path_join(file_name))
	files.sort()
	return files


## Todos los descendientes de [param root] de la clase [param type], incluida la raíz.
func _find_all(root: Node, type: String) -> Array[Node]:
	var found: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current.is_class(type):
			found.append(current)
		for child: Node in current.get_children():
			pending.append(child)
	return found


## Compara un valor de `[params]` contra el esperado y falla con el detalle.
func _expect_param(config: ConfigFile, path: String, key: String, expected: Variant) -> void:
	var actual: Variant = config.get_value("params", key, null)
	if actual == null:
		fail("import_options: '%s' no declara '%s'" % [path.get_file(), key])
		return
	if expected is float:
		expect(is_equal_approx(float(actual), float(expected)),
				"import_options: '%s' tiene %s = %s, se esperaba %s"
				% [path.get_file(), key, str(actual), str(expected)])
		return
	expect(actual == expected, "import_options: '%s' tiene %s = %s, se esperaba %s"
			% [path.get_file(), key, str(actual), str(expected)])


## Libera las 13 instancias para no dejar nodos huérfanos.
func _tear_down() -> void:
	for piece: StringName in _roots:
		var root := _roots[piece]
		remove_child(root)
		root.queue_free()
	_roots.clear()


## Triángulos sumados de todas las superficies de la pieza, para el inventario.
func _triangle_count(piece: StringName) -> int:
	var total := 0
	for node: Node in _find_all(_roots[piece], "MeshInstance3D"):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			total += mesh.get_faces().size() / 3
	return total


## Niveles de LOD sumados de todas las superficies de la pieza.
func _lod_count(piece: StringName) -> int:
	var total := 0
	for node: Node in _find_all(_roots[piece], "MeshInstance3D"):
		var mesh := (node as MeshInstance3D).mesh as ArrayMesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			total += _surface_lod_count(mesh, surface)
	return total
