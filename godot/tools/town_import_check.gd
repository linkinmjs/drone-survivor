## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del pueblo de ruta: verifica **todas** las piezas de `assets/town/`.
##
## Nació en WP-A para las 19 piezas del pack `nuke`. Desde WP-D1 el pueblo son
## **cuatro packs y un horneado propio**, y lo que verifica es la unión: las 36
## piezas que salen de `python -m voxsplit town` sobre cuatro recetas
## (`nuke_town`, `foliage`, `village`, `city_sample`) y las 18 que hornea
## `tools/build_town_props.gd`. La fuente de verdad de qué piezas hay es
## `assets/town/pieces_manifest.json`, que funde los cuatro sidecars con las
## procedurales; los sidecars siguen siendo la fuente de verdad de las medidas
## de origen de cada pack.
##
## Qué cubre, por fila:
##
## | Fila | Qué mide |
## |---|---|
## | `manifest` | el manifiesto y los sidecars declaran las mismas piezas, y cada clase tiene la cuenta esperada |
## | `scale` | la escala del pack `nuke`: puerta de 2,20 m, bloques de 4,85 × 2,50 m |
## | `pieces` | por pieza: jerarquía, capas, forma, metadatos, geometría, triángulos y material |
## | `import_options` | los `.glb.import` y los `.png.import` llevan los valores fijados |
## | `emissive_mask` | la máscara del pack `nuke` enciende **exactamente** los índices declarados |
## | `vram` | las paletas de 256×1 suman menos de 1 MB |
## | `negative` | dos piezas sintéticas rotas tienen que ser rechazadas |
## | `restore` | ningún `.import` cambió durante el check |
##
## La VRAM se estima leyendo los `.import` con `ConfigFile`, no preguntándole al
## `RenderingServer`: en `--headless` el controlador de render es nulo y sus
## contadores no sirven. Igual que en `city_import_check`.
##
## **Registrado en la lista headless de `tools/run_checks.*` desde WP-D.**
## También se corre a mano:
##
## [codeblock]
## Godot_v4.7-stable_win64_console.exe --headless --path godot res://tools/town_import_check.tscn
## [/codeblock]
##
## No escribe en `user://` ni modifica ningún `.import`: el sub-check `restore` lo
## verifica comparando los bytes de los presets antes y después.
extends CheckRunner

## Índice de todo el pueblo, que escribe `tools/build_town_props.gd`.
const MANIFEST_PATH: String = "res://assets/town/pieces_manifest.json"

## Directorios de trabajo.
const TOWN_DIR: String = "res://assets/town"
const PROP_MESH_DIR: String = "res://assets/city/props"

## Sufijo de los sidecars que emite `voxsplit town`, uno por pack.
const SIDECAR_SUFFIX: String = ".pieces.json"

## Script de post-import que deben declarar los presets de los GLB.
const IMPORT_SCRIPT: String = "res://asset_import/import_town_piece.gd"

## Tope de triángulos por clase, en el techo de todas las procedencias.
##
## `building` no es el 1 500 del plan: `house_b` —dos bloques angostos apilados,
## con la hiedra del pack intacta y el ático encima— mide 2 254 a 5 cm por vóxel,
## y las dos palancas medidas para bajarlo cuestan arte del pack. Las cuatro
## procedurales van entre 92 y 622, muy por debajo. `prop` es 800 por la parada
## de colectivo del pack `city` (728 diezmada ×2; sin diezmar son 1 714), y
## `foliage` es 500 porque se instancia con `MultiMesh` y el coste se multiplica.
## El número exacto de cada pieza se compara además contra el manifiesto, que es
## lo que de verdad atrapa una regresión.
const BUDGETS: Dictionary[String, int] = {
	"building": 2400, "prop": 800, "foliage": 500,
}

## Cuántas piezas tiene que haber de cada clase. Si el manifiesto crece, este
## número crece con él **a mano**: una pieza que desaparece sin que nadie lo note
## es exactamente el fallo que este check existe para ver.
const EXPECTED_COUNT: Dictionary[String, int] = {
	"building": 14, "prop": 29, "foliage": 11,
}

## Tolerancia relativa entre la huella y el alto medidos y los declarados en el
## manifiesto (plan P2c, WP-D1).
const DECLARED_TOLERANCE: float = 0.10

## Nombre del nodo de colisión, el contrato con `Building.intact_shape`.
const SHAPE_NAME: StringName = &"IntactShape"

