## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Check de la cámara FPV y de la proyección del HUD (`docs/03` §5 y §11.6,
## `docs/12` §9.1).
##
## Corre dentro del nivel de vuelo libre, que es la única escena de juego que hay hoy,
## y verifica las dos mitades del contrato:
## - **La matemática** (sirve en `--headless`): la dirección de la cámara cae en el
##   centro de la pantalla en los tres modos de ojo de pez; un barrido de actitudes y
##   direcciones nunca devuelve una mezcla de finito y `NAN`, ni `INF`; lo que queda
##   fuera del campo —y todo lo que está detrás— devuelve `NAN` en las dos componentes;
##   `marker_for()` no devuelve `NAN` nunca; `edge_clamp()` es idempotente; el remapeo
##   de FAST es monótono en el radio; en FULL la fórmula equidistante ubica una
##   dirección a 45° de guiñada donde dice `docs/12` §3.1.
## - **La imagen** (necesita ventana): una captura por modo y el coste en draw calls
##   del ojo de pez respecto de OFF.
##
## Además comprueba lo que `docs/03` §5 le pide al nivel: que `LevelBase` ponga la FPV
## primera en el ciclo de cámaras y que sea la cámara activa al cargar.
##
## **WP-08** cierra las dos filas que quedaban en SKIP (`docs/12` §9.1):
## - **Fila 4** ([method _check_horizon_match]): el horizonte que dibuja [HUDHorizon] en
##   modo `camera` cae sobre la transición cielo/suelo de la captura, con menos de
##   [constant HORIZON_TOLERANCE] px de error, en los tres modos y en tres actitudes.
##   Necesita ventana; en `--headless` se imprime el SKIP.
## - **Fila 5** ([method _check_hud_components]): los 12 componentes del
##   `enum Component` existen y obedecen a `show_component()` —esto sí corre headless— y
##   se captura uno `hud_<modo>.png` por modo con los doce visibles y `preview_mode`
##   encendido.
##
## El check devuelve `GameSettings.hud_config` a lo que había antes de correr.
##
## Corre así:
##   godot --headless --path godot res://tools/hud_projection_check.tscn
##   godot --windowed --resolution 960x540 --path godot res://tools/hud_projection_check.tscn -- --shots=tools/out/shots
extends CheckRunner

## Tolerancia del centro de pantalla, en píxeles (`docs/03` §11.6).
const CENTRE_TOLERANCE: float = 2.0

## Tolerancia de la fórmula equidistante de FULL, en píxeles.
const EQUIDISTANT_TOLERANCE: float = 3.0

## Guiñada con la que se verifica la fórmula equidistante, en grados.
const EQUIDISTANT_YAW: float = 45.0

## Margen alrededor del borde del campo donde no se exige nada: ahí la diferencia
## entre «se ve» y «no se ve» es de un flotante, y no es lo que se está midiendo.
const FIELD_GUARD: float = 0.01

## Margen de los marcadores, en píxeles (`docs/12` §8).
const MARKER_MARGIN: float = 56.0

## Actitudes del barrido: cabeceo × alabeo, en grados.
const SWEEP_PITCH: Array[float] = [-80.0, -40.0, 0.0, 40.0, 80.0]
const SWEEP_ROLL: Array[float] = [-180.0, -90.0, 0.0, 90.0]

## Azimutes del barrido, en pasos de 10°.
const SWEEP_AZIMUTHS: int = 36

## Ángulos polares del barrido, en grados. Los tres primeros caen dentro de cualquier
## campo razonable; los tres últimos, fuera, y dos de ellos detrás.
const SWEEP_POLARS: Array[float] = [10.0, 40.0, 70.0, 88.0, 100.0, 170.0]

## Pasos del barrido de monotonía del remapeo de FAST.
const MONOTONIC_STEPS: int = 64

## Cuántas veces se cicla el modo de ojo de pez para buscar fugas de nodos.
const LEAK_CYCLES: int = 3

## Tolerancia de nodos al volver al modo inicial.
const LEAK_TOLERANCE: int = 2

## Frames que se dejan pasar para que las sub-viewports dibujen antes de medir o
## capturar.
const SETTLE_FRAMES: int = 6

## Pose desde la que se sacan las capturas: enfrente de la torre de 40 m, lo bastante
## cerca como para que la niebla no se la coma y lo bastante alto como para que el
## horizonte curvo entre en el cuadro.
const SHOT_POSITION: Vector3 = Vector3(-22.0, 12.0, 78.0)

# --- Fila 4 de `docs/12` §9.1: el HUD contra la imagen ----------------------------------------

## Error máximo admitido entre la `y` que dibuja [HUDHorizon] y la transición
## cielo/suelo de la captura, en píxeles (`docs/12` §9.1 fila 4).
const HORIZON_TOLERANCE: float = 6.0

## Pose desde la que se mide el horizonte: despejada de pilares en la columna central.
const HORIZON_POSITION: Vector3 = Vector3(0.0, 6.0, 120.0)

