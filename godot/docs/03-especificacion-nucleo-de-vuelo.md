# 03 — Especificación del núcleo de vuelo (sala limpia)

> Estado: borrador v1 · Fecha: 2026-09-19 · Gobierna: WP-04, WP-05, WP-06, WP-07 · Depende de: `02-configuracion-del-proyecto.md`, `04-especificacion-configuracion-y-menus.md` · Consumido por: `08`, `09`, `12`, `13`

## 1. Objetivo y alcance

> **Nota de WP-29 (2026-09-20)**: el integrador del dron (`_integrate_forces`, 10 sub-pasos) cuesta **0,201 ms por tick** en `boss_and_city` (15,8 % del tick de 1,27 ms) y corre **dentro del paso de Jolt**, no en la fase de `_physics_process` (`PerfProbe` lo resta del hueco); `jolt_step` 0,432 ms. `flight_only` completo: 0,55 ms/tick (presupuesto 1,6). Los sub-pasos de §2.5 no se tocaron.

> **Nota de WP-28 parte B (2026-09-20)**: `CameraRig.add_trauma()` deja de ser un no-op: modelo de `docs/13` §6 (ruido simplex, caída 1,4/s, desplazamiento ∝ trauma²) compuesto sobre la inclinación del hangar y con vuelta exacta a la base; `DroneRig._feed_hud()` publica además la calidad de señal del overlay en el `FlightHUD`. La física no cambia: `flight_bench` idéntico. `LevelBase.warm_up_view()` es la única excepción conocida a «la `FPVCamera` cuelga del `CameraRig` con identidad» (gira `rotation.y` durante el calentamiento y restaura).

> **Nota de WP-28 parte A (2026-09-20)**: `drone_rig.tscn` gana el nodo `Overlay` (`FPVOverlay`, `CanvasLayer` −1) **después** del `Drone`, porque `battle_level`, `audio_check`, `energy_check`, `flight_check`, `flight_sandbox` y `weapon_check` sobrescriben al `Drone` por `index="0"` y un nodo delante les correría el índice; `DroneRig.get_overlay()`, `get_energy_system()` con respaldo por ruta `Drone/EnergySystem` (el `_ready()` del hijo corre antes que el del padre). El overlay no toca la física ni la cámara.

> **Nota de WP-27 (2026-09-20)**: `MotorAudio` se registra en el `AudioPool` como categoría `motors` (grupo `audio_motors`, `logical_voice_count()` = 4 voces lógicas) sin cambiar su mezcla; la muerte (`signal_cut`, corte de señal) y el arranque tras la reconstrucción (`power_up`, hojalata) suenan por el bus `Motors`.

> **Nota de WP-24e (2026-09-20, audio de motores)**: con el cuerpo **congelado** (`Drone.freeze`, como hace `RespawnController._begin()` y `RoundManager._freeze_drone()`), `_integrate_forces` no corre y las RPM quedan clavadas en el último valor (medido: 25 725 durante los 12 s); `MotorAudio` las trataba como régimen real y los 8 loops seguían sonando (el «sonido en loop» que reportó el usuario). Regla nueva de §6: si el dron está congelado la envolvente apunta a `SILENT_DB` (el limitador de 300 dB/s da un fundido de ~0,25 s), `_stop()` dispara solo y el retorno es automático al descongelar y armar; `enabled` no se toca. Guardianes: `audio_check` 6b y `round_check` fila 8 (silencio antes de 1 s de juego al congelar para la tarjeta).

