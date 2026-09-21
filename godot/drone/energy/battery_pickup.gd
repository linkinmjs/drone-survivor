## Copyright (c) 2026 Drone Survivor. Todos los derechos reservados.
##
## Pila de energía recogible (`docs/09` §2.4).
##
## Es el **único** [Area3D] de todo el sistema de combate y una de las dos
## excepciones que permite la regla anti-`Area3D` de `docs/02` §3.2 (la otra son
## los volúmenes de ronda). Está en la **capa 7** (`pickup`, 64) con **máscara 2**
## (`drone`), así que solo el dron la ve y ella no ve nada más.
##
## Tres decisiones que vienen del presupuesto de física (`docs/02` §3.2 mide
## 0.39 ms/tick con 218 `Area3D`):
##
## - `monitorable = false`: nadie necesita detectar a la pila, así que no entra en
##   la lista de áreas consultables del espacio.
## - `monitoring` se apaga **en cuanto se recoge**, junto con `visible` y el
##   proceso de física. Una pila inactiva no cuesta nada; con cinco activas el
##   coste es despreciable.
## - La animación de giro y flotación va en [method _physics_process] y no en un
##   [Tween]: un [Tween] sobrevive a `set_physics_process(false)` y seguiría
##   moviendo una pila apagada.
##
## Pertenece al grupo **`pickups`**, que `OffscreenMarkers` (`docs/12`) recorre
## para dibujar las balizas fuera de pantalla.
##
## **Presentación (WP-26)**: la caja emisiva cian de WP-15 ya no está; lo que se
## ve es `vfx/battery_cell.tscn` —celda con casquillo, bandas emisivas `SUCCESS`,
## halo de seis motas y luz suave—, instanciado como hijo `Mesh`. La colisión, la
## capa, la máscara y esta API no cambiaron.
##
## **Discrepancias que quedan con `docs/09` §3.1**: el documento dibuja un
## `PickupSound` ([AudioStreamPlayer3D]) que sigue sin existir, y §2.4 pide la
## malla voxel `assets/drone/battery_cell.glb`, que tampoco: el prop es procedural
## para no traer un asset que haya que licenciar (sala limpia, `docs/01`).
class_name BatteryPickup extends Area3D

## La recogió el dron. [param pickup] es esta misma pila; lo consume
## [BatterySpawner] para liberar el marcador.
signal collected(pickup: BatteryPickup)

## Energía que devuelve, en la escala 0–100 de `docs/09` §2.1.
@export var amount: float = 30.0

## Batería del dron a la que se le suma [member amount]. La inyecta el spawner.
@export var energy_system: EnergySystem

## Amplitud de la oscilación vertical, en metros.
@export_range(0.0, 2.0) var bob_amplitude: float = 0.35

## Ciclos de la oscilación vertical por segundo.
@export_range(0.0, 4.0) var bob_frequency: float = 0.45

## Giro sobre `Y`, en grados por segundo.
@export_range(0.0, 360.0) var spin_degrees: float = 55.0

var _active: bool = false
var _phase: float = 0.0
var _anchor: Vector3 = Vector3.ZERO


func _ready() -> void:
	collision_layer = PhysicsLayers.PICKUP
	collision_mask = PhysicsLayers.DRONE
	monitorable = false
	if not is_in_group(&"pickups"):
		add_to_group(&"pickups")
	if not body_entered.is_connected(_on_body_entered):
		var _discard := body_entered.connect(_on_body_entered)
	_anchor = global_position
	deactivate()


## Giro y flotación. No mueve nada en el mundo físico —la pila es un área, no un
## cuerpo—, así que da igual que corra en el paso de física: lo que importa es que
## se apague con [method deactivate].
func _physics_process(delta: float) -> void:
	if not _active:
		return
	PerfProbe.begin(&"drone_energy")
	_phase = fmod(_phase + delta, 1.0 / maxf(bob_frequency, 0.0001))
	rotate_y(deg_to_rad(spin_degrees) * delta)
	var offset := sin(_phase * TAU * bob_frequency) * bob_amplitude
	global_position = _anchor + Vector3(0.0, offset, 0.0)
	PerfProbe.end(&"drone_energy")


# --- Interfaz pública (`docs/09` §3.4) --------------------------------------------------------

## Enciende la pila en [param at]: visible, detectando y animándose.
func activate(at: Transform3D) -> void:
	global_transform = at
	_anchor = at.origin
	_phase = 0.0
	_active = true
	visible = true
	set_physics_process(true)
	_sync_monitoring()


## Apaga la pila: invisible, sin detección y sin proceso de física.
func deactivate() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	_sync_monitoring()


## Pone [member Area3D.monitoring] al día con [member _active], **en diferido**.
##
## Godot prohíbe escribir `monitoring` mientras se está despachando un
## `body_entered`/`body_exited` —«Function blocked during in/out signal»— y ahí es
## justamente donde se apaga una pila recogida. Lo que se difiere no es el valor
## sino la orden de sincronizar: [method _apply_monitoring] vuelve a leer
## [member _active] al ejecutarse, así que si la pila se apagó y se volvió a
## encender antes del vaciado de la cola, gana el último estado y no el orden en
## que se encolaron las llamadas.
##
## Mientras tanto una pila recién apagada sigue monitoreando unos milisegundos;
## no importa, porque [method _on_body_entered] descarta todo si no está activa.
func _sync_monitoring() -> void:
	if monitoring == _active:
		return
	call_deferred(&"_apply_monitoring")


func _apply_monitoring() -> void:
	monitoring = _active


## `true` mientras la pila esté disponible para recoger.
func is_active() -> bool:
	return _active


## Posición de reposo, sin la oscilación vertical. Es la del marcador que la
## activó y la que viaja en `Events.battery_collected`.
func get_anchor() -> Vector3:
	return _anchor


# --- Recolección ------------------------------------------------------------------------------

## Solo el dron puede recogerla: la máscara ya deja fuera todo lo demás, y la
## comparación contra [member EnergySystem.drone] cubre el caso de que un nivel
## ponga dos cuerpos en la capa 2.
func _on_body_entered(body: Node3D) -> void:
	if not _active or energy_system == null:
		return
	var owner_drone := energy_system.get_drone()
	if owner_drone != null and body != owner_drone:
		return
	var at_position := _anchor
	energy_system.recharge(amount)
	deactivate()
	Events.battery_collected.emit(amount, at_position)
	collected.emit(self)
