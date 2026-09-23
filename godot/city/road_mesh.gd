## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Geometría del viario del pueblo: cintas de calzada, polígonos de cruce,
## anillos de vereda y cierres de cabo (`docs/10`, plan P2c §2).
##
## Es una caja de funciones **estáticas y puras**: no crea nodos, no toca el
## árbol, no abre una escena y no sortea nada. Entra aritmética —polilíneas,
## polígonos, anchos— y sale una [ArrayMesh]. Eso la hace ejercitable en
## `--headless` puro desde un banco y, sobre todo, **determinista**: dos corridas
## con los mismos números producen los mismos vértices bit a bit, que es lo que
## permite hornear el viario a `.res` y compararlo entre commits.
##
## ## Por qué una cinta y no una cadena de baldosas
##
## Hasta P2b la calzada eran instancias de `Road_Chunk_5` (10 × 0,5 × 10 m)
## encadenadas a lo largo de cada tramo, los cruces un parche cuadrado **alineado
## a los ejes del mundo** apoyado a la misma altura que la calzada y las veredas
## barras que atravesaban cada cruce. Eso deja cuatro defectos que no se arreglan
## moviendo instancias:
##
## 1. **Z-fighting.** El parche del cruce y la calzada están los dos en
##    `y = 0,03`: dos superficies coplanares que el depth buffer no puede ordenar.
## 2. **Esquinas que sobresalen.** Un cuadrado del mundo sobre un cruce oblicuo
##    asoma por las cuatro puntas y deja ver las marcas viales debajo.
## 3. **Muescas en los quiebres.** Dos cadenas de baldosas que se encuentran en
##    ángulo dejan un triángulo de campo entre ellas.
## 4. **Cabos sin sellar.** Una calle que termina en el medio del campo.
##
## La cinta los cierra de raíz: una sola malla por material, con **miter** en los
## quiebres (el vértice se corre sobre la bisectriz, así que las dos mitades
## comparten borde y no queda muesca), corte **recto** en los extremos y recorte
## contra el polígono del nodo, que es lo que evita que dos asfaltos se pisen.
##
## ## El atlas
##
## Las piezas del pack son voxel remallado con un atlas por cara: la cara
## superior de `Road_Chunk_5` es **un solo cuadrilátero** que mapea sus 10 × 10 m
## al rectángulo [constant ROAD_UV] del atlas `t_roads_diffuse.png`. Medido sobre
## la pieza (`assets/city/pieces`): el eje **+X local —el que corre a lo largo del
## camino— cae sobre la V del atlas**, y el +Z local —el ancho— sobre la U. Es al
## revés de lo que se esperaría, y es lo que hay: las bandas pintadas corren
## sobre la V. [method ribbon] respeta esa medida en vez de la convención, y por
## eso [param u_scale] se documenta como «UV por metro **a lo largo**» sin decir
## sobre qué eje del atlas cae.
##
## Donde no tiene que haber marcas —los cruces, las veredas, los cierres— se usa
## [constant ASPHALT_UV], el parche de asfalto liso que WP-24b midió entre las
## dos bandas anaranjadas del borde.
@tool
class_name RoadMesh extends RefCounted

# --------------------------------------------------------------------------
# Atlas
# --------------------------------------------------------------------------

## Rectángulo UV de la cara superior de `Road_Chunk_5` en `t_roads_diffuse.png`.
## Mide 10 × 10 m de calzada con sus marcas.
const ROAD_UV: Rect2 = Rect2(0.856320, 0.150777, 0.135297, 0.135297)

## Rectángulo UV de un parche de asfalto **sin marcas**, dentro de
## [constant ROAD_UV]. Es la misma constante que usaba
## `CityGrid._build_crossing_mesh`, y por la misma razón: reutiliza `roads.tres`
## sin sumar un PNG al presupuesto de VRAM de `docs/10` §2.3.
const ASPHALT_UV: Rect2 = Rect2(0.8905, 0.1565, 0.02606, 0.02606)

## [constant ROAD_UV] recortado **a lo ancho** a su zona lisa: la calzada de
## `Road_Chunk_5` sin las dos bandas pintadas que la pieza trae en el atlas.
##
## Medido sobre `assets/city/textures/t_roads_diffuse.png` (1024²) en WP-T5: el
## tile ocupa las columnas 877–1015; la columna 877–882 es una línea clara de
## borde y las columnas **981–1007** son una franja anaranjada de 27 téxeles
## —el cordón que la pieza lleva pintado—, contra los (77, 81, 100) planos del
## resto. Estirada a lo ancho de una calle, esa franja cae al 75–94 % de la
## calzada y se lee como una banda paralela al cordón; y como la V se repite
## cada diez metros, cada junta de celda le cambia la mipmap y la banda aparece
## y desaparece con un período regular. Eso son los «dientes» que se vieron en
## `plaza_60` y en la aérea del checkpoint 4.
##
## Las calles y los pasajes usan este recorte y la ruta se queda con el tile
## entero, que es la gramática de `docs/17` §4: sólo la ruta lleva marcas.
const ROAD_SMOOTH_UV: Rect2 = Rect2(0.865234, 0.152344, 0.087891, 0.131836)

## Metros de calzada que cubre [constant ASPHALT_UV] a lo largo y a lo ancho.
const ASPHALT_PATCH: float = 2.0

## Cuánto se recorta [constant ASPHALT_UV] por cada lado antes de usarlo en las
## veredas, en fracción del parche.
##
## El parche mide 0,026 de atlas —unos 26 téxeles— y **sus cuatro bordes son la
## frontera con la baldosa vecina**, que en `t_roads_diffuse.png` trae las dos
## bandas anaranjadas del cordón pintado. Mapear hasta el borde exacto hace que
## el filtrado bilineal y las mipmaps chupen esos téxeles: en la captura de
## WP-T4 el borde exterior de cada vereda salía con una franja naranja que no
## está en ninguna geometría. Recortando un quinto de parche por lado sólo se
## muestrea la zona lisa del medio.
const SMOOTH_INSET: float = 0.2

## Media altura del parche que usa la cara del cordón, en fracción.
##
## El cordón mide 15 cm: estirarle el parche entero a lo alto le da al
## muestreo una derivada UV enorme en la vertical, el GPU salta a una mipmap
## muy gruesa y la cara se pinta con el promedio del atlas. Con una tajada
## angosta del medio la derivada baja dos órdenes y el cordón queda del gris de
## la vereda, que es lo que pide la gramática de `docs/17` §4.
const CURB_UV_BAND: float = 0.12

## UV por metro a lo largo de la cinta con marcas: los 10 m de la pieza sobre el
## alto de [constant ROAD_UV].
const ROAD_U_SCALE: float = 0.0135297

# --------------------------------------------------------------------------
# Tolerancias de la geometría
# --------------------------------------------------------------------------

## Cordón de la vereda, en metros: la cara vertical que separa la vereda de la
## calzada. Es el número que `city_check` mide con ±0,01.
const CURB: float = 0.15

## Paso máximo entre vértices a lo largo de una cinta o de un anillo, en metros.
## Manda cuánto sigue la malla al relieve: con la rejilla de 1 m de
## [TownTerrain] y grano de 25 m, dos metros y medio no dejan ver la
## interpolación.
## Bajó de 2,5 m a 1,25 m al re-hornear el pueblo con relieve (WP-T4). El
## terreno no es sólo suave: donde una manzana se termina, la máscara pasa de
## la cota municipal al perfil de la ruta en pocos metros y deja un quiebre de
## 0,07 m por metro. Una cuerda de dos metros y medio sobre ese quiebre se
## hunde cuatro centímetros por debajo del terreno —o sea, la calzada
## desaparece bajo el pasto—, y el criterio 1 del plan pide que la separación no
## baje de un centímetro. Con 1,25 m el error se divide por cuatro.
const MAX_STEP: float = 1.25

