## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Hornea `tools/asset_gallery.tscn`: la galería de inventario de assets (plan
## P2e). **No es un check** ni forma parte del juego: es una escena para abrir en
## el editor y recorrer todos los assets uno al lado del otro, por familia, con
## una etiqueta que dice cómo se llama cada uno, de dónde viene, qué es, cuánto
## mide y cuántos triángulos tiene.
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_asset_gallery.gd
## [/codeblock]
##
## Qué entra y en qué fila lo decide `tools/asset_gallery_sources.gd` (sin
## listas a mano: cada familia sale de su propia fuente de verdad). Este script
## sólo reparte, etiqueta y guarda.
##
## ## La escena
##
## - Raíz `Node3D` **sin script**, y ningún nodo con script: al abrirla en el
##   editor no corre nada del juego. Los efectos de `vfx/` y la pila se
##   instancian con el script quitado en la instancia (sus escenas no se tocan);
##   lo que sus scripts harían en el juego —estirar un haz, dibujar una guía,
##   cablear una textura procedural, colocar las motas de la pila— queda
##   escrito en el horneado.
## - `WorldEnvironment` y `Sun` como `tools/town_showcase.tscn` (el sol lleva el
##   perfil de atardecer ya aplicado, sin `SunLight`), un suelo con rejilla de
##   10 m, una `Camera3D` mirando la primera fila y un título con la fecha del
##   horneado y los conteos por familia.
## - Una fila por familia a lo largo de +X, apiladas hacia −Z; cada fila arranca
##   con un poste de escala de 2 m y, si la fila lo declara en `ROWS`
##   (`reference`), con una pieza de referencia: `house_a` en las del pueblo y
##   las de packs, `car_a` junto a los autos del pack. Las mallas horneadas del
##   nivel van aparte, desde −400 m, a escala 1.
## - Por pieza, un nodo `slot_<id>` con la instancia (que se llama `<id>`, para
##   buscarla con el filtro del árbol) y su etiqueta.
##
## ## Determinismo
##
## Dos horneados seguidos dan el mismo md5: los identificadores del `.tscn` los
## reescribe [method SceneBake.stabilise_ids]. La única entrada que cambia sola
## es la fecha del título, que va sin hora.
##
## ## Por qué el trabajo va en `_initialize()`
##
## Con `-s` el script del bucle principal se compila antes de dar de alta los
## autoload, y las fuentes nombran a `VFXPool`, que los necesita. Todo lo que
## toca clases del juego se pide con `load()` ya dentro de [method _initialize].
extends SceneTree

const OUT_PATH: String = "res://tools/asset_gallery.tscn"
const SOURCES_PATH: String = "res://tools/asset_gallery_sources.gd"
const GRID_MATERIAL: String = "res://assets/city/materials/gallery_grid.tres"
const TEXTURE_DIR: String = "res://tools/asset_gallery"
const ENVIRONMENT: String = "res://world/environment_battle.tres"
const CAMERA_ATTRIBUTES: String = "res://world/camera_attributes_dusk.tres"
const SUN_PROFILE: String = "res://world/sun_dusk.tres"
const REFERENCE_ID: String = "house_a"

## Tope del `.tscn`, en kilobytes: las mallas van por referencia, nunca adentro.
const TSCN_BUDGET_KB: float = 500.0

## Cuánto se separan las filas de piezas entre sí y cuánto las horneadas.
const ROW_GAP_MIN: float = 12.0
const BAKED_FRONT_Z: float = -400.0
const BAKED_ROW_SPACING: float = 300.0
const BAKED_GAP: float = 40.0

## Etiquetas: tamaño en pantalla fijo, fuente mono.
const LABEL_FONT_SIZE: int = 32
const LABEL_PIXEL_SIZE: float = 0.00045

## Desplazamiento vertical, en píxeles de texto, de la etiqueta de las piezas
## impares de cada fila: dos pisos de etiquetas alternados para que las de
## piezas vecinas no se pisen (con tamaño fijo en pantalla, el desplazamiento en
## píxeles también es fijo).
const LABEL_TIER_OFFSET: float = 120.0
const TITLE_FONT_SIZE: int = 56

