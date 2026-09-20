## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Barra del jefe (`docs/12` §4.1 y §8).
##
## Arriba al centro, **una barra por punto débil** y no una barra de vida única: el
## Arachnodroid tiene 8 —4 rodillas, el visor y 3 núcleos, `docs/07` §4— y lo que el
## jugador necesita saber no es «cuánta vida le queda» sino «qué puedo romper ahora».
## Las barras salen en el orden del [EnemyProfile], que es el orden de `docs/07` §4.
##
## Tres estados por barra ([enum State]):
## - **expuesta**: relleno cian [constant CombatHUDPalette.TARGET], que es el color
##   diegético de lo que se puede romper (`docs/13` §3).
## - **cubierta**: atenuada y con hachurado diagonal. El visor sólo se enciende
##   mientras el jefe ataca y los núcleos piden tres rodillas rotas y estar debajo
##   (`docs/07` §4): el hachurado dice «existe, todavía no».
## - **rota**: vacía y tachada en gris. Gris y no rojo: el rojo del HUD es peligro
##   —telegrafía, casco, enemigo— y una parte rota es exactamente lo contrario.
##
## ## Los rótulos por grupo (WP-24d)
##
## Ocho segmentos sin nombre eran ocho segmentos sin nombre: el feedback de la primera
## partida fue «no entendí cómo matarlo». Ahora cada corrida contigua de puntos
## débiles del mismo `hud_key` lleva su rótulo encima —**RODILLAS · VISOR ·
## NÚCLEOS**—, y el grupo entero destella un instante cuando pasa a estar expuesto:
## los núcleos al abrirse la carcasa, el visor mientras el jefe carga el láser. Ese
## destello es lo que convierte la barra en una **instrucción**: lo que se enciende es
## lo que hay que disparar ahora.
##
## Los grupos salen del `hud_key` del [WeakPointProfile], no de una tabla en este
## archivo: un jefe nuevo con otros puntos débiles agrupa solo.
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

## Estado de una barra.
enum State {
	EXPOSED, ## Se puede romper ahora mismo.
	COVERED, ## Existe pero todavía no se puede romper.
	BROKEN,  ## Ya se rompió; no vuelve.
}

## Ancho total del bloque de barras, en píxeles.
const TOTAL_WIDTH: float = 620.0

## Alto de cada barra, en píxeles.
const BAR_HEIGHT: float = 11.0

## Hueco entre dos barras, en píxeles.
const BAR_GAP: float = 6.0

## Distancia del borde superior del lienzo al bloque, en píxeles.
##
## No es un número libre: la cinta de rumbo del `FlightHUD` ocupa hasta la `y` 110 del
## mismo lienzo de 1280 × 720 (`hud/hud.tscn`), y los dos HUD se dibujan a la vez.
const TOP_MARGIN: float = 118.0

## Alto del renglón de rótulos de grupo, en píxeles. Es lo que las barras bajan
## respecto de WP-22 para hacerles lugar; la franja de ciudad sigue en la `y` 184
## ([constant HUDCityBar.TOP_MARGIN]), así que sobran casi cuarenta píxeles.
const GROUP_ROW_HEIGHT: float = 16.0

## Línea base del nombre del jefe y de la fase, relativa a [constant TOP_MARGIN].
const NAME_OFFSET: float = -10.0

## Línea base de los rótulos de grupo, relativa a [constant TOP_MARGIN].
const GROUP_OFFSET: float = 10.0

## Tamaño de la fuente de los rótulos de grupo, en píxeles.
const GROUP_FONT_SIZE: int = 13

## Paso del hachurado de una barra cubierta, en píxeles.
const HATCH_STEP: float = 7.0

## Duración del destello de un grupo que pasa a expuesto, en segundos.
const PULSE_SECONDS: float = 0.55

## Cuánto se agranda el marco del destello en su primer cuadro, en píxeles.
const PULSE_GROW: float = 7.0

## Clave del rótulo de fase.
const PHASE_KEY: String = "HUD_BOSS_PHASE"

## Clave de respaldo del nombre del jefe, si el perfil no trae `display_key`.
const FALLBACK_NAME_KEY: String = "ENEMY_ARACHNODROID"

## Prefijo de la clave del rótulo de grupo. Se arma con el `hud_key` del
## [WeakPointProfile] sin su propio prefijo: `WP_KNEE` → `HUD_WP_GROUP_KNEE`.
const GROUP_KEY_PREFIX: String = "HUD_WP_GROUP_"

## Prefijo que traen los `hud_key` del perfil (`docs/12`).
const WEAK_KEY_PREFIX: String = "WP_"

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

## Corridas contiguas del mismo `hud_key`, como `Vector2i(primera_barra, cuántas)`.
var _groups: Array[Vector2i] = []

## `hud_key` de cada grupo, en el mismo orden que [member _groups].
var _group_keys: PackedStringArray = PackedStringArray()

## Segundos que le quedan al destello de cada grupo.
var _pulses: PackedFloat32Array = PackedFloat32Array()

