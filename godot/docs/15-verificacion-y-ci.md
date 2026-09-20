# 15 — Verificación y CI

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: todos los WPs (WP-30 para CI) · Depende de: `docs/00-plan-maestro.md`, `docs/02-configuracion-del-proyecto.md`

## 1. Objetivo y alcance

> **Nota de WP-10/incidente (2026-09-19)**: (1) `run_checks.ps1`/`.sh` imponen un **timeout externo por proceso** (`-ProcessTimeout` / `PROCESS_TIMEOUT`, 420 s por defecto) además del interno de `CheckRunner`: un error de parseo en el script raíz de un check (por ejemplo, si `check_runner.gd` pierde su `class_name`) deja el proceso vivo sin escena y el timeout interno nunca corre; el externo mata el árbol y marca `FAIL`. Tras editar scripts con `class_name` hay que refrescar la caché de clases (`--editor --quit` o el paso de import del runner) antes de correr checks a mano. (2) Simulación de joypad: `Input` indexa ejes por `axis | (device << 20)`; un `InputEventJoypadMotion` con `device = -1` casa con el `InputMap` pero **no** aparece en `Input.get_joy_axis(0, eje)`; para lecturas crudas (calibración, `Controls.get_flight_input()`) inyectar con `device = 0`. (3) `CheckRunner` aísla por defecto `Global.config_dir`/`log_path` en `user://config_check_<pid>` (opt-out `isolate_config = false` en `project_check`) y las capturas van a `<shots>/<check_name>/`, así dos suites concurrentes no se pisan; `tools/out/report.txt` sigue siendo compartido: no correr dos `run_checks` a la vez.


Define **cómo se demuestra que un paquete de trabajo está terminado**: el helper común de los checks, el catálogo completo de checks headless con su comando exacto, cómo se simula entrada y tiempo sin jugador humano, cómo se mide el rendimiento, el guion del smoke test manual del MVP, el workflow de CI y la política de regresión.

**Incluye**: `tools/check_runner.gd`, los 28 checks, los presupuestos numéricos, `run_checks.ps1` / `run_checks.sh` y los cuatro jobs de CI.

**NO incluye**: el contenido funcional que cada check verifica (vive en el documento que gobierna ese WP), ni la configuración de `project.godot` (`docs/02`).

### 1.1 Filosofía

1. **Un check por feature.** Cada WP entrega exactamente una escena `tools/<x>_check.tscn`. Los checks no se fusionan ni se dividen por conveniencia.
2. **No destructivo.** Un check nunca deja el entorno del jugador peor que como lo encontró. Antes de tocar nada hace *snapshot* de los `.cfg` de `user://config/` y los restaura al salir, **también cuando falla o cuando expira el timeout**.
3. **Código de salida ≠ 0 al fallar.** Es el único contrato con CI y con el orquestador. Sin excepciones.
4. **Headless por defecto.** Solo los checks que sacan capturas corren con ventana, porque en `--headless` no hay rasterizado y `get_viewport().get_texture()` devuelve una imagen vacía.
5. **Determinista.** Nada de `randf()` sin semilla, nada de esperar «un rato». El tiempo se avanza en ticks de física contados. *Límite medido en WP-23:* con el solucionador multihilo de Jolt la misma semilla **no** reproduce una pelea completa entre corridas (la semilla 99 dio 432, 451, 515 y 548 s); la semilla fija personalidad, puestos de pila y decisiones del bot, no la física. Los checks largos aseveran sobre promedios de varias semillas y hechos cualitativos por partida.
6. **Una línea final legible.** `CHECK <nombre>: OK` o `CHECK <nombre>: FAIL (n fallos)`, con una línea por fallo antes del resumen.

Comando base:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/<x>_check.tscn
```

Variante para los que capturan:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --windowed --resolution 960x540 --path godot res://tools/<x>_check.tscn -- --shots=<dir>
```

Todo lo que va después de `--` lo lee el juego con `OS.get_cmdline_user_args()`.

---

## 2. `tools/check_runner.gd`

```gdscript
class_name CheckRunner extends Node

signal check_finished(ok: bool, failures: int)

@export var check_name: String = ""
@export var default_timeout: float = 60.0

var failures: Array[String] = []
var shots_dir: String = ""

func expect(cond: bool, msg: String) -> void
func expect_near(a: float, b: float, tol: float, msg: String) -> void
func fail(msg: String) -> void
func finish() -> void

func user_args() -> Dictionary
func wait_physics(ticks: int) -> void
func wait_frames(count: int) -> void
func shot(name: String) -> void
```

### 2.1 Contrato de cada método

