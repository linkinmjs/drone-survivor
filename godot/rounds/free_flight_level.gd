## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Nivel de vuelo libre (WP-11).
##
## Es el terreno de juego del checkpoint 2: una llanura de 800 × 800 m con unos pocos
## pilares de referencia, el dron, el punto de reaparición y dos cámaras externas para
## poder verlo mientras WP-06 no entregue la FPV. No hay ciudad, ni enemigos, ni
## objetivos: eso es del nivel de batalla de WP-21.
##
## Toda la lógica —pausa, contrato de precalentamiento, ciclo de cámaras, reaparición—
## la pone [LevelBase]. Lo propio es aplicar al `Environment` compartido la calidad
## elegida en el menú de gráficos (`docs/04` §3.5) y hospedar los dos pools del arma.
##
## **Pools del arma (WP-14, `docs/08` §2.6)**: `ProjectilePool` e `ImpactFXPool` son
## nodos del nivel, no del dron, porque los proyectiles en vuelo tienen que sobrevivir
## al respawn. El `WeaponMount` los encuentra por grupo; el nivel sólo los hospeda.
## Los tres bloques de `Targets/` son [FreeFlightTarget]: capa 8 y
## `take_damage(amount, point)`, lo mínimo que el resolvedor de impactos pide por duck
## typing hasta que WP-20 entregue el `Building` de verdad.
##
## **Pilas (WP-15, `docs/09` §2.5)**: `BatterySpawner` con ocho `Marker3D` repartidos
## entre 31 y 124 m del punto de reaparición, de los que mantiene cinco activos. El
## nivel no lo cablea: el spawner encuentra la batería del dron por el árbol y la
## `LevelBase` ya expone `get_respawn_camera()` para la vista de reconstrucción.
class_name FreeFlightLevel
extends LevelBase

## Argumento de usuario que enciende la demo de disparo. Es sólo para la captura de
## Movie Maker de WP-14: no hay forma de llegar a él desde el juego.
const DEMO_ARG: String = "weapon-demo"

## Argumento que deja la demo en la vista **FPV** en vez de la cámara lateral.
## Sirve para capturar lo que ve el piloto: destello de boca, impactos y marcas.
const DEMO_FPV_ARG: String = "weapon-demo-fpv"

## Acelerador con el que la demo mantiene el dron a flote.
##
## El comando de equilibrio medido en `flight_bench` es 0.395 (`docs/03`, nota de la
## pasada de correcciones), pero disparando hay que sostener también la componente
## vertical del retroceso: con la cámara a 25°, cada disparo empuja 1.29·sin 25° =
## 0.55 m/s hacia abajo, o sea 4.4 m/s² a 8 disparos/s. El acelerador que compensa
## los 14.2 m/s² resultantes es `0.395 · sqrt(14.2 / 9.81)` ≈ 0.48; se usa 0.50 para
## que además suba un poco y la captura no termine en el suelo.
const DEMO_HOVER_THROTTLE: float = 0.50

## Ticks que la demo espera antes de armar, para que el rig termine de cablearse.
const DEMO_ARM_DELAY: int = 10

## Posición de la cámara de la demo, en metros.
##
## Va **de costado** al corredor de fuego a propósito. En la vista FPV los
## trazadores se alejan a lo largo del eje de la cámara, así que un segmento de 6 m
## se escorza hasta ser un punto: para verlos hay que mirarlos de perfil.
const DEMO_CAMERA_POSITION: Vector3 = Vector3(24.0, 9.0, -12.0)

## Punto al que mira la cámara de la demo: el medio del corredor de fuego.
const DEMO_CAMERA_TARGET: Vector3 = Vector3(0.0, 13.0, -24.0)

# --- Demo de energía (WP-15) ------------------------------------------------------------------

## Argumento de usuario que enciende la demo de energía y respawn. Igual que la de
## disparo, sólo existe para la captura de Movie Maker.
const ENERGY_DEMO_ARG: String = "energy-demo"

## Marcador de pila que la demo enseña de cerca.
const ENERGY_DEMO_MARKER: int = 0