## Poste de escala.
const SCALE_HEIGHT: float = 2.0
const SCALE_RADIUS: float = 0.06

var _sources: Variant = null
var _font: Font = null
var _scale_mesh: Mesh = null
var _marker_mesh: Mesh = null
var _textures: Dictionary = {}
var _entries: Array[Dictionary] = []


func _initialize() -> void:
	_sources = load(SOURCES_PATH)
	_font = load("res://gui/theme/theme_builder.gd").font_mono() as Font
	_entries = _sources.entries()
	if not _unique_ids():
		quit(1)
		return
	_textures = _bake_textures()

	var gallery := Node3D.new()
	gallery.name = "AssetGallery"
	_add_environment(gallery)
	var rows := Node3D.new()
	rows.name = "Rows"
	gallery.add_child(rows)
	var bounds := _lay_rows(rows)
	_add_ground(gallery, bounds)
	_add_camera(gallery, rows)
	_add_title(gallery)

	_own(gallery, gallery)
	var packed := PackedScene.new()
	var err := packed.pack(gallery)
	gallery.free()
	if err != OK:
		push_error("build_asset_gallery: no se pudo empaquetar: %s" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("build_asset_gallery: no se pudo guardar '%s': %s"
				% [OUT_PATH, error_string(err)])
		quit(1)
		return
	SceneBake.stabilise_ids(OUT_PATH, "build_asset_gallery")
	_report()
	var size := float(FileAccess.get_file_as_bytes(OUT_PATH).size()) / 1024.0
	print("build_asset_gallery: %s guardado (%.1f KB de %.0f)." % [OUT_PATH, size, TSCN_BUDGET_KB])
	if size > TSCN_BUDGET_KB:
		push_error("build_asset_gallery: '%s' pesa %.1f KB y el tope es %.0f KB."
				% [OUT_PATH, size, TSCN_BUDGET_KB])
		quit(1)
		return
	quit(0)


# --------------------------------------------------------------------------
# Filas
# --------------------------------------------------------------------------

## Reparte todas las filas y devuelve la caja que ocupan, para el suelo.
func _lay_rows(rows: Node3D) -> AABB:
	var bounds := AABB(Vector3(-20.0, 0.0, -20.0), Vector3(40.0, 1.0, 40.0))
	var front := 0.0
	var baked_centre := 0.0
	var baked_half := 0.0
	var first_baked := true
	for row: Dictionary in _sources.ROWS:
		var name := String(row["name"])
		var members := _members(name)
		var baked := String(row["zone"]) == "baked"
		var items := _row_items(name, members, baked)
		var depth := 4.0
		for item: Dictionary in items:
			depth = maxf(depth, (item["box"] as AABB).size.z)
		var centre := 0.0
		if not baked:
			centre = front - depth * 0.5
			front = centre - depth * 0.5 - maxf(ROW_GAP_MIN, depth * 0.6)
		elif first_baked:
			centre = minf(BAKED_FRONT_Z, front) - depth * 0.5
			first_baked = false
		else:
			# Trescientos metros entre centros, o lo que haga falta para que el
			# relieve (512 m de colisión) no pise a la fila de al lado.
			centre = baked_centre - maxf(BAKED_ROW_SPACING, baked_half + depth * 0.5 + BAKED_GAP)
		if baked:
			baked_centre = centre
			baked_half = depth * 0.5
		var row_node := Node3D.new()
		row_node.name = String(row["node"])
		row_node.position = Vector3(0.0, 0.0, centre)
		row_node.set_meta(&"row", name)
		rows.add_child(row_node)
		var width := _place_row(row_node, name, items, members.size())
		bounds = bounds.merge(AABB(Vector3(-20.0, 0.0, centre - depth * 0.5),
				Vector3(width + 40.0, 1.0, depth)))
	return bounds


## Entradas de la fila [param row_name], en orden de fuente (con `house_a`
## primero en los edificios del pueblo: es la referencia de escala).
func _members(row_name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if String(entry["row"]) != row_name:
			continue
		if String(entry["id"]) == REFERENCE_ID:
			found.push_front(entry)
		else:
			found.append(entry)
	return found


## Qué va en la fila y cuánto ocupa cada cosa: el poste de escala, la pieza de
## referencia que declare la fila en `ROWS` (`house_a`, `car_a`) y las piezas.
func _row_items(row_name: String, members: Array[Dictionary], baked: bool) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var info: Dictionary = _sources.row_info(row_name)
	items.append({"kind": "scale",
			"box": AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, SCALE_HEIGHT, 0.6))})
	var reference_id := String(info.get("reference", ""))
	if not reference_id.is_empty():
		var reference := _entry(reference_id)
		if not reference.is_empty():
			items.append({"kind": "reference", "entry": reference,
					"box": _rotated_box(reference)})
	for entry: Dictionary in members:
		items.append({"kind": "slot", "entry": entry, "box": _rotated_box(entry)})
	# Aire proporcional: cada pieza deja un 30 % de su ancho, con un piso que
	# sale de la pieza típica de la fila para que las chicas no queden pegadas.
	var widths: Array[float] = []
	for item: Dictionary in items:
		widths.append((item["box"] as AABB).size.x)
	widths.sort()
	var floor_gap := clampf(widths[widths.size() / 2] * 0.35, 1.5, 20.0)
	# Paso propio de la fila (`gap` en `ROWS`): con piezas de veinte metros el
	# 30 % del ancho deja las etiquetas de dos vecinos pisándose.
	floor_gap = maxf(floor_gap, float(info.get("gap", 0.0)))
	for item: Dictionary in items:
		var width := (item["box"] as AABB).size.x
		item["gap"] = BAKED_GAP if baked else maxf(floor_gap, width * 0.3)
	return items


