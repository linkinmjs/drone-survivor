## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Muestreador de una ventana de fotogramas (`docs/15` §5.1), compartido por
## `tools/perf_report.gd` y `tools/render_check.gd`.
##
## Hace tres cosas que `Performance` sola no hace:
##
## 1. **Separa CPU de GPU.** `RenderingServer.viewport_set_measure_render_time`
##    pide al servidor los tiempos reales de cada viewport, y
##    `viewport_get_measured_render_time_gpu/cpu` los devuelve en milisegundos.
##    Con el ojo de pez hay más de una viewport 3D dibujando —la raíz y las
##    `SubViewport` de la cámara FPV—, así que se miden todas y se reportan por
##    separado: es la única forma de saber si el coste está en la escena o en el
##    compuesto.
## 2. **Da un percentil 1 honesto.** El fps medio esconde los tirones.
##    [member fps_engine_p1] es `1000 / p99(ms por fotograma)`, con el tiempo de
##    fotograma medido con el reloj de pared (`Time.get_ticks_usec`), que sí
##    incluye la espera por la GPU y es lo que siente el jugador.
## 3. **Reparte el tick de física** entre sistemas leyendo [PerfProbe], y suma
##    los contadores de cuerpos activos, pares de colisión e islas de Jolt.
## 4. **Cierra la atribución** (WP-29): con los dos [PerfBracket] puestos sabe cuánto
##    costó el GDScript del tick entero, cuánto de eso está instrumentado y cuánto
##    queda sin atribuir, y estima el paso de Jolt con el hueco entre ticks
##    encadenados ([method PerfProbe.gap_ms]). Además reparte el fotograma de
##    `_process` entre [constant PerfProbe.PROCESS_IDS].
##
## ## Qué es de verdad `TIME_PHYSICS_PROCESS`
##
## No es «el coste del último tick»: Godot lo reescribe **una vez por segundo** con
## el **máximo** que vio en ese segundo, en el mismo bloque de `main.cpp` que
## actualiza `Engine.get_frames_per_second()`. Por eso `physics_ms_avg` es la media
## de esos picos y no un promedio por tick, y por eso un presupuesto de «< 2 ms» es
## conservador: si el peor tick del segundo cabe, caben todos. `docs/15` §5.1 lo
## llama «ms/tick», que es la lectura optimista de la misma cifra; queda anotado.
##
## El reparto por sistema sí es un promedio honesto por tick: [PerfProbe] acumula
## microsegundos y divide por los ticks de física transcurridos. Las dos cifras no
## son comparables entre sí y por eso no se resta una de la otra.
##
## Ciclo de vida:
## [codeblock]
## var sampler := PerfSampler.new()
## sampler.attach(get_viewport(), fpv_camera.get_fisheye_viewports())
## sampler.begin()
## for i in frames:
##     await get_tree().process_frame
##     sampler.sample()
## var data := sampler.finish()
## [/codeblock]
##
## `attach()` es idempotente y `finish()` apaga la medición de render, que no es
## gratis: el servidor sincroniza con la GPU para leer los contadores.
class_name PerfSampler
extends RefCounted

## Percentil del tiempo de fotograma que define el «percentil 1» de fps.
const P1_PERCENTILE: float = 99.0

## Clave del total instrumentado dentro del desglose de física. **No** es el tick
## entero: es la suma de lo que [PerfProbe] sabe medir. Lo que falta —el paso de
## Jolt y los `_physics_process` de los archivos que WP-24a no puede instrumentar—
## se atribuye con la ablación de `perf_report`, nunca restando.
const PROBED_KEY: StringName = &"instrumentado_total"

## Clave del GDScript **entero** del tick, medido por los dos [PerfBracket]. Es el
## denominador honesto de la atribución de WP-29: `instrumentado_total / gdscript_total`
## es la fracción cubierta por [constant PerfProbe.IDS].
const SCRIPTS_KEY: StringName = &"gdscript_total"

## Clave de lo que corre dentro del tick y **no** pasó por ninguna sonda.
const UNPROBED_KEY: StringName = &"sin_instrumentar"

