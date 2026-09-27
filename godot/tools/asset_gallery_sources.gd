## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Inventario de la galería de assets (plan P2e): **qué** entra en
## `tools/asset_gallery.tscn`, en qué fila, con qué etiqueta y qué huella ocupa.
##
## Lo usan los dos lados del contrato —`tools/build_asset_gallery.gd`, que
## hornea la escena, y `tools/asset_gallery_check.gd`, que la verifica— para que
## la lista de lo que *debería* haber salga siempre del mismo cálculo.
##
## ## Sin listas a mano
##
## Cada familia sale de su propia fuente de verdad, nunca de una tabla escrita
## acá:
##
## | Filas | Fuente |
## |---|---|
## | `Pueblo/*` | `assets/town/pieces_manifest.json` (54 piezas) |
## | `Ciudad/*` | `assets/city/pieces_manifest.json` (13 piezas) |
## | `Rocas` | `ROCK_IDS` y `ROCK_DIR` de `tools/build_city_meshes.gd` |
## | `Escombros` | los `.res` de `assets/city/rubble/` |
## | `Enemigos` | [constant EnemyCatalog.ENTRIES], con el GLB **estático** de cada uno |
## | `Dron` | `assets/drone/drone_quad.glb` |
## | `Pila` | `vfx/battery_cell.tscn` |
## | `VFX`, `Decals` | [constant VFXPool.SPECS], sólo las escenas con malla o decal |
## | `Horneados/*` | los `.res` de `assets/city/town_a/` y `assets/city/terrain/` |
## | `Packs/*`, `Enemigos/Vista previa` | cada `assets/preview/*/pieces_manifest.json` (WP-G2) |
##
## Si mañana entra una pieza nueva en cualquiera de esas fuentes, la galería la
## muestra al volver a hornearla y el check la exige: no hay que tocar este
## archivo.
##
## ## Por qué no tiene `class_name`
##
## Nombra a [EnemyCatalog] y a [VFXPool], y [VFXPool] arrastra a los autoload.
## El horneador corre con `-s`, que compila su script antes de dar de alta los
## autoload: si este archivo fuera una clase global y el horneador la nombrara,
## el arranque moriría con «Identifier not found». El horneador lo pide con
## `load()` dentro de `_initialize()`; el check, que es una escena normal, con
## `preload`.
extends RefCounted

## Orden y nombre de las filas. `node` es el nombre del nodo en la escena (el
## árbol del editor no admite `/`); `zone` separa las filas de piezas de las de
## mallas horneadas, que van aparte, a escala 1. Dos claves opcionales:
## `reference`, el id de la pieza que se pone al principio de la fila como
## referencia de escala (`house_a` en las del pueblo, `car_a` junto a los autos
## del pack), y `gap`, el aire mínimo entre piezas en metros, para las filas cuyas
## etiquetas necesitan un paso propio: los mechas de veinte metros y las filas de
## packs donde una pieza de 0,9 m (un cartel, un cajón) queda al lado de una de
## 4-6 m, que aleja la cámara y junta las etiquetas de las chicas.
const ROWS: Array[Dictionary] = [
	{"name": "Pueblo/Edificios", "node": "Pueblo_Edificios", "zone": "main"},
	{"name": "Pueblo/Props", "node": "Pueblo_Props", "zone": "main", "reference": "house_a"},
	{"name": "Pueblo/Vehículos (placeholder)", "node": "Pueblo_Vehiculos", "zone": "main",
			"reference": "house_a"},
	{"name": "Pueblo/Follaje", "node": "Pueblo_Follaje", "zone": "main", "reference": "house_a"},
	{"name": "Ciudad/Edificios", "node": "Ciudad_Edificios", "zone": "main"},
	{"name": "Ciudad/Props", "node": "Ciudad_Props", "zone": "main"},
	{"name": "Ciudad/Viario", "node": "Ciudad_Viario", "zone": "main"},
	{"name": "Rocas", "node": "Rocas", "zone": "main"},
	{"name": "Escombros", "node": "Escombros", "zone": "main"},
	{"name": "Enemigos", "node": "Enemigos", "zone": "main"},
	{"name": "Enemigos/Vista previa", "node": "Enemigos_VistaPrevia", "zone": "main",
			"reference": "house_a", "gap": 16.0},
	{"name": "Packs/Autos y calle", "node": "Packs_Autos", "zone": "main", "reference": "car_a",
			"gap": 3.0},
	{"name": "Packs/Ciudad voxel", "node": "Packs_CiudadVoxel", "zone": "main",
			"reference": "house_a"},
	{"name": "Packs/Aldea", "node": "Packs_Aldea", "zone": "main", "reference": "house_a",
			"gap": 4.5},
	{"name": "Packs/Follaje extra", "node": "Packs_Follaje", "zone": "main",
			"reference": "house_a", "gap": 3.0},
	{"name": "Packs/Nuke extra", "node": "Packs_Nuke", "zone": "main", "reference": "house_a"},
	{"name": "Packs/Barrancas", "node": "Packs_Barrancas", "zone": "main",
			"reference": "house_a"},
	{"name": "Dron", "node": "Dron", "zone": "main"},
	{"name": "Pila", "node": "Pila", "zone": "main"},
	{"name": "VFX", "node": "VFX", "zone": "main"},
	{"name": "Decals", "node": "Decals", "zone": "main"},
	{"name": "Horneados/Pueblo", "node": "Horneados_Pueblo", "zone": "baked"},
	{"name": "Horneados/Terreno", "node": "Horneados_Terreno", "zone": "baked"},
]

