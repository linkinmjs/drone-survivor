## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Genera las mallas y materiales **propios** de WP-20 (`docs/10` §3.2, §4.4 y
## riesgo 4): el pack FreeSample no trae variantes dañadas, ni pilas de ruina, ni
## rocas, así que se hornean acá una sola vez y se comitean como recursos.
##
## Produce:
##
## - `assets/city/materials/rubble.tres` — hormigón roto, para pilas y escombros.
## - `assets/city/materials/rock.tres` — roca gris triplanar con normal de ruido.
## - `assets/city/rubble/rubble_pile_{low,mid,high}.res` — tres montículos
##   normalizados a una huella de 1 × 1 m con la base en `y = 0`, para que
##   [Building] los escale a la huella real del edificio.
## - `assets/city/rubble/debris_concrete_{small,large}.res` y sus
##   `BoxShape3D` — los dos únicos trozos que la ciudad registra en el
##   [RubbleField] (`docs/10` §6 reserva 2 campos para la ciudad y 2 para los
##   enemigos).
## - `world/rocks/rock_{a..f}.res` y `rock_{a..f}.tscn` — seis rocas de 18 a 40 m
##   con `ConvexPolygonShape3D` en la capa 1 y en el grupo `city_rocks`.
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_city_meshes.gd
## [/codeblock]
extends SceneTree

const RUBBLE_DIR: String = "res://assets/city/rubble"
const MATERIAL_DIR: String = "res://assets/city/materials"
const ROCK_DIR: String = "res://world/rocks"

## Semilla fija: dos corridas producen exactamente las mismas mallas.
const MESH_SEED: int = 20260920

## Altura de las seis rocas, en metros (`docs/10` §4.4: 18–40 m).
const ROCK_HEIGHTS: Array[float] = [18.0, 23.0, 28.0, 32.0, 36.0, 40.0]

## Letras de las seis rocas.
const ROCK_IDS: Array[String] = ["a", "b", "c", "d", "e", "f"]

## Capa 1 `world` con máscara 2·3·6·9 (`docs/10` §9.4).
const ROCK_LAYER: int = 1
const ROCK_MASK: int = 294

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = MESH_SEED
	_ensure_dir(RUBBLE_DIR)
	_ensure_dir(ROCK_DIR)

	# Los materiales se guardan **antes** y se recargan desde disco: así quedan
	# con `resource_path` y las mallas los referencian como recurso externo en
	# vez de incrustar una copia propia cada una (una copia por malla serían
	# cinco materiales distintos y, por lo tanto, cinco lotes de dibujo).
	var rubble_path := "%s/rubble.tres" % MATERIAL_DIR
	_save(_build_rubble_material(), rubble_path)
	var rubble_material := ResourceLoader.load(rubble_path, "StandardMaterial3D",
			ResourceLoader.CACHE_MODE_REPLACE) as StandardMaterial3D
	var rock_path := "%s/rock.tres" % MATERIAL_DIR
	_save(_build_rock_material(), rock_path)
	var rock_material := ResourceLoader.load(rock_path, "StandardMaterial3D",
			ResourceLoader.CACHE_MODE_REPLACE) as StandardMaterial3D

	_save(_build_ground_material(), "%s/ground.tres" % MATERIAL_DIR)

	_build_piles(rubble_material)
	_build_debris(rubble_material)
	_build_rocks(rock_material)
	_build_vfx()

	print("build_city_meshes: listo.")
	quit(0)


# --------------------------------------------------------------------------
# Materiales
# --------------------------------------------------------------------------

## Hormigón roto: gris sucio, mate, con manchas por ruido triplanar. Sin
## emisivo, porque una ruina no tiene ventanas encendidas.
func _build_rubble_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "city_rubble"
	material.albedo_color = Color(0.41, 0.40, 0.38, 1.0)
	material.roughness = 0.95
	material.metallic_specular = 0.2
	material.albedo_texture = _noise_texture(512, 6.0, false)
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.12, 0.12, 0.12)
	return material


## Roca: gris fría, triplanar, con una normal de ruido suave para que las caras
## planas del horneado no se lean como cristal.
func _build_rock_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "city_rock"
	material.albedo_color = Color(0.36, 0.37, 0.40, 1.0)
	material.roughness = 1.0
	material.metallic_specular = 0.15
	material.albedo_texture = _noise_texture(512, 4.0, false)
	material.normal_enabled = true
	material.normal_scale = 0.45
	material.normal_texture = _noise_texture(512, 12.0, true)
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.05, 0.05, 0.05)
	return material


