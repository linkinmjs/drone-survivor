## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Genera **una sola vez** el pueblo `city/districts/town_a.tscn` y, si faltan,
## el perfil `city/profiles/house.tres` y el material de campo
## `assets/city/materials/field.tres` (`docs/10` §4.3 y §12, decisión 10: el
## distrito se comitea como escena concreta, no se siembra en cada arranque,
## para que la iluminación, las capturas y los checks sean reproducibles).
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_town.gd
## [/codeblock]
##
## Los perfiles **no se pisan** si ya existen: son datos de diseño y un ajuste
## manual de balance no debe perderse al regenerar el pueblo. Para rehacerlos hay
## que borrarlos.
##
## ## La tabla de piezas
##
## [TownPlan] nombra la pieza de cada parcela con un [StringName] —`&"house_a"`,
## `&"block_mid"`— y no sabe qué archivo es cada una: así el plano y su check
## corren sin abrir un solo asset. Quien traduce es [constant PIECE_PATHS], acá
## abajo. Si a la tabla le falta un archivo la herramienta lo dice con un
## `push_error` y sigue: un pueblo con una parcela vacía es un fallo visible, y
## sustituir la pieza que falta por otra cualquiera —lo que hacía WP-B mientras
## WP-A no había entregado las casas— esconde el problema debajo de un edificio
## que se ve bien y no es el que el plano pidió.
##
## ## Por qué el trabajo va en `_initialize()` y las variables son `Variant`
##
## Con `-s`, Godot compila el script del bucle principal **antes** de dar de alta
## los autoload. [CityGrid] arrastra a [Building], que emite en `Events` y lee
## `Global.round_seed`: escribir `var grid := CityGrid.new()` obligaría al
## analizador a compilar esa cadena demasiado temprano y el arranque fallaría con
## «Identifier not found: Global». La herramienta carga las clases con `load()`
## ya dentro de [method _initialize], cuando los autoload existen, y declara los
## locales como `Variant` —explícito, no inferido— para que el despacho sea
## dinámico.
extends SceneTree

const TOWN_PATH: String = "res://city/districts/town_a.tscn"
const PROFILE_DIR: String = "res://city/profiles"
const RUBBLE_DIR: String = "res://assets/city/rubble"
const MATERIAL_DIR: String = "res://assets/city/materials"
const FIELD_PATH: String = "res://assets/city/materials/field.tres"
const WALKWAY_PATH: String = "res://assets/city/materials/walkway.tres"
const ROADS_PATH: String = "res://assets/city/materials/roads.tres"

## Dónde van las dos mallas de viario horneadas.
##
## Fuera del `.tscn` y en binario: con las cintas de calzada y los anillos de
## vereda incrustados en texto el pueblo se iba muy por encima del tope de
## 500 KB del plan (§5.12). [method CityGrid.save_street_meshes] las escribe y
## deja los nodos apuntando al archivo.
const STREET_DIR: String = "res://assets/city/town_a"

## El relieve horneado por `tools/build_terrain.gd` (WP-T2).
const TERRAIN_PATH: String = "res://assets/city/terrain/town_a_terrain.res"
const TERRAIN_COLLISION_PATH: String = "res://assets/city/terrain/town_a_collision.res"
const TERRAIN_CHUNK_PATH: String = "res://assets/city/terrain/town_a_chunk_%d.res"
const TERRAIN_MATERIAL_PATH: String = "res://assets/city/materials/terrain.tres"

## Tope del `.tscn` horneado, en kilobytes (plan P2c §5.12).
const TSCN_BUDGET_KB: float = 500.0

## Semilla fija de `town_a`.
##
## La fuente de verdad es `TownPlanner.TOWN_SEED`, que es lo que `city_check`
## usa para rehacer el plano y comprobar que la escena comiteada está al día.
## Acá se lee **en tiempo de ejecución** (ver [method _initialize]) y no con un
## `const`: una constante que nombre a `TownPlanner` obliga al analizador a
## compilar `TownPlan` —que lee `Global.round_seed`— antes de que existan los
## autoload, y el arranque muere con «Identifier not found: Global».

