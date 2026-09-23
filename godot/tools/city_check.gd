## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-20, reescrito por WP-D para el **pueblo de ruta**: verifica
## `city/districts/town_a.tscn` contra `docs/10` §11.2 y la nota de P2b.
##
## Instancia el pueblo y lo maltrata: cuenta los 59 destructibles y su reparto
## por rol, comprueba que ninguna variación de altura escaló un cuerpo físico,
## recorre las tres etapas de una casa, cronometra un derrumbe completo
## —escombros incluidos—, derriba diez seguidos para medir el tope del pool,
## arrasa el pueblo para comprobar que la integridad es monótona y que la derrota
## se publica una sola vez, y termina liberando todo para que no queden
## huérfanos.
##
## ## Qué cambió al pasar de la retícula al pueblo
##
## El distrito rectangular de P2 se medía contra un **modelo de carriles**: la
## extensión era la suma de anchos de carril, cada edificio vivía en una celda
## `Vector2i` y su fachada caía sobre una de cuatro líneas municipales. Nada de
## eso existe ya. Lo que el pueblo tiene es un [TownPlan] —una ruta, ejes de
## calle, manzanas convexas y parcelas con `frontage_point` y
## `frontage_normal`— y la regla de este check es **medir la escena contra el
## plano**, nunca contra una tabla de números copiada:
##
## - la **cuenta** y el **HP** se comparan con [method TownPlan.destructible_count]
##   y [method TownPlan.total_hp], no con un literal (el literal se conserva
##   además como banda ancha, para cazar un plano que cambió sin querer);
## - la **fachada** se rehace con la misma fórmula que publica
##   [method TownPlan.parcel_position], así que si mañana cambia la regla de
##   apoyo el check sigue midiendo lo que la rejilla construye;
## - el **círculo de juego** reemplaza a la caja del distrito: todo `Building`
##   adentro, toda la decoración afuera y ni un nodo de `Decor` con `building.gd`;
## - la **ruta** se muestrea cada dos metros y se comprueba que hay calzada
##   debajo, con el ancho que declara el plano y con banquina dentro del pueblo;
## - los **oclusores** pasan de quince a **cero**: un pueblo de casas de 5 m no
##   tiene nada que ocluir y [method CityGrid.occluder_for] devuelve `null`.
##
## Cierra con **dos pruebas negativas**: un perfil con el umbral de ruina mal
## puesto tiene que producir dos etapas en vez de tres, y un edificio corrido
## fuera del círculo de juego tiene que hacer saltar el sub-check del círculo.
## Sirven para saber que los sub-checks miden algo de verdad.
##
## No escribe en `user://` y deja `Global.round_seed` como estaba.
extends CheckRunner

## El pueblo horneado con semilla 0 (`tools/build_town.gd`).
const TOWN_PATH: String = "res://city/districts/town_a.tscn"

# --- Reparto del pueblo ------------------------------------------------------
#
# Los recuentos **se derivan del plano**, no se copian. Este check compara la
# escena horneada contra el plano que la generó, y el plano ya dice cuántas
# casas, medianos, hitos, escuelas, casas de caserío, rocas, apariciones,
# puestos y manzanas a oscuras tiene que haber. Escribirlos otra vez como
# constantes obligaba a tocar el check cada vez que el generador movía un número
# —y, peor, dejaba pasar una escena vieja mientras los dos números coincidieran
# por casualidad.
#
# Lo que sí queda fijo es lo que el plano **no** puede decidir: los rangos de
# diseño del encargo (`docs/10`) y las tolerancias.

## HP nominal de cada familia de perfil.
const HOUSE_HP: float = 1300.0
const BIG_HP: float = 3500.0

## Tolerancia del HP total de la escena contra el que declara el plano. No es
## una banda absoluta: el generador puede mover el reparto de casas y lo que
## importa es que la escena horneada coincida con **su** plano.
const HP_TOLERANCE: float = 1.0

# --- Umbrales de etapa y derrumbe (`docs/10` §3.1 y §11.2) -------------------

const DAMAGED_THRESHOLD: float = 0.60
const RUBBLE_THRESHOLD: float = 0.15

## Tope de tiempo del derrumbe completo, en segundos (`docs/10` §11.2 #8).
const COLLAPSE_BUDGET: float = 6.0

## Integridad por debajo de la cual se pierde la ronda (`docs/11` §4.1).
const DEFEAT_RATIO: float = 0.35

## Daño de un impacto del jugador sobre la ciudad: `16 × 0.375` (`docs/08` §2.7
## tras el rebalance del checkpoint 4).
const FRIENDLY_FIRE_DAMAGE: float = 6.0

## Impactos de fuego amigo para derribar una casa de 1 300 HP: `ceil(1300 / 6)`.
const FRIENDLY_FIRE_SHOTS: int = 217

## Shader de boquetes de las piezas de paleta (el perfil `house` trae el suyo).
const DAMAGE_SHADER_PATH: String = "res://city/damage_overlay.gdshader"
const PALETTE_SHADER_PATH: String = "res://city/damage_overlay_palette.gdshader"

## Material del asfalto. El suelo del pueblo **no** puede usarlo: es campo.
const ROADS_MATERIAL_PATH: String = "res://assets/city/materials/roads.tres"

## Malla de escombro que el perfil `house` tiene que **reutilizar** del perfil
## `low_block`, porque el `RubbleField` sólo admite cuatro campos y los enemigos
## reservan dos (`docs/10` §6).
const DEBRIS_SMALL_PATH: String = "res://assets/city/rubble/debris_concrete_small.res"

# --- Apoyo y fachada ---------------------------------------------------------

## Tolerancias de la alineación a la línea municipal.
const FACADE_TOLERANCE: float = 0.05
const BASE_TOLERANCE: float = 0.011
const YAW_TOLERANCE_DEG: float = 0.5

## Holgura con la que se acepta que la huella de una parcela caiga dentro del
## polígono de su manzana. Es negativa —es decir, se tolera asomar un
## centímetro— porque el polígono viene de recortar semiplanos en coma flotante.
const FOOTPRINT_MARGIN: float = -0.01

# --- Ruta --------------------------------------------------------------------

## Paso del muestreo de la ruta, en metros.
const ROUTE_SAMPLE_STEP: float = 2.0

## Tolerancia del ancho de calzada, en metros: cuánto puede faltarle o sobrarle
## a la media franja de asfalto medida contra el eje.
const ROUTE_WIDTH_TOLERANCE: float = 0.2

## Paso con el que se busca el borde de la calzada a lo ancho, en metros.
const ROUTE_WIDTH_STEP: float = 0.05

## La ruta tiene que seguir existiendo a esta distancia del centro, **por los dos
## lados**. Una ruta que muere a 200 m del pueblo no es una ruta: es una calle.
const ROUTE_REACH_MIN: float = 500.0

# --- Relieve (P2c, WP-T4) ----------------------------------------------------

## Cuánto puede separarse una esquina de huella de su cota de apoyo, en metros
## (criterio 6 del plan: «casas apoyadas, 4 esquinas dentro de ±2 cm»).
const REST_TOLERANCE: float = 0.02

## Cuánto puede separarse un marcador de `height_at + holgura`, en metros.
const GROUND_MARKER_TOLERANCE: float = 0.05

## Muestras con las que se busca campo lejano asomando por encima del relieve, y
## su semilla.
const FAR_FIELD_SAMPLES: int = 2000
const FAR_FIELD_SEED: int = 20260922

## Escalón máximo en la junta entre el relieve y el campo lejano, en metros.
const SEAM_TOLERANCE: float = 0.01

## Muestras con las que se recorre la junta.
const SEAM_SAMPLES: int = 360

## Tope del `.tscn` horneado, en kilobytes (plan P2c §5.12).
const TSCN_BUDGET_KB: float = 500.0

# --- Red viaria --------------------------------------------------------------

## Paso del muestreo del **borde** de calzada, en metros (`docs/10`, P2c §5).
const EDGE_STEP: float = 1.0

## Cuánto se mete hacia adentro la muestra del borde, para no caer justo sobre
## la arista de la cinta.
const EDGE_INSET: float = 0.25

## Separación admitida entre el asfalto y el terreno que tiene debajo, en
## metros. Por debajo de un centímetro el depth buffer no los puede ordenar
## —eso es z-fighting— y por encima de ocho la calzada flota.
const ASPHALT_CLEARANCE_MIN: float = 0.01
const ASPHALT_CLEARANCE_MAX: float = 0.08

## Holgura con la que se pregunta si un punto está cubierto (negativa: se acepta
## el borde) y con la que se pregunta si está cubierto **dos veces** (positiva:
## el borde compartido de dos triángulos vecinos no es un solape).
const COVER_MARGIN: float = -0.02
const OVERLAP_MARGIN: float = 0.02

## Cordón de la vereda y su tolerancia, en metros.
const CURB_HEIGHT: float = RoadMesh.CURB
const CURB_TOLERANCE: float = 0.01

## Hueco máximo admitido al recorrer un anillo de vereda, en metros, y paso del
## recorrido.
const RING_GAP_MAX: float = 0.05
const RING_STEP: float = 0.04

## Cuánto puede alejarse el extremo de una calle del polígono de su nodo.
const STUB_TOLERANCE: float = 0.05

## Lado de la celda de la rejilla con la que se indexan los triángulos del
## viario, en metros.
const INDEX_CELL: float = 5.0

## Desplazamiento de la cinta en la prueba negativa de z-fighting, en metros.
const ZFIGHT_SHIFT: float = 0.05

# --- Campo y rocas -----------------------------------------------------------

const ROCK_CONE_DEG: float = 30.0

# --- Ventanas racionadas (`docs/13` §1) --------------------------------------

## Banda admitida de la ración de ventanas sobre el total de manzanas.
const WINDOWS_DARK_MIN: float = 0.25
const WINDOWS_DARK_MAX: float = 0.35

## Semilla de control del determinismo.
const WINDOWS_SEED_B: int = 987654

## Materiales distintos admitidos en las fachadas. El pueblo mezcla dos
## familias: las casas GLB de paleta (opaca + ventanas) y las piezas FBX de
## VoxelCity de los siete grandes, más las copias apagadas de las que emiten.
const WINDOWS_MAX_MATERIALS: int = 6

## Material compartido de las ventanas de las casas; el racionamiento lo duplica
## y **nunca** lo muta.
const TOWN_WINDOWS_MATERIAL_PATH: String = "res://assets/town/materials/town_houses_windows.tres"

# --- Silueta y presupuesto ---------------------------------------------------

## El edificio más alto del pueblo (el hito, `tower_b` ×1,45).
const SKYLINE_MIN: float = 17.0
const SKYLINE_MAX: float = 20.0

## Altura del Arachnodroid (`docs/05`): el pueblo no puede taparlo.
const BOSS_HEIGHT: float = 29.0

## Tope de lotes de dibujo del distrito a 1080p (`docs/10` §7).
const DRAW_CALL_BUDGET: int = 900

# --- Decoración inerte -------------------------------------------------------

## Impactos que se le tiran a una casa de caserío para comprobar que no responde.
const DECOR_SHOTS: int = 200

# --- Marcadores --------------------------------------------------------------


## Distancia de los accesos del coloso al centro: `play_radius + 60 ± 1`.
const SPAWN_MARGIN: float = 60.0
const SPAWN_MARGIN_TOLERANCE: float = 1.0

## Cuánto puede desviarse el rumbo de un acceso respecto de la línea al centro.
const SPAWN_FACING_DEG: float = 2.0

## Tolerancia con la que un marcador horneado tiene que coincidir con el punto
## que publica el plano, en metros.
const MARKER_TOLERANCE: float = 0.05

## Cuántos de los ocho puestos de pila van en azotea.
const ROOF_POSTS: int = 3

## Cuánto puede afinarse un puesto de azotea respecto de la altura nominal del
## plano. Más que esto quiere decir que la tabla de alturas de [TownPlanner] y la
## malla de la pieza dejaron de parecerse.
const ROOF_REFINE_MAX: float = 3.0

## Tolerancia del cociente entre lo que cuesta el protegido y lo que cuesta un
## edificio de su mismo HP.
const PROTECTED_WEIGHT_TOLERANCE: float = 0.02

var _town: CityGrid = null
var _plan: TownPlan = null

## El plano que `TownPlanner` produce **hoy** con la semilla del pueblo. Es el
## que trae el grafo mientras `town_a.tscn` siga horneado de P2b, y es contra el
## que las filas de viario miden de verdad. Ver [method _check_road_surfaces].
var _fresh: TownPlan = null
var _integrity: CityIntegrity = null
var _pool: DebrisPool = null
var _field: RubbleField = null

var _destroyed_events: Array[Dictionary] = []
var _integrity_samples: PackedFloat32Array = PackedFloat32Array()
var _trauma_events: Array[Dictionary] = []
var _defeat_events: int = 0
var _seed_before: int = 0

## Cuentas del plano guardadas antes de la limpieza, para el resumen final.
var _destructible: int = 0
var _houses: int = 0

## Emisores del pueblo, cacheados por [method _sample_budgets].
var _emitters: Array[GPUParticles3D] = []

var _max_live_debris: int = 0
var _max_emitters: int = 0
var _max_emitting_nodes: int = 0
var _emitter_overflow_reported: int = 0
var _collapse_seconds: float = 0.0
var _collapse_piece: String = ""
var _draw_calls: int = 0
var _estimated_batches: int = 0


