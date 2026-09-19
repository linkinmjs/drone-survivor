## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Post-import de los GLB voxel de enemigos que produce `tools/voxsplit`
## (`docs/05` §9.1).
##
## Se ejecuta una vez por GLB al final de la importación, cuando los
## `ImporterMeshInstance3D` ya son `MeshInstance3D` con `ArrayMesh` y la
## jerarquía de partes ya tiene sus pivotes en metros. Deja la escena lista para
## que `EnemyBase` (`docs/06` §2.1) construya el grafo de `EnemyPart` y
## `WeakPoint` en tiempo de ejecución:
##
## 1. Un `AnimatableBody3D` llamado `<id>_body` por parte con colisión, con
##    `sync_to_physics = false` y su `CollisionShape3D`.
## 2. Capas 3 (`enemy_body`) o 4 (`enemy_weak`) con las máscaras de `docs/02` §3.1.
## 3. Los nueve metadatos de `docs/05` §12, escritos **tanto** en la malla como
##    en el cuerpo: `docs/08` resuelve el impacto sobre el collider que devuelve
##    `intersect_ray`, así que tenerlos ya en el cuerpo ahorra un salto.
## 4. `gi_mode` deshabilitado y sombras activas en cada malla.
##
## **No añade ningún script a ningún nodo** (`docs/05` §9.1 punto 7) y el fallo
## es siempre ruidoso: un sidecar ausente o una parte que no case produce
## `push_error` con el `id` implicado y deja esa rama sin tocar.
@tool
extends EditorScenePostImport

## Sufijo del cuerpo de colisión de cada parte. `docs/06` §2.1 punto 3 lo busca
## como primer hijo directo `AnimatableBody3D` de la malla.
const BODY_SUFFIX: String = "_body"

## Sufijo del `CollisionShape3D` que cuelga del cuerpo.
const SHAPE_SUFFIX: String = "_shape"

## Flag que manda una parte a la capa 4 (`enemy_weak`).
const WEAK_POINT_FLAG: String = "weak_point"

## Flag que marca la parte como desprendible (`EnemyPart.detach()`).
const DETACHABLE_FLAG: String = "detachable"

## Valor de `collision` cuando ni la parte ni la cabecera lo declaran.
const DEFAULT_COLLISION: String = "box"

## Valores por defecto de `docs/05` §4.2 y `docs/06` §3 para los campos
## opcionales del `parts.json`. El balance definitivo lo pisa
## `EnemyProfile.part_overrides`; esto es solo el punto de partida.
const DEFAULT_HP: int = 600
const DEFAULT_ARMOR: float = 0.90
const DEFAULT_FUNCTION: String = "cosmetic"


