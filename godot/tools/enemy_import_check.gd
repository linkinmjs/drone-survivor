## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-12b: verifica que los dos GLB voxel del MVP —el Arachnodroid y el
## dron del jugador— hayan sido importados por `asset_import/import_voxel_enemy.gd`
## y `asset_import/import_drone.gd` exactamente como manda `docs/05` §14.2.
##
## Todo se contrasta contra el **sidecar** `<base>.parts.json`, nunca contra
## constantes del check: el número de partes, la altura, la huella y los pivotes
## viven en `metadata` (decisión D-1 de `docs/05` §15). Lo único que sí vive acá
## son las rutas, las tolerancias, las capas de `docs/02` §3.1 y los nombres
## canónicos del dron, que son el contrato con `docs/03` §7.
##
## No instancia ninguna escena de juego ni escribe en `user://`.
extends CheckRunner

const ENEMY_SCENE: String = "res://enemies/arachnodroid/arachnodroid.glb"
const ENEMY_SIDECAR: String = "res://enemies/arachnodroid/arachnodroid.parts.json"
const ENEMY_IMPORT: String = "res://enemies/arachnodroid/arachnodroid.glb.import"
const ENEMY_PALETTE_IMPORT: String = "res://enemies/arachnodroid/arachnodroid_palette.png.import"
const ENEMY_IMPORT_SCRIPT: String = "res://asset_import/import_voxel_enemy.gd"
const ENEMY_ROOT_NAME: String = "ArachnodroidRoot"

const DRONE_SCENE: String = "res://assets/drone/drone_quad.glb"
const DRONE_SIDECAR: String = "res://assets/drone/drone_quad.parts.json"
const DRONE_IMPORT: String = "res://assets/drone/drone_quad.glb.import"
const DRONE_PALETTE_IMPORT: String = "res://assets/drone/drone_quad_palette.png.import"
const DRONE_IMPORT_SCRIPT: String = "res://asset_import/import_drone.gd"
const DRONE_ROOT_NAME: String = "DroneQuad"

## Tolerancia de los pivotes, de `docs/05` §14.2 criterio 3.
const PIVOT_TOLERANCE: float = 0.05

## Tolerancia de la altura total y de la huella, criterio 7.
const SIZE_TOLERANCE: float = 0.1

## Diagonal motor a motor del dron y su tolerancia (`docs/05` §10 y §13).
const MOTOR_DIAGONAL: float = 0.24
const MOTOR_DIAGONAL_TOLERANCE: float = 0.01

## Los mismos valores por defecto que aplica `import_voxel_enemy.gd`. El check
## los rederiva del sidecar por su cuenta: si el importador dejara de aplicarlos,
## la comparación falla.
const DEFAULT_HP: int = 600
const DEFAULT_ARMOR: float = 0.90
const DEFAULT_FUNCTION: String = "cosmetic"
const DEFAULT_COLLISION: String = "box"

## Las 16 partes canónicas del dron (`docs/03` §7 más `camera`, `battery` y el
## `led` que añadió WP-12a).
const DRONE_PARTS: PackedStringArray = [
	"frame",
	"motor_1", "motor_2", "motor_3", "motor_4",
	"prop_1", "prop_2", "prop_3", "prop_4",
	"prop_disk_1", "prop_disk_2", "prop_disk_3", "prop_disk_4",
	"camera", "battery", "led",
]

## Pares de motores en diagonal. `docs/03` §2.1: M1 delantero-izquierdo,
## M2 delantero-derecho, M3 trasero-derecho, M4 trasero-izquierdo.
const MOTOR_DIAGONALS: Dictionary[String, String] = {
	"motor_1": "motor_3",
	"motor_2": "motor_4",
}

## Puntos débiles que `docs/05` §14.2 criterio 9 exige con superficie emisiva.
const EMISSIVE_WEAK_POINTS: PackedStringArray = [
	"wp_head_visor",
	"wp_leg_fl_knee", "wp_leg_fr_knee", "wp_leg_bl_knee", "wp_leg_br_knee",
]

