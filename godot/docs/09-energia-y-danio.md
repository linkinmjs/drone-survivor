# 09 — Energía y daño

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-15 · Depende de: `docs/02-configuracion-del-proyecto.md`, `docs/03-especificacion-nucleo-de-vuelo.md`, `docs/08-combate-y-armas.md`, `docs/06-framework-de-enemigos.md`

## 1. Objetivo y alcance

Especifica la economía de energía del dron, las pilas y su spawner, la integridad del casco, la tabla de daños recibidos y el ciclo de muerte y respawn con penalización de puntaje. Es la única fuente de verdad para WP-15.

**Incluye**: `EnergySystem`, `EnergyProfile`, `BatteryPickup`, `BatterySpawner`, `Hull`, `HullProfile`, `RespawnController`, la tabla de daño por fuente, la interacción con el `emp_pulse` del jefe, los eventos del bus y el check `energy_check`.

**NO incluye**: el valor del consumo por disparo (`docs/08`, aquí sólo se consume); la física de vuelo ni la implementación de `set_thrust_scale()` (`docs/03`); barras, aviso crítico y glitch de HUD (`docs/12`); el comportamiento del jefe que produce los ataques (`docs/06`, `docs/07`); el multiplicador dentro de la fórmula de puntaje (`docs/11`).

**Reglas duras heredadas del plan**:

- `BatteryPickup` es el **único** `Area3D` de este documento; ningún hitbox es un `Area3D`.
- Todo temporizador de *gameplay* (drenaje, crítico, bloqueo, respawn, reaparición de pilas) se implementa con **acumulador en `_physics_process(delta)`**, nunca con `Timer`. Los `Timer` sólo se admiten para presentación (vida de VFX, desvanecidos). Esto es lo que permite que `energy_check` avance 12 s de simulación en milisegundos.

---

## 2. Diseño

### 2.1 `EnergySystem` — modelo de consumo

`EnergySystem` es un `Node` hijo del `Drone`, cableado por `drone_rig.tscn`. Guarda `energy` en la escala **0–100** (porcentaje), no normalizada, porque todos los valores del Anexo C están en porcentaje y así no hay conversiones dispersas.

Drenaje continuo, sólo con el dron **armado**:

```
drain_rate = base_drain + throttle_drain * drone.get_throttle()      # %/s
```

Con `base_drain = 0.55` y `throttle_drain = 0.85`:

| Situación | `throttle` | Drenaje | Autonomía desde 100 % |
|---|---|---|---|
| Armado en el suelo | 0.00 | 0.55 %/s | 182 s |
| Vuelo estacionario | 0.45 (estimado) | 0.93 %/s | 107 s |
| Acelerador a fondo | 1.00 | 1.40 %/s | 71 s |
| Combate (hover + 4.35 disp/s) | 0.45 | 0.93 + 1.96 = **2.89 %/s** | **35 s** |

El consumo del arma es 0.45 % por disparo; a la cadencia sostenida de 4.35 disparos/s (`docs/08` §2.12) son 1.96 %/s.

**Recarga en reposo (aceptada, 2026-09-19)**: con el dron **desarmado**, `energy` se recupera a `idle_recharge` (1.0 %/s) hasta `idle_recharge_cap` (10 %). Sin esta regla, un dron que llega a 0 % lejos de una pila queda en bloqueo irrecuperable — no puede armar, volar ni alcanzar una pila, y la única salida sería dejarse destruir. Con 10 % hay ~10 s de vuelo, suficiente para llegar a la pila más cercana.

### 2.2 Estados y efectos

```
NORMAL → CRITICAL → DEPLETED
```

| Estado | Condición de entrada | Condición de salida | Efectos |
|---|---|---|---|
| `NORMAL` | inicio, o `ratio >= critical_exit_ratio` | `ratio < critical_ratio` | ninguno |
| `CRITICAL` | `ratio < 0.15` | `ratio >= 0.18` (histéresis) | `drone.set_thrust_scale(0.82)`; `Events.energy_changed(ratio, true)`; aviso en el `CombatHUD`; bus de audio con alarma |
| `DEPLETED` | `energy <= 0.0` | `energy > 0.0` (pila o recarga en reposo) | `drone.force_disarm()`; `depleted()`; el arma deja de poder consumir |

La **histéresis** (entrar a 15 %, salir a 18 %) evita que el aviso y la escala de empuje parpadeen mientras la energía oscila alrededor del umbral con cada disparo. `set_thrust_scale(0.82)` multiplica por 0.82 el empuje máximo disponible: con una relación empuje/peso de ~4:1 el dron sigue volando pero pierde autoridad vertical de forma notoria; la implementación del factor es de `docs/03`, aquí sólo se llama. `Events.energy_changed(ratio, critical)` se emite al cambiar de estado y cuando `ratio` varía ≥ 0.005.

