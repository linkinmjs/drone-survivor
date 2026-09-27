## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de la galería de inventario de assets (plan P2e, WP-G).
##
## Carga `tools/asset_gallery.tscn` —la escena que hornea
## `tools/build_asset_gallery.gd`— y la mide contra las fuentes de verdad de
## cada familia, recalculadas con `tools/asset_gallery_sources.gd`: lo que la
## galería *debería* tener sale del mismo cálculo que usó el horneador, así que
## una galería vieja —una pieza nueva en un manifiesto, un `.res` que se fue—
## se pone en rojo hasta que alguien la vuelva a hornear.
##
## | # | Fila | Umbral |
## |---|------|--------|
## | 1 | La escena carga | `ResourceLoader.load` + `instantiate`; ≤ 500 KB |
## | 2 | Nada del juego corre al abrirla | ningún nodo con script, ningún `Script` entre sus recursos externos |
## | 3 | Slots = fuentes | el conjunto de `slot_*` es la unión de las fuentes; lista faltantes y sobrantes |
## | 4 | Cada slot en su fila | el padre del slot es la fila de su familia |
## | 5 | Cada instancia apunta a lo declarado | escena (`scene_file_path`) o `.res` (malla, `MultiMesh`, forma) |
## | 6 | Etiquetas | el texto de cada etiqueta es el que dicta su fuente |
## | 7 | Sin solapes en fila | cajas de la geometría real en X, por fila, sin cruzarse |
## | 8 | Horneados aparte | las filas horneadas empiezan a −400 m o más allá |
##
## **Prueba negativa** (`-- --negative`): borra un slot en memoria y cambia una
## etiqueta, y exige que las filas 3 y 6 se pongan en rojo. Un check que no sabe
## fallar no está midiendo nada.
##
## **Capturas** (`-- --shots`, con ventana): una o más por familia desde una
## cámara de fila (la regla de `town_showcase.gd::_shoot_row()`), con las otras
## filas ocultas, en `tools/out/shots/asset_gallery/`. Las filas largas se parten
## en tramos de pocas piezas para que las etiquetas se lean.
##
## Uso:
## [codeblock]
## godot --headless --path godot res://tools/asset_gallery_check.tscn
## godot --headless --path godot res://tools/asset_gallery_check.tscn -- --negative
## godot --path godot --windowed --resolution 1920x1080 \
##     res://tools/asset_gallery_check.tscn -- --shots --timeout=400
## [/codeblock]
extends CheckRunner

const Sources := preload("res://tools/asset_gallery_sources.gd")

const GALLERY_PATH: String = "res://tools/asset_gallery.tscn"
## Directorio de capturas cuando se pide `--shots` sin valor. El runner le
## suma el nombre del check (`asset_gallery`): quedan en
## `tools/out/shots/asset_gallery/`.
const SHOTS_ROOT: String = "res://tools/out/shots"
const TSCN_BUDGET_KB: float = 500.0
const BAKED_FRONT_Z: float = -400.0

## Tolerancia de contacto entre dos cajas vecinas, en metros.
const TOUCH: float = 0.001

## Piezas por captura como máximo; en las filas horneadas, que miden cientos de
## metros, dos, para que se vean desde arriba y no como una raya.
const SHOT_MAX_ITEMS: int = 8
const SHOT_MAX_BAKED: int = 2

## Avance de un carácter de la fuente mono, en em, y aire entre dos etiquetas
## del mismo piso, en píxeles de pantalla.
const MONO_ADVANCE: float = 0.6
const LABEL_AIR_PX: float = 24.0

## Fotogramas para que compilen los shaders antes de la primera captura, y entre
## capturas.
const WARMUP_FRAMES: int = 90
const SETTLE_FRAMES: int = 12

var _negative: bool = false
var _fired: Dictionary[String, bool] = {}
var _entries: Array[Dictionary] = []
var _by_id: Dictionary[String, Dictionary] = {}


func _run() -> void:
	_negative = user_args().has("negative")

	var gallery := _load_gallery()
	if gallery == null:
		return
	_entries = Sources.entries()
	for entry: Dictionary in _entries:
		_by_id[String(entry["id"])] = entry

	if _negative:
		_spoil(gallery)

	_check_scripts(gallery)
	var slots := _slots(gallery)
	_check_membership(slots)
	_check_rows(slots)
	_check_targets(slots)
	_check_labels(slots)
	_check_overlaps(gallery)
	_check_baked_zone(gallery)
	_print_counts(slots)

	if _negative:
		_report_negative()
	elif not shots_dir.is_empty() and DisplayServer.get_name() != "headless":
		await _shoot(gallery)
	gallery.queue_free()
	await wait_frames(2)


