# 01 — Sala limpia y reutilización

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-02 y todos los WPs de implementación · Depende de: `00-plan-maestro.md`, `16-licencias-y-atribucion.md`

## 1. Objetivo y alcance

El simulador `drone-simulator` es un fork del proyecto `GodotDrone` (licencia GPL-3). Copiar su código de vuelo, sus menús o su HUD haría de Drone Survivor una obra derivada bajo GPL-3. El usuario decidió **no heredar esa licencia**, por lo que este proyecto se construye en **sala limpia**:

- Se reutilizan **solo** los archivos que el usuario creó después del fork y que no tienen contraparte en el proyecto original (son de su autoría y puede licenciarlos como quiera).
- Todo lo demás se **reimplementa** a partir de especificaciones de comportamiento (`03` y `04`), sin leer el código original.

Este documento fija la lista cerrada de archivos reutilizables, la lista de lo que se reimplementa, el protocolo de trabajo y la plantilla de especificación. No cubre las licencias de assets de terceros (ver `16`).

## 2. Clasificación de propiedad intelectual

Método: comparación con git entre el punto de fork (commit del proyecto original "Port project to Godot 4.6") y la rama `master` del simulador. Los archivos **agregados** después del fork y sin equivalente en el original son propios; los **modificados** o **intactos** respecto al original son derivados.

### 2.1 Propios → reutilizables (copiar tal cual, con cabecera de copyright del autor)

| Grupo | Archivos en el simulador | Destino en este repo | Notas |
|---|---|---|---|
| Autoloads de UI | `autoloads/ui.gd`, `autoloads/stick_navigation.gd`, `autoloads/scene_transition.gd` | `autoloads/` | Mismos nombres de autoload (`UI`, `StickNavigation`, `SceneTransition`) |
| Tema | `gui/theme/ui_palette.gd`, `gui/theme/theme_builder.gd`, `gui/theme/main_theme.tres` | `gui/theme/` | La paleta se reemplaza en WP-25; el generador se conserva |
| Base de menús | `gui/menu_screen.gd`, `gui/choice_menu.gd`, `gui/components/confirm_overlay.gd`, `gui/components/control_hints.gd`, `gui/components/loading_spinner.gd`, `gui/components/menu_hero.gd` | `gui/`, `gui/components/` | `menu_hero.gd` referencia una escena de preview del dron que no existe aquí: se adapta al dron nuevo o se deja sin héroe hasta WP-25 |
| Boot | `gui/boot/boot_sequence.gd`, `gui/boot/boot_sequence.tscn` | `gui/boot/` | Fuente `Withheld Data.otf` pendiente de licencia: sustituir por una fuente OFL si no se confirma |
| Menú de lista | `gui/challenges_menu.gd`, `gui/challenges_menu.tscn` | `gui/rounds_menu.gd/.tscn` | Se renombra y se apunta a `RoundCatalog` |
| HUD procedural | `hud/hud_draw.gd`, `hud/hud_horizon.gd`, `hud/hud_side_tapes.gd`, `hud/hud_compass_tape.gd`, `hud/hud_readouts.gd`, `hud/hud_crosshair.gd`, `hud/hud_mode_badge.gd`, `hud/hud_rec_indicator.gd`, `hud/hud_gate_marker.gd` | `hud/` | Dependen de `HUDDraw`, `UIPalette` y de `camera.project_direction()`; el tipo `FPVCamera` se declara de nuevo en WP-06 |
| Objetivos | `tutorial/tutorial_sequencer.gd`, `tutorial/tutorial_step.gd`, `tutorial/tutorial_hud.gd`, `tutorial/tutorial_stick_hint.gd`, `tutorial/tutorial_zone.gd`, `tutorial/steps/*.gd` | `rounds/objectives/objective_sequencer.gd`, `objective.gd`, `objective_hud.gd`, `objective_stick_hint.gd`, `objective_zone.gd` | Renombrar clases (`TutorialSequencer` → `ObjectiveSequencer`, `TutorialStep` → `Objective`); reescribir las ~40 líneas ligadas al dron contra las clases nuevas (`ObjectiveContext`) |
| Catálogos y niveles | `challenges/challenge_catalog.gd`, `sceneries/challenge_level.gd`, `sceneries/challenge_level.tscn`, `sceneries/tutorial_level.gd`, `sceneries/tutorial_level.tscn`, `sceneries/freestyle_level.tscn`, `sceneries/skies/sky_catalog.gd` | referencia | Se usan como **referencia de patrón** para `RoundCatalog`/`RoundManager`; no se copian tal cual porque referencian el nivel base derivado. **No** copiar `sceneries/skies/sky.gdshader` ni `clear_day_sky.tres` (licencia sin identificar) |
| Herramientas | `tools/build_theme.gd`, `tools/generate_ui_sounds.gd`, `tools/bake_sky_noise.gd`, `tools/ui_smoke_test.gd/.tscn`, `tools/boot_check.gd/.tscn`, `tools/loading_check.gd/.tscn`, `tools/hud_projection_check.gd/.tscn`, `tools/render_parity_check.gd/.tscn`, `tools/sky_check.gd/.tscn`, `tools/overlay_probe.gd`, `tools/track_check.*`, `tools/challenge_check.*`, `tools/tutorial_check.*` | `tools/` | Los checks se adaptan a las escenas nuevas; los de pistas/desafíos/tutorial sirven solo como patrón |
| Datos | `localization/translations.csv`, `default_bus_layout.tres`, `export_presets.cfg` | `localization/`, raíz | CSV podado de prefijos `CHAL_`, `TRACK_`, `SKY_`, `EDIT_`, `RACE_`; buses ampliados |
| Audio de UI | `Assets/Audio/UI/back.wav`, `click.wav`, `error.wav`, `hover.wav`, `tick.wav` (sintetizados por herramienta propia); `boot_key.ogg`, `boot_enter.ogg` (CC BY 4.0, atribuir) | `assets/audio/ui/` | |
| Fuentes | `gui/RecursiveSansLnrSt-Med.otf`, `gui/RecursiveSansLnrSt-Bold.otf`, `hud/RecursiveMonoLnrSt-Regular.otf` | `gui/theme/fonts/` | Licencia OFL del autor de la fuente (no del simulador); atribuir en `CREDITS.md` |
| Documentación | `docs/*.md`, `ANALISIS_SIMULADOR_DRONES.md` | referencia | Convenciones y método de medición de rendimiento |

