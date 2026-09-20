## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Base común de los niveles jugables (`docs/04` §4.9, `docs/11` §3.1 y §3.2).
##
## Un nivel es lo único que sabe tres cosas que ni el dron ni la interfaz pueden saber
## solos: dónde se reaparece, qué cámaras hay para mirar la escena y cuándo el jugador
## quiere pausar. Esta clase resuelve esas tres y nada más; el contenido —terreno,
## distrito, enemigos, objetivos— lo pone cada nivel concreto.
##
## Contratos que implementa:
## - **Precalentamiento** (`docs/11` §3.1): [signal view_warmed_up] y [method warm_up_view].
##   `SceneTransition.change_scene(path, true)` mantiene el fundido hasta que el nivel
##   avisa que ya compiló los shaders de lo que se va a ver.
## - **Pausa** (`docs/04` §4.9): [method add_pause_menu] instancia `gui/pause_menu.tscn`,
##   pone el árbol en pausa y escucha sus dos señales. El menú **no** es dueño de la
##   pausa: acá se decide cuándo es seguro despausar, con [method _resume_input_held],
##   para que mantener apretado el botón que abrió la pausa no la cierre en el acto.
## - **Cámaras** (`docs/03` §5): [member cameras] junta las cámaras del nivel y la FPV
##   del rig si ya existe, y la acción `change_camera` las cicla. El `FlightHUD` del rig
##   (`docs/12` §1.1) se esconde mientras la cámara activa no sea la FPV: es la vista
##   del piloto, y dibujarla sobre la cámara de seguimiento sería una mira que no apunta
##   a nada y un horizonte que no es el que se ve (WP-08).
##
## `process_mode` es `PROCESS_MODE_PAUSABLE`: al pausar se detienen el dron, la física
## y todo lo que cuelgue del nivel. El menú de pausa se declara `WHEN_PAUSED` y por eso
## sigue vivo (`docs/11` §3.2).
class_name LevelBase
extends Node3D

## El nivel ya dibujó lo suficiente como para revelarlo sin tirones (`docs/11` §3.1).
signal view_warmed_up

## Menú de pausa del juego.
const PAUSE_MENU_SCENE: String = "res://gui/pause_menu.tscn"

## Destino de `MENU_MAIN` (`docs/04` §4.9).
const MAIN_MENU_SCENE: String = "res://gui/main_menu.tscn"

## Cuadros dibujados por cámara durante el precalentamiento (`docs/11` §3.1).
const WARMUP_FRAMES: int = 3

## Nombre convencional del sol del nivel. Es el que [method _register_sun] le pasa
## a `Graphics` para que le aplique la tabla de sombras del preset.
const SUN_NODE: NodePath = ^"Sun"

## Nombre convencional del `WorldEnvironment` del nivel.
const WORLD_ENVIRONMENT_NODE: NodePath = ^"WorldEnvironment"

## Respaldo de [method _resume_input_held]: si la entrada de pausa sigue apretada
## después de este tiempo, se despausa igual. Evita quedarse trabado si el jugador
## suelta el mando o si la acción quedó pegada.
const RESUME_RELEASE_TIMEOUT: float = 0.35

## Punto de reaparición del dron. Lo consume el rig (`docs/03` §8).
@export var respawn_point: Node3D

## Cámara fija sobre la ciudad a la que se pasa mientras el dron se reconstruye
## (`docs/09` §2.8). Si queda vacía, [method get_respawn_camera] la deduce.
@export var respawn_camera: Camera3D

## Conjunto jugable del dron, si el nivel tiene uno.
@export var drone_rig: Node3D

## Cámaras que cicla la acción `change_camera`, en orden. La FPV del rig, si existe,
## va primera porque es la vista de juego.
var cameras: Array[Camera3D] = []

var _camera_index: int = 0

## La FPV del rig, si la hay. La memoriza [method collect_cameras] para no tener que
## volver a buscarla en cada cambio de cámara.
var _fpv_camera: Camera3D = null

var _pause_menu: PauseMenu = null
var _paused_by_us: bool = false
var _warmed: bool = false
var _warming: bool = false
var _warmups: int = 0
var _previous_sticks_suspended: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Antes que nada: el `Environment` propio y el sol dado de alta. Las subclases
	# llaman a `Graphics.apply_environment_quality()` justo después de `super()`,
	# así que para entonces el clon ya tiene que estar puesto.
	_clone_environment()
	_register_sun()
	# Mientras se vuela, los sticks pilotan: no navegan menús. El menú de pausa los
	# devuelve a la navegación (`docs/04` §4.9).
	_previous_sticks_suspended = StickNavigation.suspended
	StickNavigation.suspended = true
	_wire_respawn_point()
	collect_cameras()
	_apply_camera()


