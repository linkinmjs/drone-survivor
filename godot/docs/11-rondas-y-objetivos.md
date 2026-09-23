# 11 — Rondas y objetivos

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-21 · Depende de: `docs/06-framework-de-enemigos.md`, `docs/07-arachnodroid.md`, `docs/09-energia-y-danio.md`, `docs/10-ciudad-destructible.md`, `docs/12-interfaz-y-hud.md`

## 1. Objetivo y alcance

> **Nota del cierre de la tanda 2 de P2c (2026-09-23)**: la partida de control del pueblo diseñado dura 395,6 s (banda de `balance_check` recalibrada a 340–580 s): el pueblo sin defensa cae un 32 % después del objetivo de cinco minutos de §11 (antes 70–89 %). El bot gana en 127–148 s con oro en las dos semillas completas (2 390 y 2 468 puntos): `time_par` 540 sigue pendiente de decisión del usuario.

> **Nota de P2c, WP-D2 (2026-09-23)**: los marcadores pueden declararse en el diseño (`markers[]` del JSON: `battery|enemy|drone|camera` reemplazan a los sorteados de su clase); los 4 puestos de pila de calle declarados están bajo un toldo naranja (estación de servicio y tres `awning_orange`), el quinto de calle y los 3 de azotea siguen sorteados. El acceso oeste del jefe (`EnemySpawn0`, a 200 m de arco) quedó a 22 m del vano del puente tras correr el cruce del arroyo a −230 m: el jefe no pisa el puente. La escuela protegida sigue siendo `Building_School`, ahora en m08 frente a la plaza; HP total 91 800 (52 destructibles). `balance_check --only=1` en banda.

> **Nota de P2b, WP-D (2026-09-21)**: la nota de WP-25b de esta sección que declara el protegido como `Building_8_4` (y la de `Building_2_1`) queda superada: el protegido es **`Building_School`** de `town_a.tscn`. Medallas con el pueblo: 5 oros y 1 plata en 6 partidas del bot (ronda de 2,5 min contra `time_par` 540): la decisión sobre `time_par` sigue pendiente del usuario.

> **Nota de P2b (2026-09-21)**: `RoundCatalog` apunta a `res://city/districts/town_a.tscn` y `protected.building = "Building_School"` (nombre **por rol**, ya no por celda: la fragilidad de `Building_8_4` desaparece; `round_check` lee `protected_node()` del catálogo). `RoundManager._spawn_district()` → `_adopt_district_markers()`: si el distrito trae `DroneSpawn`, `CameraFixedPose` y `BatteryPosts`, mueve `Respawn`, `DroneRig` (y el cuerpo del dron: un `RigidBody3D` no se entera de que su padre se movió) y `CameraFixed`, y `BatterySpawner.adopt_markers()` reemplaza los puestos; los `Marker1..8` copiados a mano de `battle_level.tscn` se borraron. `_prepare_intro_camera()` usa `district.play_centre()`. `Arachnodroid.city_centre()` = primer nodo del grupo `protected` → grupo `town_centre` → baricentro (siempre por grupo: el enemigo no busca nodos en la raíz, §3). `round_check` 17 filas (17: adopción de marcadores con distrito sintético y los tres escalones de `city_centre()`; la fila retira temporalmente del grupo a los `TownCentre` presentes); fila 16 con conteos derivados del barrio (59, no 60). El HP total baja a 92 100: el 35 % de derrota se mide contra eso y `balance_check` se recalibra en WP-D.

> **Nota del checkpoint 4, segunda vuelta (2026-09-21)**: con rodillas de 800 HP el bot gana en 3–3,5 min y el bono de tiempo (8 pts/s bajo `time_par` 540 s) le da oro en 8 de 9 partidas. Los umbrales 350/800/2000 no cambiaron; la palanca es `time_par` (≈ 300–360 s) o el peso del bono. Pendiente de decisión del usuario.

> **Nota del checkpoint 4 (2026-09-21)**: con la ronda más corta, el bono de tiempo (8 pts/s sobre `time_par` 540 s) reparte el 68 % del puntaje base (antes 56 %): el bot con 2 muertes saca plata en las tres semillas (antes bronce) y una partida limpia saca oro con 75 % de margen. Umbrales 350/800/2000 sin tocar; si se quiere recuperar el reparto anterior, la palanca es `time_par` 540 → ~380 o el bono 8 → 5 pts/s. Se decide cuando el usuario juegue el rebalance.

> **Nota de WP-28 parte B (2026-09-20)**: al completar un objetivo, `ObjectiveSequencer._on_objective_completed()` emite `Events.camera_trauma(0.08, Vector3.INF)` (sin atenuación) junto con el texto de éxito, no en `advance()`, para que el golpecito llegue con el cartel.

> **Nota del cierre de WP-26 (2026-09-20)**: `Events.hit_confirmed(position, weak, lethal, surface)`; `RoundManager` y `BotPilot` aceptan la aridad nueva y la precisión del resultado no cambia.

> **Nota de WP-25b parte de pantalla (2026-09-20)**: la pantalla de la alerta está implementada en `hud/combat/alert_screen.gd` (ver `docs/12` §1); `RoundManager` no necesitó cambios: alcanzaron `get_alert_remaining()`, `get_protected_building()`, `get_protected_kind()`, `get_enemy_entry_position()`, `get_district()` y `alert_finished`. Verificado en Movie Maker: ALERT a t=0 → estática a 6,2 s → INTRO a 6,5 s con «EN PIE 100 %».

