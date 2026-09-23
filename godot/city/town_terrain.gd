## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Relieve horneado del pueblo (`docs/10` §4.4, plan P2c §2, WP-T2).
##
## Es un [Resource] de **datos puros**: una rejilla de alturas de 513 × 513
## muestras a un metro, centrada en el pueblo, y las cuatro funciones que hacen
## falta para consultarla. No conoce el ruido que la generó, ni una malla, ni un
## nodo. El ruido se evalúa **una sola vez**, en `tools/build_terrain.gd`, y lo
## que se comitea es el resultado.
##
## ## Por qué una rejilla horneada y no ruido en runtime
##
## Un `FastNoiseLite` evaluado en runtime es una bomba de tres mechas. La
## primera es el coste: la ciudad pregunta la cota del suelo para cada edificio,
## cada poste, cada roca y cada marcador, y el rig del jefe lo haría cuatro
## veces por tick. La segunda es la coherencia: la malla visible, el
## [HeightMapShape3D] de colisión y quien pregunta analíticamente tienen que
## responder **lo mismo al milímetro**, y tres evaluaciones separadas del mismo
## ruido divergen en cuanto alguien cambia un parámetro. La tercera es el
## determinismo entre versiones del motor: `FastNoiseLite` es una
## implementación, no un contrato, y un pueblo que se mueve al actualizar Godot
## no es un pueblo.
##
## Con la rejilla horneada las tres se apagan de una vez: [method height_at] es
## una interpolación bilineal sobre un [PackedFloat32Array], la forma de
## colisión **es** esa misma rejilla, y el `.res` se comitea.
##
## ## Sistema de coordenadas
##
## [member origin] es la esquina XZ de la muestra `(0, 0)` y [member cell] el
## paso. La muestra `(ix, iz)` vive en `heights[iz * size + ix]` —fila por `z`,
## que es exactamente el orden que espera [member HeightMapShape3D.map_data]— y
## cae en el punto del mundo `origin + Vector2(ix, iz) * cell`.
##
## Fuera de la rejilla la altura es **cero**, no la del borde: el campo lejano
## de `CityGrid` es un plano a `y = 0` y el horneado desvanece el relieve a cero
## antes del borde para que no haya escalón entre los dos.
@tool
class_name TownTerrain extends Resource

## Esquina XZ de la muestra `(0, 0)`, en el espacio local del distrito.
@export var origin: Vector2 = Vector2(-256.0, -256.0)

## Paso de la rejilla, en metros. Es `1.0` porque [HeightMapShape3D] trabaja en
## unidades de rejilla y la forma **no se escala** (`docs/03` prohíbe escalar un
## [StaticBody3D]; sobre una forma de altura, además, Jolt lo desaconseja).
@export var cell: float = 1.0

## Muestras por lado. `513` cubre ±256 m a un metro y es múltiplo de 2, que es
## lo que Jolt redondea internamente; además deja la rejilla **cuadrada**, sin
## lo cual Jolt descarta el heightfield y cae a una malla de colisión.
@export var size: int = 513

## Alturas, `size * size` valores, fila por `z`.
@export var heights: PackedFloat32Array = PackedFloat32Array()

## Semilla con la que `tools/build_terrain.gd` generó el relieve.
@export var seed: int = 0

## Copia literal del spec usado en el horneado (`terrain`, `creek`, `bridge`).
## Entra en [method signature] y es lo que permite saber, mirando sólo el
## `.res`, con qué diseño se horneó.
@export var params: Dictionary = {}


# --------------------------------------------------------------------------
# Consulta
# --------------------------------------------------------------------------

## Altura del terreno en el punto XZ `(x, z)`, interpolada bilinealmente entre
## las cuatro muestras que lo rodean. Fuera de la rejilla devuelve `0.0`.
func height_at(x: float, z: float) -> float:
	if size < 2 or heights.size() < size * size or cell <= 0.0:
		return 0.0
	var fx := (x - origin.x) / cell
	var fz := (z - origin.y) / cell
	var last := float(size - 1)
	if fx < 0.0 or fz < 0.0 or fx > last or fz > last:
		return 0.0
	var ix := int(fx)
	var iz := int(fz)
	# El borde exacto cae en la última celda, no en una celda que no existe.
	if ix >= size - 1:
		ix = size - 2
	if iz >= size - 1:
		iz = size - 2
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var row := iz * size + ix
	var low := lerpf(heights[row], heights[row + 1], tx)
	var high := lerpf(heights[row + size], heights[row + size + 1], tx)
	return lerpf(low, high, tz)


