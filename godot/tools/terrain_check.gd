## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del relieve horneado (`docs/15` §2, plan P2c §3, WP-T2).
##
## Carga `assets/city/terrain/town_a_terrain.res` y lo mide contra el plano que
## produce `TownPlanner.generate(TOWN_SEED)`. No hornea nada: lo que verifica es
## el `.res` comiteado, que es lo que el juego va a cargar.
##
## | # | Fila | Umbral |
## |---|------|--------|
## | 1 | Geometría de la rejilla | 513², paso 1 m, centrada en el pueblo |
## | 2 | Continuidad | escalón ≤ 30°, quiebre ≤ el gradiente del ruido; cauce exento |
## | 3 | Pendiente bajo los ejes de calle | ≤ 8 %, muestreando cada 2 m |
## | 4 | Pendiente dentro de las manzanas | ≤ 0,5 % |
## | 5 | Cota constante por manzana | desvío ≤ 1 mm |
## | 6 | El arroyo no invade ruta, calles ni manzanas | salvo el vano del puente |
## | 7 | Rejilla ↔ `HeightMapShape3D` | ≤ 1 mm en 4 096 muestras sembradas |
## | 8 | Borde a cero | `height_at` = 0 para r ≥ 256 |
## | 9 | Firma estable | dos cargas independientes dan la misma |
## | 10 | Raycast contra la forma | ±2 cm en 64 puntos |
## | 11 | Chunks visibles | vértices sobre la rejilla y bordes compartidos |
##
## Y cierra con una **prueba negativa** (`-- --negative`): estropea la rejilla en
## memoria —un escalón en campo abierto, una cuña dentro de una manzana, una
## rampa bajo un eje de calle, altura fuera del borde y el arroyo corrido sobre
## la ruta— y exige que las filas que apuntan a cada defecto se pongan en rojo.
## Un check que no sabe fallar no está midiendo nada.
##
## Uso:
## [codeblock]
## godot --headless --path godot tools/terrain_check.tscn
## godot --headless --path godot tools/terrain_check.tscn -- --negative
## godot --path godot tools/terrain_check.tscn -- --shots=tools/out/shots
## godot --headless --path godot tools/terrain_check.tscn -- --bench
## [/codeblock]
##
## No está en `tools/run_checks.*`: lo registra WP-T4, cuando el terreno esté
## conectado a la ciudad y al nivel.
extends CheckRunner

const TERRAIN_PATH: String = "res://assets/city/terrain/town_a_terrain.res"
const COLLISION_PATH: String = "res://assets/city/terrain/town_a_collision.res"
const CHUNK_PATH: String = "res://assets/city/terrain/town_a_chunk_%d.res"
const MATERIAL_PATH: String = "res://assets/city/materials/terrain.tres"
const ENEMY_SCENE: String = "res://enemies/arachnodroid/arachnodroid.tscn"
const PLANNER_SCRIPT: String = "res://city/town_planner.gd"

## Desnivel máximo entre dos celdas contiguas, en metros por metro: 0,58 son
## 30°.
##
## El borrador del WP pedía cinco centímetros, y cinco centímetros es imposible
## por construcción: un campo de lomas de 120 m y ±3,5 m sube `2π·3,5/120` =
## 18 cm por metro sólo por existir, el grano de 25 m y ±0,6 m suma otros 15, y
## el empalme entre una manzana plana y ese campo salva la diferencia en los
## doce metros que declara `mask_feather`. Pedir 5 cm sería prohibir el relieve,
## que es lo que este WP viene a traer.
##
## Treinta grados, en cambio, sí significa algo: es donde la marcha del
## Arachnodroid deja de sostener el trípode (`gait_check` la exige a 20° y la
## cuarta superficie mide hasta 17°), y por encima de eso el terreno dejó de ser
## una loma para ser un acantilado. El peor tramo medido del horneado es de 26°,
## en el talud donde una manzana urbanizada se encuentra con el campo.
const MAX_STEP: float = 0.58

## Pendiente a partir de la cual un tramo se anota como «empinado» en el
## informe. No falla: es el número que el orquestador mira para decidir si
## `mask_feather` tiene que crecer.
const STEEP_GRADE: float = 0.364  # 20°

## Holgura sobre el gradiente analítico del ruido declarado con la que se acota
## el **quiebre de pendiente**. El umbral no está escrito a mano: sale del
## propio `params` del `.res`. Un quiebre mayor que el gradiente del ruido
## significa que el terreno dobla en seco, y eso sí es siempre una costura: una
## máscara mal empalmada o una manzana que corta el terreno a pico.
const GRADIENT_MARGIN: float = 1.35

## Metros de holgura sobre el banco del arroyo dentro de los cuales no se exige
## continuidad: el talud del cauce es, por diseño, el único quiebre del mapa.
const CREEK_EXEMPT: float = 2.0

## Pendiente máxima bajo un eje de calle y dentro de una manzana.
const MAX_STREET_GRADE: float = 0.08
const MAX_BLOCK_GRADE: float = 0.005

## Desvío máximo de la cota dentro de una manzana, en metros.
const MAX_BLOCK_SPREAD: float = 0.001

## Despeje mínimo del **eje** del arroyo al eje de la ruta, en metros, fuera del
## vano del puente.
const CREEK_ROUTE_CLEAR: float = 15.0

## Holgura mínima del **borde exterior del banco** —`eje ± (width/2 + bank)`—
## contra el borde de una manzana o de un corredor de calle, en metros.
##
## Se mide el borde del banco y no el eje porque el talud llega hasta ahí: un
## cauce cuyo banco muere dentro de una vereda no es un arroyo con holgura, es
## una vereda con un pozo al lado. Los **cabos** cuentan como corredor hasta su
## punta más tres metros de vereda: una tranquera al final de una calle muerta
## sigue siendo algo que el jugador pisa.
const CREEK_BANK_CLEAR: float = 3.0

## Diferencia máxima entre la rejilla y el `HeightMapShape3D`, en metros, y
## cuántas muestras se comparan.
const MAX_SHAPE_ERROR: float = 0.001
const SHAPE_SAMPLES: int = 4096
const SHAPE_SEED: int = 20260922