## Paso **a lo ancho** de la cinta. Puede ser más grueso que el de a lo largo:
## una calzada tiene nueve metros de ancho y el relieve no tiene quiebres
## transversales —la máscara de una calle es simétrica respecto de su eje—, así
## que con cuatro carriles de dos metros y medio el peralte ya se sigue.
const MAX_STEP_ACROSS: float = 2.5

## Cuánto puede estirarse un miter antes de recortarlo, en múltiplos de la
## media franja. Sin tope, dos tramos casi opuestos mandan el vértice al
## infinito.
const MITER_LIMIT: float = 4.0

## Radio de boca de un nodo, en múltiplos de la media franja más ancha: mínimo
## —para que un nodo de paso no salga degenerado— y tope —para que dos calles
## que se cruzan casi en paralelo no produzcan una plaza de asfalto.
const MOUTH_MIN: float = 0.45
const MOUTH_MAX: float = 4.0

## Cuánto se corre la boca de un nodo **más allá** de la esquina verdadera, en
## metros.
##
## Es lo que produce el chaflán. Con la boca justo sobre la esquina, el polígono
## del cruce termina en punta y se lee como una estrella; corriéndola ochenta
## centímetros, el lado que une la boca de una calle con la de la siguiente corta
## la punta en diagonal, que es lo que hace una esquina de verdad. El chaflán que
## sale mide `CHAMFER · √2` en un cruce a 90°.
const CHAMFER: float = 0.8

## Debajo de esto dos vértices de una polilínea son el mismo punto.
const EPSILON: float = 0.001

# --------------------------------------------------------------------------
# Cierres de cabo
# --------------------------------------------------------------------------

const KIND_GATE: StringName = &"gate"
const KIND_CULVERT: StringName = &"culvert"
const KIND_FENCE: StringName = &"fence"
const KIND_NONE: StringName = &"none"

## Los cuatro cierres que el diseño puede declarar sobre un cabo.
const CLOSURE_KINDS: Array[StringName] = [KIND_GATE, KIND_CULVERT, KIND_FENCE, KIND_NONE]


# --------------------------------------------------------------------------
# Cintas
# --------------------------------------------------------------------------

## Calzada de [param polyline] como una cinta triangulada de
## `2 · half_width` metros de ancho.
##
## - **Miter en los quiebres**: el vértice interior se corre sobre la bisectriz,
##   así que los dos tramos comparten el mismo par de vértices y no queda muesca.
##   El estiramiento se recorta a [constant MITER_LIMIT] medias franjas.
## - **Corte recto en los extremos**: perpendicular a la tangente. Es lo que
##   permite empalmar la cinta con el polígono de un nodo o con la cadena de
##   baldosas de la ruta exterior sin dejar hueco ni solape.
## - **`y` del terreno**: cada vértice toma `height_fn.call(x, z) + top`. Con
##   [param height_fn] nulo o inválido el terreno es el plano `y = 0`.
## - **UV**: a lo largo se repite [param uv_rect] cada `uv_rect.size.y / u_scale`
##   metros —o sea, cada 10 m con el valor nominal— para que las marcas viales
##   salgan a escala; a lo ancho el rectángulo se estira al ancho real de la
##   calle, que es lo que hacía la escala en Z de la baldosa.
##
##   [param uv_rect] es el tile entero ([constant ROAD_UV], con las bandas
##   pintadas) por omisión, y la ruta es la única que lo quiere así. Las calles
##   pasan [constant ROAD_SMOOTH_UV]: estirar las bandas pintadas a lo ancho de
##   una calle deja una franja paralela al cordón que la repetición de la V
##   vuelve intermitente, y eso se lee como dientes.
##
## Devuelve `null` si la polilínea no da ni un tramo.
static func ribbon(polyline: PackedVector3Array, half_width: float, height_fn: Callable,
		top: float, u_scale: float = ROAD_U_SCALE,
		uv_rect: Rect2 = ROAD_UV) -> ArrayMesh:
	var line := _clean(polyline)
	if line.size() < 2 or half_width <= 0.0:
		return null

	var rails := _miter_rails(line, half_width)
	var left: PackedVector3Array = rails[0]
	var right: PackedVector3Array = rails[1]

	# Largo de atlas: los metros de cinta que cubren el rectángulo entero. Cada
	# tramo se parte en un número **entero** de esas celdas, así el dibujo no se
	# corta a mitad de una marca y dos tramos consecutivos empalman en una
	# frontera de celda.
	var tile := uv_rect.size.y / maxf(u_scale, 0.000001)

	var across := _steps(half_width * 2.0, height_fn, MAX_STEP_ACROSS)

	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in line.size() - 1:
		var span := _flat(line[index + 1] - line[index]).length()
		if span <= EPSILON:
			continue
		var cells := maxi(roundi(span / tile), 1)
		var steps := _steps(span / float(cells), height_fn)
		for cell: int in cells:
			for step: int in steps:
				var t0 := (float(cell) + float(step) / float(steps)) / float(cells)
				var t1 := (float(cell) + float(step + 1) / float(steps)) / float(cells)
				var v0 := uv_rect.position.y + uv_rect.size.y * (float(step) / float(steps))
				var v1 := uv_rect.position.y + uv_rect.size.y * (float(step + 1) / float(steps))
				var l0 := _at(left[index], left[index + 1], t0, height_fn, top)
				var l1 := _at(left[index], left[index + 1], t1, height_fn, top)
				var r0 := _at(right[index], right[index + 1], t0, height_fn, top)
				var r1 := _at(right[index], right[index + 1], t1, height_fn, top)
				# A lo ancho, la U recorre el rectángulo de izquierda a derecha.
				# La cinta también se subdivide **a lo ancho**: nueve metros de
				# calzada cruzando una loma con un 5 % de peralte dejaban la
				# cuerda un par de centímetros por debajo del terreno en el medio
				# —justo el grosor de la banda `[0,01; 0,08]` que mide el check—
				# y ahí no hay manera de distinguir la calzada del pasto.
				for lane: int in across:
					var u0 := float(lane) / float(across)
					var u1 := float(lane + 1) / float(across)
					_quad(builder,
							_lerp_lifted(l0, r0, u0, height_fn, top),
							_lerp_lifted(l0, r0, u1, height_fn, top),
							_lerp_lifted(l1, r1, u1, height_fn, top),
							_lerp_lifted(l1, r1, u0, height_fn, top),
							Vector2(lerpf(uv_rect.position.x, uv_rect.end.x, u0), v0),
							Vector2(lerpf(uv_rect.position.x, uv_rect.end.x, u1), v0),
							Vector2(lerpf(uv_rect.position.x, uv_rect.end.x, u1), v1),
							Vector2(lerpf(uv_rect.position.x, uv_rect.end.x, u0), v1),
							Vector3.UP)
	return _commit(builder)


