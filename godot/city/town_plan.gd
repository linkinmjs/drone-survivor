## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Plano del **pueblo de ruta** (`docs/10` §4, reescrito por WP-B).
##
## Es un [Resource] de datos puros: una polilínea de ruta, ejes de calle,
## polígonos de manzana y una lista de parcelas. No conoce ni una sola pieza, ni
## un material, ni un nodo: se puede generar, guardar y verificar **sin abrir
## ningún asset**, que es lo que permite a `tools/town_plan_check.gd` correr en
## menos de cinco segundos y en `--headless` puro.
##
## Quien lo construye es [TownPlanner]; quien lo convierte en geometría es
## [CityGrid]. Esta clase sólo responde preguntas.
##
## ## Por qué un plano y no una rejilla
##
## Hasta WP-24b la ciudad era el producto cartesiano de dos listas de carriles:
## toda calle era paralela a un eje del mundo, toda manzana un rectángulo y toda
## fachada miraba a uno de cuatro rumbos. Leída desde el aire —que es de donde el
## jugador la mira siempre— eso no es un pueblo: es papel cuadriculado. El plano
## invierte el orden: primero existe **la ruta**, después las calles que la
## cruzan en ángulos que no son rectos, después las manzanas que quedan entre
## ellas (polígonos convexos cualesquiera, recortados contra el disco del pueblo)
## y recién al final las parcelas, apoyadas sobre los lados de manzana que de
## verdad dan a una calle.
##
## ## Sistema de coordenadas
##
## Todo está en el espacio local del distrito, que vive en el origen. Las
## manzanas se guardan en **XZ** ([PackedVector2Array]: `x` es X y `y` es Z)
## porque son figuras planas y guardar una `y` constante por vértice sería
## mentira y un tercio más de archivo. Todo lo demás es [Vector3] con `y` real.
@tool
class_name TownPlan extends Resource

## Rol de una parcela. Los cuatro primeros son destructibles y llevan
## `city/building.gd`; [constant Role.DECOR] es una casa de caserío, instanciada
## como pieza cruda fuera del círculo de juego.
enum Role {
	HOUSE,      ## Casa del pueblo, perfil `house` (1 300 HP).
	MEDIUM,     ## Mediano de frente de ruta, perfil `tower` (3 500 HP).
	LANDMARK,   ## Hito del borde del pueblo, perfil `tower` estirado a 1,45.
	SCHOOL,     ## Escuela: el edificio protegido de `docs/11` §1.
	DECOR,      ## Casa de caserío, fuera del círculo y sin `Building`.
}

## HP de cada rol. Vive acá y no en los `.tres` de perfil para que
## [method total_hp] se pueda calcular **sin cargar un solo recurso**, que es lo
## que hace barato al check del plano.
const ROLE_HP: Dictionary[int, float] = {
	Role.HOUSE: 1300.0,
	Role.MEDIUM: 3500.0,
	Role.LANDMARK: 3500.0,
	Role.SCHOOL: 3500.0,
	Role.DECOR: 0.0,
}

## Nombres de nodo de cada rol. `docs/11` §1 y `rounds/round_catalog.gd` buscan
## al protegido **por nombre**, así que la escuela tiene uno fijo.
const SCHOOL_NODE: StringName = &"Building_School"
const LANDMARK_NODE: StringName = &"Building_Landmark"
const MEDIUM_PREFIX: String = "Building_Mid_"
const HOUSE_PREFIX: String = "Building_House_"
const DECOR_PREFIX: String = "Decor_House_"

## Fracción de manzanas que se queda sin luz en las ventanas (`docs/13` §1,
## préstamo de la dirección B del checkpoint 3b).
##
## Se raciona por **manzana** y no por edificio: un apagón salpicado edificio a
## edificio se lee como ruido de textura, y lo que el pueblo tiene que contar es
## que hay cuadras enteras sin luz.
const DARK_BLOCK_RATIO: float = 0.30

## Sal del racionamiento de ventanas. Es un entero y no un texto porque la
## llave la produce [method mix_all], no `String.hash()`.
const DARK_SEED_SALT: int = 0x77696E64  # "wind"

## Factor de la extensión que declara [method get_extent] sobre el diámetro del
## círculo de juego. El mapa de la alerta (`hud/combat/alert_screen.gd`) dibuja
## esa caja, y ceñirla al círculo dejaría los caseríos y las rocas justo encima
## del marco.
const EXTENT_MARGIN: float = 1.35

## Altura a la que apoya un edificio: la de la vereda. Se repite acá —y no se
## importa de [CityGrid]— para que el plano no dependa de la clase que lo
## construye.
const SIDEWALK_TOP: float = 0.18

## Clase de calle. La ruta es la clase de la calle `0` y la única que sale del
## pueblo; el resto ordena la jerarquía del trazado y es lo que el diseño
## declara en `city/designs/town_a.json`.
enum StreetKind {
	ROUTE,   ## La ruta: cruza el pueblo y se va hasta ±600 m.
	STREET,  ## Calle del pueblo, con vereda a los dos lados.
	LANE,    ## Calle secundaria o de fondo, más angosta.
	ACCESS,  ## Acceso de tierra a un caserío o a un campo: termina en cabo.
}

## Ángulo mínimo, en grados, entre dos calles que llegan al mismo nodo.
##
## Por debajo de esto el polígono del cruce se estira hasta ser una plaza —la
## esquina de dos franjas a 20° cae a casi tres anchos de calle del nodo— y el
## jugador deja de poder leer el cruce como una elección. Es el número que
## [method graph_problems] hace cumplir y el que le permite a
## [method RoadMesh.node_radius] acotar el radio de boca.
const GRAPH_ANGLE_MIN: float = 35.0

## Cuánto puede alejarse el extremo de una calle del nodo que dice tocar, en
## metros.
const GRAPH_TOLERANCE: float = 0.5

## Cuánto puede alejarse un cruce de calles del nodo que lo declara, además de
## la media franja más ancha de las dos, en metros.
const GRAPH_CROSS_TOLERANCE: float = 2.0

# --------------------------------------------------------------------------
# Datos
# --------------------------------------------------------------------------

## Semilla con la que [TownPlanner] generó este plano.
@export var seed: int = 0

## Centro del círculo de juego, en el espacio local del distrito.
@export var play_centre: Vector3 = Vector3.ZERO

## Radio del círculo de juego, en metros. Todo lo destructible cae adentro.
@export var play_radius: float = 140.0

## Lado de la caja de suelo, en metros.
@export var field_size: float = 1200.0

## Radio del disco contra el que se recortan las manzanas. Es algo mayor que
## [member play_radius] para que el borde del pueblo no quede cortado justo
## sobre la última fachada.
@export var block_radius: float = 150.0

## Ruta: polilínea de cuatro vértices con dos quiebres. Pasa a 30–40 m del
## centro y se va hasta ±600 m.
@export var route: PackedVector3Array = PackedVector3Array()

## Ancho de la calzada de la ruta, en metros.
@export var route_width: float = 10.0

## Banquina de la ruta a cada lado, en metros.
@export var route_shoulder: float = 3.0

## Ejes de las calles: siete transversales a la ruta y dos paralelas de fondo.
@export var streets: Array[PackedVector3Array] = []

## Ancho de calzada de cada calle de [member streets], en metros (8–12).
@export var street_widths: PackedFloat32Array = PackedFloat32Array()

## Vereda de cada calle, en metros. Fuera del contrato congelado, pero hace
## falta para saber dónde termina la calle y empieza la manzana.
@export var street_sidewalks: PackedFloat32Array = PackedFloat32Array()

