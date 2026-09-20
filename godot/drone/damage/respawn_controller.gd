## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Reconstrucción del dron con penalización de puntaje (`docs/09` §2.8).
##
## Se dispara por **dos motivos** ([enum Reason]), y los dos cuestan exactamente lo
## mismo —doce segundos, `Events.drone_destroyed` y el ×0.6 del multiplicador—:
##
## - `HULL`: el casco llegó a cero ([signal Hull.destroyed]). El dron vuelve con
##   [member EnergyProfile.respawn_energy] (60 %).
## - `ENERGY`: la batería llegó a cero ([signal EnergySystem.depleted]). El dron
##   vuelve con [member EnergyProfile.respawn_energy_depleted] (20 %). Es la única
##   salida del bloqueo a 0 %: desde WP-24e la recarga en reposo está apagada, así
##   que un dron sin batería ya no se rearma con el 1 % que acababa de juntar para
##   volver a caerse al frame siguiente.
##
## Es un [Node] hijo de [DroneRig] y **no** del [Drone], porque tiene que seguir
## corriendo mientras el dron está congelado e invisible. El dron **nunca se
## libera**: se desarma, se congela, se esconde, y doce segundos después se
## teletransporta al punto de reaparición y se reinicia entero.
##
## ## El mundo no se pausa
##
## Ésa es la penalización de verdad. Durante los doce segundos el jefe sigue
## derribando la ciudad y la integridad sigue bajando; `get_tree().paused` no se
## toca nunca. La cuenta va por **acumulador** en [method _physics_process]
## (`docs/09` §1), así que `energy_check` la recorre entera en milisegundos.
##
## ## Multiplicador de puntaje
##
## `maxf(piso, pow(0.6, muertes))`: 1 muerte ×0.6, 2 ×0.36, 3 o más ×0.30, que es
## el piso. Sale por tres canales, y los tres importan:
##
## - [signal respawned], señal local que [DroneRig] reexpone como
##   `DroneRig.respawned` — es la que consume `docs/11`;
## - `Events.drone_respawned(score_multiplier)`, para los consumidores
##   desacoplados (`CombatHUD`);
## - [method get_score_multiplier], para quien llegue tarde a la fiesta.
##
## ## Decisiones registradas
##
## - **Se escucha [signal Hull.destroyed], no `Events.drone_destroyed`.** Las dos
##   se emiten en el mismo instante, pero la señal local es la del casco **de este
##   rig**: con el bus, un segundo dron en escena dispararía el respawn del
##   primero. El hecho global se sigue publicando; simplemente no es por donde
##   viaja el mando. Lo mismo vale para [signal EnergySystem.depleted], que también
##   es local.
## - **Quien publica `Events.drone_destroyed` en el caso `ENERGY` es este nodo.**
##   Por el casco lo publica [method Hull.apply_damage] en el mismo instante en que
##   baja a cero; la batería no tiene un equivalente, así que la reconstrucción por
##   agotamiento lo emite acá, una sola vez, desde [method _begin].
## - **En el caso `ENERGY` el casco se desactiva, no se destruye.** El dron queda
##   congelado en el mundo con su colisionador puesto y el casco todavía vivo: un
##   barrido del jefe durante los doce segundos podría bajarlo a cero y publicar un
##   segundo `Events.drone_destroyed` por la misma reconstrucción.
##   [method Hull.deactivate] lo saca de juego sin publicar nada, y el
##   [method Hull.restore] de [method _finish] lo devuelve entero, igual que tras una
##   muerte por casco: una reconstrucción es una reconstrucción.
## - **La cámara de reconstrucción la pone el nivel.** Se busca hacia arriba el
##   primer ancestro con `get_respawn_camera()` ([LevelBase] lo implementa
##   devolviendo su `Cameras/CameraFixed`). Sin nivel que la ofrezca, la cámara no
##   se toca: un banco de pruebas no tiene por qué tener una.
class_name RespawnController extends Node

## El dron volvió a volar con [param score_multiplier] de castigo acumulado.
signal respawned(score_multiplier: float)

## El dron fue destruido y arrancó la cuenta. Lo usan los VFX del nivel.
signal respawn_started()

## Por qué arrancó la reconstrucción.
enum Reason {
	HULL,   ## El casco llegó a cero ([signal Hull.destroyed]).
	ENERGY, ## La batería llegó a cero ([signal EnergySystem.depleted]).
}

## Dron del rig. Si queda vacío se busca `Drone` entre los hermanos.
@export var drone: Drone