## Dónde se para el dron respecto de la pila, en metros. A 5.7 m queda fuera del
## radio de recogida (3.5 m) y entra entero en el cuadro.
const ENERGY_DEMO_DRONE_OFFSET: Vector3 = Vector3(-4.0, 0.0, 4.0)

## Dónde se pone la cámara de la demo respecto de la pila, en metros.
const ENERGY_DEMO_CAMERA_OFFSET: Vector3 = Vector3(3.0, 1.6, 7.5)

## Adónde mira la cámara de la demo respecto de la pila, en metros: un punto entre
## la pila y el dron.
const ENERGY_DEMO_LOOK_OFFSET: Vector3 = Vector3(-2.0, 0.3, 2.0)

## Energía con la que arranca la demo, para que la pila se note al recogerse.
const ENERGY_DEMO_START_ENERGY: float = 45.0

## Segundo en el que el dron entra en la pila y la recoge.
const ENERGY_DEMO_COLLECT_SECONDS: float = 3.0

## Segundo en el que la demo destruye el dron para enseñar el ciclo de respawn.
const ENERGY_DEMO_KILL_SECONDS: float = 5.5

## Dónde se muda la cámara al reaparecer el dron, respecto del punto de
## reaparición, en metros.
const ENERGY_DEMO_RESPAWN_CAMERA_OFFSET: Vector3 = Vector3(2.4, 1.1, 4.0)

## Cada cuántos segundos la demo imprime el estado. Sin `CombatHUD` (WP-22) la
## consola es la única lectura de energía y casco que hay.
const ENERGY_DEMO_REPORT_SECONDS: float = 1.0

@onready var _world_environment: WorldEnvironment = $WorldEnvironment

var _demo_active: bool = false
var _demo_ticks: int = 0
var _demo_command: FlightCommand = FlightCommand.new()
var _demo_camera: Camera3D = null

var _energy_demo_active: bool = false
var _energy_demo_time: float = 0.0
var _energy_demo_report: float = 0.0
var _energy_demo_killed: bool = false
var _energy_demo_camera: Camera3D = null
var _energy_demo_placed: bool = false
var _energy_demo_collected: bool = false
var _energy_demo_anchor: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	_apply_environment_quality()
	var _discard := Graphics.environment_quality_changed.connect(_apply_environment_quality)
	var args := OS.get_cmdline_user_args()
	_demo_active = args.has("--%s" % DEMO_ARG) or args.has("--%s" % DEMO_FPV_ARG)
	if _demo_active:
		print("FreeFlightLevel: demo de disparo activa (--%s)." % DEMO_ARG)
		if not args.has("--%s" % DEMO_FPV_ARG):
			_build_demo_camera()
	_energy_demo_active = args.has("--%s" % ENERGY_DEMO_ARG)
	if _energy_demo_active:
		print("FreeFlightLevel: demo de energía activa (--%s)." % ENERGY_DEMO_ARG)
		_wire_energy_demo()


## Cámara lateral de la demo. Sólo existe con `--weapon-demo`: se crea en código
## para no dejar un nodo de captura en la escena que juega el jugador.
func _build_demo_camera() -> void:
	_demo_camera = Camera3D.new()
	_demo_camera.name = "WeaponDemoCamera"
	_demo_camera.fov = 60.0
	_demo_camera.far = 900.0
	add_child(_demo_camera)
	_demo_camera.global_position = DEMO_CAMERA_POSITION
	_demo_camera.look_at(DEMO_CAMERA_TARGET, Vector3.UP)


