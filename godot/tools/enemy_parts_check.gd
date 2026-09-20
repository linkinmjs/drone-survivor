## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de WP-16: verifica el framework de enemigos de `docs/06` §16.1 sobre el
## Arachnodroid real (`docs/07` §13, criterios 1, 2, 5, 6, 10, 11 y 13).
##
## Instancia el jefe sobre un suelo sintético y comprueba, en una sola pasada:
##
## 1. El grafo: tantas [EnemyPart] como declara `metadata.part_count` del
##    sidecar, con la jerarquía del `parts.json` y un [WeakPoint] por
##    `weak_point_id` distinto.
## 2. Los metadatos propagados al colisionador (`part_id`, `weak_point_id` y
##    `enemy_part`, que es lo que `docs/08` resuelve en O(1)).
## 3. Las capas iniciales: rodillas en la 4 y en el grupo `weak_points`; visor y
##    núcleos en la 3 y fuera del grupo.
## 4. El daño con blindaje y el multiplicador de punto débil, que el arma aplica
##    y la parte **no** vuelve a aplicar.
## 5. `total_structure_ratio()` sobre los 12 000 HP de puntos débiles.
## 6. El desprendimiento: un chunk por pata, con sus hijos, en la capa 9.
## 7. Las cinco fases en orden y la exposición del núcleo ventral.
## 8. El tope del pool, el congelado y el horneado en el [RubbleField].
## 9. El movedor cinemático: ≤ 0.6 m/tick y ≤ `turn_rate` grados por segundo.
## 10. Que no queden nodos huérfanos al liberar la escena.
##
## Todas las cifras del modelo salen del sidecar; las del balance, del
## `EnemyProfile`. El check no codifica ni el número de partes ni los HP.
extends CheckRunner

const ENEMY_ID: StringName = &"arachnodroid"
const SIDECAR: String = "res://enemies/arachnodroid/arachnodroid.parts.json"

## Rodillas en el orden en el que se rompen; cada una arrastra su fémur.
const KNEES: Array[StringName] = [
	&"wp_leg_fl_knee", &"wp_leg_fr_knee", &"wp_leg_bl_knee", &"wp_leg_br_knee",
]

## Núcleos ventrales, en el orden en el que se rompen.
const CORES: Array[StringName] = [&"wp_core_a", &"wp_core_b", &"wp_core_c"]

## Ids de fase esperados, en orden (`docs/07` §6).
const PHASES: Array[StringName] = [
	&"p1_siege", &"p2_alert", &"p3_fury", &"p4_belly", &"p5_selfdestruct",
]

## Daño de un disparo del arma (`docs/08` §2.7).
## Suma del HP de los ocho puntos débiles (`docs/07` §4), que es el denominador
## de `total_structure_ratio()`: `4 · 1600` de rodillas + `1500` del visor +
## `3 · 1900` de núcleos. Subió de 12 000 a 13 600 al recalibrar las rodillas en
## WP-23.
const WEAK_POINT_BUDGET: float = 13600.0

const SHOT_DAMAGE: float = 12.0

## Multiplicador que el arma aplica a un punto débil expuesto.
const WEAK_MULTIPLIER: float = 3.0

## Máscara que debe llevar un escombro: capas 1, 2, 8 y 9 (`docs/02` §3.1).
const DEBRIS_MASK: int = 387

## Tolerancia de las comparaciones de daño.
const DAMAGE_TOLERANCE: float = 0.01

var _pool: DebrisPool = null
var _field: RubbleField = null
var _muzzle: Marker3D = null
var _enemy: EnemyBase = null

var _spawned: Array[StringName] = []
var _broken_events: Array[StringName] = []
var _phase_events: Array[StringName] = []
var _defeated_events: Array[StringName] = []
var _exposure_events: Array[Dictionary] = []
var _trauma_events: int = 0


func _run() -> void:
	_pool = get_node_or_null(^"DebrisPool") as DebrisPool
	_field = get_node_or_null(^"DebrisPool/RubbleField") as RubbleField
	_muzzle = get_node_or_null(^"Muzzle") as Marker3D
	if _pool == null or _field == null or _muzzle == null:
		fail("la escena del check no tiene DebrisPool, RubbleField o Muzzle")
		return
	_pool.rubble_field = _field
	_listen()
	await wait_frames(1)

	var sidecar := _read_sidecar()
	if sidecar.is_empty():
		return

	var nodes_before := get_tree().get_node_count()
	var children_before := get_tree().root.get_child_count()

	_enemy = _spawn()
	if _enemy == null:
		return
	await wait_physics(2)

	_check_catalog()
	_check_graph(sidecar)
	_check_collider_metadata()
	_check_initial_exposure()
	_check_structure_budget()
	_check_damage()
	_check_visor_while_attack()
	_check_move_body()
	_check_negative()
	await _check_breaking()
	await _check_pool_limits()
	await _check_cleanup(nodes_before, children_before)


# --------------------------------------------------------------------------
# Construcción
# --------------------------------------------------------------------------