### 2.2 Derivados → reimplementar (ni copiar ni leer durante la implementación)

| Grupo | Archivos del simulador | Spec que los reemplaza |
|---|---|---|
| Núcleo de vuelo | todo `drone/` (cuerpo rígido, controlador, PID, modos, perfil de control, radio, motores, hélices, cámara FPV y sus shaders, LED, frame, batería, ghost, escenas del dron) | `03-especificacion-nucleo-de-vuelo.md` |
| Autoloads de configuración | `autoloads/global.gd`, `audio.gd`, `controls.gd`, `game_settings.gd`, `graphics.gd`, `quad_settings.gd`, `debug_geometry.gd` | `04` (§3) |
| Menús | `gui/main_menu.*`, `gui/pause_menu.*`, `gui/help_page.*`, `gui/quad_settings_menu.*`, `gui/rate_graph.gd`, `gui/options_menu/**` (hub, audio, gráficos, juego, HUD config, controles, calibración, widgets de binding), `gui/timer_theme.tres`, `gui/countdown_theme.tres` | `04` (§4–§6), `12` |
| HUD | `hud/hud.gd`, `hud/hud.tscn`, `hud/hud_status.gd`, `hud/hud_stick_input.*`, `hud/hud_rpm.*`, `hud/hud_theme.tres` | `12` |
| Mundo | `sceneries/level.gd`, `sceneries/level1.tscn`, `sceneries/cameras/*`, `tracks/**`, `asset_import/*` | `11`, `05`, `10` |
| Assets | `Assets/Drones/**` (modelos del dron), `Assets/Audio/SFX/Propellers/*` (sonidos de motor), `Assets/GUI/**`, `Assets/HUD/*`, `Assets/grid_*` | modelo voxel propio (`05`), audio sintetizado (`03`), UI procedural (`12`) |
| Configuración | `project.godot` | `02` |

### 2.3 Firmas reales de las piezas reutilizadas

Los archivos de 2.1 se copian **tal cual**, así que su interfaz ya existe y **no se negocia**: cualquier documento que asuma otra firma está equivocado y se corrige. Esta es la lista verificada contra los archivos copiados; es la referencia de `04`, `11` y `12`.

