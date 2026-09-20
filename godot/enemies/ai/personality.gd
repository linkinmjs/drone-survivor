## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Personalidad de un enemigo (`docs/06` §10).
##
## Un peso por acción en `[1 − spread, 1 + spread]` (±0.30 por defecto), sorteado
## una sola vez en `_ready()` con un [RandomNumberGenerator] sembrado en
## `Global.round_seed`, y fijo el resto de la ronda. Dos partidas con la misma
## semilla abren igual; con semillas distintas, una araña prefiere `siege_beam`
## y otra `climb` (`docs/07` §7).
##
## El sorteo recorre los ids [b]ordenados[/b] a propósito: así el peso de un
## ataque no depende del orden en que los nodos cuelguen de `AttackLibrary`, y
## agregar un ataque nuevo no revuelve los de los demás salvo los que le siguen
## alfabéticamente.
class_name Personality extends RefCounted

## Dispersión por defecto si nadie pasa otra (`docs/06` §15).
const DEFAULT_SPREAD: float = 0.30

## Peso por ataque, en `[1 − spread, 1 + spread]`.
var weights: Dictionary[StringName, float] = {}

## Semilla con la que se sortearon los pesos.
var seed_value: int = 0

## Dispersión con la que se sortearon.
var spread: float = DEFAULT_SPREAD


## Construye una personalidad sorteando un peso por cada id de [param attack_ids].
static func from_seed(seed_value: int, attack_ids: PackedStringArray,
		spread: float = DEFAULT_SPREAD) -> Personality:
	var personality := Personality.new()
	personality.seed_value = seed_value
	personality.spread = maxf(spread, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ordered := attack_ids.duplicate()
	ordered.sort()
	for attack_id: String in ordered:
		personality.weights[StringName(attack_id)] = rng.randf_range(
				1.0 - personality.spread, 1.0 + personality.spread)
	return personality


## Peso de [param attack_id]. Un ataque que no se sorteó pesa 1.0: agregar una
## acción en caliente no puede dejarla fuera del selector.
func weight_for(attack_id: StringName) -> float:
	return float(weights.get(attack_id, 1.0))


## Ids con peso sorteado, en orden alfabético.
func attack_ids() -> PackedStringArray:
	var found := PackedStringArray()
	for attack_id: StringName in weights:
		found.append(String(attack_id))
	found.sort()
	return found


## Línea legible para los logs de los checks y del showcase.
func describe() -> String:
	var parts := PackedStringArray()
	for attack_id: String in attack_ids():
		parts.append("%s %.2f" % [attack_id, weights[StringName(attack_id)]])
	return "semilla %d · dispersión ±%.2f · %s" % [seed_value, spread, ", ".join(parts)]