## Conecta los hechos del bus que este check audita (`docs/02` §5.1).
func _listen() -> void:
	var _spawn_discard := Events.enemy_spawned.connect(_on_spawned)
	var _break_discard := Events.enemy_part_broken.connect(_on_part_broken)
	var _phase_discard := Events.enemy_phase_changed.connect(_on_phase_changed)
	var _weak_discard := Events.enemy_weak_point_state.connect(_on_weak_point_state)
	var _defeat_discard := Events.enemy_defeated.connect(_on_defeated)
	var _trauma_discard := Events.camera_trauma.connect(_on_trauma)


## Instancia el jefe desde el catálogo, con el pool del check ya cableado.
func _spawn() -> EnemyBase:
	var packed := EnemyCatalog.scene_of(ENEMY_ID)
	if packed == null:
		fail("EnemyCatalog no devolvió la escena de '%s'" % ENEMY_ID)
		return null
	var enemy := packed.instantiate() as EnemyBase
	if enemy == null:
		fail("la escena de '%s' no es un EnemyBase" % ENEMY_ID)
		return null
	enemy.debris_pool = _pool
	enemy.rubble_field = _field
	add_child(enemy)
	return enemy


## Lee el sidecar del modelo: es la fuente de verdad de partes y jerarquía.
func _read_sidecar() -> Dictionary:
	if not FileAccess.file_exists(SIDECAR):
		fail("no existe '%s'" % SIDECAR)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIDECAR))
	var data := parsed as Dictionary
	if data == null:
		fail("'%s' no es un objeto JSON válido" % SIDECAR)
		return {}
	return data


# --------------------------------------------------------------------------
# Criterios
# --------------------------------------------------------------------------

## El catálogo resuelve escena, perfil y clave de traducción.
func _check_catalog() -> void:
	expect(EnemyCatalog.has_id(ENEMY_ID), "EnemyCatalog no conoce '%s'" % ENEMY_ID)
	expect(EnemyCatalog.profile_of(ENEMY_ID) != null,
			"EnemyCatalog.profile_of('%s') devolvió null" % ENEMY_ID)
	expect(EnemyCatalog.display_key(ENEMY_ID) == "ENEMY_ARACHNODROID",
			"EnemyCatalog.display_key('%s') vale '%s'" \
			% [ENEMY_ID, EnemyCatalog.display_key(ENEMY_ID)])
	expect(_spawned.has(ENEMY_ID),
			"no se emitió Events.enemy_spawned con el id '%s'" % ENEMY_ID)
	expect(_enemy.is_in_group(&"enemies"), "el enemigo no entró en el grupo 'enemies'")


## Criterio 1: el grafo reproduce el `parts.json` exactamente.
func _check_graph(sidecar: Dictionary) -> void:
	var metadata := sidecar.get("metadata", {}) as Dictionary
	var declared := int(metadata.get("part_count", -1))
	var parts := _enemy.get_parts()
	expect(parts.size() == declared,
			"EnemyPart construidas: %d, esperadas %d (metadata.part_count)" \
			% [parts.size(), declared])

	var parents: Dictionary[StringName, StringName] = {}
	var weak_ids: Dictionary[StringName, bool] = {}
	for raw: Variant in sidecar.get("parts", []) as Array:
		var entry := raw as Dictionary
		var part_id := StringName(String(entry.get("id", "")))
		# La parte raíz trae `parent: null` en el JSON.
		var raw_parent: Variant = entry.get("parent", null)
		parents[part_id] = StringName(String(raw_parent)) if raw_parent != null else &""
		var weak_id := StringName(String(entry.get("weak_point_id", "")))
		if weak_id != &"":
			weak_ids[weak_id] = true

	for part_id: StringName in parents:
		var part := _enemy.get_part(part_id)
		if part == null:
			fail("falta la EnemyPart '%s' que declara el sidecar" % part_id)
			continue
		var found := part.parent_part.part_id if part.parent_part != null else &""
		expect(found == parents[part_id],
				"'%s' cuelga de '%s', el sidecar dice '%s'" % [part_id, found, parents[part_id]])
		expect(part.body != null, "'%s' no tiene colisionador" % part_id)
		expect(not part.invalid, "'%s' quedó marcada como inválida" % part_id)

	var weak_points := _enemy.get_weak_points()
	expect(weak_points.size() == weak_ids.size(),
			"WeakPoint construidos: %d, esperados %d (weak_point_id distintos del sidecar)" \
			% [weak_points.size(), weak_ids.size()])
	for weak_id: StringName in weak_ids:
		expect(_enemy.get_weak_point(weak_id) != null,
				"falta el WeakPoint '%s'" % weak_id)

	# Las patas se agruparon con fémur, tibia y pie (`docs/06` §2.1 punto 6).
	var legs := _enemy.get_legs()
	expect(legs.size() == 4, "patas agrupadas: %d, esperadas 4" % legs.size())
	for leg: Dictionary in legs:
		var segments := leg["segments"] as Array
		expect(segments.size() == 2,
				"la pata '%s' tiene %d segmentos, esperados 2" % [leg["prefix"], segments.size()])
		expect(leg["foot"] != null, "la pata '%s' no tiene pie" % leg["prefix"])
	print("  grafo: %d partes, %d puntos débiles, %d patas" \
			% [parts.size(), weak_points.size(), legs.size()])


