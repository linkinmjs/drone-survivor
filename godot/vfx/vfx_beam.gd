## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Haz continuo (`docs/13` §4, `docs/07` §5.6 y §5.7).
##
## Tres piezas: el cilindro con `vfx/beam.gdshader`, una [OmniLight3D] en el
## punto de contacto —que es lo que hace que el haz **ilumine** la fachada que
## está cortando— y doce chispas en bucle en ese mismo punto.
##
## Sirve para los tres haces del juego, que sólo se diferencian por el `.tscn`
## que los configura:
##
## - `vfx/laser_beam.tscn` — cian del [b]head_laser[/b], radio 0.25 m.
## - `vfx/siege_beam.tscn` — ámbar-naranja grueso del [b]siege_beam[/b], radio
##   1.5 m. Es la **única** excepción cálida de la identidad de `docs/13` §1: no
##   es el enemigo, es su luz cayendo sobre nuestra ciudad.
## - `vfx/siege_column.tscn` — la columna vertical de la telegrafía del asedio,
##   el mismo haz puesto de pie sobre el edificio marcado.
##
## [b]Vida manual[/b]: `life_seconds = 0`. Quien lo enciende es quien lo apaga —
## [SweepAction] con `update_beam`/`hide_beam`, o [Telegraph] con la columna—,
## porque la duración es la del ataque y no la de una animación.
class_name VFXBeam extends VFXEffect

## Eje local del [CylinderMesh]: su altura crece sobre `Y`.
const MESH_AXIS: Vector3 = Vector3.UP

## Longitud mínima por debajo de la cual el haz se oculta, en metros.
const MIN_LENGTH: float = 0.05

@onready var _beam: MeshInstance3D = get_node_or_null(^"Beam") as MeshInstance3D
@onready var _impact_light: OmniLight3D = get_node_or_null(^"ImpactLight") as OmniLight3D
@onready var _sparks: GPUParticles3D = get_node_or_null(^"ContactSparks") as GPUParticles3D

var _mesh: CylinderMesh = null
var _radius: float = 0.25
var _lit: bool = false


func _ready() -> void:
	super()
	if _beam != null:
		# La malla es un sub-recurso compartido por las instancias de la escena;
		# cada haz estira la suya, así que se queda con una copia propia.
		_mesh = (_beam.mesh as CylinderMesh).duplicate() as CylinderMesh
		_beam.mesh = _mesh
		_radius = _mesh.top_radius
	set_lit(false)


## Radio del haz, en metros. Lo fija la acción desde su `BEAM_RADIUS`.
func set_radius(radius: float) -> void:
	_radius = maxf(radius, 0.01)
	if _mesh != null:
		_mesh.top_radius = _radius
		_mesh.bottom_radius = _radius


## Color del haz. Tiñe el shader, la luz de impacto y las chispas de contacto de
## una sola vez, para que un haz nunca quede con el cuerpo de un color y el
## contacto de otro.
func set_beam_color(body: Color, core: Color) -> void:
	var material := _shader_material()
	if material != null:
		material.set_shader_parameter(&"beam_color", body)
		material.set_shader_parameter(&"core_color", core)
	if _impact_light != null:
		_impact_light.light_color = body
	if _sparks != null:
		var process := _sparks.process_material as ParticleProcessMaterial
		if process != null:
			process.color = core


## Estira el haz de [param from] a [param to] y lo enciende.
##
## El eje del [CylinderMesh] es `Y`, así que la base se construye poniendo `Y`
## sobre la dirección y el centro a media longitud. Es exactamente el cálculo del
## placeholder de WP-19: lo que cambia es el material y lo que hay en la punta.
func set_endpoints(from: Vector3, to: Vector3) -> void:
	if _beam == null or _mesh == null:
		return
	var delta := to - from
	var length := delta.length()
	if length < MIN_LENGTH:
		set_lit(false)
		return
	var axis := delta / length
	var reference := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := reference.cross(axis).normalized()
	_mesh.height = length
	global_position = from
	_beam.global_transform = Transform3D(
			Basis(right, axis, right.cross(axis)).orthonormalized(),
			from + axis * length * 0.5)
	if _impact_light != null:
		_impact_light.global_position = to - axis * _radius
	if _sparks != null:
		_sparks.global_position = to - axis * _radius
		# Las chispas salen **hacia** el que dispara, que es como rebota el metal
		# fundido de una superficie cortada. El blanco está siempre a 1 m, así que
		# `look_at` nunca recibe un vector nulo.
		_sparks.look_at(_sparks.global_position - axis,
				Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT)
	set_lit(true)


## Enciende o apaga las tres piezas a la vez. Apagarlo libera el presupuesto de
## emisores sin devolver la instancia al pool: el haz sigue siendo de su acción.
func set_lit(lit: bool) -> void:
	_lit = lit
	visible = lit
	if _beam != null:
		_beam.visible = lit
	if _impact_light != null:
		_impact_light.visible = lit
	if _sparks != null:
		_sparks.emitting = lit


## Nodo de malla del haz. Es lo que devuelve `SweepAction.beam_node()` y lo que
## mide el criterio 15 de `arachnodroid_check`.
func beam_mesh() -> MeshInstance3D:
	return _beam


## `true` mientras el haz esté encendido. [VFXPool] lo usa para saber si sus
## emisores cuentan contra el presupuesto.
func is_playing() -> bool:
	return _lit


func _on_stop() -> void:
	set_lit(false)


## Material de shader del cilindro, con copia propia por instancia para que dos
## haces del mismo `.tscn` puedan tener colores distintos.
func _shader_material() -> ShaderMaterial:
	if _beam == null:
		return null
	var material := _beam.material_override as ShaderMaterial
	if material != null:
		return material
	var source := _beam.mesh.surface_get_material(0) as ShaderMaterial
	if source == null:
		return null
	material = source.duplicate() as ShaderMaterial
	_beam.material_override = material
	return material
