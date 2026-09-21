## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Sonda de coste por sistema dentro del tick de física (`docs/15` §5).
##
## `TIME_PHYSICS_PROCESS` da un solo número: 2,98 ms/tick con jefe y ciudad. Esta
## sonda lo reparte entre los sistemas que lo gastan, para que la optimización
## ataque lo que pesa y no lo que parece pesar.
##
## Es **estática y está apagada por defecto**: con [member enabled] en `false`,
## [method begin] y [method end] son una comparación de un booleano y un `return`,
## así que el juego normal no paga nada por llevarlas escritas. Solo la encienden
## `tools/perf_report.gd` y `tools/balance_check.gd`.
##
## Uso, siempre en pares y sin `await` en medio:
## [codeblock]
## PerfProbe.begin(&"drone_integrator")
## ...trabajo...
## PerfProbe.end(&"drone_integrator")
## [/codeblock]
##
## Los acumuladores son microsegundos totales desde el último [method reset]. El
## coste por tick lo calcula quien mide, dividiendo por los ticks de física
## transcurridos ([method physics_frames]); así la sonda no necesita saber nada
## del tamaño de la ventana de medición.
##
## Convención de identificadores (los consume `PerfSampler`):
##
## | Id | Qué mide |
## |---|---|
## | `drone_integrator` | `Drone._integrate_forces` completo, sub-pasos incluidos |
## | `projectile_pool` | avance y rayos de `ProjectilePool._physics_process` |
## | `weapon_mount` | disparo, cadencia y retroceso de `WeaponMount` |
## | `aim_assist` | barrido de candidatos de `AimAssist` |
## | `perception` | muestreo **y rayo de LOS** de `Perception` |
## | `bot_pilot` | piloto sintético de `tools/bot_pilot.gd` |
## | `rig_tick` | `ProceduralLegRig.rig_tick`: IK, rayos y pose del cuerpo (WP-29) |
## | `fsm_state` | `EnemyFSM` por tick: locomoción, interrupciones y `_tick` del estado |
## | `fsm_context` | `EnemyFSM._build_context()`: barrido de ciudad, rayo de altura y creencia |
## | `fsm_select` | `UtilitySelector.select()`: puntaje de las nueve acciones |
## | `enemy_action` | enfriamientos de las nueve `EnemyAction` (WP-29) |
## | `telegraph` | desvanecido del aviso de `Telegraph` (WP-29) |
## | `enemy_base` | `EnemyBase`: bloqueos, exposición a 10 Hz y fases a 4 Hz (WP-29) |
## | `enemy_audio` | `AudioRig`: carga de servos y bucle (WP-29) |
## | `city_building` | los 60 `Building` que estén despiertos (WP-29) |
## | `city_integrity` | `CityIntegrity`: publicación y asedio (WP-29) |
## | `debris_pool` | envejecimiento y retiro de `DebrisPool` (WP-29) |
## | `audio_pool` | anclas y corte de bucles de `AudioPool` (WP-29) |
## | `round_objectives` | `Objective._physics_process` de la ronda en curso (WP-29) |
## | `drone_rig` | `DroneRig._physics_process`: cableado del dron (WP-29) |
## | `drone_damage` | `Hull` y `RespawnController`: cooldowns y cuenta atrás (WP-29) |
## | `drone_energy` | `EnergySystem`, `BatterySpawner` y `BatteryPickup` (WP-29) |
## | `motor_audio` | `MotorAudio`: los ocho bucles de motor por banda (WP-29) |
## | `drone_misc` | `RadioController` y `FollowCamera` (WP-29) |
##
## Y por **fotograma** de `_process`, no por tick ([constant PROCESS_IDS]):
##
## | Id | Qué mide |
## |---|---|
## | `camera_rig` | `CameraRig`: seguimiento, trauma y sacudida (WP-29) |
## | `fpv_overlay` | `FPVOverlay`: uniformes del sombreador de la radio (WP-29) |
## | `fpv_camera` | `FPVCamera`: compuesto del ojo de pez (WP-29) |
## | `vfx_pool` | `VFXPool`: vencimiento de efectos y presupuesto (WP-29) |
## | `round_manager` | `RoundManager`: máquina de la ronda (WP-29) |
## | `objective_sequencer` | `ObjectiveSequencer`: avance de objetivos (WP-29) |
## | `hud_flight` | `HUD` (FlightHUD): horizonte, cintas y proyección (WP-29) |
## | `hud_combat` | `CombatHUD`: barras, marcadores y proyección (WP-29) |
##
## ## Total por tick y `jolt_step` (WP-29)
##
## [method tick_open] y [method tick_close] las llaman dos [PerfBracket] que
## `tools/perf_report.gd` cuelga del árbol con prioridad de física extrema, así que
## abren antes del primer `_physics_process` y cierran después del último. La
## diferencia es el **GDScript entero del tick** ([method scripts_ms_per_tick]), que
## sí se puede comparar con la suma de [constant IDS] para saber qué fracción quedó
## sin instrumentar.
##
## El paso de Jolt corre **después** del último `_physics_process`, así que ningún
## par `begin/end` lo puede envolver. Lo que sí se mide es el **hueco** entre cerrar
## un tick y abrir el siguiente ([method gap_ms]): cuando el motor encadena varios
## pasos de física dentro de la misma iteración del bucle principal —lo que pasa
## siempre que `Engine.max_fps` está por debajo de `physics_ticks_per_second`— ese
## hueco es el paso de Jolt y nada más. Los huecos que se comen un fotograma de
## render quedan arriba en la distribución, así que el percentil bajo es la lectura
## limpia. `Performance.TIME_PHYSICS_PROCESS` **no** sirve para esto: es el máximo
## por segundo de una iteración entera (WP-24a).
class_name PerfProbe
extends RefCounted

