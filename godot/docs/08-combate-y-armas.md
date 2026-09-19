# 08 — Combate y armas

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-14 · Depende de: `docs/02-configuracion-del-proyecto.md`, `docs/03-especificacion-nucleo-de-vuelo.md`, `docs/06-framework-de-enemigos.md`, `docs/09-energia-y-danio.md`, `docs/10-ciudad-destructible.md`

## 1. Objetivo y alcance

Especifica el arma primaria del dron: ciclo de disparo, proyectiles, trazadores, asistencia de puntería, calor, retroceso, impactos y realimentación al HUD. Es la única fuente de verdad para WP-14.

**Incluye**: `WeaponMount`, `WeaponProfile`, `ProjectilePool`, `Projectile`, `TracerRenderer`, `AimAssist`, `MuzzleFlash`, `ImpactFXPool`, la tabla de resolución de impacto por capa de física, los eventos del bus y el check `weapon_check`.

**NO incluye**: drenaje de energía en vuelo y casco (`docs/09`); daño estructural de edificios (`docs/10`); reparto de HP y exposición de puntos débiles (`docs/06`); dibujo del retículo, hitmarkers y barra de calor (`docs/12`); balance final (WP-23); armas secundarias y proyectiles físicos de capa 5 (P3).

**Regla dura heredada del plan**: no se usa ningún `Area3D` como hitbox. Todo impacto se resuelve con `PhysicsDirectSpaceState3D.intersect_ray`.

---

## 2. Diseño

### 2.1 Modelo de disparo

El arma dispara **proyectiles de alta velocidad resueltos por raycast por paso de física**, no hitscan puro (que no permite trazadores creíbles ni tiempo de vuelo a 200 m) ni `RigidBody3D` (un cuerpo por bala, con *tunneling*).

Cada `Projectile` es un `RefCounted` sin nodo. En cada `_physics_process(delta)` (100 Hz) avanza `next = position + velocity * delta` y se resuelve el tramo `position → next` con un `intersect_ray`. A 420 m/s el paso es de **4.2 m**, corto frente a la pieza más fina del juego que puede recibir un disparo (las patas del jefe miden ≥ 1.5 m de sección).

### 2.2 `WeaponMount` — ciclo y máquina de estados

`WeaponMount` es un `Node3D` hijo directo del `Drone` (capa 2), cableado por `drone_rig.tscn`. Dos estados: `READY` (dispara si hay `fire_pressed` y el acumulador venció) y `OVERHEATED` (se entra con `heat >= 1.0` tras un disparo; se sale con `overheat_lock` agotado **y** `heat <= overheat_release`).

`fire_pressed` es un `bool` público que `RadioController` escribe cada frame desde la acción `fire`. `WeaponMount` nunca lee el `InputMap`.

Orden de compuertas dentro de `fire()`, que `weapon_check` verifica por separado: (1) `profile` y pool no nulos; (2) `not is_overheated()`; (3) `drone.is_armed()`; (4) `energy_system.consume(profile.energy_per_shot)` devuelve `true` — si devuelve `false` no consume nada y no sale el disparo. Sólo si las cuatro pasan, `fire()` devuelve `true`.

**Cadencia**: acumulador, no `Timer`. `_shot_accumulator += delta`; mientras supere `1.0 / fire_rate` y las compuertas pasen, dispara y resta el intervalo. Máximo **2 disparos por tick**, para que un *hitch* no produzca una ráfaga instantánea. A 8/s el intervalo son 0.125 s = 12.5 ticks.

**Origen y dirección**: el `Muzzle` (`Marker3D`) está 0.35 m por delante del casco para que el rayo no arranque dentro del dron; la dirección base es `-muzzle.global_basis.z` (en Godot el frente es −Z).

### 2.3 Dispersión creciente en ráfaga

```
_burst_time += delta                      si fire_pressed
_burst_time  = max(0, _burst_time - delta * spread_decay_factor)   si no
spread_deg   = min(spread_max_deg, spread_base_deg + spread_growth_deg * _burst_time)
```

La desviación se muestrea uniforme en área dentro del disco de semiángulo `spread_deg`: se rota `aim_dir` un ángulo `r = spread_deg * sqrt(randf())` alrededor de un eje perpendicular elegido con `randf() * TAU`. El RNG es propio del `WeaponMount` y se siembra con `Global.round_seed`, para que `weapon_check` sea determinista.

Primer disparo desde frío: 0.35°. El tope de 2.2° se alcanza a los 2.1 s de ráfaga; equivale a un radio de ~7.7 m a 200 m y de ~2.3 m a 60 m (distancia típica contra el jefe).

### 2.4 Calor y sobrecalentamiento