const TOWN_MANIFEST: String = "res://assets/town/pieces_manifest.json"
## Carpeta de las vistas previas de packs (WP-G2): una subcarpeta por pack, cada
## una con su `pieces_manifest.json` escrito por `voxsplit`.
const PREVIEW_DIR: String = "res://assets/preview"
const CITY_MANIFEST: String = "res://assets/city/pieces_manifest.json"
const CITY_MESHES_TOOL: String = "res://tools/build_city_meshes.gd"
const RUBBLE_DIR: String = "res://assets/city/rubble"
const DRONE_GLB: String = "res://assets/drone/drone_quad.glb"
const BATTERY_SCENE: String = "res://vfx/battery_cell.tscn"
const TOWN_BAKED_DIR: String = "res://assets/city/town_a"
const TERRAIN_BAKED_DIR: String = "res://assets/city/terrain"
const ENEMY_CATALOG: String = "res://enemies/enemy_catalog.gd"
const VFX_POOL: String = "res://vfx/vfx_pool.gd"
const VFX_GUIDE: String = "res://vfx/vfx_guide.gd"
const VFX_TEXTURES: String = "res://vfx/vfx_textures.gd"

## Largo representativo de los haces y las guías en la galería, en metros. En
## el juego lo fija el ataque (`set_endpoints`); en la galería no corre ningún
## script, así que el horneador lo deja escrito sobre la malla de la instancia.
const BEAM_LENGTH: float = 10.0

## Altura a la que flotan los haces horizontales y las guías sobre el suelo.
const BEAM_LIFT: float = 1.0

## Haces que se muestran de pie: la columna de asedio cae del cielo.
const VERTICAL_BEAMS: PackedStringArray = ["siege_column"]

## Lado del marcador del recurso de datos del relieve, que no tiene malla.
const DATA_MARKER_SIDE: float = 20.0

## Cuánto se levantan las mallas horneadas sobre el suelo de la galería: la
## plaza y el césped son planos y sin esto parpadean contra la rejilla.
const BAKED_LIFT: float = 0.05


# --------------------------------------------------------------------------
# La lista
# --------------------------------------------------------------------------

## Todas las entradas de la galería, en orden de fila.
##
## Cada entrada es un diccionario con:
## `id`, `row` (nombre de fila), `path` (escena o `.res`), `kind` (`scene`,
## `mesh`, `multimesh`, `shape` o `data`), `origin`, `klass`, `dims` (A×F×H de la
## etiqueta), `tris`, `placeholder`, `extra` (sufijo de la etiqueta), `yaw` (giro
## en Y), `aabb` (caja local **sin girar**, para repartir la fila), `lift`
## (`false` en los decals, que proyectan sobre el suelo desde su centro) y
## `note` (aclaración que va en el informe).
static func entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	found.append_array(_town_entries())
	found.append_array(_city_entries())
	found.append_array(_rock_entries())
	found.append_array(_rubble_entries())
	found.append_array(_enemy_entries())
	found.append_array(_preview_entries())
	found.append_array(_drone_entries())
	found.append_array(_battery_entries())
	found.append_array(_vfx_entries())
	found.append_array(_baked_entries(TOWN_BAKED_DIR, "Horneados/Pueblo"))
	found.append_array(_baked_entries(TERRAIN_BAKED_DIR, "Horneados/Terreno"))
	return found


## Texto de la etiqueta de [param entry]: `id` y, debajo,
## `origen · clase · A×F×H m · N tris` (+ `PLACEHOLDER`, + KB y superficies en
## los horneados).
static func label_text(entry: Dictionary) -> String:
	if String(entry.get("kind", "")) == "data":
		return "%s\n%s · %s%s" % [String(entry["id"]), String(entry["origin"]),
				String(entry["klass"]), String(entry.get("extra", ""))]
	var dims: Vector3 = entry["dims"]
	var line := "%s · %s · %s×%s×%s m · %d tris" % [
		String(entry["origin"]), String(entry["klass"]),
		num(dims.x), num(dims.y), num(dims.z), int(entry["tris"])]
	if bool(entry.get("placeholder", false)):
		line += " · PLACEHOLDER"
	if bool(entry.get("preview_only", false)):
		line += " · VISTA PREVIA"
	line += String(entry.get("extra", ""))
	return "%s\n%s" % [String(entry["id"]), line]


## Número corto para la etiqueta: sin ceros de más y con la precisión que el
## tamaño merece.
static func num(value: float) -> String:
	var text := ""
	if absf(value) >= 100.0:
		text = "%.0f" % value
	elif absf(value) >= 10.0:
		text = "%.1f" % value
	else:
		text = "%.2f" % value
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text


