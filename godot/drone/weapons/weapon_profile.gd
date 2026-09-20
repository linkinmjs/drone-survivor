## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Todos los números del arma primaria en un [Resource] (`docs/08` §3.3).
##
## La razón de que esto sea un recurso y no constantes en [WeaponMount] es el
## balance: WP-23 ajusta cadencia, daño, calor y retroceso sin recompilar nada y
## sin tocar una sola línea de lógica. El recurso del MVP vive en
## `res://drone/weapons/profiles/default_gun.tres` con los valores cerrados del
## Anexo C (`docs/08` §4).
##
## **Quién aplica qué factor** (`docs/08` §2.7, regla que no se puede invertir):
## el arma aplica [member weak_point_multiplier] y [member city_friendly_fire_scale];
## el blindaje lo aplica `EnemyPart` (`docs/06`). Nunca los dos el mismo factor.
##
## Discrepancias registradas con la tabla de `docs/08` §3.3:
## - [member aim_assist_max_range] se declara con rango `0–600`, no `0–60`: el
##   valor por defecto que fija el propio documento son **220 m**, que no entra en
##   el rango escrito. Es una errata de la tabla.
## - Se agregan [member aim_assist_strength_assisted], [member lock_break_angle] y
##   [member lock_break_range], que `docs/08` §2.8 y §4 fijan como propuestas
##   cerradas (0.60, 35° y 250 m) pero que la tabla de §3.3 se olvidó de listar.
##   Sin ellos el lock no se puede romper por ángulo ni por distancia.
## - Se agrega [member muzzle_offset], los 0.35 m de §2.2 y §4, que la tabla
##   tampoco lista.
class_name WeaponProfile extends Resource

## Id estable del arma; es clave de guardado, así que no cambia nunca.
@export var id: StringName = &"mk1_repeater"

## Clave de traducción del nombre visible (`WPN_`, `docs/02` §6.2).
@export var display_key: String = "WPN_MK1_REPEATER"

# --- Ciclo de disparo ------------------------------------------------------------------------

## Disparos por segundo. El intervalo del acumulador es `1 / fire_rate`.
@export_range(0.5, 30.0) var fire_rate: float = 8.0

## Daño base por impacto, antes del blindaje del enemigo.
@export_range(0.0, 200.0) var damage: float = 12.0

## Multiplicador que **aplica el arma** al impactar en la capa 4 (`enemy_weak`).
@export_range(1.0, 10.0) var weak_point_multiplier: float = 3.0

## Velocidad del proyectil, en m/s. A 420 m/s y 100 Hz el paso es de 4.2 m.
@export_range(50.0, 2000.0) var projectile_speed: float = 420.0

## Alcance máximo, en metros. El `ttl` inicial es `max_range / projectile_speed`.
@export_range(10.0, 2000.0) var max_range: float = 600.0

# --- Dispersión ------------------------------------------------------------------------------

## Semiángulo del cono de dispersión en frío, en grados.
@export_range(0.0, 10.0) var spread_base_deg: float = 0.35

## Crecimiento de la dispersión por segundo de ráfaga sostenida, en grados.
@export_range(0.0, 10.0) var spread_growth_deg: float = 0.9

## Tope de la dispersión, en grados.
@export_range(0.0, 15.0) var spread_max_deg: float = 2.2

## Con el gatillo suelto el tiempo de ráfaga se descuenta a este múltiplo del
## tiempo real: con 3.0 la ráfaga se «olvida» en ~0.7 s.
@export_range(0.0, 20.0) var spread_decay_factor: float = 3.0

# --- Calor -----------------------------------------------------------------------------------

## Calor que suma cada disparo, sobre 1.0. Con 0.045 el bloqueo llega al disparo 23.
@export_range(0.0, 1.0) var heat_per_shot: float = 0.045

## Enfriado base, en unidades de calor por segundo. Sólo corre con el gatillo
## suelto o durante el bloqueo (`docs/08` §2.4).
@export_range(0.0, 5.0) var heat_cooldown: float = 0.40

## Enfriado extra por debajo de [member heat_cooldown_bonus_threshold].
@export_range(0.0, 5.0) var heat_cooldown_bonus: float = 0.15

## Umbral de calor por debajo del cual se suma [member heat_cooldown_bonus].
@export_range(0.0, 1.0) var heat_cooldown_bonus_threshold: float = 0.30

## Duración mínima del bloqueo por sobrecalentamiento, en segundos.
@export_range(0.0, 10.0) var overheat_lock: float = 1.8