## Textura de ruido procedural. Se guarda dentro del `.tres` del material: no
## añade un PNG al repositorio ni entra en el presupuesto de VRAM de `docs/10`
## §2.3, que cuenta sólo las ocho texturas del pack.
func _noise_texture(size: int, frequency: float, as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = _rng.randi()
	noise.frequency = frequency / float(size)
	noise.fractal_octaves = 4

	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = size
	texture.height = size
	texture.seamless = true
	texture.as_normal_map = as_normal
	texture.bump_strength = 4.0
	return texture


## Suelo del descampado: asfalto oscuro triplanar. El `PlaneMesh` de 1 200 m
## tiene cuatro vértices, así que la variación sólo puede venir del triplanar,
## que trabaja sobre la posición de mundo y no sobre la UV.
func _build_ground_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "city_ground"
	material.albedo_color = Color(0.17, 0.17, 0.18, 1.0)
	material.roughness = 0.97
	material.metallic_specular = 0.18
	material.albedo_texture = _noise_texture(512, 5.0, false)
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.03, 0.03, 0.03)
	return material


# --------------------------------------------------------------------------
# Polvo y humo
# --------------------------------------------------------------------------

## Recursos compartidos de los dos emisores de cada edificio. Son **compartidos
## a propósito**: sesenta copias de un `ParticleProcessMaterial` en
## `district_a.tscn` serían sesenta lotes distintos y un archivo enorme.
func _build_vfx() -> void:
	_save(_particle_quad(Color(0.62, 0.58, 0.52, 1.0), 7.0), "%s/dust_quad.tres" % RUBBLE_DIR)
	_save(_particle_quad(Color(0.20, 0.195, 0.20, 1.0), 20.0), "%s/smoke_quad.tres" % RUBBLE_DIR)
	_save(_dust_process(), "%s/dust_process.tres" % RUBBLE_DIR)
	_save(_smoke_process(), "%s/smoke_process.tres" % RUBBLE_DIR)


## Cuadrilátero de partícula con un degradado radial por textura: sin él la
## partícula se vería como un cuadrado duro.
func _particle_quad(tint: Color, size: float) -> QuadMesh:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 0.62))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = tint
	material.albedo_texture = texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.particles_anim_h_frames = 1
	material.particles_anim_v_frames = 1
	material.particles_anim_loop = false
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	return quad


## Estallido de polvo del derrumbe: sale hacia arriba y hacia afuera y se abre.
func _dust_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.resource_name = "city_dust"
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 7.0
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 62.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 15.0
	process.gravity = Vector3(0.0, -2.2, 0.0)
	process.damping_min = 1.5
	process.damping_max = 3.5
	process.scale_min = 1.4
	process.scale_max = 3.4
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color = Color(0.68, 0.64, 0.58, 0.85)
	process.alpha_curve = _fade_curve()
	process.scale_curve = _grow_curve()
	return process


## Columna de humo de la ruina: lenta, ancha y con flotabilidad positiva.
func _smoke_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.resource_name = "city_smoke"
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(7.0, 1.5, 7.0)
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 16.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.35, 1.1, 0.0)
	process.scale_min = 1.0
	process.scale_max = 2.6
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -12.0
	process.angular_velocity_max = 12.0
	process.color = Color(0.24, 0.235, 0.24, 0.85)
	process.alpha_curve = _fade_curve()
	process.scale_curve = _grow_curve()
	return process


## Curva de alfa: entra rápido y se va lento.
func _fade_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.14, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## Curva de escala: la nube crece mientras vive.
func _grow_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


# --------------------------------------------------------------------------
# Pilas de ruina
# --------------------------------------------------------------------------

## Tres montículos de cascotes, cada uno normalizado a una caja de 1 × 1 × 1 m
## con la base en `y = 0`. [Building] los escala a `base_size.x × altura × base_size.z`.
func _build_piles(material: StandardMaterial3D) -> void:
	var recipes: Array[Dictionary] = [
		{"name": "low", "chunks": 22, "flatness": 0.55},
		{"name": "mid", "chunks": 30, "flatness": 0.70},
		{"name": "high", "chunks": 38, "flatness": 0.85},
	]
	for recipe: Dictionary in recipes:
		var tool_mesh := SurfaceTool.new()
		tool_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		var chunks: int = recipe["chunks"]
		var flatness: float = recipe["flatness"]
		for index: int in chunks:
			# Radio creciente hacia afuera y altura decreciente: un cono de
			# cascotes, no una pila uniforme.
			var t := float(index) / float(chunks - 1)
			var radius := 0.10 + 0.40 * sqrt(t)
			var angle := _rng.randf() * TAU
			var centre := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var block := Vector3(
					_rng.randf_range(0.10, 0.26),
					_rng.randf_range(0.06, 0.22) * flatness * (1.0 - 0.55 * t),
					_rng.randf_range(0.10, 0.26))
			centre.y = block.y * 0.5 * _rng.randf_range(0.45, 1.0)
			var basis := Basis.from_euler(Vector3(
					_rng.randf_range(-0.22, 0.22),
					_rng.randf() * TAU,
					_rng.randf_range(-0.22, 0.22)))
			_add_box(tool_mesh, Transform3D(basis, centre), block)
		_finish_pile(tool_mesh, material, "%s/rubble_pile_%s.res" % [RUBBLE_DIR, recipe["name"]])


