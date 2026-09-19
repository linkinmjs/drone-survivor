## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de `SceneTransition` (`docs/15` §3).
##
## Ejercita la transición con pantalla de carga entre el menú principal y el nivel de
## vuelo libre, cinco veces seguidas, y comprueba que:
##
## - cada ciclo termina (el fundido no se queda a medias) y deja la escena pedida;
## - una segunda solicitud mientras hay una en curso se ignora sin romper nada;
## - el nivel cumple el contrato de precalentamiento de `docs/11` §3.1: `warm_up_view()`
##   emite `view_warmed_up` **antes** de que se levante el fundido;
## - los cinco ciclos no dejan nodos colgados;
## - después del fundido no hay ningún cuadro por encima de 70 ms.
##
## WP-02 dejó la parte de `warm_up_view()` en SKIP porque todavía no existía un nivel que
## implementara el contrato. WP-11 entrega `rounds/free_flight_level.tscn` y con él este
## check queda completo: ya no hay ningún SKIP.
extends CheckRunner

const MENU_SCENE: String = "res://gui/main_menu.tscn"

## Nivel de WP-11: es la escena «pesada» que pide `docs/15` §3 (terreno, dron con su
## física, luz direccional y `Environment` compartido).
const LEVEL_SCENE: String = "res://rounds/free_flight_level.tscn"

## Ciclos de carga y descarga, como pide `docs/15` §3 para `loading_check`.
const CYCLES: int = 5

## Tolerancia de nodos vivos respecto del valor inicial, tras los cinco ciclos.
const NODE_TOLERANCE: int = 2

## Un frame por encima de esto cuenta como hitch (`SceneTransition.HITCH_MS`).
const HITCH_MS: float = 70.0

## Ventana de medición después de revelar la escena.
const MEASURE_SECONDS: float = 2.0

## Plazo máximo de cada espera intermedia; el timeout global lo pone `CheckRunner`.
const STEP_TIMEOUT_SECONDS: float = 30.0

## Veces que un nivel terminó de precalentar la vista.
var _warmups: int = 0

## Niveles a los que ya se les conectó la señal, para no contar dos veces.
var _watched: Array[int] = []


func _run() -> void:
	# El nodo del check deja de ser la escena actual para sobrevivir a los cambios.
	get_tree().current_scene = null
	var _discard := get_tree().node_added.connect(_on_node_added)

	if not ResourceLoader.exists(LEVEL_SCENE):
		fail("falta el nivel de vuelo libre (%s)" % LEVEL_SCENE)
		return

	# El primer ciclo solo sirve de referencia: pone las dos escenas en pie, y con ellas
	# los nodos que cada una crea una vez. Medir antes contaría esa alta como fuga.
	if not await _one_cycle(0):
		return
	await wait_frames(10)
	var baseline := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	for cycle: int in range(1, CYCLES):
		if not await _one_cycle(cycle):
			return

	await wait_frames(10)
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	expect(absi(after - baseline) <= NODE_TOLERANCE,
			"los %d ciclos no dejan nodos colgados (referencia %d, final %d, tolerancia %d)"
					% [CYCLES, baseline, after, NODE_TOLERANCE])
	expect(not SceneTransition.is_busy(), "SceneTransition queda libre al terminar")
	expect(_warmups == CYCLES,
			"cada carga del nivel precalentó la vista (esperado %d, hubo %d)"
					% [CYCLES, _warmups])

	# La medición de tirones se hace sobre el nivel, que es lo que de verdad compila
	# shaders al aparecer, no sobre el menú.
	if not await _enter(LEVEL_SCENE, CYCLES):
		return
	await _measure_hitches()
	_discard_scene()


## Un ciclo completo: entra al nivel y vuelve al menú, los dos con pantalla de carga.
func _one_cycle(index: int) -> bool:
	if not await _enter(LEVEL_SCENE, index):
		return false
	var level := get_tree().current_scene as LevelBase
	expect(level != null and level.is_warmed_up(),
			"el ciclo %d revela el nivel con la vista ya precalentada" % index)
	if index == 0:
		await shot("level_loaded")
	return await _enter(MENU_SCENE, index)


## Cambia de escena con pantalla de carga y comprueba el camino completo.
func _enter(path: String, index: int) -> bool:
	SceneTransition.change_scene(path, true)
	await wait_frames(2)
	expect(SceneTransition.is_busy(),
			"el ciclo %d marca la transición a %s como ocupada" % [index, path.get_file()])
	# Mientras está ocupada, una segunda solicitud no debe encolarse ni romper nada.
	SceneTransition.change_scene(path, true)

	var done := await _wait_until(func() -> bool: return not SceneTransition.is_busy())
	if not done:
		fail("el ciclo %d nunca terminó la transición a %s (fundido a medias)"
				% [index, path.get_file()])
		return false
	var scene := get_tree().current_scene
	expect(scene != null and scene.scene_file_path == path,
			"el ciclo %d deja %s como escena actual" % [index, path.get_file()])
	return true


## Cada nivel que entra al árbol se vigila una sola vez: así se comprueba que la señal
## del contrato se emite de verdad, y no solo que la bandera quedó en `true`.
func _on_node_added(node: Node) -> void:
	var level := node as LevelBase
	if level == null or _watched.has(level.get_instance_id()):
		return
	_watched.append(level.get_instance_id())
	var _discard := level.view_warmed_up.connect(_on_view_warmed_up)


func _on_view_warmed_up() -> void:
	_warmups += 1


## Tras revelar la escena no debe haber frames por encima de [constant HITCH_MS].
func _measure_hitches() -> void:
	var worst := 0.0
	var hitches := 0
	var last := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + int(MEASURE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		last = now
		worst = maxf(worst, frame_ms)
		if frame_ms > HITCH_MS:
			hitches += 1
	print("  frame más largo tras el fade: %.1f ms (umbral %.0f ms)" % [worst, HITCH_MS])
	expect(hitches == 0,
			"no hay hitches por encima de %.0f ms tras el fade (hubo %d, peor %.1f ms)"
					% [HITCH_MS, hitches, worst])


## Suelta la escena actual para que `CheckRunner` cierre con el árbol limpio.
func _discard_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	get_tree().current_scene = null
	scene.queue_free()


## Espera a que [param condition] se cumpla; devuelve `false` si se agota el plazo.
func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return false
