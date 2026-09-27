## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Hornea `tools/asset_gallery.tscn`, la galería de inventario de assets (planes
## P2e y P2f), y escribe `assets/INVENTARIO.md`. **No es un check** ni forma
## parte del juego: la escena es para abrirla en el editor y recorrer todos los
## objetos que se pueden poner en un nivel, uno al lado del otro, por familia,
## con una etiqueta que dice cómo se llama cada uno, si es propio o descargado,
## qué es, cuánto mide, cuántos triángulos tiene y si su escala es dudosa; el
## inventario es la misma información como tablas, con un diagnóstico de escala
## por pack.
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_asset_gallery.gd
## [/codeblock]
##
## Qué entra, en qué fila, con qué procedencia y con qué marcas lo decide
## [AssetGallerySources] (sin listas a mano: cada familia sale de su propia
## fuente de verdad). Este script sólo reparte, etiqueta y guarda.
##
## ## La escena
##
## - Raíz `Node3D` **sin script**, y ningún nodo con script: al abrirla en el
##   editor no corre nada del juego.
## - Luz de estudio propia (plan P2f), no la del juego: `WorldEnvironment` con
##   `tools/asset_gallery_environment.tres` y
##   `tools/asset_gallery_camera_attributes.tres`, un `Sun` alto y de frente con
##   sombras suaves y un `Fill` sin sombras del lado opuesto (ver
##   [method _add_lights]); un suelo con rejilla de 10 m, una `Camera3D` mirando
##   la primera fila y un título con los conteos por familia.
## - Una fila por familia a lo largo de +X, apiladas hacia −Z. Cada fila arranca
##   con el poste de escala de 2 m (`Escala`, en el borde delantero de la fila
##   para que ninguna pieza honda lo tape) y, posado encima y de frente, el dron
##   de 0,24 m (`ref_drone_quad`): la unidad con la que se leen todas las
##   medidas.
## - Por pieza, un nodo `slot_<id>` con la instancia (que se llama `<id>`, para
##   buscarla con el filtro del árbol) y su etiqueta, teñida según la
##   procedencia.
##
## ## Determinismo
##
## Dos horneados seguidos dan el mismo md5, del `.tscn` y del inventario: los
## identificadores del `.tscn` los reescribe [method SceneBake.stabilise_ids] y
## ninguno de los dos lleva fecha ni hora.
extends SceneTree

const OUT_PATH: String = "res://tools/asset_gallery.tscn"
const GRID_MATERIAL: String = "res://assets/city/materials/gallery_grid.tres"
## Entorno y cámara de la galería (plan P2f). Hasta P2f usaba los del juego
## (`world/environment_battle.tres`, `world/camera_attributes_dusk.tres` y el sol
## de `world/sun_dusk.tres`): atardecer naranja, bajo y de costado, con niebla,
## glow y SDFGI, que dejaba las fachadas a contraluz y el horizonte quemado. Son
## archivos propios de la galería para retocarlos en el editor sin volver a
## hornear: el horneador los crea **sólo si faltan** ([method _ensure_environment])
## y nunca los pisa. Para rehacerlos con los valores de acá, hay que borrarlos.
const ENVIRONMENT: String = "res://tools/asset_gallery_environment.tres"
const CAMERA_ATTRIBUTES: String = "res://tools/asset_gallery_camera_attributes.tres"