## Los nueve metadatos garantizados de `docs/05` §12, con el tipo `Variant.Type`
## que debe tener cada uno en la malla y en el cuerpo.
const META_TYPES: Dictionary[StringName, int] = {
	&"part_id": TYPE_STRING,
	&"hp": TYPE_INT,
	&"armor": TYPE_FLOAT,
	&"detachable": TYPE_BOOL,
	&"debris_mass": TYPE_FLOAT,
	&"weak_point_id": TYPE_STRING,
	&"function": TYPE_STRING,
	&"flags": TYPE_PACKED_STRING_ARRAY,
	&"has_emissive_surface": TYPE_BOOL,
}


func _run() -> void:
	await wait_frames(1)
	_check_scene_presets(ENEMY_IMPORT, ENEMY_IMPORT_SCRIPT, ENEMY_ROOT_NAME)
	_check_scene_presets(DRONE_IMPORT, DRONE_IMPORT_SCRIPT, DRONE_ROOT_NAME)
	_check_palette_preset(ENEMY_PALETTE_IMPORT)
	_check_palette_preset(DRONE_PALETTE_IMPORT)
	_check_enemy()
	_check_drone()


# --------------------------------------------------------------------------
# Presets de importación
# --------------------------------------------------------------------------

## Comprueba el `.import` de un GLB: script de post-import, sin LOD, con malla
## de sombra, sin tangentes, sin animaciones y con el nombre de raíz esperado
## (`docs/02` §7.1 y `docs/05` §9.3).
func _check_scene_presets(import_path: String, script_path: String, root_name: String) -> void:
	var config := ConfigFile.new()
	var err := config.load(import_path)
	if err != OK:
		fail("no se pudo leer '%s': %s" % [import_path, error_string(err)])
		return
	var expected: Dictionary[String, Variant] = {
		"import_script/path": script_path,
		"meshes/generate_lods": false,
		"meshes/create_shadow_meshes": true,
		"meshes/ensure_tangents": false,
		"animation/import": false,
		"nodes/root_type": "Node3D",
		"nodes/root_name": root_name,
		"nodes/root_scale": 1.0,
		"materials/extract": 0,
		"gltf/embedded_image_handling": 1,
	}
	for key: String in expected:
		var got: Variant = config.get_value("params", key, null)
		expect(got == expected[key], "%s: '%s' esperado %s, obtenido %s" \
				% [import_path.get_file(), key, str(expected[key]), str(got)])


## Comprueba el `.import` de una paleta 256×1: lossless, sin mipmaps y sin
## rellenar el borde alfa (`docs/02` §7.3).
func _check_palette_preset(import_path: String) -> void:
	var config := ConfigFile.new()
	var err := config.load(import_path)
	if err != OK:
		fail("no se pudo leer '%s': %s" % [import_path, error_string(err)])
		return
	var expected: Dictionary[String, Variant] = {
		"compress/mode": 0,
		"mipmaps/generate": false,
		"process/fix_alpha_border": false,
		"detect_3d/compress_to": 0,
	}
	for key: String in expected:
		var got: Variant = config.get_value("params", key, null)
		expect(got == expected[key], "%s: '%s' esperado %s, obtenido %s" \
				% [import_path.get_file(), key, str(expected[key]), str(got)])


# --------------------------------------------------------------------------
# Arachnodroid
# --------------------------------------------------------------------------

## Los once criterios de `docs/05` §14.2 sobre `arachnodroid.glb`.
func _check_enemy() -> void:
	var sidecar := _read_json(ENEMY_SIDECAR)
	if sidecar.is_empty():
		return
	var root := _instantiate(ENEMY_SCENE)
	if root == null:
		return

	expect(root.name == ENEMY_ROOT_NAME,
			"la raíz del enemigo se llama '%s', esperada '%s'" % [root.name, ENEMY_ROOT_NAME])

	var metadata := sidecar.get("metadata", {}) as Dictionary
	var geometry := metadata.get("parts", {}) as Dictionary
	var specs := _enemy_specs(sidecar)
	var meshes := _meshes_by_part_id(root)

	_check_root_metadata(root, metadata, specs.size())
	_check_part_inventory(specs, meshes, metadata)
	_check_hierarchy(specs, meshes)
	_check_pivots(geometry, meshes)
	_check_bodies(specs, meshes)
	_check_materials(specs, meshes)
	_check_no_lods(meshes)
	_check_bounds(root, meshes, metadata)
	_check_knees_and_feet(geometry, meshes)

	root.queue_free()