## Distancia de desvanecimiento de los props, igual que en la ciudad.
const PROP_VISIBILITY_RANGE_END: float = 180.0

## Tolerancias de `docs/10` §4.1: `CityGrid` coloca la pieza por su centro.
const CENTRE_TOLERANCE: float = 0.01
const FLOOR_TOLERANCE: float = 0.001
const SIZE_TOLERANCE: float = 0.01

## Medidas de referencia del pack `nuke`, en metros (escala ×2,5 sobre 0,02).
const DOOR_HEIGHT: float = 2.20
const DOOR_TOLERANCE: float = 0.05
const BLOCK_WIDTH: float = 4.85
const BLOCK_HEIGHT: float = 2.50
const BLOCK_TOLERANCE: float = 0.02

## Emisión de las ventanas: el mismo 0.65 del rebalance del checkpoint 4.
const EMISSION_ENERGY: float = 0.65
const EMISSION_OPERATOR_MULTIPLY: int = 1

## Presupuesto de VRAM de las texturas del pueblo. Cuatro paletas de 256×1, una
## máscara de 256×1 y el atlas de carteles de 512×512, todas sin comprimir: 1 MB
## justo. El tope está para que nadie las pase a 4 096² sin darse cuenta.
const VRAM_BUDGET_MB: float = 2.0

## Máscara de colisión de la capa `city`, igual que las 13 piezas de la ciudad.
const CITY_MASK: int = PhysicsLayers.WORLD | PhysicsLayers.DRONE \
		| PhysicsLayers.ENEMY_BODY | PhysicsLayers.PROJECTILE_PLAYER \
		| PhysicsLayers.PROJECTILE_ENEMY | PhysicsLayers.DEBRIS

## Materiales que puede usar una pieza **procedural**: las cinco familias de
## `docs/17` §4, compartidas por las dieciocho.
const FAMILY_MATERIALS: PackedStringArray = [
	"res://assets/city/materials/town_concrete.tres",
	"res://assets/city/materials/town_sheet.tres",
	"res://assets/city/materials/town_metal.tres",
	"res://assets/city/materials/town_wood.tres",
	"res://assets/city/materials/town_signs.tres",
]

## Material por clase cuando el sidecar de un pack no declara `materials`: es el
## caso de `nuke_town`, anterior al bloque.
const DEFAULT_MATERIALS: Dictionary[String, String] = {
	"house": "res://assets/town/materials/town_houses_windows.tres",
	"prop": "res://assets/town/materials/town_houses_opaque.tres",
}

## Valores que tienen que estar en todos los `<pieza>.glb.import`.
const GLB_PARAMS: Dictionary[String, Variant] = {
	"nodes/apply_root_scale": true,
	"nodes/root_scale": 1.0,
	"meshes/generate_lods": true,
	# `meshes/create_shadow_meshes` va en **false** y por eso el valor está acá.
	# El shadow mesh es una copia deduplicada de la malla para el paso de sombras,
	# y sobre geometría vóxel no deduplica nada: cada vértice está partido por
	# cara, así que sale con el mismo número de triángulos. Era el doble de
	# memoria por cero ganancia.
	"meshes/create_shadow_meshes": false,
	"animation/import": false,
	"import_script/path": IMPORT_SCRIPT,
	"materials/extract": 0,
}

## Valores que tienen que estar en los `.png.import` de las **paletas** de 256×1
## y de la máscara emisiva: sin comprimir, sin mipmaps y sin que la detección de
## uso en 3D los recomprima a VRAM por su cuenta. Un solo píxel mal interpolado
## de una paleta de 256 entradas tiñe una fachada entera.
const PNG_PARAMS: Dictionary[String, Variant] = {
	"compress/mode": 0,
	"mipmaps/generate": false,
	"detect_3d/compress_to": 0,
}

## Y los del **atlas de carteles**, que es la excepción: 512 × 512 de texto
## pintado píxel a píxel. Sin comprimir, igual que las paletas —la compresión
## de bloques le come los bordes a una letra de cinco píxeles de alto—, pero
## **con** mipmaps, porque a cien metros un cartel sin ellos centellea.
const ATLAS_NAME: String = "signs"
const ATLAS_PARAMS: Dictionary[String, Variant] = {
	"compress/mode": 0,
	"mipmaps/generate": true,
	"detect_3d/compress_to": 0,
}

var _manifest: Dictionary = {}
var _sidecars: Dictionary = {}
var _import_snapshot: Dictionary[String, PackedByteArray] = {}