### 2.3 `EnergyProfile`

Todos los números viven en un `Resource` para que WP-23 pueda balancear sin tocar código. Recurso inicial: `drone/energy/profiles/default_energy.tres`.

### 2.4 `BatteryPickup`

`Area3D` en la **capa 7** (`pickup`, valor 64) con **máscara 2** (`drone`, valor 2). Es el único `Area3D` del sistema de combate.

- `CollisionShape3D` con `SphereShape3D` de radio **3.5 m**; `monitorable = false` (nadie necesita detectar a la pila).
- `monitoring = true` **sólo mientras la pila está activa**; al recogerse pasa a `false` junto con `visible = false` y `set_physics_process(false)`. Con 5 activas el coste es despreciable (la medición de referencia es 0.39 ms/tick con 218 `Area3D`, `docs/02` §3.2).
- Presentación: malla voxel propia (`assets/drone/battery_cell.glb`, pipeline de `docs/05`) con material emisivo cian, `OmniLight3D` de 6 m, oscilación vertical ±0.35 m y giro sobre `Y` por `Tween` en bucle, más un `GPUParticles3D` de halo.
- Pertenece al grupo **`pickups`**, que `OffscreenMarkers` (`docs/12`) recorre para las balizas.
- `body_entered(body)` → si `body == energy_system.drone`: `recharge(30)`, `Events.battery_collected(amount, global_position)`, sonido posicional, VFX de absorción, `deactivate()` y `collected(self)` hacia el spawner.

### 2.5 `BatterySpawner`

`Node3D` con **8 hijos `Marker3D`** que definen las posiciones candidatas, repartidas por el distrito (azoteas, cruces, plaza central, borde rocoso). Mantiene **5 activas**.

- `_ready()` recorre sus hijos `Marker3D` en orden y los guarda en un `Array[Marker3D]` tipado; no busca nodos por ruta ni por nombre.
- Activa 5 marcadores al arrancar, elegidos con un `RandomNumberGenerator` sembrado con `Global.round_seed` (determinismo para `energy_check` y rejugabilidad con semilla). Al recogerse una pila, un acumulador de **25 s** reactiva otra en un marcador libre.
- **Comprobación de espacio libre** antes de activar, con `intersect_shape` sobre una `SphereShape3D` de `clearance_radius` (2.5 m) en la posición del marcador:

```gdscript
var params := PhysicsShapeQueryParameters3D.new()
params.shape = _clearance_shape
params.transform = Transform3D(Basis.IDENTITY, marker.global_position)
params.collision_mask = 384          # capas 8 (city) | 9 (debris)
params.collide_with_areas = false
params.collide_with_bodies = true
var blocked := not space.intersect_shape(params, 1).is_empty()
```

> El plan pide «`intersect_shape` en capa 8 para no reaparecer dentro de escombros». Los `DebrisChunk` están en la capa **9** y las ruinas de un `Building` en la capa **8**; se consultan **ambas** (`8|9` = 384) para cubrir la intención completa. Queda registrado como ampliación deliberada.

- Si todos los marcadores libres están bloqueados, se reintenta cada `retry_interval` (1.0 s) hasta encontrar hueco. Nunca se fuerza una aparición dentro de geometría.
- Un marcador que quedó sepultado bajo una ruina deja de usarse de forma natural, sin lógica adicional.

### 2.6 `Hull` — daño por choque

`Hull` es un `Node` hijo del `Drone`. El `Drone` (capa 2, máscara `1|3|4|8|9` = 397) ya tiene `contact_monitor = true` y `max_contacts_reported = 6` por `docs/03`; `Hull` se conecta a su señal `body_entered`.

`body_entered` no informa de la velocidad del impacto y, cuando se emite, Jolt ya resolvió parte de la colisión. Por eso `Hull` guarda la velocidad del tick anterior:

```
v_rel = (drone_prev_velocity - other_velocity).length()
damage = max(0.0, (v_rel - impact_speed_threshold) * impact_damage_per_ms)
```

Con `impact_speed_threshold = 8.0` m/s y `impact_damage_per_ms = 4.0`:

| Velocidad relativa | Daño | Lectura |
|---|---|---|
| ≤ 8 m/s | 0 | aterrizajes y roces |
| 10 m/s | 8 | roce duro |
| 15 m/s | 28 | choque serio |
| 20 m/s | 48 | casi la mitad del casco |
| 25 m/s | 68 | queda al 32 % |
| 33 m/s | 100 | **destrucción instantánea** |

