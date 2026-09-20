## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Ficha de un ataque de enemigo (`docs/06` §3).
##
## **WP-16 entrega sólo el `Resource`**: los nodos `EnemyAction`, la máquina de
## estados de dos capas, la telegrafía y la resolución por barrido son WP-19
## (`docs/06` §11). Acá viven los campos para que `EnemyProfile.attacks` y los
## `unlock_attacks` de las fases se puedan declarar desde ya, aunque todavía no
## haya nadie que los ejecute.
class_name AttackProfile extends Resource

## A qué apunta el ataque (`docs/06` §3).
enum TargetKind {
	DRONE,        ## Al dron del jugador.
	BUILDING,     ## A un edificio de la ciudad.
	SELF,         ## Al propio enemigo (sacudidas, autodestrucción).
	GROUND_POINT, ## A un punto del suelo (pisotones, ondas).
}

## Id estable del ataque; es la clave de `unlock_attacks`, `lock_attacks` y de
## los pesos de utilidad por fase.
@export var attack_id: StringName = &""

## Clave de traducción `ATK_*` para el aviso del HUD.
@export var display_key: String = ""

## Aviso previo, en segundos. Ninguna acción dañina puede pasar a `ACTIVE` con
## menos de **0.80 s** efectivos tras los multiplicadores de fase (`docs/06` §6.1).
@export_range(0.0, 10.0, 0.05) var windup: float = 0.9

## Ventana activa en la que el ataque hace daño.
@export_range(0.0, 30.0, 0.05) var active: float = 0.5

## Recuperación tras la ventana activa: la ventana de daño del jugador.
@export_range(0.0, 30.0, 0.05) var recover: float = 1.0

## Tiempo mínimo entre dos usos del mismo ataque.
@export_range(0.0, 120.0, 0.1) var cooldown: float = 8.0

## Objetivo del ataque.
@export var target_kind: TargetKind = TargetKind.DRONE

## Distancia mínima al objetivo para que el ataque sea elegible.
@export_range(0.0, 500.0, 0.5) var min_range: float = 0.0

## Distancia máxima al objetivo para que el ataque sea elegible.
@export_range(0.0, 500.0, 0.5) var max_range: float = 40.0

## Si la locomoción se bloquea mientras dura `TELEGRAPH` + `ACTIVE`.
@export var lock_locomotion: bool = true

## Partes que deben estar sanas para poder usar el ataque.
@export var requires_parts: PackedStringArray = PackedStringArray()

## Partes cuya rotura deja el ataque fuera del selector.
@export var disabled_if_broken: PackedStringArray = PackedStringArray()

## Daño al casco del dron (`docs/09`).
@export_range(0.0, 1000.0, 1.0) var damage_drone: float = 0.0

## Daño a los edificios alcanzados (`docs/10`).
@export_range(0.0, 10000.0, 1.0) var damage_building: float = 0.0

## Si el daño se aplica por segundo en vez de una sola vez por ventana activa.
@export var damage_per_second: bool = false

## Impulso al dron, en N·s. La resolución lo recorta a 120 N·s (`docs/06` §11.3).
@export_range(0.0, 500.0, 1.0) var impulse_drone: float = 0.0

## Volumen de la consulta `intersect_shape` de la ventana activa.
@export var query_shape: Shape3D = null

## Capas que barre la consulta: 2 (`drone`) y 8 (`city`) por defecto.
@export_flags_3d_physics var query_layers: int = 130

## Cada cuánto se repite la consulta durante la ventana activa.
@export_range(0.01, 1.0, 0.01) var query_interval: float = 0.05

## [TelegraphProfile] del ataque: los tres canales del aviso (`docs/06` §3 y
## §11.2). Sin él, el [Telegraph] cae en su anillo de suelo y en el barrido
## genérico `charge.wav`, que es lo que hacen las acciones de locomoción.
@export var telegraph: TelegraphProfile = null

## Curva de utilidad del ataque, alimentada por [member score_input] (`docs/06` §10.2).
@export var score_curve: Curve = null

## Clave del contexto que alimenta [member score_curve] (`docs/06` §10.1).
@export var score_input: StringName = &"distance"

## Peso base del ataque antes de la personalidad y de la fase.
@export_range(0.0, 10.0, 0.05) var base_weight: float = 1.0

## Banco de audio del `AudioRig` (`docs/07` §10).
@export var audio_bank: StringName = &""