## Casco del dron. Si queda vacío se busca `Drone/Hull`.
@export var hull: Hull

## Batería del dron. Si queda vacía se busca `Drone/EnergySystem`.
@export var energy_system: EnergySystem

## Arma del dron; se reinicia al reaparecer. Si queda vacía se busca
## `Drone/WeaponMount`. Es un [Node] y no un `WeaponMount` para que el respawn
## siga funcionando en un rig sin arma.
@export var weapon_mount: Node

## Cámara fija sobre la ciudad. Si queda vacía se le pide al nivel con
## `get_respawn_camera()`.
@export var respawn_camera: Camera3D

## Cámara del piloto, a la que se vuelve al reaparecer. Si queda vacía se busca
## `Drone/CameraRig/FPVCamera`.
@export var fpv_camera: Camera3D

## Perfil del que salen la duración y el multiplicador. Si queda vacío se usa el
## del [member hull].
@export var profile: HullProfile

var _respawning: bool = false
var _elapsed: float = 0.0
var _deaths: int = 0
var _multiplier: float = 1.0
var _reason: Reason = Reason.HULL


func _ready() -> void:
	_resolve_nodes()
	if hull == null:
		push_error("RespawnController: no se encontró el Hull del rig %s (docs/09 §3.1)." % name)
		return
	if not hull.destroyed.is_connected(_on_hull_destroyed):
		var _discard := hull.destroyed.connect(_on_hull_destroyed)
	if energy_system != null and not energy_system.depleted.is_connected(_on_energy_depleted):
		var _discard := energy_system.depleted.connect(_on_energy_depleted)


## Cuenta atrás del respawn. Es la única lógica del nodo y va por acumulador.
func _physics_process(delta: float) -> void:
	if not _respawning or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed < _seconds():
		return
	_finish()


# --- Interfaz pública (`docs/09` §3.5) --------------------------------------------------------

## Multiplicador de puntaje vigente: 1.0 sin muertes, después `pow(0.6, muertes)`
## con piso.
func get_score_multiplier() -> float:
	return _multiplier


## Muertes acumuladas en la ronda.
func get_death_count() -> int:
	return _deaths


## `true` mientras el dron está destruido y esperando.
func is_respawning() -> bool:
	return _respawning


## Motivo de la reconstrucción en curso —o de la última, si el dron ya está
## volando—. Lo consume [HUDRespawnOverlay] para escribir «SIN BATERÍA» bajo
## «RECONSTRUYENDO» (`docs/12` §4).
func get_reason() -> Reason:
	return _reason


## Segundos que faltan para reaparecer, o 0.0 si el dron está volando.
func get_remaining_seconds() -> float:
	if not _respawning:
		return 0.0
	return maxf(_seconds() - _elapsed, 0.0)


## Alias de [method get_remaining_seconds] con el nombre de la tabla de
## `docs/09` §3.5.
func get_remaining() -> float:
	return get_remaining_seconds()


## Cancela una cuenta en curso y borra el historial de muertes. Lo llama el
## `RoundManager` (`docs/11`) al empezar una ronda.
func reset() -> void:
	_respawning = false
	_elapsed = 0.0
	_deaths = 0
	_multiplier = 1.0
	_reason = Reason.HULL


## Fuerza la secuencia de muerte sin pasar por el casco ni por la batería. Lo usa
## la demo `--energy-demo` del nivel de vuelo libre para capturar el ciclo completo
## y `combat_hud_check` para levantar el cartel.
##
## Nadie destruyó el casco, así que con [param reason] en `ENERGY` el hecho global
## sale por el mismo camino que en una reconstrucción por batería de verdad.
func force_respawn(reason: Reason = Reason.HULL) -> void:
	if _respawning:
		return
	_begin(reason)


# --- Secuencia --------------------------------------------------------------------------------

func _on_hull_destroyed() -> void:
	if _respawning:
		return
	_begin(Reason.HULL)


## La batería llegó a 0 % (`docs/09` §2.8): reconstrucción completa, igual que una
## muerte por casco.
##
## [EnergySystem] ya desarmó y bajó `can_arm_energy` antes de emitir; acá se agrega
## lo que el casco hace por su cuenta cuando muere: congelar, esconder, publicar el
## hecho global y cobrar los doce segundos.
func _on_energy_depleted() -> void:
	if _respawning:
		return
	_begin(Reason.ENERGY)