## Punto de entrada del importador. Devuelve la misma escena, modificada.
func _post_import(scene: Node) -> Object:
	var source := get_source_file()
	var sidecar_path := source.get_basename() + ".parts.json"
	var sidecar := _read_sidecar(sidecar_path)
	if sidecar.is_empty():
		return scene

	var root := scene as Node3D
	if root == null:
		push_error("import_voxel_enemy: la raíz de '%s' no es un Node3D." % source)
		return scene

	var specs := _part_specs(sidecar, sidecar_path)
	if specs.is_empty():
		push_error("import_voxel_enemy: '%s' no declara ninguna parte." % sidecar_path)
		return root

	_collapse_redundant_root(root, specs)

	var seen: Dictionary[StringName, bool] = {}
	for node: Node in _descendants(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		var part_id := StringName(mesh_instance.name)
		if not specs.has(part_id):
			push_error("import_voxel_enemy: la malla '%s' no figura en '%s'." \
					% [part_id, sidecar_path])
			continue
		seen[part_id] = true
		_configure_part(mesh_instance, specs[part_id], root)

	for part_id: StringName in specs:
		if not seen.has(part_id):
			push_error("import_voxel_enemy: falta la malla de la parte '%s' declarada en '%s'." \
					% [part_id, sidecar_path])

	_write_root_metadata(root, sidecar, specs.size())
	return root


## Lee el sidecar `<base>.parts.json` que acompaña al GLB. Devuelve un
## diccionario vacío —y avisa— si falta o si no es JSON válido.
func _read_sidecar(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("import_voxel_enemy: no existe el sidecar '%s'." % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("import_voxel_enemy: el sidecar '%s' está vacío o no se pudo leer." % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	var sidecar := parsed as Dictionary
	if sidecar == null:
		push_error("import_voxel_enemy: el sidecar '%s' no es un objeto JSON válido." % path)
		return {}
	return sidecar


## Funde la entrada `parts[]` del sidecar con su bloque `metadata.parts` y
## resuelve los valores por defecto. La clave es el `id` de la parte, que es
## también el nombre del nodo en el GLB.
func _part_specs(sidecar: Dictionary, sidecar_path: String) -> Dictionary[StringName, Dictionary]:
	var specs: Dictionary[StringName, Dictionary] = {}
	var default_collision := String(sidecar.get("collision_default", DEFAULT_COLLISION))
	var metadata := sidecar.get("metadata", {}) as Dictionary
	var geometry := metadata.get("parts", {}) as Dictionary

	for raw: Variant in sidecar.get("parts", []) as Array:
		var entry := raw as Dictionary
		if entry == null or not entry.has("id"):
			push_error("import_voxel_enemy: entrada de parte sin 'id' en '%s'." % sidecar_path)
			continue
		var part_id := StringName(entry["id"])
		var geo := geometry.get(String(part_id), {}) as Dictionary
		var flags := PackedStringArray()
		for flag: Variant in entry.get("flags", []) as Array:
			flags.append(String(flag))
		specs[part_id] = {
			"part_id": String(part_id),
			"hp": int(entry.get("hp", DEFAULT_HP)),
			"armor": float(entry.get("armor", DEFAULT_ARMOR)),
			"detachable": flags.has(DETACHABLE_FLAG),
			# `docs/05` §4.2: si el `parts.json` no fija `debris_mass`, vale la
			# masa estimada del sidecar (`voxel_count · voxel_size³ · density`).
			"debris_mass": float(entry.get("debris_mass", geo.get("estimated_mass", 0.0))),
			"weak_point_id": String(entry.get("weak_point_id", "")),
			"function": String(entry.get("function", DEFAULT_FUNCTION)),
			"flags": flags,
			"has_emissive_surface": bool(geo.get("has_emissive_surface", false)),
			"weak_point": flags.has(WEAK_POINT_FLAG),
			"collision": String(entry.get("collision", default_collision)),
		}
	return specs


## Aplica a una parte los ajustes de render, los metadatos y su colisionador.
func _configure_part(mesh_instance: MeshInstance3D, spec: Dictionary, owner_node: Node) -> void:
	# Sin GI: el jefe se mueve y sus partes se desprenden, así que ninguna puede
	# participar del lightmap ni de la sonda de SDFGI (`docs/05` §9.1 punto 6).
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_force_nearest_filter(mesh_instance)
	_write_part_metadata(mesh_instance, spec)

	var collision := String(spec["collision"])
	if collision == "none":
		return
	var body := _build_body(mesh_instance, spec, collision)
	if body == null:
		return
	mesh_instance.add_child(body)
	_claim(body, owner_node)
	_write_part_metadata(body, spec)


## Construye el `AnimatableBody3D` de una parte con su forma de colisión.
## Devuelve `null` —y avisa— si la malla no tiene geometría utilizable.
func _build_body(mesh_instance: MeshInstance3D, spec: Dictionary,
		collision: String) -> AnimatableBody3D:
	var part_id := String(spec["part_id"])
	var mesh := mesh_instance.mesh
	if mesh == null:
		push_error("import_voxel_enemy: la parte '%s' no tiene malla; sin colisionador." % part_id)
		return null

	var shape := _build_shape(mesh, collision, part_id)
	if shape == null:
		return null

	var shape_node := CollisionShape3D.new()
	shape_node.name = part_id + SHAPE_SUFFIX
	shape_node.shape = shape
	if shape is BoxShape3D:
		shape_node.position = mesh.get_aabb().get_center()

	var body := AnimatableBody3D.new()
	body.name = part_id + BODY_SUFFIX
	# `EnemyBase` mueve las transformadas a mano (`docs/06` §7): con
	# `sync_to_physics` el cuerpo iría un tick por detrás y pelearía con Jolt.
	body.sync_to_physics = false
	var is_weak := bool(spec["weak_point"])
	if is_weak:
		body.collision_layer = PhysicsLayers.ENEMY_WEAK
		body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.DRONE
	else:
		body.collision_layer = PhysicsLayers.ENEMY_BODY
		body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.DRONE \
				| PhysicsLayers.CITY | PhysicsLayers.DEBRIS
	body.add_child(shape_node)
	return body


## Forma de colisión de una parte según su campo `collision` (`docs/05` §9.1
## punto 2). Un valor desconocido se trata como `box` y se reporta.
func _build_shape(mesh: Mesh, collision: String, part_id: String) -> Shape3D:
	if collision == "convex":
		var convex := mesh.create_convex_shape(true, true)
		if convex != null and not convex.points.is_empty():
			return convex
		push_error("import_voxel_enemy: '%s' no produjo casco convexo; se usa BoxShape3D." % part_id)
	elif collision != "box":
		push_error("import_voxel_enemy: colisión desconocida '%s' en '%s'; se usa 'box'." \
				% [collision, part_id])
	var bounds := mesh.get_aabb()
	if bounds.size.is_zero_approx():
		push_error("import_voxel_enemy: el AABB de '%s' es degenerado; sin colisionador." % part_id)
		return null
	var box := BoxShape3D.new()
	box.size = bounds.size
	return box


## Escribe los nueve metadatos garantizados de `docs/05` §12. Se llama con la
## malla y con su cuerpo, para que `docs/06` y `docs/08` lean lo mismo desde
## cualquiera de los dos.
func _write_part_metadata(node: Node, spec: Dictionary) -> void:
	node.set_meta(&"part_id", String(spec["part_id"]))
	node.set_meta(&"hp", int(spec["hp"]))
	node.set_meta(&"armor", float(spec["armor"]))
	node.set_meta(&"detachable", bool(spec["detachable"]))
	node.set_meta(&"debris_mass", float(spec["debris_mass"]))
	node.set_meta(&"weak_point_id", String(spec["weak_point_id"]))
	node.set_meta(&"function", String(spec["function"]))
	node.set_meta(&"flags", spec["flags"] as PackedStringArray)
	node.set_meta(&"has_emissive_surface", bool(spec["has_emissive_surface"]))


## Metadatos del modelo completo, en la raíz. Salen del bloque `metadata` del
## sidecar: ni este script ni los checks conocen el número de partes ni la
## altura del Arachnodroid (D-1 de `docs/05` §15).
func _write_root_metadata(root: Node3D, sidecar: Dictionary, fallback_count: int) -> void:
	var metadata := sidecar.get("metadata", {}) as Dictionary
	root.set_meta(&"part_count", int(metadata.get("part_count", fallback_count)))
	root.set_meta(&"total_height", float(metadata.get("total_height", 0.0)))
	root.set_meta(&"emissive_strength", float(metadata.get("emissive_strength", 0.0)))


## Fija el filtro NEAREST en todos los materiales de la malla. El GLB ya declara
## un `sampler` con `magFilter`/`minFilter` NEAREST y Godot lo respeta, pero la
## paleta de 256×1 no admite ningún filtrado (`docs/02` §7.3): cualquier
## interpolación mezcla colores de índices vecinos y produce franjas. Es barato
## dejarlo escrito acá y no depender del importador.
func _force_nearest_filter(mesh_instance: MeshInstance3D) -> void:
	_apply_nearest(mesh_instance.material_override)
	_apply_nearest(mesh_instance.material_overlay)
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	for surface: int in mesh.get_surface_count():
		_apply_nearest(mesh.surface_get_material(surface))
		_apply_nearest(mesh_instance.get_surface_override_material(surface))


## Pone `TEXTURE_FILTER_NEAREST` si el material es un `BaseMaterial3D`.
func _apply_nearest(material: Material) -> void:
	var base := material as BaseMaterial3D
	if base == null:
		return
	base.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


## El GLB trae un nodo raíz propio (`<Enemy>Root`, `docs/05` §7.1) y Godot añade
## otro por encima al generar la escena, así que la jerarquía llegaría con dos
## raíces homónimas encadenadas. Se funde la interior en la de la escena,
## componiendo su transformada, para que `Model` sea un único `Node3D`
## (`docs/06` §2). Solo se funde si es un `Node3D` pelado que no es una parte.
func _collapse_redundant_root(root: Node3D, specs: Dictionary[StringName, Dictionary]) -> void:
	if root.get_child_count() != 1:
		return
	var inner := root.get_child(0) as Node3D
	if inner == null or inner.get_class() != "Node3D":
		return
	if specs.has(StringName(inner.name)):
		return

	var offset := inner.transform
	for child: Node in inner.get_children():
		inner.remove_child(child)
		var spatial := child as Node3D
		if spatial != null:
			spatial.transform = offset * spatial.transform
		# El `owner` viejo apunta al nodo que está a punto de morir: se limpia
		# antes de reparentar y se vuelve a asignar con `_claim`, o `add_child`
		# avisa de una jerarquía de propietarios inconsistente.
		_claim(child, null)
		root.add_child(child)
		_claim(child, root)
	root.remove_child(inner)
	inner.free()


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found


## Asigna `owner` al nodo y a toda su descendencia, requisito para que el
## importador los empaquete en la escena resultante.
func _claim(node: Node, owner_node: Node) -> void:
	for descendant: Node in _descendants(node):
		descendant.owner = owner_node
