## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Utilidades compartidas de los horneadores de escenas de `tools/`.
##
## Hoy tiene una sola: [method stabilise_ids], que salió de `tools/build_town.gd`
## (WP-D4a, hallazgo 4) para que la usen también `tools/build_asset_gallery.gd`
## y cualquier otro generador que guarde un `.tscn` que se comitea.
##
## ## Por qué no nombra a [TownPlan]
##
## Los horneadores corren con `-s`, y Godot compila el script del bucle
## principal **antes** de dar de alta los autoload. [TownPlan] lee
## `Global.round_seed`: si esta clase lo nombrara, compilarla —y la compila
## cualquiera que escriba `SceneBake.stabilise_ids(...)`— arrastraría a
## [TownPlan] demasiado temprano y el arranque moriría con «Identifier not found:
## Global». El mezclador se pide con `load()` en el momento de usarlo, cuando los
## autoload ya existen.
class_name SceneBake
extends RefCounted

## Script que trae el splitmix64 ([method TownPlan.mix]).
const MIXER_SCRIPT: String = "res://city/town_plan.gd"

## Testigo con el que se renombra en dos pasadas. No puede aparecer en un
## `.tscn`: ver [method stabilise_ids].
const ID_TOKEN: String = "@@wpd4a@@"


## Reescribe los identificadores **aleatorios** que `ResourceSaver` le pone al
## `.tscn` de [param path] por otros derivados del contenido. [param tag] es el
## prefijo de los mensajes (el nombre del horneador que la llama).
##
## ## El problema
##
## Godot sortea tres cosas al guardar una escena de texto: el sufijo de cada
## `id="12_l0lbw"` de `ext_resource`, el de cada `id="BoxShape3D_nclj1"` de
## `sub_resource` y el entero `unique_id=1505653870` de cada nodo. Los tres son
## arbitrarios y distintos en cada corrida, así que dos horneados de la **misma**
## escena daban dos archivos distintos: 4 796 líneas de `diff` de puro ruido
## sobre un pueblo idéntico. Eso rompe lo único que hace editable un diseño
## escrito a mano —que el `diff` del horneado diga qué cambió—.
##
## ## La regla
##
## Cada identificador sale de **lo que nombra**, con el mismo splitmix64 que usa
## todo el determinismo posicional del pueblo ([method TownPlan.mix]):
##
## - un `ext_resource` toma su orden de aparición y un token de cinco caracteres
##   derivado de su `path`;
## - un `sub_resource` toma su tipo y un token derivado de `(orden, tipo)`,
##   porque un `BoxShape3D` no tiene ruta con la que distinguirse de otro;
## - un nodo toma su `NodePath` entero —`Buildings/Building_House_07_02`—, que
##   es exactamente lo que `unique_id` identifica.
##
## El renombrado va en dos pasadas con un token intermedio para que un
## identificador nuevo no pueda pisar a uno viejo que todavía no se reemplazó.
##
## Resultado: md5 del `.tscn` igual en dos horneados seguidos.
static func stabilise_ids(path: String, tag: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("%s: no se pudo releer '%s' para estabilizar los ids" % [tag, path])
		return
	var text := file.get_as_text()
	file.close()

	var ext := RegEx.create_from_string(
			r'\[ext_resource [^\]]*path="([^"]+)"[^\]]*id="([^"]+)"')
	var sub := RegEx.create_from_string(r'\[sub_resource type="([^"]+)" id="([^"]+)"')

	var wanted: Array[String] = []
	var renames: Dictionary[String, String] = {}
	var order := 0
	for hit: RegExMatch in ext.search_all(text):
		order += 1
		renames[hit.get_string(2)] = "%d_%s" % [order, id_token(hit.get_string(1))]
		wanted.append(hit.get_string(2))
	order = 0
	for hit: RegExMatch in sub.search_all(text):
		order += 1
		var kind := hit.get_string(1)
		renames[hit.get_string(2)] = "%s_%s" % [kind, id_token("%d|%s" % [order, kind])]
		wanted.append(hit.get_string(2))

	# Pasada 1: al testigo intermedio. Pasada 2: al identificador definitivo. Con
	# una sola pasada, un identificador nuevo podria pisar a uno viejo que
	# todavia no se reemplazo.
	for slot: int in wanted.size():
		text = text.replace('"%s"' % wanted[slot], '"%s%d%s"' % [ID_TOKEN, slot, ID_TOKEN])
	for slot: int in wanted.size():
		text = text.replace('"%s%d%s"' % [ID_TOKEN, slot, ID_TOKEN],
				'"%s"' % renames[wanted[slot]])

	var stamp := RegEx.create_from_string(" unique_id=-?[0-9]+")
	var lines := text.split("\n")
	var taken: Dictionary[int, bool] = {}
	var nodes := 0
	for index: int in lines.size():
		var line := lines[index]
		if not line.begins_with("[node ") or not line.contains(" unique_id="):
			continue
		var node_path := node_path_of(line)
		if node_path.is_empty():
			continue
		nodes += 1
		var key := unique_id_for(node_path, taken, tag)
		taken[key] = true
		lines[index] = stamp.sub(line, " unique_id=%d" % key)
	text = "\n".join(lines)

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("%s: no se pudo reescribir '%s'" % [tag, path])
		return
	out.store_string(text)
	out.close()
	print("  ids estables: %d recursos y %d nodos" % [wanted.size(), nodes])


## Token de cinco caracteres en base 36 derivado de [param key].
static func id_token(key: String) -> String:
	var mixer: Variant = load(MIXER_SCRIPT)
	var value: int = absi(mixer.mix(key.hash()))
	var digits := "0123456789abcdefghijklmnopqrstuvwxyz"
	var token := ""
	for _slot: int in 5:
		token += digits[value % 36]
		value /= 36
	return token


## El `NodePath` que la línea `[node …]` declara, o `""` si no se puede leer.
static func node_path_of(line: String) -> String:
	var name_hit := RegEx.create_from_string(r'name="([^"]+)"').search(line)
	if name_hit == null:
		return ""
	var parent_hit := RegEx.create_from_string(r'parent="([^"]*)"').search(line)
	if parent_hit == null:
		return "."
	var parent := parent_hit.get_string(1)
	if parent == "." or parent.is_empty():
		return name_hit.get_string(1)
	return "%s/%s" % [parent, name_hit.get_string(1)]


## `unique_id` estable de [param node_path], evitando los ya usados.
static func unique_id_for(node_path: String, taken: Dictionary[int, bool], tag: String) -> int:
	var mixer: Variant = load(MIXER_SCRIPT)
	var salt := 0
	while salt < 64:
		var key: int = absi(mixer.mix(("%s#%d" % [node_path, salt]).hash())) % 2147483647
		if key > 0 and not taken.has(key):
			return key
		salt += 1
	push_error("%s: no se pudo asignar un unique_id estable a '%s'" % [tag, node_path])
	return 1