## `t = 0.00 s` de la tabla de `docs/09` §2.8: desarmar, congelar, esconder y
## pasar a la cámara de reconstrucción. El mundo sigue corriendo.
##
## Congelar el cuerpo es, además, lo que apaga el audio de motores: con `freeze` no
## corre [method Drone._integrate_forces] y las rpm quedan clavadas, así que
## [MotorAudio] trata el cuerpo congelado como régimen cero y desvanece los ocho
## loops (`docs/03` §6).
func _begin(reason: Reason) -> void:
	_respawning = true
	_reason = reason
	_elapsed = 0.0
	if reason == Reason.ENERGY:
		# El hecho global va **antes** de congelar, y da igual: su único consumidor
		# de juego es `RoundManager._on_drone_destroyed()`, que suma la muerte y
		# enfoca la misma cámara de reconstrucción que este método enfoca dos
		# líneas más abajo. No hay un cuadro dibujado en el medio.
		var at_position := drone.global_position if drone != null else Vector3.ZERO
		if hull != null:
			hull.deactivate()
		Events.drone_destroyed.emit(at_position)
	if drone != null:
		drone.force_disarm()
		drone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		drone.freeze = true
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		drone.visible = false
	_switch_camera(_resolve_respawn_camera())
	respawn_started.emit()


## `t = 12.00 s`: descongelar, teletransportar, reiniciar casco, batería y arma, y
## publicar el castigo.
##
## El orden no es libre: primero `freeze = false`, porque [method Drone.reset_to]
## deja una transformada pendiente que consume `_integrate_forces`, y un cuerpo
## congelado no llega nunca a ese callback.
func _finish() -> void:
	_respawning = false
	_elapsed = 0.0
	if drone != null:
		drone.freeze = false
		drone.visible = true
		var target := drone.respawn_point
		if target != null:
			drone.reset_to(target.global_transform)
		else:
			drone.reset_to(drone.global_transform)
		drone.reset_physics_interpolation()
	if hull != null:
		hull.restore()
	if energy_system != null:
		energy_system.reset(_respawn_energy())
	if weapon_mount != null and weapon_mount.has_method(&"reset"):
		weapon_mount.call(&"reset")
	_switch_camera(fpv_camera)

	_deaths += 1
	var factor := profile.respawn_score_multiplier if profile != null else 0.6
	var floor_value := profile.respawn_multiplier_floor if profile != null else 0.3
	_multiplier = maxf(floor_value, pow(factor, float(_deaths)))
	respawned.emit(_multiplier)
	Events.drone_respawned.emit(_multiplier)


func _switch_camera(camera: Camera3D) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	camera.current = true


func _seconds() -> float:
	return profile.respawn_seconds if profile != null else 12.0


## La energía de reaparición manda desde [EnergyProfile] y depende del motivo: 60 %
## tras una muerte por casco, 20 % tras quedarse sin batería. [HullProfile] la
## duplica solo como respaldo para un dron sin batería cableada.
func _respawn_energy() -> float:
	if energy_system != null and energy_system.profile != null:
		if _reason == Reason.ENERGY:
			return energy_system.profile.respawn_energy_depleted
		return energy_system.profile.respawn_energy
	return profile.respawn_energy if profile != null else 60.0


# --- Cableado ---------------------------------------------------------------------------------

func _resolve_nodes() -> void:
	var rig := get_parent()
	if drone == null and rig != null:
		drone = rig.get_node_or_null(^"Drone") as Drone
	if drone == null:
		return
	if hull == null:
		hull = drone.get_node_or_null(^"Hull") as Hull
	if energy_system == null:
		energy_system = drone.get_node_or_null(^"EnergySystem") as EnergySystem
	if weapon_mount == null:
		weapon_mount = drone.get_node_or_null(^"WeaponMount")
	if fpv_camera == null:
		fpv_camera = drone.get_node_or_null(^"CameraRig/FPVCamera") as Camera3D
	if profile == null and hull != null:
		profile = hull.profile


## Primer ancestro que ofrezca una cámara de reconstrucción ([LevelBase] lo hace).
## Se resuelve en cada muerte y no una vez en [method _ready] porque el rig puede
## cambiar de nivel sin reconstruirse.
func _resolve_respawn_camera() -> Camera3D:
	if respawn_camera != null and is_instance_valid(respawn_camera):
		return respawn_camera
	var node := get_parent()
	while node != null:
		if node.has_method(&"get_respawn_camera"):
			return node.call(&"get_respawn_camera") as Camera3D
		node = node.get_parent()
	return null
