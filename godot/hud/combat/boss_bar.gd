## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Barra del jefe (`docs/12` §4.1 y §8).
##
## Arriba al centro, **una barra por punto débil** y no una barra de vida única: el
## Arachnodroid tiene 8 —4 rodillas, el visor y 3 núcleos, `docs/07` §4— y lo que el
## jugador necesita saber no es «cuánta vida le queda» sino «qué puedo romper ahora».
## Las barras salen en el orden del [EnemyProfile], que es el orden de `docs/07` §4.
##
## Tres estados por barra:
## - **expuesta**: relleno cian [constant CombatHUDPalette.TARGET], que es el color
##   diegético de lo que se puede romper (`docs/13` §3).
## - **cubierta**: atenuada y con hachurado diagonal. El visor sólo se enciende
##   mientras el jefe ataca y los núcleos piden tres rodillas rotas y estar debajo
##   (`docs/07` §4): el hachurado dice «existe, todavía no».
## - **rota**: vacía, con una cruz encima.
##
## ## Por qué el estado no sale sólo del polling
##
## Las tres señales del bus (`enemy_part_broken`, `enemy_weak_point_state`,
## `enemy_phase_changed`) **mandan** sobre lo que se lee de [EnemyBase]. Dos razones:
## la exposición se recalcula a 10 Hz y las fases a 4 Hz (`docs/06` §2), así que el
## evento llega antes que el polling; y `combat_hud_check` inyecta hechos sintéticos
## sobre un jefe congelado, que es la única forma de verificar los ocho estados sin
## depender de la IA de WP-18. Los HP sí se leen del [EnemyPart], porque de eso no
## hay evento.
class_name HUDBossBar
extends CombatHUDComponent

## Ancho total del bloque de barras, en píxeles.
const TOTAL_WIDTH: float = 620.0

## Alto de cada barra, en píxeles.
const BAR_HEIGHT: float = 11.0

## Hueco entre dos barras, en píxeles.
const BAR_GAP: float = 6.0

## Distancia del borde superior del lienzo al bloque de barras, en píxeles.
##
## No es un número libre: la cinta de rumbo del `FlightHUD` ocupa hasta la `y` 110 del
## mismo lienzo de 1280 × 720 (`hud/hud.tscn`), y los dos HUD se dibujan a la vez.
const TOP_MARGIN: float = 118.0

## Paso del hachurado de una barra cubierta, en píxeles.
const HATCH_STEP: float = 7.0

## Clave del rótulo de fase.
const PHASE_KEY: String = "HUD_BOSS_PHASE"

## Clave de respaldo del nombre del jefe, si el perfil no trae `display_key`.
const FALLBACK_NAME_KEY: String = "ENEMY_ARACHNODROID"

## Enemigos vinculados, en orden de aparición. Se dibuja el primero vivo: el MVP
## tiene un jefe por ronda (`docs/11` §5), pero la lista deja lugar a las rondas de
## intercepción sin cambiar la interfaz.
var _enemies: Array[EnemyBase] = []

## Partes rotas conocidas por evento: `{part_id: true}`.
var _broken: Dictionary[StringName, bool] = {}

## Exposición conocida por evento: `{wp_id: bool}`.
var _exposed: Dictionary[StringName, bool] = {}

## Fase publicada por `enemy_phase_changed`, o `&""` si todavía no llegó ninguna.
var _phase_id: StringName = &""

## Cachés del último dibujo, para no pedir redibujo cuadro a cuadro sin motivo.
var _last_signature: String = ""

## Lista ordenada de puntos débiles y el jefe para el que se armó. Se rehace sólo al
## cambiar de jefe: [method weak_points] la consultan cuatro métodos por barra y por
## cuadro, y reordenar ocho elementos treinta veces por cuadro sería absurdo.
var _ordered: Array[WeakPoint] = []
var _ordered_for: EnemyBase = null


## Da de alta un enemigo. Idempotente: el mismo nodo dos veces no duplica barras.
func bind_enemy(enemy: Node3D) -> void:
	var boss := enemy as EnemyBase
	if boss == null or _enemies.has(boss):
		return
	_enemies.append(boss)
	_invalidate_order()
	queue_redraw()


## Da de baja un enemigo y olvida su estado si era el que se estaba dibujando.
func unbind_enemy(enemy: Node3D) -> void:
	var boss := enemy as EnemyBase
	if boss == null:
		return
	var was_primary := boss == primary()
	_enemies.erase(boss)
	if was_primary:
		_broken.clear()
		_exposed.clear()
		_phase_id = &""
	_invalidate_order()
	queue_redraw()


## Olvida todos los enemigos. La usa [CombatHUD] al desmontarse.
func clear_enemies() -> void:
	_enemies.clear()
	_broken.clear()
	_exposed.clear()
	_phase_id = &""
	_invalidate_order()
	queue_redraw()


## `Events.enemy_part_broken`.
func on_part_broken(enemy: Node3D, part_id: StringName) -> void:
	if not _is_tracked(enemy):
		return
	_broken[part_id] = true
	_exposed[part_id] = false
	queue_redraw()


