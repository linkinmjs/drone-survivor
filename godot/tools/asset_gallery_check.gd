## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de la galería de inventario de assets (planes P2e y P2f).
##
## Carga `tools/asset_gallery.tscn` —la escena que hornea
## `tools/build_asset_gallery.gd`— y la mide contra las fuentes de verdad de
## cada familia, recalculadas con [AssetGallerySources]: lo que la galería
## *debería* tener sale del mismo cálculo que usó el horneador, así que una
## galería vieja —una pieza nueva en un manifiesto, una regla de escala
## cambiada— se pone en rojo hasta que alguien la vuelva a hornear. Lo mismo con
## `assets/INVENTARIO.md`.
##
## | # | Fila | Umbral |
## |---|------|--------|
## | 1 | La escena carga | `ResourceLoader.load` + `instantiate`; ≤ 500 KB |
## | 2 | Nada del juego corre al abrirla | ningún nodo con script, ningún `Script` entre sus recursos externos |
## | 3 | Slots = fuentes | el conjunto de `slot_*` es la unión de las fuentes; lista faltantes y sobrantes |
## | 4 | Cada slot en su fila | el padre del slot es la fila de su familia |
## | 5 | Cada instancia apunta a lo declarado | `scene_file_path` de la instancia = escena o GLB de la fuente |
## | 6 | Etiquetas | el texto de cada etiqueta es el que dicta su fuente |
## | 7 | Sin solapes en fila | cajas de la geometría real en X, por fila, sin cruzarse |
## | 8 | Dron de referencia en cada fila | el primer elemento de cada fila es el poste `Escala` con `ref_drone_quad` (el GLB del dron) apoyado a 2 m ± 1 cm y de frente (+Z) |
## | 9 | Procedencia conocida | ninguna entrada con procedencia `?`; cada etiqueta empieza con su `PROPIO`/`DESCARGADO (pack)` y lleva su tinta |
## | 10 | Marcas de escala = reglas | la tercera línea de cada etiqueta (`MEDIDA≠`, `ESCALA?`) es exactamente la que recalculan las fuentes |
## | 11 | INVENTARIO.md al día | el texto regenerado en memoria es byte a byte el de `assets/INVENTARIO.md` |
##
## **Prueba negativa** (`-- --negative`): en memoria, borra un slot, cambia una
## medida de una etiqueta, le quita la marca de escala a otra y le cambia la
## procedencia a una tercera, y exige que las filas 3, 6, 9 y 10 se pongan en
## rojo. Además (P2f) le devuelve a `block_low_a` el `root_scale` de WP-13 (5.0)
## y exige que la fila 10 lo marque por la **puerta**: la regla de rasgos
## humanos tiene que ver sola una casa con una puerta de 10 m. Un check que no
## sabe fallar no está midiendo nada.
##
## **Capturas** (`-- --shots`, con ventana): una o más por familia desde una
## cámara de fila (la regla de `town_showcase.gd::_shoot_row()`), con las otras
## filas y el resto de la fila ocultos, en `tools/out/shots/asset_gallery/`. Las
## filas largas se parten en tramos de pocas piezas para que las etiquetas se
## lean.
##
## Uso:
## [codeblock]
## godot --headless --path godot res://tools/asset_gallery_check.tscn
## godot --headless --path godot res://tools/asset_gallery_check.tscn -- --negative
## godot --path godot --windowed --resolution 1920x1080 \
##     res://tools/asset_gallery_check.tscn -- --shots --timeout=400
## [/codeblock]
extends CheckRunner

const GALLERY_PATH: String = "res://tools/asset_gallery.tscn"
## Directorio de capturas cuando se pide `--shots` sin valor. El runner le
## suma el nombre del check (`asset_gallery`): quedan en
## `tools/out/shots/asset_gallery/`.
const SHOTS_ROOT: String = "res://tools/out/shots"
const TSCN_BUDGET_KB: float = 500.0

## Nombre del poste de escala y del dron de referencia que lleva encima, y
## altura del poste (la del horneador).
const SCALE_POST: String = "Escala"
const REFERENCE_DRONE: String = "ref_drone_quad"
const SCALE_HEIGHT: float = 2.0
## Cuánto puede separarse la base del dron de la punta del poste, en metros.
const PERCH_TOLERANCE: float = 0.01