`other_velocity`: `RigidBody3D` → `linear_velocity`; `StaticBody3D` → `constant_linear_velocity`; cualquier otro (`AnimatableBody3D` de las partes del jefe) → `Vector3.ZERO`. Esto **subestima** el daño de una pata que barre a un dron detenido; ese caso lo cubre el daño explícito de `leg_sweep` (§2.7), que el enemigo aplica con `apply_damage()`.

Salvaguardas: **cooldown por cuerpo** de `impact_cooldown` = 0.35 s por `collider_id` (Jolt reemite `body_entered` en contactos rasantes), con un `Dictionary` `{int: float}` purgado al vencer; **umbral mínimo**, se descartan daños < 1.0; y **capa 9 (`debris`)**, donde se usa la fórmula por masa de §2.7 en lugar de la de velocidad para no contar el mismo golpe dos veces.

### 2.7 Tabla de daños recibidos

Todo daño que no proviene de un choque entra por `Hull.apply_damage(amount, source_position)`. El emisor es siempre el enemigo (`docs/06`/`docs/07`) o el `DebrisPool` (`docs/10`).

| Fuente | Daño al casco | Extra | Emisor |
|---|---|---|---|
| Choque contra mundo/ciudad/enemigo | `max(0, (v−8)·4)` | — | `Hull` (colisión) |
| `stomp` | **45** con caída lineal: `45 * (1 − d / 18)` en un radio de 18 m | decal rojo 1.1 s antes (telegrafía) | jefe |
| `leg_sweep` | **60** | `drone.apply_central_impulse(sweep_dir * 40.0)` (40 N·s ≈ 57 m/s en 0.7 kg) | jefe |
| `head_laser` | **8/s** mientras el haz intersecte al dron (`8.0 * delta` por tick) | glitch leve de HUD | jefe |
| `pounce` | **100** (letal por diseño) | `camera_trauma` 1.0 | jefe |
| `shake_off` | **25** | `apply_central_impulse(away_dir * 80.0)` (80 N·s) | jefe |
| `emp_pulse` | **0** | `−25 %` de energía + glitch de HUD 3 s, radio 45 m | jefe |
| `DebrisChunk` (capa 9) | `clamp(remap(mass, 150, 3000, 15, 35), 15, 35)` | — | colisión, fórmula propia |

Todos los impulsos de ataque quedan por debajo del recorte obligatorio de **120 N·s** que impone `docs/06` §11 para que Jolt no expulse al dron del mundo (barrido 40, `shake_off` 80).

El impulso de `leg_sweep` (57 m/s de cambio de velocidad sobre 0.7 kg) por sí solo mata al dron si termina estampado contra un edificio: 57 m/s → `(57−8)·4 = 196` de daño de choque. Está previsto: el barrido es una acción de castigo y hay que esquivarla.

Masa del escombro: `DebrisChunk` publica `mass` (`docs/10`); los trozos de un bloque bajo rondan 450 kg → ≈ **17.1** de daño; un trozo de torre de 2 000 kg → ≈ **28.0**.

### 2.8 Destrucción y respawn

`RespawnController` es un `Node` hijo de `DroneRig` (no del `Drone`), porque debe sobrevivir a la inmovilización del dron. El dron **nunca se libera**: se congela, se teletransporta y se reinicia.

Secuencia, gobernada por un acumulador:

| t | Acción |
|---|---|
| 0.00 s | `hp <= 0` → `Events.hull_changed(0.0)`, `Events.drone_destroyed(position)`, `Events.camera_trauma(1.0, position)` |
| 0.00 s | `drone.force_disarm()`; `drone.freeze_mode = FREEZE_MODE_STATIC`; `drone.freeze = true`; `drone.visible = false`; VFX de explosión (one-shot del `ImpactFXPool` en variante `drone_wreck`) |
| 0.05 s | La cámara pasa a `respawn_camera` (`Camera3D` fijo sobre la ciudad, cableado por el nivel) con `current = true`. El juego **no se pausa**: el jefe sigue destruyendo la ciudad y la integridad sigue bajando. Esa es la penalización real |
| 12.00 s | `drone.global_transform = drone.respawn_point.global_transform`; `linear_velocity = Vector3.ZERO`; `angular_velocity = Vector3.ZERO`; `freeze = false`; `reset_physics_interpolation()`; `visible = true` |
| 12.00 s | `hull.reset()` → `hp = 100`; `energy_system.reset(60.0)`; `weapon_mount.reset()`; cámara de vuelta a `FPVCamera` |
| 12.00 s | `_deaths += 1`; `score_multiplier = maxf(respawn_multiplier_floor, pow(0.6, _deaths))`; `respawned(score_multiplier)` local + `Events.drone_respawned(score_multiplier)`; `Events.hull_changed(1.0)`; `Events.energy_changed(0.6, false)` |

