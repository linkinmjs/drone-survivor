# 04 — Especificación de configuración y menús (sala limpia)

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-03, WP-09, WP-10, WP-11 · Depende de: `02-configuracion-del-proyecto.md`, `03-especificacion-nucleo-de-vuelo.md`, `12-interfaz-y-hud.md`, `11-rondas-y-objetivos.md`

## 1. Objetivo y alcance

> **Nota de WP-24c (2026-09-20)**: `Graphics.FisheyeMode` pasa a `{OFF, FULL, FAST, FAST_WIDE}` (`_read_enum` acota, los `.cfg` viejos siguen válidos); presets de ojo de pez `[FAST 480p, FAST 720p, FAST_WIDE 1080p, FAST_WIDE 1080p]` con `fisheye_side_height/_msaa_level/_mesh_lod()` por preset; el menú de gráficos suma `GFX_FISHEYE_FAST_WIDE` («Rápido amplio» / «Fast wide»); FULL sigue disponible en el menú. `settings_check._check_fisheye_presets()` lo verifica.

> **Nota de WP-24a (2026-09-20)**: las tablas de sombras de §3.5 quedaron desactualizadas: `Graphics` usa atlas `2048/2048/4096/8192/8192` y filtros `SOFT_LOW/SOFT_LOW/SOFT_LOW/SOFT_MEDIUM/SOFT_HIGH` por nivel de sombras (`docs/13` §3.4 manda), más distancia y splits por preset (`SHADOW_SPLIT_COUNTS/DISTANCES/SPLIT_1`) aplicados con `apply_sun_quality()` al sol registrado por cada nivel (`register_sun()`, señal `shadows_changed`). Los presets también fijan escala de render y oclusión de las `SubViewport` del ojo de pez, `mesh_lod_threshold`, SDFGI/SSIL/SSAO/niebla/ambiente de respaldo y `max_emitters()`; `Quality.CUSTOM` se resuelve con `effective_quality()` a partir del nivel de sombras. El menú de gráficos no cambió (rótulos genéricos). `settings_check` verifica las tablas.
> Nota del checkpoint 2 (2026-09-19): los defaults persistidos de rates en `QuadSettings` pasan a **ACTUAL 5 / 30 / 25** (centro 50 deg/s, máximo 300 deg/s, expo 0,25), valores que el usuario fijó en su prueba con gamepad porque 7/67/54 era demasiado sensible; `reset_rates()` vuelve a estos. `ControlProfile.new()` conserva 7/67/54 como perfil de referencia de `03` §3.6.


> **Nota de WP-03 (2026-09-19)**: (1) el enum de curvas de `ControlProfile` se llama `RateCurve` (el nombre `Curve` colisiona con la clase del motor); el miembro sigue siendo `curve: int`. (2) `Controls.get_flight_input()` devuelve un diccionario vacío (no `null`) cuando no hay joypad. (3) Atajos de teclado de depuración: manda la tabla de `02` §4.3 (R respawn, F fire_alt, Q lock_target, E cycle_target, Shift arm) más Retroceso→respawn, Tab→cycle_target y clic derecho→fire_alt; se descarta Shift→lock_target. (4) `is_round_unlocked` no vive en `GameSettings` (no debe depender del catálogo): la derivación va en `RoundCatalog` (WP-21) sobre `get_best_score`/`has_completed`. (5) Filtro de sombras: el mapeo a `RenderingServer.ShadowQuality` es 0/2/3/4/5 (el motor intercala `SOFT_VERY_LOW`). (6) Las etiquetas `QUAD_HELP_RACEFLIGHT_RC/_RATE` del CSV están invertidas respecto de la fórmula de `03` §3.6 (`rc_rate` = escala base, `rate` = Acro+): WP-11 corrige las etiquetas.


