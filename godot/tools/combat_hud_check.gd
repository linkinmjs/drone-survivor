## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check del HUD de combate (`docs/12` §9.2, `docs/15` §2).
##
## Corre **el nivel de batalla de verdad** —rig, distrito con sus sesenta `Building`,
## Arachnodroid, `CityIntegrity`, `RoundManager` y cadena de objetivos— y le inyecta
## hechos sintéticos por el bus. `docs/12` §9.2 admitía una escena pelada con dobles
## de `WeaponMount` y `EnemyBase`; se usa el nivel porque así se verifica de paso lo
## único que un doble no puede probar: que el `CombatHUD` se cablea solo en
## `battle_level.tscn`, que apaga la tarjeta de objetivo provisional y que sus catorce
## componentes **no se pisan con el `FlightHUD`** en la misma pantalla, que es lo que
## miran las capturas.
##
## **El jefe no piensa**: [member Global.debug_freeze_ai] y, además, el contenedor
## `Enemies` en `PROCESS_MODE_DISABLED`. Lo primero es el contrato con WP-18; lo
## segundo funciona hoy, mientras esa IA se está escribiendo en paralelo. Con el jefe
## quieto, todo lo que mueve el HUD durante el check viene del bus y es reproducible.
##
## **El reloj es manual**: [method CombatHUD.set_manual_time] desengancha el HUD del
## `_process` y [method CombatHUD.advance] lo avanza en pasos exactos. Es la única
## forma de medir «120 ms de hitmarker», «1.1 s de windup» o «3.0 s de glitch» en
## `--headless`, donde el bucle principal corre tan rápido como puede y un `delta`
## real no significa nada.
##
## Comandos:
## [codeblock]
## godot --headless --path godot res://tools/combat_hud_check.tscn
## godot --windowed --resolution 960x540 --path godot res://tools/combat_hud_check.tscn -- --shots=tools/out/shots
## [/codeblock]
extends CheckRunner

const LEVEL_SCENE: String = "res://rounds/battle_level.tscn"

## Ronda que se ejercita.
const ROUND_ID: String = "first-contact"

## Semilla fija: dos corridas tienen que dar las mismas pilas y el mismo glitch.
const SEED: int = 20260919

## Plazo de cada espera intermedia; el global lo pone [CheckRunner].
const STEP_TIMEOUT_SECONDS: float = 20.0

## Paso del reloj manual, en segundos. Es el tick de física del proyecto.
const STEP: float = 1.0 / 60.0

## Frames que se dejan pasar para que la escena dibuje antes de capturar.
const SETTLE_FRAMES: int = 6

## Títulos de las filas, en orden. Las dos últimas las agrega WP-24d.
const ROW_TITLES: Array[String] = [
	"componentes presentes y dibujando", "energía, casco y calor", "hitmarkers",
	"barra del jefe por grupos", "franja de ciudad", "marcadores fuera de pantalla",
	"dirección del daño", "aviso de telegrafía", "glitch de EMP",
	"cuenta de reconstrucción", "modo cinemático", "cronómetro y objetivo",
	"claves de traducción", "prueba negativa", "sin conexiones colgadas",
	"marcador del punto débil", "consejos contextuales",
]

## Cuántos componentes tiene el `CombatHUD` tras WP-24d.
const COMPONENT_COUNT: int = 17

## Grupos de la barra del jefe, como `[primera_barra, cuántas, clave del rótulo]`
## (`docs/07` §4: 4 rodillas, 1 visor, 3 núcleos).
const BOSS_GROUPS: Array[Array] = [
	[0, 4, "HUD_WP_GROUP_KNEE"],
	[4, 1, "HUD_WP_GROUP_VISOR"],
	[5, 3, "HUD_WP_GROUP_CORE"],
]

## Puntos de prueba de la fila 6, en coordenadas **locales de cámara**: seis alrededor
## y seis detrás, incluido uno exactamente en el ojo de la cámara, que es el caso
## degenerado que produce `NAN` si alguien se saltea [method HUDProjection.marker_for].
const MARKER_PROBES: Array[Vector3] = [
	Vector3(0.0, 0.0, -40.0), Vector3(30.0, 5.0, -20.0), Vector3(-30.0, -5.0, -20.0),
	Vector3(60.0, 20.0, -5.0), Vector3(-60.0, -20.0, -5.0), Vector3(0.0, 45.0, -12.0),
	Vector3(0.0, 0.0, 40.0), Vector3(25.0, 0.0, 30.0), Vector3(-25.0, 0.0, 30.0),
	Vector3(0.0, 30.0, 25.0), Vector3(0.0, -30.0, 25.0), Vector3(0.0, 0.0, 0.0),
]

## Direcciones de la fila 7, en coordenadas locales de cámara: frente, derecha,
## espalda e izquierda.
const DAMAGE_PROBES: Array[Vector3] = [
	Vector3(0.0, 0.0, -30.0), Vector3(30.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 30.0), Vector3(-30.0, 0.0, 0.0),
]

## Ángulo de pantalla esperado para cada una, en la convención de
## [method CanvasItem.draw_arc]: el frente **arriba** (−90°), la derecha a la derecha
## (0°), la espalda **abajo** (90°) y la izquierda a la izquierda (180°).
const DAMAGE_EXPECTED_DEG: Array[float] = [-90.0, 0.0, 90.0, 180.0]

## Tolerancia angular de la fila 7, en grados.
const DAMAGE_TOLERANCE_DEG: float = 12.0

## Duración del aviso de telegrafía de la fila 8, en segundos (`docs/12` §9.2).
const TELEGRAPH_SECONDS: float = 1.1

## Tolerancia de la fila 8, en segundos.
const TELEGRAPH_TOLERANCE: float = 0.05

## Duración del EMP de la fila 9, en segundos (`docs/09` §3.3).
const EMP_SECONDS: float = 3.0

## Tolerancia de la fila 9, en segundos.
const EMP_TOLERANCE: float = 0.1

## Segundos de reconstrucción que pide `docs/09` §3.5.
const RESPAWN_SECONDS: float = 12.0

## Tolerancia de la fila 10, en segundos.
const RESPAWN_TOLERANCE: float = 0.6

## Los ocho puntos débiles del Arachnodroid (`docs/07` §4), en el orden del perfil.
const WEAK_POINT_IDS: Array[StringName] = [
	&"wp_leg_fl_knee", &"wp_leg_fr_knee", &"wp_leg_bl_knee", &"wp_leg_br_knee",
	&"wp_head_visor", &"wp_core_a", &"wp_core_b", &"wp_core_c",
]

var _level: BattleLevel = null
var _manager: RoundManager = null
var _hud: CombatHUD = null
var _rig: DroneRig = null
var _enemy: EnemyBase = null
var _probes: Node3D = null

## Resultado de cada fila: `{número: todas sus comprobaciones pasaron}`.
var _rows: Dictionary[int, bool] = {}