## Qué `.tscn` es cada identificador de pieza del plano.
const PIECE_PATHS: Dictionary = {
	&"house_a": "res://city/pieces/town/house_a.tscn",
	&"house_a_b": "res://city/pieces/town/house_a_b.tscn",
	&"house_b": "res://city/pieces/town/house_b.tscn",
	&"house_b_b": "res://city/pieces/town/house_b_b.tscn",
	&"house_c": "res://city/pieces/town/house_c.tscn",
	&"house_c_b": "res://city/pieces/town/house_c_b.tscn",
	&"house_d": "res://city/pieces/town/house_d.tscn",
	&"house_d_b": "res://city/pieces/town/house_d_b.tscn",
	&"shed": "res://city/pieces/town/shed.tscn",
	&"shed_b": "res://city/pieces/town/shed_b.tscn",
	&"block_mid": "res://city/pieces/block_mid.tscn",
	&"tower_b": "res://city/pieces/tower_b.tscn",
	&"block_low_c": "res://city/pieces/block_low_c.tscn",
}

## Props de campo. Son cuatro y no los nueve que trae WP-A a propósito: cada uno
## cuesta un [MultiMesh] —o sea un lote de dibujo— y con maleza, dos clases de
## basura y un barril el campo ya no se lee como una repetición.
const DECOR_PIECES: Array = [
	"res://city/pieces/town/props/overgrowth_a.tscn",
	"res://city/pieces/town/props/trash_1.tscn",
	"res://city/pieces/town/props/barrel_a.tscn",
	"res://city/pieces/town/props/trash_3.tscn",
]

## Piezas de [constant PIECE_PATHS] que no están en disco. Se informan al final.
var _missing: Array[String] = []


func _initialize() -> void:
	_ensure_dir(PROFILE_DIR)
	_ensure_dir(MATERIAL_DIR)
	_ensure_dir(TOWN_PATH.get_base_dir())

	var house_profile: Variant = _ensure_profile("house")
	var big_profile: Variant = _ensure_profile("tower")

	var planner: Variant = load("res://city/town_planner.gd")
	var town_seed: int = planner.TOWN_SEED
	# `generate()` carga el relieve horneado por su cuenta y se lo pasa a
	# `resolve()`: es lo que hace que el plano de acá y el que `city_check`
	# rehace salgan con la misma firma. Acá se vuelve a pedir **el mismo**
	# recurso para dárselo a la rejilla, que lo necesita para apoyar el viario,
	# los caseríos, las rocas y los marcadores.
	var plan: Variant = planner.generate(town_seed)
	var terrain: Variant = planner.baked_terrain()
	if terrain == null:
		push_error("build_town: falta '%s'; corré tools/build_terrain.gd primero."
				% TERRAIN_PATH)

	var grid_script: Variant = load("res://city/city_grid.gd")
	var grid: Variant = grid_script.new()
	grid.name = "TownA"
	grid.plan = plan
	grid.terrain = terrain
	grid.terrain_shape = _load(TERRAIN_COLLISION_PATH, "Shape3D")
	grid.terrain_chunks = _terrain_chunks()
	grid.terrain_material = _load(TERRAIN_MATERIAL_PATH, "Material")
	grid.pieces = _piece_table()
	grid.house_profile = house_profile
	grid.big_profile = big_profile
	grid.prop_pieces = _scenes([
		"res://city/pieces/props/sign_b.tscn",
		"res://city/pieces/props/sign_c.tscn",
		"res://city/pieces/props/dish.tscn"])
	grid.rock_scenes = _rocks()
	grid.road_piece = _scene("res://city/pieces/road_chunk.tscn")
	grid.ground_material = _ensure_field_material()
	grid.walkway_material = _ensure_walkway_material()
	grid.decor_pieces = _scenes(DECOR_PIECES)
	grid.decor_material = _load("%s/props.tres" % MATERIAL_DIR, "Material")

	grid.build()
	# Antes de `claim_ownership` y de empaquetar: las dos mallas de viario se
	# guardan en `.res` binarios y los nodos quedan apuntando al archivo, que es
	# lo que deja el `.tscn` por debajo del tope de 500 KB.
	var street_err: int = grid.save_street_meshes(STREET_DIR)
	if street_err != OK:
		push_error("build_town: no se pudieron guardar las mallas de calle: %s"
				% error_string(street_err))
	grid.claim_ownership(grid)
	_report(grid, plan, terrain)

	var packed := PackedScene.new()
	var err := packed.pack(grid)
	if err != OK:
		push_error("build_town: no se pudo empaquetar: %s" % error_string(err))
		grid.free()
		quit(1)
		return
	err = ResourceSaver.save(packed, TOWN_PATH)
	grid.free()
	if err != OK:
		push_error("build_town: no se pudo guardar '%s': %s" % [TOWN_PATH, error_string(err)])
		quit(1)
		return
	var size := _size_kb(TOWN_PATH)
	print("build_town: %s guardado (%.1f KB de %.0f)." % [TOWN_PATH, size, TSCN_BUDGET_KB])
	if size > TSCN_BUDGET_KB:
		push_error("build_town: '%s' pesa %.1f KB y el tope es %.0f KB: hay geometría"
				% [TOWN_PATH, size, TSCN_BUDGET_KB] + " incrustada que tendría que ser externa.")
		quit(1)
		return
	quit(0)


