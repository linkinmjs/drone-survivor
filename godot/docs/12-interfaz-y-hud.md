# 12 — Interfaz y HUD

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-08 y WP-22 · Depende de: `docs/03-especificacion-nucleo-de-vuelo.md`, `docs/04-especificacion-configuracion-y-menus.md`, `docs/06-framework-de-enemigos.md`, `docs/08-combate-y-armas.md`, `docs/09-energia-y-danio.md`, `docs/10-ciudad-destructible.md`, `docs/11-rondas-y-objetivos.md`

## 1. Objetivo y alcance

Especifica **todo lo que se dibuja en pantalla**: el HUD de vuelo del dron (WP-08), la proyección compartida que ubica cosas del mundo 3D sobre la pantalla, el HUD de combate del nivel (WP-22), el recorrido de menús y las claves de traducción nuevas.

**Incluye**

- `FlightHUD` (`hud/hud.tscn`): contrato de datos por polling, componentes, configuración, `preview_mode` y estado de armado.
- `hud/projection.gd`: proyección rectilínea y de ojo de pez, recorte al borde y marcadores.
- Componentes nuevos `HUDStatus`, `HUDStickInput`, `HUDRPM`; tema `hud_theme.tres`.
- `CombatHUD` (`hud/combat/combat_hud.tscn`): 10 componentes de combate, temporizador de ronda y glitch de EMP.
- Flujo de menús: arranque, menú principal, menú de rondas, pausa.
- Tabla es/en de claves nuevas.
- Checks `hud_projection_check` y `combat_hud_check`.

**NO incluye**

- Contenido de los menús de opciones, controles y quad, ni su persistencia (`docs/04`).
- Paleta, fuentes, tema generado y overlay FPV (`docs/13`).
- La lógica de ronda, objetivos y resultados (`docs/11`); acá solo su presentación.
- La cámara FPV, el fisheye y `project_direction()` del dron (`docs/03`); acá solo se consumen.

### 1.1 Reparto por capa de canvas

| Capa | Nodo | Dueño | Vive en |
|---|---|---|---|
| −1 | `FpvOverlay` (`ColorRect` + shader) | `docs/13` | `DroneRig` |
| 0 | `FlightHUD` (`Control`) | este doc, WP-08 | `DroneRig` |
| 20 | `CombatHUD` (`CanvasLayer`) | este doc, WP-22 | `BattleLevel` |
| 40 | `PauseMenu` (`CanvasLayer`) | este doc + `docs/04` | `BattleLevel` |
| 45 | `ResultCard` (`CanvasLayer`) | `docs/11` | instanciado por `RoundManager` |
| 100 | `SceneTransition` (autoload) | ya existe | autoload |

Regla: el `FlightHUD` muere con el dron y se reconstruye al reaparecer; el `CombatHUD` sobrevive al respawn porque pertenece al nivel. Un `Control` bajo un `Node3D` se dibuja igual en el canvas por defecto del viewport (capa 0), que es exactamente lo que se quiere.

## 2. FlightHUD

`hud/hud.tscn` + `hud/hud.gd` — `class_name FlightHUD extends Control`, `anchors_preset = PRESET_FULL_RECT`, `mouse_filter = MOUSE_FILTER_IGNORE`, `theme = res://hud/hud_theme.tres`.

### 2.1 Árbol

```
FlightHUD (Control)
├── Horizon      (HUDHorizon)       línea de horizonte + escalera de cabeceo
├── SideTapes    (HUDSideTapes)     cintas de velocidad (izq.) y altitud (der.)
├── CompassTape  (HUDCompassTape)   rumbo en grados, arriba al centro
├── Readouts     (HUDReadouts)      altitud, velocidad km/h, velocidad vertical
├── Crosshair    (HUDCrosshair)     retículo de vuelo, centro
├── ModeBadge    (HUDModeBadge)     modo de vuelo, abajo al centro
├── RecIndicator (HUDRecIndicator)  punto REC + cronómetro, arriba a la izquierda
├── Status       (HUDStatus)        mensajes de armado, abajo al centro
├── StickLeft    (HUDStickInput)    caja de stick izquierdo
├── StickRight   (HUDStickInput)    caja de stick derecho
├── RPM          (HUDRPM)           4 barras de revoluciones
└── GateMarker   (HUDGateMarker)    oculto en combate; lo reemplaza OffscreenMarkers
```

Los componentes marcados como existentes (`HUDHorizon`, `HUDSideTapes`, `HUDCompassTape`, `HUDReadouts`, `HUDCrosshair`, `HUDModeBadge`, `HUDRecIndicator`, `HUDGateMarker`) se reutilizan tal cual y dibujan con los estáticos de `HUDDraw` (`text`, `line`, `circle`, `dashed_polyline`, `fade`, `font_bold()`, `font_mono()`).

### 2.2 Contrato de datos

El HUD **no observa al dron**: el dron lo alimenta una vez por frame de física.

```gdscript
func update_data(dt: float, pos: Vector3, angles: Vector3, velocity: Vector3,
        left_stick: Vector2, right_stick: Vector2, rpm: Array[float]) -> void
func update_flight_mode(key: String, blink: bool) -> void
func show_component(component: Component, visible: bool) -> void
func apply_hud_config() -> void
func set_preview(enabled: bool) -> void
func on_armed(mode_key: String) -> void
func on_disarmed() -> void
func on_arm_failed(reason_key: String) -> void
```

