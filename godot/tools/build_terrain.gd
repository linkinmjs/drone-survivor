## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Hornea el relieve del pueblo (`docs/10` §4.4, plan P2c §2, WP-T2).
##
## Produce, en una sola corrida y de forma **determinista byte a byte**:
##
## - `assets/city/terrain/town_a_terrain.res` — el [TownTerrain]: rejilla de
##   513 × 513 alturas a un metro, ±256 m alrededor del pueblo.
## - `assets/city/terrain/town_a_collision.res` — el [HeightMapShape3D] con esa
##   misma rejilla, para el `StaticBody3D` del suelo.
## - `assets/city/terrain/town_a_chunk_{0..3}.res` — cuatro [ArrayMesh] de
##   260 m de lado, con color de capa por vértice.
## - `assets/city/materials/terrain.tres` — el [ShaderMaterial] de
##   `city/terrain.gdshader`.
##
## Uso, desde la raíz del repositorio:
## [codeblock]
## godot --headless --path godot -s res://tools/build_terrain.gd
## godot --headless --path godot -s res://tools/build_terrain.gd -- --design=res://city/designs/town_a.json
## godot --headless --path godot -s res://tools/build_terrain.gd -- --probe
## [/codeblock]
##
## ## Cómo se compone la altura
##
## [codeblock]
## h = lerp(h_noise, h_datum, mask) * (1 - smoothstep(fade0, fade1, r))
## [/codeblock]
##
## - **`h_noise`** es el campo: dos [FastNoiseLite] —lomas de ~120 m y ±3,5 m,
##   grano de 25 m y ±0,6 m— menos el canal del arroyo, tallado por distancia
##   a su polilínea con bancos de nueve metros.
## - **`h_datum`** es la **cota civil**: el perfil longitudinal de la ruta,
##   suave y de pendiente acotada, **constante dentro de cada manzana** (la cota
##   de su baricentro) e interpolado a través del corredor de calles.
## - **`mask`** vale 1 sobre la ruta, las calles y las manzanas, y se desvanece
##   con un `smoothstep` de doce metros hacia el campo.
##
## De ahí salen las tres propiedades que hacen jugable un pueblo sobre terreno
## irregular: las manzanas quedan **planas y a una sola cota** (una casa apoya
## en sus cuatro esquinas sin flotar ni enterrarse), las calles tienen
## **pendiente acotada** (ni el dron ni el jefe trepan escalones) y el campo de
## alrededor ondula sin que nada de eso lo toque. Y como el arroyo vive en
## `h_noise`, donde la ruta cruza el cauce la máscara lo borra sola: el lecho
## baja a los lados y la calzada del puente sigue plana, sin un caso especial.
##
## ## Por qué el trabajo va en `_initialize()` y el plano es `Variant`
##
## La misma razón que anota `tools/build_town.gd`: con `-s`, Godot compila el
## script del bucle principal **antes** de dar de alta los autoload, y
## [TownPlan] lee `Global.round_seed` en `dark_blocks()`. Nombrar el tipo
## obligaría a compilar esa cadena demasiado temprano y el arranque fallaría con
## «Identifier not found: Global». Así que el plano se carga con `load()` ya
## dentro de [method _initialize] y se declara `Variant`, con despacho dinámico.
##
## [TownTerrain], en cambio, sí se nombra: es un [Resource] de datos puros que
## no toca ningún autoload, y tipar la rejilla importa porque [method
## TownTerrain.height_at] se llama medio millón de veces por chunk.
##
## ## Por qué el horneado y no ruido en runtime
##
## Lo explica [TownTerrain]. Acá basta con la consecuencia práctica: este script
## es el **único** lugar del proyecto donde se evalúa ruido de terreno, y corre
## a mano. Lo que se comitea es el resultado.
extends SceneTree

const TERRAIN_DIR: String = "res://assets/city/terrain"
const MATERIAL_DIR: String = "res://assets/city/materials"
const SHADER_PATH: String = "res://city/terrain.gdshader"
const MATERIAL_PATH: String = "res://assets/city/materials/terrain.tres"
const TERRAIN_PATH: String = "res://assets/city/terrain/town_a_terrain.res"
const COLLISION_PATH: String = "res://assets/city/terrain/town_a_collision.res"
const CHUNK_PATH: String = "res://assets/city/terrain/town_a_chunk_%d.res"
const PLANNER_SCRIPT: String = "res://city/town_planner.gd"
const DESIGN_SCRIPT: String = "res://city/town_design.gd"

## Diseño del que se leen `terrain`, `creek` y `bridge` cuando no se pasa
## `--design`. Es **el mismo archivo** que resuelve `TownPlanner` (WP-T3), y por
## eso es el defecto y no el diccionario de abajo: si el terreno hornease su
## propio arroyo mientras el plano resuelve otro, el puente quedaría sobre tierra
## firme y nadie se enteraría hasta verlo.
const DEFAULT_DESIGN: String = "res://city/designs/town_a.json"

## Lado de la rejilla, en muestras, y su paso. Cuadrada y a un metro porque es
## lo único que Jolt acepta sin degradar el heightfield a una malla de colisión.
const GRID_SIZE: int = 513
const GRID_CELL: float = 1.0

## Spec de reserva, con **la misma estructura** que las claves `terrain`,
## `creek` y `bridge` de [constant DEFAULT_DESIGN]. Sólo se usa entero si ese
## archivo no existe; en condiciones normales el diseño lo pisa clave por clave.
##
## `creek.polyline` vacío significa «derivá el arroyo del plano»: el diseño
## definitivo lo escribe el orquestador en la tanda 2, y hasta entonces el
## andamio necesita un cauce que dependa de la ruta y no de coordenadas
## copiadas a mano que se desincronizarían con el primer cambio de plano.
## `bridge.at` vacío significa «donde el cauce cruce el eje de la ruta».
const DEFAULT_SPEC: Dictionary = {
	"terrain": {
		"seed": 4711,
		"hills": {"wavelength": 120.0, "amplitude": 3.5},
		"grain": {"wavelength": 25.0, "amplitude": 0.6},
		"fade": [200.0, 256.0],
		"route_grade_max": 0.02,
		"mask_feather": 12.0,
	},
	"creek": {
		"polyline": [],
		"width": 6.0,
		"depth": 2.4,
		"bank": 9.0,
	},
	"bridge": {
		"at": [],
		"span": 16.0,
		"deck_width": 12.0,
	},
}

## Holgura de la máscara más allá de la línea municipal, en metros: cuatro sobre
## la banquina de la ruta y sobre la manzana, tres sobre la vereda de calle. Es
## el margen que la cinta de asfalto de WP-T1 necesita para apoyar sin que el
## ruido le muerda el borde.
const ROUTE_MARGIN: float = 4.0
const STREET_MARGIN: float = 3.0
const BLOCK_MARGIN: float = 4.0

## Ancho de la transición de la cota civil desde el borde de una manzana hacia
## el eje del corredor, en metros.
##
## Tiene que ser **menor que la media franja de la calle más angosta** (7 m: 8 m
## de calzada y 3 de vereda). Si fuera mayor, sobre el eje del corredor pesarían
## las dos manzanas de enfrente a la vez y, como cuál de las dos es «la más
## cercana» se decide justo ahí, la cota daría un salto en la línea media de
## cada calle. Con 6,5 m el peso de la manzana ya es cero antes del eje y el
## corredor cae limpio sobre el perfil de la ruta.
const DATUM_BLEND: float = 6.5

## Longitudes de onda y pesos del perfil longitudinal de la ruta, en metros.
## Tres senos de baja frecuencia: ni una loma repetida ni una recta.
const PROFILE_WAVES: Array[float] = [520.0, 330.0, 190.0]
const PROFILE_WEIGHTS: Array[float] = [0.55, 0.30, 0.15]

## Paso de la malla visible dentro y fuera del disco del pueblo, en metros. El
## medio lado del cuadrado refinado no es constante: sale de [method
## _refine_reach], que lo lee del plano resuelto.
const CHUNK_STEP_NEAR: float = 2.0
const CHUNK_STEP_FAR: float = 4.0

## Cuánto se refina más allá del disco de manzanas, en metros.
const CHUNK_REFINE_MARGIN: float = 40.0

## Medio lado de la tanda de cuatro chunks, en metros: 2 × 2 de 260 m.
const CHUNK_REACH: float = 260.0

## Pendientes, en radianes, entre las que la capa de roca sube de 0 a 1.
## Rol `TownPlan.Role.DECOR`, escrito como literal.
##
## `tools/build_terrain.gd` corre con `-s` y no puede nombrar a [TownPlan]: el
## analizador lo compilaría antes de que existan los autoload y el arranque
## moriría con «Identifier not found: Global». Es el mismo motivo por el que
## [TownPlanner] se carga con `load()`.
const DECOR_ROLE: int = 4

## Pad de casa de caserío: cuánto sobresale el disco plano de la huella y con
## cuántos metros de desvanecido termina contra el campo.
##
## Las doce casas de caserío están en pleno campo y no tienen manzana de la que
## tomar la cota: sin un pad debajo, sus cuatro esquinas caen sobre el ruido y
## la casa queda con una esquina enterrada y la opuesta en el aire —medido sobre
## el primer horneado: de 7 cm a **2,50 m** de desnivel bajo una misma huella.
##
## El desvanecido **no es fijo**. Con 6 m para todas, la casa que está sobre la
## ladera de 23 % tendría que recuperar tres metros y medio en seis, o sea un
## talud de 85 cm por metro: el doble del escalón que `terrain_check` tolera
## (58 cm/m, 30°). El ancho se deduce entonces del desnivel que el pad tiene que
## recuperar —[constant PAD_FEATHER_GAIN] metros por metro— con un piso de 6 m
## para las nueve casas que están casi a nivel y un techo de 24 m para que el
## pad de la peor no se coma el campo entero.
const PAD_MARGIN: float = 2.0

## Margen mínimo, en metros. El relieve se muestrea con una rejilla de un metro
## y `height_at` interpola bilineal: una esquina de huella que cae **sobre** el
## borde del núcleo plano se interpola con un nodo de rejilla de afuera y sale
## desviada lo que el terreno baje en ese metro —medido, 26 mm en la peor casa,
## contra un tope de 20. Con un metro de margen las cuatro muestras que rodean a
## la esquina están adentro del núcleo y la cuenta es exacta.
const PAD_MARGIN_MIN: float = 1.0
const PAD_FEATHER_MIN: float = 6.0
const PAD_FEATHER_MAX: float = 24.0
const PAD_FEATHER_GAIN: float = 6.0

## Anillos y sectores con los que se mide el desnivel bajo un pad.
const PAD_RINGS: int = 3
const PAD_SECTORS: int = 24

