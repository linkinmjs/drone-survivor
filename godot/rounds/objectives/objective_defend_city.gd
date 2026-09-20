## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Objetivo 1 de la ronda 1: contener el asedio (`docs/11` §5).
##
## Cierra cuando el enemigo entra en [member target_phase_id] —es decir, cuando deja
## de ignorar al dron— o cuando pasan [member max_seconds] segundos, lo que ocurra
## primero. No hay forma de fallarlo: si la ciudad cae antes, la ronda ya terminó en
## derrota por su cuenta (`docs/11` §4.1).
##
## **La comparación es por índice, no por id** (`docs/11` §12, fila 5): las fases de
## un [EnemyProfile] están ordenadas y son monótonas, así que un salto de `p1_siege`
## directo a `p3_fury` también cierra el objetivo. Comparar ids sueltos lo dejaría
## abierto para siempre.
##
## ## Edificio protegido (WP-25b)
##
## Si la ronda declara uno (`docs/11` §1), el título pasa a ser «PROTEGÉ: ESCUELA 12»
## y su caída marca el objetivo como **fallido** con [method Objective.fail] —lo
## reenvía `RoundManager` desde `CityIntegrity.protected_fallen`—. Fallido no es
## terminado: el objetivo sigue corriendo, sigue cerrándose con `p2_alert` o con el
## reloj, y la cadena continúa. No hay derrota directa, que sigue siendo cosa de la
## integridad y sólo de la integridad.
##
## ## Discrepancia registrada con `docs/11` §5 (WP-24d)
##
## La tabla pide `get_progress()` = `elapsed / max_seconds` y `get_progress_text()` =
## `OBJ_DEFEND_CITY_PROGRESS` con la integridad en %. Las dos cosas cambian: la barra
## cuenta **rodillas rotas** y el texto es el contador «RODILLAS n/3». El motivo es el
## feedback que gobierna WP-24d —«no entendí cómo matarlo»—: en el primer minuto de la
## primera partida, un porcentaje de integridad que ya dibuja la [HUDCityBar] justo
## encima y un reloj invisible no dicen qué hay que **hacer**. El contador sí, y
## además engancha con el objetivo siguiente, que arranca desde el mismo número.
class_name ObjectiveDefendCity extends Objective

## Fase del enemigo que cierra el objetivo (`docs/07` §6).
@export var target_phase_id: StringName = &"p2_alert"

## Segundos tras los que el objetivo se cierra igual.
@export_range(1.0, 600.0, 0.5) var max_seconds: float = 90.0

## Ids de punto débil que alimentan el contador de la línea de tarea (`docs/07` §4).
## **No** cierran el objetivo: sólo lo cuentan.
@export var count_part_ids: PackedStringArray = PackedStringArray([
	"wp_leg_fl_knee", "wp_leg_fr_knee", "wp_leg_bl_knee", "wp_leg_br_knee",
])

## Meta del contador, que es la del objetivo siguiente (`docs/07` §6: 3 rodillas
## abren la carcasa). La barra no llega a llenarse en este objetivo y eso es correcto:
## lo que muestra es cuánto falta para el hito, no cuánto falta para esta línea.
@export_range(1, 16) var count_target: int = 3

## Clave de traducción del contador, con `{0}` rotas y `{1}` pedidas.
@export var count_key: String = "OBJ_COUNT_KNEES"

## Título cuando la ronda declara un edificio protegido, con `{0}` = su nombre
## (`docs/11` §1). Sin protegido manda [member Objective.title_key].
@export var protected_title_key: String = "OBJ_PROTECT_TITLE"

## Línea que reemplaza al título cuando el protegido cayó, con `{0}` = su nombre.
@export var protected_failed_key: String = "OBJ_PROTECT_FAILED"

var _elapsed: float = 0.0

## Índice de [member target_phase_id] dentro de las fases del enemigo, o `-1` si no
## se pudo resolver (entonces sólo cuenta el tiempo).
var _target_index: int = -1

## Ids de [member count_part_ids] ya rotos, sin repetidos.
var _broken: Dictionary[StringName, bool] = {}


func _setup() -> void:
	_target_index = _resolve_target_index()


func _on_start() -> void:
	if not Events.enemy_phase_changed.is_connected(_on_phase_changed):
		var _discard := Events.enemy_phase_changed.connect(_on_phase_changed)
	if not Events.enemy_part_broken.is_connected(_on_part_broken):
		var _discard := Events.enemy_part_broken.connect(_on_part_broken)
	if not Events.enemy_weak_point_state.is_connected(_on_weak_point_state):
		var _discard := Events.enemy_weak_point_state.connect(_on_weak_point_state)
	_recount()


func _on_restart() -> void:
	# El tiempo de asedio **no** se reinicia con el dron: lo que mide es cuánto
	# aguantó la ciudad, no cuánto sobrevivió el piloto. Las rodillas rotas tampoco:
	# siguen rotas.
	pass


func _on_stop() -> void:
	if Events.enemy_phase_changed.is_connected(_on_phase_changed):
		Events.enemy_phase_changed.disconnect(_on_phase_changed)
	if Events.enemy_part_broken.is_connected(_on_part_broken):
		Events.enemy_part_broken.disconnect(_on_part_broken)
	if Events.enemy_weak_point_state.is_connected(_on_weak_point_state):
		Events.enemy_weak_point_state.disconnect(_on_weak_point_state)


func _tick(delta: float) -> void:
	_elapsed += delta
	# El enemigo puede haber entrado en la fase antes de que este objetivo arrancara.
	if _reached_target_phase():
		finish()
		return
	if _elapsed >= max_seconds:
		finish()