Especificar los autoloads de configuración (`Global`, `Audio`, `Controls`, `GameSettings`, `Graphics`, `QuadSettings`, `DebugGeometry`) y todos los menús del juego (hub de opciones, juego y HUD, gráficos, audio, controles con bindings y calibración, hangar/quad con gráfico de rates, ayuda, pausa, menú principal). Se apoya en piezas propias ya existentes que **no** se rediseñan: `UI`, `StickNavigation`, `SceneTransition`, `MenuScreen`, `ChoiceMenu`, `ThemeBuilder`/`UIPalette`, `ConfirmOverlay`, `ControlHints`, `LoadingSpinner`. El menú de rondas se detalla en `11`; el HUD en `12`.

**Regla de sala limpia**: implementar solo desde este documento; libertad total sobre la estructura interna respetando la interfaz de §7.

## 2. Principios comunes
- Persistencia con `ConfigFile` en `user://config/<Nombre>.cfg`. Cada `load_*()` devuelve `""` si todo va bien o una clave `ERR_*` que `Global.load_startup_settings()` acumula en `Global.startup_errors`; el menú principal las muestra con `UI.alert()` y las vacía. Un archivo ausente **no** es error (se escriben los valores por defecto); un archivo corrupto sí (`ERR_CONFIG_<NOMBRE>`), y se reemplaza por defaults.
- Cada autoload expone sus valores como propiedades tipadas, un `save_*()` y una señal `*_updated` que emite después de guardar.
- Nada de literales en la interfaz: claves de traducción (§6).
- Los menús extienden `MenuScreen`, se abren con `open_submenu()` y vuelven con `ui_cancel`/botón atrás; los controles de valor llevan meta `stick_value_control` para que roll navegue valores en vez de aceptar/cancelar.

## 3. Autoloads

El orden de registro en `project.godot` es el de `02` §5 y no se altera: `Global, Audio, Controls, GameSettings, Graphics, QuadSettings, DebugGeometry, UI, StickNavigation, SceneTransition, Events`. Este documento especifica los **siete primeros** (los de configuración) en ese mismo orden; `UI`, `StickNavigation` y `SceneTransition` se reutilizan tal cual (`01` §2.3) y `Events` es el bus de `02` §5.1.

### 3.1 `Global` (creado en WP-02, ampliado aquí)
| Miembro | Tipo | Descripción |
|---|---|---|
| `config_dir` | `String` = `"user://config"` | creado en `initialize()` |
| `log_path` | `String` = `"user://output.log"` | `log_error()` **anexa** (abrir con `READ_WRITE` + `seek_end`) |
| `startup_errors` | `Array[String]` | claves `ERR_*` acumuladas |
| `RoundState` | `enum {INTRO, BATTLE, VICTORY, DEFEAT}` | ver `11` |
| `selected_round` / `round_seed` | `String` / `int` | elegidos por el menú de rondas |
| `debug` | `bool` | `--debug` en `OS.get_cmdline_user_args()` |
| `initialize()` | | crea carpetas, una sola vez |
| `load_startup_settings()` | | llama en orden `GameSettings.load_game_settings()`, `Graphics.load_graphics_settings()`, `Audio.load_audio_settings()`, `QuadSettings.load_quad_settings()`, `Controls.load_input_map(true)`; una sola vez por proceso |
| `log_error(code: int, message: String)` | | línea `[fecha hora] code message` |
| `show_error_popup(error_key: String)` | | `UI.play("error")` + `await UI.alert(error_key)` |

### 3.2 `Audio`
- Buses (en `default_bus_layout.tres`): `Master` → `Motors`, `Weapons`, `Enemies`, `City`, `UI`, `Music`.
- `Audio.cfg [audio]`: `master_volume`, `motors_volume`, `weapons_volume`, `enemies_volume`, `city_volume`, `ui_volume`, `music_volume` (float 0–1, default 0.8 salvo `master_volume` 1.0) y `muted` (bool).
- API: `load_audio_settings() -> String`, `save_audio_settings()`, `update_volumes()` (aplica `linear_to_db` con `AudioServer.set_bus_volume_db`, mute en Master), `set_volume(bus: StringName, linear: float)`, `get_volume(bus) -> float`; señal `audio_settings_updated`.