Multiplicador **acumulativo con piso 0.3** (decisión cerrada 2026-09-19): 1 muerte → ×0.6, 2 → ×0.36, 3 o más → ×0.30. `docs/11` lo aplica al puntaje final y mantiene además el castigo de −300 por muerte durante el MVP.

`respawn_point` es `@export var respawn_point: Node3D` del `Drone` (`docs/03` §9), cableado por el nivel. El dron reaparece armado en `false` y con el gatillo soltado: el jugador debe rearmar.

### 2.9 Interacción con el EMP del jefe

El `emp_pulse` del Arachnodroid alcanza 45 m y no hace daño de casco. El jefe llama directamente:

```gdscript
energy_system.apply_emp(profile.emp_drain, profile.emp_glitch_seconds)   # 25.0, 3.0
```

Efectos:

1. `drain(25.0)` — resta sin condición y sin fallar (a diferencia de `consume()`), con recorte en 0.
2. Reevaluación inmediata de estado: si la energía cae bajo 15 % se entra en `CRITICAL` en el mismo tick; si llega a 0 se fuerza el desarme y el dron cae.
3. `Events.energy_changed(ratio, critical)`.
4. Señal local `emp_hit(glitch_seconds)`, a la que se conectan el `CombatHUD` y el overlay FPV (`docs/12`, `docs/13`) para el glitch de 3 s.

> **Decisión**: el glitch se propaga por una **señal local del `EnergySystem`**, no por el bus. El dron no se libera nunca, así que la conexión que hace el nivel al arrancar es estable durante toda la ronda, y se evita añadir un segundo hecho al bus. Alternativa registrada en §6.

### 2.10 Eventos publicados

| Señal de `Events` | Firma canónica de este doc | Emitida por | Consumida por |
|---|---|---|---|
| `energy_changed` | `(ratio: float, critical: bool)` | `EnergySystem` | `EnergyBar` (`docs/12`), audio |
| `hull_changed` | `(ratio: float)` | `Hull` | `HullBar` (`docs/12`) |
| `drone_damaged` | `(amount: float, source_position: Vector3)` | `Hull` | `DamageDirection` (`docs/12`), `CameraRig` |
| `drone_destroyed` | `(position: Vector3)` | `Hull` | `RoundManager` (`docs/11`), VFX |
| `battery_collected` | `(amount: float, position: Vector3)` | `BatteryPickup` | `CombatHUD`, audio |
| `camera_trauma` | `(amount: float, position: Vector3)` | `Hull`, `RespawnController` | `CameraRig` (atenúa por distancia) |

**Respawn**: `RespawnController` emite la señal local `respawned(score_multiplier: float)`, que `DroneRig` reexpone como `DroneRig.respawned` — que es lo que `docs/11` consume — **y además** `Events.drone_respawned(score_multiplier)` para los consumidores desacoplados (`CombatHUD`). La señal de bus figura en el **Contrato de Events** (`docs/02` §5.1) y se declara en `autoloads/events.gd` desde WP-01.

> **Reconciliación cerrada (2026-09-19)**. En Godot 4 un `Callable` conectado a una señal debe aceptar todos los argumentos que ésta emite (puede ignorarlos con `_`, no omitirlos), así que las divergencias eran errores en tiempo de ejecución, no detalles de estilo. Se resolvieron a favor de las firmas largas de este documento, que son las que fija el **Contrato de Events** (`docs/02` §5.1):
>
> | Señal / método | Firma canónica | Qué se corrigió |
> |---|---|---|
> | `energy_changed` | `(ratio: float, critical: bool)` | `docs/12` §4.1 ya consume las dos |
> | `drone_destroyed` | `(position: Vector3)` | `docs/11` §9.3 ya consume el argumento |
> | `camera_trauma` | `(amount: float, position: Vector3)` | `docs/06` §4 y §8.6 y `docs/07` §5 pasan a emitir los dos |
> | `battery_collected` | `(amount: float, position: Vector3)` | el orden era el inverso en §2.4 y en `docs/13` §8 |
> | `Hull.apply_damage(amount, source_position)` | canónica | `docs/06` §11.3 la llamaba `take_damage()`; ahora llama `apply_damage()` |
>
> El motivo de fondo: `critical` lleva la histéresis (si el HUD recalcula el umbral por su cuenta, parpadea en el borde) y `position` permite que el `CameraRig` atenúe el trauma por distancia, que es lo que `docs/10` necesita. `Hull` conserva **`take_damage()` como alias** de `apply_damage()` para código heredado, pero ningún documento lo usa.

