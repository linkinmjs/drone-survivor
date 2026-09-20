## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-20: verifica la ciudad destructible según `docs/10` §11.2.
##
## Instancia `city/districts/district_a.tscn` y lo maltrata: cuenta los 60
## edificios y su reparto de HP, comprueba que ninguna variación de altura
## escaló un cuerpo físico, recorre las tres etapas de un edificio, cronometra
## un derrumbe completo —escombros incluidos—, derriba diez seguidos para medir
## el tope del pool, arrasa la ciudad para comprobar que la integridad es
## monótona y que la derrota se publica una sola vez, y termina liberando todo
## para que no queden huérfanos.
##
## Cierra con una **prueba negativa**: un perfil con el umbral de ruina mal
## puesto tiene que producir dos etapas en vez de tres, y el check lo detecta.
## Sirve para saber que los sub-checks de etapas miden algo de verdad.
##
## No escribe en `user://` y deja `Global.round_seed` como estaba.
extends CheckRunner

const DISTRICT_PATH: String = "res://city/districts/district_a.tscn"

## Reparto esperado (`docs/10` §4.2).
const EXPECTED_BUILDINGS: int = 60
const EXPECTED_LOW: int = 39
const EXPECTED_TALL: int = 21
const EXPECTED_HP: float = 120000.0
const HP_TOLERANCE: float = 0.05

## Umbrales de etapa (`docs/10` §3.1).
const DAMAGED_THRESHOLD: float = 0.60
const RUBBLE_THRESHOLD: float = 0.15

## Tope de tiempo del derrumbe completo, en segundos (`docs/10` §11.2 #8).
const COLLAPSE_BUDGET: float = 6.0

## Integridad por debajo de la cual se pierde la ronda (`docs/11` §4.1).
const DEFEAT_RATIO: float = 0.35

## Daño de un impacto del jugador sobre la ciudad: `12 × 0.5` (`docs/08` §2.7).
const FRIENDLY_FIRE_DAMAGE: float = 6.0

## Impactos de fuego amigo para derribar un bloque bajo (`docs/10` §8).
const FRIENDLY_FIRE_SHOTS: int = 170

## Ruta del shader que tiene que aparecer en `DAMAGED`.
const DAMAGE_SHADER_PATH: String = "res://city/damage_overlay.gdshader"

var _district: CityGrid = null
var _integrity: CityIntegrity = null
var _pool: DebrisPool = null
var _field: RubbleField = null

var _destroyed_events: Array[Dictionary] = []
var _integrity_samples: PackedFloat32Array = PackedFloat32Array()
var _trauma_events: Array[Dictionary] = []
var _defeat_events: int = 0
var _seed_before: int = 0

var _max_live_debris: int = 0
var _max_emitters: int = 0
var _max_emitting_nodes: int = 0
var _emitter_overflow_reported: int = 0
var _collapse_seconds: float = 0.0
var _collapse_piece: String = ""


func _run() -> void:
	_seed_before = Global.round_seed
	_pool = get_node_or_null(^"DebrisPool") as DebrisPool
	_field = get_node_or_null(^"DebrisPool/RubbleField") as RubbleField
	if _pool == null or _field == null:
		fail("la escena del check no trae DebrisPool ni RubbleField")
		return

	if not ResourceLoader.exists(DISTRICT_PATH):
		fail("falta '%s'; generalo con tools/build_district.gd" % DISTRICT_PATH)
		return
	_district = (ResourceLoader.load(DISTRICT_PATH, "PackedScene") as PackedScene).instantiate() as CityGrid
	if _district == null:
		fail("la raíz de '%s' no es un CityGrid" % DISTRICT_PATH)
		return
	add_child(_district)

	_integrity = CityIntegrity.new()
	_integrity.name = "CityIntegrity"
	_integrity.grid = _district
	add_child(_integrity)
	await wait_physics(2)

	_connect_bus()

	_check_building_count()
	_check_hp_mix()
	_check_grid_layout()
	_check_no_body_scale()
	_check_props_on_roof()
	_check_street_batching()
	_check_rocks_and_ground()
	_check_debris_profiles()

	await _check_stages()
	await _check_friendly_fire()
	await _check_collapse_time()
	await _check_siege()
	await _check_debris_cap()
	await _check_integrity_run()
	_check_negative_threshold()
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
# 1–3. Cuenta, HP y reparto
# --------------------------------------------------------------------------