## Manzanas: polígonos convexos en XZ, recortados al disco de
## [member block_radius].
@export var blocks: Array[PackedVector2Array] = []

## Calle de cada lado de cada manzana, en el mismo orden que sus vértices: el
## lado `i` va de `blocks[b][i]` a `blocks[b][(i + 1) % n]`.
##
## `-1` es un lado que no da a ninguna calle (el recorte contra el disco), `0`
## es la ruta y `1 + k` es `streets[k]`. Se guarda en vez de recalcularse por
## proximidad porque es **exacto**: sale del semiplano que cortó ese lado.
@export var block_streets: Array[PackedInt32Array] = []

# --------------------------------------------------------------------------
# Grafo del viario (contrato congelado de P2c, WP-T1)
# --------------------------------------------------------------------------
#
# Hasta P2b el viario no era un grafo: era una bolsa de polilíneas que se
# cruzaban donde se cruzaran. De ahí salían los cuatro defectos que el usuario
# vio jugando —cruces con parche cuadrado y z-fighting, veredas que atraviesan
# el cruce, cabos sin sellar y muescas en los quiebres—, y ninguno se arregla
# moviendo geometría: hay que saber **dónde se encuentran dos calles** antes de
# dibujarlas.
#
# El grafo lo llena el resolvedor del diseño (WP-T3) y lo consume el constructor
# ([CityGrid] vía [RoadMesh]). El plano sólo lo guarda y lo verifica. La calle
# `0` sigue siendo la ruta, igual que en [method street_axis]: los índices de
# este bloque son los de esa convención, no los de [member streets].

## Nodos del viario. Cada uno es un diccionario con las claves del contrato:
##
## - `pos: Vector3` — centro del nodo, en el espacio del distrito.
## - `streets: PackedInt32Array` — calles incidentes, en índices de
##   [method street_axis].
## - `angles: PackedFloat32Array` — rumbo con el que cada calle **sale** del
##   nodo, en radianes, medido como `atan2(dz, dx)`.
## - `half_widths: PackedFloat32Array` — media franja de cada calle incidente
##   (calzada / 2 + vereda), o sea [method street_half_of].
## - `poly: PackedVector2Array` — polígono del cruce en XZ. Vacío quiere decir
##   «calculalo», y lo calcula [method node_polygon].
## - `radius: float` — radio de boca: a cuántos metros del centro se corta cada
##   cinta incidente.
##
## [method refresh_nodes] rellena los cuatro últimos campos a partir de `pos`,
## de [member street_nodes] y de la geometría de las calles, así que quien
## escribe el diseño sólo declara dónde está cada nodo.
@export var nodes: Array[Dictionary] = []

## Nodos de cada calle, en pares `(a, b)`: la calle `i` va del nodo
## `street_nodes[2 · i]` al `street_nodes[2 · i + 1]`.
##
## `-1` es un **cabo declarado**: esa punta no llega a ningún lado y tiene que
## traer su cierre en [member street_closures]. Es la diferencia entre «el
## diseñador quiso que la calle muriera ahí, y puso una tranquera» y «la calle
## se quedó sin dibujar», que es lo que pasaba en P2b.
@export var street_nodes: PackedInt32Array = PackedInt32Array()

## Metros que cada punta de calle se estira **más allá** del nodo o del último
## vértice, en pares `(a, b)`. Sobre un cabo es el largo del tramo muerto.
@export var street_stubs: PackedFloat32Array = PackedFloat32Array()

## Clase de cada calle, de [enum StreetKind].
@export var street_kind: PackedInt32Array = PackedInt32Array()

## Cierre de cada punta de calle, una entrada por calle con el formato
## `"a:kind;b:kind"` —o `""` si ninguna de las dos cierra—, donde `kind` es uno
## de `gate`, `culvert`, `fence` o `none`.
##
## Va como texto y no como dos arrays de enteros porque es un dato **raro**: la
## enorme mayoría de las calles no cierra ninguna punta, y una cadena vacía
## cuesta nada mientras que dos `PackedInt32Array` paralelos cuestan dos enteros
## por calle y una oportunidad más de desincronizarse.
@export var street_closures: PackedStringArray = PackedStringArray()

## Cota civil de cada manzana, en metros. Es la `y` a la que el terreno se
## aplana debajo de la manzana (`h_datum` de WP-T2) y a la que apoyan sus casas.
@export var block_datum: PackedFloat32Array = PackedFloat32Array()

## Anillo de vereda de cada manzana: el polígono de la **línea municipal**, con
## los mismos vértices y el mismo orden de lados que [member block_streets], de
## modo que el lado `i` del anillo da a la calle `block_streets[b][i]`.
##
## Vacío quiere decir «usá el polígono de la manzana», que es lo que hace
## [method block_ring]. Existe aparte de [member blocks] para que el diseño pueda
## correr la vereda hacia adentro en una manzana concreta —un retiro, una plaza—
## sin mover la manzana ni las parcelas que ya se apoyan en ella.
@export var block_rings: Array[PackedVector2Array] = []

## Huella del diseño del que salió este plano (`city/designs/town_a.json`, WP-T3).
##
## Entra en [method signature] para que cambiar una línea del JSON cambie la
## firma aunque la geometría resuelta salga parecida: si no, un diseño editado y
## un pueblo horneado viejo podrían declararse iguales.
@export var design_hash: int = 0

## Parcelas. Cada una es un diccionario con las claves del contrato de WP-B:
## `block`, `role`, `piece`, `frontage_point`, `frontage_normal`, `depth`,
## `width`, `height_scale`, `variant`, `destructible`, `name` y `hp`.
@export var parcels: Array[Dictionary] = []

## Cuatro puntos de aparición del coloso, a `play_radius + 60`.
@export var spawns: Array[Transform3D] = []

## Ocho puestos de pila: cinco en cruces de calle y tres en azotea.
@export var battery: PackedVector3Array = PackedVector3Array()

## Parcela sobre la que se apoya cada puesto de azotea, en el orden en que
## aparecen al final de [member battery]; `-1` en los de calle.
##
## El plano calcula la azotea con la tabla de alturas nominales de
## [TownPlanner], que es lo que le permite no abrir un solo asset. [CityGrid],
## que sí tiene la pieza en la mano, **afina** esos tres puestos con la altura
## real del edificio sembrado: la tabla y la malla pueden discrepar medio metro
## y `BatterySpawner` comprueba el hueco con una esfera de 2,5 m.
@export var battery_roof_parcels: PackedInt32Array = PackedInt32Array()

## Aparición del dron, sobre la ruta.
@export var drone: Transform3D = Transform3D.IDENTITY

## Pose de la cámara fija de las capturas y de la intro.
@export var camera: Transform3D = Transform3D.IDENTITY

## Seis posiciones de roca, fuera del círculo y fuera del cono del dron.
@export var rocks: PackedVector3Array = PackedVector3Array()

## Maleza, basura y barriles. Se instancian por [MultiMesh].
@export var decor: Array[Transform3D] = []

## Manzanas sin luz, resueltas una vez por semilla de ronda.
var _dark_blocks: Dictionary[int, bool] = {}
var _dark_signature: String = ""


# --------------------------------------------------------------------------
# Identidad
# --------------------------------------------------------------------------