func _run() -> void:
	# El nodo del check deja de ser la escena actual para sobrevivir al nivel.
	get_tree().current_scene = null
	var _discard := check_finished.connect(_on_check_finished)
	Global.debug_freeze_ai = true

	if not ResourceLoader.exists(LEVEL_SCENE):
		fail("falta el nivel de batalla (%s)" % LEVEL_SCENE)
		Global.debug_freeze_ai = false
		return
	var ok := await _enter_level()
	if not ok:
		Global.debug_freeze_ai = false
		return

	await _check_cinematic()
	_manager.skip_intro()
	await wait_frames(2)
	_freeze_drone()
	_hud.set_manual_time(true)

	await _check_components()
	await _check_bars()
	await _check_hit_markers()
	await _check_boss_bar()
	await _check_city_bar()
	_check_markers()
	_check_damage_direction()
	await _check_telegraph()
	await _check_glitch()
	await _check_respawn()
	_check_timer_and_objective()
	await _check_weak_hint()
	await _check_coach()
	_check_translations()
	_check_negative()
	await _shoot_all()
	await _check_teardown()

	Global.debug_freeze_ai = false
	_print_rows()


# --- Fila 11 (se mide primero, en `INTRO`) ----------------------------------------------------

## Durante `INTRO` sólo se ven la franja de ciudad y el rótulo de la ronda
## (`docs/12` §4.2). Se mide **antes** de saltear la cinemática porque es el estado
## real en el que arranca el nivel, no uno forzado a mano.
func _check_cinematic() -> void:
	var state := _manager.get_state()
	var cinematic := _hud.is_cinematic()
	var hidden := PackedStringArray()
	var shown := PackedStringArray()
	for component: int in CombatHUD.Component.values():
		var node := _hud.component_node(component as CombatHUD.Component)
		if node == null:
			continue
		var label := String(CombatHUD.Component.keys()[component])
		var wanted := CombatHUD.CINEMATIC_COMPONENTS.has(component)
		if node.visible and not wanted:
			shown.append(label)
		elif not node.visible and wanted:
			hidden.append(label)
	var banner := _hud.component_node(CombatHUD.Component.INTRO) as HUDIntroBanner
	var keys := banner.round_keys() if banner != null else PackedStringArray()
	var has_keys := keys.size() == 2 and not keys[0].is_empty() and not keys[1].is_empty()
	await _advance(0.2)
	await _shoot("cinematic")
	_row(11, state == Global.RoundState.INTRO and cinematic and shown.is_empty()
			and hidden.is_empty() and has_keys,
			"11 · INTRO: estado %d, cinemático %s, de más [%s], de menos [%s], rótulo %s"
			% [state, str(cinematic), ", ".join(shown), ", ".join(hidden), str(keys)])


# --- Fila 1 -----------------------------------------------------------------------------------

## Los catorce componentes existen, son visibles y **dibujaron al menos una vez** tras
## alimentarlos. Un componente que existe pero nunca dibuja pasaría cualquier prueba
## de visibilidad y no se vería en pantalla.
func _check_components() -> void:
	var names: Array = CombatHUD.Component.keys()
	var missing := PackedStringArray()
	var invisible := PackedStringArray()
	var unresponsive := PackedStringArray()
	for component: int in CombatHUD.Component.values():
		var label := String(names[component])
		var node := _hud.component_node(component as CombatHUD.Component)
		if node == null:
			missing.append(label)
			continue
		# El rótulo de la ronda es `CINEMATIC_ONLY`: en `BATTLE` **no** se ve, y eso es
		# lo correcto, no un fallo (`docs/12` §4.2). Su respuesta a `show_component()`
		# se mide sobre el estado pedido, que es lo que el HUD guarda para cuando
		# vuelva la cinemática.
		var only_intro: bool = CombatHUD.CINEMATIC_ONLY_COMPONENTS.has(component)
		if node.visible == only_intro:
			invisible.append("%s(visible=%s)" % [label, str(node.visible)])
		_hud.show_component(component as CombatHUD.Component, false)
		var off := _hud.is_component_visible(component as CombatHUD.Component) \
				or (node.visible and not only_intro)
		_hud.show_component(component as CombatHUD.Component, true)
		var on := _hud.is_component_visible(component as CombatHUD.Component) \
				and (node.visible or only_intro)
		if off or not on:
			unresponsive.append("%s(off=%s,on=%s)" % [label, str(off), str(on)])

	# Alimentar a todos antes de exigir el dibujo: un componente sin datos puede
	# salir del `_draw()` en la primera línea y eso no sería un fallo.
	_feed_everything()
	await _advance(0.2)
	await wait_frames(3)
	var silent := PackedStringArray()
	for component: int in CombatHUD.Component.values():
		var node := _hud.component_node(component as CombatHUD.Component)
		if node == null or component == int(CombatHUD.Component.GLITCH):
			continue
		# El `GlitchLayer` no dibuja nada y el rótulo de la ronda ya dibujó durante la
		# cinemática, antes de que el check saltee la intro.
		if node.draw_count <= 0:
			silent.append(String(names[component]))
	print("  [1] %d componentes · %d sin nodo · %d ocultos · %d sin responder · %d sin dibujar"
			% [names.size(), missing.size(), invisible.size(), unresponsive.size(),
			silent.size()])
	_row(1, names.size() == COMPONENT_COUNT and missing.is_empty() and invisible.is_empty()
			and unresponsive.is_empty() and silent.is_empty(),
			"1 · faltan [%s], ocultos [%s], no responden [%s], no dibujaron [%s]"
			% [", ".join(missing), ", ".join(invisible), ", ".join(unresponsive),
			", ".join(silent)])


# --- Fila 2 -----------------------------------------------------------------------------------

## `energy_changed(0.14, true)` → parpadeo; `hull_changed(0.55)` → 2 segmentos rotos;
## `weapon_heat_changed(1.0, true)` → bloqueo.
func _check_bars() -> void:
	var energy := _hud.component_node(CombatHUD.Component.ENERGY) as HUDEnergyBar
	var hull := _hud.component_node(CombatHUD.Component.HULL) as HUDHullBar
	var heat := _hud.component_node(CombatHUD.Component.HEAT) as HUDHeatGauge
	Events.energy_changed.emit(0.14, true)
	Events.hull_changed.emit(0.55)
	Events.weapon_heat_changed.emit(1.0, true)
	await _advance(0.1)
	var blinking := energy.is_blinking()
	var broken := hull.broken_segments()
	var locked := heat.is_locked()
	# Y que el HUD siga obedeciendo al bus cuando el estado se va: no alcanza con que
	# encienda, tiene que apagarse.
	Events.energy_changed.emit(0.80, false)
	await _advance(0.05)
	var recovered := not energy.is_blinking()
	Events.energy_changed.emit(0.42, false)
	Events.weapon_heat_changed.emit(0.80, false)
	Events.hull_changed.emit(0.62)
	await _advance(0.05)
	print("  [2] energía parpadea %s · casco %d/4 rotos · calor bloqueado %s"
			% [str(blinking), broken, str(locked)])
	_row(2, blinking and broken == 2 and locked and recovered,
			"2 · parpadeo %s (esperado true), segmentos rotos %d (esperado 2), bloqueo %s"
			% [str(blinking), broken, str(locked)])


# --- Fila 3 -----------------------------------------------------------------------------------