## Tolerancia de contacto entre dos cajas vecinas, en metros.
const TOUCH: float = 0.001

## Piezas por captura como máximo.
const SHOT_MAX_ITEMS: int = 8

## Avance de un carácter de la fuente mono, en em, y aire entre dos etiquetas
## del mismo piso, en píxeles de pantalla.
const MONO_ADVANCE: float = 0.6
const LABEL_AIR_PX: float = 24.0

## Fotogramas para que compilen los shaders antes de la primera captura, y entre
## capturas.
const WARMUP_FRAMES: int = 90
const SETTLE_FRAMES: int = 12

## Pieza y factor de la negativa de rasgos humanos: el `root_scale` que
## `block_low_a` tuvo desde WP-13 hasta P2f.
const SPOILED_FEATURE_ID: String = "block_low_a"
const SPOILED_ROOT_SCALE: float = 5.0

var _negative: bool = false
var _fired: Dictionary[String, bool] = {}
var _problems: Dictionary[String, PackedStringArray] = {}
var _entries: Array[Dictionary] = []
var _by_id: Dictionary[String, Dictionary] = {}


func _run() -> void:
	_negative = user_args().has("negative")

	var gallery := _load_gallery()
	if gallery == null:
		return
	_entries = AssetGallerySources.entries()
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
	_check_reference_drones(gallery)
	_check_provenance(slots)
	_check_marks(slots)
	_check_inventory()
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
	var nodes := AssetGallerySources.walk(gallery)
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
		var wanted := AssetGallerySources.row_node(String(_by_id[id]["row"]))
		var parent := slots[id].get_parent()
		if parent == null or String(parent.name) != wanted:
			var _added := problems.append("'%s' está en '%s' y no en '%s'"
					% [id, String(parent.name) if parent != null else "-", wanted])
	print("  filas: %d slots revisados, %d fuera de su fila" % [slots.size(), problems.size()])
	_row("cada slot en su fila", problems)


## 5. Cada instancia apunta a la escena o al GLB que su fuente declara.
func _check_targets(slots: Dictionary[String, Node3D]) -> void:
	var problems := PackedStringArray()
	for id: String in slots:
		if not _by_id.has(id):
			continue
		var path := String(_by_id[id]["path"])
		var slot := slots[id]
		if String(slot.get_meta(&"source_path", "")) != path:
			var _added := problems.append("'%s': metadato source_path '%s', esperado '%s'"
					% [id, String(slot.get_meta(&"source_path", "")), path])
		var body := slot.get_node_or_null(NodePath(id))
		if body == null:
			var _added := problems.append("'%s': el slot no tiene la instancia '%s'" % [id, id])
			continue
		if body.scene_file_path != path:
			var _added := problems.append("'%s' apunta a '%s' y no a '%s'"
					% [id, body.scene_file_path, path])
	print("  instancias: %d revisadas, %d mal apuntadas" % [slots.size(), problems.size()])
	_row("cada instancia apunta a lo declarado", problems)


## 6. El texto de cada etiqueta es el que dicta su fuente.
func _check_labels(slots: Dictionary[String, Node3D]) -> void:
	var problems := PackedStringArray()
	var checked := 0
	for id: String in slots:
		if not _by_id.has(id):
			continue
		var label := _label_of(slots[id])
		if label == null:
			var _added := problems.append("'%s' no tiene etiqueta" % id)
			continue
		checked += 1
		var wanted := AssetGallerySources.label_text(_by_id[id])
		if label.text != wanted:
			var _added := problems.append("'%s': «%s» y la fuente dice «%s»"
					% [id, label.text.replace("\n", " | "), wanted.replace("\n", " | ")])
	print("  etiquetas: %d revisadas, %d distintas de su fuente" % [checked, problems.size()])
	_row("etiquetas", problems)


## 7. Ninguna instancia se cruza con otra de su fila. La caja de cada una sale
## de su geometría real, no del manifiesto.
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