## Criterio 2: el colisionador lleva `part_id`, `weak_point_id` y `enemy_part`.
func _check_collider_metadata() -> void:
	var wrong := 0
	for part: EnemyPart in _enemy.get_parts():
		if part.body == null:
			continue
		var meta_id := StringName(part.body.get_meta(&"part_id", ""))
		var meta_weak := StringName(part.body.get_meta(&"weak_point_id", ""))
		var meta_part := part.body.get_meta(&"enemy_part", null) as EnemyPart
		if meta_id != part.part_id or meta_weak != part.weak_point_id or meta_part != part:
			wrong += 1
			fail("metadatos mal propagados al cuerpo de '%s'" % part.part_id)
		if part.mesh.get_meta(&"enemy_part", null) != part:
			wrong += 1
			fail("la malla de '%s' no apunta a su EnemyPart" % part.part_id)
	print("  metadatos del colisionador: %d partes, %d errores" \
			% [_enemy.get_parts().size(), wrong])


## Criterio 3: capas y grupo iniciales según la exposición declarada.
func _check_initial_exposure() -> void:
	for knee_id: StringName in KNEES:
		var knee := _enemy.get_weak_point(knee_id)
		if knee == null:
			continue
		expect(knee.is_exposed(), "'%s' debería estar expuesta (ALWAYS)" % knee_id)
		_expect_layer(knee, PhysicsLayers.ENEMY_WEAK, true)
	var visor := _enemy.get_weak_point(&"wp_head_visor")
	if visor != null:
		expect(not visor.is_exposed(), "el visor no debería estar expuesto sin ataque en curso")
		_expect_layer(visor, PhysicsLayers.ENEMY_BODY, false)
	for core_id: StringName in CORES:
		var core := _enemy.get_weak_point(core_id)
		if core == null:
			continue
		expect(not core.is_exposed(), "'%s' no debería estar expuesto con 0 rodillas rotas" % core_id)
		_expect_layer(core, PhysicsLayers.ENEMY_BODY, false)
	print("  exposición inicial: 4 rodillas en la capa 4 (bit %d) y en el grupo; visor y 3 núcleos en la capa 3 (bit %d)" \
			% [PhysicsLayers.ENEMY_WEAK, PhysicsLayers.ENEMY_BODY])


## Criterio 5: los 12 000 HP de integridad salen sólo de los puntos débiles.
func _check_structure_budget() -> void:
	var weighted := 0.0
	var armored := 0
	for part: EnemyPart in _enemy.get_parts():
		weighted += part.max_hp * part.structure_weight
		if part.structure_weight <= 0.0:
			armored += 1
	var weak_total := 0.0
	for weak_point: WeakPoint in _enemy.get_weak_points():
		weak_total += weak_point.part.max_hp
	expect_near(weighted, weak_total, 0.01,
			"la integridad debería contar sólo los puntos débiles")
	# **12 000 → 13 600 (WP-23).** El balance subió el HP de las cuatro rodillas de
	# 1 200 a 1 600 —la palanca de duración de `docs/07` §14— así que el
	# presupuesto pasa a `4·1600 + 1500 + 3·1900`. `docs/07` §4 y §8 quedan por
	# recalcular.
	expect_near(weighted, WEAK_POINT_BUDGET, 0.01, "presupuesto de integridad (docs/07 §4)")
	expect(armored == _enemy.get_parts().size() - _enemy.get_weak_points().size(),
			"partes con structure_weight 0: %d, esperadas %d" \
			% [armored, _enemy.get_parts().size() - _enemy.get_weak_points().size()])
	expect_near(_enemy.total_structure_ratio(), 1.0, 0.0001,
			"total_structure_ratio() de un jefe intacto")
	print("  integridad: %.0f HP ponderados, %d partes blindadas con peso 0" % [weighted, armored])


## Criterio 4: blindaje y multiplicador de punto débil (`docs/06` §16.1 #2).
func _check_damage() -> void:
	var hull := _enemy.get_part(&"hull")
	var carapace := _enemy.get_part(&"carapace")
	var knee := _enemy.get_part(&"wp_leg_fl_knee")
	if hull == null or carapace == null or knee == null:
		fail("faltan partes para la prueba de daño")
		return

	# `docs/07` §3 le da al casco `armor 0.92`, no el 0.90 genérico de `docs/06`
	# §4: 12 · (1 − 0.92) = 0.96. Se verifican los dos blindajes por separado.
	var hull_hp := hull.hp
	var hull_damage := hull.take_damage(SHOT_DAMAGE, _hit(hull.world_position(), false, &""))
	expect_near(hull_damage, SHOT_DAMAGE * (1.0 - hull.armor), DAMAGE_TOLERANCE,
			"daño efectivo al casco con armor %.2f" % hull.armor)
	expect_near(hull_hp - hull.hp, hull_damage, DAMAGE_TOLERANCE,
			"el casco descontó exactamente el daño efectivo")

	var carapace_damage := carapace.take_damage(SHOT_DAMAGE,
			_hit(carapace.world_position(), false, &""))
	expect_near(carapace.armor, 0.90, 0.0001, "blindaje de la carcasa")
	expect_near(carapace_damage, 1.2, DAMAGE_TOLERANCE,
			"daño efectivo con blindaje 0.90 (docs/06 §4)")

	# El arma ya aplicó el ×3: la parte débil no vuelve a multiplicar.
	var weak_point := _enemy.get_weak_point(&"wp_leg_fl_knee")
	expect_near(weak_point.damage_multiplier(), WEAK_MULTIPLIER, 0.0001,
			"multiplicador del punto débil")
	expect_near(knee.armor, 0.0, 0.0001, "la rodilla debe tener armor 0.0")
	var knee_hp := knee.hp
	var knee_damage := knee.take_damage(SHOT_DAMAGE * WEAK_MULTIPLIER,
			_hit(knee.world_position(), true, &"wp_leg_fl_knee"))
	expect_near(knee_damage, 36.0, DAMAGE_TOLERANCE, "daño efectivo a la rodilla")
	expect_near(knee_hp - knee.hp, 36.0, DAMAGE_TOLERANCE, "la rodilla restó 36")

	var expected_ratio := (WEAK_POINT_BUDGET - 36.0) / WEAK_POINT_BUDGET
	expect_near(_enemy.total_structure_ratio(), expected_ratio, 0.0001,
			"la integridad bajó sólo por el punto débil")
	print("  daño: casco %.2f (armor %.2f) · carcasa %.2f (armor %.2f) · rodilla %.2f" \
			% [hull_damage, hull.armor, carapace_damage, carapace.armor, knee_damage])