| Método | Comportamiento |
|---|---|
| `expect(cond, msg)` | Si `cond` es falso, añade `msg` a `failures` e imprime `  FAIL: <msg>`. No corta la ejecución: un check debe reportar **todos** sus fallos de una pasada |
| `expect_near(a, b, tol, msg)` | `expect(absf(a - b) <= tol, "%s (esperado %.4f, obtenido %.4f, tol %.4f)" % [...])`. Falla también si `a` es `NAN` o `INF` |
| `fail(msg)` | Añade un fallo incondicional |
| `finish()` | Restaura la configuración, imprime el resumen y llama `get_tree().quit(0 if failures.is_empty() else 1)` |
| `user_args()` | Parsea `OS.get_cmdline_user_args()` a `{clave: valor}`; `--shots=dir` → `{"shots": "dir"}`, `--timeout=30` → `{"timeout": "30"}`, banderas sueltas → `{"flag": "true"}` |
| `wait_physics(ticks)` | `for i in ticks: await get_tree().physics_frame` |
| `wait_frames(count)` | Ídem con `process_frame` |
| `shot(name)` | Si `shots_dir` no está vacío: `await RenderingServer.frame_post_draw`, luego `get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [shots_dir, check_name, name])` |

### 2.2 Ciclo de vida

`_ready()` hace, en este orden:

1. Lee `user_args()`. `shots_dir` = `shots` si viene; el timeout es `timeout` si viene, si no `default_timeout`.
2. Crea `shots_dir` con `DirAccess.make_dir_recursive_absolute` si hace falta.
3. **Snapshot de configuración**: copia el contenido de `user://config/*.cfg` a un `Dictionary` en memoria (bytes crudos) y guarda la lista de archivos que existían.
4. Arranca un `SceneTreeTimer` de timeout que, al vencer, llama `fail("timeout de %.1f s")` y `finish()`.
5. Emite `check_started` y cede el control a `_run()`, el método que sobrescribe cada check concreto.

`finish()` hace, en este orden:

1. Cancela el timer de timeout.
2. **Restaura la configuración**: reescribe cada `.cfg` con sus bytes originales y **borra** los que el check hubiera creado y no existieran antes.
3. Imprime `CHECK <check_name>: OK` o `CHECK <check_name>: FAIL (n fallos)`.
4. Emite `check_finished` y llama `get_tree().quit(codigo)`.

La restauración en el paso 2 es incondicional: se ejecuta igual si el check falló, si expiró el timeout o si `_run()` lanzó un error. Es la garantía de la regla 2 de §1.1.

### 2.3 Escena tipo

`tools/<x>_check.tscn` es un `Node` raíz con `tools/<x>_check.gd` (`extends CheckRunner`), `check_name` fijado en el inspector, y como hijos lo mínimo que la feature necesite. Nunca instancia el menú principal ni `boot_sequence.tscn`, salvo `boot_check` y `ui_smoke_test`, que son precisamente los que los prueban.

---

## 3. Catálogo de checks

Comando abreviado: `GODOT` = `"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe"`, `P` = `--headless --path godot`, `PW` = `--windowed --resolution 960x540 --path godot`.