## 8. Cada fila de [constant AssetGallerySources.ROWS] existe y arranca con el
## poste de escala, que lleva encima el dron de referencia: el GLB del dron,
## con la base de su caja sobre la punta del poste y girado de frente a +Z.
func _check_reference_drones(gallery: Node) -> void:
	var problems := PackedStringArray()
	var perched := 0
	var wanted_basis := Basis(Vector3.UP, AssetGallerySources.DRONE_YAW)
	for row: Dictionary in AssetGallerySources.ROWS:
		var name := String(row["node"])
		var node := gallery.get_node_or_null(NodePath("Rows/%s" % name)) as Node3D
		if node == null:
			var _added := problems.append("falta la fila '%s'" % name)
			continue
		var spans := _row_spans(node)
		if spans.is_empty() or String(spans[0]["name"]) != SCALE_POST:
			var _added := problems.append("'%s' no arranca con el poste '%s' (arranca con '%s')"
					% [name, SCALE_POST, String(spans[0]["name"]) if not spans.is_empty() else "-"])
			continue
		var drone := node.get_node_or_null(NodePath("%s/%s" % [SCALE_POST, REFERENCE_DRONE])) \
				as Node3D
		if drone == null:
			var _added := problems.append("'%s': el poste no lleva '%s'" % [name, REFERENCE_DRONE])
			continue
		if drone.scene_file_path != AssetGallerySources.DRONE_GLB:
			var _added := problems.append("'%s': '%s' apunta a '%s' y no a '%s'" % [name,
					REFERENCE_DRONE, drone.scene_file_path, AssetGallerySources.DRONE_GLB])
			continue
		var box := drone.transform * (AssetGallerySources.measure(drone)["aabb"] as AABB)
		if absf(box.position.y - SCALE_HEIGHT) > PERCH_TOLERANCE:
			var _added := problems.append("'%s': la base del dron está a %.3f m y el poste mide %.1f"
					% [name, box.position.y, SCALE_HEIGHT])
			continue
		if not drone.transform.basis.is_equal_approx(wanted_basis):
			var _added := problems.append("'%s': el dron no mira a +Z" % name)
			continue
		perched += 1
	print("  dron de referencia: %d de %d filas con el dron sobre el poste"
			% [perched, AssetGallerySources.ROWS.size()])
	_row("dron de referencia en cada fila", problems)


## 9. Toda entrada tiene procedencia conocida y su etiqueta la dice y la tiñe.
func _check_provenance(slots: Dictionary[String, Node3D]) -> void:
	var problems := PackedStringArray()
	var counts: Dictionary[String, int] = {}
	for entry: Dictionary in _entries:
		var made := String(entry["made"])
		counts[made] = int(counts.get(made, 0)) + 1
		if made == "?":
			var _added := problems.append("'%s': origen '%s' sin procedencia en PROVENANCE"
					% [String(entry["id"]), String(entry["origin"])])
	for id: String in slots:
		if not _by_id.has(id):
			continue
		var label := _label_of(slots[id])
		if label == null:
			continue
		var entry := _by_id[id]
		var token := AssetGallerySources.provenance_token(entry)
		var line := label.text.get_slice("\n", 1)
		if not line.begins_with(token + " · ") or line.begins_with("?"):
			var _added := problems.append("'%s': la etiqueta dice «%s» y la procedencia es «%s»"
					% [id, line.get_slice(" · ", 0), token])
		if not label.modulate.is_equal_approx(AssetGallerySources.tint(entry)):
			var _added := problems.append("'%s': tinta %s y su procedencia pide %s"
					% [id, label.modulate.to_html(false), AssetGallerySources.tint(entry).to_html(false)])
	print("  procedencia: %s" % str(counts))
	_row("procedencia conocida", problems)


## 10. Las marcas de escala de cada etiqueta son exactamente las que recalculan
## las fuentes.
func _check_marks(slots: Dictionary[String, Node3D]) -> void:
	var problems := PackedStringArray()
	var marked := 0
	for id: String in slots:
		if not _by_id.has(id):
			continue
		var label := _label_of(slots[id])
		if label == null:
			continue
		var shown := label.text.get_slice("\n", 2) if label.text.get_slice_count("\n") > 2 else ""
		var wanted := AssetGallerySources.marks_line(_by_id[id])
		if not wanted.is_empty():
			marked += 1
		if shown != wanted:
			var _added := problems.append("'%s': marcas «%s» y las reglas dan «%s»"
					% [id, shown, wanted])
	print("  marcas: %d piezas marcadas según las reglas, %d etiquetas distintas"
			% [marked, problems.size()])
	_row("marcas de escala = reglas", problems)