---

## 3. Interfaz pública

### 3.1 Escenas y nodos

```
DroneRig                                      drone/drone_rig.tscn
├─ Drone (RigidBody3D, capa 2, máscara 397)   drone/drone.gd
│  ├─ WeaponMount                             docs/08
│  ├─ EnergySystem (Node)                     drone/energy/energy_system.gd
│  └─ Hull (Node)                             drone/damage/hull.gd
└─ RespawnController (Node)                   drone/damage/respawn_controller.gd

BattleLevel
├─ BatterySpawner (Node3D)                    drone/energy/battery_spawner.gd
│  └─ Marker3D ×8
└─ RespawnCamera (Camera3D)                   fija sobre la ciudad

BatteryPickup (Area3D, capa 7, máscara 2)     drone/energy/battery_pickup.tscn
├─ CollisionShape3D (SphereShape3D r = 3.5)
├─ Mesh (MeshInstance3D, emisivo)
├─ Glow (OmniLight3D)
└─ PickupSound (AudioStreamPlayer3D)
```

### 3.2 `EnergySystem`

```gdscript
class_name EnergySystem extends Node
signal depleted()
signal critical_entered()
signal critical_exited()
signal emp_hit(glitch_seconds: float)

@export var profile: EnergyProfile
@export var drone: Drone

var energy: float = 100.0          # 0–100, sólo lectura desde fuera

func consume(amount: float) -> bool          # false y sin efecto si no alcanza
func recharge(amount: float) -> void         # recorta en max_energy
func drain(amount: float) -> void            # sin condición, recorta en 0
func apply_emp(amount: float, glitch_seconds: float) -> void
func get_ratio() -> float                    # energy / max_energy
func is_critical() -> bool
func is_depleted() -> bool
func reset(value: float) -> void             # respawn
```

`consume()` es todo-o-nada: si `energy < amount` devuelve `false` sin restar. `docs/08` depende de ello para no emitir medios disparos.

### 3.3 `EnergyProfile`

```gdscript
class_name EnergyProfile extends Resource
@export_range(1.0, 1000.0) var max_energy: float = 100.0
@export_range(0.0, 10.0) var base_drain: float = 0.55              # %/s armado
@export_range(0.0, 10.0) var throttle_drain: float = 0.85          # %/s a throttle 1.0
@export_range(0.0, 1.0) var critical_ratio: float = 0.15
@export_range(0.0, 1.0) var critical_exit_ratio: float = 0.18
@export_range(0.1, 1.0) var critical_thrust_scale: float = 0.82
@export_range(0.0, 100.0) var battery_amount: float = 30.0
@export_range(0.0, 100.0) var emp_drain: float = 25.0
@export_range(0.0, 10.0) var emp_glitch_seconds: float = 3.0
@export_range(0.0, 10.0) var idle_recharge: float = 1.0            # %/s desarmado
@export_range(0.0, 100.0) var idle_recharge_cap: float = 10.0
@export_range(0.0, 100.0) var respawn_energy: float = 60.0
```

### 3.4 `BatteryPickup` y `BatterySpawner`

```gdscript
class_name BatteryPickup extends Area3D
signal collected(pickup: BatteryPickup)
@export var amount: float = 30.0
@export var energy_system: EnergySystem       # inyectado por el spawner
func activate(at: Transform3D) -> void
func deactivate() -> void
func is_active() -> bool

class_name BatterySpawner extends Node3D
@export var pickup_scene: PackedScene
@export var energy_system: EnergySystem
@export_range(1, 16) var active_target: int = 5
@export_range(0.0, 120.0) var respawn_delay: float = 25.0
@export_range(0.5, 10.0) var clearance_radius: float = 2.5
@export_range(0.1, 10.0) var retry_interval: float = 1.0
@export_flags_3d_physics var clearance_mask: int = 384    # capas 8|9

func get_active_count() -> int
func get_marker_count() -> int
func reset() -> void
```

### 3.5 `Hull`, `HullProfile` y `RespawnController`

