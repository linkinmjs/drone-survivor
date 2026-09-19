# 02 — Configuración del proyecto

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-01 · Depende de: `docs/00-plan-maestro.md`, `docs/01-sala-limpia-y-reutilizacion.md`

## 1. Objetivo y alcance
> Nota del checkpoint 2 (2026-09-19): defaults de gamepad corregidos tras la prueba del usuario: **L1 (botón 9) = `toggle_arm`**; `arm` (mantener) queda **sin botón por defecto** (es para un switch de radio, asignable en Opciones → Controles); L3 deja de usarse. La tabla de §4.3 queda superada en esas dos filas. Quien tenga un `InputMap.cfg` anterior debe usar «Restablecer» en Controles para tomar los defaults nuevos.

> Nota de WP-12b (2026-09-19): los GLB voxel se importan con `meshes/ensure_tangents=false` y `nodes/root_type`/`nodes/root_name` explícitos (ver `05` §1); el §7.1 de este doc queda superado en ese punto.

> Nota de WP-13 (2026-09-19): el `root_scale` real del pack VoxelCity es **5.0** (ufbx ya convierte unidades; a escala 1 `BuildingBlock_1` mide 2,50 m). Cualquier mención a 0.01 en este doc queda superada; ver `10-ciudad-destructible.md` §1.


> Nota de WP-01 (2026-09-19): `gdscript/warnings/exclude_addons` no existe en Godot 4.7; la sustituye `debug/gdscript/warnings/directory_rules`, cuyo valor por defecto ya excluye `res://addons`. No se declara ninguna clave para ese fin. Además, `PhysicsLayers` vive en `res://core/physics_layers.gd` (no en `tools/`, que está excluido del export) porque lo consume el gameplay.


Este documento es la especificación completa del **esqueleto** del proyecto: el archivo `project.godot`, las capas de física, las acciones de entrada, el orden de los autoloads, la estructura de carpetas, los presets de importación y de exportación, el workflow de integración continua y los archivos legales de la raíz.

**Incluye**: todo lo que WP-01 debe crear o reescribir para que el repositorio quede listo para recibir código.

**NO incluye**: la implementación de los autoloads (en WP-01 son *stubs*; ver `docs/04-especificacion-configuracion-y-menus.md`), el núcleo de vuelo (`docs/03-especificacion-nucleo-de-vuelo.md`), los menús, el HUD ni el contenido de los assets importados.

Estado de partida real del repositorio: `godot/project.godot` contiene solo `application`, `animation` y `rendering` con `gl_compatibility`; `godot/docs/` está vacío; `.github/workflows/deploy-to-itch.yml` apunta a Godot 4.4.1 con `relative_project_path: ./godot`; `godot/export_presets.cfg` tiene únicamente el preset `Web`. Todo eso se reemplaza.

**Regla de sala limpia**: el repositorio `drone-simulator` no se abre nunca. La sección 10.3 define el bloqueo técnico que lo impide.

---

## 2. `project.godot` completo

Formato INI, `config_version=5`. El bloque `[animation]` de la plantilla (`compatibility/default_parent_skeleton_in_mesh_instance_3d`) **se elimina**: es una bandera de compatibilidad con proyectos migrados y este proyecto nace en 4.7.

```ini
; Engine configuration file.
config_version=5

[application]

config/name="Drone Survivor"
config/description="FPS de dron de combate contra colosos que asedian una ciudad."
config/version="0.1.0"
run/main_scene="res://gui/boot/boot_sequence.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")
config/icon="res://icon.svg"
boot_splash/show_image=false
boot_splash/bg_color=Color(0, 0, 0, 1)

[autoload]

Global="*res://autoloads/global.gd"
Audio="*res://autoloads/audio.gd"
Controls="*res://autoloads/controls.gd"
GameSettings="*res://autoloads/game_settings.gd"
Graphics="*res://autoloads/graphics.gd"
QuadSettings="*res://autoloads/quad_settings.gd"
DebugGeometry="*res://autoloads/debug_geometry.gd"
UI="*res://autoloads/ui.gd"
StickNavigation="*res://autoloads/stick_navigation.gd"
SceneTransition="*res://autoloads/scene_transition.gd"
Events="*res://autoloads/events.gd"

[debug]

gdscript/warnings/untyped_declaration=1
gdscript/warnings/return_value_discarded=1
gdscript/warnings/unused_signal=1
gdscript/warnings/exclude_addons=true
settings/stdout/print_fps=false
file_logging/enable_file_logging=false

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/mode=3
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/vsync/vsync_mode=1

[gui]

theme/custom="res://gui/theme/main_theme.tres"
theme/default_font_antialiasing=1

[input]

; Ver sección 4. Cada acción se serializa con las plantillas de 4.1.

[internationalization]

locale/translations=PackedStringArray("res://localization/translations.es.translation", "res://localization/translations.en.translation")
locale/fallback="en"

[layer_names]

3d_physics/layer_1="world"
3d_physics/layer_2="drone"
3d_physics/layer_3="enemy_body"
3d_physics/layer_4="enemy_weak"
3d_physics/layer_5="projectile_player"
3d_physics/layer_6="projectile_enemy"
3d_physics/layer_7="pickup"
3d_physics/layer_8="city"
3d_physics/layer_9="debris"
3d_physics/layer_10="trigger"
3d_physics/layer_11="enemy_sensor"

[physics]

3d/physics_engine="Jolt Physics"
3d/default_gravity=9.81
common/physics_ticks_per_second=100
common/max_physics_steps_per_frame=12

[rendering]

renderer/rendering_method="forward_plus"
lights_and_shadows/use_physical_light_units=true
lights_and_shadows/directional_shadow/size=8192
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3
lights_and_shadows/positional_shadow/soft_shadow_filter_quality=3
anti_aliasing/quality/msaa_3d=2
scaling_3d/mode=1
scaling_3d/scale=1.0
environment/defaults/default_environment="res://world/environment_battle.tres"
occlusion_culling/use_occlusion_culling=true
textures/default_filters/anisotropic_filtering_level=2
```