## Cámara que encuadra el tramo de fila entre [param min_x] y [param max_x]
## (coordenadas de mundo), de [param height] metros de alto, con la fila en
## [param z]; [param front] es cuánto sobresale el tramo hacia la cámara desde
## [param z] (un camión de ocho metros visto de frente), y la distancia se mide
## desde ahí. Es la regla de `town_showcase.gd::_shoot_row()`: la distancia sale
## del ancho y del campo de visión, no de un número a ojo.
##
## Lo chato —el relieve, el asfalto, un decal— se mira más desde arriba: a ras
## del suelo una losa de 260 m es una raya.
static func frame(min_x: float, max_x: float, height: float, z: float, fov: float,
		front: float = 0.0) -> Transform3D:
	var width := max_x - min_x
	var distance := frame_distance(width, height, fov)
	var centre := (min_x + max_x) * 0.5
	var flat := clampf(1.0 - height / maxf(width, 0.01) * 4.0, 0.0, 1.0)
	var lift := maxf(height * 0.55, 1.6) + distance * (0.18 + 0.8 * flat)
	var eye := Vector3(centre, lift, z + maxf(front, 0.0) + distance)
	var target := Vector3(centre, height * 0.45, z)
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


## Distancia de cámara con la que un tramo de [param width] metros de ancho y
## [param height] de alto entra en cuadro con un campo de visión vertical de
## [param fov] grados. El horizontal, con 16:9, es 1,6 veces el vertical (con
## aire).
static func frame_distance(width: float, height: float, fov: float) -> float:
	var half_fov := tan(deg_to_rad(fov) * 0.5)
	var margin := width * 0.5 + 2.0
	return maxf(maxf(margin / (half_fov * 1.6), height * 0.75 / half_fov), 3.0)


## Nombre de nodo de la fila [param row_name].
static func row_node(row_name: String) -> String:
	return String(row_info(row_name).get("node", ""))


## La entrada de [constant ROWS] de la fila [param row_name], o `{}`.
static func row_info(row_name: String) -> Dictionary:
	for row: Dictionary in ROWS:
		if String(row["name"]) == row_name:
			return row
	return {}


# --------------------------------------------------------------------------
# Fuentes
# --------------------------------------------------------------------------

## Las 54 piezas del pueblo. Sus medidas y su triangulación vienen del
## manifiesto, que es lo que el diseño del pueblo consume.
static func _town_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var pieces := (_read_json(TOWN_MANIFEST).get("pieces", {}) as Dictionary)
	var ids: Array = pieces.keys()
	ids.sort()
	for raw: Variant in ids:
		var id := String(raw)
		var entry := pieces[id] as Dictionary
		var footprint: Array = entry.get("footprint", [1.0, 1.0])
		var fx := float(footprint[0])
		var fz := float(footprint[1])
		var height := float(entry.get("height", 0.0))
		var klass := String(entry.get("class", ""))
		var placeholder := bool(entry.get("placeholder", false))
		var row := "Pueblo/Props"
		match klass:
			"building":
				row = "Pueblo/Edificios"
			"foliage":
				row = "Pueblo/Follaje"
		if placeholder:
			row = "Pueblo/Vehículos (placeholder)"
		# La regla de `town_showcase.gd::_lay_row()`: el frente real del pueblo
		# es −X y un cuarto de vuelta lo trae hacia la cámara (+Z); un tramo
		# `+X-run` no tiene frente y corre a lo largo de la fila.
		var front := String(entry.get("front", "-X"))
		var yaw := PI * 0.5 if front == "-X" else 0.0
		var origin := String(entry.get("origin", "base_centre"))
		var box := AABB(Vector3(-fx * 0.5, 0.0, -fz * 0.5), Vector3(fx, height, fz))
		match origin:
			"start_x":
				box.position.x = 0.0
			"deck_top_centre":
				box.position.y = -height
		found.append({
			"id": id, "row": row, "path": String(entry.get("scene", "")),
			"kind": "scene", "origin": String(entry.get("source", "")), "klass": klass,
			"dims": Vector3(fx, fz, height), "tris": int(entry.get("tris", 0)),
			"placeholder": placeholder, "extra": "", "yaw": yaw, "aabb": box,
			"lift": true, "note": "",
		})
	return found


## Las 13 piezas de ciudad del FreeSample, desde su manifiesto.
static func _city_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var rows := {"building": "Ciudad/Edificios", "prop": "Ciudad/Props",
			"street": "Ciudad/Viario"}
	for raw: Variant in _read_json(CITY_MANIFEST).get("pieces", []) as Array:
		var entry := raw as Dictionary
		if entry == null:
			continue
		var path := String(entry.get("scene", ""))
		var measured := _measure_scene(path)
		var size: Array = entry.get("base_size", [0.0, 0.0, 0.0])
		var family := String(entry.get("family", ""))
		found.append({
			"id": String(entry.get("id", "")), "row": String(rows.get(family, "")),
			"path": path, "kind": "scene", "origin": String(entry.get("source", "")),
			"klass": family,
			"dims": Vector3(float(size[0]), float(size[2]), float(size[1])),
			"tris": int(measured["tris"]), "placeholder": false, "extra": "", "yaw": 0.0,
			"aabb": measured["aabb"], "lift": true, "note": "",
		})
	return found


