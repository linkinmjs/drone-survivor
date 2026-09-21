## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cámara FPV del dron con ojo de pez en cuatro modos (`docs/03` §5).
##
## Es la vista principal del juego: cuelga del [CameraRig] con transformada identidad
## —el rig es quien la inclina y quien la sacudirá en WP-28— y se hace `current` al
## entrar al árbol, así que al cargar un nivel se ve por los ojos del piloto.
##
## ## Los cuatro modos (`Graphics.fisheye_mode`)
##
## - **OFF**: una [Camera3D] común. El FOV horizontal se acota a 60–120° con
##   `keep_aspect = KEEP_WIDTH`, porque una proyección rectilínea más ancha que eso
##   estira los bordes hasta lo grotesco.
## - **FAST**: una `SubViewport` con un render rectilíneo de 120° y un `ColorRect` de
##   pantalla completa que lo remapea a proyección equidistante
##   (`drone/fpv_camera/fisheye_fast.gdshader`). Una viewport extra. Más allá de 60°
##   **no hay imagen**: el compuesto se va a negro con una viñeta de unos 32 px, que
##   a `hfov` 150 empieza a 0,76 de media-anchura y deja el 28 % del cuadro en negro.
## - **FAST_WIDE**: la misma frontal más **dos caras cuadradas de 100° giradas ±60°**
##   que rellenan justo los costados que a FAST le faltan. Tres viewports, pero las
##   dos laterales son baratas —2/3 del alto en HIGH y el alto entero en ULTRA, MSAA
##   acotado a 2×, LOD 4 px y un `Environment` propio sin SDFGI ni niebla
##   volumétrica—: a `hfov` 150 y 16:9 la cobertura es **1,000 en todo el cuadro** y
##   no queda ni viñeta ni costura. Es el modo de HIGH y de ULTRA.
## - **FULL**: cinco `SubViewport` cuadradas —frente, derecha, izquierda, arriba y
##   abajo— con cámaras de 100° solapadas, mezcladas por peso en la banda de solape
##   (`drone/fpv_camera/fisheye_full.gdshader`). Cubre el hemisferio entero, que es lo
##   único que gana sobre FAST_WIDE por encima de 157° de `hfov`. **Ningún preset lo
##   usa**: cuesta 14,1 ms de GPU contra 4,2, se pasa del presupuesto de draw calls de
##   `docs/15` §5.2 y es indistinguible de FAST_WIDE a ojo. Queda como opción del menú
##   para quien quiera 170° sin viñeta.
##
## ## Por qué FAST_WIDE existe (WP-24c)
##
## FAST remapea un render de 120°, o sea ±60°, a un círculo de `hfov` grados. Con el
## `hfov` por defecto de 150 el borde horizontal de la pantalla pide 75°, y los 15°
## que faltan **no están renderizados**. La versión anterior los rellenaba acotando
## el muestreo al borde de la textura, lo que repetía el último texel a lo largo de
## unos 192 px de cada costado a 1920: el churretón que reportó el jugador. Subir el
## `render_fov` no sirve —el centro se desenfoca con el cuadrado de la tangente, 2,1×
## a 140°— así que la respuesta honesta es una de dos: o no hay imagen y se ve negro
## (FAST), o se renderiza de verdad (FAST_WIDE).
##
## La resolución y el MSAA de las sub-viewports salen de `Graphics.fisheye_height()` y
## `Graphics.fisheye_msaa_level()` (`docs/04` §3.5), y el árbol se reconstruye entero
## cuando suena `Graphics.fisheye_changed`.
##
## ## Convención de la proyección
##
## El medio campo horizontal se mapea a media pantalla de ancho: una dirección a
## `hfov/2` del eje óptico cae en el borde horizontal. Es la misma fórmula en el
## shader (dirección → píxel, invertida) y en [method project_direction] (píxel →
## dirección), y por eso el HUD calza con la imagen (`docs/12` §3.1).
##
## ## Detalles de implementación que importan
##
## - Con ojo de pez, la cámara **no dibuja la escena** (`cull_mask = 0`): lo que se ve
##   es el compuesto. Si además rasterizara, cada frame se renderizaría la escena dos
##   veces y los draw calls se duplicarían de gordo.
## - Y con `cull_mask = 0` **no alcanza**: la viewport raíz seguía siendo una viewport
##   3D con una cámara `current`, así que pagaba cielo, SSAO, SDFGI, niebla volumétrica,
##   post y resolve de MSAA a pantalla completa para no mostrar nada. Medido en WP-24a:
##   1,77 ms de GPU por cuadro, el 39 % del total. Mientras el compuesto está visible se
##   pone `get_viewport().disable_3d = true`, y vuelve a `false` en cuanto la FPV deja de
##   ser la cámara activa —la `IntroCamera` y `LevelBase.change_camera()` sí dibujan por
##   la raíz— o la cámara sale del árbol.
## - El compuesto vive en un `CanvasLayer` propio en la capa −2, debajo del overlay FPV
##   (−1) y del `FlightHUD` (0), según la tabla de capas de `docs/12` §1.1. El HUD queda
##   **fuera** de las sub-viewports, así que no se deforma (riesgo 1 de `docs/12` §10).
## - Solo se dibuja cuando esta cámara es la `current`: si el nivel cicla a la cámara de
##   seguimiento, el compuesto se esconde y las sub-viewports dejan de renderizar.
## - Los nodos del ojo de pez se crean en código para que `drone_rig.tscn` quede con
##   los tres nodos de `docs/03` §8 y nada más.
class_name FPVCamera
extends Camera3D