```gdscript
class_name Hull extends Node
signal damaged(amount: float, source_position: Vector3)
signal destroyed()

@export var profile: HullProfile
@export var drone: Drone

var hp: float = 100.0

func apply_damage(amount: float, source_position: Vector3) -> void
func take_damage(amount: float, source_position: Vector3) -> void   # alias de apply_damage (docs/06)
func heal(amount: float) -> void
func get_ratio() -> float
func is_destroyed() -> bool
func reset() -> void
```

```gdscript
class_name HullProfile extends Resource
@export_range(1.0, 1000.0) var max_hp: float = 100.0
@export_range(0.0, 50.0) var impact_speed_threshold: float = 8.0
@export_range(0.0, 50.0) var impact_damage_per_ms: float = 4.0
@export_range(0.0, 5.0) var impact_cooldown: float = 0.35
@export_range(0.0, 200.0) var debris_damage_min: float = 15.0
@export_range(0.0, 200.0) var debris_damage_max: float = 35.0
@export_range(1.0, 10000.0) var debris_mass_min: float = 150.0
@export_range(1.0, 10000.0) var debris_mass_max: float = 3000.0
@export_range(0.0, 60.0) var respawn_seconds: float = 12.0
@export_range(0.0, 1.0) var respawn_score_multiplier: float = 0.6
@export_range(0.0, 1.0) var respawn_multiplier_floor: float = 0.3
@export_range(0.0, 2.0) var destroy_trauma: float = 1.0
```

```gdscript
class_name RespawnController extends Node
signal respawned(score_multiplier: float)      # DroneRig la reexpone; docs/11 la consume
@export var drone: Drone
@export var hull: Hull
@export var energy_system: EnergySystem
@export var weapon_mount: WeaponMount
@export var respawn_camera: Camera3D
@export var fpv_camera: Camera3D

func get_score_multiplier() -> float
func get_death_count() -> int
func is_respawning() -> bool
func get_remaining() -> float
func reset() -> void
```

### 3.6 Capas de física usadas

| Elemento | Capa | Máscara | Valores |
|---|---|---|---|
| `Drone` | 2 `drone` | 1,3,4,8,9 | layer 2 / mask **397** |
| `BatteryPickup` | 7 `pickup` | 2 | layer **64** / mask **2** |
| Consulta de espacio libre del spawner | — | 8,9 | mask **384** |
| `DebrisChunk` (referencia, `docs/10`) | 9 `debris` | 1,2,8,9 | layer **256** / mask **387** |

---

## 4. Parámetros y valores iniciales

Del **Anexo A/C** (valores cerrados): `max_energy` 100 · `base_drain` 0.55 %/s armado · `throttle_drain` 0.85 %/s a acelerador pleno · `energy_per_shot` 0.45 % · `critical_ratio` 0.15 con `critical_thrust_scale` 0.82 · `battery_amount` +30 % · `emp_drain` 25 % y `emp_glitch_seconds` 3.0 s · `respawn_energy` 60 % · radio de la pila 3.5 m · spawner de 8 marcadores con 5 activas y `respawn_delay` 25 s · casco `max_hp` 100 con `(v−8)·4` · daño por escombro 15–35 · `respawn_seconds` 12 s con multiplicador 0.6 acumulativo · `contact_monitor` y `max_contacts_reported` 6.

**Propuestas de este documento** (todas en `EnergyProfile` o `HullProfile`):

| Parámetro | Valor | Justificación |
|---|---|---|
| `critical_exit_ratio` | 0.18 | histéresis: sin ella el aviso y la escala de empuje parpadean en el umbral |
| `respawn_multiplier_floor` | 0.3 | el multiplicador acumulativo deja de discriminar por debajo; decisión cerrada con `docs/11` |
| `idle_recharge` / `idle_recharge_cap` | 1.0 %/s / 10 % | evita el bloqueo irrecuperable a 0 % lejos de una pila |
| `clearance_radius` / `retry_interval` | 2.5 m / 1.0 s | la pila no aparece dentro de ruinas ni escombros |
| `impact_cooldown` | 0.35 s | Jolt reemite `body_entered` en contactos rasantes |
| Umbral mínimo de daño por choque | 1.0 | descarta el ruido de los roces |
| `debris_mass_min` / `debris_mass_max` | 150 / 3 000 kg | mapea 15–35 de daño sobre las masas reales de `docs/10` |
| `destroy_trauma` | 1.0 | la muerte sacude al máximo |

---

## 5. Criterios de aceptación y check headless

**Archivo**: `tools/energy_check.tscn` + `tools/energy_check.gd`.