## Las cuatro mallas del relieve, en el orden en que las hornea
## `tools/build_terrain.gd`.
func _terrain_chunks() -> Array[Mesh]:
	var found: Array[Mesh] = []
	for index: int in 4:
		var mesh := _load(TERRAIN_CHUNK_PATH % index, "Mesh") as Mesh
		if mesh != null:
			found.append(mesh)
	return found


# --------------------------------------------------------------------------
# Piezas
# --------------------------------------------------------------------------

## La tabla que [CityGrid] usa para resolver cada parcela. Lo que falte queda
## anotado en [member _missing] y sale en el informe.
func _piece_table() -> Dictionary:
	var table: Dictionary = {}
	for id: StringName in PIECE_PATHS:
		var path := String(PIECE_PATHS[id])
		if not ResourceLoader.exists(path):
			_missing.append("%s (%s)" % [id, path])
			push_error("build_town: falta la pieza '%s' (%s)." % [id, path])
			continue
		table[id] = _scene(path)
	return table


# --------------------------------------------------------------------------
# Perfiles y materiales
# --------------------------------------------------------------------------

## Carga el perfil [param id] o lo crea.
##
## El perfil `house` es nuevo de WP-B: 1 300 HP, 60 puntos, 300 kg de escombro y
## un trauma de cámara bajo (0,40 al dañarse, 0,55 al caer). Una casa que se cae
## no puede sacudir la cámara como una torre de cuarenta metros —el jugador va a
## ver caer cincuenta— y con dos montículos alcanza: la ruina de una casa de 5 m
## no necesita la pila alta.
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
		profile.trauma_damaged = 0.65
		profile.trauma_rubble = 0.85
		profile.debris_mesh = _load("%s/debris_concrete_large.res" % RUBBLE_DIR, "Mesh")
		profile.debris_shape = _load("%s/debris_concrete_large_shape.tres" % RUBBLE_DIR, "Shape3D")
		profile.rubble_meshes = _piles(["low", "mid", "high"])
	elif id == "house":
		profile.max_hp = 1300.0
		# Las casas de WP-A pintan sus ventanas con una paleta de 256 x 1: el
		# shader de daño de la ciudad la filtra bilineal y con mipmaps, y el
		# vecino de un texel es otro color sin relación, así que la etapa
		# DAMAGED salía gris. `damage_overlay_palette.gdshader` es el mismo
		# shader con `filter_nearest, repeat_disable` (WP-A).
		profile.damage_shader = load("res://city/damage_overlay_palette.gdshader")
		profile.value = 60
		profile.debris_mass = 300.0
		profile.debris_impulse = 6.0
		profile.dust_scale = 0.7
		profile.trauma_damaged = 0.40
		profile.trauma_rubble = 0.55
		profile.debris_count_min = 3
		profile.debris_count_max = 6
		profile.collapse_seconds = 1.4
		profile.smoke_seconds = 9.0
		profile.debris_mesh = _load("%s/debris_concrete_small.res" % RUBBLE_DIR, "Mesh")
		profile.debris_shape = _load("%s/debris_concrete_small_shape.tres" % RUBBLE_DIR, "Shape3D")
		profile.rubble_meshes = _piles(["low", "mid"])
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
		push_error("build_town: no se pudo guardar '%s': %s" % [path, error_string(err)])
	else:
		print("  perfil creado: %s" % path)
	return _load(path, "BuildingProfile")


