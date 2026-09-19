## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Post-import del GLB voxel del dron del jugador (`docs/05` §10).
##
## El dron **no** lleva colisionadores por parte: es un único `RigidBody3D` con
## una forma convexa hecha a mano, que arma `drone.gd` en WP-04. Este script se
## limita a dejar la escena en condiciones para `DroneRig`:
##
## 1. Verifica que estén las 16 partes canónicas con el nombre exacto que espera
##    `docs/03` §7 (más `camera`, `battery` y `led`).
## 2. Escribe `motor_index` y `spin` en `motor_N`, `prop_N` y `prop_disk_N`, que
##    es lo que el mezclador de `docs/03` §2.1 y el desenfoque de hélices leen.
## 3. Deshabilita la GI de cada malla y fuerza el filtro NEAREST de la paleta.
##
## Igual que el importador de enemigos, **no añade ningún script** a ningún nodo
## y el fallo es ruidoso: cualquier nombre que no case produce `push_error`.
@tool
extends EditorScenePostImport

## Las 16 partes canónicas del dron, en el orden en que se nombran en `docs/05`
## §10. El nombre del nodo es el contrato con `docs/03` §7 (`DroneRig` busca
## `motor_N` y `prop_N` por ruta), así que vive acá y no en el sidecar: si el
## pipeline los renombrara, la importación tiene que gritar.
const CANONICAL_PARTS: PackedStringArray = [
	"frame",
	"motor_1", "motor_2", "motor_3", "motor_4",
	"prop_1", "prop_2", "prop_3", "prop_4",
	"prop_disk_1", "prop_disk_2", "prop_disk_3", "prop_disk_4",
	"camera", "battery", "led",
]

## Prefijos de las partes que heredan el `spin` de su motor. La pala y el disco
## son el mismo objeto visual en dos estados (`voxsplit/README` §5.8), así que
## giran en el mismo sentido que el motor del que cuelgan.
const SPIN_PREFIXES: PackedStringArray = ["prop_", "prop_disk_"]