## Actitudes de cámara con las que se mide, en grados `(cabeceo, alabeo)`. La primera
## deja el horizonte en el centro exacto; las otras dos lo sacan de ahí, que es lo
## único que hace del criterio una medida y no una tautología.
const HORIZON_ATTITUDES: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(15.0, 0.0), Vector2(25.0, 12.0),
]

## Lado del plano negro que se agrega para medir, en metros. El suelo del nivel de
## vuelo libre mide 800 m: desde 120 m de distancia su borde cae casi un grado por
## debajo del horizonte verdadero, más que la tolerancia entera. Con un plano
## prácticamente infinito la transición de la imagen **es** el horizonte.
const HORIZON_PLANE_SIDE: float = 40000.0

## Altura del plano de medición, en metros. Justo debajo del suelo del nivel para que
## no haya z-fighting y el nivel siga siendo el que se ve de cerca.
const HORIZON_PLANE_Y: float = -0.08

## Filas de los extremos de la columna que se promedian para saber qué luminancia tiene
## el cielo y cuál el suelo.
const LUMINANCE_SAMPLE_ROWS: int = 10

## Filas del borde que se descartan al muestrear: el compuesto del ojo de pez puede
## tener una fila de relleno.
const LUMINANCE_EDGE_MARGIN: int = 4

## Separación mínima de luminancia entre cielo y suelo para que la medida signifique
## algo, en `[0, 1]`.
const LUMINANCE_MIN_CONTRAST: float = 0.05

@export var level_path: NodePath = ^"FreeFlightLevel"

var _level: LevelBase = null
var _rig: DroneRig = null
var _drone: Drone = null
var _camera: FPVCamera = null
var _camera_rig: CameraRig = null
var _hud: FlightHUD = null
var _original_mode: int = 0
var _draw_calls: Dictionary[String, int] = {}

## Copia de `GameSettings.hud_config` de antes del check (`docs/12` §9.1).
var _original_hud_config: Dictionary = {}


func _run() -> void:
	_level = get_node_or_null(level_path) as LevelBase
	if _level == null:
		fail("falta el nivel '%s'" % str(level_path))
		return
	_rig = _level.get_node_or_null(^"DroneRig") as DroneRig
	if _rig == null:
		fail("el nivel no tiene 'DroneRig'")
		return
	_drone = _rig.get_drone()
	_camera = _rig.get_fpv_camera()
	_camera_rig = _rig.get_camera_rig()
	if _camera == null or _camera_rig == null:
		fail("el rig no expone CameraRig/FPVCamera (get_fpv_camera() devolvió %s)"
				% str(_camera))
		return
	_hud = _rig.get_flight_hud()
	_original_mode = int(Graphics.fisheye_mode)
	_original_hud_config = GameSettings.hud_config.duplicate(true)
	await wait_frames(2)

	_check_level_cameras()
	await _check_modes()
	_check_edge_clamp()
	_check_hud_projection()
	await _check_composite_layer()
	await _check_leaks()
	await _check_draw_calls()
	await _check_horizon_match()
	await _check_hud_components()
	_restore_mode()
	_restore_hud_config()


# --- [0] La FPV es la vista de juego ----------------------------------------------------------

## `docs/03` §5: `LevelBase` reconoce la FPV por `get_fpv_camera()`, la pone primera en
## el ciclo y la deja activa al cargar el nivel.
func _check_level_cameras() -> void:
	_level.collect_cameras()
	var names := PackedStringArray()
	for camera: Camera3D in _level.cameras:
		names.append(camera.name)
	var first := _level.cameras[0] if not _level.cameras.is_empty() else null
	print("  [0] cámaras del nivel: [%s]; activa '%s'; FPV current %s"
			% [", ".join(names),
			_level.active_camera().name if _level.active_camera() != null else "(ninguna)",
			str(_camera.is_current())])
	expect(first == _camera, "la FPV no quedó primera en el ciclo de cámaras del nivel")
	expect(_level.active_camera() == _camera and _camera.is_current(),
			"al cargar el nivel la cámara activa no es la FPV")
	expect(_camera.is_in_group(&"fpv_camera"), "la FPV no está en el grupo 'fpv_camera'")


# --- [1..5] Los tres modos --------------------------------------------------------------------

## Recorre OFF, FAST y FULL: centro, barrido, marcadores, monotonía, fórmula
## equidistante y captura.
func _check_modes() -> void:
	for mode: int in [Graphics.FisheyeMode.OFF, Graphics.FisheyeMode.FAST,
			Graphics.FisheyeMode.FULL]:
		await _set_mode(mode)
		var label := _mode_name(mode)
		var hfov := _camera.get_fisheye_hfov()
		var viewports := _camera.get_fisheye_viewports().size()
		print("  --- modo %s: hfov %.1f°, fov de render %.1f°, %d sub-viewport(s) ---"
				% [label, hfov, _camera.fov, viewports])
		expect(_camera.get_fisheye_mode() == mode,
				"la cámara quedó en el modo %d y se pidió %d"
				% [_camera.get_fisheye_mode(), mode])
		var expected_viewports := 0
		if mode == Graphics.FisheyeMode.FAST:
			expected_viewports = 1
		elif mode == Graphics.FisheyeMode.FULL:
			expected_viewports = 5
		expect(viewports == expected_viewports,
				"el modo %s construyó %d sub-viewports y esperaba %d"
				% [label, viewports, expected_viewports])
		_check_centre(label)
		_check_sweep(label, mode, hfov)
		_check_markers(label)
		if mode == Graphics.FisheyeMode.FAST:
			_check_monotonic(label, hfov)
		if mode != Graphics.FisheyeMode.OFF:
			_check_equidistant(label, hfov)
		await _shoot(label)


