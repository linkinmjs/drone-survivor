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
const LAWN_PATH: String = "res://assets/city/materials/plaza_lawn.tres"
const CREEK_WATER_PATH: String = "res://assets/city/materials/creek_water.tres"
const CREEK_WATER_SHADER: String = "res://city/creek_water.gdshader"

## Los nueve parámetros del agua del arroyo. Ver [method _ensure_creek_material].
const CREEK_WATER_PARAMS: Dictionary[String, Variant] = {
	"water_color": Color(0.043, 0.078, 0.082),
	"sky_tint": Color(0.180, 0.235, 0.330),
	"fresnel_power": 3.0,
	"fresnel_strength": 0.55,
	"water_roughness": 0.15,
	"water_alpha": 0.85,
	"wave_scale": 0.65,
	"wave_speed": 0.35,
	"wave_amplitude": 0.06,
}
const WALKWAY_PATH: String = "res://assets/city/materials/walkway.tres"

## Albedo de la vereda. Ver [method _ensure_walkway_material].
const WALKWAY_ALBEDO: Color = Color(1.0, 0.97, 0.9, 1.0)
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
	# **Sin props de azotea de ciudad** (WP-D4a, hallazgo 11). `sign_b`, `sign_c`
	# y `dish` son las piezas de la ciudad de P2: carteles de neón con emisión
	# magenta y una antena parabólica. Sobre la torre de un distrito cuentan lo
	# que tienen que contar; sobre el galpón de un pueblo de ruta al anochecer
	# contradicen la gramática de `docs/17` §4 —«el material dice qué hace la
	# cosa»— y su magenta compite con el cian del jefe y con el ámbar de las
	# ventanas (`docs/13` §1). `props.tres` no se toca: se sigue usando fuera del
	# pueblo.
	# Tipado explícito: `grid` es `Variant` (ver el encabezado) y un `[]` pelado
	# llega como `Array` sin tipo, que `Array[PackedScene]` rechaza.
	var no_roof_props: Array[PackedScene] = []
	grid.prop_pieces = no_roof_props
	grid.rock_scenes = _rocks()
	grid.road_piece = _scene("res://city/pieces/road_chunk.tscn")
	grid.ground_material = _ensure_field_material()
	grid.lawn_material = _ensure_lawn_material()
	grid.water_material = _ensure_creek_material()
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
	_stabilise_ids(TOWN_PATH)
	var size := _size_kb(TOWN_PATH)
	print("build_town: %s guardado (%.1f KB de %.0f)." % [TOWN_PATH, size, TSCN_BUDGET_KB])
	if size > TSCN_BUDGET_KB:
		push_error("build_town: '%s' pesa %.1f KB y el tope es %.0f KB: hay geometría"
				% [TOWN_PATH, size, TSCN_BUDGET_KB] + " incrustada que tendría que ser externa.")
		quit(1)
		return
	quit(0)


# --------------------------------------------------------------------------
# Identificadores estables del `.tscn`
# --------------------------------------------------------------------------

## Testigo con el que se renombra en dos pasadas. No puede aparecer en un
## `.tscn`: ver [method _stabilise_ids].
const ID_TOKEN: String = "@@wpd4a@@"