## Parte [param polyline] en los tramos de cinta que hay que dibujar, recortando
## un hueco en cada nodo que la toca.
##
## [param cuts] es la lista de nodos sobre la polilínea, cada uno un diccionario
## `{at: float, radius: float}`: `at` es la distancia del primer vértice al
## centro del nodo y `radius` su radio de boca ([method node_radius]). No hace
## falta que vengan ordenados.
##
## El recorte es **exacto y no geométrico**: la boca de un nodo está siempre a
## `radius` metros de su centro medidos sobre el eje, así que cortar ahí deja el
## borde de la cinta justo sobre el lado del polígono del cruce. No queda hueco
## (la cinta llega) ni solape (no lo pasa), que es lo único que garantiza cero
## superficies coplanares.
##
## [param start_stub] y [param end_stub] son los metros que la calle sigue más
## allá de su primer y último vértice: es el **cabo declarado**, y ahí es donde
## va el [method closure]. [param from] y [param to] acotan el tramo que hay que
## cubrir sobre la polilínea; por defecto es toda ella, y la ruta los usa para
## quedarse sólo con el trozo que atraviesa el pueblo.
##
## Devuelve una polilínea por tramo. Una calle que no toca ningún nodo devuelve
## un solo tramo, que es como corre un plano sin grafo.
static func clip_ribbon_at_nodes(polyline: PackedVector3Array, cuts: Array[Dictionary],
		start_stub: float = 0.0, end_stub: float = 0.0,
		from: float = NAN, to: float = NAN) -> Array[PackedVector3Array]:
	var pieces: Array[PackedVector3Array] = []
	var line := _clean(polyline)
	if line.size() < 2:
		return pieces
	var total := length_of(line)
	var head := -start_stub if is_nan(from) else from
	var tail := total + end_stub if is_nan(to) else to

	var ordered := cuts.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["at"]) < float(b["at"]))

	var cursor := head
	for cut: Dictionary in ordered:
		var at := float(cut["at"])
		var radius := float(cut["radius"])
		if at + radius <= cursor:
			# Nodo completamente detrás del cursor: ya lo cubrió otro recorte.
			cursor = maxf(cursor, at + radius)
			continue
		if at - radius > tail:
			break
		var stop := minf(at - radius, tail)
		if stop - cursor > EPSILON:
			pieces.append(slice(line, cursor, stop))
		cursor = maxf(cursor, at + radius)
	if tail - cursor > EPSILON:
		pieces.append(slice(line, cursor, tail))
	return pieces


## Largo de una polilínea medido en XZ.
static func length_of(line: PackedVector3Array) -> float:
	var total := 0.0
	for index: int in maxi(line.size() - 1, 0):
		total += _flat(line[index + 1] - line[index]).length()
	return total


