## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Selector de utilidad (`docs/06` §10).
##
## Se le pasa el juego completo de acciones y un `ctx` armado una sola vez, y
## devuelve la acción elegida:
##
## 1. Se [b]descartan[/b] las que no pasan [method EnemyAction.can_run]
##    (enfriamiento, alcance, fase, partes rotas) y las de `score() <= 0`.
## 2. `weighted := score · personalidad · peso_de_fase · base_weight`, recortado
##    a `[0, 1]`.
## 3. Se ordena y se toman las `top_n` (3) mejores.
## 4. Se elige una al azar con peso `weighted²`. El cuadrado concentra la
##    elección en la mejor sin volverla determinista: con pesos 1.0, 0.8 y 0.6
##    las probabilidades pasan de 42/33/25 % a 50/32/18 %.
##
## [b]Reproducibilidad[/b]: el [RandomNumberGenerator] se siembra con
## `Global.round_seed` (más el id del enemigo), así que dos corridas con la
## misma semilla eligen exactamente la misma secuencia de acciones. Es lo que
## verifica `ai_check`.
##
## [b]Discrepancia con `docs/06` §14[/b]: allí el selector es un `Node` hijo de
## `Brain` con una señal `action_selected`. Acá es un [RefCounted] que el
## [EnemyFSM] posee, porque no necesita ni `_process` ni posición en el árbol; la
## señal sigue existiendo y la reemite el FSM.
class_name UtilitySelector extends RefCounted

## Se eligió una acción.
signal action_selected(attack_id: StringName, score: float)

## Acciones que entran en el sorteo si nadie fija otro número (`docs/06` §15).
const DEFAULT_TOP_N: int = 3

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_scores: Dictionary[StringName, float] = {}
var _last_rejections: Dictionary[StringName, String] = {}
var _last_pool: PackedStringArray = PackedStringArray()
var _decisions: int = 0


## Siembra el sorteo. [param seed_value] es `Global.round_seed` combinado con el
## id del enemigo, para que dos enemigos de la misma ronda no elijan al unísono.
func configure(seed_value: int) -> void:
	_rng.seed = seed_value
	_decisions = 0


## Elige una acción entre [param actions], o `null` si ninguna es elegible.
func select(actions: Array[EnemyAction], ctx: Dictionary, personality: Personality,
		top_n: int = DEFAULT_TOP_N) -> EnemyAction:
	_last_scores.clear()
	_last_rejections.clear()
	_last_pool = PackedStringArray()
	_decisions += 1

	var candidates: Array[Dictionary] = []
	for action: EnemyAction in actions:
		if action == null:
			continue
		var attack_id := action.id()
		if not action.can_run(ctx):
			_last_rejections[attack_id] = _reason(action, ctx)
			continue
		var raw := action.score(ctx)
		_last_scores[attack_id] = raw
		if raw <= 0.0:
			_last_rejections[attack_id] = "score %.3f" % raw
			continue
		var weighted := clampf(raw * _personality_weight(personality, attack_id)
				* _phase_weight(action, attack_id) * _base_weight(action), 0.0, 1.0)
		if weighted <= 0.0:
			_last_rejections[attack_id] = "peso %.3f" % weighted
			continue
		candidates.append({"action": action, "weighted": weighted, "score": raw})

	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa := float(a["weighted"])
		var wb := float(b["weighted"])
		if is_equal_approx(wa, wb):
			# Desempate estable por id: sin él, el orden de los nodos decidiría
			# qué acción entra en el `top_n` y la corrida dejaría de ser
			# reproducible al reordenar la escena.
			return String((a["action"] as EnemyAction).id()) \
					< String((b["action"] as EnemyAction).id())
		return wa > wb)

	var pool_size := clampi(top_n if top_n > 0 else DEFAULT_TOP_N, 1, candidates.size())
	var total := 0.0
	for index: int in pool_size:
		var entry := candidates[index]
		var weight := float(entry["weighted"])
		total += weight * weight
		_last_pool.append(String((entry["action"] as EnemyAction).id()))

	var chosen := candidates[0]["action"] as EnemyAction
	var chosen_score := float(candidates[0]["score"])
	if total > 0.0:
		var roll := _rng.randf() * total
		var accumulated := 0.0
		for index: int in pool_size:
			var entry := candidates[index]
			var weight := float(entry["weighted"])
			accumulated += weight * weight
			if roll <= accumulated:
				chosen = entry["action"] as EnemyAction
				chosen_score = float(entry["score"])
				break

	action_selected.emit(chosen.id(), chosen_score)
	return chosen


## Puntuaciones crudas de la última decisión, por id.
func last_scores() -> Dictionary[StringName, float]:
	return _last_scores


## Alias con el nombre de `docs/06` §14.
func debug_last_scores() -> Dictionary[StringName, float]:
	return _last_scores


## Motivo por el que cada acción quedó fuera de la última decisión.
func last_rejections() -> Dictionary[StringName, String]:
	return _last_rejections


## Ids que entraron en el sorteo de la última decisión (las `top_n` mejores).
func last_pool() -> PackedStringArray:
	return _last_pool


## Decisiones tomadas desde el último [method configure].
func decision_count() -> int:
	return _decisions


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## Peso de personalidad de [param attack_id], o 1.0 sin personalidad.
func _personality_weight(personality: Personality, attack_id: StringName) -> float:
	if personality == null:
		return 1.0
	return personality.weight_for(attack_id)


## Peso que la fase actual le da a la acción (`docs/07` §7). Sin enemigo, 1.0.
func _phase_weight(action: EnemyAction, attack_id: StringName) -> float:
	var host := action.owner_enemy()
	if host == null:
		return 1.0
	return host.utility_weight(attack_id)


## Peso base declarado en el [AttackProfile].
func _base_weight(action: EnemyAction) -> float:
	if action.profile == null:
		return 1.0
	return action.profile.base_weight


## Motivo legible del descarte, para los logs de `ai_check`.
func _reason(action: EnemyAction, ctx: Dictionary) -> String:
	if action.profile == null:
		return "sin perfil"
	if action.cooldown_remaining() > 0.0:
		return "cooldown %.2f s" % action.cooldown_remaining()
	var distance := action.target_distance(ctx)
	if distance < action.profile.min_range or distance > action.profile.max_range:
		return "rango %.1f m fuera de [%.1f, %.1f]" \
				% [distance, action.profile.min_range, action.profile.max_range]
	return "fase o partes"