`heat` es un `float` normalizado 0–1. Cada disparo suma `heat_per_shot` (0.045); si tras sumar `heat >= 1.0` se pasa a `OVERHEATED`, y **el disparo que cruza el umbral sí sale**. El bloqueo dura `overheat_lock` = 1.8 s y se sale cuando el temporizador vence **y** `heat <= overheat_release` (0.35).

> **Decisión clave**: el enfriamiento corre **sólo con el gatillo suelto o durante el bloqueo**, nunca mientras se sostiene el fuego. A 8 disparos/s el calor gana 0.36/s y el enfriado base es 0.40/s: si enfriara en paralelo, el arma no se bloquearía jamás y el diseño del Anexo C dejaría de tener sentido.

Tasa: `heat_cooldown` 0.40/s, más `heat_cooldown_bonus` 0.15/s cuando `heat < 0.30`, es decir 0.55/s en la banda baja.

`Events.weapon_heat_changed(ratio, overheated)` se emite al cambiar de estado y cuando `ratio` varía ≥ 0.01 (evita 100 emisiones por segundo). Las señales locales `overheated()` / `cooled()` alimentan el audio y el LED del dron.

### 2.5 Retroceso y consumo de energía

Retroceso: impulso central opuesto a la dirección de disparo, `drone.apply_central_impulse(-aim_dir * profile.recoil_impulse)`, con `aim_dir == -muzzle.global_basis.z`.

> **Decisión cerrada**: el plan escribe `-basis.z * recoil_impulse`; se interpreta como «−(dirección de disparo)», o sea `+basis.z`, porque el retroceso empuja al dron **hacia atrás**. `weapon_check` verifica el signo con `linear_velocity.dot(aim_dir) < 0`.

Con 0.9 N·s sobre 0.7 kg, cada disparo cambia la velocidad en 1.29 m/s; a 8 disparos/s son 10.3 m/s² de aceleración retrógrada, comparable a la gravedad. El retroceso **se siente** y obliga a compensar con el acelerador: es intencional. No hay par de retroceso (el impulso es central); la sacudida angular es visual, vía `CameraRig` (`recoil_camera_kick_deg` 0.35°, `docs/13`). La energía (`energy_per_shot` 0.45 %) se consume antes de emitir; detalle en `docs/09`.

### 2.6 `ProjectilePool` y resolución de impacto

`ProjectilePool` es un nodo del nivel (`battle_level.tscn`), no del dron: los proyectiles deben sobrevivir al respawn del dron y compartirse entre todas las fuentes de fuego del jugador. El `WeaponMount` lo recibe con `set_projectile_pool(pool)` durante el cableado del nivel; si no recibe ninguno, crea uno local (esto permite que `weapon_check` y `flight_sandbox` funcionen sin nivel).

256 `Projectile` preasignados en `_ready()`, con lista libre en un `PackedInt32Array` usado como pila (alta y baja en O(1)); nunca se instancia nada en caliente. `spawn()` toma un índice libre y, si no hay, **recicla el más viejo** con un aviso (no debería ocurrir: la ocupación esperada es ~11). El avance y la resolución ocurren en `_physics_process(delta)`, recorriendo sólo los activos. Consulta por proyectil:

```gdscript
var q := PhysicsRayQueryParameters3D.create(prev, next, profile.hit_mask, [shooter_rid])
q.collide_with_areas = false
q.collide_with_bodies = true
q.hit_from_inside = false
var hit := space.intersect_ray(q)
```

`hit_mask` = capas `1|3|4|8|9` → **397** (`1+4+8+128+256`). La capa 2 (`drone`) **no** está en la máscara, así que el dron es inmune a su propio fuego por construcción; la exclusión del RID se mantiene como defensa en profundidad, por si el `Muzzle` queda dentro del casco tras un choque. `collide_with_areas = false` es obligatorio: evita que las `BatteryPickup` intercepten balas.

Sin impacto: `position = next`, `ttl -= delta`, y se libera si `ttl <= 0`. `ttl` inicial = `max_range / projectile_speed` = 600 / 420 ≈ **1.43 s**. Sin gravedad ni arrastre en el MVP.

**Diccionario de impacto**: el arma lo rellena **antes** de llamar a `EnemyPart.take_damage`, con exactamente las claves del contrato de `docs/06` §14.1.

| Clave | Tipo | Origen |
|---|---|---|
| `position` | `Vector3` | `intersect_ray` |
| `normal` | `Vector3` | `intersect_ray` |
| `direction` | `Vector3` | dirección del disparo, normalizada |
| `source` | `Node3D` | el `WeaponMount` emisor |
| `is_weak_point` | `bool` | `true` si el `collider` estaba en la capa 4 |
| `weak_point_id` | `StringName` | sólo si `is_weak_point` (`collider.get_meta`) |
| `damage_type` | `StringName` | `&"kinetic"` |

El resolvedor añade además `collider`, `collider_id`, `rid`, `shape`, `damage`, `distance` y `from` para su propio uso interno.