## 1. Sesenta `Building`, todos en el grupo `buildings`.
func _check_building_count() -> void:
	var buildings := _district.get_buildings()
	expect(buildings.size() == EXPECTED_BUILDINGS,
			"edificios: %d, esperados %d" % [buildings.size(), EXPECTED_BUILDINGS])
	expect(_district.building_count() == EXPECTED_BUILDINGS,
			"building_count(): %d, esperado %d" % [_district.building_count(), EXPECTED_BUILDINGS])
	var grouped := get_tree().get_nodes_in_group(Building.GROUP).size()
	expect(grouped == EXPECTED_BUILDINGS,
			"nodos en el grupo '%s': %d, esperados %d" % [Building.GROUP, grouped, EXPECTED_BUILDINGS])
	for building: Building in buildings:
		if building.profile == null:
			fail("'%s' no tiene perfil" % building.name)
			return


## 2 y 3. HP total dentro de ±5 % de 120 000 y reparto 39 bajos + 21 torres.
func _check_hp_mix() -> void:
	var low := 0
	var tall := 0
	var total := 0.0
	for building: Building in _district.get_buildings():
		total += building.get_max_hp()
		if is_equal_approx(building.get_max_hp(), 3500.0):
			tall += 1
		elif is_equal_approx(building.get_max_hp(), 1200.0):
			low += 1
		else:
			fail("'%s' tiene max_hp %.0f, que no es ni 1200 ni 3500"
					% [building.name, building.get_max_hp()])
	expect(low == EXPECTED_LOW, "bloques bajos: %d, esperados %d" % [low, EXPECTED_LOW])
	expect(tall == EXPECTED_TALL, "torres: %d, esperadas %d" % [tall, EXPECTED_TALL])
	var low_bound := EXPECTED_HP * (1.0 - HP_TOLERANCE)
	var high_bound := EXPECTED_HP * (1.0 + HP_TOLERANCE)
	expect(total >= low_bound and total <= high_bound,
			"HP total %.0f fuera de [%.0f, %.0f]" % [total, low_bound, high_bound])
	expect_near(_integrity.get_initial_hp(), total, 0.5,
			"CityIntegrity.get_initial_hp() no coincide con la suma de perfiles")


## 4. Rejilla: extensión declarada, ningún edificio en celda de calle y una
## separación mínima entre centros de una celda.
func _check_grid_layout() -> void:
	var extent := _district.get_extent()
	expect_near(extent.x, float(_district.get_cols()) * _district.cell_size, 0.01,
			"extensión en X")
	expect_near(extent.y, float(_district.get_rows()) * _district.cell_size, 0.01,
			"extensión en Z")
	var seen: Dictionary[Vector2i, bool] = {}
	for building: Building in _district.get_buildings():
		var cell: Vector2i = building.get_meta(&"cell", Vector2i(-1, -1))
		if _district.is_street_cell(cell):
			fail("'%s' está en la celda de calle %s" % [building.name, str(cell)])
		if seen.has(cell):
			fail("dos edificios en la celda %s" % str(cell))
		seen[cell] = true
		var expected := _district.cell_position(cell)
		expect(building.position.distance_to(expected) < 0.01,
				"'%s' no está en el centro de su celda" % building.name)
	expect(seen.size() == EXPECTED_BUILDINGS,
			"celdas ocupadas: %d, esperadas %d" % [seen.size(), EXPECTED_BUILDINGS])


## 5. Ningún cuerpo escalado; toda la variación de altura vive en la malla y en
## el `BoxShape3D` (`docs/03` prohíbe escalar cuerpos físicos).
func _check_no_body_scale() -> void:
	for building: Building in _district.get_buildings():
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