func _exit_tree() -> void:
	StickNavigation.suspended = _previous_sticks_suspended
	if _paused_by_us and get_tree() != null:
		get_tree().paused = false
		_paused_by_us = false
	# Si el nivel se libera en medio de un `await` de `warm_up_view()`, la corrutina muere
	# ahí y [signal view_warmed_up] no se emitiría nunca: `SceneTransition._warm_up()` se
	# quedaría esperando y el fundido colgado. Se emite acá para cerrar el contrato de
	# `docs/11` §3.1 aunque el precalentamiento no haya llegado al final.
	if _warming:
		_warming = false
		view_warmed_up.emit()


func _unhandled_input(event: InputEvent) -> void:
	if UI.has_modal() or SceneTransition.is_busy():
		return
	if event.is_action_pressed(&"pause_menu", false, true):
		get_viewport().set_input_as_handled()
		var _menu := add_pause_menu()
		return
	if event.is_action_pressed(&"change_camera", false, true):
		get_viewport().set_input_as_handled()
		change_camera()


# --- Render del nivel (WP-24a) ---------------------------------------------------------------

## Reemplaza el `Environment` del `WorldEnvironment` por una **copia propia** del
## nivel.
##
## `world/environment_battle.tres` lo comparten el nivel de batalla, el de vuelo
## libre y los dos showcases. `Graphics.apply_environment_quality()` escribe sobre
## él —SDFGI, SSAO, niebla, ambiente de respaldo— y, como los recursos viven en la
## caché mientras alguien los referencie, esas escrituras sobrevivían al nivel: un
## check que corriera en LOW dejaba el `.tres` con SDFGI apagado para el que
## corriera después, y el editor se encontraba el recurso mutado. Con un clon por
## nivel cada uno escribe el suyo.
##
## La copia es superficial a propósito: el `Sky` y su material son de sólo lectura
## para el preset, y duplicarlos obligaría a recalcular la radiancia por nivel.
##
## Devuelve el clon, o `null` si el nivel no tiene `WorldEnvironment`.
func _clone_environment() -> Environment:
	var world := get_node_or_null(WORLD_ENVIRONMENT_NODE) as WorldEnvironment
	if world == null or world.environment == null:
		return null
	var clone := world.environment.duplicate(false) as Environment
	if clone == null:
		return null
	clone.resource_local_to_scene = true
	world.environment = clone
	return clone


## Da de alta el sol del nivel en `Graphics`, que le aplica la tabla de sombras del
## preset y se lo vuelve a aplicar cada vez que el jugador cambie de calidad
## (`docs/13` §3.4).
##
## Las escenas traían el alcance, las cascadas y los sesgos cableados —700 m y
## cuatro splits en `battle_level.tscn`—, así que el preset no llegaba a la luz. Lo
## busca por el nombre convencional `Sun` y, si no está, se queda con la primera
## `DirectionalLight3D` del nivel.
##
## Devuelve el sol registrado, o `null` si el nivel no tiene ninguna luz direccional.
func _register_sun() -> DirectionalLight3D:
	var sun := get_node_or_null(SUN_NODE) as DirectionalLight3D
	if sun == null:
		for node: Node in find_children("*", "DirectionalLight3D", true, false):
			sun = node as DirectionalLight3D
			if sun != null:
				break
	if sun == null:
		return null
	Graphics.register_sun(sun)
	return sun


# --- Precalentamiento ------------------------------------------------------------------------

## Dibuja unos cuadros con cada cámara para compilar los shaders y emite
## [signal view_warmed_up] (`docs/11` §3.1).
##
## Siempre cede al menos un cuadro antes de emitir: `SceneTransition` llama a este
## método y **después** se pone a esperar la señal, así que emitirla de forma síncrona
## dejaría el fundido colgado para siempre.
##
## Mientras dura, [member _warming] queda en `true`: si el nivel se libera antes de
## terminar, [method _exit_tree] emite la señal igual.
func warm_up_view() -> void:
	_warming = true
	var original := _camera_index
	for index: int in cameras.size():
		_camera_index = index
		_apply_camera()
		await _next_draw()
	_camera_index = original
	_apply_camera()
	var camera := active_camera()
	var base_rotation := camera.rotation if camera != null else Vector3.ZERO
	for step: int in WARMUP_FRAMES:
		if camera != null:
			camera.rotation.y = base_rotation.y + TAU * float(step + 1) / float(WARMUP_FRAMES)
		await _next_draw()
	if camera != null:
		camera.rotation = base_rotation
	await _next_draw()
	_warmed = true
	_warming = false
	_warmups += 1
	view_warmed_up.emit()