Notas de implementación:

- Se elimina `renderer/rendering_method.mobile`: el proyecto es solo escritorio. El tag `GL Compatibility` desaparece de `config/features`.
- `msaa_3d=2` es **4×** (0=off, 1=2×, 2=4×, 3=8×). `Graphics` lo sobrescribe en runtime según el preset.
- `scaling_3d/mode=1` es **FSR 1.0**; con `scale=1.0` no se aplica escalado hasta que `Graphics` lo baje.
- `window/size/mode=3` es *Fullscreen* (no *Exclusive Fullscreen*), para que el cambio de ventana y los `SubViewport` del fisheye se comporten bien.
- `environment/defaults/default_environment` y `theme/custom` apuntan a recursos que todavía no existen. En WP-01 se crean como **placeholders mínimos** (`Environment` vacío y `Theme` vacío) para que el proyecto abra sin errores; WP-02 y WP-24 los reemplazan.
- `main_scene` apunta a la secuencia de arranque; en WP-01 es una escena mínima que delega en `SceneTransition`.

---

## 3. Capas de física 3D, máscaras y regla anti-`Area3D`

### 3.1 Tabla de capas

| # | Nombre | Bit | Contenido | Máscara (capas) | Máscara (entero) |
|---|---|---|---|---|---|
| 1 | `world` | 1 | Suelo, terreno, rocas escalables | 2, 3, 6, 9 | **294** |
| 2 | `drone` | 2 | `Drone` (`RigidBody3D`, `contact_monitor=true`) | 1, 3, 4, 8, 9 | **397** |
| 3 | `enemy_body` | 4 | Partes blindadas (`AnimatableBody3D`) | 1, 2, 8, 9 | **387** |
| 4 | `enemy_weak` | 8 | Colisionadores de puntos débiles **expuestos** | 1, 2 | **3** |
| 5 | `projectile_player` | 16 | Reservada: proyectiles físicos (P3) | 1, 3, 4, 8 | **141** |
| 6 | `projectile_enemy` | 32 | Balística del enemigo | 1, 2, 8 | **131** |
| 7 | `pickup` | 64 | `BatteryPickup` (`Area3D`, uso legítimo) | 2 | **2** |
| 8 | `city` | 128 | `Building` (`StaticBody3D`), calles, veredas | 1, 2, 3, 5, 6, 9 | **311** |
| 9 | `debris` | 256 | `DebrisChunk` (`RigidBody3D`) | 1, 2, 8, 9 | **387** |
| 10 | `trigger` | 512 | Volúmenes de ronda y límites de zona | 2 | **2** |
| 11 | `enemy_sensor` | 1024 | Reservada | — | **0** |

El valor de `collision_layer` de un cuerpo de la capa *n* es `1 << (n - 1)` (columna **Bit**).

### 3.2 Regla: ningún `Area3D` como hitbox

Prohibido usar `Area3D` para representar el volumen dañable de un enemigo, del dron, de un edificio o de un escombro. Se midió un coste de **0.39 ms/tick con 218 `Area3D`**, inaceptable frente al presupuesto de `docs/15` (física < 1.6 ms/tick en P0).

Excepciones permitidas, y solo esas: `BatteryPickup` (capa 7) y los volúmenes de ronda (capa 10), que son pocos, grandes y de vida larga.

Todo lo demás se resuelve con consultas explícitas sobre `PhysicsDirectSpaceState3D`, obtenido con `get_world_3d().direct_space_state` dentro de `_physics_process`.

### 3.3 Máscaras de consulta

| Consulta | API | Capas | Entero | Usuario |
|---|---|---|---|---|
| Disparo del dron | `intersect_ray` | 1, 3, 4, 8, 9 | **397** | `WeaponMount` (`docs/08`) |
| Apoyo de pie | `intersect_ray` hacia abajo | 1, 8 | **129** | `ProceduralLegRig` (`docs/06`) |
| Línea de visión | `intersect_ray` | 1, 8 | **129** | `Perception` (`docs/06`) |
| Barrido / pisotón | `intersect_shape` | 2, 8 | **130** | Ataques del enemigo (`docs/07`) |

Los cuatro enteros se exponen como catálogo estático para que ningún sistema los recalcule a mano:

```gdscript
class_name PhysicsLayers extends RefCounted

const QUERY_SHOT: int = 397     # world | enemy_body | enemy_weak | city | debris
const QUERY_FOOT: int = 129     # world | city
const QUERY_LOS: int = 129      # world | city
const QUERY_SWEEP: int = 130    # drone | city
```

Detalle no obvio: la máscara 129 **no incluye `enemy_body`**, de modo que un enemigo nunca se apoya sobre sí mismo ni se auto-ocluye la línea de visión.

---

## 4. Acciones de entrada