## Punto de entrada del importador. Devuelve la misma escena, modificada.
func _post_import(scene: Node) -> Object:
	var source := get_source_file()
	var sidecar_path := source.get_basename() + ".parts.json"
	var sidecar := _read_sidecar(sidecar_path)
	if sidecar.is_empty():
		return scene

	var root := scene as Node3D
	if root == null:
		push_error("import_drone: la raíz de '%s' no es un Node3D." % source)
		return scene

	var specs := _part_specs(sidecar, sidecar_path)
	if specs.is_empty():
		push_error("import_drone: '%s' no declara ninguna parte." % sidecar_path)
		return root

	_check_canonical_parts(specs, sidecar_path)
	_collapse_redundant_root(root, specs)

	var seen: Dictionary[StringName, bool] = {}
	for node: Node in _descendants(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		var part_id := StringName(mesh_instance.name)
		if not specs.has(part_id):
			push_error("import_drone: la malla '%s' no figura en '%s'." % [part_id, sidecar_path])
			continue
		seen[part_id] = true
		_configure_part(mesh_instance, specs[part_id])

	for part_name: String in CANONICAL_PARTS:
		if not seen.has(StringName(part_name)):
			push_error("import_drone: falta la malla canónica '%s' en el GLB." % part_name)

	_propagate_motor_spin(root)
	_write_root_metadata(root, sidecar, specs.size())
	return root


## Lee el sidecar `<base>.parts.json` que acompaña al GLB. Devuelve un
## diccionario vacío —y avisa— si falta o si no es JSON válido.
func _read_sidecar(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("import_drone: no existe el sidecar '%s'." % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("import_drone: el sidecar '%s' está vacío o no se pudo leer." % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	var sidecar := parsed as Dictionary
	if sidecar == null:
		push_error("import_drone: el sidecar '%s' no es un objeto JSON válido." % path)
		return {}
	return sidecar


## Funde `parts[]` con `metadata.parts` y normaliza el bloque libre `meta`, que
## es donde el pipeline deja `motor_index` y `spin`.
func _part_specs(sidecar: Dictionary, sidecar_path: String) -> Dictionary[StringName, Dictionary]:
	var specs: Dictionary[StringName, Dictionary] = {}
	var metadata := sidecar.get("metadata", {}) as Dictionary
	var geometry := metadata.get("parts", {}) as Dictionary

	for raw: Variant in sidecar.get("parts", []) as Array:
		var entry := raw as Dictionary
		if entry == null or not entry.has("id"):
			push_error("import_drone: entrada de parte sin 'id' en '%s'." % sidecar_path)
			continue
		var part_id := StringName(entry["id"])
		var geo := geometry.get(String(part_id), {}) as Dictionary
		specs[part_id] = {
			"part_id": String(part_id),
			"meta": entry.get("meta", {}) as Dictionary,
			"has_emissive_surface": bool(geo.get("has_emissive_surface", false)),
		}
	return specs


## Contrasta las partes del sidecar con [constant CANONICAL_PARTS] en los dos
## sentidos: ni falta ninguna canónica ni sobra ninguna desconocida.
func _check_canonical_parts(specs: Dictionary[StringName, Dictionary],
		sidecar_path: String) -> void:
	for part_name: String in CANONICAL_PARTS:
		if not specs.has(StringName(part_name)):
			push_error("import_drone: '%s' no declara la parte canónica '%s'." \
					% [sidecar_path, part_name])
	for part_id: StringName in specs:
		if not CANONICAL_PARTS.has(String(part_id)):
			push_error("import_drone: '%s' declara la parte desconocida '%s'." \
					% [sidecar_path, part_id])


## Ajustes de render y metadatos de una parte del dron.
func _configure_part(mesh_instance: MeshInstance3D, spec: Dictionary) -> void:
	# El dron es un objeto móvil y pequeño: no aporta nada a la GI y sí costaría
	# una entrada de sonda por malla (`docs/05` §10).
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_force_nearest_filter(mesh_instance)
	mesh_instance.set_meta(&"part_id", String(spec["part_id"]))
	mesh_instance.set_meta(&"has_emissive_surface", bool(spec["has_emissive_surface"]))

	var meta := spec["meta"] as Dictionary
	if meta.has("motor_index"):
		mesh_instance.set_meta(&"motor_index", int(meta["motor_index"]))
	if meta.has("spin"):
		mesh_instance.set_meta(&"spin", int(meta["spin"]))


## Copia el `spin` de cada motor a su pala y a su disco de desenfoque. El
## sidecar solo lo declara en `motor_N`; `DroneRig` lo necesita en las tres
## mallas para girarlas en el sentido correcto.
func _propagate_motor_spin(root: Node3D) -> void:
	for node: Node in _descendants(root):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.has_meta(&"spin"):
			continue
		var part_name := String(mesh_instance.name)
		var inherits := false
		for prefix: String in SPIN_PREFIXES:
			if part_name.begins_with(prefix):
				inherits = true
				break
		if not inherits:
			continue
		var motor := mesh_instance.get_parent() as MeshInstance3D
		if motor == null or not motor.has_meta(&"spin"):
			push_error("import_drone: '%s' no cuelga de un motor con 'spin'." % part_name)
			continue
		mesh_instance.set_meta(&"spin", int(motor.get_meta(&"spin")))


## Metadatos del modelo completo, tomados del bloque `metadata` del sidecar.
func _write_root_metadata(root: Node3D, sidecar: Dictionary, fallback_count: int) -> void:
	var metadata := sidecar.get("metadata", {}) as Dictionary
	root.set_meta(&"part_count", int(metadata.get("part_count", fallback_count)))
	root.set_meta(&"total_height", float(metadata.get("total_height", 0.0)))
	root.set_meta(&"emissive_strength", float(metadata.get("emissive_strength", 0.0)))


## Fija el filtro NEAREST en todos los materiales de la malla: la paleta de
## 256×1 no admite filtrado (`docs/02` §7.3).
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


## El GLB trae su propio nodo raíz y Godot añade otro al generar la escena. Se
## funde el interior en la raíz de la escena, componiendo su transformada, para
## que `drone_rig.tscn` cuelgue de un único `Node3D` llamado `DroneQuad`.
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
