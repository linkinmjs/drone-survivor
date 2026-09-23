## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-A: verifica el import del pueblo de ruta (`assets/town/`).
##
## Mismo papel que `tools/city_import_check.gd` para el pack VoxelCity, sobre las
## 19 piezas que produce `python -m voxsplit town`: 10 casas y 9 props. Cubre que
## la geometría esté donde `CityGrid` la espera (centrada en XZ, apoyada en
## `y = 0`), que quepa en presupuesto de triángulos, que la escala real coincida
## con la declarada (puerta de 2,20 m, bloque de 4,85 × 2,50 m), que los `.import`
## lleven los valores fijados, que la jerarquía cumpla el contrato de
## `CityGrid._spawn_building()` y que los materiales muestreen la paleta de 256×1
## con filtro NEAREST y enciendan sólo los índices de ventana.
##
## La VRAM se estima leyendo los `.import` con `ConfigFile`, no preguntándole al
## `RenderingServer`: en `--headless` el controlador de render es nulo y sus
## contadores no sirven. Igual que en `city_import_check`.
##
## **Registrado en la lista headless de `tools/run_checks.*` desde WP-D**, junto
## con `town_plan_check`: con el pueblo cargando en el nivel de batalla, las 19
## piezas ya son geometría de juego y su import entra en CI. También se corre a
## mano:
##
## [codeblock]
## Godot_v4.7-stable_win64_console.exe --headless --path godot res://tools/town_import_check.tscn
## [/codeblock]
##
## No escribe en `user://` ni modifica ningún `.import`: el sub-check `restore` lo
## verifica comparando los bytes de los presets antes y después.
extends CheckRunner

## Sidecar que emite `voxsplit town`: es la fuente de verdad de qué piezas hay,
## de qué clase es cada una y cuánto mide cada pieza **de origen** del pack.
const INVENTORY_PATH: String = "res://assets/town/nuke_town.pieces.json"

## Directorios de trabajo.
const TOWN_DIR: String = "res://assets/town"
const HOUSE_SCENE_DIR: String = "res://city/pieces/town"
const PROP_SCENE_DIR: String = "res://city/pieces/town/props"

## Script de post-import que deben declarar los 19 presets.
const IMPORT_SCRIPT: String = "res://asset_import/import_town_piece.gd"

## Presupuesto de triángulos por clase.
##
## `house` no es el 1 500 del plan de WP-A: `house_b` —dos bloques angostos
## apilados, con la hiedra del pack intacta y el ático encima— mide 2 254 a 5 cm
## por vóxel, y las dos palancas medidas para bajarlo (borrar la hiedra, −648;
## diezmar el ático a 3, −448) cuestan arte del pack. Se fija en **2 400**, que
## deja la pieza más cara al 94 % y sigue atrapando una regresión. Los tipos de
## una sola planta van de 772 a 1 474. Ver `assets/town/nuke_town_report.txt`.
const HOUSE_BUDGET: int = 2400
const PROP_BUDGET: int = 300

## Nombre del nodo de colisión, el contrato con `Building.intact_shape`.
const SHAPE_NAME: StringName = &"IntactShape"

## Distancia de desvanecimiento de los props, igual que en la ciudad.
const PROP_VISIBILITY_RANGE_END: float = 180.0

## Tolerancias de `docs/10` §4.1: `CityGrid` coloca la pieza por su centro.
const CENTRE_TOLERANCE: float = 0.01
const FLOOR_TOLERANCE: float = 0.001
const SIZE_TOLERANCE: float = 0.01

## Medidas de referencia del pack, en metros (escala ×2,5 sobre el vóxel de 0,02).
const DOOR_HEIGHT: float = 2.20
const DOOR_TOLERANCE: float = 0.05
const BLOCK_WIDTH: float = 4.85
const BLOCK_HEIGHT: float = 2.50
const BLOCK_TOLERANCE: float = 0.02

## Emisión de las ventanas: el mismo 0.65 del rebalance del checkpoint 4.
const EMISSION_ENERGY: float = 0.65
const EMISSION_OPERATOR_MULTIPLY: int = 1