### 4.1 Plantillas de serialización

Godot 4.7 serializa cada evento como un literal `Object(...)`. Estas son las cuatro plantillas exactas; las tablas de 4.2 a 4.4 solo indican los campos que cambian.

```ini
; Eje de joystick
Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":1,"axis_value":-1.0,"script":null)
; Botón de joystick
Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":10,"pressure":0.0,"pressed":false,"script":null)
; Tecla (por keycode físico)
Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":82,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
; Botón de ratón
Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,"pressed":false,"double_click":false,"script":null)
```

Un bloque de acción completo queda así (ejemplo literal, copiar tal cual):

```ini
throttle_up={
"deadzone": 0.01,
"events": [Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":1,"axis_value":-1.0,"script":null)]
}
```

`device: -1` significa *cualquier dispositivo*; es obligatorio en todas las entradas de joystick para que `Controls` pueda reasignarlas por GUID y para que los checks headless puedan inyectar eventos (ver `docs/15` §4).

### 4.2 Ejes de vuelo (deadzone **0.01**)

Mapeo por defecto Mode 2: acelerador y guiñada en el stick izquierdo, cabeceo y alabeo en el derecho.

| Acción | Eje | `axis_value` | Stick físico |
|---|---|---|---|
| `throttle_up` | 1 | −1.0 | Izquierdo, arriba |
| `throttle_down` | 1 | +1.0 | Izquierdo, abajo |
| `yaw_left` | 0 | −1.0 | Izquierdo, izquierda |
| `yaw_right` | 0 | +1.0 | Izquierdo, derecha |
| `pitch_up` | 3 | −1.0 | Derecho, arriba |
| `pitch_down` | 3 | +1.0 | Derecho, abajo |
| `roll_left` | 2 | −1.0 | Derecho, izquierda |
| `roll_right` | 2 | +1.0 | Derecho, derecha |

La deadzone baja (0.01) es deliberada: `RadioController` reconstruye el valor analógico de cada eje a partir del par de acciones y aplica su propia curva y calibración; una deadzone alta recortaría el centro del stick antes de tiempo.

### 4.3 Acciones de juego (deadzone **0.5** salvo indicación)

| Acción | Joystick | Teclado | Notas |
|---|---|---|---|
| `respawn` | botón 4 (Back) | `R` (82) | — |
| `cycle_flight_modes` | botón 13 (D-pad izq.) | `M` (77) | — |
| `toggle_arm` | botón 7 (stick izq.) | `Space` (32) | Alterna armado |
| `arm` | botón 9 (L1) | `Shift` (4194325) | **Mantener**; `Controls` lo trata como *hold* |
| `mode_horizon` | botón 11 (D-pad arr.) | `H` (72) | — |
| `mode_turtle` | botón 12 (D-pad ab.) | `T` (84) | — |
| `pause_menu` | botón 6 (Start) | `Escape` (4194305) | — |
| `change_camera` | botón 8 (stick der.) | `C` (67) | — |
| `fire` | **eje 5** (R2), `axis_value` +1.0, **deadzone 0.35** | ratón botón 1 | Umbral de gatillo; el clic es solo para depurar |
| `fire_alt` | botón 10 (R1) | `F` (70) | — |
| `lock_target` | **eje 4** (L2), `axis_value` +1.0, **deadzone 0.35** | `Q` (81) | — |
| `cycle_target` | botón 14 (D-pad der.) | `E` (69) | — |
| `objective_next` | botón 3 (Y) | `N` (78) | — |
| `objective_skip` | botón 2 (X) | `K` (75) | — |

Sobre `fire` y `lock_target`: en un mando estándar los gatillos analógicos reposan en −1.0 y llegan a +1.0. Con `deadzone` 0.35 la acción se activa cerca del 68 % del recorrido. `WeaponMount` lee `Input.get_action_strength("fire")` para la presión continua, no solo el booleano.

### 4.4 Acciones de interfaz redefinidas

Las seis acciones `ui_*` se **redefinen por completo** en `[input]`, lo que reemplaza los eventos por defecto de Godot. El motivo es concreto: los valores por defecto incluyen `InputEventJoypadMotion` sobre los ejes 0 y 1, de modo que un acelerador de radio en reposo (valor −1.0 permanente en el eje 1) desplazaría el foco de los menús sin parar.

| Acción | Teclado | Joystick | Prohibido |
|---|---|---|---|
| `ui_up` | `Up` (4194320) | botón 11 | Ningún `InputEventJoypadMotion` |
| `ui_down` | `Down` (4194322) | botón 12 | Ídem |
| `ui_left` | `Left` (4194319) | botón 13 | Ídem |
| `ui_right` | `Right` (4194321) | botón 14 | Ídem |
| `ui_accept` | `Enter` (4194309), `Space` (32) | botón 0 (A) | Ídem |
| `ui_cancel` | `Escape` (4194305) | botón 1 (B) | Ídem |

Todas con `"deadzone": 0.5`. La navegación analógica de los menús la provee `StickNavigation`, que sintetiza eventos con histéresis y repetición propia.

---

## 5. Autoloads: orden y responsabilidad

El orden importa: cada autoload puede leer los anteriores en su `_ready()`, nunca los posteriores.