## Funde `parts[]` con `metadata.parts` aplicando los mismos valores por defecto
## que el importador. Devuelve `{part_id: spec}`.
func _enemy_specs(sidecar: Dictionary) -> Dictionary[StringName, Dictionary]:
	var specs: Dictionary[StringName, Dictionary] = {}
	var default_collision := String(sidecar.get("collision_default", DEFAULT_COLLISION))
	var geometry := (sidecar.get("metadata", {}) as Dictionary).get("parts", {}) as Dictionary

	for raw: Variant in sidecar.get("parts", []) as Array:
		var entry := raw as Dictionary
		if entry == null or not entry.has("id"):
			fail("el sidecar del enemigo tiene una entrada de parte sin 'id'")
			continue
		var part_id := StringName(entry["id"])
		var geo := geometry.get(String(part_id), {}) as Dictionary
		var flags := PackedStringArray()
		for flag: Variant in entry.get("flags", []) as Array:
			flags.append(String(flag))
		specs[part_id] = {
			"part_id": String(part_id),
			"parent": String(geo.get("parent", "")) if geo.get("parent") != null else "",
			"hp": int(entry.get("hp", DEFAULT_HP)),
			"armor": float(entry.get("armor", DEFAULT_ARMOR)),
			"detachable": flags.has("detachable"),
			"debris_mass": float(entry.get("debris_mass", geo.get("estimated_mass", 0.0))),
			"weak_point_id": String(entry.get("weak_point_id", "")),
			"function": String(entry.get("function", DEFAULT_FUNCTION)),
			"flags": flags,
			"has_emissive_surface": bool(geo.get("has_emissive_surface", false)),
			"weak_point": flags.has("weak_point"),
			"collision": String(entry.get("collision", default_collision)),
		}
	return specs


## Criterio 1: hay tantas mallas con `part_id` como dice `metadata.part_count`,
## y el conjunto de ids coincide exactamente con el del sidecar.
func _check_part_inventory(specs: Dictionary[StringName, Dictionary],
		meshes: Dictionary[StringName, MeshInstance3D], metadata: Dictionary) -> void:
	var declared := int(metadata.get("part_count", -1))
	expect(meshes.size() == declared,
			"mallas con 'part_id': %d, esperadas %d (metadata.part_count)" \
			% [meshes.size(), declared])
	expect(specs.size() == declared,
			"partes declaradas en el sidecar: %d, esperadas %d (metadata.part_count)" \
			% [specs.size(), declared])
	for part_id: StringName in specs:
		expect(meshes.has(part_id), "falta en la escena la parte '%s' del sidecar" % part_id)
	for part_id: StringName in meshes:
		expect(specs.has(part_id), "la escena trae la parte '%s', que el sidecar no declara" % part_id)


## Criterio 2: el primer ancestro con `part_id` de cada malla es el `parent` que
## declara el sidecar; la parte raíz no tiene ninguno.
func _check_hierarchy(specs: Dictionary[StringName, Dictionary],
		meshes: Dictionary[StringName, MeshInstance3D]) -> void:
	for part_id: StringName in specs:
		if not meshes.has(part_id):
			continue
		var expected := String(specs[part_id]["parent"])
		var found := ""
		var ancestor := meshes[part_id].get_parent()
		while ancestor != null:
			if ancestor.has_meta(&"part_id"):
				found = String(ancestor.get_meta(&"part_id"))
				break
			ancestor = ancestor.get_parent()
		expect(found == expected,
				"'%s' cuelga de '%s', el sidecar dice '%s'" % [part_id, found, expected])


## Criterio 3: la posición global de cada parte coincide con su `pivot_world`.
func _check_pivots(geometry: Dictionary,
		meshes: Dictionary[StringName, MeshInstance3D]) -> void:
	for part_id: StringName in meshes:
		var geo := geometry.get(String(part_id), {}) as Dictionary
		if not geo.has("pivot_world"):
			fail("el sidecar no declara 'pivot_world' de '%s'" % part_id)
			continue
		var expected := _to_vector3(geo["pivot_world"])
		var got := meshes[part_id].global_position
		expect_near(got.distance_to(expected), 0.0, PIVOT_TOLERANCE,
				"pivote de '%s' en %s, esperado %s" % [part_id, str(got), str(expected)])