## Identificadores medidos **por tick de física**, en el orden en que se imprimen.
##
## Todos menos [constant STEP_IDS] corren en la fase de `_physics_process`, o sea
## **dentro** de la pinza de [method tick_open] / [method tick_close].
const IDS: Array[StringName] = [
	&"drone_integrator", &"projectile_pool", &"weapon_mount", &"aim_assist",
	&"perception", &"bot_pilot",
	&"rig_tick", &"fsm_state", &"fsm_context", &"fsm_select",
	&"enemy_action", &"telegraph", &"enemy_base",
	&"enemy_audio", &"city_building", &"city_integrity", &"debris_pool",
	&"audio_pool", &"round_objectives", &"drone_rig",
	&"drone_damage", &"drone_energy", &"motor_audio", &"drone_misc",
]

## Identificadores que **no** corren en la fase de `_physics_process` sino dentro del
## paso del servidor de física, que es posterior (WP-29).
##
## `_integrate_forces` es una devolución de llamada de Jolt: el motor la invoca
## mientras integra el cuerpo, así que cae en el mismo hueco que
## [method gap_ms] mide. Sumarla a la fase de callbacks daba más del 100 % de
## atribución —medido en la primera corrida de WP-29: 112 %— porque se contaba dos
## veces, una en la sonda y otra dentro del hueco.
const STEP_IDS: Array[StringName] = [&"drone_integrator"]

## Identificadores medidos **por fotograma de `_process`**. Comparten acumuladores
## con [constant IDS]; lo único que cambia es el divisor.
const PROCESS_IDS: Array[StringName] = [
	&"camera_rig", &"fpv_overlay", &"fpv_camera", &"vfx_pool",
	&"round_manager", &"objective_sequencer", &"hud_flight", &"hud_combat",
]

## Interruptor general. Con `false` —el valor de producción— ni se lee el reloj.
static var enabled: bool = false

## Microsegundos acumulados por identificador desde el último [method reset].
static var _totals: Dictionary[StringName, int] = {}