## Firma determinista del plano. Dos planos con la misma firma son el mismo
## pueblo: es lo que compara `town_plan_check` entre dos corridas.
##
## Se redondea a milímetros a propósito. Un `%.6f` sobre coordenadas que salen
## de senos y cosenos haría fallar la comparación por el último bit de un
## flotante, que no es una diferencia de diseño sino ruido de la FPU.
func signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("seed=%d" % seed)
	parts.append("centre=%s" % _v3(play_centre))
	parts.append("r=%.3f field=%.3f" % [play_radius, field_size])
	parts.append("route=%s w=%.3f s=%.3f" % [_v3_list(route), route_width, route_shoulder])
	for index: int in streets.size():
		var width := street_widths[index] if index < street_widths.size() else 0.0
		var walk := street_sidewalks[index] if index < street_sidewalks.size() else 0.0
		parts.append("st%d=%s w=%.3f s=%.3f"
				% [index, _v3_list(streets[index]), width, walk])
	for index: int in blocks.size():
		parts.append("bl%d=%s|%s|%.3f|%s" % [index, _v2_list(blocks[index]),
				_ints(block_streets[index] if index < block_streets.size()
				else PackedInt32Array()),
				_zero(block_datum[index] if index < block_datum.size() else 0.0),
				_v2_list(block_rings[index] if index < block_rings.size()
				else PackedVector2Array())])
	# El grafo entra entero: dos pueblos con las mismas calles pero distinto
	# reparto de nodos son dos pueblos, aunque la polilínea de cada calle sea la
	# misma, porque el viario horneado sale distinto.
	for index: int in nodes.size():
		var node := nodes[index]
		parts.append("nd%d=%s|%s|%s|%s|%.3f" % [index,
				_v3(node.get("pos", Vector3.ZERO)),
				_ints(node.get("streets", PackedInt32Array())),
				_floats(node.get("angles", PackedFloat32Array())),
				_floats(node.get("half_widths", PackedFloat32Array())),
				_zero(float(node.get("radius", 0.0)))])
	parts.append("graph=%s|%s|%s|%s" % [_ints(street_nodes), _floats(street_stubs),
			_ints(street_kind), "|".join(street_closures)])
	parts.append("design=%d" % design_hash)
	for index: int in parcels.size():
		var parcel := parcels[index]
		parts.append("pa%d=%d|%s|%s|%s|%.3f|%.3f|%.3f|%d|%s|%.3f|%.1f|%s|%d" % [index,
				int(parcel.get("role", 0)), String(parcel.get("piece", &"")),
				_v3(parcel.get("frontage_point", Vector3.ZERO)),
				_v3(parcel.get("frontage_normal", Vector3.ZERO)),
				_zero(float(parcel.get("depth", 0.0))), _zero(float(parcel.get("width", 0.0))),
				_zero(float(parcel.get("height_scale", 1.0))), int(parcel.get("variant", 0)),
				String(parcel.get("name", &"")), _zero(float(parcel.get("base_y", 0.0))),
				_zero(float(parcel.get("hp", 0.0))),
				"1" if bool(parcel.get("destructible", false)) else "0",
				int(parcel.get("street", -1))])
	parts.append("spawns=%s" % _xform_list(spawns))
	parts.append("battery=%s|%s" % [_v3_list(battery), _ints(battery_roof_parcels)])
	parts.append("drone=%s" % _xform(drone))
	parts.append("camera=%s" % _xform(camera))
	parts.append("rocks=%s" % _v3_list(rocks))
	parts.append("decor=%s" % _xform_list(decor))
	return "\n".join(parts)


# --------------------------------------------------------------------------
# Círculo de juego
# --------------------------------------------------------------------------

## Verdadero si [param p] cae dentro del círculo de juego, medido en XZ.
func is_inside(p: Vector3) -> bool:
	return _flat(p - play_centre).length() <= play_radius


## Verdadero si la **huella entera** de la parcela [param i] cae dentro del
## círculo de juego, con [param margin] metros de holgura.
##
## Se prueban las cuatro esquinas y no el centro: una casa de quince metros de
## frente apoyada justo sobre el borde tiene el centro adentro y dos esquinas
## afuera, y lo que `CityIntegrity` y el jefe miran es el edificio, no su punto
## medio.
func parcel_inside(i: int, margin: float = 0.0) -> bool:
	var footprint := parcel_footprint(i)
	if footprint.is_empty():
		return false
	var centre := Vector2(play_centre.x, play_centre.z)
	var limit := play_radius - margin
	for corner: Vector2 in footprint:
		if centre.distance_to(corner) > limit:
			return false
	return true


## Distancia en XZ de [param p] al centro del círculo.
func distance_to_centre(p: Vector3) -> float:
	return _flat(p - play_centre).length()


## Extensión que dibuja el mapa de la alerta: el diámetro del círculo con el
## margen de [constant EXTENT_MARGIN].
func get_extent() -> Vector2:
	var side := play_radius * 2.0 * EXTENT_MARGIN
	return Vector2(side, side)


## Extensión del casco del pueblo, sin margen: el diámetro pelado.
func get_core_extent() -> Vector2:
	var side := play_radius * 2.0
	return Vector2(side, side)


# --------------------------------------------------------------------------
# Ruta
# --------------------------------------------------------------------------

## Largo total de la ruta, en metros.
func route_length() -> float:
	return polyline_length(route)


## Punto de la ruta a [param distance] metros de su primer vértice. Fuera del
## rango se extrapola sobre la recta del tramo extremo, para que quien pida un
## punto «más allá» no reciba un salto al origen.
func route_point(distance: float) -> Vector3:
	return polyline_point(route, distance)


## Tangente unitaria de la ruta a [param distance] metros.
func route_tangent(distance: float) -> Vector3:
	return polyline_tangent(route, distance)


## Distancia sobre la ruta del punto más cercano a [param p].
func route_closest(p: Vector3) -> float:
	return polyline_closest(route, p)


## Distancia en XZ de [param p] al eje de la ruta.
func route_offset(p: Vector3) -> float:
	return _flat(p - route_point(route_closest(p))).length()


## Distancia sobre la ruta del punto más cercano al centro del pueblo. Es el
## origen natural de todo lo que se mide «a lo largo del pueblo».
func route_centre_distance() -> float:
	return route_closest(play_centre)


# --------------------------------------------------------------------------
# Calles
# --------------------------------------------------------------------------

## Cuántas calles tiene el pueblo, sin contar la ruta.
func street_count() -> int:
	return streets.size()


## Eje de la calle [param index], o el de la ruta si [param index] es `0`.
##
## El índice sigue la convención de [member block_streets]: `-1` es «ningún
## lado da a una calle», `0` es la ruta y `1 + k` es `streets[k]`.
##
## Un índice **negativo devuelve vacío**, no la ruta. Antes `index <= 0` metía
## el `-1` de [method block_edge_street] —que quiere decir «este lado lo cortó
## el disco del pueblo, no una calle»— en el mismo cajón que la ruta, así que
## un lado sin calle declaraba dar a la ruta y medía diez metros de calzada que
## no existen.
func street_axis(index: int) -> PackedVector3Array:
	if index < 0:
		return PackedVector3Array()
	if index == 0:
		return route
	var slot := index - 1
	if slot >= streets.size():
		return PackedVector3Array()
	return streets[slot]


## Ancho de calzada de la calle [param index] (`0` = ruta, negativo = ninguna).
func street_width_of(index: int) -> float:
	if index < 0:
		return 0.0
	if index == 0:
		return route_width
	var slot := index - 1
	if slot >= street_widths.size():
		return 0.0
	return street_widths[slot]