`EnemyPart.take_damage(amount, hit) -> float` **devuelve el daño efectivo** (`docs/06`); el resolvedor lo usa para el HUD y no necesita escribir nada de vuelta. La letalidad se consulta después con `part.is_broken()`.

### 2.7 Tabla de resolución de impacto por capa

| Capa del `collider` | Cómo se identifica | Daño que pasa el arma | Efectivo | Efecto | `HitKind` |
|---|---|---|---|---|---|
| 3 `enemy_body` | `get_meta("part_id")` → `EnemyPart` | `12` | `12 × (1 − 0.90)` = **1.2** | chispas metálicas, sin decal | `ARMOR` |
| 4 `enemy_weak` | `get_meta("weak_point_id")` → parte hospedadora | `12 × 3.0` = **36** | **36** (la parte débil tiene `armor = 0`) | chispas ámbar + destello | `WEAK` |
| 8 `city` | `collider as Building` | `12 × 0.5` = **6** a `Building.take_damage(amount, point)` | 6 | polvo + decal; suma a `friendly_fire_damage` | `ARMOR` atenuado |
| 9 `debris` | `collider as RigidBody3D` | 0 | 0 | `apply_impulse(direction * debris_impulse, hit.position − collider.global_position)` | ninguno |
| 1 `world` | cualquier `StaticBody3D` | 0 | 0 | chispas + **decal** | ninguno |

Notas:

- **El arma aplica el multiplicador de punto débil; `EnemyPart` aplica el blindaje.** Nunca al revés y nunca los dos el mismo factor (`docs/06` §5). Que un impacto débil valga 36 y no 3.6 depende de que el perfil de la parte hospedadora del punto débil tenga `armor = 0.0`: es un **requisito sobre `docs/06`/`docs/07`**, no sobre el arma.
- La capa 4 tiene prioridad implícita: un punto débil expuesto *no está* en la capa 3 (`docs/06`), así que el rayo devuelve un único `collider` sin ambigüedad.
- Si un `collider` de capa 3 no tiene `part_id`, se trata como `world` y se registra un aviso: es un error de importación.
- `friendly_fire_damage` se acumula en `ProjectilePool` (`get_friendly_fire_damage() -> float`) y lo lee `RoundManager` al cerrar la ronda. **Propuesta**: `−0.02 × friendly_fire_damage` puntos. Se prefiere esta métrica cruda a añadir una señal al bus. `city_friendly_fire_scale` (0.5) evita que el jugador demuela la ciudad más rápido que el jefe.

### 2.8 `AimAssist`, `lock_target` y `cycle_target`

`AimAssist` es un `RefCounted` propiedad del `WeaponMount`. No tiene nodo ni proceso propio: el `WeaponMount` lo refresca a 20 Hz.

Candidatos: los nodos del grupo `weak_points`, donde `EnemyBase` mantiene **sólo los expuestos** (`docs/06`); un punto débil que deja de estar expuesto sale del grupo y, con él, de la asistencia y del lock.

Filtro y selección: (1) distancia ≤ `aim_assist_max_range` (220 m); (2) ángulo entre `aim_dir` y `(target.global_position − origin)` ≤ `aim_assist_cone_deg` (3.5°); (3) línea de visión con `intersect_ray` de máscara `1|8` = **129** excluyendo el RID del dron, descartando si hay obstrucción; (4) gana el de menor ángulo y, a igualdad de ±0.1°, el más cercano.

Corrección aplicada en el instante del disparo, **antes** de la dispersión:

```gdscript
corrected = aim_dir.slerp(origin.direction_to(target.global_position), strength).normalized()
```

`strength` sale de la opción del menú `GameSettings.aim_assist`, no del perfil: `OPT_AIM_ASSIST_OFF` → 0.00, `OPT_AIM_ASSIST_SUBTLE` → 0.35 (por defecto), `OPT_AIM_ASSIST_ASSISTED` → 0.60.

**Lock**: `lock_target()` fija el mejor candidato dentro de un cono ampliado `lock_cone_deg` (12°, propuesta). Mientras hay lock, la asistencia ignora el cono estrecho y apunta siempre al objetivo fijado, y el retículo dibuja un marcador sobre él (`docs/12`). El lock se rompe si el `WeakPoint` sale del grupo `weak_points`, si el ángulo supera `lock_break_angle` (35°, propuesta), si la distancia supera `lock_break_range` (250 m, propuesta) o si el nodo deja de ser válido. `cycle_target()` rota entre los candidatos del cono ampliado ordenados por ángulo; si no hay lock, equivale a `lock_target()`.

Acciones de entrada: `lock_target` y `cycle_target`, definidas en WP-01 (`docs/02`).

### 2.9 `TracerRenderer`

