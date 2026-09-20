## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Genera **una sola vez** el distrito `city/districts/district_a.tscn` y, si
## faltan, los dos perfiles de `city/profiles/` (`docs/10` §4.3 y §12, decisión
## 10: el distrito se comitea como escena concreta, no se siembra en cada
## arranque, para que los oclusores y `city_check` sean reproducibles).
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_district.gd
## [/codeblock]
##
## Los perfiles **no se pisan** si ya existen: son datos de diseño y un
## ajuste manual de balance no debe perderse al regenerar el distrito. Para
## rehacerlos hay que borrarlos.
##
## ## Por qué el trabajo va en `_initialize()` y las variables son `Variant`
##
## Con `-s`, Godot compila el script del bucle principal **antes** de dar de
## alta los autoload. [CityGrid] arrastra a [Building], que emite en `Events` y
## lee `Global.round_seed`: escribir `var grid := CityGrid.new()` obligaría al
## analizador a compilar esa cadena demasiado temprano y el arranque fallaría
## con «Identifier not found: Global». La herramienta carga las clases con
## `load()` ya dentro de [method _initialize], cuando los autoload existen, y
## declara los locales como `Variant` —explícito, no inferido— para que el
## despacho sea dinámico.
extends SceneTree

const DISTRICT_PATH: String = "res://city/districts/district_a.tscn"
const PROFILE_DIR: String = "res://city/profiles"
const RUBBLE_DIR: String = "res://assets/city/rubble"
const PIECE_DIR: String = "res://city/pieces"

## Semilla fija de `district_a` (`docs/10` §4.3).
const DISTRICT_SEED: int = 0


func _initialize() -> void:
	_ensure_dir(PROFILE_DIR)
	_ensure_dir(DISTRICT_PATH.get_base_dir())

	var low_profile: Variant = _ensure_profile("low_block")
	var tall_profile: Variant = _ensure_profile("tower")

	var grid_script: Variant = load("res://city/city_grid.gd")
	var grid: Variant = grid_script.new()
	grid.name = "DistrictA"
	grid.seed = DISTRICT_SEED
	grid.low_profile = low_profile
	grid.tall_profile = tall_profile
	grid.low_pieces = _scenes([
		"block_low_a", "block_low_b", "block_low_c", "block_mid", "tower_b"])
	grid.tall_pieces = _scenes(["tower_a"])
	grid.mid_tower_pieces = _scenes(["tower_b", "block_mid"])
	grid.prop_pieces = _scenes(["props/sign_b", "props/sign_c", "props/dish"])
	grid.rock_scenes = _rocks()
	grid.road_piece = _scene("road_chunk")
	grid.sidewalk_piece = _scene("sidewalk_chunk")
	grid.sidewalk_tile_piece = _scene("sidewalk_tile")
	grid.ground_material = _load("res://assets/city/materials/ground.tres", "Material")

	grid.build()
	grid.claim_ownership(grid)
	_report(grid)

	var packed := PackedScene.new()
	var err := packed.pack(grid)
	if err != OK:
		push_error("build_district: no se pudo empaquetar: %s" % error_string(err))
		grid.free()
		quit(1)
		return
	err = ResourceSaver.save(packed, DISTRICT_PATH)
	grid.free()
	if err != OK:
		push_error("build_district: no se pudo guardar '%s': %s" % [DISTRICT_PATH, error_string(err)])
		quit(1)
		return
	print("build_district: %s guardado (%.1f KB)." % [DISTRICT_PATH, _size_kb(DISTRICT_PATH)])
	quit(0)


# --------------------------------------------------------------------------
# Perfiles
# --------------------------------------------------------------------------