## Las seis rocas de borde, en el orden de `ROCK_IDS`.
static func _rock_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var tool: Variant = load(CITY_MESHES_TOOL)
	var rock_dir := String(tool.ROCK_DIR)
	for letter: String in tool.ROCK_IDS:
		var id := "rock_%s" % letter
		found.append(_scene_entry(id, "Rocas", "%s/%s.tscn" % [rock_dir, id],
				"procedural", "rock"))
	return found


## Las cinco mallas de escombro: todo `.res` de `assets/city/rubble/` (las formas
## de colisión son `.tres` y no entran).
static func _rubble_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for file: String in _sorted_files(RUBBLE_DIR, "res"):
		var path := "%s/%s" % [RUBBLE_DIR, file]
		var mesh := load(path) as Mesh
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		var note := ""
		if box.size.is_equal_approx(Vector3.ONE):
			note = "malla unitaria: el juego la escala al tamaño del edificio caído"
		found.append({
			"id": file.get_basename(), "row": "Escombros", "path": path, "kind": "mesh",
			"origin": "procedural", "klass": "rubble", "dims": _dims(box),
			"tris": mesh_tris(mesh), "placeholder": false, "extra": "", "yaw": 0.0,
			"aabb": box, "lift": true, "note": note,
		})
	return found


## Un enemigo por entrada del catálogo, con su GLB **estático** —la escena de
## juego arranca IA y marcha—, que vive junto a la escena con el mismo nombre.
static func _enemy_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var catalog: Variant = load(ENEMY_CATALOG)
	var table: Dictionary = catalog.ENTRIES
	for raw: Variant in table:
		var id := String(raw)
		var scene := String((table[raw] as Dictionary).get("scene", ""))
		var glb := "%s/%s.glb" % [scene.get_base_dir(), id]
		found.append(_scene_entry(id, "Enemigos", glb, "voxsplit", "enemy"))
	return found


## Las vistas previas de los packs de `assets/_raw/` (WP-G2): cada
## `assets/preview/<pack>/pieces_manifest.json`, sin conocer ningún pack. La fila
## sale de `row` de cada pieza, así que un pack nuevo entra sin tocar código:
## basta con que su receta de `voxsplit` escriba el manifiesto en una carpeta
## nueva (y, si trae una fila nueva, una línea en [constant ROWS]).
##
## Son GLB **estáticos** importados sin `import_script`: se instancian como
## escena, con el giro `yaw` (grados) del manifiesto si su frente no es +Z. La
## caja sale de `footprint` y `height`, con el origen en el centro de la base,
## que es lo que `voxsplit` garantiza al escribirlos. `sort: height` (los
## mechas) ordena de menor a mayor altura; si no, por `order` (1 si falta) y
## después por id.
static func _preview_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var folders := DirAccess.get_directories_at(PREVIEW_DIR)
	folders.sort()
	for folder: String in folders:
		var path := "%s/%s/pieces_manifest.json" % [PREVIEW_DIR, folder]
		if not FileAccess.file_exists(path):
			continue
		var manifest := _read_json(path)
		var listed: Array[Dictionary] = []
		for raw: Variant in manifest.get("pieces", []) as Array:
			var piece := raw as Dictionary
			if piece == null:
				continue
			var footprint: Array = piece.get("footprint", [1.0, 1.0])
			var fx := float(footprint[0])
			var fz := float(footprint[1])
			var height := float(piece.get("height", 0.0))
			listed.append({
				"id": String(piece.get("id", "")), "row": String(piece.get("row", "")),
				"path": String(piece.get("scene", "")), "kind": "scene",
				"origin": String(piece.get("pack", "")), "klass": String(piece.get("class", "")),
				"dims": Vector3(fx, fz, height), "tris": int(piece.get("tris", 0)),
				"placeholder": bool(piece.get("placeholder", false)),
				"preview_only": bool(piece.get("preview_only", false)), "extra": "",
				"yaw": deg_to_rad(float(piece.get("yaw", 0.0))),
				"aabb": AABB(Vector3(-fx * 0.5, 0.0, -fz * 0.5), Vector3(fx, height, fz)),
				"lift": true, "note": String(piece.get("note", "")),
				"order": int(piece.get("order", 1)),
			})
		if String(manifest.get("sort", "id")) == "height":
			listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ha := (a["dims"] as Vector3).z
				var hb := (b["dims"] as Vector3).z
				return ha < hb if ha != hb else String(a["id"]) < String(b["id"]))
		else:
			listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var oa := int(a["order"])
				var ob := int(b["order"])
				return oa < ob if oa != ob else String(a["id"]) < String(b["id"]))
		found.append_array(listed)
	return found