```gdscript
# gui/choice_menu.gd
func setup(title: String, subtitle: String, entries: Array[Dictionary], back_id := "") -> void
signal chosen(id: String)          # NO existe `option_chosen`

# gui/menu_screen.gd
signal back
enum Backdrop {AUTO, OPAQUE, SCRIM, NONE}
@export var initial_focus: Control
func open_submenu(packed: PackedScene, hide_node: CanvasItem, parent: Node = self) -> void
func request_back() -> void
func _before_back() -> void                       # gancho para guardar al salir
func bind_back_button(button: BaseButton) -> void
func grab_initial_focus(force := false) -> void

# autoloads/ui.gd
enum InputKind {MOUSE, KEYBOARD, GAMEPAD, STICKS}
func confirm(text: String, ok_text := "UI_CONFIRM", cancel_text := "UI_CANCEL", ...) -> bool   # asíncrono: se usa con await
func alert(text: String, ok_text := "UI_OK") -> void
func play(sound: String) -> void
func sticks_allowed() -> bool
func has_modal() -> bool
func set_input_kind(kind: InputKind) -> void

# autoloads/scene_transition.gd
func change_scene(path: String, show_loading := false) -> void
func is_busy() -> bool
const TIPS: Array[String]                         # claves de consejo de la pantalla de carga

# autoloads/stick_navigation.gd
enum Scheme {BETAFLIGHT, YAW_SELECT}
var scheme: Scheme
var suspended: bool
var assume_joypad: bool
func any_axis_deflected() -> bool
```

Nota sobre `SceneTransition.TIPS`: las claves `UI_TIP_*` que trae el archivo copiado son del simulador de vuelo y **no aplican a este juego**. En WP-02 se reemplazan por las seis claves propias `UI_TIP_ARM`, `UI_TIP_STICKS`, `UI_TIP_WEAK_POINTS`, `UI_TIP_BATTERIES`, `UI_TIP_CITY` y `UI_TIP_TELEGRAPH` (textos en `12` §6).

## 3. Protocolo de sala limpia

1. **Roles separados**. El orquestador (que conoce el código original) escribe especificaciones de comportamiento. Los agentes desarrolladores implementan **solo** a partir de las especificaciones y de fuentes públicas. Nunca ven el código original.
2. **Las specs describen comportamiento, no código**: entradas y salidas, fórmulas con su fuente pública (papers, documentación de Betaflight, manuales de Godot), parámetros físicos públicos, interfaces que el resto del juego consume y criterios de aceptación medibles. No incluyen fragmentos del código original, nombres internos de sus funciones ni su estructura de archivos.
3. **Barrera técnica**. El repo lleva `.claude/settings.json` con reglas `permissions.deny` para `Read`, `Grep` y `Glob` sobre `C:/Users/Mauri/Godot/Proyectos/drone-simulator/**`. Cada brief repite la prohibición. La copia de los archivos propios (2.1) se hace una sola vez, en WP-02, con `Copy-Item` y la lista cerrada de este documento.
4. **Revisión**. El revisor de cada WP verifica que ningún archivo nuevo referencie rutas del simulador, que no haya comentarios que citen su código y que la implementación siga la spec.
5. **Paridad por medición, no por comparación**. La "sensación" del dron se valida con el banco de pruebas de `03` (empuje de hover, respuesta a escalón, velocidad máxima), nunca comparando código.
6. **Cabeceras**. Cada archivo propio copiado lleva en su primera línea `## Copyright (c) 2026 <nombre del autor>. Todos los derechos reservados.` (o la licencia que el usuario elija); cada archivo nuevo lleva la misma cabecera.
7. **Registro**. Este documento mantiene la tabla 2.1 como lista cerrada; agregar un archivo del simulador requiere volver a verificar su origen con git antes de copiarlo.

## 4. Plantilla de especificación de comportamiento

```
### <Sistema>
Objetivo: <qué debe lograr, en una frase>.
Comportamiento observable:
  - Entradas: <señales, acciones, parámetros>.
  - Salidas: <fuerzas, señales, valores>.
  - Reglas: <condiciones, límites, transiciones de estado>.
Fórmulas y fuentes públicas: <ecuación> (fuente: <paper, wiki, manual>).
Parámetros: tabla nombre / unidad / valor inicial / rango.
Interfaz: clases, señales y métodos que consumen otros sistemas (firma GDScript).
Aceptación: check headless, métricas con tolerancia.
Libertades del implementador: <qué puede decidir por su cuenta>.
```

## 5. Lista de copia (WP-02)

