# 00 — Plan maestro de Drone Survivor

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: todos los paquetes de trabajo · Depende de: — (es la raíz de la documentación)

## 1. Visión

**Drone Survivor** es un juego de acción en primera persona en el que el jugador pilota un dron FPV de combate y defiende una ciudad voxel de colosos mecánicos. Cada enemigo es enorme (20–45 m), lento de matar y peligroso: hay que volar alrededor, encontrar sus puntos débiles, romper sus partes (que se desprenden y caen) y sobrevivir administrando la energía con pilas repartidas por el mapa. Las referencias son la escala y el ritmo de *Shadow of the Colossus*, el pilotaje exigente de un simulador FPV y la lectura clara de un shooter moderno.

### Pilares
1. **Pilotaje real**: el dron se maneja con sticks como un cuadricóptero FPV (acro y horizon, rates configurables, calibración por dispositivo). Volar bien es la primera habilidad.
2. **Colosos que se leen**: cada enemigo telegrafía sus ataques, muestra sus puntos débiles con luz y pierde partes de forma visible. La IA elige acciones por utilidad con una personalidad aleatoria por partida: es inteligente y algo impredecible, nunca tramposa.
3. **La ciudad es el reloj**: el enemigo ataca edificios; la integridad de la ciudad es la condición de derrota. Esconderse no es una estrategia.
4. **Sensación AAA**: iluminación global, niebla volumétrica, partículas, audio posicional, sacudida de cámara y una interfaz oscura y holográfica, sobre un estilo voxel coherente entre dron, ciudad y enemigos.

### Alcance del MVP
Un jefe (Arachnodroid), un distrito destructible, una ronda, menú completo (boot, principal, rondas, opciones, controles con calibración, hangar/quad, ayuda, pausa), HUD de vuelo + HUD de combate, energía y pilas, resultados persistentes. Todo jugable con gamepad o radio.

## 2. Decisiones fijas

| Decisión | Valor | Consecuencia |
|---|---|---|
| Motor | Godot 4.7, GDScript tipado estricto | `untyped_declaration=1`, `return_value_discarded=1` |
| Plataforma principal | Windows de escritorio, renderer **Forward+** | SDFGI, SSAO, niebla volumétrica y glow disponibles; Web solo en P4 |
| Física | Jolt, 100 Hz | El modelo de vuelo depende de esa frecuencia |
| Primer jefe | Arachnodroid | El rig de patas procedural es la tecnología central de P1 |
| Licencia | **Sala limpia**: ningún código derivado del simulador GPL | Ver `01-sala-limpia-y-reutilizacion.md` |
| Controles | Gamepad/radio primero | Sticks para volar, `fire/fire_alt/lock_target` remapeables; teclado+ratón en P4 |
| Identidad | Distinta del simulador: oscura, militar, holográfica | Paleta y fuentes nuevas, tema regenerado |

## 3. Hoja de ruta

Tamaños: **S** ≈ media sesión de un agente desarrollador, **M** ≈ una sesión, **L** ≈ una sesión larga o dos. Cada WP se cierra solo con su check headless en verde y revisión de código aprobada.

### P0 — Documentación y fundación
| WP | Objetivo | Doc que gobierna | Aceptación | Tam. | Dep. |
|---|---|---|---|---|---|
| WP-00 | Escribir esta documentación | — | Revisión del usuario (checkpoint 1) | L | — |
| WP-01 | Esqueleto del repo: `project.godot`, capas, input, autoloads stub, `.gdignore`, deny de lectura, `LICENSE/NOTICE/CREDITS`, CI 4.7, preset Windows | `02` | `project_check` | S | 00 |
| WP-02 | Copiar la lista cerrada de archivos propios + `Global` mínimo + `Events` + tema + CSV podado | `01`, `02`, `12` | `ui_smoke_test` mínimo, `build_theme` regenera | M | 01 |
| WP-03 | Autoloads de configuración: `Audio`, `GameSettings`, `Graphics`, `QuadSettings`, `Controls`, `DebugGeometry` | `04` | `settings_check` | M | 02 |
| WP-04 | Núcleo de vuelo I: cuerpo rígido, integrador, motores, hélices, arrastre, efecto suelo, dron placeholder | `03` | `flight_bench` I | L | 03 |
| WP-05 | Núcleo de vuelo II: `FlightController`, modos, rates, mezclador, `RadioController` | `03` | `flight_check` | L | 04 |
| WP-06 | `FPVCamera` con fisheye + `CameraRig` | `03`, `13` | `hud_projection_check` | M | 05 |
| WP-07 | Audio de motores, LED, `drone_rig.tscn`, sandbox de vuelo | `03` | `audio_check` básico | M | 06 |
| WP-08 | FlightHUD | `12` | `hud_projection_check` + captura | M | 07 |
| WP-09 | Menús de opciones I: hub, juego + HUD, gráficos, audio | `04` | `ui_smoke_test` ampliado | M | 03, 08 |
| WP-10 | Menús de opciones II: controles, bindings, calibración | `04` | `controls_check` | L | 09 |
| WP-11 | Quad settings, ayuda, pausa, menú principal, menú de rondas | `04`, `11`, `12` | `boot_check`, `loading_check`, `ui_smoke_test` completo | M | 10 |
| WP-12 | Pipeline voxel, GLB del Arachnodroid, import, dron voxel original | `05` | `voxsplit --report`, `enemy_import_check` | L | 01 |
| WP-13 | Import de la ciudad FreeSample | `10` | `city_import_check` | M | 01 |

**Checkpoint 2**: el dron vuela en el sandbox con HUD, los menús están completos y los assets importados.

### P1 — MVP
| WP | Objetivo | Doc | Aceptación | Tam. | Dep. |
|---|---|---|---|---|---|
| WP-14 | Arma, proyectiles, trazadores, asistencia, impactos, retroceso | `08` | `weapon_check` | M | 07 |
| WP-15 | Energía, pilas, casco, respawn | `09` | `energy_check` | M | 14 |
| WP-16 | `EnemyBase`, `EnemyPart`, `WeakPoint`, desprendimiento, `DebrisPool` | `06` | `enemy_parts_check` | L | 12 |
| WP-17 | `ProceduralLegRig` + `GaitController` + IK | `06` | `gait_check` | L | 16 |
| WP-18 | Percepción, selector de utilidad, personalidad, FSM, telegrafía | `06` | `ai_check` | M | 17 |
| WP-19 | Arachnodroid completo | `07` | `arachnodroid_check` | L | 18 |
| WP-20 | Ciudad destructible, integridad, distrito A, rocas | `10` | `city_check` | M | 13 |
| WP-21 | Rondas, objetivos, resultados, persistencia | `11` | `round_check` | M | 19, 20 |
| WP-22 | CombatHUD | `12` | `combat_hud_check` | M | 21 |
| WP-23 | Balance y smoke test manual | `07`, `15` | 3 partidas de 6–10 min | M | 22 |

**Checkpoint 3**: MVP jugable.

### P2 — Pulido AAA
| WP | Objetivo | Doc | Aceptación |
|---|---|---|---|
| WP-24 | `environment_battle.tres`, presets de calidad | `13` | `render_check` |
| WP-25 | Identidad UI, fuentes, tema, backdrop 3D del menú | `13` | `menu_shots_check` (capturas de los 8 menús) |
| WP-26 | VFX | `13` | `vfx_check` |
| WP-27 | Audio 3D, buses, música por capas | `13` | `audio_check` |
| WP-28 | Sacudida de cámara y overlay FPV | `13` | `shake_check` |
| WP-29 | Optimización y perfilado | `15` | `perf_report` |
| WP-30 | Export Windows y checks en CI | `02`, `15` | CI verde con artefacto |

