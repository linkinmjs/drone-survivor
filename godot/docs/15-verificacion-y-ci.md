# 15 — Verificación y CI

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: todos los WPs (WP-30 para CI) · Depende de: `docs/00-plan-maestro.md`, `docs/02-configuracion-del-proyecto.md`

## 1. Objetivo y alcance

> **Nota de P2c, WP-T5 (2026-09-22)**: corregido el off-by-one de cabos en `terrain_check._corridor_distance()` (y su espejo en `build_terrain._street_corridor()`): holgura del arroyo 6,57 → 9,69 m. Lección para D4: **ningún check miraba el giro de los triángulos de los chunks** (115 200 hacia abajo pasaron tres WP con `terrain_check` en verde porque mide alturas, bordes compartidos y la forma de colisión, no la malla visible) → fila pendiente «los chunks miran al cielo» (`(v1−v0)×(v2−v0)·UP < 0` en todos los triángulos) en `terrain_check`; y `build_terrain._load_spec` debería fallar fuerte si el JSON no parsea en vez de caer al spec de reserva. `city_check` OK (0 SKIP, 40 370 tris de asfalto, 6 872 de vereda), `terrain_check` OK (+ negativa 6/6), `town_plan_check` OK, `render_check` HIGH 105,9 fps / p1 75,5 / 713 lotes, `sdfgi_off` 156,4 fps, LOW 493,6 fps / 416, `gait_check` y `round_check` OK. Capturas del checkpoint verificadas por el orquestador en `tools/out/shots/town_showcase/`.

> **Nota de P2c, WP-T4 (2026-09-22)**: `terrain_check` registrado en `run_checks.ps1` (`$Headless`) y `run_checks.sh` (`HEADLESS`) detrás de `town_import_check`; el workflow de CI corre `run_checks.sh --headless-only` sin enumerar checks, así que queda cubierto. **Suite completa en verde: 32 pasos** (`balance_check` sin recalibrar: 174 s de duración, 111 s de fuego, acierto 0,512, 3,10 ventanas/min, 1,85 pilas/min, energía mínima 0,284, 5 muertes en 3 semillas, integridad final 0,675–0,794). `city_check` en modo estricto, **0 SKIP**: se borran el ramal legacy de `_check_street_batching`, `_street_mode()`, `STREET_MULTIMESH_MIN/MAX`, `_build_fresh_streets()`, `CityGrid.LEGACY_STREET_NODES` y `BUILDING_BASE_Y` (→ `parcel.base_y`); `_check_route` mide contra la malla; filas nuevas con valores: casas apoyadas (65 huellas × 4 esquinas, peor 12,4 mm, tope 20), plano lejano (2 000 muestras en r < 256 con 0 por encima del relieve, junta 1,5 mm), marcadores sobre el relieve (12, peor 0,0 mm, tope 50), ruta exterior apoyada (1 127 m, 0,023–0,043 m en [0,01; 0,08]), `town_a.tscn` ≤ 500 KB (309,8) y negativas (relieve +10 cm, campo sin agujero a +1 m, calzada +20 cm). Dos errores de medición que el relieve destapó: `RoadMesh.flat_triangles()` guardaba el promedio de las tres alturas y `surface_y()` lo devolvía constante por triángulo (19 cm de error en una cinta de 8 m con 5 % de peralte) → interpolación baricéntrica real; el escalón del cordón se medía entre dos puntos a 40 cm (3 cm de cota con peralte) → cada altura contra el terreno de su propio punto. Tolerancia declarada: `_check_route` exige vereda al costado en ≥ ¾ de las muestras de ruta dentro del pueblo (86 de 93). `town_plan_check` resuelve con el terreno horneado (`TownPlanner.baked_terrain()`) para que sus firmas y las de `city_check` hablen del mismo pueblo. `perf_report --compare` necesita el prefijo `res://`: con ruta relativa se ignora en silencio. Hallazgo pendiente (se corrige en WP-T5): off-by-one de cabos en `terrain_check.gd` (~487–494: eje con `index + 1`, cabos con `index`) espejado en `build_terrain.gd` `_street_corridor` (~1791): la «calle 7» estiraba su corredor con los cabos de la calle 7 del plano (13,0 y 12,0 m), de ahí los 6,57 m de holgura contra los ~22 m del cálculo a mano.