## Campo horizontal del render rectilíneo de FAST, en grados (`docs/03` §10).
const FAST_RENDER_FOV: float = 120.0

## Campo de cada una de las cinco caras de FULL, en grados (`docs/03` §10).
const FULL_FACE_FOV: float = 100.0

## Campo de cada una de las dos caras laterales de FAST_WIDE, en grados. Es el mismo
## de FULL: una cara cuadrada de 100° girada 60° solapa 10° con el borde de la
## frontal, que es de sobra para el fundido cruzado de `edge_fade`.
const SIDE_FACE_FOV: float = 100.0

## Guiñada de cada cara lateral de FAST_WIDE respecto del eje óptico, en grados.
##
## Con 60° y caras de 100°, las laterales cubren de 10° a 110° del eje. La frontal
## llega a 60°, así que el relevo ocurre muy adentro de las dos y el punto más
## exigente del cuadro —la esquina, a 86° del eje y 29° de azimut— cae a 0,52 del
## borde de la lateral. Verificado en `tools/hud_projection_check` fila 13.
const SIDE_FACE_YAW: float = 60.0

## Ancho de la transición a negro del compuesto en horizontal —y en las dos
## direcciones de las caras laterales—, en unidades normalizadas de la cara.
##
## 0,10 equivale a fundir de 57,3° a 60° en la frontal: unos 32 px a 1920. Cumple dos
## papeles a la vez, la viñeta de FAST y el fundido cruzado con la lateral de
## FAST_WIDE, porque los dos ocurren en el mismo borde.
const EDGE_FADE: float = 0.10

## Ídem en el **vertical de la frontal**, donde ninguna lateral toma el relevo.
##
## Arriba y abajo del centro la frontal es la única cara que existe: con los 0,10 del
## horizontal, el borde superior e inferior del cuadro se oscurecería hasta el 38 %.
## Con 0,02 la transición sigue midiendo entre 4 y 10 px —de sobra para que no se vea
## escalonada— y la cobertura de FAST_WIDE queda en 1,000.
const EDGE_FADE_Y: float = 0.02

## Ancho de la banda de mezcla entre caras de FULL.
##
## Tiene que superar `1 − tan 45°/tan(FULL_FACE_FOV/2)` = 0,161 o el reparto entre dos
## caras tendría una meseta de 50/50 de cuatro grados de ancho, o sea una banda
## borrosa en vez de una costura.
const FULL_EDGE_FADE: float = 0.20

## Profundidad mínima para que una cara tenga imagen rectilínea. Espejo de `MIN_DEPTH`
## de los dos shaders.
const MIN_FACE_DEPTH: float = 1e-3

## Plano cercano de la cámara y de todas sus sub-cámaras, en metros.
const NEAR_PLANE: float = 0.02

## Plano lejano de la cámara y de todas sus sub-cámaras, en metros.
const FAR_PLANE: float = 2000.0

## Rango del FOV horizontal sin ojo de pez, en grados (`docs/03` §5).
const RECTILINEAR_FOV_RANGE: Vector2 = Vector2(60.0, 120.0)

## Rango del FOV horizontal con ojo de pez, en grados (`QuadSettings.FOV_RANGE`).
const FISHEYE_FOV_RANGE: Vector2 = Vector2(90.0, 170.0)

## Capa de canvas del compuesto: debajo del overlay FPV (−1) y del HUD (0),
## `docs/12` §1.1.
const COMPOSITE_LAYER: int = -2

## Las sub-cámaras copian la transformada de la FPV al final del frame, después de que
## el rig haya escrito la suya (la sacudida de WP-28 también correrá en `_process`).
const SYNC_PRIORITY: int = 100

## Shader de los modos FAST y FAST_WIDE.
const FAST_SHADER: String = "res://drone/fpv_camera/fisheye_fast.gdshader"

## Shader del modo FULL.
const FULL_SHADER: String = "res://drone/fpv_camera/fisheye_full.gdshader"

## Nombre del uniform de cada cara de FULL, en el orden de [enum Face].
const FACE_UNIFORMS: Array[String] = [
	"face_front", "face_right", "face_left", "face_up", "face_down",
]

## Nombre del uniform de cada cara de FAST/FAST_WIDE, en el orden en que se crean.
const FAST_UNIFORMS: Array[String] = [
	"front_texture", "side_right_texture", "side_left_texture",
]

## Tamaño de pantalla que se asume cuando la cámara todavía no tiene viewport.
const FALLBACK_SCREEN: Vector2 = Vector2(1920.0, 1080.0)

## Resultado de [method project_direction] para una dirección fuera del campo visual.
const OUT_OF_FIELD: Vector2 = Vector2(NAN, NAN)

## Lado mínimo de una sub-viewport, en píxeles.
const MIN_VIEWPORT_SIDE: int = 16

## Caras de FULL, en el orden en que se crean y en que el shader las nombra.
enum Face {FRONT, RIGHT, LEFT, UP, DOWN}

## Si la cámara se hace `current` al entrar al árbol. Es lo normal —la FPV es la vista
## de juego—; un rig decorativo (menú, cinemática) lo apaga para no robarle la vista a
## la cámara de la escena.
@export var current_on_ready: bool = true