## Las tres combinaciones útiles de `weak`/`lethal` dan tres marcas de colores
## distintos, y a los 130 ms no queda ninguna.
func _check_hit_markers() -> void:
	var marker := _hud.component_node(CombatHUD.Component.HIT_MARKER) as HUDHitMarker
	marker.clear_marks()
	Events.hit_confirmed.emit(Vector3.ZERO, false, false)
	Events.hit_confirmed.emit(Vector3.ZERO, true, false)
	Events.hit_confirmed.emit(Vector3.ZERO, true, true)
	var count := marker.active_count()
	var colours := marker.active_colours()
	var distinct := colours.size() == 3 and colours[0] != colours[1] \
			and colours[1] != colours[2] and colours[0] != colours[2]
	await _advance(0.13)
	var gone := marker.active_count()
	print("  [3] %d marcas, %d colores distintos, quedan %d a los 130 ms"
			% [count, 3 if distinct else colours.size(), gone])
	_row(3, count == 3 and distinct and gone == 0,
			"3 · marcas %d (esperado 3), colores distintos %s, vivas a los 130 ms %d"
			% [count, str(distinct), gone])


# --- Fila 4 -----------------------------------------------------------------------------------

## Ocho barras —4 rodillas + visor + 3 núcleos, `docs/07` §4—, **sus tres rótulos de
## grupo** (WP-24d), estados de exposición y chevrons de fase. Al romper las ocho
## partes, las ocho barras quedan vacías.
func _check_boss_bar() -> void:
	var boss := _hud.component_node(CombatHUD.Component.BOSS) as HUDBossBar
	# La fila 1 ya alimentó el HUD y dejó una rodilla rota: la barra arranca de cero
	# para que lo que se mida acá sea el efecto de **estos** eventos y no el residuo
	# del estado anterior.
	boss.clear_enemies()
	boss.bind_enemy(_enemy)
	await _advance(0.05)
	var count := boss.bar_count()
	var ids := PackedStringArray()
	for weak_point: WeakPoint in boss.weak_points():
		ids.append(String(weak_point.weak_point_id()))
	var expected := PackedStringArray()
	for id: StringName in WEAK_POINT_IDS:
		expected.append(String(id))
	var order_ok := ids == expected

	# WP-24d: los tres grupos salen del `hud_key` del perfil, con su tramo exacto de
	# barras y su rótulo plural traducido.
	var groups_ok := boss.group_count() == BOSS_GROUPS.size()
	var labels := PackedStringArray()
	for index: int in mini(boss.group_count(), BOSS_GROUPS.size()):
		var wanted: Array = BOSS_GROUPS[index]
		var span := boss.group_span(index)
		var label := boss.group_label(index)
		labels.append(label)
		groups_ok = groups_ok and span == Vector2i(int(wanted[0]), int(wanted[1])) \
				and boss.group_label_key(index) == String(wanted[2]) \
				and not label.is_empty() and label != String(wanted[2])

	# Exposición por evento: el visor se enciende mientras el jefe ataca
	# (`docs/07` §4) y se apaga al terminar. El grupo entero lo acompaña y destella,
	# que es lo que convierte la barra en una instrucción (WP-24d).
	var visor_quiet := not boss.is_group_exposed(1) and boss.group_pulse(1) <= 0.0
	Events.enemy_weak_point_state.emit(_enemy, &"wp_head_visor", true)
	await _advance(0.05)
	var visor_on := boss.is_exposed_at(4)
	var visor_group_on := boss.is_group_exposed(1) and boss.group_pulse(1) > 0.0
	var visor_state := boss.state_at(4) == HUDBossBar.State.EXPOSED
	var cores_covered := boss.state_at(5) == HUDBossBar.State.COVERED \
			and not boss.is_group_exposed(2)
	Events.enemy_weak_point_state.emit(_enemy, &"wp_head_visor", false)
	await _advance(0.05)
	var visor_off := not boss.is_exposed_at(4)
	var knees_on := boss.is_exposed_at(0) and boss.is_exposed_at(1) \
			and boss.is_group_exposed(0)

	# Los núcleos al abrirse la carcasa: el grupo pasa a expuesto y destella.
	for core: StringName in [&"wp_core_a", &"wp_core_b", &"wp_core_c"]:
		Events.enemy_weak_point_state.emit(_enemy, core, true)
	await _advance(0.05)
	var cores_pulse := boss.is_group_exposed(2) and boss.group_pulse(2) > 0.0
	# El destello es breve: a los 0.6 s ya no queda nada encendido.
	await _advance(HUDBossBar.PULSE_SECONDS + 0.1)
	var pulse_done := boss.group_pulse(2) <= 0.0 and boss.is_group_exposed(2)

	Events.enemy_phase_changed.emit(_enemy, &"p3_fury")
	await _advance(0.05)
	var phase := boss.phase_number()

	# Una sola rodilla rota: la barra cae y las otras siete siguen llenas.
	Events.enemy_part_broken.emit(_enemy, WEAK_POINT_IDS[0], Vector3.ZERO)
	await _advance(0.05)
	var one_broken := boss.state_at(0) == HUDBossBar.State.BROKEN \
			and is_zero_approx(boss.bar_fill(0)) and boss.bar_fill(1) > 0.99

	for index: int in range(1, WEAK_POINT_IDS.size()):
		Events.enemy_part_broken.emit(_enemy, WEAK_POINT_IDS[index], Vector3.ZERO)
	await _advance(0.05)
	var empty := 0
	for index: int in count:
		if boss.state_at(index) == HUDBossBar.State.BROKEN \
				and is_zero_approx(boss.bar_fill(index)):
			empty += 1
	var all_broken := boss.is_group_broken(0) and boss.is_group_broken(1) \
			and boss.is_group_broken(2)
	print("  [4] %d barras (orden %s) · grupos [%s] · visor on/off %s/%s · "
			% [count, str(order_ok), ", ".join(labels), str(visor_on), str(visor_off)]
			+ "pulso núcleos %s · fase %d · vacías %d"
			% [str(cores_pulse), phase, empty])
	_row(4, count == 8 and order_ok and groups_ok and visor_quiet and visor_on
			and visor_group_on and visor_state and cores_covered and visor_off
			and knees_on and cores_pulse and pulse_done and phase == 3 and one_broken
			and empty == 8 and all_broken,
			"4 · barras %d (esperado 8), orden %s, grupos %s [%s], visor %s/%s (grupo %s), "
			% [count, str(order_ok), str(groups_ok), ", ".join(labels), str(visor_on),
			str(visor_off), str(visor_group_on)]
			+ "núcleos cubiertos %s, pulso %s→apagado %s, rodillas %s, fase %d "
			% [str(cores_covered), str(cores_pulse), str(pulse_done), str(knees_on), phase]
			+ "(esperado 3), una rota %s, vacías %d (esperado 8), grupos rotos %s"
			% [str(one_broken), empty, str(all_broken)])


# --- Fila 5 -----------------------------------------------------------------------------------