### 3.3 `Controls`
Responsable de: dispositivo activo, calibración de los cuatro ejes de vuelo, bindings de acciones, reconstrucción del `InputMap`.

`InputMap.cfg`:
- `[controls]`: `active_controller_guid`, `active_controller_name`, `default_controller_guid`.
- `[controls_<GUID>]`: por eje de vuelo (`throttle`, `yaw`, `pitch`, `roll`): `<eje>_axis` (índice), `<eje>_inverted` (bool), `<eje>_min`, `<eje>_center`, `<eje>_max` (floats de calibración); por acción bindable: `<acción>_type` (`"button"` \| `"axis"`), `<acción>_button`, `<acción>_axis`, `<acción>_min`, `<acción>_max`.

Acciones bindables (`create_action_list()` → `Array[ControllerAction]`; `ControllerAction` es RefCounted con `action_name`, `label_key`, `type`, `button`, `axis`, `axis_min`, `axis_max`, `bound`): `arm` (`CTRL_ACTION_ARM_HOLD`), `toggle_arm`, `respawn`, `cycle_flight_modes`, `mode_horizon`, `mode_turtle`, `fire`, `fire_alt`, `lock_target`, `cycle_target`, `objective_next`, `objective_skip`, `change_camera`. `pause_menu` queda fijo (Start / Esc).

API: `load_input_map(update_controller := false) -> String` (detecta joypads, elige el activo por GUID o el primero, reconstruye el `InputMap`: ejes de vuelo como `InputEventJoypadMotion` con signo según inversión y acciones según binding), `get_flight_input() -> Dictionary` (`{throttle, roll, pitch, yaw}` en `[−1, 1]` leyendo `Input.get_joy_axis` crudo y aplicando mín/centro/máx, inversión y zona muerta 0.02; `null` si no hay joypad), `save_binding(action, event: InputEvent)`, `save_axis_binding(action, axis, lo, hi)`, `clear_binding(action)`, `save_axis_calibration(axis_name, index, lo, center, hi, inverted)`, `get_axis_calibration(axis_name) -> Dictionary`, `update_active_device(device: int)`, `set_default_device(guid)`, `reset_controller_bindings()`, `get_joypad_guid_list() -> Array[String]`, `restore_keyboard_shortcuts()` (M ciclo de modos, Espacio toggle arm, Retroceso respawn, clic izquierdo fire, clic derecho fire_alt, Shift lock, Tab cycle_target, Esc pausa: solo para depuración). Señales: `active_device_changed(guid)`, `bindings_updated`.

Reglas: el `InputMap` conserva siempre las acciones de vuelo mapeadas al dispositivo activo (las necesita `StickNavigation`); la calibración fina la aplica `get_flight_input()`. Mientras un popup captura entrada, `StickNavigation.suspended = true`.

### 3.4 `GameSettings`
`GameSettings.cfg`:
| Sección | Clave | Tipo / rango | Default |
|---|---|---|---|
| `[game]` | `language` | `"es"` \| `"en"` | idioma del SO si es es/en, si no `"es"` |
| | `nav_scheme` | 0 BETAFLIGHT \| 1 YAW_SELECT | 0 |
| | `aim_assist` | 0 off \| 1 sutil \| 2 asistido | 1 |
| | `shake_intensity` | 0–1 | 1.0 |
| | `telegraph_hints` | bool (avisos de ataque en HUD) | true |
| `[hud_config]` | `fps` | 5–60 | 10 |
| | `horizon_mode` | `"camera"` \| `"attitude"` | `"camera"` |
| | `crosshair, horizon, ladder, heading, speed, altitude, side_tapes, flight_mode, rec, sticks, rpm` | bool | preset Standard |
| `[objectives]` | `completed`, `last` | int (máscara), int | 0, 0 |
| `[rounds]` | `best_score_<id>`, `best_time_<id>` | int, float | ausentes |