> **Nota de WP-24c (2026-09-20)**: el ojo de pez tiene ahora **cuatro modos**: OFF, FULL, FAST y **FAST_WIDE** (`FisheyeMode.FAST_WIDE = 3`, anexado al enum). FAST ya **no** «cubre hasta ~150° con estiramiento en los bordes»: más allá de `render_fov/2` no hay imagen y el compuesto se va a **negro con viñeta** (`edge_weight = 1 − smoothstep(1−f, 1, |n|)`, `f` 0,10 horizontal y 0,02 vertical); el estiramiento era el churretón que reportó el usuario (el `clamp` del shader repetía el texel del borde en el 20 % exterior de cada costado). FAST_WIDE = frontal 16:9 de 120° + **dos caras cuadradas de 100° giradas ±60°** (lado 2/3 del alto frontal acotado a [360, 1080], MSAA ≤ 2×, LOD ≥ 4 px), compuestas por **unión con prioridad frontal** normalizada (`cover = wf + (1−wf)·ws`, `rgb = (front·wf + side·(1−wf)·ws)/cover`; el `mix` simple oscurecía la banda de fundido); cubre el cuadro entero a 16:9 y 16:10 hasta 157° de `hfov` (a 4:3 queda 4 % negro arriba y abajo; a 170° una muesca del 2 % arriba). FULL mezcla ahora las cinco caras por peso en la banda de solape (`edge_fade` 0,20) y viñetea en vez de `clamp`. Supermuestreo RGSS 4× sobre la frontal donde se minifica (`max|n| > 0,6`), porque una `ViewportTexture` no tiene mipmaps. `project_direction` usa la fórmula **equidistante analítica** en FAST, FAST_WIDE y FULL (`_project_fast` era idéntica y se borró); `FPVCamera.coverage(dir)` es el espejo GDScript del peso del shader. **Coste medido** (batalla real, HIGH, 1080p): FAST 3,09 ms de GPU / 295 fps; FAST_WIDE con el `Environment` del nivel en las laterales 7,23 ms / 133 fps / p1 47 (el coste de una viewport es **fijo**: SDFGI, niebla volumétrica y SSAO corren una vez por viewport; bajar las laterales a 540² solo ahorró 0,5 ms) → **FAST_WIDE final con `Environment` propio y barato en las laterales** (sin SDFGI/SSIL/SSAO/niebla volumétrica; cielo, tonemap, niebla de profundidad, glow y ajustes intactos): **4,19 ms / 215 fps / p1 109**, costura medida 0,0005 de luminancia; FULL 14,1 ms / 68 fps / p1 28 y 914 draw calls (fuera de presupuesto), indistinguible de FAST_WIDE a ojo (Δ 0,0011). Draw calls por cuadro: FAST +0 %, FAST_WIDE +68 %, FULL +82 % (no ×5). Presets: LOW FAST 480p, MEDIUM FAST 720p, **HIGH FAST_WIDE 1080p + laterales 720²**, ULTRA FAST_WIDE con laterales 1080² (decisión del orquestador; FULL queda en el menú; `PRESET_FISHEYE_SIDE_RATIO = [2/3, 2/3, 2/3, 1,0]`). Medido a 1080p en `boss_and_city` con la escena de la tanda 1: FAST 188 fps / p1 105 / 5,0 ms; HIGH FAST_WIDE 126 / 87 / 7,6 ms; **ULTRA FAST_WIDE 89 / 65 / 10,9 ms / 776 draw calls**, contra FULL 68 / 28 / 14,1 ms / 914. `settings_check` asevera que ningún preset use FULL y que siga siendo elegible a mano. Pendiente para WP-25: en FAST (LOW/MEDIUM) las cintas laterales del FlightHUD caen en parte sobre la viñeta; decidir si el HUD respeta `coverage()`. **Cierre (2026-09-20)**: la franja blanca del anillo exterior de FAST_WIDE era el **propio chasis del dron** visto por las caras laterales a centímetros: `Drone._collect_model_meshes()` manda ahora **todas** las mallas del modelo a la capa visual 20 (la FPV y sus sub-cámaras la excluyen con `cull_mask = 524287`; las cámaras externas no tocan `cull_mask` y siguen viendo el dron); quemado 10 % → 0,1 %, y `render_check` HIGH 109 → 132 fps (p1 87) por los draw calls ahorrados. **Trampa documentada**: asignar `CameraAttributesPhysical` a una `Camera3D` **sobrescribe su `fov`** a partir de `frustum_focal_length` (las caras pasaban de 120°/100° a 160°): las sub-cámaras del ojo de pez heredan los atributos del `WorldEnvironment` y **no deben** llevar `attributes` propios; `hud_projection_check` fila 1 (`_check_face_fovs`) lo asevera. El `Environment` barato de las laterales parte de un `duplicate()` del del nivel.

> **Nota de WP-24a (2026-09-20)**: el integrador del dron ya no asigna memoria por sub-paso: `DronePropeller.compute_forces_into()` escribe en campos preasignados (`last_thrust/last_torque/last_in_plane`; `compute_forces()` queda como envoltorio para el banco) y `Drone` llama a un `FlightController` tipado en vez de `has_method` + `call`. `flight_bench` dio la **misma salida línea por línea** (TWR, hover, escalón 80 ms / 5,47 %, 240 ms / 8,63 %, 34,22 m/s) con el coste de física 3,72 → 1,62 ms (pico por segundo, ver `docs/15` §5.1). `SUBSTEPS_ARMED` 10 → 5 se probó y se descartó: el conteo real sale de `TARGET_SUBSTEP_SECONDS` y el banco lo detecta; la ganancia no compensaba la fidelidad del lazo.

> Nota (2026-09-19): `flight_bench` fija el perfil de referencia con `ControlProfile.new()` (7/67/54) y retira `EnergySystem`/`Hull` del dron antes de medir; el banco usa `ControlProfile.new()` porque los defaults persistidos del jugador (5/30/25) no alcanzan los 360 deg/s de §11.4.

> Nota del checkpoint 2 (2026-09-19): el perfil por defecto que recibe un jugador nuevo (persistido por `QuadSettings`) es ACTUAL 5/30/25 (50 y 300 deg/s, expo 0,25), más suave que el 7/67/54 de §3.6, que sigue siendo el default del recurso `ControlProfile` y del banco de pruebas.


> **Nota de la pasada de correcciones (2026-09-19)**: valores finales del arrastre del cuerpo, simétricos en X/Z: `A = (0.016, 0.020, 0.016)` m², `Cd = (1.0, 1.2, 1.0)`, `k_J = 1.0`; con ellos `flight_bench` mide hover 0,395, TWR 5,52, respuesta de motor 68 ms, escalón de tasa 80 ms / 5,5 % de sobrepaso, escalón de ángulo 240 ms / 8,6 %, `v_max` 34,2 m/s, velocidad terminal en caída 21,6 m/s, integrador 0,37 ms/tick. TURTLE: el par inactivo queda `powered = false` (frenado con `τ_down`), la reversa llega a `−0.75·max_rpm·|stick|` (`DroneMotor.REVERSE_LIMIT`), endereza en 0,33 s. La cámara de seguimiento externa corre en `_physics_process` (la interpolación de física está apagada en el proyecto).