`MultiMeshInstance3D` hijo de `ProjectilePool`, **una sola llamada de dibujo**. `transform_format = TRANSFORM_3D`, `use_custom_data = true`, `instance_count = 96`, `cast_shadow = OFF`, `gi_mode = DISABLED`. Malla: `QuadMesh` unitario con `tracer.gdshader` (`render_mode unshaded, blend_add, cull_disabled, depth_draw_never`), orientado a cámara en el vértice.

- **`INSTANCE_CUSTOM`** = `Color(life, length_scale, 0, 0)`, con `life` de 1.0 a 0.0 según la edad del proyectil. El shader hace `ALPHA *= INSTANCE_CUSTOM.r`: **no hay lógica de desvanecido en GDScript**.
- Transformada por instancia: origen en la posición actual del proyectil, eje `+Y` local alineado a `velocity.normalized()`, escala `(0.08, 6.0, 1)` m.
- El nodo mantiene `transform == Transform3D.IDENTITY`; todas las instancias se escriben en coordenadas de mundo.
- Cada tick se **compactan** los vivos al principio del búfer y se fija `visible_instance_count = _live_tracers`; sin esto quedan instancias fantasma.
- `tracer_every = 3` (`_shot_index % 3 == 0`): ocupación esperada 11.4 / 3 ≈ 4 trazadores.

### 2.10 VFX de boca e impacto

**`MuzzleFlash`** (`drone/weapons/muzzle_flash.tscn`), hijo del `WeaponMount`, uno solo: `GPUParticles3D` con `one_shot = true`, `explosiveness = 1.0`, `amount = 12`, `lifetime = 0.08`, `local_coords = true`, relanzado con `restart()` en cada disparo (a 0.125 s no hay solape); `OmniLight3D` hija de `omni_range = 6.0` ámbar con pulso de `light_energy` 0 → 3.5 → 0 en 0.06 s por un único `Tween` reutilizado (`kill()` antes de recrear); `AudioStreamPlayer3D` en el bus `Weapons`, `unit_size` 12 m, `pitch_scale` ±4 %.

**`ImpactFXPool`** (`drone/weapons/impact_fx_pool.gd`), nodo del nivel, **16 instancias** preasignadas de `impact_fx.tscn`, con variante elegida por `set_variant(layer)` (`metal`, `concrete`, `ground`, `debris`) en vez de una escena por material:

- Chispas: `GPUParticles3D` `one_shot`, `amount = 16`, `lifetime = 0.35`, `explosiveness = 1.0`, emisión según `hit.normal`.
- `Decal`: **sólo en capas 1 y 8**, `size` 0.8³, `albedo_mix` 0.9, `distance_fade_begin` 40 m, vida 8 s con desvanecido por `Tween`; máximo 32 simultáneos, se recicla el más viejo.
- `AudioStreamPlayer3D` posicional con el sonido de la variante.

### 2.11 Eventos publicados y `HitKind`

| Señal de `Events` | Firma canónica de este doc | Emitida por | Consumida por |
|---|---|---|---|
| `shot_fired` | `(origin: Vector3, direction: Vector3)` | `WeaponMount` | precisión del resultado (`docs/11`), audio |
| `weapon_heat_changed` | `(ratio: float, overheated: bool)` | `WeaponMount` | `HeatGauge` (`docs/12`) |
| `hit_confirmed` | `(position: Vector3, weak: bool, lethal: bool)` | `ProjectilePool` | `HitMarker` (`docs/12`) |

`lethal` se obtiene llamando a `part.is_broken()` justo después de `take_damage()`.

**Enum compartido** que `docs/12` §4.1 (fila `HitMarker`) pide que defina este documento:

```gdscript
enum HitKind { ARMOR = 0, WEAK = 1, PART_BROKEN = 2 }   # en weapon_mount.gd
```

Derivación desde los argumentos de `hit_confirmed`, sin información extra:

| `weak` | `lethal` | `HitKind` | Marca del HUD |
|---|---|---|---|
| `false` | `false` | `ARMOR` | ✕ blanco 18 px |
| `true` | `false` | `WEAK` | ✕ ámbar 18 px |
| cualquiera | `true` | `PART_BROKEN` | ✕ rojo 22 px |

> **Reconciliación cerrada (2026-09-19)**: ganan las firmas largas de la tabla de arriba, que son las que fija el **Contrato de Events** (`docs/02` §5.1): `shot_fired(origin, direction)` y `hit_confirmed(position, weak, lethal)`. El enum `HitKind` **no viaja por el bus**: `docs/12` lo deriva de `weak`/`lethal` con la tabla de abajo. En Godot 4 un `Callable` conectado debe aceptar todos los argumentos de la señal (puede ignorarlos con `_`, no omitirlos), por eso ningún consumidor puede conectar una versión corta.

### 2.12 Matemática esperada

