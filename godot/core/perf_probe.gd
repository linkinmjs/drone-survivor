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
## | `perception` | muestreo y rayo de LOS de `Perception` |
## | `bot_pilot` | piloto sintético de `tools/bot_pilot.gd` |
class_name PerfProbe
extends RefCounted

## Identificadores que `PerfSampler` tabula, en el orden en que se imprimen.
const IDS: Array[StringName] = [
	&"drone_integrator", &"projectile_pool", &"weapon_mount", &"aim_assist",
	&"perception", &"bot_pilot",
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


## Vacía los acumuladores y ancla el contador de ticks de física.
static func reset() -> void:
	_totals.clear()
	_calls.clear()
	_open.clear()
	_frames_at_reset = Engine.get_physics_frames()


## Microsegundos acumulados por [param id] desde el último [method reset].
static func total_usec(id: StringName) -> int:
	return int(_totals.get(id, 0))


## Llamadas cerradas por [param id] desde el último [method reset].
static func call_count(id: StringName) -> int:
	return int(_calls.get(id, 0))


## Ticks de física transcurridos desde el último [method reset]; nunca menor que 1.
static func physics_frames() -> int:
	return maxi(Engine.get_physics_frames() - _frames_at_reset, 1)


## Milisegundos por tick de física que gastó [param id] desde el último
## [method reset].
static func ms_per_tick(id: StringName) -> float:
	return float(total_usec(id)) / 1000.0 / float(physics_frames())


## Desglose `{id: ms/tick}` de todos los identificadores de [constant IDS], estén
## o no instrumentados en esta corrida (los que no midieron valen `0.0`).
static func breakdown() -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for id: StringName in IDS:
		result[id] = ms_per_tick(id)
	return result


## Suma de todos los identificadores, en milisegundos por tick.
static func measured_ms_per_tick() -> float:
	var total := 0.0
	for id: StringName in IDS:
		total += ms_per_tick(id)
	return total
