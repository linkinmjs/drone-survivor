## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Constructor del **pueblo de ruta** (`docs/10` §4, reescrito por WP-B).
##
## Toma un [TownPlan] —que es aritmética pura, sin un solo asset— y lo convierte
## en escena: una caja de suelo, la red viaria en cinco [MultiMeshInstance3D] sin
## colisión, un [Building] por parcela destructible, dos caseríos decorativos,
## seis rocas y los marcadores de la ronda. El resultado se empaqueta como
## `city/districts/town_a.tscn` desde `tools/build_town.gd`.
##
## Es `@tool` para poder regenerar el pueblo desde el editor, pero **nunca**
## construye sola: [method build] se llama a mano o desde la herramienta. El
## pueblo se comitea como escena concreta y no se siembra en cada arranque
## (`docs/10` §12, decisión 10), así que la iluminación, las capturas y los
## checks son reproducibles.
##
## ## Conserva el nombre de clase
##
## Diez archivos están tipados contra `CityGrid`, así que la clase sigue
## llamándose igual aunque ya no haya rejilla ninguna. Lo que se fue es el
## **modelo de carriles** (`lane_count`, `lane_kind`, `cell_position`,
## `block_cell`, `avenue_crossing`…): un pueblo de ruta no tiene carriles, tiene
## una ruta y calles que la cruzan en ángulos que no son rectos, y mantener una
## API que devolviera carriles falsos habría sido peor que quitarla. Quien
## necesita geometría se la pide al plano con [method get_plan].
##
## ## Qué sobrevive del distrito rectangular
##
## Todo lo que no dependía de la rejilla: el horneado de mallas de pieza, el
## búfer crudo de [MultiMesh], la malla de asfalto liso de los cruces, el armado
## completo de un [Building] con sus etapas —incluido el desclonado de la
## [BoxShape3D], que es lo que evita que la variación de altura de un edificio
## reescriba la de sus hermanos— y el racionamiento de ventanas por manzana.
@tool
class_name CityGrid extends Node3D

## Nombres de los contenedores generados. `build()` los recrea de cero.
const BUILDINGS_NODE: StringName = &"Buildings"
const STREETS_NODE: StringName = &"Streets"
const DECOR_NODE: StringName = &"Decor"
const ROCKS_NODE: StringName = &"Rocks"

## El contenedor de props, **uno solo**.
##
## Nombra tres cosas que son la misma idea: el contenedor de props posicionales
## que cuelga de la rejilla, el prefijo de los [MultiMesh] de maleza de campo y
## el nodo de props de azotea de un [Building]. Hasta WP-D4a había dos constantes
## —`PROPS_NODE` y `TOWN_PROPS_NODE`— con exactamente el mismo valor, y dos
## nombres para una cosa invitan a que un día digan cosas distintas (hallazgo 25).
const PROPS_NODE: StringName = &"Props"

const SPAWNS_NODE: StringName = &"Spawns"
const POSTS_NODE: StringName = &"BatteryPosts"
const GROUND_NODE: StringName = &"Ground"

## Los cinco contenedores que estrena WP-D2 (`docs/17` §2 y §3).
##
## - [constant PLAZA_NODE] — el piso de la plaza y sus canteros.
## - [constant GROVES_NODE] — un [MultiMeshInstance3D] por especie de follaje.
## - [constant FENCES_NODE] — un [MultiMeshInstance3D] por clase de cerco.
## - [constant PROPS_NODE] — los props posicionales, agrupados por pieza.
## - [constant BRIDGE_NODE] — el tablero sobre el arroyo.
## - [constant CREEK_NODE] — la lámina de agua del arroyo.
const PLAZA_NODE: StringName = &"Plaza"
const GROVES_NODE: StringName = &"Groves"
const FENCES_NODE: StringName = &"Fences"
const BRIDGE_NODE: StringName = &"Bridge"
const CREEK_NODE: StringName = &"Creek"

## Piezas que no entran en el pase de sombra. Ver [method _casts_shadow].
##
## Vive con las demás constantes y no enterrada a mil setecientas líneas junto a
## su único lector (WP-D4a, hallazgo 25): es una tabla de datos de nivel, como
## [constant TownPlanner.PIECE_HEIGHT], y quien la busca la busca acá.
const NO_SHADOW_PIECES: Array[StringName] = [
	&"gas_station", &"field_shed", &"block_mid", &"block_low_c",
]

## Cuánto sube el espejo de agua sobre el fondo del cauce, en metros.
##
## El canal del relieve tiene 2,4 m de profundidad (`creek.depth` del diseño), así
## que 0,6 m de agua dejan 1,8 m de talud a la vista: un arroyo de campo con la
## orilla seca, que es lo que pide `docs/17` §3, y no un canal lleno hasta el
## borde. Es además lo que mantiene el aire bajo el tablero por encima del metro
## y medio que verifica `city_check`.
const CREEK_WATER_RISE: float = 0.60

## Aire mínimo entre el espejo de agua y la cara de abajo del tablero, en metros.
## Es el mismo número que `city_check.BRIDGE_CLEARANCE` mide contra el terreno:
## el agua no puede comérselo.
const CREEK_BRIDGE_CLEARANCE: float = 1.50

## Hasta dónde llega el agua, medido desde el centro del pueblo.
##
## El relieve esculpido se desvanece entre 230 y 256 m (`terrain.fade` del
## diseño) y con él se desvanece el canal: más allá de unos 245 m el fondo del
## cauce ya está a cero y los bancos también, así que una lámina a `fondo + 0,6`
## sería una cinta de agua **flotando** sobre el campo llano. El eje del arroyo
## se recorta a este radio, que deja el agua entera dentro del canal tallado y
## un poco más adentro que el corte de las arboledas del arroyo (r 250 m del
## diseño), así que el agua termina debajo de los sauces y no a la vista.
##
## Medido con la sonda de WP-D3 sobre el relieve horneado: a r 249,1 m el eje
## está a −0,678 m y el banco exterior a −0,711 —o sea **por debajo** del eje,
## que es el canal ya invertido por el desvanecido—; a r 240 el canal todavía
## tiene su forma.
const CREEK_WATER_REACH: float = 240.0

## Cuánto se subdivide la cinta de agua a lo largo, en metros. El eje del arroyo
## tiene vértices cada 25–60 m y el fondo del cauce ondula: sin subdividir, el
## espejo cortaría el talud entre vértice y vértice.
const CREEK_STEP: float = 4.0

## A cuántos metros dejan de dibujarse el follaje, los cercos y los props.
##
## No es un recorte por distancia de los de P2b —aquél no ahorraba nada porque
## el pueblo mide trescientos metros—: acá lo que se recorta está **afuera**. Los
## maizales viven entre 260 y 450 m del centro y el alambrado de la ruta llega a
## 560 m, así que desde la plaza no se dibujan, y desde el maizal no se dibuja el
## alambrado del otro extremo.
##
## ## Es por nodo, no por instancia
##
## El docstring decía que un [MultiMesh] «nunca se descarta por culling porque su
## AABB cubre todas sus instancias», y lo daba a entender como si el recorte por
## distancia sí fuera fino. No lo es: el motor mide **una** distancia por nodo
## —del ojo al centro del AABB transformado del nodo— y apaga o enciende el nodo
## entero. Las mil cuatrocientas instancias de sauce son un solo `sí` o un solo
## `no`, y por eso el tamaño del AABB de cada grupo importa tanto como el
## número: un [MultiMesh] que abarca los dos maizales tiene su centro en el medio
## de los dos y se apaga —o se enciende— para los dos a la vez. Lo mismo mide
## `tools/city_check.gd._decor_lots()` desde WP-D4a (hallazgo 7).
const GROVE_RANGE: float = 300.0
const FENCE_RANGE: float = 300.0
const PROP_RANGE: float = 170.0

## Sobre cuántos metros se desvanece un grupo de decorado antes de apagarse.
##
## Con `visibility_range_end_margin` en cero —que es lo que quedaba— el modo
## [constant GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF] no tiene sobre qué
## desvanecer y el nodo **parpadea**: mil cuatrocientos árboles aparecen y
## desaparecen de golpe en cuanto el dron cruza la cota. Veinte metros son menos
## de un segundo de vuelo a la velocidad de crucero y el doble del jitter que
## mete el centro del AABB de un grupo (WP-D4a, hallazgo 7).
const VISIBILITY_FADE_MARGIN: float = 20.0

## Desde cuántas instancias una pieza de prop merece su propio
## [MultiMeshInstance3D].
##
## Por debajo de eso se funde con las demás en una malla estática: un MultiMesh
## para dos bancos cuesta el mismo lote de dibujo que uno para doce farolas y
## compra mucho menos. Los props son geometría chica y quieta, así que fundirlos
## no pierde nada —es la misma decisión que tomó el viario en WP-T1.
const PROP_MULTIMESH_MIN: int = 8

## Cuánto se mete hacia adentro el piso de la plaza respecto de su polígono, y
## dónde empiezan los canteros de pasto del centro, en metros.
const PLAZA_INSET: float = 1.0
## El cantero central se mete **catorce** metros y no ocho: con ocho, el pasto
## cubría casi toda la plaza y al anochecer la manzana 9 se leía desde el aire
## como un pozo negro con un marco claro, que es lo contrario de lo que la losa
## viene a hacer. Con catorce queda un cantero de diez o quince metros alrededor
## del mástil y del monumento, y la losa es la que manda.
const PLAZA_LAWN_INSET: float = 14.0

## Cuánto sobresale del vano la corrección de cota de la calzada, a cada lado y
## en metros. Ver [method route_height_fn].
const BRIDGE_MARGIN: float = 1.0

## Espesor y sobreancho de la losa de colisión del tablero, en metros. La pieza
## de WP-D1 no trae cuerpo: ver [method _add_bridge_collision].
const BRIDGE_DECK_THICKNESS: float = 0.8
const BRIDGE_DECK_MARGIN: float = 4.0

## Marcadores sueltos que cuelgan de la raíz.
const DRONE_NODE: StringName = &"DroneSpawn"
const CENTRE_NODE: StringName = &"TownCentre"
const CAMERA_NODE: StringName = &"CameraFixedPose"

## Grupo del marcador del centro del pueblo, que es lo que buscan el jefe y la
## cámara de la intro sin conocer a esta clase.
const CENTRE_GROUP: StringName = &"town_centre"

## Ruta a las rocas, que cuelgan de [constant DECOR_NODE].
const ROCKS_PATH: String = "Decor/Rocks"

## Los dos nodos de la red viaria (P2c, WP-T1 y WP-T4).
##
## - [constant ASPHALT_NODE] — **una** [MeshInstance3D] con todo el asfalto del
##   pueblo: la ruta entera, las calles y los polígonos de cruce, fundidos en una
##   sola superficie con `roads.tres`.
## - [constant WALKWAYS_NODE] — **una** [MeshInstance3D] con los anillos de
##   vereda y los cierres de cabo, con `walkway.tres`.
##
## Eran cinco MultiMesh en P2b (`RoadRoute`, `RoadStreets`, `Crossings`,
## `Sidewalks`, `BlockPads`, 1 013 instancias). El cambio no es de rendimiento
## sino de modelo: un cruce no es un parche cuadrado apoyado sobre la calzada,
## es el polígono que queda entre las bocas de las calles que llegan, y eso no se
## puede instanciar.
##
## ## Por qué ya no queda ni una baldosa de ruta
##
## WP-T1 dejó la ruta de **afuera** del disco como una cadena de `Road_Chunk_5`
## de 10 m: sobre el plano `y = 0` de P2b una baldosa plana apoyaba exacto y
## costaba un solo lote. Con el relieve de WP-T2 debajo deja de apoyar. Medido
## sobre el terreno horneado, una baldosa de 10 m inclinada por sus dos extremos
## y puesta a la cota media se separa del terreno entre **−1,5 cm y +8,5 cm**
## —se entierra en un extremo y flota en el otro— contra la banda de
## `[0,01; 0,08]` m que pide el criterio 1 del plan; con baldosas de 5 m todavía
## se entierra a 0,9 cm. La culpa no es del pueblo sino del **desvanecido**: la
## ruta cruza el anillo de 230 a 256 m donde el perfil se apaga contra el plano
## lejano, y ahí el terreno llega a un 5,4 % de pendiente con toda su curvatura
## concentrada. La cinta, que se subdivide cada 2,5 m con la altura del terreno,
## se queda en `[0,025; 0,036]` m en los 1 127 m de ruta: entra holgada. Así que
## la cinta cubre la ruta entera y `RoadRoute` desaparece —un lote de dibujo
## menos y un modelo menos que explicar.
const ASPHALT_NODE: StringName = &"Asphalt"
const WALKWAYS_NODE: StringName = &"Walkways"

## Script que se pone sobre la raíz de cada pieza al sembrarla (`docs/10` §2.5).
const BUILDING_SCRIPT: String = "res://city/building.gd"

## Nodo de colisión que dejó el post-import en cada pieza.
const PIECE_SHAPE: StringName = &"IntactShape"

## Capas de `docs/10` §9.4.
const GROUND_LAYER: int = 1
const GROUND_MASK: int = 294

## Fracción de manzanas que se queda sin luz en las ventanas. El reparto lo hace
## el plano; la constante se conserva acá porque hay checks que la citan.
const DARK_BLOCK_RATIO: float = TownPlan.DARK_BLOCK_RATIO

## Alturas a las que se apoyan calzada y veredas, en metros **sobre el terreno**.
## La diferencia (15 cm) es el cordón visible.
const ROAD_TOP: float = 0.03
const SIDEWALK_TOP: float = 0.18

## Cuántas mallas de terreno cuelga [method _build_ground] (`tools/build_terrain.gd`
## hornea una rejilla de 2 × 2 de 260 m de alcance).
const TERRAIN_CHUNKS: int = 4