Valores que WP-14 debe reproducir y que `weapon_check` verifica parcialmente:

| Magnitud | Cálculo | Valor |
|---|---|---|
| Intervalo entre disparos | `1 / 8` | 0.125 s |
| Disparos hasta el bloqueo desde frío | `ceil(1.0 / 0.045)` | **23** (22 dejan `heat` en 0.990), 2.75 s de ráfaga |
| Calor al salir del bloqueo | `1.035 − 0.40 × 1.8` | 0.315 |
| Disparos por ráfaga en régimen | `ceil((1.0 − 0.315) / 0.045)` | **16** en 1.875 s |
| Ciclo sostenido y cadencia efectiva | `1.875 + 1.8` → `16 / 3.675` | 3.675 s → **4.35 disparos/s** (54 % de la nominal) |
| Enfriado completo desde 1.035 | `(1.035−0.3)/0.40 + 0.3/0.55` | 2.38 s |
| DPS contra punto débil: nominal / sostenido | `8 × 36` / `4.35 × 36` | 288/s / 156.6/s |
| DPS efectivo (40 % de aciertos) | `156.6 × 0.40` | **62.6/s** ≈ los 63/s del Anexo A |
| DPS sostenido contra blindaje 0.90 | `4.35 × 1.2` | 5.2/s → 12 000 HP serían 38 min: blindaje inviable por diseño |
| Impactos para romper una rodilla (1 200 HP) | `1200 / 36` | 34 impactos ≈ 19.5 s de combate efectivo |
| Energía por segundo disparando | `4.35 × 0.45` | 1.96 %/s (ver `docs/09`) |

---

## 3. Interfaz pública

### 3.1 Escenas y nodos

```
Drone (RigidBody3D, capa 2)                  drone/drone.gd
└─ WeaponMount (Node3D)                      drone/weapons/weapon_mount.gd
   ├─ Muzzle (Marker3D)                      −Z 0.35 m
   ├─ MuzzleFlash (GPUParticles3D one_shot)  drone/weapons/muzzle_flash.tscn
   │  └─ FlashLight (OmniLight3D)
   └─ FireSound (AudioStreamPlayer3D)        bus Weapons

BattleLevel                                  rounds/battle_level.tscn
├─ ProjectilePool (Node)                     drone/weapons/projectile_pool.gd
│  └─ TracerRenderer (MultiMeshInstance3D)   drone/weapons/tracer_renderer.gd
└─ ImpactFXPool (Node3D)                     drone/weapons/impact_fx_pool.gd
   └─ ImpactFX ×16                           drone/weapons/impact_fx.tscn
```

`ProjectilePool` es un `Node`; `TracerRenderer` es un `MultiMeshInstance3D` con transformada identidad, lo que es legal y correcto porque todas las instancias se escriben en coordenadas de mundo.

### 3.2 `WeaponMount`

```gdscript
class_name WeaponMount
extends Node3D

signal fired(origin: Vector3, direction: Vector3)
signal overheated()
signal cooled()

@export var profile: WeaponProfile
@export var drone: Drone
@export var energy_system: EnergySystem
@export var muzzle: Marker3D
@export var muzzle_flash: GPUParticles3D
@export var fire_sound: AudioStreamPlayer3D

var fire_pressed: bool = false

func fire() -> bool
func set_profile(new_profile: WeaponProfile) -> void
func set_projectile_pool(pool: ProjectilePool) -> void
func set_aim_assist_mode(mode: StringName) -> void      # &"off" | &"subtle" | &"assisted"
func get_heat_ratio() -> float
func is_overheated() -> bool
func get_aim_direction() -> Vector3                      # ya corregida por AimAssist
func get_spread_deg() -> float
func lock_target() -> void
func cycle_target() -> void
func get_locked_weak_point() -> Node3D                    # null si no hay lock
func reset() -> void                                      # respawn: calor 0, ráfaga 0, sin lock
```

### 3.3 `WeaponProfile`