`hud_config` tiene **13 claves**: `fps`, `horizon_mode` y los **11 bools** de la sección. Se corresponden una a una con 11 de las 12 entradas del `enum Component` de `12` §2.4; la entrada restante, `STATUS`, **no tiene bool** porque los mensajes de armado son siempre visibles. Por eso el menú de HUD muestra 11 `CheckButton`, no 12.

Presets de HUD: **Minimal** (crosshair, horizon, flight_mode), **Standard** (+ heading, speed, altitude, side_tapes, sticks), **Full** (todo), **Custom** (cualquier cambio manual).

API: `load_game_settings() -> String`, `save_game_settings()`, `set_language(lang)` (aplica `TranslationServer.set_locale` y guarda), `get_nav_scheme()/set_nav_scheme()`, `load_hud_config()`, `save_hud_config()`, `apply_hud_preset(name: String)`, `get_hud_preset_name() -> String`, `record_score(id, score) -> bool` (true si es récord), `get_best_score(id) -> int`, `record_time(id, seconds) -> bool`, `get_best_time(id) -> float`, `is_round_unlocked(index) -> bool` (derivado del catálogo), `reset_round_progress()`, `mark_objective_completed(i)`, `is_objective_completed(i)`. Señales: `game_settings_updated`, `hud_config_updated`, `round_progress_updated`.

### 3.5 `Graphics`
Enums: `WindowMode {FULLSCREEN, WINDOW, BORDERLESS}`, `Msaa {OFF, X2, X4, X8}`, `Shadows {VERY_LOW, LOW, MEDIUM, HIGH, ULTRA}`, `FisheyeMode {OFF, FULL, FAST}`, `FisheyeResolution {P2160, P1440, P1080, P720, P480, P240}`, `FisheyeMsaa {OFF, X2, X4, X8, SAME_AS_GAME}`, `VSync {OFF, ON, ADAPTIVE}`, `Quality {LOW, MEDIUM, HIGH, ULTRA, CUSTOM}`, `Gi {OFF, SDFGI}`.

`Graphics.cfg [graphics]`: `window_mode`, `resolution_scale` (1.0 \| 0.75 \| 0.5), `vsync`, `max_fps` (0 \| 30 \| 60 \| 120 \| 144 \| 240), `quality`, `msaa`, `shadows`, `gi`, `volumetric_fog` (bool), `ssao` (bool), `fisheye_mode`, `fisheye_resolution`, `fisheye_msaa`.

Presets (`QUALITY_PRESETS`):
| Preset | msaa | shadows | gi | fog | ssao | fisheye | fisheye_res |
|---|---|---|---|---|---|---|---|
| LOW | OFF | LOW | OFF | off | off | FAST | P480 |
| MEDIUM | X2 | MEDIUM | OFF | on | off | FAST | P720 |
| HIGH | X4 | HIGH | SDFGI | on | on | FAST | P1080 |
| ULTRA | X8 | ULTRA | SDFGI | on | on | FULL | P1080 |

Default al primer arranque: HIGH, fullscreen, vsync ON, max_fps 0. Sombras → tamaño de atlas direccional `2048/4096/8192/8192/16384` y `directional_soft_shadow_filter_quality` `HARD/SOFT_LOW/SOFT_MEDIUM/SOFT_HIGH/SOFT_ULTRA`.

API: `load_graphics_settings() -> String`, `save_graphics_settings()`, `apply_all()`, `update_window_mode()`, `update_resolution_scale()` (`get_viewport().scaling_3d_scale`), `update_vsync()`, `update_max_fps()`, `update_msaa()`, `update_shadows()`, `update_fisheye()`, `apply_quality_preset(q)`, `apply_environment_quality(env: Environment)` (SDFGI, niebla, SSAO según settings; la llama el `WorldEnvironment` del nivel), `is_compatibility_renderer() -> bool`. Señales: `graphics_settings_updated`, `fisheye_changed`, `environment_quality_changed`.