## Clave del paso de Jolt, estimado con el percentil bajo del hueco entre ticks
## encadenados **menos** lo que corre dentro de ese paso
## ([constant PerfProbe.STEP_IDS], hoy `_integrate_forces`). No es una resta contra
## `TIME_PHYSICS_PROCESS` (que es un pico por segundo, WP-24a) sino una medición propia.
const JOLT_KEY: StringName = &"jolt_step"

## Clave del tick completo: GDScript más paso de Jolt.
const TICK_KEY: StringName = &"tick_total"

## Percentil del hueco entre ticks que se toma como paso de Jolt. Los huecos que se
## comieron un fotograma de render quedan por arriba; el cuartil bajo es la lectura
## limpia (ver la cabecera de [PerfProbe]).
const JOLT_PERCENTILE: float = 25.0

## RID de la viewport raíz, o un RID inválido si no se enganchó ninguna.
var root_rid: RID = RID()

## RID de cada `SubViewport` del ojo de pez, en el orden en que las devolvió la
## cámara FPV.
var fisheye_rids: Array[RID] = []

var _frames: int = 0
var _last_usec: int = 0
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _gpu_root: PackedFloat32Array = PackedFloat32Array()
var _cpu_root: PackedFloat32Array = PackedFloat32Array()
var _gpu_fisheye: Array[PackedFloat32Array] = []
var _physics_ms: PackedFloat32Array = PackedFloat32Array()
var _last_physics_frame: int = 0
var _idle_physics_frames: int = 0
var _derived_ms: PackedFloat32Array = PackedFloat32Array()
var _draw_calls: PackedFloat32Array = PackedFloat32Array()
var _primitives: PackedFloat32Array = PackedFloat32Array()
var _engine_fps: PackedFloat32Array = PackedFloat32Array()
var _active_bodies: PackedFloat32Array = PackedFloat32Array()
var _collision_pairs: PackedFloat32Array = PackedFloat32Array()
var _islands: PackedFloat32Array = PackedFloat32Array()
var _vram: float = 0.0
var _nodes: int = 0
var _measuring: bool = false


## Engancha la viewport raíz y las del ojo de pez, y le pide al servidor que
## mida sus tiempos. Volver a llamarla con otras viewports reengancha: el ojo de
## pez reconstruye sus `SubViewport` cada vez que cambia el preset.
func attach(root: Viewport, fisheye: Array[SubViewport] = []) -> void:
	detach()
	if root != null:
		root_rid = root.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(root_rid, true)
	for viewport: SubViewport in fisheye:
		if not is_instance_valid(viewport):
			continue
		var rid := viewport.get_viewport_rid()
		fisheye_rids.append(rid)
		RenderingServer.viewport_set_measure_render_time(rid, true)
		_gpu_fisheye.append(PackedFloat32Array())
	_measuring = true


## Apaga la medición de render de todo lo enganchado. La llama [method finish],
## y también [method attach] antes de enganchar otra cosa.
func detach() -> void:
	if root_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(root_rid, false)
	for rid: RID in fisheye_rids:
		if rid.is_valid():
			RenderingServer.viewport_set_measure_render_time(rid, false)
	root_rid = RID()
	fisheye_rids.clear()
	_gpu_fisheye.clear()
	_measuring = false


## Empieza la ventana: vacía los acumuladores y reinicia [PerfProbe].
func begin() -> void:
	_frames = 0
	_frame_ms.clear()
	_gpu_root.clear()
	_cpu_root.clear()
	for index: int in _gpu_fisheye.size():
		_gpu_fisheye[index] = PackedFloat32Array()
	_physics_ms.clear()
	_idle_physics_frames = 0
	_last_physics_frame = Engine.get_physics_frames()
	_derived_ms.clear()
	_draw_calls.clear()
	_primitives.clear()
	_engine_fps.clear()
	_active_bodies.clear()
	_collision_pairs.clear()
	_islands.clear()
	_vram = 0.0
	_nodes = 0
	_last_usec = Time.get_ticks_usec()
	PerfProbe.start()