| # | Nombre | Script | Responsabilidad |
|---|---|---|---|
| 1 | `Global` | `autoloads/global.gd` | Estado de partida (`RoundState`, `selected_round`, `round_seed`), `config_dir`, `startup_errors: Array[String]`, log en `user://` abierto con `FileAccess.READ_WRITE` + `seek_end` (nunca truncar) |
| 2 | `Audio` | `autoloads/audio.gd` | Volúmenes de buses, mute, persistencia en `Audio.cfg` |
| 3 | `Controls` | `autoloads/controls.gd` | GUID activo, `action_list`, reconstrucción del `InputMap` desde `InputMap.cfg`, calibración persistida |
| 4 | `GameSettings` | `autoloads/game_settings.gd` | Idioma, esquema de navegación, `hud_config`, progreso de objetivos y de rondas |
| 5 | `Graphics` | `autoloads/graphics.gd` | Modo de ventana, escala de resolución, vsync, fps máximo, preset, MSAA, sombras, fisheye |
| 6 | `QuadSettings` | `autoloads/quad_settings.gd` | Ángulo de cámara, pesos, FOV, curvas de rates |
| 7 | `DebugGeometry` | `autoloads/debug_geometry.gd` | Dibujo inmediato de líneas y esferas para depurar IK, percepción y consultas |
| 8 | `UI` | `autoloads/ui.gd` | Utilidades de interfaz compartidas, foco y sonidos de menú |
| 9 | `StickNavigation` | `autoloads/stick_navigation.gd` | Navegación de menús con sticks; se **suspende** durante la captura de bindings |
| 10 | `SceneTransition` | `autoloads/scene_transition.gd` | Fundidos y cambio de escena; expone `warm_up_view()` |
| 11 | `Events` | `autoloads/events.gd` | Bus de señales; va **último** porque no depende de nadie y todos lo consumen |

`Events` declara **solo hechos**, nunca comandos (`docs/00` §6): la lista completa y sus firmas exactas están en §5.1.

En WP-01 los once scripts son *stubs*: `extends Node` con la cabecera de copyright y un `_ready()` vacío. `Events` sí declara ya las 21 señales de §5.1, para que `project_check` pueda verificarlas y para que nadie invente nombres nuevos más adelante.

Idioma obligatorio de conexión, impuesto por `return_value_discarded=1`:

```gdscript
var _discard := Events.enemy_part_broken.connect(_on_enemy_part_broken)
```

### 5.1 Contrato de Events

Este bloque es la **fuente de verdad única** de `autoloads/events.gd`. Todo documento que emita o consuma una de estas señales usa exactamente esta firma; el documento indicado como dueño es el único que puede cambiarla, y el cambio se replica aquí antes de tocar código.

```gdscript
# Dron (dueños: 09 energía/casco, 08 arma, 03 vuelo)
signal drone_damaged(amount: float, source_position: Vector3)
signal drone_destroyed(position: Vector3)
signal drone_respawned(score_multiplier: float)
signal energy_changed(ratio: float, critical: bool)
signal hull_changed(ratio: float)
signal weapon_heat_changed(ratio: float, overheated: bool)
signal shot_fired(origin: Vector3, direction: Vector3)
signal hit_confirmed(position: Vector3, weak: bool, lethal: bool)
signal battery_collected(amount: float, position: Vector3)
# Enemigos (dueño: 06)
signal enemy_spawned(enemy: Node3D, enemy_id: StringName)
signal enemy_part_broken(enemy: Node3D, part_id: StringName, position: Vector3)
signal enemy_weak_point_state(enemy: Node3D, wp_id: StringName, exposed: bool)
signal enemy_phase_changed(enemy: Node3D, phase_id: StringName)
signal enemy_attack_telegraphed(enemy: Node3D, attack_id: StringName, duration: float)
signal enemy_defeated(enemy: Node3D, enemy_id: StringName)
# Ciudad (dueño: 10)
signal building_destroyed(position: Vector3, value: int)
signal city_integrity_changed(ratio: float)
# Ronda (dueño: 11)
signal round_state_changed(state: int)   # Global.RoundState
# Cámara (dueño: 13; lo emiten 06, 08, 09, 10)
signal camera_trauma(amount: float, position: Vector3)
# Reservadas para P3 (dueño: 14)
signal enemy_mark_shared(enemy: Node3D, target_position: Vector3, seconds: float)
signal enemy_wave_requested(enemy: Node3D, wave_id: StringName)
```

**Regla de Godot 4 que hace esto obligatorio**: un `Callable` conectado a una señal debe aceptar **todos** los argumentos que la señal emite. Puede ignorarlos nombrándolos con `_` (`func _on_hit(_position: Vector3, weak: bool, _lethal: bool)`), pero **no puede omitirlos**: conectar un método con menos parámetros falla en tiempo de ejecución, no al compilar. Por eso las firmas de arriba son canónicas y solo el documento dueño de la señal puede cambiarlas.

Las dos señales de la sección «Reservadas para P3» se declaran desde WP-01 aunque nadie las emita todavía (`unused_signal=1` las reporta como advertencia, no como error): así el bus queda cerrado y P3 no tiene que reabrir `events.gd`.

---

## 6. Estructura de carpetas

WP-01 crea los directorios vacíos (con un `.gitkeep` donde haga falta); cada WP posterior puebla el suyo.