## Presupuesto de VRAM de las dos texturas del pueblo. Son 256×1 RGBA sin
## comprimir y sin mipmaps: 1 KB cada una. El tope está para que nadie las pase
## a 4 096² sin darse cuenta.
const VRAM_BUDGET_MB: float = 1.0

## Máscara de colisión de la capa `city`, igual que las 13 piezas de la ciudad.
const CITY_MASK: int = PhysicsLayers.WORLD | PhysicsLayers.DRONE \
		| PhysicsLayers.ENEMY_BODY | PhysicsLayers.PROJECTILE_PLAYER \
		| PhysicsLayers.PROJECTILE_ENEMY | PhysicsLayers.DEBRIS

## Valores que tienen que estar en los 19 `<pieza>.glb.import`.
const GLB_PARAMS: Dictionary[String, Variant] = {
	"nodes/root_type": "StaticBody3D",
	"nodes/apply_root_scale": true,
	"nodes/root_scale": 1.0,
	"meshes/generate_lods": true,
	# `meshes/create_shadow_meshes` va en **false** y por eso no está en esta tabla.
	# El shadow mesh es una copia deduplicada de la malla para el paso de sombras, y
	# sobre geometría vóxel no deduplica nada: cada vértice está partido por cara, así
	# que sale con el mismo número de triángulos (lo mismo que ya midió WP-13 en
	# `assets/city/README.md`). Era el doble de memoria por cero ganancia.
	"meshes/create_shadow_meshes": false,
	"animation/import": false,
	"import_script/path": IMPORT_SCRIPT,
	"materials/extract": 0,
}

## Valores que tienen que estar en los dos `<textura>.png.import`.
const PNG_PARAMS: Dictionary[String, Variant] = {
	"compress/mode": 0,
	"mipmaps/generate": false,
	"detect_3d/compress_to": 0,
}

var _inventory: Dictionary = {}
var _import_snapshot: Dictionary[String, PackedByteArray] = {}


func _run() -> void:
	_inventory = _read_inventory()
	if _inventory.is_empty():
		return
	_snapshot_imports()

	_check_inventory()
	_check_source_scale()
	_check_pieces()
	_check_import_options()
	_check_emissive_mask()
	_check_texture_vram()
	_check_negative()
	_check_restore()
	await wait_frames(1)


# --- Sub-checks ------------------------------------------------------------------------------

## 1. El sidecar declara 10 casas y 9 props, y cada una tiene su escena heredada.
func _check_inventory() -> void:
	var pieces := _pieces()
	var houses := 0
	var props := 0
	for name: String in pieces:
		var kind := String((pieces[name] as Dictionary).get("kind", ""))
		if kind == "house":
			houses += 1
		elif kind == "prop":
			props += 1
		else:
			fail("inventory: '%s' declara la clase desconocida '%s'" % [name, kind])
	print("  piezas declaradas: %d casas + %d props" % [houses, props])
	expect(houses == 10, "inventory: hay %d casas, se esperaban 10" % houses)
	expect(props == 9, "inventory: hay %d props, se esperaban 9" % props)
	expect(String(_inventory.get("palette_texture", "")) == "nuke_town_palette.png",
			"inventory: el sidecar no declara 'nuke_town_palette.png'")
	var voxel_size := float(_inventory.get("voxel_size", 0.0))
	expect_near(voxel_size, 0.05, 1e-6, "inventory: el vóxel mide %.4f m, se esperaba 0.05" % voxel_size)