## Verdadero cuando [method warm_up_view] ya terminó al menos una vez.
func is_warmed_up() -> bool:
	return _warmed


## Cuántas veces terminó el precalentamiento. Lo mira `tools/loading_check.gd`.
func warm_up_count() -> int:
	return _warmups


## Espera a que el cuadro llegue a pantalla. En `--headless` no hay ventana que dibujar
## y `RenderingServer.frame_post_draw` nunca se emite, así que ahí alcanza con ceder un
## cuadro de proceso (misma nota que `autoloads/scene_transition.gd`).
func _next_draw() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw


# --- Pausa -----------------------------------------------------------------------------------

## Instancia el menú de pausa, pausa el árbol y devuelve la navegación por sticks a los
## menús. Devuelve el menú vivo, o `null` si no se pudo abrir.
func add_pause_menu() -> PauseMenu:
	if is_instance_valid(_pause_menu):
		return _pause_menu
	var packed: PackedScene = null
	if ResourceLoader.exists(PAUSE_MENU_SCENE):
		packed = load(PAUSE_MENU_SCENE) as PackedScene
	if packed == null:
		push_error("LevelBase: no se pudo cargar %s" % PAUSE_MENU_SCENE)
		return null
	var menu := packed.instantiate() as PauseMenu
	if menu == null:
		push_error("LevelBase: %s no instancia un PauseMenu" % PAUSE_MENU_SCENE)
		return null
	_pause_menu = menu
	add_child(menu)
	get_tree().paused = true
	_paused_by_us = true
	StickNavigation.suspended = false
	var _discard := menu.resumed.connect(_on_resume)
	_discard = menu.menu.connect(_on_menu)
	return menu


## El menú de pausa abierto, o `null` si el juego no está en pausa.
func pause_menu() -> PauseMenu:
	return _pause_menu if is_instance_valid(_pause_menu) else null


## Verdadero mientras este nivel mantiene el árbol en pausa.
func is_paused() -> bool:
	return _paused_by_us


## `MENU_RESUME` o `ui_cancel`: se despausa recién cuando la entrada que abrió el menú
## deja de estar apretada, para que mantener el botón no reanude sin querer.
func _on_resume() -> void:
	await _resume_input_held()
	_close_pause_menu()
	if get_tree() == null:
		return
	get_tree().paused = false
	_paused_by_us = false
	StickNavigation.suspended = true


## `MENU_MAIN`, ya confirmado por el menú: despausa y vuelve al menú principal.
func _on_menu() -> void:
	_close_pause_menu()
	if get_tree() != null:
		get_tree().paused = false
	_paused_by_us = false
	StickNavigation.suspended = _previous_sticks_suspended
	SceneTransition.change_scene(MAIN_MENU_SCENE)