Unidades y convenciones, fijas para siempre:

| Argumento | Unidad | Nota |
|---|---|---|
| `dt` | s | delta del paso de física que produjo la muestra |
| `pos` | m, mundo | `pos.y` es la altitud mostrada |
| `angles` | rad | `x` cabeceo (+ arriba), `y` guiñada, `z` alabeo (+ derecha) |
| `velocity` | m/s, mundo | `velocity.y` es la velocidad vertical |
| `left_stick`, `right_stick` | −1..1 | ya con curvas y zona muerta aplicadas |
| `rpm` | rpm absolutas, 4 elementos | el HUD normaliza con `MAX_RPM = 30000.0` |

Derivados: `speed_kmh = velocity.length() * 3.6`; `heading = fposmod(rad_to_deg(-angles.y), 360.0)` en grados para `HUDCompassTape`.

### 2.3 Promedios y refresco de números

Dos ritmos distintos en el mismo nodo:

- **Continuos** (horizonte, escalera, retículo, cintas, sticks, RPM): usan el valor instantáneo, cada frame. Son los que transmiten sensación de vuelo.
- **Numéricos** (`HUDReadouts`, rumbo en grados): usan un promedio ponderado por tiempo y se publican a `1/fps` para que los dígitos sean legibles.

```
_acc_value += value * dt
_acc_time  += dt
si _acc_time >= 1.0 / fps:
    publicar(_acc_value / _acc_time);  _acc_value = 0.0;  _acc_time = 0.0
```

`fps` viene de `GameSettings.hud_config["fps"]`, rango 5–60, por defecto **10** (el default lo fija `GameSettings`, `docs/04` §3.4). Ponderar por `dt` (y no promediar muestras) mantiene la lectura correcta aunque el paso de física varíe.

### 2.4 Componentes configurables

```gdscript
enum Component {CROSSHAIR, STATUS, HEADING, SPEED, ALTITUDE, LADDER,
                HORIZON, STICKS, RPM, FLIGHT_MODE, REC, SIDE_TAPES}
```

`STICKS` controla las dos cajas a la vez. `SPEED` y `ALTITUDE` controlan los números de `HUDReadouts`; `SIDE_TAPES` controla las cintas laterales; son independientes a propósito.

**`STATUS` no es configurable**: los mensajes de armado, desarmado y fallo de armado se ven siempre. Está en el `enum` para que `show_component()` pueda ocultarlo en el modo cinemático y en las capturas, pero **no tiene bool en `hud_config`**. Por eso el enum tiene 12 entradas y el menú de HUD (`docs/04` §4.2) muestra 11 interruptores.

`apply_hud_config()` lee `GameSettings.hud_config`, un `Dictionary` con **13 claves** (`fps`, `horizon_mode` y los 11 bools, uno por cada `Component` distinto de `STATUS`):

| Clave | Tipo | Rango / valores | Defecto |
|---|---|---|---|
| `fps` | `int` | 5–60 | 10 |
| `horizon_mode` | `String` | `camera` \| `attitude` | `camera` |
| `crosshair`, `heading`, `speed`, `altitude`, `ladder`, `horizon`, `sticks`, `rpm`, `flight_mode`, `rec`, `side_tapes` | `bool` | — | ver §9 |

`horizon_mode = camera` pone `HUDHorizon` en modo `camera` y le pasa el `Callable` `camera.project_direction(dir) -> Vector2`, de modo que la línea sigue la deformación del ojo de pez. `attitude` usa `pitch`/`roll` y dibuja una línea geométrica, más barata y siempre definida.

Cualquier clave faltante o fuera de rango se corrige con el valor por defecto y **no** aborta: un `.cfg` viejo nunca rompe el HUD.

### 2.5 `preview_mode`

`set_preview(true)` hace que el HUD se alimente solo, sin dron: un generador interno produce un barrido suave (cabeceo ±25°, alabeo ±35°, rumbo continuo a 12°/s, altitud 40 ± 15 m, velocidad 0–90 km/h, sticks en círculos de Lissajous, RPM con ruido). Lo usa el menú de opciones para previsualizar los 11 interruptores en vivo, y el check de capturas.

En `preview_mode` el HUD ignora `update_data()` externo y nunca se conecta a `Events`.

### 2.6 Estado de armado

El `DroneRig` conecta sus señales a los tres métodos. `HUDStatus` muestra un mensaje centrado de 1.6 s y, mientras el dron esté desarmado, un texto persistente parpadeando a 1 Hz.

| Señal del dron | Método | Texto | Color |
|---|---|---|---|
| `armed(mode_key)` | `on_armed` | `HUD_ARMED` + `update_flight_mode(mode_key, false)` | `SUCCESS` |
| `disarmed()` | `on_disarmed` | `HUD_DISARMED` persistente | `TEXT_DIM` |
| `arm_failed(reason_key)` | `on_arm_failed` | `HUD_ARM_FAILED_THROTTLE` / `HUD_ARM_FAILED_RECOVER` | `DANGER` |
| `flight_mode_changed(key)` | `update_flight_mode` | `HUD_MODE_*` en `HUDModeBadge` | `ACCENT`, parpadea si `blink` |