static func _drone_entries() -> Array[Dictionary]:
	return [_scene_entry(DRONE_GLB.get_file().get_basename(), "Dron", DRONE_GLB,
			"voxsplit", "drone")]


## La pila, con sus instancias colocadas por [method place_battery].
static func _battery_entries() -> Array[Dictionary]:
	var node := instance(BATTERY_SCENE)
	if node == null:
		return []
	place_battery(node)
	var measured := measure(node)
	node.free()
	var box: AABB = measured["aabb"]
	return [{
		"id": BATTERY_SCENE.get_file().get_basename(), "row": "Pila", "path": BATTERY_SCENE,
		"kind": "scene", "origin": "procedural", "klass": "pickup", "dims": _dims(box),
		"tris": int(measured["tris"]), "placeholder": false, "extra": "", "yaw": 0.0,
		"aabb": box, "lift": true, "note": "",
	}]


## Las escenas de [constant VFXPool.SPECS] que tienen algo que ver quieto: una
## malla (fila `VFX`) o un decal (fila `Decals`). Las de sólo partículas no
## entran: en la galería no emite nada.
static func _vfx_entries() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var pool: Variant = load(VFX_POOL)
	var specs: Dictionary = pool.SPECS
	for raw: Variant in specs:
		var id := String(raw)
		var path := String((specs[raw] as Dictionary).get("scene", ""))
		var node := instance(path)
		if node == null:
			continue
		var has_mesh := false
		var has_decal := false
		for child: Node in walk(node):
			has_mesh = has_mesh or child is MeshInstance3D
			has_decal = has_decal or child is Decal
		if not has_mesh and not has_decal:
			node.free()
			continue
		var beam := node.get_node_or_null(^"Beam") != null 				or node.get_node_or_null(^"Line") != null
		prepare_vfx(node, id, {})
		var measured := measure(node)
		node.free()
		var box: AABB = measured["aabb"]
		var extra := ""
		var note := ""
		if beam:
			extra = " · largo %s m" % num(BEAM_LENGTH)
			note = "largo representativo de %s m fijado en el horneado" % num(BEAM_LENGTH)
		found.append({
			"id": id, "row": "VFX" if has_mesh else "Decals", "path": path, "kind": "scene",
			"origin": "procedural", "klass": "vfx" if has_mesh else "decal",
			"dims": _dims(box), "tris": int(measured["tris"]), "placeholder": false,
			"extra": extra, "yaw": 0.0, "aabb": box, "lift": has_mesh and not beam, "note": note,
		})
	return found


