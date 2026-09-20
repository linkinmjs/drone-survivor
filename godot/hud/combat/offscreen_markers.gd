## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Marcadores de lo que importa y no está en cuadro (`docs/12` §4.1 y §8).
##
## Recorre tres grupos —`enemies`, `pickups` y `buildings_under_siege`—, los proyecta
## con [method HUDProjection.marker_for] sobre el rectángulo de la pantalla con
## [constant MARGIN] px de margen y dibuja una flecha triangular con la distancia en
## metros. Como mucho [constant MAX_MARKERS], ordenados por cercanía.
##
## ## Por qué [method HUDProjection.marker_for] y no [method HUDProjection.project_point]
##
## Porque `marker_for` **nunca** devuelve `NAN` (`docs/12` §3.1): cuando el objetivo
## está detrás de la cámara o fuera del círculo del ojo de pez, anula la componente
## frontal, normaliza lo que queda y empuja el marcador al borde. Un marcador es
## justamente lo que hace falta cuando la cosa **no** se ve; si el HUD tuviera que
## decidir eso por su cuenta, cada componente reimplementaría la misma cuenta y
## alguno se olvidaría del caso del punto exactamente detrás, que es el que produce
## `NAN`.
##
## ## Por qué vive fuera del marco escalado
##
## El margen de 56 px y el borde de la pantalla son magnitudes **de pantalla**, no del
## lienzo de diseño de 1280 × 720: una flecha que marca el borde tiene que tocar el
## borde de verdad. Por eso este componente cuelga directo del `Root` del `CombatHUD`
## y no del `Frame`.
class_name HUDOffscreenMarkers
extends CombatHUDComponent

## Margen del rectángulo útil, en píxeles (`docs/12` §8).
const MARGIN: float = 56.0

## Marcadores simultáneos (`docs/12` §8).
const MAX_MARKERS: int = 6

## Cuántos de ellos llevan además la distancia escrita.
##
## Mitigación del riesgo 8 de `docs/12` §10: seis marcadores pueden saturar. Seis
## flechas se leen de un vistazo; seis rótulos de «PILA 327 m» apilados contra el
## mismo borde se pisan y no se lee ninguno.
##
## El reparto **no** es por cercanía sino por importancia: el jefe y el edificio bajo
## asedio se llevan el número siempre, y las pilas se reparten lo que sobre. Con el
## reparto por distancia, cinco pilas a 200 m dejaban al coloso —lo único que puede
## hacerte perder la ronda— como una flecha muda.
const LABELLED_MARKERS: int = 4

## Distancia por debajo de la cual dos rótulos se consideran superpuestos, en píxeles.
const LABEL_CLEARANCE: Vector2 = Vector2(150.0, 17.0)

## Cuánto se sube un rótulo que chocaría con otro, en píxeles.
const LABEL_STAGGER: float = 19.0

## Lado de la flecha, en píxeles (`docs/12` §4.1).
const ARROW_SIZE: float = 16.0

## Grupos que se recorren, en orden de prioridad para el desempate.
const GROUP_ENEMIES: StringName = &"enemies"
const GROUP_PICKUPS: StringName = &"pickups"
const GROUP_SIEGE: StringName = &"buildings_under_siege"

## Clases de marcador.
enum Kind {ENEMY, PICKUP, SIEGE}

## Clave de traducción del rótulo de cada clase.
const KIND_KEYS: Dictionary[int, String] = {
	Kind.ENEMY: "HUD_MARKER_ENEMY",
	Kind.PICKUP: "HUD_MARKER_BATTERY",
	Kind.SIEGE: "HUD_MARKER_SIEGE",
}

## Cámara impuesta por [CombatHUD]; si es `null` se usa la que dibuja la escena.
var camera: Camera3D = null

## Integridad de la ciudad, para [method CityIntegrity.get_under_siege]. El edificio
## bajo asedio es **uno solo por vez** (`docs/12` §10, riesgo 11).
var city: CityIntegrity = null