## §11.6 — `project_direction(−basis.z)` cae en el centro de la pantalla ±2 px.
func _check_centre(label: String) -> void:
	var centre := _screen_size() * 0.5
	var projected := _camera.project_direction(-_camera.global_basis.z)
	var error := INF
	if projected.is_finite():
		error = projected.distance_to(centre)
	print("  [1] %s: project_direction(−basis.z) = %s, centro %s, error %.4f px"
			% [label, str(projected), str(centre), error])
	expect(projected.is_finite(), "en %s la dirección de la cámara no se proyecta" % label)
	expect(error <= CENTRE_TOLERANCE,
			"en %s la dirección de la cámara cae a %.3f px del centro (tolerancia %.1f)"
			% [label, error, CENTRE_TOLERANCE])


## §11.6 y `docs/12` §9.1 fila 1 — barrido de actitudes × direcciones: nunca una mezcla
## de finito y `NAN`, nunca `INF`, `NAN` exactamente cuando la dirección está fuera del
## campo, y siempre `NAN` para lo que está detrás.
func _check_sweep(label: String, mode: int, hfov: float) -> void:
	var original := _camera_rig.rotation
	var samples := 0
	var visible := 0
	var mixed := 0
	var infinite := 0
	var false_visible := 0
	var false_hidden := 0
	var behind_visible := 0
	for pitch: float in SWEEP_PITCH:
		for roll: float in SWEEP_ROLL:
			_camera_rig.rotation = Vector3(deg_to_rad(pitch), 0.0, deg_to_rad(roll))
			_camera_rig.force_update_transform()
			_camera.force_update_transform()
			for polar: float in SWEEP_POLARS:
				var theta := deg_to_rad(polar)
				for step: int in SWEEP_AZIMUTHS:
					var azimuth := TAU * float(step) / float(SWEEP_AZIMUTHS)
					var local := Vector3(sin(theta) * cos(azimuth), sin(theta) * sin(azimuth),
							-cos(theta))
					var projected := _camera.project_direction(
							_camera.global_basis.orthonormalized() * local)
					samples += 1
					var nan_x := is_nan(projected.x)
					var nan_y := is_nan(projected.y)
					if nan_x != nan_y:
						mixed += 1
					if is_inf(projected.x) or is_inf(projected.y):
						infinite += 1
					var inside := _expect_visible(mode, hfov, theta)
					if projected.is_finite():
						visible += 1
						if inside == 0:
							false_visible += 1
						if polar > 90.0 + rad_to_deg(FIELD_GUARD):
							behind_visible += 1
					elif inside == 1:
						false_hidden += 1
	_camera_rig.rotation = original
	_camera_rig.force_update_transform()
	print("  [2] %s: %d muestras, %d visibles; mezclas NAN %d, INF %d, visibles de más %d, visibles de menos %d, detrás visibles %d"
			% [label, samples, visible, mixed, infinite, false_visible, false_hidden,
			behind_visible])
	expect(mixed == 0, "en %s hubo %d proyecciones con una sola componente NAN" % [label, mixed])
	expect(infinite == 0, "en %s hubo %d proyecciones con INF" % [label, infinite])
	expect(false_visible == 0,
			"en %s hubo %d direcciones fuera del campo que devolvieron un valor finito"
			% [label, false_visible])
	expect(false_hidden == 0,
			"en %s hubo %d direcciones dentro del campo que devolvieron NAN"
			% [label, false_hidden])
	expect(behind_visible == 0,
			"en %s hubo %d direcciones detrás de la cámara que no devolvieron NAN"
			% [label, behind_visible])


## Clasifica una dirección: `1` se tiene que ver, `0` no se tiene que ver, `-1` está
## tan al borde del campo que no se le exige nada.
##
## Sin ojo de pez el campo lo corta `is_position_behind`, que descarta todo lo que
## quede a menos de `near` metros de profundidad; con ojo de pez, el medio `hfov`.
func _expect_visible(mode: int, hfov: float, theta: float) -> int:
	if mode == Graphics.FisheyeMode.OFF:
		var depth := cos(theta)
		if absf(depth - _camera.near) < FIELD_GUARD:
			return -1
		return 1 if depth > _camera.near else 0
	var half_field := deg_to_rad(hfov) * 0.5
	if absf(theta - half_field) < FIELD_GUARD:
		return -1
	return 1 if theta < half_field else 0