## Coloca los elementos de una fila a lo largo de +X y devuelve su largo.
func _place_row(row_node: Node3D, row_name: String, items: Array[Dictionary],
		count: int) -> float:
	var reach := _label_reach(items)
	var tops := _label_tops(items)
	var cursor := 0.0
	var tier := 0
	for index: int in items.size():
		var item: Dictionary = items[index]
		var box: AABB = item["box"]
		var at := Vector3(cursor + box.size.x * 0.5, 0.0, 0.0)
		match String(item["kind"]):
			"scale":
				row_node.add_child(_scale_post(at, reach))
				tier += 1
			"reference":
				var reference := _instance_for(item["entry"])
				reference.name = "ref_%s" % String((item["entry"] as Dictionary)["id"])
				reference.position += at
				row_node.add_child(reference)
			"slot":
				var slot := _slot(item["entry"], at, reach, tops[index])
				if tier % 2 == 1:
					(slot.get_node(^"Label") as Label3D).offset = Vector2(0.0, LABEL_TIER_OFFSET)
				row_node.add_child(slot)
				tier += 1
		cursor += box.size.x + float(item["gap"])
	var title := _label("%s · %d" % [row_name, count], TITLE_FONT_SIZE, reach)
	title.name = "Title"
	title.position = Vector3(0.0, SCALE_HEIGHT + 1.6, 0.0)
	row_node.add_child(title)
	return cursor


## Altura de la etiqueta de cada elemento de la fila: el techo más alto entre
## él y sus dos vecinos. Con dos pisos de etiquetas alternados, lo que las hace
## chocar no es el piso sino la diferencia de alturas entre vecinos (un tacho de
## 20 cm al lado de uno de 75); igualarlas con los vecinos deja que los pisos
## hagan su trabajo sin mandar la etiqueta de una casa a la altura del silo del
## otro extremo de la fila.
func _label_tops(items: Array[Dictionary]) -> Array[float]:
	var own: Array[float] = []
	for item: Dictionary in items:
		var box: AABB = item["box"]
		var entry: Dictionary = item.get("entry", {})
		own.append(box.size.y if bool(entry.get("lift", true)) else box.end.y)
	var tops: Array[float] = []
	for index: int in own.size():
		var top := own[index]
		if index > 0:
			top = maxf(top, own[index - 1])
		if index < own.size() - 1:
			top = maxf(top, own[index + 1])
		tops.append(top)
	return tops