> **Nota de WP-25b parte de datos (2026-09-20)**: implementado según el diseño de arriba con estas precisiones. `Global.RoundState.ALERT` anexado al final (valor 4) aunque corra primero; `RoundManager`: `signal alert_finished`, `ALERT_SECONDS 6,0`, `STATIC_SECONDS 0,4`, `ALERT_INPUT_GRACE 0,35` (con ventana, el botón con el que se llegó al nivel saltaba la alerta en el primer cuadro), `MAX_STEP 0,25` (el primer cuadro tras instanciar el distrito llega con un `delta` de segundos; se acota en la alerta y en la INTRO), `PROTECTED_PRIORITY 3,0`, `get_alert_remaining()`, `get_protected_building()`, `get_protected_kind()`, `get_enemy_entry_position()`, `get_district()`, `skip_intro()` (un estado por llamada: ALERT→INTRO se lleva la alerta y el hueco de estática en el mismo cuadro; los 0,4 s solo corren cuando la alerta se agota sola), `skip_to_battle()` para bancos y capturas. **El edificio protegido es `Building_8_4`** (no `Building_2_1`, que estaba a 240 m del cruce): `block_mid` de 20 × 11 m y 16,2 m de alto, perfil torre de 3 500 HP, el no-hito más cercano al cruce de avenidas sobre la recta `EnemySpawn0` → centro; con peso ×3 vale el 8,7 % del barrio. `RoundCatalog.protected_of()`; `Building.display_key/priority/mark_protected()/is_protected()/display_name()/windows_lit()` y grupo `protected`; `CityIntegrity.set_protected()/get_protected()/is_protected_fallen()/get_standing_count()`, `protected_weight 3,0`, señal `protected_fallen`; `Objective.fail()/objective_failed/is_failed/get_title_text()/get_failed_text()`; `ObjectiveDefendCity` titula `OBJ_PROTECT_TITLE` con el nombre y queda **fallido sin terminar** si la escuela cae («ESCUELA 12: CAÍDA»); `RoundResult.protected_state/protected_name_key/buildings_standing/buildings_total`, `state_of_building()`, y `summary_rows()` con clave `header` que abre por «Qué quedó en pie» → estado del protegido → «Edificios en pie n/60» → integridad → tiempo, partes, precisión, reconstrucciones → puntaje y medalla al final. `HUDOffscreenMarkers` marca el grupo `protected` en ámbar con prioridad máxima. `round_check` 16 filas (4/5 con ALERT, 16 «edificio protegido»: peso ×3 medido, 0,0825 contra 0,0275 de un bloque igual). `balance_check` en rango (la fila de muertes es ruidosa a `time_scale` 4: la semilla 99 dio 6 y 2 muertes en corridas iguales).

> **Nota de WP-24e (2026-09-20)**: congelar el dron (`_freeze_drone(true)` en INTRO y al terminar la ronda) ahora también **apaga el audio de motores** (`docs/03` §6); `round_check` fila 8 lo asevera antes de la tarjeta. Una reconstrucción por batería agotada cuenta como muerte (`Events.drone_destroyed`) igual que por casco (`docs/09`).

> **Diseño de WP-25b (checkpoint 3b, 2026-09-20): alerta del taller y edificio protegido.** (1) Estado nuevo `Global.RoundState.ALERT` (anexado al final del enum) previo a `INTRO`: al comenzar la ronda, con el nivel ya cargado y el dron congelado, `RoundManager._enter_alert()` muestra durante 6 s (o hasta cualquier botón) la pantalla del monitor del taller (`HUDAlertScreen`, `hud/combat/alert_screen.gd`: fondo negro con scanlines, «ALERTA» parpadeando en ámbar, mapa simple del barrio dibujado desde los carriles de `CityGrid` con el edificio protegido resaltado y su rótulo «Proteger: Escuela 12», chevron cian con «ENEMIGO: ARACHNODROID» por donde entra el jefe), después una **estática** de 0,4 s (`StaticBurst`, `hud/combat/static_burst.gd` + `static.gdshader`, reutilizable por la muerte, la vuelta y el overlay FPV) y recién entonces la INTRO de 12 s, que es «el vuelo de salida desde la azotea». `skip_intro()` saltea el estado previo activo. (2) **Edificio protegido**: `RoundCatalog` declara por ronda `protected = {building: "Building_2_1", name_key: "BLD_SCHOOL_12", kind: &"school"}` (nombre de nodo estable del `district_a.tscn` generado con semilla 0; un bloque medio cerca del cruce de avenidas, nunca un hito); `RoundManager._resolve_protected()` lo busca en `CityGrid.get_buildings()`, le pone `display_key` y `priority 3.0` (exports nuevos de `Building`), lo agrega al grupo `protected` y lo registra en `CityIntegrity.set_protected()`. Su HP pesa **×3** en la integridad (numerador y denominador); su caída destella la `CityBar` y marca el objetivo de defensa como fallido, sin derrota directa (la derrota sigue en integridad < 0,35). (3) La barra de ciudad se rotula **EN PIE** (`HUD_STANDING`); `offscreen_markers` marca el protegido en ámbar con prioridad máxima; `ObjectiveDefendCity` titula «PROTEGÉ: ESCUELA 12»; `RoundResult.summary_rows()` empieza por «Qué quedó en pie» (protegido en pie/dañada/caída, edificios en pie n/60, integridad) y deja el puntaje y la medalla al final. Voces: lo propio en ámbar y castellano llano; el enemigo en cian y código; el bando enemigo no se nombra nunca.

> **Nota de WP-24d parte 2 (2026-09-20)**: el usuario no entendía cómo vencer al jefe, así que la ronda 1 pasa de 3 a **5 objetivos** encadenados que enseñan: 0 `ObjectiveDefendCity` «CONTENÉ EL ASEDIO / DISPARALE A LAS RODILLAS CIAN» con contador «RODILLAS n/3» (`OBJ_COUNT_KNEES`; avanza con `enemy_part_broken`/`enemy_weak_point_state` de las 4 rodillas; cierra en `p2_alert` o a los 90 s); 1 `ObjectiveBreakParts` «ROMPÉ 3 RODILLAS / TRES RODILLAS ABREN LA CARCASA» (el contador continúa donde quedó); 2 **`ObjectiveBreakCores`** (nueva, extiende `BreakParts`) «CARCASA ABIERTA / DESTRUÍ LOS 3 NÚCLEOS DESDE ABAJO» con «NÚCLEOS n/3» (cierra con 3 núcleos, `p5_selfdestruct` o `enemy_defeated`); 3 **`ObjectiveSelfdestruct`** (nueva) «DERROTALO ANTES DE QUE DETONE» con el reloj del jefe leído por nombre de método (`remaining_method`/`total_method` exportados: `Objective` sigue sin conocer al Arachnodroid); 4 `ObjectiveDefeatEnemy` «DERROTÁ AL ENEMIGO / APUNTÁ A LO QUE SIGA EN CIAN». Exports nuevos: `count_part_ids`/`count_target`/`count_key` (DefendCity), `count_key` (BreakParts), `end_phase_id`/`enemy_ids` (BreakCores), `enemy_ids`/`remaining_method`/`total_method`/`fallback_seconds` (Selfdestruct). `ObjectiveDefendCity.get_progress()` es ahora rodillas/3 (no tiempo) y `OBJ_DEFEND_CITY_PROGRESS` quedó **huérfana** en el CSV (borrar en la limpieza de claves de WP-25). Estático nuevo `Objective.phase_index_of(enemy, phase_id)`: los objetivos comparan también la fase que trae el evento, no solo `current_phase_index()` (necesario con el jefe congelado en `round_check`). Todos los textos `OBJ_*` visibles pasan a mayúsculas de HUD y voseo. `round_check`: 15 filas (nueva «secuencia completa» que recorre los cinco eslabones con hechos sintéticos hasta VICTORY; la fila 6 exige cadena de 5 y contador traducido).