## Sol de estudio: alto y de frente. La cámara de cada fila está en +Z mirando a
## −Z, así que el sol viene de atrás y arriba de ella (la luz viaja hacia −Z) y
## las fachadas que miran a +Z quedan iluminadas de frente. 60° de elevación da
## sombras cortas que no tapan la pieza vecina; 30° hacia la izquierda de la
## cámara deja una cara lateral en sombra, que es lo que da volumen.
const SUN_ELEVATION_DEG: float = 60.0
const SUN_AZIMUTH_DEG: float = 30.0
## Casi blanco, apenas cálido: los colores de los atlas se leen como son.
const SUN_COLOR: Color = Color(1.0, 0.97, 0.92)
## Con el cielo a 1 de ambiente, 1,15 separa luz y sombra sin quemar las caras
## claras (las paredes blancas de la aldea).
const SUN_ENERGY: float = 1.15
## Sombra suave: desenfoque 2,5 y 1,5° de disco solar (el sol real mide 0,5°;
## más ancho ablanda el borde sin perder el contacto con el suelo).
const SUN_SHADOW_BLUR: float = 2.5
const SUN_ANGULAR_DISTANCE_DEG: float = 1.5
## Relleno del lado opuesto (a la derecha de la cámara) y más bajo, sin sombras:
## que la cara que el sol no ve no quede negra. Algo frío, para que el volumen se
## lea también por color.
const FILL_ELEVATION_DEG: float = 25.0
const FILL_AZIMUTH_DEG: float = -60.0
const FILL_COLOR: Color = Color(0.9, 0.94, 1.0)
const FILL_ENERGY: float = 0.3

## Nombre del dron de referencia de cada fila, hijo del poste de escala.
const REFERENCE_DRONE: String = "ref_drone_quad"

## Tope del `.tscn`, en kilobytes: las mallas van por referencia, nunca adentro.
const TSCN_BUDGET_KB: float = 500.0

## Cuánto se separan las filas entre sí.
const ROW_GAP_MIN: float = 12.0

## Etiquetas: tamaño en pantalla fijo, fuente mono.
const LABEL_FONT_SIZE: int = 32
const LABEL_PIXEL_SIZE: float = 0.00045

## Desplazamiento vertical, en píxeles de texto, de la etiqueta de las piezas
## impares de cada fila: dos pisos de etiquetas alternados para que las de
## piezas vecinas no se pisen (con tamaño fijo en pantalla, el desplazamiento en
## píxeles también es fijo). Cubre las tres líneas de una etiqueta con marcas.
const LABEL_TIER_OFFSET: float = 160.0
const TITLE_FONT_SIZE: int = 56

## Cuánto sube el título de la fila sobre la etiqueta del poste, en píxeles de
## texto (una línea de 32 más aire).
const TITLE_OFFSET: float = 64.0

## Poste de escala.
const SCALE_HEIGHT: float = 2.0
const SCALE_RADIUS: float = 0.06
## Altura de la etiqueta del poste sobre su punta: el dron mide 8 cm de alto.
const POST_LABEL_LIFT: float = 0.35

var _font: Font = null
var _scale_mesh: Mesh = null
var _entries: Array[Dictionary] = []
var _drone_span: float = 0.0