## Criterio 6 de `docs/07` §13: el visor sólo baja a capa 4 mientras hay ataque.
func _check_visor_while_attack() -> void:
	var visor := _enemy.get_weak_point(&"wp_head_visor")
	if visor == null:
		return
	_enemy.set_action_state(&"TELEGRAPH")
	expect(visor.is_exposed(), "el visor debería exponerse en TELEGRAPH")
	_expect_layer(visor, PhysicsLayers.ENEMY_WEAK, true)
	_enemy.set_action_state(&"ACTIVE")
	expect(visor.is_exposed(), "el visor debería seguir expuesto en ACTIVE")
	_enemy.set_action_state(&"RECOVER")
	expect(not visor.is_exposed(), "el visor debería cubrirse en RECOVER")
	_expect_layer(visor, PhysicsLayers.ENEMY_BODY, false)
	_enemy.set_action_state(&"NONE")
	expect(_exposure_events.size() >= 2,
			"Events.enemy_weak_point_state no reportó los cambios del visor")
	print("  visor: TELEGRAPH/ACTIVE → capa 4 (bit %d) y grupo; RECOVER/NONE → capa 3 (bit %d)" \
			% [PhysicsLayers.ENEMY_WEAK, PhysicsLayers.ENEMY_BODY])


## Criterio 9: el movedor no supera 0.6 m/tick ni el giro de `turn_rate`.
func _check_move_body() -> void:
	var origin := _enemy.global_transform
	var max_step := 0.0
	# Paso realista, 200 ticks a 100 Hz con una velocidad deseada absurda.
	for _tick: int in 200:
		var before := _enemy.global_position
		_enemy.move_body(0.01, Vector3(0.0, 0.0, -200.0))
		max_step = maxf(max_step, before.distance_to(_enemy.global_position))
	# Un `delta` grande fuerza el recorte: sin él la prueba sería vacía, porque
	# la aceleración nunca llega a 60 m/s en 2 s.
	for _tick: int in 5:
		var before := _enemy.global_position
		_enemy.move_body(1.0, Vector3(0.0, 0.0, -200.0))
		max_step = maxf(max_step, before.distance_to(_enemy.global_position))
	expect(max_step <= _enemy.profile.max_step_per_tick + 0.0001,
			"paso máximo %.4f m, tope %.2f m" % [max_step, _enemy.profile.max_step_per_tick])
	expect_near(max_step, _enemy.profile.max_step_per_tick, 0.0001,
			"el recorte de paso debería haberse alcanzado")

	_enemy.global_transform = origin
	_enemy.rotation = Vector3.ZERO
	_enemy.face_toward(_enemy.global_position + Vector3(1000.0, 0.0, 0.0), 1.0)
	var turned := rad_to_deg(absf(_enemy.rotation.y))
	expect(turned <= _enemy.profile.turn_rate + 0.001,
			"giro de %.3f°/s, tope %.1f°/s" % [turned, _enemy.profile.turn_rate])
	expect_near(turned, _enemy.profile.turn_rate, 0.001,
			"el recorte de giro debería haberse alcanzado")
	_enemy.global_transform = origin
	print("  movedor: paso máximo %.4f m/tick (tope %.2f) · giro %.2f°/s (tope %.1f)" \
			% [max_step, _enemy.profile.max_step_per_tick, turned, _enemy.profile.turn_rate])