## `Events.enemy_weak_point_state`.
func on_weak_point_state(enemy: Node3D, weak_point_id: StringName, exposed: bool) -> void:
	if not _is_tracked(enemy):
		return
	_exposed[weak_point_id] = exposed
	queue_redraw()


## `Events.enemy_phase_changed`.
func on_phase_changed(enemy: Node3D, phase_id: StringName) -> void:
	if not _is_tracked(enemy):
		return
	_phase_id = phase_id
	queue_redraw()


## El jefe que se está dibujando, o `null`.
func primary() -> EnemyBase:
	for enemy: EnemyBase in _enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree():
			return enemy
	return null


## Puntos débiles del jefe, en el orden de lectura de `docs/07` §4: las 4 rodillas,
## el visor y los 3 núcleos.
##
## Ese orden lo fija el [EnemyProfile], **no** [method EnemyBase.get_weak_points]:
## esa lista sale del grafo de partes, o sea del orden en que el modelo trae sus
## mallas, que es arbitrario y puede cambiar con un reimport. La barra del jefe no
## puede reordenarse sola entre dos importaciones del `.fbx`, así que la fuente de
## verdad es `profile.weak_points`, que es la tabla de `docs/07` §4 escrita a mano.
## Lo que el perfil no nombre —no debería pasar— se agrega al final en el orden que
## venga, para no esconder un punto débil huérfano.
func weak_points() -> Array[WeakPoint]:
	var boss := primary()
	if boss == null:
		_ordered.clear()
		_ordered_for = null
		return _ordered
	if boss == _ordered_for and not _ordered.is_empty():
		return _ordered
	_ordered_for = boss
	_ordered = _build_order(boss)
	return _ordered


## Arma la lista ordenada. La separa de [method weak_points] para que el caché sea
## una sola línea y no quede enterrado entre los `return` del orden.
func _build_order(boss: EnemyBase) -> Array[WeakPoint]:
	var found := boss.get_weak_points()
	if boss.profile == null or boss.profile.weak_points.is_empty():
		return found
	var by_id: Dictionary[StringName, WeakPoint] = {}
	for weak_point: WeakPoint in found:
		by_id[weak_point.weak_point_id()] = weak_point
	var ordered: Array[WeakPoint] = []
	for weak_profile: WeakPointProfile in boss.profile.weak_points:
		if weak_profile == null:
			continue
		var weak_point := by_id.get(weak_profile.weak_point_id, null) as WeakPoint
		if weak_point == null:
			continue
		ordered.append(weak_point)
		var _erased := by_id.erase(weak_profile.weak_point_id)
	for weak_point: WeakPoint in found:
		if by_id.has(weak_point.weak_point_id()):
			ordered.append(weak_point)
	return ordered


## Cantidad de barras. `docs/12` §8 fija 8 para el Arachnodroid.
func bar_count() -> int:
	return weak_points().size()


## Relleno de la barra [param index], de 0 a 1.
func bar_fill(index: int) -> float:
	var points := weak_points()
	if index < 0 or index >= points.size():
		return 0.0
	var weak_point := points[index]
	if is_broken_at(index):
		return 0.0
	var part := weak_point.part
	if part == null or part.max_hp <= 0.0:
		return 1.0
	return clampf(part.hp / part.max_hp, 0.0, 1.0)


## `true` si la barra [param index] corresponde a un punto débil ya roto.
func is_broken_at(index: int) -> bool:
	var points := weak_points()
	if index < 0 or index >= points.size():
		return false
	var weak_point := points[index]
	var id := weak_point.weak_point_id()
	return _broken.get(id, false) or weak_point.is_broken()


## `true` si la barra [param index] corresponde a un punto débil expuesto.
func is_exposed_at(index: int) -> bool:
	var points := weak_points()
	if index < 0 or index >= points.size():
		return false
	if is_broken_at(index):
		return false
	var weak_point := points[index]
	var id := weak_point.weak_point_id()
	if _exposed.has(id):
		return bool(_exposed[id])
	return weak_point.is_exposed()


## Número de fase, de 1 en adelante, derivado del `phase_id` (`p3_fury` → 3). Es la
## cantidad de chevrons que pide `docs/12` §9.2 fila 4. Devuelve 0 si todavía no hay
## fase.
func phase_number() -> int:
	var id := _phase_id
	if id == &"":
		var boss := primary()
		id = boss.current_phase() if boss != null else &""
	var text := String(id)
	if not text.begins_with("p"):
		return 0
	var digits := ""
	for index: int in range(1, text.length()):
		if not text[index].is_valid_int():
			break
		digits += text[index]
	return int(digits) if not digits.is_empty() else 0


func _tick(_delta: float) -> void:
	# Los HP se leen del enemigo, así que hay que vigilarlos; pero pedir redibujo
	# cuadro a cuadro con ocho barras quietas es justo el riesgo 5 de `docs/12` §10.
	# La firma es barata y cambia en cuanto se mueve un HP, un estado o la fase.
	var signature := _signature()
	if signature == _last_signature:
		return
	_last_signature = signature
	queue_redraw()