## Trozo de [param line] entre las distancias [param from] y [param to],
## conservando los vértices intermedios.
##
## Fuera del rango **extrapola** sobre la recta del tramo extremo, que es lo que
## hace falta para estirar una calle sobre su cabo sin inventar un quiebre.
static func slice(line: PackedVector3Array, from: float, to: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if line.size() < 2 or to <= from:
		return out
	out.append(_point_at(line, from))
	var travelled := 0.0
	for index: int in line.size() - 1:
		var span := _flat(line[index + 1] - line[index]).length()
		if span <= EPSILON:
			continue
		var mark := travelled + span
		if mark > from + EPSILON and mark < to - EPSILON:
			out.append(line[index + 1])
		travelled = mark
	out.append(_point_at(line, to))
	return _clean(out)


## Punto de [param line] a [param distance] metros de su primer vértice,
## extrapolando sobre la recta del tramo extremo fuera de rango.
static func _point_at(line: PackedVector3Array, distance: float) -> Vector3:
	if line.size() < 2:
		return line[0] if line.size() == 1 else Vector3.ZERO
	if distance <= 0.0:
		var head := _flat(line[1] - line[0])
		return line[0] + head.normalized() * distance
	var travelled := 0.0
	for index: int in line.size() - 1:
		var delta := _flat(line[index + 1] - line[index])
		var span := delta.length()
		if span <= EPSILON:
			continue
		if distance <= travelled + span:
			return line[index] + delta * ((distance - travelled) / span)
		travelled += span
	var last := line.size() - 1
	var tail := _flat(line[last] - line[last - 1])
	return line[last] + tail.normalized() * (distance - travelled)


# --------------------------------------------------------------------------
# Nodos
# --------------------------------------------------------------------------

## Radio de boca del nodo [param node]: a cuántos metros del centro se corta
## cada cinta incidente.
##
## Sale de la **esquina verdadera** entre cada par de calles consecutivas en
## orden angular —la intersección de las dos líneas municipales que se
## enfrentan— tomando la más lejana. Con dos calles a 90° y media franja `h` da
## exactamente `h`; a 35°, `h / tan(17,5°) ≈ 3,2 h`, que es por qué el contrato
## del grafo prohíbe ángulos más cerrados.
##
## Usar **un solo radio para todas las bocas** —y no uno por calle— es lo que
## hace convexo al polígono: el cruce pasa a ser la intersección de los
## semiplanos `p · uⱼ ≤ R`, y todos los extremos de boca caen sobre su borde.
static func node_radius(node: Dictionary) -> float:
	var arms := _arms(node)
	if arms.is_empty():
		return 0.0
	var widest := 0.0
	for arm: Dictionary in arms:
		widest = maxf(widest, float(arm["half"]))
	if arms.size() < 2:
		return widest * MOUTH_MIN
	var corners := 0.0
	for index: int in arms.size():
		var a: Dictionary = arms[index]
		var b: Dictionary = arms[(index + 1) % arms.size()]
		var corner: Variant = _corner(a, b)
		if corner == null:
			continue
		var point: Vector2 = corner
		corners = maxf(corners, maxf(point.dot(a["dir"] as Vector2),
				point.dot(b["dir"] as Vector2)))
	return clampf(maxf(corners + CHAMFER, widest * MOUTH_MIN),
			widest * MOUTH_MIN, widest * MOUTH_MAX)


## Polígono del cruce del nodo [param node], en XZ y en coordenadas del
## distrito.
##
## Es la envolvente convexa de las **bocas**: por cada calle incidente, los dos
## extremos del corte recto de su cinta. Como todas las bocas están al mismo
## radio (ver [method node_radius]), la envolvente es exactamente la
## intersección de las medias franjas incidentes, cada extremo de boca es un
## vértice y los lados que van de una boca a la siguiente son el **chaflán** de
## la esquina.
##
## Un nodo de grado menor que dos no tiene cruce: devuelve vacío. Es el cabo, y
## lo que va ahí es un [method closure].
static func node_polygon(node: Dictionary) -> PackedVector2Array:
	var arms := _arms(node)
	if arms.size() < 2:
		return PackedVector2Array()
	var centre := _flat_2d(node.get("pos", Vector3.ZERO))
	# El radio guardado manda sobre el recalculado. Quien resuelve el diseño
	# (`TownPlanner`, WP-T3) ya lo dejó escrito en el nodo, y recalcularlo acá
	# abriría la puerta a que la boca del polígono y el corte de la cinta —que
	# lee el mismo campo— cayeran en dos sitios distintos por un bit de coma
	# flotante. Un solo número, leído de un solo lugar.
	var radius := float(node.get("radius", 0.0))
	if radius <= 0.0:
		radius = node_radius(node)
	var points := PackedVector2Array()
	for arm: Dictionary in arms:
		var dir: Vector2 = arm["dir"]
		var side := Vector2(-dir.y, dir.x) * float(arm["half"])
		var mouth := centre + dir * radius
		points.append(mouth - side)
		points.append(mouth + side)
	return _hull(points)


## Malla del polígono [param poly], apoyada sobre el terreno a [param top]
## metros. Es la que hornea el cruce de un nodo y cualquier otro parche de
## asfalto liso.
##
## El polígono se triangula en **abanico desde el baricentro** y no desde un
## vértice: con relieve, el abanico desde un vértice deja un lado largo que
## corta la loma por la cuerda y se despega del terreno en el medio.
static func polygon_mesh(poly: PackedVector2Array, height_fn: Callable, top: float,
		uv_rect: Rect2 = ASPHALT_UV) -> ArrayMesh:
	if poly.size() < 3:
		return null
	var centre := Vector2.ZERO
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector2 in poly:
		centre += point
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	centre /= float(poly.size())
	var size := Vector2(maxf(high.x - low.x, 0.001), maxf(high.y - low.y, 0.001))

	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in poly.size():
		var a := poly[index]
		var b := poly[(index + 1) % poly.size()]
		_fan(builder, centre, a, b, height_fn, top, low, size, uv_rect)
	return _commit(builder)


## Un gajo del abanico `centro → a → b`, subdividido con el mismo paso que el
## resto del viario.
##
## El abanico pelado —un triángulo por lado del polígono— era plano por dentro,
## y sobre relieve eso se nota: el polígono de un cruce mide hasta catorce
## metros de punta a punta, así que un solo triángulo lo cruza como una tapa. Al
## re-hornear el pueblo con el terreno debajo, esa tapa dejaba la calzada hasta
## **30 cm enterrada** en un borde del cruce y **36 cm en el aire** en el otro,
## que es cinco veces la banda de `[0,01; 0,08]` m que pide el criterio 1. Con
## el gajo subdividido cada [constant MAX_STEP] metros —en filas paralelas al
## lado, que es como se subdivide un triángulo sin dejar vértices colgados— el
## cruce sigue al terreno igual que la cinta que lo alimenta.
static func _fan(builder: SurfaceTool, centre: Vector2, a: Vector2, b: Vector2,
		height_fn: Callable, top: float, low: Vector2, size: Vector2,
		uv_rect: Rect2) -> void:
	var span := maxf(maxf(centre.distance_to(a), centre.distance_to(b)),
			a.distance_to(b))
	var rows := _steps(span, height_fn)
	for row: int in rows:
		var lower := _fan_row(centre, a, b, row, rows)
		var upper := _fan_row(centre, a, b, row + 1, rows)
		for slot: int in lower.size():
			_fan_tri(builder, lower[slot], upper[slot], upper[slot + 1],
					height_fn, top, low, size, uv_rect)
			if slot + 1 < lower.size():
				_fan_tri(builder, lower[slot], upper[slot + 1], lower[slot + 1],
						height_fn, top, low, size, uv_rect)


## Los `level + 1` puntos de la fila [param level] del gajo, de `a` hacia `b`.
static func _fan_row(centre: Vector2, a: Vector2, b: Vector2, level: int,
		rows: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var t := float(level) / float(maxi(rows, 1))
	var from := centre.lerp(a, t)
	var to := centre.lerp(b, t)
	if level == 0:
		out.append(centre)
		return out
	for slot: int in level + 1:
		out.append(from.lerp(to, float(slot) / float(level)))
	return out


static func _fan_tri(builder: SurfaceTool, a: Vector2, b: Vector2, c: Vector2,
		height_fn: Callable, top: float, low: Vector2, size: Vector2,
		uv_rect: Rect2) -> void:
	_tri(builder, _lift(a, height_fn, top), _lift(b, height_fn, top),
			_lift(c, height_fn, top), _stretch_uv(a, low, size, uv_rect),
			_stretch_uv(b, low, size, uv_rect), _stretch_uv(c, low, size, uv_rect),
			Vector3.UP)


# --------------------------------------------------------------------------
# Veredas
# --------------------------------------------------------------------------

## Anillo de vereda del polígono de manzana [param polygon], **sólo en los lados
## que dan a una calle**.
##
## [param sides_with_street] lleva un valor por lado, en el orden de los
## vértices: el lado `i` va de `polygon[i]` a `polygon[(i + 1) % n]` y un valor
## negativo quiere decir «este lado no da a ninguna calle». Es el mismo contrato
## que [member TownPlan.block_streets], y es lo que evita el defecto de P2b:
## vereda por dentro de la manzana, donde nadie camina.
##
## [param inner] y [param outer] son desplazamientos **con signo desde el lado
## del polígono, positivos hacia afuera** (hacia la calle). Con la línea
## municipal como polígono —que es lo que da [method TownPlan.block_polygon]— la
## vereda va de `0` a `ancho_de_vereda`.
##
## La cara vertical del cordón, de [param curb] metros, se levanta sobre el
## borde exterior: es la que separa la vereda de la calzada y la que hace que a
## nivel de dron se vea dónde termina el asfalto. Los extremos de cada tramo se
## tapan, y dos lados consecutivos con calle comparten miter: las esquinas
## quedan cerradas.
static func ring(polygon: PackedVector2Array, sides_with_street: PackedInt32Array,
		inner: float, outer: float, top: float, curb: float, height_fn: Callable,
		outer_by_side: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
	var count := polygon.size()
	if count < 3 or sides_with_street.size() < count or outer <= inner:
		return null
	var winding := 1.0 if _signed_area(polygon) >= 0.0 else -1.0

	var runs := _street_runs(sides_with_street)
	if runs.is_empty():
		return null

	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for run: PackedInt32Array in runs:
		var closed := run.size() == count
		# Vértices del tramo: cada lado aporta su vértice inicial y, si el tramo
		# no da la vuelta entera, el último aporta además el final.
		var corners: PackedInt32Array = PackedInt32Array()
		for side: int in run:
			corners.append(side)
		if not closed:
			corners.append((run[run.size() - 1] + 1) % count)

		var rail_in := PackedVector2Array()
		var rail_out := PackedVector2Array()
		for slot: int in corners.size():
			# Lados del tramo que tocan este vértice. Fuera del tramo valen `-1`
			# y la normal se toma del único lado que sigue: es el corte recto con
			# el que la vereda termina donde termina la calle.
			var before := -1
			var after := -1
			if slot > 0:
				before = run[slot - 1]
			elif closed:
				before = run[run.size() - 1]
			if slot < run.size():
				after = run[slot]
			elif closed:
				after = run[0]
			var vertex := corners[slot]
			rail_in.append(_offset_corner(polygon, vertex, before, after, winding,
					inner, inner))
			rail_out.append(_offset_corner(polygon, vertex, before, after, winding,
					_side_outer(before, outer, outer_by_side),
					_side_outer(after, outer, outer_by_side)))

		_ring_band(builder, rail_in, rail_out, top, curb, height_fn, closed)
		if not closed:
			_ring_cap(builder, rail_in[0], rail_out[0], top, curb, height_fn, true)
			_ring_cap(builder, rail_in[rail_in.size() - 1], rail_out[rail_out.size() - 1],
					top, curb, height_fn, false)
	return _commit(builder)


# --------------------------------------------------------------------------
# Cierres de cabo
# --------------------------------------------------------------------------

## Cierre del cabo de una calle: lo que hay al final de una calle que no llega a
## ningún lado.
##
## [param kind] es uno de [constant CLOSURE_KINDS]. [param dir] es la dirección
## de la calle **saliendo** del pueblo y [param width] el ancho de calzada que
## hay que tapar. Toda la geometría son cajas: entre 36 y 84 triángulos, bien
## por debajo del tope de 200 del encargo.
##
## No hay cierre `none`: devuelve `null` a propósito, para que quien lo pida
## sepa que el diseño declaró «acá no hay nada» y no confunda el vacío con un
## error.
static func closure(kind: StringName, node_pos: Vector3, dir: Vector3, width: float,
		height_fn: Callable) -> ArrayMesh:
	var forward := _flat(dir)
	if forward.length() < EPSILON or width <= 0.0:
		return null
	forward = forward.normalized()
	var across := Vector3(-forward.z, 0.0, forward.x)
	var ground := _height(node_pos.x, node_pos.z, height_fn)
	var origin := Vector3(node_pos.x, ground, node_pos.z)
	var half := width * 0.5

	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		KIND_GATE:
			# Tranquera: dos postes y tres travesaños. 5 cajas = 60 triángulos.
			for side: float in [-1.0, 1.0]:
				_box(builder, origin + across * (half * side), forward, across,
						Vector3(0.20, 1.40, 0.20))
			for level: float in [0.40, 0.80, 1.20]:
				_box(builder, origin + Vector3.UP * level, forward, across,
						Vector3(0.10, 0.10, width), true)
		KIND_CULVERT:
			# Alcantarilla: cabecera de hormigón y dos aletas. 3 cajas.
			_box(builder, origin + Vector3.UP * 0.35, forward, across,
					Vector3(0.45, 0.70, width * 0.85), true)
			for side: float in [-1.0, 1.0]:
				_box(builder, origin + across * (half * side) - forward * 0.55
						+ Vector3.UP * 0.25, forward, across,
						Vector3(1.30, 0.50, 0.35))
		KIND_FENCE:
			# Alambrado: tres postes y tres hilos. 6 cajas = 72 triángulos.
			for side: float in [-1.0, 0.0, 1.0]:
				_box(builder, origin + across * (half * side) + Vector3.UP * 0.05,
						forward, across, Vector3(0.14, 1.20, 0.14))
			for level: float in [0.40, 0.70, 1.00]:
				_box(builder, origin + Vector3.UP * level, forward, across,
						Vector3(0.05, 0.05, width), true)
		_:
			return null
	return _commit(builder)


# --------------------------------------------------------------------------
# Fusión
# --------------------------------------------------------------------------

## Funde [param meshes] en una sola [ArrayMesh] con **una superficie por
## material**.
##
## Es lo que convierte cuarenta cintas y doce cruces en un lote de dibujo. Los
## nulos se saltean, así que quien las junta puede pedir piezas que a veces no
## existen sin filtrar antes.
static func merge(meshes: Array) -> ArrayMesh:
	var order: Array[int] = []
	var groups: Dictionary[int, Array] = {}
	var materials: Dictionary[int, Material] = {}
	for entry: Variant in meshes:
		var mesh := entry as ArrayMesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			var key := material.get_instance_id() if material != null else 0
			if not groups.has(key):
				groups[key] = []
				materials[key] = material
				order.append(key)
			groups[key].append({"mesh": mesh, "surface": surface})

	var out := ArrayMesh.new()
	for key: int in order:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for piece: Dictionary in groups[key]:
			builder.append_from(piece["mesh"], int(piece["surface"]), Transform3D.IDENTITY)
		builder.index()
		var baked := builder.commit()
		if baked == null or baked.get_surface_count() == 0:
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, baked.surface_get_arrays(0))
		out.surface_set_material(out.get_surface_count() - 1, materials[key])
	return out if out.get_surface_count() > 0 else null


## Pone [param material] en todas las superficies de [param mesh] y lo devuelve.
## Atajo para las mallas recién horneadas, que salen sin material.
static func paint(mesh: ArrayMesh, material: Material) -> ArrayMesh:
	if mesh == null:
		return null
	for surface: int in mesh.get_surface_count():
		mesh.surface_set_material(surface, material)
	return mesh


# --------------------------------------------------------------------------
# Medidas
# --------------------------------------------------------------------------

## Cuántos triángulos tiene [param mesh]. Lo usan los checks y el banco.
static func triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
				if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if not indices.is_empty():
			total += indices.size() / 3
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += vertices.size() / 3
	return total


## Triángulos de [param mesh] en XZ, como listas de tres [Vector2] más su `y`
## medio. Es la forma en que los checks preguntan «¿hay calzada debajo de este
## punto?» sin instanciar nada.
##
## Devuelve un [Array] de diccionarios `{a, b, c, y, min, max}`, con `min` y
## `max` la caja envolvente del triángulo en XZ para poder descartarlo barato.
static func flat_triangles(mesh: Mesh) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if mesh == null:
		return found
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
				if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices = PackedInt32Array()
			for slot: int in vertices.size():
				indices.append(slot)
		var slot := 0
		while slot + 2 < indices.size():
			var a := vertices[indices[slot]]
			var b := vertices[indices[slot + 1]]
			var c := vertices[indices[slot + 2]]
			slot += 3
			var flat_a := Vector2(a.x, a.z)
			var flat_b := Vector2(b.x, b.z)
			var flat_c := Vector2(c.x, c.z)
			# Las caras verticales no cubren nada en planta.
			if absf((flat_b - flat_a).cross(flat_c - flat_a)) < 0.0001:
				continue
			found.append({
				"a": flat_a, "b": flat_b, "c": flat_c,
				# Las tres alturas, **no su promedio**: la superficie se
				# interpola con coordenadas baricéntricas. Con el mundo plano de
				# P2b el promedio era exacto y por eso alcanzaba; sobre relieve
				# un triángulo de cinta mide ocho metros de ancho y con un 5 %
				# de peralte el promedio se aparta 19 cm del plano real, que es
				# más del doble de la banda `[0,01; 0,08]` que mide el check.
				"ya": a.y, "yb": b.y, "yc": c.y,
				"min": Vector2(minf(flat_a.x, minf(flat_b.x, flat_c.x)),
						minf(flat_a.y, minf(flat_b.y, flat_c.y))),
				"max": Vector2(maxf(flat_a.x, maxf(flat_b.x, flat_c.x)),
						maxf(flat_a.y, maxf(flat_b.y, flat_c.y))),
			})
	return found


## Rejilla de celdas de [param cell] metros sobre [param triangles], para poder
## preguntar por la cobertura de decenas de miles de puntos sin recorrer la
## malla entera cada vez.
##
## Devuelve `{Vector2i: PackedInt32Array}` con los índices de los triángulos que
## tocan cada celda. Un triángulo grande entra en varias.
static func index_triangles(triangles: Array[Dictionary], cell: float = 4.0) -> Dictionary:
	var grid: Dictionary = {}
	for slot: int in triangles.size():
		var low: Vector2 = triangles[slot]["min"]
		var high: Vector2 = triangles[slot]["max"]
		var from := Vector2i(floori(low.x / cell), floori(low.y / cell))
		var to := Vector2i(floori(high.x / cell), floori(high.y / cell))
		for gx: int in range(from.x, to.x + 1):
			for gz: int in range(from.y, to.y + 1):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = PackedInt32Array()
				var bucket: PackedInt32Array = grid[key]
				bucket.append(slot)
				grid[key] = bucket
	return grid


## Como [method coverage] pero contra la rejilla de [method index_triangles]: se
## miran sólo los triángulos de la celda del punto y de las ocho vecinas.
static func coverage_indexed(triangles: Array[Dictionary], grid: Dictionary, cell: float,
		point: Vector2, margin: float = 0.002) -> int:
	var hits := 0
	var seen: Dictionary[int, bool] = {}
	var home := Vector2i(floori(point.x / cell), floori(point.y / cell))
	for gx: int in range(home.x - 1, home.x + 2):
		for gz: int in range(home.y - 1, home.y + 2):
			var key := Vector2i(gx, gz)
			if not grid.has(key):
				continue
			for slot: int in (grid[key] as PackedInt32Array):
				if seen.has(slot):
					continue
				seen[slot] = true
				var triangle := triangles[slot]
				if _inside_triangle(point, triangle["a"], triangle["b"], triangle["c"],
						margin):
					hits += 1
	return hits


## Cuántos triángulos de [param triangles] cubren [param point] en XZ, con
## [param margin] metros de holgura **hacia adentro**.
##
## El margen positivo es lo que evita contar dos veces un punto que cae justo
## sobre el borde compartido de dos triángulos vecinos, que es lo normal en una
## cinta y no es un solape. Un resultado mayor que uno con margen positivo sí lo
## es: dos asfaltos coplanares.
static func coverage(triangles: Array[Dictionary], point: Vector2,
		margin: float = 0.002) -> int:
	var hits := 0
	# El prefiltro se ensancha con el **valor absoluto** del margen: con un margen
	# negativo —el que pregunta «¿está cubierto, aunque sea justo sobre el
	# borde?»— restarlo achicaría la caja y descartaría justo los triángulos que
	# hay que mirar.
	var pad := absf(margin)
	for triangle: Dictionary in triangles:
		var low: Vector2 = triangle["min"]
		var high: Vector2 = triangle["max"]
		if point.x < low.x - pad or point.x > high.x + pad:
			continue
		if point.y < low.y - pad or point.y > high.y + pad:
			continue
		if _inside_triangle(point, triangle["a"], triangle["b"], triangle["c"], margin):
			hits += 1
	return hits


## `y` de la superficie bajo [param point] usando la rejilla, o `NAN`.
static func surface_y_indexed(triangles: Array[Dictionary], grid: Dictionary, cell: float,
		point: Vector2) -> float:
	var home := Vector2i(floori(point.x / cell), floori(point.y / cell))
	for gx: int in range(home.x - 1, home.x + 2):
		for gz: int in range(home.y - 1, home.y + 2):
			var key := Vector2i(gx, gz)
			if not grid.has(key):
				continue
			for slot: int in (grid[key] as PackedInt32Array):
				var triangle := triangles[slot]
				if _inside_triangle(point, triangle["a"], triangle["b"], triangle["c"],
						-0.002):
					return _triangle_y(triangle, point)
	return NAN


## `y` de la superficie de [param triangles] bajo [param point], o `NAN` si no
## hay ninguna. Interpola con coordenadas baricéntricas.
static func surface_y(triangles: Array[Dictionary], point: Vector2) -> float:
	for triangle: Dictionary in triangles:
		var low: Vector2 = triangle["min"]
		var high: Vector2 = triangle["max"]
		if point.x < low.x or point.x > high.x or point.y < low.y or point.y > high.y:
			continue
		if _inside_triangle(point, triangle["a"], triangle["b"], triangle["c"], -0.002):
			return _triangle_y(triangle, point)
	return NAN


## Punto entre [param a] y [param b] apoyado en el terreno: la interpolación
## decide **dónde**, y la altura la vuelve a preguntar el terreno.
static func _lerp_lifted(a: Vector3, b: Vector3, t: float, height_fn: Callable,
		top: float) -> Vector3:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	return _lift(Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t)), height_fn, top)