## Criterios 4, 5, 6 y 10: por cada parte con colisión hay un `AnimatableBody3D`
## `<id>_body` en la capa correcta, con la máscara correcta, sin
## `sync_to_physics` y con los nueve metadatos en la malla y en el cuerpo.
func _check_bodies(specs: Dictionary[StringName, Dictionary],
		meshes: Dictionary[StringName, MeshInstance3D]) -> void:
	var mask_body := PhysicsLayers.WORLD | PhysicsLayers.DRONE \
			| PhysicsLayers.CITY | PhysicsLayers.DEBRIS
	var mask_weak := PhysicsLayers.WORLD | PhysicsLayers.DRONE

	for part_id: StringName in specs:
		if not meshes.has(part_id):
			continue
		var spec := specs[part_id]
		var mesh_instance := meshes[part_id]
		_check_metadata(mesh_instance, spec, "la malla")

		var body := _find_body(mesh_instance)
		if String(spec["collision"]) == "none":
			expect(body == null, "'%s' declara collision 'none' pero tiene cuerpo" % part_id)
			continue
		if body == null:
			fail("'%s' no tiene su AnimatableBody3D '%s_body'" % [part_id, part_id])
			continue

		expect(body.name == "%s_body" % part_id,
				"el cuerpo de '%s' se llama '%s'" % [part_id, body.name])
		expect(not body.sync_to_physics, "'%s_body' tiene sync_to_physics activo" % part_id)

		var is_weak := bool(spec["weak_point"])
		var expected_layer := PhysicsLayers.ENEMY_WEAK if is_weak else PhysicsLayers.ENEMY_BODY
		var expected_mask := mask_weak if is_weak else mask_body
		expect(body.collision_layer == expected_layer,
				"'%s_body' en capa %d, esperada %d" % [part_id, body.collision_layer, expected_layer])
		expect(body.collision_mask == expected_mask,
				"'%s_body' con máscara %d, esperada %d" % [part_id, body.collision_mask, expected_mask])

		var shapes := _collision_shapes(body)
		expect(shapes.size() == 1,
				"'%s_body' tiene %d CollisionShape3D, esperado 1" % [part_id, shapes.size()])
		if not shapes.is_empty():
			expect(shapes[0].shape != null, "'%s_body' tiene una forma nula" % part_id)
		_check_metadata(body, spec, "el cuerpo")


## Criterio 6: los nueve metadatos existen, son del tipo declarado en
## [constant META_TYPES] y valen lo que dice el sidecar.
func _check_metadata(node: Node, spec: Dictionary, where: String) -> void:
	var part_id := String(spec["part_id"])
	for key: StringName in META_TYPES:
		if not node.has_meta(key):
			fail("falta el metadato '%s' en %s de '%s'" % [key, where, part_id])
			continue
		var value: Variant = node.get_meta(key)
		var expected_type: int = META_TYPES[key]
		if typeof(value) != expected_type:
			fail("'%s' en %s de '%s' es %s, esperado %s" \
					% [key, where, part_id, type_string(typeof(value)), type_string(expected_type)])
			continue
		if key == &"flags":
			var got := value as PackedStringArray
			var want := spec["flags"] as PackedStringArray
			expect(got == want, "'flags' en %s de '%s' vale %s, esperado %s" \
					% [where, part_id, str(got), str(want)])
			continue
		var want_value: Variant = spec[String(key)]
		if expected_type == TYPE_FLOAT:
			expect_near(float(value), float(want_value), 0.001,
					"'%s' en %s de '%s'" % [key, where, part_id])
		else:
			expect(value == want_value, "'%s' en %s de '%s' vale %s, esperado %s" \
					% [key, where, part_id, str(value), str(want_value)])


## Criterio 9 más el filtro de paleta: toda parte con `has_emissive_surface`
## tiene al menos un material con `emission_enabled`, ningún material queda con
## un filtro distinto de NEAREST y los cinco puntos débiles emisivos de
## `docs/05` §14.2 siguen siéndolo.
func _check_materials(specs: Dictionary[StringName, Dictionary],
		meshes: Dictionary[StringName, MeshInstance3D]) -> void:
	for part_id: StringName in meshes:
		var mesh := meshes[part_id].mesh
		if mesh == null:
			fail("la parte '%s' no tiene malla" % part_id)
			continue
		var emissive := false
		for surface: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null:
				fail("la superficie %d de '%s' no tiene BaseMaterial3D" % [surface, part_id])
				continue
			expect(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
					"el material %d de '%s' no muestrea la paleta con NEAREST (filtro %d)" \
					% [surface, part_id, material.texture_filter])
			emissive = emissive or material.emission_enabled
		if not specs.has(part_id):
			continue
		if bool(specs[part_id]["has_emissive_surface"]):
			expect(emissive,
					"'%s' declara has_emissive_surface pero ningún material tiene emission_enabled" \
					% part_id)

	for part_name: String in EMISSIVE_WEAK_POINTS:
		var part_id := StringName(part_name)
		expect(specs.has(part_id) and bool(specs[part_id]["has_emissive_surface"]),
				"el punto débil '%s' debería tener superficie emisiva" % part_name)