## Vereda o banquina de la calle [param index] (`0` = ruta, negativo = ninguna).
func street_sidewalk_of(index: int) -> float:
	if index < 0:
		return 0.0
	if index == 0:
		return route_shoulder
	var slot := index - 1
	if slot >= street_sidewalks.size():
		return 0.0
	return street_sidewalks[slot]


## Media franja ocupada por la calle [param index]: calzada más vereda. Es la
## distancia del eje a la línea municipal.
func street_half_of(index: int) -> float:
	return street_width_of(index) * 0.5 + street_sidewalk_of(index)


# --------------------------------------------------------------------------
# Grafo del viario
# --------------------------------------------------------------------------

## Verdadero si el plano trae grafo. Los checks y el constructor lo preguntan
## antes de exigir nada: un plano de P2b no lo tiene y tiene que seguir
## cargando.
func has_graph() -> bool:
	return not nodes.is_empty() and street_nodes.size() >= 2


## Cuántas calles cubre el grafo: la ruta más las de [member streets]. Es el
## conteo que indexan [member street_nodes], [member street_kind] y
## [member street_closures].
func graph_street_count() -> int:
	return streets.size() + 1


## Nodo al que llega la punta [param end] (`0` = a, `1` = b) de la calle
## [param street], o `-1` si esa punta es un cabo declarado.
func node_of(street: int, end: int) -> int:
	var slot := street * 2 + clampi(end, 0, 1)
	if street < 0 or slot < 0 or slot >= street_nodes.size():
		return -1
	return street_nodes[slot]


## Metros que la punta [param end] de la calle [param street] se estira más allá
## de su nodo o de su último vértice.
func street_stub_of(street: int, end: int) -> float:
	var slot := street * 2 + clampi(end, 0, 1)
	if street < 0 or slot < 0 or slot >= street_stubs.size():
		return 0.0
	return street_stubs[slot]


## Clase de la calle [param street]. Sin declaración, la `0` es la ruta y el
## resto calles.
func street_kind_of(street: int) -> int:
	if street < 0:
		return StreetKind.STREET
	if street < street_kind.size():
		return street_kind[street]
	return StreetKind.ROUTE if street == 0 else StreetKind.STREET


## Cierre declarado en la punta [param end] de la calle [param street]:
## `gate`, `culvert`, `fence` o `none`.
##
## El formato guardado es `"a:kind;b:kind"`; leerlo acá —y no en cada
## consumidor— es lo que permite cambiarlo sin tocar al constructor ni al check.
func street_closure_of(street: int, end: int) -> StringName:
	if street < 0 or street >= street_closures.size():
		return &"none"
	var wanted := "a:" if end == 0 else "b:"
	for chunk: String in street_closures[street].split(";", false):
		var text := chunk.strip_edges()
		if text.begins_with(wanted):
			return StringName(text.substr(wanted.length()).strip_edges())
	return &"none"


## El nodo [param i] con `poly` y `radius` resueltos. Devuelve un diccionario
## vacío si el índice no existe.
func node_at(i: int) -> Dictionary:
	if i < 0 or i >= nodes.size():
		return {}
	var node := nodes[i]
	if not PackedVector2Array(node.get("poly", PackedVector2Array())).is_empty():
		return node
	node = node.duplicate()
	# El resolvedor del diseño deja `radius` escrito y `poly` vacío a propósito:
	# el radio es dato del grafo y el polígono es geometría, y la geometría la
	# hace [RoadMesh]. Si el radio no viene, se calcula una vez y se conserva.
	if float(node.get("radius", 0.0)) <= 0.0:
		node["radius"] = RoadMesh.node_radius(node)
	node["poly"] = RoadMesh.node_polygon(node)
	return node


## Polígono del cruce del nodo [param i], en XZ.
##
## Un nodo de grado uno —el final de una calle que sigue sola— no tiene cruce y
## devuelve vacío: lo que va ahí es un cierre, no asfalto.
func node_polygon(i: int) -> PackedVector2Array:
	var node := node_at(i)
	if node.is_empty():
		return PackedVector2Array()
	return node.get("poly", PackedVector2Array())


## Radio de boca del nodo [param i]: a cuántos metros de su centro se corta cada
## cinta que llega.
func node_radius(i: int) -> float:
	var node := node_at(i)
	return float(node.get("radius", 0.0)) if not node.is_empty() else 0.0


## Largo de la calle [param i] **entre sus dos nodos**, sin contar los cabos.
##
## Se mide sobre la polilínea y no en línea recta: una calle con un quiebre mide
## lo que se camina, que es lo que importa para decidir si una calle es corta.
func street_span(i: int) -> float:
	var axis := street_axis(i)
	if axis.size() < 2:
		return 0.0
	var from := 0.0
	var to := polyline_length(axis)
	var head := node_of(i, 0)
	if head >= 0 and head < nodes.size():
		from = polyline_closest(axis, nodes[head].get("pos", Vector3.ZERO))
	var tail := node_of(i, 1)
	if tail >= 0 and tail < nodes.size():
		to = polyline_closest(axis, nodes[tail].get("pos", Vector3.ZERO))
	return absf(to - from)


## Anillo de vereda de la manzana [param i]: el declarado, o el polígono de la
## manzana si el diseño no corrió la línea municipal.
func block_ring(i: int) -> PackedVector2Array:
	if i >= 0 and i < block_rings.size() and block_rings[i].size() >= 3:
		return block_rings[i]
	return block_polygon(i)


## Cota civil de la manzana [param i]. Sin terreno declarado es `0`, que es el
## mundo plano con el que corre hasta que WP-T2 entregue [TownTerrain].
func block_datum_of(i: int) -> float:
	if i < 0 or i >= block_datum.size():
		return 0.0
	return block_datum[i]


## Rellena `streets`, `angles`, `half_widths`, `poly` y `radius` de cada nodo a
## partir de `pos`, de [member street_nodes] y de la geometría de las calles.
##
## Es idempotente y determinista. Existe para que un plano **armado a mano**
## —un banco, una prueba— declare sólo el punto de cada nodo y qué calle va de
## cuál a cuál: derivar el rumbo y la media franja a mano sería pedir que se
## repita un número que ya está en otra parte, y dos copias de un número son dos
## números.
##
## ## No llamarlo sobre un plano resuelto
##
## [TownPlanner] ya entrega los nodos completos, y sabe cosas que esta rutina no
## puede deducir: en `town_a` cada transversal es **una sola calle que pasa de
## largo** por la ruta y por las dos paralelas de fondo, así que los cruces de
## la ruta tienen cuatro bocas. Acá las bocas de paso se reconstruyen por
## proximidad del eje al nodo, que funciona pero es una heurística; llamarlo
## sobre un plano ya resuelto sería reemplazar un dato por una inferencia.
func refresh_nodes() -> void:
	for index: int in nodes.size():
		var node := nodes[index]
		var pos: Vector3 = node.get("pos", Vector3.ZERO)
		var incident := PackedInt32Array()
		var angles := PackedFloat32Array()
		var halves := PackedFloat32Array()
		for street: int in graph_street_count():
			var axis := street_axis(street)
			if axis.size() < 2:
				continue
			var ends := 0
			for end: int in 2:
				if node_of(street, end) != index:
					continue
				ends += 1
				var direction := _street_heading(street, end)
				if direction.length_squared() < 0.000001:
					continue
				incident.append(street)
				angles.append(atan2(direction.z, direction.x))
				halves.append(street_half_of(street))
			if ends > 0:
				continue
			# La calle no termina acá pero puede **pasar** por el nodo, que es lo
			# que hace la ruta con las siete transversales: entra por una punta y
			# sale por la otra sin ser de ninguna. Un nodo de paso le abre dos
			# bocas, una por sentido; sin eso el cruce no tendría por dónde
			# seguir y la cinta se cortaría en seco contra un polígono cerrado.
			var at := polyline_closest(axis, pos)
			var span := polyline_length(axis)
			if at <= GRAPH_TOLERANCE or at >= span - GRAPH_TOLERANCE:
				continue
			if _flat(polyline_point(axis, at) - pos).length() > GRAPH_TOLERANCE:
				continue
			var tangent := polyline_tangent(axis, at)
			for sign: float in [1.0, -1.0]:
				incident.append(street)
				angles.append(atan2(tangent.z * sign, tangent.x * sign))
				halves.append(street_half_of(street))
		node["pos"] = pos
		node["streets"] = incident
		node["angles"] = angles
		node["half_widths"] = halves
		node["poly"] = PackedVector2Array()
		node["radius"] = 0.0
		node["radius"] = RoadMesh.node_radius(node)
		node["poly"] = RoadMesh.node_polygon(node)
		nodes[index] = node


