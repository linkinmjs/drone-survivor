## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Cámara FPV del dron con ojo de pez en tres modos (`docs/03` §5).
##
## Es la vista principal del juego: cuelga del [CameraRig] con transformada identidad
## —el rig es quien la inclina y quien la sacudirá en WP-28— y se hace `current` al
## entrar al árbol, así que al cargar un nivel se ve por los ojos del piloto.
##
## ## Los tres modos (`Graphics.fisheye_mode`)
##
## - **OFF**: una [Camera3D] común. El FOV horizontal se acota a 60–120° con
##   `keep_aspect = KEEP_WIDTH`, porque una proyección rectilínea más ancha que eso
##   estira los bordes hasta lo grotesco.
## - **FAST**: una `SubViewport` con un render rectilíneo de 120° y un `ColorRect` de
##   pantalla completa que lo remapea a proyección equidistante
##   (`drone/fpv_camera/fisheye_fast.gdshader`). Una viewport extra.
## - **FULL**: cinco `SubViewport` cuadradas —frente, derecha, izquierda, arriba y
##   abajo— con cámaras de 100° solapadas, compuestas eligiendo la cara por eje
##   dominante (`drone/fpv_camera/fisheye_full.gdshader`). Sin estiramiento, pero
##   multiplica los draw calls por cinco: FAST es el modo por defecto del juego.
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

## Shader del modo FAST.
const FAST_SHADER: String = "res://drone/fpv_camera/fisheye_fast.gdshader"

## Shader del modo FULL.
const FULL_SHADER: String = "res://drone/fpv_camera/fisheye_full.gdshader"

## Nombre del uniform de cada cara de FULL, en el orden de [enum Face].
const FACE_UNIFORMS: Array[String] = [
	"face_front", "face_right", "face_left", "face_up", "face_down",
]

## Tamaño de pantalla que se asume cuando la cámara todavía no tiene viewport.
const FALLBACK_SCREEN: Vector2 = Vector2(1920.0, 1080.0)

## Resultado de [method project_direction] para una dirección fuera del campo visual.
const OUT_OF_FIELD: Vector2 = Vector2(NAN, NAN)

## Radio por debajo del cual una dirección se considera centrada y no hay azimut que
## calcular, en medias-anchuras de pantalla.
const RADIUS_EPSILON: float = 1e-6

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

## Tamaño con el que se construyeron las sub-viewports, en píxeles.
var _built_size: Vector2i = Vector2i.ZERO

var _layer: CanvasLayer = null
var _composite: ColorRect = null
var _render_root: Node = null
var _material: ShaderMaterial = null
var _viewports: Array[SubViewport] = []
var _sub_cameras: Array[Camera3D] = []
var _face_bases: Array[Basis] = []


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
	_discard = QuadSettings.settings_updated.connect(_on_quad_settings_updated)
	var viewport := get_viewport()
	if viewport != null:
		_discard = viewport.size_changed.connect(_on_screen_resized)


func _exit_tree() -> void:
	if Graphics.fisheye_changed.is_connected(_on_fisheye_changed):
		Graphics.fisheye_changed.disconnect(_on_fisheye_changed)
	if QuadSettings.settings_updated.is_connected(_on_quad_settings_updated):
		QuadSettings.settings_updated.disconnect(_on_quad_settings_updated)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_screen_resized):
		viewport.size_changed.disconnect(_on_screen_resized)


func _process(_delta: float) -> void:
	_update_composite_state()
	if _sub_cameras.is_empty():
		return
	var facing := global_basis.orthonormalized()
	var origin := global_position
	for index: int in _sub_cameras.size():
		var camera := _sub_cameras[index]
		if is_instance_valid(camera):
			camera.global_transform = Transform3D(facing * _face_bases[index], origin)


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
	var built := not _viewports.is_empty()
	var needs_viewports := wanted != Graphics.FisheyeMode.OFF
	if wanted == _mode and height == _built_height and msaa == _built_msaa \
			and size == _built_size and built == needs_viewports:
		_apply_fov()
		_update_uniforms()
		return
	_mode = wanted
	_built_height = height
	_built_msaa = msaa
	_built_size = size
	_rebuild()


## Dirección en el mundo → píxel de la viewport raíz, o `Vector2(NAN, NAN)` si la
## dirección cae fuera del campo visual (`docs/03` §5).
##
## OFF usa la proyección rectilínea de la propia cámara; FAST desproyecta sobre el
## render rectilíneo y remapea el radio igual que el shader, pero al revés; FULL lo
## resuelve analíticamente, porque ahí no hay una sola matriz de proyección que valga.
## Los tres devuelven el centro exacto para la dirección `−basis.z`.
func project_direction(dir: Vector3) -> Vector2:
	if not is_inside_tree() or not dir.is_finite() or dir.length_squared() <= 0.0:
		return OUT_OF_FIELD
	var unit := dir.normalized()
	if _mode == Graphics.FisheyeMode.FAST:
		return _project_fast(unit)
	if _mode == Graphics.FisheyeMode.FULL:
		return _project_equidistant(unit, _hfov)
	return _project_rectilinear(unit)


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