## FOV horizontal pedido por el hangar, sin acotar. Lo acota [method _apply_fov] según
## el modo, porque los rangos de OFF y de ojo de pez no son el mismo.
var _requested_fov: float = QuadSettings.DEFAULT_FOV

## Campo horizontal efectivo del ojo de pez, en grados; `0.0` en OFF.
var _hfov: float = 0.0

## Modo de ojo de pez aplicado ahora mismo ([enum Graphics.FisheyeMode]).
var _mode: int = Graphics.FisheyeMode.OFF

## Máscara de capas con la que se dibuja la escena. La cámara principal la cede
## (`cull_mask = 0`) mientras el compuesto está al mando; las sub-cámaras la heredan.
var _scene_cull_mask: int = 0xFFFFF

## Alto de sub-viewport con el que se construyó lo que hay ahora, en píxeles.
var _built_height: int = 0

## MSAA con el que se construyó lo que hay ahora.
var _built_msaa: int = -1

## Tamaño con el que se construyó la sub-viewport principal, en píxeles.
var _built_size: Vector2i = Vector2i.ZERO

## Lado con el que se construyeron las caras laterales de FAST_WIDE, en píxeles.
var _built_side: int = 0

var _layer: CanvasLayer = null
var _composite: ColorRect = null
var _render_root: Node = null
var _material: ShaderMaterial = null
var _viewports: Array[SubViewport] = []
var _sub_cameras: Array[Camera3D] = []
var _face_bases: Array[Basis] = []

## Paralelo a [member _viewports]: si esa viewport es una cara lateral de FAST_WIDE,
## que lleva LOD, MSAA y `Environment` propios.
var _face_is_side: Array[bool] = []

## `Environment` del mundo del que se derivó [member _side_environment], para notar
## cuándo el nivel lo cambió.
var _source_environment: Environment = null

## Clon barato del `Environment` del nivel que usan las caras laterales.
var _side_environment: Environment = null


func _ready() -> void:
	process_priority = SYNC_PRIORITY
	add_to_group(&"fpv_camera")
	_scene_cull_mask = cull_mask
	_requested_fov = QuadSettings.fov
	keep_aspect = KEEP_WIDTH
	near = NEAR_PLANE
	far = FAR_PLANE
	_build_layer()
	_apply_graphics()
	if current_on_ready:
		make_current()
	var _discard := Graphics.fisheye_changed.connect(_on_fisheye_changed)
	# `Graphics.apply_environment_quality()` reescribe el `Environment` del nivel **en
	# el lugar**, así que comparar la referencia no alcanza para notar un cambio de
	# preset: sin esto, las caras laterales de FAST_WIDE se quedarían con el clon de la
	# calidad anterior hasta el próximo cambio de nivel.
	_discard = Graphics.environment_quality_changed.connect(_on_environment_quality_changed)
	_discard = QuadSettings.settings_updated.connect(_on_quad_settings_updated)
	var viewport := get_viewport()
	if viewport != null:
		_discard = viewport.size_changed.connect(_on_screen_resized)


func _exit_tree() -> void:
	# Devolver el 3D a la raíz es obligatorio: si el nivel se descarga con el
	# compuesto visible, la viewport raíz quedaría sin 3D para siempre y el menú
	# siguiente se vería negro.
	var root := get_viewport()
	if root != null and root.disable_3d:
		root.disable_3d = false
	if Graphics.fisheye_changed.is_connected(_on_fisheye_changed):
		Graphics.fisheye_changed.disconnect(_on_fisheye_changed)
	if Graphics.environment_quality_changed.is_connected(_on_environment_quality_changed):
		Graphics.environment_quality_changed.disconnect(_on_environment_quality_changed)
	if QuadSettings.settings_updated.is_connected(_on_quad_settings_updated):
		QuadSettings.settings_updated.disconnect(_on_quad_settings_updated)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_screen_resized):
		viewport.size_changed.disconnect(_on_screen_resized)


func _process(_delta: float) -> void:
	PerfProbe.begin(&"fpv_camera")
	_update_composite_state()
	if not _sub_cameras.is_empty():
		_refresh_side_environment()
		var facing := global_basis.orthonormalized()
		var origin := global_position
		for index: int in _sub_cameras.size():
			var camera := _sub_cameras[index]
			if is_instance_valid(camera):
				camera.global_transform = Transform3D(facing * _face_bases[index], origin)
	PerfProbe.end(&"fpv_camera")


# --- Interfaz pública (`docs/03` §9) ---------------------------------------------------------

## Fija el FOV horizontal pedido, en grados. Con ojo de pez vale 90–170 y es el campo
## del círculo completo; sin ojo de pez se acota a 60–120 y es el FOV rectilíneo de la
## [Camera3D], con `keep_aspect = KEEP_WIDTH` para que el número signifique lo mismo en
## cualquier relación de aspecto.
func set_horizontal_fov(fov_h: float) -> void:
	_requested_fov = fov_h
	_apply_fov()
	_update_uniforms()