Define la capa que convierte "un dron, un coloso y una ciudad" en una **partida con principio, final y puntaje**: el catálogo estático de rondas, el nivel de batalla único, la máquina de estados de la ronda, los objetivos guiados, el resultado con medalla y la persistencia.

**Incluye**

- `RoundCatalog`: catálogo estático con ids estables, distrito, enemigos, par de tiempo y umbrales de medalla.
- `battle_level.tscn`: **un solo nivel** compartido por todas las rondas, que instancia distrito y enemigos en tiempo de ejecución.
- `RoundManager`: `INTRO` → `BATTLE` → `VICTORY` / `DEFEAT`, pausa, respawn, semilla y contabilidad de la partida.
- Objetivos del MVP sobre el `ObjectiveSequencer` existente.
- `RoundResult`, fórmula de puntaje, `result_card.tscn` y persistencia de métricas crudas.
- `rounds_menu.tscn` con medallas y bloqueo.
- `tools/round_check.tscn`.

**NO incluye**

- Comportamiento del enemigo, de sus partes o de su IA (`docs/06`, `docs/07`).
- Arma, daño, energía, casco ni la cuenta regresiva de respawn (`docs/08`, `docs/09`).
- Construcción de la ciudad ni el cálculo de integridad (`docs/10`).
- Dibujo de cualquier elemento de HUD o del menú de pausa (`docs/12`).
- Rondas 2–8 y progresión larga (WP-39, P3). El MVP congela **una** ronda.

### 1.1 Contratos que este documento consume

Firmas que `RoundManager` y los objetivos esperan, **ya conciliadas** con lo que declaran los documentos dueños. Si alguna cambia en `autoloads/events.gd`, este documento se actualiza.

| Origen | Contrato | Uso |
|---|---|---|
| este doc | `Events.round_state_changed(state: int)` | lo **emite** `RoundManager` |
| `docs/06` | `Events.enemy_spawned(enemy: Node3D, enemy_id: StringName)` | contexto y `BossBar` |
| `docs/06` | `Events.enemy_defeated(enemy: Node3D, enemy_id: StringName)` | **única** fuente de victoria |
| `docs/06` | `Events.enemy_part_broken(enemy: Node3D, part_id: StringName, position: Vector3)` | conteo de partes y objetivos |
| `docs/06` | `Events.enemy_phase_changed(enemy: Node3D, phase_id: StringName)` | objetivos y música; los ids son `StringName` (`p1_siege`, `p2_alert`, `p3_fury`, `p4_belly`, `p5_selfdestruct`) |
| `docs/06` | `EnemyBase.total_structure_ratio() -> float` | progreso del objetivo final |
| `docs/06` | `EnemyCatalog.scene_of(id) -> PackedScene`, `has_id(id)`, `ids()` | instanciado |
| `docs/08` | `Events.shot_fired(origin: Vector3, direction: Vector3)` | precisión |
| `docs/08` | `Events.hit_confirmed(position: Vector3, weak: bool, lethal: bool)` | precisión |
| `docs/09` | `Events.drone_destroyed(position: Vector3)` | conteo de muertes |
| `docs/09` | `Events.drone_respawned(score_multiplier: float)` | multiplicador y vuelta de cámara |
| `docs/10` | `Events.city_integrity_changed(ratio: float)` | **única** fuente de derrota |
| `docs/10` | `CityIntegrity.get_ratio()`, `register(b)`, `reset()`, `get_under_siege()` | resultado final, objetivos |

## 2. Catálogo de rondas

`rounds/round_catalog.gd` — `class_name RoundCatalog extends RefCounted`, sin estado de instancia. Todo el catálogo es una `const`.

> **El id es para siempre: es la clave de guardado.** `first-contact` no se renombra nunca, aunque cambien el nombre visible, el distrito o el jefe.

### 2.1 Campos de una entrada

| Campo | Tipo | Significado |
|---|---|---|
| `id` | `String` | id estable, minúsculas y guiones; clave de `best_score_<id>` |
| `name_key` | `String` | clave de traducción del nombre visible |
| `goal_key` | `String` | clave de la descripción de una línea en el menú |
| `district` | `String` | ruta de la escena del distrito, se instancia bajo `District` |
| `enemies` | `Array[String]` | ids de `EnemyCatalog`, en orden de aparición |
| `time_par` | `float` | segundos de referencia para el bono de tiempo |
| `score_gold` / `score_silver` / `score_bronze` | `int` | umbrales inclusivos de medalla |
| `unlock_after` | `String` | id que debe tener récord; `""` = siempre disponible |

### 2.2 Entradas del MVP

| # | id | name_key | distrito | enemigos | par | bronce | plata | oro | unlock_after |
|---|---|---|---|---|---|---|---|---|---|
| 0 | `first-contact` | `ROUND_FIRST_CONTACT_NAME` | `res://city/districts/district_a.tscn` | `["arachnodroid"]` | **540 s** | 350 | 800 | 2000 | `""` |

El menú muestra además una tarjeta inerte "próximamente" mientras `count() < 8`; no es una entrada del catálogo.

### 2.3 API

```gdscript
static func count() -> int
static func get_round(index: int) -> Dictionary          # {} si el índice es inválido
static func get_by_id(id: String) -> Dictionary          # {} si no existe
static func get_index(id: String) -> int                 # -1 si no existe
static func medal_for(index: int, score: int) -> int     # Medal.NONE/BRONZE/SILVER/GOLD
static func menu_entries(current_id: String) -> Array[Dictionary]
```