## La franja baja con `city_integrity_changed` y destella con `building_destroyed`;
## el destello termina antes de 300 ms. Nunca se cruza el 0.35, que dispararía la
## derrota de la ronda (`docs/11` §4.1) y escondería el HUD.
func _check_city_bar() -> void:
	var city := _hud.component_node(CombatHUD.Component.CITY) as HUDCityBar
	Events.city_integrity_changed.emit(0.86)
	await _advance(0.05)
	var high := city.ratio
	Events.city_integrity_changed.emit(0.62)
	Events.building_destroyed.emit(Vector3(40.0, 0.0, -20.0), 3)
	await _advance(0.05)
	var dropped := city.ratio
	var flashing := city.is_flashing()
	await _advance(0.30)
	var calm := not city.is_flashing()
	print("  [5] integridad %.2f → %.2f · destello %s → apagado a los 300 ms %s"
			% [high, dropped, str(flashing), str(calm)])
	_row(5, is_equal_approx(high, 0.86) and is_equal_approx(dropped, 0.62)
			and flashing and calm,
			"5 · integridad %.2f→%.2f (esperado 0.86→0.62), destello %s, apagado %s"
			% [high, dropped, str(flashing), str(calm)])


# --- Fila 6 -----------------------------------------------------------------------------------

## Doce puntos alrededor y detrás de la cámara —incluido uno en el ojo mismo— dan
## siempre posiciones finitas y dentro del rectángulo útil, y se dibujan **como mucho
## seis** (`docs/12` §8).
func _check_markers() -> void:
	var markers := _hud.component_node(CombatHUD.Component.MARKERS) as HUDOffscreenMarkers
	var camera := _hud.get_camera()
	if camera == null:
		_row(6, false, "6 · no hay cámara activa para proyectar los marcadores")
		return
	_probes = Node3D.new()
	_probes.name = "MarkerProbes"
	_level.add_child(_probes)
	for index: int in MARKER_PROBES.size():
		var probe := Node3D.new()
		probe.name = "Probe%d" % index
		_probes.add_child(probe)
		probe.global_position = camera.global_transform * MARKER_PROBES[index]
		probe.add_to_group(&"pickups" if index % 2 == 0 else &"enemies")

	var computed := markers.markers()
	var rect := markers.screen_rect()
	var bad := PackedStringArray()
	for marker: Dictionary in computed:
		if not _marker_is_valid(marker, rect):
			bad.append(str(marker.get("pos", Vector2.ZERO)))
	print("  [6] %d marcadores de %d candidatos · rectángulo %s · inválidos %d"
			% [computed.size(), MARKER_PROBES.size(), str(rect), bad.size()])
	_row(6, computed.size() <= HUDOffscreenMarkers.MAX_MARKERS and computed.size() > 0
			and bad.is_empty(),
			"6 · %d marcadores (tope %d), inválidos [%s]"
			% [computed.size(), HUDOffscreenMarkers.MAX_MARKERS, ", ".join(bad)])
	# Las sondas se van ya: de lo contrario las capturas mostrarían doce marcadores
	# inventados en vez de las pilas y el jefe reales.
	_probes.queue_free()
	_probes = null


# --- Fila 7 -----------------------------------------------------------------------------------

## Cuatro golpes desde frente, derecha, espalda e izquierda dan cuatro ángulos
## distintos y correctos, y a los 0.9 s no queda arco (`docs/12` §8: 0.8 s).
func _check_damage_direction() -> void:
	var damage := _hud.component_node(CombatHUD.Component.DAMAGE) as HUDDamageDirection
	var camera := _hud.get_camera()
	if camera == null:
		_row(7, false, "7 · no hay cámara activa para orientar el arco de daño")
		return
	damage.clear_arcs()
	var measured: Array[float] = []
	for index: int in DAMAGE_PROBES.size():
		var world := camera.global_transform * DAMAGE_PROBES[index]
		measured.append(rad_to_deg(damage.angle_for(world)))
	var wrong := PackedStringArray()
	for index: int in measured.size():
		var got := measured[index]
		if is_nan(got):
			wrong.append("%d:NAN" % index)
			continue
		var error := absf(wrapf(got - DAMAGE_EXPECTED_DEG[index], -180.0, 180.0))
		if error > DAMAGE_TOLERANCE_DEG:
			wrong.append("%d:%.1f°≠%.1f°" % [index, got, DAMAGE_EXPECTED_DEG[index]])
	# `MAX_ARCS` es 3: se emiten los cuatro y el más viejo cae, que es lo que pide
	# «se suman hasta 3» de `docs/12` §4.1.
	for index: int in DAMAGE_PROBES.size():
		Events.drone_damaged.emit(20.0, camera.global_transform * DAMAGE_PROBES[index])
	var alive := damage.active_count()
	var distinct: Dictionary[float, bool] = {}
	for angle: float in damage.arc_angles():
		distinct[snappedf(angle, 0.01)] = true
	print("  [7] ángulos %s · arcos vivos %d · distintos %d"
			% [str(measured), alive, distinct.size()])
	_row(7, wrong.is_empty() and alive == HUDDamageDirection.MAX_ARCS
			and distinct.size() == alive,
			"7 · ángulos incorrectos [%s], arcos %d (esperado %d), distintos %d"
			% [", ".join(wrong), alive, HUDDamageDirection.MAX_ARCS, distinct.size()])


# --- Fila 8 -----------------------------------------------------------------------------------

## `enemy_attack_telegraphed(enemy, &"stomp", 1.1)` muestra `HUD_TELEGRAPH_STOMP` y su
## barra llega a 0 a los 1.1 s ±0.05.
func _check_telegraph() -> void:
	var telegraph := _hud.component_node(CombatHUD.Component.TELEGRAPH) as HUDTelegraphWarning
	# Antes: que el arco de daño desaparezca a los 0.9 s (cola de la fila 7).
	var damage := _hud.component_node(CombatHUD.Component.DAMAGE) as HUDDamageDirection
	await _advance(0.9)
	var damage_gone := damage.active_count() == 0
	_rows[7] = bool(_rows.get(7, false)) and damage_gone
	if not damage_gone:
		fail("7 · a los 0.9 s todavía quedan %d arcos de daño" % damage.active_count())

	Events.enemy_attack_telegraphed.emit(_enemy, &"stomp", TELEGRAPH_SECONDS)
	await _advance(0.02)
	var key := telegraph.current_key()
	var text := telegraph.display_text()
	var full := telegraph.progress()
	await _advance(TELEGRAPH_SECONDS - TELEGRAPH_TOLERANCE - 0.02)
	var before := telegraph.is_active()
	await _advance(TELEGRAPH_TOLERANCE * 2.0)
	var after := telegraph.is_active()
	print("  [8] clave '%s' → «%s» · windup %.2f → activo antes %s / después %s"
			% [key, text, full, str(before), str(after)])
	_row(8, key == "HUD_TELEGRAPH_STOMP" and text != key and not text.is_empty()
			and full > 0.9 and before and not after,
			"8 · clave '%s' (esperado HUD_TELEGRAPH_STOMP), texto '%s', windup %.2f, "
			% [key, text, full] + "activo a 1.05 s %s, a 1.15 s %s"
			% [str(before), str(after)])


# --- Fila 9 -----------------------------------------------------------------------------------

