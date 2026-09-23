## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Hornea las piezas **propias** del pueblo de ruta: las que ningún pack tiene
## (`docs/17` §7.2, plan P2c WP-D1).
##
## Los cuatro packs de `assets/town/` traen casas, follaje y mobiliario, pero no
## traen ni una estación de servicio, ni un tanque de agua, ni un silo, ni un
## cartel de ruta, ni un vehículo. Eso se modela acá, una sola vez, y se comitea
## como recurso: el mismo trato que `tools/build_city_meshes.gd` le da a las
## ruinas y a las rocas.
##
## Produce:
##
## - `assets/city/materials/town_{concrete,sheet,metal,wood}.tres` — cuatro de las
##   cinco familias de material de la gramática de `docs/17` §4. Son
##   **compartidas**: una copia por pieza serían dieciocho materiales y dieciocho
##   cambios de estado por cuadro. La quinta, `town_signs.tres`, se escribe a
##   mano y se comitea: su textura es `signs.png`, que en la corrida que lo
##   genera todavía no pasó por el importador de Godot.
## - `assets/town/signs.png` — el atlas de carteles de 512 × 512, con el texto
##   pintado por una fuente de mapa de bits de 5 × 7 incluida en este archivo.
## - `assets/city/props/<pieza>.res` — un [ArrayMesh] por pieza, con una
##   superficie por familia de material que la pieza use.
## - `city/pieces/town/<pieza>.tscn` (edificios) y `city/pieces/town/props/<pieza>.tscn`
##   (props), con el mismo contrato que las piezas importadas de los packs:
##   `StaticBody3D` en la capa `city`, un `MeshInstance3D` hijo directo, un
##   `CollisionShape3D` llamado `IntactShape` y los metadatos `piece_id`,
##   `base_size` y `town_kind`.
## - `assets/town/pieces_manifest.json` — el índice **de todo el pueblo**: estas
##   dieciocho piezas más las de los cuatro packs, con clase, huella, alto,
##   origen, frente, procedencia y triángulos. Es lo que WP-D2 funde en
##   `TownDesign.PIECE_CLASS` y en la tabla de escenas de `build_town.gd`.
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_town_props.gd
## [/codeblock]
##
## ## Orientación y origen
##
## Todas las piezas se construyen **con el frente en −X**, que es la convención
## real del pueblo: la puerta de `house_a` está en su cara −X (receta
## `models/nuke_town.json`) y `CityGrid` le suma [code]TOWN_YAW_OFFSET[/code] =
## −90° a cualquier pieza que traiga el metadato `town_kind`. El encargo de WP-D1
## pedía −Z; se sigue la convención real y queda escrita en el manifiesto, porque
## la alternativa —media docena de piezas nuevas mirando noventa grados a un lado
## de las casas— no se ve en ningún informe y se ve en la primera captura.
##
## El origen es el **centro de la base a `y = 0`**, con dos excepciones
## declaradas en el manifiesto: los tramos de cerco arrancan en su extremo
## inicial (`start_x`), porque se siembran encadenados, y el tablero del puente
## tiene la **cara superior** en `y = 0` (`deck_top_centre`), porque lo que se
## apoya sobre él es la calzada.
##
## ## Determinismo
##
## No hay azar: no se usa `RandomNumberGenerator` en ninguna pieza. Dos corridas
## producen los mismos `.res` byte a byte, y eso es lo que verifica el md5 del
## informe de WP-D1.
extends SceneTree

const PROP_DIR: String = "res://assets/city/props"
const MATERIAL_DIR: String = "res://assets/city/materials"
const TOWN_DIR: String = "res://assets/town"
const PIECE_DIR: String = "res://city/pieces/town"
const SIGNS_PATH: String = "res://assets/town/signs.png"
const MANIFEST_PATH: String = "res://assets/town/pieces_manifest.json"

## Capa 8 `city` y su máscara, escritas como literales.
##
## Este script corre con `-s`, así que Godot compila su árbol de dependencias
## **antes** de dar de alta los autoload; nombrar a [PhysicsLayers] arrastraría
## esa cadena y el arranque moriría con «Identifier not found: Global». Es el
## mismo motivo por el que `tools/build_terrain.gd` carga el plano con `load()`.
## Los valores son `PhysicsLayers.CITY` y
## `WORLD | DRONE | ENEMY_BODY | PROJECTILE_PLAYER | PROJECTILE_ENEMY | DEBRIS`.
const CITY_LAYER: int = 128
const CITY_MASK: int = 311

## Distancia a la que los props se desvanecen, la misma que fija
## `asset_import/import_town_piece.gd` para los props de los packs.
const PROP_VISIBILITY_RANGE_END: float = 180.0

## Presupuesto de triángulos por clase (plan P2c WP-D1).
const BUDGETS: Dictionary[String, int] = {
	"building": 1500, "prop": 300, "vehicle": 200,
}

## Lado del atlas de carteles, en píxeles.
const ATLAS_SIZE: int = 512

# --------------------------------------------------------------------------
# Paleta
# --------------------------------------------------------------------------

## Los colores se llevan en el **color de vértice** y no en el material: así las
## cinco familias siguen siendo cinco materiales —cinco lotes de dibujo— y dentro
## de cada una cabe toda la variedad que haga falta. Los cinco `.tres` llevan
## `vertex_color_use_as_albedo`.
const CONCRETE := Color(0.66, 0.65, 0.62)
const CONCRETE_DARK := Color(0.49, 0.48, 0.46)
const SHEET := Color(0.60, 0.62, 0.63)
const SHEET_RUST := Color(0.46, 0.36, 0.29)
const PAINT_WHITE := Color(0.85, 0.85, 0.82)
const PAINT_ORANGE := Color(0.95, 0.45, 0.10)
const PAINT_RED := Color(0.62, 0.17, 0.14)
const PAINT_GREEN := Color(0.21, 0.35, 0.25)
const PAINT_BLUE := Color(0.20, 0.32, 0.47)
const PAINT_YELLOW := Color(0.80, 0.66, 0.20)
const WOOD := Color(0.46, 0.33, 0.21)
const WOOD_DARK := Color(0.33, 0.23, 0.15)
const METAL_DARK := Color(0.28, 0.29, 0.30)
const GLASS := Color(0.13, 0.17, 0.19)
const TYRE := Color(0.10, 0.10, 0.11)

## Familias, en el orden en que se emiten las superficies. Fijo: dos corridas
## tienen que producir las superficies en el mismo orden o el `.res` cambia.
const FAMILIES: PackedStringArray = ["concrete", "sheet", "metal", "wood", "signs"]

# --------------------------------------------------------------------------
# Fuente de mapa de bits 5 × 7 para el atlas de carteles
# --------------------------------------------------------------------------