## Rumbo con el que la calle [param street] **sale** del nodo de su punta
## [param end], normalizado y en XZ.
func _street_heading(street: int, end: int) -> Vector3:
	var axis := street_axis(street)
	if axis.size() < 2:
		return Vector3.ZERO
	var tip := axis[0] if end == 0 else axis[axis.size() - 1]
	var inward := axis[1] if end == 0 else axis[axis.size() - 2]
	# El rumbo es el de la calle **saliendo** del nodo, que es hacia adentro de
	# su propio eje: es lo que ordena las bocas alrededor del cruce.
	var delta := _flat(inward - tip)
	if delta.length() < 0.0001:
		return Vector3.ZERO
	return delta.normalized()


## Los incumplimientos del grafo, como lista de mensajes. Vacía quiere decir
## «grafo sano».
##
## Va aparte del check —mismo patrón que `town_plan_check._parcel_problems()`—
## para que las pruebas negativas puedan correr esta misma rutina sobre grafos
## rotos a mano: así se verifica que el check **mira**, no que la geometría
## funcione.
##
## Un plano sin grafo no incumple nada: devuelve vacío. Quien quiera exigir que
## el grafo exista pregunta antes por [method has_graph].
func graph_problems() -> Array[String]:
	var found: Array[String] = []
	if not has_graph():
		return found

	var count := graph_street_count()
	if street_nodes.size() != count * 2:
		found.append("street_nodes tiene %d entradas y las calles son %d (hacen falta %d)"
				% [street_nodes.size(), count, count * 2])
		return found

	# 1. Toda calle termina en un nodo o en un cabo declarado con cierre.
	for street: int in count:
		var axis := street_axis(street)
		if axis.size() < 2:
			found.append("la calle %d no tiene eje" % street)
			continue
		for end: int in 2:
			var node := node_of(street, end)
			var tip := axis[0] if end == 0 else axis[axis.size() - 1]
			if node < 0:
				# Una punta que se va del pueblo no es un cabo: es un camino que
				# sigue. La ruta sale por los dos lados hasta ±600 m y no tiene
				# por qué llevar tranquera; lo que el contrato persigue son las
				# calles que mueren **dentro** del disco, que es donde el jugador
				# las ve terminar en el aire.
				if distance_to_centre(tip) > block_radius:
					continue
				var closure := street_closure_of(street, end)
				if closure == &"none" or closure == &"":
					found.append("la punta %s de la calle %d es un cabo sin cierre declarado"
							% ["a" if end == 0 else "b", street])
				elif not RoadMesh.CLOSURE_KINDS.has(closure):
					found.append("la punta %s de la calle %d declara el cierre '%s', que no existe"
							% ["a" if end == 0 else "b", street, closure])
				continue
			if node >= nodes.size():
				found.append("la calle %d dice llegar al nodo %d, que no existe" % [street, node])
				continue
			var gap := _flat(tip - (nodes[node].get("pos", Vector3.ZERO) as Vector3)).length()
			if gap > GRAPH_TOLERANCE:
				found.append("la punta %s de la calle %d queda a %.2f m de su nodo %d (tope %.2f)"
						% ["a" if end == 0 else "b", street, gap, node, GRAPH_TOLERANCE])

	# 2 y 3. Ángulos incidentes y polígono de nodo.
	for index: int in nodes.size():
		var node := node_at(index)
		var angles: PackedFloat32Array = node.get("angles", PackedFloat32Array())
		var halves: PackedFloat32Array = node.get("half_widths", PackedFloat32Array())
		if angles.is_empty():
			found.append("el nodo %d no declara ninguna calle incidente" % index)
			continue
		for a: int in angles.size():
			for b: int in range(a + 1, angles.size()):
				var apart := rad_to_deg(absf(angle_difference(angles[a], angles[b])))
				if apart < GRAPH_ANGLE_MIN - 0.01:
					found.append("las calles %d y %d se encuentran en el nodo %d a %.1f°, mínimo %.0f"
							% [_incident(node, a), _incident(node, b), index, apart,
							GRAPH_ANGLE_MIN])
		if angles.size() < 2:
			continue
		var poly: PackedVector2Array = node.get("poly", PackedVector2Array())
		if not polygon_is_convex(poly, 0.02):
			found.append("el polígono del nodo %d no es convexo" % index)
			continue
		# El polígono tiene que contener las medias franjas: los dos extremos de
		# cada boca caen sobre su borde, nunca afuera.
		var centre := node.get("pos", Vector3.ZERO) as Vector3
		var radius := float(node.get("radius", 0.0))
		for slot: int in angles.size():
			var direction := Vector2(cos(angles[slot]), sin(angles[slot]))
			var side := Vector2(-direction.y, direction.x) * halves[slot]
			for sign: float in [-1.0, 1.0]:
				var mouth := Vector2(centre.x, centre.z) + direction * radius + side * sign
				if polygon_inset(poly, mouth) < -0.01:
					found.append("la media franja de la calle %d se sale del polígono del nodo %d"
							% [_incident(node, slot), index])
					break

	# 3b. Ningún nodo se come un quiebre de su calle.
	#
	#     La boca de un nodo es **recta** y perpendicular al rumbo con el que la
	#     calle sale de él. Si la calle quiebra antes de la boca, la cinta empalma
	#     con el otro tramo y las dos superficies se pisan justo en el cruce, que
	#     es el z-fighting que P2c viene a borrar. La regla es geométrica y no de
	#     gusto: el diseño tiene que dejar el nodo a más de un radio de boca del
	#     quiebre más cercano.
	for index: int in nodes.size():
		var node := node_at(index)
		var radius := float(node.get("radius", 0.0))
		var incident: PackedInt32Array = node.get("streets", PackedInt32Array())
		var centre := node.get("pos", Vector3.ZERO) as Vector3
		var seen: Dictionary[int, bool] = {}
		for street: int in incident:
			if seen.has(street):
				continue
			seen[street] = true
			var axis := street_axis(street)
			if axis.size() < 3:
				continue
			var at := polyline_closest(axis, centre)
			var travelled := 0.0
			for vertex: int in range(1, axis.size() - 1):
				travelled += _flat(axis[vertex] - axis[vertex - 1]).length()
				if absf(travelled - at) < radius - 0.01:
					found.append("el nodo %d se come el quiebre de la calle %d (a %.2f m, radio %.2f)"
							% [index, street, absf(travelled - at), radius])
					break

	# 4. Ningún par de calles se cruza sin nodo.
	for a: int in count:
		for b: int in range(a + 1, count):
			if _share_node(a, b):
				continue
			var hit := polyline_cross(street_axis(a), street_axis(b))
			if hit.is_empty():
				continue
			var point: Vector3 = hit["point"]
			var reach := maxf(street_half_of(a), street_half_of(b)) + GRAPH_CROSS_TOLERANCE
			if _nearest_node(point) > reach:
				found.append("las calles %d y %d se cruzan en (%.1f, %.1f) sin nodo"
						% [a, b, point.x, point.z])

	# 5. El anillo de vereda no se sale de su manzana.
	for index: int in block_rings.size():
		var ring := block_rings[index]
		if ring.size() < 3:
			continue
		var block := block_polygon(index)
		if block.size() < 3:
			found.append("el anillo de la manzana %d no tiene manzana" % index)
			continue
		for corner: Vector2 in ring:
			if polygon_contains(block, corner, -0.01):
				continue
			found.append("el anillo de la manzana %d se sale de ella" % index)
			break
	return found