## 5b. Los props de azotea apoyan sobre el techo real: su altura local es
## `get_height()` (la de reposo, `base_size.y`, escalada por `height_scale`) y
## `Building` dejó la posición de reposo en `PROP_REST_META`. Regresión del cartel
## que flotaba sobre las torres de `district_a` (WP-21 lo vio a decenas de metros).
## Imprime además cuánto sobresale o se hunde la malla respecto del techo, para
## calibrar el pivote de las piezas FBX.
func _check_props_on_roof() -> void:
	var props_seen := 0
	var worst_gap := 0.0
	for building: Building in _district.get_buildings():
		if building.props == null:
			continue
		var roof_y := building.global_position.y + building.get_height()
		for child: Node in building.props.get_children():
			var prop := child as Node3D
			if prop == null:
				continue
			props_seen += 1
			expect_near(prop.position.y, building.get_height(), 0.05,
					"'%s/%s': el prop está a %.2f m y el techo a %.2f m"
					% [building.name, prop.name, prop.position.y, building.get_height()])
			expect(prop.has_meta(Building.PROP_REST_META),
					"'%s/%s' no guarda la posición de reposo" % [building.name, prop.name])
			var rest: Variant = prop.get_meta(Building.PROP_REST_META, Vector3.ZERO)
			expect(rest is Vector3 and absf((rest as Vector3).y - building.base_size.y) < 0.05,
					"'%s/%s': posición de reposo %s, esperada y = %.2f"
					% [building.name, prop.name, str(rest), building.base_size.y])
			var bottom := _visual_bottom(prop)
			if is_finite(bottom):
				worst_gap = maxf(worst_gap, absf(bottom - roof_y))
	expect(props_seen >= 12, "props de azotea encontrados: %d, esperados al menos 12" % props_seen)
	print("  props de azotea: %d; mayor desvío entre la base de la malla y el techo: %.2f m"
			% [props_seen, worst_gap])


## Cota inferior (en Y global) de las mallas de [param root]; `INF` si no tiene.
func _visual_bottom(root: Node3D) -> float:
	var bottom := INF
	var pending: Array[Node] = [root]
	var index := 0
	while index < pending.size():
		var node := pending[index]
		index += 1
		for child: Node in node.get_children():
			pending.append(child)
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var aabb := mesh.global_transform * mesh.mesh.get_aabb()
		bottom = minf(bottom, aabb.position.y)
	return bottom


## 18. Tres `MultiMeshInstance3D` para calzada y veredas, sin colisionadores
## propios de calle.
func _check_street_batching() -> void:
	var streets := _district.get_node_or_null(NodePath(CityGrid.STREETS_NODE))
	if streets == null:
		fail("el distrito no tiene el nodo '%s'" % CityGrid.STREETS_NODE)
		return
	var multis := 0
	var instances := 0
	var bodies := 0
	for node: Node in _all_nodes(streets):
		var multi := node as MultiMeshInstance3D
		if multi != null:
			multis += 1
			instances += multi.multimesh.instance_count
		if node is PhysicsBody3D:
			bodies += 1
	expect(multis == 3, "MultiMeshInstance3D de calle: %d, esperados 3" % multis)
	expect(bodies == 0, "la red viaria trae %d colisionadores propios" % bodies)
	expect(instances > 0, "los MultiMesh de calle están vacíos")
	print("  calles: 3 MultiMesh con %d instancias y 0 colisionadores" % instances)