```gdscript
class_name WeaponProfile
extends Resource

@export var id: StringName = &"mk1_repeater"
@export var display_key: String = "WPN_MK1_REPEATER"
@export_range(0.5, 30.0) var fire_rate: float = 8.0
@export_range(0.0, 200.0) var damage: float = 12.0
@export_range(1.0, 10.0) var weak_point_multiplier: float = 3.0
@export_range(50.0, 2000.0) var projectile_speed: float = 420.0
@export_range(10.0, 2000.0) var max_range: float = 600.0
@export_range(0.0, 10.0) var spread_base_deg: float = 0.35
@export_range(0.0, 10.0) var spread_growth_deg: float = 0.9
@export_range(0.0, 15.0) var spread_max_deg: float = 2.2
@export_range(0.0, 20.0) var spread_decay_factor: float = 3.0
@export_range(0.0, 1.0) var heat_per_shot: float = 0.045
@export_range(0.0, 5.0) var heat_cooldown: float = 0.40
@export_range(0.0, 5.0) var heat_cooldown_bonus: float = 0.15
@export_range(0.0, 1.0) var heat_cooldown_bonus_threshold: float = 0.30
@export_range(0.0, 10.0) var overheat_lock: float = 1.8
@export_range(0.0, 1.0) var overheat_release: float = 0.35
@export_range(0.0, 10.0) var energy_per_shot: float = 0.45
@export_range(0.0, 20.0) var recoil_impulse: float = 0.9
@export_range(0.0, 20.0) var aim_assist_cone_deg: float = 3.5
@export_range(0.0, 1.0) var aim_assist_strength: float = 0.35
@export_range(0.0, 60.0) var aim_assist_max_range: float = 220.0
@export_range(0.0, 45.0) var lock_cone_deg: float = 12.0
@export_range(1, 12) var tracer_every: int = 3
@export_range(16, 512) var pool_size: int = 256
@export_range(0.0, 2.0) var city_friendly_fire_scale: float = 0.5
@export_range(0.0, 10.0) var debris_impulse: float = 0.6
@export_flags_3d_physics var hit_mask: int = 397          # capas 1|3|4|8|9
@export_flags_3d_physics var los_mask: int = 129          # capas 1|8
@export var muzzle_flash_scene: PackedScene
@export var impact_fx_scene: PackedScene
@export var fire_sound: AudioStream
@export var overheat_sound: AudioStream
```

Recurso inicial: `drone/weapons/profiles/mk1_repeater.tres`.

### 3.4 `Projectile`, `ProjectilePool`, `TracerRenderer`, `AimAssist`

```gdscript
class_name Projectile
extends RefCounted

var position: Vector3
var velocity: Vector3
var ttl: float
var damage: float
var weak_multiplier: float
var shooter_rid: RID
var age: float
var life: float          # ttl inicial, para el fade del trazador
var tracer_slot: int     # −1 si no lleva trazador
var active: bool
```

```gdscript
class_name ProjectilePool
extends Node

@export var tracer_renderer: TracerRenderer
@export var impact_fx_pool: ImpactFXPool
@export var profile: WeaponProfile

func spawn(origin: Vector3, direction: Vector3, damage: float,
        weak_multiplier: float, shooter_rid: RID, with_tracer: bool) -> bool
func get_active_count() -> int
func get_free_count() -> int
func get_friendly_fire_damage() -> float
func clear() -> void
```

```gdscript
class_name TracerRenderer extends MultiMeshInstance3D
func acquire() -> int                    # −1 si no hay hueco
func write(slot: int, origin: Vector3, direction: Vector3, life_ratio: float) -> void
func release(slot: int) -> void
func get_live_count() -> int

class_name AimAssist extends RefCounted
func configure(cone_deg: float, strength: float, max_range: float, los_mask: int) -> void
func refresh(origin: Vector3, aim_dir: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void
func get_target() -> Node3D
func get_candidates() -> Array[Node3D]
func apply(origin: Vector3, aim_dir: Vector3) -> Vector3
func set_lock(target: Node3D) -> void
func clear_lock() -> void
```

### 3.5 Capas de física usadas

| Uso | Capas | Valor `collision_mask` |
|---|---|---|
| Rayo de proyectil | `1 world`, `3 enemy_body`, `4 enemy_weak`, `8 city`, `9 debris` | **397** |
| LOS de la asistencia | `1 world`, `8 city` | **129** |
| Cuerpo del dron (excluido por RID) | `2 drone` | 2 |

---

## 4. Parámetros y valores iniciales

Del **Anexo C** (valores cerrados): `fire_rate` 8/s · `damage` 12 · `weak_point_multiplier` 3.0 · `projectile_speed` 420 m/s · `spread` 0.35° base, +0.9°/s, tope 2.2° · `heat_per_shot` 0.045 · `heat_cooldown` 0.40/s (+0.15 bajo 0.30) · `overheat_lock` 1.8 s · `energy_per_shot` 0.45 % · `recoil_impulse` 0.9 N·s · `aim_assist_cone_deg` 3.5° · `aim_assist_strength` 0 / 0.35 / 0.6 · `tracer_every` 3 · `pool_size` 256.

**Propuestas de este documento** (todas en el `Resource`, ajustables sin tocar código):