`blink = true` se usa para `RECOVER` (modo impuesto por el sistema, no elegido).

### 2.7 `hud_theme.tres`

Tema propio del HUD, independiente del tema de menús: fuente mono a 24 px, `outline_size = 4`, `font_outline_color = HUD_SHADOW`, `font_color = HUD_TEXT`. Se genera junto con el tema de UI desde `tools/build_theme.gd` (`docs/13`). Solo el HUD usa contorno: sobre el video de la cámara no hay fondo en el que apoyarse.

## 3. Proyección compartida

`hud/projection.gd` — `class_name HUDProjection extends RefCounted`, solo estáticos, sin estado.

```gdscript
static func project_direction(camera: Camera3D, dir: Vector3, fisheye_hfov: float) -> Vector2
static func project_point(camera: Camera3D, world_point: Vector3, fisheye_hfov: float) -> Vector2
static func edge_clamp(point: Vector2, rect: Rect2, margin: float) -> Dictionary
static func marker_for(camera: Camera3D, world_point: Vector3, rect: Rect2,
        margin: float, fisheye_hfov: float) -> Dictionary
```

### 3.1 Semántica

- `fisheye_hfov <= 0.0` → **rectilínea**. Si `camera.is_position_behind(camera.global_position + dir)` devuelve `true`, el resultado es `Vector2(NAN, NAN)`; si no, `camera.unproject_position(...)`.
- `fisheye_hfov > 0.0` → **equidistante**. Con `local = camera.global_basis.inverse() * dir.normalized()` y el eje óptico en `-Z`:
  - `theta = acos(clampf(-local.z, -1.0, 1.0))`
  - si `theta > deg_to_rad(fisheye_hfov) * 0.5` → `Vector2(NAN, NAN)` (fuera del círculo visible)
  - `r = theta / (deg_to_rad(fisheye_hfov) * 0.5)`, `phi = atan2(local.y, local.x)`
  - `pos = centro + Vector2(cos(phi), -sin(phi)) * r * (viewport_size.x * 0.5)`

  El medio FOV horizontal se mapea a media pantalla de ancho: es la convención del shader de ojo de pez de `docs/03`, y por eso las dos imágenes coinciden.
- `edge_clamp(point, rect, margin)` devuelve `{pos: Vector2, angle: float, offscreen: bool}`. Si el punto cae dentro de `rect.grow(-margin)`, lo devuelve intacto con `offscreen = false`. Si no, lo recorta al borde del rectángulo interior sobre el segmento centro→punto y devuelve el ángulo de la flecha.
- `marker_for(...)` es la función que usan los marcadores: proyecta, y **si el punto está detrás de la cámara o fuera del círculo de ojo de pez**, construye la dirección de respaldo anulando la componente frontal en espacio de cámara, normalizando el resto y empujando el marcador al borde (si la parte plana es casi nula, usa `Vector2.DOWN`). Devuelve `{pos, angle, offscreen, distance}` y **nunca** `NAN`.

Quien llame a `project_*` debe verificar con `is_finite()`; quien llame a `marker_for` no.

`HUDHorizon` en modo `camera` sigue usando el `Callable` `camera.project_direction(dir)` de la cámara FPV, que internamente hace lo mismo con el `hfov` real; `HUDProjection` es la versión sin dependencias de cámara propia que usan el `CombatHUD` y los checks.

## 4. CombatHUD

`hud/combat/combat_hud.tscn` + `combat_hud.gd` — `class_name CombatHUD extends CanvasLayer`, `layer = 20`, propiedad del `battle_level`. Un hijo `Control` full-rect con `mouse_filter = IGNORE` contiene todos los componentes; cada uno es un `Control` con `_draw()` que usa `HUDDraw` y `UIPalette`.

```
CombatHUD (CanvasLayer, layer 20)
└── Root (Control, full rect, mouse_filter = IGNORE)
    ├── EnergyBar · HullBar · HeatGauge · Reticle · HitMarker
    ├── BossBar · CityBar · OffscreenMarkers · DamageDirection · TelegraphWarning
    ├── RoundTimer · ObjectiveLine
    └── GlitchLayer
```

### 4.1 Componentes

