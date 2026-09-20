## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Iluminación global local de la ciudad: los [ReflectionProbe] de `docs/13` §3.3.
##
## SDFGI aporta el rebote difuso, pero no reflejos: sin probes, una fachada de
## cristal al atardecer devuelve el cielo entero en vez de la calle de enfrente, y el
## asfalto mojado no refleja nada. Cuatro cajas con `box_projection` bien puestas
## arreglan eso por 0 ms de CPU y un único horneado.
##
## ## Por qué se crean en tiempo de ejecución y no en `district_a.tscn`
##
## La cantidad depende del preset (0 / 2 / 4 / 6, `docs/13` §3.4) y el distrito es
## una escena **horneada** por `tools/build_district.gd`: meter los probes ahí
## obligaría a regenerarla cada vez que se toque la tabla de calidad y dejaría cuatro
## nodos muertos en LOW. Acá se piden las posiciones a la API de [CityGrid]
## —[method CityGrid.avenue_crossing], [method CityGrid.lane_centre],
## [method CityGrid.get_core_extent]— y se arman los que pida `Graphics`.
##
## Con `update_mode = UPDATE_ONCE` cada probe se hornea en el primer cuadro en que se
## lo ve y no vuelve a costar nada. El precio es que un edificio que colapse **no**
## se actualiza en el reflejo; a 120 m de `max_distance` y con la ciudad reflejada en
## fachadas mate, no se nota, y es exactamente el mismo compromiso que ya asume
## SDFGI con los escombros en `GI_MODE_DISABLED`.
class_name ReflectionProbeRig
extends Node3D

## Alcance del probe, en metros (`docs/13` §3.3).
const MAX_DISTANCE: float = 120.0

## Altura del centro de los probes de calle, en metros. A 18 m la caja abarca la
## planta baja y los primeros pisos, que es lo que se ve reflejado desde el dron.
const STREET_HEIGHT: float = 18.0

## Media altura de la caja de un probe de calle.
const STREET_EXTENT_Y: float = 22.0

## Lado de la caja de un probe de calle, en metros.
const STREET_EXTENT_XZ: float = 56.0

## Caja del probe de azotea: chata y ancha, para el cielo y el remate de la torre.
const ROOF_EXTENT: Vector3 = Vector3(40.0, 16.0, 40.0)

## Cuánto por encima del techo se centra el probe de azotea, en metros.
const ROOF_CLEARANCE: float = 8.0

## Distancia de mezcla con el entorno en el borde de la caja, en metros.
const BLEND_DISTANCE: float = 6.0

## Probes vivos, en el orden en que los pide `docs/13` §3.3.
var _probes: Array[ReflectionProbe] = []


## Rehace los probes para [param grid] con la cuenta del preset activo.
##
## Es idempotente: se puede volver a llamar cuando el jugador cambia de calidad.
## Sin rejilla —o con cuenta 0, que es LOW— deja el rig vacío.
func rebuild(grid: CityGrid) -> void:
	clear()
	var wanted := Graphics.reflection_probe_count()
	if grid == null or not is_instance_valid(grid) or wanted <= 0:
		return
	var spots := probe_spots(grid)
	for index: int in mini(wanted, spots.size()):
		_probes.append(_make_probe(spots[index]))


## Borra los probes existentes.
func clear() -> void:
	for probe: ReflectionProbe in _probes:
		if is_instance_valid(probe):
			probe.queue_free()
	_probes.clear()


## Los probes vivos. Lo miran los checks.
func get_probes() -> Array[ReflectionProbe]:
	var alive: Array[ReflectionProbe] = []
	for probe: ReflectionProbe in _probes:
		if is_instance_valid(probe):
			alive.append(probe)
	return alive