## `docs/12` §9.1 fila 2 — `marker_for()` nunca devuelve `NAN` y siempre cae dentro del
## rectángulo de pantalla.
func _check_markers(label: String) -> void:
	var rect := Rect2(Vector2.ZERO, _screen_size())
	var inner := HUDProjection.inner_rect(rect, MARKER_MARGIN).grow(0.5)
	var samples := 0
	var not_finite := 0
	var outside := 0
	var origin := _camera.global_position
	for polar: float in SWEEP_POLARS:
		var theta := deg_to_rad(polar)
		for step: int in SWEEP_AZIMUTHS:
			var azimuth := TAU * float(step) / float(SWEEP_AZIMUTHS)
			var local := Vector3(sin(theta) * cos(azimuth), sin(theta) * sin(azimuth),
					-cos(theta))
			var world := origin + _camera.global_basis.orthonormalized() * local * 120.0
			var marker := HUDProjection.marker_for(_camera, world, rect, MARKER_MARGIN)
			samples += 1
			var pos: Vector2 = marker["pos"]
			var angle: float = marker["angle"]
			var distance: float = marker["distance"]
			if not pos.is_finite() or is_nan(angle) or is_inf(angle) or not is_finite(distance):
				not_finite += 1
			elif not inner.has_point(pos):
				outside += 1
	# El punto degenerado: el marcador está exactamente donde la cámara.
	var same := HUDProjection.marker_for(_camera, origin, rect, MARKER_MARGIN)
	var same_pos: Vector2 = same["pos"]
	if not same_pos.is_finite():
		not_finite += 1
	print("  [3] %s: %d marcadores, %d no finitos, %d fuera del rectángulo"
			% [label, samples + 1, not_finite, outside])
	expect(not_finite == 0, "en %s hubo %d marcadores con NAN o INF" % [label, not_finite])
	expect(outside == 0, "en %s hubo %d marcadores fuera del rectángulo" % [label, outside])


## El remapeo de FAST es monótono en el radio: a más ángulo, más lejos del centro, sin
## repliegues ni saltos. Es lo que garantiza que la imagen no se dé vuelta en los bordes.
func _check_monotonic(label: String, hfov: float) -> void:
	var half_field := deg_to_rad(hfov) * 0.5
	var centre := _screen_size() * 0.5
	var previous := -1.0
	var breaks := 0
	var last := 0.0
	for step: int in MONOTONIC_STEPS + 1:
		var theta := half_field * float(step) / float(MONOTONIC_STEPS)
		var local := Vector3(sin(theta), 0.0, -cos(theta))
		var projected := _camera.project_direction(
				_camera.global_basis.orthonormalized() * local)
		if not projected.is_finite():
			breaks += 1
			continue
		var radius := projected.distance_to(centre)
		if radius < previous - 1e-4:
			breaks += 1
		previous = radius
		last = radius
	print("  [4] %s: remapeo monótono en %d pasos hasta %.1f px (rupturas %d)"
			% [label, MONOTONIC_STEPS, last, breaks])
	expect(breaks == 0, "en %s el remapeo del radio no fue monótono (%d rupturas)"
			% [label, breaks])


## Fórmula equidistante (`docs/12` §3.1): una dirección a 45° de guiñada cae a
## `45 / (hfov/2) · (ancho/2)` píxeles del centro.
func _check_equidistant(label: String, hfov: float) -> void:
	var size := _screen_size()
	var centre := size * 0.5
	var expected := EQUIDISTANT_YAW / (hfov * 0.5) * (size.x * 0.5)
	var theta := deg_to_rad(EQUIDISTANT_YAW)
	var local := Vector3(sin(theta), 0.0, -cos(theta))
	var projected := _camera.project_direction(_camera.global_basis.orthonormalized() * local)
	var radius := INF
	var vertical := INF
	if projected.is_finite():
		radius = projected.distance_to(centre)
		vertical = absf(projected.y - centre.y)
	print("  [5] %s: %.0f° de guiñada → %.3f px del centro, fórmula %.3f px, desvío vertical %.3f px"
			% [label, EQUIDISTANT_YAW, radius, expected, vertical])
	expect(projected.is_finite(),
			"en %s la dirección a %.0f° de guiñada no se proyecta" % [label, EQUIDISTANT_YAW])
	expect_near(radius, expected, EQUIDISTANT_TOLERANCE,
			"en %s el radio de la dirección a %.0f° de guiñada" % [label, EQUIDISTANT_YAW])
	expect(vertical <= EQUIDISTANT_TOLERANCE,
			"en %s la guiñada pura se fue %.3f px en vertical" % [label, vertical])
	expect(projected.x > centre.x,
			"en %s la guiñada positiva no cayó a la derecha del centro" % label)


# --- [6] `edge_clamp` -------------------------------------------------------------------------