> **Nota de P2c, tanda 1 (2026-09-22)**: checks nuevos y ampliados. **`terrain_check`** (`tools/terrain_check.tscn`, ~1 s, `-- --negative`): 11 filas (geometría 513² a 1 m; continuidad como **escalón < 30°** y quiebre de pendiente ≤ gradiente declarado ×1,35, porque 5 cm por celda prohibiría el relieve; pendiente bajo ejes ≤ 8 %; manzanas ≤ 0,5 %; cota por manzana ≤ 1 mm; arroyo fuera del corredor de ruta salvo el vano, de los corredores de calle con cabo + 3 m y de las manzanas; rejilla ↔ `HeightMapShape3D` ≤ 1 mm en 4 096 muestras; 0 en r ≥ 256; firma estable; chunks con bordes compartidos; raycast ≤ 2 cm en 64 puntos); se registra en los runners y en CI en WP-T4. **`town_plan_check`** reescrito contra el diseño: §determinismo (mismo diseño → misma firma; disco y memoria iguales; otra `variation_seed` → otro pueblo; `generate(987654)` = `generate(TOWN_SEED)`), §grafo (bocas por nodo contra la geometría del diseño, cabos derivados del diseño), §manzanas (cada lado corrido exactamente la media franja ±1 cm), §diseño (cada casa/POI/caserío/roca aparece con su pieza a ≤ 5 cm), §determinismo posicional (recolorear o mover una casa cambia **una** línea de la firma), negativas sobre `_parcel_problems`, `graph_problems` y la validación de `TownDesign`. **`city_check`**: `_street_mode()` ribbon/legacy; fila `viario` (borde de calzada cada 1 m: 0 sin asfalto, 0 coplanares, separación asfalto–terreno ∈ [0,01; 0,08]; toda punta dentro del polígono de su nodo; todo nodo de grado ≥ 2 con polígono; anillos sin hueco > 0,05 m; cordón 0,15 ± 0,01 medido dos veces: caras verticales y escalón vereda–calzada) que construye el viario del plano resuelto en memoria mientras la escena esté vieja, y 3 negativas (cinta corrida 5 cm, sin cordón, vereda hundida); la fila de firma dice en qué línea discrepa el horneado. **`gait_check`**: cuarta superficie (heightfield 129² de ruido ±1,5 m, al final y sobre una instancia nueva del jefe: intercalada antes de la ronda la métrica 13 saltaba de 0,12 a 0,96 s sin cambio del rig), 14 métricas anteriores intactas. `combat_hud_check` sigue en verde con el `FakeTown` con grafo (4 nodos, 5 calles a 72/105/68/95°, cabo con tranquera). Regla operativa nueva: los checks cargan `TownPlanner`/`TownTerrain` con `load()` porque el `global_script_class_cache` se perdió mientras dos agentes guardaban y el check moría en parseo sin llegar a `quit()`.

> **Nota del cierre de la revisión de P2b (2026-09-22)**: `city_check` gana la fila de **firma del plano** (`town_a.tscn` al día con `TownPlanner`), fachada contra la escena, marcadores contra el plano, constantes derivadas; `town_plan_check` con `_parcel_problems()` y cinco negativas reales; `round_check` 17 con la escuela derribada de verdad y el escalón del más cercano; `combat_hud_check` 20 contra un doble con números distintos del pueblo; `town_import_check` con `default_timeout` 120. Regla operativa aprendida: verificar el parseo (`--check-only` o un check corto) entre pasos largos de edición, porque `city/**` a medio escribir tiró rojos transitorios a los demás agentes tres veces.

> **Nota de P2b (2026-09-21)**: checks nuevos en los runners: `town_import_check` (13 sub-checks sobre las 19 piezas GLB del pueblo: tris ≤ 2 400 casas / ≤ 300 props, AABB centrado y apoyado, puerta 2,20 m, `.import`, materiales de paleta, máscara emisiva, VRAM, negativa) y `town_plan_check` (2,5 s sin assets: determinismo por firma, ruta, calles, manzanas convexas, parcelas, círculo, roles y HP, marcadores, escena horneada leída como texto, 4 negativas); `city_check` reescrito con 26 filas contra el plano (`docs/10` §1); `round_check` 17 filas; `combat_hud_check` fila 20 doble (barrio real y `tools/fake_town.gd`); `energy_check` 25; `balance_check` recalibrado (`docs/07` §1). El catálogo de §3 queda desactualizado en esas filas: manda esta nota.

> **Nota del checkpoint 4, segunda vuelta (2026-09-21)**: `enemy_parts_check` presupuesto 10 400; `balance_check` recalibrado (duración 140–340, fuego 80–160, integridad 0,58–0,88, muertes 0–5 por partida y ≥ 1 en la suite; tablas de tres corridas y de fases en el docstring); el título de la fila 7 ya dice 240–480.

> **Nota del checkpoint 4 (2026-09-21)**: `energy_check` y `weapon_check` citan los valores nuevos (0,40 / 0,60 / 0,30 / +45 % / 30 %; 16 / 1,6 / 48 / 6); `balance_check` recalibrado (duración 190–390, integridad 0,55–0,85, fuego 110–190, pilas recogidas ≤ 2,6/min en la fila 4 con la energía mínima solo informativa, título de la fila 7 corregido a 240–480; ~7 min; `-- --only=1` no es una corrida válida del protocolo: la fila 5 compara una semilla contra una banda de tres); `tools/legibility_shots.tscn` (con ventana, no está en la suite) mide fogonazo, halos y velo. `hud_projection_check` fila [11]: la columna FULL/25°/12°/0,94·w busca el borde cielo/suelo solo en una ventana de ±40 px alrededor del horizonte esperado (o SKIP con motivo) en vez del máximo global de la columna, que con menos glow elegía otro borde (253 px).

> **Nota del cierre de la tanda 4 (2026-09-20, suite completa)**: `run_checks.ps1 -Extended` con **28 pasos**: 27 en verde y `balance_check` en rojo solo por la fila 5 (acierto 0,511 contra el techo 0,50), corregida como tolerancia (0,55) y repetida en verde (11/11, 18 min, sin `ERROR` ni `AVISO`). Durante la suite el usuario tenía un juego abierto (38 % de la GPU): `render_check` dio HIGH 69,9 fps / p1 45,7 (pasa el presupuesto de 60/45 pero no vale como medición; la referencia es la de WP-29 con la máquina tranquila: 120 fps / p1 76–81), variante B 83,3, LOW 297. Quedan en los logs de `balance_check` dos `WARNING` informativos del `VFXPool` por ranuras `hold` que superan los 120 s (avisan una vez y no reclaman): candidatos a bajar a `print`.

