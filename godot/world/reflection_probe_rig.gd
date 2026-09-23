## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Iluminación global local de la ciudad: los [ReflectionProbe] de `docs/13` §3.3.
##
## SDFGI aporta el rebote difuso, pero no reflejos: sin probes, una fachada de
## cristal al atardecer devuelve el cielo entero en vez de la calle de enfrente, y el
## asfalto mojado no refleja nada. Cuatro cajas con `box_projection` bien puestas
## arreglan eso por 0 ms de CPU y un único horneado.
##
## ## Por qué se crean en tiempo de ejecución y no en `town_a.tscn`
##
## La cantidad depende del preset (0 / 2 / 4 / 6, `docs/13` §3.4) y el distrito es
## una escena **horneada** por su herramienta de construcción: meter los probes ahí
## obligaría a regenerarla cada vez que se toque la tabla de calidad y dejaría cuatro
## nodos muertos en LOW. Acá se piden las posiciones al **plano del pueblo** que el
## distrito publica con `get_plan()` —centro de juego, ruta, calles— y se arman los
## que pida `Graphics`.
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

## Distancia a la que se ponen los dos probes de ruta, medida **sobre la ruta**
## desde el punto más cercano al centro del pueblo, en metros.
##
## Sesenta metros es poco más de la mitad del radio de juego: el probe todavía ve
## el centro y ya ve el tramo siguiente de la ruta, que es donde la calzada mojada
## tiene que reflejar algo.
const ROUTE_REACH: float = 60.0

## Distancia al centro, en metros, a la que se busca el probe de calle lateral.
const SIDE_STREET_REACH: float = 100.0

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
## centro del pueblo, ruta adelante, azotea del edificio más alto, calle lateral y,
## ya sólo para ULTRA, ruta atrás y una segunda azotea.
##
## El orden es el mismo de siempre —dos de calle, una de azotea, una de calle, y
## las dos últimas para ULTRA— porque es el que hace que con 2 probes se vea el
## centro y el tramo principal de la ruta, que es donde el jugador pasa la ronda.
##
## **Barrio sin plano**: hoy no hay ninguno —el distrito rectangular de P2 ya no
## existe—, pero el camino queda **por diseño**. Este rig lo arma el nivel de
## batalla, que es uno solo para todas las rondas (`docs/11` §3) y recibe el barrio
## que le toque del catálogo, así que no puede dar por sentado que publique plano.
## Sin plano no hay ruta ni círculo de juego que consultar y se degrada a las azoteas
## más altas y al origen del distrito: son peores puntos, pero son puntos reales y el
## nivel no se queda sin GI local, que es lo que importa.
##
## Cada entrada es `{"position": Vector3, "size": Vector3}` en espacio global.
func probe_spots(grid: CityGrid) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	var landmarks := _tallest_buildings(grid, 2)
	var plan := _plan_of(grid)
	if plan == null:
		for building: Building in landmarks:
			spots.append(_roof_spot(building))
		spots.append(_street_spot(grid.global_position, 1.6))
		return spots

	var centre: Vector3 = plan.get(&"play_centre")
	var along := float(plan.call(&"route_closest", centre))

	# 1. Centro del pueblo: la «plaza» de `docs/13` §3.3, ahora sin avenidas.
	spots.append(_street_spot(grid.to_global(centre), 1.6))
	# 2. Ruta, sesenta metros adelante del centro.
	spots.append(_street_spot(grid.to_global(_route_point(plan, along + ROUTE_REACH)), 1.2))
	# 3. Azotea del edificio más alto: en el pueblo es el hito y, tras él, el
	#    mediano más alto, que es el que da el segundo probe de azotea.
	if not landmarks.is_empty():
		spots.append(_roof_spot(landmarks[0]))
	# 4. Calle lateral, a un centenar de metros del centro.
	spots.append(_street_spot(grid.to_global(_side_street_point(plan, centre)), 1.0))
	# 5. Ruta, sesenta metros atrás (ULTRA).
	spots.append(_street_spot(grid.to_global(_route_point(plan, along - ROUTE_REACH)), 1.2))
	# 6. Segunda azotea (ULTRA).
	if landmarks.size() > 1:
		spots.append(_roof_spot(landmarks[1]))
	return spots


## El plano del pueblo de [param grid], o `null` si el distrito no lo publica.
##
## Por `has_method` y no por tipo: este nodo lo arma el nivel de batalla, que es uno
## para todas las rondas, y nada le garantiza que el barrio de la que venga publique
## un plano.
func _plan_of(grid: CityGrid) -> Object:
	if grid == null or not is_instance_valid(grid) or not grid.has_method(&"get_plan"):
		return null
	return grid.call(&"get_plan") as Object


## Punto de la ruta a [param distance] metros de su origen, recortado a la ruta.
##
## El recorte es lo que hace que los dos probes de ruta sigan cayendo **sobre la
## calzada** cuando el centro del pueblo queda cerca de una punta: sin él,
## `centro − 60 m` se iría fuera de la polilínea y el probe terminaría en el campo.
func _route_point(plan: Object, distance: float) -> Vector3:
	var length := float(plan.call(&"route_length"))
	return plan.call(&"route_point", clampf(distance, 0.0, length)) as Vector3


## Punto de calle más parecido a [constant SIDE_STREET_REACH] metros de
## [param centre]: la «calle lateral» de `docs/13` §3.3.
##
## Recorre los vértices de las calles del plano y se queda con el que menos se
## desvía de la distancia buscada. Si el plano no trae calles se cae a la ruta, que
## siempre existe.
func _side_street_point(plan: Object, centre: Vector3) -> Vector3:
	var streets := plan.get(&"streets") as Array
	var best := Vector3.ZERO
	var best_error := INF
	for street: Variant in streets:
		for point: Vector3 in street as PackedVector3Array:
			var error := absf(point.distance_to(centre) - SIDE_STREET_REACH)
			if error < best_error:
				best_error = error
				best = point
	if best_error == INF:
		return _route_point(plan,
				float(plan.call(&"route_closest", centre)) + SIDE_STREET_REACH)
	return best


## Caja de calle centrada en [param position], con el lado escalado por
## [param scale_xz] (el centro del pueblo es el punto más abierto y pide más caja).
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