func _initialize() -> void:
	_font = load("res://gui/theme/theme_builder.gd").font_mono() as Font
	_entries = AssetGallerySources.entries()
	_drone_span = AssetGallerySources.drone_span()
	if not _unique_ids():
		quit(1)
		return

	if not _ensure_environment():
		quit(1)
		return

	var gallery := Node3D.new()
	gallery.name = "AssetGallery"
	_add_environment(gallery)
	var rows := Node3D.new()
	rows.name = "Rows"
	gallery.add_child(rows)
	var bounds := _lay_rows(rows)
	_add_lights(gallery, bounds)
	_add_ground(gallery, bounds)
	_add_camera(gallery, rows)
	_add_title(gallery)

	_own(gallery, gallery)
	var packed := PackedScene.new()
	var err := packed.pack(gallery)
	gallery.free()
	if err != OK:
		push_error("build_asset_gallery: no se pudo empaquetar: %s" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("build_asset_gallery: no se pudo guardar '%s': %s"
				% [OUT_PATH, error_string(err)])
		quit(1)
		return
	SceneBake.stabilise_ids(OUT_PATH, "build_asset_gallery")
	if not _write_inventory():
		quit(1)
		return
	_report()
	var size := float(FileAccess.get_file_as_bytes(OUT_PATH).size()) / 1024.0
	print("build_asset_gallery: %s guardado (%.1f KB de %.0f)." % [OUT_PATH, size, TSCN_BUDGET_KB])
	if size > TSCN_BUDGET_KB:
		push_error("build_asset_gallery: '%s' pesa %.1f KB y el tope es %.0f KB."
				% [OUT_PATH, size, TSCN_BUDGET_KB])
		quit(1)
		return
	quit(0)


# --------------------------------------------------------------------------
# Filas
# --------------------------------------------------------------------------

## Reparte todas las filas y devuelve la caja que ocupan, para el suelo.
func _lay_rows(rows: Node3D) -> AABB:
	var bounds := AABB(Vector3(-20.0, 0.0, -20.0), Vector3(40.0, 1.0, 40.0))
	var front := 0.0
	for row: Dictionary in AssetGallerySources.ROWS:
		var name := String(row["name"])
		var members := _members(name)
		var items := _row_items(row, members)
		var depth := 4.0
		for item: Dictionary in items:
			depth = maxf(depth, (item["box"] as AABB).size.z)
		var centre := front - depth * 0.5
		front = centre - depth * 0.5 - maxf(ROW_GAP_MIN, depth * 0.6)
		var row_node := Node3D.new()
		row_node.name = String(row["node"])
		row_node.position = Vector3(0.0, 0.0, centre)
		row_node.set_meta(&"row", name)
		rows.add_child(row_node)
		var width := _place_row(row_node, name, items, members.size())
		bounds = bounds.merge(AABB(Vector3(-20.0, 0.0, centre - depth * 0.5),
				Vector3(width + 40.0, 1.0, depth)))
	return bounds


## Entradas de la fila [param row_name], en el orden de las fuentes.
func _members(row_name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if String(entry["row"]) == row_name:
			found.append(entry)
	return found


## Qué va en la fila y cuánto ocupa cada cosa: el poste de escala con el dron y
## las piezas.
func _row_items(row: Dictionary, members: Array[Dictionary]) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append({"kind": "scale",
			"box": AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, SCALE_HEIGHT, 0.6))})
	for entry: Dictionary in members:
		items.append({"kind": "slot", "entry": entry, "box": _rotated_box(entry)})
	# Aire proporcional: cada pieza deja un 30 % de su ancho, con un piso que
	# sale de la pieza típica de la fila para que las chicas no queden pegadas.
	var widths: Array[float] = []
	for item: Dictionary in items:
		widths.append((item["box"] as AABB).size.x)
	widths.sort()
	var floor_gap := clampf(widths[widths.size() / 2] * 0.35, 1.5, 20.0)
	# Paso propio de la fila (`gap` en `ROWS`): con piezas de veinte metros el
	# 30 % del ancho deja las etiquetas de dos vecinos pisándose.
	floor_gap = maxf(floor_gap, float(row.get("gap", 0.0)))
	for item: Dictionary in items:
		item["gap"] = maxf(floor_gap, (item["box"] as AABB).size.x * 0.3)
	return items


## Coloca los elementos de una fila a lo largo de +X y devuelve su largo.
func _place_row(row_node: Node3D, row_name: String, items: Array[Dictionary],
		count: int) -> float:
	var reach := _label_reach(items)
	var tops := _label_tops(items)
	# El poste va al borde delantero de la fila: detrás de una pieza honda (el
	# galpón de campo, 10,6 m de fondo) quedaba tapado, dron incluido.
	var front := 0.0
	for item: Dictionary in items:
		front = maxf(front, (item["box"] as AABB).size.z * 0.5)
	var cursor := 0.0
	for index: int in items.size():
		var item: Dictionary = items[index]
		var box: AABB = item["box"]
		var at := Vector3(cursor + box.size.x * 0.5, 0.0, 0.0)
		if String(item["kind"]) == "scale":
			at.z = front
			row_node.add_child(_scale_post(at, reach))
		else:
			var slot := _slot(item["entry"], at, reach, tops[index])
			# El poste es el elemento 0 y va en el piso de abajo: las piezas
			# impares van en el de arriba, alternando con las pares.
			if index % 2 == 1:
				(slot.get_node(^"Label") as Label3D).offset = Vector2(0.0, LABEL_TIER_OFFSET)
			row_node.add_child(slot)
		cursor += box.size.x + float(item["gap"])
	# El título va sobre la etiqueta del poste, separado en píxeles y no en
	# metros: junto a la torre de 81 m, 1,6 m de aire eran dos píxeles y las
	# dos etiquetas se encimaban.
	var title := _label("%s · %d" % [row_name, count], TITLE_FONT_SIZE, reach)
	title.name = "Title"
	title.position = Vector3(0.0, _post_label_height(), front)
	title.offset = Vector2(0.0, TITLE_OFFSET)
	row_node.add_child(title)
	return cursor