- `enum Medal {NONE, BRONZE, SILVER, GOLD}` vive en `RoundCatalog`.
- `medal_for()` no lee persistencia: recibe el puntaje y devuelve la medalla. Las medallas **se derivan**, nunca se guardan.
- `menu_entries(current_id)` devuelve entradas listas para `ChoiceMenu.setup(title, subtitle, entries, back_id := "")`: `{id, text_key, primary, locked}`, con `primary = true` en la ronda siguiente a `current_id` y `locked` resuelto con `GameSettings.is_round_unlocked()`. La señal de elección del menú es `chosen(id: String)` (`01` §2.3), no `option_chosen`.

## 3. Nivel de batalla

`rounds/battle_level.tscn` + `battle_level.gd`. **Único para todos los modos y rondas**: lo que cambia es el distrito y los enemigos que `RoundManager` instancia.

```
BattleLevel (Node3D, battle_level.gd)
├── WorldEnvironment            environment_battle.tres + CameraAttributesPractical  (docs/13)
├── Sun (DirectionalLight3D)    sun_dusk.tres                                        (docs/13)
├── CityIntegrity (Node)                                                             (docs/10)
├── District (Node3D)           contenedor vacío; lo puebla RoundManager
├── Enemies (Node3D)            contenedor vacío; lo puebla RoundManager
├── Respawn (Marker3D)          reaparición, 40 m sobre el borde del distrito
├── DroneRig (drone_rig.tscn)   incluye FlightHUD y FpvOverlay                       (docs/03, 12, 13)
├── Pools (Node)
│   ├── ProjectilePool                                                               (docs/08)
│   ├── DebrisPool                                                                   (docs/10)
│   └── VFXPool                                                                      (docs/13)
├── BatterySpawner (Node3D)     Slot0..Slot7 (Marker3D)                              (docs/09)
├── Cameras (Node3D)
│   ├── IntroCamera (Camera3D)
│   └── RespawnCamera (Camera3D)
├── CombatHUD (CanvasLayer)     layer 20, sobrevive al respawn                       (docs/12)
├── PauseMenu (CanvasLayer)     layer 40, host en el nivel                           (docs/12)
└── RoundManager (Node)
    └── ObjectiveSequencer (Node)
        ├── ObjectiveDefendCity
        ├── ObjectiveBreakParts
        └── ObjectiveDefeatEnemy
```

Reglas de cableado: **nadie busca nodos en la raíz**. `battle_level.gd` inyecta todas las referencias por `@export` en `RoundManager`, y `RoundManager` arma el `ObjectiveContext`.

### 3.1 Contrato de precalentamiento

`battle_level.gd` implementa el contrato opcional de `SceneTransition`:

```gdscript
signal view_warmed_up
func warm_up_view() -> void
```

`warm_up_view()` pone `IntroCamera.current = true`, fuerza `visible = true` en el `CombatHUD`, espera 3 señales `RenderingServer.frame_post_draw` (compila shaders del distrito, del jefe y del overlay) y emite `view_warmed_up`. Hasta entonces `SceneTransition` mantiene el fundido.

### 3.2 Pausa

| Nodo | `process_mode` |
|---|---|
| `BattleLevel`, `District`, `Enemies`, `DroneRig`, `Pools` | `PROCESS_MODE_PAUSABLE` |
| `RoundManager`, `ObjectiveSequencer` | `PROCESS_MODE_PAUSABLE` (el cronómetro no corre en pausa) |
| `CombatHUD` | `PROCESS_MODE_PAUSABLE` |
| `PauseMenu` | `PROCESS_MODE_WHEN_PAUSED` |
| `ResultCard` | `PROCESS_MODE_ALWAYS` |

`PauseMenu` es host del nivel: `RoundManager` conecta `resumed` → despausar y `menu` → `SceneTransition.change_scene("res://gui/main_menu.tscn")` tras `UI.confirm("MENU_QUIT_ROUND_CONFIRM")`.

## 4. RoundManager

`rounds/round_manager.gd` — `class_name RoundManager extends Node`.

### 4.1 Máquina de estados

Usa el enum compartido `Global.RoundState {INTRO, BATTLE, VICTORY, DEFEAT}` y publica cada cambio con `Events.round_state_changed(state)`.

| Estado | Entrada | Durante | Salida |
|---|---|---|---|
| `INTRO` | distrito y enemigos instanciados, dron desarmado y congelado, `IntroCamera.current = true` | travelling de 12 s sobre la ciudad hacia la silueta del coloso; `CombatHUD` en modo cinemático (solo `CityBar` y título); música `ambient` | a los 12 s, o al presionar `ui_accept` (`skip_intro()`) |
| `BATTLE` | cámara al dron, IA de enemigos habilitada, `sequencer.start_at(0)`, cronómetro en marcha | cuenta tiempo, muertes, disparos y aciertos | victoria o derrota |
| `VICTORY` | todos los ids de `round.enemies` vistos en `Events.enemy_defeated` | 1.2 s de cámara lenta (`Engine.time_scale = 0.35`), luego `ResultCard` | elección del jugador |
| `DEFEAT` | `Events.city_integrity_changed(ratio)` con `ratio < 0.35` | 1.2 s, cámara al sector más dañado, luego `ResultCard` | elección del jugador |

- La transición `INTRO → BATTLE` es irreversible; volver a presionar `ui_accept` no hace nada.
- `VICTORY` y `DEFEAT` son terminales: `stop_current()` en el secuenciador, `Engine.time_scale = 1.0` antes de mostrar la tarjeta, e ignoran eventos posteriores (un `enemy_defeated` tardío no reabre la ronda).
- La derrota tiene prioridad: si en el mismo frame se cumplen ambas, gana `DEFEAT`.

### 4.2 Instanciado

1. `var round_data := RoundCatalog.get_round(Global.selected_round)`; si está vacío, agrega `"ERR_ROUND_MISSING"` a `Global.startup_errors` y vuelve al menú.
2. `district_root.add_child(load(round_data.district).instantiate())`.
3. Por cada id de `round_data.enemies`: `EnemyCatalog.scene_of(id).instantiate()` bajo `Enemies`, colocado en los `Marker3D` del distrito llamados `EnemySpawn0..N`. Si `has_id(id)` es `false`, se registra `ERR_ENEMY_UNKNOWN` y la ronda aborta.
4. El distrito ya trae su `CityGrid`; `CityIntegrity` recibe el `grid` por `@export` y los `Building` se dan de alta con `register()`. `RoundManager` solo llama `city_integrity.reset()` antes de empezar y lee `get_ratio()` al terminar.
5. `ObjectiveContext` con `level`, `drone`, `round_manager`, `city_integrity`, `enemies` (array de `EnemyBase`), y `sequencer.setup(ctx)`.

