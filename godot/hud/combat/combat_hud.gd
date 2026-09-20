## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## HUD de combate del nivel de batalla (`docs/12` §4).
##
## Es un [CanvasLayer] en la **capa 20** y **propiedad del nivel**, no del dron
## (`docs/12` §1.1). Esa es la única decisión de la que dependen todas las demás: el
## `FlightHUD` muere con el dron y se reconstruye al reaparecer, mientras que la barra
## del jefe, la integridad de la ciudad, el cronómetro y la línea de objetivo tienen
## que seguir en pantalla **mientras el dron no existe**. Por eso el `CombatHUD`
## sobrevive al respawn y por eso hacen falta los `bind_*`: lo que llega por el bus no
## necesita rebind, pero lo que se consulta —el arma para el retículo, el
## [RespawnController] para la cuenta, el [EnergySystem] para el EMP— apunta a nodos
## que el respawn reemplaza.
##
## ## Árbol
##
## [codeblock]
## CombatHUD (CanvasLayer, layer 20)
## └── Root (Control, full rect, mouse_filter = IGNORE)
##     ├── OffscreenMarkers · DamageDirection · WeakPointHint   ← espacio de **pantalla**
##     └── Frame (Control escalado, lienzo 1280 × 720)
##         ├── EnergyBar · HullBar · HeatGauge · Reticle · HitMarker
##         ├── BossBar · CityBar · TelegraphWarning · RoundTimer · ObjectiveLine
##         ├── CoachTip · RespawnOverlay · IntroBanner
##         ├── AlertScreen                                ← alerta del taller
##         │   └── Scanlines
##         └── GlitchLayer
##             └── StaticBurst                                  ← encima de todo
## [/codeblock]
##
## El `Frame` repite el truco del `FlightHUD`: los componentes están dibujados en
## píxeles contra un lienzo de [constant LAYOUT_SIZE] y el marco se reduce —nunca se
## agranda— para entrar en la pantalla. Que los dos HUD usen el **mismo** lienzo y el
## **mismo** factor es lo que garantiza que el arco de energía nunca caiga encima de
## una cinta lateral, a cualquier resolución. Los marcadores de borde y el arco de
## daño, en cambio, cuelgan directo del `Root`: el margen de 56 px y el borde de la
## pantalla son magnitudes de pantalla, no del lienzo.
##
## ## Un solo reloj
##
## Ningún componente tiene `_process()`. [method advance] los avanza a todos en un
## orden fijo, una vez por cuadro. Además de ser más barato que quince `_process()`,
## es lo que le permite a `combat_hud_check` llamar a [method set_manual_time] y medir
## «120 ms de hitmarker» o «3.0 s de glitch» en pasos exactos, sin depender de a qué
## velocidad corra el bucle principal en `--headless`.
class_name CombatHUD
extends CanvasLayer

## Capa del canvas (`docs/12` §1.1).
const LAYER: int = 20

## Lienzo de referencia de los componentes, en píxeles. El mismo que el del
## `FlightHUD` ([constant FlightHUD.MIN_LAYOUT_SIZE]), a propósito.
const LAYOUT_SIZE: Vector2 = Vector2(1280.0, 720.0)

## Los dieciocho componentes que [method show_component] sabe encender y apagar.
##
## [constant Component.WEAK_HINT] y [constant Component.COACH] son los dos que agrega
## WP-24d, y [constant Component.ALERT_SCREEN] el que agrega WP-25b: todos van **al
## final** a propósito, porque los anteriores conservan su valor y un `enum` de HUD
## que renumera es un `enum` que rompe cualquier estado guardado.
enum Component {ENERGY, HULL, HEAT, RETICLE, HIT_MARKER, BOSS, CITY, MARKERS,
		DAMAGE, TELEGRAPH, TIMER, OBJECTIVE, RESPAWN, INTRO, GLITCH,
		WEAK_HINT, COACH, ALERT_SCREEN}

## Lo único que se ve en modo cinemático (`docs/12` §4.2). Se guarda como
## `Array[int]` porque un `Array` tipado con un `enum` no es un tipo de contenedor
## válido en GDScript; los valores son los mismos.
##
## [constant Component.GLITCH] no dibuja nada —le escribe desplazamientos a los
## demás— pero **tiene que estar encendido**: de él cuelga el [HUDStaticBurst], y la
## estática de 0,4 s que corta la alerta ocurre entera dentro del modo cinemático
## (`docs/13` §1). Con la capa apagada, [method CombatHUD.advance] no la avanzaría y
## el corte no se vería.
const CINEMATIC_COMPONENTS: Array[int] = [Component.CITY, Component.INTRO,
		Component.GLITCH]