| Nodo | Fuente de datos | Comportamiento y posición |
|---|---|---|
| `EnergyBar` | `Events.energy_changed(ratio, critical)` | arco a la izquierda del centro, 220°→320°, radio 190 px, grosor 8; relleno `ACCENT`; con `critical` parpadea a 3 Hz en `DANGER` y muestra `HUD_ENERGY_LOW` (la histéresis 15 %/18 % la resuelve `docs/09`, el HUD solo obedece) |
| `HullBar` | `Events.hull_changed(ratio)` | 4 segmentos de 25 % a la derecha del centro, espejo del arco de energía; el segmento activo se vacía, los rotos quedan en `DANGER`; flash blanco de 120 ms al bajar |
| `HeatGauge` | `Events.weapon_heat_changed(ratio, overheated)` | barra de 180×6 px, 46 px bajo el retículo; gradiente `ACCENT`→`DANGER`; con `overheated` parpadea entera en rojo y escribe `HUD_HEAT_LOCK` |
| `Reticle` | polling de `WeaponMount`: `get_spread_deg()`, `get_locked_weak_point()`, `get_aim_direction()` (`docs/08` §3.2) | 4 corchetes que se separan `spread_deg · 34 px/°`; punto central de 2 px; si el rayo de asistencia toca un `WeakPoint` expuesto, dibuja su caja en `TARGET` (cian); con objetivo fijado los corchetes giran 45° y aparece `HUD_LOCK` |
| `HitMarker` | `Events.hit_confirmed(position, weak, lethal)` | ✕ de 18 px, 120 ms, apilable hasta 3; el color sale de los dos booleanos: blanco (`weak = false`), ámbar (`weak = true`), rojo y 22 px (`lethal = true`, la parte se rompió con ese impacto) |
| `BossBar` | `Events.enemy_spawned(enemy, id)`, `enemy_part_broken(enemy, part_id, pos)`, `enemy_phase_changed(enemy, phase_id)`; polling de los `WeakPoint` del enemigo | arriba al centro: **una barra por parte** — 4 rodillas, 1 visor, 3 segmentos de núcleo; las no expuestas se dibujan atenuadas con hachurado; la fase se muestra con chevrons y la clave `BOSS_PHASE_<n>` derivada del `phase_id` |
| `CityBar` | `Events.city_integrity_changed(ratio)`, `Events.building_destroyed(position, value)` | franja superior de 640×10 px bajo la `BossBar`; muesca fija en 0.35; en `building_destroyed` destella 250 ms en `DANGER` |
| `OffscreenMarkers` | grupos `enemies` y `pickups`, más `CityIntegrity.get_under_siege()` (grupo `buildings_under_siege`, un edificio por vez) | `HUDProjection.marker_for` sobre el rectángulo de pantalla con `margin = 56`; flecha triangular de 16 px + distancia en metros; enemigo `DANGER`, pila `SUCCESS`, edificio `ACCENT`; máximo 6, ordenados por cercanía |
| `DamageDirection` | `Events.drone_damaged(amount, source_position)` | arco de 60° pegado al borde en la dirección de la fuente, radio 44 % del alto; alfa `clampf(amount / 45.0, 0.25, 1.0)`; se desvanece en 0.8 s; se suman hasta 3 arcos |
| `TelegraphWarning` | `Events.enemy_attack_telegraphed(enemy, attack_id, duration)` | franja a 24 % del alto: icono del ataque, `HUD_TELEGRAPH_<ATTACK_ID>` y barra de windup que se vacía en `duration`; parpadea a 4 Hz en el último 25 %. El punto de impacto no viene en la señal: el marcador lo toma del `enemy` recibido |
| `RoundTimer` | polling de `RoundManager.get_elapsed_seconds()` | `m:ss` arriba a la derecha en mono; pasa a `ACCENT` al superar `get_time_par()` |
| `ObjectiveLine` | `RoundManager.objective_text_changed` | tarea actual + barra de progreso (oculta si `get_progress() < 0`) + texto de progreso, debajo de la `CityBar` |
| `GlitchLayer` | señal local `EnergySystem.emp_hit(glitch_seconds)` | §4.3; no viaja por el bus, se conecta en `bind_weapon()`/`bind_drone()` tras cada respawn |

### 4.2 Modo cinemático

Durante `INTRO` el `CombatHUD` muestra solo `CityBar` y un rótulo con `name_key`/`goal_key` de la ronda, más `ROUND_INTRO_SKIP`. `set_cinematic(true/false)` lo conmuta; `RoundManager` lo llama en cada cambio de estado.

### 4.3 Glitch de EMP

`EnergySystem.emp_hit(glitch_seconds)` llama a `GlitchLayer.trigger_emp(glitch_seconds)` (3.0 s con los valores de `docs/09`) y arranca una perturbación con intensidad `e = 1.0 - t / glitch_seconds`:

- Cada componente recibe un desplazamiento aleatorio de ±`6 · e` px, re-sorteado a 12 Hz.
- Con probabilidad `0.15 · e` por sorteo, un componente al azar se oculta un cuadro.
- `HUDReadouts` y `RoundTimer` muestran `--` con probabilidad `0.2 · e`.
- Publica su valor en `emp_strength` para que `docs/13` lo lea en el uniform del `fpv_overlay.gdshader`.

`is_glitching() -> bool` es `false` a los 3.0 s exactos y todos los desplazamientos vuelven a cero. Un segundo EMP durante el primero **reinicia** el contador, no lo acumula.

## 5. Flujo de menús

```
boot_sequence.tscn ──► main_menu.tscn ──► rounds_menu.tscn ──► battle_level.tscn
   (Ominoso)              │  MENU_PLAY                            │
                          ├─ MENU_HANGAR  → quad_settings_menu     ├─ PauseMenu (layer 40)
                          ├─ MENU_HELP    → help_page              └─ ResultCard (layer 45)
                          ├─ MENU_OPTIONS → options hub
                          └─ MENU_QUIT    → UI.confirm + quit
```