### 4.3 Respawn y penalización

`Events.drone_destroyed(position)` → `deaths += 1` y `RespawnCamera.current = true` (encuadre del jefe atacando la ciudad). La cuenta de 12 s, la energía al 60 % y el cálculo del multiplicador son de `docs/09`: `RoundManager` **no lo recalcula**, lo toma de `Events.drone_respawned(score_multiplier)` y con esa misma señal devuelve la cámara al dron. Si la ronda termina entre la destrucción y la reaparición, usa `pow(0.6, deaths)`, que da el mismo número. El `CombatHUD` **no** se reinstancia: por eso vive en el nivel y no en el rig.

### 4.4 Semilla

`Global.round_seed` se fija en el menú de rondas y en "Reintentar" con `randi()`, salvo que la línea de comandos traiga `--seed=<n>` (leído en `Global._ready()` desde `OS.get_cmdline_user_args()`). `RoundManager` no consume la semilla directamente: reparte semillas derivadas y estables por subsistema, de modo que el orden de las llamadas no altere el resultado.

```gdscript
static func derive_seed(tag: String) -> int   # hash(str(Global.round_seed) + ":" + tag)
```

Etiquetas del MVP: `"personality"`, `"batteries"`, `"debris"`, `"camera"`, `"intro"`. Con la misma semilla y sin entrada del jugador, dos ejecuciones producen la misma apertura del jefe y los mismos puestos de pilas.

## 5. Objetivos

Sobre el framework existente: `ObjectiveSequencer` ejecuta a sus hijos `Objective` **en orden, uno por vez**, y el `CombatHUD` muestra la tarea actual. Ningún objetivo del MVP es opcional ni salteable por el jugador (`skip_current()` queda para el tutorial de P4 y para el check).

| # | Clase | `title_key` | Éxito | `get_progress()` | `get_progress_text()` |
|---|---|---|---|---|---|
| 1 | `ObjectiveDefendCity` | `OBJ_DEFEND_CITY_TITLE` | el enemigo llega a `target_phase_id` (`p2_alert`), o pasan `max_seconds` (90) | `elapsed / max_seconds` | `OBJ_DEFEND_CITY_PROGRESS` con la integridad en % |
| 2 | `ObjectiveBreakParts` | `OBJ_BREAK_PARTS_TITLE` | `required_count` (3) ids de `part_ids` rotos | `broken / required_count` | `"2 / 3"` |
| 3 | `ObjectiveDefeatEnemy` | `OBJ_DEFEAT_ENEMY_TITLE` | todos los ids de `enemy_ids` en `Events.enemy_defeated` | `1.0 - total_structure_ratio()` | `OBJ_DEFEAT_ENEMY_PROGRESS` con el % de estructura restante |
| — | `ObjectiveSurviveTime` | `OBJ_SURVIVE_TIME_TITLE` | pasan `seconds` | `elapsed / seconds` | `m:ss` restante |

`ObjectiveSurviveTime` se implementa y se verifica en WP-21 pero **no** está en la cadena de la ronda 1: queda disponible para rondas de intercepción (WP-35) y para el tutorial de combate.

### 5.1 Exports por objetivo

```gdscript
# ObjectiveDefendCity
@export var target_phase_id: StringName = &"p2_alert"   # ids de fase de docs/07
@export var max_seconds: float = 90.0

# ObjectiveBreakParts
@export var part_ids: PackedStringArray = ["wp_leg_fl_knee", "wp_leg_fr_knee", "wp_leg_bl_knee", "wp_leg_br_knee"]
@export var required_count: int = 3

# ObjectiveDefeatEnemy
@export var enemy_ids: PackedStringArray = ["arachnodroid"]

# ObjectiveSurviveTime
@export var seconds: float = 60.0
```

Heredan de `Objective` los exports `title_key`, `objective_key` y `success_delay` (0.8 s en los tres de la ronda 1). Implementan `_setup(ctx)`, `_on_start()`, `_tick(delta)` y `_on_stop()`; se desconectan de `Events` en `_on_stop()` para que `restart_current()` no duplique conexiones.

### 5.2 Texto de tarea

`get_task_text()` devuelve el texto de `objective_key` ya traducido; el `CombatHUD` lo reconstruye en `NOTIFICATION_TRANSLATION_CHANGED`. `get_success_text()` usa `OBJ_*_DONE`, se muestra 1.6 s y dispara `Events.camera_trauma(0.08, Vector3.INF)` como acuse táctil.

## 6. Resultado y puntaje

### 6.1 `RoundResult`

`rounds/results/round_result.gd` — `class_name RoundResult extends RefCounted`.

| Campo | Tipo | Origen |
|---|---|---|
| `round_id` | `String` | catálogo |
| `victory` | `bool` | estado terminal |
| `time_seconds` | `float` | tiempo acumulado en `BATTLE` (sin pausa, sin cinemática) |
| `city_integrity` | `float` | `CityIntegrity.get_ratio()` al terminar |
| `parts_broken` | `int` | `Events.enemy_part_broken` con ids distintos |
| `shots_fired` / `shots_hit` | `int` | `Events.shot_fired` / `hit_confirmed` |
| `accuracy` | `float` | `shots_hit / maxi(shots_fired, 1)` |
| `deaths` | `int` | `Events.drone_destroyed` |
| `respawn_multiplier` | `float` | `maxf(0.3, pow(0.6, deaths))` (piso 0.3, `docs/09`) |
| `base_score` / `score` | `int` | §6.2 |
| `medal` | `int` | `RoundCatalog.medal_for()` |
| `is_record` | `bool` | lo fija la persistencia |

Métodos: `compute_score(time_par: float) -> int`, `to_dictionary() -> Dictionary`, `summary_rows() -> Array[Dictionary]` (filas `{label_key, value_text, highlight}` para la tarjeta).

### 6.2 Fórmula