**Checkpoint 4**: fin de P2.

### P3 — Contenido
WP-31 QuadrupedTank · WP-32 `BipedRig` + MechGolem · WP-33 MechaTrooper · WP-34 FieldFighter · WP-35 MobileStorageBot y rondas de intercepción · WP-36 Mecha01 y bloqueo direccional · WP-37 ReconBot y rondas mixtas · WP-38 Companion-bot y ronda final · WP-39 rondas 2–8 y progresión. Gobierna `14-catalogo-de-enemigos.md`.

### P4 — Opcional
WP-40 vuelo con teclado y ratón · WP-41 build Web/Compatibility y despliegue a itch.io · WP-42 tutorial de combate con `ObjectiveSequencer`.

### Paralelismo permitido
WP-12 y WP-13 corren en paralelo con WP-02…11. WP-14/15 corren en paralelo con WP-16…18. WP-20 corre en paralelo con WP-16…19.

## 4. Mapa de documentos

| Archivo | Contenido | Gobierna |
|---|---|---|
| `00-plan-maestro.md` | Este documento | todos |
| `01-sala-limpia-y-reutilizacion.md` | Qué se reutiliza, qué se reimplementa, protocolo legal | WP-02 en adelante |
| `02-configuracion-del-proyecto.md` | `project.godot`, capas, input, autoloads, import, CI | WP-01 |
| `03-especificacion-nucleo-de-vuelo.md` | Spec del dron: física, control, radio, cámara, audio, banco de pruebas | WP-04…07 |
| `04-especificacion-configuracion-y-menus.md` | Spec de autoloads de configuración y de todos los menús | WP-03, 09…11 |
| `05-pipeline-voxel.md` | `.vox` → partes → GLB → import | WP-12 |
| `06-framework-de-enemigos.md` | Contrato de enemigo: partes, puntos débiles, rig, IA | WP-16…19, P3 |
| `07-arachnodroid.md` | Ficha del primer jefe | WP-19, 23 |
| `08-combate-y-armas.md` | Arma, proyectiles, asistencia, calor | WP-14 |
| `09-energia-y-danio.md` | Energía, pilas, casco, respawn | WP-15 |
| `10-ciudad-destructible.md` | Import de la ciudad, edificios, integridad | WP-13, 20 |
| `11-rondas-y-objetivos.md` | Catálogo de rondas, manager, objetivos, resultados | WP-21 |
| `12-interfaz-y-hud.md` | FlightHUD, CombatHUD, menús | WP-08, 22 |
| `13-identidad-visual-y-audio.md` | Paleta, Environment, VFX, audio, shake | WP-24…28 |
| `14-catalogo-de-enemigos.md` | Los 9 enemigos y su orden | P3 |
| `15-verificacion-y-ci.md` | Checks, smoke test, rendimiento, CI | todos |
| `16-licencias-y-atribucion.md` | Licencia del juego y atribuciones | WP-01, publicación |

### 4.1 Leyenda de referencias heredadas

Varios documentos (02, 05, 06, 07, 08, 09, 10, 11, 14) citan «plan §4.x» o «Anexo A/B/C»: son referencias al **borrador extenso** de este plan, que se condensó al redactarlo. Equivalencias vigentes, para no tener que reescribir cada cita:

| Cita heredada | Dónde vive ahora |
|---|---|
| plan §4.1 (render, input, física) | `02` §2 y §12 |
| plan §4.2 (capas y máscaras) | `02` §3.1 y §3.3 |
| plan §4.4 (bus de eventos) | `00` §6 («Eventos») y el **Contrato de Events** de `02` §5.1 |
| plan §4.5 / §4.6 / §4.7 (dron, enemigos, ciudad) | tablas de parámetros de `03` §10, `06` §15 y `10` §10 |
| Anexo A (cifras de balance) | `07` §8 y §12, `09` §4, `10` §10 |
| Anexo B (tabla de partes del Arachnodroid) | `05` §4.4 |
| Anexo C (valores del arma y de la energía) | `08` §4 y `09` §4 |

## 5. Orquestación: Fable orquesta, Opus desarrolla

### 5.1 Ciclo de un paquete de trabajo
1. El orquestador crea la rama `wp-NN-nombre` desde `master`.
2. Redacta el **brief** (plantilla en 5.2) y lanza un agente desarrollador con `model: opus`.
3. El agente implementa, crea o amplía el check headless del WP y lo deja en verde.
4. El orquestador corre el check y los anteriores: `"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/<x>_check.tscn` (o `tools/run_checks.ps1`).
5. Un agente `godot-code-reviewer` revisa el diff contra las convenciones (§6) y contra `01-sala-limpia-y-reutilizacion.md`.
6. Correcciones, commit en español imperativo (sin push), cierre del WP y actualización del estado en este documento.

### 5.2 Plantilla de brief
```
WP-NN — <título>
Objetivo: <una frase>.
Documentos que gobiernan: docs/NN-….md (leer completos antes de escribir código).
Entradas: <archivos existentes relevantes, con rutas>.
Salidas: <archivos a crear/modificar>.
Interfaz a respetar: <clases, señales, métodos, recursos que otros WPs consumen>.
Aceptación: <check>, comando exacto, métricas.
Tamaño: S/M/L. Rama: wp-NN-<nombre>.
Prohibiciones: no abrir C:\Users\Mauri\Godot\Proyectos\drone-simulator ni ninguna ruta bajo ella;
no cambiar interfaces de otros WPs sin anotarlo en el resumen; no tocar user://config del jugador.
Convenciones: §6 de docs/00-plan-maestro.md.
Al terminar: resumen de decisiones, desvíos respecto al doc, y salida del check.
```

### 5.3 Ruteo de agentes
| Tipo de trabajo | Agente |
|---|---|
| Gameplay, física, IA, sistemas | `godot-prompter:godot-game-dev` |
| Menús, HUD, tema | `godot-prompter:godot-ui-designer` |
| Shaders y efectos de pantalla | `godot-prompter:godot-shader-author` |
| Pipeline Python / Blender | `general-purpose` |
| Rendimiento | `godot-prompter:godot-performance-profiler` |
| Revisión | `godot-prompter:godot-code-reviewer` |

### 5.4 Checkpoints con el usuario
1. Documentación escrita (fin de WP-00).
2. Fin de P0: el dron vuela con HUD y menús completos; el usuario prueba con su radio.
3. MVP jugable (fin de WP-23).
4. Fin de P2.

## 6. Convenciones