## Hasta dónde llegan los chunks del terreno desde el centro del pueblo, en
## metros, y de dónde a dónde va el anillo de campo lejano.
##
## El **agujero** del anillo coincide con el borde de los chunks y no con el
## radio de desvanecido (256 m): así los dos comparten literalmente la junta, y
## no hay una franja de cuatro metros con dos superficies a `y = 0` peleándose
## el depth buffer. Entre 256 y 260 m el terreno ya vale cero exacto, así que la
## junta es plana de los dos lados.
const TERRAIN_REACH: float = 260.0
const FIELD_REACH: float = 600.0

## Paso con el que se subdivide el anillo de campo, en metros. No es por
## iluminación —el sol es por píxel— sino por la niebla de distancia y por el
## culling: un cuadrilátero de 344 × 1 200 m nunca se descarta y su interpolación
## de profundidad es la peor posible.
const FIELD_STEP: float = 60.0

## Cuánto se hunde una roca en el terreno, en metros. Una roca apoyada exacto
## sobre la cota se lee como una piedra puesta encima del pasto; hundida veinte
## centímetros se lee como una piedra que estaba ahí.
const ROCK_SINK: float = 0.20

## Cara superior de la caja de seguridad, en metros. Está por debajo del punto
## más bajo del relieve (el lecho del arroyo, −5,53 m en el horneado de WP-T2):
## es la red que atrapa a un cuerpo que se escapó del heightfield, no un piso.
const SAFETY_TOP: float = -6.0

## Metadato que marca a una pieza de pueblo (lo escribe
## `asset_import/import_town_piece.gd`).
##
## Hace falta porque las dos familias de pieza **no tienen la fachada en el
## mismo eje**: las FBX de VoxelCity la tienen en `-Z` —su lado largo es X y es
## lo que daba a la calle en la rejilla cartesiana— y las GLB de WP-A la tienen
## en `-X` (puerta y carteles). Sin esto la mitad del pueblo mostraría a la
## calle su pared lateral, que es el tipo de error que no se ve en el informe y
## se ve en la primera captura.
const TOWN_PIECE_META: StringName = &"town_kind"

## Cuarto de vuelta que se le suma al giro de una pieza de pueblo para que su
## `-X` local quede donde el `-Z` de una pieza FBX. Ver [constant TOWN_PIECE_META].
const TOWN_YAW_OFFSET: float = -PI * 0.5

## Semiángulo del cono de visión inicial que ninguna roca puede invadir.
const SPAWN_CONE_DEG: float = 30.0
const SPAWN_VIEW_CONE_DEG: float = 20.0

## Proporción de azoteas de edificio grande con prop (`docs/10` §4.3).
const PROP_CHANCE: float = 0.30


# --------------------------------------------------------------------------
# Propiedades
# --------------------------------------------------------------------------

## El plano del pueblo. Se guarda como **sub-recurso** de `town_a.tscn`: es el
## dato del que sale todo lo demás y tiene que viajar con la escena, o el mapa
## de la alerta y los puestos de pila se quedarían sin geometría al cargarla.
@export var plan: TownPlan = null

## Relieve del pueblo (`TownTerrain`, WP-T2). Mientras sea nulo el mundo es el
## plano `y = 0` y todo el viario apoya ahí.
##
## **Hay que asignarlo antes de [method build]**: de él salen la forma de
## colisión del suelo, la cota de cada cinta de calzada, la de cada anillo de
## vereda y la de todo lo que se siembra afuera del círculo.
##
## Va tipado como [Resource] y no como [TownTerrain] a propósito: la clase la
## entrega otro encargo y tipar contra ella ataría el horneado del viario a que
## exista. Lo que [method terrain_height_fn] le pide es un `height_at(x, z)`,
## resuelto por `has_method`, que es el mismo despacho flojo con el que
## [method occluder_for] y `is_building_dark` cruzan la frontera entre clases.
@export var terrain: Resource = null

## Forma de colisión del relieve (`HeightMapShape3D` de 513², WP-T2).
##
## Va como propiedad y no se deriva de [member terrain] con `build_shape()` a
## propósito: el `.res` horneado se comparte entre la escena del pueblo y los
## bancos, y construirla en cada `build()` metería un megabyte de alturas
## **dentro** de `town_a.tscn`.
@export var terrain_shape: Shape3D = null

## Las cuatro mallas de relieve, en coordenadas del distrito. Se cuelgan en el
## origen y no se mueven ni se escalan.
@export var terrain_chunks: Array[Mesh] = []

## Material de las cuatro mallas de relieve (`assets/city/materials/terrain.tres`).
@export var terrain_material: Material = null

## Piezas por identificador de parcela: `{StringName: PackedScene}`. El plano
## dice `&"house_a"`; la tabla dice qué `.tscn` es. Sustituir una pieza por otra
## —lo que hay que hacer mientras las casas de WP-A no existen— es cambiar una
## entrada de `tools/build_town.gd`.
##
## El diccionario va **sin tipar**: `tools/build_town.gd` corre con `-s` y
## despacha todo por `Variant` (los autoload no existen cuando se compila su
## script), y asignarle un `Dictionary` pelado a una propiedad
## `Dictionary[StringName, PackedScene]` es un error de asignación en tiempo de
## ejecución. [method _piece_for] hace la conversión de una sola vez.
@export var pieces: Dictionary = {}

## Perfil de las casas (1 300 HP) y de los edificios grandes (3 500 HP).
@export var house_profile: BuildingProfile = null
@export var big_profile: BuildingProfile = null

## Carteles y antenas de azotea, sólo para los edificios grandes.
@export var prop_pieces: Array[PackedScene] = []

## Rocas del borde, en el grupo `city_rocks`.
@export var rock_scenes: Array[PackedScene] = []

## `Road_Chunk_5`. Ya no se instancia ni una baldosa: la pieza se conserva
## porque de su malla sale el material `roads.tres` con el que se pinta **todo**
## el asfalto del pueblo, marcas viales incluidas.
@export var road_piece: PackedScene = null

## Piezas de maleza, basura y barriles. Cada una da su propio
## [MultiMeshInstance3D] bajo `Decor`: un [MultiMesh] lleva **una** malla, y
## repartir noventa y seis manojos entre cuatro piezas distintas cuesta cuatro
## lotes de dibujo y compra la única variedad que el campo va a tener.
@export var decor_pieces: Array[PackedScene] = []

## Material del prop de reserva. Sólo se usa si [member decor_pieces] está
## vacío, que es como corrió esto mientras WP-A no había entregado los props.
@export var decor_material: Material = null

## Material de veredas, banquinas y patios.
##
## **No puede ser el de la calzada.** Con el mismo `roads.tres` en los cinco
## MultiMesh, lo único que separaba la calzada de la vereda eran las marcas
## pintadas: a nivel de calle el jugador no ve dónde termina el asfalto, y desde
## el aire el pueblo es una mancha gris pareja. Es una copia del material de
## calzada con el albedo subido y entibiado, así que el cordón de 15 cm pasa a
## leerse por color y no sólo por su sombra propia.
@export var walkway_material: Material = null

## Material del suelo del campo.
@export var ground_material: Material = null

## Material del cantero de la plaza (WP-D3). Si falta, el cantero cae en
## [member ground_material], que es lo que hacía antes y lo que dejaba el
## cantero negro contra la losa.
@export var lawn_material: Material = null

## Material del espejo de agua del arroyo (WP-D3). Sin él no se construye el
## agua: un arroyo pintado con el material del campo es un arroyo seco con otro
## color.
@export var water_material: Material = null

## Pool de escombros del nivel. `town_a` lo deja vacío: cada [Building] lo
## resuelve con [method DebrisPool.resolve] (grupo `debris_pool`).
@export var debris_pool: DebrisPool = null

## Sales del sorteo **posicional** de lo poco que la rejilla decide y el plano
## no: la pieza, el giro y el corrimiento de un prop de azotea, y el giro de una
## roca de campo.
##
## Hasta WP-D4a esto salía de un [RandomNumberGenerator] sembrado una vez en
## [method build] y consumido en orden, o sea un **flujo secuencial**: agregar un
## POI al diseño corría la numeración de las parcelas y re-sorteaba el cartel de
## todas las azoteas de atrás y el giro de las seis rocas, y el `diff` del
## `.tscn` horneado dejaba de decir qué se había tocado. Es exactamente el
## barajado global que WP-T3 sacó del resolvedor; acá se saca del constructor,
## con la misma herramienta: [method TownPlan.mix_all] sobre `(sal, índice,
## canal)`.
const SALT_ROOF_PROP: int = 0x50524F50
const SALT_ROCK: int = 0x524F434B

## Canales del sorteo posicional: qué pregunta contesta cada tirada.
const CHANNEL_PIECE: int = 0
const CHANNEL_STEPS: int = 1
const CHANNEL_OFFSET_X: int = 2
const CHANNEL_OFFSET_Z: int = 3
const CHANNEL_YAW: int = 4

var _prop_debt: float = 0.0



# --------------------------------------------------------------------------
# Ciclo de vida
# --------------------------------------------------------------------------

## Aplica al cargar las dos anulaciones que el `.tscn` **no puede guardar**.
##
## Las dos son la misma trampa del serializador de Godot por dos caminos
## distintos, y las dos costaron un horneado en falso:
##
## 1. **La sombra de las casas.** La malla vive dentro de la pieza instanciada, y
##    una anulación sobre un nodo cuyo dueño es la pieza no se guarda. Forzarle el
##    dueño para que se guarde hace que Godot **copie la malla entera** dentro de
##    la escena, una por casa: cincuenta y dos copias, novecientos kilobytes y el
##    fin de la malla compartida, que es justo lo contrario de lo que se busca.
## 2. **La capa de las casas de caserío.** Se les pone
##    [constant PhysicsLayers.WORLD], que vale `1`, y `1` es **el valor por
##    defecto de la clase** `StaticBody3D`: el serializador compara contra el
##    defecto de la clase y no contra el de la instancia, así que omite la línea
##    y al cargar gana el `128` que traía la pieza de WP-A. Una casa de caserío en
##    la capa de ciudad es un blanco para el arma y para el jefe a doscientos
##    metros del círculo.
##
## Aplicarlo al cargar cuesta un recorrido del árbol una vez por ronda. Es
## idempotente y no construye nada: [method build] sigue llamándose a mano.
func _ready() -> void:
	_mute_house_shadows()
	_ground_decor_bodies()


## Devuelve las casas de caserío a la capa del terreno.
func _ground_decor_bodies() -> void:
	var decor := get_node_or_null(NodePath(DECOR_NODE))
	if decor == null:
		return
	for child: Node in decor.get_children():
		var body := child as PhysicsBody3D
		if body == null or not body.name.begins_with(String(TownPlan.DECOR_PREFIX)):
			continue
		body.collision_layer = PhysicsLayers.WORLD
		body.collision_mask = 0


## Recorre los edificios y la decoración ya sembrados y saca del pase de sombra
## a los que [method _casts_shadow] deja fuera.
##
## La decoración se apaga entera —doce casas de caserío y seis rocas— porque vive
## a 165–260 m del centro, **fuera** del círculo de juego: su sombra cae sobre
## campo vacío que el jugador no mira nunca, y cada una entra igual en las
## cascadas del sol.
func _mute_house_shadows() -> void:
	for building: Building in get_buildings():
		if _casts_shadow(int(building.get_meta(&"role", -1)),
				StringName(building.get_meta(&"piece", &""))):
			continue
		_mute_house_shadow(building)
	var decor := get_node_or_null(NodePath(DECOR_NODE))
	if decor == null:
		return
	for node: Node in _descendants(decor):
		var geometry := node as GeometryInstance3D
		if geometry != null:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --------------------------------------------------------------------------
# Consultas
# --------------------------------------------------------------------------

## El plano del pueblo. Es el punto de entrada de todo el que necesite
## geometría: el mapa de la alerta, las sondas de reflejo y los checks lo piden
## por `has_method(&"get_plan")`, sin conocer esta clase.
func get_plan() -> TownPlan:
	return plan


## Centro del círculo de juego.
##
## **Devuelve coordenadas locales del distrito**, no globales. El contrato de
## WP-B decía «global» y la clase nunca lo cumplió; se deja local porque es lo
## coherente con el resto de la API —`get_plan()`, `rock_spots()`,
## `battery_posts()` y los marcadores horneados están todos en el espacio del
## distrito— y porque convertir acá obligaría a que la rejilla estuviera en el
## árbol para tener `global_transform`, que durante el horneado no lo está.
## Quien necesite global usa `grid.to_global(grid.play_centre())`. Hoy el
## distrito se instancia en el origen y las dos coinciden, así que la diferencia
## no se ve en runtime: se va a ver el día que el nivel lo mueva.
func play_centre() -> Vector3:
	return plan.play_centre if plan != null else Vector3.ZERO


## Radio del círculo de juego, en metros. Es una distancia, así que local y
## global coinciden mientras nadie escale el distrito —y `docs/03` prohíbe
## escalar cuerpos físicos.
func play_radius() -> float:
	return plan.play_radius if plan != null else 0.0


## Extensión que dibuja el mapa de la alerta.
func get_extent() -> Vector2:
	return plan.get_extent() if plan != null else Vector2.ZERO


## Extensión del casco del pueblo, sin margen.
func get_core_extent() -> Vector2:
	return plan.get_core_extent() if plan != null else Vector2.ZERO


## Cuántas manzanas tiene el pueblo.
func block_count() -> int:
	return plan.block_count() if plan != null else 0


## Manzanas sin luz esta partida. Delega en el plano, que es quien conoce el
## recuento; el algoritmo —conjunto de tamaño fijo `round(manzanas · 0,30)` con
## una llave por manzana— es el mismo que estrenó WP-25b.
func dark_blocks() -> Dictionary:
	return plan.dark_blocks() if plan != null else {}


