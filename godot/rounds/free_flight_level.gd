## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Nivel de vuelo libre (WP-11).
##
## Es el terreno de juego del checkpoint 2: una llanura de 800 × 800 m con unos pocos
## pilares de referencia, el dron, el punto de reaparición y dos cámaras externas para
## poder verlo mientras WP-06 no entregue la FPV. No hay ciudad, ni enemigos, ni
## objetivos: eso es del nivel de batalla de WP-21.
##
## Toda la lógica —pausa, contrato de precalentamiento, ciclo de cámaras, reaparición—
## la pone [LevelBase]. Lo único propio es aplicar al `Environment` compartido la
## calidad elegida en el menú de gráficos (`docs/04` §3.5).
class_name FreeFlightLevel
extends LevelBase

@onready var _world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	super()
	_apply_environment_quality()
	var _discard := Graphics.environment_quality_changed.connect(_apply_environment_quality)


func _apply_environment_quality() -> void:
	if _world_environment == null or _world_environment.environment == null:
		return
	Graphics.apply_environment_quality(_world_environment.environment)