## La primera línea en la que dos firmas de plano discrepan, ya formateada para
## colgar del mensaje de la fila.
##
## Sin esto, «el pueblo está desactualizado» no dice **en qué**: puede ser una
## parcela que se movió un milímetro o el grafo entero que apareció, y la
## diferencia decide si hay que re-hornear o si cambió el generador.
func _signature_diff(baked: String, fresh: String) -> String:
	var left := baked.split("
")
	var right := fresh.split("
")
	for index: int in maxi(left.size(), right.size()):
		var a := left[index] if index < left.size() else "<falta>"
		var b := right[index] if index < right.size() else "<falta>"
		if a == b:
			continue
		return " · primera diferencia en la línea %d: horneado '%s' vs generado '%s'" 				% [index, a.left(90), b.left(90)]
	return ""


## Cuántas parcelas de rol [param role] declara el plano.
func _expected(role: int) -> int:
	return _plan.parcels_of_role(role).size()


func _run() -> void:
	_seed_before = Global.round_seed
	_pool = get_node_or_null(^"DebrisPool") as DebrisPool
	_field = get_node_or_null(^"DebrisPool/RubbleField") as RubbleField
	if _pool == null or _field == null:
		fail("la escena del check no trae DebrisPool ni RubbleField")
		return

	if not ResourceLoader.exists(TOWN_PATH):
		fail("falta '%s'; generalo con tools/build_town.gd" % TOWN_PATH)
		return
	_town = (ResourceLoader.load(TOWN_PATH, "PackedScene") as PackedScene).instantiate() as CityGrid
	if _town == null:
		fail("la raíz de '%s' no es un CityGrid" % TOWN_PATH)
		return
	add_child(_town)
	_plan = _town.get_plan()
	if _plan == null:
		fail("'%s' no trae TownPlan" % TOWN_PATH)
		return

	# Todo lo que sigue compara la escena contra **el plano que viaja dentro de
	# ella**, así que una escena vieja se verifica contra su propio pasado y pasa
	# en verde. Esto es lo único que ata las dos cosas: el plano horneado tiene
	# que ser el que `TownPlanner` produce hoy con la semilla de
	# `tools/build_town.gd`.
	_fresh = TownPlanner.generate(TownPlanner.TOWN_SEED)
	var fresh := _fresh
	expect(_plan.signature() == fresh.signature(),
			"'%s' está desactualizado respecto de TownPlanner: corré tools/build_town.gd%s"
			% [TOWN_PATH, _signature_diff(_plan.signature(), fresh.signature())])

	_integrity = CityIntegrity.new()
	_integrity.name = "CityIntegrity"
	_integrity.grid = _town
	add_child(_integrity)
	await wait_physics(2)

	_connect_bus()

	_destructible = _plan.destructible_count()
	_houses = _expected(TownPlan.Role.HOUSE)

	_check_counts()
	_check_hp_total()
	_check_play_circle()
	_check_facades()
	_check_no_body_scale()
	_check_route()
	_check_street_batching()
	_check_road_surfaces()
	_check_road_negative()
	_check_field_and_rocks()
	_check_houses_rest()
	_check_far_field()
	_check_ground_markers()
	_check_route_support()
	_check_scene_size()
	_check_ground_negative()
	_check_occluders()
	_check_windows()
	_check_skyline()
	_check_gi_modes()
	_check_debris_profiles()
	_check_markers()
	_check_budget()

	await _check_decor_inert()
	await _check_stages()
	await _check_friendly_fire()
	await _check_collapse_time()
	await _check_siege()
	await _check_protected()
	await _check_debris_cap()
	await _check_integrity_run()
	_check_negative_threshold()
	_check_negative_play_circle()
	await _check_cleanup()

	_print_metrics()
	_restore()


# --------------------------------------------------------------------------
# Bus
# --------------------------------------------------------------------------

func _connect_bus() -> void:
	var _a := Events.building_destroyed.connect(_on_building_destroyed)
	var _b := Events.city_integrity_changed.connect(_on_integrity_changed)
	var _c := Events.camera_trauma.connect(_on_camera_trauma)
	var _d := _integrity.defeat_threshold_reached.connect(_on_defeat)


func _on_building_destroyed(position: Vector3, value: int) -> void:
	_destroyed_events.append({"position": position, "value": value})


func _on_integrity_changed(ratio: float) -> void:
	_integrity_samples.append(ratio)


func _on_camera_trauma(amount: float, position: Vector3) -> void:
	_trauma_events.append({"amount": amount, "position": position})


func _on_defeat() -> void:
	_defeat_events += 1


# --------------------------------------------------------------------------
# 1. Cuenta y reparto por rol
# --------------------------------------------------------------------------

## 59 `Building`, todos en el grupo `buildings`, todos con perfil y con el nombre
## que su rol manda.
##
## La cuenta se afirma **dos veces**: contra [method TownPlan.destructible_count]
## —que es la verdad del plano y no se puede desincronizar de la escena sin que
## esto salte— y contra el literal de diseño, que caza un plano regenerado con
## otros números sin que nadie lo haya decidido.
func _check_counts() -> void:
	var buildings := _town.get_buildings()
	expect(buildings.size() == _plan.destructible_count(),
			"edificios sembrados: %d, destructibles del plano: %d"
			% [buildings.size(), _plan.destructible_count()])
	expect(buildings.size() == _plan.destructible_count(),
			"edificios: %d, esperados %d" % [buildings.size(), _plan.destructible_count()])
	var grouped := get_tree().get_nodes_in_group(Building.GROUP).size()
	expect(grouped == _plan.destructible_count(),
			"nodos en el grupo '%s': %d, esperados %d"
			% [Building.GROUP, grouped, _plan.destructible_count()])

	var by_role: Dictionary[int, int] = {}
	var parcels_seen: Dictionary[int, bool] = {}
	for building: Building in buildings:
		if building.profile == null:
			fail("'%s' no tiene perfil" % building.name)
			continue
		var role: int = building.get_meta(&"role", -1)
		by_role[role] = int(by_role.get(role, 0)) + 1
		var parcel: int = building.get_meta(&"parcel", -1)
		if parcels_seen.has(parcel):
			fail("dos edificios en la parcela %d" % parcel)
		parcels_seen[parcel] = true
		_expect_role_name(building, role)
	expect(parcels_seen.size() == _plan.destructible_count(),
			"parcelas ocupadas: %d, esperadas %d" % [parcels_seen.size(), _plan.destructible_count()])

	var wanted: Dictionary[int, int] = {
		TownPlan.Role.HOUSE: _expected(TownPlan.Role.HOUSE),
		TownPlan.Role.MEDIUM: _expected(TownPlan.Role.MEDIUM),
		TownPlan.Role.LANDMARK: _expected(TownPlan.Role.LANDMARK),
		TownPlan.Role.SCHOOL: _expected(TownPlan.Role.SCHOOL),
	}
	var labels: Array[String] = ["casas", "medianos", "hito", "escuela"]
	for role: int in wanted:
		var found := int(by_role.get(role, 0))
		expect(found == int(wanted[role]),
				"%s: %d, esperados %d" % [labels[role], found, int(wanted[role])])
		expect(_plan.parcels_of_role(role).size() == int(wanted[role]),
				"el plano declara %d parcelas de rol %d, esperadas %d"
				% [_plan.parcels_of_role(role).size(), role, int(wanted[role])])
	print("  cuenta: %d destructibles = %d casas + %d medianos + %d hito + %d escuela"
			% [buildings.size(), _expected(TownPlan.Role.HOUSE), _expected(TownPlan.Role.MEDIUM), _expected(TownPlan.Role.LANDMARK),
			_expected(TownPlan.Role.SCHOOL)] + " · todos en '%s' y con perfil" % Building.GROUP)


## El nombre de un edificio tiene que decir su rol: `RoundCatalog` busca al
## protegido **por nombre** y `docs/11` §1 lo declara como `Building_School`.
func _expect_role_name(building: Building, role: int) -> void:
	match role:
		TownPlan.Role.SCHOOL:
			expect(building.name == String(TownPlan.SCHOOL_NODE),
					"la escuela se llama '%s' y tendría que ser '%s'"
					% [building.name, TownPlan.SCHOOL_NODE])
		TownPlan.Role.LANDMARK:
			expect(building.name == String(TownPlan.LANDMARK_NODE),
					"el hito se llama '%s' y tendría que ser '%s'"
					% [building.name, TownPlan.LANDMARK_NODE])
		TownPlan.Role.MEDIUM:
			expect(building.name.begins_with(TownPlan.MEDIUM_PREFIX),
					"el mediano '%s' no empieza por '%s'"
					% [building.name, TownPlan.MEDIUM_PREFIX])
		TownPlan.Role.HOUSE:
			expect(building.name.begins_with(TownPlan.HOUSE_PREFIX),
					"la casa '%s' no empieza por '%s'"
					% [building.name, TownPlan.HOUSE_PREFIX])
		_:
			fail("'%s' tiene el rol %d, que no es destructible" % [building.name, role])


# --------------------------------------------------------------------------
# 2. HP total
# --------------------------------------------------------------------------

## La suma de `max_hp` coincide con [method TownPlan.total_hp] y cae en la banda
## de diseño. Es el número contra el que `CityIntegrity` mide la ronda entera, y
## el que recalibra `balance_check`.
func _check_hp_total() -> void:
	var total := 0.0
	var houses := 0
	var bigs := 0
	for building: Building in _town.get_buildings():
		total += building.get_max_hp()
		if is_equal_approx(building.get_max_hp(), BIG_HP):
			bigs += 1
		elif is_equal_approx(building.get_max_hp(), HOUSE_HP):
			houses += 1
		else:
			fail("'%s' tiene max_hp %.0f, que no es ni %.0f ni %.0f"
					% [building.name, building.get_max_hp(), HOUSE_HP, BIG_HP])
	expect_near(total, _plan.total_hp(), 0.5,
			"la suma de perfiles (%.0f) no coincide con TownPlan.total_hp() (%.0f)"
			% [total, _plan.total_hp()])
	# Contra el plano, no contra una banda escrita a mano: lo que este check
	# garantiza es que la escena horneada y su plano dicen lo mismo, y que el
	# plano esté dentro de lo que pide el diseño ya lo verifica `town_plan_check`.
	expect_near(total, _plan.total_hp(), HP_TOLERANCE,
			"HP total de la escena %.0f y del plano %.0f" % [total, _plan.total_hp()])
	expect(houses == _expected(TownPlan.Role.HOUSE),
			"edificios de %.0f HP: %d, esperados %d" % [HOUSE_HP, houses, _expected(TownPlan.Role.HOUSE)])
	expect(bigs == _plan.destructible_count() - _expected(TownPlan.Role.HOUSE),
			"edificios de %.0f HP: %d, esperados %d"
			% [BIG_HP, bigs, _plan.destructible_count() - _expected(TownPlan.Role.HOUSE)])
	expect_near(_integrity.get_initial_hp(), total, 0.5,
			"CityIntegrity.get_initial_hp() no coincide con la suma de perfiles")
	print("  HP: %.0f = %d × %.0f + %d × %.0f · el plano dice %.0f (±%.1f)"
			% [total, houses, HOUSE_HP, bigs, BIG_HP, _plan.total_hp(), HP_TOLERANCE])


# --------------------------------------------------------------------------
# 3. Círculo de juego
# --------------------------------------------------------------------------

## Todo lo destructible dentro del círculo y toda la decoración afuera.
##
## Es la regla que reemplaza a la caja del distrito rectangular y la que sostiene
## que la integridad sea **defendible**: `CityIntegrity` mide sobre el grupo
## `buildings`, así que una casa contada de más a 300 m del círculo sería
## integridad que el jugador no puede proteger, y una casa de caserío con
## `building.gd` haría exactamente eso.
func _check_play_circle() -> void:
	var problems := _play_circle_problems()
	for problem: String in problems:
		fail(problem)
	var decor := _decor_houses()
	expect(decor.size() == _expected(TownPlan.Role.DECOR),
			"casas de caserío: %d, esperadas %d" % [decor.size(), _expected(TownPlan.Role.DECOR)])
	var furthest := 0.0
	var nearest_decor := INF
	for building: Building in _town.get_buildings():
		furthest = maxf(furthest, _plan.distance_to_centre(building.position))
	for node: Node3D in decor:
		nearest_decor = minf(nearest_decor, _plan.distance_to_centre(node.position))
	print("  círculo: %d edificios dentro de %.0f m (el más lejano a %.1f) · %d casas de caserío"
			% [_plan.destructible_count(), _plan.play_radius, furthest, decor.size()]
			+ " afuera (la más cerca a %.1f m), ninguna con building.gd" % nearest_decor)


## Los incumplimientos del círculo de juego, como lista de mensajes.
##
## Va aparte del sub-check para que la **prueba negativa** pueda correr las
## mismas rutinas sobre un pueblo estropeado a mano y comprobar que las rechazan.
func _play_circle_problems() -> Array[String]:
	var found: Array[String] = []
	for building: Building in _town.get_buildings():
		var distance := _plan.distance_to_centre(building.position)
		if distance > _plan.play_radius:
			found.append("'%s' está a %.1f m del centro, fuera del círculo de %.0f m"
					% [building.name, distance, _plan.play_radius])
	var decor_root := _town.get_node_or_null(NodePath(CityGrid.DECOR_NODE))
	if decor_root == null:
		found.append("el pueblo no tiene el nodo '%s'" % CityGrid.DECOR_NODE)
		return found
	for node: Node in _all_nodes(decor_root):
		if node is Building:
			found.append("'%s' cuelga de '%s' y lleva building.gd"
					% [node.name, CityGrid.DECOR_NODE])
		if node.is_in_group(Building.GROUP):
			found.append("'%s' cuelga de '%s' y está en el grupo '%s'"
					% [node.name, CityGrid.DECOR_NODE, Building.GROUP])
		# Lo que se mide es la posición de los **objetos** de la decoración: las
		# doce casas de caserío y las seis rocas, que son cuerpos. Los
		# contenedores (`Rocks`) y los cuatro `MultiMeshInstance3D` de maleza
		# viven en el origen y su transformada no significa nada; la maleza,
		# además, se siembra **a propósito** también sobre las manzanas del pueblo
		# (`TownPlanner._place_decor`), así que exigirle estar afuera sería exigir
		# un campo sin pasto adentro.
		var body := node as PhysicsBody3D
		if body == null:
			continue
		var spot := _plan.distance_to_centre(body.global_position)
		if spot <= _plan.play_radius:
			found.append("'%s' es decoración y cae dentro del círculo (a %.1f m del centro)"
					% [body.name, spot])
	return found


## Las casas de caserío: hijos directos de `Decor` cuyo nombre lleva el prefijo
## del plano.
func _decor_houses() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var decor_root := _town.get_node_or_null(NodePath(CityGrid.DECOR_NODE))
	if decor_root == null:
		return found
	for child: Node in decor_root.get_children():
		var spatial := child as Node3D
		if spatial != null and spatial.name.begins_with(TownPlan.DECOR_PREFIX):
			found.append(spatial)
	return found


# --------------------------------------------------------------------------
# 4. Fachadas
# --------------------------------------------------------------------------

## Cada edificio apoya su fachada sobre la línea de frente de su parcela, con la
## base a la altura de la vereda, la huella dentro del polígono de su manzana y
## el giro que deja su frente mirando a la calle.
##
## El giro es la parte que no se puede copiar de una tabla, porque **las dos
## familias de pieza no tienen la fachada en el mismo eje**: las FBX de VoxelCity
## la tienen en `-Z` y las GLB de WP-A en `-X`. El check resuelve la familia por
## el metadato `town_kind` —el mismo que usa [method CityGrid._facade_yaw]— y no
## por el nombre del archivo: un pueblo con las casas giradas un cuarto de vuelta
## enseña a la calle su pared lateral, y eso no se ve en ningún informe.
func _check_facades() -> void:
	var worst_offset := 0.0
	var worst_base := 0.0
	var worst_yaw := 0.0
	var glb := 0
	var fbx := 0
	for building: Building in _town.get_buildings():
		var index: int = building.get_meta(&"parcel", -1)
		if index < 0 or index >= _plan.parcels.size():
			fail("'%s' no lleva el metadato de parcela" % building.name)
			continue
		var parcel := _plan.parcels[index]
		var point: Vector3 = parcel.get("frontage_point", Vector3.ZERO)
		var normal: Vector3 = parcel.get("frontage_normal", Vector3.FORWARD)
		var depth := float(parcel.get("depth", 0.0))

		# Distancia con signo de la fachada a la línea de frente. El edificio
		# está corrido media profundidad hacia adentro de la manzana, así que
		# esta cuenta tiene que dar cero.
		var delta := building.position - point
		var offset := delta.x * normal.x + delta.z * normal.z + depth * 0.5
		worst_offset = maxf(worst_offset, absf(offset))
		expect(absf(offset) <= FACADE_TOLERANCE,
				"'%s' está a %.3f m de su línea de frente, tope %.2f m"
				% [building.name, offset, FACADE_TOLERANCE])

		# Lo anterior comprueba la **regla** (la fachada apoya sobre la línea);
		# esto comprueba que el edificio horneado esté donde el plano dice que
		# esté. Sin esta fila, un `town_a.tscn` con todos los edificios corridos
		# en bloque —o sembrados con otra versión de `parcel_position()`— pasaba
		# en verde, porque la regla se cumple igual en cualquier traslación.
		var wanted := _plan.parcel_position(index)
		expect(building.position.distance_to(wanted) <= FACADE_TOLERANCE,
				"'%s' está horneado en %s y el plano lo pone en %s (%.3f m)"
				% [building.name, str(building.position), str(wanted),
				building.position.distance_to(wanted)])

		# La cota de apoyo ya no es una constante: sale de la manzana. Con el
		# relieve de WP-T2 debajo, cada manzana tiene su cota civil y el edificio
		# apoya en `datum + vereda`, que es lo que el resolvedor guarda en
		# `base_y`.
		var base_y := float(parcel.get("base_y", TownPlan.SIDEWALK_TOP))
		worst_base = maxf(worst_base, absf(building.position.y - base_y))
		expect(absf(building.position.y - base_y) <= BASE_TOLERANCE,
				"'%s' apoya en y = %.3f, esperado %.3f ±%.3f (cota de la manzana %d)"
				% [building.name, building.position.y, base_y, BASE_TOLERANCE,
				int(parcel.get("block", -1))])

		var block := int(parcel.get("block", -1))
		var polygon := _plan.block_polygon(block)
		if polygon.size() >= 3:
			for corner: Vector2 in _plan.parcel_footprint(index):
				if not TownPlan.polygon_contains(polygon, corner, FOOTPRINT_MARGIN):
					fail("la huella de '%s' se sale de la manzana %d por %.3f m"
							% [building.name, block,
							-TownPlan.polygon_inset(polygon, corner)])
					break

		# Al giro de la fachada se le suma el `yaw_jitter` posicional del
		# resolvedor: un cuarto de grado largo que corre la esquina unos diez
		# centímetros y saca a la hilera de casas de la cuadrícula. Va sobre el
		# **edificio**, no sobre el lote, así que el lote sigue siendo el
		# rectángulo con el que se miden solapes y contención.
		var expected := _plan.parcel_yaw(index) + float(parcel.get("yaw_jitter", 0.0))
		var town_kind := building.has_meta(CityGrid.TOWN_PIECE_META)
		if town_kind:
			glb += 1
			expected += CityGrid.TOWN_YAW_OFFSET
		else:
			fbx += 1
		var drift := absf(wrapf(building.rotation.y - expected, -PI, PI))
		worst_yaw = maxf(worst_yaw, drift)
		expect(rad_to_deg(drift) <= YAW_TOLERANCE_DEG,
				"'%s' (%s) está girado %.4f rad y su fachada pide %.4f (desvío %.3f°)"
				% [building.name, "GLB" if town_kind else "FBX", building.rotation.y,
				expected, rad_to_deg(drift)])
	print("  fachadas: %d GLB (frente a −X) + %d FBX (frente a −Z) · peor desvío %.3f m,"
			% [glb, fbx, worst_offset]
			+ " base %.4f m, giro %.4f° (topes %.2f / %.3f / %.1f)"
			% [worst_base, rad_to_deg(worst_yaw), FACADE_TOLERANCE, BASE_TOLERANCE,
			YAW_TOLERANCE_DEG])


## 5. Ningún cuerpo escalado; toda la variación de altura vive en la malla y en
## el `BoxShape3D` (`docs/03` prohíbe escalar cuerpos físicos).
func _check_no_body_scale() -> void:
	for building: Building in _town.get_buildings():
		if not building.scale.is_equal_approx(Vector3.ONE):
			fail("'%s' tiene el StaticBody3D escalado a %s" % [building.name, str(building.scale)])
			continue
		var box := building.intact_shape.shape as BoxShape3D
		if box == null:
			fail("'%s' no tiene BoxShape3D intacta" % building.name)
			continue
		expect_near(box.size.y, building.get_height(), 0.01,
				"'%s': la caja no refleja la altura" % building.name)
		expect_near(building.intact_shape.position.y, building.get_height() * 0.5, 0.01,
				"'%s': la caja no está centrada en la altura" % building.name)
		expect(building.collision_layer == PhysicsLayers.CITY,
				"'%s' está en la capa %d, esperada %d"
				% [building.name, building.collision_layer, PhysicsLayers.CITY])
	print("  cuerpos: %d StaticBody3D sin escalar, capa %d, caja a la altura real"
			% [_plan.destructible_count(), PhysicsLayers.CITY])


# --------------------------------------------------------------------------
# 6. La ruta
# --------------------------------------------------------------------------

## La ruta tiene calzada debajo en toda su longitud dentro del campo, del ancho
## que declara el plano, con vereda al costado dentro del pueblo y llegando a
## medio kilómetro del centro por los dos lados.
##
## Es el sub-check que defiende la lectura central del pueblo: lo primero que el
## jugador ve al aparecer es una ruta, y una ruta que se corta —o que tiene la
## calzada corrida dos metros del eje— deja el pueblo colgando de la nada.
##
## ## Qué cambió en WP-T4
##
## Hasta P2c la ruta de afuera del disco era una cadena de baldosas de 10 m en
## un [MultiMesh] y esta fila decodificaba su búfer instancia por instancia.
## Sobre relieve una baldosa plana no apoya (ver [constant CityGrid.ASPHALT_NODE]),
## así que ya no hay baldosas: la cinta cubre los 1 127 m y lo que se mide es la
## **malla**. En vez de buscar la instancia más cercana se pregunta si el punto
## tiene asfalto encima ([method RoadMesh.coverage_indexed]) y hasta dónde llega
## ese asfalto a lo ancho, que es más directo y además caza un ancho mal hecho
## en cualquier tramo, no sólo en la ruta.
func _check_route() -> void:
	var asphalt := _asphalt_mesh()
	if asphalt == null:
		fail("el pueblo no tiene la malla '%s' bajo '%s'"
				% [CityGrid.ASPHALT_NODE, CityGrid.STREETS_NODE])
		return
	var road := RoadMesh.flat_triangles(asphalt)
	var index := RoadMesh.index_triangles(road, INDEX_CELL)

	var half_field := _plan.field_size * 0.5
	var length := _plan.route_length()
	var half := _plan.route_width * 0.5
	var samples := 0
	var inside_samples := 0
	var gaps := 0
	var missing_shoulder := 0
	var worst_width := 0.0
	var worst_width_at := 0.0
	var distance := 0.0
	var walk := _walkway_mesh()
	var walk_triangles := RoadMesh.flat_triangles(walk) if walk != null else []
	var walk_index := RoadMesh.index_triangles(walk_triangles, INDEX_CELL)
	while distance <= length:
		var point := _plan.route_point(distance)
		var tangent := _plan.route_tangent(distance)
		var at := distance
		distance += ROUTE_SAMPLE_STEP
		if absf(point.x) > half_field or absf(point.z) > half_field:
			continue
		samples += 1
		if RoadMesh.coverage_indexed(road, index, INDEX_CELL,
				Vector2(point.x, point.z), COVER_MARGIN) == 0:
			gaps += 1
			continue
		# Medio ancho real de la calzada a cada lado del eje. En un cruce el
		# polígono del nodo agranda el asfalto a propósito, así que ahí no se
		# mide: lo que esta fila defiende es el ancho **entre** cruces.
		if _near_node(point):
			continue
		var side := TownPlan.left_of(tangent)
		for sign: float in [1.0, -1.0]:
			var reach := 0.0
			while reach < half + 1.0:
				var probe := point + side * (reach + ROUTE_WIDTH_STEP) * sign
				if RoadMesh.coverage_indexed(road, index, INDEX_CELL,
						Vector2(probe.x, probe.z), COVER_MARGIN) == 0:
					break
				reach += ROUTE_WIDTH_STEP
			if absf(reach - half) > worst_width:
				worst_width = absf(reach - half)
				worst_width_at = at

		if _plan.distance_to_centre(point) > _plan.block_radius:
			continue
		inside_samples += 1
		if walk == null:
			continue
		var found := false
		for sign: float in [1.0, -1.0]:
			var probe := point + side * (half + _plan.route_shoulder * 0.5) * sign
			if RoadMesh.coverage_indexed(walk_triangles, walk_index, INDEX_CELL,
					Vector2(probe.x, probe.z), COVER_MARGIN) > 0:
				found = true
		if not found:
			missing_shoulder += 1

	expect(samples > 400, "sólo %d muestras de ruta dentro del campo" % samples)
	expect(gaps == 0,
			"%d de %d muestras de la ruta no tienen calzada debajo" % [gaps, samples])
	expect(worst_width <= ROUTE_WIDTH_TOLERANCE,
			"la media franja de asfalto se desvía %.3f m de los %.2f m del plano a %.0f m"
			% [worst_width, half, worst_width_at] + " del origen, tope %.1f"
			% ROUTE_WIDTH_TOLERANCE)
	expect(missing_shoulder <= inside_samples / 4,
			"%d de %d muestras de ruta dentro del pueblo no tienen vereda al costado"
			% [missing_shoulder, inside_samples])

	# Medio kilómetro por los dos lados, medido desde el centro y con los dos
	# extremos en semiplanos opuestos: dos puntas del mismo lado no son una ruta
	# que atraviesa el pueblo, son un ramal.
	var first := _plan.route[0]
	var last := _plan.route[_plan.route.size() - 1]
	var tangent_centre := _plan.route_tangent(_plan.route_centre_distance())
	var reach_a := _plan.distance_to_centre(first)
	var reach_b := _plan.distance_to_centre(last)
	var side_a := (first - _plan.play_centre).dot(tangent_centre)
	var side_b := (last - _plan.play_centre).dot(tangent_centre)
	expect(reach_a >= ROUTE_REACH_MIN and reach_b >= ROUTE_REACH_MIN,
			"la ruta llega a %.0f m y %.0f m del centro, mínimo %.0f por lado"
			% [reach_a, reach_b, ROUTE_REACH_MIN])
	expect(side_a * side_b < 0.0,
			"las dos puntas de la ruta caen del mismo lado del pueblo (%.0f y %.0f)"
			% [side_a, side_b])
	print("  ruta: %d muestras cada %.0f m · asfalto debajo de todas · media franja"
			% [samples, ROUTE_SAMPLE_STEP]
			+ " %.2f m ±%.3f · vereda al lado en %d de %d muestras del pueblo · %.0f y %.0f m"
			% [half, worst_width, inside_samples - missing_shoulder, inside_samples,
			reach_a, reach_b] + " a cada lado")


## `true` si [param point] cae dentro del polígono de algún nodo del grafo, o a
## menos de dos metros de su borde.
func _near_node(point: Vector3) -> bool:
	for index: int in _plan.nodes.size():
		var poly := _plan.node_polygon(index)
		if poly.size() < 3:
			continue
		if TownPlan.polygon_inset(poly, Vector2(point.x, point.z)) > -2.0:
			return true
	return false


## La malla de asfalto del pueblo horneado.
func _asphalt_mesh() -> ArrayMesh:
	var streets := _town.get_node_or_null(NodePath(CityGrid.STREETS_NODE))
	if streets == null:
		return null
	var node := streets.get_node_or_null(NodePath(CityGrid.ASPHALT_NODE)) as MeshInstance3D
	return node.mesh as ArrayMesh if node != null else null


## La malla de veredas del pueblo horneado.
func _walkway_mesh() -> ArrayMesh:
	var streets := _town.get_node_or_null(NodePath(CityGrid.STREETS_NODE))
	if streets == null:
		return null
	var node := streets.get_node_or_null(NodePath(CityGrid.WALKWAYS_NODE)) as MeshInstance3D
	return node.mesh as ArrayMesh if node != null else null


# --------------------------------------------------------------------------
# 7. Red viaria
# --------------------------------------------------------------------------


## **Dos** [MeshInstance3D] y ni un [MultiMesh]: el reparto del viario de P2c.
##
## Eran cinco MultiMesh en P2b con 1 013 instancias. Son dos superficies porque
## un cruce no es un parche instanciable —es el polígono que queda entre las
## bocas de las calles que llegan— y porque, sobre relieve, una baldosa plana de
## diez metros no apoya (ver [constant CityGrid.ASPHALT_NODE]).
func _check_street_batching() -> void:
	var streets := _town.get_node_or_null(NodePath(CityGrid.STREETS_NODE))
	if streets == null:
		fail("el pueblo no tiene el nodo '%s'" % CityGrid.STREETS_NODE)
		return
	var surfaces := 0
	var multis := 0
	var bodies := 0
	var report: Array[String] = []
	for node: Node in _all_nodes(streets):
		if node is PhysicsBody3D:
			bodies += 1
		var mesh_node := node as MeshInstance3D
		if mesh_node != null:
			surfaces += 1
			expect(mesh_node.mesh != null, "'%s' no tiene malla" % mesh_node.name)
			expect(mesh_node.gi_mode == GeometryInstance3D.GI_MODE_STATIC,
					"'%s' no tiene gi_mode STATIC (`docs/13` §3.3)" % mesh_node.name)
			if mesh_node.mesh != null:
				report.append("%s %d tris" % [mesh_node.name,
						RoadMesh.triangle_count(mesh_node.mesh)])
			continue
		var multi := node as MultiMeshInstance3D
		if multi == null:
			continue
		multis += 1
		expect(multi.multimesh != null and multi.multimesh.instance_count > 0,
				"el MultiMesh '%s' está vacío" % multi.name)
		expect(multi.gi_mode == GeometryInstance3D.GI_MODE_STATIC,
				"el MultiMesh '%s' no tiene gi_mode STATIC" % multi.name)
		if multi.multimesh != null:
			report.append("%s %d instancias" % [multi.name, multi.multimesh.instance_count])

	expect(surfaces == 2, "el viario trae %d MeshInstance3D y tendría que traer 2 (%s y %s)"
			% [surfaces, CityGrid.ASPHALT_NODE, CityGrid.WALKWAYS_NODE])
	expect(multis == 0, "el viario trae %d MultiMesh y no tendría que traer ninguno"
			% multis)
	expect(bodies == 0, "la red viaria trae %d colisionadores propios" % bodies)

	var asphalt := streets.get_node_or_null(NodePath(CityGrid.ASPHALT_NODE)) as MeshInstance3D
	var walkways := streets.get_node_or_null(NodePath(CityGrid.WALKWAYS_NODE)) as MeshInstance3D
	if asphalt == null or walkways == null:
		fail("faltan '%s' o '%s' bajo '%s'" % [CityGrid.ASPHALT_NODE,
				CityGrid.WALKWAYS_NODE, CityGrid.STREETS_NODE])
		return
	# Las veredas no proyectan sombra: son una losa de quince centímetros a ras
	# del suelo y entrarían igual en cada cascada del sol.
	expect(walkways.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"'%s' proyecta sombra" % CityGrid.WALKWAYS_NODE)
	expect(asphalt.mesh != null and asphalt.mesh.get_surface_count() == 1,
			"'%s' tendría que tener una sola superficie" % CityGrid.ASPHALT_NODE)
	expect(walkways.mesh != null and walkways.mesh.get_surface_count() == 1,
			"'%s' tendría que tener una sola superficie" % CityGrid.WALKWAYS_NODE)
	var road_material := _surface_material(asphalt)
	var walk_material := _surface_material(walkways)
	expect(road_material != null and road_material.resource_path == ROADS_MATERIAL_PATH,
			"el asfalto usa '%s', se esperaba '%s'"
			% [road_material.resource_path if road_material != null else "nada",
			ROADS_MATERIAL_PATH])
	expect(walk_material != null and walk_material != road_material,
			"la vereda comparte material con la calzada: no se distinguirían")
	# Las dos mallas viajan en `.res` externos: con la geometría incrustada en
	# texto el pueblo se va del tope de 500 KB (plan §5.12).
	for node: MeshInstance3D in [asphalt, walkways]:
		expect(node.mesh != null and not node.mesh.resource_path.is_empty(),
				"'%s' lleva la malla incrustada en el .tscn en vez de un .res externo"
				% node.name)
	print("  calles: %s · 0 MultiMesh · 0 colisionadores" % " · ".join(report))


## Material de la superficie 0 de una [MeshInstance3D].
func _surface_material(node: MeshInstance3D) -> Material:
	if node == null or node.mesh == null or node.mesh.get_surface_count() == 0:
		return null
	var override := node.get_surface_override_material(0)
	return override if override != null else node.mesh.surface_get_material(0)


## Las cuatro filas de viario de P2c: cero z-fighting, cero cabos sueltos,
## cruces por nodo y veredas continuas con cordón.
##
## Miden la **escena horneada**. La prueba de que miden algo no depende de ese
## horneado: [method _check_road_negative] corre la misma rutina sobre un viario
## sintético sano y sobre tres rotos a mano.
func _check_road_surfaces() -> void:
	var asphalt := _asphalt_mesh()
	var walkways := _walkway_mesh()
	if asphalt == null or walkways == null:
		fail("faltan las mallas de viario bajo '%s'" % CityGrid.STREETS_NODE)
		return
	expect(_plan.has_graph(), "el plano horneado no trae grafo de calles")
	_measure_roads("horneado", _plan, asphalt, walkways)


## Corre las cuatro filas de viario sobre [param plan] y sus dos mallas.
func _measure_roads(label: String, plan: TownPlan, asphalt: ArrayMesh,
		walkways: ArrayMesh) -> void:
	for problem: String in _road_problems(plan, asphalt, walkways,
			_town.terrain_height_fn()):
		fail("viario %s: %s" % [label, problem])
	for problem: String in plan.graph_problems():
		fail("grafo %s: %s" % [label, problem])
	var crossings := 0
	var stubs := 0
	for index: int in plan.nodes.size():
		if plan.node_polygon(index).size() >= 3:
			crossings += 1
		else:
			stubs += 1
	print("  viario %s: %d nodos (%d cruces con polígono, %d cabos), %d triángulos de"
			% [label, plan.nodes.size(), crossings, stubs,
			RoadMesh.triangle_count(asphalt)]
			+ " asfalto y %d de vereda · borde de calzada cada %.0f m sin coplanares ·"
			% [RoadMesh.triangle_count(walkways), EDGE_STEP]
			+ " cordón de %.2f m" % CURB_HEIGHT)


## Los incumplimientos del viario de [param plan] contra sus dos mallas, como
## lista de mensajes. Vacía quiere decir «viario sano».
##
## Va aparte de la fila —mismo patrón que [method _play_circle_problems] y que
## `town_plan_check._parcel_problems()`— para que la prueba negativa corra
## **esta misma rutina** sobre un viario roto a mano. Si no, la negativa
## comprobaría que la geometría funciona, no que el check mire.
func _road_problems(plan: TownPlan, asphalt: ArrayMesh, walkways: ArrayMesh,
		height: Callable = Callable()) -> Array[String]:
	var found: Array[String] = []
	if asphalt == null:
		found.append("el viario no tiene asfalto")
		return found
	var road := RoadMesh.flat_triangles(asphalt)
	var road_index := RoadMesh.index_triangles(road, INDEX_CELL)
	var walk := RoadMesh.flat_triangles(walkways) if walkways != null else []
	var walk_index := RoadMesh.index_triangles(walk, INDEX_CELL)

	# 1. Cero z-fighting: el borde de la calzada tiene asfalto debajo, una sola
	#    capa, y a una altura que el depth buffer puede ordenar.
	var gaps := 0
	var overlaps := 0
	var worst_clearance := INF
	var highest_clearance := -INF
	var worst_at := Vector3.ZERO
	var highest_at := Vector3.ZERO
	var worst_street := -1
	var highest_street := -1
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		if axis.size() < 2:
			continue
		var reach := plan.street_width_of(street) * 0.5 - EDGE_INSET
		if reach <= 0.0:
			continue
		var span := TownPlan.polyline_length(axis)
		var at := 0.0
		while at <= span:
			var point := TownPlan.polyline_point(axis, at)
			var tangent := TownPlan.polyline_tangent(axis, at)
			at += EDGE_STEP
			if plan.distance_to_centre(point) > plan.block_radius:
				continue
			for side: float in [1.0, -1.0]:
				var edge := point + TownPlan.left_of(tangent) * reach * side
				var flat := Vector2(edge.x, edge.z)
				if RoadMesh.coverage_indexed(road, road_index, INDEX_CELL, flat,
						COVER_MARGIN) == 0:
					gaps += 1
					continue
				if RoadMesh.coverage_indexed(road, road_index, INDEX_CELL, flat,
						OVERLAP_MARGIN) > 1:
					overlaps += 1
				var surface := RoadMesh.surface_y_indexed(road, road_index, INDEX_CELL, flat)
				if not is_finite(surface):
					continue
				var ground := 0.0 if height.is_null() or not height.is_valid() \
						else float(height.call(edge.x, edge.z))
				var clearance := surface - ground
				if clearance < worst_clearance:
					worst_clearance = clearance
					worst_at = edge
					worst_street = street
				if clearance > highest_clearance:
					highest_clearance = clearance
					highest_at = edge
					highest_street = street
	if gaps > 0:
		found.append("%d muestras del borde de calzada no tienen asfalto debajo" % gaps)
	if overlaps > 0:
		found.append("%d muestras del borde de calzada tienen dos asfaltos coplanares" % overlaps)
	if is_finite(worst_clearance) and worst_clearance < ASPHALT_CLEARANCE_MIN:
		found.append("el asfalto llega a %.4f m del terreno en la calle %d, en (%.1f, %.1f);"
				% [worst_clearance, worst_street, worst_at.x, worst_at.z]
				+ " mínimo %.2f" % ASPHALT_CLEARANCE_MIN)
	if is_finite(highest_clearance) and highest_clearance > ASPHALT_CLEARANCE_MAX:
		found.append("el asfalto flota %.4f m sobre el terreno en la calle %d, en (%.1f, %.1f);"
				% [highest_clearance, highest_street, highest_at.x, highest_at.z]
				+ " máximo %.2f" % ASPHALT_CLEARANCE_MAX)

	# 2. Cero cabos sueltos y 3. cruces por nodo.
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		if axis.size() < 2:
			continue
		for end: int in 2:
			var node := plan.node_of(street, end)
			var tip := axis[0] if end == 0 else axis[axis.size() - 1]
			if node < 0:
				continue
			# Un nodo de grado uno es la punta de un acceso: no tiene cruce que
			# dibujar, tiene un cierre. Exigirle polígono sería exigirle asfalto
			# a una tranquera.
			var degree: PackedInt32Array = plan.node_at(node).get("streets",
					PackedInt32Array())
			var poly := plan.node_polygon(node)
			if poly.size() < 3:
				if degree.size() >= 2:
					found.append("la calle %d llega al nodo %d, de grado %d, que no tiene"
							% [street, node, degree.size()] + " polígono")
				continue
			if TownPlan.polygon_inset(poly, Vector2(tip.x, tip.z)) < -STUB_TOLERANCE:
				found.append("la punta %s de la calle %d queda fuera del polígono del nodo %d"
						% ["a" if end == 0 else "b", street, node])
	for index: int in plan.nodes.size():
		var node := plan.node_at(index)
		var incident: PackedInt32Array = node.get("streets", PackedInt32Array())
		if incident.size() < 2:
			continue
		var poly := plan.node_polygon(index)
		if poly.size() < 3:
			found.append("el nodo %d tiene grado %d y no tiene polígono de cruce"
					% [index, incident.size()])
			continue
		var centre := node.get("pos", Vector3.ZERO) as Vector3
		if RoadMesh.coverage_indexed(road, road_index, INDEX_CELL,
				Vector2(centre.x, centre.z), COVER_MARGIN) == 0:
			found.append("el cruce del nodo %d no tiene asfalto en su centro" % index)

	# 4. Veredas continuas con cordón, sólo donde hay calle.
	if walkways != null:
		found.append_array(_walkway_problems(plan, walkways, walk, walk_index,
				road, road_index, height))
	return found


## Altura del terreno en [param point], o `0` sin función de altura.
func _ground_at(height: Callable, point: Vector2) -> float:
	if height.is_null() or not height.is_valid():
		return 0.0
	return float(height.call(point.x, point.y))


## Los incumplimientos de los anillos de vereda.
func _walkway_problems(plan: TownPlan, mesh: ArrayMesh, triangles: Array[Dictionary],
		grid: Dictionary, road: Array[Dictionary], road_grid: Dictionary,
		height: Callable = Callable()) -> Array[String]:
	var found: Array[String] = []

	# El cordón se mide de dos maneras, y las dos hacen falta.
	#
	# La primera cuenta las caras **verticales** de la altura del cordón: es la
	# que sabe si el cordón está modelado. No se puede exigir que *todas* las
	# caras verticales midan lo mismo, porque en la misma malla viajan los
	# cierres de cabo —postes de 1,40 m, alambres de 5 cm—, y una tranquera no
	# es un cordón mal hecho.
	var faces := 0
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
			var normal := (b - a).cross(c - a)
			if normal.length() < 0.000001 or absf(normal.normalized().y) > 0.1:
				continue
			var top := maxf(a.y, maxf(b.y, c.y))
			var bottom := minf(a.y, minf(b.y, c.y))
			if absf((top - bottom) - CURB_HEIGHT) > CURB_TOLERANCE:
				continue
			faces += 1
	if faces == 0:
		found.append("la vereda no tiene ni una cara vertical de %.2f m: no hay cordón"
				% CURB_HEIGHT)

	# La segunda mide el **escalón** que ve el jugador: la vereda contra la
	# calzada, a los dos lados del cordón. Las dos alturas se miden **contra el
	# terreno de su propio punto** y no una contra la otra: los dos puntos están
	# a cuarenta centímetros y, con el peralte que el relieve le da a una calle,
	# esos cuarenta centímetros valen tres centímetros de cota —tres veces la
	# tolerancia del cordón— y la fila salía en rojo con un cordón perfecto.
	var worst_step := 0.0
	var steps := 0

	# Continuidad: se recorre la línea de cordón de cada lado con calle y se
	# mide el tramo más largo sin vereda encima.
	var worst := 0.0
	var worst_block := -1
	var covered := 0
	var probed := 0
	for block: int in plan.block_count():
		var ring := plan.block_ring(block)
		if ring.size() < 3 or block >= plan.block_streets.size():
			continue
		var sides := plan.block_streets[block]
		var winding := 1.0 if TownPlan.polygon_signed_area(ring) >= 0.0 else -1.0
		for side: int in mini(sides.size(), ring.size()):
			if sides[side] < 0:
				continue
			var walk := plan.street_sidewalk_of(sides[side])
			if walk <= 0.0:
				continue
			var from := ring[side]
			var to := ring[(side + 1) % ring.size()]
			var delta := to - from
			var length := delta.length()
			if length < RING_STEP:
				continue
			var outward := Vector2(delta.y, -delta.x) / length * winding
			# El escalón se mide en el medio del lado, lejos de las esquinas.
			var middle := from + delta * 0.5
			var walk_y := RoadMesh.surface_y_indexed(triangles, grid, INDEX_CELL,
					middle + outward * (walk - 0.05))
			var road_y := RoadMesh.surface_y_indexed(road, road_grid, INDEX_CELL,
					middle + outward * (walk + 0.35))
			if is_finite(walk_y) and is_finite(road_y):
				steps += 1
				var walk_at := middle + outward * (walk - 0.05)
				var road_at := middle + outward * (walk + 0.35)
				var over_walk := walk_y - _ground_at(height, walk_at)
				var over_road := road_y - _ground_at(height, road_at)
				worst_step = maxf(worst_step, absf(over_walk - over_road - CURB_HEIGHT))
			var run := 0.0
			var travelled := RING_STEP
			while travelled < length:
				# La muestra va a media franja de vereda, que es donde el anillo
				# tiene que estar sí o sí, y no sobre su borde.
				var point := from + delta * (travelled / length) + outward * (walk * 0.5)
				travelled += RING_STEP
				probed += 1
				if RoadMesh.coverage_indexed(triangles, grid, INDEX_CELL, point,
						COVER_MARGIN) > 0:
					covered += 1
					run = 0.0
					continue
				run += RING_STEP
				if run > worst:
					worst = run
					worst_block = block
	if steps > 0 and worst_step > CURB_TOLERANCE:
		found.append("el escalón de la vereda sobre la calzada se desvía %.3f m de los"
				% worst_step + " %.2f del cordón" % CURB_HEIGHT)
	if worst > RING_GAP_MAX:
		found.append("el anillo de la manzana %d tiene un hueco de %.3f m, máximo %.2f"
				% [worst_block, worst, RING_GAP_MAX])
	if probed > 0 and covered == 0:
		found.append("ninguna de las %d muestras de vereda encontró anillo" % probed)
	return found


## Prueba negativa del viario: las filas se corren sobre un viario sintético
## sano y sobre el mismo viario con una cinta corrida cinco centímetros.
##
## Existe porque las cuatro filas de arriba se saltean mientras `town_a.tscn`
## sea el de P2b, y una fila que no corre nunca no se distingue de una fila que
## siempre pasa. Con esto se verifica **hoy** que la rutina mide: el viario sano
## no tiene incumplimientos y el corrido sí, con el mensaje del solape.
func _check_road_negative() -> void:
	var plan := _synthetic_plan()
	var height := Callable()
	var walkways := RoadMesh.ring(plan.block_ring(0), plan.block_streets[0], 0.0, 3.0,
			CityGrid.SIDEWALK_TOP, RoadMesh.CURB, height)
	var pieces: Array = []
	for street: int in plan.graph_street_count():
		var axis := plan.street_axis(street)
		var cuts: Array[Dictionary] = [{
			"at": TownPlan.polyline_closest(axis, plan.nodes[0].get("pos", Vector3.ZERO)),
			"radius": plan.node_radius(0),
		}]
		for slice: PackedVector3Array in RoadMesh.clip_ribbon_at_nodes(axis, cuts,
				plan.street_stub_of(street, 0), plan.street_stub_of(street, 1)):
			pieces.append(RoadMesh.ribbon(slice, plan.street_width_of(street) * 0.5,
					height, CityGrid.ROAD_TOP))
	pieces.append(RoadMesh.polygon_mesh(plan.node_polygon(0), height, CityGrid.ROAD_TOP))
	var asphalt := RoadMesh.merge(pieces)

	var clean := _road_problems(plan, asphalt, walkways)
	expect(clean.is_empty(), "el viario sintético sano ya trae incumplimientos: %s"
			% ", ".join(clean))
	expect(_plan_graph_ok(plan), "el grafo sintético sano ya trae incumplimientos: %s"
			% ", ".join(plan.graph_problems()))

	# La cinta corrida cinco centímetros deja dos asfaltos coplanares encima del
	# mismo borde: es exactamente el z-fighting de P2b.
	var doubled := RoadMesh.merge([asphalt,
			_shifted(asphalt, Vector3(ZFIGHT_SHIFT, 0.0, ZFIGHT_SHIFT))])
	var broken := _road_problems(plan, doubled, walkways)
	print("  viario sintético: %d triángulos sanos, %d con la cinta corrida"
			% [RoadMesh.triangle_count(asphalt), RoadMesh.triangle_count(doubled)])
	expect(_has_road_problem(broken, "coplanares"),
			"prueba negativa: _road_problems() aprobó una cinta corrida %.2f m" % ZFIGHT_SHIFT)

	# Y una vereda sin cordón tiene que saltar por el lado del cordón.
	var flat_walk := RoadMesh.ring(plan.block_ring(0), plan.block_streets[0], 0.0, 3.0,
			CityGrid.SIDEWALK_TOP, 0.0, height)
	var no_curb := _road_problems(plan, asphalt, flat_walk)
	expect(_has_road_problem(no_curb, "cordón"),
			"prueba negativa: _road_problems() aprobó una vereda sin cordón")
	# Y una vereda apoyada a la altura de la calzada tiene que saltar por el
	# escalón, aunque su cara vertical mida bien.
	var sunken := RoadMesh.ring(plan.block_ring(0), plan.block_streets[0], 0.0, 3.0,
			CityGrid.ROAD_TOP + RoadMesh.CURB * 0.5, RoadMesh.CURB, Callable())
	expect(_has_road_problem(_road_problems(plan, asphalt, sunken), "escalón"),
			"prueba negativa: _road_problems() aprobó una vereda hundida media altura")
	print("  viario negativo: corrida %.2f m → %s · sin cordón → %s"
			% [ZFIGHT_SHIFT, "; ".join(broken), "; ".join(no_curb)])


## Un plano mínimo con grafo: dos calles que se cruzan en un nodo a 68° y una
## manzana con frente a las dos. No sale de ningún horneado: se arma acá para
## que la prueba negativa no dependa de que el pueblo esté al día.
func _synthetic_plan() -> TownPlan:
	var plan := TownPlan.new()
	plan.play_centre = Vector3.ZERO
	plan.play_radius = 140.0
	plan.block_radius = 150.0
	plan.field_size = 600.0
	# La ruta llega más allá del disco de manzanas: una punta que se va del
	# pueblo no es un cabo y no necesita cierre.
	plan.route = PackedVector3Array([Vector3(-220.0, 0.0, 0.0), Vector3(220.0, 0.0, 0.0)])
	plan.route_width = 10.0
	plan.route_shoulder = 3.0
	var angle := deg_to_rad(68.0)
	plan.streets = [PackedVector3Array([Vector3.ZERO,
			Vector3(cos(angle), 0.0, sin(angle)) * 80.0])]
	plan.street_widths = PackedFloat32Array([9.0])
	plan.street_sidewalks = PackedFloat32Array([3.0])
	plan.street_nodes = PackedInt32Array([-1, -1, 0, -1])
	plan.street_stubs = PackedFloat32Array([0.0, 0.0, 0.0, 6.0])
	plan.street_kind = PackedInt32Array([TownPlan.StreetKind.ROUTE,
			TownPlan.StreetKind.STREET])
	plan.street_closures = PackedStringArray(["", "a:none;b:gate"])
	plan.nodes = [{
		"pos": Vector3.ZERO, "streets": PackedInt32Array(),
		"angles": PackedFloat32Array(), "half_widths": PackedFloat32Array(),
		"poly": PackedVector2Array(), "radius": 0.0,
	}]
	plan.refresh_nodes()

	# Una manzana en la cuña entre las dos calles, con frente a las dos. La
	# esquina es el **corte de las dos líneas municipales**, no un largo fijo:
	# con la calle a 68° un largo fijo dejaría la vereda lejos del cordón, que es
	# justo lo que la fila mide.
	var along := Vector2(cos(angle), sin(angle))
	var perp := Vector2(along.y, -along.x)
	var municipal := plan.street_half_of(0)
	var lateral := plan.street_half_of(1)
	var reach := (municipal - perp.y * lateral) / along.y
	var corner := along * reach + perp * lateral
	plan.blocks = [PackedVector2Array([
		corner, corner + Vector2(46.0, 0.0),
		corner + Vector2(46.0, 0.0) + along * 40.0, corner + along * 40.0])]
	plan.block_streets = [PackedInt32Array([0, -1, -1, 1])]
	plan.block_rings = [plan.blocks[0]]
	plan.block_datum = PackedFloat32Array([0.0])
	return plan


## `true` si el grafo de [param plan] no tiene incumplimientos.
func _plan_graph_ok(plan: TownPlan) -> bool:
	return plan.graph_problems().is_empty()


## Copia de [param mesh] con todos sus vértices corridos [param offset].
func _shifted(mesh: ArrayMesh, offset: Vector3) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		moved.resize(vertices.size())
		for index: int in vertices.size():
			moved[index] = vertices[index] + offset
		arrays[Mesh.ARRAY_VERTEX] = moved
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(surface, mesh.surface_get_material(surface))
	return out


## `true` si alguno de los mensajes menciona [param needle].
func _has_road_problem(problems: Array[String], needle: String) -> bool:
	for problem: String in problems:
		if problem.contains(needle):
			return true
	return false


# --------------------------------------------------------------------------
# 8. Campo y rocas
# --------------------------------------------------------------------------

## Rocas del borde y caja de suelo.
##
## El suelo del pueblo es **campo**, no asfalto: su material no puede ser el de
## la calzada. Es la diferencia de lectura que separa un pueblo de ruta de un
## barrio, y la única forma de que salte si alguien reasigna `ground_material`
## por comodidad.
func _check_field_and_rocks() -> void:
	var rocks := _town.get_rocks()
	expect(rocks.size() == _plan.rock_spots().size(),
			"rocas: %d, el plano dice %d" % [rocks.size(), _plan.rock_spots().size()])
	expect(get_tree().get_nodes_in_group(&"city_rocks").size() == rocks.size(),
			"las rocas de 'Decor/Rocks' (%d) y las del grupo 'city_rocks' (%d) no coinciden"
			% [rocks.size(), get_tree().get_nodes_in_group(&"city_rocks").size()])
	var worst_angle := 180.0
	var nearest := INF
	for node: Node3D in rocks:
		var body := node as StaticBody3D
		if body == null:
			fail("'%s' del grupo city_rocks no es un StaticBody3D" % node.name)
			continue
		expect(body.collision_layer == PhysicsLayers.WORLD,
				"la roca '%s' está en la capa %d, esperada %d"
				% [body.name, body.collision_layer, PhysicsLayers.WORLD])
		var distance := _plan.distance_to_centre(body.position)
		nearest = minf(nearest, distance)
		expect(distance > _plan.play_radius,
				"la roca '%s' cae a %.1f m del centro, dentro del círculo de %.0f m"
				% [body.name, distance, _plan.play_radius])
		var angle := _town.spawn_cone_angle(body.position)
		worst_angle = minf(worst_angle, angle)
		expect(angle >= ROCK_CONE_DEG,
				"la roca '%s' está a %.1f° del eje de aparición del dron, mínimo %.0f°"
				% [body.name, angle, ROCK_CONE_DEG])

	var ground := _town.get_node_or_null(NodePath(CityGrid.GROUND_NODE)) as StaticBody3D
	if ground == null:
		fail("el pueblo no tiene el suelo '%s'" % CityGrid.GROUND_NODE)
		return
	expect(ground.collision_layer == PhysicsLayers.WORLD,
			"el suelo está en la capa %d, esperada %d"
			% [ground.collision_layer, PhysicsLayers.WORLD])
	expect(ground.collision_mask == CityGrid.GROUND_MASK,
			"el suelo tiene la máscara %d, esperada %d"
			% [ground.collision_mask, CityGrid.GROUND_MASK])

	# El relieve: un `HeightMapShape3D` en el origen y **sin escalar**. Escalar
	# un heightfield hace que Jolt lo descarte y caiga a una malla de colisión,
	# que cuesta un orden de magnitud más (`docs/03`).
	var shape_node := ground.get_node_or_null(^"Shape") as CollisionShape3D
	var height_shape := shape_node.shape as HeightMapShape3D if shape_node != null else null
	if height_shape == null:
		fail("el suelo no trae el HeightMapShape3D del relieve")
		return
	expect(shape_node.position.is_equal_approx(Vector3.ZERO),
			"la forma del relieve está en %s y tiene que estar en el origen"
			% str(shape_node.position))
	expect(shape_node.scale.is_equal_approx(Vector3.ONE),
			"la forma del relieve está escalada a %s" % str(shape_node.scale))
	expect(ground.scale.is_equal_approx(Vector3.ONE),
			"el cuerpo del suelo está escalado a %s" % str(ground.scale))
	var terrain := _terrain()
	if terrain != null:
		expect(height_shape.map_width == terrain.size
				and height_shape.map_depth == terrain.size,
				"la forma es %d × %d y la rejilla %d²"
				% [height_shape.map_width, height_shape.map_depth, terrain.size])

	# El anillo de cajas que cubre del borde del heightfield al borde del campo,
	# y la caja de seguridad, que va **debajo del lecho del arroyo**.
	var ring := 0
	var ring_top := -INF
	var reach := 0.0
	var safety_top := INF
	for child: Node in ground.get_children():
		var node := child as CollisionShape3D
		var box := node.shape as BoxShape3D if node != null else null
		if box == null:
			continue
		var top := node.position.y + box.size.y * 0.5
		if node.name == "Safety":
			safety_top = top
			continue
		ring += 1
		ring_top = maxf(ring_top, top)
		reach = maxf(reach, maxf(absf(node.position.x) + box.size.x * 0.5,
				absf(node.position.z) + box.size.z * 0.5))
	expect(ring == 4, "el anillo del suelo tiene %d cajas, esperadas 4" % ring)
	expect(absf(ring_top) <= 0.01,
			"la cara superior del anillo está en y = %.3f y el relieve muere en 0" % ring_top)
	expect(reach >= _plan.field_size * 0.5 - 0.01,
			"el suelo llega a %.0f m del centro y el campo mide %.0f m de lado"
			% [reach, _plan.field_size])
	var lowest := terrain.range_of().x if terrain != null else 0.0
	expect(is_finite(safety_top) and safety_top <= lowest,
			"la caja de seguridad tiene la cara superior en %.2f m y el punto más bajo del"
			% safety_top + " relieve está en %.2f m: asomaría por el lecho del arroyo" % lowest)

	# Las cuatro mallas del relieve, en el origen y sin sombra propia.
	var chunks := 0
	for index: int in CityGrid.TERRAIN_CHUNKS:
		var chunk := ground.get_node_or_null(NodePath("Chunk%d" % index)) as MeshInstance3D
		if chunk == null or chunk.mesh == null:
			fail("falta la malla de relieve 'Chunk%d'" % index)
			continue
		chunks += 1
		expect(chunk.transform.is_equal_approx(Transform3D.IDENTITY),
				"'Chunk%d' no está en el origen: sus vértices ya vienen en coordenadas"
				% index + " del distrito")
		expect(chunk.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"'Chunk%d' proyecta sombra" % index)
		expect(chunk.gi_mode == GeometryInstance3D.GI_MODE_STATIC,
				"'Chunk%d' no tiene gi_mode STATIC" % index)
		expect(not chunk.mesh.resource_path.is_empty(),
				"'Chunk%d' lleva la malla incrustada en el .tscn" % index)

	var field := ground.get_node_or_null(^"Field") as MeshInstance3D
	var material: Material = null
	if field != null and field.mesh != null:
		material = field.get_active_material(0)
		if material == null:
			material = field.mesh.surface_get_material(0)
	expect(field != null and field.mesh != null, "el pueblo no tiene campo lejano 'Field'")
	expect(material != null, "el campo lejano no tiene material")
	if material != null:
		expect(material.resource_path != ROADS_MATERIAL_PATH,
				"el campo usa el material de la calzada ('%s'): se leería como asfalto"
				% ROADS_MATERIAL_PATH)
	print("  suelo: heightfield %d² en el origen · %d cajas de anillo a y = %.2f hasta %.0f m"
			% [height_shape.map_width, ring, ring_top, reach]
			+ " · seguridad a %.1f m (mínimo del relieve %.2f) · %d chunks · campo '%s'"
			% [safety_top, lowest, chunks,
			material.resource_path.get_file() if material != null else "?"])
	print("  rocas: %d de %.0f m para afuera, la más metida en el eje del dron a %.1f°"
			% [rocks.size(), nearest, worst_angle])


## El relieve que viaja con el pueblo horneado, o `null`.
func _terrain() -> TownTerrain:
	return _town.terrain as TownTerrain if _town != null else null


# --------------------------------------------------------------------------
# 8b. El relieve debajo de todo (P2c, WP-T4)
# --------------------------------------------------------------------------

## Radio a partir del cual el relieve vale cero exacto: el final del
## desvanecido que declara el spec del terreno (`fade [230, 256]`).
const TERRAIN_FADE_RADIUS: float = 256.0


## Casas apoyadas: las cuatro esquinas de cada huella, destructible o
## decorativa, contra la altura del terreno bajo ellas.
##
## Es el criterio 6 del plan y la fila que cierra la cadena que empieza en
## `tools/build_terrain.gd`: el horneado deja plana la manzana de cada casa del
## pueblo y un pad debajo de cada casa de caserío, y acá se comprueba que la
## huella que el plano declara apoye de verdad en las cuatro esquinas. Una casa
## con una esquina enterrada veinte centímetros y la opuesta en el aire es lo
## que el ojo lee como «esto lo puso un generador».
##
## La cota de apoyo no es una constante: es `base_y` menos el espesor de la
## vereda para las del pueblo —que apoyan sobre la losa— y `base_y` pelado para
## las de caserío, que apoyan sobre el pasto.
func _check_houses_rest() -> void:
	var terrain := _terrain()
	if terrain == null:
		fail("el pueblo horneado no trae relieve: no se puede medir el apoyo")
		return
	for problem: String in _rest_problems(terrain):
		fail("apoyo: %s" % problem)
	var worst := 0.0
	var worst_name := ""
	var counted := 0
	for index: int in _plan.parcels.size():
		var parcel := _plan.parcels[index]
		var ground := _rest_y(parcel)
		for corner: Vector2 in _plan.parcel_footprint(index):
			var delta := absf(terrain.height_at(corner.x, corner.y) - ground)
			if delta > worst:
				worst = delta
				worst_name = String(parcel.get("name", "?"))
		counted += 1
	print("  apoyo: %d huellas x 4 esquinas contra el relieve · peor desvío %.1f mm (%s),"
			% [counted, worst * 1000.0, worst_name]
			+ " tope %.0f mm" % (REST_TOLERANCE * 1000.0))


## Cota sobre la que apoya la parcela [param parcel]: el terreno que tiene que
## haber bajo sus cuatro esquinas.
func _rest_y(parcel: Dictionary) -> float:
	var base := float(parcel.get("base_y", TownPlan.SIDEWALK_TOP))
	if int(parcel.get("role", -1)) == TownPlan.Role.DECOR:
		return base
	return base - TownPlan.SIDEWALK_TOP


## Los incumplimientos del apoyo, como lista de mensajes. Va aparte para que la
## negativa corra **esta misma rutina** sobre un relieve movido a mano.
func _rest_problems(terrain: TownTerrain) -> Array[String]:
	var found: Array[String] = []
	for index: int in _plan.parcels.size():
		var parcel := _plan.parcels[index]
		var ground := _rest_y(parcel)
		for corner: Vector2 in _plan.parcel_footprint(index):
			var delta := terrain.height_at(corner.x, corner.y) - ground
			if absf(delta) > REST_TOLERANCE:
				found.append("'%s' tiene una esquina a %.3f m de su cota de apoyo (%.3f)"
						% [parcel.get("name", "?"), delta, ground])
				break
	return found


## El campo lejano no asoma por encima del relieve, y la junta entre los dos no
## tiene escalón.
##
## Hasta P2b el suelo visible era un `PlaneMesh` de 1 200 m a `y = 0` debajo de
## todo. Con relieve encima eso se rompe: el arroyo baja a −5,5 m, así que el
## plano asomaría por el medio del cauce como una lámina gris. La fila muestrea
## [constant FAR_FIELD_SAMPLES] puntos del disco del pueblo y exige que ningún
## triángulo de campo lejano quede por encima del terreno; después recorre la
## junta comprobando que ahí el relieve valga cero.
func _check_far_field() -> void:
	var terrain := _terrain()
	var ground := _town.get_node_or_null(NodePath(CityGrid.GROUND_NODE))
	var field := ground.get_node_or_null(^"Field") as MeshInstance3D if ground != null else null
	if terrain == null or field == null or field.mesh == null:
		fail("no hay relieve o campo lejano que medir")
		return
	for problem: String in _far_field_problems(terrain, field.mesh as ArrayMesh):
		fail("campo lejano: %s" % problem)

	var seam := 0.0
	for step: int in SEAM_SAMPLES:
		var angle := TAU * float(step) / float(SEAM_SAMPLES)
		var offset := Vector2(cos(angle), sin(angle)) * TERRAIN_FADE_RADIUS
		seam = maxf(seam, absf(terrain.height_at(
				_plan.play_centre.x + offset.x, _plan.play_centre.z + offset.y)))
	expect(seam <= SEAM_TOLERANCE,
			"en la junta (r = %.0f m) el relieve vale %.4f m y el campo lejano está en 0:"
			% [TERRAIN_FADE_RADIUS, seam] + " habría un escalón de %.0f mm" % (seam * 1000.0))
	print("  campo lejano: %d muestras dentro de r = %.0f m sin campo por encima del relieve"
			% [FAR_FIELD_SAMPLES, TERRAIN_FADE_RADIUS]
			+ " · junta a %.1f mm de cero (tope %.0f)"
			% [seam * 1000.0, SEAM_TOLERANCE * 1000.0])


## Los incumplimientos del campo lejano. Aparte, para la negativa.
func _far_field_problems(terrain: TownTerrain, mesh: ArrayMesh) -> Array[String]:
	var found: Array[String] = []
	var triangles := RoadMesh.flat_triangles(mesh)
	var index := RoadMesh.index_triangles(triangles, INDEX_CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = FAR_FIELD_SEED
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var hits := 0
	for _slot: int in FAR_FIELD_SAMPLES:
		# Muestreo uniforme sobre el disco: la raíz del radio, o se apelotona
		# todo en el centro y el arroyo —que está en el borde— no se mide.
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * TERRAIN_FADE_RADIUS
		var p := Vector2(_plan.play_centre.x + cos(angle) * radius,
				_plan.play_centre.z + sin(angle) * radius)
		if RoadMesh.coverage_indexed(triangles, index, INDEX_CELL, p, COVER_MARGIN) == 0:
			continue
		var surface := RoadMesh.surface_y_indexed(triangles, index, INDEX_CELL, p)
		if not is_finite(surface):
			continue
		var above := surface - terrain.height_at(p.x, p.y)
		if above <= 0.0:
			continue
		hits += 1
		if above > worst:
			worst = above
			worst_at = p
	if hits > 0:
		found.append("%d de %d muestras tienen campo lejano por encima del relieve (hasta"
				% [hits, FAR_FIELD_SAMPLES]
				+ " %.2f m en (%.0f, %.0f))" % [worst, worst_at.x, worst_at.y])
	return found


## Los marcadores apoyan sobre el relieve con la holgura que el plano declara.
##
## El plano no sabe de relieve: su `y` dice **cuánto por encima del suelo** va
## cada cosa —una aparición a ras, el dron a 1,5 m, un puesto de pila a 4,8—, y
## [method CityGrid.on_terrain] le suma el suelo al sembrarla. Esta fila
## comprueba justamente esa suma, que es lo que separa un marcador puesto sobre
## una loma de uno enterrado en ella.
func _check_ground_markers() -> void:
	var terrain := _terrain()
	if terrain == null:
		fail("el pueblo horneado no trae relieve: no se pueden medir los marcadores")
		return
	var worst := 0.0
	var worst_name := ""
	var counted := 0
	for entry: Array in _ground_markers():
		var node: Node3D = entry[0]
		var lift: float = entry[1]
		var wanted := terrain.height_at(node.position.x, node.position.z) + lift
		var delta := absf(node.position.y - wanted)
		counted += 1
		if delta > worst:
			worst = delta
			worst_name = node.name
		expect(delta <= GROUND_MARKER_TOLERANCE,
				"'%s' está en y = %.3f y el relieve más su holgura de %.2f m piden %.3f"
				% [node.name, node.position.y, lift, wanted])
	print("  marcadores sobre el relieve: %d medidos · peor desvío %.1f mm (%s), tope %.0f mm"
			% [counted, worst * 1000.0, worst_name, GROUND_MARKER_TOLERANCE * 1000.0])


## Los marcadores que tienen que apoyar en el relieve, con la holgura que el
## plano les da. Los puestos de azotea quedan afuera: los afina
## [method CityGrid._refined_post] con la altura real del edificio y los mide
## [method _check_markers].
func _ground_markers() -> Array[Array]:
	var found: Array[Array] = []
	var spawns := _town.get_node_or_null(NodePath(CityGrid.SPAWNS_NODE))
	if spawns != null:
		for index: int in _plan.spawn_points().size():
			var marker := spawns.get_node_or_null(NodePath("EnemySpawn%d" % index)) as Marker3D
			if marker != null:
				found.append([marker, _plan.spawn_points()[index].origin.y])
	var posts := _town.get_node_or_null(NodePath(CityGrid.POSTS_NODE))
	if posts != null:
		for index: int in _plan.battery_posts().size():
			if index < _plan.battery_roof_parcels.size() \
					and _plan.battery_roof_parcels[index] >= 0:
				continue
			var post := posts.get_node_or_null(NodePath("Post%d" % index)) as Marker3D
			if post != null:
				found.append([post, _plan.battery_posts()[index].y])
	for entry: Array in [[CityGrid.DRONE_NODE, _plan.drone_spawn().origin.y],
			[CityGrid.CAMERA_NODE, _plan.camera_fixed().origin.y],
			[CityGrid.CENTRE_NODE, _plan.play_centre.y]]:
		var node := _town.get_node_or_null(NodePath(entry[0])) as Marker3D
		if node != null:
			found.append([node, float(entry[1])])
	return found


## La ruta entera apoya sobre el relieve: el borde de calzada, cada metro y en
## los 1 127 m, se separa del terreno entre 1 y 8 cm.
##
## [method _road_problems] mide lo mismo pero **sólo dentro del disco de
## manzanas**, que es donde están los cruces. Esta fila cubre el kilómetro que
## queda afuera, que es el que se llevó la decisión de WP-T4: con baldosas
## planas de 10 m la separación se iba de −1,5 a +8,5 cm —se enterraba en un
## extremo y flotaba en el otro— por culpa del anillo de desvanecido, donde el
## terreno llega al 5,4 % con toda su curvatura junta.
func _check_route_support() -> void:
	var asphalt := _asphalt_mesh()
	var terrain := _terrain()
	if asphalt == null or terrain == null:
		fail("faltan el asfalto o el relieve para medir el apoyo de la ruta")
		return
	for problem: String in _route_support_problems(_plan, asphalt, terrain):
		fail("ruta: %s" % problem)
	var span := _route_support_span(_plan, asphalt, terrain)
	print("  ruta apoyada: borde cada %.0f m en %.0f m de ruta · separación %.4f–%.4f m"
			% [EDGE_STEP, _plan.route_length(), span.x, span.y]
			+ " (banda [%.2f; %.2f])" % [ASPHALT_CLEARANCE_MIN, ASPHALT_CLEARANCE_MAX])


## Separación mínima y máxima del borde de calzada de la ruta al relieve, como
## `Vector2(mínima, máxima)`.
func _route_support_span(plan: TownPlan, asphalt: ArrayMesh,
		terrain: TownTerrain) -> Vector2:
	var triangles := RoadMesh.flat_triangles(asphalt)
	var index := RoadMesh.index_triangles(triangles, INDEX_CELL)
	var axis := plan.street_axis(0)
	var span := TownPlan.polyline_length(axis)
	var reach := plan.route_width * 0.5 - EDGE_INSET
	var low := INF
	var high := -INF
	var at := 0.0
	while at <= span:
		var point := TownPlan.polyline_point(axis, at)
		var tangent := TownPlan.polyline_tangent(axis, at)
		at += EDGE_STEP
		for sign: float in [1.0, -1.0]:
			var edge := point + TownPlan.left_of(tangent) * reach * sign
			var flat := Vector2(edge.x, edge.z)
			if RoadMesh.coverage_indexed(triangles, index, INDEX_CELL, flat,
					COVER_MARGIN) == 0:
				continue
			var surface := RoadMesh.surface_y_indexed(triangles, index, INDEX_CELL, flat)
			if not is_finite(surface):
				continue
			var clearance := surface - terrain.height_at(edge.x, edge.z)
			low = minf(low, clearance)
			high = maxf(high, clearance)
	return Vector2(low, high)


## Los incumplimientos del apoyo de la ruta. Aparte, para la negativa.
func _route_support_problems(plan: TownPlan, asphalt: ArrayMesh,
		terrain: TownTerrain) -> Array[String]:
	var found: Array[String] = []
	var triangles := RoadMesh.flat_triangles(asphalt)
	var index := RoadMesh.index_triangles(triangles, INDEX_CELL)
	var axis := plan.street_axis(0)
	var span := TownPlan.polyline_length(axis)
	var reach := plan.route_width * 0.5 - EDGE_INSET
	var gaps := 0
	var sunk := 0
	var floating := 0
	var samples := 0
	var at := 0.0
	while at <= span:
		var point := TownPlan.polyline_point(axis, at)
		var tangent := TownPlan.polyline_tangent(axis, at)
		at += EDGE_STEP
		for sign: float in [1.0, -1.0]:
			var edge := point + TownPlan.left_of(tangent) * reach * sign
			var flat := Vector2(edge.x, edge.z)
			samples += 1
			if RoadMesh.coverage_indexed(triangles, index, INDEX_CELL, flat,
					COVER_MARGIN) == 0:
				gaps += 1
				continue
			var surface := RoadMesh.surface_y_indexed(triangles, index, INDEX_CELL, flat)
			if not is_finite(surface):
				continue
			var clearance := surface - terrain.height_at(edge.x, edge.z)
			if clearance < ASPHALT_CLEARANCE_MIN:
				sunk += 1
			elif clearance > ASPHALT_CLEARANCE_MAX:
				floating += 1
	if gaps > 0:
		found.append("%d de %d muestras del borde de calzada no tienen asfalto debajo"
				% [gaps, samples])
	if sunk > 0:
		found.append("%d de %d muestras del borde de calzada se entierran en el terreno"
				% [sunk, samples])
	if floating > 0:
		found.append("%d de %d muestras del borde de calzada flotan sobre el terreno"
				% [floating, samples])
	return found


## `town_a.tscn` entra en el tope de 500 KB con las mallas en `.res` externos
## (criterio 12 del plan).
func _check_scene_size() -> void:
	var file := FileAccess.open(TOWN_PATH, FileAccess.READ)
	if file == null:
		fail("no se pudo abrir '%s' para medirlo" % TOWN_PATH)
		return
	var kilobytes := float(file.get_length()) / 1024.0
	file.close()
	expect(kilobytes <= TSCN_BUDGET_KB,
			"'%s' pesa %.1f KB y el tope es %.0f KB: hay geometría incrustada que tendría"
			% [TOWN_PATH, kilobytes, TSCN_BUDGET_KB] + " que ser un .res externo")
	print("  escena: %s pesa %.1f KB de %.0f"
			% [TOWN_PATH.get_file(), kilobytes, TSCN_BUDGET_KB])


## Las negativas de las filas de relieve: el apoyo, el campo lejano y la ruta
## tienen que ponerse en rojo cuando se les rompe la geometría a mano.
##
## Mismo patrón que [method _check_road_negative]: cada rutina de
## incumplimientos se corre sobre una copia estropeada, y lo que se afirma es
## que **mira**, no que la geometría funcione.
func _check_ground_negative() -> void:
	var terrain := _terrain()
	var asphalt := _asphalt_mesh()
	if terrain == null or asphalt == null:
		fail("no hay relieve ni asfalto para la negativa de apoyo")
		return

	# 1. Un relieve diez centímetros más arriba entierra las cuarenta y seis
	#    casas: cinco veces el tope de 2 cm.
	var lifted := terrain.duplicate(true) as TownTerrain
	var heights := lifted.heights
	for slot: int in heights.size():
		heights[slot] += 0.10
	lifted.heights = heights
	expect(not _rest_problems(lifted).is_empty(),
			"prueba negativa: _rest_problems() aprobó un relieve subido 10 cm")

	# 2. Un campo lejano **sin agujero** y a `y = +1` asoma por encima del
	#    relieve en todo el disco, que es el defecto del `PlaneMesh` de P2b.
	expect(not _far_field_problems(terrain, _covering_field()).is_empty(),
			"prueba negativa: _far_field_problems() aprobó un campo a y = +1 debajo del"
			+ " pueblo")

	# 3. Una calzada veinte centímetros más arriba flota sobre el terreno.
	var floated := _shifted(asphalt, Vector3(0.0, 0.20, 0.0))
	expect(_has_road_problem(_route_support_problems(_plan, floated, terrain), "flotan"),
			"prueba negativa: _route_support_problems() aprobó una calzada 20 cm arriba")
	print("  negativa de relieve: relieve +10 cm → apoyo en rojo · campo a y = +1 → campo"
			+ " lejano en rojo · calzada +20 cm → ruta en rojo")


## Un campo lejano **sin agujero** a `y = +1`, para la negativa: el anillo
## horneado no cubre el pueblo, y lo que no lo cubre no puede asomar.
func _covering_field() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var reach := TERRAIN_FADE_RADIUS
	var corners: Array[Vector3] = [
		Vector3(-reach, 1.0, -reach), Vector3(-reach, 1.0, reach),
		Vector3(reach, 1.0, reach), Vector3(reach, 1.0, -reach),
	]
	for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
		for slot: int in triangle:
			builder.set_normal(Vector3.UP)
			builder.set_uv(Vector2.ZERO)
			builder.add_vertex(corners[slot]
					+ Vector3(_plan.play_centre.x, 0.0, _plan.play_centre.z))
	return builder.commit()


# --------------------------------------------------------------------------
# 9. Oclusores
# --------------------------------------------------------------------------

## El pueblo no hornea **ningún** [OccluderInstance3D] y
## [method CityGrid.occluder_for] devuelve `null`.
##
## Es lo contrario del distrito de P2, que tenía quince —uno por manzana— y
## fueron el «mapa y enemigo que aparecen y desaparecen» del checkpoint 3b: la
## losa opaca invisible se quedaba en pie cuando el edificio se caía. Un pueblo
## de casas de 5 m en manzanas abiertas no tiene nada que ocluir, así que la
## respuesta correcta es no hornear ninguna y dejar que `Building` se lo
## pregunte al derrumbarse y reciba `null`, que es exactamente lo que ese camino
## tolera.
func _check_occluders() -> void:
	var occluders := 0
	for node: Node in _all_nodes(_town):
		if node is OccluderInstance3D:
			occluders += 1
	expect(occluders == 0,
			"el pueblo hornea %d OccluderInstance3D y no tendría que tener ninguno" % occluders)
	var buildings := _town.get_buildings()
	var nulls := 0
	for building: Building in buildings:
		if _town.occluder_for(building) == null:
			nulls += 1
	expect(nulls == buildings.size(),
			"occluder_for() devolvió un oclusor para %d edificios"
			% [buildings.size() - nulls])
	print("  oclusores: 0 en el pueblo · occluder_for() → null en los %d edificios" % nulls)


# --------------------------------------------------------------------------
# 10. Ventanas racionadas (`docs/13` §1)
# --------------------------------------------------------------------------

## Verifica las cuatro cosas que el racionamiento promete: que apague entre el
## 25 % y el 35 % de las **manzanas**, que sea determinista por semilla, que lo
## que se apaga sea la emisión sobre una copia del material —nunca el `.tres`
## compartido— y que no aparezcan materiales de más, que es lo único que podría
## subir los lotes de dibujo.
func _check_windows() -> void:
	_reset_city()
	var blocks := _plan.block_count()
	var dark := _plan.dark_blocks()
	var ratio := float(dark.size()) / float(maxi(blocks, 1))
	expect(dark.size() == _plan.dark_blocks().size(),
			"manzanas a oscuras: %d de %d, esperadas %d"
			% [dark.size(), blocks, _plan.dark_blocks().size()])
	expect(ratio >= WINDOWS_DARK_MIN and ratio <= WINDOWS_DARK_MAX,
			"manzanas a oscuras: %d de %d (%.1f %%), fuera de [%.0f, %.0f] %%"
			% [dark.size(), blocks, ratio * 100.0, WINDOWS_DARK_MIN * 100.0,
			WINDOWS_DARK_MAX * 100.0])

	var first := _dark_signature()
	Global.round_seed = WINDOWS_SEED_B
	var other := _dark_signature()
	Global.round_seed = _seed_before
	var again := _dark_signature()
	expect(first == again, "el reparto de ventanas no es determinista por semilla")
	expect(first != other, "cambiar la semilla no cambió qué manzanas se apagan")

	var mismatched := 0
	var unlit := 0
	var materials: Dictionary[Material, bool] = {}
	var meshes := 0
	for building: Building in _town.get_buildings():
		var block: int = building.get_meta(&"block", -1)
		var expected_dark := _plan.is_block_dark(block)
		if building.windows_lit() == expected_dark:
			mismatched += 1
		if not building.windows_lit():
			unlit += 1
		var mesh_instance := building.stage_intact as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		meshes += 1
		# Las casas de paleta traen **dos** superficies —la opaca y la de las
		# ventanas— y sólo la segunda tiene emisión. Mirar la superficie 0 y
		# nada más, como hacía el check del distrito, no vería el racionamiento.
		for surface: int in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material == null:
				continue
			materials[material] = true
			var standard := material as StandardMaterial3D
			if standard == null or not standard.emission_enabled:
				continue
			var off := is_zero_approx(standard.emission_energy_multiplier)
			if off == building.windows_lit():
				mismatched += 1
	expect(mismatched == 0,
			"%d edificios no coinciden con el reparto de manzanas o con su emisión" % mismatched)
	expect(meshes == _plan.destructible_count(),
			"los edificios no son una malla cada uno: %d mallas para %d edificios"
			% [meshes, _plan.destructible_count()])
	expect(materials.size() <= WINDOWS_MAX_MATERIALS,
			"%d materiales distintos en las fachadas (tope %d): el racionamiento"
			% [materials.size(), WINDOWS_MAX_MATERIALS]
			+ " no puede multiplicar los lotes de dibujo")

	# El `.tres` compartido sigue encendido: lo que se apaga es una copia. Se
	# asevera que **no esté apagado**, no que valga un número concreto: el
	# literal convertía el valor de autor en contrato y se ponía rojo cada vez
	# que alguien bajaba el emisivo por legibilidad. Lo que esta línea tiene que
	# cazar es que `Building._resolve_dark_material()` mute el recurso
	# compartido en vez de duplicarlo, y eso lo deja en 0.0.
	var shared := ResourceLoader.load(TOWN_WINDOWS_MATERIAL_PATH, "StandardMaterial3D") \
			as StandardMaterial3D
	expect(shared != null and shared.emission_enabled
			and shared.emission_energy_multiplier > 0.0,
			"el material compartido '%s' quedó apagado (emisión %s, energía %.3f)"
			% [TOWN_WINDOWS_MATERIAL_PATH,
			str(shared.emission_enabled) if shared != null else "sin material",
			shared.emission_energy_multiplier if shared != null else 0.0])
	print("  ventanas: %d de %d manzanas apagadas (%.0f %%) → %d edificios a oscuras,"
			% [dark.size(), blocks, ratio * 100.0, unlit]
			+ " %d materiales de fachada (tope %d)" % [materials.size(), WINDOWS_MAX_MATERIALS])


## Firma del reparto de manzanas a oscuras, para comparar dos semillas.
func _dark_signature() -> String:
	var parts := PackedStringArray()
	for block: int in _plan.dark_blocks():
		parts.append("%d" % block)
	parts.sort()
	return ",".join(parts)


# --------------------------------------------------------------------------
# 11. Silueta
# --------------------------------------------------------------------------

## El pueblo no tiene rascacielos: el edificio más alto es el hito, de 17 a 20 m,
## y el que domina la silueta es el **coloso**, de 29 m.
##
## Es la decisión de escala de P2b y la que hace legible la pelea desde el aire:
## con los hitos de 75 m del distrito rectangular el jefe desaparecía entre las
## torres.
func _check_skyline() -> void:
	var tallest := 0.0
	var shortest := INF
	var tallest_name := ""
	var houses_max := 0.0
	for building: Building in _town.get_buildings():
		var height := building.get_height()
		shortest = minf(shortest, height)
		if height > tallest:
			tallest = height
			tallest_name = building.name
		if int(building.get_meta(&"role", -1)) == TownPlan.Role.HOUSE:
			houses_max = maxf(houses_max, height)
	expect(tallest >= SKYLINE_MIN and tallest <= SKYLINE_MAX,
			"el edificio más alto ('%s') mide %.1f m, fuera de %.0f–%.0f m"
			% [tallest_name, tallest, SKYLINE_MIN, SKYLINE_MAX])
	expect(tallest < BOSS_HEIGHT,
			"el edificio más alto (%.1f m) llega al coloso (%.0f m): el pueblo lo tapa"
			% [tallest, BOSS_HEIGHT])
	print("  silueta: el más alto es '%s' con %.1f m (banda %.0f–%.0f) contra los %.0f m del"
			% [tallest_name, tallest, SKYLINE_MIN, SKYLINE_MAX, BOSS_HEIGHT]
			+ " coloso · casas hasta %.1f m, el más bajo %.1f m" % [houses_max, shortest])


# --------------------------------------------------------------------------
# 12. `gi_mode`
# --------------------------------------------------------------------------

## `gi_mode` por rol, no por nombre de nodo: estático lo que no se mueve
## —edificios intactos, dañados, calles y suelo— y deshabilitado lo que sí
## —ruinas, escombros, polvo y humo— (`docs/13` §3.3).
##
## Es lo único de la iluminación que se hornea en `town_a.tscn`, así que es lo
## único que puede quedar desincronizado sin que nadie lo note: un edificio en
## `DISABLED` deja de aportar rebote y las ruinas en `STATIC` hacen parpadear las
## cascadas de SDFGI al colapsar (riesgo 1 de `docs/13` §11).
func _check_gi_modes() -> void:
	var wrong_static: Array[String] = []
	var wrong_disabled: Array[String] = []
	var statics := 0
	var disabled := 0
	for node: Node in _all_nodes(_town):
		var geometry := node as GeometryInstance3D
		if geometry == null:
			continue
		var dynamic := node is GPUParticles3D or _under_rubble(node)
		if dynamic:
			disabled += 1
			if geometry.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
				wrong_disabled.append(node.name)
			continue
		statics += 1
		if geometry.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			wrong_static.append(node.name)
	expect(wrong_static.is_empty(),
			"mallas fijas que no están en GI_MODE_STATIC: %s" % ", ".join(wrong_static))
	expect(wrong_disabled.is_empty(),
			"mallas móviles que no están en GI_MODE_DISABLED: %s" % ", ".join(wrong_disabled))
	expect(statics > 0 and disabled > 0,
			"el pueblo no tiene mallas de los dos tipos (%d fijas, %d móviles)"
			% [statics, disabled])
	print("  gi_mode: %d mallas STATIC (edificios, calles, campo) · %d DISABLED"
			% [statics, disabled] + " (ruinas, polvo y humo)")


## Verdadero si [param node] cuelga de una etapa de ruina, que es la malla que
## cambia de forma al colapsar.
func _under_rubble(node: Node) -> bool:
	var walker := node
	while walker != null and walker != _town:
		if walker.name == &"StageRubble":
			return true
		walker = walker.get_parent()
	return false


# --------------------------------------------------------------------------
# 13. Mallas de escombro
# --------------------------------------------------------------------------

## Los perfiles del pueblo comparten como mucho **dos** mallas de escombro,
## porque el `RubbleField` sólo admite cuatro campos y los enemigos reservan dos
## (`docs/10` §6).
##
## El perfil `house`, que estrena WP-B, tiene que **reutilizar** la malla chica
## del perfil `low_block` en vez de traer la suya: cincuenta y dos casas con
## escombro propio serían un tercer campo y el pueblo se quedaría sin sitio para
## las ruinas del coloso.
func _check_debris_profiles() -> void:
	var meshes: Dictionary[Mesh, bool] = {}
	var house_mesh: Mesh = null
	for building: Building in _town.get_buildings():
		if building.profile.debris_mesh == null:
			fail("'%s' no tiene malla de escombro" % building.name)
			continue
		meshes[building.profile.debris_mesh] = true
		if is_equal_approx(building.get_max_hp(), HOUSE_HP):
			house_mesh = building.profile.debris_mesh
		expect(building.profile.debris_shape != null,
				"'%s' no tiene forma de escombro" % building.name)
	expect(meshes.size() <= 2,
			"el pueblo registra %d mallas de escombro, tope 2" % meshes.size())
	expect(house_mesh != null and house_mesh.resource_path == DEBRIS_SMALL_PATH,
			"el perfil 'house' usa '%s' y tendría que reutilizar '%s'"
			% [house_mesh.resource_path if house_mesh != null else "nada", DEBRIS_SMALL_PATH])
	print("  escombro: %d mallas distintas (tope 2) · 'house' reutiliza '%s'"
			% [meshes.size(), DEBRIS_SMALL_PATH.get_file()])


# --------------------------------------------------------------------------
# 14. Marcadores
# --------------------------------------------------------------------------

## Los marcadores que el nivel adopta (`docs/11`): cuatro accesos del coloso, los
## ocho puestos de pila, la aparición del dron, el centro del pueblo y la pose de
## la cámara fija.
##
## El centro se busca **por grupo** y no por nombre porque es así como lo
## encuentra el jefe (`arachnodroid.city_centre()`), y una vez se perdió por un
## `add_to_group()` sin `persistent = true`: el grupo no se guardaba en la escena
## empaquetada y el coloso se quedaba sin pueblo al que marchar.
func _check_markers() -> void:
	var spawns := _town.get_node_or_null(NodePath(CityGrid.SPAWNS_NODE))
	expect(spawns != null, "el pueblo no tiene el nodo '%s'" % CityGrid.SPAWNS_NODE)
	if spawns != null:
		expect(spawns.get_child_count() == _plan.spawn_points().size(),
				"accesos del coloso: %d, esperados %d"
				% [spawns.get_child_count(), _plan.spawn_points().size()])
		var wanted := _plan.play_radius + SPAWN_MARGIN
		for index: int in _plan.spawn_points().size():
			var marker := spawns.get_node_or_null(NodePath("EnemySpawn%d" % index)) as Marker3D
			if marker == null:
				fail("falta 'EnemySpawn%d'" % index)
				continue
			var distance := _plan.distance_to_centre(marker.position)
			expect(absf(distance - wanted) <= SPAWN_MARGIN_TOLERANCE,
					"'EnemySpawn%d' está a %.2f m del centro, esperado %.2f ±%.1f"
					% [index, distance, wanted, SPAWN_MARGIN_TOLERANCE])
			# El plano da la aparición **a ras del suelo** y `CityGrid` le suma el
			# relieve: lo que tiene que coincidir es la suma.
			var planned := _town.on_terrain(_plan.spawn_points()[index].origin)
			expect(marker.position.distance_to(planned) <= MARKER_TOLERANCE,
					"'EnemySpawn%d' horneado en %s y el plano lo pone en %s"
					% [index, str(marker.position), str(planned)])
			var facing := -marker.transform.basis.z
			var angle := TownPlan.flat_angle(facing, _plan.play_centre - marker.position)
			expect(angle <= SPAWN_FACING_DEG,
					"'EnemySpawn%d' mira a %.2f° del centro, tope %.1f°"
					% [index, angle, SPAWN_FACING_DEG])

	var posts := _town.get_node_or_null(NodePath(CityGrid.POSTS_NODE))
	expect(posts != null, "el pueblo no tiene el nodo '%s'" % CityGrid.POSTS_NODE)
	if posts != null:
		expect(posts.get_child_count() == _plan.battery_posts().size(),
				"puestos de pila: %d, esperados %d"
				% [posts.get_child_count(), _plan.battery_posts().size()])
		# Los puestos se comparan **posición a posición** contra el plano. Los
		# tres de azotea son la excepción: el plano los calcula con su tabla de
		# alturas nominales —que es lo que le permite no abrir un solo asset— y
		# `CityGrid` los afina con la altura real del edificio sembrado. Ahí lo
		# que se verifica es que el afinado **exista** (el puesto está sobre el
		# techo de su parcela, no sobre el del plano) y que sea coherente.
		var roofs := 0
		for index: int in _plan.battery_posts().size():
			var post := posts.get_node_or_null(NodePath("Post%d" % index)) as Marker3D
			if post == null:
				fail("falta 'Post%d' o no es un Marker3D" % index)
				continue
			var on_roof := index < _plan.battery_roof_parcels.size() \
					and _plan.battery_roof_parcels[index] >= 0
			# Un puesto de calle cuelga a tantos metros **del suelo**; uno de azotea,
			# sobre un edificio que ya apoya en la cota de su manzana.
			var planned: Vector3 = _plan.battery_posts()[index]
			if not on_roof:
				planned = _town.on_terrain(planned)
			var parcel := _plan.battery_roof_parcels[index] \
					if index < _plan.battery_roof_parcels.size() else -1
			if parcel < 0:
				expect(post.position.distance_to(planned) <= MARKER_TOLERANCE,
						"'Post%d' horneado en %s y el plano lo pone en %s"
						% [index, str(post.position), str(planned)])
				continue
			roofs += 1
			var building := _town.get_building_at(parcel)
			if building == null:
				fail("'Post%d' dice apoyar en la parcela %d y no hay edificio ahí"
						% [index, parcel])
				continue
			var roof := building.position.y + building.get_height() \
					+ TownPlanner.POST_ROOF_CLEARANCE
			expect(absf(post.position.y - roof) <= MARKER_TOLERANCE,
					"'Post%d' está a %.2f m y la azotea real de '%s' pide %.2f m"
					% [index, post.position.y, building.name, roof])
			expect(Vector2(post.position.x - building.position.x,
					post.position.z - building.position.z).length() <= MARKER_TOLERANCE,
					"'Post%d' no cae sobre '%s'" % [index, building.name])
			expect(post.position.y > planned.y - ROOF_REFINE_MAX
					and post.position.y < planned.y + ROOF_REFINE_MAX,
					"'Post%d' se afinó %.2f m respecto del plano (%.2f m): la tabla de"
					% [index, post.position.y - planned.y, planned.y]
					+ " alturas nominales y la malla no se parecen")
		expect(roofs == ROOF_POSTS,
				"puestos de azotea: %d, esperados %d" % [roofs, ROOF_POSTS])

	var drone := _town.get_node_or_null(NodePath(CityGrid.DRONE_NODE)) as Marker3D
	expect(drone != null, "falta '%s'" % CityGrid.DRONE_NODE)
	if drone != null:
		var planned_drone := _town.on_terrain_xform(_plan.drone_spawn())
		expect(drone.position.distance_to(planned_drone.origin) <= MARKER_TOLERANCE,
				"'%s' horneado en %s y el plano lo pone en %s"
				% [CityGrid.DRONE_NODE, str(drone.position), str(planned_drone.origin)])
		expect(TownPlan.flat_angle(-drone.transform.basis.z, -planned_drone.basis.z)
				<= SPAWN_FACING_DEG,
				"'%s' no mira adonde dice el plano" % CityGrid.DRONE_NODE)
	var camera := _town.get_node_or_null(NodePath(CityGrid.CAMERA_NODE)) as Marker3D
	expect(camera != null, "falta '%s'" % CityGrid.CAMERA_NODE)
	if camera != null:
		var planned_camera := _town.on_terrain_xform(_plan.camera_fixed())
		expect(camera.position.distance_to(planned_camera.origin) <= MARKER_TOLERANCE,
				"'%s' horneado en %s y el plano lo pone en %s"
				% [CityGrid.CAMERA_NODE, str(camera.position), str(planned_camera.origin)])
	var centre := _town.get_node_or_null(NodePath(CityGrid.CENTRE_NODE)) as Marker3D
	expect(centre != null, "falta '%s'" % CityGrid.CENTRE_NODE)
	if centre != null:
		expect(centre.is_in_group(CityGrid.CENTRE_GROUP),
				"'%s' no está en el grupo '%s'"
				% [CityGrid.CENTRE_NODE, CityGrid.CENTRE_GROUP])
		expect(_plan.distance_to_centre(centre.position) <= 0.01,
				"'%s' no está en el centro del círculo (a %.2f m)"
				% [CityGrid.CENTRE_NODE, _plan.distance_to_centre(centre.position)])
	var grouped := get_tree().get_nodes_in_group(CityGrid.CENTRE_GROUP)
	expect(grouped.size() == 1,
			"nodos en el grupo '%s': %d, esperado 1" % [CityGrid.CENTRE_GROUP, grouped.size()])
	print("  marcadores: %d accesos a %.0f m (play_radius + %.0f), %d puestos de pila,"
			% [_plan.spawn_points().size(), _plan.play_radius + SPAWN_MARGIN, SPAWN_MARGIN, _plan.battery_posts().size()]
			+ " DroneSpawn, TownCentre en '%s' y CameraFixedPose" % CityGrid.CENTRE_GROUP)


# --------------------------------------------------------------------------
# 15. Presupuesto de dibujo
# --------------------------------------------------------------------------

## Lotes de dibujo del pueblo contra el tope de 900 a 1080p (`docs/10` §7).
##
## En `--headless` no hay controlador de render y `RenderingServer` devuelve cero
## en todos sus contadores, así que el número medido **no existe**: lo que se
## asevera ahí es una **estimación** —una superficie de malla es un lote, un
## `MultiMesh` es uno solo— y se dice en el informe que es una estimación. La
## medida de verdad la toma `render_check` con ventana a 1080p; este sub-check
## existe para que una regresión estructural (alguien deja de agrupar las calles
## en `MultiMesh` y siembra mil nodos) se vea también en CI.
func _check_budget() -> void:
	_draw_calls = int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var surfaces := 0
	var multis := 0
	for node: Node in _all_nodes(_town):
		if node is MultiMeshInstance3D:
			multis += 1
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		surfaces += maxi(mesh_instance.mesh.get_surface_count(), 1)
	_estimated_batches = surfaces + multis
	if _draw_calls > 0:
		expect(_draw_calls < DRAW_CALL_BUDGET,
				"lotes de dibujo medidos: %d, tope %d" % [_draw_calls, DRAW_CALL_BUDGET])
		print("  presupuesto: %d lotes medidos (tope %d) · %d superficies de malla + %d MultiMesh"
				% [_draw_calls, DRAW_CALL_BUDGET, surfaces, multis])
		return
	expect(_estimated_batches < DRAW_CALL_BUDGET,
			"lotes estimados: %d (%d superficies + %d MultiMesh), tope %d"
			% [_estimated_batches, surfaces, multis, DRAW_CALL_BUDGET])
	print("  presupuesto: %d lotes ESTIMADOS (%d superficies de malla + %d MultiMesh), tope %d"
			% [_estimated_batches, surfaces, multis, DRAW_CALL_BUDGET]
			+ " · en --headless no hay contador de render: la medida real es de render_check")


# --------------------------------------------------------------------------
# 16. Decoración inerte
# --------------------------------------------------------------------------

## Doscientos impactos sobre una casa de caserío no producen nada.
##
## Las doce casas de afuera son paisaje, no juego: están a 170–350 m del círculo,
## el jugador no puede defenderlas y contarlas en la integridad sería bajarle la
## barra por algo que no puede hacer. La garantía es doble y las dos mitades se
## comprueban acá: **no se las puede tocar** (capa y máscara en cero, así que el
## rayo del arma no las ve) y **no responden** (no llevan `building.gd`, así que
## ni siquiera tienen a qué llamar).
##
## El bucle tira los doscientos disparos igual, por el mismo camino que el arma
## —`has_method(&"take_damage")` y adentro— para que una regresión que le ponga
## `building.gd` a una casa de caserío se vea acá y no en la barra EN PIE de una
## partida.
func _check_decor_inert() -> void:
	_reset_city()
	var houses := _decor_houses()
	if houses.is_empty():
		fail("no hay casas de caserío sobre las que disparar")
		return
	var target := houses[0] as StaticBody3D
	if target == null:
		fail("'%s' no es un StaticBody3D" % houses[0].name)
		return
	expect(not (target is Building), "'%s' lleva building.gd" % target.name)
	expect(not target.is_in_group(Building.GROUP),
			"'%s' está en el grupo '%s'" % [target.name, Building.GROUP])
	# La garantía **no** es que sea intangible, sino que no sea ciudad: en
	# `PhysicsLayers.WORLD` el dron no la atraviesa y el rayo del arma se detiene
	# en ella igual que en el terreno, pero no hay `take_damage` a quien llamar
	# ni `CityIntegrity` que la cuente. En la capa `CITY` sería un blanco.
	expect(target.collision_layer == PhysicsLayers.WORLD,
			"'%s' está en la capa %d, esperada %d (WORLD)"
			% [target.name, target.collision_layer, PhysicsLayers.WORLD])
	expect(target.collision_layer & PhysicsLayers.CITY == 0,
			"'%s' está en la capa de ciudad: el arma y el jefe la tomarían por edificio"
			% target.name)

	var destroyed_before := _destroyed_events.size()
	var integrity_before := _integrity.get_ratio()
	var hp_before := _integrity.get_total_hp()
	var point := target.global_position + Vector3(0.0, 2.0, 0.0)
	var applied := 0.0
	for shot: int in DECOR_SHOTS:
		if target.has_method(&"take_damage"):
			applied += float(target.call(&"take_damage", FRIENDLY_FIRE_DAMAGE, point))
	await wait_physics(2)

	expect(is_zero_approx(applied),
			"'%s' absorbió %.1f de daño: es decoración" % [target.name, applied])
	expect(_destroyed_events.size() == destroyed_before,
			"los %d disparos sobre '%s' publicaron %d building_destroyed"
			% [DECOR_SHOTS, target.name, _destroyed_events.size() - destroyed_before])
	expect(is_equal_approx(_integrity.get_ratio(), integrity_before),
			"la integridad pasó de %.6f a %.6f al disparar sobre la decoración"
			% [integrity_before, _integrity.get_ratio()])
	expect_near(_integrity.get_total_hp(), hp_before, 0.001,
			"el HP acumulado de la ciudad se movió al disparar sobre la decoración")
	expect(is_instance_valid(target) and target.visible,
			"'%s' desapareció tras los disparos" % target.name)
	print("  decoración: %d × %.0f HP sobre '%s' → 0 building_destroyed, integridad %.4f"
			% [DECOR_SHOTS, FRIENDLY_FIRE_DAMAGE, target.name, _integrity.get_ratio()]
			+ " sin cambio, capa WORLD (el arma no tiene a quién pegarle)")


# --------------------------------------------------------------------------
# 17, 18 y 19. Etapas
# --------------------------------------------------------------------------

## Daño progresivo sobre una casa: `DAMAGED` al cruzar 0.60, `RUBBLE` al cruzar
## 0.15, shader puesto, emisivos apagados, `hp = 0`, inmune y conmutación de
## formas al terminar el derrumbe.
##
## La casa que se maltrata tiene que estar **encendida**: cuatro de las doce
## manzanas están a oscuras y una casa de una de ellas ya llega con la emisión en
## cero, así que la aserción de «en INTACT los emisivos están encendidos» no
## mediría nada sobre ella. No es una concesión: el racionamiento lo verifica su
## propio sub-check, y éste mide las etapas.
func _check_stages() -> void:
	var building := _pick_lit_building(HOUSE_HP)
	if building == null:
		fail("no hay ninguna casa encendida para probar las etapas")
		return
	var stages: Array[int] = []
	var _s := building.stage_changed.connect(func(stage: Building.Stage) -> void:
		stages.append(int(stage)))
	var destroyed_count := [0]
	var _d := building.destroyed.connect(func(_value: int) -> void:
		destroyed_count[0] += 1)

	expect(building.stage == Building.Stage.INTACT, "el edificio no arranca en INTACT")
	expect(_active_material(building) is StandardMaterial3D,
			"en INTACT la malla debería llevar el StandardMaterial3D de la pieza")
	expect(_emission_enabled(building), "en INTACT los emisivos deberían estar encendidos")

	# Justo por encima del umbral de DAMAGED: todavía intacto.
	var max_hp := building.get_max_hp()
	var applied := building.take_damage(max_hp * (1.0 - DAMAGED_THRESHOLD) - 1.0, building.global_position)
	expect_near(applied, max_hp * (1.0 - DAMAGED_THRESHOLD) - 1.0, 0.01, "daño aplicado devuelto")
	expect(building.hp < max_hp, "take_damage no redujo el HP")
	expect(building.stage == Building.Stage.INTACT,
			"cruzó a DAMAGED antes del umbral (ratio %.3f)" % building.get_ratio())

	# Un punto más y cruza.
	var _first := building.take_damage(2.0, building.global_position)
	expect(building.stage == Building.Stage.DAMAGED,
			"no entró en DAMAGED con ratio %.3f" % building.get_ratio())
	var overlay := _active_material(building) as ShaderMaterial
	expect(overlay != null, "en DAMAGED la malla no lleva ShaderMaterial")
	if overlay != null:
		var path := overlay.shader.resource_path if overlay.shader != null else ""
		expect(path == DAMAGE_SHADER_PATH or path == PALETTE_SHADER_PATH,
				"el material de daño usa '%s' y no es ninguno de los dos shaders de boquetes"
				% path)
	expect(not _emission_enabled(building), "en DAMAGED los emisivos siguen encendidos")
	expect(_trauma_events.size() >= 1, "DAMAGED no publicó camera_trauma")
	if not _trauma_events.is_empty():
		var last: Dictionary = _trauma_events[-1]
		expect_near(float(last["amount"]), building.profile.trauma_damaged, 0.001,
				"trauma de DAMAGED")

	# Hasta justo antes del umbral de ruina.
	var to_edge := building.hp - max_hp * RUBBLE_THRESHOLD - 1.0
	var _second := building.take_damage(to_edge, building.global_position)
	expect(building.stage == Building.Stage.DAMAGED,
			"cruzó a RUBBLE antes de tiempo (ratio %.3f)" % building.get_ratio())

	var trauma_before := _trauma_events.size()
	var _third := building.take_damage(2.0, building.global_position)
	expect(building.stage == Building.Stage.RUBBLE,
			"no entró en RUBBLE con ratio %.3f" % building.get_ratio())
	expect(is_zero_approx(building.hp), "en RUBBLE el HP vale %.2f, esperado 0" % building.hp)
	expect(_trauma_events.size() == trauma_before + 1, "RUBBLE no publicó exactamente un trauma")
	if _trauma_events.size() > trauma_before:
		var last: Dictionary = _trauma_events[-1]
		expect_near(float(last["amount"]), building.profile.trauma_rubble, 0.001,
				"trauma de RUBBLE")
		expect(building.global_position.distance_to(last["position"]) < 0.01,
				"el trauma no publicó la posición del edificio")

	# Inmunidad: insistir no cambia nada ni vuelve a emitir.
	var again := building.take_damage(5000.0, building.global_position)
	expect(is_zero_approx(again), "una ruina devolvió %.2f de daño aplicado" % again)
	expect(building.stage == Building.Stage.RUBBLE, "la ruina cambió de etapa al insistir")

	await _advance(building.profile.collapse_seconds + 0.3)
	expect(building.is_collapsed(), "el derrumbe no terminó")
	expect(building.intact_shape.disabled, "la caja intacta sigue activa en RUBBLE")
	expect(not building.rubble_shape.disabled, "la caja de ruina sigue desactivada en RUBBLE")
	expect(not building.stage_intact.visible, "la malla intacta sigue visible en RUBBLE")
	expect(building.stage_rubble.visible, "la etapa de ruina no es visible")
	var rubble_box := building.rubble_shape.shape as BoxShape3D
	expect(rubble_box != null and rubble_box.size.y <= 3.01,
			"la caja de ruina mide %.2f m, tope 3 m"
			% [rubble_box.size.y if rubble_box != null else -1.0])
	expect(stages == [int(Building.Stage.DAMAGED), int(Building.Stage.RUBBLE)],
			"secuencia de etapas: %s" % str(stages))
	expect(destroyed_count[0] == 1, "'destroyed' se emitió %d veces" % destroyed_count[0])
	expect(_destroyed_events.size() >= 1, "no llegó Events.building_destroyed")
	if not _destroyed_events.is_empty():
		var event: Dictionary = _destroyed_events[-1]
		expect(event["value"] == building.profile.value,
				"building_destroyed publicó value %s, esperado %d"
				% [str(event["value"]), building.profile.value])
		expect(building.global_position.distance_to(event["position"]) < 0.01,
				"building_destroyed publicó otra posición")
	print("  etapas: INTACT → DAMAGED (ratio ≤ %.2f) → RUBBLE (ratio ≤ %.2f), 1 'destroyed'"
			% [DAMAGED_THRESHOLD, RUBBLE_THRESHOLD])
	_reset_city()


## Fuego amigo: 217 impactos de 6 HP derriban una casa de 1 300 (`docs/10` §8).
func _check_friendly_fire() -> void:
	var building := _pick_building(HOUSE_HP)
	if building == null:
		return
	# El acumulador va dentro de un `Array`: GDScript captura los locales de una
	# lambda **por valor**, así que sumar sobre un `float` capturado no saldría
	# nunca de la lambda.
	var registered: Array[float] = [0.0]
	var _c := building.damage_taken.connect(func(amount: float, _p: Vector3) -> void:
		registered[0] += amount)
	var point := building.global_position + Vector3(0.0, 2.0, 0.0)
	for shot: int in FRIENDLY_FIRE_SHOTS:
		var _applied := building.take_damage(FRIENDLY_FIRE_DAMAGE, point)
	expect(building.stage == Building.Stage.RUBBLE,
			"tras %d impactos de %.0f HP la casa sigue en etapa %d"
			% [FRIENDLY_FIRE_SHOTS, FRIENDLY_FIRE_DAMAGE, int(building.stage)])
	expect_near(registered[0], building.get_max_hp(), 0.5,
			"el daño registrado no coincide con el HP nominal de la casa")
	print("  fuego amigo: %d × %.0f HP derriban una casa de %.0f HP (%.0f registrados)"
			% [FRIENDLY_FIRE_SHOTS, FRIENDLY_FIRE_DAMAGE, HOUSE_HP, registered[0]])
	await _advance(building.profile.collapse_seconds + 0.2)
	_reset_city()


## Derrumbe completo —etapa, formas y escombros quietos— en menos de 6 s.
func _check_collapse_time() -> void:
	var building := _pick_building(BIG_HP)
	if building == null:
		fail("no hay ningún edificio grande para cronometrar el derrumbe")
		return
	_collapse_piece = String(building.get_meta(&"piece", &"?"))
	_pool.clear()
	await wait_physics(2)
	var _applied := building.take_damage(building.get_max_hp(), building.global_position)
	var chunks := _pool.get_live_chunks()
	expect(chunks.size() >= building.profile.debris_count_min,
			"el derrumbe pidió %d escombros, mínimo %d"
			% [chunks.size(), building.profile.debris_count_min])
	expect(chunks.size() <= building.profile.debris_count_max,
			"el derrumbe pidió %d escombros, máximo %d"
			% [chunks.size(), building.profile.debris_count_max])

	var elapsed := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while elapsed < COLLAPSE_BUDGET + 1.0:
		await wait_physics(1)
		elapsed += step
		_sample_budgets()
		if building.is_collapsed() and _chunks_settled(chunks):
			break
	_collapse_seconds = elapsed
	expect(building.is_collapsed(), "el edificio no terminó de derrumbarse")
	expect(elapsed < COLLAPSE_BUDGET,
			"el derrumbe completo tardó %.2f s, tope %.1f s" % [elapsed, COLLAPSE_BUDGET])
	print("  derrumbe completo de '%s' (%.1f m): %.2f s con %d escombros"
			% [_collapse_piece, building.get_height(), elapsed, chunks.size()])
	_reset_city()


# --------------------------------------------------------------------------
# 20. Asedio
# --------------------------------------------------------------------------

## El grupo `buildings_under_siege` tiene un único miembro mientras hay daño
## sostenido, y queda vacío tras `siege_window` segundos sin recibir más.
func _check_siege() -> void:
	var building := _pick_building(BIG_HP)
	if building == null:
		return
	var window := building.profile.siege_window
	var needed := building.profile.siege_damage
	# Daño sostenido durante media ventana, repartido en pasos de física.
	var elapsed := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while elapsed < window * 0.5:
		var _applied := building.take_damage(needed * 0.1, building.global_position)
		await wait_physics(1)
		elapsed += step
	await _advance(0.4)
	var marked := get_tree().get_nodes_in_group(Building.GROUP_UNDER_SIEGE)
	expect(marked.size() == 1,
			"bajo asedio: %d edificios, esperado 1" % marked.size())
	if marked.size() == 1:
		expect(marked[0] == building, "el marcado no es el edificio que recibe el daño")
	expect(_integrity.get_under_siege() == building,
			"get_under_siege() no devuelve el edificio golpeado")

	# Sin daño, la ventana se vacía.
	await _advance(window + 0.6)
	var after := get_tree().get_nodes_in_group(Building.GROUP_UNDER_SIEGE)
	expect(after.is_empty(), "%d edificios siguen bajo asedio %.1f s después"
			% [after.size(), window])
	expect(_integrity.get_under_siege() == null,
			"get_under_siege() sigue devolviendo un edificio")
	print("  asedio: 1 edificio marcado con daño sostenido, 0 tras %.1f s sin daño" % window)
	_reset_city()


# --------------------------------------------------------------------------
# 21. Edificio protegido
# --------------------------------------------------------------------------

## La escuela: peso ×3 en la integridad, ventanas siempre encendidas y una sola
## `protected_fallen` al caer (`docs/11` §1).
##
## El protegido no se elige por comodidad: es `Building_School`, el mismo nodo
## que `RoundCatalog` declara por nombre, así que este sub-check falla si alguien
## regenera el pueblo y la escuela cambia de nombre.
##
## Para probar «queda encendido aunque su manzana esté a oscuras» hace falta que
## la manzana de la escuela **esté** a oscuras, y con la semilla de la ronda eso
## pasa o no pasa. En vez de dejar la aserción a merced del sorteo, se busca una
## semilla que apague esa manzana y se reparte con ella; al terminar se devuelve
## `Global.round_seed` a lo que estaba, que es lo que comprueba
## [method _restore].
func _check_protected() -> void:
	_reset_city()
	var school := _school()
	if school == null:
		fail("el pueblo no trae '%s'" % TownPlan.SCHOOL_NODE)
		return
	var twin := _twin_of(school)
	if twin == null:
		fail("no hay otro edificio del mismo HP que la escuela")
		return

	var block: int = school.get_meta(&"block", -1)
	var dark_seed := _seed_that_darkens(block)
	if dark_seed != _seed_before:
		Global.round_seed = dark_seed
		school.reset()
	var was_lit := school.windows_lit()

	school.mark_protected("BLD_SCHOOL_12", 3.0)
	_integrity.set_protected(school)
	expect(school.is_in_group(Building.GROUP_PROTECTED), "el protegido no entró en su grupo")
	expect(school.windows_lit(),
			"el protegido tiene que quedar encendido aunque su manzana esté a oscuras")
	expect(not was_lit,
			"no se encontró ninguna semilla que apague la manzana %d de la escuela: la"
			% block + " aserción de arriba no estaría midiendo nada")
	expect(is_equal_approx(_integrity.get_ratio(), 1.0),
			"el peso ×3 movió la integridad inicial a %.4f" % _integrity.get_ratio())

	var fallen: Array[int] = [0]
	var on_fallen := func(_building: Building) -> void: fallen[0] += 1
	var _discard := _integrity.protected_fallen.connect(on_fallen)

	var before_twin := _integrity.get_ratio()
	var _applied := twin.take_damage(twin.get_max_hp(), twin.global_position)
	var twin_cost := before_twin - _integrity.get_ratio()
	var before_school := _integrity.get_ratio()
	_applied = school.take_damage(school.get_max_hp(), school.global_position)
	var school_cost := before_school - _integrity.get_ratio()
	var factor := school_cost / maxf(twin_cost, 0.000001)
	expect(absf(factor - _integrity.protected_weight) <= PROTECTED_WEIGHT_TOLERANCE,
			"el protegido pesa ×%.3f y tendría que pesar ×%.1f"
			% [factor, _integrity.protected_weight])
	expect(fallen[0] == 1, "protected_fallen se emitió %d veces, no una" % fallen[0])
	await _advance(0.2)
	expect(fallen[0] == 1, "protected_fallen se repitió durante el derrumbe (%d)" % fallen[0])
	print("  protegido: '%s' (manzana %d, a oscuras con semilla %d) pesa ×%.2f"
			% [school.name, block, dark_seed, factor]
			+ " (%.5f contra %.5f de un edificio de %.0f HP), 1 protected_fallen y"
			% [school_cost, twin_cost, twin.get_max_hp()] + " ventanas encendidas")

	# El pueblo vuelve a su estado neutro para los sub-checks que siguen.
	_integrity.protected_fallen.disconnect(on_fallen)
	school.remove_from_group(Building.GROUP_PROTECTED)
	school.display_key = ""
	school.priority = 1.0
	_integrity.set_protected(null)
	Global.round_seed = _seed_before
	_reset_city()


## La escuela, buscada por el nombre que declara el plano.
func _school() -> Building:
	for building: Building in _town.get_buildings():
		if building.name == String(TownPlan.SCHOOL_NODE):
			return building
	return null


## Primera semilla que deja a oscuras la manzana [param block], empezando por la
## que está puesta. Devuelve la actual si ninguna de las cien primeras lo hace.
func _seed_that_darkens(block: int) -> int:
	var restore := Global.round_seed
	for offset: int in 100:
		Global.round_seed = restore + offset
		if _plan.is_block_dark(block):
			var found := Global.round_seed
			Global.round_seed = restore
			return found
	Global.round_seed = restore
	return restore


## Otro edificio intacto con el mismo HP nominal que [param building].
func _twin_of(building: Building) -> Building:
	if building == null:
		return null
	for other: Building in _town.get_buildings():
		if other == building or other.stage != Building.Stage.INTACT:
			continue
		if is_equal_approx(other.get_max_hp(), building.get_max_hp()):
			return other
	return null


# --------------------------------------------------------------------------
# 22. Escombros
# --------------------------------------------------------------------------

## Diez edificios derribados seguidos no dejan más de `MAX_LIVE` escombros vivos
## en ningún tick, y los retirados se hornean en el `RubbleField`.
func _check_debris_cap() -> void:
	_pool.clear()
	_field.clear()
	await wait_physics(2)
	# El contador de construidos es acumulado desde que nació el pool y las fases
	# anteriores ya gastaron unos cuantos; lo que prueba el reciclado es el
	# **incremento** durante esta fase, que no puede pasar del tope de vivos.
	var created_before := _pool.get_created_count()
	var recycled_before := _pool.get_recycled_count()
	# Cinco casas y cinco grandes, **intercalados**: así se registran las dos
	# mallas de escombro del pueblo (`debris_concrete_small` de las casas y
	# `debris_concrete_large` de los grandes) y el tope de campos del
	# `RubbleField` se mide de verdad (`docs/10` §6 reserva 2 campos para la
	# ciudad y 2 para los enemigos).
	#
	# Lo de intercalar no es cosmética. El pool admite 24 escombros vivos y
	# cinco casas seguidas ya lo llenan; a partir de ahí cada derrumbe nuevo
	# recicla los más viejos, y **el reciclado es lo que hornea el campo**. Con
	# las cinco casas primero y los cinco grandes después, lo único que llegaba
	# a hornearse era escombro de casa: un campo, no dos, y la mitad de la
	# aserción dejaba de medir nada.
	var by_family: Array[Array] = [[] as Array[Building], [] as Array[Building]]
	for slot: int in 2:
		var max_hp := HOUSE_HP if slot == 0 else BIG_HP
		var family: Array[Building] = by_family[slot]
		for building: Building in _town.get_buildings():
			if family.size() >= 5:
				break
			if building.stage == Building.Stage.INTACT \
					and is_equal_approx(building.get_max_hp(), max_hp):
				family.append(building)
	var queue: Array[Building] = []
	for index: int in 5:
		for slot: int in 2:
			var family: Array[Building] = by_family[slot]
			if index < family.size():
				queue.append(family[index])
	var count := 0
	for building: Building in queue:
		if count >= 10:
			break
		count += 1
		var _applied := building.take_damage(building.get_max_hp(), building.global_position)
		expect(_pool.get_live_count() <= DebrisPool.MAX_LIVE,
				"tras derribar %d edificios hay %d escombros vivos, tope %d"
				% [count, _pool.get_live_count(), DebrisPool.MAX_LIVE])
		_sample_budgets()
		await wait_physics(4)
		_sample_budgets()
	await _advance(2.5)
	expect(_max_live_debris <= DebrisPool.MAX_LIVE,
			"máximo de escombros vivos: %d, tope %d" % [_max_live_debris, DebrisPool.MAX_LIVE])
	expect(_field.get_field_count() == 2,
			"campos del RubbleField tras derribar casas y grandes: %d, esperados 2"
			% _field.get_field_count())
	expect(_field.get_field_count() <= RubbleField.MAX_FIELDS,
			"campos del RubbleField: %d, tope %d"
			% [_field.get_field_count(), RubbleField.MAX_FIELDS])
	expect(_field.get_total_instance_count() > 0,
			"ningún escombro retirado se horneó en el RubbleField")
	var created := _pool.get_created_count() - created_before
	var recycled := _pool.get_recycled_count() - recycled_before
	expect(recycled > 0, "ningún escombro volvió a la lista libre: no hubo reciclado")
	expect(created <= DebrisPool.MAX_LIVE,
			"el pool construyó %d RigidBody3D para %d retiros: el reciclado no funciona"
			% [created, recycled])
	expect(_max_emitters <= Building.MAX_EMITTERS,
			"emisores simultáneos: %d, tope %d" % [_max_emitters, Building.MAX_EMITTERS])
	print(("  escombros: máximo %d vivos (tope %d), %d horneados en %d campos,"
			+ " %d reciclados con sólo %d cuerpos construidos")
			% [_max_live_debris, DebrisPool.MAX_LIVE, _field.get_total_instance_count(),
			_field.get_field_count(), recycled, created])
	_reset_city()
	_pool.clear()
	_field.clear()
	await wait_physics(2)


# --------------------------------------------------------------------------
# 23. Integridad
# --------------------------------------------------------------------------

## Arrasa el pueblo y verifica que la integridad es monótona no creciente, que el
## acumulador no deriva, que la derrota se publica una sola vez al cruzar 0.35 y
## que el valor final es 0.
func _check_integrity_run() -> void:
	_integrity_samples = PackedFloat32Array()
	_destroyed_events.clear()
	_defeat_events = 0
	var buildings := _town.get_buildings()
	var drift := 0.0
	var checkpoints := 0
	var defeat_seen_at := -1.0
	var expected_value := 0

	for index: int in buildings.size():
		var building := buildings[index]
		expected_value += building.profile.value
		var _applied := building.take_damage(building.get_max_hp(), building.global_position)
		if index % 12 == 0:
			var accumulated := _integrity.get_total_hp()
			var recomputed := _integrity.recompute_total_hp()
			drift = maxf(drift, absf(accumulated - recomputed))
			checkpoints += 1
		if _defeat_events > 0 and defeat_seen_at < 0.0:
			defeat_seen_at = _integrity.get_ratio()
		await wait_physics(2)
		_sample_budgets()

	await _advance(2.6)
	_sample_budgets()

	expect(checkpoints >= 5, "sólo %d puntos de control del acumulador" % checkpoints)
	expect(drift < 1e-3, "el acumulador de HP derivó %.6f" % drift)

	var monotonic := true
	for index: int in range(1, _integrity_samples.size()):
		if _integrity_samples[index] > _integrity_samples[index - 1] + 1e-6:
			monotonic = false
			break
	expect(monotonic, "city_integrity_changed no es monótona no creciente")
	expect(_integrity_samples.size() > 10,
			"sólo %d muestras de city_integrity_changed" % _integrity_samples.size())
	expect(_integrity.get_ratio() <= 0.001,
			"integridad final %.4f, esperada 0" % _integrity.get_ratio())
	expect(not _integrity_samples.is_empty()
			and _integrity_samples[_integrity_samples.size() - 1] <= 0.001,
			"la última muestra publicada vale %.4f"
			% _integrity_samples[_integrity_samples.size() - 1])
	expect(_defeat_events == 1,
			"defeat_threshold_reached se emitió %d veces, esperada 1" % _defeat_events)
	expect(defeat_seen_at >= 0.0 and defeat_seen_at < DEFEAT_RATIO,
			"la derrota se publicó con integridad %.3f, esperada < %.2f"
			% [defeat_seen_at, DEFEAT_RATIO])
	expect(_destroyed_events.size() == _plan.destructible_count(),
			"building_destroyed llegó %d veces, esperadas %d"
			% [_destroyed_events.size(), _plan.destructible_count()])
	expect(_integrity.get_destroyed_count() == _plan.destructible_count(),
			"get_destroyed_count(): %d" % _integrity.get_destroyed_count())
	var value_total := 0
	for event: Dictionary in _destroyed_events:
		value_total += int(event["value"])
	expect(value_total == expected_value,
			"suma de 'value' publicada: %d, esperada %d" % [value_total, expected_value])
	print("  integridad: %d muestras monótonas, derrota en %.3f, deriva %.6f, valor total %d"
			% [_integrity_samples.size(), defeat_seen_at, drift, value_total])
	print("  emisores: máximo %d plazas tomadas y %d GPUParticles3D emitiendo (tope %d)"
			% [_max_emitters, _max_emitting_nodes, Building.MAX_EMITTERS])


# --------------------------------------------------------------------------
# 24 y 25. Pruebas negativas
# --------------------------------------------------------------------------

## Con el umbral de ruina mal puesto —igual al de daño— el edificio salta de
## `INTACT` a `RUBBLE` y sólo hay **dos** etapas. Si este sub-check no detectara
## la diferencia, los de arriba no estarían midiendo nada.
func _check_negative_threshold() -> void:
	# El pueblo llega arrasado de la fase anterior: hay que devolverlo a INTACT
	# para tener un edificio sano sobre el que montar el perfil roto.
	_reset_city()
	var building := _pick_building(HOUSE_HP)
	if building == null:
		fail("prueba negativa: no quedó ninguna casa intacta")
		return
	var broken := building.profile.duplicate() as BuildingProfile
	broken.rubble_threshold = broken.damaged_threshold
	building.profile = broken
	building.reset()

	var stages: Array[int] = []
	var _s := building.stage_changed.connect(func(stage: Building.Stage) -> void:
		stages.append(int(stage)))
	var steps := 0
	while building.stage != Building.Stage.RUBBLE and steps < 40:
		var _applied := building.take_damage(building.get_max_hp() * 0.05, building.global_position)
		steps += 1
	expect(stages.size() == 1 and stages[0] == int(Building.Stage.RUBBLE),
			"prueba negativa: con rubble_threshold = damaged_threshold se esperaban 2 etapas"
			+ " (INTACT → RUBBLE), se obtuvo %s" % str(stages))
	print("  prueba negativa (etapas): umbral de RUBBLE mal puesto → %d transición, 2 etapas"
			% stages.size())


## Un edificio corrido fuera del círculo de juego tiene que hacer saltar el
## sub-check del círculo.
##
## Es la prueba negativa **de geometría** que WP-D estrena, y la que sostiene que
## el sub-check 3 mida algo: se toma un edificio cualquiera, se lo manda a
## trescientos metros del centro, se vuelven a correr las mismas rutinas que
## aprobaron el pueblo bueno y se exige que **esta vez** encuentren el problema y
## lo nombren. Después se lo devuelve a su sitio y se comprueba que el pueblo
## vuelve a estar limpio.
func _check_negative_play_circle() -> void:
	var buildings := _town.get_buildings()
	if buildings.is_empty():
		fail("prueba negativa: no quedan edificios")
		return
	var victim := buildings[0]
	var rest := victim.position
	victim.position = rest + Vector3(_plan.play_radius + 160.0, 0.0, 0.0)
	var problems := _play_circle_problems()
	var named := false
	for problem: String in problems:
		if problem.contains(victim.name):
			named = true
			break
	expect(not problems.is_empty() and named,
			"prueba negativa: '%s' corrido a %.0f m del centro no hizo saltar el sub-check"
			% [victim.name, _plan.distance_to_centre(victim.position)]
			+ " del círculo (%d avisos)" % problems.size())
	victim.position = rest
	expect(_play_circle_problems().is_empty(),
			"al devolver '%s' a su parcela el círculo sigue dando avisos" % victim.name)
	print("  prueba negativa (círculo): '%s' a %.0f m del centro → %d aviso; devuelto, 0"
			% [victim.name, _plan.play_radius + 160.0, problems.size()])


# --------------------------------------------------------------------------
# 26. Limpieza
# --------------------------------------------------------------------------

## Liberar el pueblo no deja nodos huérfanos ni emisores contados de más.
func _check_cleanup() -> void:
	_pool.clear()
	_field.clear()
	await wait_physics(2)
	var children_before := get_child_count()
	var town := _town
	_town = null
	_plan = null
	_integrity.queue_free()
	_integrity = null
	town.queue_free()
	await wait_frames(3)

	expect(get_tree().get_nodes_in_group(Building.GROUP).is_empty(),
			"quedaron %d nodos en el grupo 'buildings'"
			% get_tree().get_nodes_in_group(Building.GROUP).size())
	expect(get_tree().get_nodes_in_group(&"city_rocks").is_empty(),
			"quedaron rocas en el grupo 'city_rocks'")
	expect(get_tree().get_nodes_in_group(CityGrid.CENTRE_GROUP).is_empty(),
			"quedó un nodo en el grupo '%s'" % CityGrid.CENTRE_GROUP)
	expect(get_tree().get_nodes_in_group(Building.GROUP_UNDER_SIEGE).is_empty(),
			"quedaron edificios marcados bajo asedio")
	expect(get_child_count() == children_before - 2,
			"hijos del check: %d antes, %d después" % [children_before, get_child_count()])
	expect(_pool.get_live_count() == 0, "quedaron %d escombros vivos" % _pool.get_live_count())
	expect(Building.active_emitters() == 0,
			"el presupuesto de emisores quedó en %d" % Building.active_emitters())
	print("  limpieza: 0 edificios, 0 rocas, 0 centros de pueblo, 0 escombros, 0 emisores")


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Resumen final. Corre **después** de la limpieza, así que el plano ya no
## existe: los dos números que salen de él se guardan antes (ver
## [member _destructible] y [member _houses]). Leerlos del plano liberado
## dejaba un `SCRIPT ERROR` al final de cada corrida en verde.
func _print_metrics() -> void:
	print("  métricas: %d destructibles = %d casas (%.0f HP) + %d grandes (%.0f HP) = %.0f HP"
			% [_destructible, _houses, HOUSE_HP, _destructible - _houses, BIG_HP,
			float(_houses) * HOUSE_HP + float(_destructible - _houses) * BIG_HP])
	print("  métricas: derrumbe %.2f s · escombros vivos máx %d · emisores máx %d (%d emitiendo)"
			% [_collapse_seconds, _max_live_debris, _max_emitters, _max_emitting_nodes])
	print("  métricas: %d lotes %s (tope %d)"
			% [_draw_calls if _draw_calls > 0 else _estimated_batches,
			"medidos" if _draw_calls > 0 else "estimados", DRAW_CALL_BUDGET])


## Deja `Global.round_seed` como estaba (`docs/10` §11.2 sub-check 20).
func _restore() -> void:
	expect(Global.round_seed == _seed_before,
			"Global.round_seed cambió de %d a %d" % [_seed_before, Global.round_seed])
	Global.round_seed = _seed_before


## Avanza [param seconds] de simulación en pasos de física, muestreando los
## presupuestos en cada tick.
func _advance(seconds: float) -> void:
	var ticks := maxi(int(seconds * float(Engine.physics_ticks_per_second)), 1)
	for tick: int in ticks:
		await wait_physics(1)
		_sample_budgets()


## Muestrea los dos presupuestos duros: escombros vivos y emisores encendidos.
##
## Los emisores se cuentan **dos veces**: el contador estático de [Building], que
## es el que decide si un derrumbe consigue polvo, y los `GPUParticles3D` del
## árbol que están de verdad en `emitting`. Si los dos números se separan es que
## el contador se desincronizó del mundo, y eso es lo que tiene que saltar.
func _sample_budgets() -> void:
	_max_live_debris = maxi(_max_live_debris, _pool.get_live_count())
	_max_emitters = maxi(_max_emitters, Building.active_emitters())
	if _town == null:
		return
	# La lista de emisores se arma **una vez**. Esto corre en cada tick de varios
	# sub-checks y recorrer los ~1 000 nodos del pueblo cada vez costaba más que
	# lo que mide: los `GPUParticles3D` del pueblo los crea `CityGrid` al sembrar
	# y no aparecen ni desaparecen durante el check.
	if _emitters.is_empty():
		for node: Node in _all_nodes(_town):
			var particles := node as GPUParticles3D
			if particles != null:
				_emitters.append(particles)
	var emitting := 0
	for particles: GPUParticles3D in _emitters:
		if is_instance_valid(particles) and particles.emitting:
			emitting += 1
	_max_emitting_nodes = maxi(_max_emitting_nodes, emitting)
	if emitting > Building.MAX_EMITTERS and _emitter_overflow_reported < 1:
		_emitter_overflow_reported += 1
		fail("%d GPUParticles3D emitiendo a la vez, tope %d"
				% [emitting, Building.MAX_EMITTERS])


## Verdadero cuando todos los [param chunks] están dormidos, congelados o ya
## retirados (`docs/10` §11.2 sub-check 8).
func _chunks_settled(chunks: Array[DebrisChunk]) -> bool:
	for chunk: DebrisChunk in chunks:
		if not is_instance_valid(chunk):
			continue
		if chunk.freeze or chunk.sleeping:
			continue
		if chunk.linear_velocity.length() < 0.25 and chunk.angular_velocity.length() < 0.25:
			continue
		return false
	return true


## Primer edificio intacto con el `max_hp` pedido y las ventanas encendidas, o
## `null`. Ver la nota de [method _check_stages].
func _pick_lit_building(max_hp: float) -> Building:
	for building: Building in _town.get_buildings():
		if building.stage == Building.Stage.INTACT and building.windows_lit() \
				and is_equal_approx(building.get_max_hp(), max_hp):
			return building
	return null


## Primer edificio intacto con el `max_hp` pedido.
func _pick_building(max_hp: float) -> Building:
	for building: Building in _town.get_buildings():
		if building.stage == Building.Stage.INTACT and is_equal_approx(building.get_max_hp(), max_hp):
			return building
	return null


## Devuelve el pueblo a su estado intacto entre fases.
func _reset_city() -> void:
	_integrity.reset()
	_integrity_samples = PackedFloat32Array()
	_destroyed_events.clear()
	_trauma_events.clear()
	_defeat_events = 0


## Material efectivo de la primera malla de la etapa intacta.
func _active_material(building: Building) -> Material:
	var mesh_instance := building.stage_intact as MeshInstance3D
	if mesh_instance == null:
		return null
	return mesh_instance.material_override if mesh_instance.material_override != null \
			else mesh_instance.get_active_material(0)


## Verdadero si **alguna** superficie de la etapa intacta enciende emisivos.
##
## En el distrito rectangular alcanzaba con mirar la superficie 0: las piezas de
## VoxelCity traen una sola. Las casas de paleta del pueblo traen **dos** —la
## opaca y la de las ventanas— y la emisión vive en la segunda, así que mirar la
## primera diría siempre que no hay luz.
func _emission_enabled(building: Building) -> bool:
	var mesh_instance := building.stage_intact as MeshInstance3D
	if mesh_instance == null:
		return false
	if mesh_instance.material_override != null:
		var forced := mesh_instance.material_override as StandardMaterial3D
		return forced != null and forced.emission_enabled \
				and forced.emission_energy_multiplier > 0.0
	if mesh_instance.mesh == null:
		return false
	for surface: int in mesh_instance.mesh.get_surface_count():
		var standard := mesh_instance.get_active_material(surface) as StandardMaterial3D
		if standard != null and standard.emission_enabled \
				and standard.emission_energy_multiplier > 0.0:
			return true
	return false


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