## Demo de disparo de WP-14: arma el dron, lo deja en equilibrio y mantiene el
## gatillo. Se usa así, para la captura del smoke test:
##
##     godot --path godot --windowed --resolution 960x540 \
##         --write-movie <dir>/w.png --fixed-fps 30 --quit-after 60 \
##         res://rounds/free_flight_level.tscn -- --weapon-demo
##
## La radio se apaga: sin mando, `throttle_up`/`throttle_down` dejan el acelerador en
## 0.5 y `Drone.arm()` lo rechazaría por `docs/03` §3.3 (hace falta `throttle < 0.02`).
## Por eso se arma con el comando en cero y recién después se pasa al de equilibrio.
func _physics_process(_delta: float) -> void:
	if _energy_demo_active:
		_run_energy_demo(_delta)
	if not _demo_active:
		return
	_demo_ticks += 1
	# `LevelBase.collect_cameras()` pone la FPV como activa al calentar la vista;
	# la demo la recupera una vez que eso ya pasó.
	if _demo_camera != null and not _demo_camera.current:
		_demo_camera.current = true
	var rig := drone_rig as DroneRig
	if rig == null:
		return
	var drone := rig.get_drone()
	if drone == null:
		return
	var radio := rig.get_radio()
	if radio != null:
		radio.enabled = false
	if _demo_ticks < DEMO_ARM_DELAY:
		_demo_command.clear()
		drone.update_command(_demo_command)
		return
	if not drone.is_armed():
		var _armed := drone.arm()
	_demo_command.set_axes(DEMO_HOVER_THROTTLE, 0.0, 0.0, 0.0)
	drone.update_command(_demo_command)
	var weapon := rig.get_weapon_mount()
	if weapon != null:
		weapon.fire_pressed = drone.is_armed()
	# El HUD es de la vista FPV: sobre la cámara lateral de la demo sólo estorba.
	if _demo_camera != null:
		var hud := rig.get_flight_hud()
		if hud != null:
			hud.visible = false


func _apply_environment_quality() -> void:
	if _world_environment == null or _world_environment.environment == null:
		return
	Graphics.apply_environment_quality(_world_environment.environment)


# --- Demo de energía (WP-15, `docs/09`) -------------------------------------------------------

## Cámara de la demo y avisos por consola. Se usa así, para la captura del smoke
## test de WP-15:
##
##     godot --path godot --windowed --resolution 960x540 \
##         --write-movie <dir>/e.png --fixed-fps 30 --quit-after 660 \
##         res://rounds/free_flight_level.tscn -- --energy-demo
##
## Los 660 cuadros a 30 fps son 22 s: cinco de pila en primer plano, doce de
## reconstrucción desde la cámara fija y el resto con el dron ya reaparecido.
func _wire_energy_demo() -> void:
	var rig := drone_rig as DroneRig
	if rig == null:
		return
	var energy := rig.get_energy_system()
	if energy != null and not energy.emp_hit.is_connected(_on_energy_demo_emp):
		var _emp := energy.emp_hit.connect(_on_energy_demo_emp)
	var controller := rig.get_respawn_controller()
	if controller != null and not controller.respawned.is_connected(_on_energy_demo_respawned):
		var _back := controller.respawned.connect(_on_energy_demo_respawned)
	var _battery := Events.battery_collected.connect(_on_energy_demo_battery)
	_energy_demo_camera = Camera3D.new()
	_energy_demo_camera.name = "EnergyDemoCamera"
	_energy_demo_camera.fov = 62.0
	_energy_demo_camera.far = 900.0
	add_child(_energy_demo_camera)


## Guion de la demo: colocar el dron junto a una pila encendida, esperar, destruir
## el casco y dejar que [RespawnController] haga el resto.
##
## El dron se **coloca**, no se pilota: sin mando no hay acelerador, y lo que la
## captura tiene que enseñar es la pila emisiva y el ciclo de muerte y reaparición,
## no el vuelo, que ya cubre la captura de WP-05.
func _run_energy_demo(delta: float) -> void:
	var rig := drone_rig as DroneRig
	if rig == null:
		return
	var radio := rig.get_radio()
	if radio != null:
		radio.enabled = false
	var hud := rig.get_flight_hud()
	if hud != null:
		hud.visible = false
	_energy_demo_time += delta
	if not _energy_demo_placed:
		_place_energy_demo(rig)
		return
	var controller := rig.get_respawn_controller()
	if _energy_demo_camera != null and controller != null and not controller.is_respawning():
		_energy_demo_camera.current = true
	if not _energy_demo_collected and _energy_demo_time >= ENERGY_DEMO_COLLECT_SECONDS:
		_energy_demo_collected = true
		# El dron entra en la esfera de 3.5 m de la pila: `body_entered` hace el resto.
		var drone := rig.get_drone()
		if drone != null and _energy_demo_anchor != Vector3.ZERO:
			drone.reset_to(Transform3D(Basis.IDENTITY, _energy_demo_anchor))
	if not _energy_demo_killed and _energy_demo_time >= ENERGY_DEMO_KILL_SECONDS:
		_energy_demo_killed = true
		var hull := rig.get_hull()
		var drone := rig.get_drone()
		if hull != null and drone != null:
			print("[energy-demo] t=%.1fs destruyo el casco; el mundo no se pausa."
					% _energy_demo_time)
			hull.apply_damage(hull.hp + 1.0, drone.global_position)
	_report_energy_demo(rig, delta)


