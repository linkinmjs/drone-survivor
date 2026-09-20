## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Asistencia de puntería y fijado de objetivo del arma primaria (`docs/08` §2.8).
##
## Es un [RefCounted] propiedad del [WeaponMount]: no tiene nodo ni proceso propio,
## el arma lo refresca a 20 Hz. Así la búsqueda de candidatos y sus consultas de
## línea de visión cuestan cinco veces menos que si corrieran a 100 Hz, que es
## justo el margen que `docs/15` le deja al combate.
##
## **Candidatos**: los nodos del grupo `weak_points`, donde `EnemyBase` mantiene
## **sólo los expuestos** (`docs/06` §5). Un punto débil que se vuelve a cubrir
## sale del grupo y, con él, de la asistencia y del lock, sin que haga falta
## ninguna señal ni ninguna baja explícita.
##
## **Corrección**: se aplica en el instante del disparo y **antes** de la
## dispersión, con `aim_dir.slerp(hacia_el_objetivo, strength)`. Como los dos
## vectores son unitarios, el `slerp` interpola el ángulo linealmente: con un
## objetivo a 3.0° y `strength` 0.35 el residual es exactamente 1.95°, que es lo
## que mide `weapon_check`.
##
## **Discrepancia registrada con `docs/08` §3.4 (nombre de la clase)**. El
## documento pide `class_name AimAssist`. No se puede: `GameSettings` ya declara
## un `enum AimAssist` (`docs/04` §3.3) y en Godot 4 una clase global gana la
## resolución de nombres dentro de cualquier script, de modo que declararla rompe
## `autoloads/game_settings.gd` con cuatro errores de parseo
## («Cannot assign a value of type game_settings.gd.AimAssist to variable
## "aim_assist" with specified type AimAssist»), y con él los once autoloads.
## Como `autoloads/*` está fuera del alcance de WP-14, la clase se llama
## [b]`WeaponAimAssist`[/b] y el archivo conserva la ruta del documento,
## `res://drone/weapons/aim_assist.gd`.
class_name WeaponAimAssist extends RefCounted

## Grupo donde `EnemyBase` publica los puntos débiles expuestos (`docs/06` §5).
const GROUP: StringName = &"weak_points"

## Desempate por distancia cuando dos candidatos están al mismo ángulo, en grados.
const ANGLE_TIE_DEG: float = 0.1

## Semiángulo del cono estrecho de la corrección, en grados.
var cone_deg: float = 3.5

## Fuerza de la corrección, de 0.0 a 1.0. La fija el menú, no el perfil.
var strength: float = 0.35

## Alcance máximo de la asistencia, en metros.
var max_range: float = 220.0

## Semiángulo del cono ampliado con el que se busca objetivo para el lock.
var lock_cone_deg: float = 12.0

## Ángulo a partir del cual se rompe el lock, en grados.
var lock_break_angle: float = 35.0

## Distancia a partir de la cual se rompe el lock, en metros.
var lock_break_range: float = 250.0

## Máscara de la consulta de línea de visión: `world | city` (129).
var los_mask: int = PhysicsLayers.QUERY_LOS

## Objetivo fijado por `lock_target` / `cycle_target`, o `null`. Lo consume el
## retículo del HUD (WP-22).
var locked_target: Node3D = null

var _target: Node3D = null
var _candidates: Array[Node3D] = []
var _lock_candidates: Array[Node3D] = []
var _origin: Vector3 = Vector3.ZERO
var _aim: Vector3 = Vector3.FORWARD


## Copia los parámetros del perfil y la opción del menú. Se llama al cambiar de
## perfil y cada vez que el jugador toca la opción de asistencia.
func configure(cone_degrees: float, assist_strength: float, range_max: float,
		mask: int) -> void:
	cone_deg = maxf(cone_degrees, 0.0)
	strength = clampf(assist_strength, 0.0, 1.0)
	max_range = maxf(range_max, 0.0)
	los_mask = mask


## Parámetros del lock, que `docs/08` §2.8 y §4 fijan aparte del cono estrecho.
func configure_lock(cone_degrees: float, break_angle_deg: float,
		break_range: float) -> void:
	lock_cone_deg = maxf(cone_degrees, 0.0)
	lock_break_angle = maxf(break_angle_deg, 0.0)
	lock_break_range = maxf(break_range, 0.0)


## Rehace las dos listas de candidatos y elige el mejor. Lo llama el arma a 20 Hz.
##
## [param space] puede venir en `null` —una escena sin mundo de física—; en ese
## caso se saltea el filtro de línea de visión y el resto sigue valiendo.
func refresh(origin: Vector3, aim_dir: Vector3, space: PhysicsDirectSpaceState3D,
		exclude: Array[RID]) -> void:
	_origin = origin
	_aim = aim_dir.normalized() if aim_dir.length_squared() > 0.0 else Vector3.FORWARD
	_candidates.clear()
	_lock_candidates.clear()
	_target = null

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	var narrow := cos(deg_to_rad(minf(cone_deg, 179.9)))
	var wide := cos(deg_to_rad(minf(lock_cone_deg, 179.9)))
	var best_angle := INF
	var best_distance := INF
	var scored: Array[Vector2] = []   # (ángulo en grados, distancia) por candidato ampliado

	for node: Node in tree.get_nodes_in_group(GROUP):
		var target := node as Node3D
		if target == null or not target.is_inside_tree():
			continue
		var offset := target.global_position - _origin
		var distance := offset.length()
		if distance <= 0.0001 or distance > max_range:
			continue
		var to_target := offset / distance
		var cosine := _aim.dot(to_target)
		if cosine < wide and cosine < narrow:
			continue
		if not _has_line_of_sight(space, target, exclude):
			continue
		var angle_deg := rad_to_deg(acos(clampf(cosine, -1.0, 1.0)))
		if cosine >= wide:
			_lock_candidates.append(target)
			scored.append(Vector2(angle_deg, distance))
		if cosine < narrow:
			continue
		_candidates.append(target)
		# Gana el de menor ángulo; a igualdad de ±0.1°, el más cercano.
		var better := angle_deg < best_angle - ANGLE_TIE_DEG
		var tied_and_closer := absf(angle_deg - best_angle) <= ANGLE_TIE_DEG \
				and distance < best_distance
		if better or tied_and_closer:
			best_angle = angle_deg
			best_distance = distance
			_target = target

	_sort_by_angle(scored)
	_validate_lock()