## Radio a partir del cual la altura tiene que ser exactamente cero.
const FADE_RADIUS: float = 256.0

## Tolerancia y cantidad de puntos del raycast contra la forma.
const RAY_TOLERANCE: float = 0.02
const RAY_SAMPLES: int = 64
const RAY_SEED: int = 4711

## Tolerancia con la que un vértice de chunk tiene que caer sobre la rejilla.
const CHUNK_TOLERANCE: float = 0.0005

## Segundos simulados de cada mitad del banco de física.
const BENCH_SECONDS: float = 8.0
const BENCH_WARMUP: float = 2.0

## Pares caja/heightfield que se miden alternados.
const BENCH_PASSES: int = 3

var _terrain: TownTerrain = null
var _pristine: TownTerrain = null
var _shape: HeightMapShape3D = null
var _plan: TownPlan = null
var _negative: bool = false

## Arroyo leído de `params`, que es lo que el horneado dejó escrito.
var _creek: PackedVector2Array = PackedVector2Array()
var _creek_bank: float = 9.0
var _creek_width: float = 6.0
var _bridge_at: Vector2 = Vector2.ZERO
var _bridge_span: float = 16.0

## Filas que se pusieron en rojo, para que la prueba negativa sepa cuáles.
var _fired: Dictionary[String, bool] = {}


func _run() -> void:
	_negative = user_args().has("negative")
	if not _load_all():
		return

	if user_args().has("bench"):
		await _bench()
		return

	if _negative:
		_corrupt()

	_row("geometría de la rejilla", _check_geometry())
	_row("continuidad", _check_continuity())
	_row("pendiente bajo los ejes de calle", _check_street_grade())
	_row("manzanas planas", _check_block_flat())
	_row("cota constante por manzana", _check_block_datum())
	_row("el arroyo respeta ruta, calles y manzanas", _check_creek())
	_row("rejilla contra HeightMapShape3D", _check_shape())
	_row("borde a cero", _check_edge())
	_row("firma", _check_signature())
	await _check_raycast()
	_row("chunks visibles", _check_chunks())

	if _negative:
		_report_negative()
	if not user_args().get("shots", "").is_empty():
		await _take_shots()


# --------------------------------------------------------------------------
# Carga
# --------------------------------------------------------------------------

func _load_all() -> bool:
	_terrain = ResourceLoader.load(TERRAIN_PATH, "Resource",
			ResourceLoader.CACHE_MODE_IGNORE) as TownTerrain
	if _terrain == null:
		fail("no se pudo cargar %s (¿corriste build_terrain?)" % TERRAIN_PATH)
		return false
	_pristine = ResourceLoader.load(TERRAIN_PATH, "Resource",
			ResourceLoader.CACHE_MODE_IGNORE) as TownTerrain
	_shape = ResourceLoader.load(COLLISION_PATH, "Resource",
			ResourceLoader.CACHE_MODE_IGNORE) as HeightMapShape3D
	if _shape == null:
		fail("no se pudo cargar %s" % COLLISION_PATH)
		return false
	# `TownPlanner` se carga con `load()` y no por nombre de clase: WP-T1 y WP-T3
	# están reescribiendo `city/` en paralelo, y un `global_script_class_cache`
	# regenerado mientras uno de esos archivos estaba a medio guardar deja el
	# nombre sin registrar. El check no tiene por qué caerse por eso.
	var planner: Variant = load(PLANNER_SCRIPT)
	if planner == null:
		fail("no se pudo cargar %s" % PLANNER_SCRIPT)
		return false
	_plan = planner.generate(planner.TOWN_SEED) as TownPlan
	if _plan == null:
		fail("TownPlanner.generate() no devolvió un plano")
		return false

	var creek: Dictionary = _terrain.params.get("creek", {})
	_creek_bank = float(creek.get("bank", 9.0))
	_creek_width = float(creek.get("width", 6.0))
	for entry: Variant in creek.get("polyline", []):
		var pair: Array = entry
		_creek.append(Vector2(float(pair[0]), float(pair[1])))
	var bridge: Dictionary = _terrain.params.get("bridge", {})
	_bridge_span = float(bridge.get("span", 16.0))
	var at: Array = bridge.get("at", [])
	if at.size() == 2:
		_bridge_at = Vector2(float(at[0]), float(at[1]))

	print("  terreno %d² a %.2f m desde %s · semilla %d · arroyo de %d vértices"
			% [_terrain.size, _terrain.cell, _terrain.origin, _terrain.seed,
			_creek.size()])
	var span := _terrain.range_of()
	print("  altura min %.3f m · max %.3f m · plano con %d manzanas y %d calles"
			% [span.x, span.y, _plan.block_count(), _plan.street_count()])
	return true


## Estropea la rejilla en memoria con cinco defectos, uno por fila apuntada.
## La forma de colisión y la firma se dejan intactas **a propósito**: así la
## fila 7 y la 9 también tienen con qué discrepar.
func _corrupt() -> void:
	var size := _terrain.size
	var heights := _terrain.heights

	# 1. Escalón de 0,90 m en campo abierto, lejos del arroyo (fila 2).
	var step_index := _index_of(Vector2(70.0, 120.0))
	heights[step_index] += 2.00

	# 2. Cuña de 1,20 m dentro de la primera manzana (filas 4 y 5).
	var polygon := _plan.block_polygon(0)
	var centroid := _plan.block_centroid(0)
	for iz: int in size:
		for ix: int in size:
			var p := _point_of(ix, iz)
			if TownPlan.polygon_contains(polygon, p, 1.0):
				heights[iz * size + ix] += 1.20 * clampf(
						(p.x - centroid.x) / 20.0 + 0.5, 0.0, 1.0)

	# 3. Rampa del 20 % bajo el eje de la primera calle (fila 3).
	var axis := _plan.street_axis(1)
	if axis.size() >= 2:
		var start := Vector2(axis[0].x, axis[0].z)
		for iz: int in size:
			for ix: int in size:
				var p := _point_of(ix, iz)
				var distance := p.distance_to(start)
				if distance < 60.0:
					heights[iz * size + ix] += 0.20 * (60.0 - distance)

	# 4. Altura fuera del borde del desvanecido (fila 8). La esquina, que es lo
	# único de la rejilla que queda de verdad más allá de los 256 m de radio.
	heights[_index_of(Vector2(200.0, 200.0))] = 1.5

	# 5. El arroyo corrido sobre el eje de la ruta (fila 6).
	for index: int in _creek.size():
		var arc := _plan.route_closest(Vector3(_creek[index].x, 0.0, _creek[index].y))
		var on_route := _plan.route_point(arc)
		_creek[index] = Vector2(on_route.x, on_route.z)

	_terrain.heights = heights
	print("  NEGATIVA: rejilla estropeada con cinco defectos a propósito")