## Índice de calle del brazo [param slot] de [param node].
func _incident(node: Dictionary, slot: int) -> int:
	var list: PackedInt32Array = node.get("streets", PackedInt32Array())
	return list[slot] if slot < list.size() else -1


## Verdadero si las calles [param a] y [param b] comparten al menos un nodo.
func _share_node(a: int, b: int) -> bool:
	for end_a: int in 2:
		var node := node_of(a, end_a)
		if node < 0:
			continue
		for end_b: int in 2:
			if node_of(b, end_b) == node:
				return true
	return false


## Distancia en XZ de [param point] al nodo más cercano, o `INF` si no hay.
func _nearest_node(point: Vector3) -> float:
	var best := INF
	for node: Dictionary in nodes:
		best = minf(best, _flat(point - (node.get("pos", Vector3.ZERO) as Vector3)).length())
	return best


# --------------------------------------------------------------------------
# Manzanas
# --------------------------------------------------------------------------

## Cuántas manzanas tiene el pueblo.
func block_count() -> int:
	return blocks.size()


## Polígono convexo de la manzana [param i], en XZ.
func block_polygon(i: int) -> PackedVector2Array:
	if i < 0 or i >= blocks.size():
		return PackedVector2Array()
	return blocks[i]


## Baricentro de la manzana [param i], con `y = 0`.
func block_centroid(i: int) -> Vector3:
	var flat := polygon_centroid(block_polygon(i))
	return Vector3(flat.x, 0.0, flat.y)


## Área de la manzana [param i], en metros cuadrados.
func block_area(i: int) -> float:
	return polygon_area(block_polygon(i))


## Calle a la que da el lado [param edge] de la manzana [param i], o `-1` si ese
## lado no da a ninguna (es el recorte contra el disco del pueblo).
func block_edge_street(i: int, edge: int) -> int:
	if i < 0 or i >= block_streets.size():
		return -1
	var tags := block_streets[i]
	if edge < 0 or edge >= tags.size():
		return -1
	return tags[edge]


# --------------------------------------------------------------------------
# Parcelas
# --------------------------------------------------------------------------

## Índices de las parcelas de rol [param role], en orden de plano.
func parcels_of_role(role: int) -> Array[int]:
	var found: Array[int] = []
	for index: int in parcels.size():
		if int(parcels[index].get("role", -1)) == role:
			found.append(index)
	return found


## Cuántas parcelas llevan un [Building] de verdad.
func destructible_count() -> int:
	var total := 0
	for parcel: Dictionary in parcels:
		if bool(parcel.get("destructible", false)):
			total += 1
	return total


## HP sumado de todo lo destructible. Es el número que recalibra el balance de
## `docs/11` §4.1: la integridad del pueblo se mide contra esto.
func total_hp() -> float:
	var total := 0.0
	for parcel: Dictionary in parcels:
		if not bool(parcel.get("destructible", false)):
			continue
		total += float(parcel.get("hp", 0.0))
	return total


## Índice de la parcela de la escuela, o `-1` si el plano no tiene.
func school_parcel() -> int:
	var found := parcels_of_role(Role.SCHOOL)
	return found[0] if not found.is_empty() else -1


## Posición del edificio de la parcela [param i]: el punto de frente corrido
## hacia adentro de la manzana media profundidad, a la altura de la vereda.
##
## Es **la** regla de apoyo del pueblo y vive acá para que el check la verifique
## sin copiarla de [CityGrid]: dos copias de una fórmula son dos fórmulas.
func parcel_position(i: int) -> Vector3:
	if i < 0 or i >= parcels.size():
		return Vector3.ZERO
	var parcel := parcels[i]
	var point: Vector3 = parcel.get("frontage_point", Vector3.ZERO)
	var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
	var depth := float(parcel.get("depth", 0.0))
	var base := float(parcel.get("base_y", SIDEWALK_TOP))
	return Vector3(point.x - normal.x * depth * 0.5, base,
			point.z - normal.z * depth * 0.5)


## Giro del edificio de la parcela [param i], en radianes. El `-Z` local de la
## pieza —su frente— queda mirando a la calle.
func parcel_yaw(i: int) -> float:
	if i < 0 or i >= parcels.size():
		return 0.0
	var normal: Vector3 = parcels[i].get("frontage_normal", Vector3.FORWARD)
	return atan2(-normal.x, -normal.z)


## Rectángulo de la huella de la parcela [param i] en XZ, como los cuatro
## vértices en orden. Lo usan el check (solapes, parcela dentro de su manzana) y
## el informe.
func parcel_footprint(i: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if i < 0 or i >= parcels.size():
		return out
	var parcel := parcels[i]
	var centre := parcel_position(i)
	var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
	var along := Vector2(-normal.z, normal.x)
	var into := Vector2(normal.x, normal.z)
	var half_w := float(parcel.get("width", 0.0)) * 0.5
	var half_d := float(parcel.get("depth", 0.0)) * 0.5
	var mid := Vector2(centre.x, centre.z)
	out.append(mid - along * half_w - into * half_d)
	out.append(mid + along * half_w - into * half_d)
	out.append(mid + along * half_w + into * half_d)
	out.append(mid - along * half_w + into * half_d)
	return out


# --------------------------------------------------------------------------
# Racionamiento de ventanas
# --------------------------------------------------------------------------

## Manzanas cuyas ventanas están apagadas esta partida (`docs/13` §1).
##
## El reparto es determinista por [member Global.round_seed] y de **tamaño
## fijo**: `round(manzanas · DARK_BLOCK_RATIO)`. Sortear cada manzana por
## separado con probabilidad 0,30 daría el mismo promedio pero una varianza
## enorme —con doce tiradas es normal salir con 1 o con 7—, y lo que el jugador
## ve en una partida no es el promedio: es esa partida. Por eso cada manzana
## recibe una **llave** de su propio generador sembrado con su índice y la
## semilla maestra, y se apagan las `K` llaves más bajas.
func dark_blocks() -> Dictionary:
	var signature := "%d|%d|%.3f" % [Global.round_seed, blocks.size(), DARK_BLOCK_RATIO]
	if signature == _dark_signature:
		return _dark_blocks
	_dark_signature = signature
	_dark_blocks = {}
	var keyed: Array[Dictionary] = []
	for block: int in blocks.size():
		keyed.append({
			"block": block,
			"key": mix_unit(mix_all([DARK_SEED_SALT, block, Global.round_seed])),
		})
	# Desempate por índice: dos llaves iguales no pueden depender del orden en
	# que `sort_custom` las visite, o el reparto dejaría de ser reproducible.
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["key"]), float(b["key"])):
			return float(a["key"]) < float(b["key"])
		return int(a["block"]) < int(b["block"]))
	var wanted := clampi(roundi(float(keyed.size()) * DARK_BLOCK_RATIO), 0, keyed.size())
	for index: int in wanted:
		_dark_blocks[int(keyed[index]["block"])] = true
	return _dark_blocks