## Escalón, en metros, por debajo del cual dos pads vecinos no se estorban.
##
## Dos plataformas a distinta cota tienen que quedar **separadas**: si sus
## taludes se tocan, el punto donde una deja de mandar y empieza la otra es un
## escalón vertical de la diferencia de cotas. La regla es entonces simple: cada
## talud llega a lo sumo hasta la mitad del terreno natural que queda entre los
## dos núcleos, así que los dos mueren antes de encontrarse y entre las dos
## terrazas queda campo. Cuando ni eso alcanza —porque entre las dos casas hay
## menos de [constant PAD_FEATHER_HARD] metros por lado— no hay dos terrazas que
## valgan y las casas comparten una, con la cota promedio: es lo que hace un
## loteo de verdad, una quinta con dos casas tiene **una** terraza.
const PAD_JOIN_STEP: float = 0.05
const PAD_JOIN_SAMPLES: int = 129
const PAD_JOIN_PASSES: int = 6

## Paso con el que se muestrea la geometría que los pads no pueden pisar.
const PROTECT_STEP: float = 2.0

## Talud mínimo irreducible, en metros. Por debajo de esto el desvanecido deja
## de ser un talud y pasa a ser un escalón.
const PAD_FEATHER_HARD: float = 2.0

## Campo, en metros, por debajo del cual dos casas de caserío a distinta cota
## comparten terraza.
##
## Diez metros no es una distancia elegida a ojo: es el orden del talud que un
## pad necesita cuando el terreno natural le varía un metro y medio bajo la
## huella —que es lo que pasa en el caserío del este—, y dos taludes de diez
## metros no entran en menos de veinte. Por debajo de eso las dos casas están en
## la misma quinta y el terreno lo dice.
const PAD_JOIN_GAP: float = 10.0

const ROCK_SLOPE_MIN: float = 0.30  # ~17°
const ROCK_SLOPE_MAX: float = 0.60  # ~34°

## Pendientes entre las que el pasto empieza a pelarse a tierra.
const DIRT_SLOPE_MIN: float = 0.12  # ~7°
const DIRT_SLOPE_MAX: float = 0.30  # ~17°

## Peso de tierra que aporta la máscara de lo urbanizado. Ver [method _layer_color].
const CIVIL_DIRT: float = 0.33


# --------------------------------------------------------------------------
# Compositor
# --------------------------------------------------------------------------