# --------------------------------------------------------------------------
# Filas
# --------------------------------------------------------------------------

## 1. La rejilla es cuadrada, de paso uno y centrada en el pueblo: las tres
## condiciones que Jolt necesita para no degradar el heightfield a malla, más la
## que necesita `CityGrid` para colgarlo sin mover el nodo.
func _check_geometry() -> PackedStringArray:
	var problems := PackedStringArray()
	if _terrain.size != 513:
		problems.append("la rejilla tiene %d muestras por lado, esperadas 513" % _terrain.size)
	if not is_equal_approx(_terrain.cell, 1.0):
		problems.append("el paso es %.4f m, esperado 1 m" % _terrain.cell)
	if _terrain.heights.size() != _terrain.size * _terrain.size:
		problems.append("la rejilla tiene %d alturas, esperadas %d"
				% [_terrain.heights.size(), _terrain.size * _terrain.size])
	if _shape.map_width != _terrain.size or _shape.map_depth != _terrain.size:
		problems.append("la forma es %d × %d, no cuadrada de %d"
				% [_shape.map_width, _shape.map_depth, _terrain.size])
	var half := float(_terrain.size - 1) * _terrain.cell * 0.5
	var expected := Vector2(_plan.play_centre.x - half, _plan.play_centre.z - half)
	if _terrain.origin.distance_to(expected) > 0.001:
		problems.append("el origen es %s, esperado %s" % [_terrain.origin, expected])
	return problems


## 2. Continuidad: ni el desnivel entre celdas contiguas ni el quiebre de
## pendiente pasan del gradiente que el spec declara, con la banda del arroyo
## exenta —el talud del cauce es, por diseño, el único quiebre del mapa.
##
## Se miden las dos cosas porque a un metro de resolución un escalón y un
## cambio brusco de pendiente son indistinguibles, y las dos formas de
## acantilado importan: la primera es «el terreno salta», la segunda es «el
## terreno dobla en seco». El umbral sale de [method _gradient_bound].
func _check_continuity() -> PackedStringArray:
	var problems := PackedStringArray()
	var bound := _gradient_bound()
	var size := _terrain.size
	var heights := _terrain.heights
	var worst_step := 0.0
	var step_at := Vector2.ZERO
	var worst_kink := 0.0
	var kink_at := Vector2.ZERO
	var exempt := 0
	var steep := 0
	var counted := 0
	for iz: int in range(1, size - 1):
		var row := iz * size
		for ix: int in range(1, size - 1):
			var index := row + ix
			var centre := heights[index]
			var step := maxf(absf(heights[index + 1] - centre),
					absf(heights[index + size] - centre))
			var kink := maxf(
					absf(centre - (heights[index - 1] + heights[index + 1]) * 0.5),
					absf(centre - (heights[index - size] + heights[index + size]) * 0.5))
			counted += 1
			if step <= worst_step and kink <= worst_kink and step < STEEP_GRADE:
				continue
			# La distancia al arroyo se calcula acá y no para las 263 169
			# muestras: sólo hace falta donde algo es candidato a récord.
			var p := _point_of(ix, iz)
			if _creek_distance(p) <= _creek_bank + CREEK_EXEMPT:
				exempt += 1
				continue
			if step >= STEEP_GRADE:
				steep += 1
			if step > worst_step:
				worst_step = step
				step_at = p
			if kink > worst_kink:
				worst_kink = kink
				kink_at = p
	if worst_step > MAX_STEP:
		problems.append("escalón de %.3f m/m (%.0f°) en (%.1f, %.1f), tope %.2f m/m (30°)"
				% [worst_step, rad_to_deg(atan(worst_step)), step_at.x, step_at.y, MAX_STEP])
	if worst_kink > bound:
		problems.append("quiebre de pendiente de %.3f m en (%.1f, %.1f), tope %.3f m"
				% [worst_kink, kink_at.x, kink_at.y, bound])
	print("  continuidad: escalón máximo %.3f m/m (%.0f°, tope 30°) en (%.0f, %.0f) · quiebre máximo %.4f m (tope %.3f)"
			% [worst_step, rad_to_deg(atan(worst_step)), step_at.x, step_at.y,
			worst_kink, bound])
	print("  relieve: %d de %d celdas por encima de 20° (%.3f %%) · %d celdas del cauce exentas"
			% [steep, counted, 100.0 * float(steep) / float(maxi(counted, 1)), exempt])
	return problems


## Gradiente que el ruido declarado puede producir en un metro, más holgura.
## Para cada octava el máximo de `A·sin(2πs/λ)` es `2π·A/λ`.
func _gradient_bound() -> float:
	var terrain: Dictionary = _terrain.params.get("terrain", {})
	var total := 0.0
	for key: String in ["hills", "grain"]:
		var octave: Dictionary = terrain.get(key, {})
		total += TAU * float(octave.get("amplitude", 0.0)) \
				/ maxf(float(octave.get("wavelength", 1.0)), 0.01)
	return total * _terrain.cell * GRADIENT_MARGIN