## Cierra un montículo: normales planas, tangentes, recorte por debajo de `y = 0`
## y normalización a la caja unitaria.
func _finish_pile(tool_mesh: SurfaceTool, material: StandardMaterial3D, path: String) -> void:
	tool_mesh.generate_normals()
	tool_mesh.generate_tangents()
	var mesh := tool_mesh.commit()
	var normalized := _normalize_mesh(mesh, Vector3.ONE, true)
	normalized.surface_set_material(0, material)
	normalized.resource_name = path.get_file().get_basename()
	_save(normalized, path)


# --------------------------------------------------------------------------
# Escombros
# --------------------------------------------------------------------------

## Los dos trozos de hormigón de la ciudad. Son losas del tamaño de un piso:
## 3.4 m el bloque bajo y 6.4 m la torre (`docs/10` §3.2 pide «cajas del tamaño
## de un piso del edificio»).
func _build_debris(material: StandardMaterial3D) -> void:
	var recipes: Array[Dictionary] = [
		{"name": "small", "size": Vector3(3.4, 1.3, 2.6)},
		{"name": "large", "size": Vector3(6.4, 2.1, 4.8)},
	]
	for recipe: Dictionary in recipes:
		var size: Vector3 = recipe["size"]
		var tool_mesh := SurfaceTool.new()
		tool_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Losa principal más dos esquirlas pegadas: la silueta no es una caja
		# perfecta y se distingue de los cubos de depuración.
		_add_box(tool_mesh, Transform3D.IDENTITY, size)
		_add_box(tool_mesh, Transform3D(Basis.from_euler(Vector3(0.0, 0.5, 0.35)),
				Vector3(size.x * 0.38, size.y * 0.42, -size.z * 0.28)), size * 0.42)
		_add_box(tool_mesh, Transform3D(Basis.from_euler(Vector3(0.28, -0.7, 0.0)),
				Vector3(-size.x * 0.34, -size.y * 0.30, size.z * 0.30)), size * 0.34)
		tool_mesh.generate_normals()
		tool_mesh.generate_tangents()
		# Centrado en el origen: el `RigidBody3D` del [DebrisChunk] gira en torno
		# a su centro de masa y una malla descentrada se vería bambolear.
		var mesh := _normalize_mesh(tool_mesh.commit(), size * 1.22, false)
		mesh.surface_set_material(0, material)
		mesh.resource_name = "debris_concrete_%s" % recipe["name"]
		_save(mesh, "%s/debris_concrete_%s.res" % [RUBBLE_DIR, recipe["name"]])

		var shape := BoxShape3D.new()
		shape.size = mesh.get_aabb().size
		shape.resource_name = "debris_concrete_%s_shape" % recipe["name"]
		_save(shape, "%s/debris_concrete_%s_shape.tres" % [RUBBLE_DIR, recipe["name"]])


# --------------------------------------------------------------------------
# Rocas
# --------------------------------------------------------------------------

## Seis rocas escalables: esfera de baja resolución desplazada por ruido, con la
## base recortada para que apoye en el suelo. Cada una sale a `.res` y a una
## escena `StaticBody3D` de capa 1 con casco convexo, en el grupo `city_rocks`.
func _build_rocks(material: StandardMaterial3D) -> void:
	for index: int in ROCK_IDS.size():
		var rock_id := ROCK_IDS[index]
		var height := ROCK_HEIGHTS[index]
		# Las colinas bajas son más anchas que altas; las agujas, al revés.
		var width := height * _rng.randf_range(0.70, 1.10)
		var depth := height * _rng.randf_range(0.70, 1.10)
		var mesh := _build_rock_mesh(Vector3(width, height, depth))
		mesh.surface_set_material(0, material)
		mesh.resource_name = "rock_%s" % rock_id
		var mesh_path := "%s/rock_%s.res" % [ROCK_DIR, rock_id]
		_save(mesh, mesh_path)
		_save_rock_scene(rock_id, ResourceLoader.load(mesh_path, "Mesh") as Mesh)