## Espera a que el spawner encienda su primera pila y planta ahí al dron y la
## cámara. Hasta que haya una pila activa no hay nada que capturar.
func _place_energy_demo(rig: DroneRig) -> void:
	var spawner := get_node_or_null(^"BatterySpawner") as BatterySpawner
	if spawner == null or spawner.get_active_count() <= 0:
		return
	var pickup := spawner.get_pickup(ENERGY_DEMO_MARKER)
	if pickup == null or not pickup.is_active():
		return
	var anchor := pickup.get_anchor()
	_energy_demo_anchor = anchor
	var drone := rig.get_drone()
	if drone != null:
		drone.reset_to(Transform3D(Basis.IDENTITY, anchor + ENERGY_DEMO_DRONE_OFFSET))
	var energy := rig.get_energy_system()
	if energy != null:
		energy.reset(ENERGY_DEMO_START_ENERGY)
	if _energy_demo_camera != null:
		_energy_demo_camera.global_position = anchor + ENERGY_DEMO_CAMERA_OFFSET
		_energy_demo_camera.look_at(anchor + ENERGY_DEMO_LOOK_OFFSET, Vector3.UP)
		_energy_demo_camera.current = true
	_energy_demo_placed = true
	_energy_demo_time = 0.0
	print("[energy-demo] %d pilas activas de %d marcadores; pila 1 en %v."
			% [spawner.get_active_count(), spawner.get_marker_count(), anchor])


func _report_energy_demo(rig: DroneRig, delta: float) -> void:
	_energy_demo_report += delta
	if _energy_demo_report < ENERGY_DEMO_REPORT_SECONDS:
		return
	_energy_demo_report = 0.0
	var energy := rig.get_energy_system()
	var hull := rig.get_hull()
	var controller := rig.get_respawn_controller()
	print("[energy-demo] t=%.1fs energía %.1f%% casco %.0f respawn %.1fs mult ×%.2f"
			% [_energy_demo_time,
			energy.energy if energy != null else -1.0,
			hull.hp if hull != null else -1.0,
			controller.get_remaining_seconds() if controller != null else 0.0,
			controller.get_score_multiplier() if controller != null else 1.0])


## El `amount` de `Events.battery_collected` es lo que **ofrece** la pila, no lo que
## entró: desde que una pila renueva toda la energía vale 100 siempre, y un dron a
## 60 % sólo suma 40. Por eso la línea no dice «+100 %» —sería mentira en casi todos
## los casos— sino lo único que es verdad siempre: la batería queda llena.
func _on_energy_demo_battery(_amount: float, at_position: Vector3) -> void:
	print("[energy-demo] pila recogida en %v: batería al 100 %%." % at_position)


func _on_energy_demo_emp(glitch_seconds: float) -> void:
	print("[energy-demo] EMP: glitch de %.1f s." % glitch_seconds)


## Al reaparecer, la cámara de la demo se muda al punto de reaparición: es lo que
## la captura tiene que enseñar, y el `RespawnController` acaba de devolver la
## vista a la FPV, desde donde el dron no se ve a sí mismo.
func _on_energy_demo_respawned(score_multiplier: float) -> void:
	print("[energy-demo] dron reaparecido; multiplicador ×%.2f." % score_multiplier)
	if _energy_demo_camera == null or respawn_point == null:
		return
	var anchor := respawn_point.global_position
	_energy_demo_camera.global_position = anchor + ENERGY_DEMO_RESPAWN_CAMERA_OFFSET
	_energy_demo_camera.look_at(anchor, Vector3.UP)
	_energy_demo_camera.current = true
