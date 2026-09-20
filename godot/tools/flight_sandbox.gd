## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Escena de vuelo a mano: plano, sol y el `DroneRig`, sin ronda ni enemigos.
##
## No es un check y no afirma nada. Lo único que hace este script es lo que
## `LevelBase` hace por los niveles jugables y esta escena no heredaba, porque su
## raíz es un [Node3D] pelado (WP-24a):
##
## 1. **Clona el `Environment`.** `world/environment_battle.tres` lo comparten el
##    nivel de batalla, el de vuelo libre y los dos showcases;
##    `Graphics.apply_environment_quality()` escribe encima, y sin el clon la
##    escritura sobrevive a la escena y ensucia a la siguiente.
## 2. **Aplica el preset al `Environment`**: SDFGI, SSIL, SSAO, niebla volumétrica
##    y glow según `docs/13` §3.4.
## 3. **Da de alta el sol** para que reciba la tabla de sombras del preset —atlas,
##    cascadas, alcance, cortes y sesgos— en vez de los valores cableados en la
##    escena.
##
## Comando, desde la raíz del repositorio:
## [codeblock]
## godot --path godot --windowed --resolution 1280x720 res://tools/flight_sandbox.tscn
## [/codeblock]
extends Node3D

## Nombre del `WorldEnvironment` de la escena.
const WORLD_ENVIRONMENT_NODE: NodePath = ^"WorldEnvironment"

## Nombre del sol de la escena. No es `Sun`: esta escena lo llama `SunLight`.
const SUN_NODE: NodePath = ^"SunLight"


func _ready() -> void:
	var world := get_node_or_null(WORLD_ENVIRONMENT_NODE) as WorldEnvironment
	if world != null and world.environment != null:
		var clone := world.environment.duplicate(false) as Environment
		if clone != null:
			clone.resource_local_to_scene = true
			world.environment = clone
		Graphics.apply_environment_quality(world.environment)
		var _discard := Graphics.environment_quality_changed.connect(
				_on_environment_quality_changed)
	Graphics.register_sun(get_node_or_null(SUN_NODE) as DirectionalLight3D)


func _on_environment_quality_changed() -> void:
	var world := get_node_or_null(WORLD_ENVIRONMENT_NODE) as WorldEnvironment
	if world != null and world.environment != null:
		Graphics.apply_environment_quality(world.environment)