## Altura de la etiqueta de cada elemento de la fila. Con dos pisos de
## etiquetas alternados, lo que las hace chocar no es el piso sino la diferencia
## de alturas entre vecinos (un tacho de 20 cm al lado de uno de 75), así que la
## base de cada una es el techo más alto entre la pieza y sus dos vecinas: eso
## deja que los pisos hagan su trabajo sin mandar la etiqueta de una casa a la
## altura del silo del otro extremo de la fila.
##
## Las del piso de arriba (índice impar) suben además a la base de sus vecinas
## de abajo, para no quedar por debajo de ellas (un mecha de 23,5 m al lado de
## uno de 27 las encimaba), salvo que esa base sea más del doble de la propia:
## una etiqueta a 81 m (la torre) no choca con una a 12,5, y subirla la dejaba
## lejísimos de su pieza.
func _label_tops(items: Array[Dictionary]) -> Array[float]:
	var own: Array[float] = []
	for item: Dictionary in items:
		own.append((item["box"] as AABB).size.y)
	var bases: Array[float] = []
	for index: int in own.size():
		var base := own[index]
		if index > 0:
			base = maxf(base, own[index - 1])
		if index < own.size() - 1:
			base = maxf(base, own[index + 1])
		bases.append(base)
	var tops: Array[float] = []
	for index: int in bases.size():
		var top := bases[index]
		if index % 2 == 1:
			for other: int in [index - 1, index + 1]:
				if other >= 0 and other < bases.size() and bases[other] <= bases[index] * 2.0:
					top = maxf(top, bases[other])
		tops.append(top)
	return tops


## Distancia a la que se apagan las etiquetas de la fila: con tamaño fijo en
## pantalla y sin prueba de profundidad, las de las filas de atrás se leerían
## encima de las de adelante. Crece con el tamaño de lo que la fila muestra.
func _label_reach(items: Array[Dictionary]) -> float:
	var biggest := 1.0
	for item: Dictionary in items:
		var size := (item["box"] as AABB).size
		biggest = maxf(biggest, maxf(size.x, maxf(size.y, size.z)))
	return maxf(90.0, biggest * 5.0)


## Un `slot_<id>`: la instancia y su etiqueta, teñida por procedencia.
func _slot(entry: Dictionary, at: Vector3, reach: float, top: float) -> Node3D:
	var slot := Node3D.new()
	slot.name = "slot_%s" % String(entry["id"])
	slot.position = at
	slot.set_meta(&"asset_id", String(entry["id"]))
	slot.set_meta(&"source_path", String(entry["path"]))
	slot.set_meta(&"row", String(entry["row"]))
	var body := _instance_for(entry)
	if body != null:
		slot.add_child(body)
	var label := _label(AssetGallerySources.label_text(entry), LABEL_FONT_SIZE, reach)
	label.name = "Label"
	label.modulate = AssetGallerySources.tint(entry)
	label.position = Vector3(0.0, top + maxf(0.3, top * 0.04), 0.0)
	slot.add_child(label)
	return slot


## La instancia de [param entry], ya girada y apoyada: la caja girada queda
## centrada en el origen del slot en X y Z, con la base en y = 0.
func _instance_for(entry: Dictionary) -> Node3D:
	var node := AssetGallerySources.instance(String(entry["path"]), true)
	if node == null:
		return null
	var basis := Basis(Vector3.UP, float(entry["yaw"]))
	var box := _rotated_box(entry)
	node.name = String(entry["id"])
	node.transform = Transform3D(basis, Vector3(-(box.position.x + box.size.x * 0.5),
			-box.position.y, -(box.position.z + box.size.z * 0.5)))
	return node