- El menú principal es un `MenuScreen`; las cuatro primeras entradas usan `open_submenu(packed)`, que conserva la pila y el botón de volver. `MENU_QUIT` hace `if await UI.confirm("MENU_QUIT_CONFIRM"): get_tree().quit()`.
- `Global.startup_errors` se muestra como una lista de claves `ERR_*` en un panel del menú principal, y se vacía al leerlo.
- `UI` ya provee sonido y anillo de foco automático en todo `BaseButton`; los elementos que no deben sonar o enfocarse llevan las metas `ui_silent` y `no_focus_ring`. Las tarjetas de ronda bloqueadas llevan las dos.
- `StickNavigation` traduce sticks a `ui_*`; se suspende (`suspended = true`) mientras un popup de captura de control esté abierto (`docs/04`) y mientras corra la cinemática de `INTRO`.
- `SceneTransition.change_scene(path: String, show_loading := false)` se usa para entrar y salir del nivel (al nivel se entra con `show_loading = true`); `is_busy()` bloquea pulsaciones repetidas.

### 5.1 PauseMenu

`gui/pause_menu.tscn` — `CanvasLayer` layer 40, `process_mode = PROCESS_MODE_WHEN_PAUSED`, host en el nivel.

```gdscript
signal resumed
signal menu
```

Entradas: `MENU_RESUME`, `MENU_HANGAR`, `MENU_OPTIONS`, `MENU_HELP`, `MENU_MAIN` (con `UI.confirm("MENU_QUIT_ROUND_CONFIRM")`).

**Bloqueo de reanudación**: el botón que abre la pausa suele ser el mismo que la cierra. El menú marca `_armed = false` al abrirse y solo lo pone en `true` cuando detecta el `release` de la acción `pause`; hasta entonces ignora toda solicitud de reanudar. Así, mantener el botón apretado no reanuda.

Al pausar, `docs/13` habilita el filtro pasa-bajos del bus `Music`; al reanudar lo deshabilita.

## 6. Claves de traducción nuevas

CSV `localization/translations.csv` con columnas `keys,es,en`. En los `.tscn` el `text` **es la clave**; `tr()` solo se usa donde hay formato. Cada pantalla reconstruye sus textos en `NOTIFICATION_TRANSLATION_CHANGED`.

| clave | es | en |
|---|---|---|
| `HUD_ENERGY` | ENERGÍA | ENERGY |
| `HUD_ENERGY_LOW` | ENERGÍA CRÍTICA | LOW POWER |
| `HUD_HULL` | CASCO | HULL |
| `HUD_HEAT` | CALOR | HEAT |
| `HUD_HEAT_LOCK` | SOBRECALENTADO | OVERHEATED |
| `HUD_CITY` | CIUDAD | CITY |
| `HUD_LOCK` | FIJADO | LOCKED |
| `HUD_ARMED` | ARMADO | ARMED |
| `HUD_DISARMED` | DESARMADO | DISARMED |
| `HUD_ARM_FAILED_THROTTLE` | BAJÁ EL ACELERADOR | LOWER THROTTLE |
| `HUD_ARM_FAILED_RECOVER` | RECUPERACIÓN ACTIVA | RECOVERY ACTIVE |
| `HUD_MODE_ACRO` | ACRO | ACRO |
| `HUD_MODE_HORIZON` | HORIZONTE | HORIZON |
| `HUD_MODE_TURTLE` | TORTUGA | TURTLE |
| `HUD_MODE_RECOVER` | RECUPERAR | RECOVER |
| `HUD_RESPAWN_IN` | RECONSTRUYENDO {0} | REBUILDING {0} |
| `HUD_TELEGRAPH_STOMP` | PISOTÓN | STOMP |
| `HUD_TELEGRAPH_LEG_SWEEP` | BARRIDO | LEG SWEEP |
| `HUD_TELEGRAPH_HEAD_LASER` | LÁSER | HEAD LASER |
| `HUD_TELEGRAPH_SIEGE_BEAM` | HAZ DE ASEDIO | SIEGE BEAM |
| `HUD_TELEGRAPH_EMP_PULSE` | PULSO EMP | EMP PULSE |
| `HUD_TELEGRAPH_POUNCE` | EMBESTIDA | POUNCE |
| `HUD_TELEGRAPH_SHAKE_OFF` | SACUDIDA | SHAKE OFF |
| `MENU_PLAY` | Jugar | Play |
| `MENU_HANGAR` | Hangar | Hangar |
| `MENU_HELP` | Ayuda | Help |
| `MENU_OPTIONS` | Opciones | Options |
| `MENU_QUIT` | Salir | Quit |
| `MENU_QUIT_CONFIRM` | ¿Salir del juego? | Quit the game? |
| `MENU_QUIT_ROUND_CONFIRM` | ¿Abandonar la ronda? Se pierde el progreso. | Abandon the round? Progress will be lost. |
| `MENU_RESUME` | Reanudar | Resume |
| `MENU_MAIN` | Menú principal | Main menu |
| `MENU_PAUSED` | EN PAUSA | PAUSED |
| `ROUND_FIRST_CONTACT_NAME` | Primer contacto | First Contact |
| `ROUND_FIRST_CONTACT_GOAL` | Defendé el distrito A del Arachnodroid. | Defend District A from the Arachnodroid. |
| `ROUND_LOCKED_HINT` | Completá «{0}» para desbloquear | Complete "{0}" to unlock |
| `ROUND_BEST_SCORE` | Mejor puntaje | Best score |
| `ROUND_BEST_TIME` | Mejor tiempo | Best time |
| `ROUND_SOON` | Próximamente | Coming soon |
| `ROUND_INTRO_SKIP` | Saltear | Skip |
| `ROUND_VICTORY` | CIUDAD A SALVO | CITY SECURED |
| `ROUND_DEFEAT` | CIUDAD PERDIDA | CITY LOST |
| `RESULT_TIME` | Tiempo | Time |
| `RESULT_INTEGRITY` | Integridad | Integrity |
| `RESULT_PARTS` | Partes rotas | Parts broken |
| `RESULT_ACCURACY` | Precisión | Accuracy |
| `RESULT_DEATHS` | Reconstrucciones | Rebuilds |
| `RESULT_MULTIPLIER` | Multiplicador | Multiplier |
| `RESULT_SCORE` | Puntaje | Score |
| `RESULT_NEW_RECORD` | ¡Nuevo récord! | New record! |
| `RESULT_RETRY` | Reintentar | Retry |
| `RESULT_NEXT` | Siguiente ronda | Next round |
| `RESULT_ROUNDS` | Elegir ronda | Choose round |
| `RESULT_MENU` | Menú principal | Main menu |
| `RESULT_MEDAL_GOLD` / `_SILVER` / `_BRONZE` / `_NONE` | Oro / Plata / Bronce / Sin medalla | Gold / Silver / Bronze / No medal |
| `OBJ_DEFEND_CITY_TITLE` | Contener el asedio | Hold the siege |
| `OBJ_DEFEND_CITY_PROGRESS` | Integridad {0} % | Integrity {0}% |
| `OBJ_BREAK_PARTS_TITLE` | Romper 3 rodillas | Break 3 knees |
| `OBJ_DEFEAT_ENEMY_TITLE` | Destruir el núcleo | Destroy the core |
| `OBJ_DEFEAT_ENEMY_PROGRESS` | Estructura {0} % | Structure {0}% |
| `OBJ_SURVIVE_TIME_TITLE` | Sobrevivir | Survive |
| `UI_TIP_ARM` | Bajá el acelerador antes de armar. | Lower the throttle before arming. |
| `UI_TIP_STICKS` | Acro manda velocidad de giro; Horizonte manda ángulo. | Acro commands rate; Horizon commands angle. |
| `UI_TIP_WEAK_POINTS` | Lo que brilla en cian se puede romper. | Anything glowing cyan can be broken. |
| `UI_TIP_BATTERIES` | Las pilas reaparecen: memorizá dónde están. | Batteries respawn — memorize where they are. |
| `UI_TIP_CITY` | Si la ciudad cae por debajo del 35 %, perdés. | If the city drops below 35 %, you lose. |
| `UI_TIP_TELEGRAPH` | Todo ataque avisa antes de golpear. | Every attack telegraphs before it lands. |