```
godot/  project.godot export_presets.cfg default_bus_layout.tres LICENSE NOTICE CREDITS.md
  autoloads/    los 11 scripts de §5
  drone/        drone.gd drone_rig.* camera_rig.gd + flight/ parts/ radio/ fpv_camera/
                weapons/ energy/ damage/
  enemies/      enemy_base.gd enemy_part.gd weak_point.gd detachment.gd debris_pool.gd
                enemy_catalog.gd + locomotion/ ai/ arachnodroid/
  city/         building.gd building_profile.gd city_grid.gd city_integrity.gd
                rubble_field.gd + pieces/ districts/
  rounds/       round_catalog.gd round_manager.gd battle_level.* + objectives/ results/
  gui/          boot/ components/ options_menu/ theme/ + menu_screen.gd choice_menu.gd
                main_menu.* pause_menu.* rounds_menu.* quad_settings_menu.* help_page.*
  hud/          hud.* hud_draw.gd hud_horizon.gd projection.gd + combat/
  vfx/  world/  audio/  localization/translations.csv  docs/00…16
  assets/       _raw/.gdignore + drone/ city/ enemies/ audio/ gui/ hud/
  asset_import/ import_voxel_enemy.gd import_city_piece.gd import_drone.gd
  tools/        voxsplit/ check_runner.gd physics_layers.gd build_theme.gd
                generate_ui_sounds.gd flight_sandbox.tscn *_check.* run_checks.ps1|.sh
.claude/settings.json  .github/workflows/deploy-to-itch.yml  builds/windows/  README.md
```

### 6.1 `.gdignore`

`godot/assets/_raw/.gdignore` es un archivo **vacío**. Su presencia hace que Godot ignore el directorio por completo: no lo escanea, no importa nada de él y no genera archivos `.import`. Es imprescindible porque `_raw/` contiene diez archivos comprimidos (≈ 140 MB) con los `.vox`, los `.fbx` y las texturas 4K de origen.

Los archivos de `_raw/` **no se extraen dentro del repositorio**. El pipeline de `docs/05` los lee desde el comprimido o desde un directorio temporal fuera del árbol del proyecto, y escribe únicamente los productos finales en `assets/`.

### 6.2 Claves de traducción

`localization/translations.csv` usa cabecera `keys,es,en` y prefijos estables por dominio: `UI_`, `MENU_`, `OPT_`, `AUD_`, `GFX_`, `CTRL_`, `CAL_`, `HUD_`, `QUAD_`, `OBJ_`, `ERR_`, `GAME_`, más los nuevos `RND_` (rondas), `ENM_` (enemigos) y `WPN_` (armas). Ninguna cadena visible se escribe literal en un script.

---

## 7. Presets de importación

### 7.1 GLB de enemigos

Archivo `<enemy>.glb.import`, sección `[params]`:

```ini
nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=0
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
import_script/path="res://asset_import/import_voxel_enemy.gd"
gltf/embedded_image_handling=1
_subresources={}
```

Justificación de los valores no obvios: `generate_lods=false` porque las partes se desprenden como `DebrisChunk` y un LOD generado rompería la correspondencia 1:1 malla↔colisionador (además el modelo completo son 4 282 triángulos, ver `docs/05`); `create_shadow_meshes=true` porque el jefe es el mayor emisor de sombras de la escena; `animation/import=false` porque **no hay animaciones**, toda la locomoción es procedural; `import_script/path` añade colisionadores, capas y metadatos pero **no añade scripts** a los nodos; `root_scale=1.0` porque el pipeline ya escribe el GLB en metros.

### 7.2 Piezas de ciudad (FBX)

Godot 4.7 importa FBX de forma nativa con **ufbx**; no hace falta FBX2glTF ni configurar rutas a binarios externos.

```ini
nodes/apply_root_scale=true
nodes/root_scale=<definido en docs/10>
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
animation/import=false
import_script/path="res://asset_import/import_city_piece.gd"
gltf/embedded_image_handling=1
```

Aquí los LODs **sí** se activan: hay unos 60 edificios estáticos visibles a la vez y no se desprenden en partes. La escala (`root_scale`) queda **abierta**: los FBX del pack FreeSample vienen en centímetros o en unidades arbitrarias, y `docs/10-ciudad-destructible.md` fija el valor definitivo verificándolo con `city_import_check` (`BuildingBlock_1` debe medir entre 12 y 16 m).

### 7.3 Texturas

Dos perfiles:

| Perfil | Uso | `compress/mode` | `mipmaps/generate` | `detect_3d/compress_to` |
|---|---|---|---|---|
| **VRAM** | Difusas y emisivas de ciudad y de GUI 3D | `2` (VRAM Compressed) | `true` | `0` (Disabled) |
| **Paleta** | `<enemy>_palette.png` (256×1) | `0` (Lossless) | `false` | `0` |

`detect_3d/compress_to=0` evita que Godot reimporte la textura la primera vez que la ve en un material 3D, lo que provocaría *churn* en el caché de CI.

La textura de paleta es un caso especial y **no negociable**: 256×1 píxeles, sin compresión, sin mipmaps, y el material debe usar `texture_filter = TEXTURE_FILTER_NEAREST`. Cualquier filtrado o mipmap mezcla colores de paleta adyacentes y produce franjas en los bordes de cada parte.

---

## 8. `export_presets.cfg`

Dos presets. `Windows Desktop` pasa a ser `preset.0`; el bloque `Web` existente se **renumera** a `preset.1`.

```ini
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="addons/*, tools/*, docs/*, assets/_raw/*"
export_path="../builds/windows/drone-survivor.exe"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

binary_format/architecture="x86_64"
binary_format/embed_pck=false
debug/export_console_wrapper=1
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
codesign/enable=false
application/modify_resources=true
application/product_name="Drone Survivor"
application/file_description="Drone Survivor"
```