## Lo único que se ve durante `ALERT` (`docs/11` §1, `docs/narrativa` §5).
##
## La alerta del taller **no es** la cinemática: es un monitor que tapa la pantalla
## entera, así que ni la franja de ciudad ni el rótulo de la ronda tienen sitio. Los
## dos vuelven en `INTRO`, que sí es [constant CINEMATIC_COMPONENTS].
const ALERT_COMPONENTS: Array[int] = [Component.ALERT_SCREEN, Component.GLITCH]

## Componentes que **sólo** existen en modo cinemático. El rótulo de la ronda es un
## cartel de apertura: en `BATTLE` taparía el aviso de telegrafía y el retículo, así
## que su visibilidad no es negociable con [method show_component]; y la pantalla de
## la alerta, por el mismo motivo, sólo existe en `ALERT`.
const CINEMATIC_ONLY_COMPONENTS: Array[int] = [Component.INTRO, Component.ALERT_SCREEN]

## Componentes que **sólo** tienen sentido con un dron vivo.
##
## Mientras [RespawnController] reconstruye el dron no hay arma, así que una mira, una
## barra de calor y un acuse de impacto estarían mintiendo (`docs/09` §2.8). Todo lo
## demás —jefe, ciudad, cronómetro, objetivo— sigue en pantalla: es justamente lo que
## el `CombatHUD` existe para sostener mientras el `FlightHUD` no está.
const DRONE_ONLY_COMPONENTS: Array[int] = [Component.RETICLE, Component.HEAT,
		Component.HIT_MARKER]

var _root: Control = null
var _frame: Control = null
var _energy: HUDEnergyBar = null
var _hull: HUDHullBar = null
var _heat: HUDHeatGauge = null
var _reticle: HUDReticle = null
var _hit_marker: HUDHitMarker = null
var _boss: HUDBossBar = null
var _city_bar: HUDCityBar = null
var _markers: HUDOffscreenMarkers = null
var _damage: HUDDamageDirection = null
var _telegraph: HUDTelegraphWarning = null
var _timer: HUDRoundTimer = null
var _objective: HUDObjectiveLine = null
var _respawn: HUDRespawnOverlay = null
var _intro: HUDIntroBanner = null
var _glitch: HUDGlitchLayer = null
var _weak_hint: HUDWeakPointHint = null
var _coach: HUDCoachTip = null
var _alert: HUDAlertScreen = null

## Cámara impuesta con [method set_camera]; si es `null` manda la que dibuja la escena.
var _camera: Camera3D = null

## Rig vivo. Se vuelve a leer entero en cada `drone_respawned`.
var _rig: DroneRig = null

## [EnergySystem] al que está conectada la señal local `emp_hit` (`docs/09` §2.9).
## Se guarda para poder desconectarla antes de conectar la del dron nuevo.
var _energy_system: EnergySystem = null

var _city: CityIntegrity = null
var _manager: RoundManager = null
var _sequencer: ObjectiveSequencer = null

## Enemigos vinculados, en orden de aparición (`docs/12` §7: «varios enemigos: lista»).
var _enemies: Array[Node3D] = []

var _cinematic: bool = false

## `true` mientras el dron esté reconstruyéndose. Lo deduce [method advance] de la
## cuenta atrás, que es quien consulta al [RespawnController].
var _drone_absent: bool = false

## Con `true`, [method advance] sólo corre cuando alguien la llama a mano. Lo usa
## `combat_hud_check` para medir plazos en pasos exactos.
var _manual_time: bool = false

## Estado de ronda que se está reflejando, de [enum Global.RoundState].
var _round_state: int = Global.RoundState.INTRO

## Visibilidad pedida con [method show_component], independiente de la que impone el
## modo cinemático: al salir de la cinemática cada componente vuelve a lo que el
## llamador había pedido, no a «todo encendido».
var _wanted: Dictionary[int, bool] = {}


func _ready() -> void:
	layer = LAYER
	# El HUD de combate se congela con el juego: en pausa no tiene nada que contar y
	# el `PauseMenu` de la capa 40 le pasa por encima (`docs/11` §6.3).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_collect_nodes()
	_layout()
	for component: int in Component.values():
		_wanted[component] = true
	if _glitch != null:
		_glitch.set_targets(_glitch_targets())
	_connect_bus()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_layout):
		var _discard := viewport.size_changed.connect(_layout)
	_apply_visibility()