## Último cálculo, que es lo que dibuja `_draw()` y lo que leen los checks.
var _markers: Array[Dictionary] = []


func _tick(_delta: float) -> void:
	_markers = _compute()
	queue_redraw()


## Recalcula ahora y devuelve los marcadores vigentes.
##
## Cada entrada trae `pos`, `angle`, `offscreen`, `distance` y `kind`. `pos` siempre
## es finita y está dentro del rectángulo útil: es el contrato de
## [method HUDProjection.marker_for], y la fila 6 de `docs/12` §9.2 lo verifica.
func markers() -> Array[Dictionary]:
	_markers = _compute()
	return _markers.duplicate()


## Rectángulo de pantalla sobre el que se recortan los marcadores.
func screen_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(Vector2.ZERO, size)
	return viewport.get_visible_rect()


func _draw() -> void:
	if not begin_draw():
		return
	var font := HUDDraw.font_mono()
	var to_local := get_global_transform_with_canvas().affine_inverse()
	# Rótulos ya escritos, para escalonar los que caerían encima. Varios objetivos
	# detrás de la cámara se recortan al **mismo** punto del borde (riesgo 8 de
	# `docs/12` §10): sin esto, tres «PILA 327 m» se dibujan en el mismo renglón.
	var taken: Array[Vector2] = []
	var labelled := _label_slots()
	for slot: int in _markers.size():
		var marker := _markers[slot]
		var kind := int(marker["kind"])
		var colour := _colour(kind)
		var at: Vector2 = to_local * (marker["pos"] as Vector2)
		if not at.is_finite():
			continue
		var angle := float(marker["angle"])
		var offscreen := bool(marker["offscreen"])
		if offscreen:
			_draw_arrow(at, angle, colour)
		else:
			_draw_diamond(at, colour)
		if not labelled.has(slot):
			continue
		# El rótulo va hacia **adentro** de la pantalla, en contra de la flecha: contra
		# el borde inferior, «debajo» es fuera del cuadro, y dos marcadores vecinos
		# escribirían encima del mismo renglón.
		var anchor := at + Vector2(0.0, ARROW_SIZE + 20.0)
		if offscreen:
			anchor = at - Vector2.from_angle(angle) * (ARROW_SIZE + 16.0) + Vector2(0.0, 6.0)
		anchor = _stagger(anchor, taken)
		taken.append(anchor)
		var label := "%s %s" % [tr(String(KIND_KEYS.get(kind, ""))),
				number_text("%d m" % [roundi(float(marker["distance"]))])]
		HUDDraw.text(self, font, anchor - Vector2(70.0, 0.0), label, 15,
				HORIZONTAL_ALIGNMENT_CENTER, 140.0,
				CombatHUDPalette.with_alpha(colour, 0.9))


# --- Internos ---------------------------------------------------------------------------------

## Junta, ordena y proyecta. Devuelve como mucho [constant MAX_MARKERS] entradas.
func _compute() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active := _camera()
	if active == null:
		return result
	var tree := get_tree()
	if tree == null:
		return result

	var origin := active.global_position
	var found: Array[Dictionary] = []
	for pair: Array in [[GROUP_ENEMIES, Kind.ENEMY], [GROUP_PICKUPS, Kind.PICKUP],
			[GROUP_SIEGE, Kind.SIEGE]]:
		for node: Node in tree.get_nodes_in_group(pair[0] as StringName):
			var spatial := node as Node3D
			if spatial == null or not spatial.is_inside_tree():
				continue
			if not _is_active(spatial):
				continue
			var point := spatial.global_position
			if not point.is_finite():
				continue
			found.append({"point": point, "kind": int(pair[1]),
					"distance": origin.distance_to(point), "node": spatial})

	# `get_under_siege()` es una consulta y no un hecho del bus (`docs/12` §7), así
	# que el edificio marcado puede no estar todavía en el grupo cuando se lo pide.
	if city != null and is_instance_valid(city):
		var besieged := city.get_under_siege()
		if besieged != null and besieged.is_inside_tree():
			var already := false
			for entry: Dictionary in found:
				if entry["node"] == besieged:
					already = true
					break
			if not already:
				found.append({"point": besieged.global_position, "kind": int(Kind.SIEGE),
						"distance": origin.distance_to(besieged.global_position),
						"node": besieged})

	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))

	var rect := screen_rect()
	var count := mini(found.size(), MAX_MARKERS)
	for index: int in count:
		var entry := found[index]
		var marker := HUDProjection.marker_for(active, entry["point"] as Vector3, rect,
				MARGIN)
		marker["kind"] = entry["kind"]
		result.append(marker)
	return result