## Reescribe los identificadores **aleatorios** que `ResourceSaver` le pone al
## `.tscn` por otros derivados del contenido.
##
## ## El problema
##
## Godot sortea tres cosas al guardar una escena de texto: el sufijo de cada
## `id="12_l0lbw"` de `ext_resource`, el de cada `id="BoxShape3D_nclj1"` de
## `sub_resource` y el entero `unique_id=1505653870` de cada nodo. Los tres son
## arbitrarios y distintos en cada corrida, así que dos horneados del **mismo**
## pueblo daban dos archivos distintos: 4 796 líneas de `diff` de puro ruido
## sobre un pueblo idéntico. Eso rompe lo único que hace editable un diseño
## escrito a mano —que el `diff` del horneado diga qué cambió— y obliga a leer
## la firma del plano para saber si algo se movió de verdad.
##
## ## La regla
##
## Cada identificador sale de **lo que nombra**, con el mismo splitmix64 que usa
## todo el determinismo posicional del pueblo ([method TownPlan.mix]):
##
## - un `ext_resource` toma su orden de aparición y un token de cinco caracteres
##   derivado de su `path`;
## - un `sub_resource` toma su tipo y un token derivado de `(orden, tipo)`,
##   porque un `BoxShape3D` no tiene ruta con la que distinguirse de otro;
## - un nodo toma su `NodePath` entero —`Buildings/Building_House_07_02`—, que
##   es exactamente lo que `unique_id` identifica.
##
## El renombrado va en dos pasadas con un token intermedio para que un
## identificador nuevo no pueda pisar a uno viejo que todavía no se reemplazó.
##
## Resultado: `md5(town_a.tscn)` igual en dos horneados seguidos (WP-D4a,
## hallazgo 4).
func _stabilise_ids(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("build_town: no se pudo releer '%s' para estabilizar los ids" % path)
		return
	var text := file.get_as_text()
	file.close()

	var ext := RegEx.create_from_string(
			r'\[ext_resource [^\]]*path="([^"]+)"[^\]]*id="([^"]+)"')
	var sub := RegEx.create_from_string(r'\[sub_resource type="([^"]+)" id="([^"]+)"')

	var wanted: Array[String] = []
	var renames: Dictionary[String, String] = {}
	var order := 0
	for hit: RegExMatch in ext.search_all(text):
		order += 1
		renames[hit.get_string(2)] = "%d_%s" % [order, _id_token(hit.get_string(1))]
		wanted.append(hit.get_string(2))
	order = 0
	for hit: RegExMatch in sub.search_all(text):
		order += 1
		var kind := hit.get_string(1)
		renames[hit.get_string(2)] = "%s_%s" % [kind, _id_token("%d|%s" % [order, kind])]
		wanted.append(hit.get_string(2))

	# Pasada 1: al testigo intermedio. Pasada 2: al identificador definitivo. Con
	# una sola pasada, un identificador nuevo podria pisar a uno viejo que
	# todavia no se reemplazo.
	for slot: int in wanted.size():
		text = text.replace('"%s"' % wanted[slot], '"%s%d%s"' % [ID_TOKEN, slot, ID_TOKEN])
	for slot: int in wanted.size():
		text = text.replace('"%s%d%s"' % [ID_TOKEN, slot, ID_TOKEN],
				'"%s"' % renames[wanted[slot]])

	var stamp := RegEx.create_from_string(" unique_id=-?[0-9]+")
	var lines := text.split("\n")
	var taken: Dictionary[int, bool] = {}
	var nodes := 0
	for index: int in lines.size():
		var line := lines[index]
		if not line.begins_with("[node ") or not line.contains(" unique_id="):
			continue
		var node_path := _node_path_of(line)
		if node_path.is_empty():
			continue
		nodes += 1
		var key := _unique_id_for(node_path, taken)
		taken[key] = true
		lines[index] = stamp.sub(line, " unique_id=%d" % key)
	text = "\n".join(lines)

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("build_town: no se pudo reescribir '%s'" % path)
		return
	out.store_string(text)
	out.close()
	print("  ids estables: %d recursos y %d nodos" % [wanted.size(), nodes])


## Token de cinco caracteres en base 36 derivado de [param key].
func _id_token(key: String) -> String:
	var plan: Variant = load("res://city/town_plan.gd")
	var value: int = absi(plan.mix(key.hash()))
	var digits := "0123456789abcdefghijklmnopqrstuvwxyz"
	var token := ""
	for _slot: int in 5:
		token += digits[value % 36]
		value /= 36
	return token


## El `NodePath` que la línea `[node …]` declara, o `""` si no se puede leer.
func _node_path_of(line: String) -> String:
	var name_hit := RegEx.create_from_string(r'name="([^"]+)"').search(line)
	if name_hit == null:
		return ""
	var parent_hit := RegEx.create_from_string(r'parent="([^"]*)"').search(line)
	if parent_hit == null:
		return "."
	var parent := parent_hit.get_string(1)
	if parent == "." or parent.is_empty():
		return name_hit.get_string(1)
	return "%s/%s" % [parent, name_hit.get_string(1)]


## `unique_id` estable de [param node_path], evitando los ya usados.
func _unique_id_for(node_path: String, taken: Dictionary[int, bool]) -> int:
	var plan: Variant = load("res://city/town_plan.gd")
	var salt := 0
	while salt < 64:
		var key: int = absi(plan.mix(("%s#%d" % [node_path, salt]).hash())) % 2147483647
		if key > 0 and not taken.has(key):
			return key
		salt += 1
	push_error("build_town: no se pudo asignar un unique_id estable a '%s'" % node_path)
	return 1


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
	_merge_manifest(table)
	return table


## Suma a la tabla las piezas del **manifiesto** de WP-D1.
##
## [constant PIECE_PATHS] queda como lo que era: las trece piezas de P2b, con su
## ruta escrita a mano. Todo lo que WP-D1 hornea —los cinco edificios nuevos, los
## dieciséis props, el tablero del puente, el alambrado y las once piezas de
## follaje— entra por el manifiesto, que es el archivo que ese encargo ya escribe
## para decir qué produjo. Mantener a mano cincuenta y cuatro rutas en dos
## archivos habría sido pedir que se desincronizaran.
##
## La tabla escrita a mano **gana**: si alguna vez el manifiesto declarara una
## casa que ya está acá, la de acá es la que el pueblo viene usando.
func _merge_manifest(table: Dictionary) -> void:
	var design: Variant = load("res://city/town_design.gd")
	var manifest: Dictionary = design.manifest()
	if manifest.is_empty():
		print("  manifiesto de WP-D1 ausente: las piezas nuevas no se siembran.")
		return
	var added := 0
	var absent: Array[String] = []
	for key: Variant in manifest:
		var id := StringName(String(key))
		if table.has(id):
			continue
		var path := String((manifest[key] as Dictionary).get("scene", ""))
		if path.is_empty():
			continue
		if not ResourceLoader.exists(path):
			absent.append("%s (%s)" % [id, path])
			continue
		table[id] = _scene(path)
		added += 1
	print("  manifiesto de WP-D1: %d piezas sumadas a la tabla%s"
			% [added, "" if absent.is_empty()
			else ", %d declaradas y ausentes: %s" % [absent.size(), ", ".join(absent)]])
	_missing.append_array(absent)


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


## Carga el material del agua del arroyo o lo crea.
##
## Es el **único** material transparente del pueblo (`docs/13` §4) y el único con
## shader propio fuera del terreno. Se regenera en cada corrida —a diferencia del
## campo y del cantero, que se respetan si ya existen— porque no tiene ningún
## valor de autor que se pueda perder: los nueve parámetros son los de WP-D3 y
## viven acá.
##
## ## Los valores van escritos, no en blanco
##
## Hasta WP-D4a el material se guardaba sin tocar un solo `shader_parameter`, así
## que el `.tres` comiteado decía `shader_parameter/water_roughness = null` nueve
## veces: el agua se veía bien porque el motor caía en los valores por omisión
## del `.gdshader`, pero el recurso no decía qué agua es. Un cambio de un
## `= 0.15` del shader habría cambiado el arroyo sin que ningún `diff` lo
## mostrara, y nadie podía leer del recurso con qué rugosidad y con qué alfa se
## aprobaron las capturas de WP-D3. Ahora se escriben los nueve (hallazgo 18) y
## son los mismos números que el shader trae por omisión: rugosidad 0,15 —agua
## quieta de arroyo, no un espejo—, alfa 0,85, Fresnel 3,0 a 0,55 y olas de
## 0,06 m a 0,35 de velocidad sobre una escala de 0,65 m.
func _ensure_creek_material() -> Resource:
	var shader: Variant = _load(CREEK_WATER_SHADER, "Shader")
	if shader == null:
		push_error("build_town: no se pudo cargar '%s'" % CREEK_WATER_SHADER)
		return null
	var material := ShaderMaterial.new()
	material.resource_name = "creek_water"
	material.shader = shader
	for name: String in CREEK_WATER_PARAMS:
		material.set_shader_parameter(name, CREEK_WATER_PARAMS[name])
	var err := ResourceSaver.save(material, CREEK_WATER_PATH)
	if err != OK:
		push_error("build_town: no se pudo guardar '%s': %s"
				% [CREEK_WATER_PATH, error_string(err)])
		return material
	print("  material creado: %s" % CREEK_WATER_PATH)
	return _load(CREEK_WATER_PATH, "Material")


## Carga el material del cantero de la plaza o lo crea.
##
## El cantero central de la plaza se pintaba con el material del **campo**
## (`field.tres`), y el campo es pasto seco de anochecer: rodeado por la losa de
## vereda —que es el material más claro del pueblo— se leía como un pozo negro
## en el medio de la plaza y no como pasto. Medido en el encuadre `plaza_60` de
## WP-D2: luminancia media del cantero 0,134 contra 0,301 de la losa, o sea
## **0,45×**, cuando el criterio de WP-D3 son 0,70×.
##
## El cantero es la única superficie **regada** del pueblo y puede permitírselo:
## es un verde de parque, más claro y algo más frío que el pasto del campo, pero
## todavía apagado —no el verde de juguete que WP-D3 le sacó al follaje—. El
## degradado va de tierra del cantero a pasto regado y la escala del triplanar
## es cinco veces más corta que la del campo, porque un cantero mide treinta
## metros y no mil doscientos: con la escala del campo el cantero entero caía
## dentro de una sola mancha de ruido y quedaba de un color plano.
##
## ## El escalón de WP-D3b
##
## WP-D3 midió el cantero con un parche de 8 × 8 m proyectado sobre el centroide
## de la plaza, que es **justo** donde están el monumento y el mástil: el parche
## medía sobre todo el monumento y su sombra. Con la máscara por diferencia de
## `tools/out/wpd3/art_probe.gd` —apagar el `Plaza/Lawn` y quedarse con los
## píxeles que cambian— el cantero daba 0,1781 contra 0,3199 de la losa, o sea
## **0,557×**, todavía lejos de los 0,70× del criterio. Los tres colores de la
## rampa suben un 28 % en sRGB —un primer escalón del 20 % dejó el cantero en
## 0,672× y hubo que rematarlo con otro 7 %— y lo dejan en 0,73×. Se sube el
## degradado entero y no sólo su extremo claro: subir el claro le habría metido
## contraste al cantero, y lo que le falta es valor, no moteado.
##
## Este material **no se pisa** si ya existe, así que estos tres colores y los de
## `assets/city/materials/plaza_lawn.tres` tienen que decir lo mismo.
func _ensure_lawn_material() -> Resource:
	if ResourceLoader.exists(LAWN_PATH):
		return _load(LAWN_PATH, "Material")

	var noise := FastNoiseLite.new()
	noise.seed = 20260923
	noise.frequency = 0.02
	noise.fractal_octaves = 4

	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.238, 0.263, 0.148, 1.0))
	ramp.set_color(1, Color(0.437, 0.507, 0.276, 1.0))
	ramp.add_point(0.55, Color(0.327, 0.385, 0.205, 1.0))

	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	texture.seamless = true
	texture.color_ramp = ramp

	var material := StandardMaterial3D.new()
	material.resource_name = "town_plaza_lawn"
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.albedo_texture = texture
	material.roughness = 0.96
	material.metallic_specular = 0.10
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.06, 0.06, 0.06)

	var err := ResourceSaver.save(material, LAWN_PATH)
	if err != OK:
		push_error("build_town: no se pudo guardar '%s': %s" % [LAWN_PATH, error_string(err)])
		return material
	print("  material creado: %s" % LAWN_PATH)
	return _load(LAWN_PATH, "Material")


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
	# **Albedo ≤ 1** (WP-D4a, hallazgo 30). (1,34; 1,27; 1,14) no es un color:
	# es un multiplicador por encima de uno sobre la misma textura que pinta la
	# calzada, y empujaba la vereda fuera del rango sRGB hacia un salmón que no
	# está en la paleta de `docs/13`.
	#
	# Lo que cuesta: la vereda y la calzada muestrean **el mismo** parche de
	# `t_roads_diffuse.png` y la calzada va con albedo (1, 1, 1), así que el
	# multiplicador era el único contraste que había. Medido en `street_4` con la
	# sonda de WP-D4a: con 1,34 la vereda daba 0,3494 de luminancia contra 0,2692
	# de la calzada (1,30×); con el albedo al máximo que el rango permite da
	# 0,2617 (0,97×). Por encima de uno no se va, así que el contraste lo llevan
	# ahora el **cordón** de 15 cm —la línea dura que mide `city_check`— y el
	# **tono**: (1; 0,97; 0,90) deja la vereda en un marfil neutro a 288° de
	# matiz y 0,17 de saturación contra el lila de la calzada a 250° y 0,24.
	# Recuperar contraste de valor pide un parche más claro del atlas o una
	# textura propia de vereda: es trabajo de arte y queda anotado.
	walkway.albedo_color = WALKWAY_ALBEDO
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
	_report_town_decor(grid, plan)
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