## Verdadero si la manzana [param block] tiene las ventanas apagadas.
func is_block_dark(block: int) -> bool:
	return plan != null and plan.is_block_dark(block)


## Verdadero si [param building] tiene que apagar sus ventanas, es decir, si su
## manzana está a oscuras. Un edificio sin metadato `block` —una casa de caserío
## o una escena de prueba con un edificio suelto— queda siempre encendido.
##
## Lo consulta [method Building._apply_window_ration] por `has_method`, sin
## conocer esta clase: es el mismo despacho flojo que usa [method occluder_for],
## y por el mismo motivo (no cerrar el ciclo `city_grid.gd` → `building.gd`).
func is_building_dark(building: Node3D) -> bool:
	if building == null or plan == null:
		return false
	var block: int = building.get_meta(&"block", -1)
	if block < 0:
		return false
	return plan.is_block_dark(block)


## Oclusor de la manzana de [param building]. **Siempre `null`**.
##
## La oclusión por oclusores está apagada en todos los presets desde WP-24e
## (`Graphics.use_occlusion_culling()`), y el pueblo de ruta no hornea ninguno:
## sus edificios son casas de 5 m repartidas en manzanas abiertas, donde una
## caja oclusora tapa más de lo que ahorra. El método se conserva porque
## `city/building.gd` lo resuelve por `has_method` al derrumbarse y espera poder
## llamarlo; devolver `null` es exactamente lo que ese camino tolera.
func occluder_for(_building: Building) -> OccluderInstance3D:
	return null


## Edificios ya sembrados, en el orden en que se crearon.
func get_buildings() -> Array[Building]:
	var found: Array[Building] = []
	var container := get_node_or_null(NodePath(BUILDINGS_NODE))
	if container == null:
		return found
	for child: Node in container.get_children():
		var building := child as Building
		if building != null:
			found.append(building)
	return found


## Edificio de la parcela [param parcel], o `null`.
func get_building_at(parcel: int) -> Building:
	for building: Building in get_buildings():
		if int(building.get_meta(&"parcel", -1)) == parcel:
			return building
	return null


## Rocas del borde (grupo `city_rocks`).
##
## El pueblo las cuelga de `Decor/Rocks`. El respaldo a `Rocks` a secas se
## conserva para cualquier escena de prueba que arme un distrito a mano —
## `tools/fake_town.gd` es la única hoy— y cuesta una búsqueda fallida por
## llamada, que ocurre cero veces sobre `town_a.tscn`.
func get_rocks() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var container := get_node_or_null(NodePath(ROCKS_PATH))
	if container == null:
		container = get_node_or_null(NodePath(ROCKS_NODE))
	if container == null:
		return found
	for child: Node in container.get_children():
		var rock := child as Node3D
		if rock != null:
			found.append(rock)
	return found


## Ángulo, en grados, entre la línea que une el punto de aparición del dron con
## el centro del pueblo y [param spot].
func spawn_cone_angle(spot: Vector3) -> float:
	if plan == null:
		return 0.0
	return plan.spawn_cone_angle(spot)


## Ángulo, en grados, entre el rumbo real del dron al aparecer y [param spot].
func spawn_view_angle(spot: Vector3) -> float:
	if plan == null:
		return 0.0
	return plan.spawn_view_angle(spot)


func _flat_angle(reference: Vector3, target: Vector3) -> float:
	return TownPlan.flat_angle(reference, target)


# --------------------------------------------------------------------------
# Construcción
# --------------------------------------------------------------------------

## Genera el pueblo completo de cero. Es idempotente: vuelve a empezar borrando
## lo que hubiera. Con el mismo [member plan] produce siempre lo mismo.
func build() -> void:
	_clear_generated()
	if plan == null:
		push_error("CityGrid: no hay plano que construir.")
		return
	_prop_debt = 0.0
	_missing_pieces = {}

	_build_ground()
	_build_streets()
	_build_plaza()
	_build_creek_water()
	_build_bridge()
	_build_buildings()
	_build_decor()
	_build_groves()
	_build_fences()
	_build_props()
	_build_spawns()
	_build_posts()
	_build_markers()


## Asigna `owner` a todo lo generado para que [method PackedScene.pack] lo
## guarde. Se llama una vez, al final, desde `tools/build_town.gd`.
##
## La regla vale también dentro de las piezas instanciadas: un nodo **sin
## dueño** lo creó [method build] y hay que reclamarlo; uno que ya tiene dueño
## vino dentro de un `PackedScene` y se deja en paz, porque lo que se guarda es
## su instancia con las anulaciones de sus internos.
func claim_ownership(scene_root: Node) -> void:
	for node: Node in _descendants(self):
		if node == scene_root:
			continue
		if node.owner == null:
			node.owner = scene_root



func _clear_generated() -> void:
	for name: StringName in [BUILDINGS_NODE, STREETS_NODE, DECOR_NODE, SPAWNS_NODE,
			POSTS_NODE, GROUND_NODE, DRONE_NODE, CENTRE_NODE, CAMERA_NODE,
			PLAZA_NODE, GROVES_NODE, FENCES_NODE, PROPS_NODE, BRIDGE_NODE,
			CREEK_NODE]:
		var existing := get_node_or_null(NodePath(name))
		if existing != null:
			remove_child(existing)
			existing.free()


## Contenedor vacío colgado de [param parent], o de la rejilla si no se pasa.
func _container(name: StringName, parent: Node3D = null) -> Node3D:
	var node := Node3D.new()
	node.name = name
	var host := parent if parent != null else self
	host.add_child(node)
	return node


# --- Suelo -----------------------------------------------------------------

## Un único `StaticBody3D` de capa 1 con el relieve adentro (`docs/10` §4.4).
##
## Lo que cuelga, y por qué cada cosa es como es:
##
## - **`Shape`** — el [HeightMapShape3D] horneado de 513 × 513 muestras a un
##   metro, **en el origen y sin escalar**. Jolt trabaja el heightfield en
##   unidades de rejilla: escalar el nodo o darle un paso distinto de uno lo
##   hace caer a una malla de colisión, que cuesta diez veces más.
## - **`RingN/E/S/W`** — cuatro cajas a `y = 0` que cubren del borde del
##   heightfield (±256 m) al borde del campo. El relieve se desvanece a cero
##   antes de los 256 m justamente para empalmar con ellas sin escalón.
## - **`Safety`** — una caja de seguridad con la cara superior en
##   [constant SAFETY_TOP], **debajo del lecho del arroyo**. No es piso: es la
##   red que atrapa a un cuerpo que se escapó por un borde.
## - **`Chunk0..3`** — las cuatro mallas del relieve, en el origen.
## - **`Field`** — el campo lejano.
##
## ## El plano de 1 200 m no podía seguir en `y = 0`
##
## Hasta P2b el suelo visible era un `PlaneMesh` de 1 200 m a `y = 0` **debajo**
## de todo. Con relieve encima eso se rompe: el arroyo baja a −5,5 m y las
## vaguadas del campo a −2 m, así que el plano asomaba por el medio del cauce
## como una lámina de agua gris y opaca. En su lugar va un **anillo cuadrado con
## agujero** de [constant TERRAIN_REACH] a [constant FIELD_REACH] metros: no hay
## ni un triángulo de campo lejano debajo del relieve, y la junta cae donde el
## terreno vale cero exacto.
func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = GROUND_NODE
	body.collision_layer = GROUND_LAYER
	body.collision_mask = GROUND_MASK
	add_child(body)

	_add_terrain_collision(body)
	_add_ground_ring(body)
	_add_terrain_chunks(body)
	_add_far_field(body)


## El heightfield horneado, en el origen y sin escalar.
func _add_terrain_collision(body: StaticBody3D) -> void:
	if terrain_shape == null:
		return
	var node := CollisionShape3D.new()
	node.name = "Shape"
	node.shape = terrain_shape
	body.add_child(node)


## Las cuatro cajas de anillo a `y = 0` y la caja de seguridad.
##
## El anillo se arma con cuatro cajas y no con una sola grande porque una sola
## grande taparía el heightfield: dos colisionadores superpuestos en el mismo
## sitio hacen que el cuerpo apoye en el más alto, y el más alto sería la caja
## plana en cada vaguada del pueblo.
func _add_ground_ring(body: StaticBody3D) -> void:
	var half := plan.field_size * 0.5
	var inner := _terrain_half()
	if half > inner:
		var band := half - inner
		var spans: Array[Array] = [
			# nombre, tamaño XZ, centro XZ
			["RingN", Vector2(half * 2.0, band), Vector2(0.0, -(inner + band * 0.5))],
			["RingS", Vector2(half * 2.0, band), Vector2(0.0, inner + band * 0.5)],
			["RingW", Vector2(band, inner * 2.0), Vector2(-(inner + band * 0.5), 0.0)],
			["RingE", Vector2(band, inner * 2.0), Vector2(inner + band * 0.5, 0.0)],
		]
		for span: Array in spans:
			var size: Vector2 = span[1]
			var centre: Vector2 = span[2]
			_add_ground_box(body, StringName(span[0]),
					Vector3(size.x, 4.0, size.y), Vector3(centre.x, -2.0, centre.y))

	_add_ground_box(body, &"Safety",
			Vector3(plan.field_size, 4.0, plan.field_size),
			Vector3(0.0, SAFETY_TOP - 2.0, 0.0))