func _exit_tree() -> void:
	_disconnect_bus()
	_bind_energy_system(null)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_layout):
		viewport.size_changed.disconnect(_layout)
	_unbind_round()


func _process(delta: float) -> void:
	if _manual_time:
		return
	advance(delta)


# --- Reloj ------------------------------------------------------------------------------------

## Avanza el HUD entero un paso. El orden importa poco salvo en un punto: el
## [HUDGlitchLayer] va **último**, para que el desplazamiento que escribe se aplique
## sobre componentes que ya actualizaron su estado en este mismo cuadro.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_layout_if_needed()
	for component: CombatHUDComponent in _components():
		if component == null or not component.visible:
			continue
		component.tick(delta)
	_refresh_drone_presence()
	if _glitch != null and _glitch.visible:
		_glitch.tick(delta)


## Con `true` el HUD deja de avanzar solo y sólo se mueve con [method advance].
func set_manual_time(enabled: bool) -> void:
	_manual_time = enabled


## `true` si el HUD está en modo de reloj manual.
func is_manual_time() -> bool:
	return _manual_time


# --- Vínculos (`docs/12` §7) ------------------------------------------------------------------

## Ata el HUD al dron vivo: arma para el retículo, [RespawnController] para la cuenta
## y [EnergySystem] para la señal local `emp_hit`.
##
## Es idempotente y **no duplica conexiones**: la única señal que se conecta acá es
## `emp_hit`, y antes de conectar la nueva se desconecta la vieja. Llamarla con `null`
## deja el HUD sin dron, que es lo correcto mientras el dron se reconstruye.
func bind_drone(rig: DroneRig) -> void:
	_rig = rig if rig != null and is_instance_valid(rig) else null
	var mount: WeaponMount = null
	var controller: RespawnController = null
	var energy: EnergySystem = null
	if _rig != null:
		mount = _rig.get_weapon_mount()
		controller = _rig.get_respawn_controller()
		energy = _rig.get_energy_system()
	if _reticle != null:
		_reticle.bind_weapon(mount)
	if _respawn != null:
		_respawn.bind_respawn(controller)
	_bind_energy_system(energy)


## Da de alta un enemigo para la barra del jefe y los marcadores. Idempotente.
func bind_enemy(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy) or _enemies.has(enemy):
		return
	_enemies.append(enemy)
	if _boss != null:
		_boss.bind_enemy(enemy)
	if _weak_hint != null:
		_weak_hint.bind_enemy(enemy)
	if _coach != null:
		_coach.bind_enemy(enemy)


## Da de baja un enemigo.
func unbind_enemy(enemy: Node3D) -> void:
	if enemy == null:
		return
	_enemies.erase(enemy)
	if _boss != null:
		_boss.unbind_enemy(enemy)
	if _weak_hint != null:
		_weak_hint.unbind_enemy(enemy)
	if _coach != null:
		_coach.unbind_enemy(enemy)


## Enemigos vinculados, en orden de aparición.
func bound_enemies() -> Array[Node3D]:
	return _enemies.duplicate()


## Ata el HUD a la integridad de la ciudad. Hace falta porque
## [method CityIntegrity.get_under_siege] es una **consulta**, no un hecho del bus
## (`docs/12` §7), y el marcador del edificio bajo asedio la necesita cada cuadro.
func bind_city(integrity: CityIntegrity) -> void:
	_city = integrity if integrity != null and is_instance_valid(integrity) else null
	if _markers != null:
		_markers.city = _city
	if _city_bar != null and _city != null:
		_city_bar.set_integrity(_city.get_ratio())


## Ata el cronómetro y la línea de objetivo a la ronda.
##
## [param sequencer] puede venir en `null`: el cronómetro sigue andando y la línea de
## objetivo se queda vacía, que es lo que corresponde en una escena de prueba sin
## cadena de objetivos.
func bind_round(manager: RoundManager, sequencer: ObjectiveSequencer) -> void:
	_unbind_round()
	_manager = manager if manager != null and is_instance_valid(manager) else null
	_sequencer = sequencer if sequencer != null and is_instance_valid(sequencer) else null
	if _timer != null:
		_timer.bind_round(_manager)
	if _objective != null:
		_objective.bind_sequencer(_sequencer)
	if _alert != null:
		_alert.bind_round(_manager)
	if _manager != null:
		var _discard := _manager.objective_text_changed.connect(_on_objective_text_changed)
		# La única señal **local** de la ronda que el HUD escucha (`docs/11` §9.2): el
		# estado ya viaja por el bus, pero el instante exacto en que la pantalla del
		# taller deja de dibujarse sólo le interesa a quien dibuja el corte.
		_discard = _manager.alert_finished.connect(_on_alert_finished)
		_refresh_intro_keys()
	if _sequencer != null:
		var _discard := _sequencer.objective_started.connect(_on_objective_started)
		_discard = _sequencer.all_finished.connect(_on_objectives_finished)