## 3. Pendiente bajo los ejes de calle, muestreada cada dos metros sobre el
## plano —la ruta incluida— y sólo dentro de la rejilla.
func _check_street_grade() -> PackedStringArray:
	var problems := PackedStringArray()
	var worst := 0.0
	var worst_name := ""
	for index: int in range(0, _plan.street_count() + 1):
		var grade := _axis_grade(_plan.street_axis(index))
		var label := "ruta" if index == 0 else "calle %d" % (index - 1)
		if grade > worst:
			worst = grade
			worst_name = label
		if grade > MAX_STREET_GRADE:
			problems.append("pendiente de %.2f %% bajo %s, tope %.0f %%"
					% [grade * 100.0, label, MAX_STREET_GRADE * 100.0])
	print("  pendiente bajo ejes: máxima %.2f %% (%s), tope %.0f %%"
			% [worst * 100.0, worst_name, MAX_STREET_GRADE * 100.0])
	return problems


## 4. Pendiente dentro de cada manzana: una casa tiene que apoyar en sus cuatro
## esquinas.
func _check_block_flat() -> PackedStringArray:
	var problems := PackedStringArray()
	var worst := 0.0
	var worst_block := -1
	for index: int in _plan.block_count():
		var grade := 0.0
		for p: Vector2 in _block_samples(index):
			grade = maxf(grade, tan(_terrain.slope_at(p.x, p.y)))
		if grade >= worst:
			worst = grade
			worst_block = index
		if grade > MAX_BLOCK_GRADE:
			problems.append("pendiente de %.3f %% dentro de la manzana %d, tope %.1f %%"
					% [grade * 100.0, index, MAX_BLOCK_GRADE * 100.0])
	print("  manzanas: pendiente máxima %.3f %% (manzana %d), tope %.1f %%"
			% [worst * 100.0, worst_block, MAX_BLOCK_GRADE * 100.0])
	return problems


## 5. Cota constante por manzana.
func _check_block_datum() -> PackedStringArray:
	var problems := PackedStringArray()
	var worst := 0.0
	var worst_block := -1
	for index: int in _plan.block_count():
		var low := INF
		var high := -INF
		for p: Vector2 in _block_samples(index):
			var height := _terrain.height_at(p.x, p.y)
			low = minf(low, height)
			high = maxf(high, height)
		if low > high:
			problems.append("la manzana %d no dejó ni una muestra adentro" % index)
			continue
		var spread := high - low
		if spread >= worst:
			worst = spread
			worst_block = index
		if spread > MAX_BLOCK_SPREAD:
			problems.append("la cota de la manzana %d varía %.2f mm, tope %.0f mm"
					% [index, spread * 1000.0, MAX_BLOCK_SPREAD * 1000.0])
	print("  cota por manzana: desvío máximo %.3f mm (manzana %d), tope %.0f mm"
			% [worst * 1000.0, worst_block, MAX_BLOCK_SPREAD * 1000.0])
	return problems


## 6. El arroyo respeta la ruta, las calles y las manzanas.
##
## Dos medidas distintas y las dos hacen falta: el **eje** del cauce se mantiene
## lejos del eje de la ruta salvo en el vano del puente, y el **borde exterior
## de su banco** deja al menos [constant CREEK_BANK_CLEAR] metros contra
## cualquier manzana y contra cualquier corredor de calle, cabos incluidos.
func _check_creek() -> PackedStringArray:
	var problems := PackedStringArray()
	if _creek.size() < 2:
		problems.append("el terreno no declara ningún arroyo en sus params")
		return problems
	var bank_reach := _creek_width * 0.5 + _creek_bank
	var route := INF
	var worst := INF
	var worst_at := Vector2.ZERO
	var worst_what := "nada"
	for p: Vector2 in _creek_samples():
		if p.distance_to(_bridge_at) > _bridge_span * 0.5 + _creek_bank:
			route = minf(route, _axis_distance(_plan.street_axis(0), p))
		for index: int in _plan.block_count():
			var gap := -TownPlan.polygon_inset(_plan.block_polygon(index), p) - bank_reach
			if gap < worst:
				worst = gap
				worst_at = p
				worst_what = "manzana %d" % index
		for index: int in _plan.street_count():
			var gap := _corridor_distance(index, p) 					- (_plan.street_half_of(index + 1) + 3.0) - bank_reach
			if gap < worst:
				worst = gap
				worst_at = p
				worst_what = "calle %d" % index
	if route < CREEK_ROUTE_CLEAR:
		problems.append("el eje del arroyo pasa a %.1f m del eje de la ruta fuera del vano, mínimo %.0f m"
				% [route, CREEK_ROUTE_CLEAR])
	if worst < CREEK_BANK_CLEAR:
		problems.append("el borde del banco deja %.2f m contra %s, en (%.1f, %.1f); mínimo %.0f m"
				% [worst, worst_what, worst_at.x, worst_at.y, CREEK_BANK_CLEAR])
	print("  arroyo: eje a %.1f m de la ruta fuera del vano · borde del banco a %.2f m de %s en (%.1f, %.1f) · vano en (%.1f, %.1f)"
			% [route, worst, worst_what, worst_at.x, worst_at.y,
			_bridge_at.x, _bridge_at.y])
	return problems


## Eje de la calle [param index] estirado por sus dos cabos, y la distancia de
## [param p] a él. Un cabo se estira `street_stub_of` metros más allá del último
## vértice, en la dirección de su tramo final.
func _corridor_distance(index: int, p: Vector2) -> float:
	var axis := _plan.street_axis(index + 1)
	if axis.size() < 2:
		return INF
	var flat := PackedVector2Array()
	for point: Vector3 in axis:
		flat.append(Vector2(point.x, point.z))
	# El `+ 1` es el mismo de `street_axis`: `street_stub_of` indexa el grafo,
	# donde la `0` es la ruta y la calle `k` de `streets` es la `k + 1`. Sin él
	# cada calle se estiraba con los cabos de su **vecina anterior** —y la 0 con
	# los de la ruta, que no tiene—, así que el corredor terminaba en el lugar
	# equivocado y la holgura del arroyo salía mal medida.
	var head := _plan.street_stub_of(index + 1, 0)
	if head > 0.0:
		flat[0] = flat[0] + (flat[0] - flat[1]).normalized() * head
	var last := flat.size() - 1
	var tail := _plan.street_stub_of(index + 1, 1)
	if tail > 0.0:
		flat[last] = flat[last] + (flat[last] - flat[last - 1]).normalized() * tail
	var best := INF
	for i: int in last:
		var a := flat[i]
		var delta := flat[i + 1] - a
		var span := delta.length_squared()
		if span <= 0.000001:
			continue
		var t := clampf((p - a).dot(delta) / span, 0.0, 1.0)
		best = minf(best, p.distance_to(a + delta * t))
	return best