- **Idioma**: documentación, comentarios de diseño, mensajes de commit y textos en español; código, identificadores, nombres de archivos y claves en inglés.
- **Tipado**: todo declarado con tipo; valores de retorno no usados capturados con `var _discard := ...`.
- **Estilo**: `snake_case` para archivos y miembros, `PascalCase` para `class_name`, `SCREAMING_CASE` para constantes; docstrings `##` en cada clase y método público.
- **Traducción**: nunca literales en la interfaz; claves con prefijo (`UI_`, `MENU_`, `OPT_`, `AUD_`, `GFX_`, `CTRL_`, `CAL_`, `HUD_`, `QUAD_`, `ROUND_`, `RESULT_`, `ENEMY_`, `ERR_`, `GAME_`) en `localization/translations.csv` (`keys,es,en`, español primero, orden alfabético). En los `.tscn` el `text` es la clave; `tr()` solo cuando hay formato; reconstrucción en `NOTIFICATION_TRANSLATION_CHANGED`.
- **Catálogos**: datos estáticos en `class_name X extends RefCounted` con `const` de diccionarios y funciones puras estáticas. Los ids son para siempre: son la clave de guardado.
- **Un nivel compartido por modo**: el contenido se instancia dentro; nunca una escena por ronda.
- **Persistencia**: solo la métrica cruda (`best_score_<id>`, `best_time_<id>`); medallas y desbloqueos se derivan. Config en `user://config/*.cfg` con `ConfigFile`; cada cargador devuelve una clave de error que se acumula en `Global.startup_errors`.
- **Eventos**: `Events` publica hechos, nunca comandos; solo el sistema dueño del hecho lo emite.
- **Física**: capas de `02-configuracion-del-proyecto.md`; ningún `Area3D` como hitbox; consultas con `PhysicsDirectSpaceState3D`.
- **Verificación**: cada feature entrega `tools/<feature>_check.tscn` que devuelve código ≠ 0 al fallar y restaura la configuración del jugador.
- **Git**: **ningún commit ni push sin confirmación explícita del usuario** (regla fijada el 2026-09-19). Los agentes trabajan en el árbol de trabajo sobre archivos disjuntos; cuando el usuario autoriza, se hace un commit por WP (o por checkpoint) con mensaje en español imperativo (`Agregar el rig de patas procedural`).
- **Assets**: `assets/_raw/` lleva `.gdignore`; todo lo importable vive en `assets/<dominio>/`; texturas comprimidas para VRAM con mipmaps.

## 7. Estado