## Altura del triángulo [param triangle] en [param point], por coordenadas
## baricéntricas. Con el punto fuera del triángulo la extrapolación sigue siendo
## el plano del triángulo, que es lo que quiere quien llega acá desde
## [method _inside_triangle] con tolerancia.
static func _triangle_y(triangle: Dictionary, point: Vector2) -> float:
	var a: Vector2 = triangle["a"]
	var b: Vector2 = triangle["b"]
	var c: Vector2 = triangle["c"]
	var v0 := b - a
	var v1 := c - a
	var denominator := v0.cross(v1)
	if absf(denominator) < 0.000001:
		return (float(triangle["ya"]) + float(triangle["yb"])
				+ float(triangle["yc"])) / 3.0
	var v2 := point - a
	var beta := v2.cross(v1) / denominator
	var gamma := v0.cross(v2) / denominator
	var alpha := 1.0 - beta - gamma
	var value := alpha * float(triangle["ya"]) + beta * float(triangle["yb"])
	return value + gamma * float(triangle["yc"])


# --------------------------------------------------------------------------
# Interno: polilíneas y rieles
# --------------------------------------------------------------------------

## Copia de [param line] aplastada a `y = 0` y sin vértices repetidos.
static func _clean(line: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point: Vector3 in line:
		var flat := _flat(point)
		if out.is_empty() or _flat(flat - out[out.size() - 1]).length() > EPSILON:
			out.append(flat)
	return out


## Los dos rieles de la cinta: izquierdo y derecho, con miter en cada vértice
## interior y corte recto en los extremos.
static func _miter_rails(line: PackedVector3Array, half_width: float) -> Array:
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for index: int in line.size():
		var before := line[maxi(index - 1, 0)]
		var after := line[mini(index + 1, line.size() - 1)]
		var incoming := _flat(line[index] - before)
		var outgoing := _flat(after - line[index])
		if incoming.length() <= EPSILON:
			incoming = outgoing
		if outgoing.length() <= EPSILON:
			outgoing = incoming
		incoming = incoming.normalized()
		outgoing = outgoing.normalized()
		var normal_in := Vector3(incoming.z, 0.0, -incoming.x)
		var normal_out := Vector3(outgoing.z, 0.0, -outgoing.x)
		var bisector := normal_in + normal_out
		var offset := normal_out * half_width
		if bisector.length() > EPSILON:
			bisector = bisector.normalized()
			var cosine := bisector.dot(normal_out)
			var reach := half_width / maxf(cosine, 1.0 / MITER_LIMIT)
			offset = bisector * reach
		left.append(line[index] + offset)
		right.append(line[index] - offset)
	return [left, right]


## Punto a fracción [param t] del tramo `a → b`, levantado al terreno.
static func _at(a: Vector3, b: Vector3, t: float, height_fn: Callable, top: float) -> Vector3:
	var point := a.lerp(b, t)
	return Vector3(point.x, _height(point.x, point.z, height_fn) + top, point.z)


## Un punto `(u, v)` de `[0, 1]²` llevado a la **zona lisa** de
## [constant ASPHALT_UV]: el parche recortado [constant SMOOTH_INSET] por cada
## lado, o sea lejos de la frontera con la baldosa vecina del atlas.
static func _smooth_uv(u: float, v: float) -> Vector2:
	var keep := 1.0 - SMOOTH_INSET * 2.0
	return Vector2(
			ASPHALT_UV.position.x + ASPHALT_UV.size.x * (SMOOTH_INSET + clampf(u, 0.0, 1.0) * keep),
			ASPHALT_UV.position.y + ASPHALT_UV.size.y * (SMOOTH_INSET + clampf(v, 0.0, 1.0) * keep))


## Levanta un punto de XZ al terreno.
static func _lift(point: Vector2, height_fn: Callable, top: float) -> Vector3:
	return Vector3(point.x, _height(point.x, point.y, height_fn) + top, point.y)


## En cuántos pasos se parte un tramo de [param span] metros.
##
## Con terreno hay que seguir el relieve y el paso lo manda [constant MAX_STEP];
## **sin** terreno el tramo es plano y subdividirlo sólo suma triángulos que
## dibujan exactamente el mismo plano. Con el mundo plano de P2c esto ahorra tres
## cuartos de la malla del viario, y en cuanto WP-T4 cablee [TownTerrain] la
## subdivisión vuelve sola.
static func _steps(span: float, height_fn: Callable, step: float = MAX_STEP) -> int:
	if height_fn.is_null() or not height_fn.is_valid():
		return 1
	return maxi(ceili(span / maxf(step, 0.01)), 1)


## Altura del terreno en `(x, z)`. Sin [param height_fn] válido, el mundo es
## plano: es como corre hasta que WP-T2 entregue [TownTerrain].
static func _height(x: float, z: float, height_fn: Callable) -> float:
	if height_fn.is_null() or not height_fn.is_valid():
		return 0.0
	return float(height_fn.call(x, z))


# --------------------------------------------------------------------------
# Interno: nodos
# --------------------------------------------------------------------------

## Brazos del nodo, en orden angular: `{dir: Vector2, half: float}`.
static func _arms(node: Dictionary) -> Array[Dictionary]:
	var angles: PackedFloat32Array = node.get("angles", PackedFloat32Array())
	var halves: PackedFloat32Array = node.get("half_widths", PackedFloat32Array())
	var found: Array[Dictionary] = []
	for index: int in angles.size():
		var half := halves[index] if index < halves.size() else 0.0
		if half <= 0.0:
			continue
		found.append({
			"angle": fposmod(angles[index], TAU),
			"dir": Vector2(cos(angles[index]), sin(angles[index])),
			"half": half,
		})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["angle"]) < float(b["angle"]))
	return found