> **Nota del cierre de la revisión de la tanda 4 (2026-09-20)**: `vfx_check` pasa a **17 filas** (14 retención larga: el haz aguanta 130 s simulados y se suelta a pedido, incluso sobre una ranura ya libre; 15 el `Telegraph` devuelve su ranura al salir del árbol; 16 denegar no apaga nada, con `used <= budget()` en el instante de denegar; 17 el pool deja de escuchar el bus al salir del árbol, con un pool propio y antes de la foto de nodos) y restaura el preset en `finish()`. `audio_check` suma [8g] (intensidad automática: calor 1,00 tras 60 hp y 0,00 en 6,2 s, `tension` −10 → −4,3 → −10 dB, salto máximo 0,546 dB/20 ms, 0 reversiones, sin jefe la cercanía queda en 0) y las filas de la tabla de §5.3 corren con `auto_intensity = false`. `shake_check` usa `auto_tick = false`. `tools/balance_check.gd` ya no llama a `set_current_scene` (abortaba siempre con `ERROR: Condition "p_scene && p_scene->get_parent() != root"` y era un no-op de runtime: los pools se resuelven por grupo); la corrida corta es `-- --only=1`. Los runners validan el nombre del check (exit 2) y fallan si no ejecutaron ningún paso (exit 3). La asimetría `NON_BLOCKING=(render_check)` en bash y `$NonBlocking = @()` en PowerShell es intencional: informativo en CI sin GPU, bloqueante en la máquina de desarrollo.

> **Nota de WP-29 (2026-09-20, referencia de rendimiento)**: la física de `boss_and_city` con bot cuesta **1,27 ms por tick** (cinco corridas entre 1,25 y 1,29: ±3 %) y está **atribuida al 92 %** con `core/perf_bracket.gd` (dos nodos con `process_physics_priority` ±1 000 000 que envuelven todo el `_physics_process` del árbol) y 24 secciones de `PerfProbe`: fase de callbacks 0,637 ms (`fsm_state` 0,174, `rig_tick` 0,151, sin instrumentar 0,102 = despacho del motor sobre ~120 nodos y coste de la sonda, `bot_pilot` 0,059, `enemy_base` 0,025, el resto < 0,025) y paso del servidor 0,633 ms (`drone_integrator` 0,201 —`_integrate_forces` corre dentro del paso de Jolt, no en la fase de callbacks— y `jolt_step` 0,432, medido por el hueco entre ticks encadenados con `--max_fps=25`; sin tope el estimador se apaga solo, `physics_gap_valid`). `boss` sin ciudad: 0,572 ms/tick (`rig_tick` 0,194 = 62 % de la fase); `flight_only` 0,552. **Jolt no es el grueso** (34 % con ciudad): no se tocaron `velocity_steps`/`position_steps`. `_process` por cuadro en HIGH: `hud_combat` 0,268 ms (3,3 % del cuadro; en LOW 0,240 ms = 11,3 %), `vfx_pool` 0,029, el resto ≤ 0,013. **Lo que parecía un problema de rendimiento era de métrica**: `physics_ms_avg` (pico por segundo de `TIME_PHYSICS_PROCESS`) mide ~1,6× el tick medio y varía 6–12 % entre corridas idénticas (p95: 21 %), del orden del umbral de regresión del 10 %; por eso §5.2 y §8.3 juzgan ahora `physics_tick_ms` y `fps_wall` (campos nuevos del JSON). Cuatro optimizaciones neutras en comportamiento (11 de 14 logs de checks byte-idénticos; `arachnodroid_check` −15 % de física caminando): barrido único de la ciudad en `EnemyFSM` (que resultó costar 0,001 ms: la capa de decisión corre a 4 Hz; lo caro es `fsm_state`), `get_parts()` cacheado, un `_exposure_context()` por evaluación, lista de componentes del `CombatHUD` cacheada. `perf_report` gana `--preset=`, `--compare=` (Δ por escenario y métrica, `REGRESIÓN` > 10 %), `--strict` (exit 1), `--ablate=vfx,overlay,trauma`, `--gpu-profile` (existía solo como comentario) y graba `preset`, `fisheye_mode`, `max_fps`, `physics_tick_ms`, `physics_gap_valid`; `--preset` encontró y arregló un bug: `Graphics.apply_all()` encendía el vsync y clavaba 60 fps. **Referencia nueva**: `docs/perf/2026-09-20-p2.json` (HIGH) y `2026-09-20-p2-low.json` (LOW), dos corridas dentro del 5 % en todo salvo `physics_ms_avg`: `boss_and_city` HIGH 1,27 ms/tick (pico 1,90–2,02), 854/873 draw calls, 124,5 fps de reloj (p1 85), GPU 7,7 ms de los que el ojo de pez FAST_WIDE es el **96,7 %** (frontal 5,6 ms, laterales 1,1 c/u); LOW 471 fps, 430 draw calls, GPU 0,63 ms. `render_check` ×2: HIGH 120,7/120,4 fps (p1 81/76), 873 draw calls; variante B 139/137; LOW 461/450. Ablación: VFX −4 draw calls y ≈ 0 GPU; overlay −1 draw call y **−0,10 ms**; sacudida 0. Contra `2026-09-20high24c.json` (la única comparable, FAST_WIDE): física +0,1 %, p95 −19 %, draw calls +14 % (contenido nuevo: VFX, overlay, prop de la pila; techo de 900 respetado), fps −1,3 %. `2026-09-20-wp24.json` y `-wp26.json` no son comparables: se midieron sin `--preset`, con el ojo de pez en FAST (492 draw calls contra 854). 17 checks en verde con `balance_check` extendido (11 filas). Pendientes priorizados (`docs/00` §7): sub-instrumentar `fsm_state`, rayos del IK solo en patas en vuelo, `hud_combat` en LOW, y la única palanca de fps en HIGH es el ojo de pez (decisión de identidad).