## El EMP dura 3.0 s exactos, mueve los componentes y los devuelve a
## [constant Vector2.ZERO]; un segundo pulso **reinicia** el contador.
func _check_glitch() -> void:
	var glitch := _hud.component_node(CombatHUD.Component.GLITCH) as HUDGlitchLayer
	var energy_system := _rig.get_energy_system()
	if energy_system == null:
		_row(9, false, "9 · el rig no expone el EnergySystem")
		return
	# Llega por la señal **local** del `EnergySystem` (`docs/09` §2.9), no por el bus:
	# es la conexión que [method CombatHUD.bind_drone] rehace en cada respawn.
	energy_system.emp_hit.emit(EMP_SECONDS)
	await _advance(0.2)
	var started := _hud.is_glitching()
	var moved := false
	var strength := glitch.emp_strength
	for _step: int in 24:
		await _advance(STEP)
		for component: CombatHUDComponent in _all_components():
			if not component.glitch_offset.is_zero_approx():
				moved = true
		if moved:
			break
	var bounded := true
	for component: CombatHUDComponent in _all_components():
		if component.glitch_offset.length() > HUDGlitchLayer.MAX_OFFSET * 1.5:
			bounded = false

	# Segundo pulso a la mitad: reinicia a 3.0 s, no acumula.
	await _advance(1.5 - 0.2 - float(24) * STEP)
	energy_system.emp_hit.emit(EMP_SECONDS)
	await _advance(EMP_SECONDS - EMP_TOLERANCE)
	var still := _hud.is_glitching()
	await _advance(EMP_TOLERANCE * 2.0)
	var done := not _hud.is_glitching()
	var zeroed := true
	var offenders := PackedStringArray()
	for component: CombatHUDComponent in _all_components():
		if not component.glitch_offset.is_zero_approx() or component.glitch_scramble \
				or component.glitch_blank:
			zeroed = false
			offenders.append(component.name)
	print("  [9] arranca %s (e=%.2f) · desplaza %s · acotado %s · reinicia %s · termina %s · a cero %s"
			% [str(started), strength, str(moved), str(bounded), str(still), str(done),
			str(zeroed)])
	_row(9, started and moved and bounded and still and done and zeroed
			and is_zero_approx(glitch.emp_strength),
			"9 · arranca %s, mueve %s, acotado %s, sigue a 2.9 s %s, termina a 3.1 s %s, "
			% [str(started), str(moved), str(bounded), str(still), str(done)]
			+ "desplazamientos residuales [%s]" % ", ".join(offenders))


# --- Fila 10 ----------------------------------------------------------------------------------

## La cuenta de reconstrucción aparece con [method RespawnController.is_respawning] y
## arranca en los 12 s de `docs/09` §3.5.
func _check_respawn() -> void:
	var overlay := _hud.component_node(CombatHUD.Component.RESPAWN) as HUDRespawnOverlay
	var controller := _rig.get_respawn_controller()
	if controller == null:
		_row(10, false, "10 · el rig no expone el RespawnController")
		return
	var idle := not overlay.is_showing()
	controller.force_respawn()
	await _advance(0.05)
	await wait_physics(2)
	await _advance(0.05)
	var showing := overlay.is_showing()
	var remaining := overlay.remaining()
	var hull_plain := not overlay.shows_no_battery()
	await _shoot("respawn")

	# WP-24e: la reconstrucción por batería agotada escribe «SIN BATERÍA» bajo el
	# título, y la del casco no. Es la única diferencia visible entre las dos, y sin
	# ella el piloto no puede saber que lo que falló fue la gestión de la batería.
	controller.reset()
	controller.force_respawn(RespawnController.Reason.ENERGY)
	await _advance(0.05)
	await wait_physics(2)
	await _advance(0.05)
	var no_battery := overlay.shows_no_battery()
	var battery_text := tr(HUDRespawnOverlay.NO_BATTERY_KEY)

	# Se cancela la cuenta: el resto del check necesita el dron visible y en su sitio.
	controller.reset()
	_freeze_drone()
	var level := _level as LevelBase
	var _focused := level.focus_camera(_rig.get_fpv_camera())
	await _advance(0.05)
	var cleared := not overlay.is_showing()
	print("  [10] en reposo %s · visible %s · faltan %.1f s · cancelado %s · por casco sin motivo %s · por batería '%s' %s"
			% [str(idle), str(showing), remaining, str(cleared), str(hull_plain),
			battery_text, str(no_battery)])
	_row(10, idle and showing and absf(remaining - RESPAWN_SECONDS) <= RESPAWN_TOLERANCE
			and cleared,
			"10 · reposo %s, visible %s, restante %.2f s (esperado %.1f ±%.1f), cancelado %s"
			% [str(idle), str(showing), remaining, RESPAWN_SECONDS, RESPAWN_TOLERANCE,
			str(cleared)])
	_row(10, hull_plain and no_battery,
			"10 · el cartel distingue los dos motivos: por casco sin línea de motivo (%s),"
			% str(hull_plain) + " por batería con «%s» (%s)" % [battery_text, str(no_battery)])
	_row(10, battery_text != HUDRespawnOverlay.NO_BATTERY_KEY,
			"10 · la clave '%s' está traducida (devolvió la clave cruda)"
			% HUDRespawnOverlay.NO_BATTERY_KEY)


# --- Fila 12 ----------------------------------------------------------------------------------

## El cronómetro avanza con la ronda y la línea de objetivo refleja el objetivo en
## curso del secuenciador.
func _check_timer_and_objective() -> void:
	var timer := _hud.component_node(CombatHUD.Component.TIMER) as HUDRoundTimer
	var line := _hud.component_node(CombatHUD.Component.OBJECTIVE) as HUDObjectiveLine
	var elapsed := _manager.get_elapsed_seconds()
	var shown := timer.elapsed_seconds()
	var text := timer.text()
	var well_formed := text.length() == 5 and text[2] == ":"

	var sequencer := _manager.sequencer
	var objective := sequencer.get_current() if sequencer != null else null
	line.refresh_objective()
	var title := line.title()
	var matches := objective != null and title == tr(objective.title_key) \
			and not title.is_empty() and title != objective.title_key
	print("  [12] cronómetro %.2f s del manager / %.2f s del HUD → «%s» · objetivo «%s»"
			% [elapsed, shown, text, title])
	_row(12, well_formed and absf(shown - elapsed) < 1.5 and matches,
			"12 · texto '%s' (mm:ss %s), HUD %.2f vs ronda %.2f, título '%s'"
			% [text, str(well_formed), shown, elapsed, title])


# --- Fila 16 ----------------------------------------------------------------------------------

