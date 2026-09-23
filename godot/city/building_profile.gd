## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Datos de un tipo de edificio (`docs/10` §9.2).
##
## Es el único lugar donde viven los números de la destrucción: HP, umbrales de
## etapa, cuántos escombros se desprenden y con qué masa, cuánto dura el
## derrumbe, cuánto trauma publica cada transición y qué mallas de ruina usa.
## Un [Building] no inventa ningún valor propio; si el perfil falta, cae en los
## valores por defecto de este recurso, que son los del bloque bajo.
##
## WP-20 entrega **dos** perfiles, `city/profiles/low_block.tres` y
## `city/profiles/tower.tres`, en lugar de los cuatro que enumera `docs/10` §9.2
## (`block_low`, `block_mid`, `tower_a`, `tower_b`): los cuatro sólo se
## diferenciaban en pares de valores idénticos (1 200/1 200 y 3 500/3 500), así
## que la variedad la aporta la pieza y la escala de altura, no el perfil.
class_name BuildingProfile extends Resource

## Id de catálogo. Es para siempre: lo usan el check y los informes de ronda.
@export var id: StringName = &"low_block"

## Puntos de estructura del edificio intacto (`docs/10` §4.2).
@export_range(1.0, 50000.0, 1.0) var max_hp: float = 1200.0

## Umbral de `INTACT` → `DAMAGED`, en fracción de [member max_hp].
@export_range(0.0, 1.0, 0.01) var damaged_threshold: float = 0.60

## Umbral de `DAMAGED` → `RUBBLE`, en fracción de [member max_hp]. Al cruzarlo el
## HP se pone en cero, de modo que la integridad de una ciudad arrasada vale
## exactamente 0.0 y el coste efectivo de derribar es el 85 % del nominal.
@export_range(0.0, 1.0, 0.01) var rubble_threshold: float = 0.15

## Peso del edificio en el puntaje de la ronda (`docs/11` §7).
@export_range(0, 10000, 1) var value: int = 100

## Trozos que se desprenden en cada transición de etapa (`docs/10` §10: 4–8).
@export_range(0, 32, 1) var debris_count_min: int = 4
@export_range(0, 32, 1) var debris_count_max: int = 8

## Masa de cada trozo, en kilogramos. Fija el daño al dron (`docs/09`) y decide
## la detección continua de colisión (`DebrisChunk.continuous_cd_mass`).
@export_range(1.0, 10000.0, 1.0) var debris_mass: float = 450.0

## Impulso vertical y radial con el que salen los trozos, en N·s por kg.
@export_range(0.0, 40.0, 0.1) var debris_impulse: float = 6.0

## Escala del polvo del derrumbe. 1.0 es un bloque bajo (`docs/06` §4.1 punto 6).
@export_range(0.0, 5.0, 0.05) var dust_scale: float = 1.0

## Segundos que dura la animación de derrumbe (`docs/10` §10).
@export_range(0.1, 10.0, 0.05) var collapse_seconds: float = 1.8

## Segundos que la columna de humo sigue emitiendo tras el derrumbe. Pasado ese
## tiempo libera su plaza del presupuesto de emisores (`docs/13` §7).
@export_range(0.0, 120.0, 0.5) var smoke_seconds: float = 12.0

## Ventana deslizante del daño reciente, en segundos (`docs/10` §5). Sin daño
## durante este tiempo el edificio deja de estar «bajo asedio».
@export_range(0.5, 30.0, 0.1) var siege_window: float = 3.0

## Daño mínimo acumulado en la ventana para que el edificio pueda marcarse como
## el que está bajo asedio.
@export_range(0.0, 5000.0, 1.0) var siege_damage: float = 150.0

## Trauma de cámara al entrar en `DAMAGED` (`Events.camera_trauma`).
@export_range(0.0, 2.0, 0.01) var trauma_damaged: float = 0.65

## Trauma de cámara al entrar en `RUBBLE`. Una torre que cae se siente más que
## un boquete en la fachada.
@export_range(0.0, 2.0, 0.01) var trauma_rubble: float = 0.85

## Fracción de la altura que conserva el colisionador de la ruina
## (`docs/10` §10). Se recorta además a [member rubble_height_max] para que una
## torre de 45 m no deje un muro de 8 m en pie.
@export_range(0.0, 1.0, 0.01) var rubble_height_factor: float = 0.18

## Altura máxima del colisionador de la ruina, en metros.
@export_range(0.5, 20.0, 0.1) var rubble_height_max: float = 3.0

## Fracción de la altura que se hunde el edificio durante el derrumbe.
@export_range(0.0, 1.0, 0.01) var collapse_sink: float = 0.35

## Montículos de ruina, normalizados a una caja de 1 × 1 × 1 m con la base en
## `y = 0`. [Building] elige uno por tamaño y lo escala a su huella. Opcional: si
## queda vacío, la etapa `RUBBLE` no dibuja pila.
@export var rubble_meshes: Array[Mesh] = []

## Malla del trozo de escombro. **Debe ser compartida** por todos los edificios
## del mismo perfil: el [RubbleField] abre un [MultiMeshInstance3D] por malla
## distinta y sólo admite cuatro (`docs/10` §6).
@export var debris_mesh: Mesh = null

## Forma de colisión del trozo, a juego con [member debris_mesh].
@export var debris_shape: Shape3D = null

## Shader de la etapa `DAMAGED` para esta familia de piezas. Si queda en `null`
## se usa `city/damage_overlay.gdshader`, que es el de la ciudad y muestrea la
## difusa con filtro lineal y mipmaps. Las piezas del pueblo de ruta
## (`assets/town/`) llevan en cambio la paleta de 256×1 del pipeline voxel, donde
## el vecino de un texel es otro color sin relación: para ésas el perfil apunta a
## `city/damage_overlay_palette.gdshader`, idéntico salvo por
## `filter_nearest, repeat_disable` (WP-A).
@export var damage_shader: Shader = null


## Cantidad de trozos de esta transición, sembrada con [param rng] para que dos
## corridas con la misma semilla tiren lo mismo.
func roll_debris_count(rng: RandomNumberGenerator) -> int:
	var low := mini(debris_count_min, debris_count_max)
	var high := maxi(debris_count_min, debris_count_max)
	if high <= 0:
		return 0
	return rng.randi_range(low, high)


## Montículo de ruina para un edificio de [param height] metros. Devuelve `null`
## si el perfil no trae mallas.
func pick_rubble_mesh(height: float) -> Mesh:
	if rubble_meshes.is_empty():
		return null
	# Tres tramos: hasta 14 m el montículo bajo, hasta 28 m el medio, y el alto
	# para las torres. Con menos de tres mallas se recorta al índice disponible.
	var tier := 0
	if height > 28.0:
		tier = 2
	elif height > 14.0:
		tier = 1
	return rubble_meshes[mini(tier, rubble_meshes.size() - 1)]
