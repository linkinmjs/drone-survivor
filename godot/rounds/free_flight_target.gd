## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Blanco de prueba del nivel de vuelo libre (WP-14).
##
## Es lo mínimo que el resolvedor de impactos del arma le pide a un edificio:
## estar en la **capa 8** (`city`) y tener `take_damage(amount: float, point: Vector3)`.
## `ProjectilePool` lo llama por **duck typing**, sin conocer ningún tipo: el
## `Building` de verdad es de WP-20 (`docs/10`) y todavía no existe.
##
## Lo único que agrega sobre el contrato es realimentación visual, para que el
## piloto vea que le está pegando: el bloque se oscurece y se encoge a medida que
## pierde estructura, y al llegar a cero se apaga. No hay escombros, ni etapas, ni
## integridad de ciudad: todo eso es de `docs/10` y no se adelanta acá.
##
## No pertenece al sistema de ciudad y no hereda nada de él a propósito: cuando
## WP-20 entregue `Building`, este script se borra y el nivel instancia el de verdad.
class_name FreeFlightTarget extends StaticBody3D

## Estructura inicial. Con 6 de daño por impacto (`docs/08` §2.7), 300 son 50
## impactos: unos 12 s de fuego sostenido, suficiente para notar el progreso sin
## que el bloque se evapore.
@export var structure: float = 300.0

## Color del bloque intacto.
@export var intact_color: Color = Color(0.42, 0.46, 0.52)

## Color del bloque a punto de caer.
@export var ruined_color: Color = Color(0.16, 0.13, 0.11)

## Fracción de la escala original que conserva un bloque agotado.
@export_range(0.1, 1.0) var ruined_scale: float = 0.55

var _max_structure: float = 1.0
var _base_scale: Vector3 = Vector3.ONE
var _material: StandardMaterial3D = null
var _mesh: MeshInstance3D = null


func _ready() -> void:
	_max_structure = maxf(structure, 0.0001)
	_base_scale = scale
	_mesh = get_node_or_null(^"Mesh") as MeshInstance3D
	if _mesh == null:
		return
	# Material propio por instancia: los tres blancos comparten la malla del
	# `.tscn` y sin esto el primer impacto teñiría a los tres.
	_material = StandardMaterial3D.new()
	_material.albedo_color = intact_color
	_material.roughness = 0.85
	_material.metallic_specular = 0.3
	_mesh.material_override = _material
	_refresh()


## Contrato de `Building.take_damage(amount, point)` (`docs/10` §5). El punto de
## impacto no se usa todavía: lo pide la firma y lo usará WP-20 para elegir qué
## trozo se desprende.
func take_damage(amount: float, _point: Vector3) -> void:
	if structure <= 0.0:
		return
	structure = maxf(structure - amount, 0.0)
	_refresh()
	if structure <= 0.0:
		# Sin estructura deja de existir para la física: el rayo del arma lo
		# atraviesa y las balas siguen hasta lo que haya detrás.
		visible = false
		collision_layer = 0


## Fracción de estructura restante, de 1.0 a 0.0.
func structure_ratio() -> float:
	return clampf(structure / _max_structure, 0.0, 1.0)


func _refresh() -> void:
	var ratio := structure_ratio()
	if _material != null:
		_material.albedo_color = ruined_color.lerp(intact_color, ratio)
	scale = _base_scale * lerpf(ruined_scale, 1.0, ratio)