> **Nota de WP-06 (2026-09-19)**: la exposición no la define la cámara sino el `WorldEnvironment` del nivel, con `CameraAttributesPhysical` (f/16, 1/100 s, ISO 100, auto-exposición apagada, focal 2,1 mm para que la profundidad de campo no desenfoque las hélices): con `use_physical_light_units` y un sol de 100 000 lux, sin atributos la imagen sale blanca. §5 queda superado en la línea de `CameraAttributesPractical`. La `FPVCamera` construye en código el compuesto del ojo de pez en un `CanvasLayer` de capa −2 (bajo el HUD), con la cámara principal en `cull_mask = 0` mientras el compuesto manda (FAST cuesta +1 % de draw calls; FULL +147 %). Las sub-cámaras heredan la máscara de escena leída en `_ready`.


> **Nota de WP-04 (2026-09-19, hechos medidos)**: (1) §2.2: el par de reacción se implementa como `τ = +s·Q` (s = +1 para CW); con `−s·Q` la guiñada quedaba invertida respecto del mezclador de §3.5. (2) §2.1: los motores están donde el modelo voxel los tiene, `(∓0.085, 0.015, ∓0.085)`; manda el modelo. (3) §2.5: los sub-pasos se generalizan a `N = ceil(step / 1 ms)` (10 a 100 Hz; acotado a 40) para que el sub-paso siga siendo de 1 ms cuando un banco acelera con `Engine.time_scale`, que multiplica `state.step`. (4) §11.8: `Performance.TIME_PHYSICS_PROCESS` reporta el máximo por segundo, no una media; el criterio de coste se mide con el profiler propio de `Drone` (`start_profiling()`): 0,32 ms de media y 0,67 ms de pico por tick. (5) `FlightState.velocity` va en ejes de mundo (hay `body_velocity()`); `angular_velocity` en ejes del cuerpo; `euler`/`rates()` en convención de piloto (alabeo positivo = ala derecha abajo). (6) Las fuerzas de hélice se aplican en la posición de la hélice (2 cm sobre el motor). (7) Con `C_T 0.11`, `C_Q 0.009` e inercia propuesta: TWR 5,52 y comando de equilibrio 0,395 sin ajuste. (8) Aviso para WP-05: con el arrastre de §2.4 la velocidad máxima estimada supera los 40 m/s; WP-05 debe cumplir §11.6 ajustando `k_J`, `A_z`/`Cd_z` dentro de rangos físicos o midiendo con la inclinación que el controlador permita, y documentar el valor final.


Especificar, sin código de referencia, un cuadricóptero FPV jugable con la sensación de un simulador: cuerpo rígido con integrador propio a 100 Hz, motores y hélices con modelo físico, controlador de vuelo con modos acro/horizon, mezclador con air mode, curvas de rates estilo Betaflight, lectura de radio con calibración, cámara FPV con ojo de pez, audio de motores y LED de modo. Incluye el banco de pruebas que fija la "sensación" objetivo.

**No incluye**: arma (`08`), energía y casco (`09`), HUD (`12`), sacudida de cámara y overlay (`13`, salvo el nodo `CameraRig` que aquí se define), teclado y ratón para volar (P4).

**Regla de sala limpia**: el implementador trabaja solo con este documento y las fuentes públicas citadas en §13. Tiene libertad total sobre la estructura interna del código mientras respete la interfaz de §9 y los criterios de §11.

## 2. Modelo físico

### 2.1 Cuerpo rígido
- `Drone extends RigidBody3D`, `custom_integrator = true`, `gravity_scale = 0` (la gravedad se aplica dentro del integrador), `continuous_cd = true`, `can_sleep = false`, `contact_monitor = true`, `max_contacts_reported = 6`, capa 2, máscara 1|3|4|8|9.
- Masa `m = dry_weight + battery_weight` (defaults 0.52 + 0.18 = **0.70 kg**), leída de `QuadSettings` y actualizada en `settings_updated`.
- Inercia diagonal propuesta `I = (0.0025, 0.0045, 0.0025)` kg·m² (ejes x, y, z del cuerpo), asignada con la propiedad `inertia` del RigidBody3D. Alternativa aceptable: calcularla como 4 masas puntuales de 0.035 kg en los motores más un cuerpo central.
- Ejes del cuerpo (convención Godot): **−Z adelante, +Y arriba, +X derecha**. Brazos de 0.08 m: motores en `(∓0.08, 0, ∓0.08)`.
- Numeración y giro de motores (visto desde arriba): M1 delantero-izquierdo `(−0.08, 0, −0.08)` **CW**; M2 delantero-derecho `(+0.08, 0, −0.08)` **CCW**; M3 trasero-derecho `(+0.08, 0, +0.08)` **CW**; M4 trasero-izquierdo `(−0.08, 0, +0.08)` **CCW**.
- Colisión: `BoxShape3D` 0.22 × 0.05 × 0.22 m centrado, más una `SphereShape3D` de radio 0.02 m en cada motor (para que los choques de hélice se noten). El modelo visual llega del pipeline voxel (`05`); hasta WP-12 se usa un placeholder CSG.