| Check | WP | Qué verifica | Comando |
|---|---|---|---|
| `project_check` | 01 | 11 capas 3D nombradas; 11 autoloads en orden; `forward_plus`; Jolt Physics a 100 Hz; las 28 acciones de input con sus deadzones (0.01 en vuelo, 0.35 en `fire`/`lock_target`); ninguna acción `ui_*` con `InputEventJoypadMotion`; `.gdignore` presente; `Events` con sus **21 señales** y el número de argumentos de cada una (`docs/02` §5.1) | `GODOT P res://tools/project_check.tscn` |
| `ui_smoke_test` | 02, 09, 11 | Recorre boot → menú principal → los 4 menús de opciones → quad → ayuda → rondas → pausa, navegando con `ui_*` sintéticos. Cero `push_error`, cero nodos huérfanos al salir, todas las etiquetas con clave de traducción resuelta (ninguna cadena empieza por un prefijo conocido sin traducir) | `GODOT PW res://tools/ui_smoke_test.tscn -- --shots=tools/out/shots` |
| `settings_check` | 03 | Round-trip guardar/cargar de los 5 `.cfg` (`Audio`, `GameSettings`, `Graphics`, `Quad`, `InputMap`): escribe valores no-default, recarga, compara campo a campo. Un `.cfg` corrupto produce una **clave de traducción** en `Global.startup_errors`, no un crash | `GODOT P res://tools/settings_check.tscn` |
| `flight_bench` | 04 | Banco de física sin controlador: con acelerador estable, el empuje de hover iguala `masa × g` con **± 3 %**; 60 s de simulación sin `NAN` ni `INF` en posición, velocidad, cuaternión ni RPM; el efecto suelo multiplica entre 1.0 y 2.0 | `GODOT P res://tools/flight_bench.tscn -- --timeout=120` |
| `flight_check` | 05 | Arma con acelerador bajo; flota 5 s con deriva de altura < 0.5 m; escalón de 30° en HORIZON **asentado en < 1.0 s** con sobrepaso **< 15 %**; `reset_requested` → `respawned` y la transform coincide con `respawn_point`; `TIME_PHYSICS_PROCESS` medio **< 1.6 ms/tick** en 300 ticks | `GODOT P res://tools/flight_check.tscn -- --timeout=120` |
| `hud_projection_check` | 06, 08 | `FPVCamera.project_direction()` no devuelve `NAN` en los tres modos de fisheye (OFF / FAST / FULL) para 64 direcciones de muestra; los puntos detrás de la cámara se reportan como inválidos, no como coordenadas absurdas; captura con los 12 componentes del FlightHUD activos | `GODOT PW res://tools/hud_projection_check.tscn -- --shots=tools/out/shots` |
| `audio_check` | 07, 27 | Los **7 buses** (`Master`, `Motors`, `Weapons`, `Enemies`, `City`, `UI`, `Music`) existen con el nombre exacto y enrutan a `Master`; los loops de motor cargan y el crossfade por bandas de RPM no salta de golpe; en la escena de combate completa hay **≤ 24 voces** simultáneas; ningún `AudioStreamPlayer3D` con `max_distance` 0 | `GODOT P res://tools/audio_check.tscn` |
| `controls_check` | 10 | Con joypad simulado (§4): asignar un binding lo persiste en `InputMap.cfg`; el rango de eje `[min, max]` se guarda y se relee; la calibración de 14 pasos detecta los 4 ejes y guarda la inversión; un `reset` vuelve al default. Todo sobrevive a recargar `Controls` | `GODOT P res://tools/controls_check.tscn -- --timeout=90` |
| `boot_check` | 11 | La secuencia de arranque «Ominoso» corre entera, es **saltable** con `ui_cancel` en cualquier momento, y termina siempre en el menú principal; no deja `AudioStreamPlayer` sonando | `GODOT PW res://tools/boot_check.tscn -- --shots=tools/out/shots` |
| `loading_check` | 11 | `SceneTransition` carga y descarga una escena pesada 5 veces seguidas: `OBJECT_NODE_COUNT` vuelve al valor inicial ± 2 (sin fugas), el fundido no se queda a medias y `warm_up_view()` termina antes del fade-in | `GODOT P res://tools/loading_check.tscn -- --timeout=120` |
| `pause_check` | WP-11 | En `free_flight_level`: `pause_menu` pausa el árbol y la física (el dron no cae), `resumed` despausa solo tras soltar la entrada (respaldo 0,35 s), `menu` vuelve al menú principal con confirmación, `change_camera` cicla las cámaras; sin nodos huérfanos | `GODOT P res://tools/pause_check.tscn` |
| `enemy_import_check` | 12 | 31 partes con `part_id`; jerarquía exacta de `docs/05` §4.4; pivotes a **< 0.05 m** de lo declarado; `collision_layer` 4 (cuerpo) u 8 (punto débil) con máscaras 387 / 3; los 9 metadatos presentes; altura total **29.25 ± 0.1 m**; sin LOD; `sync_to_physics == false` | `GODOT P res://tools/enemy_import_check.tscn` |
| `city_import_check` | 13 | Las **13 piezas** del pack importan; `BuildingBlock_1` mide entre **12 y 16 m** de alto; la VRAM de texturas de ciudad suma **< 90 MB** (estimación analítica leyendo los `.import` con `ConfigFile`, **no** `RENDER_VIDEO_MEM_USED`: en `--headless` el controlador de render es nulo, ver `docs/10` §11.1); cada pieza tiene colisión y LODs generados | `GODOT P res://tools/city_import_check.tscn` |
| `weapon_check` | 14 | 100 disparos programáticos: cadencia **8/s ± 2 %**; dispersión base 0.35° que crece 0.9°/s hasta tope 2.2°; el calor bloquea entre los disparos **22 y 23** y el `overheat_lock` dura 1.8 s; daño **1.2** al casco blindado (armor 0.90), **36** al punto débil (×3.0), daño estructural a la ciudad; el retroceso aplica 0.9 N·s al `RigidBody3D` | `GODOT P res://tools/weapon_check.tscn -- --timeout=90` |
| `energy_check` | 15 | Drenaje base 0.55 %/s armado, `+0.85 × throttle` %/s, 0.45 % por disparo; `BatteryPickup` suma **+30 %**; bajo 15 % el empuje cae a ×0.82; a 0 % hay desarme forzado; el respawn dura **12 s** y durante esos 12 s la ciudad sigue recibiendo daño; el multiplicador de puntaje pasa a ×0.6 | `GODOT P res://tools/energy_check.tscn -- --timeout=120` |
| `enemy_parts_check` | 16 | Romper 4 partes genera **4 `DebrisChunk`**; la función asociada (`function`) queda deshabilitada; nunca hay **> 24** escombros vivos (el pool recicla el más viejo); al desprender una parte, sus hijos se van con ella; cero nodos huérfanos tras 60 s | `GODOT P res://tools/enemy_parts_check.tscn -- --timeout=90` |
| `gait_check` | 17 | Tres terrenos (rampa 20°, escalones de 4 m, roca): deslizamiento de pie apoyado **< 0.25 m**; ningún pie flotando **> 0.3 m** durante **> 0.2 s**; 120 s continuos sin `NAN` en el IK; el cuerpo sigue el plano de mínimos cuadrados de los pies | `GODOT P res://tools/gait_check.tscn -- --timeout=240` |
| `ai_check` | 18 | Tres semillas de `Personality` producen **tres distribuciones de acciones distintas** (distancia L1 entre histogramas > 0.15); **toda** acción ejecutada tuvo telegrafía **≥ 0.8 s**; la LOS se pierde al interponer un edificio y se recupera, con memoria de 4.5 s | `GODOT P res://tools/ai_check.tscn -- --timeout=180` |
| `arachnodroid_check` | 19 | Aplicando daño programático se alcanzan las **5 fases** en orden; los cooldowns de las 9 acciones se respetan (ninguna se repite antes de su cooldown); la señal `enemy_defeated` se emite **exactamente una vez** | `GODOT P res://tools/arachnodroid_check.tscn -- --timeout=180` |
| `city_check` | 20 | El distrito tiene **60 edificios**; la suma de HP es **120 000 ± 5 %**; cada edificio pasa por las 3 etapas (`INTACT → DAMAGED → RUBBLE`) en orden; `CityIntegrity` es **monótona decreciente**; bajo 0.35 se emite derrota | `GODOT P res://tools/city_check.tscn -- --timeout=120` |
| `round_check` | 21 | La ronda 1 se juega sin pilotar: `INTRO → BATTLE → VICTORY` con victoria forzada, y `INTRO → BATTLE → DEFEAT` con integridad forzada a 0.30; el `INTRO` es saltable; las métricas (`best_score_<id>`, `best_time_<id>`) persisten; **la configuración del jugador queda restaurada** | `GODOT P res://tools/round_check.tscn -- --timeout=180` |
| `combat_hud_check` | 22 | Capturas de los **10 componentes** del CombatHUD (energía, casco, calor, retículo, hitmarker, barra de jefe, integridad de ciudad, marcadores fuera de pantalla, dirección de daño, temporizador); ningún marcador con coordenada `NAN`; los marcadores de objetivos detrás de la cámara se clampean al borde | `GODOT PW res://tools/combat_hud_check.tscn -- --shots=tools/out/shots` |
| `balance_check` | 23 | **Extendido** (`-Extended`): `BotPilot` juega la ronda 1 real con 3 semillas + control idle a `time_scale` 4; asevera duración, integridad, muertes, fuego, acierto y ventanas sobre la media (`docs/07` §14), derrota del control por integridad, sin NaN, física mediana bajo guarda, `time_scale` restaurado y prueba negativa; ~541 s | `GODOT P res://tools/balance_check.tscn -- --timeout=1500` |
| `render_check` | 24 | Escena completa (jefe + 60 edificios + fisheye FAST, preset HIGH) a 1080p: **≥ 60 fps** de media en 300 frames; `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` **< 900**; el `Environment` compartido carga con SDFGI, SSAO, niebla volumétrica y glow activos | `GODOT --windowed --resolution 1920x1080 --path godot res://tools/render_check.tscn -- --shots=tools/out/shots` |
| `vfx_check` | 26 | Con todos los efectos disparados a la vez hay **≤ 12 emisores `GPUParticles3D`** activos; ninguno con `amount` por encima de su presupuesto; los `Decal` se reciclan y no crecen sin límite | `GODOT PW res://tools/vfx_check.tscn -- --shots=tools/out/shots` |
| `shake_check` | 28 | El trauma de `CameraRig` decae a 0 en el tiempo declarado; la magnitud está acotada (nunca saca la cámara más de su límite); dos traumas simultáneos no se suman por encima de 1.0; el overlay FPV reacciona a daño y EMP sin dejar el glitch pegado | `GODOT PW res://tools/shake_check.tscn -- --shots=tools/out/shots` |
| `perf_report` | 29 | **No es un test binario**: mide y compara. Ejecuta tres escenarios (vuelo solo, jefe, jefe + ciudad) 300 frames cada uno, registra los 5 monitores de §5 y escribe `docs/perf/<fecha>.json`. Falla si algún presupuesto de §5.2 se supera **o** si hay una regresión **> 10 %** contra la referencia | `GODOT --windowed --resolution 1920x1080 --path godot res://tools/perf_report.tscn -- --shots=tools/out/shots` |
| `menu_shots_check` | 25 | Instancia las 8 pantallas obligatorias de `docs/13` §10.5 (principal con backdrop vivo, rondas, hub de opciones, juego+HUD con preview, gráficos, audio, controles, hangar) y captura una imagen de cada una. **Falla** si alguna pantalla no se instancia o si algún `Label` muestra su propia clave de traducción (síntoma de clave faltante en el CSV) | `GODOT PW res://tools/menu_shots_check.tscn -- --shots=tools/out/shots` |
| `enemy_catalog_check` | 31…39 (P3) | Check transversal del catálogo de `docs/14` §9: toda entrada de `EnemyCatalog.ENTRIES` resuelve escena y perfil; cada enemigo construye su grafo de partes sin errores, respeta su altura declarada ±0.15 m y el presupuesto de **< 18 000** triángulos; ≥ 3 ataques, entre 2 y 5 fases monótonas, `effective_windup() >= 0.80` en todas ellas, ≥ 1 punto débil y ≥ 1 parte `detachable`; claves `ENEMY_*`/`ATK_*`/`WP_*` presentes; **0** `Area3D` como hitbox. Crece con cada WP de P3, además del `tools/<enemy>_check.tscn` propio de cada uno | `GODOT P res://tools/enemy_catalog_check.tscn -- --timeout=180` |
| `render_parity_check` | 24+ | **Informativo, nunca bloqueante.** Compara las capturas de `tools/out/shots/` contra un conjunto de referencia en `docs/perf/shots_ref/` y reporta el porcentaje de píxeles que difieren por encima de un umbral. Siempre sale con 0; su salida se lee a mano | `GODOT PW res://tools/render_parity_check.tscn -- --shots=tools/out/shots` |