| Parámetro | Valor | Justificación |
|---|---|---|
| `max_range` / `ttl` | 600 m / 1.43 s | cubre el distrito de 360 × 216 m con margen |
| `spread_decay_factor` | 3.0 | la ráfaga se «olvida» en ~0.7 s |
| `overheat_release` | 0.35 | el calor cae a 0.315 en los 1.8 s de bloqueo: manda el temporizador |
| `aim_assist_max_range` | 220 m | más allá el jefe no es un objetivo legible |
| `lock_cone_deg` / `lock_break_angle` / `lock_break_range` | 12° / 35° / 250 m | el lock aguanta una maniobra evasiva completa |
| Trazadores: instancias / largo / ancho | 96 / 6.0 m / 0.08 m | 256 / 3 con margen |
| `city_friendly_fire_scale` | 0.5 | 170 impactos por bloque bajo (`docs/10` §8) |
| `debris_impulse` | 0.6 N·s | mueve un trozo sin lanzarlo |
| Desplazamiento del `Muzzle` | 0.35 m en −Z | el rayo no arranca dentro del casco |
| `ImpactFXPool` / decals | 16 instancias / 32 decals de 8 s | acota el coste de VFX (`vfx_check`) |
| Refresco de `AimAssist` | 20 Hz | 1 consulta de LOS por candidato y tick |

---

## 5. Criterios de aceptación y check headless

**Archivo**: `tools/weapon_check.tscn` + `tools/weapon_check.gd`.

**Comando**:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/weapon_check.tscn
```

**Banco de pruebas**: un `DroneStub` (`RigidBody3D`, capa 2, masa 0.7, `gravity_scale = 0`, `linear_damp = 0`) con `is_armed()`, `get_throttle()`, `force_disarm()` y `set_thrust_scale()`; un `EnergyStub` con `consume()` configurable; cuatro `StaticBody3D` a 50 m en las capas **3** (meta `part_id`, `EnemyPartStub` con `armor` 0.90), **4** (meta `weak_point_id`, `armor` 0.0), **8** (`BuildingStub`) y **1** (`WorldStub`); y un `WeakPointStub` en el grupo `weak_points`.

**El tiempo se avanza sintéticamente**: el check desactiva `set_physics_process` y llama a `_physics_process(1.0 / 100.0)` en bucle. Por eso ningún temporizador de gameplay del arma puede ser un `Timer` (sólo se admiten para presentación: vida de decals y VFX).

| # | Sub-check | Criterio |
|---|---|---|
| 1 | `cadence` | Con `heat_per_shot = 0`, gatillo sostenido 10 s → **80 ±1** emisiones de `Events.shot_fired`; intervalos de 0.125 s ±1 tick |
| 2 | `spread_cold` | Primer disparo desde frío: ángulo respecto de `aim_dir` ≤ 0.35° |
| 3 | `spread_growth` | 60 disparos sostenidos: media angular de los 10 últimos > media de los 10 primeros; máximo ≤ 2.2° + 0.01 |
| 4 | `heat_lock` | Disparos hasta `overheated()` ∈ [22, 23]; `fire()` devuelve `false` durante el bloqueo; `cooled()` a 1.8 s ±0.05; calor al desbloquear ≤ 0.35 |
| 5 | `heat_event` | `Events.weapon_heat_changed` emitido con `overheated == true` y luego `false`; ≤ 120 emisiones en los 10 s de la prueba |
| 6 | `damage_layer_3` | `EnemyPartStub.take_damage` recibe `amount == 12.0`, devuelve **1.2 ±0.01** (`armor` 0.90); `hit["is_weak_point"] == false`; `HitKind.ARMOR` |
| 7 | `damage_layer_4` | Recibe `amount == 36.0` y devuelve **36.0 ±0.01** (`armor` 0.0); `hit["is_weak_point"] == true` y `hit["weak_point_id"]` presente; `HitKind.WEAK`; con `is_broken()` → `HitKind.PART_BROKEN` |
| 7b | `hit_dict` | El `Dictionary` que llega a `take_damage` trae **exactamente** las 7 claves del contrato de `docs/06` §14.1, con `source == weapon_mount` y `damage_type == &"kinetic"` |
| 8 | `damage_layer_8` | `BuildingStub.take_damage(6.0 ±0.01, point)`; `get_friendly_fire_damage() == 6.0 × nº impactos` |
| 9 | `damage_layer_1` | 0 daño; se solicita exactamente 1 decal al `ImpactFXPool` |
| 10 | `recoil` | 20 disparos: `linear_velocity.dot(aim_dir) < 0` y `|Δv| ≈ 20 × 0.9 / 0.7 = 25.7 m/s` ±10 % |
| 11 | `energy_gate` | Con `EnergyStub.consume()` devolviendo `false`: `fire()` devuelve `false`, 0 proyectiles, 0 `shot_fired` |
| 12 | `disarmed_gate` | Con `is_armed() == false`: `fire()` devuelve `false` |
| 13 | `orphans` | Tras 100 disparos + 3 s de asentamiento: `get_active_count() == 0`, `get_free_count() == 256`, `tracer_renderer.get_live_count() == 0`, `multimesh.visible_instance_count == 0` |
| 14 | `tracers` | Exactamente **1** `MultiMeshInstance3D` en el subárbol de trazadores; `use_custom_data == true`; `instance_count == 96`; con 6 trazadores vivos `visible_instance_count == 6`; `INSTANCE_CUSTOM.r` decreciente con la edad; 1 de cada 3 disparos lleva trazador ±1 |
| 15 | `aim_assist` | Objetivo a 3.0° y 60 m con `strength = 0.35` → ángulo residual **1.95° ±0.1**; con `strength = 0` → sin cambio; objetivo a 5.0° (fuera del cono de 3.5°) → no seleccionado; objetivo tapado por un cuerpo de capa 8 → descartado |
| 16 | `lock` | `lock_target()` fija el más cercano; `cycle_target()` rota; al sacar el `WeakPoint` del grupo `weak_points`, `get_locked_weak_point() == null` |
| 17 | `no_self_hit` | Disparando con el `Muzzle` dentro del volumen del `DroneStub`: 0 impactos sobre la capa 2 |
| 18 | `restore` | El check no escribe en `user://`; si modifica `GameSettings.aim_assist` en memoria, restaura el valor previo antes de `quit()` |