## Llamadas cerradas por identificador desde el último [method reset].
static var _calls: Dictionary[StringName, int] = {}

## Marca de tiempo abierta por identificador; `0` si no hay ninguna.
static var _open: Dictionary[StringName, int] = {}

## Ticks de física en el momento del último [method reset].
static var _frames_at_reset: int = 0

## Fotogramas de proceso en el momento del último [method reset].
static var _process_frames_at_reset: int = 0

## Marca de [method tick_open] del tick en curso; `0` si no hay ninguno abierto.
static var _tick_open_usec: int = 0

## Marca del último [method tick_close]; `0` si todavía no cerró ninguno.
static var _tick_close_usec: int = 0

## Microsegundos sumados entre [method tick_open] y [method tick_close].
static var _tick_total_usec: int = 0

## Pares abrir/cerrar completados desde el último [method reset].
static var _tick_brackets: int = 0

## Huecos entre cerrar un tick y abrir el siguiente, en microsegundos.
static var _gaps: PackedInt32Array = PackedInt32Array()


## Abre el cronómetro de [param id]. No hace nada con la sonda apagada.
##
## Llamarla dos veces seguidas sin [method end] pisa la marca anterior: la sonda
## no es reentrante a propósito, porque un contador de anidamiento costaría más
## que lo que mide.
static func begin(id: StringName) -> void:
	if not enabled:
		return
	_open[id] = Time.get_ticks_usec()


## Cierra el cronómetro de [param id] y acumula lo que duró. Sin un [method begin]
## previo no acumula nada.
static func end(id: StringName) -> void:
	if not enabled:
		return
	var started := int(_open.get(id, 0))
	if started == 0:
		return
	_open[id] = 0
	_totals[id] = int(_totals.get(id, 0)) + (Time.get_ticks_usec() - started)
	_calls[id] = int(_calls.get(id, 0)) + 1


## Enciende la sonda y deja los acumuladores en cero.
static func start() -> void:
	reset()
	enabled = true


## Apaga la sonda. Los acumuladores quedan como estaban, para poder leerlos.
static func stop() -> void:
	enabled = false
	_open.clear()
	_tick_open_usec = 0


## Vacía los acumuladores y ancla el contador de ticks de física.
static func reset() -> void:
	_totals.clear()
	_calls.clear()
	_open.clear()
	_frames_at_reset = Engine.get_physics_frames()
	_process_frames_at_reset = Engine.get_process_frames()
	_tick_open_usec = 0
	_tick_close_usec = 0
	_tick_total_usec = 0
	_tick_brackets = 0
	_gaps = PackedInt32Array()


## Microsegundos acumulados por [param id] desde el último [method reset].
static func total_usec(id: StringName) -> int:
	return int(_totals.get(id, 0))


## Llamadas cerradas por [param id] desde el último [method reset].
static func call_count(id: StringName) -> int:
	return int(_calls.get(id, 0))


## Ticks de física transcurridos desde el último [method reset]; nunca menor que 1.
static func physics_frames() -> int:
	return maxi(Engine.get_physics_frames() - _frames_at_reset, 1)


## Fotogramas de proceso desde el último [method reset]; nunca menor que 1.
static func process_frames() -> int:
	return maxi(Engine.get_process_frames() - _process_frames_at_reset, 1)


# --- Total del tick y hueco de Jolt (WP-29) -----------------------------------------------------

## Abre el tick de física. La llama el [PerfBracket] de prioridad más baja, que es
## el primer `_physics_process` del árbol.
static func tick_open() -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	if _tick_close_usec > 0:
		_gaps.append(now - _tick_close_usec)
	_tick_open_usec = now


## Cierra el tick de física. La llama el [PerfBracket] de prioridad más alta, que es
## el último `_physics_process` del árbol.
static func tick_close() -> void:
	if not enabled or _tick_open_usec == 0:
		return
	var now := Time.get_ticks_usec()
	_tick_total_usec += now - _tick_open_usec
	_tick_brackets += 1
	_tick_open_usec = 0
	_tick_close_usec = now