## Altura bajo [param p], ignorando su `y`. Azúcar para quien ya tiene el punto.
func height_at_point(p: Vector3) -> float:
	return height_at(p.x, p.z)


## Normal unitaria del terreno en `(x, z)`, por diferencias centradas de un
## paso de rejilla. Fuera de la rejilla devuelve [constant Vector3.UP].
func normal_at(x: float, z: float) -> Vector3:
	var step := maxf(cell, 0.0001)
	var left := height_at(x - step, z)
	var right := height_at(x + step, z)
	var back := height_at(x, z - step)
	var front := height_at(x, z + step)
	# Para `y = h(x, z)` la normal es `(-dh/dx, 1, -dh/dz)`; multiplicada por
	# `2 * step` queda sin divisiones.
	return Vector3(left - right, 2.0 * step, back - front).normalized()


## Normal bajo [param p], ignorando su `y`.
func normal_at_point(p: Vector3) -> Vector3:
	return normal_at(p.x, p.z)


## Pendiente del terreno en `(x, z)`, en **radianes** sobre la horizontal.
func slope_at(x: float, z: float) -> float:
	return acos(clampf(normal_at(x, z).y, -1.0, 1.0))


## Muestra cruda `(ix, iz)`, sin interpolar. Fuera de la rejilla, `0.0`.
func sample(ix: int, iz: int) -> float:
	if ix < 0 or iz < 0 or ix >= size or iz >= size:
		return 0.0
	var index := iz * size + ix
	if index >= heights.size():
		return 0.0
	return heights[index]


## [param p] apoyado sobre el terreno, con [param lift] metros de holgura. Es lo
## que usa WP-T4 para poner edificios, postes y marcadores a cota.
func place(p: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z) + lift, p.z)


## Rectángulo XZ que cubre la rejilla.
func extent() -> Rect2:
	var side := float(maxi(size - 1, 0)) * cell
	return Rect2(origin, Vector2(side, side))


## Alturas mínima y máxima de la rejilla, como `Vector2(min, max)`.
func range_of() -> Vector2:
	if heights.is_empty():
		return Vector2.ZERO
	var low := INF
	var high := -INF
	for value: float in heights:
		low = minf(low, value)
		high = maxf(high, value)
	return Vector2(low, high)


# --------------------------------------------------------------------------
# Interoperación
# --------------------------------------------------------------------------

## [Callable] de [method height_at] para quien reciba una función de altura,
## como `RoadMesh.ribbon(polyline, half_width, height_fn, top)` de WP-T1.
##
## Se devuelve un [Callable] y no la propia rejilla para que el viario no
## dependa de esta clase: cualquier cosa que sepa responder `(x, z) -> float`
## sirve, incluida una constante en los bancos de prueba.
func height_callable() -> Callable:
	return Callable(self, &"height_at")


## [HeightMapShape3D] con esta misma rejilla, para el `StaticBody3D` del suelo.
##
## La forma queda **centrada en el origen del nodo** y con un paso de una
## unidad, que es lo único que Jolt acepta sin degradar: por eso [member cell]
## vale `1.0` y el nodo no se escala nunca. Si la rejilla no fuese cuadrada
## Jolt la descartaría y caería a una malla de colisión, así que se comprueba.
func build_shape() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = heights
	return shape


# --------------------------------------------------------------------------
# Firma
# --------------------------------------------------------------------------