## Carga el perfil [param id] o lo crea con los valores de `docs/10` §4.2 y §10.
func _ensure_profile(id: String) -> Resource:
	var path := "%s/%s.tres" % [PROFILE_DIR, id]
	if ResourceLoader.exists(path):
		return _load(path, "BuildingProfile")

	var profile_script: Variant = load("res://city/building_profile.gd")
	var profile: Variant = profile_script.new()
	profile.resource_name = id
	profile.id = StringName(id)
	profile.damaged_threshold = 0.60
	profile.rubble_threshold = 0.15
	profile.debris_count_min = 4
	profile.debris_count_max = 8
	profile.collapse_seconds = 1.8
	profile.siege_window = 3.0
	profile.siege_damage = 150.0
	profile.rubble_height_factor = 0.18
	profile.rubble_height_max = 3.0
	profile.smoke_seconds = 12.0

	if id == "tower":
		profile.max_hp = 3500.0
		profile.value = 300
		profile.debris_mass = 2000.0
		profile.debris_impulse = 4.5
		profile.dust_scale = 1.0
		# `docs/10` §10 fija el trauma del derrumbe de una torre en 0.85 y el de
		# un bloque bajo en 0.65; WP-20 desdobla además el de la etapa DAMAGED,
		# que el documento no distinguía.
		profile.trauma_damaged = 0.65
		profile.trauma_rubble = 0.85
		profile.debris_mesh = _load("%s/debris_concrete_large.res" % RUBBLE_DIR, "Mesh")
		profile.debris_shape = _load("%s/debris_concrete_large_shape.tres" % RUBBLE_DIR, "Shape3D")
		profile.rubble_meshes = _piles(["low", "mid", "high"])
	else:
		profile.max_hp = 1200.0
		profile.value = 100
		profile.debris_mass = 450.0
		profile.debris_impulse = 6.0
		profile.dust_scale = 0.85
		profile.trauma_damaged = 0.45
		profile.trauma_rubble = 0.65
		profile.debris_mesh = _load("%s/debris_concrete_small.res" % RUBBLE_DIR, "Mesh")
		profile.debris_shape = _load("%s/debris_concrete_small_shape.tres" % RUBBLE_DIR, "Shape3D")
		profile.rubble_meshes = _piles(["low", "mid"])

	var err := ResourceSaver.save(profile, path)
	if err != OK:
		push_error("build_district: no se pudo guardar '%s': %s" % [path, error_string(err)])
	else:
		print("  perfil creado: %s" % path)
	return _load(path, "BuildingProfile")


func _piles(names: Array) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	for name: String in names:
		var mesh: Mesh = _load("%s/rubble_pile_%s.res" % [RUBBLE_DIR, name], "Mesh")
		if mesh != null:
			meshes.append(mesh)
	return meshes


# --------------------------------------------------------------------------
# Informe
# --------------------------------------------------------------------------

## Imprime la tabla de edificios por tipo, el HP total y la extensión.
func _report(grid: Variant) -> void:
	var buildings: Array = grid.get_buildings()
	var by_piece: Dictionary[String, int] = {}
	var by_piece_hp: Dictionary[String, float] = {}
	var by_piece_min: Dictionary[String, float] = {}
	var by_piece_max: Dictionary[String, float] = {}
	var total_hp := 0.0
	var low_count := 0
	var tall_count := 0

	for building: Variant in buildings:
		var piece := String(building.get_meta(&"piece", &"?"))
		var key := "%s [%s]" % [piece, building.profile.id]
		by_piece[key] = by_piece.get(key, 0) + 1
		by_piece_hp[key] = by_piece_hp.get(key, 0.0) + float(building.get_max_hp())
		var height: float = building.get_height()
		by_piece_min[key] = minf(by_piece_min.get(key, 999.0), height)
		by_piece_max[key] = maxf(by_piece_max.get(key, 0.0), height)
		total_hp += float(building.get_max_hp())
		if building.profile.id == &"tower":
			tall_count += 1
		else:
			low_count += 1

	print("  edificios: %d (bajos %d · torres %d)" % [buildings.size(), low_count, tall_count])
	for key: String in by_piece:
		print("    %-26s ×%-3d  HP %7.0f  altura %5.1f – %5.1f m" \
				% [key, by_piece[key], by_piece_hp[key], by_piece_min[key], by_piece_max[key]])
	print("  HP total: %.0f · extensión %s m (núcleo %s m) · celda %.0f m" \
			% [total_hp, str(grid.get_extent()), str(grid.get_core_extent()), grid.cell_size])
	_report_lanes(grid)
	_report_streets(grid)
	_report_rocks(grid)
	_report_markers(grid)
	var occluders: Node = grid.get_node(NodePath("Occluders"))
	print("  rocas: %d · oclusores: %d" % [grid.get_rocks().size(), occluders.get_child_count()])


## Plano de carriles por eje: clase y ancho de cada uno, y la suma que da la
## extensión. Es la tabla que `city_check` rehace con la fórmula nueva.
func _report_lanes(grid: Variant) -> void:
	for axis: int in 2:
		var names := ["X", "Z"]
		var line := ""
		var total := 0.0
		var count: int = grid.get_cols() if axis == 0 else grid.get_rows()
		for lane: int in count:
			var kind: int = grid.lane_kind(axis, lane)
			var width: float = grid.lane_width(axis, lane)
			total += width
			line += "%s%.0f " % [["B", "c", "A"][kind], width]
		print("  carriles %s (%d): %s= %.0f m" % [names[axis], count, line, total])
	print("  avenidas: cruce en %s · calle %.0f m (vereda %.0f) · avenida %.0f m (vereda %.0f, cantero %.0f)" \
			% [str(grid.avenue_crossing()), grid.street_width, grid.street_sidewalk,
			grid.avenue_width, grid.avenue_sidewalk, grid.avenue_median])