### 3.1 Checks que **no** corren con `--headless`

Los diez que usan `PW` en la tabla necesitan un framebuffer real, porque miden o capturan imagen y en `--headless` el controlador de render es nulo: `ui_smoke_test`, `hud_projection_check`, `boot_check`, `combat_hud_check`, `menu_shots_check`, `render_check`, `vfx_check`, `shake_check`, `perf_report` y `render_parity_check`. Los **18 restantes** son headless puros y son los que CI corre sin discusión (§7.1 y D-1).

`hud_projection_check` y `combat_hud_check` tienen además una parte puramente numérica que **sí** corre headless (`docs/12` §9.1); `render_check` y `perf_report` no, y quedan marcados como **solo local** si `xvfb-run` no resulta fiable en el contenedor.

---

## 4. Simular entrada y tiempo sin jugador

### 4.1 Joypad sintético

Los eventos se inyectan con `Input.parse_input_event`, que los procesa como si vinieran del sistema. Las entradas del `InputMap` se serializan con `device: -1` (*cualquier dispositivo*), así que un evento inyectado con `device = -1` casa con todas ellas.

```gdscript
func press_axis(axis: JoyAxis, value: float) -> void:
    var ev := InputEventJoypadMotion.new()
    ev.device = -1
    ev.axis = axis
    ev.axis_value = value
    Input.parse_input_event(ev)

func press_button(button: JoyButton, pressed: bool) -> void:
    var ev := InputEventJoypadButton.new()
    ev.device = -1
    ev.button_index = button
    ev.pressed = pressed
    Input.parse_input_event(ev)
```