Las seis claves `UI_TIP_*` son el contenido de `SceneTransition.TIPS` (pantalla de carga). **Reemplazan por completo** a las que trae el archivo copiado, que hablan de un simulador de vuelo y no aplican a este juego (`01` §2.3).

La lista completa (incluidos `OBJ_*_DONE` y los `HUD_TELEGRAPH_*` restantes) vive en el CSV; esta tabla fija el estilo: mayúsculas para el HUD, capital inicial para menús, voseo rioplatense.

## 7. Interfaz pública

| Archivo | Clase | Extiende |
|---|---|---|
| `hud/hud.gd` | `FlightHUD` | `Control` |
| `hud/projection.gd` | `HUDProjection` | `RefCounted` (estático) |
| `hud/hud_status.gd` | `HUDStatus` | `Control` |
| `hud/hud_stick_input.gd` | `HUDStickInput` | `Control` |
| `hud/hud_rpm.gd` | `HUDRPM` | `Control` |
| `hud/combat/combat_hud.gd` | `CombatHUD` | `CanvasLayer` |
| `hud/combat/energy_bar.gd` … `telegraph_warning.gd` | un `class_name` por componente | `Control` |
| `gui/pause_menu.gd` | `PauseMenu` | `CanvasLayer` |

Métodos públicos de los componentes nuevos:

```gdscript
# HUDStatus
func show_message(text_key: String, color: Color, seconds: float) -> void
func set_persistent(text_key: String, color: Color) -> void   # "" limpia
# HUDStickInput
func update_stick_input(value: Vector2) -> void
# HUDRPM
func update_rpm(r1: float, r2: float, r3: float, r4: float) -> void
# CombatHUD
func set_cinematic(enabled: bool) -> void
func bind_round(round_manager: RoundManager) -> void
func bind_drone(rig: Node3D) -> void            # WeaponMount + EnergySystem.emp_hit
func bind_enemy(enemy: Node3D) -> void
func bind_city(city_integrity: Node) -> void
func is_glitching() -> bool
```

`bind_*` existe porque el `CombatHUD` sobrevive al respawn: cuando el dron se reconstruye, `RoundManager` vuelve a llamar `bind_drone()` con el rig nuevo, y el HUD desconecta lo viejo antes de conectar lo nuevo. Todo lo que llega por el bus no necesita rebind. `bind_city` es necesaria porque `get_under_siege()` es una consulta, no un evento.

## 8. Parámetros y valores iniciales