## Cámara con la que se proyectan el retículo, los marcadores y el arco de daño.
## Con `null` se usa la que esté dibujando la escena, que es lo que hace que el HUD
## siga funcionando mientras el nivel cicla cámaras o el dron se reconstruye.
func set_camera(camera: Camera3D) -> void:
	_camera = camera if camera != null and is_instance_valid(camera) else null
	if _reticle != null:
		_reticle.camera = _camera
	if _markers != null:
		_markers.camera = _camera
	if _damage != null:
		_damage.camera = _camera
	if _telegraph != null:
		_telegraph.camera = _camera
	if _weak_hint != null:
		_weak_hint.camera = _camera


## Cámara efectiva: la impuesta si sigue viva, si no la que dibuja la escena.
func get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera) and _camera.is_inside_tree():
		return _camera
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


# --- Modo cinemático (`docs/12` §4.2) ---------------------------------------------------------

## Deja en pantalla sólo la franja de ciudad y el rótulo de la ronda, o devuelve el
## HUD entero. Lo llama el nivel en cada cambio de estado de la ronda.
func set_cinematic(enabled: bool) -> void:
	if _cinematic == enabled:
		return
	_cinematic = enabled
	if enabled:
		# Nada de lo acumulado durante la batalla tiene sentido en una cinemática.
		if _hit_marker != null:
			_hit_marker.clear_marks()
		if _damage != null:
			_damage.clear_arcs()
		if _telegraph != null:
			_telegraph.clear_warning()
		if _glitch != null:
			_glitch.stop()
			# La estática es un corte de video y una cinemática **es** otro video: si
			# una ráfaga sobreviviera al cambio de modo, el rótulo de la ronda
			# aparecería debajo de ruido que ya no significa nada.
			_glitch.stop_static()
		if _coach != null:
			_coach.clear_tip()
	_apply_visibility()


## `true` mientras el HUD esté en modo cinemático.
func is_cinematic() -> bool:
	return _cinematic


# --- Componentes ------------------------------------------------------------------------------

## Enciende o apaga un componente. En modo cinemático la petición se guarda y se
## aplica al salir: lo que manda mientras dura la cinemática es `docs/12` §4.2.
func show_component(component: Component, component_visible: bool) -> void:
	_wanted[int(component)] = component_visible
	_apply_visibility()


## Estado **pedido** de un componente, sin contar el modo cinemático.
func is_component_visible(component: Component) -> bool:
	return bool(_wanted.get(int(component), false))


## Estado real en pantalla de un componente.
func is_component_drawn(component: Component) -> bool:
	var node := component_node(component)
	return node != null and node.visible


## Nodo que dibuja un componente. Nunca es `null` en un HUD bien construido.
func component_node(component: Component) -> CombatHUDComponent:
	match component:
		Component.ENERGY:
			return _energy
		Component.HULL:
			return _hull
		Component.HEAT:
			return _heat
		Component.RETICLE:
			return _reticle
		Component.HIT_MARKER:
			return _hit_marker
		Component.BOSS:
			return _boss
		Component.CITY:
			return _city_bar
		Component.MARKERS:
			return _markers
		Component.DAMAGE:
			return _damage
		Component.TELEGRAPH:
			return _telegraph
		Component.TIMER:
			return _timer
		Component.OBJECTIVE:
			return _objective
		Component.RESPAWN:
			return _respawn
		Component.INTRO:
			return _intro
		Component.GLITCH:
			return _glitch
		Component.WEAK_HINT:
			return _weak_hint
		Component.COACH:
			return _coach
		Component.ALERT_SCREEN:
			return _alert
		_:
			return null


## `true` mientras el EMP esté perturbando el HUD (`docs/12` §4.3).
func is_glitching() -> bool:
	return _glitch != null and _glitch.is_glitching()


