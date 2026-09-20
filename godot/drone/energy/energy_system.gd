## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Economía de energía del dron (`docs/09` §2.1, §2.2 y §2.9).
##
## Es un [Node] hijo del [Drone] —`Drone/EnergySystem`, la ruta que fija
## `docs/09` §3.1— y guarda [member energy] en la escala **0–100**, no
## normalizada, porque todos los valores del Anexo C están en porcentaje.
##
## Qué hace, una línea por cosa:
##
## 1. **Drena** mientras el dron está armado: `base_drain + throttle_drain ·
##    throttle` por segundo, con acumulador propio en [method _physics_process]
##    (nunca un [Timer], `docs/09` §1).
## 2. **Recarga en reposo** con el dron desarmado, a `idle_recharge` %/s y solo
##    por debajo de `idle_recharge_cap`: es la salida del bloqueo a 0 % lejos de
##    una pila.
## 3. **Cobra** los disparos con [method consume], que es **todo o nada**:
##    `docs/08` depende de eso para no emitir medios disparos.
## 4. Lleva la máquina de estados `NORMAL → CRITICAL → DEPLETED` con **histéresis**
##    de salida, aplica [method Drone.set_thrust_scale] y baja
##    [member FlightController.can_arm_energy] cuando la batería se agota.
## 5. Publica `Events.energy_changed(ratio, critical)` al cambiar de estado y
##    cuando `ratio` se mueve al menos [member EnergyProfile.publish_epsilon].
##
## **Dos discrepancias registradas con `docs/09`**:
##
## - §5 sub-check 5 pide que un dron desarmado a 50 % suba a 60 % en 10 s y a la
##   vez que «el tope de reposo es 10 % (desde 5 % → 10.0, no más)». Las dos frases
##   no pueden ser ciertas al mismo tiempo. Manda §2.1, que es donde se justifica
##   la regla: la recarga en reposo existe **solo** para salir del bloqueo a 0 % y
##   da «~10 s de vuelo, suficiente para llegar a la pila más cercana». Por eso
##   [member EnergyProfile.idle_recharge_cap] es un techo absoluto y un dron
##   desarmado al 50 % se queda al 50 %.
## - §2.1 habla de recarga «con el dron **desarmado**» y el Anexo de §4 le cobra
##   `base_drain` a un dron «armado en el suelo». Estar posado, entonces, no
##   recarga: lo que decide es el armado, no el contacto con el suelo.
class_name EnergySystem extends Node

## La batería llegó a 0 %. Se emite una sola vez por agotamiento.
signal depleted()

## Se entró en estado crítico (`ratio < critical_ratio`).
signal critical_entered()

## Se salió del estado crítico (`ratio >= critical_exit_ratio`).
signal critical_exited()

## Pulso EMP recibido; [param glitch_seconds] es lo que dura la perturbación de
## interfaz. Va por señal **local** y no por el bus (`docs/09` §2.9): el dron nunca
## se libera, así que la conexión que hace el nivel al arrancar vale toda la ronda.
signal emp_hit(glitch_seconds: float)

## Números de la economía (`docs/09` §3.3). Sin perfil el nodo no drena ni cobra
## nada y lo avisa en [method _ready].
@export var profile: EnergyProfile

## Dron dueño de esta batería. Si queda vacío se busca el primer ancestro [Drone].
@export var drone: Drone

## Energía actual, en la escala 0–100.
##
## Escribirla es equivalente a [method reset] sin forzar la publicación: recorta
## en `[0, max_energy]` y reevalúa el estado en el acto. Fuera del respawn el
## proyecto usa [method consume], [method recharge] y [method drain].
var energy: float = 100.0:
	set(value):
		_write_energy(value)
	get:
		return _energy

var _energy: float = 100.0
var _critical: bool = false
var _depleted: bool = false
var _controller: Node = null
var _published_ratio: float = -1.0
var _published_critical: bool = false
var _published: bool = false

## Hasta que [method _ready] termina, escribir [member energy] no publica nada ni
## emite señales: un nodo a medio construir no tiene por qué avisarle al bus.
var _live: bool = false