## 2. Escala de las piezas **de origen**: la puerta mide 2,20 m y los dos bloques
## 4,85 × 2,50 m. Es la comprobación que ancla el factor ×2,5 del pack; en las
## casas ya compuestas no se puede aislar la puerta de la pared.
func _check_source_scale() -> void:
	var sources := _inventory.get("sources", {}) as Dictionary
	var door := sources.get("door", {}) as Dictionary
	var door_size := _floats(door.get("metres", []))
	if door_size.size() != 3:
		fail("scale: el sidecar no declara las medidas de 'door'")
	else:
		print("  puerta: %.2f × %.2f × %.2f m" % [door_size[0], door_size[1], door_size[2]])
		expect_near(door_size[1], DOOR_HEIGHT, DOOR_TOLERANCE,
				"scale: la puerta mide %.3f m de alto" % door_size[1])
	for block_id: String in ["block_square", "block_narrow"]:
		var block := sources.get(block_id, {}) as Dictionary
		var size := _floats(block.get("metres", []))
		if size.size() != 3:
			fail("scale: el sidecar no declara las medidas de '%s'" % block_id)
			continue
		print("  %s: %.2f × %.2f × %.2f m" % [block_id, size[0], size[1], size[2]])
		expect_near(size[0], BLOCK_WIDTH, BLOCK_TOLERANCE,
				"scale: '%s' mide %.3f m de ancho" % [block_id, size[0]])
		expect_near(size[1], BLOCK_HEIGHT, BLOCK_TOLERANCE,
				"scale: '%s' mide %.3f m de alto" % [block_id, size[1]])


## 3–8. Cada pieza instanciada: jerarquía, capas, forma, metadatos, geometría,
## triángulos y materiales.
func _check_pieces() -> void:
	var pieces := _pieces()
	for name: String in pieces:
		var entry := pieces[name] as Dictionary
		var path := String(entry.get("scene", ""))
		if not ResourceLoader.exists(path):
			fail("scenes: falta la escena '%s' de '%s'" % [path, name])
			continue
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			fail("scenes: '%s' no carga como PackedScene" % path)
			continue
		var root := packed.instantiate() as StaticBody3D
		if root == null:
			fail("root: la raíz de '%s' no es un StaticBody3D" % path)
			continue
		var problems := validate_piece(root, name, entry)
		for problem: String in problems:
			fail(problem)
		root.free()


## 9. Los 19 `.glb.import` y los 2 `.png.import` llevan los valores fijados.
func _check_import_options() -> void:
	for name: String in _pieces():
		var config := ConfigFile.new()
		var path := "%s/%s.glb.import" % [TOWN_DIR, name]
		if config.load(path) != OK:
			fail("import_options: no se pudo leer '%s'" % path)
			continue
		expect(String(config.get_value("remap", "importer", "")) == "scene",
				"import_options: '%s' no usa el importador 'scene'" % name)
		for key: String in GLB_PARAMS:
			_expect_param(config, name, key, GLB_PARAMS[key])
		expect(String(config.get_value("params", "nodes/root_name", "")) == _pascal(name),
				"import_options: '%s' no declara nodes/root_name = '%s'" % [name, _pascal(name)])
	for texture: String in ["nuke_town_palette", "nuke_town_emissive"]:
		var config := ConfigFile.new()
		var path := "%s/%s.png.import" % [TOWN_DIR, texture]
		if config.load(path) != OK:
			fail("import_options: no se pudo leer '%s'" % path)
			continue
		for key: String in PNG_PARAMS:
			_expect_param(config, texture, key, PNG_PARAMS[key])


## 10. La máscara emisiva es 256×1 y enciende **exactamente** los índices de
## ventana declarados: un píxel de más y se enciende media fachada.
func _check_emissive_mask() -> void:
	var image := _texture_image("nuke_town_emissive")
	if image == null:
		fail("emissive_mask: no se pudo leer nuke_town_emissive.png")
		return
	expect(image.get_width() == 256 and image.get_height() == 1,
			"emissive_mask: mide %d × %d, se esperaba 256 × 1"
			% [image.get_width(), image.get_height()])
	var declared: Dictionary = _inventory.get("window_indices", {}) as Dictionary
	# Sin esto, un sidecar sin `window_indices` y una máscara toda negra daban
	# `[] == []` y la fila pasaba con el pueblo entero a oscuras.
	expect(declared.size() >= 1,
			"emissive_mask: el sidecar no declara ningún índice de ventana; la máscara "
			+ "saldría negra y ninguna fachada se encendería")
	var lit: Array[int] = []
	for x: int in mini(image.get_width(), 256):
		var colour := image.get_pixel(x, 0)
		if colour.r > 0.0 or colour.g > 0.0 or colour.b > 0.0:
			lit.append(x + 1)
	lit.sort()
	var expected: Array[int] = []
	for key: String in declared:
		expected.append(int(key))
	expected.sort()
	print("  índices encendidos en la máscara: %s" % str(lit))
	expect(lit == expected,
			"emissive_mask: encendidos %s, declarados %s" % [str(lit), str(expected)])
	for key: String in declared:
		var index := int(key)
		if index < 1 or index > 256:
			continue
		var want := _floats(declared[key])
		var got := image.get_pixel(index - 1, 0)
		var rgb: Array[int] = [roundi(got.r8), roundi(got.g8), roundi(got.b8)]
		expect(absf(rgb[0] - want[0]) <= 1.0 and absf(rgb[1] - want[1]) <= 1.0
				and absf(rgb[2] - want[2]) <= 1.0,
				"emissive_mask: el índice %d es %s y el sidecar declara %s"
				% [index, str(rgb), str(want)])