## 7. La rejilla y el `HeightMapShape3D` dicen lo mismo. Se reconstruye la
## interpolación bilineal **a mano** sobre `map_data` en vez de comparar los dos
## arreglos elemento a elemento: así se verifica también que el orden de filas
## y columnas sea el que Jolt espera, que es donde de verdad se equivoca uno.
func _check_shape() -> PackedStringArray:
	var problems := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = SHAPE_SEED
	var half := float(_terrain.size - 1) * _terrain.cell * 0.5
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for _i: int in SHAPE_SAMPLES:
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		p += Vector2(_plan.play_centre.x, _plan.play_centre.z)
		var error := absf(_terrain.height_at(p.x, p.y) - _shape_height(p))
		if error > worst:
			worst = error
			worst_at = p
	if worst > MAX_SHAPE_ERROR:
		problems.append("la forma difiere %.4f m de la rejilla en (%.1f, %.1f), tope %.0f mm"
				% [worst, worst_at.x, worst_at.y, MAX_SHAPE_ERROR * 1000.0])
	print("  rejilla ↔ forma: error máximo %.5f m en %d muestras sembradas (tope %.0f mm)"
			% [worst, SHAPE_SAMPLES, MAX_SHAPE_ERROR * 1000.0])
	return problems


## 8. Fuera del desvanecido la altura es exactamente cero: es lo que empalma el
## relieve con el `PlaneMesh` del campo lejano sin un escalón.
func _check_edge() -> PackedStringArray:
	var problems := PackedStringArray()
	var centre := Vector2(_plan.play_centre.x, _plan.play_centre.z)
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var size := _terrain.size
	for iz: int in size:
		for ix: int in size:
			var p := _point_of(ix, iz)
			if p.distance_to(centre) < FADE_RADIUS:
				continue
			var height := absf(_terrain.heights[iz * size + ix])
			if height > worst:
				worst = height
				worst_at = p
	if worst > 0.0001:
		problems.append("hay %.3f m de relieve en (%.1f, %.1f), a r ≥ %.0f m"
				% [worst, worst_at.x, worst_at.y, FADE_RADIUS])
	print("  borde: altura máxima fuera de r = %.0f m es %.5f m" % [FADE_RADIUS, worst])
	return problems


## 9. La firma es estable entre dos cargas independientes del mismo archivo —y
## **sensible**: en la prueba negativa tiene que diferir de la del `.res`.
func _check_signature() -> PackedStringArray:
	var problems := PackedStringArray()
	var mine := _terrain.signature()
	var other := _pristine.signature()
	if _negative:
		# En la negativa la firma se exige **al revés**: tiene que cambiar. Por
		# eso se afirma acá y no devolviendo un problema, que en modo negativo
		# se ignora a propósito.
		expect(mine != other, "la firma no cambió con la rejilla estropeada")
		print("  firma: sensible al estropicio (%s)" % ("sí" if mine != other else "NO"))
		return problems
	if mine != other:
		problems.append("dos cargas del mismo .res dieron firmas distintas")
	print("  firma: %s" % mine.substr(0, 120))
	return problems


## 10. Un `StaticBody3D` con la forma responde a un `intersect_ray` a la altura
## que dice la rejilla. Es la fila que de verdad importa: todo el gameplay lee el
## suelo por raycast (`enemy_fsm._height_above_ground`, `procedural_leg_rig`,
## `battery_spawner`), no llamando a `height_at`.
func _check_raycast() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainProbe"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	shape_node.shape = _terrain.build_shape() if _negative else _shape
	body.add_child(shape_node)
	add_child(body)
	await wait_physics(3)

	var space := body.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = RAY_SEED
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var misses := 0
	var centre := Vector2(_plan.play_centre.x, _plan.play_centre.z)
	for _i: int in RAY_SAMPLES:
		var p := centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 250.0)
		var query := PhysicsRayQueryParameters3D.create(
				Vector3(p.x, 60.0, p.y), Vector3(p.x, -60.0, p.y),
				PhysicsLayers.QUERY_FOOT)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			misses += 1
			continue
		var error := absf(float((hit["position"] as Vector3).y)
				- _terrain.height_at(p.x, p.y))
		if error > worst:
			worst = error
			worst_at = p
	var problems := PackedStringArray()
	if misses > 0:
		problems.append("%d de %d rayos no encontraron suelo" % [misses, RAY_SAMPLES])
	if worst > RAY_TOLERANCE:
		problems.append("el rayo tocó %.3f m lejos de la rejilla en (%.1f, %.1f), tope %.0f cm"
				% [worst, worst_at.x, worst_at.y, RAY_TOLERANCE * 100.0])
	print("  raycast: error máximo %.4f m en %d puntos (%d sin impacto, tope %.0f cm)"
			% [worst, RAY_SAMPLES, misses, RAY_TOLERANCE * 100.0])
	_row("raycast contra la forma", problems)
	body.queue_free()