## Distancia a la que se apagan las etiquetas de la fila: con tamaño fijo en
## pantalla y sin prueba de profundidad, las de las filas de atrás se leerían
## encima de las de adelante. Crece con el tamaño de lo que la fila muestra.
func _label_reach(items: Array[Dictionary]) -> float:
	var biggest := 1.0
	for item: Dictionary in items:
		var size := (item["box"] as AABB).size
		biggest = maxf(biggest, maxf(size.x, maxf(size.y, size.z)))
	return maxf(90.0, biggest * 5.0)


## Un `slot_<id>`: la instancia y su etiqueta.
func _slot(entry: Dictionary, at: Vector3, reach: float, top: float) -> Node3D:
	var slot := Node3D.new()
	slot.name = "slot_%s" % String(entry["id"])
	slot.position = at
	slot.set_meta(&"asset_id", String(entry["id"]))
	slot.set_meta(&"source_path", String(entry["path"]))
	slot.set_meta(&"kind", String(entry["kind"]))
	slot.set_meta(&"row", String(entry["row"]))
	var body := _instance_for(entry)
	if body != null:
		slot.add_child(body)
	var label := _label(String(_sources.label_text(entry)), LABEL_FONT_SIZE, reach)
	label.name = "Label"
	label.position = Vector3(0.0, top + maxf(0.3, top * 0.04), 0.0)
	slot.add_child(label)
	return slot


## La instancia de [param entry], ya girada y apoyada: la caja girada queda
## centrada en el origen del slot en X y Z, con la base en y = 0.
func _instance_for(entry: Dictionary) -> Node3D:
	var basis := Basis(Vector3.UP, float(entry["yaw"]))
	var box := _rotated_box(entry)
	var offset := Vector3(-(box.position.x + box.size.x * 0.5), 0.0,
			-(box.position.z + box.size.z * 0.5))
	if bool(entry.get("lift", true)):
		offset.y = -box.position.y
	var path := String(entry["path"])
	var node: Node3D = null
	match String(entry["kind"]):
		"scene":
			node = _scene_instance(entry)
		"mesh":
			var mesh_node := MeshInstance3D.new()
			mesh_node.mesh = load(path) as Mesh
			node = mesh_node
		"multimesh":
			var multi_node := MultiMeshInstance3D.new()
			multi_node.multimesh = load(path) as MultiMesh
			node = multi_node
		"shape":
			# La forma de colisión del relieve: en el editor el gizmo de la
			# `CollisionShape3D` la dibuja como rejilla. Capa y máscara en cero:
			# en la galería no choca nada.
			var body := StaticBody3D.new()
			body.collision_layer = 0
			body.collision_mask = 0
			var shape_node := CollisionShape3D.new()
			shape_node.name = "Shape"
			shape_node.shape = load(path) as Shape3D
			shape_node.debug_color = Color(0.35, 0.85, 1.0, 1.0)
			shape_node.debug_fill = false
			body.add_child(shape_node)
			node = body
		"data":
			var marker := MeshInstance3D.new()
			marker.mesh = _marker()
			node = marker
	if node == null:
		return null
	if String(entry["origin"]) == "horneado":
		offset.y += float(_sources.BAKED_LIFT)
	node.name = String(entry["id"])
	node.transform = Transform3D(basis, offset)
	return node