El resto de claves de `[preset.0.options]` queda con el valor por defecto que escribe el editor al crear el preset.

El preset **`Web` se conserva** tal como está, con dos cambios: pasa a `[preset.1]` y recibe `runnable=false`. Queda documentado como **P4**: el juego es Forward+ y escritorio; la build Web requeriría el renderizador GL Compatibility y está explícitamente fuera del alcance hasta WP-41. Ningún check ni job de CI la exporta.

`exclude_filter` saca del `.pck` los addons, las herramientas de verificación, la documentación y los assets crudos. `tools/` contiene los `*_check.tscn`, que no deben viajar en la build del jugador.

---

## 9. Integración continua

Reescritura completa de `.github/workflows/deploy-to-itch.yml`. Cuatro jobs encadenados: `import` → `checks` → `export` → `deploy-itch` (este último desactivado).

```yaml
name: Drone Survivor — checks y export

on:
  push:
    branches: [master, "wp-**"]
  pull_request:
  workflow_dispatch:

env:
  GODOT_VERSION: "4.7"
  GODOT_STATUS: "stable"

jobs:
  import:
    name: Importar assets
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.7
    steps:
      - uses: actions/checkout@v4
      - name: Cache de importacion
        uses: actions/cache@v4
        with:
          path: godot/.godot/imported/
          key: godot-import-${{ runner.os }}-4.7-${{ hashFiles('godot/**/*.import', 'godot/project.godot') }}
          restore-keys: godot-import-${{ runner.os }}-4.7-
      - name: Importar
        run: godot --headless --path ./godot --import
      - uses: actions/upload-artifact@v4
        with:
          name: godot-imported
          path: godot/.godot/
          retention-days: 1

  checks:
    name: Checks headless
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.7
    needs: import
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: godot-imported
          path: godot/.godot/
      - name: Ejecutar todos los checks
        run: bash godot/tools/run_checks.sh
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: check-report
          path: |
            godot/tools/out/report.txt
            godot/tools/out/shots/

  export:
    name: Export Windows
    runs-on: ubuntu-latest
    needs: checks
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: godot-imported
          path: godot/.godot/
      - name: Exportar preset Windows Desktop
        uses: firebelley/godot-export@v6.0.0
        with:
          godot_executable_download_url: "https://github.com/godotengine/godot/releases/download/${{ env.GODOT_VERSION }}-${{ env.GODOT_STATUS }}/Godot_v${{ env.GODOT_VERSION }}-${{ env.GODOT_STATUS }}_linux.x86_64.zip"
          godot_export_templates_download_url: "https://github.com/godotengine/godot/releases/download/${{ env.GODOT_VERSION }}-${{ env.GODOT_STATUS }}/Godot_v${{ env.GODOT_VERSION }}-${{ env.GODOT_STATUS }}_export_templates.tpz"
          relative_project_path: "./godot"
          archive_output: true
          presets_to_export: "Windows Desktop"
          cache: false
      - uses: actions/upload-artifact@v4
        with:
          name: windows-desktop
          path: "/home/runner/.local/share/godot/archives/Windows Desktop.zip"

  deploy-itch:
    name: Publicar en itch.io (desactivado)
    if: false
    runs-on: ubuntu-latest
    needs: export
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: windows-desktop
      - uses: manleydev/butler-publish-itchio-action@master
        env:
          BUTLER_CREDENTIALS: ${{ secrets.BUTLER_API_KEY }}
          CHANNEL: windows
          ITCH_GAME: ${{ secrets.ITCHIO_GAME }}
          ITCH_USER: ${{ secrets.ITCHIO_USERNAME }}
          PACKAGE: "Windows Desktop.zip"
```

Diferencias contra el workflow actual, todas obligatorias: `GODOT_VERSION` pasa de `4.4.1` a `4.7`; el contenedor pasa de `barichello/godot-ci:4.4.1` a `:4.7`; `relative_project_path` se mantiene en `./godot`; se añade el job `checks` **entre** import y export; se exporta `Windows Desktop` en lugar de `Web`; el job de itch queda con `if: false` porque el juego todavía no se publica y la licencia es propietaria.

`godot/tools/run_checks.sh` es el equivalente Linux de `tools/run_checks.ps1`; ambos se especifican en `docs/15-verificacion-y-ci.md` §7.

---

## 10. Archivos de raíz y bloqueo de sala limpia

### 10.1 Legales

| Archivo | Contenido |
|---|---|
| `godot/LICENSE` | Licencia **propietaria**: «Copyright (c) 2026 … Todos los derechos reservados. No se concede permiso para usar, copiar, modificar ni distribuir este software ni su código fuente sin autorización expresa y por escrito del titular.» Cierra con: *«Esta licencia puede relajarse a una licencia permisiva (por ejemplo MIT) en el futuro, a criterio exclusivo del titular. Hasta entonces rige lo anterior.»* |
| `godot/NOTICE` | Aviso de terceros: audio de arranque (CC BY 4.0, con atribución al autor), fuentes Recursive (SIL OFL 1.1), packs voxel de enemigos y pack de ciudad FreeSample (licencias **a verificar antes de publicar**). Declara explícitamente que el juego **no** deriva de ningún código con licencia GPL. |
| `godot/CREDITS.md` | Créditos legibles por el jugador: autoría del código, assets por origen, herramientas usadas. Enlaza a `NOTICE` para el texto legal. |
| `README.md` (raíz del repo) | Qué es el juego, requisitos (Godot 4.7, Windows, Forward+), cómo abrir el proyecto (`--path godot`), cómo correr los checks, dónde están los documentos y la nota de sala limpia. |