func _run() -> void:
	_manifest = _read_manifest()
	_sidecars = _read_sidecars()
	if _manifest.is_empty():
		return
	_snapshot_imports()

	_check_manifest()
	_check_source_scale()
	_check_pieces()
	_check_import_options()
	_check_emissive_mask()
	_check_texture_vram()
	_check_negative()
	_check_restore()
	await wait_frames(1)


# --- Sub-checks ------------------------------------------------------------------------------

## 1. El manifiesto y los sidecars declaran las mismas piezas y la cuenta por
## clase es la esperada.
##
## La comprobación cruzada importa más que las cuentas: una pieza que sale de un
## pack y no entra en el manifiesto es una pieza que WP-D2 no puede sembrar, y
## una del manifiesto sin pack ni `.res` es un hueco en el pueblo.
func _check_manifest() -> void:
	var tally: Dictionary[String, int] = {}
	for name: String in _manifest:
		var entry := _manifest[name] as Dictionary
		var piece_class := String(entry.get("class", ""))
		if not BUDGETS.has(piece_class):
			fail("manifest: '%s' declara la clase desconocida '%s'" % [name, piece_class])
			continue
		tally[piece_class] = int(tally.get(piece_class, 0)) + 1
	for piece_class: String in EXPECTED_COUNT:
		var found := int(tally.get(piece_class, 0))
		expect(found == int(EXPECTED_COUNT[piece_class]),
				"manifest: hay %d piezas de clase '%s', se esperaban %d"
				% [found, piece_class, int(EXPECTED_COUNT[piece_class])])
	print("  manifiesto: %d piezas (%s)" % [_manifest.size(), str(tally)])

	for sidecar_name: String in _sidecars:
		var sidecar := _sidecars[sidecar_name] as Dictionary
		var pieces := sidecar.get("pieces", {}) as Dictionary
		for name: String in pieces:
			if not _manifest.has(name):
				fail("manifest: '%s' sale del pack '%s' y no está en el manifiesto"
						% [name, sidecar_name])
				continue
			var declared := String((_manifest[name] as Dictionary).get("source", ""))
			expect(declared == sidecar_name,
					"manifest: '%s' dice venir de '%s' y sale de '%s'"
					% [name, declared, sidecar_name])
	for name: String in _manifest:
		var entry := _manifest[name] as Dictionary
		var source := String(entry.get("source", ""))
		if source == "procedural":
			expect(FileAccess.file_exists("%s/%s.res" % [PROP_MESH_DIR, name]),
					"manifest: la pieza procedural '%s' no tiene malla en '%s'"
					% [name, PROP_MESH_DIR])
			continue
		expect(_sidecars.has(source),
				"manifest: '%s' dice venir del pack '%s', que no tiene sidecar"
				% [name, source])


## 2. Escala de las piezas **de origen** del pack `nuke`: la puerta mide 2,20 m y
## los dos bloques 4,85 × 2,50 m. Es la comprobación que ancla el factor ×2,5 del
## pack; en las casas ya compuestas no se puede aislar la puerta de la pared.
func _check_source_scale() -> void:
	var sidecar := _sidecars.get("nuke_town", {}) as Dictionary
	var sources := sidecar.get("sources", {}) as Dictionary
	if sources.is_empty():
		fail("scale: el sidecar de 'nuke_town' no declara sus piezas de origen")
		return
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


## 3. Cada pieza del manifiesto, instanciada: jerarquía, capas, forma,
## metadatos, geometría, triángulos y materiales.
func _check_pieces() -> void:
	var names := PackedStringArray(_manifest.keys())
	names.sort()
	var worst_drift := 0.0
	var worst_name := ""
	for name: String in names:
		var entry := _manifest[name] as Dictionary
		var path := String(entry.get("scene", ""))
		if not ResourceLoader.exists(path):
			fail("scenes: falta la escena '%s' de '%s'" % [path, name])
			continue
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			fail("scenes: '%s' no carga como PackedScene" % path)
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			fail("root: la raíz de '%s' no es un Node3D" % path)
			continue
		for problem: String in validate_piece(root, name, entry):
			fail(problem)
		var drift := _declared_drift(root, entry)
		if drift > worst_drift:
			worst_drift = drift
			worst_name = name
		root.free()
	print("  medidas: el peor desvío contra el manifiesto es %.1f %% (%s), tope %.0f %%"
			% [worst_drift * 100.0, worst_name, DECLARED_TOLERANCE * 100.0])