> **Nota de WP-28 parte B (2026-09-20)**: `shake_check` (headless, ~2 s, registrado en los runners tras `overlay_check`) con 10 filas: decaimiento 0,7167 s (límite 1,5), máximos de módulo 0,051 m / 1,43° bajo 0,08 m / 2,5°, vuelta a la base 0,0 con inclinación 0° y 30°, atenuación 0,5 → 0,075 a 160 m, horizonte que sigue a la cámara en los cuatro modos (≤ 0,003 px) con 1/3/5 sub-cámaras a 0,0 m de desvío, techo 1,0 con 30 sumas, señal publicada (0,55/3, 0,30/2, 0,165/1, 1,0/4), determinismo por semilla, 113 nodos antes y después, `-- --negative` con 6 fallos. `hud_projection_check` esconde el `Rect` del overlay en `_check_horizon_match()` y en la escena de smear (fila 14): la columna FULL/25°/12°/0,94·w pasó de 5,8 / 6,0 / 253 px a 2,18 / 2,07 / 2,07 px; peor error actual 7,48 px en FAST_WIDE/15°/0°/0,94·w (tolerancia 8).

> **Nota del cierre de WP-27 (2026-09-20)**: `audio_check` suma [7c] bucles del haz con un `SweepAction` real (voz a 0,000 m del punto de contacto, lo sigue sin crear un segundo bucle, `hide_beam()` la para; `configure_beam(&"SiegeBeam")` elige `siege_loop`), [7d] tope de `enemies` (3 voces del jefe + haz + 2 chispas = 6/6, una fractura más se rechaza, el tercer bucle de chispas no entra) y [7e] sin fugas (enemigo liberado con haz y chispas → 0 bucles, 0 voces). `settings_check` compara el volumen volcado contra `Audio.bus_volume_db()` y contra `base + linear_to_db(deslizador)` en `Music` (base −8 dB) y `Master` (base 0): falla si alguien vuelve a `linear_to_db(v)` a secas o suma la base dos veces.

> **Nota de WP-28 parte A (2026-09-20)**: `overlay_check` (headless, ~5 s, registrado en los runners tras `vfx_check`, sobre `drone_rig.tscn` real): [1] capa −1, `ColorRect` full-rect y uniforms iniciales de `docs/13` §7; [2] `hull_changed(0.4)` → `damage` 0,6 y uniform; [3] EMP 1,0 → 0,5 a 1,5 s → reinicio → 0,0 exacto a 3,0 s (con el `EnergySystem` real: `apply_emp(0.0, 3.0)`); [4] señal 1,0 / 0,55 / 0,30 / 0,165; [5] lectura de pantalla a mano y por preset (LOW no lee; `Shader.get_shader_uniform_list()` no lista los samplers con `hint_screen_texture`, así que se detecta en las líneas `uniform` del código); [6] respawn con casco entero → 0,0 y con casco al 40 % → 0,6; [7] 20 ciclos sin fugas (117 nodos); `-- --negative` falla con 5 fallos. `tools/overlay_shots.tscn` (capturas y medición GPU con ventana) queda fuera de la suite.

> **Nota del cierre de WP-26 (2026-09-20)**: `vfx_check` pasa a 13 filas (12 zona del pisotón, 13 anillo del EMP: ciclo completo y vuelta al pool; la 12 encontró el bug de las ranuras de telegrafía retenidas 120 s); `weapon_check` asevera la superficie de `hit_confirmed` con impactos reales y las seis filas de `surface_for`; `project_check` conoce la aridad 4; `tools/enemy_showcase.gd` acepta `--drone=x,y,z` para encuadrar el pisotón.

> **Nota de WP-26 (2026-09-20)**: `vfx_check` (headless, ~30 s, registrado en los runners tras `arachnodroid_check`) con 11 filas: contrato de §4 sobre 64 emisores en 18 escenas, presupuesto por preset (6/8/12) con telegrafías servidas incluso con el presupuesto lleno, tanda de 200 pedidos, vaciado sin fugas (`OBJECT_NODE_COUNT` y huérfanos iguales), `null` con presupuesto lleno o id inexistente, ningún emisor colgado, y `-- --negative` que retiene un `emp_ring` fuera de la tanda y falla. `arachnodroid_check` 15 mide el haz nuevo; `tools/arachnodroid_check.tscn` y `tools/enemy_showcase.tscn` instancian un `VFXPool`.

> **Nota de WP-27 (2026-09-20)**: `audio_check` ampliado con [1b] mezcla base del layout ↔ `Audio.BASE_VOLUMES_DB` (el `.tres` leído como texto), [2] efectos por bus con parámetros y pasa-bajos apagado → encendido → apagado, [2b] composición base + deslizador, [7] 30 fuentes 3D → 22 voces de pico con topes 4/6/6/6 y eventos del bus (`collapse_low` + `collapse_debris`, `battery_click`, `impact_weak`), [7b] tope sobre una fuente externa (`can_claim` cerrado y `play_3d` → `null`), [8] stems a 64,000000 s, tres cruces con salto máximo por 20 ms / sobrepasos / reversiones, intensidad ±6 dB, ambiente en `BATTLE`, deriva del reloj de mezcla y sting de victoria, [9] prueba negativa del comparador de duraciones (iguales ✓, una muestra ✗, medio segundo ✗); `default_timeout` 180 s (el externo del runner es 420 s). `tools/audio_showcase.tscn` queda fuera de la suite.

