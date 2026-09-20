## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Campos de escombro horneado (`docs/10` §6).
##
## Cuando un [DebrisChunk] agota su vida, su transformada se **hornea** acá: la
## ruina sigue viéndose sin costar un `RigidBody3D` ni un draw call propio. Cada
## malla distinta registrada abre un [MultiMeshInstance3D] con
## [constant INSTANCES_PER_FIELD] plazas, y hay un tope de [constant MAX_FIELDS]
## campos (≤ 4 draw calls): dos para la ciudad y dos para los enemigos.
##
## `docs/10` §9.3 declara `RubbleField extends Node3D` con un `MultiMeshInstance3D`
## por malla; es la forma que se implementa acá, porque [method register_mesh]
## devuelve un índice sobre varias mallas y un único `MultiMeshInstance3D` sólo
## podría dibujar una.
class_name RubbleField extends Node3D

## Tope de mallas distintas, y por lo tanto de draw calls (`docs/10` §6).
const MAX_FIELDS: int = 4

## Instancias por campo.
const INSTANCES_PER_FIELD: int = 512

var _fields: Array[MultiMeshInstance3D] = []
var _meshes: Array[Mesh] = []
var _counts: PackedInt32Array = PackedInt32Array()


## Da de alta [param mesh] y devuelve su índice de campo. Es **idempotente**: una
## malla ya registrada devuelve su índice anterior sin abrir un campo nuevo.
## Devuelve `-1` si la malla es nula o si ya hay [constant MAX_FIELDS] campos.
func register_mesh(mesh: Mesh) -> int:
	if mesh == null:
		return -1
	var existing := _meshes.find(mesh)
	if existing >= 0:
		return existing
	if _fields.size() >= MAX_FIELDS:
		return -1

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_custom_data = true
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = INSTANCES_PER_FIELD
	multi_mesh.visible_instance_count = 0

	var field := MultiMeshInstance3D.new()
	field.name = "RubbleField%d" % _fields.size()
	field.multimesh = multi_mesh
	# Riesgo 9 del plan: geometría que cambia no participa de SDFGI.
	field.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(field)

	_fields.append(field)
	_meshes.append(mesh)
	_counts.append(0)
	return _fields.size() - 1


## Hornea una instancia de la malla [param mesh_index] en [param xform] con el
## tinte [param tint]. Al llenarse el campo se reescriben las plazas desde el
## principio: la ruina más vieja desaparece, que es el comportamiento deseado.
func bake(mesh_index: int, xform: Transform3D, tint: Color) -> void:
	if mesh_index < 0 or mesh_index >= _fields.size():
		return
	var multi_mesh := _fields[mesh_index].multimesh
	var slot := _counts[mesh_index] % INSTANCES_PER_FIELD
	# `set_instance_transform` sobre una plaza aún no visible es legal: el
	# `MultiMesh` ya tiene `instance_count` plazas reservadas.
	multi_mesh.set_instance_transform(slot, xform)
	multi_mesh.set_instance_custom_data(slot, tint)
	_counts[mesh_index] += 1
	multi_mesh.visible_instance_count = mini(_counts[mesh_index], INSTANCES_PER_FIELD)


## Cantidad de campos abiertos.
func get_field_count() -> int:
	return _fields.size()


## Cuántas instancias se hornearon en el campo [param mesh_index].
func get_instance_count(mesh_index: int) -> int:
	if mesh_index < 0 or mesh_index >= _counts.size():
		return 0
	return _counts[mesh_index]


## Total horneado en todos los campos.
func get_total_instance_count() -> int:
	var total := 0
	for count: int in _counts:
		total += count
	return total


## Índice del campo de [param mesh], o `-1` si no está registrada.
func index_of(mesh: Mesh) -> int:
	return _meshes.find(mesh)


## Vacía todos los campos y los cierra. Lo llama el `RoundManager` al reiniciar.
func clear() -> void:
	for field: MultiMeshInstance3D in _fields:
		field.queue_free()
	_fields.clear()
	_meshes.clear()
	_counts = PackedInt32Array()