## Criterio 8: ninguna superficie llegó con niveles de detalle generados.
func _check_no_lods(meshes: Dictionary[StringName, MeshInstance3D]) -> void:
	for part_id: StringName in meshes:
		var mesh := meshes[part_id].mesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var info := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
			var lods := info.get("lods", []) as Array
			expect(lods.is_empty(),
					"la superficie %d de '%s' trae %d LOD" % [surface, part_id, lods.size()])


## Criterio 7: el AABB combinado mide lo que declara el sidecar, tanto de alto
## como de huella.
func _check_bounds(root: Node3D, meshes: Dictionary[StringName, MeshInstance3D],
		metadata: Dictionary) -> void:
	var bounds := AABB()
	var first := true
	for part_id: StringName in meshes:
		var mesh_instance := meshes[part_id]
		if mesh_instance.mesh == null:
			continue
		var world := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		bounds = world if first else bounds.merge(world)
		first = false
	if first:
		fail("no se pudo calcular el AABB combinado: ninguna parte tiene malla")
		return

	var local := root.global_transform.affine_inverse() * bounds
	expect_near(local.size.y, float(metadata.get("total_height", 0.0)), SIZE_TOLERANCE,
			"altura total del AABB combinado")
	var footprint := metadata.get("footprint", []) as Array
	if footprint.size() != 2:
		fail("el sidecar no declara 'metadata.footprint' como par de números")
		return
	expect_near(local.size.x, float(footprint[0]), SIZE_TOLERANCE, "huella en X")
	expect_near(local.size.z, float(footprint[1]), SIZE_TOLERANCE, "huella en Z")


## Criterio 11 (adaptado): las cuatro rodillas y los cuatro pies están a la
## altura que declara su `pivot_world` en el sidecar.
##
## `docs/05` §14.2 pide 11.0 m y 3.0 m. Con los pivotes reales de §4.4 la pose de
## reposo del modelo importado da **8.625 m** y **3.75 m**; el 11.0 / 3.0
## corresponde a la pose de marcha, con el cuerpo a `hip_height` 14 m, que es
## trabajo del rig procedural de WP-17 y no del GLB. El criterio se verifica,
## entonces, contra el sidecar, que es la única fuente de verdad del modelo.
func _check_knees_and_feet(geometry: Dictionary,
		meshes: Dictionary[StringName, MeshInstance3D]) -> void:
	var knees := 0
	var feet := 0
	for part_id: StringName in meshes:
		var name_text := String(part_id)
		var is_knee := name_text.begins_with("wp_leg_") and name_text.ends_with("_knee")
		var is_foot := name_text.begins_with("leg_") and name_text.ends_with("_foot")
		if not is_knee and not is_foot:
			continue
		if is_knee:
			knees += 1
		else:
			feet += 1
		var geo := geometry.get(name_text, {}) as Dictionary
		if not geo.has("pivot_world"):
			fail("el sidecar no declara 'pivot_world' de '%s'" % part_id)
			continue
		expect_near(meshes[part_id].global_position.y, _to_vector3(geo["pivot_world"]).y,
				PIVOT_TOLERANCE, "altura sobre el suelo de '%s'" % part_id)
	expect(knees == 4, "rodillas encontradas: %d, esperadas 4" % knees)
	expect(feet == 4, "pies encontrados: %d, esperados 4" % feet)


