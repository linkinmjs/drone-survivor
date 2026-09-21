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
## **WP-24c** agrega los dos detectores del churretón de los costados, más el modo
## `FAST_WIDE`:
## - **Fila 13** ([method _check_coverage], headless): `FPVCamera.coverage()` —el
##   espejo en GDScript del factor `cover` de los shaders— sobre una rejilla que cubre
##   el rectángulo de salida. En FAST_WIDE tiene que dar 1,0 en **todo** el cuadro; en
##   FAST tiene que dar 1,0 exactamente dentro del frustum de la frontal y 0 fuera, sin
##   ningún salto brusco por el camino. Es lo que garantiza que no haya ni texel
##   repetido ni agujero negro donde sí hay imagen.
## - **Fila 14** ([method _check_smear], necesita ventana): FULL es la verdad de
##   terreno —a `hfov` 150 cubre el hemisferio entero con la misma proyección— y se
##   compara la luminancia de FAST y FAST_WIDE contra ella en las bandas laterales.
##   Incluye la **prueba negativa**: un shader con el `clamp` viejo tiene que hacer
##   fallar la medición, o la fila no estaría midiendo nada.
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
##
## **0.02 y no 0.05 (WP-24)**: es una guarda contra medir ruido, no el criterio. El
## criterio es el **gradiente más pronunciado** de la columna, que sigue exigiendo
## `LUMINANCE_MIN_CONTRAST * 0.25`. Con el atardecer de `docs/13` §3.1 el cielo del
## lado **opuesto** al sol —que es justo hacia donde mira esta pose— cae a 0.040
## sobre el plano negro, y con la guarda vieja las quince medidas devolvían `NAN` con
## la transición perfectamente visible en la captura de evidencia. A 0.02 siguen
## quedando cinco niveles de 8 bits entre cielo y suelo, que es de sobra para que el
## vértice de la parábola tenga sentido, y el gradiente medido ahí es 0.039: tres
## veces el piso.
const LUMINANCE_MIN_CONTRAST: float = 0.02

## Columnas donde se mide el horizonte, en fracción del ancho. Las dos de los
## extremos son las que WP-24c agrega: son justo las que el churretón arruinaba.
const HORIZON_COLUMNS: Array[float] = [0.06, 0.15, 0.5, 0.85, 0.94]

## Tolerancia del horizonte en las columnas laterales, en píxeles. Es mayor que la de
## la columna central porque ahí un píxel de pantalla vale más grados: a `hfov` 150 la
## proyección equidistante comprime la periferia y el cruce cielo/suelo se lee peor.
const HORIZON_SIDE_TOLERANCE: float = 8.0

## Cobertura por debajo de la cual una columna se considera viñeteada y no se le mide
## el horizonte.
const COVERED_THRESHOLD: float = 0.5

# --- Fila 13 de WP-24c: cobertura del compuesto -----------------------------------------------

## Rejilla de muestreo de la cobertura sobre el rectángulo de salida.
const COVERAGE_GRID: Vector2i = Vector2i(64, 36)

## Cobertura a partir de la cual se considera «imagen a plena luz».
const COVERAGE_FULL: float = 0.999

## Salto máximo de cobertura entre dos píxeles vecinos de un barrido radial.
##
## La continuidad se mide en **píxeles de pantalla** y no en grados: lo que se ve como
## escalón es un borde de un píxel, y el mismo fundido en grados ocupa el doble de
## píxeles a 1080p que a 540p. Un borde duro de verdad salta 1,0 de un píxel al
## siguiente; el fundido más angosto del diseño ocupa 4 px, o sea 0,375 por píxel en
## su punto más empinado (la pendiente máxima de `smoothstep` es 1,5).
const COVERAGE_MAX_JUMP: float = 0.5

## Ancho mínimo, en píxeles, de cualquier transición entre imagen y negro.
const COVERAGE_MIN_TRANSITION: int = 3

## Relación de aspecto por debajo de la cual FAST_WIDE ya no llega a las esquinas y la
## exigencia de cobertura total se relaja a `θ ≤ COVERAGE_INNER_THETA`.
const COVERAGE_MIN_ASPECT: float = 1.5

# --- Fila 14 de WP-24c: churretón y costura ---------------------------------------------------

## Guiñada del dron para las capturas de la fila 14, en grados: pone un pilar en un
## costado, que es donde el modo FAST viejo repetía el texel del borde.
const SMEAR_YAW: float = 65.0

## Ancho de cada banda lateral que se compara contra FULL, en fracción del ancho.
const SMEAR_BAND: float = 0.18

## Alto de las franjas superior e inferior que se comparan, en fracción del alto.
const SMEAR_STRIP: float = 0.12

## Diferencia media de luminancia admitida contra FULL, en `[0, 1]`.
const SMEAR_TOLERANCE: float = 0.05

## Ídem en la banda central, que es la sanidad de la medición: ahí los tres modos
## muestrean el mismo render y tienen que coincidir mucho mejor.
const SMEAR_CENTRE_TOLERANCE: float = 0.02

## Diferencia de luminancia a partir de la cual **un píxel** está visiblemente mal.
##
## La media sobre una banda entera es demasiado roma para este trabajo: medido, el
## `clamp` de antes de WP-24c se separaba sólo 0,009 de FULL en promedio sobre la zona
## de viñeta, porque ahí la mayor parte del cuadro es cielo y suelo liso y el texel
## repetido acierta. El churretón se ve en los pocos por ciento de píxeles donde hay un
## edificio, y ahí se equivoca por mucho. Por eso el criterio que decide es qué
## **fracción** del área supera este umbral, no el promedio.
const SMEAR_PIXEL_DELTA: float = 0.1

## Fracción máxima del área que puede superar [constant SMEAR_PIXEL_DELTA].
const SMEAR_BAD_FRACTION: float = 0.02

## Ancho de la banda central de sanidad, en fracción del ancho.
const SMEAR_CENTRE_BAND: float = 0.30

## Luminancia por debajo de la cual un píxel del compuesto se considera negro.
const BLACK_LEVEL: float = 0.02

## Fracción de píxeles en la que pueden discrepar el negro de la captura y la
## `coverage()` de la cámara.
const BLACK_MISMATCH: float = 0.01

## Paso de muestreo de los mapas de cobertura por píxel. `coverage()` es una función
## de GDScript: recorrer dos millones de píxeles costaría más que todo el resto del
## check, y un criterio del 1 % no necesita esa resolución.
const COVERAGE_STRIDE: int = 4

## Paso de muestreo de las comparaciones de luminancia. `Image.get_pixel()` es una
## llamada de GDScript por píxel; de a dos alcanza para una media sobre decenas de
## miles de muestras y el check no se va a los segundos.
const SMEAR_STRIDE: int = 2

## Columnas a cada lado de la costura que se promedian.
const SEAM_COLUMNS: int = 8

## Salto de luminancia media admitido al cruzar la costura, en `[0, 1]`.
const SEAM_TOLERANCE: float = 0.06

## Cuadros de reposo antes de capturar para la fila 14. Son más que
## [constant SETTLE_FRAMES] porque acá se comparan **dos renders distintos** del mismo
## mundo y cualquier acumulación temporal a medio converger se leería como churretón.
const SMEAR_SETTLE_FRAMES: int = 24