## 11. `assets/INVENTARIO.md` es byte a byte el que escribiría el horneador hoy.
func _check_inventory() -> void:
	var problems := PackedStringArray()
	var path := AssetGallerySources.INVENTORY_PATH
	var wanted := AssetGallerySources.inventory_text(_entries).to_utf8_buffer()
	if not FileAccess.file_exists(path):
		var _added := problems.append("falta '%s'; horneá la galería" % path)
	else:
		var found := FileAccess.get_file_as_bytes(path)
		if found != wanted:
			var lines := found.get_string_from_utf8().split("\n")
			var fresh := wanted.get_string_from_utf8().split("\n")
			var line := 0
			while line < mini(lines.size(), fresh.size()) and lines[line] == fresh[line]:
				line += 1
			var _added := problems.append("'%s' (%d bytes) no es el regenerado (%d bytes): difiere en la línea %d"
					% [path, found.size(), wanted.size(), line + 1])
	print("  inventario: %s, %d bytes regenerados" % [path, wanted.size()])
	_row("INVENTARIO.md al día", problems)


# --------------------------------------------------------------------------
# Negativa
# --------------------------------------------------------------------------

## En memoria: borra un slot, cambia una medida de una etiqueta, le quita la
## marca de escala a otra y le cambia la procedencia a una tercera.
func _spoil(gallery: Node) -> void:
	var slots := _slots(gallery)
	var removed := "barrel_a"
	var relabelled := "house_a"
	var unmarked := "tree_large"
	var unknown := "bench"
	if slots.has(removed):
		var slot := slots[removed]
		slot.get_parent().remove_child(slot)
		slot.free()
	var label := _label_of(slots.get(relabelled, null))
	if label != null:
		label.text = label.text.replace("5×5×3 m", "5×5×4 m")
	label = _label_of(slots.get(unmarked, null))
	if label != null:
		label.text = label.text.get_slice("\n", 0) + "\n" + label.text.get_slice("\n", 1)
	label = _label_of(slots.get(unknown, null))
	if label != null:
		label.text = label.text.replace("\nPROPIO · ", "\n? · ")
	print("  NEGATIVA: slot '%s' borrado, medida de '%s' cambiada, marca de '%s' quitada y "
			% [removed, relabelled, unmarked]
			+ "procedencia de '%s' borrada, en memoria" % unknown)
	# La fuente, no la etiqueta: el `root_scale` vuelve a 5.0 y las marcas se
	# recalculan como lo haría el horneador con ese preset.
	if _by_id.has(SPOILED_FEATURE_ID):
		var entry := _by_id[SPOILED_FEATURE_ID]
		entry["root_scale"] = SPOILED_ROOT_SCALE
		var marks := AssetGallerySources.measure_marks(entry)
		marks.append_array(AssetGallerySources.scale_marks(entry))
		entry["marks"] = marks
		print("  NEGATIVA: root_scale de '%s' a %.1f en memoria → «%s»" % [SPOILED_FEATURE_ID,
				SPOILED_ROOT_SCALE, AssetGallerySources.marks_line(entry)])


func _report_negative() -> void:
	var expected := PackedStringArray(["slots = fuentes", "etiquetas", "procedencia conocida",
			"marcas de escala = reglas"])
	var fired := 0
	for label: String in expected:
		if bool(_fired.get(label, false)):
			fired += 1
		expect(bool(_fired.get(label, false)), "la fila «%s» no vio el defecto que le tocaba" % label)
	print("  NEGATIVA: %d de %d filas apuntadas se pusieron en rojo" % [fired, expected.size()])
	var feature_seen := false
	var marks: PackedStringArray = _problems.get("marcas de escala = reglas", PackedStringArray())
	for problem: String in marks:
		if problem.begins_with("'%s'" % SPOILED_FEATURE_ID) and problem.contains("puerta"):
			feature_seen = true
	expect(feature_seen, "la fila «marcas de escala = reglas» no marcó la puerta de '%s' con "
			% SPOILED_FEATURE_ID + "root_scale %.1f" % SPOILED_ROOT_SCALE)
	print("  NEGATIVA: puerta de '%s' a root_scale %.1f %s" % [SPOILED_FEATURE_ID,
			SPOILED_ROOT_SCALE, "marcada" if feature_seen else "SIN MARCAR"])


# --------------------------------------------------------------------------
# Capturas
# --------------------------------------------------------------------------