Comando de referencia (PowerShell, desde la raíz del repo destino; `$S` = raíz del simulador):

```
$S = "C:\Users\Mauri\Godot\Proyectos\drone-simulator"
Copy-Item "$S\autoloads\ui.gd","$S\autoloads\stick_navigation.gd","$S\autoloads\scene_transition.gd" godot\autoloads\
Copy-Item "$S\gui\theme\ui_palette.gd","$S\gui\theme\theme_builder.gd","$S\gui\theme\main_theme.tres" godot\gui\theme\
Copy-Item "$S\gui\menu_screen.gd","$S\gui\choice_menu.gd" godot\gui\
Copy-Item "$S\gui\components\*.gd" godot\gui\components\
Copy-Item "$S\gui\boot\*" godot\gui\boot\ -Recurse
Copy-Item "$S\gui\challenges_menu.gd" godot\gui\rounds_menu.gd
Copy-Item "$S\gui\challenges_menu.tscn" godot\gui\rounds_menu.tscn
Copy-Item "$S\hud\hud_draw.gd","$S\hud\hud_horizon.gd","$S\hud\hud_side_tapes.gd","$S\hud\hud_compass_tape.gd","$S\hud\hud_readouts.gd","$S\hud\hud_crosshair.gd","$S\hud\hud_mode_badge.gd","$S\hud\hud_rec_indicator.gd","$S\hud\hud_gate_marker.gd" godot\hud\
Copy-Item "$S\tutorial\tutorial_sequencer.gd" godot\rounds\objectives\objective_sequencer.gd
Copy-Item "$S\tutorial\tutorial_step.gd" godot\rounds\objectives\objective.gd
Copy-Item "$S\tutorial\tutorial_hud.gd" godot\rounds\objectives\objective_hud.gd
Copy-Item "$S\tutorial\tutorial_stick_hint.gd" godot\rounds\objectives\objective_stick_hint.gd
Copy-Item "$S\tutorial\tutorial_zone.gd" godot\rounds\objectives\objective_zone.gd
Copy-Item "$S\tools\build_theme.gd","$S\tools\generate_ui_sounds.gd","$S\tools\bake_sky_noise.gd","$S\tools\ui_smoke_test.gd","$S\tools\ui_smoke_test.tscn","$S\tools\boot_check.gd","$S\tools\boot_check.tscn","$S\tools\loading_check.gd","$S\tools\loading_check.tscn","$S\tools\hud_projection_check.gd","$S\tools\hud_projection_check.tscn","$S\tools\render_parity_check.gd","$S\tools\render_parity_check.tscn" godot\tools\
Copy-Item "$S\localization\translations.csv" godot\localization\
Copy-Item "$S\default_bus_layout.tres" godot\
Copy-Item "$S\Assets\Audio\UI\*" godot\assets\audio\ui\
Copy-Item "$S\gui\RecursiveSansLnrSt-Med.otf","$S\gui\RecursiveSansLnrSt-Bold.otf","$S\hud\RecursiveMonoLnrSt-Regular.otf" godot\gui\theme\fonts\
```

Después de copiar: agregar cabeceras de copyright, renombrar clases del framework de objetivos, corregir rutas `res://` (fuentes, escenas), podar el CSV y regenerar el tema con `tools/build_theme.gd`. Ningún otro archivo del simulador se copia.

## 6. Criterios de aceptación

- `grep -rn "drone-simulator" godot/` no devuelve nada fuera de `docs/`.
- Todos los archivos copiados figuran en la tabla 2.1 y llevan cabecera de copyright.
- El revisor de cada WP marca "sala limpia: OK" en su informe.

## 7. Riesgos y decisiones abiertas

- Los archivos propios que reemplazaron componentes del original (HUD procedural) fueron reescritos desde cero; si el usuario prefiere máxima cautela, se pueden reimplementar también (coste M).
- La fuente `Withheld Data.otf` del boot no tiene licencia documentada: sustituir por una fuente OFL salvo confirmación.
- Los parámetros físicos públicos de un cuadricóptero (masa, KV, hélice) no son obra protegida; los valores de sintonía se eligen de nuevo con el banco de pruebas.

## 8. Referencias cruzadas

`00-plan-maestro.md`, `02-configuracion-del-proyecto.md` (deny y estructura), `03-especificacion-nucleo-de-vuelo.md`, `04-especificacion-configuracion-y-menus.md`, `16-licencias-y-atribucion.md`.