## Intensidad del EMP, de 1 a 0. La lee `docs/13` para el `fpv_overlay.gdshader`.
func emp_strength() -> float:
	return _glitch.emp_strength if _glitch != null else 0.0


## `true` mientras la estática de la caída esté tapando la pantalla (`docs/13` §1).
func is_static_playing() -> bool:
	return _glitch != null and _glitch.is_static_playing()


# --- Bus (`docs/02` §5.1) ---------------------------------------------------------------------

func _connect_bus() -> void:
	for pair: Array in _bus_pairs():
		var signal_ref: Signal = pair[0]
		var callable: Callable = pair[1]
		if not signal_ref.is_connected(callable):
			var _discard := signal_ref.connect(callable)


func _disconnect_bus() -> void:
	for pair: Array in _bus_pairs():
		var signal_ref: Signal = pair[0]
		var callable: Callable = pair[1]
		if signal_ref.is_connected(callable):
			signal_ref.disconnect(callable)


## Las dieciséis señales del bus que el `CombatHUD` escucha, con su manejador. Una
## sola tabla para conectar y desconectar: dos listas separadas se desincronizan y
## dejan conexiones colgadas, que es justo lo que verifica la fila 11 de `docs/12` §9.2.
func _bus_pairs() -> Array[Array]:
	return [
		[Events.energy_changed, _on_energy_changed],
		[Events.hull_changed, _on_hull_changed],
		[Events.weapon_heat_changed, _on_weapon_heat_changed],
		[Events.hit_confirmed, _on_hit_confirmed],
		[Events.drone_damaged, _on_drone_damaged],
		[Events.drone_destroyed, _on_drone_destroyed],
		[Events.drone_respawned, _on_drone_respawned],
		[Events.enemy_spawned, _on_enemy_spawned],
		[Events.enemy_part_broken, _on_enemy_part_broken],
		[Events.enemy_weak_point_state, _on_enemy_weak_point_state],
		[Events.enemy_phase_changed, _on_enemy_phase_changed],
		[Events.enemy_attack_telegraphed, _on_enemy_attack_telegraphed],
		[Events.enemy_defeated, _on_enemy_defeated],
		[Events.building_destroyed, _on_building_destroyed],
		[Events.city_integrity_changed, _on_city_integrity_changed],
		[Events.round_state_changed, _on_round_state_changed],
	]


func _on_energy_changed(ratio: float, critical: bool) -> void:
	if _energy != null:
		_energy.set_energy(ratio, critical)


func _on_hull_changed(ratio: float) -> void:
	if _hull != null:
		_hull.set_hull(ratio)


func _on_weapon_heat_changed(ratio: float, overheated: bool) -> void:
	if _heat != null:
		_heat.set_heat(ratio, overheated)


## Un impacto en un punto débil es el acuse de que el jugador entendió: apaga el
## marcador de ayuda y reinicia el reloj de los ocho segundos (WP-24d).
func _on_hit_confirmed(_position: Vector3, weak: bool, lethal: bool) -> void:
	if _hit_marker != null:
		_hit_marker.add_hit(weak, lethal)
	if not weak:
		return
	if _weak_hint != null:
		_weak_hint.on_weak_hit()
	if _coach != null:
		_coach.on_weak_hit()


func _on_drone_damaged(amount: float, source_position: Vector3) -> void:
	if _damage != null:
		_damage.add_damage(amount, source_position)


## El dron cayó. Aquí **no hay pantalla de muerte** (`docs/13` §1, nota del checkpoint
## 3b): se corta el video ocho décimas y ya. El hecho llega por el bus y no por la
## señal local del [Hull] porque el `CombatHUD` es del nivel y no del dron; es el mismo
## hecho global que escucha el `RoundManager`.
func _on_drone_destroyed(_position: Vector3) -> void:
	if _glitch != null:
		_glitch.trigger_static(HUDStaticBurst.DEATH_SECONDS)


## El dron volvió a volar: hay que volver a atar el arma, el [RespawnController] y la
## señal `emp_hit`, porque el respawn los reconstruye (`docs/12` §7). El HUD **no** se
## reinstancia; por eso vive en el nivel.
##
## Y media ráfaga de estática más: el enlace del dron nuevo enganchando. Es la otra
## mitad del corte —el taller ya entregó— y por eso dura la mitad.
func _on_drone_respawned(_score_multiplier: float) -> void:
	bind_drone(_rig)
	if _glitch != null:
		_glitch.trigger_static(HUDStaticBurst.REBUILT_SECONDS)