```
base  = 1000 · city_integrity + 40 · parts_broken − 300 · deaths + max(0, (time_par − time_seconds) · 8)
score = round( max(0, base) · respawn_multiplier )     # respawn_multiplier = max(0.3, 0.6^deaths)
```

- El multiplicador de respawn es acumulativo **con piso 0.30**: 1 muerte ×0.6, 2 muertes ×0.36, 3 o más ×0.30. El castigo de −300 por muerte **se mantiene** en el MVP (decisiones cerradas 2026-09-19; WP-23 las revisa con datos reales).
- En derrota el puntaje se calcula y se muestra, pero **no se persiste** (§7).
- Ejemplos de referencia con `time_par` **540 s**:

| Partida | integridad | partes | muertes | t | base | mult. | score | medalla |
|---|---|---|---|---|---|---|---|---|
| Impecable | 0.92 | 8 | 0 | 380 s | 5240 | 1.00 | 5240 | oro |
| Sólida | 0.78 | 9 | 0 | 445 s | 3515 | 1.00 | 3515 | oro |
| Con un respawn | 0.75 | 9 | 1 | 440 s | 3310 | 0.60 | 1986 | plata |
| Al límite | 0.40 | 8 | 2 | 560 s | 120 | 0.36 | 43 | ninguna |

> Efecto colateral del `time_par` de 540 s: con 25 puntos por segundo el bono de tiempo domina la fórmula y los umbrales 600/1300/2000 quedan cortos (tres de los cuatro ejemplos sacan oro o plata). El `time_par` queda fijo; **recalibrar el bono o los umbrales es trabajo de WP-23** (ver §12, fila 3). **Cerrado en WP-23 (2026-09-19)**: bono **8 pts/s** (`RoundResult.TIME_BONUS_PER_SECOND`; tope 4 320 con par 540) y umbrales **350 / 800 / 2000** (`RoundCatalog`). Medido con el bot: victoria limpia y rápida (0,70, 0 muertes, 400 s) = 2 220 → ORO; una muerte (0,61–0,63, 335–352 s) = 1 329–1 422 → PLATA; dos muertes y 515 s = 219 → nada. `round_check` fila 9: integridad 0,9, 8 partes, t = 400 s → base 2 340 sin muertes (ORO), 2 040 × 0,6 = 1 224 con una; fila 1 verifica `medal_for(350) == BRONCE` y `medal_for(800) == PLATA`. En **derrota** la medalla es NONE y el bono de tiempo 0 (WP-19b; el control de WP-23 había sacado «PLATA» perdiendo a los 431 s).

### 6.3 `result_card.tscn`

`rounds/results/result_card.tscn` — `CanvasLayer` (layer 45) con `process_mode = ALWAYS`, un `Control` de estadísticas y una instancia de `ChoiceMenu`.

Filas, en orden: tiempo (`RESULT_TIME`, ámbar si mejora el récord), integridad (`RESULT_INTEGRITY`), partes rotas (`RESULT_PARTS`), precisión (`RESULT_ACCURACY`), muertes (`RESULT_DEATHS`), multiplicador (`RESULT_MULTIPLIER`, solo si es menor que 1.0), puntaje (`RESULT_SCORE`, grande) y medalla. Si `is_record`, se muestra `RESULT_NEW_RECORD`.

Entradas del `ChoiceMenu`:

| id | `text_key` | `primary` | `locked` |
|---|---|---|---|
| `retry` | `RESULT_RETRY` | en derrota | nunca |
| `next` | `RESULT_NEXT` | en victoria | si no hay ronda siguiente desbloqueada |
| `rounds` | `RESULT_ROUNDS` | no | nunca |
| `menu` | `RESULT_MENU` | no | nunca |

`retry` y `next` fijan `Global.selected_round` y `Global.round_seed = randi()` y vuelven a `battle_level.tscn` con `SceneTransition.change_scene(path, true)`.

## 7. Persistencia

Solo métricas crudas, en `user://config/GameSettings.cfg`, sección `[round_progress]`, vía `ConfigFile`.

| Clave | Tipo | Escritura |
|---|---|---|
| `best_score_<id>` | `int` | solo en victoria y solo si mejora |
| `best_time_<id>` | `float` | solo en victoria y solo si mejora |

Todo lo demás **se deriva**: completada = `get_best_score(id) > 0`; medalla = `RoundCatalog.medal_for(index, get_best_score(id))`; desbloqueo = récord de `unlock_after`.

```gdscript
func record_score(id: String, score: int) -> bool   # true si es récord; guarda y llama save()
func get_best_score(id: String) -> int              # 0 si no hay
func record_time(id: String, seconds: float) -> bool
func get_best_time(id: String) -> float             # -1.0 si no hay
func is_round_unlocked(index: int) -> bool
```

`is_round_unlocked(0)` es siempre `true`. Un id desconocido devuelve valores neutros sin error: borrar el `.cfg` solo pierde progreso, nunca rompe el arranque.

## 8. Menú de rondas

`gui/rounds_menu.tscn` + `rounds_menu.gd`, derivado de `MenuScreen`. Se abre desde el menú principal con `open_submenu()`.

- Un `RoundCard` (Control con `_draw()`) por entrada: nombre (`name_key`), objetivo (`goal_key`), mejor tiempo, mejor puntaje y medalla dibujada como hexágono relleno con el color de `UIPalette`.
- Entrada bloqueada: glifo de candado, texto `ROUND_LOCKED_HINT` con el nombre de la ronda requerida, botón `disabled = true` y meta `no_focus_ring` para que el foco automático de `UI` la saltee.
- Selección: `Global.selected_round = index`, `Global.round_seed = randi()`, `SceneTransition.change_scene("res://rounds/battle_level.tscn", true)`.
- En los `.tscn` el `text` es la clave; solo se usa `tr()` donde hay formato (tiempo, puntaje). Los textos se reconstruyen en `NOTIFICATION_TRANSLATION_CHANGED`.
- Navegación por sticks provista por `StickNavigation`; sonidos y foco automático por `UI`.

## 9. Interfaz pública

### 9.1 Clases