| Parámetro | Valor | Nodo |
|---|---|---|
| `hud_config.fps` | 10 (rango 5–60) | `GameSettings` / `FlightHUD` |
| `hud_config.horizon_mode` | `camera` | `HUDHorizon` |
| Interruptores por defecto (11; `STATUS` no tiene) | `crosshair` ✓ · `horizon` ✓ · `ladder` ✓ · `heading` ✓ · `speed` ✓ · `altitude` ✓ · `side_tapes` ✓ · `flight_mode` ✓ · `rec` ✗ · `sticks` ✗ · `rpm` ✗ | `GameSettings` |
| Fuente del HUD | mono 24 px, contorno 4 px | `hud_theme.tres` |
| `MAX_RPM` para normalizar | 30000.0 | `HUDRPM` |
| Mensaje de armado | 1.6 s | `HUDStatus` |
| Parpadeo de desarmado | 1 Hz | `HUDStatus` |
| Radio del arco de energía | 190 px, grosor 8 px | `EnergyBar` |
| Umbral de parpadeo de energía | 0.15, a 3 Hz | `EnergyBar` |
| Segmentos de casco | 4 × 25 % | `HullBar` |
| Barra de calor | 180 × 6 px, 46 px bajo el centro | `HeatGauge` |
| Escala de dispersión del retículo | 34 px por grado | `Reticle` |
| Duración del hitmarker | 120 ms, hasta 3 apilados | `HitMarker` |
| Barras de la `BossBar` | 8 (4 rodillas + visor + 3 núcleo) | `BossBar` |
| Franja de ciudad | 640 × 10 px, muesca en 0.35 | `CityBar` |
| Margen de marcadores | 56 px | `OffscreenMarkers` |
| Marcadores simultáneos | ≤ 6 | `OffscreenMarkers` |
| Arco de daño | 60°, 0.8 s de desvanecido, hasta 3 | `DamageDirection` |
| Parpadeo final de telegrafía | último 25 % a 4 Hz | `TelegraphWarning` |
| Duración del glitch de EMP | 3.0 s exactos | `GlitchLayer` |
| Desplazamiento máximo del glitch | ±6 px a 12 Hz | `GlitchLayer` |
| Capas de canvas | −1 / 0 / 20 / 40 / 45 / 100 | §1.1 |

## 9. Criterios de aceptación y checks headless

### 9.1 `hud_projection_check` (WP-08, reutilizado por WP-06)

Archivos: `tools/hud_projection_check.tscn` + `.gd`. Escena mínima: plano oscuro de 400 × 400 m, cielo claro, `FPVCamera` a 30 m.

**Comando** (necesita framebuffer real por la parte de captura):

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --windowed --resolution 960x540 --path godot res://tools/hud_projection_check.tscn -- --shots=user://shots/hud
```

La parte puramente numérica (filas 1–3) también corre sin GPU:

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/hud_projection_check.tscn
```

| # | Verifica |
|---|---|
| 1 | Barrido de 200 actitudes (cabeceo −80..80°, alabeo −180..180°) × 3 modos de ojo de pez (OFF `hfov = 0`, FAST `hfov = 160`, FULL `hfov = 180`) × 36 direcciones del círculo del horizonte: `project_direction` devuelve o bien un valor finito, o bien `NAN` en **ambas** componentes; nunca una mezcla, nunca `INF` |
| 2 | `marker_for` sobre esas mismas 21 600 muestras devuelve siempre `pos` finito y dentro del rectángulo, y `angle` finito |
| 3 | `edge_clamp` es idempotente: aplicarlo dos veces da el mismo punto; un punto interior no se mueve |
| 4 | **Coincidencia con la imagen**: en 9 actitudes representativas y los 3 modos, se lee la imagen del viewport, se busca en 9 columnas la fila donde la luminancia cruza el punto medio (transición cielo/suelo) y se compara con la `y` que `HUDHorizon` dibujó en esa columna: error ≤ 6 px |
| 5 | Captura `hud_<modo>.png` en el directorio de `--shots`, con todos los componentes visibles y `preview_mode` activo |

### 9.2 `combat_hud_check` (WP-22)

Archivos: `tools/combat_hud_check.tscn` + `.gd`. Instancia `combat_hud.tscn` sin nivel y lo alimenta con `Events` sintéticos y objetos falsos (`WeaponMount` y `EnemyBase` de prueba con la interfaz mínima).

**Comando**

```
"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --windowed --resolution 960x540 --path godot res://tools/combat_hud_check.tscn -- --shots=user://shots/combat
```

| # | Verifica |
|---|---|
| 1 | Los 10 componentes existen, son `visible` y dibujaron al menos una vez tras alimentarlos |
| 2 | `energy_changed(0.10, true)` → `EnergyBar` en estado de parpadeo; `hull_changed(0.55)` → 2 segmentos rotos; `weapon_heat_changed(1.0, true)` → `HeatGauge` bloqueado |
| 3 | `hit_confirmed` con las 3 combinaciones útiles de `weak`/`lethal` → 3 marcas distintas, todas desaparecidas a los 130 ms |
| 4 | `enemy_spawned` + 8 `enemy_part_broken` → la `BossBar` pasa de 8 barras llenas a 8 vacías; `enemy_phase_changed(enemy, &"p3_fury")` muestra 3 chevrons |
| 5 | `building_destroyed` → destello de `CityBar` que termina antes de 300 ms |
| 6 | `OffscreenMarkers`: 12 puntos alrededor y detrás de la cámara → todas las posiciones finitas y dentro del rectángulo; se dibujan como mucho 6 |
| 7 | `drone_damaged` desde 4 direcciones → 4 ángulos distintos, ninguno `NAN`; a los 0.9 s no queda arco |
| 8 | `enemy_attack_telegraphed(enemy, &"stomp", 1.1)` → texto `HUD_TELEGRAPH_STOMP` y barra que llega a 0 a los 1.1 s ±0.05 |
| 9 | **Glitch**: `emp_hit(3.0)` → `is_glitching()` es `true`, y es `false` a los 3.0 s ±0.1; todos los desplazamientos vuelven a `Vector2.ZERO`; un segundo `emp_hit` a los 1.5 s reinicia el contador a 3.0 s |
| 10 | Captura `combat_hud.png` con los 10 componentes alimentados a la vez |
| 11 | `queue_free()` + 2 frames → sin nodos huérfanos y sin conexiones colgadas a `Events` |