## Acumula un fotograma. Se llama justo después de `await process_frame`.
func sample() -> void:
	var now := Time.get_ticks_usec()
	_frame_ms.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	_frames += 1
	if root_rid.is_valid():
		_gpu_root.append(RenderingServer.viewport_get_measured_render_time_gpu(root_rid))
		_cpu_root.append(RenderingServer.viewport_get_measured_render_time_cpu(root_rid))
	for index: int in fisheye_rids.size():
		_gpu_fisheye[index].append(
				RenderingServer.viewport_get_measured_render_time_gpu(fisheye_rids[index]))
	var physics_ms := float(Performance.get_monitor(
			Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	_physics_ms.append(physics_ms)
	var now_ticks := Engine.get_physics_frames()
	if now_ticks == _last_physics_frame:
		_idle_physics_frames += 1
	_last_physics_frame = now_ticks
	# FPS «derivados» de `docs/15` §5.1: sirven para comparar coste de CPU entre
	# corridas, no para afirmar «≥ 60 fps» (ver la nota de WP-23 en ese mismo §).
	_derived_ms.append(maxf(physics_ms + float(Performance.get_monitor(
			Performance.TIME_PROCESS)) * 1000.0, 0.0001))
	_draw_calls.append(float(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_primitives.append(float(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_engine_fps.append(float(Engine.get_frames_per_second()))
	_active_bodies.append(float(Performance.get_monitor(
			Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
	_collision_pairs.append(float(Performance.get_monitor(
			Performance.PHYSICS_3D_COLLISION_PAIRS)))
	_islands.append(float(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)))
	_vram = maxf(_vram, float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	_nodes = maxi(_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))


## Cierra la ventana, apaga la sonda y devuelve el diccionario de resultados con
## el formato de `docs/15` §5.3 más los campos nuevos de WP-24a.
func finish() -> Dictionary:
	PerfProbe.stop()
	var physics_avg := _mean(_physics_ms)
	var breakdown := PerfProbe.breakdown()
	var physics: Dictionary = {}
	for id: StringName in PerfProbe.IDS:
		physics[String(id)] = snappedf(float(breakdown[id]), 0.001)
	var probed := PerfProbe.measured_ms_per_tick()
	var scripts := PerfProbe.scripts_ms_per_tick()
	# Sin cuadro topado el hueco entre ticks es un fotograma de render y no el paso de
	# Jolt, así que no se publica ningún número antes que publicar uno falso.
	var gap_valid := PerfProbe.gap_is_valid()
	var gap := PerfProbe.gap_ms(JOLT_PERCENTILE) if gap_valid else 0.0
	var in_step := PerfProbe.step_ms_per_tick()
	var jolt := maxf(gap - in_step, 0.0) if gap_valid else 0.0
	physics[String(PROBED_KEY)] = snappedf(probed, 0.001)
	physics[String(SCRIPTS_KEY)] = snappedf(scripts, 0.001)
	physics[String(UNPROBED_KEY)] = snappedf(maxf(scripts - probed, 0.0), 0.001)
	physics[String(JOLT_KEY)] = snappedf(jolt, 0.001)
	physics[String(TICK_KEY)] = snappedf(scripts + gap, 0.001)
	var process_breakdown := PerfProbe.process_breakdown()
	var per_frame: Dictionary = {}
	for id: StringName in PerfProbe.PROCESS_IDS:
		per_frame[String(id)] = snappedf(float(process_breakdown[id]), 0.001)
	per_frame[String(PROBED_KEY)] = snappedf(PerfProbe.measured_ms_per_frame(), 0.001)
	var fisheye_avg: Array[float] = []
	var fisheye_max: Array[float] = []
	var fisheye_total := 0.0
	for index: int in _gpu_fisheye.size():
		var avg := _mean(_gpu_fisheye[index])
		fisheye_avg.append(snappedf(avg, 0.001))
		fisheye_max.append(snappedf(_maximum(_gpu_fisheye[index]), 0.001))
		fisheye_total += avg
	var result: Dictionary = {
		"frames": _frames,
		"physics_ms_avg": physics_avg,
		"physics_ms_p95": _percentile(_physics_ms, 95.0),
		"physics_ms_max": _maximum(_physics_ms),
		"physics_ticks": PerfProbe.physics_frames(),
		"frames_without_tick": _idle_physics_frames,
		"physics_breakdown_ms": physics,
		"process_breakdown_ms": per_frame,
		"physics_scripts_ms": snappedf(scripts, 0.001),
		"physics_probed_ms": snappedf(probed, 0.001),
		"physics_jolt_ms": snappedf(jolt, 0.001),
		"physics_gap_ms": snappedf(gap, 0.001),
		"physics_step_scripts_ms": snappedf(in_step, 0.001),
		"physics_tick_ms": snappedf(scripts + gap, 0.001),
		"physics_attributed_pct": snappedf(
				100.0 * (probed + in_step + jolt) / maxf(scripts + gap, 0.0001)
				if scripts + gap > 0.0 else 0.0, 0.1),
		"physics_callbacks_attributed_pct": snappedf(
				100.0 * probed / maxf(scripts, 0.0001) if scripts > 0.0 else 0.0, 0.1),
		"physics_bracketed_ticks": PerfProbe.bracketed_ticks(),
		"physics_gap_samples": PerfProbe.gap_count() if gap_valid else 0,
		"physics_gap_valid": gap_valid,
		"physics_active_bodies_avg": _mean(_active_bodies),
		"physics_collision_pairs_avg": _mean(_collision_pairs),
		"physics_islands_avg": _mean(_islands),
		"draw_calls_avg": _mean(_draw_calls),
		"draw_calls_p95": _percentile(_draw_calls, 95.0),
		"draw_calls_max": _maximum(_draw_calls),
		"primitives_avg": _mean(_primitives),
		"primitives_p95": _percentile(_primitives, 95.0),
		"primitives_max": _maximum(_primitives),
		"gpu_ms_root_avg": _mean(_gpu_root),
		"gpu_ms_root_p95": _percentile(_gpu_root, 95.0),
		"gpu_ms_root_max": _maximum(_gpu_root),
		"cpu_ms_render_avg": _mean(_cpu_root),
		"cpu_ms_render_p95": _percentile(_cpu_root, 95.0),
		"gpu_ms_fisheye": fisheye_avg,
		"gpu_ms_fisheye_max": fisheye_max,
		"gpu_ms_fisheye_total": fisheye_total,
		"gpu_ms_total": _mean(_gpu_root) + fisheye_total,
		"frame_ms_avg": _mean(_frame_ms),
		"frame_ms_p99": _percentile(_frame_ms, P1_PERCENTILE),
		"frame_ms_max": _maximum(_frame_ms),
		"fps_wall": 1000.0 / maxf(_mean(_frame_ms), 0.0001),
		"fps_avg": 1000.0 / maxf(_mean(_derived_ms), 0.0001),
		"fps_p95": 1000.0 / maxf(_percentile(_derived_ms, 95.0), 0.0001),
		"fps_min": 1000.0 / maxf(_maximum(_derived_ms), 0.0001),
		"fps_median": 1000.0 / maxf(_percentile(_derived_ms, 50.0), 0.0001),
		"fps_engine": _mean(_engine_fps),
		"fps_engine_p1": 1000.0 / maxf(_percentile(_frame_ms, P1_PERCENTILE), 0.0001),
		"vram_bytes": _vram,
		"vram_mb": _vram / 1048576.0,
		"node_count": _nodes,
	}
	return result


## Verdadero mientras haya alguna viewport enganchada.
func is_attached() -> bool:
	return _measuring


## Fotogramas acumulados en la ventana en curso.
func frame_count() -> int:
	return _frames


## Redondea a tres decimales los flotantes de [param sample]; los diccionarios
## anidados —el desglose de física— ya vienen redondeados.
static func round_values(sample: Dictionary) -> Dictionary:
	var rounded: Dictionary = {}
	for key: Variant in sample:
		var value: Variant = sample[key]
		if typeof(value) == TYPE_FLOAT:
			rounded[key] = snappedf(float(value), 0.001)
		elif typeof(value) == TYPE_ARRAY:
			var list: Array = []
			for item: Variant in value as Array:
				list.append(snappedf(float(item), 0.001) if typeof(item) == TYPE_FLOAT else item)
			rounded[key] = list
		else:
			rounded[key] = value
	return rounded


# --- Estadística -----------------------------------------------------------------------------

static func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


static func _percentile(values: PackedFloat32Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := Array(values)
	sorted.sort()
	var index := clampi(int(roundf(p / 100.0 * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return float(sorted[index])


static func _maximum(values: PackedFloat32Array) -> float:
	var best := 0.0
	for value: float in values:
		best = maxf(best, value)
	return best