## Cambia el modo de ojo de pez ([enum Graphics.FisheyeMode]) y reconstruye lo que haga
## falta. Llamarla con el modo que ya está puesto no rehace nada, salvo que hayan
## cambiado la resolución o el MSAA del ojo de pez.
func set_fisheye_mode(mode: int) -> void:
	var wanted := clampi(mode, 0, Graphics.FisheyeMode.size() - 1)
	var height := Graphics.fisheye_height()
	var msaa := int(Graphics.fisheye_msaa_level())
	var size := _target_viewport_size(wanted, height)
	var side := Graphics.fisheye_side_height()
	var built := not _viewports.is_empty()
	var needs_viewports := wanted != Graphics.FisheyeMode.OFF
	if wanted == _mode and height == _built_height and msaa == _built_msaa \
			and size == _built_size and side == _built_side and built == needs_viewports:
		_apply_fov()
		_update_uniforms()
		return
	_mode = wanted
	_built_height = height
	_built_msaa = msaa
	_built_size = size
	_built_side = side
	_rebuild()


## Dirección en el mundo → píxel de la viewport raíz, o `Vector2(NAN, NAN)` si la
## dirección cae fuera del campo visual (`docs/03` §5).
##
## OFF usa la proyección rectilínea de la propia cámara; los tres modos de ojo de pez
## usan la **misma** fórmula equidistante analítica, porque el compuesto es
## equidistante por construcción y el HUD sólo depende de eso, no de cuántas cámaras
## lo alimenten. Los cuatro devuelven el centro exacto para la dirección `−basis.z`.
##
## Hasta WP-24c, FAST tenía una rama propia que desproyectaba sobre el render
## rectilíneo y rehacía el remapeo del shader al revés. Era exactamente la misma
## función —`atan(rs · tan(fov/2))` deshace `tan θ / tan(fov/2)`— con dos vueltas de
## coma flotante de más y una dependencia gratuita de `unproject_position`, que
## FAST_WIDE ya no podría satisfacer con una sola matriz.
func project_direction(dir: Vector3) -> Vector2:
	if not is_inside_tree() or not dir.is_finite() or dir.length_squared() <= 0.0:
		return OUT_OF_FIELD
	var unit := dir.normalized()
	if _mode == Graphics.FisheyeMode.OFF:
		return _project_rectilinear(unit)
	return _project_equidistant(unit, _hfov)


## Punto del mundo → píxel de la viewport raíz, con la misma semántica que
## [method project_direction].
func project_point(world_point: Vector3) -> Vector2:
	if not is_inside_tree():
		return OUT_OF_FIELD
	return project_direction(world_point - global_position)


## Campo horizontal del ojo de pez en grados, o `0.0` si está en OFF. Es el `hfov` que
## espera `HUDProjection` (`docs/12` §3).
func get_fisheye_hfov() -> float:
	return _hfov


## Modo de ojo de pez aplicado ([enum Graphics.FisheyeMode]).
func get_fisheye_mode() -> int:
	return _mode


## Verdadero cuando hay un compuesto de ojo de pez construido.
func is_fisheye_active() -> bool:
	return _mode != Graphics.FisheyeMode.OFF and not _viewports.is_empty()


## El `ColorRect` del compuesto. Lo miran los checks.
func get_composite() -> ColorRect:
	return _composite


## Las sub-viewports vivas: una en FAST, tres en FAST_WIDE, cinco en FULL, ninguna
## en OFF.
func get_fisheye_viewports() -> Array[SubViewport]:
	return _viewports.duplicate()


## Cuánta imagen real hay en la dirección [param dir], de `0.0` (negro: ninguna cara
## la tiene renderizada) a `1.0` (la cubre al menos una cara con holgura).
##
## Es el **espejo exacto en GDScript** del factor `cover` que aplica el shader, y
## existe para que `tools/hud_projection_check` pueda verificar sin GPU que el
## compuesto no tiene ni churretón ni agujeros: donde esta función da `0.0` el shader
## pinta negro, y donde da `1.0` pinta imagen a plena luz. Si alguien toca una de las
## dos fórmulas sin tocar la otra, la fila 13 del check lo detecta.
##
## - **OFF** no tiene compuesto —la escena la dibuja la viewport raíz— y devuelve
##   siempre `1.0`.
## - **FAST** devuelve el peso de la única cara frontal.
## - **FAST_WIDE** devuelve la unión `wf + (1 − wf)·ws`, que es 1 si **alguna** de las
##   tres caras cubre la dirección con holgura.
## - **FULL** devuelve `1.0` mientras alguna de las cinco caras aporte: el shader
##   normaliza por la suma de pesos, así que ahí no hay medias tintas.
##
## [param dir] va en coordenadas de mundo, igual que [method project_direction].
func coverage(dir: Vector3) -> float:
	if not is_inside_tree() or not dir.is_finite() or dir.length_squared() <= 0.0:
		return 0.0
	if _mode == Graphics.FisheyeMode.OFF:
		return 1.0
	var local := (global_basis.orthonormalized().inverse() * dir).normalized()
	if _mode == Graphics.FisheyeMode.FULL:
		return 1.0 if _full_weight(local) > 0.0 else 0.0
	var front := _front_weight(local)
	if _mode != Graphics.FisheyeMode.FAST_WIDE:
		return front
	return front + (1.0 - front) * _side_weight(local)


# --- Proyección ------------------------------------------------------------------------------

## Proyección rectilínea: la de la propia [Camera3D], con la guarda de «detrás».
func _project_rectilinear(unit: Vector3) -> Vector2:
	var point := global_position + unit
	if is_position_behind(point):
		return OUT_OF_FIELD
	var projected := unproject_position(point)
	return projected if projected.is_finite() else OUT_OF_FIELD