## Verdadero si la manzana [param block] tiene las ventanas apagadas.
func is_block_dark(block: int) -> bool:
	return dark_blocks().has(block)


# --------------------------------------------------------------------------
# Marcadores
# --------------------------------------------------------------------------

## Los cuatro accesos del coloso, mirando al centro.
func spawn_points() -> Array[Transform3D]:
	return spawns


## Los ocho puestos de pila: cinco en cruce de calle y tres en azotea.
func battery_posts() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for point: Vector3 in battery:
		found.append(point)
	return found


## Aparición del dron, sobre la ruta y mirando al pueblo.
func drone_spawn() -> Transform3D:
	return drone


## Pose de la cámara fija.
func camera_fixed() -> Transform3D:
	return camera


## Las seis rocas del borde.
func rock_spots() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for point: Vector3 in rocks:
		found.append(point)
	return found


## Maleza, basura y barriles.
func decor_spots() -> Array[Transform3D]:
	return decor


## Ángulo en grados entre el rumbo de aparición del dron y [param spot].
func spawn_view_angle(spot: Vector3) -> float:
	var facing := -drone.basis.z
	return flat_angle(facing, spot - drone.origin)


## Ángulo en grados entre la línea aparición → centro y [param spot].
func spawn_cone_angle(spot: Vector3) -> float:
	return flat_angle(play_centre - drone.origin, spot - drone.origin)


## Mezclador entero determinista (splitmix64).
##
## Reemplaza a `hash("texto:%d")`. `String.hash()` es un detalle de
## implementación del motor: no está documentado como estable entre versiones de
## Godot ni entre plataformas, y de él dependían **qué manzanas se apagan** y
## **en qué orden se llenan de casas los lados de manzana**. Un cambio de motor
## habría movido el pueblo entero sin que ningún check lo notara, porque todos
## comparan el plano contra sí mismo.
##
## splitmix64 es media docena de operaciones, no tiene estado y está definido
## sobre enteros de 64 bits, que es exactamente lo que GDScript garantiza.
static func mix(value: int) -> int:
	var z := value + -7046029254386353131  # 0x9E3779B97F4A7C15
	z = (z ^ (z >> 30)) * -4658895280553007687  # 0xBF58476D1CE4E5B9
	z = (z ^ (z >> 27)) * -7723592293110705685  # 0x94D049BB133111EB
	return z ^ (z >> 31)


## Mezcla varios enteros en uno solo, en orden.
static func mix_all(values: Array[int]) -> int:
	var acc := 0
	for value: int in values:
		acc = mix(acc ^ mix(value))
	return acc


## Flotante en `[0, 1)` determinista a partir de [param key].
static func mix_unit(key: int) -> float:
	# Se usan los 53 bits altos, que es lo que un `float` representa sin perder
	# nada, y se fuerza el signo para que el módulo no dependa del complemento.
	return float((mix(key) >> 11) & 0x1FFFFFFFFFFFFF) / float(0x20000000000000)


## Ángulo en grados entre dos direcciones, medido en XZ.
static func flat_angle(reference: Vector3, target: Vector3) -> float:
	var a := Vector2(reference.x, reference.z)
	var b := Vector2(target.x, target.z)
	if a.length_squared() < 0.01 or b.length_squared() < 0.01:
		return 0.0
	return rad_to_deg(absf(a.normalized().angle_to(b.normalized())))


# --------------------------------------------------------------------------
# Geometría: polilíneas
# --------------------------------------------------------------------------

## Largo de una polilínea, medido en XZ.
static func polyline_length(line: PackedVector3Array) -> float:
	var total := 0.0
	for index: int in maxi(line.size() - 1, 0):
		total += _flat(line[index + 1] - line[index]).length()
	return total


## Punto a [param distance] metros del primer vértice, extrapolando fuera de
## rango sobre la recta del tramo extremo.
static func polyline_point(line: PackedVector3Array, distance: float) -> Vector3:
	if line.is_empty():
		return Vector3.ZERO
	if line.size() == 1:
		return line[0]
	var remaining := distance
	for index: int in line.size() - 1:
		var delta := line[index + 1] - line[index]
		var span := _flat(delta).length()
		if span <= 0.0001:
			continue
		var last := index == line.size() - 2
		if remaining <= span or last:
			return line[index] + delta * (remaining / span)
		remaining -= span
	return line[line.size() - 1]


## Tangente unitaria a [param distance] metros.
static func polyline_tangent(line: PackedVector3Array, distance: float) -> Vector3:
	if line.size() < 2:
		return Vector3.FORWARD
	var remaining := distance
	for index: int in line.size() - 1:
		var delta := _flat(line[index + 1] - line[index])
		var span := delta.length()
		if span <= 0.0001:
			continue
		if remaining <= span or index == line.size() - 2:
			return delta / span
		remaining -= span
	return Vector3.FORWARD


## Distancia sobre la polilínea del punto más cercano a [param p].
static func polyline_closest(line: PackedVector3Array, p: Vector3) -> float:
	var best := 0.0
	var best_distance := INF
	var travelled := 0.0
	var flat_p := _flat(p)
	for index: int in maxi(line.size() - 1, 0):
		var a := _flat(line[index])
		var b := _flat(line[index + 1])
		var delta := b - a
		var span := delta.length()
		if span <= 0.0001:
			continue
		var t := clampf((flat_p - a).dot(delta) / (span * span), 0.0, 1.0)
		var distance := (flat_p - (a + delta * t)).length()
		if distance < best_distance:
			best_distance = distance
			best = travelled + span * t
		travelled += span
	return best


## Corte en XZ de dos polilíneas.
##
## Devuelve un diccionario con cuatro claves, o **uno vacío** si no se cruzan:
##
## - `point: Vector3` — dónde se cruzan, con `y = 0`.
## - `angle: float` — ángulo entre las dos tangentes en el corte, en grados y
##   siempre en `[0, 90]`: dos calles que se cruzan a 120° se encuentran a 60°,
##   que es el número que el diseño mira.
## - `t_a`, `t_b: float` — distancia sobre cada polilínea desde su primer
##   vértice hasta el corte, en metros.
##
## **Cambió de contrato en P2c** (plan §2): antes devolvía sólo el punto, o
## `null`. El grafo necesita el ángulo y las dos distancias para decidir si un
## cruce merece un nodo y dónde ponerlo, y devolver cuatro valores en cuatro
## llamadas sería recorrer las dos polilíneas cuatro veces. Para el código que
## sólo quiere el punto queda [method polyline_cross_point], que conserva la
## firma vieja tal cual.
static func polyline_cross(a: PackedVector3Array, b: PackedVector3Array) -> Dictionary:
	var travelled_a := 0.0
	for i: int in maxi(a.size() - 1, 0):
		var p := Vector2(a[i].x, a[i].z)
		var r := Vector2(a[i + 1].x, a[i + 1].z) - p
		var travelled_b := 0.0
		for j: int in maxi(b.size() - 1, 0):
			var q := Vector2(b[j].x, b[j].z)
			var s := Vector2(b[j + 1].x, b[j + 1].z) - q
			var denominator := r.cross(s)
			if absf(denominator) < 0.000001:
				travelled_b += s.length()
				continue
			var t := (q - p).cross(s) / denominator
			var u := (q - p).cross(r) / denominator
			if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
				travelled_b += s.length()
				continue
			var hit := p + r * t
			var apart := rad_to_deg(absf(r.normalized().angle_to(s.normalized())))
			return {
				"point": Vector3(hit.x, 0.0, hit.y),
				"angle": minf(apart, 180.0 - apart),
				"t_a": travelled_a + r.length() * t,
				"t_b": travelled_b + s.length() * u,
			}
		travelled_a += r.length()
	return {}