## Prueba negativa: si el blindaje se ignorara, el casco devolvería los 12
## brutos. Que el valor medido **no** sea 12 es lo que demuestra que
## `amount · (1 − armor)` se aplica de verdad.
func _check_negative() -> void:
	var hull := _enemy.get_part(&"hull")
	if hull == null:
		return
	var effective := hull.take_damage(SHOT_DAMAGE, _hit(hull.world_position(), false, &""))
	expect(not is_equal_approx(effective, SHOT_DAMAGE),
			"prueba negativa: el casco devolvió el daño bruto %.2f; el blindaje no se aplicó" \
			% effective)
	# El mismo razonamiento del lado del punto débil: la parte no puede volver a
	# multiplicar por 3 lo que el arma ya multiplicó.
	var knee := _enemy.get_part(&"wp_leg_fr_knee")
	var weak_effective := knee.take_damage(SHOT_DAMAGE * WEAK_MULTIPLIER,
			_hit(knee.world_position(), true, &"wp_leg_fr_knee"))
	expect(not is_equal_approx(weak_effective, SHOT_DAMAGE * WEAK_MULTIPLIER * WEAK_MULTIPLIER),
			"prueba negativa: la rodilla aplicó el multiplicador por segunda vez (%.2f)" \
			% weak_effective)
	print("  prueba negativa: casco %.2f ≠ %.2f bruto · rodilla %.2f ≠ %.2f doble multiplicador" \
			% [effective, SHOT_DAMAGE, weak_effective, SHOT_DAMAGE * 9.0])