| Archivo | Clase | Tipo |
|---|---|---|
| `rounds/round_catalog.gd` | `RoundCatalog` | `RefCounted` estático |
| `rounds/round_manager.gd` | `RoundManager` | `Node` |
| `rounds/battle_level.gd` | `BattleLevel` | `Node3D` |
| `rounds/objectives/objective_defend_city.gd` | `ObjectiveDefendCity` | `Objective` |
| `rounds/objectives/objective_break_parts.gd` | `ObjectiveBreakParts` | `Objective` |
| `rounds/objectives/objective_defeat_enemy.gd` | `ObjectiveDefeatEnemy` | `Objective` |
| `rounds/objectives/objective_survive_time.gd` | `ObjectiveSurviveTime` | `Objective` |
| `rounds/results/round_result.gd` | `RoundResult` | `RefCounted` |
| `rounds/results/result_card.gd` | `ResultCard` | `CanvasLayer` |
| `gui/rounds_menu.gd` | `RoundsMenu` | `MenuScreen` |

### 9.2 `RoundManager`

```gdscript
signal objective_text_changed(task_text: String, progress: float, progress_text: String)

@export var district_root: Node3D
@export var enemies_root: Node3D
@export var drone_rig: Node3D
@export var city_integrity: Node
@export var sequencer: ObjectiveSequencer
@export var intro_camera: Camera3D
@export var respawn_camera: Camera3D
@export var battery_spawner: Node3D
@export var result_card_scene: PackedScene

func get_state() -> int
func get_elapsed_seconds() -> float
func get_time_par() -> float
func get_round_id() -> String
func get_enemies() -> Array
func skip_intro() -> void
func request_defeat(reason_key: String) -> void
func build_result() -> RoundResult
```

`RoundManager` **emite** `Events.round_state_changed(state)` y ningún otro evento del bus: todo lo demás son hechos de otros sistemas.

### 9.3 Señales consumidas

| Señal | Efecto |
|---|---|
| `Events.enemy_defeated(enemy, enemy_id)` | marca el id; si están todos → `VICTORY` |
| `Events.city_integrity_changed(ratio)` | `ratio < 0.35` → `DEFEAT` |
| `Events.drone_destroyed(position)` | `deaths += 1`, cámara de respawn |
| `Events.drone_respawned(score_multiplier)` | guarda el multiplicador y devuelve la cámara |
| `Events.enemy_part_broken(enemy, part_id, position)` | `parts_broken += 1` con ids distintos |
| `Events.shot_fired(origin, direction)` / `Events.hit_confirmed(position, weak, lethal)` | precisión |
| `ObjectiveSequencer.all_finished` | no fuerza victoria; solo limpia la línea de tarea |

Toda conexión usa `var _discard := señal.connect(...)` por `return_value_discarded=1`, y todas las declaraciones son tipadas por `untyped_declaration=1`.

## 10. Parámetros y valores iniciales

| Parámetro | Valor | Dónde |
|---|---|---|
| Duración de `INTRO` | 12.0 s | `RoundManager.INTRO_SECONDS` |
| Acción de salteo | `ui_accept` | `_unhandled_input` |
| Umbral de derrota | integridad `< 0.35` | `RoundManager.DEFEAT_INTEGRITY` |
| Pausa dramática terminal | 1.2 s a `time_scale 0.35` | `RoundManager.OUTRO_SECONDS` |
| `time_par` ronda 1 | **540.0 s** | catálogo |
| Umbrales ronda 1 | 350 / 800 / 2000 (WP-23; eran 600 / 1300 / 2000) | catálogo |
| Peso de integridad | 1000 | fórmula |
| Peso por parte rota | 40 | fórmula |
| Castigo por muerte | −300 | fórmula |
| Bono de tiempo | 25 por segundo bajo el par | fórmula |
| Multiplicador de respawn | ×0.6 acumulativo, **piso 0.30** | `maxf(0.3, pow(0.6, deaths))` |
| Espera de respawn | 12 s (propiedad de `docs/09`) | — |
| Energía al reaparecer | 60 % (`docs/09`) | — |
| `ObjectiveDefendCity.max_seconds` | 90.0 s | export |
| `ObjectiveDefendCity.target_phase_id` | `&"p2_alert"` | export |
| `ObjectiveBreakParts.required_count` | 3 de 4 rodillas | export |
| `Objective.success_delay` | 0.8 s | export |
| Texto de éxito en pantalla | 1.6 s | `CombatHUD` |
| Puestos de pila | 8 marcadores, 5 activos (`docs/09`) | `BatterySpawner` |
| Capas de canvas del nivel | `CombatHUD` 20 · `PauseMenu` 40 · `ResultCard` 45 | `docs/12` |

## 11. Criterios de aceptación y check headless

**Check**: `tools/round_check.tscn` + `tools/round_check.gd`.