## Las sub-viewports vivas: una en FAST, cinco en FULL, ninguna en OFF.
func get_fisheye_viewports() -> Array[SubViewport]:
	return _viewports.duplicate()


# --- Proyección ------------------------------------------------------------------------------

## Proyección rectilínea: la de la propia [Camera3D], con la guarda de «detrás».
func _project_rectilinear(unit: Vector3) -> Vector2:
	var point := global_position + unit
	if is_position_behind(point):
		return OUT_OF_FIELD
	var projected := unproject_position(point)
	return projected if projected.is_finite() else OUT_OF_FIELD


## Proyección FAST: desproyecta sobre el render rectilíneo de 120° y remapea el radio.
##
## El radio de salida es `θ / (hfov/2)` en medias-anchuras, con `θ` deducido del radio
## rectilíneo `rs` como `atan(rs · tan(fov/2))`. Es exactamente la inversa de lo que
## hace el shader, así que el píxel que devuelve esta función es el píxel donde se ve
## la cosa.
func _project_fast(unit: Vector3) -> Vector2:
	var half_field := deg_to_rad(_hfov) * 0.5
	if half_field <= 0.0 or _angle_to_axis(unit) > half_field:
		return OUT_OF_FIELD
	var point := global_position + unit
	if is_position_behind(point):
		return OUT_OF_FIELD
	var centre := _screen_centre()
	var half_width := maxf(centre.x, 1.0)
	var offset := unproject_position(point) - centre
	if not offset.is_finite():
		return OUT_OF_FIELD
	var source_radius := offset.length() / half_width
	if source_radius <= RADIUS_EPSILON:
		return centre
	var theta := atan(source_radius * tan(deg_to_rad(fov) * 0.5))
	return centre + offset.normalized() * (theta / half_field * half_width)


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


## Ángulo entre [param unit] y el eje óptico (−Z de la cámara), en radianes.
func _angle_to_axis(unit: Vector3) -> float:
	var forward := -global_basis.orthonormalized().z
	return acos(clampf(forward.dot(unit), -1.0, 1.0))


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


## Rehace las sub-viewports del modo actual. Es la única función que crea o destruye
## nodos de render: por eso un cambio de modo en caliente no puede dejar fugas.
func _rebuild() -> void:
	_clear_viewports()
	match _mode:
		Graphics.FisheyeMode.FAST:
			_build_fast()
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
	if is_instance_valid(_composite):
		_composite.material = null
	_material = null


## FAST: una sub-viewport rectilínea con la relación de aspecto de la pantalla.
func _build_fast() -> void:
	var shader := load(FAST_SHADER) as Shader
	if shader == null:
		push_error("FPVCamera: no se pudo cargar %s" % FAST_SHADER)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	var viewport := _add_face(Basis.IDENTITY, FAST_RENDER_FOV, _built_size)
	_material.set_shader_parameter("source_texture", viewport.get_texture())
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
		var viewport := _add_face(_face_basis(index), FULL_FACE_FOV, _built_size)
		_material.set_shader_parameter(FACE_UNIFORMS[index], viewport.get_texture())
	_composite.material = _material


## Crea una sub-viewport con su cámara mirando en la dirección de [param face] relativa
## a la FPV. La sub-cámara hereda la máscara de capas, el plano cercano y el lejano de
## la cámara principal (`docs/03` §5).
func _add_face(face: Basis, face_fov: float, size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = false
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	viewport.msaa_3d = Graphics.fisheye_msaa_level()
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
	return viewport


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


## Tamaño de cada sub-viewport: cuadrada en FULL —las caras de un cubo lo son— y con la
## relación de aspecto de la pantalla en FAST, para que el remapeo del shader y
## [method project_direction] compartan la misma geometría.
func _target_viewport_size(mode: int, height: int) -> Vector2i:
	var side := maxi(height, MIN_VIEWPORT_SIDE)
	if mode != Graphics.FisheyeMode.FAST:
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
		Graphics.FisheyeMode.FAST:
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


## Vuelca en el shader el campo, el aspecto y el FOV del render.
func _update_uniforms() -> void:
	if _material == null:
		return
	var screen := _screen_size()
	_material.set_shader_parameter("hfov", _hfov)
	_material.set_shader_parameter("aspect", screen.x / maxf(screen.y, 1.0))
	if _mode == Graphics.FisheyeMode.FAST:
		_material.set_shader_parameter("render_fov", FAST_RENDER_FOV)
	else:
		_material.set_shader_parameter("face_fov", FULL_FACE_FOV)


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


func _on_fisheye_changed() -> void:
	_apply_graphics()


func _on_quad_settings_updated() -> void:
	set_horizontal_fov(QuadSettings.fov)


func _on_screen_resized() -> void:
	var size := _target_viewport_size(_mode, _built_height)
	if size != _built_size:
		_built_size = size
		for viewport: SubViewport in _viewports:
			if is_instance_valid(viewport):
				viewport.size = size
	_update_uniforms()