Reglas de uso:

- Un eje **se mantiene** en su último valor hasta que se inyecte otro evento. Para «soltar» un stick hay que inyectar `0.0` explícitamente; para un gatillo, `-1.0`.
- Tras inyectar hay que **ceder al menos un frame** (`await get_tree().process_frame`) antes de leer `Input.is_action_pressed` o `get_action_strength`.
- Para acciones puramente digitales es más simple y más robusto `Input.action_press(name)` / `Input.action_release(name)`, que saltan el `InputMap` y fijan el estado directamente. Se usa así en `ui_smoke_test`.
- `controls_check` **sí** debe usar `parse_input_event`, porque lo que prueba es precisamente la resolución del `InputMap` y la captura de bindings.

### 4.2 Tiempo y daño

| Necesidad | Mecanismo |
|---|---|
| Avanzar N ticks de física | `await get_tree().physics_frame` en bucle (`CheckRunner.wait_physics`) |
| Acelerar una espera larga | `Engine.time_scale = 4.0`. **Nunca** por encima de 4.0: el integrador de vuelo y el IK se vuelven imprecisos y aparecen falsos positivos |
| Simular 120 s de marcha en menos tiempo | Subir `Engine.physics_ticks_per_second` **no sirve** (cambia la dinámica). Se usa `time_scale` y se acepta el coste |
| Aplicar daño | Llamar directamente al método público (`EnemyPart.take_damage`, `Building.take_damage`, `Hull.apply_damage`), nunca simular disparos, salvo en `weapon_check` que es justo lo que prueba |
| Forzar una fase | Aplicar el daño programático que la desbloquea, no fijar la fase a mano: el check debe probar la transición |

`Engine.time_scale` se restaura a 1.0 en `finish()`, como parte de la restauración de estado.

---

## 5. Medición de rendimiento

### 5.1 Método

Ventana de **300 frames**, descartando los **60 primeros** (compilación de shaders y calentamiento de SDFGI). Por cada frame se acumula:

| Monitor | Constante | Unidad | Uso |
|---|---|---|---|
| Tiempo de física | `Performance.TIME_PHYSICS_PROCESS` | s (se reporta en ms) | Presupuesto principal |
| Draw calls | `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` | conteo | Presupuesto de render |
| Primitivas | `Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME` | conteo | Detecta geometría fuera de control |
| VRAM | `Performance.RENDER_VIDEO_MEM_USED` | bytes | Texturas y buffers |
| Nodos | `Performance.OBJECT_NODE_COUNT` | conteo | Detecta fugas entre escenarios |

Se reportan **media, p95 y máximo** de cada uno. La media sola esconde los picos, que son lo que el jugador siente.