## 4. Los `.glb.import` de los packs y los `.png.import` llevan los valores
## fijados. Las piezas procedurales no pasan por el importador: su preset es el
## código de `build_town_props.gd`.
func _check_import_options() -> void:
	for name: String in _manifest:
		var entry := _manifest[name] as Dictionary
		if String(entry.get("source", "")) == "procedural":
			continue
		var config := ConfigFile.new()
		var path := "%s/%s.glb.import" % [TOWN_DIR, name]
		if config.load(path) != OK:
			fail("import_options: no se pudo leer '%s'" % path)
			continue
		expect(String(config.get_value("remap", "importer", "")) == "scene",
				"import_options: '%s' no usa el importador 'scene'" % name)
		for key: String in GLB_PARAMS:
			_expect_param(config, name, key, GLB_PARAMS[key])
		# El follaje entra como `Node3D` pelado: no tiene colisión y un
		# `StaticBody3D` sin formas sería un cuerpo de física por árbol para nada.
		var want_root := "Node3D" if String(entry.get("class", "")) == "foliage" \
				else "StaticBody3D"
		expect(String(config.get_value("params", "nodes/root_type", "")) == want_root,
				"import_options: '%s' no declara nodes/root_type = '%s'" % [name, want_root])
		expect(String(config.get_value("params", "nodes/root_name", "")) == _pascal(name),
				"import_options: '%s' no declara nodes/root_name = '%s'" % [name, _pascal(name)])
	for texture: String in _texture_names():
		var config := ConfigFile.new()
		var path := "%s/%s.png.import" % [TOWN_DIR, texture]
		if config.load(path) != OK:
			fail("import_options: no se pudo leer '%s'" % path)
			continue
		var wanted := ATLAS_PARAMS if texture == ATLAS_NAME else PNG_PARAMS
		for key: String in wanted:
			_expect_param(config, texture, key, wanted[key])


## 5. Las máscaras emisivas encienden **exactamente** los índices de ventana que
## declara su sidecar: un píxel de más y se enciende media fachada.
##
## Sólo `nuke_town` tiene máscara. Los otros tres packs no tienen nada que
## encender —follaje, mobiliario de aldea y de ciudad— y escribir un PNG negro
## por pack sería una textura y un material de más por nada; el sub-check exige
## que su sidecar lo diga explícitamente en vez de dejarlo implícito.
func _check_emissive_mask() -> void:
	var masked := 0
	for sidecar_name: String in _sidecars:
		var sidecar := _sidecars[sidecar_name] as Dictionary
		var texture := String(sidecar.get("emissive_texture", ""))
		var declared := sidecar.get("window_indices", {}) as Dictionary
		if texture.is_empty():
			expect(declared.is_empty(),
					"emissive_mask: el pack '%s' declara %d índices de ventana y ninguna máscara"
					% [sidecar_name, declared.size()])
			continue
		masked += 1
		var image := _texture_image(texture.get_basename())
		if image == null:
			fail("emissive_mask: no se pudo leer %s" % texture)
			continue
		expect(image.get_width() == 256 and image.get_height() == 1,
				"emissive_mask: '%s' mide %d × %d, se esperaba 256 × 1"
				% [texture, image.get_width(), image.get_height()])
		# Sin esto, un sidecar sin `window_indices` y una máscara toda negra daban
		# `[] == []` y la fila pasaba con el pueblo entero a oscuras.
		expect(declared.size() >= 1,
				"emissive_mask: '%s' declara una máscara y ningún índice de ventana; "
				% sidecar_name + "saldría negra y ninguna fachada se encendería")
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
		print("  índices encendidos en la máscara de '%s': %s" % [sidecar_name, str(lit)])
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
	expect(masked >= 1, "emissive_mask: ningún pack trae máscara emisiva; el pueblo "
			+ "quedaría sin un solo punto de luz al anochecer")


## 6. Las texturas del pueblo suman menos del tope, estimadas desde su `.import`.
func _check_texture_vram() -> void:
	var total := 0.0
	for texture: String in _texture_names():
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
	print("  VRAM estimada de las texturas del pueblo: %.4f MB en %d texturas (tope %.1f MB)"
			% [megabytes, _texture_names().size(), VRAM_BUDGET_MB])
	expect(megabytes < VRAM_BUDGET_MB,
			"vram: las texturas del pueblo suman %.4f MB, por encima de %.1f MB"
			% [megabytes, VRAM_BUDGET_MB])