### 2.2 Motores
Cada motor tiene `rpm` (actual), `rpm_target` y `powered`.
- Mapa de comando a régimen: `rpm_target = idle_rpm + cmd · (max_rpm − idle_rpm)` con `cmd ∈ [0, 1]` del mezclador; desarmado ⇒ `rpm_target = 0`.
- Dinámica de primer orden asimétrica (comportamiento público de un ESC con hélice): `rpm += (rpm_target − rpm) · (1 − e^(−dt/τ))` con `τ_up = 0.030 s` al acelerar y `τ_down = 0.060 s` al frenar.
- `max_rpm = 30 000` (motor KV 2400 en 4S bajo carga), `idle_rpm = 0.05 · max_rpm = 1 500`.
- Reversa (solo modo TURTLE): `rpm_target` negativo hasta `−0.5 · max_rpm`; el empuje en reversa vale la mitad del directo (hélice ineficiente al revés).
- Par de reacción sobre el cuerpo: `τ_reacción = −s · Q` alrededor del eje +Y del cuerpo, donde `s = +1` para giro CW y `−1` para CCW, y `Q` es el par de la hélice (2.3). Es lo que produce el yaw.

### 2.3 Hélices
Hélice 5.1" (D = **0.1295 m**), paso 4.8", 3 palas. `n = |rpm| / 60` (rev/s), `ρ = 1.225 kg/m³`.
- Empuje estático: `T₀ = C_T · ρ · n² · D⁴`; par: `Q = C_Q · ρ · n² · D⁵` (fórmulas estándar de hélices, ver §13). Valores iniciales `C_T = 0.11`, `C_Q = 0.009`, que dan ≈ 9.5 N por motor a 30 000 rpm y una relación empuje/peso ≈ 5.5 para 0.70 kg (rango objetivo 4–6; ajustar `C_T` para entrar en rango).
- Corrección por vuelo hacia delante (modelo simple, física pública): velocidad de entrada de aire a lo largo del eje de la hélice `V_a = (v_hélice · eje_empuje)` (positiva cuando el dron sube o avanza contra la hélice), relación de avance `J = V_a / (n · D)`; `T = T₀ · clamp(1 − k_J · J, 0.2, 1.2)` con `k_J = 0.6`. Al descender rápido `J < 0` y el empuje crece (hasta 1.2×). Refinamiento opcional: modelo de Gill y D'Andrea (§13) con flujo inducido.
- Fuerza en plano (arrastre de hélice): `F_h = −k_h · n · D² · v_plano` con `k_h = 0.004`, donde `v_plano` es la componente de la velocidad de la hélice perpendicular a su eje. Aporta amortiguación natural en traslación.
- Punto de aplicación: posición del motor; el momento es `r × F`.
- Efecto suelo (Cheeseman–Bennett, §13): `T_ige = T / (1 − (R / (4·z))²)` con `R = D/2` y `z` la altura de la hélice sobre el suelo medida con un `RayCast3D` hacia abajo (alcance 2 m, máscara 1|8); `z` se acota a `≥ R/2` (factor máximo 1.33); sin impacto del rayo, factor 1.

### 2.4 Arrastre del cuerpo
En ejes del cuerpo, por eje `i`: `F_i = −½ · ρ · Cd_i · A_i · |v_i| · v_i` con áreas proyectadas `A = (0.013, 0.014, 0.006)` m² y `Cd = (0.4, 1.2, 0.4)`. Amortiguación angular: `τ_i = −k_ω · |ω_i| · ω_i` con `k_ω = 0.0004` N·m·s².

### 2.5 Integración
`_integrate_forces(state)` con sub-pasos: `N = 10` si armado, `N = 1` si desarmado; `dt = state.step / N`. En cada sub-paso:
1. Actualizar el estado de vuelo (posición, base, velocidad lineal y angular en ejes del cuerpo) y ejecutar el lazo de control (§3) a 1 000 Hz.
2. Actualizar régimen de motores (2.2) y calcular fuerzas y momentos de hélices (2.3), arrastre (2.4) y gravedad `g = (0, −9.81, 0)`.
3. Euler semi-implícito: `a = ΣF/m + g`; `v += a·dt`; `p += v·dt`; `α = I⁻¹ · (Στ − ω × (I·ω))`; `ω += α·dt`; base rotada por `ω·dt` (`Basis.rotated(ω.normalized(), |ω|·dt)`) y ortonormalizada.
4. Al terminar los sub-pasos escribir `state.linear_velocity`, `state.angular_velocity` y `state.transform`.
- Los contactos los resuelve Jolt entre pasos de física; el dron detecta choques con `body_entered` y la variación de velocidad entre pasos: si `|Δv| > 6 m/s` emite `crashed(impact_speed)`.
- Con `N = 10` el tick de física del dron debe costar **< 1.6 ms** en el hardware de referencia (medido en `flight_bench`).

## 3. Controlador de vuelo

### 3.1 Entradas y estado
- `FlightCommand` (RefCounted): `throttle ∈ [0, 1]`, `roll`, `pitch`, `yaw ∈ [−1, 1]`, actualizado por `RadioController` cada frame de física.
- `FlightState` (RefCounted): `position`, `basis`, `velocity`, `angular_velocity` (ejes del cuerpo, rad/s), `euler` (roll, pitch, yaw en rad, derivados de la base con convención YXZ), `altitude_agl` (rayo hacia abajo).