## Exposición de cada grupo en el cuadro anterior, para detectar el flanco. Vacío
## mientras no se haya evaluado ninguna vez.
var _group_was_exposed: Array[bool] = []


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
		# Sin jefe no hay grupos: dejar los de antes haría que [method group_count]
		# prometiera tramos que ya no tienen barras debajo.
		_build_groups()
		return _ordered
	if boss == _ordered_for and not _ordered.is_empty():
		return _ordered
	_ordered_for = boss
	_ordered = _build_order(boss)
	_build_groups()
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


## Estado de la barra [param index].
func state_at(index: int) -> State:
	if is_broken_at(index):
		return State.BROKEN
	return State.EXPOSED if is_exposed_at(index) else State.COVERED


# --- Grupos (WP-24d) --------------------------------------------------------------------------

## Cuántos grupos contiguos de puntos débiles tiene el jefe. Para el Arachnodroid son
## 3: rodillas, visor y núcleos.
func group_count() -> int:
	var _points := weak_points()
	return _groups.size()


## Primera barra y cantidad de barras del grupo [param index].
func group_span(index: int) -> Vector2i:
	var _points := weak_points()
	if index < 0 or index >= _groups.size():
		return Vector2i.ZERO
	return _groups[index]


## `hud_key` del grupo [param index] tal como lo declara el [WeakPointProfile]
## (`WP_KNEE`, `WP_VISOR`, `WP_CORE`), o `""`.
func group_key(index: int) -> String:
	var _points := weak_points()
	if index < 0 or index >= _group_keys.size():
		return ""
	return _group_keys[index]


## Clave de traducción del rótulo del grupo [param index] (`HUD_WP_GROUP_KNEE`…).
func group_label_key(index: int) -> String:
	var key := group_key(index)
	if key.is_empty():
		return ""
	if key.begins_with(WEAK_KEY_PREFIX):
		return GROUP_KEY_PREFIX + key.substr(WEAK_KEY_PREFIX.length())
	return key


## Rótulo del grupo [param index], ya traducido y en mayúsculas de HUD.
##
## Si la clave plural no existe todavía en el CSV, cae al `hud_key` singular del
## perfil: es preferible «RODILLA» a ver `HUD_WP_GROUP_KNEE` en pantalla (riesgo 12
## de `docs/12` §10).
func group_label(index: int) -> String:
	var key := group_label_key(index)
	if key.is_empty():
		return ""
	var text := tr(key)
	if text == key:
		text = tr(group_key(index))
	return text.to_upper()


## `true` si alguna barra del grupo [param index] está expuesta.
func is_group_exposed(index: int) -> bool:
	var span := group_span(index)
	for offset: int in span.y:
		if is_exposed_at(span.x + offset):
			return true
	return false


## `true` si todas las barras del grupo [param index] están rotas.
func is_group_broken(index: int) -> bool:
	var span := group_span(index)
	if span.y <= 0:
		return false
	for offset: int in span.y:
		if not is_broken_at(span.x + offset):
			return false
	return true


## Destello del grupo [param index], de 1 —recién expuesto— a 0.
func group_pulse(index: int) -> float:
	var _points := weak_points()
	if index < 0 or index >= _pulses.size():
		return 0.0
	return clampf(_pulses[index] / PULSE_SECONDS, 0.0, 1.0)


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


func _tick(delta: float) -> void:
	var pulsing := _tick_pulses(delta)
	# Los HP se leen del enemigo, así que hay que vigilarlos; pero pedir redibujo
	# cuadro a cuadro con ocho barras quietas es justo el riesgo 5 de `docs/12` §10.
	# La firma es barata y cambia en cuanto se mueve un HP, un estado o la fase.
	var signature := _signature()
	if signature == _last_signature and not pulsing:
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
	var top := TOP_MARGIN + GROUP_ROW_HEIGHT

	var font := HUDDraw.font_mono()
	var name_key := FALLBACK_NAME_KEY
	if boss != null and boss.profile != null and not boss.profile.display_key.is_empty():
		name_key = boss.profile.display_key
	HUDDraw.text(self, font, Vector2(left, TOP_MARGIN + NAME_OFFSET),
			tr(name_key).to_upper(), 19, HORIZONTAL_ALIGNMENT_LEFT, TOTAL_WIDTH * 0.6,
			CombatHUDPalette.TARGET)

	var phase := phase_number()
	if phase > 0:
		var chevrons := ""
		for _index: int in phase:
			chevrons += "»"
		HUDDraw.text(self, font, Vector2(left + TOTAL_WIDTH * 0.4, TOP_MARGIN + NAME_OFFSET),
				"%s %s" % [chevrons, tr(PHASE_KEY).format([number_text(str(phase))])],
				17, HORIZONTAL_ALIGNMENT_RIGHT, TOTAL_WIDTH * 0.6,
				CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, 0.85))

	_draw_groups(left, bar_width, top)

	for index: int in count:
		var rect := Rect2(Vector2(left + (bar_width + BAR_GAP) * float(index), top),
				Vector2(bar_width, BAR_HEIGHT))
		draw_rect(rect.grow(1.5), CombatHUDPalette.SHADOW, true)
		draw_rect(rect, CombatHUDPalette.TRACK, true)
		match state_at(index):
			State.BROKEN:
				_draw_broken(rect)
			State.EXPOSED:
				_draw_fill(rect, bar_fill(index), CombatHUDPalette.TARGET)
			_:
				_draw_fill(rect, bar_fill(index),
						CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, 0.34))
				_draw_hatch(rect)