## Esquina entre dos brazos consecutivos: el corte de la línea municipal
## izquierda de [param a] con la derecha de [param b]. `null` si son paralelos.
static func _corner(a: Dictionary, b: Dictionary) -> Variant:
	var dir_a: Vector2 = a["dir"]
	var dir_b: Vector2 = b["dir"]
	var normal_a := Vector2(-dir_a.y, dir_a.x)
	var normal_b := Vector2(-dir_b.y, dir_b.x)
	var target_a := float(a["half"])
	var target_b := -float(b["half"])
	var determinant := normal_a.x * normal_b.y - normal_a.y * normal_b.x
	if absf(determinant) < 0.000001:
		return null
	return Vector2(
			(target_a * normal_b.y - target_b * normal_a.y) / determinant,
			(normal_a.x * target_b - normal_b.x * target_a) / determinant)


## Envolvente convexa (cadena monótona de Andrew), en sentido antihorario.
static func _hull(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var sorted: Array[Vector2] = []
	for point: Vector2 in points:
		sorted.append(point)
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if not is_equal_approx(a.x, b.x):
			return a.x < b.x
		return a.y < b.y)

	var lower: Array[Vector2] = []
	for point: Vector2 in sorted:
		while lower.size() >= 2 and (lower[lower.size() - 1] - lower[lower.size() - 2]) \
				.cross(point - lower[lower.size() - 2]) <= 0.0:
			lower.remove_at(lower.size() - 1)
		lower.append(point)
	var upper: Array[Vector2] = []
	for index: int in range(sorted.size() - 1, -1, -1):
		var point := sorted[index]
		while upper.size() >= 2 and (upper[upper.size() - 1] - upper[upper.size() - 2]) \
				.cross(point - upper[upper.size() - 2]) <= 0.0:
			upper.remove_at(upper.size() - 1)
		upper.append(point)
	lower.remove_at(lower.size() - 1)
	upper.remove_at(upper.size() - 1)
	var hull := PackedVector2Array()
	for point: Vector2 in lower:
		hull.append(point)
	for point: Vector2 in upper:
		hull.append(point)
	return hull