## Carga el material del campo o lo crea.
##
## El pueblo no está sobre asfalto: `ground.tres` es la playa de estacionamiento
## gris del distrito rectangular, y debajo de un pueblo de ruta se lee como una
## ciudad a la que le faltan los edificios. El campo es tierra con pasto seco, y
## la variación viene del triplanar sobre la posición de mundo: el `PlaneMesh` de
## 1 200 m tiene cuatro vértices y no hay UV que valgan.
##
## ## Dos tonos y una escala larga
##
## La primera versión era un solo tono oscuro con ruido de 22 m: al anochecer el
## campo se leía como una masa negra pareja y el pueblo parecía flotar en el
## vacío. Ahora:
##
## - el ruido va a **83 m de tile con la base en cinco octavas**, así que hay
##   manchones de unos 40 m —que es lo que da la sensación de terreno— y grano
##   fino para cuando el dron pasa a dos metros del suelo;
## - un `color_ramp` de dos tonos mapea ese ruido a **tierra** y **pasto seco**,
##   en vez de multiplicar un gris por un valor;
## - el albedo medio sube un 25 %, y aun así el campo queda **por debajo** de la
##   calzada: el asfalto tiene que seguir leyéndose más claro que el pasto, o la
##   ruta deja de ser lo primero que el ojo encuentra desde el aire.
func _ensure_field_material() -> Resource:
	if ResourceLoader.exists(FIELD_PATH):
		return _load(FIELD_PATH, "Material")

	var noise := FastNoiseLite.new()
	noise.seed = 4711
	noise.frequency = 0.004
	noise.fractal_octaves = 5

	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.115, 0.100, 0.072, 1.0))
	ramp.set_color(1, Color(0.205, 0.210, 0.140, 1.0))
	ramp.add_point(0.52, Color(0.150, 0.148, 0.100, 1.0))

	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.noise = noise
	texture.seamless = true
	texture.color_ramp = ramp

	var material := StandardMaterial3D.new()
	material.resource_name = "town_field"
	# El tinte lo lleva el `color_ramp`: el albedo queda en blanco para no
	# multiplicar dos veces.
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.albedo_texture = texture
	material.roughness = 0.99
	material.metallic_specular = 0.08
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.012, 0.012, 0.012)

	var err := ResourceSaver.save(material, FIELD_PATH)
	if err != OK:
		push_error("build_town: no se pudo guardar '%s': %s" % [FIELD_PATH, error_string(err)])
		return material
	print("  material creado: %s" % FIELD_PATH)
	return _load(FIELD_PATH, "Material")


## Carga el material de vereda o lo deriva del de calzada.
##
## Es `roads.tres` duplicado con el albedo subido y entibiado. Comparte el atlas
## y el emisivo horneado, así que no suma ni una textura al presupuesto de VRAM
## de `docs/10` §2.3: lo único que cambia es el tinte.
##
## Hace falta porque la calzada y la vereda usaban **el mismo** material y sólo
## se distinguían por las marcas pintadas: a nivel de calle no se veía dónde
## terminaba el asfalto y desde el aire el pueblo era una mancha gris pareja.
func _ensure_walkway_material() -> Resource:
	if ResourceLoader.exists(WALKWAY_PATH):
		return _load(WALKWAY_PATH, "Material")
	var roads := _load(ROADS_PATH, "Material") as StandardMaterial3D
	if roads == null:
		push_error("build_town: no se puede derivar la vereda sin '%s'." % ROADS_PATH)
		return null
	var walkway := roads.duplicate() as StandardMaterial3D
	walkway.resource_name = "town_walkway"
	walkway.albedo_color = Color(1.34, 1.27, 1.14, 1.0)
	walkway.roughness = minf(roads.roughness + 0.03, 1.0)
	var err := ResourceSaver.save(walkway, WALKWAY_PATH)
	if err != OK:
		push_error("build_town: no se pudo guardar '%s': %s" % [WALKWAY_PATH, error_string(err)])
		return walkway
	print("  material creado: %s" % WALKWAY_PATH)
	return _load(WALKWAY_PATH, "Material")


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

## Los números del pueblo: manzanas, parcelas por rol, HP, ruta, instancias por
## [MultiMesh] y una estimación de triángulos y lotes de dibujo.
func _report(grid: Variant, plan: Variant, terrain: Variant) -> void:
	print("  semilla %d · radio de juego %.0f m · campo %.0f m"
			% [plan.seed, plan.play_radius, plan.field_size])
	print("  ruta: %.0f m de largo · %d vértices · pasa a %.1f m del centro · %d calles"
			% [plan.route_length(), plan.route.size(),
			plan.distance_to_centre(plan.route_point(plan.route_centre_distance())),
			plan.street_count()])

	var areas: Array[float] = []
	for index: int in plan.block_count():
		areas.append(float(plan.block_area(index)))
	areas.sort()
	print("  manzanas: %d (%.0f–%.0f m², %d a oscuras)"
			% [plan.block_count(), areas[0] if not areas.is_empty() else 0.0,
			areas[areas.size() - 1] if not areas.is_empty() else 0.0,
			plan.dark_blocks().size()])

	_report_roles(grid, plan)
	_report_ground(grid, terrain)
	_report_streets(grid)
	_report_decor(grid, plan)
	_report_markers(grid, plan)
	_report_budget(grid)
	if not _missing.is_empty():
		print("  FALTAN %d piezas y sus parcelas quedaron vacías: %s"
				% [_missing.size(), ", ".join(_missing)])