## 7. Prueba negativa: una pieza mal formada tiene que ser **rechazada**.
##
## Se arman a mano **dos** piezas rotas y se pasan por la misma
## [method validate_piece] que usan las reales. Hacen falta dos porque el primer
## defecto —la malla colgando de un nodo intermedio— corta la validación antes de
## llegar al material: la segunda pieza sí tiene la malla donde va, y falla por
## el filtro, por la geometría y por el presupuesto. Si la unión de los dos diera
## una lista vacía, el check estaría en verde por no mirar.
func _check_negative() -> void:
	var entry := {
		"class": "building", "tris": 12, "shape": "box", "origin": "base_centre",
		"source": "nuke_town", "footprint": [2.0, 2.0], "height": 2.0,
		"scene": "res://tools/<sintética>.tscn",
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
## filtro lineal sobre la paleta, sin emisión, desplazado fuera del centro y del
## suelo.
func _bad_mesh() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
	var material := StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = ResourceLoader.load(
			"%s/nuke_town_palette.png" % TOWN_DIR, "Texture2D") as Texture2D
	array_mesh.surface_set_material(0, material)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	mesh_instance.position = Vector3(3.0, 5.0, 0.0)
	return mesh_instance


## 8. Ningún `.import` cambió durante el check.
func _check_restore() -> void:
	for path: String in _import_snapshot:
		var now := _read_file(path)
		expect(now == _import_snapshot[path],
				"restore: '%s' cambió durante el check" % path)


# --- Validación de una pieza ------------------------------------------------------------------

## Comprueba una pieza ya instanciada y devuelve la lista de problemas.
##
## Devuelve en vez de llamar a [method CheckRunner.fail] para que
## [method _check_negative] pueda usar exactamente el mismo código sobre una
## pieza deliberadamente rota.
func validate_piece(root: Node3D, name: String, entry: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var piece_class := String(entry.get("class", "prop"))
	var shape := String(entry.get("shape", "box"))

	# --- raíz y capas ---------------------------------------------------------------------
	var body := root as StaticBody3D
	if piece_class == "foliage":
		if body != null:
			problems.append("root: el follaje '%s' trae un StaticBody3D; se siembra con "
					% name + "MultiMesh y no lleva colisión")
	elif body == null:
		problems.append("root: '%s' no es un StaticBody3D" % name)
	elif shape == "none":
		# Una pieza sin forma no puede quedar registrada como cuerpo: sería un
		# `StaticBody3D` vacío en el espacio de física por cada tablero de puente.
		if body.collision_layer != 0 or body.collision_mask != 0:
			problems.append("root: '%s' no tiene forma y sigue en la capa %d/%d"
					% [name, body.collision_layer, body.collision_mask])
	else:
		if body.collision_layer != PhysicsLayers.CITY:
			problems.append("root: '%s' tiene collision_layer %d, se esperaba %d (city)"
					% [name, body.collision_layer, PhysicsLayers.CITY])
		if body.collision_mask != CITY_MASK:
			problems.append("root: '%s' tiene collision_mask %d, se esperaba %d"
					% [name, body.collision_mask, CITY_MASK])

	# --- malla: hija **directa**, que es lo que mira `CityGrid._spawn_building()`.
	var mesh_instance: MeshInstance3D = null
	for child: Node in root.get_children():
		if child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
			break
	if mesh_instance == null:
		problems.append("mesh: '%s' no tiene ningún MeshInstance3D como hijo directo" % name)
	return _finish_validation(root, name, entry, problems, mesh_instance)


## Segunda mitad de [method validate_piece]: forma, metadatos, geometría,
## triángulos y material. Separada para que el camino sin malla no duplique nada.
func _finish_validation(root: Node3D, name: String, entry: Dictionary,
		problems: Array[String], mesh_instance: MeshInstance3D) -> Array[String]:
	var piece_class := String(entry.get("class", "prop"))
	var shape := String(entry.get("shape", "box"))
	var shape_node := root.get_node_or_null(NodePath(SHAPE_NAME)) as CollisionShape3D
	match shape:
		"none":
			if shape_node != null:
				problems.append("shape: '%s' declara no llevar colisión y trae un '%s'"
						% [name, SHAPE_NAME])
		"box":
			if shape_node == null:
				problems.append("shape: '%s' no trae un CollisionShape3D '%s' como hijo directo"
						% [name, SHAPE_NAME])
			elif shape_node.shape is not BoxShape3D:
				problems.append("shape: '%s' usa %s, se esperaba BoxShape3D"
						% [name, shape_node.shape.get_class() if shape_node.shape != null else "null"])
		"convex":
			if shape_node == null:
				problems.append("shape: '%s' no trae un CollisionShape3D '%s' como hijo directo"
						% [name, SHAPE_NAME])
			elif shape_node.shape is not ConvexPolygonShape3D:
				problems.append("shape: '%s' usa %s, se esperaba ConvexPolygonShape3D"
						% [name, shape_node.shape.get_class() if shape_node.shape != null else "null"])
		_:
			problems.append("shape: '%s' declara la forma desconocida '%s'" % [name, shape])

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
	if mesh.get_surface_count() < 1 or mesh.get_surface_count() > FAMILY_MATERIALS.size():
		problems.append("mesh: '%s' tiene %d superficies; el tope es una por familia de material (%d)"
				% [name, mesh.get_surface_count(), FAMILY_MATERIALS.size()])
	if mesh_instance.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
		problems.append("mesh: '%s' no tiene gi_mode = STATIC" % name)
	if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		problems.append("mesh: '%s' no proyecta sombra" % name)
	if piece_class != "building" and not is_equal_approx(
			mesh_instance.visibility_range_end, PROP_VISIBILITY_RANGE_END):
		problems.append("mesh: '%s' se desvanece a %.1f m, se esperaba %.1f"
				% [name, mesh_instance.visibility_range_end, PROP_VISIBILITY_RANGE_END])

	# --- geometría: el origen declarado y el apoyo en y = 0 --------------------------------
	var bounds := mesh_instance.transform * mesh.get_aabb()
	var centre := bounds.get_center()
	var origin := String(entry.get("origin", "base_centre"))
	match origin:
		"base_centre":
			if absf(centre.x) > CENTRE_TOLERANCE or absf(centre.z) > CENTRE_TOLERANCE:
				problems.append("geometry: '%s' tiene el centro en (%.4f, %.4f) XZ, tolerancia %.3f"
						% [name, centre.x, centre.z, CENTRE_TOLERANCE])
			if absf(bounds.position.y) > FLOOR_TOLERANCE:
				problems.append("geometry: '%s' apoya en y = %.4f, se esperaba 0"
						% [name, bounds.position.y])
		"start_x":
			if absf(bounds.position.x) > CENTRE_TOLERANCE:
				problems.append("geometry: '%s' declara origen 'start_x' y arranca en x = %.4f"
						% [name, bounds.position.x])
			if absf(centre.z) > CENTRE_TOLERANCE:
				problems.append("geometry: '%s' tiene el centro en z = %.4f, tolerancia %.3f"
						% [name, centre.z, CENTRE_TOLERANCE])
			if absf(bounds.position.y) > FLOOR_TOLERANCE:
				problems.append("geometry: '%s' apoya en y = %.4f, se esperaba 0"
						% [name, bounds.position.y])
		"deck_top_centre":
			if absf(centre.x) > CENTRE_TOLERANCE or absf(centre.z) > CENTRE_TOLERANCE:
				problems.append("geometry: '%s' tiene el centro en (%.4f, %.4f) XZ, tolerancia %.3f"
						% [name, centre.x, centre.z, CENTRE_TOLERANCE])
			if absf(bounds.end.y) > FLOOR_TOLERANCE:
				problems.append("geometry: '%s' declara la cara superior en y = 0 y la tiene en %.4f"
						% [name, bounds.end.y])
		_:
			problems.append("geometry: '%s' declara el origen desconocido '%s'" % [name, origin])

	# La huella y el alto medidos contra el manifiesto: es lo que lee WP-D2 para
	# repartir lotes, y un manifiesto que miente reparte mal.
	var declared_footprint := _floats(entry.get("footprint", []))
	var declared_height := float(entry.get("height", 0.0))
	if declared_footprint.size() == 2:
		_expect_declared(problems, name, "huella x", bounds.size.x, declared_footprint[0])
		_expect_declared(problems, name, "huella z", bounds.size.z, declared_footprint[1])
	_expect_declared(problems, name, "alto", bounds.size.y, declared_height)

	# Para las piezas de pack, además, la medida exacta del sidecar.
	var sidecar_size := _sidecar_size(name, String(entry.get("source", "")))
	if sidecar_size.size() == 3:
		for axis: int in 3:
			if absf(bounds.size[axis] - sidecar_size[axis]) > SIZE_TOLERANCE:
				problems.append("geometry: '%s' mide %.3f en %s y el sidecar declara %.3f"
						% [name, bounds.size[axis], "xyz"[axis], sidecar_size[axis]])

	# --- triángulos -----------------------------------------------------------------------
	var triangles := _triangle_count(mesh)
	var budget := int(BUDGETS.get(piece_class, BUDGETS["prop"]))
	if triangles > budget:
		problems.append("triangles: '%s' tiene %d triángulos, presupuesto %d de la clase '%s'"
				% [name, triangles, budget, piece_class])
	if triangles != int(entry.get("tris", triangles)):
		problems.append("triangles: '%s' tiene %d y el manifiesto declara %d"
				% [name, triangles, int(entry.get("tris", -1))])

	_validate_materials(mesh, name, entry, problems)
	return problems


## Compara una medida contra la declarada en el manifiesto.
func _expect_declared(problems: Array[String], name: String, what: String,
		measured: float, declared: float) -> void:
	if declared <= 0.0:
		problems.append("geometry: '%s' no declara %s en el manifiesto" % [name, what])
		return
	var drift := absf(measured - declared) / declared
	if drift > DECLARED_TOLERANCE:
		problems.append("geometry: '%s' mide %.3f m de %s y el manifiesto declara %.3f (%.1f %%)"
				% [name, measured, what, declared, drift * 100.0])


## Materiales de la pieza.
##
## Tres reglas, una por familia de problema:
##
## 1. Toda superficie usa un material **de disco** (con `resource_path`), y de la
##    lista que le toca a su procedencia. Un material incrustado en la malla es
##    un lote de dibujo más por pieza.
## 2. Todo material que muestree una paleta de 256×1 va con filtro NEAREST: con
##    cualquier otro, el muestreo sangra al índice vecino y una pared beige se
##    tinta del verde de la ventana de al lado (`docs/02` §7.3).
## 3. Las casas del pack `nuke` llevan además la máscara de ventanas en modo
##    MULTIPLY, que es lo que `Building._resolve_dark_material()` raciona.
func _validate_materials(mesh: ArrayMesh, name: String, entry: Dictionary,
		problems: Array[String]) -> void:
	var allowed := _allowed_materials(entry)
	for surface: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null:
			problems.append("material: la superficie %d de '%s' no tiene un StandardMaterial3D"
					% [surface, name])
			continue
		if material.resource_path.is_empty():
			problems.append("material: la superficie %d de '%s' lleva un material incrustado"
					% [surface, name])
		elif not allowed.has(material.resource_path):
			problems.append("material: '%s' usa '%s', que no está entre %s"
					% [name, material.resource_path, str(allowed)])
		var albedo := material.albedo_texture
		if albedo != null and albedo.resource_path.ends_with("_palette.png") \
				and material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
			problems.append("material: '%s' muestrea una paleta de 256×1 sin TEXTURE_FILTER_NEAREST (tiene %d)"
					% [name, material.texture_filter])

	if String(entry.get("source", "")) != "nuke_town" \
			or String(entry.get("class", "")) != "building":
		return
	var facade := mesh.surface_get_material(0) as StandardMaterial3D
	if facade == null:
		return
	if not facade.emission_enabled:
		problems.append("material: la casa '%s' no tiene emission_enabled; sin eso "
				% name + "Building._resolve_dark_material() no puede racionar sus ventanas")
		return
	if int(facade.emission_operator) != EMISSION_OPERATOR_MULTIPLY:
		problems.append("material: la casa '%s' usa emission_operator %d, se esperaba %d (MULTIPLY)"
				% [name, int(facade.emission_operator), EMISSION_OPERATOR_MULTIPLY])
	if not is_equal_approx(facade.emission_energy_multiplier, EMISSION_ENERGY):
		problems.append("material: la casa '%s' emite a %.3f, se esperaba %.2f"
				% [name, facade.emission_energy_multiplier, EMISSION_ENERGY])
	if facade.emission_texture == null:
		problems.append("material: la casa '%s' no tiene emission_texture" % name)
	elif not facade.emission_texture.resource_path.ends_with("nuke_town_emissive.png"):
		problems.append("material: la casa '%s' no usa la máscara del pueblo, sino '%s'"
				% [name, facade.emission_texture.resource_path])


## Qué materiales puede usar una pieza según su procedencia.
func _allowed_materials(entry: Dictionary) -> PackedStringArray:
	var source := String(entry.get("source", ""))
	if source == "procedural":
		return FAMILY_MATERIALS
	var sidecar := _sidecars.get(source, {}) as Dictionary
	var declared := sidecar.get("materials", {}) as Dictionary
	var out := PackedStringArray()
	for key: String in declared:
		out.append(String(declared[key]))
	if out.is_empty():
		for key: String in DEFAULT_MATERIALS:
			out.append(String(DEFAULT_MATERIALS[key]))
	return out


# --- Utilidades --------------------------------------------------------------------------------

## Cuánto se aparta del manifiesto la medida más desviada de una pieza ya
## instanciada, como fracción. Es sólo para el informe.
func _declared_drift(root: Node3D, entry: Dictionary) -> float:
	for child: Node in root.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.transform * mesh_instance.mesh.get_aabb()
		var footprint := _floats(entry.get("footprint", []))
		var height := float(entry.get("height", 0.0))
		var worst := 0.0
		if footprint.size() == 2 and footprint[0] > 0.0 and footprint[1] > 0.0:
			worst = maxf(worst, absf(bounds.size.x - footprint[0]) / footprint[0])
			worst = maxf(worst, absf(bounds.size.z - footprint[1]) / footprint[1])
		if height > 0.0:
			worst = maxf(worst, absf(bounds.size.y - height) / height)
		return worst
	return 0.0


## Medidas que el sidecar de su pack declara para [param name], o `[]`.
func _sidecar_size(name: String, source: String) -> Array[float]:
	var sidecar := _sidecars.get(source, {}) as Dictionary
	var pieces := sidecar.get("pieces", {}) as Dictionary
	if not pieces.has(name):
		return []
	return _floats((pieces[name] as Dictionary).get("size", []))


## Nombres (sin extensión) de todas las texturas de `assets/town/`.
func _texture_names() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(TOWN_DIR)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if file_name.ends_with(".png"):
			found.append(file_name.get_basename())
	found.sort()
	return found


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


## Triángulos de todas las superficies de [param mesh], contando por índices.
func _triangle_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_INDEX] == null:
			var loose := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			total += loose.size() / 3
			continue
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


## Lee el manifiesto. Devuelve `{}` —y falla— si no está o está vacío.
func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		fail("manifest: no existe '%s'; corré `build_town_props.gd`" % MANIFEST_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var document := parsed as Dictionary
	if document == null:
		fail("manifest: '%s' no es un objeto JSON válido" % MANIFEST_PATH)
		return {}
	var pieces := document.get("pieces", {}) as Dictionary
	# Un manifiesto vacío cortaba `_run()` antes de cualquier comprobación y el
	# check salía en **verde sin haber mirado nada**. Es el peor modo de fallo
	# posible para un check, así que es un fallo explícito.
	if pieces.is_empty():
		fail("manifest: '%s' no declara ninguna pieza" % MANIFEST_PATH)
		return {}
	return pieces


## Los sidecars de los packs, indexados por su nombre (`nuke_town`, `foliage`…).
func _read_sidecars() -> Dictionary:
	var found: Dictionary = {}
	var dir := DirAccess.open(TOWN_DIR)
	if dir == null:
		fail("inventory: no se pudo abrir '%s'" % TOWN_DIR)
		return found
	var names := PackedStringArray(dir.get_files())
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(SIDECAR_SUFFIX):
			continue
		var path := "%s/%s" % [TOWN_DIR, file_name]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var sidecar := parsed as Dictionary
		if sidecar == null:
			fail("inventory: '%s' no es un objeto JSON válido" % path)
			continue
		found[String(sidecar.get("name", file_name.get_basename()))] = sidecar
	expect(found.size() >= 4, "inventory: se encontraron %d sidecars en '%s', se esperaban 4"
			% [found.size(), TOWN_DIR])
	print("  packs: %s" % str(PackedStringArray(found.keys())))
	return found


## Convierte un `Array` del JSON a flotantes tipados.
func _floats(value: Variant) -> Array[float]:
	var out: Array[float] = []
	for item: Variant in (value as Array if value is Array else []):
		out.append(float(item))
	return out


## Guarda los bytes de todos los `.import` que el check lee.
func _snapshot_imports() -> void:
	_import_snapshot.clear()
	for name: String in _manifest:
		if String((_manifest[name] as Dictionary).get("source", "")) == "procedural":
			continue
		var path := "%s/%s.glb.import" % [TOWN_DIR, name]
		_import_snapshot[path] = _read_file(path)
	for texture: String in _texture_names():
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