# --------------------------------------------------------------------------
# Interno: anillos
# --------------------------------------------------------------------------

## Tramos maximales de lados consecutivos con calle. Si **todos** los lados dan a
## una calle devuelve un solo tramo con los `n` lados, que es el anillo cerrado.
static func _street_runs(sides: PackedInt32Array) -> Array[PackedInt32Array]:
	var count := sides.size()
	var runs: Array[PackedInt32Array] = []
	var with_street := 0
	for side: int in sides:
		if side >= 0:
			with_street += 1
	if with_street == 0:
		return runs
	if with_street == count:
		var whole := PackedInt32Array()
		for index: int in count:
			whole.append(index)
		runs.append(whole)
		return runs

	# Se arranca en un lado sin calle para que ningún tramo quede partido por el
	# corte del array.
	var start := 0
	for index: int in count:
		if sides[index] < 0:
			start = index
			break
	var current := PackedInt32Array()
	for step: int in count:
		var side := (start + step) % count
		if sides[side] >= 0:
			current.append(side)
			continue
		if not current.is_empty():
			runs.append(current)
			current = PackedInt32Array()
	if not current.is_empty():
		runs.append(current)
	return runs


## Ancho exterior del lado [param side]: el propio si el anillo declara uno, o
## el general.
static func _side_outer(side: int, outer: float, by_side: PackedFloat32Array) -> float:
	if side < 0 or side >= by_side.size():
		return outer
	return by_side[side]


## Punto del riel en el vértice [param vertex], donde se encuentran los lados
## [param before] y [param after] corridos [param off_before] y
## [param off_after] metros hacia afuera.
##
## Se resuelve **cortando las dos rectas desplazadas** y no con la bisectriz de
## las normales: la bisectriz sólo vale cuando los dos desplazamientos son
## iguales, y dos lados de la misma manzana pueden dar a calles con veredas de
## distinto ancho. El corte de rectas da el mismo resultado en el caso parejo y
## el correcto en el desparejo, que es lo que cierra la esquina sin escalón.
##
## Un lado negativo quiere decir «acá el tramo de vereda se corta»: se usa la
## normal del único lado que sigue, que es el corte recto con el que la vereda
## termina donde termina la calle.
static func _offset_corner(poly: PackedVector2Array, vertex: int, before: int, after: int,
		winding: float, off_before: float, off_after: float) -> Vector2:
	var normal_before := _edge_normal(poly, before, winding)
	var normal_after := _edge_normal(poly, after, winding)
	var corner := poly[vertex % poly.size()]
	if normal_before == Vector2.ZERO:
		return corner + normal_after * off_after
	if normal_after == Vector2.ZERO:
		return corner + normal_before * off_before
	var dir_before := Vector2(normal_before.y, -normal_before.x)
	var dir_after := Vector2(normal_after.y, -normal_after.x)
	var determinant := dir_before.cross(dir_after)
	var reach := maxf(absf(off_before), absf(off_after)) * MITER_LIMIT
	if absf(determinant) < 0.0001:
		return corner + normal_after * off_after
	var base_before := corner + normal_before * off_before
	var base_after := corner + normal_after * off_after
	var t := (base_after - base_before).cross(dir_after) / determinant
	var point := base_before + dir_before * t
	if corner.distance_to(point) > reach:
		return corner + normal_after * off_after
	return point


## Normal exterior unitaria del lado [param edge], o cero si el índice no vale.
static func _edge_normal(poly: PackedVector2Array, edge: int, winding: float) -> Vector2:
	if edge < 0 or poly.size() < 2:
		return Vector2.ZERO
	var a := poly[edge % poly.size()]
	var b := poly[(edge + 1) % poly.size()]
	var delta := b - a
	var length := delta.length()
	if length < EPSILON:
		return Vector2.ZERO
	return Vector2(delta.y, -delta.x) / length * winding


## Cara superior de la vereda y su cordón, a lo largo de los dos rieles.
##
## Con [param closed] el anillo da la vuelta entera y el último riel empalma con
## el primero; si no, el recorrido termina en el penúltimo vértice y las dos
## puntas las tapa [method _ring_cap].
##
## ## La UV corre a lo largo del tramo entero, no por celda
##
## Hasta WP-T4 **cada celda repetía el parche entero**, y eso deja dos
## artefactos que en la captura del checkpoint se leyeron como «dientes» en el
## borde exterior de cada vereda:
##
## 1. El borde exterior de la celda caía exactamente sobre `ASPHALT_UV.end.x`,
##    o sea sobre la frontera del parche en el atlas, y el filtrado traía los
##    téxeles de la baldosa vecina —las bandas anaranjadas del cordón pintado—.
## 2. La UV volvía de golpe de `end` a `position` en cada junta de celda, cada
##    1,25 m. Ahí la derivada de la UV se dispara, el GPU elige una mipmap
##    mucho más gruesa que en el resto de la celda y el tono salta: celda por
##    medio salía clara y oscura, que es el diente regular que se veía.
##
## Las dos se arreglan con lo mismo: la coordenada a lo largo se toma de la
## **longitud acumulada del tramo** —una sola rampa de 0 a 1, sin vueltas— y se
## mapea dentro del parche ya recortado por [constant SMOOTH_INSET]. El parche
## es liso, así que estirarlo a lo largo de la manzana no se nota; lo que se
## nota es el borde que ya no está. Mapear por posición del mundo con un módulo
## fue el primer intento y rompe en cuanto un triángulo cruza el límite del
## módulo: la UV va para atrás adentro del triángulo y sale un moiré de franjas
## diagonales.
static func _ring_band(builder: SurfaceTool, rail_in: PackedVector2Array,
		rail_out: PackedVector2Array, top: float, curb: float,
		height_fn: Callable, closed: bool) -> void:
	var edges := rail_in.size() if closed else rail_in.size() - 1
	# Longitud acumulada del riel interior hasta el arranque de cada lado, y
	# total del tramo: de ahí sale la rampa continua de la UV.
	var reach := PackedFloat32Array()
	var total := 0.0
	for index: int in maxi(edges, 0):
		reach.append(total)
		total += rail_in[(index + 1) % rail_in.size()].distance_to(rail_in[index])
	if total < EPSILON:
		return
	for index: int in maxi(edges, 0):
		var next := (index + 1) % rail_in.size()
		var span := rail_in[next].distance_to(rail_in[index])
		if span < EPSILON:
			continue
		var steps := _steps(span, height_fn)
		for step: int in steps:
			var t0 := float(step) / float(steps)
			var t1 := float(step + 1) / float(steps)
			var i0 := rail_in[index].lerp(rail_in[next], t0)
			var i1 := rail_in[index].lerp(rail_in[next], t1)
			var o0 := rail_out[index].lerp(rail_out[next], t0)
			var o1 := rail_out[index].lerp(rail_out[next], t1)
			var v0 := (reach[index] + span * t0) / total
			var v1 := (reach[index] + span * t1) / total
			# Cara de arriba: la U cruza la vereda y la V corre por el tramo.
			_quad(builder, _lift(i0, height_fn, top), _lift(o0, height_fn, top),
					_lift(o1, height_fn, top), _lift(i1, height_fn, top),
					_smooth_uv(0.0, v0), _smooth_uv(1.0, v0),
					_smooth_uv(1.0, v1), _smooth_uv(0.0, v1),
					Vector3.UP)
			# Cordón: cara vertical mirando a la calzada, o sea hacia afuera del
			# riel interior. Sólo una tajada angosta del parche a lo alto: son
			# quince centímetros y el parche entero le daría una mipmap gruesa.
			if curb <= 0.0:
				continue
			var outward := o0 - i0
			if outward.length() < EPSILON:
				continue
			outward = outward.normalized()
			var high := 0.5 + CURB_UV_BAND
			var low := 0.5 - CURB_UV_BAND
			_quad(builder, _lift(o0, height_fn, top), _lift(o0, height_fn, top - curb),
					_lift(o1, height_fn, top - curb), _lift(o1, height_fn, top),
					_smooth_uv(v0, high), _smooth_uv(v0, low),
					_smooth_uv(v1, low), _smooth_uv(v1, high),
					Vector3(outward.x, 0.0, outward.y))