## Proyección equidistante analítica: `r = θ / (hfov/2)` del centro, con el azimut
## `φ = atan2(local.y, local.x)` (`docs/12` §3.1).
func _project_equidistant(unit: Vector3, hfov: float) -> Vector2:
	var half_field := deg_to_rad(hfov) * 0.5
	if half_field <= 0.0:
		return OUT_OF_FIELD
	var local := (global_basis.orthonormalized().inverse() * unit).normalized()
	var theta := acos(clampf(-local.z, -1.0, 1.0))
	if theta > half_field:
		return OUT_OF_FIELD
	var centre := _screen_centre()
	var radius := theta / half_field * maxf(centre.x, 1.0)
	var phi := atan2(local.y, local.x)
	return centre + Vector2(cos(phi), -sin(phi)) * radius


# --- Cobertura: el espejo en GDScript de los shaders -----------------------------------------

## Peso de un eje de una cara: 1 bien adentro del frustum, 0 justo en el borde.
## Espejo de `edge_weight()` de `fisheye_fast.gdshader`.
func _edge_weight(coord: float, fade: float) -> float:
	return 1.0 - smoothstep(1.0 - fade, 1.0, absf(coord))


## [param local] en coordenadas normalizadas de una cara: `|n| ≤ 1` dentro del
## frustum. [param half_tangent] es `tan(fov/2)` y [param vertical_scale] lleva la
## relación de aspecto cuando la cara no es cuadrada. `Vector2.INF` si queda detrás.
func _face_normalized(local: Vector3, axis: Vector3, right: Vector3,
		half_tangent: float, vertical_scale: float) -> Vector2:
	var depth := local.dot(axis)
	if depth <= MIN_FACE_DEPTH:
		return Vector2.INF
	return Vector2(local.dot(right), -local.y * vertical_scale) / (depth * half_tangent)


## Peso de la cara frontal de FAST/FAST_WIDE sobre la dirección [param local], ya en
## coordenadas de cámara.
func _front_weight(local: Vector3) -> float:
	var half_tangent := tan(deg_to_rad(FAST_RENDER_FOV) * 0.5)
	var n := _face_normalized(local, Vector3.FORWARD, Vector3.RIGHT, half_tangent,
			_front_aspect())
	if not n.is_finite():
		return 0.0
	return _edge_weight(n.x, EDGE_FADE) * _edge_weight(n.y, EDGE_FADE_Y)


## Peso de la cara lateral del lado de `local.x` en FAST_WIDE.
func _side_weight(local: Vector3) -> float:
	var sign_x := 1.0 if local.x >= 0.0 else -1.0
	var cos_yaw := cos(deg_to_rad(SIDE_FACE_YAW))
	var sin_yaw := sin(deg_to_rad(SIDE_FACE_YAW))
	var axis := Vector3(sign_x * sin_yaw, 0.0, -cos_yaw)
	var right := Vector3(cos_yaw, 0.0, sign_x * sin_yaw)
	var n := _face_normalized(local, axis, right,
			tan(deg_to_rad(SIDE_FACE_FOV) * 0.5), 1.0)
	if not n.is_finite():
		return 0.0
	return _edge_weight(n.x, EDGE_FADE) * _edge_weight(n.y, EDGE_FADE)


## Suma de los pesos de las cinco caras de FULL, que es lo que el shader normaliza.
func _full_weight(local: Vector3) -> float:
	var half_tangent := tan(deg_to_rad(FULL_FACE_FOV) * 0.5)
	var total := 0.0
	for index: int in FACE_UNIFORMS.size():
		# La cara ve `local` girado por la inversa de su base, que es justo lo que
		# hace el shader con sus `vec3(d.z, d.y, -d.x)` y compañía.
		var face := _face_basis(index).inverse() * local
		var n := _face_normalized(face, Vector3.FORWARD, Vector3.RIGHT, half_tangent, 1.0)
		if not n.is_finite():
			continue
		total += _edge_weight(n.x, FULL_EDGE_FADE) * _edge_weight(n.y, FULL_EDGE_FADE)
	return total


## Relación ancho/alto de la sub-viewport frontal, que es la que el shader necesita
## para el eje vertical de la cara.
func _front_aspect() -> float:
	if _built_size.x > 0 and _built_size.y > 0:
		return float(_built_size.x) / float(_built_size.y)
	var screen := _screen_size()
	return screen.x / maxf(screen.y, 1.0)


## Centro de la viewport raíz, en píxeles.
func _screen_centre() -> Vector2:
	return _screen_size() * 0.5


## Tamaño visible de la viewport raíz, en píxeles.
func _screen_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return FALLBACK_SCREEN
	var size := viewport.get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return FALLBACK_SCREEN
	return size


# --- Construcción del ojo de pez -------------------------------------------------------------

## Crea, una sola vez, el `CanvasLayer` del compuesto y el nodo que aloja las
## sub-viewports. El `ColorRect` arranca invisible: hasta que no haya modo de ojo de
## pez no hay nada que dibujar.
func _build_layer() -> void:
	if is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.name = "FisheyeComposite"
	_layer.layer = COMPOSITE_LAYER
	add_child(_layer)
	_composite = ColorRect.new()
	_composite.name = "Composite"
	_composite.color = Color.BLACK
	_composite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_composite.visible = false
	_layer.add_child(_composite)
	_render_root = Node.new()
	_render_root.name = "FisheyeViewports"
	_layer.add_child(_render_root)