## Caracteres que sabe dibujar [method _draw_text], en el orden de
## [constant FONT_ROWS].
const FONT_CHARS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -.,/*"

## Siete filas por glifo, cada una un dígito en base 32 con el bit 16 a la
## izquierda. Una fuente vectorial habría hecho falta rasterizarla con un
## `CanvasItem`, que en `--headless` no existe; ésta cabe en cuarenta líneas, es
## determinista y el grano de píxel es justamente el del resto del pueblo.
const FONT_ROWS: PackedStringArray = [
	"EHHVHHH", "UHHUHHU", "EHGGGHE", "UHHHHHU", "VGGUGGV", "VGGUGGG", "EHGNHHF",
	"HHHVHHH", "E44444E", "72222IC", "HIKOKIH", "GGGGGGV", "HRLLHHH", "HPLJHHH",
	"EHHHHHE", "UHHUGGG", "EHHHLID", "UHHUKIH", "FGGE11U", "V444444", "HHHHHHE",
	"HHHHHA4", "HHHLLRH", "HHA4AHH", "HHA4444", "V1248GV", "EHJLPHE", "4C4444E",
	"EH1248V", "V2421HE", "26AIV22", "VGU11HE", "68GUHHE", "V124888", "EHHEHHE",
	"EHHF12C", "0000000", "000V000", "00000CC", "0000C48", "122488G", "00CC000",
]

## Celdas del atlas, en píxeles: `{nombre: Rect2i}`. Las UV de cada cartel salen
## de acá dividido por [constant ATLAS_SIZE].
const ATLAS_CELLS: Dictionary[String, Rect2i] = {
	"welcome_a": Rect2i(0, 0, 512, 64),
	"welcome_b": Rect2i(0, 64, 512, 64),
	"price": Rect2i(0, 128, 256, 192),
	"narrow": Rect2i(256, 128, 128, 128),
	"speed": Rect2i(384, 128, 128, 128),
	"plaque": Rect2i(0, 320, 256, 64),
	"flag": Rect2i(256, 320, 192, 128),
	"blank": Rect2i(448, 448, 64, 64),
}

# --------------------------------------------------------------------------
# Estado
# --------------------------------------------------------------------------

var _materials: Dictionary[String, StandardMaterial3D] = {}
var _manifest: Dictionary = {}


func _initialize() -> void:
	_ensure_dir(PROP_DIR)
	_ensure_dir(MATERIAL_DIR)
	_ensure_dir("%s/props" % PIECE_DIR)

	_write_atlas()
	_build_materials()

	_build_gas_station()
	_build_water_tower()
	_build_silo()
	_build_field_shed()

	_build_lamp_post()
	_build_bench()
	_build_flag_mast()
	_build_monument()
	_build_welcome_sign()
	_build_road_sign_narrow()
	_build_road_sign_speed()
	_build_fence_post()
	_build_fence_wire()
	_build_bridge_deck()
	_build_vehicles()

	_write_manifest()
	print("build_town_props: listo.")
	quit(0)


# --------------------------------------------------------------------------
# Materiales
# --------------------------------------------------------------------------

## Las cinco familias de `docs/17` §4. Se guardan **antes** que las mallas y se
## recargan desde disco para que las mallas las referencien como recurso externo
## en vez de incrustar una copia cada una (misma razón que en
## `build_city_meshes.gd`).
func _build_materials() -> void:
	# `noise` es la frecuencia en ciclos por textura; `low`/`high` son los dos
	# extremos de la rampa con la que el ruido se convierte en color. Ver
	# [method _noise_texture]: la rampa es lo que separa «grano de hormigón» de
	# «manchón de camuflaje».
	var recipes: Array[Dictionary] = [
		{"id": "concrete", "colour": Color.WHITE, "rough": 0.94, "spec": 0.20,
			"noise": 22.0, "scale": 0.10,
			"low": Color(0.389, 0.379, 0.356), "high": Color(0.621, 0.606, 0.574)},
		{"id": "sheet", "colour": Color.WHITE, "rough": 0.62, "spec": 0.45,
			"noise": 10.0, "scale": 0.22,
			"low": Color(0.360, 0.355, 0.345), "high": Color(0.660, 0.650, 0.635)},
		{"id": "metal", "colour": Color.WHITE, "rough": 0.48, "spec": 0.55,
			"noise": 0.0, "scale": 0.0},
		{"id": "wood", "colour": Color.WHITE, "rough": 0.88, "spec": 0.25,
			"noise": 11.0, "scale": 0.16},
	]
	for recipe: Dictionary in recipes:
		var material := StandardMaterial3D.new()
		material.resource_name = "town_%s" % recipe["id"]
		material.albedo_color = recipe["colour"]
		material.roughness = float(recipe["rough"])
		material.metallic_specular = float(recipe["spec"])
		# El color va en el vértice: una sola familia pinta el hormigón limpio y
		# el sucio, la chapa gris y la oxidada.
		material.vertex_color_use_as_albedo = true
		if float(recipe["noise"]) > 0.0:
			material.albedo_texture = _noise_texture(256, float(recipe["noise"]),
					recipe.get("low", Color.BLACK) as Color,
					recipe.get("high", Color.WHITE) as Color)
			material.uv1_triplanar = true
			var scale := float(recipe["scale"])
			material.uv1_scale = Vector3(scale, scale, scale)
		_save(material, "%s/town_%s.tres" % [MATERIAL_DIR, recipe["id"]])

	for family: String in FAMILIES:
		var path := "%s/town_%s.tres" % [MATERIAL_DIR, family]
		_materials[family] = ResourceLoader.load(path, "StandardMaterial3D",
				ResourceLoader.CACHE_MODE_REPLACE) as StandardMaterial3D
		if _materials[family] == null:
			push_error("build_town_props: no se pudo recargar '%s'" % path)


## Textura de ruido procedural, guardada dentro del `.tres` del material. La
## semilla es fija: el `.tres` tiene que salir igual en dos corridas.
##
## ## Por qué hay rampa y por qué la escala es fina (WP-D3, defecto 3)
##
## Sin rampa, el ruido sale en todo el rango `[0, 1]` y el material lo multiplica
## por el color del vértice: el hormigón pasaba de negro a blanco dentro de la
## misma pared. Con la frecuencia de WP-D1 —siete ciclos por textura, o sea una
## onda de metro y medio sobre la escala de 0,10— el resultado eran **manchones
## grises de camuflaje** sobre el silo, el tanque, el galpón y la estación, que
## es lo contrario de la paleta plana de las casas Nuke que tienen al lado.
##
## Las dos palancas, las dos en la receta:
##
## - **la rampa** recorta el recorrido del ruido alrededor de la media —que se
##   conserva, para no cambiar cuán claro es el hormigón— y de paso lo entibia:
##   el extremo claro tiene más rojo que azul, que es el tono de un revoque al
##   sol del anochecer;
## - **la frecuencia** sube de 7 a 22 ciclos por textura en el hormigón y de 3 a
##   10 en la chapa, así que la mancha de metro y medio pasa a grano de medio
##   metro y se lee como superficie, no como dibujo.
##
## ## Cómo se mide, y por qué la medida de WP-D3 no servía (WP-D3b)
##
## WP-D3 midió la desviación estándar «sobre una cara plana del silo a 30 m» y
## le dio 0,0834. El silo **no tiene** una cara plana: es un cilindro con una
## escalera al medio y tres zunchos. Esa medida sumaba el moteado, el degradado
## del cilindro y los herrajes, y por eso no se movió al tocar la rampa: con la
## rampa ya puesta seguía dando 0,0846.
##
## `tools/out/wpd3/mottle_probe.gd` mide en cambio una **placa plana de 6 × 6 m**
## del mismo material, de frente al sol y a 30 m, que es la cara plana que el
## silo no tiene. Ahí la rampa de WP-D3 daba **0,0441** contra un criterio de
## 0,04, así que el defecto seguía abierto. Estrechar la rampa a 0,68 de su
## recorrido —conservando la media (0,505; 0,4925; 0,465) y el sesgo cálido—
## la deja en **0,0303**. La chapa ya cumplía (0,0311) y no se toca.
func _noise_texture(size: int, frequency: float, low: Color = Color.BLACK,
		high: Color = Color.WHITE) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 20260923
	noise.frequency = frequency / float(size)
	noise.fractal_octaves = 3

	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = size
	texture.height = size
	texture.seamless = true
	if low != Color.BLACK or high != Color.WHITE:
		var ramp := Gradient.new()
		ramp.set_color(0, low)
		ramp.set_color(1, high)
		texture.color_ramp = ramp
	return texture


# --------------------------------------------------------------------------
# Atlas de carteles
# --------------------------------------------------------------------------

## Pinta `assets/town/signs.png`: 512 × 512, fondo neutro y una celda por cartel.
func _write_atlas() -> void:
	var image := Image.create_empty(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.18, 0.18, 0.19, 1.0))

	# Bienvenida: dos franjas verdes con borde blanco, como la cartelería vial.
	_fill_cell(image, "welcome_a", PAINT_GREEN)
	_frame_cell(image, "welcome_a", 4, PAINT_WHITE)
	_draw_text(image, "welcome_a", "BIENVENIDOS", 7, PAINT_WHITE)
	_fill_cell(image, "welcome_b", PAINT_GREEN)
	_frame_cell(image, "welcome_b", 4, PAINT_WHITE)
	_draw_text(image, "welcome_b", "ESCUELA 12 * 1,2 KM", 4, PAINT_WHITE)

	# Cartel de precios de la estación: apagado, como pide `docs/17` §2.
	_fill_cell(image, "price", Color(0.11, 0.13, 0.16, 1.0))
	_frame_cell(image, "price", 6, PAINT_WHITE)
	_draw_text_at(image, "price", 16, 20, "NAFTA", 4, Color(0.55, 0.55, 0.52))
	_draw_text_at(image, "price", 16, 60, "1259", 6, Color(0.55, 0.50, 0.40))
	_draw_text_at(image, "price", 16, 112, "GAS OIL", 3, Color(0.55, 0.55, 0.52))
	_draw_text_at(image, "price", 16, 144, "1099", 6, Color(0.55, 0.50, 0.40))

	# Puente angosto: rombo blanco con borde rojo y las dos barras que se juntan.
	_fill_cell(image, "narrow", PAINT_WHITE)
	_frame_cell(image, "narrow", 10, PAINT_RED)
	var narrow: Rect2i = ATLAS_CELLS["narrow"]
	for row: int in range(26, 102):
		var pinch := 10 + absi(row - 64) / 2
		_span(image, narrow.position.x + 30 - pinch, narrow.position.y + row, 8, METAL_DARK)
		_span(image, narrow.position.x + 90 + pinch - 8, narrow.position.y + row, 8, METAL_DARK)

	# Velocidad máxima 40: disco blanco con aro rojo.
	_fill_cell(image, "speed", PAINT_WHITE)
	_ring_cell(image, "speed", 58, 12, PAINT_RED)
	_draw_text_at(image, "speed", 26, 40, "40", 10, METAL_DARK)

	# Placa del monumento.
	_fill_cell(image, "plaque", Color(0.30, 0.27, 0.22, 1.0))
	_draw_text(image, "plaque", "MEMORIA", 5, Color(0.72, 0.68, 0.56))

	# Bandera a media asta: celeste, blanco, celeste.
	var flag: Rect2i = ATLAS_CELLS["flag"]
	for row: int in flag.size.y:
		var third := row * 3 / flag.size.y
		var tone := Color(0.55, 0.74, 0.88) if third != 1 else Color(0.93, 0.93, 0.90)
		_span(image, flag.position.x, flag.position.y + row, flag.size.x, tone)

	_fill_cell(image, "blank", Color(0.32, 0.32, 0.31))

	var err := image.save_png(SIGNS_PATH)
	if err != OK:
		push_error("build_town_props: no se pudo guardar '%s': %s"
				% [SIGNS_PATH, error_string(err)])
		return
	print("  guardado %s (%d × %d)" % [SIGNS_PATH, ATLAS_SIZE, ATLAS_SIZE])


func _fill_cell(image: Image, cell: String, colour: Color) -> void:
	var rect: Rect2i = ATLAS_CELLS[cell]
	image.fill_rect(rect, colour)


func _frame_cell(image: Image, cell: String, width: int, colour: Color) -> void:
	var rect: Rect2i = ATLAS_CELLS[cell]
	for offset: int in width:
		_rect_outline(image, Rect2i(rect.position + Vector2i(offset + 2, offset + 2),
				rect.size - Vector2i(2 * offset + 4, 2 * offset + 4)), colour)


func _rect_outline(image: Image, rect: Rect2i, colour: Color) -> void:
	for x: int in rect.size.x:
		image.set_pixel(rect.position.x + x, rect.position.y, colour)
		image.set_pixel(rect.position.x + x, rect.position.y + rect.size.y - 1, colour)
	for y: int in rect.size.y:
		image.set_pixel(rect.position.x, rect.position.y + y, colour)
		image.set_pixel(rect.position.x + rect.size.x - 1, rect.position.y + y, colour)


func _ring_cell(image: Image, cell: String, radius: int, width: int, colour: Color) -> void:
	var rect: Rect2i = ATLAS_CELLS[cell]
	for y: int in rect.size.y:
		for x: int in rect.size.x:
			var distance := Vector2(float(x) - float(rect.size.x) * 0.5,
					float(y) - float(rect.size.y) * 0.5).length()
			if distance <= float(radius) and distance >= float(radius - width):
				image.set_pixel(rect.position.x + x, rect.position.y + y, colour)
			elif distance > float(radius):
				image.set_pixel(rect.position.x + x, rect.position.y + y,
						Color(0.18, 0.18, 0.19, 1.0))


func _span(image: Image, x: int, y: int, width: int, colour: Color) -> void:
	for offset: int in width:
		var px := x + offset
		if px < 0 or px >= ATLAS_SIZE or y < 0 or y >= ATLAS_SIZE:
			continue
		image.set_pixel(px, y, colour)


## Escribe [param text] centrado en la celda [param cell], a [param scale]
## píxeles por celda de la fuente.
func _draw_text(image: Image, cell: String, text: String, scale: int,
		colour: Color) -> void:
	var rect: Rect2i = ATLAS_CELLS[cell]
	var width := text.length() * 6 * scale - scale
	var x := (rect.size.x - width) / 2
	var y := (rect.size.y - 7 * scale) / 2
	_draw_text_at(image, cell, x, y, text, scale, colour)


## Escribe [param text] con la esquina superior izquierda en `(x, y)` **dentro**
## de la celda.
func _draw_text_at(image: Image, cell: String, x: int, y: int, text: String,
		scale: int, colour: Color) -> void:
	var rect: Rect2i = ATLAS_CELLS[cell]
	var cursor := x
	for index: int in text.length():
		var slot := FONT_CHARS.find(text[index])
		if slot < 0:
			slot = FONT_CHARS.find(" ")
		for row: int in 7:
			var bits := _base32(FONT_ROWS[slot][row])
			for column: int in 5:
				if (bits & (1 << (4 - column))) == 0:
					continue
				for dy: int in scale:
					for dx: int in scale:
						var px := rect.position.x + cursor + column * scale + dx
						var py := rect.position.y + y + row * scale + dy
						if not rect.has_point(Vector2i(px, py)):
							continue
						image.set_pixel(px, py, colour)
		cursor += 6 * scale


func _base32(digit: String) -> int:
	var slot := "0123456789ABCDEFGHIJKLMNOPQRSTUV".find(digit)
	return maxi(slot, 0)


## UV del punto `(u, v)` en `[0, 1]²` de la celda [param cell].
func _cell_uv(cell: String, u: float, v: float) -> Vector2:
	var rect: Rect2i = ATLAS_CELLS[cell]
	return Vector2((float(rect.position.x) + u * float(rect.size.x)) / float(ATLAS_SIZE),
			(float(rect.position.y) + v * float(rect.size.y)) / float(ATLAS_SIZE))


# --------------------------------------------------------------------------
# Constructor de mallas
# --------------------------------------------------------------------------

## Acumula geometría en una superficie por familia de material.
##
## Una pieza usa entre una y cuatro familias —el hormigón de las columnas, la
## chapa del techo, el metal pintado del toldo, el atlas del cartel— y cada
## familia sale como una superficie del mismo `ArrayMesh`. No se funden en una
## porque la rugosidad **es** la diferencia entre el hormigón y la chapa, y
## porque cuatro superficies que comparten cuatro materiales de disco siguen
## siendo cuatro lotes para toda la ciudad y no cuatro por pieza.
class Builder extends RefCounted:
	var tools: Dictionary[String, SurfaceTool] = {}

	func tool_for(family: String) -> SurfaceTool:
		if not tools.has(family):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[family] = surface
		return tools[family]

	## Un cuadrilátero con los cuatro vértices en orden, con normal exterior
	## [param normal].
	##
	## El orden se **corrige solo**: si el producto vectorial de los dos primeros
	## lados apunta hacia el mismo lado que la normal declarada, se invierte el
	## bobinado. Godot dibuja de frente los triángulos cuyo `(v1−v0)×(v2−v0)`
	## apunta **contra** la normal visible (la misma regla que comprueba
	## `CityGrid._field_quad` y que WP-T4 tuvo que arreglar en los chunks del
	## terreno); dejar que cada llamada acierte el orden a mano es la forma
	## segura de terminar con media pieza invisible.
	func quad(family: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			normal: Vector3, colour: Color, uvs: Array[Vector2]) -> void:
		var points: Array[Vector3] = [a, b, c, d]
		var texture: Array[Vector2] = uvs.duplicate()
		if (b - a).cross(c - a).dot(normal) > 0.0:
			points = [d, c, b, a]
			texture = [uvs[3], uvs[2], uvs[1], uvs[0]]
		var surface := tool_for(family)
		for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
			for slot: int in triangle:
				surface.set_uv(texture[slot])
				surface.set_color(colour)
				surface.add_vertex(points[slot])

	## Caja de [param size] centrada en el origen de [param xform].
	func box(family: String, xform: Transform3D, size: Vector3, colour: Color) -> void:
		var half := size * 0.5
		var corner := func(sx: float, sy: float, sz: float) -> Vector3:
			return xform * Vector3(half.x * sx, half.y * sy, half.z * sz)
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var faces: Array[Array] = [
			[Vector3.UP, [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]]],
			[Vector3.DOWN, [[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]]],
			[Vector3.BACK, [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]],
			[Vector3.FORWARD, [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1]]],
			[Vector3.RIGHT, [[1, -1, -1], [1, -1, 1], [1, 1, 1], [1, 1, -1]]],
			[Vector3.LEFT, [[-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]]],
		]
		for face: Array in faces:
			var signs: Array = face[1]
			quad(family, corner.call(signs[0][0], signs[0][1], signs[0][2]),
					corner.call(signs[1][0], signs[1][1], signs[1][2]),
					corner.call(signs[2][0], signs[2][1], signs[2][2]),
					corner.call(signs[3][0], signs[3][1], signs[3][2]),
					xform.basis * (face[0] as Vector3), colour, uvs)

	## Un triángulo suelto, con el mismo autocorrector de bobinado que
	## [method quad]: lo usan las caras de un cono y las tapas de un cilindro.
	func tri(family: String, a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
			colour: Color) -> void:
		var points: Array[Vector3] = [a, b, c]
		if (b - a).cross(c - a).dot(normal) > 0.0:
			points = [a, c, b]
		var surface := tool_for(family)
		for point: Vector3 in points:
			surface.set_uv(Vector2(point.x, point.z))
			surface.set_color(colour)
			surface.add_vertex(point)

	## Prisma de [param sides] lados, con radio [param bottom] en la base y
	## [param top] a [param height] metros, en el marco de [param xform] (el eje
	## del prisma es el `+Y` de ese marco). Cubre cilindros
	## ([param bottom] == [param top]) y conos ([param top] == 0).
	func tube(family: String, xform: Transform3D, bottom: float, top: float,
			height: float, sides: int, colour: Color, cap_top: bool,
			cap_bottom: bool) -> void:
		var ring_low: Array[Vector3] = []
		var ring_high: Array[Vector3] = []
		for index: int in sides:
			var angle := TAU * float(index) / float(sides)
			var unit := Vector3(cos(angle), 0.0, sin(angle))
			ring_low.append(xform * (unit * bottom))
			ring_high.append(xform * (unit * top + Vector3(0.0, height, 0.0)))
		var axis := (xform.basis * Vector3.UP).normalized()
		var base := xform.origin
		var apex := xform * Vector3(0.0, height, 0.0)
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var pointed := top <= 0.0001
		for index: int in sides:
			var next := (index + 1) % sides
			var outward := (ring_low[index] + ring_low[next]) * 0.5 - base
			outward -= axis * outward.dot(axis)
			if outward.length_squared() < 0.000001:
				outward = xform.basis * Vector3.RIGHT
			if pointed:
				tri(family, ring_low[index], ring_low[next], apex,
						outward.normalized(), colour)
			else:
				quad(family, ring_low[index], ring_low[next], ring_high[next],
						ring_high[index], outward.normalized(), colour, uvs)
		if cap_bottom:
			_cap(family, ring_low, base, -axis, colour)
		if cap_top and not pointed:
			_cap(family, ring_high, apex, axis, colour)

	func _cap(family: String, ring: Array[Vector3], centre: Vector3,
			normal: Vector3, colour: Color) -> void:
		var surface := tool_for(family)
		for index: int in ring.size():
			var next := (index + 1) % ring.size()
			var a := centre
			var b := ring[index]
			var c := ring[next]
			if (b - a).cross(c - a).dot(normal) > 0.0:
				var swap := b
				b = c
				c = swap
			for point: Vector3 in [a, b, c]:
				surface.set_uv(Vector2(point.x, point.z))
				surface.set_color(colour)
				surface.add_vertex(point)

	## Cierra las superficies y devuelve la malla, con las familias en el orden
	## de [constant FAMILIES].
	func commit(materials: Dictionary[String, StandardMaterial3D],
			order: PackedStringArray) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for family: String in order:
			if not tools.has(family):
				continue
			var surface := tools[family]
			surface.generate_normals()
			surface.generate_tangents()
			var arrays := surface.commit_to_arrays()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(family))
		return mesh


# --------------------------------------------------------------------------
# Edificios
# --------------------------------------------------------------------------

## Estación de servicio: el «hola» del pueblo (`docs/17` §2 y §3).
##
## Marquesina plana de 24 × 14 m a seis metros sobre cuatro columnas de hormigón,
## dos surtidores debajo, la tienda de 12 × 8 × 4 m adosada al fondo con el
## **toldo naranja** sobre la puerta —la gramática de `docs/17` §4: toldo naranja
## = pila— y el cartel de precios de ocho metros sobre la ruta.
func _build_gas_station() -> void:
	var build := Builder.new()
	# Marquesina: losa de chapa con el frente pintado de blanco, a 6 m.
	build.box("sheet", Transform3D(Basis.IDENTITY, Vector3(0.0, 6.40, 0.0)),
			Vector3(14.0, 0.60, 24.0), SHEET)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 6.02, 0.0)),
			Vector3(14.2, 0.30, 24.2), PAINT_WHITE)
	for x: float in [-5.0, 5.0]:
		for z: float in [-9.0, 9.0]:
			build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(x, 3.0, z)),
					Vector3(0.70, 6.0, 0.70), CONCRETE)
	# Playón: losa de hormigón de 2 cm bajo la marquesina.
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.06, 0.0)),
			Vector3(15.0, 0.12, 25.0), CONCRETE_DARK)

	# Dos surtidores bajo la marquesina.
	for z: float in [-5.0, 5.0]:
		build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, z)),
				Vector3(1.40, 0.50, 3.60), CONCRETE)
		build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.30, z - 0.9)),
				Vector3(0.55, 1.60, 0.90), PAINT_RED)
		build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.30, z + 0.9)),
				Vector3(0.55, 1.60, 0.90), PAINT_RED)

	# Tienda al fondo (+X), con puerta y banda de vidriera.
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(6.0, 2.0, 0.0)),
			Vector3(8.0, 4.0, 12.0), CONCRETE)
	build.box("sheet", Transform3D(Basis.IDENTITY, Vector3(6.0, 4.15, 0.0)),
			Vector3(8.4, 0.30, 12.4), SHEET_RUST)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(1.94, 2.30, 0.0)),
			Vector3(0.12, 1.60, 7.0), GLASS)
	build.box("wood", Transform3D(Basis.IDENTITY, Vector3(1.94, 1.05, -3.9)),
			Vector3(0.14, 2.10, 1.80), WOOD_DARK)
	# El toldo naranja sobre la puerta: en pendiente hacia afuera.
	build.box("metal", Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.32)),
			Vector3(1.10, 3.05, -3.9)), Vector3(1.80, 0.12, 2.60), PAINT_ORANGE)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(1.95, 2.86, -3.9)),
			Vector3(0.10, 0.55, 2.60), PAINT_ORANGE)

	# Cartel de precios: ocho metros, del lado de la ruta.
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(-5.6, 3.10, -11.6)),
			Vector3(0.40, 6.20, 0.40), PAINT_WHITE)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(-5.6, 7.00, -11.6)),
			Vector3(0.25, 2.00, 2.60), PAINT_WHITE)
	for side: int in 2:
		var x := -5.6 + (0.14 if side == 0 else -0.14)
		var normal := Vector3.RIGHT if side == 0 else Vector3.LEFT
		build.quad("signs",
				Vector3(x, 6.10, -12.80), Vector3(x, 6.10, -10.40),
				Vector3(x, 7.90, -10.40), Vector3(x, 7.90, -12.80), normal,
				Color.WHITE, _cell_rect("price"))

	_emit_piece("gas_station", "building", build, "box", {})


## Tanque de agua elevado: el hito del noreste (`docs/17` §2, hito A).
func _build_water_tower() -> void:
	var build := Builder.new()
	for x: float in [-2.6, 2.6]:
		for z: float in [-2.6, 2.6]:
			build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(x, 6.0, z)),
					Vector3(0.55, 12.0, 0.55), CONCRETE)
	# Dos anillos de arriostramiento: es lo que hace que la torre se lea calada
	# y no como cuatro palos sueltos.
	for height: float in [4.2, 8.6]:
		for z: float in [-2.6, 2.6]:
			build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, height, z)),
					Vector3(5.2, 0.16, 0.16), METAL_DARK)
		for x: float in [-2.6, 2.6]:
			build.box("metal", Transform3D(Basis.IDENTITY, Vector3(x, height, 0.0)),
					Vector3(0.16, 0.16, 5.2), METAL_DARK)
	# Tanque: cilindro de chapa de 7 m de diámetro y 4 de alto, con cono arriba.
	build.tube("sheet", Transform3D(Basis.IDENTITY, Vector3(0.0, 12.0, 0.0)),
			3.5, 3.5, 3.6, 14, SHEET, false, true)
	build.tube("sheet", Transform3D(Basis.IDENTITY, Vector3(0.0, 15.6, 0.0)),
			3.6, 0.0, 0.9, 14, SHEET_RUST, false, true)
	_ladder(build, Vector3(-2.6, 0.6, -2.6), 11.4)
	_emit_piece("water_tower", "building", build, "box", {})


## Silo con cono: el hito del suroeste (`docs/17` §2, hito B).
func _build_silo() -> void:
	var build := Builder.new()
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)),
			Vector3(7.0, 0.30, 7.0), CONCRETE_DARK)
	build.tube("sheet", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.30, 0.0)),
			3.0, 3.0, 10.7, 16, SHEET, false, false)
	build.tube("sheet", Transform3D(Basis.IDENTITY, Vector3(0.0, 11.0, 0.0)),
			3.1, 0.0, 3.0, 16, SHEET_RUST, false, true)
	# Tres zunchos: rompen el cilindro liso y lo hacen legible a cien metros.
	for height: float in [3.0, 6.0, 9.0]:
		build.tube("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, height, 0.0)),
				3.06, 3.06, 0.22, 16, METAL_DARK, false, false)
	_ladder(build, Vector3(-3.05, 0.4, 0.0), 10.4)
	_emit_piece("silo", "building", build, "box", {})


## Galpón de chapa a dos aguas con portón (`docs/17` §7.2, prioridad B).
func _build_field_shed() -> void:
	var build := Builder.new()
	var half_x := 5.0
	var half_z := 9.0
	var eave := 4.2
	var ridge := 6.0
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)),
			Vector3(half_x * 2.0 + 0.4, 0.30, half_z * 2.0 + 0.4), CONCRETE_DARK)
	# Cuatro paredes hasta el alero.
	build.box("sheet", Transform3D(Basis.IDENTITY, Vector3(0.0, eave * 0.5, -half_z)),
			Vector3(half_x * 2.0, eave, 0.14), SHEET)
	build.box("sheet", Transform3D(Basis.IDENTITY, Vector3(0.0, eave * 0.5, half_z)),
			Vector3(half_x * 2.0, eave, 0.14), SHEET)
	build.box("sheet", Transform3D(Basis.IDENTITY, Vector3(half_x, eave * 0.5, 0.0)),
			Vector3(0.14, eave, half_z * 2.0), SHEET)
	build.box("sheet", Transform3D(Basis.IDENTITY, Vector3(-half_x, eave * 0.5, 0.0)),
			Vector3(0.14, eave, half_z * 2.0), SHEET_RUST)
	# Dos faldones y los dos frontones.
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for side: float in [-1.0, 1.0]:
		build.quad("sheet",
				Vector3(side * (half_x + 0.3), eave - 0.1, -half_z - 0.3),
				Vector3(side * (half_x + 0.3), eave - 0.1, half_z + 0.3),
				Vector3(0.0, ridge, half_z + 0.3), Vector3(0.0, ridge, -half_z - 0.3),
				Vector3(side, 1.0, 0.0).normalized(), SHEET, uvs)
	for z: float in [-half_z, half_z]:
		var normal := Vector3(0.0, 0.0, signf(z))
		build.quad("sheet", Vector3(-half_x, eave, z), Vector3(half_x, eave, z),
				Vector3(0.0, ridge, z), Vector3(0.0, ridge, z), normal, SHEET, uvs)
	# Portón corredizo en la cara −X, el frente de la pieza.
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(-half_x - 0.10, 1.90, 0.0)),
			Vector3(0.10, 3.60, 5.60), PAINT_GREEN)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(-half_x - 0.16, 3.78, 0.0)),
			Vector3(0.12, 0.16, 6.20), METAL_DARK)
	_emit_piece("field_shed", "building", build, "box", {})


## Escalera exterior: dos largueros y un peldaño cada 35 cm. La usan el tanque y
## el silo, y es lo que le da escala humana a los dos hitos.
func _ladder(build: Builder, foot: Vector3, height: float) -> void:
	for side: float in [-0.22, 0.22]:
		build.box("metal", Transform3D(Basis.IDENTITY,
				foot + Vector3(0.0, height * 0.5, side)),
				Vector3(0.07, height, 0.07), METAL_DARK)
	var rungs := int(height / 0.35)
	for index: int in rungs:
		build.box("metal", Transform3D(Basis.IDENTITY,
				foot + Vector3(0.0, 0.35 * float(index + 1), 0.0)),
				Vector3(0.05, 0.05, 0.48), METAL_DARK)


# --------------------------------------------------------------------------
# Props
# --------------------------------------------------------------------------

## Poste de luz de avenida: ocho metros con brazo de dos y luminaria. **Sin luz
## real**: el presupuesto de luces con sombra de `docs/13` §3 no tiene sitio para
## una farola cada 25 m.
func _build_lamp_post() -> void:
	var build := Builder.new()
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.20, 0.0)),
			Vector3(0.50, 0.40, 0.50), CONCRETE_DARK)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 4.10, 0.0)),
			Vector3(0.18, 7.80, 0.18), PAINT_WHITE)
	build.box("metal", Transform3D(Basis.from_euler(Vector3(0.0, 0.0, -0.18)),
			Vector3(-1.00, 7.90, 0.0)), Vector3(2.10, 0.14, 0.14), PAINT_WHITE)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(-1.95, 7.62, 0.0)),
			Vector3(0.80, 0.22, 0.34), METAL_DARK)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(-1.95, 7.46, 0.0)),
			Vector3(0.70, 0.10, 0.26), Color(0.72, 0.68, 0.55))
	_emit_piece("lamp_post", "prop", build, "box", {})


## Banco de plaza de 1,8 m: tablones de madera sobre patas de hierro.
func _build_bench() -> void:
	var build := Builder.new()
	for z: float in [-0.75, 0.75]:
		build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, z)),
				Vector3(0.50, 0.44, 0.08), METAL_DARK)
		build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.18, 0.62, z)),
				Vector3(0.08, 0.50, 0.08), METAL_DARK)
	for x: float in [-0.20, 0.0, 0.20]:
		build.box("wood", Transform3D(Basis.IDENTITY, Vector3(x, 0.46, 0.0)),
				Vector3(0.17, 0.05, 1.80), WOOD)
	for height: float in [0.70, 0.86]:
		build.box("wood", Transform3D(Basis.IDENTITY, Vector3(0.22, height, 0.0)),
				Vector3(0.05, 0.14, 1.80), WOOD)
	_emit_piece("bench", "prop", build, "box", {})


## Mástil de diez metros con la bandera **a media asta**: la puso alguien esta
## tarde (`docs/17` §2, historia de la escuela).
func _build_flag_mast() -> void:
	var build := Builder.new()
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, 0.0)),
			Vector3(0.80, 0.50, 0.80), CONCRETE)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 5.20, 0.0)),
			Vector3(0.16, 9.50, 0.16), PAINT_WHITE)
	# Media asta: el paño arranca a 4,60 m y no a 9.
	var uvs := _cell_rect("flag")
	for side: int in 2:
		var normal := Vector3.RIGHT if side == 0 else Vector3.LEFT
		var x := 0.02 if side == 0 else -0.02
		build.quad("signs", Vector3(x, 4.60, 0.08), Vector3(x, 4.60, 1.88),
				Vector3(x, 5.80, 1.88), Vector3(x, 5.80, 0.08), normal,
				Color.WHITE, uvs)
	_emit_piece("flag_mast", "prop", build, "box", {})


## Monumento de la plaza: pedestal de 2 × 2 × 1,5 m con la placa y obelisco de
## cuatro metros.
func _build_monument() -> void:
	var build := Builder.new()
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.10, 0.0)),
			Vector3(2.60, 0.20, 2.60), CONCRETE_DARK)
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.85, 0.0)),
			Vector3(2.00, 1.50, 2.00), CONCRETE)
	build.tube("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.60, 0.0)),
			0.62, 0.26, 3.90, 4, CONCRETE, true, false)
	build.quad("signs", Vector3(-1.01, 0.75, -0.55), Vector3(-1.01, 0.75, 0.55),
			Vector3(-1.01, 1.30, 0.55), Vector3(-1.01, 1.30, -0.55), Vector3.LEFT,
			Color.WHITE, _cell_rect("plaque"))
	_emit_piece("monument", "prop", build, "box", {})


## Cartel de bienvenida: dos postes de tres metros y una chapa de 4 × 0,9 m con
## las dos franjas del atlas.
func _build_welcome_sign() -> void:
	var build := Builder.new()
	for z: float in [-1.70, 1.70]:
		build.box("wood", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.50, z)),
				Vector3(0.18, 3.00, 0.18), WOOD_DARK)
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 2.55, 0.0)),
			Vector3(0.08, 0.96, 4.00), PAINT_GREEN)
	for side: int in 2:
		var normal := Vector3.RIGHT if side == 0 else Vector3.LEFT
		var x := 0.05 if side == 0 else -0.05
		build.quad("signs", Vector3(x, 2.57, -1.98), Vector3(x, 2.57, 1.98),
				Vector3(x, 3.01, 1.98), Vector3(x, 3.01, -1.98), normal,
				Color.WHITE, _cell_rect("welcome_a"))
		build.quad("signs", Vector3(x, 2.09, -1.98), Vector3(x, 2.09, 1.98),
				Vector3(x, 2.53, 1.98), Vector3(x, 2.53, -1.98), normal,
				Color.WHITE, _cell_rect("welcome_b"))
	_emit_piece("welcome_sign", "prop", build, "box", {})


## Señal de puente angosto: rombo reglamentario sobre poste de 2,2 m.
func _build_road_sign_narrow() -> void:
	_build_road_sign("road_sign_narrow", "narrow", 0.45, true)


## Señal de velocidad máxima 40.
func _build_road_sign_speed() -> void:
	_build_road_sign("road_sign_speed", "speed", 0.40, false)


## Poste de señal con la chapa de [param cell], girada 45° si [param diamond].
func _build_road_sign(piece_id: String, cell: String, half: float,
		diamond: bool) -> void:
	var build := Builder.new()
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.15, 0.0)),
			Vector3(0.10, 2.30, 0.10), Color(0.72, 0.72, 0.70))
	var height := 2.30 + half
	var uvs := _cell_rect(cell)
	var corners: Array[Vector3] = []
	if diamond:
		var reach := half * 1.41421
		corners = [Vector3(0.0, height - reach, 0.0), Vector3(0.0, height, reach),
				Vector3(0.0, height + reach, 0.0), Vector3(0.0, height, -reach)]
	else:
		corners = [Vector3(0.0, height - half, -half), Vector3(0.0, height - half, half),
				Vector3(0.0, height + half, half), Vector3(0.0, height + half, -half)]
	for side: int in 2:
		var normal := Vector3.RIGHT if side == 0 else Vector3.LEFT
		var offset := Vector3(0.04 if side == 0 else -0.04, 0.0, 0.0)
		build.quad("signs", corners[0] + offset, corners[1] + offset,
				corners[2] + offset, corners[3] + offset, normal, Color.WHITE,
				_rotate_uvs(uvs, diamond))
	build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, height, 0.0)),
			Vector3(0.03, half * 1.9, half * 1.9), Color(0.55, 0.55, 0.53))
	_emit_piece(piece_id, "prop", build, "box", {})


## UV del cuadrilátero de una señal; en el rombo hay que girarlas un cuarto para
## que el dibujo salga derecho y no apoyado en un vértice.
func _rotate_uvs(uvs: Array[Vector2], rotate: bool) -> Array[Vector2]:
	if not rotate:
		return uvs
	return [uvs[1], uvs[2], uvs[3], uvs[0]]


## Poste de alambrado suelto de 1,3 m: el que cierra un frente cuando el tramo
## de seis metros no entra.
func _build_fence_post() -> void:
	var build := Builder.new()
	build.box("wood", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.65, 0.0)),
			Vector3(0.12, 1.30, 0.12), WOOD_DARK)
	_emit_piece("fence_post", "prop", build, "box", {})


## Tramo de alambrado de seis metros a lo largo de +X, con el origen en el
## extremo inicial: dos postes y tres alambres.
##
## El origen no está en el centro **a propósito**: un cerco se siembra
## encadenando tramos sobre una polilínea, y con el origen en el medio cada
## eslabón hay que corregirlo medio tramo. Queda declarado en el manifiesto.
func _build_fence_wire() -> void:
	var build := Builder.new()
	for x: float in [0.10, 5.90]:
		build.box("wood", Transform3D(Basis.IDENTITY, Vector3(x, 0.60, 0.0)),
				Vector3(0.12, 1.20, 0.12), WOOD_DARK)
	for height: float in [0.42, 0.74, 1.06]:
		build.box("metal", Transform3D(Basis.IDENTITY, Vector3(3.0, height, 0.0)),
				Vector3(6.0, 0.035, 0.035), Color(0.46, 0.45, 0.42))
	_emit_piece("fence_wire_6m", "prop", build, "box", {"origin": "start_x"})


## Tablero del puente: 20 m a lo largo de +X, 12 de ancho, con la **cara superior
## en `y = 0`**.
##
## La calzada no la pone esta pieza sino la cinta de asfalto del viario, que
## sigue el perfil recto entre los extremos del vano; por eso el tablero no lleva
## colisión propia (la pone el terreno y la cinta) y por eso su cara de arriba
## está en el cero: se cuelga directamente sobre la rasante de la ruta.
func _build_bridge_deck() -> void:
	var build := Builder.new()
	build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, -0.40, 0.0)),
			Vector3(20.0, 0.80, 12.0), CONCRETE)
	# Dos vigas longitudinales: sin ellas, desde el cauce el puente es una tabla.
	for z: float in [-4.0, 4.0]:
		build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(0.0, -1.10, z)),
				Vector3(19.0, 0.60, 1.10), CONCRETE_DARK)
	# Estribos: dos metros de muro en cada extremo, tres metros hacia abajo.
	for x: float in [-9.0, 9.0]:
		build.box("concrete", Transform3D(Basis.IDENTITY, Vector3(x, -2.30, 0.0)),
				Vector3(2.0, 3.00, 12.0), CONCRETE_DARK)
	# Barandas de caño de un metro a los dos lados.
	for z: float in [-5.85, 5.85]:
		for height: float in [0.45, 0.92]:
			build.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.0, height, z)),
					Vector3(20.0, 0.08, 0.08), Color(0.70, 0.70, 0.67))
		# Siete parantes por lado y no nueve: con nueve el tablero se iba a 324
		# triángulos, por encima de los 300 de la clase, y a 2,9 m de paso la
		# baranda sigue leyéndose como baranda desde la ruta.
		for index: int in 7:
			var x := -8.7 + 2.9 * float(index)
			build.box("metal", Transform3D(Basis.IDENTITY, Vector3(x, 0.50, z)),
					Vector3(0.09, 1.00, 0.09), Color(0.70, 0.70, 0.67))
	_emit_piece("bridge_deck", "prop", build, "none",
			{"origin": "deck_top_centre"})


## Los cuatro vehículos **placeholder** (`docs/17` §7.2, prioridad A).
##
## No hay vehículos en ninguno de los cuatro packs y el pueblo sin autos no
## cuenta la historia de `docs/17` §0.10 —los autos apuntando hacia afuera son lo
## que dice qué pasó los últimos veinte minutos. Son cajas con ruedas y
## parabrisas, con colores planos y sin una sola línea de detalle: tienen que
## leerse como marcador de posición desde el primer vistazo, y el manifiesto los
## declara con `placeholder: true` para que el informe de arte los liste.
func _build_vehicles() -> void:
	var recipes: Array[Dictionary] = [
		{"id": "car_a", "length": 4.20, "width": 1.72, "body": 0.70, "cabin": 0.62,
			"colour": Color(0.62, 0.22, 0.20), "cabin_back": 0.30},
		{"id": "car_b", "length": 4.40, "width": 1.78, "body": 0.72, "cabin": 0.60,
			"colour": Color(0.24, 0.34, 0.46), "cabin_back": 0.26},
		{"id": "pickup", "length": 5.20, "width": 1.92, "body": 0.86, "cabin": 0.78,
			"colour": Color(0.72, 0.70, 0.64), "cabin_back": 0.72},
		{"id": "truck", "length": 8.00, "width": 2.45, "body": 1.05, "cabin": 1.35,
			"colour": Color(0.30, 0.42, 0.30), "cabin_back": 1.90},
	]
	for recipe: Dictionary in recipes:
		var build := Builder.new()
		var length := float(recipe["length"])
		var width := float(recipe["width"])
		var body := float(recipe["body"])
		var cabin := float(recipe["cabin"])
		var wheel := 0.34
		var colour: Color = recipe["colour"]
		# Caja principal.
		build.box("metal", Transform3D(Basis.IDENTITY,
				Vector3(0.0, wheel + body * 0.5, 0.0)),
				Vector3(length, body, width), colour)
		# Cabina, corrida hacia el frente (−X).
		var cabin_length := length * 0.42
		var cabin_x := -length * 0.5 + cabin_length * 0.5 + float(recipe["cabin_back"])
		build.box("metal", Transform3D(Basis.IDENTITY,
				Vector3(cabin_x, wheel + body + cabin * 0.5, 0.0)),
				Vector3(cabin_length, cabin, width * 0.94), colour)
		# Parabrisas y luneta.
		for side: float in [-1.0, 1.0]:
			build.box("metal", Transform3D(Basis.IDENTITY,
					Vector3(cabin_x + side * cabin_length * 0.5,
					wheel + body + cabin * 0.55, 0.0)),
					Vector3(0.08, cabin * 0.62, width * 0.80), GLASS)
		# Faros.
		for z: float in [-width * 0.34, width * 0.34]:
			build.box("metal", Transform3D(Basis.IDENTITY,
					Vector3(-length * 0.5 - 0.03, wheel + body * 0.62, z)),
					Vector3(0.08, 0.16, 0.28), Color(0.86, 0.84, 0.70))
		# Cuatro ruedas hexagonales: baratas y claramente de relleno. El eje del
		# prisma es el `+Y` de su marco, así que el marco se gira un cuarto sobre
		# X para dejarlo a lo ancho del vehículo.
		var tread := 0.22
		for x: float in [-length * 0.32, length * 0.32]:
			for side: float in [-1.0, 1.0]:
				var inner := side * (width * 0.5 - 0.02 - tread)
				var basis := Basis.from_euler(Vector3(-side * PI * 0.5, 0.0, 0.0))
				build.tube("metal", Transform3D(basis, Vector3(x, wheel, inner)),
						wheel, wheel, tread, 6, TYRE, true, true)
		_emit_piece(String(recipe["id"]), "vehicle", build, "box",
				{"placeholder": true})


# --------------------------------------------------------------------------
# Emisión
# --------------------------------------------------------------------------

## Cierra una pieza: guarda la malla, arma la escena y la anota en el manifiesto.
func _emit_piece(piece_id: String, kind: String, build: Builder, shape: String,
		extra: Dictionary) -> void:
	var mesh := build.commit(_materials, FAMILIES)
	if mesh.get_surface_count() == 0:
		push_error("build_town_props: '%s' no produjo ninguna superficie" % piece_id)
		return
	var origin := String(extra.get("origin", "base_centre"))
	mesh = _place_origin(mesh, origin)
	mesh.resource_name = piece_id
	var mesh_path := "%s/%s.res" % [PROP_DIR, piece_id]
	_save(mesh, mesh_path)
	var stored := ResourceLoader.load(mesh_path, "ArrayMesh",
			ResourceLoader.CACHE_MODE_REPLACE) as ArrayMesh
	if stored == null:
		push_error("build_town_props: no se pudo recargar '%s'" % mesh_path)
		return

	var bounds := stored.get_aabb()
	var triangles := _triangle_count(stored)
	var budget := int(BUDGETS.get(kind, BUDGETS["prop"]))
	if triangles > budget:
		push_error("build_town_props: '%s' tiene %d triángulos, presupuesto %d"
				% [piece_id, triangles, budget])
	var folder := PIECE_DIR if kind == "building" else "%s/props" % PIECE_DIR
	var scene_path := "%s/%s.tscn" % [folder, piece_id]
	_save_scene(piece_id, kind, bounds, shape, scene_path, triangles, mesh_path)

	_manifest[piece_id] = {
		"class": "building" if kind == "building" else "prop",
		"scene": scene_path,
		"footprint": [snappedf(bounds.size.x, 0.001), snappedf(bounds.size.z, 0.001)],
		"height": snappedf(bounds.size.y, 0.001),
		"origin": origin,
		"front": _front_of(piece_id),
		"source": "procedural",
		"placeholder": bool(extra.get("placeholder", false)),
		"tris": triangles,
		"shape": shape,
		"surfaces": stored.get_surface_count(),
	}
	print("  %-18s %-8s %5d tris · %5.2f × %5.2f × %5.2f m · %d superficies"
			% [piece_id, kind, triangles, bounds.size.x, bounds.size.y,
			bounds.size.z, stored.get_surface_count()])


## Lleva la malla a su origen declarado: centro de la base, extremo inicial en X
## o cara superior del tablero.
func _place_origin(mesh: ArrayMesh, origin: String) -> ArrayMesh:
	var bounds := mesh.get_aabb()
	var shift := Vector3.ZERO
	match origin:
		"base_centre":
			shift = Vector3(-bounds.get_center().x, -bounds.position.y,
					-bounds.get_center().z)
		"start_x":
			shift = Vector3(-bounds.position.x, -bounds.position.y,
					-bounds.get_center().z)
		"deck_top_centre":
			shift = Vector3(-bounds.get_center().x, -bounds.end.y,
					-bounds.get_center().z)
		_:
			push_error("build_town_props: origen '%s' desconocido" % origin)
	if shift.length_squared() < 1e-12:
		return mesh
	var moved := ArrayMesh.new()
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index: int in vertices.size():
			vertices[index] = vertices[index] + shift
		arrays[Mesh.ARRAY_VERTEX] = vertices
		moved.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		moved.surface_set_material(surface, mesh.surface_get_material(surface))
	return moved


## Escena de la pieza, con el mismo contrato que las importadas de los packs.
##
## Se escribe **como texto** y no con `PackedScene.pack()` + `ResourceSaver`. El
## serializador de Godot le pone a cada `ext_resource`, a cada `sub_resource` y a
## cada nodo un identificador aleatorio, así que dos corridas idénticas producían
## dos `.tscn` con md5 distinto y el criterio de reproducibilidad de WP-D1 no se
## podía cumplir. Escrito a mano el archivo es una función pura de la pieza.
func _save_scene(piece_id: String, kind: String, bounds: AABB, shape: String,
		path: String, triangles: int, mesh_path: String) -> void:
	var is_building := kind == "building"
	var steps := 3 if shape != "none" else 2
	var lines := PackedStringArray()
	lines.append("[gd_scene load_steps=%d format=3]" % steps)
	lines.append("")
	lines.append("[ext_resource type=\"ArrayMesh\" path=\"%s\" id=\"1_mesh\"]" % mesh_path)
	lines.append("")
	if shape != "none":
		lines.append("[sub_resource type=\"BoxShape3D\" id=\"BoxShape3D_intact\"]")
		lines.append("size = %s" % _vector_text(bounds.size))
		lines.append("")
	lines.append("[node name=\"%s\" type=\"StaticBody3D\"]" % piece_id)
	lines.append("collision_layer = %d" % (CITY_LAYER if shape != "none" else 0))
	lines.append("collision_mask = %d" % (CITY_MASK if shape != "none" else 0))
	lines.append("metadata/piece_id = &\"%s\"" % piece_id)
	lines.append("metadata/base_size = %s" % _vector_text(bounds.size))
	lines.append("metadata/town_kind = \"%s\"" % ("building" if is_building else "prop"))
	lines.append("metadata/triangle_count = %d" % triangles)
	lines.append("metadata/window_voxels = 0")
	lines.append("")
	lines.append("[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]")
	# 1 = GI_MODE_STATIC, 1 = SHADOW_CASTING_SETTING_ON. Se escriben aunque sean
	# los valores de fábrica: `town_import_check` los exige y un cambio de
	# defecto del motor no tiene por qué apagarle la sombra al pueblo.
	lines.append("gi_mode = 1")
	lines.append("cast_shadow = 1")
	if not is_building:
		lines.append("visibility_range_end = %.1f" % PROP_VISIBILITY_RANGE_END)
		# 1 = VISIBILITY_RANGE_FADE_SELF.
		lines.append("visibility_range_fade_mode = 1")
	lines.append("mesh = ExtResource(\"1_mesh\")")
	if shape != "none":
		lines.append("")
		lines.append("[node name=\"IntactShape\" type=\"CollisionShape3D\" parent=\".\"]")
		lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s)"
				% _components_text(bounds.get_center()))
		lines.append("shape = SubResource(\"BoxShape3D_intact\")")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("build_town_props: no se pudo escribir '%s'" % path)
		return
	file.store_string("
".join(lines) + "
")
	file.close()


## `Vector3(1.5, 2, 3)` con los decimales recortados al milímetro, que es la
## precisión con la que se declara todo en el manifiesto.
func _vector_text(value: Vector3) -> String:
	return "Vector3(%s)" % _components_text(value)


func _components_text(value: Vector3) -> String:
	return "%s, %s, %s" % [_number_text(value.x), _number_text(value.y),
			_number_text(value.z)]


func _number_text(value: float) -> String:
	var text := "%.4f" % snappedf(value, 0.0001)
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text += "0"
	return text


# --------------------------------------------------------------------------
# Manifiesto
# --------------------------------------------------------------------------

## Escribe `assets/town/pieces_manifest.json` con **todo** el pueblo: las piezas
## de este script más las de los cuatro packs, leídas de sus sidecars.
##
## Es el único archivo que WP-D2 tiene que mirar para saber qué piezas existen,
## de qué clase son, cuánto miden y dónde está su escena.
func _write_manifest() -> void:
	var sidecars := _sidecar_paths()
	for path: String in sidecars:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var sidecar := parsed as Dictionary
		if sidecar == null:
			push_error("build_town_props: '%s' no es un objeto JSON válido" % path)
			continue
		var source := String(sidecar.get("name", path.get_file()))
		var pieces := sidecar.get("pieces", {}) as Dictionary
		for name: String in pieces:
			var entry := pieces[name] as Dictionary
			if _manifest.has(name):
				push_error("build_town_props: '%s' está en el manifiesto y en '%s'"
						% [name, path])
				continue
			var size := entry.get("size", [0.0, 0.0, 0.0]) as Array
			var kind := String(entry.get("kind", "prop"))
			_manifest[name] = {
				"class": "building" if kind == "house" else kind,
				"scene": String(entry.get("scene", "")),
				"footprint": [snappedf(float(size[0]), 0.001),
						snappedf(float(size[2]), 0.001)],
				"height": snappedf(float(size[1]), 0.001),
				"origin": "start_x" if String(entry.get("origin", "centre")) == "start_x"
						else "base_centre",
				"front": _front_of(name),
				"source": source,
				"placeholder": false,
				"tris": int(entry.get("triangles", 0)),
				"shape": "none" if kind == "foliage" else
						("box" if kind == "house" else "convex"),
				"surfaces": 1,
			}

	var ordered: Dictionary = {}
	var names := PackedStringArray(_manifest.keys())
	names.sort()
	for name: String in names:
		ordered[name] = _manifest[name]

	var document := {
		"version": 1,
		"comment": [
			"Indice de todas las piezas del pueblo de ruta (WP-D1).",
			"Lo escribe tools/build_town_props.gd fundiendo sus piezas procedurales",
			"con los sidecars <pack>.pieces.json de assets/town/.",
			"front '-X' es la convencion REAL del pueblo: la puerta de house_a esta",
			"en su cara -X y CityGrid le suma TOWN_YAW_OFFSET = -90 grados a toda",
			"pieza con el metadato town_kind. El encargo pedia -Z; manda la real.",
			"front '+X-run' es una pieza de TRAMO -cercos y tablero de puente-: no",
			"tiene frente, corre a lo largo de su +X, y CityGrid no le suma nada.",
			"origin 'base_centre' es centro de la base a y=0; 'start_x' es extremo",
			"inicial del tramo; 'deck_top_centre' deja la cara superior en y=0.",
		],
		"pieces": ordered,
	}
	var text := JSON.stringify(document, "\t", true, false)
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		push_error("build_town_props: no se pudo escribir '%s'" % MANIFEST_PATH)
		return
	file.store_string(text + "\n")
	file.close()
	print("  guardado %s (%d piezas)" % [MANIFEST_PATH, ordered.size()])


## Hacia dónde mira [param piece] en su espacio local.
##
## Casi todo el pueblo mira a `-X` —es la convención real del pack Nuke y de los
## procedurales— y [method CityGrid._piece_yaw_offset] le suma por eso un cuarto
## de vuelta al giro que el diseño declara. Las **piezas de tramo** son la
## excepción: un cerco o el tablero de un puente no tienen frente, tienen
## **recorrido**, y su `+X` ya es el rumbo del tramo. Marcarlas `"+X-run"`
## (WP-D4a, hallazgo 19) hace que esa excepción viva en el dato y no en que
## nadie se acuerde de no sembrarlas como props sueltos.
func _front_of(piece: String) -> String:
	return "+X-run" if RUN_PIECES.has(piece) else "-X"


## Piezas que corren a lo largo de su `+X` en vez de tener frente. Ver
## [method _front_of].
const RUN_PIECES: Array[String] = [
	"fence_picket_3m", "fence_post", "fence_wire_6m", "bridge_deck",
]


## Los sidecars de `assets/town/`, en orden alfabético.
func _sidecar_paths() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(TOWN_DIR)
	if dir == null:
		push_error("build_town_props: no se pudo abrir '%s'" % TOWN_DIR)
		return found
	for file_name: String in dir.get_files():
		if file_name.ends_with(".pieces.json"):
			found.append("%s/%s" % [TOWN_DIR, file_name])
	found.sort()
	return found


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Las cuatro UV de una celda del atlas, en el orden de los vértices de
## [method Builder.quad] (abajo-izquierda, abajo-derecha, arriba-derecha,
## arriba-izquierda). La V del atlas crece hacia abajo, así que la fila de abajo
## del cartel es `v = 1`.
func _cell_rect(cell: String) -> Array[Vector2]:
	return [_cell_uv(cell, 0.0, 1.0), _cell_uv(cell, 1.0, 1.0),
			_cell_uv(cell, 1.0, 0.0), _cell_uv(cell, 0.0, 0.0)]


func _triangle_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_INDEX] == null:
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			total += vertices.size() / 3
			continue
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if indices.is_empty():
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			total += vertices.size() / 3
		else:
			total += indices.size() / 3
	return total


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("build_town_props: no se pudo crear '%s': %s"
				% [path, error_string(err)])


func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("build_town_props: no se pudo guardar '%s': %s"
				% [path, error_string(err)])
