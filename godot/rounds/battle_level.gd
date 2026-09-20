## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Nivel de batalla, **único para todas las rondas** (`docs/11` §3).
##
## Lo que cambia de una ronda a otra es el distrito y los enemigos, y eso lo
## instancia [RoundManager] en tiempo de ejecución desde [RoundCatalog]. Este script
## no sabe qué ronda se está jugando: arma el escenario vacío, aplica la calidad de
## `Environment` elegida en el menú de gráficos (`docs/04` §3.5) y le da el arranque
## al `RoundManager` cuando el árbol ya está entero.
##
## **El orden importa**: `_ready()` de un padre corre **después** del de sus hijos, así
## que cuando se llega acá el `DroneRig` ya cableó su cámara FPV y [LevelBase] ya
## juntó las cámaras del nivel. Recién entonces tiene sentido que `RoundManager` pida
## la cámara de la cinemática, porque [method LevelBase.focus_camera] necesita que la
## lista esté hecha.
##
## **Nadie busca nodos en la raíz** (`docs/11` §3): todas las referencias del
## `RoundManager` entran por `@export` desde la escena.
##
## Pausa, ciclo de cámaras, contrato de precalentamiento y reaparición los pone
## [LevelBase]; el contenido —distrito, ciudad, enemigos, objetivos— lo pone la ronda.
##
## ## El `CombatHUD` es del nivel (`docs/12` §1.1)
##
## El HUD de combate cuelga de `CombatHUDSlot` en la escena, no del rig, porque tiene
## que **sobrevivir al respawn**: mientras el dron se reconstruye, la barra del jefe,
## la integridad de la ciudad y el cronómetro siguen en pantalla. Por eso lo cablea
## este nodo y no [RoundManager]: el nivel es su dueño, y quien lo alimenta después
## es el bus.
##
## El cableado va **antes** de [method RoundManager.begin] a propósito. `begin()`
## instancia el distrito y los enemigos, y el `enemy_spawned` de cada uno se emite en
## su `_ready()`: si el HUD todavía no estuviera conectado al bus perdería el único
## aviso de que el jefe existe.
class_name BattleLevel
extends LevelBase

## Máquina de estados de la ronda. Recibe el nivel entero en [method _ready].
@export var round_manager: RoundManager

## HUD de combate de la capa 20 (`docs/12` §4). Es el que apaga la tarjeta de
## objetivo provisional: con el `CombatHUDSlot` ocupado,
## `RoundManager._show_objective_hud()` devuelve `false`.
@export var combat_hud: CombatHUD

@onready var _world_environment: WorldEnvironment = $WorldEnvironment

## Iluminación local de la ciudad (`docs/13` §3.3). Se crea acá y no en la escena
## porque necesita el `CityGrid` que instancia [method RoundManager.begin].
var _probe_rig: ReflectionProbeRig = null


func _ready() -> void:
	super()
	_apply_environment_quality()
	var _discard := Graphics.environment_quality_changed.connect(_apply_environment_quality)
	_wire_combat_hud()
	if round_manager != null:
		round_manager.begin(self)
		_bind_spawned_enemies()
		_build_reflection_probes()
	else:
		push_error("BattleLevel: falta el RoundManager (docs/11 §3).")


## La ronda en curso, o `null` si la escena se abrió sin `RoundManager`.
func get_round_manager() -> RoundManager:
	return round_manager


## El HUD de combate del nivel, o `null` si la escena se abrió sin él.
func get_combat_hud() -> CombatHUD:
	return combat_hud


# --- HUD de combate ---------------------------------------------------------------------------

## Ata el HUD al dron, a la ciudad y a la ronda.
##
## La cámara se deja **sin fijar** a propósito: con `set_camera(null)` el HUD usa la
## que esté dibujando la escena, así que sigue sola al ciclo de cámaras de
## [LevelBase] y al salto a la cámara fija durante el respawn, sin que nadie tenga que
## avisarle. Fijarla sería volver a tener dos sistemas que sincronizar.
func _wire_combat_hud() -> void:
	if combat_hud == null:
		return
	if round_manager == null:
		return
	combat_hud.bind_round(round_manager, round_manager.sequencer)
	combat_hud.bind_city(round_manager.city_integrity)
	combat_hud.bind_drone(drone_rig as DroneRig)


## Da de alta los enemigos que [method RoundManager.begin] acaba de instanciar.
##
## Es redundante con `Events.enemy_spawned` —y [method CombatHUD.bind_enemy] es
## idempotente— pero cierra el caso del enemigo que se instanciara **fuera** del
## árbol o antes de que el HUD estuviera listo, que es lo que haría un check.
func _bind_spawned_enemies() -> void:
	if combat_hud == null or round_manager == null:
		return
	for enemy: Variant in round_manager.get_enemies():
		combat_hud.bind_enemy(enemy as Node3D)


func _apply_environment_quality() -> void:
	if _world_environment == null or _world_environment.environment == null:
		return
	Graphics.apply_environment_quality(_world_environment.environment)
	# La cuenta de probes es parte del preset, así que cambiar de calidad en caliente
	# tiene que rehacerlos. En el primer `_ready()` el distrito todavía no existe y
	# [method _build_reflection_probes] no hace nada: lo llama otra vez `_ready()`
	# después de `RoundManager.begin()`.
	_build_reflection_probes()


# --- GI local (`docs/13` §3.3) -----------------------------------------------------------------

## Arma los [ReflectionProbe] de la ciudad sobre puntos que pide a [CityGrid].
##
## Sin distrito —un nivel que se abra suelto, o el instante anterior a
## [method RoundManager.begin]— no hace nada y deja el rig vacío.
func _build_reflection_probes() -> void:
	var grid := get_city_grid()
	if grid == null:
		return
	if _probe_rig == null or not is_instance_valid(_probe_rig):
		_probe_rig = ReflectionProbeRig.new()
		_probe_rig.name = "ReflectionProbes"
		add_child(_probe_rig)
	_probe_rig.rebuild(grid)


## La rejilla del distrito instanciado, o `null` si la ronda todavía no lo puso.
func get_city_grid() -> CityGrid:
	if round_manager == null or not is_instance_valid(round_manager):
		return null
	var integrity := round_manager.city_integrity
	if integrity == null or not is_instance_valid(integrity):
		return null
	return integrity.grid


## Los [ReflectionProbe] locales vivos. Lo mira `render_check`.
func get_reflection_probes() -> Array[ReflectionProbe]:
	if _probe_rig == null or not is_instance_valid(_probe_rig):
		return []
	return _probe_rig.get_probes()