### 3.6 `QuadSettings`
`Quad.cfg`: `[quad] angle` (−20..80, 25), `dry_weight` (0.1–1.0, 0.52), `battery_weight` (0.1–0.5, 0.18), `fov` (90–170, 150); `[rates] curve` (0–4, 0), `roll_rc_rate`, `roll_rate`, `roll_expo`, `pitch_*`, `yaw_*` (unidades de `03` §3.6; defaults 7 / 67 / 54).
API: `load_quad_settings() -> String`, `save_quad_settings()`, `control_profile: ControlProfile` (reconstruido al cargar y al guardar), `reset_quad()`, `reset_rates()`; señal `settings_updated`.

### 3.7 `DebugGeometry`
Dibujo inmediato para depuración: `draw_line(a, b, color)`, `draw_arrow(origin, dir, color)`, `draw_cube(center, size, color)`, `draw_sphere(center, radius, color)`, `draw_text(pos, text)` (Label3D pooleado). Acumula en un `ImmediateMesh` que se vacía cada frame; activo solo con `Global.debug`. Sin dependencias.

## 4. Menús

Todos son escenas `Control` que extienden `MenuScreen`; título con variación `TitleLabel`, contenido en `Card`, botón atrás con meta `ui_back`.

### 4.1 Hub de opciones — `gui/options_menu/options_menu.tscn`
Botones `OPT_GAME`, `OPT_GRAPHICS`, `OPT_AUDIO`, `OPT_CONTROLS` (`MenuItemButton`) → `open_submenu()` de cada pantalla; atrás.

### 4.2 Juego y HUD — `gui/options_menu/game_settings_menu.tscn`
`TabContainer` con dos pestañas:
- **Gameplay**: idioma (`OptionButton` "Español"/"English"), esquema de navegación por sticks (`GAME_STICK_NAVIGATION_BETAFLIGHT` / `_YAW`), asistencia de puntería (`GAME_AIM_OFF/SUBTLE/ASSISTED`), intensidad de sacudida (`HSlider` 0–100 %), avisos de ataque (`CheckButton`). Cada cambio guarda de inmediato.
- **HUD** (`gui/options_menu/hud_config.tscn`): preset (`OptionButton` Minimal/Standard/Full/Custom, deshabilitado si Custom), modo de horizonte, frecuencia de números (`HSlider` 5–60 Hz, default 10), **11** `CheckButton` (uno por cada componente configurable; `STATUS` no tiene interruptor), y a la derecha un `FlightHUD` real en `preview_mode` dentro de un panel `HudPreviewPanel` que simula vuelo (oscilación suave de actitud, velocidad y altura). Cada cambio emite `hud_config_updated` y el preview se actualiza.

### 4.3 Gráficos — `gui/options_menu/graphics_menu.tscn`
Secciones: **Pantalla** (modo de ventana, escala de resolución, VSync, FPS máximos), **Calidad** (preset, MSAA, sombras, iluminación global, niebla volumétrica, SSAO), **FPV** (ojo de pez, resolución del ojo de pez, MSAA del ojo de pez con opción "igual al juego"). Aplicación inmediata; cualquier cambio manual pone el preset en Custom. Aviso `GFX_RESTART_NOTE` si algún cambio requiere reinicio (ninguno en Forward+).

### 4.4 Audio — `gui/options_menu/audio_menu.tscn`
Siete `HSlider` 0–100 % (`AUD_MASTER`, `AUD_MOTORS`, `AUD_WEAPONS`, `AUD_ENEMIES`, `AUD_CITY`, `AUD_UI`, `AUD_MUSIC`) con valor numérico, y `CheckButton` `AUD_MUTE`. Cada cambio aplica y guarda; al mover un slider suena un `tick` de UI.