## Instancia una escena de pieza. Los efectos se preparan para verse quietos y
## la pila recibe sus instancias ya colocadas; a los dos se les quita el script
## en la instancia.
func _scene_instance(entry: Dictionary) -> Node3D:
	var node: Node3D = _sources.instance(String(entry["path"]), true)
	if node == null:
		return null
	var row := String(entry["row"])
	if row == "VFX" or row == "Decals":
		_sources.prepare_vfx(node, String(entry["id"]), _textures)
		node.set_meta(&"gallery_editable", true)
	elif row == "Pila":
		_sources.place_battery(node)
		node.set_script(null)
		node.set_meta(&"gallery_editable", true)
	return node


## Poste de escala de 2 m con su etiqueta.
func _scale_post(at: Vector3, reach: float) -> Node3D:
	var post := Node3D.new()
	post.name = "Escala"
	post.position = at
	var mesh := MeshInstance3D.new()
	mesh.name = "Poste"
	mesh.mesh = _scale()
	mesh.position = Vector3(0.0, SCALE_HEIGHT * 0.5, 0.0)
	post.add_child(mesh)
	var label := _label("2 m", LABEL_FONT_SIZE, reach)
	label.name = "Label"
	label.position = Vector3(0.0, SCALE_HEIGHT + 0.25, 0.0)
	post.add_child(label)
	return post


func _label(text: String, font_size: int, reach: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = font_size
	label.outline_size = 10
	label.modulate = Color(0.96, 0.95, 0.9, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.pixel_size = LABEL_PIXEL_SIZE
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = reach
	return label


# --------------------------------------------------------------------------
# Entorno, suelo, cámara y título
# --------------------------------------------------------------------------

func _add_environment(gallery: Node3D) -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = load(ENVIRONMENT) as Environment
	world.camera_attributes = load(CAMERA_ATTRIBUTES) as CameraAttributes
	gallery.add_child(world)
	# El sol de las escenas del juego es un `SunLight` (`@tool`) que lee su
	# perfil al entrar al árbol. En la galería no corre ningún script: el perfil
	# se aplica acá, una vez, y queda escrito en la luz.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var profile: Variant = load(SUN_PROFILE)
	if profile != null:
		profile.apply_to(sun)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	gallery.add_child(sun)


## Suelo con rejilla de 10 m que cubre todas las filas.
func _add_ground(gallery: Node3D, bounds: AABB) -> void:
	var plane := PlaneMesh.new()
	var margin := 60.0
	plane.size = Vector2(ceilf(bounds.size.x + margin * 2.0), ceilf(bounds.size.z + margin * 2.0))
	plane.material = load(GRID_MATERIAL) as Material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var centre := bounds.get_center()
	ground.position = Vector3(roundf(centre.x), 0.0, roundf(centre.z))
	gallery.add_child(ground)


## Cámara inicial: mirando el comienzo de la primera fila.
func _add_camera(gallery: Node3D, rows: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 55.0
	camera.far = 6000.0
	var first := rows.get_child(0) as Node3D
	var z := first.position.z if first != null else 0.0
	camera.transform = _sources.frame(0.0, 40.0, 8.0, z, camera.fov)
	gallery.add_child(camera)


func _add_title(gallery: Node3D) -> void:
	var counts := PackedStringArray()
	var total := 0
	for group: String in ["Pueblo", "Ciudad", "Rocas", "Escombros", "Enemigos", "Packs",
			"Dron", "Pila", "VFX", "Decals", "Horneados"]:
		var count := 0
		for entry: Dictionary in _entries:
			if String(entry["row"]).get_slice("/", 0) == group:
				count += 1
		total += count
		counts.append("%s %d" % [group, count])
	var text := "Galería de assets · %d piezas · horneada %s\n%s" % [
		total, Time.get_date_string_from_system(), " · ".join(counts)]
	var title := _label(text, TITLE_FONT_SIZE, 400.0)
	title.name = "Title"
	title.position = Vector3(20.0, 14.0, 12.0)
	gallery.add_child(title)


# --------------------------------------------------------------------------
# Recursos compartidos
# --------------------------------------------------------------------------

func _scale() -> Mesh:
	if _scale_mesh == null:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = SCALE_RADIUS
		cylinder.bottom_radius = SCALE_RADIUS
		cylinder.height = SCALE_HEIGHT
		cylinder.radial_segments = 8
		cylinder.rings = 1
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.98, 0.72, 0.2, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.98, 0.72, 0.2, 1.0)
		material.emission_energy_multiplier = 0.6
		cylinder.material = material
		_scale_mesh = cylinder
	return _scale_mesh


func _marker() -> Mesh:
	if _marker_mesh == null:
		var side := float(_sources.DATA_MARKER_SIDE)
		var box := BoxMesh.new()
		box.size = Vector3(side, 0.2, side)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.3, 0.55, 0.7, 1.0)
		material.roughness = 0.9
		box.material = material
		_marker_mesh = box
	return _marker_mesh


## Guarda en `tools/asset_gallery/` las texturas procedurales que piden los
## efectos de la galería y las devuelve recargadas desde disco, para que la
## escena las nombre como recurso externo y no las incruste.
func _bake_textures() -> Dictionary:
	var names := PackedStringArray()
	for entry: Dictionary in _entries:
		var row := String(entry["row"])
		if row != "VFX" and row != "Decals":
			continue
		var node: Node3D = _sources.instance(String(entry["path"]))
		if node == null:
			continue
		for key: String in _sources.texture_names(node):
			if not names.has(key):
				var _added := names.append(key)
		node.free()
	names.sort()
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEXTURE_DIR))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("build_asset_gallery: no se pudo crear '%s'" % TEXTURE_DIR)
	var found: Dictionary = {}
	for key: String in names:
		var texture: Texture2D = _sources.make_texture(key)
		if texture == null:
			push_error("build_asset_gallery: VFXTextures no sabe hacer '%s'" % key)
			continue
		var path := "%s/%s.res" % [TEXTURE_DIR, key]
		err = ResourceSaver.save(texture, path)
		if err != OK:
			push_error("build_asset_gallery: no se pudo guardar '%s'" % path)
			continue
		found[key] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return found


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Caja de [param entry] ya girada por su `yaw`.
func _rotated_box(entry: Dictionary) -> AABB:
	var basis := Basis(Vector3.UP, float(entry["yaw"]))
	return Transform3D(basis, Vector3.ZERO) * (entry["aabb"] as AABB)