## 11. Las dos texturas suman menos de 1 MB de VRAM, estimada desde su `.import`.
func _check_texture_vram() -> void:
	var total := 0.0
	for texture: String in ["nuke_town_palette", "nuke_town_emissive"]:
		var image := _texture_image(texture)
		if image == null:
			fail("vram: no se pudo leer %s.png" % texture)
			continue
		var config := ConfigFile.new()
		var mipmaps := false
		if config.load("%s/%s.png.import" % [TOWN_DIR, texture]) == OK:
			mipmaps = bool(config.get_value("params", "mipmaps/generate", false))
		# `compress/mode = 0` es sin comprimir: 4 bytes por píxel RGBA8.
		var bytes := float(image.get_width() * image.get_height() * 4)
		if mipmaps:
			bytes *= 4.0 / 3.0
		total += bytes
	var megabytes := total / 1048576.0
	print("  VRAM estimada de las texturas del pueblo: %.4f MB (tope %.1f MB)"
			% [megabytes, VRAM_BUDGET_MB])
	expect(megabytes < VRAM_BUDGET_MB,
			"vram: las texturas del pueblo suman %.4f MB, por encima de %.1f MB"
			% [megabytes, VRAM_BUDGET_MB])


## 12. Prueba negativa: una pieza mal formada tiene que ser **rechazada**.
##
## Se arman a mano **dos** casas rotas y se pasan por la misma
## [method validate_piece] que usan las 19 piezas reales. Hacen falta dos porque
## el primer defecto —la malla colgando de un nodo intermedio— corta la
## validación antes de llegar al material: la segunda pieza sí tiene la malla
## donde va, y falla por el filtro, por la geometría y por el presupuesto. Si la
## unión de los dos diera una lista vacía, el check estaría en verde por no mirar.
func _check_negative() -> void:
	var entry := {
		"kind": "house", "triangles": 12, "budget": HOUSE_BUDGET,
		"size": [2.0, 2.0, 2.0], "scene": "res://tools/<sintética>.tscn",
	}
	var problems: Array[String] = []

	# a) jerarquía rota: malla anidada, sin forma, sin metadatos, capa equivocada.
	var nested := StaticBody3D.new()
	nested.collision_layer = PhysicsLayers.WORLD
	nested.collision_mask = 0
	var wrapper := Node3D.new()
	wrapper.name = "Wrapper"
	nested.add_child(wrapper)
	wrapper.add_child(_bad_mesh())
	problems.append_array(validate_piece(nested, "negativa_jerarquia", entry))
	nested.free()

	# b) malla en su sitio pero con filtro lineal, sin paleta, sin emisión y
	#    desplazada: rompe material, centrado en XZ, apoyo en y = 0 y tamaño.
	var flat := StaticBody3D.new()
	flat.collision_layer = PhysicsLayers.CITY
	flat.collision_mask = CITY_MASK
	flat.set_meta(&"piece_id", "negativa_material")
	flat.set_meta(&"base_size", Vector3.ONE)
	flat.set_meta(&"town_kind", "house")
	var shape_node := CollisionShape3D.new()
	shape_node.name = SHAPE_NAME
	shape_node.shape = BoxShape3D.new()
	flat.add_child(shape_node)
	flat.add_child(_bad_mesh())
	problems.append_array(validate_piece(flat, "negativa_material", entry))
	flat.free()

	print("  prueba negativa: %d fallos detectados" % problems.size())
	expect(problems.size() >= 8,
			"negative: las piezas sintéticas sólo produjeron %d fallos; %s"
			% [problems.size(), str(problems)])
	for needle: String in ["IntactShape", "MeshInstance3D", "piece_id", "NEAREST",
			"collision_layer", "geometry"]:
		var found := false
		for problem: String in problems:
			if problem.contains(needle):
				found = true
				break
		expect(found, "negative: ningún fallo menciona '%s'; %s" % [needle, str(problems)])