## Shader con el `clamp` de antes de WP-24c, para la prueba negativa de la fila 14.
## Es el `fisheye_fast.gdshader` que tenía el proyecto, recortado a lo mínimo.
const LEGACY_SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D front_texture : filter_linear, repeat_disable;
uniform float hfov = 150.0;
uniform float render_fov = 120.0;
uniform float aspect = 1.7777778;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 q = vec2(p.x, p.y / aspect);
	float r = length(q);
	float theta = r * radians(hfov) * 0.5;
	vec3 rgb = vec3(0.0);
	if (theta < radians(89.0)) {
		float source_radius = tan(theta) / tan(radians(render_fov) * 0.5);
		vec2 direction = r > 1e-6 ? q / r : vec2(0.0);
		vec2 source_q = direction * source_radius;
		vec2 source_uv = vec2(source_q.x, source_q.y * aspect) * 0.5 + vec2(0.5);
		rgb = texture(front_texture, clamp(source_uv, vec2(0.0), vec2(1.0))).rgb;
	}
	COLOR = vec4(rgb, 1.0);
}
"""

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
	await _check_coverage()
	await _check_smear()
	_restore_mode()
	_restore_hud_config()


## Los cuatro modos, en orden de costo creciente. Es la lista que recorren casi todas
## las filas: tenerla en un solo lugar es lo que impide que agregar un modo lo deje
## fuera de la mitad de los criterios.
func _all_modes() -> Array[int]:
	return [Graphics.FisheyeMode.OFF, Graphics.FisheyeMode.FAST,
			Graphics.FisheyeMode.FAST_WIDE, Graphics.FisheyeMode.FULL]


## Sólo los modos con compuesto.
func _fisheye_modes() -> Array[int]:
	return [Graphics.FisheyeMode.FAST, Graphics.FisheyeMode.FAST_WIDE,
			Graphics.FisheyeMode.FULL]


## Sub-viewports que tiene que construir cada modo (`docs/03` §5).
func _expected_viewports(mode: int) -> int:
	match mode:
		Graphics.FisheyeMode.FAST:
			return 1
		Graphics.FisheyeMode.FAST_WIDE:
			return 3
		Graphics.FisheyeMode.FULL:
			return 5
		_:
			return 0


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

## Recorre OFF, FAST, FAST_WIDE y FULL: centro, barrido, marcadores, monotonía,
## fórmula equidistante y captura.
func _check_modes() -> void:
	for mode: int in _all_modes():
		await _set_mode(mode)
		var label := _mode_name(mode)
		var hfov := _camera.get_fisheye_hfov()
		var viewports := _camera.get_fisheye_viewports().size()
		print("  --- modo %s: hfov %.1f°, fov de render %.1f°, %d sub-viewport(s) ---"
				% [label, hfov, _camera.fov, viewports])
		expect(_camera.get_fisheye_mode() == mode,
				"la cámara quedó en el modo %d y se pidió %d"
				% [_camera.get_fisheye_mode(), mode])
		var expected_viewports := _expected_viewports(mode)
		expect(viewports == expected_viewports,
				"el modo %s construyó %d sub-viewports y esperaba %d"
				% [label, viewports, expected_viewports])
		_check_face_fovs(label, mode)
		_check_centre(label)
		_check_sweep(label, mode, hfov)
		_check_markers(label)
		if mode != Graphics.FisheyeMode.OFF:
			_check_monotonic(label, hfov)
			_check_equidistant(label, hfov)
		await _shoot(label)


## Cada sub-cámara conserva el `fov` que el compuesto da por supuesto, y ninguna lleva
## `attributes` propios.
##
## El shader proyecta con `FAST_RENDER_FOV`, `SIDE_FACE_FOV` y `FULL_FACE_FOV`
## cableados: si una sub-cámara renderiza con otro campo, la imagen no da error, sale
## mal proyectada, que es mucho peor. Y hay una forma concreta y tentadora de romperlo:
## asignarle a la sub-cámara el `CameraAttributesPhysical` del nivel para "heredar la
## exposición". Ese recurso lleva `frustum_focal_length` y **sobrescribe el `fov`** —
## medido en WP-24c: 120° y 100° pasaban a 160,15°—, y además no hace falta, porque la
## exposición del `WorldEnvironment` se hereda igual.
func _check_face_fovs(label: String, mode: int) -> void:
	var cameras: Array[Camera3D] = []
	for viewport: SubViewport in _camera.get_fisheye_viewports():
		var camera := viewport.get_node_or_null(^"FaceCamera") as Camera3D
		if camera != null:
			cameras.append(camera)
	var wrong := PackedStringArray()
	for index: int in cameras.size():
		var camera := cameras[index]
		var wanted := FPVCamera.FULL_FACE_FOV
		if mode != Graphics.FisheyeMode.FULL:
			wanted = FPVCamera.FAST_RENDER_FOV if index == 0 else FPVCamera.SIDE_FACE_FOV
		if not is_equal_approx(camera.fov, wanted):
			wrong.append("cara %d: %.2f° en vez de %.2f°" % [index, camera.fov, wanted])
		if camera.attributes != null:
			wrong.append("cara %d lleva attributes propios, que le pisan el fov" % index)
	print("  [1] %s: %d sub-cámaras con el fov del compuesto, 0 con attributes propios%s"
			% [label, cameras.size(),
			"" if wrong.is_empty() else " — ERRORES: " + ", ".join(wrong)])
	expect(cameras.size() == _expected_viewports(mode),
			"en %s se encontraron %d sub-cámaras y se esperaban %d"
			% [label, cameras.size(), _expected_viewports(mode)])
	expect(wrong.is_empty(), "en %s: %s" % [label, ", ".join(wrong)])


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
	# El barrido llega hasta el borde del campo pero no lo pisa: ahí `theta` y
	# `hfov/2` difieren en un flotante y si el redondeo cae para el lado equivocado
	# `project_direction` devuelve NAN con todo derecho. Es el mismo margen que usa
	# el barrido de la fila 2.
	var limit := maxf(half_field - FIELD_GUARD, 0.0)
	for step: int in MONOTONIC_STEPS + 1:
		var theta := limit * float(step) / float(MONOTONIC_STEPS)
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
##
## WP-24a agrega la invariante del 3D de la raíz: mientras el compuesto se ve, la
## viewport raíz **no** dibuja 3D (`disable_3d == composite.visible`), porque la
## escena la dibujan las sub-viewports y la raíz sólo compone. Al ciclar a la
## cámara de intro o a la fija, que sí dibujan por la raíz, tiene que volver a
## `false` en el mismo cuadro o la pantalla se queda en negro.
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
	var root_viewport := get_viewport()
	var visible_with_fpv := composite.visible
	var disable_3d_with_fpv := root_viewport.disable_3d
	_level.change_camera()
	await wait_frames(2)
	var other := _level.active_camera()
	var other_name: String = String(other.name) if other != null else "(ninguna)"
	var visible_with_other := composite.visible
	var disable_3d_with_other := root_viewport.disable_3d
	var disabled := true
	for viewport: SubViewport in _camera.get_fisheye_viewports():
		if viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			disabled = false
	while not _camera.is_current():
		_level.change_camera()
		await wait_frames(2)
	var visible_again := composite.visible
	var disable_3d_again := root_viewport.disable_3d
	print("  [8] compuesto en la capa %d (HUD en 0): visible con la FPV %s, con '%s' %s, al volver %s; sub-viewports apagadas fuera de la FPV %s"
			% [layer.layer, str(visible_with_fpv), other_name,
			str(visible_with_other), str(visible_again), str(disabled)])
	print("  [8] 3D de la viewport raíz apagado: con la FPV %s, con '%s' %s, al volver %s"
			% [str(disable_3d_with_fpv), other_name, str(disable_3d_with_other),
			str(disable_3d_again)])
	expect(layer.layer == FPVCamera.COMPOSITE_LAYER and layer.layer < 0,
			"el compuesto está en la capa %d y `docs/12` §1.1 lo pone debajo del HUD"
			% layer.layer)
	expect(visible_with_fpv, "el compuesto no se dibuja con la FPV activa")
	expect(not visible_with_other, "el compuesto siguió dibujándose con otra cámara activa")
	expect(disabled, "las sub-viewports siguieron renderizando con otra cámara activa")
	expect(visible_again, "el compuesto no volvió al ciclar de nuevo a la FPV")
	expect(disable_3d_with_fpv == visible_with_fpv,
			"con la FPV activa, disable_3d de la raíz (%s) no sigue a composite.visible (%s)"
			% [str(disable_3d_with_fpv), str(visible_with_fpv)])
	expect(disable_3d_with_other == visible_with_other,
			"con '%s' activa, disable_3d de la raíz (%s) no sigue a composite.visible (%s)"
			% [other_name, str(disable_3d_with_other), str(visible_with_other)])
	expect(disable_3d_again == visible_again,
			"al volver a la FPV, disable_3d de la raíz (%s) no sigue a composite.visible (%s)"
			% [str(disable_3d_again), str(visible_again)])


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
	for mode: int in _all_modes():
		await _set_mode(mode)
		await wait_frames(SETTLE_FRAMES)
		var peak := 0
		for _frame: int in 10:
			await get_tree().process_frame
			peak = maxi(peak, int(Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_draw_calls[_mode_name(mode)] = peak
	var off := maxi(_draw_calls.get("OFF", 0), 1)
	var line := PackedStringArray()
	for mode: int in _all_modes():
		var label := _mode_name(mode)
		var calls: int = _draw_calls.get(label, 0)
		line.append("%s %d (%+.1f %%)"
				% [label, calls, 100.0 * (float(calls) / float(off) - 1.0)])
	print("  [10] draw calls por frame: %s" % ", ".join(line))


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
		Graphics.FisheyeMode.FAST_WIDE:
			return "FAST_WIDE"
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
## - Se esconde también el `ColorRect` del overlay FPV (`docs/13` §7), por la misma
##   razón. Su viñeta atenúa el gradiente cielo/suelo justo en la periferia, y el
##   detector toma el máximo de la columna: con el overlay puesto, la columna de
##   0.94·w en FULL con 25° de cabeceo y 12° de alabeo daba **5.82, 6.00 y 253 px**
##   en tres corridas donde sin overlay daba 1.92. Lo que se mide es dónde está el
##   horizonte, no cuánto lo tapa el efecto de señal.
## - Se mide en cinco columnas ([constant HORIZON_COLUMNS]) y no sólo en la central.
##   Medir el centro nada más era la razón por la que el churretón de los costados
##   pasaba desapercibido: ahí el compuesto siempre coincidió. En las columnas de los
##   extremos la tolerancia sube a [constant HORIZON_SIDE_TOLERANCE] px porque la
##   proyección equidistante comprime la periferia y un píxel vale más grados.
## - Una columna que caiga en la viñeta —FAST a 0,06 y 0,94 del ancho, que ahora es
##   negro honesto— no se mide: se informa el SKIP y se sigue. La decisión no es a
##   dedo, sale de `FPVCamera.coverage()` sobre la dirección de ese mismo píxel.
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
	# Se esconde **toda** la geometría del nivel y se deja sólo el plano de 40 km: los
	# pilares tapan el horizonte en las columnas de los costados —el pilar F queda a
	# 57° a la izquierda desde esta pose—, el dron mueve las hélices entre capturas y
	# las pilas tienen un emisivo cuyo halo se come varias columnas. Con el cielo y el
	# plano solos, lo que cruza la columna **es** el horizonte geométrico.
	#
	# El orden importa: se recoge **antes** de agregar el plano, o el plano entraría en
	# la lista y se escondería a sí mismo.
	var hidden := _collect_visuals(_level)
	for instance: VisualInstance3D in hidden:
		instance.visible = false
	var plane := _add_horizon_plane()
	var rig_rotation := _camera_rig.rotation
	var hud_was_visible := _hud.visible
	var overlay_rect := _overlay_rect()
	var overlay_was_visible := overlay_rect != null and overlay_rect.visible

	GameSettings.hud_config["horizon_mode"] = "camera"
	_hud.apply_hud_config()
	_hud.show_component(FlightHUD.Component.HORIZON, true)

	var width := _screen_size().x
	var worst := 0.0
	var measured := 0
	var skipped := 0
	for mode: int in _all_modes():
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
			var drawn: Array[float] = []
			var covered: Array[bool] = []
			for fraction: float in HORIZON_COLUMNS:
				var column := float(int(roundf(width * fraction)))
				var y := _hud.horizon_screen_y(column)
				drawn.append(y)
				covered.append(_column_is_measurable(column, y))
			_hud.visible = false
			_set_overlay_visible(false)
			await wait_frames(2)
			var image := await _capture_image()
			_hud.visible = hud_was_visible
			_set_overlay_visible(overlay_was_visible)
			if image == null:
				fail("en %s no se pudo leer la imagen de la viewport" % label)
				continue
			# La imagen **con la que se mide**, sin HUD y con el plano de medición: es
			# la evidencia de la fila 4 y lo primero que hay que mirar si el criterio
			# empieza a fallar por un cambio de iluminación y no de proyección.
			_save_image(image, "horizonte_%s_%.0f" % [label.to_lower(), attitude.x])
			for index: int in HORIZON_COLUMNS.size():
				var fraction := HORIZON_COLUMNS[index]
				var column := int(roundf(width * fraction))
				var tolerance := HORIZON_TOLERANCE if is_equal_approx(fraction, 0.5) \
						else HORIZON_SIDE_TOLERANCE
				if not covered[index]:
					skipped += 1
					print("  [11] %s cabeceo %.0f° x %.2f·w: SKIP — la columna cae en la"
							% [label, attitude.x, fraction]
							+ " viñeta, ahí no hay imagen que medir")
					continue
				var seen := _sky_ground_row(image, column)
				var error := INF
				if is_finite(drawn[index]) and is_finite(seen):
					error = absf(drawn[index] - seen)
					worst = maxf(worst, error)
					measured += 1
				print("  [11] %s cabeceo %.0f° alabeo %.0f° x %.2f·w: HUD %.2f px, imagen %.2f px, error %.2f px"
						% [label, attitude.x, attitude.y, fraction, drawn[index], seen, error])
				expect(is_finite(drawn[index]),
						"en %s con cabeceo %.0f° el HUD no dibujó horizonte en x = %.2f·w"
								% [label, attitude.x, fraction])
				expect(is_finite(seen),
						"en %s con cabeceo %.0f° la imagen no tiene transición cielo/suelo en x = %.2f·w"
								% [label, attitude.x, fraction])
				expect(error <= tolerance,
						"en %s con cabeceo %.0f°, alabeo %.0f° y x = %.2f·w el horizonte del HUD y el de la imagen difieren %.2f px (tolerancia %.1f)"
								% [label, attitude.x, attitude.y, fraction, error, tolerance])

	var total := _all_modes().size() * HORIZON_ATTITUDES.size() * HORIZON_COLUMNS.size()
	print("  [11] fila 4: %d medidas + %d columnas viñeteadas de %d posibles (%d modos × %d actitudes × %d columnas), peor error %.2f px"
			% [measured, skipped, total, _all_modes().size(), HORIZON_ATTITUDES.size(),
			HORIZON_COLUMNS.size(), worst])
	expect(measured + skipped == total,
			"se esperaban %d medidas del horizonte y salieron %d medidas y %d SKIP"
					% [total, measured, skipped])
	# La columna central tiene que medirse siempre, en los cuatro modos: si se
	# viñeteara, el compuesto estaría roto de raíz.
	expect(measured >= _all_modes().size() * HORIZON_ATTITUDES.size(),
			"al menos la columna central tiene que medirse en los %d modos (sólo %d medidas)"
					% [_all_modes().size(), measured])

	_camera_rig.rotation = rig_rotation
	_hud.visible = hud_was_visible
	_set_overlay_visible(overlay_was_visible)
	for instance: VisualInstance3D in hidden:
		if is_instance_valid(instance):
			instance.visible = true
	if is_instance_valid(plane):
		plane.queue_free()
	if fog and environment != null:
		environment.volumetric_fog_enabled = true


## Si la columna [param column] se le puede medir el horizonte.
##
## [method _sky_ground_row] no mira sólo la fila del horizonte: promedia las diez
## primeras y las diez últimas filas de la columna para saber qué luminancia tiene el
## cielo y cuál el suelo. Si el compuesto viñetea **cualquiera** de esos tres lugares
## —en FAST a `hfov` 150 las esquinas son negras hasta bien adentro— no hay contraste
## que medir y la función devolvería `NAN`. Por eso se consultan los tres.
func _column_is_measurable(column: float, horizon_y: float) -> bool:
	if not is_finite(column) or not is_finite(horizon_y):
		return false
	var height := _screen_size().y
	var probes: Array[float] = [
		float(LUMINANCE_EDGE_MARGIN + LUMINANCE_SAMPLE_ROWS),
		height - 1.0 - float(LUMINANCE_EDGE_MARGIN + LUMINANCE_SAMPLE_ROWS),
		horizon_y,
	]
	for y: float in probes:
		var direction := _direction_at(Vector2(column, y))
		if direction == Vector3.ZERO:
			return false
		if _camera.coverage(direction) < COVERED_THRESHOLD:
			return false
	return true


## Dirección de mundo que el compuesto dibuja en el píxel [param point], o
## `Vector3.ZERO` si ese píxel cae fuera de toda proyección posible (`θ ≥ 180°`).
##
## Es la inversa de `FPVCamera.project_direction()`, escrita **acá** y no en la cámara
## a propósito: si las dos fórmulas salieran del mismo código, el check no estaría
## comprobando nada.
func _direction_at(point: Vector2) -> Vector3:
	var size := _screen_size()
	var half := size * 0.5
	var p := Vector2((point.x - half.x) / half.x, (point.y - half.y) / half.y)
	var aspect := size.x / maxf(size.y, 1.0)
	var q := Vector2(p.x, p.y / aspect)
	var radius := q.length()
	var theta := radius * deg_to_rad(_camera.get_fisheye_hfov()) * 0.5
	if theta >= PI:
		return Vector3.ZERO
	var unit := q / radius if radius > 1e-6 else Vector2.ZERO
	var local := Vector3(sin(theta) * unit.x, -sin(theta) * unit.y, -cos(theta))
	return _camera.global_basis.orthonormalized() * local


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
	for mode: int in _all_modes():
		await _set_mode(mode)
		_drone.reset_to(Transform3D(Basis.IDENTITY, SHOT_POSITION))
		await wait_physics(2)
		await wait_frames(SETTLE_FRAMES * 2)
		await shot("hud_%s" % _mode_name(mode).to_lower())
	print("  [12] capturas hud_* de los %d modos con los 12 componentes visibles en %s"
			% [_all_modes().size(), shots_dir])


# --- [14] Churretón y costura (WP-24c) --------------------------------------------------------

## FAST y FAST_WIDE contra FULL, que es la verdad de terreno.
##
## A `hfov` 150 las cinco caras de FULL cubren el hemisferio entero con **la misma**
## proyección equidistante que los otros dos modos: la imagen que tiene que salir es
## exactamente la misma, y cualquier diferencia sistemática en las bandas laterales es
## un defecto del compuesto. Esa es toda la idea de la fila.
##
## Qué se mide, desde [constant SHOT_POSITION] con [constant SMEAR_YAW] de guiñada
## —que pone un pilar del nivel en un costado—:
## - **FAST_WIDE contra FULL** en las dos bandas laterales y en las franjas superior e
##   inferior: diferencia media de luminancia < [constant SMEAR_TOLERANCE].
## - **FAST contra FULL** sólo sobre los píxeles que FAST **no** dejó en negro, con el
##   mismo límite, y además el negro de FAST tiene que coincidir con
##   `coverage() == 0` en más del `100 − BLACK_MISMATCH` % de los píxeles.
## - **Banda central** < [constant SMEAR_CENTRE_TOLERANCE]: es la sanidad de la
##   medición. Si el centro tampoco coincide, lo que está mal es el banco, no el modo.
## - **Costura de FAST_WIDE**: al cruzar el relevo entre la frontal y la lateral, la
##   luminancia media de ocho columnas no salta más de [constant SEAM_TOLERANCE].
## - **Prueba negativa**: se vuelve a poner el `clamp` de antes de WP-24c sobre el
##   mismo render y la comparación contra FULL **tiene que fallar**. Sin eso, un
##   criterio que pasa no distingue «no hay churretón» de «no estoy mirando».
##
## Se apagan la niebla volumétrica, SSAO, SDFGI, SSIL y glow, y se esconde el modelo
## del dron. No es para que el criterio sea más fácil: SSAO y SDFGI son efectos de
## espacio de pantalla y acumulación temporal, y **por definición** dan distinto en
## una viewport de 1920×1080 que en cinco de 1080², así que medirlos sería medir el
## ruido en vez del churretón. El modelo del dron se esconde porque las hélices se
## mueven entre capturas.
func _check_smear() -> void:
	if Graphics.is_headless():
		print("  [14] SKIP: [WP-24c] churretón y costura de los costados"
				+ " — en --headless no hay rasterizado; corre con ventana")
		return
	var restore := _begin_smear_scene()
	var images: Dictionary[String, Image] = {}
	var fast_cover: Dictionary[Vector2i, float] = {}
	var poses: Array[Transform3D] = []
	for mode: int in _fisheye_modes():
		await _set_mode(mode)
		_park_drone()
		await wait_frames(SMEAR_SETTLE_FRAMES)
		var image := await _capture_image()
		if image == null:
			fail("en %s no se pudo leer la imagen para la fila 14" % _mode_name(mode))
			continue
		images[_mode_name(mode)] = image
		poses.append(_camera.global_transform)
		# Se guarda **la imagen medida**, no una captura nueva: así el PNG que se
		# mira a ojo y el número de la fila 14 son literalmente el mismo cuadro.
		_save_image(image, "smear_%s" % _mode_name(mode).to_lower())
		# La máscara se toma **con el modo puesto**: `coverage()` responde por el modo
		# activo, y tomarla después, ya en FULL, daría 1,0 en todas partes.
		if mode == Graphics.FisheyeMode.FAST:
			fast_cover = _coverage_mask(Vector2i(image.get_width(), image.get_height()))
	_check_same_pose(poses)
	if images.size() == _fisheye_modes().size():
		_compare_against_full(images, fast_cover)
		_check_seam(images["FAST_WIDE"], "efectos apagados")
		await _check_legacy_clamp(images["FULL"], fast_cover)
		await _check_wide_at_max_fov()
		await _check_seam_with_effects(restore)
	_end_smear_scene(restore)


## FAST_WIDE en el extremo del rango de `QuadSettings.fov`.
##
## A 170° el borde horizontal pide 85° y la esquina 97,5°, más de lo que cubren la
## frontal y las dos laterales juntas: ahí **sí** tiene que aparecer viñeta, y poca.
## Es la contracara de la fila 13: no sólo que no haya negro donde tiene que haber
## imagen, sino que lo haya donde de verdad no la hay.
func _check_wide_at_max_fov() -> void:
	await _set_mode(Graphics.FisheyeMode.FAST_WIDE)
	var before := _camera.get_fisheye_hfov()
	_camera.set_horizontal_fov(FPVCamera.FISHEYE_FOV_RANGE.y)
	_park_drone()
	await wait_frames(SMEAR_SETTLE_FRAMES)
	var image := await _capture_image()
	var size := _screen_size()
	var mask := _coverage_mask(Vector2i(int(size.x), int(size.y)))
	var dark := 0
	for point: Vector2i in mask:
		if mask[point] <= 1e-6:
			dark += 1
	var ratio := float(dark) / maxf(float(mask.size()), 1.0)
	print("  [14] FAST_WIDE a hfov %.0f°: viñeta en el %.2f %% del cuadro (a %.0f° era 0 %%)"
			% [_camera.get_fisheye_hfov(), 100.0 * ratio, before])
	expect(ratio > 0.0 and ratio < 0.1,
			"a hfov %.0f° FAST_WIDE tiene que viñetear un poco y viñetea el %.2f %%"
			% [_camera.get_fisheye_hfov(), 100.0 * ratio])
	if image != null:
		_save_image(image, "wide_hfov_%.0f" % _camera.get_fisheye_hfov())
	else:
		fail("no se pudo capturar FAST_WIDE a hfov máximo")
	_camera.set_horizontal_fov(before)


## La costura de FAST_WIDE **con el `Environment` del nivel puesto**.
##
## Las caras laterales corren con SDFGI, SSIL, SSAO y niebla volumétrica apagados
## ([method FPVCamera._refresh_side_environment]): es lo que las hace baratas, y lo
## que podría dejar un escalón de brillo donde la frontal cede el relevo. Las demás
## medidas de la fila 14 apagan esos efectos para poder comparar modos entre sí, así
## que son ciegas justamente a esto. Esta medida los vuelve a encender y mira el mismo
## salto de luminancia: es el único criterio que vigila el precio de esa optimización.
func _check_seam_with_effects(restore: Dictionary) -> void:
	var environment: Environment = restore["environment"]
	if environment == null:
		print("  [14] costura con efectos: SKIP — el nivel no tiene WorldEnvironment")
		return
	environment.volumetric_fog_enabled = bool(restore["fog"])
	environment.ssao_enabled = bool(restore["ssao"])
	environment.sdfgi_enabled = bool(restore["sdfgi"])
	environment.ssil_enabled = bool(restore["ssil"])
	environment.glow_enabled = bool(restore["glow"])
	# Sin esto, una medida que dé cero no se distingue de una medida que no midió
	# nada porque el nivel tenía los efectos apagados de entrada.
	print("  [14] costura con efectos: SDFGI %s, SSAO %s, niebla volumétrica %s, SSIL %s, glow %s"
			% [str(environment.sdfgi_enabled), str(environment.ssao_enabled),
			str(environment.volumetric_fog_enabled), str(environment.ssil_enabled),
			str(environment.glow_enabled)])
	expect(environment.sdfgi_enabled or environment.ssao_enabled
			or environment.volumetric_fog_enabled,
			"la medida de costura con efectos no tiene ningún efecto encendido que medir:"
			+ " el preset del check dejó el Environment pelado")
	await _set_mode(Graphics.FisheyeMode.FAST_WIDE)
	_park_drone()
	# SDFGI acumula entre cuadros: con la ventana corta de las otras medidas, el
	# escalón que se leería sería el de las cascadas a medio converger.
	await wait_frames(SMEAR_SETTLE_FRAMES * 3)
	var image := await _capture_image()
	if image == null:
		fail("no se pudo capturar FAST_WIDE con los efectos del nivel encendidos")
		return
	_check_seam(image, "SDFGI, SSAO y niebla encendidos")


## Vuelve a poner el dron exactamente en la pose de medición, antes de cada captura.
##
## El dron es un [RigidBody3D] desarmado: entre una captura y la siguiente se cae. Con
## medio metro de caída el paralaje contra un pilar cercano mueve decenas de píxeles, y
## eso se lee igual que un churretón. Se congela **y** se reubica: congelar solo no
## alcanzaría si algo lo empujó antes.
func _park_drone() -> void:
	_drone.freeze = true
	_drone.reset_to(Transform3D(Basis(Vector3.UP, deg_to_rad(SMEAR_YAW)), SHOT_POSITION))
	_camera_rig.rotation = Vector3(deg_to_rad(QuadSettings.angle), 0.0, 0.0)
	_camera_rig.force_update_transform()
	_camera.force_update_transform()


## Las tres capturas salieron desde exactamente la misma pose.
##
## Es la validación del banco, no del ojo de pez: si la cámara se movió entre capturas,
## todo lo que mide la fila 14 es paralaje y no significa nada. Vale la pena que falle
## ruidosamente en vez de dar un número que nadie puede interpretar.
func _check_same_pose(poses: Array[Transform3D]) -> void:
	if poses.size() < 2:
		return
	var drift := 0.0
	for index: int in range(1, poses.size()):
		drift = maxf(drift, poses[index].origin.distance_to(poses[0].origin))
		drift = maxf(drift, (poses[index].basis.z - poses[0].basis.z).length())
	print("  [14] las %d capturas salieron de la misma pose: desvío máximo %.6f"
			% [poses.size(), drift])
	expect(drift <= 1e-3,
			"la cámara se movió %.4f entre las capturas de la fila 14: lo que se mide es"
			% drift + " paralaje, no el compuesto")


## Deja la escena en condiciones de medir y devuelve lo que hay que restaurar.
func _begin_smear_scene() -> Dictionary:
	var environment := _level_environment()
	var overlay_rect := _overlay_rect()
	var restore: Dictionary = {
		"rig_rotation": _camera_rig.rotation,
		"hud_visible": _hud.visible if _hud != null else true,
		"overlay_visible": overlay_rect != null and overlay_rect.visible,
		"environment": environment,
		"visuals": _collect_visuals(_drone),
		"frozen": _drone.freeze,
	}
	if environment != null:
		restore["fog"] = environment.volumetric_fog_enabled
		restore["ssao"] = environment.ssao_enabled
		restore["sdfgi"] = environment.sdfgi_enabled
		restore["ssil"] = environment.ssil_enabled
		restore["glow"] = environment.glow_enabled
		environment.volumetric_fog_enabled = false
		environment.ssao_enabled = false
		environment.sdfgi_enabled = false
		environment.ssil_enabled = false
		environment.glow_enabled = false
	for instance: VisualInstance3D in restore["visuals"]:
		instance.visible = false
	if _hud != null:
		_hud.visible = false
	# La viñeta del overlay oscurece la periferia justo donde se mide la costura: con
	# ella puesta, el churretón y el desvanecido del borde son el mismo píxel.
	_set_overlay_visible(false)
	_park_drone()
	return restore


func _end_smear_scene(restore: Dictionary) -> void:
	var environment: Environment = restore["environment"]
	if environment != null:
		environment.volumetric_fog_enabled = bool(restore["fog"])
		environment.ssao_enabled = bool(restore["ssao"])
		environment.sdfgi_enabled = bool(restore["sdfgi"])
		environment.ssil_enabled = bool(restore["ssil"])
		environment.glow_enabled = bool(restore["glow"])
	for instance: VisualInstance3D in restore["visuals"]:
		if is_instance_valid(instance):
			instance.visible = true
	if _hud != null:
		_hud.visible = bool(restore["hud_visible"])
	_set_overlay_visible(bool(restore["overlay_visible"]))
	_camera_rig.rotation = restore["rig_rotation"]
	_drone.freeze = bool(restore["frozen"])


## El `ColorRect` del overlay de señal FPV del rig, o `null` si no hay overlay
## (`docs/13` §7).
func _overlay_rect() -> ColorRect:
	if _rig == null:
		return null
	var overlay := _rig.get_overlay()
	return overlay.rect() if overlay != null else null


## Esconde o muestra el overlay de señal. Se usa junto con el del HUD en las dos filas
## que **miden la imagen**: la viñeta es parte de la respuesta, no del enunciado.
func _set_overlay_visible(value: bool) -> void:
	var rect := _overlay_rect()
	if rect != null:
		rect.visible = value


## Las mallas visibles que cuelgan de [param root]. Devuelve vacío si es `null`, así
## que un nivel sin `Pillars` no rompe nada.
func _collect_visuals(root: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if root == null:
		return found
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		var instance := node as VisualInstance3D
		if instance != null and instance.visible:
			found.append(instance)
		for child: Node in node.get_children():
			pending.append(child)
	return found


## Las dos comparaciones contra FULL, banda por banda.
func _compare_against_full(images: Dictionary[String, Image],
		fast_cover: Dictionary[Vector2i, float]) -> void:
	var truth: Image = images["FULL"]
	var size := Vector2i(truth.get_width(), truth.get_height())
	var regions := _smear_regions(size)
	for label: String in ["FAST", "FAST_WIDE"]:
		var image: Image = images[label]
		# En FAST se compara **sólo donde FAST dice tener imagen a plena luz**. Los
		# píxeles de la viñeta y los del fundido no se comparan: ahí FAST no pretende
		# mostrar el mundo, y exigirle que coincida con FULL sería exigirle justo lo
		# que WP-24c decidió no hacer.
		var mask: Dictionary[Vector2i, float] = {}
		if label == "FAST":
			mask = fast_cover
		for region_name: String in regions:
			var region: Rect2i = regions[region_name]
			var tolerance := SMEAR_CENTRE_TOLERANCE if region_name == "centro" \
					else SMEAR_TOLERANCE
			var result := _mean_abs_difference(image, truth, region, mask, true)
			var mean := float(result["mean"])
			var bad := float(result["bad"])
			print("  [14] %s contra FULL en %-10s: |Δluminancia| media %.4f, %.2f %% de píxeles con más de %.2f, peor %.3f, sobre %d muestras"
					% [label, region_name, mean, 100.0 * bad, SMEAR_PIXEL_DELTA,
					float(result["worst"]), int(result["samples"])])
			expect(int(result["samples"]) > 0,
					"en %s la región '%s' no dejó ninguna muestra que comparar"
					% [label, region_name])
			expect(mean <= tolerance,
					"en %s la región '%s' difiere de FULL en %.4f de luminancia media (tolerancia %.2f): eso es el churretón"
					% [label, region_name, mean, tolerance])
			expect(bad <= SMEAR_BAD_FRACTION,
					"en %s el %.2f %% de la región '%s' difiere de FULL en más de %.2f (tope %.2f %%)"
					% [label, 100.0 * bad, region_name, SMEAR_PIXEL_DELTA,
					100.0 * SMEAR_BAD_FRACTION])
		if label == "FAST":
			_check_black_matches_coverage(image, fast_cover, size)


## Las cinco regiones que se comparan, en píxeles.
func _smear_regions(size: Vector2i) -> Dictionary[String, Rect2i]:
	var band := int(roundf(float(size.x) * SMEAR_BAND))
	var strip := int(roundf(float(size.y) * SMEAR_STRIP))
	var centre := int(roundf(float(size.x) * SMEAR_CENTRE_BAND))
	return {
		"izquierda": Rect2i(0, 0, band, size.y),
		"derecha": Rect2i(size.x - band, 0, band, size.y),
		"arriba": Rect2i(band, 0, size.x - band * 2, strip),
		"abajo": Rect2i(band, size.y - strip, size.x - band * 2, strip),
		"centro": Rect2i((size.x - centre) / 2, 0, centre, size.y),
	}


## Diferencia media de luminancia entre [param image] y [param truth] sobre
## [param region].
##
## [param mask] vacío compara todos los píxeles. Si trae cobertura por píxel, sólo
## cuentan aquellos donde la cobertura está **a plena luz** ([param lit] en `true`) o
## exactamente **en cero** ([param lit] en `false`, que es lo que usa la prueba
## negativa para mirar sólo la zona de la viñeta).
func _mean_abs_difference(image: Image, truth: Image, region: Rect2i,
		mask: Dictionary[Vector2i, float], lit: bool) -> Dictionary:
	var total := 0.0
	var samples := 0
	var end_x := mini(region.position.x + region.size.x, image.get_width())
	var end_y := mini(region.position.y + region.size.y, image.get_height())
	var start_x := maxi(region.position.x, 0)
	var y := maxi(region.position.y, 0)
	# Con máscara, el recorrido se alinea a su rejilla o las claves no existirían.
	if not mask.is_empty():
		start_x -= start_x % COVERAGE_STRIDE
		y -= y % COVERAGE_STRIDE
	var step := COVERAGE_STRIDE if not mask.is_empty() else SMEAR_STRIDE
	var bad := 0
	var worst := 0.0
	while y < end_y:
		var x := start_x
		while x < end_x:
			var counts := true
			if not mask.is_empty():
				var cover: float = mask.get(Vector2i(x, y), -1.0)
				counts = cover >= COVERAGE_FULL if lit else cover >= 0.0 and cover <= 1e-6
			if counts:
				var delta := absf(_luminance(image, x, y) - _luminance(truth, x, y))
				total += delta
				worst = maxf(worst, delta)
				if delta > SMEAR_PIXEL_DELTA:
					bad += 1
				samples += 1
			x += step
		y += step
	return {
		"mean": total / maxf(float(samples), 1.0),
		"samples": samples,
		"bad": float(bad) / maxf(float(samples), 1.0),
		"worst": worst,
	}


## `FPVCamera.coverage()` por píxel, en el modo actual, con el paso de
## [constant COVERAGE_STRIDE].
func _coverage_mask(size: Vector2i) -> Dictionary[Vector2i, float]:
	var mask: Dictionary[Vector2i, float] = {}
	var y := 0
	while y < size.y:
		var x := 0
		while x < size.x:
			var direction := _direction_at(Vector2(float(x) + 0.5, float(y) + 0.5))
			mask[Vector2i(x, y)] = 0.0 if direction == Vector3.ZERO \
					else _camera.coverage(direction)
			x += COVERAGE_STRIDE
		y += COVERAGE_STRIDE
	return mask


## El negro de la captura de FAST coincide con lo que predice `coverage()`.
##
## Es el cierre del círculo entre la fila 13 y la 14: la matemática dice dónde no hay
## imagen y la imagen lo confirma. Si el shader se fuera por su lado —por ejemplo
## volviendo al `clamp`—, la captura tendría color donde `coverage()` da 0.
func _check_black_matches_coverage(image: Image, mask: Dictionary[Vector2i, float],
		size: Vector2i) -> void:
	var samples := 0
	var dark := 0
	for point: Vector2i in mask:
		if point.x >= size.x or point.y >= size.y:
			continue
		samples += 1
		# Un píxel que la matemática da por iluminado puede salir oscuro porque el
		# mundo es oscuro ahí; al revés no: si `coverage()` da 0 el shader pinta negro.
		if mask[point] <= 1e-6:
			dark += 1
	var ratio := _lit_where_dark(image, mask, size)
	print("  [14] FAST: el %.2f %% de la viñeta tiene color donde coverage() da 0 (tope %.2f %%); la viñeta es el %.1f %% del cuadro (%d de %d muestras)"
			% [100.0 * ratio, 100.0 * BLACK_MISMATCH,
			100.0 * float(dark) / maxf(float(samples), 1.0), dark, samples])
	expect(dark > 0, "a este hfov FAST tiene que viñetear y la máscara no marcó nada")
	expect(ratio <= BLACK_MISMATCH,
			"en FAST el %.2f %% de la viñeta tiene color donde coverage() da 0 (tope %.2f %%)"
			% [100.0 * ratio, 100.0 * BLACK_MISMATCH])


## La costura de FAST_WIDE: donde la frontal cede el relevo a la lateral, la
## luminancia media no puede dar un escalón.
##
## El relevo cae en `r = (render_fov/2) / (hfov/2)` de la media-anchura, que a
## `hfov` 150 son los 0,8 de siempre. Se calcula y no se cablea, para que cambiar el
## FOV desde el hangar no deje la fila midiendo el lugar equivocado.
func _check_seam(image: Image, label: String) -> void:
	var size := Vector2i(image.get_width(), image.get_height())
	var half := float(size.x) * 0.5
	var hfov := maxf(_camera.get_fisheye_hfov(), 1.0)
	var fraction := FPVCamera.FAST_RENDER_FOV / hfov
	var worst := 0.0
	for direction: int in [-1, 1]:
		var seam := int(roundf(half + float(direction) * fraction * half))
		var inner := _column_luminance(image, seam - SEAM_COLUMNS * direction,
				seam, size)
		var outer := _column_luminance(image, seam, seam + SEAM_COLUMNS * direction,
				size)
		var jump := absf(inner - outer)
		worst = maxf(worst, jump)
		print("  [14] FAST_WIDE costura (%s) en x = %d (%.3f·w): luminancia media %.4f adentro, %.4f afuera, salto %.4f"
				% [label, seam, float(seam) / float(size.x), inner, outer, jump])
		expect(jump <= SEAM_TOLERANCE,
				"en FAST_WIDE (%s) la costura de x = %d salta %.4f de luminancia media (tolerancia %.2f)"
				% [label, seam, jump, SEAM_TOLERANCE])
	print("  [14] FAST_WIDE (%s): peor salto de costura %.4f (tolerancia %.2f), relevo en %.3f·media-anchura"
			% [label, worst, SEAM_TOLERANCE, fraction])


## Luminancia media de las columnas entre [param from] y [param to], en el alto entero.
func _column_luminance(image: Image, from: int, to: int, size: Vector2i) -> float:
	var low := clampi(mini(from, to), 0, size.x - 1)
	var high := clampi(maxi(from, to), 0, size.x)
	var total := 0.0
	var samples := 0
	var x := low
	while x < high:
		var y := 0
		while y < size.y:
			total += _luminance(image, x, y)
			samples += 1
			y += SMEAR_STRIDE
		x += 1
	return total / maxf(float(samples), 1.0)


## Prueba negativa: el `clamp` de antes de WP-24c sobre el mismo render frontal tiene
## que hacer **fallar** la comparación contra FULL.
##
## Sin esta prueba, una fila 14 en verde podría significar «no hay churretón» o «el
## criterio no mide nada». Acá se reconstruye el shader viejo, se lo aplica sobre el
## compuesto y se comprueba que la diferencia contra FULL **supera** la tolerancia. Si
## algún día no la superara, la fila 14 entera dejó de servir y hay que arreglarla a
## ella, no al ojo de pez.
##
## Se mide justo donde `coverage()` da cero, que es donde el `clamp` inventaba píxeles
## repitiendo el texel del borde. En el resto del cuadro el shader viejo y el nuevo
## dan lo mismo, así que promediar la banda entera diluiría el defecto hasta
## esconderlo: medido así daba 0,006 contra FULL y la prueba no probaba nada.
func _check_legacy_clamp(truth: Image, fast_cover: Dictionary[Vector2i, float]) -> void:
	await _set_mode(Graphics.FisheyeMode.FAST)
	_park_drone()
	await wait_frames(SMEAR_SETTLE_FRAMES)
	var composite := _camera.get_composite()
	var viewports := _camera.get_fisheye_viewports()
	if composite == null or viewports.is_empty():
		fail("la prueba negativa de la fila 14 no encontró el compuesto de FAST")
		return
	var shader := Shader.new()
	shader.code = LEGACY_SHADER_CODE
	var legacy := ShaderMaterial.new()
	legacy.shader = shader
	legacy.set_shader_parameter("front_texture", viewports[0].get_texture())
	legacy.set_shader_parameter("hfov", _camera.get_fisheye_hfov())
	legacy.set_shader_parameter("render_fov", FPVCamera.FAST_RENDER_FOV)
	var size := _screen_size()
	legacy.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	var original := composite.material
	composite.material = legacy
	await wait_frames(SETTLE_FRAMES)
	var smeared := await _capture_image()
	composite.material = original
	if smeared == null:
		fail("la prueba negativa de la fila 14 no pudo capturar la imagen con clamp")
		return
	var image_size := Vector2i(smeared.get_width(), smeared.get_height())
	var whole := Rect2i(Vector2i.ZERO, image_size)
	var against_full := _mean_abs_difference(smeared, truth, whole, fast_cover, false)
	var invented := _lit_where_dark(smeared, fast_cover, image_size)
	var samples := int(against_full["samples"])
	print("  [14] prueba negativa (clamp de antes de WP-24c), sólo donde coverage() da 0"
			+ " (%d muestras): inventa imagen en el %.1f %% del área (tope %.2f %%);"
			% [samples, 100.0 * invented, 100.0 * BLACK_MISMATCH]
			+ " contra FULL se separa %.4f de media y arruina el %.2f %%"
			% [float(against_full["mean"]), 100.0 * float(against_full["bad"])])
	# Nota honesta sobre el alcance de cada criterio: en esta pose el promedio contra
	# FULL **no** alcanza para delatar al clamp, porque la periferia de este nivel es
	# casi toda cielo y suelo liso y el texel repetido le acierta; el churretón se ve
	# en el puñado de píxeles donde hay un pilar. El criterio que sí lo caza siempre es
	# el de arriba: donde la matemática dice que no hay imagen, no puede haber color.
	print("  [14] prueba negativa: el promedio contra FULL habría dejado pasar al clamp"
			+ " (%.4f < %.2f); lo que lo caza es el contraste con coverage()"
			% [float(against_full["mean"]), SMEAR_TOLERANCE])
	expect(samples > 0, "la prueba negativa no encontró zona de viñeta que comparar")
	expect(invented > BLACK_MISMATCH * 10.0,
			"el clamp de antes de WP-24c sólo inventa imagen en el %.2f %% de la viñeta:"
			% (100.0 * invented) + " la fila 14 no lo detectaría")


## Fracción de píxeles con color donde [param mask] dice que la cobertura es cero.
##
## Es el mismo criterio de [method _check_black_matches_coverage], sacado aparte para
## poder aplicárselo también al shader viejo en la prueba negativa.
func _lit_where_dark(image: Image, mask: Dictionary[Vector2i, float],
		size: Vector2i) -> float:
	var lit := 0
	var dark := 0
	for point: Vector2i in mask:
		if point.x >= size.x or point.y >= size.y or mask[point] > 1e-6:
			continue
		dark += 1
		if _luminance(image, point.x, point.y) > BLACK_LEVEL:
			lit += 1
	return float(lit) / maxf(float(dark), 1.0)


# --- [13] Cobertura del compuesto (WP-24c) ---------------------------------------------------

## Cada píxel del rectángulo de salida tiene imagen real o es negro honesto, y nunca
## un texel repetido.
##
## `FPVCamera.coverage()` devuelve el mismo factor que el shader multiplica sobre el
## color. Esta fila lo recorre en una rejilla de [constant COVERAGE_GRID] y lo
## contrasta con la geometría **recalculada acá desde cero**: si alguien cambia el
## shader sin cambiar `coverage()`, o al revés, la fila 14 lo ve en la imagen y ésta
## lo ve en la matemática, sin GPU y en un segundo.
##
## Lo que se exige:
## - **FAST_WIDE**: cobertura 1,0 en *todo* el cuadro, esquinas incluidas. A `hfov`
##   150 y 16:9 la esquina está a 86,05° del eje y cae a 0,52 del borde de la cara
##   lateral, así que sobra margen. Con aspectos por debajo de
##   [constant COVERAGE_MIN_ASPECT] las esquinas se salen y sólo se exige `θ ≤ 80°`.
## - **FAST**: 1,0 exactamente donde la cara frontal llega con holgura y 0 exactamente
##   donde no llega. Ese 0 es el reemplazo del churretón.
## - **FULL**: 1,0 en todas partes; las cinco caras cubren el hemisferio.
## - **Continuidad**: en un barrido radial de medio grado, la cobertura nunca salta
##   más de [constant COVERAGE_MAX_JUMP]. Un salto grande es un borde duro, que es lo
##   que se ve como escalón.
func _check_coverage() -> void:
	var size := _screen_size()
	var aspect := size.x / maxf(size.y, 1.0)
	var strict := aspect >= COVERAGE_MIN_ASPECT
	if not strict:
		print("  [13] el rectángulo de salida mide %.0f×%.0f (aspecto %.3f): por debajo de"
				% [size.x, size.y, aspect]
				+ " %.1f las dos caras laterales no llegan a las esquinas de arriba y abajo,"
				% COVERAGE_MIN_ASPECT
				+ " así que la cobertura total de FAST_WIDE no se exige (sí todo lo demás)")
	var lit: Dictionary[String, PackedByteArray] = {}
	for mode: int in _fisheye_modes():
		await _set_mode(mode)
		var label := _mode_name(mode)
		var hfov := _camera.get_fisheye_hfov()
		# Se lee **después** de cambiar de modo: en FULL las sub-viewports son
		# cuadradas y en FAST llevan el aspecto de la pantalla.
		var front_aspect := _front_viewport_aspect()
		var mask := PackedByteArray()
		var samples := 0
		var dark := 0
		var worst_inner := 1.0
		var wrong_full := 0
		var wrong_black := 0
		var worst_theta := 0.0
		for row: int in COVERAGE_GRID.y:
			for column: int in COVERAGE_GRID.x:
				var point := Vector2(
						(float(column) + 0.5) / float(COVERAGE_GRID.x) * size.x,
						(float(row) + 0.5) / float(COVERAGE_GRID.y) * size.y)
				var direction := _direction_at(point)
				var cover := 0.0 if direction == Vector3.ZERO \
						else _camera.coverage(direction)
				mask.append(1 if cover > 1e-6 else 0)
				var theta := _theta_at(point, hfov, aspect)
				samples += 1
				worst_theta = maxf(worst_theta, theta)
				if cover <= 1e-6:
					dark += 1
				if mode != Graphics.FisheyeMode.FAST:
					worst_inner = minf(worst_inner, cover)
					continue
				# FAST: la única cara es la frontal, y su frustum se recalcula acá
				# desde la geometría de `docs/03` §5, sin preguntarle a la cámara.
				var n := _front_normalized(point, hfov, aspect, front_aspect)
				if not n.is_finite():
					if cover > 1e-6:
						wrong_black += 1
					continue
				var inside := absf(n.x) <= 1.0 - FPVCamera.EDGE_FADE \
						and absf(n.y) <= 1.0 - FPVCamera.EDGE_FADE_Y
				var outside := absf(n.x) >= 1.0 or absf(n.y) >= 1.0
				if inside and cover < COVERAGE_FULL:
					wrong_full += 1
				if outside != (cover <= 1e-6):
					wrong_black += 1
		lit[label] = mask
		var sweep := _coverage_sweep(hfov)
		print("  [13] %s: %d muestras (θ máx %.1f°), %.1f %% en negro, cobertura mínima exigible %.3f, %d fuera de contrato; barrido radial: peor salto %.3f/px, transición más angosta %d px"
				% [label, samples, worst_theta, 100.0 * float(dark) / maxf(float(samples), 1.0),
				worst_inner, wrong_full + wrong_black, float(sweep["worst"]),
				int(sweep["narrowest"])])
		if mode == Graphics.FisheyeMode.FAST:
			expect(wrong_full == 0,
					"en FAST hay %d muestras dentro del frustum de la frontal que no están a plena luz"
					% wrong_full)
			expect(wrong_black == 0,
					"en FAST hay %d muestras donde el negro del compuesto no coincide con el borde del frustum de la frontal"
					% wrong_black)
			expect(dark > 0,
					"a hfov %.0f° FAST tiene que dejar los costados en negro y no dejó ninguno"
					% hfov)
		elif mode == Graphics.FisheyeMode.FULL or strict:
			# FULL cubre el hemisferio en cualquier aspecto; FAST_WIDE sólo cuando el
			# rectángulo de salida es lo bastante apaisado como para que sus extremos
			# verticales sigan cayendo dentro de la cara frontal.
			expect(worst_inner >= COVERAGE_FULL,
					"en %s la cobertura baja a %.3f donde tiene que valer 1,0 (aspecto %.3f)"
					% [label, worst_inner, aspect])
			expect(dark == 0,
					"en %s quedaron %d muestras en negro con aspecto %.3f"
					% [label, dark, aspect])
		expect(int(sweep["jumps"]) == 0,
				"en %s la cobertura salta más de %.2f entre dos píxeles vecinos (%d veces): eso es un borde duro, no una viñeta"
				% [label, COVERAGE_MAX_JUMP, int(sweep["jumps"])])
		expect(int(sweep["narrowest"]) < 0
				or int(sweep["narrowest"]) >= COVERAGE_MIN_TRANSITION,
				"en %s la transición más angosta entre imagen y negro mide %d px y tiene que medir al menos %d"
				% [label, int(sweep["narrowest"]), COVERAGE_MIN_TRANSITION])
	_check_wide_covers_fast(lit)


## FAST_WIDE cubre **todo** lo que cubre FAST, y estrictamente más.
##
## Es la invariante que vale en cualquier aspecto, incluido el cuadrado con el que
## corre `--headless`: las dos caras laterales sólo pueden agregar imagen, nunca
## quitarla. Si un día alguien tocara los pesos y FAST_WIDE perdiera un píxel que
## FAST sí tenía, acá se ve sin necesidad de GPU.
func _check_wide_covers_fast(lit: Dictionary[String, PackedByteArray]) -> void:
	var fast: PackedByteArray = lit.get("FAST", PackedByteArray())
	var wide: PackedByteArray = lit.get("FAST_WIDE", PackedByteArray())
	if fast.size() != wide.size() or fast.is_empty():
		fail("la fila 13 no pudo comparar las máscaras de FAST y FAST_WIDE")
		return
	var lost := 0
	var gained := 0
	for index: int in fast.size():
		if fast[index] == 1 and wide[index] == 0:
			lost += 1
		elif fast[index] == 0 and wide[index] == 1:
			gained += 1
	print("  [13] FAST_WIDE contra FAST: %d muestras ganadas, %d perdidas de %d"
			% [gained, lost, fast.size()])
	expect(lost == 0,
			"FAST_WIDE perdió %d muestras que FAST sí cubría: las laterales sólo pueden sumar"
			% lost)
	expect(gained > 0,
			"FAST_WIDE no agregó ninguna muestra sobre FAST: las caras laterales no están"
			+ " aportando nada")


## Barrido radial **en píxeles** desde el centro hacia ocho azimutes, hasta la esquina.
##
## Devuelve `{jumps, worst, narrowest}`: cuántos pares de píxeles vecinos saltan más
## de [constant COVERAGE_MAX_JUMP], cuál fue el peor salto, y cuántos píxeles mide la
## transición imagen↔negro más angosta que se encontró (`-1` si no hubo ninguna).
func _coverage_sweep(_hfov: float) -> Dictionary:
	var size := _screen_size()
	var centre := size * 0.5
	var reach := int(centre.length())
	var jumps := 0
	var worst := 0.0
	var narrowest := -1
	for azimuth_step: int in 8:
		var phi := TAU * float(azimuth_step) / 8.0
		var step_vector := Vector2(cos(phi), sin(phi))
		var previous := -1.0
		var transition := 0
		for radius: int in reach + 1:
			var point := centre + step_vector * float(radius)
			if point.x < 0.0 or point.y < 0.0 or point.x >= size.x or point.y >= size.y:
				break
			var direction := _direction_at(point)
			var cover := 0.0 if direction == Vector3.ZERO else _camera.coverage(direction)
			if previous >= 0.0:
				var jump := absf(cover - previous)
				worst = maxf(worst, jump)
				if jump > COVERAGE_MAX_JUMP:
					jumps += 1
			if cover > 0.02 and cover < 0.98:
				transition += 1
			elif transition > 0:
				narrowest = transition if narrowest < 0 else mini(narrowest, transition)
				transition = 0
			previous = cover
		if transition > 0:
			narrowest = transition if narrowest < 0 else mini(narrowest, transition)
	return {"jumps": jumps, "worst": worst, "narrowest": narrowest}


## Ángulo polar, en grados, que el compuesto dibuja en el píxel [param point].
func _theta_at(point: Vector2, hfov: float, aspect: float) -> float:
	var size := _screen_size()
	var half := size * 0.5
	var p := Vector2((point.x - half.x) / half.x, (point.y - half.y) / half.y)
	return Vector2(p.x, p.y / aspect).length() * hfov * 0.5


## Coordenadas normalizadas del píxel [param point] en la cara frontal: `|n| ≤ 1`
## dentro del frustum, `Vector2.INF` si cae por detrás.
##
## Es la fórmula de `docs/03` §5 escrita desde la geometría —`tan θ` sobre
## `tan(render_fov/2)`, con el aspecto en el eje vertical— y no una llamada a la
## cámara: de eso vive el valor de esta fila.
func _front_normalized(point: Vector2, hfov: float, aspect: float,
		front_aspect: float) -> Vector2:
	var size := _screen_size()
	var half := size * 0.5
	var p := Vector2((point.x - half.x) / half.x, (point.y - half.y) / half.y)
	var q := Vector2(p.x, p.y / aspect)
	var radius := q.length()
	var theta := radius * deg_to_rad(hfov) * 0.5
	if theta >= deg_to_rad(89.9):
		return Vector2.INF
	var unit := q / radius if radius > 1e-6 else Vector2.ZERO
	var scale := tan(theta) / tan(deg_to_rad(FPVCamera.FAST_RENDER_FOV) * 0.5)
	return Vector2(unit.x * scale, unit.y * scale * front_aspect)


## Relación de aspecto de la sub-viewport frontal, leída de la viewport de verdad.
func _front_viewport_aspect() -> float:
	var viewports := _camera.get_fisheye_viewports()
	if not viewports.is_empty() and viewports[0].size.y > 0:
		return float(viewports[0].size.x) / float(viewports[0].size.y)
	var size := _screen_size()
	return size.x / maxf(size.y, 1.0)


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


## Guarda una imagen ya capturada como `<shots_dir>/<check_name>_<name>.png`. A
## diferencia de [method CheckRunner.shot] no vuelve a dibujar: escribe el cuadro que
## se midió.
func _save_image(image: Image, file_name: String) -> void:
	if shots_dir.is_empty() or image == null:
		return
	var err := image.save_png("%s/%s_%s.png" % [shots_dir, check_name, file_name])
	if err != OK:
		fail("no se pudo guardar la captura '%s': %s" % [file_name, error_string(err)])


## Imagen de la viewport ya dibujada, o `null` si no hay rasterizado.
func _capture_image() -> Image:
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	return texture.get_image() if texture != null else null


## Fila donde la columna [param column] pasa del plano negro de medición al cielo,
## interpolada entre píxeles. `NAN` si no hay contraste o no hay cruce.
##
## Se busca el **borde más pronunciado** de la columna —la fila que maximiza
## `|L(y+1) − L(y−1)|`— con refinamiento sub-píxel por parábola.
##
## No se busca el punto medio entre la fila de arriba de todo y la de abajo de todo,
## que era lo que hacía antes. Ese criterio suponía dos zonas planas separadas por un
## escalón, y la iluminación de atardecer que entró en `world/environment_battle.tres`
## rompe las dos suposiciones: el cielo va de claro sobre el sol a oscuro en el cenit
## —así que la luminancia cruza el medio **dos veces** y el barrido desde arriba
## enganchaba el degradado del cielo, hasta 130 px de error— y la niebla de
## profundidad difumina el plano negro en otro degradado, así que tampoco hay un
## umbral absoluto que sirva (medido: 400 px de error por abajo).
##
## El borde más pronunciado, en cambio, no depende de cuánto valgan el cielo y el
## suelo sino de que entre ellos haya una transición más abrupta que sus propios
## degradados, que es lo único que este criterio necesita de verdad. Vale para el
## atardecer, para un mediodía plano y para lo que venga después.
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
	var best_y := -1
	var best := 0.0
	for y: int in range(LUMINANCE_EDGE_MARGIN + 1, height - LUMINANCE_EDGE_MARGIN - 1):
		var gradient := absf(_luminance(image, x, y + 1) - _luminance(image, x, y - 1))
		if gradient > best:
			best = gradient
			best_y = y
	if best_y < 0 or best < LUMINANCE_MIN_CONTRAST * 0.25:
		return NAN
	# Vértice de la parábola por los tres gradientes vecinos: el borde real casi nunca
	# cae en el centro exacto de un píxel.
	var previous := absf(_luminance(image, x, best_y) - _luminance(image, x, best_y - 2))
	var next := absf(_luminance(image, x, best_y + 2) - _luminance(image, x, best_y))
	var denominator := previous - 2.0 * best + next
	var offset_y := 0.0
	if absf(denominator) > 1e-9:
		offset_y = clampf(0.5 * (previous - next) / denominator, -1.0, 1.0)
	return float(best_y) + offset_y


func _luminance(image: Image, x: int, y: int) -> float:
	var colour := image.get_pixel(x, y)
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