### 3.2 Modos
| Modo | Clave | Comportamiento | Entrada disponible |
|---|---|---|---|
| ACRO | `"acro"` | Los sticks mandan velocidad angular objetivo (deg/s) por eje según `ControlProfile`; lazo PID de tasa; acelerador directo | siempre (modo por defecto) |
| HORIZON | `"horizon"` | Roll y pitch mandan un ángulo objetivo `θ_obj = stick · angle_limit` (35°); lazo externo proporcional `ω_obj = K_angle · (θ_obj − θ)` con `K_angle = 6.0 s⁻¹`, acotado a la tasa máxima del perfil; yaw sigue siendo tasa; acelerador directo | acción `mode_horizon` o `cycle_flight_modes` |
| TURTLE | `"turtle"` | Solo desde desarmado boca abajo (`basis.y · UP < 0`): armar manteniendo `mode_turtle`; los dos motores del lado hacia donde apunta el stick dominante (roll o pitch, umbral 0.2) giran en reversa a `−0.5 · max_rpm · |stick|`; los otros dos quedan apagados; al quedar derecho (`basis.y · UP > 0.7`) pasa a ACRO desarmado | mantener `mode_turtle` al armar |
| RECOVER | `"recover"` | Automático cuando, armado en HORIZON, `|roll|` o `|pitch|` supera 60° durante 0.3 s, o tras `crashed` con `impact_speed > 12 m/s` en cualquier modo asistido; el controlador lleva los ángulos a 0 y desciende a −3 m/s (lazo P sobre velocidad vertical, ganancia 0.08 por m/s sobre el acelerador de hover); sale al modo anterior cuando `|θ| < 10°` y `|v_y| < 1 m/s` durante 0.5 s, o desarma bajo 0.5 m AGL | automático |

En ACRO no hay recuperación automática (el piloto conserva el control total). `cycle_flight_modes` alterna ACRO ↔ HORIZON. Cada cambio emite `flight_mode_changed(mode_key)`.

### 3.3 Armado
- `arm()` tiene éxito solo si `throttle < 0.02`, el modo actual no es RECOVER y `EnergySystem` (`09`) no reporta energía agotada. Si falla emite `arm_failed(reason_key)` con `ERR_ARM_THROTTLE_HIGH`, `ERR_ARM_RECOVERING` o `ERR_ARM_NO_ENERGY`.
- Al armar: motores a `idle_rpm`, integradores a cero, `armed(mode_key)`. `disarm()`: `rpm_target = 0`, integradores a cero, `disarmed()`.
- Acciones: `toggle_arm` alterna; `arm` (mantener) arma al presionar y desarma al soltar.

### 3.4 PID
- Forma paralela por eje: `u = Kp·e + Ki·∫e·dt − Kd·d(medida)/dt` (derivada sobre la medida, filtrada con paso bajo de primer orden a 40 Hz). Integral acotada a `±0.3` (unidades de salida), salida acotada a `±1`. Anti-windup: no integrar cuando la salida está saturada en el mismo sentido del error. Reinicio de integradores al armar, desarmar y cambiar de modo.
- El lazo de tasa corre a 1 000 Hz (cada sub-paso). Ganancias iniciales (error en rad/s → fracción de comando de motor): roll y pitch `Kp 0.045, Ki 0.06, Kd 0.0009`; yaw `Kp 0.08, Ki 0.10, Kd 0`. El implementador las ajusta hasta cumplir §11.

### 3.5 Mezclador y air mode
Con acelerador `T ∈ [0, 1]` y salidas PID `r, p, y ∈ [−1, 1]` (roll positivo = ala derecha abajo; pitch positivo = morro arriba; yaw positivo = morro a la izquierda, giro CCW visto desde arriba):

```
m1 (FL, CW)  = T + r − p + y
m2 (FR, CCW) = T − r − p − y
m3 (RR, CW)  = T − r + p + y
m4 (RL, CCW) = T + r + p − y
```

Air mode (comportamiento público de Betaflight): sea `lo = min(mᵢ)`, `hi = max(mᵢ)`, `idle = 0.05`. Si `hi − lo > 1 − idle`, se escalan las desviaciones respecto de `T` por `(1 − idle)/(hi − lo)`. Luego, si `lo < idle` se desplazan todos en `idle − lo`; si `hi > 1` se desplazan en `1 − hi`. Finalmente `cmdᵢ = clamp(mᵢ, idle, 1)`. Así la autoridad de control se mantiene con el acelerador al mínimo.

### 3.6 Curvas de rates (`ControlProfile`)
Entrada: deflexión de stick `x ∈ [−1, 1]`; parámetros por eje `rc_rate`, `rate`, `expo` en unidades enteras de la documentación pública de Betaflight; salida `ω` en deg/s, acotada a `±1 998`. Sea `e = expo / 100`.

| Curva | Fórmula |
|---|---|
| ACTUAL (por defecto) | `c = rc_rate · 10`; `mx = max(0, rate · 10 − c)`; `curva = |x| · (x⁵·e + x·(1 − e))`; `ω = x·c + mx·curva` |
| BETAFLIGHT | `k = rc_rate/100`; si `k > 2`: `k += 14.54·(k − 2)`; `x' = x·|x|³·e + x·(1 − e)`; `ω = 200·k·x'`; si `rate > 0`: `ω /= clamp(1 − |x|·rate/100, 0.01, 1)` |
| RACEFLIGHT | `x' = (1 + 0.01·expo·(x² − 1))·x`; `ω = 10·rc_rate·x'·(1 + |x|·rate·0.01)` |
| KISS | `s = 1 / clamp(1 − |x|·rate/100, 0.01, 1)`; `x' = (x³·e + x·(1 − e))·rc_rate/1000`; `ω = 2000·s·x'` |
| QUICKRATES | `k = rc_rate · 2`; `mx = max(rate · 10, k)`; `sf = (mx/k − 1)/(mx/k)`; `curva = x³·e + x·(1 − e)`; `s = 1 / clamp(1 − |x|·sf, 0.01, 1)`; `ω = curva·k·s` |