## 16. Seis rocas en `city_rocks` con casco convexo en capa 1, y una sola caja
## de suelo que cubre el distrito con la cara superior en `y = 0`.
func _check_rocks_and_ground() -> void:
	var rocks := get_tree().get_nodes_in_group(&"city_rocks")
	expect(rocks.size() == 6, "rocas en 'city_rocks': %d, esperadas 6" % rocks.size())
	for node: Node in rocks:
		var body := node as StaticBody3D
		if body == null:
			fail("'%s' del grupo city_rocks no es un StaticBody3D" % node.name)
			continue
		expect(body.collision_layer == PhysicsLayers.WORLD,
				"la roca '%s' está en la capa %d, esperada 1" % [body.name, body.collision_layer])
		var convex := 0
		var height := 0.0
		for child: Node in _all_nodes(body):
			var shape_node := child as CollisionShape3D
			if shape_node != null and shape_node.shape is ConvexPolygonShape3D:
				convex += 1
			var mesh_instance := child as MeshInstance3D
			if mesh_instance != null and mesh_instance.mesh != null:
				height = maxf(height, mesh_instance.mesh.get_aabb().size.y)
		expect(convex == 1, "la roca '%s' tiene %d formas convexas, esperada 1" % [body.name, convex])
		expect(height >= 18.0 and height <= 40.0,
				"la roca '%s' mide %.1f m, fuera de 18–40 m" % [body.name, height])

	var ground := _district.get_node_or_null(NodePath(CityGrid.GROUND_NODE)) as StaticBody3D
	if ground == null:
		fail("el distrito no tiene la caja de suelo '%s'" % CityGrid.GROUND_NODE)
		return
	expect(ground.collision_layer == PhysicsLayers.WORLD,
			"el suelo está en la capa %d, esperada 1" % ground.collision_layer)
	var shape_node := ground.get_node_or_null(^"Shape") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	if box == null:
		fail("el suelo no tiene BoxShape3D")
		return
	var extent := _district.get_extent()
	expect(box.size.x >= extent.x and box.size.z >= extent.y,
			"la caja de suelo (%.0f × %.0f) no cubre el distrito (%.0f × %.0f)"
			% [box.size.x, box.size.z, extent.x, extent.y])
	var top := shape_node.position.y + box.size.y * 0.5
	expect_near(top, 0.0, 0.01, "la cara superior del suelo no está en y = 0")


## Los dos perfiles comparten como mucho dos mallas de escombro, porque el
## `RubbleField` sólo admite cuatro campos y los enemigos reservan dos.
func _check_debris_profiles() -> void:
	var meshes: Dictionary[Mesh, bool] = {}
	for building: Building in _district.get_buildings():
		if building.profile.debris_mesh == null:
			fail("'%s' no tiene malla de escombro" % building.name)
			continue
		meshes[building.profile.debris_mesh] = true
		expect(building.profile.debris_shape != null,
				"'%s' no tiene forma de escombro" % building.name)
	expect(meshes.size() <= 2,
			"la ciudad registra %d mallas de escombro, tope 2" % meshes.size())


# --------------------------------------------------------------------------
# 6, 7 y 19. Etapas
# --------------------------------------------------------------------------

## 6 y 7. Daño progresivo sobre un bloque bajo: `DAMAGED` al cruzar 0.60,
## `RUBBLE` al cruzar 0.15, shader puesto, emisivos apagados, `hp = 0`, inmune y
## conmutación de formas al terminar el derrumbe.
func _check_stages() -> void:
	var building := _pick_building(1200.0)
	if building == null:
		fail("no hay ningún bloque bajo para probar las etapas")
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
		expect(overlay.shader != null and overlay.shader.resource_path == DAMAGE_SHADER_PATH,
				"el material de daño no usa '%s'" % DAMAGE_SHADER_PATH)
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


## 19. Fuego amigo: 170 impactos de 6 HP derriban un bloque bajo (`docs/10` §8).
func _check_friendly_fire() -> void:
	var building := _pick_building(1200.0)
	if building == null:
		return
	# El acumulador va dentro de un `Array`: GDScript captura los locales de una
	# lambda **por valor**, así que sumar sobre un `float` capturado no saldría
	# nunca de la lambda.
	var registered: Array[float] = [0.0]
	var _c := building.damage_taken.connect(func(amount: float, _p: Vector3) -> void:
		registered[0] += amount)
	var point := building.global_position + Vector3(0.0, 4.0, 0.0)
	for shot: int in FRIENDLY_FIRE_SHOTS:
		var _applied := building.take_damage(FRIENDLY_FIRE_DAMAGE, point)
	expect(building.stage == Building.Stage.RUBBLE,
			"tras %d impactos de %.0f HP el bloque sigue en etapa %d"
			% [FRIENDLY_FIRE_SHOTS, FRIENDLY_FIRE_DAMAGE, int(building.stage)])
	expect_near(registered[0], building.get_max_hp(), 0.5,
			"el daño registrado no coincide con el HP nominal del bloque")
	print("  fuego amigo: %d × %.0f HP derriban un bloque bajo (%.0f HP registrados)"
			% [FRIENDLY_FIRE_SHOTS, FRIENDLY_FIRE_DAMAGE, registered[0]])
	await _advance(building.profile.collapse_seconds + 0.2)
	_reset_city()