## Sólo el punto de corte de dos polilíneas, o `null` si no se cruzan.
##
## Es la firma que tenía [method polyline_cross] hasta P2b y se conserva para
## que quien no necesite el grafo no tenga que desempacar un diccionario.
static func polyline_cross_point(a: PackedVector3Array, b: PackedVector3Array) -> Variant:
	var hit := polyline_cross(a, b)
	return hit["point"] if not hit.is_empty() else null


## Proyección de [param v] al plano XZ, con `y = 0`.
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Normal izquierda unitaria de una dirección en XZ. «Izquierda» es girar 90°
## hacia `-X` mirando desde arriba con `+Y`; la elección es arbitraria pero
## tiene que ser **una sola** en todo el plano o los frentes salen espejados.
static func left_of(direction: Vector3) -> Vector3:
	var flat := _flat(direction)
	if flat.length_squared() < 0.000001:
		return Vector3.LEFT
	flat = flat.normalized()
	return Vector3(flat.z, 0.0, -flat.x)


# --------------------------------------------------------------------------
# Geometría: polígonos convexos
# --------------------------------------------------------------------------

## Área con signo de un polígono en XZ.
static func polygon_signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for index: int in poly.size():
		var a := poly[index]
		var b := poly[(index + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## Área de un polígono, siempre positiva.
static func polygon_area(poly: PackedVector2Array) -> float:
	return absf(polygon_signed_area(poly))


## Baricentro de un polígono. Cae al promedio de vértices si el área es nula,
## que es lo único razonable para un polígono degenerado.
static func polygon_centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var area := polygon_signed_area(poly)
	if absf(area) < 0.0001:
		var sum := Vector2.ZERO
		for point: Vector2 in poly:
			sum += point
		return sum / float(poly.size())
	var acc := Vector2.ZERO
	for index: int in poly.size():
		var a := poly[index]
		var b := poly[(index + 1) % poly.size()]
		var cross := a.x * b.y - b.x * a.y
		acc += (a + b) * cross
	return acc / (6.0 * area)


## Verdadero si el polígono es convexo (con la tolerancia que deja el recorte en
## coma flotante) y no degenerado.
static func polygon_is_convex(poly: PackedVector2Array, tolerance: float = 0.05) -> bool:
	if poly.size() < 3:
		return false
	var sign_seen := 0
	for index: int in poly.size():
		var a := poly[index]
		var b := poly[(index + 1) % poly.size()]
		var c := poly[(index + 2) % poly.size()]
		var cross := (b - a).cross(c - b)
		if absf(cross) <= tolerance:
			continue
		var sign := 1 if cross > 0.0 else -1
		if sign_seen == 0:
			sign_seen = sign
		elif sign != sign_seen:
			return false
	return sign_seen != 0


## Normal exterior unitaria del lado [param edge] de un polígono convexo.
static func polygon_edge_normal(poly: PackedVector2Array, edge: int) -> Vector2:
	if poly.size() < 3:
		return Vector2.ZERO
	var a := poly[edge % poly.size()]
	var b := poly[(edge + 1) % poly.size()]
	var delta := b - a
	var length := delta.length()
	if length <= 0.0001:
		return Vector2.ZERO
	var winding := 1.0 if polygon_signed_area(poly) >= 0.0 else -1.0
	return Vector2(delta.y, -delta.x) / length * winding


## Verdadero si [param point] está dentro del polígono convexo [param poly], con
## [param margin] metros de holgura hacia adentro (negativo = hacia afuera).
static func polygon_contains(poly: PackedVector2Array, point: Vector2,
		margin: float = 0.0) -> bool:
	return polygon_inset(poly, point) >= margin


## Distancia de [param point] al lado más cercano del polígono convexo,
## positiva hacia adentro y negativa hacia afuera.
static func polygon_inset(poly: PackedVector2Array, point: Vector2) -> float:
	if poly.size() < 3:
		return -INF
	var best := INF
	for index: int in poly.size():
		var outward := polygon_edge_normal(poly, index)
		if outward == Vector2.ZERO:
			continue
		best = minf(best, -(point - poly[index]).dot(outward))
	return best


## Verdadero si dos polígonos convexos se solapan, por el teorema del eje
## separador. Con [param tolerance] metros de holgura: dos parcelas que se tocan
## justo en el borde no se consideran superpuestas.
static func polygons_overlap(a: PackedVector2Array, b: PackedVector2Array,
		tolerance: float = 0.01) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	for poly: PackedVector2Array in [a, b]:
		for index: int in poly.size():
			var p := poly[index]
			var q := poly[(index + 1) % poly.size()]
			var edge := q - p
			if edge.length_squared() <= 0.000001:
				continue
			var axis := Vector2(edge.y, -edge.x).normalized()
			var a_min := INF
			var a_max := -INF
			for point: Vector2 in a:
				var value := point.dot(axis)
				a_min = minf(a_min, value)
				a_max = maxf(a_max, value)
			var b_min := INF
			var b_max := -INF
			for point: Vector2 in b:
				var value := point.dot(axis)
				b_min = minf(b_min, value)
				b_max = maxf(b_max, value)
			if a_max <= b_min + tolerance or b_max <= a_min + tolerance:
				return false
	return true


# --------------------------------------------------------------------------
# Formato
# --------------------------------------------------------------------------

## Normaliza el **cero negativo**.
##
## `-0.0` y `0.0` son el mismo número, comparan iguales y `is_equal_approx()` no
## los distingue, pero `"%.3f"` imprime `-0.000` y `0.000`. Y el `.tscn` guarda
## `-0.0` como `0`, así que un plano recién generado y el mismo plano después de
## pasar por disco daban firmas distintas y `city_check` declaraba
## «desactualizado» un pueblo recién horneado.
##
## Aparece en las normales de frente: `-normal` con `normal.y == 0.0` da `-0.0`.
static func _zero(value: float) -> float:
	return 0.0 if value == 0.0 else value


static func _ints(list: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: int in list:
		parts.append(str(value))
	return ",".join(parts)


## Lista de flotantes a milímetros, con el cero negativo normalizado por el
## mismo motivo que [method _zero].
static func _floats(list: PackedFloat32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: float in list:
		parts.append("%.4f" % _zero(value))
	return ",".join(parts)


static func _v3(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [_zero(v.x), _zero(v.y), _zero(v.z)]


static func _v3_list(list: PackedVector3Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for point: Vector3 in list:
		parts.append(_v3(point))
	return "".join(parts)


static func _v2_list(list: PackedVector2Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for point: Vector2 in list:
		parts.append("(%.3f,%.3f)" % [_zero(point.x), _zero(point.y)])
	return "".join(parts)


static func _xform(xform: Transform3D) -> String:
	return "%s@%.3f" % [_v3(xform.origin), _zero(xform.basis.get_euler().y)]


static func _xform_list(list: Array[Transform3D]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for xform: Transform3D in list:
		parts.append(_xform(xform))
	return "".join(parts)
