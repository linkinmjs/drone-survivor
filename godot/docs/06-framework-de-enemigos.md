# 06 — Framework de enemigos

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-16, WP-17, WP-18 (y es el contrato de P3: WP-31…WP-39) · Depende de: `docs/05-pipeline-voxel.md`, `docs/02-configuracion-del-proyecto.md`

## 1. Objetivo y alcance

> **Nota del cierre de la revisión (2026-09-20)**: `Telegraph` devuelve su efecto espacial al `VFXPool` también en `NOTIFICATION_EXIT_TREE` (antes solo en `_shutdown()` tras el fundido); `EnemyPart._spawn_detach_fx()` marca `claim_part_fx()` solo si el pool sirvió el efecto.

> **Nota de WP-29 (2026-09-20)**: `rig_tick` (rig procedural de patas) cuesta **0,151 ms por tick** con ciudad y **0,194 ms = 62 % de la fase de callbacks** en `boss` sin ciudad: los rayos del IK son lo caro y las patas apoyadas no necesitan un rayo por tick (candidato P3, no hecho; `gait_check` es el juez). `EnemyBase.get_parts()` devuelve la lista cacheada y `_exposure_context()` se calcula una vez por evaluación de fases (sin cambio de comportamiento: `enemy_parts_check` y `arachnodroid_check` idénticos salvo la física del banco, −15 % caminando). Los `AnimatableBody3D` de las partes no tienen `_physics_process`: su sincronización va por propagación de transformadas dentro de `jolt_step`.

> **Nota de WP-26 (2026-09-20)**: el canal espacial del `Telegraph` lo sirve el `VFXPool` según `spatial_kind` (`stomp_decal` / `emp_ring` / `siege_column` / `guide_line` / `parabola`) con respaldo de malla; API nueva `freeze_zone()`, `flash_ring()`, `spatial_effect()`. `EnemyPart.detach()` pide `part_detach` siguiendo al `DebrisChunk`; `EnemyPart.damaged` bajo el 35 % enciende `damaged_sparks`; `ProceduralLegRig.foot_planted` alimenta `foot_dust`. La luz de carga del `Telegraph` se atenúa en el cierre corto de WP-26 (inundaba la imagen de cerca).

> **Nota de WP-24d parte 1 (2026-09-20, marcha)**: el usuario vio al coloso «moverse raro» y el diagnóstico visual (tres encuadres, siete actos) lo confirmó: patas verticales y juntas con las rodillas por debajo de la panza (7,9 m), puntales rectos arrastrados, rodillas apuntando adelante/atrás, cruce de patas al girar, cuerpo a 12° en una rampa de 20°, aterrizaje sin peso, sin cadencia ni respiración. Cambios en `enemies/locomotion/**` y `leg_rig_profile.gd`, todos medidos en `gait_check` (ahora **14 métricas**, mundo con 3 edificios y giro de 180°): `stance_spread` pasa de 1,5 m **radial** a **5,0 m lateral** (huella de marcha 22 × 23 m; rodillas en reposo 9,48 m, mínima en marcha 8,56 m); `step_duration` 0,80 s (ciclo 1,97 s, un apoyo de par cada 0,98 s); `step_trigger` 3,0 y `turn_step_trigger` 1,6; `reach_trigger` 0,95; `step_height_min` 3,5; `tilt_blend` 0,75 y `tilt_smooth_rate` 6,0; nuevos `body_bob` 0,02, `gait_roll` 2°, `gait_pitch` 1,5°, `gait_blend_time` 0,45 s, `idle_breath` 0,15 m a 0,30 Hz, `land_crouch` 0,12 en 0,30 s, `climb_pitch` 25°. §8.4 cambia: el objetivo del paso lleva adelanto `v·step_time + max(step_trigger, v·step_time/2)` (zancada **centrada**, no arrastrada); el disparo se mide sin signo contra el reposo actual con histéresis del 35 % del paso; la colocación prueba hasta **6 candidatos** y gana el primero alcanzable (`PLANT_REACH` 0,97; un rayo por paso en marcha normal); el arco es `smootherstep` horizontal y `sin(π·t^0,80)^1,35` vertical, con velocidad nula en el contacto (retraso contacto→apoyo 0,040 s). §8.2: `TwoBoneIK.solve` gana `knee_lift` opcional (piso 0,30) y el polo es `(±1, 0,30, 0,3)`; `Leg.COXA_YAW_LIMIT` 55°. §8.3: `GaitController.blend()` interpola trípode/arrastre. §8.5: altura sobre la media de los **cuatro** puntos de contacto (suelo interpolado bajo el pie en vuelo) + rebote del ciclo + respiración + agachada por alcance (`COMFORT_REACH` 0,86) + aceleración del vuelo hasta 2,2× cuando la pata apoyada se queda sin cadena. §8.6: aterrizaje con flexión de rodillas. §7: `face_toward()` compone `Basis(UP, Δ) · global_basis` y lee el rumbo del eje frontal (escribir `rotation.y` con el cuerpo inclinado lo hacía cabecear). Medido: deslizamiento 0,000 m (umbral apretado a 0,10), flotación 0,000 s sostenida (máx 0,226 m), inclinación en rampa 15,0°, cabeceo en llano 5,6°, giro de 180° en 7,2 s con 0,003 m, `rig_tick` 147 µs. El hecho «rodillas a 7,9 m en marcha» de las notas de WP-18/19/23 queda obsoleto (9,4 m).

> **Nota de WP-18 (2026-09-19)**: `Perception` expone `has_los` como **campo** (como §9/§14) y la forma funcional es `has_line_of_sight()`: GDScript no admite campo y método homónimos. `UtilitySelector` es `RefCounted` poseído por el `EnemyFSM` (el nodo `Brain`), no un nodo hijo; el FSM reemite `action_selected`. `PerceptionProfile` usa `hz`, `blind_noise_multiplier`, `head_node_name`/`head_fallback_name` y `search_radius_start/end/seconds/refresh` en vez de los nombres de §9. El sesgo ciudad/dron de `07` §7 viaja como multiplicador de fase `then.multipliers.city_bias` (0.70/0.50/0.40/0.30/1.00) y se lee con `EnemyBase.phase_multiplier()`. `Telegraph.begin(attack_id, seconds, color, spatial)` es quien emite `Events.enemy_attack_telegraphed`; una acción nunca lo emite a mano y coloca la señal espacial con `set_ground_point()/set_radius()`; `TelegraphProfile` se define en WP-19. `EnemyAction.effective_windup()` es siempre ≥ 0.80 s, pero `telegraph_seconds()` vale 0 para acciones **sin daño** y con `windup` 0 (la locomoción `approach`); toda acción con daño paga el piso, medido en el reloj real de la FSM. Los estados `ActionNone/Telegraph/Active/Recover` no enrutan: llevan su reloj y exponen `is_finished()`, y el FSM decide (evita un ciclo de referencias). `Global.debug_freeze_ai` se honra en `Perception`, `EnemyFSM`, `ProceduralLegRig` y `EnemyBase.move_body()/face_toward()`. El banco de `ai_check` usa nueve acciones sintéticas (campana de 75 m) para los histogramas por semilla, porque con dos la curva decide sola. El modulador `planted_legs ≥ 3` de §10.2 era irrealizable con el trote (ver el gate de apoyo bajo la tabla de §10.2).