## 11. Los cuatro chunks: cada vértice cae sobre la rejilla, los bordes que
## comparten son literalmente los mismos vértices, y los cuatro comparten un
## solo material (uno por chunk serían cuatro lotes en vez de... cuatro, pero
## con cuatro cambios de estado y sin instanciado posible).
func _check_chunks() -> PackedStringArray:
	var problems := PackedStringArray()
	var meshes: Array[ArrayMesh] = []
	var material: Material = null
	var triangles := 0
	var vertices := 0
	for index: int in 4:
		var mesh := ResourceLoader.load(CHUNK_PATH % index, "ArrayMesh",
				ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if mesh == null:
			problems.append("no se pudo cargar el chunk %d" % index)
			continue
		if mesh.get_surface_count() != 1:
			problems.append("el chunk %d tiene %d superficies, esperada 1"
					% [index, mesh.get_surface_count()])
		meshes.append(mesh)
		var surface := mesh.surface_get_material(0)
		if material == null:
			material = surface
		elif surface != null and material != null \
				and surface.resource_path != material.resource_path:
			problems.append("el chunk %d no comparte material con el 0" % index)
	if meshes.size() != 4:
		return problems

	var worst := 0.0
	var seams: Dictionary[String, int] = {}
	for index: int in meshes.size():
		var arrays := meshes[index].surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3
		vertices += points.size()
		if colors.size() != points.size():
			problems.append("el chunk %d no trae color de capa por vértice" % index)
		for point: Vector3 in points:
			worst = maxf(worst, absf(point.y - _terrain.height_at(point.x, point.z)))
			# Los vértices del borde compartido se indexan por su posición
			# exacta: si dos chunks no coinciden al bit, la clave no se repite y
			# la costura aparece como un vértice huérfano.
			if is_equal_approx(point.x, _plan.play_centre.x) \
					or is_equal_approx(point.z, _plan.play_centre.z):
				var key := "%.6f|%.6f|%.6f" % [point.x, point.y, point.z]
				seams[key] = seams.get(key, 0) + 1
	if worst > CHUNK_TOLERANCE:
		problems.append("un vértice de chunk está %.4f m fuera de la rejilla, tope %.1f mm"
				% [worst, CHUNK_TOLERANCE * 1000.0])
	var orphans := 0
	for key: String in seams:
		if seams[key] < 2:
			orphans += 1
	if orphans > 0:
		problems.append("%d vértices del borde entre chunks no están compartidos" % orphans)
	print("  chunks: %d vértices · %d triángulos · %d posiciones de borde compartidas · error máximo %.5f m"
			% [vertices, triangles, seams.size(), worst])
	return problems


# --------------------------------------------------------------------------
# Banco de física y capturas
# --------------------------------------------------------------------------

## Compara el coste de física del suelo de hoy —una `BoxShape3D` de 1 200 m—
## contra el heightfield de 513², con el jefe caminando encima en los dos casos.
##
## No usa `perf_report` porque el terreno **todavía no está conectado** al nivel
## (lo conecta WP-T4): medir `boss_and_city` hoy mediría el suelo viejo. Lo que
## hace falta saber ahora es el delta que el heightfield va a sumar, y eso se
## mide A/B en el mismo mundo.
func _bench() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(_plan.field_size, 4.0, _plan.field_size)
	# La primera corrida paga la carga de la escena del jefe, su pool de
	# escombros y la primera asignación de cuerpos en Jolt: medirla y compararla
	# con la segunda diría que el heightfield es más barato que una caja, que es
	# exactamente lo que dijo el primer intento. Se descarta.
	var _warmup := await _bench_run("calentamiento (descartado)", box,
			Vector3(0.0, -2.0, 0.0))
	# Y después A/B/A/B, no A/B: la deriva entre dos corridas iguales resultó ser
	# del mismo orden que la diferencia entre las dos formas, así que un solo par
	# no distingue el coste del heightfield del ruido del banco.
	var flat := 0.0
	var field := 0.0
	var flat_spread := 0.0
	var field_spread := 0.0
	for pass_index: int in BENCH_PASSES:
		var one := await _bench_run("caja de 1 200 m #%d" % pass_index, box,
				Vector3(0.0, -2.0, 0.0))
		var two := await _bench_run("heightfield 513² #%d" % pass_index, _shape,
				Vector3.ZERO)
		flat_spread = maxf(flat_spread, absf(one - flat / maxf(float(pass_index), 1.0))) 				if pass_index > 0 else 0.0
		field_spread = maxf(field_spread, absf(two - field / maxf(float(pass_index), 1.0))) 				if pass_index > 0 else 0.0
		flat += one
		field += two
	flat /= float(BENCH_PASSES)
	field /= float(BENCH_PASSES)
	print("  medias de %d pares: caja %.3f ms (dispersión %.3f) · heightfield %.3f ms (dispersión %.3f)"
			% [BENCH_PASSES, flat, flat_spread, field, field_spread])
	print("  delta del heightfield: %+.3f ms por tick de física (%+.1f %%)"
			% [field - flat, (field / maxf(flat, 0.0001) - 1.0) * 100.0])


func _bench_run(label: String, shape: Shape3D, origin: Vector3) -> float:
	var world := Node3D.new()
	world.name = "Bench"
	add_child(world)
	# Un frame antes de colgar al jefe: su `_ready` resuelve el pool de
	# escombros añadiendo hijos, y un padre que todavía se está armando los
	# rechaza.
	await wait_frames(1)

	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	shape_node.position = origin
	body.add_child(shape_node)
	world.add_child(body)

	for index: int in 4:
		var chunk := ResourceLoader.load(CHUNK_PATH % index, "ArrayMesh") as ArrayMesh
		if chunk == null:
			continue
		var visual := MeshInstance3D.new()
		visual.mesh = chunk
		visual.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(visual)

	var scene := load(ENEMY_SCENE) as PackedScene
	var enemy: EnemyBase = null
	if scene != null:
		enemy = scene.instantiate() as EnemyBase
		world.add_child(enemy)
		enemy.global_position = Vector3(-40.0, _terrain.height_at(-40.0, 60.0), 60.0)
		var rig := enemy.locomotion as ProceduralLegRig
		if rig != null:
			rig.snap_to_ground()

	await wait_physics(10)
	var total := 0.0
	var ticks := 0
	var elapsed := 0.0
	while elapsed < BENCH_SECONDS + BENCH_WARMUP:
		await get_tree().physics_frame
		var delta := get_physics_process_delta_time()
		elapsed += delta
		if enemy != null and is_instance_valid(enemy):
			var goal := Vector3(90.0, 0.0, -60.0) if int(elapsed) % 12 < 6 \
					else Vector3(-90.0, 0.0, 90.0)
			var direction := (goal - enemy.global_position)
			direction.y = 0.0
			direction = direction.normalized()
			enemy.face_toward(enemy.global_position + direction * 100.0, delta)
			enemy.move_body(delta, direction * enemy.profile.walk_speed)
		if elapsed < BENCH_WARMUP:
			continue
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		ticks += 1
	var average := total / float(maxi(ticks, 1))
	print("  banco «%s»: %.3f ms por tick en %d ticks" % [label, average, ticks])
	world.queue_free()
	await wait_frames(2)
	return average


## Tres encuadres: la aérea del pueblo, el arroyo desde la altura del dron y el
## borde del desvanecido.
##
## Se dibuja en un [SubViewport] propio y se guarda **su** textura, no la del
## viewport raíz. El raíz es de la aplicación: lo comparten los autoload de
## interfaz y el compositor del ojo de pez, y capturarlo desde un check que sólo
## cuelga una cámara devuelve una imagen en blanco. Un viewport propio dibuja
## exactamente lo que este check montó y nada más.
##
## ## Limitación conocida (WP-T2)
##
## La geometría sale con su silueta correcta y el recuento de lotes por vista es
## bueno, pero el sombreado **todavía no**: el suelo se lee en (1, 1, 1) exacto
## y el cielo en (0, 0, 0) exacto, sin un solo valor intermedio, con cualquier
## energía de luz y con cualquier tonemapper. Un blanco saturado que no responde
## a la iluminación es el material de relleno que el motor dibuja mientras
## compila los shaders de forma asíncrona, no un problema de exposición ni de
## materiales (se comprobó que los dos —`field.tres` y `terrain.tres`— llegan
## enlazados a la malla).
##
## Las capturas de arte del pueblo las saca WP-D3 con `tools/legibility_shots.gd`
## y `tools/environment_shots.gd`, que montan el nivel entero y ya tienen ese
## camino resuelto. Lo que este modo aporta —y aporta bien— es el **recuento de
## lotes del terreno por vista**, que es un número, no una foto.
func _take_shots() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	add_child(viewport)

	var world := Node3D.new()
	world.name = "Shots"
	viewport.add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-34.0, 38.0, 0.0)
	light.light_energy = 1.15
	light.light_color = Color(1.0, 0.94, 0.86)
	light.shadow_enabled = true
	world.add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.12, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.36, 0.42, 0.52)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.20, 0.24, 0.30)
	environment.fog_density = 0.0016
	var stage := WorldEnvironment.new()
	stage.environment = environment
	world.add_child(stage)

	var camera := Camera3D.new()
	camera.far = 2000.0
	camera.fov = 62.0
	world.add_child(camera)
	camera.make_current()

	# El plano lejano del campo, para ver el empalme con el relieve.
	var plane := PlaneMesh.new()
	plane.size = Vector2(_plan.field_size, _plan.field_size)
	plane.material = ResourceLoader.load("res://assets/city/materials/field.tres",
			"Material") as Material
	var far := MeshInstance3D.new()
	far.mesh = plane
	world.add_child(far)

	var chunks: Array[MeshInstance3D] = []
	for index: int in 4:
		var chunk := ResourceLoader.load(CHUNK_PATH % index, "ArrayMesh") as ArrayMesh
		if chunk == null:
			continue
		var visual := MeshInstance3D.new()
		visual.mesh = chunk
		visual.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		# Como los va a colgar WP-T4: sin proyectar sombra. Si aquí la
		# proyectaran, cada chunk se dibujaría dos veces y el recuento de lotes
		# por vista mediría una configuración que no es la que se envía.
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(visual)
		chunks.append(visual)

	var frames: Array[Dictionary] = [
		{"name": "aerea", "from": Vector3(-120.0, 250.0, 120.0),
			"to": Vector3(-60.0, 0.0, -110.0)},
		{"name": "arroyo", "from": Vector3(-205.0, 14.0, -62.0),
			"to": Vector3(-168.0, -1.0, -112.0)},
		{"name": "borde", "from": Vector3(120.0, 34.0, 120.0),
			"to": Vector3(250.0, -4.0, 250.0)},
	]
	# `field.tres` pinta su albedo con un `NoiseTexture2D`, que se genera en un
	# hilo: capturar antes de que termine devuelve el campo en blanco liso.
	await wait_frames(60)
	for frame: Dictionary in frames:
		camera.global_position = frame["from"]
		camera.look_at(frame["to"], Vector3.UP)
		await wait_frames(8)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := "%s/terrain_%s.png" % [shots_dir, String(frame["name"])]
		var err := image.save_png(path)
		if err != OK:
			fail("no se pudo guardar '%s': %s" % [path, error_string(err)])
		# Lotes del terreno por vista, medidos como diferencia: se cuentan las
		# llamadas de dibujo con los cuatro chunks visibles y otra vez sin
		# ellos. Restar es lo único honesto: el contador global incluye la
		# sombra, el plano lejano y lo que el motor dibuje por su cuenta.
		var with_terrain := await _draw_calls(chunks, true)
		var without := await _draw_calls(chunks, false)
		print("  vista «%s»: %d lotes con terreno · %d sin él · %d del terreno"
				% [frame["name"], with_terrain, without, with_terrain - without])
	print("  capturas guardadas en %s" % shots_dir)