## Parcelas por rol, con su pieza, su altura y su HP.
func _report_roles(grid: Variant, plan: Variant) -> void:
	var names := ["casa", "mediano", "hito", "escuela", "decorativa"]
	for role: int in names.size():
		var indices: Array = plan.parcels_of_role(role)
		if indices.is_empty():
			continue
		var by_piece: Dictionary = {}
		var hp := 0.0
		var low := 999.0
		var high := 0.0
		for index: int in indices:
			var parcel: Dictionary = plan.parcels[index]
			var piece := String(parcel.get("piece", "?"))
			by_piece[piece] = int(by_piece.get(piece, 0)) + 1
			hp += float(parcel.get("hp", 0.0))
			var scale := float(parcel.get("height_scale", 1.0))
			low = minf(low, scale)
			high = maxf(high, scale)
		var pieces: Array[String] = []
		for piece: String in by_piece:
			pieces.append("%s x%d" % [piece, by_piece[piece]])
		print("    %-11s x%-3d  HP %7.0f  escala %.2f–%.2f  %s"
				% [names[role], indices.size(), hp, low, high, ", ".join(pieces)])

	var buildings: Array = grid.get_buildings()
	var heights: Array[float] = []
	for building: Variant in buildings:
		heights.append(float(building.get_height()))
	heights.sort()
	print("  sembrados: %d edificios (%.1f–%.1f m de alto) · HP total %.0f"
			% [buildings.size(), heights[0] if not heights.is_empty() else 0.0,
			heights[heights.size() - 1] if not heights.is_empty() else 0.0,
			plan.total_hp()])

	var school: int = plan.school_parcel()
	if school >= 0:
		print("    escuela '%s' a %.0f m del centro, sobre la ruta"
				% [plan.parcels[school].get("name", "?"),
				plan.distance_to_centre(plan.parcel_position(school))])


## Triángulos por superficie de la red viaria y dónde quedó cada malla.
func _report_streets(grid: Variant) -> void:
	var streets: Node = grid.get_node(NodePath("Streets"))
	var parts: Array[String] = []
	for child: Node in streets.get_children():
		var surface := child as MeshInstance3D
		if surface == null or surface.mesh == null:
			continue
		var where := surface.mesh.resource_path
		parts.append("%s %d tris → %s" % [surface.name,
				_mesh_triangles(surface.mesh),
				where.get_file() if not where.is_empty() else "INCRUSTADA"])
	print("  calles: %d superficies (%s), 0 MultiMesh, 0 colisionadores"
			% [streets.get_child_count(), " · ".join(parts)])


## El suelo: heightfield, anillo, caja de seguridad, chunks y campo lejano.
func _report_ground(grid: Variant, terrain: Variant) -> void:
	var ground: Node = grid.get_node(NodePath("Ground"))
	var shapes: Array[String] = []
	var chunks := 0
	var field_triangles := 0
	for child: Node in ground.get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shapes.append("%s %s" % [shape.name,
					"heightfield" if shape.shape is HeightMapShape3D else "caja"])
			continue
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if mesh_node.name == "Field":
			field_triangles = _mesh_triangles(mesh_node.mesh)
		else:
			chunks += 1
	var span: Vector2 = terrain.range_of() if terrain != null else Vector2.ZERO
	print("  suelo: %s · %d chunks de relieve (%.2f a %.2f m) · campo lejano de %d triángulos"
			% [", ".join(shapes), chunks, span.x, span.y, field_triangles])