## Tapa vertical del extremo de un tramo de vereda.
static func _ring_cap(builder: SurfaceTool, inner: Vector2, outer: Vector2, top: float,
		curb: float, height_fn: Callable, head: bool) -> void:
	if curb <= 0.0 or inner.distance_to(outer) < EPSILON:
		return
	var along := (outer - inner).normalized()
	var facing := Vector3(-along.y, 0.0, along.x)
	if head:
		facing = -facing
	var high := 0.5 + CURB_UV_BAND
	var low := 0.5 - CURB_UV_BAND
	_quad(builder, _lift(inner, height_fn, top), _lift(outer, height_fn, top),
			_lift(outer, height_fn, top - curb), _lift(inner, height_fn, top - curb),
			_smooth_uv(0.0, high), _smooth_uv(1.0, high),
			_smooth_uv(1.0, low), _smooth_uv(0.0, low), facing)


# --------------------------------------------------------------------------
# Interno: primitivas
# --------------------------------------------------------------------------

## Caja de [param size] metros centrada en [param centre], con su eje Z sobre
## [param across] y su X sobre [param forward].
##
## Con [param centred] falso la caja apoya sobre `centre.y` en vez de centrarse:
## es lo que quiere un poste, que se clava en el suelo.
static func _box(builder: SurfaceTool, centre: Vector3, forward: Vector3, across: Vector3,
		size: Vector3, centred: bool = false) -> void:
	var half_x := size.x * 0.5
	var half_y := size.y * 0.5
	var half_z := size.z * 0.5
	var middle := centre if centred else centre + Vector3.UP * half_y
	var corners: Array[Vector3] = []
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for sx: float in [-1.0, 1.0]:
				corners.append(middle + forward * (half_x * sx)
						+ Vector3.UP * (half_y * sy) + across * (half_z * sz))
	# Índices de las seis caras, en el orden en que se apilaron las esquinas.
	var faces: Array = [
		[4, 5, 7, 6, Vector3.UP],
		[2, 3, 1, 0, -Vector3.UP],
		[1, 3, 7, 5, forward],
		[2, 0, 4, 6, -forward],
		[3, 2, 6, 7, across],
		[0, 1, 5, 4, -across],
	]
	for face: Array in faces:
		var a: Vector3 = corners[int(face[0])]
		var b: Vector3 = corners[int(face[1])]
		var c: Vector3 = corners[int(face[2])]
		var d: Vector3 = corners[int(face[3])]
		var normal: Vector3 = face[4]
		_quad(builder, a, b, c, d,
				ASPHALT_UV.position, Vector2(ASPHALT_UV.end.x, ASPHALT_UV.position.y),
				ASPHALT_UV.end, Vector2(ASPHALT_UV.position.x, ASPHALT_UV.end.y), normal)


## Cuadrilátero `a → b → c → d` como dos triángulos, orientado hacia
## [param normal].
static func _quad(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2,
		normal: Vector3) -> void:
	_tri(builder, a, b, c, uv_a, uv_b, uv_c, normal)
	_tri(builder, a, c, d, uv_a, uv_c, uv_d, normal)


## Triángulo con el sentido de giro que Godot pide para que [param normal] sea
## la cara de frente.
##
## Godot dibuja de frente los triángulos **en sentido horario** vistos desde
## fuera, o sea que el producto `(b−a) × (c−a)` apunta al **revés** de la normal
## visible. Comprobarlo acá —y dar vuelta el triángulo si hace falta— evita
## tener que razonar el orden de los vértices en cada una de las quince llamadas
## de este archivo, que es exactamente el tipo de error que sólo se ve en la
## captura.
static func _tri(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, normal: Vector3) -> void:
	var first := b
	var second := c
	var first_uv := uv_b
	var second_uv := uv_c
	if (b - a).cross(c - a).dot(normal) > 0.0:
		first = c
		second = b
		first_uv = uv_c
		second_uv = uv_b
	builder.set_normal(normal.normalized())
	builder.set_uv(uv_a)
	builder.add_vertex(a)
	builder.set_normal(normal.normalized())
	builder.set_uv(first_uv)
	builder.add_vertex(first)
	builder.set_normal(normal.normalized())
	builder.set_uv(second_uv)
	builder.add_vertex(second)


## UV de un punto dentro de una figura, estirando el parche del atlas sobre su
## caja envolvente.
##
## El atlas **no es repetible**: fuera del rectángulo hay otra cara de otra
## pieza, así que la UV no puede salirse de él. Estirar es lo único que da un
## mapeo continuo sobre una figura grande sin costuras ni saltos; el precio es
## menos grano en el cruce, que es asfalto liso y no tiene nada que mostrar.
static func _stretch_uv(point: Vector2, low: Vector2, size: Vector2,
		rect: Rect2) -> Vector2:
	return Vector2(rect.position.x + rect.size.x * ((point.x - low.x) / size.x),
			rect.position.y + rect.size.y * ((point.y - low.y) / size.y))


## Cierra el [SurfaceTool] y devuelve la malla, o `null` si no se añadió nada.
static func _commit(builder: SurfaceTool) -> ArrayMesh:
	builder.generate_tangents()
	var mesh := builder.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	return mesh


# --------------------------------------------------------------------------
# Interno: geometría plana
# --------------------------------------------------------------------------

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _flat_2d(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for index: int in poly.size():
		var a := poly[index]
		var b := poly[(index + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## Verdadero si [param point] cae dentro del triángulo con [param margin] metros
## de holgura hacia adentro (negativo = hacia afuera).
static func _inside_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2,
		margin: float) -> bool:
	var area := (b - a).cross(c - a)
	if absf(area) < 0.000001:
		return false
	var sign := 1.0 if area > 0.0 else -1.0
	for edge: Array in [[a, b], [b, c], [c, a]]:
		var from: Vector2 = edge[0]
		var to: Vector2 = edge[1]
		var length := from.distance_to(to)
		if length < 0.000001:
			return false
		var distance := (to - from).cross(point - from) * sign / length
		if distance < margin:
			return false
	return true