Los FPS se derivan de `Performance.TIME_PROCESS + TIME_PHYSICS_PROCESS` medidos, no de `Engine.get_frames_per_second()`, que está limitado por vsync. `render_check` corre con `--disable-vsync` para que el techo no lo imponga el monitor. *Corrección de WP-23:* `TIME_PROCESS` incluye la espera del hilo principal por la GPU, así que en una escena limitada por render la derivación miente (1,7 «fps» contra 66 reales); `tools/perf_report` reporta la media derivada, la **mediana** derivada y `Engine.get_frames_per_second()` con vsync apagado, y el veredicto se toma con esta última. `RENDER_VIDEO_MEM_USED` cuenta toda la memoria de vídeo (1,5 GB) y **no** es comparable con el techo de 90 MB de texturas de ciudad, que mide `city_import_check`.

### 5.2 Presupuestos

| Escenario | Métrica | Presupuesto |
|---|---|---|
| P0 (vuelo solo, sandbox) | `TIME_PHYSICS_PROCESS` medio | **< 1.6 ms/tick** |
| Jefe + ciudad completa | `TIME_PHYSICS_PROCESS` medio | **< 2.0 ms/tick** |
| Jefe + ciudad completa | Draw calls | **< 900** |
| 1080p, preset HIGH, fisheye FAST, jefe + 60 edificios | FPS medio | **≥ 60** |
| Ciudad completa | VRAM de texturas | **< 90 MB** |
| Escombros vivos | Conteo | **≤ 24** |
| Voces de audio | Conteo | **≤ 24** |
| Emisores de partículas | Conteo | **≤ 12** |

A 100 Hz, 2.0 ms/tick son 200 ms de física por segundo de juego: el 20 % de un núcleo. Ese es el techo, no el objetivo.

**Medido en WP-23** (`docs/perf/2026-09-19.json`, 1080p, vsync apagado, hardware del usuario): física media 1,31 / 1,61 / **2,98** ms/tick en `flight_only` / `boss` / `boss_and_city` (en combate real 2,1–3,8: proyectiles, escombros rodando y derrumbes); draw calls 173 / 87 / 453; FPS de motor 57 / 65 / **48**. Incumplen el presupuesto de física con ciudad y los 60 fps: trabajo de WP-24 (Environment/presets) y WP-29 (optimización).

### 5.3 `docs/perf/<fecha>.json`

```json
{
  "date": "2026-09-19",
  "godot": "4.7.stable",
  "commit": "c320e96",
  "scenarios": {
    "flight_only":  {"physics_ms_avg": 0.0, "physics_ms_p95": 0.0, "draw_calls_avg": 0,
                     "primitives_avg": 0, "vram_bytes": 0, "node_count": 0, "fps_avg": 0.0},
    "boss":         {"...": 0},
    "boss_and_city":{"...": 0}
  }
}
```

---

## 6. Smoke test manual del MVP

Quince pasos, a jugar con la radio real. Cada uno indica **qué observar**; si lo observado no coincide, el MVP no está listo.

| # | Acción | Qué observar |
|---|---|---|
| 1 | Arrancar el juego | Boot «Ominoso» completo, saltable; el menú detecta la radio y la muestra; sin `startup_errors` en pantalla |
| 2 | Opciones → Controles → recalibrar `fire` | Las barras de ejes reaccionan en vivo; el popup de captura toma el gatillo; al reiniciar el juego el binding sigue puesto |
| 3 | Jugar → Ronda 1 | `INTRO` cinemático: ciudad al anochecer, silueta del jefe recortada contra el cielo; se salta con `ui_cancel` y no vuelve a aparecer |
| 4 | Armar | FlightHUD completo (horizonte, escalera, cintas, compás, sticks, RPM) y CombatHUD con energía 100, casco 100, calor 0, ciudad 100 % |
| 5 | Disparar al casco blindado | Hitmarker **blanco**, daño ínfimo (1.2 por impacto), y bloqueo por calor a los **~22 disparos** con aviso visible |
| 6 | Disparar a una rodilla cian | Hitmarker **ámbar**, la barra de la parte baja rápido; al romperla la pata **se desprende**, cae como `DebrisChunk`, levanta polvo, sacude la cámara y el jefe **cojea** (−15 % de velocidad) |
| 7 | Dejar que use `siege_beam` | Telegrafía de 1.8 s con luz y sonido; el edificio objetivo queda **marcado en el HUD**; pasa a dañado y luego a ruinas; la integridad de la ciudad baja de forma visible |
| 8 | Dejarse alcanzar por `stomp` | **Decal rojo en el suelo 1.1 s antes**; al recibirlo, −45 de casco y arco rojo de dirección de daño |
| 9 | Volar hasta bajar de 15 % de energía | Aviso en el HUD y **pérdida de empuje** perceptible (×0.82); recoger una pila devuelve +30 % |
| 10 | Dejar que use `emp_pulse` | −25 % de energía y **glitch de 3 s** en el overlay FPV |
| 11 | Romper tres rodillas | La carcasa se abre; el núcleo ventral solo es alcanzable **desde abajo** (cono de 70°) |
| 12 | Morir | 12 s de reconstrucción con la cámara mirando la ciudad, que **sigue sufriendo**; al volver, el multiplicador de puntaje está reducido |
| 13 | Ganar | Tarjeta de resultados con el desglose del puntaje y el récord guardado |
| 14 | Repetir la ronda | La semilla cambia: las aperturas del jefe son distintas y la distribución de acciones no se repite |
| 15 | Ignorar la ciudad 5 min | Derrota por integridad **< 35 %**, con la pantalla correspondiente |