## Una o más capturas por fila, con las demás filas y lo que queda fuera de cada
## tramo ocultos.
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
		var z := (row as Node3D).position.z
		var segments := _segments(_row_spans(row as Node3D), camera, SHOT_MAX_ITEMS, z)
		for index: int in segments.size():
			var segment: Array = segments[index]
			var low := INF
			var high := -INF
			var tall := 1.0
			var front := 0.0
			var names := PackedStringArray()
			# Sólo el tramo a la vista: las etiquetas de las piezas vecinas, fuera
			# del encuadre calculado, se leían encima de las del borde.
			for child: Node in row.get_children():
				if child is Node3D and not child is Label3D:
					(child as Node3D).visible = false
			for span: Dictionary in segment:
				(row.get_node(NodePath(String(span["name"]))) as Node3D).visible = true
				low = minf(low, float(span["min"]))
				high = maxf(high, float(span["max"]))
				tall = maxf(tall, float(span["height"]))
				front = maxf(front, float(span["front"]) - z)
				var _added := names.append(String(span["name"]))
			camera.global_transform = AssetGallerySources.frame(low, high, tall, z, camera.fov,
					front)
			await wait_frames(SETTLE_FRAMES)
			var name := "%s_%d" % [String(row.name), index + 1]
			print("  captura %s: %s" % [name, ", ".join(names)])
			await shot(name)
	remove_child(gallery)


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
## captura ([method AssetGallerySources.frame], fila en [param z]): ésa se aleja
## además lo que sobresale el tramo hacia ella y se levanta, sobre todo en los
## tramos chatos. Medida con la distancia horizontal a secas (antes de WP-G2),
## la escala salía hasta 1,5 veces más grande que la real y las etiquetas de las
## piezas chicas junto a una grande (un cartel al lado de una baldosa de 4 m) se
## pisaban.
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
	var view := AssetGallerySources.frame(low, high, tall, z, camera.fov, front)
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
	var em := float(span["font_size"]) * float(span["pixel_size"]) * screen_height \
			/ (2.0 * half_fov)
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
	for node: Node in AssetGallerySources.walk(gallery):
		var name := String(node.name)
		if name.begins_with("slot_"):
			found[name.trim_prefix("slot_")] = node as Node3D
	return found


## La etiqueta `Label` de [param item], o `null`.
func _label_of(item: Node) -> Label3D:
	if item == null:
		return null
	return item.get_node_or_null(^"Label") as Label3D


## Tramos en X que ocupa cada elemento de la fila (slots y poste de escala con
## su dron), ordenados, con su alto y su borde delantero en Z.
func _row_spans(row: Node3D) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	for child: Node in row.get_children():
		var item := child as Node3D
		if item == null or item is Label3D:
			continue
		var measured := AssetGallerySources.measure(item)
		var local: AABB = measured["aabb"]
		if local.size == Vector3.ZERO and local.position == Vector3.ZERO:
			continue
		var box := item.transform * local
		var label := _label_of(item)
		var chars := 0
		# El encuadre tiene que dejar ver también la etiqueta, que puede ir más
		# alta que la pieza (se empareja con la de sus vecinos).
		var top := box.end.y
		if label != null:
			top = maxf(top, label.position.y + 0.5)
			for line: String in label.text.split("\n"):
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


## Cuántos slots hay por fila.
func _print_counts(slots: Dictionary[String, Node3D]) -> void:
	var per_row: Dictionary[String, int] = {}
	for id: String in slots:
		var row := String(slots[id].get_parent().name)
		per_row[row] = int(per_row.get(row, 0)) + 1
	var parts := PackedStringArray()
	for row: Dictionary in AssetGallerySources.ROWS:
		var _added := parts.append("%s %d" % [String(row["node"]),
				int(per_row.get(String(row["node"]), 0))])
	print("  por fila: %s · total %d" % [", ".join(parts), slots.size()])


## Registra una fila. En modo normal exige que no tenga problemas; en la prueba
## negativa sólo anota si se puso en rojo.
func _row(label: String, problems: PackedStringArray) -> void:
	_fired[label] = not problems.is_empty()
	_problems[label] = problems
	if _negative:
		for problem: String in problems:
			print("    (negativa) %s: %s" % [label, problem])
		return
	for problem: String in problems:
		fail("%s: %s" % [label, problem])