## El marcador del punto débil no aparece antes de los ocho segundos, aparece después,
## trae el rótulo del grupo y la distancia, y se apaga con un acierto débil (WP-24d).
##
## El reloj se adelanta con [method WeakPointTracker.set_idle_seconds] en vez de
## avanzar ocho segundos de reloj manual: ocho segundos son 480 pasos de 1/60 y en la
## corrida con ventana son ocho segundos de pared. Lo que sí se mide de verdad es que
## el acumulador **suba** con el tiempo y que el umbral esté donde dice estar: se
## cruza con dos pasos de 0.1 s alrededor de los 8.0 s.
func _check_weak_hint() -> void:
	var hint := _hud.component_node(CombatHUD.Component.WEAK_HINT) as HUDWeakPointHint
	hint.clear_enemies()
	hint.bind_enemy(_enemy)
	# Las cuatro rodillas están expuestas siempre (`docs/07` §4); se publica por el
	# bus para que el check no dependa de que la IA congelada las haya evaluado.
	for index: int in 4:
		Events.enemy_weak_point_state.emit(_enemy, WEAK_POINT_IDS[index], true)
	hint.on_weak_hit()
	await _advance(0.5)
	var counting := hint.tracker.idle_seconds() > 0.4 and hint.tracker.has_exposed()
	var quiet := not hint.is_active()

	hint.tracker.set_idle_seconds(WeakPointTracker.IDLE_SECONDS - 0.15)
	await _advance(0.1)
	var still_quiet := not hint.is_active()
	await _advance(0.1)
	var armed := hint.is_active()
	# Un par de pasos más para que la opacidad suba y el componente elija blanco.
	await _advance(HUDWeakPointHint.FADE_SECONDS + 0.1)
	var showing := hint.is_showing()
	var target_id := hint.target_id()
	var label_key := hint.label_key()
	var metres := hint.distance()
	var knee_ids := PackedStringArray()
	for index: int in 4:
		knee_ids.append(String(WEAK_POINT_IDS[index]))
	var on_a_knee := knee_ids.has(String(target_id)) and label_key == "WP_KNEE"

	# Acertarle a un débil lo apaga: es el acuse de que el jugador entendió.
	Events.hit_confirmed.emit(Vector3.ZERO, true, false)
	await _advance(HUDWeakPointHint.FADE_SECONDS + 0.2)
	var off := not hint.is_active() and not hint.is_showing()
	print("  [16] cuenta %.2f s · antes %s · después %s · blanco '%s' (%s) a %.0f m · apagado %s"
			% [hint.tracker.idle_seconds(), str(quiet), str(armed), target_id, label_key,
			metres, str(off)])
	_row(16, counting and quiet and still_quiet and armed and showing and on_a_knee
			and metres > 0.0 and off,
			"16 · acumula %s, callado antes %s/%s, activo después %s, visible %s, "
			% [str(counting), str(quiet), str(still_quiet), str(armed), str(showing)]
			+ "blanco '%s' con rótulo '%s' (esperado una rodilla), %.1f m, apagado %s"
			% [target_id, label_key, metres, str(off)])
	hint.on_weak_hit()


# --- Fila 17 ----------------------------------------------------------------------------------

## Los cuatro consejos contextuales salen con su disparador, **una sola vez cada uno**
## y se van solos (WP-24d).
func _check_coach() -> void:
	var coach := _hud.component_node(CombatHUD.Component.COACH) as HUDCoachTip
	coach.reset()
	# La fila 4 rompió los ocho puntos débiles por el bus: sin tirar ese estado, el
	# reloj de los débiles no arrancaría nunca porque no quedaría ninguno expuesto.
	coach.clear_enemies()
	coach.bind_enemy(_enemy)

	# Primer `head_laser`: el visor se expone mientras carga.
	Events.enemy_attack_telegraphed.emit(_enemy, &"head_laser", 1.4)
	await _advance(0.1)
	var visor_tip := coach.current_key() == "HUD_COACH_VISOR" and coach.is_showing()
	var translated := coach.display_text() != coach.current_key() \
			and not coach.display_text().is_empty()

	# El segundo `head_laser` **no** repite: un consejo que se repite es ruido.
	coach.clear_tip()
	await _advance(0.05)
	Events.enemy_attack_telegraphed.emit(_enemy, &"head_laser", 1.4)
	await _advance(0.1)
	var once := coach.current_key().is_empty() and not coach.is_showing()

	Events.enemy_attack_telegraphed.emit(_enemy, &"emp_pulse", 1.0)
	await _advance(0.1)
	var emp_tip := coach.current_key() == "HUD_COACH_EMP"
	Events.enemy_attack_telegraphed.emit(_enemy, &"stomp", 1.0)
	await _advance(0.1)
	var stomp_tip := coach.current_key() == "HUD_COACH_STOMP"

	# El cuarto no lo dispara un ataque sino el reloj de los puntos débiles.
	for index: int in 4:
		Events.enemy_weak_point_state.emit(_enemy, WEAK_POINT_IDS[index], true)
	coach.clear_tip()
	coach.tracker.set_idle_seconds(WeakPointTracker.IDLE_SECONDS - 0.05)
	await _advance(0.2)
	var weak_tip := coach.current_key() == HUDCoachTip.WEAK_KEY \
			and coach.has_fired(HUDCoachTip.WEAK_KEY)

	# Y se va solo, sin que nadie lo cierre.
	await _advance(HUDCoachTip.TIP_SECONDS + HUDCoachTip.FADE_SECONDS + 0.2)
	var faded := not coach.is_showing()
	var fired := coach.fired_count()

	# Ningún consejo puede salirse del bloque en ningún idioma: `HUDDraw.text` recorta
	# y un consejo cortado a la mitad enseña menos que ninguno. La primera captura de
	# WP-24d mostraba «EL RESTO ES BLIND» a 20 px, y de ahí sale el ajuste de cuerpo.
	var tip_keys := PackedStringArray([HUDCoachTip.WEAK_KEY])
	for key: String in HUDCoachTip.TIP_KEYS.values():
		tip_keys.append(key)
	var previous := TranslationServer.get_locale()
	var overflow := PackedStringArray()
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in tip_keys:
			var width := coach.text_width(tr(key))
			if width > HUDCoachTip.BLOCK_WIDTH - HUDCoachTip.PADDING * 2.0:
				overflow.append("%s@%s(%.0fpx)" % [key, locale, width])
	TranslationServer.set_locale(previous)

	print("  [17] visor %s · una sola vez %s · emp %s · stomp %s · débiles %s · "
			% [str(visor_tip), str(once), str(emp_tip), str(stomp_tip), str(weak_tip)]
			+ "%d consejos disparados · se fue solo %s · %d se pasan de ancho"
			% [fired, str(faded), overflow.size()])
	_row(17, visor_tip and translated and once and emp_tip and stomp_tip and weak_tip
			and faded and fired == 4 and overflow.is_empty(),
			"17 · visor %s (traducido %s), una sola vez %s, emp %s, stomp %s, "
			% [str(visor_tip), str(translated), str(once), str(emp_tip), str(stomp_tip)]
			+ "débiles %s, se fue solo %s, disparados %d (esperado 4), se pasan [%s]"
			% [str(weak_tip), str(faded), fired, ", ".join(overflow)])
	coach.reset()


# --- Fila 13 ----------------------------------------------------------------------------------