## Lee el estado de `Graphics` y deja la cámara en ese modo.
func _apply_graphics() -> void:
	set_fisheye_mode(int(Graphics.fisheye_mode))
	_apply_viewport_quality()


## Vuelca sobre las sub-viewports ya construidas lo que puede cambiar sin rehacer el
## árbol: escala de render, modo de escalado, LOD y oclusión. Cambiar la resolución o
## el MSAA sí obliga a reconstruir, y de eso se ocupa [method set_fisheye_mode].
func _apply_viewport_quality() -> void:
	var render_scale := Graphics.fisheye_render_scale()
	var mode := Graphics.fisheye_scaling_mode()
	var lod := Graphics.mesh_lod_threshold()
	var side_lod := Graphics.fisheye_side_mesh_lod()
	var occlusion := Graphics.use_occlusion_culling()
	for index: int in _viewports.size():
		var viewport := _viewports[index]
		if not is_instance_valid(viewport):
			continue
		viewport.scaling_3d_mode = mode
		viewport.scaling_3d_scale = render_scale
		viewport.mesh_lod_threshold = side_lod if _face_is_side[index] else lod
		viewport.use_occlusion_culling = occlusion


## Rehace las sub-viewports del modo actual. Es la única función que crea o destruye
## nodos de render: por eso un cambio de modo en caliente no puede dejar fugas.
func _rebuild() -> void:
	_clear_viewports()
	match _mode:
		Graphics.FisheyeMode.FAST:
			_build_fast(false)
		Graphics.FisheyeMode.FAST_WIDE:
			_build_fast(true)
		Graphics.FisheyeMode.FULL:
			_build_full()
		_:
			pass
	_apply_fov()
	_update_uniforms()
	_update_composite_state()


## Saca del árbol y libera las sub-viewports vivas.
func _clear_viewports() -> void:
	for viewport: SubViewport in _viewports:
		if not is_instance_valid(viewport):
			continue
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var parent := viewport.get_parent()
		if parent != null:
			parent.remove_child(viewport)
		viewport.queue_free()
	_viewports.clear()
	_sub_cameras.clear()
	_face_bases.clear()
	_face_is_side.clear()
	# El clon y los atributos se vuelven a derivar en el primer `_process` del modo
	# nuevo, cuando ya existen las sub-cámaras a las que asignárselos.
	_source_environment = null
	_side_environment = null
	if is_instance_valid(_composite):
		_composite.material = null
	_material = null


## FAST y FAST_WIDE: una sub-viewport rectilínea con la relación de aspecto de la
## pantalla y, con [param wide], dos caras cuadradas giradas ±[constant SIDE_FACE_YAW].
##
## Las laterales se crean **después** de la frontal, así que el orden de
## [member _viewports] es el de [constant FAST_UNIFORMS] —frontal, derecha,
## izquierda— y el check puede contar 1 o 3 sin mirar nada más.
func _build_fast(wide: bool) -> void:
	var shader := load(FAST_SHADER) as Shader
	if shader == null:
		push_error("FPVCamera: no se pudo cargar %s" % FAST_SHADER)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	var front := _add_face(Basis.IDENTITY, FAST_RENDER_FOV, _built_size, false)
	_material.set_shader_parameter(FAST_UNIFORMS[0], front.get_texture())
	if not wide:
		_composite.material = _material
		return
	var side_size := Vector2i(_built_side, _built_side)
	for index: int in 2:
		# `Basis(UP, θ)` lleva el −Z de la cara a `(−sin θ, 0, −cos θ)`: la guiñada
		# hacia la derecha es la **negativa**, igual que en [method _face_basis].
		var yaw := deg_to_rad(SIDE_FACE_YAW) * (-1.0 if index == 0 else 1.0)
		var viewport := _add_face(Basis(Vector3.UP, yaw), SIDE_FACE_FOV, side_size, true)
		_material.set_shader_parameter(FAST_UNIFORMS[index + 1], viewport.get_texture())
	_composite.material = _material


## FULL: cinco sub-viewports cuadradas, una por cara.
func _build_full() -> void:
	var shader := load(FULL_SHADER) as Shader
	if shader == null:
		push_error("FPVCamera: no se pudo cargar %s" % FULL_SHADER)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	for index: int in FACE_UNIFORMS.size():
		var viewport := _add_face(_face_basis(index), FULL_FACE_FOV, _built_size, false)
		_material.set_shader_parameter(FACE_UNIFORMS[index], viewport.get_texture())
	_composite.material = _material