func _on_enemy_spawned(enemy: Node3D, _enemy_id: StringName) -> void:
	bind_enemy(enemy)


func _on_enemy_part_broken(enemy: Node3D, part_id: StringName, _position: Vector3) -> void:
	if _boss != null:
		_boss.on_part_broken(enemy, part_id)
	if _weak_hint != null:
		_weak_hint.on_part_broken(enemy, part_id)
	if _coach != null:
		_coach.on_part_broken(enemy, part_id)


func _on_enemy_weak_point_state(enemy: Node3D, wp_id: StringName, exposed: bool) -> void:
	if _boss != null:
		_boss.on_weak_point_state(enemy, wp_id, exposed)
	if _weak_hint != null:
		_weak_hint.on_weak_point_state(enemy, wp_id, exposed)
	if _coach != null:
		_coach.on_weak_point_state(enemy, wp_id, exposed)


func _on_enemy_phase_changed(enemy: Node3D, phase_id: StringName) -> void:
	if _boss != null:
		_boss.on_phase_changed(enemy, phase_id)


func _on_enemy_attack_telegraphed(enemy: Node3D, attack_id: StringName,
		duration: float) -> void:
	if _telegraph != null:
		_telegraph.on_telegraph(enemy, attack_id, duration)
	if _coach != null:
		_coach.on_telegraph(enemy, attack_id, duration)


func _on_enemy_defeated(enemy: Node3D, _enemy_id: StringName) -> void:
	unbind_enemy(enemy)
	if _telegraph != null:
		_telegraph.clear_warning()


func _on_building_destroyed(_position: Vector3, _value: int) -> void:
	if _city_bar != null:
		_city_bar.flash()


func _on_city_integrity_changed(ratio: float) -> void:
	if _city_bar != null:
		_city_bar.set_integrity(ratio)


## `ALERT` e `INTRO` encienden el modo cinemático; `BATTLE` lo apaga. En los dos
## estados terminales el HUD se queda en modo cinemático hasta que el nivel lo esconde
## al mostrar la [ResultCard] (`docs/11` §6.3).
##
## Los dos primeros estados son cinemáticos pero **no muestran lo mismo**: `ALERT` es
## el monitor del taller a pantalla completa ([constant ALERT_COMPONENTS]) e `INTRO`
## el rótulo de la ronda sobre el travelling ([constant CINEMATIC_COMPONENTS]). Por
## eso [method _apply_visibility] se llama **siempre** al final y no se confía en
## [method set_cinematic], que corta por lo sano cuando el modo no cambia: de `ALERT`
## a `INTRO` el modo es el mismo y lo visible no.
##
## Y esa salida temprana es justo lo que hace falta: [method set_cinematic] apaga la
## estática al **entrar** en modo cinemático, así que si se ejecutara en el paso de
## `ALERT` a `INTRO` se llevaría por delante el corte de 0,4 s que acaba de arrancar
## [method _on_alert_finished].
func _on_round_state_changed(state: int) -> void:
	_round_state = state
	match state:
		Global.RoundState.ALERT:
			if _alert != null:
				_alert.refresh()
			set_cinematic(true)
		Global.RoundState.INTRO:
			_refresh_intro_keys()
			# Ronda nueva, consejos nuevos: los de la partida anterior ya se dieron
			# por dados y el jugador que reintenta puede ser otro (WP-24d).
			if _coach != null:
				_coach.reset()
			set_cinematic(true)
		Global.RoundState.BATTLE:
			set_cinematic(false)
		_:
			set_cinematic(true)
	_apply_visibility()


## `RoundManager.alert_finished`: el monitor del taller se corta y entra la estática.
##
## Es el corte de `docs/narrativa` §5 —«la imagen cae a estática un instante y aparece
## la señal del dron»— y se dibuja con la **misma** ráfaga que la caída del dron
## (`docs/13` §1): un solo efecto de señal perdida, tres motivos para dispararlo.
##
## La ráfaga tiene que sobrevivir al cambio de estado que viene detrás, porque el
## corte es justamente el pase de una imagen a la otra. Lo consigue
## [method _on_round_state_changed], que no vuelve a entrar en modo cinemático cuando
## ya está en él.
func _on_alert_finished() -> void:
	if _glitch != null:
		_glitch.trigger_static(RoundManager.STATIC_SECONDS)