Duración esperada de una partida ganada: **6.5 a 9 minutos**. Si se gana en menos de 5 o se tarda más de 12, el balance de `docs/07` está mal y WP-23 no cierra.

---

## 7. Ejecución: local y CI

### 7.1 `tools/run_checks.ps1`

Script de PowerShell que corre **todos** los checks en orden, acumula el resultado y escribe `tools/out/report.txt`.

```powershell
param([string]$Only = "", [string]$Godot = "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe")

$headless = @("project_check","settings_check","flight_bench","flight_check","audio_check",
              "controls_check","loading_check","enemy_import_check","city_import_check",
              "weapon_check","energy_check","enemy_parts_check","gait_check","ai_check",
              "arachnodroid_check","city_check","round_check","enemy_catalog_check")
$windowed = @("ui_smoke_test","hud_projection_check","boot_check","combat_hud_check",
              "menu_shots_check","render_check","vfx_check","shake_check","perf_report",
              "render_parity_check")
# 1) editor import + sin errores; 2) cada check; 3) resumen y exit code
```

Comportamiento obligatorio:

1. Primero ejecuta `--headless --path godot --editor --quit` y **falla** si la salida contiene `ERROR:` o `SCRIPT ERROR:`.
2. Luego cada check, capturando su salida en `tools/out/report.txt` con una línea de encabezado por check.
3. `-Only <nombre>` corre uno solo.
4. `-Extended` (PowerShell) o `RUN_EXTENDED=1` (bash) suma al final los **checks extendidos**: `balance_check` (WP-23, cuatro partidas simuladas a `time_scale` 4, ~9 min, `--timeout=1500`, timeout externo propio de 1 800 s). `-Only balance_check` también lo corre. `tools/perf_report.tscn` no es un check: se corre a mano con ventana (`--windowed --resolution 1920x1080 --disable-vsync`) y escribe `docs/perf/<fecha>.json`.
4. Sale con **1** si algún check salió distinto de 0; con 0 si todos pasaron. `render_parity_check` no cuenta para el código de salida.
5. `tools/out/` está en `.gitignore`.

`tools/run_checks.sh` es el equivalente para el contenedor Linux de CI: misma lista, mismo orden, mismo contrato. Los checks con ventana corren bajo `xvfb-run` cuando no hay display.

### 7.2 Workflow

Cuatro jobs encadenados en `.github/workflows/deploy-to-itch.yml`: **`import` → `checks` → `export` → `deploy-itch`** (`if: false`). El YAML completo está en `docs/02-configuracion-del-proyecto.md` §9; aquí van solo las reglas que le competen a este documento:

- `import` cachea `godot/.godot/imported/` con clave `hashFiles('godot/**/*.import', 'godot/project.godot')` y publica `godot/.godot/` como artefacto para los jobs siguientes. Sin ese artefacto, `checks` reimportaría todo.
- `checks` corre `bash godot/tools/run_checks.sh` y sube **siempre** (`if: always()`) `godot/tools/out/report.txt` y `godot/tools/out/shots/` como artefacto `check-report`. Que el job falle no debe impedir ver por qué.
- `export` solo corre si `checks` pasó, y exporta **únicamente** el preset `Windows Desktop`.
- `deploy-itch` queda con `if: false` hasta que el juego se publique.

---

## 8. Política de regresión

1. **Un WP no cierra si su check falla.** Sin excepciones, sin «lo arreglo en el siguiente».
2. **Un WP tampoco cierra si rompe un check anterior.** Antes del commit se corre `run_checks.ps1` completo. Si un check de otro WP se pone en rojo, arreglarlo es parte del WP actual.
3. **`perf_report` compara contra la referencia.** La referencia es el `docs/perf/<fecha>.json` más reciente commiteado. Una regresión **> 10 %** en `physics_ms_avg`, `draw_calls_avg` o `fps_avg` hace fallar el check.
4. **Actualizar la referencia es un acto explícito.** Se commitea un `docs/perf/<fecha>.json` nuevo con una línea en el mensaje de commit justificando por qué el coste subió. Nunca se sobrescribe el archivo anterior.
5. **Los checks informativos no bloquean.** `render_parity_check` reporta y sale con 0; su resultado se mira a ojo en el artefacto de CI.
6. **Un check que hay que desactivar es una deuda registrada**, no un archivo borrado: se le pone un `skip` explícito con el motivo y se anota en `docs/00` como pendiente.

---

## 9. Interfaz pública