## Crea una sub-viewport con su cámara mirando en la dirección de [param face] relativa
## a la FPV. La sub-cámara hereda la máscara de capas, el plano cercano y el lejano de
## la cámara principal (`docs/03` §5).
##
## Con [param is_side] la viewport es una cara lateral de FAST_WIDE y lleva el MSAA y
## el LOD recortados de `Graphics`, que es lo que hace que las dos caras extra cuesten
## una fracción de la frontal.
func _add_face(face: Basis, face_fov: float, size: Vector2i, is_side: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = false
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	viewport.msaa_3d = Graphics.fisheye_side_msaa_level() if is_side \
			else Graphics.fisheye_msaa_level()
	# Todo lo que en una viewport normal viene del proyecto hay que ponérselo a mano a
	# una `SubViewport`: acá es donde se dibuja la escena, así que acá van la escala de
	# render del preset, el umbral de LOD y la oclusión (`docs/13` §3.4).
	viewport.scaling_3d_mode = Graphics.fisheye_scaling_mode()
	viewport.scaling_3d_scale = Graphics.fisheye_render_scale()
	viewport.mesh_lod_threshold = Graphics.fisheye_side_mesh_lod() if is_side \
			else Graphics.mesh_lod_threshold()
	viewport.use_occlusion_culling = Graphics.use_occlusion_culling()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera := Camera3D.new()
	camera.name = "FaceCamera"
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = face_fov
	camera.near = NEAR_PLANE
	camera.far = FAR_PLANE
	camera.cull_mask = _scene_cull_mask
	viewport.add_child(camera)
	_render_root.add_child(viewport)
	camera.global_transform = Transform3D(global_basis.orthonormalized() * face, global_position)
	camera.make_current()
	_viewports.append(viewport)
	_sub_cameras.append(camera)
	_face_bases.append(face)
	_face_is_side.append(is_side)
	return viewport


## Mantiene al día el `Environment` barato de las caras laterales.
##
## ## Por qué las laterales no comparten el `Environment` del nivel
##
## Una `SubViewport` paga el **pipeline entero** cada cuadro, no sólo sus píxeles:
## medido en la batalla a 1080p con el preset HIGH, pasar de una viewport a tres
## llevó el ojo de pez de 3,09 ms a 7,23 ms, y bajar las laterales de 720² a 540²
## —44 % menos de píxeles— sólo lo dejó en 6,71 ms. El costo no está en el tamaño:
## está en que SDFGI, la niebla volumétrica y SSAO corren **una vez por viewport**.
##
## [member Camera3D.environment] permite darle a una cámara su propio `Environment`
## sin tocar el del mundo, así que las laterales corren con SDFGI, SSIL, SSAO y
## niebla volumétrica apagados y el resto —cielo, tonemap, niebla de profundidad,
## glow, ajustes de color— idéntico. Lo que se pierde es el rebote indirecto en la
## periferia, que es justo donde la proyección equidistante comprime más y donde el
## fundido de [constant EDGE_FADE] mezcla las dos caras.
##
## El clon se rehace solo cuando el nivel cambia de `Environment` —al cargar, y cada
## vez que `Graphics` reaplica la calidad—, comparando la referencia: es un puntero
## por cuadro, y evita tener que enganchar y desenganchar señales del nivel.
##
## ## Por qué las sub-cámaras **no** llevan `Camera3D.attributes`
##
## La exposición la define el `CameraAttributesPhysical` del `WorldEnvironment` del
## nivel (`docs/13`), y una sub-cámara con `environment` propio **igual lo hereda**:
## medido con `tools/environment_shots`, asignarlo o no no cambia la exposición del
## anillo exterior. No hace falta.
##
## Y asignarlo rompe el ojo de pez: `CameraAttributesPhysical` lleva
## `frustum_focal_length` —2,1 mm, para que la profundidad de campo no desenfoque las
## hélices— y al ponerlo en una [Camera3D] **le sobrescribe el `fov`**. Medido: las
## caras pasaban de 120° y 100° a **160,15°**, que es justo la geometría que el
## compuesto da por supuesta. No daría un error: daría una imagen mal proyectada, que
## es peor. La fila 1 de `tools/hud_projection_check` verifica el `fov` de cada
## sub-cámara para que esto no vuelva por la ventana.
func _refresh_side_environment() -> void:
	var world := get_world_3d()
	var source := world.environment if world != null else null
	if source == _source_environment:
		return
	_source_environment = source
	_side_environment = _build_side_environment(source)
	for index: int in _sub_cameras.size():
		var camera := _sub_cameras[index]
		if not is_instance_valid(camera):
			continue
		camera.environment = _side_environment if _face_is_side[index] else null


## El clon barato del `Environment` del nivel para las caras laterales, o `null`.
##
## Parte de un `duplicate()` del `Environment` **del nivel**, no de un
## `Environment.new()`: así el cielo, el tonemap, la niebla de profundidad, el glow y
## los ajustes de color son exactamente los mismos que ve la cara frontal, y lo único
## que cambia es lo que se apaga a propósito.
func _build_side_environment(source: Environment) -> Environment:
	if source == null:
		return null
	var cheap := source.duplicate() as Environment
	if cheap == null:
		return null
	cheap.sdfgi_enabled = false
	cheap.ssil_enabled = false
	cheap.ssao_enabled = false
	cheap.volumetric_fog_enabled = false
	return cheap



## Rotación de cada cara respecto de la FPV, en el orden de [enum Face]. Es la inversa
## de la que aplica el shader para llevar una dirección al espacio de la cara.
func _face_basis(index: int) -> Basis:
	match index:
		Face.RIGHT:
			return Basis(Vector3.UP, -PI * 0.5)
		Face.LEFT:
			return Basis(Vector3.UP, PI * 0.5)
		Face.UP:
			return Basis(Vector3.RIGHT, PI * 0.5)
		Face.DOWN:
			return Basis(Vector3.RIGHT, -PI * 0.5)
		_:
			return Basis.IDENTITY


## Tamaño de la sub-viewport principal: cuadrada en FULL —las caras de un cubo lo
## son— y con la relación de aspecto de la pantalla en FAST y FAST_WIDE, para que el
## remapeo del shader y [method project_direction] compartan la misma geometría. Las
## caras laterales de FAST_WIDE son cuadradas y miden `Graphics.fisheye_side_height()`.
func _target_viewport_size(mode: int, height: int) -> Vector2i:
	var side := maxi(height, MIN_VIEWPORT_SIDE)
	if mode != Graphics.FisheyeMode.FAST and mode != Graphics.FisheyeMode.FAST_WIDE:
		return Vector2i(side, side)
	var screen := _screen_size()
	var width := int(roundf(side * maxf(screen.x / maxf(screen.y, 1.0), 0.1)))
	return Vector2i(maxi(width, MIN_VIEWPORT_SIDE), side)


## Acota el FOV según el modo y decide quién dibuja la escena: la cámara en OFF, las
## sub-cámaras con ojo de pez.
func _apply_fov() -> void:
	keep_aspect = KEEP_WIDTH
	near = NEAR_PLANE
	far = FAR_PLANE
	match _mode:
		Graphics.FisheyeMode.FAST, Graphics.FisheyeMode.FAST_WIDE:
			_hfov = clampf(_requested_fov, FISHEYE_FOV_RANGE.x, FISHEYE_FOV_RANGE.y)
			fov = FAST_RENDER_FOV
			cull_mask = 0
		Graphics.FisheyeMode.FULL:
			_hfov = clampf(_requested_fov, FISHEYE_FOV_RANGE.x, FISHEYE_FOV_RANGE.y)
			fov = FULL_FACE_FOV
			cull_mask = 0
		_:
			_hfov = 0.0
			fov = clampf(_requested_fov, RECTILINEAR_FOV_RANGE.x, RECTILINEAR_FOV_RANGE.y)
			cull_mask = _scene_cull_mask
	for camera: Camera3D in _sub_cameras:
		if is_instance_valid(camera):
			camera.cull_mask = _scene_cull_mask


## Vuelca en el shader el campo, los dos aspectos, el FOV del render y los anchos de
## transición. `aspect` es el del rectángulo de salida y `front_aspect` el de la
## sub-viewport frontal: difieren por el redondeo a píxeles enteros del alto del
## preset, y confundirlos inclina el campo unas décimas de grado.
func _update_uniforms() -> void:
	if _material == null:
		return
	var screen := _screen_size()
	_material.set_shader_parameter("hfov", _hfov)
	_material.set_shader_parameter("aspect", screen.x / maxf(screen.y, 1.0))
	if _mode == Graphics.FisheyeMode.FULL:
		_material.set_shader_parameter("face_fov", FULL_FACE_FOV)
		_material.set_shader_parameter("edge_fade", FULL_EDGE_FADE)
		return
	_material.set_shader_parameter("render_fov", FAST_RENDER_FOV)
	_material.set_shader_parameter("front_aspect", _front_aspect())
	_material.set_shader_parameter("use_sides", _mode == Graphics.FisheyeMode.FAST_WIDE)
	_material.set_shader_parameter("side_fov", SIDE_FACE_FOV)
	_material.set_shader_parameter("side_yaw", SIDE_FACE_YAW)
	_material.set_shader_parameter("edge_fade", EDGE_FADE)
	_material.set_shader_parameter("edge_fade_y", EDGE_FADE_Y)


## El compuesto se ve solo si hay ojo de pez y esta cámara es la activa; si no, las
## sub-viewports dejan de renderizar. En `--headless` no hay rasterizado: se dejan
## apagadas y la matemática de [method project_direction] sigue valiendo igual.
func _update_composite_state() -> void:
	if not is_instance_valid(_composite):
		return
	var active := is_fisheye_active() and is_inside_tree() and is_current()
	if _composite.visible != active:
		_composite.visible = active
	var wanted := SubViewport.UPDATE_ALWAYS if active and not Graphics.is_headless() \
			else SubViewport.UPDATE_DISABLED
	for viewport: SubViewport in _viewports:
		if is_instance_valid(viewport) and viewport.render_target_update_mode != wanted:
			viewport.render_target_update_mode = wanted
	# La escena se dibuja en las sub-viewports; la raíz sólo compone. Apagarle el 3D
	# mientras dura el compuesto ahorra el cuadro entero que dibujaba para nada.
	var root := get_viewport()
	if root != null and root.disable_3d != active:
		root.disable_3d = active


func _on_fisheye_changed() -> void:
	_apply_graphics()


## Obliga a rederivar el `Environment` barato de las caras laterales en el próximo
## cuadro: el del nivel acaba de cambiar sin cambiar de objeto.
func _on_environment_quality_changed() -> void:
	_source_environment = null


func _on_quad_settings_updated() -> void:
	set_horizontal_fov(QuadSettings.fov)


func _on_screen_resized() -> void:
	var size := _target_viewport_size(_mode, _built_height)
	if size != _built_size:
		_built_size = size
		# Las caras laterales de FAST_WIDE son cuadradas y no dependen del aspecto de
		# la pantalla: redimensionarlas acá las dejaría rectangulares y el shader las
		# muestrearía con la geometría equivocada.
		for index: int in _viewports.size():
			var viewport := _viewports[index]
			if is_instance_valid(viewport) and not _face_is_side[index]:
				viewport.size = size
	_update_uniforms()