## «PROTEGÉ: ESCUELA 12» cuando la ronda nombra un edificio, y el título genérico
## «CONTENÉ EL ASEDIO» cuando no (`docs/11` §1).
##
## El nombre se resuelve **en cada llamada** y no se cachea: el HUD reconstruye sus
## textos en `NOTIFICATION_TRANSLATION_CHANGED` y un nombre cacheado se quedaría en
## el idioma anterior.
func get_title_text() -> String:
	var name_text := _protected_name()
	if name_text.is_empty() or protected_title_key.is_empty():
		return super()
	return tr(protected_title_key).format([name_text])


## «ESCUELA 12: CAÍDA». Vacía si la ronda no declara protegido: entonces no hay
## nada que se pueda haber caído y el objetivo nunca se marca fallido.
func get_failed_text() -> String:
	var name_text := _protected_name()
	if name_text.is_empty() or protected_failed_key.is_empty():
		return ""
	return tr(protected_failed_key).format([name_text])


## Nombre del edificio protegido de la ronda en **mayúsculas de HUD**, o `""`.
##
## La clave `BLD_*` guarda «Escuela 12» en caja de oración porque la tarjeta de
## resultado la muestra así; los textos `OBJ_*` visibles van en mayúsculas desde
## WP-24d. Un solo nombre por edificio y cada superficie lo escribe como habla.
##
## Se lo pide a [CityIntegrity] y no a `RoundManager` porque el contexto ya trae la
## integridad tipada y el `round_manager` viene como [Node] suelto (`docs/11` §4.2:
## el objetivo no conoce la máquina de ronda).
func _protected_name() -> String:
	if ctx == null or ctx.city_integrity == null or not is_instance_valid(ctx.city_integrity):
		return ""
	var building := ctx.city_integrity.get_protected()
	return building.display_name().to_upper() if building != null else ""


func get_task_text() -> String:
	return objective_key if not objective_key.is_empty() else "OBJ_DEFEND_CITY_TITLE"


## Rodillas rotas sobre las que pide [member count_target]. Ver la discrepancia con
## `docs/11` §5 del encabezado.
func get_progress() -> float:
	return clampf(float(_broken.size()) / float(maxi(count_target, 1)), 0.0, 1.0)


## Contador «RODILLAS 1/3» de la línea de objetivo (`docs/12` §4.1).
func get_progress_text() -> String:
	var done := mini(_broken.size(), count_target)
	if count_key.is_empty():
		return "%d / %d" % [done, count_target]
	return tr(count_key).format([done, count_target])


func get_success_text() -> String:
	return tr("OBJ_DEFEND_CITY_DONE")


## Segundos que lleva el asedio.
func get_elapsed() -> float:
	return _elapsed


## Cuántos ids de [member count_part_ids] están rotos.
func get_broken_count() -> int:
	return _broken.size()


## Verdadero si algún enemigo del contexto ya alcanzó la fase objetivo.
func _reached_target_phase() -> bool:
	if ctx == null:
		return false
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy):
			continue
		if _target_index >= 0 and enemy.current_phase_index() >= _target_index:
			return true
		if _target_index < 0 and enemy.current_phase() == target_phase_id:
			return true
	return false


## La fase que trae el evento cuenta tanto como la que se lee del enemigo
## ([method Objective.phase_index_of] explica por qué).
func _on_phase_changed(enemy: Node3D, phase_id: StringName) -> void:
	if not active:
		return
	var announced := phase_index_of(enemy, phase_id)
	if _reached_target_phase() or (_target_index >= 0 and announced >= _target_index) \
			or (_target_index < 0 and phase_id == target_phase_id):
		finish()


func _on_part_broken(_enemy: Node3D, part_id: StringName, _position: Vector3) -> void:
	if not _counts(part_id):
		return
	_broken[part_id] = true


## Segunda fuente del contador, igual que en [ObjectiveBreakParts]: la exposición se
## recalcula a 10 Hz y cada cambio permite recontar contra las partes reales.
func _on_weak_point_state(_enemy: Node3D, weak_point_id: StringName,
		_exposed: bool) -> void:
	if not _counts(weak_point_id):
		return
	_recount()


## Recuenta contra lo que ya pasó. Es **aditivo**, nunca borra: una rodilla rota
## sigue rota aunque el enemigo se libere de la pata entera (`docs/07` §4).
func _recount() -> void:
	if ctx == null:
		return
	if ctx.round_manager != null and ctx.round_manager.has_method(&"get_broken_part_ids"):
		var ids: Array = ctx.round_manager.call(&"get_broken_part_ids")
		for part_id: StringName in ids:
			if _counts(part_id):
				_broken[part_id] = true
	for enemy: EnemyBase in ctx.enemies:
		if not is_instance_valid(enemy):
			continue
		for part: EnemyPart in enemy.get_parts():
			if part.is_broken() and _counts(part.part_id):
				_broken[part.part_id] = true


func _counts(part_id: StringName) -> bool:
	return count_part_ids.has(String(part_id))


## Posición de [member target_phase_id] en la lista de fases del primer enemigo.
func _resolve_target_index() -> int:
	var enemy := ctx.first_enemy() if ctx != null else null
	if enemy == null or enemy.profile == null:
		return -1
	for index: int in enemy.profile.phases.size():
		var phase: Dictionary = enemy.profile.phases[index]
		if StringName(phase.get("id", &"")) == target_phase_id:
			return index
	return -1