> **Nota de WP-24e (2026-09-20)**: sub-checks nuevos: `audio_check` 6b (cuerpo congelado a RPM de vuelo → 8 voces a `SILENT_DB` en < 0,5 s y vuelta al armar), `city_check` 8b (oclusor deshabilitado al caer el edificio más alto de la manzana), `settings_check` (oclusión apagada y LOD lateral = preset en los cuatro presets), `round_check` fila 8 (audio callado al congelar para la tarjeta), `combat_hud_check` fila 10 (dos motivos del cartel de reconstrucción), `energy_check` 5/9/10/16 reescritos. Confirmado otra vez: `--editor --quit` sale 0 ante errores de parseo; solo un check que cargue el script los detecta.

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
| `hud_projection_check` | 06, 08, 24c, 28 | `FPVCamera.project_direction()` sin `NAN` en los **cuatro** modos (OFF / FAST / FAST_WIDE / FULL, con 1/3/5 viewports) para 64 direcciones; los puntos detrás de la cámara se reportan inválidos; cobertura analítica del ojo de pez en una rejilla 64×36 (sin saltos > 0,2 en un barrido radial); `disable_3d` de la raíz con el compuesto visible; draw calls por modo; con ventana suma las filas de imagen: horizonte en columnas laterales (tolerancia 8 px), smear y costura contra FULL (< 0,05 / 0,06), captura del FlightHUD; 15 filas. El `Rect` del overlay FPV se esconde durante las mediciones de imagen (WP-28) | `GODOT P res://tools/hud_projection_check.tscn` (en la suite); `GODOT PW … -- --shots=tools/out/shots` para las filas de imagen |
| `audio_check` | 07, 24e, 27 | Los **7 buses** con nombre exacto enrutan a `Master`; mezcla base del layout ↔ `Audio.BASE_VOLUMES_DB`; compresor + limitador en `Master`, reverb en `City`, pasa-bajos conmutable en `Music`; composición base + deslizador; loops de motor con crossfade por bandas sin saltos y silencio al congelar el dron (6b); `AudioPool`: 30 fuentes → ≤ 24 voces y topes por categoría, fuente externa bajo tope (7b), bucles del haz que siguen al punto de contacto (7c), tope de `enemies` con haz + chispas (7d), sin fugas al liberar al enemigo (7e); `MusicDirector`: stems a 64,000000 s, cruces ≤ 6 dB por 20 ms, intensidad, ambiente en BATTLE, sting; prueba negativa del comparador de duraciones | `GODOT P res://tools/audio_check.tscn` |
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
| `combat_hud_check` | 22, 24d, 24e, 25, 25b, 26 | Headless, **20 filas**: los 18 componentes del CombatHUD (energía, casco, calor, retículo, hitmarker con `surface`, barra del jefe por grupos, EN PIE, marcadores fuera de pantalla con el grupo `protected`, dirección de daño, temporizador, objetivos, pista de punto débil, consejos, glitch de EMP de 3,0 s, estática, cartel de reconstrucción con motivo, pantalla de alerta con mapa del barrio); ningún marcador con `NAN`; los objetivos detrás de la cámara se clampean al borde; sin claves crudas | `GODOT P res://tools/combat_hud_check.tscn` |
| `balance_check` | 23 | **Extendido** (`-Extended`): `BotPilot` juega la ronda 1 real con 3 semillas + control idle a `time_scale` 4; asevera duración, integridad, muertes, fuego, acierto (0,33–0,55 desde el cierre de la tanda 4) y ventanas sobre la media (`docs/07` §14), derrota del control por integridad, sin NaN, física mediana bajo guarda, `time_scale` restaurado y prueba negativa; ~541 s | `GODOT P res://tools/balance_check.tscn -- --timeout=1500` |
| `render_check` | 24a, 24c, 24e | Escena completa (jefe + 60 edificios + FAST_WIDE, preset HIGH) a 1080p sin vsync: tras 120 frames de calentamiento, 600 frames con **≥ 60 fps** de media y p1 ≥ 45; `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` **< 900** (870 medidos con VFX, prop de la pila y overlay); variante B de SDFGI tabulada; LOW ≥ 120 fps; capturas `render_high/low/sdfgi_off`; restaura el preset del jugador. Necesita GPU real: **informativo** en bash (`NON_BLOCKING`) y excluido por `--headless-only` | `GODOT --windowed --resolution 1920x1080 --disable-vsync --path godot res://tools/render_check.tscn -- --shots=tools/out/shots` |
| `vfx_check` | 26 | Headless, **13 filas**: contrato de `docs/13` §4 sobre 64 emisores en 18 escenas; presupuesto por preset (6/8/12) nunca superado, con las telegrafías servidas aun con el presupuesto lleno; tanda de 200 pedidos en 20 s; todo vuelve al pool (hijos 56/56), sin fugas (`OBJECT_NODE_COUNT` y huérfanos ±0); `null` con presupuesto lleno o id inexistente; ningún `GPUParticles3D` emitiendo pasada su vida + 0,5 s; ciclo completo de la zona del pisotón y del anillo del EMP; `-- --negative` debe fallar | `GODOT P res://tools/vfx_check.tscn` |
| `shake_check` | 28 | Headless (`docs/13` §10.4): `add_trauma(1.0)` decae a 0 antes de 1,5 s; desplazamiento acotado a 0,08 m y 2,5°; vuelta exacta a la base (< 1e-4) incluso con inclinación del hangar; atenuación por distancia (≤ 0,15 a 160 m); el horizonte proyectado sigue a la cámara (< 1 px) en los cuatro modos de ojo de pez; sumar 30 traumas no supera 1,0; la calidad de señal se publica en el `FlightHUD` (barras por 0,75/0,5/0,25); determinismo por semilla; sin fugas; prueba negativa | `GODOT P res://tools/shake_check.tscn` |
| `overlay_check` | 28 | Headless: `FPVOverlay` en la capa −1 con `ColorRect` full-rect y uniforms iniciales de `docs/13` §7; `hull_changed(0.4)` → `damage` 0,6; EMP 1 → 0,5 a 1,5 s → 0 exacto a 3,0 s con reinicio; `signal_quality` 1,0 / 0,55 / 0,30 / 0,165; LOW sin lectura de pantalla; respawn relee el casco; sin fugas; `-- --negative` falla | `GODOT P res://tools/overlay_check.tscn` |
| `perf_report` | 24a, 29 | **No es un check**: informe de rendimiento con ventana. Escenarios `flight_only`, `boss`, `boss_and_city` (`--only=`), 120 frames descartados + 600 medidos, física por tick real con `PerfBracket` + `PerfProbe` (24 secciones, `jolt_step` por hueco entre ticks con `--max_fps`), draw calls, primitivas, VRAM, fps por reloj de pared, GPU por viewport (`--gpu-profile`), ablación por rasgo (`--ablate=root3d,shadows,sdfgi,fog,ssao,msaa,fisheye,occlusion,vfx,overlay,trauma`), `--preset=`, `--compare=<json>` (Δ por métrica, `REGRESIÓN` > 10 %) y `--strict` (exit 1), `--suffix=`; escribe `docs/perf/<fecha><sufijo>.json` | `GODOT --windowed --resolution 1920x1080 --disable-vsync --path godot res://tools/perf_report.tscn -- --preset=HIGH --compare=docs/perf/2026-09-20-p2.json` |
| `menu_shots_check` | 25 | Instancia las 8 pantallas obligatorias de `docs/13` §10.5 más la pausa y la tarjeta de resultado (**10 capturas**) y captura una imagen de cada una. **Falla** si alguna pantalla no se instancia o si algún `Label` muestra su propia clave de traducción | `GODOT PW res://tools/menu_shots_check.tscn -- --shots=tools/out/shots` |
| `enemy_catalog_check` | 31…39 (P3) | **Todavía no existe** (se crea en P3). Check transversal del catálogo de `docs/14` §9: toda entrada de `EnemyCatalog.ENTRIES` resuelve escena y perfil; cada enemigo construye su grafo de partes sin errores, respeta su altura declarada ±0.15 m y el presupuesto de **< 18 000** triángulos; ≥ 3 ataques, entre 2 y 5 fases monótonas, `effective_windup() >= 0.80` en todas ellas, ≥ 1 punto débil y ≥ 1 parte `detachable`; claves `ENEMY_*`/`ATK_*`/`WP_*` presentes; **0** `Area3D` como hitbox. Crece con cada WP de P3, además del `tools/<enemy>_check.tscn` propio de cada uno | `GODOT P res://tools/enemy_catalog_check.tscn -- --timeout=180` |