## 8. Derrumbe completo —etapa, formas y escombros quietos— en menos de 6 s.
func _check_collapse_time() -> void:
	var building := _pick_building(3500.0)
	if building == null:
		fail("no hay ninguna torre para cronometrar el derrumbe")
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
	expect(building.is_collapsed(), "la torre no terminó de derrumbarse")
	expect(elapsed < COLLAPSE_BUDGET,
			"el derrumbe completo tardó %.2f s, tope %.1f s" % [elapsed, COLLAPSE_BUDGET])
	print("  derrumbe completo de '%s' (%.1f m): %.2f s con %d escombros"
			% [_collapse_piece, building.get_height(), elapsed, chunks.size()])
	_reset_city()


# --------------------------------------------------------------------------
# 11. Asedio
# --------------------------------------------------------------------------

## El grupo `buildings_under_siege` tiene un único miembro mientras hay daño
## sostenido, y queda vacío tras `siege_window` segundos sin recibir más.
func _check_siege() -> void:
	var building := _pick_building(3500.0)
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
# 12 y 13. Escombros
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
	# Cinco bloques bajos y cinco torres: así se registran las **dos** mallas de
	# escombro de la ciudad y el tope de campos del `RubbleField` se mide de
	# verdad (`docs/10` §6 reserva 2 campos para la ciudad y 2 para los enemigos).
	var queue: Array[Building] = []
	for max_hp: float in [1200.0, 3500.0]:
		var taken := 0
		for building: Building in _district.get_buildings():
			if taken >= 5:
				break
			if building.stage == Building.Stage.INTACT 					and is_equal_approx(building.get_max_hp(), max_hp) 					and not queue.has(building):
				queue.append(building)
				taken += 1
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
			"campos del RubbleField tras derribar bloques y torres: %d, esperados 2"
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
# 9, 10 y 11. Integridad
# --------------------------------------------------------------------------

## Arrasa la ciudad y verifica que la integridad es monótona no creciente, que
## el acumulador no deriva, que la derrota se publica una sola vez al cruzar
## 0.35 y que el valor final es 0.
func _check_integrity_run() -> void:
	_integrity_samples = PackedFloat32Array()
	_destroyed_events.clear()
	_defeat_events = 0
	var buildings := _district.get_buildings()
	var drift := 0.0
	var checkpoints := 0
	var defeat_seen_at := -1.0

	for index: int in buildings.size():
		var building := buildings[index]
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
	expect(_integrity_samples[_integrity_samples.size() - 1] <= 0.001,
			"la última muestra publicada vale %.4f" % _integrity_samples[_integrity_samples.size() - 1])
	expect(_defeat_events == 1,
			"defeat_threshold_reached se emitió %d veces, esperada 1" % _defeat_events)
	expect(defeat_seen_at >= 0.0 and defeat_seen_at < DEFEAT_RATIO,
			"la derrota se publicó con integridad %.3f, esperada < %.2f"
			% [defeat_seen_at, DEFEAT_RATIO])
	expect(_destroyed_events.size() == EXPECTED_BUILDINGS,
			"building_destroyed llegó %d veces, esperadas %d"
			% [_destroyed_events.size(), EXPECTED_BUILDINGS])
	expect(_integrity.get_destroyed_count() == EXPECTED_BUILDINGS,
			"get_destroyed_count(): %d" % _integrity.get_destroyed_count())
	var value_total := 0
	for event: Dictionary in _destroyed_events:
		value_total += int(event["value"])
	expect(value_total == EXPECTED_LOW * 100 + EXPECTED_TALL * 300,
			"suma de 'value' publicada: %d, esperada %d"
			% [value_total, EXPECTED_LOW * 100 + EXPECTED_TALL * 300])
	print("  integridad: %d muestras monótonas, derrota en %.3f, deriva %.6f, valor total %d"
			% [_integrity_samples.size(), defeat_seen_at, drift, value_total])
	print("  emisores: máximo %d plazas tomadas y %d GPUParticles3D emitiendo (tope %d)"
			% [_max_emitters, _max_emitting_nodes, Building.MAX_EMITTERS])