## Los `.res` horneados de [param dir]: mallas, `MultiMesh`, la forma de colisión
## y el recurso de datos del relieve.
static func _baked_entries(dir: String, row: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for file: String in _sorted_files(dir, "res"):
		var path := "%s/%s" % [dir, file]
		var resource := load(path)
		var kb := float(FileAccess.get_file_as_bytes(path).size()) / 1024.0
		var entry := {
			"id": file.get_basename(), "row": row, "path": path, "origin": "horneado",
			"placeholder": false, "yaw": 0.0, "lift": true, "note": "",
		}
		if resource is Mesh:
			var mesh := resource as Mesh
			var box := mesh.get_aabb()
			entry.merge({"kind": "mesh", "klass": "ArrayMesh", "dims": _dims(box),
					"tris": mesh_tris(mesh), "aabb": box,
					"extra": " · %s KB · %d sup" % [num(kb), mesh.get_surface_count()]})
		elif resource is MultiMesh:
			var multi := resource as MultiMesh
			var box := multimesh_aabb(multi)
			var surfaces := multi.mesh.get_surface_count() if multi.mesh != null else 0
			entry.merge({"kind": "multimesh", "klass": "MultiMesh×%d" % multi.instance_count,
					"dims": _dims(box), "tris": multimesh_tris(multi), "aabb": box,
					"extra": " · %s KB · %d sup" % [num(kb), surfaces]})
		elif resource is HeightMapShape3D:
			var shape := resource as HeightMapShape3D
			var box := heightmap_aabb(shape)
			entry.merge({"kind": "shape",
					"klass": "HeightMapShape3D %d×%d" % [shape.map_width, shape.map_depth],
					"dims": _dims(box),
					"tris": 2 * (shape.map_width - 1) * (shape.map_depth - 1), "aabb": box,
					"extra": " · %s KB · colisión" % num(kb),
					"note": "forma de colisión: se ve como rejilla (gizmo del editor)"})
		else:
			var class_label := resource.get_class() if resource != null else "?"
			var script := resource.get_script() as Script if resource != null else null
			if script != null and not script.get_global_name().is_empty():
				class_label = String(script.get_global_name())
			var side := DATA_MARKER_SIDE
			var box := AABB(Vector3(-side * 0.5, 0.0, -side * 0.5), Vector3(side, 0.2, side))
			entry.merge({"kind": "data", "klass": class_label, "dims": Vector3.ZERO,
					"tris": 0, "aabb": box, "extra": " · %s KB · datos, sin malla" % num(kb),
					"note": "recurso de datos: la galería muestra un marcador, no lo carga"})
		found.append(entry)
	return found


# --------------------------------------------------------------------------
# Preparación de los VFX para la galería
# --------------------------------------------------------------------------

## Deja la instancia de un efecto lista para mirarla quieta, **sin llamar a su
## script**: le quita el script (en la galería no corre nada), estira los haces
## y las guías a [constant BEAM_LENGTH], enciende las mallas que la escena trae
## apagadas y, si [param textures] trae texturas por nombre, las cablea como lo
## haría [VFXEffect] con el metadato `vfx_texture`.
static func prepare_vfx(root: Node3D, id: String, textures: Dictionary) -> void:
	var guide_mode := int(root.get(&"mode")) if root.get(&"mode") != null else -1
	root.set_script(null)
	for node: Node in walk(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.visible = true
	var beam := root.get_node_or_null(^"Beam") as MeshInstance3D
	if beam != null and beam.mesh is CylinderMesh:
		_stretch_beam(root, beam, VERTICAL_BEAMS.has(id))
	var line := root.get_node_or_null(^"Line") as MeshInstance3D
	if line != null:
		_draw_guide(line, guide_mode == 1)
	if not textures.is_empty():
		_wire_textures(root, textures)


## Nombres de textura de [VFXTextures] que piden las entradas de VFX, para que el
## horneador las guarde una vez.
static func texture_names(node: Node) -> PackedStringArray:
	var names := PackedStringArray()
	for child: Node in walk(node):
		if child.has_meta(&"vfx_texture") and (child is Decal or child is MeshInstance3D):
			var key := String(child.get_meta(&"vfx_texture"))
			if not names.has(key):
				var _added := names.append(key)
	return names


## Genera la textura procedural [param key] con [VFXTextures].
static func make_texture(key: String) -> Texture2D:
	var textures: Variant = load(VFX_TEXTURES)
	if not textures.has_method(key):
		return null
	return textures.call(key) as Texture2D


static func _stretch_beam(root: Node3D, beam: MeshInstance3D, vertical: bool) -> void:
	var mesh := (beam.mesh as CylinderMesh).duplicate() as CylinderMesh
	mesh.height = BEAM_LENGTH
	beam.mesh = mesh
	beam.top_level = false
	var radius := mesh.top_radius
	var tip := Vector3.ZERO
	if vertical:
		beam.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, BEAM_LENGTH * 0.5, 0.0))
		tip = Vector3(0.0, 0.0, 0.0)
	else:
		# El eje del cilindro es +Y; un cuarto de vuelta sobre Z lo acuesta a lo
		# largo de +X, que es la dirección de la fila.
		var lift := radius + BEAM_LIFT
		beam.transform = Transform3D(Basis(Vector3.BACK, -PI * 0.5),
				Vector3(BEAM_LENGTH * 0.5, lift, 0.0))
		tip = Vector3(BEAM_LENGTH, lift, 0.0)
	for name: StringName in [&"ImpactLight", &"ContactSparks"]:
		var extra := root.get_node_or_null(NodePath(String(name))) as Node3D
		if extra != null:
			extra.top_level = false
			extra.transform = Transform3D(Basis.IDENTITY, tip)


## La cinta de la guía (recta o parábola punteada) como `ArrayMesh`, encarada a
## +Z —donde está la cámara de la fila— con el ancho y la flecha del script.
static func _draw_guide(line: MeshInstance3D, parabola: bool) -> void:
	var guide: Variant = load(VFX_GUIDE)
	var width := float(guide.DEFAULT_WIDTH)
	var segments := int(guide.SEGMENTS) if parabola else 1
	var arc := float(guide.ARC_HEIGHT)
	var from := Vector3(0.0, BEAM_LIFT, 0.0)
	var to := Vector3(BEAM_LENGTH, BEAM_LIFT, 0.0)
	var points := PackedVector3Array()
	for index: int in segments + 1:
		var ratio := float(index) / float(segments)
		var point := from.lerp(to, ratio)
		if parabola:
			point.y += sin(PI * ratio) * BEAM_LENGTH * arc
		var _point := points.append(point)
	var vertices := PackedVector3Array()
	for index: int in points.size() - 1:
		if parabola and index % 2 == 1:
			continue
		var a := points[index]
		var b := points[index + 1]
		var side := (b - a).normalized().cross(Vector3.BACK).normalized() * (width * 0.5)
		for vertex: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
			var _vertex := vertices.append(vertex)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	line.mesh = mesh
	line.top_level = false
	line.transform = Transform3D.IDENTITY