La lista definitiva de atribuciones y el checklist de verificación previo a publicar viven en `docs/16-licencias-y-atribucion.md`; los archivos de raíz solo los materializan.

### 10.2 Nota de sala limpia en `README.md`

Texto obligatorio, literal:

> Este proyecto se desarrolla en **sala limpia**. No se copia, lee ni consulta código de terceros con licencia copyleft. En particular, el repositorio `drone-simulator` queda fuera de límites para cualquier persona o agente que trabaje en este código; la configuración de `.claude/settings.json` lo bloquea técnicamente.

### 10.3 `.claude/settings.json`

Archivo en la **raíz del repositorio** (no dentro de `godot/`). Contenido exacto:

```json
{
  "permissions": {
    "deny": [
      "Read(C:/Users/Mauri/Godot/Proyectos/drone-simulator/**)",
      "Grep(C:/Users/Mauri/Godot/Proyectos/drone-simulator/**)",
      "Glob(C:/Users/Mauri/Godot/Proyectos/drone-simulator/**)"
    ]
  }
}
```

Este archivo **se versiona** (es `settings.json`, no `settings.local.json`), para que el bloqueo viaje con el repositorio y aplique a todos los agentes. Es una barrera técnica complementaria a la prohibición explícita que lleva cada *brief* de WP.

---

## 11. Interfaz pública

WP-01 no expone lógica, pero sí contratos que el resto del proyecto consume desde el primer día.

| Elemento | Tipo | Definición |
|---|---|---|
| `res://core/physics_layers.gd` | `class_name PhysicsLayers extends RefCounted` | `const QUERY_SHOT / QUERY_FOOT / QUERY_LOS / QUERY_SWEEP: int` (§3.3) |
| `Global.startup_errors` | `Array[String]` | Claves de traducción de errores de arranque; el menú principal las muestra |
| `Global.config_dir` | `String` | `"user://config"`; todos los `.cfg` cuelgan de aquí |
| `Events.<21 señales>` | `signal` | Solo hechos, nunca comandos; firmas canónicas en §5.1 |
| `res://tools/check_runner.gd` | `class_name CheckRunner extends Node` | Helper común de los checks; se especifica en `docs/15` §2 |

Nombres de archivo de configuración bajo `user://config/`: `Audio.cfg`, `GameSettings.cfg`, `Graphics.cfg`, `Quad.cfg`, `InputMap.cfg`. Los cinco se leen y escriben con `ConfigFile`. Ningún sistema usa `JSON` ni `ResourceSaver` para configuración del jugador.

---

## 12. Parámetros y valores iniciales

Los valores literales están en el bloque INI de §2. Esta tabla recoge los que **no** vienen del plan o que hace falta justificar, más los conteos que verifica el check.

| Parámetro | Valor | Origen |
|---|---|---|
| `max_physics_steps_per_frame` | 12 | **Propuesta**: a 100 Hz y 60 fps hacen falta ~2 pasos; 12 da margen sin espiral de la muerte |
| `anisotropic_filtering_level` | 2 (= 4×) | **Propuesta** |
| `vsync_mode` | 1 (Enabled) | **Propuesta**; `Graphics` lo sobrescribe en runtime |
| `msaa_3d` | 2 (= 4×) | Plan §4.1; `Graphics` lo sobrescribe |
| `scaling_3d/mode` | 1 (FSR 1.0), `scale` 1.0 | Plan §4.1 |
| Deadzone ejes de vuelo | 0.01 | Plan §4.1 |
| Deadzone `fire` / `lock_target` | 0.35 | Plan |
| Deadzone del resto | 0.5 | Por defecto de Godot |
| Autoloads | **11**, en el orden de §5 | Plan §4.4 |
| Señales de `Events` | **21**, con las firmas de §5.1 | §5.1 |
| Capas 3D nombradas | **11** | Plan §4.2 |
| Acciones de `InputMap` | **28** (8 ejes + 14 de juego + 6 de interfaz) | §4 |
| Máscaras de consulta | 397 / 129 / 129 / 130 | §3.3 |

---

## 13. Criterios de aceptación y check headless

**Escena**: `tools/project_check.tscn` (raíz `Node` con `tools/project_check.gd`, que extiende `CheckRunner`).