func _draw() -> void:
	if not begin_draw():
		return
	var points := weak_points()
	if points.is_empty():
		return
	var boss := primary()
	var count := points.size()
	var gaps := BAR_GAP * float(count - 1)
	var bar_width := maxf((TOTAL_WIDTH - gaps) / float(count), 4.0)
	var left := centre().x - TOTAL_WIDTH * 0.5
	var top := TOP_MARGIN

	var font := HUDDraw.font_mono()
	var name_key := FALLBACK_NAME_KEY
	if boss != null and boss.profile != null and not boss.profile.display_key.is_empty():
		name_key = boss.profile.display_key
	HUDDraw.text(self, font, Vector2(left, top - 10.0), tr(name_key).to_upper(), 19,
			HORIZONTAL_ALIGNMENT_LEFT, TOTAL_WIDTH * 0.6, CombatHUDPalette.TARGET)

	var phase := phase_number()
	if phase > 0:
		var chevrons := ""
		for _index: int in phase:
			chevrons += "»"
		HUDDraw.text(self, font, Vector2(left + TOTAL_WIDTH * 0.4, top - 10.0),
				"%s %s" % [chevrons, tr(PHASE_KEY).format([number_text(str(phase))])],
				17, HORIZONTAL_ALIGNMENT_RIGHT, TOTAL_WIDTH * 0.6,
				CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, 0.85))

	for index: int in count:
		var rect := Rect2(Vector2(left + (bar_width + BAR_GAP) * float(index), top),
				Vector2(bar_width, BAR_HEIGHT))
		draw_rect(rect.grow(1.5), CombatHUDPalette.SHADOW, true)
		draw_rect(rect, CombatHUDPalette.TRACK, true)
		if is_broken_at(index):
			_draw_broken(rect)
			continue
		var fill := bar_fill(index)
		var exposed := is_exposed_at(index)
		var colour := CombatHUDPalette.TARGET if exposed \
				else CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, 0.34)
		if fill > 0.0:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)),
					colour, true)
		if not exposed:
			_draw_hatch(rect)


# --- Internos ---------------------------------------------------------------------------------

## Cruz de una barra rota. Se dibuja sobre la carcasa vacía, no sobre relleno: una
## parte rota no vuelve.
func _draw_broken(rect: Rect2) -> void:
	var colour := CombatHUDPalette.with_alpha(CombatHUDPalette.DANGER, 0.75)
	HUDDraw.line(self, rect.position + Vector2(1.0, 1.0),
			rect.end - Vector2(1.0, 1.0), 1.5, colour)
	HUDDraw.line(self, Vector2(rect.position.x + 1.0, rect.end.y - 1.0),
			Vector2(rect.end.x - 1.0, rect.position.y + 1.0), 1.5, colour)


## Hachurado diagonal de una barra cubierta.
##
## Cada trazo baja a 45° desde `(x, arriba)` hasta `(x − alto, abajo)` y se recorta
## contra los dos bordes verticales del rectángulo, que es todo lo que hace falta
## porque la pendiente es 1: el recorte horizontal se traduce uno a uno en vertical.
func _draw_hatch(rect: Rect2) -> void:
	var colour := CombatHUDPalette.with_alpha(CombatHUDPalette.TEXT, 0.22)
	var height := rect.size.y
	var x := rect.position.x
	while x <= rect.end.x + height:
		var from := Vector2(x, rect.position.y)
		if from.x > rect.end.x:
			from = Vector2(rect.end.x, rect.position.y + (x - rect.end.x))
		var to := Vector2(x - height, rect.end.y)
		if to.x < rect.position.x:
			to = Vector2(rect.position.x, rect.end.y - (rect.position.x - (x - height)))
		if from.y < rect.end.y and to.y > rect.position.y and from.distance_to(to) > 0.5:
			draw_line(from, to, colour, 1.0, true)
		x += HATCH_STEP


## Cadena barata que resume lo que se está dibujando.
func _signature() -> String:
	var boss := primary()
	if boss == null:
		return ""
	var parts := PackedStringArray()
	parts.append(str(phase_number()))
	for index: int in weak_points().size():
		parts.append("%d%d%.3f" % [1 if is_broken_at(index) else 0,
				1 if is_exposed_at(index) else 0, bar_fill(index)])
	return "|".join(parts)


## Tira el caché del orden. Lo llama todo lo que puede cambiar quién es el jefe.
func _invalidate_order() -> void:
	_ordered.clear()
	_ordered_for = null


func _is_tracked(enemy: Node3D) -> bool:
	if enemy == null:
		return false
	var boss := enemy as EnemyBase
	if boss == null:
		return false
	if _enemies.has(boss):
		return true
	# Un enemigo que todavía no se vinculó pero que es el único del nivel: el bus
	# puede adelantarse a `bind_enemy()` en el mismo cuadro del `enemy_spawned`.
	return _enemies.is_empty()