### 4.5 Controles — `gui/options_menu/controls_menu/controls_menu.tscn` (WP-10)
- **Dispositivo**: `OptionButton` con los joypads conectados (nombre + GUID abreviado), autodetección: al mover cualquier eje > 0.5 de un joypad no activo, se propone como activo; `CheckButton` "usar por defecto".
- **Vista en vivo**: 8 barras de eje (`GUIControllerAxis`: `TextureProgressBar` −1..1 tintada) y rejilla de 16 botones (`GUIControllerButton`), leídas en `_process` con `Input.get_joy_axis` / `Input.is_joy_button_pressed`.
- **Ejes de vuelo**: 4 filas (acelerador, yaw, pitch, roll) con eje asignado, inversión (`CheckButton`) y estado de calibración; botón **Calibrar** abre 4.6.
- **Acciones**: una fila `GUIControllerBinding` por acción bindable (etiqueta, binding actual como texto `CTRL_BOUND_BUTTON %d` / `CTRL_BOUND_AXIS %d [%.2f, %.2f]` / `CTRL_UNBOUND`); al activar abre `BindingPopup` (modal): botones **Escuchar** (captura el siguiente `InputEventJoypadButton`, o un `InputEventJoypadMotion` cuyo valor supere 0.5 → binding de eje con banda editable mediante `GUIControllerAxisRange`, control de dos manijas con meta `stick_value_control`), **Borrar**, **Cancelar**, **Confirmar**. Los eventos de joypad se leen en `_input` para que el foco no los consuma. Mientras escucha, `StickNavigation.suspended = true`.
- **Reset**: `UI.confirm("CTRL_RESET_CONFIRM")` → `Controls.reset_controller_bindings()`.

### 4.6 Calibración — `gui/options_menu/controls_menu/calibration_menu.tscn` (WP-10)
Asistente de 14 pasos con texto `CAL_STEP_*`, barra de progreso y botón "Siguiente"/"Omitir":
1. Mover ambos sticks a las cuatro esquinas: se detectan los cuatro ejes con mayor recorrido.
2. Soltar los sticks: se registra el centro de cada eje.
3–5. Acelerador arriba, abajo, centro. 6–8. Yaw derecha, izquierda, centro. 9–11. Pitch adelante, atrás, centro. 12–14. Roll derecha, izquierda, centro.
Cada paso confirma al detectar un valor estable (> 0.5 de recorrido durante 0.4 s). Al terminar guarda `<eje>_axis/_min/_center/_max/_inverted` con `Controls.save_axis_calibration()` y reconstruye el `InputMap`. Se puede cancelar sin guardar.

### 4.7 Hangar (quad) — `gui/quad_settings_menu.tscn` (WP-11)
- **Cuadro**: ángulo de cámara (−20..80°), peso seco, peso de batería, FOV FPV: cada uno `HSlider` + `SpinBox` compartiendo `Range` (`slider.share(spin)`), con `tooltip_text` `QUAD_HELP_*`.
- **Rates**: `OptionButton` de curva (ACTUAL/BETAFLIGHT/RACEFLIGHT/KISS/QUICKRATES); por eje (pitch, roll, yaw) tres pares slider+spinbox (`rc_rate`, `rate`, `expo`) con rangos según la curva (ACTUAL: rc_rate 1–100, rate 0–180, expo 0–100; otras: rc_rate 1–255, rate 0–100, expo 0–100); `RateGraph` (Control con `_draw()`): eje x deflexión −1..1, eje y deg/s, tres curvas (`UIPalette.GRAPH_PITCH/ROLL/YAW`), rejilla y etiqueta con la tasa máxima de cada eje; se redibuja al cambiar cualquier valor.
- Botones `QUAD_RESET_QUAD` y `QUAD_RESET_RATES` (con confirmación). Se guarda al salir (`_before_back()`), emitiendo `settings_updated`.

### 4.8 Ayuda — `gui/help_page.tscn`
`RichTextLabel` con `HELP_INTRO`, `HELP_FLIGHT`, `HELP_COMBAT`, `HELP_ENERGY`, `HELP_CITY`, `HELP_HUD`, `HELP_CONTROLS`, `HELP_CREDITS` (texto de `CREDITS.md`) y un botón que muestra `Engine.get_license_text()` en un `ScrollContainer`. Reconstrucción en `NOTIFICATION_TRANSLATION_CHANGED`.