## Las seis posiciones candidatas, **en orden de importancia** (`docs/13` §3.3):
## cruce de avenidas, avenida, azotea del hito más alto, calle lateral y, ya sólo
## para ULTRA, el otro extremo de la avenida y una segunda azotea.
##
## Cada entrada es `{"position": Vector3, "size": Vector3}` en espacio global.
func probe_spots(grid: CityGrid) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	var core := grid.get_core_extent()
	var crossing := grid.to_global(grid.avenue_crossing())

	# 1. Cruce de las dos avenidas: la «plaza central» de `docs/13` §3.3.
	spots.append(_street_spot(crossing, 1.6))
	# 2. Avenida, a un cuarto del núcleo del cruce hacia el borde negativo en X.
	var avenue_x := grid.to_global(_lane_point(grid, CityGrid.Lane.AVENUE, 0, crossing))
	avenue_x.x = crossing.x - core.x * 0.25
	spots.append(_street_spot(avenue_x, 1.2))
	# 3. Azotea del edificio más alto.
	var landmarks := _tallest_buildings(grid, 2)
	if not landmarks.is_empty():
		spots.append(_roof_spot(landmarks[0]))
	# 4. Calle lateral: el centro de la calle más alejada del cruce.
	spots.append(_street_spot(grid.to_global(_side_street_point(grid)), 1.0))
	# 5. El otro extremo de la avenida (ULTRA).
	var avenue_z := crossing
	avenue_z.z = crossing.z + core.y * 0.25
	spots.append(_street_spot(avenue_z, 1.2))
	# 6. Segunda azotea (ULTRA).
	if landmarks.size() > 1:
		spots.append(_roof_spot(landmarks[1]))
	return spots


## Caja de calle centrada en [param position], con el lado escalado por
## [param scale_xz] (el cruce de avenidas es el punto más abierto y pide más caja).
func _street_spot(position: Vector3, scale_xz: float) -> Dictionary:
	var centre := position
	centre.y = STREET_HEIGHT
	return {
		"position": centre,
		"size": Vector3(STREET_EXTENT_XZ * scale_xz, STREET_EXTENT_Y,
				STREET_EXTENT_XZ * scale_xz) * 2.0,
	}


## Caja de azotea sobre [param building].
func _roof_spot(building: Building) -> Dictionary:
	var centre := building.global_position
	centre.y = building.global_position.y + building.get_height() + ROOF_CLEARANCE
	return {"position": centre, "size": ROOF_EXTENT * 2.0}


## Centro del primer carril de clase [param kind] del eje [param axis], conservando
## la otra coordenada de [param fallback].
func _lane_point(grid: CityGrid, kind: int, axis: int, fallback: Vector3) -> Vector3:
	var point := fallback
	for lane: int in grid.lane_count(axis):
		if grid.lane_kind(axis, lane) != kind:
			continue
		if axis == 0:
			point.x = grid.lane_centre(0, lane)
		else:
			point.z = grid.lane_centre(1, lane)
		return point
	return point


## Cruce de calles comunes más lejano al cruce de avenidas: la «calle lateral».
func _side_street_point(grid: CityGrid) -> Vector3:
	var crossing := grid.avenue_crossing()
	var best := crossing
	var best_distance := -1.0
	for lane_x: int in grid.lane_count(0):
		if grid.lane_kind(0, lane_x) != CityGrid.Lane.STREET:
			continue
		for lane_z: int in grid.lane_count(1):
			if grid.lane_kind(1, lane_z) != CityGrid.Lane.STREET:
				continue
			var point := Vector3(grid.lane_centre(0, lane_x), 0.0, grid.lane_centre(1, lane_z))
			var distance := point.distance_to(crossing)
			if distance > best_distance:
				best_distance = distance
				best = point
	return best


## Los [param count] edificios más altos, de mayor a menor.
func _tallest_buildings(grid: CityGrid, count: int) -> Array[Building]:
	var buildings := grid.get_buildings()
	buildings.sort_custom(func(a: Building, b: Building) -> bool:
		return a.get_height() > b.get_height())
	return buildings.slice(0, mini(count, buildings.size()))


func _make_probe(spot: Dictionary) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = "Probe%d" % (_probes.size() + 1)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.max_distance = MAX_DISTANCE
	probe.size = spot["size"] as Vector3
	probe.blend_distance = BLEND_DISTANCE
	probe.interior = false
	# Las sombras dentro del probe cuestan un horneado carísimo y lo que se refleja
	# al atardecer son fachadas planas: el ahorro no se ve.
	probe.enable_shadows = false
	# Sin LOD agresivo el horneado dibuja los 60 edificios a full: 8 px alcanza para
	# un reflejo de 128².
	probe.mesh_lod_threshold = 8.0
	add_child(probe)
	probe.global_position = spot["position"] as Vector3
	return probe