## Ticks que cerraron con los dos [PerfBracket] puestos.
static func bracketed_ticks() -> int:
	return _tick_brackets


## Milisegundos de **todo** el GDScript del tick, medidos entre [method tick_open] y
## [method tick_close]. Vale `0.0` si nadie colgó los [PerfBracket].
static func scripts_ms_per_tick() -> float:
	if _tick_brackets <= 0:
		return 0.0
	return float(_tick_total_usec) / 1000.0 / float(_tick_brackets)


## Percentil [param p] del hueco entre ticks, en milisegundos.
##
## Con `Engine.max_fps` por debajo de los ticks por segundo, el motor encadena
## varios pasos dentro de la misma iteración y la mayoría de los huecos son el paso
## de Jolt puro; los pocos que se comieron un fotograma de render quedan arriba. Por
## eso el estimador es un percentil bajo y no la media.
static func gap_ms(p: float = 25.0) -> float:
	if _gaps.is_empty():
		return 0.0
	var sorted := Array(_gaps)
	sorted.sort()
	var index := clampi(int(roundf(p / 100.0 * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return float(sorted[index]) / 1000.0


## Cuántos huecos entre ticks se registraron.
static func gap_count() -> int:
	return _gaps.size()


## Si el hueco entre ticks mide el paso de Jolt y no un fotograma de render.
##
## Sólo lo mide cuando el motor encadena **varios** pasos de física dentro de la
## misma iteración del bucle principal, y eso pasa únicamente con el cuadro topado
## por debajo de los ticks por segundo. Sin tope, a 130 fps con física a 100 Hz, casi
## toda iteración trae un tick o ninguno y el hueco es el fotograma entero: medido en
## WP-29, 6,5 ms donde el paso real son 0,42.
static func gap_is_valid() -> bool:
	return Engine.max_fps > 0 and Engine.max_fps < Engine.physics_ticks_per_second


## Milisegundos por tick de física que gastó [param id] desde el último
## [method reset].
static func ms_per_tick(id: StringName) -> float:
	return float(total_usec(id)) / 1000.0 / float(physics_frames())


## Milisegundos por fotograma de `_process` que gastó [param id]. Es el divisor que
## corresponde a [constant PROCESS_IDS]: dividir esos identificadores por ticks de
## física daría un número que el jugador no paga.
static func ms_per_frame(id: StringName) -> float:
	return float(total_usec(id)) / 1000.0 / float(process_frames())


## Desglose `{id: ms/tick}` de todos los identificadores de [constant IDS], estén
## o no instrumentados en esta corrida (los que no midieron valen `0.0`).
static func breakdown() -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for id: StringName in IDS:
		result[id] = ms_per_tick(id)
	return result


## Desglose `{id: ms/fotograma}` de todos los identificadores de
## [constant PROCESS_IDS].
static func process_breakdown() -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for id: StringName in PROCESS_IDS:
		result[id] = ms_per_frame(id)
	return result


## Suma de los identificadores de la **fase de callbacks**, en ms por tick. Es lo
## que se compara con [method scripts_ms_per_tick]: los dos miden lo mismo.
static func measured_ms_per_tick() -> float:
	var total := 0.0
	for id: StringName in IDS:
		if STEP_IDS.has(id):
			continue
		total += ms_per_tick(id)
	return total


## Suma de [constant STEP_IDS], en ms por tick: lo que corre dentro del paso del
## servidor y por lo tanto vive dentro del hueco de [method gap_ms].
static func step_ms_per_tick() -> float:
	var total := 0.0
	for id: StringName in STEP_IDS:
		total += ms_per_tick(id)
	return total


## Suma de [constant PROCESS_IDS], en milisegundos por fotograma.
static func measured_ms_per_frame() -> float:
	var total := 0.0
	for id: StringName in PROCESS_IDS:
		total += ms_per_frame(id)
	return total