| Elemento | Definición |
|---|---|
| `res://tools/check_runner.gd` | `class_name CheckRunner extends Node` — API de §2 |
| `CheckRunner._run()` | Método virtual que sobrescribe cada check concreto; corutina (`async`) |
| `CheckRunner.check_finished` | `signal check_finished(ok: bool, failures: int)` |
| `tools/<x>_check.tscn` | Escena raíz de cada check, 28 en total (18 headless + 10 con ventana, §3.1) |
| `tools/run_checks.ps1` / `.sh` | Runner local y de CI (§7.1) |
| `tools/out/report.txt` | Salida agregada; artefacto de CI |
| `tools/out/shots/<check>_<nombre>.png` | Capturas; artefacto de CI |
| `docs/perf/<fecha>.json` | Referencia de rendimiento (§5.3) |

Convenciones que todo check respeta: tipado estricto, `var _discard := señal.connect(...)`, cero cadenas visibles sin clave de traducción, y **cero escrituras permanentes** en `user://`.

---

## 10. Parámetros y valores iniciales

| Parámetro | Valor |
|---|---|
| Timeout por defecto de un check | 60 s |
| Timeout de los checks largos | 90–240 s, declarado con `--timeout=` |
| Ventana de medición | 300 frames |
| Frames descartados al inicio | 60 |
| `Engine.time_scale` máximo permitido | 4.0 (`balance_check` lo respeta y por eso tarda 541 s; `arachnodroid_check` usa 8.0 sobre un mundo sintético sin dron físico) |
| Resolución de capturas | 960×540 (1920×1080 en `render_check` y `perf_report`) |
| Física, P0 | < 1.6 ms/tick |
| Física, jefe + ciudad | < 2.0 ms/tick |
| Draw calls | < 900 |
| FPS, 1080p preset HIGH | ≥ 60 |
| VRAM de texturas de ciudad | < 90 MB |
| Umbral de regresión | 10 % |
| Checks en el catálogo | 28 (18 headless + 10 con ventana) |

---

## 11. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| D-1 | Capturas en CI (contenedor sin display) | **Propuesta**: `xvfb-run` para los 10 checks con ventana (§3.1). Si da problemas, esos checks se marcan como «solo local» y CI corre solo los 18 headless |
| D-2 | `--disable-vsync` en `render_check` | **Propuesta**; si el flag no existe con ese nombre en 4.7, usar `Graphics` para fijar `vsync_mode = 0` desde el propio check |
| D-3 | FPS derivados de monitores en vez de `get_frames_per_second()` | **Propuesta**. En una máquina de CI sin GPU el número no es comparable con el de escritorio; `render_check` puede tener que marcarse como «solo local» |
| D-4 | Umbral de distancia L1 > 0.15 entre histogramas en `ai_check` | **Propuesta** sin calibrar; se ajusta en WP-18 con datos reales |
| D-5 | `render_parity_check` necesita un conjunto de referencia | **Abierto**: las imágenes de `docs/perf/shots_ref/` se generan al cerrar WP-24 y se commitean entonces |
| D-6 | Presupuesto de 900 draw calls | Del plan, sin medición previa sobre esta ciudad. Se confirma o se renegocia en WP-24 |
| D-7 | Restaurar `user://config` copiando bytes | **Propuesta**. Alternativa más simple: apuntar `Global.config_dir` a un directorio temporal durante los checks. Es más limpio pero exige que los 5 autoloads lean siempre de `Global.config_dir` y nunca de una ruta fija |
| D-8 | `ui_smoke_test` crece en tres WPs distintos (02, 09, 11) | Aceptado; es el único check que se amplía. Cada ampliación mantiene verdes los pasos anteriores |

---

## 12. Referencias cruzadas

- `docs/00-plan-maestro.md` — hoja de ruta; el criterio de aceptación de cada WP apunta a un check de §3.
- `docs/02-configuracion-del-proyecto.md` — `project_check` en detalle y el YAML completo del workflow (§9).
- `docs/03-especificacion-nucleo-de-vuelo.md` — métricas de `flight_bench` y `flight_check`.
- `docs/04-especificacion-configuracion-y-menus.md` — `settings_check`, `controls_check`, `ui_smoke_test`, `boot_check`, `loading_check`.
- `docs/05-pipeline-voxel.md` — `enemy_import_check` y el check Python `voxsplit --report`.
- `docs/06-framework-de-enemigos.md` — `enemy_parts_check`, `gait_check`, `ai_check`.
- `docs/07-arachnodroid.md` — `arachnodroid_check` y el balance que valida el smoke test de §6.
- `docs/08-combate-y-armas.md` — `weapon_check`.
- `docs/09-energia-y-danio.md` — `energy_check`.
- `docs/10-ciudad-destructible.md` — `city_import_check`, `city_check`.
- `docs/11-rondas-y-objetivos.md` — `round_check`.
- `docs/12-interfaz-y-hud.md` — `hud_projection_check`, `combat_hud_check`.
- `docs/13-identidad-visual-y-audio.md` — `render_check`, `vfx_check`, `audio_check`, `shake_check`, `menu_shots_check`.
- `docs/14-catalogo-de-enemigos.md` — `enemy_catalog_check` y los checks por enemigo de P3.