func _ready() -> void:
	if profile == null:
		push_error("EnergySystem: falta el EnergyProfile en %s (docs/09 §3.3)." % name)
	if drone == null:
		drone = _find_drone()
	if drone == null:
		push_error("EnergySystem: no se encontró el Drone dueño de %s (docs/09 §3.1)." % name)
	_controller = _find_controller()
	_energy = _max_energy()
	_live = true
	_refresh_state(true)


## Drenaje y recarga del tick (`docs/09` §2.1).
##
## Todo por acumulador: `energy` se mueve `rate · delta` por paso de física, que a
## 100 Hz son 10 ms. No hay ningún [Timer] en el camino, y por eso `energy_check`
## puede simular 12 s llamando a este método 1 200 veces en milisegundos.
func _physics_process(delta: float) -> void:
	if delta <= 0.0 or profile == null:
		return
	if _is_armed():
		var throttle := clampf(_throttle(), 0.0, 1.0)
		var rate := profile.base_drain + profile.throttle_drain * throttle
		if rate > 0.0:
			_write_energy(_energy - rate * delta)
		return
	# Reposo: solo por debajo del techo, y sin pasarse de él.
	if profile.idle_recharge <= 0.0 or _energy >= profile.idle_recharge_cap:
		return
	_write_energy(minf(_energy + profile.idle_recharge * delta, profile.idle_recharge_cap))


# --- Interfaz pública (`docs/09` §3.2) --------------------------------------------------------

