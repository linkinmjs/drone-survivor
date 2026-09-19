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