## Criterios 6, 7 y 10: desprendimiento, fases, núcleo y derrota.
func _check_breaking() -> void:
	expect(_phase_events.size() == 1 and _phase_events[0] == PHASES[0],
			"la fase inicial debería ser '%s', se emitieron %s" % [PHASES[0], str(_phase_events)])

	# --- Rodilla 1: un chunk con la pata entera y paso a P2 -----------------
	await _break_weak_point(&"wp_leg_fl_knee")
	expect(_broken_events.has(&"wp_leg_fl_knee"),
			"no se emitió enemy_part_broken de la rodilla")
	expect(_broken_events.has(&"leg_fl_femur"),
			"no se emitió enemy_part_broken del fémur desprendido")
	expect(_pool.get_live_count() == 1,
			"escombros vivos tras una rodilla: %d, esperado 1" % _pool.get_live_count())

	var chunk := _chunks()[0] if not _chunks().is_empty() else null
	if chunk != null:
		expect(chunk.collision_layer == PhysicsLayers.DEBRIS,
				"el chunk está en la capa %d, esperada %d" \
				% [chunk.collision_layer, PhysicsLayers.DEBRIS])
		expect(chunk.collision_mask == DEBRIS_MASK,
				"el chunk tiene máscara %d, esperada %d" % [chunk.collision_mask, DEBRIS_MASK])
		expect_near(chunk.mass, _enemy.get_part(&"leg_fl_femur").effective_debris_mass(), 0.5,
				"masa del chunk del fémur")
		var carried := _mesh_names(chunk)
		for part_name: String in ["leg_fl_femur", "leg_fl_tibia", "leg_fl_foot", "wp_leg_fl_knee"]:
			expect(carried.has(part_name),
					"el chunk no se llevó '%s'; lleva %s" % [part_name, str(carried)])
		expect_near(chunk.lifetime, _enemy.profile.debris_lifetime, 0.01,
				"vida del escombro")

	for part_name: StringName in [&"leg_fl_femur", &"leg_fl_tibia", &"leg_fl_foot",
			&"wp_leg_fl_knee"]:
		var part := _enemy.get_part(part_name)
		expect(part.is_detached(), "'%s' debería estar desprendida" % part_name)
	expect(_enemy.get_part(&"wp_leg_fl_knee").is_broken(), "la rodilla debería estar rota")
	expect(_enemy.legs_lost() == 1, "patas perdidas: %d, esperada 1" % _enemy.legs_lost())
	expect(_trauma_events > 0, "no se emitió Events.camera_trauma al romper")
	expect(_enemy.current_phase() == PHASES[1],
			"fase tras 1 rodilla: '%s', esperada '%s'" % [_enemy.current_phase(), PHASES[1]])
	_check_limp()
	_check_attack_gating()

	# --- Rodillas 2 y 3: P3, P4 y el núcleo ventral expuesto ----------------
	await _break_weak_point(&"wp_leg_fr_knee")
	expect(_enemy.current_phase() == PHASES[2],
			"fase tras 2 rodillas: '%s', esperada '%s'" % [_enemy.current_phase(), PHASES[2]])
	# Desbloqueos acumulados: `head_laser` y `emp_pulse` llegaron con P2 y
	# `pounce` con P3 (`docs/07` §6).
	var fury_attacks := _enemy.unlocked_attacks()
	for attack_id: String in ["walk", "climb", "stomp", "leg_sweep", "siege_beam",
			"shake_off", "head_laser", "emp_pulse", "pounce"]:
		expect(fury_attacks.has(attack_id),
				"'%s' debería estar disponible en P3; hay %s" % [attack_id, str(fury_attacks)])

	await _check_visor_on_destroy()

	# El cono del núcleo exige el dron **debajo**: se simula con la API pública.
	var belly := _enemy.get_part(&"underbelly")
	_enemy.set_target_position(belly.world_position() + Vector3(0.0, -20.0, 0.0))
	await _break_weak_point(&"wp_leg_bl_knee")
	expect(_enemy.current_phase() == PHASES[3],
			"fase tras 3 rodillas: '%s', esperada '%s'" % [_enemy.current_phase(), PHASES[3]])
	for core_id: StringName in CORES:
		var core := _enemy.get_weak_point(core_id)
		expect(core.is_exposed(), "'%s' debería exponerse con 3 rodillas y el dron abajo" % core_id)
		_expect_layer(core, PhysicsLayers.ENEMY_WEAK, true)
	# Fuera del cono vuelve a cubrirse: las dos condiciones se exigen juntas.
	_enemy.set_target_position(belly.world_position() + Vector3(200.0, 0.0, 0.0))
	await wait_physics(2)
	expect(not _enemy.get_weak_point(&"wp_core_a").is_exposed(),
			"el núcleo no debería exponerse con el dron fuera del cono de 70°")
	_enemy.set_target_position(belly.world_position() + Vector3(0.0, -20.0, 0.0))
	await wait_physics(2)

	# --- Rodilla 4: cuatro patas perdidas, DOWNED ---------------------------
	await _break_weak_point(&"wp_leg_br_knee")
	expect(_enemy.legs_lost() == 4, "patas perdidas: %d, esperadas 4" % _enemy.legs_lost())
	expect(_enemy.is_downed(), "con 4 patas perdidas el jefe debería estar DOWNED")
	expect(_enemy.locomotion_state() == &"DOWNED",
			"locomotion_state() vale '%s', esperado 'DOWNED'" % _enemy.locomotion_state())
	expect(_pool.get_live_count() == 4,
			"escombros vivos tras 4 rodillas: %d, esperados 4" % _pool.get_live_count())
	expect(_pool.get_live_count() <= DebrisPool.MAX_LIVE,
			"el pool superó MAX_LIVE (%d)" % DebrisPool.MAX_LIVE)
	# **El desplome entra solo en P5** (WP-19b): un jefe con las cuatro patas
	# arrancadas no se puede mover, los núcleos quedan expuestos de forma
	# permanente y arranca la cuenta atrás larga. Sin esto la ronda no terminaba
	# nunca (medido en WP-23).
	await wait_physics(4)
	expect(_enemy.current_phase() == PHASES[4],
			"tras el desplome la fase debería ser '%s' y es '%s'"
					% [PHASES[4], _enemy.current_phase()])
	var arachnodroid := _enemy as Arachnodroid
	expect(arachnodroid != null and arachnodroid.is_downed_selfdestruct(),
			"el desplome debería marcar su propia cuenta atrás")
	expect(arachnodroid != null
			and arachnodroid.selfdestruct_remaining() > Arachnodroid.SELFDESTRUCT_SECONDS,
			"la cuenta del desplome debería ser la larga (%.0f s) y quedan %.1f s"
					% [Arachnodroid.SELFDESTRUCT_SECONDS_DOWNED,
					arachnodroid.selfdestruct_remaining() if arachnodroid != null else -1.0])
	for core_id: StringName in CORES:
		expect(_enemy.get_weak_point(core_id).is_exposed(),
				"'%s' debería quedar expuesto con el jefe caído" % core_id)

	# --- Núcleos: la fase ya no se mueve, la derrota llega con el tercero ----
	await _break_weak_point(CORES[0])
	expect(_enemy.current_phase() == PHASES[4],
			"con 1 núcleo roto la fase debería seguir en '%s'" % PHASES[4])
	await _break_weak_point(CORES[1])
	expect(_enemy.current_phase() == PHASES[4],
			"fase tras 2 núcleos: '%s', esperada '%s'" % [_enemy.current_phase(), PHASES[4]])
	expect(_defeated_events.is_empty(),
			"no debería haber derrota antes de romper los tres núcleos")
	await _break_weak_point(CORES[2])
	expect(_defeated_events.size() == 1,
			"Events.enemy_defeated se emitió %d veces, esperada 1" % _defeated_events.size())
	# Repetir el daño no puede volver a emitir la derrota.
	_enemy.declare_defeat()
	var _extra := _enemy.apply_damage(CORES[2], 5000.0, _hit(Vector3.ZERO, true, CORES[2]))
	await wait_physics(2)
	expect(_defeated_events.size() == 1,
			"la derrota se emitió %d veces tras insistir" % _defeated_events.size())

	expect(_phase_events == PHASES,
			"secuencia de fases: %s, esperada %s" % [str(_phase_events), str(PHASES)])
	# En P5 sólo quedan `walk` y `shake_off` (`docs/07` §6).
	var final_attacks := _enemy.unlocked_attacks()
	expect(final_attacks.has("walk") and final_attacks.has("shake_off"),
			"en P5 deberían quedar 'walk' y 'shake_off'; hay %s" % str(final_attacks))
	for attack_id: String in ["climb", "stomp", "leg_sweep", "head_laser", "siege_beam",
			"emp_pulse", "pounce"]:
		expect(not final_attacks.has(attack_id),
				"'%s' debería estar bloqueado en P5; hay %s" % [attack_id, str(final_attacks)])
	print("  ataques disponibles en P3: %s" % str(fury_attacks))
	print("  ataques disponibles en P5: %s" % str(final_attacks))
	print("  fases: %s" % str(_phase_events))
	print("  roturas publicadas: %d ids únicas · escombros vivos %d" \
			% [_broken_events.size(), _pool.get_live_count()])