**Comando**:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/energy_check.tscn
```

**Banco de pruebas**: un `DroneStub` (`RigidBody3D`, capa 2, masa 0.7, `contact_monitor = true`, `max_contacts_reported = 6`) con `is_armed()`, `get_throttle()` ajustables y contadores de `force_disarm()` y `set_thrust_scale()`; un `BatterySpawner` con 8 marcadores, uno de ellos tapado por un `StaticBody3D` de capa 8; un `BuildingStub` de capa 8 con un emisor que lo daña 500 HP/s para verificar que la ciudad sufre durante el respawn; un `RespawnPoint` (`Marker3D`) a 40 m.

**Avance de tiempo**: el check desactiva `set_physics_process` de los sistemas bajo prueba y llama a `_physics_process(1.0 / 100.0)` en bucle. Los 12 s del respawn son 1 200 iteraciones y tardan milisegundos.

| # | Sub-check | Criterio |
|---|---|---|
| 1 | `drain_base` | Armado, `throttle = 0`, 10 s → **94.5 ±2 %** relativo (drenaje 5.5) |
| 2 | `drain_throttle` | Armado, 10 s con `throttle = 1.0` → **86.0 ±2 %**; con `throttle = 0.5` → **90.25 ±2 %** |
| 4 | `drain_shot` | 20 llamadas a `consume(0.45)` → baja exactamente **9.0 ±0.01**; con `energy = 0.2` devuelve `false` y no resta |
| 5 | `drain_disarmed` | Desarmado, 10 s desde 50 % → **60.0**; desde 95 % no pasa de 100; el tope de reposo es 10 % (desde 5 % → 10.0, no más) |
| 6 | `battery_pickup` | Energía a 50, `body_entered(drone)` → **80.0 ±0.01**; `Events.battery_collected` emitido **una** vez; el pickup queda con `monitoring == false` y `is_active() == false` |
| 7 | `critical_enter` | Bajar a 14 % → `critical_entered()`, `Events.energy_changed(ratio, true)`, `set_thrust_scale(0.82)` llamado una vez |
| 8 | `critical_hysteresis` | Subir a 16 % → **sigue** en crítico; subir a 19 % → `critical_exited()` y `set_thrust_scale(1.0)`; contar ≤ 2 cambios de escala en todo el barrido |
| 9 | `depleted` | Llegar a 0 % → `force_disarm()` llamado **una** vez, `is_depleted() == true`, `consume()` devuelve `false` |
| 10 | `emp` | Desde 80 %: `apply_emp(25, 3)` → **55.0 ±0.01**, `emp_hit(3.0)` emitido una vez; desde 20 % → 0 %, crítico y desarme en el mismo tick |
| 11 | `hull_impact` | `body_entered` sintético con velocidad previa 20 m/s → daño **48.0 ±0.1**; con 6 m/s → **0**; segundo `body_entered` del mismo cuerpo a los 0.1 s → ignorado (cooldown) |
| 12 | `hull_debris` | Colisión con un cuerpo de capa 9 de 450 kg → daño **17.1 ±0.5**, no `(v−8)·4` |
| 13 | `hull_attack` | `apply_damage(45, p)` → `hp == 55`, `Events.drone_damaged(45, p)`, `Events.hull_changed(0.55 ±0.001)` |
| 14 | `destroy` | `apply_damage(200, p)` → `Events.drone_destroyed` **una** vez, `hp == 0`, `drone.freeze == true`, `force_disarm()` llamado |
| 15 | `respawn_timing` | Avanzando a 100 Hz, el respawn llega a **12.00 s ±0.02**; antes `is_respawning() == true` |
| 16 | `respawn_state` | Tras el respawn: `hp == 100`, `energy == 60`, `global_position ≈ respawn_point` (±0.01 m), `linear_velocity == Vector3.ZERO`, `freeze == false`, arma con `heat == 0` y sin lock |
| 17 | `respawn_penalty` | Multiplicador **0.6**, luego **0.36 ±0.001**, luego **0.30** (piso; `pow(0.6, 3)` = 0.216 queda recortado); emitido por `respawned` y por `Events.drone_respawned` |
| 18 | `city_suffers` | Durante los 12 s el `BuildingStub` pierde ≥ 5 000 HP y `get_tree().paused == false`: el mundo no se congela |
| 19 | `spawner_initial` | Tras 1 s: `get_active_count() == 5` de 8 marcadores |
| 20 | `spawner_refill` | Recoger 2 → 3 activas; avanzar 25 s → **5** de nuevo; nunca más de 5 |
| 21 | `spawner_clearance` | El marcador tapado por el cuerpo de capa 8 **nunca** se usa en 200 s de simulación |
| 22 | `spawner_determinism` | Dos ejecuciones con el mismo `Global.round_seed` activan la misma secuencia de marcadores |
| 23 | `no_area_hitbox` | En el subárbol del `DroneStub` y del jefe de prueba: **0** `Area3D` fuera del grupo `pickups` |
| 24 | `restore` | No escribe en `user://`; restaura `Engine.physics_ticks_per_second` y todo valor de `GameSettings` que toque antes de `quit()` |