func _on_objective_text_changed(task_text: String, progress: float,
		progress_text: String) -> void:
	if _objective != null:
		_objective.set_task(task_text, progress, progress_text)


func _on_objective_started(_index: int) -> void:
	if _objective != null:
		_objective.refresh_objective()


func _on_objectives_finished() -> void:
	if _objective != null:
		_objective.clear_objective()


# --- Internos ---------------------------------------------------------------------------------

## Conecta la señal **local** `EnergySystem.emp_hit` (`docs/09` §2.9), desconectando
## primero la del dron anterior. Es el único punto del HUD donde una conexión podría
## duplicarse al reaparecer, y por eso está aislado en una función.
func _bind_energy_system(energy: EnergySystem) -> void:
	if _energy_system != null and is_instance_valid(_energy_system) \
			and _energy_system.emp_hit.is_connected(_on_emp_hit):
		_energy_system.emp_hit.disconnect(_on_emp_hit)
	_energy_system = energy if energy != null and is_instance_valid(energy) else null
	if _energy_system != null and not _energy_system.emp_hit.is_connected(_on_emp_hit):
		var _discard := _energy_system.emp_hit.connect(_on_emp_hit)


func _on_emp_hit(glitch_seconds: float) -> void:
	if _glitch != null:
		_glitch.trigger_emp(glitch_seconds)


func _unbind_round() -> void:
	if _manager != null and is_instance_valid(_manager):
		if _manager.objective_text_changed.is_connected(_on_objective_text_changed):
			_manager.objective_text_changed.disconnect(_on_objective_text_changed)
		if _manager.alert_finished.is_connected(_on_alert_finished):
			_manager.alert_finished.disconnect(_on_alert_finished)
	if _sequencer != null and is_instance_valid(_sequencer):
		if _sequencer.objective_started.is_connected(_on_objective_started):
			_sequencer.objective_started.disconnect(_on_objective_started)
		if _sequencer.all_finished.is_connected(_on_objectives_finished):
			_sequencer.all_finished.disconnect(_on_objectives_finished)
	_manager = null
	_sequencer = null
	if _alert != null:
		_alert.bind_round(null)


## Nombre y objetivo de la ronda en curso para el rótulo de la cinemática.
func _refresh_intro_keys() -> void:
	if _intro == null:
		return
	var id := _manager.get_round_id() if _manager != null and is_instance_valid(_manager) \
			else Global.selected_round
	var data := RoundCatalog.get_by_id(id)
	if data.is_empty():
		data = RoundCatalog.get_by_id(RoundManager.FALLBACK_ROUND_ID)
	if data.is_empty():
		return
	_intro.set_round(String(data.get("name_key", "")), String(data.get("goal_key", "")))


## Los diecisiete componentes que dibujan, sin el [HUDGlitchLayer], que los mueve.
func _components() -> Array[CombatHUDComponent]:
	return [_energy, _hull, _heat, _reticle, _hit_marker, _boss, _city_bar, _markers,
			_damage, _telegraph, _timer, _objective, _respawn, _intro, _weak_hint,
			_coach, _alert]


## A quiénes sacude el EMP. El propio [HUDGlitchLayer] no está: moverse a sí mismo no
## tendría efecto visible y saltearse un cuadro cortaría la perturbación entera.
func _glitch_targets() -> Array[CombatHUDComponent]:
	return _components()


## Apaga o enciende lo que depende de que haya dron. La cuenta atrás ya consultó al
## [RespawnController] en su `tick`, así que acá sólo se lee su estado.
func _refresh_drone_presence() -> void:
	var absent := _respawn != null and _respawn.is_showing()
	if absent == _drone_absent:
		return
	_drone_absent = absent
	if absent and _hit_marker != null:
		_hit_marker.clear_marks()
	_apply_visibility()


## Deja visible lo que corresponde al modo vigente.
##
## El modo cinemático tiene **dos** listas y no una: `ALERT` es el monitor del taller
## a pantalla completa y el resto de los estados cinemáticos son el rótulo de la ronda
## sobre el nivel. Se resuelve cuál manda una sola vez, fuera del bucle.
func _apply_visibility() -> void:
	var allowed := CINEMATIC_COMPONENTS
	if _round_state == Global.RoundState.ALERT:
		allowed = ALERT_COMPONENTS
	for component: int in Component.values():
		var node := component_node(component as Component)
		if node == null:
			continue
		var wanted := bool(_wanted.get(component, true))
		if _cinematic:
			wanted = wanted and allowed.has(component)
		elif CINEMATIC_ONLY_COMPONENTS.has(component):
			wanted = false
		elif _drone_absent and DRONE_ONLY_COMPONENTS.has(component):
			wanted = false
		if node.visible != wanted:
			node.visible = wanted
			if wanted:
				node.queue_redraw()