# --------------------------------------------------------------------------
# Filas
# --------------------------------------------------------------------------

## 1. La escena carga, se instancia y cabe en el tope.
func _load_gallery() -> Node3D:
	if not ResourceLoader.exists(GALLERY_PATH):
		fail("falta '%s'; horneala con tools/build_asset_gallery.gd" % GALLERY_PATH)
		return null
	var packed := ResourceLoader.load(GALLERY_PATH, "PackedScene") as PackedScene
	if packed == null:
		fail("'%s' no carga como PackedScene" % GALLERY_PATH)
		return null
	var gallery := packed.instantiate() as Node3D
	if gallery == null:
		fail("'%s' no se pudo instanciar (o su raíz no es Node3D)" % GALLERY_PATH)
		return null
	var size := float(FileAccess.get_file_as_bytes(GALLERY_PATH).size()) / 1024.0
	print("  carga: %s instanciada, %.1f KB (tope %.0f)" % [GALLERY_PATH, size, TSCN_BUDGET_KB])
	_row("carga", PackedStringArray() if size <= TSCN_BUDGET_KB
			else PackedStringArray(["pesa %.1f KB" % size]))
	return gallery


## 2. Nada del juego corre al abrir la galería: ningún nodo con script (la raíz
## tampoco, así que no pide autoloads) y ningún `Script` entre los recursos que
## la escena nombra.
func _check_scripts(gallery: Node) -> void:
	var problems := PackedStringArray()
	var nodes := Sources.walk(gallery)
	for node: Node in nodes:
		if node.get_script() != null:
			var _added := problems.append("'%s' lleva script %s"
					% [gallery.get_path_to(node), (node.get_script() as Script).resource_path])
	var text := FileAccess.get_file_as_string(GALLERY_PATH)
	if text.contains('type="Script"'):
		var _added := problems.append("la escena nombra un Script como recurso externo")
	print("  sin scripts: %d nodos revisados, %d con script" % [nodes.size(), problems.size()])
	_row("sin scripts", problems)


## 3. El conjunto de slots es la unión de las fuentes.
func _check_membership(slots: Dictionary[String, Node3D]) -> void:
	var missing := PackedStringArray()
	var extra := PackedStringArray()
	for id: String in _by_id:
		if not slots.has(id):
			var _added := missing.append(id)
	for id: String in slots:
		if not _by_id.has(id):
			var _added := extra.append(id)
	print("  slots: %d en la galería, %d en las fuentes · faltan %d %s · sobran %d %s"
			% [slots.size(), _by_id.size(), missing.size(), str(missing), extra.size(), str(extra)])
	var problems := PackedStringArray()
	for id: String in missing:
		var _added := problems.append("falta el slot '%s'" % id)
	for id: String in extra:
		var _added := problems.append("sobra el slot '%s'" % id)
	_row("slots = fuentes", problems)


## 4. Cada slot cuelga de la fila de su familia.
func _check_rows(slots: Dictionary[String, Node3D]) -> void:
	var problems := PackedStringArray()
	for id: String in slots:
		if not _by_id.has(id):
			continue
		var wanted := Sources.row_node(String(_by_id[id]["row"]))
		var parent := slots[id].get_parent()
		if parent == null or String(parent.name) != wanted:
			var _added := problems.append("'%s' está en '%s' y no en '%s'"
					% [id, String(parent.name) if parent != null else "-", wanted])
	print("  filas: %d slots revisados, %d fuera de su fila" % [slots.size(), problems.size()])
	_row("cada slot en su fila", problems)


## 5. Cada instancia apunta a la escena o al `.res` que su fuente declara.
func _check_targets(slots: Dictionary[String, Node3D]) -> void:
	var problems := PackedStringArray()
	var kinds: Dictionary[String, int] = {}
	for id: String in slots:
		if not _by_id.has(id):
			continue
		var entry := _by_id[id]
		var path := String(entry["path"])
		var kind := String(entry["kind"])
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var slot := slots[id]
		if String(slot.get_meta(&"source_path", "")) != path:
			var _added := problems.append("'%s': metadato source_path '%s', esperado '%s'"
					% [id, String(slot.get_meta(&"source_path", "")), path])
		var body := slot.get_node_or_null(NodePath(id))
		if body == null:
			var _added := problems.append("'%s': el slot no tiene la instancia '%s'" % [id, id])
			continue
		var found := _target_of(body, kind)
		if kind != "data" and found != path:
			var _added := problems.append("'%s' apunta a '%s' y no a '%s'" % [id, found, path])
	print("  instancias: %s" % str(kinds))
	_row("cada instancia apunta a lo declarado", problems)