Perfil por defecto: ACTUAL con `rc_rate 7`, `rate 67`, `expo 54` en los tres ejes (centro 70 deg/s, máximo 670 deg/s). El controlador normaliza el comando como `ω / ω_max` cuando necesita una entrada en `[−1, 1]` (p. ej. HORIZON) y vuelve a multiplicar por la tasa máxima del modo.

## 4. Radio (`RadioController`)
- Nodo hermano del dron en `drone_rig.tscn`, `@export var target: Drone`.
- Cada frame de física construye `FlightCommand`: si hay joypad activo, lee ejes crudos con `Controls.get_flight_input()` (`04`, aplica calibración mín/centro/máx, inversión y zona muerta 0.02 con reescalado); si no, usa las acciones del InputMap (`throttle_up/down`, `pitch_up/down`, `roll_left/right`, `yaw_left/right`). `throttle = (eje + 1)/2`: un stick centrado da 0.5, cómodo en gamepads con retorno al centro.
- Acciones (`_unhandled_input`): `toggle_arm`; `arm` (presionar arma, soltar desarma); `respawn` → `reset_requested`; `cycle_flight_modes`; `mode_horizon`; `mode_turtle` (mantenido al armar); `fire`, `fire_alt` → `fire_changed(pressed)`, `fire_alt_changed(pressed)`; `lock_target` → `lock_pressed()`; `cycle_target` → `cycle_target_pressed()`.
- Switches en ejes analógicos: para cada acción cuyo binding sea de tipo eje con banda `[axis_min, axis_max]` (`Controls.action_list`), el controlador sintetiza `InputEventAction` presionado/soltado al entrar/salir de la banda, con histéresis 0.05.
- Expone `get_left_stick() -> Vector2` (yaw, acelerador) y `get_right_stick() -> Vector2` (roll, pitch) en `[−1, 1]` para el HUD.

## 5. Cámara FPV y `CameraRig`
- Jerarquía: `Drone/CameraRig/FPVCamera`. `CameraRig` (Node3D) aplica la inclinación `rotation.x = deg_to_rad(QuadSettings.angle)` y, en P2, el desplazamiento de sacudida (`13`). Nadie más escribe la transform de la cámara.
- FOV horizontal desde `QuadSettings.fov`: 90–170° con ojo de pez; sin ojo de pez se acota a 60–120° con `keep_aspect = KEEP_WIDTH`.
- Modos de ojo de pez (`Graphics.fisheye_mode`):
  - **OFF**: `Camera3D` común.
  - **FAST**: una `SubViewport` renderizada con FOV rectilíneo 120° y un shader de pantalla completa que remapea a proyección equidistante: para cada píxel de salida a radio normalizado `r` se toma el ángulo `θ = r · fov_h/2` y se muestrea el render rectilíneo en `r' = f · tan θ` (f = distancia focal del render). Cubre hasta ~150° con estiramiento en los bordes. Coste: una viewport extra.
  - **FULL**: cinco cámaras (frente, izquierda, derecha, arriba, abajo) con FOV 100° cada una (solapadas) renderizan en cinco `SubViewport` a `Graphics.fisheye_resolution` con `Graphics.fisheye_msaa`; un `ColorRect` con `ShaderMaterial` calcula para cada píxel la dirección `d(θ, φ)` (equidistante: `θ = r · fov_h/2`) y muestrea la cara cuyo eje domina. Uniform `hfov`.
  - El compuesto se dibuja en un `CanvasLayer` propio por debajo del HUD; las sub-cámaras copian la transform global de `FPVCamera` cada frame.
- `project_direction(dir: Vector3) -> Vector2`: dirección en mundo → posición en píxeles de la viewport raíz; devuelve `Vector2(NAN, NAN)` si queda fuera del campo visual. OFF/FAST usan `unproject_position` (FAST aplica el mismo remapeo del shader); FULL lo resuelve analíticamente con `θ = ángulo(dir, adelante)`, `r = θ / (fov_h/2) · (ancho/2)`, `φ = atan2(local.y, local.x)`. Lo consumen `HUDHorizon` y los marcadores (`12`).
- `CameraAttributesPractical` con auto-exposición desactivada (exposición fija en unidades físicas, `13`).

## 6. Audio de motores
- Herramienta headless `tools/generate_motor_sounds.gd` (`godot --headless -s`) sintetiza 8 loops WAV 16 bit 44.1 kHz de 1.5 s sin costura (`idle`, `band_1..7`): suma de armónicos de la frecuencia de paso de pala (`3 · rpm/60`) con amplitud decreciente, más la fundamental del motor (`rpm/60`) y ruido filtrado; rpm por banda = `max_rpm · [0.05, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 1.0]`.
- En tiempo de ejecución, por motor: dos `AudioStreamPlayer` (no posicionales, la cámara va en el dron) en el bus `Motors`, con las dos bandas adyacentes al régimen actual; volumen `lerp(−24 dB, 0 dB, ratio)` con curva exponencial, `pitch_scale = rpm / rpm_banda` acotado a `[0.8, 1.25]`; por debajo de `idle_rpm` se desvanece a −80 dB. Máximo 8 reproductores.