Salida: una línea `[PASS]`/`[FAIL]` por sub-check y un resumen. `quit(0)` si todos pasan, `quit(1)` en caso contrario.

---

## 6. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| 1 | **Autonomía en combate de sólo 35 s** | Abierto y es el mayor riesgo de balance del documento. Con 5 pilas activas y 25 s de reaparición hay oferta suficiente, pero el jugador puede pasar más tiempo buscando pilas que peleando. WP-23 puede ajustar `base_drain` a 0.35, `throttle_drain` a 0.60 o `battery_amount` a 40. Todo está en `EnergyProfile`, sin cambios de código |
| 2 | Recarga en reposo (1 %/s hasta 10 %) | **Aceptada (2026-09-19)**. Evita el bloqueo irrecuperable a 0 %. Si más adelante se prefiere el castigo puro, basta `idle_recharge = 0` en el `EnergyProfile` |
| 3 | Canal del glitch de EMP | **Decidido**: señal local `EnergySystem.emp_hit`. Alternativa registrada: añadir `Events.drone_emp(glitch_seconds)` al bus si `docs/12`/`docs/13` necesitan más de un consumidor desacoplado |
| 4 | Firmas de `energy_changed`, `drone_destroyed`, `camera_trauma`, `battery_collected` y nombre de `Hull.apply_damage` | **Cerrado (2026-09-19)**: ganan las firmas largas de este documento, ya recogidas en el Contrato de Events (`docs/02` §5.1). `battery_collected` pasa a `(amount, position)`. `Hull.apply_damage()` es el nombre canónico y `take_damage()` queda como alias |
| 5 | Velocidad de los cuerpos `AnimatableBody3D` del jefe | El daño por colisión los trata como estáticos. Si en pruebas resulta que barridos y pisotones «no se sienten» por colisión, `docs/06` puede publicar la velocidad del mover cinemático en un `set_meta("linear_velocity", v)` que `Hull` lea |
| 6 | Rango de masas del escombro (150–3000 kg) | **Propuesta**; hay que cerrarlo con los valores reales de `BuildingProfile.debris_mass` y de las partes del jefe en `docs/10` y `docs/06` |
| 7 | Cámara de respawn y pilas en azoteas que se derrumban | La cámara fija sobre la ciudad es decisión de `docs/13`, sin impacto en esta interfaz. Un marcador de pila puede quedar flotando si el edificio bajo él pasa a RUBBLE: propuesta de refuerzo, un `intersect_ray` hacia abajo (máscara `1|8`, 60 m) que descarte el marcador sin suelo |

---

## 7. Referencias cruzadas

- `docs/02-configuracion-del-proyecto.md` — capas de física, autoloads, declaración de las señales de `Events`.
- `docs/03-especificacion-nucleo-de-vuelo.md` — `Drone`, `is_armed()`, `get_throttle()`, `force_disarm()`, `set_thrust_scale()`, `respawn_point`, `contact_monitor`. · `docs/05-pipeline-voxel.md` — malla emisiva de la pila.
- `docs/06-framework-de-enemigos.md` — quién llama a `Hull.apply_damage()` y a `apply_emp()`; recorte de impulsos a 120 N·s. · `docs/07-arachnodroid.md` — valores de `stomp`, `leg_sweep`, `head_laser`, `pounce`, `shake_off` y `emp_pulse`.
- `docs/08-combate-y-armas.md` — `energy_per_shot`, `WeaponMount.reset()`, cadencia sostenida que fija el consumo en combate. · `docs/10-ciudad-destructible.md` — `DebrisChunk`, masas, `camera_trauma`.
- `docs/11-rondas-y-objetivos.md` — multiplicador de respawn en el puntaje; derrota por integridad. · `docs/12-interfaz-y-hud.md` — `EnergyBar`, `HullBar`, `DamageDirection`, balizas de pilas, `GlitchLayer.trigger_emp(3.0)`.
- `docs/13-identidad-visual-y-audio.md` — VFX de destrucción, `CameraRig` y atenuación del trauma, overlay FPV. · `docs/15-verificacion-y-ci.md` — convenciones de los checks headless.