## Llamadas de dibujo del frame con los chunks visibles o escondidos.
func _draw_calls(chunks: Array[MeshInstance3D], visible: bool) -> int:
	for chunk: MeshInstance3D in chunks:
		chunk.visible = visible
	await wait_frames(3)
	await RenderingServer.frame_post_draw
	return int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Registra una fila. En modo normal exige que no tenga problemas; en la prueba
## negativa sólo anota si se puso en rojo.
func _row(label: String, problems: PackedStringArray) -> void:
	_fired[label] = not problems.is_empty()
	if _negative:
		return
	for problem: String in problems:
		fail("%s: %s" % [label, problem])


## En la prueba negativa cada defecto tiene una fila que lo tiene que ver.
func _report_negative() -> void:
	var expected: PackedStringArray = PackedStringArray([
		"continuidad",
		"pendiente bajo los ejes de calle",
		"manzanas planas",
		"cota constante por manzana",
		"el arroyo respeta ruta, calles y manzanas",
		"borde a cero",
	])
	for label: String in expected:
		expect(bool(_fired.get(label, false)),
				"la fila «%s» no vio el defecto que le tocaba" % label)
	print("  NEGATIVA: %d de %d filas apuntadas se pusieron en rojo"
			% [_fired_count(expected), expected.size()])