func _entry(id: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if String(entry["id"]) == id:
			return entry
	return {}


## Los ids son nombres de nodo y de búsqueda: no pueden repetirse.
func _unique_ids() -> bool:
	var seen: Dictionary[String, String] = {}
	var ok := true
	for entry: Dictionary in _entries:
		var id := String(entry["id"])
		if seen.has(id):
			push_error("build_asset_gallery: id repetido '%s' (%s y %s)"
					% [id, seen[id], String(entry["path"])])
			ok = false
		seen[id] = String(entry["path"])
	return ok


## Asigna el dueño a todo lo que se creó acá. Las instancias de escena se
## adueñan sólo en su raíz; los efectos y la pila, cuyos hijos se tocaron, se
## marcan como instancia editable para que el empaquetado guarde esos cambios.
func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		if not child.scene_file_path.is_empty():
			if child.has_meta(&"gallery_editable"):
				child.remove_meta(&"gallery_editable")
				owner.set_editable_instance(child, true)
			continue
		_own(child, owner)


func _report() -> void:
	var per_row: Dictionary[String, int] = {}
	for entry: Dictionary in _entries:
		var row := String(entry["row"])
		per_row[row] = int(per_row.get(row, 0)) + 1
	for row: Dictionary in _sources.ROWS:
		print("  %-32s %3d" % [String(row["name"]), int(per_row.get(String(row["name"]), 0))])
	print("  %-32s %3d" % ["total", _entries.size()])
	for entry: Dictionary in _entries:
		if not String(entry.get("note", "")).is_empty():
			print("  nota %s: %s" % [String(entry["id"]), String(entry["note"])])