## Dirección corregida para este disparo (`docs/08` §2.8).
##
## Con lock activo manda el objetivo fijado y el cono estrecho se ignora; sin lock
## manda el mejor candidato del cono. Con `strength` 0 devuelve [param aim_dir]
## intacto, que es lo que pide `GameSettings.AimAssist.OFF`.
func apply(origin: Vector3, aim_dir: Vector3) -> Vector3:
	if strength <= 0.0:
		return aim_dir
	var target := locked_target if _is_valid(locked_target) else _target
	if target == null:
		return aim_dir
	var offset := target.global_position - origin
	if offset.length_squared() <= 0.0001:
		return aim_dir
	var corrected := aim_dir.normalized().slerp(offset.normalized(), strength)
	if corrected.length_squared() <= 0.0001:
		return aim_dir
	return corrected.normalized()


## Mejor candidato del cono estrecho, o `null`.
func get_target() -> Node3D:
	return _target


## Candidatos del cono estrecho de este refresco.
func get_candidates() -> Array[Node3D]:
	return _candidates.duplicate()


## Candidatos del cono ampliado, ordenados por ángulo. Es la lista que rota
## [method cycle_lock].
func get_lock_candidates() -> Array[Node3D]:
	return _lock_candidates.duplicate()


## Objetivo fijado, o `null`. Lo usa el retículo del HUD (WP-22).
func get_locked_target() -> Node3D:
	return locked_target if _is_valid(locked_target) else null


## `true` si hay un objetivo fijado y sigue siendo válido.
func has_lock() -> bool:
	return get_locked_target() != null


## Fija el mejor candidato del cono ampliado. Sin candidatos no hace nada y el
## lock anterior —si lo había— se conserva.
func lock() -> void:
	if _lock_candidates.is_empty():
		return
	locked_target = _lock_candidates[0]


## Rota entre los candidatos del cono ampliado. Sin lock previo equivale a
## [method lock] (`docs/08` §2.8).
func cycle_lock() -> void:
	if _lock_candidates.is_empty():
		locked_target = null
		return
	if not _is_valid(locked_target):
		locked_target = _lock_candidates[0]
		return
	var index := _lock_candidates.find(locked_target)
	locked_target = _lock_candidates[(index + 1) % _lock_candidates.size()] if index >= 0 \
			else _lock_candidates[0]


## Fija [param target] a mano. `null` limpia el lock.
func set_lock(target: Node3D) -> void:
	locked_target = target if _is_valid(target) else null


## Suelta el objetivo fijado.
func clear_lock() -> void:
	locked_target = null


## Olvida objetivo, lock y candidatos. Lo llama `WeaponMount.reset()` al reaparecer.
func reset() -> void:
	locked_target = null
	_target = null
	_candidates.clear()
	_lock_candidates.clear()


# --- Internos --------------------------------------------------------------------------------


## Línea de visión con máscara `1|8`: un punto débil tapado por un edificio no es
## candidato. Sin mundo de física el filtro no aplica y se da por visible.
func _has_line_of_sight(space: PhysicsDirectSpaceState3D, target: Node3D,
		exclude: Array[RID]) -> bool:
	if space == null or los_mask == 0:
		return true
	var query := PhysicsRayQueryParameters3D.create(_origin, target.global_position,
			los_mask, exclude)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	return space.intersect_ray(query).is_empty()


## Ordena [member _lock_candidates] por ángulo usando las puntuaciones paralelas
## de [method refresh]. Es una inserción sobre un arreglo de a lo sumo un puñado
## de elementos: no hace falta nada mejor y evita un `sort_custom` con lambda por
## refresco.
func _sort_by_angle(scored: Array[Vector2]) -> void:
	var count := _lock_candidates.size()
	for i: int in range(1, count):
		var node := _lock_candidates[i]
		var score := scored[i]
		var j := i - 1
		while j >= 0 and scored[j].x > score.x:
			_lock_candidates[j + 1] = _lock_candidates[j]
			scored[j + 1] = scored[j]
			j -= 1
		_lock_candidates[j + 1] = node
		scored[j + 1] = score


## Rompe el lock si el nodo dejó de valer, si salió del grupo `weak_points` o si
## se pasó de ángulo o de distancia (`docs/08` §2.8).
func _validate_lock() -> void:
	if not _is_valid(locked_target):
		locked_target = null
		return
	if not locked_target.is_in_group(GROUP):
		locked_target = null
		return
	var offset := locked_target.global_position - _origin
	var distance := offset.length()
	if distance > lock_break_range or distance <= 0.0001:
		locked_target = null
		return
	var angle_deg := rad_to_deg(acos(clampf(_aim.dot(offset / distance), -1.0, 1.0)))
	if angle_deg > lock_break_angle:
		locked_target = null


func _is_valid(node: Node3D) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()