## Réplica del contrato `vfx_texture` de [VFXEffect] para decals y mallas. Los
## materiales de malla son sub-recursos de la escena del efecto: se duplican y
## van como `material_override` del nodo, que es lo único que se guarda en la
## escena de la galería.
static func _wire_textures(root: Node, textures: Dictionary) -> void:
	for node: Node in walk(root):
		if not node.has_meta(&"vfx_texture"):
			continue
		var texture := textures.get(String(node.get_meta(&"vfx_texture")), null) as Texture2D
		if texture == null:
			continue
		var decal := node as Decal
		if decal != null:
			decal.texture_albedo = texture
			if decal.has_meta(&"vfx_emissive") and bool(decal.get_meta(&"vfx_emissive")):
				decal.texture_emission = texture
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		var source: Material = mesh_instance.material_override
		if source == null and mesh_instance.mesh != null:
			source = mesh_instance.mesh.surface_get_material(0)
		var material := source.duplicate() as BaseMaterial3D if source != null else null
		if material != null:
			material.albedo_texture = texture
			mesh_instance.material_override = material


# --------------------------------------------------------------------------
# La pila
# --------------------------------------------------------------------------

## Coloca las instancias de los tres `MultiMesh` de la pila **sin su script**.
##
## En el juego las escribe `BatteryCell._ready()` con `set_instance_transform()`,
## pero el horneador corre en `--headless`, donde el servidor de render es nulo:
## `set_instance_transform()` no hace nada y `get_instance_transform()` devuelve
## la identidad (medido: `buffer` vacío tras el `_ready()`). Lo único que el
## servidor nulo sí conserva es el `buffer` entero, así que se escribe ése, con
## las mismas piezas que `BatteryCell._build_shell()` (el cuerpo, el casquillo y
## el borne), los anillos de `BatteryCell.BAND_HEIGHTS` y las motas del halo en
## la fase 0 de `BatteryCell._place_motes()`. Cada `MultiMesh` es una copia
## propia: los de la escena son sub-recursos compartidos y no se tocan.
static func place_battery(root: Node) -> void:
	var cell: Variant = load(BATTERY_SCENE.get_basename() + ".gd")
	var shell: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3.ZERO),
		Transform3D(Basis().scaled(Vector3(0.74, 0.18, 0.74)), Vector3(0.0, 0.48, 0.0)),
		Transform3D(Basis().scaled(Vector3(0.36, 0.16, 0.36)), Vector3(0.0, 0.62, 0.0)),
	]
	var colours: Array[Color] = []
	for colour: Color in cell.SHELL_COLORS:
		colours.append(colour)
	var bands: Array[Transform3D] = []
	for height: float in cell.BAND_HEIGHTS:
		bands.append(Transform3D(Basis.IDENTITY, Vector3(0.0, height, 0.0)))
	var motes: Array[Transform3D] = []
	var count := int(cell.MOTE_COUNT)
	var radius := float(cell.MOTE_RADIUS)
	for index: int in count:
		var share := float(index) / float(count)
		var angle := TAU * share
		var bob := sin(TAU * share) * float(cell.MOTE_BOB)
		motes.append(Transform3D(Basis.IDENTITY,
				Vector3(cos(angle) * radius, bob, sin(angle) * radius)))
	var no_colours: Array[Color] = []
	var layout: Dictionary[String, Array] = {"Shell": shell, "Bands": bands, "Halo": motes}
	for name: String in layout:
		var node := root.get_node_or_null(NodePath(name)) as MultiMeshInstance3D
		if node == null or node.multimesh == null:
			continue
		var placed: Array[Transform3D] = []
		placed.assign(layout[name])
		node.multimesh = _filled_multimesh(node.multimesh, placed,
				colours if name == "Shell" else no_colours)


## Copia de [param source] con [param placed] escritas directamente en el
## `buffer` (y [param colours], si el `MultiMesh` usa color por instancia).
static func _filled_multimesh(source: MultiMesh, placed: Array[Transform3D],
		colours: Array[Color]) -> MultiMesh:
	var copy := MultiMesh.new()
	copy.transform_format = MultiMesh.TRANSFORM_3D
	copy.use_colors = source.use_colors
	copy.use_custom_data = source.use_custom_data
	copy.mesh = source.mesh
	copy.instance_count = source.instance_count
	var data := PackedFloat32Array()
	for index: int in source.instance_count:
		var t: Transform3D = placed[index] if index < placed.size() else Transform3D.IDENTITY
		data.append_array(PackedFloat32Array([
			t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
			t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y,
			t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z]))
		if source.use_colors:
			var c: Color = colours[index] if index < colours.size() else Color.WHITE
			data.append_array(PackedFloat32Array([c.r, c.g, c.b, c.a]))
		if source.use_custom_data:
			data.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	copy.buffer = data
	return copy


## Transformadas de instancia de [param multi] leídas del `buffer`, que es lo
## único que conserva el servidor de render nulo de `--headless`.
static func multimesh_transforms(multi: MultiMesh) -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	var data := multi.buffer
	var stride := 12 + (4 if multi.use_colors else 0) + (4 if multi.use_custom_data else 0)
	if multi.transform_format != MultiMesh.TRANSFORM_3D \
			or data.size() < stride * multi.instance_count:
		for index: int in multi.instance_count:
			found.append(multi.get_instance_transform(index))
		return found
	for index: int in multi.instance_count:
		var at := index * stride
		found.append(Transform3D(
				Vector3(data[at], data[at + 4], data[at + 8]),
				Vector3(data[at + 1], data[at + 5], data[at + 9]),
				Vector3(data[at + 2], data[at + 6], data[at + 10]),
				Vector3(data[at + 3], data[at + 7], data[at + 11])))
	return found