## Plaza, puente, arboledas, cercos y props (WP-D2), y las piezas que faltaron.
##
## El conteo de piezas ausentes es el número que dice si el pueblo se horneó
## entero o con huecos: mientras WP-D1 no entregue una pieza, el plano la
## declara y el constructor la omite, y lo único que separa «todavía no está» de
## «se rompió» es esta línea.
func _report_town_decor(grid: Variant, plan: Variant) -> void:
	if plan.has_plaza():
		print("  plaza: manzana %d · %.0f m² · %d props propios"
				% [plan.plaza_block, plan.polygon_area(plan.plaza_polygon),
				plan.prop_placements.size()])
	if plan.has_bridge():
		print("  puente: %s · vano %.0f m · tablero %.0f m · rumbo %.1f° · pieza '%s'"
				% [str(plan.bridge_at.round()), plan.bridge_span, plan.bridge_deck_width,
				rad_to_deg(plan.bridge_yaw), plan.bridge_piece])
	var lines: Array[String] = []
	for index: int in plan.grove_species.size():
		lines.append("%s %d" % [plan.grove_species[index], plan.grove_count(index)])
	print("  arboledas: %d instancias en %d especies (%s)"
			% [plan.grove_total(), plan.grove_species.size(), ", ".join(lines)])
	print("  cercos: %d tramos (%.0f m de alambre, %.0f m de tabla)"
			% [plan.fence_points.size(), plan.fence_length_of(0), plan.fence_length_of(1)])
	var groups: Array[String] = []
	for name: String in ["Plaza", "Groves", "Fences", "Props", "Bridge"]:
		var node: Node = grid.get_node_or_null(NodePath(name))
		groups.append("%s %d" % [name, 0 if node == null else node.get_child_count()])
	print("  props: %d instancias en %d piezas · nodos: %s"
			% [plan.prop_placements.size(), plan.prop_pieces_used().size(),
			" · ".join(groups)])
	var missing: Dictionary = grid.missing_pieces()
	if missing.is_empty():
		print("  piezas: 0 ausentes (el manifiesto de WP-D1 cubre todo lo que el diseño nombra)")
		return
	var rows: Array[String] = []
	for id: Variant in missing:
		rows.append("%s ×%d" % [id, int(missing[id])])
	print("  AVISOS: %d piezas ausentes, %d instancias sin sembrar: %s"
			% [missing.size(), _sum(missing), ", ".join(rows)])


func _sum(counts: Dictionary) -> int:
	var total := 0
	for key: Variant in counts:
		total += int(counts[key])
	return total


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