## Calor al que hay que bajar para salir del bloqueo, además de agotar
## [member overheat_lock].
@export_range(0.0, 1.0) var overheat_release: float = 0.35

# --- Coste y retroceso -----------------------------------------------------------------------

## Energía por disparo, en puntos de la escala 0–100 de `docs/09`.
@export_range(0.0, 10.0) var energy_per_shot: float = 0.45

## Impulso del retroceso, en N·s. Se aplica como `-aim_dir * recoil_impulse`.
@export_range(0.0, 20.0) var recoil_impulse: float = 0.9

## Distancia del `Muzzle` por delante de la cámara, en metros, para que el rayo
## no arranque dentro del casco (`docs/08` §2.2).
@export_range(0.0, 3.0) var muzzle_offset: float = 0.35

# --- Asistencia de puntería ------------------------------------------------------------------

## Semiángulo del cono de asistencia, en grados.
@export_range(0.0, 20.0) var aim_assist_cone_deg: float = 3.5

## Corrección del modo `subtle` (`GameSettings.AimAssist.SUBTLE`), de 0 a 1.
@export_range(0.0, 1.0) var aim_assist_strength: float = 0.35

## Corrección del modo `assisted` (`GameSettings.AimAssist.ASSISTED`), de 0 a 1.
@export_range(0.0, 1.0) var aim_assist_strength_assisted: float = 0.60

## Alcance máximo de la asistencia, en metros.
@export_range(0.0, 600.0) var aim_assist_max_range: float = 220.0

## Semiángulo del cono ampliado con el que `lock_target` y `cycle_target` buscan
## candidatos, en grados.
@export_range(0.0, 45.0) var lock_cone_deg: float = 12.0

## Ángulo a partir del cual se rompe el lock, en grados.
@export_range(0.0, 180.0) var lock_break_angle: float = 35.0

## Distancia a partir de la cual se rompe el lock, en metros.
@export_range(0.0, 1000.0) var lock_break_range: float = 250.0

# --- Presentación y pool ---------------------------------------------------------------------

## Uno de cada `tracer_every` disparos lleva trazador.
@export_range(1, 12) var tracer_every: int = 3

## Proyectiles preasignados en el pool.
@export_range(16, 512) var pool_size: int = 256

## Escala del daño que el jugador le hace a la ciudad (capa 8).
@export_range(0.0, 2.0) var city_friendly_fire_scale: float = 0.5

## Impulso que un impacto le transmite a un escombro de la capa 9, en N·s.
@export_range(0.0, 10.0) var debris_impulse: float = 0.6

# --- Máscaras de física (`docs/02` §3.3) -----------------------------------------------------

## Máscara del rayo del proyectil: `world | enemy_body | enemy_weak | city | debris`.
## La capa 2 (`drone`) **no** está: el dron es inmune a su fuego por construcción.
@export_flags_3d_physics var hit_mask: int = PhysicsLayers.QUERY_SHOT

## Máscara de la línea de visión de la asistencia: `world | city`.
@export_flags_3d_physics var los_mask: int = PhysicsLayers.QUERY_LOS

# --- Recursos de presentación ----------------------------------------------------------------

## Escena del destello de boca; la instancia [WeaponMount] si el nodo no está.
@export var muzzle_flash_scene: PackedScene

## Escena de una instancia del pool de impactos.
@export var impact_fx_scene: PackedScene

## Sonido del disparo, en el bus `Weapons`.
@export var fire_sound: AudioStream

## Sonido del bloqueo por sobrecalentamiento.
@export var overheat_sound: AudioStream

## Sonido del impacto, posicional.
@export var impact_sound: AudioStream


## Intervalo entre disparos, en segundos. Es `1 / fire_rate` con guarda de división
## por cero.
func shot_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.001)


## Tiempo de vuelo máximo de un proyectil, en segundos (`docs/08` §2.6).
func projectile_ttl() -> float:
	return max_range / maxf(projectile_speed, 0.001)


## Dispersión, en grados, tras [param burst_time] segundos de ráfaga sostenida.
func spread_at(burst_time: float) -> float:
	return minf(spread_max_deg, spread_base_deg + spread_growth_deg * maxf(burst_time, 0.0))


## Enfriado instantáneo, en unidades de calor por segundo, para el [param heat] dado.
func cooldown_at(heat: float) -> float:
	if heat < heat_cooldown_bonus_threshold:
		return heat_cooldown + heat_cooldown_bonus
	return heat_cooldown