## 7. LED y modelo
- `ModeLED` (Node3D con material emisivo): cian en ACRO, verde en HORIZON, magenta en TURTLE, rojo en RECOVER; desarmado parpadea lento (0.5 s); fallo de armado parpadea rápido tres veces.
- Modelo: `assets/drone/drone_quad.glb` del pipeline voxel (`05`) con partes `frame`, `motor_1..4`, `prop_1..4`, `prop_disk_1..4`. Las hélices giran visualmente según `rpm` (con tope visual de 20 rev/s) y los discos de desenfoque aparecen con el régimen. Hasta WP-12, placeholder CSG con las mismas rutas de nodo.

## 8. Escena `drone_rig.tscn`
```
DroneRig (Node3D, drone_rig.gd)
├── Drone (RigidBody3D, drone.gd)
│   ├── CollisionShape3D (+ 4 esferas de motor)
│   ├── Model (instancia del GLB o placeholder)
│   ├── ModeLED (mode_led.gd)
│   ├── Motors/Motor1..4 (Node3D, motor.gd) → Propeller (Node3D, propeller.gd) + GroundRay (RayCast3D)
│   ├── FlightController (Node, flight_controller.gd)
│   ├── CameraRig (Node3D, camera_rig.gd) → FPVCamera (Camera3D, fpv_camera.gd)
│   ├── WeaponMount (08) · EnergySystem (09) · Hull (09)
│   └── MotorAudio (Node, motor_audio.gd)
├── FlightHUD (12)
└── RadioController (Node, radio_controller.gd)
```
`drone_rig.gd` cablea: radio → controlador; señales del controlador → HUD; `QuadSettings.settings_updated` → masa, inclinación de cámara, FOV y perfil de control; el punto de reaparición del nivel → `Drone.respawn_point` y `Drone.reset_to()`.

## 9. Interfaz pública

```gdscript
class_name Drone extends RigidBody3D
signal armed(mode_key: String)
signal disarmed()
signal arm_failed(reason_key: String)
signal flight_mode_changed(mode_key: String)
signal respawned()
signal crashed(impact_speed: float)
@export var respawn_point: Node3D               # lo cablea el nivel; lo leen DroneRig y RespawnController (09)
func reset_to(xform: Transform3D) -> void      # detiene, teletransporta, reinicia el controlador, emite respawned
func is_armed() -> bool
func get_throttle() -> float                    # 0..1 del último FlightCommand
func force_disarm() -> void                     # usado por EnergySystem
func set_thrust_scale(scale: float) -> void     # 1.0 normal; 0.82 con energía crítica
func get_flight_state() -> FlightState
func get_motor_rpm() -> Array[float]           # 4 valores
func get_stick_input() -> Array[Vector2]       # [izquierdo, derecho]
func get_mode_key() -> String

class_name FlightController extends Node
func select_mode(mode_key: String) -> void
func cycle_mode() -> void
func arm() -> bool
func disarm() -> void
func set_control_profile(profile: ControlProfile) -> void
func update_command(cmd: FlightCommand) -> void
func integrate(dt: float, state: FlightState) -> Array[float]   # devuelve cmd de los 4 motores en [0,1] (o negativo en TURTLE)

class_name ControlProfile extends Resource
@export var curve: int                          # 0 ACTUAL, 1 BETAFLIGHT, 2 RACEFLIGHT, 3 KISS, 4 QUICKRATES
@export var rc_rate: Vector3; @export var rate: Vector3; @export var expo: Vector3   # x=roll, y=pitch, z=yaw
func get_rate(axis: int, x: float) -> float     # deg/s
func get_max_rate(axis: int) -> float
func get_normalized(axis: int, x: float) -> float

class_name RadioController extends Node
signal reset_requested()
signal fire_changed(pressed: bool)
signal fire_alt_changed(pressed: bool)
signal lock_pressed()
signal cycle_target_pressed()
func get_left_stick() -> Vector2
func get_right_stick() -> Vector2

class_name FPVCamera extends Camera3D
func project_direction(dir: Vector3) -> Vector2
func set_fisheye_mode(mode: int) -> void
func set_horizontal_fov(fov_h: float) -> void

class_name CameraRig extends Node3D
func set_tilt_degrees(angle: float) -> void
func add_trauma(amount: float) -> void          # implementado en 13; aquí es un no-op con la firma fija
```

## 10. Parámetros y valores iniciales