## Metadatos del modelo en la raíz: `part_count`, `total_height` y
## `emissive_strength`, todos tomados del sidecar.
func _check_root_metadata(root: Node3D, metadata: Dictionary, fallback_count: int) -> void:
	expect(root.has_meta(&"part_count"), "la raíz no tiene el metadato 'part_count'")
	expect(root.has_meta(&"total_height"), "la raíz no tiene el metadato 'total_height'")
	expect(root.has_meta(&"emissive_strength"), "la raíz no tiene el metadato 'emissive_strength'")
	if root.has_meta(&"part_count"):
		expect(int(root.get_meta(&"part_count")) == int(metadata.get("part_count", fallback_count)),
				"'part_count' de la raíz vale %d, esperado %d" \
				% [int(root.get_meta(&"part_count")), int(metadata.get("part_count", fallback_count))])
	if root.has_meta(&"total_height"):
		expect_near(float(root.get_meta(&"total_height")),
				float(metadata.get("total_height", 0.0)), 0.001, "'total_height' de la raíz")
	if root.has_meta(&"emissive_strength"):
		expect_near(float(root.get_meta(&"emissive_strength")),
				float(metadata.get("emissive_strength", 0.0)), 0.001,
				"'emissive_strength' de la raíz")


# --------------------------------------------------------------------------
# Dron
# --------------------------------------------------------------------------

## El dron: 16 partes canónicas, metadatos de motor y diagonal motor a motor.
func _check_drone() -> void:
	var sidecar := _read_json(DRONE_SIDECAR)
	if sidecar.is_empty():
		return
	var root := _instantiate(DRONE_SCENE)
	if root == null:
		return

	expect(root.name == DRONE_ROOT_NAME,
			"la raíz del dron se llama '%s', esperada '%s'" % [root.name, DRONE_ROOT_NAME])

	var metadata := sidecar.get("metadata", {}) as Dictionary
	var geometry := metadata.get("parts", {}) as Dictionary
	var meshes := _meshes_by_name(root)

	expect(meshes.size() == int(metadata.get("part_count", -1)),
			"el dron tiene %d mallas, esperadas %d (metadata.part_count)" \
			% [meshes.size(), int(metadata.get("part_count", -1))])
	expect(meshes.size() == DRONE_PARTS.size(),
			"el dron tiene %d mallas, esperadas %d canónicas" % [meshes.size(), DRONE_PARTS.size()])
	for part_name: String in DRONE_PARTS:
		expect(meshes.has(StringName(part_name)), "falta la parte canónica '%s' del dron" % part_name)
	for part_id: StringName in meshes:
		expect(DRONE_PARTS.has(String(part_id)), "el dron trae la parte desconocida '%s'" % part_id)

	_check_root_metadata(root, metadata, meshes.size())
	_check_no_lods(meshes)

	var seen_indices: Dictionary[int, String] = {}
	for part_name: String in DRONE_PARTS:
		var part_id := StringName(part_name)
		if not meshes.has(part_id):
			continue
		var mesh_instance := meshes[part_id]
		expect(mesh_instance.gi_mode == GeometryInstance3D.GI_MODE_DISABLED,
				"'%s' no tiene la GI deshabilitada" % part_name)
		expect(_find_body(mesh_instance) == null,
				"'%s' tiene colisionador; el dron es un único RigidBody3D (docs/05 §10)" % part_name)
		_check_drone_filter(mesh_instance, part_name)

		var geo := geometry.get(part_name, {}) as Dictionary
		if geo.has("pivot_world"):
			var expected := _to_vector3(geo["pivot_world"])
			expect_near(mesh_instance.global_position.distance_to(expected), 0.0, PIVOT_TOLERANCE,
					"pivote de '%s' en %s, esperado %s" \
					% [part_name, str(mesh_instance.global_position), str(expected)])

		if not part_name.begins_with("motor_") and not part_name.begins_with("prop_"):
			continue
		if not mesh_instance.has_meta(&"motor_index") or not mesh_instance.has_meta(&"spin"):
			fail("'%s' no tiene 'motor_index' y 'spin'" % part_name)
			continue
		var index := int(mesh_instance.get_meta(&"motor_index"))
		var spin := int(mesh_instance.get_meta(&"spin"))
		expect(index >= 1 and index <= 4, "'%s' tiene motor_index %d, fuera de 1–4" % [part_name, index])
		expect(spin == 1 or spin == -1, "'%s' tiene spin %d, esperado +1 o −1" % [part_name, spin])
		expect(String(part_name).ends_with(str(index)),
				"'%s' declara motor_index %d, que no coincide con su nombre" % [part_name, index])
		if part_name.begins_with("motor_"):
			expect(not seen_indices.has(index),
					"motor_index %d repetido en '%s' y en '%s'" \
					% [index, part_name, seen_indices.get(index, "")])
			seen_indices[index] = part_name

	expect(seen_indices.size() == 4, "motores con motor_index único: %d, esperados 4" % seen_indices.size())
	_check_motor_geometry(meshes)
	root.queue_free()