## Ninguna clave nueva se queda sin texto en es ni en en. Es la red del riesgo 12 de
## `docs/12` §10: una clave faltante se ve en pantalla como su propio nombre.
func _check_translations() -> void:
	var keys := PackedStringArray([HUDEnergyBar.LABEL_KEY, HUDEnergyBar.LOW_KEY,
			HUDHullBar.LABEL_KEY, HUDHeatGauge.LABEL_KEY, HUDHeatGauge.LOCK_KEY,
			HUDCityBar.LABEL_KEY, HUDReticle.LOCK_KEY, HUDBossBar.PHASE_KEY,
			HUDBossBar.FALLBACK_NAME_KEY, HUDRespawnOverlay.TITLE_KEY,
			HUDRespawnOverlay.MULTIPLIER_KEY, HUDIntroBanner.SKIP_KEY,
			HUDObjectiveLine.STEP_KEY, HUDTelegraphWarning.GENERIC_KEY,
			HUDIntroBanner.WEAK_HINT_KEY, HUDCoachTip.WEAK_KEY])
	for key: String in HUDOffscreenMarkers.KIND_KEYS.values():
		keys.append(key)
	for attack: String in ["stomp", "leg_sweep", "head_laser", "siege_beam", "emp_pulse",
			"pounce", "shake_off", "climb"]:
		keys.append(HUDTelegraphWarning.KEY_PREFIX + attack.to_upper())
	# Las claves que agrega WP-24d: los consejos, los rótulos de grupo de la barra
	# —que salen del `hud_key` del perfil, no de una tabla de acá—, los rótulos del
	# marcador de punto débil y los contadores de la línea de objetivo.
	for key: String in HUDCoachTip.TIP_KEYS.values():
		keys.append(key)
	for group: Array in BOSS_GROUPS:
		keys.append(String(group[2]))
	for key: String in ["WP_KNEE", "WP_VISOR", "WP_CORE", "OBJ_COUNT_KNEES",
			"OBJ_COUNT_CORES", "OBJ_BREAK_CORES_TITLE", "OBJ_BREAK_CORES_DESC",
			"OBJ_BREAK_CORES_DONE", "OBJ_SELFDESTRUCT_TITLE", "OBJ_SELFDESTRUCT_DESC",
			"OBJ_SELFDESTRUCT_DONE"]:
		keys.append(key)

	var previous := TranslationServer.get_locale()
	var missing := PackedStringArray()
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in keys:
			if tr(key) == key:
				missing.append("%s@%s" % [key, locale])
	TranslationServer.set_locale(previous)
	print("  [13] %d claves comprobadas en es y en · faltan %d"
			% [keys.size(), missing.size()])
	_row(13, missing.is_empty(), "13 · claves sin texto: %s" % ", ".join(missing))


# --- Fila 14 ----------------------------------------------------------------------------------

## **Prueba negativa.** Un check cuyo validador acepta cualquier cosa siempre pasa. Se
## le dan al mismo validador de la fila 6 tres marcadores inventados —uno con `NAN`,
## uno con el ángulo `NAN` y uno fuera del rectángulo— y se exige que los rechace; y
## se comprueba que [method HUDProjection.marker_for] **no** produce ninguno de los
## tres ni siquiera con una posición no finita.
func _check_negative() -> void:
	var markers := _hud.component_node(CombatHUD.Component.MARKERS) as HUDOffscreenMarkers
	var rect := markers.screen_rect()
	var rejected := 0
	for bogus: Dictionary in [
		{"pos": Vector2(NAN, NAN), "angle": 0.0, "offscreen": true, "distance": 1.0},
		{"pos": rect.get_center(), "angle": NAN, "offscreen": false, "distance": 1.0},
		{"pos": rect.position - Vector2(500.0, 500.0), "angle": 0.0, "offscreen": true,
				"distance": 1.0},
	]:
		if not _marker_is_valid(bogus, rect):
			rejected += 1
	var good := _marker_is_valid({"pos": rect.get_center(), "angle": 0.0,
			"offscreen": false, "distance": 1.0}, rect)

	var camera := _hud.get_camera()
	var degenerate := true
	if camera != null:
		for point: Vector3 in [camera.global_position, Vector3(INF, 0.0, 0.0),
				Vector3(NAN, NAN, NAN), camera.global_position - camera.global_basis.z * -1e6]:
			var marker := HUDProjection.marker_for(camera, point, rect,
					HUDOffscreenMarkers.MARGIN)
			if not _marker_is_valid(marker, rect):
				degenerate = false
	print("  [14] 3 marcadores inventados rechazados: %d · uno válido aceptado: %s · "
			% [rejected, str(good)] + "casos degenerados sanos: %s" % str(degenerate))
	_row(14, rejected == 3 and good and degenerate,
			"14 · rechazados %d/3, válido aceptado %s, degenerados sanos %s"
			% [rejected, str(good), str(degenerate)])


# --- Fila 15 ----------------------------------------------------------------------------------

## Al liberar el nivel no puede quedar ninguna conexión del `CombatHUD` colgada en
## `Events`: el bus es un autoload y vive más que cualquier escena, así que una
## conexión olvidada es un `Callable` sobre un objeto liberado que explota en la
## ronda siguiente (`docs/12` §9.2 fila 11).
func _check_teardown() -> void:
	var before := _count_hud_connections()
	if _probes != null and is_instance_valid(_probes):
		_probes.queue_free()
		_probes = null
	_level.queue_free()
	_level = null
	_manager = null
	_hud = null
	_rig = null
	_enemy = null
	await wait_frames(3)
	var after := _count_hud_connections()
	print("  [15] conexiones del CombatHUD en Events: %d antes, %d después"
			% [before, after])
	_row(15, before > 0 and after == 0,
			"15 · conexiones a Events antes %d (esperado > 0), después %d (esperado 0)"
			% [before, after])


# --- Capturas ---------------------------------------------------------------------------------

## Deja el HUD con los catorce componentes alimentados a la vez y saca las capturas.
func _shoot_all() -> void:
	if shots_dir.is_empty() or Graphics.is_headless():
		print("  [capturas] SKIP — %s"
				% ("no se pasó --shots" if shots_dir.is_empty()
				else "sin rasterizado en --headless"))
		return
	_feed_everything()
	Events.enemy_attack_telegraphed.emit(_enemy, &"siege_beam", 4.0)
	await _advance(0.4)
	await wait_frames(SETTLE_FRAMES)
	await shot("combat_hud")

	# WP-24d: la barra con sus rótulos, el consejo contextual y el marcador cian del
	# punto débil, los tres a la vez. Es la captura que hay que mirar para decidir si
	# la pantalla enseña o satura.
	var coach := _hud.component_node(CombatHUD.Component.COACH) as HUDCoachTip
	var hint := _hud.component_node(CombatHUD.Component.WEAK_HINT) as HUDWeakPointHint
	coach.reset()
	var _shown := coach.show_tip(HUDCoachTip.WEAK_KEY)
	hint.clear_enemies()
	hint.bind_enemy(_enemy)
	for index: int in 4:
		Events.enemy_weak_point_state.emit(_enemy, WEAK_POINT_IDS[index], true)
	hint.tracker.set_idle_seconds(WeakPointTracker.IDLE_SECONDS + 1.0)
	await _advance(HUDWeakPointHint.FADE_SECONDS + 0.2)
	await wait_frames(SETTLE_FRAMES)
	await shot("coach_hint")
	coach.clear_tip()
	hint.on_weak_hit()
	await _advance(HUDWeakPointHint.FADE_SECONDS + 0.2)

	# Con el EMP encendido: la captura tiene que seguir siendo legible.
	var energy_system := _rig.get_energy_system()
	if energy_system != null:
		energy_system.emp_hit.emit(EMP_SECONDS)
	await _advance(0.5)
	await wait_frames(SETTLE_FRAMES)
	await shot("glitch")
	if energy_system != null:
		var glitch := _hud.component_node(CombatHUD.Component.GLITCH) as HUDGlitchLayer
		glitch.stop()
	await _advance(0.1)
	print("  [capturas] combat_hud.png, coach_hint.png, glitch.png, cinematic.png y "
			+ "respawn.png en %s" % shots_dir)