## 6. El texto de cada etiqueta es el que dicta su fuente.
func _check_labels(slots: Dictionary[String, Node3D]) -> void:
	var problems := PackedStringArray()
	var checked := 0
	for id: String in slots:
		if not _by_id.has(id):
			continue
		var label := slots[id].get_node_or_null(^"Label") as Label3D
		if label == null:
			var _added := problems.append("'%s' no tiene etiqueta" % id)
			continue
		checked += 1
		var wanted := Sources.label_text(_by_id[id])
		if label.text != wanted:
			var _added := problems.append("'%s': «%s» y la fuente dice «%s»"
					% [id, label.text.replace("\n", " | "), wanted.replace("\n", " | ")])
	print("  etiquetas: %d revisadas, %d distintas de su fuente" % [checked, problems.size()])
	_row("etiquetas", problems)


## 7. Ninguna instancia se cruza con otra de su fila. La caja de cada una sale
## de su geometría real —mallas, `MultiMesh` leídos del `buffer`, decals, la
## forma de altura—, no del manifiesto.
func _check_overlaps(gallery: Node) -> void:
	var problems := PackedStringArray()
	var rows := gallery.get_node_or_null(^"Rows")
	var pairs := 0
	if rows == null:
		_row("sin solapes en fila", PackedStringArray(["no hay nodo Rows"]))
		return
	for row: Node in rows.get_children():
		var spans := _row_spans(row as Node3D)
		for index: int in range(1, spans.size()):
			pairs += 1
			var before: Dictionary = spans[index - 1]
			var after: Dictionary = spans[index]
			if float(after["min"]) < float(before["max"]) - TOUCH:
				var _added := problems.append("%s: '%s' [%.2f, %.2f] se cruza con '%s' [%.2f, %.2f]"
						% [String(row.name), String(before["name"]), float(before["min"]),
						float(before["max"]), String(after["name"]), float(after["min"]),
						float(after["max"])])
	print("  solapes: %d pares vecinos revisados en %d filas, %d cruces"
			% [pairs, rows.get_child_count(), problems.size()])
	_row("sin solapes en fila", problems)


## 8. Las mallas horneadas van aparte, desde −400 m.
func _check_baked_zone(gallery: Node) -> void:
	var problems := PackedStringArray()
	for row: Dictionary in Sources.ROWS:
		if String(row["zone"]) != "baked":
			continue
		var node := gallery.get_node_or_null(NodePath("Rows/%s" % String(row["node"]))) as Node3D
		if node == null:
			var _added := problems.append("falta la fila '%s'" % String(row["node"]))
			continue
		var spans := _row_spans(node)
		var front := -INF
		for span: Dictionary in spans:
			front = maxf(front, float(span["front"]))
		print("  %s: centro z = %.0f m, borde delantero z = %.0f m"
				% [String(row["name"]), node.position.z, front])
		if front > BAKED_FRONT_Z + TOUCH:
			var _added := problems.append("'%s' llega a z = %.1f" % [String(row["name"]), front])
	_row("horneados aparte", problems)


# --------------------------------------------------------------------------
# Negativa
# --------------------------------------------------------------------------

## Borra un slot y cambia una etiqueta, en memoria.
func _spoil(gallery: Node) -> void:
	var slots := _slots(gallery)
	var removed := "barrel_a"
	var relabelled := "house_a"
	if slots.has(removed):
		var slot := slots[removed]
		slot.get_parent().remove_child(slot)
		slot.free()
	if slots.has(relabelled):
		var label := slots[relabelled].get_node_or_null(^"Label") as Label3D
		if label != null:
			label.text = label.text.replace("5×5×3 m", "5×5×4 m")
	print("  NEGATIVA: slot '%s' borrado y etiqueta de '%s' cambiada en memoria"
			% [removed, relabelled])


func _report_negative() -> void:
	var expected := PackedStringArray(["slots = fuentes", "etiquetas"])
	var fired := 0
	for label: String in expected:
		if bool(_fired.get(label, false)):
			fired += 1
		expect(bool(_fired.get(label, false)), "la fila «%s» no vio el defecto que le tocaba" % label)
	print("  NEGATIVA: %d de %d filas apuntadas se pusieron en rojo" % [fired, expected.size()])


# --------------------------------------------------------------------------
# Capturas
# --------------------------------------------------------------------------