## Cobra [param amount] de energía. Es **todo o nada**: si no alcanza devuelve
## `false` y no resta nada.
##
## Es el contrato exacto que consume `WeaponMount._consume_energy()` por duck
## typing (`docs/08` §2). Un cobro rechazado tiene que dejar la batería intacta,
## porque si no el arma iría descontando energía por disparos que nunca salen.
func consume(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _depleted or _energy < amount:
		return false
	_write_energy(_energy - amount)
	return true


## Suma [param amount] de energía, con recorte en el máximo del perfil. Es lo que
## llama [BatteryPickup] al recogerse.
func recharge(amount: float) -> void:
	if amount <= 0.0:
		return
	_write_energy(minf(_energy + amount, _max_energy()))


## Resta [param amount] **sin condición** y con recorte en 0, a diferencia de
## [method consume]. Es la vía del EMP y de cualquier castigo que no pueda fallar.
func drain(amount: float) -> void:
	if amount <= 0.0:
		return
	_write_energy(maxf(_energy - amount, 0.0))


## Pulso EMP del jefe (`docs/09` §2.9): resta sin condición, reevalúa el estado en
## el mismo tick y avisa del glitch por [signal emp_hit].
func apply_emp(amount: float, glitch_seconds: float) -> void:
	drain(amount)
	emp_hit.emit(glitch_seconds)


## Energía normalizada, de 0.0 a 1.0. Es lo que viaja por el bus.
func get_ratio() -> float:
	var maximum := _max_energy()
	if maximum <= 0.0:
		return 0.0
	return clampf(_energy / maximum, 0.0, 1.0)


## `true` mientras la energía esté bajo el umbral crítico, con la histéresis de
## salida ya aplicada.
func is_critical() -> bool:
	return _critical


## `true` con la batería a 0 %. Mientras dure, [method consume] rechaza todo y el
## dron no puede armar.
func is_depleted() -> bool:
	return _depleted


## Energía máxima del perfil, en la escala 0–100.
func get_max_energy() -> float:
	return _max_energy()


## Deja la batería en [param value], reevalúa el estado y **siempre** publica. Es
## lo que llama [RespawnController] con `respawn_energy` (`docs/09` §2.8).
func reset(value: float) -> void:
	_energy = clampf(value, 0.0, _max_energy())
	if not _live:
		return
	_refresh_state(true)


## El dron dueño de esta batería.
func get_drone() -> Drone:
	return drone


# --- Estado interno ---------------------------------------------------------------------------

## Punto único de escritura de [member energy]: recorta, reevalúa estado y publica.
##
## La guarda de «no cambió nada» compara por igualdad exacta y **no** con
## `is_equal_approx`: la tolerancia relativa de esa función cerca de 100 es 0.001,
## y el drenaje de un tick a 100 Hz vale `rate / 100`. Con los 0.55 %/s del Anexo C
## son 0.0055 y pasaría, pero si WP-23 bajara `base_drain` por debajo de 0.1 %/s
## cada escritura se descartaría y el drenaje se detendría del todo.
func _write_energy(value: float) -> void:
	var clamped := clampf(value, 0.0, _max_energy())
	if _live and clamped == _energy:
		return
	_energy = clamped
	if not _live:
		return
	_refresh_state(false)


## Reevalúa `CRITICAL` y `DEPLETED` y aplica sus efectos.
##
## El orden importa: primero el crítico —que toca la escala de empuje— y después
## el agotamiento, que además desarma. Con la energía a 0 el dron está por
## definición en crítico, así que un EMP que lleva de 20 % a 0 % entra en los dos
## estados en el mismo tick, tal como pide `docs/09` §2.9.
func _refresh_state(force_publish: bool) -> void:
	var changed := false
	var ratio := get_ratio()

	if profile != null:
		if _critical:
			if ratio >= profile.critical_exit_ratio:
				_critical = false
				changed = true
				_apply_thrust_scale(1.0)
				critical_exited.emit()
		elif ratio < profile.critical_ratio:
			_critical = true
			changed = true
			_apply_thrust_scale(profile.critical_thrust_scale)
			critical_entered.emit()

	if _depleted:
		if _energy > 0.0:
			_depleted = false
			changed = true
			_set_can_arm(true)
	elif _energy <= 0.0:
		_depleted = true
		changed = true
		_set_can_arm(false)
		if drone != null:
			drone.force_disarm()
		depleted.emit()

	_publish(force_publish or changed)


## `Events.energy_changed(ratio, critical)` (`docs/09` §2.10).
##
## Se emite al cambiar de estado y cuando `ratio` se movió al menos
## `publish_epsilon`. El filtro no es cosmético: sin él el drenaje base publicaría
## 100 eventos por segundo y el `EnergyBar` de `docs/12` se redibujaría en cada
## tick de física.
func _publish(force: bool) -> void:
	if not _live:
		return
	var ratio := get_ratio()
	if not force and _published:
		var epsilon := profile.publish_epsilon if profile != null else 0.005
		if absf(ratio - _published_ratio) < epsilon and _critical == _published_critical:
			return
	_published = true
	_published_ratio = ratio
	_published_critical = _critical
	Events.energy_changed.emit(ratio, _critical)


func _apply_thrust_scale(scale: float) -> void:
	if drone == null:
		return
	drone.set_thrust_scale(scale)


## Sube o baja [member FlightController.can_arm_energy] (`docs/03` §3.3): con la
## batería agotada, `arm()` falla con `ERR_ARM_NO_ENERGY`.
##
## Se escribe por duck typing y no con un tipo concreto porque el controlador es
## opcional —un dron de adorno o un banco de pruebas puede no tenerlo— y porque
## este nodo no tiene por qué conocer la clase que implementa la regla de armado.
func _set_can_arm(allowed: bool) -> void:
	if _controller == null:
		_controller = _find_controller()
	if _controller == null:
		return
	_controller.set(&"can_arm_energy", allowed)


func _max_energy() -> float:
	return profile.max_energy if profile != null else 100.0


func _is_armed() -> bool:
	return drone != null and drone.is_armed()


func _throttle() -> float:
	return drone.get_throttle() if drone != null else 0.0


func _find_drone() -> Drone:
	var node := get_parent()
	while node != null:
		var found := node as Drone
		if found != null:
			return found
		node = node.get_parent()
	return null


## Busca el nodo que expone `can_arm_energy`. `Object.get()` devuelve `null` para
## una propiedad que no existe, y `can_arm_energy` es un `bool`: nunca es `null`.
func _find_controller() -> Node:
	if drone == null:
		return null
	var named := drone.get_node_or_null(^"FlightController")
	if named != null and named.get(&"can_arm_energy") != null:
		return named
	for child: Node in drone.get_children():
		if child.get(&"can_arm_energy") != null:
			return child
	return null