**Comando**

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/round_check.tscn
```

Corre la ronda 1 **sin jugarla**: nadie dispara, el jefe no se mueve (el nivel se instancia con `Global.debug_freeze_ai = true`) y los hechos se inyectan por el bus.

| # | Verifica | Cómo |
|---|---|---|
| 1 | Catálogo consistente | `count() == 1`; ids únicos; `get_index(get_round(0).id) == 0`; `medal_for(0, 1999) == SILVER`, `medal_for(0, 2000) == GOLD`, `medal_for(0, 599) == NONE` |
| 2 | Respaldo de configuración | Lee y guarda en memoria `best_score_first-contact` y `best_time_first-contact` antes de tocar nada |
| 3 | Instanciado | Con `Global.selected_round = 0` y `Global.round_seed = 12345`, el nivel carga, `District` tiene 1 hijo y `Enemies` tiene 1 `EnemyBase` |
| 4 | Estado inicial | `get_state() == Global.RoundState.INTRO` y hubo un `round_state_changed(INTRO)` |
| 5 | Salteo de la cinemática | `skip_intro()` → `BATTLE` en el mismo frame; un segundo `skip_intro()` no cambia nada |
| 6 | Objetivos | `objective_started(0)` emitido; `get_task_text()` no vacío; `get_progress()` dentro de `[0, 1]` |
| 7 | Determinismo de semilla | `derive_seed("batteries")` da el mismo valor en dos instanciados con la misma `round_seed` y otro distinto con otra |
| 8 | Victoria | `Events.enemy_defeated.emit(enemy, &"arachnodroid")` → `VICTORY` antes de 2 s; `Engine.time_scale` vuelve a 1.0 |
| 9 | Puntaje | Con integridad 0.9, 8 partes, 0 muertes y t = 400 s (`time_par` 540) → `base_score == 4720` y `score == 4720`; el mismo caso con 1 muerte da `base_score == 4420`, `respawn_multiplier == 0.6` y `score == 2652`; con 4 muertes, `respawn_multiplier == 0.30` (piso) |
| 10 | Persistencia | `get_best_score("first-contact")` pasa a ser el puntaje; un segundo `record_score` menor devuelve `false` y no lo pisa |
| 11 | Derrota | Segunda instancia del nivel: `Events.city_integrity_changed.emit(0.30)` → `DEFEAT`; no se escribe `best_score` |
| 12 | Prioridad | Victoria y derrota emitidas en el mismo frame → queda `DEFEAT` (es el caso real de la autodestrucción del jefe en P5) |
| 13 | Restauración | Reescribe los valores originales (o borra las claves si no existían) y lo verifica releyendo el `.cfg` |
| 14 | Sin huérfanos | `queue_free()` del nivel + 2 frames; `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` igual al valor previo |

Salida: una línea `OK`/`FAIL` por fila y `get_tree().quit(0)` solo si todas pasan; cualquier fallo imprime la fila y sale con `1`. El check nunca deja `Engine.time_scale` ni el `ConfigFile` modificados.

**Criterios de aceptación de WP-21**

- `round_check` verde.
- La ronda 1 arranca desde el menú de rondas, muestra la cinemática de 12 s y se puede saltear.
- La tarjeta de resultado muestra medalla y récord, y sus cuatro opciones funcionan.
- Ignorar la ciudad 5 minutos termina en derrota (se valida a mano en WP-23).

## 12. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| 1 | **Doble castigo por muerte** (−300 y ×0.6) | **Cerrado para el MVP (2026-09-19)**: se mantienen los dos. WP-23 midió que con 8 pts/s y el umbral viejo de 1 300 una sola muerte hacía imposible la plata (918–1 422); se bajaron los umbrales (§6.2). Propuesta en reserva: quitar el −300 y dejar el castigo solo en el multiplicador (la semilla 1 pasaría de 1 329 a 1 509) |
| 2 | Piso del multiplicador de respawn | **Cerrado (2026-09-19)**: piso **0.30**, no 0.2. `respawn_multiplier = maxf(0.3, pow(0.6, deaths))`, con `respawn_multiplier_floor` en el `HullProfile` de `docs/09` |
| 3 | `time_par` de la ronda 1 | **Cerrado (2026-09-19)**: **540 s**, para que el bono de tiempo sea alcanzable con la duración esperada de 6.5–9 min (`docs/07` §8). **Queda abierto** el efecto colateral de §6.2: con 25 pts/s el bono domina el puntaje y los umbrales 600/1300/2000 se vuelven triviales. Palancas para WP-23: bajar el bono a ~8 pts/s o subir los umbrales a 2500/4000/5500. **Cerrado (WP-23, 2026-09-19)**: bono 8 pts/s y umbrales 350/800/2000, ver §6.2 |
| 4 | Victoria y derrota se deciden **solo** por el bus. Si `docs/06` o `docs/10` no publican esos hechos, la ronda nunca termina; el check lo detecta | acordado, verificar en WP-19/20 |
| 5 | `ObjectiveDefendCity` completa por fase del enemigo: si el jefe salta de `p1_siege` a `p3_fury`, el objetivo igual cierra (se compara el **índice** de la fase alcanzada contra el de `target_phase_id` dentro de `EnemyProfile.phases`, que son ordenadas y monótonas) | resuelto |
| 6 | El `CombatHUD` vive en el nivel para sobrevivir al respawn; el `FlightHUD` muere con el dron y se reconstruye. Confirmar que no parpadea al reaparecer | verificar en WP-22 |
| 7 | Nombre de la señal de `ChoiceMenu` al elegir | **Cerrado**: es `chosen(id: String)`, no `option_chosen`; firma real verificada en `01` §2.3 |
| 8 | `district_a.tscn` debe exponer `EnemySpawn0..N` y el grupo `buildings`; lo fija `docs/10` | acordado |
| 9 | Reproducibilidad total exigiría fijar también el orden de los `randf()` de la física; el objetivo real es que la **apertura** del jefe y los puestos de pila sean reproducibles | resuelto |
| 10 | `Global.debug_freeze_ai` es una bandera solo para checks; no se expone en ningún menú | resuelto |
| 11 | **Autodestrucción del jefe (P5, `docs/07`)**: al detonar reparte 25 000 de daño a los edificios a ≤ 120 m y emite `enemy_defeated` igual. Con la ciudad al límite eso puede disparar victoria y derrota en el mismo frame; la regla de prioridad de §4.1 lo resuelve como derrota, que es lo dramáticamente correcto | resuelto |
| 12 | `Events.drone_respawned` | **Cerrado**: figura en el Contrato de Events (`docs/02` §5.1) con la firma `(score_multiplier: float)` y se declara en `autoloads/events.gd` desde WP-01 |
| 13 | `district_a.tscn` debe exponer `EnemySpawn0..N`; `docs/10` todavía no lo menciona. Confirmar en WP-20 o, si no existen, usar el centro del `CityGrid` con un desplazamiento del perfil de la ronda | pendiente |

## 13. Referencias cruzadas

- `00-plan-maestro.md` — hoja de ruta, convenciones y checkpoints.
- `04-especificacion-configuracion-y-menus.md` — `GameSettings`, `ConfigFile`, navegación y menú principal.
- `06-framework-de-enemigos.md` — `EnemyBase`, `EnemyCatalog`, partes, fases y señales del bus.
- `07-arachnodroid.md` — ids de partes, fases y duración objetivo de la ronda 1.
- `08-combate-y-armas.md` — `shot_fired`, `hit_confirmed` y la precisión del resultado.
- `09-energia-y-danio.md` — respawn de 12 s, energía al 60 %, `drone_destroyed`.
- `10-ciudad-destructible.md` — `CityIntegrity`, `district_a`, `building_destroyed`.
- `12-interfaz-y-hud.md` — `CombatHUD`, línea de tarea, `RoundTimer`, `PauseMenu`, claves `ROUND_*`/`RESULT_*`/`OBJ_*`.
- `13-identidad-visual-y-audio.md` — cámara de intro, `environment_battle.tres`, música por fase.
- `15-verificacion-y-ci.md` — registro de checks y comandos.
