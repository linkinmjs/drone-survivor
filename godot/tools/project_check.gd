## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-01: verifica el esqueleto del proyecto según `docs/02` §13.
##
## Todo se comprueba leyendo `ProjectSettings`, `InputMap` y el propio bus
## `Events`; nunca parseando el texto de `project.godot`. No escribe en `user://`
## ni toca la configuración del jugador.
extends CheckRunner

## Las 11 capas de física 3D de `docs/02` §3.1, en orden.
const LAYER_NAMES: PackedStringArray = [
	"world", "drone", "enemy_body", "enemy_weak", "projectile_player",
	"projectile_enemy", "pickup", "city", "debris", "trigger", "enemy_sensor",
]

## Los 11 autoloads de `docs/02` §5, en el orden canónico de registro.
const AUTOLOADS: PackedStringArray = [
	"Global", "Audio", "Controls", "GameSettings", "Graphics", "QuadSettings",
	"DebugGeometry", "UI", "StickNavigation", "SceneTransition", "Events",
]

## Ejes de vuelo de `docs/02` §4.2; deadzone 0.01.
const FLIGHT_ACTIONS: PackedStringArray = [
	"throttle_up", "throttle_down", "yaw_left", "yaw_right",
	"pitch_up", "pitch_down", "roll_left", "roll_right",
]

## Acciones de juego de `docs/02` §4.3.
const GAME_ACTIONS: PackedStringArray = [
	"respawn", "cycle_flight_modes", "toggle_arm", "arm", "mode_horizon",
	"mode_turtle", "pause_menu", "change_camera", "fire", "fire_alt",
	"lock_target", "cycle_target", "objective_next", "objective_skip",
]

## Acciones de interfaz redefinidas de `docs/02` §4.4.
const UI_ACTIONS: PackedStringArray = [
	"ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel",
]

## Gatillos analógicos: deadzone 0.35 en vez de 0.5.
const TRIGGER_ACTIONS: PackedStringArray = ["fire", "lock_target"]

const FLIGHT_DEADZONE: float = 0.01
const TRIGGER_DEADZONE: float = 0.35
const DEFAULT_DEADZONE: float = 0.5

## Las 21 señales del contrato de `docs/02` §5.1 con su número exacto de argumentos.
const EVENT_SIGNALS: Dictionary[String, int] = {
	"drone_damaged": 2,
	"drone_destroyed": 1,
	"drone_respawned": 1,
	"energy_changed": 2,
	"hull_changed": 1,
	"weapon_heat_changed": 2,
	"shot_fired": 2,
	"hit_confirmed": 4,
	"battery_collected": 2,
	"enemy_spawned": 2,
	"enemy_part_broken": 3,
	"enemy_weak_point_state": 3,
	"enemy_phase_changed": 2,
	"enemy_attack_telegraphed": 3,
	"enemy_defeated": 2,
	"building_destroyed": 2,
	"city_integrity_changed": 1,
	"round_state_changed": 1,
	"camera_trauma": 2,
	"enemy_mark_shared": 3,
	"enemy_wave_requested": 2,
}

## Máscaras de consulta de `docs/02` §3.3, como la lista de capas (1-based) que
## las compone y el entero que la tabla declara. El check recompone el entero
## desde las capas y lo compara con ambos.
const QUERY_MASKS: Dictionary[String, Array] = {
	"QUERY_SHOT": [[1, 3, 4, 8, 9], 397],
	"QUERY_FOOT": [[1, 8], 129],
	"QUERY_LOS": [[1, 8], 129],
	"QUERY_SWEEP": [[2, 8], 130],
}


func _run() -> void:
	await wait_frames(1)
	_check_layer_names()
	_check_autoloads()
	_check_renderer()
	_check_physics()
	_check_features()
	_check_input_actions()
	_check_ui_actions_free_of_joypad_motion()
	_check_physics_layers()
	_check_events_contract()
	_check_gdignore()


## Comprobación 1: las 11 capas 3D existen con el nombre exacto.
func _check_layer_names() -> void:
	for index in LAYER_NAMES.size():
		var key := "layer_names/3d_physics/layer_%d" % (index + 1)
		var value := String(ProjectSettings.get_setting(key, ""))
		expect(value == LAYER_NAMES[index],
			"la capa %d debería llamarse '%s' y vale '%s'" % [index + 1, LAYER_NAMES[index], value])


## Comprobación 2: los 11 autoloads están registrados y en el orden canónico.
func _check_autoloads() -> void:
	var registered: PackedStringArray = PackedStringArray()
	for property: Dictionary in ProjectSettings.get_property_list():
		var key := String(property.get("name", ""))
		if key.begins_with("autoload/"):
			registered.append(key.trim_prefix("autoload/"))
	expect(registered == AUTOLOADS, "los autoloads deberían ser [%s] y son [%s]" % [
		", ".join(AUTOLOADS), ", ".join(registered)])
	for autoload_name: String in AUTOLOADS:
		expect(get_tree().root.has_node(NodePath(autoload_name)),
			"el autoload %s no llegó al árbol de escena" % autoload_name)


## Comprobación 3: el renderizador es Forward+.
func _check_renderer() -> void:
	var method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	expect(method == "forward_plus", "el renderizador debería ser 'forward_plus' y es '%s'" % method)