### 4.9 Pausa — `gui/pause_menu.tscn`
`process_mode = PROCESS_MODE_WHEN_PAUSED`. Botones `MENU_RESUME`, `MENU_HANGAR`, `MENU_OPTIONS`, `MENU_HELP`, `MENU_MAIN` (con `UI.confirm("MENU_QUIT_ROUND_CONFIRM")`). Señales `resumed`, `menu`. Contrato del nivel host: `add_pause_menu()` (instancia, `get_tree().paused = true`, `StickNavigation.suspended = false`), `_on_resume()` (espera a que `ui_accept`/`pause_menu` se suelten antes de despausar: `_resume_input_held()`), `_on_menu()` → `SceneTransition.change_scene("res://gui/main_menu.tscn")`.

### 4.10 Menú principal — `gui/main_menu.tscn`
Botones `MENU_PLAY` (→ `rounds_menu`), `MENU_HANGAR` (→ hangar), `MENU_OPTIONS`, `MENU_HELP`, `MENU_QUIT` (`UI.confirm("MENU_QUIT_CONFIRM")` → `get_tree().quit()`). En `_ready`: `Global.load_startup_settings()` (por si se arranca sin boot) y muestra `Global.startup_errors` con `UI.alert()`. Fondo: en P0 un `ColorRect` con la paleta; en WP-25, backdrop 3D (`13`). Versión del juego en una esquina (`ProjectSettings.get_setting("application/config/version")`).

## 5. Navegación por sticks y foco
`StickNavigation` convierte pitch en `ui_up/ui_down` (con repetición) y roll en `ui_accept/ui_cancel` (o `ui_left/ui_right` sobre controles con meta `stick_value_control` o de tipo `Range`, `OptionButton`, `TabBar`, `CheckButton`, `CheckBox`); el acelerador nunca navega. Todo menú fija el foco inicial en `_ready()` y lo restaura al volver de un submenú. `UI` agrega sonidos y el pulso de foco a cada botón automáticamente.

## 6. Claves de traducción (extracto; el CSV completo se produce en los WPs)
| Clave | es | en |
|---|---|---|
| `OPT_GAME` / `OPT_GRAPHICS` / `OPT_AUDIO` / `OPT_CONTROLS` | Juego / Gráficos / Audio / Controles | Game / Graphics / Audio / Controls |
| `GAME_AIM_OFF` / `GAME_AIM_SUBTLE` / `GAME_AIM_ASSISTED` | Sin asistencia / Sutil / Asistida | Off / Subtle / Assisted |
| `GAME_SHAKE` / `GAME_TELEGRAPH_HINTS` | Sacudida de cámara / Avisos de ataque | Camera shake / Attack warnings |
| `GFX_GI` / `GFX_FOG` / `GFX_SSAO` | Iluminación global / Niebla volumétrica / Oclusión ambiental | Global illumination / Volumetric fog / Ambient occlusion |
| `AUD_WEAPONS` / `AUD_ENEMIES` / `AUD_CITY` / `AUD_MUSIC` | Armas / Enemigos / Ciudad / Música | Weapons / Enemies / City / Music |
| `CTRL_ACTION_FIRE` / `CTRL_ACTION_FIRE_ALT` / `CTRL_ACTION_LOCK` / `CTRL_ACTION_CYCLE_TARGET` | Disparar / Disparo secundario / Fijar objetivo / Cambiar objetivo | Fire / Alt fire / Lock target / Cycle target |
| `CTRL_BOUND_BUTTON` / `CTRL_BOUND_AXIS` / `CTRL_UNBOUND` | Botón %d / Eje %d [%.2f, %.2f] / Sin asignar | Button %d / Axis %d [%.2f, %.2f] / Unbound |
| `CAL_STEP_CORNERS` … `CAL_STEP_ROLL_CENTER` | (14 textos del asistente) | |
| `QUAD_HELP_ANGLE` … | (tooltips) | |
| `MENU_PLAY` / `MENU_HANGAR` / `MENU_RESUME` / `MENU_MAIN` / `MENU_QUIT_CONFIRM` | Jugar / Hangar / Continuar / Menú principal / ¿Salir del juego? | Play / Hangar / Resume / Main menu / Quit the game? |
| `ERR_CONFIG_GAME` / `ERR_CONFIG_GRAPHICS` / `ERR_CONFIG_AUDIO` / `ERR_CONFIG_QUAD` / `ERR_CONFIG_INPUT` | No se pudo leer la configuración de … | Could not read the … settings |
| `ERR_ARM_THROTTLE_HIGH` / `ERR_ARM_RECOVERING` / `ERR_ARM_NO_ENERGY` | Bajá el acelerador para armar / Recuperando… / Sin energía | Lower the throttle to arm / Recovering… / No energy |