# --------------------------------------------------------------------------
# Medición
# --------------------------------------------------------------------------

## Caja y triángulos de la geometría visible de [param root], en su espacio
## local: mallas, `MultiMesh`, decals y la forma de altura si la hay.
static func measure(root: Node) -> Dictionary:
	var box := AABB()
	var first := true
	var tris := 0
	for node: Node in walk(root):
		var local := AABB()
		var has := false
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh := (node as MeshInstance3D).mesh
			local = mesh.get_aabb()
			tris += mesh_tris(mesh)
			has = true
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multi := (node as MultiMeshInstance3D).multimesh
			local = multimesh_aabb(multi)
			tris += multimesh_tris(multi)
			has = true
		elif node is Decal:
			var size := (node as Decal).size
			local = AABB(-size * 0.5, size)
			has = true
		elif node is CollisionShape3D and (node as CollisionShape3D).shape is HeightMapShape3D:
			local = heightmap_aabb((node as CollisionShape3D).shape as HeightMapShape3D)
			has = true
		if not has:
			continue
		var world := relative_transform(node as Node3D, root) * local
		box = world if first else box.merge(world)
		first = false
	return {"aabb": box, "tris": tris}


## Mide la escena de [param path] instanciándola fuera del árbol.
static func _measure_scene(path: String) -> Dictionary:
	var node := instance(path)
	if node == null:
		return {"aabb": AABB(), "tris": 0}
	var measured := measure(node)
	node.free()
	return measured


## Transformada de [param node] relativa a [param root], sin pasar por el árbol.
static func relative_transform(node: Node3D, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			result = spatial.transform * result
		current = current.get_parent()
	return result


## Triángulos de [param mesh], contando índices o, sin índices, vértices.
static func mesh_tris(mesh: Mesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null and (indices as PackedInt32Array).size() > 0:
			total += (indices as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


static func multimesh_tris(multi: MultiMesh) -> int:
	if multi.mesh == null:
		return 0
	return mesh_tris(multi.mesh) * multi.instance_count


## Caja de un `MultiMesh` a partir de sus transformadas de instancia: en
## `--headless` el servidor de render es nulo y `get_aabb()` devuelve vacío.
static func multimesh_aabb(multi: MultiMesh) -> AABB:
	if multi.mesh == null or multi.instance_count == 0:
		return AABB()
	var local := multi.mesh.get_aabb()
	var box := AABB()
	var first := true
	for placed_at: Transform3D in multimesh_transforms(multi):
		var placed := placed_at * local
		box = placed if first else box.merge(placed)
		first = false
	return box


## Caja de una forma de altura centrada en el origen, con paso de 1 m.
static func heightmap_aabb(shape: HeightMapShape3D) -> AABB:
	var low := shape.get_min_height()
	var high := shape.get_max_height()
	var width := float(shape.map_width - 1)
	var depth := float(shape.map_depth - 1)
	return AABB(Vector3(-width * 0.5, low, -depth * 0.5), Vector3(width, high - low, depth))


## A×F×H de la etiqueta: ancho en X, fondo en Z y alto en Y.
static func _dims(box: AABB) -> Vector3:
	return Vector3(box.size.x, box.size.z, box.size.y)


static func _scene_entry(id: String, row: String, path: String, origin: String,
		klass: String) -> Dictionary:
	var measured := _measure_scene(path)
	var box: AABB = measured["aabb"]
	return {
		"id": id, "row": row, "path": path, "kind": "scene", "origin": origin,
		"klass": klass, "dims": _dims(box), "tris": int(measured["tris"]),
		"placeholder": false, "extra": "", "yaw": 0.0, "aabb": box, "lift": true,
		"note": "",
	}


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Instancia la escena de [param path], o `null` si no carga. Con
## [param for_bake] la instancia guarda el estado de su escena
## (`GEN_EDIT_STATE_INSTANCE`), que es lo que `PackedScene.pack()` necesita para
## escribir sólo lo que cambió —el script quitado, el haz estirado— y no una
## copia de cada propiedad.
static func instance(path: String, for_bake: bool = false) -> Node3D:
	if not ResourceLoader.exists(path):
		push_error("asset_gallery: falta '%s'" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("asset_gallery: '%s' no es una escena" % path)
		return null
	var state := PackedScene.GEN_EDIT_STATE_INSTANCE if for_bake 			else PackedScene.GEN_EDIT_STATE_DISABLED
	return packed.instantiate(state) as Node3D


## [param root] y toda su descendencia, en profundidad.
static func walk(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		found.append_array(found[index].get_children())
		index += 1
	return found


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("asset_gallery: falta '%s'" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var document := parsed as Dictionary
	return document if document != null else {}


## Archivos con extensión [param extension] de [param dir], ordenados.
static func _sorted_files(dir: String, extension: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			var _file := found.append(file)
	found.sort()
	return found