## Criterios 8: tope del pool, congelado, horneado y vida del escombro.
func _check_pool_limits() -> void:
	var baked_before := _field.get_total_instance_count()
	var live_before := _pool.get_live_count()
	_pool.retire_oldest()
	expect(_pool.get_live_count() == live_before - 1,
			"retire_oldest() dejó %d vivos, esperados %d" \
			% [_pool.get_live_count(), live_before - 1])
	expect(_field.get_total_instance_count() > baked_before,
			"el RubbleField no registró el escombro retirado")
	await wait_frames(1)

	# Tope duro: 40 pedidos seguidos no pueden dejar más de 24 vivos.
	var mesh := BoxMesh.new()
	var shape := BoxShape3D.new()
	for index: int in 40:
		var xform := Transform3D(Basis.IDENTITY, Vector3(float(index) * 3.0, 40.0, 0.0))
		var _chunk := _pool.request(mesh, shape, xform, 450.0, Vector3.ZERO, 20.0)
	expect(_pool.get_live_count() <= DebrisPool.MAX_LIVE,
			"tras 40 pedidos hay %d escombros vivos, tope %d" \
			% [_pool.get_live_count(), DebrisPool.MAX_LIVE])
	var oldest := _chunks()
	if not oldest.is_empty():
		expect(not oldest[0].freeze, "un escombro recién pedido no debería nacer congelado")

	# Vida: un trozo con `lifetime` corto se congela y se hornea solo. El campo se
	# vacía antes de medir porque las cuatro plazas ya las ocuparon las mallas
	# del jefe, y una quinta malla devolvería −1 (`docs/10` §6).
	_pool.clear()
	_field.clear()
	await wait_frames(2)
	var short := _pool.request(mesh, shape, Transform3D(Basis.IDENTITY, Vector3(0.0, 60.0, 0.0)),
			450.0, Vector3.ZERO, 0.25)
	expect(short != null, "el pool no devolvió el escombro de vida corta")
	var baked_mid := _field.get_total_instance_count()
	expect(baked_mid == 0, "el campo de ruina debería haber quedado vacío tras clear()")
	Engine.time_scale = 4.0
	await wait_physics(40)
	Engine.time_scale = 1.0
	expect(_pool.get_live_count() == 0,
			"el escombro de 0.25 s sigue vivo (%d)" % _pool.get_live_count())
	expect(_field.get_total_instance_count() > baked_mid,
			"el RubbleField no horneó el escombro expirado")
	expect(_field.get_field_count() > 0 and _field.get_field_count() <= RubbleField.MAX_FIELDS,
			"campos del RubbleField: %d, tope %d" \
			% [_field.get_field_count(), RubbleField.MAX_FIELDS])
	print("  pool: tope %d respetado · %d instancias horneadas en %d campos" \
			% [DebrisPool.MAX_LIVE, _field.get_total_instance_count(), _field.get_field_count()])


## Criterio 10 de `docs/06` §16.1: sin huérfanos tras liberar el enemigo.
func _check_cleanup(nodes_before: int, children_before: int) -> void:
	_pool.clear()
	_field.clear()
	_enemy.queue_free()
	_enemy = null
	await wait_frames(3)

	var nodes_after := get_tree().get_node_count()
	var children_after := get_tree().root.get_child_count()
	expect(absi(nodes_after - nodes_before) <= 2,
			"nodos en el árbol: %d antes, %d después (tolerancia ±2)" \
			% [nodes_before, nodes_after])
	expect(children_after == children_before,
			"hijos de la raíz: %d antes, %d después" % [children_before, children_after])
	var leftovers := 0
	for node: Node in _all_nodes(get_tree().root):
		if node.has_meta(&"enemy_part"):
			leftovers += 1
	expect(leftovers == 0, "quedaron %d nodos con el metadato 'enemy_part'" % leftovers)
	print("  limpieza: %d → %d nodos, 0 metadatos 'enemy_part' huérfanos" \
			% [nodes_before, nodes_after])


## Criterio 5 de `docs/06` §16.1, primera mitad: perder una pata cuesta el 15 %
## de velocidad (`leg_speed_penalty`).
func _check_limp() -> void:
	var rig := _enemy.locomotion
	if rig == null or not rig.has_method(&"speed_multiplier"):
		fail("el nodo Locomotion no expone speed_multiplier()")
		return
	var expected := 1.0 - _enemy.profile.leg_speed_penalty
	expect_near(float(rig.call(&"speed_multiplier")), expected, 0.001,
			"speed_multiplier() con una pata perdida")
	expect(int(rig.call(&"planted_count")) == 3,
			"patas apoyadas: %d, esperadas 3" % int(rig.call(&"planted_count")))
	print("  cojera: speed_multiplier() = %.2f con 1 pata perdida" 			% float(rig.call(&"speed_multiplier")))


## Criterio 5 de `docs/06` §16.1, segunda mitad: una acción cuyo
## `disabled_if_broken` apunta a una parte rota sale del selector.
func _check_attack_gating() -> void:
	var saved := _enemy.profile.attacks
	var attack := AttackProfile.new()
	attack.attack_id = &"stomp"
	attack.disabled_if_broken = PackedStringArray(["wp_leg_fl_knee"])
	var injected: Array[AttackProfile] = [attack]
	_enemy.profile.attacks = injected
	expect(not _enemy.unlocked_attacks().has("stomp"),
			"'stomp' debería salir del selector con 'wp_leg_fl_knee' rota")
	attack.disabled_if_broken = PackedStringArray(["antenna_l"])
	expect(_enemy.unlocked_attacks().has("stomp"),
			"'stomp' debería volver al selector con 'antenna_l' intacta")
	_enemy.profile.attacks = saved