## Malla deliberadamente mala para [method _check_negative]: cubo con material de
## filtro lineal, sin paleta ni emisión, desplazado fuera del centro y del suelo.
func _bad_mesh() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
	var material := StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	array_mesh.surface_set_material(0, material)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	mesh_instance.position = Vector3(3.0, 5.0, 0.0)
	return mesh_instance


## 13. Ningún `.import` cambió durante el check.
func _check_restore() -> void:
	for path: String in _import_snapshot:
		var now := _read_file(path)
		expect(now == _import_snapshot[path],
				"restore: '%s' cambió durante el check" % path)


# --- Validación de una pieza ------------------------------------------------------------------

## Comprueba una pieza ya instanciada y devuelve la lista de problemas.
##
## Devuelve en vez de llamar a [method CheckRunner.fail] para que
## [method _check_negative] pueda usar exactamente el mismo código sobre una pieza
## deliberadamente rota.
func validate_piece(root: StaticBody3D, name: String, entry: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var kind := String(entry.get("kind", "house"))
	var is_prop := kind == "prop"

	if root.collision_layer != PhysicsLayers.CITY:
		problems.append("root: '%s' tiene collision_layer %d, se esperaba %d (city)"
				% [name, root.collision_layer, PhysicsLayers.CITY])
	if root.collision_mask != CITY_MASK:
		problems.append("root: '%s' tiene collision_mask %d, se esperaba %d"
				% [name, root.collision_mask, CITY_MASK])

	# --- malla: hija **directa**, que es lo que mira `CityGrid._spawn_building()`.
	var mesh_instance: MeshInstance3D = null
	for child: Node in root.get_children():
		if child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
			break
	if mesh_instance == null:
		problems.append("mesh: '%s' no tiene ningún MeshInstance3D como hijo directo" % name)
		return _finish_validation(root, name, entry, problems, is_prop, null)
	return _finish_validation(root, name, entry, problems, is_prop, mesh_instance)


## Segunda mitad de [method validate_piece]: forma, metadatos, geometría,
## triángulos y material. Separada para que el camino sin malla no duplique nada.
func _finish_validation(root: StaticBody3D, name: String, entry: Dictionary,
		problems: Array[String], is_prop: bool,
		mesh_instance: MeshInstance3D) -> Array[String]:
	var shape_node := root.get_node_or_null(NodePath(SHAPE_NAME)) as CollisionShape3D
	if shape_node == null:
		problems.append("shape: '%s' no trae un CollisionShape3D '%s' como hijo directo"
				% [name, SHAPE_NAME])
	elif is_prop:
		if shape_node.shape is not ConvexPolygonShape3D:
			problems.append("shape: el prop '%s' usa %s, se esperaba ConvexPolygonShape3D"
					% [name, shape_node.shape.get_class() if shape_node.shape != null else "null"])
	elif shape_node.shape is not BoxShape3D:
		problems.append("shape: la casa '%s' usa %s, se esperaba BoxShape3D"
				% [name, shape_node.shape.get_class() if shape_node.shape != null else "null"])

	for key: StringName in [&"piece_id", &"base_size", &"town_kind"]:
		if not root.has_meta(key):
			problems.append("meta: '%s' no tiene el metadato '%s'" % [name, key])
	if root.has_meta(&"piece_id") and String(root.get_meta(&"piece_id")) != name:
		problems.append("meta: '%s' declara piece_id '%s'"
				% [name, String(root.get_meta(&"piece_id"))])

	if mesh_instance == null:
		return problems

	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null:
		problems.append("mesh: '%s' no tiene un ArrayMesh" % name)
		return problems
	if mesh.get_surface_count() != 1:
		problems.append("mesh: '%s' tiene %d superficies; el pueblo va con una sola"
				% [name, mesh.get_surface_count()])
	if mesh_instance.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
		problems.append("mesh: '%s' no tiene gi_mode = STATIC" % name)
	if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		problems.append("mesh: '%s' no proyecta sombra" % name)
	if is_prop and not is_equal_approx(mesh_instance.visibility_range_end,
			PROP_VISIBILITY_RANGE_END):
		problems.append("mesh: el prop '%s' se desvanece a %.1f m, se esperaba %.1f"
				% [name, mesh_instance.visibility_range_end, PROP_VISIBILITY_RANGE_END])

	# --- geometría: centrada en XZ y apoyada en y = 0 -------------------------------------
	var bounds := mesh_instance.transform * mesh.get_aabb()
	var centre := bounds.get_center()
	if absf(centre.x) > CENTRE_TOLERANCE or absf(centre.z) > CENTRE_TOLERANCE:
		problems.append("geometry: '%s' tiene el centro en (%.4f, %.4f) XZ, tolerancia %.3f"
				% [name, centre.x, centre.z, CENTRE_TOLERANCE])
	if absf(bounds.position.y) > FLOOR_TOLERANCE:
		problems.append("geometry: '%s' apoya en y = %.4f, se esperaba 0" % [name, bounds.position.y])
	var declared := _floats(entry.get("size", []))
	if declared.size() == 3:
		for axis: int in 3:
			if absf(bounds.size[axis] - declared[axis]) > SIZE_TOLERANCE:
				problems.append("geometry: '%s' mide %.3f en %s y el sidecar declara %.3f"
						% [name, bounds.size[axis], "xyz"[axis], declared[axis]])

	# --- triángulos -----------------------------------------------------------------------
	var triangles := _triangle_count(mesh)
	var budget := PROP_BUDGET if is_prop else HOUSE_BUDGET
	if triangles > budget:
		problems.append("triangles: '%s' tiene %d triángulos, presupuesto %d"
				% [name, triangles, budget])
	if triangles != int(entry.get("triangles", triangles)):
		problems.append("triangles: '%s' tiene %d y el sidecar declara %d"
				% [name, triangles, int(entry.get("triangles", -1))])

	_validate_material(mesh, name, is_prop, problems)
	return problems


## Material de la pieza: paleta con filtro NEAREST, y las casas además con la
## máscara emisiva en modo MULTIPLY.
func _validate_material(mesh: ArrayMesh, name: String, is_prop: bool,
		problems: Array[String]) -> void:
	var material := mesh.surface_get_material(0) as StandardMaterial3D
	if material == null:
		problems.append("material: '%s' no tiene un StandardMaterial3D en la superficie 0" % name)
		return
	if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		problems.append("material: '%s' no usa TEXTURE_FILTER_NEAREST (tiene %d)"
				% [name, material.texture_filter])
	if material.albedo_texture == null:
		problems.append("material: '%s' no tiene albedo_texture" % name)
	elif not material.albedo_texture.resource_path.ends_with("nuke_town_palette.png"):
		problems.append("material: '%s' no usa la paleta del pueblo, sino '%s'"
				% [name, material.albedo_texture.resource_path])
	if is_prop:
		return
	if not material.emission_enabled:
		problems.append("material: la casa '%s' no tiene emission_enabled; sin eso "
				% name + "Building._resolve_dark_material() no puede racionar sus ventanas")
		return
	if int(material.emission_operator) != EMISSION_OPERATOR_MULTIPLY:
		problems.append("material: la casa '%s' usa emission_operator %d, se esperaba %d (MULTIPLY)"
				% [name, int(material.emission_operator), EMISSION_OPERATOR_MULTIPLY])
	if not is_equal_approx(material.emission_energy_multiplier, EMISSION_ENERGY):
		problems.append("material: la casa '%s' emite a %.3f, se esperaba %.2f"
				% [name, material.emission_energy_multiplier, EMISSION_ENERGY])
	if material.emission_texture == null:
		problems.append("material: la casa '%s' no tiene emission_texture" % name)
	elif not material.emission_texture.resource_path.ends_with("nuke_town_emissive.png"):
		problems.append("material: la casa '%s' no usa la máscara del pueblo, sino '%s'"
				% [name, material.emission_texture.resource_path])


# --- Utilidades --------------------------------------------------------------------------------

## Imagen de una textura del pueblo, leída a través del recurso **importado**.
##
## No se usa `Image.load_from_file()`: esa ruta lee el PNG suelto y avisa —con
## razón— de que no funcionaría en un export. El recurso importado es además lo
## que ve el juego, que es lo que el check quiere comprobar.
func _texture_image(name: String) -> Image:
	var path := "%s/%s.png" % [TOWN_DIR, name]
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null:
		return null
	return texture.get_image()


## Triángulos de la superficie 0 de [param mesh], contando por índices.
func _triangle_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if indices.is_empty():
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			total += vertices.size() / 3
		else:
			total += indices.size() / 3
	return total


## `house_a` → `HouseA`, el `nodes/root_name` que fija el preset.
func _pascal(name: String) -> String:
	var out := ""
	for chunk: String in name.split("_", false):
		out += chunk.substr(0, 1).to_upper() + chunk.substr(1)
	return out


## Lee el sidecar del pueblo. Devuelve `{}` —y falla— si no está.
func _read_inventory() -> Dictionary:
	if not FileAccess.file_exists(INVENTORY_PATH):
		fail("inventory: no existe '%s'; corré `python -m voxsplit town`" % INVENTORY_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY_PATH))
	var sidecar := parsed as Dictionary
	if sidecar == null:
		fail("inventory: '%s' no es un objeto JSON válido" % INVENTORY_PATH)
		return {}
	# Un sidecar vacío —o sin bloque `pieces`— cortaba `_run()` antes de cualquier
	# comprobación y el check salía en **verde sin haber mirado nada**. Es el peor modo de
	# fallo posible para un check, así que es un fallo explícito.
	if sidecar.is_empty() or not sidecar.has("pieces") \
			or (sidecar.get("pieces", {}) as Dictionary).is_empty():
		fail("inventory: '%s' no declara ninguna pieza; corré `python -m voxsplit town`"
				% INVENTORY_PATH)
		return {}
	return sidecar


