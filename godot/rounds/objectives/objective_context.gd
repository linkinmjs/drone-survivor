## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Lo que un [Objective] necesita saber del nivel que lo hospeda (`docs/11` §4.2).
##
## El framework de objetivos viene del simulador de vuelo, donde cada lección
## recibía el nivel entero y se servía sola de sus propiedades. Acá el nivel es un
## [BattleLevel] con distrito, ciudad y enemigos, y los objetivos no deben conocerlo:
## reciben **esta** bolsa de referencias, que arma [RoundManager] una sola vez y pasa
## al secuenciador con `setup(ctx)`.
##
## Es un [RefCounted] a propósito: no vive en el árbol, no se libera con nadie y
## cualquier objetivo puede guardárselo sin crear un ciclo de referencias con nodos.
##
## [member round_manager] se declara como [Node] y no como `RoundManager` para no
## cerrar el ciclo `RoundManager → ObjectiveSequencer → Objective → ObjectiveContext`,
## que el analizador de GDScript resuelve mal. Quien lo necesite tipado que lo
## convierta en el momento.
class_name ObjectiveContext extends RefCounted

## Nivel jugable que hospeda la ronda. En el MVP siempre es `battle_level.tscn`.
var level: LevelBase = null

## Conjunto del dron: cámara FPV, HUD de vuelo, arma, energía, casco y respawn.
var drone_rig: DroneRig = null

## Cuerpo del dron. Es `drone_rig.get_drone()`, cacheado para no repetirlo por tick.
var drone: Drone = null

## Máquina de estados de la ronda ([RoundManager]). Tipado flojo a propósito.
var round_manager: Node = null

## Integridad de la ciudad del nivel (`docs/10` §5).
var city_integrity: CityIntegrity = null

## Enemigos instanciados por [member round_manager], en orden de aparición.
var enemies: Array[EnemyBase] = []


## Controlador de vuelo del dron, o `null` si el rig todavía no lo cableó.
func flight_controller() -> FlightController:
	if drone_rig == null or not is_instance_valid(drone_rig):
		return null
	return drone_rig.get_flight_controller()


## Controlador de reaparición del dron, o `null` si el rig no lo tiene.
func respawn_controller() -> RespawnController:
	if drone_rig == null or not is_instance_valid(drone_rig):
		return null
	return drone_rig.get_respawn_controller()


## Primer enemigo vivo del contexto, o `null` si no queda ninguno. Es lo que miran
## los objetivos del MVP, que pelean contra un solo coloso.
func first_enemy() -> EnemyBase:
	for enemy: EnemyBase in enemies:
		if is_instance_valid(enemy):
			return enemy
	return null


## Integridad de la ciudad de 0.0 a 1.0; 1.0 si el nivel no tiene [CityIntegrity].
func integrity() -> float:
	if city_integrity == null or not is_instance_valid(city_integrity):
		return 1.0
	return city_integrity.get_ratio()