## `docs/12` §9.1 fila 3 — `edge_clamp` es idempotente y no mueve un punto interior.
func _check_edge_clamp() -> void:
	var rect := Rect2(Vector2.ZERO, _screen_size())
	var inner := HUDProjection.inner_rect(rect, MARKER_MARGIN)
	var moved := 0
	var drift := 0.0
	var points: Array[Vector2] = [
		inner.position + inner.size * 0.5,
		inner.position + Vector2(10.0, 10.0),
		Vector2(-4000.0, 120.0),
		Vector2(9000.0, -9000.0),
		Vector2(0.0, 20000.0),
		Vector2(NAN, NAN),
	]
	for point: Vector2 in points:
		var once := HUDProjection.edge_clamp(point, rect, MARKER_MARGIN)
		var first: Vector2 = once["pos"]
		var twice := HUDProjection.edge_clamp(first, rect, MARKER_MARGIN)
		var second: Vector2 = twice["pos"]
		if not first.is_finite() or not second.is_finite():
			moved += 1
			continue
		drift = maxf(drift, first.distance_to(second))
		if point.is_finite() and inner.has_point(point) and first.distance_to(point) > 1e-3:
			moved += 1
	print("  [6] edge_clamp: desvío máximo al aplicarlo dos veces %.6f px, puntos interiores movidos %d"
			% [drift, moved])
	expect(drift <= 1e-3, "edge_clamp no es idempotente (desvío %.6f px)" % drift)
	expect(moved == 0, "edge_clamp movió %d puntos que no debía" % moved)


# --- [7] `HUDProjection` con campo forzado ----------------------------------------------------

## `docs/12` §9.1 fila 1, la mitad que no depende de la cámara: la proyección estática
## con `fisheye_hfov` explícito (OFF 0, FAST 160, FULL 180) sobre la misma cámara.
func _check_hud_projection() -> void:
	var fields: Array[float] = [0.0, 160.0, 180.0]
	for hfov: float in fields:
		var mixed := 0
		var wrong := 0
		var samples := 0
		var half_field := deg_to_rad(hfov) * 0.5
		for polar: float in SWEEP_POLARS:
			var theta := deg_to_rad(polar)
			for step: int in SWEEP_AZIMUTHS:
				var azimuth := TAU * float(step) / float(SWEEP_AZIMUTHS)
				var local := Vector3(sin(theta) * cos(azimuth), sin(theta) * sin(azimuth),
						-cos(theta))
				var dir := _camera.global_basis.orthonormalized() * local
				var projected := HUDProjection.project_direction(_camera, dir, hfov)
				samples += 1
				if is_nan(projected.x) != is_nan(projected.y):
					mixed += 1
				if is_inf(projected.x) or is_inf(projected.y):
					mixed += 1
				if hfov > 0.0 and absf(theta - half_field) > FIELD_GUARD:
					var should := theta < half_field
					if should != projected.is_finite():
						wrong += 1
		print("  [7] HUDProjection con hfov %.0f°: %d muestras, %d mezclas NAN/INF, %d fuera de contrato"
				% [hfov, samples, mixed, wrong])
		expect(mixed == 0, "HUDProjection con hfov %.0f° devolvió %d valores mezclados"
				% [hfov, mixed])
		expect(wrong == 0, "HUDProjection con hfov %.0f° falló el contrato en %d muestras"
				% [hfov, wrong])
	var centre := _screen_size() * 0.5
	var forward := -_camera.global_basis.z
	for hfov: float in fields:
		var projected := HUDProjection.project_direction(_camera, forward, hfov)
		expect(projected.is_finite() and projected.distance_to(centre) <= CENTRE_TOLERANCE,
				"HUDProjection con hfov %.0f° no puso el eje óptico en el centro (%s)"
				% [hfov, str(projected)])


# --- [8] El compuesto solo se dibuja con la FPV activa ---------------------------------------

## `docs/03` §5 y `docs/12` §1.1: el compuesto vive en un `CanvasLayer` propio por
## debajo del HUD y solo se dibuja cuando la FPV es la cámara activa. Si el nivel cicla
## a la cámara de seguimiento, se esconde y las sub-viewports dejan de renderizar.
func _check_composite_layer() -> void:
	await _set_mode(Graphics.FisheyeMode.FAST)
	await wait_frames(2)
	var composite := _camera.get_composite()
	if composite == null:
		fail("la cámara no construyó el ColorRect del compuesto")
		return
	var layer := composite.get_parent() as CanvasLayer
	if layer == null:
		fail("el compuesto no cuelga de un CanvasLayer propio")
		return
	var visible_with_fpv := composite.visible
	_level.change_camera()
	await wait_frames(2)
	var other := _level.active_camera()
	var other_name: String = String(other.name) if other != null else "(ninguna)"
	var visible_with_other := composite.visible
	var disabled := true
	for viewport: SubViewport in _camera.get_fisheye_viewports():
		if viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			disabled = false
	while not _camera.is_current():
		_level.change_camera()
		await wait_frames(2)
	var visible_again := composite.visible
	print("  [8] compuesto en la capa %d (HUD en 0): visible con la FPV %s, con '%s' %s, al volver %s; sub-viewports apagadas fuera de la FPV %s"
			% [layer.layer, str(visible_with_fpv), other_name,
			str(visible_with_other), str(visible_again), str(disabled)])
	expect(layer.layer == FPVCamera.COMPOSITE_LAYER and layer.layer < 0,
			"el compuesto está en la capa %d y `docs/12` §1.1 lo pone debajo del HUD"
			% layer.layer)
	expect(visible_with_fpv, "el compuesto no se dibuja con la FPV activa")
	expect(not visible_with_other, "el compuesto siguió dibujándose con otra cámara activa")
	expect(disabled, "las sub-viewports siguieron renderizando con otra cámara activa")
	expect(visible_again, "el compuesto no volvió al ciclar de nuevo a la FPV")