## Una o más capturas por fila, con las demás filas ocultas.
func _shoot(gallery: Node3D) -> void:
	add_child(gallery)
	var camera := gallery.get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		fail("la galería no trae Camera3D")
		return
	camera.make_current()
	var rows := gallery.get_node(^"Rows")
	# El título general queda cerca de la primera fila y taparía sus etiquetas.
	var title := gallery.get_node_or_null(^"Title") as Node3D
	if title != null:
		title.visible = false
	await wait_frames(WARMUP_FRAMES)
	for row: Node in rows.get_children():
		for other: Node in rows.get_children():
			(other as Node3D).visible = other == row
		if String(row.name) == "Horneados_Terreno":
			_show_collision(row)
		var most := SHOT_MAX_BAKED if String(row.name).begins_with("Horneados") 				else SHOT_MAX_ITEMS
		var segments := _segments(_row_spans(row as Node3D), camera, most, (row as Node3D).position.z)
		var z := (row as Node3D).position.z
		for index: int in segments.size():
			var segment: Array = segments[index]
			var low := INF
			var high := -INF
			var tall := 1.0
			var front := 0.0
			var names := PackedStringArray()
			for span: Dictionary in segment:
				low = minf(low, float(span["min"]))
				high = maxf(high, float(span["max"]))
				tall = maxf(tall, float(span["height"]))
				front = maxf(front, float(span["front"]) - z)
				var _added := names.append(String(span["name"]))
			camera.global_transform = Sources.frame(low, high, tall, z, camera.fov, front)
			await wait_frames(SETTLE_FRAMES)
			var name := "%s_%d" % [String(row.name), index + 1]
			print("  captura %s: %s" % [name, ", ".join(names)])
			await shot(name)
	remove_child(gallery)


## La forma de colisión del relieve sólo se dibuja con el indicador de
## depuración de colisiones encendido: se enciende y se vuelve a meter el cuerpo
## al árbol para que arme su malla de depuración.
func _show_collision(row: Node) -> void:
	get_tree().debug_collisions_hint = true
	for node: Node in Sources.walk(row):
		var body := node as StaticBody3D
		if body == null:
			continue
		var parent := body.get_parent()
		parent.remove_child(body)
		parent.add_child(body)


## Parte una fila en tramos que se puedan leer en una captura: se suman piezas
## mientras, con la cámara que encuadraría el tramo, dos etiquetas vecinas del
## mismo piso no se pisen en pantalla.
func _segments(spans: Array[Dictionary], camera: Camera3D, most: int, z: float) -> Array[Array]:
	var found: Array[Array] = []
	var current: Array[Dictionary] = []
	for span: Dictionary in spans:
		var trial: Array[Dictionary] = current.duplicate()
		trial.append(span)
		if not current.is_empty() and (trial.size() > most
				or not _legible(trial, camera, z)):
			found.append(current)
			trial = [span]
		current = trial
	if not current.is_empty():
		found.append(current)
	return found


## `true` si en el encuadre del tramo [param spans] ninguna etiqueta se pisa con
## la siguiente de su mismo piso.
##
## La escala en pantalla se mide con la cámara que de verdad va a sacar la
## captura (`Sources.frame()`, fila en [param z]): ésa se aleja además lo que
## sobresale el tramo hacia ella y se levanta, sobre todo en los tramos chatos.
## Medida con la distancia horizontal a secas (antes de WP-G2), la escala salía
## hasta 1,5 veces más grande que la real y las etiquetas de las piezas chicas
## junto a una grande (un cartel al lado de una baldosa de 4 m) se pisaban.
func _legible(spans: Array[Dictionary], camera: Camera3D, z: float) -> bool:
	var low := INF
	var high := -INF
	var tall := 1.0
	var front := 0.0
	for span: Dictionary in spans:
		low = minf(low, float(span["min"]))
		high = maxf(high, float(span["max"]))
		tall = maxf(tall, float(span["height"]))
		front = maxf(front, float(span["front"]) - z)
	var size := get_viewport().get_visible_rect().size
	var half_fov := tan(deg_to_rad(camera.fov) * 0.5)
	var view := Sources.frame(low, high, tall, z, camera.fov, front)
	var target := Vector3((low + high) * 0.5, tall * 0.45, z)
	var depth := (target - view.origin).dot(-view.basis.z)
	var pixels_per_metre := size.y / (2.0 * maxf(depth, 0.01) * half_fov)
	for index: int in spans.size():
		var here: Dictionary = spans[index]
		for other_index: int in range(index + 1, spans.size()):
			var there: Dictionary = spans[other_index]
			if int(there["tier"]) != int(here["tier"]):
				continue
			var gap := (float(there["centre"]) - float(here["centre"])) * pixels_per_metre
			var wanted := (_label_px(here, size.y, half_fov)
					+ _label_px(there, size.y, half_fov)) * 0.5 + LABEL_AIR_PX
			if gap < wanted:
				return false
			break
	return true