## Malla de una roca de tamaño [param size], con la base en `y = 0`.
func _build_rock_mesh(size: Vector3) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 13
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	# Desplazamiento por ruido de valor sobre la dirección del vértice: sirve
	# para todos los vértices coincidentes por igual, así no se abren costuras.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = _rng.randi()
	noise.frequency = 1.4
	noise.fractal_octaves = 3

	var displaced := PackedVector3Array()
	displaced.resize(vertices.size())
	for i: int in vertices.size():
		var v := vertices[i]
		var dir := v.normalized()
		var amount := 1.0 + 0.34 * noise.get_noise_3dv(dir * 3.0)
		displaced[i] = dir * 0.5 * amount

	var tool_mesh := SurfaceTool.new()
	tool_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in indices.size():
		var v := displaced[indices[i]]
		# Base plana: lo que quedaría enterrado se aplasta contra el suelo.
		v.y = maxf(v.y, -0.34)
		tool_mesh.set_uv(Vector2(v.x, v.z))
		tool_mesh.add_vertex(v)
	tool_mesh.generate_normals()
	tool_mesh.generate_tangents()
	return _normalize_mesh(tool_mesh.commit(), size, true)


## Escena de una roca: `StaticBody3D` capa 1 / máscara 294 con casco convexo,
## malla sin GI dinámica y alta en el grupo `city_rocks`.
func _save_rock_scene(rock_id: String, mesh: Mesh) -> void:
	var body := StaticBody3D.new()
	body.name = "rock_%s" % rock_id
	body.collision_layer = ROCK_LAYER
	body.collision_mask = ROCK_MASK
	body.add_to_group(&"city_rocks", true)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)
	mesh_instance.owner = body

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Shape"
	shape_node.shape = mesh.create_convex_shape(true, true)
	body.add_child(shape_node)
	shape_node.owner = body

	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		push_error("build_city_meshes: no se pudo empaquetar 'rock_%s': %s" % [rock_id, error_string(err)])
		body.free()
		return
	_save(packed, "%s/rock_%s.tscn" % [ROCK_DIR, rock_id])
	body.free()


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Añade una caja de [param size] transformada por [param xform] al constructor.
## Sin índices: [method SurfaceTool.generate_normals] deja normales planas, que
## es el aspecto facetado que buscan las ruinas y las rocas.
func _add_box(tool_mesh: SurfaceTool, xform: Transform3D, size: Vector3) -> void:
	var half := size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z),
		Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z),
		Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z),
	]
	var faces: Array[PackedInt32Array] = [
		PackedInt32Array([4, 5, 6, 7]),  # +Y
		PackedInt32Array([1, 0, 3, 2]),  # −Y
		PackedInt32Array([7, 6, 2, 3]),  # +Z
		PackedInt32Array([5, 4, 0, 1]),  # −Z
		PackedInt32Array([6, 5, 1, 2]),  # +X
		PackedInt32Array([4, 7, 3, 0]),  # −X
	]
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for face: PackedInt32Array in faces:
		for triangle: PackedInt32Array in [PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3])]:
			for corner: int in triangle:
				tool_mesh.set_uv(uvs[corner])
				tool_mesh.add_vertex(xform * corners[face[corner]])


## Reescala y recentra una malla para que su AABB mida [param size], quede
## centrada en XZ y, si [param base_at_zero], apoye en `y = 0`.
func _normalize_mesh(mesh: ArrayMesh, size: Vector3, base_at_zero: bool) -> ArrayMesh:
	var bounds := mesh.get_aabb()
	var factor := Vector3(
			size.x / maxf(bounds.size.x, 0.0001),
			size.y / maxf(bounds.size.y, 0.0001),
			size.z / maxf(bounds.size.z, 0.0001))
	var centre := bounds.get_center()

	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(vertices.size())
	for i: int in vertices.size():
		var v := (vertices[i] - centre) * factor
		moved[i] = v
	if base_at_zero:
		var lowest := INF
		for v: Vector3 in moved:
			lowest = minf(lowest, v.y)
		for i: int in moved.size():
			moved[i] = moved[i] - Vector3(0.0, lowest, 0.0)
	arrays[Mesh.ARRAY_VERTEX] = moved

	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("build_city_meshes: no se pudo crear '%s': %s" % [path, error_string(err)])


func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("build_city_meshes: no se pudo guardar '%s': %s" % [path, error_string(err)])
		return
	print("  guardado %s" % path)