| Fecha | Hito |
|---|---|
| 2026-09-19 | Plan aprobado; WP-00 escrito, conciliado y mergeado a `master` |
| 2026-09-19 | WP-01 cerrado: `project_check` en verde con prueba negativa. Ajustes: `PhysicsLayers` movido a `res://core/` (tools/ está excluido del export); `builds/windows/.gitkeep` versionado; `gdscript/warnings/exclude_addons` no existe en 4.7 (se usa el default de `directory_rules`); las advertencias de GDScript no se imprimen en headless, así que el tipado estricto se controla en revisión |
| 2026-09-19 | WP-02 cerrado: plomería UI propia copiada (17 `.gd`), tema regenerado, CSV podado y reparado (328 claves), boot → menú mínimo, `ui_smoke_test`/`boot_check`/`loading_check` (parcial, SKIP documentado) en verde. `SceneTransition` gana `_next_draw()` para headless |
| 2026-09-19 | WP-13 cerrado: 13 piezas VoxelCity importadas (escala ×5, texturas 2K/1K, 9,3 MB de VRAM), `city_import_check` en verde; hallazgos en `10` §1 |
| 2026-09-19 | WP-12 cerrado: pipeline Python (31 partes, 4 274 tris, GLB determinista), dron voxel de 16 partes, scripts de import con colisionadores/capas/metadatos, `enemy_import_check` con 4 pruebas negativas. Notas en `05` §1 |
| 2026-09-19 | WP-03 cerrado: autoloads de configuración reales, `ControlProfile` (`RateCurve`, 5 curvas verificadas), `ControllerAction`, `settings_check` con prueba negativa; suite en verde (8 pasos con `enemy_import_check`). Notas en `04` §1 |
| 2026-09-19 | WP-09 cerrado: hub, Juego/HUD, Gráficos y Audio sobre `MenuScreen`; `ui_smoke_test` recorre las 4 pantallas (119 claves es/en, persistencia, foco). Hallazgo: dos suites de checks concurrentes colisionan en `user://` y `tools/out` → regla operativa: un solo `run_checks` a la vez; endurecer `CheckRunner` (config temporal por PID por defecto) en el próximo WP que lo toque |
| 2026-09-19 | WP-04 cerrado: `Drone` con integrador propio, motores, hélices, arrastre, efecto suelo, modelo voxel cableado; `flight_bench` I en verde (TWR 5,52, hover 0,395, 0,32 ms/tick); notas en `03` §1 |
| 2026-09-19 | WP-10 cerrado: menú de controles (dispositivo, vista en vivo, ejes, 13 bindings con popup y banda de eje), calibración de 14 pasos, `controls_check` con test de mutación (9 aserciones); `ui_smoke_test` a 189 claves. Nota: en `Input`, `device = -1` casa con el InputMap pero no aparece en `get_joy_axis(0, …)` (usar `device = 0` para lecturas crudas) |
| 2026-09-19 | Incidente: WP-05 y WP-11 se cortaron por el límite de sesión de la API con el trabajo casi completo en el árbol. Un shell huérfano de WP-11 siguió lanzando checks colgados durante horas: al editar `check_runner.gd` se había perdido la línea `class_name CheckRunner extends Node`, con lo que ningún check encontraba su clase base y el proceso quedaba vivo sin escena (el timeout de `CheckRunner` no puede protegerlo porque nunca llega a `_ready`). Restaurada la declaración y refrescada la caché de clases (`--editor --quit`); `project_check` en verde. Lección para `15`: un check que no arranca cuelga el runner → `run_checks` debe imponer un timeout externo por proceso |
| 2026-09-19 | WP-05 y WP-11: código completo en el árbol; sus checks (`flight_bench`, `flight_check`, `pause_check`, `loading_check`, `ui_smoke_test`, `controls_check`, `settings_check`) pasan tras corregir: `class_name` de `CheckRunner`, miembros `_original_*` duplicados en tres checks, `run_checks.ps1` (timeout externo por proceso y lectura fiable de `ExitCode` con `-PassThru`), y el nivel de vuelo libre renderizaba blanco por sobreexposición con unidades físicas de luz → `CameraAttributesPhysical` en el `WorldEnvironment`; cámara de seguimiento acercada a 2,2 m. Suite completa en verde (12 pasos: import previo, editor, 9 checks headless y 2 con ventana). Revisión de código de ambos WPs en curso |
| 2026-09-19 | WP-06 cerrado: `FPVCamera` OFF/FAST/FULL con shaders propios, `CameraRig`, `HUDProjection`, `hud_projection_check` (shader y matemática coinciden a 1 px; FAST +1 % draw calls); notas en `03` §1 y `12` §1 |
| 2026-09-19 | Pasada de correcciones cerrada: 21 archivos, suite en verde (13 pasos). Pendientes registrados: `ui_smoke_test` sensible a la posición del puntero (forzar `UI.set_input_kind(KEYBOARD)` en WP-08); sandbox sin `camera_attributes` y cámara externa que pierde frente a la FPV (WP-07); con el dron posado la mitad inferior de la vista FPV es oscura (placeholder, WP-24) |
| 2026-09-19 | WP-07 cerrado: 8 loops de motor sintetizados y deterministas (1 MiB), `MotorAudio` (crossfade de potencia constante, limitador 300 dB/s, sin clics), `ModeLED` sobre la parte `led` del voxel, sandbox con exposición y cámara correctas, `audio_check` (2 pruebas negativas), `flight_check` §11.7 activo. Sol del nivel de vuelo libre corregido por el orquestador (apuntaba hacia arriba). Suite: 14 pasos |
| 2026-09-19 | WP-08 cerrado: FlightHUD (9 componentes propios + contenedor, estado, sticks, RPM, tema), integrado en el rig y en la vista previa del menú; el horizonte del HUD calza con la imagen del ojo de pez (error < 2,5 px en OFF/FAST/FULL). Suite en verde (14 pasos). Corrección del orquestador: la carcasa `camera` del voxel pasa a la capa visual 20 y la FPV la excluye (tapaba el centro de la imagen) |
| 2026-09-19 | Prueba del usuario con gamepad: había que mantener L1 para que el dron siguiera armado (L1 = `arm` mantener, L3 = `toggle_arm`). Defaults corregidos: L1 alterna el armado y `arm` (mantener) queda sin botón por defecto (switch de radio asignable). Checks `project/controls/flight/ui_smoke` en verde |
| 2026-09-19 | Checkpoint 2 aprobado por el usuario («va encaminado»). Feedback: el dron voxel se ve tosco (se pule en WP-25); rates demasiado sensibles → defaults de `QuadSettings` a ACTUAL 5/30/25 (sus valores). P0 commiteado en `master` (`c256afe`, un solo commit autorizado). **P1 iniciado**: WP-14 (arma) y WP-16 (framework de enemigos + `DebrisPool`/`RubbleField`) en paralelo |
| 2026-09-19 | WP-16 cerrado: `EnemyBase`/`EnemyPart`/`WeakPoint`, perfiles `Resource`, `DebrisPool`/`DebrisChunk`/`RubbleField` (en `city/`), catálogo, Arachnodroid con las 31 partes y 8 puntos débiles de `07`, 5 fases declarativas, `enemy_parts_check` (~9 s) y `enemy_showcase`. Decisiones: denominador fijo en `total_structure_ratio()`, `AFTER_PARTS` «N de una lista», el grupo `weak_points` contiene el `AnimatableBody3D`, `detach()` mueve las `CollisionShape3D` al chunk, un solo `enemy_part_broken` por parte, `continuous_cd` por masa > 2 000 kg, `detach_speed` 3 m/s. P4 («carcasa se abre», cono de núcleo a 55°) y P5 (`defeat` al expirar 45 s) quedan para WP-19 |
| 2026-09-19 | WP-14 cerrado: `WeaponMount`/`WeaponProfile`/`ProjectilePool`/`TracerRenderer`/`WeaponAimAssist`/`ImpactFXPool`/`MuzzleFlash`, sonidos sintetizados, `weapon_check` (19 sub-checks + perfil, ~35 s) con los valores del Anexo C; notas en `08` §1 |
| 2026-09-19 | WP-15 cerrado: `EnergySystem`/`EnergyProfile`, `BatteryPickup`/`BatterySpawner`, `Hull`/`HullProfile`, `RespawnController`, `energy_check` (23 sub-checks, prueba negativa de histéresis). Regresión detectada y corregida: con `EnergySystem` en `drone_quad.tscn`, `flight_bench` agotaba la batería durante el minuto simulado y el escalón de tasa no llegaba al 90 % → el banco retira `EnergySystem`/`Hull` antes de medir (como `weapon_check`). Notas en `09` §1 |
| 2026-09-19 | WP-20 cerrado: `Building` por etapas (shader de boquetes, ruinas, escombros reciclados con tope 24), `CityGrid` con celda de 32 m (bloques de 30 m), `district_a` de 60 edificios / 120 300 HP / 480×288 m con 15 oclusores y 4 `EnemySpawn`, `CityIntegrity`, 6 rocas de 18–40 m, `city_check` (~35 s) y `city_showcase`; `continuous_cd_mass` 800 kg; notas en el informe (celda 32 m, 2 perfiles, torres = `Building_3` ×0.40–0.55) |
| 2026-09-19 | WP-17 cerrado: `TwoBoneIK`, `Leg`, `GaitController` (trote por pares diagonales, trípode, arrastre), `ProceduralLegRig` (colocación por rayo con escalada y aplastamiento, plano de mínimos cuadrados, salto tuck→balístico→land, stagger, DOWNED), `gait_check` (deslizamiento 4 cm, inclinación 12° en rampa, `rig_tick` 130 µs) y showcase con marcha/rampa/salto. Hallazgo: la pose de marcha realizable pone las rodillas a 7,9 m (no 11) porque la cadena del modelo mide 13,6 m; el origen del cuerpo queda a −3,25 m con los pies en el suelo |
| 2026-09-19 | Regresión de `flight_bench` cerrada: la causa era el cambio de defaults de rates a 5/30/25 (máximo 300 deg/s): el banco asignaba `QuadSettings.control_profile` y pedía 360 deg/s. Ahora el banco fija `ControlProfile.new()` (referencia 7/67/54) y retira `EnergySystem`/`Hull` antes de medir; vuelve a 80 ms / 5,5 % |
| 2026-09-19 | WP-21 cerrado: `battle_level.tscn` único, `RoundManager` (INTRO 12 s saltable con cámara lenta al cierre, BATTLE, VICTORY/DEFEAT por el bus con prioridad DEFEAT), `ObjectiveSequencer`/`Objective` (copia propia del tutorial generalizada con `ObjectiveContext`), 4 objetivos, `RoundResult` + `result_card`, persistencia cruda, `round_check` 14/14, `loading_check` sobre el nivel real. Pendientes: `Global.debug_freeze_ai` (no existe), cartel de ciudad flotando a ~200 m (WP-20), spawn del dron a 40 m en caída (WP-23 decide) |
| 2026-09-19 | En curso: WP-18 (IA) y WP-22 (CombatHUD). Orquestador: `Global.debug_freeze_ai` agregado (`docs/11` §11; la IA lo honra desde WP-18/19 y `round_check` lo enciende); criterio 11 de `05` §14.2 corregido con las medidas reales (reposo: rodillas 8,625 m / pies 3,75 m; marcha realizable: rodillas 7,9 m, origen del cuerpo a −3,25 m). Cartel flotante de `district_a` resuelto: `CityGrid` colocaba los props de azotea a `base_size.y` antes de aplicar `height_scale`, así que sobre una torre al 54 % quedaban 37 m por encima del techo; ahora `Building._place_props()` los baja a `get_height()` guardando la posición de reposo en un metadato (idempotente, sobrevive al empaquetado) y `city_check` 5b lo verifica (17 props, base de malla a 0,00 m del techo). Incidente repetido: WP-18 y WP-22 cortados por el límite de sesión de la API (reinicio 19:00); ambos agentes retomados con su contexto |
| 2026-09-19 | WP-18 cerrado: `Perception`/`PerceptionProfile`, `Personality`, `ActionScore`, `UtilitySelector` (score², top-3), `EnemyAction` + `AttackLibrary`, `Telegraph` (luz + sonido + señal espacial, emite `enemy_attack_telegraphed`), `EnemyFSM` de dos capas con estados-nodo, acciones `approach` y `test_stomp` (provisional), sonido `charge.wav` sintetizado, `ai_check` (3 semillas con L1 ≥ 0,33 entre histogramas, σ 2,05/4,11 m, memoria 4,52 s, cegado σ 9,95 m, telegrafía 1,12 s, piso de windup 0,80 s medido en la FSM, `lock_locomotion` con 0,000 m de deriva, `debug_freeze_ai` 2 s sin muestras ni deriva, DOWNED sin consultas). Registrado en los runners con `--timeout=300`. Discrepancias anotadas en `06` §1; gate de apoyo de `stomp`/`pounce` corregido en `06` §10.2 y `07` §5.4. **En curso: WP-19 (Arachnodroid completo) y WP-22 (CombatHUD)** |
| 2026-09-19 | WP-22 cerrado: `CombatHUD` (capa 20, 15 componentes procedurales: energía, casco, calor, retículo con lock, hitmarkers, barra de jefe por puntos débiles, franja de ciudad, marcadores fuera de pantalla, dirección de daño, aviso de telegrafía, cronómetro, línea de objetivo, glitch de EMP, reconstrucción, rótulo de INTRO), integrado en `battle_level` y apagado con la tarjeta; 23 claves `HUD_*`; `combat_hud_check` (15 filas, prueba negativa de marcadores, capturas headless y con ventana; ~35 s) registrado en los runners; Movie Maker de la batalla con FlightHUD + CombatHUD juntos. Cuatro defectos de layout detectados en las capturas y corregidos antes de cerrar. Discrepancias con `12` anotadas en `12` §1. Interferencias transitorias con WP-19 en paralelo (clase `AudioRig` nueva, `.tres` de ataques a medio escribir) resueltas reintentando. **En curso: WP-19** |
| 2026-09-19 | Orquestador: el dron aparecía a 40 m sobre el suelo en `battle_level` y, al soltarlo la INTRO, caía y llegaba a BATTLE con el casco al 67 % (visto en el Movie Maker de WP-22). `Respawn` y `DroneRig` pasan a 1,5 m sobre el suelo en (120, 200), fuera del distrito y a 120 m del `EnemySpawn1`, como en el vuelo libre |
| 2026-09-19 | WP-19 cerrado: `TelegraphProfile`, `SweepAction`, las 8 acciones reales + `approach` (= `walk`), 16 `.tres` horneados por `build_arachnodroid_profile.gd`, 5 fases reales (P4 abre la carcasa 70° y amplía el cono a 55°; P5 temporizador 45 s + `detonate()` a ≤ 120 m), ceguera del visor con sensor de respaldo, `AudioRig` real (19 WAV sintetizados), `arachnodroid_check` (14 criterios + 3 negativas, 34 s; física 0,65–1,36 ms/tick mediana) registrado en los runners; `test_stomp` y los placeholders eliminados; corregidos de paso un bug de `EnemyFSM.request_action()` (la acción del `ctx` no llegaba a `ACTIVE`) y el `stagger` del aterrizaje que cancelaba el propio `pounce`. Orquestador: 14 claves `ATK_*`/`BOSS_PHASE_*` agregadas al CSV y `HUD_TELEGRAPH_TEST_STOMP` retirada. Hallazgo de diseño: con «rodilla rota = pata desprendida» P4 queda con 1 pata y P5 no puede marchar → decisión para el MVP: P4 postrado, P5 detona en el lugar, `pounce` con ≥ 2 apoyos (`07` §1 y §15 #11); haces placeholder de `head_laser`/`siege_beam` entregados en el cierre corto de WP-19 (`SweepAction.configure_beam`, criterio 15 de `arachnodroid_check`; `pounce` con `MIN_SUPPORT` 2 y `MAX_LEGS_LOST` 2; showcase con `pounce` en P3). Física 1,2 ms/tick mediana |
| 2026-09-19 | **Suite completa en verde con todo P1 en el árbol: 23 pasos en 290 s** (import previo, editor, 20 checks headless incluidos `ai_check`, `combat_hud_check` y `arachnodroid_check`, y 2 con ventana). Lanzado WP-23: `BotPilot` + `balance_check` (3 semillas + partida de control), ajuste de palancas de `07` §14, bono de tiempo a 8 pts/s (`11` §12 #3), `perf_report` (`15` §5) y recorrido del smoke test manual por Movie Maker |
| 2026-09-19 | WP-23 cerrado: `BotPilot` + `balance_check` (11 filas, 541 s; registrado como paso **extendido** de los runners: `-Extended` / `RUN_EXTENDED=1`, timeout propio 1 800 s), `perf_report` → `docs/perf/2026-09-19.json`. Tres bugs bloqueantes corregidos: nadie fijaba `Perception.target` (el jefe no veía al dron), los núcleos estaban dentro del collider de la panza (parche `pierces_host`), y el gate de apoyo abortaba `stomp`/`leg_sweep` (0 daño al casco). Palancas: rodillas 1 600 HP, `stomp` 9×12, `head_laser` r 1,8, `siege_beam` 1 100/s, cooldown P3+ ×0,55; bono de tiempo 8 pts/s y medallas 350/800/2000. Resultados: 401 s de media, integridad 0,61–0,63, 1–2 muertes, acierto 0,43; control pierde a los 431 s. Perf: 2,98 ms/tick y 48 fps con ciudad (WP-24/29). Cámara de reconstrucción corregida (miraba al cielo). Hallazgo bloqueante: romper la 4.ª rodilla dejaba la ronda sin fin → WP-19b en curso (DOWNED sobre el suelo, núcleos expuestos, P5 a 90 s; medalla NONE en derrota; reencuadre de la INTRO). Hechos en `06` §1/§10.2, `07` §1/§4/§5.1/§6/§14/§15, `11` §6.2/§12, `15` §1.1/§5/§7.1/§10 |
| 2026-09-20 | WP-19b cerrado: estado final de `DOWNED` (`LegRigProfile.downed_body_height` −6,0 m: el cuerpo apoya la panza en el suelo y los núcleos quedan a ~6,5 m; los tres `wp_core_*` pasan a `ALWAYS`; entra en `p5_selfdestruct` con temporizador propio de 90 s o conserva el restante), medalla NONE y bono de tiempo 0 en derrota (`RoundResult.resolve_medal`), INTRO reencuadrada desde el jefe (final a ~103 m y 26 m de alto, cabeza sobre el horizonte; el borde del plano ya no entra en cuadro). `arachnodroid_check` 10/10b, `round_check` fila 11 ampliada, `enemy_parts_check` con la progresión nueva. El cuadrilátero magenta de la INTRO era un cartel de neón emisivo del atlas de props del pack (WP-24/26). Suite completa relanzada |
| 2026-09-20 | **P1 completo → checkpoint 3 (MVP).** Suite completa en verde: 23 pasos en 313 s (más `balance_check` extendido, 541 s). Pendiente del usuario: smoke test manual de `15` §6 con la radio y autorización del commit. Limitaciones conocidas para P2: rendimiento con ciudad (2,98 ms/tick, 48 fps a 1080p), INTRO y ciudad planas sin `Environment` definitivo (WP-24), haces y decals placeholder (WP-26/27), pila y VFX provisionales, dron voxel tosco (WP-25), cajas de los núcleos dentro de la panza (parche `pierces_host`), `ui_smoke_test` con un fallo intermitente sobre el interruptor REC de la vista previa del HUD (visto una vez en WP-23, no reproducido) |
| 2026-09-20 | **P1 commiteado y subido**: `71b8387` «Construir el MVP P1…» en `origin/master` (377 archivos), autorizado por el usuario. Próximo: su smoke test manual con la radio y, con su visto bueno, P2 empezando por WP-24 (Environment y presets, que además ataca el rendimiento con ciudad) |
| 2026-09-20 | Checkpoint 3 jugado por el usuario: «va bien» con errores: costados del ojo de pez (FAST por defecto), el jefe se mueve raro y no se entiende cómo vencerlo, estructuras y calles del mapa fuera de escala. Prioridad: rendimiento y ambiente primero. Tipografías elegidas: Chakra Petch / Barlow Semi Condensed / JetBrains Mono. **Plan de P2 aprobado** (archivo de plan del orquestador; resumen: tanda 1 WP-24a rendimiento/presets/`render_check` ∥ WP-24b ciudad ∥ WP-24d marcha del jefe; tanda 2 WP-24 entorno → WP-24c ojo de pez FAST_WIDE + WP-24d guía para vencerlo → commit «P2 parte 1»; tanda 3 WP-25…30 → checkpoint 4). Diagnóstico previo: el churretón de FAST es geométrico (120° de render para 150° de campo, `clamp` en el shader); la doc 13 no tiene casi nada implementado (sin glow/SDFGI configurado, presets parciales, `camera_trauma` sin listeners, buses `Music`/`City` sin uso, sin overlay ni backdrop); ciudad con calles de 32 m sin rotar, cruces de vereda, props ×5, torres aplastadas. Regla reafirmada por el usuario: Fable orquesta, Opus desarrolla (ni arreglos chicos a mano). Tanda 1 lanzada |
| 2026-09-20 | WP-24a cerrado: los «48 fps» eran un artefacto del contador de fps del motor; medido con reloj de pared la batalla en HIGH da **263–267 fps (p1 131), 3,2 ms de GPU, 367 draw calls**, LOW 407. Aun así: `disable_3d` de la viewport raíz (renderizaba la escena entera para no mostrar nada: −95 % de GPU ahí), `SubViewport` del ojo de pez con oclusión, escala de render y LOD, `Graphics` aplicando toda la tabla de presets (`apply_sun_quality`/`register_sun` desde `LevelBase`, SDFGI 4/5 cascadas, ambiente de respaldo, niebla por preset, `max_emitters()`), `Environment` clonado por nivel, integrador del dron sin asignaciones (−57 % de coste, números de vuelo idénticos), `ProjectilePool` sin `create()` por rayo, `PerfProbe` + `PerfSampler`, `perf_report` con ablación y GPU por viewport, `render_check` (19 s; registrado con ventana 1080p en `run_checks.ps1` e informativo en CI), referencia `docs/perf/2026-09-20.json`. Hallazgo de método: `TIME_PHYSICS_PROCESS` es pico por segundo y no ms/tick (`15` §5). Variante B de SDFGI: +35 % fps pero imagen plana; decide el usuario en el checkpoint 4. Notas en `13` §1, `15` §5, `04` §1, `03` §1 |
| 2026-09-20 | WP-24b cerrado: distrito A regenerado con rejilla por carriles (calles de 16 m con veredas y cordón, avenidas de 32 m con cantero, marcas viales a lo largo, cruces de asfalto liso, patios sin estirar; 432 × 272 m), fachadas a la línea municipal y base a la altura de la vereda, 6 hitos de 74–80 m con pisos reales + 15 torres medias + 39 bajos, props a escala real (antena 1,8 m, carteles 3–6 m), rocas de 8–18 m fuera del cono de aparición, marcadores de pila repartidos (dos en azoteas), `city_check`/`city_import_check` con aserciones nuevas (fachada, silueta, orientación de bandas, material del cruce, escala de props). Economía intacta (60 edificios, 39/21, 120 300 HP). Capturas revisadas: aéreo, avenida, nivel de calle con cordón, azotea, silueta, INTRO sin tocar. Pendientes cruzados: `arachnodroid_check` `climb` en rojo por el rig en reescritura (WP-24d) y control de `balance_check` en 444–470 s contra 450 (ruido de la métrica; WP-24d ajusta marcha o ensancha a 480). Nota en `10` §1 |
| 2026-09-20 | Incidente: WP-24c, WP-24, WP-24d (rig) y WP-24d (guía) cortados a las ~2:40 por el límite de sesión de la API (reinicio 5:00); un `hud_projection_check` de WP-24c quedó colgado 8 h sin salida (error de parseo en headless: regla operativa para los briefs: checks siempre con `> log 2>&1` y timeout externo). Los cuatro agentes retomados a las 10:30 con su contexto. Dato parcial de WP-24c: FULL 68,5 fps / p1 28,3 y fuera del presupuesto de draw calls; FAST_WIDE p1 47,1 en HIGH, probando laterales más baratos |
| 2026-09-20 | WP-24c cerrado: viñeta honesta en vez de `clamp` en FAST y FULL, supermuestreo RGSS 4× donde la frontal se minifica, `project_direction` equidistante analítico en los tres modos de ojo de pez, `FPVCamera.coverage()`, **FAST_WIDE** (frontal 120° + dos caras de 100° a ±60° con `Environment` propio y barato: el coste de una viewport es fijo, no por píxel) como preset de HIGH: 215 fps / p1 109 / +1,1 ms sobre FAST, costura 0,0005; FULL medido 68 fps / p1 28 / 914 draw calls → ULTRA pasa también a FAST_WIDE (laterales 1080²) y FULL queda en el menú (cierre corto encargado). `hud_projection_check` 15 filas en 4 modos (cobertura, churretón/costura con prueba negativa, horizonte en 5 columnas); `settings_check`, `ui_smoke_test`, `render_check`, `flight_check`, `combat_hud_check` en verde. Pendiente WP-25: FlightHUD sobre la viñeta en LOW/MEDIUM. Notas en `03` §1, `04` §1, `12` §1, `13` §1 |
| 2026-09-20 | WP-24d parte 1 cerrado (marcha del coloso): diagnóstico visual en 3 encuadres × 7 actos (patas verticales y juntas, rodillas bajo la panza, puntales rectos, cruce al girar, sin peso al aterrizar, sin cadencia) → huella lateral de 22 m con rodillas a 9,4 m, zancada centrada de 0,8 s con llegada a velocidad cero y hasta 6 candidatos de apoyo, giro con pasos cortos, rebote y balanceo del ciclo, respiración en reposo, flexión al aterrizar, cabeceo de 25° al trepar, `face_toward` sin cabeceo, `set_climb_intent()` para trepar edificios angostos. `gait_check` 8 → 14 métricas (deslizamiento 0,000 m con umbral 0,10; flotación 0 s; rampa 15°; cabeceo 5,6°; giro 0,003 m; contacto→apoyo 0,04 s), `arachnodroid_check`, `ai_check`, `enemy_parts_check`, `balance_check` en verde (control 461 s → `RANGE_CONTROL` 240–480 en vez de subir `crush_damage`). Pendientes menores: roca del showcase de 12 m más angosta que la huella (34 m para la toma), `ERROR` inofensivo de `current_scene` en `balance_check._play`. Notas en `06` §1, `07` §1, `05` §14.2 |
| 2026-09-20 | Cierre corto de WP-24c: ULTRA pasa a FAST_WIDE con laterales 1080² (89 fps / p1 65 / 10,9 ms, contra FULL 68 / 28 / 14,1 y 914 draw calls); FULL queda en el menú y `settings_check` lo asevera. La fila 4 de `hud_projection_check` (horizonte) se rehízo con el borde más pronunciado de la columna y refinamiento sub-píxel porque el cielo físico de WP-24 (en curso) cruza la luminancia media dos veces y la niebla difumina el plano de medición: peor error 2,97 px. Con el entorno nuevo entrando en paralelo, `render_check` en HIGH está en 109 fps / p1 75 (740 draw calls, 330 k primitivas): dentro de presupuesto; WP-24 reporta el número final. Pendiente: `perf_report` mide con los defaults de `Graphics`: agregar `--preset`. Incidente del orquestador: un script de notas truncó `docs/13` al abrir para escribir antes de calcular el reemplazo; restaurada desde HEAD con las notas de WP-24a/24c reaplicadas; regla: calcular primero, abrir después |
| 2026-09-20 | WP-24d parte 2 cerrado (cómo vencerlo): cadena de 5 objetivos que enseñan (rodillas cian con contador → 3 rodillas abren la carcasa → núcleos desde abajo → derrotarlo antes de que detone → derrotarlo), `ObjectiveBreakCores` y `ObjectiveSelfdestruct` nuevos, `Objective.phase_index_of()`; `HUDBossBar` por grupos (RODILLAS · VISOR · NÚCLEOS, destello al exponerse, roto tachado gris), `HUDWeakPointHint` (corchetes cian tras 8 s sin acertar), `HUDCoachTip` (4 consejos de una vez), línea de consejo en la INTRO; 16 claves; `round_check` 15 filas y `combat_hud_check` 17 filas en verde; capturas y Movie Maker con el bot revisados (t = 6 / 22 / 46 / 70 s). Pendiente: `OBJ_DEFEND_CITY_PROGRESS` huérfana (WP-25). Notas en `11` §1 y `12` §1. **Tanda 1+2 de P2: solo falta WP-24 (entorno y luz)** |
| 2026-09-20 | WP-24 cerrado (entorno y luz): dos bugs medibles corregidos (materiales de ciudad con `emission_operator` ADD que encendían toda fachada a 1 000 nits; escena expuesta para mediodía con `background_intensity` 30 000 nits, sol ×1,45 y f/16 · ISO 100), `environment_battle.tres` generado por `tools/build_environment.gd` con cielo físico, niebla, glow, SDFGI, SSAO/SSIL y AgX (`tonemap_agx_contrast` 1,35; `tonemap_contrast`/`HIGH_QUALITY` no existen en 4.7), exposición compartida f/2,8 · ISO 400 (`camera_attributes_dusk.tres`), `SunProfile`/`SunLight` (2 400 lux, 3 200 K), `ReflectionProbeRig` en runtime (0/2/4/6), `gi_mode` verificado, banderas A/B `gi_variant`/`tonemap` y `tools/environment_shots` con 10 capturas en la misma pose; sin LUT. `render_check` HIGH 122 fps / p1 80 (el ojo de pez a 3 viewports es el 98 % de la GPU), B 138 fps. Recomendación: A (SDFGI) + AgX. Traspasos: periferia quemada de las caras laterales (WP-24c) y calibración de `enemy_showcase` (WP-24d), ambos encargados. Notas en `13` §1 y `10` §1 |
| 2026-09-20 | Cierre corto de WP-24d: `tools/enemy_showcase.tscn` calibrado al entorno compartido (`camera_attributes_dusk.tres` y `Sun` como `SunLight` con `sun_dusk.tres`, registrado con `Graphics.register_sun()`; el sol deja de ser un key light a medida y pasa a ser el de atardecer compartido), roca del acto `leap` a 34 m de lado (el aterrizaje apoya las 4 patas). `gait_check` y `arachnodroid_check` en verde. Falta solo el cierre de la periferia de FAST_WIDE (WP-24c) para correr la suite completa |
| 2026-09-20 | Cierre de WP-24c: el anillo quemado de FAST_WIDE era el chasis del dron en las caras laterales → todo el modelo del dron a la capa visual 20 (`drone.gd`), quemado 10 % → 0,1 %, `render_check` HIGH 132 fps / p1 87 / 713 draw calls; `hud_projection_check` fila 1 nueva (`fov` de cada sub-cámara y sin `attributes` propios: asignar `CameraAttributesPhysical` a una cámara sobrescribe el `fov` a 160°); hallazgo de método: `--editor --quit` no detecta errores de parseo (`15` §7.1). **Tanda 1+2 de P2 completa**: suite completa lanzada |
| 2026-09-20 | **P2 parte 1 lista para commit**: suite completa en verde, **24 pasos en 336 s** (con `render_check` a 1080p: HIGH 132 fps / p1 87 / 713 draw calls, LOW 370). 125 archivos modificados o nuevos sin commitear. Pendiente del usuario: autorizar el commit «P2 parte 1» y probar fps, mapa, ojo de pez y jefe; elegir A/B de SDFGI y AgX/ACES (recomendación: A + AgX) |
| 2026-09-20 | **Checkpoint 3b**: el usuario probó la parte 1 y reportó tres bugs (sonido del dron en loop al reconstruir; mapa y enemigo que aparecen y desaparecen; batería a cero con recarga lentísima → quiere reconstrucción con 20 %) y pidió una identidad propia, minimalista y escalable, distinta del simulador, con `docs/narrativa/narrativa.md` e `identidad-visual-opciones.md` (suyos) como contexto. Diagnósticos (solo lectura): el loop es `MotorAudio` leyendo `rpm` congelado (el `freeze` del respawn impide que las RPM decaigan); el parpadeo son los 15 oclusores del distrito que nunca se retiran al derrumbe, encendidos en las `SubViewport` del ojo de pez desde WP-24a (y la oclusión no ahorra nada medible); la energía a 0 % recarga 1 %/s hasta 10 %. Decisiones validadas con el usuario: identidad **A · Última luz + dos préstamos de B**, HUD de vuelo con el mismo instrumental y otro estilo, **alerta del taller** antes del nivel y **edificio protegido con nombre** (versión mínima) en esta tanda. Plan de P2 actualizado (WP-24e correcciones → commit «P2 parte 1 + correcciones»; WP-25 identidad ∥ WP-25b datos → WP-25b pantalla → commit «P2 parte 2»; luego WP-26…30). Regla operativa nueva para briefs: checks con `> log 2>&1` y timeout externo; nada de capturas sin mirar. **WP-24e lanzado** |
| 2026-09-20 | WP-24e cerrado (correcciones del checkpoint 3b): `MotorAudio` calla en 0,25 s al congelar el dron (RPN clavadas confirmadas: 25 725 durante 12 s), oclusión apagada en proyecto y presets + oclusores retirados al derrumbe (`CityGrid.occluder_for`), LOD lateral = preset, batería a 0 % → reconstrucción con motivo ENERGY y 20 % (`Hull.deactivate()` evita el doble `drone_destroyed`), «SIN BATERÍA» en el cartel. Guardianes en `audio_check` 6b, `city_check` 8b, `settings_check`, `round_check` 8, `combat_hud_check` 10, `energy_check` 5/9/10/16; `balance_check` en rango sin tocar el bot. **Suite completa en verde: 24 pasos**; `render_check` HIGH 131 fps / p1 88. Movie Maker de los tres casos revisado. Notas en `09`, `03`, `10`, `11`, `12`, `13`, `15` §1. Pendiente del usuario: autorizar el commit «P2 parte 1 + correcciones» |
| 2026-09-19 | **P0 completo → checkpoint 2.** Faltan de P0 solo pendientes cosméticos para P2 (contorno del HUD flojo sobre fondo claro; suelo oscuro con el dron posado; `Environment` provisional). Próximo: P1 (WP-14…23) tras el visto bueno del usuario |

## 8. Registro de conciliación (2026-09-19)

Revisión cruzada de los 17 documentos: firmas del bus, nombres de método, grupos de nodos, cifras y decisiones abiertas. Lo que sigue es el resumen por documento; el detalle vive en cada uno.

| Doc | Qué se cambió | Por qué |
|---|---|---|
| `00` | Nueva §4.1 con la leyenda de referencias heredadas («plan §4.x», «Anexo A–C»); WP-25 pasa a nombrar `menu_shots_check`; esta §8 | Esas citas apuntaban a un borrador del plan que ya no existe, y el check de WP-25 no tenía nombre |
| `01` | Nueva §2.3 con las **firmas reales** de `ChoiceMenu`, `MenuScreen`, `UI`, `SceneTransition` y `StickNavigation`, más la nota de reemplazo de `UI_TIP_*` | Tres documentos suponían firmas distintas de piezas que se copian tal cual y no se pueden cambiar |
| `02` | Nueva §5.1 **Contrato de Events** (21 señales + la regla de aridad de Godot 4); `Events` pasa de 18 a 21 señales en §5, §11, §12 y en `project_check` | Era el conflicto bloqueante de 08, 09 y 10: tres firmas divergentes de la misma señal revientan en tiempo de ejecución |
| `03` | Se agrega `@export var respawn_point: Node3D` a la interfaz de `Drone` (§9) y se ajusta el cableado de §8 | `09` lo consumía como propiedad del `Drone` y `03` lo declaraba solo en `drone_rig.gd` |
| `04` | §3 reordenado al orden canónico de autoloads (`Controls` pasa a 3.3); `hud_config` documentado como 13 claves con `STATUS` siempre visible; `MENU_MAIN_CONFIRM` → `MENU_QUIT_ROUND_CONFIRM`; `fps` default 10 explícito | El orden no coincidía con `02` §5, `12` contaba 12 bools donde `04` lista 11, y la clave de confirmación de pausa difería de `11` y `12` |
| `05` | D-1 cerrada: **31 nodos de malla** (23 estructurales + 8 puntos débiles); `_emit` aclarado como valor de `_type`, con `_weight`/`_flux` como claves canónicas | Ya no requiere decisión del usuario, y `_emit` se leía como campo de intensidad |
| `06` | `Hull.take_damage()` → `Hull.apply_damage(amount, source_position)`; `camera_trauma` con posición; `adopt()` con `PhysicsBody3D`; alta en el grupo `enemies`; `get_instance_count(mesh_index)`; riesgos 7 y 8 cerrados; §14.2 apunta a `02` §3.1 | Nombres y aridades que no existían en el documento dueño |
| `07` | `camera_trauma` con posición en `stomp`, `pounce` y la detonación de P5; ceguera del visor cerrada (20 s + sensor de respaldo a los 45 s); §3 y §11 apuntan a `05` §4.4 y `02` §3.1 | Cierre de la duda abierta de balance y de dos referencias muertas |
| `08` | §2.11 y riesgo 1 cerrados a favor de `shot_fired(origin, direction)` y `hit_confirmed(position, weak, lethal)`; `docs/12 §456` → `docs/12` §4.1 | Era el bloqueo declarado de WP-14; el enum `HitKind` se deriva en el HUD y no viaja por el bus |
| `09` | `battery_collected(amount, position)` (orden invertido en dos sitios); tabla de reconciliación de §2.10 y riesgo 4 cerrados; piso 0.30 del multiplicador de respawn (`respawn_multiplier_floor`); recarga en reposo aceptada; se quita la atribución al simulador de la medición de `Area3D` | Firmas canónicas, decisiones de balance cerradas y regla de sala limpia |
| `10` | `DebrisPool.acquire()` → `adopt(mesh, body, mass, impulse, lifetime)`; se elimina `RubbleField.absorb()`; `get_ratio()` marcado como canónico y `ratio()`/`rebuild()` como alias; §9.5 y riesgo 1 cerrados; referencias `§205`/`§166`/`§4.2 del plan` corregidas | `06` y `10` nombraban de tres formas distintas los mismos dos métodos |
| `11` | `time_par` 420 → **540 s** (tabla, §6.2, §10 y `round_check` §11 recalculados); piso 0.30 y −300 por muerte confirmados; `target_phase` → `target_phase_id`; `EnemyBase` → `Node3D` en las firmas del bus; `option_chosen` → `chosen`; riesgos 1, 2, 3, 7 y 12 cerrados | Decisiones de balance del orquestador y alineación con el Contrato de Events |
| `12` | `hud_config` de 14 → **13 claves** (`STATUS` sin bool, 11 interruptores); `fps` default 10; `Reticle` pasa a los métodos reales de `WeaponMount`; grupo `under_siege` → `buildings_under_siege`; `p3_rage` → `p3_fury`; `change_scene(..., show_loading := false)`; seis claves `UI_TIP_*` nuevas | El menú de `04` y el HUD contaban componentes distintos, y tres nombres no existían en el documento dueño |
| `13` | Ruinas (`StageRubble`) pasan a `GI_MODE_DISABLED`; `p3_rage` → `p3_fury`; `camera_trauma(amount, position)`; `battery_collected(amount, position)`; fuentes a `gui/theme/fonts/` | `10` §3.2 exige `DISABLED` en ruinas y las dos firmas estaban invertidas |
| `14` | `Mecha01.rar` se extrae con `UnRAR.exe` y **no** sale del alcance; `enemy_mark_shared` y `enemy_wave_requested` con las firmas del Contrato de Events; §7 apunta a `02` §3.1 | Decisión cerrada del orquestador y dos señales del bus sin dueño ni firma |
| `15` | Catálogo de 26 → **28 checks** (`menu_shots_check` y `enemy_catalog_check`); nueva §3.1 con los 10 que no corren headless; `Events` 18 → 21 señales; `audio_check` 4 → 7 buses; VRAM de ciudad por lectura de `.import`; comandos de `render_check`/`perf_report` corregidos; listas de `run_checks` actualizadas | Dos documentos dueños habían introducido checks que el catálogo no registraba, y tres criterios contradecían al documento dueño |
| `16` | Se agrega como criterio de aceptación explícito la confirmación del **nombre legal del titular** | Estaba solo como D-7 en `02`, sin dueño |

### Decisiones pendientes del usuario

Solo éstas requieren al usuario; todo lo demás quedó cerrado arriba.

> **Diferido por decisión del usuario (2026-09-19)**: los puntos 1 a 4 (nombre legal, licencias de packs, fuente del boot y tipografía) se resuelven al final del proyecto, cuando el juego esté encaminado. Mientras tanto no se crean `LICENSE`/`NOTICE`/`CREDITS.md` y `project_check` no los exige; la fuente del boot y las fuentes Recursive se usan tal cual durante el desarrollo.

1. **Nombre legal completo del titular** del copyright, para `LICENSE`, `NOTICE` y `CREDITS.md` (`02` D-7, `16` §7). Bloquea el cierre de WP-01 en su parte legal, no el código.
2. **Licencias de los dos packs de assets**: los nueve `.vox` de mechas (incluido `Mecha01.rar`) y el pack de ciudad *VoxelCity Free Sample*. Hay que confirmar uso comercial, derecho de modificación y crédito exigido antes del checkpoint 3 (`16` §4). Si alguno no permite uso comercial, el reemplazo es caro.
3. **Licencia de la fuente `Withheld Data.otf`** del boot: sin documentar. Por defecto se sustituye por una OFL, salvo que el usuario confirme su origen (`01` §7, `16` §5).
4. **Identidad tipográfica**: `13` §2.3 propone Chakra Petch / Barlow Semi Condensed / JetBrains Mono con alternativas por rol. Es una decisión estética que conviene cerrar antes de WP-25.
5. **Umbrales de medalla de la ronda 1**: con `time_par` 540 s y 25 puntos por segundo, el bono de tiempo domina el puntaje y 600/1300/2000 se vuelven triviales (`11` §6.2 y §12 fila 3). La palanca —bajar el bono a ~8 pts/s o subir los umbrales— se elige con datos reales en WP-23, pero el usuario puede fijarla antes si prefiere.
