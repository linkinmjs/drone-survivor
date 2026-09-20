## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Estado compartido de «qué punto débil está expuesto y hace cuánto que no le pegás».
##
## Lo usan los dos componentes que WP-24d agrega al `CombatHUD` —[HUDWeakPointHint] y
## [HUDCoachTip]— porque los dos se encienden con la **misma** condición: hay al menos
## un punto débil expuesto y el jugador lleva [constant IDLE_SECONDS] segundos sin
## acertarle a ninguno. Tener la regla escrita una sola vez es lo que garantiza que el
## corchete cian y el consejo «los puntos débiles son los cian» aparezcan juntos y no
## con medio segundo de diferencia, que se leería como dos avisos distintos.
##
## Es un [RefCounted] y no un nodo: no dibuja, no tiene reloj propio —lo avanza quien
## lo posee, con la convención de acumuladores de `docs/00` §6— y cada componente
## tiene el suyo.
##
## ## De dónde sale el estado
##
## Igual que en [HUDBossBar]: los hechos del bus (`enemy_weak_point_state`,
## `enemy_part_broken`) **mandan** sobre lo que se lee de [EnemyBase], porque la
## exposición se recalcula a 10 Hz (`docs/06` §2) y porque `combat_hud_check` inyecta
## hechos sintéticos sobre un jefe congelado. Lo que no viaja en ninguna señal —la
## posición en el mundo del punto débil— se pregunta al nodo.
class_name WeakPointTracker
extends RefCounted

## Segundos sin acertarle a un punto débil tras los que el HUD sale a ayudar.
const IDLE_SECONDS: float = 8.0

## Enemigos vigilados, en orden de aparición.
var _enemies: Array[EnemyBase] = []

## Exposición conocida por evento: `{wp_id: bool}`.
var _exposed: Dictionary[StringName, bool] = {}

## Partes rotas conocidas por evento: `{part_id: true}`.
var _broken: Dictionary[StringName, bool] = {}

## Segundos acumulados **con algún punto débil expuesto** y sin acierto débil.
var _idle: float = 0.0


## Da de alta un enemigo. Idempotente.
func bind_enemy(enemy: Node3D) -> void:
	var boss := enemy as EnemyBase
	if boss == null or _enemies.has(boss):
		return
	_enemies.append(boss)


## Da de baja un enemigo y olvida su estado si era el único.
func unbind_enemy(enemy: Node3D) -> void:
	var boss := enemy as EnemyBase
	if boss == null:
		return
	_enemies.erase(boss)
	if _enemies.is_empty():
		clear()


## Olvida enemigos, exposiciones, roturas y el reloj.
func clear() -> void:
	_enemies.clear()
	_exposed.clear()
	_broken.clear()
	_idle = 0.0


## `Events.enemy_weak_point_state`.
func on_state(enemy: Node3D, weak_point_id: StringName, exposed: bool) -> void:
	if not _is_tracked(enemy):
		return
	_exposed[weak_point_id] = exposed


## `Events.enemy_part_broken`.
func on_broken(enemy: Node3D, part_id: StringName) -> void:
	if not _is_tracked(enemy):
		return
	_broken[part_id] = true
	_exposed[part_id] = false


## `Events.hit_confirmed` con `weak = true`: el jugador entendió, el reloj vuelve a
## cero y los dos avisos se apagan.
func on_weak_hit() -> void:
	_idle = 0.0


## Avanza el reloj. **Sólo corre con algún punto débil expuesto**: castigar los ocho
## segundos en los que el jefe tiene todo cubierto sería castigar al jugador por
## hacerle caso al HUD.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if has_exposed():
		_idle += delta
	else:
		_idle = 0.0


## Segundos sin acertarle a un punto débil expuesto.
func idle_seconds() -> float:
	return _idle


## `true` cuando hace falta salir a ayudar: hay blanco y el reloj se pasó.
func is_idle() -> bool:
	return _idle >= IDLE_SECONDS and has_exposed()


## Deja el reloj en [param seconds]. La usan los checks para no esperar ocho segundos
## de reloj manual, y [method CombatHUD.set_cinematic] para empezar de cero.
func set_idle_seconds(seconds: float) -> void:
	_idle = maxf(seconds, 0.0)


## `true` si algún punto débil vivo está expuesto ahora mismo.
func has_exposed() -> bool:
	return not exposed_points().is_empty()


## Puntos débiles expuestos y enteros de todos los enemigos vigilados.
func exposed_points() -> Array[WeakPoint]:
	var found: Array[WeakPoint] = []
	for enemy: EnemyBase in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		for weak_point: WeakPoint in enemy.get_weak_points():
			if _is_exposed(weak_point):
				found.append(weak_point)
	return found


## El punto débil expuesto más cercano a [param origin], o `null` si no hay ninguno.
func nearest(origin: Vector3) -> WeakPoint:
	var best: WeakPoint = null
	var best_distance := INF
	for weak_point: WeakPoint in exposed_points():
		var point := weak_point.world_position()
		if not point.is_finite():
			continue
		var distance := origin.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = weak_point
	return best


## Clave `WP_*` del grupo de [param weak_point], tal como la declara su
## [WeakPointProfile] (`docs/12`). `""` si el perfil no la trae.
static func group_key_of(weak_point: WeakPoint) -> String:
	if weak_point == null or weak_point.profile == null:
		return ""
	return weak_point.profile.hud_key


# --- Internos ---------------------------------------------------------------------------------

## Misma regla que [method HUDBossBar.is_exposed_at]: el evento manda y el nodo es el
## respaldo, y una parte rota no cuenta por más que el último evento dijera lo
## contrario.
func _is_exposed(weak_point: WeakPoint) -> bool:
	if weak_point == null:
		return false
	var id := weak_point.weak_point_id()
	if bool(_broken.get(id, false)) or weak_point.is_broken():
		return false
	if _exposed.has(id):
		return bool(_exposed[id])
	return weak_point.is_exposed()


func _is_tracked(enemy: Node3D) -> bool:
	if enemy == null:
		return false
	var boss := enemy as EnemyBase
	if boss == null:
		return false
	# Un enemigo que todavía no se vinculó pero que es el único del nivel: el bus
	# puede adelantarse al `bind_enemy()` en el mismo cuadro del `enemy_spawned`.
	return _enemies.has(boss) or _enemies.is_empty()