## Ancho en pantalla de la etiqueta de [param span]: con `fixed_size`, un em
## mide `font_size · pixel_size` veces el alto de la pantalla sobre
## `2 · tan(fov / 2)`.
func _label_px(span: Dictionary, screen_height: float, half_fov: float) -> float:
	var em := float(span["font_size"]) * float(span["pixel_size"]) * screen_height 			/ (2.0 * half_fov)
	return float(span["chars"]) * MONO_ADVANCE * em


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## `--shots` a secas llega como `"true"`: se lo lleva a [constant SHOTS_ROOT]
## en vez de crear una carpeta `res://true/`.
func _resolve_dir(path: String) -> String:
	if path == "true":
		return SHOTS_ROOT
	return super(path)


## Los `slot_*` de la galería, por id.
func _slots(gallery: Node) -> Dictionary[String, Node3D]:
	var found: Dictionary[String, Node3D] = {}
	for node: Node in Sources.walk(gallery):
		var name := String(node.name)
		if name.begins_with("slot_"):
			found[name.trim_prefix("slot_")] = node as Node3D
	return found


## Tramos en X que ocupa cada elemento de la fila (slots, poste de escala y
## casa de referencia), ordenados, con su alto y su borde delantero en Z.
func _row_spans(row: Node3D) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	for child: Node in row.get_children():
		var item := child as Node3D
		if item == null or item is Label3D:
			continue
		var measured := Sources.measure(item)
		var local: AABB = measured["aabb"]
		if local.size == Vector3.ZERO and local.position == Vector3.ZERO:
			continue
		var box := item.transform * local
		var label := item.get_node_or_null(^"Label") as Label3D
		var chars := 0
		# El encuadre tiene que dejar ver también la etiqueta, que puede ir más
		# alta que la pieza (se empareja con la de sus vecinos).
		var top := box.end.y
		if label != null:
			top = maxf(top, label.position.y + 0.5)
			for line: String in label.text.split("
"):
				chars = maxi(chars, line.length())
		spans.append({"name": String(item.name), "min": box.position.x, "max": box.end.x,
				"centre": item.position.x, "height": top,
				"front": row.position.z + box.end.z, "chars": chars,
				"tier": 1 if label != null and label.offset.y != 0.0 else 0,
				"font_size": label.font_size if label != null else 0,
				"pixel_size": label.pixel_size if label != null else 0.0})
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["min"]) < float(b["min"]))
	return spans


## Ruta del recurso al que apunta la instancia de un slot.
func _target_of(body: Node, kind: String) -> String:
	match kind:
		"scene":
			return body.scene_file_path
		"mesh":
			var mesh := body as MeshInstance3D
			return mesh.mesh.resource_path if mesh != null and mesh.mesh != null else ""
		"multimesh":
			var multi := body as MultiMeshInstance3D
			return multi.multimesh.resource_path if multi != null and multi.multimesh != null \
					else ""
		"shape":
			var shape := body.get_node_or_null(^"Shape") as CollisionShape3D
			return shape.shape.resource_path if shape != null and shape.shape != null else ""
	return ""


## Cuántos slots hay por fila.
func _print_counts(slots: Dictionary[String, Node3D]) -> void:
	var per_row: Dictionary[String, int] = {}
	for id: String in slots:
		var row := String(slots[id].get_parent().name)
		per_row[row] = int(per_row.get(row, 0)) + 1
	var parts := PackedStringArray()
	for row: Dictionary in Sources.ROWS:
		var _added := parts.append("%s %d" % [String(row["node"]),
				int(per_row.get(String(row["node"]), 0))])
	print("  por fila: %s · total %d" % [", ".join(parts), slots.size()])


## Registra una fila. En modo normal exige que no tenga problemas; en la prueba
## negativa sólo anota si se puso en rojo.
func _row(label: String, problems: PackedStringArray) -> void:
	_fired[label] = not problems.is_empty()
	if _negative:
		for problem: String in problems:
			print("    (negativa) %s: %s" % [label, problem])
		return
	for problem: String in problems:
		fail("%s: %s" % [label, problem])