## Espera a que se suelten `pause_menu` y `ui_accept`, con un respaldo de
## [constant RESUME_RELEASE_TIMEOUT] segundos.
func _resume_input_held() -> void:
	var deadline := Time.get_ticks_msec() + int(RESUME_RELEASE_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not Input.is_action_pressed(&"pause_menu") \
				and not Input.is_action_pressed(&"ui_accept"):
			return
		await get_tree().process_frame


func _close_pause_menu() -> void:
	if not is_instance_valid(_pause_menu):
		_pause_menu = null
		return
	_pause_menu.queue_free()
	_pause_menu = null


# --- Cámaras ---------------------------------------------------------------------------------

## Junta las cámaras que cicla `change_camera`: primero la FPV del rig —si WP-06 ya la
## entregó, la reconoce por el método `get_fpv_camera()` o por el grupo `fpv_camera`— y
## después las del propio nivel, en orden de árbol.
func collect_cameras() -> void:
	cameras.clear()
	var fpv := _find_fpv_camera()
	_fpv_camera = fpv
	if fpv != null:
		cameras.append(fpv)
	for node: Node in find_children("*", "Camera3D", true, false):
		var camera := node as Camera3D
		if camera == null or cameras.has(camera):
			continue
		if drone_rig != null and drone_rig.is_ancestor_of(camera):
			continue
		cameras.append(camera)
	for index: int in cameras.size():
		if cameras[index].current:
			_camera_index = index
			break


## La cámara activa, o `null` si el nivel no tiene ninguna.
func active_camera() -> Camera3D:
	if cameras.is_empty():
		return null
	return cameras[clampi(_camera_index, 0, cameras.size() - 1)]


## Índice de la cámara activa dentro de [member cameras].
func camera_index() -> int:
	return _camera_index


## Pasa a la cámara siguiente (`docs/03` §5). Con una sola cámara no hace nada.
func change_camera() -> void:
	if cameras.size() < 2:
		return
	_camera_index = (_camera_index + 1) % cameras.size()
	_apply_camera()


## Hace activa [param camera] y **sincroniza el índice del ciclo**, para que
## `change_camera` siga desde ahí y para que [method _update_flight_hud] acierte.
##
## Lo necesita WP-21: `RoundManager` mueve la cámara por su cuenta al entrar en
## `INTRO`, al empezar la batalla y al reaparecer el dron. Poner `current = true`
## a mano funcionaría para la imagen, pero dejaría a [member _camera_index]
## apuntando a otra cámara y el `FlightHUD` se dibujaría sobre una vista que no es
## la del piloto. Devuelve `false` si la cámara no es una de las del nivel.
func focus_camera(camera: Camera3D) -> bool:
	if camera == null or not is_instance_valid(camera):
		return false
	var index := cameras.find(camera)
	if index < 0:
		return false
	_camera_index = index
	_apply_camera()
	return true


## La cámara FPV del rig, o `null` si el nivel no tiene dron. La memoriza
## [method collect_cameras].
func get_fpv_camera() -> Camera3D:
	return _fpv_camera


func _apply_camera() -> void:
	var camera := active_camera()
	if camera != null:
		camera.current = true
	_update_flight_hud()


## El `FlightHUD` es la vista del piloto y solo vale sobre la imagen de la FPV
## (`docs/03` §5, `docs/12` §1.1): con cualquier otra cámara activa se esconde.
##
## Es lo mínimo que WP-08 agrega a esta clase. No se cachea el HUD: el rig puede
## reconstruirlo al reaparecer el dron (`docs/12` §1.1) y una referencia vieja apuntaría
## a un nodo liberado.
func _update_flight_hud() -> void:
	if drone_rig == null or not drone_rig.has_method(&"get_flight_hud"):
		return
	var hud := drone_rig.call(&"get_flight_hud") as Control
	if hud == null or not is_instance_valid(hud):
		return
	hud.visible = _fpv_camera != null and active_camera() == _fpv_camera


## Gancho mínimo de WP-15 (`docs/09` §2.8): la cámara desde la que se mira la
## ciudad mientras el dron está destruido.
##
## `RespawnController` lo busca hacia arriba por `has_method`, así que un nivel que
## no lo herede —o que devuelva `null`— simplemente deja la cámara como estaba; no
## hay nada obligatorio acá. El orden de preferencia es: [member respawn_camera] si
## el nivel la cableó, después `Cameras/CameraFixed` por convención de escena, y en
## última instancia la primera cámara del nivel que no sea la FPV, porque mirar la
## reconstrucción desde la cabina de un dron destruido no tendría sentido.
func get_respawn_camera() -> Camera3D:
	if respawn_camera != null and is_instance_valid(respawn_camera):
		return respawn_camera
	var fixed := get_node_or_null(^"Cameras/CameraFixed") as Camera3D
	if fixed != null:
		return fixed
	for camera: Camera3D in cameras:
		if camera != null and camera != _fpv_camera:
			return camera
	return null


func _find_fpv_camera() -> Camera3D:
	if drone_rig == null:
		return null
	if drone_rig.has_method(&"get_fpv_camera"):
		return drone_rig.call(&"get_fpv_camera") as Camera3D
	for node: Node in get_tree().get_nodes_in_group(&"fpv_camera"):
		var camera := node as Camera3D
		if camera != null and drone_rig.is_ancestor_of(camera):
			return camera
	return null


# --- Reaparición -----------------------------------------------------------------------------

## Le pasa al rig el punto de reaparición del nivel, por si la escena no lo cableó.
func _wire_respawn_point() -> void:
	if drone_rig == null or respawn_point == null:
		return
	if drone_rig.get(&"respawn_point") == null:
		drone_rig.set(&"respawn_point", respawn_point)
	if not drone_rig.has_method(&"get_drone"):
		return
	var drone := drone_rig.call(&"get_drone") as Node3D
	if drone != null and drone.get(&"respawn_point") == null:
		drone.set(&"respawn_point", respawn_point)