## `{nombre: entrada}` de las piezas del sidecar.
func _pieces() -> Dictionary:
	return _inventory.get("pieces", {}) as Dictionary


## Convierte un `Array` del JSON a flotantes tipados.
func _floats(value: Variant) -> Array[float]:
	var out: Array[float] = []
	for item: Variant in (value as Array if value is Array else []):
		out.append(float(item))
	return out


## Guarda los bytes de los 21 `.import` para el sub-check `restore`.
func _snapshot_imports() -> void:
	_import_snapshot.clear()
	for name: String in _pieces():
		var path := "%s/%s.glb.import" % [TOWN_DIR, name]
		_import_snapshot[path] = _read_file(path)
	for texture: String in ["nuke_town_palette", "nuke_town_emissive"]:
		var path := "%s/%s.png.import" % [TOWN_DIR, texture]
		_import_snapshot[path] = _read_file(path)


## Bytes de un archivo, o un buffer vacío si no se puede leer.
func _read_file(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


## Compara un parámetro del `.import` con el valor esperado.
func _expect_param(config: ConfigFile, name: String, key: String, expected: Variant) -> void:
	var value: Variant = config.get_value("params", key, null)
	if value == null:
		fail("import_options: '%s' no declara '%s'" % [name, key])
		return
	if expected is float:
		expect_near(float(value), float(expected), 0.001,
				"import_options: '%s' tiene %s = %s" % [name, key, str(value)])
		return
	expect(value == expected, "import_options: '%s' tiene %s = %s, se esperaba %s"
			% [name, key, str(value), str(expected)])