## Escala el marco igual que el `FlightHUD`, para que los dos lienzos coincidan.
func _layout() -> void:
	if _root == null or _frame == null:
		return
	var available := _root.size
	if available.x < 1.0 or available.y < 1.0:
		var viewport := get_viewport()
		available = viewport.get_visible_rect().size if viewport != null else LAYOUT_SIZE
	if available.x < 1.0 or available.y < 1.0:
		available = LAYOUT_SIZE
	var factor := minf(1.0, minf(available.x / LAYOUT_SIZE.x, available.y / LAYOUT_SIZE.y))
	factor = maxf(factor, 0.05)
	_frame.position = Vector2.ZERO
	_frame.scale = Vector2(factor, factor)
	_frame.size = available / factor


## El primer cuadro del HUD llega antes de que el `Control` raíz tenga tamaño: ahí el
## marco quedaría con el lienzo de respaldo. Se corrige en cuanto haya tamaño real.
func _layout_if_needed() -> void:
	if _root == null or _frame == null:
		return
	if _root.size.x < 1.0 or _root.size.y < 1.0:
		return
	var expected := minf(1.0, minf(_root.size.x / LAYOUT_SIZE.x,
			_root.size.y / LAYOUT_SIZE.y))
	expected = maxf(expected, 0.05)
	if not is_equal_approx(_frame.scale.x, expected):
		_layout()


## Toma los nodos por nombre único y avisa de los que falten. Un HUD al que le falta
## un componente no debe fallar en silencio.
func _collect_nodes() -> void:
	_root = get_node_or_null(^"%Root") as Control
	_frame = get_node_or_null(^"%Frame") as Control
	_energy = get_node_or_null(^"%EnergyBar") as HUDEnergyBar
	_hull = get_node_or_null(^"%HullBar") as HUDHullBar
	_heat = get_node_or_null(^"%HeatGauge") as HUDHeatGauge
	_reticle = get_node_or_null(^"%Reticle") as HUDReticle
	_hit_marker = get_node_or_null(^"%HitMarker") as HUDHitMarker
	_boss = get_node_or_null(^"%BossBar") as HUDBossBar
	_city_bar = get_node_or_null(^"%CityBar") as HUDCityBar
	_markers = get_node_or_null(^"%OffscreenMarkers") as HUDOffscreenMarkers
	_damage = get_node_or_null(^"%DamageDirection") as HUDDamageDirection
	_telegraph = get_node_or_null(^"%TelegraphWarning") as HUDTelegraphWarning
	_timer = get_node_or_null(^"%RoundTimer") as HUDRoundTimer
	_objective = get_node_or_null(^"%ObjectiveLine") as HUDObjectiveLine
	_respawn = get_node_or_null(^"%RespawnOverlay") as HUDRespawnOverlay
	_intro = get_node_or_null(^"%IntroBanner") as HUDIntroBanner
	_glitch = get_node_or_null(^"%GlitchLayer") as HUDGlitchLayer
	_weak_hint = get_node_or_null(^"%WeakPointHint") as HUDWeakPointHint
	_coach = get_node_or_null(^"%CoachTip") as HUDCoachTip
	_alert = get_node_or_null(^"%AlertScreen") as HUDAlertScreen
	var missing := PackedStringArray()
	for pair: Array in [["Root", _root], ["Frame", _frame], ["EnergyBar", _energy],
			["HullBar", _hull], ["HeatGauge", _heat], ["Reticle", _reticle],
			["HitMarker", _hit_marker], ["BossBar", _boss], ["CityBar", _city_bar],
			["OffscreenMarkers", _markers], ["DamageDirection", _damage],
			["TelegraphWarning", _telegraph], ["RoundTimer", _timer],
			["ObjectiveLine", _objective], ["RespawnOverlay", _respawn],
			["IntroBanner", _intro], ["GlitchLayer", _glitch],
			["WeakPointHint", _weak_hint], ["CoachTip", _coach],
			["AlertScreen", _alert]]:
		if pair[1] == null:
			missing.append(String(pair[0]))
	if not missing.is_empty():
		push_error("CombatHUD: faltan componentes en %s: %s" % [name, ", ".join(missing)])
