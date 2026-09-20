## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ficha completa de un enemigo (`docs/06` §3).
##
## Es el único lugar donde vive el balance: [member part_overrides] pisa lo que
## el GLB trajo por metadatos, [member weak_points] declara las condiciones de
## exposición y [member phases] el guion de la pelea. [EnemyBase] no tiene
## ningún número propio.
class_name EnemyProfile extends Resource

## Id estable de catálogo. Es la clave de [EnemyCatalog] y no se renombra nunca.
@export var enemy_id: StringName = &""

## Clave de traducción `ENEMY_*` del nombre visible.
@export var display_key: String = ""

## Blindaje que se aplica si el import no declara `armor` en una parte.
@export_range(0.0, 0.99, 0.01) var armor_default: float = 0.90

## Velocidad de marcha en llano, en m/s.
@export_range(0.0, 60.0, 0.1) var walk_speed: float = 6.0

## Velocidad de giro del cuerpo, en grados por segundo.
@export_range(1.0, 360.0, 0.5) var turn_rate: float = 25.0

## Tope duro de desplazamiento por tick de física, en metros. Es la defensa
## contra el *tunneling* de Jolt (`docs/06` §7 punto 3 y §17 riesgo 1).
@export_range(0.05, 5.0, 0.05) var max_step_per_tick: float = 0.6

## Altura de la cadera sobre la media de los pies apoyados, en metros.
@export_range(0.0, 80.0, 0.1) var hip_height: float = 14.0

## Duración del tambaleo que provoca romper una parte, en segundos.
@export_range(0.0, 10.0, 0.05) var stagger_seconds: float = 0.9

## Penalización de velocidad por pata perdida, como fracción.
@export_range(0.0, 1.0, 0.01) var leg_speed_penalty: float = 0.15

## Patas perdidas a partir de las cuales el enemigo queda `DOWNED`.
@export_range(1, 12) var downed_legs_lost: int = 4

## Vida de los escombros desprendidos, en segundos, antes de fundirse en el
## `RubbleField` (`docs/10` §6).
@export_range(1.0, 120.0, 0.5) var debris_lifetime: float = 20.0

## Velocidad inicial que se imprime al escombro al desprenderse, en m/s. El
## impulso resultante es `masa · detach_speed`, de modo que una antena de 250 kg
## y un fémur de 42 t salen a la misma velocidad.
@export_range(0.0, 40.0, 0.1) var detach_speed: float = 3.0

## Overrides de balance por parte: `part_id` (`StringName`) → [EnemyPartProfile].
## **El import es el valor por defecto; esto es la fuente de verdad**
## (`docs/06` §2.1 punto 7).
@export var part_overrides: Dictionary = {}

## Puntos débiles del enemigo, uno por `weak_point_id` del GLB.
@export var weak_points: Array[WeakPointProfile] = []

## Ajustes del rig de patas (WP-17).
@export var leg_rig: LegRigProfile = null

## `PerceptionProfile` (WP-18). Se declara como [Resource] porque esa clase la
## entrega WP-18 y tiparla ahora obligaría a crear un recurso vacío.
@export var perception: Resource = null

## Ataques del enemigo, en el mismo orden que los nodos de `AttackLibrary` (WP-19).
@export var attacks: Array[AttackProfile] = []

## Guion de fases, ordenado y monótono (`docs/06` §6.1). Cada entrada es
## `{"id": StringName, "when": Dictionary, "then": Dictionary}`.
@export var phases: Array[Dictionary] = []

## Dispersión de la personalidad por ataque, ±fracción (WP-18).
@export_range(0.0, 1.0, 0.01) var personality_spread: float = 0.30

## Frecuencia del selector de utilidad, en Hz (WP-18).
@export_range(0.5, 60.0, 0.5) var decision_hz: float = 4.0

## Cuántas acciones entran en el muestreo ponderado (WP-18).
@export_range(1, 16) var top_n: int = 3

## Color base de los emisivos de carcasa; las fases lo pisan con
## `then.emissive_color`.
@export var body_material_emissive: Color = Color(0.0, 1.0, 1.0)


## Override de balance de [param part_id], o `null` si esa parte no tiene ninguno.
func override_for(part_id: StringName) -> EnemyPartProfile:
	var entry: Variant = part_overrides.get(part_id, null)
	if entry == null:
		# Un `.tres` editado a mano puede haber guardado la clave como `String`.
		entry = part_overrides.get(String(part_id), null)
	return entry as EnemyPartProfile


## Perfil del punto débil [param weak_point_id], o `null` si no está declarado.
func weak_point_for(weak_point_id: StringName) -> WeakPointProfile:
	for profile: WeakPointProfile in weak_points:
		if profile != null and profile.weak_point_id == weak_point_id:
			return profile
	return null