## Evalúa la altura en cualquier punto XZ a partir del plano y del spec.
##
## Vive en una clase y no en funciones sueltas porque hay bastante que
## precomputar —las polilíneas en XZ, las cotas de manzana, los círculos
## envolventes— y rehacerlo por punto sobre 263 169 puntos sería media hora de
## horneado. Por la misma razón la geometría de polígonos se reimplementa acá
## en vez de llamar a [TownPlan]: son quince líneas, evitan un despacho dinámico
## por muestra y dejan al compositor sin dependencias de compilación. Que las
## dos implementaciones coincidan no se confía: `tools/terrain_check.gd` mide el
## terreno con las utilidades **de verdad** del plano, así que cualquier
## divergencia sale en rojo.
class Composer extends RefCounted:
	var plan: Variant = null

	var hills: FastNoiseLite = FastNoiseLite.new()
	var grain: FastNoiseLite = FastNoiseLite.new()
	var hills_amplitude: float = 0.0
	var grain_amplitude: float = 0.0

	var centre: Vector2 = Vector2.ZERO
	var fade_start: float = 200.0
	var fade_end: float = 256.0
	var feather: float = 12.0

	## Ruta y calles en XZ, con sus longitudes acumuladas y su media franja.
	var route: PackedVector2Array = PackedVector2Array()
	var route_arcs: PackedFloat32Array = PackedFloat32Array()
	var route_half: float = 8.0
	var route_centre_arc: float = 0.0
	var streets: Array[PackedVector2Array] = []
	var street_halves: PackedFloat32Array = PackedFloat32Array()
	var street_bounds: Array[Vector3] = []  # (centro.x, centro.z, radio)

	## Manzanas: polígono, círculo envolvente y cota civil.
	var blocks: Array[PackedVector2Array] = []
	var block_bounds: Array[Vector3] = []
	var block_datum: PackedFloat32Array = PackedFloat32Array()

	## Perfil longitudinal.
	var profile_amplitude: float = 0.0
	var profile_phases: PackedFloat32Array = PackedFloat32Array()

	## Arroyo.
	var creek: PackedVector2Array = PackedVector2Array()
	var creek_width: float = 6.0
	var creek_depth: float = 2.4
	var creek_bank: float = 9.0

	## Pads de las casas de caserío, uno por casa y en el mismo orden: centro,
	## dirección de su frente, medias medidas del núcleo plano (a lo largo y a
	## lo ancho), desvanecido y cota.
	var pad_centre: PackedVector2Array = PackedVector2Array()
	var pad_axis: PackedVector2Array = PackedVector2Array()
	var pad_half: PackedVector2Array = PackedVector2Array()
	var pad_feather: PackedFloat32Array = PackedFloat32Array()
	var pad_datum: PackedFloat32Array = PackedFloat32Array()


	func setup(town: Variant, spec: Dictionary) -> void:
		plan = town
		var terrain_spec: Dictionary = spec.get("terrain", {})
		var creek_spec: Dictionary = spec.get("creek", {})

		var play_centre: Vector3 = town.play_centre
		centre = Vector2(play_centre.x, play_centre.z)
		var fade: Array = terrain_spec.get("fade", [200.0, 256.0])
		fade_start = float(fade[0])
		fade_end = float(fade[1])
		feather = float(terrain_spec.get("mask_feather", 12.0))

		var noise_seed := int(terrain_spec.get("seed", 4711))
		var hills_spec: Dictionary = terrain_spec.get("hills", {})
		var grain_spec: Dictionary = terrain_spec.get("grain", {})
		hills_amplitude = float(hills_spec.get("amplitude", 3.5))
		grain_amplitude = float(grain_spec.get("amplitude", 0.6))
		_setup_noise(hills, noise_seed, float(hills_spec.get("wavelength", 120.0)))
		_setup_noise(grain, noise_seed + 1, float(grain_spec.get("wavelength", 25.0)))

		var route_line: PackedVector3Array = town.route
		route = _flatten(route_line)
		route_arcs = _arcs(route)
		route_half = float(town.route_width) * 0.5 + float(town.route_shoulder)
		route_centre_arc = _arc_of(route, route_arcs, centre)

		var street_count: int = town.street_count()
		for index: int in street_count:
			var line: PackedVector3Array = town.street_axis(index + 1)
			var axis := _flatten(line)
			streets.append(axis)
			street_halves.append(float(town.street_half_of(index + 1)))
			street_bounds.append(_bounds_of(axis))

		_setup_profile(noise_seed, float(terrain_spec.get("route_grade_max", 0.02)))

		var block_count: int = town.block_count()
		for index: int in block_count:
			var polygon: PackedVector2Array = town.block_polygon(index)
			blocks.append(polygon)
			block_bounds.append(_bounds_of(polygon))
			var centroid: Vector3 = town.block_centroid(index)
			block_datum.append(profile(_arc_of(route, route_arcs,
					Vector2(centroid.x, centroid.z))))

		creek_width = float(creek_spec.get("width", 6.0))
		creek_depth = float(creek_spec.get("depth", 2.4))
		creek_bank = float(creek_spec.get("bank", 9.0))


	static func _setup_noise(noise: FastNoiseLite, noise_seed: int, wavelength: float) -> void:
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.seed = noise_seed
		noise.frequency = 1.0 / maxf(wavelength, 0.01)


	## Amplitud y fases del perfil. La amplitud se deduce del gradiente máximo
	## pedido: la derivada de una suma está acotada por la suma de las
	## derivadas, así que se escala para que el peor caso sea exactamente
	## `grade_max` y el pueblo entero quede por debajo del 2 %.
	func _setup_profile(noise_seed: int, grade_max: float) -> void:
		var derivative := 0.0
		for index: int in PROFILE_WAVES.size():
			derivative += TAU * PROFILE_WEIGHTS[index] / PROFILE_WAVES[index]
		profile_amplitude = grade_max / maxf(derivative, 0.000001)
		for index: int in PROFILE_WAVES.size():
			# Fases deterministas: la misma semilla da el mismo perfil siempre,
			# y dos semillas distintas dan dos pueblos con lomas distintas.
			profile_phases.append(TAU * _unit(_mix(noise_seed ^ _mix(index + 17))))


	## Perfil longitudinal de la ruta a [param arc] metros de su primer vértice,
	## medido desde el arco del centro del pueblo.
	func profile(arc: float) -> float:
		var s := arc - route_centre_arc
		var value := 0.0
		for index: int in PROFILE_WAVES.size():
			value += PROFILE_WEIGHTS[index] * sin(TAU * s / PROFILE_WAVES[index]
					+ profile_phases[index])
		return profile_amplitude * value


	# ----------------------------------------------------------------------
	# Campos
	# ----------------------------------------------------------------------

	## Manzana más cercana a [param p] y su inset, como `Vector2(índice, inset)`.
	## El índice es `-1` si ninguna queda a tiro.
	func nearest_block(p: Vector2) -> Vector2:
		var best := -1
		var best_inset := -INF
		for index: int in blocks.size():
			var bound := block_bounds[index]
			var reach := bound.z + DATUM_BLEND + feather + BLOCK_MARGIN
			if p.distance_squared_to(Vector2(bound.x, bound.y)) > reach * reach:
				continue
			var inset := _inset(blocks[index], p)
			if inset > best_inset:
				best_inset = inset
				best = index
		return Vector2(float(best), best_inset)


	## Cota civil en [param p]: constante dentro de cada manzana y del perfil de
	## la ruta sobre el eje de cada corredor.
	func datum(p: Vector2, block: Vector2) -> float:
		var index := int(block.x)
		if index >= 0 and block.y >= 0.0:
			return block_datum[index]
		var base := profile(_arc_of(route, route_arcs, p))
		if index < 0:
			return base
		var weight := clampf(1.0 + block.y / DATUM_BLEND, 0.0, 1.0)
		return lerpf(base, block_datum[index], weight)


	## Máscara civil en [param p]: 1 sobre la ruta, las calles y las manzanas,
	## desvanecida con un `smoothstep` de [member feather] metros hacia afuera.
	##
	## Las bandas se combinan con la unión probabilística `1 − Π(1 − bᵢ)` y no
	## con un `max`. Las dos dan 1 donde alguna banda vale 1 —que es la garantía
	## que importa: manzana plana y calle a cota—, pero el `max` de dos funciones
	## suaves tiene un **pliegue** donde se cruzan, y ese pliegue se hereda a la
	## altura: en el primer horneado dejaba una arruga de 22 cm por metro en el
	## borde del pueblo, visible como una línea recta en el pasto. La unión
	## probabilística es derivable donde lo son sus términos, así que el empalme
	## entre lo urbanizado y el campo sale liso.
	func mask(p: Vector2, block: Vector2) -> float:
		var value := _band(_distance(route, p), route_half + ROUTE_MARGIN, feather)
		if value >= 1.0:
			return 1.0
		for index: int in streets.size():
			var bound := street_bounds[index]
			var reach := bound.z + street_halves[index] + STREET_MARGIN + feather
			if p.distance_squared_to(Vector2(bound.x, bound.y)) > reach * reach:
				continue
			var band := _band(_distance(streets[index], p),
					street_halves[index] + STREET_MARGIN, feather)
			if band >= 1.0:
				return 1.0
			value = 1.0 - (1.0 - value) * (1.0 - band)
		if int(block.x) >= 0:
			var band := _band(-block.y, BLOCK_MARGIN, feather)
			if band >= 1.0:
				return 1.0
			value = 1.0 - (1.0 - value) * (1.0 - band)
		return clampf(value, 0.0, 1.0)


	## Distancia de [param p] al eje del arroyo, o `INF` si no hay arroyo.
	func creek_distance(p: Vector2) -> float:
		if creek.size() < 2:
			return INF
		return _distance(creek, p)


	## Campo sin urbanizar: lomas, grano y el canal del arroyo.
	func noise_height(p: Vector2) -> float:
		var value := hills_amplitude * hills.get_noise_2d(p.x, p.y) \
				+ grain_amplitude * grain.get_noise_2d(p.x, p.y)
		var distance := creek_distance(p)
		if distance < creek_bank:
			value -= creek_depth * (1.0 - smoothstep(creek_width * 0.5, creek_bank, distance))
		return value


	## Factor de desvanecido global hacia el plano lejano, por radio.
	func fade(p: Vector2) -> float:
		return 1.0 - smoothstep(fade_start, fade_end, p.distance_to(centre))


	## Altura **antes** de los pads y del desvanecido: campo, ruta, calles y
	## manzanas, que es la composición de `h = lerp(h_ruido, h_cota, máscara)`.
	func base_height(p: Vector2) -> float:
		var block := nearest_block(p)
		var civil := mask(p, block)
		if civil >= 1.0:
			return datum(p, block)
		if civil <= 0.0:
			return noise_height(p)
		return lerpf(noise_height(p), datum(p, block), civil)


	## Distancia de [param p] al borde del núcleo del pad [param index]: negativa
	## adentro, positiva afuera.
	##
	## El núcleo es la **huella de la casa** crecida [constant PAD_MARGIN] metros
	## —un rectángulo, no un disco—, y la diferencia no es cosmética. Tres de las
	## doce casas de caserío están a ocho metros del eje de su calle, o sea con
	## la vereda pegada al frente: el disco circunscripto a esa huella mide 7,5 m
	## de radio y le entraba a la calzada por setenta centímetros, así que el pad
	## aplanaba la calle. El rectángulo llega 4,7 m hacia el lado y deja la
	## calzada afuera.
	func pad_distance(index: int, p: Vector2) -> float:
		var local := p - pad_centre[index]
		var axis := pad_axis[index]
		var half := pad_half[index]
		var q := Vector2(absf(local.dot(axis)) - half.x,
				absf(local.dot(Vector2(-axis.y, axis.x))) - half.y)
		return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


	## Peso del pad [param index] en [param p]: 1 sobre su núcleo, desvanecido
	## hacia afuera.
	func pad_band(index: int, p: Vector2) -> float:
		return _band(maxf(pad_distance(index, p), 0.0), 0.0, pad_feather[index])


	## Pad que manda en [param p] y con cuánto peso, como `Vector2(índice, peso)`.
	## Sin pad a tiro devuelve `(-1, 0)`.
	##
	## Se elige por **peso máximo** y no por promedio: sobre el núcleo de un pad
	## su peso vale exactamente 1 y gana siempre, que es lo único que garantiza
	## que la huella salga plana al milímetro. Dos pads que se pisan comparten
	## cota (los funde [method _merge_pads]), así que el desempate no cambia
	## nada.
	func pad_weight(p: Vector2) -> Vector2:
		var best := -1
		var best_weight := 0.0
		for index: int in pad_centre.size():
			var reach := pad_half[index].length() + pad_feather[index]
			if p.distance_squared_to(pad_centre[index]) > reach * reach:
				continue
			var weight := pad_band(index, p)
			if weight > best_weight:
				best_weight = weight
				best = index
		return Vector2(float(best), best_weight)


	## Altura compuesta en [param p]. Es la función que define el terreno.
	##
	## Los pads de caserío se aplican **después** de la composición civil y no
	## como una banda más de la máscara, y la diferencia importa: una banda más
	## habría hecho que el pad decidiera también la cota de la calle o de la ruta
	## que le pasa cerca —tres de las doce casas están a un metro del corredor de
	## su calle y otra a dos de la banquina de la ruta—, y el pueblo habría
	## quedado con cuatro mesetas encima del viario. Aplicado encima, el pad
	## aplana lo que haya debajo y su cota **es** la que ese punto ya tenía, así
	## que contra una calle el escalón es el que el perfil da en catorce metros
	## (≤ 2 %) y en pleno campo es la terraza que una casa rural necesita.
	func height(p: Vector2) -> float:
		var attenuation := fade(p)
		if attenuation <= 0.0:
			return 0.0
		var value := base_height(p)
		var pad := pad_weight(p)
		if pad.x >= 0.0 and pad.y > 0.0:
			value = lerpf(value, pad_datum[int(pad.x)], pad.y)
		return value * attenuation


	# ----------------------------------------------------------------------
	# Geometría
	# ----------------------------------------------------------------------

	static func _band(distance: float, inner: float, width: float) -> float:
		if distance <= inner:
			return 1.0
		if width <= 0.0:
			return 0.0
		return 1.0 - smoothstep(inner, inner + width, distance)


	static func _flatten(line: PackedVector3Array) -> PackedVector2Array:
		var flat := PackedVector2Array()
		for point: Vector3 in line:
			flat.append(Vector2(point.x, point.z))
		return flat


	## Longitudes acumuladas de una polilínea, una por vértice.
	static func _arcs(line: PackedVector2Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var total := 0.0
		out.append(0.0)
		for index: int in maxi(line.size() - 1, 0):
			total += line[index].distance_to(line[index + 1])
			out.append(total)
		return out


	## Centro y radio del círculo envolvente de una polilínea o un polígono,
	## como `Vector3(x, z, radio)`.
	static func _bounds_of(points: PackedVector2Array) -> Vector3:
		if points.is_empty():
			return Vector3.ZERO
		var low := points[0]
		var high := points[0]
		for point: Vector2 in points:
			low = low.min(point)
			high = high.max(point)
		var middle := (low + high) * 0.5
		return Vector3(middle.x, middle.y, (high - low).length() * 0.5)


	## Distancia de [param p] a una polilínea, en XZ.
	static func _distance(line: PackedVector2Array, p: Vector2) -> float:
		var best := INF
		for index: int in maxi(line.size() - 1, 0):
			var a := line[index]
			var delta := line[index + 1] - a
			var span := delta.length_squared()
			if span <= 0.000001:
				continue
			var t := clampf((p - a).dot(delta) / span, 0.0, 1.0)
			best = minf(best, p.distance_to(a + delta * t))
		return best


	## Arco del punto más cercano a [param p] sobre una polilínea.
	static func _arc_of(line: PackedVector2Array, arcs: PackedFloat32Array,
			p: Vector2) -> float:
		var best := 0.0
		var best_distance := INF
		for index: int in maxi(line.size() - 1, 0):
			var a := line[index]
			var delta := line[index + 1] - a
			var span := delta.length_squared()
			if span <= 0.000001:
				continue
			var t := clampf((p - a).dot(delta) / span, 0.0, 1.0)
			var distance := p.distance_squared_to(a + delta * t)
			if distance < best_distance:
				best_distance = distance
				best = arcs[index] + sqrt(span) * t
		return best


	## Distancia de [param p] al lado más cercano de un polígono convexo,
	## positiva hacia adentro. Espejo exacto de `TownPlan.polygon_inset`.
	static func _inset(poly: PackedVector2Array, p: Vector2) -> float:
		var count := poly.size()
		if count < 3:
			return -INF
		var winding := 1.0 if _signed_area(poly) >= 0.0 else -1.0
		var best := INF
		for index: int in count:
			var a := poly[index]
			var delta := poly[(index + 1) % count] - a
			var length := delta.length()
			if length <= 0.000001:
				continue
			var outward := Vector2(delta.y, -delta.x) / length * winding
			best = minf(best, -(p - a).dot(outward))
		return best


	## Muestras equiespaciadas sobre una polilínea, con paso [param step].
	static func _samples_2d(line: PackedVector2Array, step: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for index: int in maxi(line.size() - 1, 0):
			var a := line[index]
			var b := line[index + 1]
			var span := a.distance_to(b)
			var steps := maxi(ceili(span / maxf(step, 0.01)), 1)
			for slot: int in steps + 1:
				out.append(a.lerp(b, float(slot) / float(steps)))
		return out


	static func _signed_area(poly: PackedVector2Array) -> float:
		var total := 0.0
		var count := poly.size()
		for index: int in count:
			var a := poly[index]
			var b := poly[(index + 1) % count]
			total += a.x * b.y - b.x * a.y
		return total * 0.5


	## Normal izquierda unitaria de una dirección en XZ. Espejo de
	## `TownPlan.left_of`.
	static func _left_of(direction: Vector3) -> Vector2:
		var flat := Vector2(direction.x, direction.z)
		if flat.length_squared() < 0.000001:
			return Vector2(-1.0, 0.0)
		flat = flat.normalized()
		return Vector2(flat.y, -flat.x)


	## splitmix64, la mezcla de `TownPlan.mix`.
	static func _mix(value: int) -> int:
		var z := value + -7046029254386353131  # 0x9E3779B97F4A7C15
		z = (z ^ (z >> 30)) * -4658895280553007687  # 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) * -7723592293110705685  # 0x94D049BB133111EB
		return z ^ (z >> 31)


	static func _unit(key: int) -> float:
		return float((_mix(key) >> 11) & 0x1FFFFFFFFFFFFF) / float(0x20000000000000)


var _spec: Dictionary = {}
var _plan: Variant = null
var _composer: Composer = Composer.new()
var _terrain: TownTerrain = null
## Máscara, distancia al arroyo y cota civil por muestra: las necesita el color
## de capa de los chunks, y recalcularlas sería un segundo horneado entero.
var _mask_grid: PackedFloat32Array = PackedFloat32Array()
var _creek_grid: PackedFloat32Array = PackedFloat32Array()
var _datum_grid: PackedFloat32Array = PackedFloat32Array()
## A qué plataforma pertenece cada pad de caserío. Lo llena
## [method _merge_pads] y lo lee el informe.
var _pad_group: PackedInt32Array = PackedInt32Array()

## Geometría intocable para los pads: bordes de calzada y lados de manzana
## ([member _no_flat]), ejes del viario y lados de manzana ([member _keep_level]).
var _no_flat: PackedVector2Array = PackedVector2Array()
var _keep_level: PackedVector2Array = PackedVector2Array()


func _initialize() -> void:
	var args := _user_args()
	_spec = _load_spec(String(args.get("design", "")))

	var planner: Variant = load(PLANNER_SCRIPT)
	if planner == null:
		push_error("build_terrain: no se pudo cargar %s" % PLANNER_SCRIPT)
		quit(1)
		return
	var town_seed: int = planner.TOWN_SEED
	_plan = planner.generate(town_seed)
	if _plan == null:
		push_error("build_terrain: TownPlanner.generate() no devolvió un plano")
		quit(1)
		return
	_composer.setup(_plan, _spec)
	_resolve_creek()
	# Después del arroyo: la cota de un pad es la altura que ese punto ya tenía,
	# y el cauce forma parte de ella.
	_setup_pads()

	if args.has("probe"):
		_probe()
		quit(0)
		return

	_ensure_dir(TERRAIN_DIR)
	_ensure_dir(MATERIAL_DIR)

	var started := Time.get_ticks_msec()
	_bake_grid()
	print("  rejilla horneada en %.1f s" % (float(Time.get_ticks_msec() - started) / 1000.0))

	_save(_terrain, TERRAIN_PATH)
	_save(_terrain.build_shape(), COLLISION_PATH)

	# El material se guarda **antes** que las mallas y se recarga desde disco:
	# así las cuatro lo referencian como recurso externo en vez de incrustar una
	# copia cada una, que serían cuatro materiales y cuatro lotes de dibujo.
	_save(_build_material(), MATERIAL_PATH)
	var material := ResourceLoader.load(MATERIAL_PATH, "ShaderMaterial",
			ResourceLoader.CACHE_MODE_REPLACE) as ShaderMaterial
	if material == null:
		push_error("build_terrain: no se pudo recargar %s" % MATERIAL_PATH)
		quit(1)
		return

	_build_chunks(material)
	_report()
	print("build_terrain: listo.")
	quit(0)


# --------------------------------------------------------------------------
# Spec
# --------------------------------------------------------------------------

## Spec por defecto, o el del JSON de diseño si se pasó `--design=`. Del archivo
## se leen sólo las tres claves que le tocan a este script; el resto lo usa
## `city/town_design.gd` (WP-T3).
func _load_spec(path: String) -> Dictionary:
	var spec := DEFAULT_SPEC.duplicate(true)
	var source := path if not path.is_empty() else DEFAULT_DESIGN
	if not FileAccess.file_exists(source):
		if not path.is_empty():
			push_error("build_terrain: no existe '%s'" % source)
		else:
			print("  sin diseño en %s: se hornea con el spec de reserva" % source)
		return spec
	var text := FileAccess.get_file_as_string(source)
	if text.is_empty():
		push_error("build_terrain: no se pudo leer '%s'" % source)
		return spec
	# El diseño admite comentarios `//` y `/* */` (`TownDesign` §1) y acá se
	# leía crudo: el primer comentario del archivo rompía el parseo, se caía al
	# spec de reserva **sin fallar** y el terreno salía horneado con otro arroyo.
	# Se usa el mismo quitador que el cargador del diseño —cargado con `load()`,
	# que es la regla de este script— para que los dos lean exactamente igual.
	var design_script: Variant = load(DESIGN_SCRIPT)
	var clean := text if design_script == null else String(design_script._strip_comments(text))
	var parsed: Variant = JSON.parse_string(clean)
	if not (parsed is Dictionary):
		push_error("build_terrain: '%s' no contiene un objeto JSON" % source)
		return spec
	var design: Dictionary = parsed
	for key: String in ["terrain", "creek", "bridge"]:
		if design.has(key) and design[key] is Dictionary:
			var section: Dictionary = spec[key]
			section.merge(design[key] as Dictionary, true)
			spec[key] = section
	print("  spec leído de %s" % source)
	return spec


# --------------------------------------------------------------------------
# Arroyo
# --------------------------------------------------------------------------

## Deja el arroyo listo en el compositor y anota en el spec la polilínea y el
## punto de puente que se usaron, para que el `.res` cuente con qué se horneó.
func _resolve_creek() -> void:
	var creek_spec: Dictionary = _spec["creek"]
	var declared: Array = creek_spec.get("polyline", [])
	var line := PackedVector2Array()
	if declared.is_empty():
		line = _scaffold_creek()
	else:
		for entry: Variant in declared:
			var pair: Array = entry
			line.append(Vector2(float(pair[0]), float(pair[1])))
	_composer.creek = line

	var points: Array = []
	for point: Vector2 in line:
		points.append([snappedf(point.x, 0.001), snappedf(point.y, 0.001)])
	creek_spec["polyline"] = points
	_spec["creek"] = creek_spec

	var bridge_spec: Dictionary = _spec["bridge"]
	var declared_at: Array = bridge_spec.get("at", [])
	if declared_at.is_empty():
		var crossing := _creek_route_crossing(line)
		bridge_spec["at"] = [snappedf(crossing.x, 0.001), snappedf(crossing.y, 0.001)]
	_spec["bridge"] = bridge_spec


# --------------------------------------------------------------------------
# Pads de caserío
# --------------------------------------------------------------------------

## Un disco plano bajo cada casa de caserío.
##
## El pad sale del **plano resuelto** y no del JSON: el radio es la media
## diagonal de la huella que `TownPlan.parcel_footprint()` calcula más
## [constant PAD_MARGIN] metros, así que si el diseño cambia el ancho de una
## casa el pad la sigue sin que haya que tocar dos archivos. Lo que se mide y se
## guarda por pad es su cota —la altura compuesta en su centro— y el desvanecido
## que necesita, que sale del desnivel real bajo su disco.
func _setup_pads() -> void:
	_protect_geometry()
	_composer.pad_centre = PackedVector2Array()
	_composer.pad_axis = PackedVector2Array()
	_composer.pad_half = PackedVector2Array()
	_composer.pad_feather = PackedFloat32Array()
	_composer.pad_datum = PackedFloat32Array()
	var base := PackedFloat32Array()
	var parcels: Array = _plan.parcels
	for index: int in parcels.size():
		var parcel: Dictionary = parcels[index]
		if int(parcel.get("role", -1)) != DECOR_ROLE:
			continue
		var position: Vector3 = _plan.parcel_position(index)
		var centre := Vector2(position.x, position.z)
		# El frente de la parcela da la orientación del rectángulo: a lo ancho va
		# la fachada y a lo largo la profundidad de la casa.
		var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
		var across := Vector2(normal.x, normal.z)
		if across.length_squared() < 0.000001:
			across = Vector2(0.0, 1.0)
		across = across.normalized()
		var slot := _composer.pad_centre.size()
		_composer.pad_centre.append(centre)
		_composer.pad_axis.append(Vector2(across.y, -across.x))
		_composer.pad_half.append(Vector2(float(parcel.get("width", 10.0)) * 0.5,
				float(parcel.get("depth", 5.4)) * 0.5))
		_composer.pad_feather.append(PAD_FEATHER_MIN)
		_composer.pad_datum.append(0.0)
		# El margen se recorta contra lo que no se puede aplanar: la casa que está
		# a ocho metros del eje de su calle tiene sitio para 1,3 m de margen y no
		# para los dos declarados, y con los dos el pad le entraba a la calzada.
		var margin := clampf(_pad_reach(slot, _no_flat), PAD_MARGIN_MIN, PAD_MARGIN)
		_composer.pad_half[slot] = _composer.pad_half[slot] + Vector2(margin, margin)
		base.append(_composer.base_height(centre))
	_pad_group = _merge_pads(base)
	_settle_pads(base)


## Reparte los pads en plataformas y devuelve el grupo de cada uno.
##
## Se funden dos pads cuando sus núcleos se pisan —ahí no hay decisión que
## tomar— o cuando el escalón que quedaría entre ellos pasa de
## [constant PAD_JOIN_STEP]. Como fundir cambia la cota y el desvanecido del
## grupo, y eso cambia a su vez qué escalón quedaría contra el vecino de al
## lado, se repite hasta que no se funde nada más (a lo sumo
## [constant PAD_JOIN_PASSES] vueltas; cada vuelta reduce el número de grupos,
## así que termina).
func _merge_pads(base: PackedFloat32Array) -> PackedInt32Array:
	var count := _composer.pad_centre.size()
	var group := PackedInt32Array()
	for index: int in count:
		group.append(index)
	for _pass: int in PAD_JOIN_PASSES:
		_settle_pads(base, group)
		var merged := false
		for a: int in count:
			for b: int in range(a + 1, count):
				if _root(group, a) == _root(group, b):
					continue
				if not _pads_conflict(a, b):
					continue
				var ra := _root(group, a)
				var rb := _root(group, b)
				group[maxi(ra, rb)] = mini(ra, rb)
				merged = true
		for index: int in count:
			group[index] = _root(group, index)
		if not merged:
			break
	return group


## `true` si los pads [param a] y [param b] tienen que ser una sola plataforma:
## cuando sus núcleos se pisan, o cuando entre los dos no queda terreno
## suficiente para dos taludes y las cotas difieren lo bastante como para que se
## note el escalón.
func _pads_conflict(a: int, b: int) -> bool:
	var gap := _pad_gap(a, b)
	if gap <= 0.0:
		return true
	if absf(_composer.pad_datum[a] - _composer.pad_datum[b]) <= PAD_JOIN_STEP:
		return false
	return gap < PAD_JOIN_GAP


## Metros de terreno natural que quedan entre los núcleos de los pads
## [param a] y [param b], medidos sobre el segmento que une sus centros. Cero
## —o menos— significa que se pisan.
func _pad_gap(a: int, b: int) -> float:
	var from := _composer.pad_centre[a]
	var to := _composer.pad_centre[b]
	var span := from.distance_to(to)
	if span <= 0.0:
		return 0.0
	var last_a := 0.0
	var first_b := 1.0
	for step: int in PAD_JOIN_SAMPLES:
		var t := float(step) / float(PAD_JOIN_SAMPLES - 1)
		var p := from.lerp(to, t)
		if _composer.pad_distance(a, p) <= 0.0:
			last_a = maxf(last_a, t)
		if _composer.pad_distance(b, p) <= 0.0:
			first_b = minf(first_b, t)
	return (first_b - last_a) * span


## Cota y desvanecido de cada pad a partir de su grupo.
##
## La **cota** es de la plataforma: el promedio de las alturas naturales de sus
## casas, así que dos casas que comparten terraza quedan a la misma altura y
## entre ellas no hay escalón. El **desvanecido**, en cambio, es de cada
## rectángulo: sale del desnivel que ese rectángulo tiene que recuperar y está
## acotado por el sitio que tiene para hacerlo ([method _pad_room]). Compartir
## también el desvanecido fue el primer intento y salió mal: el pad de la casa
## que está sobre la barranca del arroyo necesita quince metros de talud, y
## dárselos también a su vecina —que está a dieciocho metros de una manzana—
## metía la plataforma **dentro** de la manzana y dejaba la cota municipal con
## 81 mm de desvío y una calle con un 10,4 % de pendiente, el doble del tope.
func _settle_pads(base: PackedFloat32Array, group: PackedInt32Array = PackedInt32Array()) -> void:
	var count := _composer.pad_centre.size()
	var groups := group if group.size() == count else _pad_group
	if groups.size() != count:
		groups = PackedInt32Array()
		for index: int in count:
			groups.append(index)
	var members: Dictionary[int, PackedInt32Array] = {}
	for index: int in count:
		var key := groups[index]
		var list: PackedInt32Array = members.get(key, PackedInt32Array())
		list.append(index)
		members[key] = list
	for key: int in members:
		var datum := _platform_datum(members[key], base)
		for index: int in members[key]:
			_composer.pad_datum[index] = datum
	for index: int in count:
		# El talud nunca pasa de la mitad del campo que queda contra el vecino de
		# otra plataforma: así los dos mueren antes de tocarse y entre las dos
		# terrazas no hay escalón sino terreno.
		var cap := minf(PAD_FEATHER_MAX, _pad_room(index))
		for other: int in count:
			if other == index or groups[other] == groups[index]:
				continue
			if absf(_composer.pad_datum[other] - _composer.pad_datum[index]) <= PAD_JOIN_STEP:
				continue
			cap = minf(cap, maxf(_pad_gap(index, other) * 0.5, PAD_FEATHER_HARD))
		_composer.pad_feather[index] = minf(
				maxf(PAD_FEATHER_GAIN * _pad_drop(index), PAD_FEATHER_MIN), cap)


## Cota de una plataforma: la que deja el **talud más suave posible** en la casa
## que menos sitio tiene.
##
## Promediar las alturas naturales —que fue el primer intento— reparte el
## movimiento de suelo en partes iguales y eso es justo lo que no conviene: en
## el caserío del este una de las tres casas está a ocho metros del eje de su
## calle y sólo tiene tres metros de talud, mientras que sus dos vecinas tienen
## doce y quince. Con el promedio, esa casa se comía un metro de corte en tres
## metros —un talud de 45°— y el terreno se partía. Acá la cota es la que
## **minimiza el peor `corte / sitio`** de la plataforma, que para tres casas se
## resuelve mirando los pares: el par que más cuesta manda, y su punto de
## equilibrio es la cota.
func _platform_datum(members: PackedInt32Array, base: PackedFloat32Array) -> float:
	if members.size() == 1:
		return base[members[0]]
	var best := 0.0
	var best_cost := -1.0
	var total := 0.0
	for index: int in members:
		total += base[index]
	var average := total / float(members.size())
	for a: int in members:
		for b: int in members:
			if base[a] <= base[b]:
				continue
			var wa := 1.0 / maxf(_pad_room(a), 0.001)
			var wb := 1.0 / maxf(_pad_room(b), 0.001)
			var cost := (base[a] - base[b]) * wa * wb / (wa + wb)
			if cost > best_cost:
				best_cost = cost
				best = (base[a] * wa + base[b] * wb) / (wa + wb)
	return best if best_cost >= 0.0 else average


## Desnivel que el pad [param index] tiene que recuperar: lo que el terreno
## natural se aparta de su cota sobre el propio rectángulo.
func _pad_drop(index: int) -> float:
	var centre := _composer.pad_centre[index]
	var axis := _composer.pad_axis[index]
	var across := Vector2(-axis.y, axis.x)
	var half := _composer.pad_half[index]
	var datum := _composer.pad_datum[index]
	var drop := 0.0
	for ring: int in PAD_RINGS:
		var scale := float(ring + 1) / float(PAD_RINGS)
		for sector: int in PAD_SECTORS:
			var angle := TAU * float(sector) / float(PAD_SECTORS)
			# Un rectángulo recorrido por su parámetro angular: el punto más lejano
			# en cada dirección, no un círculo inscripto.
			var unit := Vector2(cos(angle), sin(angle))
			var reach := 1.0 / maxf(maxf(absf(unit.x) / half.x, absf(unit.y) / half.y), 0.000001)
			var local := unit * reach * scale
			var p := centre + axis * local.x + across * local.y
			drop = maxf(drop, absf(_composer.base_height(p) - datum))
	return drop


## Cuánto talud puede desplegar el pad [param index] sin tocar nada que tenga
## que quedarse como está.
##
## Lo que no se puede tocar son **dos cosas medidas, no dos radios**: el eje de
## cada calle y de la ruta —que es donde `terrain_check` mide la pendiente del
## viario— y el borde de cada manzana, que es plana al milímetro por
## definición. El talud se corta justo antes de llegar a cualquiera de las dos,
## así que el pad no cambia ni un milímetro de la calle ni de la manzana; el
## precio es un talud más corto —y por lo tanto más empinado— en las tres casas
## que están declaradas al borde del camino.
func _pad_room(index: int) -> float:
	return maxf(_pad_reach(index, _keep_level), 0.5)


## Distancia del núcleo del pad [param index] al punto más cercano de
## [param points].
func _pad_reach(index: int, points: PackedVector2Array) -> float:
	var best := INF
	for p: Vector2 in points:
		best = minf(best, _composer.pad_distance(index, p))
	return best


## Geometría que los pads no pueden pisar, muestreada cada
## [constant PROTECT_STEP] metros.
##
## - [member _no_flat] son los **bordes de calzada** y los lados de las
##   manzanas: ni el núcleo plano puede cruzarlos.
## - [member _keep_level] son los **ejes** del viario y los mismos lados de
##   manzana: ni el talud puede llegar hasta ahí.
func _protect_geometry() -> void:
	_no_flat = PackedVector2Array()
	_keep_level = PackedVector2Array()
	for p: Vector2 in Composer._samples_2d(_composer.route, PROTECT_STEP):
		_keep_level.append(p)
	# El borde que no se puede aplanar es el de **calzada**, no el de vereda: la
	# vereda es una losa que sigue al terreno, así que aplanar debajo de ella no
	# se nota; la calzada, en cambio, se lee.
	_offset_samples(_composer.route, float(_plan.route_width) * 0.5, _no_flat)
	for slot: int in _composer.streets.size():
		for p: Vector2 in Composer._samples_2d(_composer.streets[slot], PROTECT_STEP):
			_keep_level.append(p)
		_offset_samples(_composer.streets[slot],
				float(_plan.street_width_of(slot + 1)) * 0.5, _no_flat)
	for polygon: PackedVector2Array in _composer.blocks:
		var ring := polygon.duplicate()
		if ring.size() >= 3:
			ring.append(ring[0])
		for p: Vector2 in Composer._samples_2d(ring, PROTECT_STEP):
			_keep_level.append(p)
			_no_flat.append(p)


## Vuelca en [param out] los dos bordes de una polilínea corrida
## [param half] metros a cada lado.
func _offset_samples(line: PackedVector2Array, half: float,
		out: PackedVector2Array) -> void:
	for index: int in maxi(line.size() - 1, 0):
		var a := line[index]
		var b := line[index + 1]
		var span := a.distance_to(b)
		if span <= 0.0001:
			continue
		var normal := Vector2(-(b.y - a.y), b.x - a.x) / span * half
		var steps := maxi(ceili(span / PROTECT_STEP), 1)
		for step: int in steps + 1:
			var p := a.lerp(b, float(step) / float(steps))
			out.append(p + normal)
			out.append(p - normal)


func _root(group: PackedInt32Array, index: int) -> int:
	var cursor := index
	while group[cursor] != cursor:
		cursor = group[cursor]
	return cursor


## Despeje que el cauce tiene que guardar, en metros, medido de **eje a eje**:
## la media franja del obstáculo más el margen de la máscara más medio ancho de
## arroyo. Un cauce más cerca que esto metería su talud dentro del corredor, y
## aunque la máscara lo borrase de la altura seguiría siendo un error de diseño:
## el arroyo estaría dibujado debajo de la calle.
const CREEK_ROUTE_CLEAR: float = 15.0
const CREEK_STREET_CLEAR: float = 15.0
const CREEK_BLOCK_CLEAR: float = 12.0

## Cuánto puede empujarse un vértice de la banda hacia afuera buscando despeje.
## El tope es el arranque del desvanecido: más allá el cauce se borraría solo.
const CREEK_BAND_MAX: float = 198.0


## Arroyo de andamio, derivado del plano (plan P2c §2, con la corrección de
## cotas del orquestador): cruza la ruta a `route_centre − 200 m` de arco —bien
## al oeste del disco de manzanas y lejos de la primera transversal— y después
## bordea el pueblo por el lado **izquierdo** de la ruta a unos 165–195 m del
## centro durante unos trescientos metros, con tres curvas suaves, antes de
## irse al borde.
##
## Tiene dos tramos con dos geometrías distintas, y a propósito:
##
## - **El cruce** se define en coordenadas de la ruta —offsets perpendiculares
##   a su eje— para que el arroyo la cruce **casi en ángulo recto**. Un cruce
##   oblicuo deja el cauce corriendo dentro del corredor de la calzada durante
##   decenas de metros antes de despegarse, que es lo que la primera versión de
##   este trazado hacía: cruzaba a 19° y a diecisiete metros del puente todavía
##   estaba a seis del eje.
## - **La banda** se define en polar alrededor del centro del pueblo, porque las
##   tres condiciones que la gobiernan son radiales: quedar fuera del disco de
##   manzanas (150 m), fuera de la punta de las calles (hasta 177 m en este
##   plano) y **dentro** del arranque del desvanecido (200 m), que si no
##   borraría el cauce justo donde tiene que verse.
##
## El radio de cada vértice de la banda no está escrito a mano: es un deseo que
## [method _fit_creek] empuja hacia afuera hasta que despeja de verdad contra
## las calles y las manzanas **de este plano**. Escribirlos a mano los ataría a
## una generación concreta del pueblo y el primer cambio de plano los rompería
## en silencio.
func _scaffold_creek() -> PackedVector2Array:
	var play_centre: Vector3 = _plan.play_centre
	var centre := Vector2(play_centre.x, play_centre.z)
	var arc: float = float(_plan.route_centre_distance()) - 200.0
	var crossing_point: Vector3 = _plan.route_point(arc)
	var crossing := Vector2(crossing_point.x, crossing_point.z)
	var radial := crossing - centre
	var base_angle := atan2(radial.y, radial.x)

	var tangent_direction: Vector3 = _plan.route_tangent(arc)
	var left := Composer._left_of(tangent_direction)
	var along := Vector2(tangent_direction.x, tangent_direction.z).normalized()
	# Hacia qué lado gira «izquierda» en el barrido polar. La normal izquierda
	# de la ruta en el cruce es casi tangencial al círculo del pueblo, así que
	# su signo contra la tangente antihoraria dice si el ángulo hay que barrerlo
	# hacia adelante o hacia atrás.
	var sweep := Vector2(-sin(base_angle), cos(base_angle))
	var turn := 1.0 if left.dot(sweep) >= 0.0 else -1.0

	var line := PackedVector2Array()
	# Aguas arriba, por el lado derecho: del borde del mapa al cruce, cada vez
	# más perpendicular a la ruta.
	line.append(crossing - left * 300.0 - along * 90.0)
	line.append(crossing - left * 150.0 - along * 30.0)
	line.append(crossing - left * 46.0 + along * 2.0)
	line.append(crossing)
	# Y por el izquierdo, despegándose igual de rápido. El vértice de salida
	# lleva también catorce metros **hacia el pueblo**: saliendo en
	# perpendicular pura el cauce se alejaría del centro hasta los 230 m, donde
	# el desvanecido ya se le come la mitad de la profundidad justo al lado del
	# puente, que es donde el jugador lo va a mirar de cerca.
	line.append(crossing + left * 34.0 + along * 14.0)

	# Banda alrededor del pueblo. `(grados desde el cruce, radio deseado)`.
	var band: Array[Vector2] = [
		Vector2(26.0, 172.0),
		Vector2(44.0, 186.0),
		Vector2(64.0, 170.0),
		Vector2(84.0, 188.0),
		Vector2(102.0, 174.0),
	]
	for step: Vector2 in band:
		var angle := base_angle + turn * deg_to_rad(step.x)
		line.append(centre + Vector2(cos(angle), sin(angle))
				* _fit_creek(centre, angle, step.y))
	# Fuga al borde.
	for step: Vector2 in [Vector2(114.0, 252.0), Vector2(124.0, 336.0)]:
		var angle := base_angle + turn * deg_to_rad(step.x)
		line.append(centre + Vector2(cos(angle), sin(angle)) * step.y)

	return _relax_creek(line, centre)


## Radio más chico, a partir de [param desired], en el que el punto polar
## despeja calles y manzanas. Si no lo encuentra antes de
## [constant CREEK_BAND_MAX] devuelve el deseado: el trazado sale mal y lo caza
## el informe, que es mejor que devolver un radio que borre el desvanecido.
func _fit_creek(centre: Vector2, angle: float, desired: float) -> float:
	var direction := Vector2(cos(angle), sin(angle))
	var radius := desired
	while radius <= CREEK_BAND_MAX:
		var p := centre + direction * radius
		if _nearest_street_distance(p) >= CREEK_STREET_CLEAR \
				and _nearest_block_distance(p) >= CREEK_BLOCK_CLEAR:
			return radius
		radius += 1.0
	return desired


## Empuja hacia afuera los vértices de la banda cuyos **tramos** —no sólo sus
## vértices— rocen una calle o una manzana. Un vértice puede despejar y el tramo
## que lo une al siguiente cortar igual por la cuerda, que es lo que pasa cuando
## la banda pasa por encima de la punta de una transversal.
func _relax_creek(line: PackedVector2Array, centre: Vector2) -> PackedVector2Array:
	# Los tres primeros y los dos últimos vértices son el cruce y la fuga: su
	# geometría la manda la ruta, no el despeje radial.
	var first := 5
	var last := line.size() - 3
	for _pass: int in 6:
		var worst := 0.0
		var offender := -1
		for index: int in range(first, last + 1):
			var deficit := maxf(
					CREEK_STREET_CLEAR - _segment_clearance(line, index, true),
					CREEK_BLOCK_CLEAR - _segment_clearance(line, index, false))
			if deficit > worst:
				worst = deficit
				offender = index
		if offender < 0 or worst <= 0.0:
			break
		var radial := line[offender] - centre
		var radius := minf(radial.length() + worst + 1.0, CREEK_BAND_MAX)
		line[offender] = centre + radial.normalized() * radius
	return line


## Despeje mínimo de los dos tramos que tocan el vértice [param index], contra
## las calles ([param streets]) o contra las manzanas.
func _segment_clearance(line: PackedVector2Array, index: int, streets: bool) -> float:
	var best := INF
	for side: int in [index - 1, index]:
		if side < 0 or side + 1 >= line.size():
			continue
		var piece := PackedVector2Array([line[side], line[side + 1]])
		for p: Vector2 in _samples_of(piece, 2.0):
			best = minf(best, _nearest_street_distance(p) if streets
					else _nearest_block_distance(p))
	return best


## Punto donde el arroyo cruza el eje de la ruta. Es el `bridge.at`.
func _creek_route_crossing(line: PackedVector2Array) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	for point: Vector2 in _samples_of(line, 1.0):
		var distance := Composer._distance(_composer.route, point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


# --------------------------------------------------------------------------
# Horneado de la rejilla
# --------------------------------------------------------------------------

## Evalúa la altura en las 513 × 513 muestras y llena de paso los tres campos
## auxiliares que el color de capa de los chunks necesita.
func _bake_grid() -> void:
	var play_centre: Vector3 = _plan.play_centre
	var half := float(GRID_SIZE - 1) * GRID_CELL * 0.5
	var origin := Vector2(play_centre.x - half, play_centre.z - half)

	var count := GRID_SIZE * GRID_SIZE
	var data := PackedFloat32Array()
	var _ok := data.resize(count)
	var _ok_mask := _mask_grid.resize(count)
	var _ok_creek := _creek_grid.resize(count)
	var _ok_datum := _datum_grid.resize(count)

	for iz: int in GRID_SIZE:
		var z := origin.y + float(iz) * GRID_CELL
		for ix: int in GRID_SIZE:
			var p := Vector2(origin.x + float(ix) * GRID_CELL, z)
			var index := iz * GRID_SIZE + ix
			var attenuation := _composer.fade(p)
			var block := _composer.nearest_block(p)
			var civil := _composer.mask(p, block)
			var civil_datum := _composer.datum(p, block)
			var distance := _composer.creek_distance(p)
			var pad := _composer.pad_weight(p)
			var value := 0.0
			if attenuation > 0.0:
				var wild := 0.0
				if civil < 1.0:
					wild = _composer.noise_height(p)
				value = lerpf(wild, civil_datum, civil)
				if pad.x >= 0.0 and pad.y > 0.0:
					value = lerpf(value, _composer.pad_datum[int(pad.x)], pad.y)
				value *= attenuation
			data[index] = value
			# El patio de un caserío cuenta como urbanizado para el color de capa:
			# es tierra pisada, no pasto.
			_mask_grid[index] = 1.0 - (1.0 - civil) * (1.0 - pad.y)
			_creek_grid[index] = minf(distance, 1000.0)
			_datum_grid[index] = civil_datum * attenuation

	_terrain = TownTerrain.new()
	_terrain.resource_name = "town_a_terrain"
	_terrain.origin = origin
	_terrain.cell = GRID_CELL
	_terrain.size = GRID_SIZE
	_terrain.heights = data
	_terrain.seed = int((_spec["terrain"] as Dictionary).get("seed", 0))
	_terrain.params = _spec


# --------------------------------------------------------------------------
# Malla visible
# --------------------------------------------------------------------------

## Coordenadas de un eje, compartidas por los cuatro chunks: paso de dos metros
## dentro del cuadrado refinado y de cuatro fuera.
##
## Que la lista sea **una sola y global** es lo que hace que dos chunks vecinos
## compartan literalmente los vértices de su borde: ambos toman la misma
## coordenada de la misma lista y la misma `height_at`, así que no hay costura
## posible. Que cada chunk arme su propia rejilla y confiar en que los flotantes
## coincidan es exactamente el error que produce grietas de un píxel.
func _axis_coordinates() -> PackedFloat32Array:
	var refine := _refine_reach()
	var out := PackedFloat32Array()
	var x := -CHUNK_REACH
	while x < -refine - 0.0001:
		out.append(x)
		x += CHUNK_STEP_FAR
	x = -refine
	while x < refine - 0.0001:
		out.append(x)
		x += CHUNK_STEP_NEAR
	x = refine
	while x < CHUNK_REACH - 0.0001:
		out.append(x)
		x += CHUNK_STEP_FAR
	out.append(CHUNK_REACH)
	return out


## Medio lado del cuadrado de paso fino, en metros: `block_radius + 40` del
## **plano resuelto**, redondeado hacia arriba a un múltiplo del paso grueso.
##
## Se lee del plano y no se escribe a mano porque el disco de manzanas se mueve:
## WP-T3 lo llevó de 150 a 180 m al extender las transversales hasta sus nodos,
## y un cuadrado refinado escrito para 150 habría dejado las manzanas del borde
## dibujadas con el paso grueso de cuatro metros.
func _refine_reach() -> float:
	var reach: float = float(_plan.block_radius) + CHUNK_REFINE_MARGIN
	reach = ceilf(reach / CHUNK_STEP_FAR) * CHUNK_STEP_FAR
	return minf(reach, CHUNK_REACH - CHUNK_STEP_FAR)


func _build_chunks(material: ShaderMaterial) -> void:
	var axis := _axis_coordinates()
	var middle := axis.find(0.0)
	if middle < 0:
		push_error("build_terrain: la lista de coordenadas no pasa por el centro")
		return
	var spans: Array[Vector2i] = [
		Vector2i(0, middle), Vector2i(middle, axis.size() - 1),
	]
	var chunk := 0
	for iz: int in 2:
		for ix: int in 2:
			var mesh := _build_chunk(axis, spans[ix], spans[iz], material)
			_save(mesh, CHUNK_PATH % chunk)
			chunk += 1


## Un chunk: rejilla de posiciones tomadas de [param axis] entre los índices de
## [param span_x] y [param span_z], con la altura, la normal y el color de capa
## de cada vértice.
##
## Los vértices van en **coordenadas del distrito**, no locales al chunk: el
## nodo que los lleve se cuelga en el origen y no se mueve. Así el borde
## compartido es el mismo número en los dos chunks y el `AABB` sigue siendo el
## de la baldosa, que es lo que necesita el culling.
func _build_chunk(axis: PackedFloat32Array, span_x: Vector2i, span_z: Vector2i,
		material: ShaderMaterial) -> ArrayMesh:
	var play_centre: Vector3 = _plan.play_centre
	var columns := span_x.y - span_x.x + 1
	var rows := span_z.y - span_z.x + 1

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var _ok_v := vertices.resize(columns * rows)
	var _ok_n := normals.resize(columns * rows)
	var _ok_c := colors.resize(columns * rows)

	for row: int in rows:
		var z := axis[span_z.x + row] + play_centre.z
		for column: int in columns:
			var x := axis[span_x.x + column] + play_centre.x
			var index := row * columns + column
			vertices[index] = Vector3(x, _terrain.height_at(x, z), z)
			normals[index] = _terrain.normal_at(x, z)
			colors[index] = _layer_color(x, z)

	var indices := PackedInt32Array()
	for row: int in rows - 1:
		for column: int in columns - 1:
			var a := row * columns + column
			var b := a + 1
			var c := a + columns
			var d := c + 1
			# La diagonal alterna por paridad: una diagonal fija en toda la
			# rejilla se lee como un peinado en las lomas, porque todas las
			# facetas miran para el mismo lado.
			#
			# El **orden** de los tres índices es el que decide de qué lado se
			# ve el triángulo, y no la normal: con `cull_back`, una cara mirando
			# al cielo necesita `(v1 − v0) × (v2 − v0) · UP` **negativo**, la
			# misma regla que comprueba a mano `CityGrid._field_quad`. Hasta
			# WP-T4 los seis índices iban al revés y los 115 200 triángulos del
			# relieve se descartaban: en la captura aérea no se veía el terreno
			# sino el `ground_color` del cielo por el agujero del campo lejano
			# —un azul oscuro plano y sin sombrear— y desde la ruta, la misma
			# lámina celeste en el horizonte.
			if (row + column) % 2 == 0:
				indices.append_array([a, b, c, b, d, c])
			else:
				indices.append_array([a, d, c, a, b, d])

	var arrays: Array = []
	var _ok_a := arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.resource_name = "town_a_terrain_chunk"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## Peso de cada capa en el vértice `(x, z)`, con la prioridad arena > roca >
## tierra > pasto y la suma exactamente en uno.
##
## - **Arena** es el lecho y los bancos del arroyo, y sólo fuera de lo urbano.
## - **Roca** sale donde la pendiente pasa de unos 17°, que en este terreno es
##   el talud del cauce y el hombro de las lomas más marcadas.
## - **Tierra** es lo urbanizado —calle, vereda y patio— más las pendientes
##   medias, donde el pasto se pela.
## - **Pasto** es el resto, que es casi todo el campo.
func _layer_color(x: float, z: float) -> Color:
	var civil := _grid_value(_mask_grid, x, z, 0.0)
	var distance := _grid_value(_creek_grid, x, z, 1000.0)
	var slope := _terrain.slope_at(x, z)

	var sand := clampf(1.0 - smoothstep(_composer.creek_width * 0.5,
			_composer.creek_bank * 0.85, distance), 0.0, 1.0) * (1.0 - civil)
	var rock := smoothstep(ROCK_SLOPE_MIN, ROCK_SLOPE_MAX, slope) * (1.0 - sand)
	# Lo urbanizado aporta `CIVIL_DIRT` de tierra y no 0,8: la calle y la vereda
	# las tapan sus propias cintas, así que el único suelo civil que se ve es el
	# **patio** de cada manzana, y un patio con el 80 % de tierra se lee como un
	# pozo negro entre las casas. Con un tercio queda pasto gastado, que es lo
	# que hay en un fondo de casa, y la tierra pasa a ser cosa de las pendientes.
	var dirt := maxf(civil * CIVIL_DIRT, smoothstep(DIRT_SLOPE_MIN, DIRT_SLOPE_MAX, slope) * 0.55) \
			* (1.0 - sand) * (1.0 - rock)
	var grass := maxf(0.0, 1.0 - sand - rock - dirt)
	return Color(grass, dirt, rock, sand)


## Valor de una rejilla auxiliar en la muestra más cercana a `(x, z)`. Los
## vértices de los chunks caen en pasos de dos y cuatro metros sobre una rejilla
## de uno, así que «la más cercana» es siempre exacta.
func _grid_value(grid: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var ix := roundi((x - _terrain.origin.x) / _terrain.cell)
	var iz := roundi((z - _terrain.origin.y) / _terrain.cell)
	if ix < 0 or iz < 0 or ix >= _terrain.size or iz >= _terrain.size:
		return outside
	return grid[iz * _terrain.size + ix]


func _build_material() -> ShaderMaterial:
	var shader := ResourceLoader.load(SHADER_PATH, "Shader") as Shader
	if shader == null:
		push_error("build_terrain: no se pudo cargar %s" % SHADER_PATH)
		return ShaderMaterial.new()
	var material := ShaderMaterial.new()
	material.resource_name = "town_terrain"
	material.shader = shader
	return material


# --------------------------------------------------------------------------
# Informe
# --------------------------------------------------------------------------

## Vuelca lo que hay que mirar de un horneado: extremos de altura, pendientes
## bajo los tres tipos de eje, cotas de manzana, despeje del arroyo y tamaño de
## las mallas.
func _report() -> void:
	var span := _terrain.range_of()
	print("  altura: min %.3f m · max %.3f m · desnivel %.3f m"
			% [span.x, span.y, span.y - span.x])
	print("  perfil de ruta: amplitud %.3f m · gradiente máximo %.2f %%"
			% [_composer.profile_amplitude, _max_profile_grade() * 100.0])

	print("  pendiente máxima bajo la ruta %.2f %%" % (_axis_grade(_composer.route) * 100.0))
	var worst_street := 0.0
	var worst_index := -1
	for index: int in _composer.streets.size():
		var grade := _axis_grade(_composer.streets[index])
		if grade > worst_street:
			worst_street = grade
			worst_index = index
	print("  pendiente máxima bajo los ejes de calle %.2f %% (calle %d de %d)"
			% [worst_street * 100.0, worst_index, _composer.streets.size()])

	var worst_block := 0.0
	var worst_flat := 0.0
	for index: int in _composer.blocks.size():
		var stats := _block_stats(index)
		worst_block = maxf(worst_block, stats.x)
		worst_flat = maxf(worst_flat, stats.y)
	print("  manzanas: %d · pendiente máxima %.3f %% · desvío de cota máximo %.3f mm"
			% [_composer.blocks.size(), worst_block * 100.0, worst_flat * 1000.0])

	_report_pads()

	var bridge: Array = (_spec["bridge"] as Dictionary)["at"]
	print("  arroyo: %d vértices · banda r %.1f–%.1f m · cruce en (%.1f, %.1f)"
			% [_composer.creek.size(), _creek_radius(false), _creek_radius(true),
			float(bridge[0]), float(bridge[1])])
	var clearance := _bank_clearance()
	print("  arroyo: eje a %.1f m del eje de la ruta fuera del vano" % _creek_clearance_route())
	print("  arroyo: holgura mínima del borde del banco %.2f m contra %s, en (%.1f, %.1f)%s"
			% [float(clearance["gap"]), clearance["what"],
			(clearance["at"] as Vector2).x, (clearance["at"] as Vector2).y,
			"  ← POR DEBAJO DE 3 m: lo corrige WP-T3 en el JSON"
			if float(clearance["gap"]) < 3.0 else ""])
	# Desglose para quien tenga que corregir el trazado: cada obstáculo que
	# invade, su holgura y dónde. Un mínimo global no dice qué mover.
	var offenders: Array = clearance["offenders"]
	for entry: Dictionary in offenders:
		print("    invade %s: holgura %.2f m en (%.1f, %.1f)"
				% [entry["what"], float(entry["gap"]),
				(entry["at"] as Vector2).x, (entry["at"] as Vector2).y])

	var triangles := 0
	for index: int in 4:
		var mesh := ResourceLoader.load(CHUNK_PATH % index, "ArrayMesh",
				ResourceLoader.CACHE_MODE_REPLACE) as ArrayMesh
		if mesh == null:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3
		print("  chunk %d: %d vértices · %d triángulos · %d KB · AABB %s"
				% [index, vertices.size(), indices.size() / 3,
				_file_size(CHUNK_PATH % index) / 1024, mesh.get_aabb().size.round()])
	print("  malla visible: %d triángulos en 4 superficies" % triangles)
	print("  recursos: terreno %d KB · colisión %d KB"
			% [_file_size(TERRAIN_PATH) / 1024, _file_size(COLLISION_PATH) / 1024])
	print("  firma: %s" % _terrain.signature())


## Metros de campo que quedan entre el pad [param index] y el núcleo del pad de
## otra plataforma más cercano, o `INF` si no hay ninguno.
func _nearest_pad_gap(index: int) -> float:
	var best := INF
	for other: int in _composer.pad_centre.size():
		if other == index or _pad_group[other] == _pad_group[index]:
			continue
		best = minf(best, _pad_gap(index, other))
	return best


## Los doce pads de caserío: medidas, desvanecido, cota, cuánto apoya la huella
## y qué tan cerca están de algo que no conviene aplanar.
func _report_pads() -> void:
	var worst_rest := 0.0
	var worst_name := ""
	for index: int in _composer.pad_centre.size():
		var centre := _composer.pad_centre[index]
		var axis := _composer.pad_axis[index]
		var across := Vector2(-axis.y, axis.x)
		var half := _composer.pad_half[index] - Vector2(PAD_MARGIN, PAD_MARGIN)
		var rest := 0.0
		for corner: Array in [[1.0, 1.0], [1.0, -1.0], [-1.0, 1.0], [-1.0, -1.0]]:
			var p := centre + axis * (half.x * float(corner[0])) 					+ across * (half.y * float(corner[1]))
			rest = maxf(rest, absf(_terrain.height_at(p.x, p.y)
					- _composer.pad_datum[index]))
		if rest > worst_rest:
			worst_rest = rest
			worst_name = "pad %d" % index
		print("    pad %2d en (%7.1f, %7.1f) · %.1f × %.1f m · desvanecido %5.2f m"
				% [index, centre.x, centre.y, _composer.pad_half[index].x * 2.0,
				_composer.pad_half[index].y * 2.0, _composer.pad_feather[index]]
				+ " · plataforma %d · cota %6.3f m · huella plana ±%.1f mm"
				% [_pad_group[index] if index < _pad_group.size() else index,
				_composer.pad_datum[index], rest * 1000.0]
				+ " · vecino a %.1f m · arroyo a %.1f m · sitio %.1f m"
				% [_nearest_pad_gap(index), _composer.creek_distance(centre),
				_pad_room(index)])
	var platforms: Dictionary[int, bool] = {}
	for index: int in _pad_group.size():
		platforms[_pad_group[index]] = true
	print("  pads de caserío: %d en %d plataformas · el peor deja la huella a ±%.1f mm (%s)"
			% [_composer.pad_centre.size(), platforms.size(), worst_rest * 1000.0, worst_name])


## Imprime el plano y el arroyo sin hornear nada. Es el modo con el que se
## ajustó el trazado del cauce contra la geometría real del pueblo.
func _probe() -> void:
	var play_centre: Vector3 = _plan.play_centre
	print("probe: plano semilla %d" % int(_plan.seed))
	print("  centro %s · juego %.1f · manzanas %.1f · campo %.1f"
			% [play_centre, float(_plan.play_radius), float(_plan.block_radius),
			float(_plan.field_size)])
	print("  ruta %s (largo %.1f, arco del centro %.1f)"
			% [_composer.route, float(_plan.route_length()),
			float(_plan.route_centre_distance())])
	for index: int in _composer.streets.size():
		var axis := _composer.streets[index]
		var far := 0.0
		for point: Vector2 in axis:
			far = maxf(far, point.distance_to(_composer.centre))
		print("    calle %d: %s franja %.1f radio máximo %.1f"
				% [index, axis, _composer.street_halves[index], far])
	for index: int in _composer.blocks.size():
		var bound := _composer.block_bounds[index]
		print("    manzana %d: centro (%.1f, %.1f) radio %.1f cota %.3f"
				% [index, bound.x, bound.y, bound.z, _composer.block_datum[index]])
	for point: Vector2 in _composer.creek:
		print("    arroyo (%.1f, %.1f) r=%.1f ruta=%.1f calles=%.1f manzanas=%.1f"
				% [point.x, point.y, point.distance_to(_composer.centre),
				Composer._distance(_composer.route, point),
				_nearest_street_distance(point), _nearest_block_distance(point)])
	var probe_clearance := _bank_clearance()
	print("  despeje: eje a ruta %.1f · borde del banco %.2f contra %s"
			% [_creek_clearance_route(), float(probe_clearance["gap"]),
			probe_clearance["what"]])
	print("  cruce en %s" % str((_spec["bridge"] as Dictionary)["at"]))
	print("  perfil: amplitud %.3f m · gradiente máximo %.2f %%"
			% [_composer.profile_amplitude, _max_profile_grade() * 100.0])


# --------------------------------------------------------------------------
# Medidas
# --------------------------------------------------------------------------

## Gradiente máximo del perfil longitudinal, muestreado sobre la ruta.
func _max_profile_grade() -> float:
	var worst := 0.0
	var length: float = _plan.route_length()
	var arc := 0.0
	while arc < length:
		worst = maxf(worst, absf(_composer.profile(arc + 1.0)
				- _composer.profile(arc - 1.0)) * 0.5)
		arc += 2.0
	return worst


## Pendiente máxima del terreno bajo un eje, muestreado cada dos metros y sólo
## dentro de la rejilla: fuera de ella la altura es cero por definición.
func _axis_grade(axis: PackedVector2Array) -> float:
	var worst := 0.0
	var half := float(GRID_SIZE - 1) * GRID_CELL * 0.5
	var samples := _samples_of(axis, 2.0)
	for index: int in maxi(samples.size() - 1, 0):
		var p := samples[index]
		var q := samples[index + 1]
		if absf(p.x - _composer.centre.x) > half or absf(p.y - _composer.centre.y) > half:
			continue
		if absf(q.x - _composer.centre.x) > half or absf(q.y - _composer.centre.y) > half:
			continue
		var rise := absf(_terrain.height_at(q.x, q.y) - _terrain.height_at(p.x, p.y))
		worst = maxf(worst, rise / maxf(p.distance_to(q), 0.0001))
	return worst


## Pendiente máxima y desvío de cota dentro de la manzana [param index], como
## `Vector2(pendiente, desvío)`.
func _block_stats(index: int) -> Vector2:
	var polygon := _composer.blocks[index]
	var bound := _composer.block_bounds[index]
	var low := INF
	var high := -INF
	var worst := 0.0
	var z := bound.y - bound.z
	while z <= bound.y + bound.z:
		var x := bound.x - bound.z
		while x <= bound.x + bound.z:
			# 2,5 m de retiro y no uno: `slope_at` mira a un metro a cada lado y
			# `height_at` interpola entre muestras a otro metro, así que un
			# punto a un metro del borde mide, sin querer, la vereda.
			if Composer._inset(polygon, Vector2(x, z)) >= 2.5:
				var height := _terrain.height_at(x, z)
				low = minf(low, height)
				high = maxf(high, height)
				worst = maxf(worst, tan(_terrain.slope_at(x, z)))
			x += 2.0
		z += 2.0
	if low > high:
		return Vector2.ZERO
	return Vector2(worst, high - low)


func _nearest_street_distance(p: Vector2) -> float:
	var best := INF
	for axis: PackedVector2Array in _composer.streets:
		best = minf(best, Composer._distance(axis, p))
	return best


func _nearest_block_distance(p: Vector2) -> float:
	var best := INF
	for polygon: PackedVector2Array in _composer.blocks:
		best = minf(best, -Composer._inset(polygon, p))
	return best


## Holgura del **borde exterior del banco** del arroyo contra manzanas y
## corredores de calle, como `{gap, at, what}`.
##
## Lo que se mide no es el eje del cauce sino `eje ± (width/2 + bank)`: el talud
## llega hasta ahí, y un arroyo cuyo banco muere dentro de una vereda no es un
## arroyo con holgura, es una vereda con un pozo al lado. Los **cabos** cuentan
## como corredor hasta su punta (`street_stub_of` metros más allá del último
## vértice) más tres metros de vereda: una tranquera al final de una calle
## muerta sigue siendo algo que el jugador pisa.
##
## La ruta se mide aparte y sin el vano del puente, que es justamente donde el
## cauce tiene que pasar por debajo.
func _bank_clearance() -> Dictionary:
	var bank_reach := _composer.creek_width * 0.5 + _composer.creek_bank
	var per_obstacle: Dictionary = {}
	for p: Vector2 in _samples_of(_composer.creek, 2.0):
		for index: int in _composer.blocks.size():
			_note_gap(per_obstacle, "manzana %d" % index,
					-Composer._inset(_composer.blocks[index], p) - bank_reach, p)
		for index: int in _composer.streets.size():
			_note_gap(per_obstacle, "calle %d" % index,
					Composer._distance(_street_corridor(index), p)
					- (_composer.street_halves[index] + STREET_MARGIN) - bank_reach, p)

	var worst := INF
	var worst_at := Vector2.ZERO
	var worst_what := "nada"
	var offenders: Array = []
	for what: String in per_obstacle:
		var entry: Dictionary = per_obstacle[what]
		var gap := float(entry["gap"])
		if gap < 3.0:
			offenders.append({"what": what, "gap": gap, "at": entry["at"]})
		if gap < worst:
			worst = gap
			worst_at = entry["at"]
			worst_what = what
	offenders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["gap"]) < float(b["gap"]))
	return {"gap": worst, "at": worst_at, "what": worst_what, "offenders": offenders}


func _note_gap(store: Dictionary, what: String, gap: float, at: Vector2) -> void:
	if not store.has(what) or gap < float((store[what] as Dictionary)["gap"]):
		store[what] = {"gap": gap, "at": at}


## Eje de la calle [param index] **estirado por sus dos cabos**, en XZ.
func _street_corridor(index: int) -> PackedVector2Array:
	var axis := _composer.streets[index].duplicate()
	if axis.size() < 2:
		return axis
	# `_composer.streets[index]` es la calle `index + 1` **del grafo** (la `0` es
	# la ruta), y `street_stub_of` indexa el grafo. Sin el `+ 1` cada calle se
	# estiraba con los cabos de la anterior y la holgura del arroyo se medía
	# contra un corredor que no existe.
	var head: float = float(_plan.street_stub_of(index + 1, 0))
	var tail: float = float(_plan.street_stub_of(index + 1, 1))
	if head > 0.0:
		axis[0] = axis[0] + (axis[0] - axis[1]).normalized() * head
	if tail > 0.0:
		var last := axis.size() - 1
		axis[last] = axis[last] + (axis[last] - axis[last - 1]).normalized() * tail
	return axis


## Distancia mínima del **eje** del arroyo al eje de la ruta, fuera del vano.
func _creek_clearance_route() -> float:
	var bridge: Dictionary = _spec["bridge"]
	var at_list: Array = bridge["at"]
	var at := Vector2(float(at_list[0]), float(at_list[1]))
	var span := float(bridge.get("span", 16.0))
	var best := INF
	for p: Vector2 in _samples_of(_composer.creek, 2.0):
		if p.distance_to(at) <= span * 0.5 + _composer.creek_bank:
			continue
		best = minf(best, Composer._distance(_composer.route, p))
	return best


## Radio mínimo o máximo de la banda que bordea el pueblo. Los dos vértices de
## cada punta son la fuga al borde y no forman parte de la banda: medirlos
## falsearía el rango.
func _creek_radius(highest: bool) -> float:
	var best := INF if not highest else -INF
	for index: int in _composer.creek.size():
		if index <= 3 or index >= _composer.creek.size() - 2:
			continue
		var radius := _composer.creek[index].distance_to(_composer.centre)
		best = minf(best, radius) if not highest else maxf(best, radius)
	return best


## Una polilínea muestreada cada [param step] metros, extremos incluidos.
static func _samples_of(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for index: int in maxi(line.size() - 1, 0):
		var a := line[index]
		var b := line[index + 1]
		var steps := maxi(int(a.distance_to(b) / maxf(step, 0.01)), 1)
		for offset: int in steps:
			out.append(a.lerp(b, float(offset) / float(steps)))
	if not line.is_empty():
		out.append(line[line.size() - 1])
	return out


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

func _user_args() -> Dictionary:
	var parsed: Dictionary = {}
	for raw: String in OS.get_cmdline_user_args():
		var arg := raw
		while arg.begins_with("-"):
			arg = arg.substr(1)
		if arg.is_empty():
			continue
		var separator := arg.find("=")
		if separator >= 0:
			parsed[arg.substr(0, separator)] = arg.substr(separator + 1)
		else:
			parsed[arg] = "true"
	return parsed


func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("build_terrain: no se pudo crear '%s': %s" % [path, error_string(err)])


func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("build_terrain: no se pudo guardar '%s': %s" % [path, error_string(err)])
		return
	print("  guardado %s (%d KB)" % [path, _file_size(path) / 1024])


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length