> **Nota de WP-23 (2026-09-19)**: `Perception.target` no lo fija nadie dentro del enemigo (el dron vive en el nivel): lo asigna **`RoundManager._aim_perception(enemy)`** tras `enemies_root.add_child(enemy)`, llamando `perception.set_target(drone)`. Sin eso el jefe nunca veía al jugador y las seis acciones que apuntan al dron puntuaban 0 (medido: 900 s con solo `approach`/`climb`/`siege_beam`). Quien instancie un enemigo fuera de `RoundManager` (checks, showcases) debe hacer lo mismo. `WeakPointProfile.pierces_host` (nuevo): mientras un punto débil con esa bandera está expuesto, su parte hospedadora sale de la capa `enemy_body` (contador en un metadato del cuerpo, porque varios puntos débiles pueden compartirla); lo usan los tres núcleos, cuyas cajas quedaron dentro del collider de `underbelly` (`07` §15 #12). **`DOWNED` (WP-19b)**: `LegRigProfile.downed_body_height` (−6,0 m sobre el suelo, remedido con un rayo bajo el cuerpo porque sin patas apoyadas la media de pies se congela) fija la altura del origen del cuerpo caído en `body_height_target()`; `downed_hip_factor` de §8.7 ya no decide la pose (daba −12,35 m: el cuerpo enterrado). El Arachnodroid, al caer, abre la carcasa, expone los núcleos y entra en P5 (`07` §15 #11).

Define el **contrato común de todos los enemigos** de Drone Survivor: cómo se arma un enemigo en runtime a partir del GLB importado, cómo se modela su salud por partes, cómo se desprenden esas partes, cómo camina con un rig procedural, cómo percibe al dron, cómo elige qué hacer y cómo telegrafía cada ataque.

**Incluye:** árbol de escena estándar; construcción del grafo de partes desde metadatos de import; familia de recursos de configuración; `EnemyPart`, `WeakPoint` y fases; movedor cinemático; `ProceduralLegRig` + `GaitController` + IK de dos huesos; `Perception`; `UtilitySelector` + `Personality`; `EnemyFSM` de dos capas; telegrafía obligatoria; resolución de ataques por barrido; `DebrisPool`; `EnemyCatalog`; `AudioRig` y `Telegraph`; los tres checks headless de P1.

**NO incluye:** la ficha del Arachnodroid (`docs/07`); `.vox`/`parts.json`/GLB ni el importador (`docs/05`); el arma del jugador (`docs/08`); `Building`/`CityIntegrity`/`RubbleField` (`docs/10`); el `RoundManager` (`docs/11`); VFX y música (`docs/13`); los rigs bípedo y hover, que son extensiones de P3 (`docs/14`).

**Restricción transversal:** ningún `Area3D` como hitbox. Impactos, apoyos, línea de visión, pisotones y barridos se resuelven con `PhysicsDirectSpaceState3D.intersect_ray` / `intersect_shape`.

---

## 2. Árbol de escena de un enemigo

```
<Enemy> (EnemyBase, Node3D)          ← raíz de la escena instanciable
├── Model (Node3D)                   ← raíz del GLB importado (p. ej. ArachnodroidRoot)
│   └── …MeshInstance3D por parte, cada uno con un AnimatableBody3D hijo
├── Parts (Node)                     ← contenedor de los EnemyPart creados en _ready()
├── WeakPoints (Node)                ← contenedor de los WeakPoint creados en _ready()
├── Locomotion (ProceduralLegRig, Node3D)
├── Perception (Perception, Node)
├── Brain (Node)
│   ├── Selector (UtilitySelector, Node)
│   └── FSM (EnemyFSM, Node)
│       ├── Locomotion (Node)  → Idle, Walk, Turn, Climb, Leap, Stagger, Downed
│       └── Action (Node)      → None, Telegraph, Active, Recover
├── AttackLibrary (Node)             ← un EnemyAction por ataque, hijos directos
├── AudioRig (AudioRig, Node3D)
└── Telegraph (Telegraph, Node3D)
```

Reglas: la escena **no** lleva scripts dentro del GLB (`docs/05`); `Model` es la instancia importada tal cual. Todas las dependencias se inyectan por `@export` o por búsqueda de hijos con nombre fijo; ningún nodo busca en la raíz del árbol. Los estados de la FSM son nodos hijos, no enums sueltos.

### 2.1 Construcción del grafo de partes en `EnemyBase._ready()`

1. **Recorrido en profundidad de `Model`.** Para cada `MeshInstance3D` con `has_meta(&"part_id")` se instancia un `EnemyPart`, se lo agrega bajo `Parts/` con `name = part_id` y se lo registra en `_parts: Dictionary[StringName, EnemyPart]`.
2. **Lectura de metadatos** (los escribe `asset_import/import_voxel_enemy.gd`, ver `docs/05`): `part_id`, `hp`, `armor`, `detachable`, `debris_mass`, `weak_point_id`, `function`, `flags`.
3. **Colisionador.** Se toma el primer hijo directo `AnimatableBody3D` de la malla (el importador lo llama `<id>_body` y lo deja con `sync_to_physics = false`, `docs/05`). Si falta, se agrega `ERR_ENEMY_PART_NO_BODY` a `Global.startup_errors` y la parte queda marcada `invalid` (no recibe daño, no se desprende). **`docs/05` escribe los metadatos sólo en el `MeshInstance3D`, y `docs/08` los lee del collider devuelto por `intersect_ray`**, así que este paso los **propaga al cuerpo**: `body.set_meta(&"part_id", …)`, `body.set_meta(&"weak_point_id", …)` y `body.set_meta(&"enemy_part", part)` (más el mismo `enemy_part` en la malla). Con eso el arma resuelve el impacto en O(1), sin `get_parent()` encadenados.
4. **Jerarquía lógica.** `part.parent_part` es el primer ancestro `MeshInstance3D` con `part_id`; se rellena `child_parts` en la pasada inversa. Esta jerarquía es la que decide qué se lleva una parte al desprenderse.
5. **Puntos débiles.** Segunda pasada: toda parte con `weak_point_id != &""` genera un `WeakPoint` bajo `WeakPoints/`, configurado con el `WeakPointProfile` homónimo de `EnemyProfile.weak_points`, y **se agrega al grupo `weak_points`** (lo usa la asistencia de puntería de `docs/08`). Sin perfil → `ERR_ENEMY_WP_NO_PROFILE` y el punto débil se degrada a parte normal.
6. **Patas.** Tercera pasada: se agrupan las partes por prefijo (`leg_fl_`, `leg_fr_`, …). En cada grupo se busca el nodo con flag `leg_root` (cadera/coxa), la cadena de `leg_segment` en orden de profundidad (fémur → tibia) y el `foot`. Se arma un `Array[Dictionary]` y se pasa a `Locomotion.setup()`. Un grupo incompleto → `ERR_ENEMY_LEG_INCOMPLETE`.
7. **Overrides de balance.** `EnemyProfile.part_overrides` (`part_id` → `EnemyPartProfile`) pisa los metadatos del import. **El import es el valor por defecto; el `.tres` es la fuente de verdad del balance**, para no re-exportar el GLB por cada ajuste.
8. El enemigo se agrega al grupo **`enemies`** (lo recorre `OffscreenMarkers`, `docs/12`) y se emite `Events.enemy_spawned.emit(self, profile.enemy_id)`.

Coste medido objetivo: < 8 ms para 32 mallas, una sola vez, con `Model` ya instanciado.

---

## 3. Recursos de configuración

Todos son `Resource` con `class_name`, guardados en `enemies/<enemy>/profiles/*.tres` y `enemies/<enemy>/attacks/*.tres`.

### `EnemyProfile`

| Campo | Defecto | Campo | Defecto |
|---|---|---|---|
| `enemy_id: StringName` | `&""` (id estable = `EnemyCatalog`) | `display_key: String` | `""` (clave `ENEMY_*`) |
| `armor_default: float` | `0.90` (si el import no trae `armor`) | `walk_speed: float` | `6.0` m/s en llano |
| `turn_rate: float` | `25.0` °/s | `max_step_per_tick: float` | `0.6` m (antiteletransporte) |
| `hip_height: float` | `14.0` m sobre la media de pies | `stagger_seconds: float` | `0.9` s |
| `leg_speed_penalty: float` | `0.15` por pata | `downed_legs_lost: int` | `4` |
| `debris_lifetime: float` | `20.0` s | `part_overrides: Dictionary` | `{}` (`part_id`→`EnemyPartProfile`) |
| `weak_points: Array[WeakPointProfile]` | `[]` | `leg_rig: LegRigProfile` | `null` |
| `perception: PerceptionProfile` | `null` | `attacks: Array[AttackProfile]` | `[]` (orden = nodos de `AttackLibrary`) |
| `phases: Array[Dictionary]` | `[]` (ver §6) | `personality_spread: float` | `0.30` |
| `decision_hz: float` | `4.0` | `top_n: int` | `3` |
| `body_material_emissive: Color` | color base de emisivos de fase | | |

### `EnemyPartProfile` y `WeakPointProfile`

| `EnemyPartProfile` | Defecto | `WeakPointProfile` | Defecto |
|---|---|---|---|
| `part_id: StringName` | `&""` | `weak_point_id: StringName` | `&""` |
| `hp: float` | `600.0` | `host_part_id: StringName` | `&""` |
| `armor: float` | `0.90` | `hp: float` | `1200.0` |
| `detachable: bool` | `false` | `damage_multiplier: float` | `3.0` |
| `debris_mass: float` | `8000.0` kg | `conditions: Array[int]` | `[Exposure.ALWAYS]` |
| `function: StringName` | `&"cosmetic"` (`leg`\|`sensor`\|`weapon`\|`cosmetic`\|`core`) | `require_all: bool` | `true` (`false` = basta una) |
| `structure_weight: float` | `1.0` (0 = no cuenta en `total_structure_ratio()`) | `after_parts_ids: PackedStringArray` | `[]` |
| `break_trauma: float` | `0.35` (`Events.camera_trauma`) | `after_parts_count: int` | `0` (>0 basta el conteo) |
| `dust_scale: float` | `1.0` | `cone_axis: Vector3` / `cone_half_angle: float` | `DOWN` local / `35.0`° |
| | | `timed_period` / `timed_duty: float` | `0.0` / `0.0` |
| | | `emissive_color` / `emissive_energy` | `Color(0,1,1)` / `3.0` |
| | | `hud_key: String` | `""` (clave `WP_*`) |
| | | `on_destroy: Dictionary` | `{}` (ver abajo) |

`on_destroy` declara los efectos secundarios de romper el punto débil, sin código propio: `detach_part: StringName` (parte que se desprende), `blind_seconds: float`, `lock_attacks: PackedStringArray` + `lock_seconds: float`, `stagger_seconds: float`. `EnemyBase` los ejecuta al recibir `WeakPoint.destroyed`.

El conjunto **canónico** de `function` es `leg` \| `sensor` \| `weapon` \| `cosmetic` \| `core`. Si el `parts.json` trae un sinónimo descriptivo (por ejemplo `vision`), `EnemyBase._ready()` lo normaliza con una tabla de equivalencias (`vision`/`optics` → `sensor`, `gun`/`turret` → `weapon`) y registra `ERR_ENEMY_FUNCTION_UNKNOWN` si no lo reconoce.

### `LegRigProfile`

| Campo | Tipo | Defecto | Campo | Tipo | Defecto |
|---|---|---|---|---|---|
| `step_trigger` | `float` | `3.5` | `stretch_max` | `float` | `1.15` |
| `step_duration` | `float` | `0.55` | `tilt_blend` | `float` | `0.6` |
| `step_height_min` | `float` | `3.0` | `tilt_smooth_rate` | `float` | `4.0` |
| `step_height_bias` | `float` | `2.0` | `height_smooth_rate` | `float` | `4.0` |
| `speed_ref` | `float` | `6.0` | `foot_ray_span` | `float` | `40.0` |
| `speed_clamp` | `Vector2` | `(0.6, 1.8)` | `foot_ray_mask` | `int` | `1 \| 8` |
| `gait_pairs` | `Array[PackedInt32Array]` | `[[0,3],[1,2]]` | `crush_damage` | `float` | `900.0` |
| `tripod_min_planted` | `int` | `2` | `leap_tuck_time` | `float` | `0.5` |

### `AttackProfile`

| Campo | Tipo | Defecto | Campo | Tipo | Defecto |
|---|---|---|---|---|---|
| `attack_id` | `StringName` | `&""` | `damage_drone` | `float` | `0.0` |
| `display_key` | `String` | `""` (`ATK_*`) | `damage_building` | `float` | `0.0` |
| `windup` | `float` | `0.9` | `damage_per_second` | `bool` | `false` |
| `active` | `float` | `0.5` | `impulse_drone` | `float` | `0.0` (N·s) |
| `recover` | `float` | `1.0` | `query_shape` | `Shape3D` | `null` |
| `cooldown` | `float` | `8.0` | `query_layers` | `int` | `0b1000_0010` (2 y 8) |
| `target_kind` | `int` | `TargetKind.DRONE` | `query_interval` | `float` | `0.05` |
| `min_range` | `float` | `0.0` | `telegraph` | `TelegraphProfile` | `null` |
| `max_range` | `float` | `40.0` | `score_curve` | `Curve` | `null` |
| `lock_locomotion` | `bool` | `true` | `score_input` | `StringName` | `&"distance"` |
| `requires_parts` | `PackedStringArray` | `[]` | `base_weight` | `float` | `1.0` |
| `disabled_if_broken` | `PackedStringArray` | `[]` | `audio_bank` | `StringName` | `&""` |

`TargetKind`: `DRONE`, `BUILDING`, `SELF`, `GROUND_POINT`.

### `TelegraphProfile`

`light_color_from: Color`, `light_color_to: Color`, `light_energy_from/to: float`, `audio_event: StringName`, `spatial_kind: int` (`NONE`\|`DECAL_ZONE`\|`GUIDE_LINE`\|`POSTURE`), `decal_texture: Texture2D`, `decal_radius: float`, `guide_width: float`, `posture_curve: Curve`, `hud_warning_key: String`.

---

## 4. `EnemyPart` y desprendimiento

`EnemyPart extends Node`, hijo de `Parts/`. No es un cuerpo físico: **envuelve** el par `MeshInstance3D` + `AnimatableBody3D` que vino del GLB.

- **Daño efectivo:** `effective := amount * (1.0 - armor)`, con `armor` recortado a `[0.0, 0.99]`. Un disparo de 12 sobre blindaje 0.90 quita 1.2 hp. Si el impacto llega por un `WeakPoint` expuesto, el arma ya aplicó `damage_multiplier`; `EnemyPart` no lo vuelve a aplicar.
- **`is_broken()`** es `hp <= 0.0`. Al cruzar 0: se emite `broken`, `Events.enemy_part_broken`, `Events.camera_trauma(break_trauma, posición_de_la_parte)`, se pide `EnemyBase.request_stagger(profile.stagger_seconds, part_id)` y, si `detachable`, se llama `detach()`.
- **Función deshabilitada.** Al romperse, según `function`: `leg` → `Locomotion.notify_leg_broken(i)` (cojera −15 % de velocidad por pata y re-balance de `rest_offset`); `sensor` → `Perception.blind(profile-defined)` o pérdida permanente de un canal; `weapon` → todo `AttackProfile` que liste la parte en `disabled_if_broken` queda fuera del selector; `core` → cuenta para fases y derrota; `cosmetic` → sólo VFX.

### 4.1 Secuencia de `detach(impulse: Vector3)`

1. `DebrisPool.adopt(mesh, body, debris_mass, impulse, profile.debris_lifetime)` devuelve un `DebrisChunk` (`RigidBody3D`, `freeze = true` al nacer). **`DebrisPool` y `DebrisChunk` los define `docs/10`**; su `request(mesh, shape, xform, …)` construye un trozo nuevo desde cero (caso de la ciudad). El desprendimiento de enemigos necesita **reparentar los nodos existentes** para conservar hijos, materiales y colisión, así que usa el método adicional `adopt(mesh: MeshInstance3D, body: PhysicsBody3D, mass: float, impulse: Vector3, lifetime: float) -> DebrisChunk`, ya definido con esa firma exacta en `docs/10` §9.3.
2. Se guarda `var world := mesh.global_transform`. Se reparentan `mesh` y su `body` bajo el chunk y se restaura `mesh.global_transform = world`. **Los hijos del nodo se van con la parte**: al reparentar la malla se llevan sus sub-mallas, luces y `GPUParticles3D`, y sus `EnemyPart` hijas quedan marcadas `is_detached()` (siguen existiendo, ya no reciben daño ni cuentan para `total_structure_ratio()`).
3. El colisionador cambia de capa: `collision_layer = 1 << 8` (capa 9 `debris`), `collision_mask` = capas 1, 2, 8 y 9. Los puntos débiles que viajaban en la parte se apagan.
4. `chunk.mass = debris_mass`; `continuous_cd = true` si la diagonal del AABB > 4 m; `freeze = false`.
5. `chunk.launch(impulse, angular)` con `apply_impulse(impulse, offset)` en el centro de masa desplazado y `angular_velocity` aleatoria en `[-1.2, 1.2] rad/s` por eje (RNG sembrado con `Global.round_seed` para reproducibilidad en los checks).
6. Polvo: `GPUParticles3D` de impacto en el pivote, escalado por `dust_scale`; `AudioRig.play(&"part_break")`.
7. `Events.enemy_part_broken.emit(enemy, part_id, world.origin)`.
8. A los `debris_lifetime` (20 s) el `DebrisPool` congela el chunk (`freeze = true`, `freeze_mode = FREEZE_MODE_STATIC`) y **hornea su transformada en el `RubbleField`** con `bake(mesh_index, xform, tint)`, devolviendo el chunk a la lista libre (`docs/10` §6). El enemigo sólo registra sus mallas de escombro una vez, en `_ready()`, con `RubbleField.register_mesh(mesh)` — máximo **2 por enemigo** (el tope global es de 4 campos).

> El `AnimatableBody3D` nunca se convierte en `RigidBody3D`: viaja como colisionador **hijo** del chunk. Esto evita reconstruir formas y mantiene la malla y su colisión alineadas.

---

## 5. `WeakPoint`

`WeakPoint extends Node`, hijo de `WeakPoints/`, apunta a su `EnemyPart` hospedadora.

```gdscript
enum Exposure { ALWAYS, WHILE_ATTACK, AFTER_PARTS, ANGLE_CONE, TIMED }
```

| Condición | Se cumple cuando |
|---|---|
| `ALWAYS` | siempre |
| `WHILE_ATTACK` | `EnemyFSM.action_state()` ∈ `{TELEGRAPH, ACTIVE}` |
| `AFTER_PARTS` | todas las de `after_parts_ids` rotas, o `after_parts_count` partes estructurales rotas |
| `ANGLE_CONE` | el ángulo entre `cone_axis` (en espacio global del hospedador) y el vector hospedador→dron es ≤ `cone_half_angle` |
| `TIMED` | `fposmod(tiempo, timed_period) < timed_period * timed_duty` |

Las condiciones son **combinables**: `require_all = true` exige todas (es el caso del núcleo ventral del Arachnodroid: `AFTER_PARTS ≥ 3` **y** `ANGLE_CONE 70°` desde abajo); con `require_all = false` basta una.

La evaluación corre a 10 Hz (junto con `Perception`) más un disparo inmediato en cada cambio de estado de acción y en cada `part_broken`. Al cambiar:

- **Expuesto:** `collision_layer = 1 << 3` (capa 4 `enemy_weak`), `collision_mask` = capas 1 y 2; el material emisivo se enciende (`emission_enabled = true`, `emission = emissive_color`, `emission_energy_multiplier = emissive_energy`).
- **No expuesto:** `collision_layer = 1 << 2` (capa 3 `enemy_body`), `collision_mask` = capas 1, 2, 8 y 9; `emission_energy_multiplier = 0.0`. El disparo sigue impactando, pero como carcasa blindada.
- Se emite `exposure_changed` y `Events.enemy_weak_point_state(enemy, weak_point_id, exposed)` — el `CombatHUD` (`docs/12`) lo consume para el marcador.

**Material:** en `_ready()` la malla del punto débil recibe un `material_override` que es `get_active_material(0).duplicate()` (un `StandardMaterial3D`). Así el encendido no afecta al resto del atlas de paleta. P2 puede migrar a `set_instance_shader_parameter()` con el shader voxel compartido (`docs/13`).

---

## 6. Salud escalonada y fases

**No hay HP único.** La integridad se deriva de las partes:

```gdscript
func total_structure_ratio() -> float
# Σ(hp_actual · structure_weight) / Σ(hp_max · structure_weight)
# sobre partes no desprendidas; las partes con structure_weight 0 no cuentan.
```

La derrota **no** se dispara por `total_structure_ratio() == 0`, sino por la condición declarada en `EnemyProfile.phases`: la última fase suele llevar `then.defeat = true` (autodestrucción) o el enemigo cae al romperse todos los `core`. `EnemyBase` emite `defeated` y `Events.enemy_defeated(enemy, enemy_id)` **una sola vez** (guarda `_defeated: bool`).

### 6.1 Formato de `EnemyProfile.phases`

```gdscript
{"id": &"p3_fury",
 "when": {"parts_broken": ["leg_fl_femur", "leg_fr_femur"],  # todas rotas
          "parts_broken_any_count": 2,                       # N cualesquiera con weight > 0
          "parts_broken_from": ["wp_leg_fl_knee", "wp_leg_fr_knee",
                                "wp_leg_bl_knee", "wp_leg_br_knee"],
          "parts_broken_from_count": 2,                      # N de ESA lista
          "structure_below": 0.55, "weak_points_broken": ["wp_head_visor"],
          "require_all": false},                             # OR entre criterios presentes
 "then": {"unlock_attacks": ["pounce"], "lock_attacks": ["climb"],
          "multipliers": {"cooldown": 0.74, "windup": 0.85, "walk_speed": 1.10},
          "emissive_color": Color(1.0, 0.25, 0.1),
          "utility_weights": {"siege_beam": 0.6, "head_laser": 1.3},
          "music_stem": &"combat", "defeat": false}}
```

Reglas:
- Las fases son **ordenadas y monótonas**: se evalúan de la última a la primera y gana la de índice más alto que cumpla; nunca se retrocede.
- Se evalúan en cada `part_broken`, en cada `WeakPoint.destroyed` y a 4 Hz.
- `multipliers.windup` **nunca** puede bajar el windup efectivo de menos de **0.80 s**: `effective_windup = max(0.80, profile.windup * mult)`. Es una invariante verificada por `ai_check`.
- Al cambiar: `Events.enemy_phase_changed(enemy, phase_id)`, recoloreo de emisivos de carcasa y `AudioRig.play(&"phase_shift")`.

---

## 7. Movimiento cinemático

El enemigo **nunca** es empujado por la física. `EnemyBase` mueve su `global_transform` a mano en `_physics_process` (100 Hz).

```gdscript
func move_body(delta: float, desired_velocity: Vector3) -> void
```

1. Si `EnemyFSM.is_locomotion_locked()` (por `AttackProfile.lock_locomotion`) o el estado es `STAGGER`/`DOWNED`, `desired_velocity` se anula (salvo el desplazamiento residual del `Leap`).
2. Aceleración recortada: la velocidad interna converge a `desired_velocity` a `walk_speed / 0.8` m/s².
3. **Tope duro:** `step := velocity * delta`; si `step.length() > max_step_per_tick` (0.6 m) se reescala. A 100 Hz eso permite 60 m/s teóricos; el tope existe para que Jolt no haga tunneling con el dron ni con los edificios.
4. **Giro limitado:** el yaw objetivo se interpola con `Basis.slerp` a `turn_rate` grados/s. `face_toward(target, delta)` hace lo mismo hacia un punto.
5. **Altura e inclinación** las dicta el rig de patas (§8.5), no el movedor: `origin.y = rig.body_height_target()` y `basis = basis.slerp(rig.body_basis_target(), 1.0 - exp(-tilt_smooth_rate * delta))`.
6. **`stagger`:** `request_stagger(seconds, source_part)` fuerza `LocomotionState = STAGGER`, cancela la acción en curso (`EnemyAction.cancel()`, que respeta el cooldown como si hubiera terminado) y aplica una sacudida de pose de amplitud proporcional a `break_trauma`.

Colisión de cuerpo: los `AnimatableBody3D` de las partes (capa 3, máscara 1·2·8·9) hacen el trabajo. No hay `move_and_slide`.

---

## 8. `ProceduralLegRig`

### 8.1 Clase interna `Leg`

```gdscript
class Leg extends RefCounted:
    var index: int ; var side: StringName                       # &"FL" | &"FR" | &"BL" | &"BR"
    var hip: Node3D ; var femur: Node3D ; var tibia: Node3D ; var foot: Node3D
    var femur_length: float ; var tibia_length: float
    var rest_offset: Vector3                                    # reposo del pie, local al cuerpo
    var planted: bool ; var plant_position: Vector3 ; var target: Vector3
    var step_from: Vector3 ; var step_t: float ; var step_time: float
    var broken: bool
```

### 8.2 IK analítico de dos huesos

`TwoBoneIK.solve(root, target, len_a, len_b, pole, stretch_max) -> Dictionary`. Ley del coseno:

- `d := clamp(root.distance_to(target), abs(len_a - len_b) + 0.01, (len_a + len_b) * stretch_max)`.
- `cos_a := clamp((len_a² + d² - len_b²) / (2·len_a·d), -1, 1)`; el ángulo de la rodilla sale de `acos()`.
- Si `d > len_a + len_b` la cadena **se estira** proporcionalmente hasta `stretch_max = 1.15` (17.25 m de alcance con fémur 7.5 + tibia 6.0) en lugar de despegar el pie. Devuelve `stretched = true` para que el rig priorice un paso.
- El `pole` (vector de polo) define el plano de flexión; por defecto es el eje lateral del cuerpo, de modo que las rodillas siempre miran hacia afuera.
- Devuelve `{"mid": Vector3, "end": Vector3, "basis_a": Basis, "basis_b": Basis, "stretched": bool}`; el rig asigna `femur.global_transform` y `tibia.global_transform` con esas bases.

### 8.3 `GaitController`

`Gait { IDLE, TROT, TRIPOD, DRAG, LEAP }`.

- **TROT (4 patas sanas):** pares diagonales `{FL, BR}` y `{FR, BL}`. **Nunca dos pares en el aire**: `can_lift(i)` devuelve `false` si el par opuesto tiene alguna pata en vuelo.
- **TRIPOD (3 patas):** siempre hay al menos 2 apoyadas; las patas se levantan de a una, en orden rotatorio.
- **DRAG (2 patas):** una pata en vuelo como máximo; el cuerpo se arrastra, `speed_multiplier()` cae a 0.55 y el paso se alarga un 30 %.
- **LEAP:** todas las patas libres mientras dura el vuelo balístico.
- `set_available(legs)` se llama en cada `notify_leg_broken()` y recalcula el modo y los pares.

### 8.4 Ciclo de paso

- **Disparo:** un pie pide paso cuando `foot.global_position.distance_to(desired_rest_world) > step_trigger` (3.5 m), cuando la cadena devolvió `stretched == true`, o cuando el rayo de apoyo no encuentra suelo bajo el pie apoyado.
- **Colocación:** `intersect_ray` con `PhysicsRayQueryParameters3D.create(target + up*40, target - up*40)`, `collision_mask = 1 | 8` (`world` y `city`), `exclude` con los RID de las partes propias. El punto de impacto es el nuevo `plant_position`. Si el rayo no golpea nada (abismo), el objetivo se retrae hacia `rest_offset` un 40 % y se reintenta una vez; si vuelve a fallar, la pata mantiene el apoyo anterior y el cuerpo frena.
- **Trepar:** si el collider pertenece a la capa 8, el pie se apoya **sobre el techo** del edificio (el enemigo trepa) y en el instante del apoyo se llama `Building.take_damage(crush_damage, plant_position)` (ver `docs/10`), con `crush_damage` 900 por defecto.
- **Arco:** `height := max(step_height_min, abs(target.y - step_from.y) + step_height_bias)`; la posición del pie es `step_from.lerp(target, t) + up * height * sin(PI * t)` con `t ∈ [0,1]`.
- **Duración:** `step_time := step_duration / clamp(speed / speed_ref, 0.6, 1.8)` → 0.55 s a 6 m/s, 0.31 s a 11 m/s, 0.92 s casi detenido.
- **Aterrizaje:** al llegar `t = 1` se emite `foot_planted(index, position, impact_speed)`; el `AudioRig` dispara la pisada y el `Telegraph`/VFX el polvo.

### 8.5 Altura e inclinación del cuerpo

- **Altura:** `media_y(pies_apoyados) + hip_height`, suavizada con `1 - exp(-height_smooth_rate * delta)` (4/s).
- **Inclinación:** plano de **mínimos cuadrados** sobre las posiciones de los pies (matriz normal 3×3 resuelta a mano; si el determinante < 1e-6 se cae a `Vector3.UP`). La normal del plano da el `up` objetivo; se construye `Basis` objetivo ortonormalizada conservando el yaw actual y se aplica `basis.slerp(target_basis, tilt_blend)` con `tilt_blend = 0.6`, otra vez suavizado a 4/s. Resultado: el coloso se ladea en rampas sin "nadar".

### 8.6 Salto

`begin_leap(landing, flight_time)`:

1. **`tuck` 0.5 s:** las patas se recogen hacia `rest_offset * 0.55`; el cuerpo baja 15 %; `GaitController` pasa a `LEAP`.
2. **Vuelo balístico:** `EnemyBase` integra `v0` resuelta para llegar a `landing` en `flight_time` con gravedad 9.81; el tope de 0.6 m/tick se eleva a 1.2 m/tick sólo durante el vuelo (el enemigo ya no toca nada salvo el suelo).
3. **`land`:** a `flight_time - 0.35 s` se predicen los 4 puntos de impacto con `intersect_ray` desde `landing + rest_offset_i + up*40`; los pies se llevan a esos puntos con el mismo arco.
4. **Recolocación:** al tocar, `stagger` 0.35 s, polvo, `Events.camera_trauma(0.5, landing)` y un `intersect_shape` de onda (ver §11) si el `AttackProfile` lo pide.

### 8.7 Pérdida de patas

`notify_leg_broken(i)`: `leg.broken = true`, la pata deja de recibir IK (queda colgando o ya se fue como escombro), `GaitController.set_available()` recalcula el modo, `speed_multiplier()` baja `leg_speed_penalty` (0.15) por pata perdida, y los `rest_offset` de las patas sanas se **re-balancean** hacia el centroide del polígono de soporte restante (interpolado en 1.2 s) para que el cuerpo no se vuelque. Con `downed_legs_lost` patas perdidas (4) el enemigo entra en `DOWNED` de forma irreversible.

---

## 9. `Perception`

Corre a **10 Hz** en `_physics_process` acumulando tiempo (nunca en `_process`).

1. **LOS:** `intersect_ray` desde el nodo cabeza (o `Model` si no hay) hasta la posición real del dron, `collision_mask = 1 | 8`, `exclude` con los RID propios. Impacto ⇒ sin LOS.
2. **Ruido:** posición medida `= posición_real + gauss(0, σ)` por eje, con `σ = noise_base + noise_speed_factor * drone_speed` (2.0 + 0.25·v). Gauss por Box-Muller con un `RandomNumberGenerator` sembrado con `Global.round_seed ^ hash(enemy_id)`.
3. **Filtro paso bajo:** `believed_position = believed_position.lerp(medida, 1 - exp(-delta / 0.35))` (τ = 0.35 s). `believed_velocity` es la derivada del filtrado, suavizada con el mismo τ.
4. **Memoria:** al perder LOS se sigue **extrapolando** `believed_position += believed_velocity * delta` durante `memory_seconds` (4.5 s), con `confidence` decayendo linealmente de 1 a 0. Al expirar, `confidence = 0` y la IA pasa a **patrón de búsqueda**: `search_point()` devuelve puntos sobre una espiral de radio creciente (8 m → 45 m en 6 s) centrada en la última posición creída, regenerada cada 2 s.
5. **Cegado:** `blind(seconds)` (visor roto, EMP propio, bengala) multiplica σ por 5 y recorta la memoria a 1.5 s mientras dura.
6. Señales `los_gained` / `los_lost`; campos públicos `has_los`, `believed_position`, `believed_velocity`, `confidence`.

### `PerceptionProfile`

`perception_hz 10.0`, `noise_base 2.0`, `noise_speed_factor 0.25`, `filter_tau 0.35`, `memory_seconds 4.5`, `blind_noise_factor 5.0`, `blind_memory_seconds 1.5`, `head_part_id`, `los_mask 1|8`, `search_radius_max 45.0`.

---

## 10. `UtilitySelector` y `Personality`

A **4 Hz**, y siempre que `EnemyFSM.action_state() == NONE`:

1. Se arma `ctx` (§10.1) una sola vez y se pasa a todas las acciones.
2. Se **descartan** las acciones en cooldown, fuera de `[min_range, max_range]`, bloqueadas por la fase (`lock_attacks`), con partes requeridas rotas (`requires_parts` / `disabled_if_broken`), o cuyo `score()` sea ≤ 0.
3. `weighted := score * personality.weight_for(id) * phase_weight(id) * base_weight`, recortado a `[0,1]`.
4. Se ordena y se toman las `top_n` (3) mejores. Se elige una **al azar con peso `weighted²`** (el cuadrado concentra la elección en la mejor sin volverla determinista).
5. `action_selected(attack_id, score)` → `EnemyFSM.request_action(&"TELEGRAPH", {"action": nodo})`.

`Personality extends RefCounted`: `Personality.from_seed(seed_value, attack_ids, spread)` genera, con un `RandomNumberGenerator` sembrado en `Global.round_seed`, un peso por acción en `[1 - spread, 1 + spread]` (spread 0.30). Se crea una sola vez por enemigo, en `_ready()`, y queda fijo toda la ronda: la misma semilla reproduce la misma "personalidad".

### 10.1 Claves de `ctx`

| Clave | Significado | Clave | Significado |
|---|---|---|---|
| `distance: float` | horizontal enemigo↔`believed_position` | `distance_3d: float` | euclídea |
| `drone_height: float` | altura del dron sobre el suelo bajo él | `drone_speed: float` | módulo de `believed_velocity` |
| `has_los: bool` | línea de visión directa | `confidence: float` | 0–1 |
| `time_near: float` | s con el dron a < 12 m | `buildings_in_cone: int` | vivos en cono frontal 60° a ≤ 90 m |
| `time_since_city_attack: float` | s desde el último daño a la ciudad | `structure_ratio: float` | `total_structure_ratio()` |
| `phase: StringName` | fase actual | `planted_legs: int` / `legs_lost: int` | patas apoyadas / perdidas |

### 10.2 Curvas de score de ejemplo

Cada acción define `score_input` (la clave de `ctx` que alimenta `score_curve`, normalizada a `[0,1]` por `max_range` o por el rango indicado) y multiplica por moduladores. Puntos clave de las `Curve` (`x`, `y`):

| Acción | Entrada normalizada | Puntos de la `Curve` | Moduladores |
|---|---|---|---|
| `stomp` | `distance / 18` | (0.00, 0.0) (0.10, 0.9) (0.30, 1.0) (0.70, 0.55) (1.00, 0.0) | `× (1 - clamp(drone_height/12,0,1))` `× confidence` `× gate(locomoción ∉ {LEAP, STAGGER, DOWNED})` |
| `siege_beam` | `time_since_city_attack / 25` | (0.00, 0.10) (0.35, 0.55) (0.70, 0.90) (1.00, 1.0) | `× clamp(buildings_in_cone/4,0,1)` `× city_bias(phase)` |
| `head_laser` | `distance / 60` | (0.00, 0.0) (0.12, 0.25) (0.45, 1.0) (0.75, 0.70) (1.00, 0.20) | `× confidence` `× has_los` `× (visor intacto)` |
| `pounce` | `distance / 55` | (0.00, 0.0) (0.25, 0.35) (0.55, 1.0) (0.85, 0.60) (1.00, 0.0) | `× (1 - clamp(drone_speed/14,0,1))` `× gate(locomoción ∉ {LEAP, STAGGER, DOWNED} ∧ legs_lost ≤ 1)` `× has_los` |

**Gate de apoyo (decisión de WP-18/19, medido en WP-23, 2026-09-19).** El trote mantiene **exactamente dos** patas apoyadas mientras el jefe camina, así que un modulador `planted_legs ≥ 3` nunca se cumple en marcha. Al **decidir**, las acciones que necesitan apoyo solo exigen que la locomoción no esté en `LEAP`/`STAGGER`/`DOWNED` (`locomotion_ready()`). WP-23 midió además que exigir «≥ 2 patas apoyadas además de la que actúa» al entrar en `ACTIVE` era **insatisfacible** (`planted_count()` vale 2 en trote y menos desde P2: `stomp` 5/6 y `leg_sweep` 6/7 abortados, cero daño al casco en 13 min), así que el conteo de apoyo quedó en `MIN_SUPPORT` **0** para `stomp`/`leg_sweep` y **1** para `pounce`. Si una acción aborta al entrar en `ACTIVE`, pasa directo a `RECOVER` sin causar daño y paga igual su cooldown.

Lectura: `stomp` es la respuesta a un dron que se acerca **bajo y cerca**; `siege_beam` es un temporizador de presión sobre la ciudad que sube si el jugador deja de molestar; `head_laser` vive en distancia media y muere pegado o muy lejos; `pounce` castiga al que se queda quieto a media-larga distancia.

---

## 11. `EnemyFSM`, telegrafía y resolución de ataques

### 11.1 Dos capas

Capa **locomoción**: `IDLE`, `WALK`, `TURN`, `CLIMB`, `LEAP`, `STAGGER`, `DOWNED`. Capa **acción**: `NONE`, `TELEGRAPH`, `ACTIVE`, `RECOVER`. Las capas corren en paralelo salvo cuando `AttackProfile.lock_locomotion == true`, que fuerza la locomoción a `IDLE` (o `TURN` si el ataque necesita apuntar) mientras dura `TELEGRAPH` + `ACTIVE`. `STAGGER` y `DOWNED` tienen prioridad absoluta y cancelan la acción.

Cada estado es un nodo hijo con `_enter(ctx: Dictionary)`, `_exit()`, `_tick(delta: float)` y `can_exit() -> bool`. El `EnemyFSM` sólo enruta; no contiene lógica de gameplay.

### 11.2 Telegrafía obligatoria

Ninguna acción con `damage_drone > 0` o `damage_building > 0` puede pasar a `ACTIVE` sin haber pasado ≥ **0.9 s** en `TELEGRAPH` (**mínimo absoluto 0.8 s** tras los multiplicadores de fase). Se exigen **al menos dos de tres canales**, y los ataques letales exigen los tres:

1. **Luz emisiva:** `light_color_from → light_color_to` y energía interpolada durante el windup (cian → rojo en el Arachnodroid).
2. **Audio:** `AudioStreamPlayer3D` con el evento de carga (`audio_event`), con `unit_size` grande para que se oiga a 80 m.
3. **Señal espacial:** `Decal` de zona proyectado en el suelo (pisotones, ondas), línea guía (`MeshInstance3D` con un cilindro fino y material emisivo aditivo, para el láser) o postura (el cuerpo se agacha / levanta una pata).

Al entrar en `TELEGRAPH`: `Telegraph.begin(attack_id, duration, cfg, target)` y `Events.enemy_attack_telegraphed.emit(enemy, attack_id, duration)` — el `CombatHUD` lo usa para el aviso y el marcador fuera de pantalla. Si la acción se cancela, `Telegraph.cancel()` apaga los tres canales en 0.15 s.

### 11.3 Resolución de ataques

Durante toda la ventana `ACTIVE`, cada `query_interval` (0.05 s) se ejecuta `intersect_shape` con `PhysicsShapeQueryParameters3D`:

```gdscript
var params := PhysicsShapeQueryParameters3D.new()
params.shape = profile.query_shape          # Sphere/Box/Capsule/Cylinder
params.transform = attack_volume_transform  # lo mueve la acción (barrido, haz, onda)
params.collision_mask = profile.query_layers # capas 2 (drone) y 8 (city)
params.collide_with_bodies = true
params.exclude = enemy_rids
```

- Un mismo collider se daña **una sola vez por ventana activa** salvo que `damage_per_second == true`, en cuyo caso se aplica `damage * query_interval`.
- Contra el dron: `Hull.apply_damage(amount, source_position)` (`docs/09`; `take_damage()` existe allí sólo como alias histórico y **no** se usa desde acá) y, si `impulse_drone > 0`, `apply_impulse(dir * min(impulse_drone, 120.0))` sobre el `RigidBody3D` — **el clamp a 120 N·s es obligatorio** para que Jolt no lance el dron fuera del mundo.
- Contra la ciudad: `Building.take_damage(amount, point)` (`docs/10`).
- Los haces continuos (`siege_beam`, `head_laser`) resuelven además un `intersect_ray` por tick para el punto de contacto visual; el daño sigue saliendo del `intersect_shape`.

---

## 12. Utilitarios: `DebrisPool`, `AudioRig`, `Telegraph`, `EnemyCatalog`

- **`DebrisPool` y `RubbleField`**: **los define `docs/10-ciudad-destructible.md`** (`MAX_LIVE = 24`, `get_live_count()`, `retire_oldest()`, `clear()`; `RubbleField.register_mesh/bake/get_field_count`). Hay **uno solo por nivel**, cableado por `battle_level.tscn` y compartido entre ciudad y enemigos; `EnemyBase` lo recibe por `@export`, nunca lo busca. Si no hay chunk libre, el pool retira el más viejo. Escombros con `gi_mode = DISABLED` y sin sombra propia si el AABB < 2 m. Lo único que este framework agrega es `adopt()` (§4.1).
- **`AudioRig`** (`Node3D`): pool de 6 `AudioStreamPlayer3D` reciclados por prioridad + 2 canales de loop (servos, carga). `set_servo_load(load)` modula volumen y pitch del loop de servos con la velocidad angular del cuerpo. Bus `Enemies`.
- **`Telegraph`** (`Node3D`): posee un `OmniLight3D`/`SpotLight3D`, un `Decal`, un `MeshInstance3D` de línea guía y un `AudioStreamPlayer3D`; los enciende y apaga según `TelegraphProfile`. Un solo `Telegraph` por enemigo: nunca hay dos telegrafías simultáneas.
- **`EnemyCatalog`** (estático, `RefCounted`, §14): `const ENTRIES` con ids estables → `{"scene", "profile", "display_key"}`. El `RoundManager` (`docs/11`) instancia exclusivamente desde acá.

---

## 13. Contrato para agregar un enemigo nuevo (P3)

1. `.vox` en `assets/_raw/<Enemy>.zip` (solo lectura). Extraer **fuera** del repo.
2. Autorar `enemies/<enemy>/<enemy>.parts.json` según `docs/05`: cajas, jerarquía `parent`, pivotes, `flags` (`root`, `detachable`, `weak_point`, `leg_root`, `leg_segment`, `foot`, `cosmetic`), `voxel_size` y `axis_map`.
3. `python -m tools.voxsplit build <enemy> --report` → GLB + previews. **0 voxels sin asignar** y presupuesto de triángulos, o el comando falla.
4. Importar en Godot: `asset_import/import_voxel_enemy.gd` añade `AnimatableBody3D` + forma por parte, capas 3/4 y metadatos. Verificar con `enemy_import_check`.
5. Crear los `.tres`: `<enemy>_profile.tres`, `leg_rig.tres` (o el rig que corresponda), `perception.tres`, `attacks/*.tres`.
6. Armar `enemies/<enemy>/<enemy>.tscn` con el árbol de §2 y un nodo `EnemyAction` por ataque bajo `AttackLibrary`.
7. Declarar `phases` y los pesos de utilidad por fase en el profile.
8. Registrar en `EnemyCatalog.ENTRIES` y agregar las claves `ENEMY_*`, `ATK_*` y `WP_*` a `localization/translations.csv`.
9. Escribir `tools/<enemy>_check.tscn` (fases alcanzables, cooldowns, telegrafías ≥ 0.8 s, `defeated` una sola vez).
10. Dar de alta la ronda en `RoundCatalog` (`docs/11`).

---

## 14. Interfaz pública

```gdscript
class_name EnemyBase extends Node3D
signal part_broken(part_id: StringName)     # + weak_point_state_changed(id, exposed), phase_changed(id), defeated()
@export var profile: EnemyProfile           # + debris_pool: DebrisPool, rubble_field: Node3D
func get_part(part_id: StringName) -> EnemyPart
func get_weak_point(weak_point_id: StringName) -> WeakPoint
func total_structure_ratio() -> float
func move_body(delta: float, desired_velocity: Vector3) -> void
func face_toward(target: Vector3, delta: float) -> void
func request_stagger(seconds: float, source_part: StringName) -> void
func current_phase() -> StringName
func unlocked_attacks() -> PackedStringArray
func is_downed() -> bool

class_name EnemyPart extends Node
signal broken(part_id: StringName)
signal damaged(part_id: StringName, amount: float, remaining: float)
func take_damage(amount: float, hit: Dictionary) -> float    # devuelve el daño efectivo
func is_broken() -> bool
func is_detached() -> bool
func structure_ratio() -> float
func detach(impulse: Vector3) -> void

class_name WeakPoint extends Node
enum Exposure { ALWAYS, WHILE_ATTACK, AFTER_PARTS, ANGLE_CONE, TIMED }
signal exposure_changed(weak_point_id: StringName, exposed: bool)
signal destroyed(weak_point_id: StringName)
func evaluate(ctx: Dictionary) -> bool
func is_exposed() -> bool
func damage_multiplier() -> float

class_name ProceduralLegRig extends Node3D
signal foot_planted(leg_index: int, position: Vector3, impact_speed: float)
signal leg_broken(leg_index: int)
func setup(legs: Array[Dictionary]) -> void
func rig_tick(delta: float, body_velocity: Vector3) -> void
func body_height_target() -> float
func body_basis_target() -> Basis
func planted_count() -> int
func speed_multiplier() -> float
func notify_leg_broken(leg_index: int) -> void
func begin_leap(landing: Vector3, flight_time: float) -> void

class_name Perception extends Node
signal los_gained()                          # + los_lost()
func blind(seconds: float) -> void
func is_blinded() -> bool
func time_since_los() -> float
func search_point() -> Vector3
# campos públicos: has_los: bool, believed_position/velocity: Vector3, confidence: float

class_name UtilitySelector extends Node
signal action_selected(attack_id: StringName, score: float)
func evaluate(ctx: Dictionary) -> EnemyAction
func set_personality(p: Personality) -> void
func debug_last_scores() -> Dictionary

class_name EnemyAction extends Node
@export var profile: AttackProfile
func score(ctx: Dictionary) -> float          # 0–1
func is_available(ctx: Dictionary) -> bool
func effective_windup() -> float              # ≥ 0.80 siempre
func begin_telegraph() -> void                # + begin_active(), tick_active(delta),
func end_active() -> void                     #   begin_recover(), cancel()

class_name EnemyFSM extends Node
signal locomotion_changed(from: StringName, to: StringName)   # + action_changed(from, to)
func request_locomotion(state: StringName, ctx: Dictionary = {}) -> bool
func request_action(state: StringName, ctx: Dictionary = {}) -> bool
func locomotion_state() -> StringName
func action_state() -> StringName
func is_locomotion_locked() -> bool

# DebrisPool lo define docs/10 (MAX_LIVE 24, request, get_live_count, retire_oldest, clear).
# docs/06 sólo agrega este método para el desprendimiento con reparentado:
func adopt(mesh: MeshInstance3D, body: PhysicsBody3D, mass: float,
        impulse: Vector3, lifetime: float) -> DebrisChunk

class_name Personality extends RefCounted
static func from_seed(seed_value: int, attack_ids: PackedStringArray, spread: float) -> Personality
func weight_for(attack_id: StringName) -> float

class_name TwoBoneIK extends RefCounted
static func solve(root: Vector3, target: Vector3, len_a: float, len_b: float,
        pole: Vector3, stretch_max: float) -> Dictionary   # mid, end, basis_a, basis_b, stretched

class_name EnemyCatalog extends RefCounted
const ENTRIES: Dictionary = {}               # id → {scene, profile, display_key}
static func has_id(id: StringName) -> bool
static func entry(id: StringName) -> Dictionary
static func scene_of(id: StringName) -> PackedScene
static func profile_of(id: StringName) -> EnemyProfile
static func ids() -> PackedStringArray
```

> Convención obligatoria en todo el framework: tipado estricto (`untyped_declaration=1`) y `var _discard := señal.connect(...)` por `return_value_discarded=1`.

### 14.1 Contrato del `Dictionary` `hit`

Lo rellena el arma (`docs/08-combate-y-armas.md`) antes de llamar a `EnemyPart.take_damage`.

| Clave | Tipo | Obligatoria | Nota |
|---|---|---|---|
| `position` | `Vector3` | sí | punto de impacto en mundo |
| `normal` | `Vector3` | sí | normal de la superficie |
| `direction` | `Vector3` | sí | dirección del disparo, normalizada |
| `source` | `Node3D` | sí | `WeaponMount` emisor |
| `is_weak_point` | `bool` | sí | `true` si el collider estaba en capa 4 |
| `weak_point_id` | `StringName` | no | presente sólo si `is_weak_point` |
| `damage_type` | `StringName` | no | `&"kinetic"` por defecto |

`take_damage` **no escribe nada dentro de `hit`**: devuelve el daño efectivo y el llamador consulta la letalidad con `part.is_broken()` inmediatamente después (acuerdo cerrado con `docs/08` §, decisión abierta 2 de ese documento).

### 14.2 Capas de física usadas (tabla de `docs/02` §3.1)

| Uso | Capa propia | Máscara de consulta |
|---|---|---|
| Parte blindada (`AnimatableBody3D`) | 3 `enemy_body` | 1, 2, 8, 9 |
| Punto débil expuesto | 4 `enemy_weak` | 1, 2 |
| Escombro (`DebrisChunk`) | 9 `debris` | 1, 2, 8, 9 |
| Rayo de apoyo del pie | — | `1 \| 8` |
| Rayo de LOS | — | `1 \| 8` |
| Barrido de ataque (`intersect_shape`) | — | capas 2 y 8 |
| Balística enemiga (P3) | 6 `projectile_enemy` | 1, 2, 8 |

---

## 15. Parámetros y valores iniciales

| Recurso | Parámetros y valores |
|---|---|
| `EnemyProfile` | `armor_default` 0.90 · `walk_speed` 6.0 m/s · `turn_rate` 25 °/s · `max_step_per_tick` 0.6 m (1.2 m en `LEAP`) · `hip_height` 14.0 m · `stagger_seconds` 0.9 s · `leg_speed_penalty` 0.15/pata · `downed_legs_lost` 4 · `debris_lifetime` 20 s · `decision_hz` 4 Hz · `top_n` 3 · `personality_spread` ±0.30 |
| `LegRigProfile` | `step_trigger` 3.5 m · `step_duration` 0.55 s ÷ `clamp(v/6, 0.6, 1.8)` · `step_height` `max(3.0, abs(Δy)+2.0)` · `stretch_max` 1.15 · `tilt_blend` 0.6 · suavizados 4 s⁻¹ · `foot_ray_span` ±40 m con máscara `1\|8` · `crush_damage` 900 · `leap_tuck_time` 0.5 s · `tripod_min_planted` 2 |
| `PerceptionProfile` | `perception_hz` 10 Hz · `noise_base` 2.0 m · `noise_speed_factor` 0.25 · `filter_tau` 0.35 s · `memory_seconds` 4.5 s · `blind_noise_factor` ×5 · `blind_memory_seconds` 1.5 s · `search_radius_max` 45 m |
| `AttackProfile` | `windup` 0.9 s nominal / **0.80 s absoluto** tras fases · `query_interval` 0.05 s · `query_layers` capas 2 y 8 · `cooldown` por ataque (`docs/07`) |
| Constantes del framework | `DebrisPool.max_live` 24 · clamp de `impulse_drone` 120 N·s · daño efectivo `amount · (1 − armor)` con `armor ∈ [0, 0.99]` · construcción del grafo < 8 ms · `rig_tick` < 0.25 ms/tick · física total con 1 jefe < 2.0 ms/tick (`docs/15`) |

---

## 16. Criterios de aceptación y checks headless

Comando base: `"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/<x>_check.tscn`. Los tres devuelven **0** si todo pasa, **1** ante una aserción fallida (con la línea `FAIL: <criterio> esperado=<x> medido=<y>`) y **2** si falta un recurso. Todos restauran `Global.round_seed` y la configuración del jugador al salir.

### 16.1 `tools/enemy_parts_check.tscn` (WP-16)

`… --headless --path godot res://tools/enemy_parts_check.tscn`

| # | Verifica | Umbral |
|---|---|---|
| 1 | Grafo construido: toda parte de `parts.json` tiene `EnemyPart` + `AnimatableBody3D`, y `parent_part` reproduce la jerarquía del sidecar | igualdad exacta de ids y de padres |
| 2 | Blindaje y multiplicador: `take_damage(100, hit)` sobre `armor 0.90`; el multiplicador de punto débil no se aplica dos veces | hp baja 10.0 ± 0.01; daño efectivo = el que pasó el arma |
| 3 | Desprendimiento: 4 partes `detachable` rotas | `get_live_count() == 4`, 4 `Events.enemy_part_broken` con ids únicas, chunk en capa 9 con máscara 1·2·8·9 |
| 4 | Los hijos se van con la parte | tras romper `leg_fl_femur`, `leg_fl_tibia.is_detached() == true` |
| 5 | Función deshabilitada | `rig.speed_multiplier()` ≈ 0.85 tras una pata; acción con `disabled_if_broken` fuera del selector |
| 6 | Tope del pool: 40 desprendimientos forzados | `get_live_count() <= 24`, el más viejo con `freeze == true` |
| 7 | Vida del escombro | a 20.1 s simulados, `RubbleField.get_instance_count(mesh_index)` crece y el chunk vuelve a la lista libre |
| 8 | Sin huérfanos | tras `enemy.queue_free()` + 2 frames, 0 nodos con meta `enemy_part` en el árbol |

### 16.2 `tools/gait_check.tscn` (WP-17)

`… --headless --path godot res://tools/gait_check.tscn`

Tres escenarios encadenados, 40 s cada uno, con el enemigo en `WALK` a `walk_speed` y objetivos sintéticos: **(A)** rampa de 20°; **(B)** escalones de 4 m de alto; **(C)** campo de rocas (5 `StaticBody3D` convexos de 3–9 m).

| # | Métrica | Umbral |
|---|---|---|
| 1 | Deslizamiento de pie apoyado (máx. desplazamiento de `plant_position` mientras `planted`) | < 0.25 m |
| 2 | Pie flotando (> 0.30 m sobre el suelo consultado) con `planted == true` | nunca > 0.20 s continuos |
| 3 | Apoyo con 4 patas sanas; pares diagonales en el aire a la vez | `planted_count() >= 2` el 100 % de los ticks; 0 ocurrencias |
| 4 | Velocidad media en llano; inclinación en rampa de 20° | ≥ 0.85 × `walk_speed`; `up` del cuerpo entre 8° y 16° en régimen |
| 5 | Estabilidad numérica, 120 s totales; determinismo con la misma semilla | 0 `NaN`/`INF`; trayectoria idéntica ± 0.01 m |
| 6 | Trepado: al apoyar sobre capa 8; coste del rig | `Building.take_damage` con `crush_damage`; `rig_tick` < 0.25 ms/tick |

### 16.3 `tools/ai_check.tscn` (WP-18)

`… --headless --path godot res://tools/ai_check.tscn`

| # | Verifica | Umbral |
|---|---|---|
| 1 | 3 semillas (`round_seed` = 1, 7, 99) × 600 decisiones → 3 histogramas de `attack_id` | distancia L1 entre cada par ≥ 0.15 |
| 2 | Ninguna acción monopoliza y ninguna queda muerta | probabilidad máxima por acción ≤ 0.60; conteo > 0 para todas las disponibles |
| 3 | Windup efectivo de toda acción en toda fase | `effective_windup() >= 0.80` |
| 4 | Telegrafía precede al daño, con canales suficientes | `enemy_attack_telegraphed` ≥ 0.80 s antes del primer `intersect_shape` dañino; ≥ 2 canales activos (3 si `damage_drone >= 100`) |
| 5 | Cooldowns | ninguna acción se repite antes de su `cooldown` |
| 6 | LOS se pierde y se recupera (`StaticBody3D` de capa 8 interpuesto y retirado) | `has_los` conmuta en ≤ 0.15 s en ambos sentidos |
| 7 | Memoria tras perder LOS | `believed_position` extrapola 4.5 s; después `confidence < 0.10` y `search_point()` cambia cada 2 s |
| 8 | Ruido con dron quieto, 200 muestras; y cegado con `blind(5.0)` | σ = `noise_base` ± 20 %; cegado σ ≈ ×5 y memoria efectiva ≈ 1.5 s |

---

## 17. Riesgos y decisiones abiertas

| # | Riesgo / decisión | Mitigación o pendiente |
|---|---|---|
| 1 | El coloso cinemático atraviesa al dron (tunneling en Jolt) | tope de 0.6 m/tick, `AnimatableBody3D` sin `sync_to_physics`, ataques por `intersect_shape` en vez de contacto; verificado en `gait_check` |
| 2 | La marcha "nada" o resbala en geometría compleja | métricas duras de `gait_check`; debug draw de objetivos, apoyos y plano de mínimos cuadrados con `DebugGeometry` |
| 3 | Reparentar mallas en runtime rompe materiales o transformaciones | `detach()` guarda y restaura `global_transform`; test 7 y 12 de `enemy_parts_check` |
| 4 | `material_override` duplicado por punto débil multiplica draw calls | ≤ 8 puntos débiles por enemigo; migrar a `set_instance_shader_parameter()` en P2 (`docs/13`) |
| 5 | `Array[Dictionary]` de `phases` es incómodo en el inspector | se autoriza editar el `.tres` a mano; evaluar una herramienta de editor en P2 si duele |
| 6 | Dos fases compiten al romperse dos partes en el mismo tick | resuelto por orden: gana la de índice más alto; monotonía garantizada |
| 7 | **Acordado con `docs/10`:** `DebrisPool` y `RubbleField` son únicos por nivel y compartidos | **cerrado**: `adopt(mesh, body, mass, impulse, lifetime) -> DebrisChunk` queda definido en `docs/10` §9.3 con esa firma exacta |
| 8 | Ceguera por sensor roto: ¿permanente o temporal? | **cerrada**: temporal. Para el Arachnodroid son 20 s de ceguera y un sensor de respaldo a los 45 s (`docs/07` §4); el framework soporta ambas formas |
| 9 | **Abierto:** frecuencia de evaluación de `ANGLE_CONE` | 10 Hz puede sentirse "pegajoso" al orbitar; medir en WP-23 y subir a 20 Hz si hace falta |
| 10 | Beehave para secuenciar ataques compuestos (P3) | se reevalúa en WP-31; el framework no depende de ningún addon |

---

## 18. Referencias cruzadas

- `docs/02-configuracion-del-proyecto.md` — capas de física, autoloads, acciones de input.
- `docs/05-pipeline-voxel.md` — `parts.json`, GLB, `AnimatableBody3D` por malla y metadatos de import que consume §2.1.
- `docs/07-arachnodroid.md` — primera aplicación completa de este framework.
- `docs/08-combate-y-armas.md` — quien llama a `EnemyPart.take_damage(amount, hit)` y llena el `Dictionary` de §14.1.
- `docs/09-energia-y-danio.md` — `Hull.apply_damage(amount, source_position)` y los impulsos que recibe el dron.
- `docs/10-ciudad-destructible.md` — `Building.take_damage(amount, point)`, `RubbleField`, `DebrisPool` compartido.
- `docs/11-rondas-y-objetivos.md` — `RoundManager`, instanciación desde `EnemyCatalog`, `enemy_defeated`.
- `docs/12-interfaz-y-hud.md` — barra de jefe por partes, aviso de telegrafía, marcadores fuera de pantalla.
- `docs/13-identidad-visual-y-audio.md` — emisivos, polvo, buses `Enemies`, música por fase.
- `docs/14-catalogo-de-enemigos.md` — los otros 8 enemigos y las extensiones del rig.
- `docs/15-verificacion-y-ci.md` — inventario de checks y presupuestos de rendimiento.