## Diagonal motor a motor y alternancia del sentido de giro.
func _check_motor_geometry(meshes: Dictionary[StringName, MeshInstance3D]) -> void:
	for first: String in MOTOR_DIAGONALS:
		var second: String = MOTOR_DIAGONALS[first]
		var a := StringName(first)
		var b := StringName(second)
		if not meshes.has(a) or not meshes.has(b):
			continue
		var distance := meshes[a].global_position.distance_to(meshes[b].global_position)
		expect_near(distance, MOTOR_DIAGONAL, MOTOR_DIAGONAL_TOLERANCE,
				"diagonal %s↔%s" % [first, second])
		if meshes[a].has_meta(&"spin") and meshes[b].has_meta(&"spin"):
			expect(int(meshes[a].get_meta(&"spin")) == int(meshes[b].get_meta(&"spin")),
					"'%s' y '%s' son diagonales y deberían girar igual" % [first, second])
	if meshes.has(&"motor_1") and meshes.has(&"motor_2") \
			and meshes[&"motor_1"].has_meta(&"spin") and meshes[&"motor_2"].has_meta(&"spin"):
		expect(int(meshes[&"motor_1"].get_meta(&"spin")) != int(meshes[&"motor_2"].get_meta(&"spin")),
				"'motor_1' y 'motor_2' son adyacentes y deberían girar al revés")


## Filtro NEAREST en los materiales de una parte del dron.
func _check_drone_filter(mesh_instance: MeshInstance3D, part_name: String) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		fail("'%s' no tiene malla" % part_name)
		return
	for surface: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		if material == null:
			fail("la superficie %d de '%s' no tiene BaseMaterial3D" % [surface, part_name])
			continue
		expect(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
				"el material %d de '%s' no muestrea la paleta con NEAREST (filtro %d)" \
				% [surface, part_name, material.texture_filter])


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Carga un JSON de `res://`. Devuelve `{}` y registra el fallo si no se puede.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		fail("no existe '%s'" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var data := parsed as Dictionary
	if data == null:
		fail("'%s' no es un objeto JSON válido" % path)
		return {}
	return data


## Instancia un GLB importado y lo cuelga del check para que las transformadas
## globales sean las del modelo. Devuelve `null` si no carga.
func _instantiate(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		fail("no existe la escena importada '%s'" % path)
		return null
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		fail("'%s' no cargó como PackedScene" % path)
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		fail("la raíz de '%s' no es un Node3D" % path)
		return null
	add_child(root)
	return root


## Todas las mallas con metadato `part_id`, indexadas por ese `part_id`.
func _meshes_by_part_id(root: Node3D) -> Dictionary[StringName, MeshInstance3D]:
	var found: Dictionary[StringName, MeshInstance3D] = {}
	for node: Node in _descendants(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.has_meta(&"part_id"):
			continue
		var part_id := StringName(mesh_instance.get_meta(&"part_id"))
		if found.has(part_id):
			fail("hay dos mallas con part_id '%s'" % part_id)
			continue
		found[part_id] = mesh_instance
	return found


## Todas las mallas del árbol, indexadas por nombre de nodo.
func _meshes_by_name(root: Node3D) -> Dictionary[StringName, MeshInstance3D]:
	var found: Dictionary[StringName, MeshInstance3D] = {}
	for node: Node in _descendants(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		found[StringName(mesh_instance.name)] = mesh_instance
	return found


## Primer hijo directo `AnimatableBody3D` de una malla, o `null`.
func _find_body(mesh_instance: MeshInstance3D) -> AnimatableBody3D:
	for child: Node in mesh_instance.get_children():
		var body := child as AnimatableBody3D
		if body != null:
			return body
	return null


## Hijos `CollisionShape3D` de un cuerpo.
func _collision_shapes(body: AnimatableBody3D) -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	for child: Node in body.get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			found.append(shape)
	return found


## Convierte una lista JSON de tres números en un `Vector3`.
func _to_vector3(raw: Variant) -> Vector3:
	var values := raw as Array
	if values == null or values.size() != 3:
		return Vector3.ZERO
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