### 3.1 Checks que **no** corren con `--headless`

Los **cuatro** que usan ventana en la tabla necesitan un framebuffer real porque capturan o miden imagen y en `--headless` el controlador de render es nulo: `ui_smoke_test`, `boot_check`, `menu_shots_check` y `render_check` (que además necesita GPU real: en bash es informativo). Los **22 restantes** del catálogo real de los runners (más `shake_check` desde WP-28) son headless puros y son los que CI corre con `--headless-only` (§7.1 y D-1). `perf_report` no es un check y se corre a mano con ventana. (`render_parity_check` nunca existió: retirado del catálogo en WP-24a.)

`hud_projection_check` corre headless en la suite (cobertura analítica, `disable_3d`, draw calls) y con ventana suma sus filas de imagen; `combat_hud_check` y `vfx_check` son headless puros desde WP-24d/25b y WP-26. `render_check` y `perf_report` necesitan GPU y son **solo local** (WP-30: el contenedor de CI no trae Vulkan).

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
| P0 (vuelo solo, sandbox) | `physics_tick_ms` (tick medio real, `PerfBracket`) | **< 1.6 ms/tick** (medido 0,55) |
| Jefe + ciudad completa | `physics_tick_ms` (tick medio real, `PerfBracket`) | **< 2.0 ms/tick** (medido 1,27; `physics_ms_avg`, el pico por segundo, queda como dato informativo) |
| Jefe + ciudad completa | Draw calls | **< 900** |
| 1080p, preset HIGH (ojo de pez FAST_WIDE), jefe + 60 edificios | `fps_wall` medio (reloj de pared) | **≥ 60** y p1 ≥ 45 (medido 120 / 76–81) |
| Ciudad completa | VRAM de texturas | **< 90 MB** |
| Escombros vivos | Conteo | **≤ 24** |
| Voces de audio | Conteo | **≤ 24** |
| Emisores de partículas | Conteo | **≤ 12** |

A 100 Hz, 2.0 ms/tick son 200 ms de física por segundo de juego: el 20 % de un núcleo. Ese es el techo, no el objetivo.