**Comando**:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/project_check.tscn
```

Verifica, todo por lectura de `ProjectSettings` y de `InputMap` (nunca parseando texto):

| # | Comprobación | Cómo |
|---|---|---|
| 1 | Las **11 capas 3D** existen con el nombre exacto de §3.1 | `ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % i)` |
| 2 | Los **11 autoloads** están y **en el orden** de §5 | Recorrer `ProjectSettings.get_property_list()` con prefijo `autoload/`; comparar la lista ordenada contra la esperada |
| 3 | Renderizador `forward_plus` | `rendering/renderer/rendering_method == "forward_plus"` |
| 4 | Motor de física `Jolt Physics` y **100 Hz** | `physics/3d/physics_engine`, `physics/common/physics_ticks_per_second` |
| 5 | `config/features` contiene `"4.7"` y **no** contiene `"GL Compatibility"` | Lectura del `PackedStringArray` |
| 6 | Las **28 acciones** de §4.2–4.4 existen | `InputMap.has_action(name)` sobre la lista completa |
| 7 | Las 8 acciones de vuelo tienen `deadzone == 0.01`; `fire` y `lock_target`, `0.35` | `InputMap.action_get_deadzone(name)` |
| 8 | Ninguna acción `ui_*` tiene eventos `InputEventJoypadMotion` | Recorrer `InputMap.action_get_events("ui_…")` |
| 9 | Las 4 constantes de `PhysicsLayers` valen 397 / 129 / 129 / 130 | Comparación directa |
| 10 | `Events` declara las **21 señales** de §5.1, con el **número de argumentos** exacto | `Events.has_signal(name)` y `Events.get_signal_list()` (comparar `args.size()`) |
| 11 | `assets/_raw/.gdignore` existe | `FileAccess.file_exists` sobre `ProjectSettings.globalize_path("res://assets/_raw/.gdignore")`; el directorio está ignorado, así que la ruta se globaliza antes de consultar |
| 12 | Las 4 máscaras de consulta son coherentes con la tabla de capas | Recomputar los enteros desde §3.1 y comparar |

**Comprobación 13** (fuera de la escena, la ejecuta el runner): el proyecto abre en el editor sin errores.

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot --editor --quit
```

Criterio: código de salida 0 y **ninguna** línea que empiece por `ERROR:` o `SCRIPT ERROR:` en la salida. `run_checks.ps1` y `run_checks.sh` ejecutan este comando, filtran la salida y fallan si hay coincidencias.

`project_check` imprime `CHECK project_check: OK` y sale con 0, o `CHECK project_check: FAIL (n fallos)` con una línea por fallo y sale con 1. No escribe en `user://` ni toca la configuración del jugador.

---

## 14. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| D-1 | La imagen `barichello/godot-ci:4.7` puede no existir todavía en Docker Hub | **Abierto**. Plan B: quitar `container:` y descargar el binario Linux de Godot 4.7 con `curl` en un paso propio. El job `export` ya descarga su propio binario y no depende de la imagen |
| D-2 | `--import` como comando de importación | Existe desde 4.4; si diera problemas en 4.7, sustituir por `--editor --quit` (más lento, mismo efecto) |
| D-3 | Mapeo de botones del mando | **Propuesta**. Los índices de §4.3 siguen el estándar Xbox de Godot (`JoyButton`: A=0, B=1, X=2, Y=3, Back=4, Start=6, L3=7, R3=8, L1=9, R1=10, D-pad 11–14). Con una radio RC el usuario los reasigna desde el menú de Controles; el default solo tiene que ser razonable |
| D-4 | Teclas de `fire_alt`, `lock_target`, `cycle_target`, `objective_*` | **Propuesta** (`F`, `Q`, `E`, `N`, `K`). El teclado es P4; solo existe para depurar |
| D-5 | `root_scale` de los FBX de ciudad | **Abierto por diseño**: lo fija `docs/10` tras medir `BuildingBlock_1` |
| D-6 | `default_environment` y `theme/custom` apuntan a recursos placeholder en WP-01 | Aceptado. Si el archivo falta, Godot emite un error al abrir y la comprobación 13 lo detecta |
| D-7 | Titular del copyright en `LICENSE` y `NOTICE` | **Abierto**: hace falta el nombre legal completo. Mientras tanto dejar un `TODO` explícito y registrarlo en `docs/16` |
| D-8 | `max_physics_steps_per_frame=12`, `anisotropic_filtering_level=2`, `vsync_mode=1` | **Propuesta** sin medición; se revisan en WP-29 con `perf_report` |
| D-9 | Colisión de botón entre `toggle_arm` (L3) y el uso del stick izquierdo como clic | **Propuesta**; si molesta en pruebas, mover `toggle_arm` a L1 y `arm` a un botón libre |

---

## 15. Referencias cruzadas

- `docs/00-plan-maestro.md` — hoja de ruta, convenciones del proyecto y plantilla de *brief* por WP.
- `docs/01-sala-limpia-y-reutilizacion.md` — lista cerrada de archivos propios a copiar y protocolo de sala limpia; complementa §10.
- `docs/03-especificacion-nucleo-de-vuelo.md` — consumidor de las acciones de vuelo de §4.2 y de los 100 Hz de §2.
- `docs/04-especificacion-configuracion-y-menus.md` — implementación de los 11 autoloads de §5 y de los `.cfg` de §11.
- `docs/05-pipeline-voxel.md` — productor de los GLB que consumen los presets de §7.1.
- `docs/06-framework-de-enemigos.md` — usa las capas 3, 4 y 9 y las máscaras de §3.3.
- `docs/08-combate-y-armas.md` — usa `QUERY_SHOT` (397).
- `docs/10-ciudad-destructible.md` — fija `root_scale` de §7.2 y usa la capa 8.
- `docs/12-interfaz-y-hud.md` — consume `theme/custom` y las acciones `ui_*` de §4.4.
- `docs/15-verificacion-y-ci.md` — especifica `CheckRunner`, `run_checks.ps1` / `run_checks.sh` y el catálogo completo de checks; §9 y §13 de este documento son su primera entrada.
- `docs/16-licencias-y-atribucion.md` — origen de los textos de `LICENSE`, `NOTICE` y `CREDITS.md`.