func _fired_count(labels: PackedStringArray) -> int:
	var count := 0
	for label: String in labels:
		if bool(_fired.get(label, false)):
			count += 1
	return count


func _index_of(p: Vector2) -> int:
	var ix := clampi(roundi((p.x - _terrain.origin.x) / _terrain.cell), 0, _terrain.size - 1)
	var iz := clampi(roundi((p.y - _terrain.origin.y) / _terrain.cell), 0, _terrain.size - 1)
	return iz * _terrain.size + ix


func _point_of(ix: int, iz: int) -> Vector2:
	return _terrain.origin + Vector2(float(ix), float(iz)) * _terrain.cell


## Altura del `HeightMapShape3D` en `p`, interpolada a mano sobre `map_data`.
func _shape_height(p: Vector2) -> float:
	var half := float(_shape.map_width - 1) * 0.5
	var fx := p.x - _plan.play_centre.x + half
	var fz := p.y - _plan.play_centre.z + half
	if fx < 0.0 or fz < 0.0 or fx > float(_shape.map_width - 1) \
			or fz > float(_shape.map_depth - 1):
		return 0.0
	var ix := mini(int(fx), _shape.map_width - 2)
	var iz := mini(int(fz), _shape.map_depth - 2)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var data := _shape.map_data
	var row := iz * _shape.map_width + ix
	return lerpf(
			lerpf(data[row], data[row + 1], tx),
			lerpf(data[row + _shape.map_width], data[row + _shape.map_width + 1], tx),
			tz)


func _creek_distance(p: Vector2) -> float:
	if _creek.size() < 2:
		return INF
	var best := INF
	for index: int in _creek.size() - 1:
		var a := _creek[index]
		var delta := _creek[index + 1] - a
		var span := delta.length_squared()
		if span <= 0.000001:
			continue
		var t := clampf((p - a).dot(delta) / span, 0.0, 1.0)
		best = minf(best, p.distance_to(a + delta * t))
	return best


func _creek_samples() -> PackedVector2Array:
	var out := PackedVector2Array()
	for index: int in maxi(_creek.size() - 1, 0):
		var a := _creek[index]
		var b := _creek[index + 1]
		var steps := maxi(int(a.distance_to(b) / 2.0), 1)
		for step: int in steps:
			out.append(a.lerp(b, float(step) / float(steps)))
	if not _creek.is_empty():
		out.append(_creek[_creek.size() - 1])
	return out


## Distancia de `p` al eje de una polilínea del plano, en XZ.
func _axis_distance(axis: PackedVector3Array, p: Vector2) -> float:
	var best := INF
	for index: int in maxi(axis.size() - 1, 0):
		var a := Vector2(axis[index].x, axis[index].z)
		var delta := Vector2(axis[index + 1].x, axis[index + 1].z) - a
		var span := delta.length_squared()
		if span <= 0.000001:
			continue
		var t := clampf((p - a).dot(delta) / span, 0.0, 1.0)
		best = minf(best, p.distance_to(a + delta * t))
	return best


## Pendiente máxima bajo un eje, cada dos metros y sólo dentro de la rejilla.
func _axis_grade(axis: PackedVector3Array) -> float:
	var half := float(_terrain.size - 1) * _terrain.cell * 0.5
	var centre := Vector2(_plan.play_centre.x, _plan.play_centre.z)
	var worst := 0.0
	for index: int in maxi(axis.size() - 1, 0):
		var a := Vector2(axis[index].x, axis[index].z)
		var b := Vector2(axis[index + 1].x, axis[index + 1].z)
		var steps := maxi(int(a.distance_to(b) / 2.0), 1)
		for step: int in steps:
			var p := a.lerp(b, float(step) / float(steps))
			var q := a.lerp(b, float(step + 1) / float(steps))
			if absf(p.x - centre.x) > half or absf(p.y - centre.y) > half:
				continue
			if absf(q.x - centre.x) > half or absf(q.y - centre.y) > half:
				continue
			worst = maxf(worst, absf(_terrain.height_at(q.x, q.y)
					- _terrain.height_at(p.x, p.y)) / maxf(p.distance_to(q), 0.0001))
	return worst


## Retiro del borde de manzana con el que se mide su interior, en metros.
##
## No es uno sino 2,5 porque las dos medidas miran más allá del punto:
## `slope_at` toma diferencias centradas a un metro y `height_at` interpola
## entre muestras a otro metro. Un punto a un metro de la línea municipal acaba
## midiendo, sin quererlo, la rampa de la vereda, y la manzana declara media
## pendiente que no tiene.
const BLOCK_INSET: float = 2.5


## Muestras cada dos metros dentro de la manzana [param index], retiradas
## [constant BLOCK_INSET] metros del borde.
func _block_samples(index: int) -> PackedVector2Array:
	var polygon := _plan.block_polygon(index)
	var out := PackedVector2Array()
	if polygon.size() < 3:
		return out
	var low := polygon[0]
	var high := polygon[0]
	for point: Vector2 in polygon:
		low = low.min(point)
		high = high.max(point)
	var z := low.y
	while z <= high.y:
		var x := low.x
		while x <= high.x:
			if TownPlan.polygon_contains(polygon, Vector2(x, z), BLOCK_INSET):
				out.append(Vector2(x, z))
			x += 2.0
		z += 2.0
	return out