## Un objetivo sólo se marca si tiene sentido marcarlo: una pila desactivada está
## escondida bajo el suelo y un enemigo derrotado ya no es un objetivo.
func _is_active(node: Node3D) -> bool:
	var pickup := node as BatteryPickup
	if pickup != null:
		return pickup.is_active()
	var enemy := node as EnemyBase
	if enemy != null:
		return not enemy.is_defeated()
	return node.visible


## Índices de los marcadores que llevan número, por importancia y después por
## cercanía (la lista ya viene ordenada por distancia).
func _label_slots() -> Array[int]:
	var chosen: Array[int] = []
	var pickups: Array[int] = []
	for slot: int in _markers.size():
		if int(_markers[slot]["kind"]) == int(Kind.PICKUP):
			pickups.append(slot)
		elif chosen.size() < LABELLED_MARKERS:
			chosen.append(slot)
	for slot: int in pickups:
		if chosen.size() >= LABELLED_MARKERS:
			break
		chosen.append(slot)
	chosen.sort()
	return chosen


## Sube [param anchor] hasta que no choque con ninguno de [param taken].
##
## Como mucho [constant LABELLED_MARKERS] rótulos y otros tantos intentos: no hay
## forma de que el bucle se vaya de las manos.
func _stagger(anchor: Vector2, taken: Array[Vector2]) -> Vector2:
	var result := anchor
	for _attempt: int in LABELLED_MARKERS:
		var clashes := false
		for used: Vector2 in taken:
			if absf(used.x - result.x) < LABEL_CLEARANCE.x 					and absf(used.y - result.y) < LABEL_CLEARANCE.y:
				clashes = true
				break
		if not clashes:
			return result
		result.y -= LABEL_STAGGER
	return result


func _colour(kind: int) -> Color:
	match kind:
		Kind.PICKUP:
			return CombatHUDPalette.SUCCESS
		Kind.SIEGE:
			return CombatHUDPalette.ACCENT
		_:
			return CombatHUDPalette.DANGER


func _draw_arrow(at: Vector2, angle: float, colour: Color) -> void:
	var direction := Vector2.from_angle(angle)
	var side := Vector2(-direction.y, direction.x)
	var tip := at + direction * ARROW_SIZE * 0.6
	var base := at - direction * ARROW_SIZE * 0.5
	var points := PackedVector2Array([tip, base + side * ARROW_SIZE * 0.5,
			base - side * ARROW_SIZE * 0.5])
	draw_colored_polygon(PackedVector2Array([points[0] + direction * 2.0,
			points[1] + side * 2.0, points[2] - side * 2.0]), CombatHUDPalette.SHADOW)
	draw_colored_polygon(points, colour)


func _draw_diamond(at: Vector2, colour: Color) -> void:
	var half := ARROW_SIZE * 0.5
	var points := PackedVector2Array([at + Vector2(0.0, -half), at + Vector2(half, 0.0),
			at + Vector2(0.0, half), at + Vector2(-half, 0.0), at + Vector2(0.0, -half)])
	draw_polyline(points, CombatHUDPalette.SHADOW, 4.0, true)
	draw_polyline(points, colour, 2.0, true)


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		return camera
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null