func _add_ground_box(body: StaticBody3D, name: StringName, size: Vector3,
		centre: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var node := CollisionShape3D.new()
	node.name = name
	node.shape = box
	node.position = centre
	body.add_child(node)


## Medio lado del cuadrado que cubre el heightfield, en metros.
func _terrain_half() -> float:
	if terrain == null or not terrain.has_method(&"extent"):
		return 0.0
	var rect: Rect2 = terrain.call(&"extent")
	return rect.size.x * 0.5


## Las cuatro mallas del relieve. Van **en el origen**: sus vértices ya vienen
## en coordenadas del distrito, así que moverlas las duplicaría de lugar.
func _add_terrain_chunks(body: StaticBody3D) -> void:
	for index: int in terrain_chunks.size():
		var mesh := terrain_chunks[index]
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.name = "Chunk%d" % index
		node.mesh = mesh
		if terrain_material != null:
			node.material_override = terrain_material
		node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(node)


## El campo lejano: un anillo cuadrado con agujero, a `y = 0`, con la normal
## hacia arriba y el material de campo.
func _add_far_field(body: StaticBody3D) -> void:
	var inner := _terrain_half()
	if inner <= 0.0:
		inner = TERRAIN_REACH
	var outer := maxf(plan.field_size * 0.5, inner + FIELD_STEP)
	var mesh := _field_ring_mesh(inner, outer)
	if mesh == null:
		return
	var node := MeshInstance3D.new()
	node.name = "Field"
	node.mesh = mesh
	if terrain_material != null:
		node.material_override = terrain_material
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(node)


## Anillo cuadrado de `[-outer, outer]²` menos `[-inner, inner]²`, teselado con
## un paso de [constant FIELD_STEP] metros y con el agujero exacto.
##
## Se arma recorriendo la rejilla completa y salteando las celdas que caen
## enteras dentro del agujero: así el borde del agujero es una fila de vértices
## de la misma rejilla y no hay que coser nada a mano.
func _field_ring_mesh(inner: float, outer: float) -> ArrayMesh:
	var axis := _field_axis(inner, outer)
	if axis.size() < 2:
		return null
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_material(ground_material)
	var count := axis.size() - 1
	for iz: int in count:
		for ix: int in count:
			var x0 := axis[ix]
			var x1 := axis[ix + 1]
			var z0 := axis[iz]
			var z1 := axis[iz + 1]
			if maxf(absf(x0), absf(x1)) <= inner + 0.001 \
					and maxf(absf(z0), absf(z1)) <= inner + 0.001:
				continue
			_field_quad(builder, x0, x1, z0, z1, outer)
	builder.index()
	return builder.commit()


## Coordenadas del eje del anillo: el borde del agujero y el del campo son
## vértices exactos, y entre ellos se reparte un paso regular de a lo sumo
## [constant FIELD_STEP].
func _field_axis(inner: float, outer: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var band := outer - inner
	var steps := maxi(ceili(band / FIELD_STEP), 1)
	for index: int in range(steps, 0, -1):
		out.append(-inner - band * float(index) / float(steps))
	var inside := maxi(ceili(inner * 2.0 / FIELD_STEP), 1)
	for index: int in inside + 1:
		out.append(-inner + inner * 2.0 * float(index) / float(inside))
	for index: int in range(1, steps + 1):
		out.append(inner + band * float(index) / float(steps))
	return out


## Una celda del anillo, como dos triángulos mirando a `+Y`.
##
## El orden de giro sale de la misma comprobación que [method RoadMesh._tri] y
## no de razonarlo: Godot dibuja de frente los triángulos **horarios** vistos
## desde fuera, así que `(b−a) × (c−a)` tiene que apuntar al revés de la normal
## visible. Un anillo con la cara para abajo es invisible desde el aire y sólo
## se descubre en la captura.
func _field_quad(builder: SurfaceTool, x0: float, x1: float, z0: float, z1: float,
		outer: float) -> void:
	var corners: Array[Vector2] = [
		Vector2(x0, z0), Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0),
	]
	for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector2 = corners[triangle[0]]
		var b: Vector2 = corners[triangle[1]]
		var c: Vector2 = corners[triangle[2]]
		var pa := Vector3(a.x, 0.0, a.y)
		var pb := Vector3(b.x, 0.0, b.y)
		var pc := Vector3(c.x, 0.0, c.y)
		if (pb - pa).cross(pc - pa).dot(Vector3.UP) > 0.0:
			var swap := pb
			pb = pc
			pc = swap
		for point: Vector3 in [pa, pb, pc]:
			# Peso de capa «todo pasto», que es lo que el shader del relieve
			# espera en el COLOR de cada vértice. El campo lejano lleva **el
			# mismo material** que los chunks y no el de P2b: con dos materiales
			# distintos la junta a 260 m se leía como una línea recta en el pasto
			# —un verde a un lado y un gris azulado al otro— y era lo primero que
			# saltaba en la captura aérea.
			builder.set_color(Color(1.0, 0.0, 0.0, 0.0))
			builder.set_normal(Vector3.UP)
			# El material del campo es triplanar sobre la posición de mundo: la
			# UV no la mira nadie, pero un `SurfaceTool` sin UV deja el canal
			# fuera y cualquier material que sí lo use se vería en negro.
			builder.set_uv(Vector2(point.x, point.z) / maxf(outer * 2.0, 1.0)
					+ Vector2(0.5, 0.5))
			builder.add_vertex(point)


# --- Calles ----------------------------------------------------------------

## Calzada, cruces y veredas del pueblo: **dos mallas y un MultiMesh**, sin
## colisión propia (el suelo lo aporta la caja única de [method _build_ground],
## `docs/10` §4.4 y §7).
##
## Reparto, y por qué cada cosa va donde va:
##
## - **Calzada** — una cinta triangulada por tramo de calle
##   ([method RoadMesh.ribbon]), recortada contra el polígono de cada nodo que
##   toca. Con miter en los quiebres no queda muesca; con el corte recto en la
##   boca del nodo no queda ni hueco ni solape, que es lo que borra el
##   z-fighting de P2b.
## - **Cruces** — el polígono que queda entre las bocas de las calles que llegan
##   al nodo ([method RoadMesh.node_polygon]), con asfalto liso y chaflán en las
##   esquinas. Ya no es un cuadrado alineado a los ejes del mundo apoyado encima
##   de la calzada.
## - **Veredas** — un anillo por manzana ([method RoadMesh.ring]) **sólo en los
##   lados que dan a una calle**, con la cara vertical del cordón de 15 cm. Ya
##   no atraviesan los cruces ni se meten por el fondo de la manzana.
## - **Cierres** — cada cabo declarado lleva su tranquera, su alcantarilla o su
##   tramo de alambrado ([method RoadMesh.closure]).
## - **Ruta entera** — la cinta cubre los 1 127 m de ruta y no sólo el tramo del
##   pueblo. Ver la nota de [constant ASPHALT_NODE]: sobre relieve, una baldosa
##   plana de 10 m no apoya.
##
## Los dos [MeshInstance3D] van **sin sombra propia**: son superficies planas a
## tres centímetros del suelo, su sombra cae sobre el suelo que ya las tapa y
## entrarían igual en cada cascada del sol. Es la misma decisión que tomaba
## `_add_multimesh` con los cinco MultiMesh de P2b y vale por lo mismo
## (`docs/10`, nota del cierre de P2b).
func _build_streets() -> void:
	var streets := _container(STREETS_NODE)
	var height := terrain_height_fn()
	var road_tile := _bake_piece_mesh(road_piece)
	var asphalt_material: Material = null
	if road_tile != null and road_tile.get_surface_count() > 0:
		asphalt_material = road_tile.surface_get_material(0)

	var asphalt: Array = []
	var walkways: Array = []

	_emit_roadways(asphalt, height)
	_emit_crossings(asphalt, height)
	_emit_walkways(walkways, height)
	_emit_closures(walkways, height)

	var _asphalt_node := _add_surface(streets, ASPHALT_NODE,
			RoadMesh.paint(RoadMesh.merge(asphalt), asphalt_material))
	var _walkway_node := _add_surface(streets, WALKWAYS_NODE,
			RoadMesh.paint(RoadMesh.merge(walkways), walkway_material))


## Función de altura del terreno que usa todo el viario.
##
## Mientras [member terrain] sea nulo —o no sepa contestar `height_at`— el mundo
## es el plano `y = 0`, que es el suelo que construye [method _build_ground].
## Cuando WP-T2 entregue [TownTerrain] y WP-T4 lo cablee acá, las mismas cintas y
## los mismos anillos se apoyan sobre el relieve sin tocar una línea de
## [RoadMesh]: por eso la altura entra como [Callable] y no como una dependencia
## de tipo.
func terrain_height_fn() -> Callable:
	var source := terrain
	if source != null and source.has_method(&"height_at"):
		return func(x: float, z: float) -> float:
			return float(source.call(&"height_at", x, z))
	return Callable()


## Función de altura **de la ruta**: la del terreno salvo dentro del vano del
## puente, donde es la recta que une los dos extremos del vano.
##
## Es la corrección que hace que la calzada cruce el arroyo en vez de bajar al
## cauce. Hasta WP-D2 el perfil de la ruta y el relieve eran la misma cosa, y con
## el vano abierto por WP-D1 —el terreno baja dos metros y pico bajo el tablero—
## la cinta habría seguido al terreno y la ruta habría entrado al agua.
##
## La corrección se aplica al vano más un metro a cada lado
## ([constant BRIDGE_MARGIN]) para que el empalme con el terreno caiga sobre el
## estribo y no sobre el borde del tablero, donde un escalón de un centímetro se
## ve desde el dron.
##
## Sin puente declarado devuelve exactamente [method terrain_height_fn]: un
## pueblo sin arroyo no paga nada por esto.
func route_height_fn() -> Callable:
	var height := terrain_height_fn()
	if plan == null or not plan.has_bridge():
		return height
	var axis := plan.street_axis(0)
	if axis.size() < 2:
		return height
	var at := TownPlan.polyline_closest(axis, plan.bridge_at)
	var half := plan.bridge_span * 0.5 + BRIDGE_MARGIN
	var head := TownPlan.polyline_point(axis, at - half)
	var tail := TownPlan.polyline_point(axis, at + half)
	var y_head := ground_y(head.x, head.z)
	var y_tail := ground_y(tail.x, tail.z)
	var from := Vector2(head.x, head.z)
	var to := Vector2(tail.x, tail.z)
	var delta := to - from
	var span := delta.length_squared()
	if span < 0.000001:
		return height
	return func(x: float, z: float) -> float:
		var t := (Vector2(x, z) - from).dot(delta) / span
		if t <= 0.0 or t >= 1.0:
			return height.call(x, z) if height.is_valid() else 0.0
		return lerpf(y_head, y_tail, t)


## Altura del terreno en `(x, z)`, o `0` sin relieve conectado.
func ground_y(x: float, z: float) -> float:
	if terrain == null or not terrain.has_method(&"height_at"):
		return 0.0
	return float(terrain.call(&"height_at", x, z))


## [param point] apoyado sobre el terreno conservando su `y` como **holgura**.
##
## Es la regla con la que WP-T4 subió al relieve todo lo que el plano declara
## con una altura relativa al suelo: un poste de pila a 4,8 m, el dron a 1,5 m,
## una aparición a ras. El plano no sabe de relieve —su `y` es «cuánto por
## encima del suelo»— y acá se le suma el suelo. Con [member terrain] nulo la
## cuenta es la identidad, que es como corrió hasta P2b.
func on_terrain(point: Vector3) -> Vector3:
	return Vector3(point.x, point.y + ground_y(point.x, point.z), point.z)


## [param xform] con su origen apoyado sobre el terreno. La base no se toca: el
## giro de una aparición mira al centro del pueblo y eso no depende de la cota.
func on_terrain_xform(xform: Transform3D) -> Transform3D:
	return Transform3D(xform.basis, on_terrain(xform.origin))


## Calzada de la ruta y de las calles, recortada contra los nodos.
func _emit_roadways(asphalt: Array, height: Callable) -> void:
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		if axis.size() < 2:
			continue
		var half := plan.street_width_of(street) * 0.5
		if half <= 0.0:
			continue
		# Sólo la ruta lleva el tile con marcas (`docs/17` §4). Estirar las dos
		# bandas pintadas de `Road_Chunk_5` a lo ancho de una calle de nueve
		# metros deja una franja anaranjada paralela al cordón, y como la V del
		# tile se repite cada diez metros esa franja se corta y vuelve con un
		# período regular: son los dientes que WP-T5 midió en `plaza_60`.
		var marked := plan.street_kind_of(street) == TownPlan.StreetKind.ROUTE
		var uv_rect := RoadMesh.ROAD_UV if marked else RoadMesh.ROAD_SMOOTH_UV
		# La ruta usa la altura **con el vano del puente corregido**: adentro del
		# vano el terreno baja al cauce y la calzada no puede seguirlo.
		var lift := route_height_fn() if marked else height
		# Cabos **cero**: el eje que `TownPlanner.build_graph()` hornea ya sale
		# prolongado por sus dos cabos (`from = a − dir·stub_a`,
		# `to = b + dir·stub_b`), así que volver a pasarle `street_stub_of` a
		# `clip_ribbon_at_nodes` —que estira `head = −stub_a` y
		# `tail = total + stub_b` sobre ese eje— aplicaba el cabo **dos veces**:
		# las catorce tranqueras quedaban al doble de su distancia declarada
		# (15,6 a 33,6 m) y el último tramo de asfalto apoyaba sobre relieve que
		# `build_terrain` nunca aplanó, porque el corredor del terreno se calcula
		# con el eje 1×.
		for piece: PackedVector3Array in RoadMesh.clip_ribbon_at_nodes(axis,
				_street_cuts(street, axis), 0.0, 0.0):
			var mesh := RoadMesh.ribbon(piece, half, lift, ROAD_TOP,
					RoadMesh.ROAD_U_SCALE, uv_rect)
			if mesh != null:
				asphalt.append(mesh)


## Los nodos que la calle [param street] toca, como recortes sobre su eje.
##
## Se recorren **todos** los nodos y no sólo los dos de [method TownPlan.node_of]
## a propósito: la ruta entra al pueblo por una punta y sale por la otra, pero en
## el medio cruza siete transversales, y cada uno de esos cruces es un nodo que
## le abre un hueco. Un nodo de grado uno —un cabo— no recorta nada: ahí no hay
## cruce, hay un cierre.
func _street_cuts(street: int, axis: PackedVector3Array) -> Array[Dictionary]:
	var cuts: Array[Dictionary] = []
	if plan == null or not plan.has_graph():
		return cuts
	for index: int in plan.nodes.size():
		var node := plan.node_at(index)
		var incident: PackedInt32Array = node.get("streets", PackedInt32Array())
		if not incident.has(street):
			continue
		var poly: PackedVector2Array = node.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var pos: Vector3 = node.get("pos", Vector3.ZERO)
		cuts.append({
			"at": TownPlan.polyline_closest(axis, pos),
			"radius": float(node.get("radius", 0.0)),
		})
	return cuts


## El polígono de asfalto liso de cada nodo de grado dos o más.
func _emit_crossings(asphalt: Array, height: Callable) -> void:
	if plan == null or not plan.has_graph():
		return
	for index: int in plan.nodes.size():
		var poly := plan.node_polygon(index)
		if poly.size() < 3:
			continue
		var mesh := RoadMesh.polygon_mesh(poly, height, ROAD_TOP)
		if mesh != null:
			asphalt.append(mesh)


## Un anillo de vereda por manzana, con el ancho de vereda de cada calle.
func _emit_walkways(walkways: Array, height: Callable) -> void:
	for block: int in plan.block_count():
		var ring := plan.block_ring(block)
		if ring.size() < 3 or block >= plan.block_streets.size():
			continue
		var sides := plan.block_streets[block]
		if sides.size() < ring.size():
			continue
		var widths := PackedFloat32Array()
		var widest := 0.0
		for side: int in sides:
			var walk := plan.street_sidewalk_of(side)
			widths.append(walk)
			widest = maxf(widest, walk)
		if widest <= 0.0:
			continue
		var mesh := RoadMesh.ring(ring, sides, 0.0, widest, SIDEWALK_TOP,
				RoadMesh.CURB, height, widths)
		if mesh != null:
			walkways.append(mesh)


## La tranquera, la alcantarilla o el alambrado de cada cabo declarado.
func _emit_closures(walkways: Array, height: Callable) -> void:
	if plan == null or not plan.has_graph():
		return
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		if axis.size() < 2:
			continue
		var total := TownPlan.polyline_length(axis)
		for end: int in 2:
			# Un cabo puede venir de dos formas: sin nodo (`-1`) o con un nodo de
			# **grado uno**, que es como el resolvedor del diseño marca la punta
			# de un acceso. Las dos terminan en el aire y las dos llevan cierre;
			# lo que no lleva cierre es un nodo de grado dos o más, que es un
			# cruce y ya tiene su polígono de asfalto.
			var node := plan.node_of(street, end)
			if node >= 0 and plan.node_polygon(node).size() >= 3:
				continue
			var kind := plan.street_closure_of(street, end)
			if not RoadMesh.CLOSURE_KINDS.has(kind) or kind == RoadMesh.KIND_NONE:
				continue
			# El cierre va **sobre la punta del eje**, no más allá: el cabo ya
			# está horneado dentro de `street_axis` (ver [method _emit_roadways]),
			# así que sumarle otra vez `street_stub_of` dejaba la tranquera al
			# doble de la distancia que el diseño declara y el asfalto terminaba
			# metros antes que ella.
			var at := 0.0 if end == 0 else total
			var point := TownPlan.polyline_point(axis, at)
			var facing := TownPlan.polyline_tangent(axis, clampf(at, 0.0, total))
			if end == 0:
				facing = -facing
			var mesh := RoadMesh.closure(kind, point, facing,
					plan.street_width_of(street), height)
			if mesh != null:
				walkways.append(mesh)


## Cuelga de [param parent] una [MeshInstance3D] con la malla ya fundida.
func _add_surface(parent: Node3D, name: StringName, mesh: ArrayMesh) -> MeshInstance3D:
	if mesh == null:
		push_error("CityGrid: la malla de calle '%s' quedaría vacía." % name)
		return null
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## Guarda las dos mallas de calle como `.res` binarios en [param dir] y deja los
## nodos apuntando a los archivos.
##
## Lo llama el horneador (`tools/build_town.gd`, WP-T4) **después** de
## [method build] y **antes** de empaquetar la escena. Sin esto las dos mallas
## viajan dentro de `town_a.tscn` en texto y el archivo se va bastante más allá
## del tope de 500 KB del plan; con esto el `.tscn` guarda dos rutas.
##
## Devuelve `OK` o el primer error.
func save_street_meshes(dir: String) -> Error:
	var streets := get_node_or_null(NodePath(STREETS_NODE))
	if streets == null:
		push_error("CityGrid: no hay calles que guardar; llamá a build() antes.")
		return ERR_UNCONFIGURED
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	for entry: Array in [[ASPHALT_NODE, "asphalt.res"], [WALKWAYS_NODE, "walkways.res"]]:
		var node := streets.get_node_or_null(NodePath(entry[0])) as MeshInstance3D
		if node == null or node.mesh == null:
			continue
		var path := String(dir).path_join(String(entry[1]))
		err = ResourceSaver.save(node.mesh, path,
				ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
		if err != OK:
			push_error("CityGrid: no se pudo guardar '%s': %s" % [path, error_string(err)])
			return err
		node.mesh = ResourceLoader.load(path, "ArrayMesh")
	return _save_decor_resources(dir)


## Saca de la escena la geometría de plaza, arboledas, cercos y props.
##
## Por el mismo motivo que las dos mallas de calle: mil cuatrocientas instancias
## de follaje son diecisiete mil flotantes, y escritos en el `.tscn` en texto el
## pueblo pasaba de 310 KB a **1 843 KB** contra un tope de 500. Cada
## [MultiMesh] y cada malla fundida se guardan en un `.res` binario comprimido y
## el nodo queda apuntando al archivo.
##
## Se guarda el [MultiMesh] entero —no sólo su malla— porque el búfer de
## transformadas vive **en el recurso**: dejarlo adentro del `.tscn` no habría
## ahorrado nada.
func _save_decor_resources(dir: String) -> Error:
	for name: StringName in [PLAZA_NODE, GROVES_NODE, FENCES_NODE, PROPS_NODE,
			CREEK_NODE]:
		var group := get_node_or_null(NodePath(name))
		if group == null:
			continue
		for child: Node in group.get_children():
			var slug := "%s_%s" % [String(name).to_lower(), String(child.name).to_lower()]
			var multi := child as MultiMeshInstance3D
			if multi != null and multi.multimesh != null:
				var path := String(dir).path_join("%s.res" % slug)
				var err := ResourceSaver.save(multi.multimesh, path,
						ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
				if err != OK:
					push_error("CityGrid: no se pudo guardar '%s': %s" % [path, error_string(err)])
					return err
				multi.multimesh = ResourceLoader.load(path, "MultiMesh")
				continue
			var surface := child as MeshInstance3D
			if surface == null or surface.mesh == null:
				continue
			var mesh_path := String(dir).path_join("%s.res" % slug)
			var mesh_err := ResourceSaver.save(surface.mesh, mesh_path,
					ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
			if mesh_err != OK:
				push_error("CityGrid: no se pudo guardar '%s': %s"
						% [mesh_path, error_string(mesh_err)])
				return mesh_err
			surface.mesh = ResourceLoader.load(mesh_path, "ArrayMesh")
	return OK


## Crea un [MultiMeshInstance3D] con [param mesh] y las [param transforms] dadas.
func _add_multimesh(parent: Node3D, name: StringName, mesh: Mesh,
		transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	if mesh == null or transforms.is_empty():
		push_error("CityGrid: el MultiMesh '%s' quedaría vacío." % name)
		return null
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = transforms.size()
	multi_mesh.buffer = _multimesh_buffer(transforms)

	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multi_mesh
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## Empaqueta [param transforms] en el formato crudo de [member MultiMesh.buffer]:
## tres filas de cuatro flotantes por instancia (la matriz 3 × 4 por filas).
##
## Se escribe el búfer entero y **no** se usa [method MultiMesh.set_instance_transform]
## a propósito: esa vía guarda las transformadas dentro del `RenderingServer`, y
## el servidor de `--headless` —que es donde corre `tools/build_town.gd`— no las
## retiene, así que `get_buffer()` devolvería vacío y `town_a.tscn` se guardaría
## con todas las instancias en el origen. Asignar `buffer` escribe la propiedad
## del recurso, que sí se serializa.
func _multimesh_buffer(transforms: Array[Transform3D]) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(transforms.size() * 12)
	var cursor := 0
	for xform: Transform3D in transforms:
		for row: int in 3:
			data[cursor] = xform.basis.x[row]
			data[cursor + 1] = xform.basis.y[row]
			data[cursor + 2] = xform.basis.z[row]
			data[cursor + 3] = xform.origin[row]
			cursor += 4
	return data


## Copia la malla de una pieza de calle horneando la transformada de su nodo.
##
## Se copia en vez de referenciar `<fbx>::ArrayMesh_xxx` a propósito: el id de
## un subrecurso de escena importada lo genera el importador y cambia si se
## vuelve a importar, con lo que `town_a.tscn` quedaría apuntando a la nada. La
## copia son 12 a 28 triángulos y viaja dentro del `.tscn`.
func _bake_piece_mesh(piece: PackedScene) -> ArrayMesh:
	if piece == null:
		return null
	var root := piece.instantiate()
	var source: MeshInstance3D = null
	var meshes := 0
	for node: Node in _descendants(root):
		var candidate := node as MeshInstance3D
		if candidate == null or candidate.mesh == null:
			continue
		meshes += 1
		if source == null:
			source = candidate
	# Esta rutina hornea **una** superficie de **una** malla y aplica la
	# transformada local del nodo, no la cadena hasta la raíz. Sirve para las
	# piezas de calle y de prop, que son una malla plana colgada de la raíz. Si
	# alguna vez llega una pieza con varias mallas, varias superficies o la malla
	# anidada, lo que se hornea es un trozo de la pieza y el resto desaparece sin
	# decir nada: de ahí el aviso.
	if meshes > 1:
		push_error("CityGrid: la pieza '%s' trae %d mallas y sólo se hornea la primera."
				% [piece.resource_path, meshes])
	if source != null and source.get_parent() != root:
		push_error("CityGrid: la malla de '%s' está anidada; se hornearía con la"
				% piece.resource_path + " transformada equivocada.")
	if source == null:
		root.free()
		push_error("CityGrid: la pieza '%s' no tiene malla." % piece.resource_path)
		return null

	# **Todas** las superficies, no sólo la 0.
	#
	# Hasta WP-D1 las piezas horneables eran baldosas de calle y matas de campo:
	# una malla, un material. Las piezas procedurales del pueblo traen dos o tres
	# —el cartel lleva chapa, poste y el atlas de texto—, y quedarse con la
	# primera dejaba el cartel sin cartel y el banco sin patas, en silencio y
	# después de un `push_error` que nadie iba a leer en medio del horneado.
	var xform := source.transform
	var mesh := ArrayMesh.new()
	for surface: int in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		moved.resize(vertices.size())
		for index: int in vertices.size():
			moved[index] = xform * vertices[index]
		arrays[Mesh.ARRAY_VERTEX] = moved
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var turned := PackedVector3Array()
			turned.resize(normals.size())
			for index: int in normals.size():
				turned[index] = (xform.basis * normals[index]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = turned
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := source.mesh.surface_get_material(surface)
		if material != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	root.free()
	return mesh


# --- Edificios -------------------------------------------------------------

## Siembra un [Building] por parcela destructible del plano.
func _build_buildings() -> void:
	var container := _container(BUILDINGS_NODE)
	for index: int in plan.parcels.size():
		var parcel := plan.parcels[index]
		if not bool(parcel.get("destructible", false)):
			continue
		var role := int(parcel.get("role", TownPlan.Role.HOUSE))
		var profile := house_profile if role == TownPlan.Role.HOUSE else big_profile
		var building := _spawn_building(_piece_for(parcel), profile, index)
		if building == null:
			continue
		container.add_child(building)


## La pieza de una parcela, por su identificador. Devuelve `null` —y lo dice—
## si la tabla no la trae: es el aviso de que falta importar algo.
func _piece_for(parcel: Dictionary) -> PackedScene:
	var id: StringName = parcel.get("piece", &"")
	var piece := pieces.get(id, null) as PackedScene
	if piece == null:
		push_error("CityGrid: no hay pieza para '%s'." % id)
	return piece


## Instancia una pieza, le pone el script [Building] y le monta los nodos de
## etapa. Devuelve el edificio **fuera del árbol**; quien llama lo cuelga.
##
## Sirve para las dos familias de pieza que conviven en el pueblo:
##
## - las **FBX de VoxelCity**, cuyo origen está en una esquina y cuya forma de
##   colisión quedó centrada en el AABB por el post-import;
## - las **GLB de WP-A**, centradas en XZ y con `min.y = 0`.
##
## No hace falta distinguirlas: el `rest` se calcula **desde la posición de la
## forma**, que en el primer caso vale el desplazamiento de la esquina y en el
## segundo es cero. Una sola fórmula cubre las dos.
func _spawn_building(piece: PackedScene, profile: BuildingProfile,
		parcel_index: int) -> Building:
	if piece == null or profile == null:
		push_error("CityGrid: falta la pieza o el perfil de la parcela %d." % parcel_index)
		return null
	var root := piece.instantiate() as StaticBody3D
	if root == null:
		push_error("CityGrid: la pieza '%s' no tiene raíz StaticBody3D." % piece.resource_path)
		return null

	var parcel := plan.parcels[parcel_index]
	var mesh_instance: MeshInstance3D = null
	var fallback_shape: CollisionShape3D = null
	for node: Node in root.get_children():
		if mesh_instance == null and node is MeshInstance3D:
			mesh_instance = node as MeshInstance3D
		if fallback_shape == null and node is CollisionShape3D:
			fallback_shape = node as CollisionShape3D
		var player := node as AnimationPlayer
		if player != null:
			# El pack trae un `AnimationPlayer` vacío por pieza; sin animaciones
			# no cuesta nada, pero tampoco hace falta que procese.
			player.process_mode = Node.PROCESS_MODE_DISABLED
	var shape_node := root.get_node_or_null(NodePath(PIECE_SHAPE)) as CollisionShape3D
	if shape_node == null:
		shape_node = fallback_shape
	if mesh_instance == null or shape_node == null:
		push_error("CityGrid: la pieza '%s' no trae malla o forma de colisión."
				% piece.resource_path)
		root.free()
		return null

	var base_size: Vector3 = root.get_meta(&"base_size", Vector3(20.0, 12.5, 11.0))
	# El post-import deja la forma en el centro del AABB, y el origen de las
	# piezas FBX está en una esquina: ese offset es lo que hay que anular para
	# que la huella quede centrada sobre la parcela y el giro sea en torno a su
	# eje. En las piezas GLB, ya centradas, el offset es cero y esto no hace
	# nada.
	var centre := shape_node.position
	var rest := Transform3D(Basis.IDENTITY, Vector3(-centre.x, 0.0, -centre.z)) * mesh_instance.transform

	root.set_script(ResourceLoader.load(BUILDING_SCRIPT, "Script"))
	var building := root as Building
	building.name = String(parcel.get("name", &"Building"))
	building.set_meta(&"parcel", parcel_index)
	building.set_meta(&"block", int(parcel.get("block", -1)))
	building.set_meta(&"role", int(parcel.get("role", -1)))
	building.set_meta(&"piece", StringName(piece.resource_path.get_file().get_basename()))
	building.profile = profile
	building.base_size = base_size
	building.stage_intact = mesh_instance
	building.intact_rest_transform = rest
	building.intact_shape = shape_node
	building.debris_pool = debris_pool
	# La `BoxShape3D` viene del `PackedScene` y la comparten todas las instancias
	# de la misma pieza: sin duplicarla, la variación de altura de un edificio
	# reescribiría la de sus diez hermanos.
	shape_node.shape = shape_node.shape.duplicate()

	building.rubble_shape = _make_rubble_shape(building)
	_make_rubble_stage(building, profile)
	building.dust_burst = _make_dust(building, profile)
	if int(parcel.get("role", -1)) != TownPlan.Role.HOUSE:
		building.props = _make_props(building, base_size, parcel_index)

	# Quién proyecta sombra y quién no lo decide [method _casts_shadow]. Se
	# aplica acá —al hornear— y otra vez en [method _mute_house_shadows] al
	# cargar la escena, porque `cast_shadow` es una propiedad de nodo que viaja
	# dentro del `.tscn` y las dos vías tienen que decir lo mismo.
	if not _casts_shadow(int(parcel.get("role", -1)),
			StringName(piece.resource_path.get_file().get_basename())):
		_mute_house_shadow(building)

	building.position = plan.parcel_position(parcel_index)
	# `apply_variation()` sólo sabe de cuartos de vuelta, que es todo lo que
	# necesitaba una rejilla cartesiana; un pueblo de ruta necesita el giro exacto
	# de la fachada, y para eso WP-C agregó `apply_variation_yaw()`.
	building.apply_variation_yaw(float(parcel.get("height_scale", 1.0)),
			_facade_yaw(building, parcel_index))
	return building


## Giro con el que la **fachada** de [param piece_root] queda mirando a la calle
## de la parcela [param parcel_index]. Ver [constant TOWN_PIECE_META].
##
## Al giro de la fachada se le suma el `yaw_jitter` que el resolvedor calculó
## para esa parcela: un cuarto de grado largo que corre la esquina de la fachada
## unos diez centímetros sobre la línea municipal. Va **sobre el edificio y no
## sobre el lote** a propósito —el lote sigue siendo un rectángulo alineado con
## su cuadra, y es contra él que el check mide solapes y contención—, y es
## posicional: el giro de la casa 2 de la manzana 7 no cambia si se agrega una
## casa en la manzana 3. Es la diferencia entre una hilera de casas y una hilera
## de cajas.
func _facade_yaw(piece_root: Node3D, parcel_index: int) -> float:
	var yaw := plan.parcel_yaw(parcel_index)
	if parcel_index >= 0 and parcel_index < plan.parcels.size():
		yaw += float(plan.parcels[parcel_index].get("yaw_jitter", 0.0))
	if piece_root.has_meta(TOWN_PIECE_META):
		return yaw + TOWN_YAW_OFFSET
	return yaw


## Caja baja de la ruina, deshabilitada hasta que termina el derrumbe.
func _make_rubble_shape(building: Building) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var node := CollisionShape3D.new()
	node.name = "RubbleShape"
	node.shape = box
	node.disabled = true
	building.add_child(node)
	return node


## Montículo de cascotes y columna de humo, ocultos hasta el derrumbe.
func _make_rubble_stage(building: Building, profile: BuildingProfile) -> void:
	var stage := Node3D.new()
	stage.name = "StageRubble"
	stage.visible = false
	building.add_child(stage)
	building.stage_rubble = stage

	var pile_mesh := profile.pick_rubble_mesh(building.base_size.y * building.height_scale)
	if pile_mesh != null:
		var pile := MeshInstance3D.new()
		pile.name = "Pile"
		pile.mesh = pile_mesh
		# Riesgo 9 del plan: geometría que aparece a mitad de partida no
		# participa de SDFGI.
		pile.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		stage.add_child(pile)
		building.rubble_pile = pile

	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.emitting = false
	smoke.amount = 40
	smoke.lifetime = 6.0
	smoke.fixed_fps = 30
	smoke.interpolate = true
	smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	smoke.process_material = _SMOKE_PROCESS
	smoke.draw_pass_1 = _SMOKE_QUAD
	smoke.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_range_end = Building.SMOKE_VISIBILITY_RANGE_END
	smoke.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	smoke.position = Vector3(0.0, 4.0, 0.0)
	stage.add_child(smoke)
	building.smoke = smoke


## Estallido de polvo de cada transición de etapa.
func _make_dust(building: Building, profile: BuildingProfile) -> GPUParticles3D:
	var dust := GPUParticles3D.new()
	dust.name = "DustBurst"
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.amount = 30
	dust.lifetime = 2.4
	dust.fixed_fps = 30
	dust.interpolate = true
	dust.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	dust.process_material = _DUST_PROCESS
	dust.draw_pass_1 = _DUST_QUAD
	dust.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.visibility_range_end = Building.SMOKE_VISIBILITY_RANGE_END
	dust.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	dust.position = Vector3(0.0, building.base_size.y * 0.35, 0.0)
	dust.amount_ratio = clampf(profile.dust_scale, 0.15, 1.0)
	building.add_child(dust)
	return dust


## Props de azotea en el 30 % de los edificios **grandes**. No llevan colisión:
## son decorativos y se desprenden al entrar en `DAMAGED`.
##
## Las casas no llevan: un cartel de 6 m sobre una casa de 5 no es un cartel, es
## un error de escala.
func _make_props(building: Building, base_size: Vector3, parcel: int) -> Node3D:
	# Reparto por deuda acumulada y no por tirada de dado: con pocas muestras
	# una Bernoulli de p = 0.30 se va con facilidad al 50 %, y `docs/10` §4.3
	# pide un 30 % parejo.
	_prop_debt += PROP_CHANCE
	if prop_pieces.is_empty() or _prop_debt < 1.0:
		return null
	_prop_debt -= 1.0
	var container := Node3D.new()
	container.name = PROPS_NODE
	building.add_child(container)

	var prop_scene := _pick(prop_pieces, SALT_ROOF_PROP, parcel, CHANNEL_PIECE)
	var prop := prop_scene.instantiate() as Node3D
	if prop == null:
		container.free()
		return null
	# Los props son decorativos: se los saca de toda capa en vez de desactivar su
	# `CollisionShape3D`, porque la capa y la máscara son propiedades de la raíz
	# de la instancia —y esas sí se guardan al empaquetar—, mientras que tocar un
	# nodo interno se perdería.
	var body := prop as PhysicsBody3D
	if body != null:
		body.collision_layer = 0
		body.collision_mask = 0

	var steps := mini(int(_unit(SALT_ROOF_PROP, parcel, CHANNEL_STEPS) * 4.0), 3)
	var prop_size: Vector3 = prop.get_meta(&"base_size", Vector3(2.0, 2.0, 2.0))
	var footprint := Vector2(prop_size.x, prop_size.z)
	if steps % 2 == 1:
		footprint = Vector2(prop_size.z, prop_size.x)
	var margin_x := maxf((base_size.x - footprint.x) * 0.5 - 0.5, 0.0)
	var margin_z := maxf((base_size.z - footprint.y) * 0.5 - 0.5, 0.0)
	# Altura **sin** variación: `Building.apply_variation()` (que corre después)
	# y `Building.reset()` la escalan con `height_scale` y guardan la posición de
	# reposo en `Building.PROP_REST_META`.
	prop.position = Vector3(
			lerpf(-margin_x, margin_x, _unit(SALT_ROOF_PROP, parcel, CHANNEL_OFFSET_X)),
			base_size.y,
			lerpf(-margin_z, margin_z, _unit(SALT_ROOF_PROP, parcel, CHANNEL_OFFSET_Z)))
	prop.rotation = Vector3(0.0, float(steps) * (PI * 0.5), 0.0)
	container.add_child(prop)
	return container


# --- Afuera del círculo ----------------------------------------------------

## Todo lo que vive fuera del círculo de juego: los dos caseríos, las rocas y la
## maleza.
func _build_decor() -> void:
	var decor := _container(DECOR_NODE)
	_build_decor_houses(decor)
	_build_rocks(decor)
	_build_decor_props(decor)


## Las doce casas de caserío, una instancia cada una.
##
## Son paisaje, no juego: no llevan `building.gd`, ni perfil, ni etapas, ni HP.
## Darles `Building` las metería en el grupo `buildings`, y con eso en
## `CityIntegrity`, en la elección de blanco del jefe y en la barra EN PIE: doce
## casas que el jugador no puede defender bajarían la integridad sin que nadie
## pueda hacer nada.
##
## Van en [constant PhysicsLayers.WORLD], como las rocas y el suelo, y **no** en
## la capa de ciudad en la que las importó WP-A: así el dron no las atraviesa, el
## rayo del arma se detiene en ellas igual que en el terreno y no hay nada que
## reciba daño, porque no hay `take_damage` a quien llamar.
##
## ## Se intentó fundirlas en una sola malla y salió peor
##
## Doce casas son doce [MeshInstance3D], y fundirlas en una parecía ahorrar once
## lotes por viewport. Medido, **costaba cuatro lotes más**: la malla fundida
## tiene el AABB de los dos caseríos, o sea que no se descarta nunca y entra en
## las tres cascadas de sombra del sol, mientras que las doce sueltas se
## descartan casi siempre. El fundido sirve para geometría junta y chica; para
## paisaje desparramado en setecientos metros, lo que sirve es el recorte por
## distancia.
func _build_decor_houses(parent: Node3D) -> void:
	for index: int in plan.parcels.size():
		var parcel := plan.parcels[index]
		if int(parcel.get("role", -1)) != TownPlan.Role.DECOR:
			continue
		var piece := _piece_for(parcel)
		if piece == null:
			continue
		var node := piece.instantiate() as Node3D
		if node == null:
			continue
		node.name = String(parcel.get("name", &"Decor_House"))
		var body := node as PhysicsBody3D
		if body != null:
			body.collision_layer = PhysicsLayers.WORLD
			body.collision_mask = 0
		# La `y` sale del plano, que para una casa de caserío es la altura del
		# terreno bajo ella (`TownPlanner._place_hamlets`): el horneado del
		# relieve le aplanó un pad debajo para que apoye en sus cuatro esquinas.
		node.position = plan.parcel_position(index)
		node.rotation = Vector3(0.0, _facade_yaw(node, index), 0.0)
		parent.add_child(node)


## Seis rocas de 8 a 18 m en el borde, en el grupo `city_rocks` (`docs/10` §4.4).
##
## Ninguna cae dentro del cono de [constant SPAWN_CONE_DEG] grados que sale del
## punto de aparición del dron hacia el centro del pueblo: en WP-21 una roca de
## 40 m tapaba media pantalla en el primer fotograma de la ronda. De eso se
## ocupa el plano; acá sólo se siembran.
func _build_rocks(parent: Node3D) -> void:
	var container := _container(ROCKS_NODE, parent)
	if rock_scenes.is_empty():
		return
	var spots := plan.rock_spots()
	for index: int in spots.size():
		var scene := rock_scenes[index % rock_scenes.size()]
		var rock := scene.instantiate() as Node3D
		if rock == null:
			continue
		rock.name = "Rock_%d" % index
		# Apoyada sobre el relieve y hundida veinte centímetros, que es lo que
		# la separa de una piedra puesta encima del pasto.
		rock.position = on_terrain(spots[index]) - Vector3(0.0, ROCK_SINK, 0.0)
		rock.rotation = Vector3(0.0, _unit(SALT_ROCK, index, CHANNEL_YAW) * TAU, 0.0)
		container.add_child(rock)


## Maleza, basura y barriles, repartidos entre un [MultiMeshInstance3D] por
## pieza y **sin colisión**: son dos triángulos tirados en el pasto y nadie
## choca con ellos (`docs/10` §7).
##
## El reparto es por turnos y no por sorteo: con noventa y seis manojos y cuatro
## piezas, un sorteo deja con facilidad una pieza con quince apariciones y otra
## con cuarenta, y lo que el campo necesita es que las cuatro se vean.
func _build_decor_props(parent: Node3D) -> void:
	var spots := plan.decor_spots()
	if spots.is_empty():
		return
	var meshes: Array[Mesh] = []
	for piece: PackedScene in decor_pieces:
		var baked := _bake_piece_mesh(piece)
		if baked != null:
			meshes.append(baked)
	if meshes.is_empty():
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 1.1, 0.9)
		if decor_material != null:
			box.material = decor_material
		meshes.append(box)

	var groups: Array[Array] = []
	for _slot: int in meshes.size():
		groups.append([] as Array[Transform3D])
	for index: int in spots.size():
		var mesh := meshes[index % meshes.size()]
		# La malla puede tener su origen en el centro (una caja de reserva) o en
		# la base (un prop importado): se la sube justo lo que su AABB baja de
		# `y = 0`, escalado como la instancia, para que apoye en el suelo en los
		# dos casos.
		var lift := -mesh.get_aabb().position.y * spots[index].basis.get_scale().y
		var origin := on_terrain(spots[index].origin) + Vector3(0.0, lift, 0.0)
		# Un manojo de maleza sigue la pendiente; el barril y los cajones también,
		# que es lo que los saca de la postal de «props clavados en la loma». La
		# inclinación se aplica sobre la base que ya trae el giro y la escala, así
		# que el prop no cambia de tamaño al inclinarse.
		groups[index % meshes.size()].append(
				Transform3D(_tilted(spots[index].basis, origin), origin))
	for slot: int in meshes.size():
		var transforms: Array[Transform3D] = groups[slot]
		_add_multimesh(parent, StringName("%s_%d" % [PROPS_NODE, slot]),
				meshes[slot], transforms)


## [param basis] reorientada para que su `+Y` siga la normal del terreno bajo
## [param at].
##
## Se compone la rotación mínima que lleva `+Y` a la normal **por la izquierda**
## para no tocar el giro ni la escala que la base ya traía. Con el terreno plano
## —o sin relieve— la rotación es la identidad y esto no hace nada.
func _tilted(basis: Basis, at: Vector3) -> Basis:
	if terrain == null or not terrain.has_method(&"normal_at"):
		return basis
	var normal: Vector3 = terrain.call(&"normal_at", at.x, at.z)
	if normal.length_squared() < 0.000001:
		return basis
	normal = normal.normalized()
	var axis := Vector3.UP.cross(normal)
	if axis.length_squared() < 0.000001:
		return basis
	return Basis(axis.normalized(), Vector3.UP.angle_to(normal)) * basis


## Saca a una casa del pase de sombra del sol.
##
## Es la palanca que cierra el presupuesto de lotes de `docs/13`, y sale de
## medir, no de suponer. Con la cámara dentro del pueblo, de 140 lotes por
## viewport **88 son las casas y 83 de esos son sus sombras**: cincuenta y dos
## casas entrando en cada cascada del sol. El ojo de pez FAST_WIDE dibuja la
## escena tres veces, así que son unos 250 lotes de un presupuesto de 900
## gastados en la sombra de cajas de tres metros.
##
## Lo que se pierde y lo que no: los siete edificios grandes —escuela, hito y
## cinco medianos— **siguen proyectando**, y son los que dan las sombras largas
## que el atardecer de `docs/13` necesita; las casas siguen **recibiendo** sombra
## y oclusión de SDFGI y SSAO, así que no flotan. Lo que desaparece es la sombra
## propia de cada casa sobre su patio.
##
## Se probaron antes dos palancas que no alcanzaron: fundir la decoración en una
## malla (costaba cuatro lotes **más**, porque el AABB fundido no se descarta
## nunca y entra en toda cascada) y recortar las casas por distancia (no ahorra
## nada: el pueblo mide 300 m y desde cualquier pose de juego las casas están
## dentro del rango).
## Si un edificio de rol [param role] y pieza [param piece] entra en el pase de
## sombra del sol.
##
## ## Por qué se recorta (WP-D3, defecto 6)
##
## El presupuesto de `docs/13` §10.1 son 900 lotes de dibujo y el pueblo de
## WP-D2 medía **857 de máximo** en el preset HIGH: quedaban cuarenta y tres de
## margen para todo lo que falta. Una malla que proyecta sombra se dibuja una
## vez por cascada del sol —cuatro en HIGH— además de su pase de color, así que
## sacar un edificio del pase de sombra devuelve hasta cuatro lotes, y hacerlo
## es más barato que cualquier otra cosa que se pueda tocar sin que se note.
##
## La regla es de **silueta**, no de presupuesto: proyecta sombra lo que hace
## de hito y lo que el jugador usa para orientarse.
##
## - Las **casas** ya estaban fuera desde WP-T4: son cincuenta y dos volúmenes
##   de tres metros y su sombra es un rectángulo más sobre la vereda.
## - La **estación de servicio** y el **galpón de campo** son las dos piezas de
##   POI por debajo de los ocho metros: su sombra no dice nada que su volumen no
##   diga ya, y la marquesina de la estación además la tapa entera.
## - Los **medianos de perfil bajo** —`block_mid` y `block_low_c`, once y nueve
##   metros— quedan fuera por lo mismo: a la hora del anochecer su sombra cae
##   sobre la manzana de al lado y se confunde con la de la manzana entera.
## - El **tanque de agua** y el **silo** se quedan con la suya, y el `tower_b`
##   de la escuela y del hito también: son los cuatro volúmenes altos del
##   pueblo, los que se ven desde la ruta a 500 m, y la sombra larga del sol
##   rasante es justamente lo que los apoya en el suelo (`docs/17` §4).
static func _casts_shadow(role: int, piece: StringName) -> bool:
	if role == TownPlan.Role.HOUSE:
		return false
	return not NO_SHADOW_PIECES.has(piece)


func _mute_house_shadow(building: Building) -> void:
	for node: Node in _descendants(building):
		var geometry := node as GeometryInstance3D
		if geometry == null:
			continue
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Marcadores ------------------------------------------------------------

## Cuatro `Marker3D` en los accesos del pueblo, que es por donde `RoundManager`
## hace entrar al coloso (`docs/11` §4.2).
func _build_spawns() -> void:
	var container := _container(SPAWNS_NODE)
	var spots := plan.spawn_points()
	for index: int in spots.size():
		var marker := Marker3D.new()
		marker.name = "EnemySpawn%d" % index
		# Se copia la transformada entera y no sólo el origen: el giro lo
		# calculó el plano a mano porque durante el horneado la rejilla todavía
		# no está en el árbol y `global_transform` no está definida. La cota, en
		# cambio, la pone el relieve: el plano dice «a ras del suelo» y el suelo
		# ya no es `y = 0`.
		marker.transform = on_terrain_xform(spots[index])
		container.add_child(marker)


## Ocho `Marker3D` de puesto de pila. Los tres de azotea se **afinan** con la
## altura real del edificio: el plano los calculó con su tabla de alturas
## nominales, que es lo que le permite no abrir un solo asset, y la malla puede
## discrepar medio metro.
func _build_posts() -> void:
	var container := _container(POSTS_NODE)
	var posts := plan.battery_posts()
	for index: int in posts.size():
		var marker := Marker3D.new()
		marker.name = "Post%d" % index
		marker.position = _refined_post(index, posts[index])
		container.add_child(marker)


func _refined_post(index: int, fallback: Vector3) -> Vector3:
	if index >= plan.battery_roof_parcels.size():
		return on_terrain(fallback)
	var parcel := plan.battery_roof_parcels[index]
	if parcel < 0:
		# Puesto de calle: el plano dice a cuántos metros **del suelo** cuelga.
		return on_terrain(fallback)
	var building := get_building_at(parcel)
	if building == null:
		return fallback
	return Vector3(building.position.x,
			building.position.y + building.get_height() + TownPlanner.POST_ROOF_CLEARANCE,
			building.position.z)


## Aparición del dron, centro del pueblo y pose de la cámara fija.
func _build_markers() -> void:
	var drone := Marker3D.new()
	drone.name = DRONE_NODE
	drone.transform = on_terrain_xform(plan.drone_spawn())
	add_child(drone)

	var centre := Marker3D.new()
	centre.name = CENTRE_NODE
	centre.position = on_terrain(plan.play_centre)
	# `persistent = true` o el grupo no se guarda en `town_a.tscn` y el jefe se
	# queda sin centro de pueblo al cargar la escena empaquetada.
	centre.add_to_group(CENTRE_GROUP, true)
	add_child(centre)

	var camera := Marker3D.new()
	camera.name = CAMERA_NODE
	camera.transform = on_terrain_xform(plan.camera_fixed())
	add_child(camera)


# --- Utilidades ------------------------------------------------------------

const _DUST_PROCESS: ParticleProcessMaterial = preload("res://assets/city/rubble/dust_process.tres")
const _SMOKE_PROCESS: ParticleProcessMaterial = preload("res://assets/city/rubble/smoke_process.tres")
const _DUST_QUAD: Mesh = preload("res://assets/city/rubble/dust_quad.tres")
const _SMOKE_QUAD: Mesh = preload("res://assets/city/rubble/smoke_quad.tres")


## Tirada determinista en `[0, 1)` para el índice [param index] y el canal
## [param channel] de la sal [param salt]. Ver [constant SALT_ROOF_PROP].
func _unit(salt: int, index: int, channel: int) -> float:
	return TownPlan.mix_unit(TownPlan.mix_all([salt, index, channel]))


## Una de [param options], elegida **posicionalmente**: la misma parcela elige
## siempre la misma pieza, aunque el diseño haya crecido por delante de ella.
func _pick(options: Array[PackedScene], salt: int, index: int,
		channel: int) -> PackedScene:
	if options.is_empty():
		return null
	return options[mini(int(_unit(salt, index, channel) * float(options.size())),
			options.size() - 1)]


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found


# --------------------------------------------------------------------------
# Plaza, puente, arboledas, cercos y props (P2c, WP-D2)
# --------------------------------------------------------------------------

## Piezas que el plano nombró y la tabla no tiene, con cuántas veces pasó.
##
## No es un error: mientras el manifiesto de WP-D1 no exista, el pueblo hornea
## sin tanque de agua, sin sauces y sin farolas, y lo que hace falta es **contar
## el hueco**, no taparlo con otra pieza. `tools/build_town.gd` lo imprime al
## final y los checks lo miran para saber si una pieza que falta es trabajo
## pendiente o una regresión.
var _missing_pieces: Dictionary[StringName, int] = {}


## Las piezas que faltaron en el último [method build], con su cuenta.
func missing_pieces() -> Dictionary[StringName, int]:
	return _missing_pieces


## La escena de [param id], o `null` anotándola en [member _missing_pieces].
##
## A diferencia de [method _piece_for] **no** hace ruido por cada instancia: una
## arboleda de trescientos sauces sin pieza llenaría el log con trescientas
## líneas iguales. Se cuenta y se informa una vez.
func _decor_piece(id: StringName) -> PackedScene:
	var piece := pieces.get(id, null) as PackedScene
	if piece == null:
		_missing_pieces[id] = int(_missing_pieces.get(id, 0)) + 1
	return piece


## El piso de la plaza: la losa y los canteros de pasto del centro.
##
## La plaza es la única manzana sin casas (`docs/17` §3), y lo que la hace
## legible desde el aire no es que le falten edificios sino que **tenga piso**:
## sin la losa, el jugador ve un hueco de pasto entre cuatro cuadras y lo lee
## como un baldío. La losa va con el material de vereda —es la misma cosa que
## una vereda, sólo que de cuarenta metros— metida un metro hacia adentro del
## polígono para que el cordón de la manzana siga leyéndose, y los canteros del
## centro con el material de campo: son los que dejan que el mástil, el
## monumento y los bancos se apoyen sobre algo que no es asfalto.
func _build_plaza() -> void:
	if plan == null or not plan.has_plaza():
		return
	var plaza := _container(PLAZA_NODE)
	var height := terrain_height_fn()
	var floor_polygon := TownPlan.polygon_shrink(plan.plaza_polygon, PLAZA_INSET)
	if floor_polygon.size() >= 3:
		var slab := RoadMesh.polygon_mesh(floor_polygon, height, SIDEWALK_TOP)
		if slab != null:
			var _floor := _add_surface(plaza, &"Floor",
					RoadMesh.paint(slab, walkway_material))
	var lawn_polygon := TownPlan.polygon_shrink(plan.plaza_polygon, PLAZA_LAWN_INSET)
	if lawn_polygon.size() >= 3:
		# Un centímetro por encima de la losa: coplanar con ella sería z-fighting
		# y es exactamente el defecto que P2c vino a borrar del viario.
		var lawn := RoadMesh.polygon_mesh(lawn_polygon, height, SIDEWALK_TOP + 0.01)
		if lawn != null:
			# El cantero lleva **su** material y no el del campo: es la única
			# superficie regada del pueblo y con el pasto seco del campo se leía
			# como un pozo negro en el medio de la losa (WP-D3, defecto 2).
			var paint: Material = lawn_material if lawn_material != null else ground_material
			var _lawn := _add_surface(plaza, &"Lawn", RoadMesh.paint(lawn, paint))


## La lámina de agua del arroyo (`docs/17` §4, WP-D3).
##
## Una sola cinta a lo largo de `creek_points`, de `creek_width` de ancho, un
## lote de dibujo y sin colisión: el dron la atraviesa igual que atraviesa el
## follaje, y lo que lo frena en el cauce es el terreno, que sigue estando ahí
## abajo.
##
## ## Por qué la cota sale del **eje** y no de cada vértice
##
## [method RoadMesh.ribbon] pregunta la altura del terreno en cada vértice, y en
## el arroyo eso es exactamente lo que no hay que hacer: los vértices de los
## bordes caen sobre el **talud**, así que el espejo subiría por la orilla y el
## agua quedaría en forma de V. La función de altura que se le pasa proyecta
## primero el punto sobre el eje del cauce y devuelve la cota de **ahí**: el
## agua queda horizontal a lo ancho y sigue el fondo a lo largo, que es lo que
## hace un arroyo.
##
## ## El vano
##
## Dentro del vano el terreno baja a propósito y el tablero pasa por encima. El
## agua se recorta contra la cara de abajo del tablero menos
## [constant CREEK_BRIDGE_CLEARANCE]: con el cauce de este diseño el recorte no
## llega a actuar —sobra aire de largo—, pero deja el invariante escrito en el
## código en vez de confiado a que nadie suba nunca el nivel del agua.
func _build_creek_water() -> void:
	if plan == null or not plan.has_creek() or water_material == null:
		return
	var axis := plan.creek_axis()
	if axis.size() < 2:
		return
	var line := _within_reach(_densified(axis, CREEK_STEP),
			Vector2(plan.play_centre.x, plan.play_centre.z), CREEK_WATER_REACH)
	if line.size() < 2:
		return
	var creek := _container(CREEK_NODE)
	var mesh := RoadMesh.ribbon(line, plan.creek_width * 0.5, creek_height_fn(), 0.0)
	if mesh == null:
		return
	var surface := _add_surface(creek, &"Water", RoadMesh.paint(mesh, water_material))
	if surface == null:
		return
	# Sin sombra: una lámina horizontal transparente no proyecta nada que se vea
	# y el mapa de sombras del sol es el recurso más escaso del cuadro.
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Altura del espejo de agua en `(x, z)`: la del terreno bajo el **eje** del
## arroyo más [constant CREEK_WATER_RISE], recortada contra el tablero.
func creek_height_fn() -> Callable:
	var axis := plan.creek_axis()
	var terrain_at := terrain_height_fn()
	var ceiling := INF
	var bridge_at := Vector2.ZERO
	var bridge_reach := 0.0
	if plan.has_bridge():
		ceiling = plan.bridge_at.y - BRIDGE_DECK_THICKNESS - CREEK_BRIDGE_CLEARANCE
		bridge_at = Vector2(plan.bridge_at.x, plan.bridge_at.z)
		bridge_reach = plan.bridge_span * 0.5 + BRIDGE_DECK_MARGIN
	return func(x: float, z: float) -> float:
		var point := Vector3(x, 0.0, z)
		var along := TownPlan.polyline_closest(axis, point)
		var on_axis := TownPlan.polyline_point(axis, along)
		var y := float(terrain_at.call(on_axis.x, on_axis.z)) + CREEK_WATER_RISE
		if bridge_reach > 0.0 and Vector2(x, z).distance_to(bridge_at) <= bridge_reach:
			y = minf(y, ceiling)
		return y


## El tramo contiguo de [param line] que queda a [param reach] metros o menos de
## [param centre], **más un vértice de sobra en cada punta**. El arroyo entra al
## disco por un extremo y sale por el otro, así que el tramo es uno solo y basta
## con recortar las dos puntas.
##
## ## Por qué sobra un vértice (WP-D3b)
##
## Recortando justo en el último vértice de dentro, la cinta termina **antes**
## del borde del alcance: entre ese vértice y el punto en que el eje cruza el
## círculo queda hasta un paso de densificado de cauce sin agua. `city_check`
## muestrea el eje crudo con su propio paso y cae ahí: a r 238,4 m de 240, en
## (−236,1; 33,1), el arroyo estaba seco. Con un vértice de sobra la cinta
## cruza el borde y tapa el hueco; cuesta dos cuadriláteros y ni un lote de
## dibujo, porque la lámina entera es una sola superficie.
##
## [param line] es la polilínea del eje del arroyo ya densificada, en XZ con la
## `y` sin usar; [param centre] es el centro del disco en planta —el
## `play_centre` del plano— y [param reach] su radio en metros. Devuelve una
## polilínea vacía si ningún vértice cae dentro o si el tramo se reduce a un
## punto, que es la forma de decir «acá no hay agua que dibujar».
static func _within_reach(line: PackedVector3Array, centre: Vector2,
		reach: float) -> PackedVector3Array:
	var first := -1
	var last := -1
	for index: int in line.size():
		if Vector2(line[index].x, line[index].z).distance_to(centre) > reach:
			continue
		if first < 0:
			first = index
		last = index
	if first < 0 or last <= first:
		return PackedVector3Array()
	return line.slice(maxi(first - 1, 0), mini(last + 2, line.size()))


## [param line] con un vértice cada [param step] metros como mucho.
##
## La cinta de agua no puede heredar los tramos de 25–60 m del eje del arroyo:
## la cota sale del fondo del cauce, que ondula, y entre dos vértices lejanos la
## cuerda se hundiría bajo la arena o saldría por encima del banco.
static func _densified(line: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if line.size() < 2:
		return line
	for index: int in line.size() - 1:
		var a := line[index]
		var b := line[index + 1]
		var cuts := maxi(ceili(a.distance_to(b) / maxf(step, 0.01)), 1)
		for cut: int in cuts:
			out.append(a.lerp(b, float(cut) / float(cuts)))
	out.append(line[line.size() - 1])
	return out


## El tablero del puente, con el rumbo de la ruta y la cota del perfil.
##
## La pieza de WP-D1 tiene la cara superior en `y = 0` y corre a lo largo de
## `+X`, así que se cuelga en la cota de la calzada: el tablero **es** el suelo
## de la ruta sobre el vano, y la cinta de asfalto apoya encima con sus tres
## centímetros de siempre.
func _build_bridge() -> void:
	if plan == null or not plan.has_bridge():
		return
	var piece := _decor_piece(plan.bridge_piece)
	if piece == null:
		return
	var node := piece.instantiate() as Node3D
	if node == null:
		return
	var bridge := _container(BRIDGE_NODE)
	node.name = "Deck"
	# El tablero **cabecea con el vano**. La calzada cruza el arroyo por una
	# recta, y esa recta está en pendiente: el terreno del lado oeste y el del
	# lado este no están a la misma cota. Un tablero horizontal bajo una calzada
	# en rampa deja el asfalto hundido en un extremo y volando en el otro —que es
	# lo que la aérea de WP-D3 mostraba— así que el `Deck` toma el cabeceo del
	# vano y su cota sale de la **misma** función que levanta la cinta de la ruta
	# (WP-D4a, hallazgo 8).
	node.transform = bridge_deck_xform()
	# **Siempre visible, sin sombra y estático para la GI** (WP-D4a, hallazgo 12).
	# La pieza viene del molde de props de WP-D1 y trae `visibility_range_end`
	# 180 m, que es un número pensado para un banco de plaza: el puente es lo
	# primero que se ve entrando por la ruta —`docs/17` §0.5 lo pone a 250 m del
	# pueblo— y a 180 m desaparecía justo cuando el revelado lo necesita. La
	# sombra sí se apaga: es un prop bajo y su sombra cae sobre el cauce, donde
	# no dice nada y cuesta tres cascadas.
	for child: Node in _descendants(node):
		var visual := child as GeometryInstance3D
		if visual == null:
			continue
		visual.visibility_range_end = 0.0
		visual.visibility_range_end_margin = 0.0
		visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		visual.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bridge.add_child(node)
	_add_bridge_collision(bridge, node)


## La transformada del tablero: dónde, con qué rumbo y con qué cabeceo.
##
## Vive aparte de [method _build_bridge] para que `tools/city_check.gd` pueda
## pedir lo mismo que la escena horneada tiene y medir el asfalto contra la cara
## superior del tablero sin copiar la cuenta.
##
## La cota es `route_height_fn()` más [constant ROAD_TOP] —la cara superior de la
## pieza está en su `y = 0` local y la cinta de la ruta se dibuja tres
## centímetros por encima de su función de altura— y el cabeceo es el arco
## tangente de la pendiente del vano medida entre sus dos extremos.
func bridge_deck_xform() -> Transform3D:
	var lift := route_height_fn()
	var span := maxf(plan.bridge_span, 0.001)
	var along := Vector3(cos(plan.bridge_yaw), 0.0, -sin(plan.bridge_yaw))
	var centre := Vector3(plan.bridge_at.x, 0.0, plan.bridge_at.z)
	var head := centre - along * (span * 0.5)
	var tail := centre + along * (span * 0.5)
	var y_head := float(lift.call(head.x, head.z))
	var y_tail := float(lift.call(tail.x, tail.z))
	var pitch := atan2(y_tail - y_head, span)
	var basis := Basis.from_euler(Vector3(0.0, plan.bridge_yaw, 0.0)) \
			* Basis.from_euler(Vector3(0.0, 0.0, pitch))
	var y := float(lift.call(centre.x, centre.z)) + ROAD_TOP
	return Transform3D(basis, Vector3(centre.x, y, centre.z))


## La losa de colisión del tablero.
##
## La pieza de WP-D1 viene **sin cuerpo** (`shape: "none"` en el manifiesto):
## es geometría de decorado, y el decorado del pueblo no choca con nada. El
## tablero es la excepción y tiene que serlo: el dron vuela a ras de la ruta y
## el coloso la cruza, y un puente que se atraviesa como una cortina convierte
## el único cruce del arroyo en un agujero. Se le pone una caja —no la malla—
## porque lo que hace falta es el piso, no las barandas.
func _add_bridge_collision(parent: Node3D, deck: Node3D) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(plan.bridge_span + BRIDGE_DECK_MARGIN, BRIDGE_DECK_THICKNESS,
			plan.bridge_deck_width)
	var shape := CollisionShape3D.new()
	shape.name = "DeckShape"
	shape.shape = box
	# La cara superior de la pieza está en `y = 0` local, así que la caja cuelga
	# media altura por debajo: el dron apoya sobre el tablero, no dentro.
	shape.position = Vector3(0.0, -BRIDGE_DECK_THICKNESS * 0.5, 0.0)
	var body := StaticBody3D.new()
	body.name = "DeckBody"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	body.transform = deck.transform
	body.add_child(shape)
	parent.add_child(body)


## Un [MultiMeshInstance3D] por especie de follaje.
##
## Sin colisión, sin sombra propia y con recorte por distancia. Las tres cosas
## por el mismo motivo: son miles de instancias de una malla de cien triángulos.
## Una colisión por árbol llenaría el espacio de fase de Jolt con geometría que
## nadie toca —el dron vuela y el coloso pisa, y ninguno de los dos se detiene en
## un arbusto—; una sombra por árbol metería cada arboleda en las tres cascadas
## del sol, que es la palanca que ya costó cerrar el presupuesto en P2b; y sin
## recorte, el maizal del sur se dibujaría desde la plaza.
func _build_groves() -> void:
	if plan == null or plan.grove_species.is_empty():
		return
	var groves := _container(GROVES_NODE)
	for index: int in plan.grove_species.size():
		var species := StringName(plan.grove_species[index])
		var points := plan.grove_points[index]
		if points.is_empty():
			continue
		var piece := _decor_piece(species)
		if piece == null:
			continue
		var mesh := _bake_piece_mesh(piece)
		if mesh == null:
			continue
		var transforms: Array[Transform3D] = []
		for slot: int in points.size():
			var scale := plan.grove_scales[index][slot] if slot < plan.grove_scales[index].size() \
					else 1.0
			var yaw := plan.grove_yaws[index][slot] if slot < plan.grove_yaws[index].size() \
					else 0.0
			var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)) \
					* Basis.from_scale(Vector3(scale, scale, scale))
			transforms.append(Transform3D(basis, on_terrain(points[slot])))
		var node := _add_multimesh(groves, species, mesh, transforms)
		if node != null:
			node.visibility_range_end = GROVE_RANGE
			node.visibility_range_end_margin = VISIBILITY_FADE_MARGIN
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Un [MultiMeshInstance3D] por clase de cerco.
##
## Los tramos ya vienen resueltos del plano —punto y rumbo, con el hueco de cada
## calle ya abierto—, así que acá sólo se apoyan sobre el relieve.
func _build_fences() -> void:
	if plan == null or plan.fence_points.is_empty():
		return
	var fences := _container(FENCES_NODE)
	for kind: int in TownDesign.FENCE_LINE_KINDS.size():
		var name := TownDesign.FENCE_LINE_KINDS[kind]
		var piece := _decor_piece(StringName(TownDesign.FENCE_PIECE.get(name, &"")))
		if piece == null:
			continue
		var mesh := _bake_piece_mesh(piece)
		if mesh == null:
			continue
		var transforms: Array[Transform3D] = []
		for index: int in plan.fence_points.size():
			if plan.fence_kinds[index] != kind:
				continue
			var yaw := plan.fence_yaws[index] if index < plan.fence_yaws.size() else 0.0
			transforms.append(Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)),
					on_terrain(plan.fence_points[index])))
		if transforms.is_empty():
			continue
		var node := _add_multimesh(fences, name, mesh, transforms)
		if node != null:
			node.visibility_range_end = FENCE_RANGE
			node.visibility_range_end_margin = VISIBILITY_FADE_MARGIN
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Los props posicionales, agrupados por pieza.
##
## Una pieza con [constant PROP_MULTIMESH_MIN] instancias o más se lleva su
## propio [MultiMesh]; las demás se funden en una sola malla estática. Es la
## misma cuenta que hizo el viario en WP-T1 y el mismo motivo: un lote de dibujo
## por dos bancos es un lote de dibujo mal gastado, y los props son geometría
## chica que nunca se mueve.
##
## Nada de esto lleva colisión. Un banco, un farol o un cartel que frenaran al
## dron convertirían el vuelo a ras de calle —que es donde el juego pasa— en una
## carrera de obstáculos invisibles: lo que frena al dron son el terreno, los
## edificios y las casas de caserío, y eso ya está resuelto.
func _build_props() -> void:
	if plan == null or plan.prop_placements.is_empty():
		return
	var props := _container(PROPS_NODE)
	var by_piece: Dictionary[StringName, Array] = {}
	var order: Array[StringName] = []
	for placement: Dictionary in plan.prop_placements:
		var piece := StringName(placement.get("piece", &""))
		if not by_piece.has(piece):
			by_piece[piece] = []
			order.append(piece)
		(by_piece[piece] as Array).append(placement)

	var merged: Array = []
	for piece: StringName in order:
		var scene := _decor_piece(piece)
		if scene == null:
			continue
		var mesh := _bake_piece_mesh(scene)
		if mesh == null:
			continue
		var placements: Array = by_piece[piece]
		var transforms: Array[Transform3D] = []
		for placement: Variant in placements:
			transforms.append(_prop_transform(placement as Dictionary))
		if transforms.size() >= PROP_MULTIMESH_MIN:
			var node := _add_multimesh(props, piece, mesh, transforms)
			if node != null:
				node.visibility_range_end = PROP_RANGE
				node.visibility_range_end_margin = VISIBILITY_FADE_MARGIN
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			continue
		for xform: Transform3D in transforms:
			merged.append(_transformed_mesh(mesh, xform))
	if merged.is_empty():
		return
	var node := _add_surface(props, &"Merged", RoadMesh.merge(merged))
	if node != null:
		node.visibility_range_end = PROP_RANGE
		node.visibility_range_end_margin = VISIBILITY_FADE_MARGIN
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## La transformada de un prop: apoyado sobre el relieve, girado como dice el
## diseño y, si lo pide, inclinado con la pendiente.
##
## `align_to_slope` es una decisión por prop y no una regla: un barril tirado en
## la banquina sigue la pendiente y una farola **no** —una farola inclinada se
## lee como una farola chocada—, así que quien lo decide es quien escribe el
## diseño.
func _prop_transform(placement: Dictionary) -> Transform3D:
	var point: Vector3 = placement.get("pos", Vector3.ZERO)
	var origin := on_terrain(point) if bool(placement.get("on_terrain", true)) else point
	var basis := Basis.from_euler(Vector3(0.0,
			float(placement.get("yaw", 0.0))
			+ _piece_yaw_offset(StringName(placement.get("piece", &""))), 0.0))
	if bool(placement.get("align", false)):
		basis = _tilted(basis, origin)
	return Transform3D(basis, origin)


## Cuarto de vuelta que hay que sumarle al giro de [param piece] para que su
## frente mire adonde el diseño dice.
##
## Es la misma corrección que [method _facade_yaw] le hace a los edificios por
## el metadato [constant TOWN_PIECE_META], dicha para piezas que se siembran por
## [MultiMesh] y por lo tanto no conservan metadatos: quién la contesta es el
## manifiesto de WP-D1 con su campo `front`.
##
## Las piezas que corren **a lo largo** de su eje —los tramos de cerco, el
## tablero del puente— no entran acá: su giro se calcula desde el rumbo del
## tramo, que ya es el de su `+X`, y sumarles un cuarto de vuelta las pondría de
## costado. Eso hasta WP-D4a era una regla que sólo vivía en este comentario y en
## que nadie las sembrara como props; ahora el manifiesto las declara con
## `front: "+X-run"` y esta función contesta cero para ellas (hallazgo 19), así
## que un diseño que ponga un `fence_wire_6m` suelto en `props[]` lo pone
## derecho.
func _piece_yaw_offset(piece: StringName) -> float:
	return TOWN_YAW_OFFSET if TownDesign.piece_front(piece) == &"-X" else 0.0


## Copia de [param mesh] con [param xform] horneada en sus vértices.
##
## Hace falta para fundir props: [method RoadMesh.merge] junta mallas por
## material y no sabe de transformadas, porque las cintas de calle ya vienen en
## coordenadas de mundo.
func _transformed_mesh(mesh: ArrayMesh, xform: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		moved.resize(vertices.size())
		for index: int in vertices.size():
			moved[index] = xform * vertices[index]
		arrays[Mesh.ARRAY_VERTEX] = moved
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var turned := PackedVector3Array()
			turned.resize(normals.size())
			for index: int in normals.size():
				turned[index] = (xform.basis * normals[index]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = turned
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := mesh.surface_get_material(surface)
		if material != null:
			out.surface_set_material(out.get_surface_count() - 1, material)
	return out