## Firma determinista del relieve: geometría de la rejilla, semilla, extremos,
## un hash de las alturas **cuantizadas a milímetros** y el spec.
##
## Se cuantiza a milímetros por lo mismo que [method TownPlan.signature]: el
## último bit de un flotante que salió de un seno no es una diferencia de
## diseño. Y se hashea en vez de volcarse porque son 263 169 valores: una firma
## de tres megabytes no la compara nadie.
func signature() -> String:
	var accumulator := 0
	for value: float in heights:
		accumulator = _mix(accumulator ^ _mix(roundi(value * 1000.0)))
	var span := range_of()
	return "TownTerrain size=%d cell=%.3f origin=(%.3f,%.3f) seed=%d min=%.3f max=%.3f grid=%016x params=%s" % [
			size, cell, origin.x, origin.y, seed, span.x, span.y,
			accumulator & 0x7FFFFFFFFFFFFFFF, JSON.stringify(params, "", true)]


# --------------------------------------------------------------------------
# Fábrica de ruido
# --------------------------------------------------------------------------

## Rejilla de ruido puro: dos [FastNoiseLite] —lomas de [param wavelength] y
## grano de un quinto— con desvanecido al borde. Es **la misma técnica** que
## compone el relieve del pueblo en `tools/build_terrain.gd`, reducida a lo
## mínimo, y existe para que un banco de pruebas pueda levantar un heightfield
## creíble sin cargar el `.res` del pueblo: la usa la cuarta superficie de
## `tools/gait_check.gd`.
##
## [param lift] sube toda la rejilla —un parche que apoya sobre un plano a
## `y = 0` necesita que el relieve no baje de cero— y [param border_fade] la
## desvanece **a cero, no a `lift`**, en los últimos metros. Desvanecer sólo el
## ruido dejaría el parche terminando en un escalón de `lift` metros contra el
## plano, que es justo el acantilado que se quería evitar.
static func from_noise(noise_seed: int, samples: int, cell_size: float,
		grid_origin: Vector2, wavelength: float, amplitude: float,
		lift: float = 0.0, border_fade: float = 0.0) -> TownTerrain:
	var terrain := TownTerrain.new()
	terrain.size = maxi(samples, 2)
	terrain.cell = maxf(cell_size, 0.0001)
	terrain.origin = grid_origin
	terrain.seed = noise_seed
	terrain.params = {
		"wavelength": wavelength, "amplitude": amplitude,
		"lift": lift, "border_fade": border_fade,
	}

	var hills := FastNoiseLite.new()
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.fractal_type = FastNoiseLite.FRACTAL_NONE
	hills.seed = noise_seed
	hills.frequency = 1.0 / maxf(wavelength, 0.01)

	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.fractal_type = FastNoiseLite.FRACTAL_NONE
	grain.seed = noise_seed + 1
	grain.frequency = 1.0 / maxf(wavelength * 0.21, 0.01)

	var side := float(terrain.size - 1) * terrain.cell
	var data := PackedFloat32Array()
	var _ok := data.resize(terrain.size * terrain.size)
	for iz: int in terrain.size:
		var z := grid_origin.y + float(iz) * terrain.cell
		for ix: int in terrain.size:
			var x := grid_origin.x + float(ix) * terrain.cell
			var value := amplitude * (0.82 * hills.get_noise_2d(x, z)
					+ 0.18 * grain.get_noise_2d(x, z)) + lift
			if border_fade > 0.0:
				var to_edge := minf(minf(x - grid_origin.x, grid_origin.x + side - x),
						minf(z - grid_origin.y, grid_origin.y + side - z))
				value *= smoothstep(0.0, border_fade, to_edge)
			data[iz * terrain.size + ix] = value
	terrain.heights = data
	return terrain


# --------------------------------------------------------------------------
# Interno
# --------------------------------------------------------------------------

## splitmix64, la misma mezcla de [method TownPlan.mix]. Se repite acá —y no se
## importa— para que el relieve no dependa del plano: se puede hornear, guardar
## y verificar un [TownTerrain] sin que exista un [TownPlan].
static func _mix(value: int) -> int:
	var z := value + -7046029254386353131  # 0x9E3779B97F4A7C15
	z = (z ^ (z >> 30)) * -4658895280553007687  # 0xBF58476D1CE4E5B9
	z = (z ^ (z >> 27)) * -7723592293110705685  # 0x94D049BB133111EB
	return z ^ (z >> 31)