## Comprobación 4: motor de física Jolt a 100 Hz, también en tiempo de ejecución.
func _check_physics() -> void:
	var physics_engine := String(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	expect(physics_engine == "Jolt Physics",
		"el motor de física 3D debería ser 'Jolt Physics' y es '%s'" % physics_engine)
	var ticks := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0))
	expect(ticks == 100, "physics_ticks_per_second debería ser 100 y es %d" % ticks)
	expect(Engine.physics_ticks_per_second == 100,
		"Engine.physics_ticks_per_second debería ser 100 en runtime y es %d" % Engine.physics_ticks_per_second)


## Comprobación 5: `config/features` declara 4.7 y ya no declara GL Compatibility.
func _check_features() -> void:
	var features := PackedStringArray(ProjectSettings.get_setting(
		"application/config/features", PackedStringArray()))
	expect(features.has("4.7"), "config/features debería contener '4.7' y contiene [%s]" % ", ".join(features))
	expect(not features.has("GL Compatibility"),
		"config/features no debería contener 'GL Compatibility': el proyecto es Forward+")


## Comprobaciones 6 y 7: las 28 acciones existen, tienen eventos y su deadzone.
func _check_input_actions() -> void:
	var expected: PackedStringArray = PackedStringArray()
	expected.append_array(FLIGHT_ACTIONS)
	expected.append_array(GAME_ACTIONS)
	expected.append_array(UI_ACTIONS)
	expect(expected.size() == 28,
		"el catálogo del check debería listar 28 acciones y lista %d" % expected.size())
	for action: String in expected:
		if not InputMap.has_action(action):
			fail("falta la acción de entrada '%s'" % action)
			continue
		expect(not InputMap.action_get_events(action).is_empty(),
			"la acción '%s' no tiene ningún evento asignado" % action)
		var deadzone_expected := DEFAULT_DEADZONE
		if FLIGHT_ACTIONS.has(action):
			deadzone_expected = FLIGHT_DEADZONE
		elif TRIGGER_ACTIONS.has(action):
			deadzone_expected = TRIGGER_DEADZONE
		expect_near(InputMap.action_get_deadzone(action), deadzone_expected, 0.0001,
			"deadzone de la acción '%s'" % action)


## Comprobación 8: ninguna acción `ui_*` acepta un eje de joystick, porque un
## acelerador de radio en reposo desplazaría el foco de los menús sin parar.
func _check_ui_actions_free_of_joypad_motion() -> void:
	for action: String in UI_ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			expect(not (event is InputEventJoypadMotion),
				"la acción '%s' tiene un InputEventJoypadMotion y no puede tenerlo" % action)


## Comprobaciones 9 y 12: las constantes de `PhysicsLayers` valen lo que dice la
## tabla y son coherentes con las capas que las componen.
func _check_physics_layers() -> void:
	var declared: Dictionary[String, int] = {
		"QUERY_SHOT": PhysicsLayers.QUERY_SHOT,
		"QUERY_FOOT": PhysicsLayers.QUERY_FOOT,
		"QUERY_LOS": PhysicsLayers.QUERY_LOS,
		"QUERY_SWEEP": PhysicsLayers.QUERY_SWEEP,
	}
	for key: String in QUERY_MASKS:
		var entry: Array = QUERY_MASKS[key]
		var layers: Array = entry[0]
		var documented: int = entry[1]
		var recomputed := 0
		for layer: int in layers:
			recomputed |= 1 << (layer - 1)
		expect(recomputed == documented,
			"la máscara %s recompuesta desde sus capas da %d y la tabla declara %d" % [
				key, recomputed, documented])
		expect(declared[key] == documented,
			"PhysicsLayers.%s vale %d y debería valer %d" % [key, declared[key], documented])


## Comprobación 10: `Events` declara exactamente las 21 señales del contrato,
## cada una con su número de argumentos.
func _check_events_contract() -> void:
	var script := Events.get_script() as Script
	var declared: Dictionary[String, int] = {}
	if script == null:
		fail("el autoload Events no tiene script")
	else:
		for info: Dictionary in script.get_script_signal_list():
			var args: Array = info.get("args", [])
			declared[String(info.get("name", ""))] = args.size()
	expect(declared.size() == EVENT_SIGNALS.size(),
		"events.gd debería declarar %d señales propias y declara %d" % [
			EVENT_SIGNALS.size(), declared.size()])
	for signal_name: String in EVENT_SIGNALS:
		if not Events.has_signal(signal_name):
			fail("Events no declara la señal '%s' del contrato" % signal_name)
			continue
		var arity: int = declared.get(signal_name, -1)
		expect(arity == EVENT_SIGNALS[signal_name],
			"Events.%s debería tener %d argumentos y tiene %d" % [
				signal_name, EVENT_SIGNALS[signal_name], arity])
	for signal_name: String in declared:
		expect(EVENT_SIGNALS.has(signal_name),
			"Events declara la señal '%s', que no está en el contrato de docs/02 §5.1" % signal_name)


## Comprobación 11: el `.gdignore` que mantiene los packs crudos fuera del
## escaneo de Godot. La ruta se globaliza porque el directorio está ignorado.
func _check_gdignore() -> void:
	var path := ProjectSettings.globalize_path("res://assets/_raw/.gdignore")
	expect(FileAccess.file_exists(path),
		"falta assets/_raw/.gdignore: Godot escanearía e importaría los packs crudos")