**Corrección de WP-24a (2026-09-20): `Performance.TIME_PHYSICS_PROCESS` no es «ms/tick».** Godot lo reescribe una vez por segundo con el **máximo** de una iteración del bucle principal, que puede contener varios ticks: con el mismo trabajo por tick da 2,18 ms a 285 fps y **12,1 ms con el juego topado a 30 fps**. Leído correctamente, el presupuesto de esta tabla es «pico por segundo de una iteración» y la media real por tick sale de la sonda `core/perf_probe.gd` (`PerfProbe.begin/end`, apagada por defecto; `PerfSampler` la enciende): en `boss_and_city` el GDScript instrumentado cuesta **0,32 ms/tick** (integrador del dron 0,22 tras el refactor sin asignaciones, bot 0,07, arma/proyectiles/percepción < 0,03) y por ablación el `_physics_process` del nivel ≈ 1,04 ms (el jefe ≈ 0,50) sobre un piso de Jolt + `_integrate_forces` ≈ 1,08 ms. Los monitores `PHYSICS_3D_ACTIVE_OBJECTS/COLLISION_PAIRS/ISLAND_COUNT` devuelven 0 con Jolt (no los implementa). Los fps se deciden por **reloj de pared** (`fps_wall`, con p1 = 1000 / p99 del tiempo de cuadro): `Engine.get_frames_per_second()` se refresca una vez por segundo y sobre una ventana de 1,5 s recién cargada dio 5 fps donde el reloj daba 410; los «48 fps» de `docs/perf/2026-09-19.json` eran ese artefacto. `perf_report` mide GPU y CPU de render por viewport (`viewport_set_measure_render_time`), tiene `--ablate=<lista|all>` con líneas de base emparejadas y árbol en pausa, `--only`, `--suffix`, `--max_fps`, `--reference=<json>` con Δ % por métrica; **Ojo**: `perf_report` no ejecuta `Global.load_startup_settings()`, así que sin `--preset` mide con los valores por defecto en memoria de `Graphics`, que **no son el preset HIGH** (`fisheye_mode` vale FAST por defecto y HIGH manda FAST_WIDE: 492 draw calls contra 854); desde WP-29 `--preset=LOW|MEDIUM|HIGH|ULTRA` aplica el preset sin persistirlo y el JSON graba `preset` y `fisheye_mode`. `docs/perf/2026-09-20-antes.json` y `2026-09-20.json` son la referencia nueva (`boss_and_city`: 286 fps de reloj, p1 149, GPU 2,98 ms, 332 draw calls, pico de física 2,18 ms).

**Medido en WP-23** (`docs/perf/2026-09-19.json`, 1080p, vsync apagado, hardware del usuario): física media 1,31 / 1,61 / **2,98** ms/tick en `flight_only` / `boss` / `boss_and_city` (en combate real 2,1–3,8: proyectiles, escombros rodando y derrumbes); draw calls 173 / 87 / 453; FPS de motor 57 / 65 / **48**. Incumplen el presupuesto de física con ciudad y los 60 fps: trabajo de WP-24 (Environment/presets) y WP-29 (optimización).

### 5.3 `docs/perf/<fecha>.json`

```json
{
  "date": "2026-09-19",
  "godot": "4.7.stable",
  "commit": "c320e96",
  "preset": "HIGH", "fisheye_mode": "FAST_WIDE", "max_fps": 0,
  "scenarios": {
    "flight_only":  {"physics_tick_ms": 0.0, "physics_ms_avg": 0.0, "physics_ms_p95": 0.0,
                     "physics_breakdown_ms": {}, "physics_gap_valid": true, "draw_calls_avg": 0,
                     "primitives_avg": 0, "vram_bytes": 0, "node_count": 0,
                     "fps_wall": 0.0, "fps_wall_p1": 0.0, "fps_avg": 0.0, "gpu_ms_total": 0.0},
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
param([string]$Only = "", [switch]$Extended, [switch]$HeadlessOnly, [int]$ProcessTimeout = 420,
      [string]$Godot = "C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe")

# Catálogo real (2026-09-20, WP-30): 22 headless + shake_check (WP-28), 4 con ventana, 1 extendido
$Headless = @("project_check","loading_check","settings_check","city_import_check","enemy_import_check",
              "flight_bench","flight_check","controls_check","pause_check","hud_projection_check",
              "audio_check","enemy_parts_check","weapon_check","energy_check","city_check","gait_check",
              "round_check","ai_check","combat_hud_check","arachnodroid_check","vfx_check","overlay_check",
              "shake_check")
$Windowed = @("ui_smoke_test","boot_check","menu_shots_check","render_check")   # render_check a 1920x1080 --disable-vsync
$ExtendedChecks = @("balance_check")                                                # -Extended / RUN_EXTENDED=1
# 1) editor import + sin errores; 2) cada check; 3) resumen y exit code
```

Comportamiento obligatorio:

1. Primero ejecuta `--headless --path godot --editor --quit` y **falla** si la salida contiene `ERROR:` o `SCRIPT ERROR:`.
2. Luego cada check, capturando su salida en `tools/out/report.txt` con una línea de encabezado por check.
3. `-Only <nombre>` corre uno solo.
   **Límite conocido (WP-24c, 2026-09-20)**: el paso 0 `--headless --editor --quit` sale con 0 y sin imprimir nada ante un **error de parseo de GDScript**; no sirve como puerta de compilación. Lo que lo detecta es correr un check que cargue el script (que en headless se cuelga sin salida y cae por el timeout externo del runner, o falla al instanciar). Regla operativa para los agentes: correr siempre los checks con `> log 2>&1` y timeout externo, y no dar por buena una captura sin mirarla.