func _shoot(label: String) -> void:
	if shots_dir.is_empty() or Graphics.is_headless():
		return
	await wait_frames(SETTLE_FRAMES)
	await shot(label)


# --- Utilidades -------------------------------------------------------------------------------

## Instancia el nivel, congela al jefe y toma las referencias. Devuelve `false` si
## algo falta, y en ese caso el check ya anotó el fallo.
func _enter_level() -> bool:
	Global.selected_round = ROUND_ID
	Global.round_seed = SEED
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		fail("no se pudo cargar %s" % LEVEL_SCENE)
		return false
	_level = packed.instantiate() as BattleLevel
	if _level == null:
		fail("%s no instancia un BattleLevel" % LEVEL_SCENE)
		return false
	add_child(_level)
	await wait_frames(3)

	_manager = _level.get_round_manager()
	_hud = _level.get_combat_hud()
	_rig = _level.drone_rig as DroneRig
	if _manager == null:
		fail("el nivel no trae RoundManager")
		return false
	if _hud == null:
		fail("el nivel no trae el CombatHUD en CombatHUDSlot (docs/12 §4)")
		return false
	if _rig == null:
		fail("el nivel no trae DroneRig")
		return false
	var enemies := _manager.get_enemies()
	if enemies.is_empty():
		fail("la ronda no instanció ningún enemigo")
		return false
	_enemy = enemies[0] as EnemyBase

	# Respaldo de `Global.debug_freeze_ai` mientras WP-18 termina de honrarla: con el
	# contenedor deshabilitado, el jefe no piensa ni recalcula exposiciones, así que
	# todo lo que mueve el HUD viene del bus y es reproducible.
	var enemies_root := _level.get_node_or_null(^"Enemies") as Node3D
	if enemies_root != null:
		enemies_root.process_mode = Node.PROCESS_MODE_DISABLED

	# La tarjeta de objetivo provisional tiene que haber quedado apagada por tener el
	# slot ocupado (`docs/11` §5.2).
	var legacy := _level.get_node_or_null(^"ObjectiveHUD") as CanvasLayer
	expect(legacy == null or not legacy.visible,
			"la ObjectiveHUD provisional sigue encendida con el CombatHUD instalado")
	return true


## Clava el dron donde apareció, desarmado y congelado.
##
## `skip_intro()` lo descongela para que el piloto vuele, pero acá no hay piloto: un
## dron suelto cae los 40 m del punto de reaparición, choca contra la ciudad y el
## [Hull] empieza a publicar `drone_damaged` por su cuenta. Esos arcos de daño
## espontáneos hacían fallar la fila 7 sólo en la corrida con ventana, que es más
## lenta y le daba tiempo de estrellarse. Congelado, **todo** lo que mueve el HUD
## durante el check viene del bus.
func _freeze_drone() -> void:
	var drone := _rig.get_drone()
	if drone == null or not is_instance_valid(drone):
		return
	drone.force_disarm()
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	drone.freeze = true
	drone.visible = true


## Alimenta los catorce componentes con un estado de combate creíble, el de las
## capturas: batería a media carga, casco golpeado, arma caliente, jefe en fase 3 con
## una rodilla rota y la ciudad mordida.
func _feed_everything() -> void:
	# La barra del jefe acumula estado por evento y no hay ningún hecho que
	# «desrompa» una parte: se la reinicia volviendo a vincular al enemigo, que es lo
	# mismo que pasa en el juego cuando aparece un jefe nuevo.
	var boss := _hud.component_node(CombatHUD.Component.BOSS) as HUDBossBar
	boss.clear_enemies()
	boss.bind_enemy(_enemy)
	Events.enemy_part_broken.emit(_enemy, WEAK_POINT_IDS[0], Vector3.ZERO)
	Events.energy_changed.emit(0.42, false)
	Events.hull_changed.emit(0.62)
	Events.weapon_heat_changed.emit(0.74, false)
	Events.hit_confirmed.emit(Vector3.ZERO, true, false)
	Events.city_integrity_changed.emit(0.78)
	Events.enemy_phase_changed.emit(_enemy, &"p2_alert")
	Events.enemy_weak_point_state.emit(_enemy, &"wp_head_visor", true)
	var camera := _hud.get_camera()
	if camera != null:
		Events.drone_damaged.emit(28.0, camera.global_transform * Vector3(20.0, 0.0, 12.0))


## Avanza el reloj manual del HUD [param seconds] segundos en pasos de
## [constant STEP], cediendo un cuadro por paso para que el dibujo y el resto del
## nivel acompañen.
func _advance(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(STEP, left)
		_hud.advance(step)
		left -= step
		await get_tree().process_frame


## Los catorce componentes que dibujan, sin el `GlitchLayer`.
func _all_components() -> Array[CombatHUDComponent]:
	var found: Array[CombatHUDComponent] = []
	for component: int in CombatHUD.Component.values():
		if component == int(CombatHUD.Component.GLITCH):
			continue
		var node := _hud.component_node(component as CombatHUD.Component)
		if node != null:
			found.append(node)
	return found


## Criterio único de «marcador sano», compartido por la fila 6 y por la prueba
## negativa de la fila 14. Que sea **uno solo** es lo que hace que la prueba negativa
## signifique algo.
func _marker_is_valid(marker: Dictionary, rect: Rect2) -> bool:
	if not marker.has("pos") or not marker.has("angle") or not marker.has("distance"):
		return false
	var pos: Vector2 = marker["pos"]
	if not pos.is_finite():
		return false
	if not is_finite(float(marker["angle"])) or not is_finite(float(marker["distance"])):
		return false
	return rect.grow(1.0).has_point(pos)


## Conexiones vivas del `CombatHUD` —o de cualquiera de sus componentes— en el bus.
func _count_hud_connections() -> int:
	var total := 0
	for signal_info: Dictionary in Events.get_signal_list():
		var signal_name := StringName(signal_info["name"])
		for connection: Dictionary in Events.get_signal_connection_list(signal_name):
			var callable: Callable = connection["callable"]
			var target := callable.get_object()
			if target == null:
				continue
			if target is CombatHUD or target is CombatHUDComponent:
				total += 1
	return total


func _row(number: int, ok: bool, message: String) -> void:
	_rows[number] = ok
	if not ok:
		fail(message)


func _print_rows() -> void:
	print("  --- filas de docs/12 §9.2 ---")
	for row: int in range(1, ROW_TITLES.size() + 1):
		if not _rows.has(row):
			fail("%d · %s: la fila no llegó a ejecutarse" % [row, ROW_TITLES[row - 1]])
			print("  %2d %-34s FAIL" % [row, ROW_TITLES[row - 1]])
			continue
		print("  %2d %-34s %s" % [row, ROW_TITLES[row - 1],
				"OK" if _rows[row] else "FAIL"])


## Devuelve la bandera de congelado aunque el check muera por timeout.
func _on_check_finished(_ok: bool, _failures: int) -> void:
	Global.debug_freeze_ai = false