## Criterio 11 de `docs/07` §13: romper el visor ciega 20 s y bloquea
## `head_laser` 30 s, todo declarado en `on_destroy`.
func _check_visor_on_destroy() -> void:
	await _break_weak_point(&"wp_head_visor")
	var perception := _enemy.perception
	if perception == null or not perception.has_method(&"is_blinded"):
		fail("el nodo Perception no expone is_blinded()")
		return
	expect(bool(perception.call(&"is_blinded")),
			"romper el visor debería cegar la percepción")
	expect_near(float(perception.call(&"blind_remaining")), 20.0, 0.2,
			"segundos de ceguera tras romper el visor")
	expect(_enemy.is_attack_locked(&"head_laser"),
			"'head_laser' debería quedar bloqueado al romper el visor")
	expect(not _enemy.unlocked_attacks().has("head_laser"),
			"'head_laser' sigue en el selector con el visor roto")
	expect(not _enemy.get_weak_point(&"wp_head_visor").is_exposed(),
			"un punto débil roto no puede volver a exponerse")
	print("  visor roto: ceguera %.1f s · head_laser bloqueado" 			% float(perception.call(&"blind_remaining")))


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------

## Rompe un punto débil de un golpe y deja pasar dos ticks de física.
func _break_weak_point(weak_point_id: StringName) -> void:
	var part := _enemy.get_part(weak_point_id)
	if part == null:
		fail("no existe la parte del punto débil '%s'" % weak_point_id)
		return
	var _effective := part.take_damage(part.hp / maxf(1.0 - part.armor, 0.01),
			_hit(part.world_position(), true, weak_point_id))
	await wait_physics(2)


## Diccionario de impacto del contrato de `docs/06` §14.1.
func _hit(position: Vector3, weak: bool, weak_point_id: StringName) -> Dictionary:
	return {
		"position": position,
		"normal": Vector3.UP,
		"direction": Vector3.FORWARD,
		"source": _muzzle,
		"is_weak_point": weak,
		"weak_point_id": weak_point_id,
		"damage_type": &"kinetic",
	}


## Comprueba capa, máscara y pertenencia al grupo `weak_points` de un punto débil.
func _expect_layer(weak_point: WeakPoint, layer: int, in_group: bool) -> void:
	var body := weak_point.collider()
	if body == null:
		fail("el punto débil '%s' no tiene colisionador" % weak_point.weak_point_id())
		return
	expect(body.collision_layer == layer,
			"'%s' está en la capa %d, esperada %d" \
			% [weak_point.weak_point_id(), body.collision_layer, layer])
	var expected_mask := WeakPoint.EXPOSED_MASK if in_group else WeakPoint.COVERED_MASK
	expect(body.collision_mask == expected_mask,
			"'%s' tiene máscara %d, esperada %d" \
			% [weak_point.weak_point_id(), body.collision_mask, expected_mask])
	expect(body.is_in_group(WeakPoint.GROUP) == in_group,
			"'%s' %s en el grupo 'weak_points'" \
			% [weak_point.weak_point_id(), "debería estar" if in_group else "no debería estar"])


## Escombros vivos colgados del pool.
func _chunks() -> Array[DebrisChunk]:
	var found: Array[DebrisChunk] = []
	for child: Node in _pool.get_children():
		var chunk := child as DebrisChunk
		if chunk != null and not chunk.is_queued_for_deletion():
			found.append(chunk)
	return found


## Nombres de las mallas que viajan dentro de un escombro.
func _mesh_names(chunk: DebrisChunk) -> PackedStringArray:
	var found := PackedStringArray()
	for node: Node in _all_nodes(chunk):
		if node is MeshInstance3D:
			found.append(node.name)
	return found


## Recorre la jerarquía completa en profundidad, incluida la raíz.
func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	var index := 0
	while index < found.size():
		for child: Node in found[index].get_children():
			found.append(child)
		index += 1
	return found


# --------------------------------------------------------------------------
# Escuchas del bus
# --------------------------------------------------------------------------

func _on_spawned(_enemy_node: Node3D, enemy_id: StringName) -> void:
	_spawned.append(enemy_id)


func _on_part_broken(_enemy_node: Node3D, part_id: StringName, _position: Vector3) -> void:
	if _broken_events.has(part_id):
		fail("Events.enemy_part_broken repitió el id '%s'" % part_id)
	_broken_events.append(part_id)


func _on_phase_changed(_enemy_node: Node3D, phase_id: StringName) -> void:
	_phase_events.append(phase_id)


func _on_weak_point_state(_enemy_node: Node3D, weak_point_id: StringName, exposed: bool) -> void:
	_exposure_events.append({"id": weak_point_id, "exposed": exposed})


func _on_defeated(_enemy_node: Node3D, enemy_id: StringName) -> void:
	_defeated_events.append(enemy_id)


func _on_trauma(_amount: float, _position: Vector3) -> void:
	_trauma_events += 1