| Parámetro | Unidad | Valor | Rango / nota |
|---|---|---|---|
| `dry_weight` / `battery_weight` | kg | 0.52 / 0.18 | 0.1–1.0 / 0.1–0.5 (`QuadSettings`) |
| `inertia` | kg·m² | (0.0025, 0.0045, 0.0025) | propuesta |
| Brazo (distancia motor–centro por eje) | m | 0.08 | |
| `max_rpm` / `idle_rpm` | rpm | 30 000 / 1 500 | |
| `τ_up` / `τ_down` | s | 0.030 / 0.060 | |
| `D` / palas | m / — | 0.1295 / 3 | 5.1" × 4.8" |
| `C_T` / `C_Q` | — | 0.11 / 0.009 | ajustar para TWR 4–6 |
| `k_J` / `k_h` | — | 0.6 / 0.004 | |
| `A` / `Cd` | m² / — | (0.013, 0.014, 0.006) / (0.4, 1.2, 0.4) | |
| `k_ω` | N·m·s² | 0.0004 | |
| Sub-pasos armado / desarmado | — | 10 / 1 | física 100 Hz |
| `angle_limit` (HORIZON) | deg | 35 | |
| `K_angle` | s⁻¹ | 6.0 | |
| Ganancias PID roll/pitch | — | 0.045 / 0.06 / 0.0009 | iniciales |
| Ganancias PID yaw | — | 0.08 / 0.10 / 0 | iniciales |
| Filtro D | Hz | 40 | |
| Límite integral / salida | — | ±0.3 / ±1 | |
| `idle` del mezclador | — | 0.05 | |
| Tasa máxima absoluta | deg/s | 1 998 | |
| Perfil por defecto | — | ACTUAL 7 / 67 / 54 | 70 y 670 deg/s |
| Umbral `crashed` | m/s | 6 | |
| RECOVER: umbral ángulo / tiempo | deg / s | 60 / 0.3 | |
| Inclinación cámara / FOV | deg | 25 / 150 | −20..80 / 90–170 |
| FOV sub-cámaras FULL / render FAST | deg | 100 / 120 | |

## 11. Criterios de aceptación y checks headless

### `tools/flight_bench.tscn` (WP-04, se completa en WP-05)
Escena mínima con suelo y dron, sin HUD, `Engine.physics_ticks_per_second = 100`. Mide y falla si no se cumple:
1. **Hover**: con un controlador de prueba de altitud (solo del check), el acelerador de equilibrio queda en `[0.35, 0.55]` y la suma de empujes iguala `m·g` ±3 %.
2. **Relación empuje/peso**: a `cmd = 1` en los 4 motores, `ΣT / (m·g) ∈ [4, 6]`.
3. **Respuesta de motor**: de idle a 90 % de `max_rpm` en < 0.12 s.
4. **Escalón de tasa (ACRO)**: comando de 360 deg/s en roll; la tasa medida alcanza el 90 % en < 150 ms y el sobrepaso es < 15 %.
5. **Escalón de ángulo (HORIZON)**: 30° de roll; se asienta (±2°) en < 1.0 s con sobrepaso < 15 %.
6. **Velocidad máxima**: vuelo nivelado a acelerador máximo en HORIZON con inclinación libre en ACRO: `v_max ∈ [25, 40] m/s` alcanzada en < 6 s.
7. **Estabilidad numérica**: 60 s de vuelo con entradas aleatorias sin NaN ni |v| > 80 m/s.
8. **Coste**: media de `Performance.TIME_PHYSICS_PROCESS` < 1.6 ms con el dron armado.

### `tools/flight_check.tscn` (WP-05…07)
1. Armar con acelerador alto falla con `ERR_ARM_THROTTLE_HIGH`; con acelerador bajo emite `armed("acro")`.
2. Con el controlador de prueba, flota 5 s dentro de ±0.3 m de la altura objetivo.
3. `cycle_flight_modes` emite `flight_mode_changed("horizon")` y vuelve a `"acro"`.
4. Volcado boca abajo en el suelo: TURTLE endereza el dron en < 3 s.
5. `reset_requested` → `respawned` y la transform coincide con `respawn_point`.
6. Cámara: `project_direction(−basis.z)` cae en el centro de la pantalla ±2 px en los tres modos de ojo de pez; ningún NaN en un barrido de 360° de direcciones (`hud_projection_check`).
7. Audio: 8 reproductores en el bus `Motors`; el volumen sube con el régimen; sin clics en el crossfade (varianza de amplitud entre bandas < 6 dB).

Comando: `"C:/Users/Mauri/Godot/Godot_4.7/Godot_v4.7-stable_win64_console.exe" --headless --path godot res://tools/flight_bench.tscn` (ídem `flight_check`).

## 12. Riesgos y decisiones abiertas
- La sensación final depende de la sintonía PID y de `C_T`; el banco fija rangos, no valores exactos. El usuario valida con su radio en el checkpoint 2.
- El modelo de hélice simple puede sentirse "flotante" a alta velocidad; si ocurre, activar el refinamiento de Gill y D'Andrea.
- FULL ojo de pez multiplica draw calls por 5: FAST es el modo por defecto del juego (`13`).
- Cuando la energía es crítica, `set_thrust_scale` reduce `max_rpm` efectivo; verificar que HORIZON siga estable con 82 % de empuje.

## 13. Referencias públicas
- Cheeseman, I. C. y Bennett, W. E., *The Effect of the Ground on a Helicopter Rotor in Forward Flight*, ARC R&M 3021 (1955): fórmula de efecto suelo.
- Gill, R. y D'Andrea, R., *Propeller Thrust and Drag in Forward Flight*, IEEE CCTA (2017): modelo de hélice en vuelo hacia delante (refinamiento opcional).
- Coeficientes de hélice `C_T`, `C_Q` y relación de avance: teoría estándar de hélices (p. ej. McCormick, *Aerodynamics, Aeronautics and Flight Mechanics*).
- Documentación pública de Betaflight: *Rates* (curvas ACTUAL, Betaflight, RaceFlight, KISS, QuickRates) y *Air Mode*.
- Documentación de Godot 4.7: `RigidBody3D` (`custom_integrator`, `_integrate_forces`, `PhysicsDirectBodyState3D`), `SubViewport`, `Camera3D.unproject_position`, `AudioStreamWAV`.