Ambos checks devuelven `0` solo si todas las filas pasan, imprimen una línea por fila y restauran `GameSettings.hud_config` a lo que había antes.

### 9.3 Criterios de WP-08 y WP-22

- **WP-08**: el sandbox de vuelo muestra el HUD completo; los 11 interruptores encienden y apagan lo que corresponde (`STATUS` siempre visible); el preview del menú de opciones se mueve sin dron; `hud_projection_check` verde.
- **WP-22**: los 10 componentes responden a la partida real; el `CombatHUD` sobrevive a un respawn sin perder estado ni duplicar conexiones; `combat_hud_check` verde.

## 10. Riesgos y decisiones abiertas

| # | Asunto | Estado |
|---|---|---|
| 1 | El `FlightHUD` es un `Control` hijo de un `Node3D` y se dibuja en la capa 0 del canvas. Debe quedar **fuera** de los `SubViewport` del ojo de pez FULL, o se deformaría con la imagen | resuelto, verificar en WP-06 |
| 2 | `HUDHorizon` en modo `camera` depende de `camera.project_direction`. Si el fisheye está en OFF, ese `Callable` debe seguir existiendo y devolver la proyección rectilínea | acordado con `docs/03` |
| 3 | Dos proyecciones (la de la cámara y `HUDProjection`) pueden divergir. La fila 4 del check de proyección es justamente el detector | mitigado |
| 4 | El `Reticle` hace polling del `WeaponMount` en vez de escuchar el bus: la dispersión cambia cada frame y un evento por frame sería ruido. Requiere rebind tras el respawn | resuelto |
| 5 | Presupuesto de `_draw()`: 14 `Control` redibujando cada frame. Medir en WP-29; si hace falta, los numéricos solo llaman `queue_redraw()` cuando su valor publicado cambia | abierto |
| 6 | Legibilidad del HUD sobre la ciudad al anochecer: el contorno de 4 px puede no alcanzar sobre emisivos cian. Alternativa: caja semitransparente `HUD_BOX` detrás de los números | abierto, se decide con capturas en WP-25 |
| 7 | Las firmas del bus quedaron **conciliadas** con `docs/08`/`docs/09`/`docs/06`: `hit_confirmed(position, weak, lethal)` en vez de un enum `kind`, y el EMP por la señal local `EnergySystem.emp_hit`, no por `drone_damaged`. Las tres columnas de `hit_confirmed` alcanzan para los 3 colores de hitmarker | resuelto |
| 11 | El edificio bajo asedio es **uno solo por vez** (`CityIntegrity.get_under_siege()`), no una lista: el marcador correspondiente es único y eso alivia el riesgo 8 | resuelto |
| 8 | 6 marcadores fuera de pantalla pueden saturar en fase 4. Si molesta, agrupar los edificios bajo asedio en un solo marcador con contador | abierto |
| 9 | El bloqueo de reanudación depende de detectar el `release` de la acción `pause`; con un switch en un eje analógico (radio) eso puede no llegar nunca. Respaldo: temporizador mínimo de 0.35 s | abierto |
| 12 | Claves nuevas: cada una debe existir en **es** y en **en** o el CSV falla en el check de localización de `docs/15` | acordado |

## 11. Referencias cruzadas

- `03-especificacion-nucleo-de-vuelo.md` — señales de armado, `FPVCamera`, `project_direction`, modos de ojo de pez.
- `04-especificacion-configuracion-y-menus.md` — `GameSettings.hud_config`, menús de opciones y el preview del HUD, `Controls`, navegación.
- `06-framework-de-enemigos.md` — `WeakPoint.exposed`, fases, `enemy_attack_telegraphed`.
- `08-combate-y-armas.md` — dispersión, calor, `hit_confirmed`, fijado de objetivo.
- `09-energia-y-danio.md` — `energy_changed`, `hull_changed`, `drone_damaged`, EMP, respawn.
- `10-ciudad-destructible.md` — `city_integrity_changed`, `building_destroyed(position, value)`, `get_under_siege()` y el grupo `buildings_under_siege`.
- `11-rondas-y-objetivos.md` — `RoundManager`, línea de objetivo, `ResultCard`, claves `ROUND_*`/`RESULT_*`.
- `13-identidad-visual-y-audio.md` — `UIPalette`, fuentes, `hud_theme.tres`, `fpv_overlay.gdshader`, filtro del bus `Music` al pausar.
- `15-verificacion-y-ci.md` — registro de checks y comandos.