## Instancias por [MultiMeshInstance3D] de la red viaria.
func _report_streets(grid: Variant) -> void:
	var streets: Node = grid.get_node(NodePath("Streets"))
	var total := 0
	var line := ""
	for child: Node in streets.get_children():
		var multi := child as MultiMeshInstance3D
		if multi == null:
			continue
		total += multi.multimesh.instance_count
		line += "%s %d · " % [multi.name, multi.multimesh.instance_count]
	print("  calles: %d MultiMesh (%s%d instancias)" % [streets.get_child_count(), line, total])


## Altura de cada roca y su ángulo respecto de la línea de visión inicial del
## dron: ninguna puede caer dentro del cono de 30°.
func _report_rocks(grid: Variant) -> void:
	for rock: Variant in grid.get_rocks():
		var height := 0.0
		for child: Node in rock.get_children():
			var mesh_instance := child as MeshInstance3D
			if mesh_instance != null and mesh_instance.mesh != null:
				height = maxf(height, mesh_instance.mesh.get_aabb().size.y)
		print("    %-8s %s  alto %5.1f m  ángulo al centro %5.1f°  al rumbo del dron %5.1f°" \
				% [rock.name, str(rock.position), height,
				grid.spawn_cone_angle(rock.position), grid.spawn_view_angle(rock.position)])


## Candidatos para `BatterySpawner/Marker*`: los cruces de calle y las azoteas
## más altas. Se copian a mano a `rounds/battle_level.tscn`, que no lo genera
## esta herramienta.
func _report_markers(grid: Variant) -> void:
	var crossings: Array[String] = []
	for lane_x: int in grid.get_cols():
		if grid.lane_kind(0, lane_x) == 0:
			continue
		for lane_z: int in grid.get_rows():
			if grid.lane_kind(1, lane_z) == 0:
				continue
			crossings.append("(%.0f, %.0f)" % [grid.lane_centre(0, lane_x),
					grid.lane_centre(1, lane_z)])
	print("  cruces de calle (%d): %s" % [crossings.size(), ", ".join(crossings)])

	var sorted: Array = grid.get_buildings()
	sorted.sort_custom(func(a: Variant, b: Variant) -> bool:
		return a.get_height() > b.get_height())
	for index: int in mini(3, sorted.size()):
		var building: Variant = sorted[index]
		print("    hito   %-14s %s  techo %.1f m  huella %.0f × %.0f m" \
				% [building.name, str(building.position),
				building.position.y + building.get_height(),
				building.base_size.x, building.base_size.z])
	# Azoteas de torre media, que son las que sirven de puesto de pila: un techo
	# de 16 m está al alcance del dron y el de un hito de 80 no.
	var shown := 0
	for building: Variant in sorted:
		if shown >= 4:
			break
		var height: float = building.get_height()
		if height < 14.0 or height > 18.0:
			continue
		shown += 1
		print("    azotea %-14s %s  techo %.1f m  huella %.0f × %.0f m" \
				% [building.name, str(building.position), building.position.y + height,
				building.base_size.x, building.base_size.z])


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

func _scenes(names: Array) -> Array[PackedScene]:
	var found: Array[PackedScene] = []
	for name: String in names:
		var scene := _scene(name)
		if scene != null:
			found.append(scene)
	return found


func _scene(name: String) -> PackedScene:
	return _load("%s/%s.tscn" % [PIECE_DIR, name], "PackedScene") as PackedScene


func _rocks() -> Array[PackedScene]:
	var found: Array[PackedScene] = []
	for id: String in ["a", "b", "c", "d", "e", "f"]:
		var scene := _load("res://world/rocks/rock_%s.tscn" % id, "PackedScene") as PackedScene
		if scene != null:
			found.append(scene)
	return found


func _load(path: String, hint: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_error("build_district: falta '%s'." % path)
		return null
	return ResourceLoader.load(path, hint)


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("build_district: no se pudo crear '%s': %s" % [path, error_string(err)])


func _size_kb(path: String) -> float:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0.0
	var size := float(file.get_length()) / 1024.0
	file.close()
	return size
