## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Todos los números del casco y del respawn en un [Resource] (`docs/09` §3.5).
##
## Igual que [EnergyProfile] y `WeaponProfile`: WP-23 ajusta la dureza del dron, la
## curva de daño por choque y el castigo por morir sin tocar una línea de lógica.
## El recurso del MVP vive en `res://drone/damage/profiles/default_hull.tres`.
##
## El bloque de respawn vive acá y no en un tercer recurso porque los tres valores
## —duración, multiplicador y piso— son la penalización por morir, y morir es lo
## que decide este perfil.
class_name HullProfile extends Resource

## Integridad máxima del casco.
@export_range(1.0, 1000.0) var max_hp: float = 100.0

# --- Choque (`docs/09` §2.6) ------------------------------------------------------------------

## Velocidad relativa bajo la cual un contacto no hace daño, en m/s. Cubre
## aterrizajes y roces.
@export_range(0.0, 50.0) var impact_speed_threshold: float = 8.0

## Daño por cada m/s de velocidad relativa **por encima** del umbral.
@export_range(0.0, 50.0) var impact_damage_per_ms: float = 4.0

## Segundos que un mismo cuerpo no puede volver a dañar el casco.
##
## Jolt reemite `body_entered` en contactos rasantes; sin esta guarda un rozón
## contra una pared se cobraría cinco o seis veces.
@export_range(0.0, 5.0) var impact_cooldown: float = 0.35

## Daño mínimo que se aplica. Por debajo se descarta el golpe entero, que es el
## ruido de los roces (`docs/09` §4).
@export_range(0.0, 20.0) var min_impact_damage: float = 1.0

# --- Escombro (`docs/09` §2.7) ----------------------------------------------------------------

## Daño de un `DebrisChunk` de [member debris_mass_min] kg o menos.
@export_range(0.0, 200.0) var debris_damage_min: float = 15.0

## Daño de un `DebrisChunk` de [member debris_mass_max] kg o más.
@export_range(0.0, 200.0) var debris_damage_max: float = 35.0

## Masa, en kg, en la que empieza la rampa de daño por escombro.
@export_range(1.0, 10000.0) var debris_mass_min: float = 150.0

## Masa, en kg, en la que la rampa de daño por escombro llega al máximo.
@export_range(1.0, 10000.0) var debris_mass_max: float = 3000.0

# --- Muerte y respawn (`docs/09` §2.8) --------------------------------------------------------

## Segundos que el dron pasa destruido antes de reaparecer. La ciudad sigue
## sufriendo durante todo ese tiempo: esa es la penalización real.
@export_range(0.0, 60.0) var respawn_seconds: float = 12.0

## Energía con la que reaparece el dron, en la escala 0–100. Duplica
## [member EnergyProfile.respawn_energy] para que el respawn siga funcionando si
## el dron no tiene [EnergySystem]; manda el del perfil de energía cuando lo hay.
@export_range(0.0, 100.0) var respawn_energy: float = 60.0

## Factor que se aplica al multiplicador de puntaje por cada muerte. Es
## **acumulativo**: `pow(0.6, muertes)`.
@export_range(0.0, 1.0) var respawn_score_multiplier: float = 0.6

## Piso del multiplicador acumulativo. Por debajo deja de discriminar (decisión
## cerrada con `docs/11`).
@export_range(0.0, 1.0) var respawn_multiplier_floor: float = 0.3

## Trauma de cámara que pide la destrucción del dron.
@export_range(0.0, 2.0) var destroy_trauma: float = 1.0