## Lo de afuera del círculo: caseríos, rocas y maleza.
func _report_decor(grid: Variant, plan: Variant) -> void:
	var decor: Node = grid.get_node(NodePath("Decor"))
	var houses := 0
	var props := 0
	var merged := 0
	for child: Node in decor.get_children():
		var multi := child as MultiMeshInstance3D
		if multi != null:
			props += multi.multimesh.instance_count
			continue
		if child is MeshInstance3D:
			merged += 1
			continue
		if child.name.begins_with("Decor_House"):
			houses += 1
	var reach: Array[float] = []
	for index: int in plan.parcels_of_role(4):
		reach.append(float(plan.distance_to_centre(plan.parcel_position(index))))
	reach.sort()
	print(("  afuera: %d casas de caserío (%.0f–%.0f m del centro) · %d rocas · %d props"
			+ " · %d mallas fundidas")
			% [houses, reach[0] if not reach.is_empty() else 0.0,
			reach[reach.size() - 1] if not reach.is_empty() else 0.0,
			grid.get_rocks().size(), props, merged])
	for rock: Variant in grid.get_rocks():
		print("    %-8s %s  a %.0f m del centro · %.0f° de la visual del dron"
				% [rock.name, str(rock.position), plan.distance_to_centre(rock.position),
				plan.spawn_cone_angle(rock.position)])


## Apariciones, puestos de pila y poses.
func _report_markers(grid: Variant, plan: Variant) -> void:
	var spawns: Node = grid.get_node(NodePath("Spawns"))
	var line: Array[String] = []
	for child: Node in spawns.get_children():
		var marker := child as Marker3D
		if marker != null:
			line.append("%s (%.0f, %.0f)" % [marker.name, marker.position.x, marker.position.z])
	print("  apariciones: %s" % ", ".join(line))

	var posts: Node = grid.get_node(NodePath("BatteryPosts"))
	var post_line: Array[String] = []
	for child: Node in posts.get_children():
		var marker := child as Marker3D
		if marker != null:
			post_line.append("%.0f,%.1f,%.0f" % [marker.position.x, marker.position.y,
					marker.position.z])
	print("  puestos de pila (%d): %s" % [posts.get_child_count(), " · ".join(post_line)])

	var drone: Variant = plan.drone_spawn()
	var camera: Variant = plan.camera_fixed()
	print("  dron %s (a %.0f m del centro) · cámara fija %s"
			% [str(drone.origin), plan.distance_to_centre(drone.origin), str(camera.origin)])


## Triángulos y lotes de dibujo estimados.
##
## Es una **estimación de horneado**, no una medida del renderizador: cuenta la
## geometría que la escena lleva adentro sin culling ni LOD, que es la cota
## superior y lo único que se puede saber en `--headless`. Los lotes se cuentan
## por superficie: cada [MultiMeshInstance3D] es uno solo por muchas instancias
## que lleve, y ahí está el ahorro de la red viaria.
func _report_budget(grid: Variant) -> void:
	var triangles := 0
	var batches := 0
	var materials: Dictionary = {}
	for node: Node in _walk(grid):
		var multi := node as MultiMeshInstance3D
		if multi != null and multi.multimesh != null and multi.multimesh.mesh != null:
			triangles += _mesh_triangles(multi.multimesh.mesh) * multi.multimesh.instance_count
			batches += multi.multimesh.mesh.get_surface_count()
			_collect_materials(multi.multimesh.mesh, materials)
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not mesh_instance.visible:
			continue
		triangles += _mesh_triangles(mesh_instance.mesh)
		batches += mesh_instance.mesh.get_surface_count()
		_collect_materials(mesh_instance.mesh, materials)
	print("  presupuesto: ~%d triángulos · ~%d lotes de dibujo · %d materiales distintos"
			% [triangles, batches, materials.size()])


func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
				else PackedInt32Array()
		if not indices.is_empty():
			total += indices.size() / 3
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += vertices.size() / 3
	return total


func _collect_materials(mesh: Mesh, out: Dictionary) -> void:
	for surface: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material == null:
			continue
		out[material.get_instance_id()] = true


func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

func _scenes(paths: Array) -> Array[PackedScene]:
	var found: Array[PackedScene] = []
	for path: String in paths:
		var scene := _scene(path)
		if scene != null:
			found.append(scene)
	return found


func _scene(path: String) -> PackedScene:
	return _load(path, "PackedScene") as PackedScene


func _rocks() -> Array[PackedScene]:
	var found: Array[PackedScene] = []
	for id: String in ["a", "b", "c", "d", "e", "f"]:
		var scene := _load("res://world/rocks/rock_%s.tscn" % id, "PackedScene") as PackedScene
		if scene != null:
			found.append(scene)
	return found


func _load(path: String, hint: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_error("build_town: falta '%s'." % path)
		return null
	return ResourceLoader.load(path, hint)


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("build_town: no se pudo crear '%s': %s" % [path, error_string(err)])


func _size_kb(path: String) -> float:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0.0
	var size := float(file.get_length()) / 1024.0
	file.close()
	return size