4. `-Extended` (PowerShell) o `RUN_EXTENDED=1` (bash) suma al final los **checks extendidos**: `balance_check` (WP-23, cuatro partidas simuladas a `time_scale` 4, ~9 min, `--timeout=1500`, timeout externo propio de 1 800 s). `-Only balance_check` también lo corre. `tools/perf_report.tscn` no es un check: se corre a mano con ventana (`--windowed --resolution 1920x1080 --disable-vsync`) y escribe `docs/perf/<fecha>.json`.
5. Sale con **1** si algún check salió distinto de 0; con 0 si todos pasaron. En bash, `render_check` es informativo (`NON_BLOCKING`) y no cuenta para el código de salida.
6. `-HeadlessOnly` (PowerShell) o `--headless-only` / `RUN_WINDOWED=0` (bash) **saltan** los checks con ventana y los extendidos y los listan como «locales» en el resumen: es el modo de CI (WP-30). Un `-Only`/nombre que apunte a un check excluido por la bandera o inexistente sale con **2** y un mensaje, antes de tocar `report.txt`; si por cualquier motivo no se ejecutó ningún paso, sale con **3**. Códigos de salida: 0 verde, 1 falló algún check, 2 error de uso, 3 nada ejecutado. En bash, `--` corta el parseo de banderas y un segundo nombre posicional es error de uso (cierre de la revisión de la tanda 4).
7. `tools/out/` y `builds/` están en `.gitignore`.

`tools/run_checks.sh` es el equivalente para el contenedor Linux de CI: misma lista, mismo orden, mismo contrato. Los checks con ventana corren bajo `xvfb-run` cuando no hay display, salvo con `--headless-only`, que es lo que usa CI (sin Vulkan en el contenedor).

### 7.2 Workflow

Cuatro jobs encadenados en `.github/workflows/deploy-to-itch.yml`: **`import` → `checks` → `export` → `deploy-itch`** (`if: false`). El YAML completo está en `docs/02-configuracion-del-proyecto.md` §9; aquí van solo las reglas que le competen a este documento:

- `import` cachea `godot/.godot/imported/` con clave `hashFiles('godot/**/*.import', 'godot/project.godot')` y publica `godot/.godot/` como artefacto para los jobs siguientes. Sin ese artefacto, `checks` reimportaría todo.
- `checks` corre `bash godot/tools/run_checks.sh --headless-only` (WP-30: el contenedor no trae Vulkan y el proyecto es Forward+, así que los cuatro checks con ventana y `balance_check` quedan como locales) y sube **siempre** (`if: always()`) `godot/tools/out/report.txt` como artefacto `check-report` (en ese modo no hay capturas). Que el job falle no debe impedir ver por qué.
- `export` solo corre si `checks` pasó, y exporta **únicamente** el preset `Windows Desktop` con `firebelley/godot-export@v6.0.0` (`id: export`); el artefacto `windows-desktop` sale de `${{ steps.export.outputs.archive_directory }}/Windows Desktop.zip`. Verificado localmente (WP-30): export con exit 0, pck de 818 archivos sin `tools/`, `docs/` ni `_raw`, `.exe` que llega al menú principal sin errores. El run real de GitHub Actions se comprueba con el primer push.
- `deploy-itch` queda con `if: false` hasta que el juego se publique.

---

## 8. Política de regresión

1. **Un WP no cierra si su check falla.** Sin excepciones, sin «lo arreglo en el siguiente».
2. **Un WP tampoco cierra si rompe un check anterior.** Antes del commit se corre `run_checks.ps1` completo. Si un check de otro WP se pone en rojo, arreglarlo es parte del WP actual.
3. **`perf_report --compare=<json>` compara contra la referencia.** La referencia es el `docs/perf/<fecha>.json` más reciente commiteado (hoy `2026-09-20-p2.json` y `-p2-low.json`). Una regresión **> 10 %** en `physics_tick_ms`, `draw_calls_avg` o `fps_wall` se marca como `REGRESIÓN` y, con `--strict`, hace salir con 1. (`physics_ms_avg` y `fps_avg` quedan fuera del veredicto: el primero es el pico por segundo y varía 6–21 % entre corridas idénticas; el segundo se deriva de `TIME_PROCESS`, que incluye la espera por la GPU. WP-29.)
4. **Actualizar la referencia es un acto explícito.** Se commitea un `docs/perf/<fecha>.json` nuevo con una línea en el mensaje de commit justificando por qué el coste subió. Nunca se sobrescribe el archivo anterior.
5. **Los checks informativos no bloquean.** `render_check` en bash (`NON_BLOCKING`) reporta y no cuenta para el código de salida; en Windows sí bloquea. (`render_parity_check` nunca se implementó: retirado del catálogo en WP-24a.)
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
| D-1 | Capturas en CI (contenedor sin display) | **Cerrado (WP-30)**: CI corre `run_checks.sh --headless-only`; los cuatro checks con ventana y `balance_check` son locales (el contenedor no trae Vulkan) |
| D-2 | `--disable-vsync` en `render_check` | **Propuesta**; si el flag no existe con ese nombre en 4.7, usar `Graphics` para fijar `vsync_mode = 0` desde el propio check |
| D-3 | FPS derivados de monitores en vez de `get_frames_per_second()` | **Propuesta**. En una máquina de CI sin GPU el número no es comparable con el de escritorio; `render_check` puede tener que marcarse como «solo local» |
| D-4 | Umbral de distancia L1 > 0.15 entre histogramas en `ai_check` | **Propuesta** sin calibrar; se ajusta en WP-18 con datos reales |
| D-5 | `render_parity_check` necesita un conjunto de referencia | **Cerrado**: el check nunca se implementó; retirado del catálogo en WP-24a y sin referencias en runners ni workflow (WP-30). La revisión visual la hacen las capturas de `render_check`, `menu_shots_check` y los Movie Maker de cada WP |
| D-6 | Presupuesto de 900 draw calls | **Confirmado**: 870 máximos medidos por `render_check` con VFX, prop de la pila y overlay (WP-26/28); una versión del prop con 11 `MeshInstance3D` dio 905 y falló, lo que demuestra que el tope trabaja |
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