> El **≤ 1 draw call de trazadores** se verifica estructuralmente (sub-check 14) porque `--headless` usa el controlador de render nulo y los contadores de `RenderingServer` no son fiables. La medición real de draw calls corresponde a `render_check` (WP-24, `docs/15`).

Salida: una línea `[PASS]`/`[FAIL]` por sub-check y un resumen. `quit(0)` si todos pasan, `quit(1)` con el recuento de fallos en caso contrario.

---

## 6. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| 1 | **Firmas de `shot_fired` y `hit_confirmed`** | **Cerrado (2026-09-19)**: `shot_fired(origin, direction)` y `hit_confirmed(position, weak, lethal)` en `docs/02` §5.1; `docs/11` y `docs/12` ya están alineados y el enum `HitKind` se deriva en el HUD (ver §2.11) |
| 2 | Signo del retroceso | **Cerrado**: el impulso es `-aim_dir * recoil_impulse`. Lo verifica el sub-check 10 |
| 3 | `armor = 0.0` en las partes hospedadoras de puntos débiles | **Requisito sobre `docs/06`/`docs/07`**. Si allí quedara en 0.90, el daño débil sería 3.6 en vez de 36 y el jefe sería inderrotable |
| 4 | El retroceso a 10.3 m/s² puede volver el vuelo inmanejable en ACRO | Abierto: WP-23 puede bajar `recoil_impulse` a 0.6 o repartirlo en 2 ticks. Es un `Resource` |
| 5 | Sin caída balística del proyectil | Decidido para el MVP; `Projectile.velocity` ya es un vector si en P3 se integra la gravedad |
| 6 | Penalización por fuego amigo | **Propuesta** `−0.02 × friendly_fire_damage`; el coeficiente lo fija `docs/11` |
| 7 | 256 proyectiles × 1 `intersect_ray` a 100 Hz | Ocupación esperada 11; peor caso 25 600 rayos/s. Si `docs/15` lo marca, se baja el pool a 96 |
| 8 | La asistencia con `slerp` puede «pegarse» con dos puntos débiles casi alineados | Mitigado por el desempate por distancia y el refresco a 20 Hz; revisar en el smoke test manual |

---

## 7. Referencias cruzadas

- `docs/02-configuracion-del-proyecto.md` — capas de física, acciones `fire` / `fire_alt` / `lock_target` / `cycle_target`, declaración de `Events`.
- `docs/03-especificacion-nucleo-de-vuelo.md` — `Drone`, `is_armed()`, `get_throttle()`, `apply_central_impulse`, `RadioController`.
- `docs/06-framework-de-enemigos.md` — `EnemyPart.take_damage(amount, hit) -> float`, `is_broken()`, contrato del `Dictionary` `hit` (§14.1), metadatos `part_id` / `weak_point_id`, grupo `weak_points`.
- `docs/07-arachnodroid.md` — HP de rodillas, visor y núcleo; validación del tiempo de combate.
- `docs/09-energia-y-danio.md` — `EnergySystem.consume()`, `Hull`, respawn. · `docs/10-ciudad-destructible.md` — `Building.take_damage(amount, point)`, `DebrisChunk`, fuego amigo.
- `docs/11-rondas-y-objetivos.md` — puntaje, precisión, uso de `friendly_fire_damage`. · `docs/12-interfaz-y-hud.md` — retículo, `HitMarker`, `HeatGauge`, marcador de lock, enum `HitKind`.
- `docs/13-identidad-visual-y-audio.md` — materiales de trazador e impacto, bus `Weapons`, sacudida de cámara. · `docs/15-verificacion-y-ci.md` — checks headless y medición de draw calls.