# --- [9] Fugas de nodos -----------------------------------------------------------------------

## Cambiar el modo en caliente reconstruye las sub-viewports sin dejar nodos colgados.
func _check_leaks() -> void:
	await _set_mode(Graphics.FisheyeMode.OFF)
	await wait_frames(3)
	var before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for _cycle: int in LEAK_CYCLES:
		await _set_mode(Graphics.FisheyeMode.FAST)
		await _set_mode(Graphics.FisheyeMode.FULL)
		await _set_mode(Graphics.FisheyeMode.OFF)
	await wait_frames(3)
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("  [9] %d ciclos OFF→FAST→FULL: %d nodos antes, %d después"
			% [LEAK_CYCLES, before, after])
	expect(absi(after - before) <= LEAK_TOLERANCE,
			"ciclar el ojo de pez dejó %d nodos de diferencia (tolerancia %d)"
			% [after - before, LEAK_TOLERANCE])


# --- [10] Draw calls ---------------------------------------------------------------------------

## Coste del ojo de pez, informativo (`docs/03` §12: FULL multiplica por cinco). En
## `--headless` no hay rasterizado y la métrica vale cero: se informa y se sigue.
func _check_draw_calls() -> void:
	if Graphics.is_headless():
		print("  [10] draw calls: SKIP — no hay rasterizado en --headless")
		return
	for mode: int in [Graphics.FisheyeMode.OFF, Graphics.FisheyeMode.FAST,
			Graphics.FisheyeMode.FULL]:
		await _set_mode(mode)
		await wait_frames(SETTLE_FRAMES)
		var peak := 0
		for _frame: int in 10:
			await get_tree().process_frame
			peak = maxi(peak, int(Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_draw_calls[_mode_name(mode)] = peak
	var off := maxi(_draw_calls.get("OFF", 0), 1)
	var fast: int = _draw_calls.get("FAST", 0)
	var full: int = _draw_calls.get("FULL", 0)
	print("  [10] draw calls por frame: OFF %d, FAST %d (+%.1f %%), FULL %d (+%.1f %%)"
			% [off, fast, 100.0 * (float(fast) / float(off) - 1.0), full,
			100.0 * (float(full) / float(off) - 1.0)])


# --- Capturas y utilidades --------------------------------------------------------------------

## Deja el dron quieto mirando a los pilares y saca la captura del modo.
func _shoot(label: String) -> void:
	if shots_dir.is_empty():
		return
	if _drone != null:
		_drone.reset_to(Transform3D(Basis.IDENTITY, SHOT_POSITION))
	await wait_physics(2)
	await wait_frames(SETTLE_FRAMES)
	await shot(label.to_lower())


## Cambia el modo de ojo de pez como lo haría el menú de gráficos: escribe el valor y
## avisa con `fisheye_changed`, sin tocar el `.cfg`.
func _set_mode(mode: int) -> void:
	Graphics.fisheye_mode = int(mode) as Graphics.FisheyeMode
	Graphics.update_fisheye()
	await wait_frames(2)


func _restore_mode() -> void:
	Graphics.fisheye_mode = _original_mode as Graphics.FisheyeMode
	Graphics.update_fisheye()


func _mode_name(mode: int) -> String:
	match mode:
		Graphics.FisheyeMode.FAST:
			return "FAST"
		Graphics.FisheyeMode.FULL:
			return "FULL"
		_:
			return "OFF"


func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _restore_hud_config() -> void:
	if _original_hud_config.is_empty():
		return
	GameSettings.hud_config = _original_hud_config.duplicate(true)
	if _hud != null and is_instance_valid(_hud):
		_hud.set_preview(false)
		_hud.apply_hud_config()


# --- [11] Fila 4: el horizonte del HUD contra la imagen ---------------------------------------

## `docs/12` §9.1 fila 4 — la línea que dibuja [HUDHorizon] en modo `camera` cae sobre
## la transición cielo/suelo de la imagen, con menos de
## [constant HORIZON_TOLERANCE] px de error.
##
## Es el detector del riesgo 3 de `docs/12` §10: la cámara y el HUD tienen que estar
## usando **la misma** proyección. Si el shader del ojo de pez y
## `FPVCamera.project_direction()` se separan, el horizonte dibujado deja de coincidir
## con el que se ve, y esta fila es lo único que lo nota.
##
## Cómo se mide, y por qué así:
## - Se agrega un plano negro de [constant HORIZON_PLANE_SIDE] m y se apaga la niebla
##   volumétrica. El suelo del nivel mide 800 m, y desde 120 m su **borde** —no el
##   horizonte— cae casi un grado más abajo, o sea más que toda la tolerancia. Con un
##   plano casi infinito y sin niebla, la transición de la imagen es el horizonte
##   geométrico y nada más.
## - Se esconde el HUD antes de capturar. Si no, la propia línea de horizonte y el
##   retículo son píxeles blancos justo en la columna que se está midiendo: el check
##   estaría leyendo su propia respuesta.
## - Se mide en la **columna central**, que es la única que está dentro del círculo
##   visible del ojo de pez en los tres modos (las esquinas de FAST y FULL son negras).
func _check_horizon_match() -> void:
	if _hud == null:
		fail("el rig no expone el FlightHUD (get_flight_hud() devolvió null)")
		return
	if Graphics.is_headless():
		print("  [11] SKIP: [docs/12 §9.1 fila 4] coincidencia de HUDHorizon con la imagen"
				+ " — en --headless no hay rasterizado; corre con ventana")
		return

	var environment := _level_environment()
	var fog := environment != null and environment.volumetric_fog_enabled
	if fog:
		environment.volumetric_fog_enabled = false
	var plane := _add_horizon_plane()
	var rig_rotation := _camera_rig.rotation
	var hud_was_visible := _hud.visible

	GameSettings.hud_config["horizon_mode"] = "camera"
	_hud.apply_hud_config()
	_hud.show_component(FlightHUD.Component.HORIZON, true)

	var column := int(roundf(_screen_size().x * 0.5))
	var worst := 0.0
	var measured := 0
	for mode: int in [Graphics.FisheyeMode.OFF, Graphics.FisheyeMode.FAST,
			Graphics.FisheyeMode.FULL]:
		await _set_mode(mode)
		var label := _mode_name(mode)
		for attitude: Vector2 in HORIZON_ATTITUDES:
			_drone.reset_to(Transform3D(Basis.IDENTITY, HORIZON_POSITION))
			_camera_rig.rotation = Vector3(deg_to_rad(attitude.x), 0.0, deg_to_rad(attitude.y))
			await wait_physics(2)
			await wait_frames(SETTLE_FRAMES)
			expect(_hud.horizon_mode() == "camera",
					"en %s el horizonte no quedó en modo 'camera' (quedó '%s')"
							% [label, _hud.horizon_mode()])
			var drawn := _hud.horizon_screen_y(float(column))
			_hud.visible = false
			await wait_frames(2)
			var image := await _capture_image()
			_hud.visible = hud_was_visible
			if image == null:
				fail("en %s no se pudo leer la imagen de la viewport" % label)
				continue
			var seen := _sky_ground_row(image, column)
			var error := INF
			if is_finite(drawn) and is_finite(seen):
				error = absf(drawn - seen)
				worst = maxf(worst, error)
				measured += 1
			print("  [11] %s cabeceo %.0f° alabeo %.0f°: HUD %.2f px, imagen %.2f px, error %.2f px"
					% [label, attitude.x, attitude.y, drawn, seen, error])
			expect(is_finite(drawn),
					"en %s con cabeceo %.0f° el HUD no dibujó horizonte en la columna central"
							% [label, attitude.x])
			expect(is_finite(seen),
					"en %s con cabeceo %.0f° la imagen no tiene transición cielo/suelo en la columna central"
							% [label, attitude.x])
			expect(error <= HORIZON_TOLERANCE,
					"en %s con cabeceo %.0f° y alabeo %.0f° el horizonte del HUD y el de la imagen difieren %.2f px (tolerancia %.1f)"
							% [label, attitude.x, attitude.y, error, HORIZON_TOLERANCE])

	print("  [11] fila 4: %d medidas en 3 modos × %d actitudes, peor error %.2f px (tolerancia %.1f)"
			% [measured, HORIZON_ATTITUDES.size(), worst, HORIZON_TOLERANCE])
	expect(measured == 3 * HORIZON_ATTITUDES.size(),
			"se esperaban %d medidas del horizonte y salieron %d"
					% [3 * HORIZON_ATTITUDES.size(), measured])

	_camera_rig.rotation = rig_rotation
	_hud.visible = hud_was_visible
	if is_instance_valid(plane):
		plane.queue_free()
	if fog and environment != null:
		environment.volumetric_fog_enabled = true


# --- [12] Fila 5: los 12 componentes del HUD --------------------------------------------------

## `docs/12` §9.1 fila 5 — los 12 componentes del `enum Component` existen, obedecen a
## `show_component()` y salen en una captura por modo de ojo de pez.
##
## La mitad numérica corre también en `--headless`: que los doce nodos estén y
## respondan no necesita rasterizado, y es lo que impide que un `.tscn` mal editado
## deje el HUD a medias en silencio. La captura es la que exige ventana.
func _check_hud_components() -> void:
	if _hud == null:
		fail("el rig no expone el FlightHUD (get_flight_hud() devolvió null)")
		return
	var names: Array = FlightHUD.Component.keys()
	expect(names.size() == 12,
			"el enum Component tiene %d entradas y docs/12 §2.4 fija 12" % names.size())

	var missing := PackedStringArray()
	var unresponsive := PackedStringArray()
	for component: int in FlightHUD.Component.values():
		var label := String(names[component])
		if _hud.component_node(component as FlightHUD.Component) == null:
			missing.append(label)
			continue
		_hud.show_component(component as FlightHUD.Component, false)
		var off := _hud.is_component_visible(component as FlightHUD.Component)
		_hud.show_component(component as FlightHUD.Component, true)
		var on := _hud.is_component_visible(component as FlightHUD.Component)
		if off or not on:
			unresponsive.append("%s(off=%s,on=%s)" % [label, str(off), str(on)])
	print("  [12] %d componentes: %d sin nodo, %d que no responden a show_component()"
			% [names.size(), missing.size(), unresponsive.size()])
	expect(missing.is_empty(),
			"faltan los nodos de estos componentes del HUD: %s" % ", ".join(missing))
	expect(unresponsive.is_empty(),
			"estos componentes no obedecen a show_component(): %s" % ", ".join(unresponsive))

	if shots_dir.is_empty() or Graphics.is_headless():
		print("  [12] captura de los 12 componentes: SKIP — %s"
				% ("no se pasó --shots" if shots_dir.is_empty() else "sin rasterizado en --headless"))
		return

	# `preview_mode` da valores que se mueven y, de paso, deja el estado en «armado»:
	# sin eso `HUDStatus` estaría vacío justo en la captura que tiene que mostrarlo.
	_hud.set_preview(true)
	for component: int in FlightHUD.Component.values():
		_hud.show_component(component as FlightHUD.Component, true)
	for mode: int in [Graphics.FisheyeMode.OFF, Graphics.FisheyeMode.FAST,
			Graphics.FisheyeMode.FULL]:
		await _set_mode(mode)
		_drone.reset_to(Transform3D(Basis.IDENTITY, SHOT_POSITION))
		await wait_physics(2)
		await wait_frames(SETTLE_FRAMES * 2)
		await shot("hud_%s" % _mode_name(mode).to_lower())
	print("  [12] capturas hud_off/hud_fast/hud_full con los 12 componentes visibles en %s"
			% shots_dir)


# --- Utilidades de la fila 4 ------------------------------------------------------------------

## El `Environment` del nivel, o `null` si no tiene `WorldEnvironment`.
func _level_environment() -> Environment:
	var world := _level.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	return world.environment if world != null else null


## Plano negro casi infinito bajo el suelo del nivel. Sin sombreado y en negro puro, la
## transición contra el cielo es un escalón y no un degradado.
func _add_horizon_plane() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.BLACK
	material.disable_receive_shadows = true
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(HORIZON_PLANE_SIDE, HORIZON_PLANE_SIDE)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "HorizonProbePlane"
	instance.mesh = mesh
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_level.add_child(instance)
	instance.global_position = Vector3(0.0, HORIZON_PLANE_Y, 0.0)
	return instance


## Imagen de la viewport ya dibujada, o `null` si no hay rasterizado.
func _capture_image() -> Image:
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	return texture.get_image() if texture != null else null


## Fila donde la luminancia de [param column] cruza el punto medio entre el cielo (arriba)
## y el suelo (abajo), interpolada entre píxeles. `NAN` si no hay contraste o no hay cruce.
func _sky_ground_row(image: Image, column: int) -> float:
	var height := image.get_height()
	var x := clampi(column, 0, image.get_width() - 1)
	if height < LUMINANCE_SAMPLE_ROWS * 2 + LUMINANCE_EDGE_MARGIN * 2:
		return NAN
	var sky := 0.0
	var ground := 0.0
	for offset: int in LUMINANCE_SAMPLE_ROWS:
		sky += _luminance(image, x, LUMINANCE_EDGE_MARGIN + offset)
		ground += _luminance(image, x, height - 1 - LUMINANCE_EDGE_MARGIN - offset)
	sky /= float(LUMINANCE_SAMPLE_ROWS)
	ground /= float(LUMINANCE_SAMPLE_ROWS)
	if absf(sky - ground) < LUMINANCE_MIN_CONTRAST:
		return NAN
	var middle := (sky + ground) * 0.5
	var previous := sky
	for y: int in range(LUMINANCE_EDGE_MARGIN, height - LUMINANCE_EDGE_MARGIN):
		var value := _luminance(image, x, y)
		if (previous - middle) * (value - middle) <= 0.0:
			var span := value - previous
			if absf(span) < 1e-6:
				return float(y)
			return float(y - 1) + (middle - previous) / span
		previous = value
	return NAN


func _luminance(image: Image, x: int, y: int) -> float:
	var colour := image.get_pixel(x, y)
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