## 7. Interfaz pública (resumen)
Ver firmas en §3. Consumidores: `Drone`/`DroneRig` (`QuadSettings.settings_updated`, `Controls.get_flight_input()`), `FlightHUD` (`GameSettings.hud_config`, `hud_config_updated`), `WorldEnvironment` del nivel (`Graphics.apply_environment_quality`, `environment_quality_changed`), `FPVCamera` (`Graphics.fisheye_*`, `fisheye_changed`), `WeaponMount` (`GameSettings.aim_assist`), `CameraRig` (`GameSettings.shake_intensity`), `RoundManager` (`GameSettings.record_score/record_time`, `Global.selected_round/round_seed`).

## 8. Parámetros y valores iniciales
Consolidados en las tablas de §3. Rangos de sliders: volumen 0–100 %, frecuencia HUD 5–60 Hz, sacudida 0–100 %, ángulo −20..80°, pesos 0.10–1.00 / 0.10–0.50 kg (paso 0.01), FOV 90–170°.

## 9. Criterios de aceptación y checks headless
- `tools/settings_check.tscn` (WP-03): para cada autoload, guardar valores no default → recargar → iguales; archivo corrupto → clave `ERR_CONFIG_*` y defaults; `Global.startup_errors` acumula; `Controls.load_input_map()` reconstruye las 8 acciones de vuelo y las acciones bindables; `get_flight_input()` aplica mín/centro/máx e inversión sobre valores inyectados; al terminar restaura los `.cfg` originales del jugador.
- `tools/controls_check.tscn` (WP-10): con joypad simulado (`Input.parse_input_event` de `InputEventJoypadButton`/`Motion`): asignar botón, asignar banda de eje, calibrar los 14 pasos con valores sintéticos, inversión; todo persiste y se relee; `StickNavigation.suspended` vuelve a `false` al cerrar el popup.
- `tools/ui_smoke_test.tscn` (WP-09 y WP-11): abre cada menú (principal, rondas, hangar, opciones, juego/HUD, gráficos, audio, controles, calibración, ayuda, pausa), verifica foco inicial, atrás, que cada control cambia y persiste un valor, que ninguna clave de traducción queda sin traducir en es y en (`TranslationServer.get_translation_object(locale).get_message(key) != ""`), sin `push_error`.
- Comando: `"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/<x>_check.tscn`.

## 10. Riesgos y decisiones abiertas
- La calibración vive fuera del `InputMap` (Godot no reescala ejes); `StickNavigation` solo necesita umbrales, así que el `InputMap` puede quedar sin calibración fina.
- Un joypad desconectado en mitad de la partida: `Controls` emite `active_device_changed("")`, el dron desarma y el HUD muestra `HUD_NO_CONTROLLER`.
- Los presets de calidad tocan el `Environment` del nivel; el menú de gráficos debe probarse tanto desde el menú principal como desde la pausa.

## 11. Referencias cruzadas
`02-configuracion-del-proyecto.md` (acciones y autoloads), `03-especificacion-nucleo-de-vuelo.md` (perfil de control, radio), `11-rondas-y-objetivos.md` (menú de rondas, persistencia), `12-interfaz-y-hud.md` (preview del HUD, pausa), `13-identidad-visual-y-audio.md` (paleta, backdrop, buses), `15-verificacion-y-ci.md`.
