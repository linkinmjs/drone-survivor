## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Configuración de un punto débil (`docs/06` §3 y §5).
##
## Vive en [member EnemyProfile.weak_points] y se empareja con el `weak_point_id`
## que el importador escribió en la malla. Describe **cuándo** el punto débil
## queda expuesto (capa 4, emisivo encendido), cuánto aguanta y qué pasa al
## romperlo, todo de forma declarativa: [WeakPoint] no tiene lógica propia por
## enemigo.
class_name WeakPointProfile extends Resource

## Id del punto débil, igual al metadato `weak_point_id` del GLB.
@export var weak_point_id: StringName = &""

## Parte que lo hospeda (`docs/07` §4: la tibia de la rodilla, el `hull` del
## visor, el `underbelly` de los núcleos). Define el origen y los ejes del cono
## de [constant WeakPoint.Exposure.ANGLE_CONE]. Vacío = el padre de la parte
## débil en el grafo.
@export var host_part_id: StringName = &""

## Puntos de vida del punto débil. La parte que los recibe lleva `armor 0.0`,
## así que el daño que pasa el arma entra entero (`docs/07` §4).
@export_range(1.0, 100000.0, 1.0, "or_greater") var hp: float = 1200.0

## Multiplicador de daño del punto débil. **Lo aplica el arma** (`docs/08` §2.7),
## no [EnemyPart]: por eso un disparo de 12 vale 36 y no 3.6.
@export_range(1.0, 10.0, 0.1) var damage_multiplier: float = 3.0

## Condiciones de exposición, como valores de [enum WeakPoint.Exposure]:
## 0 `ALWAYS`, 1 `WHILE_ATTACK`, 2 `AFTER_PARTS`, 3 `ANGLE_CONE`, 4 `TIMED`.
##
## Se declaran como enteros y no como el `enum` para que este recurso no tenga
## que referenciar a [WeakPoint]: el nodo ya depende de este perfil y la
## referencia cruzada sería cíclica.
@export var conditions: Array[int] = [0]

## `true` exige **todas** las condiciones (es el caso del núcleo ventral:
## `AFTER_PARTS` **y** `ANGLE_CONE`); `false` se conforma con una.
@export var require_all: bool = true

## Ids que [constant WeakPoint.Exposure.AFTER_PARTS] vigila. Pueden ser partes o
## puntos débiles: se considera roto lo que tenga `hp <= 0`.
@export var after_parts_ids: PackedStringArray = PackedStringArray()

## Cuántas de [member after_parts_ids] hacen falta. `0` las exige todas. Si
## [member after_parts_ids] está vacío, cuenta partes estructurales cualesquiera
## (`structure_weight > 0`), que es la forma literal de `docs/06` §5.
@export_range(0, 64) var after_parts_count: int = 0

## Eje del cono de exposición, en espacio local del hospedador. `DOWN` es «hay
## que mirarlo desde abajo».
@export var cone_axis: Vector3 = Vector3.DOWN

## Semiapertura del cono en grados. `35°` son los «70° de apertura» de
## `docs/07` §4.
@export_range(0.0, 180.0, 0.5) var cone_half_angle: float = 35.0

## Periodo del parpadeo de [constant WeakPoint.Exposure.TIMED], en segundos.
@export_range(0.0, 60.0, 0.05) var timed_period: float = 0.0

## Fracción del periodo en la que el punto débil está expuesto, de 0 a 1.
@export_range(0.0, 1.0, 0.01) var timed_duty: float = 0.0

## Color del emisivo cuando está expuesto.
@export var emissive_color: Color = Color(0.0, 1.0, 1.0)

## Energía del emisivo cuando está expuesto; 0 cuando no lo está.
@export_range(0.0, 32.0, 0.1) var emissive_energy: float = 3.0

## El volumen del hospedador **tapa** el del punto débil, y mientras éste esté
## expuesto hay que dejar pasar el disparo a través de él.
##
## Hace falta cuando el modelo mete el punto débil **dentro** de la caja de su
## hospedador en vez de dejarlo sobresalir. Medido en WP-23 sobre los tres núcleos
## ventrales del Arachnodroid: el `underbelly` ocupa y ∈ [6.50, 14.00] y los tres
## `wp_core_*` y ∈ [12.50, 14.00] con x y z **por dentro**, así que un disparo desde
## abajo choca con la panza seis metros antes de llegar al núcleo, los núcleos no se
## pueden romper y la ronda no se puede ganar. Con esto en `true`, la capa
## `enemy_body` del hospedador se apaga mientras alguno de sus puntos débiles esté
## expuesto y se vuelve a encender cuando ninguno lo está.
##
## Es un **parche de balance**: la solución de fondo es que `docs/05` saque las
## cajas de los núcleos por debajo de la cara inferior de la panza (WP-24).
@export var pierces_host: bool = false

## Clave de traducción `WP_*` para el marcador del `CombatHUD` (`docs/12`).
@export var hud_key: String = ""

## Efectos declarativos al romperse, que ejecuta [EnemyBase] (`docs/06` §3):
## `detach_part: StringName`, `blind_seconds: float`,
## `lock_attacks: PackedStringArray` + `lock_seconds: float` y
## `stagger_seconds: float`. Las claves desconocidas se ignoran sin ruido: son
## marcas declarativas que consumen otros sistemas (el `staged` de los núcleos
## del Arachnodroid lo leen las fases, `docs/07` §6).
@export var on_destroy: Dictionary = {}