## Poste de escala de 2 m con el dron de referencia posado encima, de frente, y
## su etiqueta.
func _scale_post(at: Vector3, reach: float) -> Node3D:
	var post := Node3D.new()
	post.name = "Escala"
	post.position = at
	var mesh := MeshInstance3D.new()
	mesh.name = "Poste"
	mesh.mesh = _scale()
	mesh.position = Vector3(0.0, SCALE_HEIGHT * 0.5, 0.0)
	post.add_child(mesh)
	var drone := AssetGallerySources.instance(AssetGallerySources.DRONE_GLB, true)
	if drone != null:
		var basis := Basis(Vector3.UP, AssetGallerySources.DRONE_YAW)
		var box := Transform3D(basis, Vector3.ZERO) * (AssetGallerySources.measure(drone)["aabb"] as AABB)
		drone.name = REFERENCE_DRONE
		drone.transform = Transform3D(basis, Vector3(-(box.position.x + box.size.x * 0.5),
				SCALE_HEIGHT - box.position.y, -(box.position.z + box.size.z * 0.5)))
		post.add_child(drone)
	var label := _label("%s m · dron %s m" % [AssetGallerySources.num(SCALE_HEIGHT),
			AssetGallerySources.num(_drone_span)], LABEL_FONT_SIZE, reach)
	label.name = "Label"
	label.position = Vector3(0.0, _post_label_height(), 0.0)
	post.add_child(label)
	return post


## Altura de la etiqueta del poste: por encima del dron posado.
func _post_label_height() -> float:
	return SCALE_HEIGHT + POST_LABEL_LIFT