# --- Internos ---------------------------------------------------------------------------------

## Rótulos de grupo y marco del destello.
func _draw_groups(left: float, bar_width: float, top: float) -> void:
	var font := HUDDraw.font_mono()
	for index: int in _groups.size():
		var span := _groups[index]
		if span.y <= 0:
			continue
		var origin := left + (bar_width + BAR_GAP) * float(span.x)
		var width := (bar_width + BAR_GAP) * float(span.y) - BAR_GAP
		var pulse := group_pulse(index)
		var label := group_label(index)
		if not label.is_empty():
			var colour := CombatHUDPalette.TEXT_DIM
			if is_group_broken(index):
				colour = CombatHUDPalette.with_alpha(CombatHUDPalette.TEXT_DIM, 0.40)
			elif is_group_exposed(index):
				colour = CombatHUDPalette.TARGET
			HUDDraw.text(self, font, Vector2(origin, TOP_MARGIN + GROUP_OFFSET), label,
					GROUP_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, width, colour)
		if pulse <= 0.0:
			continue
		# El marco nace agrandado y se cierra sobre las barras: el gesto dice «mirá
		# acá» sin tapar nada, porque es una línea de un píxel y medio.
		var frame := Rect2(Vector2(origin, top), Vector2(width, BAR_HEIGHT))
		draw_rect(frame.grow(2.0 + PULSE_GROW * pulse),
				CombatHUDPalette.with_alpha(CombatHUDPalette.TARGET, pulse), false, 1.5)


## Baja los destellos y detecta el flanco «el grupo pasó a expuesto». Devuelve `true`
## si hay alguno encendido, que es lo que obliga a redibujar cuadro a cuadro.
func _tick_pulses(delta: float) -> bool:
	var count := group_count()
	if count <= 0:
		return false
	var first_time := _group_was_exposed.size() != count
	if first_time:
		_group_was_exposed.resize(count)
	var pulsing := false
	for index: int in count:
		if _pulses[index] > 0.0:
			_pulses[index] = maxf(_pulses[index] - delta, 0.0)
		var exposed := is_group_exposed(index)
		# En el primer paso sólo se toma la foto: los núcleos y el visor arrancan
		# cubiertos, pero las rodillas arrancan expuestas y un destello de bienvenida
		# sería ruido justo cuando el jugador está leyendo el rótulo de la ronda.
		if not first_time and exposed and not _group_was_exposed[index]:
			_pulses[index] = PULSE_SECONDS
		_group_was_exposed[index] = exposed
		pulsing = pulsing or _pulses[index] > 0.0
	return pulsing


## Relleno de una barra viva.
func _draw_fill(rect: Rect2, fill: float, colour: Color) -> void:
	if fill <= 0.0:
		return
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), colour, true)


## Tachado de una barra rota, en gris. Se dibuja sobre la carcasa vacía, no sobre
## relleno: una parte rota no vuelve.
func _draw_broken(rect: Rect2) -> void:
	var colour := CombatHUDPalette.with_alpha(CombatHUDPalette.TEXT_DIM, 0.85)
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


## Agrupa las barras por corridas contiguas del mismo `hud_key` del perfil.
func _build_groups() -> void:
	_groups.clear()
	_group_keys.clear()
	_group_was_exposed.clear()
	for index: int in _ordered.size():
		var key := WeakPointTracker.group_key_of(_ordered[index])
		if not _group_keys.is_empty() and _group_keys[_group_keys.size() - 1] == key:
			var last := _groups[_groups.size() - 1]
			_groups[_groups.size() - 1] = Vector2i(last.x, last.y + 1)
			continue
		_groups.append(Vector2i(index, 1))
		_group_keys.append(key)
	_pulses.resize(_groups.size())
	_pulses.fill(0.0)


## Cadena barata que resume lo que se está dibujando.
func _signature() -> String:
	var boss := primary()
	if boss == null:
		return ""
	var parts := PackedStringArray()
	parts.append(str(phase_number()))
	for index: int in weak_points().size():
		parts.append("%d%.3f" % [int(state_at(index)), bar_fill(index)])
	return "|".join(parts)


## Tira el caché del orden. Lo llama todo lo que puede cambiar quién es el jefe.
func _invalidate_order() -> void:
	_ordered.clear()
	_ordered_for = null
	_groups.clear()
	_group_keys.clear()
	_group_was_exposed.clear()
	_pulses.resize(0)


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