# --------------------------------------------------------------------------
# Prueba negativa
# --------------------------------------------------------------------------

## Con el umbral de ruina mal puesto —igual al de daño— el edificio salta de
## `INTACT` a `RUBBLE` y sólo hay **dos** etapas. Si este sub-check no detectara
## la diferencia, los de arriba no estarían midiendo nada.
func _check_negative_threshold() -> void:
	# La ciudad llega arrasada de la fase anterior: hay que devolverla a INTACT
	# para tener un edificio sano sobre el que montar el perfil roto.
	_reset_city()
	var building := _pick_building(1200.0)
	if building == null:
		fail('prueba negativa: no quedó ningún bloque bajo intacto')
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
	print("  prueba negativa: umbral de RUBBLE mal puesto → %d transición, 2 etapas" % stages.size())


# --------------------------------------------------------------------------
# Limpieza
# --------------------------------------------------------------------------

## 20. Liberar el distrito no deja nodos huérfanos ni emisores contados de más.
func _check_cleanup() -> void:
	_pool.clear()
	_field.clear()
	await wait_physics(2)
	var children_before := get_child_count()
	var district := _district
	_district = null
	_integrity.queue_free()
	_integrity = null
	district.queue_free()
	await wait_frames(3)

	expect(get_tree().get_nodes_in_group(Building.GROUP).is_empty(),
			"quedaron %d nodos en el grupo 'buildings'"
			% get_tree().get_nodes_in_group(Building.GROUP).size())
	expect(get_tree().get_nodes_in_group(&"city_rocks").is_empty(),
			"quedaron rocas en el grupo 'city_rocks'")
	expect(get_tree().get_nodes_in_group(Building.GROUP_UNDER_SIEGE).is_empty(),
			"quedaron edificios marcados bajo asedio")
	expect(get_child_count() == children_before - 2,
			"hijos del check: %d antes, %d después" % [children_before, get_child_count()])
	expect(_pool.get_live_count() == 0, "quedaron %d escombros vivos" % _pool.get_live_count())
	expect(Building.active_emitters() == 0,
			"el presupuesto de emisores quedó en %d" % Building.active_emitters())
	print("  limpieza: 0 edificios, 0 rocas, 0 escombros, 0 emisores ocupados")


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

func _print_metrics() -> void:
	print("  métricas: 60 edificios = %d bajos (1 200 HP) + %d torres (3 500 HP) = 120 300 HP"
			% [EXPECTED_LOW, EXPECTED_TALL])
	print("  métricas: derrumbe %.2f s · escombros vivos máx %d · emisores máx %d (%d emitiendo)"
			% [_collapse_seconds, _max_live_debris, _max_emitters, _max_emitting_nodes])


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
	if _district == null:
		return
	var emitting := 0
	for node: Node in _all_nodes(_district):
		var particles := node as GPUParticles3D
		if particles != null and particles.emitting:
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


## Primer edificio intacto con el `max_hp` pedido.
func _pick_building(max_hp: float) -> Building:
	for building: Building in _district.get_buildings():
		if building.stage == Building.Stage.INTACT and is_equal_approx(building.get_max_hp(), max_hp):
			return building
	return null


## Devuelve la ciudad a su estado intacto entre fases.
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


## Verdadero si el material efectivo enciende emisivos.
func _emission_enabled(building: Building) -> bool:
	var standard := _active_material(building) as StandardMaterial3D
	return standard != null and standard.emission_enabled


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found