func _label(text: String, font_size: int, reach: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = font_size
	label.outline_size = 14
	label.modulate = Color(0.96, 0.95, 0.9, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.pixel_size = LABEL_PIXEL_SIZE
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = reach
	return label


# --------------------------------------------------------------------------
# Entorno, suelo, cámara y título
# --------------------------------------------------------------------------

func _add_environment(gallery: Node3D) -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = load(ENVIRONMENT) as Environment
	world.camera_attributes = load(CAMERA_ATTRIBUTES) as CameraAttributes
	gallery.add_child(world)


## Crea el entorno y los atributos de cámara de la galería si faltan. Cada valor,
## con su motivo: mirar objetos, no ambientar una batalla.
func _ensure_environment() -> bool:
	if not ResourceLoader.exists(ENVIRONMENT):
		var sky_material := ProceduralSkyMaterial.new()
		# Cielo de estudio: arriba gris azulado suave, horizonte gris claro y sin
		# el resplandor del sol (`sun_angle_max` chico y las luces no se dibujan
		# en el cielo, ver `sky_mode`), para que ninguna etiqueta ni silueta se
		# pierda contra un horizonte blanco.
		sky_material.sky_top_color = Color(0.46, 0.53, 0.62)
		sky_material.sky_horizon_color = Color(0.72, 0.74, 0.76)
		sky_material.ground_horizon_color = Color(0.72, 0.74, 0.76)
		sky_material.ground_bottom_color = Color(0.3, 0.31, 0.33)
		sky_material.sun_angle_max = 1.0
		sky_material.energy_multiplier = 1.0
		var sky := Sky.new()
		sky.sky_material = sky_material
		var environment := Environment.new()
		environment.resource_name = "asset_gallery_environment"
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
		# Energía 1: el cielo se ve como es, sin la intensidad física de 1 100
		# del entorno de batalla (que pide exposición de cámara física).
		environment.background_energy_multiplier = 1.0
		# Ambiente del cielo a 1: rellena todas las caras por igual, que es lo
		# que se quiere para leer la forma y el color de cada pieza.
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = 1.0
		environment.ambient_light_sky_contribution = 1.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		# AgX neutro: contraste 1 y blanco 1, sin la curva dramática (1,35) del
		# juego; los colores de los atlas llegan sin virar.
		environment.tonemap_mode = Environment.TONE_MAPPER_AGX
		environment.tonemap_exposure = 1.0
		environment.tonemap_agx_contrast = 1.0
		environment.tonemap_agx_white = 1.0
		environment.tonemap_white = 1.0
		# Nada de efectos: sin niebla (tapa las filas del fondo), sin glow (las
		# emisivas de los carteles sangraban sobre las etiquetas), sin SSAO/SSIL
		# ni SDFGI (oscurecen los huecos y cambian con la distancia de cámara).
		environment.fog_enabled = false
		environment.volumetric_fog_enabled = false
		environment.glow_enabled = false
		environment.ssao_enabled = false
		environment.ssil_enabled = false
		environment.sdfgi_enabled = false
		environment.ssr_enabled = false
		environment.adjustment_enabled = false
		if not _save_resource(environment, ENVIRONMENT):
			return false
	if not ResourceLoader.exists(CAMERA_ATTRIBUTES):
		var attributes := CameraAttributesPractical.new()
		attributes.resource_name = "asset_gallery_camera_attributes"
		# Exposición 1 y sin autoexposición: una pieza oscura al lado de una
		# clara no cambia el brillo de la captura.
		attributes.exposure_multiplier = 1.0
		attributes.auto_exposure_enabled = false
		attributes.dof_blur_far_enabled = false
		attributes.dof_blur_near_enabled = false
		if not _save_resource(attributes, CAMERA_ATTRIBUTES):
			return false
	return true


func _save_resource(resource: Resource, path: String) -> bool:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("build_asset_gallery: no se pudo guardar '%s': %s" % [path, error_string(err)])
		return false
	print("build_asset_gallery: %s creado." % path)
	return true


## Sol de estudio y relleno (ver las constantes `SUN_*` y `FILL_*`). La sombra
## del sol llega a toda la galería: su distancia máxima es la diagonal de la caja
## de las filas.
func _add_lights(gallery: Node3D, bounds: AABB) -> void:
	var sun := _directional("Sun", SUN_ELEVATION_DEG, SUN_AZIMUTH_DEG, SUN_COLOR, SUN_ENERGY)
	sun.shadow_enabled = true
	sun.shadow_blur = SUN_SHADOW_BLUR
	sun.light_angular_distance = SUN_ANGULAR_DISTANCE_DEG
	sun.directional_shadow_max_distance = ceilf(Vector2(bounds.size.x, bounds.size.z).length())
	gallery.add_child(sun)
	var fill := _directional("Fill", FILL_ELEVATION_DEG, FILL_AZIMUTH_DEG, FILL_COLOR,
			FILL_ENERGY)
	fill.shadow_enabled = false
	gallery.add_child(fill)


## Luz direccional que llega desde [param elevation_deg] sobre el horizonte y
## [param azimuth_deg] grados a la izquierda de la cámara de fila (que mira a
## −Z desde +Z): la luz viaja hacia −Z. No se dibuja en el cielo.
func _directional(node_name: String, elevation_deg: float, azimuth_deg: float,
		color: Color, energy: float) -> DirectionalLight3D:
	var elevation := deg_to_rad(elevation_deg)
	var azimuth := deg_to_rad(azimuth_deg)
	var from := Vector3(-sin(azimuth) * cos(elevation), sin(elevation),
			cos(azimuth) * cos(elevation))
	var light := DirectionalLight3D.new()
	light.name = node_name
	light.transform = Transform3D(Basis.looking_at(-from, Vector3.UP), Vector3.ZERO)
	light.light_color = color
	light.light_energy = energy
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return light


## Suelo con rejilla de 10 m que cubre todas las filas.
func _add_ground(gallery: Node3D, bounds: AABB) -> void:
	var plane := PlaneMesh.new()
	var margin := 60.0
	plane.size = Vector2(ceilf(bounds.size.x + margin * 2.0), ceilf(bounds.size.z + margin * 2.0))
	plane.material = load(GRID_MATERIAL) as Material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var centre := bounds.get_center()
	ground.position = Vector3(roundf(centre.x), 0.0, roundf(centre.z))
	gallery.add_child(ground)


## Cámara inicial: mirando el comienzo de la primera fila.
func _add_camera(gallery: Node3D, rows: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 55.0
	camera.far = 6000.0
	var first := rows.get_child(0) as Node3D
	var z := first.position.z if first != null else 0.0
	camera.transform = AssetGallerySources.frame(0.0, 40.0, 8.0, z, camera.fov)
	gallery.add_child(camera)


## Título general: total, propio/descargado y conteo por familia (el primer
## tramo del nombre de cada fila de [constant AssetGallerySources.ROWS]).
func _add_title(gallery: Node3D) -> void:
	var groups: Dictionary[String, int] = {}
	for row: Dictionary in AssetGallerySources.ROWS:
		groups[String(row["name"]).get_slice("/", 0)] = 0
	var own := 0
	for entry: Dictionary in _entries:
		var group := String(entry["row"]).get_slice("/", 0)
		groups[group] = int(groups.get(group, 0)) + 1
		own += 1 if String(entry["made"]) == "propio" else 0
	var counts := PackedStringArray()
	for group: String in groups:
		var _added := counts.append("%s %d" % [group, groups[group]])
	var text := "Galería de objetos · %d piezas · propio %d · descargado %d\n%s" % [
		_entries.size(), own, _entries.size() - own, " · ".join(counts)]
	var title := _label(text, TITLE_FONT_SIZE, 400.0)
	title.name = "Title"
	title.position = Vector3(20.0, 14.0, 12.0)
	gallery.add_child(title)


# --------------------------------------------------------------------------
# Inventario
# --------------------------------------------------------------------------

## Escribe `assets/INVENTARIO.md` con [method AssetGallerySources.inventory_text].
func _write_inventory() -> bool:
	var path := AssetGallerySources.INVENTORY_PATH
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("build_asset_gallery: no se pudo escribir '%s': %s"
				% [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(AssetGallerySources.inventory_text(_entries))
	file.close()
	print("build_asset_gallery: %s escrito." % path)
	return true


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

func _scale() -> Mesh:
	if _scale_mesh == null:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = SCALE_RADIUS
		cylinder.bottom_radius = SCALE_RADIUS
		cylinder.height = SCALE_HEIGHT
		cylinder.radial_segments = 8
		cylinder.rings = 1
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.98, 0.72, 0.2, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.98, 0.72, 0.2, 1.0)
		material.emission_energy_multiplier = 0.6
		cylinder.material = material
		_scale_mesh = cylinder
	return _scale_mesh


## Caja de [param entry] ya girada por su `yaw`.
func _rotated_box(entry: Dictionary) -> AABB:
	var basis := Basis(Vector3.UP, float(entry["yaw"]))
	return Transform3D(basis, Vector3.ZERO) * (entry["aabb"] as AABB)


## Los ids son nombres de nodo y de búsqueda: no pueden repetirse.
func _unique_ids() -> bool:
	var seen: Dictionary[String, String] = {}
	var ok := true
	for entry: Dictionary in _entries:
		var id := String(entry["id"])
		if seen.has(id):
			push_error("build_asset_gallery: id repetido '%s' (%s y %s)"
					% [id, seen[id], String(entry["path"])])
			ok = false
		seen[id] = String(entry["path"])
	return ok


## Asigna el dueño a todo lo que se creó acá. Las instancias de escena se
## adueñan sólo en su raíz: su interior lo trae la escena instanciada.
func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_own(child, owner)


func _report() -> void:
	var per_row: Dictionary[String, int] = {}
	for entry: Dictionary in _entries:
		var row := String(entry["row"])
		per_row[row] = int(per_row.get(row, 0)) + 1
	for row: Dictionary in AssetGallerySources.ROWS:
		print("  %-32s %3d" % [String(row["name"]), int(per_row.get(String(row["name"]), 0))])
	print("  %-32s %3d" % ["total", _entries.size()])
	print("  dron de referencia: %s m motor a motor" % AssetGallerySources.num(_drone_span))
	for entry: Dictionary in _entries:
		var marks := AssetGallerySources.marks_line(entry)
		if not marks.is_empty():
			print("  %s: %s" % [String(entry["id"]), marks])
		if not String(entry.get("note", "")).is_empty():
			print("  nota %s: %s" % [String(entry["id"]), String(entry["note"])])
